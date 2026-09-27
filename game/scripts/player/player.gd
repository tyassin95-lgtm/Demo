class_name Player
extends Actor
## Player character. Movement follows S4 League's rules: the body always faces the
## camera (strafing), double-tap forward to sprint (sprinting in mid-air falls faster:
## bunny hops), JUMP + left/right is a side dodge (jump-cancelable into wave dashes),
## wall jumps only from a jump and reflect off the wall (angle in = angle out; near the
## top of a wall they carry you over it), a short delay between jumps, crouch, speed set
## by the equipped weapon, and dodge/jump recoveries from hits. SP (stamina) pays for
## dodges and wall jumps. Plus weapons, overdrive and combo tracking.

signal overdrive_changed(active: bool)
signal combo_changed(count: int)

# --- Movement tuning (speeds at 100 % weapon mobility) -------------------------
const RUN_SPEED := 8.2
const SPRINT_SPEED := 13.0
const CROUCH_SPEED := 2.6
const GROUND_ACCEL := 95.0
const GROUND_DECEL := 80.0
const AIR_ACCEL := 10.0
const AIR_SPRINT_ACCEL := 20.0
const AIR_DRAG := 1.0
## Share of the run speed you can walk at while swinging a melee weapon.
const ATTACK_WALK := 0.45
const JUMP_VELOCITY := 10.4
## Sprinting in mid-air ("air dash"): gravity multipliers going up / coming down.
const AIR_DASH_RISE := 1.3
const AIR_DASH_FALL := 2.0
## Delay between landing and the next jump or dodge.
const LANDING_LAG := 0.14
const COYOTE_TIME := 0.06
const BUFFER_TIME := 0.22
const DOUBLE_TAP_TIME := 0.3
## How far sideways the stick/keys must point for JUMP to become a dodge.
const DODGE_INPUT := 0.5
const DODGE_COST := 20.0
const DODGE_SPEED := 15.5
const DODGE_END_SPEED := 5.0
const DODGE_TIME := 0.28
const DODGE_RECOVERY := 0.22
const DODGE_JUMP_CANCEL := 0.1
const AIR_DODGE_LIFT := 3.8
const WALL_JUMP_COST := 20.0
const WALL_JUMP_UP := 11.6
const WALL_JUMP_MIN_OUT := 5.5
const WALL_JUMP_MAX_OUT := 13.0
const WALL_PLANT_TIME := 0.07
const WALL_PROBE := 0.85
## After a wall kick the reflected arc can't be steered for a moment.
const WALL_JUMP_LOCK := 0.3
## Knocked-flying players can recover (JUMP, or a dodge) after this long; the throw's
## path then stays fixed for a moment.
const THROW_RECOVER_TIME := 0.2
const THROW_PATH_LOCK := 0.3
## Dodging out of a stagger ("faint") costs almost the whole gauge.
const FAINT_COST := 90.0
const STAMINA_MAX := 100.0
const STAMINA_REGEN := 22.0
const STAMINA_DELAY := 0.6
const SPRINT_DRAIN := 5.0
const SPRINT_MIN := 5.0
const OVERDRIVE_TIME := 8.0
const COMBO_TIMEOUT := 2.6

var stamina := STAMINA_MAX
var stamina_delay := 0.0
var sprinting := false
## True while SP is too low for a dodge or wall jump.
var exhausted := false
var crouching := false
## Set by jumps (ground, wall, jump-cancel): wall jumps are only possible during one.
var jump_state := false
var air_dodge_ready := true
var coyote := 0.0
var land_lag := 0.0
var dodge_time := 0.0
var dodge_dir := Vector3.RIGHT
var dodge_side := 1.0
var dodge_in_air := false
## > 0 while the feet are planted on a wall, right before the kick.
var wall_plant := 0.0
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
var crouch_held := false
var _buffer := {"jump": 0.0, "attack": 0.0, "special": 0.0, "sprint": 0.0}
var _fwd_down := false
var _fwd_tap := -10.0
var _sprint_armed := 0.0
var _wall_out := Vector3.ZERO
var _wall_reverse := false
var _last_wall_normal := Vector3.ZERO
var _last_wall_time := -10.0
var _last_shot_time := -10.0
var _air_lock := 0.0
var _dodge_recovering := false
var _step_timer := 0.0
## Set by jump pads: no air drag until landing so ballistic arcs stay exact.
var _pad_flight := false
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
	weapons.fired.connect(func(_id: String) -> void: _last_shot_time = _clock)
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


