extends Objective
## The default goal: outlast every wave.
##
## Met once the last wave has been spawned and no hostile zombie is left. This
## is the rule the runner used to hardcode.

var _spawned_all: bool = false


func on_all_waves_spawned() -> void:
	_spawned_all = true
	notify_progress()


func is_met() -> bool:
	return _spawned_all and board.zombie_count() == 0


func describe() -> String:
	if not _spawned_all:
		return "Survive the waves"
	var left: int = board.zombie_count()
	return "Clear the lawn" if left == 0 else "Zombies left: %d" % left
