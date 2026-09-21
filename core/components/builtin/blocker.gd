extends EntityComponent
## A high-toughness plant whose job is to soak damage (wall-nut and friends).
##
## Config: armor_toughness - when present it replaces the plant's base
## toughness, since PopCap stores a wall-nut's real health there.

func setup() -> void:
	var armor := float(cfg(&"armor_toughness", 0.0))
	if armor > 0.0:
		host.max_health = armor
		host.health = armor
	host.set_runtime_tag(&"blocker", true)


## Plant food: patch the plant back up to full.
func on_plantfood() -> bool:
	if host.health >= host.max_health:
		return false
	host.heal(host.max_health)
	return true
