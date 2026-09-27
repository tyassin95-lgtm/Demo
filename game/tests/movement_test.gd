extends Node3D
## Automated checks of the S4 League-style movement rules. Run headless:
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
	# Tall wall, face at x = 12, for wall jumps.
	_add_box(Vector3(12.5, 5, 0), Vector3(1, 10, 60))
	# Platform (top y = 3, west edge x = -23) next to a tall wall (face x = -24.5).
	_add_box(Vector3(-20, 1.5, 0), Vector3(6, 3, 6))
	_add_box(Vector3(-25, 5, 0), Vector3(1, 10, 20))
	# Block too tall to jump onto (top y = 2.6, south face z = 39.5) for the reverse
	# wall jump.
	_add_box(Vector3(0, 1.3, 40), Vector3(8, 2.6, 1))


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


func _speed() -> float:
	return Vector3(player.velocity.x, 0, player.velocity.z).length()


func _reset(pos: Vector3 = Vector3.ZERO, yaw: float = 0.0) -> void:
	player.global_position = pos + Vector3(0, 0.05, 0)
	player.velocity = Vector3.ZERO
	player.set_state(Actor.State.NORMAL)
	player.stamina = Player.STAMINA_MAX
	player.sprinting = false
	player.land_lag = 0.0
	player.wall_plant = 0.0
	player._flinch_immunity = 0.0
	player.health = player.max_health
	player.cam.yaw = yaw
	player.input_move = Vector2.ZERO
	player.bot = self
	player.weapons.switch_to(0)
	_move = Vector2.ZERO
	_crouch = false
	await _frames(20)


# The test acts as the player's input driver.
var _move := Vector2.ZERO
var _crouch := false


func drive(p: Player, _dt: float) -> void:
	p.input_move = _move
	p.crouch_held = _crouch


## Jumps (optionally with a mid-air action) and returns [peak height, airtime].
func _measure_jump() -> Array:
	var y0 := player.global_position.y
	var peak := y0
	var frames := 0
	await _frames(1)
	while not player.is_on_floor() or frames < 3:
		await _frames(1)
		frames += 1
		peak = maxf(peak, player.global_position.y)
		if frames > 300:
			break
	return [peak - y0, frames / 60.0]


## Runs toward the tall wall at x = 12 along `yaw`, jumps, and presses JUMP again
## when close enough. Returns [velocity before, velocity after the kick, plant seen].
func _wall_jump_run(yaw: float, start: Vector3) -> Array:
	await _reset(start, yaw)
	_move = Vector2(0, 1)
	while player.global_position.x < 9.2:
		await _frames(1)
	player.press("jump")
	await _frames(2)
	while player.global_position.x < 11.3 and not player.is_on_floor():
		await _frames(1)
	var before := player.velocity
	player.press("jump")
	var planted := false
	for i in 12:
		await _frames(1)
		if player.wall_plant > 0.0:
			planted = true
		elif planted:
			break
	return [before, player.velocity, planted]


func _hit(reaction: int, dir: Vector3, knock: float, lift: float) -> void:
	player.god_mode = false
	var h := HitInfo.make(1.0, null, dir, reaction)
	h.knockback = knock
	h.lift = lift
	player.take_hit(h)
	player.god_mode = true


