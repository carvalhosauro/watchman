defmodule Watchman.Analysis.Classifier.Rule do
  @moduledoc """
  One entry in the classifier's ordered rule list.

  `Watchman.Analysis.Classifier` evaluates rules in priority order (1
  = highest) against an `%Indicators{}` and a list of news items. A
  rule with a `predicate` that returns `true` "fires" and contributes
  its `level` + `direction` + `reason/2` output to the resulting
  `%Signal{}`.

  Rules are data, not behaviour — the engine never special-cases
  individual rules. New rules are added by appending another struct to
  the list; rule ordering is enforced via the `priority` field.

  All fields are required (`@enforce_keys`).

    * `id` — atom identifier (e.g., `:high_bearish_zscore_streak`).
    * `priority` — positive integer, 1 = highest priority.
    * `level` — `Watchman.Analysis.Signal.level()` produced when the rule fires.
    * `direction` — `Watchman.Analysis.Signal.direction()` produced, or
      `:derived` when the rule's direction depends on the inputs (the
      classifier resolves `:derived` at evaluation time).
    * `predicate` — `(Indicators.t(), [NewsItem.t()] -> boolean())`.
    * `reason` — `(Indicators.t(), [NewsItem.t()] -> String.t())`
      producing the human-readable reason string when the rule fires.
  """

  alias Watchman.Analysis.{Indicators, Signal}
  alias Watchman.Models.NewsItem

  @enforce_keys [:id, :priority, :level, :direction, :predicate, :reason]

  defstruct [:id, :priority, :level, :direction, :predicate, :reason]

  @type direction_marker :: Signal.direction() | :derived

  @type t :: %__MODULE__{
          id: atom(),
          priority: pos_integer(),
          level: Signal.level(),
          direction: direction_marker(),
          predicate: (Indicators.t(), [NewsItem.t()] -> boolean()),
          reason: (Indicators.t(), [NewsItem.t()] -> String.t())
        }
end
