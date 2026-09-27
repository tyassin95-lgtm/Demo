extends SceneTree
# Build step: extracts the animations used by the game from the Quaternius
# Universal Animation Library GLBs into one AnimationLibrary, and saves
# standalone mannequin scenes (mesh + skeleton, no animations).
# Run: godot --headless --path . --script res://tools/build_character_assets.gd

const UAL1 := "res://assets/characters/UAL1_Standard.glb"
const UAL2 := "res://assets/characters/UAL2_Standard.glb"
const FEMALE := "res://assets/characters/Mannequin_F.glb"

const KEEP_UAL1 := [
	"Idle", "Jog_Fwd", "Sprint", "Walk", "Jump_Start", "Jump", "Jump_Land", "Roll",
	"Sword_Attack", "Sword_Idle", "Pistol_Idle", "Pistol_Aim_Neutral", "Pistol_Aim_Up",
	"Pistol_Aim_Down", "Pistol_Shoot", "Pistol_Reload", "Hit_Chest", "Hit_Head", "Death01",
	"Punch_Jab", "Punch_Cross", "Spell_Simple_Shoot", "Crouch_Idle", "Crouch_Fwd", "Dance",
]
const KEEP_UAL2 := [
	"Sword_Regular_A", "Sword_Regular_B", "Sword_Regular_C", "Sword_Regular_A_Rec",
	"Sword_Regular_B_Rec", "Sword_Dash", "Sword_Heavy_Combo", "Sword_Block", "Slide_Start", "Slide",
	"Slide_Exit", "NinjaJump_Start", "NinjaJump_Idle", "NinjaJump_Land", "Hit_Knockback",
	"LayToIdle", "Shield_Dash", "Melee_Hook", "Melee_Hook_Rec", "OverhandThrow", "ClimbUp_1m",
	"Idle_FoldArms",
]

func _initialize() -> void:
	var lib := AnimationLibrary.new()
	_collect(UAL1, KEEP_UAL1, lib)
	_collect(UAL2, KEEP_UAL2, lib)
	var err := ResourceSaver.save(lib, "res://assets/characters/mannequin_anims.res", ResourceSaver.FLAG_COMPRESS)
	print("saved anim library: ", lib.get_animation_list().size(), " anims, err=", err)
	_save_model(UAL1, "res://assets/characters/mannequin_m.scn")
	_save_model(FEMALE, "res://assets/characters/mannequin_f.scn")
	quit()

func _collect(path: String, keep: Array, lib: AnimationLibrary) -> void:
	var inst: Node = load(path).instantiate()
	var ap: AnimationPlayer = inst.find_child("AnimationPlayer", true, false)
	var src := ap.get_animation_library(&"")
	for n in keep:
		if not src.has_animation(n):
			push_error("missing animation " + n + " in " + path)
			continue
		var a: Animation = src.get_animation(n).duplicate(true)
		lib.add_animation(n, a)
	inst.free()

func _save_model(path: String, out: String) -> void:
	var inst: Node3D = load(path).instantiate()
	var ap := inst.find_child("AnimationPlayer", true, false)
	if ap:
		inst.remove_child(ap)
		ap.free()
	for sim in inst.find_children("*", "PhysicalBoneSimulator3D", true, false):
		sim.get_parent().remove_child(sim)
		sim.free()
	for mi: MeshInstance3D in inst.find_children("*", "MeshInstance3D", true, false):
		mi.mesh = mi.mesh.duplicate(true)
		if mi.skin:
			mi.skin = mi.skin.duplicate(true)
	_set_owner(inst, inst)
	var ps := PackedScene.new()
	ps.pack(inst)
	var err := ResourceSaver.save(ps, out, ResourceSaver.FLAG_COMPRESS)
	print("saved model ", out, " err=", err)
	inst.print_tree_pretty()
	inst.free()

func _set_owner(n: Node, owner_node: Node) -> void:
	for c in n.get_children():
		c.owner = owner_node
		_set_owner(c, owner_node)
