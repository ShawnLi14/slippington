extends Node
## SoundManager autoload: a small SFX pool plus the ambient music loop.
## Game-flow sounds wire themselves to GameState signals here; physical
## one-shots (jump/spring/portal) are called directly by the local player.

const SFX := {
	"jump": preload("res://assets/audio/jump.wav"),
	"spring": preload("res://assets/audio/spring.wav"),
	"portal": preload("res://assets/audio/portal.wav"),
	"tag": preload("res://assets/audio/tag.wav"),
	"blink": preload("res://assets/audio/blink.wav"),
	"swap": preload("res://assets/audio/swap.wav"),
	"stun": preload("res://assets/audio/stun.wav"),
	"rewind": preload("res://assets/audio/rewind.wav"),
	"doppel": preload("res://assets/audio/doppel.wav"),
	"build": preload("res://assets/audio/build.wav"),
	"tick": preload("res://assets/audio/tick.wav"),
	"caught": preload("res://assets/audio/caught.wav"),
	"survived": preload("res://assets/audio/survived.wav"),
}

const SFX_DB := -8.0
const MUSIC_DB := -14.0

var _pool: Array[AudioStreamPlayer] = []
var _next_voice := 0
var _music: AudioStreamPlayer
var _last_tick_second := -1


func _ready() -> void:
	for i in 8:
		var p := AudioStreamPlayer.new()
		p.volume_db = SFX_DB
		add_child(p)
		_pool.append(p)

	_music = AudioStreamPlayer.new()
	var loop: AudioStreamWAV = preload("res://assets/audio/music_loop.wav")
	loop.loop_mode = AudioStreamWAV.LOOP_FORWARD
	loop.loop_end = loop.data.size() / 2  # 16-bit mono: 2 bytes per frame
	_music.stream = loop
	_music.volume_db = MUSIC_DB
	add_child(_music)

	GameState.phase_changed.connect(_on_phase_changed)
	GameState.it_changed.connect(func(_n, _o): play("tag"))
	GameState.practice_tagged.connect(func(): play("tag"))
	GameState.ability_fired.connect(_on_ability_fired)
	GameState.match_timer_updated.connect(_on_timer)
	GameState.match_ended.connect(_on_match_ended)


func play(name: String) -> void:
	if not SFX.has(name):
		return
	var voice := _pool[_next_voice]
	_next_voice = (_next_voice + 1) % _pool.size()
	voice.stream = SFX[name]
	voice.play()


func _on_phase_changed(phase: GameState.Phase) -> void:
	if phase == GameState.Phase.PLAYING:
		_last_tick_second = -1
		if not _music.playing:
			_music.play()
	elif phase == GameState.Phase.MENU:
		_music.stop()


func _on_ability_fired(_peer_id: int, ability_id: String) -> void:
	play(ability_id)


func _on_timer(remaining: float) -> void:
	var second := int(ceil(remaining))
	if second <= 5 and second >= 1 and second != _last_tick_second:
		_last_tick_second = second
		play("tick")


func _on_match_ended(_results: Array) -> void:
	var mine: Dictionary = {}
	for r in GameState.results:
		if r["peer_id"] == multiplayer.get_unique_id():
			mine = r
	if mine.get("was_it_at_end", false):
		play("caught")
	else:
		play("survived")
	if GameState.series_final:
		_music.stop()
