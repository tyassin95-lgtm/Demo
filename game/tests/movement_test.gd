extends Node3D
## Automated movement/combat checks. Run headless:
##   godot --headless --path . --fixed-fps 60 res://tests/movement_test.tscn
## Prints measured metrics and PASS/FAIL per check, then quits with exit code.

var player: Player
var results: Array = []
var _floor: StaticBody3D


func _ready() -> void:
	_build_world()
	player = Player.new()
	add_child(player)
	player.global_position = Vector3(0, 0.1, 0)
	player.god_mode = true
	await _frames(10)
	await _run_all()
	var failed := 0
	for r in results:
		print(("PASS  " if r[1] else "FAIL  ") + r[0] + "  " + r[2])
		if not r[1]:
			failed += 1
	print("RESULT: %d/%d passed" % [results.size() - failed, results.size()])
	get_tree().quit(1 if failed > 0 else 0)


func _build_world() -> void:
	_floor = StaticBody3D.new()
	_floor.collision_layer = Game.LAYER_WORLD
	add_child(_floor)
	_add_box(Vector3(0, -0.5, 0), Vector3(200, 1, 200))
	# A tall wall at x = 12 for wall jumps / wall runs.
	_add_box(Vector3(12.5, 5, 0), Vector3(1, 10, 60))


func _add_box(c: Vector3, s: Vector3) -> void:
	var cs := CollisionShape3D.new()
	var b := BoxShape3D.new()
	b.size = s
	cs.shape = b
	cs.position = c
	_floor.add_child(cs)


func _frames(n: int) -> void:
	for i in n:
		await get_tree().physics_frame


func _check(name: String, ok: bool, detail: String) -> void:
	results.append([name, ok, detail])


func _reset(pos: Vector3 = Vector3.ZERO, yaw: float = 0.0) -> void:
	player.global_position = pos + Vector3(0, 0.05, 0)
	player.velocity = Vector3.ZERO
	player.set_state(Actor.State.NORMAL)
	player.stamina = Player.STAMINA_MAX
	player.cam.yaw = yaw
	player.input_move = Vector2.ZERO
	player.bot = self
	_move = Vector2.ZERO
	_sprint = false
	await _frames(20)


# The test acts as the player's input driver.
var _move := Vector2.ZERO
var _sprint := false
var _jump_hold := false


func drive(p: Player, _dt: float) -> void:
	p.input_move = _move
	p.sprinting = _sprint and _move.length() > 0.4
	p.jump_held = _jump_hold


