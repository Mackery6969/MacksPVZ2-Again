extends Node2D
## Headless end-to-end checks. Run with:
##   godot --headless tests/gameplay_test.tscn
##
## Time is scaled up so that real plant intervals (a peashooter fires every
## 1.35s) resolve in a short run without faking any game logic.

const TIME_SCALE := 25.0

var _failures: Array[String] = []
var _checks := 0


func _ready() -> void:
	Engine.time_scale = TIME_SCALE
	await get_tree().process_frame
	await _run()
	Engine.time_scale = 1.0
	_report()


func _run() -> void:
	_test_all_scripts_compile()
	_test_data_loaded()
	_test_inheritance_and_tags()
	_test_tag_inversion()
	await _test_peashooter_kills_zombie()
	await _test_sunflower_produces_sun()
	await _test_sun_value_and_hover()
	await _test_spawn_spacing()
	await _test_armor_absorbs_damage()
	await _test_level_runner_spawns_waves()
	_test_entity_taxonomy()
	await _test_allegiance()
	_test_zombie_seed_packets()
	_test_plantable_lanes()
	_test_tutorial_levels_playable()
	await _test_seed_cooldowns()
	await _test_armor_visual_state()
	await _test_armed_mine_is_not_food()
	await _test_sun_expires()
	await _test_mowers()
	await _test_plant_food()
	_test_input_actions()
	_test_shovel()
	await _test_conveyor_belt()
	_test_audio()
	await _test_natural_win_condition()
	await _test_campaign_progression()
	_test_modding()


# --- checks --------------------------------------------------------------

func check(label: String, condition: bool, detail: String = "") -> void:
	_checks += 1
	if condition:
		print("  PASS  %s" % label)
	else:
		_failures.append(label)
		print("  FAIL  %s%s" % [label, ("  (%s)" % detail) if detail else ""])


func check_eq(label: String, actual, expected) -> void:
	check(label, actual == expected, "got %s, expected %s" % [str(actual), str(expected)])


# --- tests ---------------------------------------------------------------

## Loads every GDScript in the project. The gameplay tests only touch the
## classes they use, so a parse error in a scene script - main.gd especially -
## would otherwise slip through to runtime.
func _test_all_scripts_compile() -> void:
	print("\n[scripts]")
	var bad: Array[String] = []
	var count := 0
	for path in _gd_files("res://"):
		count += 1
		var res = load(path)
		if not (res is GDScript):
			bad.append(path)
	check("every .gd compiles", bad.is_empty(),
			"failed: %s" % str(bad) if not bad.is_empty() else "")
	print("        (%d scripts checked)" % count)


## Every .gd under `root`, skipping Godot's own metadata directory.
func _gd_files(root: String) -> Array[String]:
	var out: Array[String] = []
	var pending: Array[String] = [root]
	while not pending.is_empty():
		var dir_path: String = pending.pop_back()
		var dir := DirAccess.open(dir_path)
		if dir == null:
			continue
		dir.list_dir_begin()
		var name := dir.get_next()
		while name != "":
			if name.begins_with("."):
				pass
			elif dir.current_is_dir():
				pending.append(dir_path.path_join(name))
			elif name.ends_with(".gd"):
				out.append(dir_path.path_join(name))
			name = dir.get_next()
		dir.list_dir_end()
	return out


func _test_data_loaded() -> void:
	print("\n[data]")
	check("zombies loaded", Data.zombies.size() > 400)
	check("plants loaded", Data.plants.size() > 200)
	check("levels loaded", Data.levels.size() >= 4)
	check("no load errors", Data.errors().is_empty(), str(Data.errors()))
	check("peashooter exists", Data.plant(&"peashooter") != null)
	check("tutorial zombie exists", Data.zombie(&"tutorial") != null)


func _test_inheritance_and_tags() -> void:
	print("\n[inheritance]")
	# tutorial_armor1 is untouched by any pack, so it shows base values.
	var z := Data.zombie(&"tutorial_armor1")
	check_eq("extends archetype", z.extends_id, &"normal")
	check_eq("toughness from data", z.stat(&"toughness"), 190)
	check("inherited archetype tags", z.has_tag(&"swallowable"))

	var p := Data.plant(&"peashooter")
	check("peashooter has shooter component", p.components_of(&"shooter").size() == 1)
	check_eq("shoot interval", p.components_of(&"shooter")[0].cfg(&"interval"), 1.35)


func _test_tag_inversion() -> void:
	print("\n[tag inversion]")
	# The whole point of the inversion: a gargantuar is NOT swallowable, and we
	# can find that out without any plant-specific field on the zombie.
	var garg := Data.zombie(&"beach_gargantuar")
	check("gargantuar not swallowable", garg != null and not garg.has_tag(&"swallowable"))
	check("basic zombie is swallowable", Data.zombie(&"tutorial_armor1").has_tag(&"swallowable"))

	var swallowable := Data.query(&"zombie", [&"swallowable"])
	var immune := Data.query(&"zombie", [], [&"swallowable"])
	check("query splits the roster", swallowable.size() > 0 and immune.size() > 0,
			"%d swallowable / %d immune" % [swallowable.size(), immune.size()])


