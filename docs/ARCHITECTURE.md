# Architecture

The blueprint asked for a lot of separate things: a bot dashboard, WHOOP,
Mac vitals, calendar, Focus, music, contextual layouts per app, a Morning
Brief, macros, widgets, a Live Activity, Siri, USB-C mode and multi-Mac.
Built one by one, that would be a dozen integrations each with its own
polling, UI, settings and failure modes.

This build combines all of them with four ideas. Everything else follows
from these.

1. **One hub.** The Mac owns every piece of state. Everything else is a view.
2. **Channels on demand.** A data source runs only while something on screen
   needs it.
3. **One action language.** Every button, scene, widget, Siri phrase and
   script sends the same `ButtonAction`.
4. **Everything is a tile, and context picks the page.** Pages are lists of
   tiles on one grid, and a small rule engine decides which page you see.

```
                         ┌────────────────────── Mac: ControlCenter Helper ──────────────────────┐
                         │                                                                        │
 NSWorkspace, AX ───────▶│  Providers (start/stop on demand)          Hub (@MainActor)            │
 EventKit, DND DB ──────▶│  context · apps · system · media · audio   ├─ LiveState (17 channels)  │
 Spotify/Music ─────────▶│  calendar · focus · bot · whoop · weather  ├─ Workspace (pages, tiles, │
 Bot REST / webhook ────▶│  timers · daily · portfolio · git          │   keys, rules, scenes)    │
 WHOOP · Open-Meteo ────▶│                                            ├─ TimerEngine · DailyStore │
 PortTracker · git ─────▶│  ActionExecutor ◀── ButtonAction ──────────┤                           │
                         │  keys · text · AppleScript · shell · windows · media · audio · calls   │
                         │  bot · focus · timers · git · scenes · macros · apps · clipboard       │
                         │                                                                        │
                         │  HubServer (Bonjour, TLS-free E2E crypto)   LocalAPI 127.0.0.1:52521    │
                         │  USBBridge (usbmuxd → iPad:52530)           APNsPusher (optional)       │
                         └───────────▲───────────────────▲───────────────────▲────────────────────┘
                                     │ Wi-Fi / AWDL      │ USB-C             │ HTTP (loopback)
             ┌───────────────────────┴──────┐   ┌────────┴────────┐   ┌──────┴───────────────┐
             │ iPad app (pages, editor)     │   │ same protocol    │   │ your bot, scripts,   │
             │ iPhone app (compact pages)   │   │ over the cable   │   │ Raycast, cron        │
             │ widgets · controls · intents │   └──────────────────┘   └──────────────────────┘
             │ (one-shot sessions)          │
             └──────────────────────────────┘
```

## 1. One hub

The helper is the single source of truth:

- **Live state:** 17 typed channels (`context`, `system`, `bot`, `whoop`,
  `timers`, …).
- **The workspace:** pages, tiles, keys, rules, scenes and preferences. It is
  saved as `workspace.json`, which is watched on disk, so you can also edit it
  by hand.
- **Timers:** the hub runs them. Clients get `endsAt` and count down on their
  own.
- **The day:** priorities, study mode and whether the Brief was dismissed.
- **Integrations and their secrets.** Secrets live in the Mac's Keychain and
  never travel to the iPad; only `has…` flags do.

Every client is a thin renderer plus an action sender: the iPad, the iPhone,
widgets, Live Activity, Siri, Control Center controls and the local HTTP API.
The results:

- **Consistency for free.** Start a timer from Siri and the iPad, the
  widgets, the iPhone Live Activity and the menu bar all show the same
  countdown, because they all read the same `timers` value.
- **Two iPads, or an iPad and an iPhone, just work.** Layout edits carry a
  revision number (optimistic concurrency), so a stale editor gets the
  current layout back instead of overwriting it.
- **Multi-Mac:** each Mac runs its own hub. The app remembers every Mac it
  has paired with and connects to whichever is on the network.

## 2. Channels on demand

A provider declares the channels it produces. The hub turns a provider on
only while at least one connected client subscribes to one of its channels:

