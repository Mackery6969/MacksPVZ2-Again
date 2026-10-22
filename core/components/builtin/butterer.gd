extends EntityComponent
## Butters whatever is eating it, stunning the eater and stinging it -
## buttercup. Plant food butters every zombie on the lawn.
##
## Config: damage, duration (stun), interval (between butters),
## plantfood_damage.

var _timer: float = 0.0


func _process(delta: float) -> void:
	if host.is_dead:
		return
	_timer -= delta
	if _timer > 0.0:
		return
	var eaters := _eaters()
	if eaters.is_empty():
		return
	_timer = scaled(float(cfg(&"interval", 1.0)))
	host.play_art_once(&"attack")
	for z in eaters:
		_butter(z, float(cfg(&"damage", 100.0)))


func _eaters() -> Array:
	var out: Array = []
	for z in host.board.hostile_zombies_in_row(host.row):
		if z.target == host and not z.is_stunned():
			out.append(z)
	return out


func _butter(z: Zombie, damage: float) -> void:
	z.apply_stun(float(cfg(&"duration", 8.0)))
	if z.is_stunned():
		z.add_timed_tag(&"buttered", float(cfg(&"duration", 8.0)))
	z.take_damage(damage, host)


func on_plantfood() -> bool:
	for z in host.board.all_hostile_zombies():
		_butter(z, float(cfg(&"plantfood_damage", 150.0)))
	return true
