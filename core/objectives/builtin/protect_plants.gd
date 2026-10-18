extends Objective
## Keep a minimum number of specific plants alive.
##
## Config: must_protect - how many must survive; plants - the placements the
## level pre-seeds, used to know which ones count.

var must_protect: int = 1

var _watched: Array[Node] = []
var _lost: int = 0


func setup() -> void:
	must_protect = int(cfg(&"must_protect", 1))
	# Whatever the level planted up front is what has to survive.
	for cell in (cfg(&"plants", []) as Array):
		if not (cell is Dictionary):
			continue
		var plant = board.plant_at(int(cell.get("row", 0)), int(cell.get("col", 0)))
		if plant != null:
			_watched.append(plant)


func on_plant_died(plant: Node) -> void:
	if _watched.has(plant):
		_watched.erase(plant)
		_lost += 1
		notify_progress()
		if alive() < must_protect:
			fail()


func alive() -> int:
	var n := 0
	for p in _watched:
		if is_instance_valid(p) and not p.is_dead:
			n += 1
	return n


func is_met() -> bool:
	return alive() >= must_protect


func describe() -> String:
	return "Protect plants: %d / %d" % [alive(), must_protect]
