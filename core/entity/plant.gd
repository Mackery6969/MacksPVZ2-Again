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
@export var stunned_color: Color = Color("8e8e9c")

## How much of its usual pace a stunned plant keeps. Not zero, so a stunned
## plant looks slowed rather than switched off.
const STUN_FACTOR := 0.05

var _color: Color = DEFAULT_COLOR
## For an imitater: the plant it turns into. Set from its seed packet.
var imitates: StringName = &""


func art_kind() -> StringName:
	return &"plant"


## Damage states a rig may be drawn in, worst last. A wall-nut has four; most
## plants have none and simply keep idling.
const DAMAGE_STATES: Array[StringName] = [&"hurt1", &"hurt2", &"hurt3"]

var _damage_state: StringName = &"idle"


func _on_initialized() -> void:
	play_art(&"idle")
	damaged.connect(_on_damaged)
	_color = fallback_color
	for tag in FAMILY_COLORS:
		if has_tag(tag):
			_color = FAMILY_COLORS[tag]
			break
	queue_redraw()


## A plant has no movement to stop, so being stunned means everything it does
## crawls. Suppression is divided into every component's timers through
## `scaled()`, so no component has to know it can be stunned - which is how
## Zomboss's roar reaches all 15 behaviours at once.
## Shows the wear. The bands are even across the health bar, so a plant drawn
## in four states changes at three quarters, a half and a quarter.
func _on_damaged(_who: Character, _amount: float, _remaining: float) -> void:
	if art == null or is_dead:
		return
	var bands := DAMAGE_STATES.size() + 1
	var step := int((1.0 - health_fraction()) * bands)
	var want: StringName = &"idle" if step <= 0 else DAMAGE_STATES[
			mini(step - 1, DAMAGE_STATES.size() - 1)]
	if want == _damage_state:
		return
	if play_art(want):
		_damage_state = want


func apply_stun(seconds: float) -> void:
	apply_suppression(STUN_FACTOR, seconds)
	queue_redraw()


func is_stunned() -> bool:
	return is_suppressed()


func _on_death() -> void:
	Audio.play(&"plant.eaten", position)
	if board and board.has_method("remove_plant"):
		board.remove_plant(row, col, self)
	queue_free()


func _draw() -> void:
	var size := body_size
	var rect := Rect2(-size * 0.5, size)
	# With real art attached the placeholder body would sit on top of it;
	# the health bar below still draws, because the art has none.
	if art == null:
		var body: Color = stunned_color if is_stunned() else _color
		draw_rect(rect, body, true)
		draw_rect(rect, body.darkened(0.4), false, 2.0)

	if health < max_health:
		var bar := Rect2(Vector2(-size.x * 0.5, -size.y * 0.5 - 8), Vector2(size.x, 4))
		draw_rect(bar, Color(0, 0, 0, 0.5), true)
		bar.size.x *= health_fraction()
		draw_rect(bar, health_bar_color, true)
