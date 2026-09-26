# Control Center wire protocol (v1)

The iPad/iPhone app and the Mac helper talk over one TCP connection per
device. The helper advertises itself with Bonjour; the app pairs once with a
6‑digit code. After that, every connection is mutually authenticated and
encrypted. Everything below is implemented in `Packages/ControlCenterKit`
(`CCCore` for messages, `CCNet` for transport and crypto) and is shared by
both sides, so the two can't drift apart.

## Discovery

| | |
|---|---|
| Service type | `_ccontrol._tcp` |
| Port | 52520 (the helper falls back to a random port if it's taken) |
| Name | the Mac's computer name |
| TXT `id` | stable Mac ID (UUID) |
| TXT `v` | protocol version (`1`) |
| TXT `model` | e.g. `MacBook Pro · M3 Pro` |
| TXT `host` | `Yorbens-MacBook-Pro.local` |

The app browses with peer-to-peer allowed, so it also finds the Mac without a
shared router (AWDL). A paired Mac is matched by its TXT `id`, not by name.
The last good IP and port are remembered and dialed directly when Bonjour is
slow or silent.

**USB-C:** the helper watches `usbmuxd` for a trusted iPad. When one attaches,
it opens a tunnel to port **52530** on the iPad, where the app listens on
loopback while it is in the foreground. Exactly the same protocol runs over
the tunnel, and the app prefers it over Wi‑Fi whenever it's up.

## Framing

```
┌──────────────┬──────────────────────────────┐
│ length (u32, │ body (length bytes)          │
│ big-endian)  │                              │
└──────────────┴──────────────────────────────┘
```

- The body is JSON during the handshake and an encrypted frame afterwards.
- Maximum frame size is 8 MiB.
- A receive with a deadline that expires closes the stream, because a
  half-read frame would desynchronise the channel.

TCP runs with Nagle off and keep-alive on (idle 5 s, interval 2 s, 3 probes),
so a vanished peer is noticed within about 11 s even when nothing is being
sent.

## Envelope

```json
{ "type": "buttonTap", "id": 7, "payload": { … } }
```

| Field | Meaning |
|---|---|
| `type` | one of the message types below |
| `id` | optional request ID. A response echoes it as `replyTo`. |
| `replyTo` | ID of the request being answered |
| `payload` | type-specific object |

Unknown message types and unknown action types are **kept, not rejected**
(`ButtonAction.unsupported`), so an older app can round-trip a workspace
written by a newer helper without losing buttons.

## Message types

The blueprint's names are kept verbatim: `appDidChange`, `liveDataUpdate`,
`buttonConfigUpdate`, `buttonTap`, `requestLayout` and `ping`. The rest
extend them.

### Handshake (plaintext)

| Type | Direction | Payload |
|---|---|---|
| `pairBegin` | app → Mac | `deviceID`, `deviceName`, `platform`, `commitment` |
| `pairKey` | Mac → app | `macID`, `macName`, `publicKey`, `nonce` |
| `pairReveal` | app → Mac | `publicKey`, `nonce` |
| `pairConfirm` | app → Mac | `mac` (HMAC) |
| `pairResult` | Mac → app | `ok`, `mac?`, `reason?` |
| `hello` | app → Mac | `protocolVersion`, `deviceID`, `deviceName`, `platform`, `appVersion`, `nonce`, `transport` |
| `challenge` | Mac → app | `macID`, `macName`, `nonce`, `known` |
| `auth` | app → Mac | `proof` |
| `authResult` | Mac → app | `ok`, `proof?`, `reason?`, `helperVersion?` |

### App → Mac (encrypted)

| Type | Payload | Notes |
|---|---|---|
| `buttonTap` | `action`, `buttonID?`, `pageID?` | Answered by `actionResult` (`ok`, `message`, `output`, `durationMs`). |
| `requestLayout` | `knownRevision?` | Answered by `buttonConfigUpdate`, but only if the revision changed. |
| `updateLayout` | `baseRevision`, `workspace` | Optimistic concurrency. If `baseRevision` is stale, the reply is a failed `actionResult` followed by the current `buttonConfigUpdate`. |
| `subscribe` | `channels: [Channel]` | Replaces the device's subscription. The hub runs only the providers that someone is watching. |
| `requestSnapshot` | `channels` | One-shot `liveDataUpdate` with `full: true`. Used by widgets and intents. |
| `ping` | `seq`, `t` | Sent every 2 s. The Mac answers with `pong` carrying the same payload, which gives the latency. |
| `requestIcons` | `bundleIDs`, `size` | Answered by `icons`: PNG data per bundle ID. |
| `requestArtwork` | `id` | Answered by `artwork`: JPEG, at most 360 px. |
| `query` | `kind` | `shortcuts`, `installedApps`, `runningApps`, `focusModes`, `integrations`, `repositories` or `permissions`. Answered by `queryResult`. |
| `recordMacro` | `command` (`start`, `stop` or `cancel`) | The Mac streams back `macroRecording` with the captured steps. |
| `registerPushToken` | Live Activity push token | Optional; used by APNs. |
| `updateIntegrations` | integration settings | Secrets never travel back; only `has…` flags do. |

### Mac → app (encrypted)

| Type | Payload |
|---|---|
| `appDidChange` | `ActiveContext`: bundle ID, app name, window title, URL, presence (active, idle, locked, asleep) |
| `liveDataUpdate` | `values: [ChannelValue]`, `full` |
| `buttonConfigUpdate` | the whole `Workspace` (pages, tiles, buttons, rules, scenes, preferences, revision) |
| `actionResult` | result of a `buttonTap` (`replyTo` set) |
| `toast` | `title`, `message?`, `style` (`info`, `success`, `warning`, `error` or `trade`), `symbol?` |
| `directive` | `navigate` (with `page`), `chime`, `ambient` or `wake` |
| `bye` | `reason` (`sleeping`, `quitting`, `replaced`, `revoked` or `error`), `message?` |

### Channels

`context`, `apps`, `system`, `media`, `audio`, `calendar`, `focus`, `bot`,
`botSeries`, `botEvents`, `whoop`, `weather`, `timers`, `daily`, `portfolio`,
`git`, `helper`

Each `ChannelValue` is `{ "ch": "<channel>", "v": { … } }`. Providers
push only changes; a value that merely moved the clock forward, such as a
media position, is not re-sent, and clients extrapolate it. Timers carry
`endsAt`, so every client counts down on its own without per-second
traffic.

## Pairing: commitment-based SAS

This is the ZRTP / Bluetooth-passkey family. The iPad commits to its key
before it sees the Mac's, so a man in the middle gets exactly one
one-in-a-million guess per attempt, instead of grinding keys until two
codes collide.

```
iPad                                         Mac
 │ pairBegin  commitment = SHA256("cc-commit-v1" ‖ pkI ‖ nI)
 │ ───────────────────────────────────────────▶
 │                                pairKey  pkR, nR, macID
 │ ◀───────────────────────────────────────────
 │ pairReveal  pkI, nI            (Mac verifies the commitment)
 │ ───────────────────────────────────────────▶
 │
 │   shared = X25519(sk, pk)
 │   T      = SHA256("cc-transcript-v1" ‖ pkI ‖ pkR ‖ nI ‖ nR ‖ deviceID ‖ 0 ‖ macID)
 │   code   = u32(SHA256("cc-sas-v1" ‖ T)[0..4]) mod 10⁶      ← shown on the Mac
 │   kc     = HKDF(shared, salt T, "cc-confirm-v1")
 │   LTK    = HKDF(shared, salt T, "cc-ltk-v1")               ← 256-bit long-term key
 │
 │ (user types the code; the iPad compares locally in constant time;
 │  up to 5 attempts)
 │ pairConfirm  HMAC(kc, "cc-confirm-I" ‖ T)
 │ ───────────────────────────────────────────▶
 │                       pairResult  ok, HMAC(kc, "cc-confirm-R" ‖ T)
 │ ◀───────────────────────────────────────────
```

Timeouts:

- The Mac shows the code and waits up to **180 s** for `pairConfirm`.
- The iPad waits up to **60 s** for `pairResult`, because the Mac stores the
  key first and macOS may be asking for Keychain access at that moment.
- Declining on the Mac sends `pairResult ok:false`.

The LTK is stored in the Mac's Keychain (one item per device) and in the
app's Keychain (shared with the widgets through the access group).

## Session authentication

Every connection, including the one right after pairing, runs:

```
hello      nI (32 random bytes), deviceID, protocolVersion
challenge  nR, macID, known
auth       HMAC(LTK, "cc-auth-I" ‖ deviceID ‖ 0 ‖ macID ‖ 0 ‖ nI ‖ nR)
authResult HMAC(LTK, "cc-auth-R" ‖ …same…)
```

Both proofs are verified, so the Mac knows the device and the device knows it
reached *its* Mac and not an impostor that copied the Bonjour name. A version
mismatch is refused in `authResult` with a readable reason.

## Encryption

Per-direction keys:

```
k_i2r = HKDF(LTK, salt nI ‖ nR, "cc-i2r-v1")
k_r2i = HKDF(LTK, salt nI ‖ nR, "cc-r2i-v1")
```

Each frame after the handshake:

```
counter (u64 big-endian) ‖ ChaCha20-Poly1305 ciphertext ‖ tag (16)
nonce = 0x00000000 ‖ counter        AAD = "I" or "R" (direction byte)
```

The counter must be exactly the previous counter + 1. A replayed, dropped
or reordered frame is rejected, and the session is torn down. The fresh
nonces mean every session has new keys.

## Liveness and reconnect

- The app pings every 2 s and shows the latency in the top bar. With no pong
  for 12 s, it treats the link as dead (Wi-Fi dropped without a FIN) and
  reconnects.
- Reconnecting uses exponential backoff from 3 s to 30 s (×1.5 each time).
  Each attempt tries the Bonjour result first, then the last known IP and
  port, then the service name. The backoff resets to 3 s the moment the
  paired Mac reappears in Bonjour or the app returns to the foreground.
- The Mac says `bye` when it sleeps (the app shows "Mac is asleep" and
  retries every 10 s), quits, replaces a session from the same device, or
  revokes a device.

## One-shot sessions (widgets, intents, controls)

Widgets, App Intents and iOS 18 Control Center controls can't hold a
connection open. `HubOneShot` does a full `hello`/`auth` exchange with the
stored LTK, sends one `buttonTap` or `requestSnapshot`, reads the reply, and
closes. It tries the last known IP and port first, then the Bonjour service
name, so it doesn't wait for a browse.

## Versioning

`ccProtocolVersion` (currently `1`) is bumped only for incompatible changes.
New optional fields and new message types don't need a bump, because both
sides ignore what they don't know.
