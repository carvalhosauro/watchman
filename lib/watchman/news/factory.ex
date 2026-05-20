defmodule Watchman.News.Factory do
  @moduledoc """
  Resolves configured news provider modules.

  The `news_provider` config key accepts one of:

    * `"cvm"` — `[Watchman.News.CVM]`
    * `"infomoney"` — `[Watchman.News.Infomoney]`
    * `"b3"` — `[Watchman.News.B3]`
    * `"rss"` — `[Watchman.News.RssFeed]`
    * `"all"` — every adapter, in the order above
    * `"cvm,b3,rss"` — a comma-separated subset (whitespace tolerated)
    * any unknown or missing value — defaults to `[Watchman.News.CVM]`

  Callers iterate the returned list, fetch from each adapter, then
  merge + deduplicate by URL.
  """

  alias Watchman.News.{B3, CVM, Infomoney, RssFeed}

  @map %{
    "cvm" => CVM,
    "infomoney" => Infomoney,
    "b3" => B3,
    "rss" => RssFeed
  }

  @all [CVM, Infomoney, B3, RssFeed]
  @default [CVM]

  @spec providers() :: [module()]
  def providers do
    Application.get_env(:watchman, :news_providers_override) ||
      resolve(Watchman.Config.news_provider())
  end

  defp resolve("all"), do: @all

  defp resolve(name) when is_binary(name) do
    name
    |> String.split(",")
    |> Enum.map(&String.trim/1)
    |> Enum.map(&Map.get(@map, &1))
    |> Enum.reject(&is_nil/1)
    |> case do
      [] -> @default
      list -> list
    end
  end

  defp resolve(_), do: @default
end
