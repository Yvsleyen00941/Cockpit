# Connecting your trading bot

Control Center shows your bot's P&L, positions, trades and health. It also
lets you pause, resume or flatten it from the iPad, a widget, a Control Center
control, or Siri ("Pause the bot with Control Center").

Your bot does **not** need to change. The helper reads whatever JSON your bot
already serves and maps its field names (see [Field mapping](#field-mapping)).
There are two ways in, and you can use both:

| Direction | What | When |
|---|---|---|
| Helper → bot | polls `GET /status` (and optionally `/events` and `/pnl`) | every 2 s, only while an iPad, iPhone or widget is looking |
| Bot → helper | pushes to `POST /v1/bot/event` and `POST /v1/bot/status` on the helper's local API | trade toasts reach the iPad instantly instead of at the next poll |

Until you switch the helper to **Live**, it runs a realistic simulated bot, and
every screen shows a `SIM` badge so you never mistake it for real money.

## Settings

Set these in the helper under **Preferences → Trading Bot**:

| Setting | Default |
|---|---|
| Mode | `Simulated` (other options: `Live`, `Off`) |
| Base URL | `http://127.0.0.1:8000` |
| Status path | `/status` |
| Events path | `/events` (leave empty to skip) |
| P&L series path | `/pnl` (leave empty to skip) |
| Pause / Resume / Close all | `/pause`, `/resume`, `/close-all` |
| Poll interval | 2 s (minimum 1 s) |
| API key | optional; sent as `Authorization: Bearer <key>` and stored in the helper's Keychain |

**Test connection** polls once and shows the result.

## `GET {status}`: required

Every poll reads one JSON object. These are the fields the helper looks for,
by default name:

```json
{
  "status": "running",
  "pnl_today": -190.47,
  "pnl_today_pct": -0.76,
  "equity": 24810.00,
  "currency": "EUR",
  "trades_today": 60,
  "last_heartbeat": "2026-09-25T09:14:03Z",
  "api_connected": true,
  "positions": [
    {
      "symbol": "BTC-EUR",
      "side": "long",
      "qty": 0.05,
      "entry_price": 57360.03,
      "current_price": 57420.10,
      "unrealized_pnl": 3.00,
      "opened_at": 1790320443
    }
  ]
}
```

| Field | Notes |
|---|---|
| `status` | `running`, `active`, `trading`, `live`, `on` → Running. `paused`, `pause`, `halted` → Paused. `stopped`, `idle`, `off`, `disabled` → Stopped. Anything else → Unknown. Not case-sensitive. |
| `pnl_today` | number, in `currency` |
| `pnl_today_pct` | **percent**: `-0.76` means −0.76 %. If it's missing, it is derived from `equity`. |
| `equity` | optional |
| `currency` | optional, default `EUR` |
| `trades_today` | optional. If missing, the helper counts today's trades from the events it has seen. |
| `last_heartbeat` | optional. Epoch seconds, epoch milliseconds or ISO 8601. Drives the heartbeat chip on the health tile: green while under 10 s old, yellow under a minute, red after that. |
| `api_connected` | optional, default `true`. Means the bot's connection to the exchange or broker. |
| `positions` | optional array; see below |

Position fields accept common aliases:

| Meaning | Accepted keys |
|---|---|
| symbol | `symbol`, `instrument` |
| side | `side` (anything starting with `s` is short) |
| quantity | `qty`, `quantity`, `size`, `amount` |
| entry | `entry_price`, `entry`, `avg_price`, `average_price`, `open_price` |
| current | `current_price`, `price`, `mark`, `mark_price`, `last` |
| unrealised P&L | `unrealized_pnl`, `unrealised_pnl`, `upnl`, `pnl`; computed from the prices if missing |
| opened | `opened_at` |

If the request fails or returns a non-2xx status, the status turns red
(**Offline**). The last good numbers stay on screen, and the health tile
shows the error.

## Field mapping

If your bot uses other names or nests them, map each field to a path:

```json
{ "pnlToday": "stats.daily.pnl", "equity": "account.equity", "positions": "data.open_positions" }
```

Keys you can map: `status`, `pnlToday`, `pnlTodayPct`, `equity`, `currency`,
`tradesToday`, `lastHeartbeat`, `apiConnected`, `positions`. Paths use dots
for objects and `[n]` for arrays (`data.accounts[0].equity`); `$` is the
root. Numbers that arrive as strings (`"1,234.5"`) are accepted.

## `GET {events}?since=<id>`: optional

Trades and notable events, newest first or in any order. The helper sends the
ID of the newest event it already has as `since`. It deduplicates by `id` in
any case, so ignoring `since` is fine.

Either a bare array or `{ "events": [ … ] }`:

```json
[
  { "id": "t-1842", "side": "buy",  "symbol": "BTC-EUR", "qty": 0.05, "price": 57360.03, "ts": "2026-09-25T09:14:03Z" },
  { "id": "t-1843", "side": "sell", "symbol": "BTC-EUR", "qty": 0.05, "price": 57611.20, "pnl": 12.56, "outcome": "take profit", "ts": 1790321100 },
  { "id": "e-77",   "type": "warning", "message": "Spread widened", "ts": 1790321160000 }
]
```

| Field | Notes |
|---|---|
| kind | `side`, `kind` or `type`. `buy`, `long`, `open_long` → Buy. `sell`, `short`, `close`, `open_short` → Sell. `paused`, `resumed`, `error`, `warning` → as named. Anything else → Info. |
| time | `ts`, `time` or `timestamp`, in any of the date formats |
| `id` | strongly recommended. Without it, the ID becomes time plus kind. |
| `symbol`, `qty`/`quantity`, `price`, `pnl`, `outcome`/`status`, `message` | all optional |

Every **new** buy or sell becomes a toast on the iPad (`BUY BTC-EUR ·
0.05 @ 57,360.03`) and an entry in the helper's log. The last 300 events
are kept in `bot-ledger.json`, which also feeds the Morning Brief's
**overnight** line: trades between 22:00 and 07:00.

## `GET {pnl}`: optional

Today's P&L curve for the chart, fetched at most once a minute. Either:

```json
[[1790294400, 0.0], [1790298000, 12.4], [1790301600, -8.9]]
```

or objects with `t`/`time`/`ts` and `v`/`pnl`/`value`, as a bare array or
under `points`. Without this endpoint, the helper builds the curve itself from
the polls: one point every 2 minutes, up to 800 a day.

## Commands

`POST {pause}`, `POST {resume}`, `POST {close-all}`, with an empty body and the
API key, if one is set. Any 2xx counts as success; the helper then polls
immediately, so the new state shows within a second. Anything else is shown
on the iPad together with the first 200 characters of your response body.

**Close all** asks for confirmation on the iPad, because it's destructive.

## Pushing to the helper (webhook)

The helper runs a small HTTP API on **127.0.0.1:52521**. It accepts
connections from this Mac only.

```sh
TOKEN=$(defaults read be.yorben.controlcenter.helper localAPIToken)

# A trade: one event, an array, or {"events": [...]}; same fields as above
curl -s -X POST http://127.0.0.1:52521/v1/bot/event \
  -H "Authorization: Bearer $TOKEN" \
  -d '{"id":"t-1844","side":"buy","symbol":"ETH-EUR","qty":0.8,"price":2311.4,"ts":"2026-09-25T10:02:11Z"}'

# A full status (same shape as GET /status), e.g. right after a fill
curl -s -X POST http://127.0.0.1:52521/v1/bot/status \
  -H "Authorization: Bearer $TOKEN" \
  -d '{"status":"running","pnl_today":42.10,"equity":25042.10}'
```

The token is also shown, and can be regenerated, in **Preferences →
Advanced**.

From Python, fire-and-forget:

```python
import os, requests

CC = "http://127.0.0.1:52521"
TOKEN = os.environ["CC_TOKEN"]  # defaults read be.yorben.controlcenter.helper localAPIToken

def notify_trade(trade):
    try:
        requests.post(f"{CC}/v1/bot/event", timeout=0.5,
                      headers={"Authorization": f"Bearer {TOKEN}"},
                      json={"id": trade.id, "side": trade.side, "symbol": trade.symbol,
                            "qty": trade.qty, "price": trade.price, "pnl": trade.pnl,
                            "ts": trade.time.isoformat()})
    except requests.RequestException:
        pass  # the iPad simply picks it up on the next poll
```

## A minimal adapter

If your bot has no HTTP API yet, this is enough (FastAPI):

```python
from fastapi import FastAPI
import time

app = FastAPI()
bot = ...  # your bot

@app.get("/status")
def status():
    return {
        "status": "paused" if bot.paused else "running",
        "pnl_today": bot.pnl_today(),
        "pnl_today_pct": bot.pnl_today_pct(),
        "equity": bot.equity(),
        "currency": "EUR",
        "last_heartbeat": time.time(),
        "api_connected": bot.exchange_ok(),
        "positions": [p.as_dict() for p in bot.positions()],
    }

@app.post("/pause")
def pause():
    bot.pause()
    return {"ok": True}

@app.post("/resume")
def resume():
    bot.resume()
    return {"ok": True}

@app.post("/close-all")
def close_all():
    bot.close_all()
    return {"ok": True}
```

Run it with `uvicorn adapter:app --port 8000`. The defaults already point
there.

## "Bot command center" page switch

When the frontmost browser tab is `localhost:8000` or `127.0.0.1:8000`, the
iPad switches to the Bot page on its own (rule **Bot command center** in the
iPad's Settings → Rules). If your dashboard lives elsewhere, edit that rule's
URL, or add your dashboard app's bundle ID to it.
