extends EntityComponent
## Lights the squares around it - plantern, glowkengu. Lit squares are what a
## fog system clears and where hidden zombies show; the board answers
## `Board.is_lit` from every light on the lawn.
##
## Plant food: a plantern makes every zombie on the lawn carry sun to drop
## when it dies; a glowkengu shines wider for a while.
##
## Config: radius (squares either side), plantfood_radius,
## plantfood_duration, plantfood_sun (sun handed to each zombie).

var _boost_left: float = 0.0


func setup() -> void:
	host.set_runtime_tag(&"light", true)


func _process(delta: float) -> void:
	if _boost_left > 0.0:
		_boost_left -= delta


func radius() -> int:
	if _boost_left > 0.0:
		return int(cfg(&"plantfood_radius", cfg(&"radius", 1)))
	return int(cfg(&"radius", 1))


func lights(row: int, col: int) -> bool:
	var r := radius()
	return absi(row - host.row) <= r and absi(col - host.col) <= r


func on_plantfood() -> bool:
	var sun := int(cfg(&"plantfood_sun", 0))
	if sun > 0:
		for z in host.board.all_hostile_zombies():
			z.set_meta(&"carried_sun", maxi(sun, int(z.get_meta(&"carried_sun", 0))))
			z.set_runtime_tag(&"carrying_sun", true)
	_boost_left = float(cfg(&"plantfood_duration", 0.0))
	return sun > 0 or _boost_left > 0.0
