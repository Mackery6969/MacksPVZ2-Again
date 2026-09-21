class_name GraveDef
extends EntityDef
## A gravestone: a board object plants can destroy, which may fire grid-item
## events such as summoning zombies on a timer.
##
## Kept distinct from ObjectDef because graves are targetable and destroyable,
## while tiles and potions are not.

@export_group("Stats")
@export var toughness: float = 500.0
@export var plantfood_count: int = 0

@export_group("Interactions")
## Flying graves sit above the lawn and ignore ground effects.
@export var flying: bool = false
## Whether Grave Buster can be planted on it.
@export var gravebuster_plantable: bool = true
@export var hot_potato_meltable: bool = false


func stat(name: StringName, fallback: Variant = 0.0) -> Variant:
	match name:
		&"toughness": return toughness
		&"plantfood_count": return plantfood_count
		&"flying": return flying
		&"gravebuster_plantable": return gravebuster_plantable
		&"hot_potato_meltable": return hot_potato_meltable
	return custom_stats.get(name, fallback)


func set_stat(name: StringName, value: Variant) -> bool:
	match name:
		&"toughness": toughness = float(value)
		&"plantfood_count": plantfood_count = int(value)
		&"flying": flying = bool(value)
		&"gravebuster_plantable": gravebuster_plantable = bool(value)
		&"hot_potato_meltable": hot_potato_meltable = bool(value)
		_: return false
	return true


func stat_names() -> Array[StringName]:
	return [&"toughness", &"plantfood_count", &"flying",
			&"gravebuster_plantable", &"hot_potato_meltable"]


func _copy_stats_to(target: EntityDef) -> void:
	if target is GraveDef:
		target.toughness = toughness
		target.plantfood_count = plantfood_count
		target.flying = flying
		target.gravebuster_plantable = gravebuster_plantable
		target.hot_potato_meltable = hot_potato_meltable
