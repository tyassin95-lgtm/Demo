class_name Enemy
extends Actor
## AI-controlled opponent. Three archetypes share the player's combat systems:
##  STRIKER - fast blade fighter: dash-in attacks, combos, circles and dodges.
##  GUNNER  - keeps range, strafes, fires telegraphed bursts of dodgeable bolts.
##  BRUTE   - big, slow, super-armoured; charges and slams (knockdown AOE).
## Melee attackers share a small pool of attack tokens so fights stay readable.

enum Kind { STRIKER, GUNNER, BRUTE }
enum AI { CHASE, CIRCLE, ENGAGE, RETREAT, STRAFE, AIM, RECOVER, USE_PAD, WINDUP }

const SCORE := {Kind.STRIKER: 100, Kind.GUNNER: 120, Kind.BRUTE: 300}
const DODGE_SPEED := 15.0
const DODGE_TIME := 0.28

static var melee_tokens := 0
static var max_tokens := 2

var kind: Kind = Kind.STRIKER
var ai: AI = AI.CHASE
var ai_time := 0.0
var think_timer := 0.0
var target: Actor
var run_speed := 7.0
var accel := 40.0
var dodge_chance := 0.35
var aggression := 0.6
var has_token := false
var combo_left := 0
var dodge_cd := 0.0
var attack_cd := 1.0
var dash_attack_cd := 2.0
var strafe_sign := 1.0
var burst_left := 0
var aim_time := 0.0
var passive := false
var respawn_training := false
var difficulty := 1.0

var nav: NavigationAgent3D
var _dash_dir := Vector3.ZERO
var _dash_time := 0.0
var _pad_target: JumpPad = null
var _flight := 0.0
var _laser: MeshInstance3D
var _death_timer := 0.0
var _last_target_pos := Vector3.ZERO
var _stuck_time := 0.0
var _windup_action := ""
var _windup_time := 0.0


func setup(k: Kind, diff: float = 1.0) -> void:
	kind = k
	difficulty = diff
	team = Game.TEAM_ENEMY
	match kind:
		Kind.STRIKER:
			max_health = 70.0 * lerpf(1.0, 1.35, diff - 1.0)
			run_speed = 7.4
			dodge_chance = 0.3 + 0.15 * (diff - 1.0)
			aggression = 0.65
			poise_max = 26.0
			model_path = "res://assets/characters/mannequin_f.scn"
			style = {"base": Color(0.13, 0.13, 0.16), "rim": Color(1.0, 0.25, 0.15), "glow": Color(1.0, 0.25, 0.12),
				"visor": Color(1.0, 0.2, 0.1), "stripe": 0.5, "metallic": 0.6, "roughness": 0.3, "rim_strength": 0.9,
				"glow_strength": 3.0, "pack_color": Color(0.2, 0.05, 0.04)}
		Kind.GUNNER:
			max_health = 55.0 * lerpf(1.0, 1.3, diff - 1.0)
			run_speed = 6.6
			dodge_chance = 0.28 + 0.1 * (diff - 1.0)
			poise_max = 22.0
			style = {"base": Color(0.24, 0.22, 0.2), "rim": Color(1.0, 0.65, 0.1), "glow": Color(1.0, 0.6, 0.08),
				"visor": Color(1.0, 0.75, 0.2), "stripe": 0.3, "metallic": 0.5, "roughness": 0.35, "rim_strength": 0.8,
				"glow_strength": 2.6, "pack_color": Color(0.18, 0.12, 0.03)}
		Kind.BRUTE:
			max_health = 240.0 * lerpf(1.0, 1.3, diff - 1.0)
			run_speed = 5.2
			dodge_chance = 0.0
			poise_max = 140.0
			visual_scale = 1.38
			damage_taken_mult = 0.9
			style = {"base": Color(0.16, 0.1, 0.2), "rim": Color(1.0, 0.2, 0.75), "glow": Color(1.0, 0.2, 0.7),
				"visor": Color(1.0, 0.3, 0.8), "stripe": 0.6, "metallic": 0.7, "roughness": 0.25, "rim_strength": 1.0,
				"glow_strength": 3.2, "pack_color": Color(0.12, 0.04, 0.12)}