func _cam_right() -> Vector3:
	var yaw := cam.yaw if cam else facing
	return Vector3(cos(yaw), 0.0, -sin(yaw))


func _wish_dir() -> Vector3:
	if cam == null:
		return Vector3.ZERO
	var yaw := cam.yaw
	var fwd := Vector3(-sin(yaw), 0.0, -cos(yaw))
	var right := Vector3(cos(yaw), 0.0, -sin(yaw))
	var v := right * input_move.x + fwd * input_move.y
	return v.limit_length(1.0)


## -1 / +1 when left / right is held firmly enough for JUMP to dodge, else 0.
func _lateral_input() -> float:
	return signf(input_move.x) if absf(input_move.x) >= DODGE_INPUT else 0.0


## The body always faces where the camera looks (S4-style third-person shooter).
func is_strafing() -> bool:
	return true


## Movement speed factor of the equipped weapon (lower while firing or scoped).
func mobility() -> float:
	var w := weapons.current()
	var m := w.move_speed_mult if w else 1.0
	if w and (weapons.scoped or (w.kind != WeaponDB.Kind.MELEE and attack_held)):
		m = w.move_speed_firing
	return m * (1.2 if overdrive_time > 0.0 else 1.0)


func can_act() -> bool:
	return state == State.NORMAL or (state == State.ATTACK and weapons.can_cancel())


func chest_position() -> Vector3:
	return global_position + Vector3(0, 0.8 if crouching else 1.25, 0)


func _turn_speed() -> float:
	return 40.0


# --- Input ------------------------------------------------------------------------

func _gather_input(dt: float) -> void:
	for k in _buffer:
		_buffer[k] = maxf(_buffer[k] - dt, 0.0)
	if bot and is_instance_valid(bot):
		bot.call("drive", self, dt)
		_track_double_tap()
		return
	var mv := Vector2(Input.get_axis("move_left", "move_right"), Input.get_axis("move_back", "move_forward"))
	if controls and is_instance_valid(controls):
		mv += controls.move_vector
	input_move = mv.limit_length(1.0)
	_track_double_tap()
	if Input.is_action_just_pressed("jump") or (controls and controls.consume("jump")):
		_buffer["jump"] = BUFFER_TIME
	if Input.is_action_just_pressed("sprint") or (controls and controls.consume("sprint")):
		_buffer["sprint"] = BUFFER_TIME
	if Input.is_action_just_pressed("attack") or (controls and controls.consume("attack")):
		_buffer["attack"] = BUFFER_TIME
	if Input.is_action_just_pressed("special") or (controls and controls.consume("special")):
		_buffer["special"] = BUFFER_TIME
	jump_held = Input.is_action_pressed("jump") or (controls != null and controls.is_held("jump"))
	attack_held = Input.is_action_pressed("attack") or (controls != null and controls.is_held("attack"))
	crouch_held = Input.is_action_pressed("crouch") or (controls != null and controls.crouch_on)
	# Optional assist: pushing the stick all the way forward also starts a sprint.
	if bool(Settings.get_value("auto_sprint")) and controls != null and controls.stick_active and input_move.y > 0.92 and not sprinting:
		_buffer["sprint"] = BUFFER_TIME
	if Input.is_action_just_pressed("camera_swap") and cam:
		cam.swap_shoulder()
	if Input.is_action_just_pressed("reload") or (controls and controls.consume("reload")):
		weapons.start_reload()
	for i in 4:
		if Input.is_action_just_pressed("weapon_%d" % (i + 1)) or (controls and controls.consume("weapon_%d" % (i + 1))):
			weapons.switch_to(i)
	if Input.is_action_just_pressed("weapon_next") or (controls and controls.consume("weapon_next")):
		weapons.cycle(1)
	if Input.is_action_just_pressed("weapon_prev"):
		weapons.cycle(-1)
	if Input.is_action_just_pressed("overdrive") or (controls and controls.consume("overdrive")):
		activate_overdrive()


