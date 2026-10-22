extends EntityComponent
## Goes off once a zombie reaches it, shrinking every zombie in the 3x3
## around it - shrinking violet. A shrunk zombie takes extra damage, walks and
## bites slower, and an imp shrinks to nothing.
##
## Config: damage_multiplier, speed_scale, bite_scale, delay (between the
## trigger and the shrink), radius (squares either side).

var _timer: float = -1.0


func _process(delta: float) -> void:
	if host.is_dead:
		return
	if _timer < 0.0:
		var half: float = host.board.cell_size.x * 0.5
		for z in host.board.hostile_zombies_in_row(host.row):
			if absf(z.position.x - host.position.x) <= half:
				_timer = scaled(float(cfg(&"delay", 1.5)))
				host.play_art_once(&"attack")
				host.set_runtime_tag(&"uneatable", true)
				return
		return
	_timer -= delta
	if _timer <= 0.0:
		_shrink_all()
		host.die()


func _shrink_all() -> void:
	Audio.play(&"plant.shrink", host.position)
	var radius := float(cfg(&"radius", 1.5))
	for z in host.board.hostile_zombies_near(host.row, host.position.x, 1, radius):
		if not z.has_tag(&"shrinkable") or z.component(&"shrunk") != null:
			continue
		# An imp is already as small as a zombie gets.
		if String(z.entity_id()).contains("imp"):
			z.die()
			continue
		z.attach_component(&"shrunk", {
			"damage_multiplier": float(cfg(&"damage_multiplier", 2.0)),
			"speed_scale": float(cfg(&"speed_scale", 0.75)),
			"bite_scale": float(cfg(&"bite_scale", 0.5)),
		})


func on_plantfood() -> bool:
	if _timer >= 0.0:
		return false
	_timer = 0.0
	return true