- **What subscribes:** each client subscribes to the channels its current
  page's tiles declare (`WidgetKind.channels`), plus a small always-on set
  for the chrome. That set is `context`, `audio`, `timers`, `daily`, `focus`,
  `helper` and `media`, plus `bot`, `botSeries`, `whoop` and `calendar`,
  which the widgets and the context engine read.
- **Nobody watching:** no bot polling and no AppleScript calls to Spotify.
  With the iPad locked in a drawer, the helper is close to idle.
- **Event-driven wherever macOS allows it:**
  - app switches (NSWorkspace);
  - window-title changes (an Accessibility observer, debounced to 250 ms);
  - track changes (Spotify and Music distributed notifications);
  - calendar changes (EventKit);
  - Focus changes (the DoNotDisturb database);
  - screen lock and sleep.

  Polling remains only where nothing pushes: CPU and memory at 2 s, the bot
  at 2 s, and the weather every 30 min. Elsewhere there are slow safety polls:
  media drift, Focus every 20 s, the calendar every 5 min.
- **Deltas only.** A provider publishes when its value changes, and
  clock-driven values are extrapolated by clients: media position from
  `positionAt`, timers from `endsAt`.

This is what lets the blueprint's "every 2 s" bot polling and live Mac stats
coexist with a battery-friendly Mac.

## 3. One action language

