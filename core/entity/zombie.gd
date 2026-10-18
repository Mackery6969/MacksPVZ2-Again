class_name Zombie
extends Character
## A zombie walks along its lane, stopping to attack whatever blocks it.
##
## Allegiance decides both direction and prey. A hostile zombie walks left and
## eats plants; a charmed one (hypnotised, zomboid) walks right and attacks
## hostile zombies. Keeping this on the zombie rather than in a separate class
## means charming is a runtime state change, not a respawn.

signal reached_house(who: Zombie)
signal allegiance_changed(who: Zombie, allegiance: Allegiance)

enum Allegiance {
	HOSTILE,  ## the default: eats plants, walks toward the house
	CHARMED,  ## hypnotised: attacks hostile zombies, walks away from the house
}

@export_group("Allegiance")
@export var allegiance: Allegiance = Allegiance.HOSTILE

@export_group("Appearance")
@export var body_size := Vector2(44, 68)
@export var body_color: Color = Color("9aa6b2")
@export var metal_color: Color = Color("b9c2cc")
@export var charmed_color: Color = Color("b98ac6")
@export var head_color: Color = Color("d8cfa8")
@export var health_bar_color: Color = Color("d46a6a")
@export var frozen_color: Color = Color("8fc7e8")
@export var slowed_color: Color = Color("7f9bb5")
@export var armor_color: Color = Color("c98a3e")
@export var armor_metal_color: Color = Color("aeb6bf")

## Stats are filled from the entity definition on spawn; these are fallbacks
## used when a definition omits them.
@export_group("Fallback stats")
@export var speed: float = 0.5        ## squares per second
@export var eat_dps: float = 100.0

var target: Character = null

var _eat_accumulator: float = 0.0
## Status effects, as remaining seconds. A slow also stores its factor so the
## original speed can be restored exactly rather than approximately.
var _stun_left: float = 0.0
var _slow_left: float = 0.0
var _slow_factor: float = 1.0
var _base_speed: float = 0.0
## reached_house fires once; the board decides what happens next.
var _announced_house: bool = false


func _on_initialized() -> void:
	speed = float(def.stat(&"speed", speed))
	eat_dps = float(def.stat(&"eat_dps", eat_dps))
	_base_speed = speed
	queue_redraw()


# --- allegiance ----------------------------------------------------------

func is_charmed() -> bool:
	return allegiance == Allegiance.CHARMED


## Hypnotises this zombie so it fights for the player.
func charm() -> void:
	set_allegiance(Allegiance.CHARMED)


func set_allegiance(value: Allegiance) -> void:
	if allegiance == value:
		return
	allegiance = value
	target = null            # whatever it was chasing is no longer its enemy
	set_runtime_tag(&"charmed", value == Allegiance.CHARMED)
	allegiance_changed.emit(self, value)
	queue_redraw()


## -1 walking toward the house, +1 walking away from it.
func direction() -> int:
	return 1 if is_charmed() else -1


# --- status effects ------------------------------------------------------

## Halts the zombie entirely for `seconds`. Freezing is a stun that also
## chills, so both routes end up here.
func apply_stun(seconds: float) -> void:
	_stun_left = maxf(_stun_left, seconds)
	set_runtime_tag(&"stunned", true)
	queue_redraw()


## Scales speed by `factor` (0.5 = half speed) for `seconds`. Re-applying takes
## whichever is stronger and whichever lasts longer, so effects do not stack
## into a standstill.
func apply_slow(factor: float, seconds: float) -> void:
	_slow_factor = minf(_slow_factor if _slow_left > 0.0 else 1.0,
			clampf(factor, 0.05, 1.0))
	_slow_left = maxf(_slow_left, seconds)
	speed = _base_speed * _slow_factor
	set_runtime_tag(&"slowed", true)
	queue_redraw()


## Chilled and held in place at once, the usual effect of an ice plant.
func apply_freeze(seconds: float) -> void:
	apply_stun(seconds)
	apply_slow(0.5, seconds * 2.0)
	set_runtime_tag(&"frozen", true)


func is_stunned() -> bool:
	return _stun_left > 0.0


