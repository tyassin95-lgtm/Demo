class_name BroadcastDrone
extends Node3D
## Ambient "broadcast camera" drone that orbits the arena and watches the action.

var radius := 30.0
var height := 10.0
var speed := 0.12
var phase := 0.0
var _model: Node3D
var _t := 0.0


func _ready() -> void:
	_model = load("res://assets/props/Enemy_EyeDrone.gltf").instantiate()
	_model.scale = Vector3.ONE * 1.6
	add_child(_model)
	var ap: AnimationPlayer = _model.find_child("AnimationPlayer", true, false)
	if ap:
		var anim_name := "Look" if ap.has_animation("Look") else ap.get_animation_list()[0]
		ap.get_animation(anim_name).loop_mode = Animation.LOOP_LINEAR
		ap.play(anim_name)
		ap.speed_scale = 0.8 + randf() * 0.4
	var em: Texture2D = load("res://assets/props/T_Enemies_Emissive.png")
	for mi: MeshInstance3D in _model.find_children("*", "MeshInstance3D", true, false):
		mi.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
		for i in mi.mesh.get_surface_count():
			var src := mi.get_active_material(i)
			if src is StandardMaterial3D:
				var m := src.duplicate() as StandardMaterial3D
				m.emission_enabled = true
				m.emission_texture = em
				m.emission = Color(1.0, 0.45, 0.2)
				m.emission_energy_multiplier = 3.0
				m.emission_operator = BaseMaterial3D.EMISSION_OP_MULTIPLY
				mi.set_surface_override_material(i, m)


func _process(delta: float) -> void:
	_t += delta
	var a := phase + _t * speed
	position = Vector3(cos(a) * radius, height + sin(_t * 0.7 + phase) * 1.2, sin(a) * radius)
	var look_at_pos := Vector3.ZERO
	if Game.player and is_instance_valid(Game.player):
		look_at_pos = Game.player.global_position + Vector3.UP
	var dir := (look_at_pos - global_position).normalized()
	if dir.length() > 0.01:
		var target_basis := Basis.looking_at(-dir, Vector3.UP)
		global_basis = global_basis.slerp(target_basis, clampf(delta * 2.0, 0.0, 1.0)).orthonormalized()