func _test_peashooter_kills_zombie() -> void:
	print("\n[combat]")
	var board := _make_board()
	var plant := board.place_plant(&"peashooter", 2, 1)
	check("peashooter placed", plant != null)
	var zombie := board.spawn_zombie(&"tutorial", 2)
	check("zombie spawned", zombie != null)
	var expected_hp: float = float(Data.zombie(&"tutorial").stat(&"toughness"))
	check_eq("zombie health from data", zombie.max_health, expected_hp)

	var start_x: float = zombie.position.x
	# 260 HP / 20 dmg = 13 peas at 1.35s = ~18s of game time.
	await _wait_game_seconds(26.0)

	check("zombie moved toward house", zombie == null or not is_instance_valid(zombie)
			or zombie.position.x < start_x)
	check("zombie died to peas", not is_instance_valid(zombie) or zombie.is_dead,
			"health left %s" % (zombie.health if is_instance_valid(zombie) else "gone"))
	board.queue_free()


func _test_sunflower_produces_sun() -> void:
	print("\n[sun]")
	var board := _make_board()
	var before: int = board.sun
	var sf := board.place_plant(&"sunflower", 1, 1)
	check("sunflower placed", sf != null)

	# first_delay is 5s +/- 5, so 14s covers the worst case. Watch as it
	# happens rather than counting at the end - a sun dropped early would
	# have expired by then and the check would read as a failure.
	var seen := false
	var waited := 0.0
	while waited < 14.0 and not seen:
		await get_tree().process_frame
		waited += get_process_delta_time()
		if board.get_node("Suns").get_child_count() > 0:
			seen = true
	check("sunflower dropped sun", seen, "none seen in %.0fs" % waited)
	board.queue_free()


func _test_sun_value_and_hover() -> void:
	print("\n[sun value + hover]")
	check_eq("sun value is the constant 50", SunToken.VALUE, 50)

	var board := _make_board()
	var before: int = board.sun
	board.drop_sun(board.grid_to_world(2, 3))
	var suns := board.get_node("Suns")
	check_eq("one sun on the board", suns.get_child_count(), 1)

	var token: SunToken = suns.get_child(0)

	# Hover reach: inside the radius counts, well outside does not.
	check("hover hits at the centre", token.contains_point(token.global_position))
	check("hover hits within the radius",
			token.contains_point(token.global_position + Vector2(token.radius * 0.5, 0)))
	check("hover misses well outside",
			not token.contains_point(token.global_position + Vector2(200, 0)))

	token.collect()
	check_eq("not banked until it reaches the counter", board.sun, before)

	# collect() is idempotent, so hover polling every frame during the flight
	# cannot collect the same sun twice.
	token.collect()
	token.collect()

	await _wait_game_seconds(token.fly_time + 0.4)
	check_eq("collecting grants 50 sun exactly once", board.sun, before + 50)
	check("sun token freed after banking", not is_instance_valid(token))
	board.queue_free()


func _test_spawn_spacing() -> void:
	print("\n[spawn spacing]")
	var board := _make_board()
	var runner := LevelRunner.new()
	runner.first_wave_delay = 0.0
	add_child(runner)

	# Four zombies into one lane - the case that used to stack them exactly.
	runner.start({
		"id": "spacing_test",
		"waves": [{"kind": "spawn", "zombies": [
			{"type": "tutorial", "row": 3}, {"type": "tutorial", "row": 3},
			{"type": "tutorial", "row": 3}, {"type": "tutorial", "row": 3}]}],
		"wave_settings": {"count": 1},
	}, board)

	await _wait_game_seconds(0.5)
	var lane := board.zombies_in_row(2)
	check_eq("all four spawned in the lane", lane.size(), 4)

	if lane.size() == 4:
		# zombies_in_row sorts nearest-house first, so walk the gaps.
		var min_gap := INF
		var overlapping := false
		for i in range(1, lane.size()):
			var gap: float = absf(lane[i].position.x - lane[i - 1].position.x)
			min_gap = minf(min_gap, gap)
			if gap < 1.0:
				overlapping = true
		check("no two zombies share a position", not overlapping)
		# spawn_spacing is a floor, not an average - jitter only ever widens.
		var expected: float = runner.spawn_spacing * board.cell_size.x
		check("every gap clears the spacing floor", min_gap >= expected - 0.5,
				"smallest gap %.1fpx, floor %.1fpx" % [min_gap, expected])
		# And that floor has to actually clear a zombie's body.
		var body_width: float = lane[0].body_size.x
		check("spacing floor exceeds zombie width", expected > body_width,
				"%.1fpx spacing vs %.1fpx body" % [expected, body_width])

	runner.queue_free()
	board.queue_free()


func _test_armor_absorbs_damage() -> void:
	print("\n[armor]")
	var board := _make_board()
	var z := board.spawn_zombie(&"tutorial_armor2", 0)
	check("armored zombie spawned", z != null)
	var armor := z.component(&"armor")
	check("armor component attached", armor != null)
	if armor != null:
		check_eq("armor durability from data", armor.durability, 1100.0)
		var body_before: float = z.health
		z.take_damage(500.0)
		check("armor absorbed the hit", z.health == body_before,
				"body went %s -> %s" % [body_before, z.health])
		check_eq("durability reduced", armor.durability, 600.0)
		z.take_damage(600.0)
		check("armor broke, body still full", z.health == body_before)
		z.take_damage(50.0)
		check("damage reaches body once armor is gone", z.health < body_before)
	board.queue_free()


