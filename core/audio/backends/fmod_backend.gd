extends AudioBackend
## Routes events to FMOD Studio.
##
## Inactive until an FMOD integration is installed - `is_available()` looks for
## the singleton the GDExtension registers, so this file can sit in the project
## harmlessly until then. Banks are loaded from `res://audio/banks/`.
##
## Install notes live in docs/AUDIO.md. In short: FMOD Studio and FMOD Engine
## must be the SAME version (2.03.x), and the integration is a GDExtension, so
## no recompiling Godot.

## Singleton names used by the known Godot integrations, newest first.
const SINGLETONS := ["FmodServer", "FmodManager", "Fmod"]
const BANK_DIR := "res://audio/banks"

var _server: Object = null


func backend_name() -> String:
	return "fmod"


func is_available() -> bool:
	return _find_server() != null


func _find_server() -> Object:
	for name in SINGLETONS:
		if Engine.has_singleton(name):
			return Engine.get_singleton(name)
	return null


func setup(_catalog: AudioCatalog) -> void:
	_server = _find_server()
	if _server == null:
		return
	_load_banks()


## Loads every bank in the bank directory. FMOD needs the master bank and its
## strings bank before any event can resolve.
func _load_banks() -> void:
	var dir := DirAccess.open(BANK_DIR)
	if dir == null:
		push_warning("FMOD: no bank directory at %s" % BANK_DIR)
		return
	dir.list_dir_begin()
	var fname := dir.get_next()
	while fname != "":
		if not dir.current_is_dir() and fname.ends_with(".bank"):
			_call_if_present("load_bank", [BANK_DIR.path_join(fname), 0])
		fname = dir.get_next()
	dir.list_dir_end()


func play(event: AudioEvent, position: Variant = null) -> void:
	if _server == null or event.fmod_path == "":
		return
	if position is Vector2 or position is Vector3:
		_call_if_present("play_one_shot_at_position", [event.fmod_path, position])
	else:
		_call_if_present("play_one_shot", [event.fmod_path])


func play_music(event: AudioEvent) -> void:
	if _server == null or event.fmod_path == "":
		return
	stop_music()
	_call_if_present("play_one_shot", [event.fmod_path])


func stop_music() -> void:
	_call_if_present("stop_all_events", [])


func set_parameter(name: StringName, value: float) -> void:
	_call_if_present("set_global_parameter_by_name", [String(name), value])


func set_bus_volume(bus: StringName, linear: float) -> void:
	_call_if_present("set_bus_volume", ["bus:/%s" % bus, linear])


func shutdown() -> void:
	_server = null


## Integrations differ slightly in method names, so every call is guarded
## rather than assumed. A missing method is a no-op, not a crash.
func _call_if_present(method: String, args: Array) -> void:
	if _server != null and _server.has_method(method):
		_server.callv(method, args)
