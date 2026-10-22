extends EntityComponent
## Eats the gravestone it was planted on, and is spent - grave buster. It can
## only be planted onto a stone (its `on_grave:gravebuster_plantable` tag),
## and zombies can still eat it while it chews.
##
## Config: bust_time.

var _timer: float = 0.0


func setup() -> void:
	_timer = float(cfg(&"bust_time", 4.0))


func _process(delta: float) -> void:
	if host.is_dead:
		return
	_timer -= delta / maxf(host.attack_rate * host.suppression, 0.01)
	if _timer > 0.0:
		return
	var stone = host.board.object_at(host.row, host.col)
	if stone is Grave:
		Audio.play(&"plant.chomp", host.position)
		stone.die()
	host.die()