func _test_level_runner_spawns_waves() -> void:
	print("\n[level]")
	var board := _make_board()
	var runner := LevelRunner.new()
	add_child(runner)

	var level := Data.level(&"tutorial_1")
	check("tutorial_1 level found", not level.is_empty())
	var seeds: Array = []
	runner.seedbank_ready.connect(func(ids): seeds.assign(ids))
	runner.start(level, board)
	check_eq("seedbank is peashooter only", seeds,
			[{"kind": &"plant", "id": &"peashooter"}])
	check_eq("level has 3 waves", runner.waves.size(), 3)

	await _wait_game_seconds(16.0)
	check("first wave spawned zombies", board.zombie_count() > 0,
			"%d on board" % board.zombie_count())
	runner.queue_free()
	board.queue_free()


func _test_modding() -> void:
	print("\n[modding]")
	var pack_installed := false
	for m in Mods.priority_list():
		if String(m["id"]) == "example_pack":
			pack_installed = true
	check("example_pack is installed", pack_installed)
	if not pack_installed:
		return

	# 1. custom zombie
	var sprinter := Data.zombie(&"sprinter")
	check("mod added a new zombie", sprinter != null)
	if sprinter != null:
		check_eq("custom zombie stats", sprinter.stat(&"speed"), 0.55)
		check("custom tag applied", sprinter.has_tag(&"fast"))
		check("tag removal applied", not sprinter.has_tag(&"swallowable"))
		check("archetype tags still inherited", sprinter.has_tag(&"chompable"))

	# 2. data override of an existing entity
	var tut := Data.zombie(&"tutorial")
	check_eq("mod overrode base zombie stats", tut.stat(&"toughness"), 260)
	check_eq("override came from the pack", tut.source_mod, &"example_pack")

	# 3. custom plant using a mod-supplied behaviour
	var splitpea := Data.plant(&"splitpea_mk2")
	check("mod added a new plant", splitpea != null)
	check("new component type registered", Components.has_type(&"burst_shooter"))
	check_eq("burst_shooter owned by pack", Components.owner_of(&"burst_shooter"), &"example_pack")

	# 4. a pack can be installed but switched off
	check("example_override is installed", Mods.is_installed(&"example_override"))
	check("example_override is disabled", not Mods.is_enabled(&"example_override"))
	check_eq("disabled pack does not override a built-in",
			Components.owner_of(&"sun_producer"), &"base")

	# 5. overriding a BUILT-IN still works, tested directly so the capability
	#    is proven without a pack altering base balance by default.
	var original: GDScript = load("res://core/components/builtin/sun_producer.gd")
	var replacement: GDScript = load("res://mods/example_override/components/sun_producer.gd")
	var announced := [false]
	var on_override := func(type, _old, _new): announced[0] = (type == &"sun_producer")
	Components.type_overridden.connect(on_override)
	Components.register(&"sun_producer", replacement, &"test_override")
	check_eq("a built-in can be replaced", Components.owner_of(&"sun_producer"),
			&"test_override")
	check("the override is announced", announced[0])
	Components.register(&"sun_producer", original, &"base")
	Components.type_overridden.disconnect(on_override)
	check_eq("restored to the built-in", Components.owner_of(&"sun_producer"), &"base")

	# 6. custom level
	var lvl := Data.level(&"example_showdown")
	check("mod added a new level", not lvl.is_empty())
	check_eq("custom level wave count", (lvl.get("waves", []) as Array).size(), 3)

	# 7. the modded plant actually runs the modded component
	var board := _make_board()
	var p := board.place_plant(&"splitpea_mk2", 2, 1)
	check("modded plant spawns", p != null)
	if p != null:
		check("modded plant runs mod component", p.component(&"burst_shooter") != null)
	board.queue_free()


func _test_entity_taxonomy() -> void:
	print("\n[taxonomy]")
	check("graves loaded", Data.graves.size() >= 30, "%d" % Data.graves.size())
	check("objects loaded", Data.objects.size() >= 50, "%d" % Data.objects.size())

	# Graves are destroyable and carry grid-item events.
	var grave := Data.grave(&"gravestone")
	check("a grave has toughness", grave != null and grave.toughness > 0.0)
	var cabinet := Data.grave(&"eightiesarcadecabinet")
	check("a grave can summon", cabinet != null
			and cabinet.component_spec(&"grave_summon") != null)
	# Every component type the data references must actually exist, or the
	# entity spawns with a missing behaviour and only a warning.
	check("grave_summon is implemented", Components.has_type(&"grave_summon"))
	var missing: Array[StringName] = []
	for pool in [Data.zombies, Data.plants, Data.graves, Data.objects]:
		for id in pool:
			for spec in (pool[id] as EntityDef).components:
				if not Components.has_type(spec.type) and not missing.has(spec.type):
					missing.append(spec.type)
	check("no data references an unknown component type", missing.is_empty(),
			str(missing))

	# Evil potions are objects, not plants - PVZGE files them as plants, which
	# would otherwise let them into seed banks and level generation.
	check("potion is not a plant", Data.plant(&"zombiepotion_speed") == null)
	var potion := Data.board_object(&"zombiepotion_speed")
	check("potion is an object", potion != null)
	if potion != null:
		check_eq("potion category", potion.category, ObjectDef.Category.POTION)
	var tile := Data.board_object(&"goldtile")
	check("tiles are objects", tile != null)
	if tile != null:
		check_eq("tile category", tile.category, ObjectDef.Category.TILE)


