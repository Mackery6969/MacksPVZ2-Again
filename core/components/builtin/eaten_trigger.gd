extends EntityComponent
## Strikes back at whatever eats this plant. One component for the family of
## plants whose whole point is being eaten:
##
## - `charm`: the eater turns and fights for the player (hypno-shroom).
##   Plant food makes the next eater come back as a gargantuar instead.
## - `stun_gas`: after `gas_delay`, the eater lets off gas that stuns every
##   zombie from it to the end of the lane (chili bean). The eater dies.
## - `poison`: the eater is poisoned (shadow-shroom).
## - `sun_infect`: the eater drops sun as it is hurt (sun bean).
## - `sun_bomb`: a sun bomb is left where the plant stood; collecting it
##   blows up the zombies around it (moon bean).
##
## The trigger is a zombie dealing the killing bite, read from
## `last_damage_source`; a plant crushed by anything else just dies.
##
## Config: effect, duration, dps, gas_delay, sun_per_hitpoint,
## zombie_damage, zombie_radius, plant_damage, plant_radius (radii in PVZGE
## pixels), plantfood_zombie (the fallback gargantuar).

var effect: StringName = &""
var _fed: bool = false


func setup() -> void:
	effect = StringName(cfg(&"effect", &""))
	host.died.connect(_on_died)


func _on_died(_who: Character) -> void:
	var eater = host.last_damage_source
	if not (eater is Zombie) or not is_instance_valid(eater) or eater.is_dead \
			or eater.is_charmed():
		return
	match effect:
		&"charm":
			_charm(eater)
		&"stun_gas":
			_gas(eater)
		&"poison":
			eater.apply_poison(float(cfg(&"dps", 30.0)), float(cfg(&"duration", 30.0)))
		&"sun_infect":
			var infection = eater.component(&"sun_infection")
			if infection == null:
				eater.attach_component(&"sun_infection",
						{"sun_per_hitpoint": float(cfg(&"sun_per_hitpoint", 0.2))})
		&"sun_bomb":
			host.board.drop_sun_bomb(host.position, {
				"zombie_damage": float(cfg(&"zombie_damage", 900.0)),
				"zombie_radius": host.board.pvzge_px(float(cfg(&"zombie_radius", 80.0))),
				"plant_damage": float(cfg(&"plant_damage", 500.0)),
				"plant_radius": host.board.pvzge_px(float(cfg(&"plant_radius", 40.0))),
			})


func _charm(eater: Zombie) -> void:
	Audio.play(&"plant.hypno", eater.position)
	if _fed:
		# The meal comes back as a gargantuar on the player's side - its own
		# world's, where there is one.
		var giant := StringName(String(eater.entity_id()).get_slice("_", 0)
				+ "_gargantuar")
		if Data.zombie(giant) == null:
			giant = StringName(cfg(&"plantfood_zombie", &"tutorial_gargantuar"))
		var row: int = eater.row
		var x: float = eater.position.x
		eater.die()
		var z: Zombie = host.board.spawn_zombie_at(giant, row, x)
		if z != null:
			z.charm()
		return
	eater.charm()


## The eater is done for either way; the gas is what makes a chili bean worth
## its sun, holding up the whole queue behind it.
func _gas(eater: Zombie) -> void:
	eater.attach_component(&"stun_gas", {
		"delay": float(cfg(&"gas_delay", 2.0)),
		"duration": float(cfg(&"duration", 10.0)),
	})


## Plant food only means something to a hypno-shroom; nothing else here
## takes it.
func on_plantfood() -> bool:
	if effect != &"charm" or _fed:
		return false
	_fed = true
	return true
