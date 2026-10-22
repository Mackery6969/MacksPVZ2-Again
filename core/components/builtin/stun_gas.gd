extends EntityComponent
## Attached to a zombie that ate a chili bean. It stands still for `delay`,
## then lets off gas that stuns every zombie from it to the back of the lane
## for `duration`, and dies.
##
## Config: delay, duration.

var _timer: float = 0.0


func setup() -> void:
	_timer = float(cfg(&"delay", 2.0))
	host.apply_stun(_timer + 0.1)
	host.set_runtime_tag(&"gassy", true)


func _process(delta: float) -> void:
	if host.is_dead:
		return
	_timer -= delta
	if _timer > 0.0:
		return
	Audio.play(&"plant.gas", host.position)
	var from: float = host.position.x - host.board.cell_size.x * 0.5
	for z in host.board.hostile_zombies_in_row(host.row):
		if z != host and z.position.x >= from:
			z.apply_stun(float(cfg(&"duration", 10.0)))
	host.die()
