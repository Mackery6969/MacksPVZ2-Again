extends EntityComponent
## Flattens whatever blocks this zombie instead of eating it (gargantuars).
##
## A smash is one enormous blow after a wind-up, then a rest - not a stream of
## damage. That is what makes a gargantuar feel different from a biter: a
## wall-nut dies in a single hit, and the zombie stands still long enough
## afterwards to be shot at.
##
## Config: damage, distance (lanes of reach), max_targets, windup, rest.

var damage: float = 1500.0
var distance: float = 1.0
var max_targets: int = 1
var windup: float = 0.6
var rest: float = 1.0

## Counts down to the blow while a target is held, then counts the rest out.
var _timer: float = 0.0
var _resting: bool = false


func setup() -> void:
	damage = float(cfg(&"damage", damage))
	distance = float(cfg(&"distance", distance))
	max_targets = int(cfg(&"max_targets", max_targets))
	windup = float(cfg(&"windup", windup))
	rest = float(cfg(&"rest", rest))
	_timer = windup


## The zombie stops at a plant but never bites it; this does the damage.
func claims_attack() -> bool:
	return true


func _process(delta: float) -> void:
	if host.is_dead:
		return
	if _resting:
		_timer -= delta
		if _timer <= 0.0:
			_resting = false
			_timer = scaled(windup)
			host.set_runtime_tag(&"smashing", false)
		return
	# Nothing in front means nothing to wind up for.
	if not is_instance_valid(host.target) or host.target.is_dead:
		_timer = scaled(windup)
		host.set_runtime_tag(&"smashing", false)
		return
	host.set_runtime_tag(&"smashing", true)
	_timer -= delta
	if _timer > 0.0:
		return
	_smash()
	_resting = true
	_timer = scaled(rest)


func _smash() -> void:
	Audio.play(&"zombie.smash", host.position)
	var hit := 0
	for victim in _targets():
		victim.take_damage(damage, host)
		hit += 1
		if hit >= max_targets:
			break


## What the hammer lands on, nearest first. The held target comes first so a
## charmed smasher hits the zombie it is fighting; anything further is read
## off the lawn, `distance` being a reach in lanes.
func _targets() -> Array[Character]:
	var out: Array[Character] = []
	if is_instance_valid(host.target) and not host.target.is_dead:
		out.append(host.target)
	for step in range(1, maxi(1, int(ceilf(distance)))):
		var ahead: Plant = host.board.plant_at(host.row,
				host.col + step * host.direction())
		if ahead != null and not ahead.is_dead and not out.has(ahead):
			out.append(ahead)
	return out
