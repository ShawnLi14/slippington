# Map Phase A2 — Phase Platform & Pinch Gate Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Add two timing/route-fake map elements whose defining trait is the planner must treat them as **non-blocking** (they're open part of every cycle, so they add routes but must never gate one): the **Phase platform** (blinks solid↔pass-through on the `world_clock`) and the **Pinch gate** (a counter-phase mover pair that meets and parts).

**Architecture:** Both are deterministic off the synced `GameState.world_clock`. The Phase platform is a `PlatformBody` whose collision toggles between a one-way solid (landable) and nothing (pass-through), driven by `world_clock`. The Pinch gate is just two ordinary movers (already supported at runtime) tagged as a counter-phase pair. The real work is in `MapPlanner`: a phase platform and a pinch mover must be excluded from `_blockers` (so they never sever an arc), and the pinch pair's intentionally-overlapping sweeps must be exempt from the mover-collision strip.

**Tech Stack:** Godot 4.4.1, GDScript. Headless SceneTree unit tests on the autoload-free `MapGenerator`/`MapPlanner` layer.

**This is plan 2 (of 3-4) for Phase A.** A1 (Conveyor + vertical Elevator) is merged. A2b will add Angled launcher + Updraft (new `Area2D` classes + directed edges); A3 adds the 6 landmarks + 4–6 variety dial + connector salting.

## Global Constraints

Every task implicitly includes these (copied from the spec, same as A1):

- **Map-element-only.** Do NOT touch the shared movement controller's base verbs (run/jump/drop).
- **Determinism.** Elements are driven ONLY by static geometry or the synced `GameState.world_clock`. Per-element randomness comes ONLY from the seeded `rng`. Nothing is networked. Same seed → same map. (Adding elements reshuffles the RNG stream → existing seeds reroll; accepted.)
- **Planner stays conservative & correct.** Phase platforms and pinch movers are LANDABLE surfaces (`_surfaces` includes them) but NON-blocking (`_blockers` excludes them) — they may add routes, never gate one. The planner must keep guaranteeing every map is reachable + 2-connected. At RUNTIME these elements are real solid bodies (you must time through them); only the planner's reachability model treats them as always-passable.
- **Headless test limitation.** Node classes that reference autoloads (`PlatformBody`, `Player`) can't be instantiated under `--script` — verify those via clean import + `--auto` integration. Only the autoload-free `MapGenerator`/`MapPlanner` layer is unit-testable; that's where the planner-rule tests live.
- **Toolchain.** `GODOT="$LOCALAPPDATA/Programs/Godot/Godot_v4.4.1-stable_win64_console.exe"` (Git Bash). Reimport after adding/renaming a `class_name`/test: `"$GODOT" --headless --path godot --import`. Run a test: `"$GODOT" --headless --path godot --script res://tests/<file>.gd`. Tests for this plan extend `godot/tests/test_elements.gd`.

---

### Task 1: Phase platform — PlatformBody collision toggle + draw

**Files:**
- Modify: `godot/scripts/game/platform_body.gd`

**Interfaces:**
- Produces: `PlatformBody.phase: Dictionary` — `{"period": float, "duty": float (0..1), "offset": float}` or `{}`. When present, the body is a one-way solid during the "solid window" (`fmod(world_clock + offset, period) < duty*period`) and has no collision otherwise.

**Testing note:** `PlatformBody` references `GameState`, so it's not headless-instantiable — verify by clean import. Its behavior is exercised by the integration smoke in Task 5 once Task 4 generates phase platforms.

- [ ] **Step 1: Add the field + collision setup + per-frame toggle + draw**

In `godot/scripts/game/platform_body.gd`:

(a) Add the field after `var conveyor` :
```gdscript
var phase: Dictionary = {}  # {period, duty, offset} or empty — clocked solid↔thru
```

(b) In `create()`, after `p.conveyor = data.get("conveyor", {})`:
```gdscript
	p.phase = data.get("phase", {})
```

