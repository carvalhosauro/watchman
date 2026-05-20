# Track 5 — Daemon paradigm shift (v0.7.0)

> **This track reverses an architectural pillar.** From v0.7.0 onwards
> Watchman runs as a long-lived OTP daemon that owns all ingestion and
> analysis. The `wm` binary becomes a read-only CLI against the
> daemon's database. `wm run` is **removed**.

## Status — not started

Track 4 (v0.6.0) must ship first. Track 4 wires news + indicators +
classifier into `Watchman.Pipeline.run/0` for the existing
run-and-exit invocation model. Track 5 then moves that same Pipeline
logic out of the CLI and into a supervised GenServer schedule.

## Why this paradigm shift

The current model — `wm run` invoked by cron / systemd timer — was
documented in `ARCHITECTURE.md` under "Key Decisions":

> No GenServer · Run-and-exit suits cron, avoids complexity

That choice was correct for v0.1.0–v0.6.0 when ingestion was
homogeneous (one daily pull). With Track 3 (8 news sources) and Track
4 (multi-stage analytical pipeline) it stops being optimal:

- **Cadence per source.** CVM publishes in business hours; RSS feeds
  update hourly; B3 corporate actions are daily; Brapi prices may
  refresh every 15 minutes. One cron entry per cadence is operational
  noise the user already flagged as the trigger for this track.
- **Shared rate-limit budget.** Brapi's free tier is monthly. A
  daemon holds the running count in memory; independent cron
  invocations cannot.
- **Cold-start cost.** Each `wm run` invocation loads the Erlang VM,
  fetches deps, runs migrations — ~1–2 s of overhead. A daemon pays
  that once at boot.
- **Cross-source dedup before persistence.** Four news adapters can
  return overlapping URLs. The daemon dedupes in memory before any
  INSERT touches SQLite.
- **Real-time alerts.** A material-fact disclosure from CVM should
  fire a Telegram alert in seconds, not at the next cron tick.

## End state

```
wm                          → read-only CLI (no run, no ingestion)
wm daemon start | stop | status   → service control
wm-daemon (or wm daemon)    → long-lived OTP application
```

### Daemon supervision tree

```
Watchman.Application (existing top-level supervisor)
├── Watchman.Repo
├── Watchman.Daemon.Supervisor                       (new)
│   ├── Watchman.Daemon.RateLimiter                  (new — shared Brapi budget)
│   ├── Watchman.Daemon.NewsScheduler                (new — per-source intervals)
│   │   ├── poll News.CVM       — default every 15 min
│   │   ├── poll News.Infomoney — default every 30 min
│   │   ├── poll News.B3        — default daily 18:00 BRT
│   │   └── poll News.RssFeed   — default every 30 min
│   ├── Watchman.Daemon.PriceScheduler               (new — market data)
│   │   └── Pulls Market.Factory.provider() at the configured cadence
│   ├── Watchman.Daemon.AnalysisScheduler            (new — runs analytical pipeline)
│   │   └── Calls Watchman.Pipeline.run/0 (unchanged from Track 4) on schedule
│   └── Watchman.Daemon.OutcomeCloser                (new — runs Accuracy.close_pending_outcomes)
└── Watchman.Alerts.Supervisor                       (existing-ish; alerts now dispatched from daemon hooks)
```

Each scheduler is a `GenServer` with:

- `init/1` reads its config (interval, source, enabled flag)
- `handle_info(:tick, state)` does one fetch cycle, then
  `Process.send_after/3` to schedule the next tick
- Crashes are caught by the `Watchman.Daemon.Supervisor` (one-for-one
  strategy) — a failing scheduler restarts, the others keep running

### CLI surface (post-Track-5)

The `wm` binary keeps every read-only command and gains daemon control
+ analytical queries:

| Command | Status |
|---|---|
| `wm setup` | unchanged (still configures TOML, keys, schedule) |
| `wm assets / list / remove` | unchanged |
| `wm show [TICKER] [-l N]` | unchanged (reads stored analyses) |
| `wm retro -w / -m / list / show ID` | unchanged |
| `wm logs [-f] [-n N]` | unchanged |
| `wm accuracy [...]` | unchanged (read Accuracy.report) |
| `wm completions bash / zsh` | unchanged |
| `wm update` | unchanged |
| `wm daemon start / stop / status / restart` | **new** — service control |
| `wm news TICKER [--since DATE] [--source X]` | **new** — list stored news |
| `wm impact TICKER [--days N]` | **new** — show recent news + price reaction window |
| **`wm run`** | **REMOVED** — daemon owns the loop |
| **`wm schedule / unschedule`** | **REPLACED** — daemon controls cadence via TOML, no cron / systemd-timer needed |

