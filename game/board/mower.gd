class_name Mower
extends Node2D
## The last line of defence in one lane.
##
## Sits parked at the house until a zombie reaches it, then drives down the
## lane destroying every hostile zombie it touches before leaving the board.
## A lane gets exactly one, so losing it means the next zombie through that
## lane ends the level.

signal triggered(row: int)
signal finished(row: int)

@export var speed: float = 420.0
@export var body_size := Vector2(46, 30)
@export var body_color: Color = Color("c0392b")
@export var blade_color: Color = Color("9aa6b2")
@export var parked_color: Color = Color("e07a5f")

var row: int = 0
var board: Node = null

var _running: bool = false
var _spent: bool = false


func is_available() -> bool:
	return not _spent


func is_running() -> bool:
	return _running


## Sets the mower off. Returns false if it has already been used.
func trigger() -> bool:
	if _spent:
		return false
	_spent = true
	_running = true
	triggered.emit(row)
	queue_redraw()
	return true


func _process(delta: float) -> void:
	if not _running or board == null:
		return
	var from_x := position.x
	position.x += speed * delta
	_mow(from_x, position.x)
	if position.x > board.despawn_x():
		_running = false
		finished.emit(row)
		queue_free()


## Destroys hostile zombies the mower has passed over. Swept rather than
## sampled: at 420 px/s the mower covers more ground in one frame than a
## zombie is wide, so testing only the current position lets zombies survive
## by being stepped over. Charmed zombies are the player's, so they are safe.
func _mow(from_x: float, to_x: float) -> void:
	var reach: float = body_size.x * 0.5 + 12.0
	var lo := minf(from_x, to_x) - reach
	var hi := maxf(from_x, to_x) + reach
	for z in board.hostile_zombies_in_row(row):
		if z.position.x >= lo and z.position.x <= hi:
			z.take_damage(z.health + 1.0, self)


func _draw() -> void:
	var rect := Rect2(Vector2(-body_size.x * 0.5, -body_size.y), body_size)
	draw_rect(rect, body_color if _running else parked_color, true)
	draw_rect(rect, body_color.darkened(0.45), false, 2.0)
	# Blade housing at the front, so facing is readable.
	draw_rect(Rect2(Vector2(body_size.x * 0.5 - 6, -body_size.y * 0.7),
			Vector2(10, body_size.y * 0.7)), blade_color, true)
