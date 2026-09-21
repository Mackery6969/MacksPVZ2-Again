class_name ObjectDef
extends EntityDef
## A non-grave board object: slider and trap tiles, liquids, mold, and the
## zombie-side potions PVZGE misfiles as plants.
##
## Objects occupy a cell and change what can happen there. They are not
## generally destroyable and never belong in a seed bank, which is why keeping
## potions out of the plant pool matters for level generation.

enum Category { TILE, LIQUID, POTION, OTHER }

@export var category: Category = Category.TILE
@export var toughness: float = 0.0
## Seconds before a spent trap tile rearms.
@export var recover_delay: float = 0.0


static func category_from_string(text: String) -> Category:
	match text.to_lower():
		"tile": return Category.TILE
		"liquid": return Category.LIQUID
		"potion": return Category.POTION
	return Category.OTHER


func stat(name: StringName, fallback: Variant = 0.0) -> Variant:
	match name:
		&"toughness": return toughness
		&"recover_delay": return recover_delay
	return custom_stats.get(name, fallback)


func set_stat(name: StringName, value: Variant) -> bool:
	match name:
		&"toughness": toughness = float(value)
		&"recover_delay": recover_delay = float(value)
		_: return false
	return true


func stat_names() -> Array[StringName]:
	return [&"toughness", &"recover_delay"]


func _copy_stats_to(target: EntityDef) -> void:
	if target is ObjectDef:
		target.toughness = toughness
		target.recover_delay = recover_delay
		target.category = category
