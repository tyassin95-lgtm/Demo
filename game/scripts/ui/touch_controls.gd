class_name TouchControls
extends Control
## Mobile touch controls: floating move stick (left), camera drag (right), action
## buttons (hold ATTACK and drag to aim at the same time), weapon slots, overdrive.
## Everything is drawn procedurally. Supports scale/opacity/left-handed settings.

signal pause_requested

const STICK_RADIUS := 78.0
const DEFAULT_STICK := Vector2(190, -190)

## name, offset from bottom-right corner (px @ scale 1), radius, look-drag allowed
var button_defs := [
	["attack", Vector2(-148, -150), 80.0, true],
	["jump", Vector2(-318, -92), 58.0, false],
	["dash", Vector2(-300, -250), 54.0, false],
	["special", Vector2(-152, -326), 52.0, true],
	["overdrive", Vector2(-420, -330), 44.0, false],
	["reload", Vector2(-445, -95), 34.0, false],
]

var player: Player
var camera: PlayerCamera
var move_vector := Vector2.ZERO
var stick_active := false
var sprint_active := false

var _stick_touch := -1
var _stick_origin := Vector2.ZERO
var _stick_pos := Vector2.ZERO
var _look_touches := {}
var _button_touches := {}
var _held := {}
var _presses := {}
var _consumed := {}
var _pulse := 0.0
var _font: Font
var _font_bold: Font
var _flash := {}


func _ready() -> void:
	set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	mouse_filter = Control.MOUSE_FILTER_IGNORE
	_font = load("res://assets/fonts/Rajdhani-SemiBold.ttf")
	_font_bold = load("res://assets/fonts/Rajdhani-Bold.ttf")
	for d in button_defs:
		_presses[d[0]] = 0
		_consumed[d[0]] = 0
		_held[d[0]] = false
	for n in ["weapon_1", "weapon_2", "weapon_3", "weapon_4", "pause", "weapon_next"]:
		_presses[n] = 0
		_consumed[n] = 0
		_held[n] = false
	Settings.changed.connect(func(_k: String) -> void: queue_redraw())


## Clears all touch state (pause, focus loss) so nothing stays "held".
func reset() -> void:
	_stick_touch = -1
	stick_active = false
	move_vector = Vector2.ZERO
	_look_touches.clear()
	_button_touches.clear()
	for k in _held:
		_held[k] = false
	queue_redraw()


func _notification(what: int) -> void:
	if what == NOTIFICATION_APPLICATION_FOCUS_OUT or what == NOTIFICATION_APPLICATION_PAUSED:
		reset()


# --- Queries used by the player ----------------------------------------------------

func consume(name: String) -> bool:
	if not _presses.has(name):
		return false
	if _presses[name] > _consumed[name]:
		_consumed[name] = _presses[name]
		return true
	return false


func is_held(name: String) -> bool:
	return _held.get(name, false)


func _press(name: String) -> void:
	_presses[name] = _presses.get(name, 0) + 1
	_held[name] = true
	_flash[name] = 1.0
	if name == "pause":
		pause_requested.emit()


# --- Layout ------------------------------------------------------------------------

func _scale() -> float:
	return float(Settings.get_value("button_scale"))


func _left_handed() -> bool:
	return bool(Settings.get_value("left_handed"))


func _button_center(d: Array) -> Vector2:
	var s := _scale()
	var off: Vector2 = d[1] * s
	if _left_handed():
		return Vector2(-off.x, size.y + off.y)
	return Vector2(size.x + off.x, size.y + off.y)


func _button_radius(d: Array) -> float:
	return d[2] * _scale()


func _slot_rect(i: int) -> Rect2:
	var s := _scale()
	var w := 92.0 * s
	var h := 50.0 * s
	var gap := 8.0 * s
	var total := 4.0 * w + 3.0 * gap
	var x0 := size.x - total - 24.0 if not _left_handed() else 24.0
	return Rect2(Vector2(x0 + i * (w + gap), 86.0), Vector2(w, h))


func _pause_rect() -> Rect2:
	var s := 52.0
	return Rect2(Vector2(size.x - s - 20.0 if not _left_handed() else 20.0, 18.0), Vector2(s, s))


func _stick_zone(pos: Vector2) -> bool:
	if _left_handed():
		return pos.x > size.x * 0.58 and pos.y > size.y * 0.3
	return pos.x < size.x * 0.42 and pos.y > size.y * 0.3


