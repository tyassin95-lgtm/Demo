class_name WeaponController
extends Node
## Loadout, switching, ammo/reload, ranged firing (hitscan, shotgun, piercing beam,
## projectiles), melee combos (timing windows, soft lock-on, lunges, hit detection)
## and secondary abilities (heavy slash, grenade, recoil jump, scope).

signal weapon_changed(index: int)
signal hit_landed(target: Actor, hit: HitInfo, killed: bool)
signal attack_started(attack_id: String)
signal fired(weapon_id: String)

const MELEE_TARGET_RANGE := 7.5
const DASH_TARGET_RANGE := 11.0
const PLUNGE_SPEED := 30.0

var actor: Actor
var loadout: Array = []
var index := 0
var ammo: Array[int] = []
var reload_left := 0.0
var fire_cd := 0.0
var secondary_cd := 0.0
var scoped := false
var damage_mult := 1.0
var speed_mult := 1.0
## Ranged weapons fire slow projectiles instead of hitscan (enemies: dodgeable shots).
var use_projectiles := false
var projectile_speed := 42.0

var attack: WeaponDB.Attack = null
var attack_time := 0.0
var lunge_dir := Vector3.FORWARD
var lunge_speed := 0.0
var lunge_time := 0.0
var plunging := false
var recovering := false
var lock_target: Actor = null

var aim_point := Vector3.ZERO
var aim_dir := Vector3.FORWARD
var assist_target: Actor = null
var assist_strength := 0.0
var spread_mult := 1.0

var _hit_targets: Array = []
var _buffered := false
var _buffer_age := 0.0
var _combo_next := ""
var _combo_window := 0.0
var _swing_sfx_done := false
var _slash_done := false
var _semi_queued := false


func setup(ids: Array) -> void:
	loadout.clear()
	ammo.clear()
	for id in ids:
		var w := WeaponDB.weapon(id)
		loadout.append(w)
		ammo.append(w.mag_size)
	index = 0
	actor.visual.show_weapon(current())
	actor.visual.anim.set_upper(current().kind != WeaponDB.Kind.MELEE)


func current() -> WeaponDB.Weapon:
	return loadout[index] if index < loadout.size() else null


func is_melee() -> bool:
	var w := current()
	return w != null and w.kind == WeaponDB.Kind.MELEE


func is_attacking() -> bool:
	return attack != null


func can_cancel() -> bool:
	return attack == null or (attack_time >= attack.cancel_time and not plunging)


func hostile_mask() -> int:
	return Game.LAYER_WORLD | (Game.LAYER_ENEMY if actor.team == Game.TEAM_PLAYER else Game.LAYER_PLAYER)


# --- Switching / reload --------------------------------------------------------

func switch_to(i: int) -> void:
	if i == index or i < 0 or i >= loadout.size():
		return
	cancel_attack()
	reload_left = 0.0
	scoped = false
	index = i
	var w := current()
	actor.visual.show_weapon(w)
	actor.visual.anim.set_upper(w.kind != WeaponDB.Kind.MELEE)
	fire_cd = maxf(fire_cd, 0.15)
	if actor.team == Game.TEAM_PLAYER:
		Audio.play("swap_blade" if w.kind == WeaponDB.Kind.MELEE else "swap_gun", -4.0)
		if w.kind == WeaponDB.Kind.MELEE:
			Audio.play("blade_ignite", -8.0)
	weapon_changed.emit(i)


func cycle(step: int = 1) -> void:
	switch_to(posmod(index + step, loadout.size()))


func start_reload() -> void:
	var w := current()
	if w == null or w.kind == WeaponDB.Kind.MELEE or reload_left > 0.0 or ammo[index] >= w.mag_size:
		return
	reload_left = w.reload_time
	actor.visual.anim.play_upper("reload", minf(w.reload_time, 1.6))
	if actor.team == Game.TEAM_PLAYER:
		Audio.play("reload", -3.0)


# --- Input entry points -------------------------------------------------------

## Primary action pressed this frame. `context` is "ground", "dash", or "air".
func press_primary(context: String) -> void:
	var w := current()
	if w == null:
		return
	if w.kind == WeaponDB.Kind.MELEE:
		if attack != null:
			_buffered = true
			_buffer_age = 0.0
			return
		var id: String = w.combo.get("ground", "")
		if context == "air":
			id = w.combo.get("air", id)
		elif context == "dash":
			id = w.combo.get("dash", id)
		elif _combo_window > 0.0 and _combo_next != "" and _combo_next != "blade_plunge":
			id = _combo_next
		start_attack(id)
	else:
		if not w.automatic:
			_semi_queued = true


