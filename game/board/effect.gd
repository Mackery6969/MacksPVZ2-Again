class_name Effect
extends Node2D
## A one-shot animation on the lawn - the dirt kicked up by planting - that
## removes itself when it ends. Without art it is never created at all.

## Seconds to keep it if the rig never reports finishing.
const MAX_LIFETIME := 3.0

var art: Armature = null
var _left: float = MAX_LIFETIME


## Plays `effect:<id>` in `state` at `at` under `parent`, or does nothing when
## there is no art for it. Returns the effect so a caller can reposition it.
static func spawn(parent: Node, id: StringName, state: StringName, at: Vector2,
		z: int = 0) -> Effect:
	var rig := Art.make(&"effect", id)
	if rig == null:
		return null
	var fx := Effect.new()
	fx.name = "Effect_%s" % id
	fx.position = at
	fx.z_index = z
	fx.art = rig
	fx.add_child(rig)
	parent.add_child(fx)
	if not rig.play(Art.animation_for(&"effect", id, state), false):
		fx.queue_free()
		return null
	rig.animation_finished.connect(func(_n): fx.queue_free())
	return fx


func _process(delta: float) -> void:
	_left -= delta
	if _left <= 0.0:
		queue_free()
