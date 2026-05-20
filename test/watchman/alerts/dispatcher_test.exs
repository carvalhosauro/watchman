defmodule Watchman.Alerts.DispatcherTest do
  use ExUnit.Case, async: false

  import Mox

  alias Watchman.Alerts.Dispatcher
  alias Watchman.Analysis.Signal

  setup :verify_on_exit!

  setup do
    Application.put_env(:watchman, :alerts_provider_override, [Watchman.Alerts.MockProvider])

    Application.put_env(
      :watchman,
      :toml_config,
      %{"alerts" => %{"triggers" => ["investigar", "vender"]}}
    )

    on_exit(fn ->
      Application.delete_env(:watchman, :alerts_provider_override)
    end)

    :ok
  end

  describe "maybe_notify/3" do
    test "sends alert when recommendation matches trigger" do
      Watchman.Alerts.MockProvider
      |> expect(:send_alert, fn "PETR4", "investigar", "Queda no preco" -> :ok end)

      assert :ok = Dispatcher.maybe_notify("PETR4", "investigar", "Queda no preco")
    end

    test "sends alert for vender recommendation" do
      Watchman.Alerts.MockProvider
      |> expect(:send_alert, fn "VALE3", "vender", "Risco alto" -> :ok end)

      assert :ok = Dispatcher.maybe_notify("VALE3", "vender", "Risco alto")
    end

    test "does not send alert for manter recommendation" do
      # No expectation set — Mox will fail if send_alert is called
      assert :ok = Dispatcher.maybe_notify("ITUB4", "manter", "Estavel")
    end

    test "returns :ok even when provider fails" do
      Watchman.Alerts.MockProvider
      |> expect(:send_alert, fn _, _, _ -> {:error, :timeout} end)

      assert :ok = Dispatcher.maybe_notify("PETR4", "investigar", "Queda")
    end

    test "is no-op when no providers configured" do
      Application.put_env(:watchman, :alerts_provider_override, [])
      assert :ok = Dispatcher.maybe_notify("PETR4", "investigar", "Queda")
    end

    test "handles nil justification" do
      Watchman.Alerts.MockProvider
      |> expect(:send_alert, fn "PETR4", "investigar", "" -> :ok end)

      assert :ok = Dispatcher.maybe_notify("PETR4", "investigar", nil)
    end
  end

  describe "test_all/0" do
    test "returns results per provider" do
      Watchman.Alerts.MockProvider
      |> expect(:test_connection, fn -> :ok end)

      results = Dispatcher.test_all()
      assert [{_, :ok}] = results
    end

    test "reports no providers when none configured" do
      Application.put_env(:watchman, :alerts_provider_override, [])
      assert :no_providers = Dispatcher.test_all()
    end
  end

  describe "maybe_notify_signal/3" do
    test "dispatches when HIGH bullish signal matches default config" do
      signal = %Signal{
        level: :high,
        direction: :bullish,
        reasons: ["RSI oversold", "MACD cross"],
        confidence: 0.85
      }

      Watchman.Alerts.MockProvider
      |> expect(:send_alert, fn "PETR4", message, "" ->
        assert message =~ "[PETR4]"
        assert message =~ "HIGH"
        assert message =~ "BULLISH"
        assert message =~ "85.0%"
        assert message =~ "RSI oversold"
        assert message =~ "MACD cross"
        :ok
      end)

      assert :ok = Dispatcher.maybe_notify_signal("PETR4", signal)
    end

    test "does not dispatch when MEDIUM bullish signal with default config (level not whitelisted)" do
      signal = %Signal{
        level: :medium,
        direction: :bullish,
        reasons: ["Volume spike"],
        confidence: 0.6
      }

      # No expectation — Mox fails if send_alert is called
      assert :ok = Dispatcher.maybe_notify_signal("VALE3", signal)
    end

    test "does not dispatch when HIGH neutral signal with default config (direction not whitelisted)" do
      signal = %Signal{
        level: :high,
        direction: :neutral,
        reasons: ["Mixed signals"],
        confidence: 0.7
      }

      assert :ok = Dispatcher.maybe_notify_signal("ITUB4", signal)
    end

    test "dispatches LOW bearish signal when notify_levels overrides include low" do
      Application.put_env(:watchman, :toml_config, %{
        "alerts" => %{
          "triggers" => ["investigar", "vender"],
          "signal" => %{"notify_levels" => ["high", "medium", "low"]}
        }
      })

      signal = %Signal{
        level: :low,
        direction: :bearish,
        reasons: ["Weak momentum"],
        confidence: 0.4
      }

      Watchman.Alerts.MockProvider
      |> expect(:send_alert, fn "MGLU3", message, "" ->
        assert message =~ "LOW"
        assert message =~ "BEARISH"
        :ok
      end)

      assert :ok = Dispatcher.maybe_notify_signal("MGLU3", signal)
    end

    test "returns :ok and logs warning when provider fails" do
      signal = %Signal{level: :high, direction: :bullish, reasons: ["Breakout"], confidence: 0.9}

      Watchman.Alerts.MockProvider
      |> expect(:send_alert, fn _, _, _ -> {:error, :timeout} end)

      assert :ok = Dispatcher.maybe_notify_signal("BBDC4", signal)
    end
  end
end
