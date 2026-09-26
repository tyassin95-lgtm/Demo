class_name ArenaBuilder
extends Node3D
## Builds the "Stratos Deck" arena procedurally: a floating sky platform with a raised
## core, four towers joined by high walkways, wall-run lanes, pillars, cover, jump pads,
## pickups, an energy barrier and a distant city. Static geometry is merged per
## material into a few meshes (few draw calls on mobile) with simple box colliders.

const PANEL := preload("res://shaders/panel.gdshader")
const NEON := preload("res://shaders/neon.gdshader")
const BARRIER := preload("res://shaders/barrier.gdshader")
const CITY := preload("res://shaders/city.gdshader")
const GRIT := preload("res://assets/environment/grit.png")

const HALF := 26.0
const CYAN := Color(0.2, 0.85, 1.0)
const ORANGE := Color(1.0, 0.45, 0.12)
const MAGENTA := Color(1.0, 0.25, 0.7)

var player_spawn := Vector3(0, 0.1, 19)
var enemy_spawns: Array[Vector3] = []
var pickup_points: Array[Vector3] = []
var jump_pads: Array = []

var _surfaces := {}
var _materials := {}
var _body: StaticBody3D
var _neon := SurfaceTool.new()
var _neon_used := false


func build() -> void:
	_make_materials()
	_body = StaticBody3D.new()
	_body.name = "ArenaCollision"
	_body.collision_layer = Game.LAYER_WORLD
	_body.collision_mask = 0
	add_child(_body)
	_neon.begin(Mesh.PRIMITIVE_TRIANGLES)
	_layout()
	_commit_meshes()
	_build_barrier()
	_build_city()
	_build_decor()


func _make_materials() -> void:
	_materials["floor"] = _panel_mat(Color(0.2, 0.22, 0.27), Color(0.15, 0.16, 0.2), CYAN, 2.0, 0.07, 0.34, 0.4)
	_materials["floor_core"] = _panel_mat(Color(0.15, 0.16, 0.2), Color(0.11, 0.11, 0.15), ORANGE, 1.5, 0.18, 0.3, 0.45)
	_materials["wall"] = _panel_mat(Color(0.36, 0.4, 0.47), Color(0.28, 0.31, 0.37), CYAN, 1.5, 0.05, 0.6, 0.08)
	_materials["block"] = _panel_mat(Color(0.72, 0.75, 0.8), Color(0.6, 0.63, 0.69), CYAN, 1.0, 0.0, 0.5, 0.05)
	_materials["dark"] = _panel_mat(Color(0.08, 0.09, 0.12), Color(0.06, 0.07, 0.09), MAGENTA, 1.0, 0.08, 0.45, 0.5)
	var nm := ShaderMaterial.new()
	nm.shader = NEON
	nm.set_shader_parameter("color", Vector3(1, 1, 1))
	_materials["neon"] = nm


func _panel_mat(base: Color, alt: Color, light: Color, tile: float, density: float, rough: float, metal: float) -> ShaderMaterial:
	var m := ShaderMaterial.new()
	m.shader = PANEL
	m.set_shader_parameter("base_color", Vector3(base.r, base.g, base.b))
	m.set_shader_parameter("alt_color", Vector3(alt.r, alt.g, alt.b))
	m.set_shader_parameter("light_color", Vector3(light.r, light.g, light.b))
	m.set_shader_parameter("tile_size", tile)
	m.set_shader_parameter("light_density", density)
	m.set_shader_parameter("roughness_base", rough)
	m.set_shader_parameter("metallic_base", metal)
	m.set_shader_parameter("detail_tex", GRIT)
	return m


# --- Geometry helpers ---------------------------------------------------------------

func _st(mat: String) -> SurfaceTool:
	if not _surfaces.has(mat):
		var st := SurfaceTool.new()
		st.begin(Mesh.PRIMITIVE_TRIANGLES)
		_surfaces[mat] = st
	return _surfaces[mat]


