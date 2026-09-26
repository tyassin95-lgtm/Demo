class_name Player
extends Actor
## Player character: responsive high-speed movement (sprint, jump, air control, dash,
## air dash, wall jump, wall run), weapons, stamina, overdrive and combo tracking.

signal overdrive_changed(active: bool)
signal combo_changed(count: int)

# --- Movement tuning ------------------------------------------------------------
const RUN_SPEED := 7.6
const SPRINT_SPEED := 11.8
const GROUND_ACCEL := 70.0
const GROUND_DECEL := 52.0
const REVERSE_BONUS := 1.7
const AIR_ACCEL := 24.0
const AIR_DRAG := 1.2
const JUMP_VELOCITY := 10.8
const JUMP_CUT_GRAVITY := 2.1
const COYOTE_TIME := 0.11
const BUFFER_TIME := 0.14
const DASH_SPEED := 25.0
const DASH_TIME := 0.19
const DASH_EXIT_SPEED := 12.5
const DASH_COST := 20.0
const AIR_DASH_COST := 16.0
const DASH_COOLDOWN := 0.1
const DASH_IFRAMES := 0.2
const WALL_JUMP_UP := 11.0
const WALL_JUMP_OUT := 8.8
const WALL_JUMP_COST := 7.0
const WALL_PROBE := 0.75
const WALLRUN_TIME := 0.9
const WALLRUN_MIN_SPEED := 7.0
const WALLRUN_GRAVITY := 0.2
const WALLRUN_COST := 10.0
const STAMINA_MAX := 100.0
const STAMINA_REGEN := 34.0
const STAMINA_DELAY := 0.55
const SPRINT_DRAIN := 11.0
const OVERDRIVE_TIME := 8.0
const COMBO_TIMEOUT := 2.6

var stamina := STAMINA_MAX
var stamina_delay := 0.0
var sprinting := false
var exhausted := false
var coyote := 0.0
var air_dashes := 1
var dash_timer := 0.0
var dash_dir := Vector3.FORWARD
var dash_cd := 0.0
var dash_in_air := false
var wallrun_timer := 0.0
var wallrun_normal := Vector3.ZERO
var wallrun_cd := 0.0
var jumped := false
var air_attacks := 0
var afterimage_timer := 0.0
var combo := 0
var combo_timer := 0.0
var best_combo := 0
var overdrive := 0.0
var overdrive_time := 0.0
var damage_dealt := 0.0
var kills := 0
var cam: PlayerCamera
var controls: Node = null
var god_mode := false
## Optional automation driver (tests / attract mode). Replaces human input.
var bot: Node = null

# Input state (merged from keyboard/gamepad/touch).
var input_move := Vector2.ZERO
var jump_held := false
var attack_held := false
var sprint_toggle := false
var _buffer := {"jump": 0.0, "dash": 0.0, "attack": 0.0, "special": 0.0}
var _last_wall_normal := Vector3.ZERO
var _last_wall_time := -10.0
var _step_timer := 0.0
var _land_anim_cd := 0.0


func _init() -> void:
	team = Game.TEAM_PLAYER
	max_health = 150.0
	poise_max = 34.0
	flinch_immunity_after_hit = 0.7
	style = {
		"base": Color(0.9, 0.92, 0.96), "rim": Color(0.25, 0.85, 1.0), "glow": Color(0.2, 0.9, 1.0),
		"visor": Color(0.3, 1.0, 1.0), "stripe": 0.45, "metallic": 0.4, "roughness": 0.28,
		"rim_strength": 0.8, "glow_strength": 2.8,
	}


func _ready() -> void:
	collision_layer = Game.LAYER_PLAYER
	collision_mask = Game.LAYER_WORLD
	super._ready()
	weapons.setup(["arc_blade", "pulse_rifle", "scatter_cannon", "rail_lancer"])
	weapons.hit_landed.connect(_on_hit_landed)
	Game.player = self
	cam = PlayerCamera.new()
	cam.name = "PlayerCamera"
	cam.target = self
	add_child(cam)
	cam.snap_behind(facing)


# --- Helpers ----------------------------------------------------------------------

func aim_dir_flat() -> Vector3:
	if cam == null:
		return forward()
	var f := -cam.global_basis.z
	f.y = 0.0
	return f.normalized() if f.length() > 0.01 else forward()


