# Map Phase A3 — Landmark Vocabulary Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Add six new landmark builders (Mill, Shaft, Flicker, Battery, Geyser, Press) — each showcasing one Phase-A element — and grow the landmark pool from 5 to 11, so every map shows a different 4-of-11 and feels distinct.

**Architecture:** Each landmark is a pure `static func _<name>(...)` in `godot/scripts/map/map_generator.gd` returning `{platforms, objects}`, mirroring the five existing builders. The names join the `LANDMARKS` pool and `LANDMARK_HALF` budget; the generator still picks the first 4 of the shuffle (the 4→6 variety dial and connector salting are deferred to Phase A4). A new `force_landmark` debug hook pins one landmark into column 0 so each builder can be soundness-tested in isolation and screenshotted deterministically.

**Tech Stack:** Godot 4.4.1, GDScript. Headless unit tests via `SceneTree` scripts (`godot/tests/test_elements.gd`, `test_mapgen.gd`). Integration via `godot/tests/auto_driver.gd` `--auto=` modes.

## Global Constraints

- **Determinism (hard):** every landmark is built only from static geometry and the seeded `rng` passed in. No `world_clock`, no local time, no `Math.random`/`Date.now`. Same seed → same map on every peer. (`phase`/`move`/`conveyor` elements are themselves clock/geometry-driven and already implemented; landmarks only *place* them.)
- **Headless-test limitation:** under `--script` SceneTree mode the `GameState` autoload is NOT loaded, so any `class_name` script that references an autoload (`PlatformBody`, `Player`, the Area2D object scripts) fails to **compile** when instantiated. Therefore unit tests may ONLY touch autoload-free statics: `MapGenerator`, `MapPlanner`, `SeededRng`, `GameConfig`. Landmark builders are pure statics on `MapGenerator` → directly unit-testable. Runtime/visual behavior is verified via the `auto_driver` screenshot mode (Task 7), not unit tests.
- **GDScript 4.4.1 typing:** the engine cannot infer `bool`/numeric types from comparisons on `Variant` dict values. Annotate explicitly where needed (`var x: bool = ...`).
- **`LANDMARK_HALF` budget:** the value declared for each landmark MUST be ≥ the largest `|platform_x_extent − cx|` the builder ever produces, *including a mover's full horizontal sweep* (`base ± amplitude`). The packing math (`generate()` lines ~97-106) relies on this to keep landmarks clear of neighbors and the border. The worst-4-of-11 half-sum after this plan is `190+170+170+150 = 680` → `1360 + 5*100 gaps = 1860 < 1920` map width. Keep every new `HALF ≤ 150` so this never inverts.
- **Conservative planning:** `MapPlanner` plans at `SPEED=270` (runtime 330), `JUMP_V=450` → single-jump apex ≈ `450²/(2·800) − 6 ≈ 120 px`. Keep static vertical steps ≤ ~105 px so each ledge is reachable by an ordinary jump (every special element is then an *additive* fast route, never the only way up — preserves 2-connectivity without forcing the repair pass to mutate the landmark).
- **No double-conversion:** the spring→launcher/updraft conversion loop (`generate()` ~445-460) only rewrites objects whose `type == "spring"`. Landmarks that emit `launcher`/`updraft` objects directly are correctly skipped by it. Do not emit `spring` from Battery/Geyser.

---

## File Structure

- `godot/scripts/map/map_generator.gd` — **modify.** Add `static var force_landmark`; honor it in `generate()`; add 6 names to `LANDMARKS`; add 6 `LANDMARK_HALF` entries; add 6 `_build_landmark` match arms; add 6 `_<name>` builder funcs.
- `godot/tests/test_elements.gd` — **modify.** Add one direct builder test per landmark + a forced-soundness sweep over all 6.
- `godot/tests/auto_driver.gd` — **modify (Task 7).** Add a `--landmark=` arg and a `shot-landmark` mode that pins a landmark and screenshots it.

No new files. Every commit leaves the suite green and the game shippable (an unbuilt landmark name is never committed — each task adds the name and its builder together).

---

### Task 1: `force_landmark` debug hook + The Mill (conveyor)

**Files:**
- Modify: `godot/scripts/map/map_generator.gd` (add `force_landmark` static var ~line 46; honor it after the shuffle ~line 85; add `"mill"` to `LANDMARKS` line 42; add `"mill"` to `LANDMARK_HALF` ~line 57; add match arm ~line 481; add `_mill` after `_spring_yard` ~line 561)
- Test: `godot/tests/test_elements.gd`

**Interfaces:**
- Produces: `MapGenerator.force_landmark: String` (default `""`; when set to a name in `LANDMARKS`, that landmark occupies column 0 of every generated map). Consumed by Tasks 2-6 (forced-soundness tests) and Task 7 (screenshots).
- Produces: `MapGenerator._mill(cx: float, rng: SeededRng) -> Dictionary` returning `{"platforms": Array[Dictionary], "objects": Array[Dictionary]}`.

- [ ] **Step 1: Write the failing test (force hook + Mill builder)**

