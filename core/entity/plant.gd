class_name Plant
extends Character
## A plant occupies one grid cell and is stationary.
##
## Placeholder art: a rounded square tinted by the plant's family, with a
## health bar once damaged. Real art replaces `_draw` later without touching
## any behaviour.

const FAMILY_COLORS := {
	&"family:peashooter": Color("5fbf5f"),
	&"family:sun":        Color("f2c744"),
	&"family:defence":    Color("b98a54"),
	&"family:lobber":     Color("7fc46b"),
	&"family:melee":      Color("d05a5a"),
	&"family:explosive":  Color("c96a3a"),
	&"family:cold":       Color("6fc4d8"),
}
const DEFAULT_COLOR := Color("74a874")

@export var body_size := Vector2(56, 56)
@export var fallback_color: Color = DEFAULT_COLOR
@export var health_bar_color: Color = Color("6ad46a")

var _color: Color = DEFAULT_COLOR


func _on_initialized() -> void:
	_color = fallback_color
	for tag in FAMILY_COLORS:
		if has_tag(tag):
			_color = FAMILY_COLORS[tag]
			break
	queue_redraw()


func _on_death() -> void:
	Audio.play(&"plant.eaten", position)
	if board and board.has_method("remove_plant"):
		board.remove_plant(row, col)
	queue_free()


func _draw() -> void:
	var size := body_size
	var rect := Rect2(-size * 0.5, size)
	draw_rect(rect, _color, true)
	draw_rect(rect, _color.darkened(0.4), false, 2.0)

	if health < max_health:
		var bar := Rect2(Vector2(-size.x * 0.5, -size.y * 0.5 - 8), Vector2(size.x, 4))
		draw_rect(bar, Color(0, 0, 0, 0.5), true)
		bar.size.x *= health_fraction()
		draw_rect(bar, health_bar_color, true)
