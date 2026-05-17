defmodule Watchman.AI.Provider do
  @moduledoc "Behaviour for AI analysis providers."

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

  @callback generate_retro(prompt :: String.t()) ::
              {:ok, String.t()}
              | {:error, term()}
end
