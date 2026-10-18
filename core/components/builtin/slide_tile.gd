extends EntityComponent
## A slide tile: a plant placed on it is carried one cell along the lane.
##
## Movement rather than a placement rule, which is why this is a component on
## the tile instead of a terrain flag - the cell is plantable, it just does not
## keep what you put there.
##
## Config: direction ("up" moves toward row 0, "down" away), interval.

var direction: int = -1
var interval: float = 1.5

var _timer: float = 0.0


func setup() -> void:
	direction = -1 if String(cfg(&"direction", "up")) == "up" else 1
	interval = float(cfg(&"interval", 1.5))
	_timer = interval


func _process(delta: float) -> void:
	_timer -= delta
	if _timer > 0.0:
		return
	_timer = interval

	var rider: Plant = host.board.plant_at(host.row, host.col)
	if rider == null or rider.is_dead:
		return
	var to_row: int = host.row + direction
	if not host.board.in_bounds(to_row, host.col):
		return
	if host.board.plant_at(to_row, host.col) != null:
		return      # occupied; the rider stays put this tick
	host.board.move_plant(host.row, host.col, to_row, host.col)
