class_name AnimController
extends RefCounted
## Builds and drives a layered AnimationTree for the mannequin rig:
##   base locomotion (Transition, phase-synced move blend space, time scale)
##   -> upper-body aim layer (bone-filtered Blend2)
##   -> full-body action layer (two ping-pong slots, crossfaded by a Transition)
## The tree is advanced manually so each actor can be slowed or frozen (hit-stop).

const BASE_STATES := {
	"idle": "Idle",
	"idle_blade": "Sword_Idle",
	"move": "",
	"jump": "Jump_Start",
	"fall": "Jump",
	"land": "Jump_Land",
	"flip": "NinjaJump_Start",
	"flip_fall": "NinjaJump_Idle",
	"flip_land": "NinjaJump_Land",
	"slide": "Slide_Start",
	"wallrun": "Sprint",
	"dance": "Dance",
}
const RESET_STATES := ["jump", "land", "flip", "flip_land", "slide"]
const UPPER_BONES := [
	"spine_01", "spine_02", "spine_03", "neck_01", "Head",
	"clavicle_l", "upperarm_l", "lowerarm_l", "hand_l",
	"clavicle_r", "upperarm_r", "lowerarm_r", "hand_r",
	"index_01_l", "index_02_l", "index_03_l", "middle_01_l", "middle_02_l", "middle_03_l",
	"pinky_01_l", "pinky_02_l", "pinky_03_l", "ring_01_l", "ring_02_l", "ring_03_l",
	"thumb_01_l", "thumb_02_l", "thumb_03_l",
	"index_01_r", "index_02_r", "index_03_r", "middle_01_r", "middle_02_r", "middle_03_r",
	"pinky_01_r", "pinky_02_r", "pinky_03_r", "ring_01_r", "ring_02_r", "ring_03_r",
	"thumb_01_r", "thumb_02_r", "thumb_03_r",
]

const P_BASE := &"parameters/base/transition_request"
const P_BASE_TS := &"parameters/base_ts/scale"
const P_MOVE := &"parameters/move_bs/blend_position"
const P_AIM := &"parameters/aim_bs/blend_position"
const P_UPPER_T := &"parameters/upper_t/transition_request"
const P_UPPER_W := &"parameters/upper_blend/blend_amount"
const P_ACT_T := &"parameters/act_t/transition_request"
const P_ACT_W := &"parameters/act_blend/blend_amount"
const P_TS := [&"parameters/ts_a/scale", &"parameters/ts_b/scale"]
const P_SEEK := [&"parameters/seek_a/seek_request", &"parameters/seek_b/seek_request"]
const SLOT_NAMES := ["a", "b"]

var tree: AnimationTree
var base_state := ""
var base_speed := 1.0
var move_blend := 0.0
var aim_pitch := 0.0
## Global playback multiplier for this character (0 = frozen during hit-stop).
var time_scale := 1.0

var action_name := ""
var action_time := 0.0
var action_length := 0.0
var action_playing := false
var action_speed := 1.0

var _base_node: AnimationNodeTransition
var _upper_node: AnimationNodeTransition
var _act_trans: AnimationNodeTransition
var _act_nodes: Array[AnimationNodeAnimation] = []
var _slot := 0
var _act_weight := 0.0
var _act_target := 0.0
var _fade_in := 0.08
var _fade_out := 0.2
var _upper_weight := 0.0
var _upper_target := 0.0
var _upper_state := "aim"
var _upper_timer := 0.0


func setup(model_root: Node, lib: AnimationLibrary, skeleton_path: String) -> void:
	tree = AnimationTree.new()
	tree.name = "AnimationTree"
	model_root.add_child(tree)
	tree.root_node = NodePath("..")
	tree.add_animation_library(&"", lib)
	tree.callback_mode_process = AnimationMixer.ANIMATION_CALLBACK_MODE_PROCESS_MANUAL
	tree.tree_root = _build(skeleton_path)
	tree.active = true
	set_base("idle", 0.0)
	tree.advance(0.0)


