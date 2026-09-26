class_name CharacterVisual
extends Node3D
## Visual representation of an actor: styled mannequin, layered animation, weapon
## models, hit flash / dissolve effects, procedural lean and dash afterimages.

const ANIM_LIB := preload("res://assets/characters/mannequin_anims.res")
const CHAR_SHADER := preload("res://shaders/character.gdshader")
const GHOST_SHADER := preload("res://shaders/ghost.gdshader")
const SKELETON_PATH := "Armature/Skeleton3D"

## Grip setup, in right-hand bone space. The mannequin's hand bone has +Y along the
## fingers, +Z from pinky to index (knuckle line) and +X on the back of the hand.
const FIST_CENTER := Vector3(-0.035, 0.085, 0.0)
const BLADE_ROT := Vector3(90, 0, 0)
## Maps gun model axes (barrel -X, up +Y) to hand axes (barrel +Y, up +Z).
const GUN_ROT := Vector3(0, -90, -90)
## Handle position of each gun model (model space, unscaled).
const GUN_GRIP_POINT := {
	"res://assets/weapons/Gun_Rifle.gltf": Vector3(0.03, -0.03, 0.0),
	"res://assets/weapons/Gun_Revolver.gltf": Vector3(0.01, -0.01, 0.0),
	"res://assets/weapons/Gun_Sniper.gltf": Vector3(0.05, -0.04, 0.0),
	"res://assets/weapons/Gun_Pistol.gltf": Vector3(0.05, -0.03, 0.0),
}
const GUN_EMISSIVE := {
	"res://assets/weapons/Gun_Rifle.gltf": "res://assets/weapons/T_Guns_Batch1_Emissive.png",
	"res://assets/weapons/Gun_Pistol.gltf": "res://assets/weapons/T_Guns_Batch1_Emissive.png",
	"res://assets/weapons/Gun_Revolver.gltf": "res://assets/weapons/T_Guns_Batch2_Emissive.png",
	"res://assets/weapons/Gun_Sniper.gltf": "res://assets/weapons/T_Guns_Batch2_Emissive.png",
}

var model: Node3D
var skeleton: Skeleton3D
var mesh: MeshInstance3D
var anim := AnimController.new()
var twist: SpineTwistModifier
var hand_r: BoneAttachment3D
var head: BoneAttachment3D
var chest: BoneAttachment3D
var blade: BladeFX
var guns := {}
var current_gun: Node3D
var muzzle: Marker3D
var body_mat: ShaderMaterial
var joint_mat: ShaderMaterial
var style := {}

var _flash := 0.0
var _dissolve := 0.0
var _dissolve_target := 0.0
var _dissolve_speed := 1.0
var _lean := Vector2.ZERO
var _lean_target := Vector2.ZERO
var _gun_kick := 0.0
var _overdrive := 0.0


func build(model_path: String, p_style: Dictionary) -> void:
	style = p_style
	model = load(model_path).instantiate()
	add_child(model)
	model.rotation.y = PI
	skeleton = model.get_node(SKELETON_PATH)
	for c in skeleton.get_children():
		if c is MeshInstance3D:
			mesh = c
	anim.setup(model, ANIM_LIB, SKELETON_PATH)
	twist = SpineTwistModifier.new()
	skeleton.add_child(twist)
	hand_r = BoneAttachment3D.new()
	hand_r.bone_name = "hand_r"
	skeleton.add_child(hand_r)
	head = BoneAttachment3D.new()
	head.bone_name = "Head"
	skeleton.add_child(head)
	chest = BoneAttachment3D.new()
	chest.bone_name = "spine_03"
	skeleton.add_child(chest)
	_apply_materials()
	_build_accessories()


func _make_char_mat(params: Dictionary) -> ShaderMaterial:
	var m := ShaderMaterial.new()
	m.shader = CHAR_SHADER
	for k in params:
		var v: Variant = params[k]
		if v is Color:
			v = Vector3(v.r, v.g, v.b)
		m.set_shader_parameter(k, v)
	return m


