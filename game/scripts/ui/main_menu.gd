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
	var sky := Sky.new()
	var sm := ShaderMaterial.new()
	sm.shader = load("res://shaders/sky.gdshader")
	sky.sky_material = sm
	sky.radiance_size = Sky.RADIANCE_SIZE_64
	sky.process_mode = Sky.PROCESS_MODE_QUALITY
	env.background_mode = Environment.BG_SKY
	env.sky = sky
	env.ambient_light_source = Environment.AMBIENT_SOURCE_SKY
	env.ambient_light_sky_contribution = 0.55
	env.tonemap_mode = Environment.TONE_MAPPER_ACES
	env.tonemap_white = 6.0
	env.glow_enabled = true
	env.glow_intensity = 0.9
	env.glow_hdr_threshold = 0.85
	env.glow_blend_mode = Environment.GLOW_BLEND_MODE_ADDITIVE
	env.fog_enabled = true
	env.fog_light_color = Color(0.36, 0.24, 0.42)
	env.fog_density = 0.0035
	env.fog_height = -12.0
	env.fog_height_density = 0.06
	env.adjustment_enabled = true
	env.adjustment_saturation = 1.12
	we.environment = env
	add_child(we)
	var sun := DirectionalLight3D.new()
	sun.rotation_degrees = Vector3(-28.0, -125.0, 0.0)
	sun.light_color = Color(1.0, 0.78, 0.62)
	sun.light_energy = 1.35
	sun.shadow_enabled = true
	sun.directional_shadow_mode = DirectionalLight3D.SHADOW_ORTHOGONAL
	sun.directional_shadow_max_distance = 40.0
	add_child(sun)
	var fill := DirectionalLight3D.new()
	fill.rotation_degrees = Vector3(-35.0, 60.0, 0.0)
	fill.light_color = Color(0.45, 0.6, 1.0)
	fill.light_energy = 0.35
	add_child(fill)
	var arena := ArenaBuilder.new()
	add_child(arena)
	arena.build()
	_fighter = CharacterVisual.new()
	add_child(_fighter)
	_fighter.build("res://assets/characters/mannequin_m.scn", {
		"base": Color(0.9, 0.92, 0.96), "rim": Color(0.25, 0.85, 1.0), "glow": Color(0.2, 0.9, 1.0),
		"visor": Color(0.3, 1.0, 1.0), "stripe": 0.45, "metallic": 0.4, "roughness": 0.28,
	})
	_fighter.show_weapon(WeaponDB.weapon("arc_blade"))
	_fighter.position = Vector3(0, 2.5, 0)
	_fighter.rotation.y = PI * 0.15
	_fighter.anim.set_base("idle_blade", 0.0)
	_cam = Camera3D.new()
	_cam.fov = 55.0
	add_child(_cam)
	_cam.current = true
	get_viewport().scaling_3d_scale = 0.85 if int(Settings.get_value("quality")) < 2 else 1.0


func _process(delta: float) -> void:
	_t += delta
	var ang := _t * 0.08 + 0.6
	var target := Vector3(0, 3.6, 0)
	_cam.global_position = target + Vector3(sin(ang) * 7.5, 1.4 + sin(_t * 0.3) * 0.4, cos(ang) * 7.5)
	_cam.look_at(target + Vector3(sin(ang + 1.2) * 1.8, -0.2, cos(ang + 1.2) * 1.8))
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
	margin.add_theme_constant_override("margin_top", 60)
	margin.add_theme_constant_override("margin_bottom", 40)
	_ui.add_child(margin)
	_main_panel = VBoxContainer.new()
	_main_panel.add_theme_constant_override("separation", 12)
	margin.add_child(_main_panel)
	var title := Label.new()
	title.text = "NEON RIFT"
	title.add_theme_font_override("font", UITheme.title_font())
	title.add_theme_font_size_override("font_size", 92)
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
	spacer.custom_minimum_size = Vector2(0, 26)
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


func _add_button(text: String, cb: Callable) -> void:
	var b := Button.new()
	b.text = text
	b.custom_minimum_size = Vector2(420, 66)
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
[b]Left thumb[/b] – floating stick. Push to the edge to [b]sprint[/b] (uses SP).
[b]Right side drag[/b] – camera. You can keep aiming while holding [b]ATTACK[/b].
[b]ATTACK[/b] – blade combo / fire.  [b]SPECIAL[/b] – heavy slash, grenade, recoil jump or scope.
[b]JUMP[/b] – jump; press again next to a wall to [b]wall-kick[/b].
[b]DASH[/b] – quick evade with invulnerability frames; works in mid-air.
[b]Weapon tabs[/b] (top right) – switch instantly.  [b]Lightning[/b] – OVERDRIVE when charged.

[b][color=#ff8c33]MOVEMENT TECH[/color][/b]
• Sprint along a wall while airborne to [b]wall-run[/b]; jump off it to keep speed.
• Dash then jump to carry dash momentum. Jump pads launch you to high ground.
• Attack during a sprint or dash for a lunging [b]dash slash[/b]. In the air: slash, then plunge.
• Cancel attack recovery with dash or jump for fast combos.
• Scatter Cannon SPECIAL = recoil jump (mobility + close blast).

[b][color=#4de6ff]PC / GAMEPAD[/color][/b]
WASD move · Mouse look · LMB attack · RMB special · Space jump · Shift sprint · Ctrl/Q dash
1-4 weapons · Tab cycle · R reload · E overdrive · Esc pause"""


func _credits_text() -> String:
	return """[b][color=#4de6ff]NEON RIFT[/color][/b] – an original gameplay study inspired by the feel of fast arena action games. No assets, names or designs from any commercial game are used.

[b]Characters & animations:[/b] Quaternius – Universal Animation Library 1 & 2, Sci-Fi Essentials Kit, Modular Sci-Fi MegaKit (CC0)
[b]Effects textures & sounds:[/b] Kenney – Particle Pack, Sci-Fi / Impact / Interface / Digital / RPG audio (CC0)
[b]Music:[/b] "Hyper Ultra-Racing" by cynicmusic (CC0) · "Cyberpunk Moonlight Sonata" by Joth (CC0), via OpenGameArt
[b]Fonts:[/b] Orbitron (The Orbitron Project Authors) and Rajdhani (Indian Type Foundry), SIL Open Font License 1.1
[b]Engine:[/b] Godot Engine 4.7 (MIT) with Jolt Physics (MIT)

All code, shaders, level design, UI and the synthesized sound effects were created for this project. Full license details are in CREDITS.md."""
