defmodule Watchman.Scheduler do
  @install_dir System.get_env("WATCHMAN_INSTALL_DIR") ||
                 Path.join([System.get_env("HOME") || "~", ".local", "share", "watchman"])

  def setup do
    IO.puts("""

    Schedule daily analysis
    =======================
    """)

    case detect_init_system() do
      :systemd ->
        IO.puts("  Detected: systemd\n")
        IO.puts("  [1] systemd timer (recommended)")
        IO.puts("  [2] crontab")

        case prompt("Choose [1-2]", "1") do
          "1" -> setup_systemd()
          "2" -> setup_cron()
          _ -> setup_systemd()
        end

      _ ->
        IO.puts("  Detected: cron\n")
        setup_cron()
    end
  end

  # --- systemd ---

  defp setup_systemd do
    time = prompt("  Run at (HH:MM)", "08:00")
    home = System.get_env("HOME") || "~"
    wm_path = Path.join(@install_dir, "bin/wm")

    unit_dir = Path.join(home, ".config/systemd/user")
    File.mkdir_p!(unit_dir)

    service_content = """
    [Unit]
    Description=Watchman daily asset analysis
    After=network-online.target
    Wants=network-online.target

    [Service]
    Type=oneshot
    ExecStart=#{wm_path} run
    WorkingDirectory=#{@install_dir}
    Environment="HOME=#{home}"
    Environment="PATH=#{System.get_env("PATH")}"
    Environment="MIX_ENV=prod"
    StandardOutput=journal
    StandardError=journal

    [Install]
    WantedBy=default.target
    """

    timer_content = """
    [Unit]
    Description=Run Watchman daily at #{time}

    [Timer]
    OnCalendar=*-*-* #{time}:00
    Persistent=true
    RandomizedDelaySec=300

    [Install]
    WantedBy=timers.target
    """

    service_path = Path.join(unit_dir, "watchman.service")
    timer_path = Path.join(unit_dir, "watchman.timer")

    File.write!(service_path, service_content)
    File.write!(timer_path, timer_content)

    IO.puts("\n  Created:")
    IO.puts("    #{service_path}")
    IO.puts("    #{timer_path}")

    IO.puts("\n  Enable with:")
    IO.puts("    systemctl --user daemon-reload")
    IO.puts("    systemctl --user enable --now watchman.timer")
    IO.puts("\n  Check status:")
    IO.puts("    systemctl --user status watchman.timer")
    IO.puts("    journalctl --user -u watchman.service")

    case prompt("\n  Enable timer now? [Y/n]", "Y") do
      answer when answer in ["Y", "y", ""] ->
        {_, _} = System.cmd("systemctl", ["--user", "daemon-reload"], stderr_to_stdout: true)

        case System.cmd("systemctl", ["--user", "enable", "--now", "watchman.timer"],
               stderr_to_stdout: true
             ) do
          {_, 0} -> IO.puts("\n  Timer enabled! Watchman will run daily at #{time}.")
          {err, _} -> IO.puts("\n  Failed to enable: #{err}\n  Enable manually with the commands above.")
        end

      _ ->
        IO.puts("\n  Skipped. Enable manually with the commands above.")
    end
  end

  # --- cron ---

  defp setup_cron do
    time = prompt("  Run at (HH:MM)", "08:00")

    [hour, minute] = String.split(time, ":")
    wm_path = Path.join(@install_dir, "bin/wm")
    log_path = Path.join([System.get_env("HOME") || "~", ".local", "share", "watchman", "logs", "cron.log"])

    cron_line = "#{minute} #{hour} * * * cd #{@install_dir} && #{wm_path} run >> #{log_path} 2>&1"

    IO.puts("\n  Cron entry:\n")
    IO.puts("    #{cron_line}")

    case prompt("\n  Add to crontab now? [Y/n]", "Y") do
      answer when answer in ["Y", "y", ""] ->
        install_cron(cron_line)

      _ ->
        IO.puts("\n  Skipped. Add manually: crontab -e")
    end
  end

  defp install_cron(new_line) do
    existing =
      case System.cmd("crontab", ["-l"], stderr_to_stdout: true) do
        {content, 0} -> content
        _ -> ""
      end

    # Remove any existing watchman entry
    cleaned =
      existing
      |> String.split("\n")
      |> Enum.reject(&String.contains?(&1, "watchman"))
      |> Enum.join("\n")
      |> String.trim()

    updated = if cleaned == "", do: new_line <> "\n", else: cleaned <> "\n" <> new_line <> "\n"

    # Write via temp file
    tmp = Path.join(System.tmp_dir!(), "watchman_crontab")
    File.write!(tmp, updated)

    case System.cmd("crontab", [tmp], stderr_to_stdout: true) do
      {_, 0} ->
        File.rm(tmp)
        IO.puts("\n  Crontab updated! Watchman will run daily.")

      {err, _} ->
        File.rm(tmp)
        IO.puts("\n  Failed: #{err}\n  Add manually: crontab -e")
    end
  end

  # --- helpers ---

  defp detect_init_system do
    case System.cmd("systemctl", ["--version"], stderr_to_stdout: true) do
      {_, 0} -> :systemd
      _ -> :other
    end
  rescue
    _ -> :other
  end

  defp prompt(label, default) do
    result = IO.gets("#{label} [#{default}]: ") |> String.trim()
    if result == "", do: default, else: result
  end
end
