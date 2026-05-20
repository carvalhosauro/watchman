# Track 3 — News Provider Layer (v0.5.0)

Concrete prep for the third realignment track. See
[`REALIGNMENT.md`](REALIGNMENT.md) for the broader rationale.

## Status — shipped v0.5.0

Track 3 shipped as of v0.5.0. Commits `708d4e5` (schema + whitelist)
through `89e5100` (version bump) on branch `dev`. 4 adapters
implementing `Watchman.News.Provider` (CVM + Infomoney + B3 +
RssFeed) cover 8 free news sources. Pure parsing logic on every
adapter is exercised by hardcoded fixture tests; HTTP fetch wrappers
follow the existing "tested via integration" convention.

344 tests, 0 failures. Total coverage 70.81%.
`Watchman.News.Provider` and `Watchman.News.TickerAliases` at 100%;
`Watchman.News.Factory` at 88.9%.

The task list at the bottom of this document is preserved as the
historical record of how the track was decomposed.

Wiring into `Watchman.Pipeline.run/0` is intentionally deferred to
Track 4 (v0.6.0).

## Goal

Stop delegating news fetching to the AI provider's web search. Own the
audit trail by pulling news directly from official Brazilian sources
and free financial press feeds, then persist them in `news_items` with
a stable `source` + `category` schema.

Track 3 fetches and persists news only. It does NOT interpret news
content — that's Track 4 (Classifier consumes news count + category).

## Coverage: 4 adapters, 8 sources

Per-company IR sites (e.g. `ri.bb.com.br`) were considered but rejected
for v0.5.0: each has unique HTML, no standardised RSS, layouts shift,
and CVM already covers every listed company's regulatory disclosures.
IR adapters return as opt-in extension in a future patch (see "Out of
scope").

| Adapter | Source(s) | Type |
|---|---|---|
| `News.CVM` | CVM (Comissão de Valores Mobiliários) | Regulatory XML, universal coverage |
| `News.Infomoney` | Infomoney | RSS per ticker |
| `News.B3` | B3 (Brazilian stock exchange) | Corporate-actions / dividend events |
| `News.RssFeed` | Valor Econômico, Money Times, InvestNews, Suno Notícias, Brazil Journal | Generic broad-market RSS reader, one module across 5 outlets |

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

defmodule Watchman.News.B3 do
  @behaviour Watchman.News.Provider

  @spec fetch(String.t(), keyword()) ::
          {:ok, [Watchman.Models.NewsItem.t()]} | {:error, term()}
end

defmodule Watchman.News.RssFeed do
  @moduledoc """
  Generic RSS adapter. Reads the per-outlet URL list from config and
  pulls each feed, tagging items with the outlet name as the source.
  """

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

## Adapter C — B3 (corporate actions)

**Endpoint:** `https://arquivos.b3.com.br/` and
`https://bvmf.bmfbovespa.com.br/` host several open data files. Pick the
JSON endpoint that returns corporate-action events per ticker (dividend
ex-dates, splits, subscription rights). The exact path is undocumented
in places — verify during step 4 and pin the working URL in
`@moduledoc`.

**Category mapping:**
- dividend / juros sobre capital próprio → `:dividend`
- split / inplit / grupamento → `:other`
- subscription rights / bonifications → `:other`

**Constraints:** keep the payload small (a single ticker request, no
bulk dumps). If the endpoint requires JSON parsing, `Jason` is already
in deps — no new dependency. Cache the most recent fetch per ticker in
memory only (no DB cache) since the data is small.

## Adapter D — Generic RSS reader (5 outlets in one module)

`Watchman.News.RssFeed` consumes a config-provided list of RSS URLs and
returns merged items. One module covers Valor Econômico, Money Times,
InvestNews, Suno Notícias, and Brazil Journal — all expose standard
RSS 2.0 feeds.

**Config:**

```toml
[news.rss]
feeds = [
  { name = "valor",         url = "https://valor.globo.com/empresas/rss/" },
  { name = "money_times",   url = "https://www.moneytimes.com.br/feed/" },
  { name = "investnews",    url = "https://investnews.com.br/feed/" },
  { name = "suno",          url = "https://www.suno.com.br/noticias/feed/" },
  { name = "brazil_journal", url = "https://braziljournal.com/feed/" }
]
```

Each item's `source` field is set to the outlet name (`"valor"`,
`"money_times"`, etc.) rather than `"rss"`, so reports can break down
hit rate per outlet.

