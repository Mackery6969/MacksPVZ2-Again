class_name Board
extends Node2D
## The lawn: grid geometry, entity ownership, and player input.
##
## Everything positional goes through here so components never do their own
## coordinate maths. Rows run top to bottom, columns left to right; zombies
## enter from the right and walk toward the house at the left.

signal sun_changed(total: int)
signal level_lost
signal level_won
signal mower_triggered(row: int)
signal plant_food_changed(total: int)

const DEFAULT_ROWS := 5
const DEFAULT_COLS := 9

@export_group("Grid")
## Lanes on the lawn. Exported so a level or stage can use a different shape.
@export_range(1, 12) var rows: int = DEFAULT_ROWS
@export_range(1, 16) var cols: int = DEFAULT_COLS
@export var cell_size := Vector2(84.0, 98.0)
@export var origin := Vector2(180.0, 120.0)

@export_group("Mowers")
## One mower per lane, parked at the house. Levels turn these on through their
## feature list; without them a single zombie reaching the house ends the level.
@export var mowers_enabled: bool = false
## How far left of the house line the mowers park.
@export var mower_offset: float = 26.0

@export_group("Economy")
@export var starting_sun: int = 50
## Where collected sun flies to, in board-local coordinates. Should sit under
## the sun counter in the HUD.
@export var sun_collect_target := Vector2(60.0, 30.0)
## Where collected plant food flies to, in board-local coordinates.
@export var plant_food_collect_target := Vector2(200.0, 30.0)
## Plant food the player can hold at once.
@export var max_plant_food: int = 3

@export_group("Appearance")
@export var lawn_light := Color("5a8f3c")
@export var lawn_dark := Color("528436")
@export var house_line := Color("3d2b1f")
## Tint drawn over lanes the player cannot plant in.
@export var locked_lane_tint := Color(0, 0, 0, 0.35)

var sun: int = 50
var plant_food: int = 0
## What the player has picked from the seed bank, as {kind, id, slot}.
## Zombies are placeable too, for level types where the player plays the
## zombie side.
var selected_seed: Dictionary = {}
## Optional. When set, a packet must have recharged before it can be placed,
## and placing starts its recharge.
var seed_bank: SeedBank = null
## When true a click digs up a plant instead of placing a seed.
var shovel_active: bool = false
## When true a click feeds a plant instead of placing a seed.
var plant_food_active: bool = false

## Lanes the player may plant in, 0-based. Empty means every lane is open.
## Tutorial 1 uses this to confine the player to a single lane.
var plantable_rows: Array[int] = []

var _plants: Dictionary = {}          ## Vector2i -> Plant
var _zombies_by_row: Dictionary = {}  ## int -> Array[Zombie]
var _projectiles: Node2D
var _suns: Node2D
var _entities: Node2D
var _mowers_node: Node2D
var _mowers: Dictionary = {}   ## int row -> Mower


func _ready() -> void:
	_entities = Node2D.new()
	_entities.name = "Entities"
	add_child(_entities)
	_projectiles = Node2D.new()
	_projectiles.name = "Projectiles"
	add_child(_projectiles)
	_suns = Node2D.new()
	_suns.name = "Suns"
	add_child(_suns)
	_mowers_node = Node2D.new()
	_mowers_node.name = "Mowers"
	add_child(_mowers_node)
	sun = starting_sun
	for r in rows:
		_zombies_by_row[r] = []
	sun_changed.emit(sun)


## Clears the lawn back to its starting state, ready for another level.
func reset() -> void:
	for group in [_entities, _projectiles, _suns, _mowers_node]:
		for child in group.get_children():
			child.queue_free()
	_mowers.clear()
	_plants.clear()
	for r in _zombies_by_row:
		_zombies_by_row[r].clear()
	plantable_rows.clear()
	selected_seed = {}
	sun = starting_sun
	plant_food = 0
	sun_changed.emit(sun)
	plant_food_changed.emit(plant_food)
	queue_redraw()


