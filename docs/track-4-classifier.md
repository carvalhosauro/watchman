# Track 4 — Signal Classifier + Pipeline integration (v0.6.0)

Concrete prep for the fourth realignment track. See
[`REALIGNMENT.md`](REALIGNMENT.md) for the broader rationale.

## Status — shipped v0.6.0

Track 4 shipped on branch `dev`. 456 tests pass, 0 failures. Total
coverage 75.12% (above the 60 threshold).
`Watchman.Analysis.Classifier` at 98.33%; `Signal`, `SignalFormatter`,
`Classifier.Rule`, `Indicators`, `Technical` all at 100%.

Implementation walked the 12-step ordered task list at the bottom of
this document. The team-mode split landed in this order:

- worker-classifier → `Watchman.Analysis.Classifier` (9-rule engine
  via grouped private functions because Elixir cannot escape
  anonymous functions through module attributes) + `SignalFormatter`
- worker-schema → migration adding `signal_level / signal_direction
  / signal_reasons / signal_confidence` to `analyses` plus indices,
  changeset validation via `Signal.levels/0` / `directions/0`
- worker-ai → `analyze/4` callback alongside the existing `analyze/2`,
  Claude/Gemini/Deepseek prompt updates, `Shared.recommendation_from_signal/1`
  taxonomy bridge
- worker-alerts → `Dispatcher.maybe_notify_signal/3` +
  `[alerts.signal]` config readers
- lead → `Pipeline` rewrite (news + history + indicators + signal +
  AI enrichment with graceful fallback), version bump, docs

`Track 5` (v0.7.0 daemon paradigm shift) reuses this Pipeline — only
the invocation site changes (from `wm run` to a GenServer
scheduler).

## Goal

Produce a deterministic `%Signal{}` for every analyzed asset on every
pipeline run. The signal is computed by a pure rule engine from
indicators + news. The AI provider (when configured) receives the
signal as context and writes a narrative on top — it no longer
classifies from scratch.

```
wm run
 ├── close pending outcomes (Track 1)
 ├── for each asset (Task.async_stream):
 │   ├── fetch price (existing)         ─┐
 │   ├── fetch news (Track 3)           ─┤ parallel
 │   ├── load last 50 snapshots         ─┘
 │   ├── compute %Indicators{} (Track 2)
 │   ├── classify %Signal{}             (Track 4 — new)
 │   ├── if AI configured:
 │   │     enrich with narrative using Signal as context
 │   │   else:
 │   │     format Signal directly
 │   ├── persist Analysis + NewsItems
 │   └── maybe dispatch alerts
 └── print summary
```

## Module surface

### `Watchman.Analysis.Signal` struct

```elixir
defmodule Watchman.Analysis.Signal do
  @enforce_keys [:level, :direction, :reasons, :confidence]

  defstruct [:level, :direction, :reasons, :confidence]

  @type level :: :high | :medium | :low | :noise
  @type direction :: :bullish | :bearish | :neutral

  @type t :: %__MODULE__{
          level: level(),
          direction: direction(),
          reasons: [String.t()],
          confidence: float()
        }
end
```

### `Watchman.Analysis.Classifier`

```elixir
defmodule Watchman.Analysis.Classifier do
  alias Watchman.Analysis.{Indicators, Signal}
  alias Watchman.Models.NewsItem

  @spec classify(Indicators.t(), [NewsItem.t()]) :: Signal.t()
  def classify(%Indicators{} = indicators, news_items)
end
```

Pure function. No DB, no side effects, no raises.

## Rule engine

Rules are an **ordered list of rule structs**, not nested conditionals.
Each rule has a predicate and an output (level + direction +
reason-string template). The engine walks the list, collects every
rule that fires, then picks the highest-severity match.

```elixir
defmodule Watchman.Analysis.Classifier.Rule do
  @enforce_keys [:id, :priority, :level, :direction, :predicate, :reason]

  defstruct [:id, :priority, :level, :direction, :predicate, :reason]

  @type t :: %__MODULE__{
          id: atom(),                                      # :high_bearish_zscore_streak | ...
          priority: pos_integer(),                         # 1 (highest) ... N (lowest)
          level: Signal.level(),
          direction: Signal.direction(),
          predicate: (Indicators.t(), [NewsItem.t()] -> boolean()),
          reason: (Indicators.t(), [NewsItem.t()] -> String.t())
        }
end
```

