# Track 1 — Accuracy Tracking (v0.3.0)

Concrete prep for the first realignment track. See
[`REALIGNMENT.md`](REALIGNMENT.md) for the broader rationale.

## Goal

Close the feedback loop on past analyses using data already in the database.
Add `wm accuracy` so users can answer:

> *Were watchman's calls actually right? How often? Which provider does
> best on which ticker?*

Zero new APIs. Zero new dependencies. The only new external touchpoint is
the `wm accuracy` CLI.

## Recommendation taxonomy

The existing `analyses.recommendation` field is constrained to:

```elixir
~w(manter investigar vender)
```

Mapped to expected price behavior over the lookahead window:

| Recommendation | Expectation                | Hit when                            |
|----------------|----------------------------|-------------------------------------|
| `manter`       | hold value, no major drop  | `variation_pct >= -drop_threshold`  |
| `vender`       | price falls                | `variation_pct <= -drop_threshold`  |
| `investigar`   | uncertain — observe only   | not scored (outcome stored as `neutral`) |

`drop_threshold` default: **3.0%**. Configurable via TOML
(`[accuracy] drop_threshold_pct`).

Storing `investigar` outcomes as `neutral` means they still get an
`observed_variation` audit record, but the global hit-rate denominator
excludes them. Per-provider reports can opt in via `--include-neutral`.

## Schema — `analysis_outcomes`

```
analysis_outcomes
├── id                   integer, pk
├── analysis_id          fk → analyses.id, NOT NULL, UNIQUE
├── lookahead_days       integer, NOT NULL
├── baseline_price       float,   NOT NULL   -- copy from analysis snapshot for audit
├── observed_price       float,   NOT NULL   -- price at evaluated_at
├── observed_snapshot_id fk → price_snapshots.id, NOT NULL
├── variation_pct        float,   NOT NULL
├── outcome              string,  NOT NULL   -- "hit" | "miss" | "neutral"
├── drop_threshold_pct   float,   NOT NULL   -- snapshot of config at evaluation time
├── evaluated_at         utc_datetime, NOT NULL
└── inserted_at          utc_datetime
```

Indices:

- `unique(analysis_id)` — one outcome per analysis
- `index(outcome)` — group-by in queries
- `index(evaluated_at)` — date range filters

`UNIQUE(analysis_id)` makes the closer step idempotent: if a previous run
already closed an outcome, re-running is a no-op.

## Migration draft

```elixir
defmodule Watchman.Repo.Migrations.AddAnalysisOutcomes do
  use Ecto.Migration

  def change do
    create table(:analysis_outcomes) do
      add :analysis_id,          references(:analyses, on_delete: :delete_all), null: false
      add :lookahead_days,       :integer, null: false
      add :baseline_price,       :float,   null: false
      add :observed_price,       :float,   null: false
      add :observed_snapshot_id, references(:price_snapshots, on_delete: :nilify_all), null: false
      add :variation_pct,        :float,   null: false
      add :outcome,              :string,  null: false
      add :drop_threshold_pct,   :float,   null: false
      add :evaluated_at,         :utc_datetime, null: false

      timestamps(type: :utc_datetime, updated_at: false)
    end

    create unique_index(:analysis_outcomes, [:analysis_id])
    create index(:analysis_outcomes, [:outcome])
    create index(:analysis_outcomes, [:evaluated_at])
  end
end
```

Filename: `priv/repo/migrations/<UTC-stamp>_add_analysis_outcomes.exs`.

## Outcome closer — invoked inside `wm run`

Placed at the **top** of `Watchman.Pipeline.run/0`, before the
`Task.async_stream` over assets:

```
For each analysis A where:
  - no row exists in analysis_outcomes for A
  - A.analyzed_at + lookahead_days <= today
  - A.snapshot_id is not nil
do:
  baseline = A.snapshot.price
  observed = most recent PriceSnapshot for A.asset_id
             with fetched_at >= (A.analyzed_at + lookahead_days)
  if observed is nil: skip (not enough history yet — retry next run)
  variation_pct = (observed.price - baseline) / baseline * 100
  outcome = classify(A.recommendation, variation_pct, drop_threshold)
  insert analysis_outcomes row
```

`lookahead_days` default: 5 business days, configurable via TOML
(`[accuracy] lookahead_days`).

Business-day math: skip Saturday/Sunday. Holidays not handled in v0.3.0 —
documented as a known limitation, fix in v0.7.0 if it matters.

## Query layer — `Watchman.Accuracy`

Public API:

