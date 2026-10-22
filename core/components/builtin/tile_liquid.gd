extends EntityComponent
## A puddle that works on the zombies standing in it: butter, goo, cranberry
## jelly, sap, molten pools and lava.
##
## One component rather than one per liquid, because they differ only in their
## numbers - PVZGE's own TileLiquid subclasses each override a single update.
##
## Config, any combination of:
##   lifespan    - seconds before the puddle dries up (omit to keep it)
##   damage, interval - a hit of `damage` to every zombie in it, every `interval`
##   dps         - continuous damage per second
##   poison_dps  - damage per second that keeps going for `slow` seconds after
##   slow        - seconds of half speed each tick a zombie is in it
##   butter      - stuns the first zombie to step in for this long, and is
##                 used up doing it

var _left: float = INF
var _hit_timer: float = 0.0


func setup() -> void:
	if cfg(&"lifespan") != null:
		_left = float(cfg(&"lifespan"))
	_hit_timer = float(cfg(&"interval", 0.5))


## Hostile zombies standing in this cell. Flying zombies pass over.
func zombies_in_cell() -> Array:
	var out: Array = []
	for z in host.board.hostile_zombies_in_row(host.row):
		if z.col == host.col and not z.has_tag(&"flying"):
			out.append(z)
	return out


func _process(delta: float) -> void:
	if host.is_dead:
		return
	_left -= delta
	if _left <= 0.0:
		host.die()
		return

	var inside := zombies_in_cell()
	if inside.is_empty():
		return

	var butter := float(cfg(&"butter", 0.0))
	if butter > 0.0:
		# Butter sticks to whoever is furthest along, then it is gone.
		var first: Zombie = inside[0]
		first.apply_stun(butter)
		host.die()
		return

	var dps := float(cfg(&"dps", 0.0)) + float(cfg(&"poison_dps", 0.0))
	var slow := float(cfg(&"slow", 0.0))
	for z in inside:
		if dps > 0.0:
			z.take_damage(dps * delta, host)
		if slow > 0.0:
			z.apply_slow(0.5, slow)

	var damage := float(cfg(&"damage", 0.0))
	if damage <= 0.0:
		return
	_hit_timer -= delta
	if _hit_timer > 0.0:
		return
	_hit_timer = float(cfg(&"interval", 0.5))
	for z in inside:
		z.take_damage(damage, host)
