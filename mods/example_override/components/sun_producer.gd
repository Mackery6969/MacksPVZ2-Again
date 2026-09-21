extends EntityComponent
## Replaces the built-in sun_producer outright.
##
## This file is named `sun_producer.gd`, the same as the core component, so the
## loader registers it over the original. Every plant that uses the
## `sun_producer` component now runs THIS code instead - no plant JSON and no
## core file had to change. This is how a pack completely rewrites what an
## existing plant does.
##
## This pack ships disabled, because an override of a core behaviour changes
## the base game for every plant that uses it. That is exactly the power being
## demonstrated, and exactly why it should be opt-in.
##
## Behaviour change: produces four times as fast as the data asks, and drops a
## second sun while the plant is above half health.

var interval: float = 8.0

var _timer: float = 0.0


func setup() -> void:
	# Deliberately ignores the data's slow interval to prove the override runs.
	interval = float(cfg(&"interval", 24.0)) * 0.25
	_timer = interval


func _process(delta: float) -> void:
	if host.is_dead:
		return
	_timer -= delta
	if _timer > 0.0:
		return
	host.board.drop_sun(host.position)
	if host.health_fraction() > 0.5:
		host.board.drop_sun(host.position + Vector2(18, 0))
	_timer = interval
