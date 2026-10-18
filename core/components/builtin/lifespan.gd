extends EntityComponent
## Gives this entity a time limit: when it runs out, it dies.
##
## The Kung-Fu bronze statue is the case in the source data - it stands there
## calling gargantuars onto the lane for twenty-five to thirty-five seconds
## and then crumbles whether or not anything shot it.
##
## Config: duration (a {Min, Max} range in the source data).

var _left: float = 0.0


func setup() -> void:
	_left = scaled(cfg_range(&"duration", 10.0))


func _process(delta: float) -> void:
	if host.is_dead:
		return
	_left -= delta
	if _left <= 0.0:
		host.die()
