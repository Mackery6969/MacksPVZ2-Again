extends EntityComponent
## Strikes zombies that come within reach (bonk choy and friends).
##
## Config: damage, damage_heavy, interval, detect_width.

var damage: float = 15.0
var interval: float = 0.3
var detect_width: float = 1.0

var _cooldown: float = 0.0


func setup() -> void:
	damage = float(cfg(&"damage", 15.0))
	# Witch hazel states its interval as a PopCap {Min, Max} range.
	var raw: Variant = cfg(&"interval", 0.3)
	interval = float(raw.get("Min", 0.3)) if raw is Dictionary else float(raw)
	detect_width = float(cfg(&"detect_width", 1.0))
	_cooldown = randf() * interval


func _process(delta: float) -> void:
	if host.is_dead:
		return
	_cooldown -= delta
	if _cooldown > 0.0:
		return
	var reach: float = detect_width * host.board.cell_size.x * 0.5
	for z in host.board.hostile_zombies_in_row(host.row):
		if absf(z.position.x - host.position.x) <= reach:
			z.take_damage(damage, host)
			host.play_art_once(&"attack")
			_cooldown = interval
			return


## Plant food: a flurry of heavy hits on everything in reach.
func on_plantfood() -> bool:
	var hits := int(cfg(&"plantfood_hits", 10))
	var power := float(cfg(&"damage_plantfood", damage * 4.0))
	var reach: float = detect_width * host.board.cell_size.x
	var struck := false
	for z in host.board.hostile_zombies_in_row(host.row):
		if absf(z.position.x - host.position.x) <= reach:
			z.take_damage(power * hits, host)
			struck = true
	return struck
