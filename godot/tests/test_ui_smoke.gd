extends SceneTree
## Headless UI smoke test:
##   godot --headless --path . --script res://tests/test_ui_smoke.gd
## Verifies the global Theme is built with the expected control styling and
## that bundled fonts load. Extended in later tasks (bg_art geometry).

func _init() -> void:
	var fails := 0

	# Fonts load
	if UiTheme.FONT_DISPLAY == null:
		print("FAIL: display font did not load"); fails += 1
	if UiTheme.body(600) == null:
		print("FAIL: body font variation did not build"); fails += 1

	# Theme built with the controls we rely on
	var t := UiTheme.build_theme()
	if not (t is Theme):
		print("FAIL: build_theme did not return a Theme"); fails += 1
	else:
		if t.default_font == null:
			print("FAIL: theme has no default font"); fails += 1
		var checks := {"Button": "normal", "LineEdit": "normal", "OptionButton": "normal", "PanelContainer": "panel"}
		for type in checks:
			if not t.has_stylebox(checks[type], type):
				print("FAIL: theme missing %s stylebox for %s" % [checks[type], type]); fails += 1
		for state in ["hover", "pressed", "disabled"]:
			if not t.has_stylebox(state, "Button"):
				print("FAIL: Button missing %s stylebox" % state); fails += 1

	if fails > 0:
		print("FAILED: %d issues" % fails); quit(1)
	else:
		print("DONE: ui smoke ok"); quit(0)
