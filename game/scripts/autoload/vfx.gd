extends Node
## Visual effects spawner. Frequently used effects are pooled per scene so combat
## never instantiates particle systems mid-fight (avoids hitches on mobile).

const TEX_DIR := "res://assets/vfx/"
const STREAK_SHADER := preload("res://shaders/particle_streak.gdshader")
const SLASH_SHADER := preload("res://shaders/slash.gdshader")
const PILLAR_SHADER := preload("res://shaders/pillar.gdshader")

const POOL_SIZES := {"sparks": 10, "flash": 10, "tracer": 18, "number": 16, "muzzle": 6, "slash": 6, "ring": 8}

var quality := 1
var _tex := {}
var _pool_root: Node3D
var _pools := {}
var _pool_idx := {}
var _font: Font


func _ready() -> void:
	for n in ["circle_05", "flare_01", "light_01", "light_03", "magic_05", "muzzle_01", "muzzle_02", "muzzle_04", "scorch_02", "slash_02", "slash_03", "smoke_04", "smoke_07", "spark_01", "spark_02", "spark_04", "spark_05", "star_04", "star_06", "trace_02", "twirl_01", "dirt_02"]:
		_tex[n] = load(TEX_DIR + n + ".png")
	_font = load("res://assets/fonts/Rajdhani-Bold.ttf")


# --- Pool management ---------------------------------------------------------------

func _ensure_pools() -> bool:
	if is_instance_valid(_pool_root) and _pool_root.is_inside_tree():
		return true
	var scene := get_tree().current_scene
	if scene == null or not (scene is Node3D):
		return false
	_pool_root = Node3D.new()
	_pool_root.name = "VFXPool"
	scene.add_child(_pool_root)
	_pools.clear()
	_pool_idx.clear()
	for key in POOL_SIZES:
		var arr := []
		for i in POOL_SIZES[key]:
			var n: Node3D = call("_make_" + key)
			n.visible = false
			_pool_root.add_child(n)
			arr.append(n)
		_pools[key] = arr
		_pool_idx[key] = 0
	return true


func _next(key: String) -> Node3D:
	if not _ensure_pools():
		return null
	var arr: Array = _pools[key]
	var i: int = _pool_idx[key]
	_pool_idx[key] = (i + 1) % arr.size()
	var n: Node3D = arr[i]
	if n.has_meta("tween"):
		var tw: Tween = n.get_meta("tween")
		if tw and tw.is_valid():
			tw.kill()
	n.visible = true
	return n


## Pre-builds pools and draws every effect once off-screen so shaders compile early.
func warmup(at: Vector3) -> void:
	if not _ensure_pools():
		return
	sparks(at, Vector3.UP, Color.WHITE, 1.0)
	hit_spark(at, Vector3.UP, Color.WHITE, 1.0)
	tracer(at, at + Vector3.UP, Color.WHITE, 0.05, 0.05)
	muzzle_flash(at, Vector3.FORWARD, Color.WHITE, 1.0)
	slash(Transform3D(Basis(), at), Color.WHITE, 1.0, 0.0, false)
	damage_number(at, 1.0, Color.WHITE, false)
	shockwave(at, 1.0, Color.WHITE)
	explosion(at, 1.0, Color.WHITE, false)


func _add_to_scene(n: Node) -> void:
	var scene := get_tree().current_scene
	if scene:
		scene.add_child(n)


func _unshaded_add(tex: Texture2D, billboard: bool = true) -> StandardMaterial3D:
	var m := StandardMaterial3D.new()
	m.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	m.blend_mode = BaseMaterial3D.BLEND_MODE_ADD
	m.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	m.cull_mode = BaseMaterial3D.CULL_DISABLED
	m.no_depth_test = false
	m.disable_receive_shadows = true
	m.albedo_texture = tex
	m.vertex_color_use_as_albedo = true
	if billboard:
		m.billboard_mode = BaseMaterial3D.BILLBOARD_ENABLED
	return m


func _particle_mat(tex: Texture2D) -> StandardMaterial3D:
	var m := _unshaded_add(tex, false)
	m.billboard_mode = BaseMaterial3D.BILLBOARD_PARTICLES
	m.billboard_keep_scale = true
	return m