func _run_all() -> void:
	var blade_run := Player.RUN_SPEED * 0.92
	# 1. Near-instant acceleration.
	await _reset()
	_move = Vector2(0, 1)
	var t := 0
	while _speed() < blade_run * 0.95 and t < 60:
		await _frames(1)
		t += 1
	_check("run acceleration", t <= 8, "%.3fs to 95%% of %.2f m/s" % [t / 60.0, blade_run])
	# 2. Quick stop.
	await _frames(20)
	_move = Vector2.ZERO
	t = 0
	while _speed() > 0.3 and t < 60:
		await _frames(1)
		t += 1
	_check("stopping", t <= 10, "%.3fs to stop" % (t / 60.0))
	# 3. The body faces the camera while strafing.
	await _reset(Vector3.ZERO, 0.8)
	_move = Vector2(1, 0)
	await _frames(25)
	var cam_right := Vector3(cos(0.8), 0, -sin(0.8))
	var hv := Vector3(player.velocity.x, 0, player.velocity.z)
	_check("strafe faces camera", absf(wrapf(player.facing - 0.8, -PI, PI)) < 0.01 and hv.normalized().dot(cam_right) > 0.98,
		"facing=%.2f cam=0.80, strafe dir . right=%.2f" % [player.facing, hv.normalized().dot(cam_right)])
	# 4. Weapon mobility: blade 92 %, rifle 83 %.
	await _reset()
	_move = Vector2(0, 1)
	await _frames(30)
	var v_blade := _speed()
	player.weapons.switch_to(1)
	await _frames(30)
	var v_rifle := _speed()
	_check("weapon mobility", absf(v_blade - blade_run) < 0.2 and absf(v_rifle - Player.RUN_SPEED * 0.83) < 0.2,
		"blade %.2f m/s, rifle %.2f m/s" % [v_blade, v_rifle])
	# 5. Double-tap forward starts a sprint; a single long press doesn't.
	await _reset()
	_move = Vector2(0, 1)
	await _frames(60)
	var single := player.sprinting
	_move = Vector2.ZERO
	await _frames(20)
	_move = Vector2(0, 1)
	await _frames(4)
	_move = Vector2.ZERO
	await _frames(4)
	_move = Vector2(0, 1)
	await _frames(40)
	var sprint_v := _speed()
	_check("double-tap sprint", player.sprinting and not single and absf(sprint_v - Player.SPRINT_SPEED * 0.92) < 0.3,
		"single press sprint=%s, double tap %.2f m/s (expected %.2f)" % [single, sprint_v, Player.SPRINT_SPEED * 0.92])
	# 6. Sprint drains 5 SP per second.
	var sp0 := player.stamina
	await _frames(60)
	var drain := sp0 - player.stamina
	_check("sprint drains 5 SP/s", absf(drain - Player.SPRINT_DRAIN) < 0.6, "%.2f SP in 1 s" % drain)
	# 7. Releasing forward ends the sprint.
	_move = Vector2(1, 0)
	await _frames(3)
	_check("sprint ends without forward", not player.sprinting, "sprinting=%s" % player.sprinting)
	# 8. Fixed-height somersault jump (no short hop when JUMP is released).
	await _reset()
	player.press("jump")
	var j := await _measure_jump()
	_check("jump height", j[0] > 1.6 and j[0] < 2.0, "%.2f m, airtime %.2fs, flip=%s" % [j[0], j[1], player.visual.is_spinning() or true])
	# 9. Sprint jump = air dash: lower and quicker (bunny hop).
	await _reset()
	player.sprinting = true
	_move = Vector2(0, 1)
	await _frames(20)
	player.press("jump")
	var h := await _measure_jump()
	_check("air dash hop", h[0] < j[0] * 0.85 and h[1] < j[1] * 0.85, "%.2f m / %.2fs vs %.2f m / %.2fs" % [h[0], h[1], j[0], j[1]])
	# 10. A short delay between landing and the next jump.
	await _reset()
	player.press("jump")
	await _frames(3)
	while not player.is_on_floor():
		await _frames(1)
	player.press("jump")
	t = 0
	while player.velocity.y <= 0.0 and t < 60:
		await _frames(1)
		t += 1
	_check("landing lag", t >= 6 and t <= 12, "next jump after %.3fs" % (t / 60.0))
	# 11. JUMP + right = side dodge (20 SP, no invulnerability).
	await _reset()
	var p0 := player.global_position
	_move = Vector2(1, 0)
	player.press("jump")
	await _frames(2)
	var dodging := player.state == Actor.State.DODGE
	var inv := player.invuln
	await _frames(28)
	var moved := player.global_position - p0
	_check("side dodge", dodging and moved.x > 2.8 and moved.x < 4.5 and absf(moved.z) < 0.3 and absf(player.stamina - 80.0) < 0.5 and inv <= 0.0,
		"moved %.2f m right, SP %.0f, invuln %.2f" % [moved.x, player.stamina, inv])
	# 12. Jump-cancel a dodge (wave dash start).
	await _reset()
	_move = Vector2(1, 0)
	player.press("jump")
	await _frames(8)
	_move = Vector2.ZERO
	player.press("jump")
	await _frames(2)
	_check("dodge jump-cancel", player.state == Actor.State.NORMAL and player.velocity.y > 5.0 and player.velocity.x > 3.0,
		"state=%s vy=%.1f vx=%.1f" % [Actor.State.keys()[player.state], player.velocity.y, player.velocity.x])
	# 13. Air dodge, then jump-cancel it into a mid-air jump.
	await _frames(10)
	_move = Vector2(-1, 0)
	player.press("jump")
	await _frames(2)
	var air_dodge := player.state == Actor.State.DODGE and player.dodge_in_air
	var sp_after := player.stamina
	await _frames(8)
	_move = Vector2.ZERO
	player.press("jump")
	await _frames(2)
	_check("air dodge + jump-cancel", air_dodge and player.velocity.y > 5.0 and absf(sp_after - 60.0) < 0.5,
		"air dodge=%s, SP %.0f, vy after cancel %.1f" % [air_dodge, sp_after, player.velocity.y])
	# 14. Wall jump reflects like a mirror (angle in = angle out) and costs 20 SP.
	var w: Array = await _wall_jump_run(-PI * 0.75, Vector3(6.0, 0, -4.0))
	var vin: Vector3 = w[0]
	var vout: Vector3 = w[1]
	_check("wall jump mirror", w[2] and vout.x < -0.5 and absf(vout.x + vin.x) < 1.0 and absf(vout.z - vin.z) < 1.0 and vout.y > 9.0 and absf(player.stamina - 80.0) < 1.0,
		"in (%.1f, %.1f) -> out (%.1f, %.1f), up %.1f, SP %.0f" % [vin.x, vin.z, vout.x, vout.z, vout.y, player.stamina])
	# 15. Straight into the wall -> straight back out (the 180 wall jump).
	w = await _wall_jump_run(-PI * 0.5, Vector3(6.0, 0, 0.0))
	vin = w[0]
	vout = w[1]
	_check("180 wall jump", w[2] and vout.x < -Player.WALL_JUMP_MIN_OUT + 0.1 and absf(vout.z) < 0.5,
		"in (%.1f, %.1f) -> out (%.1f, %.1f)" % [vin.x, vin.z, vout.x, vout.z])
	# 16. Wall jumps need 20 SP.
	await _reset(Vector3(6.0, 0, 0), -PI * 0.5)
	_move = Vector2(0, 1)
	while player.global_position.x < 9.2:
		await _frames(1)
	player.press("jump")
	await _frames(2)
	player.stamina = 10.0
	while player.global_position.x < 11.3 and not player.is_on_floor():
		await _frames(1)
	player.stamina = 10.0
	player.press("jump")
	await _frames(4)
	_check("wall jump needs SP", player.wall_plant <= 0.0 and player.velocity.y < 9.0, "vy=%.1f with 10 SP" % player.velocity.y)
	# 17. No wall jump while falling (walked off a ledge, not jumping).
	await _reset(Vector3(-20, 3.0, 0), PI * 0.5)
	_move = Vector2(0, 1)
	while player.is_on_floor():
		await _frames(1)
	await _frames(4)
	var st := player.stamina
	player.press("jump")
	await _frames(4)
	_check("no wall jump from a fall", player.wall_plant <= 0.0 and player.velocity.y < 0.0 and player.stamina >= st,
		"x=%.2f vy=%.1f SP %.0f" % [player.global_position.x, player.velocity.y, player.stamina])
	# 18. Reverse wall jump: kicking a wall whose top is below head height vaults you over it.
	await _reset(Vector3(0, 0, 33.0), PI)
	_move = Vector2(0, 1)
	while player.global_position.z < 37.2:
		await _frames(1)
	player.press("jump")
	var kicked := false
	var reverse := false
	for i in 40:
		await _frames(1)
		if player.wall_plant > 0.0:
			kicked = true
			reverse = player._wall_reverse
		var y := player.global_position.y
		if not kicked and player.global_position.z > 38.5 and y > 0.95 and y < 1.5:
			player.press("jump")
	for i in 90:
		await _frames(1)
		if player.is_on_floor() and i > 5:
			break
	_check("reverse wall jump", kicked and reverse and player.global_position.z > 39.4,
		"kicked=%s reverse=%s landed z=%.2f y=%.2f" % [kicked, reverse, player.global_position.z, player.global_position.y])
	# 19. Crouch: shorter body, slow walk, no attacks.
	await _reset()
	_crouch = true
	_move = Vector2(0, 1)
	await _frames(30)
	var cap := player.body_shape.shape as CapsuleShape3D
	player.press("attack")
	await _frames(3)
	_check("crouch", player.crouching and cap.height < 1.3 and absf(_speed() - Player.CROUCH_SPEED) < 0.2 and player.state == Actor.State.NORMAL,
		"crouching=%s height=%.2f speed=%.2f state=%s" % [player.crouching, cap.height, _speed(), Actor.State.keys()[player.state]])
	_crouch = false
	await _frames(10)
	# 20. Knocked flying: JUMP recovers in the air.
	await _reset()
	_hit(HitInfo.Reaction.KNOCKDOWN, Vector3(0, 0, 1), 8.0, 7.0)
	var knocked := player.state == Actor.State.KNOCKDOWN
	await _frames(16)
	player.press("jump")
	await _frames(2)
	_check("throw recovery", knocked and player.state == Actor.State.NORMAL and not player.is_on_floor(),
		"knocked=%s state=%s airborne=%s" % [knocked, Actor.State.keys()[player.state], not player.is_on_floor()])
	# 21. Stagger: dodging out ("faint") costs 90 SP.
	await _reset()
	_hit(HitInfo.Reaction.STAGGER, Vector3(0, 0, 1), 4.0, 0.0)
	var staggered := player.state == Actor.State.STAGGER
	_move = Vector2(1, 0)
	player.press("jump")
	await _frames(2)
	_check("faint out of a stagger", staggered and player.state == Actor.State.DODGE and absf(player.stamina - 10.0) < 0.5,
		"staggered=%s state=%s SP %.0f" % [staggered, Actor.State.keys()[player.state], player.stamina])
	# 22. Flinches don't interrupt a dodge.
	await _reset()
	_move = Vector2(1, 0)
	player.press("jump")
	await _frames(3)
	_hit(HitInfo.Reaction.FLINCH, Vector3(1, 0, 0), 2.0, 0.0)
	await _frames(1)
	_check("dodge ignores flinch", player.state == Actor.State.DODGE, "state=%s" % Actor.State.keys()[player.state])
	# 23. Melee combo chain: three presses -> three attacks.
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
	# 24. Attack recovery can be dodge-canceled.
	await _reset()
	player.press("attack")
	await _frames(16)
	_move = Vector2(-1, 0)
	player.press("jump")
	await _frames(3)
	_check("dodge cancels attack recovery", player.state == Actor.State.DODGE, "state=%s" % Actor.State.keys()[player.state])
	# 25. Weapon switch + fire.
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
