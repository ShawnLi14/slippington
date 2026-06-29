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