func box(center: Vector3, size: Vector3, mat: String, collide: bool = true, yaw_deg: float = 0.0) -> void:
	var bm := BoxMesh.new()
	bm.size = size
	var xf := Transform3D(Basis(Vector3.UP, deg_to_rad(yaw_deg)), center)
	_st(mat).append_from(bm, 0, xf)
	if collide:
		var cs := CollisionShape3D.new()
		var shape := BoxShape3D.new()
		shape.size = size
		cs.shape = shape
		cs.transform = xf
		_body.add_child(cs)


## Ramp rising along +dir (local -Z when yaw=0) from `low` height 0 to `height`.
func ramp(base_center: Vector3, width: float, length: float, height: float, yaw_deg: float, mat: String) -> void:
	var b := Basis(Vector3.UP, deg_to_rad(yaw_deg))
	var hw := width * 0.5
	var hl := length * 0.5
	# Local: slope goes up toward -Z.
	var p := [
		Vector3(-hw, 0, hl), Vector3(hw, 0, hl), Vector3(hw, 0, -hl), Vector3(-hw, 0, -hl),
		Vector3(-hw, height, -hl), Vector3(hw, height, -hl),
	]
	var world := []
	for v in p:
		world.append(base_center + b * v)
	var st := _st(mat)
	var centroid := Vector3.ZERO
	for v in world:
		centroid += v
	centroid /= world.size()
	var tris := [[0, 4, 1], [1, 4, 5], [3, 4, 0], [1, 5, 2], [3, 2, 5], [3, 5, 4], [0, 1, 2], [0, 2, 3]]
	for t in tris:
		var a: Vector3 = world[t[0]]
		var c1: Vector3 = world[t[1]]
		var c2: Vector3 = world[t[2]]
		# Godot treats clockwise triangles as front faces: orient each face outward.
		var n := (c2 - a).cross(c1 - a).normalized()
		if n.dot((a + c1 + c2) / 3.0 - centroid) < 0.0:
			var tmp := c1
			c1 = c2
			c2 = tmp
			n = -n
		for v in [a, c1, c2]:
			st.set_normal(n)
			st.set_uv(Vector2(v.x, v.z))
			st.add_vertex(v)
	var cs := CollisionShape3D.new()
	var shape := ConvexPolygonShape3D.new()
	shape.points = PackedVector3Array(world)
	cs.shape = shape
	_body.add_child(cs)


func neon(a: Vector3, b: Vector3, color: Color, thick: float = 0.08) -> void:
	var d := b - a
	var len := d.length()
	if len < 0.01:
		return
	var bm := BoxMesh.new()
	bm.size = Vector3(thick, thick, len)
	var basis := Basis.looking_at(d / len, Vector3.UP if absf(d.normalized().y) < 0.95 else Vector3.RIGHT)
	var arrays := bm.get_mesh_arrays()
	var verts: PackedVector3Array = arrays[Mesh.ARRAY_VERTEX]
	var idx: PackedInt32Array = arrays[Mesh.ARRAY_INDEX]
	var xf := Transform3D(basis, (a + b) * 0.5)
	for i in idx:
		_neon.set_color(color)
		_neon.add_vertex(xf * verts[i])
	_neon_used = true


## Neon outline around the top edge of an axis-aligned box.
func neon_top_outline(center: Vector3, size: Vector3, color: Color, inset: float = 0.02) -> void:
	var y := center.y + size.y * 0.5 + 0.01
	var hx := size.x * 0.5 - inset
	var hz := size.z * 0.5 - inset
	var c := [Vector3(-hx, y, -hz), Vector3(hx, y, -hz), Vector3(hx, y, hz), Vector3(-hx, y, hz)]
	for i in 4:
		neon(Vector3(center.x, 0, center.z) + c[i], Vector3(center.x, 0, center.z) + c[(i + 1) % 4], color)


