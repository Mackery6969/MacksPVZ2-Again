extends EntityComponent
## Drains the zombies around it and grows tougher on what it takes -
## vamporcini. Once something comes near it feeds for a spell; plant food
## starts a longer feed over a wider patch.
##
## Config: dps (taken from each zombie), duration (one feed), radius (squares
## either side), max_toughness, plantfood_dps, plantfood_duration,
## plantfood_radius.

var _feed_left: float = 0.0
var _fed: bool = false


func _process(delta: float) -> void:
	if host.is_dead:
		return
	if _feed_left <= 0.0:
		_fed = false
		if _targets().is_empty():
			return
		_feed_left = float(cfg(&"duration", 6.0))
		host.play_art_once(&"attack")
	_feed_left -= delta
	var dps := float(cfg(&"plantfood_dps", 40.0) if _fed else cfg(&"dps", 40.0))
	var drained := 0.0
	for z in _targets():
		var before: float = z.health
		z.take_damage(dps * delta, host)
		drained += before - (z.health if is_instance_valid(z) else 0.0)
	if drained <= 0.0:
		return
	var cap := float(cfg(&"max_toughness", 6000.0))
	host.max_health = minf(cap, host.max_health + drained)
	host.heal(drained)


func _targets() -> Array:
	var radius := float(cfg(&"plantfood_radius", 2.5) if _fed else cfg(&"radius", 1.5))
	return host.board.hostile_zombies_near(host.row, host.position.x,
			2 if _fed else 1, radius)


func on_plantfood() -> bool:
	_fed = true
	_feed_left = float(cfg(&"plantfood_duration", 10.0))
	return true
