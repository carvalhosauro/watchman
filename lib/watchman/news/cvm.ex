defmodule Watchman.News.CVM do
  @moduledoc """
  News adapter for CVM (Comissão de Valores Mobiliários) regulatory disclosures.

  ## Endpoint

  Fetches XML from the CVM RAD (Recebimento, Armazenamento e Divulgação) system.

      Base URL: https://www.rad.cvm.gov.br/ENETCONSULTA/frmGetXml.aspx
      Parameters:
        TipoConsulta=c          — category query
        CodigoInstituicao=<n>   — CVM institution code for the company
                                  (pass via opts: [codigo: n]; defaults to 1)

  Example:
      https://www.rad.cvm.gov.br/ENETCONSULTA/frmGetXml.aspx?TipoConsulta=c&CodigoInstituicao=1

  ## Expected XML Schema

      <?xml version="1.0" encoding="UTF-8"?>
      <CVM>
        <documento>
          <tipo>Fato Relevante</tipo>
          <titulo>Aprovação de pagamento de dividendos</titulo>
          <url>https://www.rad.cvm.gov.br/ENETCONSULTA/abrir.html?id=123</url>
          <dataEntrega>2026-04-15T14:30:00</dataEntrega>
        </documento>
      </CVM>

  ## Category Mapping

  | CVM `<tipo>` value                         | Category           |
  |--------------------------------------------|--------------------|
  | `"Fato Relevante"`                         | `"material_fact"`  |
  | `"ITR"`, `"DFP"`, contains `"Demonstrações Financeiras"` | `"financial_result"` |
  | `"Comunicado ao Mercado"` + title contains `"dividendo"` or `"JCP"` | `"dividend"` |
  | Anything else                              | `"other"`          |

  HTTP fetch is excluded from unit-test coverage; it is tested via integration.
  `parse_response/2` is the pure, fully-covered entry point.
  """

  @behaviour Watchman.News.Provider

  import SweetXml, only: [xpath: 3, sigil_x: 2]

  alias Watchman.Models.NewsItem

  @base_url "https://www.rad.cvm.gov.br/ENETCONSULTA/frmGetXml.aspx"

  @impl true
  @spec fetch(String.t(), keyword()) :: {:ok, [NewsItem.t()]} | {:error, term()}
  def fetch(ticker, opts \\ []) do
    codigo = Keyword.get(opts, :codigo, 1)

    case Req.get(@base_url,
           params: [TipoConsulta: "c", CodigoInstituicao: codigo],
           receive_timeout: 10_000,
           retry: :transient
         ) do
      {:ok, %Req.Response{status: 200, body: body}} when is_binary(body) ->
        parse_response(body, ticker)

      {:ok, %Req.Response{status: status, body: body}} ->
        {:error, {:cvm_http, status, body}}

      {:error, reason} ->
        {:error, {:cvm_request, reason}}
    end
  end

  @spec parse_response(binary(), String.t()) :: {:ok, [NewsItem.t()]} | {:error, term()}
  def parse_response(xml, _ticker) do
    items =
      xml
      |> xpath(
        ~x"//documento"l,
        tipo: ~x"./tipo/text()"s,
        titulo: ~x"./titulo/text()"s,
        url: ~x"./url/text()"s,
        data_entrega: ~x"./dataEntrega/text()"s
      )
      |> Enum.map(&build_item/1)

    {:ok, items}
  rescue
    e -> {:error, {:parse_error, e}}
  catch
    _, reason -> {:error, {:parse_error, reason}}
  end

  defp build_item(%{tipo: tipo, titulo: titulo, url: url, data_entrega: data_entrega}) do
    %NewsItem{
      source: "cvm",
      category: map_category(tipo, titulo),
      title: titulo,
      url: url,
      published_at: parse_datetime(data_entrega)
    }
  end

  defp map_category("Fato Relevante", _title), do: "material_fact"
  defp map_category("ITR", _title), do: "financial_result"
  defp map_category("DFP", _title), do: "financial_result"

  defp map_category("Comunicado ao Mercado", title) do
    if String.contains?(title, ["dividendo", "JCP"]) do
      "dividend"
    else
      "other"
    end
  end

  defp map_category(tipo, _title) do
    if String.contains?(tipo, "Demonstrações Financeiras") do
      "financial_result"
    else
      "other"
    end
  end

  defp parse_datetime(""), do: nil

  defp parse_datetime(dt_str) do
    case NaiveDateTime.from_iso8601(dt_str) do
      {:ok, ndt} -> DateTime.from_naive!(ndt, "Etc/UTC")
      _error -> nil
    end
  end
end
