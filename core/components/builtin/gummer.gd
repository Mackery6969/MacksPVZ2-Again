extends EntityComponent
## Bursts into gum when a zombie walks up, gluing it and its neighbours in
## place until they chew free - gumnut. Plant food gums the 3x3 around it
## without spending the nut.
##
## Config: reach (squares ahead that trigger it), radius (squares the gum
## spreads), gum_health (most a single wad holds), health_mult (a wad holds
## this many times the zombie's health, up to gum_health), require_tags.

func _process(_delta: float) -> void:
	if host.is_dead:
		return
	var reach: float = float(cfg(&"reach", 1.0)) * host.board.cell_size.x
	for z in host.board.hostile_zombies_in_row(host.row):
		if z.position.x >= host.position.x - host.board.cell_size.x * 0.5 \
				and z.position.x - host.position.x <= reach and _gummable(z):
			_gum(host.board.hostile_zombies_near(host.row, host.position.x, 0,
					float(cfg(&"radius", 1.0)) + float(cfg(&"reach", 1.0))))
			host.die()
			return


func _gummable(z: Zombie) -> bool:
	return z.matches(cfg(&"require_tags", [&"gummable"])) and z.component(&"gummed") == null


func _gum(zombies: Array) -> int:
	var stuck := 0
	for z in zombies:
		if not _gummable(z):
			continue
		var wad := minf(float(cfg(&"gum_health", 4000.0)),
				z.health * float(cfg(&"health_mult", 3.0)))
		z.attach_component(&"gummed", {"health": wad})
		stuck += 1
	return stuck


func on_plantfood() -> bool:
	_gum(host.board.hostile_zombies_near(host.row, host.position.x, 1, 1.5))
	return true
