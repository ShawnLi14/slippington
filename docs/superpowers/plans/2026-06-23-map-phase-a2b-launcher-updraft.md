# Map Phase A2b — Angled Launcher & Updraft Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Add the two "vertical reset" elements: the **Angled launcher** (a spring that fires you up *and* sideways — a long directed hop) and the **Updraft** (a zone of upward push you float up through). Both are new `Area2D` objects that act on the owning peer's own pawn, plus new *directed* edges in the `MapPlanner` so reachability/2-connectivity guarantees still hold.

**Architecture:** Both follow the existing spring/portal object pattern exactly — an `Area2D` instantiated from map `objects` data, acting only on `is_multiplayer_authority()` bodies (deterministic from the seed, nothing networked). The launcher reuses the spring's impulse path with a 2-D velocity; the updraft applies a per-frame upward force while a body is inside. The risky part is the planner: a launcher needs a directed arc edge (`_launcher_edge_ok`) and an updraft needs a vertical-assist edge (`_updraft_edge_ok`), both validated like springs.

**Robust placement:** To avoid the geometry-assumption pain A2's pinch hit, both elements are **derived from existing springs** — the generator converts a fraction of already-placed, already-validated spring pads (which come with proven support + reachable target + headroom) into launchers/updrafts, then re-validates and reverts on failure. No fresh position guessing.

**Tech Stack:** Godot 4.4.1, GDScript. Headless SceneTree unit tests on the autoload-free `MapGenerator`/`MapPlanner` layer; `Area2D`/`Player` runtime verified by clean import + `--auto` integration.

**This is plan 3 for Phase A.** A1 (conveyor + elevator) and A2 (phase + pinch) are merged; element frequencies were tuned up. A3 (the 6 landmarks + 4–6 variety dial + broad salting) follows.

## Global Constraints

- **Map-element-only.** Do NOT touch the shared movement controller's base verbs (run/jump/drop). Launcher/updraft act on the pawn via new dedicated methods, like `apply_spring`.
- **Determinism.** Driven only by static geometry / the synced `world_clock`; applied ONLY to `is_multiplayer_authority()` pawns (the spring/portal model); per-element randomness only from the seeded `rng`; nothing networked; same seed → same map.
- **Planner stays conservative & sound.** New edges must never claim a reach the player lacks (plan at `SPEED=270`, with the existing `EDGE_MARGIN`/`HEIGHT_MARGIN`). Every map stays reachable + 2-connected. Launchers/updrafts get object-validation rules like springs (support + reachable target + clearance); invalid ones are scrubbed.
- **Headless test limitation.** `Area2D`/`Player`/`PlatformBody` reference autoloads → not instantiable under `--script`; verify those via clean import + `--auto`. Only `MapGenerator`/`MapPlanner` are unit-testable; the planner edges carry the unit coverage.
- **Toolchain.** `GODOT="$LOCALAPPDATA/Programs/Godot/Godot_v4.4.1-stable_win64_console.exe"` (Git Bash). Reimport after adding a `class_name`/test: `"$GODOT" --headless --path godot --import`. Run a test: `"$GODOT" --headless --path godot --script res://tests/<file>.gd`. Element tests extend `godot/tests/test_elements.gd`. Import-clean check: `… --import 2>&1 | grep -iE "SCRIPT ERROR|Parse Error|ERROR at" || echo "IMPORT CLEAN"`.

---

### Task 1: Angled launcher — runtime (LauncherPad + Player.apply_launch + scene wiring)

**Files:**
- Create: `godot/scripts/game/launcher_pad.gd`
- Modify: `godot/scripts/game/player.gd` (add `apply_launch`)
- Modify: `godot/scripts/game/game.gd` (instantiate `"launcher"` objects)

**Interfaces:**
- Produces: object dict `{"type": "launcher", "pos": Vector2, "vel": Vector2}` (vel = up-and-sideways, vel.y < 0). `LauncherPad.create(pos, vel) -> LauncherPad`. `Player.apply_launch(vel: Vector2)`.

**Testing note:** `Area2D`/`Player` can't be instantiated headless; verified by clean import + the Task 7 integration smoke.

