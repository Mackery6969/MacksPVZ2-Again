extends EntityComponent
## Strikes back at everything around it each time it loses a chunk of health -
## lychee. Plant food makes it hit harder and more often, and halves what it
## takes, for a while.
##
## Config: damage, health_between (the chunk), radius (squares either side),
## plantfood_damage, plantfood_health_between, plantfood_damage_taken,
## plantfood_duration.

var _lost: float = 0.0
var _food_left: float = 0.0


func setup() -> void:
	host.damaged.connect(_on_damaged)


func _process(delta: float) -> void:
	if _food_left > 0.0:
		_food_left -= delta


func _on_damaged(_who: Character, amount: float, _remaining: float) -> void:
	var fed := _food_left > 0.0
	var chunk := float(cfg(&"plantfood_health_between", 50.0) if fed
			else cfg(&"health_between", 100.0))
	var damage := float(cfg(&"plantfood_damage", 40.0) if fed else cfg(&"damage", 20.0))
	_lost += amount
	while _lost >= chunk:
		_lost -= chunk
		for z in host.board.hostile_zombies_near(host.row, host.position.x, 1,
				float(cfg(&"radius", 1.5))):
			z.take_damage(damage, host)


## Called by Character.take_damage: while fed, only part of a bite lands.
func absorb_damage(amount: float) -> float:
	if _food_left > 0.0:
		return amount * float(cfg(&"plantfood_damage_taken", 0.5))
	return amount


func on_plantfood() -> bool:
	_food_left = float(cfg(&"plantfood_duration", 10.0))
	host.heal(host.max_health)
	return true
