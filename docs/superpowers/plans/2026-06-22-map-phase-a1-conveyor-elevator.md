# Map Phase A1 — Conveyor & Vertical Elevator Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Add the two zero-risk map elements — Conveyor belts and vertical (y-axis) Elevator movers — end-to-end, establishing the data, runtime, and test conventions the rest of Phase A reuses.

**Architecture:** New elements are plain data on the existing map dictionaries; the runtime reads them in `PlatformBody` and `Player`, applied per-peer on the authority's own pawn (deterministic, nothing synced — same model as springs/portals). The `MapPlanner` needs no new logic for these two (conveyor is a bonus the planner conservatively ignores; vertical movers are already modeled by `_sweep_rect`). Generation salts conveyors onto connector platforms and emits some movers on the y axis.

**Tech Stack:** Godot 4.4.1, GDScript. Headless SceneTree unit tests. Existing seeded RNG + traversal-graph planner.

**This is plan 1 of 3 for Phase A** (see the spec `docs/superpowers/specs/2026-06-22-map-elements-phase-a-design.md`). A2 covers the four planner-intricate elements (Phase platform, Angled launcher, Updraft, Pinch gate); A3 covers the 6 new landmarks, the 4–6 variety dial, and connector salting. Each plan ships working, tested software.

## Global Constraints

Every task implicitly includes these (copied from the spec):

- **Map-element-only.** Do NOT touch the shared movement controller's base verbs (run/jump/drop). New behavior is surface/zone interaction, not new player abilities.
- **Determinism.** Elements are driven ONLY by static geometry or the already-synced `GameState.world_clock`. Apply per-element effects ONLY to `is_multiplayer_authority()` pawns (the spring/portal pattern). Never trigger off local contact-time or `Time.get_ticks` for gameplay state. Nothing about these elements is sent over the network.
- **Planner stays conservative.** Plans at `SPEED=270` (runtime is 330). New elements must never make a map claim a reach it lacks, nor let a sometimes-open element block an arc.
- **Determinism check holds going forward.** Adding elements shifts the seeded RNG stream, so existing seeds reroll to new maps — accepted. But same-seed-same-map must still hold after each change.
- **Headless test limitation (important).** Under `--script` SceneTree mode the autoload singletons (`GameState`, etc.) are NOT loaded, so any `class_name` script that references an autoload — including `PlatformBody` and `Player` — fails to COMPILE when instantiated in a test and cannot be unit-tested by instantiation. Only autoload-free `class_name` classes (`MapGenerator`, `MapPlanner`, `SeededRng`, `GameConfig`) are headless-testable. Test new data/generation logic through those; verify node/runtime changes via the `--auto` integration modes and a clean project import.
- **Toolchain.** Godot binary: `$LOCALAPPDATA/Programs/Godot/Godot_v4.4.1-stable_win64_console.exe` (call it `$GODOT`). After adding/renaming any `class_name` script or test, reimport first: `"$GODOT" --headless --path godot --import`. Run a headless test: `"$GODOT" --headless --path godot --script res://tests/<file>.gd`.

---

### Task 1: Conveyor data field + PlatformBody rendering

**Files:**
- Modify: `godot/scripts/game/platform_body.gd` (add field in `create`, draw chevrons in `_draw`)

**Interfaces:**
- Produces: `PlatformBody.conveyor: Dictionary` — `{"dir": int (±1), "speed": float}` when the platform is a belt, else `{}`. Populated from `data.get("conveyor", {})`. Later tasks (Player) read `collider.conveyor`.

**Testing note:** `PlatformBody` references the `GameState` autoload in `_physics_process`, so it CANNOT be instantiated under headless `--script` mode (see Global Constraints). The `conveyor` field is a pure transcription assignment — its data shape is covered by the generator test in Task 3 (pure dicts, no node instantiation) and its runtime effect by the integration run in Task 2. Task 1 is verified by a clean project import.

- [ ] **Step 1: Add the field and rendering**

