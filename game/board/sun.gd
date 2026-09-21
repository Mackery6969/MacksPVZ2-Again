class_name SunToken
extends Collectable
## A collectable sun.

## Every sun is worth the same amount, deliberately fixed rather than
## configurable. The original game drops 25; this is 50.
const VALUE := 50

@export var core_color: Color = Color("ffd83d")
@export var glow_color: Color = Color("ffee8a")


func _draw() -> void:
	draw_circle(Vector2.ZERO, radius, core_color)
	draw_circle(Vector2.ZERO, radius * 0.62, glow_color)
