extends Node
## Maps component type names to their implementing scripts.
##
## This is the seam that makes behaviour moddable. Core registers the built-in
## types at startup; a mod can then register a script under a NEW name to add a
## behaviour, or under an EXISTING name to replace one outright - which is how
## a mod completely changes what a plant does without touching core code.
##
## Registered as an autoload singleton named `Components`.

signal type_registered(type: StringName, source_mod: StringName)
signal type_overridden(type: StringName, old_mod: StringName, new_mod: StringName)

const BUILTIN_DIR := "res://core/components/builtin"

var _scripts: Dictionary = {}   ## StringName -> GDScript
var _owners: Dictionary = {}    ## StringName -> StringName (mod that supplied it)


func _ready() -> void:
	load_builtins()


func load_builtins() -> void:
	var dir := DirAccess.open(BUILTIN_DIR)
	if dir == null:
		push_warning("ComponentRegistry: no builtin dir at %s" % BUILTIN_DIR)
		return
	dir.list_dir_begin()
	var fname := dir.get_next()
	while fname != "":
		if not dir.current_is_dir() and fname.ends_with(".gd"):
			var script: GDScript = load(BUILTIN_DIR.path_join(fname))
			if script != null:
				# File name is the type name: shooter.gd -> &"shooter".
				register(StringName(fname.get_basename()), script, &"base")
		fname = dir.get_next()
	dir.list_dir_end()


## Register `script` as the implementation of `type`. Registering an existing
## type replaces it, which is the supported way for a mod to override
## behaviour; the override is announced so it shows up in load logs.
func register(type: StringName, script: GDScript, source_mod: StringName = &"base") -> void:
	if script == null:
		push_error("ComponentRegistry: null script for type '%s'" % type)
		return
	if _scripts.has(type):
		var old_mod: StringName = _owners.get(type, &"base")
		if old_mod != source_mod:
			type_overridden.emit(type, old_mod, source_mod)
			print("[mod] '%s' overrides component '%s' (was from '%s')"
					% [source_mod, type, old_mod])
	else:
		type_registered.emit(type, source_mod)
	_scripts[type] = script
	_owners[type] = source_mod


## Instantiate the component a ComponentSpec describes.
## Returns null for unknown types so a bad mod degrades instead of crashing.
func create(spec: ComponentSpec, host: Node) -> EntityComponent:
	if spec == null:
		return null
	if not _scripts.has(spec.type):
		push_warning("ComponentRegistry: unknown component type '%s' on %s"
				% [spec.type, host.name if host else "<none>"])
		return null
	var comp: EntityComponent = _scripts[spec.type].new()
	comp.name = String(spec.type)
	comp.host = host
	comp.config = spec.config
	return comp


func has_type(type: StringName) -> bool:
	return _scripts.has(type)


func owner_of(type: StringName) -> StringName:
	return _owners.get(type, &"")


func types() -> Array:
	var out := _scripts.keys()
	out.sort()
	return out


func summary() -> String:
	var by_mod := {}
	for t in _owners:
		by_mod[_owners[t]] = by_mod.get(_owners[t], 0) + 1
	return "components: %d types %s" % [_scripts.size(), str(by_mod)]
