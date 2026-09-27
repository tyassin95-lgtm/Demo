extends Node
## Synthetic multi-touch test of the on-screen controls (run with --touch-test).

var arena: Node
var ok := 0
var fail := 0


func _ready() -> void:
	_run.call_deferred()


func _check(name: String, cond: bool, detail: String = "") -> void:
	print(("PASS  " if cond else "FAIL  ") + name + "  " + detail)
	if cond:
		ok += 1
	else:
		fail += 1


var _c: Control


## Converts control-local (logical) coordinates to window pixels, like a real touch.
func _win(p: Vector2) -> Vector2:
	return _c.get_viewport().get_final_transform() * (_c.get_global_transform_with_canvas() * p)


func _touch(i: int, pos: Vector2, pressed: bool) -> void:
	var e := InputEventScreenTouch.new()
	e.index = i
	e.position = _win(pos)
	e.pressed = pressed
	Input.parse_input_event(e)


func _drag(i: int, pos: Vector2, rel: Vector2) -> void:
	var e := InputEventScreenDrag.new()
	e.index = i
	e.position = _win(pos)
	e.relative = _win(rel) - _win(Vector2.ZERO)
	Input.parse_input_event(e)


func _frames(n: int) -> void:
	for k in n:
		await get_tree().process_frame


func _run() -> void:
	await _frames(30)
	var p: Player = Game.player
	var c: TouchControls = p.controls
	_c = c
	c.visible = true
	p.god_mode = true
	var sz := c.size
	print("controls size: ", sz)
	# 1. Floating stick.
	_touch(0, Vector2(220, sz.y - 200), true)
	await _frames(2)
	_drag(0, Vector2(300, sz.y - 200), Vector2(80, 0))
	await _frames(20)
	_check("stick sets move vector", c.move_vector.x > 0.7, str(c.move_vector))
	_check("player moves right", p.velocity.x > 3.0, "vx=%.1f" % p.velocity.x)
	# 2. Attack button while moving (multi-touch).
	var atk := Vector2(sz.x - 148, sz.y - 150)
	var yaw0 := p.cam.yaw
	_touch(1, atk, true)
	await _frames(3)
	_check("attack button starts attack", p.weapons.is_attacking() or p.state == Actor.State.ATTACK, "state=%s" % Actor.State.keys()[p.state])
	# 3. Drag while holding attack aims the camera.
	for k in 5:
		_drag(1, atk + Vector2(20 * (k + 1), 0), Vector2(20, 0))
		await _frames(1)
	await _frames(2)
	_check("drag on attack aims camera", absf(wrapf(p.cam.yaw - yaw0, -PI, PI)) > 0.05, "dyaw=%.3f" % wrapf(p.cam.yaw - yaw0, -PI, PI))
	_touch(1, atk, false)
	_touch(0, Vector2(300, sz.y - 200), false)
	await _frames(5)
	_check("stick release stops input", c.move_vector == Vector2.ZERO)
	# 4. Free camera drag on the right side.
	yaw0 = p.cam.yaw
	var pitch0 := p.cam.pitch
	_touch(2, Vector2(sz.x * 0.6, 250), true)
	for k in 5:
		_drag(2, Vector2(sz.x * 0.6 - 15 * (k + 1), 250 + 8 * (k + 1)), Vector2(-15, 8))
		await _frames(1)
	_touch(2, Vector2(sz.x * 0.6 - 75, 290), false)
	await _frames(2)
	_check("right-side drag rotates camera", absf(wrapf(p.cam.yaw - yaw0, -PI, PI)) > 0.05 and p.cam.pitch != pitch0, "dyaw=%.3f dpitch=%.3f" % [wrapf(p.cam.yaw - yaw0, -PI, PI), p.cam.pitch - pitch0])
	# 5. Weapon slot tap.
	var slot: Rect2 = c._slot_rect(1)
	_touch(3, slot.get_center(), true)
	await _frames(2)
	_touch(3, slot.get_center(), false)
	await _frames(3)
	_check("weapon slot switches weapon", p.weapons.index == 1, "index=%d" % p.weapons.index)
	# 6. Jump button (stick centred) jumps.
	await _frames(20)
	var jump := Vector2(sz.x - 318, sz.y - 92)
	_touch(4, jump, true)
	await _frames(4)
	_check("jump button jumps", p.velocity.y > 3.0 or not p.is_on_floor(), "vy=%.1f" % p.velocity.y)
	_touch(4, jump, false)
	await _frames(40)
	# 7. Stick forward + SPRINT button sprints.
	var base := Vector2(220, sz.y - 200)
	_touch(0, base, true)
	await _frames(2)
	_drag(0, base + Vector2(0, -80), Vector2(0, -80))
	await _frames(3)
	var spr := Vector2(sz.x - 300, sz.y - 250)
	_touch(5, spr, true)
	await _frames(3)
	_touch(5, spr, false)
	await _frames(20)
	_check("sprint button sprints", p.sprinting, "sprinting=%s speed=%.1f" % [p.sprinting, Vector2(p.velocity.x, p.velocity.z).length()])
	# 8. Double flick of the stick also sprints.
	_drag(0, base, Vector2(0, 80))
	await _frames(20)
	_check("stick back ends sprint", not p.sprinting)
	_drag(0, base + Vector2(0, -80), Vector2(0, -80))
	await _frames(3)
	_drag(0, base, Vector2(0, 80))
	await _frames(3)
	_drag(0, base + Vector2(0, -80), Vector2(0, -80))
	await _frames(10)
	_check("double flick sprints", p.sprinting, "sprinting=%s" % p.sprinting)
	# 9. Stick right + JUMP = side dodge.
	_drag(0, base + Vector2(80, 0), Vector2(80, 80))
	await _frames(3)
	_touch(4, jump, true)
	await _frames(3)
	_check("jump + stick sideways dodges", p.state == Actor.State.DODGE, "state=%s" % Actor.State.keys()[p.state])
	_touch(4, jump, false)
	_touch(0, base + Vector2(80, 0), false)
	await _frames(40)
	# 10. Crouch toggle.
	var crouch := Vector2(sz.x - 440, sz.y - 212)
	_touch(6, crouch, true)
	await _frames(2)
	_touch(6, crouch, false)
	await _frames(5)
	var crouched := p.crouching
	_touch(6, crouch, true)
	await _frames(2)
	_touch(6, crouch, false)
	await _frames(5)
	_check("crouch button toggles", crouched and not p.crouching, "on=%s off=%s" % [crouched, not p.crouching])
	# 11. Pause button.
	await _frames(20)
	var pr: Rect2 = c._pause_rect()
	_touch(7, pr.get_center(), true)
	await _frames(3)
	_touch(7, pr.get_center(), false)
	await _frames(3)
	_check("pause button pauses", get_tree().paused)
	get_tree().paused = false
	print("TOUCH RESULT: %d/%d passed" % [ok, ok + fail])
	get_tree().quit(1 if fail > 0 else 0)
