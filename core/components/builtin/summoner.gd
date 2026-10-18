extends EntityComponent
## Calls more zombies onto the lane, once or on a timer.
##
## Two things in PopCap's data summon, and they behave differently. An abbot
## shouts once as it becomes the wave's flag zombie and a group walks on;
## a gong or a bronze statue keeps calling at an interval. `once` picks
## between them, and the importer sets it from whether an interval was stated.
##
## Config: zombies, count, first_delay, interval, distance, once, each
## (summon one of every type listed instead of `count` random picks).

var zombies: Array = []
var once: bool = false
var each: bool = false
var distance: float = 0.0

var _timer: float = 0.0
var _spent: bool = false


func setup() -> void:
	for id in (cfg(&"zombies", []) as Array):
		zombies.append(StringName(id))
	once = bool(cfg(&"once", false))
	each = bool(cfg(&"each", false))
	_timer = scaled(cfg_range(&"first_delay", 1.0 if once else 8.0))
	# A summoned zombie does not summon. An abbot's list contains abbots, so
	# without this one wave would become every wave.
	if host.has_tag(&"summoned"):
		_spent = true


func _process(delta: float) -> void:
	if _spent or host.is_dead or zombies.is_empty():
		return
	_timer -= delta
	if _timer > 0.0:
		return
	_summon()
	if once:
		_spent = true
	else:
		_timer = scaled(cfg_range(&"interval", 8.0))


func _summon() -> void:
	Audio.play(&"zombie.summon", host.position)
	var calls: Array = zombies.duplicate() if each else []
	if not each:
		for _i in range(maxi(1, int(cfg_range(&"count", 1.0)))):
			calls.append(zombies[randi() % zombies.size()])
	for id: StringName in calls:
		var lanes := cfg_range(&"distance", distance)
		var at: float = host.position.x \
				- host.direction() * lanes * host.board.cell_size.x
		var called: Zombie = host.board.spawn_zombie_at(id, host.row, at,
				[&"summoned"])
		if called == null:
			continue
		called.set_allegiance(host.allegiance)
