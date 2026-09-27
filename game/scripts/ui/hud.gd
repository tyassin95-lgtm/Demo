class_name HUD
extends Control
## In-game HUD: health / stamina / overdrive bars, crosshair with hit markers,
## ammo + reload, combo counter, wave info, score, enemy health bars, off-screen
## threat indicators, announcements, damage vignette, speed lines and FPS.

const CYAN := Color(0.3, 0.9, 1.0)
const ORANGE := Color(1.0, 0.55, 0.18)
const RED := Color(1.0, 0.25, 0.2)
const GREEN := Color(0.4, 1.0, 0.55)

var player: Player
var director: WaveDirector

var _font: Font
var _font_bold: Font
var _title_font: Font
var _vignette: ColorRect
var _vig_mat: ShaderMaterial
var _speed: ColorRect
var _speed_mat: ShaderMaterial
var _announce_title: Label
var _announce_sub: Label
var _combo_label: Label
var _combo_sub: Label
var _hp_display := 1.0
var _hp_ghost := 1.0
var _damage_flash := 0.0
var _low_hp_t := 0.0
var _combo_pop := 0.0
var _last_combo := 0
var _announce_tw: Tween
var _heartbeat_t := 0.0
var _last_hp := -1.0
var _od_flash := 0.0
var _speed_amount := 0.0
const TIPS := [
	"Flick the stick forward twice (or tap SPRINT) to sprint",
	"JUMP while pushing left/right = SIDE DODGE (20 SP)",
	"JUMP again mid-dodge to cancel its end lag, then dodge again",
	"During a jump, JUMP next to a wall to WALL JUMP (20 SP)",
	"Wall jumps bounce like a mirror: angle in = angle out",
	"Wall jump at the top edge of a wall to vault over it",
	"Sprinting in mid-air drops you faster: bunny hop!",
	"Knocked flying? Press JUMP to land on your feet",
	"Knocked down? Dodge to spring back up",
	"ATTACK while sprinting for a lunging DASH SLASH",
	"You run faster holding the blade than a gun",
	"CROUCH ducks under gunfire, but you can't attack",
	"Hold ATTACK and drag to aim while firing",
	"Jump pads launch you onto the towers and walkways",
	"Deal damage to fill OVERDRIVE, then tap the lightning button",
	"Watch for the red ! — enemies telegraph their attacks",
]
var _tip_t := 0.0
## Recent damage directions: [world_dir: Vector3, time_left: float]
var _dmg_dirs: Array = []
## Touch controls (the weapon slots live there on touch screens).
var controls: Control
var _italic: Font
## Kill feed entries: [text_left, weapon_name, weapon_color, victim, victim_color, time_left]
var _feed: Array = []


func _ready() -> void:
	set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	mouse_filter = Control.MOUSE_FILTER_IGNORE
	_font = UITheme.font(false)
	_font_bold = UITheme.font(true)
	_title_font = UITheme.title_font()
	_italic = UITheme.italic_font(true)
	_speed = ColorRect.new()
	_speed.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	_speed.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_speed_mat = ShaderMaterial.new()
	_speed_mat.shader = load("res://shaders/speed_lines.gdshader")
	_speed.material = _speed_mat
	add_child(_speed)
	_vignette = ColorRect.new()
	_vignette.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	_vignette.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_vig_mat = ShaderMaterial.new()
	_vig_mat.shader = load("res://shaders/vignette.gdshader")
	_vignette.material = _vig_mat
	add_child(_vignette)
	_announce_title = _make_label(_title_font, 64, HORIZONTAL_ALIGNMENT_CENTER)
	UITheme.place(_announce_title, Vector4(0.5, 0, 0.5, 0), Vector4(-500, 150, 500, 230))
	_announce_title.modulate.a = 0.0
	_announce_sub = _make_label(_font_bold, 28, HORIZONTAL_ALIGNMENT_CENTER)
	UITheme.place(_announce_sub, Vector4(0.5, 0, 0.5, 0), Vector4(-500, 228, 500, 268))
	_announce_sub.modulate.a = 0.0
	_combo_label = _make_label(_italic, 76, HORIZONTAL_ALIGNMENT_RIGHT)
	UITheme.place(_combo_label, Vector4(1, 0.5, 1, 0.5), Vector4(-330, -178, -40, -92))
	_combo_sub = _make_label(_italic, 30, HORIZONTAL_ALIGNMENT_RIGHT)
	UITheme.place(_combo_sub, Vector4(1, 0.5, 1, 0.5), Vector4(-360, -96, -40, -60))
	Game.actor_died.connect(_on_actor_died)


func bind_player(p: Player) -> void:
	player = p
	p.damaged.connect(_on_player_damaged)


func _on_player_damaged(_a: Actor, hit: HitInfo) -> void:
	if hit.source is Node3D and is_instance_valid(hit.source):
		var d: Vector3 = (hit.source as Node3D).global_position - player.global_position
		d.y = 0.0
		if d.length() > 0.1:
			_dmg_dirs.append([d.normalized(), 1.0])
			if _dmg_dirs.size() > 6:
				_dmg_dirs.pop_front()