func _test_allegiance() -> void:
	print("\n[allegiance]")
	var board := _make_board()
	var hostile := board.spawn_zombie(&"tutorial", 2)
	var charmed := board.spawn_zombie(&"tutorial", 2)
	check("both zombies spawned", hostile != null and charmed != null)

	check("zombies start hostile", not hostile.is_charmed())
	check_eq("hostile walks toward the house", hostile.direction(), -1)

	charmed.charm()
	check("charmed zombie reports charmed", charmed.is_charmed())
	check_eq("charmed walks the other way", charmed.direction(), 1)
	check("charming sets a runtime tag", charmed.has_tag(&"charmed"))

	check_eq("lane still holds both", board.zombies_in_row(2).size(), 2)
	check_eq("only one is hostile", board.hostile_zombies_in_row(2).size(), 1)
	check_eq("only one is charmed", board.charmed_zombies_in_row(2).size(), 1)
	# Win conditions must not wait on the player's own zombies.
	check_eq("charmed excluded from zombie_count", board.zombie_count(), 1)

	# A pea must not hit the player's own zombie. Move the hostile one well
	# clear first, since both spawn on the same line.
	hostile.position.x += 400.0
	var pea := board.spawn_projectile(&"pea", 2, charmed.position - Vector2(40, 0), null)
	check("projectile ignores charmed zombies",
			not pea._check_hit(charmed.position.x - 5.0, charmed.position.x + 5.0))
	check("projectile still hits hostile zombies",
			pea._check_hit(hostile.position.x - 5.0, hostile.position.x + 5.0))
	board.queue_free()


func _test_zombie_seed_packets() -> void:
	print("\n[zombie seed packets]")
	var board := _make_board()
	var runner := LevelRunner.new()
	add_child(runner)

	# An I-Zombie style level: the seed bank holds zombies, not plants.
	runner.start({
		"id": "izombie_test",
		"seedbank": {"mode": "chooser", "kind": "zombie",
					 "preset": ["tutorial", "tutorial_armor1"]},
		"waves": [],
	}, board)

	var seeds := runner.seedbank_seeds()
	check_eq("seed bank holds two zombies", seeds.size(), 2)
	if seeds.size() == 2:
		check_eq("seeds are zombie kind", seeds[0]["kind"], &"zombie")
		check_eq("seed id carried", seeds[0]["id"], &"tutorial")

	var placed := board.place_entity(&"zombie", &"tutorial", 1, 4)
	check("a zombie can be placed from a packet", placed is Zombie)
	if placed != null:
		check("placed zombie landed in its lane",
				board.zombies_in_row(1).has(placed))
	# A lane takes any number of zombies, unlike a plant cell.
	check("zombies do not block their cell",
			board.can_place_entity(&"zombie", 1, 4))
	runner.queue_free()
	board.queue_free()


func _test_plantable_lanes() -> void:
	print("\n[plantable lanes]")
	var board := _make_board()
	var runner := LevelRunner.new()
	add_child(runner)
	var level := Data.level(&"tutorial_1")
	runner.start(level, board)

	var rows: Array = level.get("plantable_rows", [])
	check_eq("tutorial 1 restricts planting to one lane", rows.size(), 1)
	check_eq("and that lane is 3", int(rows[0]) if rows.size() > 0 else -1, 3)
	# Level rows are 1-based; the board is 0-based.
	check("lane 3 is plantable", board.is_row_plantable(2))
	check("lane 1 is locked", not board.is_row_plantable(0))
	check("planting is refused in a locked lane",
			board.place_plant(&"peashooter", 0, 1) == null)
	check("planting works in the open lane",
			board.place_plant(&"peashooter", 2, 1) != null)

	# Other levels leave every lane open.
	var board2 := _make_board()
	var runner2 := LevelRunner.new()
	add_child(runner2)
	runner2.start(Data.level(&"tutorial_2"), board2)
	check("tutorial 2 leaves lanes open", board2.is_row_plantable(0))

	runner.queue_free()
	runner2.queue_free()
	board.queue_free()
	board2.queue_free()


