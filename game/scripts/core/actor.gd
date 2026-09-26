class_name Actor
extends CharacterBody3D
## Base class for the player and enemies: health, hit reactions (flinch, stagger,
## knockdown, get-up), hit-stop, poise, physics helpers and death.

signal damaged(actor: Actor, hit: HitInfo)
signal died(actor: Actor, hit: HitInfo)

enum State { NORMAL, ATTACK, DASH, FLINCH, STAGGER, KNOCKDOWN, DOWN, GETUP, DEAD, SPAWNING }

const FLINCH_TIME := 0.32
const STAGGER_TIME := 0.6
const DOWN_TIME := 0.45
const GETUP_TIME := 0.85
const SEPARATION_RADIUS := 0.85

@export var team := 0
@export var max_health := 100.0
@export var gravity := 30.0
@export var fall_multiplier := 1.3
@export var max_fall_speed := 40.0
## Poise damage required before a non-flinching hit causes a flinch.
@export var poise_max := 28.0
@export var super_armor := false
@export var damage_taken_mult := 1.0
@export var model_path := "res://assets/characters/mannequin_m.scn"
@export var visual_scale := 1.0

var health := 100.0
var state: State = State.NORMAL
var state_time := 0.0
var invuln := 0.0
var hitstop := 0.0
## Logical facing yaw (radians). 0 faces -Z.
var facing := 0.0
var poise := 0.0
var last_hit_time := -100.0
var time_scale := 1.0
var visual: CharacterVisual
var weapons: WeaponController
var style := {}
var was_on_floor := true
var air_time := 0.0
var peak_fall_speed := 0.0
var last_attacker: Actor = null
## Added to the facing when orienting the visual (legs offset while strafing).
var visual_yaw_offset := 0.0
## After a flinch/stagger ends, light reactions are ignored for this long
## (damage still applies). Used by the player to prevent stun-locks.
var flinch_immunity_after_hit := 0.0
var _flinch_immunity := 0.0
var _knock_grounded_time := 0.0
var _clock := 0.0


func _ready() -> void:
	health = max_health
	floor_snap_length = 0.4
	floor_max_angle = deg_to_rad(50.0)
	floor_constant_speed = true
	floor_block_on_wall = true
	wall_min_slide_angle = deg_to_rad(10.0)
	max_slides = 5
	var shape := CollisionShape3D.new()
	var cap := CapsuleShape3D.new()
	cap.radius = 0.38 * visual_scale
	cap.height = 1.8 * visual_scale
	shape.shape = cap
	shape.position = Vector3(0, 0.9 * visual_scale, 0)
	add_child(shape)
	visual = CharacterVisual.new()
	visual.name = "Visual"
	add_child(visual)
	visual.build(model_path, style)
	visual.scale = Vector3.ONE * visual_scale
	weapons = WeaponController.new()
	weapons.name = "Weapons"
	add_child(weapons)
	weapons.actor = self
	Game.register_actor(self)


func _exit_tree() -> void:
	Game.unregister_actor(self)


func is_alive() -> bool:
	return state != State.DEAD and health > 0.0


func is_down() -> bool:
	return state == State.KNOCKDOWN or state == State.DOWN or state == State.GETUP


func chest_position() -> Vector3:
	return global_position + Vector3(0, 1.25 * visual_scale, 0)


func forward() -> Vector3:
	return Vector3(-sin(facing), 0.0, -cos(facing))


func set_state(s: State) -> void:
	state = s
	state_time = 0.0


static func yaw_from_dir(d: Vector3) -> float:
	return atan2(-d.x, -d.z)


func _physics_process(delta: float) -> void:
	_clock += delta
	if hitstop > 0.0:
		hitstop -= delta
		visual.anim.time_scale = 0.0
		visual.tick(delta)
		return
	visual.anim.time_scale = time_scale
	var dt := delta * time_scale
	state_time += dt
	if invuln > 0.0:
		invuln -= dt
	if _flinch_immunity > 0.0:
		_flinch_immunity -= dt
	if _clock - last_hit_time > 1.2:
		poise = move_toward(poise, 0.0, poise_max * dt)
	_actor_update(dt)
	var sep := _separation_velocity()
	var pre_vel := velocity
	velocity = (velocity + sep) * time_scale
	move_and_slide()
	velocity = velocity / maxf(time_scale, 0.001) - sep
	_post_move(dt, pre_vel)
	visual.rotation.y = lerp_angle(visual.rotation.y, facing + visual_yaw_offset, clampf(dt * _turn_speed(), 0.0, 1.0))
	visual.tick(delta)