- [ ] **Step 1: Create `launcher_pad.gd`** (mirrors `spring_pad.gd` — duck-typed, authority-only, deterministic)

```gdscript
class_name LauncherPad
extends Area2D
## A directional launch pad: touch it and get flung up AND sideways along its
## aim vector. Like SpringPad, each peer applies the launch to its OWN player
## only (authority model) — deterministic from the seed, nothing to sync.

const SIZE := Vector2(48.0, 18.0)
const RETRIGGER_COOLDOWN := 0.3

var vel := Vector2(0, -700)  # launch velocity (up-and-sideways)
var _cooldown := 0.0
var _squash := 0.0


static func create(pos: Vector2, launch_vel: Vector2) -> LauncherPad:
	var pad := LauncherPad.new()
	pad.position = pos
	pad.vel = launch_vel
	return pad


func _ready() -> void:
	var shape := CollisionShape2D.new()
	var rect := RectangleShape2D.new()
	rect.size = SIZE
	shape.shape = rect
	add_child(shape)
	collision_layer = 0
	collision_mask = 4  # players
	body_entered.connect(_on_body_entered)


func _process(delta: float) -> void:
	_cooldown = maxf(0.0, _cooldown - delta)
	if _squash > 0.0:
		_squash = maxf(0.0, _squash - delta * 4.0)
		queue_redraw()


func _on_body_entered(body: Node) -> void:
	# Duck-typed (see SpringPad) so headless map tests don't chain in Player.
	if not body.has_method("apply_launch"):
		return
	if _cooldown <= 0.0:
		_cooldown = RETRIGGER_COOLDOWN
		_squash = 1.0
		queue_redraw()
	if body.is_multiplayer_authority() and body.velocity.y >= -100.0:
		body.apply_launch(vel)


func _draw() -> void:
	# A cannon-ish wedge pointing along the aim, in the spring palette.
	var dir := vel.normalized()
	var squash_offset := _squash * 5.0
	draw_rect(Rect2(-SIZE.x / 2.0, 2.0, SIZE.x, 6.0), Color("#5a3d2b"))  # base
	var muzzle := dir * (14.0 - squash_offset)
	draw_line(Vector2.ZERO, muzzle, Color("#ff8c5a"), 6.0)
	draw_circle(muzzle, 5.0, Color("#ffd2b0"))
```

- [ ] **Step 2: Add `Player.apply_launch`** in `godot/scripts/game/player.gd`, right after `apply_spring` (ends line ~396):

```gdscript
## Directional launch from an angled launcher pad (owning peer only). Unlike
## the spring (vertical only), this sets both velocity components.
func apply_launch(launch_vel: Vector2) -> void:
	velocity = launch_vel
	dash_left = 0.0
	SoundManager.play("spring")
```

- [ ] **Step 3: Wire `"launcher"` into the scene** in `godot/scripts/game/game.gd`, in `_ready()`'s object loop (the `match obj["type"]:` block, after the `"portal"` case):

```gdscript
			"launcher":
				add_child(LauncherPad.create(obj["pos"], obj["vel"]))
```

- [ ] **Step 4: Verify the project imports cleanly**

```bash
"$GODOT" --headless --path godot --import 2>&1 | grep -iE "SCRIPT ERROR|Parse Error|ERROR at" || echo "IMPORT CLEAN"
```
Expected: `IMPORT CLEAN`.

- [ ] **Step 5: Commit**