func _button_at(pos: Vector2) -> String:
	if _pause_rect().grow(14.0).has_point(pos):
		return "pause"
	for i in 4:
		if _slot_rect(i).grow(4.0).has_point(pos):
			return "weapon_%d" % (i + 1)
	var best := ""
	var best_d := INF
	for d in button_defs:
		if d[0] == "overdrive" and (player == null or player.overdrive < 100.0):
			continue
		var c := _button_center(d)
		var r := _button_radius(d) * 1.2
		var dist := pos.distance_to(c)
		if dist < r and dist < best_d:
			best_d = dist
			best = d[0]
	return best


# --- Input ---------------------------------------------------------------------------

func _input(event: InputEvent) -> void:
	if not visible or get_tree().paused:
		return
	if event is InputEventScreenTouch:
		var e := make_input_local(event) as InputEventScreenTouch
		if e.pressed:
			_touch_down(e.index, e.position)
		else:
			_touch_up(e.index)
		get_viewport().set_input_as_handled()
	elif event is InputEventScreenDrag:
		var e := make_input_local(event) as InputEventScreenDrag
		_drag(e.index, e.position, e.relative)
		get_viewport().set_input_as_handled()


func _touch_down(i: int, pos: Vector2) -> void:
	var b := _button_at(pos)
	if b != "":
		_button_touches[i] = b
		_press(b)
		queue_redraw()
		return
	if _stick_zone(pos) and _stick_touch < 0:
		_stick_touch = i
		_stick_origin = pos
		_stick_pos = pos
		stick_active = true
	else:
		_look_touches[i] = pos
	queue_redraw()


func _touch_up(i: int) -> void:
	if i == _stick_touch:
		_stick_touch = -1
		stick_active = false
		move_vector = Vector2.ZERO
	elif _look_touches.has(i):
		_look_touches.erase(i)
	elif _button_touches.has(i):
		var b: String = _button_touches[i]
		_button_touches.erase(i)
		if not _button_touches.values().has(b):
			_held[b] = false
	queue_redraw()


func _drag(i: int, pos: Vector2, rel: Vector2) -> void:
	if i == _stick_touch:
		var r := STICK_RADIUS * _scale()
		var d := pos - _stick_origin
		# Floating stick: the base follows the thumb if it drifts too far.
		if d.length() > r * 1.35:
			_stick_origin = pos - d.normalized() * r * 1.35
			d = pos - _stick_origin
		_stick_pos = pos
		var v := d / r
		if v.length() > 1.0:
			v = v.normalized()
		# Small dead zone, then remap so fine control is easy.
		var mag := v.length()
		if mag < 0.12:
			v = Vector2.ZERO
		else:
			v = v.normalized() * clampf((mag - 0.12) / 0.88, 0.0, 1.0)
		move_vector = Vector2(v.x, -v.y)
		queue_redraw()
	elif _look_touches.has(i):
		if camera:
			camera.add_touch_look(rel)
		_look_touches[i] = pos
	elif _button_touches.has(i):
		var b: String = _button_touches[i]
		for d in button_defs:
			if d[0] == b and d[3] and camera:
				camera.add_touch_look(rel)


func _process(delta: float) -> void:
	_pulse += delta
	for k in _flash.keys():
		_flash[k] = maxf(_flash[k] - delta * 5.0, 0.0)
	queue_redraw()


# --- Drawing -------------------------------------------------------------------------

