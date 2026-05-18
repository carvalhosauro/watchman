defmodule Watchman.Market.BrapiUsage do
  @moduledoc "Tracks Brapi API usage for free-tier awareness."

  @monthly_limit 60
  @warning_threshold 0.8
  @usage_file "brapi_usage.json"

  def usage_path do
    data_dir =
      System.get_env("WATCHMAN_DATA_DIR") ||
        Path.join([System.get_env("HOME") || "~", ".local", "share", "watchman"])

    Path.join(data_dir, @usage_file)
  end

  def record_call do
    usage = read_usage()
    current_month = Calendar.strftime(Date.utc_today(), "%Y-%m")

    updated =
      if usage["month"] == current_month do
        %{usage | "count" => usage["count"] + 1}
      else
        %{"month" => current_month, "count" => 1}
      end

    write_usage(updated)
    updated
  end

  def check_limit do
    usage = read_usage()
    current_month = Calendar.strftime(Date.utc_today(), "%Y-%m")

    count = if usage["month"] == current_month, do: usage["count"], else: 0

    cond do
      count >= @monthly_limit -> {:exceeded, count, @monthly_limit}
      count >= @monthly_limit * @warning_threshold -> {:warning, count, @monthly_limit}
      true -> {:ok, count, @monthly_limit}
    end
  end

  defp read_usage do
    case File.read(usage_path()) do
      {:ok, content} ->
        case Jason.decode(content) do
          {:ok, data} -> data
          _ -> %{"month" => "", "count" => 0}
        end

      _ ->
        %{"month" => "", "count" => 0}
    end
  end

  defp write_usage(data) do
    path = usage_path()
    File.mkdir_p!(Path.dirname(path))
    File.write!(path, Jason.encode!(data))
  end
end
