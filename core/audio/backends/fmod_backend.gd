extends AudioBackend
## Routes events to FMOD Studio.
##
## Inactive until an FMOD integration is installed - `is_available()` looks for
## the singleton the GDExtension registers, so this file can sit in the project
## harmlessly until then. Banks are loaded from `res://audio/banks/`.
##
## Written against utopia-rise's fmod-gdextension, whose `FmodServer` is the
## API used here: `play_one_shot`, `create_event_instance`, `get_bus`,
## `update`. Install notes live in docs/AUDIO.md. In short: FMOD Studio and
## FMOD Engine must be the SAME version (2.03.x), and the integration is a
## GDExtension, so no recompiling Godot.

const SINGLETON := "FmodServer"
const BANK_DIR := "res://audio/banks"
## The plugin's own autoload, which pumps `FmodServer.update()` every frame.
const MANAGER := ^"/root/FmodManager"
## FMOD_STUDIO_LOAD_BANK_NORMAL.
const LOAD_BANK_NORMAL := 0
## FMOD_STUDIO_STOP_ALLOWFADEOUT, so music ends on its own fade rather than a cut.
const STOP_ALLOW_FADEOUT := 0

var _server: Object = null
var _banks: Array = []
## The playing music instance, held so it can be stopped and steered. A
## one-shot cannot be: FMOD releases it the moment it starts.
var _music: Object = null
var _music_event: StringName = &""
## Parameters the game has set, so a music cue started later picks them up.
var _parameters: Dictionary = {}
var _pump: Node = null


func backend_name() -> String:
	return "fmod"


func is_available() -> bool:
	return _find_server() != null


func _find_server() -> Object:
	if Engine.has_singleton(SINGLETON):
		return Engine.get_singleton(SINGLETON)
	return null


func setup(_catalog: AudioCatalog) -> void:
	attach(_find_server())


## Starts driving `server`. Split from `setup` so tests can hand in a
## stand-in for FmodServer.
func attach(server: Object) -> void:
	_server = server
	if _server == null:
		return
	_load_banks()
	_ensure_pump()


## Loads every bank in the bank directory, strings banks first. FMOD needs
## the master bank and its strings bank before any event path resolves.
func _load_banks() -> void:
	var dir := DirAccess.open(BANK_DIR)
	if dir == null:
		push_warning("FMOD: no bank directory at %s" % BANK_DIR)
		return
	var names := Array(dir.get_files()).filter(func(f): return f.ends_with(".bank"))
	names.sort_custom(func(a, b): return a.ends_with(".strings.bank") and not b.ends_with(".strings.bank"))
	if names.is_empty():
		push_warning("FMOD: no banks in %s - build them from the Music project" % BANK_DIR)
	for fname in names:
		var bank = _server.load_bank(BANK_DIR.path_join(fname), LOAD_BANK_NORMAL)
		if bank != null:
			_banks.append(bank)


## FMOD only advances when `update()` is called. The plugin's autoload does
## that when the plugin is enabled; when it is not, this does, so a project
## with the extension but not the editor plugin still makes sound.
func _ensure_pump() -> void:
	var tree := Engine.get_main_loop() as SceneTree
	if tree == null or tree.root.has_node(MANAGER) or not _server.has_method("update"):
		return
	_pump = FmodPump.new()
	_pump.server = _server
	tree.root.add_child.call_deferred(_pump)


func can_play(event: AudioEvent) -> bool:
	return _server != null and event.fmod_path != ""


## Position is not used: the lawn is one screen with no listener to place,
## and a 2D panner keyed on board pixels would only pull sounds off-centre.
func play(event: AudioEvent, _position: Variant = null) -> void:
	if not can_play(event):
		return
	_server.play_one_shot(event.fmod_path)


func play_music(event: AudioEvent) -> void:
	if not can_play(event):
		return
	# The same cue again keeps playing, so its phase is not thrown away.
	if _music_event == event.id and _music != null and _music.is_valid():
		return
	stop_music()
	var instance = _server.create_event_instance(event.fmod_path)
	if instance == null or not instance.is_valid():
		push_warning("FMOD: no event %s - is it in a built bank?" % event.fmod_path)
		return
	for name in _parameters:
		instance.set_parameter_by_name(String(name), _parameters[name])
	instance.start()
	_music = instance
	_music_event = event.id


func stop_music() -> void:
	if _music != null and _music.is_valid():
		_music.stop(STOP_ALLOW_FADEOUT)
		_music.release()
	_music = null
	_music_event = &""


## Sets `name` everywhere it could live: as a global parameter, and on the
## playing music event, where a preset parameter such as `state` is local.
## FMOD ignores a name an event does not have, so setting both is harmless.
func set_parameter(name: StringName, value: float) -> void:
	_parameters[name] = value
	if _server == null:
		return
	_server.set_global_parameter_by_name(String(name), value)
	if _music != null and _music.is_valid():
		_music.set_parameter_by_name(String(name), value)


func set_bus_volume(bus: StringName, linear: float) -> void:
	if _server == null:
		return
	var path := String(bus) if String(bus).begins_with("bus:/") else "bus:/%s" % bus
	if not _server.check_bus_path(path):
		return
	var handle = _server.get_bus(path)
	if handle != null:
		handle.volume = linear


func shutdown() -> void:
	stop_music()
	if _pump != null:
		_pump.queue_free()
		_pump = null
	_banks.clear()
	_server = null


## Calls `update()` each frame for an FmodServer nobody else is pumping.
class FmodPump extends Node:
	var server: Object

	func _init() -> void:
		name = "FmodPump"
		process_mode = Node.PROCESS_MODE_ALWAYS

	func _process(_delta: float) -> void:
		if server != null:
			server.update()
