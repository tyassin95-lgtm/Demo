extends SceneTree
func _initialize() -> void:
	var s: Node = load("res://assets/characters/UAL1_Standard.glb").instantiate()
	var sk: Skeleton3D = s.find_child("Skeleton3D", true, false)
	var out := []
	for i in sk.get_bone_count():
		out.append("%d:%s(p%d)" % [i, sk.get_bone_name(i), sk.get_bone_parent(i)])
	print(" ".join(out))
	var mi: MeshInstance3D = s.find_child("Mannequin", true, false)
	print("aabb ", mi.get_aabb(), " surfaces ", mi.mesh.get_surface_count(), " verts ", mi.mesh.surface_get_array_len(0), " ", mi.mesh.surface_get_array_len(1))
	sk.reset_bone_poses()
	for b in ["hand_r", "hand_l", "head", "spine_03", "pelvis", "root"]:
		var idx := sk.find_bone(b)
		if idx >= 0:
			print(b, " global_rest ", sk.get_bone_global_rest(idx).origin)
	quit()
