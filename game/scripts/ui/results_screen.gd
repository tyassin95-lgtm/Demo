class_name ResultsScreen
extends Control
## End-of-match screen with stats, rank, retry and menu buttons.

var _stats: VBoxContainer
var _title: Label
var _rank: Label


func _ready() -> void:
	process_mode = Node.PROCESS_MODE_ALWAYS
	set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	theme = UITheme.get_theme()
	visible = false
	var dim := ColorRect.new()
	dim.color = Color(0.0, 0.01, 0.03, 0.6)
	dim.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	add_child(dim)
	var center := CenterContainer.new()
	center.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	add_child(center)
	var panel := PanelContainer.new()
	center.add_child(panel)
	var h := HBoxContainer.new()
	h.add_theme_constant_override("separation", 40)
	panel.add_child(h)
	var left := VBoxContainer.new()
	left.add_theme_constant_override("separation", 8)
	h.add_child(left)
	_title = Label.new()
	_title.add_theme_font_override("font", UITheme.title_font())
	_title.add_theme_font_size_override("font_size", 54)
	left.add_child(_title)
	_stats = VBoxContainer.new()
	left.add_child(_stats)
	var buttons := HBoxContainer.new()
	buttons.add_theme_constant_override("separation", 16)
	left.add_child(buttons)
	var retry := Button.new()
	retry.text = "RETRY"
	retry.custom_minimum_size = Vector2(220, 60)
	retry.pressed.connect(func() -> void:
		Audio.play("ui_confirm")
		Game.start_mode(Game.mode))
	buttons.add_child(retry)
	var menu := Button.new()
	menu.text = "MAIN MENU"
	menu.custom_minimum_size = Vector2(240, 60)
	menu.pressed.connect(func() -> void:
		Audio.play("ui_back")
		Game.goto_scene("res://scenes/main_menu.tscn"))
	buttons.add_child(menu)
	_rank = Label.new()
	_rank.add_theme_font_override("font", UITheme.title_font())
	_rank.add_theme_font_size_override("font_size", 150)
	_rank.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	h.add_child(_rank)


func show_results(victory: bool, d: Dictionary) -> void:
	visible = true
	Input.mouse_mode = Input.MOUSE_MODE_VISIBLE
	_title.text = "ARENA CLEARED" if victory else "DEFEATED"
	_title.add_theme_color_override("font_color", Color(0.45, 1.0, 0.6) if victory else Color(1.0, 0.35, 0.3))
	for c in _stats.get_children():
		c.queue_free()
	var lines := [
		["SCORE", str(d.get("score", 0))],
		["WAVE", "%d / %d" % [d.get("wave", 0), d.get("waves", 0)]],
		["KILLS", str(d.get("kills", 0))],
		["BEST COMBO", str(d.get("best_combo", 0))],
		["DAMAGE DEALT", str(int(d.get("damage", 0)))],
		["TIME", "%d:%02d" % [int(d.get("time", 0)) / 60, int(d.get("time", 0)) % 60]],
	]
	for l in lines:
		var row := HBoxContainer.new()
		var a := Label.new()
		a.text = l[0]
		a.custom_minimum_size = Vector2(240, 0)
		a.add_theme_color_override("font_color", Color(0.6, 0.75, 0.9))
		row.add_child(a)
		var b := Label.new()
		b.text = l[1]
		b.add_theme_font_override("font", UITheme.font(true))
		row.add_child(b)
		_stats.add_child(row)
	var score: int = d.get("score", 0)
	var rank := "C"
	if victory:
		rank = "S" if score > 5200 else ("A" if score > 3800 else "B")
	elif int(d.get("wave", 0)) >= 3:
		rank = "B"
	_rank.text = rank
	var rc := {"S": Color(1.0, 0.8, 0.25), "A": Color(0.4, 1.0, 0.7), "B": Color(0.4, 0.8, 1.0), "C": Color(0.7, 0.7, 0.8)}
	_rank.add_theme_color_override("font_color", rc[rank])
	_rank.scale = Vector2(1.6, 1.6)
	_rank.pivot_offset = Vector2(60, 90)
	var tw := create_tween()
	tw.tween_property(_rank, "scale", Vector2.ONE, 0.35).set_trans(Tween.TRANS_BACK).set_ease(Tween.EASE_OUT)