## Primary held this frame (automatic fire).
func hold_primary() -> void:
	var w := current()
	if w != null and w.kind != WeaponDB.Kind.MELEE and w.automatic:
		_try_fire()


func press_secondary(context: String) -> void:
	var w := current()
	if w == null:
		return
	match w.secondary:
		WeaponDB.Secondary.HEAVY:
			if attack == null or can_cancel():
				var id: String = w.combo.get("heavy", "")
				if id != "":
					cancel_attack()
					start_attack(id)
		WeaponDB.Secondary.GRENADE:
			if secondary_cd <= 0.0 and reload_left <= 0.0:
				secondary_cd = w.secondary_cooldown
				_throw_grenade()
		WeaponDB.Secondary.BLAST_JUMP:
			if secondary_cd <= 0.0:
				if ammo[index] <= 0:
					start_reload()
					return
				secondary_cd = w.secondary_cooldown
				_recoil_jump(w, context)
		WeaponDB.Secondary.SCOPE:
			if secondary_cd <= 0.0:
				secondary_cd = w.secondary_cooldown
				scoped = not scoped
				Audio.play("ui_toggle", -6.0)


# --- Update -----------------------------------------------------------------------

func update(dt: float) -> void:
	fire_cd -= dt * speed_mult
	secondary_cd -= dt
	_combo_window -= dt
	if _buffered:
		_buffer_age += dt
		if _buffer_age > 0.4:
			_buffered = false
	if reload_left > 0.0:
		reload_left -= dt * speed_mult
		if reload_left <= 0.0:
			reload_left = 0.0
			ammo[index] = current().mag_size
			if actor.team == Game.TEAM_PLAYER:
				Audio.play("reload_done", -4.0)
	var w := current()
	if w != null and w.kind != WeaponDB.Kind.MELEE:
		if _semi_queued:
			if fire_cd <= 0.0:
				_semi_queued = false
				_try_fire()
			elif fire_cd > 0.2:
				_semi_queued = false
		if ammo[index] <= 0 and reload_left <= 0.0 and fire_cd <= 0.05:
			start_reload()
	if attack != null:
		_update_attack(dt)


# --- Melee ------------------------------------------------------------------------

func start_attack(id: String) -> void:
	var a := WeaponDB.attack(id)
	if a == null:
		return
	if a.stamina > 0.0 and "stamina" in actor:
		if actor.stamina < a.stamina:
			if actor.team == Game.TEAM_PLAYER:
				Audio.play("ui_error", -6.0)
			return
		actor.stamina -= a.stamina
		actor.stamina_delay = 0.8
	attack = a
	attack_time = 0.0
	recovering = false
	plunging = id == "blade_plunge"
	_hit_targets.clear()
	_buffered = false
	_swing_sfx_done = false
	_slash_done = false
	actor.set_state(Actor.State.ATTACK)
	var reach_range := DASH_TARGET_RANGE if id == "blade_dash" else MELEE_TARGET_RANGE
	lock_target = _find_melee_target(reach_range)
	var dir := actor.forward()
	if lock_target != null:
		var to := lock_target.global_position - actor.global_position
		to.y = 0.0
		if to.length() > 0.05:
			dir = to.normalized()
		var gap := maxf(to.length() - 1.15 * lock_target.visual_scale, 0.0)
		lunge_speed = clampf(gap / maxf(a.lunge_time, 0.05), 0.0, a.lunge_speed * (1.7 if id == "blade_dash" else 1.35))
	else:
		lunge_speed = a.lunge_speed
	lunge_dir = dir
	lunge_time = a.lunge_time
	actor.facing = Actor.yaw_from_dir(dir)
	actor.visual.rotation.y = lerp_angle(actor.visual.rotation.y, actor.facing, 0.7)
	var spd := a.speed * speed_mult
	actor.visual.anim.play_action(a.anim, spd, 0.05, 0.14, a.offset, a.duration / speed_mult + (1.0 if plunging else 0.0))
	if actor.visual.blade:
		actor.visual.blade.set_trail(true)
	if plunging:
		actor.velocity = dir * 3.0 + Vector3(0, -PLUNGE_SPEED, 0)
	attack_started.emit(id)