func _on_actor_died(a: Node) -> void:
	if not (a is Enemy) or player == null or not is_instance_valid(player):
		return
	var e := a as Enemy
	var w: WeaponDB.Weapon = player.weapons.current()
	var killer := "YOU" if e.last_attacker == player or e.last_attacker == null else "ALLY"
	var victim: String = Enemy.Kind.keys()[e.kind]
	_feed.append([killer, w.short_name if w else "", w.color if w else CYAN, victim, e.style.get("glow", RED), 4.5])
	if _feed.size() > 5:
		_feed.pop_front()


func _make_label(f: Font, fs: int, align: HorizontalAlignment) -> Label:
	var l := Label.new()
	l.add_theme_font_override("font", f)
	l.add_theme_font_size_override("font_size", fs)
	l.add_theme_color_override("font_outline_color", Color(0.01, 0.02, 0.05, 0.9))
	l.add_theme_constant_override("outline_size", 10)
	l.horizontal_alignment = align
	l.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(l)
	return l


func announce(title: String, sub: String, color: Color) -> void:
	_announce_title.text = title
	_announce_sub.text = sub
	_announce_title.add_theme_color_override("font_color", color)
	_announce_sub.add_theme_color_override("font_color", Color(0.9, 0.95, 1.0))
	if _announce_tw and _announce_tw.is_valid():
		_announce_tw.kill()
	_announce_title.scale = Vector2(1.25, 1.25)
	_announce_title.pivot_offset = _announce_title.size * 0.5
	_announce_tw = create_tween().set_parallel(true)
	_announce_tw.tween_property(_announce_title, "modulate:a", 1.0, 0.15)
	_announce_tw.tween_property(_announce_title, "scale", Vector2.ONE, 0.25).set_trans(Tween.TRANS_BACK).set_ease(Tween.EASE_OUT)
	_announce_tw.tween_property(_announce_sub, "modulate:a", 1.0, 0.25).set_delay(0.1)
	_announce_tw.chain().tween_interval(2.0)
	_announce_tw.chain().tween_property(_announce_title, "modulate:a", 0.0, 0.4)
	_announce_tw.parallel().tween_property(_announce_sub, "modulate:a", 0.0, 0.4)


func _process(delta: float) -> void:
	if player == null or not is_instance_valid(player):
		return
	var hp := player.health / player.max_health
	if _last_hp >= 0.0 and player.health < _last_hp - 0.5:
		_damage_flash = clampf(_damage_flash + (_last_hp - player.health) / 30.0, 0.35, 1.0)
	_last_hp = player.health
	_hp_display = move_toward(_hp_display, hp, delta * 2.5)
	_hp_display = minf(_hp_display, hp) if hp < _hp_display else _hp_display
	_hp_ghost = move_toward(_hp_ghost, hp, delta * (0.35 if _hp_ghost > hp else 3.0))
	_damage_flash = move_toward(_damage_flash, 0.0, delta * 1.8)
	for d in _dmg_dirs:
		d[1] = float(d[1]) - delta * 0.9
	_dmg_dirs = _dmg_dirs.filter(func(d: Array) -> bool: return d[1] > 0.0)
	_od_flash += delta
	_tip_t += delta
	for f in _feed:
		f[5] = float(f[5]) - delta
	_feed = _feed.filter(func(f: Array) -> bool: return f[5] > 0.0)
	# Low health pulse + heartbeat.
	var low := hp < 0.3 and player.is_alive()
	_low_hp_t += delta
	var vig := _damage_flash * 0.8
	if low:
		vig = maxf(vig, 0.35 + 0.25 * sin(_low_hp_t * 6.0))
		_heartbeat_t -= delta
		if _heartbeat_t <= 0.0:
			_heartbeat_t = 0.9
			Audio.play("heartbeat", -4.0, 1.0, 0.0, 500)
	if player.overdrive_time > 0.0:
		_vig_mat.set_shader_parameter("color", Color(1.0, 0.45, 0.1, 1.0))
		vig = maxf(vig, 0.45 + 0.1 * sin(_low_hp_t * 8.0))
	else:
		_vig_mat.set_shader_parameter("color", Color(1.0, 0.08, 0.08, 1.0))
	_vig_mat.set_shader_parameter("amount", vig)
	# Speed lines.
	var spd := Vector3(player.velocity.x, 0, player.velocity.z).length()
	var sl := clampf((spd - 10.0) / 10.0, 0.0, 1.0)
	if player.state == Actor.State.DODGE and player.dodge_time < Player.DODGE_TIME:
		sl = 0.8
	_speed_amount = move_toward(_speed_amount, sl * 0.8, delta * 4.0)
	_speed_mat.set_shader_parameter("amount", _speed_amount)
	# Combo.
	if player.combo != _last_combo:
		if player.combo > _last_combo:
			_combo_pop = 1.0
		_last_combo = player.combo
	_combo_pop = move_toward(_combo_pop, 0.0, delta * 5.0)
	if player.combo >= 2:
		_combo_label.text = "%d" % player.combo
		_combo_label.modulate.a = clampf(player.combo_timer * 2.0, 0.0, 1.0)
		_combo_sub.modulate.a = _combo_label.modulate.a
		var c := Color(0.55, 0.85, 1.0).lerp(ORANGE, clampf(player.combo / 30.0, 0.0, 1.0))
		_combo_label.add_theme_color_override("font_color", c)
		_combo_label.pivot_offset = Vector2(270, 60)
		_combo_label.scale = Vector2.ONE * (1.0 + _combo_pop * 0.35)
		_combo_sub.text = _combo_rank(player.combo)
		_combo_sub.add_theme_color_override("font_color", c.lerp(Color.WHITE, 0.4))
	else:
		_combo_label.modulate.a = 0.0
		_combo_sub.modulate.a = 0.0
	queue_redraw()


