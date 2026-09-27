class_name ArenaTheme
extends RefCounted
## Time-of-day palettes for the arena: DAY is the bright sports-venue look (default),
## DUSK the neon evening look. Sky, lights, fog and arena material colours.

const DAY := {
	"sky_zenith": Color(0.09, 0.3, 0.76), "sky_mid": Color(0.28, 0.56, 0.95), "sky_horizon": Color(0.74, 0.88, 1.0),
	"sky_ground": Color(0.34, 0.44, 0.6), "sky_sun": Color(1.0, 0.93, 0.78), "stars": 0.0,
	"planet": Color(0.8, 0.86, 1.0), "planet_alpha": 0.3,
	"cloud": Color(1.0, 1.0, 1.0), "cloud_band": 0.55, "cloud_puffs": 0.85,
	"sun_rot": Vector3(-50.0, -135.0, 0.0), "sun_color": Color(1.0, 0.95, 0.88), "sun_energy": 1.3,
	"fill_color": Color(0.55, 0.72, 1.0), "fill_energy": 0.3,
	"ambient": Color(0.42, 0.5, 0.64), "ambient_sky": 0.45,
	"fog": Color(0.6, 0.74, 0.95), "fog_density": 0.003, "exposure": 0.92, "glow_threshold": 1.25,
	"floor": [Color(0.33, 0.36, 0.41), Color(0.28, 0.31, 0.36)], "floor_light": Color(0.25, 0.65, 1.0),
	"core": [Color(0.2, 0.25, 0.35), Color(0.17, 0.21, 0.3)], "core_light": Color(1.0, 0.55, 0.15),
	"wall": [Color(0.5, 0.55, 0.63), Color(0.43, 0.48, 0.56)], "wall_light": Color(0.2, 0.7, 1.0),
	"block": [Color(0.6, 0.63, 0.69), Color(0.52, 0.55, 0.61)],
	"dark": [Color(0.12, 0.16, 0.25), Color(0.1, 0.13, 0.2)], "dark_light": Color(0.25, 0.75, 1.0),
	"edge_neon": Color(0.15, 0.5, 0.9), "barrier": Color(0.4, 0.8, 1.0), "barrier_intensity": 0.3,
	"city_facade": Color(0.5, 0.58, 0.72), "city_window_a": Color(0.85, 0.92, 1.0), "city_window_b": Color(0.55, 0.8, 1.0),
	"city_windows": 0.2, "lamp": Color(1.3, 1.45, 1.6),
	"sign": Color(0.1, 0.45, 0.95, 0.95), "sign_sub": Color(1.0, 0.45, 0.15, 0.95),
}

const DUSK := {
	"sky_zenith": Color(0.04, 0.05, 0.16), "sky_mid": Color(0.22, 0.12, 0.35), "sky_horizon": Color(0.95, 0.42, 0.28),
	"sky_ground": Color(0.03, 0.03, 0.07), "sky_sun": Color(1.0, 0.6, 0.35), "stars": 0.9,
	"planet": Color(0.45, 0.55, 0.95), "planet_alpha": 1.0,
	"cloud": Color(1.24, 0.55, 0.44), "cloud_band": 0.45, "cloud_puffs": 0.0,
	"sun_rot": Vector3(-28.0, -125.0, 0.0), "sun_color": Color(1.0, 0.78, 0.62), "sun_energy": 1.35,
	"fill_color": Color(0.45, 0.6, 1.0), "fill_energy": 0.35,
	"ambient": Color(0.24, 0.28, 0.38), "ambient_sky": 0.3,
	"fog": Color(0.32, 0.24, 0.4), "fog_density": 0.003, "exposure": 1.05, "glow_threshold": 0.85,
	"floor": [Color(0.2, 0.22, 0.27), Color(0.15, 0.16, 0.2)], "floor_light": Color(0.2, 0.85, 1.0),
	"core": [Color(0.15, 0.16, 0.2), Color(0.11, 0.11, 0.15)], "core_light": Color(1.0, 0.45, 0.12),
	"wall": [Color(0.36, 0.4, 0.47), Color(0.28, 0.31, 0.37)], "wall_light": Color(0.2, 0.85, 1.0),
	"block": [Color(0.72, 0.75, 0.8), Color(0.6, 0.63, 0.69)],
	"dark": [Color(0.08, 0.09, 0.12), Color(0.06, 0.07, 0.09)], "dark_light": Color(1.0, 0.25, 0.7),
	"edge_neon": Color(0.15, 0.5, 0.8), "barrier": Color(0.25, 0.7, 1.0), "barrier_intensity": 0.55,
	"city_facade": Color(0.05, 0.06, 0.09), "city_window_a": Color(1.0, 0.7, 0.4), "city_window_b": Color(0.3, 0.8, 1.0),
	"city_windows": 1.6, "lamp": Color(2.2, 1.6, 1.1),
	"sign": Color(0.45, 0.95, 1.0, 0.9), "sign_sub": Color(1.0, 0.55, 0.25, 0.85),
}


static func current() -> Dictionary:
	return DUSK if int(Settings.get_value("arena_time")) == 1 else DAY


static func sky_material() -> ShaderMaterial:
	var t := current()
	var sm := ShaderMaterial.new()
	sm.shader = load("res://shaders/sky.gdshader")
	for k in [["zenith", "sky_zenith"], ["mid", "sky_mid"], ["horizon", "sky_horizon"], ["ground", "sky_ground"],
			["sun_color", "sky_sun"], ["planet_color", "planet"], ["cloud_color", "cloud"]]:
		var c: Color = t[k[1]]
		sm.set_shader_parameter(k[0], Vector3(c.r, c.g, c.b))
	sm.set_shader_parameter("star_density", t["stars"])
	sm.set_shader_parameter("planet_alpha", t["planet_alpha"])
	sm.set_shader_parameter("cloud_band", t["cloud_band"])
	sm.set_shader_parameter("cloud_puffs", t["cloud_puffs"])
	return sm


## Applies the palette's sky, ambient light, fog and exposure to an Environment and
## its sun / fill lights.
static func apply(env: Environment, sun: DirectionalLight3D, fill: DirectionalLight3D) -> void:
	var t := current()
	var sky := Sky.new()
	sky.sky_material = sky_material()
	sky.radiance_size = Sky.RADIANCE_SIZE_64
	sky.process_mode = Sky.PROCESS_MODE_QUALITY
	env.background_mode = Environment.BG_SKY
	env.sky = sky
	env.ambient_light_source = Environment.AMBIENT_SOURCE_SKY
	env.ambient_light_sky_contribution = t["ambient_sky"]
	env.ambient_light_color = t["ambient"]
	env.tonemap_exposure = t["exposure"]
	env.fog_light_color = t["fog"]
	env.fog_density = t["fog_density"]
	env.glow_hdr_threshold = t["glow_threshold"]
	if sun:
		sun.rotation_degrees = t["sun_rot"]
		sun.light_color = t["sun_color"]
		sun.light_energy = t["sun_energy"]
	if fill:
		fill.light_color = t["fill_color"]
		fill.light_energy = t["fill_energy"]
