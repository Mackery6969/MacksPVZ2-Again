#!/usr/bin/env python3
"""Restore an FMOD project's audio files from the PVZGE build.

The Studio project tracks its *authored* work in git - events, mixer routing,
loop points, bank layout - but not the audio, which belongs to PopCap and is
reproducible. This puts the files back where the metadata expects them, so a
fresh clone opens complete.

Two ways a path is resolved back to a source clip:

  1. the file name is a clip name (`zen00.mp3`), which covers anything placed
     by hand in Studio from the extracted library;
  2. otherwise the event that references it is looked up in the audio catalog
     and its source clip used, which covers anything `fmod_populate.py` placed.

    python3 tools/fmod_restore_assets.py <project dir> <audio_index.json> [--dry-run]

`audio_index.json` comes from `build_audio_index.py`. Clips are pulled from the
Docker image unless `--from <dir>` names an already-extracted copy.
"""
import json
import os
import re
import shutil
import subprocess
import sys
import glob

IMAGE = "gaozih/pvzge:latest"
NATIVE = "/usr/share/nginx/html/assets/resources/native"
CATALOG = "data/native/audio/events.json"
SOURCES = "data/native/audio/pvzge_sources.json"


def arg_value(flag, default=None):
    if flag in sys.argv:
        i = sys.argv.index(flag)
        if i + 1 < len(sys.argv):
            return sys.argv[i + 1]
    return default


def event_paths(root):
    """-> {audioFile id: event path} for every referenced audio file."""
    folders, master = {}, None
    for f in glob.glob(os.path.join(root, "Metadata", "EventFolder", "*.xml")):
        t = open(f, encoding="utf-8").read()
        i = re.search(r'class="(Master)?EventFolder" id="(\{[^}]+\})"', t)
        n = re.search(r'<property name="name">\s*<value>([^<]*)', t)
        p = re.search(r'<relationship name="folder">\s*<destination>(\{[^}]+\})', t)
        if i is None:
            continue
        if i.group(1):
            master = i.group(2)
        folders[i.group(2)] = (n.group(1) if n else "", p.group(1) if p else None)

    def path_of(fid):
        parts = []
        while fid and fid in folders and fid != master:
            name, parent = folders[fid]
            parts.append(name)
            fid = parent
        return "/".join(reversed(parts))

    out = {}
    for f in glob.glob(os.path.join(root, "Metadata", "Event", "*.xml")):
        t = open(f, encoding="utf-8").read()
        n = re.search(r'<property name="name">\s*<value>([^<]*)', t)
        p = re.search(r'<relationship name="folder">\s*<destination>(\{[^}]+\})', t)
        key = ("%s/%s" % (path_of(p.group(1)) if p else "", n.group(1) if n else "")).lstrip("/")
        for aid in re.findall(r'<relationship name="audioFile">\s*<destination>(\{[^}]+\})', t):
            out[aid] = key
    return out


def load_catalog():
    """-> {event path without 'event:/': source clip name}."""
    if not (os.path.exists(CATALOG) and os.path.exists(SOURCES)):
        return {}
    events = {e["id"]: e for e in json.load(open(CATALOG, encoding="utf-8"))["events"]}
    sources = json.load(open(SOURCES, encoding="utf-8"))["sources"]
    out = {}
    for event_id, clip in sources.items():
        fmod = events.get(event_id, {}).get("fmod", "")
        if fmod.startswith("event:/"):
            out[fmod[len("event:/"):]] = clip
    return out


def fetch(uid, ext, cache, from_dir):
    """-> a local path holding this clip's bytes, or None."""
    if from_dir:
        for candidate in (os.path.join(from_dir, uid[:2], uid + ext),
                          os.path.join(from_dir, uid + ext)):
            if os.path.exists(candidate):
                return candidate
    local = os.path.join(cache, uid + ext)
    if os.path.exists(local):
        return local
    blob = subprocess.run(
        ["docker", "run", "--rm", IMAGE, "sh", "-c",
         "cat %s/%s/%s%s" % (NATIVE, uid[:2], uid, ext)],
        capture_output=True).stdout
    if not blob:
        return None
    os.makedirs(cache, exist_ok=True)
    open(local, "wb").write(blob)
    return local


def main():
    if len(sys.argv) < 3:
        print(__doc__)
        return 2
    root, index_path = sys.argv[1], sys.argv[2]
    dry = "--dry-run" in sys.argv
    from_dir = arg_value("--from")

    index = json.load(open(index_path, encoding="utf-8"))
    by_name = {}
    for uid, info in index.items():
        by_name.setdefault(info["name"], (uid, info))

    owners = event_paths(root)
    catalog = load_catalog()
    cache = os.path.join(os.path.dirname(index_path) or ".", "clips")

    restored = already = unresolved = orphaned = 0
    for f in sorted(glob.glob(os.path.join(root, "Metadata", "AudioFile", "*.xml"))):
        t = open(f, encoding="utf-8").read()
        aid = re.search(r'class="AudioFile" id="(\{[^}]+\})"', t)
        ap = re.search(r'<property name="assetPath">\s*<value>([^<]*)', t)
        if not (aid and ap):
            continue
        dest = os.path.join(root, "Assets", ap.group(1))
        # assetPath comes from the metadata; refuse any that would land
        # outside Assets/ (absolute paths, "../" components).
        assets = os.path.abspath(os.path.join(root, "Assets"))
        if not os.path.abspath(dest).startswith(assets + os.sep):
            print("  !! skipping unsafe asset path %r" % ap.group(1))
            unresolved += 1
            continue
        if os.path.exists(dest):
            already += 1
            continue

        # A record no event references is dead metadata, not a missing file.
        if aid.group(1) not in owners:
            orphaned += 1
            continue

        stem = os.path.splitext(os.path.basename(ap.group(1)))[0]
        clip = stem if stem in by_name else catalog.get(owners.get(aid.group(1), ""))
        if clip is None or clip not in by_name:
            print("  !! cannot resolve %s" % ap.group(1))
            unresolved += 1
            continue

        uid, info = by_name[clip]
        if dry:
            print("   %s <- %s" % (ap.group(1), clip))
            restored += 1
            continue
        src = fetch(uid, info.get("ext", ".mp3"), cache, from_dir)
        if src is None:
            print("  !! no file on disk for %s (%s)" % (clip, uid))
            unresolved += 1
            continue
        os.makedirs(os.path.dirname(dest), exist_ok=True)
        shutil.copy2(src, dest)
        print("   %s <- %s" % (ap.group(1), clip))
        restored += 1

    print("\nrestored %d, already present %d, unreferenced %d, unresolved %d"
          % (restored, already, orphaned, unresolved))
    if not dry:
        print("Run tools/fmod_stage_library.py to rebuild Assets/PVZGE/ "
              "(the browsing library), which no event references.")
    return 0 if unresolved == 0 else 1


if __name__ == "__main__":
    sys.exit(main())
