#!/usr/bin/env python3
"""Pull DragonBones rigs out of the PVZGE build by the rig's own name.

`extract_prefabs.py` starts from a named prefab, which covers plants, zombies,
lawns and mowers. Everything else the game animates - the sun, the sun
counter, the shovel, the plant food slots, seed packet art, the planting dirt -
lives in a scene or in a resource prefab that bundles dozens of them, and
none of it has a name in `config.json`. What it does have is the rig's own
name: every DragonBones export carries one (`SunAnimate`, `Shovel`,
`PlantFoodSlot`), so this goes looking for that instead.

    python3 tools/extract_rigs.py <import dir> <res.config.json> <out dir> \\
        [--native <dir>] NAME[:ARMATURE] ...

`NAME` is the skeleton's name. A few names are used by more than one export -
there are two `SeedPacker`s, one for plant packets and one for zombie ones -
and `:ARMATURE` picks the export that has that armature; the bundle is then
called `rigs_<NAME>_<ARMATURE>` so both can be extracted side by side.
With no NAME, every rig in the build is listed instead.

Output matches extract_prefabs.py - `<out>/rigs_<NAME>/skeleton.json`,
`atlas.json`, the texture under `_textures/` - and is merged into the same
`_index.json`, so the game's art library finds both the same way.
"""
import json, os, sys

sys.path.insert(0, os.path.dirname(os.path.abspath(__file__)))
from extract_prefabs import (  # noqa: E402
    decode_uuid, embedded, fetch_native, native_listing, region_coverage,
    PNG_MAGIC)


def scan(import_dir):
    """-> [(skeleton, atlases, file uuids)] for every rig in the build.

    Each import file is read once. A pack holds many assets and shares one
    dependency list, so the uuids that might be a rig's texture are that
    list, not anything the rig names - the atlas says `SunAnimate_tex.png`,
    which is not a filename that exists.
    """
    found = []
    for sub in sorted(os.listdir(import_dir)):
        d = os.path.join(import_dir, sub)
        if not os.path.isdir(d):
            continue
        for fname in sorted(os.listdir(d)):
            if not fname.endswith(".json"):
                continue
            path = os.path.join(d, fname)
            try:
                data = json.load(open(path, encoding="utf-8"))
            except (json.JSONDecodeError, UnicodeDecodeError):
                continue
            skeletons = [s for s in embedded(data, "armature")
                         if isinstance(s.get("armature"), list)]
            if not skeletons:
                continue
            atlases = embedded(data, "SubTexture")
            uuids = []
            if isinstance(data, list) and len(data) > 1 and isinstance(data[1], list):
                uuids = [decode_uuid(u) for u in data[1] if isinstance(u, str)]
            for ske in skeletons:
                found.append((ske, atlases, uuids, fname))
    return found


def armature_names(skeleton):
    return [a.get("name") for a in skeleton.get("armature", []) if isinstance(a, dict)]


def displayed_regions(skeleton):
    """-> every image name the rig's skins display."""
    names = set()
    for arm in skeleton.get("armature", []):
        for skin in arm.get("skin", []) or []:
            for slot in skin.get("slot", []) or []:
                for display in slot.get("display", []) or []:
                    if display.get("type", "image") in ("image", "mesh"):
                        names.add(display.get("path", display.get("name")))
    names.discard(None)
    return names


def pick_atlas(skeleton, atlases):
    """The atlas that actually holds this rig's art.

    A pack carries several atlases, sometimes two with the rig's own name at
    different sizes. The right one is whichever covers most of the images the
    rig displays.
    """
    wanted = displayed_regions(skeleton)
    best, best_score = None, -1
    for atlas in atlases:
        have = {r.get("name") for r in atlas.get("SubTexture", []) if isinstance(r, dict)}
        score = len(wanted & have)
        if atlas.get("name") == skeleton.get("name"):
            score += 0.5
        if score > best_score:
            best, best_score = atlas, score
    return best


def png_size(path):
    with open(path, "rb") as fh:
        head = fh.read(24)
    if len(head) < 24 or head[:8] != PNG_MAGIC:
        return None
    return int.from_bytes(head[16:20], "big"), int.from_bytes(head[20:24], "big")


def pick_texture(atlas, uuids, native_dir, listing):
    """-> the uuid of the image this atlas cuts up, or None.

    The dependency list is shared by everything in a pack, so a size match
    alone can leave several images; the one with art where the atlas says art
    is wins.
    """
    want = (atlas.get("width"), atlas.get("height"))
    hits = []
    for uuid in dict.fromkeys(uuids):
        rel = "%s/%s.png" % (uuid[:2], uuid)
        if rel not in listing:
            continue
        if native_dir and png_size(os.path.join(native_dir, rel)) == want:
            hits.append(uuid)
    if len(hits) <= 1:
        return hits[0] if hits else None
    scored = []
    for uuid in hits:
        path = os.path.join(native_dir, uuid[:2], uuid + ".png")
        scored.append((region_coverage(open(path, "rb").read(), atlas), uuid))
    scored.sort(reverse=True)
    return scored[0][1]


