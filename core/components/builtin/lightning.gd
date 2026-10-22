extends EntityComponent
## Calls down a lightning bolt on a zombie somewhere on the lawn every so
## often - electric blueberry. Which zombie is a weighted draw: ordinary
## zombies most often, gargantuars least.
##
## Config: damage, interval, first_delay, targets, weight_normal,
## weight_gargantuar, weight_other, plantfood_targets.

var _timer: float = 0.0


func setup() -> void:
	_timer = float(cfg(&"first_delay", 10.0))


func _process(delta: float) -> void:
	if host.is_dead:
		return
	_timer -= delta
	if _timer > 0.0:
		return
	if _strike(int(cfg(&"targets", 1))) > 0:
		_timer = scaled(float(cfg(&"interval", 12.0)))


## -> how many zombies were struck.
func _strike(count: int) -> int:
	var pool: Array = host.board.all_hostile_zombies()
	var struck := 0
	while struck < count and not pool.is_empty():
		var z: Zombie = _draw_one(pool)
		pool.erase(z)
		Audio.play(&"plant.lightning", z.position)
		z.take_damage(float(cfg(&"damage", 5000.0)), host)
		struck += 1
	if struck > 0:
		host.play_art_once(&"attack")
	return struck


func _draw_one(pool: Array) -> Zombie:
	var weights: Array[float] = []
	var total := 0.0
	for z in pool:
		var w := float(cfg(&"weight_other", 40.0))
		if (z.def is ZombieDef and z.def.sort == &"Gargantuar") \
				or z.component(&"smasher") != null:
			w = float(cfg(&"weight_gargantuar", 5.0))
		elif z.component(&"armor") == null and z.component(&"summoner") == null:
			w = float(cfg(&"weight_normal", 55.0))
		weights.append(w)
		total += w
	var roll := randf() * total
	for i in pool.size():
		roll -= weights[i]
		if roll <= 0.0:
			return pool[i]
	return pool[-1]


func on_plantfood() -> bool:
	return _strike(int(cfg(&"plantfood_targets", 3))) > 0
