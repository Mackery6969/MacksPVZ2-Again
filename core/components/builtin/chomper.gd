extends EntityComponent
## Swallows the zombie in front of it whole, then has to chew before it can
## eat again - chomper, toadstool.
##
## A zombie it cannot swallow (anything without the `swallowable` tag - a
## gargantuar, a mech) gets bitten for `fail_damage` instead. Each swallowed
## zombie is chewed separately, so a chomper with room for two can take a
## second bite while the first is still going down.
##
## Config: reach (squares in front), capacity, chew_time, fail_damage,
## interval between bites, require_tags, sun_per_zombie (a toadstool turns
## its meal into sun), plantfood_swallows, plantfood_reach.

var reach: float = 2.0
var capacity: int = 2
var chew_time: float = 17.0
var fail_damage: float = 100.0
var interval: float = 1.0
var sun_per_zombie: int = 0

var _chewing: Array[float] = []
var _cooldown: float = 0.0


func setup() -> void:
	reach = float(cfg(&"reach", reach))
	capacity = int(cfg(&"capacity", capacity))
	chew_time = float(cfg(&"chew_time", chew_time))
	fail_damage = float(cfg(&"fail_damage", fail_damage))
	interval = float(cfg(&"interval", interval))
	sun_per_zombie = int(cfg(&"sun_per_zombie", 0))


func _process(delta: float) -> void:
	if host.is_dead:
		return
	_digest(delta)
	_cooldown -= delta
	if _cooldown > 0.0 or _chewing.size() >= capacity:
		return
	var prey := _prey()
	if prey == null:
		return
	_bite(prey)
	_cooldown = scaled(interval)


func _digest(delta: float) -> void:
	if _chewing.is_empty():
		return
	var still: Array[float] = []
	for left in _chewing:
		left -= delta
		if left > 0.0:
			still.append(left)
		elif sun_per_zombie > 0:
			for i in ceili(sun_per_zombie / float(SunToken.VALUE)):
				host.board.drop_sun(host.position + Vector2(i * 16.0, 0))
	_chewing = still
	host.set_runtime_tag(&"chewing", not _chewing.is_empty())


## Whatever stands nearest in front, within reach. Gravestones in the way are
## bitten too, since a chomper facing a grave is otherwise stuck.
func _prey() -> Character:
	var span: float = reach * host.board.cell_size.x
	for t in host.board.plant_targets_in_row(host.row):
		var ahead: float = t.position.x - host.position.x
		if ahead >= -host.board.cell_size.x * 0.25 and ahead <= span:
			return t
	return null


func _bite(prey: Character) -> void:
	host.play_art_once(&"attack")
	Audio.play(&"plant.chomp", host.position)
	if prey is Zombie and prey.matches(cfg(&"require_tags", [&"swallowable"])):
		_swallow(prey)
	else:
		prey.take_damage(fail_damage, host)


func _swallow(prey: Zombie) -> void:
	# Swallowed is gone, not killed: armour does not get a say.
	prey.die()
	if chew_time > 0.0:
		_chewing.append(scaled(chew_time))
		host.set_runtime_tag(&"chewing", true)


## Plant food: swallow several zombies in the lane at once, chewing nothing.
func on_plantfood() -> bool:
	var count := int(cfg(&"plantfood_swallows", 4))
	var span: float = float(cfg(&"plantfood_reach", 9.0)) * host.board.cell_size.x
	var eaten := 0
	for z in host.board.hostile_zombies_in_row(host.row):
		if eaten >= count:
			break
		if z.position.x < host.position.x - host.board.cell_size.x * 0.5:
			continue
		if z.position.x - host.position.x > span:
			break
		if z.matches(cfg(&"require_tags", [&"swallowable"])):
			z.die()
			eaten += 1
	_chewing.clear()
	host.set_runtime_tag(&"chewing", false)
	return true
