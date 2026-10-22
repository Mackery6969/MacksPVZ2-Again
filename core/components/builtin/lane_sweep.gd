extends EntityComponent
## Sends a crushing wave down its lane from the house end, then is gone -
## cran-jelly. Everything in the lane is in its way, wherever the plant was
## put down.
##
## Config: speed (squares per second), dps.

func setup() -> void:
	host.board.spawn_sweeper(host.row, float(cfg(&"speed", 4.4)),
			float(cfg(&"dps", 3000.0)), host)
	Audio.play(&"plant.explode", host.position)
	host.die.call_deferred()