## Visual turn rate (per second) toward the logical facing.
func _turn_speed() -> float:
	return 18.0


## Overridden by subclasses: control logic for the current state.
func _actor_update(dt: float) -> void:
	_update_reaction_states(dt)


func _post_move(dt: float, pre_vel: Vector3) -> void:
	var on_floor := is_on_floor()
	if not on_floor:
		air_time += dt
		peak_fall_speed = maxf(peak_fall_speed, -velocity.y)
	if on_floor and not was_on_floor:
		_on_landed(peak_fall_speed)
		peak_fall_speed = 0.0
		air_time = 0.0
	was_on_floor = on_floor


func _on_landed(fall_speed: float) -> void:
	if state == State.KNOCKDOWN and state_time > 0.15:
		set_state(State.DOWN)
		Audio.play_at("knockdown", global_position, -2.0)
		VFX.dust_ring(global_position, 1.2)


## Gravity with a heavier fall, clamped to terminal velocity.
func apply_gravity(dt: float, mult: float = 1.0) -> void:
	if is_on_floor() and velocity.y <= 0.0:
		velocity.y = -1.0
		return
	var g := gravity * mult * (fall_multiplier if velocity.y < 0.0 else 1.0)
	velocity.y = maxf(velocity.y - g * dt, -max_fall_speed)


## Accelerates horizontal velocity toward `target` (y ignored).
func steer_horizontal(target: Vector3, accel: float, dt: float) -> void:
	var hv := Vector3(velocity.x, 0.0, velocity.z)
	var tv := Vector3(target.x, 0.0, target.z)
	hv = hv.move_toward(tv, accel * dt)
	velocity.x = hv.x
	velocity.z = hv.z


## Soft push-apart between overlapping actors (they don't physically collide, which
## keeps dashes and melee lunges smooth). Applied only for the current frame's move.
func _separation_velocity() -> Vector3:
	var sep := Vector3.ZERO
	if state == State.DEAD:
		return sep
	for other in Game.actors:
		if other == self or not is_instance_valid(other) or not other.is_alive():
			continue
		var d: Vector3 = global_position - other.global_position
		d.y = 0.0
		var dist := d.length()
		var min_d: float = SEPARATION_RADIUS * (visual_scale + other.visual_scale) * 0.5
		if dist < min_d and absf(global_position.y - other.global_position.y) < 1.6:
			if dist < 0.001:
				d = Vector3(randf() - 0.5, 0.0, randf() - 0.5)
				dist = d.length()
			sep += d / dist * (min_d - dist) * 9.0
	return sep


# --- Damage ------------------------------------------------------------------

## Applies a hit. Returns true if the hit connected.
func take_hit(hit: HitInfo) -> bool:
	if not is_alive() or state == State.SPAWNING:
		return false
	if invuln > 0.0:
		return false
	# Downed characters are invulnerable while getting up (prevents endless juggles),
	# but can still be struck while lying on the ground by heavy moves.
	if state == State.GETUP:
		return false
	if state == State.DOWN and hit.reaction < HitInfo.Reaction.KNOCKDOWN and not hit.is_explosion:
		return false
	var dmg := hit.damage * damage_taken_mult
	health = maxf(health - dmg, 0.0)
	last_hit_time = _clock
	last_attacker = hit.source as Actor
	visual.flash(1.0)
	damaged.emit(self, hit)
	if health <= 0.0:
		_die(hit)
		return true
	var reaction := hit.reaction
	poise += hit.impact
	if reaction == HitInfo.Reaction.NONE and poise >= poise_max:
		reaction = HitInfo.Reaction.FLINCH
	if reaction != HitInfo.Reaction.NONE:
		poise = 0.0
	if super_armor and reaction <= HitInfo.Reaction.STAGGER:
		reaction = HitInfo.Reaction.NONE
	if _flinch_immunity > 0.0 and reaction <= HitInfo.Reaction.STAGGER:
		reaction = HitInfo.Reaction.NONE
	if hit.hitstop > 0.0:
		hitstop = maxf(hitstop, hit.hitstop)
	_apply_reaction(reaction, hit)
	return true