## Parks a fresh mower in every lane. Called when a level with mowers starts.
func setup_mowers() -> void:
	for child in _mowers_node.get_children():
		child.queue_free()
	_mowers.clear()
	if not mowers_enabled:
		return
	for r in rows:
		var m := Mower.new()
		m.row = r
		m.board = self
		m.name = "Mower_%d" % r
		m.position = Vector2(house_x() - mower_offset, grid_to_world(r, 0).y)
		m.finished.connect(_on_mower_finished)
		_mowers_node.add_child(m)
		_mowers[r] = m


func mower_in_row(row: int) -> Mower:
	var m = _mowers.get(row)
	return m if is_instance_valid(m) else null


## True when a lane still has an unused mower protecting it.
func has_mower(row: int) -> bool:
	var m := mower_in_row(row)
	return m != null and m.is_available()


func _on_mower_finished(row: int) -> void:
	_mowers.erase(row)


# --- geometry ------------------------------------------------------------

func grid_to_world(row: int, col: int) -> Vector2:
	return origin + Vector2((col + 0.5) * cell_size.x, (row + 0.5) * cell_size.y)


func world_to_col(x: float) -> int:
	return clampi(int(floorf((x - origin.x) / cell_size.x)), -1, cols - 1)


func world_to_row(y: float) -> int:
	return clampi(int(floorf((y - origin.y) / cell_size.y)), 0, rows - 1)


func in_bounds(row: int, col: int) -> bool:
	return row >= 0 and row < rows and col >= 0 and col < cols


func house_x() -> float:
	return origin.x - cell_size.x * 0.5


func spawn_x() -> float:
	return origin.x + (cols + 0.6) * cell_size.x


func despawn_x() -> float:
	return spawn_x() + cell_size.x


# --- plants --------------------------------------------------------------

func plant_at(row: int, col: int) -> Plant:
	var p = _plants.get(Vector2i(col, row))
	return p if is_instance_valid(p) and not p.is_dead else null


func is_row_plantable(row: int) -> bool:
	return plantable_rows.is_empty() or plantable_rows.has(row)


func can_place(row: int, col: int) -> bool:
	return in_bounds(row, col) and is_row_plantable(row) and plant_at(row, col) == null


## Places a plant. Convenience wrapper over `place_entity`.
func place_plant(id: StringName, row: int, col: int) -> Plant:
	return place_entity(&"plant", id, row, col)


## Places whatever a seed packet holds. Plants occupy their cell; zombies are
## dropped into the lane and walk from there, so they do not block it.
func place_entity(kind: StringName, id: StringName, row: int, col: int) -> Character:
	if not can_place_entity(kind, row, col):
		return null
	if kind == &"zombie":
		var z := spawn_zombie(id, row)
		if z != null:
			z.position.x = grid_to_world(row, col).x
		return z
	var p := _place_plant_at(id, row, col)
	if p != null:
		Audio.play(&"plant.place", p.position)
	return p


## True when `kind` may be placed in this cell.
func can_place_entity(kind: StringName, row: int, col: int) -> bool:
	if not in_bounds(row, col) or not is_row_plantable(row):
		return false
	# A lane holds any number of zombies, but only one plant per cell.
	return true if kind == &"zombie" else plant_at(row, col) == null


## Placement cost for a seed, read from whichever definition owns it.
func seed_cost(kind: StringName, id: StringName) -> int:
	var def: EntityDef = Data.zombie(id) if kind == &"zombie" else Data.plant(id)
	return int(def.stat(&"sun_cost", 100)) if def else 0


func _place_plant_at(id: StringName, row: int, col: int) -> Plant:
	var def := Data.plant(id)
	if def == null:
		push_warning("Board: unknown plant '%s'" % id)
		return null

	var p := Plant.new()
	p.row = row
	p.col = col
	p.position = grid_to_world(row, col)
	p.name = "Plant_%s_%d_%d" % [id, row, col]
	_entities.add_child(p)
	p.initialize(def, self)
	_plants[Vector2i(col, row)] = p
	return p


func remove_plant(row: int, col: int) -> void:
	_plants.erase(Vector2i(col, row))


