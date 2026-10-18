extends EntityComponent
## Lets out whatever was riding inside when this zombie dies.
##
## One mechanic covers several things PopCap names separately: the mummy that
## walks out of a dead camel, the imp that drops off a broken barrel, the
## rider thrown clear when a bull goes down.
##
## Config: zombie, count, protects (the inner one takes no damage until the
## shell is gone, which is already true here because it does not exist yet).

var zombie: StringName = &""
var count: int = 1


func setup() -> void:
	zombie = StringName(cfg(&"zombie", &""))
	count = maxi(1, int(cfg_range(&"count", 1.0)))
	# `died` fires before the host frees itself, so the board still knows
	# where it was standing.
	host.died.connect(_on_host_died)


func _on_host_died(_who: Character) -> void:
	if zombie == &"":
		return
	for i in range(count):
		var offset: float = float(i) * host.board.cell_size.x * 0.4
		var out: Zombie = host.board.spawn_zombie_at(zombie, host.row,
				host.position.x - host.direction() * offset)
		if out == null:
			continue
		out.set_allegiance(host.allegiance)
