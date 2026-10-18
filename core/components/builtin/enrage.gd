extends EntityComponent
## Makes this zombie faster and harder-hitting once something is taken from it.
##
## A newspaper zombie is the case the data describes: ordinary until the paper
## is shredded, then four times the speed and four times the bite. The trigger
## is losing the last of its armor, or crossing a health fraction when the
## entry gives one instead.
##
## Config: damage_scale, speed_scale, health_pct, on_armor_broken.

var damage_scale: float = 1.0
var speed_scale: float = 1.0
var health_pct: float = 0.0
var on_armor_broken: bool = false

var _enraged: bool = false


func setup() -> void:
	damage_scale = float(cfg(&"damage_scale", 1.0))
	speed_scale = float(cfg(&"speed_scale", 1.0))
	health_pct = float(cfg(&"health_pct", 0.0))
	on_armor_broken = bool(cfg(&"on_armor_broken", false))


## Polled rather than driven off `damaged`, because the hit that shreds the
## paper may be entirely absorbed by it - no damage reaches the body, no
## signal fires, and the zombie would stay calm until something hit it again.
func _process(_delta: float) -> void:
	if _enraged or host.is_dead:
		return
	if health_pct > 0.0:
		if host.health_fraction() > health_pct:
			return
	elif on_armor_broken:
		if _still_armored():
			return
	else:
		return
	_enrage()


## Any armor still absorbing counts: a poncho zombie keeps its temper until
## both the plate and the poncho are off.
func _still_armored() -> bool:
	for c in host.components():
		if c.has_method("is_intact") and c.is_intact():
			return true
	return false


func _enrage() -> void:
	_enraged = true
	host.set_runtime_tag(&"enraged", true)
	host.scale_aggression(speed_scale, damage_scale)
	Audio.play(&"zombie.enrage", host.position)
