class_name ArmatureBaker
extends RefCounted
## Converts one DragonBones armature into Godot's own animation system.
##
## This runs ONCE per armature and never again: everything DragonBones does
## differently from Godot is resolved here, at conversion time, so that
## playback is `AnimationPlayer.play()` and nothing else. Easing, blending,
## interpolation and timing are then the engine's problem rather than ours.
##
## Three things have to be resolved, and all three are why a bone tree of
## Node2Ds cannot simply be handed to Godot:
##
## 1. A transform is built from TWO skew angles. skX and skY are equal for a
##    rotation; where they differ they describe a mirror or a shear, which
##    Godot expresses as `skew` - the peashooter's stem is one.
## 2. A bone can refuse its parent's rotation or scale. The basic zombie's
##    head refuses both. Godot's node tree has no equivalent, so the chain is
##    resolved here and the sprites come out flat - every one a direct child,
##    which is also cheaper to transform.
## 3. Frames carry their own easing, as a cubic bezier or an easing factor.
##    Sampling at the source frame rate bakes that in, so Godot's linear
##    interpolation between samples reproduces it exactly.

## Each: {name, parent, local (Transform2D), inherit_rotation, inherit_scale,
##        tracks (per-animation, filled during baking)}
var bones: Array[Dictionary] = []
var bone_index: Dictionary = {}
## Each: {name, bone, xform (Transform2D), region, offset}
var slots: Array[Dictionary] = []

var frame_rate: float = 30.0

var _armature: Dictionary = {}
var _set: ArmatureSet = null
var _sockets: Dictionary = {}


## `sockets` maps a game-facing name to a bone - {"muzzle": "mouthhole"} -
## and each becomes a marker node animated like any slot, so the game can ask
## where a rig's mouth is at this instant without sampling anything itself.
func _init(source: ArmatureSet, armature_name: StringName,
		sockets: Dictionary = {}) -> void:
	_set = source
	_sockets = sockets
	_armature = source.armature(armature_name)
	frame_rate = float(_armature.get("frameRate", source.frame_rate))
	if frame_rate <= 0.0:
		frame_rate = source.frame_rate
	_read_bones()
	_read_slots()


# --- reading -------------------------------------------------------------

func _read_bones() -> void:
	var raw := _armature.get("bone", []) as Array
	# Parents first, so one pass composes the whole skeleton. The export is
	# usually already ordered, but a child declared early would otherwise
	# compose against a stale parent.
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
			for entry in pending:
				if entry is Dictionary:
					ordered.append(entry)
			break

	for entry in ordered:
		var name := StringName(entry.get("name", ""))
		if name == &"":
			continue
		bone_index[name] = bones.size()
		bones.append({
			"name": name,
			"parent": int(bone_index.get(StringName(entry.get("parent", "")), -1)),
			"raw": entry.get("transform", {}) if entry.get("transform") is Dictionary else {},
			"inherit_rotation": bool(entry.get("inheritRotation", true)),
			"inherit_scale": bool(entry.get("inheritScale", true)),
		})


func _read_slots() -> void:
	var skins := _armature.get("skin", []) as Array
	if skins.is_empty():
		return
	var displays := {}
	for entry in ((skins[0] as Dictionary).get("slot", []) as Array):
		if entry is Dictionary:
			displays[StringName(entry.get("name", ""))] = entry

	# Declaration order is draw order, so each slot goes in front of the last.
	for entry in (_armature.get("slot", []) as Array):
		if not (entry is Dictionary):
			continue
		var name := StringName(entry.get("name", ""))
		var options := (displays.get(name, {}) as Dictionary).get("display", []) as Array
		var index := int(entry.get("displayIndex", 0))
		if index < 0 or index >= options.size():
			continue
		var display: Dictionary = options[index]
		# `name` names the display; `path` names the texture when they differ,
		# which is how one slot carries both mouth and mouth_open.
		var region := StringName(display.get("path", display.get("name", "")))
		if _set.region(region) == null:
			continue
		slots.append({
			"name": name,
			"bone": int(bone_index.get(StringName(entry.get("parent", "")), -1)),
			"xform": matrix_of(display.get("transform", {})),
			"region": region,
		})

	# Sockets ride along as slots with nothing to draw.
	for alias in _sockets:
		var bone := int(bone_index.get(StringName(_sockets[alias]), -1))
		if bone < 0:
			push_warning("armature: no bone '%s' for socket '%s'"
					% [_sockets[alias], alias])
			continue
		slots.append({
			"name": StringName("socket_%s" % alias),
			"bone": bone,
			"xform": Transform2D.IDENTITY,
			"region": &"",
			"socket": StringName(alias),
		})


