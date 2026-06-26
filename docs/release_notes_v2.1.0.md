# v2.1.0 — New Ways to Slip

The biggest map update yet. Every match now mixes **six new movement elements** and draws from **eleven landmark set-pieces** (up from five), so no two games feel the same — and there's a lot more room to juke.

## Six new ways to move

- **Conveyor belts** — surfaces that shove you sideways. Run with one for a boost; the juke is luring your chaser onto the belt dragging them the *wrong* way.
- **Elevators** — platforms that ride up and down. Commit to the lift and a mistimed chaser is left a beat behind.
- **Phase platforms** — blink solid and intangible on a steady beat. Time the solid window or drop right through.
- **Angled launchers** — pop you up with a directional lean; you steer the arc in the air. A fast vault out of a corner.
- **Updraft columns** — float up a chute and peel off onto a ledge while the chaser has to commit to the climb.
- **Pinch gates** — paired walls that close and part on the beat; thread the gap or get walled out for a moment.

## Eleven landmarks, four per map

Each map now builds from **4 of 11** landmarks (was 4 of 5), so you're missing a different seven every game. The six new set-pieces each showcase one element:

- **The Mill** — stacked counter-running conveyors
- **The Shaft** — a vertical channel with a bobbing elevator
- **The Flicker** — a phase stair whose solid window rolls upward like a wave
- **The Battery** — a pinball lane of angled launchers
- **The Geyser** — a central updraft flanked by peel-off ledges
- **The Press** — a ground-level pinch gate to thread

…alongside the returning Scaffold, Pocket, Ice Rink, Spring Yard, and Mast.

## Under the hood

- Every element is fully **deterministic** — driven by static geometry or the shared match clock — so all peers see exactly the same map and the same behavior. No new networked state, no desync risk.
- The map planner learned each new element's real reach and blocking rules: it still guarantees every generated map is **fully reachable and 2-connected**, with every special element an *additive* route (never the only way somewhere), so maps stay fair.
- Launchers are **vertical-dominant**: they give an initial directional pop, then hand you full air control — you choose where the arc lands.

No new download needed for online play beyond the updated build. Same seed → same map on every client.
