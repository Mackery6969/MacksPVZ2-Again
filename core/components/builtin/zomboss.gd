extends EntityComponent
## Runs a staged boss fight: the only zombie whose whole behaviour is written
## down in the source data rather than hard-coded.
##
## A boss is a list of stages. Each has its own health pool and a weighted
## list of actions it picks from, so the fight gets both harder and busier as
## stages fall. Exhausting a stage's health does not kill the boss - it
## advances, through `prevent_death()`, so nothing outside this file knows a
## boss has stages.
##
## The eight action names are PopCap's. A mod adds a ninth by registering a
## script under `zomboss` or by overriding `_perform` in a subclass; the
## actions themselves are data, so a new world's boss needs no code at all
## unless it does something none of these cover.
##
## Config: missile, idle_column, mech_level, stages
##   [{health, idle, idle_max, stun_time, stun_damage_scale, stagger,
##     stagger_time, chill_from_freeze, anim_rate, actions, tuning}]

## Burst damage, as a fraction of the stage's pool, that staggers the boss.
## PopCap states how long a stagger lasts and what it costs the boss but not
## what earns one, so this is the threshold: hurt it hard and fast and it
## reels, which is what makes burst damage the counter to a boss.
const STAGGER_AT := 0.08
## How quickly accumulated damage is forgotten, as a fraction per second. A
## slow chip of damage never staggers anything.
const DAMAGE_DECAY := 0.5

## Lanes a rush crosses per second, and what it does to what it runs over.
const RUSH_SPEED := 2.5
const RUSH_DAMAGE := 400.0
## How far a summoned zombie lands from the boss, in lanes.
const SUMMON_OFFSET := 1.0

var stages: Array = []
var missile: StringName = &""
var idle_column: int = -1

var stage_index: int = 0
## The action being carried out, how many repeats are left of it, and the
## pause before the next one is picked.
var _action: Dictionary = {}
var _repeats_left: int = 0
var _idle_left: float = 0.0
## Rush state: lanes still to travel, and where it started.
var _rush_left: float = 0.0
var _struck: Array = []
## Stagger: a boss-only stun. It is not Zombie.apply_stun, because every boss
## in the data is flatly immune to being stunned by a plant - this is the
## stagger its own stage describes, earned by hurting it in a burst.
var _stagger_left: float = 0.0
var _shove_left: float = 0.0
var _recent_damage: float = 0.0


func setup() -> void:
	stages = cfg(&"stages", []) as Array
	missile = StringName(cfg(&"missile", &""))
	idle_column = int(cfg(&"idle_column", -1))
	if stages.is_empty():
		push_warning("zomboss: '%s' has no stages" % host.entity_id())
		return
	_enter_stage(0)


## A boss neither walks the lane nor bites: it holds its column and acts.
func claims_movement() -> bool:
	return true


func claims_attack() -> bool:
	return true


# --- stages --------------------------------------------------------------

func stage() -> Dictionary:
	if stage_index < 0 or stage_index >= stages.size():
		return {}
	return stages[stage_index]


func _enter_stage(index: int) -> void:
	stage_index = index
	var s := stage()
	host.max_health = float(s.get("health", host.max_health))
	host.health = host.max_health
	# Stun resistance and ice behaviour are per stage, so a later stage is
	# genuinely harder to hold still rather than only tougher.
	host.chill_override = float(s.get("chill_from_freeze", 0.0))
	host.set_runtime_tag(&"boss", true)
	host.set_runtime_tag(StringName("boss_stage_%d" % index), true)
	if idle_column >= 0:
		host.col = idle_column
		host.position.x = host.board.grid_to_world(host.row, idle_column).x
	_action = {}
	_repeats_left = 0
	_idle_left = _idle_time()
	host.queue_redraw()


## Called from `Character.die`: a boss with stages left advances instead.
func prevent_death() -> bool:
	if stage_index + 1 >= stages.size():
		return false
	Audio.play(&"zombie.boss.stage", host.position)
	_enter_stage(stage_index + 1)
	return true


func _idle_time() -> float:
	var s := stage()
	var low := float(s.get("idle", 1.0))
	var high := float(s.get("idle_max", low))
	return scaled(randf_range(low, maxf(high, low)))