(c) In `_ready()`, replace the `sync_to_physics`/`set_physics_process` lines (currently:
`sync_to_physics = not move_data.is_empty()` / `set_physics_process(not move_data.is_empty())`) with versions that also run physics for phase platforms, and make a phase platform a one-way (thru-style) collider:
```gdscript
	sync_to_physics = not move_data.is_empty()
	set_physics_process(not move_data.is_empty() or not phase.is_empty())
```
Then, where collision layer is set (the `if thru:` / `else:` block that sets `collision_layer` and `one_way_collision`), make a phase platform behave like a one-way thru platform (landable from above, pass up through):
```gdscript
	if thru or not phase.is_empty():
		collision_layer = 2
		shape.one_way_collision = true
		shape.one_way_collision_margin = 8.0
	else:
		collision_layer = 1
```
(Replace the existing `if thru:` collision block with this.)

(d) In `_physics_process()`, handle move and phase independently. Replace the body of `_physics_process` (which currently only does mover motion) with:
```gdscript
func _physics_process(_delta: float) -> void:
	if not move_data.is_empty():
		var t: float = GameState.world_clock / move_data["period"] + move_data["phase"]
		var offset: float = move_data["amplitude"] * sin(TAU * t)
		if move_data["axis"] == "y":
			position = _base_pos + Vector2(0, offset)
		else:
			position = _base_pos + Vector2(offset, 0)
	if not phase.is_empty():
		var on := fmod(GameState.world_clock + phase["offset"], phase["period"]) < phase["duty"] * phase["period"]
		var want := 2 if on else 0
		if collision_layer != want:
			collision_layer = want
		if (on and modulate.a != 1.0) or (not on and modulate.a != 0.45):
			modulate.a = 1.0 if on else 0.45
			queue_redraw()
```

(e) In `_draw()`, add a dashed "phase" hint so the off-window reads as ghostly. Just before the `if type == "ice":` glint block (alongside the conveyor block), add:
```gdscript
	if not phase.is_empty():
		var px := -half.x + 6.0
		while px < half.x - 6.0:
			draw_line(Vector2(px, -half.y + 2), Vector2(minf(px + 8, half.x - 6.0), -half.y + 2), Color(1, 1, 1, 0.7), 2.0)
			px += 16.0
```

- [ ] **Step 2: Verify the project imports cleanly**

```bash
"$GODOT" --headless --path godot --import 2>&1 | grep -iE "SCRIPT ERROR|Parse Error|ERROR at" || echo "IMPORT CLEAN"
```
Expected: `IMPORT CLEAN`.

- [ ] **Step 3: Commit**

```bash
git add godot/scripts/game/platform_body.gd
git commit -m "Phase platform: clocked solid<->passthrough PlatformBody"
```

---

### Task 2: Planner — phase platforms are landable but non-blocking

**Files:**
- Modify: `godot/scripts/map/map_planner.gd` (`_blockers`)
- Modify: `godot/tests/test_elements.gd` (planner-rule tests, pure)

