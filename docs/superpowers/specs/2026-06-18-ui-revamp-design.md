# Slippington UI & Background Revamp — Design

**Date:** 2026-06-18
**Status:** Approved direction; pending spec review
**Scope:** Visual revamp of all menu/HUD screens and the procedural in-game backgrounds.

## Problem

Two complaints drive this work:

1. **Backgrounds look bad** — the in-game procedural backdrops are flat, simple shapes
   (triangle mountains, blocky islands, flat clouds) with no depth or atmosphere.
2. **Menus aren't sleek/professional** — the UI uses Godot's default font everywhere, half the
   controls (plain buttons, `LineEdit`, `OptionButton`) fall back to default gray styling, and
   panels/cards are flat with no depth or motion.

The teal/coral/sky identity is good and is **kept**. This is an elevation, not a reinvention.

## Locked decisions (validated via visual mockups)

- **Aesthetic direction: "Playful Party."** Bold, friendly, party-game energy (think Fall Guys /
  Stumble Guys), built on the existing palette.
- **Typography: bundle two OFL fonts** in `godot/assets/fonts/`:
  - **Display — Lilita One** (chunky rounded): title, buttons, class names, big HUD numbers.
  - **Body — Fredoka** (rounded sans, weights 400–700): labels, descriptions, HUD text, inputs.
  - Both are SIL Open Font License — free to bundle and ship; render identically on desktop and
    in the web export.
- **Coverage: full party styling everywhere**, including the in-game HUD (tuned for legibility —
  see Constraints).
- **Backgrounds: layered & atmospheric**, replacing flat shapes with depth (gradient skies, soft
  parallax silhouettes, volumetric clouds, haze, grain, vignette). Validated the floating-island
  art specifically: a **soft silhouette** with a wide grassy plateau, a single smooth tapering
  rock underside, and a simple single-tone tree (leaves opaque over the trunk). Background elements
  stay quiet so players/platforms remain the focus.

## Visual language

