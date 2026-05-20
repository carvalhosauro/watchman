# Strategic Realignment — owning the analytical layer

> Canonical reference for the v0.3.0+ direction. If something here conflicts
> with another document, this one wins until the realignment is complete.

## Core problem

Until v0.2.x, the pipeline was:

```
wm run → fetch price (Brapi/yfinance) → send to AI provider → receive
analysis + news → persist to SQLite
```

The AI provider does everything intellectually valuable: it fetches news,
reads context, classifies noise vs signal, and generates the recommendation.

Without the AI provider, watchman is a price fetcher with cron scheduling
and Telegram notifications — no proprietary logic exists in the codebase
itself.

The realignment makes watchman own its analytical layer. The AI provider
becomes an optional narrative enrichment step, not the engine of the entire
product.

## Target architecture (end state)

```
wm run
 ├── close past analysis outcomes whose lookahead window has elapsed
 ├── fetch price (Brapi / yfinance)                   — unchanged
 ├── fetch news (News.Provider — CVM / Infomoney)     — NEW
 ├── compute technical indicators (Analysis.Technical) — NEW, pure
 ├── classify signal (Analysis.Classifier)            — NEW, deterministic rule engine
 ├── [optional] enrich with AI narrative (AI.Provider) — existing, now optional
 └── persist everything                                — extended schema
```

Key properties:

- **AI is optional.** Pipeline produces a usable signal with zero API keys.
- **Signal is deterministic.** Same inputs → same output. Auditable. Replayable.
- **News is owned.** Stored verbatim from official sources (CVM regulatory filings, financial-press RSS), not summarized by a third-party LLM.
- **Accuracy is measurable.** Each analysis is evaluated against price `N` days later and stored as a hit/miss outcome.

## Implementation tracks

Four tracks, ordered by dependency and by how soon they add user-visible value.

### Track 1 — Accuracy tracking (`wm accuracy`) — v0.3.0

**Why first:** uses only data already in the database. Zero new API, zero new
dependencies. Immediately adds credibility by closing the feedback loop on
past analyses.

What to build:

- Query layer joining `analyses` with subsequent `price_snapshots` (N business days after analysis date, configurable, default 5).
- Hit definition: `buy/hold` recommendation + price up → hit. `sell/avoid` + price down → hit. Recorded in a new `analysis_outcomes` table.
- `wm accuracy` command with `--ticker TICKER`, `--provider PROVIDER`, `--days N`, `--since DATE`.
- Tabular report: hit rate per asset, per provider, overall.

Constraints:

- Outcomes are **stored**, not recomputed at query time. The `wm run` pipeline closes outcomes for analyses that have reached their lookahead window before running new ones.
- Pure Ecto queries only. No external API calls.

Detailed prep: [`track-1-accuracy.md`](track-1-accuracy.md).

### Track 2 — Technical analysis (`Watchman.Analysis.Technical`) — v0.4.0

**Why second:** uses only stored `price_snapshots`. Zero new API. Pure
deterministic functions, 100% unit-testable.

Surface:

```elixir
# All functions take a list of price_snapshots (oldest → newest)
# and return tagged result tuples.

Technical.sma(snapshots, period)          # → {:ok, float} | {:error, :insufficient_data}
Technical.ema(snapshots, period)          # → {:ok, float} | {:error, :insufficient_data}
Technical.rsi(snapshots, period \\ 14)    # → {:ok, float} | {:error, :insufficient_data}
Technical.zscore(snapshots, period \\ 21) # → {:ok, float} | {:error, :insufficient_data}
Technical.streak(snapshots)               # → {:ok, %{direction: :up | :down, days: integer}}
Technical.drawdown(snapshots, period)     # → {:ok, float} | {:error, :insufficient_data}
Technical.indicators(snapshots)           # → {:ok, %Indicators{}} — computes all at once
```

`%Indicators{}` fields: `sma7, sma21, sma50, ema21, rsi14, zscore21, streak,
drawdown_from_peak`.

Constraints:

- All functions pure — no DB, no side effects, no process communication.
- Return `{:error, :insufficient_data}` (never raise) when the snapshot list is shorter than the required period.
- ExUnit tests with hardcoded fixtures for every function. RSI and EMA validated against manually-computed reference values (e.g., spreadsheet).
- Do **not** import or call these from `Pipeline` until Track 4 is ready.
- Minimum snapshot history required must be documented in `@moduledoc`.

### Track 3 — News provider layer (`Watchman.News.Provider`) — v0.5.0

**Why third:** replaces news fetching currently delegated to the AI provider's
web search. Own the data, own the audit trail.

Behaviour:

```elixir
@callback fetch(ticker :: String.t(), opts :: keyword()) ::
  {:ok, [%NewsItem{}]} | {:error, term()}
```

Adapters:

