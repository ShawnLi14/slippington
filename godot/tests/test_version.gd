extends SceneTree
## Version / update-check unit tests (headless):
##   godot --headless --path . --script res://tests/test_version.gd
## Exercises the autoload-free UpdateCheck statics only.

var UpdateCheck = preload("res://scripts/net/update_check.gd")

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