`wm run` removal is the breaking change that defines this milestone.
Users upgrading from v0.6.x must:

1. Stop the old cron / systemd timer (instructions in the `wm update`
   one-time migration message).
2. Run `wm daemon start` once to install + enable the new
   `wm-daemon.service` (systemd user unit).
3. The daemon then drives every existing schedule.

## Architecture decisions

### Daemon ↔ CLI communication

**SQLite shared with WAL mode.** No IPC protocol. No HTTP API. No
distributed Erlang.

```sql
PRAGMA journal_mode = WAL;
```

The daemon is the sole writer; the CLI opens its own connection with
read-only access. SQLite WAL handles one writer + many concurrent
readers without locking the readers behind the writer.

Migration of the existing DB: detect `journal_mode != "wal"` at daemon
boot and `PRAGMA journal_mode = WAL` it. The migration is idempotent
and survives copy / restore.

### Daemon lifecycle

- `wm daemon start` writes `~/.config/systemd/user/wm-daemon.service`,
  reloads systemd, enables + starts the unit.
- `wm daemon stop` issues `systemctl --user stop wm-daemon`.
- `wm daemon status` parses `systemctl --user is-active wm-daemon` and
  reads the schedulers' `last_tick_at` from a status file in
  `~/.local/share/watchman/daemon-status.json`.
- `wm daemon restart` is `stop` then `start` with a clean shutdown of
  the GenServers.

`Watchman.Daemon.Supervisor` writes the status file every minute so
`wm daemon status` does not need IPC.

### Graceful shutdown

On `SIGTERM` (systemd) the application calls
`Watchman.Daemon.Supervisor.terminate/2` which:

1. Stops accepting new ticks (sets `:draining` flag on each
   scheduler).
2. Waits up to 30 s for in-flight Pipeline runs to finish.
3. Persists `daemon-status.json` with `stopped_at`.
4. Exits.

systemd unit gets `TimeoutStopSec=45s` to give the drain time to
complete.

### Memory management

Long-lived processes accumulate garbage. Mitigations:

- Each scheduler's heap reset via `:erlang.garbage_collect/1` after
  every tick.
- `MemoryHigh=200M` on the systemd unit triggers a soft pressure
  signal before OOM.
- A weekly `:hibernate` on idle schedulers (between ticks) drops the
  heap to a minimum.

If a scheduler exceeds memory thresholds repeatedly, the supervisor
restarts it.

### Configuration

New `[daemon]` section in `~/.config/watchman/config.toml`:

```toml
[daemon]
enabled = true

[daemon.intervals]
news_cvm = "15m"
news_infomoney = "30m"
news_b3 = "1d"
news_rss = "30m"
price = "1h"
analysis = "1h"            # how often Pipeline.run/0 fires
outcome_closer = "1d"      # accuracy outcome close cadence

[daemon.alerts]
notify_on_material_fact = true
notify_on_dividend = true
```

Interval values parsed as `HhMm` / `Nm` / `Nh` / `Nd` via a small
`Watchman.Daemon.Interval` helper.

## Hard constraints (apply throughout)

- **`wm run` is REMOVED** at v0.7.0. No deprecation period — the
  command exits with `"wm run was removed in v0.7.0. The daemon
  handles ingestion now. Use: wm daemon start"`.
- **Daemon is the sole DB writer.** CLI opens its own read-only
  connection.
- **Schedulers must be idempotent.** A duplicate tick (e.g., systemd
  re-delivers `SIGUSR1`) must not double-insert news or analyses.
  Existing UNIQUE constraints on `analysis_outcomes` and the
  per-day-per-asset index on `analyses` already cover this.
- **No new runtime deps** unless justified. The standard library
  + `:gen_server` + existing Req / Ecto / SweetXml stack covers
  everything.
- **`@spec` + `@moduledoc` on every new module.** `mix credo --strict`
  clean.
- **Coverage**: schedulers tested with simulated clocks
  (`Process.send/3` `:tick` messages directly), no `Process.sleep`.

## Test strategy

| Layer | Approach |
|---|---|
| `Watchman.Daemon.Interval` | Pure parser; happy + malformed strings |
| Each scheduler GenServer | start_link, send `:tick`, assert side effect (DB row inserted / mock provider called), assert next-tick scheduled |
| `Watchman.Daemon.RateLimiter` | Concurrent claim/release tests, budget exhaustion |
| `Watchman.Daemon.Supervisor` crash recovery | Kill a child scheduler, assert restart, others unaffected |
| `wm daemon status` reading daemon-status.json | CaptureIO + fixture file |
| `wm run` removal | dispatch returns the removal-message exit code |

