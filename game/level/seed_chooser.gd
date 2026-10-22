class_name SeedChooser
extends Control
## The pre-level screen where the player picks which plants to bring.
##
## A view over SeedChooserRules: the rules decide what may be picked and how
## many, this only shows them and collects the picks. Plants the level
## pre-picks start in the hand and cannot be put back. Ready-made decks fill
## the hand in one click. "Let's Rock!" is enabled once the hand is full, or
## exactly matches a challenging deck.

## The player is done. `hand` is what they picked, in slot order, with the
## Imitater as itself; `SeedChooserRules.seeds_for` turns it into a bank.
signal confirmed(hand: Array[StringName])

@export var columns: int = 8
@export var packet_size := Vector2(104, 52)
@export var font_size: int = 16

var rules: SeedChooserRules
## Plant ids in the hand, in slot order.
var chosen: Array[StringName] = []

var _hand: HBoxContainer
var _grid: GridContainer
var _decks: HBoxContainer
var _info: Label
var _start: Button
var _title: Label
## Plant id -> its button in the grid.
var _buttons: Dictionary = {}


## Shows the chooser for `chooser_rules`, starting from `remembered` picks
## where the rules still allow them.
func open(chooser_rules: SeedChooserRules, remembered: Array = []) -> void:
	rules = chooser_rules
	chosen = rules.locked.duplicate()
	if not rules.challenging_locked:
		for id in remembered:
			var sid := StringName(id)
			if chosen.size() >= rules.slots:
				break
			if _can_add(sid):
				chosen.append(sid)
	if _grid == null:
		_build()
	_fill_grid()
	_fill_decks()
	_refresh()
	show()
	Audio.play(&"ui.chooseseeds.open")


## Adds `id` to the hand. Returns false when it cannot go in.
func pick(id: StringName) -> bool:
	if not _can_add(id):
		Audio.play(&"ui.seed.refuse")
		return false
	chosen.append(id)
	Audio.play(&"ui.seed.select")
	_refresh()
	return true


func _can_add(id: StringName) -> bool:
	if chosen.has(id) or chosen.size() >= rules.slots or not rules.can_pick(id):
		return false
	if id == SeedChooserRules.IMITATER:
		return rules.can_imitate(chosen[-1] if not chosen.is_empty() else &"")
	return true


## Takes `id` back out of the hand, unless the level put it there. An
## Imitater copying it goes with it.
func unpick(id: StringName) -> bool:
	if not chosen.has(id) or rules.locked.has(id):
		return false
	var at := chosen.find(id)
	chosen.remove_at(at)
	if at < chosen.size() and chosen[at] == SeedChooserRules.IMITATER:
		chosen.remove_at(at)
	Audio.play(&"ui.chooseseeds.remove")
	_refresh()
	return true


## Replaces the hand with a deck's plants.
func use_deck(deck: Dictionary) -> void:
	chosen = rules.deck_picks(deck)
	Audio.play(&"ui.seed.select")
	_refresh()


func clear_hand() -> void:
	chosen = rules.locked.duplicate()
	_refresh()


func can_start() -> bool:
	return rules != null and rules.can_start(chosen)


## Confirms the hand. Returns false when it is not ready.
func lets_rock() -> bool:
	if not can_start():
		Audio.play(&"ui.seed.refuse")
		return false
	hide()
	confirmed.emit(chosen.duplicate())
	return true


func _unhandled_input(event: InputEvent) -> void:
	if not visible:
		return
	if event is InputEventKey and event.pressed and not event.echo \
			and event.keycode in [KEY_ENTER, KEY_KP_ENTER]:
		lets_rock()
		get_viewport().set_input_as_handled()


# --- view ------------------------------------------------------------------

