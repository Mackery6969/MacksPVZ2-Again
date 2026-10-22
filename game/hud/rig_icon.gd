class_name RigIcon
extends Control
## A HUD rig inside a Control, so containers can lay it out like any widget.
## The rig hangs at the control's centre and plays the states its
## `hud:<id>` mapping names. With no art, `has_art()` is false and the owner
## shows its plain fallback instead.

var id: StringName = &""
var art: Armature = null
var state: StringName = &""


func _init(hud_id: StringName = &"", min_size := Vector2(48, 48)) -> void:
	id = hud_id
	custom_minimum_size = min_size
	mouse_filter = Control.MOUSE_FILTER_IGNORE


func _ready() -> void:
	art = Art.make(&"hud", id)
	if art == null:
		return
	add_child(art)
	_centre()
	resized.connect(_centre)
	play(&"idle")


func has_art() -> bool:
	return art != null


## Plays a state from the mapping. Returns false when the rig has no such
## state, so the caller can fall back.
func play(next: StringName, loop: bool = true) -> bool:
	if art == null:
		return false
	var anim := Art.animation_for(&"hud", id, next)
	if anim == &"":
		return false
	if next == state and art.playing == anim:
		return true
	state = next
	return art.play(anim, loop, true)


func _centre() -> void:
	if art != null:
		art.position = size * 0.5
