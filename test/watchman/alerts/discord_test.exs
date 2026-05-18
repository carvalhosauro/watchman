defmodule Watchman.Alerts.DiscordTest do
  use ExUnit.Case, async: false

  alias Watchman.Alerts.Discord

  @webhook_url "https://discord.com/api/webhooks/123456789/test_token"

  setup do
    Application.put_env(:watchman, :toml_config, %{
      "alerts" => %{"discord" => %{"webhook_url" => @webhook_url}}
    })

    Application.put_env(:watchman, :discord_test_plug, {Req.Test, __MODULE__})

    on_exit(fn ->
      Application.put_env(:watchman, :toml_config, %{})
      Application.delete_env(:watchman, :discord_test_plug)
    end)

    :ok
  end

  describe "send_alert/3" do
    test "posts embed with red color for vender" do
      Req.Test.stub(__MODULE__, fn conn ->
        body = Req.Test.raw_body(conn)
        decoded = Jason.decode!(body)
        [embed] = decoded["embeds"]

        assert embed["title"] == "PETR4 — vender"
        assert embed["description"] == "Risco alto"
        assert embed["color"] == 15_158_332

        Req.Test.json(conn, %{})
      end)

      assert :ok = Discord.send_alert("PETR4", "vender", "Risco alto")
    end

    test "posts embed with yellow color for investigar" do
      Req.Test.stub(__MODULE__, fn conn ->
        body = Req.Test.raw_body(conn)
        decoded = Jason.decode!(body)
        [embed] = decoded["embeds"]

        assert embed["title"] == "VALE3 — investigar"
        assert embed["color"] == 16_776_960

        Req.Test.json(conn, %{})
      end)

      assert :ok = Discord.send_alert("VALE3", "investigar", "Queda no preco")
    end

    test "posts embed with green color for manter" do
      Req.Test.stub(__MODULE__, fn conn ->
        body = Req.Test.raw_body(conn)
        decoded = Jason.decode!(body)
        [embed] = decoded["embeds"]

        assert embed["title"] == "ITUB4 — manter"
        assert embed["color"] == 3_066_993

        Req.Test.json(conn, %{})
      end)

      assert :ok = Discord.send_alert("ITUB4", "manter", "Estavel")
    end

    test "returns error on non-2xx response" do
      Req.Test.stub(__MODULE__, fn conn ->
        conn
        |> Plug.Conn.put_resp_content_type("application/json")
        |> Plug.Conn.send_resp(404, Jason.encode!(%{"message" => "Unknown Webhook"}))
      end)

      assert {:error, {:discord_api, 404, _}} = Discord.send_alert("PETR4", "vender", "Risco")
    end

    test "returns error when webhook not configured" do
      Application.put_env(:watchman, :toml_config, %{})

      assert {:error, {:config, _}} = Discord.send_alert("PETR4", "vender", "Risco")
    end
  end

  describe "test_connection/0" do
    test "sends content message and returns :ok on success" do
      Req.Test.stub(__MODULE__, fn conn ->
        body = Req.Test.raw_body(conn)
        decoded = Jason.decode!(body)

        assert decoded["content"] == "✓ Watchman alertas configurado!"

        Req.Test.json(conn, %{})
      end)

      assert :ok = Discord.test_connection()
    end

    test "returns error on API failure" do
      Req.Test.stub(__MODULE__, fn conn ->
        conn
        |> Plug.Conn.put_resp_content_type("application/json")
        |> Plug.Conn.send_resp(401, Jason.encode!(%{"message" => "Unauthorized"}))
      end)

      assert {:error, {:discord_api, 401, _}} = Discord.test_connection()
    end

    test "returns error when webhook not configured" do
      Application.put_env(:watchman, :toml_config, %{})

      assert {:error, {:config, _}} = Discord.test_connection()
    end
  end
end
