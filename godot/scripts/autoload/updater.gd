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