func _wish_dir() -> Vector3:
	if cam == null:
		return Vector3.ZERO
	var yaw := cam.yaw
	var fwd := Vector3(-sin(yaw), 0.0, -cos(yaw))
	var right := Vector3(cos(yaw), 0.0, -sin(yaw))
	var v := right * input_move.x + fwd * input_move.y
	return v.limit_length(1.0)


func is_strafing() -> bool:
	return not weapons.is_melee() or weapons.scoped


func can_act() -> bool:
	return state == State.NORMAL or state == State.DASH or (state == State.ATTACK and weapons.can_cancel())


# --- Input ------------------------------------------------------------------------

func _gather_input(dt: float) -> void:
	if bot and is_instance_valid(bot):
		for k in _buffer:
			_buffer[k] = maxf(_buffer[k] - dt, 0.0)
		bot.call("drive", self, dt)
		return
	var mv := Vector2(Input.get_axis("move_left", "move_right"), Input.get_axis("move_back", "move_forward"))
	var touch_sprint := false
	if controls and is_instance_valid(controls):
		mv += controls.move_vector
		touch_sprint = controls.sprint_active
	input_move = mv.limit_length(1.0)
	for k in _buffer:
		_buffer[k] = maxf(_buffer[k] - dt, 0.0)
	if Input.is_action_just_pressed("jump") or (controls and controls.consume("jump")):
		_buffer["jump"] = BUFFER_TIME
	if Input.is_action_just_pressed("dash") or (controls and controls.consume("dash")):
		_buffer["dash"] = BUFFER_TIME
	if Input.is_action_just_pressed("attack") or (controls and controls.consume("attack")):
		_buffer["attack"] = BUFFER_TIME
	if Input.is_action_just_pressed("special") or (controls and controls.consume("special")):
		_buffer["special"] = BUFFER_TIME
	jump_held = Input.is_action_pressed("jump") or (controls != null and controls.is_held("jump"))
	attack_held = Input.is_action_pressed("attack") or (controls != null and controls.is_held("attack"))
	var sprint_key := Input.is_action_pressed("sprint")
	var auto: bool = bool(Settings.get_value("auto_sprint")) and input_move.length() > 0.92 and controls != null and controls.stick_active
	sprinting = (sprint_key or touch_sprint or auto) and input_move.length() > 0.4 and not exhausted and not weapons.scoped
	if Input.is_action_just_pressed("reload") or (controls and controls.consume("reload")):
		weapons.start_reload()
	for i in 4:
		if Input.is_action_just_pressed("weapon_%d" % (i + 1)) or (controls and controls.consume("weapon_%d" % (i + 1))):
			weapons.switch_to(i)
	if Input.is_action_just_pressed("weapon_next") or (controls and controls.consume("weapon_next")):
		weapons.cycle(1)
	if Input.is_action_just_pressed("overdrive") or (controls and controls.consume("overdrive")):
		activate_overdrive()


## Used by automation to press a buffered action.
func press(k: String) -> void:
	_buffer[k] = BUFFER_TIME


func _consume(k: String) -> bool:
	if _buffer[k] > 0.0:
		_buffer[k] = 0.0
		return true
	return false


# --- Main update ------------------------------------------------------------------

func _actor_update(dt: float) -> void:
	_gather_input(dt)
	_update_stamina(dt)
	_update_timers(dt)
	_update_aim()
	if _update_reaction_states(dt):
		visual_yaw_offset = 0.0
		visual.twist.yaw = 0.0
		visual.set_lean(0.0, 0.0)
		return
	match state:
		State.NORMAL:
			_update_normal(dt)
		State.DASH:
			_update_dash(dt)
		State.ATTACK:
			_update_attack(dt)
	weapons.update(dt)
	_update_anim(dt)


func _update_timers(dt: float) -> void:
	# Gentle regeneration after a few seconds without taking damage.
	if is_alive() and _clock - last_hit_time > 4.5 and health < max_health:
		health = minf(health + 5.0 * dt, max_health)
	dash_cd -= dt
	wallrun_cd -= dt
	_land_anim_cd -= dt
	if combo > 0:
		combo_timer -= dt
		if combo_timer <= 0.0:
			combo = 0
			combo_changed.emit(0)
	if overdrive_time > 0.0:
		overdrive_time -= dt
		stamina = STAMINA_MAX
		if overdrive_time <= 0.0:
			_end_overdrive()


