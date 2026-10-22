extends EntityComponent
## Rewinds every zombie on the lawn back to where it came in, at full health,
## and is spent - thyme warp. Bosses are not rewound, nor anything without the
## `warpable` tag.
##
## Config: none.

func setup() -> void:
	Audio.play(&"plant.warp", host.position)
	for z in host.board.all_hostile_zombies():
		if not z.has_tag(&"warpable") or z.component(&"zomboss") != null:
			continue
		z.position.x = host.board.spawn_x()
		z.col = host.board.world_to_col(z.position.x)
		z.target = null
		z.heal(z.max_health)
	host.die.call_deferred()
