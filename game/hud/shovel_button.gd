class_name ShovelButton
extends Button
## The shovel, as PVZGE's round shovel button: idle, lit while hovered, held
## down while the shovel is in hand. Without art it is a text button.

var _icon: RigIcon
var _active: bool = false
## Followed every frame, so however the shovel is put down - a click on the
## lawn, Escape, picking a seed - the button lets go with it.
var board: Board = null


func _init() -> void:
	focus_mode = Control.FOCUS_NONE
	custom_minimum_size = Vector2(72, 72)
	_icon = RigIcon.new(&"shovel", Vector2(72, 72))
	_icon.set_anchors_preset(Control.PRESET_FULL_RECT)
	add_child(_icon)
	mouse_entered.connect(_refresh)
	mouse_exited.connect(_refresh)


func _ready() -> void:
	if _icon.has_art():
		flat = true
		text = ""
	else:
		text = "Shovel"
	_refresh()


func _process(_delta: float) -> void:
	if board != null and board.shovel_active != _active:
		set_active(board.shovel_active)


func set_active(active: bool) -> void:
	_active = active
	_refresh()


func _refresh() -> void:
	if not _icon.has_art():
		modulate = Color(0.7, 1.0, 0.7) if _active else Color.WHITE
		return
	if _active:
		_icon.play(&"chosen")
	elif is_hovered():
		_icon.play(&"pointed")
	else:
		_icon.play(&"idle")