func cancel_attack() -> void:
	if attack == null:
		recovering = false
		return
	attack = null
	plunging = false
	recovering = false
	_buffered = false
	if actor.visual.blade:
		actor.visual.blade.set_trail(false)
	if actor.state == Actor.State.ATTACK:
		actor.set_state(Actor.State.NORMAL)


func _update_attack(dt: float) -> void:
	var a := attack
	attack_time += dt * speed_mult
	var t := attack_time
	if plunging:
		return
	if not _swing_sfx_done and t >= a.hit_start * 0.5:
		_swing_sfx_done = true
		Audio.play_at(a.sfx, actor.global_position + Vector3.UP, 0.0 if actor.team == Game.TEAM_PLAYER else -3.0)
	if t >= a.hit_start and t <= a.hit_end + dt:
		if not _slash_done:
			_slash_done = true
			_spawn_slash(a)
		_melee_sweep(a)
	if _buffered and t >= a.chain_time and a.next != "":
		var next_id := a.next
		if next_id == "blade_plunge" and actor.is_on_floor():
			next_id = "blade_2"
		start_attack(next_id)
		return
	if t >= a.duration:
		_end_attack()


func _end_attack() -> void:
	var a := attack
	attack = null
	plunging = false
	if actor.visual.blade:
		actor.visual.blade.set_trail(false)
	_combo_next = a.next
	_combo_window = 0.32
	if actor.state == Actor.State.ATTACK:
		actor.set_state(Actor.State.NORMAL)
	if a.recovery_anim != "":
		recovering = true
		actor.visual.anim.play_action(a.recovery_anim, 1.6, 0.06, 0.2, 0.0, 0.4)


## Called by the owner when landing during a plunge attack.
func on_plunge_landed() -> void:
	if not plunging or attack == null:
		return
	var a := attack
	plunging = false
	_melee_sweep(a)
	var pos := actor.global_position
	VFX.shockwave(pos + Vector3.UP * 0.05, a.reach * 1.2, current().color)
	VFX.burst(pos + Vector3.UP * 0.2, current().color, 26, 9.0)
	VFX.dust_ring(pos, 2.0)
	Audio.play_at("shockwave", pos, 0.0)
	Game.shake(a.shake)
	Game.vibrate(40)
	attack_time = maxf(attack_time, a.duration - 0.35)
	actor.visual.anim.play_action("Jump_Land", 1.4, 0.05, 0.2, 0.25, 0.35)


func _find_melee_target(max_range: float) -> Actor:
	var best: Actor = null
	var best_score := INF
	var fwd := actor.forward()
	if actor.has_method("aim_dir_flat"):
		var af: Vector3 = actor.call("aim_dir_flat")
		if af.length() > 0.1:
			fwd = af
	for t in Game.hostiles_of(actor.team):
		var to: Vector3 = t.global_position - actor.global_position
		if absf(to.y) > 3.0:
			continue
		to.y = 0.0
		var d := to.length()
		if d > max_range:
			continue
		var ang := fwd.angle_to(to.normalized()) if d > 0.1 else 0.0
		if ang > deg_to_rad(80.0) and d > 2.2:
			continue
		var score := d + ang * 4.0
		if score < best_score:
			best_score = score
			best = t
	return best


func _melee_sweep(a: WeaponDB.Attack) -> void:
	var origin := actor.global_position
	var fwd := actor.forward()
	var reach := a.reach * actor.visual_scale
	for target in Game.hostiles_of(actor.team):
		if _hit_targets.has(target):
			continue
		var to: Vector3 = target.global_position - origin
		var dy := to.y
		to.y = 0.0
		var dist := to.length()
		if dist > reach + 0.45 * target.visual_scale:
			continue
		if dy < a.height.x - 0.6 or dy > a.height.y:
			continue
		if a.arc_deg < 359.0 and dist > 0.6:
			if rad_to_deg(fwd.angle_to(to / dist)) > a.arc_deg * 0.5:
				continue
		if not _line_clear(actor.chest_position(), target.chest_position()):
			continue
		_hit_targets.append(target)
		var hit := HitInfo.new()
		hit.source = actor
		hit.damage = a.damage * damage_mult
		hit.reaction = a.reaction
		hit.knockback = a.knockback
		hit.lift = a.lift
		hit.impact = a.impact
		hit.hitstop = a.hitstop
		hit.is_melee = true
		hit.weapon_id = a.id
		hit.color = current().color
		var away := to / dist if dist > 0.1 else fwd
		hit.direction = (away * 0.6 + fwd * 0.4).normalized()
		hit.position = target.chest_position() - away * 0.25 * target.visual_scale
		var was_alive: bool = target.is_alive()
		if target.take_hit(hit):
			var killed: bool = was_alive and not target.is_alive()
			_on_melee_connect(target, hit, killed, a)


