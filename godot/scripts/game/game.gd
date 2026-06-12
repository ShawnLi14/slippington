class_name Game
extends Node2D
## The in-match world. Every client builds the same map from the shared seed
## and spawns a pawn for every roster entry; each pawn is owned (multiplayer
## authority) by its peer. The host additionally runs a MatchDirector.

var map_data: Dictionary
var _players: Dictionary = {}  # peer_id -> Player node
var _hud: CanvasLayer


func _ready() -> void:
	# Themed, animated backdrop (sky + parallax silhouettes + ambient particles).
	# Sits on its own negative CanvasLayer, so it renders behind the world.
	var bg := GameBackground.new()
	bg.bg_theme = BackgroundThemes.theme_for_seed(GameState.map_seed)
	add_child(bg)

	map_data = MapGenerator.from_seed_or_preset(GameState.map_seed)
	for platform_data in map_data["platforms"]:
		add_child(PlatformBody.create(platform_data))

	_spawn_players()

	if multiplayer.is_server():
		var director := MatchDirector.new()
		director.game = self
		add_child(director)

	_hud = preload("res://scripts/ui/hud.gd").new()
	_hud.game = self
	add_child(_hud)

	GameState.player_left_game.connect(_on_player_left)
	GameState.stunned.connect(_on_local_stunned)
	GameState.swapped.connect(_on_local_swapped)
	GameState.ability_fired.connect(_on_ability_fired)
	GameState.it_changed.connect(_on_it_changed)


func _spawn_players() -> void:
	var spawn_points: Array = map_data["spawn_points"]
	var ids: Array = GameState.players.keys()
	ids.sort()  # same spawn assignment on every client
	for i in ids.size():
		var peer_id: int = ids[i]
		var player := Player.new()
		player.setup(peer_id, GameState.players[peer_id], spawn_points[i % spawn_points.size()])
		add_child(player)
		_players[peer_id] = player


func get_player_node(peer_id: int) -> Player:
	return _players.get(peer_id)


func get_player_nodes() -> Array:
	return _players.values()


func local_player() -> Player:
	return _players.get(multiplayer.get_unique_id())


func _on_player_left(peer_id: int) -> void:
	if _players.has(peer_id):
		_players[peer_id].queue_free()
		_players.erase(peer_id)


func _on_local_stunned(duration: float) -> void:
	var me := local_player()
	if me != null:
		me.apply_stun(duration)


func _on_local_swapped(pos: Vector2) -> void:
	var me := local_player()
	if me != null:
		me.teleport_to(pos)


func _on_ability_fired(peer_id: int, ability_id: String) -> void:
	# Remote VFX only — the owner already executed the ability optimistically.
	if peer_id == multiplayer.get_unique_id():
		return
	var player := get_player_node(peer_id)
	if player != null:
		player.play_remote_ability(ability_id)


func _on_it_changed(new_it: int, old_it: int) -> void:
	if _hud != null and _hud.has_method("flash_tag"):
		_hud.flash_tag(new_it == multiplayer.get_unique_id())

	# Sell the tag on every screen: a lunge streak bridges whatever visual
	# gap replication left between the two players (the Among Us trick),
	# an impact ring marks the new "it", and both involved players freeze
	# for a beat (hit-stop) on their own machines.
	var tagger := get_player_node(old_it)
	var tagged := get_player_node(new_it)
	if tagger != null and tagged != null:
		var streak := TagStreak.new()
		streak.from_pos = tagger.global_position
		streak.to_pos = tagged.global_position
		add_child(streak)
	if tagged != null:
		tagged.spawn_pulse_ring(70.0)
	var my_id := multiplayer.get_unique_id()
	if my_id == new_it or my_id == old_it:
		var me := local_player()
		if me != null:
			me.hitstop_left = Player.TAG_HITSTOP


class TagStreak:
	extends Node2D
	var from_pos := Vector2.ZERO
	var to_pos := Vector2.ZERO

	func _ready() -> void:
		global_position = from_pos
		z_index = 50
		var tween := create_tween()
		tween.tween_property(self, "modulate:a", 0.0, 0.35)
		tween.tween_callback(queue_free)

	func _draw() -> void:
		var delta := to_pos - from_pos
		if delta.length() < 1.0:
			delta = Vector2(1, 0)
		draw_line(Vector2.ZERO, delta, Color(1.0, 0.3, 0.3, 0.9), 6.0)
		draw_circle(delta, 12.0, Color(1.0, 0.3, 0.3, 0.9))