static func _ramp(stops: Array) -> GradientTexture1D:
	var g := Gradient.new()
	g.offsets = PackedFloat32Array()
	g.colors = PackedColorArray()
	for s in stops:
		g.add_point(s[0], s[1])
	g.remove_point(0)
	g.remove_point(0)
	var t := GradientTexture1D.new()
	t.gradient = g
	return t


# --- Pooled builders ----------------------------------------------------------------

func _make_sparks() -> Node3D:
	var p := GPUParticles3D.new()
	p.amount = 18
	p.one_shot = true
	p.explosiveness = 1.0
	p.lifetime = 0.4
	p.emitting = false
	p.local_coords = false
	p.visibility_aabb = AABB(Vector3(-4, -4, -4), Vector3(8, 8, 8))
	var pm := ParticleProcessMaterial.new()
	pm.direction = Vector3(0, 0, -1)
	pm.spread = 60.0
	pm.initial_velocity_min = 5.0
	pm.initial_velocity_max = 14.0
	pm.gravity = Vector3(0, -14, 0)
	pm.damping_min = 3.0
	pm.damping_max = 6.0
	pm.scale_min = 0.6
	pm.scale_max = 1.2
	pm.particle_flag_align_y = true
	var curve := CurveTexture.new()
	var c := Curve.new()
	c.add_point(Vector2(0, 1))
	c.add_point(Vector2(1, 0))
	curve.curve = c
	pm.scale_curve = curve
	pm.color = Color(1, 1, 1)
	pm.color_ramp = _ramp([[0.0, Color(1, 1, 1, 1)], [0.35, Color(1, 1, 1, 1)], [1.0, Color(1, 1, 1, 0)]])
	p.process_material = pm
	var q := QuadMesh.new()
	q.size = Vector2(0.05, 0.42)
	var sm := ShaderMaterial.new()
	sm.shader = STREAK_SHADER
	sm.set_shader_parameter("tex", _tex["circle_05"])
	sm.set_shader_parameter("intensity", 2.4)
	q.material = sm
	p.draw_pass_1 = q
	return p


func _make_flash() -> Node3D:
	var mi := MeshInstance3D.new()
	var q := QuadMesh.new()
	q.size = Vector2(1, 1)
	mi.mesh = q
	var m := _unshaded_add(_tex["star_06"])
	m.no_depth_test = true
	mi.material_override = m
	mi.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	var ring := MeshInstance3D.new()
	var q2 := QuadMesh.new()
	q2.size = Vector2(1, 1)
	ring.mesh = q2
	ring.name = "Ring"
	ring.material_override = _unshaded_add(_tex["light_03"])
	ring.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	mi.add_child(ring)
	return mi


func _make_tracer() -> Node3D:
	var mi := MeshInstance3D.new()
	var q := QuadMesh.new()
	q.size = Vector2(1, 1)
	q.center_offset = Vector3(0, 0.5, 0)
	mi.mesh = q
	var sm := ShaderMaterial.new()
	sm.shader = STREAK_SHADER
	sm.set_shader_parameter("tex", _tex["trace_02"])
	sm.set_shader_parameter("intensity", 2.2)
	mi.material_override = sm
	mi.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	mi.extra_cull_margin = 200.0
	return mi


func _make_number() -> Node3D:
	var l := Label3D.new()
	l.billboard = BaseMaterial3D.BILLBOARD_ENABLED
	l.no_depth_test = true
	l.fixed_size = true
	l.pixel_size = 0.0011
	l.font = _font
	l.font_size = 44
	l.outline_size = 12
	l.outline_modulate = Color(0.02, 0.02, 0.05, 0.9)
	l.render_priority = 10
	l.outline_render_priority = 9
	return l


