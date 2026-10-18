class_name Objective
extends Node
## A level's win or lose rule.
##
## Objectives are to levels what components are to entities: named, data
## configured, and replaceable by a mod. A level lists the objectives it uses;
## the runner asks each one whether it is met or failed rather than deciding
## for itself. That is what lets a pack add "don't lose a plant", "produce
## 2000 sun" or an entirely new goal without touching the runner.
##
## A pack ships one as `objectives/<type>.gd`; the file name is the type.

## Emitted when this objective's state changes, so a HUD can follow it.
signal progress_changed(objective: Objective)

var runner: Node = null        ## the LevelRunner
var board: Node = null
var config: Dictionary = {}    ## this objective's entry from the level

## True once the rule can no longer be satisfied.
var failed: bool = false


## Called once after `runner`, `board` and `config` are set.
func setup() -> void:
	pass


func cfg(key: StringName, fallback: Variant = null) -> Variant:
	return config.get(key, fallback)


## Whether the player has satisfied this objective. A level is won when every
## objective is met.
func is_met() -> bool:
	return true


## Whether the objective has been broken. Any failed objective loses the level.
func is_failed() -> bool:
	return failed


## Human-readable state for the HUD, e.g. "Sun produced 450 / 2000".
func describe() -> String:
	return ""


func fail() -> void:
	if failed:
		return
	failed = true
	progress_changed.emit(self)


func notify_progress() -> void:
	progress_changed.emit(self)


## What this objective needs remembered across a save. Objectives that track
## progress override both of these; the rest need nothing.
func save_state() -> Dictionary:
	return {}


func load_state(_state: Dictionary) -> void:
	pass


# --- optional hooks ------------------------------------------------------
# The runner calls these when they happen, so an objective does not have to
# poll the board every frame.

func on_wave_started(_index: int, _total: int) -> void:
	pass


func on_all_waves_spawned() -> void:
	pass


func on_zombie_died(_zombie: Node) -> void:
	pass


func on_plant_died(_plant: Node) -> void:
	pass


func on_sun_collected(_amount: int) -> void:
	pass


func on_zombie_reached_house(_zombie: Node) -> void:
	pass