func _combo_rank(n: int) -> String:
	if n >= 40:
		return "RIFTBREAKER!  COMBO"
	if n >= 25:
		return "UNSTOPPABLE  COMBO"
	if n >= 15:
		return "BLAZING  COMBO"
	if n >= 8:
		return "SLICK  COMBO"
	return "COMBO"


func _draw() -> void:
	if player == null or not is_instance_valid(player):
		return
	_draw_damage_dirs()
	_draw_crosshair()
	_draw_enemy_bars()
	_draw_gauges()
	_draw_radar()
	_draw_scoreboard()
	_draw_killfeed()
	if not _touch_layout():
		_draw_weapon_row()
	if director and director.training:
		_draw_tip()
	if Settings.get_value("show_fps"):
		draw_string(_font, Vector2(24, 198), "%d FPS" % Engine.get_frames_per_second(), HORIZONTAL_ALIGNMENT_LEFT, -1, 20, Color(1, 1, 1, 0.7))


## Text with a dark outline so it stays readable over bright scenery.
func _txt(f: Font, pos: Vector2, text: String, align: HorizontalAlignment, width: float, fs: int, col: Color) -> void:
	draw_string_outline(f, pos, text, align, width, fs, maxi(4, fs / 4), Color(0.01, 0.02, 0.05, 0.7 * col.a))
	draw_string(f, pos, text, align, width, fs, col)


func _touch_layout() -> bool:
	return controls != null and controls.visible


func _draw_damage_dirs() -> void:
	if player.cam == null:
		return
	var c := size * 0.5
	var yaw := player.cam.yaw
	var fwd := Vector3(-sin(yaw), 0, -cos(yaw))
	var right := Vector3(cos(yaw), 0, -sin(yaw))
	for d in _dmg_dirs:
		var v: Vector3 = d[0]
		var a := atan2(v.dot(right), v.dot(fwd))
		var alpha: float = d[1]
		var ang := a - PI / 2.0
		var r := minf(size.x, size.y) * 0.36
		draw_arc(c, r, ang - 0.32, ang + 0.32, 20, Color(1.0, 0.2, 0.15, 0.75 * alpha), 10.0, true)
		draw_arc(c, r - 9.0, ang - 0.2, ang + 0.2, 16, Color(1.0, 0.5, 0.4, 0.5 * alpha), 4.0, true)


# --- Bottom-centre gauges (arched HP and SP bars, hex badges) -------------------

const GAUGE_R := 700.0
const GAUGE_HALF := 0.25


## Filled band between two radii of a circle, from angle a0 to a1 (0 = straight up).
func _arc_band(c: Vector2, r0: float, r1: float, a0: float, a1: float, col: Color) -> void:
	if a1 - a0 <= 0.0005:
		return
	var n := maxi(3, int((a1 - a0) / 0.012))
	var pts := PackedVector2Array()
	for i in n + 1:
		var a := lerpf(a0, a1, float(i) / n)
		pts.append(c + Vector2(sin(a), -cos(a)) * r1)
	for i in n + 1:
		var a := lerpf(a1, a0, float(i) / n)
		pts.append(c + Vector2(sin(a), -cos(a)) * r0)
	draw_colored_polygon(pts, col)


func _arc_line(c: Vector2, r: float, a0: float, a1: float, col: Color, w: float) -> void:
	draw_arc(c, r, a0 - PI / 2.0, a1 - PI / 2.0, 48, col, w, true)


func _hex(c: Vector2, r: float) -> PackedVector2Array:
	var pts := PackedVector2Array()
	for i in 6:
		var a := PI / 3.0 * i
		pts.append(c + Vector2(cos(a), sin(a)) * r)
	return pts