Add these two tests to `godot/tests/test_elements.gd` and register them in `_init()` (add the two `failures += _check(...)` lines next to the existing ones):

```gdscript
func _test_force_landmark() -> bool:
	# Forcing a known landmark must place its signature in column 0 (cx≈240).
	# "pocket" emits wall platforms; without the hook a fixed seed won't put
	# them in col 0.
	MapGenerator.force_landmark = "pocket"
	var m := MapGenerator.generate("a3-force")
	MapGenerator.force_landmark = ""
	for p in m["platforms"]:
		var r: Rect2 = p["rect"]
		if p["type"] == "wall" and r.position.x + r.size.x / 2.0 < 440.0:
			return true
	return false

func _test_mill_builds() -> bool:
	# The Mill is 4 conveyor belts; every platform stays within HALF (150) of cx
	# and carries a conveyor.
	var m := MapGenerator._mill(300.0, SeededRng.new("m"))
	var plats: Array = m["platforms"]
	if plats.size() != 4:
		return false
	for p in plats:
		if p.get("conveyor", {}).is_empty():
			return false
		var r: Rect2 = p["rect"]
		if r.position.x < 300.0 - 150.0 or r.end.x > 300.0 + 150.0:
			return false
	return true
```

Register in `_init()` (add after the existing `_check(...)` lines):

```gdscript
	failures += _check("force_landmark pins column 0", _test_force_landmark())
	failures += _check("the Mill builds 4 conveyor belts", _test_mill_builds())
```

- [ ] **Step 2: Add the pool entry + stub so the suite compiles and fails for the right reason**

In `map_generator.gd`, add `"mill"` to the `LANDMARKS` array (line 42) and a budget to `LANDMARK_HALF`:

```gdscript
const LANDMARKS := ["scaffold", "pocket", "ice_rink", "spring_yard", "mast", "mill"]
```

```gdscript
	"mast": 140.0,         # crow's nest 280 wide
	"mill": 150.0,         # 200 belt /2 + 35 offset + 8 jitter
}
```

Add the `force_landmark` static var next to `skip_plan` (~line 46):

```gdscript
## Debug/test hook: pin this landmark kind into column 0 (and exclude it from
## the random tail). "" = normal shuffle. Used by unit tests and screenshots.
static var force_landmark := ""
```

Add a **stub** builder after `_spring_yard` (so `_mill` exists and the test compiles, but returns empty → `_test_mill_builds` fails):

```gdscript
static func _mill(cx: float, rng: SeededRng) -> Dictionary:
	return {"platforms": [], "objects": []}
```

Add the match arm in `_build_landmark` (after the `"spring_yard"` arm):

```gdscript
		"mill":
			return _mill(cx, rng)
```

- [ ] **Step 3: Run the tests to verify they fail**

Run: `godot/Godot_v4.4.1-stable_win64_console.exe --headless --path godot --script res://tests/test_elements.gd`
Expected: `FAIL force_landmark pins column 0` (hook not wired yet) and `FAIL the Mill builds 4 conveyor belts` (stub returns empty), suite exits 1.

- [ ] **Step 4: Wire the `force_landmark` hook**

In `generate()`, immediately AFTER the Fisher-Yates shuffle of `order` (after line 85, before `var columns := 4`), insert:

```gdscript
	if force_landmark != "" and LANDMARKS.has(force_landmark):
		order.erase(force_landmark)
		order.push_front(force_landmark)
```

- [ ] **Step 5: Implement the Mill builder**

Replace the `_mill` stub body with the real builder:

```gdscript
## Stacked conveyor belts running alternate directions: the juke is the
## counter-belt — lure the chaser onto a belt dragging them the wrong way
## while you ride yours. Open stack with horizontal offsets (no walls), so
## nothing corners you; every level is a jump apart.
static func _mill(cx: float, rng: SeededRng) -> Dictionary:
	var plats: Array[Dictionary] = []
	var w := 200.0
	var levels := [960.0, 860.0, 760.0, 660.0]
	var side := 1.0 if rng.next() < 0.5 else -1.0
	for i in levels.size():
		var off := side * (35.0 if i % 2 == 0 else -35.0) + rng.next_float(-8.0, 8.0)
		plats.append({
			"rect": Rect2(cx + off - w / 2.0, levels[i], w, PLATFORM_HEIGHT),
			"type": "solid",
			"conveyor": {"dir": 1 if i % 2 == 0 else -1, "speed": rng.next_float(110.0, 150.0)},
		})
	return {"platforms": plats, "objects": []}
```

- [ ] **Step 6: Run the tests to verify they pass**

Run: `godot/Godot_v4.4.1-stable_win64_console.exe --headless --path godot --script res://tests/test_elements.gd`
Expected: `PASS force_landmark pins column 0`, `PASS the Mill builds 4 conveyor belts`, and `DONE: elements ok` (exit 0).

- [ ] **Step 7: Verify the forced Mill keeps maps sound**

