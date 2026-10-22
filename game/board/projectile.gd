class_name Projectile
extends Node2D
## A pea or similar shot travelling along one lane.
##
## `direction` decides both which way it goes and what it can hit, since
## nothing shoots past its own side: a plant's pea travels right into zombies,
## a boss's missile travels left into plants.
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

## +1 travels right (a plant's shot), -1 travels left (a zombie's).
@export var direction: int = 1

var row: int = 0
var source: Node = null
var board: Node = null
## Artwork, when some is mapped for this projectile; null keeps the drawn dot.
var art: Armature = null

## Tags a target must have for this shot to affect it. Mods use these to make
## a projectile selective without touching zombie data.
@export var required_tags: Array[StringName] = []
@export var excluded_tags: Array[StringName] = []


## Gives this shot its artwork. Called by the board once the id is known,
## since a projectile has no definition of its own to read it from.
func attach_art(id: StringName) -> void:
	var built := Art.make(&"projectile", id)
	if built == null:
		return
	art = built
	art.set_facing(direction)
	add_child(art)
	art.play(Art.animation_for(&"projectile", id, &"idle"))
	queue_redraw()


func _process(delta: float) -> void:
	var from_x := position.x
	position.x += direction * speed * delta
	if _check_hit(from_x, position.x):
		return
	if board == null:
		return
	if position.x > board.despawn_x() or position.x < board.house_x() - board.cell_size.x:
		queue_free()


## Hits the nearest valid target whose centre lies in the swept span.
## Returns true if the projectile was consumed.
func _check_hit(from_x: float, to_x: float) -> bool:
	if board == null:
		return false
	var lo := minf(from_x, to_x) - hit_radius
	var hi := maxf(from_x, to_x) + hit_radius

	var best: Node = null
	var best_x := INF * direction
	for t in _candidates():
		if t.is_dead or t.position.x < lo or t.position.x > hi:
			continue
		if not t.matches(required_tags, excluded_tags):
			continue
		# Whichever is nearest along the way it is going gets hit first.
		if (t.position.x - best_x) * direction < 0.0:
			best_x = t.position.x
			best = t
	if best == null:
		return false
	# The shooter may have been eaten or dug up while this was in flight.
	best.take_damage(damage, source if is_instance_valid(source) else null)
	queue_free()
	return true


## What this shot can hit: its own side is never a target. A plant's shot
## also breaks gravestones and ice blocks in its way.
func _candidates() -> Array:
	if direction < 0:
		return board.plants_in_row(row)
	return board.plant_targets_in_row(row)


func _draw() -> void:
	if art != null:
		return
	draw_circle(Vector2.ZERO, draw_radius, color)
	draw_circle(Vector2(-2, -2), draw_radius * 0.38, color.lightened(0.4))
