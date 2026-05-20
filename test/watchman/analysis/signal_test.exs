defmodule Watchman.Analysis.SignalTest do
  use ExUnit.Case, async: true

  alias Watchman.Analysis.Signal

  @valid_fields %{
    level: :high,
    direction: :bearish,
    reasons: ["Price is 2.3σ below 21-day average", "3 consecutive down days"],
    confidence: 0.75
  }

  describe "Signal struct" do
    test "constructs with all required fields" do
      sig = struct!(Signal, @valid_fields)
      assert sig.level == :high
      assert sig.direction == :bearish
      assert length(sig.reasons) == 2
      assert sig.confidence == 0.75
    end

    test "missing field raises ArgumentError" do
      attrs = Map.delete(@valid_fields, :confidence)

      assert_raise ArgumentError, ~r/:confidence/, fn ->
        struct!(Signal, attrs)
      end
    end
  end

  describe "levels/0" do
    test "returns the four documented levels in priority order" do
      assert Signal.levels() == [:high, :medium, :low, :noise]
    end
  end

  describe "directions/0" do
    test "returns the three documented directions" do
      assert Signal.directions() == [:bullish, :bearish, :neutral]
    end
  end
end
