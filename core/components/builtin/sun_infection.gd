extends EntityComponent
## Attached to a zombie that ate a sun bean: every blow it takes shakes sun
## loose, `sun_per_hitpoint` sun per point of damage.
##
## Config: sun_per_hitpoint.

var _owed: float = 0.0


func setup() -> void:
	host.damaged.connect(_on_damaged)
	host.set_runtime_tag(&"sun_infected", true)


func _on_damaged(_who: Character, amount: float, _remaining: float) -> void:
	_owed += amount * float(cfg(&"sun_per_hitpoint", 0.2))
	while _owed >= SunToken.VALUE:
		_owed -= SunToken.VALUE
		host.board.drop_sun(host.position)