Run: `godot/Godot_v4.4.1-stable_win64_console.exe --headless --path godot --script res://tests/test_mapgen.gd`
Expected: `DONE: 50 seeds + presets sound` (exit 0). The Mill now appears in ~1/3 of random maps; soundness must hold. If any seed reports an unreachable Mill level, widen the horizontal offset (keep within HALF 150) so each level overlaps the one below, then re-run — do NOT weaken the test.

- [ ] **Step 8: Commit**

```bash
git add godot/scripts/map/map_generator.gd godot/tests/test_elements.gd
git commit -m "Landmark: force_landmark hook + The Mill (stacked counter-conveyors)"
```

---

### Task 2: The Shaft (vertical-mover elevator)

**Files:**
- Modify: `godot/scripts/map/map_generator.gd` (`LANDMARKS`, `LANDMARK_HALF`, `_build_landmark` match, new `_shaft`)
- Test: `godot/tests/test_elements.gd`

**Interfaces:**
- Consumes: `MapGenerator.force_landmark` (Task 1).
- Produces: `MapGenerator._shaft(cx: float, rng: SeededRng) -> Dictionary`.

- [ ] **Step 1: Write the failing test**

Add to `test_elements.gd` and register in `_init()`:

```gdscript
func _test_shaft_builds() -> bool:
	# The Shaft has static side ledges plus at least one vertical (axis "y")
	# elevator; everything within HALF (120) of cx.
	var m := MapGenerator._shaft(500.0, SeededRng.new("s"))
	var has_ymover := false
	for p in m["platforms"]:
		var r: Rect2 = p["rect"]
		if r.position.x < 500.0 - 120.0 or r.end.x > 500.0 + 120.0:
			return false
		if p.get("move", {}).get("axis", "x") == "y":
			has_ymover = true
	return has_ymover
```

```gdscript
	failures += _check("the Shaft builds a vertical elevator", _test_shaft_builds())
```

- [ ] **Step 2: Add the pool entry + stub**

```gdscript
const LANDMARKS := ["scaffold", "pocket", "ice_rink", "spring_yard", "mast", "mill", "shaft"]
```
```gdscript
	"mill": 150.0,         # 200 belt /2 + 35 offset + 8 jitter
	"shaft": 120.0,        # side ledges reach cx±118
}
```
Add match arm after `"mill"`:
```gdscript
		"shaft":
			return _shaft(cx, rng)
```
Add stub after `_mill`:
```gdscript
static func _shaft(cx: float, rng: SeededRng) -> Dictionary:
	return {"platforms": [], "objects": []}
```

- [ ] **Step 3: Run to verify it fails**

Run: `godot/Godot_v4.4.1-stable_win64_console.exe --headless --path godot --script res://tests/test_elements.gd`
Expected: `FAIL the Shaft builds a vertical elevator` (stub has no y-mover), exit 1.

- [ ] **Step 4: Implement the Shaft**

Replace the stub:

```gdscript
## A narrow vertical channel: static side ledges staggered L/R (each a jump
## apart, so the climb never depends on the lift) plus a y-mover elevator
## bobbing the center as the express route. The juke is committing to the
## lift — a mistimed chaser eats a beat.
static func _shaft(cx: float, rng: SeededRng) -> Dictionary:
	var plats: Array[Dictionary] = []
	var lw := 70.0
	# Staggered side ledges: left, right, left, right — 85-90 px steps.
	plats.append({"rect": Rect2(cx - 118.0, 945.0, lw, PLATFORM_HEIGHT), "type": "solid"})
	plats.append({"rect": Rect2(cx + 48.0, 855.0, lw, PLATFORM_HEIGHT), "type": "solid"})
	plats.append({"rect": Rect2(cx - 118.0, 760.0, lw, PLATFORM_HEIGHT), "type": "solid"})
	plats.append({"rect": Rect2(cx + 48.0, 668.0, lw, PLATFORM_HEIGHT), "type": "solid"})
	# Center elevator: y-axis mover, amplitude clamped so the sweep stays in the
	# channel; 12 px clear of the ledges (ledges start at cx±48, ew/2 = 36).
	var ew := 72.0
	plats.append({
		"rect": Rect2(cx - ew / 2.0, 815.0, ew, PLATFORM_HEIGHT),
		"type": "solid",
		"move": {"axis": "y", "amplitude": 110.0, "period": rng.next_float(2.8, 3.6), "phase": rng.next_float(0.0, 1.0)},
	})
	return {"platforms": plats, "objects": []}
```

- [ ] **Step 5: Run to verify it passes**

Run: `godot/Godot_v4.4.1-stable_win64_console.exe --headless --path godot --script res://tests/test_elements.gd`
Expected: `PASS the Shaft builds a vertical elevator`, `DONE: elements ok` (exit 0).

- [ ] **Step 6: Verify forced soundness**

Run: `godot/Godot_v4.4.1-stable_win64_console.exe --headless --path godot --script res://tests/test_mapgen.gd`
Expected: `DONE: 50 seeds + presets sound`. If the elevator sweep is flagged as colliding with a side ledge, lower `amplitude` or narrow `ew` (keep 12 px clearance to the cx±48 ledges) and re-run.

- [ ] **Step 7: Commit**

