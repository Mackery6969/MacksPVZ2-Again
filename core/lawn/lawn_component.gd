class_name LawnComponent
extends Node
## A behaviour belonging to the lawn rather than to any entity.
##
## Some worlds do things the board itself has to do: Aerial Fortress style
## turret fire, tides, moving platforms, a world-specific ability the player
## can trigger. Those have nowhere to live on a plant or a zombie, so a lawn
## carries its own components, registered and overridable exactly like entity
## components and objectives.
##
## A pack ships one as `lawn_components/<type>.gd`; the file name is the type.
##
## A component that sets `is_ability` is player-triggered and appears in the
## HUD with its cooldown; otherwise it just runs.

signal state_changed(component: LawnComponent)

var board: Node = null
var runner: Node = null
var config: Dictionary = {}

## True when the player triggers this rather than it running on its own.
var is_ability: bool = false


## Called once after `board`, `runner` and `config` are set.
func setup() -> void:
	pass


func cfg(key: StringName, fallback: Variant = null) -> Variant:
	return config.get(key, fallback)


# --- ability interface ---------------------------------------------------
# Only meaningful when `is_ability` is true.

## Whether the player may trigger it right now.
func can_activate() -> bool:
	return false


## Trigger it. Returns true if it actually fired, so the HUD can refuse
## silently rather than pretending.
func activate() -> bool:
	return false


## 0 while fully charged, rising to 1 right after use - for a HUD meter.
func cooldown_fraction() -> float:
	return 0.0


## Short label for the HUD, e.g. "Cannon ready".
func describe() -> String:
	return ""


func notify_state() -> void:
	state_changed.emit(self)


# --- threshold handling --------------------------------------------------

## A zombie has reached the house. Return true to consume it, which stops the
## board from falling through to mowers and then to a loss.
##
## This is what lets a world replace the lose condition rather than decorate
## it: Sky has no mowers and a house with its own health, so it handles the
## zombie here and loses only when that health runs out.
func handle_zombie_at_house(_zombie: Node) -> bool:
	return false


# --- helpers -------------------------------------------------------------

## The nearest hostile zombie to the house, across every lane, or null.
func nearest_hostile() -> Node:
	var best: Node = null
	for row in board.rows:
		for z in board.hostile_zombies_in_row(row):
			if best == null or z.position.x < best.position.x:
				best = z
	return best


## Every hostile zombie on the board.
func all_hostiles() -> Array:
	var out: Array = []
	for row in board.rows:
		out.append_array(board.hostile_zombies_in_row(row))
	return out
