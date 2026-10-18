extends EntityComponent
## Throws a rider over the defences as this zombie is worn down.
##
## Each threshold in `throw_at` fires once, when health falls past it, so a
## gargantuar that is chewed down slowly still only throws its imp once per
## threshold. The imp lands `distance` lanes closer to the house, behind
## whatever was blocking its carrier - which is the whole point of it.
##
## Config: imp, imps (picked from at random), throw_at, distance, count.

const DEFAULT_DISTANCE := 3.0

var imps: Array = []
var distance: float = DEFAULT_DISTANCE
var count: int = 1

## Thresholds still to cross, highest first.
var _pending: Array[float] = []


func setup() -> void:
	var single := StringName(cfg(&"imp", &""))
	if single != &"":
		imps = [single]
	for id in (cfg(&"imps", []) as Array):
		imps.append(StringName(id))
	distance = cfg_range(&"distance", DEFAULT_DISTANCE)
	if distance <= 0.0:
		distance = DEFAULT_DISTANCE
	count = int(cfg_range(&"count", 1.0))

	for fraction in (cfg(&"throw_at", [0.5]) as Array):
		_pending.append(float(fraction))
	_pending.sort()
	_pending.reverse()
	host.damaged.connect(_on_damaged)


func _on_damaged(_who: Character, _amount: float, _remaining: float) -> void:
	if _pending.is_empty() or imps.is_empty() or host.is_dead:
		return
	if host.health_fraction() > _pending[0]:
		return
	_pending.pop_front()
	for _i in range(maxi(1, count)):
		_throw()


func _throw() -> void:
	var id: StringName = imps[randi() % imps.size()]
	var landing: float = host.position.x \
			+ host.direction() * distance * host.board.cell_size.x
	var imp: Zombie = host.board.spawn_zombie_at(id, host.row, landing)
	if imp == null:
		return
	# A thrown imp inherits the side it was thrown from, so a charmed
	# gargantuar's imp fights for the player too.
	imp.set_allegiance(host.allegiance)
	Audio.play(&"zombie.imp.throw", host.position)