## Digs up the plant in a cell, freeing the square. Returns false if empty.
func dig_up(row: int, col: int) -> bool:
	var p := plant_at(row, col)
	if p == null:
		return false
	remove_plant(row, col)
	Audio.play(&"plant.dig", p.position)
	p.queue_free()
	return true


# --- zombies -------------------------------------------------------------

## `x_offset` is in cells, pushing the zombie further right of the spawn line
## so that several zombies entering the same lane do not overlap.
func spawn_zombie(id: StringName, row: int, x_offset: float = 0.0) -> Zombie:
	var def := Data.zombie(id)
	if def == null:
		push_warning("Board: unknown zombie '%s'" % id)
		return null

	var z := Zombie.new()
	z.row = clampi(row, 0, rows - 1)
	z.col = cols - 1
	z.position = Vector2(spawn_x() + x_offset * cell_size.x,
			grid_to_world(z.row, 0).y)
	z.name = "Zombie_%s" % id
	_entities.add_child(z)
	z.initialize(def, self)

	_zombies_by_row[z.row].append(z)
	z.died.connect(_on_carrier_died)
	z.died.connect(_on_zombie_gone)
	z.tree_exiting.connect(_on_zombie_gone.bind(z))
	z.reached_house.connect(_on_zombie_reached_house)
	Audio.play(&"zombie.spawn", z.position)
	return z


## A zombie on the threshold is caught by the lane's mower if one is left;
## otherwise the level is lost.
func _on_zombie_reached_house(who: Zombie) -> void:
	var m := mower_in_row(who.row)
	if m != null and m.trigger():
		mower_triggered.emit(who.row)
		Audio.play(&"mower.trigger", m.position)
		return
	level_lost.emit()


## A zombie marked as carrying plant food drops it where it fell.
func _on_carrier_died(who: Character) -> void:
	if who is Zombie and who.has_tag(&"carrying_plantfood"):
		drop_plant_food(who.position)


func _on_zombie_gone(who: Node) -> void:
	for r in _zombies_by_row:
		_zombies_by_row[r].erase(who)


## Living zombies in one row, nearest the house first.
func zombies_in_row(row: int) -> Array:
	var out: Array = []
	for z in _zombies_by_row.get(row, []):
		if is_instance_valid(z) and not z.is_dead:
			out.append(z)
	out.sort_custom(func(a, b): return a.position.x < b.position.x)
	return out


## Zombies in a lane that still fight for the zombie side. Plant weapons use
## this so they never target a charmed zombie fighting for the player.
func hostile_zombies_in_row(row: int) -> Array:
	var out: Array = []
	for z in zombies_in_row(row):
		if not z.is_charmed():
			out.append(z)
	return out


func charmed_zombies_in_row(row: int) -> Array:
	var out: Array = []
	for z in zombies_in_row(row):
		if z.is_charmed():
			out.append(z)
	return out


func zombie_count() -> int:
	var n := 0
	for r in _zombies_by_row:
		for z in _zombies_by_row[r]:
			if is_instance_valid(z) and not z.is_dead and not z.is_charmed():
				n += 1
	return n


# --- projectiles and sun -------------------------------------------------

func spawn_projectile(id: StringName, row: int, from: Vector2, source: Node) -> Projectile:
	var pr := Projectile.new()
	pr.row = row
	pr.board = self
	pr.source = source
	pr.damage = float(Data.projectile_damage(id))
	pr.position = from + Vector2(24, -12)
	_projectiles.add_child(pr)
	return pr


## Drops a sun just above `at`, which settles slightly below it. Every sun is
## worth SunToken.VALUE, so there is no amount to pass.
func drop_sun(at: Vector2) -> void:
	_add_sun_token(at + Vector2(0, -30), at.y + 20.0)


func drop_sun_from_sky() -> void:
	var at := grid_to_world(randi() % rows, randi() % cols)
	_add_sun_token(Vector2(at.x, origin.y - 40.0), at.y)


func _add_sun_token(at: Vector2, rest_y: float) -> SunToken:
	var s := SunToken.new()
	s.position = at
	s.fall_to_y = rest_y
	s.collect_target = to_global(sun_collect_target)
	s.collected.connect(func(c): _on_sun_collected(c))
	_suns.add_child(s)
	Audio.play(&"sun.drop", at)
	return s


