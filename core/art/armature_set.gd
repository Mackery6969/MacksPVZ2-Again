class_name ArmatureSet
extends RefCounted
## One DragonBones export: its skeleton, its atlas and the texture they share.
##
## Loaded once and shared by every entity using it. Fifty basic zombies are
## fifty nodes over ONE of these - one parsed skeleton, one texture, and one
## AtlasTexture per region - so adding zombies costs nodes, not memory.

var id: StringName = &""
var texture: Texture2D = null
var frame_rate: float = 30.0

## armature name -> ArmatureBaker, and its baked AnimationLibrary. Both are
## built on first use and shared by every entity using that rig.
var _rigs: Dictionary = {}
var _libraries: Dictionary = {}

## region name -> AtlasTexture, built once and handed out by reference.
var _regions: Dictionary = {}
## region name -> the untrimmed-frame offset the display transform expects.
var _offsets: Dictionary = {}
## armature name -> its parsed definition.
var _armatures: Dictionary = {}


func armature_names() -> Array:
	var names := _armatures.keys()
	names.sort()
	return names


func has_armature(name: StringName) -> bool:
	return _armatures.has(name)


func armature(name: StringName) -> Dictionary:
	return _armatures.get(name, {})


## The rig's own bounding box, which every export states. Fitting art to a
## lawn cell from this beats hand-tuned offsets: the origin sits at the feet
## and the art is rarely centred on it, so the numbers differ per rig.
func bounds(name: StringName) -> Rect2:
	var box: Dictionary = armature(name).get("aabb", {})
	if box.is_empty():
		return Rect2()
	return Rect2(float(box.get("x", 0.0)), float(box.get("y", 0.0)),
			float(box.get("width", 0.0)), float(box.get("height", 0.0)))


## The resolved rig: bones, slots and the rules for composing them.
func rig(name: StringName) -> ArmatureBaker:
	if not _rigs.has(name):
		_rigs[name] = ArmatureBaker.new(self, name) if has_armature(name) else null
	return _rigs[name]


## This rig's animations as Godot resources, baked once and shared.
func animations(name: StringName) -> AnimationLibrary:
	if not _libraries.has(name):
		var built := rig(name)
		_libraries[name] = built.bake_animations() if built != null \
				else AnimationLibrary.new()
	return _libraries[name]


func region(name: StringName) -> AtlasTexture:
	return _regions.get(name)


## Where a region's art sits inside its untrimmed frame. DragonBones places a
## display by the centre of the ORIGINAL frame, and the packer trims the
## transparent edges away, so without this every trimmed part drifts.
func region_offset(name: StringName) -> Vector2:
	return _offsets.get(name, Vector2.ZERO)


## Builds a set from an extracted `art/<bundle>/` directory.
## Returns null when anything is missing, so a caller falls back to
## placeholder art rather than half-drawing.
static func load_from(dir_path: String, texture_path: String) -> ArmatureSet:
	var skeleton := _read_json(dir_path.path_join("skeleton.json"))
	var atlas := _read_json(dir_path.path_join("atlas.json"))
	if skeleton.is_empty() or atlas.is_empty():
		return null
	var image := ResourceLoader.load(texture_path, "Texture2D") as Texture2D
	if image == null:
		return null

	var built := ArmatureSet.new()
	built.id = StringName(dir_path.get_file())
	built.texture = image
	built.frame_rate = float(skeleton.get("frameRate", 30.0))

	for entry in (atlas.get("SubTexture", []) as Array):
		var name := StringName(entry.get("name", ""))
		if name == &"":
			continue
		var at := AtlasTexture.new()
		at.atlas = image
		var w := float(entry.get("width", 0))
		var h := float(entry.get("height", 0))
		at.region = Rect2(float(entry.get("x", 0)), float(entry.get("y", 0)), w, h)
		built._regions[name] = at
		# frameX/frameY are where the trimmed art sits in the original frame,
		# measured from its top-left; the display is centred on that frame.
		var fw := float(entry.get("frameWidth", w))
		var fh := float(entry.get("frameHeight", h))
		var fx := float(entry.get("frameX", 0))
		var fy := float(entry.get("frameY", 0))
		# The trimmed art starts (-fx, -fy) into the frame, so its centre sits
		# this far from the frame's centre, which is what the display is
		# positioned by.
		built._offsets[name] = Vector2(-fx + (w - fw) * 0.5, -fy + (h - fh) * 0.5)

	for entry in (skeleton.get("armature", []) as Array):
		if entry is Dictionary and entry.has("name"):
			built._armatures[StringName(entry["name"])] = entry
	return built


static func _read_json(path: String) -> Dictionary:
	if not FileAccess.file_exists(path):
		return {}
	var text := FileAccess.get_file_as_string(path)
	var parsed: Variant = JSON.parse_string(text)
	return parsed if parsed is Dictionary else {}
