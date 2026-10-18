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

@export_group("Terrain")
## Nothing can be planted here at all - Sky's open air, a crater.
@export var blocks_planting: bool = false
## A plant must carry this tag to go here. Big Wave Beach water wants an
## aquatic plant; Sky's gaps want something that can sit on air. One rule
## covers both, which is why they share this field rather than each getting
## their own special case.
@export var requires_tag: StringName = &""
## Planting this object (or plant) in a cell satisfies that cell's
## `requires_tag`, the way a lily pad makes water plantable.
@export var provides_tag: StringName = &""


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
		&"blocks_planting": return blocks_planting
	return custom_stats.get(name, fallback)


func set_stat(name: StringName, value: Variant) -> bool:
	match name:
		&"toughness": toughness = float(value)
		&"recover_delay": recover_delay = float(value)
		&"blocks_planting": blocks_planting = bool(value)
		&"requires_tag": requires_tag = StringName(value)
		&"provides_tag": provides_tag = StringName(value)
		_: return false
	return true


func stat_names() -> Array[StringName]:
	return [&"toughness", &"recover_delay"]


func _copy_stats_to(target: EntityDef) -> void:
	if target is ObjectDef:
		target.toughness = toughness
		target.recover_delay = recover_delay
		target.category = category
		target.blocks_planting = blocks_planting
		target.requires_tag = requires_tag
		target.provides_tag = provides_tag
