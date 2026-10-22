extends EntityComponent
## Melts the block of ice it was planted on, freeing whatever was frozen
## inside, and is spent - hot potato. It can only go onto a block (its
## `on_grave:hot_potato_meltable` tag), and nothing can eat it meanwhile.
##
## Config: melt_time.

var _timer: float = 0.0


func setup() -> void:
	_timer = float(cfg(&"melt_time", 2.5))
	host.set_runtime_tag(&"uneatable", true)


func _process(delta: float) -> void:
	if host.is_dead:
		return
	_timer -= delta / maxf(host.attack_rate, 0.01)
	if _timer > 0.0:
		return
	var block = host.board.object_at(host.row, host.col)
	if block is Grave and block.def.hot_potato_meltable:
		Audio.play(&"plant.melt", host.position)
		# Breaking the block is what releases its prisoner.
		block.die()
	host.die()