func _anim(name: String) -> AnimationNodeAnimation:
	var a := AnimationNodeAnimation.new()
	a.animation = StringName(name)
	return a


func _build(skel: String) -> AnimationNodeBlendTree:
	var bt := AnimationNodeBlendTree.new()

	# --- Base locomotion ---------------------------------------------------
	_base_node = AnimationNodeTransition.new()
	_base_node.allow_transition_to_self = true
	var names: Array = BASE_STATES.keys()
	_base_node.input_count = names.size()
	for i in names.size():
		_base_node.set_input_name(i, names[i])
		_base_node.set_input_reset(i, names[i] in RESET_STATES)
	bt.add_node(&"base", _base_node)
	for i in names.size():
		var n: String = names[i]
		if n == "move":
			var bs := AnimationNodeBlendSpace1D.new()
			bs.min_space = 0.0
			bs.max_space = 12.0
			bs.sync_mode = AnimationNodeBlendSpace1D.SYNC_MODE_CYCLIC_MUTABLE
			bs.add_blend_point(_anim("Walk"), 1.6, -1, &"walk")
			bs.add_blend_point(_anim("Jog_Fwd"), 5.5, -1, &"jog")
			bs.add_blend_point(_anim("Sprint"), 9.5, -1, &"sprint")
			bt.add_node(&"move_bs", bs)
			bt.connect_node(&"base", i, &"move_bs")
		else:
			var node_name := StringName("b_" + n)
			bt.add_node(node_name, _anim(BASE_STATES[n]))
			bt.connect_node(&"base", i, node_name)
	bt.add_node(&"base_ts", AnimationNodeTimeScale.new())
	bt.connect_node(&"base_ts", 0, &"base")

	# --- Upper-body aim layer ----------------------------------------------
	var aim := AnimationNodeBlendSpace1D.new()
	aim.min_space = -1.0
	aim.max_space = 1.0
	aim.add_blend_point(_anim("Pistol_Aim_Down"), -1.0, -1, &"down")
	aim.add_blend_point(_anim("Pistol_Aim_Neutral"), 0.0, -1, &"neutral")
	aim.add_blend_point(_anim("Pistol_Aim_Up"), 1.0, -1, &"up")
	bt.add_node(&"aim_bs", aim)
	bt.add_node(&"u_reload", _anim("Pistol_Reload"))
	bt.add_node(&"u_shoot", _anim("Pistol_Shoot"))
	_upper_node = AnimationNodeTransition.new()
	_upper_node.input_count = 3
	_upper_node.set_input_name(0, "aim")
	_upper_node.set_input_name(1, "reload")
	_upper_node.set_input_name(2, "shoot")
	_upper_node.set_input_reset(1, true)
	_upper_node.set_input_reset(2, true)
	_upper_node.allow_transition_to_self = true
	_upper_node.xfade_time = 0.1
	bt.add_node(&"upper_t", _upper_node)
	bt.connect_node(&"upper_t", 0, &"aim_bs")
	bt.connect_node(&"upper_t", 1, &"u_reload")
	bt.connect_node(&"upper_t", 2, &"u_shoot")
	var ub := AnimationNodeBlend2.new()
	ub.filter_enabled = true
	for b in UPPER_BONES:
		ub.set_filter_path(NodePath(skel + ":" + b), true)
	bt.add_node(&"upper_blend", ub)
	bt.connect_node(&"upper_blend", 0, &"base_ts")
	bt.connect_node(&"upper_blend", 1, &"upper_t")

	# --- Full-body action layer (ping-pong slots) ---------------------------
	for s in SLOT_NAMES:
		var an := _anim("Idle")
		_act_nodes.append(an)
		bt.add_node(StringName("act_" + s), an)
		bt.add_node(StringName("seek_" + s), AnimationNodeTimeSeek.new())
		bt.add_node(StringName("ts_" + s), AnimationNodeTimeScale.new())
		bt.connect_node(StringName("seek_" + s), 0, StringName("act_" + s))
		bt.connect_node(StringName("ts_" + s), 0, StringName("seek_" + s))
	_act_trans = AnimationNodeTransition.new()
	_act_trans.input_count = 2
	_act_trans.set_input_name(0, "a")
	_act_trans.set_input_name(1, "b")
	_act_trans.set_input_reset(0, true)
	_act_trans.set_input_reset(1, true)
	bt.add_node(&"act_t", _act_trans)
	bt.connect_node(&"act_t", 0, &"ts_a")
	bt.connect_node(&"act_t", 1, &"ts_b")
	bt.add_node(&"act_blend", AnimationNodeBlend2.new())
	bt.connect_node(&"act_blend", 0, &"upper_blend")
	bt.connect_node(&"act_blend", 1, &"act_t")
	bt.connect_node(&"output", 0, &"act_blend")
	return bt


