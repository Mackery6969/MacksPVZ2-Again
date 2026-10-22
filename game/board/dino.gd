class_name Dino
extends Node2D
## A Jurassic Marsh dinosaur: neither plant nor zombie, it wanders into one
## lane for a while and throws the zombies there around - almost always
## toward the house.
##
## Which of five things it does is data (`behaviour` in data/native/dinos),
## so a pack can add a dinosaur by reusing one or override the numbers:
##   kick  - raptor: paces the right half of the lane kicking zombies forward
##   carry - pterodactyl: swoops on zombies at the back and drops them far ahead
##   toss  - stegosaurus: scoops up zombies passing its tail, tosses them anywhere
##   fling - ankylosaurus: knocks zombies in front of it toward the house
##   roar  - T. rex: roars and leaves (a wild one only bites once charmed)
##
## Placeholder art: a big tinted block with the dinosaur's initial.

const COLORS := {
	&"kick": Color("c76b3a"), &"carry": Color("8a6fc4"), &"toss": Color("6fa35a"),
	&"fling": Color("a38a4f"), &"roar": Color("b84a4a"),
}
const LEAVE_SPEED := 3.0

var board: Board
var spec: Dictionary = {}
var row: int = 0
var behaviour: StringName = &""
var leaving: bool = false

## How many more times it acts before it has had enough.
var uses_left: int = 0
var _time_left: float = 40.0
var _timer: float = 0.0
var _heading: int = -1
var _cooldowns: Dictionary = {}   ## Zombie -> seconds before it can be kicked again
var _held: Array = []             ## zombies sitting on a stegosaurus's tail


func setup(dino_spec: Dictionary, owning_board: Board, lane: int) -> void:
	spec = dino_spec
	board = owning_board
	row = lane
	behaviour = StringName(spec.get("behaviour", "kick"))
	_time_left = float(spec.get("max_time", 40.0))
	z_index = board.lane_z(row, board.LAYER_ZOMBIE)
	var start := board.spawn_x()
	match behaviour:
		&"kick":
			uses_left = int(spec.get("kicks", 5))
		&"carry":
			uses_left = int(spec.get("flights", 3))
			start = _column_x(float(spec.get("idle_column", 8.5)))
			_timer = float(spec.get("flight_interval", 5.0))
		&"toss":
			uses_left = int(spec.get("tosses", 3))
			start = _column_x(float(spec.get("idle_column", 6.5)))
		&"fling":
			uses_left = int(spec.get("flings", 5))
			start = _column_x(float(spec.get("idle_column", 8.8)))
			_timer = float(spec.get("attack_interval", 5.0)) * 0.5
		&"roar":
			uses_left = int(spec.get("roars", 1))
			start = _column_x(float(spec.get("idle_column", 6.0)))
			_timer = float(spec.get("roar_delay", 3.0))
	position = Vector2(start, board.grid_to_world(row, 0).y)
	queue_redraw()


## The x of a fractional column, so 6.5 is the edge between columns 6 and 7.
func _column_x(col: float) -> float:
	return board.origin.x + (col + 0.5) * board.cell_size.x


func _range(key: String, low: float, high: float) -> float:
	var r: Variant = spec.get(key, {})
	if r is Dictionary:
		return randf_range(float(r.get("min", low)), float(r.get("max", high)))
	return float(r)


func _zombies() -> Array:
	return board.hostile_zombies_in_row(row)


func _process(delta: float) -> void:
	if board == null:
		return
	if leaving:
		position.x += LEAVE_SPEED * board.cell_size.x * delta
		if position.x > board.despawn_x():
			queue_free()
		return
	_time_left -= delta
	if _time_left <= 0.0 or uses_left <= 0:
		leave()
		return
	match behaviour:
		&"kick": _kick(delta)
		&"carry": _carry(delta)
		&"toss": _toss(delta)
		&"fling": _fling(delta)
		&"roar": _roar(delta)


## Lets go of anything held and heads off the lawn.
func leave() -> void:
	if leaving:
		return
	leaving = true
	for z in _held:
		if is_instance_valid(z) and not z.is_dead:
			z.release()
	_held.clear()


