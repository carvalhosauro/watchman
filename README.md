# watchman

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

## Setup

```bash
# install dependencies
mix deps.get

# set API keys
export ANTHROPIC_API_KEY="your-key"
export BRAPI_TOKEN="your-token"
```

## CLI

```bash
# register assets to track
./bin/wm assets MXRF11 PETR4 ITUB4

# run analysis manually
./bin/wm run

# generate a retrospective
./bin/wm retro --weekly
./bin/wm retro --monthly

# list tracked assets
./bin/wm list

# stop tracking an asset
./bin/wm remove MXRF11
```

The database is created automatically on first run at `~/.local/share/watchman/watchman.db`.

watchman also runs on its own, every day, at whatever time you configure.

---

## Philosophy

More data is not more clarity.
watchman doesn't try to give you everything —
it tries to give you enough
to make decisions with less anxiety and more context.

[License GPL-2.0-only](LICENSE)
