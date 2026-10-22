extends EntityComponent
## Leaps onto the first zombie that comes near and flattens everything around
## where it lands - squash.
##
## The leap is aimed, not instant: once a zombie is spotted the squash looks at
## it for `look_time`, then jumps. Whoever it lands on and anyone within a
## square of them takes the blow. It only dies once it has actually hit
## something, so a target that is gone by the time it lands is not a waste.
##
## Config: damage, detect_width (squares either side), smash_width (squares
## either side of the landing point), look_time, uses, plantfood_smashes.

var damage: float = 1800.0
var detect_width: float = 1.5
var smash_width: float = 1.0
var look_time: float = 0.6
var uses: int = 1

var _target: Zombie = null
var _timer: float = 0.0
## Plant food smashes still to come. Each picks the most crowded spot on the
## lawn, and none of them use up the squash.
var _food_smashes: int = 0


func setup() -> void:
	damage = float(cfg(&"damage", damage))
	detect_width = float(cfg(&"detect_width", detect_width))
	smash_width = float(cfg(&"smash_width", smash_width))
	look_time = float(cfg(&"look_time", look_time))
	uses = int(cfg(&"uses", uses))


func _process(delta: float) -> void:
	if host.is_dead:
		return
	if _food_smashes > 0:
		_timer -= delta
		if _timer <= 0.0:
			_food_smashes -= 1
			_timer = scaled(look_time)
			var crowd := _most_crowded()
			if crowd != null:
				_smash_at(crowd.row, crowd.position.x, false)
		return
	if _target != null:
		_timer -= delta
		if _timer > 0.0:
			return
		var landing := _target
		_target = null
		# Re-aim if the first pick died while the squash was winding up.
		if not is_instance_valid(landing) or landing.is_dead:
			landing = _spot()
		if landing != null:
			_smash_at(landing.row, landing.position.x, true)
		return
	_target = _spot()
	if _target != null:
		_timer = scaled(look_time)
		host.play_art_once(&"attack")


## The zombie nearest the house within reach of this lane.
func _spot() -> Zombie:
	var reach: float = detect_width * host.board.cell_size.x
	for z in host.board.hostile_zombies_in_row(host.row):
		if absf(z.position.x - host.position.x) <= reach:
			return z
	return null


func _smash_at(row: int, x: float, spends_use: bool) -> void:
	var hit := false
	for z in host.board.hostile_zombies_near(row, x, 0, smash_width):
		z.take_damage(damage, host)
		hit = true
	Audio.play(&"plant.squash", host.position)
	if spends_use and hit:
		uses -= 1
		if uses <= 0:
			host.die()


## The zombie with the most health standing within a square of it.
func _most_crowded() -> Zombie:
	var best: Zombie = null
	var best_total := 0.0
	for z in host.board.all_hostile_zombies():
		var total := 0.0
		for n in host.board.hostile_zombies_near(z.row, z.position.x, 0, smash_width):
			total += n.health
		if total > best_total:
			best_total = total
			best = z
	return best


## Plant food: three smashes on whichever spot on the lawn hurts most, and the
## squash survives them.
func on_plantfood() -> bool:
	_food_smashes = int(cfg(&"plantfood_smashes", 3))
	_timer = 0.0
	_target = null
	return true
