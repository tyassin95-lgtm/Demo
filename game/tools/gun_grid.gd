extends SceneTree
# Dev tool: orthographic side view of a gun model over a 10 cm grid (origin = yellow).
func _initialize() -> void:
	_run.call_deferred()

func _run() -> void:
	var args := OS.get_cmdline_user_args()
	var world := Node3D.new()
	root.add_child(world)
	var env := WorldEnvironment.new()
	var e := Environment.new()
	e.background_mode = Environment.BG_COLOR
	e.background_color = Color(0.25, 0.25, 0.3)
	e.ambient_light_source = Environment.AMBIENT_SOURCE_COLOR
	e.ambient_light_color = Color(0.9, 0.9, 0.9)
	env.environment = e
	world.add_child(env)
	var gun: Node3D = load(args[1]).instantiate()
	world.add_child(gun)
	var m := StandardMaterial3D.new()
	m.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	m.albedo_color = Color(0.6, 0.6, 0.6)
	for i in range(-10, 11):
		for horiz in [true, false]:
			var mi := MeshInstance3D.new()
			var bm := BoxMesh.new()
			bm.size = Vector3(2.0, 0.002, 0.002) if horiz else Vector3(0.002, 2.0, 0.002)
			mi.mesh = bm
			mi.material_override = m
			mi.position = Vector3(0, i * 0.1, -0.2) if horiz else Vector3(i * 0.1, 0, -0.2)
			world.add_child(mi)
	var o := MeshInstance3D.new()
	var sm := SphereMesh.new()
	sm.radius = 0.012
	sm.height = 0.024
	o.mesh = sm
	var om := StandardMaterial3D.new()
	om.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	om.albedo_color = Color.YELLOW
	o.material_override = om
	world.add_child(o)
	var cam := Camera3D.new()
	cam.projection = Camera3D.PROJECTION_ORTHOGONAL
	cam.size = float(args[2])
	cam.position = Vector3(0, 0, 2)
	world.add_child(cam)
	await process_frame
	await process_frame
	await RenderingServer.frame_post_draw
	root.get_viewport().get_texture().get_image().save_png(args[0])
	quit()
