extends EntityComponent
## Fires a projectile down the lane whenever a zombie is ahead.
##
## Config: projectile, interval, interval_jitter, projectile_plantfood,
## plantfood_count.

var interval: float = 1.5
var projectile_id: StringName = &"pea"

var _cooldown: float = 0.0
var _burst_remaining: int = 0
var _burst_gap: float = 0.0
var _burst_projectile: StringName = &"pea"


func setup() -> void:
	interval = float(cfg(&"interval", 1.5))
	projectile_id = StringName(cfg(&"projectile", &"pea"))
	# Stagger identical plants so they do not fire in lockstep.
	_cooldown = randf() * interval


func _process(delta: float) -> void:
	if host.is_dead:
		return

	# A plant food burst takes priority over the normal firing rhythm.
	if _burst_remaining > 0:
		_burst_gap -= delta
		if _burst_gap <= 0.0:
			host.board.spawn_projectile(_burst_projectile, host.row,
					host.position, host)
			_burst_remaining -= 1
			_burst_gap = 0.04
		return

	_cooldown -= delta
	if _cooldown > 0.0:
		return
	if not _has_target():
		return
	_fire()
	_cooldown = cfg_jittered(&"interval", &"interval_jitter", interval)


func _has_target() -> bool:
	var board = host.board
	if board == null:
		return false
	for z in board.hostile_zombies_in_row(host.row):
		if z.position.x > host.position.x:
			return true
	return false


func _fire() -> void:
	host.board.spawn_projectile(projectile_id, host.row, host.position, host)
	Audio.play(&"plant.shoot", host.position)


## Plant food: unload a burst of shots down the lane.
func on_plantfood() -> bool:
	var count := int(cfg(&"plantfood_count", 24))
	var id := StringName(cfg(&"projectile_plantfood", projectile_id))
	_burst_remaining = count
	_burst_projectile = id
	return count > 0
