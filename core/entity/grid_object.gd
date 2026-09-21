class_name GridObject
extends Character
## A board object occupying one cell: trap and slider tiles, liquids, mold,
## and zombie-side potions.
##
## Distinct from Plant because an object is never planted by the player and
## never belongs in a seed bank, and distinct from Grave because an object is
## not generally something plants destroy.

const CATEGORY_COLORS := {
	ObjectDef.Category.TILE: Color("8a7f5c"),
	ObjectDef.Category.LIQUID: Color("4f7fa8"),
	ObjectDef.Category.POTION: Color("7a4fa8"),
	ObjectDef.Category.OTHER: Color("6f6f6f"),
}

@export var body_size := Vector2(60, 34)

var _color: Color = Color("6f6f6f")


func _on_initialized() -> void:
	if def is ObjectDef:
		_color = CATEGORY_COLORS.get(def.category, _color)
	queue_redraw()


func category() -> ObjectDef.Category:
	return def.category if def is ObjectDef else ObjectDef.Category.OTHER


func _on_death() -> void:
	if board and board.has_method("remove_object"):
		board.remove_object(row, col)
	queue_free()


func _draw() -> void:
	var rect := Rect2(-body_size * 0.5, body_size)
	draw_rect(rect, _color, true)
	draw_rect(rect, _color.darkened(0.4), false, 2.0)
