extends EntityComponent
## Brings a column of identical zombies along, strung out behind the leader.
##
## This is how a camel train arrives: one entry in the wave, several bodies on
## the lawn. They spawn behind the leader so the lane fills from the edge
## inwards rather than all at once on top of each other.
##
## Config: teammate, count (a {Min, Max} range in the source data), spacing.

const DEFAULT_SPACING := 0.45

var teammate: StringName = &""
var spacing: float = DEFAULT_SPACING


func setup() -> void:
	teammate = StringName(cfg(&"teammate", &""))
	spacing = float(cfg(&"spacing", DEFAULT_SPACING))
	# An escort's members must not bring escorts of their own. The data
	# happens to say count 0 for the segments, but a mod will not, and one
	# missing zero would spawn until the process died.
	if teammate == &"" or host.has_tag(&"escorting"):
		return
	for i in range(_count()):
		var behind: float = host.position.x \
				- host.direction() * (i + 1) * spacing * host.board.cell_size.x
		var mate: Zombie = host.board.spawn_zombie_at(teammate, host.row,
				behind, [&"escorting"])
		if mate == null:
			continue
		mate.set_allegiance(host.allegiance)


## PopCap stores the size as a list of allowed lengths - a camel train is 5, 6
## or 7 segments - so one is picked per leader.
func _count() -> int:
	var raw: Variant = cfg(&"count", 0)
	if raw is Array:
		var choices: Array = raw
		if choices.is_empty():
			return 0
		return maxi(0, int(choices[randi() % choices.size()]))
	return maxi(0, int(cfg_range(&"count", 0.0)))