func _update_stamina(dt: float) -> void:
	if sprinting and state == State.NORMAL and is_on_floor() and Vector3(velocity.x, 0, velocity.z).length() > 3.0:
		stamina -= SPRINT_DRAIN * dt
		stamina_delay = STAMINA_DELAY
	elif state != State.DASH and wallrun_timer <= 0.0:
		stamina_delay -= dt
		if stamina_delay <= 0.0:
			stamina = minf(stamina + STAMINA_REGEN * dt, STAMINA_MAX)
	if stamina <= 0.0:
		stamina = 0.0
		if not exhausted:
			exhausted = true
			Audio.play("ui_error", -10.0)
	if exhausted and stamina >= 30.0:
		exhausted = false


func _spend(amount: float) -> bool:
	if overdrive_time > 0.0:
		return true
	if stamina < amount * 0.5:
		Audio.play("ui_error", -10.0, 1.0, 0.0, 300)
		return false
	stamina = maxf(stamina - amount, 0.0)
	stamina_delay = STAMINA_DELAY
	return true


func _update_aim() -> void:
	if cam == null:
		return
	var ray := cam.get_aim_ray()
	weapons.aim_dir = ray[1]
	weapons.aim_point = cam.get_aim_point()
	var info := cam.find_assist_target(weapons.current())
	weapons.assist_target = info[0]
	weapons.assist_strength = info[1]
	var moving := Vector3(velocity.x, 0, velocity.z).length() > 2.0
	weapons.spread_mult = (1.6 if not is_on_floor() else (1.25 if moving else 1.0)) * (0.35 if weapons.scoped else 1.0)
	visual.anim.aim_pitch = clampf(cam.pitch / deg_to_rad(55.0), -1.0, 1.0)


# --- NORMAL (ground / air / wall run) --------------------------------------------

func _update_normal(dt: float) -> void:
	var grounded := is_on_floor()
	var wish := _wish_dir()
	if grounded:
		coyote = COYOTE_TIME
		air_dashes = 1
		air_attacks = 0
		jumped = false
		wallrun_timer = 0.0
	else:
		coyote -= dt

	# Recovery animations are interrupted by movement.
	if weapons.recovering and wish.length() > 0.2:
		weapons.recovering = false
		visual.anim.stop_action(0.12)

	# Horizontal movement.
	var speed_mult: float = weapons.current().move_speed_mult * (1.2 if overdrive_time > 0.0 else 1.0) * (0.6 if weapons.scoped else 1.0)
	if wallrun_timer > 0.0:
		_update_wallrun(dt, wish)
	elif grounded:
		var top := (SPRINT_SPEED if sprinting else RUN_SPEED * lerpf(0.45, 1.0, clampf(input_move.length() * 1.25, 0.0, 1.0))) * speed_mult
		var target := wish.normalized() * top if wish.length() > 0.05 else Vector3.ZERO
		var hv := Vector3(velocity.x, 0, velocity.z)
		var accel := GROUND_ACCEL if target.length() > 0.1 else GROUND_DECEL
		if hv.length() > 1.0 and target.length() > 0.1 and hv.dot(target) < 0.0:
			accel *= REVERSE_BONUS
		# Keep momentum above top speed (e.g. after dashes/pads) but bleed it off smoothly.
		if hv.length() > top and target.length() > 0.1 and hv.normalized().dot(target.normalized()) > 0.7:
			hv = hv.move_toward(target, accel * 0.35 * dt)
		else:
			hv = hv.move_toward(target, accel * dt)
		velocity.x = hv.x
		velocity.z = hv.z
	else:
		var hv := Vector3(velocity.x, 0, velocity.z)
		if wish.length() > 0.1:
			var max_air := maxf(hv.length(), RUN_SPEED * speed_mult)
			hv = hv.move_toward(wish * max_air, AIR_ACCEL * dt)
		else:
			hv = hv.move_toward(Vector3.ZERO, AIR_DRAG * dt)
		velocity.x = hv.x
		velocity.z = hv.z

	# Vertical.
	if wallrun_timer <= 0.0:
		var g_mult := 1.0
		if jumped and velocity.y > 0.0 and not jump_held:
			g_mult = JUMP_CUT_GRAVITY
		# Wall slide: pushing into a wall while falling slows the fall.
		if not grounded and velocity.y < 0.0 and is_on_wall() and wish.dot(-get_wall_normal()) > 0.3:
			velocity.y = maxf(velocity.y, -5.0)
		apply_gravity(dt, g_mult)

	# Jump / wall jump.
	if _buffer["jump"] > 0.0:
		if grounded or coyote > 0.0:
			_consume("jump")
			_do_jump()
		elif wallrun_timer > 0.0:
			_consume("jump")
			_do_wall_jump(wallrun_normal, true)
		else:
			var n := _find_wall(wish)
			if n != Vector3.ZERO:
				_consume("jump")
				_do_wall_jump(n, false)

	# Wall run entry.
	if not grounded and wallrun_timer <= 0.0 and wallrun_cd <= 0.0:
		_try_start_wallrun(wish)

	# Dash.
	if _buffer["dash"] > 0.0 and dash_cd <= 0.0:
		if grounded or air_dashes > 0:
			_consume("dash")
			_start_dash(wish)
			return

	_handle_attack_input(grounded)
	_update_facing(dt, wish)