**A — CVM (priority, Brazilian regulatory filings):**
- Endpoint: `https://www.rad.cvm.gov.br/ENETCONSULTA/frmGetXml.aspx`
- Fetches fatos relevantes, ITR disclosures, material events by ticker.
- Free, official, no auth.
- XML → `%NewsItem{source: "cvm", ticker, title, published_at, url, category}`.
- `category` maps CVM document type codes to `:material_fact | :financial_result | :dividend | :other`.

**B — Infomoney RSS:**
- Feed: `https://www.infomoney.com.br/mercados/[TICKER]/feed/`
- RSS → `%NewsItem{source: "infomoney", ...}`.
- Max 10 items per run.

Factory resolution mirrors `Market.Factory` / `AI.Factory`. Config key
`news_provider`, values `"cvm" | "infomoney" | "all"`. `"all"` fetches both
and merges, deduplicating by URL.

Constraints:

- Persisted in the existing `news_items` table (add `source`, `category` columns).
- HTTP via `Req`, 10s timeout, single transient retry.
- Provider failure must not break the pipeline — log, continue with empty list.
- Do NOT interpret news content. Store title, URL, published_at, category. Interpretation is Track 4.
- Mock HTTP layer with `Mox`.

### Track 4 — Signal classifier (`Watchman.Analysis.Classifier`) — v0.6.0

**Why fourth:** depends on Tracks 2 and 3. Combines indicators + news count into
a deterministic signal.

Surface:

```elixir
Classifier.classify(%Indicators{}, news_items) :: %Signal{
  level: :high | :medium | :low | :noise,
  direction: :bullish | :bearish | :neutral,
  reasons: [String.t()],
  confidence: float()  # 0.0 to 1.0
}
```

Rules (evaluated in priority order):

```
:high + :bearish  → |zscore| > 2.0 AND streak.direction == :down AND streak.days >= 3
:high + :bullish  → |zscore| > 2.0 AND streak.direction == :up   AND streak.days >= 3
:high (either)    → any :material_fact or :financial_result news item present
:medium + :bearish → zscore < -1.5 OR (streak.direction == :down AND streak.days >= 2)
:medium + :bullish → zscore >  1.5 OR (streak.direction == :up   AND streak.days >= 2)
:medium (either)  → news_count >= 2
:low              → |zscore| between 0.5 and 1.5 OR news_count == 1
:noise            → default (no rule matched)
```

`:neutral` direction applies when conditions conflict (e.g., bullish zscore +
bearish streak).

`reasons` is a list of human-readable English strings explaining which rule
fired, e.g.:

```
["Price is 2.3σ below 21-day average",
 "3 consecutive down days",
 "Material fact disclosed by CVM"]
```

Constraints:

- Pure function. No side effects, no DB.
- Every rule branch must have at least one test case that fires it **and** one that doesn't.
- Rules defined as module constants or a config-driven list of rule structs evaluated in order — **not** as nested conditionals.
- `confidence = matched_conditions / total_evaluated_conditions`, capped at 1.0.
- When AI is enabled, the classifier output is passed in as additional context, so the AI references it rather than starting from scratch.

## Pipeline integration (after all four tracks ship)

`Watchman.Pipeline` is rewritten to:

1. Close pending outcomes (Track 1) before doing new work.
2. Fetch news (Track 3) in parallel with price (existing).
3. Load last N price snapshots from DB (N = 50 minimum for RSI).
4. Compute `%Indicators{}` (Track 2).
5. Compute `%Signal{}` (Track 4).
6. If AI configured: pass price + news + indicators + signal to AI. AI prompt
   must reference the signal and explain/enrich it — not re-derive.
7. If AI not configured: format `%Signal{}` directly for display.

## Hard constraints (apply to all tracks)

**Do NOT touch until the track that owns it:**

- `Watchman.Pipeline` orchestration logic until Track 4.
- `Watchman.Setup`, `Watchman.Scheduler`, `Watchman.Config`, `Watchman.Credentials`.
- Any existing migration files.
- The `bin/wm` wrapper or install/uninstall scripts.

**Code quality:**

- Every new public function has a `@spec`.
- Every new module has a `@moduledoc` explaining responsibility and constraints.
- No `IO.inspect` or debug output in committed code.
- `mix credo --strict` passes on all new files before commit.
- New modules excluded from coverage must be explicitly justified in `mix.exs` with a comment.

**Testing:**

- Pure modules (`Technical`, `Classifier`): 100% coverage, no exceptions.
- Provider adapters (`News.CVM`, `News.Infomoney`): `Mox` happy path + timeout + malformed response.
- Accuracy queries: in-memory SQLite sandbox.
- No `ExUnit.Case, async: false` unless absolutely required (comment why).

**Dependencies:**

- No new runtime dependencies without explicit justification.
- `SweetXml` acceptable for XML parsing (CVM / RSS).
- No LLM SDKs, no paid APIs, no services requiring account creation.

**Database:**

- New tables via Ecto migrations only. No raw SQL in application code.
- New columns: NOT NULL with sensible defaults where appropriate.
- Add indices on columns used in WHERE or ORDER BY.