# --- DragonBones transform rules ----------------------------------------

## The matrix DragonBones builds from one transform. Two skew angles, not one
## rotation: the X axis comes from skY and the Y axis from skX, so equal
## angles give a rotation and unequal ones a mirror or a shear.
static func matrix_of(raw: Variant, offset: Dictionary = {}) -> Transform2D:
	var t: Dictionary = raw if raw is Dictionary else {}
	var sk_x := float(t.get("skX", 0.0))
	var sk_y := float(t.get("skY", sk_x))
	var pos := Vector2(float(t.get("x", 0.0)), float(t.get("y", 0.0)))
	var size := Vector2(float(t.get("scX", 1.0)), float(t.get("scY", 1.0)))
	if not offset.is_empty():
		pos += offset["pos"] as Vector2
		sk_x += float(offset["rot"])
		sk_y += float(offset["rot"])
		size *= offset["scale"] as Vector2
	var rx := deg_to_rad(sk_x)
	var ry := deg_to_rad(sk_y)
	return Transform2D(
			Vector2(cos(ry) * size.x, sin(ry) * size.x),
			Vector2(-sin(rx) * size.y, cos(rx) * size.y),
			pos)


## A bone can opt out of its parent's rotation or scale, and several do: the
## basic zombie's head sets both false, so it keeps its own size and angle
## however the body leans. Position always inherits - that is what a skeleton
## is for. Where both are inherited the parent's matrix is used directly,
## which keeps a parent's skew that decomposing would throw away.
static func inherit(parent: Transform2D, local: Transform2D,
		rot: bool, size: bool) -> Transform2D:
	var origin := parent * local.origin
	if rot and size:
		var full := parent * local
		full.origin = origin
		return full
	var carrier := Transform2D(parent.get_rotation() if rot else 0.0, Vector2.ZERO)
	if size:
		carrier = carrier.scaled(parent.get_scale())
	var out := carrier * local
	out.origin = origin
	return out


## Composes every bone at one moment. `offsets` is the animation's
## contribution per bone index, empty for the setup pose.
func world_at(offsets: Dictionary) -> Array[Transform2D]:
	var out: Array[Transform2D] = []
	out.resize(bones.size())
	for i in bones.size():
		var bone: Dictionary = bones[i]
		var local := matrix_of(bone["raw"], offsets.get(i, {}))
		var parent: int = bone["parent"]
		out[i] = inherit(out[parent], local, bone["inherit_rotation"],
				bone["inherit_scale"]) if parent >= 0 else local
	return out


## The transform each slot's sprite needs, given composed bones.
func slot_transforms(world: Array[Transform2D]) -> Array[Transform2D]:
	var out: Array[Transform2D] = []
	for slot in slots:
		var bone: int = slot["bone"]
		var base: Transform2D = world[bone] if bone >= 0 else Transform2D.IDENTITY
		out.append(base * (slot["xform"] as Transform2D))
	return out


# --- baking to Godot animations -----------------------------------------

## Properties Godot needs to reproduce a Transform2D exactly.
const TRACKS := ["position", "rotation", "scale", "skew"]


## Bakes every animation into Godot `Animation` resources.
##
## Sampling at the source frame rate rather than copying keyframes is what
## lets the easing go: a frame's cubic bezier is already in the sampled
## values, so Godot's linear interpolation between samples reproduces it.
## Keys that repeat are dropped, and a slot nothing moves gets no track at
## all, which is most of them in any one animation.
func bake_animations() -> AnimationLibrary:
	var library := AnimationLibrary.new()
	for entry in (_armature.get("animation", []) as Array):
		if not (entry is Dictionary and entry.has("name")):
			continue
		var animation := _bake_one(entry)
		if animation != null:
			library.add_animation(StringName(entry["name"]), animation)
	return library


