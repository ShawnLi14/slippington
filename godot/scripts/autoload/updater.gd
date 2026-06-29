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

func _ready() -> void:
	if OS.has_feature("web"):
		return
	cleanup_leftovers(_install_dir())
	# Headless test/driver runs pass --auto=... ; don't hit the network there.
	for arg in OS.get_cmdline_user_args():
		if arg.begins_with("--auto="):
			return
	check_for_update()


## Query GitHub for the latest release; emit update_available if it's newer.
func check_for_update() -> void:
	var http := HTTPRequest.new()
	add_child(http)
	var headers := ["Accept: application/vnd.github+json", "User-Agent: " + USER_AGENT]
	http.request_completed.connect(
		func(result: int, code: int, rheaders: PackedStringArray, body: PackedByteArray):
			_on_check_completed(http, result, code, rheaders, body))
	if http.request(RELEASES_API, headers) != OK:
		http.queue_free()


func _on_check_completed(http: HTTPRequest, result: int, code: int, _headers: PackedStringArray, body: PackedByteArray) -> void:
	http.queue_free()
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


## Delete *.old leftovers a previous successful self-update left behind — but
## ONLY when the corresponding LIVE binary exists. If a swap double-faulted and
## the live binary survives only as its .old backup, reaping it would turn a
## recoverable failure into a permanent brick; leave it for manual recovery.
func cleanup_leftovers(dir: String) -> void:
	var exe_pairs := {
		"Slippington.old.exe": "Slippington.exe",
		"Slippington.console.old.exe": "Slippington.console.exe",
	}
	for old_name in exe_pairs:
		var old_p := dir.path_join(old_name)
		var live_p := dir.path_join(exe_pairs[old_name])
		if FileAccess.file_exists(old_p) and FileAccess.file_exists(live_p):
			DirAccess.remove_absolute(old_p)
	var app_old := dir.path_join("Slippington.app.old")
	var app_live := dir.path_join("Slippington.app")
	if DirAccess.dir_exists_absolute(app_old) and DirAccess.dir_exists_absolute(app_live):
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
	for sub in d.get_directories():
		_rm_rf(path.path_join(sub))
	DirAccess.remove_absolute(path)


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
			if not _write_bytes(out, reader.read_file(n)):
				reader.close()
				return false
			got = true
		else:
			# Windows auto-update swaps only the embedded-PCK executable(s).
			# Sidecar native libs (e.g. the webrtc .dll) are NOT propagated — a
			# release that changes the GDExtension must ship as a manual full-zip
			# download, not via auto-update. See README "Releasing". macOS is
			# unaffected (the whole .app, framework included, is swapped).
			var base := n.get_file()
			if base == "Slippington.exe" or base == "Slippington.console.exe":
				if not _write_bytes(staging.path_join(base), reader.read_file(n)):
					reader.close()
					return false
				got = true
	reader.close()
	return got


func _write_bytes(path: String, data: PackedByteArray) -> bool:
	var f := FileAccess.open(path, FileAccess.WRITE)
	if f == null:
		return false
	f.store_buffer(data)
	f.close()
	return true


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


# --- download + relaunch ------------------------------------------------------

## Streams the download while active so the menu can show progress.
signal update_progress(downloaded: int, total: int)
## Update could not be applied; install is unchanged. The menu shows `message`
## and a manual-download fallback.
signal update_failed(message: String)

var _dl: HTTPRequest
var _expected_size: int = 0
var _zip_path: String = ""


## User pressed "Update Now": pre-flight, download, install, relaunch.
func begin_update(asset_url: String, asset_size: int) -> void:
	if _dl != null:
		return  # a download is already in flight; ignore re-entry
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
	if result != HTTPRequest.RESULT_SUCCESS:
		_fail_download("Network error during download — check your connection and try again.")
		return
	if code != 200:
		_fail_download("Download failed (HTTP %d) — try again or download manually." % code)
		return
	var f := FileAccess.open(_zip_path, FileAccess.READ)
	var got := int(f.get_length()) if f != null else 0
	if f != null:
		f.close()
	# Always size-verify: a 0/unknown expected size means we CAN'T trust the
	# bytes, so we refuse rather than install unverified (safety invariant).
	if _expected_size <= 0 or got != _expected_size:
		_fail_download("Download was incomplete or unverifiable — try again.")
		return
	if not install_from_zip(_zip_path, _install_dir()):
		_fail_download("Couldn't apply the update — download manually.")
		return
	_relaunch()


## Emit a failure message and discard the partial/failed download so stale
## bytes don't pile up in the cache. The install itself was never touched.
func _fail_download(message: String) -> void:
	if _zip_path != "" and FileAccess.file_exists(_zip_path):
		DirAccess.remove_absolute(_zip_path)
	update_failed.emit(message)


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
