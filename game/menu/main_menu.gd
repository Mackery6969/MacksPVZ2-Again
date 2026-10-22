class_name MainMenu
extends Control
## The title screen: play, continue a part-played level, settings, quit.
##
## It never loads anything itself - it asks the App, which owns which screen
## is showing.

signal play_requested
signal continue_requested(level_id: StringName)
signal quit_requested

const BACKGROUND := Color(0.16, 0.3, 0.14)

var _settings: SettingsMenu


func _ready() -> void:
	set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	add_child(MenuUI.backdrop(BACKGROUND))

	var center := CenterContainer.new()
	center.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	add_child(center)
	var stack := VBoxContainer.new()
	stack.add_theme_constant_override("separation", 14)
	center.add_child(stack)

	var title := MenuUI.label(String(ProjectSettings.get_setting(
			"application/config/name", "PVZ2")), MenuUI.TITLE_SIZE)
	title.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	stack.add_child(title)
	var spacer := Control.new()
	spacer.custom_minimum_size.y = 24
	stack.add_child(spacer)

	var play := MenuUI.button("Play", play_requested.emit)
	play.name = "Play"
	stack.add_child(play)

	var resume := latest_save()
	if resume != &"":
		var b := MenuUI.button("Continue: %s" % level_name(resume),
				continue_requested.emit.bind(resume))
		b.name = "Continue"
		stack.add_child(b)

	stack.add_child(MenuUI.button("Settings", _open_settings))
	# The web build has nothing to quit to.
	if OS.get_name() != "Web":
		stack.add_child(MenuUI.button("Quit", quit_requested.emit))

	var mods := Data.mod_order().size() - 1    # "base" is not a mod
	var footer := MenuUI.label("Unofficial fan work - not affiliated with "
			+ "PopCap Games or Electronic Arts.    %d mod(s) enabled" % mods, 14)
	footer.modulate.a = 0.7
	footer.set_anchors_and_offsets_preset(Control.PRESET_BOTTOM_WIDE)
	footer.offset_top = -32
	footer.offset_left = 16
	add_child(footer)

	(stack.get_node("Continue") if stack.has_node("Continue") else play) \
			.grab_focus.call_deferred()
	MenuUI.music(&"music.menu")


## The part-played level saved most recently, or &"" when there is none.
static func latest_save() -> StringName:
	var best := &""
	var best_time := -1
	for level_id in Saves.saved_levels():
		if Data.level(level_id).is_empty():
			continue    # left behind by a mod that is no longer enabled
		var t := FileAccess.get_modified_time(Saves.slot_path(level_id))
		if t > best_time:
			best_time = t
			best = level_id
	return best


static func level_name(level_id: StringName) -> String:
	var level := Data.level(level_id)
	return str(level.get("name", level_id))


func _open_settings() -> void:
	if _settings != null:
		return
	_settings = SettingsMenu.new()
	_settings.closed.connect(_on_settings_closed)
	add_child(_settings)


## Settings can reset progress, which takes the saved level with it.
func _on_settings_closed() -> void:
	_settings = null
	var resume := find_child("Continue", true, false)
	if resume != null and latest_save() == &"":
		resume.queue_free()
		(find_child("Play", true, false) as Button).grab_focus()
