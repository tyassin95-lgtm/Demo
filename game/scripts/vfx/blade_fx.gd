class_name BladeFX
extends Node3D
## Procedural energy blade: metal hilt + glowing blade + swing trail.
## The blade extends along local +Y from the hilt.

const BLADE_SHADER := preload("res://shaders/blade.gdshader")
const TRAIL_SHADER := preload("res://shaders/trail.gdshader")

var color := Color(0.25, 0.95, 1.0)
var length := 1.0
var trail: TrailRibbon
var base_marker: Marker3D
var tip_marker: Marker3D
var _blade_root: Node3D
var _blade_mat: ShaderMaterial
var _power := 1.0
var _target_power := 1.0


func build(c: Color, blade_length: float = 1.0) -> void:
	color = c
	length = blade_length
	var metal := StandardMaterial3D.new()
	metal.albedo_color = Color(0.12, 0.13, 0.16)
	metal.metallic = 0.9
	metal.roughness = 0.3
	var accent := StandardMaterial3D.new()
	accent.albedo_color = Color(0.05, 0.05, 0.06)
	accent.emission_enabled = true
	accent.emission = color
	accent.emission_energy_multiplier = 3.0

	var hilt := MeshInstance3D.new()
	var cyl := CylinderMesh.new()
	cyl.top_radius = 0.021
	cyl.bottom_radius = 0.024
	cyl.height = 0.24
	cyl.radial_segments = 10
	cyl.rings = 1
	hilt.mesh = cyl
	hilt.material_override = metal
	hilt.position = Vector3(0, 0.0, 0)
	add_child(hilt)
	var ring := MeshInstance3D.new()
	var ring_mesh := CylinderMesh.new()
	ring_mesh.top_radius = 0.027
	ring_mesh.bottom_radius = 0.027
	ring_mesh.height = 0.03
	ring_mesh.radial_segments = 10
	ring_mesh.rings = 1
	ring.mesh = ring_mesh
	ring.material_override = accent
	ring.position = Vector3(0, 0.06, 0)
	add_child(ring)
	var guard := MeshInstance3D.new()
	var box := BoxMesh.new()
	box.size = Vector3(0.1, 0.035, 0.05)
	guard.mesh = box
	guard.material_override = metal
	guard.position = Vector3(0, 0.13, 0)
	add_child(guard)

	_blade_root = Node3D.new()
	_blade_root.position = Vector3(0, 0.14, 0)
	add_child(_blade_root)
	_blade_mat = ShaderMaterial.new()
	_blade_mat.shader = BLADE_SHADER
	_blade_mat.set_shader_parameter("color", Vector3(color.r, color.g, color.b))
	var core := MeshInstance3D.new()
	var cap := CapsuleMesh.new()
	cap.radius = 0.03
	cap.height = length
	cap.radial_segments = 10
	cap.rings = 3
	core.mesh = cap
	core.scale = Vector3(1.0, 1.0, 0.45)
	core.position = Vector3(0, length * 0.5, 0)
	core.material_override = _blade_mat
	core.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	_blade_root.add_child(core)
	var glow := MeshInstance3D.new()
	var cap2 := CapsuleMesh.new()
	cap2.radius = 0.06
	cap2.height = length + 0.06
	cap2.radial_segments = 10
	cap2.rings = 3
	glow.mesh = cap2
	glow.scale = Vector3(1.0, 1.0, 0.5)
	glow.position = Vector3(0, length * 0.5, 0)
	var glow_mat := _blade_mat.duplicate() as ShaderMaterial
	glow_mat.set_shader_parameter("intensity", 0.9)
	glow_mat.set_shader_parameter("core_width", 0.0)
	glow.material_override = glow_mat
	glow.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	_blade_root.add_child(glow)

	base_marker = Marker3D.new()
	base_marker.position = Vector3(0, 0.2, 0)
	_blade_root.add_child(base_marker)
	tip_marker = Marker3D.new()
	tip_marker.position = Vector3(0, length + 0.05, 0)
	_blade_root.add_child(tip_marker)

	trail = TrailRibbon.new()
	var tm := ShaderMaterial.new()
	tm.shader = TRAIL_SHADER
	tm.set_shader_parameter("color", Vector3(color.r, color.g, color.b))
	trail.material_override = tm
	trail.base_node = base_marker
	trail.tip_node = tip_marker
	add_child(trail)


func set_trail(on: bool) -> void:
	if trail:
		trail.emitting = on


## Ignites/retracts the blade (used on weapon switch).
func ignite(on: bool) -> void:
	_target_power = 1.0 if on else 0.0
	if on:
		_power = 0.0


func _process(delta: float) -> void:
	_power = move_toward(_power, _target_power, delta * 6.0)
	if _blade_root:
		_blade_root.scale = Vector3(1.0, maxf(_power, 0.001), 1.0)
		_blade_root.visible = _power > 0.01