func _tick_status(delta: float) -> void:
	if _stun_left > 0.0:
		_stun_left -= delta
		if _stun_left <= 0.0:
			set_runtime_tag(&"stunned", false)
			set_runtime_tag(&"frozen", false)
			queue_redraw()
	if _slow_left > 0.0:
		_slow_left -= delta
		if _slow_left <= 0.0:
			_slow_factor = 1.0
			speed = _base_speed
			set_runtime_tag(&"slowed", false)
			queue_redraw()


func _process(delta: float) -> void:
	super(delta)
	if is_dead or board == null:
		return
	_tick_status(delta)
	# A stunned zombie neither walks nor eats.
	if is_stunned():
		return
	if is_instance_valid(target) and not target.is_dead:
		_attack(delta)
	else:
		target = null
		_walk(delta)


func _walk(delta: float) -> void:
	position.x += direction() * speed * board.cell_size.x * delta
	col = board.world_to_col(position.x)

	var ahead := _find_target()
	if ahead != null:
		target = ahead
		_eat_accumulator = 0.0

	if is_charmed():
		# A charmed zombie that walks off the lawn has done its job.
		if position.x > board.despawn_x():
			queue_free()
	elif position.x < board.house_x():
		# Stop on the threshold rather than removing itself: a lawn mower may
		# still be waiting there, and it needs something to catch.
		position.x = board.house_x()
		if not _announced_house:
			_announced_house = true
			reached_house.emit(self)
	queue_redraw()


## What this zombie should attack next, if anything is in reach.
func _find_target() -> Character:
	if is_charmed():
		# Charmed zombies fight the nearest hostile zombie in the lane.
		for z in board.hostile_zombies_in_row(row):
			if absf(z.position.x - position.x) <= board.cell_size.x * 0.5:
				return z
		return null

	var plant: Plant = board.plant_at(row, col)
	if plant != null and not plant.is_dead and _can_eat(plant):
		return plant
	# Graves and objects do not block a zombie, so nothing else is checked.
	return null


## A zombie only eats plants it is allowed to; a mod can block this by
## granting the plant a tag this zombie excludes.
func _can_eat(plant: Plant) -> bool:
	return not plant.has_tag(&"uneatable")


func _attack(delta: float) -> void:
	_eat_accumulator += eat_dps * delta
	var whole := floorf(_eat_accumulator)
	if whole >= 1.0:
		_eat_accumulator -= whole
		target.take_damage(whole, self)


## A cone sitting on the head, so an armored zombie reads at a glance. It
## shrinks as the armor is chewed through and disappears when it breaks.
func _draw_armor(head: Vector2) -> void:
	var armor := component(&"armor")
	if armor == null or not armor.is_intact():
		return
	var wear: float = 0.35 + 0.65 * armor.fraction()
	var half := 12.0
	var tip := head + Vector2(0, -12.0 - 12.0 * wear)
	var points := PackedVector2Array([
		Vector2(head.x - half, head.y - 6.0),
		Vector2(head.x + half, head.y - 6.0),
		tip,
	])
	var tint: Color = armor_metal_color if armor.is_metal else armor_color
	draw_colored_polygon(points, tint)
	draw_polyline(points + PackedVector2Array([points[0]]), tint.darkened(0.45), 2.0)


func _on_death() -> void:
	Audio.play(&"zombie.die", position)
	super()


func _draw() -> void:
	var size := body_size
	var rect := Rect2(Vector2(-size.x * 0.5, -size.y * 0.75), size)
	var body := body_color
	if is_charmed():
		body = charmed_color
	elif has_tag(&"frozen"):
		body = frozen_color
	elif has_tag(&"slowed"):
		body = slowed_color
	elif has_tag(&"metal"):
		body = metal_color
	draw_rect(rect, body, true)
	draw_rect(rect, body.darkened(0.45), false, 2.0)
	# Head offset shows which way it is facing.
	var head := Vector2(6 * direction(), -size.y * 0.75 - 10)
	draw_circle(head, 11.0, head_color)
	_draw_armor(head)

	if health < max_health:
		var bar := Rect2(Vector2(-size.x * 0.5, -size.y * 0.75 - 34), Vector2(size.x, 4))
		draw_rect(bar, Color(0, 0, 0, 0.5), true)
		bar.size.x *= health_fraction()
		draw_rect(bar, health_bar_color, true)
