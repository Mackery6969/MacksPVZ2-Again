# Audio

Nothing in the game calls FMOD, or Godot's audio, directly. Game code raises a
named event:

```gdscript
Audio.play(&"plant.place", plant.position)
Audio.play_music(&"music.tutorial")
```

A **backend** decides what that means. Backends are tried in order and the
first available one wins:

| Backend | When it is used |
|---|---|
| `fmod` | an FMOD integration is installed |
| `godot` | otherwise, playing each event's `stream` through Godot's audio |
| `silent` | last resort, so the game always runs |

The boot log says which one was picked:

```
[boot] audio: backend=godot events=26 playable=0
```

`playable` counts events that actually have an asset for the current backend.
`playable=0` means the wiring is in place and nothing is hooked up yet.

## Installing FMOD

**Versions must match.** FMOD Studio and FMOD Engine ship as a pair, and a
Studio project will not load into a different Engine runtime.

The Studio project in this workspace reports `Studio.02.03.00`, so the pair is:

| | Version |
|---|---|
| FMOD Studio | **2.03.00** (installed) |
| FMOD Engine | **2.03.00** (must match) |

1. Make an account at [fmod.com](https://www.fmod.com/download) and download
   **FMOD Engine 2.03.00** for Linux, matching the installed Studio.
2. Install a Godot integration. The GDExtension at
   [utopia-rise/fmod-gdextension](https://github.com/utopia-rise/fmod-gdextension)
   is the one to prefer: it targets FMOD 2.03 and installs as an addon, so
   Godot itself never has to be recompiled. The module-based integrations
   ([timoschwarzer](https://github.com/timoschwarzer/godot-fmod),
   [jordigulley](https://github.com/jordigulley/fmod_gd4)) require building
   Godot from source.
3. Drop the FMOD Engine libraries where the integration asks.
4. Export your banks from FMOD Studio to `res://audio/banks/`. The master bank
   and its `.strings` bank are both required before any event resolves.
   See "Running Studio under Proton" below if Studio is running through Wine.
5. Restart. `fmod_backend.gd` looks for the integration's singleton and takes
   over automatically; the boot log should now read `backend=fmod`.

**Compatibility warning:** this project runs Godot 4.7.2, and no FMOD
integration currently advertises 4.7 support - the GDExtension targets 4.4.
Expect to rebuild the extension against 4.7 headers. That is another reason to
prefer the GDExtension over a module: rebuilding an addon is much cheaper than
rebuilding the engine.

FMOD is free below its revenue threshold but the project must be registered.

### Running Studio under Proton

FMOD Studio here runs inside a Proton prefix, so it sees the filesystem through
Wine's drive mappings rather than Linux paths. The prefix maps `Z:` to `/`,
which makes the bank directory reachable from inside Studio as:

```
Z:\var\home\mackery\pvz-2\audio\banks
```

Set that as the build output in Studio so exporting lands banks directly in the
project. Without it they end up inside the prefix, where the game will not find
them - and the failure is silent, because a missing bank just means no event
resolves.

The Studio project itself lives at:

```
~/.local/share/Steam/steamapps/compatdata/4204175343/pfx/drive_c/
  users/steamuser/Documents/Music/PVZGE/PVZGE.fspro
```

That is inside a Proton prefix, which Steam can reset. Worth keeping the
project under version control somewhere outside the prefix.

## Building the Studio project

`tools/fmod_event_list.py` prints the events to create, generated from the
catalog so the two cannot drift:

```sh
python3 tools/fmod_event_list.py          # the base game's 26 events
python3 tools/fmod_event_list.py --mods   # include installed packs
python3 tools/fmod_event_list.py --check  # fails if any event lacks a path
```

The event paths imply the folder structure - `event:/Plants/Place` means a
`Plants` folder containing a `Place` event. Music events want a looping event;
the rest are one-shots.

## Event types, and what the game does not decide

**Sound effects are action sheets; music is a timeline.** An effect has
nothing to lay out in time - it fires, plays and stops - so a timeline it only
ever scrubs from zero is overhead for nothing. Music wants the timeline, for
markers, loop regions and transitions. `tools/fmod_action_sheets.py` rebuilds
generated effects as action sheets and leaves music alone.

**Variations are FMOD's job.** Several clips of one sound go into a single
multi instrument with its playlist set to shuffle, so FMOD picks and the game
never knows a sound has variations. There is no variation handling in the
catalog and there should not be.

**Volume and routing are the mixer's job.** The catalog's `music` flag means
only that a cue is *exclusive* - starting it stops whatever held the same slot
- which is a playback rule, not a level. It does not pick a bus. Buses, VCAs
and snapshots in Studio decide how loud anything is, and they do it better
than a flag here could. `bus` stays in the schema for the one case that needs
it: a settings slider reaching a named bus directly.

## The event catalog

Events live in `audio/events.json` beside a pack's other content:

```json
{"events": [
  {"id": "plant.place", "fmod": "event:/Plants/Place"},
  {"id": "music.tutorial", "fmod": "event:/Music/Tutorial", "music": true}
]}
```

- `fmod` is the FMOD Studio event path.
- `stream` is a Godot resource path, used by the `godot` backend as a stopgap.
  An event can carry both; each backend reads the one it understands.
- `music: true` routes through the music channel rather than a one-shot voice.

Author the events in FMOD Studio with paths matching the `fmod` fields, and the
game needs no changes.

## Adding sounds from a mod

A pack adds `audio/events.json` like any other content. A new id adds a sound;
reusing an existing id replaces that sound everywhere the game raises it:

```json
{"events": [
  {"id": "example.burst", "fmod": "event:/ExamplePack/BurstShot"},
  {"id": "plant.shoot",   "fmod": "event:/ExamplePack/ReplacedShoot"}
]}
```

Raise your own events from a mod component with `Audio.play(&"example.burst")`.

## Events the game raises

Plants: `plant.place` `plant.dig` `plant.eaten` `plant.shoot` `plant.lob`
`plant.explode` `plant.food`

Collectables: `sun.drop` `sun.collect` `plantfood.drop` `plantfood.collect`

Zombies: `zombie.spawn` `zombie.eat` `zombie.hit` `zombie.die`
`zombie.armor.break`

Board: `mower.trigger` `wave.start` `wave.huge`

UI and flow: `ui.seed.select` `ui.seed.refuse` `level.win` `level.lose`

Music: `music.tutorial` `music.frontlawn` `music.chooseseeds`

A test asserts that every id the game raises exists in the catalog, so a
mistyped event fails the suite rather than going quietly silent.

## How PVZGE's music is built

Recovered from the build's own asset paths (`music/inGame/<world>/`), not from
guesswork:

| Cue | Files | Notes |
|---|---|---|
| Lawn phase 1 | `P1_LP_<World>` | **no intro** - starts on the loop |
| Lawn phases 2-4 | `P2_Start_<World>` + `P2_LP_<World>`, ... | intro then loop |
| Choose your seeds | `CYS_Start_<World>` + `CYS_LP_<World>` | |
| One-shots | `VIC_` `LOSE_` `LEAVE_` `UB_` `ZBI_` `MG_<World>` | |

Twelve worlds follow that four-phase shape. The phases are what makes the
music dynamic: it escalates as a level progresses, which is the whole reason
to drive it from FMOD rather than swapping files. The game pushes the phase to
a global parameter named **`stage`** (1-4) as waves advance, so one event per
world covers all four.

**Front Lawn is the exception.** The `tutorial` world ships a single
`LP_Tutorial` and no phases at all, so its music is a static loop - the `stage`
parameter has nothing to switch. Worlds with phases arrive with the other
worlds.

`data/native/audio/music_map.json` holds the full per-world cue map.

### Loop points

Because `LP_Tutorial` is a pure loop file - no intro baked in - its loop region
is the **whole file**, `0` to `186.012`. A region that starts partway in clips
the opening and drops the tail, and the seam is audible on every repeat.

The rule generalises: a `_LP` file loops end to end, and an intro belongs in
the matching `_Start` file rather than in the head of the loop.

## Creating the events

`tools/fmod_create_events.py` writes any missing event into the Studio project,
generated from the catalog:

```sh
python3 tools/fmod_create_events.py "<path to PVZGE.fspro dir>" --dry-run
python3 tools/fmod_create_events.py "<path to PVZGE.fspro dir>"
```

It copies the object graph from an event Studio wrote itself, minus the
content, so what lands on disk is a shape Studio accepts. Existing events are
never touched, so it is safe to re-run as the catalog grows. Events are created
**unassigned to a bank**, matching how the reference event is stored - select
them in Studio and assign them to the Sound bank in one go.

SFX live under `event:/SFX/`, music under `event:/Music/`.

## Source material

PVZGE has no `sound/` asset namespace, so its clips look anonymous - addressed
only by UUID. They are not. Cocos packs store, alongside the member UUID list,
an instance array carrying each asset's original file name and duration,
aligned by position. Reading the two together recovers all of them:

```sh
python3 tools/build_audio_index.py <import dir> <config.json> audio_index.json
# named audio assets: 4187  (2857 distinct names)
```

That is where `plant1`, `shovel0`, `plantFoodCollect`, `hugewave`, `groan0`
and the rest come from - the game's own sounds under their own names, not
lookalikes.

`data/native/audio/pvzge_sources.json` maps each event to its clip, and
`tools/fmod_populate.py` ties catalog, source map and index together to pull
the clips out of the build and attach them:

```sh
python3 tools/fmod_populate.py "<project dir>" audio_index.json --dry-run
python3 tools/fmod_populate.py "<project dir>" audio_index.json
```

It skips events that already have audio, so it is safe to re-run.

### Variants

PVZGE ships numbered variants for most effects - `death0..3`, `groan0..n`,
`chew0..3`, `shovel0..3`. The source map takes the first of each; the rest are
staged under `Assets/SFX/_library/` (625 clips) for building multi-sounds in
Studio, which is what the variants are for. Nothing references that folder, so
it costs nothing in a build.
