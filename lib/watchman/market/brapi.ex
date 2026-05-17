defmodule Watchman.Market.Brapi do
  @behaviour Watchman.Market.Provider

  @base_url "https://brapi.dev/api/quote"

  @impl true
  def fetch(ticker) do
    token = Watchman.Config.brapi_token()
    url = "#{@base_url}/#{ticker}"

    case Req.get(url, params: [token: token]) do
      {:ok, %Req.Response{status: 200, body: %{"results" => [result | _]}}} ->
        {:ok, %{
          price: result["regularMarketPrice"],
          variation_day: result["regularMarketChangePercent"],
          variation_week: get_in(result, ["historicalDataPrice"]) |> calc_weekly_var(),
          variation_month: get_in(result, ["historicalDataPrice"]) |> calc_monthly_var()
        }}

      {:ok, %Req.Response{status: status, body: body}} ->
        {:error, {:brapi, status, body}}

      {:error, reason} ->
        {:error, {:brapi_request, reason}}
    end
  end

  # brapi may not provide week/month variation directly — return nil for now
  # these can be computed from historical snapshots later
  defp calc_weekly_var(nil), do: nil
  defp calc_weekly_var(_data), do: nil

  defp calc_monthly_var(nil), do: nil
  defp calc_monthly_var(_data), do: nil
end
