extends Node3D
## Main menu: live 3D backdrop (the arena at dusk with an orbiting camera and a
## showcase fighter), title, mode selection, settings, how-to-play and credits.

var _cam: Camera3D
var _t := 0.0
var _ui: Control
var _main_panel: VBoxContainer
var _settings: SettingsPanel
var _info: PanelContainer
var _info_label: RichTextLabel
var _fighter: CharacterVisual
var _fighter_label: Label
var _pose_timer := 0.0
var _poses := ["Sword_Regular_A", "Sword_Regular_B", "Sword_Regular_C", "Sword_Attack"]
var _pose_i := 0


func _ready() -> void:
	get_tree().paused = false
	Input.mouse_mode = Input.MOUSE_MODE_VISIBLE
	_build_world()
	_build_ui()
	Audio.play_music(Audio.MUSIC_MENU, 1.5)


func _build_world() -> void:
	var we := WorldEnvironment.new()
	var env := Environment.new()
	env.tonemap_mode = Environment.TONE_MAPPER_ACES
	env.tonemap_white = 6.0
	env.glow_enabled = true
	env.glow_intensity = 0.9
	env.glow_hdr_threshold = 0.85
	env.glow_blend_mode = Environment.GLOW_BLEND_MODE_ADDITIVE
	env.fog_enabled = true
	env.fog_height = -12.0
	env.fog_height_density = 0.06
	env.adjustment_enabled = true
	env.adjustment_saturation = 1.12
	we.environment = env
	add_child(we)
	var sun := DirectionalLight3D.new()
	sun.shadow_enabled = true
	sun.directional_shadow_mode = DirectionalLight3D.SHADOW_ORTHOGONAL
	sun.directional_shadow_max_distance = 40.0
	add_child(sun)
	var fill := DirectionalLight3D.new()
	fill.rotation_degrees = Vector3(-35.0, 60.0, 0.0)
	add_child(fill)
	ArenaTheme.apply(env, sun, fill)
	var arena := ArenaBuilder.new()
	add_child(arena)
	arena.build()
	_spawn_fighter()
	_cam = Camera3D.new()
	_cam.fov = 50.0
	# Shift the frustum so the fighter sits on the right, clear of the menu.
	_cam.h_offset = -1.35
	add_child(_cam)
	_cam.current = true
	get_viewport().scaling_3d_scale = 0.85 if int(Settings.get_value("quality")) < 2 else 1.0


func _process(delta: float) -> void:
	_t += delta
	var ang := sin(_t * 0.12) * 0.6 + 0.35
	var target := _fighter.global_position + Vector3(0, 1.05, 0)
	_cam.global_position = target + Vector3(sin(ang) * 4.2, 0.55 + sin(_t * 0.3) * 0.15, cos(ang) * 4.2)
	_cam.look_at(target)
	_fighter.tick(delta)
	_pose_timer -= delta
	if _pose_timer <= 0.0:
		_pose_timer = 2.4
		var p: String = _poses[_pose_i % _poses.size()]
		_pose_i += 1
		_fighter.anim.play_action(p, 1.1, 0.12, 0.3)
		if _fighter.blade:
			_fighter.blade.set_trail(true)
			get_tree().create_timer(0.8).timeout.connect(func() -> void:
				if is_instance_valid(_fighter) and _fighter.blade:
					_fighter.blade.set_trail(false))


## Shows the selected fighter in the lobby (rebuilt when the choice changes).
func _spawn_fighter() -> void:
	if _fighter:
		_fighter.queue_free()
	_fighter = CharacterVisual.new()
	add_child(_fighter)
	var look := Player.fighter_look(int(Settings.get_value("fighter")))
	_fighter.build(look["model"], look["style"])
	_fighter.show_weapon(WeaponDB.weapon("arc_blade"))
	_fighter.position = Vector3(0, 2.5, 0)
	_fighter.rotation.y = PI * 1.12
	_fighter.anim.set_base("idle_blade", 0.0)


func _cycle_fighter(step: int) -> void:
	var n := Player.FIGHTERS.size()
	Settings.set_value("fighter", (int(Settings.get_value("fighter")) + step + n) % n)
	Audio.play("ui_toggle", -4.0)
	_spawn_fighter()
	_update_fighter_label()


func _update_fighter_label() -> void:
	if _fighter_label:
		_fighter_label.text = Player.FIGHTERS[int(Settings.get_value("fighter")) % Player.FIGHTERS.size()]["name"]


