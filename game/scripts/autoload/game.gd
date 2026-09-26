extends Node
## Global game state: input map, live actor registry, scene transitions, haptics.

signal actor_died(actor: Node)

enum Mode { WAVES, TRAINING }

const TEAM_PLAYER := 0
const TEAM_ENEMY := 1

const LAYER_WORLD := 1
const LAYER_PLAYER := 2
const LAYER_ENEMY := 4
const LAYER_PICKUP := 8

var mode: Mode = Mode.WAVES
var player: Node3D = null
var camera: Node3D = null
var actors: Array = []
var last_results := {}
var is_touch_device := false

# Debug / automation (command line: -- --shots=DIR --shot-frames=60,120 --quit-frame=200 --mode=training --bot)
var debug_args := {}
var _frame := 0
var _shot_frames: Array = []

var _fade_layer: CanvasLayer
var _fade_rect: ColorRect
var _switching := false


func _ready() -> void:
	process_mode = Node.PROCESS_MODE_ALWAYS
	# Back button is handled by the menus (pause in-game, close panels / quit in menu).
	get_tree().quit_on_go_back = false
	is_touch_device = DisplayServer.is_touchscreen_available() and OS.has_feature("mobile")
	_setup_input_map()
	_fade_layer = CanvasLayer.new()
	_fade_layer.layer = 100
	add_child(_fade_layer)
	_fade_rect = ColorRect.new()
	_fade_rect.color = Color(0.01, 0.01, 0.03, 0.0)
	_fade_rect.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_fade_rect.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	_fade_layer.add_child(_fade_rect)
	_parse_debug_args()


func _parse_debug_args() -> void:
	for a in OS.get_cmdline_user_args():
		if a.begins_with("--"):
			var kv := a.substr(2).split("=", true, 1)
			debug_args[kv[0]] = kv[1] if kv.size() > 1 else "1"
	if debug_args.has("mode"):
		mode = Mode.TRAINING if debug_args["mode"] == "training" else Mode.WAVES
	if debug_args.has("shot-frames"):
		for f in String(debug_args["shot-frames"]).split(","):
			_shot_frames.append(int(f))


func _process(_delta: float) -> void:
	if debug_args.is_empty():
		return
	_frame += 1
	if debug_args.has("nav-test") and player and is_instance_valid(player) and not has_node("NavTest"):
		var nt: Node = load("res://scripts/debug/nav_test.gd").new()
		nt.name = "NavTest"
		add_child(nt)
	if debug_args.has("touch-test") and player and is_instance_valid(player) and not has_node("TouchTest"):
		var tt: Node = load("res://scripts/debug/touch_test.gd").new()
		tt.name = "TouchTest"
		add_child(tt)
	if debug_args.has("bot") and player and is_instance_valid(player) and player.get("bot") == null:
		var b: Node = load("res://scripts/debug/test_bot.gd").new()
		player.add_child(b)
		player.set("bot", b)
		if debug_args.has("god"):
			player.set("god_mode", true)
	if _shot_frames.has(_frame) and debug_args.has("shots"):
		var img := get_viewport().get_texture().get_image()
		var path := "%s/shot_%04d.png" % [debug_args["shots"], _frame]
		img.save_png(path)
		print("[debug] saved ", path)
	if debug_args.has("perf") and _frame % 60 == 0:
		print("[perf] frame=%d draw_calls=%d objects=%d primitives=%d nodes=%d vram=%.0fMB mem=%.0fMB" % [_frame,
			Performance.get_monitor(Performance.RENDER_TOTAL_DRAW_CALLS_IN_FRAME),
			Performance.get_monitor(Performance.RENDER_TOTAL_OBJECTS_IN_FRAME),
			Performance.get_monitor(Performance.RENDER_TOTAL_PRIMITIVES_IN_FRAME),
			Performance.get_monitor(Performance.OBJECT_NODE_COUNT),
			Performance.get_monitor(Performance.RENDER_VIDEO_MEM_USED) / 1048576.0,
			Performance.get_monitor(Performance.MEMORY_STATIC) / 1048576.0])
	if debug_args.has("ui-tour") and player and is_instance_valid(player):
		var arena := get_tree().current_scene
		if _frame == 40:
			arena.pause_menu.open()
		elif _frame == 55:
			arena.pause_menu._open_settings()
		elif _frame == 70:
			arena.pause_menu._resume()
			player.health = 1.0
			var h := HitInfo.make(50.0, null, Vector3.FORWARD, HitInfo.Reaction.KNOCKDOWN)
			player.take_hit(h)
	if debug_args.has("flow-test"):
		match _frame:
			60:
				print("[flow] start waves from ", get_tree().current_scene.name)
				start_mode(Mode.WAVES)
			300:
				print("[flow] in ", get_tree().current_scene.name, " actors=", actors.size(), " -> menu")
				goto_scene("res://scenes/main_menu.tscn")
			420:
				print("[flow] in ", get_tree().current_scene.name, " -> training")
				start_mode(Mode.TRAINING)
			700:
				print("[flow] in ", get_tree().current_scene.name, " actors=", actors.size(), " -> retry")
				start_mode(mode)
			900:
				print("[flow] in ", get_tree().current_scene.name, " actors=", actors.size(), " done")
				get_tree().quit()
	if debug_args.has("quit-frame") and _frame >= int(debug_args["quit-frame"]):
		get_tree().quit()


