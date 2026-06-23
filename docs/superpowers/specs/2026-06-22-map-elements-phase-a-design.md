# Map System Overhaul — Phase A: Element & Landmark Vocabulary

**Status:** Design approved (brainstorm), pending spec review
**Date:** 2026-06-22
**Scope:** Phase A of a two-phase map overhaul. This spec covers the *vocabulary* — new map elements and landmarks plus their generator/planner/runtime integration. Phase B (the generative *curator*: scoring + best-of-N rejection sampling + variety budget) is a separate, later spec. The two "stretch" elements (Crumbling, Zip-line) are deferred to their own netcode-focused spec after Phase B.

---

## 1. Goals & non-goals

**Goals**
- Add *dimensionality* to movement and *constraints* that induce juking ("slipping"), purely through elements the generator places — **base run/jump/drop is unchanged**.
- Cover all four juke flavors the user wants: momentum/slip, route-fakes, tight-timing, vertical resets.
- Make games stop feeling samey (more landmarks, more per map) and stop having dead zones (new elements salt the connector layers).
- Keep the quality bar high — the element/landmark set was hand-curated and approved.

**Non-goals (this spec)**
- No changes to the shared movement controller (no wall-jump, double-jump, dive, etc.). Map-element-only was an explicit decision, so class balance, lag-comp, bot AI, and netcode stay untouched.
- No quality-scoring / rejection-sampling generator (that's Phase B).
- No Crumbling or Zip-line yet (they need new networked state; deferred).

**Hard constraint — determinism.** Every new element must produce identical behavior on every peer. The game is host-authoritative P2P with per-peer movement authority; anything that desyncs movement reproduces exactly the class of bug fixed in v2.0.1. Therefore every new element is driven only by **static geometry** or the **already-synced `world_clock`** — never by local contact state or local time.

---

## 2. Background (current system, as built)

- `MapGenerator.generate(seed)` builds a 1920×1080 map: full-width ground, then **4 landmark columns** drawn from a pool of **5** (`scaffold, pocket, ice_rink, spring_yard, mast` — shuffled, first 4 used), then random **connector platform layers** above `LANDMARK_TOP=640` up to y≈80.
- Platform dict: `{rect, type: "solid"|"ice"|"wall", thru: bool, ramp: ±1, move: {axis, amplitude, period, phase}}`. Objects: `{type: "spring"|"portal", pos, dest}`.
- `MapPlanner.plan(map, rng)` builds a real jump-arc traversal graph (`_edge_ok`, spring/portal edges), flood-fills from the ground, and **repairs/deletes to a fixed point** until everything is reachable AND 2-connected (`_repair_bottlenecks`, `MIN_BOTTLENECK_ORPHANS=3`). It also validates object rules (spring needs support+headroom+target; portal needs supported, clear arrival; movers must not sweep through geometry).
- Planning uses conservative physics (`SPEED=270` vs runtime 330, margins) so seeds stay stable and reachable.
- Movers today only patrol on **axis "x"** even though `_sweep_rect` already handles "y".

This architecture is the integration surface: **every new element must teach the planner a new edge or blocker rule, or it will be stripped or will make maps unfair.**

---

## 3. Element catalog (6 safe elements)

Each element below specifies: *behavior*, *data representation*, *runtime*, and *planner model*. The planner model is the make-or-break part — when in doubt the model is **conservative** (never claim reach the element doesn't reliably give; never let a sometimes-open element block an arc).

### 3.1 Conveyor (momentum)
- **Behavior:** a solid platform whose surface pushes you horizontally at a constant speed. Run with it = boost; against it = crawl; standing still = drift.
- **Data:** `platform["conveyor"] = {"dir": ±1, "speed": float}` on a `solid` platform (never on `wall`/`ice`/`ramp`).
- **Runtime:** while `is_on_floor()` and standing on a conveyor platform, add `dir*speed` to the horizontal target/velocity (applied in `_authority_physics`, deterministic from geometry). Remote puppets need no special handling — position is already replicated.
- **Planner model:** **no-op for reachability** (conservative). The belt can only *add* horizontal reach in its direction; ignoring it can never make a map claim a reach it lacks. Conveyor platforms are ordinary solid surfaces to the graph. (The belt pushing you off an edge is a *feature*, not a reachability break.)

### 3.2 Phase platform (route-fake)
- **Behavior:** blinks **solid ⟷ pass-through** on a steady cycle. You can only land on / be blocked by it during its "solid" window.
- **Data:** `platform["phase"] = {"period": float, "duty": 0..1, "offset": float}`. Solid when `fmod(world_clock + offset, period) < duty*period`, else thru.
- **Runtime:** collision toggled per-frame from `world_clock` (synced) — identical on all peers. When solid it behaves like a one-way `thru` top (you can stand); when off you pass through. Rendered with the off-phase drawn translucent/dashed.
- **Planner model:** as a **landing node, yes** (you can always wait for the solid window, so treat as a reachable surface like a normal platform); as a **blocker, no** (it is open part of every cycle, so it must not block any arc — treat like `thru` in `_blockers`). This keeps the graph honest: phase platforms add routes, never gate them.

### 3.3 Elevator — vertical mover (tight-timing)
- **Behavior:** a platform that patrols **up/down** instead of sideways.
- **Data:** existing `move` with `"axis": "y"`. No new field.
- **Runtime:** already supported by the mover system; just emit `axis:"y"` from the generator.
- **Planner model:** already supported — `_sweep_rect` handles y, `_edge_ok` takes off/lands on the **base rect** (honest: the platform is only at a sweep extreme momentarily), blockers use the full sweep. Verify `_mover_sweep_collides` and the lowest-first mover logic behave for vertical sweeps (they should; add tests).

### 3.4 Pinch gate (tight-timing)
- **Behavior:** two solid movers in **counter-phase** that meet in the middle and part — a closing gap you thread on the beat. No damage (the game has no health); a mistimed chaser is simply walled out for a beat.
- **Data:** a pair of `move` platforms sharing `move["pinch"] = group_id`, with phases offset by 0.5 and sweeps that overlap in the middle.
- **Runtime:** two ordinary time-driven movers; counter-phase guarantees they're never co-located.
- **Planner model:** **(a)** exempt intra-pair sweeps from `_mover_sweep_collides`/`_strip_colliding_movers` (they overlap *by design* but never collide in time). **(b)** For arc-blocking, treat pinch movers as **non-blocking** (`thru`-like), because the gap opens every cycle — you can always time through, so they must not be allowed to sever a route. They remain real solid bodies at runtime. *This is the most planner-intricate safe element; build it after the simpler ones and test the exemption explicitly.*

### 3.5 Angled launcher (vertical reset)
- **Behavior:** like a spring, but fires you **up and sideways** — a long directed hop that vaults a whole zone.
- **Data:** `object {type:"launcher", pos, vel: Vector2}` where `vel` has both components (e.g. up-and-right). (Generalizes today's straight-up spring.)
- **Runtime:** on contact, set the player's velocity to `vel` (an impulse, like the spring's `launch_velocity` path). Deterministic.
- **Planner model:** a new directed edge `_launcher_edge_ok(pos, vel, target, blockers)` — same shape as `_spring_edge_ok` but the initial horizontal velocity shifts the arc; the apex and landing x derive from `vel`. Validation mirrors springs: a launcher must have a reachable, unobstructed **target surface** in its arc and **head/arc clearance**, else it's scrubbed (extend `_scrub_objects`/`validate`).

### 3.6 Updraft column (vertical reset)
- **Behavior:** a vertical zone of upward push — float, hover, and steer as you rise; drift up a chute the chaser must commit to.
- **Data:** `object {type:"updraft", rect: Rect2, accel: float}`.
- **Runtime:** while the player's body is inside `rect`, apply upward acceleration (reduce effective gravity / clamp rise speed) so you can steer up. Deterministic from position.
- **Planner model:** a vertical assist edge `_updraft_edge_ok` from the surface at the column base to surfaces within the column whose height is within the updraft's reach — analogous to a soft spring with a tall, narrow reach envelope. Validate: column has top clearance and at least one landing (like spring target). Where an updraft is *inside* the Geyser landmark, the landmark also guarantees its side ledges are reachable by ordinary jumps, so the updraft is additive, not load-bearing.

---

## 4. New landmarks (6) — pool grows 5 → 11

Each new landmark packages one element + one juke flavor. All follow the **fairness lessons already in the codebase**: open structures, no walled dead-end cubbies (the scaffold/mast rule), every shelf droppable or thru so nothing corners you, and a `LANDMARK_HALF` budget so the packing math can't invert.

| Landmark | Element | Flavor | Sketch | `LANDMARK_HALF` (target) |
|---|---|---|---|---|
| **The Mill** | Conveyor | momentum | Stacked belts running opposite directions; lure the chaser onto a counter-belt | ~150 |
| **The Shaft** | Elevator (y-mover) | timing | Open vertical channel, elevators bobbing between side ledges | ~120 |
| **The Flicker** | Phase platform | route-fake | Stair of phase platforms blinking in a rising wave (a window rolls up) | ~120 |
| **The Battery** | Angled launcher | vertical reset | Pinball lane of angled launchers arcing you up ledge-by-ledge | ~150 |
| **The Geyser** | Updraft | vertical reset | Central updraft flanked by thin ledges; float over or peel onto a ledge | ~110 |
| **The Press** | Pinch gate | timing | Low corridor of closing gaps to thread, slow high road over the top | ~150 |

The 5 existing landmarks (`scaffold, pocket, ice_rink, spring_yard, mast`) remain. `LANDMARKS` becomes an 11-entry pool; `LANDMARK_HALF` gains the 6 new budgets. Each new landmark is a `_build_*` static function returning `{platforms, objects}`, mirroring the existing builders.

---

## 5. Variety dial — 4–6 landmarks per map

- Replace the fixed `columns = 4` with a per-map count **`N = rng.next_int(4, 6)`** drawn from the 11-pool shuffle.
- **Packing constraint:** the generator already reserves right-side room so bounds can't invert (`reserve` loop). Generalize it for variable `N`: the chosen landmarks' `2*LANDMARK_HALF` sum + `(N+1)*gap` must stay `< MAP_WIDTH (1920)`. If a drawn set is too wide for `N`, either (a) drop `N` by one, or (b) swap the widest pick for a narrower unused landmark. Wide landmarks (`ice_rink` half=190) naturally bias toward smaller `N`.
- **Optional stretch within Phase A:** pairing two *small* landmarks (e.g. Shaft + Geyser, both ≤120) into one column to raise content density without widening footprint. Spec it as a follow-on toggle; not required for the first cut.

---

## 6. Connector salting (kill dead zones)

The connector-layer loop already places platforms, ramps, bends, springs, and movers. Extend it so new elements appear *outside* landmarks too, at low per-roll chances tuned to avoid clutter:
- A connector platform may roll a **conveyor** belt or be a **phase** rung.
- A connector **spring** may instead be an **angled launcher**.
- A short **updraft** may bridge a tall connector gap.
- Vertical (**y-axis**) movers join the existing mover budget.

This is what makes the air above the landmarks feel different each game rather than "landmarks + plain platforms."

---

## 7. Data-model & API summary

**Platform dict — new optional keys:** `conveyor:{dir,speed}`, `phase:{period,duty,offset}`, `move:{...,axis:"y"}`, `move:{...,pinch:group_id}`.
**Object dict — new types:** `{type:"launcher",pos,vel}`, `{type:"updraft",rect,accel}`.
**Constants:** add conveyor speed, phase period/duty ranges, updraft accel, launcher power ranges (in `GameConfig` or `MapGenerator`), chosen to keep planning conservative and seeds stable.
**Determinism note:** adding elements shifts the seeded RNG stream, so existing seeds reroll to new maps. This is an accepted, deliberate reroll (same precedent as the `make_sfx` RNG note); the M1 same-seed determinism check still must pass *going forward*.

---

## 8. Planner changes summary

1. `_blockers`: treat **phase** and **pinch** platforms as non-blocking (like `thru`).
2. `_build_graph`: add **launcher** and **updraft** edges (new `_launcher_edge_ok`, `_updraft_edge_ok`).
3. `_mover_sweep_collides` / `_strip_colliding_movers`: exempt **intra-pinch-pair** overlap.
4. `validate` / `_scrub_objects`: add launcher (target+clearance) and updraft (top clearance+landing) rules; keep springs/portals as-is.
5. Conveyor and y-movers need **no** new reachability logic (conservative / already-supported).

---

## 9. Testing strategy (TDD)

- **Pure planner unit tests** (headless, no autoload — extend the `test_lagcomp`/`test_puppetstream` pattern): `_launcher_edge_ok` arc lands/rejects correctly; `_updraft_edge_ok` reach envelope; phase platform is a landing-node but not a blocker; pinch pair is sweep-exempt and non-blocking; y-mover reachability.
- **`test_mapgen.gd` extension:** across ≥50 seeds *and* the new landmarks, every generated map remains **reachable + 2-connected** and all object rules validate. Assert `N ∈ [4,6]` and packing never inverts.
- **Determinism:** same seed → identical map (existing M1 check) holds after the change.
- **Integration `--auto` modes:** add `shot-mill`, `shot-shaft`, `shot-flicker`, `shot-battery`, `shot-geyser`, `shot-press` screenshot modes (mirroring `shot-*`), plus at least one "ride" check that a bot can board an elevator and be carried, and one that a launcher arc deposits a player on its target.
- **No regression:** existing host/join and swap auto modes still pass.

---

## 10. Suggested implementation ordering (for the plan)

1. **Data model + planner scaffolding** + the two zero-risk elements (Conveyor, y-axis Elevator) end-to-end with tests.
2. **Phase platform** (land-yes/block-no) + **Angled launcher** (new edge + validation).
3. **Updraft** (new edge + validation) + **Pinch gate** (sweep exemption + non-blocking) — the two most planner-intricate.
4. **6 landmark builders** + pool expansion.
5. **Variety dial (4–6)** + packing generalization.
6. **Connector salting.**
7. Full `test_mapgen` sweep + screenshot modes + manual review.

Each step is independently testable and leaves the game shippable.

---

## 11. Deferred / future

- **Phase B — Generator curator:** quality scoring (variety, density/no-dead-zones, spawn fairness, juke-coverage) + best-of-N rejection sampling from sub-seeds + a variety budget so consecutive games differ. Separate spec.
- **Stretch elements — Crumbling platform & Zip-line:** approved for the long-term vision but need new networked state (synced contact-triggered collapse; replicated grab/ride state). Their own netcode-focused spec, sequenced after Phase B. Until then: Crumbling and Zip-line are NOT placed by the generator.

---

## 12. Risks & open questions

- **Pinch-gate planner model** is the riskiest piece — overlapping sweeps that are legal in time. If the exemption proves fiddly, fall back to placing pinch gates only on the wide ground surface (where they don't participate in the vertical reachability graph at all) for the first cut.
- **Launcher/updraft tuning** must stay within the planner's conservative envelope or maps will over-repair. Pick powers so the planned (270-speed) arc is comfortably within reach.
- **6-landmark packing** with wide landmarks may force `N` down often; confirm the distribution of `N` actually feels varied (a Phase-B metric, but worth a generation-time histogram during dev).
- **RNG reroll** changes every existing seed's map — acceptable, but any hard-coded preset/test seeds must be re-blessed.
