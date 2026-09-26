class_name TrailRibbon
extends MeshInstance3D
## Samples two moving points (blade base and tip) and builds a smooth fading ribbon.

const SUBDIV := 3

var base_node: Node3D
var tip_node: Node3D
var emitting := false
var point_life := 0.16
var max_samples := 20

var _samples: Array = []
var _im := ImmediateMesh.new()
var _time := 0.0


func _ready() -> void:
	top_level = true
	global_transform = Transform3D.IDENTITY
	mesh = _im
	cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	extra_cull_margin = 16384.0


func _process(delta: float) -> void:
	_time += delta
	if emitting and base_node and tip_node and base_node.is_inside_tree():
		_samples.push_front([base_node.global_position, tip_node.global_position, _time])
		if _samples.size() > max_samples:
			_samples.pop_back()
	while not _samples.is_empty() and _time - float(_samples.back()[2]) > point_life:
		_samples.pop_back()
	_rebuild()


func clear() -> void:
	_samples.clear()
	_im.clear_surfaces()


func _rebuild() -> void:
	_im.clear_surfaces()
	var n := _samples.size()
	if n < 2:
		return
	_im.surface_begin(Mesh.PRIMITIVE_TRIANGLE_STRIP)
	for i in n - 1:
		var p0: Array = _samples[maxi(i - 1, 0)]
		var p1: Array = _samples[i]
		var p2: Array = _samples[i + 1]
		var p3: Array = _samples[mini(i + 2, n - 1)]
		var steps := SUBDIV if i < n - 2 else SUBDIV + 1
		for s in steps:
			var t := float(s) / float(SUBDIV)
			var b := _catmull(p0[0], p1[0], p2[0], p3[0], t)
			var tip := _catmull(p0[1], p1[1], p2[1], p3[1], t)
			var age := clampf((_time - lerpf(p1[2], p2[2], t)) / point_life, 0.0, 1.0)
			_im.surface_set_color(Color(1, 1, 1, 1))
			_im.surface_set_uv(Vector2(age, 0.0))
			_im.surface_add_vertex(b)
			_im.surface_set_color(Color(1, 1, 1, 1))
			_im.surface_set_uv(Vector2(age, 1.0))
			_im.surface_add_vertex(tip)
	_im.surface_end()


static func _catmull(p0: Vector3, p1: Vector3, p2: Vector3, p3: Vector3, t: float) -> Vector3:
	var t2 := t * t
	var t3 := t2 * t
	return 0.5 * ((2.0 * p1) + (-p0 + p2) * t + (2.0 * p0 - 5.0 * p1 + 4.0 * p2 - p3) * t2 + (-p0 + 3.0 * p1 - 3.0 * p2 + p3) * t3)
