class_name AudioCatalog
extends RefCounted
## The set of known audio events, loaded from data and layered by mods.
##
## Events live in `audio/events.json` beside a pack's other content, so a mod
## adds or replaces sounds the same way it adds a zombie. A pack's
## `audio/streams.json`, generated from its Studio project, gives those events
## their clips for the Godot fallback.

var events: Dictionary = {}     ## StringName -> AudioEvent
var errors: Array[String] = []


func load_from(sources: Array) -> void:
	events.clear()
	errors.clear()
	for source in sources:
		var mod := StringName(source.get("id", &"base"))
		var root := String(source["root"])
		_load_file(root.path_join("audio/events.json"), mod)
		_load_streams(root.path_join("audio/streams.json"), mod)


func _load_file(path: String, mod: StringName) -> void:
	var parsed := _read_json(path)
	for entry in (parsed.get("events", []) as Array):
		if not (entry is Dictionary) or entry.get("id") == null:
			continue
		var event := AudioEvent.from_dict(entry)
		event.source_mod = mod
		events[event.id] = event


## Fills in fallback streams for this pack's own events. Only its own: a pack
## that replaces a base event has replaced its sound too, so the base clip must
## not leak back in under it. A stream written in events.json wins.
func _load_streams(path: String, mod: StringName) -> void:
	var parsed := _read_json(path)
	var table: Dictionary = parsed.get("streams", {})
	for id in table:
		var event: AudioEvent = events.get(StringName(id))
		var entry = table[id]
		if event == null or event.source_mod != mod or not event.streams.is_empty() \
				or not (entry is Dictionary):
			continue
		event.streams = PackedStringArray(entry.get("streams", []))
		event.loop = event.loop or bool(entry.get("loop", false))


func _read_json(path: String) -> Dictionary:
	if not FileAccess.file_exists(path):
		return {}
	var f := FileAccess.open(path, FileAccess.READ)
	var parsed = JSON.parse_string(f.get_as_text())
	f.close()
	if not (parsed is Dictionary):
		errors.append("%s: not a JSON object" % path)
		return {}
	return parsed


func get_event(id: StringName) -> AudioEvent:
	return events.get(id)


func has_event(id: StringName) -> bool:
	return events.has(id)


func size() -> int:
	return events.size()
