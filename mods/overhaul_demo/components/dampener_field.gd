extends EntityComponent
## A gimmick: slows every hostile zombie in its lane while it lives, and
## restores their speed when it dies.
##
## Config: radius (cells), slow (fraction of speed removed).

var radius: float = 2.0
var slow: float = 0.45

var _slowed: Array = []


func setup() -> void:
	radius = float(cfg(&"radius", 2.0))
	slow = clampf(float(cfg(&"slow", 0.45)), 0.0, 0.95)
	host.died.connect(_on_host_died)


func _process(_delta: float) -> void:
	if host.is_dead:
		return
	var reach: float = radius * host.board.cell_size.x
	var hostile: Array = host.board.hostile_zombies_in_row(host.row)
	# A zombie that was charmed or freed is no longer listed, so release it.
	for z in _slowed.duplicate():
		if not hostile.has(z):
			_restore(z)
	for z in hostile:
		var near: bool = absf(z.position.x - host.position.x) <= reach
		var already: bool = _slowed.has(z)
		if near and not already:
			z.speed *= (1.0 - slow)
			z.set_runtime_tag(&"dampened", true)
			_slowed.append(z)
		elif already and not near:
			_restore(z)


func _restore(z) -> void:
	if is_instance_valid(z):
		z.speed /= maxf(1.0 - slow, 0.05)
		z.set_runtime_tag(&"dampened", false)
	_slowed.erase(z)


## Letting the plant die must not leave zombies permanently slowed.
func _on_host_died(_who) -> void:
	for z in _slowed.duplicate():
		_restore(z)


## Digging the plant up frees it without dying, so restore on removal too.
func _exit_tree() -> void:
	_on_host_died(host)
