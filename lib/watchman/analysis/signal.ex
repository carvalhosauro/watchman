defmodule Watchman.Analysis.Signal do
  @moduledoc """
  Deterministic classification of an asset at a single point in time.

  Produced by `Watchman.Analysis.Classifier.classify/2` from an
  `%Indicators{}` plus the list of news items for the asset. Consumed
  by `Watchman.Pipeline` (Track 4) and, when configured, the AI
  provider (which receives the signal as context and writes a
  narrative on top — it does not re-classify from scratch).

  Persisted by the pipeline into the `analyses` table via the four
  signal columns added in v0.6.0: `signal_level`, `signal_direction`,
  `signal_reasons` (JSON-encoded list), `signal_confidence`.

  All four fields are required (`@enforce_keys`) — partial construction
  raises `ArgumentError`.
  """

  @enforce_keys [:level, :direction, :reasons, :confidence]

  defstruct [:level, :direction, :reasons, :confidence]

  @type level :: :high | :medium | :low | :noise
  @type direction :: :bullish | :bearish | :neutral

  @type t :: %__MODULE__{
          level: level(),
          direction: direction(),
          reasons: [String.t()],
          confidence: float()
        }

  @levels [:high, :medium, :low, :noise]
  @directions [:bullish, :bearish, :neutral]

  @spec levels() :: [level()]
  def levels, do: @levels

  @spec directions() :: [direction()]
  def directions, do: @directions
end
