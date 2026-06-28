# Version Management & Auto-Update — Design

Date: 2026-06-28
Status: Approved (brainstorming) — pending spec review before implementation planning

## Problem

Slippington is distributed as GitHub Release zips (one Windows, one macOS) and has
**no in-code version**. Two gaps follow from that:

1. **Silent version skew.** A friend on an older build can connect to a newer host
   (or vice versa). Behavior diverges (netcode/map-gen changes between releases) with
   no explanation — it just feels broken. There's also no way for a player to *see*
   which version they're running.
2. **Manual updates.** Getting a new release means re-downloading and re-extracting the
   whole zip by hand, every time.

## Goals

- A single source of truth for the game version, shown in the UI.
- Block (with a clear message) a joiner whose version doesn't exactly match the host's.
- In-app notification when a newer release exists, plus one-click **auto-update**
  (download → swap files → relaunch) on **both Windows and macOS**.
- Never leave an install worse off than before an update attempt.

## Non-goals

- Web build: it is always served fresh, so the entire update subsystem is disabled
  there. (The version label can still show; the gate still applies if a web peer joins
  a desktop host, but in practice web and desktop builds are versioned together.)
- Delta/partial updates — we download the full release zip.
- Background/automatic downloads — updating is always an explicit user action.
- Backward compatibility shims so mismatched versions can interoperate — exact-match by design.

## Decisions (from brainstorming)

- **Update mechanism:** full auto-update (download + replace + relaunch), not just a link.
- **Platforms for self-replace:** **both** Windows and macOS.
- **Mismatch rule:** **exact** version-string match required to join.
- **Update trigger:** user-initiated ("Update Now"); the check is automatic but
  downloading/replacing only happens on a click.

---

## Architecture

Four self-contained units:

| Unit | File | Kind | Responsibility |
|---|---|---|---|
| Version constant | `godot/scripts/game/constants.gd` (`GameConfig`) | const | The one version string. |
| Version utilities | `godot/scripts/net/update_check.gd` (`class_name UpdateCheck`) | pure statics | semver compare, platform asset name, latest-release JSON parsing. Autoload-free → headless-testable. |
| Updater | `godot/scripts/autoload/updater.gd` (`Updater` autoload) | Node | HTTPRequest lifecycle (check + download), file swap, leftover cleanup, signals. |
| Join gate | `godot/scripts/autoload/game_state.gd` | RPC | exact-match check on `register_player`; `reject_join` RPC. |

UI touch-points: `menu.gd` (version label + update banner), and `main.gd` (startup
leftover cleanup).

Why an autoload for `Updater`: a download must survive the menu→(anywhere) scene
lifetime, cleanup must run at startup regardless of which screen the user goes to, and it
matches the existing autoload pattern (`NetworkManager`, `GameState`, `SoundManager`).
The *pure* logic lives in `UpdateCheck` (a `class_name` util) precisely because autoloads
are not loaded under the `--script` headless test harness.

---

## Part 1 — Version visibility & mismatch gate

### Source of truth

```gdscript
# constants.gd (GameConfig)
const GAME_VERSION := "2.1.0"   # bump every release; load-bearing (gate + update check)
```

- This drives: the menu label, the join gate, and the update-check comparison.
- The macOS export-preset fields `application/version` / `application/short_version`
  (`export_presets.cfg`) are kept in sync as cosmetic OS metadata — bumped alongside.
- **Release-checklist addition:** bumping `GAME_VERSION` (and the preset fields) is now a
  required pre-release step. A forgotten bump makes the new build reject same-release
  joiners. This goes into the release notes/memory.

### Display

A dim `v2.1.0` label pinned to the **bottom-right corner** of the main menu
(`menu.gd`), using `GameConfig.GAME_VERSION`. Low risk, visible before joining.

### Mismatch gate (host-authoritative, exact match)

Flow today: a joiner connects, then `GameState.enter_lobby()` calls
`register_player.rpc_id(1, name, class_id)`; the host adds it to the roster.

Changes:

- `register_player` gains a `version: String` param. The joiner passes the version from
  `GameState._sent_version()` — which returns `GameConfig.GAME_VERSION` unless a test-only
  `GameState.version_override` string is set (the injection hook the mismatch driver test
  uses; empty in normal play).