func _setup_input_map() -> void:
	var keys := {
		"move_forward": [KEY_W, KEY_UP],
		"move_back": [KEY_S, KEY_DOWN],
		"move_left": [KEY_A, KEY_LEFT],
		"move_right": [KEY_D, KEY_RIGHT],
		"jump": [KEY_SPACE],
		"sprint": [KEY_SHIFT],
		"dash": [KEY_CTRL, KEY_Q],
		"attack": [],
		"special": [KEY_F],
		"overdrive": [KEY_E],
		"reload": [KEY_R],
		"weapon_1": [KEY_1],
		"weapon_2": [KEY_2],
		"weapon_3": [KEY_3],
		"weapon_4": [KEY_4],
		"weapon_next": [KEY_TAB],
		"pause": [KEY_ESCAPE, KEY_P],
	}
	for action in keys:
		if not InputMap.has_action(action):
			InputMap.add_action(action, 0.2)
		for k in keys[action]:
			var ev := InputEventKey.new()
			ev.physical_keycode = k
			InputMap.action_add_event(action, ev)
	var lmb := InputEventMouseButton.new()
	lmb.button_index = MOUSE_BUTTON_LEFT
	InputMap.action_add_event("attack", lmb)
	var rmb := InputEventMouseButton.new()
	rmb.button_index = MOUSE_BUTTON_RIGHT
	InputMap.action_add_event("special", rmb)
	# Gamepad support (nice to have for testing on Android TV / controllers).
	_add_joy_button("jump", JOY_BUTTON_A)
	_add_joy_button("dash", JOY_BUTTON_B)
	_add_joy_button("attack", JOY_BUTTON_RIGHT_SHOULDER)
	_add_joy_button("special", JOY_BUTTON_LEFT_SHOULDER)
	_add_joy_button("overdrive", JOY_BUTTON_Y)
	_add_joy_button("weapon_next", JOY_BUTTON_X)
	_add_joy_button("pause", JOY_BUTTON_START)
	_add_joy_axis("move_left", JOY_AXIS_LEFT_X, -1.0)
	_add_joy_axis("move_right", JOY_AXIS_LEFT_X, 1.0)
	_add_joy_axis("move_forward", JOY_AXIS_LEFT_Y, -1.0)
	_add_joy_axis("move_back", JOY_AXIS_LEFT_Y, 1.0)


func _add_joy_button(action: String, button: JoyButton) -> void:
	var ev := InputEventJoypadButton.new()
	ev.button_index = button
	InputMap.action_add_event(action, ev)


func _add_joy_axis(action: String, axis: JoyAxis, value: float) -> void:
	var ev := InputEventJoypadMotion.new()
	ev.axis = axis
	ev.axis_value = value
	InputMap.action_add_event(action, ev)


# --- Actor registry -------------------------------------------------------

func register_actor(a: Node) -> void:
	if not actors.has(a):
		actors.append(a)


func unregister_actor(a: Node) -> void:
	actors.erase(a)


## Returns living actors that are hostile to `team`.
func hostiles_of(team: int) -> Array:
	var out := []
	for a in actors:
		if is_instance_valid(a) and a.team != team and a.is_alive():
			out.append(a)
	return out


func notify_death(a: Node) -> void:
	actor_died.emit(a)


# --- Feedback -------------------------------------------------------------

func shake(amount: float) -> void:
	if camera and is_instance_valid(camera) and camera.has_method("add_trauma"):
		camera.add_trauma(amount)


func vibrate(ms: int, amplitude: float = -1.0) -> void:
	if not Settings.get_value("vibration"):
		return
	if OS.has_feature("mobile"):
		Input.vibrate_handheld(ms, amplitude)


# --- Scene flow -----------------------------------------------------------

func start_mode(m: Mode) -> void:
	mode = m
	goto_scene("res://scenes/arena.tscn")


func goto_scene(path: String) -> void:
	if _switching:
		return
	_switching = true
	get_tree().paused = false
	Engine.time_scale = 1.0
	var tw := create_tween()
	tw.tween_property(_fade_rect, "color:a", 1.0, 0.25)
	await tw.finished
	actors.clear()
	player = null
	camera = null
	get_tree().change_scene_to_file(path)
	await get_tree().process_frame
	await get_tree().process_frame
	var tw2 := create_tween()
	tw2.tween_property(_fade_rect, "color:a", 0.0, 0.35)
	_switching = false


func flash_screen(color: Color, duration: float) -> void:
	_fade_rect.color = Color(color.r, color.g, color.b, color.a)
	var tw := create_tween()
	tw.tween_property(_fade_rect, "color:a", 0.0, duration)
