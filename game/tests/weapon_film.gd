extends Node3D
## Filmstrip of ranged weapons and explosions for VFX review (needs a display).

var player: Player
var dummy: Enemy
var frames: Array[Image] = []
var labels: Array[String] = []


func drive(p: Player, _dt: float) -> void:
	p.input_move = Vector2.ZERO
	p.sprinting = false


func _ready() -> void:
	var arena_env := load("res://scripts/game/arena.gd")
	var we := WorldEnvironment.new()
	var e := Environment.new()
	e.background_mode = Environment.BG_COLOR
	e.background_color = Color(0.07, 0.08, 0.12)
	e.ambient_light_source = Environment.AMBIENT_SOURCE_COLOR
	e.ambient_light_color = Color(0.4, 0.42, 0.5)
	e.glow_enabled = true
	e.glow_hdr_threshold = 0.85
	e.tonemap_mode = Environment.TONE_MAPPER_ACES
	we.environment = e
	add_child(we)
	var sun := DirectionalLight3D.new()
	sun.rotation_degrees = Vector3(-45, 30, 0)
	add_child(sun)
	var body := StaticBody3D.new()
	body.collision_layer = Game.LAYER_WORLD
	add_child(body)
	for spec in [[Vector3(0, -0.5, 0), Vector3(80, 1, 80)], [Vector3(0, 2, -16), Vector3(20, 4, 1)]]:
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
	dummy = Enemy.new()
	dummy.setup(Enemy.Kind.BRUTE, 1.0)
	dummy.passive = true
	dummy.position = Vector3(0.5, 0.1, -9)
	add_child(dummy)
	dummy.max_health = 99999.0
	dummy.health = 99999.0
	_run.call_deferred()


func _snap(label: String) -> void:
	await RenderingServer.frame_post_draw
	var img := get_viewport().get_texture().get_image()
	img.resize(400, 300)
	frames.append(img)
	labels.append(label)


func _wait(n: int) -> void:
	for i in n:
		await get_tree().physics_frame


func _run() -> void:
	await _wait(40)
	player.cam.yaw = 0.0
	player.cam.pitch = deg_to_rad(-4.0)
	for w in [1, 2, 3]:
		player.weapons.switch_to(w)
		await _wait(20)
		for k in 3:
			player.attack_held = true
			player.weapons.press_primary("ground")
			player.weapons.hold_primary()
			await _wait(1)
			await _snap(player.weapons.current().short_name)
			var an := player.visual.anim
			print("[dbg] weapon=%s upper_w=%.2f upper_t=%.2f upper_state=%s base=%s act_w=%.2f action=%s" % [player.weapons.current().id, an._upper_weight, an._upper_target, an._upper_state, an.base_state, an._act_weight, an.action_name])
			player.attack_held = false
			await _wait(4)
			await _snap(player.weapons.current().short_name)
			await _wait(6)
	# Grenade.
	player.weapons.switch_to(1)
	await _wait(20)
	player.weapons.secondary_cd = 0.0
	player.weapons.press_secondary("ground")
	for k in 12:
		await _wait(4)
		await _snap("GRENADE")
	# Recoil jump.
	player.weapons.switch_to(2)
	await _wait(20)
	player.weapons.secondary_cd = 0.0
	player.weapons.press_secondary("ground")
	for k in 6:
		await _wait(3)
		await _snap("RECOIL")
	var cols := 6
	var rows := int(ceil(frames.size() / float(cols)))
	var sheet := Image.create(400 * cols, 300 * rows, false, frames[0].get_format())
	for i in frames.size():
		sheet.blit_rect(frames[i], Rect2i(0, 0, 400, 300), Vector2i((i % cols) * 400, (i / cols) * 300))
	sheet.save_png(OS.get_cmdline_user_args()[0])
	print("saved frames=", frames.size())
	get_tree().quit()