func _on_melee_connect(target: Actor, hit: HitInfo, killed: bool, a: WeaponDB.Attack) -> void:
	actor.hitstop = maxf(actor.hitstop, a.hitstop * (1.3 if killed else 1.0))
	var big := a.reaction >= HitInfo.Reaction.KNOCKDOWN or killed
	VFX.hit_spark(hit.position, hit.direction, hit.color, 1.5 if big else 1.0)
	VFX.damage_number(hit.position + Vector3.UP * 0.4, hit.damage, hit.color, big)
	Audio.play_at("heavy_hit" if big else "blade_hit", hit.position, 2.0 if actor.team == Game.TEAM_PLAYER else -2.0)
	if actor.team == Game.TEAM_PLAYER:
		Game.shake(a.shake * (1.3 if killed else 1.0))
		Game.vibrate(25 if not big else 45)
	hit_landed.emit(target, hit, killed)


func _spawn_slash(a: WeaponDB.Attack) -> void:
	var fwd := actor.forward()
	var pos := actor.global_position + Vector3.UP * 1.05 * actor.visual_scale + fwd * 0.9 * actor.visual_scale
	var basis := Basis.looking_at(fwd, Vector3.UP)
	var xf := Transform3D(basis, pos)
	VFX.slash(xf, current().color, a.slash_scale * actor.visual_scale * (1.6 if a.aoe else 1.0), a.slash_roll, a.aoe)


func _line_clear(from: Vector3, to: Vector3) -> bool:
	var space := actor.get_world_3d().direct_space_state
	var q := PhysicsRayQueryParameters3D.create(from, to, Game.LAYER_WORLD)
	return space.intersect_ray(q).is_empty()


# --- Ranged ------------------------------------------------------------------------

func _try_fire() -> void:
	var w := current()
	if w == null or reload_left > 0.0 or fire_cd > 0.0:
		return
	if ammo[index] <= 0:
		if actor.team == Game.TEAM_PLAYER:
			Audio.play("empty", -6.0, 1.0, 0.0, 200)
		start_reload()
		return
	fire_cd = w.fire_interval
	ammo[index] -= 1
	var muzzle := actor.visual.muzzle_position()
	if use_projectiles:
		_fire_projectile(w, muzzle)
	else:
		match w.kind:
			WeaponDB.Kind.HITSCAN, WeaponDB.Kind.SHOTGUN:
				_fire_pellets(w, muzzle)
			WeaponDB.Kind.BEAM:
				_fire_beam(w, muzzle)
	actor.visual.gun_kick(w.recoil * 0.5)
	if w.kind != WeaponDB.Kind.HITSCAN:
		actor.visual.anim.play_upper("shoot", 0.3)
	VFX.muzzle_flash(muzzle, (aim_point - muzzle).normalized(), w.color, 1.6 if w.kind == WeaponDB.Kind.SHOTGUN else (1.3 if w.kind == WeaponDB.Kind.BEAM else 0.9))
	if actor.team == Game.TEAM_PLAYER:
		Audio.play(w.sfx, -1.0 if w.kind == WeaponDB.Kind.HITSCAN else 1.0, 1.0, 0.06, 20)
		if w.kind == WeaponDB.Kind.SHOTGUN:
			Audio.play("scatter_boom", -8.0)
		Game.shake(w.shake)
		if w.kind != WeaponDB.Kind.HITSCAN:
			Game.vibrate(30)
	else:
		Audio.play_at(w.sfx, muzzle, -4.0, 0.85)
	fired.emit(w.id)


