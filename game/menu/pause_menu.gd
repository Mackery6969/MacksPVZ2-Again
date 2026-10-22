class_name PauseMenu
extends CanvasLayer
## The in-level pause button and the menu it opens.
##
## Pausing stops the whole tree, so the lawn freezes exactly - timers,
## projectiles and recharge included - and this layer keeps running on its own.
## It only asks for things to happen; the level decides what restarting or
## leaving means, including saving first.

signal resumed
signal restart_requested
## `destination` is &"map" or &"menu".
signal exit_requested(destination: StringName)

## Asked before opening, so the level can refuse (between levels, say).
var can_open: Callable

var _button: Button
var _overlay: Control
var _panel: Control
var _settings: SettingsMenu


func _ready() -> void:
	layer = 10
	process_mode = Node.PROCESS_MODE_ALWAYS

	# The button sits in the top-right corner, clear of the seed bank.
	_button = Button.new()
	_button.name = "PauseButton"
	_button.text = "II"
	_button.tooltip_text = "Pause (Esc)"
	_button.focus_mode = Control.FOCUS_NONE
	_button.custom_minimum_size = Vector2(48, 48)
	_button.add_theme_font_size_override("font_size", 20)
	_button.set_anchors_preset(Control.PRESET_TOP_RIGHT)
	_button.offset_left = -64
	_button.offset_right = -16
	_button.offset_top = 16
	_button.offset_bottom = 64
	_button.pressed.connect(open)
	add_child(_button)

	_overlay = Control.new()
	_overlay.name = "Overlay"
	_overlay.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	_overlay.visible = false
	add_child(_overlay)
	_overlay.add_child(MenuUI.backdrop(Color(0, 0, 0, 0.55)))

	var parts := MenuUI.panel(320.0)
	_panel = parts[0]
	_overlay.add_child(_panel)
	var stack: VBoxContainer = parts[1]
	var title := MenuUI.label("Paused", MenuUI.HEADING_SIZE)
	title.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	stack.add_child(title)
	var resume := MenuUI.button("Resume", close)
	resume.name = "Resume"
	stack.add_child(resume)
	stack.add_child(MenuUI.button("Restart level", _on_restart))
	stack.add_child(MenuUI.button("Settings", _open_settings))
	stack.add_child(MenuUI.button("World map", _on_exit.bind(&"map")))
	stack.add_child(MenuUI.button("Main menu", _on_exit.bind(&"menu")))


func is_open() -> bool:
	return _overlay.visible


func open() -> void:
	if is_open() or (can_open.is_valid() and not can_open.call()):
		return
	_overlay.visible = true
	_button.visible = false
	get_tree().paused = true
	MenuUI.cue(&"ui.pause")
	_focus_first()


func close() -> void:
	if not is_open():
		return
	if _settings != null:
		_settings.close()
	_overlay.visible = false
	_button.visible = true
	get_tree().paused = false
	MenuUI.cue(&"ui.unpause")
	resumed.emit()


func _unhandled_input(event: InputEvent) -> void:
	if is_open() and _settings == null and (event.is_action_pressed(&"ui_cancel")
			or event.is_action_pressed(&"Pause")):
		get_viewport().set_input_as_handled()
		close()


func _focus_first() -> void:
	var resume := _overlay.find_child("Resume", true, false) as Button
	if resume != null:
		resume.grab_focus.call_deferred()


func _open_settings() -> void:
	_settings = SettingsMenu.new()
	_settings.allow_reset_progress = false
	# One panel at a time, so the two menus do not show through each other.
	_panel.visible = false
	_settings.closed.connect(func() -> void:
		_settings = null
		_panel.visible = true
		_focus_first())
	_overlay.add_child(_settings)


func _on_restart() -> void:
	_release()
	restart_requested.emit()


func _on_exit(destination: StringName) -> void:
	_release()
	exit_requested.emit(destination)


## Unpauses without the resume cue, for actions that leave the current run.
func _release() -> void:
	if _settings != null:
		_settings.close()
	_overlay.visible = false
	_button.visible = true
	get_tree().paused = false
