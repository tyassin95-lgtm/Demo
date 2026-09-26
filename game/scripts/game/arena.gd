extends Node3D
## Arena scene root: builds the level, lighting, navigation, player, UI and runs
## the match through the WaveDirector.

var builder: ArenaBuilder
var player: Player
var director: WaveDirector
var hud: HUD
var controls: TouchControls
var pause_menu: PauseMenu
var results: ResultsScreen
var env: Environment
var sun: DirectionalLight3D
var nav_region: NavigationRegion3D
var _ended := false


func _ready() -> void:
	_setup_environment()
	builder = ArenaBuilder.new()
	builder.name = "Arena"
	add_child(builder)
	builder.build()
	_setup_navigation()
	for p in builder.pickup_points:
		var hp := HealthPickup.new()
		add_child(hp)
		hp.global_position = p
	player = Player.new()
	player.name = "Player"
	add_child(player)
	player.global_position = builder.player_spawn
	player.facing = 0.0
	player.cam.snap_behind(0.0)
	_setup_ui()
	director = WaveDirector.new()
	director.name = "Director"
	director.arena = self
	director.spawns = builder.enemy_spawns
	add_child(director)
	director.announce.connect(hud.announce)
	director.finished.connect(_on_finished)
	hud.director = director
	director.start(Game.mode)
	Settings.changed.connect(_on_settings_changed)
	apply_quality()
	Audio.play_music(Audio.MUSIC_BATTLE)
	VFX.warmup(builder.player_spawn + Vector3(0, -8, 0))
	if not Game.is_touch_device and not _force_touch():
		Input.mouse_mode = Input.MOUSE_MODE_CAPTURED


func _force_touch() -> bool:
	return OS.get_cmdline_user_args().has("--touch") or DisplayServer.is_touchscreen_available()


func _setup_environment() -> void:
	var we := WorldEnvironment.new()
	env = Environment.new()
	var sky := Sky.new()
	var sm := ShaderMaterial.new()
	sm.shader = load("res://shaders/sky.gdshader")
	sky.sky_material = sm
	sky.radiance_size = Sky.RADIANCE_SIZE_64
	sky.process_mode = Sky.PROCESS_MODE_QUALITY
	env.background_mode = Environment.BG_SKY
	env.sky = sky
	env.ambient_light_source = Environment.AMBIENT_SOURCE_SKY
	env.ambient_light_sky_contribution = 0.3
	env.ambient_light_color = Color(0.24, 0.28, 0.38)
	env.ambient_light_energy = 1.0
	env.reflected_light_source = Environment.REFLECTION_SOURCE_SKY
	env.tonemap_mode = Environment.TONE_MAPPER_ACES
	env.tonemap_exposure = 1.05
	env.tonemap_white = 6.0
	env.glow_enabled = true
	env.glow_intensity = 0.9
	env.glow_strength = 1.0
	env.glow_bloom = 0.04
	env.glow_hdr_threshold = 0.85
	env.glow_blend_mode = Environment.GLOW_BLEND_MODE_ADDITIVE
	env.set_glow_level(0, 0.0)
	env.set_glow_level(1, 1.0)
	env.set_glow_level(2, 0.8)
	env.set_glow_level(3, 0.6)
	env.set_glow_level(4, 0.4)
	env.fog_enabled = true
	env.fog_mode = Environment.FOG_MODE_EXPONENTIAL
	env.fog_light_color = Color(0.32, 0.24, 0.4)
	env.fog_light_energy = 1.0
	env.fog_density = 0.003
	env.fog_sky_affect = 0.15
	env.fog_height = -12.0
	env.fog_height_density = 0.06
	env.adjustment_enabled = true
	env.adjustment_contrast = 1.08
	env.adjustment_saturation = 1.12
	we.environment = env
	add_child(we)
	sun = DirectionalLight3D.new()
	sun.name = "Sun"
	sun.rotation_degrees = Vector3(-28.0, -125.0, 0.0)
	sun.light_color = Color(1.0, 0.78, 0.62)
	sun.light_energy = 1.35
	sun.shadow_enabled = true
	sun.directional_shadow_mode = DirectionalLight3D.SHADOW_ORTHOGONAL
	sun.directional_shadow_max_distance = 55.0
	sun.shadow_bias = 0.04
	sun.shadow_normal_bias = 1.2
	sun.shadow_blur = 1.0
	add_child(sun)
	# Cool rim fill from the opposite side (no shadows).
	var fill := DirectionalLight3D.new()
	fill.rotation_degrees = Vector3(-35.0, 60.0, 0.0)
	fill.light_color = Color(0.45, 0.6, 1.0)
	fill.light_energy = 0.35
	fill.shadow_enabled = false
	add_child(fill)