`Classifier.rules/0` returns the full ordered list (frozen at compile
time via `@rules` module attribute) so callers can introspect.
Configuration override via `Application.get_env(:watchman,
:classifier_rules)` for tests and future experimentation.

## Classification rules (priority order)

From `docs/REALIGNMENT.md` Track 4 section, restated here as the
canonical list:

| Priority | id | level | direction | Predicate |
|---|---|---|---|---|
| 1 | `:high_bearish_zscore_streak` | `:high` | `:bearish` | `abs(zscore21) > 2.0 AND streak.direction == :down AND streak.days >= 3` |
| 2 | `:high_bullish_zscore_streak` | `:high` | `:bullish` | `abs(zscore21) > 2.0 AND streak.direction == :up AND streak.days >= 3` |
| 3 | `:high_material_news` | `:high` | derived* | any news item with `category in ["material_fact", "financial_result"]` |
| 4 | `:medium_bearish_zscore_or_streak` | `:medium` | `:bearish` | `zscore21 < -1.5 OR (streak.direction == :down AND streak.days >= 2)` |
| 5 | `:medium_bullish_zscore_or_streak` | `:medium` | `:bullish` | `zscore21 > 1.5 OR (streak.direction == :up AND streak.days >= 2)` |
| 6 | `:medium_news_volume` | `:medium` | derived* | `length(news_items) >= 2` |
| 7 | `:low_moderate_zscore` | `:low` | derived* | `abs(zscore21) between 0.5 and 1.5` |
| 8 | `:low_single_news` | `:low` | derived* | `length(news_items) == 1` |
| 9 | `:noise` | `:noise` | `:neutral` | default fallback (no other rule fired) |

(*) "derived" means the direction is computed from the same
indicators that triggered the rule. The reason-string carries the
specific signal source ("material fact disclosed by CVM",
"2 news items", "z-score 1.1σ", etc.).

### Direction resolution

When multiple rules fire and they disagree on direction (e.g.,
`:high_bullish_zscore_streak` fires AND `:high_material_news` fires
on a bearish material fact), the engine returns
`direction: :neutral` and `reasons` lists both contributing rules.

Explicit cases:
- All firing rules agree → that direction.
- Bullish + bearish present → `:neutral`.
- Only "derived" rules fire and indicators are flat → `:neutral`.

### Reasons

`reasons` is a list of human-readable English strings, one per fired
rule. Each rule's `reason` field is a function taking
`(Indicators.t(), [NewsItem.t()])` so the message can include
specific numbers:

- `"Price is 2.3σ below 21-day average"`
- `"3 consecutive down days"`
- `"Material fact disclosed by CVM: <truncated title>"`

Reasons are deterministic from inputs — same inputs always produce
the same list in the same order.

### Confidence

```
confidence = matched_conditions / total_evaluated_conditions
           |> min(1.0)
```

`total_evaluated_conditions` is fixed at compile time (the number of
distinct atomic predicates inside the rule set — count the boolean
clauses, not the rules). A rule firing because of a compound `OR`
counts as one matched condition.

Pin the exact denominator in `@total_conditions` module attribute and
expose it via `Classifier.total_conditions/0` for the test that
asserts confidence math.

## Pipeline rewrite

`Watchman.Pipeline.run/0` is rewritten end-to-end. The closer call at
the top stays (Track 1). The per-asset loop changes shape:

```elixir
defp analyze_asset(asset) do
  today = Date.utc_today()

  if already_analyzed_today?(asset.id, today) do
    {:skip, asset.ticker}
  else
    do_analyze(asset)
  end
end

defp do_analyze(asset) do
  # 1. Parallel fetch: price + news, plus DB load of history
  {price_task, news_task, history_task} = launch_fetches(asset)

  with {:ok, price_data}   <- Task.await(price_task, fetch_timeout()),
       {:ok, news_items}   <- safe_await(news_task),
       {:ok, history}      <- Task.await(history_task, fetch_timeout()),
       {:ok, snapshot}     <- persist_snapshot(asset, price_data),
       {:ok, indicators}   <- Technical.indicators([snapshot | history]),
       %Signal{} = signal  <- Classifier.classify(indicators, news_items),
       {:ok, analysis}     <- persist_analysis(asset, snapshot, signal, news_items),
       :ok                 <- persist_news(asset, news_items),
       :ok                 <- maybe_dispatch_alerts(asset, signal) do
    {:ok, asset.ticker, signal}
  end
end
```

