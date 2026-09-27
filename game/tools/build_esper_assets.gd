extends SceneTree
# Build step: turns the Universal Base Characters glTFs into lightweight game assets.
# - Bodies: skeleton + skinned body, eyes and eyebrows (materials stripped; the game
#   assigns its own outfit materials at runtime).
# - Hair: static meshes moved into Head-bone space, attached at runtime with a
#   BoneAttachment3D (cheaper than skinning them).
# Run: godot --headless --path . --script res://tools/build_esper_assets.gd

const DIR := "res://assets/characters/esper/"
const BODIES := {"m": "Superhero_Male_FullBody", "f": "Superhero_Female_FullBody"}
const HAIRS := ["Hair_Long", "Hair_Buns", "Hair_SimpleParted", "Hair_BuzzedFemale", "Hair_Buzzed"]


func _initialize() -> void:
	for g in BODIES:
		_save_body(DIR + "src/" + BODIES[g] + ".gltf", DIR + "esper_%s.scn" % g)
	for h in HAIRS:
		_save_hair(DIR + "hair/" + h + ".gltf", DIR + "hair/" + h.to_snake_case() + ".res")
	quit()


func _save_body(path: String, out: String) -> void:
	var inst: Node3D = load(path).instantiate()
	for n in inst.find_children("*", "AnimationPlayer", true, false):
		n.get_parent().remove_child(n)
		n.free()
	var biggest: MeshInstance3D = null
	for mi: MeshInstance3D in inst.find_children("*", "MeshInstance3D", true, false):
		mi.mesh = mi.mesh.duplicate(true)
		for i in mi.mesh.get_surface_count():
			mi.mesh.surface_set_material(i, null)
		if mi.skin:
			mi.skin = mi.skin.duplicate(true)
		if mi.name.to_lower().contains("eyes"):
			mi.name = "Eyes"
		elif mi.name.to_lower().contains("eyebrow") or mi.name == "Face":
			mi.name = "Brows"
		if biggest == null or _vertex_count(mi.mesh) > _vertex_count(biggest.mesh):
			biggest = mi
	biggest.name = "Body"
	_set_owner(inst, inst)
	var ps := PackedScene.new()
	ps.pack(inst)
	var err := ResourceSaver.save(ps, out, ResourceSaver.FLAG_COMPRESS)
	print("saved body ", out, " err=", err)
	inst.print_tree_pretty()
	inst.free()


func _save_hair(path: String, out: String) -> void:
	var inst: Node3D = load(path).instantiate()
	var mi: MeshInstance3D = inst.find_children("*", "MeshInstance3D", true, false)[0]
	var arrays: Array = mi.mesh.surface_get_arrays(0)
	var bones: PackedInt32Array = arrays[Mesh.ARRAY_BONES]
	var weights: PackedFloat32Array = arrays[Mesh.ARRAY_WEIGHTS]
	var verts: PackedVector3Array = arrays[Mesh.ARRAY_VERTEX]
	var per := bones.size() / verts.size()
	# The hair is rigged to a single bone (Head): find it from the heaviest influence.
	var bind := bones[0]
	var best := 0.0
	for k in per:
		if weights[k] > best:
			best = weights[k]
			bind = bones[k]
	var name := mi.skin.get_bind_name(bind)
	var xf := mi.skin.get_bind_pose(bind)
	for i in verts.size():
		verts[i] = xf * verts[i]
	arrays[Mesh.ARRAY_VERTEX] = verts
	var normals: PackedVector3Array = arrays[Mesh.ARRAY_NORMAL]
	for i in normals.size():
		normals[i] = (xf.basis * normals[i]).normalized()
	arrays[Mesh.ARRAY_NORMAL] = normals
	if arrays[Mesh.ARRAY_TANGENT] != null:
		var tan: PackedFloat32Array = arrays[Mesh.ARRAY_TANGENT]
		for i in tan.size() / 4:
			var t := (xf.basis * Vector3(tan[i * 4], tan[i * 4 + 1], tan[i * 4 + 2])).normalized()
			tan[i * 4] = t.x
			tan[i * 4 + 1] = t.y
			tan[i * 4 + 2] = t.z
		arrays[Mesh.ARRAY_TANGENT] = tan
	arrays[Mesh.ARRAY_BONES] = null
	arrays[Mesh.ARRAY_WEIGHTS] = null
	var am := ArrayMesh.new()
	am.add_surface_from_arrays(Mesh.PRIMITIVE_TRIANGLES, arrays)
	var err := ResourceSaver.save(am, out, ResourceSaver.FLAG_COMPRESS)
	print("saved hair ", out, " bone=", name, " (", bind, ") verts=", verts.size(), " aabb=", am.get_aabb(), " err=", err)
	inst.free()


func _vertex_count(m: Mesh) -> int:
	var n := 0
	for i in m.get_surface_count():
		n += (m.surface_get_arrays(i)[Mesh.ARRAY_VERTEX] as PackedVector3Array).size()
	return n


func _set_owner(n: Node, owner_node: Node) -> void:
	for c in n.get_children():
		c.owner = owner_node
		_set_owner(c, owner_node)
