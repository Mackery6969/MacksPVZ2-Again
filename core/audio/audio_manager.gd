extends Node
## Raises named audio events, and owns which backend handles them.
##
## Game code calls `Audio.play(&"plant.place")` and never mentions FMOD, a bank
## path or a file. That indirection is the whole point: the backend can be
## silent today, Godot's own audio tomorrow, and FMOD once it is installed,
## without a single call site changing.
##
## Backends are tried in order of preference and the first available one wins,
## so installing the FMOD integration is enough to switch over.
##
## Registered as an autoload singleton named `Audio`, after `Mods`.

signal backend_changed(name: String)

const BACKEND_SCRIPTS := [
	"res://core/audio/backends/fmod_backend.gd",
	"res://core/audio/backends/godot_backend.gd",
	"res://core/audio/backends/null_backend.gd",
]

## Turns all audio off without changing backend, for tests and headless runs.
@export var muted: bool = false

var catalog := AudioCatalog.new()
var backend: AudioBackend = null

var _missing_reported: Dictionary = {}


func _ready() -> void:
	reload()


func reload() -> void:
	if backend != null:
		backend.shutdown()
	catalog.load_from(_sources())
	backend = _pick_backend()
	backend.setup(catalog)
	for e in catalog.errors:
		push_warning("[audio] " + e)
	backend_changed.emit(backend.backend_name())


func _sources() -> Array:
	var mods := get_node_or_null(^"/root/Mods")
	if mods != null and mods.has_method("data_sources"):
		return mods.data_sources()
	return [{"id": &"base", "root": "res://data/native"}]


func _pick_backend() -> AudioBackend:
	for path in BACKEND_SCRIPTS:
		var script = load(path)
		if script == null:
			continue
		var candidate: AudioBackend = script.new()
		if candidate.is_available():
			return candidate
	return AudioBackend.new()


# --- events --------------------------------------------------------------

## Fires a one-shot event. Unknown ids are reported once and then ignored, so a
## missing sound never floods the log or stops the game.
func play(id: StringName, position: Variant = null) -> void:
	if muted:
		return
	var event := catalog.get_event(id)
	if event == null:
		_report_missing(id)
		return
	backend.play(event, position)


func play_music(id: StringName) -> void:
	if muted:
		return
	var event := catalog.get_event(id)
	if event == null:
		_report_missing(id)
		return
	backend.play_music(event)


func stop_music() -> void:
	backend.stop_music()


func set_parameter(name: StringName, value: float) -> void:
	backend.set_parameter(name, value)


func set_bus_volume(bus: StringName, linear: float) -> void:
	backend.set_bus_volume(bus, linear)


func has_event(id: StringName) -> bool:
	return catalog.has_event(id)


func _report_missing(id: StringName) -> void:
	if _missing_reported.has(id):
		return
	_missing_reported[id] = true
	push_warning("[audio] no event '%s' in the catalog" % id)


func summary() -> String:
	var playable := 0
	for id in catalog.events:
		var e: AudioEvent = catalog.events[id]
		var addr := e.fmod_path if backend.backend_name() == "fmod" else e.stream_path
		if addr != "":
			playable += 1
	return "audio: backend=%s events=%d playable=%d" % [
			backend.backend_name(), catalog.size(), playable]