## Hexagon badge with an optional bottom-up fill (0..1).
func _draw_hex(c: Vector2, r: float, fill: float, col: Color, glow: float = 0.0) -> void:
	var hex := _hex(c, r)
	draw_colored_polygon(hex, Color(0.02, 0.04, 0.08, 0.72))
	if fill > 0.001:
		var h := r * 2.0 * clampf(fill, 0.0, 1.0)
		var clip := PackedVector2Array([c + Vector2(-r - 2, r - h), c + Vector2(r + 2, r - h), c + Vector2(r + 2, r + 2), c + Vector2(-r - 2, r + 2)])
		for poly in Geometry2D.intersect_polygons(hex, clip):
			draw_colored_polygon(poly, Color(col.r, col.g, col.b, 0.35 + glow * 0.3))
	var outline := hex.duplicate()
	outline.append(hex[0])
	draw_polyline(outline, Color(col.r, col.g, col.b, 0.9), 2.5, true)
	if glow > 0.0:
		var big := _hex(c, r + 5.0)
		big.append(big[0])
		draw_polyline(big, Color(col.r, col.g, col.b, glow * 0.6), 2.0, true)


func _draw_gauges() -> void:
	var touch := _touch_layout()
	var cx := size.x * 0.5
	var base := size.y - 16.0
	var c := Vector2(cx, base - 58.0 + GAUGE_R)
	# Narrower on touch screens so it sits between the stick and the buttons.
	var half := GAUGE_HALF * (0.88 if touch else 1.0)
	var a0 := -half
	var a1 := half
	var span := a1 - a0
	# Plate behind the gauges.
	_arc_band(c, GAUGE_R - 30.0, GAUGE_R + 26.0, a0 - 0.012, a1 + 0.012, Color(0.02, 0.04, 0.08, 0.5))
	_arc_line(c, GAUGE_R + 26.0, a0 - 0.012, a1 + 0.012, Color(0.45, 0.8, 1.0, 0.55), 2.0)
	# HP (thick, yellow like a sports scoreboard; turns red when low).
	var hp := player.health / player.max_health
	var hp_col := Color(1.0, 0.82, 0.25).lerp(RED, clampf((0.45 - hp) * 2.5, 0.0, 1.0))
	if hp < 0.3:
		hp_col = hp_col.lerp(Color.WHITE, 0.3 * (0.5 + 0.5 * sin(_low_hp_t * 10.0)))
	_arc_band(c, GAUGE_R + 2.0, GAUGE_R + 20.0, a0, a1, Color(0.0, 0.0, 0.0, 0.45))
	if _hp_ghost > _hp_display:
		_arc_band(c, GAUGE_R + 2.0, GAUGE_R + 20.0, a0, a0 + span * _hp_ghost, Color(1, 1, 1, 0.6))
	_arc_band(c, GAUGE_R + 2.0, GAUGE_R + 20.0, a0, a0 + span * clampf(_hp_display, 0.0, 1.0), hp_col)
	_arc_line(c, GAUGE_R + 18.0, a0, a0 + span * clampf(_hp_display, 0.0, 1.0), hp_col.lightened(0.55), 2.0)
	# SP (thin, blue) under it.
	var st := player.stamina / Player.STAMINA_MAX
	var st_col := Color(0.3, 0.7, 1.0) if not player.exhausted else Color(1.0, 0.35, 0.3)
	_arc_band(c, GAUGE_R - 10.0, GAUGE_R - 3.0, a0, a1, Color(0.0, 0.0, 0.0, 0.45))
	_arc_band(c, GAUGE_R - 10.0, GAUGE_R - 3.0, a0, a0 + span * clampf(st, 0.0, 1.0), st_col)
	var lab := c + Vector2(sin(a0), -cos(a0)) * (GAUGE_R + 8.0)
	_txt(_italic, lab + Vector2(6, -18), "HP", HORIZONTAL_ALIGNMENT_LEFT, -1, 18, Color(1, 1, 1, 0.85))
	var lab2 := c + Vector2(sin(a1), -cos(a1)) * (GAUGE_R + 8.0)
	_txt(_italic, lab2 + Vector2(-26, -18), "SP", HORIZONTAL_ALIGNMENT_LEFT, -1, 18, Color(0.6, 0.85, 1.0, 0.85))
	# Numbers.
	var num := "%d / %d" % [ceili(player.health), int(player.max_health)]
	_txt(_italic, Vector2(cx - 150, base), num, HORIZONTAL_ALIGNMENT_CENTER, 300, 26, Color(1, 1, 1, 0.95))
	if touch:
		return
	# Overdrive hex (left) and weapon/ammo hex (right).
	var hx := GAUGE_R * sin(half) + 64.0
	var od_c := Vector2(cx - hx, base - 40.0)
	var od := player.overdrive / 100.0
	var od_col := ORANGE
	var ready := player.overdrive >= 100.0 and player.overdrive_time <= 0.0
	if player.overdrive_time > 0.0:
		od = player.overdrive_time / Player.OVERDRIVE_TIME
		od_col = Color(1.0, 0.8, 0.3)
	_draw_hex(od_c, 36.0, od, od_col, (0.6 + 0.4 * sin(_od_flash * 7.0)) if ready else 0.0)
	_txt(_italic, od_c + Vector2(-30, 7), "OD", HORIZONTAL_ALIGNMENT_CENTER, 60, 22, Color(1, 1, 1, 0.95 if ready or player.overdrive_time > 0.0 else 0.6))
	if ready:
		_txt(_font_bold, od_c + Vector2(-60, -44), "READY", HORIZONTAL_ALIGNMENT_CENTER, 120, 18, Color(ORANGE.r, ORANGE.g, ORANGE.b, 0.6 + 0.4 * sin(_od_flash * 7.0)))
	var w: WeaponDB.Weapon = player.weapons.current()
	if w:
		var wc := Vector2(cx + hx, base - 40.0)
		var reload := player.weapons.reload_left > 0.0
		var ammo_frac := 1.0
		var ammo_text := "∞"
		if w.kind != WeaponDB.Kind.MELEE:
			var ammo: int = player.weapons.ammo[player.weapons.index]
			ammo_frac = float(ammo) / float(maxi(w.mag_size, 1))
			ammo_text = "%03d" % ammo
			if reload:
				ammo_frac = 1.0 - player.weapons.reload_left / w.reload_time
		_draw_hex(wc, 36.0, ammo_frac, w.color)
		var low := w.kind != WeaponDB.Kind.MELEE and ammo_frac < 0.25 and not reload
		_txt(_italic, wc + Vector2(-34, 8), ammo_text, HORIZONTAL_ALIGNMENT_CENTER, 68, 24 if ammo_text != "∞" else 30, Color(1.0, 0.4, 0.3) if low else Color(1, 1, 1, 0.95))
		_txt(_font_bold, wc + Vector2(-60, -44), "RELOAD" if reload else w.short_name, HORIZONTAL_ALIGNMENT_CENTER, 120, 18, Color(w.color.r, w.color.g, w.color.b, 0.95))


