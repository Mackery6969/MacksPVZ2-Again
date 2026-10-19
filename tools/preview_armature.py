#!/usr/bin/env python3
"""Render an extracted armature to a PNG, without launching the game.

Mirrors what core/art/armature.gd does - bones in a parent chain, slots hung
off them, each slot's region placed by its own transform - so a wrong pivot or
draw order shows up here rather than in a playtest.

    python3 tools/preview_armature.py <art dir> <bundle> [armature] [out.png] \
        [--anim NAME] [--frames N]

With `--anim` it samples that animation the way the runtime does, which is
where the pivots and the parent-scale rule actually get tested - a setup pose
can look right while every animated frame is wrong.
"""
import json, math, os, sys
from PIL import Image


def transform_of(raw):
    t = raw or {}
    return (float(t.get("x", 0.0)), float(t.get("y", 0.0)),
            math.radians(float(t.get("skX", 0.0))),
            float(t.get("scX", 1.0)), float(t.get("scY", 1.0)))


def compose(parent, local):
    """-> the child's world transform, parent applied to local.

    The parent's scale moves the child but does not shear it. Godot's own
    node parenting does shear it, which is why the runtime composes this
    itself rather than hanging Node2Ds off each other.
    """
    px, py, prot, psx, psy = parent
    lx, ly, lrot, lsx, lsy = local
    cos, sin = math.cos(prot), math.sin(prot)
    x = px + (lx * psx) * cos - (ly * psy) * sin
    y = py + (lx * psx) * sin + (ly * psy) * cos
    return (x, y, prot + lrot, psx * lsx, psy * lsy)


def timeline(frames, key_a, key_b, fallback, rate):
    """-> [(time, a, b)] from DragonBones' duration-per-frame lists."""
    out, at = [], 0.0
    for f in frames or []:
        out.append((at / rate, float(f.get(key_a, fallback)),
                    float(f.get(key_b, fallback)) if key_b else 0.0))
        at += float(f.get("duration", 0))
    return out


def sample(track, time, fallback):
    if not track:
        return fallback
    if time <= track[0][0] or len(track) == 1:
        return (track[0][1], track[0][2])
    for (ta, aa, ab), (tb, ba, bb) in zip(track, track[1:]):
        if time < tb:
            t = 0.0 if tb <= ta else (time - ta) / (tb - ta)
            return (aa + (ba - aa) * t, ab + (bb - ab) * t)
    return (track[-1][1], track[-1][2])


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
    rate = float(armature.get("frameRate", skeleton.get("frameRate", 30)))

    anim_name = None
    if "--anim" in sys.argv:
        anim_name = sys.argv[sys.argv.index("--anim") + 1]
    count = int(sys.argv[sys.argv.index("--frames") + 1]) if "--frames" in sys.argv else 1
    tracks, duration = {}, 0.0
    if anim_name:
        anim = next(a for a in armature["animation"] if a["name"] == anim_name)
        duration = float(anim.get("duration", 0)) / rate
        for b in anim.get("bone", []):
            tracks[b["name"]] = (
                timeline(b.get("translateFrame"), "x", "y", 0.0, rate),
                timeline(b.get("rotateFrame"), "rotate", "", 0.0, rate),
                timeline(b.get("scaleFrame"), "x", "y", 1.0, rate))

    rest = {}
    for bone in armature.get("bone", []):
        rest[bone["name"]] = (bone.get("parent"), transform_of(bone.get("transform")))

    displays = {s["name"]: s for s in armature["skin"][0].get("slot", [])}
    strip = Image.new("RGBA", (420 * count, 520), (30, 32, 38, 255))

    for step in range(count):
        time = (duration * step / count) if duration else 0.0
        world = {}

        def resolve(bone_name):
            if bone_name in world:
                return world[bone_name]
            parent, local = rest[bone_name]
            lx, ly, lrot, lsx, lsy = local
            if bone_name in tracks:
                tr, ro, sc = tracks[bone_name]
                dx, dy = sample(tr, time, (0.0, 0.0))
                dr, _ = sample(ro, time, (0.0, 0.0))
                mx, my = sample(sc, time, (1.0, 1.0))
                local = (lx + dx, ly + dy, lrot + math.radians(dr), lsx * mx, lsy * my)
            base = resolve(parent) if parent in rest else (0.0, 0.0, 0.0, 1.0, 1.0)
            world[bone_name] = compose(base, local)
            return world[bone_name]

        for bone_name in rest:
            resolve(bone_name)
        frame = render(armature, displays, regions, sheet, world)
        strip.paste(frame, (420 * step, 0))

    strip.save(out)
    print("%s / %s%s: -> %s" % (bundle, name,
          (" " + anim_name) if anim_name else "", out))
    return 0


def render(armature, displays, regions, sheet, world, size=(420, 520),
           origin=(210, 400), background=(30, 32, 38, 255)):
    canvas = Image.new("RGBA", size, background)
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
    return canvas


if __name__ == "__main__":
    sys.exit(main())
