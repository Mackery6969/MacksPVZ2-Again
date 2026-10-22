extends EntityComponent
## Brings back the last plant that died in its cell, at part of its health,
## and is spent - intensive carrot. Planted where nothing has died, it is
## simply used up.
##
## Config: health_fraction.

func setup() -> void:
	var board = host.board
	var back: StringName = board.last_dead_plant(host.row, host.col)
	host.die.call_deferred()
	# Queued on the board, which outlives the carrot: by the time it runs the
	# carrot is out of the cell and its own death is forgotten.
	board.revive_plant.call_deferred(back, host.row, host.col,
			float(cfg(&"health_fraction", 0.5)))
