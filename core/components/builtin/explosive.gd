extends EntityComponent
## Arms after a delay, then detonates when a zombie steps onto it.
##
## Config: damage, charge_time, plantfood_children.

var damage: float = 1800.0
var charge_time: float = 14.0

var _armed: bool = false
var _timer: float = 0.0


func setup() -> void:
	damage = float(cfg(&"damage", 1800.0))
	charge_time = float(cfg(&"charge_time", 14.0))
	_timer = charge_time
	host.set_runtime_tag(&"arming", true)
	# Until it arms it rests underground, as PVZGE's Idle_Baby.
	host.idle_state = &"asleep"
	# While still arming it is just a plant, and zombies will eat it.


func _process(delta: float) -> void:
	if host.is_dead:
		return
	if not _armed:
		_timer -= delta
		if _timer <= 0.0:
			_armed = true
			host.set_runtime_tag(&"arming", false)
			# Once armed it detonates on contact rather than being eaten, so
			# zombies walk over it instead of stopping to chew.
			host.set_runtime_tag(&"uneatable", true)
			_pop_up()
			host.queue_redraw()
		return

	var reach: float = host.board.cell_size.x * 0.5
	for z in host.board.hostile_zombies_in_row(host.row):
		if absf(z.position.x - host.position.x) <= reach:
			_detonate()
			return


## Plant food: arm instantly and go off now.
func on_plantfood() -> bool:
	_armed = true
	host.set_runtime_tag(&"arming", false)
	host.idle_state = &"idle"
	_detonate()
	return true


## Pops out of the ground and idles armed from then on.
func _pop_up() -> void:
	host.idle_state = &"idle"
	if not host.play_art_once(&"arm"):
		host.play_art(&"idle")


func _detonate() -> void:
	Audio.play(&"plant.explode", host.position)
	for z in host.board.hostile_zombies_in_row(host.row):
		if absf(z.position.x - host.position.x) <= host.board.cell_size.x:
			z.take_damage(damage, host)
	host.die()
