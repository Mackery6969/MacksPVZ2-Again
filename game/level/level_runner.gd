class_name LevelRunner
extends Node
## Plays a level from its native definition.
##
## Reads the clean level schema produced by tools/import_levels.py: a `waves`
## list where each entry is either a spawn action or a `multi` bundle of
## actions. Wave pacing follows `wave_settings`, and the level is won once the
## last wave is cleared.

signal wave_started(index: int, total: int)
signal level_complete
## Emits the seed bank contents as an Array of {kind, id} dictionaries.
signal seedbank_ready(seeds: Array)

@export_group("Pacing")
## Seconds before the first wave arrives.
@export var first_wave_delay: float = 12.0
## Seconds between waves when the player has not cleared the board.
@export var wave_gap: float = 18.0
## A wave also starts early once the board has been cleared down to this share
## of the wave's original health, matching PvZ2's "next wave health" pacing.
@export_range(0.0, 1.0) var clear_fraction: float = 0.45

## PvZ2's music escalates through four stages across a level.
const MUSIC_STAGES := 4

@export_group("Spawning")
## Cells of guaranteed separation between zombies entering the same lane.
## Without this a wave's zombies stack on the spawn line exactly.
@export var spawn_spacing: float = 0.7
## Extra random spread added on top of the spacing, in cells. Accumulated
## rather than applied independently, so jitter can only widen a gap - never
## narrow one below `spawn_spacing`.
@export var spawn_jitter: float = 0.5

@export_group("Sun")
## Seconds between sun falling from the sky.
@export var sun_interval: float = 10.0
## Used instead when the level lists the FastSunDropper feature, which the
## early tutorial levels rely on to keep the player supplied.
@export var fast_sun_interval: float = 5.0

var board: Board
var level: Dictionary = {}
## Set by the host scene so conveyor wave actions can reach the belt.
var seed_bank: SeedBank = null

var waves: Array = []
var wave_index: int = -1
var running: bool = false

var _timer: float = 0.0
var _wave_spawned_health: float = 0.0
var _finished_spawning: bool = false
var _sun_timer: float = 0.0
## Last value pushed to the music `stage` parameter, so it is only set on change.
var _music_stage: int = 0


func start(level_def: Dictionary, target_board: Board) -> void:
	level = level_def
	board = target_board
	waves = level.get("waves", [])
	wave_index = -1
	running = true
	_finished_spawning = false
	_timer = first_wave_delay
	_sun_timer = _sun_cycle()

	# Level rows are 1-based, matching the wave data; the board is 0-based.
	var open_rows: Array[int] = []
	for r in (level.get("plantable_rows", []) as Array):
		open_rows.append(int(r) - 1)
	board.plantable_rows = open_rows

	# Any *Mowers feature gives the lane a mower; which one is cosmetic.
	board.mowers_enabled = has_mower_feature()
	board.setup_mowers()
	board.queue_redraw()

	var settings: Dictionary = level.get("wave_settings", {})
	if settings.has("first_delay"):
		_timer = float(settings["first_delay"])

	_music_stage = 0
	Audio.play_music(music_event())
	_update_music_stage()
	seedbank_ready.emit(seedbank_seeds())


## What the player may place, as {kind, id} entries.
##
## Entries are plants unless told otherwise. A level whose seedbank sets
## `"kind": "zombie"` hands the player zombies instead, which is how an
## I-Zombie style level works; individual entries may override it too.
func seedbank_seeds() -> Array:
	var sb: Dictionary = level.get("seedbank", {})
	var default_kind := StringName(sb.get("kind", &"plant"))
	var source: Array = sb.get("plants", []) if String(sb.get("mode", "chooser")) == "conveyor" \
			else sb.get("preset", [])

	var out: Array = []
	for entry in source:
		if entry is String:
			out.append({"kind": default_kind, "id": StringName(entry)})
		elif entry is Dictionary and entry.has("type"):
			out.append({
				"kind": StringName(entry.get("kind", default_kind)),
				"id": StringName(entry["type"]),
			})
	return out


## Levels name their mowers by stage - TutorialMowers, FrontLawnMowers,
## ModernMowers and so on - so the suffix is what matters, not the exact name.
func has_mower_feature() -> bool:
	for f in (level.get("features", []) as Array):
		if String(f).ends_with("Mowers"):
			return true
	return false


## Music for this level.
##
## A level names a stage, the stage's lawn names a music track, and the audio
## catalog maps that track to an event. Adding a world is then data only.
func music_event() -> StringName:
	var id := StringName("music.lawn." + music_track().to_lower())
	return id if Audio.has_event(id) else &"music.lawn.tutorial"


## The PVZGE track name for this level's stage, e.g. "Tutorial", "Egypt".
func music_track() -> String:
	var lawn := Data.lawn(StringName(level.get("stage", "")))
	return lawn.get("music", "Tutorial") if not lawn.is_empty() else "Tutorial"


## PvZ2 escalates its music in four stages as a level progresses. FMOD drives
## that from a parameter rather than by swapping tracks, so the intro/loop
## structure survives the transition.
func music_stage() -> int:
	if waves.is_empty():
		return 1
	var progress := float(maxi(wave_index, 0)) / float(waves.size())
	return clampi(int(progress * MUSIC_STAGES) + 1, 1, MUSIC_STAGES)


