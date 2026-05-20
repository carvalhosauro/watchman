defmodule Watchman.Analysis.IndicatorsTest do
  use ExUnit.Case, async: true

  alias Watchman.Analysis.Indicators

  @valid_fields %{
    sma7: 10.0,
    sma21: 10.5,
    sma50: 11.0,
    ema21: 10.7,
    rsi14: 55.0,
    zscore21: -0.5,
    streak: %{direction: :up, days: 3},
    drawdown_from_peak: -2.0
  }

  describe "Indicators struct" do
    test "constructs with all required fields" do
      ind = struct!(Indicators, @valid_fields)
      assert ind.sma7 == 10.0
      assert ind.sma21 == 10.5
      assert ind.sma50 == 11.0
      assert ind.ema21 == 10.7
      assert ind.rsi14 == 55.0
      assert ind.zscore21 == -0.5
      assert ind.streak == %{direction: :up, days: 3}
      assert ind.drawdown_from_peak == -2.0
    end

    test "missing field raises ArgumentError (enforced via @enforce_keys)" do
      attrs = Map.delete(@valid_fields, :rsi14)

      assert_raise ArgumentError, ~r/the following keys must also be given.*:rsi14/s, fn ->
        struct!(Indicators, attrs)
      end
    end
  end
end