## Double-tapping forward (keys or a double flick of the stick) requests a sprint.
func _track_double_tap() -> void:
	if input_move.y > 0.6:
		if not _fwd_down:
			_fwd_down = true
			if _clock - _fwd_tap < DOUBLE_TAP_TIME:
				_buffer["sprint"] = BUFFER_TIME
				_fwd_tap = -10.0
			else:
				_fwd_tap = _clock
	elif input_move.y < 0.3:
		_fwd_down = false


## Used by automation to press a buffered action ("jump", "attack", "special", "sprint").
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
	_update_sprint(dt)
	_update_stamina(dt)
	_update_timers(dt)
	_update_aim()
	_try_recovery()
	if _update_reaction_states(dt):
		visual_yaw_offset = 0.0
		visual.twist.yaw = 0.0
		visual.set_lean(0.0, 0.0)
		return
	match state:
		State.NORMAL:
			_update_normal(dt)
		State.DODGE:
			_update_dodge(dt)
		State.ATTACK:
			_update_attack(dt)
	weapons.update(dt)
	_update_anim(dt)


func _update_timers(dt: float) -> void:
	# Gentle regeneration after a few seconds without taking damage.
	if is_alive() and _clock - last_hit_time > 4.5 and health < max_health:
		health = minf(health + 5.0 * dt, max_health)
	land_lag -= dt
	_air_lock -= dt
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


func _update_sprint(dt: float) -> void:
	if _buffer["sprint"] > 0.0:
		_buffer["sprint"] = 0.0
		_sprint_armed = 0.5
	_sprint_armed -= dt
	var forwardish := input_move.y > 0.35
	var grounded := is_on_floor()
	if not sprinting and _sprint_armed > 0.0 and forwardish and state == State.NORMAL and not crouching and not weapons.scoped:
		# On the ground a sprint needs SP; in the air it still makes you fall faster.
		if not grounded or stamina >= SPRINT_MIN:
			sprinting = true
			_sprint_armed = 0.0
			if grounded:
				Audio.play("dash", -12.0, 1.25)
				if cam:
					cam.kick_fov(3.0)
	if sprinting:
		var stop := not forwardish or crouching or weapons.scoped or state != State.NORMAL
		if grounded and stamina <= 0.0:
			stop = true
		if stop:
			sprinting = false


func _update_stamina(dt: float) -> void:
	var hv := Vector3(velocity.x, 0, velocity.z)
	if sprinting and state == State.NORMAL and is_on_floor() and hv.length() > 2.0:
		stamina -= SPRINT_DRAIN * dt
		stamina_delay = STAMINA_DELAY
	elif state != State.DODGE and wall_plant <= 0.0:
		stamina_delay -= dt
		if stamina_delay <= 0.0:
			stamina = minf(stamina + STAMINA_REGEN * dt, STAMINA_MAX)
	stamina = maxf(stamina, 0.0)
	exhausted = stamina < DODGE_COST and overdrive_time <= 0.0


func _spend(amount: float) -> bool:
	if overdrive_time > 0.0:
		return true
	if stamina < amount:
		Audio.play("ui_error", -10.0, 1.0, 0.0, 300)
		return false
	stamina -= amount
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
	weapons.spread_mult = (1.6 if not is_on_floor() else (1.25 if moving else (0.8 if crouching else 1.0))) * (0.35 if weapons.scoped else 1.0)
	visual.anim.aim_pitch = clampf(cam.pitch / deg_to_rad(55.0), -1.0, 1.0)


# --- Recoveries from hits ------------------------------------------------------------

