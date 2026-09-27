class_name PlayerCamera
extends Node3D
## Third-person orbit camera: touch/mouse look with sensitivity settings, centred or
## over-the-shoulder view (swappable), collision, speed-based FOV, FOV kicks, trauma
## shake, aim point and aim assist (bullet magnetism + reticle friction).

const PITCH_MIN := deg_to_rad(-62.0)
const PITCH_MAX := deg_to_rad(55.0)
const TOUCH_SCALE := 0.0042
const MOUSE_SCALE := 0.0024
## Horizontal camera offset per view: centred (character slightly left of the
## crosshair), right shoulder, left shoulder.
const SIDE_OFFSETS := [0.28, 0.62, -0.62]

var target: Player
var camera: Camera3D
var yaw := 0.0
var pitch := deg_to_rad(-12.0)
var distance := 3.7
var height := 1.6
var base_fov := 72.0
var hitmarker_time := 0.0
var hitmarker_kill := false

var _look := Vector2.ZERO
var _fov_kick := 0.0
var _trauma := 0.0
var _shake_t := 0.0
var _pivot := Vector3.ZERO
var _cur_dist := 3.7
var _assist_angle := 99.0
var _side := 0.28
var _sphere := SphereShape3D.new()
var _noise := FastNoiseLite.new()


func _ready() -> void:
	top_level = true
	camera = Camera3D.new()
	camera.near = 0.08
	camera.far = 500.0
	camera.fov = base_fov
	add_child(camera)
	camera.current = true
	_sphere.radius = 0.22
	_noise.frequency = 3.0
	_noise.noise_type = FastNoiseLite.TYPE_SIMPLEX
	_side = _side_offset()
	Game.camera = self
	if target:
		_pivot = target.global_position + Vector3.UP * height
		global_position = _pivot


func _unhandled_input(event: InputEvent) -> void:
	if event is InputEventMouseMotion and Input.mouse_mode == Input.MOUSE_MODE_CAPTURED:
		_look += (event as InputEventMouseMotion).relative * MOUSE_SCALE * float(Settings.get_value("mouse_sensitivity"))


## Touch drag input in screen pixels (called by the touch controls).
func add_touch_look(delta_px: Vector2) -> void:
	var vp_h := get_viewport().get_visible_rect().size.y
	# Normalize to a 720p reference so sensitivity feels the same on any screen.
	_look += delta_px * (720.0 / maxf(vp_h, 1.0)) * TOUCH_SCALE


func snap_behind(facing_yaw: float) -> void:
	yaw = facing_yaw


func _side_offset() -> float:
	return SIDE_OFFSETS[clampi(int(Settings.get_value("camera_side")), 0, 2)]


## Cycles centre -> right shoulder -> left shoulder (Z key).
func swap_shoulder() -> void:
	Settings.set_value("camera_side", (int(Settings.get_value("camera_side")) + 1) % 3)
	Audio.play("ui_toggle", -8.0)


func add_trauma(amount: float) -> void:
	_trauma = minf(_trauma + amount, 1.0)


func kick_fov(amount: float) -> void:
	_fov_kick = maxf(_fov_kick, amount)


func hitmarker(kill: bool) -> void:
	hitmarker_time = 0.18 if not kill else 0.35
	hitmarker_kill = kill


func get_aim_ray() -> Array:
	var b := camera.global_basis
	return [camera.global_position, -b.z]


## World point under the crosshair (ignores geometry between camera and player).
func get_aim_point() -> Vector3:
	var o := camera.global_position
	var d := -camera.global_basis.z
	var start := o + d * (_cur_dist + 0.6)
	var q := PhysicsRayQueryParameters3D.create(start, o + d * 220.0, Game.LAYER_WORLD | Game.LAYER_ENEMY)
	var res := get_world_3d().direct_space_state.intersect_ray(q)
	return res.position if not res.is_empty() else o + d * 220.0


## Returns [target Actor or null, strength 0..1] for bullet magnetism.
func find_assist_target(w: WeaponDB.Weapon) -> Array:
	_assist_angle = 99.0
	var assist := float(Settings.get_value("aim_assist"))
	if w == null or assist <= 0.0 or target == null:
		return [null, 0.0]
	var o := camera.global_position
	var d := -camera.global_basis.z
	var best: Actor = null
	var best_score := INF
	var best_ratio := 1.0
	for a in Game.hostiles_of(target.team):
		var actor := a as Actor
		var to := actor.chest_position() - o
		var dist := to.length()
		if dist > w.max_range or dist < 0.5:
			continue
		var ang := rad_to_deg(d.angle_to(to / dist))
		var size_deg := rad_to_deg(atan(0.55 * actor.visual_scale / dist))
		var limit := w.aim_assist_deg * (0.5 + assist) + size_deg
		if ang > limit:
			continue
		var score := ang / limit + dist * 0.004
		if score < best_score:
			var q := PhysicsRayQueryParameters3D.create(o + d * _cur_dist, actor.chest_position(), Game.LAYER_WORLD)
			if not get_world_3d().direct_space_state.intersect_ray(q).is_empty():
				continue
			best_score = score
			best = actor
			best_ratio = ang / limit
			_assist_angle = ang
	if best == null:
		return [null, 0.0]
	return [best, clampf((1.0 - best_ratio * 0.6) * assist, 0.0, 1.0)]