**Filtering:**
- These feeds are broad-market (not per-ticker). The adapter filters
  items by ticker presence in title or summary (case-insensitive
  substring match on the ticker code and the company name).
- Company-name lookup table lives at
  `lib/watchman/news/ticker_aliases.ex` (small map, e.g.
  `"PETR4" => ["Petrobras", "PETR4"]`). Document that the alias map
  starts minimal and grows as users register assets.
- Items with no ticker match are discarded.

**Cap:** 20 items per feed per run (5 × 20 = 100 max items per call).
After ticker filter, typical yield is 0-3 items per outlet.

**Failure mode:** if one feed errors, log a warning and continue with
the rest — return the partial merged list. Don't propagate single-feed
errors to the caller.

## News.Factory resolution

Same pattern as `Watchman.Market.Factory` and `Watchman.AI.Factory`.
Config key `news_provider` under `[providers]` in TOML:

```toml
[providers]
news = "cvm"               # CVM only
# news = "infomoney"       # Infomoney only
# news = "b3"              # B3 corporate actions only
# news = "rss"             # generic RSS feeds only
# news = "all"             # all four adapters, merged + deduped by URL
# news = "cvm,b3,rss"      # comma-separated subset
```

`Factory.providers/0` returns a list of behaviour modules. When more
than one, the caller fetches each, merges results, and deduplicates by
URL.

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
@sources ~w(
  cvm
  infomoney
  b3
  valor
  money_times
  investnews
  suno
  brazil_journal
  unknown
)
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
| Migration | applies + reverts cleanly; indices present on `source` + `category` |
| `NewsItem` model | source/category required + inclusion-validated for all 8 source values |
| `News.Factory.providers/0` | resolves `"cvm"` → `[CVM]`; `"infomoney"` → `[Infomoney]`; `"b3"` → `[B3]`; `"rss"` → `[RssFeed]`; `"all"` → `[CVM, Infomoney, B3, RssFeed]`; comma-separated subset; unknown → default |
| `News.CVM.fetch/2` | happy path (sample XML fixture); timeout returns `{:error, _}`; malformed XML returns `{:error, _}`; category mapping per known doc-type code |
| `News.Infomoney.fetch/2` | happy path (sample RSS fixture); 10-item cap honored; timeout `{:error, _}` |
| `News.B3.fetch/2` | happy path (sample JSON fixture); dividend / split / rights category mapping; timeout returns `{:error, _}` |
| `News.RssFeed.fetch/2` | happy path with 2 feeds returning items; ticker filter via title/summary substring (matches and rejects); per-outlet source tag; 20-items-per-feed cap honored; one-feed-failure returns the rest (partial OK, not propagated) |
| Ticker aliases | unknown ticker returns `[ticker]` as the only alias (no crash) |
| Dedup by URL when `"all"` | overlapping URLs across adapters collapse to one item |

All HTTP calls mocked with Mox. Existing pattern at
`test/watchman/market/factory_test.exs` is the reference.

## Ordered task list

1. **Migration** — add `source` + `category` to `news_items` with the
   8-source inclusion list. Update `Watchman.Models.NewsItem` schema +
   changeset.
2. **`Watchman.News.Provider` behaviour** — `@callback fetch/2`.
3. **`Watchman.News.Factory`** — config-driven resolution supporting
   `"cvm" | "infomoney" | "b3" | "rss" | "all" | "<csv subset>"`.
4. **`Watchman.News.CVM` adapter** — Req call, XML parse via
   SweetXml, category mapping from doc-type codes, Mox-mocked tests.