func _kick(delta: float) -> void:
	for z in _cooldowns.keys():
		_cooldowns[z] -= delta
		if _cooldowns[z] <= 0.0 or not is_instance_valid(z):
			_cooldowns.erase(z)
	# Pace between the walk edge and the right end of the lane.
	# Like a zombie, it hurries on from off-screen until it reaches the lawn.
	var hurry := Zombie.ENTERING_SPEED if position.x > board.lawn_right_x() else 1.0
	position.x += _heading * float(spec.get("speed", 0.65)) * hurry \
			* board.cell_size.x * delta
	var left_edge := _column_x(float(spec.get("walk_edge_column", 4)))
	if position.x <= left_edge:
		_heading = 1
	elif position.x >= _column_x(board.cols - 1):
		_heading = -1
	var floor_x := _column_x(float(spec.get("kick_edge_column", 2)))
	# It kicks what is just ahead of it, whichever way it is facing.
	var reach := board.cell_size.x
	for z in _zombies():
		var ahead: float = (z.position.x - position.x) * _heading
		if _cooldowns.has(z) or ahead < -board.cell_size.x * 0.25 or ahead > reach:
			continue
		var to_x := maxf(z.position.x - float(spec.get("kick_distance", 3)) * board.cell_size.x,
				floor_x)
		if board.move_zombie(z, row, to_x):
			_cooldowns[z] = float(spec.get("same_zombie_cooldown", 4.5))
			uses_left -= 1
			return


func _carry(delta: float) -> void:
	_timer -= delta
	if _timer > 0.0:
		return
	_timer = float(spec.get("flight_interval", 5.0))
	var from_x := _column_x(float(spec.get("grab_from_column", 5)) - 0.5)
	var carried := 0
	var carry := int(spec.get("carry", 1))
	# The furthest-back zombies are the ones a swoop from the right reaches.
	var candidates := _zombies()
	candidates.reverse()
	for z in candidates:
		if carried >= carry:
			break
		if z.position.x < from_x or z.position.x > board.spawn_x():
			continue
		if board.move_zombie(z, row, _column_x(float(spec.get("drop_column", 0)))):
			carried += 1
	if carried > 0:
		uses_left -= 1


func _toss(delta: float) -> void:
	_held = _held.filter(func(z): return is_instance_valid(z) and not z.is_dead)
	var tail_end := position.x + 2.0 * board.cell_size.x
	if _held.size() < int(spec.get("per_toss", 3)):
		for z in _zombies():
			if _held.has(z) or z.movement_claimed or z.is_encased():
				continue
			if z.position.x >= position.x and z.position.x <= tail_end:
				_held.append(z)
				z.encase()
				if _held.size() == 1:
					_timer = float(spec.get("toss_ready_time", 1.5))
				if _held.size() >= int(spec.get("per_toss", 3)):
					break
	if _held.is_empty():
		return
	_timer -= delta
	if _timer > 0.0:
		return
	for z in _held:
		z.release()
		board.move_zombie(z, randi() % board.rows, _column_x(_range("throw_column", 3, 4)))
	_held.clear()
	uses_left -= 1


func _fling(delta: float) -> void:
	_timer -= delta
	if _timer > 0.0:
		return
	var reach := float(spec.get("reach", 3)) * board.cell_size.x
	var flung := 0
	for z in _zombies():
		if z.position.x <= position.x and z.position.x >= position.x - reach:
			if board.move_zombie(z, row, _column_x(_range("fling_column", 1.8, 2.3))):
				flung += 1
				if flung >= uses_left:
					break
	if flung > 0:
		uses_left -= flung
		_timer = float(spec.get("attack_interval", 5.0))


func _roar(delta: float) -> void:
	_timer -= delta
	if _timer > 0.0 or _zombies().is_empty():
		return
	uses_left -= 1
	_timer = float(spec.get("roar_delay", 3.0))
	queue_redraw()


func _draw() -> void:
	var size := Vector2(78, 60)
	var tint: Color = COLORS.get(behaviour, Color("888888"))
	var rect := Rect2(Vector2(-size.x * 0.5, -size.y * 0.8), size)
	draw_rect(rect, tint, true)
	draw_rect(rect, tint.darkened(0.45), false, 2.0)
	var font := ThemeDB.fallback_font
	draw_string(font, Vector2(-8, -size.y * 0.25),
			String(spec.get("id", "?")).substr(0, 1).to_upper(),
			HORIZONTAL_ALIGNMENT_LEFT, -1, 22, Color.WHITE)
