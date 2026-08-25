---
name: gloomberb
description: Gloomberb CLI (market research TUI, v0.10.x) — headless JSON/NDJSON market data from Yahoo, Gloom Cloud, FRED, and CNN. Use when running any gloomberb command or fetching quotes, history, fundamentals, options chains, econ calendar, FRED series, or correlations through it. Carries the verified sharp edges: level-vs-return correlation trap (correlation vs fn CORR), unit-free econ calendar strings, options OI-vs-quotes reliability, the fn/catalog pane surface, and the IBKR order-command guardrail. Research tool only — never a production data dependency.
allowed-tools: Read, Bash, Grep
---

<!-- Auto-synced from ~/.claude/includes/gloomberb.md — do not edit manually -->

# Gloomberb CLI — Market Research TUI with Headless JSON Output

Local finance terminal (`gloomberb`, bun-based, installed at `~/.local/bin/gloomberb`; verified against **v0.10.5**, data dir `~/.gloomberb`). Data sources: **Yahoo Finance** (quotes, history, fundamentals, options), **Gloom Cloud** (its own hosted session — news, FRED passthrough, congress/substack/x-feed), **CNN** (Fear & Greed), **RSS**. Quotes are **delayed** (`source: "delayed"`), not real-time.

**Standing verdict: research / prototyping tool — NOT a production dependency.** The semantic traps below (level-vs-return correlation, unit-free calendar strings, junk option IV) disqualify it as an input to anything money sits on. Use it for quick market lookups, exploration, and cross-checking; pipe nothing from it into production calc paths.

## Output Modes

- Default: human-readable tables.
- `--json`: envelope `{"ok": true, "data": ..., "metadata": {...}, "columns": [...]}`. Full float precision. **Prefer this for any numeric work.**
- `--ndjson`: one flat object per row — but *display-formatted*: `price` is a string (`"$772.67"`) with the number in `rawPrice`, and `changePercent` is rounded to 2 dp. Fine for streaming/grep, wrong for precision.

## Command Surface (the useful, verified subset)

```bash
gloomberb quote SPY TLT --json          # delayed quotes, batch
gloomberb history SPY --range 1M --json # daily OHLCV rows {date, open, high, low, close, volume}
gloomberb compare SPY QQQ IWM --json
gloomberb indices --json                # major US indices
gloomberb sectors --json                # SPDR sector ETFs
gloomberb movers gainers --json         # gainers|losers|active|trending
gloomberb fx EUR --json
gloomberb fundamentals AAPL --json      # also: financials, valuation, holders, insider, 13f, analyst, events, earnings, filings
gloomberb news AAPL --feed ticker --json
gloomberb options SPY --json            # see options trap below
gloomberb econ --country US --impact high --json   # see calendar trap below
gloomberb fred DGS10 --start 2024-01-01 --json     # FRED via Gloom Cloud session; {date, value} rows
gloomberb yield-curve --json            # standard Treasury FRED series in one call
gloomberb fear-greed --json             # CNN gauge: score, rating, previous close/week/month/year
gloomberb search "term" / provider-search "term"
gloomberb doctor                        # config/db/plugins/capabilities health
gloomberb provider status               # which source serves which operation
gloomberb cache status                  # local cache db: ~/.gloomberb/.gloomberb-cache.db
```

`fred`, `congress`, `substack`, `x-feed`, `buildout` require an existing **Gloom Cloud session** (pre-authed on this machine — `gloomberb doctor` to confirm). FRED observations carry **no vintage/ALFRED availability dates**.

## 🚨 Trap 1 — Two Correlations, Opposite Answers

`gloomberb correlation A B` (alias `relationship`) computes **1Y close-price *level* correlation**. `gloomberb fn CORR A,B` computes **daily-*return* correlation**. Verified same-day on SPY/TLT: `correlation` → **−0.708** (251 samples), `fn CORR` → **+0.237** (250 samples). Level correlation of trending series is a statistics-101 artifact and almost never what a finance question means.

