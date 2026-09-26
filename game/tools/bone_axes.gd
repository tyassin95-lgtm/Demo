extends SceneTree
func _initialize() -> void:
	var s: Node3D = load("res://assets/characters/mannequin_m.scn").instantiate()
	var sk: Skeleton3D = s.get_node("Armature/Skeleton3D")
	for b in ["hand_r", "hand_l", "lowerarm_r", "index_01_r", "pinky_01_r", "thumb_01_r", "Head", "spine_03"]:
		var i := sk.find_bone(b)
		var g := sk.get_bone_global_rest(i)
		print(b, " origin=", g.origin, " X=", g.basis.x.normalized(), " Y=", g.basis.y.normalized(), " Z=", g.basis.z.normalized())
	quit()
