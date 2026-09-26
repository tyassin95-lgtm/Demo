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


func _ready() -> void:
	set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	mouse_filter = Control.MOUSE_FILTER_IGNORE
	_font = UITheme.font(false)
	_font_bold = UITheme.font(true)
	_title_font = UITheme.title_font()
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
	_combo_label = _make_label(_title_font, 58, HORIZONTAL_ALIGNMENT_RIGHT)
	UITheme.place(_combo_label, Vector4(1, 0.5, 1, 0.5), Vector4(-330, -150, -30, -80))
	_combo_sub = _make_label(_font_bold, 24, HORIZONTAL_ALIGNMENT_RIGHT)
	UITheme.place(_combo_sub, Vector4(1, 0.5, 1, 0.5), Vector4(-330, -84, -30, -54))


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
	_od_flash += delta
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
	if player.state == Actor.State.DASH:
		sl = 1.0
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
		var c := CYAN.lerp(ORANGE, clampf(player.combo / 30.0, 0.0, 1.0))
		_combo_label.add_theme_color_override("font_color", c)
		_combo_label.pivot_offset = Vector2(300, 35)
		_combo_label.scale = Vector2.ONE * (1.0 + _combo_pop * 0.35)
		_combo_sub.text = _combo_rank(player.combo)
		_combo_sub.add_theme_color_override("font_color", c.lerp(Color.WHITE, 0.4))
	else:
		_combo_label.modulate.a = 0.0
		_combo_sub.modulate.a = 0.0
	queue_redraw()


func _combo_rank(n: int) -> String:
	if n >= 40:
		return "HITS · RIFTBREAKER!"
	if n >= 25:
		return "HITS · UNSTOPPABLE"
	if n >= 15:
		return "HITS · BLAZING"
	if n >= 8:
		return "HITS · SLICK"
	return "HITS"


func _draw() -> void:
	if player == null or not is_instance_valid(player):
		return
	_draw_bars()
	_draw_crosshair()
	_draw_enemy_bars()
	_draw_wave_info()
	if Settings.get_value("show_fps"):
		draw_string(_font, Vector2(size.x * 0.5 - 40, size.y - 12), "%d FPS" % Engine.get_frames_per_second(), HORIZONTAL_ALIGNMENT_LEFT, -1, 20, Color(1, 1, 1, 0.7))


func _draw_bar(pos: Vector2, w: float, h: float, frac: float, col: Color, ghost: float = -1.0) -> void:
	# Slanted bar with background, ghost (recent damage) and fill.
	var skew := h * 0.6
	var bg := PackedVector2Array([pos + Vector2(skew, 0), pos + Vector2(w + skew, 0), pos + Vector2(w, h), pos + Vector2(0, h)])
	draw_colored_polygon(bg, Color(0.02, 0.03, 0.06, 0.75))
	if ghost > frac:
		var gw := w * ghost
		draw_colored_polygon(PackedVector2Array([pos + Vector2(skew, 0), pos + Vector2(gw + skew, 0), pos + Vector2(gw, h), pos + Vector2(0, h)]), Color(1, 1, 1, 0.55))
	var fw := w * clampf(frac, 0.0, 1.0)
	if fw > 0.5:
		draw_colored_polygon(PackedVector2Array([pos + Vector2(skew, 0), pos + Vector2(fw + skew, 0), pos + Vector2(fw, h), pos + Vector2(0, h)]), col)
		draw_line(pos + Vector2(skew, 1), pos + Vector2(fw + skew, 1), col.lightened(0.5), 2.0)
	draw_polyline(PackedVector2Array([bg[0], bg[1], bg[2], bg[3], bg[0]]), Color(1, 1, 1, 0.25), 1.5)