func _run_all() -> void:
	# 1. Acceleration to run speed.
	await _reset()
	_move = Vector2(0, 1)
	var t := 0
	while Vector3(player.velocity.x, 0, player.velocity.z).length() < Player.RUN_SPEED * 0.95 and t < 60:
		await _frames(1)
		t += 1
	_check("run acceleration", t <= 10, "%.3fs to 95%% run speed (%.1f m/s)" % [t / 60.0, Player.RUN_SPEED])
	# 2. Stop quickly.
	await _frames(30)
	_move = Vector2.ZERO
	t = 0
	while Vector3(player.velocity.x, 0, player.velocity.z).length() > 0.3 and t < 60:
		await _frames(1)
		t += 1
	_check("stopping", t <= 12, "%.3fs to stop from run" % (t / 60.0))
	# 3. Sprint speed.
	await _reset()
	_move = Vector2(0, 1)
	_sprint = true
	await _frames(40)
	var sp := Vector3(player.velocity.x, 0, player.velocity.z).length()
	var expect := Player.SPRINT_SPEED * player.weapons.current().move_speed_mult
	_check("sprint speed", absf(sp - expect) < 0.4, "%.2f m/s (expected %.2f)" % [sp, expect])
	var st_before := player.stamina
	await _frames(60)
	_check("sprint drains stamina", player.stamina < st_before - 5.0, "stamina %.0f -> %.0f" % [st_before, player.stamina])
	_sprint = false
	# 4. Jump height (full hold) and short hop (tap).
	await _reset()
	_jump_hold = true
	player.press("jump")
	var y0 := player.global_position.y
	var peak := y0
	var air_frames := 0
	await _frames(1)
	while not player.is_on_floor() or air_frames < 3:
		await _frames(1)
		air_frames += 1
		peak = maxf(peak, player.global_position.y)
		if air_frames > 180:
			break
	var h := peak - y0
	_check("full jump height", h > 1.7 and h < 2.4, "%.2f m, airtime %.2fs" % [h, air_frames / 60.0])
	await _reset()
	_jump_hold = false
	player.press("jump")
	peak = player.global_position.y
	y0 = peak
	air_frames = 0
	await _frames(1)
	while not player.is_on_floor() or air_frames < 3:
		await _frames(1)
		air_frames += 1
		peak = maxf(peak, player.global_position.y)
		if air_frames > 180:
			break
	_check("short hop (jump cut)", peak - y0 < h * 0.75, "%.2f m" % (peak - y0))
	_jump_hold = true
	# 5. Ground dash distance + i-frames.
	await _reset()
	_move = Vector2(0, 1)
	await _frames(1)
	var p0 := player.global_position
	player.press("dash")
	await _frames(2)
	var inv := player.invuln > 0.0
	await _frames(12)
	var dash_d := (player.global_position - p0).length()
	_check("dash distance", dash_d > 3.5 and dash_d < 6.5, "%.2f m in 0.23s, iframes=%s" % [dash_d, str(inv)])
	_move = Vector2.ZERO
	# 6. Air dash keeps altitude.
	await _reset()
	player.press("jump")
	await _frames(20)
	var ya := player.global_position.y
	player.press("dash")
	await _frames(8)
	var yb := player.global_position.y
	_check("air dash hover", absf(yb - ya) < 0.3 and player.air_dashes == 0, "dy=%.2f m" % (yb - ya))
	# 7. Wall jump: run at the wall, jump, jump again at the wall.
	await _reset(Vector3(8, 0, 0), deg_to_rad(-90.0))
	_move = Vector2(0, 1)
	await _frames(20)
	player.press("jump")
	await _frames(18)
	var vx_before := player.velocity.x
	player.press("jump")
	await _frames(3)
	var vx_after := player.velocity.x
	var vy_after := player.velocity.y
	_check("wall jump", vx_before >= -0.5 and vx_after < -5.0 and vy_after > 6.0, "vx %.1f -> %.1f, vy %.1f" % [vx_before, vx_after, vy_after])
	_move = Vector2.ZERO
	# 8. Wall run: sprint-jump alongside the wall.
	await _reset(Vector3(11.2, 0, -12), deg_to_rad(180.0))
	_move = Vector2(0, 1)
	_sprint = true
	await _frames(40)
	player.press("jump")
	var ran := false
	var max_t := 0.0
	for i in 60:
		await _frames(1)
		if player.wallrun_timer > 0.0:
			ran = true
			max_t = maxf(max_t, Player.WALLRUN_TIME - player.wallrun_timer)
	_check("wall run engages", ran, "wall-ran %.2fs" % max_t)
	_sprint = false
	_move = Vector2.ZERO
	# 9. Melee combo chain: three presses -> three attacks.
	await _reset()
	var started: Array = []
	var cb := func(id: String) -> void: started.append(id)
	player.weapons.attack_started.connect(cb)
	for i in 3:
		player.press("attack")
		await _frames(14)
	await _frames(40)
	player.weapons.attack_started.disconnect(cb)
	_check("blade 3-hit combo", started.size() >= 3 and started[2] == "blade_3", str(started))
	# 10. Dash-cancel attack recovery.
	await _reset()
	player.press("attack")
	await _frames(16)
	player.press("dash")
	await _frames(3)
	_check("dash cancels attack recovery", player.state == Actor.State.DASH, "state=%s" % Actor.State.keys()[player.state])
	# 11. Weapon switch + fire.
	await _reset()
	player.weapons.switch_to(1)
	await _frames(20)
	var ammo0: int = player.weapons.ammo[1]
	player.attack_held = true
	player.bot = null
	for i in 20:
		player.weapons.hold_primary()
		await _frames(1)
	player.bot = self
	_check("rifle fires & consumes ammo", player.weapons.ammo[1] < ammo0, "ammo %d -> %d" % [ammo0, player.weapons.ammo[1]])
	player.weapons.switch_to(0)