# --- the action loop -----------------------------------------------------

func _process(delta: float) -> void:
	if host.is_dead or stages.is_empty():
		return
	_recent_damage = maxf(0.0, _recent_damage - _recent_damage * DAMAGE_DECAY * delta)
	if _stagger_left > 0.0:
		_stagger(delta)
		return
	if _rush_left > 0.0:
		_rush(delta)
		return
	if _idle_left > 0.0:
		_idle_left -= delta
		return
	if _repeats_left > 0:
		_repeats_left -= 1
		_perform(StringName(_action.get("action", &"")))
		_idle_left = _idle_time()
		return
	_pick_action()


## Interrupts whatever the boss was doing and shoves it backwards.
func stagger() -> void:
	if _stagger_left > 0.0:
		return
	_stagger_left = scaled(float(stage().get("stun_time", 0.0)))
	_shove_left = float(stage().get("stagger_time", 0.0))
	_rush_left = 0.0
	_struck = []
	_recent_damage = 0.0
	host.set_runtime_tag(&"rushing", false)
	host.set_runtime_tag(&"staggered", true)
	host.queue_redraw()


func is_staggered() -> bool:
	return _stagger_left > 0.0


## Shoved back over the stagger window - a fixed distance however long the
## stagger runs, so a long stagger is not also a long shove.
func _stagger(delta: float) -> void:
	_stagger_left -= delta
	if _shove_left > 0.0:
		var window := maxf(float(stage().get("stagger_time", 0.0)), 0.001)
		var lanes := float(stage().get("stagger", 0.0))
		var step: float = minf(_shove_left, delta) / window
		_shove_left -= delta
		host.position.x += lanes * host.board.cell_size.x * step
		host.col = host.board.world_to_col(host.position.x)
	if _stagger_left <= 0.0:
		host.set_runtime_tag(&"staggered", false)
		_idle_left = _idle_time()
	host.queue_redraw()


## Hooked for the same reason armor is: this is the one chance to change
## incoming damage before the body takes it. A staggered boss is wide open, so
## here it multiplies rather than absorbs - and enough damage at once is what
## earns the stagger in the first place.
func absorb_damage(amount: float) -> float:
	if _stagger_left > 0.0:
		return amount * float(stage().get("stun_damage_scale", 1.0))
	_recent_damage += amount
	if _recent_damage >= float(stage().get("health", 1.0)) * STAGGER_AT:
		stagger()
	return amount


## Weighted pick from the current stage. A weight of 0 is how the data retires
## an action in a later stage, so it has to be able to choose nothing.
func _pick_action() -> void:
	var actions: Array = stage().get("actions", [])
	var total := 0.0
	for a: Dictionary in actions:
		total += maxf(float(a.get("weight", 0)), 0.0)
	if total <= 0.0:
		_idle_left = _idle_time()
		return
	var roll := randf() * total
	for a: Dictionary in actions:
		roll -= maxf(float(a.get("weight", 0)), 0.0)
		if roll <= 0.0:
			_action = a
			var low := int(a.get("repeat", 1))
			_repeats_left = randi_range(low, maxi(int(a.get("repeat_max", low)), low))
			return
	_idle_left = _idle_time()


## Carries out one repetition of a named action. Unknown names idle rather
## than erroring, so a world whose special action is not implemented yet
## still fights with the rest of its list.
func _perform(action: StringName) -> void:
	match action:
		&"summon", &"imps":
			_summon()
		&"shoot":
			_shoot()
		&"walk", &"jump":
			_reposition(action == &"jump")
		&"rush", &"rush2":
			_begin_rush()
		&"roar":
			_roar()
		_:
			pass