func _handle_attack_input(grounded: bool) -> void:
	if weapons.is_melee():
		if _consume("attack"):
			var ctx := "ground"
			if not grounded:
				if air_attacks >= 2:
					return
				air_attacks += 1
				ctx = "air"
			elif sprinting and Vector3(velocity.x, 0, velocity.z).length() > SPRINT_SPEED * 0.8:
				ctx = "dash"
			weapons.press_primary(ctx)
		if _consume("special"):
			weapons.press_secondary("air" if not grounded else "ground")
	else:
		if _consume("attack"):
			weapons.press_primary("ground")
		if attack_held:
			weapons.hold_primary()
		if _consume("special"):
			weapons.press_secondary("air" if not grounded else "ground")


func _update_facing(dt: float, wish: Vector3) -> void:
	if is_strafing() and cam:
		facing = cam.yaw
		# Legs follow the movement direction; the spine counter-twists to keep aiming.
		var hv := Vector3(velocity.x, 0, velocity.z)
		var offset := 0.0
		var backward := false
		if hv.length() > 1.0:
			var rel := wrapf(Actor.yaw_from_dir(hv.normalized()) - facing, -PI, PI)
			if absf(rel) > deg_to_rad(105.0):
				backward = true
				rel = wrapf(rel - PI, -PI, PI)
			offset = clampf(rel, deg_to_rad(-65.0), deg_to_rad(65.0))
		visual_yaw_offset = lerp_angle(visual_yaw_offset, offset, clampf(dt * 10.0, 0.0, 1.0))
		visual.twist.yaw = -visual_yaw_offset
		visual.set_meta("backpedal", backward)
	else:
		visual_yaw_offset = lerp_angle(visual_yaw_offset, 0.0, clampf(dt * 10.0, 0.0, 1.0))
		visual.twist.yaw = -visual_yaw_offset
		visual.set_meta("backpedal", false)
		if wish.length() > 0.15:
			var target := Actor.yaw_from_dir(wish.normalized())
			facing = _rotate_toward(facing, target, 16.0 * dt)


static func _rotate_toward(from: float, to: float, max_step: float) -> float:
	var diff := wrapf(to - from, -PI, PI)
	return from + clampf(diff, -max_step, max_step)


func _do_jump() -> void:
	velocity.y = JUMP_VELOCITY
	jumped = true
	coyote = 0.0
	# Sprint-jump keeps momentum; a small boost in the input direction feels snappy.
	var wish := _wish_dir()
	if wish.length() > 0.3:
		var hv := Vector3(velocity.x, 0, velocity.z)
		if hv.length() < RUN_SPEED:
			hv = wish.normalized() * RUN_SPEED * 0.9
			velocity.x = hv.x
			velocity.z = hv.z
	visual.anim.set_base("fall", 0.12, true)
	visual.anim.play_action("Jump_Start", 1.7, 0.04, 0.25, 0.32, 0.32)
	Audio.play("jump", -4.0)
	VFX.dust_ring(global_position, 0.6)


