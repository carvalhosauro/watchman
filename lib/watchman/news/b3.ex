defmodule Watchman.News.B3 do
  @moduledoc """
  News adapter that fetches corporate-action events for a ticker from B3
  (Brasil, Bolsa, Balcão).

  ## Endpoint

  B3 publishes corporate-actions data via an undocumented JSON endpoint:

      https://sistemaswebb3-listados.b3.com.br/listedCompaniesProxy/CompanyCall/GetListedSupplementCompany/<base64-params>

  where `<base64-params>` is the Base64-encoding of:

      {"language": "pt-br", "pageNumber": 1, "pageSize": 20, "company": "<TICKER>"}

  If the endpoint is unreachable or returns an unexpected shape, `fetch/2`
  returns `{:error, reason}`.

  ## Expected JSON shape

      {
        "ticker": "PETR4",
        "corporateActions": [
          {
            "type": "DIVIDEND",
            "description": "Dividendo extraordinário",
            "approvedAt": "2026-04-15",
            "exDate": "2026-05-01",
            "url": "https://b3.com.br/..."
          },
          {
            "type": "STOCK_SPLIT",
            "description": "Desdobramento 1:2",
            "approvedAt": "2026-03-01",
            "url": "https://b3.com.br/..."
          },
          {
            "type": "SUBSCRIPTION",
            "description": "Direito de subscrição",
            "approvedAt": "2026-02-15",
            "url": "https://b3.com.br/..."
          }
        ]
      }

  ## Category mapping

  | B3 `type`                           | `category`   |
  |-------------------------------------|--------------|
  | `DIVIDEND`, `JCP`, `INTEREST_ON_CAPITAL` | `"dividend"` |
  | `STOCK_SPLIT`, `REVERSE_SPLIT`, `BONUS`, `SUBSCRIPTION`, other | `"other"` |
  """

  @behaviour Watchman.News.Provider

  alias Watchman.Models.NewsItem

  @base_url "https://sistemaswebb3-listados.b3.com.br/listedCompaniesProxy/CompanyCall/GetListedSupplementCompany"
  @fallback_url "https://www.b3.com.br/pt_br/produtos-e-servicos/negociacao/renda-variavel/empresas-listadas.htm"
  @dividend_types ~w(DIVIDEND JCP INTEREST_ON_CAPITAL)

  @impl true
  @spec fetch(String.t(), keyword()) :: {:ok, [NewsItem.t()]} | {:error, term()}
  def fetch(ticker, _opts) do
    params =
      Jason.encode!(%{
        "language" => "pt-br",
        "pageNumber" => 1,
        "pageSize" => 20,
        "company" => ticker
      })

    url = "#{@base_url}/#{Base.encode64(params)}"

    case Req.get(url, receive_timeout: 10_000, retry: :transient) do
      {:ok, %Req.Response{status: 200, body: body}} ->
        parse_response(body, ticker)

      {:ok, %Req.Response{status: status, body: body}} ->
        {:error, {:b3_http, status, body}}

      {:error, reason} ->
        {:error, {:b3_request, reason}}
    end
  end

  @doc """
  Parses a B3 corporate-actions response for `ticker`.

  Accepts either a raw JSON binary or an already-decoded map (Req
  auto-decodes responses with `application/json` content-type).

  Returns `{:ok, [%NewsItem{}]}` or `{:error, reason}`.
  """
  @spec parse_response(binary() | map(), String.t()) ::
          {:ok, [NewsItem.t()]} | {:error, term()}
  def parse_response(body, ticker) when is_binary(body) do
    case Jason.decode(body) do
      {:ok, decoded} -> parse_response(decoded, ticker)
      {:error, reason} -> {:error, {:json_decode, reason}}
    end
  end

  def parse_response(%{"corporateActions" => actions}, _ticker) when is_list(actions) do
    items =
      actions
      |> Enum.map(&build_news_item/1)
      |> Enum.reject(&is_nil/1)

    {:ok, items}
  end

  def parse_response(%{}, _ticker), do: {:ok, []}

  def parse_response(_body, _ticker), do: {:error, :unexpected_shape}

  defp build_news_item(%{"type" => type, "description" => description} = action) do
    %NewsItem{
      source: "b3",
      category: map_category(type),
      title: description,
      url: Map.get(action, "url") || @fallback_url,
      published_at: parse_date(Map.get(action, "approvedAt"))
    }
  end

  defp build_news_item(_action), do: nil

  defp map_category(type) when type in @dividend_types, do: "dividend"
  defp map_category(_type), do: "other"

  defp parse_date(nil), do: nil

  defp parse_date(date_str) when is_binary(date_str) do
    case Date.from_iso8601(date_str) do
      {:ok, date} -> DateTime.new!(date, ~T[00:00:00], "Etc/UTC")
      {:error, _} -> nil
    end
  end
end
