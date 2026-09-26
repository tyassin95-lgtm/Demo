extends Node
## Automation driver for testing and screenshots: plays the player character by
## chasing enemies, using every weapon, jumping, dashing and wall-kicking, and
## logs match statistics once per second.

var target: Actor = null
var _t := 0.0
var _log_t := 0.0
var _weapon_t := 0.0
var _jump_t := 1.5
var _dash_t := 2.5
var _special_t := 4.0
var _strafe := 1.0
var weapon_cycle := true
var stats := {"jumps": 0, "dashes": 0, "attacks": 0, "wall_jumps": 0, "specials": 0}


func drive(p: Player, dt: float) -> void:
	_t += dt
	_log_t += dt
	_weapon_t += dt
	_jump_t -= dt
	_dash_t -= dt
	_special_t -= dt
	if target == null or not is_instance_valid(target) or not target.is_alive():
		target = _nearest(p)
	p.attack_held = false
	p.jump_held = true
	p.sprinting = false
	if target == null:
		p.input_move = Vector2(sin(_t * 0.7), 0.6)
		return
	var to := target.global_position - p.global_position
	var flat := Vector3(to.x, 0, to.z)
	var dist := flat.length()
	# Aim the camera at the target.
	var aim := target.chest_position() - p.cam.camera.global_position
	var want_yaw := atan2(-aim.x, -aim.z)
	var want_pitch := atan2(aim.y, Vector2(aim.x, aim.z).length())
	p.cam.yaw = lerp_angle(p.cam.yaw, want_yaw, clampf(dt * 8.0, 0.0, 1.0))
	p.cam.pitch = lerpf(p.cam.pitch, clampf(want_pitch, -0.9, 0.8), clampf(dt * 6.0, 0.0, 1.0))
	var melee := p.weapons.is_melee()
	var ideal := 2.0 if melee else 11.0
	var fwd := clampf((dist - ideal) * 0.4, -1.0, 1.0)
	if _t > 3.0 and int(_t / 3.0) % 2 == 0:
		_strafe = -_strafe if randf() < 0.02 else _strafe
	p.input_move = Vector2(0.55 * _strafe if not melee or dist > 4.0 else 0.0, fwd).limit_length(1.0)
	p.sprinting = dist > 8.0 and p.stamina > 30.0
	if melee:
		if dist < 3.2:
			p.press("attack")
			stats["attacks"] += 1
		elif dist < 9.0 and p.sprinting and randf() < 0.05:
			p.press("attack")
			stats["attacks"] += 1
	else:
		p.attack_held = dist < 45.0
		if p.attack_held:
			stats["attacks"] += 1
	if _jump_t <= 0.0:
		_jump_t = randf_range(1.2, 3.0)
		p.press("jump")
		stats["jumps"] += 1
	if _dash_t <= 0.0 and p.stamina > 40.0:
		_dash_t = randf_range(1.5, 3.5)
		p.press("dash")
		stats["dashes"] += 1
	if _special_t <= 0.0:
		_special_t = randf_range(3.0, 6.0)
		if p.weapons.current().secondary != WeaponDB.Secondary.SCOPE:
			p.press("special")
			stats["specials"] += 1
	if weapon_cycle and _weapon_t > 9.0:
		_weapon_t = 0.0
		p.weapons.cycle(1)
	if p.overdrive >= 100.0:
		p.activate_overdrive()
	if _log_t >= 1.0:
		_log_t = 0.0
		_log(p)


func _nearest(p: Player) -> Actor:
	var best: Actor = null
	var bd := INF
	for a in Game.hostiles_of(p.team):
		var d: float = (a as Actor).global_position.distance_to(p.global_position)
		if d < bd:
			bd = d
			best = a
	return best


func _log(p: Player) -> void:
	var d: Node = p.get_parent().get_node_or_null("Director")
	var wave := -1
	var score := 0
	var left := 0
	if d:
		wave = d.wave
		score = d.score
		left = d.enemies_remaining()
	print("[bot] t=%.0f hp=%.0f sp=%.0f state=%s weapon=%s wave=%d left=%d kills=%d score=%d combo=%d best=%d od=%.0f pos=%s" % [
		_t, p.health, p.stamina, Actor.State.keys()[p.state], p.weapons.current().id, wave + 1, left, p.kills, score, p.combo,
		p.best_combo, p.overdrive, str(p.global_position.snapped(Vector3(0.1, 0.1, 0.1)))])