func _update_music_stage() -> void:
	var stage := music_stage()
	if stage != _music_stage:
		_music_stage = stage
		Audio.set_parameter(&"stage", float(stage))


## True when this level's seeds arrive on a conveyor belt rather than from a
## fixed set of chooser slots.
func is_conveyor() -> bool:
	return String((level.get("seedbank", {}) as Dictionary)
			.get("mode", "chooser")) == "conveyor"


## True when the current level lists `name` among its optional modules.
func has_feature(name: String) -> bool:
	return (level.get("features", []) as Array).has(name)


## Sun rate for this level, from its feature list.
func _sun_cycle() -> float:
	return fast_sun_interval if has_feature("FastSunDropper") else sun_interval


## Halts the level without clearing the board, so a result can be shown.
func stop() -> void:
	running = false


func _process(delta: float) -> void:
	if not running or board == null:
		return

	_sun_timer -= delta
	if _sun_timer <= 0.0:
		board.drop_sun_from_sky()
		_sun_timer = _sun_cycle()

	if _finished_spawning:
		if board.zombie_count() == 0:
			running = false
			level_complete.emit()
		return

	_timer -= delta
	if _timer <= 0.0 or _board_mostly_cleared():
		_advance_wave()


## True when enough of the current wave's health has been destroyed that the
## next wave should come early.
func _board_mostly_cleared() -> bool:
	if wave_index < 0 or _wave_spawned_health <= 0.0:
		return false
	return _remaining_health() <= _wave_spawned_health * clear_fraction


func _remaining_health() -> float:
	var total := 0.0
	for r in board.rows:
		for z in board.hostile_zombies_in_row(r):
			total += z.health
	return total


func _advance_wave() -> void:
	wave_index += 1
	if wave_index >= waves.size():
		_finished_spawning = true
		return

	_wave_spawned_health = 0.0
	_run_action(waves[wave_index])
	wave_started.emit(wave_index + 1, waves.size())
	_update_music_stage()
	var settings_flag: int = int((level.get("wave_settings", {}) as Dictionary)
			.get("flag_interval", 0))
	var is_flag := settings_flag > 0 and (wave_index + 1) % settings_flag == 0
	Audio.play(&"wave.huge" if is_flag else &"wave.start")

	var settings: Dictionary = level.get("wave_settings", {})
	_timer = float(settings.get("wave_gap", wave_gap))


func _run_action(action: Dictionary) -> void:
	match String(action.get("kind", "")):
		"spawn":
			# Track the last offset used in each lane, so each zombie starts
			# a guaranteed distance behind the one before it.
			var per_lane := {}
			var spawned: Array[Zombie] = []
			for z in (action.get("zombies", []) as Array):
				var made := _spawn_one(z, per_lane)
				if made != null:
					spawned.append(made)
			_assign_plant_food(spawned, int(action.get("plantfood", 0)))
		"conveyor":
			# Mid-level changes to what the belt can deliver.
			if seed_bank is ConveyorSeedBank:
				seed_bank.add_to_pool(action.get("add", []))
				seed_bank.remove_from_pool(action.get("remove", []))
		"multi":
			for sub in (action.get("actions", []) as Array):
				if sub is Dictionary:
					_run_action(sub)
		_:
			# Unmodelled action kinds are skipped rather than fatal, so a level
			# using a feature we have not built yet still plays.
			pass


## Marks some of a wave's zombies as carrying plant food, which they drop when
## killed. Only zombies whose data allows it are eligible - the rest are
## skipped rather than forced.
func _assign_plant_food(spawned: Array[Zombie], count: int) -> void:
	if count <= 0:
		return
	var eligible: Array[Zombie] = []
	for z in spawned:
		if z.has_tag(&"plantfood_carrier"):
			eligible.append(z)
	eligible.shuffle()
	for i in mini(count, eligible.size()):
		eligible[i].set_runtime_tag(&"carrying_plantfood", true)


func _spawn_one(entry: Dictionary, per_lane: Dictionary) -> Zombie:
	var id := StringName(entry.get("type", &""))
	if id == &"":
		return null
	# PopCap rows are 1-based; an absent row means "anywhere".
	var row: int = int(entry.get("row", 0)) - 1
	if not entry.has("row"):
		row = randi() % board.rows
	row = clampi(row, 0, board.rows - 1)

	# Offsets accumulate down the lane: each zombie sits at least
	# `spawn_spacing` behind the previous one, plus a random extra.
	var offset: float = randf() * spawn_jitter
	if per_lane.has(row):
		offset = float(per_lane[row]) + spawn_spacing + randf() * spawn_jitter
	per_lane[row] = offset

	var z := board.spawn_zombie(id, row, offset)
	if z != null:
		_wave_spawned_health += z.max_health
	return z


func wave_label() -> String:
	if _finished_spawning:
		return "Final wave"
	return "Wave %d / %d" % [maxi(wave_index + 1, 0), waves.size()]
