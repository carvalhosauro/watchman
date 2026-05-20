defmodule Watchman.Calendar do
  @moduledoc """
  Pure calendar helpers for business-day arithmetic.

  ## Weekend rule

  If the starting date falls on a Saturday or Sunday, it is first advanced to
  the following Monday before counting business days.  So `Saturday + 0` returns
  Saturday itself (N=0 short-circuits before any adjustment), but
  `Saturday + 1` returns Tuesday.

  ## N = 0

  When `days` is 0 the input date is returned unchanged, regardless of whether
  it falls on a weekend.

  ## Negative N

  Passing a negative value for `days` raises `ArgumentError`. Backward
  business-day arithmetic is not supported in v0.3.0.

  ## Holidays

  Holidays are **not** handled. Only Saturday and Sunday are treated as
  non-business days. This is a known v0.3.0 simplification.
  """

  @spec add_business_days(Date.t(), integer()) :: Date.t()
  def add_business_days(%Date{} = date, 0), do: date

  def add_business_days(%Date{}, days) when is_integer(days) and days < 0 do
    raise ArgumentError, "days must be non-negative, got: #{days}"
  end

  def add_business_days(%Date{} = date, days) when is_integer(days) do
    date
    |> skip_to_weekday()
    |> advance(days)
  end

  # ---------------------------------------------------------------------------
  # Private helpers
  # ---------------------------------------------------------------------------

  # Advance from a weekday by exactly `n` business days.
  defp advance(date, 0), do: date

  defp advance(date, n) do
    next =
      date
      |> Date.add(1)
      |> skip_to_weekday()

    advance(next, n - 1)
  end

  # Move a weekend date forward to the next Monday; weekdays are unchanged.
  defp skip_to_weekday(date) do
    case Date.day_of_week(date) do
      6 -> Date.add(date, 2)
      7 -> Date.add(date, 1)
      _ -> date
    end
  end
end
