extends EntityComponent
## Hurts everything in a band of its lane continuously rather than shooting -
## inferno, fire gourd, a warming radius.
##
## Config: dps, min_distance, max_distance (cells), duration (0 = forever),
## charge_time before it starts.

var dps: float = 100.0
var min_distance: float = 0.0
var max_distance: float = 3.0
var duration: float = 0.0
var charge_time: float = 0.0

var _charge: float = 0.0
var _active: float = 0.0
var _accumulator: float = 0.0


func setup() -> void:
	dps = float(cfg(&"dps", 100.0))
	min_distance = float(cfg(&"min_distance", 0.0))
	max_distance = float(cfg(&"max_distance", 3.0))
	duration = float(cfg(&"duration", 0.0))
	charge_time = float(cfg(&"charge_time", 0.0))
	_charge = charge_time
	_active = duration


func _process(delta: float) -> void:
	if host.is_dead:
		return
	if _charge > 0.0:
		_charge -= delta
		return
	if duration > 0.0:
		_active -= delta
		if _active <= 0.0:
			host.die()
			return

	# Damage is accumulated so a low dps still lands whole hits.
	_accumulator += dps * delta
	var whole := floorf(_accumulator)
	if whole < 1.0:
		return
	_accumulator -= whole

	var cell: float = host.board.cell_size.x
	for z in host.board.hostile_zombies_in_row(host.row):
		var gap: float = absf(z.position.x - host.position.x) / cell
		if gap >= min_distance and gap <= max_distance:
			z.take_damage(whole, host)


func on_plantfood() -> bool:
	dps *= 3.0
	max_distance += 1.0
	_charge = 0.0
	return true