**Palette** (extends today's constants in `ui_theme.gd`):

| Token | Hex | Use |
|-------|-----|-----|
| `INK` | `#2b2350` | Outlines, text on light, card borders, hard shadows |
| `CREAM` | `#fff7ec` | Card / input fill |
| `TEAL` | `#4ecdc4` | Primary accent (kept) |
| `CORAL` | `#ff6b6b` | Primary action / "IT"/danger (kept) |
| `SUN` | `#ffd93d` | Secondary accent (JOIN, highlights) |
| `BG` | `#0f0f1a` | Deep background base (kept) |
| Class colors | existing 6 | Unchanged (slipper/swapper/anchor/echo/decoy/mason) |

**Signature components**

- **Party button** — Lilita One label, thick `INK` border, **offset hard drop-shadow** (a solid
  `INK` box below), press = translate down onto the shadow. Accent fill `CORAL` (primary) / `SUN`
  (secondary) / `CREAM` (neutral).
- **Class card** — `CREAM` fill, `INK` border + hard shadow; selected card lifts, tilts slightly,
  and gains a `SUN` fill + accent glow. Avatar drawn as today (rounded square + eyes).
- **Inputs (`LineEdit`)** — `CREAM` fill, `INK` border + small hard shadow, Fredoka, rounded.
- **Dropdowns (`OptionButton`)** — themed to match inputs (no default gray).
- **Pill / chip** — for "have a code?", code display, ready state.
- **Title** — Lilita One, thick `INK` outline + stacked drop-shadow, slight rotation, subtle idle
  bounce on the menu.

**Type scale** (approx, px): title 84 / screen-title 40 / card-name 20 / button 18–24 / body 15–16
/ small 12–13 / HUD timer 40. Final values tuned in implementation.

## Implementation approach

**Chosen: A — Global `Theme` + refactor the existing code-built UI + rebuild the procedural
background.** Keeps the project's established pattern (screens are `Control` subclasses built in
GDScript and swapped by `main.gd`), but introduces a single root-applied `Theme` so every control
inherits the look by default — eliminating the "Godot default leaks through" problem. Rejected: (B)
rebuilding screens as `.tscn` files (large rewrite, diverges from current architecture); (C)
font/color-only tweak (doesn't address backgrounds or overall polish — fails the brief).

## Architecture (units & responsibilities)

Each unit has one job and a clear interface; screens depend on `UiTheme`, never on raw Godot
defaults.

1. **`godot/assets/fonts/` (data)** — `lilita_one.ttf`, `fredoka.ttf` (+ `.import`). Sourced from
   Google Fonts (OFL). License text recorded in the folder.

2. **`UiTheme` (`scripts/ui/ui_theme.gd`) — the single styling source.** Expanded from today's
   helper bag into:
   - Palette constants (above) + font preloads.
   - `build_theme() -> Theme` — constructs a Godot `Theme` styling `Button`, `LineEdit`,
     `OptionButton`, `PopupMenu`, `PanelContainer`, `Label` (default font + sizes + StyleBoxes for
     normal/hover/pressed/focus). Applied once at the root so all screens inherit it.
   - Helpers (kept API, new look): `title()`, `label()`, `button(accent)`, `panel()`, plus new
     `class_card()`, `pill()`, and the existing `anchor_rect()` / `menu_backdrop()`.

3. **Motion helpers (`scripts/ui/ui_anim.gd`, new, small)** — reusable tweens: `entrance(node, i)`
   (staggered fade/slide-up), `hover_pop(button)`, `press(button)`, `title_idle(label)`. Keeps
   animation code out of each screen.

4. **Background system** — rebuild rather than replace the data-driven design:
   - **`background_themes.gd` (data)** — keep `frozen_lake()` / `sky_islands()`; add the new
     parameters the richer renderer needs (haze color, vignette strength, cloud softness, tree
     density, rim-light color, snow-cap gradient stops).
   - **`bg_art.gd` (new) — procedural art primitives.** Functions that draw *good-looking* shapes
     with within-shape gradients and soft edges instead of flat fills: `draw_island()` (plateau +
     smooth rock + tree, soft silhouette), `draw_mountain()` (ridge + snow-cap gradient + rim
     light), `draw_cloud()` (multi-blob volumetric), `draw_tree()`. Drawn via `Polygon2D`
     vertex-color gradients / `GradientTexture2D`, not `draw_rect`.
   - **`background.gd` (composition)** — assembles layers: graded gradient sky → sun glow / aurora
     → far+near parallax silhouettes (`bg_art`) → volumetric cloud layers → ambient particles →
     **haze band** → **grain overlay** → **vignette**. Parallax/wrap/particles as today; seeded by
     `GameState.map_seed` so all clients match.
   - **Menu backdrop** — `UiTheme.menu_backdrop()` uses `sky_islands` with the richer treatment
     plus the existing readability veil.

5. **Screens (consume `UiTheme`/`ui_anim`)** — `menu.gd`, `lobby.gd`, `end_screen.gd`, `hud.gd`
   restyled to the new components and given entrance/hover/press motion. Logic and networking
   unchanged.

## Per-screen changes

- **Main menu** — bouncing tilted title; class cards as party cards (lift/tilt/glow on select);
  `CREATE GAME` as the big primary party button; styled name field, code pill + `JOIN`; advanced
  panel and practice button restyled; staggered entrance.
- **Lobby** — code share as a bold pill with copy feedback; player list rows with swatch + ready
  pills; map/mode `OptionButton`s themed; `START`/`READY`/`LEAVE` as party buttons.
- **End screen** — bold win/lose title (CAUGHT! / YOU SURVIVED! / champion), results rows as
  themed cards with SAFE/CAUGHT pills; `PLAY AGAIN`/`LEAVE` party buttons; light celebratory motion
  on a win.
- **HUD (legibility-tuned)** — Lilita One timer (large, dark outline, turns `CORAL` under 10s);
  ability box keeps the keycap + cooldown-bar pattern but on the new theme; `GO!` / `TAG!` flashes
  restyled. Kept deliberately high-contrast and uncluttered so it never competes with gameplay.

## Constraints & non-negotiables

- **Renderer: `gl_compatibility`** (required for the web export). No `WorldEnvironment` glow/bloom.
  "Glow" is faked with additive radial-gradient sprites (as the current sun already does); vignette,
  grain, and haze are layered `ColorRect`/texture overlays (or a lightweight `hint_screen_texture`
  CanvasItem shader, which works in Compatibility). The aurora shader already runs in Compatibility.
- **Web export must keep working** — bundled fonts (not `SystemFont`); avoid features unsupported on
  HTML5; keep the backdrop full-rect so non-16:9 browser windows show no uncovered clear-color strip
  (preserve the current `_build_sky` full-rect approach).
- **Determinism** — backgrounds stay seeded by `map_seed`; cosmetic, so exact cross-client pixel
  match isn't required, but layout must be stable across reconnects.
- **Performance** — procedural only, no heavy per-pixel shaders; particle counts in today's range.
- **HUD legibility** — gameplay-critical text stays high-contrast and outlined.
- **No gameplay/network changes** — this is presentation only. Autoload signal connections in
  screens remain method connections (lambdas on autoload signals outlive freed screens and crash
  release builds — preserve the existing pattern).

## Out of scope (non-goals)

- New map layouts / gameplay / abilities / networking.
- New audio.
- Player/platform sprite art (players stay rounded-square + eyes; platforms unchanged) — unless a
  later pass is requested.
- Localization / font glyph coverage beyond Latin.

## Risks

- **Procedural art quality** — getting good-looking shapes in `_draw`/`Polygon2D` takes iteration
  (the island alone took several rounds). Mitigate by building `bg_art` primitives first and
  eyeballing them in isolation before wiring into scenes.
- **Web font loading** — verify TTFs import and render in the HTML5 build early.
- **Theme coverage gaps** — some control state (focus/disabled) easy to miss; audit every control
  type in the `Theme`.

## Verification

- Headless smoke test (per project tooling) that each screen instantiates without errors.
- Manual pass on desktop **and** the web export: menu, lobby (host + joiner), a full match, end
  screen; both `frozen_lake` and `sky_islands` backgrounds; window resized to a non-16:9 ratio.
- Confirm HUD timer/ability readable over both bright and dark backgrounds.

## Open questions

- Exact title bounce/tilt intensity and entrance timing — tune live.
- Tree variety (round vs. pine, 0–2 per island) — nice-to-have, can randomize per seed later.