func _ready() -> void:
	collision_layer = Game.LAYER_ENEMY
	collision_mask = Game.LAYER_WORLD
	super._ready()
	match kind:
		Kind.STRIKER:
			weapons.setup(["enemy_blade"])
		Kind.GUNNER:
			weapons.setup(["enemy_rifle"])
			weapons.use_projectiles = true
			weapons.projectile_speed = 34.0 + 6.0 * (difficulty - 1.0)
		Kind.BRUTE:
			weapons.setup(["enemy_heavy"])
			if visual.blade:
				visual.blade.visible = false
	# Enemies reuse the player's move set but hit softer so fights stay fair on touch.
	var base_mult := 0.45 if kind == Kind.STRIKER else (0.7 if kind == Kind.BRUTE else 1.0)
	weapons.damage_mult = base_mult * (1.0 + 0.25 * (difficulty - 1.0))
	nav = NavigationAgent3D.new()
	nav.path_desired_distance = 0.8
	nav.target_desired_distance = 1.0
	nav.radius = 0.5
	nav.avoidance_enabled = false
	add_child(nav)
	_build_laser()
	strafe_sign = 1.0 if randf() < 0.5 else -1.0
	attack_cd = randf_range(0.6, 1.4)
	# Materialize.
	set_state(State.SPAWNING)
	visual.dissolve_in(0.8)
	VFX.spawn_pillar(global_position, style.get("glow", Color.RED), 5.0, 0.8)
	Audio.play_at("spawn", global_position, -2.0)


func _build_laser() -> void:
	_laser = MeshInstance3D.new()
	var cyl := CylinderMesh.new()
	cyl.top_radius = 0.012
	cyl.bottom_radius = 0.012
	cyl.height = 1.0
	cyl.radial_segments = 6
	cyl.rings = 1
	_laser.mesh = cyl
	var m := StandardMaterial3D.new()
	m.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	m.blend_mode = BaseMaterial3D.BLEND_MODE_ADD
	m.albedo_color = Color(2.0, 0.6, 0.2)
	_laser.material_override = m
	_laser.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	_laser.top_level = true
	_laser.visible = false
	add_child(_laser)


func _exit_tree() -> void:
	_release_token()
	super._exit_tree()


func _release_token() -> void:
	if has_token:
		has_token = false
		melee_tokens = maxi(melee_tokens - 1, 0)


func _try_token() -> bool:
	if has_token:
		return true
	if melee_tokens < max_tokens:
		melee_tokens += 1
		has_token = true
		return true
	return false


# --- Main loop ----------------------------------------------------------------------

func _actor_update(dt: float) -> void:
	dodge_cd -= dt
	attack_cd -= dt
	dash_attack_cd -= dt
	if state == State.SPAWNING:
		apply_gravity(dt)
		steer_horizontal(Vector3.ZERO, 30.0, dt)
		if state_time > 0.8:
			set_state(State.NORMAL)
		_update_anim()
		return
	if state == State.DEAD:
		_update_reaction_states(dt)
		_death_timer += dt
		if _death_timer > 1.1 and _death_timer - dt <= 1.1:
			visual.dissolve_out(0.8)
		if _death_timer > 2.0:
			queue_free()
		return
	if _update_reaction_states(dt):
		_laser.visible = false
		if state == State.KNOCKDOWN or state == State.DOWN:
			super_armor = false
		if ai == AI.WINDUP:
			ai = AI.CIRCLE
			_release_token()
		if state != State.FLINCH:
			_release_token()
		return
	weapons.update(dt)
	target = Game.player as Actor
	if target == null or not is_instance_valid(target) or not target.is_alive():
		apply_gravity(dt)
		steer_horizontal(Vector3.ZERO, 20.0, dt)
		_update_anim()
		return
	match state:
		State.ATTACK:
			_attack_motion(dt)
		State.DODGE:
			_dodge_motion(dt)
		_:
			think_timer -= dt
			if think_timer <= 0.0:
				think_timer = randf_range(0.14, 0.24)
				_think()
			_act(dt)
	_update_anim()


func _to_target() -> Vector3:
	var d := target.global_position - global_position
	d.y = 0.0
	return d


