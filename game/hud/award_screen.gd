class_name AwardScreen
extends Control
## The screen after a prize is picked up: "You got a new plant!", the prize,
## and a button to carry on. PVZGE's awardScene.
##
## Coin bags never get here; they pay out on the lawn.

signal continued

var reward: LevelReward
var _title: Label
var _name: Label
var _detail: Label
var _packet: SeedPacketView
var _button: Button


func _init() -> void:
	set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	process_mode = Node.PROCESS_MODE_ALWAYS
	hide()


func _build() -> void:
	add_child(MenuUI.backdrop(Color(0, 0, 0, 0.6)))
	var parts := MenuUI.panel(420.0)
	add_child(parts[0])
	var stack: VBoxContainer = parts[1]
	_title = MenuUI.label("", MenuUI.HEADING_SIZE)
	_title.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	stack.add_child(_title)
	var center := CenterContainer.new()
	stack.add_child(center)
	_packet = SeedPacketView.new()
	_packet.custom_minimum_size = Vector2(120, 64)
	_packet.focus_mode = Control.FOCUS_NONE
	center.add_child(_packet)
	_name = MenuUI.label("", MenuUI.HEADING_SIZE - 4)
	_name.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	stack.add_child(_name)
	_detail = MenuUI.label("")
	_detail.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_detail.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	stack.add_child(_detail)
	_button = MenuUI.button("Continue", _on_continue)
	var row := CenterContainer.new()
	row.add_child(_button)
	stack.add_child(row)


func open(prize: LevelReward) -> void:
	reward = prize
	if _title == null:
		_build()
	_title.text = prize.title()
	_name.text = prize.item_name()
	var is_plant := prize.type == &"unlock_plant"
	_packet.visible = is_plant
	_detail.text = ""
	if is_plant:
		var def := Data.plant(prize.param)
		var cost := int(def.stat(&"sun_cost", 0)) if def != null else 0
		_packet.setup(&"plant", prize.param, cost, "")
		_packet.disabled = true
		_detail.text = "Costs %d sun. You can pick it before levels where you choose your seeds." % cost
	elif prize.type == &"gems":
		_detail.text = "Gems: %d" % Saves.currency(&"gems")
	show()
	_button.grab_focus()


func _on_continue() -> void:
	hide()
	continued.emit()


func _unhandled_input(event: InputEvent) -> void:
	if visible and event.is_action_pressed(&"ui_accept"):
		get_viewport().set_input_as_handled()
		_on_continue()