## JUMP (or a dodge) while knocked flying lands you on your feet; a dodge gets you up
## from the floor; dodging out of a stagger ("faint") costs 90 SP.
func _try_recovery() -> void:
	if _buffer["jump"] <= 0.0:
		return
	var side := _lateral_input()
	match state:
		State.KNOCKDOWN:
			if state_time < THROW_RECOVER_TIME or is_on_floor():
				return
			if side != 0.0 and not _spend(DODGE_COST):
				return
			_consume("jump")
			set_state(State.NORMAL)
			_air_lock = THROW_PATH_LOCK
			jump_state = true
			air_dodge_ready = true
			air_attacks = 0
			visual.anim.stop_action(0.08)
			visual.anim.set_base("flip_fall", 0.08, true)
			visual.anim.play_action("NinjaJump_Start", 1.8, 0.03, 0.2, 0.15, 0.35)
			_flip_toward(-Vector3(velocity.x, 0, velocity.z), 1.0, 0.42)
			Audio.play("air_dash", -4.0)
			VFX.sparks(global_position + Vector3.UP, Vector3.UP, style.get("glow", Color.CYAN), 0.6, 0.5)
		State.DOWN:
			if side != 0.0 and stamina >= DODGE_COST:
				_consume("jump")
				set_state(State.NORMAL)
				_start_dodge(side)
		State.STAGGER:
			if side != 0.0 and (stamina >= FAINT_COST or overdrive_time > 0.0):
				_consume("jump")
				if overdrive_time <= 0.0:
					stamina -= FAINT_COST
					stamina_delay = STAMINA_DELAY
				set_state(State.NORMAL)
				_start_dodge(side, true)


# --- NORMAL (ground / air) ------------------------------------------------------------

func _update_normal(dt: float) -> void:
	# Launched by a pad: airborne from the first frame (no ground friction on the arc).
	var grounded := is_on_floor() and not _pad_flight
	var wish := _wish_dir()
	if grounded:
		coyote = COYOTE_TIME
		air_attacks = 0
	else:
		coyote -= dt

	# Feet planted on a wall for a moment, then the kick.
	if wall_plant > 0.0:
		wall_plant -= dt
		velocity = Vector3.ZERO
		if wall_plant <= 0.0:
			_launch_wall_jump()
		_update_facing(dt)
		return

	_update_crouch(grounded)

	# Recovery animations are interrupted by movement.
	if weapons.recovering and wish.length() > 0.2:
		weapons.recovering = false
		visual.anim.stop_action(0.12)

	var mob := mobility()
	var hv := Vector3(velocity.x, 0, velocity.z)
	if grounded:
		var top: float
		if crouching:
			top = CROUCH_SPEED
		elif sprinting:
			top = SPRINT_SPEED * mob
		else:
			top = RUN_SPEED * mob * lerpf(0.45, 1.0, clampf(input_move.length() * 1.25, 0.0, 1.0))
		var target := wish.normalized() * top if wish.length() > 0.05 else Vector3.ZERO
		var accel := GROUND_ACCEL if target.length() > 0.1 else GROUND_DECEL
		# Keep extra momentum (jump pads, dodges) but bleed it off smoothly.
		if hv.length() > top and target.length() > 0.1 and hv.normalized().dot(target.normalized()) > 0.7:
			hv = hv.move_toward(target, accel * 0.3 * dt)
		else:
			hv = hv.move_toward(target, accel * dt)
	elif _air_lock <= 0.0:
		if sprinting and stamina > 0.0:
			# Air dash: drive toward sprint speed where the stick points (or ahead).
			var dir := wish.normalized() if wish.length() > 0.1 else aim_dir_flat()
			hv = hv.move_toward(dir * maxf(SPRINT_SPEED * mob, hv.length()), AIR_SPRINT_ACCEL * dt)
		elif wish.length() > 0.1:
			var max_air := maxf(hv.length(), RUN_SPEED * mob)
			hv = hv.move_toward(wish * max_air, AIR_ACCEL * dt)
		elif not _pad_flight:
			hv = hv.move_toward(Vector3.ZERO, AIR_DRAG * dt)
	velocity.x = hv.x
	velocity.z = hv.z

	# Gravity: sprinting in the air makes you drop faster (bunny hops).
	if sprinting and not grounded:
		apply_gravity(dt, AIR_DASH_RISE if velocity.y > 0.0 else AIR_DASH_FALL)
	else:
		apply_gravity(dt)

	# JUMP button: jump, side dodge (with left/right), wall jump (mid-jump next to a wall).
	if _buffer["jump"] > 0.0:
		_handle_jump_button(grounded, wish)
		if state != State.NORMAL or wall_plant > 0.0:
			return

	_handle_attack_input(grounded)
	_update_facing(dt)


