defmodule Watchman.Analysis.SignalFormatterTest do
  use ExUnit.Case, async: true

  alias Watchman.Analysis.{Signal, SignalFormatter}

  # ---------------------------------------------------------------------------
  # Fixtures
  # ---------------------------------------------------------------------------

  defp sig(overrides) do
    struct!(
      %Signal{level: :high, direction: :bearish, reasons: [], confidence: 0.0},
      overrides
    )
  end

  # ---------------------------------------------------------------------------
  # format/1 — noise
  # ---------------------------------------------------------------------------

  describe "format/1 — noise signal" do
    test "returns the fixed noise string regardless of direction or confidence" do
      signal = sig(level: :noise, direction: :neutral, reasons: [], confidence: 0.0)
      assert SignalFormatter.format(signal) == "NOISE — no actionable signal."
    end
  end

  # ---------------------------------------------------------------------------
  # format/1 — high level
  # ---------------------------------------------------------------------------

  describe "format/1 — high bearish signal" do
    test "renders level, direction, confidence, and reasons block" do
      signal =
        sig(
          level: :high,
          direction: :bearish,
          reasons: [
            "Price is 2.3σ below 21-day average",
            "3 consecutive down days"
          ],
          confidence: 0.75
        )

      result = SignalFormatter.format(signal)

      assert result =~ "HIGH BEARISH signal (confidence 0.75)"
      assert result =~ "Reasons:"
      assert result =~ "- Price is 2.3σ below 21-day average"
      assert result =~ "- 3 consecutive down days"
    end

    test "produces a multi-line string with header on first line" do
      signal =
        sig(
          level: :high,
          direction: :bearish,
          reasons: ["Price is 2.3σ below 21-day average"],
          confidence: 0.75
        )

      lines = signal |> SignalFormatter.format() |> String.split("\n")

      assert hd(lines) == "HIGH BEARISH signal (confidence 0.75)"
    end
  end

  # ---------------------------------------------------------------------------
  # format/1 — medium level
  # ---------------------------------------------------------------------------

  describe "format/1 — medium bullish signal" do
    test "renders MEDIUM BULLISH with correct confidence" do
      signal =
        sig(
          level: :medium,
          direction: :bullish,
          reasons: ["Price is 1.8σ above 21-day average"],
          confidence: 0.12
        )

      result = SignalFormatter.format(signal)

      assert result =~ "MEDIUM BULLISH signal (confidence 0.12)"
      assert result =~ "- Price is 1.8σ above 21-day average"
    end
  end

  # ---------------------------------------------------------------------------
  # format/1 — low level
  # ---------------------------------------------------------------------------

  describe "format/1 — low signal" do
    test "renders LOW with derived neutral direction" do
      signal =
        sig(
          level: :low,
          direction: :neutral,
          reasons: ["Z-score 0.8σ within moderate range"],
          confidence: 0.06
        )

      result = SignalFormatter.format(signal)

      assert result =~ "LOW NEUTRAL signal (confidence 0.06)"
      assert result =~ "- Z-score 0.8σ within moderate range"
    end
  end

  # ---------------------------------------------------------------------------
  # format/1 — reasons list sizes
  # ---------------------------------------------------------------------------

  describe "format/1 — reasons list" do
    test "single reason produces one bullet line" do
      signal =
        sig(
          level: :medium,
          direction: :bearish,
          reasons: ["Price is 1.6σ below 21-day average"],
          confidence: 0.06
        )

      result = SignalFormatter.format(signal)
      bullet_lines = result |> String.split("\n") |> Enum.filter(&String.starts_with?(&1, "- "))

      assert length(bullet_lines) == 1
    end

    test "multiple reasons each appear on their own bullet line" do
      signal =
        sig(
          level: :high,
          direction: :bearish,
          reasons: [
            "Price is 2.3σ below 21-day average",
            "3 consecutive down days",
            "Material fact disclosed by CVM: Major event"
          ],
          confidence: 0.18
        )

      result = SignalFormatter.format(signal)
      bullet_lines = result |> String.split("\n") |> Enum.filter(&String.starts_with?(&1, "- "))

      assert length(bullet_lines) == 3
    end

    test "reasons appear in the order given" do
      signal =
        sig(
          level: :high,
          direction: :bearish,
          reasons: ["First reason", "Second reason"],
          confidence: 0.12
        )

      result = SignalFormatter.format(signal)
      lines = String.split(result, "\n")

      first_bullet_idx = Enum.find_index(lines, &String.starts_with?(&1, "- First"))
      second_bullet_idx = Enum.find_index(lines, &String.starts_with?(&1, "- Second"))

      assert first_bullet_idx < second_bullet_idx
    end
  end
end
