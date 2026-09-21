class_name ZombieDef
extends EntityDef
## A zombie's typed stats, editable in the inspector or authored as JSON.

@export_group("Stats")
@export var toughness: float = 100.0
## Lanes crossed per second.
@export var speed: float = 0.5
@export var eat_dps: float = 100.0
@export var wave_cost: int = 100
@export var weight: int = 0
## Cost to place this zombie from a seed packet. Only used by level types
## where the player plays the zombie side, such as I-Zombie.
@export var sun_cost: int = 0

@export_group("Classification")
## PopCap's ZombieSort: Normal, Gargantuar, Zomboss, ...
@export var sort: StringName = &"Normal"


func stat(name: StringName, fallback: Variant = 0.0) -> Variant:
	match name:
		&"toughness": return toughness
		&"speed": return speed
		&"eat_dps": return eat_dps
		&"wave_cost": return wave_cost
		&"weight": return weight
		&"sun_cost": return sun_cost
	return custom_stats.get(name, fallback)


func set_stat(name: StringName, value: Variant) -> bool:
	match name:
		&"toughness": toughness = float(value)
		&"speed": speed = float(value)
		&"eat_dps": eat_dps = float(value)
		&"wave_cost": wave_cost = int(value)
		&"weight": weight = int(value)
		&"sun_cost": sun_cost = int(value)
		_: return false
	return true


func stat_names() -> Array[StringName]:
	return [&"toughness", &"speed", &"eat_dps", &"wave_cost", &"weight",
			&"sun_cost"]


func _copy_stats_to(target: EntityDef) -> void:
	if target is ZombieDef:
		target.toughness = toughness
		target.speed = speed
		target.eat_dps = eat_dps
		target.wave_cost = wave_cost
		target.weight = weight
		target.sun_cost = sun_cost
		target.sort = sort