func _test_tutorial_levels_playable() -> void:
	print("\n[tutorial levels]")
	var campaign := Data.campaign(&"tutorial")
	check("tutorial campaign exists", campaign != null)
	if campaign == null:
		return
	check_eq("campaign has four levels", campaign.levels.size(), 4)
	check_eq("in order", campaign.levels,
			[&"tutorial_1", &"tutorial_2", &"tutorial_3", &"tutorial_4"] as Array[StringName])

	# Every level must be loadable, have waves, and reference only content
	# that actually exists - otherwise it stalls partway through.
	var runner := LevelRunner.new()
	add_child(runner)
	for level_id in campaign.levels:
		var level := Data.level(level_id)
		if level.is_empty():
			check("%s exists" % level_id, false)
			continue

		var waves: Array = level.get("waves", [])
		check("%s has waves" % level_id, not waves.is_empty())

		# Seeds resolve.
		var board := _make_board()
		runner.start(level, board)
		var seeds := runner.seedbank_seeds()
		check("%s has a seed bank" % level_id, not seeds.is_empty())
		var bad_seeds: Array = []
		for seed in seeds:
			var def: EntityDef = (Data.zombie(seed["id"]) if seed["kind"] == &"zombie"
					else Data.plant(seed["id"]))
			if def == null:
				bad_seeds.append(seed["id"])
		check("%s seeds all exist" % level_id, bad_seeds.is_empty(), str(bad_seeds))

		# Every seed's behaviour is implemented, or the plant does nothing.
		var inert: Array = []
		for seed in seeds:
			var def := Data.plant(seed["id"])
			if def != null and def.components.is_empty():
				inert.append(seed["id"])
		check("%s seeds all do something" % level_id, inert.is_empty(), str(inert))

		# Wave zombies resolve.
		var bad_zombies: Array = []
		for wave in waves:
			for entry in _wave_zombies(wave):
				var zid := StringName(entry.get("type", &""))
				if Data.zombie(zid) == null and not bad_zombies.has(zid):
					bad_zombies.append(zid)
		check("%s zombies all exist" % level_id, bad_zombies.is_empty(), str(bad_zombies))

		board.queue_free()
	runner.queue_free()


## Zombie entries in a wave, flattening `multi` bundles.
func _wave_zombies(wave: Dictionary) -> Array:
	var out: Array = []
	if wave.get("kind") == "multi":
		for sub in (wave.get("actions", []) as Array):
			if sub is Dictionary:
				out.append_array(_wave_zombies(sub))
	else:
		out.append_array(wave.get("zombies", []))
	return out


## The runner must declare victory on its own once the last wave is spawned
## and the board is clear - not only when something calls _on_won().
func _test_natural_win_condition() -> void:
	print("\n[win condition]")
	var board := _make_board()
	var runner := LevelRunner.new()
	runner.first_wave_delay = 0.0
	add_child(runner)

	var won := [false]
	runner.level_complete.connect(func(): won[0] = true)
	runner.start({
		"id": "win_test",
		"seedbank": {"mode": "chooser", "preset": ["peashooter"]},
		"waves": [{"kind": "spawn", "zombies": [{"type": "tutorial", "row": 3}]}],
		"wave_settings": {"count": 1},
	}, board)

	await _wait_game_seconds(0.5)
	check_eq("the wave spawned", board.zombie_count(), 1)
	check("not won while a zombie lives", not won[0])

	for z in board.zombies_in_row(2):
		z.take_damage(99999.0)
	await _wait_game_seconds(0.5)

	check_eq("board is clear", board.zombie_count(), 0)
	check("runner declares victory", won[0])
	check("runner stops after winning", not runner.running)

	runner.queue_free()
	board.queue_free()


func _test_campaign_progression() -> void:
	print("\n[progression]")
	var campaign := Data.campaign(&"tutorial")
	check_eq("next after 1 is 2", campaign.next_after(&"tutorial_1"), &"tutorial_2")
	check_eq("next after 3 is 4", campaign.next_after(&"tutorial_3"), &"tutorial_4")
	check_eq("nothing after the last", campaign.next_after(&"tutorial_4"), &"")
	check("last level is flagged", campaign.is_last(&"tutorial_4"))
	check("first level is not", not campaign.is_last(&"tutorial_1"))

	# Drive the real entry scene: clearing a level must load the next one.
	var main = load("res://game/main.tscn").instantiate()
	main.level_transition_delay = 0.05
	main.retry_delay = 0.05
	add_child(main)
	await get_tree().process_frame
	check_eq("starts at the first level", main._current_level, &"tutorial_1")

	main._on_won()
	await _wait_game_seconds(0.4)
	check_eq("clearing a level advances", main._current_level, &"tutorial_2")
	check("board was cleared for the next level", main.board.zombie_count() == 0)

	# Losing repeats the same level rather than advancing.
	main._on_lost()
	await _wait_game_seconds(0.4)
	check_eq("losing retries the same level", main._current_level, &"tutorial_2")

	# Finishing the last level ends the campaign instead of wrapping around.
	main.load_level(&"tutorial_4")
	await get_tree().process_frame
	main._on_won()
	await _wait_game_seconds(0.4)
	check_eq("last level does not advance", main._current_level, &"tutorial_4")
	check_eq("campaign completion is announced", main._status.text,
			campaign.completion_message)
	main.queue_free()


