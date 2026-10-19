class_name DetachedLimb
extends Node2D
## A piece that has come off something: an arm knocked loose, a head on death.
##
## It is handed the sprites the rig was drawing, already at the transform they
## had, so the moment of separation is seamless - nothing pops or jumps. From
## there it is only physics and a fade.

@export var gravity: float = 900.0
@export var spin: float = 4.0
@export var lifetime: float = 1.6

var velocity := Vector2.ZERO

var _left: float = 0.0


func _init() -> void:
	_left = lifetime


## `piece` is what Armature.detach_slots handed back.
static func drop(piece: Node2D, toward: int, floor_y: float) -> DetachedLimb:
	var limb := DetachedLimb.new()
	limb.transform = piece.transform
	piece.transform = Transform2D.IDENTITY
	limb.add_child(piece)
	limb.velocity = Vector2(toward * randf_range(40.0, 110.0),
			-randf_range(180.0, 300.0))
	limb.spin = randf_range(-5.0, 5.0)
	limb.set_meta(&"floor_y", floor_y)
	return limb


func _process(delta: float) -> void:
	velocity.y += gravity * delta
	position += velocity * delta
	rotation += spin * delta
	var floor_y: float = get_meta(&"floor_y", INF)
	if position.y >= floor_y:
		position.y = floor_y
		velocity = Vector2.ZERO
		spin = 0.0
	_left -= delta
	if _left <= 0.0:
		queue_free()
	elif _left < 0.5:
		modulate.a = _left / 0.5