## Switches the base locomotion state with a crossfade.
func set_base(state: String, xfade: float = 0.15, force: bool = false) -> void:
	if state == base_state and not force:
		return
	base_state = state
	_base_node.xfade_time = xfade
	tree.set(P_BASE, state)


## Plays a full-body action. `length` (real seconds) is when it starts fading out;
## defaults to the clip length at the given speed.
func play_action(anim_name: String, speed: float = 1.0, fade_in: float = 0.07, fade_out: float = 0.18, offset: float = 0.0, length: float = -1.0, weight: float = 1.0) -> void:
	var anim_res := tree.get_animation(StringName(anim_name))
	if anim_res == null:
		push_warning("Missing animation " + anim_name)
		return
	var was_playing := _act_weight > 0.02
	_slot = 1 - _slot
	_act_nodes[_slot].animation = StringName(anim_name)
	tree.set(P_TS[_slot], speed)
	if offset > 0.0:
		tree.set(P_SEEK[_slot], offset)
	_act_trans.xfade_time = fade_in if was_playing else 0.0
	tree.set(P_ACT_T, SLOT_NAMES[_slot])
	action_name = anim_name
	action_speed = speed
	action_time = 0.0
	action_length = length if length > 0.0 else maxf(0.05, (anim_res.length - offset) / maxf(speed, 0.01))
	action_playing = true
	_act_target = weight
	_fade_in = maxf(fade_in, 0.001)
	_fade_out = maxf(fade_out, 0.001)
	if not was_playing:
		_act_weight = 0.0


func stop_action(fade_out: float = 0.18) -> void:
	action_playing = false
	action_name = ""
	_act_target = 0.0
	_fade_out = maxf(fade_out, 0.001)


## Changes the speed of the currently playing action (e.g. hit-stop recovery).
func set_action_speed(speed: float) -> void:
	action_speed = speed
	tree.set(P_TS[_slot], speed)


func set_upper(active: bool) -> void:
	_upper_target = 1.0 if active else 0.0


func upper_active() -> bool:
	return _upper_target > 0.5


## Plays an upper-body clip ("reload"/"shoot") for `duration` then returns to aiming.
func play_upper(state: String, duration: float) -> void:
	_upper_state = state
	_upper_timer = duration
	tree.set(P_UPPER_T, state)


func is_action_done() -> bool:
	return not action_playing


func update(dt: float) -> void:
	var sdt := dt * time_scale
	if action_playing:
		action_time += sdt
		if action_time >= action_length:
			action_playing = false
			action_name = ""
			_act_target = 0.0
	if _upper_timer > 0.0:
		_upper_timer -= sdt
		if _upper_timer <= 0.0 and _upper_state != "aim":
			_upper_state = "aim"
			tree.set(P_UPPER_T, "aim")
	var rate := (1.0 / _fade_in) if _act_target > _act_weight else (1.0 / _fade_out)
	_act_weight = move_toward(_act_weight, _act_target, rate * sdt)
	_upper_weight = move_toward(_upper_weight, _upper_target, 9.0 * dt)
	tree.set(P_ACT_W, _act_weight)
	tree.set(P_UPPER_W, _upper_weight)
	tree.set(P_AIM, aim_pitch)
	tree.set(P_MOVE, move_blend)
	tree.set(P_BASE_TS, base_speed)
	tree.advance(sdt)
