# Modding Guide

Everything in this game is data. Every entity and level is a file, and every
behaviour is a named component you can replace with your own GDScript. A pack
never has to copy content it does not change.

Definitions can be authored two ways, and both load identically:

- **`.tres`** - a typed Godot resource, edited in the inspector with real
  fields, dropdowns and validation.
- **`.json`** - plain text, easy to diff and generate, and what the PVZGE
  importer emits.

Use whichever suits you; a pack can mix them freely.

## Pack layout

A pack is a folder under `mods/`:

```
mods/my_pack/
  mod.json            id, name, version
  zombies/*.json      add a zombie, or replace one by reusing its id
  plants/*.json       .tres works anywhere .json does
  graves/*.json
  objects/*.json
  projectiles/*.json
  armors/*.json
  levels/*.json
  campaigns/*.json    ordered runs of levels
  audio/events.json   add or replace sounds
  components/*.gd     new behaviours, or overrides of built-in ones
  init.gd             optional startup hook
```

## The four entity kinds

Keeping these separate matters, because conflating them is what breaks level
generation:

| Kind | What it is | Notes |
|---|---|---|
| **plant** | what the player grows | the only kind that belongs in a normal seed bank |
| **zombie** | the opposition | can be charmed to fight for the player |
| **grave** | destroyable board object | plants can break it; may fire grid-item events such as summoning |
| **object** | everything else on the grid | slider and trap tiles, liquids, mold, and the zombie-side potions |

PVZGE files evil potions (`zombiepotion_*`) under plants. They are objects
here, so they can never leak into a seed bank or a plant roll.

Only `mod.json` is required, and every folder is optional. Drop the folder into
`mods/` and it loads on the next run.

## Load order

Order is declared in `mods/load_order.json`, **highest priority first**, with
the base game implicitly at the bottom:

```json
{ "order": ["my_overrides", "some_content_pack"],
  "disabled": ["pack_i_am_not_using"] }
```

A pack higher in the list wins over everything below it. Packs you do not list
are appended underneath the listed ones, alphabetically. Packaged `.pck` files
in `mods/` are mounted before folders and load the same way.

### Turning a pack off

A pack named in `disabled`, or whose own `mod.json` says `"enabled": false`,
stays installed and listed but contributes no data and no scripts. This
matters for packs that override built-in behaviour: such a pack changes the
base game for everything using that component, so it should usually ship
disabled and be opted into. `mods/example_override/` is exactly that case.

## Adding a zombie

```json
{
 "id": "sprinter",
 "extends": "normal",
 "stats": { "toughness": 120, "speed": 0.55, "eat_dps": 80, "wave_cost": 150 },
 "tags": { "add": ["fast"], "remove": ["swallowable", "grabbable"] }
}
```

`extends` names an archetype (`normal`, `gargantuar`, `zomboss`) or another
zombie, and you inherit its stats, tags and components. `tags.add` and
`tags.remove` are applied on top, so you only write the differences.

A `.tres` works the same way, except that it is already complete when it
loads - its parent only fills in what the resource left unset, rather than
overwriting what you authored. `mods/example_pack/zombies/brute.tres` is a
working example.

### Charmed zombies

A zombie's `allegiance` decides which way it walks and what it attacks.
Hypnotised (zomboid) zombies walk away from the house, attack hostile zombies,
are ignored by plant weapons, and do not count toward the level's remaining
zombies. Call `zombie.charm()` to switch sides at runtime - no respawn needed.

### Tags, and why they matter

A zombie declares **what it is**. A plant declares **what it does**. Tags are
the contract between them.

The original game stored interactions the other way round, as plant-named
booleans on every zombie (`CannotBeSwallowedByChomper`,
`CannotBeGrabbedByPtero`, and 23 more). Adding one plant meant editing hundreds
of zombie entries. Here, Chomper asks for the `swallowable` tag, and any zombie
that has it can be swallowed. **Your new plant needs zero edits to zombie
files** - ask for a tag that already exists, or invent your own and tag the
zombies you ship.

Capability tags currently in use include `swallowable`, `grabbable`, `tossable`,
`draggable`, `hypnotizable`, `knockbackable`, `shrinkable`, `transformable`,
`pushable`, `carriable`, `gummable`, `chompable`, `divertable`, `attractable`,
`sporeable`, `flickable`, `lane_movable`, and `plantfood_carrier`. Descriptive
tags such as `metal` and `deep_water` sit alongside them.