```elixir
@spec report(keyword()) ::
  %{
    by_ticker:   [%{ticker: String.t(), hits: integer, misses: integer, neutral: integer, hit_rate: float}],
    by_provider: [%{provider: String.t(), hits: integer, misses: integer, neutral: integer, hit_rate: float}],
    overall:     %{hits: integer, misses: integer, neutral: integer, hit_rate: float},
    window:      %{from: Date.t() | nil, to: Date.t() | nil, lookahead_days: integer}
  }

# Options:
#   :ticker            String.t() | nil
#   :provider          String.t() | nil
#   :lookahead_days    integer (filter)  — default: nil (any)
#   :since             Date.t() | nil
#   :include_neutral   boolean — default: false
```

Implementation: a single `from` query joining `analysis_outcomes`,
`analyses`, and `assets`, grouped and counted. No raw SQL.

`hit_rate = hits / (hits + misses)` (neutral excluded by default).
Returns `0.0` when denominator is zero — no `:nan`, no `:undefined`.

## CLI surface — `wm accuracy`

```
wm accuracy                              # overall, per-ticker, per-provider
wm accuracy --ticker PETR4               # filter by asset
wm accuracy --provider claude            # filter by AI provider used
wm accuracy --days 10                    # show outcomes evaluated with 10-day lookahead
wm accuracy --since 2026-01-01           # only analyses from that date
wm accuracy --include-neutral            # roll investigar into the denominator
```

Output (example):

```
Accuracy — lookahead 5 business days, since 2026-01-01

By ticker:
  PETR4   12 hits   3 misses   2 neutral   hit rate 80.0%
  MXRF11   8 hits   2 misses   0 neutral   hit rate 80.0%
  ITUB4    5 hits   5 misses   1 neutral   hit rate 50.0%

By provider:
  claude    18 hits   4 misses   2 neutral   hit rate 81.8%
  gemini     7 hits   6 misses   1 neutral   hit rate 53.8%

Overall:   25 hits  10 misses   3 neutral   hit rate 71.4%
```

Empty-state message: `"No outcomes recorded yet. Outcomes are evaluated <lookahead_days> business days after each analysis."`.

## Test plan

| Layer | Cases |
|-------|-------|
| Migration | applies cleanly, drops cleanly, indices present |
| `Accuracy.classify_outcome/3` (pure) | hit/miss/neutral for each recommendation × variation combo, boundary at exact threshold |
| Outcome closer | inserts when lookahead elapsed; skips when not enough history; idempotent on rerun (UNIQUE constraint); honors `drop_threshold_pct` from config |
| `Accuracy.report/1` | filters by ticker/provider/since/lookahead; groups correctly; handles zero denominator; `--include-neutral` toggles denominator |
| `wm accuracy` CLI | parses all flags; routes to `Accuracy.report/1`; formats tabular output; empty-state copy |
| Business-day math | `+5` business days skips weekends; explicit fixtures for Friday → Friday |

All DB tests run inside `Ecto.Adapters.SQL.Sandbox`. Pure-function tests
have no DB.

## Task list — ordered, ready to claim

1. **Migration** — `analysis_outcomes` table + indices + Ecto model.
2. **Pure classifier** — `Accuracy.classify_outcome(recommendation, variation_pct, drop_threshold)` returning `:hit | :miss | :neutral`. Heavily fixtured tests.
3. **Business-day helper** — small `Watchman.Calendar` (or inlined private fn) with `+N` business days math. Tests against known weekends.
4. **Closer step** — `Watchman.Accuracy.close_pending_outcomes/0`, idempotent, persists via the new model.
5. **Wire closer into pipeline** — single call at top of `Pipeline.run/0`, before `maybe_warn_brapi_usage`. Logged at info level.
6. **Config keys** — `[accuracy] lookahead_days`, `[accuracy] drop_threshold_pct` in `Watchman.Config` with sensible defaults (5, 3.0).
7. **Report query** — `Watchman.Accuracy.report/1` with all filter options. Sandbox tests.
8. **CLI** — `wm accuracy` dispatch + `OptionParser` + formatter. CaptureIO tests.
9. **Docs** — README CLI section (already has placeholder), `wm` usage block, completions update.
10. **Release** — bump `mix.exs` to `0.3.0`, update CHANGELOG via git-cliff, PR to `dev`.

Each step is independently committable; each ends with `mix quality` clean.

## Hard constraints reminder

- Do not touch `Pipeline` orchestration beyond the single closer call (step 5).
- Do not touch `Setup`, `Scheduler`, `Config` *structure* — only add new keys via `toml_get/1`.
- No raw SQL.
- `mix credo --strict` passes before each commit.
- Every public function has `@spec`. Every new module has `@moduledoc`.
