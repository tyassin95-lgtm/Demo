extends Node
## Sound manager: pooled 2D/3D SFX players with variation, anti-spam, and crossfading music.

const SFX_DIR := "res://assets/audio/sfx/"
const MUSIC_BATTLE := "res://assets/audio/music/battle_hyper_ultra_racing.ogg"
const MUSIC_MENU := "res://assets/audio/music/menu_cyberpunk_moonlight_sonata.ogg"
const BATTLE_LOOP_OFFSET := 11.482

## Logical sound name -> list of file variants (without extension).
const SOUNDS := {
	"ui_click": ["ui_click"], "ui_select": ["ui_select"], "ui_confirm": ["ui_confirm"],
	"ui_back": ["ui_back"], "ui_toggle": ["ui_toggle"], "ui_error": ["ui_error"],
	"ui_hover": ["gen_ui_hover"], "hitmarker": ["hitmarker"],
	"rifle_shot": ["rifle_shot_1", "rifle_shot_2", "rifle_shot_3"],
	"scatter_shot": ["scatter_shot"], "scatter_boom": ["scatter_boom"],
	"rail_shot": ["rail_shot"], "rail_charge": ["rail_charge"],
	"launcher_shot": ["launcher_shot"],
	"explosion": ["explosion_1", "explosion_2"], "explosion_low": ["explosion_low"],
	"impact_world": ["impact_metal_1", "impact_metal_2", "impact_light"],
	"body_hit": ["body_hit_1", "body_hit_2"],
	"player_hurt": ["player_hurt_1", "player_hurt_2"],
	"knockdown": ["knockdown"],
	"step": ["step_1", "step_2", "step_3", "step_4"],
	"reload": ["reload_1"], "reload_done": ["reload_2"],
	"swap_blade": ["swap_blade"], "swap_gun": ["swap_gun"], "empty": ["empty_click"],
	"pickup": ["pickup"], "wave_start": ["wave_start"], "wave_clear": ["wave_clear"],
	"beep": ["beep"], "game_over": ["game_over"], "kill": ["kill_confirm"],
	"enemy_death": ["enemy_death"], "enemy_alert": ["enemy_alert"],
	"overdrive_ready": ["overdrive_ready"], "shield": ["shield"],
	"jump": ["gen_jump"], "dash": ["gen_dash"], "air_dash": ["gen_air_dash"],
	"land": ["gen_land"], "wall_kick": ["gen_wall_kick"], "jump_pad": ["gen_jump_pad"],
	"blade_swing": ["gen_blade_swing_1", "gen_blade_swing_2"],
	"blade_swing_big": ["gen_blade_swing_3"], "blade_heavy": ["gen_blade_heavy"],
	"blade_ignite": ["gen_blade_ignite"], "blade_hit": ["gen_blade_hit"],
	"heavy_hit": ["gen_heavy_hit"], "overdrive": ["gen_overdrive"],
	"shockwave": ["gen_shockwave"], "spawn": ["gen_spawn"], "heartbeat": ["gen_heartbeat"],
}

const POOL_2D := 14
const POOL_3D := 20

var _streams := {}
var _pool2d: Array[AudioStreamPlayer] = []
var _pool3d: Array[AudioStreamPlayer3D] = []
var _i2d := 0
var _i3d := 0
var _last_play := {}
var _music_a: AudioStreamPlayer
var _music_b: AudioStreamPlayer
var _music_current: AudioStreamPlayer
var _current_music_path := ""
var _music_filter: AudioEffectLowPassFilter


func _ready() -> void:
	process_mode = Node.PROCESS_MODE_ALWAYS
	_create_buses()
	for i in POOL_2D:
		var p := AudioStreamPlayer.new()
		p.bus = &"SFX"
		add_child(p)
		_pool2d.append(p)
	for i in POOL_3D:
		var p := AudioStreamPlayer3D.new()
		p.bus = &"SFX"
		p.unit_size = 8.0
		p.max_distance = 60.0
		p.attenuation_filter_cutoff_hz = 9000.0
		p.panning_strength = 0.8
		add_child(p)
		_pool3d.append(p)
	_music_a = AudioStreamPlayer.new()
	_music_b = AudioStreamPlayer.new()
	for m in [_music_a, _music_b]:
		m.bus = &"Music"
		m.volume_db = -80.0
		add_child(m)
	_music_current = _music_a
	Settings.apply_runtime()
	# Preload every sound so first use never hitches.
	for key in SOUNDS:
		for f in SOUNDS[key]:
			_get_stream(f)