func _think() -> void:
	var d := _to_target()
	var dist := d.length()
	var dy := target.global_position.y - global_position.y
	# Elevated target: melee units look for a jump pad that goes up there.
	if kind != Kind.GUNNER and dy > 3.0 and target.is_on_floor():
		var pad := _find_pad_to(target.global_position)
		if pad:
			_pad_target = pad
			ai = AI.USE_PAD
			return
	if ai == AI.USE_PAD and dy <= 3.0:
		ai = AI.CHASE
	if passive:
		ai = AI.STRAFE if kind == Kind.GUNNER else AI.CIRCLE
		return
	match kind:
		Kind.STRIKER:
			_think_striker(dist)
		Kind.GUNNER:
			_think_gunner(dist)
		Kind.BRUTE:
			_think_brute(dist)
	_maybe_dodge(dist)


func _think_striker(dist: float) -> void:
	if dist > 9.0:
		_release_token()
		ai = AI.CHASE
		return
	if ai == AI.WINDUP:
		return
	if dash_attack_cd <= 0.0 and dist > 4.5 and dist < 9.5 and randf() < 0.35 * aggression and _try_token():
		dash_attack_cd = randf_range(3.5, 6.0) / difficulty
		_begin_windup("dash", 0.42 / sqrt(difficulty))
		return
	if dist < 3.0 and attack_cd <= 0.0:
		if _try_token():
			combo_left = randi_range(1, 3 if difficulty > 1.2 else 2)
			_begin_windup("combo", 0.3 / sqrt(difficulty))
			return
	if dist < 5.5:
		ai = AI.CIRCLE if not has_token else AI.CHASE
	else:
		ai = AI.CHASE


func _think_gunner(dist: float) -> void:
	var los := _has_los()
	if ai == AI.AIM:
		return
	if dist < 6.5:
		ai = AI.RETREAT
	elif dist > 17.0 or not los:
		ai = AI.CHASE
	else:
		ai = AI.STRAFE
		if ai_time > randf_range(1.2, 2.6):
			ai_time = 0.0
			strafe_sign = -strafe_sign
	if los and attack_cd <= 0.0 and dist < 24.0:
		ai = AI.AIM
		aim_time = 0.0
		burst_left = randi_range(3, 5) + int(difficulty > 1.3)
		Audio.play_at("enemy_alert", global_position + Vector3.UP, -8.0, 1.2)


func _think_brute(dist: float) -> void:
	if ai == AI.WINDUP:
		return
	if dist < 3.6 and attack_cd <= 0.0:
		attack_cd = randf_range(2.0, 2.8) / difficulty
		super_armor = true
		_begin_windup("slam", 0.35)
		return
	if dash_attack_cd <= 0.0 and dist > 6.0 and dist < 13.0:
		dash_attack_cd = randf_range(5.0, 7.0) / difficulty
		super_armor = true
		_begin_windup("charge", 0.5)
		return
	ai = AI.CHASE


func _maybe_dodge(dist: float) -> void:
	if dodge_cd > 0.0 or dodge_chance <= 0.0 or state != State.NORMAL:
		return
	var p := target as Player
	if p == null:
		return
	var threatened := false
	if p.state == State.ATTACK and dist < 4.0:
		threatened = true
	elif not p.weapons.is_melee() and p.attack_held:
		var to_me := (chest_position() - p.cam.camera.global_position).normalized()
		var aim := -p.cam.camera.global_basis.z
		if aim.angle_to(to_me) < deg_to_rad(4.0):
			threatened = true
	if threatened and randf() < dodge_chance:
		dodge_cd = randf_range(1.6, 3.0)
		_start_dodge(1.0 if randf() < 0.5 else -1.0)


## Telegraph before melee attacks: stop, face the player, blade glint + cue.
func _begin_windup(action: String, time: float) -> void:
	ai = AI.WINDUP
	_windup_action = action
	_windup_time = time
	_face_target()
	var glow: Color = style.get("glow", Color.RED)
	var hand := visual.hand_r.global_position if visual.hand_r else chest_position()
	VFX.glint(hand, glow)
	visual.flash(0.35)
	Audio.play_at("enemy_alert", global_position + Vector3.UP, -6.0, 1.3)