func _build_ui() -> void:
	var layer := CanvasLayer.new()
	add_child(layer)
	_ui = Control.new()
	_ui.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	_ui.theme = UITheme.get_theme()
	layer.add_child(_ui)
	# Left gradient for legibility.
	var grad := TextureRect.new()
	var gt := GradientTexture2D.new()
	var g := Gradient.new()
	g.set_color(0, Color(0.0, 0.01, 0.04, 0.85))
	g.set_color(1, Color(0.0, 0.01, 0.04, 0.0))
	gt.gradient = g
	gt.fill_from = Vector2(0, 0.5)
	gt.fill_to = Vector2(1, 0.5)
	grad.texture = gt
	UITheme.place(grad, Vector4(0, 0, 0, 1), Vector4(0, 0, 760, 0))
	grad.stretch_mode = TextureRect.STRETCH_SCALE
	grad.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_ui.add_child(grad)
	var margin := MarginContainer.new()
	margin.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	margin.add_theme_constant_override("margin_left", 70)
	margin.add_theme_constant_override("margin_top", 46)
	margin.add_theme_constant_override("margin_bottom", 40)
	_ui.add_child(margin)
	_main_panel = VBoxContainer.new()
	_main_panel.add_theme_constant_override("separation", 9)
	margin.add_child(_main_panel)
	var title := Label.new()
	title.text = "NEON RIFT"
	title.add_theme_font_override("font", UITheme.title_font())
	title.add_theme_font_size_override("font_size", 80)
	title.add_theme_color_override("font_color", Color(0.85, 0.97, 1.0))
	title.add_theme_color_override("font_shadow_color", Color(0.1, 0.7, 1.0, 0.6))
	title.add_theme_constant_override("shadow_offset_x", 0)
	title.add_theme_constant_override("shadow_offset_y", 0)
	title.add_theme_constant_override("shadow_outline_size", 18)
	_main_panel.add_child(title)
	var sub := Label.new()
	sub.text = "HIGH-SPEED ARENA COMBAT  ·  DEMO"
	sub.add_theme_font_override("font", UITheme.font(true))
	sub.add_theme_font_size_override("font_size", 28)
	sub.add_theme_color_override("font_color", UITheme.ORANGE)
	_main_panel.add_child(sub)
	var spacer := Control.new()
	spacer.custom_minimum_size = Vector2(0, 14)
	_main_panel.add_child(spacer)
	_add_button("WAVE ASSAULT", func() -> void:
		Audio.play("ui_confirm")
		Game.start_mode(Game.Mode.WAVES))
	_add_button("TRAINING GROUND", func() -> void:
		Audio.play("ui_confirm")
		Game.start_mode(Game.Mode.TRAINING))
	_add_button("SETTINGS", _open_settings)
	_add_button("HOW TO PLAY", func() -> void: _show_info(_how_to_text()))
	_add_button("CREDITS", func() -> void: _show_info(_credits_text()))
	if not OS.has_feature("mobile"):
		_add_button("QUIT", func() -> void: get_tree().quit())
	# Fighter select under the character (lobby style).
	var sel := HBoxContainer.new()
	sel.add_theme_constant_override("separation", 10)
	UITheme.place(sel, Vector4(1, 1, 1, 1), Vector4(-470, -130, -110, -64))
	sel.alignment = BoxContainer.ALIGNMENT_CENTER
	_ui.add_child(sel)
	var prev := Button.new()
	prev.text = "<"
	prev.custom_minimum_size = Vector2(64, 60)
	prev.pressed.connect(_cycle_fighter.bind(-1))
	sel.add_child(prev)
	_fighter_label = Label.new()
	_fighter_label.custom_minimum_size = Vector2(190, 60)
	_fighter_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_fighter_label.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	_fighter_label.add_theme_font_override("font", UITheme.italic_font(true))
	_fighter_label.add_theme_font_size_override("font_size", 34)
	_fighter_label.add_theme_color_override("font_outline_color", Color(0.01, 0.02, 0.05, 0.85))
	_fighter_label.add_theme_constant_override("outline_size", 8)
	sel.add_child(_fighter_label)
	var next := Button.new()
	next.text = ">"
	next.custom_minimum_size = Vector2(64, 60)
	next.pressed.connect(_cycle_fighter.bind(1))
	sel.add_child(next)
	_update_fighter_label()
	var ver := Label.new()
	ver.text = "v%s · original fan-made gameplay study" % ProjectSettings.get_setting("application/config/version", "1.0")
	ver.add_theme_font_size_override("font_size", 18)
	ver.add_theme_color_override("font_color", Color(1, 1, 1, 0.4))
	UITheme.place(ver, Vector4(1, 1, 1, 1), Vector4(-520, -40, -20, -10))
	ver.horizontal_alignment = HORIZONTAL_ALIGNMENT_RIGHT
	_ui.add_child(ver)
	var center := CenterContainer.new()
	center.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	center.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_ui.add_child(center)
	_settings = SettingsPanel.new()
	_settings.visible = false
	center.add_child(_settings)
	_settings.closed.connect(func() -> void:
		_settings.visible = false
		_main_panel.visible = true)
	_info = PanelContainer.new()
	_info.visible = false
	_info.custom_minimum_size = Vector2(820, 520)
	center.add_child(_info)
	var iv := VBoxContainer.new()
	_info.add_child(iv)
	_info_label = RichTextLabel.new()
	_info_label.bbcode_enabled = true
	_info_label.fit_content = false
	_info_label.custom_minimum_size = Vector2(780, 430)
	_info_label.add_theme_font_size_override("normal_font_size", 22)
	_info_label.add_theme_font_override("bold_font", UITheme.font(true))
	iv.add_child(_info_label)
	var back := Button.new()
	back.text = "BACK"
	back.pressed.connect(func() -> void:
		Audio.play("ui_back")
		_info.visible = false
		_main_panel.visible = true)
	iv.add_child(back)


