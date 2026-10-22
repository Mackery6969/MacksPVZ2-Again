extends EntityComponent
## A Dark Ages potion: the first zombie to walk into it drinks it and is
## strengthened. Plants never use them, which is why they are objects.
##
## Config: effect ("speed", "toughness" or "invisibility"), speed_scale,
## damage_taken_scale, max_level - how many of one kind a zombie can drink.


func _process(_delta: float) -> void:
	if host.is_dead:
		return
	for z in host.board.hostile_zombies_in_row(host.row):
		if z.col == host.col and not z.is_encased():
			drink(z)
			return


## Applies this potion to `z` and uses it up. A zombie already at the limit
## for this kind still empties the bottle.
func drink(z: Zombie) -> void:
	var effect := StringName(cfg(&"effect", &"speed"))
	var key := StringName("potion_" + String(effect))
	var level := int(z.get_meta(key, 0))
	if level < int(cfg(&"max_level", 3)):
		z.set_meta(key, level + 1)
		match effect:
			&"speed":
				z.scale_aggression(float(cfg(&"speed_scale", 1.5)), 1.0)
			&"toughness":
				# Taking 85% damage is the same as having 1/0.85 the health.
				var scale := 1.0 / maxf(float(cfg(&"damage_taken_scale", 0.85)), 0.01)
				z.max_health *= scale
				z.health *= scale
			&"invisibility":
				z.set_runtime_tag(&"invisible", true)
				z.modulate.a = 0.25
		z.queue_redraw()
	host.die()