func _apply_materials() -> void:
	var base: Color = style.get("base", Color(0.85, 0.87, 0.9))
	var rim: Color = style.get("rim", Color(0.2, 0.9, 1.0))
	var glow: Color = style.get("glow", Color(0.2, 0.9, 1.0))
	body_mat = _make_char_mat({
		"base_color": base, "metallic": style.get("metallic", 0.35), "roughness": style.get("roughness", 0.32),
		"rim_color": rim, "rim_strength": style.get("rim_strength", 0.9), "rim_power": 3.0,
		"stripe_strength": style.get("stripe", 0.0), "stripe_color": glow, "dissolve_color": glow,
	})
	joint_mat = _make_char_mat({
		"base_color": Color(0.05, 0.05, 0.06), "metallic": 0.2, "roughness": 0.4,
		"emission_color": glow, "emission_strength": style.get("glow_strength", 2.6),
		"rim_color": glow, "rim_strength": 0.4, "dissolve_color": glow,
	})
	if mesh:
		var n := mesh.mesh.get_surface_count()
		for i in n:
			var src := mesh.mesh.surface_get_material(i)
			var is_joint := src != null and String(src.resource_name).to_lower().contains("joint")
			mesh.set_surface_override_material(i, joint_mat if is_joint else body_mat)
		mesh.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_ON


func _build_accessories() -> void:
	var glow: Color = style.get("glow", Color(0.2, 0.9, 1.0))
	var visor_color: Color = style.get("visor", glow)
	# Visor band across the "face".
	var visor := MeshInstance3D.new()
	var vb := BoxMesh.new()
	vb.size = Vector3(0.17, 0.045, 0.06)
	visor.mesh = vb
	var vm := StandardMaterial3D.new()
	vm.albedo_color = Color(0.02, 0.02, 0.03)
	vm.emission_enabled = true
	vm.emission = visor_color
	vm.emission_energy_multiplier = 3.5
	vm.metallic = 0.8
	vm.roughness = 0.15
	visor.material_override = vm
	visor.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	head.add_child(visor)
	visor.position = Vector3(0.0, 0.1, 0.085)
	# Compact thruster pack on the upper back.
	if style.get("backpack", true):
		var pack := MeshInstance3D.new()
		var pb := BoxMesh.new()
		pb.size = Vector3(0.24, 0.26, 0.09)
		pack.mesh = pb
		var pm := StandardMaterial3D.new()
		pm.albedo_color = style.get("pack_color", Color(0.14, 0.15, 0.18))
		pm.metallic = 0.7
		pm.roughness = 0.35
		pack.material_override = pm
		chest.add_child(pack)
		pack.position = Vector3(0.0, 0.02, -0.14)
		for side in [-1.0, 1.0]:
			var noz := MeshInstance3D.new()
			var nc := CylinderMesh.new()
			nc.top_radius = 0.035
			nc.bottom_radius = 0.045
			nc.height = 0.09
			nc.radial_segments = 8
			nc.rings = 1
			noz.mesh = nc
			var nm := StandardMaterial3D.new()
			nm.albedo_color = Color(0.05, 0.05, 0.06)
			nm.emission_enabled = true
			nm.emission = glow
			nm.emission_energy_multiplier = 2.5
			noz.material_override = nm
			pack.add_child(noz)
			noz.position = Vector3(side * 0.08, -0.15, 0.0)


# --- Weapons ------------------------------------------------------------

func show_weapon(w: WeaponDB.Weapon) -> void:
	if w == null:
		return
	if w.kind == WeaponDB.Kind.MELEE:
		if blade == null:
			blade = BladeFX.new()
			blade.build(w.color, 1.0)
			hand_r.add_child(blade)
			blade.position = FIST_CENTER
			blade.rotation_degrees = BLADE_ROT
		blade.visible = true
		blade.ignite(true)
		for g in guns.values():
			g.visible = false
		current_gun = null
		muzzle = null
	else:
		if blade:
			blade.visible = false
			blade.set_trail(false)
		for g in guns.values():
			g.visible = false
		if not guns.has(w.id):
			guns[w.id] = _make_gun(w)
		current_gun = guns[w.id]
		current_gun.visible = true
		muzzle = current_gun.get_node("Model/Muzzle")


func _make_gun(w: WeaponDB.Weapon) -> Node3D:
	var holder := Node3D.new()
	hand_r.add_child(holder)
	holder.position = FIST_CENTER
	holder.rotation_degrees = GUN_ROT
	var gun: Node3D = load(w.model).instantiate()
	gun.name = "Model"
	holder.add_child(gun)
	gun.scale = Vector3.ONE * w.model_scale
	var grip: Vector3 = GUN_GRIP_POINT.get(w.model, Vector3.ZERO)
	gun.position = -grip * w.model_scale
	holder.set_meta("base_pos", gun.position)
	# Model forward is -X in the source files: compute muzzle from the mesh bounds.
	var aabb := AABB()
	var first := true
	for mi: MeshInstance3D in gun.find_children("*", "MeshInstance3D", true, false):
		mi.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
		var a: AABB = _xform_to(mi, gun) * mi.get_aabb()
		aabb = a if first else aabb.merge(a)
		first = false
		_tint_gun_material(mi, w)
	var muzzle_marker := Marker3D.new()
	muzzle_marker.name = "Muzzle"
	muzzle_marker.position = Vector3(aabb.position.x, aabb.position.y + aabb.size.y * 0.72, aabb.position.z + aabb.size.z * 0.5)
	gun.add_child(muzzle_marker)
	return holder


