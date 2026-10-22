extends EntityComponent
## Bounces back the first zombie to reach it, then has to rest - spring bean.
##
## Config: distance (squares knocked back), rest, reach (squares either side),
## require_tags.

var _rest: float = 0.0


func _process(delta: float) -> void:
	if host.is_dead:
		return
	if _rest > 0.0:
		_rest -= delta
		host.set_runtime_tag(&"resting", _rest > 0.0)
		return
	var reach: float = float(cfg(&"reach", 0.5)) * host.board.cell_size.x
	for z in host.board.hostile_zombies_in_row(host.row):
		if absf(z.position.x - host.position.x) <= reach \
				and z.matches(cfg(&"require_tags", [&"knockbackable"])):
			_bounce([z])
			return


func _bounce(zombies: Array) -> void:
	Audio.play(&"plant.spring", host.position)
	host.play_art_once(&"attack")
	for z in zombies:
		z.knock_back(float(cfg(&"distance", 1.0)))
	_rest = scaled(float(cfg(&"rest", 10.0)))
	host.set_runtime_tag(&"resting", true)


## Plant food: wake up and bounce everything in the 3x3 around it.
func on_plantfood() -> bool:
	var near: Array = []
	for z in host.board.hostile_zombies_near(host.row, host.position.x, 1, 1.5):
		if z.matches(cfg(&"require_tags", [&"knockbackable"])):
			near.append(z)
	_bounce(near)
	return true
