extends EntityComponent
## A grid-item event: the grave periodically summons a zombie at its own cell.
##
## This is what makes a grave more than scenery - an arcade cabinet or spawner
## grave keeps producing zombies until a plant destroys it.
##
## Config: interval_min, interval_max, zombies ([{type, weight}]).

var interval_min: float = 10.0
var interval_max: float = 12.0

var _pool: Array[Dictionary] = []
var _total_weight: float = 0.0
var _timer: float = 0.0


func setup() -> void:
	interval_min = float(cfg(&"interval_min", 10.0))
	interval_max = float(cfg(&"interval_max", maxf(interval_min, 12.0)))

	for entry in (cfg(&"zombies", []) as Array):
		if entry is Dictionary and entry.has("type"):
			var weight := maxf(float(entry.get("weight", 1)), 0.0)
			_pool.append({"type": StringName(entry["type"]), "weight": weight})
			_total_weight += weight
	_timer = _next_interval()


func _process(delta: float) -> void:
	if host.is_dead or _pool.is_empty():
		return
	_timer -= delta
	if _timer > 0.0:
		return
	_summon()
	_timer = _next_interval()


func _next_interval() -> float:
	return randf_range(interval_min, interval_max)


func _summon() -> void:
	var id := _pick()
	if id == &"":
		return
	host.board.place_entity(&"zombie", id, host.row, host.col)


## Weighted pick from the summon pool.
func _pick() -> StringName:
	if _total_weight <= 0.0:
		return _pool[randi() % _pool.size()]["type"]
	var roll := randf() * _total_weight
	for entry in _pool:
		roll -= entry["weight"]
		if roll <= 0.0:
			return entry["type"]
	return _pool[-1]["type"]
