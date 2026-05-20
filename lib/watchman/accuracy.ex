defmodule Watchman.Accuracy do
  @moduledoc """
  Stores realized outcomes for analyses post-lookahead and provides the
  classification and reporting API for accuracy tracking.

  `classify_outcome/3` implements the recommendation-vs-variation rule:
  given a recommendation string and the price variation observed after the
  lookahead window, it returns `:hit`, `:miss`, or `:neutral`.

  `investigar` outcomes are stored as `:neutral` — they receive an audit
  record but are excluded from the global hit-rate denominator by default.
  """

  @spec classify_outcome(String.t(), float(), float()) :: :hit | :miss | :neutral
  def classify_outcome("manter", variation_pct, drop_threshold_pct) do
    if variation_pct >= -drop_threshold_pct, do: :hit, else: :miss
  end

  def classify_outcome("vender", variation_pct, drop_threshold_pct) do
    if variation_pct <= -drop_threshold_pct, do: :hit, else: :miss
  end

  def classify_outcome("investigar", _variation_pct, _drop_threshold_pct), do: :neutral
end