func _make_muzzle() -> Node3D:
	var root := Node3D.new()
	for i in 2:
		var mi := MeshInstance3D.new()
		var q := QuadMesh.new()
		q.size = Vector2(1, 1)
		mi.mesh = q
		mi.material_override = _unshaded_add(_tex["star_04"] if i == 0 else _tex["circle_05"])
		mi.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
		root.add_child(mi)
	var jet := MeshInstance3D.new()
	var q2 := QuadMesh.new()
	q2.size = Vector2(1, 1)
	q2.center_offset = Vector3(0, 0.5, 0)
	jet.mesh = q2
	var sm := ShaderMaterial.new()
	sm.shader = STREAK_SHADER
	sm.set_shader_parameter("tex", _tex["muzzle_04"])
	sm.set_shader_parameter("intensity", 2.4)
	jet.material_override = sm
	jet.name = "Jet"
	jet.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	root.add_child(jet)
	return root


func _make_slash() -> Node3D:
	var mi := MeshInstance3D.new()
	mi.mesh = _arc_mesh(1.35, 0.55, 150.0, 20)
	var sm := ShaderMaterial.new()
	sm.shader = SLASH_SHADER
	mi.material_override = sm
	mi.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	return mi


func _make_ring() -> Node3D:
	var mi := MeshInstance3D.new()
	var q := PlaneMesh.new()
	q.size = Vector2(1, 1)
	mi.mesh = q
	var m := _unshaded_add(_tex["light_03"], false)
	mi.material_override = m
	mi.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	return mi


## Flat arc (crescent) mesh in the XZ plane, facing -Z, for slash effects.
static func _arc_mesh(outer: float, inner: float, arc_deg: float, segs: int) -> ArrayMesh:
	var st := SurfaceTool.new()
	st.begin(Mesh.PRIMITIVE_TRIANGLES)
	var half := deg_to_rad(arc_deg) * 0.5
	for i in segs:
		var a0 := -half + (2.0 * half) * float(i) / segs
		var a1 := -half + (2.0 * half) * float(i + 1) / segs
		var u0 := float(i) / segs
		var u1 := float(i + 1) / segs
		var p := [
			[Vector3(sin(a0) * inner, 0, -cos(a0) * inner), Vector2(u0, 0)],
			[Vector3(sin(a0) * outer, 0, -cos(a0) * outer), Vector2(u0, 1)],
			[Vector3(sin(a1) * outer, 0, -cos(a1) * outer), Vector2(u1, 1)],
			[Vector3(sin(a1) * inner, 0, -cos(a1) * inner), Vector2(u1, 0)],
		]
		for idx in [0, 1, 2, 0, 2, 3]:
			st.set_uv(p[idx][1])
			st.set_normal(Vector3.UP)
			st.add_vertex(p[idx][0])
	return st.commit()


# --- Public effects ---------------------------------------------------------------

func sparks(pos: Vector3, dir: Vector3, color: Color, size: float = 1.0, amount_scale: float = 1.0) -> void:
	var p := _next("sparks") as GPUParticles3D
	if p == null:
		return
	p.global_position = pos
	var d := dir.normalized() if dir.length() > 0.01 else Vector3.UP
	var up := Vector3.UP if absf(d.y) < 0.95 else Vector3.RIGHT
	p.global_basis = Basis.looking_at(d, up)
	var pm := p.process_material as ParticleProcessMaterial
	pm.color = Color(color.r * 1.4, color.g * 1.4, color.b * 1.4)
	pm.initial_velocity_min = 5.0 * size
	pm.initial_velocity_max = 14.0 * size
	p.amount_ratio = clampf(amount_scale, 0.1, 1.0)
	p.restart()


func burst(pos: Vector3, color: Color, count: int = 20, speed: float = 10.0) -> void:
	var p := _next("sparks") as GPUParticles3D
	if p == null:
		return
	p.global_position = pos
	p.global_basis = Basis.looking_at(Vector3.UP, Vector3.RIGHT)
	var pm := p.process_material as ParticleProcessMaterial
	pm.color = Color(color.r * 1.4, color.g * 1.4, color.b * 1.4)
	pm.initial_velocity_min = speed * 0.4
	pm.initial_velocity_max = speed
	p.amount_ratio = clampf(count / 18.0, 0.1, 1.0)
	p.restart()