func _physics_process(delta: float) -> void:
	if target == null or not is_instance_valid(target):
		return
	var scoped := target.weapons.scoped
	var sens := float(Settings.get_value("look_sensitivity")) * (float(Settings.get_value("scope_sensitivity")) if scoped else 1.0)
	# Reticle friction: slow the camera slightly when the crosshair is on a target.
	if _assist_angle < 6.0:
		sens *= 1.0 - 0.35 * float(Settings.get_value("aim_assist"))
	var inv := -1.0 if Settings.get_value("invert_y") else 1.0
	yaw -= _look.x * sens
	pitch = clampf(pitch - _look.y * sens * inv, PITCH_MIN, PITCH_MAX)
	_look = Vector2.ZERO
	_assist_magnetism(delta)

	# Pivot follows tightly horizontally, softer vertically (smooths jumps/landings).
	var p := target.global_position + Vector3.UP * height * target.visual_scale
	_pivot.x = p.x
	_pivot.z = p.z
	_pivot.y = lerpf(_pivot.y, p.y, clampf(delta * (14.0 if absf(p.y - _pivot.y) < 2.5 else 30.0), 0.0, 1.0))
	var rot := Basis.from_euler(Vector3(pitch, yaw, 0.0))
	var want_dist := (1.9 if scoped else distance) * (1.0 + clampf(-pitch * 0.25, -0.1, 0.25))
	_side = lerpf(_side, _side_offset(), clampf(delta * 8.0, 0.0, 1.0))
	var off := rot * Vector3(_side * (0.7 if scoped else 1.0), 0.0, 0.0)
	var from := _pivot + off
	var dir := rot * Vector3(0, 0.08, 1.0)
	# Camera collision (sphere cast from the pivot).
	var params := PhysicsShapeQueryParameters3D.new()
	params.shape = _sphere
	params.transform = Transform3D(Basis(), _pivot)
	params.motion = off
	params.collision_mask = Game.LAYER_WORLD
	var space := get_world_3d().direct_space_state
	var side_frac: float = space.cast_motion(params)[0]
	from = _pivot + off * side_frac
	params.transform = Transform3D(Basis(), from)
	params.motion = dir * want_dist
	var frac: float = space.cast_motion(params)[0]
	var hit_dist := want_dist * frac
	if hit_dist < _cur_dist:
		_cur_dist = hit_dist
	else:
		_cur_dist = lerpf(_cur_dist, hit_dist, clampf(delta * 5.0, 0.0, 1.0))
	global_transform = Transform3D(rot, from + dir * maxf(_cur_dist, 0.3))
	var near := global_position.distance_to(target.chest_position())
	target.visual.set_fade(clampf((1.5 - near) / 0.8, 0.0, 0.85))

	# Shake (trauma^2 scaled noise on position and rotation).
	_trauma = move_toward(_trauma, 0.0, delta * 1.6)
	_shake_t += delta * 60.0
	var s := _trauma * _trauma
	camera.position = Vector3(_noise.get_noise_2d(_shake_t, 0.0), _noise.get_noise_2d(0.0, _shake_t), 0.0) * 0.25 * s
	camera.rotation = Vector3(_noise.get_noise_2d(_shake_t, 50.0) * 0.05 * s, _noise.get_noise_2d(50.0, _shake_t) * 0.05 * s, _noise.get_noise_2d(_shake_t, 99.0) * 0.08 * s)

	# FOV: widen with speed, kick on dashes, zoom when scoped.
	var spd := Vector3(target.velocity.x, 0.0, target.velocity.z).length()
	var fov_target := base_fov + clampf((spd - 7.0) / 6.0, 0.0, 1.0) * 9.0 + _fov_kick
	if scoped:
		fov_target = 34.0
	if target.overdrive_time > 0.0:
		fov_target += 4.0
	camera.fov = lerpf(camera.fov, fov_target, clampf(delta * 9.0, 0.0, 1.0))
	_fov_kick = move_toward(_fov_kick, 0.0, delta * 28.0)
	hitmarker_time = maxf(hitmarker_time - delta, 0.0)


## Gently pulls the camera toward the assisted target while firing.
func _assist_magnetism(delta: float) -> void:
	if target.weapons.is_melee() or not target.attack_held:
		return
	var t: Actor = target.weapons.assist_target
	var strength: float = target.weapons.assist_strength
	if t == null or not is_instance_valid(t) or strength <= 0.0:
		return
	var to := t.chest_position() - camera.global_position
	var want_yaw := atan2(-to.x, -to.z)
	var want_pitch := atan2(to.y, Vector2(to.x, to.z).length())
	var k := clampf(delta * 3.0 * strength, 0.0, 0.2)
	yaw += wrapf(want_yaw - yaw, -PI, PI) * k
	pitch = clampf(pitch + (want_pitch - pitch) * k * 0.6, PITCH_MIN, PITCH_MAX)