func _handle_jump_button(grounded: bool, wish: Vector3) -> void:
	var side := _lateral_input()
	if grounded or coyote > 0.0:
		if land_lag > 0.0:
			return
		_consume("jump")
		if side != 0.0:
			_start_dodge(side)
		else:
			_do_jump()
		return
	if jump_state:
		var wall := _find_wall(wish)
		if not wall.is_empty():
			_consume("jump")
			_start_wall_jump(wall["normal"], wall["reverse"])
			return
	if side != 0.0 and air_dodge_ready:
		_consume("jump")
		_start_dodge(side)


func _handle_attack_input(grounded: bool) -> void:
	# No attacking while crouched.
	if crouching:
		_buffer["attack"] = 0.0
		_buffer["special"] = 0.0
		return
	if weapons.is_melee():
		if _consume("attack"):
			var ctx := "ground"
			if not grounded:
				if air_attacks >= 2:
					return
				air_attacks += 1
				ctx = "air"
			elif sprinting and Vector3(velocity.x, 0, velocity.z).length() > SPRINT_SPEED * mobility() * 0.8:
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


func _update_facing(dt: float) -> void:
	if cam:
		facing = cam.yaw
	var offset := 0.0
	var backward := false
	if state == State.DODGE and not dodge_in_air and dodge_time < DODGE_TIME:
		# Duck-and-slide: the legs turn toward the dodge.
		offset = wrapf(Actor.yaw_from_dir(dodge_dir) - facing, -PI, PI)
		visual_yaw_offset = lerp_angle(visual_yaw_offset, offset, clampf(dt * 30.0, 0.0, 1.0))
		visual.twist.yaw = 0.0
		visual.set_meta("backpedal", false)
		return
	var hv := Vector3(velocity.x, 0, velocity.z)
	if hv.length() > 1.0 and is_on_floor():
		# Legs follow the movement direction; the spine counter-twists to keep aiming.
		var rel := wrapf(Actor.yaw_from_dir(hv.normalized()) - facing, -PI, PI)
		if absf(rel) > deg_to_rad(105.0):
			backward = true
			rel = wrapf(rel - PI, -PI, PI)
		offset = clampf(rel, deg_to_rad(-65.0), deg_to_rad(65.0))
	visual_yaw_offset = lerp_angle(visual_yaw_offset, offset, clampf(dt * 12.0, 0.0, 1.0))
	visual.twist.yaw = -visual_yaw_offset
	visual.set_meta("backpedal", backward)


## Rotates the body once around the horizontal axis so the head leads toward `dir`.
func _flip_toward(dir: Vector3, turns: float, duration: float) -> void:
	var d := Vector3(dir.x, 0.0, dir.z)
	if d.length() < 0.5:
		d = aim_dir_flat()
	var local := visual.global_basis.inverse() * d.normalized()
	local.y = 0.0
	if local.length() < 0.01:
		return
	visual.spin(Vector3.UP.cross(local.normalized()), turns, duration)


func _do_jump() -> void:
	velocity.y = JUMP_VELOCITY
	jump_state = true
	air_dodge_ready = true
	coyote = 0.0
	if crouching:
		crouching = false
		_set_crouch_shape(false)
	var hv := Vector3(velocity.x, 0, velocity.z)
	if sprinting:
		# Sprint jump: a quick low hop (air dash gravity), no somersault.
		visual.anim.set_base("fall", 0.1, true)
		visual.anim.play_action("Jump_Start", 1.9, 0.03, 0.2, 0.32, 0.25)
	else:
		# The S4 jump is a somersault.
		visual.anim.set_base("flip_fall", 0.08, true)
		visual.anim.play_action("NinjaJump_Start", 1.7, 0.03, 0.22, 0.12, 0.3)
		_flip_toward(hv if hv.length() > 2.0 else aim_dir_flat(), 1.0, 0.52)
	Audio.play("jump", -4.0)
	VFX.dust_ring(global_position, 0.6)


# --- Crouch -----------------------------------------------------------------------------

func _update_crouch(grounded: bool) -> void:
	var want := crouch_held and grounded and not sprinting
	if want == crouching:
		return
	if want:
		crouching = true
		_set_crouch_shape(true)
	elif _can_stand():
		crouching = false
		_set_crouch_shape(false)