## Flash + ring + sparks where a character is struck.
func hit_spark(pos: Vector3, dir: Vector3, color: Color, size: float = 1.0) -> void:
	var f := _next("flash") as MeshInstance3D
	if f == null:
		return
	f.global_position = pos
	var m := f.material_override as StandardMaterial3D
	var bright := Color(1.6 + color.r, 1.6 + color.g, 1.6 + color.b)
	m.albedo_color = bright
	var ring := f.get_node("Ring") as MeshInstance3D
	(ring.material_override as StandardMaterial3D).albedo_color = color * 2.0
	f.scale = Vector3.ONE * 0.2
	ring.scale = Vector3.ONE * 0.5
	var tw := f.create_tween().set_parallel(true)
	f.set_meta("tween", tw)
	var s := 1.3 * size
	tw.tween_property(f, "scale", Vector3.ONE * s, 0.06).set_trans(Tween.TRANS_QUAD).set_ease(Tween.EASE_OUT)
	tw.tween_property(ring, "scale", Vector3.ONE * 1.6, 0.18).set_trans(Tween.TRANS_QUAD).set_ease(Tween.EASE_OUT)
	tw.tween_property(m, "albedo_color", Color(0, 0, 0), 0.16).set_delay(0.04)
	tw.tween_property(ring.material_override, "albedo_color", Color(0, 0, 0), 0.18)
	tw.chain().tween_callback(f.hide)
	sparks(pos, dir, color, size, size)


## Short star glint (attack telegraphs).
func glint(pos: Vector3, color: Color, size: float = 1.0) -> void:
	var f := _next("flash") as MeshInstance3D
	if f == null:
		return
	f.global_position = pos
	var m := f.material_override as StandardMaterial3D
	m.albedo_color = Color(1.2 + color.r * 1.5, 1.2 + color.g * 1.5, 1.2 + color.b * 1.5)
	var ring := f.get_node("Ring") as MeshInstance3D
	(ring.material_override as StandardMaterial3D).albedo_color = Color(0, 0, 0)
	f.scale = Vector3.ONE * 0.05
	f.rotation = Vector3.ZERO
	var tw := f.create_tween()
	f.set_meta("tween", tw)
	tw.tween_property(f, "scale", Vector3.ONE * 0.9 * size, 0.12).set_trans(Tween.TRANS_BACK).set_ease(Tween.EASE_OUT)
	tw.tween_property(f, "scale", Vector3.ONE * 0.01, 0.18)
	tw.tween_callback(f.hide)


func impact(pos: Vector3, normal: Vector3, color: Color, size: float = 1.0) -> void:
	var f := _next("flash") as MeshInstance3D
	if f == null:
		return
	f.global_position = pos + normal * 0.05
	var m := f.material_override as StandardMaterial3D
	m.albedo_color = Color(color.r * 2.0, color.g * 2.0, color.b * 2.0)
	var ring := f.get_node("Ring") as MeshInstance3D
	(ring.material_override as StandardMaterial3D).albedo_color = Color(0, 0, 0)
	f.scale = Vector3.ONE * 0.15 * size
	var tw := f.create_tween().set_parallel(true)
	f.set_meta("tween", tw)
	tw.tween_property(f, "scale", Vector3.ONE * 0.55 * size, 0.05)
	tw.tween_property(m, "albedo_color", Color(0, 0, 0), 0.12).set_delay(0.03)
	tw.chain().tween_callback(f.hide)
	sparks(pos, normal, color, 0.6 * size, 0.5)


func tracer(from: Vector3, to: Vector3, color: Color, width: float = 0.05, life: float = 0.1) -> void:
	var t := _next("tracer") as MeshInstance3D
	if t == null:
		return
	var d := to - from
	var len := d.length()
	if len < 0.05:
		t.hide()
		return
	var y := d / len
	var x := y.cross(Vector3.UP if absf(y.y) < 0.95 else Vector3.RIGHT).normalized()
	var z := x.cross(y).normalized()
	t.global_transform = Transform3D(Basis(x * width, y * len, z), from)
	var sm := t.material_override as ShaderMaterial
	sm.set_shader_parameter("intensity", 2.6)
	_tint_streak(t, color)
	var tw := t.create_tween()
	t.set_meta("tween", tw)
	tw.tween_method(func(w: float) -> void: _set_width(t, x, y * len, z, from, w), width, 0.0, life)
	tw.tween_callback(t.hide)