func _commit_meshes() -> void:
	for key in _surfaces:
		var st: SurfaceTool = _surfaces[key]
		var mi := MeshInstance3D.new()
		mi.name = "Mesh_" + key
		mi.mesh = st.commit()
		mi.material_override = _materials[key]
		add_child(mi)
	if _neon_used:
		var mi := MeshInstance3D.new()
		mi.name = "Mesh_neon"
		mi.mesh = _neon.commit()
		mi.material_override = _materials["neon"]
		mi.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
		add_child(mi)


# --- Layout -----------------------------------------------------------------------------

func _layout() -> void:
	# Main deck.
	box(Vector3(0, -0.5, 0), Vector3(HALF * 2, 1.0, HALF * 2), "floor")
	# Underside hull (visible from the edges) tapering down.
	box(Vector3(0, -2.5, 0), Vector3(HALF * 2 - 4, 3.0, HALF * 2 - 4), "dark", false)
	box(Vector3(0, -5.5, 0), Vector3(HALF * 2 - 16, 3.0, HALF * 2 - 16), "dark", false)
	# Perimeter walls (wall-run surfaces) with neon caps.
	var wh := 4.0
	for s in [-1.0, 1.0]:
		box(Vector3(0, wh * 0.5, s * (HALF + 0.5)), Vector3(HALF * 2 + 2, wh, 1.0), "wall")
		box(Vector3(s * (HALF + 0.5), wh * 0.5, 0), Vector3(1.0, wh, HALF * 2), "wall")
		neon(Vector3(-HALF, wh + 0.02, s * HALF), Vector3(HALF, wh + 0.02, s * HALF), CYAN, 0.1)
		neon(Vector3(s * HALF, wh + 0.02, -HALF), Vector3(s * HALF, wh + 0.02, HALF), CYAN, 0.1)
		neon(Vector3(-HALF, 0.6, s * (HALF - 0.01)), Vector3(HALF, 0.6, s * (HALF - 0.01)), Color(0.15, 0.5, 0.8), 0.05)
		neon(Vector3(s * (HALF - 0.01), 0.6, -HALF), Vector3(s * (HALF - 0.01), 0.6, HALF), Color(0.15, 0.5, 0.8), 0.05)
	# Invisible containment above the walls.
	for s in [-1.0, 1.0]:
		_invisible_wall(Vector3(0, 14.0, s * (HALF + 0.5)), Vector3(HALF * 2 + 2, 20.0, 1.0))
		_invisible_wall(Vector3(s * (HALF + 0.5), 14.0, 0), Vector3(1.0, 20.0, HALF * 2))

	# Central core platform with ramps north/south.
	var core_h := 2.5
	box(Vector3(0, core_h * 0.5, 0), Vector3(12, core_h, 12), "floor_core")
	neon_top_outline(Vector3(0, core_h * 0.5, 0), Vector3(12, core_h, 12), ORANGE)
	for s in [-1.0, 1.0]:
		ramp(Vector3(0, 0, s * 9.0), 4.0, 6.0, core_h, 0.0 if s > 0 else 180.0, "floor_core")
		neon(Vector3(-2.0, 0.05, s * 12.0), Vector3(-2.0, core_h + 0.05, s * 6.0), ORANGE, 0.06)
		neon(Vector3(2.0, 0.05, s * 12.0), Vector3(2.0, core_h + 0.05, s * 6.0), ORANGE, 0.06)
	# Core emblem ring.
	for i in 24:
		var a0 := TAU * i / 24.0
		var a1 := TAU * (i + 1) / 24.0
		neon(Vector3(cos(a0) * 3.0, core_h + 0.02, sin(a0) * 3.0), Vector3(cos(a1) * 3.0, core_h + 0.02, sin(a1) * 3.0), ORANGE, 0.07)

	# Towers in the corners + high walkways east/west.
	var th := 5.0
	for sx in [-1.0, 1.0]:
		for sz in [-1.0, 1.0]:
			var c := Vector3(sx * 18.0, th * 0.5, sz * 18.0)
			box(c, Vector3(6, th, 6), "block")
			neon_top_outline(c, Vector3(6, th, 6), MAGENTA)
			# Vertical light seams on the tower faces.
			for k in [-1.0, 1.0]:
				neon(Vector3(c.x + k * 3.01, 0.3, c.z - sz * 3.01), Vector3(c.x + k * 3.01, th - 0.2, c.z - sz * 3.01), MAGENTA, 0.06)
			pickup_points.append(Vector3(c.x, th + 0.1, c.z))
		box(Vector3(sx * 18.0, th - 0.25, 0), Vector3(3.0, 0.5, 30.0), "dark")
		neon(Vector3(sx * 16.5, th + 0.01, -15), Vector3(sx * 16.5, th + 0.01, 15), CYAN, 0.07)
		neon(Vector3(sx * 19.5, th + 0.01, -15), Vector3(sx * 19.5, th + 0.01, 15), CYAN, 0.07)
		# Walkway support struts.
		for z in [-7.5, 7.5]:
			box(Vector3(sx * 18.0, (th - 0.5) * 0.5, z), Vector3(0.8, th - 0.5, 0.8), "dark")

	# Wall-run lanes north and south of the core.
	for sx in [-1.0, 1.0]:
		for sz in [-1.0, 1.0]:
			var c := Vector3(sx * 9.5, 2.25, sz * 13.5)
			box(c, Vector3(8.0, 4.5, 0.8), "wall")
			neon_top_outline(c, Vector3(8.0, 4.5, 0.8), ORANGE)
			neon(Vector3(c.x - 4.0, 1.2, c.z + 0.41), Vector3(c.x + 4.0, 1.2, c.z + 0.41), CYAN, 0.05)
			neon(Vector3(c.x - 4.0, 1.2, c.z - 0.41), Vector3(c.x + 4.0, 1.2, c.z - 0.41), CYAN, 0.05)

	# Pillars.
	for p in [Vector2(11, 4), Vector2(-11, 4), Vector2(11, -4), Vector2(-11, -4), Vector2(4.5, 11), Vector2(-4.5, 11), Vector2(4.5, -11), Vector2(-4.5, -11)]:
		var c := Vector3(p.x, 3.0, p.y)
		box(c, Vector3(1.3, 6.0, 1.3), "block")
		neon(Vector3(c.x - 0.66, 0.2, c.z - 0.66), Vector3(c.x - 0.66, 5.8, c.z - 0.66), CYAN, 0.05)
		neon(Vector3(c.x + 0.66, 0.2, c.z + 0.66), Vector3(c.x + 0.66, 5.8, c.z + 0.66), CYAN, 0.05)

	# Low cover.
	for c in [Vector3(0, 0.6, 21), Vector3(0, 0.6, -21), Vector3(-21.5, 0.6, 0), Vector3(21.5, 0.6, 0)]:
		var sz := Vector3(4.0, 1.2, 1.2) if absf(c.z) > 5.0 else Vector3(1.2, 1.2, 4.0)
		box(c, sz, "dark")
		neon_top_outline(c, sz, CYAN)
	for c in [Vector3(7, 0.55, 18), Vector3(-7, 0.55, -18), Vector3(18, 0.55, 8), Vector3(-18, 0.55, -8)]:
		box(c, Vector3(1.8, 1.1, 1.8), "block")

	# Jump pads: to tower tops and up onto the walkways.
	for sx in [-1.0, 1.0]:
		for sz in [-1.0, 1.0]:
			_add_pad(Vector3(sx * 12.5, 0.02, sz * 18.0), Vector3(sx * 17.0, th + 0.2, sz * 18.0), MAGENTA)
		_add_pad(Vector3(sx * 12.0, 0.02, 0.0), Vector3(sx * 18.0, th + 0.2, 0.0), CYAN)
	pickup_points.append(Vector3(0, core_h + 0.1, 0))

	# Spawn points.
	player_spawn = Vector3(0, 0.1, 19)
	for p in [Vector3(-22, 0.1, -10), Vector3(22, 0.1, -10), Vector3(-22, 0.1, 10), Vector3(22, 0.1, 10), Vector3(-10, 0.1, -22), Vector3(10, 0.1, -22), Vector3(0, 0.1, -17), Vector3(-15, 0.1, 22), Vector3(15, 0.1, 22)]:
		enemy_spawns.append(p)