func _create_buses() -> void:
	if AudioServer.get_bus_index("Music") < 0:
		AudioServer.add_bus()
		var i := AudioServer.bus_count - 1
		AudioServer.set_bus_name(i, "Music")
		AudioServer.set_bus_send(i, &"Master")
		_music_filter = AudioEffectLowPassFilter.new()
		_music_filter.cutoff_hz = 20000.0
		AudioServer.add_bus_effect(i, _music_filter)
	if AudioServer.get_bus_index("SFX") < 0:
		AudioServer.add_bus()
		var j := AudioServer.bus_count - 1
		AudioServer.set_bus_name(j, "SFX")
		AudioServer.set_bus_send(j, &"Master")
		var comp := AudioEffectCompressor.new()
		comp.threshold = -10.0
		comp.ratio = 3.0
		comp.release_ms = 120.0
		AudioServer.add_bus_effect(j, comp)
	var master := AudioServer.get_bus_index("Master")
	var lim := AudioEffectHardLimiter.new()
	AudioServer.add_bus_effect(master, lim)


func _get_stream(file: String) -> AudioStream:
	if _streams.has(file):
		return _streams[file]
	var path := SFX_DIR + file + ".ogg"
	var s: AudioStream = load(path) if ResourceLoader.exists(path) else null
	_streams[file] = s
	return s


func _pick(sound: String) -> AudioStream:
	var list: Array = SOUNDS.get(sound, [])
	if list.is_empty():
		return null
	return _get_stream(list[randi() % list.size()])


func _allowed(sound: String, min_gap_ms: int) -> bool:
	var now := Time.get_ticks_msec()
	if now - int(_last_play.get(sound, -100000)) < min_gap_ms:
		return false
	_last_play[sound] = now
	return true


## Plays a non-positional sound (player-centric or UI).
func play(sound: String, volume_db: float = 0.0, pitch: float = 1.0, pitch_rand: float = 0.06, min_gap_ms: int = 25) -> void:
	if not _allowed(sound, min_gap_ms):
		return
	var s := _pick(sound)
	if s == null:
		return
	var p := _pool2d[_i2d]
	_i2d = (_i2d + 1) % POOL_2D
	p.stream = s
	p.volume_db = volume_db
	p.pitch_scale = maxf(0.05, pitch * (1.0 + randf_range(-pitch_rand, pitch_rand)))
	p.play()


## Plays a positional sound in the world.
func play_at(sound: String, pos: Vector3, volume_db: float = 0.0, pitch: float = 1.0, pitch_rand: float = 0.08, min_gap_ms: int = 25) -> void:
	if not _allowed(sound + "@3d", min_gap_ms):
		return
	var s := _pick(sound)
	if s == null:
		return
	var p := _pool3d[_i3d]
	_i3d = (_i3d + 1) % POOL_3D
	p.stream = s
	p.volume_db = volume_db
	p.pitch_scale = maxf(0.05, pitch * (1.0 + randf_range(-pitch_rand, pitch_rand)))
	p.global_position = pos
	p.play()


func play_music(path: String, fade: float = 1.2) -> void:
	if path == _current_music_path and _music_current.playing:
		return
	_current_music_path = path
	var stream: AudioStream = load(path)
	if stream is AudioStreamOggVorbis:
		stream.loop = true
		if path == MUSIC_BATTLE:
			stream.loop_offset = BATTLE_LOOP_OFFSET
	var old := _music_current
	var new := _music_b if old == _music_a else _music_a
	new.stream = stream
	new.volume_db = -40.0
	new.play()
	_music_current = new
	var tw := create_tween().set_parallel(true)
	tw.tween_property(new, "volume_db", 0.0, fade).set_trans(Tween.TRANS_SINE)
	if old.playing:
		tw.tween_property(old, "volume_db", -60.0, fade)
		tw.chain().tween_callback(old.stop)


func stop_music(fade: float = 1.0) -> void:
	_current_music_path = ""
	var m := _music_current
	var tw := create_tween()
	tw.tween_property(m, "volume_db", -60.0, fade)
	tw.tween_callback(m.stop)


## Muffles the music (pause menu, overdrive, low health).
func set_music_muffled(muffled: bool, cutoff: float = 900.0) -> void:
	if _music_filter == null:
		return
	var target := cutoff if muffled else 20000.0
	var tw := create_tween()
	tw.tween_property(_music_filter, "cutoff_hz", target, 0.35)