func _tint_streak(t: MeshInstance3D, color: Color) -> void:
	# Mesh quads have white vertex colours, so the streak shader is tinted by uniform.
	var sm := t.material_override as ShaderMaterial
	sm.set_shader_parameter("tint", Vector3(color.r, color.g, color.b))


func _set_width(t: MeshInstance3D, x: Vector3, y: Vector3, z: Vector3, origin: Vector3, w: float) -> void:
	t.global_transform = Transform3D(Basis(x * maxf(w, 0.0005), y, z), origin)


func beam(from: Vector3, to: Vector3, color: Color, width: float = 0.12) -> void:
	tracer(from, to, color, width * 1.8, 0.35)
	tracer(from, to, Color(1.2, 1.2, 1.2), width * 0.45, 0.25)
	var steps := int(clampf(from.distance_to(to) / 3.0, 2.0, 10.0))
	for i in range(1, steps):
		if i % 2 == 0:
			var p := from.lerp(to, float(i) / steps)
			sparks(p, (to - from).normalized(), color, 0.4, 0.3)


func muzzle_flash(pos: Vector3, dir: Vector3, color: Color, size: float = 1.0) -> void:
	var r := _next("muzzle")
	if r == null:
		return
	r.global_position = pos
	var star := r.get_child(0) as MeshInstance3D
	var glow := r.get_child(1) as MeshInstance3D
	var jet := r.get_node("Jet") as MeshInstance3D
	var c := Color(color.r * 2.2 + 0.6, color.g * 2.2 + 0.6, color.b * 2.2 + 0.6)
	(star.material_override as StandardMaterial3D).albedo_color = c
	(glow.material_override as StandardMaterial3D).albedo_color = color * 1.5
	star.scale = Vector3.ONE * 0.55 * size
	star.rotation.z = randf() * TAU
	glow.scale = Vector3.ONE * 0.8 * size
	var d := dir.normalized() if dir.length() > 0.01 else Vector3.FORWARD
	var x := d.cross(Vector3.UP if absf(d.y) < 0.95 else Vector3.RIGHT).normalized()
	jet.global_transform = Transform3D(Basis(x * 0.28 * size, d * 0.7 * size, x.cross(d)), pos)
	_tint_streak(jet, color)
	var tw := r.create_tween()
	r.set_meta("tween", tw)
	tw.tween_interval(0.05 if size < 1.2 else 0.08)
	tw.tween_callback(r.hide)


## Crescent slash arc in front of an attacker. `xform` faces the swing direction.
func slash(xform: Transform3D, color: Color, scale: float = 1.0, roll_deg: float = 0.0, full_circle: bool = false) -> void:
	if full_circle:
		# Spin attacks: two horizontal arcs around the attacker's body.
		var center := xform.origin + xform.basis.z * 0.9
		var yaw := randf() * TAU
		for k in 2:
			var b := Basis(Vector3.UP, yaw + PI * k)
			_slash_one(Transform3D(b.scaled(Vector3.ONE * scale * 1.25), center), color, 0.3)
		return
	var b2 := xform.basis * Basis(Vector3(0, 0, 1), deg_to_rad(roll_deg))
	_slash_one(Transform3D(b2.scaled(Vector3.ONE * scale), xform.origin + xform.basis.z * 0.35), color, 0.22)


func _slash_one(xf: Transform3D, color: Color, life: float) -> void:
	var s := _next("slash") as MeshInstance3D
	if s == null:
		return
	s.global_transform = xf
	var sm := s.material_override as ShaderMaterial
	sm.set_shader_parameter("color", Vector3(color.r, color.g, color.b))
	sm.set_shader_parameter("progress", 0.0)
	var tw := s.create_tween()
	s.set_meta("tween", tw)
	tw.tween_method(func(v: float) -> void: sm.set_shader_parameter("progress", v), 0.0, 1.0, life)
	tw.tween_callback(s.hide)


