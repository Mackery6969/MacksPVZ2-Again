extends Node2D
## Entry point: builds the board, wires the HUD, and runs a level.

## Campaign to play. Clearing a level advances to the next one in its list.
@export var campaign_id: StringName = &"tutorial"
## Level to begin at. Empty starts at the campaign's first level; setting it
## to any level id jumps straight there, which is handy while testing.
@export var start_level: StringName = &""

@export_group("Saving")
## Seconds between autosaves while a level is running. Every level keeps its
## own slot, so several can be part-played at once.
@export var autosave_interval: float = 10.0
## Resume a part-played level instead of restarting it.
@export var resume_saves: bool = true

@export_group("Pacing")
## Seconds the result is shown before the next level begins.
@export var level_transition_delay: float = 2.5
## Seconds before a failed level restarts.
@export var retry_delay: float = 3.0

@export_group("HUD")
@export var hud_font_size: int = 18
@export var seed_button_size := Vector2(96, 56)
## Speed applied while Fast Forward is toggled on.
@export_range(1.0, 8.0) var fast_forward_scale: float = 2.5

@onready var board: Board = $Board
@onready var runner: LevelRunner = $LevelRunner

var seed_bank: SeedBank

var _seed_buttons: Array[Button] = []
## {kind, id} per slot, parallel to _seed_buttons.
var _seeds: Array[Dictionary] = []
var _status: Label
var _sun_label: Label
var _wave_label: Label
var _level_label: Label
var _seed_bar: HBoxContainer

var _mode_label: Label
var _plant_food_label: Label
var _objective_label: Label
var _ability_label: Label
var _conveyor_level: bool = false
var _fast_forward: bool = false

var _campaign: CampaignDef
var _current_level: StringName = &""
## Guards against a result firing twice while a transition is already queued.
var _transitioning: bool = false
var _autosave_timer: float = 0.0


func _ready() -> void:
	_build_hud()
	board.sun_changed.connect(_on_sun_changed)
	board.plant_food_changed.connect(_on_plant_food_changed)
	board.lawn_ability_changed.connect(_on_lawn_ability_changed)
	board.level_lost.connect(_on_lost)
	runner.seedbank_ready.connect(_on_seedbank_ready)
	runner.wave_started.connect(_on_wave_started)
	runner.level_complete.connect(_on_won)
	runner.level_failed.connect(_on_objective_failed)
	runner.objectives_changed.connect(_on_objectives_changed)

	print("[boot] ", Data.summary())
	print("[boot] ", Components.summary())
	print("[boot] ", Mods.summary())
	print("[boot] ", Audio.summary())
	print("[boot] ", Saves.summary())

	_campaign = Data.campaign(campaign_id)
	var first := start_level
	if first == &"":
		if _campaign == null:
			_status.text = "Campaign '%s' not found" % campaign_id
			return
		first = _campaign.first_level()
	# Jumping straight to a level should still follow its campaign afterwards.
	if _campaign == null:
		_campaign = Data.campaign_for_level(first)
	load_level(first)


## Clears the board and starts `level_id`.
func load_level(level_id: StringName) -> void:
	var level := Data.level(level_id)
	if level.is_empty():
		_status.text = "Level '%s' not found" % level_id
		push_warning("Main: unknown level '%s'" % level_id)
		return

	_current_level = level_id
	_transitioning = false
	_autosave_timer = autosave_interval
	board.shovel_active = false
	board.plant_food_active = false
	board.reset()
	runner.start(level, board)

	# A part-played level resumes where it was left rather than restarting.
	if resume_saves and Saves.has_save(level_id):
		var save := Saves.load_save(level_id)
		if Saves.restore(save, runner, board, seed_bank):
			print("[save] resumed '%s' from %s"
					% [level_id, save.get("saved_at", "an earlier session")])

	_status.text = ""
	_wave_label.text = ""
	_refresh_mode_label()
	_level_label.text = _level_title(level)
	_refresh_ability_label()


