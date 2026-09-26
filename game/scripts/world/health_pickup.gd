class_name HealthPickup
extends Area3D
## Floating repair kit that restores health and respawns after a delay.

var amount := 45.0
var respawn_time := 18.0
var _model: Node3D
var _ring: MeshInstance3D
var _active := true
var _timer := 0.0
var _t := 0.0
var _base_y := 0.0


func _ready() -> void:
	collision_layer = Game.LAYER_PICKUP
	collision_mask = Game.LAYER_PLAYER
	monitorable = false
	var cs := CollisionShape3D.new()
	var sph := SphereShape3D.new()
	sph.radius = 1.0
	cs.shape = sph
	cs.position = Vector3(0, 0.8, 0)
	add_child(cs)
	_model = Node3D.new()
	add_child(_model)
	var kit: Node3D = load("res://assets/props/Prop_HealthPack.gltf").instantiate()
	kit.scale = Vector3.ONE * 1.6
	_model.add_child(kit)
	_model.position.y = 0.9
	_base_y = 0.9
	_ring = MeshInstance3D.new()
	var pm := PlaneMesh.new()
	pm.size = Vector2(2.0, 2.0)
	_ring.mesh = pm
	var m := StandardMaterial3D.new()
	m.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	m.blend_mode = BaseMaterial3D.BLEND_MODE_ADD
	m.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	m.albedo_texture = load("res://assets/vfx/light_03.png")
	m.albedo_color = Color(0.4, 1.6, 0.7)
	_ring.material_override = m
	_ring.position.y = 0.06
	_ring.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	add_child(_ring)
	body_entered.connect(_on_body_entered)


func _process(delta: float) -> void:
	_t += delta
	if not _active:
		_timer -= delta
		if _timer <= 0.0:
			_active = true
			_model.visible = true
			_ring.visible = true
			VFX.spawn_pillar(global_position, Color(0.3, 1.0, 0.5), 3.0, 0.6)
			for b in get_overlapping_bodies():
				_on_body_entered(b)
		return
	_model.rotation.y += delta * 1.6
	_model.position.y = _base_y + sin(_t * 2.4) * 0.15
	_ring.scale = Vector3.ONE * (0.9 + 0.1 * sin(_t * 4.0))


func _on_body_entered(body: Node) -> void:
	if not _active or not (body is Player):
		return
	var p := body as Player
	if not p.is_alive() or p.health >= p.max_health - 0.5:
		return
	p.heal(amount)
	_active = false
	_timer = respawn_time
	_model.visible = false
	_ring.visible = false
	Audio.play("pickup", 0.0)
	VFX.burst(global_position + Vector3.UP, Color(0.3, 1.0, 0.5), 20, 8.0)
	VFX.shockwave(global_position + Vector3.UP * 0.1, 1.5, Color(0.3, 1.0, 0.5))