func shockwave(pos: Vector3, radius: float, color: Color) -> void:
	var r := _next("ring") as MeshInstance3D
	if r == null:
		return
	r.global_transform = Transform3D(Basis(), pos + Vector3.UP * 0.08)
	r.scale = Vector3.ONE * 0.3
	var m := r.material_override as StandardMaterial3D
	m.albedo_color = Color(color.r * 2.5, color.g * 2.5, color.b * 2.5)
	var tw := r.create_tween().set_parallel(true)
	r.set_meta("tween", tw)
	tw.tween_property(r, "scale", Vector3(radius * 2.6, 1.0, radius * 2.6), 0.35).set_trans(Tween.TRANS_EXPO).set_ease(Tween.EASE_OUT)
	tw.tween_property(m, "albedo_color", Color(0, 0, 0), 0.35).set_trans(Tween.TRANS_QUAD).set_ease(Tween.EASE_IN)
	tw.chain().tween_callback(r.hide)


func dust_ring(pos: Vector3, size: float = 1.0) -> void:
	var r := _next("ring") as MeshInstance3D
	if r == null:
		return
	r.global_transform = Transform3D(Basis(), pos + Vector3.UP * 0.06)
	r.scale = Vector3.ONE * 0.4 * size
	var m := r.material_override as StandardMaterial3D
	m.albedo_color = Color(0.55, 0.6, 0.7)
	var tw := r.create_tween().set_parallel(true)
	r.set_meta("tween", tw)
	tw.tween_property(r, "scale", Vector3(2.2 * size, 1.0, 2.2 * size), 0.3).set_trans(Tween.TRANS_QUAD).set_ease(Tween.EASE_OUT)
	tw.tween_property(m, "albedo_color", Color(0, 0, 0), 0.3)
	tw.chain().tween_callback(r.hide)


func damage_number(pos: Vector3, amount: float, color: Color, big: bool = false) -> void:
	var l := _next("number") as Label3D
	if l == null:
		return
	l.text = str(int(round(amount)))
	l.global_position = pos + Vector3(randf_range(-0.25, 0.25), randf_range(0.0, 0.2), randf_range(-0.25, 0.25))
	var c := color.lerp(Color.WHITE, 0.55) if not big else Color(1.0, 0.92, 0.45)
	l.modulate = c
	l.outline_modulate = Color(0.02, 0.02, 0.05, 0.9)
	l.font_size = 60 if big else 44
	l.scale = Vector3.ONE * 1.7
	var tw := l.create_tween().set_parallel(true)
	l.set_meta("tween", tw)
	tw.tween_property(l, "scale", Vector3.ONE, 0.14).set_trans(Tween.TRANS_BACK).set_ease(Tween.EASE_OUT)
	tw.tween_property(l, "global_position", l.global_position + Vector3.UP * 0.9, 0.7).set_trans(Tween.TRANS_QUAD).set_ease(Tween.EASE_OUT)
	tw.tween_property(l, "modulate:a", 0.0, 0.25).set_delay(0.45)
	tw.tween_property(l, "outline_modulate:a", 0.0, 0.25).set_delay(0.45)
	tw.chain().tween_callback(l.hide)


