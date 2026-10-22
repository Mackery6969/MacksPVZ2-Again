extends EntityComponent
## Grows back - infi-nut. It regenerates fully once it has gone a while
## without being hit, and when eaten down it lies flat, uneatable, until it
## springs back up.
##
## Config: regen_delay (seconds after the last hit), revive_delay (seconds
## lying flat), plantfood_shield (seconds the plant food barrier holds; the
## barrier itself is a full heal).

var _since_hit: float = 0.0
var _downed_left: float = 0.0


func setup() -> void:
	host.damaged.connect(func(_w, _a, _r): _since_hit = 0.0)


func _process(delta: float) -> void:
	if _downed_left > 0.0:
		_downed_left -= delta
		if _downed_left <= 0.0:
			host.set_runtime_tag(&"uneatable", false)
			host.set_runtime_tag(&"downed", false)
			host.heal(host.max_health)
		return
	if host.health >= host.max_health:
		return
	_since_hit += delta
	if _since_hit >= float(cfg(&"regen_delay", 15.0)):
		host.heal(host.max_health)


## Eaten down, it flattens rather than dies. Anything that removes it outright
## - a shovel, an instant kill on the board - goes around this.
func prevent_death() -> bool:
	if _downed_left > 0.0:
		return true
	_downed_left = float(cfg(&"revive_delay", 15.0))
	host.set_runtime_tag(&"uneatable", true)
	host.set_runtime_tag(&"downed", true)
	return true


func is_downed() -> bool:
	return _downed_left > 0.0


func on_plantfood() -> bool:
	if _downed_left > 0.0:
		_downed_left = 0.0001
	else:
		host.heal(host.max_health)
	return true