- Host handler: if `version != GameConfig.GAME_VERSION`, call
  `reject_join.rpc_id(sender, GameConfig.GAME_VERSION)` and **return without adding** the
  joiner to `players`.
- New RPC on the joiner:

  ```gdscript
  @rpc("authority", "call_remote", "reliable")
  func reject_join(host_version: String) -> void:
      NetworkManager.leave()
      reset_to_menu("Version mismatch — host is on v%s, you're on v%s. "
          "Both must run the same version. Update from the menu."
          % [host_version, GameConfig.GAME_VERSION])
  ```

- The rejected joiner self-leaves. Because it was never added to `players`, the host's
  existing `_on_peer_disconnected` no-ops. The host does **not** force-disconnect (lets the
  reliable RPC arrive first).
- Same code path serves WebRTC and LAN, so both are gated.

**Cross-version caveat:** the friendly message only works when *both* builds carry this
feature (this release onward). Against a pre-feature build, `register_player`'s signature
differs, so the high-level RPC won't match and it degrades to a generic connection
failure. Acceptable; documented.

---

## Part 2 — Auto-update

Entirely skipped when `OS.has_feature("web")`.

### Update check

On main-menu load, `Updater` issues an `HTTPRequest`:

- `GET https://api.github.com/repos/ShawnLi14/slippington/releases/latest`
- Headers: `Accept: application/vnd.github+json`, `User-Agent: Slippington-Updater`
  (GitHub requires a UA). No auth token needed — public repo, 60 req/hr/IP is ample.

Parse (in `UpdateCheck.parse_latest(json) -> Dictionary`):

- `tag_name` (e.g. `"v2.1.0"`) → normalized version (strip leading `v`).
- `html_url` → the release page (for "Release notes" + manual-download fallback).
- `assets[]` → the asset whose `name` matches the running platform
  (`UpdateCheck.asset_name_for_platform()` → `"Slippington-Windows.zip"` /
  `"Slippington-macOS.zip"`) → its `browser_download_url` and `size`.

If `UpdateCheck.is_newer(remote, GAME_VERSION)` is true, emit:

```gdscript
signal update_available(version: String, notes_url: String, asset_url: String, asset_size: int)
```

Any failure (offline, rate-limited, parse error, missing asset) → **silent**; no UI, menu
unaffected.

`UpdateCheck.is_newer(a, b)`: split each on `.`, compare numerically component-by-component,
missing components treated as 0; strictly-greater → true. Pure and unit-tested.

### Update banner (menu)

On `update_available`, `menu.gd` shows a non-blocking banner near the title:

- Text: `Update available: v2.2.0`
- **Update Now** → `Updater.begin_update(asset_url, asset_size)`
- **Later** → dismiss for this session
- **Release notes** → `OS.shell_open(notes_url)`

### Download → swap → relaunch (only on "Update Now")

Phases, with a progress indicator during download:

1. **Pre-flight write probe.** Confirm the install directory (dir of
   `OS.get_executable_path()`) is writable. If not → abort with "couldn't write here —
   download manually" + open `notes_url`. (Catches Program Files / read-only mounts before
   touching anything.)
