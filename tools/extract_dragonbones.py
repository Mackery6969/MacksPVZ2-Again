#!/usr/bin/env python3
"""Pull DragonBones armatures out of the PVZGE build.

Cocos stores assets content-addressed under assets/resources/import/, so a
character's skeleton, atlas JSON and atlas PNG sit in three unrelated
directories under opaque names. This identifies each file by content rather
than by name and writes the skeletons out grouped per armature.

Output:
    <out_dir>/<armature>/skeleton.json
    <out_dir>/_index.json      bones, slots and animation names per armature
"""
import json, os, sys, subprocess

IMAGE = "gaozih/pvzge:latest"
ROOT = "/usr/share/nginx/html/assets/resources"


def sh(script):
    return subprocess.run(["docker", "run", "--rm", IMAGE, "sh", "-c", script],
                          capture_output=True, text=True).stdout


def fetch(paths, head_bytes=None, label=""):
    """-> {path: text}, in batches to keep argv and buffered output manageable."""
    out = {}
    batch_size = 200 if head_bytes else 40
    reader = f"head -c {head_bytes}" if head_bytes else "cat"
    for start in range(0, len(paths), batch_size):
        batch = paths[start:start + batch_size]
        script = (f"cd {ROOT}; for f in " + " ".join(batch)
                  + f'; do echo "@@$f"; {reader} "$f"; echo; done')
        blob = sh(script)
        current, buf = None, []
        for line in blob.splitlines():
            if line.startswith("@@"):
                if current:
                    out[current] = "".join(buf)
                current, buf = line[2:], []
            else:
                buf.append(line)
        if current:
            out[current] = "".join(buf)
        print(f"  {label}{min(start + batch_size, len(paths))}/{len(paths)}",
              file=sys.stderr)
    return out


def find_payload(node):
    """Dig the skeleton out of Cocos's envelope.

    DragonBones data is not stored as a nested object - it is the serialized
    DragonBonesAsset's raw JSON, held as an escaped STRING inside the envelope.
    So string values are re-parsed rather than skipped.
    """
    if isinstance(node, dict):
        if isinstance(node.get("armature"), list):
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
    elif isinstance(node, str) and '"armature"' in node:
        try:
            return find_payload(json.loads(node))
        except json.JSONDecodeError:
            return None
    return None


def main():
    out_dir = sys.argv[1] if len(sys.argv) > 1 else "dragonbones_out"
    os.makedirs(out_dir, exist_ok=True)

    print("scanning for armatures...", file=sys.stderr)
    # "armature.:" matches both the plain key and the escaped form the
    # embedded skeleton string uses, while avoiding quotes in the shell.
    candidates = sh(f'cd {ROOT} && grep -rlE "armature.{{0,2}}:" import/ 2>/dev/null').split()
    print(f"  {len(candidates)} candidate files", file=sys.stderr)
    skeletons = candidates

    index = {}
    for path, text in fetch(skeletons, label="body ").items():
        text = text.strip()
        if not text:
            continue
        try:
            payload = find_payload(json.loads(text))
        except json.JSONDecodeError:
            continue
        if not payload:
            continue

        name = payload.get("name") or os.path.basename(path).split(".")[0]
        # The name comes from the asset itself; keep it to one path component
        # so a "../" or absolute name cannot write outside out_dir.
        name = os.path.basename(str(name).replace("\\", "/"))
        if name in ("", ".", ".."):
            name = os.path.basename(path).split(".")[0]
        dest = os.path.join(out_dir, name)
        os.makedirs(dest, exist_ok=True)
        with open(os.path.join(dest, "skeleton.json"), "w", encoding="utf-8") as fh:
            json.dump(payload, fh, ensure_ascii=False, separators=(",", ":"))

        armatures = [a for a in payload.get("armature", []) if isinstance(a, dict)]
        index[name] = {
            "source": path,
            "armatures": [a.get("name") for a in armatures],
            "animations": sorted({
                anim.get("name") for a in armatures
                for anim in (a.get("animation") or []) if isinstance(anim, dict)
            }),
            "bones": sum(len(a.get("bone", [])) for a in armatures),
            "slots": sum(len(a.get("slot", [])) for a in armatures),
        }

    with open(os.path.join(out_dir, "_index.json"), "w", encoding="utf-8") as fh:
        json.dump(index, fh, indent=1, ensure_ascii=False)

    total_anims = sum(len(v["animations"]) for v in index.values())
    print(f"wrote {len(index)} armatures, {total_anims} animations -> {out_dir}")
    print("NOTE: atlas PNGs are not paired up yet; "
          "see addons/dragonbones_import/README.md")


if __name__ == "__main__":
    main()