func _test_seed_cooldowns() -> void:
	print("\n[seed cooldowns]")
	var bank := SeedBank.new()
	add_child(bank)
	bank.setup([{"kind": &"plant", "id": &"peashooter"},
				{"kind": &"plant", "id": &"sunflower"},
				{"kind": &"plant", "id": &"wallnut"}])
	check_eq("bank has three packets", bank.size(), 3)

	# cooldown_from is the share of the recharge a packet starts with:
	# peashooter 1.0 (ready), sunflower 0.0 (empty), wallnut 0.75.
	check("peashooter starts ready", bank.is_recharged(0))
	check("sunflower starts recharging", not bank.is_recharged(1))
	check("wallnut starts part-charged", not bank.is_recharged(2))
	check_eq("wallnut starts at 75%", snappedf(bank.packet(2).fraction(), 0.01), 0.75)
	check_eq("cost read from the plant", bank.packet(0).cost, 100)

	# Using a packet empties it.
	bank.spend(0)
	check("spending empties the packet", not bank.is_recharged(0))
	check_eq("and it starts from zero", bank.packet(0).fraction(), 0.0)

	# Sun alone is not enough while a packet is still charging.
	check("recharging packet is unusable", not bank.can_use(0, 9999))
	check("affordability is separate", bank.can_afford(0, 9999))

	await _wait_game_seconds(6.0)
	check("peashooter recharged after its cooldown", bank.is_recharged(0))
	check("and is now usable", bank.can_use(0, 9999))
	check("still unusable without sun", not bank.can_use(0, 0))

	# The half-time module halves every recharge.
	var fast := SeedBank.new()
	add_child(fast)
	fast.setup([{"kind": &"plant", "id": &"wallnut"}], true)
	check_eq("half-time halves the recharge", fast.packet(0).recharge,
			float(Data.plant(&"wallnut").cooldown) * 0.5)

	bank.queue_free()
	fast.queue_free()


func _test_armor_visual_state() -> void:
	print("\n[armor state]")
	var board := _make_board()
	var plain := board.spawn_zombie(&"tutorial", 0)
	var armored := board.spawn_zombie(&"tutorial_armor2", 1)

	check("plain zombie has no armor component", plain.component(&"armor") == null)
	check("plain zombie is not tagged armored", not plain.has_tag(&"armored"))

	var armor := armored.component(&"armor")
	check("armored zombie has armor", armor != null)
	if armor != null:
		check("armor starts intact", armor.is_intact())
		check("armored zombie is tagged", armored.has_tag(&"armored"))
		check_eq("armor starts full", armor.fraction(), 1.0)

		armored.take_damage(550.0)
		check("armor is worn but intact", armor.is_intact())
		check_eq("wear is reflected", snappedf(armor.fraction(), 0.01), 0.5)

		armored.take_damage(600.0)
		check("armor breaks", not armor.is_intact())
		check("armored tag cleared on break", not armored.has_tag(&"armored"))
	board.queue_free()


func _test_armed_mine_is_not_food() -> void:
	print("\n[potato mine]")
	var board := _make_board()
	var mine := board.place_plant(&"potatomine", 2, 3)
	check("potato mine placed", mine != null)
	var fuse := mine.component(&"explosive")
	check("mine has an explosive component", fuse != null)

	# While arming it is ordinary food.
	check("arming mine is edible", not mine.has_tag(&"uneatable"))
	check("arming mine is tagged arming", mine.has_tag(&"arming"))
	var zombie := board.spawn_zombie(&"tutorial", 2)
	check("zombie would eat an arming mine", zombie._can_eat(mine))

	# Once armed it detonates on contact instead of being chewed.
	await _wait_game_seconds(float(Data.plant(&"potatomine").stat(&"charge_time", 14.0)) + 2.0)
	check("mine finished arming", not mine.has_tag(&"arming"))
	check("armed mine is uneatable", mine.has_tag(&"uneatable"))
	check("zombie ignores an armed mine as food", not zombie._can_eat(mine))
	board.queue_free()


func _test_sun_expires() -> void:
	print("\n[sun expiry]")
	var board := _make_board()
	board.drop_sun(board.grid_to_world(2, 3))
	var suns := board.get_node("Suns")
	check_eq("sun on the board", suns.get_child_count(), 1)

	var token: SunToken = suns.get_child(0)
	var life: float = token.lifetime
	await _wait_game_seconds(life * 0.5)
	check("still there halfway through its life", is_instance_valid(token))

	await _wait_game_seconds(life * 0.6 + 1.0)
	check("uncollected sun despawns", not is_instance_valid(token))
	check_eq("and leaves nothing behind", suns.get_child_count(), 0)
	board.queue_free()


func _test_mowers() -> void:
	print("\n[mowers]")
	var board := _make_board()
	board.mowers_enabled = true
	board.setup_mowers()
	check_eq("one mower per lane", board.get_node("Mowers").get_child_count(), board.rows)
	check("lane starts protected", board.has_mower(2))

	var lost := [false]
	board.level_lost.connect(func(): lost[0] = true)
	var fired := [-1]
	board.mower_triggered.connect(func(row): fired[0] = row)

	# A zombie reaching the house should set the mower off, not end the level.
	var z := board.spawn_zombie(&"tutorial", 2)
	z.position.x = board.house_x() + 4.0
	await _wait_game_seconds(1.0)
	check_eq("the lane's mower fired", fired[0], 2)
	check("level not lost while a mower remains", not lost[0])

	# It should clear the lane on its way out.
	await _wait_game_seconds(3.0)
	check("mower destroyed the zombie", not is_instance_valid(z) or z.is_dead)
	check("lane is no longer protected", not board.has_mower(2))
	check("other lanes still are", board.has_mower(0))

	# The next zombie through a spent lane ends the level.
	var z2 := board.spawn_zombie(&"tutorial", 2)
	z2.position.x = board.house_x() + 4.0
	await _wait_game_seconds(1.0)
	check("spent lane loses the level", lost[0])
	board.queue_free()