In `godot/scripts/game/platform_body.gd`, add the field next to the others (after `var move_data` on line 17):

```gdscript
var conveyor: Dictionary = {}  # {dir: ±1, speed: float} or empty
```

In `create()`, after `p.move_data = data.get("move", {})`:

```gdscript
	p.conveyor = data.get("conveyor", {})
```

In `_draw()`, just before the final `if type == "ice":` glint block (i.e., right after the flat-platform non-thru `draw_line(...edge...)` and at the same indent level as the `if thru:` / `else:` pair, so it runs regardless of thru), add belt chevrons so direction reads at a glance:

```gdscript
	if not conveyor.is_empty():
		var cdir: int = conveyor["dir"]
		var cy := -half.y + 9.0
		var cx := -half.x + 14.0
		while cx < half.x - 14.0:
			draw_line(Vector2(cx, cy - 4), Vector2(cx + 6 * cdir, cy), Color(1, 1, 1, 0.6), 2.0)
			draw_line(Vector2(cx + 6 * cdir, cy), Vector2(cx, cy + 4), Color(1, 1, 1, 0.6), 2.0)
			cx += 22.0
```

- [ ] **Step 2: Verify the project imports cleanly**

Run:
```bash
"$GODOT" --headless --path godot --import 2>&1 | grep -iE "SCRIPT ERROR|Parse Error|ERROR at" || echo "IMPORT CLEAN"
```
Expected: `IMPORT CLEAN` — no parse/script errors introduced by the new field or draw code.

- [ ] **Step 3: Commit**

```bash
git add godot/scripts/game/platform_body.gd
git commit -m "Conveyor: PlatformBody field + belt chevrons"
```

---

### Task 2: Player conveyor force

**Files:**
- Modify: `godot/scripts/game/player.gd` (add `_standing_on_conveyor`, apply force in `_authority_physics`)

**Interfaces:**
- Consumes: `PlatformBody.conveyor` (Task 1).
- Produces: `Player._standing_on_conveyor() -> Dictionary` — the belt under the player's feet, or `{}`.

This is runtime physics (floor + slide collisions); `Player` references autoloads, so it is verified by a clean import + the `--auto` integration smoke (no regression), NOT a headless unit test. The belt-drift visual confirmation happens at the Task 5 gate, once Task 3 actually generates belts.

- [ ] **Step 1: Add the detector (mirrors `_standing_on_ice`)**

In `godot/scripts/game/player.gd`, immediately after `_standing_on_ice()` (ends line 389):

```gdscript
## The conveyor belt (if any) the player is standing on, else {}.
func _standing_on_conveyor() -> Dictionary:
	if not is_on_floor():
		return {}
	for i in get_slide_collision_count():
		var collider := get_slide_collision(i).get_collider()
		if collider is PlatformBody and not collider.conveyor.is_empty():
			return collider.conveyor
	return {}
```

- [ ] **Step 2: Apply the belt in `_authority_physics`**

In the `else` branch of the movement block (the not-dashing/not-stunned case), right after the ice/solid `velocity.x` assignment closes (after line 205, before the `if direction > 0.0` facing block on line 206), add (note: 3 tabs of indent — it sits inside that `else`):

```gdscript
			var belt := _standing_on_conveyor()
			if not belt.is_empty():
				velocity.x += float(belt["dir"]) * belt["speed"]
```

(The belt is additive on top of input each frame — run with it for a boost, against it and you crawl, stand still and you drift. Re-applied every physics frame, not accumulated.)

- [ ] **Step 3: Verify import + integration smoke**

