class_name SettingsPanel
extends PanelContainer
## Settings screen used by both the main menu and the pause menu.

signal closed

var _rows: Array = []


func _ready() -> void:
	theme = UITheme.get_theme()
	custom_minimum_size = Vector2(760, 0)
	var root := VBoxContainer.new()
	root.add_theme_constant_override("separation", 10)
	add_child(root)
	var title := Label.new()
	title.text = "SETTINGS"
	title.add_theme_font_override("font", UITheme.title_font())
	title.add_theme_font_size_override("font_size", 40)
	title.add_theme_color_override("font_color", UITheme.CYAN)
	root.add_child(title)
	var scroll := ScrollContainer.new()
	scroll.custom_minimum_size = Vector2(700, 440)
	scroll.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	root.add_child(scroll)
	var list := VBoxContainer.new()
	list.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	list.add_theme_constant_override("separation", 6)
	scroll.add_child(list)

	_section(list, "CONTROLS")
	_slider(list, "Look sensitivity", "look_sensitivity", 0.2, 3.0, 0.05)
	_slider(list, "Scoped sensitivity", "scope_sensitivity", 0.2, 1.5, 0.05)
	_slider(list, "Aim assist", "aim_assist", 0.0, 1.0, 0.05)
	_choice(list, "Camera view", "camera_side", ["CENTER", "RIGHT", "LEFT"], [0, 1, 2])
	_toggle(list, "Invert look Y", "invert_y")
	_toggle(list, "Sprint by pushing the stick to the edge", "auto_sprint")
	_slider(list, "Button size", "button_scale", 0.7, 1.4, 0.05)
	_slider(list, "Button opacity", "button_opacity", 0.3, 1.0, 0.05)
	_toggle(list, "Left-handed layout", "left_handed")
	_toggle(list, "Vibration", "vibration")
	_slider(list, "Mouse sensitivity (PC)", "mouse_sensitivity", 0.2, 3.0, 0.05)
	_section(list, "GRAPHICS")
	_choice(list, "Quality", "quality", ["LOW", "MEDIUM", "HIGH"], [0, 1, 2])
	_choice(list, "Frame rate cap", "fps_cap", ["30", "60", "90", "120"], [30, 60, 90, 120])
	_toggle(list, "Show FPS", "show_fps")
	_section(list, "AUDIO")
	_slider(list, "Music volume", "music_volume", 0.0, 1.0, 0.05)
	_slider(list, "Effects volume", "sfx_volume", 0.0, 1.0, 0.05)

	var buttons := HBoxContainer.new()
	buttons.add_theme_constant_override("separation", 16)
	buttons.alignment = BoxContainer.ALIGNMENT_END
	root.add_child(buttons)
	var reset := Button.new()
	reset.text = "DEFAULTS"
	reset.pressed.connect(func() -> void:
		Audio.play("ui_click")
		Settings.reset_to_defaults()
		_refresh())
	buttons.add_child(reset)
	var back := Button.new()
	back.text = "BACK"
	back.pressed.connect(func() -> void:
		Audio.play("ui_back")
		closed.emit())
	buttons.add_child(back)
	_refresh()


func _section(parent: Control, text: String) -> void:
	var l := Label.new()
	l.text = text
	l.add_theme_font_override("font", UITheme.font(true))
	l.add_theme_font_size_override("font_size", 24)
	l.add_theme_color_override("font_color", UITheme.ORANGE)
	parent.add_child(l)


func _row(parent: Control, label: String) -> HBoxContainer:
	var h := HBoxContainer.new()
	h.add_theme_constant_override("separation", 14)
	var l := Label.new()
	l.text = label
	l.custom_minimum_size = Vector2(330, 0)
	l.add_theme_font_size_override("font_size", 24)
	h.add_child(l)
	parent.add_child(h)
	return h


func _slider(parent: Control, label: String, key: String, lo: float, hi: float, step: float) -> void:
	var h := _row(parent, label)
	var s := HSlider.new()
	s.min_value = lo
	s.max_value = hi
	s.step = step
	s.custom_minimum_size = Vector2(250, 36)
	s.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	h.add_child(s)
	var v := Label.new()
	v.custom_minimum_size = Vector2(60, 0)
	v.add_theme_font_size_override("font_size", 22)
	h.add_child(v)
	s.value_changed.connect(func(val: float) -> void:
		Settings.set_value(key, val)
		v.text = "%.2f" % val)
	_rows.append(func() -> void:
		s.set_value_no_signal(float(Settings.get_value(key)))
		v.text = "%.2f" % float(Settings.get_value(key)))


func _toggle(parent: Control, label: String, key: String) -> void:
	var h := _row(parent, label)
	var c := CheckButton.new()
	h.add_child(c)
	c.toggled.connect(func(on: bool) -> void:
		Audio.play("ui_toggle", -4.0)
		Settings.set_value(key, on))
	_rows.append(func() -> void: c.set_pressed_no_signal(bool(Settings.get_value(key))))


func _choice(parent: Control, label: String, key: String, names: Array, values: Array) -> void:
	var h := _row(parent, label)
	var group := ButtonGroup.new()
	var btns: Array[Button] = []
	for i in names.size():
		var b := Button.new()
		b.text = names[i]
		b.toggle_mode = true
		b.button_group = group
		b.add_theme_font_size_override("font_size", 22)
		var val: int = values[i]
		b.pressed.connect(func() -> void:
			Audio.play("ui_click")
			Settings.set_value(key, val))
		h.add_child(b)
		btns.append(b)
	_rows.append(func() -> void:
		var cur := int(Settings.get_value(key))
		for i in btns.size():
			btns[i].set_pressed_no_signal(values[i] == cur))


func _refresh() -> void:
	for r in _rows:
		(r as Callable).call()
