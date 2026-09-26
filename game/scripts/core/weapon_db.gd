class_name WeaponDB
extends RefCounted
## Static weapon and melee move definitions. All combat tuning lives here.

enum Kind { MELEE, HITSCAN, SHOTGUN, BEAM }
enum Secondary { NONE, HEAVY, GRENADE, BLAST_JUMP, SCOPE }


class Attack:
	extends RefCounted
	var id := ""
	var anim := ""
	var speed := 1.0
	var offset := 0.0
	## Action length in real seconds (after speed scaling).
	var duration := 0.5
	var hit_start := 0.1
	var hit_end := 0.25
	## Earliest time a buffered attack input chains into `next`.
	var chain_time := 0.2
	## Earliest time movement/dash can cancel the recovery.
	var cancel_time := 0.3
	var next := ""
	var recovery_anim := ""
	var damage := 10.0
	var reaction := HitInfo.Reaction.FLINCH
	var knockback := 3.0
	var lift := 0.0
	var impact := 30.0
	var hitstop := 0.06
	var reach := 2.6
	var arc_deg := 140.0
	var height := Vector2(-0.6, 2.4)
	var lunge_speed := 5.0
	var lunge_time := 0.12
	var stamina := 0.0
	var sfx := "blade_swing"
	## Slash VFX: roll angle of the arc (degrees) and whether it is drawn.
	var slash_roll := 0.0
	var slash_scale := 1.0
	var shake := 0.25
	var aoe := false
	var air_hang := false


class Weapon:
	extends RefCounted
	var id := ""
	var display_name := ""
	var short_name := ""
	var kind := Kind.MELEE
	var secondary := Secondary.NONE
	var color := Color(0.3, 0.95, 1.0)
	var model := ""
	var model_scale := 1.0
	## Weapon model transform relative to the right-hand bone.
	var grip_pos := Vector3.ZERO
	var grip_rot := Vector3.ZERO
	var fire_interval := 0.1
	var automatic := true
	var damage := 10.0
	var pellets := 1
	var spread_deg := 1.0
	var max_range := 80.0
	var falloff_start := 1000.0
	var mag_size := 30
	var reload_time := 1.4
	var reaction := HitInfo.Reaction.NONE
	var knockback := 0.0
	var impact := 6.0
	var hitstop := 0.0
	var pierce := false
	var recoil := 0.4
	var shake := 0.08
	var sfx := "rifle_shot"
	var secondary_cooldown := 1.0
	var aim_assist_deg := 4.0
	var tracer_width := 0.05
	var move_speed_mult := 1.0
	var combo: Dictionary = {}


static var _weapons := {}
static var _attacks := {}


static func weapon(id: String) -> Weapon:
	if _weapons.is_empty():
		_build()
	return _weapons.get(id)


static func attack(id: String) -> Attack:
	if _attacks.is_empty():
		_build()
	return _attacks.get(id)


static func _atk(id: String, anim: String, speed: float, duration: float, hit: Vector2, dmg: float) -> Attack:
	var a := Attack.new()
	a.id = id
	a.anim = anim
	a.speed = speed
	a.duration = duration
	a.hit_start = hit.x
	a.hit_end = hit.y
	a.damage = dmg
	_attacks[id] = a
	return a