func _set_crouch_shape(on: bool) -> void:
	var cap := body_shape.shape as CapsuleShape3D
	cap.height = (1.2 if on else 1.8) * visual_scale
	body_shape.position.y = cap.height * 0.5


func _can_stand() -> bool:
	var q := PhysicsShapeQueryParameters3D.new()
	var sphere := SphereShape3D.new()
	sphere.radius = 0.34
	q.shape = sphere
	q.transform = Transform3D(Basis.IDENTITY, global_position + Vector3.UP * 1.45)
	q.collision_mask = Game.LAYER_WORLD
	return get_world_3d().direct_space_state.intersect_shape(q, 1).is_empty()


# --- Wall jump ---------------------------------------------------------------------------

## Looks for a wall within kicking range. Returns {normal, reverse} or {} if none.
## `reverse` means the wall's top is below head height: S4's "reverse wall jump"
## carries you forward over the wall instead of bouncing back.
func _find_wall(wish: Vector3) -> Dictionary:
	var space := get_world_3d().direct_space_state
	var origin := global_position + Vector3.UP * 1.0
	var dirs: Array[Vector3] = []
	var hv := Vector3(velocity.x, 0, velocity.z)
	if hv.length() > 0.5:
		dirs.append(hv.normalized())
	if wish.length() > 0.1:
		dirs.append(wish.normalized())
	var f := aim_dir_flat()
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
	if best == Vector3.ZERO:
		return {}
	if best.dot(_last_wall_normal) > 0.9 and _clock - _last_wall_time < 0.3:
		return {}
	var head := global_position + Vector3.UP * 1.75
	var q2 := PhysicsRayQueryParameters3D.create(head, head - best * (WALL_PROBE + 0.3), Game.LAYER_WORLD)
	return {"normal": best, "reverse": space.intersect_ray(q2).is_empty()}


func _start_wall_jump(n: Vector3, reverse: bool) -> void:
	if not _spend(WALL_JUMP_COST):
		return
	var hv := Vector3(velocity.x, 0, velocity.z)
	var out: Vector3
	if reverse:
		var ahead := hv if hv.dot(-n) > 1.0 else -n
		out = ahead.normalized() * clampf(hv.length(), WALL_JUMP_MIN_OUT, WALL_JUMP_MAX_OUT)
	else:
		# Mirror the approach: the angle going in equals the angle coming out.
		var into := hv.dot(n)
		out = hv - 2.0 * into * n if into < 0.0 else hv
		var away := out.dot(n)
		if away < WALL_JUMP_MIN_OUT:
			out += n * (WALL_JUMP_MIN_OUT - away)
		out = out.limit_length(WALL_JUMP_MAX_OUT)
	_wall_out = out + Vector3.UP * WALL_JUMP_UP
	_wall_reverse = reverse
	wall_plant = WALL_PLANT_TIME
	velocity = Vector3.ZERO
	sprinting = false
	jump_state = true
	air_dodge_ready = true
	air_attacks = 0
	_last_wall_normal = n
	_last_wall_time = _clock
	visual.stop_spin()
	visual.anim.play_action("NinjaJump_Land", 2.2, 0.02, 0.08, 0.05, WALL_PLANT_TIME + 0.04)
	Audio.play("wall_kick", -1.0)
	var contact := global_position + Vector3.UP * 0.6 - n * 0.4
	VFX.sparks(contact, n, style.get("glow", Color.CYAN), 0.8, 0.6)
	VFX.shockwave(contact, 0.5, style.get("glow", Color.CYAN))


func _launch_wall_jump() -> void:
	velocity = _wall_out
	_air_lock = WALL_JUMP_LOCK
	visual.anim.set_base("flip_fall", 0.06, true)
	visual.anim.play_action("NinjaJump_Start", 1.8, 0.03, 0.25, 0.12, 0.36)
	_flip_toward(_wall_out, 1.0, 0.5)
	Game.vibrate(18)
	if cam:
		cam.kick_fov(5.0)


# --- DODGE (JUMP + left/right) ----------------------------------------------------------

