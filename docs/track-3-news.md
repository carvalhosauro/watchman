# Track 3 — News Provider Layer (v0.5.0)

Concrete prep for the third realignment track. See
[`REALIGNMENT.md`](REALIGNMENT.md) for the broader rationale.

## Status — not started

Track 1 (v0.3.0) and Track 2 (v0.4.0) shipped. Track 3 is the next
active milestone. This document is the work plan; it will be updated
with shipped-commit metadata as the track progresses, mirroring
[`track-1-accuracy.md`](track-1-accuracy.md) and
[`track-2-technical.md`](track-2-technical.md).

## Goal

Stop delegating news fetching to the AI provider's web search. Own the
audit trail by pulling news directly from official Brazilian sources
(CVM regulatory filings, Infomoney RSS) and persisting them in
`news_items` with a stable `source` + `category` schema.

Track 3 fetches and persists news only. It does NOT interpret news
content — that's Track 4 (Classifier consumes news count + category).

## Module surface

```elixir
defmodule Watchman.News.Provider do
  @moduledoc """
  Behaviour for news fetching adapters.
  """

  @callback fetch(ticker :: String.t(), opts :: keyword()) ::
              {:ok, [Watchman.Models.NewsItem.t()]} | {:error, term()}
end

defmodule Watchman.News.Factory do
  @moduledoc "Resolves the configured news provider(s)."

  @spec providers() :: [module()]
  def providers do
    # config: "cvm" | "infomoney" | "all"
  end
end

defmodule Watchman.News.CVM do
  @behaviour Watchman.News.Provider

  @spec fetch(String.t(), keyword()) ::
          {:ok, [Watchman.Models.NewsItem.t()]} | {:error, term()}
end

defmodule Watchman.News.Infomoney do
  @behaviour Watchman.News.Provider

  @spec fetch(String.t(), keyword()) ::
          {:ok, [Watchman.Models.NewsItem.t()]} | {:error, term()}
end
```

## Adapter A — CVM (priority, regulatory)

**Endpoint:** `https://www.rad.cvm.gov.br/ENETCONSULTA/frmGetXml.aspx`

Fetches fatos relevantes, ITR disclosures, material events by ticker.
Free, official, no authentication required.

**Response shape:** XML with document entries — each has a type code,
title, publication date, URL.

**Category mapping** from CVM document type codes:
- material fact codes → `:material_fact`
- earnings/ITR codes → `:financial_result`
- dividend codes → `:dividend`
- everything else → `:other`

**Persistence:** each entry becomes a `%Watchman.Models.NewsItem{}` with
`source: "cvm"`, `category: "<atom_string>"`, plus the standard
title/url/published_at/fetched_at.

## Adapter B — Infomoney RSS

**Feed:** `https://www.infomoney.com.br/mercados/[TICKER]/feed/`

**Constraints:**
- Cap at 10 items per run (rate-friendly).
- RSS XML → `%NewsItem{source: "infomoney"}`.
- Category mapping is harder for free-form news — default to `:other`
  unless the title matches a known dividend/results keyword (document
  the keyword list in `@moduledoc`).

## News.Factory resolution

Same pattern as `Watchman.Market.Factory` and `Watchman.AI.Factory`.
Config key `news_provider` under `[providers]` in TOML:

```toml
[providers]
news = "cvm"          # use CVM only
# news = "infomoney"  # use Infomoney only
# news = "all"        # fetch both, merge, dedupe by URL
```

`Factory.providers/0` returns a list of behaviour modules. When more
than one, the caller merges and deduplicates by URL.

## Schema changes

New migration: add `source` and `category` columns to `news_items`.

```elixir
defmodule Watchman.Repo.Migrations.AddSourceCategoryToNewsItems do
  use Ecto.Migration

  def change do
    alter table(:news_items) do
      add :source,   :string, null: false, default: "unknown"
      add :category, :string, null: false, default: "other"
    end

    create index(:news_items, [:source])
    create index(:news_items, [:category])
  end
end
```

`Watchman.Models.NewsItem` schema gains the two fields. Changeset
validates `source` and `category` via `validate_inclusion`:

```elixir
@sources    ~w(cvm infomoney unknown)
@categories ~w(material_fact financial_result dividend other)
```

## Pipeline behaviour

Track 3 does NOT wire news into `Watchman.Pipeline.run/0` — that's
Track 4. But the factory and adapters must be callable directly:

```elixir
iex> Watchman.News.Factory.providers()
[Watchman.News.CVM]

iex> Watchman.News.CVM.fetch("PETR4")
{:ok, [%NewsItem{source: "cvm", category: "material_fact", ...}, ...]}
```

## Hard constraints

