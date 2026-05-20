defmodule Watchman.Analysis.SignalFormatter do
  @moduledoc """
  Formats a `%Signal{}` into a plain-text string for the AI-less mode.

  Used by the pipeline when no AI provider is configured. The formatted
  string is stored in the `justification` column of the `analyses` table.
  The pipeline records this case as `tokens_used: 0, cost_usd: 0.0`.

  This module is pure: no DB, no HTTP, no Process state, no side effects.

  ## Format

  For any level other than `:noise`:

      HIGH BEARISH signal (confidence 0.75)
      Reasons:
      - Price is 2.3σ below 21-day average
      - 3 consecutive down days

  For `:noise`:

      NOISE — no actionable signal.
  """

  alias Watchman.Analysis.Signal

  @doc """
  Formats a `%Signal{}` as a plain-text string.

  Returns `"NOISE — no actionable signal."` for `:noise` level signals.
  For all other levels, returns a multi-line string with level, direction,
  confidence, and a bulleted reasons block.
  """
  @spec format(Signal.t()) :: String.t()
  def format(%Signal{level: :noise}), do: "NOISE — no actionable signal."

  def format(%Signal{
        level: level,
        direction: direction,
        reasons: reasons,
        confidence: confidence
      }) do
    level_str = level |> Atom.to_string() |> String.upcase()
    direction_str = direction |> Atom.to_string() |> String.upcase()
    confidence_str = confidence |> Float.round(2) |> to_string()
    reasons_str = Enum.map_join(reasons, "\n", &"- #{&1}")

    "#{level_str} #{direction_str} signal (confidence #{confidence_str})\nReasons:\n#{reasons_str}"
  end
end