## Weapon slots above the gauges (keyboard/gamepad layout; touch screens have tappable slots).
func _draw_weapon_row() -> void:
	var n := mini(4, player.weapons.loadout.size())
	var w := 104.0
	var h := 30.0
	var gap := 8.0
	var x0 := size.x * 0.5 - (n * w + (n - 1) * gap) * 0.5
	var y := size.y - 150.0
	for i in n:
		var ww: WeaponDB.Weapon = player.weapons.loadout[i]
		var sel := i == player.weapons.index
		var p := Vector2(x0 + i * (w + gap), y)
		var sk := 8.0
		var poly := PackedVector2Array([p + Vector2(sk, 0), p + Vector2(w + sk, 0), p + Vector2(w, h), p + Vector2(0, h)])
		draw_colored_polygon(poly, Color(0.02, 0.04, 0.08, 0.75 if sel else 0.45))
		var col := ww.color
		var outline := poly.duplicate()
		outline.append(poly[0])
		draw_polyline(outline, Color(col.r, col.g, col.b, 1.0 if sel else 0.35), 2.5 if sel else 1.5, true)
		_txt(_italic, p + Vector2(8, 22), "%d %s" % [i + 1, ww.short_name], HORIZONTAL_ALIGNMENT_CENTER, w, 18, Color(1, 1, 1, 1.0 if sel else 0.55))


# --- Radar (top left) --------------------------------------------------------

const RADAR_R := 70.0
const RADAR_RANGE := 30.0


func _radar_point(c: Vector2, d: Vector3, right: Vector3, fwd: Vector3) -> Vector2:
	return c + Vector2(d.dot(right), -d.dot(fwd)) * (RADAR_R / RADAR_RANGE)


