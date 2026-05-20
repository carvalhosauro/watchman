defmodule Watchman.AccuracyTest do
  use ExUnit.Case, async: true

  alias Watchman.Accuracy

  describe "classify_outcome/3" do
    test "manter with positive variation is a hit" do
      assert Accuracy.classify_outcome("manter", 1.0, 3.0) == :hit
    end

    test "manter at -2.9 with threshold 3.0 is a hit (boundary inclusive)" do
      assert Accuracy.classify_outcome("manter", -2.9, 3.0) == :hit
    end

    test "manter at exactly -3.0 with threshold 3.0 is a hit (at threshold)" do
      assert Accuracy.classify_outcome("manter", -3.0, 3.0) == :hit
    end

    test "manter at -3.1 with threshold 3.0 is a miss" do
      assert Accuracy.classify_outcome("manter", -3.1, 3.0) == :miss
    end

    test "vender at -3.0 with threshold 3.0 is a hit" do
      assert Accuracy.classify_outcome("vender", -3.0, 3.0) == :hit
    end

    test "vender at -10.0 with threshold 3.0 is a hit" do
      assert Accuracy.classify_outcome("vender", -10.0, 3.0) == :hit
    end

    test "vender at -2.0 with threshold 3.0 is a miss" do
      assert Accuracy.classify_outcome("vender", -2.0, 3.0) == :miss
    end

    test "vender at +1.0 with threshold 3.0 is a miss" do
      assert Accuracy.classify_outcome("vender", 1.0, 3.0) == :miss
    end

    test "investigar is always neutral" do
      assert Accuracy.classify_outcome("investigar", 0.0, 3.0) == :neutral
    end

    test "investigar with extreme positive variation is neutral" do
      assert Accuracy.classify_outcome("investigar", 99.9, 3.0) == :neutral
    end

    test "investigar with extreme negative variation is neutral" do
      assert Accuracy.classify_outcome("investigar", -99.9, 3.0) == :neutral
    end

    test "unknown recommendation raises FunctionClauseError" do
      assert_raise FunctionClauseError, fn ->
        Accuracy.classify_outcome("comprar", 1.0, 3.0)
      end
    end
  end
end
