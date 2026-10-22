extends EntityComponent
## Bursts out a lump of sun the moment it is planted, and is spent - gold
## bloom.
##
## Config: sun (the total, paid out in whole tokens).

func setup() -> void:
	var tokens := ceili(float(cfg(&"sun", 100)) / SunToken.VALUE)
	for i in tokens:
		host.board.drop_sun(host.position + Vector2((i - tokens * 0.5) * 20.0, 0))
	host.die.call_deferred()
