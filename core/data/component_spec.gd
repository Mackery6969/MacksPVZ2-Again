class_name ComponentSpec
extends Resource
## One behaviour attached to an entity, as data.
##
## `type` names a script in the ComponentRegistry; `config` carries whatever
## that behaviour needs. Config stays a Dictionary on purpose - a mod can add a
## component type this project has never heard of, so its shape cannot be typed
## ahead of time. A mod that wants type safety can subclass this and export
## real fields.

@export var type: StringName = &""
@export var config: Dictionary = {}


static func from_dict(d: Dictionary) -> ComponentSpec:
	var spec := ComponentSpec.new()
	spec.type = StringName(d.get("type", &""))
	spec.config = d.duplicate(true)
	spec.config.erase("type")
	return spec


func cfg(key: StringName, fallback: Variant = null) -> Variant:
	return config.get(key, fallback)


func duplicate_spec() -> ComponentSpec:
	var copy := ComponentSpec.new()
	copy.type = type
	copy.config = config.duplicate(true)
	return copy


func _to_string() -> String:
	return "ComponentSpec(%s)" % type