2. **Download.** `HTTPRequest.download_file = <user temp>/Slippington-update.zip`, request
   `asset_url` (follows GitHub's redirect to `objects.githubusercontent.com`). Show
   `get_downloaded_bytes()` / `asset_size`. On non-200 or size mismatch → abort; **nothing
   on disk has changed yet**; show error + manual link.
3. **Extract.** `ZIPReader.open(zip)`:
   - Windows: read `Slippington.exe` (and `Slippington.console.exe` if present) into a temp
     staging dir.
   - macOS: extract the full `Slippington.app/...` subtree to a temp staging dir, preserving
     relative paths.
   - Extraction failure → abort; install untouched; error + manual link.
4. **Swap (platform-specific, defensive).**
   - **Windows** (install dir = dir of `Slippington.exe`):
     1. Rename running `Slippington.exe` → `Slippington.old.exe` (permitted while running).
     2. Write new `Slippington.exe` from staging. Repeat for `Slippington.console.exe`.
     3. On any write failure: rename `*.old.exe` back (restore), abort + manual link.
     4. On success: `OS.create_process(<new exe>, [])`; `get_tree().quit()`.
   - **macOS** (exe path = `…/Slippington.app/Contents/MacOS/Slippington`; bundle root =
     three dirs up):
     1. In staging, `chmod +x` the inner `Contents/MacOS/Slippington`
        (`OS.execute("chmod", ["+x", inner])`).
     2. Rename current `Slippington.app` → `Slippington.app.old` (permitted while running).
     3. Move staged `Slippington.app` into the install dir.
     4. On failure: move `.app.old` back (restore), abort + manual link.
     5. On success: `OS.create_process("/usr/bin/open", [app_path])`; `get_tree().quit()`.
5. **Leftover cleanup.** At startup (`main.gd._ready` → `Updater.cleanup_leftovers()`),
   delete any `Slippington.old.exe` / `Slippington.console.old.exe` / `Slippington.app.old`
   in the install dir. Wrapped so a still-locked leftover simply retries next launch.

### Safety invariant

Nothing destructive happens until the new bytes are **downloaded, size-verified, and
extracted**. The `.old` backup is the restore path for any swap failure. Net effect: a
failed update always lands back on the previously-working install.

### macOS risk (explicit)

macOS self-replace ships without real-hardware testing from the Windows dev machine. The
backup/restore + extract-before-swap ordering are the mitigations. The macOS path's first
real run will be on a user's Mac; this is called out in the release notes.

---

## Error handling summary

| Failure | Behavior |
|---|---|
| Update check (offline / rate-limited / parse) | Silent. Menu unaffected. |
| Download non-200 / size mismatch | Error toast + "Download manually" (`notes_url`). Install untouched. |
| Extract failure | Same as above. |
| Swap write/move failure | Restore from `.old` backup, then error + manual link. |
| Non-writable install dir | Caught by pre-flight probe → manual link; nothing touched. |
| Leftover `.old` still locked at startup | Skipped silently; retried next launch. |
| Version mismatch on join | Joiner shown the mismatch message, returned to menu. |

---

## Testing

**Headless unit tests** (`godot/tests/test_version.gd`, wired into the existing runner;
pure `UpdateCheck` statics, autoload-free):

- `is_newer`: `2.2.0>2.1.0`, `2.1.0==2.1.0` (false), `2.1.0<2.2.0` (false),
  `2.10.0>2.9.0`, `2.1>2.1.0` (false), `2.1.1>2.1` (true), leading-`v` tolerated.
- `asset_name_for_platform`: returns the right zip name per platform feature.
- `parse_latest`: extracts version/notes_url/asset_url/size from a sample GitHub JSON;
  returns empty on missing asset.

**Driver integration tests** (`godot/tests/auto_driver.gd`, matching existing host/join modes):

- `--auto=version-mismatch`: host on X, joiner forced to Y by setting
  `GameState.version_override` before `enter_lobby()` → assert joiner rejected, message
  shown, returned to menu; a matching-version joiner still reaches the lobby.
- `--auto=update-dryrun`: point `Updater` at a fake zip + a temp install dir in the
  scratchpad → assert backup made, new files in place, restore-on-simulated-failure works,
  and leftover cleanup removes `.old` artifacts. (Exercises swap logic without a real
  download or relaunch.)

**Manual e2e** (the parts CI can't cover): bump to a throwaway version, cut a test release,
run the prior build, confirm banner → Update Now → progress → relaunch → new version shown
— on Windows, and on a real Mac for the macOS path.

---

## Files touched

- `godot/scripts/game/constants.gd` — add `GAME_VERSION`.
- `godot/scripts/net/update_check.gd` — **new** `class_name UpdateCheck` statics.
- `godot/scripts/autoload/updater.gd` — **new** `Updater` autoload.
- `godot/project.godot` — register the `Updater` autoload.
- `godot/scripts/autoload/game_state.gd` — `register_player` version param; `reject_join` RPC.
- `godot/scripts/ui/menu.gd` — version label + update banner.
- `godot/scripts/main.gd` — startup leftover cleanup call.
- `godot/export_presets.cfg` — version metadata in sync.
- `godot/tests/test_version.gd` — **new** unit tests (+ wire into runner).
- `godot/tests/auto_driver.gd` — `version-mismatch` + `update-dryrun` modes.
- Release notes / memory — version-bump discipline.
