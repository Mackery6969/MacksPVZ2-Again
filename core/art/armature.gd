class_name Armature
extends Node2D
## A rig on screen: flat sprites driven by Godot's own AnimationPlayer.
##
## All the DragonBones-specific work happens once, in ArmatureBaker, which
## turns a rig into `Animation` resources. Nothing samples a timeline here,
## eases a curve or blends two poses by hand - `AnimationPlayer.play()` does
## all of it, and does it in engine code.
##
## The sprites are flat rather than a bone tree because DragonBones bones can
## refuse their parent's rotation or scale and Godot's nodes cannot. Resolving
## the chain at bake time removes the difference, and leaves a shallow scene:
## a lane of zombies is wide, not deep.
##
## The baked animations and the atlas regions belong to a shared ArmatureSet,
## so entities cost nodes, not memory.

signal animation_finished(name: StringName)

## How long to ease from one animation into the next. Without it a zombie
## switching from Walk to Death cuts straight to the death pose.
const BLEND_TIME := 0.12

var playing: StringName = &""
var looping: bool = true
## Which way the art looks: +1 as authored, -1 mirrored.
var facing: int = 1
## The horizontal placement the library fitted, before any mirroring.
var fitted_x: float = 0.0

var _player: AnimationPlayer = null
var _slots: Dictionary = {}          ## slot name -> Sprite2D
var _names: Array = []


func setup(source: ArmatureSet, armature_name: StringName) -> bool:
	if source == null or not source.has_armature(armature_name):
		return false
	var rig := source.rig(armature_name)
	if rig == null:
		return false

	for slot in rig.slots:
		var region: StringName = slot["region"]
		var sprite := Sprite2D.new()
		sprite.name = String(slot["name"])
		sprite.texture = source.region(region)
		sprite.centered = true
		sprite.offset = source.region_offset(region)
		add_child(sprite)
		_slots[slot["name"]] = sprite

	# The setup pose, which is also what a slot keeps when an animation never
	# touches it - those get no track at all.
	var rest := rig.slot_transforms(rig.world_at({}))
	for i in rig.slots.size():
		var sprite: Sprite2D = _slots[rig.slots[i]["name"]]
		sprite.transform = rest[i]

	_player = AnimationPlayer.new()
	_player.name = "Animations"
	add_child(_player)
	_player.add_animation_library(&"", source.animations(armature_name))
	_player.animation_finished.connect(_on_finished)
	_names = _player.get_animation_list()
	return true


## Playback speed, so a buffed or slowed entity animates to match.
func set_speed_scale(value: float) -> void:
	if _player != null:
		_player.speed_scale = maxf(value, 0.0)


func animation_names() -> Array:
	return _names.duplicate()


func has_animation(name: StringName) -> bool:
	return _player != null and _player.has_animation(name)


## Plays `name`, easing out of whatever was playing. Returns false if this
## armature has no such animation, so a caller can fall back rather than
## silently freeze.
##
## Looping is the caller's call, not the rig's: PopCap marks every animation
## as looping, including the death ones, and it is the game that knows an
## entity only dies once. A one-shot simply is not restarted when it ends.
func play(name: StringName, loop: bool = true, restart: bool = false) -> bool:
	if not has_animation(name):
		return false
	if playing == name and not restart and _player.is_playing():
		looping = loop
		return true
	playing = name
	looping = loop
	_player.play(name, BLEND_TIME)
	return true


## The first of `candidates` this armature actually has. Lets an entity ask
## for a walk and settle for an idle without knowing which rig it got.
func play_first(candidates: Array, loop: bool = true) -> bool:
	for name in candidates:
		if play(StringName(name), loop):
			return true
	return false


func _on_finished(name: StringName) -> void:
	if looping and name == playing:
		_player.play(name)
		return
	playing = &""
	animation_finished.emit(name)


## Mirrors the art. The flip is about this node's own origin, so the fitted
## offset has to flip with it - otherwise a mirrored entity slides to the
## wrong side of itself by twice that offset.
func set_facing(direction: int) -> void:
	var want: int = -1 if direction < 0 else 1
	if facing == want:
		return
	facing = want
	scale.x = absf(scale.x) * want
	position.x = fitted_x * want


## Slots the rig draws but the game should not, until something turns them
## on. PvZ rigs carry a detached-limb variant in its own slot - the basic
## zombie's `arm_here_ARM` is the broken stump, sitting on top of the intact
## arm - because the game decides when a limb comes off, not the rig.
func hide_slot(name: StringName, hidden: bool = true) -> void:
	var node: Sprite2D = _slots.get(name)
	if node != null:
		node.visible = not hidden


func slot_names() -> Array:
	var names := _slots.keys()
	names.sort()
	return names