## Direction toward the aim point with aim assist bias and random spread.
func _aimed_direction(w: WeaponDB.Weapon, from: Vector3) -> Vector3:
	var target_point := aim_point
	if assist_target != null and is_instance_valid(assist_target) and assist_target.is_alive() and assist_strength > 0.0:
		var tp := assist_target.chest_position() + Vector3(randf_range(-0.15, 0.15), randf_range(-0.25, 0.2), randf_range(-0.15, 0.15))
		target_point = target_point.lerp(tp, assist_strength)
	var dir := (target_point - from).normalized()
	var spread := deg_to_rad(w.spread_deg) * spread_mult
	return _random_cone(dir, spread)


static func _random_cone(dir: Vector3, angle: float) -> Vector3:
	if angle <= 0.0:
		return dir
	var up := Vector3.UP if absf(dir.dot(Vector3.UP)) < 0.95 else Vector3.RIGHT
	var right := dir.cross(up).normalized()
	var up2 := right.cross(dir).normalized()
	var r := sqrt(randf()) * tan(angle)
	var th := randf() * TAU
	return (dir + right * cos(th) * r + up2 * sin(th) * r).normalized()


func _falloff(w: WeaponDB.Weapon, dist: float) -> float:
	if dist <= w.falloff_start:
		return 1.0
	var span := maxf(w.max_range - w.falloff_start, 0.01)
	return clampf(1.0 - (dist - w.falloff_start) / span * 0.6, 0.4, 1.0)


func _fire_pellets(w: WeaponDB.Weapon, muzzle: Vector3) -> void:
	var space := actor.get_world_3d().direct_space_state
	var per_target := {}
	var impacts := 0
	for i in w.pellets:
		var dir := _aimed_direction(w, muzzle)
		var to := muzzle + dir * w.max_range
		var q := PhysicsRayQueryParameters3D.create(muzzle, to, hostile_mask())
		q.exclude = [actor.get_rid()]
		var res := space.intersect_ray(q)
		var end := to
		if not res.is_empty():
			end = res.position
			var col: Object = res.collider
			if col is Actor and (col as Actor).team != actor.team:
				var dmg := w.damage * _falloff(w, muzzle.distance_to(end)) * damage_mult
				if not per_target.has(col):
					per_target[col] = [0, 0.0, end]
				per_target[col][0] += 1
				per_target[col][1] += dmg
			elif impacts < 3:
				impacts += 1
				VFX.impact(end, res.normal, w.color, 0.8 if w.pellets > 1 else 1.0)
		if w.pellets == 1 or i % 2 == 0:
			VFX.tracer(muzzle, end, w.color, w.tracer_width, 0.08 if w.pellets > 1 else 0.1)
	for target: Actor in per_target:
		var data: Array = per_target[target]
		var hit := HitInfo.new()
		hit.source = actor
		hit.damage = data[1]
		hit.position = data[2]
		hit.color = w.color
		hit.weapon_id = w.id
		var dir := target.global_position - actor.global_position
		dir.y = 0.0
		hit.direction = dir.normalized() if dir.length() > 0.01 else actor.forward()
		hit.impact = w.impact * data[0]
		hit.reaction = HitInfo.Reaction.NONE
		if w.kind == WeaponDB.Kind.SHOTGUN:
			var close := actor.global_position.distance_to(target.global_position) < 7.0
			if data[0] >= 4 and close:
				hit.reaction = w.reaction
				hit.knockback = w.knockback * float(data[0]) / float(w.pellets) * 1.5
				hit.hitstop = w.hitstop
		_apply_ranged_hit(target, hit, data[0] >= 4 or w.kind == WeaponDB.Kind.BEAM)


func _fire_beam(w: WeaponDB.Weapon, muzzle: Vector3) -> void:
	var space := actor.get_world_3d().direct_space_state
	var dir := _aimed_direction(w, muzzle)
	var end := muzzle + dir * w.max_range
	var exclude: Array[RID] = [actor.get_rid()]
	var hits := []
	for i in 8:
		var q := PhysicsRayQueryParameters3D.create(muzzle, end, hostile_mask())
		q.exclude = exclude
		var res := space.intersect_ray(q)
		if res.is_empty():
			break
		var col: Object = res.collider
		if col is Actor:
			if (col as Actor).team != actor.team:
				hits.append([col, res.position])
			exclude.append(res.rid)
			continue
		end = res.position
		VFX.impact(end, res.normal, w.color, 1.8)
		break
	VFX.beam(muzzle, end, w.color, w.tracer_width)
	for h in hits:
		var target: Actor = h[0]
		var hit := HitInfo.new()
		hit.source = actor
		hit.damage = w.damage * damage_mult
		hit.position = h[1]
		hit.color = w.color
		hit.weapon_id = w.id
		hit.direction = dir
		hit.impact = w.impact
		hit.reaction = w.reaction
		hit.knockback = w.knockback
		hit.hitstop = w.hitstop
		_apply_ranged_hit(target, hit, true)