func _test_plant_food() -> void:
	print("\n[plant food]")
	var board := _make_board()
	check_eq("starts with none", board.plant_food, 0)

	# A carrier drops food where it dies.
	var carrier := board.spawn_zombie(&"tutorial", 1)
	check("tutorial zombie may carry food", carrier.has_tag(&"plantfood_carrier"))
	carrier.set_runtime_tag(&"carrying_plantfood", true)
	carrier.take_damage(99999.0)
	await get_tree().process_frame

	var dropped: PlantFoodToken = null
	for c in board.get_node("Suns").get_children():
		if c is PlantFoodToken:
			dropped = c
	check("carrier dropped plant food", dropped != null)
	if dropped != null:
		dropped.collect()
		await _wait_game_seconds(dropped.fly_time + 0.4)
		check_eq("collecting banks one food", board.plant_food, 1)

	# Feeding a shooter should unload a burst.
	var shooter := board.place_plant(&"peashooter", 2, 1)
	board.spawn_zombie(&"tutorial", 2)
	var before := board.get_node("Projectiles").get_child_count()
	check("feeding a plant works", board.feed_plant(2, 1))
	check_eq("food was spent", board.plant_food, 0)
	await _wait_game_seconds(1.5)
	check("plant food fired a burst",
			board.get_node("Projectiles").get_child_count() > before + 3,
			"%d projectiles" % board.get_node("Projectiles").get_child_count())

	# Feeding with nothing in the bank does nothing.
	check("cannot feed without food", not board.feed_plant(2, 1))
	# Feeding an empty cell does nothing either.
	board.add_plant_food(1)
	check("cannot feed an empty cell", not board.feed_plant(4, 8))
	check_eq("and the food is kept", board.plant_food, 1)

	# Sunflower produces a handful at once.
	var sf := board.place_plant(&"sunflower", 3, 1)
	var suns_before := board.get_node("Suns").get_child_count()
	check("feeding a sunflower works", board.feed_plant(3, 1))
	check("sunflower dropped several suns",
			board.get_node("Suns").get_child_count() >= suns_before + 3)
	board.queue_free()


func _test_input_actions() -> void:
	print("\n[input actions]")
	# The project's InputMap owns these, so they can be rebound - including to
	# a controller - without touching code.
	for action in ["Slot 1", "Slot 4", "Plant Food", "Shovel", "Fast Forward",
			"Previous Slot", "Next Slot"]:
		check("action '%s' exists" % action, InputMap.has_action(action))

	var main = load("res://game/main.tscn").instantiate()
	add_child(main)
	await get_tree().process_frame
	# Conveyor levels have extra slots with their own bindings from 5 on.
	main._conveyor_level = false
	check_eq("slot 5 uses the normal binding", main._slot_action(4), &"Slot 5")
	main._conveyor_level = true
	check_eq("slot 5 uses the conveyor binding", main._slot_action(4),
			&"Slot 5 (Convayor)")
	check_eq("slot 1 is shared", main._slot_action(0), &"Slot 1")
	main.queue_free()


func _test_shovel() -> void:
	print("\n[shovel]")
	var board := _make_board()
	check("plant placed", board.place_plant(&"peashooter", 2, 3) != null)
	check("cell is occupied", board.plant_at(2, 3) != null)
	check("shovel digs it up", board.dig_up(2, 3))
	check("cell is free again", board.plant_at(2, 3) == null)
	check("can replant there", board.can_place_entity(&"plant", 2, 3))
	check("digging an empty cell does nothing", not board.dig_up(2, 3))
	board.queue_free()


