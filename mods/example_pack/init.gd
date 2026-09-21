extends RefCounted
## Optional startup hook, run after every pack's data has loaded.
##
## Use it for setup that data files cannot express - registering components
## generated at runtime, patching definitions, or reacting to what else is
## installed.

func initialize(ctx: Dictionary) -> void:
	var mod: Dictionary = ctx["mod"]
	var data = ctx["data"]
	print("[%s] init: %d zombies and %d plants visible"
			% [mod["id"], data.zombies.size(), data.plants.size()])

	# Data loaded by this pack is queryable like any other.
	var fast = data.query(&"zombie", [&"fast"])
	print("[%s] zombies tagged 'fast': %d" % [mod["id"], fast.size()])
