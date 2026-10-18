class_name EntityDef
extends Resource
## A fully resolved entity definition: archetype chain flattened, tag deltas
## applied, components merged.
##
## Definitions can be authored two ways and both end up here:
##   - a `.tres` resource, edited in the Godot inspector
##   - a `.json` file, which suits text mods and the PVZGE importer
##
## Subclasses expose their real stats as exported properties so they are typed
## and inspector-editable; `stat()` gives generic code one way to read them.

@export var id: StringName = &""
@export var kind: StringName = &""           ## &"zombie", &"plant", ...
@export var extends_id: StringName = &""     ## archetype or parent entity
@export var tags: Array[StringName] = []
@export var components: Array[ComponentSpec] = []
## Stats with no typed property, including anything a mod invents.
@export var custom_stats: Dictionary = {}
## Source fields not yet modelled, kept verbatim so nothing is lost.
@export var extra: Dictionary = {}

var source_path: String = ""
var source_mod: StringName = &"base"

var _tag_set: Dictionary = {}
var _tag_set_built: bool = false


# --- tags ----------------------------------------------------------------

func has_tag(tag: StringName) -> bool:
	if not _tag_set_built:
		_rebuild_tag_set()
	return _tag_set.has(tag)


func add_tag(tag: StringName) -> void:
	if not tags.has(tag):
		tags.append(tag)
		_tag_set_built = false


func remove_tag(tag: StringName) -> void:
	tags.erase(tag)
	_tag_set_built = false


func set_tags(new_tags: Array) -> void:
	tags.clear()
	for t in new_tags:
		tags.append(StringName(t))
	_tag_set_built = false


func _rebuild_tag_set() -> void:
	_tag_set.clear()
	for t in tags:
		_tag_set[t] = true
	_tag_set_built = true


## True only if every required tag is present and no excluded tag is.
func matches(required: Array, excluded: Array = []) -> bool:
	for t in required:
		if not has_tag(StringName(t)):
			return false
	for t in excluded:
		if has_tag(StringName(t)):
			return false
	return true


func tag_list() -> Array[StringName]:
	var out := tags.duplicate()
	out.sort()
	return out


# --- stats ---------------------------------------------------------------

## Reads a stat by name. Subclasses override to expose their typed properties;
## anything they do not recognise falls through to `custom_stats`.
func stat(name: StringName, fallback: Variant = 0.0) -> Variant:
	return custom_stats.get(name, fallback)


## Writes a stat by name, used when building a definition from data.
## Returns false if the name is not a typed property, so the caller can store
## it in `custom_stats` instead.
func set_stat(_name: StringName, _value: Variant) -> bool:
	return false


func apply_stats(values: Dictionary) -> void:
	for key in values:
		var name := StringName(key)
		if not set_stat(name, values[key]):
			custom_stats[name] = values[key]


func stat_names() -> Array[StringName]:
	return []


# --- components ----------------------------------------------------------

## Components of one type, e.g. all &"armor" entries.
func components_of(type: StringName) -> Array[ComponentSpec]:
	var out: Array[ComponentSpec] = []
	for c in components:
		if c != null and c.type == type:
			out.append(c)
	return out


func component_spec(type: StringName) -> ComponentSpec:
	for c in components:
		if c != null and c.type == type:
			return c
	return null


## Adds a component, replacing any existing one of the same type - how a child
## definition overrides a behaviour it inherited.
func put_component(spec: ComponentSpec) -> void:
	for i in components.size():
		if components[i] != null and components[i].type == spec.type:
			components[i] = spec
			return
	components.append(spec)


## Drops every component of one type, which is how an entry opts out of
## something its archetype supplied.
func remove_components(type: StringName) -> void:
	var kept: Array[ComponentSpec] = []
	for c in components:
		if c != null and c.type != type:
			kept.append(c)
	components = kept


## Copies the inheritable parts of `parent` onto this definition.
func inherit_from(parent: EntityDef) -> void:
	set_tags(parent.tags)
	components.clear()
	for c in parent.components:
		components.append(c.duplicate_spec())
	custom_stats = parent.custom_stats.duplicate(true)
	parent._copy_stats_to(self)


## Fills gaps from `parent` without disturbing anything already authored here.
##
## `inherit_from` is for definitions built up from data, where the child's
## values are applied afterwards. A `.tres` is already complete when it loads,
## so its parent may only contribute what the resource left unset.
func merge_under(parent: EntityDef) -> void:
	for t in parent.tags:
		add_tag(t)
	for c in parent.components:
		if component_spec(c.type) == null:
			components.append(c.duplicate_spec())
	for key in parent.custom_stats:
		if not custom_stats.has(key):
			custom_stats[key] = parent.custom_stats[key]


## Hook for subclasses to carry their typed properties down the chain.
func _copy_stats_to(_target: EntityDef) -> void:
	pass


func _to_string() -> String:
	return "%s(%s tags=%d components=%d)" % [
			get_script().get_global_name(), id, tags.size(), components.size()]
