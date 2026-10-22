extends EntityComponent
## Hides underground until a zombie has walked past, then pops up and beats
## it from behind - celery stalker.
##
## Hidden, it cannot be eaten and zombies walk straight over it. Once it has
## had nothing to hit for `retract_delay` it goes back down.
##
## Config: damage, interval, reach (squares behind it), retract_delay,
## plantfood_children (copies planted in random free cells).

var damage: float = 25.0
var interval: float = 0.5
var reach: float = 1.5
var retract_delay: float = 3.0

var _hidden: bool = true
var _cooldown: float = 0.0
var _idle: float = 0.0


func setup() -> void:
	damage = float(cfg(&"damage", damage))
	interval = float(cfg(&"interval", interval))
	reach = float(cfg(&"reach", reach))
	retract_delay = float(cfg(&"retract_delay", retract_delay))
	_set_hidden(true)


func _process(delta: float) -> void:
	if host.is_dead:
		return
	var prey := _prey()
	if _hidden:
		if prey != null:
			_set_hidden(false)
			_cooldown = scaled(interval)
		return
	if prey == null:
		_idle += delta
		if _idle >= scaled(retract_delay):
			_set_hidden(true)
		return
	_idle = 0.0
	_cooldown -= delta
	if _cooldown > 0.0:
		return
	_cooldown = scaled(interval)
	prey.take_damage(damage, host)
	host.play_art_once(&"attack")


## The zombie that has just gone past: behind it, within reach. One standing
## right on top of it is not prey yet.
func _prey() -> Character:
	var span: float = reach * host.board.cell_size.x
	var best: Character = null
	for t in host.board.plant_targets_in_row(host.row):
		var behind: float = host.position.x - t.position.x
		if behind > host.board.cell_size.x * 0.25 and behind <= span:
			if best == null or t.position.x > best.position.x:
				best = t
	return best


func _set_hidden(value: bool) -> void:
	_hidden = value
	_idle = 0.0
	host.set_runtime_tag(&"hidden", value)
	host.set_runtime_tag(&"uneatable", value)
	host.queue_redraw()


## Plant food: patch up, and plant copies of itself in free cells.
func on_plantfood() -> bool:
	host.heal(host.max_health)
	var count := int(cfg(&"plantfood_children", 3))
	var cells: Array[Vector2i] = []
	for r in host.board.rows:
		for c in host.board.cols:
			if host.board.can_place_entity(&"plant", host.entity_id(), r, c):
				cells.append(Vector2i(c, r))
	cells.shuffle()
	for cell in cells.slice(0, count):
		host.board.place_preset_plant(host.entity_id(), cell.y, cell.x)
	return true