func _release_windup() -> void:
	_face_target()
	if _windup_action == "slam":
		weapons.press_primary("ground")
		ai = AI.CHASE
		return
	if _windup_action == "charge":
		_start_charge()
		ai = AI.CHASE
		return
	if _windup_action == "dash":
		weapons.press_primary("dash")
		combo_left = 0
		ai = AI.ENGAGE
	else:
		ai = AI.ENGAGE
		weapons.press_primary("ground")
		combo_left -= 1


func _has_los() -> bool:
	var q := PhysicsRayQueryParameters3D.create(chest_position(), target.chest_position(), Game.LAYER_WORLD)
	return get_world_3d().direct_space_state.intersect_ray(q).is_empty()


func _face_target() -> void:
	var d := _to_target()
	if d.length() > 0.05:
		facing = Actor.yaw_from_dir(d.normalized())


# --- Acting -----------------------------------------------------------------------------

func _act(dt: float) -> void:
	ai_time += dt
	var d := _to_target()
	var dist := d.length()
	var dir := d / dist if dist > 0.01 else forward()
	var wish := Vector3.ZERO
	var speed := run_speed
	match ai:
		AI.CHASE:
			wish = _nav_dir(target.global_position)
			if dist > 10.0:
				speed = run_speed * 1.5
		AI.CIRCLE:
			var side := Vector3(dir.z, 0, -dir.x) * strafe_sign
			var radial := dir * clampf((dist - 4.5) * 0.5, -1.0, 1.0)
			wish = (side + radial).normalized()
			speed = run_speed * 0.7
			if ai_time > randf_range(1.5, 3.0):
				ai_time = 0.0
				strafe_sign = -strafe_sign
		AI.ENGAGE:
			wish = dir if dist > 2.2 else Vector3.ZERO
			if combo_left > 0 and not weapons.is_attacking():
				_face_target()
				weapons.press_primary("ground")
				combo_left -= 1
			elif combo_left <= 0 and not weapons.is_attacking():
				_release_token()
				attack_cd = randf_range(0.9, 1.8) / difficulty
				ai = AI.CIRCLE
		AI.RETREAT:
			wish = _nav_dir(global_position - dir * 6.0)
			speed = run_speed * 1.1
		AI.STRAFE:
			var side2 := Vector3(dir.z, 0, -dir.x) * strafe_sign
			wish = side2
			speed = run_speed * 0.8
		AI.AIM:
			_update_aim_burst(dt, dist)
			wish = Vector3(dir.z, 0, -dir.x) * strafe_sign * 0.35
		AI.WINDUP:
			wish = Vector3.ZERO
			_face_target()
			_windup_time -= dt
			if _windup_time <= 0.0:
				_release_windup()
		AI.USE_PAD:
			if _pad_target and is_instance_valid(_pad_target):
				wish = _nav_dir(_pad_target.global_position)
				speed = run_speed * 1.2
			else:
				ai = AI.CHASE
	# Stuck detection -> hop.
	if wish.length() > 0.1 and is_on_floor():
		if Vector3(velocity.x, 0, velocity.z).length() < 1.0:
			_stuck_time += dt
			if _stuck_time > 0.5:
				_stuck_time = 0.0
				velocity.y = 10.0
		else:
			_stuck_time = 0.0
	var mult := 1.0 if is_on_floor() else 0.35
	if _flight > 0.0:
		_flight -= dt
		mult = 0.0
	steer_horizontal(wish * speed, accel * mult, dt)
	apply_gravity(dt)
	# Hop up onto the core when the player is just above.
	if is_on_floor() and target.global_position.y - global_position.y > 1.5 and dist < 4.0 and randf() < 0.02:
		velocity.y = 10.5
	# Facing.
	if kind == Kind.GUNNER or ai in [AI.CIRCLE, AI.ENGAGE, AI.AIM, AI.STRAFE, AI.RETREAT]:
		facing = _rotate_toward(facing, Actor.yaw_from_dir(dir), 10.0 * dt)
	elif wish.length() > 0.1:
		facing = _rotate_toward(facing, Actor.yaw_from_dir(wish), 10.0 * dt)
	if kind == Kind.GUNNER:
		weapons.aim_point = target.chest_position() + Vector3(0, -0.1, 0)
		weapons.aim_dir = (weapons.aim_point - chest_position()).normalized()
		visual.anim.set_upper(true)
		var hv := Vector3(velocity.x, 0, velocity.z)
		var rel := 0.0
		var back := false
		if hv.length() > 1.0:
			rel = wrapf(Actor.yaw_from_dir(hv.normalized()) - facing, -PI, PI)
			if absf(rel) > deg_to_rad(105.0):
				back = true
				rel = wrapf(rel - PI, -PI, PI)
		visual_yaw_offset = lerp_angle(visual_yaw_offset, clampf(rel, -1.1, 1.1), clampf(dt * 8.0, 0.0, 1.0))
		visual.twist.yaw = -visual_yaw_offset
		visual.set_meta("backpedal", back)


