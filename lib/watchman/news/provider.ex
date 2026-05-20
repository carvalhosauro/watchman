defmodule Watchman.News.Provider do
  @moduledoc """
  Behaviour every news adapter implements.

  Adapters fetch news items for a single ticker and return them as a list
  of `Watchman.Models.NewsItem` structs (not yet persisted — caller is
  responsible for inserting via the changeset).

  Track 3 adapters: `Watchman.News.CVM`, `Watchman.News.Infomoney`,
  `Watchman.News.B3`, `Watchman.News.RssFeed`.

  Resolution and merge happens in `Watchman.News.Factory`.
  """

  alias Watchman.Models.NewsItem

  @callback fetch(ticker :: String.t(), opts :: keyword()) ::
              {:ok, [NewsItem.t()]} | {:error, term()}
end
