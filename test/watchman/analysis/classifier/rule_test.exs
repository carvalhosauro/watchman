defmodule Watchman.Analysis.Classifier.RuleTest do
  use ExUnit.Case, async: true

  alias Watchman.Analysis.Classifier.Rule

  defp valid_fields do
    %{
      id: :high_bearish_zscore_streak,
      priority: 1,
      level: :high,
      direction: :bearish,
      predicate: fn _indicators, _news -> true end,
      reason: fn _indicators, _news -> "test reason" end
    }
  end

  describe "Rule struct" do
    test "constructs with all required fields" do
      rule = struct!(Rule, valid_fields())
      assert rule.id == :high_bearish_zscore_streak
      assert rule.priority == 1
      assert rule.level == :high
      assert rule.direction == :bearish
      assert is_function(rule.predicate, 2)
      assert is_function(rule.reason, 2)
    end

    test ":derived direction marker is permitted" do
      rule = struct!(Rule, %{valid_fields() | direction: :derived})
      assert rule.direction == :derived
    end

    test "missing field raises ArgumentError" do
      attrs = Map.delete(valid_fields(), :predicate)

      assert_raise ArgumentError, ~r/:predicate/, fn ->
        struct!(Rule, attrs)
      end
    end
  end
end
