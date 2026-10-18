class_name Projectile
extends Node2D
## A pea or similar shot travelling right along one lane.
##
## Collision is swept rather than sampled: at 380 px/s a projectile moves
## further in one frame than a zombie is wide, so testing only the current
## position lets shots tunnel straight through targets on a slow frame.

## Pixels per second travelled down the lane.
@export var speed: float = 380.0
## Damage dealt to the first valid target hit.
@export var damage: float = 20.0
## Half-width of the hit window, in pixels, around the target's centre.
@export var hit_radius: float = 22.0
@export var draw_radius: float = 8.0
@export var color: Color = Color("7ad17a")

var row: int = 0
var source: Node = null
var board: Node = null

## Tags a target must have for this shot to affect it. Mods use these to make
## a projectile selective without touching zombie data.
@export var required_tags: Array[StringName] = []
@export var excluded_tags: Array[StringName] = []


func _process(delta: float) -> void:
	var from_x := position.x
	position.x += speed * delta
	if _check_hit(from_x, position.x):
		return
	if board and position.x > board.despawn_x():
		queue_free()


## Hits the nearest valid target whose centre lies in the swept span.
## Returns true if the projectile was consumed.
func _check_hit(from_x: float, to_x: float) -> bool:
	if board == null:
		return false
	var lo := minf(from_x, to_x) - hit_radius
	var hi := maxf(from_x, to_x) + hit_radius

	var best: Node = null
	var best_x := INF
	for z in board.hostile_zombies_in_row(row):
		if z.is_dead or z.position.x < lo or z.position.x > hi:
			continue
		if not z.matches(required_tags, excluded_tags):
			continue
		# Travelling right, so the leftmost candidate is hit first.
		if z.position.x < best_x:
			best_x = z.position.x
			best = z
	if best == null:
		return false
	# The shooter may have been eaten or dug up while this was in flight.
	best.take_damage(damage, source if is_instance_valid(source) else null)
	queue_free()
	return true


func _draw() -> void:
	draw_circle(Vector2.ZERO, draw_radius, color)
	draw_circle(Vector2(-2, -2), draw_radius * 0.38, color.lightened(0.4))
