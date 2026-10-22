extends EntityComponent
## Converts the zombie that reaches it: the zombie gives up, turns round and
## wanders off the lawn, dropping sun as it goes - solar sage. Everything in
## its square is converted at once, and the sage is spent after `uses`.
##
## Config: uses, sun_value, walk_speed (squares per second), produce_interval
## and produce_interval_max, infect_chance, plantfood_count.

var uses: int = 1


func setup() -> void:
	uses = int(cfg(&"uses", 1))


func _process(_delta: float) -> void:
	if host.is_dead:
		return
	var half: float = host.board.cell_size.x * 0.5
	var caught: Array = []
	for z in host.board.hostile_zombies_in_row(host.row):
		if absf(z.position.x - host.position.x) <= half and _convertible(z):
			caught.append(z)
	if caught.is_empty():
		return
	for z in caught:
		convert_zombie(z)
	host.play_art_once(&"attack")
	uses -= 1
	if uses <= 0:
		host.die()


func _convertible(z: Zombie) -> bool:
	return z.has_tag(&"enlightenable") and z.component(&"zomboss") == null \
			and z.component(&"sun_trail") == null


func convert_zombie(z: Zombie) -> void:
	Audio.play(&"plant.enlighten", z.position)
	z.charm()
	z.peaceful = true
	z.scale_aggression(float(cfg(&"walk_speed", 0.3)) / maxf(z.speed, 0.01), 0.0)
	z.attach_component(&"sun_trail", {
		"sun_value": int(cfg(&"sun_value", 50)),
		"interval": float(cfg(&"produce_interval", 10.0)),
		"interval_max": float(cfg(&"produce_interval_max", 14.0)),
		"infect_chance": float(cfg(&"infect_chance", 0.2)),
	})


## Plant food: reach out and convert several zombies anywhere on the lawn.
func on_plantfood() -> bool:
	var pool: Array = host.board.all_hostile_zombies().filter(_convertible)
	pool.shuffle()
	for z in pool.slice(0, int(cfg(&"plantfood_count", 3))):
		convert_zombie(z)
	return true
