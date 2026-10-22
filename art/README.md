# Art

Extracted from the PVZGE build, **not committed**. Regenerate it with:

```sh
python3 tools/extract_prefabs.py <import dir> <res.config.json> art --native <native dir> \
    plants/PeashooterPLANT plants/SunflowerPLANT plants/WallnutPLANT \
    plants/PotatoMinePLANT zombies/BasicZOMBIE armors/BasicConeARMOR \
    armors/BasicBucketARMOR projectiles/Pea0PRJ lawns/ MowerPRJ
python3 tools/extract_rigs.py <import dir> <res.config.json> art --native <native dir> \
    SunAnimate SunSlot Shovel PlantFoodSlot SeedPacker:Card Particles
```

The first pulls named prefabs - entities, every world's lawn (`lawns/`) and
every world's mower (`MowerPRJ`). The second pulls rigs by their DragonBones
name, for the art that lives in scenes and resource packs instead: the sun,
the sun counter, the shovel, the plant food slots, the seed packet art and the
planting dirt. Run it with no names to list every rig in the build. Both merge
into the same `_index.json`, so either can be re-run on its own.

`res.config.json` is `assets/resources/config.json` from the build, and
`<import dir>` is `assets/resources/import/` and `<native dir>`
`assets/resources/native/` - from the web build, or a desktop build unpacked
with `tools/extract_desktop.py`. Without `--native <dir>`, extract_prefabs.py
pulls the images from the Docker image directly; extract_rigs.py needs it.

## Layout

```
art/
  _index.json            what each prefab resolved to: skeleton, armature, atlas, texture
  _textures/<uuid>.png   the atlas images, shared between entities
  <bundle>_<Name>/
    skeleton.json        DragonBones armatures, bones, slots, animations
    atlas.json           the regions, in the texture named by _index.json
```

One texture serves many entities: the basic zombie and both its armors all
read `ZombieAnimate_tex.png`, which is the point of the shared rigs.

## Copyright

The art belongs to **PopCap Games**, **PopCap Games (Shanghai)** and
**Electronic Arts**, exactly as the audio does - see `Music/COPYRIGHT.md` for
the full position. Nothing here is licensed by this repository, which is why
it is generated rather than committed. If this directory should be versioned,
a separate repository added as a submodule is the shape the music already
uses.
