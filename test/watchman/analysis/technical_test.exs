defmodule Watchman.Analysis.TechnicalTest do
  use ExUnit.Case, async: true

  alias Watchman.Analysis.Technical
  alias Watchman.Models.PriceSnapshot

  defp snap(price), do: %PriceSnapshot{price: price}

  describe "sma/2" do
    test "reference: period 3 over 5 snapshots → (3+4+5)/3 = 4.0" do
      snapshots = Enum.map([1, 2, 3, 4, 5], &snap/1)
      assert Technical.sma(snapshots, 3) == {:ok, 4.0}
    end

    test "period equals list length → average over all" do
      snapshots = Enum.map([2, 4, 6], &snap/1)
      assert Technical.sma(snapshots, 3) == {:ok, 4.0}
    end

    test "period = 1 → last price" do
      snapshots = Enum.map([10, 20, 30], &snap/1)
      assert Technical.sma(snapshots, 1) == {:ok, 30.0}
    end

    test "length < period → {:error, :insufficient_data}" do
      snapshots = Enum.map([1, 2], &snap/1)
      assert Technical.sma(snapshots, 5) == {:error, :insufficient_data}
    end

    test "empty list with any period → {:error, :insufficient_data}" do
      assert Technical.sma([], 3) == {:error, :insufficient_data}
    end
  end
end
