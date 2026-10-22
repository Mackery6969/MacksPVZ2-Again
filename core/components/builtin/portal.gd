extends EntityComponent
## A time rift that lets zombies through onto its own cell.
##
## Nothing about which zombies is fixed here: the wave that opens the portal
## hands it a spec through `configure`, either a shared portal from
## data/native/portals or one the level defines itself. As in PVZGE, each
## listed zombie comes through once, drawn by weight, and the rift closes
## once the list is spent.
##
## Spec: zombies [{type, weight}], first {min, max}, interval {min, max};
## limit caps how many come through.

var _queue: Array[StringName] = []
var _interval := Vector2(10.0, 12.0)
var _timer: float = INF


func configure(spec: Dictionary, limit: int = -1) -> void:
	var pool: Array = (spec.get("zombies", []) as Array).duplicate()
	_queue.clear()
	# Weighted draw without replacement, so the order is random but every
	# entry appears once.
	while not pool.is_empty() and (limit < 0 or _queue.size() < limit):
		var total := 0.0
		for e in pool:
			total += float(e.get("weight", 1.0))
		var pick := randf() * total
		for i in pool.size():
			pick -= float(pool[i].get("weight", 1.0))
			if pick <= 0.0 or i == pool.size() - 1:
				_queue.append(StringName(pool[i].get("type", "")))
				pool.remove_at(i)
				break
	_interval = _range(spec.get("interval", {}), Vector2(10.0, 12.0))
	var first := _range(spec.get("first", {}), Vector2(5.0, 6.0))
	_timer = randf_range(first.x, first.y)


func _range(r: Variant, fallback: Vector2) -> Vector2:
	if not (r is Dictionary):
		return fallback
	return Vector2(float(r.get("min", fallback.x)), float(r.get("max", fallback.y)))


## Zombies still to come through.
func remaining() -> int:
	return _queue.size()


func _process(delta: float) -> void:
	if host.is_dead or _timer == INF:
		return
	_timer -= delta
	if _timer > 0.0:
		return
	if _queue.is_empty():
		host.die()
		return
	var id: StringName = _queue.pop_front()
	host.board.spawn_zombie_at(id, host.row, host.position.x)
	_timer = randf_range(_interval.x, _interval.y) if not _queue.is_empty() else 1.0