## Adding a plant

```json
{
 "id": "splitpea_mk2",
 "family": "Peashooter",
 "stats": { "sun_cost": 175, "toughness": 300, "cooldown": 7 },
 "components": [
  { "type": "burst_shooter", "projectile": "pea", "interval": 2.0, "burst": 3 }
 ]
}
```

`stats` drive the seed packet as well as the plant: `sun_cost` is the price,
`cooldown` is the recharge in seconds, and `cooldown_from` is the share of
that recharge the packet starts with (1 is ready immediately, 0 means waiting
a full cycle before first use). A level listing the
`SeedPacketHalfTimeModule` feature halves every recharge.

`components` is the interesting part: each entry names a behaviour and
configures it. Built-in types are `shooter`, `lobber`, `sun_producer`, `melee`,
`explosive`, `blocker`, `armor`, `hit_rect` and `attack_rect`.

### Zombie seed packets

A seed bank is not plant-only. Setting `"kind": "zombie"` on a level's seedbank
hands the player zombies instead, which is how an I-Zombie style level works;
individual entries can override the kind too. Placement cost comes from the
entity's own `sun_cost`.

```json
"seedbank": { "mode": "chooser", "kind": "zombie",
			  "preset": ["tutorial", "tutorial_armor1"] }
```

Zombies placed this way drop into the lane and walk from there, so unlike a
plant they do not occupy their cell.

One thing is deliberately not configurable: **every sun is worth
`SunToken.VALUE` (50)**. `sun_producer` controls only the timing. The original
game's per-plant `SunValue` is kept in each plant's `extra` block for
reference, but nothing reads it - to change the amount, change the constant.
Sun is collected by hovering the cursor over it, not by clicking.

## Changing existing content

Reuse the id. A file at `mods/my_pack/zombies/tutorial.json` replaces the base
`tutorial` zombie outright, as long as your pack sits above the base game in
the load order (it always does).

## Adding a behaviour

Drop a `.gd` file in `components/`. **The filename is the component type**, so
`components/burst_shooter.gd` registers the type `burst_shooter`.

```gdscript
extends EntityComponent

var _cooldown: float = 0.0

func setup() -> void:
	_cooldown = float(cfg(&"interval", 2.0))

func _process(delta: float) -> void:
	if host.is_dead:
		return
	_cooldown -= delta
	if _cooldown <= 0.0:
		host.board.spawn_projectile(&"pea", host.row, host.position, host)
		_cooldown = float(cfg(&"interval", 2.0))
```

`host` is the plant or zombie, `cfg()` reads from the component's JSON entry,
and `host.board` is the lawn.

## Completely rewriting what a plant does

Name your file after an existing component type. A pack shipping
`components/sun_producer.gd` replaces the built-in one, and **every plant using
that component now runs your code** - no plant JSON and no core file changes.

To rewrite a single plant instead of all of them, give it a component type only
it uses, and point its JSON at that:

```json
{ "id": "meteorflower",
  "components": [{ "type": "my_meteor_behaviour", "damage": 900 }] }
```

The override is announced at startup so you can confirm it took effect:

```
[mod] 'example_override' overrides component 'sun_producer' (was from 'base')
```

Because this replaces the behaviour for *every* plant using that component,
`example_override` ships disabled. Remove it from `disabled` in
`load_order.json` to see it take over.

## Adding a level

```json
{
 "id": "example_showdown",
 "name": "Sprinter Showdown",
 "stage": "TutorialStage",
 "seedbank": { "mode": "chooser", "selection": "preset",
               "preset": ["peashooter", "sunflower"] },
 "waves": [
  { "kind": "spawn", "zombies": [ { "type": "tutorial", "row": 3 } ] },
  { "kind": "spawn", "zombies": [ { "type": "sprinter", "row": 2 } ] }
 ],
 "wave_settings": { "count": 2, "flag_interval": 2 }
}
```

Rows are 1-based; omit `row` to spawn in a random lane. `plantable_rows`
restricts where the player may plant - Tutorial 1 uses `[3]` to confine the
player to the middle lane, and locked lanes are dimmed on the board. Use
`"mode": "conveyor"` with a `plants` list for a conveyor level. A wave that
needs several things at once uses `{"kind": "multi", "actions": [...]}`.

