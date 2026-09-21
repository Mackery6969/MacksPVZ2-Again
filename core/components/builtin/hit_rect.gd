extends EntityComponent
## Defines the area that projectiles and attacks can strike.
##
## Config: rect - a named entry in RectangleProps. Kept as a component so a mod
## can resize a zombie's hitbox, or swap in its own targeting rules, as data.

var rect_id: StringName = &""


func setup() -> void:
	rect_id = StringName(cfg(&"rect", &""))
