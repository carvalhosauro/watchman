defmodule Watchman.Credentials do
  @moduledoc "System keyring interface for secure credential storage."

  @service "watchman"

  @doc "Get a credential by key. Returns nil if not found."
  def get(key) when is_atom(key) do
    get(Atom.to_string(key))
  end

  def get(key) when is_binary(key) do
    case os_type() do
      :linux -> linux_get(key)
      :macos -> macos_get(key)
      :unsupported -> nil
    end
  end

  @doc "Store a credential in the system keyring. Returns :ok or {:error, reason}."
  def put(key, value) when is_atom(key) do
    put(Atom.to_string(key), value)
  end

  def put(key, value) when is_binary(key) and is_binary(value) do
    case os_type() do
      :linux -> linux_put(key, value)
      :macos -> macos_put(key, value)
      :unsupported -> {:error, :unsupported_platform}
    end
  end

  @doc "Delete a credential from the system keyring."
  def delete(key) when is_atom(key) do
    delete(Atom.to_string(key))
  end

  def delete(key) when is_binary(key) do
    case os_type() do
      :linux -> linux_delete(key)
      :macos -> macos_delete(key)
      :unsupported -> {:error, :unsupported_platform}
    end
  end

  @doc "Check if system keyring is available."
  def available? do
    case os_type() do
      :linux -> command_exists?("secret-tool")
      :macos -> true
      :unsupported -> false
    end
  end

  # Linux — libsecret via secret-tool

  defp linux_get(key) do
    case System.cmd("secret-tool", ["lookup", "service", @service, "key", key],
           stderr_to_stdout: true
         ) do
      {value, 0} ->
        trimmed = String.trim(value)
        if trimmed == "", do: nil, else: trimmed

      _ ->
        nil
    end
  rescue
    _ -> nil
  end

  defp linux_put(key, value) do
    port =
      Port.open(
        {:spawn_executable, System.find_executable("secret-tool")},
        [
          :binary,
          :exit_status,
          args: [
            "store",
            "--label",
            "watchman: #{key}",
            "service",
            @service,
            "key",
            key
          ]
        ]
      )

    Port.command(port, value)
    Port.command(port, "")
    Port.close(port)

    # Give secret-tool time to process
    Process.sleep(100)
    :ok
  rescue
    e -> {:error, Exception.message(e)}
  end

  defp linux_delete(key) do
    case System.cmd("secret-tool", ["clear", "service", @service, "key", key],
           stderr_to_stdout: true
         ) do
      {_, 0} -> :ok
      {err, _} -> {:error, err}
    end
  rescue
    e -> {:error, Exception.message(e)}
  end

  # macOS — Keychain via security

  defp macos_get(key) do
    case System.cmd(
           "security",
           [
             "find-generic-password",
             "-a",
             @service,
             "-s",
             key,
             "-w"
           ],
           stderr_to_stdout: true
         ) do
      {value, 0} ->
        trimmed = String.trim(value)
        if trimmed == "", do: nil, else: trimmed

      _ ->
        nil
    end
  rescue
    _ -> nil
  end

  defp macos_put(key, value) do
    # -U flag updates if exists
    case System.cmd(
           "security",
           [
             "add-generic-password",
             "-a",
             @service,
             "-s",
             key,
             "-w",
             value,
             "-U"
           ],
           stderr_to_stdout: true
         ) do
      {_, 0} -> :ok
      {err, _} -> {:error, err}
    end
  rescue
    e -> {:error, Exception.message(e)}
  end

  defp macos_delete(key) do
    case System.cmd(
           "security",
           [
             "delete-generic-password",
             "-a",
             @service,
             "-s",
             key
           ],
           stderr_to_stdout: true
         ) do
      {_, 0} -> :ok
      {err, _} -> {:error, err}
    end
  rescue
    e -> {:error, Exception.message(e)}
  end

  # Helpers

  defp os_type do
    case :os.type() do
      {:unix, :linux} -> :linux
      {:unix, :darwin} -> :macos
      _ -> :unsupported
    end
  end

  defp command_exists?(cmd) do
    System.find_executable(cmd) != nil
  end
end
