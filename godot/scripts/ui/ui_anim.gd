class_name UiAnim
## Small reusable tweens for party-feel motion. All are no-ops if the node is
## invalid, so callers don't need guards.

## Staggered fade + slide-up entrance; call with the child index for stagger.
static func entrance(node: CanvasItem, index := 0) -> void:
	if node == null: return
	node.modulate.a = 0.0
	if node is Control:
		var c := node as Control
		var rest := c.position
		c.position = rest + Vector2(0, 18)
		var tw := c.create_tween().set_parallel(true).set_ease(Tween.EASE_OUT).set_trans(Tween.TRANS_BACK)
		tw.tween_property(c, "position", rest, 0.35).set_delay(0.05 * index)
		tw.tween_property(c, "modulate:a", 1.0, 0.30).set_delay(0.05 * index)
	else:
		node.create_tween().tween_property(node, "modulate:a", 1.0, 0.30)


## Gentle perpetual idle bob + tilt for the title.
static func title_idle(node: Control, tilt_deg := 1.5) -> void:
	if node == null: return
	node.pivot_offset = node.size / 2.0
	node.rotation = deg_to_rad(-tilt_deg)
	var tw := node.create_tween().set_loops().set_trans(Tween.TRANS_SINE).set_ease(Tween.EASE_IN_OUT)
	tw.tween_property(node, "rotation", deg_to_rad(tilt_deg), 2.2)
	tw.tween_property(node, "rotation", deg_to_rad(-tilt_deg), 2.2)


## Hover/press feedback for a button (wire in the screen that owns it).
static func attach_button_feedback(b: Button) -> void:
	if b == null: return
	b.pivot_offset = b.size / 2.0
	b.mouse_entered.connect(func(): _scale_to(b, 1.04))
	b.mouse_exited.connect(func(): _scale_to(b, 1.0))


static func _scale_to(c: Control, s: float) -> void:
	if not is_instance_valid(c): return
	c.pivot_offset = c.size / 2.0
	c.create_tween().set_trans(Tween.TRANS_BACK).set_ease(Tween.EASE_OUT).tween_property(c, "scale", Vector2(s, s), 0.12)