func _draw() -> void:
	var alpha := float(Settings.get_value("button_opacity"))
	var accent := Color(0.3, 0.9, 1.0)
	var w: WeaponDB.Weapon = player.weapons.current() if player and is_instance_valid(player) else null
	if w:
		accent = w.color
	# Joystick.
	var r := STICK_RADIUS * _scale()
	var base := _stick_origin if stick_active else Vector2(size.x - DEFAULT_STICK.x * _scale() if _left_handed() else DEFAULT_STICK.x * _scale(), size.y + DEFAULT_STICK.y * _scale())
	var knob := _stick_pos if stick_active else base
	if (knob - base).length() > r:
		knob = base + (knob - base).normalized() * r
	draw_circle(base, r, Color(0.05, 0.08, 0.12, 0.35 * alpha))
	draw_arc(base, r, 0, TAU, 48, Color(0.6, 0.85, 1.0, 0.45 * alpha), 2.5, true)
	var sprint := player != null and is_instance_valid(player) and player.sprinting
	draw_circle(knob, r * 0.42, Color(accent.r, accent.g, accent.b, (0.55 if sprint else 0.35) * alpha))
	draw_arc(knob, r * 0.42, 0, TAU, 32, Color(1, 1, 1, 0.7 * alpha), 2.0, true)
	if sprint:
		draw_arc(base, r + 6.0, 0, TAU, 48, Color(accent.r, accent.g, accent.b, 0.8 * alpha), 3.0, true)
	# Action buttons.
	for d in button_defs:
		var name: String = d[0]
		if name == "overdrive" and (player == null or not is_instance_valid(player)):
			continue
		var c := _button_center(d)
		var br := _button_radius(d)
		var held: bool = _held.get(name, false)
		var fl: float = _flash.get(name, 0.0)
		var fill_a := (0.5 if held else 0.28) * alpha
		var ring_col := Color(1, 1, 1, 0.75 * alpha)
		var ready := true
		if name == "overdrive":
			ready = player.overdrive >= 100.0
			var od_col := Color(1.0, 0.55, 0.15)
			draw_circle(c, br, Color(0.08, 0.05, 0.02, 0.4 * alpha))
			draw_arc(c, br, -PI / 2.0, -PI / 2.0 + TAU * player.overdrive / 100.0, 48, Color(od_col.r, od_col.g, od_col.b, 0.9 * alpha), 5.0, true)
			if ready:
				var p := 0.5 + 0.5 * sin(_pulse * 6.0)
				draw_circle(c, br * (0.85 + 0.1 * p), Color(od_col.r, od_col.g, od_col.b, (0.35 + 0.3 * p) * alpha))
			_draw_icon(name, c, br, Color(1, 1, 1, (1.0 if ready else 0.35) * alpha), w)
			continue
		if name == "reload" and (w == null or w.kind == WeaponDB.Kind.MELEE):
			continue
		draw_circle(c, br, Color(0.04, 0.07, 0.11, fill_a))
		if fl > 0.0:
			draw_circle(c, br * (1.0 + fl * 0.15), Color(accent.r, accent.g, accent.b, fl * 0.35 * alpha))
		draw_arc(c, br, 0, TAU, 48, ring_col if not held else Color(accent.r, accent.g, accent.b, alpha), 3.0, true)
		if name == "attack":
			draw_arc(c, br - 7.0, 0, TAU, 48, Color(accent.r, accent.g, accent.b, 0.55 * alpha), 2.0, true)
		if name == "dash" and player and is_instance_valid(player):
			var st := player.stamina / Player.STAMINA_MAX
			draw_arc(c, br + 5.0, -PI / 2.0, -PI / 2.0 + TAU * st, 40, Color(0.4, 1.0, 0.6, 0.7 * alpha), 3.0, true)
		_draw_icon(name, c, br, Color(1, 1, 1, 0.92 * alpha), w)
	# Weapon slots.
	if player and is_instance_valid(player):
		for i in mini(4, player.weapons.loadout.size()):
			var rect := _slot_rect(i)
			var ww: WeaponDB.Weapon = player.weapons.loadout[i]
			var sel := i == player.weapons.index
			var col := ww.color
			draw_rect(rect, Color(0.03, 0.05, 0.09, (0.75 if sel else 0.45) * alpha))
			draw_rect(rect, Color(col.r, col.g, col.b, (1.0 if sel else 0.4) * alpha), false, 2.5 if sel else 1.5)
			if sel:
				draw_rect(Rect2(rect.position + Vector2(0, rect.size.y - 5), Vector2(rect.size.x, 5)), Color(col.r, col.g, col.b, alpha))
			var fs := int(17 * _scale())
			draw_string(_font_bold, rect.position + Vector2(8, 21 * _scale()), ww.short_name, HORIZONTAL_ALIGNMENT_LEFT, -1, fs, Color(1, 1, 1, (1.0 if sel else 0.6) * alpha))
			var sub := "∞" if ww.kind == WeaponDB.Kind.MELEE else "%d" % player.weapons.ammo[i]
			draw_string(_font, rect.position + Vector2(8, 41 * _scale()), sub, HORIZONTAL_ALIGNMENT_LEFT, -1, int(15 * _scale()), Color(col.r, col.g, col.b, alpha))
			draw_string(_font, rect.position + Vector2(rect.size.x - 16 * _scale(), 41 * _scale()), str(i + 1), HORIZONTAL_ALIGNMENT_LEFT, -1, int(13 * _scale()), Color(1, 1, 1, 0.35 * alpha))
	# Pause button.
	var pr := _pause_rect()
	draw_rect(pr, Color(0.03, 0.05, 0.09, 0.55 * alpha))
	draw_rect(pr, Color(1, 1, 1, 0.6 * alpha), false, 2.0)
	var pc := pr.get_center()
	draw_rect(Rect2(pc + Vector2(-10, -12), Vector2(7, 24)), Color(1, 1, 1, 0.9 * alpha))
	draw_rect(Rect2(pc + Vector2(3, -12), Vector2(7, 24)), Color(1, 1, 1, 0.9 * alpha))


