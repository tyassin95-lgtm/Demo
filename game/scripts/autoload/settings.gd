extends Node
## Persistent player settings (controls, graphics, audio). Saved to user://settings.cfg.

signal changed(key: String)

const PATH := "user://settings.cfg"

## Quality presets: 0 = Low, 1 = Medium, 2 = High.
const QUALITY_NAMES := ["LOW", "MEDIUM", "HIGH"]

var defaults := {
	"look_sensitivity": 1.0,
	"scope_sensitivity": 0.6,
	"invert_y": false,
	"aim_assist": 0.65,
	"auto_sprint": false,
	"camera_side": 0,
	"button_scale": 1.0,
	"button_opacity": 0.8,
	"left_handed": false,
	"quality": 1,
	"fps_cap": 60,
	"show_fps": false,
	"music_volume": 0.65,
	"sfx_volume": 0.9,
	"vibration": true,
	"mouse_sensitivity": 1.0,
}

var _data := {}


func _ready() -> void:
	_data = defaults.duplicate()
	load_settings()
	apply_runtime()


func get_value(key: String) -> Variant:
	return _data.get(key, defaults.get(key))


func set_value(key: String, value: Variant) -> void:
	if _data.get(key) == value:
		return
	_data[key] = value
	apply_runtime()
	save_settings()
	changed.emit(key)


func reset_to_defaults() -> void:
	_data = defaults.duplicate()
	apply_runtime()
	save_settings()
	changed.emit("")


func load_settings() -> void:
	var cfg := ConfigFile.new()
	if cfg.load(PATH) != OK:
		return
	for key in defaults.keys():
		if cfg.has_section_key("settings", key):
			var v: Variant = cfg.get_value("settings", key)
			if typeof(v) == typeof(defaults[key]) or (typeof(defaults[key]) == TYPE_FLOAT and typeof(v) == TYPE_INT):
				_data[key] = v


func save_settings() -> void:
	var cfg := ConfigFile.new()
	for key in _data.keys():
		cfg.set_value("settings", key, _data[key])
	cfg.save(PATH)


## Applies settings that live outside individual scenes (frame rate, audio buses).
func apply_runtime() -> void:
	var fps: int = int(get_value("fps_cap"))
	Engine.max_fps = fps
	# Keep physics in lock-step with the display cap so movement stays smooth
	# without needing physics interpolation.
	Engine.physics_ticks_per_second = maxi(60, fps) if fps > 0 else 60
	_set_bus_volume("Music", float(get_value("music_volume")))
	_set_bus_volume("SFX", float(get_value("sfx_volume")))


func _set_bus_volume(bus_name: String, linear: float) -> void:
	var idx := AudioServer.get_bus_index(bus_name)
	if idx < 0:
		return
	AudioServer.set_bus_volume_db(idx, linear_to_db(maxf(linear, 0.0001)))
	AudioServer.set_bus_mute(idx, linear <= 0.001)
