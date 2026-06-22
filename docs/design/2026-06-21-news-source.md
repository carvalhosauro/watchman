# News source — design note (v2.1 FeedRSS fix)

Research date: 2026-06-21. All endpoints below were fetched live during research.

## Problem

`internal/news` parses RSS `<channel><item>` and defaults `FeedURL` to the CVM RAD
`frmGetXml.aspx` endpoint — which actually returns `<CVM><documento>`. Mismatch →
live fetch yields 0 items → `wm run` is price-only in practice. **No global RSS feed
of material facts exists.** So the fix changes the *source and parser*, not just the URL.

## Verified options

| Source | Endpoint | Format | Fresh? | Per-ticker | Auth | License/ToS |
|---|---|---|---|---|---|---|
| **B3 reportsPeriodProxy** | `sistemaswebb3-listados.b3.com.br/reportsPeriodProxy/ReportsPeriodCall/GetMaterialFacts/<base64(params)>` | JSON `{page,results[]}` | **Yes (real-time mirror of CVM filings)** | by `codeCVM` (client-side); date via `dateInitial/dateFinal` | none | **undocumented**, Cloudflare-fronted, gray-area |
| **CVM Open Data IPE** | `dados.cvm.gov.br/dados/CIA_ABERTA/DOC/IPE/DADOS/ipe_cia_aberta_2026.zip` | ZIP→CSV (latin1, `;`) | **No — weekly** | by `Codigo_CVM` | none | **open license (clean)** |
| **Dados de Mercado** | `api.dadosdemercado.com.br/v1/companies/:cvm_code/docs` | JSON, has `tickers[]` | yes | by `cvm_code`; `tickers[]` in payload | **Bearer token** | commercial, pricing unclear |
| News aggregators (Money Times, Suno) | `moneytimes.com.br/tag/<empresa>/feed/`, `suno.com.br/noticias/feed/` | **RSS 2.0** (ticker in `<title>`) | yes | by tag/title | none | copyrighted general news, not regulatory |

Notes:
- **B3 params**: `base64(JSON.stringify({language:"pt-br",pageNumber:1,pageSize:N,dateInitial:"yyyy-MM-dd",dateFinal:"yyyy-MM-dd",category:"",keyword:""}))`. `category` must be a **string**: `"4"`=Fato Relevante, `"6"`=Comunicado ao Mercado, `""`=all. Results carry `company.codeCVM`, `tradingName`, `category`, `type`, `subject`, `deliveryDateTime`, `urlSearch`/`urlDownload` (→ rad.cvm.gov.br). All documents ultimately resolve at CVM RAD.
- **ticker → CVM code**: B3 `listedCompaniesProxy/CompanyCall/GetDetail/<base64({codeCVM,language})>` returns `otherCodes[]` (tickers); or build a static map from the CVM cadastro CSV. Needed because no source filters by ticker server-side.
- brapi.dev / Yahoo / Alpha Vantage / HG Brasil / Finnhub(free) — **no B3 material-fact news**. Marketaux covers B3 news (`?symbols=PETR4.SA`) but it's headlines, token-gated, not regulatory facts.

## Recommendation

**B3 `GetMaterialFacts` JSON**, filtered to `category="4"` (Fato Relevante) for today,
matched to held tickers via a ticker→`codeCVM` map.

- Pro: real-time, free, no key, authoritative (CVM filings), exactly "fato relevante today".
- Con: undocumented (B3 can change/pull it), JSON not RSS (new parser), base64 params,
  needs the ticker→CVM map, Cloudflare may throttle.
- Fallback already in place: any failure → `nil` → price-only glance.

**Not** CVM Open Data IPE for the live glance — weekly cadence can't answer "today"
(keep it in mind for a future backfill/history feature). **Not** Dados de Mercado for
v2.1 — adds a token dependency.

## Implementation sketch (for the fix branch)

- Keep `news.Item{Title,Date}` and `news.Fresh(ticker, items, today)` stable.
- Replace `FetchItems`/`ParseItems`: build base64 params for today, GET B3, parse the
  JSON `results[]` → `Item{Title: subject||type, Date: deliveryDateTime[:10]}` plus the
  `codeCVM`; change `Fresh` matching from title-substring to `codeCVM` equality via a
  ticker→CVM map (so it's exact, not fuzzy — aliases become unnecessary).
- `WATCHMAN_NEWS_URL` seam stays (point at an httptest serving a captured JSON fixture).
- Hermetic flow tests: real B3 JSON sample committed as a fixture; no live network in tests.
- Document the dependency as undocumented/best-effort in the package doc.

## Open question for the maintainer

Accept the **undocumented B3 endpoint** (real-time, free, but may break without notice)
for v2.1, with graceful price-only fallback? Or prefer a licensed/stable but slower/
token-gated source? Default recommendation: **B3 JSON**.