func _draw_radar() -> void:
	if player.cam == null:
		return
	var c := Vector2(24.0 + RADAR_R, 24.0 + RADAR_R)
	var yaw := player.cam.yaw
	var fwd := Vector3(-sin(yaw), 0, -cos(yaw))
	var right := Vector3(cos(yaw), 0, -sin(yaw))
	draw_circle(c, RADAR_R, Color(0.02, 0.05, 0.1, 0.55))
	draw_arc(c, RADAR_R * 0.5, 0, TAU, 40, Color(0.45, 0.8, 1.0, 0.18), 1.0, true)
	draw_line(c + Vector2(-RADAR_R, 0), c + Vector2(RADAR_R, 0), Color(0.45, 0.8, 1.0, 0.12), 1.0)
	draw_line(c + Vector2(0, -RADAR_R), c + Vector2(0, RADAR_R), Color(0.45, 0.8, 1.0, 0.12), 1.0)
	# View cone.
	var cone := PackedVector2Array([c, c + Vector2(-0.55, -1.0) * RADAR_R * 0.8, c + Vector2(0.55, -1.0) * RADAR_R * 0.8])
	draw_colored_polygon(cone, Color(0.5, 0.85, 1.0, 0.1))
	# Arena edge (the deck is a square).
	var pp := player.global_position
	var half := ArenaBuilder.HALF
	var corners := [Vector3(-half, 0, -half), Vector3(half, 0, -half), Vector3(half, 0, half), Vector3(-half, 0, half)]
	for i in 4:
		var e0: Vector3 = corners[i] - pp
		var e1: Vector3 = corners[(i + 1) % 4] - pp
		var prev := _radar_point(c, e0, right, fwd)
		for k in range(1, 25):
			var cur := _radar_point(c, e0.lerp(e1, k / 24.0), right, fwd)
			if prev.distance_to(c) < RADAR_R - 2.0 and cur.distance_to(c) < RADAR_R - 2.0:
				draw_line(prev, cur, Color(0.6, 0.85, 1.0, 0.5), 2.0)
			prev = cur
	# Enemies.
	for a in Game.actors:
		if not is_instance_valid(a) or not (a is Enemy) or not (a as Actor).is_alive():
			continue
		var e := a as Enemy
		var q := _radar_point(c, e.global_position - pp, right, fwd)
		var off := q - c
		var col: Color = e.style.get("glow", RED)
		if off.length() > RADAR_R - 5.0:
			q = c + off.normalized() * (RADAR_R - 5.0)
			draw_circle(q, 3.0, Color(col.r, col.g, col.b, 0.6))
		else:
			draw_circle(q, 5.5 if e.kind == Enemy.Kind.BRUTE else 4.5, Color(0, 0, 0, 0.6))
			draw_circle(q, 4.0 if e.kind == Enemy.Kind.BRUTE else 3.2, col)
	# Player arrow.
	draw_colored_polygon(PackedVector2Array([c + Vector2(0, -9), c + Vector2(6, 6), c + Vector2(0, 3), c + Vector2(-6, 6)]), Color(0.4, 0.9, 1.0))
	draw_arc(c, RADAR_R, 0, TAU, 64, Color(0.45, 0.8, 1.0, 0.7), 2.5, true)


# --- Kill feed (top right) -----------------------------------------------------

func _draw_killfeed() -> void:
	# Top right on PC; under the radar on touch screens (weapon slots own the top right).
	var touch := _touch_layout()
	var y := 196.0 if touch else 40.0
	for i in _feed.size():
		var f: Array = _feed[_feed.size() - 1 - i]
		var a := clampf(float(f[5]) / 0.5, 0.0, 1.0)
		var victim: String = f[3]
		var wname: String = "[" + String(f[1]) + "]"
		var vw := _font_bold.get_string_size(victim, HORIZONTAL_ALIGNMENT_LEFT, -1, 20).x
		var ww := _font_bold.get_string_size(wname, HORIZONTAL_ALIGNMENT_LEFT, -1, 16).x
		var kw := _font_bold.get_string_size(String(f[0]), HORIZONTAL_ALIGNMENT_LEFT, -1, 20).x
		var total := kw + ww + vw + 28.0
		var x := 24.0 + total if touch else size.x - 24.0
		draw_rect(Rect2(Vector2(x - total - 10, y - 20), Vector2(total + 14, 28)), Color(0.02, 0.04, 0.08, 0.5 * a))
		var vc: Color = f[4]
		var wc: Color = f[2]
		_txt(_font_bold, Vector2(x - vw, y), victim, HORIZONTAL_ALIGNMENT_LEFT, -1, 20, Color(vc.r, vc.g, vc.b, a))
		_txt(_font_bold, Vector2(x - vw - ww - 12, y - 1), wname, HORIZONTAL_ALIGNMENT_LEFT, -1, 16, Color(wc.r, wc.g, wc.b, a))
		_txt(_font_bold, Vector2(x - total + 4, y), String(f[0]), HORIZONTAL_ALIGNMENT_LEFT, -1, 20, Color(0.45, 0.8, 1.0, a))
		y += 32.0