func _draw_icon(name: String, c: Vector2, r: float, col: Color, w: WeaponDB.Weapon) -> void:
	var s := r * 0.42
	match name:
		"attack":
			if w == null or w.kind == WeaponDB.Kind.MELEE:
				# Diagonal blade with a crossguard.
				draw_line(c + Vector2(-s, s), c + Vector2(s * 1.05, -s * 1.05), col, 5.0, true)
				draw_line(c + Vector2(-s * 0.95, s * 0.35), c + Vector2(-s * 0.35, s * 0.95), col, 4.0, true)
				draw_circle(c + Vector2(-s * 1.05, s * 1.05), 4.0, col)
			else:
				draw_arc(c, s * 0.8, 0, TAU, 32, col, 3.0, true)
				for a in 4:
					var dir := Vector2.from_angle(a * PI / 2.0)
					draw_line(c + dir * s * 0.45, c + dir * s * 1.2, col, 3.0, true)
				draw_circle(c, 3.0, col)
		"jump":
			var pts := PackedVector2Array([c + Vector2(-s, s * 0.45), c + Vector2(0, -s * 0.55), c + Vector2(s, s * 0.45)])
			draw_polyline(pts, col, 5.0, true)
			draw_line(c + Vector2(-s * 0.6, s * 0.95), c + Vector2(s * 0.6, s * 0.95), col, 3.0, true)
		"dash":
			for k in 2:
				var o := Vector2(-s * 0.55 + k * s * 0.75, 0)
				draw_polyline(PackedVector2Array([c + o + Vector2(-s * 0.35, -s * 0.7), c + o + Vector2(s * 0.35, 0), c + o + Vector2(-s * 0.35, s * 0.7)]), col, 4.5, true)
		"special":
			var kind := w.secondary if w else WeaponDB.Secondary.HEAVY
			match kind:
				WeaponDB.Secondary.HEAVY:
					# Two heavy slash marks and an impact burst.
					draw_line(c + Vector2(-s * 0.9, s * 0.55), c + Vector2(s * 0.35, -s * 0.9), col, 5.0, true)
					draw_line(c + Vector2(-s * 0.35, s * 0.9), c + Vector2(s * 0.9, -s * 0.55), col, 5.0, true)
					for k in 5:
						var a := -PI * 0.9 + k * PI * 0.2
						var d := Vector2.from_angle(a)
						draw_line(c + Vector2(s * 0.55, s * 0.55) + d * s * 0.2, c + Vector2(s * 0.55, s * 0.55) + d * s * 0.45, col, 2.0, true)
				WeaponDB.Secondary.GRENADE:
					draw_circle(c + Vector2(0, s * 0.2), s * 0.62, col)
					draw_line(c + Vector2(0, -s * 0.4), c + Vector2(0, -s * 0.8), col, 4.0, true)
					draw_arc(c + Vector2(s * 0.3, -s * 0.8), s * 0.3, PI, TAU, 12, col, 2.5, true)
				WeaponDB.Secondary.BLAST_JUMP:
					draw_polyline(PackedVector2Array([c + Vector2(-s * 0.7, 0), c + Vector2(0, -s * 0.8), c + Vector2(s * 0.7, 0)]), col, 4.5, true)
					draw_polyline(PackedVector2Array([c + Vector2(-s * 0.7, s * 0.7), c + Vector2(0, -s * 0.1), c + Vector2(s * 0.7, s * 0.7)]), col, 4.5, true)
				WeaponDB.Secondary.SCOPE:
					draw_arc(c, s * 0.85, 0, TAU, 32, col, 3.5, true)
					draw_line(c + Vector2(-s * 1.1, 0), c + Vector2(s * 1.1, 0), col, 2.5, true)
					draw_line(c + Vector2(0, -s * 1.1), c + Vector2(0, s * 1.1), col, 2.5, true)
		"overdrive":
			var bolt := PackedVector2Array([c + Vector2(s * 0.15, -s), c + Vector2(-s * 0.5, s * 0.1), c + Vector2(-s * 0.02, s * 0.1), c + Vector2(-s * 0.2, s), c + Vector2(s * 0.5, -s * 0.15), c + Vector2(s * 0.05, -s * 0.15)])
			draw_colored_polygon(bolt, col)
		"reload":
			draw_arc(c, s * 0.8, -PI * 0.2, PI * 1.4, 24, col, 3.5, true)
			var tip := c + Vector2(s * 0.8, 0).rotated(-PI * 0.2)
			draw_polyline(PackedVector2Array([tip + Vector2(-7, -3), tip, tip + Vector2(2, -8)]), col, 3.0, true)