func _start_dodge(side: float, free: bool = false) -> bool:
	if not free and not _spend(DODGE_COST):
		return false
	dodge_side = side
	dodge_dir = _cam_right() * side
	dodge_time = 0.0
	dodge_in_air = not is_on_floor()
	_dodge_recovering = false
	sprinting = false
	_sprint_armed = 0.0
	if crouching:
		crouching = false
		_set_crouch_shape(false)
	weapons.cancel_attack()
	weapons.scoped = false
	set_state(State.DODGE)
	velocity.x = dodge_dir.x * DODGE_SPEED
	velocity.z = dodge_dir.z * DODGE_SPEED
	if dodge_in_air:
		# Air dodge: a little lift and a sideways aerial.
		velocity.y = maxf(velocity.y, AIR_DODGE_LIFT)
		air_dodge_ready = false
		visual.anim.play_action("NinjaJump_Start", 1.7, 0.03, 0.2, 0.15, DODGE_TIME + 0.1)
		visual.spin(Vector3.FORWARD, side, DODGE_TIME + 0.08)
		Audio.play("air_dash", -3.0)
	else:
		# Ground dodge: duck and slide sideways.
		velocity.y = -1.0
		visual.anim.play_action("Slide_Start", 2.3, 0.03, 0.12, 0.28, DODGE_TIME)
		VFX.dust_ring(global_position, 0.7)
		Audio.play("dash", -3.0)
	afterimage_timer = 0.0
	VFX.sparks(global_position + Vector3.UP * 0.4, -dodge_dir, style.get("glow", Color.CYAN), 0.5, 0.5)
	if cam:
		cam.kick_fov(4.0)
	Game.vibrate(10)
	return true


func _update_dodge(dt: float) -> void:
	dodge_time += dt
	var t := dodge_time
	if t < DODGE_TIME:
		var k := t / DODGE_TIME
		var spd := lerpf(DODGE_SPEED, DODGE_END_SPEED, k * k)
		velocity.x = dodge_dir.x * spd
		velocity.z = dodge_dir.z * spd
		apply_gravity(dt, 0.5 if dodge_in_air else 1.0)
		afterimage_timer -= dt
		if afterimage_timer <= 0.0:
			afterimage_timer = 0.07
			visual.spawn_afterimage(style.get("glow", Color.CYAN), 0.25)
	else:
		# End lag: the weak spot of a dodge (jump or sprint to cancel it).
		if not _dodge_recovering:
			_dodge_recovering = true
			if is_on_floor():
				visual.anim.play_action("Slide_Exit", 2.2, 0.06, 0.12, 0.0, DODGE_RECOVERY)
		steer_horizontal(Vector3.ZERO, 30.0, dt)
		apply_gravity(dt)
	_update_facing(dt)
	# Jump-cancel (JUMP without left/right): a jump straight out of the dodge. From an
	# air dodge this is a mid-air jump, so dodge/jump chains (wave dashing) cost SP.
	if t >= DODGE_JUMP_CANCEL and _buffer["jump"] > 0.0 and _lateral_input() == 0.0:
		_consume("jump")
		set_state(State.NORMAL)
		visual.stop_spin()
		_do_jump()
		return
	# Sprinting (double-tap) also cancels the end lag.
	if _dodge_recovering and _sprint_armed > 0.0 and is_on_floor():
		set_state(State.NORMAL)
		return
	if t >= DODGE_TIME + DODGE_RECOVERY:
		set_state(State.NORMAL)


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
	elif is_on_floor():
		# You can keep walking while slashing.
		steer_horizontal(_wish_dir() * RUN_SPEED * mobility() * ATTACK_WALK, 40.0, dt)
	else:
		steer_horizontal(Vector3.ZERO, 6.0, dt)
	if a.air_hang and not is_on_floor():
		velocity.y = maxf(velocity.y - gravity * 0.3 * dt, -1.5) if weapons.attack_time < a.duration * 0.8 else velocity.y - gravity * dt
	else:
		apply_gravity(dt)
	# Cancels: JUMP (or a dodge with left/right) or a sprint out of the recovery frames.
	if weapons.can_cancel():
		var side := _lateral_input()
		if _buffer["jump"] > 0.0 and (is_on_floor() or (side != 0.0 and air_dodge_ready)):
			_consume("jump")
			weapons.cancel_attack()
			set_state(State.NORMAL)
			if side != 0.0:
				_start_dodge(side)
			else:
				_do_jump()
			return
		if _sprint_armed > 0.0 and is_on_floor() and input_move.y > 0.35:
			weapons.cancel_attack()
			set_state(State.NORMAL)
			return
	if weapons.is_melee() and _buffer["attack"] > 0.0:
		_consume("attack")
		weapons.press_primary("air" if not is_on_floor() else "ground")
	if _consume("special"):
		weapons.press_secondary("ground")


