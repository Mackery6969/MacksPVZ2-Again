#!/usr/bin/env python3
"""Extract PvZ2 objclass/objdata tables out of a PVZGE Cocos build.

Cocos wraps each JsonAsset in a serialization envelope; the payload we want is
the object that carries {"version":..., "objects":[...]}. Everything else in the
envelope is Cocos bookkeeping we can drop.
"""
import json, sys, os, subprocess

IMAGE = "gaozih/pvzge:latest"
ROOT = "/usr/share/nginx/html/assets/resources/import"

# Global registries, by the _name Cocos stored them under.
SHEETS = {
    "PlantProps":      "07/076885ea-a5d2-4501-bd14-7c3f00e110c5.json",
    "PlantTypes":      "de/de7476ac-7e8a-494b-b58e-923cc3399440.json",
    "ZombieProps":     "e6/e67cb0cc-c662-4eca-be99-9d409254716a.json",
    "ZombieTypes":     "b9/b97ce2d2-befc-47a6-9731-684ae2321132.json",
    "ProjectileProps": "e8/e8720a22-e52e-45f4-a860-df34a0f1c62e.json",
    "ProjectileTypes": "43/43ce6243-1dd7-4a2e-9f3a-576c4f4fa614.json",
    "ArmorProps":      "7e/7eb75fa5-3672-47ce-ac0c-c05e633619bc.json",
    "ArmorTypes":      "ce/cecad9cc-5180-4763-8c97-32d3196e44fe.json",
    "LawnProps":       "35/3515a267-54eb-4b1e-8d6b-534bb5caae5e.json",
    "TileProps":       "d9/d94831be-76c9-42f1-a7d2-8ce70c508b06.json",
    "GridItemTypes":   "ff/ff89b37c-a773-48a0-bf75-3d9812f927f3.json",
    "PropertySheets":  "44/4402c297-30a9-49f8-88d6-0335fc868781.json",
    "TombstoneProps":  "10/1062d6b2-0c96-4451-b5f0-e2013815211b.json",
}


def find_payload(node):
    """Depth-first search for the {version, objects} payload inside the envelope."""
    if isinstance(node, dict):
        # Some sheets carry "version", others only "objects" - key off objects.
        if isinstance(node.get("objects"), list):
            return node
        for v in node.values():
            hit = find_payload(v)
            if hit:
                return hit
    elif isinstance(node, list):
        for v in node:
            hit = find_payload(v)
            if hit:
                return hit
    return None


def read_from_image(paths):
    """Cat many files out of the image in one container run: path\\n<len>\\n<bytes>."""
    script = ";".join(f'echo "@@{name}"; cat {ROOT}/{rel}' for name, rel in paths.items())
    out = subprocess.run(
        ["docker", "run", "--rm", IMAGE, "sh", "-c", script],
        capture_output=True, text=True, check=True,
    ).stdout
    chunks = {}
    current, buf = None, []
    for line in out.splitlines():
        if line.startswith("@@"):
            if current:
                chunks[current] = "".join(buf)
            current, buf = line[2:], []
        else:
            buf.append(line)
    if current:
        chunks[current] = "".join(buf)
    return chunks


def main():
    outdir = sys.argv[1] if len(sys.argv) > 1 else "data/pvzge"
    os.makedirs(outdir, exist_ok=True)
    raw = read_from_image(SHEETS)

    summary = {}
    for name, text in raw.items():
        if not text.strip():
            print(f"  !! {name}: empty", file=sys.stderr)
            continue
        payload = find_payload(json.loads(text))
        if payload is None:
            print(f"  !! {name}: no payload found", file=sys.stderr)
            continue
        objs = payload.get("objects", [])
        # Index by alias so the loader can resolve RTID(alias@Sheet) directly.
        table = {}
        for o in objs:
            for alias in o.get("aliases", []) or []:
                table[alias] = {"objclass": o.get("objclass"), "objdata": o.get("objdata", {})}
        dest = os.path.join(outdir, f"{name}.json")
        with open(dest, "w", encoding="utf-8") as fh:
            json.dump(table, fh, ensure_ascii=False, indent=1, sort_keys=True)
        classes = sorted({o.get("objclass") or "?" for o in objs})
        summary[name] = {"entries": len(table), "objects": len(objs), "classes": classes}
        print(f"  {name:16} {len(table):>5} aliases  {len(objs):>5} objects  classes={classes[:3]}")

    with open(os.path.join(outdir, "_summary.json"), "w") as fh:
        json.dump(summary, fh, indent=1)


if __name__ == "__main__":
    main()
