extends EntityComponent
## A cloud that hangs over the 3x3 around it, stinging every zombie inside on
## a beat until it fades - noctarine. Shadow powered it stings harder, slows,
## and lingers longer, and it powers the shadow plants it covers.
##
## Config: damage, interval, lifespan, radius (squares either side),
## powered_damage, powered_interval, powered_lifespan, powered_slow.

var _age: float = 0.0
var _timer: float = 0.0


func _process(delta: float) -> void:
	if host.is_dead:
		return
	var powered: bool = host.has_tag(&"shadow_powered")
	_age += delta
	if _age >= float(cfg(&"powered_lifespan", 25.0) if powered else cfg(&"lifespan", 20.0)):
		host.die()
		return
	_power_neighbours()
	_timer -= delta
	if _timer > 0.0:
		return
	_timer = scaled(float(cfg(&"powered_interval", 0.5) if powered
			else cfg(&"interval", 0.5)))
	var damage := float(cfg(&"powered_damage", 30.0) if powered else cfg(&"damage", 20.0))
	for z in host.board.hostile_zombies_near(host.row, host.position.x, 1,
			float(cfg(&"radius", 1.5))):
		z.take_damage(damage, host)
		if powered and is_instance_valid(z) and not z.is_dead:
			z.apply_slow(float(cfg(&"powered_slow", 0.5)), 1.0)


func _power_neighbours() -> void:
	for r in range(maxi(0, host.row - 1), mini(host.board.rows, host.row + 2)):
		for c in range(maxi(0, host.col - 1), mini(host.board.cols, host.col + 2)):
			var p: Plant = host.board.plant_at(r, c)
			if p != null and p != host and p.has_tag(&"family:shadow"):
				p.add_timed_tag(&"shadow_powered", 0.5)
