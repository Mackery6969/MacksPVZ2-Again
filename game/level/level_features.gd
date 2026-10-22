class_name LevelFeatures
extends Node
## The level's world mechanics: what the lawn is set up with (tide, rails,
## power tiles, potions) and the special wave events (storms, raiding
## parties, low tide, tidal changes, frost wind, portals, dinosaurs).
##
## Kept out of LevelRunner, which owns pacing and objectives, so that each
## mechanic is a self-contained reader of its own level field or wave action.
## Events that unfold over several seconds are queued here and only advance
## while the level runs.

## Raised for each zombie an event brings in, so wave pacing can count it.
signal zombie_spawned(zombie: Zombie)

var board: Board
var level: Dictionary = {}

## Pending timed steps, as [seconds_left, Callable].
var _queue: Array = []
var _potion_timer: float = INF


func start(level_def: Dictionary, target_board: Board, world: Dictionary) -> void:
	level = level_def
	board = target_board
	_queue.clear()
	_setup_tide()
	_setup_rails(world)
	_setup_power_tiles()
	_setup_potions()


func tick(delta: float) -> void:
	if not _queue.is_empty():
		var due: Array = []
		for entry in _queue:
			entry[0] -= delta
			if entry[0] <= 0.0:
				due.append(entry)
		for entry in due:
			_queue.erase(entry)
			(entry[1] as Callable).call()
	_tick_potions(delta)


func _after(seconds: float, step: Callable) -> void:
	if seconds <= 0.0:
		step.call()
	else:
		_queue.append([seconds, step])


## Events still waiting to happen, counting open portals. A level is not
## over while one is.
func pending() -> int:
	var n := _queue.size()
	for r in board.rows:
		for c in board.cols:
			var o := board.object_at(r, c)
			if o != null and o.component(&"portal") != null:
				n += 1
	return n


# --- lawn set-up ----------------------------------------------------------

func _setup_tide() -> void:
	var tide: Dictionary = level.get("tide", {})
	if tide.has("water_from"):
		board.set_tide(int(tide["water_from"]))


## Rails run down a column between two rows; carts start on them. Which cart
## (and so which rail art) comes from the level, else from the world.
func _setup_rails(world: Dictionary) -> void:
	var spec: Dictionary = level.get("railcarts", {})
	if spec.is_empty():
		return
	var cart_id := StringName(spec.get("type", world.get("railcart", "railcart")))
	if Data.board_object(cart_id) == null:
		cart_id = &"railcart"
	var cart_def := Data.board_object(cart_id)
	var rail_id := StringName(cart_def.extra.get("RailType", "rail")) if cart_def else &"rail"
	for r in (spec.get("rails", []) as Array):
		if not (r is Dictionary) or r.get("col") == null:
			continue
		for row in range(int(r.get("row_start", 0)), int(r.get("row_end", board.rows - 1)) + 1):
			board.add_rail(row, int(r["col"]), rail_id)
	for c in (spec.get("carts", []) as Array):
		if c is Dictionary and c.get("col") != null and c.get("row") != null:
			board.place_object(cart_id, int(c["row"]), int(c["col"]))


func _setup_power_tiles() -> void:
	for t in (level.get("power_tiles", []) as Array):
		if not (t is Dictionary):
			continue
		var tile := board.place_object(StringName("powertile_" + String(t.get("group", "alpha"))),
				int(t.get("row", 0)), int(t.get("col", 0)))
		if tile != null and t.get("delay") != null:
			tile.set_meta(&"propagation_delay", float(t["delay"]))


# --- zombie potions -------------------------------------------------------

func _setup_potions() -> void:
	var spec: Dictionary = level.get("potions", {})
	if spec.is_empty():
		_potion_timer = INF
		return
	for i in int(spec.get("initial", 0)):
		_drop_potion()
	_potion_timer = _potion_interval()


func _potion_interval() -> float:
	var r: Dictionary = (level.get("potions", {}) as Dictionary).get("interval", {})
	return randf_range(float(r.get("min", 12)), float(r.get("max", 16)))


func _tick_potions(delta: float) -> void:
	if _potion_timer == INF:
		return
	_potion_timer -= delta
	if _potion_timer > 0.0:
		return
	_potion_timer = _potion_interval()
	if _potion_count() < int(level["potions"].get("max", 0)):
		_drop_potion()


func _potion_count() -> int:
	var n := 0
	for r in board.rows:
		for c in board.cols:
			var o := board.object_at(r, c)
			if o != null and o.category() == ObjectDef.Category.POTION:
				n += 1
	return n


## Sets a potion down on a random empty cell away from the house.
func _drop_potion() -> void:
	var types: Array = (level.get("potions", {}) as Dictionary).get("types", [])
	if types.is_empty():
		return
	var cells: Array[Vector2i] = []
	for r in board.rows:
		for c in range(1, board.cols):
			if board.plant_at(r, c) == null and board.object_at(r, c) == null \
					and not board.is_rail(r, c) and board.terrain_at(r, c) == &"":
				cells.append(Vector2i(c, r))
	if cells.is_empty():
		return
	var cell: Vector2i = cells.pick_random()
	board.place_object(StringName(types.pick_random()), cell.y, cell.x)


