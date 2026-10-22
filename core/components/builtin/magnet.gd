extends EntityComponent
## Pulls metal off zombies near it - magnet-shroom. It takes one piece of
## metal armor, then rests while it holds it. Plant food rips the metal off
## every zombie on the lawn and hurls each piece down its lane.
##
## Config: reach (squares either side), rows (lanes either side), rest,
## plantfood_damage.

var _rest_left: float = 0.0


func _process(delta: float) -> void:
	if host.is_dead:
		return
	if _rest_left > 0.0:
		_rest_left -= delta
		return
	var metal: Array = []
	for z in host.board.hostile_zombies_near(host.row, host.position.x,
			int(cfg(&"rows", 1)), float(cfg(&"reach", 3.5))):
		if _metal_on(z) != null:
			metal.append(z)
	if metal.is_empty():
		return
	_metal_on(metal.pick_random()).strip()
	Audio.play(&"plant.magnet", host.position)
	host.play_art_once(&"attack")
	_rest_left = scaled(float(cfg(&"rest", 10.0)))


static func _metal_on(z: Zombie) -> EntityComponent:
	for c in z.components():
		if c.has_method(&"strip") and c.is_metal and c.is_intact():
			return c
	return null


func on_plantfood() -> bool:
	var pulled := 0
	for z in host.board.all_hostile_zombies():
		var piece := _metal_on(z)
		while piece != null:
			piece.strip()
			pulled += 1
			var lane: Array = host.board.hostile_zombies_in_row(z.row)
			if not lane.is_empty():
				lane.pick_random().take_damage(float(cfg(&"plantfood_damage", 300.0)), host)
			if not is_instance_valid(z) or z.is_dead:
				break
			piece = _metal_on(z)
	_rest_left = 0.0
	return pulled > 0
