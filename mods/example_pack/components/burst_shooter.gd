extends EntityComponent
## Fires several shots in quick succession instead of one at a time.
##
## Shipping this file is all it takes to add a new behaviour - the loader
## registers it under the type name `burst_shooter`, and any plant JSON in any
## pack can then use it.
##
## Config: projectile, interval, burst, burst_gap.

var interval: float = 2.0
var burst: int = 3
var burst_gap: float = 0.12
var projectile_id: StringName = &"pea"

var _cooldown: float = 0.0
var _remaining: int = 0
var _gap: float = 0.0


func setup() -> void:
	interval = float(cfg(&"interval", 2.0))
	burst = int(cfg(&"burst", 3))
	burst_gap = float(cfg(&"burst_gap", 0.12))
	projectile_id = StringName(cfg(&"projectile", &"pea"))
	_cooldown = randf() * interval


func _process(delta: float) -> void:
	if host.is_dead:
		return

	if _remaining > 0:
		_gap -= delta
		if _gap <= 0.0:
			_shoot()
			_remaining -= 1
			_gap = burst_gap
		return

	_cooldown -= delta
	if _cooldown > 0.0:
		return
	if host.board.hostile_zombies_in_row(host.row).is_empty():
		return
	_remaining = burst
	_gap = 0.0
	_cooldown = interval


func _shoot() -> void:
	host.board.spawn_projectile(projectile_id, host.row, host.position, host)
