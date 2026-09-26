class_name Projectile
extends Node3D
## Ray-stepped projectile: glowing energy bolts (dodgeable enemy fire) and bouncing
## grenades that explode on contact with a hostile or when the fuse runs out.

enum Kind { BOLT, GRENADE }

const GRENADE_GRAVITY := 24.0
const EXPLOSION_RADIUS := 4.8

var kind: Kind = Kind.BOLT
var shooter: Node = null
var team := 0
var velocity := Vector3.ZERO
var damage := 10.0
var impact := 10.0
var color := Color(1.0, 0.4, 0.2)
var mask := 1
var max_life := 2.0

var _life := 0.0
var _bounces := 0
var _mesh: MeshInstance3D
var _mat: StandardMaterial3D
var _passed: Array = []


func _ready() -> void:
	_mesh = MeshInstance3D.new()
	_mat = StandardMaterial3D.new()
	_mat.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	_mat.albedo_color = Color(color.r * 2.2, color.g * 2.2, color.b * 2.2)
	_mat.blend_mode = BaseMaterial3D.BLEND_MODE_ADD
	_mat.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	_mat.cull_mode = BaseMaterial3D.CULL_DISABLED
	if kind == Kind.BOLT:
		var cap := CapsuleMesh.new()
		cap.radius = 0.07
		cap.height = 0.9
		cap.radial_segments = 8
		cap.rings = 2
		_mesh.mesh = cap
		_mesh.rotation_degrees.x = 90.0
		var core := MeshInstance3D.new()
		var cap2 := CapsuleMesh.new()
		cap2.radius = 0.03
		cap2.height = 0.7
		cap2.radial_segments = 6
		cap2.rings = 2
		core.mesh = cap2
		var cm := StandardMaterial3D.new()
		cm.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
		cm.albedo_color = Color(2.5, 2.4, 2.2)
		core.material_override = cm
		_mesh.add_child(core)
	else:
		var sph := SphereMesh.new()
		sph.radius = 0.13
		sph.height = 0.26
		sph.radial_segments = 12
		sph.rings = 6
		_mesh.mesh = sph
	_mesh.material_override = _mat
	_mesh.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	add_child(_mesh)


func _physics_process(delta: float) -> void:
	_life += delta
	if kind == Kind.GRENADE:
		velocity.y -= GRENADE_GRAVITY * delta
		var pulse := 1.0 + 1.5 * absf(sin(_life * (8.0 + _life * 14.0)))
		_mat.albedo_color = Color(color.r * pulse, color.g * pulse, color.b * pulse)
	var from := global_position
	var to := from + velocity * delta
	var space := get_world_3d().direct_space_state
	var q := PhysicsRayQueryParameters3D.create(from, to, mask)
	var ex: Array[RID] = []
	if shooter is CollisionObject3D and is_instance_valid(shooter):
		ex.append((shooter as CollisionObject3D).get_rid())
	for p in _passed:
		if is_instance_valid(p):
			ex.append(p.get_rid())
	q.exclude = ex
	var res := space.intersect_ray(q)
	if not res.is_empty():
		var col: Object = res.collider
		if col is Actor and (col as Actor).team != team:
			if kind == Kind.GRENADE:
				global_position = res.position
				_explode()
				return
			var target := col as Actor
			var hit := HitInfo.new()
			hit.source = shooter
			hit.damage = damage
			hit.impact = impact
			hit.reaction = HitInfo.Reaction.NONE
			hit.direction = velocity.normalized()
			hit.position = res.position
			hit.color = color
			if target.take_hit(hit):
				VFX.hit_spark(res.position, -velocity.normalized(), color, 0.7)
				Audio.play_at("body_hit", res.position, -2.0)
				queue_free()
				return
			# Dodged (i-frames): let the bolt fly through.
			_passed.append(target)
			global_position = to
		else:
			if kind == Kind.GRENADE and _bounces < 3:
				_bounces += 1
				var n: Vector3 = res.normal
				velocity = velocity.bounce(n) * 0.45
				global_position = res.position + n * 0.06
				Audio.play_at("impact_world", global_position, -10.0, 1.4)
			else:
				VFX.impact(res.position, res.normal, color, 0.9)
				Audio.play_at("impact_world", res.position, -8.0)
				queue_free()
				return
	else:
		global_position = to
	if kind == Kind.BOLT and velocity.length_squared() > 0.01:
		look_at(global_position + velocity, Vector3.UP if absf(velocity.normalized().y) < 0.98 else Vector3.RIGHT)
	if _life >= max_life:
		if kind == Kind.GRENADE:
			_explode()
		else:
			queue_free()


func _explode() -> void:
	var pos := global_position
	VFX.explosion(pos, EXPLOSION_RADIUS, color, true)
	Audio.play_at("explosion", pos, 3.0)
	Audio.play_at("explosion_low", pos, 0.0)
	if Game.player and is_instance_valid(Game.player):
		var d: float = Game.player.global_position.distance_to(pos)
		Game.shake(clampf(0.7 - d * 0.03, 0.1, 0.6))
	var space := get_world_3d().direct_space_state
	for a in Game.hostiles_of(team):
		var target := a as Actor
		var to := target.chest_position() - pos
		var d := to.length()
		if d > EXPLOSION_RADIUS:
			continue
		var q := PhysicsRayQueryParameters3D.create(pos + Vector3.UP * 0.2, target.chest_position(), Game.LAYER_WORLD)
		if not space.intersect_ray(q).is_empty():
			continue
		var hit := HitInfo.new()
		hit.source = shooter
		hit.damage = damage * clampf(1.2 - d / EXPLOSION_RADIUS, 0.45, 1.0)
		hit.reaction = HitInfo.Reaction.KNOCKDOWN
		hit.knockback = 9.0
		hit.lift = 7.0
		hit.impact = 60.0
		hit.hitstop = 0.06
		var flat := Vector3(to.x, 0.0, to.z)
		hit.direction = flat.normalized() if flat.length() > 0.1 else Vector3.FORWARD
		hit.position = target.chest_position()
		hit.color = color
		hit.is_explosion = true
		var was_alive := target.is_alive()
		if target.take_hit(hit):
			VFX.damage_number(hit.position + Vector3.UP * 0.4, hit.damage, color, true)
			if shooter is Actor and is_instance_valid(shooter):
				(shooter as Actor).weapons.hit_landed.emit(target, hit, was_alive and not target.is_alive())
	queue_free()
