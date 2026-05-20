defmodule Watchman.AI.Provider do
  @moduledoc """
  Behaviour for AI analysis providers.

  ## Arity Strategy

  Two arities are supported:

  - `analyze/2` — legacy call (asset + snapshot only). The model
    classifies the asset from first principles. Kept for backward
    compatibility and for callers that do not yet have a
    `%Watchman.Analysis.Signal{}` available.

  - `analyze/4` — v0.6.0 enrichment call (asset + snapshot + signal +
    news). `Watchman.Analysis.Classifier` has already classified the
    asset; the AI's job is to **explain and enrich** the signal in
    Portuguese, NOT to re-classify it. The `recommendation` field in the
    returned map is derived from the signal level/direction via
    `Watchman.AI.Shared.recommendation_from_signal/1` and is not left
    to the model's discretion.

  `Watchman.Pipeline` will switch to `analyze/4` once all adapters ship;
  the lead handles that migration separately.
  """

  alias Watchman.Analysis.Signal
  alias Watchman.Models.NewsItem

  @type analysis_result :: %{
          cause: String.t() | nil,
          is_specific_problem: boolean(),
          macro_context: String.t() | nil,
          recommendation: String.t(),
          justification: String.t() | nil,
          tokens_used: integer()
        }

  @type news_item :: %{
          title: String.t() | nil,
          summary: String.t() | nil,
          source: String.t() | nil,
          url: String.t() | nil,
          published_at: DateTime.t() | nil
        }

  @callback analyze(asset :: map(), snapshot :: map()) ::
              {:ok, analysis_result(), [news_item()]}
              | {:error, term()}

  @callback analyze(
              asset :: map(),
              snapshot :: map(),
              signal :: Signal.t(),
              news :: [NewsItem.t()]
            ) ::
              {:ok, analysis_result(), [news_item()]}
              | {:error, term()}

  @callback generate_retro(prompt :: String.t()) ::
              {:ok, String.t()}
              | {:error, term()}
end
