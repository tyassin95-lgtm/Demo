extends Node
## Traversal checks (run with --nav-test): jump pads land on target, and melee enemies
## reach a player camping on high ground.

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


func _frames(n: int) -> void:
	for k in n:
		await get_tree().physics_frame


func _run() -> void:
	await _frames(20)
	var p: Player = Game.player
	p.god_mode = true
	var idle := Node.new()
	idle.set_script(load("res://scripts/debug/idle_driver.gd"))
	p.add_child(idle)
	p.bot = idle
	# 1. Every jump pad lands the player within 1.8 m of its target.
	var pads := get_tree().get_nodes_in_group("jump_pads")
	for pad: JumpPad in pads:
		p.velocity = Vector3.ZERO
		p.global_position = pad.global_position + Vector3(0, 0.3, 0)
		await _frames(3)
		var t := 0
		var landed := false
		while t < 240:
			await _frames(1)
			t += 1
			if t > 20 and p.is_on_floor():
				landed = true
				break
		var err := Vector2(p.global_position.x - pad.target.x, p.global_position.z - pad.target.z).length()
		_check("pad %s lands on target" % str(pad.global_position.snapped(Vector3.ONE)), landed and err < 1.8 and absf(p.global_position.y - pad.target.y) < 1.0, "err=%.2f m y=%.2f target_y=%.2f" % [err, p.global_position.y, pad.target.y])
	# 2. Camp on a tower top; strikers must reach the player.
	p.velocity = Vector3.ZERO
	p.global_position = Vector3(18, 5.2, 18)
	var reached := false
	for i in 60 * 45:
		await _frames(1)
		for a in Game.hostiles_of(p.team):
			var e := a as Enemy
			if e and e.kind == Enemy.Kind.STRIKER and e.global_position.distance_to(p.global_position) < 3.5 and absf(e.global_position.y - p.global_position.y) < 1.2:
				reached = true
		if reached:
			print("reached after %.1fs" % (i / 60.0))
			break
	_check("striker reaches player on tower", reached)
	print("NAV RESULT: %d/%d passed" % [ok, ok + fail])
	get_tree().quit(1 if fail > 0 else 0)
