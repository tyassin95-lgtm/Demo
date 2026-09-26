class_name UITheme
extends RefCounted
## Builds the shared UI theme: slanted neon buttons, dark glass panels, styled sliders.

const CYAN := Color(0.3, 0.88, 1.0)
const ORANGE := Color(1.0, 0.55, 0.2)

static var _theme: Theme


## Sets anchors (0..1) and pixel offsets explicitly.
static func place(c: Control, anchors: Vector4, offsets: Vector4) -> void:
	c.anchor_left = anchors.x
	c.anchor_top = anchors.y
	c.anchor_right = anchors.z
	c.anchor_bottom = anchors.w
	c.offset_left = offsets.x
	c.offset_top = offsets.y
	c.offset_right = offsets.z
	c.offset_bottom = offsets.w


static func font(bold: bool = false) -> Font:
	return load("res://assets/fonts/Rajdhani-Bold.ttf" if bold else "res://assets/fonts/Rajdhani-SemiBold.ttf")


static func title_font() -> Font:
	var base: FontFile = load("res://assets/fonts/Orbitron.ttf")
	var fv := FontVariation.new()
	fv.base_font = base
	fv.variation_opentype = {"wght": 800}
	return fv


static func get_theme() -> Theme:
	if _theme:
		return _theme
	var t := Theme.new()
	t.default_font = font()
	t.default_font_size = 26
	var normal := _box(Color(0.03, 0.06, 0.1, 0.88), Color(CYAN.r, CYAN.g, CYAN.b, 0.45))
	var hover := _box(Color(0.06, 0.12, 0.18, 0.95), Color(CYAN.r, CYAN.g, CYAN.b, 0.95))
	var pressed := _box(Color(0.12, 0.35, 0.45, 0.95), Color(1, 1, 1, 0.95))
	var focus := _box(Color(0, 0, 0, 0), Color(1.0, 1.0, 1.0, 0.8))
	focus.draw_center = false
	var disabled := _box(Color(0.03, 0.04, 0.06, 0.6), Color(0.4, 0.45, 0.5, 0.3))
	for st in ["normal", "hover", "pressed", "focus", "disabled"]:
		var box: StyleBoxFlat = {"normal": normal, "hover": hover, "pressed": pressed, "focus": focus, "disabled": disabled}[st]
		t.set_stylebox(st, "Button", box)
	t.set_color("font_color", "Button", Color(0.88, 0.94, 1.0))
	t.set_color("font_hover_color", "Button", Color(1, 1, 1))
	t.set_color("font_pressed_color", "Button", Color(1, 1, 1))
	t.set_color("font_focus_color", "Button", Color(1, 1, 1))
	t.set_font_size("font_size", "Button", 30)
	t.set_font("font", "Button", font(true))
	var panel := StyleBoxFlat.new()
	panel.bg_color = Color(0.015, 0.025, 0.05, 0.93)
	panel.border_color = Color(CYAN.r, CYAN.g, CYAN.b, 0.35)
	panel.set_border_width_all(2)
	panel.set_corner_radius_all(6)
	panel.set_content_margin_all(26)
	panel.shadow_color = Color(0, 0, 0, 0.5)
	panel.shadow_size = 18
	t.set_stylebox("panel", "PanelContainer", panel)
	t.set_stylebox("panel", "Panel", panel)
	t.set_color("font_color", "Label", Color(0.86, 0.92, 1.0))
	# Sliders.
	var track := StyleBoxFlat.new()
	track.bg_color = Color(0.1, 0.14, 0.2)
	track.set_corner_radius_all(4)
	track.content_margin_top = 5
	track.content_margin_bottom = 5
	var fill := StyleBoxFlat.new()
	fill.bg_color = Color(CYAN.r, CYAN.g, CYAN.b, 0.85)
	fill.set_corner_radius_all(4)
	fill.content_margin_top = 5
	fill.content_margin_bottom = 5
	t.set_stylebox("slider", "HSlider", track)
	t.set_stylebox("grabber_area", "HSlider", fill)
	t.set_stylebox("grabber_area_highlight", "HSlider", fill)
	t.set_icon("grabber", "HSlider", _circle_tex(30, Color(1, 1, 1)))
	t.set_icon("grabber_highlight", "HSlider", _circle_tex(34, CYAN.lerp(Color.WHITE, 0.5)))
	# Check buttons.
	t.set_icon("checked", "CheckButton", _toggle_tex(true))
	t.set_icon("unchecked", "CheckButton", _toggle_tex(false))
	t.set_font_size("font_size", "CheckButton", 24)
	var empty := StyleBoxEmpty.new()
	for st in ["normal", "hover", "pressed", "focus", "hover_pressed"]:
		t.set_stylebox(st, "CheckButton", empty)
	t.set_color("font_color", "CheckButton", Color(0.86, 0.92, 1.0))
	# Scroll container.
	t.set_stylebox("panel", "ScrollContainer", StyleBoxEmpty.new())
	var sb := StyleBoxFlat.new()
	sb.bg_color = Color(0.1, 0.14, 0.2, 0.6)
	sb.set_corner_radius_all(4)
	var grab := StyleBoxFlat.new()
	grab.bg_color = Color(CYAN.r, CYAN.g, CYAN.b, 0.6)
	grab.set_corner_radius_all(4)
	t.set_stylebox("scroll", "VScrollBar", sb)
	t.set_stylebox("grabber", "VScrollBar", grab)
	t.set_stylebox("grabber_highlight", "VScrollBar", grab)
	t.set_stylebox("grabber_pressed", "VScrollBar", grab)
	_theme = t
	return t


static func _box(bg: Color, border: Color) -> StyleBoxFlat:
	var b := StyleBoxFlat.new()
	b.bg_color = bg
	b.border_color = border
	b.set_border_width_all(2)
	b.border_width_left = 4
	b.set_corner_radius_all(3)
	b.skew = Vector2(0.18, 0)
	b.content_margin_left = 30
	b.content_margin_right = 30
	b.content_margin_top = 10
	b.content_margin_bottom = 10
	return b


static func _circle_tex(size: int, c: Color) -> ImageTexture:
	var img := Image.create(size, size, false, Image.FORMAT_RGBA8)
	var r := size * 0.5
	for y in size:
		for x in size:
			var d := Vector2(x + 0.5 - r, y + 0.5 - r).length()
			var a := clampf(r - d, 0.0, 1.0)
			img.set_pixel(x, y, Color(c.r, c.g, c.b, a))
	return ImageTexture.create_from_image(img)


static func _toggle_tex(on: bool) -> ImageTexture:
	var w := 64
	var h := 32
	var img := Image.create(w, h, false, Image.FORMAT_RGBA8)
	var bg := Color(0.25, 0.8, 0.95) if on else Color(0.18, 0.22, 0.3)
	var knob_x := 46.0 if on else 18.0
	for y in h:
		for x in w:
			var p := Vector2(x + 0.5, y + 0.5)
			var cx := clampf(p.x, 16.0, 48.0)
			var dbg := p.distance_to(Vector2(cx, 16.0))
			var col := Color(0, 0, 0, 0)
			if dbg < 16.0:
				col = bg
				col.a = clampf(16.0 - dbg, 0.0, 1.0)
			var dk := p.distance_to(Vector2(knob_x, 16.0))
			if dk < 12.0:
				col = Color(1, 1, 1, 1).lerp(col, clampf(dk - 11.0, 0.0, 1.0))
			img.set_pixel(x, y, col)
	return ImageTexture.create_from_image(img)
