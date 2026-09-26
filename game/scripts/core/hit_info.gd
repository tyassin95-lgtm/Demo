class_name HitInfo
extends RefCounted
## Describes a single hit dealt to an Actor.

enum Reaction { NONE, FLINCH, STAGGER, KNOCKDOWN, LAUNCH }

var damage: float = 10.0
var source: Node = null
## Horizontal push direction (normalized, world space).
var direction: Vector3 = Vector3.FORWARD
var knockback: float = 0.0
var lift: float = 0.0
var reaction: int = Reaction.FLINCH
## Poise damage: accumulates toward a flinch for weapons that don't flinch outright.
var impact: float = 10.0
var hitstop: float = 0.0
var position: Vector3 = Vector3.ZERO
var is_melee: bool = false
var weapon_id: String = ""
var color: Color = Color(0.3, 0.9, 1.0)
var is_explosion: bool = false


static func make(dmg: float, src: Node, dir: Vector3, react: int) -> HitInfo:
	var h := HitInfo.new()
	h.damage = dmg
	h.source = src
	h.direction = dir
	h.reaction = react
	return h
