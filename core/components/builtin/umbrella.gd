extends EntityComponent
## Shelters the 3x3 around it from whatever falls out of the sky - umbrella
## leaf. An imp thrown into its cover is bounced back to the far end of the
## lane. The board asks `Board.is_sheltered`, so whatever throws or drops
## things only has to check there.
##
## Config: radius (squares either side).

func setup() -> void:
	host.set_runtime_tag(&"umbrella", true)


## Whether this umbrella covers a cell.
func covers(row: int, col: int) -> bool:
	var reach := int(cfg(&"radius", 1))
	return absi(row - host.row) <= reach and absi(col - host.col) <= reach
