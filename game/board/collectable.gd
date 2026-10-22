class_name Collectable
extends Node2D
## Something the player picks up off the lawn: sun, plant food.
##
## Falls to a resting spot, waits, fades, then expires. Collection is by hover,
## so the player sweeps the lawn rather than clicking each one, and a collected
## item flies to its counter before being banked - the counter ticks up in step
## with the animation.

signal collected(source: Collectable)

@export_group("Timing")
## Seconds it stays collectable after landing.
@export var lifetime: float = 12.0
@export var fall_speed: float = 90.0
## Seconds for a collected item to reach its counter.
@export var fly_time: float = 0.45
## Seconds of fading before expiry, so disappearing is expected not sudden.
@export var fade_out_time: float = 2.0

@export_group("Hit area")
@export var radius: float = 20.0
## Extra reach around the item that still counts as hovering it.
@export var hover_slack: float = 6.0

@export_group("Appearance")
## Size it shrinks to as it reaches the counter.
@export var fly_scale: float = 0.35

## Where a collected item flies to, in global coordinates. Set by the board.
var collect_target := Vector2.ZERO
var fall_to_y: float = 0.0
## Pull on a tossed item, in pixels per second squared.
var gravity: float = 0.0
## Horizontal drift of a tossed item, and its upward speed, in pixels per
## second.
var toss_velocity := Vector2.ZERO
## How far a tossed item is off the ground. It is drawn this far above
## `fall_to_y` and lands when this reaches zero.
var height: float = 0.0
## Where a tossed item stays between, so a toss near the edge cannot carry it
## off the lawn.
var x_limits := Vector2(-INF, INF)

var _falling: bool = true
var _tossed: bool = false
var _collected: bool = false
## The item's rig, when its art was extracted. Subclasses draw a placeholder
## only while this is null.
var art: Armature = null


## Which `collectable:<id>` art this item uses. Empty means none.
func art_id() -> StringName:
	return &""


func _ready() -> void:
	var id := art_id()
	if id == &"":
		return
	art = Art.make(&"collectable", id)
	if art == null:
		return
	add_child(art)
	art.play(Art.animation_for(&"collectable", id, &"idle"))
	queue_redraw()


func _process(delta: float) -> void:
	if _collected:
		return

	if _tossed:
		_fly(delta)
	elif _falling:
		position.y = minf(position.y + fall_speed * delta, fall_to_y)
		if is_equal_approx(position.y, fall_to_y):
			_falling = false
	else:
		lifetime -= delta
		if lifetime <= 0.0:
			queue_free()
			return
		if fade_out_time > 0.0 and lifetime < fade_out_time:
			modulate.a = clampf(lifetime / fade_out_time, 0.0, 1.0)

	# Polled rather than event-driven so an item landing under a stationary
	# cursor is still picked up.
	if contains_point(get_global_mouse_position()):
		collect()


## Throws the item up and out from `height` pixels above the ground at
## `ground_y`, the way PVZGE's droppings move: a height above the ground that
## gravity pulls down, and a drift that stops when it lands. `velocity.y` is
## upward speed.
func toss(ground_y: float, start_height: float, velocity: Vector2, pull: float) -> void:
	fall_to_y = ground_y
	height = maxf(start_height, 0.0)
	toss_velocity = velocity
	gravity = pull
	_tossed = true
	_falling = true
	position.y = fall_to_y - height


func _fly(delta: float) -> void:
	position.x = clampf(position.x + toss_velocity.x * delta, x_limits.x, x_limits.y)
	height += toss_velocity.y * delta
	toss_velocity.y -= gravity * delta
	if height <= 0.0 and toss_velocity.y < 0.0:
		height = 0.0
		_tossed = false
		_falling = false
	position.y = fall_to_y - height


## Starts the fly-to-counter animation. Idempotent, so hover polling cannot
## collect the same item twice while the animation plays.
func collect() -> void:
	if _collected:
		return
	_collected = true

	var tween := create_tween()
	tween.set_parallel(true)
	tween.tween_property(self, "global_position", collect_target, fly_time) \
			.set_trans(Tween.TRANS_CUBIC).set_ease(Tween.EASE_IN)
	tween.tween_property(self, "scale", Vector2.ONE * fly_scale, fly_time) \
			.set_trans(Tween.TRANS_SINE)
	tween.tween_property(self, "modulate:a", 0.0, fly_time * 0.5) \
			.set_delay(fly_time * 0.5)
	tween.finished.connect(_bank)


## Grants the item once it has reached the counter.
func _bank() -> void:
	collected.emit(self)
	queue_free()


func is_collected() -> bool:
	return _collected


func contains_point(point: Vector2) -> bool:
	return point.distance_to(global_position) <= radius + hover_slack
