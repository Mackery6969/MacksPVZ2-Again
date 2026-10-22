class_name SunBomb
extends Collectable
## A sun that is really a bomb, left behind by a moon bean. Sweeping over it
## sets it off rather than banking it: zombies near it take a big hit, and
## plants close to it a smaller one.

var board: Node = null
var zombie_damage: float = 900.0
var zombie_radius: float = 94.0
var plant_damage: float = 500.0
var plant_radius: float = 47.0

@export var core_color: Color = Color("f2a23a")
@export var fuse_color: Color = Color("7a2e12")


func collect() -> void:
	if is_collected():
		return
	_explode()


func _explode() -> void:
	# Marked collected so hover polling cannot set it off twice.
	_collected = true
	queue_free()
	if board == null:
		return
	var at: Vector2 = position
	Audio.play(&"plant.explode", at)
	for z in board.all_hostile_zombies():
		if z.position.distance_to(at) <= zombie_radius:
			z.take_damage(zombie_damage, self)
	if plant_damage > 0.0:
		for r in board.rows:
			for p in board.plants_in_row(r):
				if p.position.distance_to(at) <= plant_radius:
					p.take_damage(plant_damage, self)


func _draw() -> void:
	draw_circle(Vector2.ZERO, radius, core_color)
	draw_circle(Vector2(0, -radius * 0.9), radius * 0.25, fuse_color)
