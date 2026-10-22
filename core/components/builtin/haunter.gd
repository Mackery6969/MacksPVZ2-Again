extends EntityComponent
## Haunts every zombie and gravestone near it with a steady trickle of damage,
## then blows up when its time is up - ghost pepper.
##
## The clock only starts once it first has something to haunt, so a ghost
## pepper planted early waits for the wave. Zombies walk through it rather
## than eating it.
##
## Config: damage, interval, reach (squares either side), lifetime,
## explode_damage, plantfood_duration, plantfood_multiplier.

var damage: float = 30.0
var interval: float = 0.5
var reach: float = 2.0
var lifetime: float = 10.0

var _life: float = -1.0
var _tick: float = 0.0
var _food_left: float = 0.0


func setup() -> void:
	damage = float(cfg(&"damage", damage))
	interval = float(cfg(&"interval", interval))
	reach = float(cfg(&"reach", reach))
	lifetime = float(cfg(&"lifetime", lifetime))
	host.set_runtime_tag(&"uneatable", true)


func _process(delta: float) -> void:
	if host.is_dead:
		return
	var fed := _food_left > 0.0
	if fed:
		_food_left -= delta
	var targets := _targets(fed)
	if _life < 0.0:
		if targets.is_empty():
			return
		_life = lifetime
	_life -= delta
	_tick -= delta
	if _tick <= 0.0 and not targets.is_empty():
		_tick = scaled(interval)
		var hit: float = damage * (float(cfg(&"plantfood_multiplier", 3.0)) if fed else 1.0)
		for t in targets:
			t.take_damage(hit, host)
	if _life <= 0.0:
		_explode()


func _targets(fed: bool) -> Array:
	var rows := 1 if fed else 0
	var span: float = reach + (0.5 if fed else 0.0)
	var out: Array = host.board.hostile_zombies_near(host.row, host.position.x, rows, span)
	for r in range(maxi(0, host.row - rows), mini(host.board.rows, host.row + rows + 1)):
		for g in host.board.graves_in_row(r):
			if absf(g.position.x - host.position.x) <= span * host.board.cell_size.x:
				out.append(g)
	return out


func _explode() -> void:
	Audio.play(&"plant.explode", host.position)
	var blast := float(cfg(&"explode_damage", 450.0))
	for z in host.board.hostile_zombies_near(host.row, host.position.x, 1, 1.5):
		z.take_damage(blast, host)
	host.die()


func on_plantfood() -> bool:
	_food_left = float(cfg(&"plantfood_duration", 3.5))
	return true