func _draw_crosshair() -> void:
	var c := size * 0.5
	var w: WeaponDB.Weapon = player.weapons.current()
	var cam := player.cam
	var col := Color(1, 1, 1, 0.9)
	if w == null:
		return
	if w.kind == WeaponDB.Kind.MELEE:
		draw_arc(c, 5.0, 0, TAU, 16, Color(1, 1, 1, 0.55), 2.0, true)
	else:
		var assist: bool = player.weapons.assist_target != null and player.weapons.assist_strength > 0.05
		if assist:
			col = Color(1.0, 0.45, 0.35, 0.95)
		var gap := 9.0 + w.spread_deg * player.weapons.spread_mult * 3.0
		if w.kind == WeaponDB.Kind.SHOTGUN:
			draw_arc(c, gap + 10.0, 0, TAU, 40, Color(col.r, col.g, col.b, 0.6), 1.5, true)
		elif w.kind == WeaponDB.Kind.BEAM and player.weapons.scoped:
			draw_line(c + Vector2(-size.x, 0), c + Vector2(-6, 0), Color(col.r, col.g, col.b, 0.5), 1.5)
			draw_line(c + Vector2(6, 0), c + Vector2(size.x, 0), Color(col.r, col.g, col.b, 0.5), 1.5)
			draw_line(c + Vector2(0, 6), c + Vector2(0, size.y), Color(col.r, col.g, col.b, 0.5), 1.5)
		# Four dots around a centre dot (sport-shooter style), spreading with inaccuracy.
		for dir in [Vector2.LEFT, Vector2.RIGHT, Vector2.UP, Vector2.DOWN]:
			draw_circle(c + dir * gap, 3.6, Color(0, 0, 0, 0.55))
			draw_circle(c + dir * gap, 2.4, col)
		draw_circle(c, 2.6, Color(0, 0, 0, 0.5))
		draw_circle(c, 1.6, col)
		if player.weapons.reload_left > 0.0:
			var fr := 1.0 - player.weapons.reload_left / w.reload_time
			draw_arc(c, 26.0, -PI / 2.0, -PI / 2.0 + TAU * fr, 40, Color(w.color.r, w.color.g, w.color.b, 0.9), 4.0, true)
			_txt(_font_bold, c + Vector2(-38, 60), "RELOAD", HORIZONTAL_ALIGNMENT_LEFT, -1, 20, w.color)
		if player.weapons.secondary_cd > 0.0 and w.secondary == WeaponDB.Secondary.GRENADE:
			var fr2 := 1.0 - player.weapons.secondary_cd / w.secondary_cooldown
			draw_arc(c, 34.0, -PI / 2.0, -PI / 2.0 + TAU * fr2, 40, Color(1, 1, 1, 0.3), 2.0, true)
	# Hit marker.
	if cam and cam.hitmarker_time > 0.0:
		var hc := Color(1.0, 0.3, 0.25) if cam.hitmarker_kill else Color(1, 1, 1)
		var s := 8.0 + (1.0 - cam.hitmarker_time / 0.35) * 6.0
		for d in [Vector2(1, 1), Vector2(-1, 1), Vector2(1, -1), Vector2(-1, -1)]:
			draw_line(c + d * s, c + d * (s + 9.0), hc, 3.0)


func _draw_enemy_bars() -> void:
	var cam3d: Camera3D = get_viewport().get_camera_3d()
	if cam3d == null or size.x < 100.0 or size.y < 100.0:
		return
	var screen_rect := Rect2(Vector2.ZERO, size)
	var center := size * 0.5
	for a in Game.actors:
		if not is_instance_valid(a) or a == player or not (a is Enemy):
			continue
		var e := a as Enemy
		if not e.is_alive() or e.state == Actor.State.SPAWNING:
			continue
		var head: Vector3 = e.global_position + Vector3.UP * (2.25 * e.visual_scale)
		var behind := cam3d.is_position_behind(head)
		var sp := cam3d.unproject_position(head)
		var col: Color = e.style.get("glow", RED)
		if not behind and screen_rect.grow(-10.0).has_point(sp):
			var dist := cam3d.global_position.distance_to(head)
			if dist > 45.0:
				continue
			var w := clampf(90.0 - dist * 1.2, 44.0, 90.0) * (1.4 if e.kind == Enemy.Kind.BRUTE else 1.0)
			var fr := e.health / e.max_health
			var p := sp - Vector2(w * 0.5, 0)
			draw_rect(Rect2(p - Vector2(1, 1), Vector2(w + 2, 8)), Color(0, 0, 0, 0.6))
			draw_rect(Rect2(p, Vector2(w * fr, 6)), col)
			# Name tag in the rival team colour.
			if dist < 28.0:
				var tag: String = Enemy.Kind.keys()[e.kind]
				_txt(_font_bold, p + Vector2(-40, -5), tag, HORIZONTAL_ALIGNMENT_CENTER, w + 80, 16, Color(1.0, 0.45, 0.4, 0.9))
			if (e.kind == Enemy.Kind.GUNNER and e.ai == Enemy.AI.AIM) or e.ai == Enemy.AI.WINDUP:
				var warn := Color(1.0, 0.8, 0.2) if e.ai == Enemy.AI.AIM else Color(1.0, 0.3, 0.2)
				_txt(_font_bold, sp + Vector2(-6, -24), "!", HORIZONTAL_ALIGNMENT_LEFT, -1, 34, warn)
		else:
			# Off-screen indicator on an ellipse around the screen center.
			var dir3 := e.global_position - cam3d.global_position
			var local := cam3d.global_basis.inverse() * dir3
			var d2 := Vector2(local.x, -local.y)
			if local.z > 0.0 and d2.length() < 0.01:
				d2 = Vector2(0, 1)
			d2 = d2.normalized()
			var edge := center + Vector2(d2.x * (size.x * 0.5 - 60.0), d2.y * (size.y * 0.5 - 60.0))
			var threat := (e.kind == Enemy.Kind.GUNNER and e.ai == Enemy.AI.AIM) or e.ai == Enemy.AI.WINDUP
			var ic := Color(1.0, 0.8, 0.2) if threat else col
			var ang := d2.angle()
			var tri := PackedVector2Array([edge + Vector2(16, 0).rotated(ang), edge + Vector2(-8, 10).rotated(ang), edge + Vector2(-8, -10).rotated(ang)])
			draw_colored_polygon(tri, Color(ic.r, ic.g, ic.b, 0.85))