func _level_title(level: Dictionary) -> String:
	# The world's own name, which a pack can rename without touching levels.
	var world := runner.world_name()
	var title := str(level.get("comment", level.get("name", _current_level)))
	if world != "":
		title = "%s - %s" % [world, title]
	if _campaign != null:
		var i := _campaign.index_of(_current_level)
		if i >= 0:
			return "%s  -  %d / %d" % [title, i + 1, _campaign.levels.size()]
	return title


func _build_hud() -> void:
	var layer := CanvasLayer.new()
	add_child(layer)

	var root := VBoxContainer.new()
	root.position = Vector2(20, 16)
	layer.add_child(root)

	var top := HBoxContainer.new()
	top.add_theme_constant_override("separation", 24)
	root.add_child(top)

	_sun_label = _make_label("Sun: 50")
	top.add_child(_sun_label)
	_plant_food_label = _make_label("Food: 0")
	top.add_child(_plant_food_label)
	_wave_label = _make_label("")
	top.add_child(_wave_label)
	_level_label = _make_label("")
	top.add_child(_level_label)
	_mode_label = _make_label("")
	top.add_child(_mode_label)
	_objective_label = _make_label("")
	root.add_child(_objective_label)
	_ability_label = _make_label("")
	root.add_child(_ability_label)
	_status = _make_label("")
	top.add_child(_status)

	_seed_bar = HBoxContainer.new()
	_seed_bar.add_theme_constant_override("separation", 8)
	root.add_child(_seed_bar)


func _make_label(text: String) -> Label:
	var l := Label.new()
	l.text = text
	l.add_theme_font_size_override("font_size", hud_font_size)
	l.add_theme_color_override("font_color", Color.WHITE)
	l.add_theme_color_override("font_shadow_color", Color(0, 0, 0, 0.8))
	l.add_theme_constant_override("shadow_offset_y", 2)
	return l


func _on_seedbank_ready(seeds: Array) -> void:
	# The bank owns cost and recharge; the buttons are just a view of it.
	_conveyor_level = runner.is_conveyor()
	_make_seed_bank(_conveyor_level)
	if _conveyor_level:
		seed_bank.setup_conveyor(runner.level.get("seedbank", {}))
	else:
		seed_bank.setup(seeds, runner.seed_recharge_scale() < 1.0)

	_rebuild_seed_buttons()


## Swaps in the bank this level needs. A conveyor belt and a chooser behave
## differently enough to be separate types rather than one with a mode flag.
func _make_seed_bank(conveyor: bool) -> void:
	if seed_bank != null:
		seed_bank.queue_free()
	seed_bank = ConveyorSeedBank.new() if conveyor else SeedBank.new()
	seed_bank.name = "SeedBank"
	add_child(seed_bank)
	seed_bank.changed.connect(_on_seed_bank_changed)
	board.seed_bank = seed_bank
	runner.seed_bank = seed_bank


## A chooser's slots are fixed, so its buttons only need restyling. A belt's
## packets come and go, so its buttons are rebuilt when the count changes.
func _on_seed_bank_changed() -> void:
	if seed_bank.slots_are_stable() and _seed_buttons.size() == seed_bank.size():
		_refresh_seed_buttons()
	else:
		_rebuild_seed_buttons()


func _rebuild_seed_buttons() -> void:
	for b in _seed_buttons:
		b.queue_free()
	_seed_buttons.clear()
	_seeds.clear()

	for slot in seed_bank.size():
		var packet := seed_bank.packet(slot)
		var b := Button.new()
		# Show the hotkey on the packet so the binding is discoverable.
		var key := "%d  " % (slot + 1)
		b.text = "%s%s\n%d" % [key, String(packet.id).capitalize(), packet.cost]
		b.custom_minimum_size = seed_button_size
		b.focus_mode = Control.FOCUS_NONE
		b.pressed.connect(_select_seed.bind(slot))
		_seed_bar.add_child(b)
		_seed_buttons.append(b)
		_seeds.append({"kind": packet.kind, "id": packet.id, "slot": slot})
	_refresh_seed_buttons()


## The action for a seed slot. Conveyor levels have more slots and their own
## bindings from slot 5 onward, so the layout depends on the seed bank mode.
func _slot_action(slot: int) -> StringName:
	var n := slot + 1
	if _conveyor_level and n >= 5:
		return StringName("Slot %d (Convayor)" % n)
	return StringName("Slot %d" % n)


