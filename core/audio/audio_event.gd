class_name AudioEvent
extends Resource
## One named sound in the catalog.
##
## The same event carries an address for each backend, so the game refers to
## `&"plant.place"` and never to a bank path or a file path.

@export var id: StringName = &""
## FMOD Studio event path, e.g. "event:/Plants/Place".
@export var fmod_path: String = ""
## Godot fallback streams, used while FMOD is not installed. One is played
## as is; several are picked from at random, the way FMOD's multi instrument
## picks a variation. Usually filled from the pack's generated
## `audio/streams.json` rather than written by hand.
@export var streams: PackedStringArray = []
## Whether the Godot fallback loops this event. FMOD ignores it: there, the
## event's own loop region decides.
@export var loop: bool = false
## Whether this cue is exclusive: starting it stops whatever was playing in
## the same slot, which is what separates a stage loop from a sound effect.
## It says nothing about how loud anything is - routing and level belong to
## the mixer in FMOD Studio, where buses and VCAs already do that job better
## than a flag here could.
@export var is_music: bool = false
@export_range(0.0, 2.0) var volume: float = 1.0
## A bus to address by name, ONLY for a game that has to reach one directly -
## a settings slider, say. Left empty, routing is whatever Studio says, which
## is the right default: the mixer is where that decision belongs.
@export var bus: StringName = &""

var source_mod: StringName = &"base"


static func from_dict(d: Dictionary) -> AudioEvent:
	var e := AudioEvent.new()
	e.id = StringName(d.get("id", &""))
	e.fmod_path = String(d.get("fmod", ""))
	var stream = d.get("stream", [])
	e.streams = PackedStringArray([stream] if stream is String else stream)
	e.loop = bool(d.get("loop", false))
	e.is_music = bool(d.get("music", false))
	e.volume = float(d.get("volume", 1.0))
	e.bus = StringName(d.get("bus", &""))
	return e


func _to_string() -> String:
	return "AudioEvent(%s -> %s)" % [id, fmod_path if fmod_path else ", ".join(streams)]