func _find_wall(wish: Vector3) -> Vector3:
	# Probe around the player for a wall to kick off.
	var space := get_world_3d().direct_space_state
	var origin := global_position + Vector3.UP * 1.0
	var dirs: Array[Vector3] = []
	var hv := Vector3(velocity.x, 0, velocity.z)
	if wish.length() > 0.1:
		dirs.append(wish.normalized())
	if hv.length() > 0.5:
		dirs.append(hv.normalized())
	var f := forward()
	dirs.append_array([f, -f, Vector3(f.z, 0, -f.x), Vector3(-f.z, 0, f.x)])
	var best := Vector3.ZERO
	var best_d := INF
	for d in dirs:
		var q := PhysicsRayQueryParameters3D.create(origin, origin + d * WALL_PROBE, Game.LAYER_WORLD)
		var res := space.intersect_ray(q)
		if not res.is_empty():
			var n: Vector3 = res.normal
			if absf(n.y) < 0.35:
				var dist := origin.distance_to(res.position)
				if dist < best_d:
					best_d = dist
					best = Vector3(n.x, 0, n.z).normalized()
	if is_on_wall():
		var wn := get_wall_normal()
		if absf(wn.y) < 0.35:
			best = Vector3(wn.x, 0, wn.z).normalized()
	# Can't kick the same wall twice in a row too quickly.
	if best != Vector3.ZERO and best.dot(_last_wall_normal) > 0.9 and _clock - _last_wall_time < 0.35:
		return Vector3.ZERO
	return best


func _do_wall_jump(n: Vector3, from_run: bool) -> void:
	if not _spend(WALL_JUMP_COST):
		return
	var wish := _wish_dir()
	var along := Vector3.ZERO
	if from_run:
		var hv := Vector3(velocity.x, 0, velocity.z)
		along = hv - n * hv.dot(n)
		along = along.normalized() * minf(along.length(), SPRINT_SPEED) * 0.9
	elif wish.length() > 0.2:
		var side := wish - n * wish.dot(n)
		along = side * RUN_SPEED * 0.6
	velocity = n * WALL_JUMP_OUT + along + Vector3.UP * WALL_JUMP_UP
	wallrun_timer = 0.0
	wallrun_cd = 0.25
	jumped = true
	air_dashes = 1
	air_attacks = 0
	_last_wall_normal = n
	_last_wall_time = _clock
	facing = Actor.yaw_from_dir((velocity * Vector3(1, 0, 1)).normalized())
	visual.anim.set_base("flip_fall", 0.15, true)
	visual.anim.play_action("NinjaJump_Start", 1.6, 0.04, 0.25, 0.12, 0.42)
	Audio.play("wall_kick", -1.0)
	var contact := global_position + Vector3.UP * 1.0 - n * 0.4
	VFX.sparks(contact, n, style.get("glow", Color.CYAN), 0.8, 0.6)
	VFX.shockwave(contact, 0.5, style.get("glow", Color.CYAN))
	Game.vibrate(18)
	if cam:
		cam.kick_fov(5.0)


func _try_start_wallrun(wish: Vector3) -> void:
	if velocity.y > 7.0 or velocity.y < -9.0:
		return
	var hv := Vector3(velocity.x, 0, velocity.z)
	if hv.length() < WALLRUN_MIN_SPEED or stamina < WALLRUN_COST:
		return
	var n := Vector3.ZERO
	if is_on_wall():
		n = get_wall_normal()
	else:
		var space := get_world_3d().direct_space_state
		var origin := global_position + Vector3.UP * 1.0
		var side := Vector3(hv.z, 0, -hv.x).normalized()
		for d in [side, -side]:
			var q := PhysicsRayQueryParameters3D.create(origin, origin + d * 1.05, Game.LAYER_WORLD)
			var res := space.intersect_ray(q)
			if not res.is_empty() and absf((res.normal as Vector3).y) < 0.3:
				n = res.normal
				break
	if n == Vector3.ZERO or absf(n.y) > 0.3:
		return
	n = Vector3(n.x, 0, n.z).normalized()
	var vdir := hv.normalized()
	# Needs to be running along the wall, not into it.
	if absf(vdir.dot(n)) > 0.62 or (wish.length() > 0.2 and wish.dot(n) > 0.5):
		return
	if n.dot(_last_wall_normal) > 0.9 and _clock - _last_wall_time < 0.5:
		return
	_spend(WALLRUN_COST)
	wallrun_timer = WALLRUN_TIME
	wallrun_normal = n
	velocity.y = maxf(velocity.y, 3.2)
	var along := hv - n * hv.dot(n)
	along = along.normalized() * maxf(along.length(), SPRINT_SPEED * 0.95)
	velocity.x = along.x
	velocity.z = along.z
	air_dashes = 1
	visual.anim.set_base("wallrun", 0.1)
	Audio.play("wall_kick", -8.0, 1.3)