`ButtonAction` (in `CCCore/ButtonAction.swift`) is a flat, type-tagged JSON
value. It is the blueprint's `{ "type": "keyCombo", "keys": ["cmd", "shift",
"4"] }`, extended to 24 action types:

| Group | Types |
|---|---|
| Keyboard | `keyCombo` (layout-aware: works on AZERTY), `text` (with `{{date}}`, `{{url}}`, `{{title}}`, `{{clipboard}}`, `{{input}}` templates) |
| Automation | `appleScript`, `shell`, `shortcut`, `macro` (steps with delays), `scene` (a named macro plus a page) |
| Apps & files | `openApp`, `app` (activate, hide, quit), `openURL`, `openPath`, `clipboard` |
| Mac | `media`, `system` (Mission Control, lock, screenshot, brightness, dark mode…), `window` (halves, thirds, next display…), `audio` (mic mute, volume) |
| Calls | `call` (mute, camera, raise hand, leave, share), sent as that app's own shortcut to Zoom, Teams, Webex or Discord, or to Google Meet when its tab is in front. With no call app, mute falls back to the Mac's microphone. |
| Integrations | `bot`, `focus`, `timer`, `git`, `daily`, `integration` |
| Client | `navigate` (runs on the iPad without a round trip) |

Everything that *does* something is one of these:

- keys on a page;
- buttons inside tiles (a pause button on the bot tile is `bot.pause`);
- scenes (**Start the Day** = `daily.startDay` → `focus.on` → open apps →
  `timer.deepWork`);
- interactive widgets, Control Center controls and Siri intents;
- `POST /v1/action` on the local API;
- recorded macros.

There is exactly one executor, on the Mac. So a new integration becomes
usable everywhere (iPad, widget, Siri, script) the moment it has an action
type. Properties on the action, not on the caller, decide the UX:

- `isDestructive` asks for confirmation;
- `needsAccessibility` warns when the permission is missing;
- `promptsForInput` asks for the `{{input}}` value first.

## 4. Everything is a tile; context picks the page

**Tiles.** A page is an ordered list of tiles. There are 33 kinds:

- bot summary, chart, positions and health;
- recovery;
- agenda, Pomodoro, now playing and weather;
- priorities and movers;
- key grids.

Tiles are placed on a **12×12 grid** by dense first-fit packing (CSS
`grid-auto-flow: row dense`). Rearranging a page is just reordering the
list, so the editor needs only drag-to-reorder and a size picker. The
blueprint's "4 quadrants", "Bot dashboard", "Study" and every contextual
layout are data in `DefaultWorkspace.swift`, not code.

**Context engine** (`CCCore/ContextEngine.swift`, runs on the client):

- **Inputs:** the frontmost app, window title, browser URL and presence from
  the Mac, plus derived **modes**:

  | Mode | When |
  |---|---|
  | `morning` | first connection inside the 06:00–10:00 window, Brief not dismissed |
  | `study` | study mode on, the study Focus active, or a lecture on the calendar now |
  | `focusSession` | a Pomodoro or deep-work timer running |
  | `meeting` | a call app frontmost, or the mic live during a calendar event |
  | `away` | Mac locked, asleep or idle |

- **Rules** are priority-ordered matches on any combination of bundle IDs,
  URL fragments, title keywords (whole-word and diacritic-insensitive, so
  "les" matches "Les Statistiek" but not "sales"), Focus names, modes, time
  windows and weekdays. The top match picks the page.

  One app can mean different things. Safari is the Safari page on a normal
  afternoon, the Study page during a lecture, and the Bot page when the tab is
  `localhost:8000`.
- **Manual choice wins until the context changes.** Tap another page and it
  stays until you switch apps, the tab moves to another site, or a mode
  flips. The engine keys this on a "context key", not a timer. **Pin** locks
  the current page indefinitely.

## Security and transport

Details are in [PROTOCOL.md](PROTOCOL.md):

- **Pairing:** a one-time 6-digit, commitment-based code (ZRTP-style SAS).
  It yields a 256-bit per-device key held in both Keychains.
- **Every session:** mutual HMAC proofs, then per-direction
  ChaCha20-Poly1305 with counter nonces, which makes replay and reordering
  impossible. There are no certificates and no cloud.
- **Transports:** Wi-Fi or AWDL (Bonjour `_ccontrol._tcp`), USB-C (usbmuxd
  tunnel to iPad port 52530, preferred when present), and one-shot sessions
  for widgets, intents and controls. They all speak the same protocol.
- **Local HTTP API:** 127.0.0.1:52521, loopback-only, bearer token. This is
  how your bot, scripts and cron jobs push into the hub.

## Code map

| Path | What |
|---|---|
| `Packages/ControlCenterKit/Sources/CCCore` | Models and pure logic: messages, live state, workspace, actions, context engine, grid packer, Brief composer, formatting, templates, JSON paths, simulation. Unit tested, no UI. |
| `Packages/ControlCenterKit/Sources/CCNet` | Byte streams (TCP, usbmux fd, in-memory pipe), framed channel, pairing and session crypto, Keychain, one-shot client. Unit tested. |
| `Apps/Helper` | The Mac hub. `Core/` (hub, identity, persistence, secrets), `Providers/`, `Actions/` (executor, key synthesis, AppleScript, shell, windows, macro recorder), `Server/` (Bonjour server, pairing UI, local API, USB), `Services/` (permissions, APNs), `UI/` (menu bar, preferences). |
| `Apps/iOS` | The iPad/iPhone app. `Connection/` (hub link, demo hub), `Core/` (app model, live store, navigator), `Chrome/`, `Pages/`, `Tiles/`, `Editor/`, `Pairing/`, `Settings/`, `Phone/`. |
| `Apps/Widgets` | Widgets, the Live Activity and iOS 18 Control Center controls |
| `Apps/Shared` | Theme, App Intents, the store shared with widgets (App Group plus Keychain access group), Live Activity attributes |
| `Tools/make-icons.swift` | Renders every app icon (standard, dark and tinted) from code |

**Concurrency** (Swift 6, strict):

- The hub, providers and UI are `@MainActor`.
- I/O is `async`. AppleScript runs on its own thread, because
  `NSAppleScript` isn't thread-safe. Shell commands read stdout and stderr
  concurrently, so a chatty process can't deadlock on a full pipe.
- The message channel is an actor, and each session has a single writer task,
  so frames never interleave.

## Test hooks

| Switch | Effect |
|---|---|
| `-CCDemo` (app) | A built-in hub with realistic simulated data, used for design work and screenshots |
| `-CCDemoHome`, `-CCPage <id>` | Start the demo on the home page, or pin a given page |
| `CC_E2E=1` (helper) | No permission prompts, no login item, no HUD or sounds; log to stdout |
| `CC_PRINT_PAIRING_CODE=1` | Print `CC_PAIRING_CODE=123456` when pairing starts |
| `CC_INSTANCE=test` | A second, fully separate hub next to your real one: its own identity, data folder (`ControlCenter-test`), random port, secrets in a 0600 file instead of the Keychain, and no local API or USB |
