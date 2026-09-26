class_name JumpPad
extends Area3D
## Launch pad: computes a ballistic arc (matching actor gravity with heavier falls)
## that lands on its target, and launches any actor that steps on it.

const GRAVITY := 30.0
const FALL_MULT := 1.3
const APEX_EXTRA := 2.2

var color := Color(0.3, 1.0, 0.7)
var target := Vector3.ZERO
var launch_velocity := Vector3.UP * 15.0
var flight_time := 1.0
var _mat: ShaderMaterial
var _boost := 0.0
var _recent := {}


func _ready() -> void:
	add_to_group("jump_pads")
	collision_layer = Game.LAYER_PICKUP
	collision_mask = Game.LAYER_PLAYER | Game.LAYER_ENEMY
	monitorable = false
	var cs := CollisionShape3D.new()
	var cyl := CylinderShape3D.new()
	cyl.radius = 1.25
	cyl.height = 0.8
	cs.shape = cyl
	cs.position = Vector3(0, 0.4, 0)
	add_child(cs)
	var base := MeshInstance3D.new()
	var bc := CylinderMesh.new()
	bc.top_radius = 1.55
	bc.bottom_radius = 1.7
	bc.height = 0.14
	bc.radial_segments = 24
	bc.rings = 1
	base.mesh = bc
	var bm := StandardMaterial3D.new()
	bm.albedo_color = Color(0.08, 0.09, 0.12)
	bm.metallic = 0.7
	bm.roughness = 0.35
	bm.emission_enabled = true
	bm.emission = color * 0.25
	base.material_override = bm
	base.position.y = 0.05
	add_child(base)
	var disc := MeshInstance3D.new()
	var pm := PlaneMesh.new()
	pm.size = Vector2(2.9, 2.9)
	disc.mesh = pm
	_mat = ShaderMaterial.new()
	_mat.shader = load("res://shaders/jump_pad.gdshader")
	_mat.set_shader_parameter("color", Vector3(color.r, color.g, color.b))
	disc.material_override = _mat
	disc.position.y = 0.13
	disc.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	add_child(disc)
	body_entered.connect(_on_body_entered)


func set_target(t: Vector3) -> void:
	target = t
	var p := global_position
	var apex := maxf(t.y, p.y) + APEX_EXTRA
	var vy := sqrt(2.0 * GRAVITY * (apex - p.y))
	var t_up := vy / GRAVITY
	var t_down := sqrt(2.0 * maxf(apex - t.y, 0.01) / (GRAVITY * FALL_MULT))
	flight_time = t_up + t_down
	var flat := Vector3(t.x - p.x, 0.0, t.z - p.z)
	var hv := flat / flight_time
	launch_velocity = Vector3(hv.x, vy, hv.z)


func _process(delta: float) -> void:
	_boost = move_toward(_boost, 0.0, delta * 3.0)
	_mat.set_shader_parameter("boost", _boost)


func _on_body_entered(body: Node) -> void:
	if not (body is Actor):
		return
	var a := body as Actor
	if not a.is_alive() or a.is_down():
		return
	var now := Time.get_ticks_msec()
	if now - int(_recent.get(a.get_instance_id(), 0)) < 600:
		return
	_recent[a.get_instance_id()] = now
	if a.has_method("launch"):
		a.call("launch", launch_velocity)
	_boost = 1.0
	Audio.play_at("jump_pad", global_position, 0.0 if a is Player else -6.0)
	VFX.shockwave(global_position + Vector3.UP * 0.15, 1.6, color)
	VFX.burst(global_position + Vector3.UP * 0.3, color, 14, 9.0)
