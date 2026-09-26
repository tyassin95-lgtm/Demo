class_name SpineTwistModifier
extends SkeletonModifier3D
## Distributes a yaw twist (and optional pitch) across the spine after animation is
## applied, letting the upper body aim independently from the legs.
## The mannequin's skeleton space is Y-up with X as the lateral axis.

## Radians around the character's up axis (positive = twist left).
var yaw := 0.0
## Radians around the character's lateral axis.
var pitch := 0.0

var _bones: PackedInt32Array = []
var _weights := PackedFloat32Array([0.25, 0.35, 0.4])


func _process_modification() -> void:
	var sk := get_skeleton()
	if sk == null:
		return
	if _bones.is_empty():
		for b in ["spine_01", "spine_02", "spine_03"]:
			_bones.append(sk.find_bone(b))
	if absf(yaw) < 0.0005 and absf(pitch) < 0.0005:
		return
	for i in _bones.size():
		var idx := _bones[i]
		if idx < 0:
			continue
		var w := _weights[i]
		var rot_sk := Quaternion(Vector3.UP, yaw * w)
		if absf(pitch) > 0.0005:
			rot_sk = rot_sk * Quaternion(Vector3.RIGHT, pitch * w)
		var parent := sk.get_bone_parent(idx)
		var pq := sk.get_bone_global_pose(parent).basis.get_rotation_quaternion() if parent >= 0 else Quaternion.IDENTITY
		var local := sk.get_bone_pose_rotation(idx)
		sk.set_bone_pose_rotation(idx, (pq.inverse() * rot_sk * pq) * local)