func _bake_one(source: Dictionary) -> Animation:
	var frames := int(source.get("duration", 0))
	if frames <= 0:
		return null
	var timelines := _read_timelines(source)
	if timelines.is_empty():
		return null

	# Only slots whose bone chain is actually driven need tracks.
	var moving := _moving_slots(timelines)
	if moving.is_empty():
		return null

	var animation := Animation.new()
	animation.length = float(frames) / frame_rate
	animation.step = 1.0 / frame_rate

	var sampled: Array = []
	for frame in range(frames + 1):
		var time := float(frame) / frame_rate
		var offsets := {}
		for index in timelines:
			offsets[index] = _offset_at(timelines[index], time)
		sampled.append(slot_transforms(world_at(offsets)))

	for slot_index in moving:
		var name: StringName = slots[slot_index]["name"]
		for property in TRACKS:
			var values: Array = []
			for frame in sampled:
				values.append(_component(frame[slot_index], property))
			_add_track(animation, "%s:%s" % [name, property], values)
	_add_events(animation, source)
	return animation


## A rig says when it does the thing: the peashooter's Shoot animation carries
## a "Shoot" event fifteen frames in, which is when the pea actually leaves
## its mouth. Baking those as method tracks lets Godot fire them, so the game
## spawns the pea on the frame the art throws it rather than on the frame the
## animation started.
func _add_events(animation: Animation, source: Dictionary) -> void:
	var at := 0.0
	for frame in (source.get("frame", []) as Array):
		if not (frame is Dictionary):
			at += 0.0
			continue
		for event in (frame.get("events", []) as Array):
			if not (event is Dictionary and event.has("name")):
				continue
			var track := animation.add_track(Animation.TYPE_METHOD)
			animation.track_set_path(track, NodePath("."))
			animation.track_insert_key(track, at / frame_rate, {
				"method": &"_fire_event",
				"args": [StringName(event["name"])],
			})
		at += float(frame.get("duration", 0))


## Writes one property's samples as a track, keeping only the keys that
## matter: a value that differs from its neighbour on either side. A held
## value keeps the key before it changes, so a hold stays a hold.
##
## A track whose value never changes still gets its single key. Dropping it
## entirely leaves the sprite at its REST transform, which is not the same
## thing - and the difference shows up as parts flickering as one animation
## blends into another, each snapping back to rest for the blend.
func _add_track(animation: Animation, path: String, values: Array) -> void:
	var constant := true
	for i in range(1, values.size()):
		if not _same(values[i], values[0]):
			constant = false
			break
	var track := animation.add_track(Animation.TYPE_VALUE)
	if constant:
		animation.track_set_path(track, NodePath(path))
		animation.track_set_interpolation_type(track, Animation.INTERPOLATION_LINEAR)
		animation.track_insert_key(track, 0.0, values[0])
		return
	animation.track_set_path(track, NodePath(path))
	# Rotation wraps at +-PI, and a mirrored part sits right on that seam;
	# plain linear interpolation would spin it the long way round.
	animation.track_set_interpolation_type(track,
			Animation.INTERPOLATION_LINEAR_ANGLE if path.ends_with(":rotation")
			else Animation.INTERPOLATION_LINEAR)
	for i in values.size():
		var keep := i == 0 or i == values.size() - 1
		if not keep:
			keep = not _same(values[i], values[i - 1]) \
					or not _same(values[i], values[i + 1])
		if keep:
			animation.track_insert_key(track, float(i) / frame_rate, values[i])


func _same(a: Variant, b: Variant) -> bool:
	if a is Vector2:
		return (a as Vector2).is_equal_approx(b)
	return is_equal_approx(float(a), float(b))


func _component(xform: Transform2D, property: String) -> Variant:
	match property:
		"position": return xform.origin
		"rotation": return xform.get_rotation()
		"scale": return xform.get_scale()
		"skew": return xform.get_skew()
	return 0.0