func _setup_navigation() -> void:
	nav_region = NavigationRegion3D.new()
	var nm := NavigationMesh.new()
	nm.agent_radius = 0.5
	nm.agent_height = 1.75
	nm.agent_max_climb = 0.5
	nm.agent_max_slope = 42.0
	nm.cell_size = 0.25
	nm.cell_height = 0.25
	nm.geometry_parsed_geometry_type = NavigationMesh.PARSED_GEOMETRY_STATIC_COLLIDERS
	nm.geometry_collision_mask = Game.LAYER_WORLD
	nm.geometry_source_geometry_mode = NavigationMesh.SOURCE_GEOMETRY_GROUPS_WITH_CHILDREN
	nm.geometry_source_group_name = &"nav_source"
	nm.filter_baking_aabb = AABB(Vector3(-27, -1.5, -27), Vector3(54, 9.0, 54))
	nav_region.navigation_mesh = nm
	add_child(nav_region)
	var body := builder.get_node("ArenaCollision")
	body.add_to_group("nav_source")
	nav_region.bake_navigation_mesh(false)


func _setup_ui() -> void:
	var layer := CanvasLayer.new()
	layer.layer = 10
	add_child(layer)
	hud = HUD.new()
	layer.add_child(hud)
	hud.bind_player(player)
	controls = TouchControls.new()
	controls.player = player
	controls.camera = player.cam
	layer.add_child(controls)
	controls.visible = Game.is_touch_device or _force_touch()
	player.controls = controls
	var top := CanvasLayer.new()
	top.layer = 20
	top.process_mode = Node.PROCESS_MODE_ALWAYS
	add_child(top)
	pause_menu = PauseMenu.new()
	top.add_child(pause_menu)
	results = ResultsScreen.new()
	top.add_child(results)
	controls.pause_requested.connect(pause_menu.open)


func _notification(what: int) -> void:
	# Auto-pause when the app goes to the background on mobile.
	if what == NOTIFICATION_APPLICATION_FOCUS_OUT or what == NOTIFICATION_APPLICATION_PAUSED:
		if pause_menu and not _ended and not get_tree().paused:
			pause_menu.open()
	# Android back button toggles the pause menu.
	if what == NOTIFICATION_WM_GO_BACK_REQUEST and pause_menu and not _ended:
		pause_menu.toggle()


func _input(event: InputEvent) -> void:
	# Enable touch UI automatically the first time a touch is detected.
	if event is InputEventScreenTouch and controls and not controls.visible:
		controls.visible = true
		Game.is_touch_device = true
		Input.mouse_mode = Input.MOUSE_MODE_VISIBLE
	if event is InputEventMouseButton and event.pressed and not Game.is_touch_device and not get_tree().paused and not _ended:
		Input.mouse_mode = Input.MOUSE_MODE_CAPTURED


func _on_finished(victory: bool) -> void:
	if _ended:
		return
	_ended = true
	await get_tree().create_timer(2.2 if victory else 2.8).timeout
	if not is_inside_tree():
		return
	controls.visible = false
	var d := {
		"score": director.score, "wave": director.wave + 1, "waves": director.total_waves(),
		"kills": director.kills, "best_combo": player.best_combo, "damage": player.damage_dealt,
		"time": director.elapsed,
	}
	Game.last_results = d
	results.show_results(victory, d)
	Audio.set_music_muffled(true, 1500.0)


func _on_settings_changed(key: String) -> void:
	if key == "quality" or key == "":
		apply_quality()


## Applies the graphics preset (render scale, AA, shadows, glow, effects density).
func apply_quality() -> void:
	var q := int(Settings.get_value("quality"))
	var vp := get_viewport()
	VFX.quality = q
	match q:
		0:
			vp.scaling_3d_scale = 0.7
			vp.msaa_3d = Viewport.MSAA_DISABLED
			vp.screen_space_aa = Viewport.SCREEN_SPACE_AA_FXAA
			sun.shadow_enabled = false
			env.glow_enabled = true
			env.set_glow_level(3, 0.0)
			env.set_glow_level(4, 0.0)
			env.fog_enabled = true
		1:
			vp.scaling_3d_scale = 0.85
			vp.msaa_3d = Viewport.MSAA_DISABLED
			vp.screen_space_aa = Viewport.SCREEN_SPACE_AA_FXAA
			sun.shadow_enabled = true
			sun.directional_shadow_max_distance = 40.0
			env.glow_enabled = true
			env.set_glow_level(3, 0.6)
			env.set_glow_level(4, 0.0)
		2:
			vp.scaling_3d_scale = 1.0
			vp.msaa_3d = Viewport.MSAA_2X
			vp.screen_space_aa = Viewport.SCREEN_SPACE_AA_DISABLED
			sun.shadow_enabled = true
			sun.directional_shadow_max_distance = 55.0
			env.glow_enabled = true
			env.set_glow_level(3, 0.6)
			env.set_glow_level(4, 0.4)
	vp.scaling_3d_mode = Viewport.SCALING_3D_MODE_BILINEAR
