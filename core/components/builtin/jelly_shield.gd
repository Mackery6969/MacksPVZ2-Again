extends EntityComponent
## A wall of jelly over the nut while it is shadow powered - murkadamia. The
## jelly soaks bites first and throws part of each back at the biter, and
## regrows a while after the last one. Plant food fills it up.
##
## Config: toughness (the full jelly), initial (fraction it starts with),
## reflect (fraction of each bite thrown back), cooldown (seconds after a hit
## before it regrows), regen_hps.

var jelly: float = 0.0
var _since_hit: float = 0.0


func setup() -> void:
	jelly = float(cfg(&"toughness", 2500.0)) * float(cfg(&"initial", 0.6))


func _process(delta: float) -> void:
	if host.is_dead or not _powered():
		return
	_since_hit += delta
	if _since_hit >= float(cfg(&"cooldown", 5.0)):
		jelly = minf(float(cfg(&"toughness", 2500.0)),
				jelly + float(cfg(&"regen_hps", 100.0)) * delta)


func _powered() -> bool:
	return host.has_tag(&"shadow_powered") or host.has_tag(&"jelly_fed")


## Called by Character.take_damage before the nut itself is hit.
func absorb_damage(amount: float) -> float:
	if not _powered() or jelly <= 0.0:
		return amount
	_since_hit = 0.0
	var absorbed := minf(amount, jelly)
	jelly -= absorbed
	var biter: Node = host.last_damage_source
	if biter is Zombie and is_instance_valid(biter) and not biter.is_dead:
		biter.take_damage(absorbed * float(cfg(&"reflect", 0.25)), host)
	host.queue_redraw()
	return amount - absorbed


func on_plantfood() -> bool:
	jelly = float(cfg(&"toughness", 2500.0))
	host.add_timed_tag(&"jelly_fed", float(cfg(&"plantfood_duration", 10.0)))
	return true