func _update_wallrun(dt: float, wish: Vector3) -> void:
	wallrun_timer -= dt
	var hv := Vector3(velocity.x, 0, velocity.z)
	var along := hv - wallrun_normal * hv.dot(wallrun_normal)
	var spd := maxf(along.length(), SPRINT_SPEED * 0.9)
	along = along.normalized() * spd
	velocity.x = along.x - wallrun_normal.x * 2.0
	velocity.z = along.z - wallrun_normal.z * 2.0
	velocity.y -= gravity * WALLRUN_GRAVITY * dt
	facing = Actor.yaw_from_dir(along.normalized())
	# Lean away from the wall.
	var right := Vector3(cos(facing), 0, -sin(facing))
	var side := signf(right.dot(wallrun_normal))
	visual.set_lean(side * 0.35, 0.0)
	# Leave the wall when it ends, time runs out, or the player steers away.
	var space := get_world_3d().direct_space_state
	var origin := global_position + Vector3.UP * 1.0
	var q := PhysicsRayQueryParameters3D.create(origin, origin - wallrun_normal * 0.9, Game.LAYER_WORLD)
	var still_wall := not space.intersect_ray(q).is_empty()
	if wallrun_timer <= 0.0 or not still_wall or is_on_floor() or (wish.length() > 0.3 and wish.dot(wallrun_normal) > 0.6):
		wallrun_timer = 0.0
		wallrun_cd = 0.3
		_last_wall_normal = wallrun_normal
		_last_wall_time = _clock
		visual.set_lean(0.0, 0.0)
	afterimage_timer -= dt
	if afterimage_timer <= 0.0:
		afterimage_timer = 0.09
		visual.spawn_afterimage(style.get("glow", Color.CYAN), 0.25)


# --- DASH ---------------------------------------------------------------------------

func _start_dash(wish: Vector3) -> void:
	var grounded := is_on_floor()
	if not _spend(DASH_COST if grounded else AIR_DASH_COST):
		return
	var dir := wish.normalized() if wish.length() > 0.15 else (-aim_dir_flat() if is_strafing() else forward())
	dash_dir = dir
	dash_timer = DASH_TIME
	dash_cd = DASH_COOLDOWN
	dash_in_air = not grounded
	if dash_in_air:
		air_dashes -= 1
	invuln = DASH_IFRAMES
	weapons.cancel_attack()
	set_state(State.DASH)
	velocity = dir * DASH_SPEED
	velocity.y = 0.0 if dash_in_air else -1.0
	# Face the dash direction unless strafing with a gun (then dodge sideways/backward).
	var rel := 0.0
	if is_strafing():
		rel = wrapf(Actor.yaw_from_dir(dir) - facing, -PI, PI)
	else:
		facing = Actor.yaw_from_dir(dir)
		visual.rotation.y = facing
	if dash_in_air:
		visual.anim.play_action("NinjaJump_Start", 1.8, 0.03, 0.2, 0.18, DASH_TIME + 0.12)
		Audio.play("air_dash", -2.0)
	elif is_strafing() and absf(rel) > deg_to_rad(60.0):
		visual.anim.play_action("Roll", 2.6, 0.03, 0.18, 0.12, DASH_TIME + 0.14)
		visual_yaw_offset = rel
		Audio.play("dash", -2.0)
	else:
		visual.anim.play_action("Slide_Start", 2.4, 0.03, 0.2, 0.2, DASH_TIME + 0.1)
		Audio.play("dash", -2.0)
	afterimage_timer = 0.0
	var glow: Color = style.get("glow", Color.CYAN)
	VFX.sparks(global_position + Vector3.UP * 0.3, -dir, glow, 0.6, 0.6)
	if not dash_in_air:
		VFX.dust_ring(global_position, 0.8)
	if cam:
		cam.kick_fov(9.0)
	Game.vibrate(12)


func _update_dash(dt: float) -> void:
	dash_timer -= dt
	var t := 1.0 - dash_timer / DASH_TIME
	var spd := lerpf(DASH_SPEED, DASH_EXIT_SPEED, t * t)
	velocity.x = dash_dir.x * spd
	velocity.z = dash_dir.z * spd
	if dash_in_air:
		velocity.y = 0.0
	else:
		apply_gravity(dt)
	afterimage_timer -= dt
	if afterimage_timer <= 0.0:
		afterimage_timer = 0.05
		visual.spawn_afterimage(style.get("glow", Color.CYAN), 0.3)
	# Dash cancels: attack -> dash attack, jump -> momentum jump.
	if weapons.is_melee() and _consume("attack"):
		set_state(State.NORMAL)
		if dash_in_air:
			air_attacks += 1
			weapons.press_primary("air")
		else:
			weapons.press_primary("dash")
		return
	if not dash_in_air and _buffer["jump"] > 0.0 and is_on_floor():
		_consume("jump")
		set_state(State.NORMAL)
		velocity = dash_dir * maxf(spd, SPRINT_SPEED)
		_do_jump()
		return
	if dash_timer <= 0.0:
		set_state(State.NORMAL)
		var exit := DASH_EXIT_SPEED if (sprinting or input_move.length() > 0.5) else RUN_SPEED * 0.8
		velocity.x = dash_dir.x * exit
		velocity.z = dash_dir.z * exit
		visual_yaw_offset = 0.0


