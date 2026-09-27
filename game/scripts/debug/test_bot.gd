extends Node
## Automation driver for testing and screenshots: plays the player character by
## chasing enemies, using every weapon, sprinting, jumping, side-dodging and
## wall-jumping, and logs match statistics once per second.

var target: Actor = null
var _t := 0.0
var _log_t := 0.0
var _weapon_t := 0.0
var _jump_t := 1.5
var _dash_t := 2.5
var _dodge_side := 0.0
var _special_t := 4.0
var _strafe := 1.0
var weapon_cycle := false
var stats := {"jumps": 0, "dodges": 0, "attacks": 0, "wall_jumps": 0, "specials": 0}


var _hooked := false
var dmg_by := {}


func _on_damaged(_a: Actor, hit: HitInfo) -> void:
	var src := "?"
	if hit.source is Enemy:
		src = Enemy.Kind.keys()[(hit.source as Enemy).kind] + ":" + hit.weapon_id
	dmg_by[src] = dmg_by.get(src, 0.0) + hit.damage


func drive(p: Player, dt: float) -> void:
	if not _hooked:
		_hooked = true
		p.damaged.connect(_on_damaged)
	_t += dt
	_log_t += dt
	_weapon_t += dt
	_jump_t -= dt
	_dash_t -= dt
	_special_t -= dt
	if target == null or not is_instance_valid(target) or not target.is_alive() or int(_t * 4.0) % 4 == 0:
		target = _nearest(p)
	# React to telegraphed attacks like an attentive player would (~60%).
	for a in Game.hostiles_of(p.team):
		var e := a as Enemy
		if e and e.ai == Enemy.AI.WINDUP and e.global_position.distance_to(p.global_position) < 5.0 and not e.has_meta("bot_seen"):
			e.set_meta("bot_seen", true)
			get_tree().create_timer(1.0).timeout.connect(func() -> void:
				if is_instance_valid(e):
					e.remove_meta("bot_seen"))
			if randf() < 0.6 and p.stamina > 25.0:
				_strafe = -_strafe
				_dodge_side = _strafe
	p.attack_held = false
	p.jump_held = true
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
	# Weapon choice by range (a sensible player would do this).
	if not weapon_cycle and _weapon_t > 1.5:
		var want := 0 if dist < 6.0 else (2 if dist < 10.0 else 1)
		if (target as Enemy).kind == Enemy.Kind.BRUTE and dist > 4.0:
			want = 3
		if want != p.weapons.index:
			p.weapons.switch_to(want)
			_weapon_t = 0.0
	var melee := p.weapons.is_melee()
	var ideal := 2.0 if melee else 11.0
	var fwd := clampf((dist - ideal) * 0.4, -1.0, 1.0)
	if _t > 3.0 and int(_t / 3.0) % 2 == 0:
		_strafe = -_strafe if randf() < 0.02 else _strafe
	var mv := Vector2(0.4 * _strafe if not melee or dist > 4.0 else 0.0, fwd)
	# Avoid getting pinned against the perimeter walls / corners.
	var pos := p.global_position
	if absf(pos.x) > 20.0 or absf(pos.z) > 20.0:
		var to_center := -Vector3(pos.x, 0, pos.z).normalized()
		var yaw := p.cam.yaw
		var right := Vector3(cos(yaw), 0.0, -sin(yaw))
		var fw := Vector3(-sin(yaw), 0.0, -cos(yaw))
		mv += Vector2(to_center.dot(right), to_center.dot(fw)) * 0.8
	p.input_move = mv.limit_length(1.0)
	if dist > 8.0 and p.stamina > 30.0 and not p.sprinting and p.input_move.y > 0.5:
		p.press("sprint")
	if _dodge_t_ready(p):
		# Side dodge = JUMP while the stick points left/right.
		p.input_move = Vector2(_dodge_side, 0.0)
		p.press("jump")
		stats["dodges"] += 1
		_dodge_side = 0.0
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
		_dodge_side = 1.0 if randf() < 0.5 else -1.0
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


func _dodge_t_ready(p: Player) -> bool:
	return _dodge_side != 0.0 and p.state == Actor.State.NORMAL and p.stamina >= Player.DODGE_COST


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
	if not dmg_by.is_empty():
		print("[bot] damage taken by source: ", dmg_by)
	if target:
		print("[bot] target=%s dist=%.1f state=%s ai=%s" % [Enemy.Kind.keys()[(target as Enemy).kind], target.global_position.distance_to(p.global_position), Actor.State.keys()[target.state], Enemy.AI.keys()[(target as Enemy).ai]])
