defmodule Watchman.Analysis.TechnicalTest do
  use ExUnit.Case, async: true

  alias Watchman.Analysis.{Indicators, Technical}
  alias Watchman.Models.PriceSnapshot

  defp snap(price), do: %PriceSnapshot{price: price}
  defp snaps_seq(n), do: for(i <- 1..n, do: snap(100.0 + i / 10))

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
    # SMA-seeded EMA convention LOCK:
    # A first-price-seeded EMA (ema_0 = first_price = 10.0) on this same
    # series would produce a different value at step 5. The 14.875 here
    # only matches SMA-seeding (ema_0 = sma3 of first 3 prices = 12.0).
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
    # Wilder smoothing convention LOCK:
    # A simple-average RSI (avg_gain/avg_loss recomputed as plain means
    # over all deltas each step) on this series would give a different
    # final rs and rsi. The 75.0 only matches Wilder's recurrence:
    #   ag_n = (ag_(n-1) * (period - 1) + max(d, 0)) / period
    test "reference: Wilder-smoothed period 3 → 75.0" do
      snapshots = Enum.map([3.0, 4.0, 3.0, 5.0, 4.0, 6.0], &snap/1)
      {:ok, result} = Technical.rsi(snapshots, 3)
      assert_in_delta result, 75.0, 1.0e-4
    end

    test "all-gain (monotonically increasing) → 100.0" do
      snapshots = Enum.map([1.0, 2.0, 3.0, 4.0], &snap/1)
      assert Technical.rsi(snapshots, 3) == {:ok, 100.0}
    end

    test "period + 1 snapshots is the minimum legal input (all-gain → 100.0)" do
      # period = 3 needs 4 snapshots minimum. All-gain → avg_loss = 0 → 100.0
      snapshots = Enum.map([1.0, 2.0, 3.0, 4.0], &snap/1)
      {:ok, rsi} = Technical.rsi(snapshots, 3)
      assert_in_delta rsi, 100.0, 1.0e-9
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

    test "period = 2 (lowest legal value) computes sample stddev correctly" do
      # prices = [1.0, 3.0], period 2
      # mean = 2.0
      # sample variance = ((1-2)^2 + (3-2)^2) / (2-1) = 2.0
      # stddev = sqrt(2) ≈ 1.41421
      # z = (3 - 2) / 1.41421 ≈ 0.70711
      snapshots = Enum.map([1.0, 3.0], &snap/1)
      {:ok, z} = Technical.zscore(snapshots, 2)
      assert_in_delta z, 0.70711, 1.0e-4
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

    test "default period 21 used when called with 1 argument" do
      # 20 snapshots → insufficient with default period 21
      assert Technical.zscore(snaps_seq(20)) == {:error, :insufficient_data}
      # 21 snapshots, non-flat → ok
      assert {:ok, _} = Technical.zscore(snaps_seq(21))
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

    test "flat pair MID-sequence resets streak; counts subsequent direction only" do
      # [1,2,3,3,4,5]: the 3->3 flat breaks the streak. After the flat, 3->4 and
      # 4->5 are two up days. streak/1 walks from newest back and stops at the
      # flat, so days = 2 (not 4).
      snapshots = Enum.map([1.0, 2.0, 3.0, 3.0, 4.0, 5.0], &snap/1)
      assert Technical.streak(snapshots) == {:ok, %{direction: :up, days: 2}}
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

  describe "drawdown/2" do
    test "at peak: [8,9,10] period 3 → 0.0" do
      snapshots = Enum.map([8.0, 9.0, 10.0], &snap/1)
      assert Technical.drawdown(snapshots, 3) == {:ok, 0.0}
    end

    test "20% drawdown: [10,9,8] period 3 → -20.0" do
      snapshots = Enum.map([10.0, 9.0, 8.0], &snap/1)
      {:ok, result} = Technical.drawdown(snapshots, 3)
      assert_in_delta result, -20.0, 1.0e-4
    end

    test "mid-history peak: [5,10,8] period 3 → -20.0" do
      snapshots = Enum.map([5.0, 10.0, 8.0], &snap/1)
      {:ok, result} = Technical.drawdown(snapshots, 3)
      assert_in_delta result, -20.0, 1.0e-4
    end

    test "insufficient: length < period → {:error, :insufficient_data}" do
      snapshots = Enum.map([1.0, 2.0], &snap/1)
      assert Technical.drawdown(snapshots, 5) == {:error, :insufficient_data}
    end
  end

  describe "indicators/1" do
    test "happy path: 60 monotonic snapshots → fully populated %Indicators{}" do
      snapshots = snaps_seq(60)
      assert {:ok, %Indicators{} = ind} = Technical.indicators(snapshots)
      assert is_float(ind.sma7)
      assert is_float(ind.sma21)
      assert is_float(ind.sma50)
      assert is_float(ind.ema21)
      assert ind.rsi14 >= 0.0 and ind.rsi14 <= 100.0
      assert is_float(ind.zscore21)
      assert ind.streak.direction in [:up, :down]
      assert is_integer(ind.streak.days) and ind.streak.days >= 0
      assert ind.drawdown_from_peak <= 0.0
    end

    test "happy path at exactly 50 snapshots (the documented floor)" do
      snapshots = for i <- 1..50, do: snap(100.0 + i / 10)
      assert {:ok, %Watchman.Analysis.Indicators{}} = Technical.indicators(snapshots)
    end

    test "insufficient: 49 snapshots → {:error, :insufficient_data}" do
      assert Technical.indicators(snaps_seq(49)) == {:error, :insufficient_data}
    end

    test "insufficient: empty list → {:error, :insufficient_data}" do
      assert Technical.indicators([]) == {:error, :insufficient_data}
    end

    test "sub-failure (flat input, zscore stddev=0) → {:error, :insufficient_data}" do
      # 50+ flat snapshots: zscore/2 returns :insufficient_data, triggers with-else branch
      snapshots = for _ <- 1..60, do: snap(100.0)
      assert Technical.indicators(snapshots) == {:error, :insufficient_data}
    end
  end
end
