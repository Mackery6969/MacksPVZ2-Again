class_name Armature
extends Node2D
## Plays one DragonBones armature.
##
## Bone transforms are composed here rather than by parenting Node2Ds,
## because the two do not agree. Godot multiplies a parent's scale into a
## child's whole basis, so a rotated child under a non-uniformly scaled parent
## comes out sheared - and the basic zombie's `pressure` bone is scaled 0.5 in
## Y, which laid the whole zombie on its side. DragonBones applies a parent's
## scale to the child's position and passes the scale down, never shearing.
##
## Composing it ourselves also means a flat node tree: every sprite is a direct
## child of this node, so a lane of zombies is a wide shallow scene rather than
## a deep one.
##
## The heavy data - skeleton, texture, atlas regions - belongs to a shared
## ArmatureSet, so many entities cost nodes, not memory.

signal animation_finished(name: StringName)

## Frames per second the export was authored at.
var frame_rate: float = 30.0
var playing: StringName = &""
var looping: bool = true
## Scales playback, so a buffed or slowed entity animates to match.
var speed_scale: float = 1.0
## Which way the art looks: +1 as authored, -1 mirrored.
var facing: int = 1

## The horizontal placement the library fitted, before any mirroring.
var fitted_x: float = 0.0

var _set: ArmatureSet = null
var _armature: Dictionary = {}

## Bones, parents before children, so one pass composes the whole skeleton.
## Each: {name, parent (index, -1 for none), pos, rot, scale}
var _bones: Array[Dictionary] = []
var _bone_index: Dictionary = {}     ## name -> index into _bones
## Composed world transforms for this frame, parallel to _bones.
var _world: Array[Dictionary] = []
## Sprites, each: {node, bone (index), pos, rot, scale} in bone space.
var _slots: Array[Dictionary] = []

var _animations: Dictionary = {}
var _tracks: Dictionary = {}         ## bone index -> flattened tracks
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
	_pose()
	for entry in (_armature.get("animation", []) as Array):
		if entry is Dictionary and entry.has("name"):
			_animations[StringName(entry["name"])] = entry
	return true


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
	_pose()
	return true


## The first of `candidates` this armature actually has. Lets an entity ask
## for a walk and settle for an idle without knowing which rig it got.
func play_first(candidates: Array, loop: bool = true) -> bool:
	for name in candidates:
		if play(StringName(name), loop):
			return true
	return false


# --- building ------------------------------------------------------------

func _build_bones() -> void:
	var raw := _armature.get("bone", []) as Array
	# Parents first. The export is usually already in order, but a rig that
	# declares a child early would otherwise compose against a stale parent.
	var ordered: Array = []
	var placed := {}
	var pending := raw.duplicate()
	while not pending.is_empty():
		var progressed := false
		var still: Array = []
		for entry in pending:
			if not (entry is Dictionary):
				continue
			var parent := String(entry.get("parent", ""))
			if parent == "" or placed.has(parent):
				ordered.append(entry)
				placed[String(entry.get("name", ""))] = true
				progressed = true
			else:
				still.append(entry)
		pending = still
		if not progressed:
			# A missing or circular parent: take the rest as roots rather
			# than dropping them.
			for entry in pending:
				if entry is Dictionary:
					ordered.append(entry)
			break

	for entry in ordered:
		var name := StringName(entry.get("name", ""))
		if name == &"":
			continue
		var rest := _transform_of(entry.get("transform", {}))
		rest["name"] = name
		rest["parent"] = int(_bone_index.get(StringName(entry.get("parent", "")), -1))
		_bone_index[name] = _bones.size()
		_bones.append(rest)
	_world.resize(_bones.size())


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
		var bone := int(_bone_index.get(StringName(entry.get("parent", "")), -1))
		var options := (displays.get(name, {}) as Dictionary).get("display", []) as Array
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
		add_child(sprite)
		var place := _transform_of(display.get("transform", {}))
		place["node"] = sprite
		place["bone"] = bone
		_slots.append(place)


## DragonBones omits anything at its default, so every field has to be
## defaulted rather than read. skX is the rotation; skY differs from it only
## for sheared parts, which none of this art uses.
func _transform_of(raw: Variant) -> Dictionary:
	var t: Dictionary = raw if raw is Dictionary else {}
	return {
		"pos": Vector2(float(t.get("x", 0.0)), float(t.get("y", 0.0))),
		"rot": deg_to_rad(float(t.get("skX", 0.0))),
		"scale": Vector2(float(t.get("scX", 1.0)), float(t.get("scY", 1.0))),
	}


# --- posing --------------------------------------------------------------

## Applies a parent transform to a local one, DragonBones style: the parent's
## scale moves the child but does not shear it.
func _compose(parent: Dictionary, local: Dictionary) -> Dictionary:
	var scaled := Vector2(local["pos"].x * parent["scale"].x,
			local["pos"].y * parent["scale"].y)
	return {
		"pos": parent["pos"] + scaled.rotated(parent["rot"]),
		"rot": parent["rot"] + local["rot"],
		"scale": Vector2(parent["scale"].x * local["scale"].x,
				parent["scale"].y * local["scale"].y),
	}


const IDENTITY := {"pos": Vector2.ZERO, "rot": 0.0, "scale": Vector2.ONE}


func _pose() -> void:
	for i in _bones.size():
		var bone: Dictionary = _bones[i]
		var local := bone
		if _tracks.has(i):
			local = _animated(i, bone)
		var parent: int = bone["parent"]
		_world[i] = _compose(_world[parent] if parent >= 0 else IDENTITY, local)

	for slot in _slots:
		var bone: int = slot["bone"]
		var world := _compose(_world[bone] if bone >= 0 else IDENTITY, slot)
		var node: Sprite2D = slot["node"]
		node.position = world["pos"]
		node.rotation = world["rot"]
		node.scale = world["scale"]


## The bone's transform for the current time: its rest pose with the
## animation's offsets applied. DragonBones stores offsets, not absolutes.
func _animated(index: int, rest: Dictionary) -> Dictionary:
	var track: Dictionary = _tracks[index]
	var move := _sample(track["translate"], _time, Vector2.ZERO)
	var spin := _sample(track["rotate"], _time, Vector2.ZERO)
	var size := _sample(track["scale"], _time, Vector2.ONE)
	return {
		"pos": rest["pos"] + move,
		"rot": rest["rot"] + deg_to_rad(spin.x),
		"scale": Vector2(rest["scale"].x * size.x, rest["scale"].y * size.y),
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
		var index := int(_bone_index.get(StringName(entry.get("name", "")), -1))
		if index < 0:
			continue
		_tracks[index] = {
			"translate": _timeline(entry.get("translateFrame", []), "x", "y", 0.0),
			# The rotation key is `rotate`, not `angle`.
			"rotate": _timeline(entry.get("rotateFrame", []), "rotate", "", 0.0),
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


## Linear sample of one track. DragonBones' per-frame curves are ignored:
## these are short cycles and the easing is not visible at this size.
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
			_pose()
			animation_finished.emit(finished)
			return
	_pose()