- **Default to `fn CORR`** — ticker-list argument, `--rangePreset <1M|3M|6M|1Y|5Y>` (default 1Y), needs ≥5 shared observations.
- Rolling correlation: `fn GR` (`--correlationWindow <n>`, default 120; `--range`), but a single ticker is always compared **vs SPY** — it does not take arbitrary pairs.
- Reach for the top-level `correlation` command only when you explicitly want level co-movement, and say so.

## 🚨 Trap 2 — Economic Calendar Values Are Unit-Free Strings

`econ` rows carry `actual` / `forecast` / `prior` as **free-text strings with no unit field**, and units are mixed *within one row*: observed (v0.10.4) a CPI row with `actual` as an **index level** (336.8) next to forecast/previous in **percent**. Empty strings for not-yet-released values. Never compare these numerically or compute surprises without per-event unit judgment; treat them as display text. The schedule itself (`date` ISO-8601 UTC, `impact`, `event`) is reliable and useful.

## 🚨 Trap 3 — Options Chain: OI Is Trustworthy, Quotes/IV Are Not

`options SYMBOL --json` returns `data` as a **dict** (not rows): `{underlyingSymbol, expirationDates, calls, puts, dataSource, delayMinutes, asOf}`. Without `--expiration` you get only the **nearest expiry**; `expirationDates` are **unix seconds** — pick one and pass `--expiration <unix>`.

Yahoo-sourced quote fields are stale/wide: verified a deep-ITM SPY call with `impliedVolatility: 1.376` (137%!), `volume: 0`, and a days-old `lastTradeDate`. **`openInterest` is the robust field** (daily-settled, not a quote). Build OI-based measures (put/call OI, strike-gamma from OI); do not trust per-contract `impliedVolatility`, `bid`/`ask`, or `lastPrice` for pricing or skew.

## Pane Functions (`fn` / `shot` / `catalog`)

The TUI's panes are partially exposed headless. `gloomberb catalog [query]` lists them (25 of 60 CLI-usable; `--all` for everything); each entry states `Bot safe`, `Readiness: report=…`, options, and limitations — **read the entry before using an unfamiliar function**. `gloomberb shot <FN> <arg> --output /tmp/x.png` renders a desktop-style PNG of any report-ready pane (useful for showing the user a chart).

`report=ready` set (v0.10.5), all bot-safe:

| Fn | What | Key options |
|---|---|---|
| `CORR` | Return-correlation matrix (the correct correlation) | `--rangePreset` |
| `GR` | Ratio / rolling corr / regression **vs SPY only** | `--range`, `--correlationWindow` |
| `CMP` | % performance comparison, multi-ticker | `--rangePreset`, `--axisMode`, `--chartResolution` |
| `G` | Chart arbitrary market/fundamental/FRED series together | `--rangePreset`, `--chartResolution` |
| `GP` / `GIP` / `HP` | Price chart / 1-min intraday / OHLCV table | `--range` (HP) |
| `FA` | Financial statements, one company | `--period`, `--statement` |
| `GF` | Fundamental metric graph, multi-ticker, one metric per call | `--metric`, `--period`, `--periods` |
| `GE` | Valuation-multiple graph | `--metric` (default `priceSales` — NOT trailingPE despite the description), `--period`, `--periods` |
| `RV` | Relative valuation across peers (current, not historical) | — |
| `QQ` | Quote monitor | — |

## Guardrails (agent sessions)

- **Never run `ibkr preview|place|cancel`** — these are real broker order commands; placing/canceling orders is user-only, always. `ibkr accounts|positions|orders` (read-only) only when the user asks.
- **Don't invoke `ai …` headless prompts unasked** — they spend the user's configured AI-provider credits.
- Local-state mutators (`portfolio`, `watchlist`, `alerts`, `notes`, `cache clear`, plugin `install`/`remove`) are safe but touch the user's saved setup — mutate only on request.
- `launch-ui` / bare `gloomberb` starts a fullscreen TUI — useless in a non-interactive shell; stick to subcommands.