- **HTTP via `Req`** with a 10-second timeout and one transient retry,
  matching the existing market provider conventions
  (`lib/watchman/market/brapi.ex`, `.../yfinance.ex`).
- **Graceful degradation:** if an adapter fails, the caller treats it
  as `{:error, term()}` and the future Pipeline integration (Track 4)
  will continue with an empty list — news is enrichment, not a hard
  dependency.
- **No interpretation:** store title, URL, published_at, source,
  category. Do NOT generate summaries — that's the AI layer's job.
- **Mox-mocked HTTP** in tests, same pattern as existing providers.
- **@spec on every public function. @moduledoc on every new module.**
- **mix credo --strict clean.**
- **No new runtime deps** without justification. `SweetXml` is
  acceptable for CVM/RSS parsing — add it.
- **Coverage targets:** Factory and Provider behaviour at 100%.
  Adapters (CVM, Infomoney) test happy path + timeout + malformed
  response with Mox.

## Test plan

| Layer | Cases |
|-------|-------|
| Migration | applies + reverts cleanly; indices present |
| `NewsItem` model | source/category required + inclusion-validated |
| `News.Factory.providers/0` | resolves `"cvm"` → `[CVM]`; `"infomoney"` → `[Infomoney]`; `"all"` → `[CVM, Infomoney]`; unknown → default |
| `News.CVM.fetch/2` | happy path (sample XML fixture); timeout returns `{:error, _}`; malformed XML returns `{:error, _}`; category mapping per known doc-type code |
| `News.Infomoney.fetch/2` | happy path (sample RSS fixture); 10-item cap honored; timeout `{:error, _}` |
| Dedup by URL when `"all"` | two adapters returning overlapping URLs → single merged list |

All HTTP calls mocked with Mox. Existing pattern at
`test/watchman/market/factory_test.exs` is the reference.

## Ordered task list

1. **Migration** — add `source` + `category` to `news_items`. Update
   `Watchman.Models.NewsItem` schema + changeset with inclusion lists.
2. **`Watchman.News.Provider` behaviour** — `@callback fetch/2`.
3. **`Watchman.News.Factory`** — config-driven resolution.
4. **`Watchman.News.CVM` adapter** — Req call, XML parse via
   SweetXml, category mapping from doc-type codes, Mox-mocked tests.
5. **`Watchman.News.Infomoney` adapter** — Req call, RSS parse,
   10-item cap, Mox-mocked tests.
6. **`SweetXml` dependency** added to `mix.exs` with one-line
   justification comment.
7. **Config readers** — `Watchman.Config.news_provider/0` and
   `news_providers/0` (list form), mirroring `market_provider/0`.
8. **Optional sanity command** — `wm news TICKER` that fetches via the
   configured factory and prints. *Skip if it adds CLI surface for
   Track 3; defer to Track 4 when news + indicators + classifier all
   land together.*
9. **`mix.exs` version bump** to `0.5.0`.
10. **Docs:** mark v0.5.0 done in ROADMAP; update ARCHITECTURE module
    map (`News.Provider`, `News.CVM`, `News.Infomoney`,
    `News.Factory` → shipped); add Status block to this document.

Each step is independently committable. Conventional Commits prefix:
`feat(news):` for steps 1-7, `chore(release):` for step 9, `docs:`
for step 10.

If team mode is used: pre-assign by file. Worker-A on
`Watchman.News.Provider` + `Watchman.News.Factory` (small,
sequential); worker-B on `Watchman.News.CVM` + tests; worker-C on
`Watchman.News.Infomoney` + tests; lead handles migration + docs +
version bump + mix.exs dep.

## Out of scope (lands in Track 4)

- Wiring news fetch into `Watchman.Pipeline.run/0`.
- News passed to `Classifier.classify/2` for signal derivation.
- AI prompt updated to reference news + signal.
- `wm news TICKER` CLI command (deferred — see task 8 above).
- Persisting news during normal pipeline runs (Track 4 will call the
  factory inside the per-asset reduce).

## References

- [REALIGNMENT.md](REALIGNMENT.md) — Track 3 section.
- [ROADMAP.md](../ROADMAP.md) — v0.5.0 milestone.
- [ARCHITECTURE.md](../ARCHITECTURE.md) — module map + Strategy/Factory pattern.
- [track-1-accuracy.md](track-1-accuracy.md) — prior-track format reference.
- [track-2-technical.md](track-2-technical.md) — prior-track format reference.
- `lib/watchman/market/factory.ex` + `lib/watchman/market/brapi.ex` — factory + adapter pattern to mirror.
- `test/watchman/market/factory_test.exs` — Mox-mocked HTTP test pattern.