```bash
"$GODOT" --headless --path godot --import 2>&1 | grep -iE "SCRIPT ERROR|Parse Error|ERROR at" || echo "IMPORT CLEAN"
rm -f /tmp/h_a1.log /tmp/j_a1.log
"$GODOT" --headless --path godot -- --auto=host --port=9991 --match-seconds=8 > /tmp/h_a1.log 2>&1 &
sleep 1
"$GODOT" --headless --path godot -- --auto=join --port=9991 > /tmp/j_a1.log 2>&1
wait
grep -iE "ALL CHECKS|FAIL" /tmp/h_a1.log /tmp/j_a1.log
```
Expected: `IMPORT CLEAN`, and `ALL CHECKS PASSED` on both host and join (the belt code path compiles and causes no movement/tag regression; belts aren't generated yet, so this is a no-regression gate).

- [ ] **Step 4: Commit**

```bash
git add godot/scripts/game/player.gd
git commit -m "Conveyor: player belt force (run-with boost, run-against crawl)"
```

---

### Task 3: Generator salts conveyors + the element test suite

**Files:**
- Modify: `godot/scripts/map/map_generator.gd` (add `CONVEYOR_CHANCE`, tag some connector flats)
- Create: `godot/tests/test_elements.gd` (generation-soundness + coverage tests — pure dicts, no node instantiation)

**Interfaces:**
- Consumes: nothing new.
- Produces: maps whose `platforms` may carry a `conveyor` dict on flat, solid, non-thru connectors. Establishes `tests/test_elements.gd`, extended by Task 4.

- [ ] **Step 1: Write the failing test**

Create `godot/tests/test_elements.gd` (uses only `MapGenerator`/`MapPlanner` — pure `class_name` classes with no autoload dependency, so they run headless):

```gdscript
extends SceneTree
## Phase-A element unit tests (headless):
##   godot --headless --path . --script res://tests/test_elements.gd
## These exercise the autoload-free generation/planner layer only — node
## classes like PlatformBody/Player can't be instantiated under --script.

func _init() -> void:
	var failures := 0
	failures += _check("generation stays sound with conveyors", _test_gen_sound())
	failures += _check("some seed produces a conveyor", _test_gen_has_conveyor())
	if failures > 0:
		print("FAILED: %d test(s)" % failures)
		quit(1)
		return
	print("DONE: elements ok")
	quit(0)

func _check(name: String, ok: bool) -> int:
	print(("PASS " if ok else "FAIL ") + name)
	return 0 if ok else 1

func _test_gen_sound() -> bool:
	for s in 30:
		var m := MapGenerator.generate("a1-%d" % s)
		if not MapPlanner.validate(m).is_empty():
			return false
	return true

func _test_gen_has_conveyor() -> bool:
	# Across many seeds at least one belt should appear (CONVEYOR_CHANCE > 0).
	for s in 60:
		var m := MapGenerator.generate("a1-%d" % s)
		for p in m["platforms"]:
			if not p.get("conveyor", {}).is_empty():
				return true
	return false
```

- [ ] **Step 2: Run the test to verify the coverage case fails**

Run:
```bash
"$GODOT" --headless --path godot --import
"$GODOT" --headless --path godot --script res://tests/test_elements.gd
```
Expected: `PASS generation stays sound with conveyors` (already sound), `FAIL some seed produces a conveyor` (no belts generated yet), `FAILED: 1 test(s)`.

- [ ] **Step 3: Add conveyor salting to the connector loop**

In `godot/scripts/map/map_generator.gd`, add the constant near the other connector chances (after `const BEND_CHANCE := 0.18` on line 27):

```gdscript
## Chance a flat solid connector becomes a conveyor belt.
const CONVEYOR_CHANCE := 0.12
```

In the connector loop, right after a flat platform is appended to `layer_platforms` — i.e., after the `else: platform = {"rect": rect, "type": p_type, "thru": thru}` branch and its `platforms.append(platform); layer_platforms.append(platform)` (after line 161) — add (4 tabs of indent, matching the loop body):

```gdscript
			# Salt a conveyor onto eligible flats (solid, non-thru, non-ramp).
			if not platform.has("ramp") and not platform.get("thru", false) \
					and platform["type"] == "solid" and rng.next() < CONVEYOR_CHANCE:
				platform["conveyor"] = {
					"dir": 1 if rng.next() < 0.5 else -1,
					"speed": rng.next_float(90.0, 150.0),
				}
```

- [ ] **Step 4: Run the test to verify it passes**

Run:
```bash
"$GODOT" --headless --path godot --script res://tests/test_elements.gd
```
Expected: both checks PASS, `DONE: elements ok`.

- [ ] **Step 5: Commit**

```bash
git add godot/scripts/map/map_generator.gd godot/tests/test_elements.gd godot/tests/test_elements.gd.uid
git commit -m "Conveyor: salt belts onto connectors + element test suite"
```

---

### Task 4: Vertical (y-axis) elevator movers

**Files:**
- Modify: `godot/scripts/map/map_generator.gd` (let the mover loop emit `axis:"y"` with vertical clearance)
- Modify: `godot/tests/test_elements.gd` (coverage: some seed produces a vertical mover; soundness still holds)

**Interfaces:**
- Consumes: nothing new (`PlatformBody._physics_process` and `MapPlanner._sweep_rect` already handle `axis:"y"`).
- Produces: maps whose movers may have `move["axis"] == "y"`.

- [ ] **Step 1: Write the failing test**

In `godot/tests/test_elements.gd`, register a third check in `_init` (after the conveyor checks):

```gdscript
	failures += _check("some seed produces a vertical mover", _test_gen_has_ymover())
```

And add the method:

```gdscript
func _test_gen_has_ymover() -> bool:
	for s in 60:
		var m := MapGenerator.generate("a1-%d" % s)
		for p in m["platforms"]:
			if p.get("move", {}).get("axis", "x") == "y":
				return true
	return false
```

- [ ] **Step 2: Run the test to verify it fails**

Run:
```bash
"$GODOT" --headless --path godot --script res://tests/test_elements.gd
```
Expected: `FAIL some seed produces a vertical mover` (the loop only emits `axis:"x"`), `FAILED: 1 test(s)`.

- [ ] **Step 3: Emit vertical movers with vertical clearance**

In `godot/scripts/map/map_generator.gd`, inside the `while movers_assigned < mover_target` loop, replace the block that builds `probe`, sets the horizontal-only `p["move"]`, checks the unreachable delta, and increments `movers_assigned` (lines 301-312) with an axis choice. It goes after the existing `max_amp` computation and the `if max_amp < 50.0: continue` guard:

```gdscript
		# Vertical clearance: nearest platform above/below within this column.
		var v_amp := minf(rect.position.y - 120.0, LANDMARK_TOP - rect.end.y)
		for q in platforms:
			if q == p:
				continue
			var qr2: Rect2 = q["rect"]
			if qr2.end.x <= rect.position.x or qr2.position.x >= rect.end.x:
				continue  # not in this column
			if qr2.end.y <= rect.position.y:
				v_amp = minf(v_amp, rect.position.y - qr2.end.y - 12.0)
			elif qr2.position.y >= rect.end.y:
				v_amp = minf(v_amp, qr2.position.y - rect.end.y - 12.0)
		var go_vertical := v_amp >= 60.0 and rng.next() < 0.4
		var probe := {"width": width, "height": height, "platforms": platforms, "objects": objects}
		var base_unreachable: int = MapPlanner._unreachable_surfaces(probe).size()
		if go_vertical:
			p["move"] = {
				"axis": "y",
				"amplitude": minf(rng.next_float(70.0, 130.0), v_amp),
				"period": rng.next_float(5.0, 8.0),
				"phase": rng.next_float(0.0, 1.0),
			}
		else:
			p["move"] = {
				"axis": "x",
				"amplitude": minf(rng.next_float(110.0, 180.0), max_amp),
				"period": rng.next_float(6.0, 9.0),
				"phase": rng.next_float(0.0, 1.0),
			}
		if MapPlanner._unreachable_surfaces(probe).size() > base_unreachable:
			p.erase("move")
			continue
		movers_assigned += 1
```

The existing `_strip_colliding_movers`/`validate` planner pass already strips any vertical sweep that collides (`_mover_sweep_collides` + `_sweep_rect` both handle the y axis).

- [ ] **Step 4: Run the test to verify it passes**

Run:
```bash
"$GODOT" --headless --path godot --script res://tests/test_elements.gd
```
Expected: all three checks PASS, `DONE: elements ok`. (`generation stays sound with conveyors` still passes — it validates every seed, vertical movers included.)

- [ ] **Step 5: Commit**

```bash
git add godot/scripts/map/map_generator.gd godot/tests/test_elements.gd
git commit -m "Elevator: emit vertical (y-axis) movers with clearance"
```

---

### Task 5: Phase-A1 regression gate

**Files:** none (verification only).

- [ ] **Step 1: Run the full headless suite**

```bash
"$GODOT" --headless --path godot --import
for t in test_elements test_lagcomp test_puppetstream test_mapgen; do
  echo "=== $t ==="
  "$GODOT" --headless --path godot --script res://tests/$t.gd 2>&1 | grep -iE "PASS|FAIL|DONE"
done
```
Expected: every suite ends `DONE` / all `PASS`. In particular `test_mapgen` (planner soundness across 50 seeds + presets) must still pass with conveyors and vertical movers in play.

- [ ] **Step 2: Run the integration smoke (host/join + a swap mode)**

```bash
for mode in "host:join:9992" "host-swap:join-swap:9993"; do
  IFS=: read h j port <<< "$mode"
  rm -f /tmp/h_$port.log /tmp/j_$port.log
  "$GODOT" --headless --path godot -- --auto=$h --port=$port --match-seconds=10 > /tmp/h_$port.log 2>&1 &
  sleep 1
  "$GODOT" --headless --path godot -- --auto=$j --port=$port > /tmp/j_$port.log 2>&1
  wait
  echo "=== $h/$j ==="; grep -iE "ALL CHECKS|FAIL" /tmp/h_$port.log /tmp/j_$port.log
done
```
Expected: `ALL CHECKS PASSED` for both pairs (no movement/tag regression from the belt force or vertical movers).

- [ ] **Step 3: Confirm and stop**

If everything is green, Phase A1 is complete and shippable. Do NOT tag/release (that happens after A2/A3 land). If anything fails, fix before moving on — invoke `superpowers:systematic-debugging`.

---

## Self-review notes

- **Spec coverage (A1 slice):** Conveyor — data (§3.1), runtime force, generator placement, planner no-op (conservative) ✔. Vertical elevator — generator emission (§3.3), planner already-modeled ✔. Determinism: belt + mover both ride static geometry / `world_clock`, applied on the authority pawn only ✔.
- **Testing reality:** node classes that touch autoloads can't be instantiated headless, so `PlatformBody`/`Player` changes are verified by clean import + `--auto` integration; the pure generation/planner layer carries the unit tests. This matches the existing `test_mapgen`/`test_lagcomp` split.
- **Out of scope here (later plans):** Phase platform, Angled launcher, Updraft, Pinch gate (A2); 6 landmarks, 4–6 dial, connector salting beyond conveyors (A3); Crumbling, Zip-line, Phase-B curator (deferred).
- **Risk:** the vertical-mover clearance heuristic may reject many candidates (falling back to horizontal); acceptable — the planner probe guarantees no map is broken, and A3's Shaft landmark gives vertical movers a guaranteed home.

## Future plans (titles only — detailed in their own documents)

- **Plan A2 — Route-fake & vertical-reset elements:** Phase platform (PlatformBody collision toggle off `world_clock`; planner land-yes/block-no), Angled launcher (`apply_launch(vel)` + `_launcher_edge_ok` + validation), Updraft (zone Area2D + `_updraft_edge_ok` + validation), Pinch gate (counter-phase pair; planner sweep-exemption + non-blocking).
- **Plan A3 — Landmarks, variety & salting:** 6 builders (Mill, Shaft, Flicker, Battery, Geyser, Press), pool 5→11, `N = 4..6` per map with packing generalization, salt new elements into connectors, full `test_mapgen` sweep + `shot-*` screenshot modes.
