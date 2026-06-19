class_name UiAnim
## Small reusable tweens for party-feel motion. All are no-ops if the node is
## invalid, so callers don't need guards.

## Staggered fade-in entrance; call with the child index for stagger.
## Fade-only so it is safe inside containers (which manage child positions).
static func entrance(node: CanvasItem, index := 0) -> void:
	if node == null:
		return
	node.modulate.a = 0.0
	node.create_tween().tween_property(node, "modulate:a", 1.0, 0.30).set_delay(0.05 * index)


## Gentle perpetual idle bob + tilt for the title.
static func title_idle(node: Control, tilt_deg := 1.5) -> void:
	if node == null: return
	node.pivot_offset = node.size / 2.0
	node.rotation = deg_to_rad(-tilt_deg)
	var tw := node.create_tween().set_loops().set_trans(Tween.TRANS_SINE).set_ease(Tween.EASE_IN_OUT)
	tw.tween_property(node, "rotation", deg_to_rad(tilt_deg), 2.2)
	tw.tween_property(node, "rotation", deg_to_rad(-tilt_deg), 2.2)
