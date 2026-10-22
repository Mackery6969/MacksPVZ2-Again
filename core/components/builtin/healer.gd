extends EntityComponent
## Heals other plants. An aloe tends the plant in front of it while that plant
## is hurt and then patches itself up; a peach heals everything around it on a
## timer.
##
## Config: area ("ahead" - the square to the right - or "around" - the 3x3),
## interval, amount (each heal; an aloe states hps instead), hps, self_heal
## (an aloe's own top-up once its patient is whole), plantfood_hps,
## plantfood_heal (a peach's one-off), plantfood_duration.

var _timer: float = 0.0
var _food_left: float = 0.0
var _was_healing: bool = false


func setup() -> void:
	_timer = scaled(float(cfg(&"interval", 0.5)))


func _process(delta: float) -> void:
	if host.is_dead:
		return
	if _food_left > 0.0:
		_food_left -= delta
		var hps := float(cfg(&"plantfood_hps", 1000.0))
		for p in _patients(true):
			p.heal(hps * delta)
		return
	_timer -= delta
	if _timer > 0.0:
		return
	var interval := float(cfg(&"interval", 0.5))
	_timer = scaled(interval)
	var amount := float(cfg(&"amount", float(cfg(&"hps", 0.0)) * interval))
	var healed := false
	for p in _patients(String(cfg(&"area", "ahead")) == "around"):
		if p.health < p.max_health:
			p.heal(amount)
			healed = true
	# The aloe's own top-up comes once its patient is whole again.
	if _was_healing and not healed:
		host.heal(float(cfg(&"self_heal", 0.0)))
	_was_healing = healed


func _patients(around: bool) -> Array:
	var out: Array = []
	if not around:
		var ahead: Plant = host.board.plant_at(host.row, host.col + 1) \
				if host.col + 1 < host.board.cols else null
		if ahead != null and not ahead.is_dead:
			out.append(ahead)
		return out
	for r in range(maxi(0, host.row - 1), mini(host.board.rows, host.row + 2)):
		for c in range(maxi(0, host.col - 1), mini(host.board.cols, host.col + 2)):
			var p: Plant = host.board.plant_at(r, c)
			if p != null and not p.is_dead:
				out.append(p)
	return out


func on_plantfood() -> bool:
	if cfg(&"plantfood_heal") != null:
		for p in _patients(true):
			p.heal(float(cfg(&"plantfood_heal")))
	if cfg(&"plantfood_hps") != null:
		_food_left = float(cfg(&"plantfood_duration", 10.0))
	return true