# --- ATTACK -------------------------------------------------------------------------

func _update_attack(dt: float) -> void:
	var a := weapons.attack
	if a == null:
		set_state(State.NORMAL)
		return
	if weapons.plunging:
		velocity.y = -WeaponController.PLUNGE_SPEED
		steer_horizontal(weapons.lunge_dir * 2.0, 20.0, dt)
		return
	if weapons.attack_time < weapons.lunge_time:
		steer_horizontal(weapons.lunge_dir * weapons.lunge_speed, 160.0, dt)
	else:
		steer_horizontal(Vector3.ZERO, 45.0, dt)
	if a.air_hang and not is_on_floor():
		velocity.y = maxf(velocity.y - gravity * 0.3 * dt, -1.5) if weapons.attack_time < a.duration * 0.8 else velocity.y - gravity * dt
	else:
		apply_gravity(dt)
	# Cancels (S4-style): dash or jump out of the recovery frames.
	if weapons.can_cancel():
		if _buffer["dash"] > 0.0 and dash_cd <= 0.0 and (is_on_floor() or air_dashes > 0):
			_consume("dash")
			weapons.cancel_attack()
			_start_dash(_wish_dir())
			return
		if _buffer["jump"] > 0.0 and is_on_floor():
			_consume("jump")
			weapons.cancel_attack()
			set_state(State.NORMAL)
			_do_jump()
			return
	if weapons.is_melee() and _buffer["attack"] > 0.0:
		_consume("attack")
		weapons.press_primary("air" if not is_on_floor() else "ground")
	if _consume("special"):
		weapons.press_secondary("ground")


# --- Landing / animation --------------------------------------------------------------

func _on_landed(fall_speed: float) -> void:
	super._on_landed(fall_speed)
	if state == State.ATTACK and weapons.plunging:
		weapons.on_plunge_landed()
		return
	if state == State.NORMAL or state == State.DASH:
		if fall_speed > 14.0 and _land_anim_cd <= 0.0:
			_land_anim_cd = 0.4
			visual.anim.play_action("Jump_Land", 1.8, 0.03, 0.2, 0.12, 0.28 if input_move.length() < 0.2 else 0.16)
			VFX.dust_ring(global_position, 1.0 + fall_speed * 0.04)
			if cam:
				cam.add_trauma(clampf(fall_speed * 0.012, 0.0, 0.3))
		Audio.play("land", -6.0 + clampf(fall_speed * 0.3, 0.0, 6.0))
	jumped = false


func _update_anim(dt: float) -> void:
	var anim := visual.anim
	var hv := Vector3(velocity.x, 0, velocity.z)
	var spd := hv.length()
	if state == State.DASH:
		return
	if wallrun_timer > 0.0:
		anim.set_base("wallrun", 0.12)
		anim.base_speed = 1.3
		return
	visual.set_lean(0.0, 0.0)
	if is_on_floor():
		if spd < 0.8:
			anim.set_base("idle_blade" if weapons.is_melee() else "idle", 0.22)
			anim.base_speed = 1.0
		else:
			anim.set_base("move", 0.14)
			anim.move_blend = clampf(spd * 0.82, 1.6, 9.5)
			var back: bool = visual.get_meta("backpedal", false)
			anim.base_speed = (-1.0 if back else 1.0) * clampf(spd / (6.0 if spd < 9.0 else 8.6), 0.75, 1.45)
			# Lean into acceleration and turns.
			var lean_roll := clampf(-visual_yaw_offset * 0.08, -0.2, 0.2)
			visual.set_lean(lean_roll, clampf(spd / SPRINT_SPEED, 0.0, 1.0) * 0.08)
			_step_timer -= dt * spd
			if _step_timer <= 0.0:
				_step_timer = 2.2
				Audio.play("step", -16.0, 1.0, 0.12, 60)
	else:
		if anim.base_state not in ["fall", "flip_fall"]:
			anim.set_base("fall", 0.2)
		anim.base_speed = 1.0
		if anim.base_state == "flip_fall" and velocity.y < -6.0:
			anim.set_base("fall", 0.35)


