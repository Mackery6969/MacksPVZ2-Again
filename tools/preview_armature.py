#!/usr/bin/env python3
"""Render an extracted armature to a PNG, without launching the game.

Mirrors what core/art/armature.gd does - bones in a parent chain, slots hung
off them, each slot's region placed by its own transform - so a wrong pivot or
draw order shows up here rather than in a playtest.

    python3 tools/preview_armature.py <art dir> <bundle> [armature] [out.png]
"""
import json, math, os, sys
from PIL import Image


def transform_of(raw):
    t = raw or {}
    return (float(t.get("x", 0.0)), float(t.get("y", 0.0)),
            math.radians(float(t.get("skX", 0.0))),
            float(t.get("scX", 1.0)), float(t.get("scY", 1.0)))


def compose(parent, local):
    """-> the child's world transform, parent applied to local."""
    px, py, prot, psx, psy = parent
    lx, ly, lrot, lsx, lsy = local
    cos, sin = math.cos(prot), math.sin(prot)
    x = px + (lx * psx) * cos - (ly * psy) * sin
    y = py + (lx * psx) * sin + (ly * psy) * cos
    return (x, y, prot + lrot, psx * lsx, psy * lsy)


def main():
    if len(sys.argv) < 3:
        print(__doc__)
        return 2
    art_dir, bundle = sys.argv[1], sys.argv[2]
    want = sys.argv[3] if len(sys.argv) > 3 else None
    out = sys.argv[4] if len(sys.argv) > 4 else "preview.png"

    index = json.load(open(os.path.join(art_dir, "_index.json"), encoding="utf-8"))
    entry = index[bundle]
    skeleton = json.load(open(os.path.join(art_dir, bundle, "skeleton.json"),
                              encoding="utf-8"))
    atlas = json.load(open(os.path.join(art_dir, bundle, "atlas.json"),
                           encoding="utf-8"))
    sheet = Image.open(os.path.join(art_dir, "_textures",
                                    entry["textures"][0])).convert("RGBA")
    regions = {r["name"]: r for r in atlas["SubTexture"]}

    name = want or entry.get("armature")
    armature = next(a for a in skeleton["armature"] if a.get("name") == name)

    rest = {}
    for bone in armature.get("bone", []):
        rest[bone["name"]] = (bone.get("parent"), transform_of(bone.get("transform")))
    world = {}

    def resolve(bone_name):
        if bone_name in world:
            return world[bone_name]
        parent, local = rest[bone_name]
        base = resolve(parent) if parent in rest else (0.0, 0.0, 0.0, 1.0, 1.0)
        world[bone_name] = compose(base, local)
        return world[bone_name]

    for bone_name in rest:
        resolve(bone_name)

    displays = {s["name"]: s for s in armature["skin"][0].get("slot", [])}
    canvas = Image.new("RGBA", (900, 900), (30, 32, 38, 255))
    origin = (450, 650)
    drawn = 0
    # Slot order is draw order: each one goes in front of the last.
    for slot in armature.get("slot", []):
        options = displays.get(slot["name"], {}).get("display", [])
        i = int(slot.get("displayIndex", 0))
        if i < 0 or i >= len(options):
            continue
        display = options[i]
        # DragonBones names the DISPLAY, and `path` names the texture when
        # the two differ - which is how one slot carries mouth/mouth_open.
        region = regions.get(display.get("path") or display.get("name"))
        if region is None:
            continue
        bone = world.get(slot.get("parent"), (0.0, 0.0, 0.0, 1.0, 1.0))
        x, y, rot, sx, sy = compose(bone, transform_of(display.get("transform")))

        w, h = int(region["width"]), int(region["height"])
        fw = float(region.get("frameWidth", w))
        fh = float(region.get("frameHeight", h))
        fx = float(region.get("frameX", 0))
        fy = float(region.get("frameY", 0))
        piece = sheet.crop((int(region["x"]), int(region["y"]),
                            int(region["x"]) + w, int(region["y"]) + h))
        if abs(sx - 1.0) > 0.01 or abs(sy - 1.0) > 0.01:
            piece = piece.resize((max(1, int(w * abs(sx))), max(1, int(h * abs(sy)))))
        if rot:
            piece = piece.rotate(-math.degrees(rot), expand=True,
                                 resample=Image.BICUBIC)
        # Same pivot the runtime uses: the display is centred on the UNTRIMMED
        # frame, so the trimmed art sits off-centre by this much.
        ox = -fx + (w - fw) * 0.5
        oy = -fy + (h - fh) * 0.5
        cx = origin[0] + x + ox
        cy = origin[1] + y + oy
        canvas.alpha_composite(piece, (int(cx - piece.width / 2),
                                       int(cy - piece.height / 2)))
        drawn += 1

    canvas.save(out)
    print("%s / %s: %d slots drawn -> %s" % (bundle, name, drawn, out))
    return 0


if __name__ == "__main__":
    sys.exit(main())
