# DragonBones import (not built yet)

Parked deliberately: the game runs on placeholder art so the engine and mod
architecture can be finished first. This note records what the job involves so
it can be picked up cleanly.

## What PVZGE ships

- **43 armatures / 577 animations**, confirmed by extraction. The big shared
  rigs carry most of the content: `ZombieAnimate` has 177 bones and 191 slots,
  `PlantAnimate` 23 bones and 21 slots.
- Skeleton data is **not** a standalone file. Cocos stores it as an escaped
  JSON string inside the serialized asset envelope under
  `assets/resources/import/`, so it has to be parsed out of the string rather
  than read directly - `tools/extract_dragonbones.py` handles this.
- **619 atlas PNGs** in `assets/resources/native/`, which holds the raw media
  (mp3/png/ttf) while `import/` holds the serialized metadata. Pairing an
  armature to its atlas means following the envelope's `_dragonAtlasAsset`
  reference - this is the remaining piece of the extractor.
- Animation is used by **112 of the 654 source modules**, so essentially every
  visible entity depends on it.

Extraction of skeletons works today; atlas pairing does not.

Extract them with:

```sh
python3 tools/extract_dragonbones.py <out_dir>
```

## Mapping to Godot

DragonBones and Godot line up reasonably well:

| DragonBones        | Godot                                    |
|--------------------|------------------------------------------|
| armature           | `Node2D` root + `AnimationPlayer`        |
| bone               | `Bone2D` under a `Skeleton2D`            |
| slot + display     | `Sprite2D` with an `AtlasTexture`        |
| animation timeline | `Animation` tracks on the bone transforms|
| ffd / mesh deform  | `Polygon2D` with `bones` weights         |

## Two viable approaches

**Offline conversion** (recommended). A Python or GDScript `EditorImportPlugin`
that turns each armature into a `PackedScene` with baked `Animation`
resources. Fast at runtime, inspectable in the editor, and animations become
ordinary Godot resources. Downside: modders adding new armatures must re-run
the importer.

**Runtime player.** A custom `Node2D` that parses DragonBones JSON and draws it
directly. Keeps armatures hot-swappable for modders, which suits this project's
goals, but is more work and risks GDScript performance with many entities.

A sensible middle path is offline conversion for shipped content plus a runtime
loader for mod-supplied armatures.

## Ordering note

Whatever the approach, entity visuals should stay behind the `Character`
`_draw` seam that placeholders use now, so swapping art in does not touch any
behaviour code.