func _update_aim_burst(dt: float, dist: float) -> void:
	aim_time += dt
	var telegraph := 0.45 / sqrt(difficulty)
	var muzzle := visual.muzzle_position()
	var tp := target.chest_position()
	if aim_time < telegraph:
		_laser.visible = true
		var d := tp - muzzle
		_orient_laser(muzzle, muzzle + d.normalized() * minf(d.length(), 40.0))
		return
	_laser.visible = false
	if burst_left > 0:
		# Lead the target slightly on higher difficulty.
		var lead := target.velocity * clampf(dist / weapons.projectile_speed, 0.0, 0.6) * (0.35 * (difficulty - 0.8))
		weapons.aim_point = tp + lead
		weapons.spread_mult = 1.0 + dist * 0.03
		if weapons.fire_cd <= 0.0 and weapons.ammo[0] > 0:
			weapons.hold_primary()
			burst_left -= 1
		elif weapons.ammo[0] <= 0:
			burst_left = 0
	else:
		ai = AI.STRAFE
		ai_time = 0.0
		attack_cd = randf_range(1.0, 2.0) / difficulty


func _orient_laser(a: Vector3, b: Vector3) -> void:
	var d := b - a
	var len := d.length()
	if len < 0.01:
		return
	var y := d / len
	var x := y.cross(Vector3.UP if absf(y.y) < 0.95 else Vector3.RIGHT).normalized()
	var z := x.cross(y)
	_laser.global_transform = Transform3D(Basis(x, y * len, z), (a + b) * 0.5)


func _nav_dir(goal: Vector3) -> Vector3:
	var to := goal - global_position
	to.y = 0.0
	if nav and NavigationServer3D.map_get_iteration_id(nav.get_navigation_map()) > 0:
		if goal.distance_to(_last_target_pos) > 1.0:
			nav.target_position = goal
			_last_target_pos = goal
		if not nav.is_navigation_finished():
			var nxt := nav.get_next_path_position()
			var d := nxt - global_position
			d.y = 0.0
			if d.length() > 0.2:
				return d.normalized()
	return to.normalized() if to.length() > 0.3 else Vector3.ZERO


func _find_pad_to(goal: Vector3) -> JumpPad:
	var best: JumpPad = null
	var best_d := INF
	for pad in get_tree().get_nodes_in_group("jump_pads"):
		var jp := pad as JumpPad
		var land_d := Vector2(jp.target.x - goal.x, jp.target.z - goal.z).length()
		if land_d > 12.0 or absf(jp.target.y - goal.y) > 2.0:
			continue
		var d := global_position.distance_to(jp.global_position) + land_d
		if d < best_d:
			best_d = d
			best = jp
	return best


## Side dodge (same rules as the player's: sideways only, no invulnerability, but
## flinches can't interrupt it). Female fighters cartwheel, the others duck and slide.
func _start_dodge(side: float) -> void:
	_face_target()
	var fwd := forward()
	_dash_dir = Vector3(-fwd.z, 0.0, fwd.x) * side
	_dash_time = 0.0
	set_state(State.DODGE)
	velocity.x = _dash_dir.x * DODGE_SPEED
	velocity.z = _dash_dir.z * DODGE_SPEED
	if kind == Kind.STRIKER:
		velocity.y = 3.5
		visual.anim.play_action("NinjaJump_Start", 1.7, 0.03, 0.2, 0.15, DODGE_TIME + 0.1)
		visual.spin(Vector3.FORWARD, side, DODGE_TIME + 0.12)
	else:
		visual.anim.play_action("Slide_Start", 2.3, 0.03, 0.12, 0.28, DODGE_TIME)
		visual_yaw_offset = wrapf(Actor.yaw_from_dir(_dash_dir) - facing, -PI, PI)
	Audio.play_at("dash", global_position, -6.0)
	visual.spawn_afterimage(style.get("glow", Color.RED), 0.25)


