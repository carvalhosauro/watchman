defmodule Watchman.News.FactoryTest do
  use ExUnit.Case, async: false

  alias Watchman.News.{B3, CVM, Factory, Infomoney, RssFeed}

  setup do
    prior_toml = Application.get_env(:watchman, :toml_config, %{})
    prior_override = Application.get_env(:watchman, :news_providers_override)

    on_exit(fn ->
      Application.put_env(:watchman, :toml_config, prior_toml)

      if prior_override do
        Application.put_env(:watchman, :news_providers_override, prior_override)
      else
        Application.delete_env(:watchman, :news_providers_override)
      end
    end)

    :ok
  end

  describe "providers/0" do
    test ~s("cvm" → [CVM]) do
      put_news("cvm")
      assert Factory.providers() == [CVM]
    end

    test ~s("infomoney" → [Infomoney]) do
      put_news("infomoney")
      assert Factory.providers() == [Infomoney]
    end

    test ~s("b3" → [B3]) do
      put_news("b3")
      assert Factory.providers() == [B3]
    end

    test ~s("rss" → [RssFeed]) do
      put_news("rss")
      assert Factory.providers() == [RssFeed]
    end

    test ~s("all" → [CVM, Infomoney, B3, RssFeed]) do
      put_news("all")
      assert Factory.providers() == [CVM, Infomoney, B3, RssFeed]
    end

    test "comma-separated subset preserves order and skips whitespace" do
      put_news("cvm, b3,rss")
      assert Factory.providers() == [CVM, B3, RssFeed]
    end

    test "unknown name falls back to default [CVM]" do
      put_news("totally-unknown-source")
      assert Factory.providers() == [CVM]
    end

    test "missing config falls back to default [CVM]" do
      Application.put_env(:watchman, :toml_config, %{})
      assert Factory.providers() == [CVM]
    end

    test "comma-separated with only unknown names falls back to default" do
      put_news("foo,bar")
      assert Factory.providers() == [CVM]
    end

    test "news_providers_override env wins over config" do
      put_news("all")
      Application.put_env(:watchman, :news_providers_override, [Infomoney])
      assert Factory.providers() == [Infomoney]
    end
  end

  defp put_news(name) do
    Application.put_env(:watchman, :toml_config, %{
      "providers" => %{"news" => name}
    })
  end
end
