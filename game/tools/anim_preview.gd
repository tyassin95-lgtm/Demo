extends SceneTree
# Dev tool: renders frames of character animations to PNG files for visual review.
# Usage: godot --path . --script res://tools/anim_preview.gd -- <out_dir> <glb> <anim1,anim2,...> [frames]

func _initialize() -> void:
	_run.call_deferred()

func _run() -> void:
	var args := OS.get_cmdline_user_args()
	var out_dir: String = args[0]
	var glb: String = args[1]
	var names: PackedStringArray = args[2].split(",")
	var frames: int = int(args[3]) if args.size() > 3 else 5
	DirAccess.make_dir_recursive_absolute(out_dir)
	var world := Node3D.new()
	root.add_child(world)
	var env := WorldEnvironment.new()
	var e := Environment.new()
	e.background_mode = Environment.BG_COLOR
	e.background_color = Color(0.18, 0.2, 0.24)
	e.ambient_light_source = Environment.AMBIENT_SOURCE_COLOR
	e.ambient_light_color = Color(0.6, 0.6, 0.65)
	env.environment = e
	world.add_child(env)
	var sun := DirectionalLight3D.new()
	sun.rotation_degrees = Vector3(-45, 35, 0)
	world.add_child(sun)
	var floor := MeshInstance3D.new()
	var pm := PlaneMesh.new()
	pm.size = Vector2(6, 6)
	floor.mesh = pm
	world.add_child(floor)
	var character: Node3D = load(glb).instantiate()
	world.add_child(character)
	var cam := Camera3D.new()
	world.add_child(cam)
	cam.position = Vector3(2.6, 1.4, 2.6)
	cam.look_at(Vector3(0, 0.85, 0))
	cam.fov = 50
	var ap: AnimationPlayer = character.find_child("AnimationPlayer", true, false)
	if names[0] == "LIST":
		for lib in ap.get_animation_library_list():
			print("LIB ", lib, ": ", ap.get_animation_library(lib).get_animation_list())
		character.print_tree_pretty()
		print("method: ", RenderingServer.get_current_rendering_method())
		quit()
		return
	for n in names:
		if not ap.has_animation(n):
			print("missing ", n)
			continue
		var anim := ap.get_animation(n)
		ap.play(n)
		for i in frames:
			var t := anim.length * float(i) / float(max(frames - 1, 1))
			ap.seek(t, true)
			await process_frame
			await RenderingServer.frame_post_draw
			var img := root.get_viewport().get_texture().get_image()
			img.save_png("%s/%s_%02d.png" % [out_dir, n, i])
	quit()
