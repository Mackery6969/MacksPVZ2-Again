extends EntityComponent
## Lets another plant stand on top of it where it could not stand alone - a
## lily pad on water, a flower pot in the sky. The carrying is the board's
## job (the plant's `provides:<tag>`); this only holds what the carrier does
## with plant food.
##
## Config: plantfood_toughness (a flower pot toughens up).

func setup() -> void:
	host.set_runtime_tag(&"carrier", true)


func on_plantfood() -> bool:
	var toughness := float(cfg(&"plantfood_toughness", 0.0))
	if toughness <= 0.0:
		return false
	host.max_health = maxf(host.max_health, toughness)
	host.heal(toughness)
	return true