```bash
git add godot/scripts/map/map_generator.gd godot/tests/test_elements.gd
git commit -m "Landmark: The Shaft (vertical-elevator channel)"
```

---

### Task 3: The Flicker (phase platform)

**Files:**
- Modify: `godot/scripts/map/map_generator.gd`
- Test: `godot/tests/test_elements.gd`

**Interfaces:**
- Consumes: `MapGenerator.force_landmark`.
- Produces: `MapGenerator._flicker(cx: float, rng: SeededRng) -> Dictionary`.

- [ ] **Step 1: Write the failing test**

```gdscript
func _test_flicker_builds() -> bool:
	# A rising stair of phase rungs with staggered offsets (a rolling window),
	# plus solid anchors. Needs ≥3 phase platforms whose offsets differ.
	var m := MapGenerator._flicker(500.0, SeededRng.new("f"))
	var offsets := {}
	for p in m["platforms"]:
		var r: Rect2 = p["rect"]
		if r.position.x < 500.0 - 120.0 or r.end.x > 500.0 + 120.0:
			return false
		if p.has("phase"):
			offsets[p["phase"]["offset"]] = true
	return offsets.size() >= 3
```
```gdscript
	failures += _check("the Flicker builds a staggered phase stair", _test_flicker_builds())
```

- [ ] **Step 2: Add the pool entry + stub**

```gdscript
const LANDMARKS := ["scaffold", "pocket", "ice_rink", "spring_yard", "mast", "mill", "shaft", "flicker"]
```
```gdscript
	"shaft": 120.0,        # side ledges reach cx±118
	"flicker": 120.0,      # rungs reach cx±110
}
```
Match arm after `"shaft"`:
```gdscript
		"flicker":
			return _flicker(cx, rng)
```
Stub after `_shaft`:
```gdscript
static func _flicker(cx: float, rng: SeededRng) -> Dictionary:
	return {"platforms": [], "objects": []}
```

- [ ] **Step 3: Run to verify it fails**

Run: `godot/Godot_v4.4.1-stable_win64_console.exe --headless --path godot --script res://tests/test_elements.gd`
Expected: `FAIL the Flicker builds a staggered phase stair`, exit 1.

- [ ] **Step 4: Implement the Flicker**

```gdscript
## A rising stair of phase platforms whose solid windows are offset by a
## quarter-cycle each, so the foothold rolls upward like a wave. Solid anchors
## at base and top guarantee a foothold. The juke: ride the window up; mistime
## and the next rung is intangible — you fall through and reset. To the planner
## phase rungs are landing-yes (you can wait for solid) and block-no.
static func _flicker(cx: float, rng: SeededRng) -> Dictionary:
	var plats: Array[Dictionary] = []
	# Solid base anchor.
	plats.append({"rect": Rect2(cx - 60.0, 960.0, 120.0, PLATFORM_HEIGHT), "type": "solid"})
	var period := rng.next_float(1.8, 2.4)
	var rw := 100.0
	var steps := [Vector2(cx - 55.0, 860.0), Vector2(cx + 15.0, 770.0), Vector2(cx - 55.0, 700.0)]
	for i in steps.size():
		var s: Vector2 = steps[i]
		plats.append({
			"rect": Rect2(s.x - rw / 2.0, s.y, rw, PLATFORM_HEIGHT),
			"type": "solid",
			"phase": {"period": period, "duty": 0.55, "offset": float(i) * period * 0.25},
		})
	# Solid top anchor lands the climb (a connector seed at y ≤ 760).
	plats.append({"rect": Rect2(cx - 50.0, 640.0, 100.0, PLATFORM_HEIGHT), "type": "solid"})
	return {"platforms": plats, "objects": []}
```

- [ ] **Step 5: Run to verify it passes**

Run: `godot/Godot_v4.4.1-stable_win64_console.exe --headless --path godot --script res://tests/test_elements.gd`
Expected: `PASS the Flicker builds a staggered phase stair`, `DONE: elements ok`.

- [ ] **Step 6: Verify forced soundness**

Run: `godot/Godot_v4.4.1-stable_win64_console.exe --headless --path godot --script res://tests/test_mapgen.gd`
Expected: `DONE: 50 seeds + presets sound`.

- [ ] **Step 7: Commit**

```bash
git add godot/scripts/map/map_generator.gd godot/tests/test_elements.gd
git commit -m "Landmark: The Flicker (rolling-window phase stair)"
```

---

### Task 4: The Battery (angled launcher)

**Files:**
- Modify: `godot/scripts/map/map_generator.gd`
- Test: `godot/tests/test_elements.gd`

**Interfaces:**
- Consumes: `MapGenerator.force_landmark`.
- Produces: `MapGenerator._battery(cx: float, rng: SeededRng) -> Dictionary` — emits `launcher` objects (`{type:"launcher", pos:Vector2, vel:Vector2}`).

- [ ] **Step 1: Write the failing test**

