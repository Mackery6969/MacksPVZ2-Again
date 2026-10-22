extends EntityComponent
## Grows zombies that fight for you - zoybean pod. Every few seconds a zoybean
## drawn from a weighted list ripens and walks off charmed; plant food ripens
## a big one.
##
## Config: interval, interval_max, summons ([{id, weight}]),
## plantfood_summons.

var _timer: float = 0.0


func setup() -> void:
	_timer = scaled(cfg_range(&"interval", 4.0))


func _process(delta: float) -> void:
	if host.is_dead:
		return
	_timer -= delta
	if _timer > 0.0:
		return
	_timer = scaled(cfg_range(&"interval", 4.0))
	_grow(cfg(&"summons", []))


func _grow(table: Array) -> Zombie:
	var id := _pick(table)
	if id == &"":
		return null
	var z: Zombie = host.board.spawn_zombie_at(id, host.row,
			host.position.x + host.board.cell_size.x * 0.3, [&"summoned"])
	if z != null:
		z.charm()
	return z


static func _pick(table: Array) -> StringName:
	var total := 0.0
	for entry in table:
		total += float(entry.get("weight", 1.0))
	var roll := randf() * total
	for entry in table:
		roll -= float(entry.get("weight", 1.0))
		if roll <= 0.0:
			return StringName(entry.get("id", ""))
	return StringName(table.back().get("id", "")) if not table.is_empty() else &""


func on_plantfood() -> bool:
	return _grow(cfg(&"plantfood_summons", [])) != null
