extends EntityComponent
## Turns its own cell into terrain, then is gone - power tiles, gold leaf.
##
## The cell keeps the terrain after the plant is spent, which is the point:
## the plant is a delivery mechanism for a board change.
##
## Config: tile - an object id from the terrain data.

func setup() -> void:
	var tile := StringName(cfg(&"tile", &""))
	if tile == &"":
		return
	host.board.set_terrain(host.row, host.col, tile)
	# Placed and done; the terrain is the lasting effect.
	host.die.call_deferred()