func explosion(pos: Vector3, radius: float, color: Color, with_light: bool = true) -> void:
	var scene := get_tree().current_scene
	if scene == null:
		return
	# Core flash sphere.
	var core := MeshInstance3D.new()
	var sph := SphereMesh.new()
	sph.radius = 0.5
	sph.height = 1.0
	sph.radial_segments = 16
	sph.rings = 8
	core.mesh = sph
	var cm := StandardMaterial3D.new()
	cm.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	cm.blend_mode = BaseMaterial3D.BLEND_MODE_ADD
	cm.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	cm.albedo_color = Color(1.6 + color.r, 1.4 + color.g, 1.2 + color.b)
	core.material_override = cm
	core.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	scene.add_child(core)
	core.global_position = pos
	core.scale = Vector3.ONE * 0.3
	var tw := core.create_tween().set_parallel(true)
	tw.tween_property(core, "scale", Vector3.ONE * radius * 1.1, 0.18).set_trans(Tween.TRANS_EXPO).set_ease(Tween.EASE_OUT)
	tw.tween_property(cm, "albedo_color", Color(0, 0, 0), 0.3).set_delay(0.05)
	tw.chain().tween_callback(core.queue_free)
	# Smoke/fire billboards.
	var fire := GPUParticles3D.new()
	fire.amount = 12 if quality > 0 else 6
	fire.one_shot = true
	fire.explosiveness = 0.95
	fire.lifetime = 0.8
	fire.local_coords = false
	var pm := ParticleProcessMaterial.new()
	pm.emission_shape = ParticleProcessMaterial.EMISSION_SHAPE_SPHERE
	pm.emission_sphere_radius = radius * 0.25
	pm.direction = Vector3.UP
	pm.spread = 180.0
	pm.initial_velocity_min = 1.0
	pm.initial_velocity_max = radius * 1.4
	pm.gravity = Vector3(0, 1.5, 0)
	pm.damping_min = 2.0
	pm.damping_max = 4.0
	pm.angle_min = -180.0
	pm.angle_max = 180.0
	pm.scale_min = radius * 0.5
	pm.scale_max = radius * 0.9
	var sc := CurveTexture.new()
	var c := Curve.new()
	c.add_point(Vector2(0, 0.4))
	c.add_point(Vector2(0.3, 1.0))
	c.add_point(Vector2(1, 1.2))
	sc.curve = c
	pm.scale_curve = sc
	pm.color_ramp = _ramp([[0.0, Color(2.0, 1.6, 1.2, 1)], [0.2, Color(color.r * 1.8, color.g * 1.5, color.b * 1.2, 0.9)], [0.6, Color(0.15, 0.12, 0.14, 0.5)], [1.0, Color(0.05, 0.05, 0.06, 0.0)]])
	fire.process_material = pm
	var q := QuadMesh.new()
	q.size = Vector2(1, 1)
	var fm := _particle_mat(_tex["smoke_04"])
	fm.blend_mode = BaseMaterial3D.BLEND_MODE_MIX
	q.material = fm
	fire.draw_pass_1 = q
	scene.add_child(fire)
	fire.global_position = pos
	fire.emitting = true
	fire.finished.connect(fire.queue_free)
	burst(pos, color, 22, radius * 3.5)
	shockwave(Vector3(pos.x, pos.y - 0.4, pos.z), radius, color)
	if with_light and quality > 0:
		var light := OmniLight3D.new()
		light.light_color = color.lerp(Color(1, 0.8, 0.5), 0.5)
		light.light_energy = 6.0
		light.omni_range = radius * 2.5
		light.shadow_enabled = false
		scene.add_child(light)
		light.global_position = pos
		var lt := light.create_tween()
		lt.tween_property(light, "light_energy", 0.0, 0.3)
		lt.tween_callback(light.queue_free)


## Vertical energy pillar used for spawns and pickups.
func spawn_pillar(pos: Vector3, color: Color, height: float = 6.0, life: float = 0.9) -> void:
	var scene := get_tree().current_scene
	if scene == null:
		return
	var mi := MeshInstance3D.new()
	var cyl := CylinderMesh.new()
	cyl.top_radius = 0.9
	cyl.bottom_radius = 0.9
	cyl.height = 1.0
	cyl.cap_top = false
	cyl.cap_bottom = false
	cyl.radial_segments = 20
	cyl.rings = 1
	mi.mesh = cyl
	var sm := ShaderMaterial.new()
	sm.shader = PILLAR_SHADER
	sm.set_shader_parameter("color", Vector3(color.r, color.g, color.b))
	mi.material_override = sm
	mi.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	scene.add_child(mi)
	mi.global_position = pos + Vector3.UP * height * 0.5
	mi.scale = Vector3(0.2, height, 0.2)
	var tw := mi.create_tween().set_parallel(true)
	tw.tween_property(mi, "scale", Vector3(1.0, height, 1.0), 0.18).set_trans(Tween.TRANS_BACK).set_ease(Tween.EASE_OUT)
	tw.tween_method(func(v: float) -> void: sm.set_shader_parameter("fade", v), 1.0, 0.0, life).set_delay(0.1)
	tw.chain().tween_callback(mi.queue_free)
	shockwave(pos, 1.6, color)
	burst(pos + Vector3.UP * 0.3, color, 16, 7.0)
