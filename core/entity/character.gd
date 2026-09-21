class_name Character
extends Node2D
## Shared base for plants and zombies: grid position, health, damage, and the
## component list built from an EntityDef.
##
## This is the inheritance half of the model and deliberately stays thin. It
## owns only what every board entity has - where it is, how much health it has,
## and how it dies. Anything an entity *does* belongs in a component.

signal died(who: Character)
signal damaged(who: Character, amount: float, remaining: float)
signal tag_changed(who: Character, tag: StringName, present: bool)

@export var row: int = 0
@export var col: int = 0

var def: EntityDef
var board: Node = null
var health: float = 0.0
var max_health: float = 0.0
var is_dead: bool = false

var _components: Array[EntityComponent] = []
var _runtime_tags: Dictionary = {}   ## tags added or removed after spawn


## Build this entity from a definition. Called once, right after instancing.
func initialize(entity_def: EntityDef, owning_board: Node) -> void:
	def = entity_def
	board = owning_board
	max_health = float(def.stat(&"toughness", 100.0))
	health = max_health
	_spawn_components()
	_on_initialized()


func _spawn_components() -> void:
	for spec in def.components:
		var comp := Components.create(spec, self)
		if comp == null:
			continue
		add_child(comp)
		_components.append(comp)
		comp.setup()


## Hook for subclasses; runs after components exist.
func _on_initialized() -> void:
	pass


# --- tags ----------------------------------------------------------------

## Tags come from the definition, with runtime overrides layered on top, so a
## status effect can grant or strip a capability without mutating shared data.
func has_tag(tag: StringName) -> bool:
	if _runtime_tags.has(tag):
		return _runtime_tags[tag]
	return def != null and def.has_tag(tag)


func set_runtime_tag(tag: StringName, present: bool) -> void:
	if has_tag(tag) == present:
		return
	_runtime_tags[tag] = present
	tag_changed.emit(self, tag, present)


func clear_runtime_tag(tag: StringName) -> void:
	if _runtime_tags.erase(tag):
		tag_changed.emit(self, tag, has_tag(tag))


func matches(required: Array, excluded: Array = []) -> bool:
	for t in required:
		if not has_tag(StringName(t)):
			return false
	for t in excluded:
		if has_tag(StringName(t)):
			return false
	return true


# --- health --------------------------------------------------------------

func take_damage(amount: float, _source: Node = null) -> void:
	if is_dead or amount <= 0.0:
		return
	# Armor components absorb first and may reduce what reaches the body.
	for comp in _components:
		if comp.has_method("absorb_damage"):
			amount = float(comp.absorb_damage(amount))
			if amount <= 0.0:
				return
	health = maxf(0.0, health - amount)
	damaged.emit(self, amount, health)
	queue_redraw()
	if health <= 0.0:
		die()


func heal(amount: float) -> void:
	if is_dead:
		return
	health = minf(max_health, health + amount)
	queue_redraw()


func die() -> void:
	if is_dead:
		return
	is_dead = true
	died.emit(self)
	_on_death()
	queue_redraw()


func _on_death() -> void:
	queue_free()


func health_fraction() -> float:
	return health / max_health if max_health > 0.0 else 0.0


# --- components ----------------------------------------------------------

## Feeds this entity. Returns true if any component responded, so the board
## only spends the food when it actually did something.
func apply_plant_food() -> bool:
	if is_dead:
		return false
	var used := false
	for c in _components:
		if c.on_plantfood():
			used = true
	if used:
		queue_redraw()
	return used


func component(type: StringName) -> EntityComponent:
	for c in _components:
		if StringName(c.name) == type:
			return c
	return null


func components() -> Array[EntityComponent]:
	return _components


func entity_id() -> StringName:
	return def.id if def else &""
