extends Node3D
## Renders a side-view filmstrip of the player's movement set for animation review.
## Run (needs a display): godot --path . --fixed-fps 30 res://tests/anim_film.tscn -- <out.png>

var player: Player
var cam: Camera3D
var frames: Array[Image] = []
var _move := Vector2.ZERO
var _crouch := false


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
	e.glow_enabled = true
	we.environment = e
	add_child(we)
	var sun := DirectionalLight3D.new()
	sun.rotation_degrees = Vector3(-45, 30, 0)
	add_child(sun)
	var body := StaticBody3D.new()
	body.collision_layer = Game.LAYER_WORLD
	add_child(body)
	for spec in [[Vector3(0, -0.5, 0), Vector3(400, 1, 40)], [Vector3(60, 4, -3.0), Vector3(40, 8, 1)]]:
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
		mi.position = spec[0]
		add_child(mi)
	player = Player.new()
	add_child(player)
	player.global_position = Vector3(0, 0.1, 0)
	player.god_mode = true
	player.bot = self
	player.cam.camera.current = false
	player.weapons.attack_started.connect(func(id: String) -> void: print("[film] attack ", id, " on_floor=", player.is_on_floor(), " y=", player.global_position.y))
	cam = Camera3D.new()
	add_child(cam)
	cam.current = true
	cam.fov = 45
	_run.call_deferred()


func _snap() -> void:
	await RenderingServer.frame_post_draw
	var img := get_viewport().get_texture().get_image()
	img.resize(320, 240)
	frames.append(img)


func _step(n: int, every: int = 4) -> void:
	for i in n:
		await get_tree().physics_frame
		cam.global_position = player.global_position + Vector3(0, 1.3, 7.0)
		cam.look_at(player.global_position + Vector3(0, 1.1, 0))
		if i % every == 0:
			await _snap()


func _run() -> void:
	player.cam.yaw = deg_to_rad(-90.0)
	await _step(10, 100)
	_move = Vector2(0, 0.6)
	await _step(16)        # jog
	_move = Vector2(0, 1)
	player.press("sprint")
	await _step(20)        # sprint (double-tap)
	player.press("jump")
	await _step(24)        # sprint hop (air dash)
	player.sprinting = false
	_move = Vector2(0, 0.8)
	await _step(8)
	player.press("jump")
	await _step(40)        # somersault jump
	_move = Vector2(1, 0)
	await _step(8)         # strafe (body keeps facing the camera)
	player.press("jump")
	await _step(30)        # side dodge right: duck and slide + end lag
	_move = Vector2(-1, 0)
	player.press("jump")
	await _step(8)         # side dodge left...
	_move = Vector2.ZERO
	player.press("jump")
	await _step(12)        # ...jump-canceled
	_move = Vector2(1, 0)
	player.press("jump")
	await _step(28)        # air dodge
	# Wall jump: run at the wall (face z = -2.5), jump, kick.
	_move = Vector2.ZERO
	player.global_position = Vector3(60, 0.1, 3.0)
	player.velocity = Vector3.ZERO
	player.cam.yaw = 0.0
	await _step(8)
	_move = Vector2(0, 1)
	await _step(8)
	player.press("jump")
	var kicked := false
	for i in 44:
		await _step(1, 1 if i % 3 == 0 else 99)
		if not kicked and player.global_position.z < -1.5:
			player.press("jump")
			kicked = true
	_move = Vector2.ZERO
	player.cam.yaw = deg_to_rad(-90.0)
	await _step(12)
	_crouch = true
	_move = Vector2(0, 0.7)
	await _step(20)        # crouch walk
	_crouch = false
	_move = Vector2.ZERO
	await _step(8)
	for k in 3:
		player.press("attack")
		await _step(12)    # combo
	await _step(12)
	var cols := 8
	var rows := int(ceil(frames.size() / float(cols)))
	var sheet := Image.create(320 * cols, 240 * rows, false, frames[0].get_format())
	for i in frames.size():
		sheet.blit_rect(frames[i], Rect2i(0, 0, 320, 240), Vector2i((i % cols) * 320, (i / cols) * 240))
	var out: String = OS.get_cmdline_user_args()[0]
	sheet.save_png(out)
	print("saved ", out, " frames=", frames.size())
	get_tree().quit()
