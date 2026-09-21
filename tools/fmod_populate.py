#!/usr/bin/env python3
"""Fill every event in the FMOD project with its PVZGE sound.

Ties three things together: the audio catalog (event id -> FMOD path), the
source map (event id -> PVZGE clip name), and the recovered audio index
(clip name -> asset uuid). Pulls each clip out of the build and attaches it.

    python3 tools/fmod_populate.py <project dir> <audio_index.json> [--dry-run]
"""
import json, os, subprocess, sys

IMAGE = "gaozih/pvzge:latest"
NATIVE = "/usr/share/nginx/html/assets/resources/native"
CATALOG = "data/native/audio/events.json"
SOURCES = "data/native/audio/pvzge_sources.json"


def main():
    if len(sys.argv) < 3:
        print(__doc__)
        return 2
    project, index_path = sys.argv[1], sys.argv[2]
    dry = "--dry-run" in sys.argv

    catalog = {e["id"]: e for e in json.load(open(CATALOG, encoding="utf-8"))["events"]}
    srcdoc = json.load(open(SOURCES, encoding="utf-8"))
    sources, loops = srcdoc["sources"], set(srcdoc.get("loop", []))
    index = json.load(open(index_path, encoding="utf-8"))

    # clip name -> the asset with that name, preferring one that has a duration
    by_name = {}
    for uid, info in index.items():
        name = info["name"]
        if name not in by_name or (info.get("seconds") and not by_name[name][1].get("seconds")):
            by_name[name] = (uid, info)

    work_dir = os.path.join(os.path.dirname(index_path), "clips")
    os.makedirs(work_dir, exist_ok=True)

    done = missing = skipped = 0
    for event_id, clip_name in sources.items():
        event = catalog.get(event_id)
        if event is None or not event.get("fmod"):
            print("  !! '%s' is not in the catalog" % event_id)
            missing += 1
            continue
        hit = by_name.get(clip_name)
        if hit is None:
            print("  !! no clip named '%s' (for %s)" % (clip_name, event_id))
            missing += 1
            continue
        uid, info = hit
        ext = info.get("ext", ".mp3")
        local = os.path.join(work_dir, "%s%s" % (clip_name, ext))
        if not os.path.exists(local):
            blob = subprocess.run(
                ["docker", "run", "--rm", IMAGE, "sh", "-c",
                 "cat %s/%s/%s%s" % (NATIVE, uid[:2], uid, ext)],
                capture_output=True).stdout
            if not blob:
                print("  !! '%s' has no file on disk (%s)" % (clip_name, uid))
                missing += 1
                continue
            open(local, "wb").write(blob)

        path = event["fmod"][len("event:/"):]
        if dry:
            print("   %-28s <- %-22s %s" % (path, clip_name, uid))
            done += 1
            continue

        cmd = ["python3", "tools/fmod_attach_audio.py", project, path, local]
        if event_id in loops:
            cmd.append("--loop")
        out = subprocess.run(cmd, capture_output=True, text=True)
        line = (out.stdout or out.stderr).strip()
        print("   " + line)
        if "already has audio" in line:
            skipped += 1
        elif out.returncode == 0:
            done += 1
        else:
            missing += 1

    print("\nattached %d, already had audio %d, unresolved %d" % (done, skipped, missing))
    return 0


if __name__ == "__main__":
    sys.exit(main())
