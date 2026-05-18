defmodule Watchman.Alerts.TelegramTest do
  use ExUnit.Case, async: false

  alias Watchman.Alerts.Telegram

  @bot_token "test_bot_token_123"
  @chat_id "987654321"

  setup do
    Application.put_env(:watchman, :toml_config, %{
      "alerts" => %{
        "telegram" => %{
          "bot_token" => @bot_token,
          "chat_id" => @chat_id
        }
      }
    })

    Application.put_env(:watchman, :telegram_req_plug, {Req.Test, __MODULE__})

    on_exit(fn ->
      Application.delete_env(:watchman, :toml_config)
      Application.delete_env(:watchman, :telegram_req_plug)
    end)

    :ok
  end

  describe "send_alert/3" do
    test "formats message as 'TICKER — recommendation\\njustification' and posts to Telegram" do
      Req.Test.stub(__MODULE__, fn conn ->
        assert conn.request_path == "/bot#{@bot_token}/sendMessage"
        body = Req.Test.raw_body(conn)
        decoded = Jason.decode!(body)
        assert decoded["chat_id"] == @chat_id
        assert decoded["text"] == "PETR4 — investigar\nQueda no preco do petroleo"
        assert decoded["parse_mode"] == "Markdown"
        Req.Test.json(conn, %{"ok" => true})
      end)

      assert :ok = Telegram.send_alert("PETR4", "investigar", "Queda no preco do petroleo")
    end

    test "returns error on non-200 API response" do
      Req.Test.stub(__MODULE__, fn conn ->
        conn
        |> Plug.Conn.put_status(401)
        |> Req.Test.json(%{"ok" => false, "description" => "Unauthorized"})
      end)

      assert {:error, {:telegram_api, 401, _body}} =
               Telegram.send_alert("PETR4", "investigar", "Queda")
    end

    test "returns config error when token not configured" do
      Application.put_env(:watchman, :toml_config, %{})

      assert {:error, {:config, _reason}} =
               Telegram.send_alert("PETR4", "investigar", "Queda")
    end

    test "returns config error when chat_id not configured" do
      Application.put_env(:watchman, :toml_config, %{
        "alerts" => %{"telegram" => %{"bot_token" => @bot_token}}
      })

      assert {:error, {:config, _reason}} =
               Telegram.send_alert("PETR4", "investigar", "Queda")
    end
  end

  describe "test_connection/0" do
    test "calls getMe then sends a test message on success" do
      call_count = :counters.new(1, [:atomics])

      Req.Test.stub(__MODULE__, fn conn ->
        :counters.add(call_count, 1, 1)
        count = :counters.get(call_count, 1)

        cond do
          count == 1 ->
            assert conn.request_path == "/bot#{@bot_token}/getMe"
            Req.Test.json(conn, %{"ok" => true, "result" => %{"username" => "watchman_bot"}})

          count == 2 ->
            assert conn.request_path == "/bot#{@bot_token}/sendMessage"
            body = Req.Test.raw_body(conn)
            decoded = Jason.decode!(body)
            assert decoded["text"] == "✓ Watchman alertas configurado!"
            Req.Test.json(conn, %{"ok" => true})

          true ->
            Req.Test.transport_error(conn, :closed)
        end
      end)

      assert :ok = Telegram.test_connection()
    end

    test "returns auth error when getMe fails" do
      Req.Test.stub(__MODULE__, fn conn ->
        conn
        |> Plug.Conn.put_status(401)
        |> Req.Test.json(%{"ok" => false, "description" => "Unauthorized"})
      end)

      assert {:error, {:telegram_auth, 401, _body}} = Telegram.test_connection()
    end

    test "returns config error when credentials not set" do
      Application.put_env(:watchman, :toml_config, %{})

      assert {:error, {:config, _reason}} = Telegram.test_connection()
    end
  end
end
