# watchman roadmap

Status of `wm` and what comes next. Shipped = on a tagged release. This is intent,
not a promise — order can shift. Detailed specs/plans live under
[`docs/superpowers/`](docs/superpowers/).

## Shipped

- **v2.0.0** — wallet CRUD + the one-screen `wm run` glance (single z-score signal).
- **v2.1.0** — the **multi-signal anomaly engine**: five deterministic, pure signals
  (z-score, RSI(14), drawdown, 52-week proximity, volume) → a calm/watch/⚠ LOOK
  severity per ticker, ranked worst-first, every call explained; tunable thresholds
  via `config.toml`; `--detail` / `--look` / per-ticker args; typed failures
  (No data / API error). News was dropped as a signal — sourcing didn't justify the
  value (see [`docs/design/2026-06-21-news-source.md`](docs/design/2026-06-21-news-source.md)).

## Next — scan & opportunity indicators

Spec: [`docs/superpowers/specs/2026-06-25-scan-opportunity-design.md`](docs/superpowers/specs/2026-06-25-scan-opportunity-design.md).

- **Scan (1a)** — *Done* — `wm scan`: neutral technical readout table (RANGE, DRAWDOWN, vs
  SMA200, RSI, VOL) + `--detail` + `--json`. Separate JTBD from `wm run` anomalies.
- **Explain (1b)** — `docs/indicators/` reference + `wm explain [INDICATOR]`.
- **Wallet UX (1c)** — multi-ticker `add`, `clear --yes`, default `list`.

## Later — history & schedule

- **History** — append NDJSON per `wm scan`/`wm run` to
  `~/.config/watchman/history.ndjson`; `wm history [-n N] [TICKER]`. No DB.
- **Schedule** — `wm schedule --every 3d` writes a systemd user timer / cron;
  `wm unschedule`. Not a daemon.

## Later — self-update & distribution

- **Self-update** — `wm update`: compare embedded version vs GitHub Releases, download
  the matching asset, atomic self-replace; throttled opt-out auto-check on `run`.
- **Homebrew tap** — create `carvalhosauro/homebrew-tap` + token, uncomment the
  GoReleaser `brews:` block. *Done:* `brew install carvalhosauro/tap/wm` works.
- **CODE_OF_CONDUCT.md** — add Contributor Covenant.
- More signals as opt-in (MACD, SMA/EMA cross, streak) — only if they earn their place.

## Out of scope (for now)

No buy/sell advice or price targets · no fundamentals/valuation/screening · no AI ·
no editorial signal weighting · no background alerts/notifications. `wm` stays a fast,
auditable, local glance over what you hold.
