extends EntityComponent
## Periodically drops sun onto the board.
##
## Timing is data-driven; the amount is not - every sun is worth
## SunToken.VALUE.
##
## Config: interval, interval_jitter, first_delay, first_delay_jitter.

var _timer: float = 0.0


func setup() -> void:
	_timer = cfg_jittered(&"first_delay", &"first_delay_jitter", 5.0)


func _process(delta: float) -> void:
	if host.is_dead:
		return
	_timer -= delta
	if _timer > 0.0:
		return
	host.board.drop_sun(host.position)
	_timer = cfg_jittered(&"interval", &"interval_jitter", 24.0)


## Plant food: a handful of sun at once.
func on_plantfood() -> bool:
	var count := int(cfg(&"plantfood_suns", 5))
	for i in count:
		# Spread them so they do not land exactly on top of each other.
		host.board.drop_sun(host.position + Vector2((i - count * 0.5) * 22.0, 0))
	_timer = cfg_jittered(&"interval", &"interval_jitter", 24.0)
	return count > 0
