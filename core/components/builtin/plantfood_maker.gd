extends EntityComponent
## Makes plant food out of thin air and is spent - power lily.
##
## Config: count.

func setup() -> void:
	for i in int(cfg(&"count", 1)):
		host.board.drop_plant_food(host.position)
	host.die.call_deferred()
