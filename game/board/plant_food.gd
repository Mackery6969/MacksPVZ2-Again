class_name PlantFoodToken
extends Collectable
## A collectable plant food, dropped by zombies that were carrying it.

## One pickup is one use.
const VALUE := 1

@export var outer_color: Color = Color("3fb96b")
@export var inner_color: Color = Color("9bf0b5")


func _draw() -> void:
	# A rounded lozenge, so it never reads as sun at a glance.
	draw_circle(Vector2.ZERO, radius, outer_color)
	draw_rect(Rect2(Vector2(-radius * 0.28, -radius * 0.75),
			Vector2(radius * 0.56, radius * 1.5)), inner_color, true)
	draw_circle(Vector2(0, -radius * 0.55), radius * 0.3, inner_color)