func _apply_reaction(reaction: int, hit: HitInfo) -> void:
	var dir := hit.direction
	dir.y = 0.0
	if dir.length() < 0.01:
		dir = -forward()
	dir = dir.normalized()
	match reaction:
		HitInfo.Reaction.NONE:
			return
		HitInfo.Reaction.FLINCH:
			if state == State.KNOCKDOWN or state == State.DOWN:
				return
			weapons.cancel_attack()
			set_state(State.FLINCH)
			velocity = dir * hit.knockback + Vector3(0, minf(velocity.y, 0.0), 0)
			facing = yaw_from_dir(-dir)
			visual.anim.play_action("Hit_Chest" if randf() < 0.6 else "Hit_Head", 1.3, 0.04, 0.18, 0.0, FLINCH_TIME)
		HitInfo.Reaction.STAGGER:
			if state == State.KNOCKDOWN or state == State.DOWN:
				return
			weapons.cancel_attack()
			set_state(State.STAGGER)
			velocity = dir * maxf(hit.knockback, 4.0) + Vector3(0, maxf(velocity.y, hit.lift), 0)
			facing = yaw_from_dir(-dir)
			visual.anim.play_action("Hit_Head", 0.8, 0.04, 0.22, 0.0, STAGGER_TIME)
		HitInfo.Reaction.KNOCKDOWN, HitInfo.Reaction.LAUNCH:
			weapons.cancel_attack()
			set_state(State.KNOCKDOWN)
			velocity = dir * hit.knockback + Vector3(0, maxf(hit.lift, 4.0), 0)
			facing = yaw_from_dir(-dir)
			visual.rotation.y = facing
			visual.anim.play_action("Hit_Knockback", 1.1, 0.04, 0.2, 0.0, 99.0)
			_knock_grounded_time = 0.0


## Shared handling for hit-reaction states. Returns true if a reaction state is active.
func _update_reaction_states(dt: float) -> bool:
	match state:
		State.FLINCH:
			apply_gravity(dt)
			steer_horizontal(Vector3.ZERO, 30.0, dt)
			if state_time >= FLINCH_TIME:
				set_state(State.NORMAL)
				_flinch_immunity = flinch_immunity_after_hit
			return true
		State.STAGGER:
			apply_gravity(dt)
			steer_horizontal(Vector3.ZERO, 22.0, dt)
			if state_time >= STAGGER_TIME:
				set_state(State.NORMAL)
				_flinch_immunity = flinch_immunity_after_hit
			return true
		State.KNOCKDOWN:
			apply_gravity(dt)
			steer_horizontal(Vector3.ZERO, 4.0, dt)
			if is_on_floor() and state_time > 0.15:
				_knock_grounded_time += dt
				if _knock_grounded_time > 0.05:
					set_state(State.DOWN)
			if state_time > 3.0:
				set_state(State.DOWN)
			return true
		State.DOWN:
			apply_gravity(dt)
			steer_horizontal(Vector3.ZERO, 25.0, dt)
			if state_time >= DOWN_TIME:
				set_state(State.GETUP)
				invuln = GETUP_TIME + 0.25
				visual.anim.play_action("LayToIdle", 1.6, 0.12, 0.2, 0.15, GETUP_TIME)
			return true
		State.GETUP:
			apply_gravity(dt)
			steer_horizontal(Vector3.ZERO, 25.0, dt)
			if state_time >= GETUP_TIME:
				set_state(State.NORMAL)
			return true
		State.DEAD:
			apply_gravity(dt)
			steer_horizontal(Vector3.ZERO, 6.0, dt)
			return true
		State.SPAWNING:
			apply_gravity(dt)
			return true
	return false


func _die(hit: HitInfo) -> void:
	weapons.cancel_attack()
	set_state(State.DEAD)
	var dir := hit.direction
	dir.y = 0.0
	dir = dir.normalized() if dir.length() > 0.01 else -forward()
	velocity = dir * maxf(hit.knockback, 5.0) + Vector3(0, maxf(hit.lift, 5.0), 0)
	facing = yaw_from_dir(-dir)
	visual.anim.play_action("Hit_Knockback" if hit.knockback > 6.0 else "Death01", 1.0, 0.05, 0.2, 0.0, 99.0)
	collision_layer = 0
	died.emit(self, hit)
	Game.notify_death(self)
	_on_death(hit)


## Hook for subclasses (score, dissolve, respawn...).
func _on_death(_hit: HitInfo) -> void:
	pass


func heal(amount: float) -> void:
	health = minf(health + amount, max_health)
