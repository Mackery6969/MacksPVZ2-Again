#!/usr/bin/env python3
"""Pull every LevelDefinition out of the PVZGE build into raw per-level JSON."""
import json, os, sys, subprocess

IMAGE = "gaozih/pvzge:latest"
ROOT = "/usr/share/nginx/html/assets/resources/import"


def find_payload(node):
    if isinstance(node, dict):
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


def main():
    outdir = sys.argv[1]
    os.makedirs(outdir, exist_ok=True)

    print("locating level files...", file=sys.stderr)
    files = subprocess.run(
        ["docker", "run", "--rm", IMAGE, "sh", "-c",
         f'cd {ROOT} && grep -rl \'"objclass":"LevelDefinition"\' . 2>/dev/null'],
        capture_output=True, text=True,
    ).stdout.split()
    print(f"found {len(files)} level files", file=sys.stderr)

    # Stream them all out in one container run, delimited by a marker line.
    script = f'cd {ROOT}; for f in ' + " ".join(files) + '; do echo "@@$f"; cat "$f"; echo; done'
    out = subprocess.run(["docker", "run", "--rm", IMAGE, "sh", "-c", script],
                         capture_output=True, text=True).stdout

    written, skipped = 0, 0
    current, buf = None, []

    def flush(path, chunk):
        nonlocal written, skipped
        text = "".join(chunk).strip()
        if not text:
            skipped += 1
            return
        try:
            payload = find_payload(json.loads(text))
        except json.JSONDecodeError:
            skipped += 1
            return
        if not payload:
            skipped += 1
            return
        # Name the file after the level's own name where we can.
        name = None
        for o in payload["objects"]:
            if o.get("objclass") == "LevelDefinition":
                name = (o.get("objdata", {}).get("LevelName")
                        or o.get("objdata", {}).get("Name"))
                break
        stem = os.path.basename(path).replace(".json", "")
        with open(os.path.join(outdir, f"{stem}.json"), "w", encoding="utf-8") as fh:
            json.dump(payload, fh, ensure_ascii=False, separators=(",", ":"))
        written += 1

    for line in out.splitlines():
        if line.startswith("@@"):
            if current:
                flush(current, buf)
            current, buf = line[2:], []
        else:
            buf.append(line)
    if current:
        flush(current, buf)

    print(f"wrote {written} levels, skipped {skipped}", file=sys.stderr)


if __name__ == "__main__":
    main()
