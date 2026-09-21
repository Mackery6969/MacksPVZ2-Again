class_name AudioBackend
extends RefCounted
## What an audio implementation has to provide.
##
## The game never talks to FMOD, or to Godot's audio servers, directly - it
## raises named events through `Audio`, and a backend decides what that means.
## Swapping backends is then a one-file change, and the game runs silently but
## correctly when no audio is installed at all.

## Human-readable name, shown in the boot log.
func backend_name() -> String:
	return "none"


## Whether this backend can run in the current project.
func is_available() -> bool:
	return true


func setup(_catalog: AudioCatalog) -> void:
	pass


## Fires a one-shot event. `position` is in world space for positional audio;
## backends that do not support it ignore it.
func play(_event: AudioEvent, _position: Variant = null) -> void:
	pass


func play_music(_event: AudioEvent) -> void:
	pass


func stop_music() -> void:
	pass


## Sets a global mix parameter, such as an intensity value driven by the wave.
func set_parameter(_name: StringName, _value: float) -> void:
	pass


func set_bus_volume(_bus: StringName, _linear: float) -> void:
	pass


func shutdown() -> void:
	pass