```gdscript
func _test_battery_builds() -> bool:
	# Rising ledges, each lower one carrying a launcher whose arc reaches the
	# next ledge (so the planner keeps it). Verify ≥2 launchers AND each has a
	# valid in-arc target among the ledges.
	var m := MapGenerator._battery(500.0, SeededRng.new("b"))
	var ledges: Array = []
	var launchers: Array = []
	for p in m["platforms"]:
		var r: Rect2 = p["rect"]
		if r.position.x < 500.0 - 140.0 or r.end.x > 500.0 + 140.0:
			return false
		ledges.append(p)
	for o in m["objects"]:
		if o["type"] == "launcher":
			launchers.append(o)
	if launchers.size() < 2:
		return false
	var blockers: Array[Rect2] = []
	for o in launchers:
		var support = MapPlanner._support_under({"platforms": ledges}, o["pos"])
		if support == null:
			return false
		var hit := false
		for b in ledges:
			if MapPlanner._launcher_edge_ok(o["pos"], o["vel"], support, b, blockers):
				hit = true
				break
		if not hit:
			return false
	return true
```
```gdscript
	failures += _check("the Battery launchers reach their targets", _test_battery_builds())
```

- [ ] **Step 2: Add the pool entry + stub**

```gdscript
const LANDMARKS := ["scaffold", "pocket", "ice_rink", "spring_yard", "mast", "mill", "shaft", "flicker", "battery"]
```
```gdscript
	"flicker": 120.0,      # rungs reach cx±110
	"battery": 130.0,      # ledges reach cx±105
}
```
Match arm after `"flicker"`:
```gdscript
		"battery":
			return _battery(cx, rng)
```
Stub after `_flicker`:
```gdscript
static func _battery(cx: float, rng: SeededRng) -> Dictionary:
	return {"platforms": [], "objects": []}
```

- [ ] **Step 3: Run to verify it fails**

Run: `godot/Godot_v4.4.1-stable_win64_console.exe --headless --path godot --script res://tests/test_elements.gd`
Expected: `FAIL the Battery launchers reach their targets` (stub has no launchers), exit 1.

- [ ] **Step 4: Implement the Battery**

```gdscript
## A pinball lane: ledges in a rising zigzag, each lower ledge carrying an
## angled launcher that arcs you up-and-over to the next. The launchers are a
## fast vault up the whole zone; the ledges are also jump-reachable (≤110 px
## steps) so a slower climb exists too. Each launcher's target is validated by
## the planner (_launcher_edge_ok) or _scrub_objects drops it.
static func _battery(cx: float, rng: SeededRng) -> Dictionary:
	var lw := 90.0
	var ledges := [Vector2(cx - 60.0, 960.0), Vector2(cx + 60.0, 850.0), Vector2(cx - 60.0, 740.0)]
	var plats: Array[Dictionary] = []
	for L in ledges:
		plats.append({"rect": Rect2(L.x - lw / 2.0, L.y, lw, PLATFORM_HEIGHT), "type": "solid"})
	var objects: Array[Dictionary] = []
	for i in range(ledges.size() - 1):
		var here: Vector2 = ledges[i]
		var nxt: Vector2 = ledges[i + 1]
		var dir := 1.0 if nxt.x > here.x else -1.0
		objects.append({"type": "launcher", "pos": Vector2(here.x, here.y - 7.0),
			"vel": Vector2(dir * 150.0, -700.0)})
	return {"platforms": plats, "objects": objects}
```

- [ ] **Step 5: Run to verify it passes**

Run: `godot/Godot_v4.4.1-stable_win64_console.exe --headless --path godot --script res://tests/test_elements.gd`
Expected: `PASS the Battery launchers reach their targets`, `DONE: elements ok`.

- [ ] **Step 6: Verify forced soundness (launchers survive scrubbing)**

Run: `godot/Godot_v4.4.1-stable_win64_console.exe --headless --path godot --script res://tests/test_mapgen.gd`
Expected: `DONE: 50 seeds + presets sound`. If a launcher is scrubbed (its target unreachable for some seed), nudge `vel.y` toward `-720` (raises the apex) so the arc clears, keeping ledges within HALF 130; re-run.

- [ ] **Step 7: Commit**

```bash
git add godot/scripts/map/map_generator.gd godot/tests/test_elements.gd
git commit -m "Landmark: The Battery (angled-launcher pinball lane)"
```

---

### Task 5: The Geyser (updraft column)

**Files:**
- Modify: `godot/scripts/map/map_generator.gd`
- Test: `godot/tests/test_elements.gd`

**Interfaces:**
- Consumes: `MapGenerator.force_landmark`.
- Produces: `MapGenerator._geyser(cx: float, ground_y: float) -> Dictionary` — emits an `updraft` object (`{type:"updraft", rect:Rect2, accel:float}`).

- [ ] **Step 1: Write the failing test**

