class_name PauseMenu
extends Control
## Pause overlay: resume, settings, restart, quit to menu. Muffles the music.

var _panel: PanelContainer
var _settings: SettingsPanel


func _ready() -> void:
	process_mode = Node.PROCESS_MODE_ALWAYS
	set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	theme = UITheme.get_theme()
	visible = false
	var dim := ColorRect.new()
	dim.color = Color(0.0, 0.01, 0.03, 0.72)
	dim.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	add_child(dim)
	var center := CenterContainer.new()
	center.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	add_child(center)
	_panel = PanelContainer.new()
	center.add_child(_panel)
	var v := VBoxContainer.new()
	v.add_theme_constant_override("separation", 14)
	_panel.add_child(v)
	var title := Label.new()
	title.text = "PAUSED"
	title.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	title.add_theme_font_override("font", UITheme.title_font())
	title.add_theme_font_size_override("font_size", 48)
	title.add_theme_color_override("font_color", UITheme.CYAN)
	v.add_child(title)
	for spec in [["RESUME", _resume], ["SETTINGS", _open_settings], ["RESTART", _restart], ["MAIN MENU", _quit]]:
		var b := Button.new()
		b.text = spec[0]
		b.custom_minimum_size = Vector2(380, 64)
		b.pressed.connect(spec[1])
		v.add_child(b)
	_settings = SettingsPanel.new()
	_settings.visible = false
	center.add_child(_settings)
	_settings.closed.connect(func() -> void:
		_settings.visible = false
		_panel.visible = true)


func _unhandled_input(event: InputEvent) -> void:
	if event.is_action_pressed("pause"):
		toggle()
		get_viewport().set_input_as_handled()


func toggle() -> void:
	if visible:
		_resume()
	else:
		open()


func open() -> void:
	if get_tree().paused:
		return
	visible = true
	_panel.visible = true
	_settings.visible = false
	get_tree().paused = true
	Input.mouse_mode = Input.MOUSE_MODE_VISIBLE
	Audio.set_music_muffled(true)
	Audio.play("ui_select")


func _resume() -> void:
	Audio.play("ui_back")
	visible = false
	get_tree().paused = false
	Audio.set_music_muffled(false)
	if not Game.is_touch_device:
		Input.mouse_mode = Input.MOUSE_MODE_CAPTURED


func _open_settings() -> void:
	Audio.play("ui_click")
	_panel.visible = false
	_settings.visible = true


func _restart() -> void:
	Audio.play("ui_confirm")
	Audio.set_music_muffled(false)
	Game.start_mode(Game.mode)


func _quit() -> void:
	Audio.play("ui_back")
	Audio.set_music_muffled(false)
	Input.mouse_mode = Input.MOUSE_MODE_VISIBLE
	Game.goto_scene("res://scenes/main_menu.tscn")