**Interfaces:**
- Consumes: a platform may carry a `phase` dict.
- Produces: `_blockers(map)` excludes phase platforms (they're open part of every cycle). `_surfaces(map)` already includes them (any non-wall), so they remain landable nodes.

- [ ] **Step 1: Write the failing test**

In `godot/tests/test_elements.gd`, register two checks in `_init` (after the existing ones):
```gdscript
	failures += _check("phase platform is not a blocker", _test_phase_nonblocking())
	failures += _check("phase platform is a landable surface", _test_phase_landable())
```
And add the methods:
```gdscript
func _test_phase_nonblocking() -> bool:
	# A phase platform must NOT appear among the planner's blocker rects.
	var ph := {"rect": Rect2(400, 500, 180, 16), "type": "solid", "phase": {"period": 2.0, "duty": 0.5, "offset": 0.0}}
	var m := {"width": 1920, "height": 1080, "platforms": [
		{"rect": Rect2(0, 1060, 1920, 20), "type": "solid"}, ph], "objects": []}
	for b in MapPlanner._blockers(m):
		if b.position.distance_to(Rect2(400, 500, 180, 16).grow(10.0).position) < 1.0:
			return false  # phase platform leaked into blockers
	return true

func _test_phase_landable() -> bool:
	# A phase platform is a non-wall surface, so it must be in _surfaces.
	var ph := {"rect": Rect2(400, 500, 180, 16), "type": "solid", "phase": {"period": 2.0, "duty": 0.5, "offset": 0.0}}
	var m := {"width": 1920, "height": 1080, "platforms": [ph], "objects": []}
	return MapPlanner._surfaces(m).has(ph)
```

- [ ] **Step 2: Run the test to verify the non-blocking case fails**

```bash
"$GODOT" --headless --path godot --import
"$GODOT" --headless --path godot --script res://tests/test_elements.gd
```
Expected: `FAIL phase platform is not a blocker` (the planner currently blocks it), `PASS phase platform is a landable surface`.

- [ ] **Step 3: Exclude phase platforms (and pinch movers — used in Task 4) from `_blockers`**

In `godot/scripts/map/map_planner.gd`, change `_blockers` (lines ~114-121). Replace its loop guard so thru, phase, and pinch movers don't block:
```gdscript
static func _blockers(map: Dictionary) -> Array[Rect2]:
	# Anything you can't pass through blocks movement arcs. "thru" variants,
	# phase platforms (open part of every cycle), and pinch-pair movers (the
	# gap opens every cycle) are timing elements you can always wait out, so
	# they must never sever a route — exclude them from blockers.
	var out: Array[Rect2] = []
	for p in map["platforms"]:
		if p.get("thru", false) or p.has("phase") or p.get("move", {}).has("pinch"):
			continue
		out.append(_sweep_rect(p).grow(BLOCK_INFLATE))
	return out
```

- [ ] **Step 4: Run the test to verify it passes**

```bash
"$GODOT" --headless --path godot --script res://tests/test_elements.gd
```
Expected: both phase checks PASS, `DONE: elements ok`.

- [ ] **Step 5: Commit**

```bash
git add godot/scripts/map/map_planner.gd godot/tests/test_elements.gd
git commit -m "Planner: phase platforms (and pinch movers) are non-blocking"
```

---

### Task 3: Generator salts phase platforms onto connectors

**Files:**
- Modify: `godot/scripts/map/map_generator.gd`
- Modify: `godot/tests/test_elements.gd`

**Interfaces:**
- Produces: maps whose connector layers may contain phase platforms (a flat solid that would have been `thru` becomes a phase platform instead).

- [ ] **Step 1: Write the failing test**

In `godot/tests/test_elements.gd`, register:
```gdscript
	failures += _check("some seed produces a phase platform", _test_gen_has_phase())
```
And the method:
```gdscript
func _test_gen_has_phase() -> bool:
	for s in 80:
		var m := MapGenerator.generate("a2-%d" % s)
		for p in m["platforms"]:
			if p.has("phase"):
				return true
	return false
```

- [ ] **Step 2: Run the test to verify it fails**

```bash
"$GODOT" --headless --path godot --script res://tests/test_elements.gd
```
Expected: `FAIL some seed produces a phase platform`.

- [ ] **Step 3: Add phase salting to the connector loop**

In `godot/scripts/map/map_generator.gd`, add a constant after `CONVEYOR_CHANCE`:
```gdscript
## Chance a thru connector becomes a clocked phase platform instead.
const PHASE_CHANCE := 0.12
```
In the connector loop, find where a flat platform is built as a thru variant (`platform = {"rect": rect, "type": p_type, "thru": thru}`). Right after that dict is created and before it is appended, convert a thru one to a phase platform sometimes (phase platforms behave like one-way thru, so only convert when `thru` is already true to preserve reachability semantics):
```gdscript
				if thru and rng.next() < PHASE_CHANCE:
					platform = {"rect": rect, "type": p_type,
						"phase": {"period": rng.next_float(1.6, 2.6), "duty": rng.next_float(0.45, 0.6), "offset": rng.next_float(0.0, 2.0)}}
```
(Place this immediately after the `else:` branch sets `platform = {"rect": rect, "type": p_type, "thru": thru}`, replacing the plain thru dict when the roll hits. A phase platform is NOT `thru` in the data — its non-blocking-ness comes from the `phase` key, handled in Task 2.)

- [ ] **Step 4: Run the test to verify it passes (and soundness holds)**

```bash
"$GODOT" --headless --path godot --script res://tests/test_elements.gd
```
Expected: all checks PASS including `generation stays sound with conveyors` (every seed still validates) and `some seed produces a phase platform`, `DONE: elements ok`.

- [ ] **Step 5: Commit**

```bash
git add godot/scripts/map/map_generator.gd godot/tests/test_elements.gd
git commit -m "Phase platform: salt clocked platforms into connector layers"
```

---

### Task 4: Pinch gate — planner sweep-exemption + generator placement

**Files:**
- Modify: `godot/scripts/map/map_planner.gd` (`_mover_sweep_collides`)
- Modify: `godot/scripts/map/map_generator.gd` (place a pinch pair)
- Modify: `godot/tests/test_elements.gd`

**Interfaces:**
- Produces: a pinch pair = two `move` platforms sharing `move["pinch"] = group_id`, counter-phase (`phase` offset by 0.5), with sweeps that overlap in the middle. The planner exempts intra-pair sweep overlap and (from Task 2) treats them as non-blocking.

- [ ] **Step 1: Write the failing test**

In `godot/tests/test_elements.gd`, register:
```gdscript
	failures += _check("pinch partners are sweep-exempt", _test_pinch_sweep_exempt())
	failures += _check("some seed produces a pinch pair", _test_gen_has_pinch())
```
And the methods:
```gdscript
func _test_pinch_sweep_exempt() -> bool:
	# Two counter-phase movers whose sweeps overlap in the middle must NOT be
	# flagged as colliding with each other (they're never co-located in time).
	var a := {"rect": Rect2(700, 980, 120, 16), "type": "solid",
		"move": {"axis": "x", "amplitude": 120.0, "period": 3.0, "phase": 0.0, "pinch": 1}}
	var b := {"rect": Rect2(940, 980, 120, 16), "type": "solid",
		"move": {"axis": "x", "amplitude": 120.0, "period": 3.0, "phase": 0.5, "pinch": 1}}
	var m := {"width": 1920, "height": 1080, "platforms": [
		{"rect": Rect2(0, 1060, 1920, 20), "type": "solid"}, a, b], "objects": []}
	return not MapPlanner._mover_sweep_collides(m, a) and not MapPlanner._mover_sweep_collides(m, b)

func _test_gen_has_pinch() -> bool:
	for s in 80:
		var m := MapGenerator.generate("a2-%d" % s)
		for p in m["platforms"]:
			if p.get("move", {}).has("pinch"):
				return true
	return false
```

- [ ] **Step 2: Run the test to verify it fails**

```bash
"$GODOT" --headless --path godot --script res://tests/test_elements.gd
```
Expected: `FAIL pinch partners are sweep-exempt` (the overlapping sweeps currently collide), `FAIL some seed produces a pinch pair`.

- [ ] **Step 3: Exempt intra-pair overlap in `_mover_sweep_collides`**

In `godot/scripts/map/map_planner.gd`, in `_mover_sweep_collides` (lines ~545-556), skip the mover's own pinch partner. Inside the `for p in map["platforms"]:` loop, after the existing `if p == mover: continue`, add:
```gdscript
		# A pinch partner's sweep overlaps by design; counter-phase guarantees
		# they're never co-located, so don't treat the partner as a collision.
		if mover.get("move", {}).has("pinch") and p.get("move", {}).get("pinch", -999) == mover["move"]["pinch"]:
			continue
```

- [ ] **Step 4: Run the sweep-exempt test to verify it passes (pinch-gen still fails)**

```bash
"$GODOT" --headless --path godot --script res://tests/test_elements.gd
```
Expected: `PASS pinch partners are sweep-exempt`, `FAIL some seed produces a pinch pair` (still no generation).

- [ ] **Step 5: Place a pinch pair on open ground in the generator**

In `godot/scripts/map/map_generator.gd`, the `ground_intervals` computation (used by the low mover) already finds open ground spans between landmarks. Reuse it: after the low-mover block, add an optional pinch pair in a wide ground interval. Add this after the low-mover placement block (`low_mover_placed = ...`):
```gdscript
	# A pinch gate: two counter-phase movers that meet and part — a closing gap
	# to thread on the beat. Placed in a wide open ground span (needs room for
	# both base platforms plus their overlapping sweep).
	if not ground_intervals.is_empty() and rng.next() < 0.6:
		var pv: Vector2 = ground_intervals[rng.next_int(0, ground_intervals.size() - 1)]
		if pv.y - pv.x >= 560.0:
			var mid := (pv.x + pv.y) / 2.0
			var pw := 120.0
			var amp := minf(150.0, (pv.y - pv.x) / 2.0 - pw)
			var py := rng.next_float(900.0, 960.0)
			var per := rng.next_float(2.6, 3.4)
			platforms.append({"rect": Rect2(mid - pw - 30.0, py, pw, PLATFORM_HEIGHT), "type": "solid",
				"move": {"axis": "x", "amplitude": amp, "period": per, "phase": 0.0, "pinch": int(mid)}})
			platforms.append({"rect": Rect2(mid + 30.0, py, pw, PLATFORM_HEIGHT), "type": "solid",
				"move": {"axis": "x", "amplitude": amp, "period": per, "phase": 0.5, "pinch": int(mid)}})
```
(`pinch` is the shared group id — `int(mid)` is a stable per-pair tag from the seeded layout. The planner's `_strip_colliding_movers` runs in `plan()`; with the Task 3 exemption it won't strip these, and Task 2 already makes them non-blocking so they can't sever the ground route.)

- [ ] **Step 6: Run the test to verify it passes (and soundness holds)**

```bash
"$GODOT" --headless --path godot --script res://tests/test_elements.gd
```
Expected: all checks PASS including `generation stays sound with conveyors` and both pinch checks, `DONE: elements ok`.

- [ ] **Step 7: Commit**

```bash
git add godot/scripts/map/map_planner.gd godot/scripts/map/map_generator.gd godot/tests/test_elements.gd
git commit -m "Pinch gate: counter-phase mover pair (sweep-exempt, non-blocking) + placement"
```

---

### Task 5: Phase-A2 regression gate

**Files:** none (verification only).

- [ ] **Step 1: Full headless suite**

```bash
"$GODOT" --headless --path godot --import
for t in test_elements test_lagcomp test_puppetstream test_mapgen; do
  echo "=== $t ==="
  "$GODOT" --headless --path godot --script res://tests/$t.gd 2>&1 | grep -iE "PASS|FAIL|DONE"
done
```
Expected: every suite ends `DONE` / all `PASS`. `test_mapgen` (50 seeds + presets sound) must still pass with phase platforms and pinch gates in play.

- [ ] **Step 2: Integration smoke**

```bash
for mode in "host:join:9994" "host-swap:join-swap:9995"; do
  IFS=: read h j port <<< "$mode"
  rm -f /tmp/h_$port.log /tmp/j_$port.log
  "$GODOT" --headless --path godot -- --auto=$h --port=$port --match-seconds=10 > /tmp/h_$port.log 2>&1 &
  sleep 1
  "$GODOT" --headless --path godot -- --auto=$j --port=$port > /tmp/j_$port.log 2>&1
  wait
  echo "=== $h/$j ==="; grep -iE "ALL CHECKS|FAIL" /tmp/h_$port.log /tmp/j_$port.log
done
```
Expected: `ALL CHECKS PASSED` for both pairs — phase platforms toggling collision and pinch movers patrolling cause no movement/tag regression.

- [ ] **Step 3: Confirm**

If green, Phase A2 is complete and shippable. Don't tag/release (after A2b/A3). If anything fails, invoke `superpowers:systematic-debugging`.

---

## Self-review notes

- **Spec coverage (A2 slice):** Phase platform — data (§3.2), runtime collision toggle off `world_clock`, generator placement, planner land-yes/block-no ✔. Pinch gate — counter-phase pair (§3.4), planner sweep-exemption + non-blocking, generator placement ✔.
- **Testing reality:** the planner rules (`_blockers` exclusion, `_mover_sweep_collides` exemption) ARE pure and headless-testable — they carry the unit coverage. The `PlatformBody` collision toggle is verified by clean import + integration.
- **Risk:** pinch placement requires a ≥560px open ground span, which not every map has — `_test_gen_has_pinch` scans 80 seeds to confirm it appears across the seed space, not every seed. If it never appears, widen the span budget or lower the threshold.
- **Out of scope (A2b/A3):** Angled launcher, Updraft (A2b); 6 landmarks (incl. the Flicker/Press that showcase these), 4–6 dial, broader salting (A3).
