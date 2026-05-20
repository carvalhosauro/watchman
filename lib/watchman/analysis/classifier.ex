defmodule Watchman.Analysis.Classifier do
  @moduledoc """
  Pure deterministic rule engine that produces a `%Signal{}` from technical
  indicators and news items.

  Takes an `%Indicators{}` (Track 2) and a list of `%NewsItem{}`s (Track 3)
  and returns a `%Signal{}` with `level`, `direction`, `reasons`, and
  `confidence`.

  ## Rule evaluation

  Rules are declared as `%Rule{}` structs returned by `default_rules/0` and
  exposed via `rules/0`. The engine:

    1. Walks all rules; collects every substantive rule (priority 1–8) whose
       predicate fires.
    2. If no substantive rule fires → returns a `:noise` signal immediately.
    3. Picks the highest-severity level (`high > medium > low`).
    4. Resolves direction from the highest-level firing rules.
    5. Builds the reasons list from **all** firing substantive rules ordered
       by priority.
    6. Computes `confidence = matched / total_conditions`, capped at 1.0.

  ## Direction resolution

    * All top-level firing rules agree → that direction.
    * Bullish + bearish both present at the top level → `:neutral`.
    * Only `:derived` direction rules at top level → resolve each via
      `zscore21` sign (positive = bullish, negative = bearish, zero = neutral).

  ## Confidence counting convention

  `@total_conditions` counts the **leaf atomic boolean predicates** across
  rules 1–8. Each AND/OR operand is one leaf. A rule firing because of a
  compound OR still counts as **one** matched condition regardless of which
  branch triggered it. The noise fallback (rule 9) has zero atomic predicates
  and is excluded from both numerator and denominator.

  Leaf counts per rule:

    * Rule 1 — `abs(z) > 2.0 AND streak.dir == :down AND days >= 3` → **3**
    * Rule 2 — `abs(z) > 2.0 AND streak.dir == :up AND days >= 3` → **3**
    * Rule 3 — category in `["material_fact", "financial_result"]` → **1**
    * Rule 4 — `z < -1.5 OR (dir == :down AND days >= 2)` → **3**
    * Rule 5 — `z > 1.5 OR (dir == :up AND days >= 2)` → **3**
    * Rule 6 — `length(news) >= 2` → **1**
    * Rule 7 — `abs(z) >= 0.5 AND abs(z) <= 1.5` → **2**
    * Rule 8 — `length(news) == 1` → **1**
    * Rule 9 — trivially-true fallback → **0**

  Total: `@total_conditions = 17`.

  `matched_conditions` = count of substantive rules (1–8) that fired.
  Maximum natural confidence = `8 / 17 ≈ 0.47`; the `min/2` cap guards
  against future rule additions that could push the ratio above 1.0.

  ## Implementation note

  Elixir cannot escape anonymous functions from module attributes into function
  bodies, so the rule structs are defined in private functions rather than a
  `@rules` module attribute. This preserves the data-struct approach (rules are
  `%Rule{}` values, not nested conditionals) while respecting the runtime
  boundary.

  ## Configuration override

  `rules/0` reads `Application.get_env(:watchman, :classifier_rules)` so
  tests and experiments can inject a custom rule set without recompilation.
  When the env key is absent, `default_rules/0` is called.
  """

  alias Watchman.Analysis.Classifier.Rule
  alias Watchman.Analysis.{Indicators, Signal}
  alias Watchman.Models.NewsItem

  @total_conditions 17

  @level_priority %{high: 1, medium: 2, low: 3, noise: 4}

  @doc """
  Returns the ordered list of classifier rules (priority 1 = highest).

  Override the default rule set via:
  `Application.put_env(:watchman, :classifier_rules, my_rules)`
  """
  @spec rules() :: [Rule.t()]
  def rules do
    Application.get_env(:watchman, :classifier_rules, default_rules())
  end

  @doc """
  Returns the total count of atomic boolean predicates across rules 1–8.

  Used as the denominator in the confidence formula. See `@moduledoc` for
  the counting convention.
  """
  @spec total_conditions() :: pos_integer()
  def total_conditions, do: @total_conditions

  @doc """
  Classifies an asset state into a `%Signal{}`.

  Evaluates all rules in priority order against `indicators` and
  `news_items`. Never raises — always returns a `%Signal{}`.
  """
  @spec classify(Indicators.t(), [NewsItem.t()]) :: Signal.t()
  def classify(%Indicators{} = indicators, news_items) do
    substantive = Enum.reject(rules(), &(&1.level == :noise))
    firing = Enum.filter(substantive, & &1.predicate.(indicators, news_items))

    if Enum.empty?(firing) do
      %Signal{level: :noise, direction: :neutral, reasons: [], confidence: 0.0}
    else
      build_signal(firing, indicators, news_items)
    end
  end

  # ---------------------------------------------------------------------------
  # Private — rule set (split by level to keep cyclomatic complexity in check)
  # ---------------------------------------------------------------------------

  defp default_rules do
    high_priority_rules() ++ medium_priority_rules() ++ low_and_noise_rules()
  end

  defp high_priority_rules do
    [
      %Rule{
        id: :high_bearish_zscore_streak,
        priority: 1,
        level: :high,
        direction: :bearish,
        predicate: fn %Indicators{zscore21: z, streak: s}, _news ->
          abs(z) > 2.0 and s.direction == :down and s.days >= 3
        end,
        reason: fn %Indicators{zscore21: z, streak: s}, _news ->
          "Price is #{Float.round(abs(z), 1)}σ below 21-day average; #{s.days} consecutive down days"
        end
      },
      %Rule{
        id: :high_bullish_zscore_streak,
        priority: 2,
        level: :high,
        direction: :bullish,
        predicate: fn %Indicators{zscore21: z, streak: s}, _news ->
          abs(z) > 2.0 and s.direction == :up and s.days >= 3
        end,
        reason: fn %Indicators{zscore21: z, streak: s}, _news ->
          "Price is #{Float.round(abs(z), 1)}σ above 21-day average; #{s.days} consecutive up days"
        end
      },
      %Rule{
        id: :high_material_news,
        priority: 3,
        level: :high,
        direction: :derived,
        predicate: fn _indicators, news ->
          Enum.any?(news, &(&1.category in ["material_fact", "financial_result"]))
        end,
        reason: fn _indicators, news ->
          item = Enum.find(news, &(&1.category in ["material_fact", "financial_result"]))
          "Material fact disclosed by #{String.upcase(item.source)}: #{item.title}"
        end
      }
    ]
  end

  defp medium_priority_rules do
    [
      %Rule{
        id: :medium_bearish_zscore_or_streak,
        priority: 4,
        level: :medium,
        direction: :bearish,
        predicate: fn %Indicators{zscore21: z, streak: s}, _news ->
          z < -1.5 or (s.direction == :down and s.days >= 2)
        end,
        reason: fn %Indicators{zscore21: z, streak: s}, _news ->
          medium_bearish_reason(z, s)
        end
      },
      %Rule{
        id: :medium_bullish_zscore_or_streak,
        priority: 5,
        level: :medium,
        direction: :bullish,
        predicate: fn %Indicators{zscore21: z, streak: s}, _news ->
          z > 1.5 or (s.direction == :up and s.days >= 2)
        end,
        reason: fn %Indicators{zscore21: z, streak: s}, _news ->
          medium_bullish_reason(z, s)
        end
      },
      %Rule{
        id: :medium_news_volume,
        priority: 6,
        level: :medium,
        direction: :derived,
        predicate: fn _indicators, news -> length(news) >= 2 end,
        reason: fn _indicators, news -> "#{length(news)} news items published" end
      }
    ]
  end

  defp low_and_noise_rules do
    [
      %Rule{
        id: :low_moderate_zscore,
        priority: 7,
        level: :low,
        direction: :derived,
        predicate: fn %Indicators{zscore21: z}, _news ->
          az = abs(z)
          az >= 0.5 and az <= 1.5
        end,
        reason: fn %Indicators{zscore21: z}, _news ->
          "Z-score #{Float.round(z, 1)}σ within moderate range"
        end
      },
      %Rule{
        id: :low_single_news,
        priority: 8,
        level: :low,
        direction: :derived,
        predicate: fn _indicators, news -> length(news) == 1 end,
        reason: fn _indicators, news -> "1 news item published: #{hd(news).title}" end
      },
      %Rule{
        id: :noise,
        priority: 9,
        level: :noise,
        direction: :neutral,
        predicate: fn _indicators, _news -> true end,
        reason: fn _indicators, _news -> "No significant signal detected" end
      }
    ]
  end

  defp medium_bearish_reason(z, s) do
    if z < -1.5 do
      "Price is #{Float.round(abs(z), 1)}σ below 21-day average"
    else
      "#{s.days} consecutive down days"
    end
  end

  defp medium_bullish_reason(z, s) do
    if z > 1.5 do
      "Price is #{Float.round(abs(z), 1)}σ above 21-day average"
    else
      "#{s.days} consecutive up days"
    end
  end

  # ---------------------------------------------------------------------------
  # Private — engine helpers
  # ---------------------------------------------------------------------------

  defp build_signal(firing, indicators, news_items) do
    level = pick_level(firing)
    top_rules = Enum.filter(firing, &(&1.level == level))
    direction = resolve_directions(top_rules, indicators, news_items)

    reasons =
      firing
      |> Enum.sort_by(& &1.priority)
      |> Enum.map(& &1.reason.(indicators, news_items))

    matched = length(firing)
    confidence = min(matched / @total_conditions, 1.0)

    %Signal{
      level: level,
      direction: direction,
      reasons: reasons,
      confidence: confidence
    }
  end

  defp pick_level(firing_rules) do
    rule = Enum.min_by(firing_rules, &Map.fetch!(@level_priority, &1.level))
    rule.level
  end

  defp resolve_directions(top_rules, indicators, news_items) do
    unique_dirs =
      top_rules
      |> Enum.map(fn rule -> effective_direction(rule.direction, indicators, news_items) end)
      |> Enum.uniq()

    cond do
      unique_dirs == [:bullish] -> :bullish
      unique_dirs == [:bearish] -> :bearish
      :bullish in unique_dirs and :bearish in unique_dirs -> :neutral
      true -> :neutral
    end
  end

  defp effective_direction(:derived, %Indicators{zscore21: z}, _news) do
    cond do
      z > 0.0 -> :bullish
      z < 0.0 -> :bearish
      true -> :neutral
    end
  end

  defp effective_direction(direction, _indicators, _news), do: direction
end
