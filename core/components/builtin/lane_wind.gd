extends EntityComponent
## Blows a chilling wind down its lane for a few seconds, pushing every zombie
## in it back and chilling them, then is spent - hurrikale.
##
## Config: duration, push_speed (squares per second), chill.

var _left: float = 0.0


func setup() -> void:
	_left = float(cfg(&"duration", 3.0))
	host.set_runtime_tag(&"uneatable", true)
	Audio.play(&"plant.wind", host.position)


func _process(delta: float) -> void:
	if host.is_dead:
		return
	var push := float(cfg(&"push_speed", 2.0)) * delta
	for z in host.board.hostile_zombies_in_row(host.row):
		if z.is_encased():
			continue
		z.knock_back(push)
		z.apply_slow(0.5, float(cfg(&"chill", 8.0)))
	_left -= delta
	if _left <= 0.0:
		host.die()
