class_name LevelBanner
extends Label
## The big red words across the lawn: Ready... Set... PLANT!, A huge wave of
## zombies is approaching, Final wave.
##
## Ported from PVZGE's `gamingWarn`: the label starts at `from` scale and
## tweens to `to` over `grow` seconds while fading in over the first half of
## that, holds for `hold`, then fades out over a third of a second. A new
## warning cuts off whatever was showing.

const FADE_OUT := 0.33

var _tween: Tween


func _init(font_size: int = 96) -> void:
	horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_theme_font_size_override("font_size", font_size)
	add_theme_color_override("font_outline_color", Color.BLACK)
	add_theme_constant_override("outline_size", maxi(4, font_size / 6))
	modulate.a = 0.0
	set_anchors_preset(Control.PRESET_FULL_RECT)


## Shows one warning. `from`/`to` are scales; PVZGE passes 4 -> 0.5 for the
## wave warnings and 0.4 -> 0.45 for Ready and Set.
func warn(words: String, hold: float = 5.0, from: float = 4.0, to: float = 0.5,
		grow: float = 0.33, color: Color = Color(1, 0, 0)) -> void:
	text = words
	add_theme_color_override("font_color", color)
	pivot_offset = size * 0.5
	if _tween != null:
		_tween.kill()
	scale = Vector2.ONE * from
	modulate.a = 0.0
	_tween = create_tween()
	_tween.set_parallel(true)
	_tween.tween_property(self, "scale", Vector2.ONE * to, grow)
	_tween.tween_property(self, "modulate:a", 1.0, grow * 0.5)
	_tween.chain().tween_interval(grow * 0.5 + hold)
	_tween.chain().tween_property(self, "modulate:a", 0.0, FADE_OUT)


## Ready... Set... PLANT!, with PVZGE's timings: each word 0.6s after the
## last. The font is sized so PVZGE's scales carry over unchanged.
func ready_set_plant(plant_word: String = "PLANT!") -> void:
	warn("Ready...", 3.0, 0.4, 0.45, 0.2)
	await get_tree().create_timer(0.6).timeout
	if not is_inside_tree():
		return
	warn("Set...", 3.0, 0.4, 0.45, 0.2)
	await get_tree().create_timer(0.6).timeout
	if not is_inside_tree():
		return
	warn(plant_word, 3.0, 0.6, 0.6, 0.2)


func huge_wave() -> void:
	warn("A huge wave of zombies is approaching!", 5.0, 4.0, 0.5, 0.33)


func final_wave() -> void:
	warn("FINAL WAVE", 5.0, 4.0, 0.5, 0.33)
