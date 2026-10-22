extends EntityComponent
## Turns into another plant a moment after it is planted - imitater. The
## plant comes from the seed packet (`Plant.imitates`), or is picked at random
## from anything that could grow in the cell. Plant food given while it is
## still an imitater is passed on.
##
## Config: delay, exclude (plant ids it never becomes).

var _timer: float = 0.0
var _fed: bool = false


func setup() -> void:
	_timer = float(cfg(&"delay", 1.0))
	host.set_runtime_tag(&"uneatable", true)


func _process(delta: float) -> void:
	if host.is_dead:
		return
	_timer -= delta
	if _timer > 0.0:
		return
	var board = host.board
	var row: int = host.row
	var col: int = host.col
	var into: StringName = host.imitates if host.imitates != &"" else _random_plant()
	# The imitater's own death is not a plant dying here; whatever an
	# intensive carrot would have brought back stays the same.
	var remembered: StringName = board.last_dead_plant(row, col)
	host.die()
	board.remember_dead_plant(row, col, remembered)
	if into == &"":
		return
	var grown: Plant = board.place_preset_plant(into, row, col)
	if grown != null and _fed:
		grown.apply_plant_food()


func _random_plant() -> StringName:
	var exclude: Array = cfg(&"exclude", [])
	var ids: Array = Data.plants.keys()
	ids.shuffle()
	for id in ids:
		var def: PlantDef = Data.plants[id]
		if id == host.entity_id() or exclude.has(String(id)) or def.components.is_empty():
			continue
		if def.component_spec(&"mint_buff") != null or Board.grave_need(def) != &"":
			continue
		if Board.is_carrier_def(def):
			continue
		return id
	return &""


func on_plantfood() -> bool:
	if _fed:
		return false
	_fed = true
	return true
