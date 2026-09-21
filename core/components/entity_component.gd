class_name EntityComponent
extends Node
## Base class for every behaviour attached to a plant or zombie.
##
## Components are the composition half of the entity model: a Character owns
## its position, health and lane, while everything it *does* - shooting,
## producing sun, eating, exploding - is a component added as a child node.
##
## A mod replaces a behaviour by registering its own script under an existing
## component type name; nothing else in the game needs to know.

var host: Node = null          ## the Character this is attached to
var config: Dictionary = {}    ## the component's entry from the entity JSON


## Called once after the component is attached and `host`/`config` are set.
## Override instead of `_ready` so setup order is guaranteed.
func setup() -> void:
	pass


## Called when the player feeds this entity plant food. Return true if the
## component did something, so the food is only spent when it has an effect.
## Components that have no boosted behaviour simply do not override this.
func on_plantfood() -> bool:
	return false


func cfg(key: StringName, fallback: Variant = null) -> Variant:
	return config.get(key, fallback)


## Config value with a random jitter applied, for the common
## `interval` / `interval_jitter` pairing.
func cfg_jittered(key: StringName, jitter_key: StringName, fallback: float = 0.0) -> float:
	var base := float(config.get(key, fallback))
	var jitter := float(config.get(jitter_key, 0.0))
	return base + (randf() * 2.0 - 1.0) * jitter if jitter > 0.0 else base
