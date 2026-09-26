extends Node
## Input driver that does nothing (lets tests position the player freely).

func drive(p: Player, _dt: float) -> void:
	p.input_move = Vector2.ZERO
	p.sprinting = false
	p.attack_held = false
