defmodule Watchman.CalendarTest do
  use ExUnit.Case, async: true

  alias Watchman.Calendar

  # Concrete anchor dates used across tests:
  #   2024-01-08 = Monday
  #   2024-01-09 = Tuesday
  #   2024-01-10 = Wednesday
  #   2024-01-12 = Friday
  #   2024-01-13 = Saturday
  #   2024-01-14 = Sunday
  #   2024-01-15 = Monday  (next week)
  #   2024-01-16 = Tuesday
  #   2024-01-17 = Wednesday
  #   2024-01-19 = Friday

  describe "add_business_days/2 — basic weekday arithmetic" do
    test "Monday + 1 = Tuesday" do
      assert Calendar.add_business_days(~D[2024-01-08], 1) == ~D[2024-01-09]
    end

    test "Friday + 1 = Monday (skips weekend)" do
      assert Calendar.add_business_days(~D[2024-01-12], 1) == ~D[2024-01-15]
    end

    test "Friday + 5 = next Friday (skips one weekend)" do
      assert Calendar.add_business_days(~D[2024-01-12], 5) == ~D[2024-01-19]
    end

    test "Wednesday + 5 = next Wednesday (skips one weekend)" do
      assert Calendar.add_business_days(~D[2024-01-10], 5) == ~D[2024-01-17]
    end
  end

  describe "add_business_days/2 — starting on a weekend" do
    # Rule: weekend start → advance to next Monday first, then add N days.
    # Saturday 2024-01-13 → Monday 2024-01-15, then +1 → Tuesday 2024-01-16.
    test "Saturday + 1 = Tuesday (Saturday normalised to Monday, then +1)" do
      assert Calendar.add_business_days(~D[2024-01-13], 1) == ~D[2024-01-16]
    end

    # Sunday 2024-01-14 → Monday 2024-01-15, then +1 → Tuesday 2024-01-16.
    test "Sunday + 1 = Tuesday (Sunday normalised to Monday, then +1)" do
      assert Calendar.add_business_days(~D[2024-01-14], 1) == ~D[2024-01-16]
    end
  end

  describe "add_business_days/2 — zero days" do
    test "any date + 0 returns the same date unchanged" do
      assert Calendar.add_business_days(~D[2024-01-08], 0) == ~D[2024-01-08]
    end

    test "Saturday + 0 returns Saturday (no weekend normalisation at N=0)" do
      assert Calendar.add_business_days(~D[2024-01-13], 0) == ~D[2024-01-13]
    end
  end

  describe "add_business_days/2 — negative days" do
    test "negative days raises ArgumentError" do
      assert_raise ArgumentError, fn ->
        Calendar.add_business_days(~D[2024-01-08], -1)
      end
    end

    test "error message includes the offending value" do
      assert_raise ArgumentError, ~r/-3/, fn ->
        Calendar.add_business_days(~D[2024-01-08], -3)
      end
    end
  end
end
