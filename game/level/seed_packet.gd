class_name SeedPacket
extends RefCounted
## Runtime state for one seed slot: what it plants, what it costs, and how far
## along its recharge is.

var kind: StringName = &"plant"
var id: StringName = &""
var cost: int = 0
## Seconds to recharge from empty.
var recharge: float = 5.0
## Seconds of charge accumulated, capped at `recharge`.
var charge: float = 0.0


static func create(seed_kind: StringName, seed_id: StringName, seed_cost: int,
		seconds: float, initial_fraction: float) -> SeedPacket:
	var p := SeedPacket.new()
	p.kind = seed_kind
	p.id = seed_id
	p.cost = seed_cost
	p.recharge = maxf(seconds, 0.0)
	# `cooldown_from` is how charged the packet starts: 1 is ready at once,
	# 0 means waiting the full recharge before first use.
	p.charge = p.recharge * clampf(initial_fraction, 0.0, 1.0)
	return p


func tick(delta: float) -> bool:
	if charge >= recharge:
		return false
	charge = minf(charge + delta, recharge)
	return true


func is_recharged() -> bool:
	return charge >= recharge


func fraction() -> float:
	return 1.0 if recharge <= 0.0 else clampf(charge / recharge, 0.0, 1.0)


func spend() -> void:
	charge = 0.0