## Spends a point budget on the action's zombie list, cheapest-first so a
## small budget still buys something. Wave cost is what PopCap prices a
## zombie at, and it is what the budget is denominated in.
func _summon() -> void:
	var ids: Array = _action.get("zombies", [])
	if ids.is_empty():
		return
	var budget := randf_range(float(_action.get("points", 0)),
			float(_action.get("points_max", _action.get("points", 0))))
	var offset := float(_action.get("column_offset", 0))
	var guard := 0
	while budget > 0.0 and guard < 24:
		guard += 1
		var id := StringName(ids[randi() % ids.size()])
		var def: ZombieDef = Data.zombie(id)
		if def == null:
			continue
		var cost := maxf(float(def.wave_cost), 25.0)
		if cost > budget and guard > 1:
			break
		budget -= cost
		var row: int = randi() % int(host.board.rows)
		var at: float = host.position.x \
				+ (SUMMON_OFFSET + offset) * host.board.cell_size.x
		var called: Zombie = host.board.spawn_zombie_at(id, row, at, [&"summoned"])
		if called != null and randf() < float(_action.get("plantfood_chance", 0.0)):
			called.set_runtime_tag(&"carrying_plantfood", true)
	Audio.play(&"zombie.summon", host.position)


## Fires the world's missile down a lane that has something in it, so a shot
## is a threat rather than a decoration.
func _shoot() -> void:
	if missile == &"":
		return
	var lanes: int = host.board.rows
	var occupied: Array = []
	for r in lanes:
		if not host.board.plants_in_row(r).is_empty():
			occupied.append(r)
	var row: int = int(occupied[randi() % occupied.size()]) \
			if not occupied.is_empty() else randi() % lanes
	var from := Vector2(host.position.x, host.board.grid_to_world(row, 0).y)
	host.board.spawn_projectile(missile, row, from + Vector2(-24.0, -12.0), host)
	Audio.play(&"zombie.boss.shoot", host.position)


## Moves to another lane. A jump may cross the board; a walk is one lane.
func _reposition(leap: bool) -> void:
	var rows: int = host.board.rows
	if rows <= 1:
		return
	var to: int = randi() % rows if leap else clampi(
			host.row + (1 if randf() < 0.5 else -1), 0, rows - 1)
	if to == host.row:
		return
	host.row = to
	host.position.y = host.board.grid_to_world(to, host.col).y + host.lane_offset
	host.z_index = host.board.lane_z(to, host.board.LAYER_ZOMBIE)
	host.queue_redraw()


## Charges toward the house, flattening what it runs over, then returns to
## its column. Each plant is struck once per rush, not once per frame.
func _begin_rush() -> void:
	var tuning: Dictionary = stage().get("tuning", {})
	_rush_left = float(tuning.get("RushDuration", 2.0))
	_struck = []
	host.set_runtime_tag(&"rushing", true)
	Audio.play(&"zombie.boss.rush", host.position)


func _rush(delta: float) -> void:
	var tuning: Dictionary = stage().get("tuning", {})
	var speed := float(tuning.get("RushSPS", RUSH_SPEED))
	var damage := float(tuning.get("RushDPS", RUSH_DAMAGE))
	_rush_left -= delta
	host.position.x -= speed * host.board.cell_size.x * delta
	host.col = host.board.world_to_col(host.position.x)

	for p: Plant in host.board.plants_in_row(host.row):
		if _struck.has(p) or absf(p.position.x - host.position.x) > host.board.cell_size.x * 0.6:
			continue
		_struck.append(p)
		p.take_damage(damage, host)

	if _rush_left > 0.0 and host.position.x > host.board.house_x():
		return
	# Back to its column: a boss that charged to the house and stayed there
	# would end the level by standing still.
	_rush_left = 0.0
	_struck = []
	host.set_runtime_tag(&"rushing", false)
	if idle_column >= 0:
		host.col = idle_column
		host.position.x = host.board.grid_to_world(host.row, idle_column).x
	else:
		host.position.x = host.board.spawn_x()
		host.col = host.board.world_to_col(host.position.x)
	_idle_left = _idle_time()


## Stuns every plant on the board. Plants have nothing to stop walking, so a
## stun suppresses whatever they do - see `Plant.apply_stun`.
func _roar() -> void:
	var tuning: Dictionary = stage().get("tuning", {})
	var seconds := float(tuning.get("RoarStunDuration", 5.0))
	for r in int(host.board.rows):
		for p: Plant in host.board.plants_in_row(r):
			p.apply_stun(seconds)
	Audio.play(&"zombie.boss.roar", host.position)
