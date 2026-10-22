extends EntityComponent
## Attached to a zombie a solar sage converted. It drops sun on a timer as it
## wanders off, and now and then converts a hostile zombie it passes.
##
## Config: sun_value, interval, interval_max, infect_chance.

var _timer: float = 0.0


func setup() -> void:
	_timer = cfg_range(&"interval", 10.0)


func _process(delta: float) -> void:
	if host.is_dead:
		return
	_timer -= delta
	if _timer > 0.0:
		return
	_timer = cfg_range(&"interval", 10.0)
	for i in ceili(int(cfg(&"sun_value", 50)) / float(SunToken.VALUE)):
		host.board.drop_sun(host.position)
	if randf() >= float(cfg(&"infect_chance", 0.2)):
		return
	var half: float = host.board.cell_size.x
	for z in host.board.hostile_zombies_in_row(host.row):
		if absf(z.position.x - host.position.x) <= half \
				and z.has_tag(&"enlightenable") and z.component(&"sun_trail") == null:
			z.charm()
			z.peaceful = true
			z.scale_aggression(host.speed / maxf(z.speed, 0.01), 0.0)
			z.attach_component(&"sun_trail", config)
			return
