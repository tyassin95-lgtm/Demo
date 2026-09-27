extends Node3D
## Close-up filmstrip of the S4-style moves (somersault jump, side dodge, air dodge,
## wall jump, strafing, crouch walk) for animation review. Needs a display:
## godot --path . --rendering-method mobile --fixed-fps 60 res://tests/moves_film.tscn -- <out.png>

const FRAME := Vector2i(400, 300)

var player: Player
var cam: Camera3D
var frames: Array[Image] = []
var _move := Vector2.ZERO
var _crouch := false
## Camera offset from the player (world space), set per segment.
var _cam_off := Vector3(3.2, 1.6, 3.2)


func drive(p: Player, _dt: float) -> void:
	p.input_move = _move
	p.crouch_held = _crouch


func _ready() -> void:
	var we := WorldEnvironment.new()
	var e := Environment.new()
	e.background_mode = Environment.BG_COLOR
	e.background_color = Color(0.12, 0.13, 0.17)
	e.ambient_light_source = Environment.AMBIENT_SOURCE_COLOR
	e.ambient_light_color = Color(0.5, 0.52, 0.6)
	e.tonemap_mode = Environment.TONE_MAPPER_ACES
	e.glow_enabled = true
	we.environment = e
	add_child(we)
	var sun := DirectionalLight3D.new()
	sun.rotation_degrees = Vector3(-45, 30, 0)
	sun.shadow_enabled = true
	add_child(sun)
	var body := StaticBody3D.new()
	body.collision_layer = Game.LAYER_WORLD
	add_child(body)
	# Floor with a grid texture feel (two tones), and a wall (face z = -2.5) for kicks.
	for spec in [[Vector3(0, -0.5, 0), Vector3(200, 1, 200), Color(0.3, 0.32, 0.38)], [Vector3(60, 4, -3.0), Vector3(40, 8, 1), Color(0.45, 0.47, 0.55)]]:
		var cs := CollisionShape3D.new()
		var b := BoxShape3D.new()
		b.size = spec[1]
		cs.shape = b
		cs.position = spec[0]
		body.add_child(cs)
		var mi := MeshInstance3D.new()
		var bm := BoxMesh.new()
		bm.size = spec[1]
		mi.mesh = bm
		var m := StandardMaterial3D.new()
		m.albedo_color = spec[2]
		mi.material_override = m
		mi.position = spec[0]
		add_child(mi)
	player = Player.new()
	add_child(player)
	player.global_position = Vector3(0, 0.1, 0)
	player.god_mode = true
	player.bot = self
	player.cam.camera.current = false
	cam = Camera3D.new()
	add_child(cam)
	cam.current = true
	cam.fov = 50
	_run.call_deferred()


func _snap() -> void:
	await RenderingServer.frame_post_draw
	var img := get_viewport().get_texture().get_image()
	img.resize(FRAME.x, FRAME.y)
	frames.append(img)


func _step(n: int, every: int = 3) -> void:
	for i in n:
		await get_tree().physics_frame
		var p := player.global_position
		cam.global_position = p + _cam_off
		cam.look_at(p + Vector3(0, 1.0, 0))
		if i % every == 0:
			await _snap()


func _place(pos: Vector3, yaw: float) -> void:
	_move = Vector2.ZERO
	player.global_position = pos
	player.velocity = Vector3.ZERO
	player.stamina = Player.STAMINA_MAX
	player.cam.yaw = yaw
	await _step(12, 99)


func _run() -> void:
	# Camera looks from the player's right-front so flips and slides read clearly.
	_cam_off = Vector3(4.2, 1.4, 1.2)
	await _place(Vector3(0, 0.1, 0), 0.0)
	_move = Vector2(0, 0.5)
	await _step(6, 99)
	player.press("jump")
	await _step(42)        # somersault jump (moving forward)
	await _place(Vector3(0, 0.1, 0), 0.0)
	_cam_off = Vector3(0.8, 1.5, 4.6)
	_move = Vector2(1, 0)
	player.press("jump")
	await _step(33)        # side dodge right + end lag
	await _place(Vector3(0, 0.1, 0), 0.0)
	player.press("jump")
	await _step(9, 99)
	_move = Vector2(-1, 0)
	player.press("jump")
	await _step(36)        # air dodge left
	_move = Vector2.ZERO
	# Wall jump: face the wall, run in, jump, kick.
	_cam_off = Vector3(5.0, 1.8, 2.5)
	await _place(Vector3(60, 0.1, 1.4), 0.0)
	_move = Vector2(0, 1)
	await _step(8, 99)
	player.press("jump")
	var kicked := false
	for i in 54:
		await _step(1, 1 if i % 3 == 0 else 99)
		if not kicked and player.global_position.z < -1.45 and not player.is_on_floor():
			player.press("jump")
			kicked = true
			print("[film] wall kick pressed at z=%.2f y=%.2f" % [player.global_position.z, player.global_position.y])
		if player.wall_plant > 0.0:
			print("[film] planted at z=%.2f y=%.2f" % [player.global_position.z, player.global_position.y])
	# Strafe run and crouch walk.
	_cam_off = Vector3(0.6, 1.6, 4.2)
	await _place(Vector3(0, 0.1, 0), 0.0)
	_move = Vector2(1, 0)
	await _step(15)
	_move = Vector2(0, -1)
	await _step(12)
	_crouch = true
	_move = Vector2(0, 0.8)
	await _step(18)
	var cols := 5
	var rows := int(ceil(frames.size() / float(cols)))
	var sheet := Image.create(FRAME.x * cols, FRAME.y * rows, false, frames[0].get_format())
	for i in frames.size():
		sheet.blit_rect(frames[i], Rect2i(Vector2i.ZERO, FRAME), Vector2i((i % cols) * FRAME.x, (i / cols) * FRAME.y))
	var out: String = OS.get_cmdline_user_args()[0]
	sheet.save_png(out)
	print("saved ", out, " frames=", frames.size())
	get_tree().quit()
