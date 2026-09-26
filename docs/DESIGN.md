# Design language

The surface is one lit scene, not a grid of boxes. Every page sits in an
atmosphere; everything on it is glass cut from the same material and lit by
the same light. Three references shaped it:

- an electric-cobalt sports dashboard, for the scene, the glass, and huge
  light type;
- a warm, tactile wellbeing app, for grain, sunrise warmth, and soft
  generous shapes;
- a robot-fleet console, for fill gauges, halos, and panels that read as one
  board.

## The scene

`SceneBackdrop` (`Apps/iOS/Design/Scene.swift`) is drawn once per mood and
never per frame. It is made of:

- a deep base;
- three soft lights: the **key** light top-left (glass edges catch it), a
  **fill** light on the right, and the page's **accent** from below;
- a vignette;
- fine monochrome film grain.

Each page has a mood (`SceneMood.page(_:)`):

| Page | Mood |
|---|---|
| Home, and anything unmapped | cobalt |
| Brief | sunrise (tangerine from below) |
| Bot | trading (teal) |
| Study | violet |
| Meeting | teal and green |
| Mac, Finder | steel blue |
| Markets | green |
| Terminal | green on cobalt |
| Notion | graphite |
| Safari, Xcode | their own blues |

A new mood crossfades in over about a second when the page changes.

## Glass

- **Tiles** (`CardBackground`, `.card()`): a frosted material, a cobalt body
  tint (the system material is grey), a sheen falling from the top-left, a
  1 pt refraction edge that is brightest where the key light hits, and a
  shadow tinted with the scene's ink.
- **The dock, capsules and circle buttons**: `GlassShape`, the same glass.
- **Wells**: insets on glass for rows and live capsules.

## Type

SF Pro throughout.

- **Hero numbers** (P&L, recovery, timers, temperature, net worth) are
  **light or ultralight** and large; their size does the work.
- **Titles** are 16 pt medium in sentence case, with a circular icon badge
  (`IconOrb`).
- **Labels** are 13 pt medium, secondary colour, sentence case. No tracked
  all-caps; only short tags such as BUY, SELL and LONG stay uppercase.
- **Scene titles** (pairing) use SF Pro Expanded Thin (`CCFont.wide`).
- Digits are always monospaced.

## Colour

One cool hue family. Saturated colour means something:

- green and red for profit and loss;
- the recovery zones;
- status;
- the light a page is lit with.

Neutral keys have near-white icons, so a coloured key is always telling you
something. Buttons pick ink or white text automatically for contrast
(`Color.legibleText`).

**Porcelain**, the light theme, uses the same tokens: pale periwinkle
lights and milky glass.

## Components

| Piece | Where |
|---|---|
| Glass keycaps with a coloured glow from below (wide keys: a wash from the icon side) | `KeyFace` |
| Lit pill buttons (filled) / tinted glass (quiet or hold-to-confirm) | `LargeActionButton`, `GlowCapsuleStyle` |
| Thin ring gauge with a glowing cap | `RingGauge` |
| Vertical fill gauge (the fleet console's battery) | `PillGauge` |
| Halo behind a gauge | `Halo` |
| Lit status sphere | `GlossyOrb` |
| Circular icon badge | `IconOrb` |
| Status pill, short tag | `Pill`, `Tag` |

**Motion:**

- Tiles rise into place one after another on a page change.
- Numbers roll.
- Presses compress to 0.96.
- Springs everywhere.

## Performance rule

**No SwiftUI `.shadow` or `.blur` on anything inside a tile.** A tile
re-renders whenever a number in it changes, and a SwiftUI shadow is re-blurred
on the CPU every time. The first version of this design idled at 20 % CPU
because of it.

- Drop shadows on big shapes: `ShadowPlate`, a Core Animation shadow with a
  fixed path, composited by the system.
- Glows: `.glow(_:)`, an elliptical gradient, or a wide faint stroke under a
  line (`Sparkline`, `RingGauge`, the P&L chart).
- The backdrop is a `drawingGroup` that only redraws when the mood changes.

With these rules the surface idles at about 1.5 % CPU, slightly less than the
flat design it replaced.

## Screenshots and test switches

| Launch argument | Effect |
|---|---|
| `-CCDemo -CCPage <id>` | Demo data, pinned to a page |
| `-CCDemoLocked` | The demo Mac is locked, so the iPad shows ambient mode |
| `-CCPairing` | Open the pairing flow (not in demo mode; add `-demoMode NO` if demo was left on) |
| `-theme light` / `-theme dark` | Theme for this launch |
