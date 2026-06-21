# watchman roadmap

Status of `wm` and what comes next. Shipped = on a tagged release. This is intent,
not a promise — order can shift. See the implementation plans under
[`docs/superpowers/plans/`](docs/superpowers/plans/) for the detailed breakdowns.

## Shipped — v2.0.0

The price-anomaly glance, end-to-end:

- `wm wallet add/list/remove` — plaintext wallet (`$WATCHMAN_WALLET` override)
- `wm run` — per held ticker: **ignore** or **⚠ LOOK** + reason, via a deterministic
  rule (abnormal daily move, z-score |Z| ≥ 2 vs ~30d, **or** fresh CVM news today)
- Yahoo prices + CVM feed, no DB; graceful degradation (upstream down → price-only)
- Shell completions, man pages, cross-platform static binaries (linux/darwin/windows)

## Now — v2.1: real news (the FeedRSS fix)

**Problem:** news is wired but cosmetic in practice. The parser expects RSS
`<channel><item>`, but the default `FeedURL` (CVM RAD `frmGetXml.aspx`) returns
`<CVM><documento>` — a different schema — so a live fetch yields zero items and
`wm run` is effectively price-only today.

**Goal:** a real material-fact signal so "fresh material news → LOOK" fires live.

**Scope (to design on the fix branch):**
- Decide the source: a global material-fact **RSS feed** vs. parsing the RAD
  `<CVM><documento>` schema (tipo / titulo / url / dataEntrega) — the latter is
  per-company (`CodigoInstituicao`) and needs a ticker → código map.
- Implement the matching parser; keep `FetchItems` graceful (nil on any failure).
- **Ticker aliases** — match a headline that names the company ("Petrobras") not the
  ticker ("PETR4"). (See `docs/contributing/starter-issues.md` #1.)
- Keep everything hermetic: `httptest` + `.txtar` flow tests, `$WATCHMAN_NEWS_URL` seam.

**Done signal:** against a real feed, `wm run` shows `… fresh material news` for a
ticker with a fato relevante today; new flow tests green; no real network in tests.

## Next — v2.2: history & schedule

- **History** — append NDJSON per `wm run` to `~/.config/watchman/history.ndjson`;
  `wm history [-n N]`. No DB. *Done:* runs are logged and listed.
- **Schedule** — `wm schedule --every 1h` writes a systemd user timer / cron calling
  `wm run`; `wm unschedule`. Not a daemon. *Done:* a timer is installed and fires.

## Later — v2.3+: self-update & distribution

- **Self-update** — `wm update`: compare embedded version vs GitHub Releases, download
  the matching asset, atomic self-replace; throttled opt-out auto-check on `run`.
  Pipeline already exists. *Done:* `wm update` upgrades an old binary in place.
- **Homebrew tap** — create `carvalhosauro/homebrew-tap` + token, uncomment the
  GoReleaser `brews:` block. *Done:* `brew install carvalhosauro/tap/wm` works.
- **CODE_OF_CONDUCT.md** — add Contributor Covenant (deferred from v2 prep).
- Completion/man install step in the binary installer.

## Out of scope (for now)

No buy/sell advice or price targets · no AI · no provider abstraction · no per-ticker
weighting or multi-level severity · no background alerts/notifications. `wm` stays a
fast, auditable, local glance.