func _fire_projectile(w: WeaponDB.Weapon, muzzle: Vector3) -> void:
	var dir := _aimed_direction(w, muzzle)
	var p := Projectile.new()
	p.shooter = actor
	p.team = actor.team
	p.velocity = dir * projectile_speed
	p.damage = w.damage * damage_mult
	p.impact = w.impact
	p.color = w.color
	p.mask = hostile_mask()
	p.max_life = w.max_range / projectile_speed
	actor.get_tree().current_scene.add_child(p)
	p.global_position = muzzle


func _apply_ranged_hit(target: Actor, hit: HitInfo, big: bool) -> void:
	var was_alive := target.is_alive()
	if target.take_hit(hit):
		var killed := was_alive and not target.is_alive()
		VFX.hit_spark(hit.position, hit.direction, hit.color, 1.1 if big else 0.6)
		VFX.damage_number(hit.position + Vector3.UP * 0.3, hit.damage, hit.color, big or killed)
		Audio.play_at("body_hit", hit.position, -3.0, 1.1, 0.1, 40)
		if actor.team == Game.TEAM_PLAYER:
			Audio.play("hitmarker", -2.0 if not killed else 2.0, 1.0 if not killed else 0.8, 0.02, 40)
		hit_landed.emit(target, hit, killed)


func _throw_grenade() -> void:
	var p := Projectile.new()
	p.shooter = actor
	p.team = actor.team
	p.kind = Projectile.Kind.GRENADE
	var throw_dir := aim_dir
	throw_dir.y = maxf(throw_dir.y, -0.2)
	p.velocity = throw_dir.normalized() * 19.0 + Vector3.UP * 4.5 + actor.velocity * 0.4
	p.damage = 38.0 * damage_mult
	p.color = Color(0.35, 0.85, 1.0)
	p.mask = hostile_mask()
	p.max_life = 1.4
	actor.get_tree().current_scene.add_child(p)
	p.global_position = actor.chest_position() + actor.forward() * 0.4 + Vector3.UP * 0.2
	actor.visual.anim.play_action("OverhandThrow", 1.8, 0.05, 0.15, 0.25, 0.4, 0.8)
	Audio.play("launcher_shot", -2.0, 0.8)


func _recoil_jump(w: WeaponDB.Weapon, _context: String) -> void:
	ammo[index] -= 1
	var fwd := aim_dir
	fwd.y = 0.0
	fwd = fwd.normalized() if fwd.length() > 0.01 else actor.forward()
	var hv := Vector3(actor.velocity.x, 0.0, actor.velocity.z) * 0.5
	actor.velocity = hv - fwd * 7.0 + Vector3.UP * 15.5
	if actor.has_method("on_recoil_jump"):
		actor.on_recoil_jump()
	var muzzle := actor.visual.muzzle_position()
	VFX.muzzle_flash(muzzle, fwd, w.color, 2.2)
	VFX.explosion(actor.global_position + fwd * 1.2 + Vector3.UP * 0.6, 1.4, w.color, false)
	Audio.play("scatter_shot", 2.0, 0.85)
	Audio.play("scatter_boom", -3.0)
	Game.shake(0.35)
	Game.vibrate(40)
	# Close-range blast in front of the player.
	for target in Game.hostiles_of(actor.team):
		var to: Vector3 = target.global_position - actor.global_position
		var d := to.length()
		if d < 5.0 and fwd.angle_to(Vector3(to.x, 0, to.z).normalized()) < deg_to_rad(50.0):
			var hit := HitInfo.new()
			hit.source = actor
			hit.damage = 22.0 * damage_mult
			hit.reaction = HitInfo.Reaction.STAGGER
			hit.knockback = 10.0
			hit.direction = fwd
			hit.position = target.chest_position()
			hit.color = w.color
			hit.impact = 40.0
			_apply_ranged_hit(target, hit, true)
