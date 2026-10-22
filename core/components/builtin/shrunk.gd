extends EntityComponent
## Attached to a zombie a shrinking violet caught: it takes more damage,
## walks slower and bites softer, for good.
##
## Config: damage_multiplier, speed_scale, bite_scale.

func setup() -> void:
	host.scale_aggression(float(cfg(&"speed_scale", 0.75)),
			float(cfg(&"bite_scale", 0.5)))
	host.scale *= 0.6
	host.set_runtime_tag(&"shrunk", true)


## Runs alongside armour: whatever gets through is multiplied, so the extra
## damage lands on the body as well as on the cone.
func absorb_damage(amount: float) -> float:
	return amount * float(cfg(&"damage_multiplier", 2.0))
