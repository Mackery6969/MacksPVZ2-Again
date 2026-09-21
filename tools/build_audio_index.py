#!/usr/bin/env python3
"""Recover the real name of every audio clip in the PVZGE build.

PVZGE has no `sound/` asset namespace, so clips look anonymous - addressed only
by UUID. They are not: Cocos packs carry, alongside the member UUID list, an
instance array holding each asset's original file name and duration, aligned by
position. Reading the two together recovers `groan_beach0`, `Excited_Med11` and
the rest.

    python3 tools/build_audio_index.py <import dir> <config.json> <out.json>
"""
import json, os, sys

B64 = 'ABCDEFGHIJKLMNOPQRSTUVWXYZabcdefghijklmnopqrstuvwxyz0123456789+/'
VALUES = {c: i for i, c in enumerate(B64)}
HEX = '0123456789abcdef'
AUDIO_EXT = {".mp3", ".ogg", ".wav", ".m4a"}


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


def asset_header(instance):
    """-> (name, ext, length) if this instance describes an audio asset."""
    try:
        head = instance[0][0]
    except (IndexError, TypeError):
        return None
    if not (isinstance(head, list) and len(head) >= 3):
        return None
    name, ext = head[1], head[2]
    if not (isinstance(name, str) and isinstance(ext, str) and ext in AUDIO_EXT):
        return None
    length = head[3] if len(head) > 3 and isinstance(head[3], (int, float)) else None
    return name, ext, length


def main():
    import_dir, config_path, out_path = sys.argv[1], sys.argv[2], sys.argv[3]
    cfg = json.load(open(config_path, encoding="utf-8"))
    uuids, packs, paths = cfg["uuids"], cfg.get("packs", {}), cfg["paths"]

    # An asset index can appear in several packs; the first naming wins.
    index = {}
    scanned = skipped = 0
    for pack, members in packs.items():
        path = os.path.join(import_dir, pack[:2], "%s.json" % pack)
        if not os.path.exists(path):
            skipped += 1
            continue
        try:
            data = json.load(open(path, encoding="utf-8"))
        except Exception:
            skipped += 1
            continue
        scanned += 1
        if len(data) < 6 or not isinstance(data[5], list):
            continue
        instances = data[5]
        # Members and instances are positionally aligned.
        if len(instances) != len(members):
            continue
        for i, member in enumerate(members):
            info = asset_header(instances[i])
            if info is None:
                continue
            name, ext, length = info
            uid = decode_uuid(uuids[member])
            if uid in index:
                continue
            index[uid] = {"name": name, "ext": ext, "seconds": length,
                          "pack": pack, "asset_index": member}

    # Named assets from the path table cover anything not inside a pack.
    by_index = {int(k): v[0] for k, v in paths.items()}
    for idx, p in by_index.items():
        uid = decode_uuid(uuids[idx])
        if uid in index:
            index[uid]["path"] = p
        elif p.startswith("music/"):
            index[uid] = {"name": p.split("/")[-1], "ext": ".mp3",
                          "seconds": None, "path": p, "asset_index": idx}

    json.dump(index, open(out_path, "w", encoding="utf-8"), indent=1)

    named = len(index)
    dupes = {}
    for v in index.values():
        dupes[v["name"]] = dupes.get(v["name"], 0) + 1
    collisions = sum(1 for n, c in dupes.items() if c > 1)
    print("packs scanned: %d (skipped %d)" % (scanned, skipped))
    print("named audio assets: %d  (%d distinct names, %d names reused)"
          % (named, len(dupes), collisions))
    print("-> %s" % out_path)
    return 0


if __name__ == "__main__":
    sys.exit(main())
