extends EntityComponent
## Defines the area in which this entity can attack (eat, smash, strike).
##
## Config: rect - a named entry in RectangleProps.

var rect_id: StringName = &""


func setup() -> void:
	rect_id = StringName(cfg(&"rect", &""))