func _build() -> void:
	set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	mouse_filter = Control.MOUSE_FILTER_STOP

	var shade := ColorRect.new()
	shade.color = Color(0, 0, 0, 0.55)
	shade.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	add_child(shade)

	var margin := MarginContainer.new()
	margin.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	for side in ["left", "right", "top", "bottom"]:
		margin.add_theme_constant_override("margin_" + side, 40)
	add_child(margin)

	var panel := PanelContainer.new()
	var style := StyleBoxFlat.new()
	style.bg_color = Color(0.13, 0.16, 0.12, 0.97)
	style.set_corner_radius_all(8)
	style.set_content_margin_all(14)
	panel.add_theme_stylebox_override("panel", style)
	margin.add_child(panel)
	var root := VBoxContainer.new()
	root.add_theme_constant_override("separation", 10)
	panel.add_child(root)

	_title = _label("Choose your seeds")
	root.add_child(_title)

	_hand = HBoxContainer.new()
	_hand.add_theme_constant_override("separation", 6)
	root.add_child(_hand)

	_decks = HBoxContainer.new()
	_decks.add_theme_constant_override("separation", 6)
	root.add_child(_decks)

	var scroll := ScrollContainer.new()
	scroll.size_flags_vertical = Control.SIZE_EXPAND_FILL
	scroll.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	root.add_child(scroll)
	_grid = GridContainer.new()
	_grid.columns = columns
	_grid.add_theme_constant_override("h_separation", 6)
	_grid.add_theme_constant_override("v_separation", 6)
	scroll.add_child(_grid)

	var bottom := HBoxContainer.new()
	bottom.add_theme_constant_override("separation", 12)
	root.add_child(bottom)
	_info = _label("")
	_info.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	bottom.add_child(_info)
	var clear := Button.new()
	clear.text = "Clear"
	clear.focus_mode = Control.FOCUS_NONE
	clear.pressed.connect(clear_hand)
	bottom.add_child(clear)
	_start = Button.new()
	_start.text = "Let's Rock!"
	_start.focus_mode = Control.FOCUS_NONE
	_start.custom_minimum_size = Vector2(160, 44)
	_start.pressed.connect(lets_rock)
	bottom.add_child(_start)


func _fill_grid() -> void:
	for b in _buttons.values():
		b.queue_free()
	_buttons.clear()
	for id in rules.candidates:
		var b := _packet_button(id)
		var why := rules.refusal(id)
		if why != "":
			b.tooltip_text = why
		b.pressed.connect(pick.bind(id))
		b.mouse_entered.connect(_describe.bind(id))
		_grid.add_child(b)
		_buttons[id] = b


func _fill_decks() -> void:
	for c in _decks.get_children():
		c.queue_free()
	if rules.decks.is_empty():
		_decks.hide()
		return
	_decks.show()
	_decks.add_child(_label("Decks:"))
	for deck in rules.decks:
		var b := Button.new()
		b.text = ("* " if deck["challenging"] else "") + String(deck["name"]).replace("\n", " ")
		b.tooltip_text = ", ".join(PackedStringArray(
				(deck["plants"] as Array).map(func(p): return _plant_name(StringName(p)))))
		b.focus_mode = Control.FOCUS_NONE
		b.pressed.connect(use_deck.bind(deck))
		_decks.add_child(b)


func _refresh() -> void:
	for c in _hand.get_children():
		c.queue_free()
	for i in rules.slots:
		if i < chosen.size():
			var id := chosen[i]
			var b := _packet_button(id)
			if id == SeedChooserRules.IMITATER and i > 0:
				b.text = "%s\n(%s)" % [_plant_name(id), _plant_name(chosen[i - 1])]
			if rules.locked.has(id):
				b.tooltip_text = "Chosen by the level"
				b.modulate = Color(1.0, 0.95, 0.75)
			b.pressed.connect(unpick.bind(id))
			_hand.add_child(b)
		else:
			var empty := Button.new()
			empty.disabled = true
			empty.focus_mode = Control.FOCUS_NONE
			empty.custom_minimum_size = packet_size
			_hand.add_child(empty)

	for id in _buttons:
		var b: Button = _buttons[id]
		var allowed := rules.refusal(id) == ""
		b.disabled = not allowed or chosen.has(id)
		b.modulate = Color.WHITE if allowed else Color(0.5, 0.5, 0.5)

	_title.text = "Choose your seeds  (%d / %d)" % [chosen.size(), rules.slots]
	_start.disabled = not can_start()


func _describe(id: StringName) -> void:
	var why := rules.refusal(id)
	_info.text = _plant_name(id) + ("  -  " + why if why != "" else "")


func _packet_button(id: StringName) -> Button:
	var b := Button.new()
	var def := Data.plant(id)
	b.text = "%s\n%d" % [_plant_name(id), int(def.stat(&"sun_cost", 0)) if def else 0]
	b.custom_minimum_size = packet_size
	b.clip_text = true
	b.focus_mode = Control.FOCUS_NONE
	b.add_theme_font_size_override("font_size", font_size)
	return b


func _plant_name(id: StringName) -> String:
	return String(id).capitalize()


func _label(text: String) -> Label:
	var l := Label.new()
	l.text = text
	l.add_theme_font_size_override("font_size", font_size + 2)
	return l