# --- wave events ----------------------------------------------------------

## Runs a wave action this class models. Returns false for any other kind.
func run(action: Dictionary) -> bool:
	match String(action.get("kind", "")):
		"storm": _storm(action)
		"raiding_party": _raiding_party(action)
		"low_tide": _low_tide(action)
		"tide":
			if action.has("water_from"):
				board.set_tide(int(action["water_from"]))
		"frost_wind": _frost_wind(action)
		"portal": _portal(action)
		"dino":
			var id := StringName(action.get("dino", "raptor"))
			var row := int(action.get("row", 0))
			_after(float(action.get("delay", 0.0)), func(): board.spawn_dino(id, row))
		_:
			return false
	return true


## When the nth of `count` arrivals lands, for arrivals in groups of
## `group_size` every `interval` seconds - PVZGE's own schedule.
func _group_time(index: int, group_size: int, interval: float) -> float:
	return ceilf(float(index + 1) / maxf(group_size, 1)) * interval


func _spawned(z: Zombie) -> void:
	if z != null:
		zombie_spawned.emit(z)


## Zombies arrive inside a sand- or snowstorm, already partway up the lawn.
func _storm(action: Dictionary) -> void:
	var ids: Array = (action.get("zombies", []) as Array).duplicate()
	ids.shuffle()
	var rows: Array = range(int(action.get("row_start", 0)),
			int(action.get("row_end", board.rows - 1)) + 1)
	var c0 := int(action.get("col_start", 4))
	var c1 := int(action.get("col_end", 8))
	for i in ids.size():
		var id := StringName(ids[i])
		_after(_group_time(i, int(action.get("group_size", 2)),
				float(action.get("group_interval", 2.0))), func():
			var row := board.quietest_row(rows)
			var col := c0 + int(floorf((c1 - c0) * randf()))
			_spawned(board.spawn_zombie_at(id, row, board.grid_to_world(row, col).x)))


## Swashbucklers swing in from the edge in groups.
func _raiding_party(action: Dictionary) -> void:
	var id := StringName(action.get("type", "swashbuckler"))
	for i in int(action.get("count", 1)):
		_after(_group_time(i, int(action.get("group_size", 5)),
				float(action.get("group_interval", 1.0))), func():
			_spawned(board.spawn_zombie(id, randi() % board.rows, randf() * 0.5)))


## Big Wave Beach's low tide: zombies surface from the sand the water left.
func _low_tide(action: Dictionary) -> void:
	var id := StringName(action.get("type", ""))
	var c0 := int(action.get("col_start", 0))
	var c1 := mini(int(action.get("col_end", 8)), board.cols - 1)
	var delay := float(action.get("delay", 0.1))
	for i in int(action.get("count", 0)):
		_after(delay + _group_time(i, int(action.get("group_size", 1)),
				float(action.get("group_interval", 0.25))), func():
			var row := board.quietest_row(range(board.rows))
			var col := c0 + int(round(randf() * (c1 - c0)))
			_spawned(board.spawn_zombie_at(id, row, board.grid_to_world(row, col).x)))


## A gust down each listed lane that frosts every plant it passes. The
## second blast to reach a plant freezes it in ice.
func _frost_wind(action: Dictionary) -> void:
	var winds: Array = action.get("winds", [])
	for i in winds.size():
		var w: Dictionary = winds[i]
		var row := int(w.get("row", 0))
		var from_left := String(w.get("direction", "right")) == "left"
		for blast in int(action.get("blasts", 1)):
			for step in board.cols:
				var col := step if from_left else board.cols - 1 - step
				_after(0.5 * i + 0.15 * (step + 2), func(): board.chill_cell(row, col, 2.0))


## Opens a portal on a cell; the plant there is pushed out of the way.
func _portal(action: Dictionary) -> void:
	var row: int = int(action["row"]) if action.get("row") != null else randi() % board.rows
	var col: int = int(action["col"]) if action.get("col") != null else randi() % board.cols
	if not board.in_bounds(row, col):
		return
	var spec: Variant = action.get("portal", "modern")
	if not (spec is Dictionary):
		spec = Data.portal(StringName(spec))
	if (spec as Dictionary).is_empty():
		push_warning("LevelFeatures: unknown portal '%s'" % action.get("portal"))
		return
	board.dig_up(row, col)
	var old := board.object_at(row, col)
	if old != null:
		board.remove_object(row, col)
		old.queue_free()
	var portal := board.place_object(&"zombie_portal", row, col)
	if portal != null and portal.component(&"portal") != null:
		portal.component(&"portal").configure(spec, int(action.get("limit", -1)))
