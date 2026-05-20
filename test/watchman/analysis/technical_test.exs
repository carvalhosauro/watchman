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

  describe "rsi/2" do
    # Wilder-smoothed derivation, period = 3:
    #   prices = [3.0, 4.0, 3.0, 5.0, 4.0, 6.0]
    #   deltas = [+1.0, -1.0, +2.0, -1.0, +2.0]
    #   seed (first 3): avg_gain = (1+0+2)/3 = 1.0, avg_loss = (0+1+0)/3 = 1/3
    #   d=-1.0: avg_gain = (1.0*2+0)/3 = 2/3, avg_loss = (1/3*2+1)/3 = 5/9
    #   d=+2.0: avg_gain = (2/3*2+2)/3 = 10/9, avg_loss = (5/9*2+0)/3 = 10/27
    #   rs = (10/9)/(10/27) = 3.0  →  RSI = 100 - 100/(1+3) = 75.0
    test "reference: Wilder-smoothed period 3 → 75.0" do
      snapshots = Enum.map([3.0, 4.0, 3.0, 5.0, 4.0, 6.0], &snap/1)
      {:ok, result} = Technical.rsi(snapshots, 3)
      assert_in_delta result, 75.0, 1.0e-4
    end

    test "all-gain (monotonically increasing) → 100.0" do
      snapshots = Enum.map([1.0, 2.0, 3.0, 4.0], &snap/1)
      assert Technical.rsi(snapshots, 3) == {:ok, 100.0}
    end

    test "all-loss (monotonically decreasing) → 0.0" do
      snapshots = Enum.map([4.0, 3.0, 2.0, 1.0], &snap/1)
      assert Technical.rsi(snapshots, 3) == {:ok, 0.0}
    end

    test "flat input (all same prices) → 100.0 (avg_loss == 0 convention)" do
      # avg_gain == 0 and avg_loss == 0; avg_loss == 0 check fires first → 100.0
      snapshots = Enum.map([5.0, 5.0, 5.0, 5.0], &snap/1)
      assert Technical.rsi(snapshots, 3) == {:ok, 100.0}
    end

    test "insufficient: < period+1 snapshots → {:error, :insufficient_data}" do
      snapshots = Enum.map([1.0, 2.0, 3.0], &snap/1)
      assert Technical.rsi(snapshots, 3) == {:error, :insufficient_data}
    end

    test "default period 14: 14 snapshots → insufficient, 15 all-gain → 100.0" do
      assert Technical.rsi(Enum.map(1..14, &snap(&1 * 1.0))) == {:error, :insufficient_data}
      assert Technical.rsi(Enum.map(1..15, &snap(&1 * 1.0))) == {:ok, 100.0}
    end
  end

  describe "zscore/2" do
    # Hand-computed, period = 5:
    #   prices = [10.0, 12.0, 14.0, 16.0, 18.0]
    #   mean = 70/5 = 14.0
    #   sum_sq = (10-14)^2+(12-14)^2+(14-14)^2+(16-14)^2+(18-14)^2 = 16+4+0+4+16 = 40
    #   variance = 40/(5-1) = 10.0  (sample, n-1)
    #   stddev = sqrt(10) ≈ 3.16228
    #   z = (18 - 14) / 3.16228 ≈ 1.26491
    test "reference: sample zscore period 5 → ≈1.26491" do
      snapshots = Enum.map([10.0, 12.0, 14.0, 16.0, 18.0], &snap/1)
      {:ok, result} = Technical.zscore(snapshots, 5)
      assert_in_delta result, 1.26491, 1.0e-4
    end

    test "insufficient: length < period → {:error, :insufficient_data}" do
      snapshots = Enum.map([1.0, 2.0], &snap/1)
      assert Technical.zscore(snapshots, 5) == {:error, :insufficient_data}
    end

    test "period = 1 → {:error, :insufficient_data} (sample stddev needs n ≥ 2)" do
      snapshots = Enum.map([1.0, 2.0, 3.0], &snap/1)
      assert Technical.zscore(snapshots, 1) == {:error, :insufficient_data}
    end

    test "flat input (all same prices) → {:error, :insufficient_data} (stddev == 0)" do
      snapshots = Enum.map([5.0, 5.0, 5.0, 5.0, 5.0], &snap/1)
      assert Technical.zscore(snapshots, 5) == {:error, :insufficient_data}
    end
  end

  describe "streak/1" do
    test "up streak: [1,2,3,4] → days 3" do
      snapshots = Enum.map([1.0, 2.0, 3.0, 4.0], &snap/1)
      assert Technical.streak(snapshots) == {:ok, %{direction: :up, days: 3}}
    end

    test "down streak: [4,3,2,1] → days 3" do
      snapshots = Enum.map([4.0, 3.0, 2.0, 1.0], &snap/1)
      assert Technical.streak(snapshots) == {:ok, %{direction: :down, days: 3}}
    end

    test "broken by flat last pair: [1,2,3,3] → days 0" do
      snapshots = Enum.map([1.0, 2.0, 3.0, 3.0], &snap/1)
      assert Technical.streak(snapshots) == {:ok, %{direction: :up, days: 0}}
    end

    test "mixed: [1,2,3,2,3,4] → up days 2" do
      # reversed [4,3,2,3,2,1]: 4>3→:up count=1, 3>2→count=2, 2<3→stop
      snapshots = Enum.map([1.0, 2.0, 3.0, 2.0, 3.0, 4.0], &snap/1)
      assert Technical.streak(snapshots) == {:ok, %{direction: :up, days: 2}}
    end

    test "empty list → {:ok, %{direction: :up, days: 0}}" do
      assert Technical.streak([]) == {:ok, %{direction: :up, days: 0}}
    end

    test "single element → {:ok, %{direction: :up, days: 0}}" do
      assert Technical.streak([snap(5.0)]) == {:ok, %{direction: :up, days: 0}}
    end
  end
end