# --- Combat callbacks -------------------------------------------------------------

func _on_hit_landed(target: Actor, hit: HitInfo, killed: bool) -> void:
	combo += 1
	combo_timer = COMBO_TIMEOUT
	best_combo = maxi(best_combo, combo)
	combo_changed.emit(combo)
	damage_dealt += hit.damage
	if overdrive_time <= 0.0:
		var was_full := overdrive >= 100.0
		overdrive = minf(overdrive + hit.damage * 0.55 + (12.0 if killed else 0.0), 100.0)
		if overdrive >= 100.0 and not was_full:
			Audio.play("overdrive_ready", -2.0)
	if killed:
		kills += 1
		Audio.play("kill", -3.0)
	if cam and not hit.is_melee:
		cam.hitmarker(killed)


func take_hit(hit: HitInfo) -> bool:
	if god_mode:
		return false
	var ok := super.take_hit(hit)
	if ok:
		Audio.play("player_hurt", -2.0)
		Game.vibrate(30 if hit.reaction < HitInfo.Reaction.KNOCKDOWN else 70)
		if cam:
			cam.add_trauma(0.25 if hit.reaction < HitInfo.Reaction.KNOCKDOWN else 0.5)
		dash_timer = 0.0
		wallrun_timer = 0.0
	return ok


func on_recoil_jump() -> void:
	jumped = false
	air_dashes = 1
	if state != State.NORMAL:
		set_state(State.NORMAL)
	visual.anim.set_base("flip_fall", 0.1, true)
	visual.anim.play_action("NinjaJump_Start", 1.5, 0.04, 0.25, 0.1, 0.45)


## Launches the player (jump pads).
func launch(v: Vector3) -> void:
	if not is_alive():
		return
	if state == State.ATTACK:
		weapons.cancel_attack()
	if state == State.DASH or state == State.ATTACK:
		set_state(State.NORMAL)
	velocity = v
	jumped = false
	air_dashes = 1
	air_attacks = 0
	wallrun_timer = 0.0
	visual.anim.set_base("flip_fall", 0.1, true)
	visual.anim.play_action("NinjaJump_Start", 1.3, 0.04, 0.3, 0.05, 0.5)
	if cam:
		cam.kick_fov(10.0)


func activate_overdrive() -> void:
	if overdrive < 100.0 or overdrive_time > 0.0 or not is_alive():
		return
	overdrive = 0.0
	overdrive_time = OVERDRIVE_TIME
	weapons.damage_mult = 1.35
	weapons.speed_mult = 1.2
	visual.set_overdrive(1.0)
	overdrive_changed.emit(true)
	Audio.play("overdrive", 2.0)
	var orange := Color(1.0, 0.5, 0.15)
	VFX.shockwave(global_position, 7.0, orange)
	VFX.spawn_pillar(global_position, orange, 7.0, 0.7)
	VFX.burst(global_position + Vector3.UP, orange, 30, 14.0)
	Game.shake(0.6)
	Game.vibrate(80)
	if cam:
		cam.kick_fov(16.0)
	# Activation blast knocks nearby enemies down.
	for t in Game.hostiles_of(team):
		var to: Vector3 = t.global_position - global_position
		if to.length() < 6.5:
			var hit := HitInfo.new()
			hit.source = self
			hit.damage = 15.0
			hit.reaction = HitInfo.Reaction.KNOCKDOWN
			hit.knockback = 12.0
			hit.lift = 6.0
			hit.direction = Vector3(to.x, 0, to.z).normalized()
			hit.position = t.chest_position()
			hit.color = orange
			hit.is_explosion = true
			t.take_hit(hit)
	# Brief dramatic slow motion.
	Engine.time_scale = 0.35
	get_tree().create_timer(0.25, true, false, true).timeout.connect(func() -> void: Engine.time_scale = 1.0)


func _end_overdrive() -> void:
	overdrive_time = 0.0
	weapons.damage_mult = 1.0
	weapons.speed_mult = 1.0
	visual.set_overdrive(0.0)
	overdrive_changed.emit(false)


func _on_death(_hit: HitInfo) -> void:
	_end_overdrive()
	Audio.play("game_over", 0.0)
	if cam:
		cam.add_trauma(0.6)
