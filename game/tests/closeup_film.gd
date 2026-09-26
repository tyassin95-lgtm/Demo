extends Node3D
## Close-up contact sheet of the player and enemy styles (back, three-quarter and front
## views), a spawn dissolve and the near-camera fade, for reviewing character materials
## and accessories. Needs a display:
## godot --path . --rendering-method mobile res://tests/closeup_film.tscn -- <out.png>

const FRAME := Vector2i(480, 360)

var frames: Array[Image] = []
var visuals: Array[CharacterVisual] = []
var cam: Camera3D


func _ready() -> void:
	_setup_environment()
	var floor_mesh := MeshInstance3D.new()
	var pm := PlaneMesh.new()
	pm.size = Vector2(40, 40)
	floor_mesh.mesh = pm
	var fm := StandardMaterial3D.new()
	fm.albedo_color = Color(0.18, 0.19, 0.25)
	fm.roughness = 0.5
	floor_mesh.material_override = fm
	add_child(floor_mesh)
	var player := Player.new()
	_add_visual(player.model_path, player.style, 1.0, Vector3(-3.3, 0, 0), "arc_blade")
	player.free()
	var x := -1.1
	for k in [Enemy.Kind.STRIKER, Enemy.Kind.GUNNER, Enemy.Kind.BRUTE]:
		var e := Enemy.new()
		e.setup(k)
		var wid: String = ["enemy_blade", "enemy_rifle", "enemy_heavy"][k]
		_add_visual(e.model_path, e.style, e.visual_scale, Vector3(x, 0, 0), wid)
		e.free()
		x += 2.2
	cam = Camera3D.new()
	cam.fov = 40.0
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


func _add_visual(model_path: String, style: Dictionary, s: float, pos: Vector3, weapon_id: String) -> void:
	var v := CharacterVisual.new()
	add_child(v)
	v.build(model_path, style)
	v.scale = Vector3.ONE * s
	v.position = pos
	v.show_weapon(WeaponDB.weapon(weapon_id))
	if weapon_id == "enemy_heavy" and v.blade:
		v.blade.visible = false
	v.anim.set_base("idle_blade" if v.blade and v.blade.visible else "idle", 0.0)
	visuals.append(v)


func _tick(n: int) -> void:
	for i in n:
		await get_tree().process_frame
		for v in visuals:
			v.tick(1.0 / 60.0)


func _snap() -> void:
	await RenderingServer.frame_post_draw
	var img := get_viewport().get_texture().get_image()
	img.resize(FRAME.x, FRAME.y)
	frames.append(img)


## Frames the camera on a character from a yaw angle (0 = behind, like gameplay).
func _view(v: CharacterVisual, yaw_deg: float, dist: float = 3.2, height: float = 1.55) -> void:
	var h := v.scale.x
	var target := v.global_position + Vector3(0, 1.15 * h, 0)
	# Characters face -Z, so "behind" is +Z.
	var dir := Vector3(sin(deg_to_rad(yaw_deg)), 0, cos(deg_to_rad(yaw_deg)))
	cam.global_position = v.global_position + dir * dist * h + Vector3(0, height * h, 0)
	cam.look_at(target)


func _run() -> void:
	await _tick(30)
	for yaw in [0.0, 35.0, 180.0]:
		for v in visuals:
			_view(v, yaw)
			await _tick(1)
			await _snap()
	# Spawn/death dissolve on the striker (visor, pack and weapon must dissolve too).
	var s := visuals[1]
	for d in [0.15, 0.35, 0.5, 0.65, 0.8, 0.95]:
		s._dissolve = d
		s._dissolve_target = d
		_view(s, 160.0)
		await _tick(1)
		await _snap()
	s._dissolve = 0.0
	s._dissolve_target = 0.0
	# Near-camera screen-door fade on the player.
	var p := visuals[0]
	for f in [0.3, 0.6]:
		p.set_fade(f)
		_view(p, 0.0, 1.2)
		await _tick(1)
		await _snap()
	var cols := 4
	var rows := int(ceil(frames.size() / float(cols)))
	var sheet := Image.create(FRAME.x * cols, FRAME.y * rows, false, frames[0].get_format())
	for i in frames.size():
		sheet.blit_rect(frames[i], Rect2i(Vector2i.ZERO, FRAME), Vector2i((i % cols) * FRAME.x, (i / cols) * FRAME.y))
	var out: String = OS.get_cmdline_user_args()[0] if OS.get_cmdline_user_args().size() > 0 else "user://closeup.png"
	sheet.save_png(out)
	print("saved ", out, " frames=", frames.size())
	get_tree().quit()