```gdscript
func _test_geyser_builds() -> bool:
	# A central updraft column with side ledges whose inner edge sits at the
	# column edge (so you can peel onto them). Verify the updraft has at least
	# one valid in-column landing.
	var m := MapGenerator._geyser(500.0, 1060.0)
	var plats: Array = m["platforms"]
	var zone := Rect2()
	var found_updraft := false
	for o in m["objects"]:
		if o["type"] == "updraft":
			zone = o["rect"]
			found_updraft = true
	if not found_updraft:
		return false
	for p in plats:
		var r: Rect2 = p["rect"]
		if r.position.x < 500.0 - 120.0 or r.end.x > 500.0 + 120.0:
			return false
	var blockers: Array[Rect2] = []
	var support := plats[0]  # the base footing
	for b in plats:
		if MapPlanner._updraft_edge_ok(zone, support, b, blockers):
			return true
	return false
```
```gdscript
	failures += _check("the Geyser updraft reaches a side ledge", _test_geyser_builds())
```

- [ ] **Step 2: Add the pool entry + stub**

```gdscript
const LANDMARKS := ["scaffold", "pocket", "ice_rink", "spring_yard", "mast", "mill", "shaft", "flicker", "battery", "geyser"]
```
```gdscript
	"battery": 130.0,      # ledges reach cx±105
	"geyser": 110.0,       # side ledges reach cx±108
}
```
Match arm after `"battery"`:
```gdscript
		"geyser":
			return _geyser(cx, ground_y)
```
Stub after `_battery`:
```gdscript
static func _geyser(cx: float, ground_y: float) -> Dictionary:
	return {"platforms": [], "objects": []}
```

- [ ] **Step 3: Run to verify it fails**

Run: `godot/Godot_v4.4.1-stable_win64_console.exe --headless --path godot --script res://tests/test_elements.gd`
Expected: `FAIL the Geyser updraft reaches a side ledge`, exit 1.

- [ ] **Step 4: Implement the Geyser**

```gdscript
## A central updraft column flanked by thin side ledges whose inner edge meets
## the column edge — float the chute and peel onto a ledge, or ride over the
## top. The chaser must commit to the column to follow; you peel off early. The
## base footing sits at the column bottom; side ledges are jump-reachable too
## (updraft additive). _updraft_edge_ok validates the in-column landing.
static func _geyser(cx: float, ground_y: float) -> Dictionary:
	var plats: Array[Dictionary] = []
	var base_y := 965.0
	# Footing the column rises from (also the support the planner anchors to).
	plats.append({"rect": Rect2(cx - 70.0, base_y, 140.0, PLATFORM_HEIGHT), "type": "solid"})
	var col_w := 96.0          # column spans cx-48 .. cx+48
	var lw := 60.0
	# Side ledges: inner edge AT the column edge (cx±48) so they overlap the
	# lift band and you can step off onto them.
	plats.append({"rect": Rect2(cx + 48.0, 850.0, lw, PLATFORM_HEIGHT), "type": "solid"})
	plats.append({"rect": Rect2(cx - 108.0, 740.0, lw, PLATFORM_HEIGHT), "type": "solid"})
	plats.append({"rect": Rect2(cx + 48.0, 660.0, lw, PLATFORM_HEIGHT), "type": "solid"})
	var col_top := 645.0
	var objects: Array[Dictionary] = [
		{"type": "updraft", "rect": Rect2(cx - col_w / 2.0, col_top, col_w, base_y - col_top), "accel": 1400.0},
	]
	return {"platforms": plats, "objects": objects}
```

- [ ] **Step 5: Run to verify it passes**

Run: `godot/Godot_v4.4.1-stable_win64_console.exe --headless --path godot --script res://tests/test_elements.gd`
Expected: `PASS the Geyser updraft reaches a side ledge`, `DONE: elements ok`.

- [ ] **Step 6: Verify forced soundness**

Run: `godot/Godot_v4.4.1-stable_win64_console.exe --headless --path godot --script res://tests/test_mapgen.gd`
Expected: `DONE: 50 seeds + presets sound`. If the updraft is scrubbed, confirm at least one side ledge's inner edge is exactly `cx±48` (overlapping the column x-span) and its `y` is between `col_top` and `base_y − PLAYER_SIZE`.

- [ ] **Step 7: Commit**

```bash
git add godot/scripts/map/map_generator.gd godot/tests/test_elements.gd
git commit -m "Landmark: The Geyser (central updraft chute)"
```

---

### Task 6: The Press (pinch gate)

**Files:**
- Modify: `godot/scripts/map/map_generator.gd`
- Test: `godot/tests/test_elements.gd`

**Interfaces:**
- Consumes: `MapGenerator.force_landmark`.
- Produces: `MapGenerator._press(cx: float, ground_y: float, rng: SeededRng) -> Dictionary`.

- [ ] **Step 1: Write the failing test**

```gdscript
func _test_press_builds() -> bool:
	# A pinch pair (two movers sharing a "pinch" group, counter-phase) over open
	# ground. Verify the pair exists, is counter-phase, and the movers' full
	# sweep stays within HALF (150) of cx.
	var m := MapGenerator._press(500.0, 1060.0, SeededRng.new("p"))
	var movers: Array = []
	for p in m["platforms"]:
		if p.get("move", {}).has("pinch"):
			movers.append(p)
		var sweep := MapPlanner._sweep_rect(p)
		if sweep.position.x < 500.0 - 150.0 or sweep.end.x > 500.0 + 150.0:
			return false
	if movers.size() != 2:
		return false
	return movers[0]["move"]["pinch"] == movers[1]["move"]["pinch"] \
		and absf(movers[0]["move"]["phase"] - movers[1]["move"]["phase"]) > 0.4
```
```gdscript
	failures += _check("the Press builds a counter-phase pinch pair", _test_press_builds())
```

