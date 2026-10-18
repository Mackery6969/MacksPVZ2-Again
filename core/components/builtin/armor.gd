extends EntityComponent
## A detachable armor piece (cone, bucket, screen door) that absorbs damage
## before the body takes any.
##
## Config: armor - id in ArmorProps; slot - attachment point; toughness - an
## inline pool used instead of a named armor, which is how PopCap stores a
## poncho, a surfboard or a newspaper. A zombie can wear several: they absorb
## in the order they are listed, outermost first.

var durability: float = 0.0
var is_metal: bool = false

var _broken: bool = false
var _max_durability: float = 0.0


func setup() -> void:
	var inline := float(cfg(&"toughness", 0.0))
	if inline > 0.0:
		durability = inline
		is_metal = bool(cfg(&"metal", false))
	else:
		var armor_id := StringName(cfg(&"armor", &""))
		var def := Data.armor(armor_id)
		if def == null:
			push_warning("armor: unknown armor '%s'" % armor_id)
			durability = 370.0
		else:
			durability = def.toughness
			is_metal = def.is_metal
	_max_durability = durability
	if is_metal:
		host.set_runtime_tag(&"metal", true)
	host.set_runtime_tag(&"armored", true)
	host.queue_redraw()


## Whether the armor is still on. Drawn by the host, so placeholder zombies
## visibly differ while wearing it.
func is_intact() -> bool:
	return not _broken and durability > 0.0


## 1.0 when untouched, falling to 0 as the armor is chewed through.
func fraction() -> float:
	return clampf(durability / maxf(_max_durability, 1.0), 0.0, 1.0)


## Called by Character.take_damage before the body is hit.
## Returns the damage that survives this armor.
func absorb_damage(amount: float) -> float:
	if _broken or durability <= 0.0:
		return amount
	var absorbed := minf(amount, durability)
	durability -= absorbed
	if durability <= 0.0:
		_broken = true
		Audio.play(&"zombie.armor.break", host.position)
		host.set_runtime_tag(&"metal", false)
		host.set_runtime_tag(&"armored", false)
	host.queue_redraw()
	return amount - absorbed
