class_name LaneSweeper
extends Node2D
## Something that rolls the length of a lane hurting every zombie it passes
## over - a cran-jelly's wave. It is not a projectile: it stops for nothing
## and is gone only once it leaves the lawn.

var board: Node = null
var source: Node = null
var row: int = 0
## Squares per second.
var speed: float = 4.4
var dps: float = 3000.0
## Half the width it covers, in pixels.
var half_width: float = 34.0
var color: Color = Color("c2304d", 0.75)


func _process(delta: float) -> void:
	if board == null:
		queue_free()
		return
	position.x += speed * board.cell_size.x * delta
	for z in board.hostile_zombies_in_row(row):
		if absf(z.position.x - position.x) <= half_width:
			z.take_damage(dps * delta, source if is_instance_valid(source) else null)
	if position.x > board.despawn_x():
		queue_free()


func _draw() -> void:
	draw_rect(Rect2(Vector2(-half_width, -30), Vector2(half_width * 2.0, 40)), color, true)
