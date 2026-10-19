class_name Armature
extends Node2D
## Plays one DragonBones armature.
##
## Bones are plain Node2Ds in a parent chain, slots are Sprite2Ds hung off
## them, and an animation is sampled into the bones each frame. Godot's own
## transform propagation then does the hierarchy work, which is why there is
## no matrix maths here.
##
## The heavy data - skeleton, texture, atlas regions - belongs to a shared
## ArmatureSet, so a lane full of zombies is a lane full of nodes over one
## copy of the art.

signal animation_finished(name: StringName)

## Frames per second the export was authored at.
var frame_rate: float = 30.0
var playing: StringName = &""
var looping: bool = true
## Scales playback, so a buffed or slowed entity animates to match.
var speed_scale: float = 1.0

var _set: ArmatureSet = null
var _armature: Dictionary = {}
var _bones: Dictionary = {}          ## bone name -> Node2D
var _bone_rest: Dictionary = {}      ## bone name -> {pos, rot, scale}
var _slots: Dictionary = {}          ## slot name -> Sprite2D
var _animations: Dictionary = {}     ## name -> animation dict
## The animation being played, flattened to per-bone tracks of
## {time, pos, rot, scale} so sampling is a search and a lerp.
var _tracks: Dictionary = {}
var _duration: float = 0.0
var _time: float = 0.0


func setup(source: ArmatureSet, armature_name: StringName) -> bool:
	if source == null or not source.has_armature(armature_name):
		return false
	_set = source
	_armature = source.armature(armature_name)
	frame_rate = float(_armature.get("frameRate", source.frame_rate))
	if frame_rate <= 0.0:
		frame_rate = source.frame_rate
	_build_bones()
	_build_slots()
	for entry in (_armature.get("animation", []) as Array):
		if entry is Dictionary and entry.has("name"):
			_animations[StringName(entry["name"])] = entry
	return true


func animation_names() -> Array:
	var names := _animations.keys()
	names.sort()
	return names


func has_animation(name: StringName) -> bool:
	return _animations.has(name)


## Plays `name`. Returns false if this armature has no such animation, so a
## caller can fall back rather than silently freeze.
func play(name: StringName, loop: bool = true, restart: bool = false) -> bool:
	if not _animations.has(name):
		return false
	if playing == name and not restart:
		looping = loop
		return true
	playing = name
	looping = loop
	_time = 0.0
	_flatten(_animations[name])
	_apply(0.0)
	return true


## The first of `candidates` this armature actually has. Lets an entity ask
## for "Walk" and settle for "Idle" without knowing which rig it got.
func play_first(candidates: Array, loop: bool = true) -> bool:
	for name in candidates:
		if play(StringName(name), loop):
			return true
	return false


func _build_bones() -> void:
	for entry in (_armature.get("bone", []) as Array):
		if not (entry is Dictionary):
			continue
		var name := StringName(entry.get("name", ""))
		if name == &"":
			continue
		var node := Node2D.new()
		node.name = String(name)
		var rest := _transform_of(entry.get("transform", {}))
		node.position = rest.pos
		node.rotation = rest.rot
		node.scale = rest.scale
		_bones[name] = node
		_bone_rest[name] = rest
	# Parent second, so a bone declared before its parent still lands right.
	for entry in (_armature.get("bone", []) as Array):
		if not (entry is Dictionary):
			continue
		var name := StringName(entry.get("name", ""))
		var parent := StringName(entry.get("parent", ""))
		var node: Node2D = _bones.get(name)
		if node == null:
			continue
		var host: Node2D = _bones.get(parent)
		if host != null:
			host.add_child(node)
		else:
			add_child(node)


func _build_slots() -> void:
	var skins := _armature.get("skin", []) as Array
	if skins.is_empty():
		return
	var displays := {}
	for slot_entry in ((skins[0] as Dictionary).get("slot", []) as Array):
		if slot_entry is Dictionary:
			displays[StringName(slot_entry.get("name", ""))] = slot_entry

	# Declaration order is draw order, so each slot goes in front of the last.
	for entry in (_armature.get("slot", []) as Array):
		if not (entry is Dictionary):
			continue
		var name := StringName(entry.get("name", ""))
		var parent := StringName(entry.get("parent", ""))
		var host: Node2D = _bones.get(parent, self)
		var skin_slot: Dictionary = displays.get(name, {})
		var options := skin_slot.get("display", []) as Array
		var index := int(entry.get("displayIndex", 0))
		if index < 0 or index >= options.size():
			continue
		var display: Dictionary = options[index]
		# `name` names the display; `path` names the texture when they differ,
		# which is how one slot carries both mouth and mouth_open.
		var region := StringName(display.get("path", display.get("name", "")))
		var texture: AtlasTexture = _set.region(region)
		if texture == null:
			continue
		var sprite := Sprite2D.new()
		sprite.name = String(name)
		sprite.texture = texture
		sprite.centered = true
		sprite.offset = _set.region_offset(region)
		var place := _transform_of(display.get("transform", {}))
		sprite.position = place.pos
		sprite.rotation = place.rot
		sprite.scale = place.scale
		host.add_child(sprite)
		_slots[name] = sprite


