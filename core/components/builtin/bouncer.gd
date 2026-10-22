extends EntityComponent
## Flings zombies that walk up to it back down the lane, a few times before it
## is just a wall - chard guard. Plant food restores its flings.
##
## Config: reach (squares ahead), distance (squares thrown), uses,
## require_tags.

var uses: int = 0


func setup() -> void:
	uses = int(cfg(&"uses", 3))


func _process(_delta: float) -> void:
	if host.is_dead or uses <= 0:
		return
	var reach: float = float(cfg(&"reach", 1.7)) * host.board.cell_size.x
	for z in host.board.hostile_zombies_in_row(host.row):
		var gap: float = z.position.x - host.position.x
		if gap >= -host.board.cell_size.x * 0.5 and gap <= reach \
				and z.matches(cfg(&"require_tags", [&"knockbackable"])):
			Audio.play(&"plant.spring", host.position)
			host.play_art_once(&"attack")
			z.knock_back(float(cfg(&"distance", 3.0)))
			uses -= 1
			return


func on_plantfood() -> bool:
	uses = int(cfg(&"uses", 3))
	host.heal(host.max_health)
	return true
