extends EntityComponent
## Goes off once on placement, then is spent - cherry bomb, jalapeno, squash.
##
## Config: damage, radius (cells), poison_dps, poison_duration, delay.

var damage: float = 1800.0
var radius: float = 1.5
var delay: float = 0.6

var _timer: float = 0.0
var _fired: bool = false


func setup() -> void:
	damage = float(cfg(&"damage", 1800.0))
	radius = float(cfg(&"radius", 1.5))
	delay = float(cfg(&"delay", 0.6))
	_timer = delay


func _process(delta: float) -> void:
	if _fired or host.is_dead:
		return
	_timer -= delta
	if _timer > 0.0:
		return
	_fired = true
	_detonate()


func _detonate() -> void:
	var reach: float = radius * host.board.cell_size.x
	var poison := float(cfg(&"poison_dps", 0.0))
	var poison_time := float(cfg(&"poison_duration", 0.0))
	for row in host.board.rows:
		# A radius crosses lanes, so neighbours are in range too.
		if absi(row - host.row) > int(radius):
			continue
		for z in host.board.hostile_zombies_in_row(row):
			if absf(z.position.x - host.position.x) > reach:
				continue
			z.take_damage(damage, host)
			if poison > 0.0 and poison_time > 0.0:
				# Modelled as a slow plus the damage already dealt, until
				# there is a damage-over-time status to hang this on.
				z.apply_slow(0.75, poison_time)
	Audio.play(&"plant.explode", host.position)
	host.die()


## Plant food: a bigger blast, and it still only goes off once.
func on_plantfood() -> bool:
	if _fired:
		return false
	damage *= 2.0
	radius += 1.0
	_timer = 0.0
	return true
