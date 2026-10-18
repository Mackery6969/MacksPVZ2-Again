extends EntityComponent
## One-shot cold: damages and freezes everything nearby, then is spent -
## iceberg lettuce, chilly pepper.
##
## Config: damage, freeze_duration, chill_duration, radius (cells).

var damage: float = 0.0
var freeze_duration: float = 0.0
var chill_duration: float = 0.0
var radius: float = 1.5

var _fired: bool = false


func setup() -> void:
	damage = float(cfg(&"damage", 0.0))
	freeze_duration = float(cfg(&"freeze_duration", 0.0))
	chill_duration = float(cfg(&"chill_duration", 0.0))
	radius = float(cfg(&"radius", 1.5))


func _process(_delta: float) -> void:
	if _fired or host.is_dead:
		return
	# Waits for something worth freezing rather than firing into an empty lane.
	var reach: float = radius * host.board.cell_size.x
	for z in host.board.hostile_zombies_in_row(host.row):
		if absf(z.position.x - host.position.x) <= reach:
			_fire()
			return


func _fire() -> void:
	_fired = true
	var reach: float = radius * host.board.cell_size.x
	for row in host.board.rows:
		if absi(row - host.row) > int(radius):
			continue
		for z in host.board.hostile_zombies_in_row(row):
			if absf(z.position.x - host.position.x) > reach:
				continue
			if damage > 0.0:
				z.take_damage(damage, host)
			if freeze_duration > 0.0:
				z.apply_freeze(freeze_duration)
			elif chill_duration > 0.0:
				z.apply_slow(0.5, chill_duration)
	host.die()


func on_plantfood() -> bool:
	if _fired:
		return false
	radius += 1.0
	freeze_duration = maxf(freeze_duration, chill_duration) * 1.5
	_fire()
	return true