# --- Landing / animation --------------------------------------------------------------

func _on_landed(fall_speed: float) -> void:
	super._on_landed(fall_speed)
	_pad_flight = false
	_air_lock = 0.0
	if state == State.ATTACK and weapons.plunging:
		weapons.on_plunge_landed()
		jump_state = false
		return
	if state == State.NORMAL or state == State.DODGE:
		if jump_state and air_time > 0.2:
			# A short delay before the next jump; a gun shot right before landing skips it.
			land_lag = 0.0 if _clock - _last_shot_time < 0.2 else LANDING_LAG
		if fall_speed > 14.0 and _land_anim_cd <= 0.0 and state == State.NORMAL:
			_land_anim_cd = 0.4
			visual.anim.play_action("Jump_Land", 1.8, 0.03, 0.2, 0.12, 0.28 if input_move.length() < 0.2 else 0.16)
			VFX.dust_ring(global_position, 1.0 + fall_speed * 0.04)
			if cam:
				cam.add_trauma(clampf(fall_speed * 0.012, 0.0, 0.3))
		Audio.play("land", -6.0 + clampf(fall_speed * 0.3, 0.0, 6.0))
	jump_state = false
	air_dodge_ready = true


func _update_anim(dt: float) -> void:
	var anim := visual.anim
	var hv := Vector3(velocity.x, 0, velocity.z)
	var spd := hv.length()
	if state == State.DODGE:
		return
	visual.set_lean(0.0, 0.0)
	if is_on_floor():
		if crouching:
			anim.set_base("crouch" if spd < 0.5 else "crouch_move", 0.16)
			var back: bool = visual.get_meta("backpedal", false)
			anim.base_speed = 1.0 if spd < 0.5 else (-1.0 if back else 1.0) * clampf(spd / 2.2, 0.6, 1.4)
		elif spd < 0.8:
			anim.set_base("idle_blade" if weapons.is_melee() else "idle", 0.22)
			anim.base_speed = 1.0
		else:
			anim.set_base("move", 0.14)
			anim.move_blend = clampf(spd * 0.82, 1.6, 9.5)
			var back: bool = visual.get_meta("backpedal", false)
			anim.base_speed = (-1.0 if back else 1.0) * clampf(spd / (6.0 if spd < 9.0 else 8.6), 0.75, 1.45)
			# Lean into turns and speed.
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
		if anim.base_state == "flip_fall" and velocity.y < -6.0 and not visual.is_spinning():
			anim.set_base("fall", 0.35)
		if sprinting:
			# Air dash: lean forward into the dive.
			visual.set_lean(0.0, 0.25)
			afterimage_timer -= dt
			if afterimage_timer <= 0.0 and stamina > 0.0:
				afterimage_timer = 0.12
				visual.spawn_afterimage(style.get("glow", Color.CYAN), 0.2)


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
		if state != State.NORMAL and state != State.ATTACK and state != State.DODGE:
			# Hit reactions stop sprints, wall jumps and crouching.
			sprinting = false
			wall_plant = 0.0
			visual.stop_spin()
			if crouching:
				crouching = false
				_set_crouch_shape(false)
	return ok


func on_recoil_jump() -> void:
	jump_state = true
	air_dodge_ready = true
	sprinting = false
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
	if state == State.DODGE or state == State.ATTACK:
		set_state(State.NORMAL)
	velocity = v
	jump_state = false
	sprinting = false
	wall_plant = 0.0
	_pad_flight = true
	air_dodge_ready = true
	air_attacks = 0
	visual.stop_spin()
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
