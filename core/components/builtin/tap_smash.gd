extends EntityComponent
## Tap it to flatten the first zombie in front of it - the rhythm phat beet.
## Anything already worn down to almost nothing in its square goes too.
##
## Config: reach (squares in front), min_health (it only smashes zombies with
## more than this; weaker ones in its square are finished on their own),
## cooldown.

var _cooldown: float = 0.0


func setup() -> void:
	host.set_runtime_tag(&"tap_to_fire", true)


func _process(delta: float) -> void:
	if _cooldown > 0.0:
		_cooldown -= delta


func on_tapped() -> bool:
	if host.is_dead or _cooldown > 0.0:
		return false
	_cooldown = float(cfg(&"cooldown", 0.25))
	var reach: float = float(cfg(&"reach", 2.0)) * host.board.cell_size.x
	var floor_hp := float(cfg(&"min_health", 50.0))
	var hit := false
	for z in host.board.hostile_zombies_in_row(host.row):
		var ahead: float = z.position.x - host.position.x
		if ahead < -host.board.cell_size.x * 0.5 or ahead > reach:
			continue
		if z.health > floor_hp and not hit:
			z.die()
			hit = true
		elif absf(ahead) <= host.board.cell_size.x * 0.5 and z.health <= floor_hp:
			z.die()
	host.play_art_once(&"attack")
	Audio.play(&"plant.squash", host.position)
	return true
