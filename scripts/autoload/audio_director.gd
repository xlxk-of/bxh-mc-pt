extends Node
## Music with crossfade + a pooled one-shot SFX player, wired to the
## Music / SFX buses so the settings sliders map straight onto bus volume.

const SFX_DIR := "res://assets/audio/sfx/"
const MUSIC_DIR := "res://assets/audio/music/"
const POOL_SIZE := 24
const FADE_TIME := 0.8
const DIMMED_DB := -12.0

var _sfx_pool: Array[AudioStreamPlayer] = []
var _sfx_next := 0
var _sfx_cache := {}
var _music_a: AudioStreamPlayer
var _music_b: AudioStreamPlayer
var _music_active: AudioStreamPlayer
var _current_track := ""
var _dimmed := false
var _music_tween: Tween

## Guards against a dozen simultaneous line-clear sounds stacking into a click.
var _recent := {}


func _ready() -> void:
	process_mode = Node.PROCESS_MODE_ALWAYS
	for i in POOL_SIZE:
		var p := AudioStreamPlayer.new()
		p.bus = "SFX"
		add_child(p)
		_sfx_pool.append(p)
	_music_a = _make_music_player()
	_music_b = _make_music_player()
	_music_active = _music_a
	SaveGame.settings_changed.connect(apply_volumes)
	apply_volumes()


func _make_music_player() -> AudioStreamPlayer:
	var p := AudioStreamPlayer.new()
	p.bus = "Music"
	p.volume_db = -80.0
	add_child(p)
	return p


func _process(delta: float) -> void:
	for k in _recent.keys():
		_recent[k] -= delta
		if _recent[k] <= 0.0:
			_recent.erase(k)


func apply_volumes() -> void:
	var music_bus := AudioServer.get_bus_index("Music")
	var sfx_bus := AudioServer.get_bus_index("SFX")
	var mv: float = SaveGame.music_volume
	var dim := DIMMED_DB if _dimmed else 0.0
	AudioServer.set_bus_volume_db(music_bus, (-80.0 if mv <= 0.001 else linear_to_db(mv)) + dim)
	AudioServer.set_bus_mute(music_bus, mv <= 0.001)
	var sv: float = SaveGame.sfx_volume
	AudioServer.set_bus_volume_db(sfx_bus, -80.0 if sv <= 0.001 else linear_to_db(sv))
	AudioServer.set_bus_mute(sfx_bus, sv <= 0.001)


## Ducks the music while a modal menu is open.
func set_music_dimmed(dimmed: bool) -> void:
	if _dimmed == dimmed:
		return
	_dimmed = dimmed
	apply_volumes()


# ---------------------------------------------------------------------- sfx
func play(key: String, volume_scale := 1.0, pitch := 1.0) -> void:
	if key.is_empty() or volume_scale <= 0.0:
		return
	if _recent.has(key):
		# Same cue re-triggered within a couple of frames: soften instead of stack.
		volume_scale *= 0.45
	_recent[key] = 0.05

	var stream := _load_sfx(key)
	if stream == null:
		return
	var p := _sfx_pool[_sfx_next]
	_sfx_next = (_sfx_next + 1) % _sfx_pool.size()
	p.stream = stream
	p.volume_db = linear_to_db(clampf(volume_scale, 0.01, 2.0))
	p.pitch_scale = pitch
	p.play()


## Tiered combo cue, mirroring play_tiered_combo_sfx().
func play_combo(streak: int) -> void:
	if streak <= 0:
		return
	var idx: int = mini(streak, Cfg.SFX_COMBO.size()) - 1
	# Above the top tier the pitch keeps climbing so long streaks stay readable.
	var extra: int = maxi(0, streak - Cfg.SFX_COMBO.size())
	play(Cfg.SFX_COMBO[idx], 1.0, 1.0 + minf(extra * 0.04, 0.5))


func _load_sfx(key: String) -> AudioStream:
	if _sfx_cache.has(key):
		return _sfx_cache[key]
	var path := SFX_DIR + key + ".wav"
	var s: AudioStream = null
	if ResourceLoader.exists(path):
		s = load(path)
	else:
		push_warning("Missing sfx: " + key)
	_sfx_cache[key] = s
	return s


# -------------------------------------------------------------------- music
func play_music(key: String, restart := false) -> void:
	if key == _current_track and not restart:
		return
	var path := MUSIC_DIR + key + ".ogg"
	if not ResourceLoader.exists(path):
		push_warning("Missing music: " + key)
		return
	_current_track = key

	var incoming: AudioStreamPlayer = _music_b if _music_active == _music_a else _music_a
	var outgoing: AudioStreamPlayer = _music_active
	var stream: AudioStream = load(path)
	if stream is AudioStreamOggVorbis:
		(stream as AudioStreamOggVorbis).loop = true
	incoming.stream = stream
	incoming.volume_db = -80.0
	incoming.play()
	_music_active = incoming

	if _music_tween and _music_tween.is_valid():
		_music_tween.kill()
	_music_tween = create_tween()
	_music_tween.set_parallel(true)
	_music_tween.tween_property(incoming, "volume_db", 0.0, FADE_TIME)
	_music_tween.tween_property(outgoing, "volume_db", -80.0, FADE_TIME)
	_music_tween.chain().tween_callback(outgoing.stop)


func stop_music() -> void:
	_current_track = ""
	_music_a.stop()
	_music_b.stop()


func current_track() -> String:
	return _current_track
