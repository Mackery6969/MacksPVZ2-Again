extends EntityComponent
## Holds zombies in place on a cycle rather than hurting them.
##
## Config: duration of the stun, rest_time between stuns, radius (cells).

var duration: float = 2.0
var rest_time: float = 5.0
var radius: float = 1.5

var _rest: float = 0.0


func setup() -> void:
	duration = float(cfg(&"duration", 2.0))
	rest_time = float(cfg(&"rest_time", 5.0))
	radius = float(cfg(&"radius", 1.5))


func _process(delta: float) -> void:
	if host.is_dead:
		return
	if _rest > 0.0:
		_rest -= delta
		return

	var reach: float = radius * host.board.cell_size.x
	var caught := false
	for z in host.board.hostile_zombies_in_row(host.row):
		if absf(z.position.x - host.position.x) <= reach:
			z.apply_stun(duration)
			caught = true
	if caught:
		_rest = rest_time + duration
