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
##
## Left at 0 it is derived from `wave_cost`, which is the only strength signal
## PopCap's data carries. Deriving it here as well as in the importer means a
## mod-authored zombie is priced without having to say so.
@export var sun_cost: int = 0

@export_group("Resistance")
## How long a stun lasts on this zombie, as a multiplier. 0 is immunity, which
## is what every zombie in PopCap's data that carries the field actually says;
## a fraction is available to mods that want partial resistance.
@export_range(0.0, 4.0, 0.05) var stun_scale: float = 1.0
## Speed multiplier while standing on water. Ducky-tube zombies swim faster
## than they walk, which is the whole point of them.
@export_range(0.0, 4.0, 0.05) var water_speed_scale: float = 1.0

@export_group("Classification")
## PopCap's ZombieSort: Normal, Gargantuar, Zomboss, ...
@export var sort: StringName = &"Normal"


## Snapped to 25s so the economy reads cleanly. Mirrors
## `derive_sun_cost` in tools/import_entities.py.
func placement_cost() -> int:
	if sun_cost > 0:
		return sun_cost
	return maxi(25, mini(int(round((50.0 + wave_cost * 0.12) / 25.0)) * 25, 500))


func stat(name: StringName, fallback: Variant = 0.0) -> Variant:
	match name:
		&"toughness": return toughness
		&"speed": return speed
		&"eat_dps": return eat_dps
		&"wave_cost": return wave_cost
		&"weight": return weight
		&"sun_cost": return placement_cost()
		&"stun_scale": return stun_scale
		&"water_speed_scale": return water_speed_scale
	return custom_stats.get(name, fallback)


func set_stat(name: StringName, value: Variant) -> bool:
	match name:
		&"toughness": toughness = float(value)
		&"speed": speed = float(value)
		&"eat_dps": eat_dps = float(value)
		&"wave_cost": wave_cost = int(value)
		&"weight": weight = int(value)
		&"sun_cost": sun_cost = int(value)
		&"stun_scale": stun_scale = float(value)
		&"water_speed_scale": water_speed_scale = float(value)
		_: return false
	return true


func stat_names() -> Array[StringName]:
	return [&"toughness", &"speed", &"eat_dps", &"wave_cost", &"weight",
			&"sun_cost", &"stun_scale", &"water_speed_scale"]


func _copy_stats_to(target: EntityDef) -> void:
	if target is ZombieDef:
		target.toughness = toughness
		target.speed = speed
		target.eat_dps = eat_dps
		target.wave_cost = wave_cost
		target.weight = weight
		target.sun_cost = sun_cost
		target.stun_scale = stun_scale
		target.water_speed_scale = water_speed_scale
		target.sort = sort