`safe_await/1` lets news failure degrade to `{:ok, []}` (Track 3
contract: pipeline must not break on news provider failure).

`maybe_enrich_with_ai/4` runs after `persist_analysis/4` and updates
the analysis row's narrative fields if and only if AI is configured.
It receives `(asset, snapshot, signal, news_items)` and the AI
provider's prompt must reference the signal rather than re-derive it.

## Schema changes

The `analyses` table extends to store the `%Signal{}` alongside the
existing AI-derived recommendation. New columns:

- `signal_level` :string NOT NULL (in `~w(high medium low noise)`)
- `signal_direction` :string NOT NULL (in `~w(bullish bearish neutral)`)
- `signal_reasons` :text NOT NULL (JSON-encoded list of strings)
- `signal_confidence` :float NOT NULL

The existing `recommendation` column stays but becomes optional
(nullable) — the `%Signal{}` is the authoritative classification.
`Accuracy.classify_outcome/3` keeps reading from `recommendation`
because that's the human-facing label (manter/investigar/vender);
v0.6.x can add a parallel signal-based accuracy report.

Migration adds the four columns with sensible defaults so existing
rows survive:

```elixir
alter table(:analyses) do
  add :signal_level,      :string, null: false, default: "noise"
  add :signal_direction,  :string, null: false, default: "neutral"
  add :signal_reasons,    :text,   null: false, default: "[]"
  add :signal_confidence, :float,  null: false, default: 0.0
end

create index(:analyses, [:signal_level])
create index(:analyses, [:signal_direction])
```

`Watchman.Models.Analysis.changeset/2` validates inclusion on the two
string columns and accepts the float + JSON-encoded text without
restriction.

## AI prompt update

`Watchman.AI.Provider.analyze/2` becomes
`analyze/3` (or accepts an opts keyword) so it can receive the
pre-computed `%Signal{}` alongside the asset + snapshot. Each existing
adapter (`Claude`, `Gemini`, `Deepseek`) updates its prompt to:

1. State the deterministic signal explicitly:
   `"Signal: HIGH BEARISH (confidence 0.78). Reasons: Price 2.3σ below
   21-day average; 3 consecutive down days; Material fact disclosed."`
2. Ask the model to EXPLAIN or ENRICH, never to re-classify.
3. Cap the narrative length so it stays under ~300 tokens.

The AI's free-form recommendation field maps to the existing
`manter / investigar / vender` taxonomy and is stored in the
unchanged `recommendation` column. The structured signal lives in the
new four columns.

If no AI is configured: `Watchman.Analysis.SignalFormatter.format/1`
(pure helper) produces a plain-text rendering of the signal for the
`justification` column. The pipeline records this case as
`tokens_used: 0, cost_usd: 0.0`.

## Signal alerts

`Watchman.Alerts.Dispatcher.maybe_notify/3` becomes
`maybe_notify/4` taking the signal too. Default trigger rules in TOML
`[alerts.signal]`:

```toml
[alerts.signal]
notify_levels = ["high"]               # only high-level signals page
notify_directions = ["bullish", "bearish"]   # never on :neutral
```

This complements (does not replace) the existing
`recommendation`-based trigger.

## Hard constraints

- `Watchman.Analysis.Classifier` is **pure** — no DB, no HTTP, no
  Process state, no Logger.
- Rules are a list of structs evaluated in priority order — **never**
  nested conditionals.
- Every rule branch has at least one test that fires it and one that
  does not.
- `%Signal{}` uses `@enforce_keys` so partial construction raises.
- Confidence math is testable in isolation — `Classifier.confidence/2`
  is exported as a pure helper.
- AI prompts get the signal as context; the system prompt explicitly
  forbids ignoring it.
- `mix credo --strict` clean on all new files.
- `Watchman.Analysis.Classifier`, `Watchman.Analysis.Signal`,
  `Watchman.Analysis.SignalFormatter` all at **100% coverage**.

## Test strategy

