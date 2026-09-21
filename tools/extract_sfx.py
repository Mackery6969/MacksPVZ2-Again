#!/usr/bin/env python3
"""Pull the sound effects out of PVZGE prefabs.

PVZGE has no `sound/` asset namespace - every effect is an AudioClip hanging
off a prefab, addressed by UUID. This walks the Cocos asset index to recover
them with usable names:

    prefab path -> pack -> dependency uuids -> the .mp3 files among them

Field names on the prefab (`shootSound`, `foodSound`, ...) are recovered too
and reported, but Cocos does not store which dependency each field points to in
a form this reads, so files are named by prefab and index. Durations are
included because they usually make the mapping obvious - a 0.4s clip next to a
2.5s one is a shot and a plant-food cue.

    python3 tools/extract_sfx.py <out_dir> [prefab ...]
"""
import json, os, re, subprocess, sys

IMAGE = "gaozih/pvzge:latest"
RES = "/usr/share/nginx/html/assets/resources"
B64 = 'ABCDEFGHIJKLMNOPQRSTUVWXYZabcdefghijklmnopqrstuvwxyz0123456789+/'
VALUES = {c: i for i, c in enumerate(B64)}
HEX = '0123456789abcdef'

# Front Lawn content, by prefab path in the build.
DEFAULT_PREFABS = [
    "plants/PeashooterPLANT", "plants/SunflowerPLANT", "plants/WallnutPLANT",
    "plants/PotatoMinePLANT", "plants/CabbagePultPLANT",
    "zombies/BasicZOMBIE", "zombies/BasicFlagZOMBIE", "zombies/ConeheadZOMBIE",
    "zombies/BucketheadZOMBIE", "projectiles/PeaPRJ",
]


def decode_uuid(short):
    base = short.split('@')[0]
    if len(base) != 22:
        return short
    out = [base[0], base[1]]
    for i in range(2, 22, 2):
        lhs, rhs = VALUES[base[i]], VALUES[base[i + 1]]
        out += [HEX[lhs >> 2], HEX[((lhs & 3) << 2) | (rhs >> 4)], HEX[rhs & 0xF]]
    h = ''.join(out)
    return f"{h[:8]}-{h[8:12]}-{h[12:16]}-{h[16:20]}-{h[20:32]}"


def sh(script):
    return subprocess.run(["docker", "run", "--rm", IMAGE, "sh", "-c", script],
                          capture_output=True).stdout


def load_config(cache):
    if not os.path.exists(cache):
        with open(cache, "wb") as fh:
            fh.write(sh(f"cat {RES}/config.json"))
    return json.load(open(cache, encoding="utf-8"))


def main():
    if len(sys.argv) < 2:
        print(__doc__)
        return 2
    out_dir = sys.argv[1]
    wanted = sys.argv[2:] or DEFAULT_PREFABS
    os.makedirs(out_dir, exist_ok=True)

    cfg = load_config(os.path.join(out_dir, "_config.json"))
    paths, uuids, packs = cfg["paths"], cfg["uuids"], cfg.get("packs", {})

    # path -> asset index, and index -> pack that carries it
    by_path = {v[0]: int(k) for k, v in paths.items()}
    pack_of = {}
    for pack, members in packs.items():
        for idx in members:
            pack_of[idx] = pack

    report = {}
    for prefab in wanted:
        idx = by_path.get(prefab)
        if idx is None:
            print(f"  !! no prefab '{prefab}'", file=sys.stderr)
            continue
        # Most assets are bundled into packs; a few sit in their own file
        # under their full uuid.
        pack = pack_of.get(idx)
        if pack is not None:
            raw = sh(f"cat {RES}/import/{pack[:2]}/{pack}.json")
        else:
            own = decode_uuid(uuids[idx])
            raw = sh(f"cat {RES}/import/{own[:2]}/{own}.json")
            if not raw:
                print(f"  !! '{prefab}' has no readable import file", file=sys.stderr)
                continue
        try:
            data = json.loads(raw.decode("utf-8"))
        except Exception as e:
            print(f"  !! '{prefab}' pack unreadable: {e}", file=sys.stderr)
            continue

        deps = [decode_uuid(u) for u in data[1]] if len(data) > 1 else []
        fields = [f for f in (data[2] if len(data) > 2 else []) if "ound" in f]

        name = prefab.split("/")[-1]
        clips = []
        for dep in deps:
            path = f"{RES}/native/{dep[:2]}/{dep}.mp3"
            blob = sh(f"cat {path} 2>/dev/null")
            if not blob:
                continue
            dest = os.path.join(out_dir, f"{name}_{len(clips)}.mp3")
            with open(dest, "wb") as fh:
                fh.write(blob)
            clips.append({"file": os.path.basename(dest), "uuid": dep,
                          "seconds": probe(dest), "bytes": len(blob)})
        report[prefab] = {"sound_fields": fields, "clips": clips}
        fieldtext = ", ".join(fields) if fields else "-"
        print(f"{name:24} {len(clips)} clip(s)   fields: {fieldtext}")
        for c in clips:
            print(f"    {c['file']:34} {c['seconds']:>7} s")

    with open(os.path.join(out_dir, "_index.json"), "w", encoding="utf-8") as fh:
        json.dump(report, fh, indent=1)
    total = sum(len(v["clips"]) for v in report.values())
    print(f"\n{total} clips from {len(report)} prefabs -> {out_dir}")
    return 0


def probe(path):
    try:
        out = subprocess.run(
            ["ffprobe", "-v", "error", "-show_entries", "format=duration",
             "-of", "csv=p=0", path], capture_output=True, text=True).stdout.strip()
        return round(float(out), 3)
    except Exception:
        return 0.0


if __name__ == "__main__":
    sys.exit(main())
