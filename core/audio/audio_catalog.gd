class_name AudioCatalog
extends RefCounted
## The set of known audio events, loaded from data and layered by mods.
##
## Events live in `audio/events.json` beside a pack's other content, so a mod
## adds or replaces sounds the same way it adds a zombie.

var events: Dictionary = {}     ## StringName -> AudioEvent
var errors: Array[String] = []


func load_from(sources: Array) -> void:
	events.clear()
	errors.clear()
	for source in sources:
		var mod := StringName(source.get("id", &"base"))
		_load_file(String(source["root"]).path_join("audio/events.json"), mod)


func _load_file(path: String, mod: StringName) -> void:
	if not FileAccess.file_exists(path):
		return
	var f := FileAccess.open(path, FileAccess.READ)
	var parsed = JSON.parse_string(f.get_as_text())
	f.close()
	if not (parsed is Dictionary):
		errors.append("%s: not a JSON object" % path)
		return

	for entry in (parsed.get("events", []) as Array):
		if not (entry is Dictionary) or entry.get("id") == null:
			continue
		var event := AudioEvent.from_dict(entry)
		event.source_mod = mod
		events[event.id] = event


func get_event(id: StringName) -> AudioEvent:
	return events.get(id)


func has_event(id: StringName) -> bool:
	return events.has(id)


func size() -> int:
	return events.size()