func _test_conveyor_belt() -> void:
	print("\n[conveyor]")
	var level := Data.level(&"conveyor_demo")
	check("conveyor demo level exists", not level.is_empty())
	if level.is_empty():
		return

	var belt := ConveyorSeedBank.new()
	add_child(belt)
	belt.setup_conveyor(level.get("seedbank", {}))
	check_eq("pool built from the level", belt.pool.size(), 4)
	check_eq("belt starts empty", belt.size(), 0)

	# The belt refills fast when empty and slows as it fills.
	check_eq("empty belt uses the shortest delay", belt.current_drop_delay(), 3.0)

	await _wait_game_seconds(4.0)
	check("a packet arrived", belt.size() > 0, "%d on the belt" % belt.size())

	# Packets are free and immediately usable - nothing to pay or wait for.
	check("belt packet is ready at once", belt.is_recharged(0))
	check_eq("belt packets are free", belt.cost_of(0), 0)
	check("affordable with no sun", belt.can_afford(0, 0))
	check("usable with no sun", belt.can_use(0, 0))

	# Placing takes it off the belt rather than recharging it.
	var before := belt.size()
	var taken: StringName = belt.packet(0).id
	belt.consume(0)
	check_eq("placing removes the packet", belt.size(), before - 1)
	if belt.size() > 0:
		check("the queue shifted up", belt.packet(0) != null)

	await _wait_game_seconds(20.0)
	check("belt keeps delivering", belt.size() >= 3, "%d on the belt" % belt.size())
	check("delay grows as the belt fills", belt.current_drop_delay() > 3.0)

	# Per-plant limits are respected.
	var counts := {}
	for i in belt.size():
		var id: StringName = belt.packet(i).id
		counts[id] = int(counts.get(id, 0)) + 1
	check("sunflower respects its max of 2", int(counts.get(&"sunflower", 0)) <= 2)
	check("wallnut respects its max of 2", int(counts.get(&"wallnut", 0)) <= 2)

	# Capacity caps growth. A belt built with a small capacity never exceeds
	# it, however long it runs.
	var small := ConveyorSeedBank.new()
	small.capacity = 3
	add_child(small)
	small.setup_conveyor(level.get("seedbank", {}))
	await _wait_game_seconds(40.0)
	check_eq("belt fills to capacity", small.size(), 3)
	check("and never past it", small.size() <= small.capacity)
	small.queue_free()

	# Wave actions can change what the belt delivers mid-level.
	belt.remove_from_pool([&"peashooter"])
	check_eq("removing takes it out of the pool", belt._pool_index(&"peashooter"), -1)
	belt.add_to_pool([{"type": "bonkchoy", "weight": 100, "max": 1}])
	check("adding puts it in the pool", belt._pool_index(&"bonkchoy") >= 0)

	belt.queue_free()

	# The runner reports the mode so the HUD can pick the right bank.
	var runner := LevelRunner.new()
	add_child(runner)
	var board := _make_board()
	runner.start(level, board)
	check("runner reports a conveyor level", runner.is_conveyor())
	runner.start(Data.level(&"tutorial_1"), board)
	check("and a chooser level is not", not runner.is_conveyor())
	runner.queue_free()
	board.queue_free()


func _test_audio() -> void:
	print("\n[audio]")
	check("a backend is selected", Audio.backend != null)
	check("backend has a name", Audio.backend.backend_name() != "")
	# FMOD is not installed here, so its backend must decline rather than be
	# picked and then fail at every call.
	var fmod: AudioBackend = load("res://core/audio/backends/fmod_backend.gd").new()
	check("fmod backend declines when absent", not fmod.is_available())
	check_eq("so a fallback was chosen", Audio.backend.backend_name() != "fmod", true)

	check("catalog loaded", Audio.catalog.size() > 20, "%d" % Audio.catalog.size())
	check("no catalog errors", Audio.catalog.errors.is_empty(),
			str(Audio.catalog.errors))

	# Core events the game actually raises.
	for id in [&"plant.place", &"sun.collect", &"zombie.die", &"mower.trigger",
			&"plant.food", &"level.win", &"level.lose"]:
		check("event '%s' exists" % id, Audio.has_event(id))

	# A mod can add an event, and replace one by reusing its id.
	check("mod added an event", Audio.has_event(&"example.burst"))
	var replaced := Audio.catalog.get_event(&"plant.shoot")
	check_eq("mod replaced a core event", replaced.source_mod, &"example_pack")
	check_eq("with its own path", replaced.fmod_path, "event:/ExamplePack/ReplacedShoot")

	# An unknown event must be survivable - a missing sound is not a crash.
	Audio.play(&"definitely.not.an.event")
	Audio.play_music(&"definitely.not.music")
	check("unknown events are harmless", true)

	# Every id the game raises must be in the catalog, or it is silent for a
	# reason nobody notices until playtest.
	var raised: Array[StringName] = []
	for path in _gd_files("res://core") + _gd_files("res://game"):
		var f := FileAccess.open(path, FileAccess.READ)
		if f == null:
			continue
		var text := f.get_as_text()
		f.close()
		for m in RegEx.create_from_string("Audio\\.play(?:_music)?\\(&\"([a-z0-9._]+)\"") \
				.search_all(text):
			var id := StringName(m.get_string(1))
			if not raised.has(id):
				raised.append(id)
	var missing: Array[StringName] = []
	for id in raised:
		if not Audio.has_event(id):
			missing.append(id)
	check("every raised event is in the catalog", missing.is_empty(), str(missing))
	print("        (%d distinct events raised by the game)" % raised.size())


# --- helpers -------------------------------------------------------------

func _make_board() -> Board:
	var b := Board.new()
	add_child(b)
	return b


## Waits for `seconds` of in-game time, which passes TIME_SCALE times faster.
func _wait_game_seconds(seconds: float) -> void:
	var elapsed := 0.0
	while elapsed < seconds:
		elapsed += get_process_delta_time()
		await get_tree().process_frame


func _report() -> void:
	print("\n" + "=".repeat(52))
	if _failures.is_empty():
		print("ALL %d CHECKS PASSED" % _checks)
	else:
		print("%d of %d CHECKS FAILED:" % [_failures.size(), _checks])
		for f in _failures:
			print("   - %s" % f)
	print("=".repeat(52))
	get_tree().quit(0 if _failures.is_empty() else 1)
