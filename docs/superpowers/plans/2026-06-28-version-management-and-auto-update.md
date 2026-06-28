# Version Management & Auto-Update Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Show the running version, refuse mismatched-version joiners with a clear message, and let players auto-update (download → swap → relaunch) on Windows and macOS.

**Architecture:** One version constant (`GameConfig.GAME_VERSION`) is the source of truth for display, the host-authoritative join gate, and the update check. Pure version/parse logic lives in a `class_name UpdateCheck` util (headless-testable); an `Updater` autoload owns HTTP, filesystem swaps, and relaunch. The join gate piggybacks on the existing `register_player` RPC.

**Tech Stack:** Godot 4.4.1 GDScript; Godot high-level multiplayer RPCs (ENet + WebRTC); `HTTPRequest`, `ZIPReader`/`ZIPPacker`, `DirAccess`/`FileAccess`, `OS.create_process`; GitHub Releases REST API.

## Global Constraints

- **Engine:** Godot **4.4.1-stable** exactly. GDScript can't infer bool/numeric/Dictionary from Variant — annotate explicitly; use `mini()`/`maxi()` for integer min/max.
- **Current version value:** `GAME_VERSION := "2.1.0"` (matches the live release; the gate/check compare against this).
- **Mismatch rule:** **exact** string match required to join (decided in spec).
- **Web:** the entire update subsystem is disabled when `OS.has_feature("web")`. The version label still shows; the join gate still applies.
- **Repo for the update check:** `https://api.github.com/repos/ShawnLi14/slippington/releases/latest`. Assets are named `Slippington-Windows.zip` and `Slippington-macOS.zip`.
- **Godot binary (not in repo):** `$LOCALAPPDATA/Programs/Godot/Godot_v4.4.1-stable_win64_console.exe`. Headless unit tests run from the `godot/` dir: `"$GODOT" --headless --path . --script res://tests/<file>.gd`. Driver tests run the full game: `"$GODOT" --headless --path . -- --auto=<mode> ...` (note the `--` separator — `--auto=` is a USER arg).
- **Orphan discipline:** before each two-process driver run, kill stragglers: `taskkill //F //IM Godot_v4.4.1-stable_win64_console.exe` (ignore "not found"). Use fresh ports and `>|` to overwrite logs.
- **Before asking the user to playtest a gameplay change, REBUILD the exe** (headless-green source ≠ a runnable build). Build dist zips only via `python godot/package_dist.py`.
- **Commit messages** end with:
  `Co-Authored-By: Claude Opus 4.8 (1M context) <noreply@anthropic.com>`
- **Safety invariant for updates:** nothing destructive happens until the new bytes are downloaded, size-verified, and extracted; a failed update always restores the prior working install.

---

## File Structure

| File | Create/Modify | Responsibility |
|---|---|---|
| `godot/scripts/game/constants.gd` | Modify | Add `GAME_VERSION`. |
| `godot/scripts/net/update_check.gd` | Create | `class_name UpdateCheck` pure statics: semver compare, asset name, JSON parse. |
| `godot/tests/test_version.gd` | Create | Headless unit tests for `UpdateCheck`. |
| `godot/scripts/autoload/game_state.gd` | Modify | `register_player` version param; `reject_join` RPC; `version_override`/`_sent_version`. |
| `godot/scripts/autoload/updater.gd` | Create | `Updater` autoload: check, cleanup, extract, swap, download, relaunch. |
| `godot/project.godot` | Modify | Register the `Updater` autoload. |
| `godot/scripts/ui/menu.gd` | Modify | Version label + update banner. |
| `godot/tests/auto_driver.gd` | Modify | `host-idle`, `join-badversion`, `update-dryrun` modes + helpers. |
| `godot/export_presets.cfg` | Modify | Keep version metadata in sync (cosmetic). |
| `godot/README.md` | Modify | Document the new test commands + version-bump discipline. |

**Note on `main.gd`:** the spec mentioned a startup cleanup call in `main.gd`. We instead run cleanup in `Updater._ready()` (an autoload `_ready` runs at startup, before the main scene, with no extra coupling). `main.gd` is left untouched. This is a deliberate, strictly-simpler deviation.

---

### Task 1: Version constant + `UpdateCheck` statics + unit tests

**Files:**
- Modify: `godot/scripts/game/constants.gd`
- Create: `godot/scripts/net/update_check.gd`
- Create: `godot/tests/test_version.gd`

**Interfaces:**
- Produces:
  - `GameConfig.GAME_VERSION : String` (`"2.1.0"`).
  - `UpdateCheck.normalize(v: String) -> String`
  - `UpdateCheck.is_newer(remote: String, local: String) -> bool`
  - `UpdateCheck.asset_name_for_platform() -> String`
  - `UpdateCheck.parse_latest(json: Dictionary) -> Dictionary` → `{version, notes_url, asset_url, asset_size}` or `{}`.

- [ ] **Step 1: Add the version constant**

In `godot/scripts/game/constants.gd`, after `const MAP_HEIGHT := 1080` (line ~5), add:

```gdscript
## The running game version — single source of truth for the menu label, the
## host-authoritative join gate, and the auto-update check. BUMP THIS every
## release (and keep export_presets.cfg's version fields in sync). A forgotten
## bump makes the new build reject same-release joiners.
const GAME_VERSION := "2.1.0"
```

- [ ] **Step 2: Write the `UpdateCheck` util**

Create `godot/scripts/net/update_check.gd`:

```gdscript
class_name UpdateCheck
## Pure, autoload-free helpers for the self-update flow. Kept separate from the
## Updater autoload so they're unit-testable under the --script headless harness
## (autoloads are NOT loaded there).

## Strip a leading "v" and surrounding whitespace from a release tag / version.
static func normalize(v: String) -> String:
	var s := v.strip_edges()
	if s.begins_with("v") or s.begins_with("V"):
		s = s.substr(1)
	return s

## True iff `remote` is a strictly-higher dotted version than `local`. Missing
## trailing components count as 0 ("2.1" == "2.1.0"); non-numeric components → 0.
static func is_newer(remote: String, local: String) -> bool:
	var a := normalize(remote).split(".")
	var b := normalize(local).split(".")
	var n := maxi(a.size(), b.size())
	for i in n:
		var ai := int(a[i]) if i < a.size() else 0
		var bi := int(b[i]) if i < b.size() else 0
		if ai != bi:
			return ai > bi
	return false

## The release-asset filename for the platform we're running on (desktop only).
static func asset_name_for_platform() -> String:
	if OS.has_feature("windows"):
		return "Slippington-Windows.zip"
	if OS.has_feature("macos"):
		return "Slippington-macOS.zip"
	return ""

## Pull the fields we need out of GitHub's /releases/latest JSON. Returns {}
## when the JSON is malformed or carries no asset for this platform.
## Shape: {version, notes_url, asset_url, asset_size}.
static func parse_latest(json: Dictionary) -> Dictionary:
	var tag := str(json.get("tag_name", ""))
	if tag == "":
		return {}
	var want := asset_name_for_platform()
	var assets: Array = json.get("assets", [])
	for a in assets:
		if str(a.get("name", "")) == want:
			return {
				"version": normalize(tag),
				"notes_url": str(json.get("html_url", "")),
				"asset_url": str(a.get("browser_download_url", "")),
				"asset_size": int(a.get("size", 0)),
			}
	return {}
```

- [ ] **Step 3: Write the failing unit tests**

