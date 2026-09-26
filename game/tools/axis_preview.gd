extends SceneTree
# Dev tool: shows right-hand bone axes (X red, Y green, Z blue) in a pose.
func _initialize() -> void:
	_run.call_deferred()

func _run() -> void:
	var args := OS.get_cmdline_user_args()
	var world := Node3D.new()
	root.add_child(world)
	var sun := DirectionalLight3D.new()
	sun.rotation_degrees = Vector3(-50, 30, 0)
	world.add_child(sun)
	var cv := CharacterVisual.new()
	world.add_child(cv)
	cv.build("res://assets/characters/mannequin_m.scn", {"base": Color(0.6, 0.6, 0.6)})
	cv.anim.play_action(args[1], 1.0, 0.001, 0.2, float(args[2]))
	cv.anim.update(0.001)
	for axis in [[Vector3.RIGHT, Color.RED], [Vector3.UP, Color.GREEN], [Vector3.BACK, Color.BLUE]]:
		var mi := MeshInstance3D.new()
		var bm := BoxMesh.new()
		bm.size = Vector3(0.03, 0.03, 0.03) + axis[0].abs() * 0.5
		mi.mesh = bm
		var m := StandardMaterial3D.new()
		m.albedo_color = axis[1]
		m.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
		mi.material_override = m
		mi.position = axis[0] * 0.25
		cv.hand_r.add_child(mi)
	await process_frame
	var cam := Camera3D.new()
	world.add_child(cam)
	cam.fov = 40
	var imgs := []
	for v in [Vector3(0, 1.3, -3.2), Vector3(3.2, 1.3, 0)]:
		cam.position = v
		cam.look_at(Vector3(0, 1.0, 0))
		await process_frame
		await process_frame
		await RenderingServer.frame_post_draw
		imgs.append(root.get_viewport().get_texture().get_image())
	var a: Image = imgs[0]
	var sheet := Image.create(a.get_width() * 2, a.get_height(), false, a.get_format())
	sheet.blit_rect(a, Rect2i(0, 0, a.get_width(), a.get_height()), Vector2i.ZERO)
	sheet.blit_rect(imgs[1], Rect2i(0, 0, a.get_width(), a.get_height()), Vector2i(a.get_width(), 0))
	sheet.save_png(args[0])
	quit()