Use `Mox` for News.Provider / Market.Provider / AI.Provider at the
scheduler boundary. No `async: false` unless the GenServer
serialisation forces it.

## Ordered task list

1. **Daemon supervision tree skeleton** — `Watchman.Daemon.Supervisor`,
   empty children list. No-op start/stop. Verify it boots under
   `Watchman.Application` without breaking existing CLI commands.
2. **`Watchman.Daemon.Interval` helper** — pure string parser.
3. **`Watchman.Daemon.NewsScheduler`** — one GenServer per source or
   one with multiple registered intervals (pick during step 1
   design). Calls Watchman.News.Factory.providers/0 and persists via
   the existing NewsItem changeset.
4. **`Watchman.Daemon.PriceScheduler`** — replaces the price-fetch
   leg of `Pipeline.run/0` with a scheduled GenServer call.
5. **`Watchman.Daemon.AnalysisScheduler`** — calls
   `Watchman.Pipeline.run/0` on its tick. Pipeline.run/0 itself is
   reused from Track 4 — its callsite just moves from CLI to
   GenServer.
6. **`Watchman.Daemon.OutcomeCloser`** — wraps
   `Accuracy.close_pending_outcomes/1` on a daily tick.
7. **`Watchman.Daemon.RateLimiter`** — shared budget across schedulers
   (Brapi free tier).
8. **`Watchman.Daemon.StatusWriter`** — periodic write of
   daemon-status.json.
9. **WAL pragma** at Repo boot.
10. **`wm daemon start | stop | status | restart` CLI commands** —
    systemd unit installer + status reader.
11. **Remove `wm run`** — replace dispatch with the removal message.
    Update README + completions + ROADMAP.
12. **Remove `wm schedule` / `wm unschedule`** — daemon owns
    scheduling.
13. **`wm news TICKER` CLI command** — read-only listing from
    news_items, optional filters.
14. **`wm impact TICKER` CLI command** — joins news + analysis
    outcomes for a recent window.
15. **One-time migration in `wm update`** — detects old cron / systemd
    timer, prints removal instructions, exits non-zero until the user
    confirms.
16. **`mix.exs` version bump** to `0.7.0`.
17. **Docs** — flip ROADMAP, ARCHITECTURE (rewrite "Key Decisions"
    row), this document's Status block.

Conventional Commit prefixes: `feat(daemon):` for steps 1–10,
`feat(cli)!:` for the breaking `wm run` removal (step 11), `chore(release):`
for the version bump, `docs:` for the documentation pass.

## Migration plan for existing users

1. `wm update` (current version) pulls v0.7.0.
2. First post-upgrade invocation of any `wm` command prints:

   ```
   Watchman v0.7.0 changed how ingestion runs.

   The cron / systemd timer that ran "wm run" is no longer
   needed. A long-lived daemon now handles every fetch + analysis.

   Run this once:
     wm daemon start

   Then remove the old schedule:
     wm unschedule  (last invocation — this command is also removed)
   ```

3. User runs `wm daemon start`. The installer:
   - Writes `~/.config/systemd/user/wm-daemon.service`.
   - `systemctl --user daemon-reload && systemctl --user enable --now wm-daemon`.
   - Verifies `systemctl --user is-active wm-daemon` returns `active`.
4. `wm daemon status` confirms the schedulers are ticking.

## Out of scope (deferred to v0.7.x or v0.8.0)

- **Distributed daemon** (multi-node). Single-node only.
- **HTTP API for external clients**. CLI + SQLite is sufficient.
- **Hot code reload across versions**. `wm daemon restart` after
  `wm update` is fine.
- **Cluster of daemons sharing one DB**. Out of scope.

## References

- [REALIGNMENT.md](REALIGNMENT.md) — original analytical-layer ownership rationale.
- [ROADMAP.md](../ROADMAP.md) — v0.7.0 milestone entry.
- [ARCHITECTURE.md](../ARCHITECTURE.md) — to be updated by step 17.
- [track-1-accuracy.md](track-1-accuracy.md), [track-2-technical.md](track-2-technical.md), [track-3-news.md](track-3-news.md), `track-4-classifier.md` (TBW) — prior-track context.
- systemd user-unit reference: https://www.freedesktop.org/software/systemd/man/systemd.service.html