func _invisible_wall(center: Vector3, size: Vector3) -> void:
	var cs := CollisionShape3D.new()
	var shape := BoxShape3D.new()
	shape.size = size
	cs.shape = shape
	cs.position = center
	_body.add_child(cs)


func _add_pad(pos: Vector3, target: Vector3, color: Color) -> void:
	var pad := JumpPad.new()
	pad.color = color
	add_child(pad)
	pad.global_position = pos
	pad.set_target(target)
	jump_pads.append(pad)


# --- Barrier, city, decor -----------------------------------------------------------------

func _build_barrier() -> void:
	var st := SurfaceTool.new()
	st.begin(Mesh.PRIMITIVE_TRIANGLES)
	var h0 := 4.0
	var h1 := 11.0
	var corners := [Vector3(-HALF, 0, -HALF), Vector3(HALF, 0, -HALF), Vector3(HALF, 0, HALF), Vector3(-HALF, 0, HALF)]
	for i in 4:
		var a: Vector3 = corners[i]
		var b: Vector3 = corners[(i + 1) % 4]
		var q := [a + Vector3.UP * h0, b + Vector3.UP * h0, b + Vector3.UP * h1, a + Vector3.UP * h1]
		var n := (b - a).cross(Vector3.UP).normalized()
		for t in [[0, 1, 2], [0, 2, 3]]:
			for k in t:
				st.set_normal(n)
				st.add_vertex(q[k])
	var mi := MeshInstance3D.new()
	mi.name = "Barrier"
	mi.mesh = st.commit()
	var m := ShaderMaterial.new()
	m.shader = BARRIER
	mi.material_override = m
	mi.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	add_child(mi)


