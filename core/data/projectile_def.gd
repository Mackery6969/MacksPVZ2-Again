class_name ProjectileDef
extends EntityDef
## A projectile's typed stats.

@export var damage: float = 20.0


func stat(name: StringName, fallback: Variant = 0.0) -> Variant:
	if name == &"damage":
		return damage
	return custom_stats.get(name, fallback)


func set_stat(name: StringName, value: Variant) -> bool:
	if name == &"damage":
		damage = float(value)
		return true
	return false


func stat_names() -> Array[StringName]:
	return [&"damage"]


func _copy_stats_to(target: EntityDef) -> void:
	if target is ProjectileDef:
		target.damage = damage
