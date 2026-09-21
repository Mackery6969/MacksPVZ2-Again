class_name AudioEvent
extends Resource
## One named sound in the catalog.
##
## The same event carries an address for each backend, so the game refers to
## `&"plant.place"` and never to a bank path or a file path.

@export var id: StringName = &""
## FMOD Studio event path, e.g. "event:/Plants/Place".
@export var fmod_path: String = ""
## Godot fallback stream, used while FMOD is not installed.
@export var stream_path: String = ""
@export var is_music: bool = false
@export_range(0.0, 2.0) var volume: float = 1.0
## Mix bus this belongs to, for backends that route.
@export var bus: StringName = &"sfx"

var source_mod: StringName = &"base"


static func from_dict(d: Dictionary) -> AudioEvent:
	var e := AudioEvent.new()
	e.id = StringName(d.get("id", &""))
	e.fmod_path = String(d.get("fmod", ""))
	e.stream_path = String(d.get("stream", ""))
	e.is_music = bool(d.get("music", false))
	e.volume = float(d.get("volume", 1.0))
	e.bus = StringName(d.get("bus", &"music" if e.is_music else &"sfx"))
	return e


func _to_string() -> String:
	return "AudioEvent(%s -> %s)" % [id, fmod_path if fmod_path else stream_path]