```bash
git add godot/scripts/game/launcher_pad.gd godot/scripts/game/launcher_pad.gd.uid godot/scripts/game/player.gd godot/scripts/game/game.gd
git commit -m "Angled launcher: LauncherPad object + Player.apply_launch + scene wiring"
```
(Run the `--import` first if the `.uid` isn't generated yet.)

---

### Task 2: Angled launcher — planner edge + object validation

**Files:**
- Modify: `godot/scripts/map/map_planner.gd` (`_launcher_edge_ok`, `_build_graph`, `validate`, `_scrub_objects`, `_support_under` use)
- Modify: `godot/tests/test_elements.gd`

**Interfaces:**
- Consumes: `{"type":"launcher","pos","vel"}` objects.
- Produces: directed graph edges from a launcher's support surface to surfaces its arc reaches; `validate`/`_scrub_objects` reject launchers with no support or no reachable target.

- [ ] **Step 1: Write the failing test**

In `godot/tests/test_elements.gd`, register:
```gdscript
	failures += _check("launcher reaches an in-arc target", _test_launcher_edge())
	failures += _check("launcher rejects an out-of-arc target", _test_launcher_miss())
```
And the methods (a launcher on a low pad, firing up-right, should reach a higher platform to its right but not one far to its left):
```gdscript
func _test_launcher_edge() -> bool:
	var support := {"rect": Rect2(200, 900, 200, 16), "type": "solid"}
	var target := {"rect": Rect2(640, 640, 200, 16), "type": "solid"}
	var blockers: Array[Rect2] = []
	# pad sits on the support, fires up-and-right
	return MapPlanner._launcher_edge_ok(Vector2(300, 893), Vector2(260, -700), support, target, blockers)

func _test_launcher_miss() -> bool:
	var support := {"rect": Rect2(200, 900, 200, 16), "type": "solid"}
	# target far to the LEFT and high — the up-RIGHT launch can't reach it
	var target := {"rect": Rect2(-400, 300, 200, 16), "type": "solid"}
	var blockers: Array[Rect2] = []
	return not MapPlanner._launcher_edge_ok(Vector2(300, 893), Vector2(260, -700), support, target, blockers)
```

- [ ] **Step 2: Run to verify it fails**

```bash
"$GODOT" --headless --path godot --import
"$GODOT" --headless --path godot --script res://tests/test_elements.gd
```
Expected: errors / FAIL on the launcher checks (`_launcher_edge_ok` doesn't exist yet).

- [ ] **Step 3: Add `_launcher_edge_ok` and wire it into the graph + validation**

In `godot/scripts/map/map_planner.gd`, add the edge function next to `_spring_edge_ok` (after it, ~line 252):

```gdscript
## Can a player launched from `pad_pos` with initial velocity `vel` (up and
## sideways) reach surface `b`? Models the projectile arc plus air-steering,
## conservatively (plans at SPEED). vel.y is negative (up).
static func _launcher_edge_ok(pad_pos: Vector2, vel: Vector2, support: Dictionary, b: Dictionary, blockers: Array[Rect2]) -> bool:
	if b == support:
		return false
	var rb: Rect2 = b["rect"]
	var apex_h := vel.y * vel.y / (2.0 * GRAVITY)  # height gained above the pad
	var rise := pad_pos.y - rb.position.y           # > 0 means b is above the pad
	if rise > apex_h - HEIGHT_MARGIN:
		return false
	var t_up := -vel.y / GRAVITY
	var fall_h := apex_h + HEIGHT_MARGIN - rise
	var t := t_up + sqrt(2.0 * maxf(fall_h, 0.0) / GRAVITY)
	# Where the launch carries you horizontally, plus air-steering both ways.
	var center_x := pad_pos.x + vel.x * t
	var reach := SPEED * t + EDGE_MARGIN
	var candidates := [
		clampf(center_x, rb.position.x, rb.end.x),
		rb.position.x + 25.0,
		rb.end.x - 25.0,
	]
	var skip := [support, b]
	for lx in candidates:
		if absf(lx - center_x) > reach:
			continue
		var apex_pt := Vector2(lerpf(pad_pos.x, lx, 0.5), pad_pos.y - apex_h - GameConfig.PLAYER_SIZE / 2.0)
		var land := Vector2(lx, rb.position.y - 6.0)
		if not _segment_blocked(pad_pos + Vector2(0, -8), apex_pt, blockers, skip) \
				and not _segment_blocked(apex_pt, land, blockers, skip):
			return true
	return false
```

In `_build_graph`, in the `for obj in map.get("objects", [])` loop, add a `launcher` branch alongside the `spring` one (mirror the spring's support-find + edge-add):

```gdscript
			elif obj["type"] == "launcher":
				var lsupport = _support_under(map, obj["pos"], 20.0)
				if lsupport == null:
					continue
				var li := surfaces.find(lsupport)
				for j in n:
					if j != li and _launcher_edge_ok(obj["pos"], obj["vel"], lsupport, surfaces[j], blockers):
						if not j in adj[li]:
							adj[li].append(j)
```

In `validate`, add a launcher arm to the object loop (after the spring/portal arms):
```gdscript
			elif obj["type"] == "launcher":
				if _support_under(map, obj["pos"], 20.0) == null:
					issues.append("launcher unsupported at %.0f,%.0f" % [obj["pos"].x, obj["pos"].y])
				elif not _launcher_has_target(map, obj):
					issues.append("launcher with no target at %.0f,%.0f" % [obj["pos"].x, obj["pos"].y])
```

Add the target helper (next to `_spring_has_target`, ~line 534):
```gdscript
static func _launcher_has_target(map: Dictionary, obj: Dictionary) -> bool:
	var support = _support_under(map, obj["pos"], 20.0)
	if support == null:
		return false
	var blockers := _blockers(map)
	for s in _surfaces(map):
		if s == support:
			continue
		if _launcher_edge_ok(obj["pos"], obj["vel"], support, s, blockers):
			return true
	return false
```

In `_scrub_objects`, add a launcher arm to the keep-check (after spring/portal):
```gdscript
			elif obj["type"] == "launcher":
				ok = _support_under(map, obj["pos"], 20.0) != null and _launcher_has_target(map, obj)
```

- [ ] **Step 4: Run to verify it passes**

```bash
"$GODOT" --headless --path godot --script res://tests/test_elements.gd
```
Expected: both launcher checks PASS, all others still PASS, `DONE: elements ok`.

- [ ] **Step 5: Commit**

```bash
git add godot/scripts/map/map_planner.gd godot/tests/test_elements.gd
git commit -m "Planner: angled-launcher directed edge + object validation"
```

---

### Task 3: Angled launcher — generation (convert a fraction of springs)

**Files:**
- Modify: `godot/scripts/map/map_generator.gd`
- Modify: `godot/tests/test_elements.gd`

**Interfaces:**
- Produces: maps whose `objects` may contain `launcher` entries (converted from springs the generator already placed and the planner already validated).

- [ ] **Step 1: Write the failing test**

In `godot/tests/test_elements.gd`, register:
```gdscript
	failures += _check("some seed produces a launcher", _test_gen_has_launcher())
```
And the method:
```gdscript
func _test_gen_has_launcher() -> bool:
	for s in 80:
		var m := MapGenerator.generate("a2b-%d" % s)
		for o in m.get("objects", []):
			if o["type"] == "launcher":
				return true
	return false
```

- [ ] **Step 2: Run to verify it fails**

```bash
"$GODOT" --headless --path godot --script res://tests/test_elements.gd
```
Expected: `FAIL some seed produces a launcher`.

- [ ] **Step 3: Convert some springs to launchers before the planner pass**

In `godot/scripts/map/map_generator.gd`, just before the final `return MapPlanner.plan(map, rng)` (and before the `if skip_plan: return map` line), add a conversion that re-aims a fraction of springs as launchers. Add the constant near the other chances (after `PHASE_CHANCE`):
```gdscript
## Chance a placed spring is re-aimed as an angled launcher instead.
const LAUNCHER_CHANCE := 0.45
```
Then, right before the post-pass return block at the end of `generate()` (find `var map := { ... }` then the `if skip_plan:` / `return MapPlanner.plan(...)`), insert after `map` is built but before `skip_plan`:
```gdscript
	# Re-aim a fraction of springs as angled launchers (up-and-sideways). The
	# planner's _scrub_objects DROPS any launcher whose arc has no valid target
	# (the source spring is then gone, but plan()'s repair pass re-routes, so the
	# map always stays sound — a conversion can never make a map unreachable).
	for o in map["objects"]:
		if o["type"] == "spring" and rng.next() < LAUNCHER_CHANCE:
			var dir := 1.0 if rng.next() < 0.5 else -1.0
			o["type"] = "launcher"
			o["vel"] = Vector2(dir * rng.next_float(180.0, 280.0), -rng.next_float(640.0, 740.0))
```
(Springs launch at `SpringPad.LAUNCH_VELOCITY = -780`; the launcher's vertical component is a touch lower because it also carries horizontal speed. A converted spring whose target was very high (above the launcher's lower apex) fails `_launcher_has_target` and gets dropped by `_scrub_objects` — that spring is lost but the repair pass re-routes, so the map stays sound. Most springs convert fine because the arc + air-steering still reaches the same target.)

- [ ] **Step 4: Run to verify it passes (and soundness holds)**

```bash
"$GODOT" --headless --path godot --script res://tests/test_elements.gd
```
Expected: all checks PASS including `generation stays sound with conveyors` and `some seed produces a launcher`, `DONE: elements ok`.

- [ ] **Step 5: Commit**

```bash
git add godot/scripts/map/map_generator.gd godot/tests/test_elements.gd
git commit -m "Angled launcher: re-aim a fraction of springs as launchers"
```

---

### Task 4: Updraft — runtime (UpdraftZone + Player.apply_updraft + scene wiring)

**Files:**
- Create: `godot/scripts/game/updraft_zone.gd`
- Modify: `godot/scripts/game/player.gd` (add `apply_updraft`)
- Modify: `godot/scripts/game/game.gd` (instantiate `"updraft"` objects)

**Interfaces:**
- Produces: object dict `{"type":"updraft","rect":Rect2,"accel":float}`. `UpdraftZone.create(rect, accel)`. `Player.apply_updraft(accel, delta)`.

- [ ] **Step 1: Create `updraft_zone.gd`** (an Area2D that applies upward force to the owning peer's body while it's inside)

```gdscript
class_name UpdraftZone
extends Area2D
## A vertical column of upward push: while inside, the owning peer's body is
## buoyed up (gravity countered + capped rise) so you float and steer. Each
## peer applies it only to its OWN player (authority model) — deterministic
## from the seed, nothing to sync.

const MAX_RISE := 230.0  # px/s cap on updraft-driven ascent

var rect := Rect2()
var accel := 1400.0  # upward px/s^2 applied while inside (> gravity = net lift)
var _bodies: Array = []


static func create(zone_rect: Rect2, zone_accel: float) -> UpdraftZone:
	var z := UpdraftZone.new()
	z.rect = zone_rect
	z.accel = zone_accel
	return z


func _ready() -> void:
	position = rect.position + rect.size / 2.0
	var shape := CollisionShape2D.new()
	var r := RectangleShape2D.new()
	r.size = rect.size
	shape.shape = r
	add_child(shape)
	collision_layer = 0
	collision_mask = 4  # players
	body_entered.connect(func(b): if not _bodies.has(b): _bodies.append(b))
	body_exited.connect(func(b): _bodies.erase(b))


func _physics_process(delta: float) -> void:
	for b in _bodies:
		if is_instance_valid(b) and b.has_method("apply_updraft") and b.is_multiplayer_authority():
			b.apply_updraft(accel, delta)


func _draw() -> void:
	# Faint up-arrows so the column reads as lift.
	var half := rect.size / 2.0
	var y := half.y - 10.0
	while y > -half.y:
		draw_line(Vector2(0, y), Vector2(0, y - 12), Color(0.6, 1.0, 1.0, 0.18), 2.0)
		draw_line(Vector2(-4, y - 7), Vector2(0, y - 12), Color(0.6, 1.0, 1.0, 0.18), 2.0)
		draw_line(Vector2(4, y - 7), Vector2(0, y - 12), Color(0.6, 1.0, 1.0, 0.18), 2.0)
		y -= 34.0
```

- [ ] **Step 2: Add `Player.apply_updraft`** in `player.gd`, right after `apply_launch`:

```gdscript
## Buoyancy from an updraft zone (owning peer only): counter gravity and cap
## the rise so the player floats up and can still steer.
func apply_updraft(updraft_accel: float, delta: float) -> void:
	velocity.y = maxf(velocity.y - updraft_accel * delta, -UpdraftZone.MAX_RISE)
```

- [ ] **Step 3: Wire `"updraft"` into the scene** in `game.gd`'s object loop, after the `"launcher"` case:

```gdscript
			"updraft":
				add_child(UpdraftZone.create(obj["rect"], obj["accel"]))
```

- [ ] **Step 4: Verify the project imports cleanly**

```bash
"$GODOT" --headless --path godot --import 2>&1 | grep -iE "SCRIPT ERROR|Parse Error|ERROR at" || echo "IMPORT CLEAN"
```
Expected: `IMPORT CLEAN`.

- [ ] **Step 5: Commit**

```bash
git add godot/scripts/game/updraft_zone.gd godot/scripts/game/updraft_zone.gd.uid godot/scripts/game/player.gd godot/scripts/game/game.gd
git commit -m "Updraft: UpdraftZone object + Player.apply_updraft + scene wiring"
```

---

### Task 5: Updraft — planner edge + object validation

**Files:**
- Modify: `godot/scripts/map/map_planner.gd`
- Modify: `godot/tests/test_elements.gd`

**Interfaces:**
- Consumes: `{"type":"updraft","rect","accel"}` objects.
- Produces: graph edges from the surface under the updraft's base to surfaces within the column it can lift you to; validation rejects updrafts with no base support or no reachable target.

- [ ] **Step 1: Write the failing test**

Register:
```gdscript
	failures += _check("updraft lifts to an in-column target", _test_updraft_edge())
	failures += _check("updraft rejects an out-of-column target", _test_updraft_miss())
```
Methods (a tall updraft column; a platform inside its x-span and above its base is reachable, one outside the x-span is not):
```gdscript
func _test_updraft_edge() -> bool:
	var support := {"rect": Rect2(400, 900, 160, 16), "type": "solid"}
	var target := {"rect": Rect2(420, 600, 120, 16), "type": "solid"}
	var blockers: Array[Rect2] = []
	# column spans x 400..560, y 560..900 (base just above support)
	return MapPlanner._updraft_edge_ok(Rect2(400, 560, 160, 340), support, target, blockers)

func _test_updraft_miss() -> bool:
	var support := {"rect": Rect2(400, 900, 160, 16), "type": "solid"}
	var target := {"rect": Rect2(900, 600, 120, 16), "type": "solid"}  # far right, outside column
	var blockers: Array[Rect2] = []
	return not MapPlanner._updraft_edge_ok(Rect2(400, 560, 160, 340), support, target, blockers)
```

- [ ] **Step 2: Run to verify it fails**

```bash
"$GODOT" --headless --path godot --script res://tests/test_elements.gd
```
Expected: FAIL on the updraft checks.

- [ ] **Step 3: Add `_updraft_edge_ok` + graph/validation wiring**

In `map_planner.gd`, add (after `_launcher_edge_ok`):
```gdscript
## Can a player floating up inside an updraft column reach surface `b`? The
## column lifts you anywhere within its x-span up to its top; you then step
## off onto a surface overlapping that span and above the base.
static func _updraft_edge_ok(zone: Rect2, support: Dictionary, b: Dictionary, blockers: Array[Rect2]) -> bool:
	if b == support:
		return false
	var rb: Rect2 = b["rect"]
	# Surface must overlap the column horizontally and sit within the lift band
	# (above the base, at or below the column top minus a small margin).
	if rb.end.x < zone.position.x or rb.position.x > zone.end.x:
		return false
	if rb.position.y > zone.end.y - GameConfig.PLAYER_SIZE:
		return false  # not above the base (inside/below the column floor)
	if rb.position.y < zone.position.y - HEIGHT_MARGIN:
		return false  # above the column's reach
	var lx := clampf(zone.get_center().x, rb.position.x, rb.end.x)
	var rise_pt := Vector2(lx, zone.position.y)
	var land := Vector2(lx, rb.position.y - 6.0)
	var skip := [support, b]
	return not _segment_blocked(Vector2(lx, zone.end.y - 8), rise_pt, blockers, skip) \
			and not _segment_blocked(rise_pt, land, blockers, skip)
```

In `_build_graph`'s object loop, add an `updraft` branch (the base support is the surface under the column's bottom-center):
```gdscript
			elif obj["type"] == "updraft":
				var uz: Rect2 = obj["rect"]
				var usupport = _support_under(map, Vector2(uz.get_center().x, uz.end.y), 24.0)
				if usupport == null:
					continue
				var ui := surfaces.find(usupport)
				for j in n:
					if j != ui and _updraft_edge_ok(uz, usupport, surfaces[j], blockers):
						if not j in adj[ui]:
							adj[ui].append(j)
```

In `validate`, add an updraft arm:
```gdscript
			elif obj["type"] == "updraft":
				var uz2: Rect2 = obj["rect"]
				if _support_under(map, Vector2(uz2.get_center().x, uz2.end.y), 24.0) == null:
					issues.append("updraft unsupported at %.0f,%.0f" % [uz2.position.x, uz2.position.y])
				elif not _updraft_has_target(map, obj):
					issues.append("updraft with no target at %.0f,%.0f" % [uz2.position.x, uz2.position.y])
```

Add the target helper:
```gdscript
static func _updraft_has_target(map: Dictionary, obj: Dictionary) -> bool:
	var uz: Rect2 = obj["rect"]
	var support = _support_under(map, Vector2(uz.get_center().x, uz.end.y), 24.0)
	if support == null:
		return false
	var blockers := _blockers(map)
	for s in _surfaces(map):
		if s == support:
			continue
		if _updraft_edge_ok(uz, support, s, blockers):
			return true
	return false
```

In `_scrub_objects`, add:
```gdscript
			elif obj["type"] == "updraft":
				ok = _support_under(map, Vector2(obj["rect"].get_center().x, obj["rect"].end.y), 24.0) != null \
					and _updraft_has_target(map, obj)
```

- [ ] **Step 4: Run to verify it passes**

```bash
"$GODOT" --headless --path godot --script res://tests/test_elements.gd
```
Expected: both updraft checks PASS, all others PASS, `DONE: elements ok`.

- [ ] **Step 5: Commit**

```bash
git add godot/scripts/map/map_planner.gd godot/tests/test_elements.gd
git commit -m "Planner: updraft vertical-assist edge + object validation"
```

---

### Task 6: Updraft — generation (convert a fraction of springs to columns)

**Files:**
- Modify: `godot/scripts/map/map_generator.gd`
- Modify: `godot/tests/test_elements.gd`

**Interfaces:**
- Produces: maps whose `objects` may contain `updraft` entries (a column rising from a spring's spot up toward the spring's target band). `_scrub_objects` reverts any with no valid target.

- [ ] **Step 1: Write the failing test**

Register:
```gdscript
	failures += _check("some seed produces an updraft", _test_gen_has_updraft())
```
Method:
```gdscript
func _test_gen_has_updraft() -> bool:
	for s in 80:
		var m := MapGenerator.generate("a2b-%d" % s)
		for o in m.get("objects", []):
			if o["type"] == "updraft":
				return true
	return false
```

- [ ] **Step 2: Run to verify it fails**

```bash
"$GODOT" --headless --path godot --script res://tests/test_elements.gd
```
Expected: `FAIL some seed produces an updraft`.

- [ ] **Step 3: Convert some (still-spring) pads into updraft columns**

In `map_generator.gd`, add the constant after `LAUNCHER_CHANCE`:
```gdscript
## Chance a still-spring pad becomes an updraft column instead.
const UPDRAFT_CHANCE := 0.30
```
In the same end-of-`generate()` conversion loop you added in Task 3 (the `for o in map["objects"]:` loop), extend it so a pad that did NOT become a launcher may become an updraft. Replace the launcher-only loop body with:
```gdscript
	for o in map["objects"]:
		if o["type"] != "spring":
			continue
		if rng.next() < LAUNCHER_CHANCE:
			var dir := 1.0 if rng.next() < 0.5 else -1.0
			o["type"] = "launcher"
			o["vel"] = Vector2(dir * rng.next_float(180.0, 280.0), -rng.next_float(640.0, 740.0))
		elif rng.next() < UPDRAFT_CHANCE:
			# A column rising from just above the pad's footing up ~spring height.
			var col_w := 96.0
			var col_h := minf(320.0, MapPlanner.spring_height() * 0.7)
			o["type"] = "updraft"
			o["rect"] = Rect2(o["pos"].x - col_w / 2.0, o["pos"].y - col_h, col_w, col_h)
			o["accel"] = 1400.0
			o.erase("pos")
```
(Order matters: the launcher roll is consumed first so the two conversions are mutually exclusive and deterministic. `_scrub_objects` DROPS any updraft whose column reaches no surface — that pad is then gone, but plan()'s repair pass re-routes, so the map always stays sound.)

- [ ] **Step 4: Run to verify it passes (and soundness holds)**

```bash
"$GODOT" --headless --path godot --script res://tests/test_elements.gd
```
Expected: all checks PASS including `generation stays sound with conveyors` and `some seed produces an updraft`, `DONE: elements ok`.

- [ ] **Step 5: Commit**

```bash
git add godot/scripts/map/map_generator.gd godot/tests/test_elements.gd
git commit -m "Updraft: convert a fraction of spring pads into updraft columns"
```

---

### Task 7: Phase-A2b regression gate

**Files:** none (verification only).

- [ ] **Step 1: Full headless suite**

```bash
"$GODOT" --headless --path godot --import
for t in test_elements test_lagcomp test_puppetstream test_mapgen; do
  echo "=== $t ==="
  "$GODOT" --headless --path godot --script res://tests/$t.gd 2>&1 | grep -iE "PASS|FAIL|DONE"
done
```
Expected: every suite ends `DONE` / all `PASS`. `test_mapgen` (50 seeds + presets sound) must still pass with launchers and updrafts in play.

- [ ] **Step 2: Integration smoke**

```bash
for mode in "host:join:9988" "host-swap:join-swap:9989"; do
  IFS=: read h j port <<< "$mode"
  rm -f /tmp/h_$port.log /tmp/j_$port.log
  "$GODOT" --headless --path godot -- --auto=$h --port=$port --match-seconds=10 > /tmp/h_$port.log 2>&1 &
  sleep 1
  "$GODOT" --headless --path godot -- --auto=$j --port=$port > /tmp/j_$port.log 2>&1
  wait
  echo "=== $h/$j ==="; grep -iE "ALL CHECKS|FAIL" /tmp/h_$port.log /tmp/j_$port.log
done
```
Expected: `ALL CHECKS PASSED` for both pairs — launcher impulses and updraft buoyancy cause no movement/tag regression.

- [ ] **Step 3: Confirm.** If green, A2b is complete and shippable. Then rebuild the Windows exe for playtest (kill orphan `Slippington.exe` first, `--export-release "Windows" export/windows/Slippington.exe`). If anything fails, invoke `superpowers:systematic-debugging`.

---

## Self-review notes

- **Spec coverage (A2b slice):** Angled launcher — object data (§3.5), runtime impulse, planner directed edge + validation, generation ✔. Updraft — zone data (§3.6), runtime buoyancy, planner vertical-assist edge + validation, generation ✔.
- **Robustness:** both derive from springs (already validated for support + target + headroom); `_scrub_objects` DROPS any conversion whose new reach is invalid and plan()'s repair pass re-routes, so neither can produce an unreachable map. This sidesteps the fresh-position geometry guessing that made A2's pinch placement painful. (Quality note: a dropped conversion loses that spring — measure the surviving launch-point count during dev; if too lossy, lower LAUNCHER/UPDRAFT_CHANCE or revert-to-spring instead of drop.)
- **Testing reality:** the planner edges (`_launcher_edge_ok`, `_updraft_edge_ok`) are pure and carry the unit coverage; the `Area2D`/`Player` runtime is verified by clean import + `--auto` integration.
- **Risks:** (1) the launcher arc math is the most intricate piece — the two edge tests (reaches / misses) guard direction and range, and the conservative `SPEED`/margins + `_scrub_objects` backstop prevent over-claiming. (2) Updraft `apply_updraft` runs from the zone's `_physics_process` while the player's own `_authority_physics` applies gravity the same frame; net buoyancy is correct over frames, and the integration smoke confirms no regression. (3) Spring→launcher/updraft conversion reduces the count of plain springs — acceptable (springs are common; A3 landmarks add more launch points).

## Future plan
- **A3 — Landmarks, variety & salting:** 6 builders (Mill/Shaft/Flicker/Battery/Geyser/Press — Battery showcases launchers, Geyser showcases updrafts, Shaft fixes the vertical-mover frequency limit), pool 5→11, `N=4..6` per map, broad connector salting, `shot-*` screenshot modes per spec §9.