func _action_pressed(event: InputEvent, action: StringName) -> bool:
	# Guarded: an unbound or missing action must not spam errors.
	return InputMap.has_action(action) and event.is_action_pressed(action)


## Seed slots, shovel and fast forward all come from the project's InputMap,
## so they can be rebound - including to a controller - without code changes.
func _unhandled_input(event: InputEvent) -> void:
	if event is InputEventMouseMotion:
		return

	if _action_pressed(event, &"Lawn Ability"):
		if not board.activate_lawn_ability(0):
			Audio.play(&"lawn.ability.refuse")
		_refresh_ability_label()
		get_viewport().set_input_as_handled()
		return
	if _action_pressed(event, &"Plant Food"):
		_toggle_plant_food()
		get_viewport().set_input_as_handled()
		return
	if _action_pressed(event, &"Shovel"):
		_toggle_shovel()
		get_viewport().set_input_as_handled()
		return
	if _action_pressed(event, &"Fast Forward"):
		_toggle_fast_forward()
		get_viewport().set_input_as_handled()
		return
	if _action_pressed(event, &"Previous Slot"):
		_step_slot(-1)
		get_viewport().set_input_as_handled()
		return
	if _action_pressed(event, &"Next Slot"):
		_step_slot(1)
		get_viewport().set_input_as_handled()
		return

	for slot in _seeds.size():
		if _action_pressed(event, _slot_action(slot)):
			_select_seed(slot)
			get_viewport().set_input_as_handled()
			return

	if event is InputEventKey and event.pressed and not event.echo \
			and event.keycode == KEY_ESCAPE:
		_select_seed(-1)
		board.shovel_active = false
		get_viewport().set_input_as_handled()


## Cycles the selection, skipping packets that have not recharged. Bound to
## Previous/Next Slot, which are reserved for controller shoulder buttons.
func _step_slot(step: int) -> void:
	if _seeds.is_empty():
		return
	var start: int = board.selected_seed.get("slot", -1)
	for i in _seeds.size():
		var next := posmod(start + step * (i + 1), _seeds.size())
		if seed_bank.is_recharged(next):
			_select_seed(next)
			return


func _toggle_shovel() -> void:
	board.shovel_active = not board.shovel_active
	if board.shovel_active:
		board.plant_food_active = false
		board.selected_seed = {}
	_refresh_seed_buttons()
	_refresh_mode_label()


## Arms plant food. The next click on a plant feeds it, if there is any left.
func _toggle_plant_food() -> void:
	if board.plant_food <= 0:
		board.plant_food_active = false
		_refresh_mode_label()
		return
	board.plant_food_active = not board.plant_food_active
	if board.plant_food_active:
		board.shovel_active = false
		board.selected_seed = {}
	_refresh_seed_buttons()
	_refresh_mode_label()


func _on_plant_food_changed(total: int) -> void:
	_plant_food_label.text = "Food: %d" % total
	if total <= 0:
		board.plant_food_active = false
	_refresh_mode_label()


func _toggle_fast_forward() -> void:
	_fast_forward = not _fast_forward
	Engine.time_scale = fast_forward_scale if _fast_forward else 1.0
	_refresh_mode_label()


func _refresh_mode_label() -> void:
	var bits := []
	if board.plant_food_active:
		bits.append("Plant Food")
	if board.shovel_active:
		bits.append("Shovel")
	if _fast_forward:
		bits.append("x%.1f" % fast_forward_scale)
	_mode_label.text = "  ".join(bits)


## Selects a seed slot, or clears the selection when `slot` is out of range.
## Selecting the slot that is already active clears it, so a hotkey toggles.
func _select_seed(slot: int) -> void:
	# A packet that has not recharged cannot be selected at all.
	if slot >= 0 and slot < _seeds.size() and not seed_bank.is_recharged(slot):
		Audio.play(&"ui.seed.refuse")
		return
	if slot >= 0:
		Audio.play(&"ui.seed.select")
	if slot < 0 or slot >= _seeds.size():
		board.selected_seed = {}
	elif board.selected_seed == _seeds[slot]:
		board.selected_seed = {}     # re-pressing the same slot deselects
	else:
		board.selected_seed = _seeds[slot].duplicate()
	_refresh_seed_buttons()


