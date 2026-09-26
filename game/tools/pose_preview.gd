extends SceneTree
# Dev tool: renders the styled character holding a weapon in a given pose from three
# angles. Usage: -- <out.png> <weapon_id> <anim or "upper"> <time> [model]

func _initialize() -> void:
	_run.call_deferred()


func _run() -> void:
	var args := OS.get_cmdline_user_args()
	var out: String = args[0]
	var weapon_id: String = args[1]
	var anim_name: String = args[2]
	var t: float = float(args[3])
	var model_path: String = args[4] if args.size() > 4 else "res://assets/characters/mannequin_m.scn"
	var world := Node3D.new()
	root.add_child(world)
	var env := WorldEnvironment.new()
	var e := Environment.new()
	e.background_mode = Environment.BG_COLOR
	e.background_color = Color(0.1, 0.11, 0.14)
	e.ambient_light_source = Environment.AMBIENT_SOURCE_COLOR
	e.ambient_light_color = Color(0.55, 0.55, 0.6)
	e.glow_enabled = true
	e.tonemap_mode = Environment.TONE_MAPPER_ACES
	env.environment = e
	world.add_child(env)
	var sun := DirectionalLight3D.new()
	sun.rotation_degrees = Vector3(-50, 30, 0)
	world.add_child(sun)
	var cv := CharacterVisual.new()
	world.add_child(cv)
	cv.build(model_path, {"base": Color(0.88, 0.9, 0.94), "glow": Color(0.2, 0.9, 1.0), "rim": Color(0.2, 0.9, 1.0), "stripe": 0.6})
	var w := WeaponDB.weapon(weapon_id)
	cv.show_weapon(w)
	if anim_name == "upper":
		cv.anim.set_upper(true)
		cv.anim._upper_weight = 1.0
		cv.anim.update(0.001)
	else:
		cv.anim.play_action(anim_name, 1.0, 0.001, 0.2, t)
		cv.anim.update(0.001)
	for i in 3:
		await process_frame
	var vp := root.get_viewport()
	var cam := Camera3D.new()
	world.add_child(cam)
	cam.fov = 40
	var shots := []
	var views := [Vector3(0, 1.3, -3.2), Vector3(3.2, 1.3, 0), Vector3(0.01, 4.5, -0.8)]
	for v in views:
		cam.position = v
		cam.look_at(Vector3(0, 1.0, 0))
		cam.current = true
		for i in 2:
			await process_frame
		await RenderingServer.frame_post_draw
		shots.append(vp.get_texture().get_image())
	var first_img: Image = shots[0]
	var w0 := first_img.get_width()
	var h0 := first_img.get_height()
	var sheet := Image.create(w0 * 3, h0, false, first_img.get_format())
	for i in 3:
		sheet.blit_rect(shots[i], Rect2i(0, 0, w0, h0), Vector2i(w0 * i, 0))
	sheet.save_png(out)
	quit()