static func _build() -> void:
	# --- Arc Blade melee moves ----------------------------------------------
	var a := _atk("blade_1", "Sword_Regular_A", 1.4, 0.31, Vector2(0.07, 0.2), 13)
	a.chain_time = 0.14
	a.cancel_time = 0.16
	a.next = "blade_2"
	a.recovery_anim = "Sword_Regular_A_Rec"
	a.lunge_speed = 7.0
	a.lunge_time = 0.12
	a.slash_roll = -12.0
	a.impact = 40.0
	a.knockback = 2.5

	a = _atk("blade_2", "Sword_Regular_B", 1.4, 0.38, Vector2(0.09, 0.25), 15)
	a.chain_time = 0.18
	a.cancel_time = 0.2
	a.next = "blade_3"
	a.recovery_anim = "Sword_Regular_B_Rec"
	a.lunge_speed = 8.0
	a.lunge_time = 0.14
	a.slash_roll = 160.0
	a.impact = 40.0
	a.knockback = 3.0
	a.sfx = "blade_swing"

	a = _atk("blade_3", "Sword_Regular_C", 1.45, 0.95, Vector2(0.25, 0.47), 24)
	a.chain_time = 0.72
	a.cancel_time = 0.62
	a.next = "blade_1"
	a.reaction = HitInfo.Reaction.KNOCKDOWN
	a.knockback = 9.0
	a.lift = 6.0
	a.hitstop = 0.11
	a.lunge_speed = 10.0
	a.lunge_time = 0.3
	a.slash_roll = 70.0
	a.slash_scale = 1.35
	a.reach = 3.0
	a.shake = 0.5
	a.sfx = "blade_swing_big"

	a = _atk("blade_dash", "Sword_Dash", 1.55, 0.72, Vector2(0.06, 0.4), 22)
	a.chain_time = 0.5
	a.cancel_time = 0.45
	a.next = "blade_2"
	a.reaction = HitInfo.Reaction.STAGGER
	a.knockback = 8.0
	a.hitstop = 0.09
	a.lunge_speed = 19.0
	a.lunge_time = 0.3
	a.reach = 2.8
	a.arc_deg = 120.0
	a.slash_roll = -5.0
	a.slash_scale = 1.2
	a.shake = 0.35
	a.sfx = "blade_swing_big"

	a = _atk("blade_heavy", "Sword_Attack", 1.5, 0.82, Vector2(0.2, 0.46), 28)
	a.chain_time = 0.62
	a.cancel_time = 0.55
	a.reaction = HitInfo.Reaction.KNOCKDOWN
	a.knockback = 11.0
	a.lift = 7.5
	a.hitstop = 0.12
	a.reach = 3.4
	a.arc_deg = 360.0
	a.lunge_speed = 3.0
	a.lunge_time = 0.2
	a.stamina = 25.0
	a.slash_roll = 0.0
	a.slash_scale = 1.6
	a.shake = 0.6
	a.aoe = true
	a.sfx = "blade_heavy"

	a = _atk("blade_air", "Sword_Regular_A", 1.3, 0.34, Vector2(0.07, 0.22), 14)
	a.chain_time = 0.16
	a.cancel_time = 0.2
	a.next = "blade_plunge"
	a.lunge_speed = 4.0
	a.lunge_time = 0.1
	a.slash_roll = -20.0
	a.air_hang = true
	a.impact = 45.0

	a = _atk("blade_plunge", "Melee_Hook", 0.9, 0.9, Vector2(0.0, 0.0), 22)
	a.reaction = HitInfo.Reaction.KNOCKDOWN
	a.knockback = 8.0
	a.lift = 5.0
	a.hitstop = 0.1
	a.reach = 3.6
	a.arc_deg = 360.0
	a.aoe = true
	a.shake = 0.7
	a.sfx = "blade_swing_big"

	# Enemy "Brute" slam (uses the heavy-combo animation segment).
	a = _atk("brute_slam", "Sword_Attack", 1.0, 1.35, Vector2(0.5, 0.72), 26)
	a.reaction = HitInfo.Reaction.KNOCKDOWN
	a.knockback = 10.0
	a.lift = 6.0
	a.hitstop = 0.12
	a.reach = 3.8
	a.arc_deg = 360.0
	a.aoe = true
	a.lunge_speed = 2.0
	a.lunge_time = 0.3
	a.shake = 0.7
	a.sfx = "blade_heavy"

	# --- Weapons ---------------------------------------------------------------
	var w := Weapon.new()
	w.id = "arc_blade"
	w.display_name = "ARC BLADE"
	w.short_name = "BLADE"
	w.kind = Kind.MELEE
	w.secondary = Secondary.HEAVY
	w.color = Color(0.25, 0.95, 1.0)
	w.combo = {"ground": "blade_1", "dash": "blade_dash", "air": "blade_air", "heavy": "blade_heavy"}
	w.move_speed_mult = 1.05
	_weapons[w.id] = w

	w = Weapon.new()
	w.id = "pulse_rifle"
	w.display_name = "PULSE RIFLE"
	w.short_name = "RIFLE"
	w.kind = Kind.HITSCAN
	w.secondary = Secondary.GRENADE
	w.color = Color(0.35, 0.8, 1.0)
	w.model = "res://assets/weapons/Gun_Rifle.gltf"
	w.model_scale = 0.85
	w.fire_interval = 0.095
	w.automatic = true
	w.damage = 8.0
	w.spread_deg = 1.1
	w.max_range = 90.0
	w.falloff_start = 45.0
	w.mag_size = 32
	w.reload_time = 1.35
	w.impact = 7.0
	w.recoil = 0.35
	w.shake = 0.05
	w.sfx = "rifle_shot"
	w.secondary_cooldown = 6.0
	w.aim_assist_deg = 5.0
	_weapons[w.id] = w

	w = Weapon.new()
	w.id = "scatter_cannon"
	w.display_name = "SCATTER CANNON"
	w.short_name = "SCATTER"
	w.kind = Kind.SHOTGUN
	w.secondary = Secondary.BLAST_JUMP
	w.color = Color(1.0, 0.55, 0.15)
	w.model = "res://assets/weapons/Gun_Revolver.gltf"
	w.model_scale = 1.35
	w.fire_interval = 0.7
	w.automatic = false
	w.damage = 8.0
	w.pellets = 9
	w.spread_deg = 6.5
	w.max_range = 26.0
	w.falloff_start = 9.0
	w.mag_size = 6
	w.reload_time = 1.6
	w.reaction = HitInfo.Reaction.STAGGER
	w.knockback = 7.0
	w.impact = 9.0
	w.hitstop = 0.05
	w.recoil = 1.4
	w.shake = 0.3
	w.sfx = "scatter_shot"
	w.secondary_cooldown = 1.1
	w.aim_assist_deg = 7.0
	w.tracer_width = 0.035
	_weapons[w.id] = w

	w = Weapon.new()
	w.id = "rail_lancer"
	w.display_name = "RAIL LANCER"
	w.short_name = "RAIL"
	w.kind = Kind.BEAM
	w.secondary = Secondary.SCOPE
	w.color = Color(0.75, 0.4, 1.0)
	w.model = "res://assets/weapons/Gun_Sniper.gltf"
	w.model_scale = 0.72
	w.fire_interval = 0.95
	w.automatic = false
	w.damage = 58.0
	w.max_range = 160.0
	w.mag_size = 5
	w.reload_time = 1.9
	w.reaction = HitInfo.Reaction.STAGGER
	w.knockback = 6.0
	w.impact = 60.0
	w.hitstop = 0.07
	w.pierce = true
	w.recoil = 1.8
	w.shake = 0.35
	w.sfx = "rail_shot"
	w.secondary_cooldown = 0.25
	w.aim_assist_deg = 3.0
	w.tracer_width = 0.12
	w.move_speed_mult = 0.95
	_weapons[w.id] = w

	# Enemy variants (lower damage so fights feel fair on a touchscreen).
	w = Weapon.new()
	w.id = "enemy_rifle"
	w.display_name = "RIFLE"
	w.kind = Kind.HITSCAN
	w.color = Color(1.0, 0.35, 0.25)
	w.model = "res://assets/weapons/Gun_Rifle.gltf"
	w.model_scale = 0.85
	w.fire_interval = 0.16
	w.damage = 3.5
	w.spread_deg = 2.6
	w.max_range = 70.0
	w.mag_size = 12
	w.reload_time = 1.8
	w.impact = 5.0
	w.sfx = "rifle_shot"
	_weapons[w.id] = w

	w = Weapon.new()
	w.id = "enemy_blade"
	w.display_name = "BLADE"
	w.kind = Kind.MELEE
	w.color = Color(1.0, 0.3, 0.2)
	w.combo = {"ground": "blade_1", "dash": "blade_dash", "air": "blade_air", "heavy": "blade_heavy"}
	_weapons[w.id] = w

	w = Weapon.new()
	w.id = "enemy_heavy"
	w.display_name = "BREAKER"
	w.kind = Kind.MELEE
	w.color = Color(1.0, 0.2, 0.7)
	w.combo = {"ground": "brute_slam", "heavy": "brute_slam"}
	_weapons[w.id] = w
