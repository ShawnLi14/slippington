class_name EndScreen
extends Control
## Post-match results: ranked by least time spent as "it"; whoever held
## the tag at the buzzer is called out. Host can send everyone back to
## the lobby for another round.


func _ready() -> void:
	set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	UiTheme.menu_backdrop(self)

	var center := VBoxContainer.new()
	UiTheme.anchor_rect(center, Control.PRESET_CENTER, Rect2(-330, -300, 660, 600))
	center.add_theme_constant_override("separation", 16)
	add_child(center)

	# Survivor rules: whoever is "it" when time runs out loses; everyone
	# else wins. In a series, survivors bank a point a round.
	var my_id := multiplayer.get_unique_id()
	var i_lost := false
	for r in GameState.results:
		if r["peer_id"] == my_id:
			i_lost = r["was_it_at_end"]
	var is_series: bool = GameState.rounds_total > 1
	if is_series and GameState.series_final:
		var champ_name := "?"
		for r in GameState.results:
			if r["peer_id"] == GameState.series_champion:
				champ_name = r["name"]
		var i_won := GameState.series_champion == my_id
		var title := UiTheme.title("YOU ARE THE CHAMPION!" if i_won else "%s WINS THE SERIES!" % champ_name.to_upper(), 42)
		if not i_won:
			title.add_theme_color_override("font_color", Color.WHITE)
		center.add_child(title)
	elif is_series:
		var round_title := UiTheme.title("ROUND %d / %d" % [GameState.round_number, GameState.rounds_total], 40)
		round_title.add_theme_color_override("font_color", UiTheme.RED if i_lost else UiTheme.TEAL)
		center.add_child(round_title)
		var sub := UiTheme.label("caught! no point this round" if i_lost else "survived — +1 point", 17, Color(1, 1, 1, 0.8))
		sub.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
		center.add_child(sub)
	else:
		var title := UiTheme.title("CAUGHT!" if i_lost else "YOU SURVIVED!", 48)
		if i_lost:
			title.add_theme_color_override("font_color", UiTheme.RED)
		center.add_child(title)

	var panel := UiTheme.panel()
	var list := VBoxContainer.new()
	list.add_theme_constant_override("separation", 10)
	list.custom_minimum_size = Vector2(600, 260)
	panel.add_child(list)
	center.add_child(panel)

	for r in GameState.results:
		var row := HBoxContainer.new()
		row.add_theme_constant_override("separation", 12)
		var swatch := ColorRect.new()
		swatch.color = GameConfig.PLAYER_COLORS[r["color_index"]]
		swatch.custom_minimum_size = Vector2(22, 22)
		row.add_child(swatch)
		var name_text: String = r["name"]
		if r["peer_id"] == my_id:
			name_text += "  — you"
		row.add_child(UiTheme.label(name_text, 20))
		var spacer := Control.new()
		spacer.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		row.add_child(spacer)
		row.add_child(UiTheme.label("%.1fs as IT" % r["time_as_it"], 18, Color(1, 1, 1, 0.6)))
		if GameState.rounds_total > 1:
			var pts: int = GameState.round_points.get(r["peer_id"], 0)
			row.add_child(UiTheme.label("%d pt%s" % [pts, "" if pts == 1 else "s"], 18, UiTheme.TEAL))
		if r["was_it_at_end"]:
			row.add_child(UiTheme.label("CAUGHT", 16, UiTheme.RED))
		else:
			row.add_child(UiTheme.label("SAFE", 16, UiTheme.TEAL))
		list.add_child(row)

	var bottom := HBoxContainer.new()
	bottom.add_theme_constant_override("separation", 12)
	if GameState.rounds_total > 1 and not GameState.series_final:
		var next_label := UiTheme.label("next round starting...", 17, Color(1, 1, 1, 0.7))
		next_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
		bottom.add_child(next_label)
	elif NetworkManager.is_host:
		var again := UiTheme.button("PLAY AGAIN", true)
		again.pressed.connect(func(): GameState.host_return_to_lobby())
		bottom.add_child(again)
	else:
		bottom.add_child(UiTheme.label("Waiting for the host...", 16, Color(1, 1, 1, 0.5)))
	var leave := UiTheme.button("LEAVE")
	leave.pressed.connect(func():
		NetworkManager.leave()
		GameState.reset_to_menu()
	)
	bottom.add_child(leave)
	center.add_child(bottom)