5. **`Watchman.News.Infomoney` adapter** — Req call, RSS parse,
   10-item cap, Mox-mocked tests.
6. **`Watchman.News.B3` adapter** — Req call to the verified
   corporate-actions endpoint, JSON parse via Jason (already in deps),
   category mapping for dividend / split / rights, Mox-mocked tests.
7. **`Watchman.News.TickerAliases`** — small lookup module mapping
   ticker code to a list of search aliases (ticker + company name).
   Starts minimal; tested directly.
8. **`Watchman.News.RssFeed` adapter** — config-driven URL list, ticker
   filter via TickerAliases, per-outlet source tag, 20-items-per-feed
   cap, one-feed-fail-tolerated semantics, Mox-mocked tests covering
   all 5 outlet URLs.
9. **`SweetXml` dependency** added to `mix.exs` with a justification
   comment (CVM XML + RSS parsing).
10. **Config readers** — `Watchman.Config.news_provider/0` and
    `news_providers/0` (list form). Add `news_rss_feeds/0` returning
    the configured `[{name, url}]` list for `RssFeed`.
11. **`mix.exs` version bump** to `0.5.0`.
12. **Docs:** mark v0.5.0 done in ROADMAP; flip ARCHITECTURE module map
    rows for `News.Provider`, `News.CVM`, `News.Infomoney`, `News.B3`,
    `News.RssFeed`, `News.Factory`, `News.TickerAliases` to shipped;
    add Status block to this document.

Each step is independently committable. Conventional Commits prefix:
`feat(news):` for steps 1-10, `chore(release):` for step 11, `docs:`
for step 12.

If team mode is used: workers can split by adapter (CVM / Infomoney /
B3 / RssFeed are disjoint files, true parallelism). Worker-A on
`Provider` + `Factory` + `TickerAliases` (small); workers B/C/D each
take one of CVM / Infomoney / B3 adapters; worker-E (or back to A
after the early steps) takes `RssFeed`. Lead handles migration +
schema + config + docs + version bump + dep add.

## Out of scope (lands in Track 4 or later patches)

**Track 4 (v0.6.0):**

- Wiring news fetch into `Watchman.Pipeline.run/0`.
- News passed to `Classifier.classify/2` for signal derivation.
- AI prompt updated to reference news + signal.
- Persisting news during normal pipeline runs (Track 4 will call the
  factory inside the per-asset reduce).
- `wm news TICKER` CLI command (deferred — easier to add alongside
  Track 4's pipeline integration).

**v0.5.x patches (post-track-3, opt-in extensions):**

- **`Watchman.News.IR` — per-company IR-site adapter.** Each company
  exposes its own "fatos relevantes" / "comunicados" page (e.g.
  `ri.bb.com.br`, `investidorpetrobras.com.br`, `vale.com/investors`)
  with non-standardised HTML. Adapter would hold a config-driven
  registry mapping ticker → IR URL + CSS selectors, and scrape per
  company. Not worth the maintenance until CVM coverage shows clear
  gaps in practice — most price-moving disclosures are already filed
  via CVM, and IR sites duplicate them.

- **Additional generic-RSS outlets.** Adding a feed to the v0.5.0
  `News.RssFeed` config is a one-line change once that adapter is
  shipped. Future candidates: NeoFeed, Exame, IstoÉ Dinheiro, Folha
  Mercado, Estadão Economia. Each must expose a stable RSS endpoint.

## References

- [REALIGNMENT.md](REALIGNMENT.md) — Track 3 section.
- [ROADMAP.md](../ROADMAP.md) — v0.5.0 milestone.
- [ARCHITECTURE.md](../ARCHITECTURE.md) — module map + Strategy/Factory pattern.
- [track-1-accuracy.md](track-1-accuracy.md) — prior-track format reference.
- [track-2-technical.md](track-2-technical.md) — prior-track format reference.
- `lib/watchman/market/factory.ex` + `lib/watchman/market/brapi.ex` — factory + adapter pattern to mirror.
- `test/watchman/market/factory_test.exs` — Mox-mocked HTTP test pattern.
