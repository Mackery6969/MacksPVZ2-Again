extends EntityComponent
## Puffs perfume over the 3x3 around it as soon as a zombie comes near, slowing
## everything caught in it, and is spent - stallia. Plant food perfumes every
## zombie on the lawn.
##
## Config: duration, slow (speed factor), trigger_width (squares either side),
## radius (squares either side of the cloud), plantfood_duration.

func _process(_delta: float) -> void:
	if host.is_dead:
		return
	var reach: float = float(cfg(&"trigger_width", 0.25)) * host.board.cell_size.x
	for z in host.board.hostile_zombies_in_row(host.row):
		if absf(z.position.x - host.position.x) <= reach:
			_puff(host.board.hostile_zombies_near(host.row, host.position.x, 1,
					float(cfg(&"radius", 1.5))), float(cfg(&"duration", 12.0)))
			host.die()
			return


func _puff(zombies: Array, seconds: float) -> void:
	Audio.play(&"plant.perfume", host.position)
	for z in zombies:
		z.apply_slow(float(cfg(&"slow", 0.5)), seconds)


func on_plantfood() -> bool:
	_puff(host.board.all_hostile_zombies(), float(cfg(&"plantfood_duration", 12.0)))
	return true