## Slots whose bone, or any bone above it, is driven by this animation.
func _moving_slots(timelines: Dictionary) -> Array:
	var driven := {}
	for index in timelines:
		var at: int = index
		while at >= 0:
			driven[at] = true
			at = bones[at]["parent"]
	# A driven bone moves everything under it, so walk down as well as up.
	var changed := true
	while changed:
		changed = false
		for i in bones.size():
			var parent: int = bones[i]["parent"]
			if parent >= 0 and driven.has(parent) and not driven.has(i):
				driven[i] = true
				changed = true
	var out: Array = []
	for i in slots.size():
		if driven.has(int(slots[i]["bone"])):
			out.append(i)
	return out


func _read_timelines(source: Dictionary) -> Dictionary:
	var out := {}
	for entry in (source.get("bone", []) as Array):
		if not (entry is Dictionary):
			continue
		var index := int(bone_index.get(StringName(entry.get("name", "")), -1))
		if index < 0:
			continue
		out[index] = {
			"translate": _timeline(entry.get("translateFrame", []), "x", "y", 0.0),
			# The rotation key is `rotate`, not `angle`.
			"rotate": _timeline(entry.get("rotateFrame", []), "rotate", "", 0.0),
			"scale": _timeline(entry.get("scaleFrame", []), "x", "y", 1.0),
		}
	return out


func _offset_at(timeline: Dictionary, time: float) -> Dictionary:
	return {
		"pos": _sample(timeline["translate"], time, Vector2.ZERO),
		"rot": _sample(timeline["rotate"], time, Vector2.ZERO).x,
		"scale": _sample(timeline["scale"], time, Vector2.ONE),
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
		# How this frame eases into the next: a curve is a cubic bezier's two
		# control points, `tweenEasing` 0 is linear and other values ease.
		# Neither means the frame holds, which is deliberate in DragonBones
		# and mostly appears on terminal frames where nothing follows.
		var curve: Variant = frame.get("curve")
		out.append({
			"time": at / frame_rate,
			"a": float(frame.get(key_a, fallback)),
			"b": float(frame.get(key_b, fallback)) if key_b != "" else 0.0,
			"curve": curve if curve is Array and (curve as Array).size() == 4 else null,
			"tween": float(frame["tweenEasing"]) if frame.has("tweenEasing") else NAN,
		})
		at += float(frame.get("duration", 0))
	return out


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
			t = _ease(a, t)
			return Vector2(lerpf(float(a["a"]), float(b["a"]), t),
					lerpf(float(a["b"]), float(b["b"]), t))
	var last: Dictionary = track[track.size() - 1]
	return Vector2(float(last["a"]), float(last["b"]))


func _ease(frame: Dictionary, progress: float) -> float:
	var curve: Variant = frame.get("curve")
	if curve != null:
		return _bezier(curve as Array, progress)
	var tween: float = frame.get("tween", NAN)
	if is_nan(tween):
		return 0.0      # no tween: hold this frame's value
	if is_zero_approx(tween):
		return progress
	var eased := progress
	if tween < 0.0:
		eased = progress * progress
	elif tween <= 1.0:
		eased = 1.0 - (1.0 - progress) * (1.0 - progress)
	else:
		eased = 0.5 * (1.0 - cos(progress * PI))
	return (eased - progress) * absf(tween) + progress


## Cubic bezier from (0,0) to (1,1). Solved for t by bisection: a handful of
## steps is exact enough for animation and has no trouble near flat tangents.
func _bezier(points: Array, x: float) -> float:
	var x1 := float(points[0])
	var y1 := float(points[1])
	var x2 := float(points[2])
	var y2 := float(points[3])
	var low := 0.0
	var high := 1.0
	var t := x
	for _i in 10:
		t = (low + high) * 0.5
		var u := 1.0 - t
		var at := 3.0 * u * u * t * x1 + 3.0 * u * t * t * x2 + t * t * t
		if at < x:
			low = t
		else:
			high = t
	var u2 := 1.0 - t
	return 3.0 * u2 * u2 * t * y1 + 3.0 * u2 * t * t * y2 + t * t * t