func _build_city() -> void:
	var st := SurfaceTool.new()
	st.begin(Mesh.PRIMITIVE_TRIANGLES)
	var rng := RandomNumberGenerator.new()
	rng.seed = 4242
	var count := 90
	for i in count:
		var ang := rng.randf() * TAU
		var r := rng.randf_range(75.0, 230.0)
		var w := rng.randf_range(8.0, 22.0)
		var d := rng.randf_range(8.0, 22.0)
		var top := rng.randf_range(-70.0, 8.0) + (r - 75.0) * 0.12
		if rng.randf() < 0.12:
			top += rng.randf_range(20.0, 45.0)
		var bottom := -140.0
		var h := top - bottom
		var bm := BoxMesh.new()
		bm.size = Vector3(w, h, d)
		st.append_from(bm, 0, Transform3D(Basis(Vector3.UP, rng.randf() * PI), Vector3(cos(ang) * r, bottom + h * 0.5, sin(ang) * r)))
	var mi := MeshInstance3D.new()
	mi.name = "City"
	mi.mesh = st.commit()
	var m := ShaderMaterial.new()
	m.shader = CITY
	mi.material_override = m
	mi.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	add_child(mi)


func _build_decor() -> void:
	# Holographic arena sign above the north wall.
	var sign := Label3D.new()
	sign.text = "STRATOS DECK"
	sign.font = load("res://assets/fonts/Orbitron.ttf")
	sign.font_size = 220
	sign.pixel_size = 0.012
	sign.modulate = Color(0.45, 0.95, 1.0, 0.9)
	sign.outline_size = 0
	sign.shaded = false
	sign.double_sided = true
	sign.position = Vector3(0, 8.5, -HALF - 1.0)
	add_child(sign)
	var sub := Label3D.new()
	sub.text = "NEON RIFT  ·  ARENA 01"
	sub.font = load("res://assets/fonts/Rajdhani-SemiBold.ttf")
	sub.font_size = 120
	sub.pixel_size = 0.012
	sub.modulate = Color(1.0, 0.55, 0.25, 0.85)
	sub.shaded = false
	sub.position = Vector3(0, 6.6, -HALF - 1.0)
	add_child(sub)
	# Cover props from the sci-fi kit (crates and barrels) with simple colliders.
	var crate: PackedScene = load("res://assets/props/Prop_Crate.gltf")
	var crate_l: PackedScene = load("res://assets/props/Prop_Crate_Large.gltf")
	var barrel: PackedScene = load("res://assets/props/Prop_Barrel1.gltf")
	for spec in [
		[crate_l, Vector3(23.6, 0, -5.0), 90.0, Vector3(1.5, 1.5, 3.47)],
		[crate, Vector3(23.6, 1.5, -5.6), 90.0, Vector3(1.5, 1.5, 1.57)],
		[crate_l, Vector3(-23.6, 0, 5.0), 90.0, Vector3(1.5, 1.5, 3.47)],
		[crate, Vector3(-23.6, 1.5, 5.6), 90.0, Vector3(1.5, 1.5, 1.57)],
		[crate_l, Vector3(-5.0, 0, -23.6), 0.0, Vector3(3.47, 1.5, 1.5)],
		[crate_l, Vector3(5.0, 0, 23.6), 0.0, Vector3(3.47, 1.5, 1.5)],
		[crate, Vector3(12.0, 0, -23.8), 15.0, Vector3(1.57, 1.5, 1.5)],
		[crate, Vector3(-12.0, 0, 23.8), -10.0, Vector3(1.57, 1.5, 1.5)],
	]:
		var n: Node3D = (spec[0] as PackedScene).instantiate()
		add_child(n)
		n.position = spec[1]
		n.rotation_degrees.y = spec[2]
		var sz: Vector3 = spec[3]
		var cs := CollisionShape3D.new()
		var shape := BoxShape3D.new()
		shape.size = sz if absf(spec[2]) < 45.0 or absf(spec[2]) > 135.0 else Vector3(sz.x, sz.y, sz.z)
		cs.shape = shape
		cs.position = spec[1] + Vector3(0, sz.y * 0.5, 0)
		_body.add_child(cs)
	for bp in [Vector3(24.6, 0, 9.0), Vector3(24.2, 0, 10.1), Vector3(-24.6, 0, -9.0), Vector3(9.5, 0, -24.6), Vector3(-9.0, 0, 24.5), Vector3(-10.1, 0, 24.2)]:
		var b: Node3D = barrel.instantiate()
		add_child(b)
		b.position = bp
		b.rotation_degrees.y = randf() * 360.0
		var bcs := CollisionShape3D.new()
		var bsh := CylinderShape3D.new()
		bsh.radius = 0.36
		bsh.height = 1.1
		bcs.shape = bsh
		bcs.position = bp + Vector3(0, 0.55, 0)
		_body.add_child(bcs)
	# Broadcast drones circling the arena.
	for i in 3:
		var d := BroadcastDrone.new()
		d.phase = TAU * i / 3.0
		d.radius = 31.0 + i * 3.0
		d.height = 9.0 + i * 2.5
		d.speed = 0.1 + i * 0.03
		add_child(d)
	# Corner light masts (kit columns) outside the play space.
	var col_scene: PackedScene = load("res://assets/environment/Column_Round.gltf") if ResourceLoader.exists("res://assets/environment/Column_Round.gltf") else null
	for sx in [-1.0, 1.0]:
		for sz in [-1.0, 1.0]:
			var base := Vector3(sx * (HALF + 3.5), -6.0, sz * (HALF + 3.5))
			if col_scene:
				var colm: Node3D = col_scene.instantiate()
				add_child(colm)
				colm.global_position = base
				colm.scale = Vector3(1.6, 4.0, 1.6)
			var lamp := MeshInstance3D.new()
			var sph := SphereMesh.new()
			sph.radius = 0.8
			sph.height = 1.6
			lamp.mesh = sph
			var lm := StandardMaterial3D.new()
			lm.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
			lm.albedo_color = Color(2.2, 1.6, 1.1)
			lamp.material_override = lm
			add_child(lamp)
			lamp.global_position = base + Vector3(0, 21.0, 0)
