extends Node3D
## Character lineup (player and enemy styles, front and back) at high resolution, for
## reviewing outfits, hair and faces. Needs a display:
## godot --path . --rendering-method mobile res://tests/lineup.tscn -- <out.png> [zoom] [x] [y]

var visuals: Array[CharacterVisual] = []
var cam: Camera3D


func _ready() -> void:
	_setup_environment()
	var floor_mesh := MeshInstance3D.new()
	var pm := PlaneMesh.new()
	pm.size = Vector2(40, 40)
	floor_mesh.mesh = pm
	var fm := StandardMaterial3D.new()
	fm.albedo_color = Color(0.2, 0.22, 0.3)
	floor_mesh.material_override = fm
	add_child(floor_mesh)
	for i in Player.FIGHTERS.size():
		var look := Player.fighter_look(i)
		_add(look["model"], look["style"], 1.0, Vector3(-4.0 + i * 1.6, 0, 0), "arc_blade")
	var x := -0.8
	for k in [Enemy.Kind.STRIKER, Enemy.Kind.GUNNER, Enemy.Kind.BRUTE]:
		var e := Enemy.new()
		e.setup(k)
		_add(e.model_path, e.style, e.visual_scale, Vector3(x, 0, 0), ["enemy_blade", "enemy_rifle", "enemy_heavy"][k])
		e.free()
		x += 1.6 if k != Enemy.Kind.GUNNER else 1.9
	cam = Camera3D.new()
	cam.fov = 30.0
	add_child(cam)
	cam.current = true
	_run.call_deferred()


func _setup_environment() -> void:
	# Same look as the arena (sky ambient, ACES, glow, dusk sun + cool fill).
	var we := WorldEnvironment.new()
	var env := Environment.new()
	var sky := Sky.new()
	var sm := ShaderMaterial.new()
	sm.shader = load("res://shaders/sky.gdshader")
	sky.sky_material = sm
	sky.radiance_size = Sky.RADIANCE_SIZE_64
	env.background_mode = Environment.BG_SKY
	env.sky = sky
	env.ambient_light_source = Environment.AMBIENT_SOURCE_SKY
	env.ambient_light_sky_contribution = 0.3
	env.ambient_light_color = Color(0.24, 0.28, 0.38)
	env.reflected_light_source = Environment.REFLECTION_SOURCE_SKY
	env.tonemap_mode = Environment.TONE_MAPPER_ACES
	env.tonemap_exposure = 1.05
	env.tonemap_white = 6.0
	env.glow_enabled = true
	env.glow_hdr_threshold = 0.85
	we.environment = env
	add_child(we)
	var sun := DirectionalLight3D.new()
	sun.rotation_degrees = Vector3(-28.0, -125.0, 0.0)
	sun.light_color = Color(1.0, 0.78, 0.62)
	sun.light_energy = 1.35
	sun.shadow_enabled = true
	add_child(sun)
	var fill := DirectionalLight3D.new()
	fill.rotation_degrees = Vector3(-35.0, 60.0, 0.0)
	fill.light_color = Color(0.45, 0.6, 1.0)
	fill.light_energy = 0.35
	add_child(fill)


func _add(model_path: String, style: Dictionary, s: float, pos: Vector3, weapon_id: String) -> void:
	var v := CharacterVisual.new()
	add_child(v)
	v.build(model_path, style)
	v.scale = Vector3.ONE * s
	v.position = pos
	v.show_weapon(WeaponDB.weapon(weapon_id))
	if weapon_id == "enemy_heavy" and v.blade:
		v.blade.visible = false
	v.anim.set_base("idle", 0.0)
	visuals.append(v)


func _tick(n: int) -> void:
	for i in n:
		await get_tree().process_frame
		for v in visuals:
			v.tick(1.0 / 60.0)


func _run() -> void:
	var args := OS.get_cmdline_user_args()
	var out: String = args[0]
	var zoom := float(args[1]) if args.size() > 1 else 1.0
	var fx := float(args[2]) if args.size() > 2 else 0.1
	var fy := float(args[3]) if args.size() > 3 else 1.05
	await _tick(20)
	var imgs: Array[Image] = []
	for back in [false, true]:
		var z := 9.0 / zoom
		cam.global_position = Vector3(fx, fy + 0.2, -z if not back else z)
		cam.look_at(Vector3(fx, fy, 0))
		for v in visuals:
			v.rotation.y = 0.0
		await _tick(2)
		await RenderingServer.frame_post_draw
		imgs.append(get_viewport().get_texture().get_image())
	var w := imgs[0].get_width()
	var h := imgs[0].get_height()
	var sheet := Image.create(w, h * 2, false, imgs[0].get_format())
	for i in imgs.size():
		sheet.blit_rect(imgs[i], Rect2i(0, 0, w, h), Vector2i(0, h * i))
	sheet.save_png(out)
	print("saved ", out)
	get_tree().quit()