- [ ] **Step 2: Add the pool entry + stub**

```gdscript
const LANDMARKS := ["scaffold", "pocket", "ice_rink", "spring_yard", "mast", "mill", "shaft", "flicker", "battery", "geyser", "press"]
```
```gdscript
	"geyser": 110.0,       # side ledges reach cx±108
	"press": 150.0,        # mover sweep reaches cx±140
}
```
Match arm after `"geyser"`:
```gdscript
		"press":
			return _press(cx, ground_y, rng)
```
Stub after `_geyser`:
```gdscript
static func _press(cx: float, ground_y: float, rng: SeededRng) -> Dictionary:
	return {"platforms": [], "objects": []}
```

- [ ] **Step 3: Run to verify it fails**

Run: `godot/Godot_v4.4.1-stable_win64_console.exe --headless --path godot --script res://tests/test_elements.gd`
Expected: `FAIL the Press builds a counter-phase pinch pair`, exit 1.

- [ ] **Step 4: Implement the Press**

```gdscript
## A pinch gate over open ground: two counter-phase movers that meet and part,
## a closing gap to thread on the beat. The ground beneath them is always
## reachable, and pinch movers are non-blocking to the planner (the gap opens
## every cycle), so they gate nothing — pure timing flavor for a chase. Base
## inner edges at cx±30, amplitude 30 → the gap oscillates 0..120 px and the
## full sweep reaches cx±140 (within HALF 150). A low footing gives a spawn.
static func _press(cx: float, ground_y: float, rng: SeededRng) -> Dictionary:
	var plats: Array[Dictionary] = [
		{"rect": Rect2(cx - 90.0, 980.0, 180.0, PLATFORM_HEIGHT), "type": "solid"},
	]
	var pw := 80.0
	var amp := 30.0
	var per := rng.next_float(2.6, 3.4)
	plats.append({"rect": Rect2(cx - 30.0 - pw, 880.0, pw, PLATFORM_HEIGHT), "type": "solid",
		"move": {"axis": "x", "amplitude": amp, "period": per, "phase": 0.0, "pinch": int(cx)}})
	plats.append({"rect": Rect2(cx + 30.0, 880.0, pw, PLATFORM_HEIGHT), "type": "solid",
		"move": {"axis": "x", "amplitude": amp, "period": per, "phase": 0.5, "pinch": int(cx)}})
	return {"platforms": plats, "objects": []}
```

- [ ] **Step 5: Run to verify it passes**

Run: `godot/Godot_v4.4.1-stable_win64_console.exe --headless --path godot --script res://tests/test_elements.gd`
Expected: `PASS the Press builds a counter-phase pinch pair`, `DONE: elements ok`.

- [ ] **Step 6: Verify forced soundness**

Run: `godot/Godot_v4.4.1-stable_win64_console.exe --headless --path godot --script res://tests/test_mapgen.gd`
Expected: `DONE: 50 seeds + presets sound`. The pinch pair must be sweep-exempt from each other (the A2 `pinch` exemption) and non-blocking — if `_strip_colliding_movers` removes one, confirm both carry the same `"pinch"` group id.

- [ ] **Step 7: Commit**

```bash
git add godot/scripts/map/map_generator.gd godot/tests/test_elements.gd
git commit -m "Landmark: The Press (ground-level pinch gate)"
```

---

### Task 7: Regression gate + per-landmark screenshot mode

**Files:**
- Modify: `godot/tests/test_elements.gd` (forced-soundness sweep over all 6)
- Modify: `godot/tests/auto_driver.gd` (`--landmark=` arg + `shot-landmark` mode)
- Test: full unit suite + integration smoke

**Interfaces:**
- Consumes: `MapGenerator.force_landmark`; all 6 builders.

- [ ] **Step 1: Add the forced-soundness sweep test**

Add to `test_elements.gd` and register:

```gdscript
func _test_all_landmarks_forced_sound() -> bool:
	# Force each new landmark into column 0 and confirm the whole map stays
	# reachable + 2-connected across several seeds.
	for name in ["mill", "shaft", "flicker", "battery", "geyser", "press"]:
		MapGenerator.force_landmark = name
		for s in 12:
			var m := MapGenerator.generate("a3-%s-%d" % [name, s])
			if not MapPlanner.validate(m).is_empty():
				MapGenerator.force_landmark = ""
				print("  forced %s seed %d: %s" % [name, s, MapPlanner.validate(m)])
				return false
		MapGenerator.force_landmark = ""
	return true
```
```gdscript
	failures += _check("every forced new landmark stays sound", _test_all_landmarks_forced_sound())
```

- [ ] **Step 2: Run the full unit suite**

