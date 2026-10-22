class_name MenuUI
extends RefCounted
## Shared building blocks for the menu screens, so they look alike without a
## theme resource. Placeholder styling until the art pipeline provides the
## real panels and buttons; swapping that in means changing only this file.

const TITLE_SIZE := 44
const HEADING_SIZE := 28
const BODY_SIZE := 18
const BUTTON_SIZE := Vector2(260, 48)


static func label(text: String, size: int = BODY_SIZE) -> Label:
	var l := Label.new()
	l.text = text
	l.add_theme_font_size_override("font_size", size)
	l.add_theme_color_override("font_color", Color.WHITE)
	l.add_theme_color_override("font_shadow_color", Color(0, 0, 0, 0.8))
	l.add_theme_constant_override("shadow_offset_y", 2)
	return l


static func button(text: String, on_pressed: Callable,
		min_size: Vector2 = BUTTON_SIZE) -> Button:
	var b := Button.new()
	b.text = text
	b.custom_minimum_size = min_size
	b.add_theme_font_size_override("font_size", BODY_SIZE)
	b.pressed.connect(click)
	b.pressed.connect(on_pressed)
	return b


## A full-screen backdrop that also swallows clicks meant for what is behind.
static func backdrop(color: Color) -> ColorRect:
	var r := ColorRect.new()
	r.color = color
	r.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	r.mouse_filter = Control.MOUSE_FILTER_STOP
	return r


## A centred panel holding a vertical stack, returned as [panel, stack].
static func panel(min_width: float = 360.0) -> Array:
	var center := CenterContainer.new()
	center.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	center.mouse_filter = Control.MOUSE_FILTER_IGNORE
	var p := PanelContainer.new()
	p.custom_minimum_size.x = min_width
	var box := StyleBoxFlat.new()
	box.bg_color = Color(0.12, 0.16, 0.12)
	box.border_color = Color(0.45, 0.6, 0.35)
	box.set_border_width_all(3)
	box.set_corner_radius_all(12)
	p.add_theme_stylebox_override("panel", box)
	center.add_child(p)
	var margin := MarginContainer.new()
	for side in ["left", "right", "top", "bottom"]:
		margin.add_theme_constant_override("margin_" + side, 24)
	p.add_child(margin)
	var stack := VBoxContainer.new()
	stack.add_theme_constant_override("separation", 12)
	margin.add_child(stack)
	return [center, stack]


## Plays a UI cue only when the catalog has it, so screens can name the
## sounds they want before the audio side defines them.
static func cue(id: StringName) -> void:
	if Audio.has_event(id):
		Audio.play(id)


static func music(id: StringName) -> void:
	if Audio.has_event(id):
		Audio.play_music(id)


static func click() -> void:
	cue(&"ui.button.click")
