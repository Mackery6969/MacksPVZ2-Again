extends EntityComponent
## A gimmick: the zombie periodically damages plants near it without stopping
## to eat, so cover alone does not save them.
##
## Config: radius (cells), interval (seconds), damage.

var radius: float = 1.5
var interval: float = 3.0
var damage: float = 25.0

var _timer: float = 0.0


func setup() -> void:
	radius = float(cfg(&"radius", 1.5))
	interval = float(cfg(&"interval", 3.0))
	damage = float(cfg(&"damage", 25.0))
	_timer = interval


func _process(delta: float) -> void:
	# A charmed zombie fights for the player, so it must not hurt their plants.
	if host.is_dead or host.is_charmed():
		return
	_timer -= delta
	if _timer > 0.0:
		return
	_timer = interval

	var reach: float = radius * host.board.cell_size.x
	var hit := false
	for col in host.board.cols:
		var plant = host.board.plant_at(host.row, col)
		if plant != null and not plant.is_dead \
				and absf(plant.position.x - host.position.x) <= reach:
			plant.take_damage(damage, host)
			hit = true
	if hit:
		Audio.play(&"overhaul.pulse", host.position)