func _on_sun_collected(token: Collectable) -> void:
	add_sun(SunToken.VALUE)
	Audio.play(&"sun.collect", token.position)


## Drops plant food where a carrier zombie died.
func drop_plant_food(at: Vector2) -> PlantFoodToken:
	var t := PlantFoodToken.new()
	t.position = at + Vector2(0, -30)
	t.fall_to_y = at.y + 10.0
	t.collect_target = to_global(plant_food_collect_target)
	t.collected.connect(func(c): _on_plant_food_collected(c))
	_suns.add_child(t)
	Audio.play(&"plantfood.drop", at)
	return t


func _on_plant_food_collected(token: Collectable) -> void:
	add_plant_food(PlantFoodToken.VALUE)
	Audio.play(&"plantfood.collect", token.position)


func add_plant_food(amount: int) -> void:
	plant_food = clampi(plant_food + amount, 0, max_plant_food)
	plant_food_changed.emit(plant_food)


func spend_plant_food() -> bool:
	if plant_food <= 0:
		return false
	plant_food -= 1
	plant_food_changed.emit(plant_food)
	return true


## Feeds the plant in a cell, if the player has food and the plant uses it.
func feed_plant(row: int, col: int) -> bool:
	var p := plant_at(row, col)
	if p == null or plant_food <= 0:
		return false
	if not p.apply_plant_food():
		return false
	spend_plant_food()
	Audio.play(&"plant.food", p.position)
	return true


func add_sun(amount: int) -> void:
	sun += amount
	sun_changed.emit(sun)


func spend_sun(amount: int) -> bool:
	if sun < amount:
		return false
	sun -= amount
	sun_changed.emit(sun)
	return true


# --- input ---------------------------------------------------------------

func _unhandled_input(event: InputEvent) -> void:
	if not (event is InputEventMouseButton and event.pressed
			and event.button_index == MOUSE_BUTTON_LEFT):
		return
	var at := get_local_mouse_position()

	# Sun is picked up by hovering, so a click only ever places, digs or feeds.
	if plant_food_active:
		if feed_plant(world_to_row(at.y), world_to_col(at.x)):
			plant_food_active = false
			get_viewport().set_input_as_handled()
		return
	if shovel_active:
		if dig_up(world_to_row(at.y), world_to_col(at.x)):
			get_viewport().set_input_as_handled()
		return
	if selected_seed.is_empty():
		return
	var kind := StringName(selected_seed.get("kind", &"plant"))
	var id := StringName(selected_seed.get("id", &""))
	var slot := int(selected_seed.get("slot", -1))
	var row := world_to_row(at.y)
	var col := world_to_col(at.x)
	if not can_place_entity(kind, row, col):
		return
	# A packet still recharging cannot be used, however much sun is banked.
	if seed_bank != null and not seed_bank.is_recharged(slot):
		return
	# The bank owns the price: a conveyor packet is free, a chooser packet is
	# whatever its plant costs.
	var cost := seed_bank.cost_of(slot) if seed_bank != null else seed_cost(kind, id)
	if not spend_sun(cost):
		return
	if place_entity(kind, id, row, col) != null:
		if seed_bank != null:
			seed_bank.consume(slot)
		selected_seed = {}
	get_viewport().set_input_as_handled()


# --- placeholder lawn ----------------------------------------------------

func _draw() -> void:
	for r in rows:
		var locked := not is_row_plantable(r)
		for c in cols:
			var rect := Rect2(origin + Vector2(c * cell_size.x, r * cell_size.y), cell_size)
			var light := (r + c) % 2 == 0
			draw_rect(rect, lawn_light if light else lawn_dark, true)
			if locked:
				draw_rect(rect, locked_lane_tint, true)
	# House edge and the line zombies must not cross.
	draw_line(Vector2(house_x(), origin.y),
			Vector2(house_x(), origin.y + rows * cell_size.y), house_line, 4.0)
