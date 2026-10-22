extends EntityComponent
## Bursts damage over the 3x3 around it on a timer while anything is there -
## gloom-shroom. While it is shadow powered its gloom also poisons, and it
## passes the power on to its neighbours as it fires.
##
## Config: interval, dps, duration (each burst), radius (squares either
## side), poison_dps, plantfood_dps, plantfood_duration.

var _cooldown: float = 0.0
var _burst_left: float = 0.0
var _food_left: float = 0.0


func _process(delta: float) -> void:
	if host.is_dead:
		return
	var fed := _food_left > 0.0
	if fed:
		_food_left -= delta
	_cooldown -= delta
	if _burst_left <= 0.0 and not fed:
		if _cooldown > 0.0 or _targets().is_empty():
			return
		_burst_left = float(cfg(&"duration", 0.5))
		_cooldown = scaled(float(cfg(&"interval", 1.5)))
		host.play_art_once(&"attack")
	_burst_left -= delta
	var dps := float(cfg(&"plantfood_dps", 1543.0)) if fed else float(cfg(&"dps", 100.0))
	var powered: bool = host.has_tag(&"shadow_powered")
	for t in _targets():
		t.take_damage(dps * delta, host)
		if powered and t is Zombie:
			t.apply_poison(float(cfg(&"poison_dps", 60.0)), 0.5)
	if powered:
		_power_neighbours()


func _targets() -> Array:
	var radius := float(cfg(&"radius", 1.5))
	var out: Array = host.board.hostile_zombies_near(host.row, host.position.x, 1, radius)
	for r in range(maxi(0, host.row - 1), mini(host.board.rows, host.row + 2)):
		for g in host.board.graves_in_row(r):
			if absf(g.position.x - host.position.x) <= radius * host.board.cell_size.x:
				out.append(g)
	return out


func _power_neighbours() -> void:
	for r in range(maxi(0, host.row - 1), mini(host.board.rows, host.row + 2)):
		for c in range(maxi(0, host.col - 1), mini(host.board.cols, host.col + 2)):
			var p: Plant = host.board.plant_at(r, c)
			if p != null and p != host and p.has_tag(&"family:shadow"):
				p.add_timed_tag(&"shadow_powered", 1.0)


func on_plantfood() -> bool:
	_food_left = float(cfg(&"plantfood_duration", 3.0))
	return true
