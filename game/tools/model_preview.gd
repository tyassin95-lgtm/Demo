extends SceneTree
# Dev tool: renders a row of models to a PNG. Usage: -- <out.png> <cam_dist> <res1> <res2> ...

func _initialize() -> void:
	_run.call_deferred()

func _run() -> void:
	var args := OS.get_cmdline_user_args()
	var out: String = args[0]
	var dist: float = float(args[1])
	var world := Node3D.new()
	root.add_child(world)
	var env := WorldEnvironment.new()
	var e := Environment.new()
	e.background_mode = Environment.BG_COLOR
	e.background_color = Color(0.12, 0.13, 0.16)
	e.ambient_light_source = Environment.AMBIENT_SOURCE_COLOR
	e.ambient_light_color = Color(0.5, 0.5, 0.55)
	e.glow_enabled = true
	env.environment = e
	world.add_child(env)
	var sun := DirectionalLight3D.new()
	sun.rotation_degrees = Vector3(-40, 30, 0)
	world.add_child(sun)
	var x := 0.0
	var paths := args.slice(2)
	var total_w := 0.0
	var nodes := []
	for p in paths:
		var n: Node3D = load(p).instantiate()
		world.add_child(n)
		var aabb := _aabb(n)
		nodes.append([n, aabb])
		total_w += aabb.size.x + 0.3
	x = -total_w * 0.5
	for pair in nodes:
		var n: Node3D = pair[0]
		var aabb: AABB = pair[1]
		n.position = Vector3(x - aabb.position.x, -aabb.position.y - aabb.size.y * 0.5, -aabb.position.z - aabb.size.z * 0.5)
		print(n.name, " size ", aabb.size)
		x += aabb.size.x + 0.3
	var cam := Camera3D.new()
	world.add_child(cam)
	cam.position = Vector3(0, dist * 0.35, dist)
	cam.look_at(Vector3.ZERO)
	await process_frame
	await process_frame
	await RenderingServer.frame_post_draw
	root.get_viewport().get_texture().get_image().save_png(out)
	quit()

func _aabb(n: Node) -> AABB:
	var result := AABB()
	var first := true
	for c in n.find_children("*", "VisualInstance3D", true, false):
		var vi := c as VisualInstance3D
		var a: AABB = vi.global_transform * vi.get_aabb()
		if first:
			result = a
			first = false
		else:
			result = result.merge(a)
	return result
