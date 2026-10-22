class_name SettingsMenu
extends Control
## The options screen, opened over the main menu or the pause menu.
##
## Every control writes straight through to `Settings`, which applies and
## saves the change at once, so there is no Apply button to forget.

signal closed

## Offer "Reset progress". Off in-level, where wiping the save under a
## running level would leave it in a confusing state.
var allow_reset_progress: bool = true

var _controls: Dictionary = {}   ## setting key -> Range or BaseButton
var _confirm: ConfirmationDialog


func _ready() -> void:
	set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	# Usable from the pause menu, which runs while the tree is paused.
	process_mode = Node.PROCESS_MODE_ALWAYS
	add_child(MenuUI.backdrop(Color(0, 0, 0, 0.6)))

	var parts := MenuUI.panel(440.0)
	add_child(parts[0])
	var stack: VBoxContainer = parts[1]

	var title := MenuUI.label("Settings", MenuUI.HEADING_SIZE)
	title.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	stack.add_child(title)

	_add_slider(stack, "Master volume", &"master_volume", 0.0, 1.0, 0.05, true)
	_add_slider(stack, "Music volume", &"music_volume", 0.0, 1.0, 0.05, true)
	_add_slider(stack, "Sound effects volume", &"sfx_volume", 0.0, 1.0, 0.05, true)
	_add_slider(stack, "Fast forward speed", &"fast_forward_scale", 1.5, 4.0, 0.5)
	_add_toggle(stack, "Fullscreen", &"fullscreen")
	_add_toggle(stack, "VSync", &"vsync")
	_add_toggle(stack, "Pause when the window loses focus", &"pause_on_focus_loss")
	_add_toggle(stack, "Unlock every plant (testing)", &"unlock_all_plants")

	var row := HBoxContainer.new()
	row.add_theme_constant_override("separation", 12)
	row.alignment = BoxContainer.ALIGNMENT_CENTER
	stack.add_child(row)
	row.add_child(MenuUI.button("Defaults", _on_defaults, Vector2(140, 44)))
	if allow_reset_progress:
		row.add_child(MenuUI.button("Reset progress", _ask_reset, Vector2(160, 44)))

	var back := MenuUI.button("Back", close)
	back.name = "Back"
	stack.add_child(back)
	back.grab_focus.call_deferred()

	_confirm = ConfirmationDialog.new()
	_confirm.title = "Reset progress"
	_confirm.dialog_text = ("Forget every cleared level and part-played save?\n"
			+ "Settings are kept.")
	_confirm.ok_button_text = "Reset"
	_confirm.confirmed.connect(_on_reset_confirmed)
	add_child(_confirm)


func close() -> void:
	closed.emit()
	queue_free()


func _unhandled_input(event: InputEvent) -> void:
	if event.is_action_pressed(&"ui_cancel"):
		get_viewport().set_input_as_handled()
		close()


func _add_slider(parent: Control, text: String, key: StringName,
		lo: float, hi: float, step: float, percent: bool = false) -> void:
	var row := HBoxContainer.new()
	parent.add_child(row)
	var name_label := MenuUI.label(text)
	name_label.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	row.add_child(name_label)

	var value_label := MenuUI.label("")
	value_label.custom_minimum_size.x = 56
	value_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_RIGHT

	var slider := HSlider.new()
	slider.min_value = lo
	slider.max_value = hi
	slider.step = step
	slider.custom_minimum_size.x = 160
	slider.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	var show := func(v: float) -> void:
		value_label.text = ("%d%%" % roundi(v * 100.0)) if percent else ("x%.1f" % v)
	slider.value = Settings.get_value(key)
	show.call(slider.value)
	slider.value_changed.connect(func(v: float) -> void:
		show.call(v)
		Settings.set_value(key, v))
	row.add_child(slider)
	row.add_child(value_label)
	_controls[key] = slider


func _add_toggle(parent: Control, text: String, key: StringName) -> void:
	var box := CheckButton.new()
	box.text = text
	box.add_theme_font_size_override("font_size", MenuUI.BODY_SIZE)
	box.button_pressed = Settings.get_value(key)
	box.toggled.connect(func(on: bool) -> void: Settings.set_value(key, on))
	parent.add_child(box)
	_controls[key] = box


func _on_defaults() -> void:
	Settings.reset_to_defaults()
	for key in _controls:
		var c = _controls[key]
		if c is Range:
			c.set_value_no_signal(Settings.get_value(key))
			# The value label follows value_changed, which no_signal skips.
			c.value_changed.emit(c.value)
		else:
			c.set_pressed_no_signal(Settings.get_value(key))


func _ask_reset() -> void:
	_confirm.popup_centered()


func _on_reset_confirmed() -> void:
	Saves.reset_progress()