func _start_charge() -> void:
	_face_target()
	weapons.press_primary("ground")
	# Brute charge reuses the slam with a long lunge.
	lock_on_lunge(16.0, 0.45)


func lock_on_lunge(speed: float, time: float) -> void:
	weapons.lunge_speed = speed
	weapons.lunge_time = time


func _dodge_motion(dt: float) -> void:
	_dash_time += dt
	if _dash_time < DODGE_TIME:
		var k := _dash_time / DODGE_TIME
		var spd := lerpf(DODGE_SPEED, 5.0, k * k)
		velocity.x = _dash_dir.x * spd
		velocity.z = _dash_dir.z * spd
	else:
		steer_horizontal(Vector3.ZERO, 30.0, dt)
		visual_yaw_offset = lerp_angle(visual_yaw_offset, 0.0, clampf(dt * 12.0, 0.0, 1.0))
	apply_gravity(dt)
	if _dash_time >= DODGE_TIME + 0.2:
		visual_yaw_offset = 0.0
		set_state(State.NORMAL)


func _attack_motion(dt: float) -> void:
	var a := weapons.attack
	if a == null:
		set_state(State.NORMAL)
		super_armor = false
		return
	if weapons.attack_time < weapons.lunge_time:
		steer_horizontal(weapons.lunge_dir * weapons.lunge_speed, 140.0, dt)
	else:
		steer_horizontal(Vector3.ZERO, 40.0, dt)
	apply_gravity(dt)
	if kind == Kind.BRUTE and weapons.attack_time < a.hit_start:
		visual.flash(0.35 * (0.5 + 0.5 * sin(weapons.attack_time * 40.0)))


func launch(v: Vector3) -> void:
	if state == State.ATTACK:
		weapons.cancel_attack()
	if state != State.NORMAL:
		return
	velocity = v
	_flight = 1.0
	_pad_target = null
	ai = AI.CHASE
	visual.anim.set_base("flip_fall", 0.1, true)
	visual.anim.play_action("NinjaJump_Start", 1.3, 0.04, 0.3, 0.05, 0.5)


static func _rotate_toward(from: float, to: float, max_step: float) -> float:
	var diff := wrapf(to - from, -PI, PI)
	return from + clampf(diff, -max_step, max_step)


func _update_anim() -> void:
	var anim := visual.anim
	var hv := Vector3(velocity.x, 0, velocity.z)
	var spd := hv.length()
	if state == State.DODGE or state == State.DEAD:
		return
	if is_on_floor() or state == State.SPAWNING:
		if spd < 0.7:
			anim.set_base("idle_blade" if kind == Kind.STRIKER else "idle", 0.25)
			anim.base_speed = 1.0
		else:
			anim.set_base("move", 0.16)
			anim.move_blend = clampf(spd * 0.85, 1.6, 9.5)
			var back: bool = visual.get_meta("backpedal", false)
			anim.base_speed = (-1.0 if back else 1.0) * clampf(spd / 6.0, 0.7, 1.35) / (1.15 if kind == Kind.BRUTE else 1.0)
	else:
		if anim.base_state not in ["fall", "flip_fall"]:
			anim.set_base("fall", 0.2)


func take_hit(hit: HitInfo) -> bool:
	var ok := super.take_hit(hit)
	if ok and is_alive():
		# Getting hit makes them more cautious for a moment.
		if kind == Kind.STRIKER and state == State.NORMAL and randf() < 0.3:
			ai = AI.CIRCLE
		if state != State.ATTACK:
			_laser.visible = false
	return ok


func _on_death(hit: HitInfo) -> void:
	_release_token()
	_laser.visible = false
	super_armor = false
	var col: Color = style.get("glow", Color.RED)
	VFX.burst(chest_position(), col, 26, 11.0)
	VFX.hit_spark(chest_position(), hit.direction, col, 1.8)
	Audio.play_at("enemy_death", global_position, 0.0)
	Audio.play_at("explosion", global_position, -8.0, 1.3)
