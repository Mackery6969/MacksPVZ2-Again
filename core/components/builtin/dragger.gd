extends EntityComponent
## Grabs the zombie in front of it and drags it under - tangle kelp in the
## water, grimrose in the dirt.
##
## A zombie with the `draggable` tag is taken whole; anything too big to drag
## (a gargantuar, a mech) is hurt for `fail_damage` and held in place a moment
## instead. Each grab spends one use, and the plant is gone when they run out.
## Among several zombies in reach the strongest draggable one is taken, so the
## grab lands where it matters.
##
## Config: reach (squares either side), uses, per_grab (zombies taken by one
## grab), fail_damage, fail_stun, delay before the grab lands,
## plantfood_count, plantfood_terrain (only zombies standing on this terrain
## are taken by plant food - kelp only reaches into water).

var reach: float = 0.5
var uses: int = 1
var per_grab: int = 1
var fail_damage: float = 400.0
var fail_stun: float = 1.5
var delay: float = 0.5

var _timer: float = -1.0


func setup() -> void:
	reach = float(cfg(&"reach", reach))
	uses = int(cfg(&"uses", uses))
	per_grab = int(cfg(&"per_grab", per_grab))
	fail_damage = float(cfg(&"fail_damage", fail_damage))
	fail_stun = float(cfg(&"fail_stun", fail_stun))
	delay = float(cfg(&"delay", delay))
	# Nothing bites a plant that is busy pulling a zombie down.
	host.set_runtime_tag(&"uneatable", true)


func _process(delta: float) -> void:
	if host.is_dead:
		return
	if _timer < 0.0:
		if not _in_reach().is_empty():
			_timer = scaled(delay)
			host.play_art_once(&"attack")
		return
	_timer -= delta
	if _timer > 0.0:
		return
	_timer = -1.0
	var caught := _in_reach()
	if caught.is_empty():
		return
	for z in caught.slice(0, per_grab):
		_grab(z)
	uses -= 1
	if uses <= 0:
		host.die()


## Zombies in reach, the ones worth dragging first.
func _in_reach() -> Array:
	var span: float = reach * host.board.cell_size.x
	var out: Array = []
	for z in host.board.hostile_zombies_in_row(host.row):
		if absf(z.position.x - host.position.x) <= span:
			out.append(z)
	out.sort_custom(func(a, b):
		var da: bool = a.has_tag(&"draggable")
		var db: bool = b.has_tag(&"draggable")
		if da != db:
			return da
		return a.health > b.health)
	return out


func _grab(z: Zombie) -> void:
	Audio.play(&"plant.drag", z.position)
	if z.has_tag(&"draggable"):
		z.die()
	else:
		z.take_damage(fail_damage, host)
		z.apply_stun(fail_stun)


## Plant food: reach out across the lawn and take several at once, without
## spending a use.
func on_plantfood() -> bool:
	var count := int(cfg(&"plantfood_count", 3))
	var ground := StringName(cfg(&"plantfood_terrain", &""))
	var pool: Array = host.board.all_hostile_zombies()
	pool.shuffle()
	var took := 0
	for z in pool:
		if took >= count:
			break
		if ground != &"" and host.board.terrain_at(z.row, z.col) != ground:
			continue
		_grab(z)
		took += 1
	return true
