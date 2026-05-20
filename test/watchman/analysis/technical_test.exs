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

  describe "ema/2" do
    # LibreOffice derivation:
    #   prices = [10.0, 12.0, 14.0, 13.0, 15.0, 16.0], period = 3
    #   multiplier = 2 / (3+1) = 0.5
    #   ema_0 = (10+12+14)/3 = 12.0  (SMA seed)
    #   ema_1 = (13 - 12.0) * 0.5 + 12.0 = 12.5
    #   ema_2 = (15 - 12.5) * 0.5 + 12.5 = 13.75
    #   ema_3 = (16 - 13.75) * 0.5 + 13.75 = 14.875
    test "reference: period 3 over 6 prices → 14.875" do
      snapshots = Enum.map([10.0, 12.0, 14.0, 13.0, 15.0, 16.0], &snap/1)
      {:ok, result} = Technical.ema(snapshots, 3)
      assert_in_delta result, 14.875, 1.0e-4
    end

    test "period equals list length → SMA seed, no iteration" do
      snapshots = Enum.map([2.0, 4.0, 6.0], &snap/1)
      {:ok, result} = Technical.ema(snapshots, 3)
      assert_in_delta result, 4.0, 1.0e-4
    end

    test "insufficient: length < period → {:error, :insufficient_data}" do
      snapshots = Enum.map([1.0, 2.0], &snap/1)
      assert Technical.ema(snapshots, 5) == {:error, :insufficient_data}
    end
  end
end