func _draw_bars() -> void:
	var x := 28.0
	var y := 26.0
	var hp := player.health / player.max_health
	var hp_col := GREEN.lerp(RED, clampf((0.5 - hp) * 2.0, 0.0, 1.0))
	if hp < 0.3:
		hp_col = hp_col.lerp(Color.WHITE, 0.3 * (0.5 + 0.5 * sin(_low_hp_t * 10.0)))
	draw_string(_font_bold, Vector2(x, y + 18), "HP", HORIZONTAL_ALIGNMENT_LEFT, -1, 22, Color(1, 1, 1, 0.8))
	_draw_bar(Vector2(x + 36, y), 330, 22, _hp_display, hp_col, _hp_ghost)
	draw_string(_font_bold, Vector2(x + 382, y + 19), "%d" % ceili(player.health), HORIZONTAL_ALIGNMENT_LEFT, -1, 24, Color(1, 1, 1, 0.95))
	# Stamina.
	var st := player.stamina / Player.STAMINA_MAX
	var st_col := Color(0.35, 0.95, 1.0) if not player.exhausted else Color(1.0, 0.35, 0.3)
	draw_string(_font_bold, Vector2(x, y + 44), "SP", HORIZONTAL_ALIGNMENT_LEFT, -1, 18, Color(1, 1, 1, 0.7))
	_draw_bar(Vector2(x + 36, y + 31), 270, 11, st, st_col)
	# Overdrive.
	var od_col := ORANGE
	var od := player.overdrive / 100.0
	if player.overdrive_time > 0.0:
		od = player.overdrive_time / Player.OVERDRIVE_TIME
		od_col = Color(1.0, 0.8, 0.3)
	_draw_bar(Vector2(x + 36, y + 49), 220, 9, od, od_col)
	if player.overdrive >= 100.0 and player.overdrive_time <= 0.0:
		var a := 0.6 + 0.4 * sin(_od_flash * 7.0)
		draw_string(_font_bold, Vector2(x + 268, y + 60), "OVERDRIVE READY", HORIZONTAL_ALIGNMENT_LEFT, -1, 20, Color(ORANGE.r, ORANGE.g, ORANGE.b, a))
	elif player.overdrive_time > 0.0:
		draw_string(_font_bold, Vector2(x + 268, y + 60), "OVERDRIVE", HORIZONTAL_ALIGNMENT_LEFT, -1, 20, Color(1.0, 0.85, 0.4))


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
		var gap := 7.0 + w.spread_deg * player.weapons.spread_mult * 3.0
		if w.kind == WeaponDB.Kind.SHOTGUN:
			draw_arc(c, gap + 10.0, 0, TAU, 40, col, 2.0, true)
		elif w.kind == WeaponDB.Kind.BEAM and player.weapons.scoped:
			draw_line(c + Vector2(-size.x, 0), c + Vector2(-6, 0), Color(col.r, col.g, col.b, 0.5), 1.5)
			draw_line(c + Vector2(6, 0), c + Vector2(size.x, 0), Color(col.r, col.g, col.b, 0.5), 1.5)
			draw_line(c + Vector2(0, 6), c + Vector2(0, size.y), Color(col.r, col.g, col.b, 0.5), 1.5)
		for dir in [Vector2.LEFT, Vector2.RIGHT, Vector2.UP, Vector2.DOWN]:
			draw_line(c + dir * gap, c + dir * (gap + 11.0), Color(0, 0, 0, 0.5), 5.0)
			draw_line(c + dir * gap, c + dir * (gap + 11.0), col, 2.5)
		draw_circle(c, 2.0, col)
		# Ammo + reload arc.
		var ammo: int = player.weapons.ammo[player.weapons.index]
		var ammo_col := Color(1, 1, 1, 0.9) if ammo > w.mag_size * 0.25 else Color(1.0, 0.4, 0.3)
		draw_string(_font_bold, c + Vector2(34, 44), "%d" % ammo, HORIZONTAL_ALIGNMENT_LEFT, -1, 30, ammo_col)
		draw_string(_font, c + Vector2(34 + 18 * str(ammo).length(), 44), " / %d" % w.mag_size, HORIZONTAL_ALIGNMENT_LEFT, -1, 20, Color(1, 1, 1, 0.55))
		if player.weapons.reload_left > 0.0:
			var fr := 1.0 - player.weapons.reload_left / w.reload_time
			draw_arc(c, 26.0, -PI / 2.0, -PI / 2.0 + TAU * fr, 40, Color(w.color.r, w.color.g, w.color.b, 0.9), 4.0, true)
			draw_string(_font_bold, c + Vector2(-38, 60), "RELOAD", HORIZONTAL_ALIGNMENT_LEFT, -1, 20, w.color)
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
			if (e.kind == Enemy.Kind.GUNNER and e.ai == Enemy.AI.AIM) or e.ai == Enemy.AI.WINDUP:
				var warn := Color(1.0, 0.8, 0.2) if e.ai == Enemy.AI.AIM else Color(1.0, 0.3, 0.2)
				draw_string(_font_bold, sp + Vector2(-6, -8), "!", HORIZONTAL_ALIGNMENT_LEFT, -1, 34, warn)
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


func _draw_wave_info() -> void:
	if director == null:
		return
	var cx := size.x * 0.5
	var title := ""
	if director.training:
		title = "TRAINING"
	elif director.wave >= 0:
		title = "WAVE %d / %d" % [director.wave + 1, director.total_waves()]
	else:
		title = "STAND BY"
	draw_string(_font_bold, Vector2(cx - 200, 38), title, HORIZONTAL_ALIGNMENT_CENTER, 400, 28, Color(0.85, 0.95, 1.0))
	var sub := ""
	if director.state == "break" and director.wave >= -1:
		sub = "NEXT WAVE IN %d" % ceili(director.break_timer)
	elif not director.training:
		sub = "HOSTILES  %d" % director.enemies_remaining()
	draw_string(_font, Vector2(cx - 200, 64), sub, HORIZONTAL_ALIGNMENT_CENTER, 400, 22, Color(1.0, 0.6, 0.35) if director.state == "fighting" else Color(0.7, 0.9, 1.0))
	draw_string(_font_bold, Vector2(cx - 200, 90), "SCORE  %d" % director.score, HORIZONTAL_ALIGNMENT_CENTER, 400, 20, Color(1, 1, 1, 0.6))
