extends LawnComponent
## Paints a world's terrain onto the board.
##
## This is what makes Big Wave Beach water and Sky's open air the same
## feature: both are cells that demand something before a plant can go there,
## so a world just declares which cells are which terrain.
##
## Config, any combination of:
##   columns  - [{"terrain": "water", "from": 6, "to": 8}] whole columns
##   rows     - [{"terrain": "sky_gap", "row": 0}] whole lanes
##   cells    - [{"terrain": "water", "row": 2, "col": 7}] individual cells
##
## Later entries win, so a broad fill can be dotted with exceptions.

func setup() -> void:
	for band in (cfg(&"columns", []) as Array):
		if not (band is Dictionary):
			continue
		var terrain := StringName(band.get("terrain", &""))
		var from_col := int(band.get("from", 0))
		var to_col := int(band.get("to", from_col))
		for col in range(from_col, to_col + 1):
			for row in board.rows:
				board.set_terrain(row, col, terrain)

	for band in (cfg(&"rows", []) as Array):
		if not (band is Dictionary):
			continue
		var terrain := StringName(band.get("terrain", &""))
		var row := int(band.get("row", 0))
		for col in board.cols:
			board.set_terrain(row, col, terrain)

	for cell in (cfg(&"cells", []) as Array):
		if cell is Dictionary:
			board.set_terrain(int(cell.get("row", 0)), int(cell.get("col", 0)),
					StringName(cell.get("terrain", &"")))


func describe() -> String:
	return ""
