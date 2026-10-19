# Art

Extracted from the PVZGE build, **not committed**. Regenerate it with:

```sh
python3 tools/extract_prefabs.py <import dir> <res.config.json> art \
    plants/PeashooterPLANT plants/SunflowerPLANT plants/WallnutPLANT \
    plants/PotatoMinePLANT zombies/BasicZOMBIE armors/BasicConeARMOR \
    armors/BasicBucketARMOR projectiles/Pea0PRJ lawns/TutorialLAWN
```

`res.config.json` is `assets/resources/config.json` from the build, and
`<import dir>` is `assets/resources/import/`. Without `--native <dir>` the
images are pulled from the Docker image directly.

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
