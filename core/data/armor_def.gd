class_name ArmorDef
extends EntityDef
## An armor piece's typed stats.

@export var toughness: float = 370.0
@export var bowling_level: int = 0
@export var is_metal: bool = false
@export var is_ice: bool = false


func stat(name: StringName, fallback: Variant = 0.0) -> Variant:
	match name:
		&"toughness": return toughness
		&"bowling_level": return bowling_level
		&"is_metal": return is_metal
		&"is_ice": return is_ice
	return custom_stats.get(name, fallback)


func set_stat(name: StringName, value: Variant) -> bool:
	match name:
		&"toughness": toughness = float(value)
		&"bowling_level": bowling_level = int(value)
		&"is_metal": is_metal = bool(value)
		&"is_ice": is_ice = bool(value)
		_: return false
	return true


func stat_names() -> Array[StringName]:
	return [&"toughness", &"bowling_level", &"is_metal", &"is_ice"]


func _copy_stats_to(target: EntityDef) -> void:
	if target is ArmorDef:
		target.toughness = toughness
		target.bowling_level = bowling_level
		target.is_metal = is_metal
		target.is_ice = is_ice
