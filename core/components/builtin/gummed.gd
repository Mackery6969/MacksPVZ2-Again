extends EntityComponent
## Stuck in gum, a zombie neither walks nor bites until it has chewed through
## the wad. Attached at runtime by a gumnut.
##
## Config: health (the wad; chewed at the zombie's own eating rate).

var gum: float = 0.0


func setup() -> void:
	gum = float(cfg(&"health", 1000.0))
	host.movement_claimed = true
	host.peaceful = true
	host.target = null
	host.set_runtime_tag(&"gummed", true)


func _process(delta: float) -> void:
	if host.is_dead:
		return
	if host.is_stunned() or host.is_encased():
		return
	gum -= host.eat_dps * delta
	if gum <= 0.0:
		host.movement_claimed = false
		host.peaceful = false
		host.set_runtime_tag(&"gummed", false)
		host.detach_component(self)
