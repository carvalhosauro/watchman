defmodule Watchman.Analysis.ClassifierTest do
  use ExUnit.Case, async: true

  alias Watchman.Analysis.{Classifier, Indicators}
  alias Watchman.Models.NewsItem

  # ---------------------------------------------------------------------------
  # Fixtures
  # ---------------------------------------------------------------------------

  defp ind(overrides \\ []) do
    struct!(
      %Indicators{
        sma7: 100.0,
        sma21: 100.0,
        sma50: 100.0,
        ema21: 100.0,
        rsi14: 50.0,
        zscore21: 0.0,
        streak: %{direction: :up, days: 0},
        drawdown_from_peak: 0.0
      },
      overrides
    )
  end

  defp news(overrides \\ []) do
    struct!(
      %NewsItem{source: "cvm", category: "material_fact", title: "Test disclosure"},
      overrides
    )
  end

  # ---------------------------------------------------------------------------
  # rules/0
  # ---------------------------------------------------------------------------

  describe "rules/0" do
    test "returns exactly 9 rules" do
      assert length(Classifier.rules()) == 9
    end

    test "rules are sorted by ascending priority" do
      priorities = Classifier.rules() |> Enum.map(& &1.priority)
      assert priorities == Enum.sort(priorities)
    end

    test "rule 9 is the noise fallback" do
      last = List.last(Classifier.rules())
      assert last.id == :noise
      assert last.level == :noise
      assert last.priority == 9
    end
  end

  # ---------------------------------------------------------------------------
  # total_conditions/0
  # ---------------------------------------------------------------------------

  describe "total_conditions/0" do
    test "returns a positive integer" do
      assert Classifier.total_conditions() > 0
    end

    test "equals the documented leaf count of 17" do
      assert Classifier.total_conditions() == 17
    end
  end

  # ---------------------------------------------------------------------------
  # Rule predicates — one fires + one does-not-fire per rule
  # ---------------------------------------------------------------------------

  describe "rule :high_bearish_zscore_streak (priority 1)" do
    setup do
      {:ok, rule: Enum.find(Classifier.rules(), &(&1.id == :high_bearish_zscore_streak))}
    end

    test "fires when abs(zscore21) > 2.0 AND streak down AND days >= 3", %{rule: rule} do
      assert rule.predicate.(ind(zscore21: -2.5, streak: %{direction: :down, days: 3}), [])
    end

    test "does not fire when streak days < 3", %{rule: rule} do
      refute rule.predicate.(ind(zscore21: -2.5, streak: %{direction: :down, days: 2}), [])
    end
  end

  describe "rule :high_bullish_zscore_streak (priority 2)" do
    setup do
      {:ok, rule: Enum.find(Classifier.rules(), &(&1.id == :high_bullish_zscore_streak))}
    end

    test "fires when abs(zscore21) > 2.0 AND streak up AND days >= 3", %{rule: rule} do
      assert rule.predicate.(ind(zscore21: 2.5, streak: %{direction: :up, days: 3}), [])
    end

    test "does not fire when streak is down (direction mismatch)", %{rule: rule} do
      refute rule.predicate.(ind(zscore21: 2.5, streak: %{direction: :down, days: 3}), [])
    end
  end

  describe "rule :high_material_news (priority 3)" do
    setup do
      {:ok, rule: Enum.find(Classifier.rules(), &(&1.id == :high_material_news))}
    end

    test "fires when any news item has category material_fact", %{rule: rule} do
      assert rule.predicate.(ind(), [news()])
    end

    test "fires when any news item has category financial_result", %{rule: rule} do
      assert rule.predicate.(ind(), [news(category: "financial_result")])
    end

    test "does not fire when news list is empty", %{rule: rule} do
      refute rule.predicate.(ind(), [])
    end

    test "does not fire when all news items are non-material categories", %{rule: rule} do
      refute rule.predicate.(ind(), [news(category: "other"), news(category: "dividend")])
    end
  end

  describe "rule :medium_bearish_zscore_or_streak (priority 4)" do
    setup do
      {:ok, rule: Enum.find(Classifier.rules(), &(&1.id == :medium_bearish_zscore_or_streak))}
    end

    test "fires when zscore21 < -1.5", %{rule: rule} do
      assert rule.predicate.(ind(zscore21: -1.6), [])
    end

    test "fires when streak is down and days >= 2 (even with neutral zscore)", %{rule: rule} do
      assert rule.predicate.(ind(streak: %{direction: :down, days: 2}), [])
    end

    test "does not fire when zscore is neutral and streak is up", %{rule: rule} do
      refute rule.predicate.(ind(zscore21: 0.0, streak: %{direction: :up, days: 3}), [])
    end
  end

  describe "rule :medium_bullish_zscore_or_streak (priority 5)" do
    setup do
      {:ok, rule: Enum.find(Classifier.rules(), &(&1.id == :medium_bullish_zscore_or_streak))}
    end

    test "fires when zscore21 > 1.5", %{rule: rule} do
      assert rule.predicate.(ind(zscore21: 1.6), [])
    end

    test "fires when streak is up and days >= 2 (even with neutral zscore)", %{rule: rule} do
      assert rule.predicate.(ind(streak: %{direction: :up, days: 2}), [])
    end

    test "does not fire when zscore is neutral and streak is down", %{rule: rule} do
      refute rule.predicate.(ind(zscore21: 0.0, streak: %{direction: :down, days: 3}), [])
    end
  end

  describe "rule :medium_news_volume (priority 6)" do
    setup do
      {:ok, rule: Enum.find(Classifier.rules(), &(&1.id == :medium_news_volume))}
    end

    test "fires when 2 or more news items are present", %{rule: rule} do
      assert rule.predicate.(ind(), [news(category: "other"), news(category: "dividend")])
    end

    test "does not fire when only 1 news item", %{rule: rule} do
      refute rule.predicate.(ind(), [news(category: "other")])
    end

    test "does not fire when news list is empty", %{rule: rule} do
      refute rule.predicate.(ind(), [])
    end
  end

  describe "rule :low_moderate_zscore (priority 7)" do
    setup do
      {:ok, rule: Enum.find(Classifier.rules(), &(&1.id == :low_moderate_zscore))}
    end

    test "fires when abs(zscore21) is in [0.5, 1.5]", %{rule: rule} do
      assert rule.predicate.(ind(zscore21: 0.8), [])
      assert rule.predicate.(ind(zscore21: -1.0), [])
      assert rule.predicate.(ind(zscore21: 0.5), [])
      assert rule.predicate.(ind(zscore21: 1.5), [])
    end

    test "does not fire when zscore21 is below 0.5 (flat)", %{rule: rule} do
      refute rule.predicate.(ind(zscore21: 0.3), [])
      refute rule.predicate.(ind(zscore21: 0.0), [])
    end

    test "does not fire when abs(zscore21) exceeds 1.5", %{rule: rule} do
      refute rule.predicate.(ind(zscore21: -1.6), [])
      refute rule.predicate.(ind(zscore21: 2.5), [])
    end
  end

  describe "rule :low_single_news (priority 8)" do
    setup do
      {:ok, rule: Enum.find(Classifier.rules(), &(&1.id == :low_single_news))}
    end

    test "fires when exactly 1 news item", %{rule: rule} do
      assert rule.predicate.(ind(), [news(category: "other")])
    end

    test "does not fire when 0 news items", %{rule: rule} do
      refute rule.predicate.(ind(), [])
    end

    test "does not fire when 2 or more news items", %{rule: rule} do
      refute rule.predicate.(ind(), [news(category: "other"), news(category: "dividend")])
    end
  end

  describe "rule :noise (priority 9)" do
    setup do
      {:ok, rule: Enum.find(Classifier.rules(), &(&1.id == :noise))}
    end

    test "predicate always returns true regardless of inputs", %{rule: rule} do
      assert rule.predicate.(ind(), [])
      assert rule.predicate.(ind(zscore21: -3.0), [news()])
    end
  end

  # ---------------------------------------------------------------------------
  # classify/2 — noise fallback
  # ---------------------------------------------------------------------------

  describe "classify/2 — noise signal" do
    test "returns noise when all indicators are flat and news list is empty" do
      signal = Classifier.classify(ind(), [])

      assert signal.level == :noise
      assert signal.direction == :neutral
      assert signal.reasons == []
      assert signal.confidence == 0.0
    end
  end

  # ---------------------------------------------------------------------------
  # classify/2 — direction resolution
  # ---------------------------------------------------------------------------

  describe "classify/2 — direction resolution" do
    test "bullish + bearish firing at same level → :neutral" do
      # Rule 4 fires (zscore < -1.5 → bearish medium)
      # Rule 5 fires (streak up AND days >= 2 → bullish medium)
      indicators = ind(zscore21: -1.6, streak: %{direction: :up, days: 2})
      signal = Classifier.classify(indicators, [])

      assert signal.level == :medium
      assert signal.direction == :neutral
    end

    test "all top-level rules agree on bullish → :bullish" do
      indicators = ind(zscore21: 2.5, streak: %{direction: :up, days: 3})
      signal = Classifier.classify(indicators, [])

      assert signal.level == :high
      assert signal.direction == :bullish
    end

    test "all top-level rules agree on bearish → :bearish" do
      indicators = ind(zscore21: -2.5, streak: %{direction: :down, days: 3})
      signal = Classifier.classify(indicators, [])

      assert signal.level == :high
      assert signal.direction == :bearish
    end

    test "derived direction resolves to bullish when zscore21 > 0" do
      # Rule 8 fires (1 news item, derived direction)
      indicators = ind(zscore21: 0.3)
      signal = Classifier.classify(indicators, [news(category: "other")])

      assert signal.level == :low
      assert signal.direction == :bullish
    end

    test "derived direction resolves to bearish when zscore21 < 0" do
      indicators = ind(zscore21: -0.3)
      signal = Classifier.classify(indicators, [news(category: "other")])

      assert signal.level == :low
      assert signal.direction == :bearish
    end

    test "derived direction resolves to neutral when zscore21 == 0.0" do
      indicators = ind(zscore21: 0.0)
      signal = Classifier.classify(indicators, [news(category: "other")])

      assert signal.level == :low
      assert signal.direction == :neutral
    end
  end

  # ---------------------------------------------------------------------------
  # classify/2 — level priority
  # ---------------------------------------------------------------------------

  describe "classify/2 — level priority" do
    test "high-priority rule determines level when medium rule also fires" do
      # Rule 2 (high bullish) fires; Rule 5 (medium bullish) also fires
      indicators = ind(zscore21: 2.5, streak: %{direction: :up, days: 3})
      signal = Classifier.classify(indicators, [])

      assert signal.level == :high
    end
  end

  # ---------------------------------------------------------------------------
  # classify/2 — confidence math
  # ---------------------------------------------------------------------------

  describe "classify/2 — confidence" do
    test "exact ratio: 1 rule fires → confidence == 1 / total_conditions" do
      # Only rule 4 fires: zscore=-1.6 (< -1.5), up streak (days=0, rule 4 needs :down streak OR zscore)
      indicators = ind(zscore21: -1.6, streak: %{direction: :up, days: 0})
      signal = Classifier.classify(indicators, [])

      assert signal.confidence == 1 / Classifier.total_conditions()
    end

    test "confidence scales with number of firing rules" do
      # Rules 1 + 4 fire: zscore=-2.5, down streak days=3
      indicators = ind(zscore21: -2.5, streak: %{direction: :down, days: 3})
      signal_one_rule = Classifier.classify(ind(zscore21: -1.6), [])
      signal_two_rules = Classifier.classify(indicators, [])

      assert signal_two_rules.confidence > signal_one_rule.confidence
    end

    test "confidence is 0.0 when no substantive rule fires" do
      signal = Classifier.classify(ind(), [])
      assert signal.confidence == 0.0
    end

    test "confidence is capped at 1.0" do
      # We cannot realistically exceed 1.0 with 17 total_conditions and 8 rules,
      # but verify the cap holds for the maximum possible case
      # (all 8 substantive rules — some are mutually exclusive, so 4 fire here)
      indicators = ind(zscore21: -2.5, streak: %{direction: :down, days: 3})
      news_items = [news(), news(category: "financial_result")]
      signal = Classifier.classify(indicators, news_items)

      assert signal.confidence <= 1.0
    end
  end

  # ---------------------------------------------------------------------------
  # classify/2 — reasons list
  # ---------------------------------------------------------------------------

  describe "classify/2 — reasons" do
    test "reasons list is ordered by rule priority" do
      # Rules 1 (p1), 3 (p3), 4 (p4), 6 (p6) fire
      indicators = ind(zscore21: -2.5, streak: %{direction: :down, days: 3})
      news_items = [news(), news(category: "other")]
      signal = Classifier.classify(indicators, news_items)

      assert length(signal.reasons) == 4
      # First reason is from rule 1 (zscore+streak)
      assert hd(signal.reasons) =~ "below 21-day average"
    end

    test "noise signal has an empty reasons list" do
      signal = Classifier.classify(ind(), [])
      assert signal.reasons == []
    end

    test "each fired rule contributes exactly one reason string" do
      indicators = ind(zscore21: -2.5, streak: %{direction: :down, days: 3})
      signal = Classifier.classify(indicators, [])

      # Rules 1 and 4 fire → 2 reasons
      assert length(signal.reasons) == 2
      assert Enum.all?(signal.reasons, &is_binary/1)
    end
  end

  # ---------------------------------------------------------------------------
  # classify/2 — reason content
  # ---------------------------------------------------------------------------

  describe "classify/2 — reason content" do
    test "high bearish reason includes zscore and streak day count" do
      indicators = ind(zscore21: -2.5, streak: %{direction: :down, days: 3})
      signal = Classifier.classify(indicators, [])

      assert Enum.any?(signal.reasons, &(&1 =~ "2.5σ below 21-day average"))
      assert Enum.any?(signal.reasons, &(&1 =~ "3 consecutive down days"))
    end

    test "material news reason includes uppercased source and title" do
      indicators = ind(zscore21: -0.5)
      signal = Classifier.classify(indicators, [news(source: "cvm", title: "Major event")])

      assert Enum.any?(signal.reasons, fn r ->
               r =~ "CVM" and r =~ "Major event"
             end)
    end

    test "medium bearish reason uses zscore when zscore branch triggers" do
      indicators = ind(zscore21: -1.8, streak: %{direction: :up, days: 0})
      signal = Classifier.classify(indicators, [])

      assert Enum.any?(signal.reasons, &(&1 =~ "below 21-day average"))
    end

    test "medium bearish reason uses streak days when streak branch triggers" do
      indicators = ind(zscore21: 0.0, streak: %{direction: :down, days: 2})
      signal = Classifier.classify(indicators, [])

      assert Enum.any?(signal.reasons, &(&1 =~ "consecutive down days"))
    end
  end
end
