extends EntityComponent
## Blows light zombies off the lawn outright and is spent doing it - blover.
##
## PVZGE's data marks almost everything `carriable`, gargantuars included, so
## the tag alone is too permissive to be the whole rule. Weight decides what
## the wind can actually lift, which keeps the heavy end on the ground without
## needing a tag per zombie.
##
## Config: duration, require_tags, max_weight (0 disables the weight check).

var duration: float = 3.0
var max_weight: float = 2000.0

var _fired: bool = false


func setup() -> void:
	duration = float(cfg(&"duration", 3.0))
	max_weight = float(cfg(&"max_weight", 2000.0))


func _process(_delta: float) -> void:
	if _fired or host.is_dead:
		return
	_fired = true
	var required: Array = cfg(&"require_tags", [&"carriable"])
	var blown := 0
	for row in host.board.rows:
		for z in host.board.hostile_zombies_in_row(row):
			if not z.matches(required):
				continue
			if max_weight > 0.0 and float(z.def.stat(&"weight", 0.0)) > max_weight:
				continue      # too heavy for the wind to take
			z.take_damage(z.health + 1.0, host)
			blown += 1
	if blown > 0:
		Audio.play(&"plant.explode", host.position)
	host.die()
