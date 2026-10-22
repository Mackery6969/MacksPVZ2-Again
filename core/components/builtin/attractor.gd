extends EntityComponent
## Lures zombies in the neighbouring lanes into its own - sweet potato. Every
## few seconds each zombie close enough in a lane either side changes lanes
## toward it. Plant food widens the lure for a while.
##
## Config: interval, width (squares either side), plantfood_width,
## plantfood_duration, require_tags.

var _timer: float = 0.0
var _food_left: float = 0.0


func _process(delta: float) -> void:
	if host.is_dead:
		return
	if _food_left > 0.0:
		_food_left -= delta
	_timer -= delta
	if _timer > 0.0:
		return
	_timer = scaled(float(cfg(&"interval", 5.0)))
	_lure()


func _lure() -> int:
	var width := float(cfg(&"plantfood_width", 4.0) if _food_left > 0.0
			else cfg(&"width", 2.0))
	var moved := 0
	for z in host.board.hostile_zombies_near(host.row, host.position.x, 1, width):
		if z.row != host.row and z.matches(cfg(&"require_tags", [&"attractable"])):
			host.board.move_zombie_to_row(z, host.row)
			moved += 1
	return moved


func on_plantfood() -> bool:
	_food_left = float(cfg(&"plantfood_duration", 6.0))
	_timer = 0.0
	host.heal(host.max_health)
	return true
