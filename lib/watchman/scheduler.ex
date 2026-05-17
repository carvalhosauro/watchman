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

  # --- teardown ---

  def teardown do
    IO.puts("")

    systemd_removed = teardown_systemd()
    cron_removed = teardown_cron()

    if systemd_removed or cron_removed do
      IO.puts("\n  Schedule removed.")
    else
      IO.puts("  No active schedule found.")
    end
  end

  defp teardown_systemd do
    home = System.get_env("HOME") || "~"
    unit_dir = Path.join(home, ".config/systemd/user")
    timer_path = Path.join(unit_dir, "watchman.timer")
    service_path = Path.join(unit_dir, "watchman.service")

    if File.exists?(timer_path) do
      System.cmd("systemctl", ["--user", "disable", "--now", "watchman.timer"], stderr_to_stdout: true)
      File.rm(timer_path)
      File.rm(service_path)
      System.cmd("systemctl", ["--user", "daemon-reload"], stderr_to_stdout: true)
      IO.puts("  Removed systemd timer and service")
      true
    else
      false
    end
  end

  defp teardown_cron do
    case System.cmd("crontab", ["-l"], stderr_to_stdout: true) do
      {content, 0} ->
        if String.contains?(content, "watchman") do
          cleaned =
            content
            |> String.split("\n")
            |> Enum.reject(&String.contains?(&1, "watchman"))
            |> Enum.join("\n")
            |> String.trim()

          tmp = Path.join(System.tmp_dir!(), "watchman_crontab")

          if cleaned == "" do
            System.cmd("crontab", ["-r"], stderr_to_stdout: true)
          else
            File.write!(tmp, cleaned <> "\n")
            System.cmd("crontab", [tmp], stderr_to_stdout: true)
            File.rm(tmp)
          end

          IO.puts("  Removed cron entry")
          true
        else
          false
        end

      _ ->
        false
    end
  end

  # --- status ---

  def status do
    IO.puts("")
    systemd_status()
    cron_status()
    last_run_status()
  end

  defp systemd_status do
    home = System.get_env("HOME") || "~"
    timer_path = Path.join([home, ".config/systemd/user", "watchman.timer"])

    if File.exists?(timer_path) do
      case System.cmd("systemctl", ["--user", "is-active", "watchman.timer"], stderr_to_stdout: true) do
        {status, _} ->
          IO.puts("  systemd timer: #{String.trim(status)}")
      end

      case System.cmd("systemctl", ["--user", "show", "watchman.timer", "--property=NextElapseUSecRealtime"], stderr_to_stdout: true) do
        {next, 0} ->
          IO.puts("  Next run: #{String.trim(next) |> String.replace("NextElapseUSecRealtime=", "")}")
        _ -> :ok
      end

      # Last service run result
      case System.cmd("systemctl", ["--user", "show", "watchman.service",
             "--property=ExecMainStatus", "--property=ExecMainStartTimestamp"],
             stderr_to_stdout: true) do
        {output, 0} ->
          lines = String.split(output, "\n", trim: true)
          for line <- lines do
            cond do
              String.starts_with?(line, "ExecMainStartTimestamp=") ->
                ts = String.replace(line, "ExecMainStartTimestamp=", "")
                if ts != "", do: IO.puts("  Last run: #{ts}")
              String.starts_with?(line, "ExecMainStatus=") ->
                code = String.replace(line, "ExecMainStatus=", "")
                result = if code == "0", do: "success", else: "exit code #{code}"
                IO.puts("  Last result: #{result}")
              true -> :ok
            end
          end
        _ -> :ok
      end
    end
  end

  defp cron_status do
    case System.cmd("crontab", ["-l"], stderr_to_stdout: true) do
      {content, 0} ->
        content
        |> String.split("\n")
        |> Enum.filter(&String.contains?(&1, "watchman"))
        |> Enum.each(fn line -> IO.puts("  cron: #{line}") end)

      _ -> :ok
    end
  end

  defp last_run_status do
    import Ecto.Query
    alias Watchman.{Repo, Models.Analysis, Models.Asset}

    case Repo.one(from a in Analysis, order_by: [desc: a.analyzed_at], limit: 1,
           join: asset in Asset, on: a.asset_id == asset.id,
           select: %{analyzed_at: a.analyzed_at, count: over(count(a.id))}) do
      nil ->
        IO.puts("\n  No analyses found yet. Run: wm run")
      result ->
        today = Date.utc_today()
        date = DateTime.to_date(result.analyzed_at)
        day_label = cond do
          date == today -> "today"
          date == Date.add(today, -1) -> "yesterday"
          true -> to_string(date)
        end

        # Count today's analyses
        start_dt = DateTime.new!(today, ~T[00:00:00], "Etc/UTC")
        today_count = Repo.one(from a in Analysis, where: a.analyzed_at >= ^start_dt, select: count(a.id))

        IO.puts("\n  Last analysis: #{day_label} at #{Calendar.strftime(result.analyzed_at, "%H:%M")}")
        IO.puts("  Today's analyses: #{today_count}")
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
