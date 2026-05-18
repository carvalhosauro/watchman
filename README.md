# watchman

[![CI](https://github.com/carvalhosauro/watchman/actions/workflows/ci.yml/badge.svg)](https://github.com/carvalhosauro/watchman/actions/workflows/ci.yml)

Markets make noise constantly.
Bad news, sharp drops, analyst tweets, unexplained movement.
Most of it is noise. But not always.

**watchman** keeps an eye on your assets, reads what's happening around them,
and tries to answer the only question that matters:

> *is this something I need to understand right now, or can I ignore it?*

---

## What it does

You tell watchman which assets to follow — stocks, real estate funds, whatever you hold.

Every day, it checks how they're doing, reads the surrounding news,
and records everything: price, variation, context, and what it understood about the moment.

At the end of the day, the week, or the month —
watchman looks back.

It doesn't fetch anything new.
It reads what it already stored and builds a retrospective:
what changed, what held, what's still unanswered.

Sometimes what felt urgent on a Tuesday was nothing.
Sometimes what seemed like nothing was the beginning of something.

---

## What it doesn't do

It's not investment advice.
It has no access to your brokerage account.
It doesn't execute orders.

It's a starting point for you to think —
not a replacement for thinking.

---

## Who it's for

Anyone tracking a handful of assets on their own
who's tired of opening ten tabs, reading five sites,
and still not knowing whether that drop is worth worrying about.

---

## Install

One line:

```bash
curl -fsSL https://raw.githubusercontent.com/carvalhosauro/watchman/main/install.sh | bash
```

This will:
- Check for Elixir/Erlang (guides you to install if missing)
- Clone the repo to `~/.local/share/watchman`
- Install dependencies and compile
- Create `wm` command in `~/.local/bin`
- Optionally run the setup wizard

### Requirements

- [Elixir](https://elixir-lang.org/install.html) 1.17+
- Erlang/OTP 27+

### Manual install

```bash
git clone https://github.com/carvalhosauro/watchman.git ~/.local/share/watchman
cd ~/.local/share/watchman
mix deps.get && mix compile
ln -s ~/.local/share/watchman/bin/wm ~/.local/bin/wm
wm setup
```

### Uninstall

```bash
curl -fsSL https://raw.githubusercontent.com/carvalhosauro/watchman/main/uninstall.sh | bash
```

---

## Setup

```bash
wm setup
```

Interactive wizard that configures:
- **AI provider** — Claude, Gemini, or DeepSeek
- **Market provider** — Brapi or Yahoo Finance
- **API keys** — stored in system keyring (Linux/macOS) or config file
- **Pipeline settings** — concurrency and timeouts

API keys are stored securely:
1. System keyring (recommended) — `secret-tool` on Linux, Keychain on macOS
2. Config file with `chmod 600` — fallback when keyring unavailable
3. Environment variables — always override other sources

---

## CLI

```bash
wm assets MXRF11 PETR4 ITUB4   # register assets (auto-detects FII vs stock)
wm list                          # list tracked assets
wm remove MXRF11                # stop tracking
wm run                           # run analysis for all tracked assets
wm show                          # show today's analyses
wm show PETR4                    # show history for a ticker
wm show -l 5                     # show last 5 analyses
wm retro -w                      # weekly retrospective
wm retro -m                      # monthly retrospective
```

The database is created automatically on first run at `~/.local/share/watchman/watchman.db`.

---

## Shell Completions

Tab-completion for commands, tickers, and retrospective IDs.

```bash
# Bash — add to ~/.bashrc
eval "$(wm completions bash)"

# Zsh — add to ~/.zshrc
eval "$(wm completions zsh)"
```

---

## Scheduling

Run analyses automatically every day:

```bash
wm schedule            # interactive setup (systemd or cron)
wm schedule status     # check if schedule is active
wm unschedule          # remove scheduled runs
```

---

## Logs

```bash
wm logs                # last 50 lines
wm logs -f             # follow in real-time
wm logs -n 100         # last N lines
```

Logs are stored at `~/.local/share/watchman/logs/watchman.log`.

---

## Philosophy

More data is not more clarity.
watchman doesn't try to give you everything —
it tries to give you enough
to make decisions with less anxiety and more context.

[License GPL-2.0-only](LICENSE)