Run each and confirm exit 0:
```bash
godot/Godot_v4.4.1-stable_win64_console.exe --headless --path godot --script res://tests/test_elements.gd
godot/Godot_v4.4.1-stable_win64_console.exe --headless --path godot --script res://tests/test_mapgen.gd
godot/Godot_v4.4.1-stable_win64_console.exe --headless --path godot --script res://tests/test_lagcomp.gd
godot/Godot_v4.4.1-stable_win64_console.exe --headless --path godot --script res://tests/test_puppetstream.gd
```
Expected: `DONE: elements ok`, `DONE: 50 seeds + presets sound`, `DONE: LagCompHistory ok`, `DONE: PuppetStream ok`. If `_test_all_landmarks_forced_sound` fails, fix the offending builder's geometry (it names the landmark + seed + issues) and re-run from the relevant task — do NOT relax the test.

- [ ] **Step 3: Add the `--landmark=` arg**

In `auto_driver.gd`, next to the existing `--shot-event=` parse (~line 69), add:

```gdscript
		elif arg.begins_with("--landmark="):
			forced_landmark = arg.trim_prefix("--landmark=")
```
And declare the field near `var shot_event := "tag"` (~line 26):
```gdscript
var forced_landmark := ""
```

- [ ] **Step 4: Add the `shot-landmark` mode**

In the `match mode:` block (after the `"shot-ability"` arm, before `"launch-test"`), add:

```gdscript
		"shot-landmark":
			# Pin a landmark into column 0 and screenshot the live map so each
			# new structure can be eyeballed. Usage:
			#   --auto=shot-landmark --landmark=mill --code=mill.png
			MapGenerator.force_landmark = forced_landmark
			NetworkManager.host_lan(port)
			GameState.host_start_game(map_choice)
			_take_screenshot(1.5)
			return
```

- [ ] **Step 5: Capture the six screenshots**

Kill any orphan `Slippington.exe` first. For each landmark, run (example for the Mill):
```bash
godot/Godot_v4.4.1-stable_win64_console.exe --headless --path godot --auto=shot-landmark --landmark=mill --code=mill.png --seed=42
```
Repeat for `shaft, flicker, battery, geyser, press` with matching `--code=<name>.png`. Confirm each prints `[bot] screenshot saved` and the PNG exists and visibly shows the structure. (These are for human visual review — they are not asserted by CI.)

- [ ] **Step 6: Integration smoke (movement/tag unaffected)**

Run the host/join and swap auto modes (the delicate netcode checks) and confirm `ALL CHECKS PASSED` for each, plus `launch-test`:
```bash
godot/Godot_v4.4.1-stable_win64_console.exe --headless --path godot --auto=launch-test --code=launch.txt
```
Expected: `ALL CHECKS PASSED` (host/join + swaps) and the launch-test passes. (Use the existing two-instance host/join recipe for the swap modes.)

- [ ] **Step 7: Commit**

```bash
git add godot/tests/test_elements.gd godot/tests/auto_driver.gd
git commit -m "Landmark: forced-soundness sweep + shot-landmark screenshot mode"
```

---

## Self-Review

**Spec coverage (against `2026-06-22-map-elements-phase-a-design.md` §4):** All six landmarks from the §4 table are implemented (Mill→conveyor, Shaft→y-mover, Flicker→phase, Battery→launcher, Geyser→updraft, Press→pinch), and the `LANDMARKS` pool grows 5→11 with `LANDMARK_HALF` budgets for each. §5 (variety dial 4–6) and §6 (connector salting) are explicitly **deferred to Phase A4** per the approved scope split — not gaps. §9's per-landmark screenshot modes are delivered as a single parameterized `shot-landmark` mode (Task 7). The "ride/launch deposits" integration intent is covered by the existing `launch-test` regression and the forced-soundness sweep.

**Placeholder scan:** No "TBD"/"handle edge cases"/"similar to Task N". Every builder body and every test is shown in full. Each task repeats its own match-arm/const edits rather than referencing another task.

**Type consistency:** Builder signatures are consistent everywhere — `_mill(cx, rng)`, `_shaft(cx, rng)`, `_flicker(cx, rng)`, `_battery(cx, rng)` take `(float, SeededRng)`; `_geyser(cx, ground_y)` and `_press(cx, ground_y, rng)` take the ground (mirroring `_pocket`/`_spring_yard`/`_mast`). The `_build_landmark` match passes exactly those args. `force_landmark: String` is read in `generate()` and `auto_driver`. Object dicts match the planner's expected shapes (`launcher{pos,vel}`, `updraft{rect,accel}`), and the planner helpers called from tests (`_support_under`, `_launcher_edge_ok`, `_updraft_edge_ok`, `_sweep_rect`, `validate`) match their real signatures in `map_planner.gd`.

**Determinism:** Every builder draws only from the injected `rng`; no wall-clock or local state. Adding names to `LANDMARKS` reshuffles existing seeds (the accepted reroll noted in spec §7) — the M1 same-seed check still holds going forward (`test_mapgen` prints `describe()` for fixed seeds).
