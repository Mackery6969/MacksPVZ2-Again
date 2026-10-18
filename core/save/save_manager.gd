extends Node
## Per-level save states and campaign progress.
##
## PvZ2 lets you leave a level and come back to it mid-run; PVZGE does not.
## Each level gets its own slot, so several can be part-played at once.
##
## The objects describe themselves - Board, LevelRunner, SeedBank, each
## objective and lawn component all have their own snapshot - so this only
## composes them and handles files. Adding something that needs remembering
## means giving it a `save_state`, not editing this.
##
## Registered as an autoload singleton named `Saves`.

signal level_saved(level_id: StringName)
signal level_loaded(level_id: StringName)
signal progress_changed

const SAVE_DIR := "user://saves"
const PROGRESS_FILE := "user://saves/progress.json"
const FORMAT_VERSION := 1

var _progress: Dictionary = {}


func _ready() -> void:
	DirAccess.make_dir_recursive_absolute(SAVE_DIR)
	_load_progress()


# --- level slots ---------------------------------------------------------

func slot_path(level_id: StringName) -> String:
	return SAVE_DIR.path_join("level_%s.json" % level_id)


func has_save(level_id: StringName) -> bool:
	return FileAccess.file_exists(slot_path(level_id))


## Everything needed to resume this level.
func capture(runner: Node, board: Node, seed_bank: Node = null) -> Dictionary:
	var data := {
		"version": FORMAT_VERSION,
		"saved_at": Time.get_datetime_string_from_system(),
		"level": runner.snapshot(),
		"board": board.snapshot(),
	}
	if seed_bank != null and seed_bank.has_method("snapshot"):
		data["seed_bank"] = seed_bank.snapshot()
	return data


func save_level(runner: Node, board: Node, seed_bank: Node = null) -> bool:
	var data := capture(runner, board, seed_bank)
	var level_id := StringName(data["level"].get("level_id", &""))
	if level_id == &"":
		push_warning("Saves: refusing to save a level with no id")
		return false
	var f := FileAccess.open(slot_path(level_id), FileAccess.WRITE)
	if f == null:
		push_warning("Saves: cannot write %s" % slot_path(level_id))
		return false
	f.store_string(JSON.stringify(data, "\t"))
	f.close()
	level_saved.emit(level_id)
	return true


func load_save(level_id: StringName) -> Dictionary:
	if not has_save(level_id):
		return {}
	var f := FileAccess.open(slot_path(level_id), FileAccess.READ)
	if f == null:
		return {}
	var parsed = JSON.parse_string(f.get_as_text())
	f.close()
	if not (parsed is Dictionary):
		push_warning("Saves: %s is not valid save data" % level_id)
		return {}
	if int(parsed.get("version", 0)) != FORMAT_VERSION:
		push_warning("Saves: %s is version %s, expected %d - ignoring"
				% [level_id, parsed.get("version"), FORMAT_VERSION])
		return {}
	return parsed


## Applies a save to a level that has already been started.
func restore(data: Dictionary, runner: Node, board: Node,
		seed_bank: Node = null) -> bool:
	if data.is_empty():
		return false
	# Board first: the runner's objectives inspect the lawn as they restore.
	board.apply_snapshot(data.get("board", {}))
	if seed_bank != null and seed_bank.has_method("apply_snapshot"):
		seed_bank.apply_snapshot(data.get("seed_bank", []))
	runner.apply_snapshot(data.get("level", {}))
	level_loaded.emit(StringName(data.get("level", {}).get("level_id", &"")))
	return true


func clear_save(level_id: StringName) -> void:
	if has_save(level_id):
		DirAccess.remove_absolute(slot_path(level_id))


## Levels with a save in progress.
func saved_levels() -> Array[StringName]:
	var out: Array[StringName] = []
	var dir := DirAccess.open(SAVE_DIR)
	if dir == null:
		return out
	dir.list_dir_begin()
	var name := dir.get_next()
	while name != "":
		if name.begins_with("level_") and name.ends_with(".json"):
			out.append(StringName(name.substr(6, name.length() - 11)))
		name = dir.get_next()
	dir.list_dir_end()
	out.sort()
	return out


# --- campaign progress --------------------------------------------------

func mark_cleared(level_id: StringName) -> void:
	# Finishing a level ends its run, so the part-played state goes with it -
	# done first, because a level cleared twice still has a slot to retire.
	clear_save(level_id)
	var cleared: Array = _progress.get("cleared", [])
	if cleared.has(String(level_id)):
		return
	cleared.append(String(level_id))
	_progress["cleared"] = cleared
	_save_progress()
	progress_changed.emit()


func is_cleared(level_id: StringName) -> bool:
	return (_progress.get("cleared", []) as Array).has(String(level_id))


func cleared_count() -> int:
	return (_progress.get("cleared", []) as Array).size()


func reset_progress() -> void:
	_progress = {}
	for level_id in saved_levels():
		clear_save(level_id)
	_save_progress()
	progress_changed.emit()


func _load_progress() -> void:
	if not FileAccess.file_exists(PROGRESS_FILE):
		_progress = {}
		return
	var f := FileAccess.open(PROGRESS_FILE, FileAccess.READ)
	var parsed = JSON.parse_string(f.get_as_text())
	f.close()
	_progress = parsed if parsed is Dictionary else {}


func _save_progress() -> void:
	var f := FileAccess.open(PROGRESS_FILE, FileAccess.WRITE)
	if f == null:
		push_warning("Saves: cannot write progress")
		return
	f.store_string(JSON.stringify(_progress, "\t"))
	f.close()


func summary() -> String:
	return "saves: %d level(s) in progress, %d cleared" % [
			saved_levels().size(), cleared_count()]