def main():
    if len(sys.argv) < 4:
        print(__doc__)
        return 2
    import_dir, _config, out_root = sys.argv[1:4]
    native_dir = None
    if "--native" in sys.argv:
        native_dir = sys.argv[sys.argv.index("--native") + 1]
    wanted = [a for a in sys.argv[4:] if not a.startswith("--") and a != native_dir]

    rigs = scan(import_dir)
    by_name = {}
    for entry in rigs:
        by_name.setdefault(entry[0].get("name"), []).append(entry)

    if not wanted:
        print("%d rigs. Pass NAME[:ARMATURE] to extract one:" % len(rigs))
        for name in sorted(by_name, key=str):
            for ske, _, _, fname in by_name[name]:
                print("   %-24s %-16s %s" % (name, fname, ", ".join(map(str, armature_names(ske)))[:90]))
        return 0
    if not native_dir:
        print("--native <dir> is required: point it at assets/resources/native")
        return 2

    os.makedirs(out_root, exist_ok=True)
    media_dir = os.path.join(out_root, "_textures")
    os.makedirs(media_dir, exist_ok=True)
    listing = native_listing(native_dir)
    index_path = os.path.join(out_root, "_index.json")
    index_out = {}
    if os.path.exists(index_path):
        index_out = json.load(open(index_path, encoding="utf-8"))

    failed = 0
    for spec in wanted:
        name, _, hint = spec.partition(":")
        candidates = by_name.get(name, [])
        if hint:
            candidates = [c for c in candidates if hint in armature_names(c[0])]
        # Identical copies of one rig turn up in several packs; only genuinely
        # different exports make a name ambiguous.
        distinct = {json.dumps(c[0], sort_keys=True) for c in candidates}
        if not candidates:
            print("   !! %-30s no rig by that name" % spec)
            failed += 1
            continue
        if len(distinct) > 1:
            print("   !! %-30s %d different rigs share this name; add :ARMATURE"
                  % (spec, len(distinct)))
            failed += 1
            continue
        skeleton, atlases, uuids, fname = candidates[0]
        ambiguous = len({json.dumps(c[0], sort_keys=True) for c in by_name[name]}) > 1
        slug = "rigs_%s" % name + ("_%s" % hint if hint and ambiguous else "")
        atlas = pick_atlas(skeleton, atlases)
        if atlas is None:
            print("   !! %-30s no atlas alongside it in %s" % (spec, fname))
            failed += 1
            continue
        texture = pick_texture(atlas, uuids, native_dir, listing)
        dest = os.path.join(out_root, slug)
        os.makedirs(dest, exist_ok=True)
        json.dump(skeleton, open(os.path.join(dest, "skeleton.json"), "w", encoding="utf-8"),
                  ensure_ascii=False, separators=(",", ":"))
        json.dump(atlas, open(os.path.join(dest, "atlas.json"), "w", encoding="utf-8"),
                  ensure_ascii=False, separators=(",", ":"))
        entry = {
            "path": "rig:%s" % spec,
            "source": fname,
            "skeleton": name,
            "frame_rate": skeleton.get("frameRate"),
            "armature": armature_names(skeleton)[0],
            "armatures": [
                {"name": a.get("name"), "bones": len(a.get("bone", [])),
                 "slots": len(a.get("slot", [])),
                 "animations": [an.get("name") for an in a.get("animation", [])]}
                for a in skeleton.get("armature", []) if isinstance(a, dict)],
            "atlas": {"name": atlas.get("name"), "image": atlas.get("imagePath"),
                      "size": [atlas.get("width"), atlas.get("height")],
                      "regions": len(atlas.get("SubTexture", []))},
        }
        if texture:
            written = fetch_native([texture], media_dir, native_dir, listing)
            if texture in written:
                entry["textures"] = [written[texture]]
        if "textures" not in entry:
            print("   !! %-30s no image matches the atlas size %s"
                  % (spec, entry["atlas"]["size"]))
            failed += 1
        index_out[slug] = entry
        print("   %-30s -> %s (%s)" % (spec, slug, ", ".join(
            a["name"] for a in entry["armatures"])[:70]))

    json.dump(index_out, open(index_path, "w", encoding="utf-8"), indent=1,
              ensure_ascii=False)
    return 1 if failed else 0


if __name__ == "__main__":
    sys.exit(main())
