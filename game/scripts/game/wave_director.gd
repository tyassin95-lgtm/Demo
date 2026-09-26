class_name WaveDirector
extends Node
## Runs the match: escalating enemy waves (or a training ground with passive,
## respawning dummies), spawn pacing, scoring and win/lose detection.

signal announce(title: String, subtitle: String, color: Color)
signal wave_changed(index: int, total: int)
signal finished(victory: bool)

const WAVES := [
	{"striker": 3},
	{"striker": 3, "gunner": 2},
	{"striker": 3, "gunner": 2, "brute": 1},
	{"striker": 4, "gunner": 3, "brute": 1},
	{"striker": 5, "gunner": 3, "brute": 2},
]
const BREAK_TIME := 4.0

var arena: Node3D
var spawns: Array[Vector3] = []
var wave := -1
var state := "idle"
var queue: Array = []
var alive: Array = []
var max_alive := 5
var spawn_timer := 0.0
var break_timer := 0.0
var score := 0
var elapsed := 0.0
var kills := 0
var training := false


func start(mode: int) -> void:
	Enemy.melee_tokens = 0
	Enemy.max_tokens = 2
	Game.actor_died.connect(_on_actor_died)
	if mode == Game.Mode.TRAINING:
		training = true
		state = "training"
		announce.emit("TRAINING GROUND", "Passive targets · practice freely", Color(0.4, 1.0, 0.7))
		for i in 3:
			_spawn_dummy(i)
	else:
		state = "break"
		break_timer = 3.0
		announce.emit("GET READY", "Survive %d waves" % WAVES.size(), Color(0.4, 0.9, 1.0))


func total_waves() -> int:
	return WAVES.size()


func enemies_remaining() -> int:
	return queue.size() + alive.size()


func _process(delta: float) -> void:
	alive = alive.filter(func(e: Variant) -> bool: return is_instance_valid(e) and (e as Actor).is_alive())
	match state:
		"break":
			var before := break_timer
			break_timer -= delta
			if wave >= 0 and before > 3.0 and break_timer <= 3.0:
				Audio.play("beep", -6.0)
			if break_timer <= 0.0:
				_begin_wave(wave + 1)
		"fighting":
			elapsed += delta
			spawn_timer -= delta
			if not queue.is_empty() and alive.size() < max_alive and spawn_timer <= 0.0:
				_spawn(queue.pop_front())
				spawn_timer = 0.85
			if queue.is_empty() and alive.is_empty():
				_wave_cleared()
		"training":
			elapsed += delta


func _begin_wave(i: int) -> void:
	wave = i
	state = "fighting"
	queue.clear()
	var w: Dictionary = WAVES[i]
	for k in ["brute", "gunner", "striker"]:
		for n in int(w.get(k, 0)):
			queue.append(k)
	queue.shuffle()
	# Make sure the first spawns aren't all brutes.
	queue.sort_custom(func(a: Variant, b: Variant) -> bool: return a != "brute" and b == "brute")
	max_alive = 4 + mini(i, 2)
	Enemy.max_tokens = 1 if i < 2 else (2 if i < 4 else 3)
	spawn_timer = 0.3
	var title := "WAVE %d" % (i + 1) if i < WAVES.size() - 1 else "FINAL WAVE"
	announce.emit(title, "%d hostiles incoming" % queue.size(), Color(1.0, 0.5, 0.2) if i == WAVES.size() - 1 else Color(0.4, 0.9, 1.0))
	wave_changed.emit(i, WAVES.size())
	Audio.play("wave_start", 0.0)


func _wave_cleared() -> void:
	if wave >= WAVES.size() - 1:
		state = "done"
		score += int(maxf(0.0, 600.0 - elapsed) * 5.0)
		announce.emit("ARENA CLEARED", "All waves defeated", Color(0.5, 1.0, 0.6))
		Audio.play("wave_clear", 2.0)
		finished.emit(true)
		return
	state = "break"
	break_timer = BREAK_TIME
	announce.emit("WAVE CLEAR", "+25 HP · next wave in %d" % int(BREAK_TIME), Color(0.5, 1.0, 0.6))
	Audio.play("wave_clear", 0.0)
	if Game.player and is_instance_valid(Game.player):
		(Game.player as Actor).heal(25.0)


func _difficulty() -> float:
	return 1.0 + maxf(wave, 0) * 0.12


func _pick_spawn() -> Vector3:
	var p: Vector3 = Game.player.global_position if Game.player and is_instance_valid(Game.player) else Vector3.ZERO
	var scored := []
	for sp in spawns:
		scored.append([_spawn_score(sp, p), sp])
	scored.sort_custom(func(a: Array, b: Array) -> bool: return a[0] > b[0])
	return scored[randi() % mini(3, scored.size())][1]


func _spawn_score(s: Vector3, p: Vector3) -> float:
	var d := s.distance_to(p)
	# Prefer medium distances: not on top of the player, not across the map.
	return -absf(d - 20.0) + randf() * 4.0


func _spawn(kind_name: String) -> void:
	var e := Enemy.new()
	var k := Enemy.Kind.STRIKER
	match kind_name:
		"gunner":
			k = Enemy.Kind.GUNNER
		"brute":
			k = Enemy.Kind.BRUTE
	e.setup(k, _difficulty())
	arena.add_child(e)
	e.global_position = _pick_spawn()
	if Game.player and is_instance_valid(Game.player):
		var to: Vector3 = Game.player.global_position - e.global_position
		e.facing = Actor.yaw_from_dir(Vector3(to.x, 0, to.z).normalized())
	alive.append(e)


func _spawn_dummy(i: int) -> void:
	var e := Enemy.new()
	e.setup(Enemy.Kind.GUNNER if i == 2 else Enemy.Kind.STRIKER, 1.0)
	e.passive = true
	e.respawn_training = true
	arena.add_child(e)
	var pos := [Vector3(-5, 0.1, 4), Vector3(5, 0.1, 4), Vector3(0, 0.1, -16)]
	e.global_position = pos[i]
	e.set_meta("dummy_slot", i)
	alive.append(e)


func _on_actor_died(a: Node) -> void:
	if a is Enemy:
		var e := a as Enemy
		kills += 1
		var combo: int = Game.player.combo if Game.player and is_instance_valid(Game.player) else 0
		var mult := 1.0 + minf(combo, 40) * 0.025
		score += int(Enemy.SCORE.get(e.kind, 100) * mult)
		if training and e.has_meta("dummy_slot"):
			var slot: int = e.get_meta("dummy_slot")
			get_tree().create_timer(2.5).timeout.connect(func() -> void:
				if is_inside_tree():
					_spawn_dummy(slot))
	elif a is Player:
		if state != "done":
			state = "done"
			finished.emit(false)