Create `godot/tests/test_version.gd` (mirrors `test_elements.gd`'s SceneTree pattern):

```gdscript
extends SceneTree
## Version / update-check unit tests (headless):
##   godot --headless --path . --script res://tests/test_version.gd
## Exercises the autoload-free UpdateCheck statics only.

func _init() -> void:
	var failures := 0
	failures += _check("is_newer: patch up", UpdateCheck.is_newer("2.1.1", "2.1.0"))
	failures += _check("is_newer: minor up", UpdateCheck.is_newer("2.2.0", "2.1.0"))
	failures += _check("is_newer: major up", UpdateCheck.is_newer("3.0.0", "2.9.9"))
	failures += _check("is_newer: two-digit minor", UpdateCheck.is_newer("2.10.0", "2.9.0"))
	failures += _check("is_newer: equal is not newer", not UpdateCheck.is_newer("2.1.0", "2.1.0"))
	failures += _check("is_newer: older is not newer", not UpdateCheck.is_newer("2.0.9", "2.1.0"))
	failures += _check("is_newer: short == long", not UpdateCheck.is_newer("2.1", "2.1.0"))
	failures += _check("is_newer: longer wins", UpdateCheck.is_newer("2.1.1", "2.1"))
	failures += _check("is_newer: leading v tolerated", UpdateCheck.is_newer("v2.2.0", "v2.1.0"))
	failures += _check("normalize strips v", UpdateCheck.normalize(" v2.1.0 ") == "2.1.0")
	failures += _check("asset name non-empty on desktop", UpdateCheck.asset_name_for_platform() != "")
	failures += _check("parse_latest extracts fields", _test_parse_ok())
	failures += _check("parse_latest empty on no asset", _test_parse_no_asset())
	if failures > 0:
		print("FAILED: %d test(s)" % failures); quit(1); return
	print("DONE: version ok"); quit(0)

func _check(name: String, ok: bool) -> int:
	print(("PASS " if ok else "FAIL ") + name)
	return 0 if ok else 1

# A sample GitHub response carrying BOTH platform assets, so the test passes on
# whichever OS runs it (asset_name_for_platform picks the host's).
func _sample() -> Dictionary:
	return {
		"tag_name": "v2.2.0",
		"html_url": "https://github.com/ShawnLi14/slippington/releases/tag/v2.2.0",
		"assets": [
			{"name": "Slippington-Windows.zip", "browser_download_url": "https://example/win.zip", "size": 123},
			{"name": "Slippington-macOS.zip", "browser_download_url": "https://example/mac.zip", "size": 456},
		],
	}

func _test_parse_ok() -> bool:
	var info := UpdateCheck.parse_latest(_sample())
	return info.get("version", "") == "2.2.0" \
		and info.get("notes_url", "").contains("releases/tag/v2.2.0") \
		and info.get("asset_url", "") != "" \
		and int(info.get("asset_size", 0)) > 0

func _test_parse_no_asset() -> bool:
	var j := _sample()
	j["assets"] = [{"name": "Something-Else.zip", "browser_download_url": "x", "size": 1}]
	return UpdateCheck.parse_latest(j).is_empty()
```

- [ ] **Step 4: Run tests**

From `godot/`:
```
"$GODOT" --headless --path . --script res://tests/test_version.gd
```
Expected: every line `PASS …`, then `DONE: version ok`, exit 0.

- [ ] **Step 5: Commit**

```bash
git add godot/scripts/game/constants.gd godot/scripts/net/update_check.gd godot/tests/test_version.gd
git commit -m "Version: GAME_VERSION constant + UpdateCheck statics + unit tests

Co-Authored-By: Claude Opus 4.8 (1M context) <noreply@anthropic.com>"
```

---

### Task 2: Host-authoritative version gate + mismatch driver test

**Files:**
- Modify: `godot/scripts/autoload/game_state.gd` (`register_player` ~151, `enter_lobby` ~88)
- Modify: `godot/tests/auto_driver.gd`

**Interfaces:**
- Consumes: `GameConfig.GAME_VERSION` (Task 1).
- Produces:
  - `GameState.version_override : String` (test-only; empty in normal play)
  - `GameState._sent_version() -> String`
  - `register_player(p_name, class_id, version)` (new 3rd param)
  - `reject_join(host_version: String)` RPC
  - driver modes `host-idle`, `join-badversion` (+ `--force-version=` arg).

- [ ] **Step 1: Add the driver modes (the failing integration test)**

In `godot/tests/auto_driver.gd`:

(a) Add a field near the other arg fields (after `var rounds_arg := 1`, ~line 28):
```gdscript
var forced_version := ""
```

(b) In the arg-parse loop (after the `--rounds=` branch, ~line 76), add:
```gdscript
		elif arg.begins_with("--force-version="):
			forced_version = arg.trim_prefix("--force-version=")
```

(c) Immediately AFTER the arg-parse `for` loop ends and BEFORE `var is_host := mode.begins_with("host")`, apply the override:
```gdscript
	if forced_version != "":
		GameState.version_override = forced_version
```

(d) In the `_checks` setup chain, add two branches BEFORE the final `else:` (i.e., after the `host-swap/join-swap` block, ~line 106):
```gdscript
	elif mode == "host-idle":
		# Minimal reject-capable host for the version-gate test: just stays up.
		_checks = {}
		timeout_sec = 12.0
	elif mode == "join-badversion":
		# Joins with a deliberately-wrong version; must be bounced to the menu.
		_checks = {"got_rejected": false}
		timeout_sec = 20.0
```

(e) Where the generic session-failed→fail handler is wired (`elif mode != "join-bad-online":`, ~line 144), also exclude the new mode:
```gdscript
	elif mode != "join-bad-online" and mode != "join-badversion":
		NetworkManager.session_failed.connect(func(reason): _fail("session failed: " + reason))
```

(f) Right after that block (before `GameState.players_changed.connect(_on_players_changed)`, ~line 147), add the rejection listener:
```gdscript
	if mode == "join-badversion":
		GameState.status_message.connect(func(text: String):
			if "Version mismatch" in text:
				_pass("got_rejected")
				_finish()
		)
```

(g) Guard the host auto-start so `host-idle` never launches a match. In `_on_players_changed` (~line 391), change:
```gdscript
	if mode.begins_with("host") and GameState.phase == GameState.Phase.LOBBY \
```
to:
```gdscript
	if mode.begins_with("host") and mode != "host-idle" and GameState.phase == GameState.Phase.LOBBY \
```

(h) In the `match mode:` dispatch (~line 304), add cases next to `"host", "host-swap"`:
```gdscript
		"host-idle":
			NetworkManager.host_lan(port)
		"join-badversion":
			await get_tree().create_timer(1.5).timeout
			NetworkManager.join_lan("127.0.0.1", port)
```

- [ ] **Step 2: Run the test RED (gate not implemented yet)**

This step requires the `register_player` 3rd param to exist or the RPC arg count mismatches. So first add ONLY the plumbing that SENDS the version, without the reject logic, in `game_state.gd`:

After `var local_class_id := "slipper"` (~line 27) add:
```gdscript
## Test-only override for the version sent on join (empty = use GAME_VERSION).
var version_override := ""
```

Add a helper (near `local_id()`, ~line 74):
```gdscript
func _sent_version() -> String:
	return version_override if version_override != "" else GameConfig.GAME_VERSION
```

In `enter_lobby()` (~line 94), change the joiner branch:
```gdscript
		register_player.rpc_id(1, local_name, local_class_id, _sent_version())
```

Change `register_player` signature ONLY (no reject yet), ~line 151:
```gdscript
@rpc("any_peer", "call_remote", "reliable")
func register_player(p_name: String, class_id: String, version: String) -> void:
	if not is_host():
		return
	_host_add_player(multiplayer.get_remote_sender_id(), p_name, class_id)
```

Now run (from `godot/`, two terminals or background; kill orphans first):
```
"$GODOT" --headless --path . -- --auto=host-idle --port=7811
"$GODOT" --headless --path . -- --auto=join-badversion --port=7811 --force-version=9.9.9
```
Expected: `join-badversion` connects, reaches the lobby (no reject), never sees a mismatch message, times out → `FAILED CHECKS: got_rejected`, exit 1. **This is the expected RED** (the joiner is wrongly admitted).

- [ ] **Step 3: Implement the gate (make it pass)**

In `game_state.gd`, replace `register_player` with the gated version:
```gdscript
@rpc("any_peer", "call_remote", "reliable")
func register_player(p_name: String, class_id: String, version: String) -> void:
	if not is_host():
		return
	if version != GameConfig.GAME_VERSION:
		reject_join.rpc_id(multiplayer.get_remote_sender_id(), GameConfig.GAME_VERSION)
		return
	_host_add_player(multiplayer.get_remote_sender_id(), p_name, class_id)
```

Add the reject RPC immediately after `register_player`:
```gdscript
## Host → a rejected joiner: versions differ. The joiner leaves and shows why.
@rpc("authority", "call_remote", "reliable")
func reject_join(host_version: String) -> void:
	NetworkManager.leave()
	reset_to_menu("Version mismatch — host is on v%s, you're on v%s. "
		% [host_version, _sent_version()]
		+ "Both must run the same version. Update from the menu.")
```

- [ ] **Step 4: Run the test GREEN**

Kill orphans, then:
```
"$GODOT" --headless --path . -- --auto=host-idle --port=7812
"$GODOT" --headless --path . -- --auto=join-badversion --port=7812 --force-version=9.9.9
```
Expected: `[bot join-badversion] PASS got_rejected` then `ALL CHECKS PASSED`, exit 0. (`host-idle` exits 0 at its 12s timeout.)

- [ ] **Step 5: Regression — matching versions still connect**

Kill orphans, then run the existing integration test (both on the real version):
```
"$GODOT" --headless --path . -- --auto=host --port=7813 --match-seconds=8
"$GODOT" --headless --path . -- --auto=join --port=7813
```
Expected: both print `ALL CHECKS PASSED`, exit 0 (roster syncs, match plays) — proving the new `version` param didn't break the normal join.

- [ ] **Step 6: Commit**

```bash
git add godot/scripts/autoload/game_state.gd godot/tests/auto_driver.gd
git commit -m "Join gate: reject version-mismatched joiners (host-authoritative, exact match)

Co-Authored-By: Claude Opus 4.8 (1M context) <noreply@anthropic.com>"
```

---

### Task 3: `Updater` autoload — version check + leftover cleanup

**Files:**
- Create: `godot/scripts/autoload/updater.gd`
- Modify: `godot/project.godot` (`[autoload]`)

**Interfaces:**
- Consumes: `UpdateCheck.*`, `GameConfig.GAME_VERSION`.
- Produces (on the `Updater` autoload):
  - signal `update_available(info: Dictionary)`
  - `var available_update: Dictionary` (last found this launch; `{}` if none)
  - `check_for_update() -> void`
  - `cleanup_leftovers(dir: String) -> void`
  - `_install_dir() -> String`, `_rm_rf(path: String) -> void` (used by later tasks).

- [ ] **Step 1: Create the autoload**

Create `godot/scripts/autoload/updater.gd`:

```gdscript
extends Node
## Updater autoload. On desktop, checks GitHub Releases for a newer build,
## surfaces it to the menu, and (on request — see Task 5) downloads + swaps +
## relaunches. Disabled on web (always served fresh). Pure version/parse logic
## lives in UpdateCheck; this node owns HTTP, filesystem, and process control.

const RELEASES_API := "https://api.github.com/repos/ShawnLi14/slippington/releases/latest"
const USER_AGENT := "Slippington-Updater"

## Emitted when a strictly-newer release exists. info = {version, notes_url,
## asset_url, asset_size}.
signal update_available(info: Dictionary)

## The newest update found this launch ({} if none / not yet known). The menu
## reads this when it builds AND listens to update_available for late arrival.
var available_update: Dictionary = {}

var _http: HTTPRequest


func _ready() -> void:
	cleanup_leftovers(_install_dir())
	if OS.has_feature("web"):
		return
	# Headless test/driver runs pass --auto=... ; don't hit the network there.
	for arg in OS.get_cmdline_user_args():
		if arg.begins_with("--auto="):
			return
	check_for_update()


## Query GitHub for the latest release; emit update_available if it's newer.
func check_for_update() -> void:
	_http = HTTPRequest.new()
	add_child(_http)
	_http.request_completed.connect(_on_check_completed)
	var headers := ["Accept: application/vnd.github+json", "User-Agent: " + USER_AGENT]
	if _http.request(RELEASES_API, headers) != OK:
		_http.queue_free()


func _on_check_completed(result: int, code: int, _headers: PackedStringArray, body: PackedByteArray) -> void:
	_http.queue_free()
	if result != HTTPRequest.RESULT_SUCCESS or code != 200:
		return
	var json: Variant = JSON.parse_string(body.get_string_from_utf8())
	if typeof(json) != TYPE_DICTIONARY:
		return
	var info := UpdateCheck.parse_latest(json)
	if info.is_empty():
		return
	if not UpdateCheck.is_newer(info["version"], GameConfig.GAME_VERSION):
		return
	available_update = info
	update_available.emit(info)


## Delete *.old leftovers a previous successful self-update left behind.
func cleanup_leftovers(dir: String) -> void:
	for name in ["Slippington.old.exe", "Slippington.console.old.exe"]:
		var p := dir.path_join(name)
		if FileAccess.file_exists(p):
			DirAccess.remove_absolute(p)
	var app_old := dir.path_join("Slippington.app.old")
	if DirAccess.dir_exists_absolute(app_old):
		if OS.has_feature("macos"):
			OS.execute("rm", ["-rf", app_old])  # robust for .app bundles (symlinks)
		else:
			_rm_rf(app_old)


func _install_dir() -> String:
	return OS.get_executable_path().get_base_dir()


## Recursively delete a directory tree (best-effort).
func _rm_rf(path: String) -> void:
	var d := DirAccess.open(path)
	if d == null:
		return
	d.include_hidden = true
	for f in d.get_files():
		d.remove(f)
	for sub in d.get_dirs():
		_rm_rf(path.path_join(sub))
	DirAccess.remove_absolute(path)
```

- [ ] **Step 2: Register the autoload**

In `godot/project.godot`, under `[autoload]` (after the `SoundManager` line, ~line 19), add:
```
Updater="*res://scripts/autoload/updater.gd"
```

- [ ] **Step 3: Verify it loads without breaking existing runs**

Headless map test still passes (proves the project + autoloads parse):
```
"$GODOT" --headless --path . --script res://tests/test_mapgen.gd
```
Expected: `DONE: …` exit 0 (this runs under --script, so the autoload itself isn't loaded — this only confirms nothing in the shared `class_name` graph broke).

Then confirm the autoload itself parses/loads by launching the game headless for a moment with a driver mode that exits fast (reuses Task 2):
```
"$GODOT" --headless --path . -- --auto=host-idle --port=7814
```
Expected: it reaches the lobby and exits 0 at timeout with no script errors mentioning `updater.gd` (the `--auto=` guard means no network call fires).

- [ ] **Step 4: Commit**

```bash
git add godot/scripts/autoload/updater.gd godot/project.godot
git commit -m "Updater: autoload with GitHub version check + leftover cleanup

Co-Authored-By: Claude Opus 4.8 (1M context) <noreply@anthropic.com>"
```

---

### Task 4: `Updater` swap engine — extract, swap, restore (the risky core)

**Files:**
- Modify: `godot/scripts/autoload/updater.gd`
- Modify: `godot/tests/auto_driver.gd` (add `update-dryrun` mode + helpers)

**Interfaces:**
- Consumes: `Updater._install_dir`, `Updater._rm_rf` (Task 3).
- Produces (on `Updater`):
  - `var test_fail_on: String` (test-only injection)
  - `extract_zip(zip_path: String, staging: String) -> bool`
  - `apply_windows_swap(install_dir: String, staging: String) -> bool`
  - `apply_macos_swap(install_dir: String, staging: String) -> bool`
  - `install_from_zip(zip_path: String, install_dir: String) -> bool`
  - driver mode `update-dryrun`.

- [ ] **Step 1: Write the failing dryrun test**

In `godot/tests/auto_driver.gd`, add an early dispatch in `_ready` — place it right after the `if forced_version != "":` block from Task 2 and before `var is_host := …`:
```gdscript
	if mode == "update-dryrun":
		_run_update_dryrun()
		return
```

Add these methods at the end of the file (after `_finish`):
```gdscript
# --- update-dryrun: exercises Updater's swap engine on scratch dirs ----------
# Both Windows and macOS swap logic are pure path-ops, so BOTH are testable on
# any host OS (chmod is best-effort and no-ops off macOS).

func _put(path: String, text: String) -> void:
	var f := FileAccess.open(path, FileAccess.WRITE)
	f.store_string(text)
	f.close()

func _read(path: String) -> String:
	if not FileAccess.file_exists(path):
		return ""
	return FileAccess.get_file_as_string(path)

func _rm_tree(path: String) -> void:
	var d := DirAccess.open(path)
	if d == null:
		return
	d.include_hidden = true
	for f in d.get_files():
		d.remove(f)
	for sub in d.get_dirs():
		_rm_tree(path.path_join(sub))
	DirAccess.remove_absolute(path)

func _make_zip(zip_path: String, entries: Dictionary) -> void:
	var packer := ZIPPacker.new()
	packer.open(zip_path)
	for name in entries:
		packer.start_file(name)
		packer.write_file((entries[name] as String).to_utf8_buffer())
		packer.close_file()
	packer.close()

func _run_update_dryrun() -> void:
	var fails := 0
	var root := OS.get_cache_dir().path_join("slip_dryrun")
	_rm_tree(root)
	DirAccess.make_dir_recursive_absolute(root)

	# 1) cleanup_leftovers removes *.old artifacts.
	var c := root.path_join("cleanup")
	DirAccess.make_dir_recursive_absolute(c.path_join("Slippington.app.old"))
	_put(c.path_join("Slippington.old.exe"), "x")
	_put(c.path_join("Slippington.console.old.exe"), "x")
	_put(c.path_join("Slippington.app.old").path_join("f"), "x")
	Updater.cleanup_leftovers(c)
	if FileAccess.file_exists(c.path_join("Slippington.old.exe")) \
			or FileAccess.file_exists(c.path_join("Slippington.console.old.exe")) \
			or DirAccess.dir_exists_absolute(c.path_join("Slippington.app.old")):
		print("FAIL dryrun: leftovers not cleaned"); fails += 1
	else:
		print("PASS dryrun: leftovers cleaned")

	# 2) Windows swap happy path via install_from_zip(fixture).
	var w := root.path_join("win")
	DirAccess.make_dir_recursive_absolute(w)
	_put(w.path_join("Slippington.exe"), "OLDEXE")
	_put(w.path_join("Slippington.console.exe"), "OLDCON")
	var zip := root.path_join("fixture-win.zip")
	_make_zip(zip, {"Slippington.exe": "NEWEXE", "Slippington.console.exe": "NEWCON", "HOW_TO_PLAY.txt": "ignore me"})
	Updater.test_fail_on = ""
	if Updater.install_from_zip(zip, w) \
			and _read(w.path_join("Slippington.exe")) == "NEWEXE" \
			and _read(w.path_join("Slippington.console.exe")) == "NEWCON" \
			and _read(w.path_join("Slippington.old.exe")) == "OLDEXE":
		print("PASS dryrun: windows swap + backup")
	else:
		print("FAIL dryrun: windows swap"); fails += 1

	# 3) Windows restore-on-failure (inject a mid-swap failure on the 2nd file).
	var wr := root.path_join("winr")
	var st := wr.path_join(".stage")
	DirAccess.make_dir_recursive_absolute(st)
	_put(wr.path_join("Slippington.exe"), "OLDEXE")
	_put(wr.path_join("Slippington.console.exe"), "OLDCON")
	_put(st.path_join("Slippington.exe"), "NEWEXE")
	_put(st.path_join("Slippington.console.exe"), "NEWCON")
	Updater.test_fail_on = "Slippington.console.exe"
	var w_ok := Updater.apply_windows_swap(wr, st)
	Updater.test_fail_on = ""
	if not w_ok \
			and _read(wr.path_join("Slippington.exe")) == "OLDEXE" \
			and _read(wr.path_join("Slippington.console.exe")) == "OLDCON" \
			and not FileAccess.file_exists(wr.path_join("Slippington.old.exe")):
		print("PASS dryrun: windows restore-on-failure")
	else:
		print("FAIL dryrun: windows restore"); fails += 1

	# 4) macOS swap happy path (call apply_macos_swap directly).
	var m := root.path_join("mac")
	var m_inner := "Slippington.app/Contents/MacOS/Slippington"
	var ms := m.path_join(".stage")
	DirAccess.make_dir_recursive_absolute(m.path_join("Slippington.app/Contents/MacOS"))
	DirAccess.make_dir_recursive_absolute(ms.path_join("Slippington.app/Contents/MacOS"))
	_put(m.path_join(m_inner), "OLDAPP")
	_put(ms.path_join(m_inner), "NEWAPP")
	Updater.test_fail_on = ""
	if Updater.apply_macos_swap(m, ms) \
			and _read(m.path_join(m_inner)) == "NEWAPP" \
			and _read(m.path_join("Slippington.app.old/Contents/MacOS/Slippington")) == "OLDAPP":
		print("PASS dryrun: macos swap + backup")
	else:
		print("FAIL dryrun: macos swap"); fails += 1

	# 5) macOS restore-on-failure.
	var mr := root.path_join("macr")
	var mrs := mr.path_join(".stage")
	DirAccess.make_dir_recursive_absolute(mr.path_join("Slippington.app/Contents/MacOS"))
	DirAccess.make_dir_recursive_absolute(mrs.path_join("Slippington.app/Contents/MacOS"))
	_put(mr.path_join(m_inner), "OLDAPP")
	_put(mrs.path_join(m_inner), "NEWAPP")
	Updater.test_fail_on = "macos"
	var m_ok := Updater.apply_macos_swap(mr, mrs)
	Updater.test_fail_on = ""
	if not m_ok and _read(mr.path_join(m_inner)) == "OLDAPP":
		print("PASS dryrun: macos restore-on-failure")
	else:
		print("FAIL dryrun: macos restore"); fails += 1

	_rm_tree(root)
	if fails == 0:
		print("[bot update-dryrun] ALL CHECKS PASSED"); get_tree().quit(0)
	else:
		print("[bot update-dryrun] FAILED: %d" % fails); get_tree().quit(1)
```

- [ ] **Step 2: Run RED**

```
"$GODOT" --headless --path . -- --auto=update-dryrun
```
Expected: a parse/runtime error or FAIL — `Updater` has no `test_fail_on`/`install_from_zip`/`apply_*`/`extract_zip` yet. **This is the RED.**

- [ ] **Step 3: Implement the swap engine**

Append to `godot/scripts/autoload/updater.gd`:

```gdscript
# --- self-replace engine ------------------------------------------------------

## Test-only: set to a basename ("Slippington.console.exe") or "macos" to force
## a mid-swap failure and exercise the restore path. Empty in normal play.
var test_fail_on := ""


## Extract the platform's new binaries from a release zip into `staging` (created
## fresh). Windows: the exe(s), flat. macOS: the whole Slippington.app/ subtree.
func extract_zip(zip_path: String, staging: String) -> bool:
	var reader := ZIPReader.new()
	if reader.open(zip_path) != OK:
		return false
	DirAccess.make_dir_recursive_absolute(staging)
	var got := false
	for n in reader.get_files():
		if n.ends_with("/"):
			continue
		if OS.has_feature("macos"):
			if not n.begins_with("Slippington.app/"):
				continue
			var out := staging.path_join(n)
			DirAccess.make_dir_recursive_absolute(out.get_base_dir())
			_write_bytes(out, reader.read_file(n))
			got = true
		else:
			var base := n.get_file()
			if base == "Slippington.exe" or base == "Slippington.console.exe":
				_write_bytes(staging.path_join(base), reader.read_file(n))
				got = true
	reader.close()
	return got


func _write_bytes(path: String, data: PackedByteArray) -> void:
	var f := FileAccess.open(path, FileAccess.WRITE)
	f.store_buffer(data)
	f.close()


## Replace the installed Windows exe(s) with the staged ones. On any failure,
## restores from the .old backups and returns false (install left unchanged).
func apply_windows_swap(install_dir: String, staging: String) -> bool:
	var renamed: Array = []   # [[orig, old]] to undo renames on failure
	var written: Array = []   # [orig] new files written so far
	for base in ["Slippington.exe", "Slippington.console.exe"]:
		var staged := staging.path_join(base)
		if not FileAccess.file_exists(staged):
			continue
		var orig := install_dir.path_join(base)
		var old := install_dir.path_join(base.replace(".exe", ".old.exe"))
		if FileAccess.file_exists(orig):
			if DirAccess.rename_absolute(orig, old) != OK:
				_restore_windows(renamed, written); return false
			renamed.append([orig, old])
		if base == test_fail_on or DirAccess.copy_absolute(staged, orig) != OK:
			_restore_windows(renamed, written); return false
		written.append(orig)
	return true


func _restore_windows(renamed: Array, written: Array) -> void:
	for orig in written:
		DirAccess.remove_absolute(orig)
	for pair in renamed:
		DirAccess.rename_absolute(pair[1], pair[0])


## Replace the installed Slippington.app with the staged one (chmod +x the inner
## binary; best-effort). On failure, restores the backup and returns false.
func apply_macos_swap(install_dir: String, staging: String) -> bool:
	var staged_app := staging.path_join("Slippington.app")
	if not DirAccess.dir_exists_absolute(staged_app):
		return false
	OS.execute("chmod", ["+x", staged_app.path_join("Contents/MacOS/Slippington")])
	var orig := install_dir.path_join("Slippington.app")
	var backup := install_dir.path_join("Slippington.app.old")
	if DirAccess.dir_exists_absolute(backup):
		_rm_rf(backup)
	var had_orig := DirAccess.dir_exists_absolute(orig)
	if had_orig and DirAccess.rename_absolute(orig, backup) != OK:
		return false
	if test_fail_on == "macos" or DirAccess.rename_absolute(staged_app, orig) != OK:
		if had_orig:
			DirAccess.rename_absolute(backup, orig)
		return false
	return true


## Extract `zip_path` and swap it into `install_dir`. Returns true on success
## (the caller may then relaunch). Install is left untouched on any failure.
func install_from_zip(zip_path: String, install_dir: String) -> bool:
	var staging := install_dir.path_join(".slip_update")
	_rm_rf(staging)
	if not extract_zip(zip_path, staging):
		_rm_rf(staging); return false
	var ok: bool
	if OS.has_feature("macos"):
		ok = apply_macos_swap(install_dir, staging)
	else:
		ok = apply_windows_swap(install_dir, staging)
	_rm_rf(staging)
	return ok
```

- [ ] **Step 4: Run GREEN**

```
"$GODOT" --headless --path . -- --auto=update-dryrun
```
Expected: five `PASS dryrun: …` lines then `[bot update-dryrun] ALL CHECKS PASSED`, exit 0.

- [ ] **Step 5: Commit**

```bash
git add godot/scripts/autoload/updater.gd godot/tests/auto_driver.gd
git commit -m "Updater: extract + platform swap + restore-on-failure (dryrun-tested)

Co-Authored-By: Claude Opus 4.8 (1M context) <noreply@anthropic.com>"
```

---

### Task 5: `Updater` download orchestration + write probe + relaunch

**Files:**
- Modify: `godot/scripts/autoload/updater.gd`
- Modify: `godot/tests/auto_driver.gd` (extend `update-dryrun` with a write-probe check)

**Interfaces:**
- Consumes: `Updater.install_from_zip`, `Updater._install_dir` (Task 4/3).
- Produces (on `Updater`):
  - signal `update_progress(downloaded: int, total: int)`
  - signal `update_failed(message: String)`
  - `begin_update(asset_url: String, asset_size: int) -> void`
  - `_dir_writable(dir: String) -> bool`.

- [ ] **Step 1: Add the write-probe assertion to the dryrun (RED)**

In `_run_update_dryrun()` (in `auto_driver.gd`), insert before the final `_rm_tree(root)` line:
```gdscript
	# 6) write probe: true for a writable dir, false for a bogus one.
	if Updater._dir_writable(root) and not Updater._dir_writable("Z:/slip_nope/never"):
		print("PASS dryrun: write probe")
	else:
		print("FAIL dryrun: write probe"); fails += 1
```

Run RED:
```
"$GODOT" --headless --path . -- --auto=update-dryrun
```
Expected: error/FAIL — `_dir_writable` doesn't exist yet.

- [ ] **Step 2: Implement download orchestration**

Append to `godot/scripts/autoload/updater.gd`:

```gdscript
# --- download + relaunch ------------------------------------------------------

## Streams the download while active so the menu can show progress.
signal update_progress(downloaded: int, total: int)
## Update could not be applied; install is unchanged. The menu shows `message`
## and a manual-download fallback.
signal update_failed(message: String)

var _dl: HTTPRequest
var _expected_size := 0
var _zip_path := ""


## User pressed "Update Now": pre-flight, download, install, relaunch.
func begin_update(asset_url: String, asset_size: int) -> void:
	var install := _install_dir()
	if not _dir_writable(install):
		update_failed.emit("Can't write to the install folder — download the update manually.")
		return
	_expected_size = asset_size
	_zip_path = OS.get_cache_dir().path_join("Slippington-update.zip")
	_dl = HTTPRequest.new()
	add_child(_dl)
	_dl.download_file = _zip_path
	_dl.request_completed.connect(_on_download_completed)
	if _dl.request(asset_url, ["User-Agent: " + USER_AGENT]) != OK:
		_dl.queue_free()
		_dl = null
		update_failed.emit("Couldn't start the download.")


func _process(_delta: float) -> void:
	if _dl != null and _dl.get_http_client_status() == HTTPClient.STATUS_BODY:
		update_progress.emit(_dl.get_downloaded_bytes(), _dl.get_body_size())


func _on_download_completed(result: int, code: int, _headers: PackedStringArray, _body: PackedByteArray) -> void:
	_dl.queue_free()
	_dl = null
	if result != HTTPRequest.RESULT_SUCCESS or code != 200:
		update_failed.emit("Download failed (HTTP %d) — try again or download manually." % code)
		return
	var f := FileAccess.open(_zip_path, FileAccess.READ)
	var got := int(f.get_length()) if f != null else 0
	if f != null:
		f.close()
	if _expected_size > 0 and got != _expected_size:
		update_failed.emit("Download was incomplete — try again.")
		return
	if not install_from_zip(_zip_path, _install_dir()):
		update_failed.emit("Couldn't apply the update — download manually.")
		return
	_relaunch()


## A nonexistent / read-only dir returns false (caught before any swap).
func _dir_writable(dir: String) -> bool:
	var probe := dir.path_join(".slip_write_test")
	var f := FileAccess.open(probe, FileAccess.WRITE)
	if f == null:
		return false
	f.close()
	DirAccess.remove_absolute(probe)
	return true


## Launch the freshly-swapped build and quit this (now-stale) process.
func _relaunch() -> void:
	if OS.has_feature("macos"):
		OS.create_process("/usr/bin/open", [_install_dir().path_join("Slippington.app")])
	else:
		OS.create_process(_install_dir().path_join("Slippington.exe"), [])
	get_tree().quit()
```

- [ ] **Step 3: Run GREEN**

```
"$GODOT" --headless --path . -- --auto=update-dryrun
```
Expected: six `PASS dryrun: …` lines then `ALL CHECKS PASSED`, exit 0.

- [ ] **Step 4: Commit**

```bash
git add godot/scripts/autoload/updater.gd godot/tests/auto_driver.gd
git commit -m "Updater: download orchestration + write probe + relaunch

Co-Authored-By: Claude Opus 4.8 (1M context) <noreply@anthropic.com>"
```

---

### Task 6: Menu — version label + update banner

**Files:**
- Modify: `godot/scripts/ui/menu.gd`
- Modify: `godot/tests/auto_driver.gd` (`shot-update` mode for visual check)

**Interfaces:**
- Consumes: `GameConfig.GAME_VERSION`; `Updater.available_update`, `Updater.update_available`, `Updater.begin_update`, `Updater.update_progress`, `Updater.update_failed`.

- [ ] **Step 1: Add the version label + banner wiring**

In `godot/scripts/ui/menu.gd`, at the END of `_ready()` (after the existing autoload signal connections, ~line 190), add:

```gdscript
	# Version label, pinned bottom-right of the full-rect menu.
	var ver := UiTheme.label("v" + GameConfig.GAME_VERSION, 13, Color(1, 1, 1, 0.45))
	ver.add_theme_color_override("font_outline_color", Color(0.05, 0.06, 0.12, 0.7))
	ver.add_theme_constant_override("outline_size", 3)
	ver.set_anchors_and_offsets_preset(Control.PRESET_BOTTOM_RIGHT)
	ver.offset_left = -120
	ver.offset_top = -34
	ver.offset_right = -12
	ver.offset_bottom = -8
	ver.horizontal_alignment = HORIZONTAL_ALIGNMENT_RIGHT
	add_child(ver)

	# Update banner (desktop). Show now if the check already finished, and also
	# listen for a late arrival. Method connection (not a lambda) so it survives
	# this screen being freed during a scene swap.
	Updater.update_available.connect(_show_update_banner)
	if not Updater.available_update.is_empty():
		_show_update_banner(Updater.available_update)
```

Add these methods to `menu.gd` (after `_set_buttons_disabled`, the last method):

```gdscript
var _update_banner: PanelContainer
var _update_info: Dictionary = {}


func _show_update_banner(info: Dictionary) -> void:
	_update_info = info
	if is_instance_valid(_update_banner):
		_update_banner.queue_free()
	_update_banner = UiTheme.panel()
	_update_banner.set_anchors_and_offsets_preset(Control.PRESET_TOP_WIDE)
	_update_banner.offset_left = 0
	_update_banner.offset_top = 12
	_update_banner.offset_right = 0
	_update_banner.size_flags_horizontal = Control.SIZE_SHRINK_CENTER
	var row := HBoxContainer.new()
	row.alignment = BoxContainer.ALIGNMENT_CENTER
	row.add_theme_constant_override("separation", 12)
	_update_banner.add_child(row)
	row.add_child(UiTheme.label("Update available: v%s" % info.get("version", "?"), 16, UiTheme.INK))
	var now_btn := UiTheme.button("UPDATE NOW", true)
	now_btn.pressed.connect(_on_update_now)
	row.add_child(now_btn)
	var notes_btn := UiTheme.button("RELEASE NOTES")
	notes_btn.pressed.connect(func(): OS.shell_open(str(_update_info.get("notes_url", ""))))
	row.add_child(notes_btn)
	var later_btn := UiTheme.button("LATER")
	later_btn.pressed.connect(func(): _update_banner.visible = false)
	row.add_child(later_btn)
	add_child(_update_banner)


func _on_update_now() -> void:
	for child in _update_banner.get_children():
		child.queue_free()
	var box := VBoxContainer.new()
	box.alignment = BoxContainer.ALIGNMENT_CENTER
	box.add_theme_constant_override("separation", 6)
	_update_banner.add_child(box)
	var status := UiTheme.label("Downloading update…", 15, UiTheme.INK)
	status.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	box.add_child(status)
	Updater.update_progress.connect(func(done: int, total: int):
		if is_instance_valid(status):
			if total > 0:
				status.text = "Downloading update… %d%%" % int(100.0 * done / total)
			else:
				status.text = "Downloading update… %d KB" % int(done / 1024)
	)
	Updater.update_failed.connect(func(message: String):
		if not is_instance_valid(status):
			return
		status.text = message
		var link := UiTheme.button("OPEN DOWNLOAD PAGE")
		link.pressed.connect(func(): OS.shell_open(str(_update_info.get("notes_url", ""))))
		box.add_child(link)
	)
	Updater.begin_update(str(_update_info.get("asset_url", "")), int(_update_info.get("asset_size", 0)))
```

- [ ] **Step 2: Add a `shot-update` driver mode for the visual check**

In `auto_driver.gd`'s `match mode:` dispatch (near `"shot-menu":`, ~line 178), add:
```gdscript
			"shot-update":
				# Inject a fake available update and re-emit so the already-built
				# menu renders its banner, then screenshot.
				Updater.available_update = {
					"version": "9.9.9",
					"notes_url": "https://github.com/ShawnLi14/slippington/releases",
					"asset_url": "https://example/none.zip",
					"asset_size": 1,
				}
				Updater.update_available.emit(Updater.available_update)
				_take_screenshot(1.0)
				return
```

- [ ] **Step 3: Verify the menu still builds (no crash) and the label/banner render**

Version label smoke (menu builds with the new code) — run with a real window so the texture isn't null (omit `--headless`):
```
"$GODOT" --path . -- --auto=shot-menu --code-file=C:/Users/shamb/AppData/Local/Temp/claude/shot-menu.png
```
Expected: `[bot] screenshot saved`, exit 0, no script errors. Open the PNG: a dim `v2.1.0` sits in the bottom-right.

Banner smoke:
```
"$GODOT" --path . -- --auto=shot-update --code-file=C:/Users/shamb/AppData/Local/Temp/claude/shot-update.png
```
Expected: exit 0; PNG shows the "Update available: v9.9.9" banner with UPDATE NOW / RELEASE NOTES / LATER.

- [ ] **Step 4: Commit**

```bash
git add godot/scripts/ui/menu.gd godot/tests/auto_driver.gd
git commit -m "Menu: version label + update-available banner (Update Now / Notes / Later)

Co-Authored-By: Claude Opus 4.8 (1M context) <noreply@anthropic.com>"
```

---

### Task 7: Release discipline — preset sync, docs, version-bump checklist

**Files:**
- Modify: `godot/export_presets.cfg`
- Modify: `godot/README.md`

**Interfaces:** none (docs/config only).

- [ ] **Step 1: Sync the macOS preset version metadata to the current version**

In `godot/export_presets.cfg`, set the macOS preset fields (lines ~78–79) to match `GAME_VERSION`:
```
application/short_version="2.1.0"
application/version="2.1.0"
```

- [ ] **Step 2: Document the new tests + the bump discipline in the README**

In `godot/README.md`, under `## Tests`, append:
```markdown

Version / update-check unit tests:

```
godot --headless --path . --script res://tests/test_version.gd
```

Version-gate + auto-update swap-engine driver tests (headless):

```
godot --headless --path . -- --auto=host-idle --port=7811
godot --headless --path . -- --auto=join-badversion --port=7811 --force-version=9.9.9
godot --headless --path . -- --auto=update-dryrun
```

## Releasing — version bump

`GameConfig.GAME_VERSION` (`scripts/game/constants.gd`) is the single source of
truth for the version label, the join gate, and the auto-update check. **Before
every release, bump it** and keep `export_presets.cfg`'s macOS
`application/version` / `application/short_version` in sync. A forgotten bump
makes the new build reject same-release joiners and never see itself as "up to
date". The git tag (`vX.Y.Z`) must match `GAME_VERSION` (`X.Y.Z`).
```

- [ ] **Step 3: Verify the project still exports (presets parse)**

Confirm the edited preset file is still valid by running any headless test (it loads the project):
```
"$GODOT" --headless --path . --script res://tests/test_version.gd
```
Expected: `DONE: version ok`, exit 0.

- [ ] **Step 4: Commit**

```bash
git add godot/export_presets.cfg godot/README.md
git commit -m "Release: sync preset version + document update tests and bump discipline

Co-Authored-By: Claude Opus 4.8 (1M context) <noreply@anthropic.com>"
```

---

## Post-implementation: manual end-to-end (not automatable in CI)

After all tasks pass, the real download+relaunch must be verified by hand (the
dryrun covers swap logic but not the network download or the OS relaunch):

1. Build the Windows export (REBUILD before playtest) and `python godot/package_dist.py`.
2. Temporarily bump `GAME_VERSION` LOWER than the live release (e.g. `2.0.0`) in a throwaway build, run it, and confirm: banner appears → UPDATE NOW → progress → relaunch → menu shows the real latest version. (Or cut a real test release one patch above current.)
3. On a real Mac, repeat for the macOS path (this is the untested-on-dev-hardware path; verify backup/restore by also testing an interrupted download).
4. Verify the join gate live: two builds with different `GAME_VERSION` → the joiner sees the mismatch message and returns to the menu; same version → joins normally.

---

## Self-Review

**Spec coverage:**
- Version source of truth → Task 1 (`GAME_VERSION`). ✓
- Menu version label (bottom-right) → Task 6. ✓
- Host-authoritative exact-match gate + `reject_join` + message → Task 2. ✓
- Cross-version caveat (degrades to generic failure vs pre-feature builds) → inherent; documented in spec. ✓
- Update check (desktop-only, GitHub API, silent on failure) → Task 3. ✓
- Update banner (Update Now / Later / Release notes) → Task 6. ✓
- Download → extract → swap → relaunch, both platforms → Tasks 4 (swap) + 5 (download/relaunch). ✓
- Defensive `.old` backup + restore + write probe + "never worse off" → Tasks 4/5, dryrun-tested. ✓
- Leftover cleanup at startup → Task 3 (`Updater._ready`; the `main.gd` call was folded in, noted). ✓
- Web disabled → Task 3 (`_ready` early-out); label still shows (Task 6). ✓
- Tests: `UpdateCheck` statics (Task 1), `version-mismatch` driver (Task 2), `update-dryrun` (Tasks 4/5) → all present. ✓
- Release version-bump discipline + preset sync → Task 7. ✓

**Placeholder scan:** No TBD/TODO; every code step shows complete code; every test step shows the command + expected output. ✓

**Type consistency:** `available_update`/`info` are `Dictionary` with keys `version, notes_url, asset_url, asset_size` everywhere (Tasks 1/3/5/6). `test_fail_on : String` used identically in Tasks 4 dryrun and updater. `install_from_zip`, `apply_windows_swap`, `apply_macos_swap`, `extract_zip`, `cleanup_leftovers`, `_dir_writable`, `_install_dir`, `_rm_rf` signatures match between definitions (updater.gd) and call sites (auto_driver.gd). `register_player(p_name, class_id, version)` matches `enter_lobby`'s `rpc_id` call. ✓