func _draw_tip() -> void:
	var idx := int(_tip_t / 6.0) % TIPS.size()
	var phase := fmod(_tip_t, 6.0)
	var a := clampf(minf(phase / 0.4, (6.0 - phase) / 0.4), 0.0, 1.0)
	var w := 760.0
	var pos := Vector2(size.x * 0.5 - w * 0.5, size.y - 172.0)
	draw_rect(Rect2(pos - Vector2(0, 30), Vector2(w, 42)), Color(0.02, 0.03, 0.06, 0.55 * a))
	_txt(_font_bold, pos, "TIP  ·  " + TIPS[idx], HORIZONTAL_ALIGNMENT_CENTER, w, 24, Color(0.75, 0.95, 1.0, a))


## Top-centre plate: wave label, match clock, KOs (blue) and hostiles left (red).
func _draw_scoreboard() -> void:
	if director == null:
		return
	var cx := size.x * 0.5
	var top := 10.0
	var plate := PackedVector2Array([Vector2(cx - 150, top), Vector2(cx + 150, top), Vector2(cx + 128, top + 62), Vector2(cx - 128, top + 62)])
	draw_colored_polygon(plate, Color(0.02, 0.04, 0.08, 0.62))
	var outline := plate.duplicate()
	outline.append(plate[0])
	draw_polyline(outline, Color(0.45, 0.8, 1.0, 0.45), 1.5, true)
	var title := ""
	if director.training:
		title = "TRAINING"
	elif director.wave >= 0:
		title = "WAVE %d / %d" % [director.wave + 1, director.total_waves()]
	else:
		title = "STAND BY"
	_txt(_italic, Vector2(cx - 100, top + 21), title, HORIZONTAL_ALIGNMENT_CENTER, 200, 17, Color(0.85, 0.95, 1.0, 0.9))
	var t := int(director.elapsed)
	_txt(_italic, Vector2(cx - 100, top + 54), "%02d:%02d" % [t / 60, t % 60], HORIZONTAL_ALIGNMENT_CENTER, 200, 32, Color(1, 1, 1))
	# Side boxes (slanted), blue = KOs, red = hostiles remaining.
	var blue := Color(0.2, 0.55, 1.0)
	var red := Color(1.0, 0.25, 0.22)
	var lb := PackedVector2Array([Vector2(cx - 236, top + 8), Vector2(cx - 146, top + 8), Vector2(cx - 160, top + 54), Vector2(cx - 250, top + 54)])
	var rb := PackedVector2Array([Vector2(cx + 146, top + 8), Vector2(cx + 236, top + 8), Vector2(cx + 250, top + 54), Vector2(cx + 160, top + 54)])
	draw_colored_polygon(lb, Color(0.02, 0.05, 0.14, 0.7))
	draw_colored_polygon(rb, Color(0.14, 0.03, 0.04, 0.7))
	draw_colored_polygon(lb, Color(blue.r, blue.g, blue.b, 0.22))
	draw_colored_polygon(rb, Color(red.r, red.g, red.b, 0.22))
	draw_line(lb[3], lb[2], blue, 3.0)
	draw_line(rb[3], rb[2], red, 3.0)
	_txt(_italic, Vector2(cx - 246, top + 44), "%d" % director.kills, HORIZONTAL_ALIGNMENT_CENTER, 90, 30, Color(0.75, 0.9, 1.0))
	_txt(_font_bold, Vector2(cx - 246, top + 72), "KO", HORIZONTAL_ALIGNMENT_CENTER, 90, 15, Color(0.6, 0.8, 1.0, 0.8))
	var left_n := director.enemies_remaining() if not director.training else 0
	_txt(_italic, Vector2(cx + 156, top + 44), "%d" % left_n if not director.training else "-", HORIZONTAL_ALIGNMENT_CENTER, 90, 30, Color(1.0, 0.75, 0.7))
	_txt(_font_bold, Vector2(cx + 156, top + 72), "HOSTILES", HORIZONTAL_ALIGNMENT_CENTER, 90, 15, Color(1.0, 0.6, 0.55, 0.8))
	var sub := "SCORE  %d" % director.score
	var sub_col := Color(1, 1, 1, 0.7)
	if director.state == "break" and director.wave >= -1:
		sub = "NEXT WAVE IN %d" % ceili(director.break_timer)
		sub_col = Color(0.7, 0.9, 1.0)
	_txt(_font_bold, Vector2(cx - 150, top + 86), sub, HORIZONTAL_ALIGNMENT_CENTER, 300, 19, sub_col)