func _on_sun_changed(total: int) -> void:
	_sun_label.text = "Sun: %d" % total
	_refresh_seed_buttons()


## Shows each packet's state: recharging, unaffordable, ready, or selected.
func _refresh_seed_buttons() -> void:
	for i in _seed_buttons.size():
		var packet := seed_bank.packet(i)
		var b := _seed_buttons[i]
		if packet == null:
			continue
		var charged := packet.is_recharged()
		var affordable := board.sun >= packet.cost
		b.disabled = not (charged and affordable)

		if board.selected_seed.get("slot", -1) == i:
			b.modulate = Color(0.7, 1.0, 0.7)
		elif not charged:
			# Darkened in proportion to how much recharge is left, so the
			# packet visibly fills up.
			b.modulate = Color.WHITE.darkened(0.55 * (1.0 - packet.fraction()))
		elif not affordable:
			b.modulate = Color(0.75, 0.75, 0.75)
		else:
			b.modulate = Color.WHITE


func _on_objectives_changed(_objectives: Array) -> void:
	_objective_label.text = "   ".join(runner.objective_lines())


func _on_lawn_ability_changed(_component: LawnComponent) -> void:
	_refresh_ability_label()


## Shows the world's own behaviours, abilities first with their charge.
func _refresh_ability_label() -> void:
	var bits: Array[String] = []
	for c in board.lawn_components:
		var text := c.describe()
		if text == "":
			continue
		if c.is_ability:
			bits.append("[G] %s" % text if c.can_activate() else text)
		else:
			bits.append(text)
	_ability_label.text = "   ".join(bits)


## A broken objective loses the level, and names which rule broke.
func _on_objective_failed(objective: Objective) -> void:
	if _transitioning:
		return
	var text := objective.describe()
	_on_lost()
	_status.text = "Objective failed: %s" % (text if text != "" else objective.name)


func _on_wave_started(index: int, total: int) -> void:
	_wave_label.text = "Wave %d / %d" % [index, total]


func _process(delta: float) -> void:
	if not runner.running or _transitioning or autosave_interval <= 0.0:
		return
	_autosave_timer -= delta
	if _autosave_timer > 0.0:
		return
	_autosave_timer = autosave_interval
	Saves.save_level(runner, board, seed_bank)


func _on_won() -> void:
	if _transitioning:
		return
	_transitioning = true
	runner.stop()
	# Clearing a level ends its run, which retires its save slot.
	Saves.mark_cleared(_current_level)
	_play_ending(&"victory", &"level.win")

	if _campaign == null or _campaign.is_last(_current_level):
		_status.text = (_campaign.completion_message if _campaign != null
				else "Level complete!")
		return

	var next := _campaign.next_after(_current_level)
	_status.text = "Level complete!"
	_advance_after(level_transition_delay, next)


func _on_lost() -> void:
	if _transitioning:
		return
	_transitioning = true
	runner.stop()
	# A failed run is not worth resuming; the retry starts the level over.
	Saves.clear_save(_current_level)
	Audio.stop_music()
	_play_ending(&"lose", &"level.lose")
	_status.text = "The zombies ate your brains!"
	_advance_after(retry_delay, _current_level)


## Loads `level_id` after a pause, so the result is readable first.
## The tree is never paused here - that would stop the timer too.
func _advance_after(delay: float, level_id: StringName) -> void:
	await get_tree().create_timer(delay).timeout
	if is_inside_tree():
		load_level(level_id)


## Ends the level with its world's music, falling back to the plain cue.
##
## Winning and losing are scored, not sound-effected: PVZGE keeps VIC_, LOSE_
## and LEAVE_ in its music enum beside the stage loops, so they are routed as
## music here and a world can end its own way.
func _play_ending(kind: StringName, fallback: StringName) -> void:
	var cue: StringName = runner.music_cue(kind) if runner != null else &""
	if cue != &"":
		Audio.play_music(cue)
	else:
		Audio.play(fallback)