func _notification(what: int) -> void:
	# Android back: close an open panel, otherwise quit.
	if what == NOTIFICATION_WM_GO_BACK_REQUEST:
		if _settings and _settings.visible:
			_settings.visible = false
			_main_panel.visible = true
		elif _info and _info.visible:
			_info.visible = false
			_main_panel.visible = true
		else:
			get_tree().quit()


func _add_button(text: String, cb: Callable) -> void:
	var b := Button.new()
	b.text = text
	b.custom_minimum_size = Vector2(400, 56)
	b.size_flags_horizontal = Control.SIZE_SHRINK_BEGIN
	b.alignment = HORIZONTAL_ALIGNMENT_LEFT
	b.pressed.connect(cb)
	b.mouse_entered.connect(func() -> void: Audio.play("ui_hover", -8.0))
	_main_panel.add_child(b)


func _open_settings() -> void:
	Audio.play("ui_click")
	_main_panel.visible = false
	_settings.visible = true


func _show_info(text: String) -> void:
	Audio.play("ui_click")
	_info_label.text = text
	_main_panel.visible = false
	_info.visible = true


func _how_to_text() -> String:
	return """[b][color=#4de6ff]TOUCH CONTROLS[/color][/b]
[b]Left thumb[/b] – floating stick; you always face where the camera looks.
[b]Right side drag[/b] – camera. You can keep aiming while holding [b]ATTACK[/b].
[b]SPRINT[/b] – or flick the stick forward twice. Keep pushing forward to keep sprinting (5 SP/s).
[b]JUMP[/b] – somersault jump. With the stick pushed [b]left/right[/b] it's a [b]side dodge[/b] (20 SP).
[b]ATTACK[/b] – blade combo / fire.  [b]SPECIAL[/b] – heavy slash, grenade, recoil jump or scope.
[b]CROUCH[/b] – toggle; ducks gunfire but you can't attack.  [b]Lightning[/b] – OVERDRIVE.

[b][color=#ff8c33]MOVEMENT[/color][/b]
• [b]Wall jump[/b]: during a jump, press JUMP next to a wall (20 SP). You bounce off like a mirror – angle in = angle out; run in diagonally to go farther. Near the top edge of a wall you vault over it instead. No wall jumps after just falling off a ledge.
• [b]Dodges[/b] have a short end lag: press JUMP (stick centred) to cancel it into a jump, then dodge again in the air – [b]wave dashing[/b] (costs SP fast). Sprinting also cancels the end lag.
• [b]Sprinting in mid-air[/b] makes you drop faster – chain quick [b]bunny hops[/b]. There's a short delay after each landing; firing a gun just before you land skips it.
• Weapons set your speed: blade 92 %, rifle & rail 83 %, scatter 79 % (slower while firing/scoped).
• Knocked flying? Press [b]JUMP[/b] to land on your feet. Knocked down? [b]Dodge[/b] to get up. Staggered? Dodge out for 90 SP.
• Attack while sprinting for a lunging [b]dash slash[/b]; you can walk while slashing. In the air: slash, then plunge.

[b][color=#4de6ff]PC / GAMEPAD[/color][/b]
WASD move (double-tap W to sprint) · Mouse look · LMB attack · RMB special · Space jump (A/D + Space dodge)
Ctrl crouch · Shift overdrive · Z camera view · 1-4 / wheel weapons · R reload · Esc pause"""


func _credits_text() -> String:
	return """[b][color=#4de6ff]NEON RIFT[/color][/b] – an original gameplay study inspired by the feel of fast arena action games. No assets, names or designs from any commercial game are used.

[b]Characters & animations:[/b] Quaternius – Universal Base Characters, Universal Animation Library 1 & 2, Sci-Fi Essentials Kit, Modular Sci-Fi MegaKit (CC0). Outfits painted for this project
[b]Effects textures & sounds:[/b] Kenney – Particle Pack, Sci-Fi / Impact / Interface / Digital / RPG audio (CC0)
[b]Music:[/b] "Hyper Ultra-Racing" by cynicmusic (CC0) · "Cyberpunk Moonlight Sonata" by Joth (CC0), via OpenGameArt
[b]Fonts:[/b] Orbitron (The Orbitron Project Authors) and Rajdhani (Indian Type Foundry), SIL Open Font License 1.1
[b]Engine:[/b] Godot Engine 4.7 (MIT) with Jolt Physics (MIT)

All code, shaders, level design, UI and the synthesized sound effects were created for this project. Full license details are in CREDITS.md."""