## DragonBones omits anything at its default, so every field has to be
## defaulted rather than read. skX is the rotation; skY differs from it only
## for sheared parts, which none of the tutorial art uses.
func _transform_of(raw: Variant) -> Dictionary:
	var t: Dictionary = raw if raw is Dictionary else {}
	return {
		"pos": Vector2(float(t.get("x", 0.0)), float(t.get("y", 0.0))),
		"rot": deg_to_rad(float(t.get("skX", 0.0))),
		"scale": Vector2(float(t.get("scX", 1.0)), float(t.get("scY", 1.0))),
	}


## Turns one animation's frame lists into per-bone tracks keyed by time.
##
## DragonBones stores a frame's `duration` - how long until the next one -
## rather than its timestamp, so the running total is what has to be kept.
func _flatten(animation: Dictionary) -> void:
	_tracks.clear()
	_duration = float(animation.get("duration", 0)) / frame_rate
	for entry in (animation.get("bone", []) as Array):
		if not (entry is Dictionary):
			continue
		var name := StringName(entry.get("name", ""))
		if not _bones.has(name):
			continue
		_tracks[name] = {
			"translate": _timeline(entry.get("translateFrame", []), "x", "y", 0.0),
			"rotate": _timeline(entry.get("rotateFrame", []), "angle", "", 0.0),
			"scale": _timeline(entry.get("scaleFrame", []), "x", "y", 1.0),
		}


func _timeline(frames: Variant, key_a: String, key_b: String,
		fallback: float) -> Array:
	var out: Array = []
	if not (frames is Array):
		return out
	var at := 0.0
	for frame in (frames as Array):
		if not (frame is Dictionary):
			continue
		out.append({
			"time": at / frame_rate,
			"a": float(frame.get(key_a, fallback)),
			"b": float(frame.get(key_b, fallback)) if key_b != "" else 0.0,
		})
		at += float(frame.get("duration", 0))
	return out


## Linear sample of one track. DragonBones' tweenEasing is ignored: these are
## short cycles and the difference is not visible at this size.
func _sample(track: Array, time: float, fallback: Vector2) -> Vector2:
	if track.is_empty():
		return fallback
	var first: Dictionary = track[0]
	if time <= float(first["time"]) or track.size() == 1:
		return Vector2(float(first["a"]), float(first["b"]))
	for i in range(track.size() - 1):
		var a: Dictionary = track[i]
		var b: Dictionary = track[i + 1]
		var ta := float(a["time"])
		var tb := float(b["time"])
		if time < tb:
			var t: float = 0.0 if tb <= ta else (time - ta) / (tb - ta)
			return Vector2(lerpf(float(a["a"]), float(b["a"]), t),
					lerpf(float(a["b"]), float(b["b"]), t))
	var last: Dictionary = track[track.size() - 1]
	return Vector2(float(last["a"]), float(last["b"]))


func _apply(time: float) -> void:
	for name in _tracks:
		var node: Node2D = _bones[name]
		var rest: Dictionary = _bone_rest[name]
		var track: Dictionary = _tracks[name]
		var move := _sample(track["translate"], time, Vector2.ZERO)
		node.position = rest["pos"] + move
		var spin := _sample(track["rotate"], time, Vector2.ZERO)
		node.rotation = rest["rot"] + deg_to_rad(spin.x)
		var size := _sample(track["scale"], time, Vector2.ONE)
		node.scale = Vector2(rest["scale"].x * size.x, rest["scale"].y * size.y)


func _process(delta: float) -> void:
	if playing == &"" or _duration <= 0.0:
		return
	_time += delta * maxf(speed_scale, 0.0)
	if _time >= _duration:
		if looping:
			_time = fmod(_time, _duration)
		else:
			_time = _duration
			var finished := playing
			playing = &""
			_apply(_time)
			animation_finished.emit(finished)
			return
	_apply(_time)