static func _xform_to(n: Node3D, ancestor: Node3D) -> Transform3D:
	var t := Transform3D.IDENTITY
	var cur: Node = n
	while cur != null and cur != ancestor:
		if cur is Node3D:
			t = (cur as Node3D).transform * t
		cur = cur.get_parent()
	return t


func _tint_gun_material(mi: MeshInstance3D, w: WeaponDB.Weapon) -> void:
	var emissive_path: String = GUN_EMISSIVE.get(w.model, "")
	for i in mi.mesh.get_surface_count():
		var src := mi.get_active_material(i)
		if src is StandardMaterial3D:
			var m := src.duplicate() as StandardMaterial3D
			m.emission_enabled = true
			m.emission = w.color
			m.emission_energy_multiplier = 2.5
			if emissive_path != "":
				m.emission_texture = load(emissive_path)
			m.emission_operator = BaseMaterial3D.EMISSION_OP_MULTIPLY
			mi.set_surface_override_material(i, m)


func muzzle_position() -> Vector3:
	if muzzle and muzzle.is_inside_tree():
		return muzzle.global_position
	return global_position + Vector3(0, 1.4, 0)


func gun_kick(amount: float) -> void:
	_gun_kick = minf(_gun_kick + amount, 1.5)


# --- Effects --------------------------------------------------------------

func flash(amount: float = 1.0) -> void:
	_flash = maxf(_flash, amount)


func set_overdrive(v: float) -> void:
	_overdrive = v


func dissolve_out(duration: float = 1.0) -> void:
	_dissolve = maxf(_dissolve, 0.001)
	_dissolve_target = 1.0
	_dissolve_speed = 1.0 / maxf(duration, 0.01)


func dissolve_in(duration: float = 0.8) -> void:
	_dissolve = 1.0
	_dissolve_target = 0.0
	_dissolve_speed = 1.0 / maxf(duration, 0.01)


## Screen-door fade used when the camera is very close to this character.
func set_fade(v: float) -> void:
	if body_mat:
		body_mat.set_shader_parameter("dither_fade", v)
		joint_mat.set_shader_parameter("dither_fade", v)
	for n in [head, chest]:
		if n:
			n.visible = v < 0.6


func set_lean(roll: float, pitch: float) -> void:
	_lean_target = Vector2(roll, pitch)


## Spawns a translucent snapshot of the current pose (dash afterimage).
func spawn_afterimage(color: Color, life: float = 0.35) -> void:
	if mesh == null or not is_inside_tree() or DisplayServer.get_name() == "headless":
		return
	var baked := mesh.bake_mesh_from_current_skeleton_pose()
	if baked == null:
		return
	var ghost := MeshInstance3D.new()
	ghost.mesh = baked
	var m := ShaderMaterial.new()
	m.shader = GHOST_SHADER
	m.set_shader_parameter("color", Vector3(color.r, color.g, color.b))
	ghost.material_override = m
	ghost.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	var root := get_tree().current_scene
	root.add_child(ghost)
	ghost.global_transform = mesh.global_transform
	var tw := ghost.create_tween()
	tw.tween_method(func(a: float) -> void: m.set_shader_parameter("alpha", a), 0.7, 0.0, life)
	tw.tween_callback(ghost.queue_free)


func tick(delta: float) -> void:
	anim.update(delta)
	_flash = move_toward(_flash, 0.0, delta * 6.0)
	if _dissolve != _dissolve_target:
		_dissolve = move_toward(_dissolve, _dissolve_target, delta * _dissolve_speed)
	_lean = _lean.lerp(_lean_target, clampf(delta * 10.0, 0.0, 1.0))
	model.rotation = Vector3(_lean.y, PI, _lean.x)
	_gun_kick = move_toward(_gun_kick, 0.0, delta * 9.0)
	if current_gun:
		var gm := current_gun.get_node("Model") as Node3D
		gm.position = current_gun.get_meta("base_pos") + Vector3(_gun_kick * 0.07, 0.0, 0.0)
	if body_mat:
		body_mat.set_shader_parameter("hit_flash", _flash)
		body_mat.set_shader_parameter("dissolve", _dissolve)
		body_mat.set_shader_parameter("overdrive", _overdrive)
		joint_mat.set_shader_parameter("hit_flash", _flash)
		joint_mat.set_shader_parameter("dissolve", _dissolve)
		joint_mat.set_shader_parameter("overdrive", _overdrive)