## Campaigns

A campaign is an ordered list of levels. Clearing one loads the next; failing
one repeats it. Finishing the last shows the completion message.

```json
{
 "id": "tutorial",
 "name": "Player's House",
 "completion_message": "Front Lawn complete!",
 "levels": ["tutorial_1", "tutorial_2", "tutorial_3", "tutorial_4"]
}
```

Because a campaign is just data, a pack can ship its own, or replace an
existing one by reusing its id to splice levels in:

```json
{
 "id": "tutorial",
 "name": "Player's House",
 "levels": ["tutorial_1", "my_pack_interlude", "tutorial_2",
            "tutorial_3", "tutorial_4"]
}
```

A level does not have to belong to a campaign. Setting `start_level` on the
main scene jumps straight to one, which is useful while building it; if that
level is in a campaign, progression continues from there.

## Plant food

Zombies whose data allows it (`plantfood_carrier`) can be marked as carriers by
a wave's `plantfood` count. Killing one drops a pickup, collected by hovering
like sun. Feeding a plant calls `on_plantfood()` on each of its components, and
the food is only spent if something responded - so feeding a plant with no
boosted behaviour costs nothing.

Give a component a boosted behaviour by overriding the hook:

```gdscript
func on_plantfood() -> bool:
	for z in host.board.hostile_zombies_in_row(host.row):
		z.take_damage(500.0, host)
	return true
```

Built-in boosts: `shooter` unloads a burst, `lobber` rains a volley,
`sun_producer` drops a handful of sun, `melee` lands a flurry, `explosive`
detonates immediately, and `blocker` repairs to full.

## Lawn mowers

A level whose `features` list ends in `Mowers` - `TutorialMowers`,
`FrontLawnMowers`, `ModernMowers` - parks one mower per lane. A zombie reaching
the house sets it off, clearing that lane. Each lane gets exactly one, so the
next zombie through a spent lane ends the level. Levels without a mower feature
lose on the first zombie through.

## Controls

Seed slots, plant food, the shovel and fast forward all come from the project's
InputMap, so they can be rebound - including to a controller - without code
changes. Conveyor levels have more slots and use the `Slot N (Convayor)`
actions from slot 5 upward. `Previous Slot` and `Next Slot` cycle the
selection, skipping packets that have not recharged.

## Level features

A level's `features` list names optional modules. The one wired up so far is
`FastSunDropper`, which halves the gap between sky sun and is what the early
tutorial levels use to keep the player supplied, and
`SeedPacketHalfTimeModule`, which halves seed recharge times. Unrecognised
features are ignored rather than fatal, so a level using a module that is not
built yet still plays.

## Conveyor levels

A level whose seedbank is `"mode": "conveyor"` hands out free packets on a
belt instead of fixed slots. Nothing costs sun and nothing recharges - a packet
is either on the belt or it is not, and placing one takes it off.

```json
"seedbank": {
 "mode": "conveyor",
 "plants": [{"type": "peashooter", "weight": 100, "max": 4}],
 "drop_delay": [{"delay": 3, "max_packets": 0},
				{"delay": 9, "max_packets": 4}],
 "speed": [{"speed": 100, "max_packets": 0}]
}
```

`weight` is the pick chance and `max` caps how many of that plant sit on the
belt at once (`null` for unlimited). `drop_delay` is keyed by how full the belt
is, so it refills quickly when empty and slows as it fills. A wave action of
kind `conveyor` with `add`/`remove` changes the pool mid-level.

## Audio

Sounds are named events, not file paths, so they survive a change of audio
backend. See `docs/AUDIO.md`.

## The init hook

For setup data cannot express, add `init.gd`:

```gdscript
extends RefCounted

func initialize(ctx: Dictionary) -> void:
	var data = ctx["data"]
	print("zombies tagged fast: %d" % data.query(&"zombie", [&"fast"]).size())
```

It runs after every pack's data has loaded, lowest priority first. `ctx` carries
`mod`, `data` and `components`.

## Checking your work

Startup prints what loaded and what got overridden. Errors are collected rather
than fatal, so a broken file degrades instead of crashing the game:

```
[boot] zombies=474 plants=218 levels=5 mods=[base, example_pack] errors=0
[boot] components: 10 types { base: 8, example_pack: 2 }
```

`mods/example_pack/` is a working reference covering every case above.