| Layer | Approach |
|---|---|
| `Signal` struct | `@enforce_keys` enforced; positive + missing-field tests |
| `Classifier.Rule` struct + predicate + reason | Pure function tests per rule |
| Every rule (priority 1–9) | one fires-it case + one does-not-fire case |
| Direction resolution | bullish+bearish=neutral; agreement passes through |
| Confidence math | total_conditions exposed; matched/total formula verified |
| `Classifier.classify/2` | end-to-end on Indicators + news fixtures covering every outcome path |
| Pipeline | Mox the AI / Market / News provider behaviours; assert correct order + parallel awaits + persist of all five signal columns + AI prompt receives signal |
| `SignalFormatter.format/1` | snapshot-style on each level × direction combo |
| Schema migration | applies + reverts; indices present |

`Classifier` tests are plain `ExUnit.Case, async: true`, no DB.
Pipeline tests use the existing Mox setup at
`test/watchman/pipeline_test.exs` extended with `News.MockProvider`
expectations.

## Ordered task list

1. **`Watchman.Analysis.Signal` struct** + tests.
2. **`Watchman.Analysis.Classifier.Rule` struct** + private helpers
   for evaluating a rule against `(Indicators, news_items)`.
3. **`Watchman.Analysis.Classifier` rule list** — all 9 rules
   declared with predicates + reason functions. `classify/2`
   evaluates them in priority order. `total_conditions/0` exposed.
4. **Direction-resolution** logic (`:neutral` on bullish+bearish
   conflict) + tests.
5. **Confidence math** (`Classifier.confidence/2` helper) + tests.
6. **`Watchman.Analysis.SignalFormatter.format/1`** for AI-less mode.
7. **Migration** adding the four signal columns to `analyses`. Update
   `Watchman.Models.Analysis` schema + changeset with inclusion lists
   on level / direction.
8. **Pipeline rewrite** — parallel news + price + history fetch;
   call Classifier; persist Signal columns; route through AI or
   formatter.
9. **AI provider signature change** — `analyze/3` (or kw opts)
   accepting the signal. Update Claude / Gemini / Deepseek prompts +
   adapters + Mox expectations.
10. **Signal-based alerts** — extend `Alerts.Dispatcher.maybe_notify`
    + TOML config + Telegram / Discord renderers.
11. **`mix.exs` version bump** to `0.6.0`.
12. **Docs** — flip ROADMAP, ARCHITECTURE module map
    (`Analysis.Classifier`, `Analysis.Signal`, `Analysis.SignalFormatter`
    → shipped); add Status block to this document.

Conventional Commits prefix: `feat(classifier):` for steps 1–6 and
8; `feat(analyses-schema):` for step 7; `feat(ai):` for step 9;
`feat(alerts):` for step 10; `chore(release):` for step 11; `docs:`
for step 12.

If team mode is used: workers can split by layer.

- worker-A on Signal struct + Classifier + SignalFormatter (steps
  1–6, sequential — same file).
- worker-B on migration + Analysis schema (step 7, blocked by step
  1).
- worker-C on Pipeline rewrite (step 8, blocked by 1–7).
- worker-D on AI prompts + adapters (step 9, blocked by 1–6 only —
  no dependency on Pipeline shape).
- worker-E on Alerts (step 10, blocked by 1).
- Lead does docs + version bump after all merge.

## Out of scope (lands later)

- **`wm signals TICKER`** CLI command — listing of past signals.
  Defer to v0.6.x patch once the signal columns have real data.
- **Signal-based accuracy reporting** (separate from
  recommendation-based). The existing Track 1 accuracy queries stay
  on the `recommendation` column for v0.6.0. v0.6.x patch can add a
  parallel `wm accuracy --by signal_direction` flag.
- **Daemon scheduler invoking Pipeline.run/0** — that's Track 5
  (v0.7.0). Track 4's Pipeline is still invoked by `wm run` on cron
  / systemd timer.

## References

- [REALIGNMENT.md](REALIGNMENT.md) — Track 4 section is the canonical
  rule list source.
- [ROADMAP.md](../ROADMAP.md) — v0.6.0 milestone.
- [ARCHITECTURE.md](../ARCHITECTURE.md) — module map + pipeline-flow
  diagram already shows the Track 4 stages.
- [track-1-accuracy.md](track-1-accuracy.md) — outcome closer
  invoked from the new Pipeline.
- [track-2-technical.md](track-2-technical.md) — `%Indicators{}`
  consumed by `Classifier.classify/2`.
- [track-3-news.md](track-3-news.md) — `News.Provider` /
  `News.Factory` consumed in parallel with price fetch.
- [track-5-daemon.md](track-5-daemon.md) — the paradigm shift that
  reuses Track 4's Pipeline rewrite.
