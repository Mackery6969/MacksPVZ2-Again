#!/usr/bin/env python3
"""Emit the FMOD Studio event paths the game expects.

The catalog in `audio/events.json` is the source of truth: the game raises
event ids, and each id carries the FMOD Studio path it maps to. This turns
that into a flat checklist to build the Studio project against, so the two
cannot drift apart silently.

    python3 tools/fmod_event_list.py            # the base game's events
    python3 tools/fmod_event_list.py --mods     # include installed packs
    python3 tools/fmod_event_list.py --check    # non-zero if anything lacks a path

Base events are what belongs in the game's own Studio project. A pack's events
are that pack author's to build, and a pack replacing a base id would otherwise
show its path here and send you building the wrong event.
"""
import json, glob, os, sys

BASE = "data/native/audio/events.json"
MODS = "mods/*/audio/events.json"


def load_events(include_mods=False):
    """-> [(id, fmod_path, source, is_music)], base first then mods."""
    out = {}
    sources = [BASE] + (sorted(glob.glob(MODS)) if include_mods else [])
    for path in sources:
        if not os.path.exists(path):
            continue
        source = "base" if path == BASE else path.split(os.sep)[1]
        with open(path, encoding="utf-8") as fh:
            data = json.load(fh)
        for entry in data.get("events", []):
            if not isinstance(entry, dict) or not entry.get("id"):
                continue
            # A later source replacing an id also replaces its path.
            out[entry["id"]] = (entry.get("fmod", ""), source,
                                bool(entry.get("music", False)))
    return [(k, *v) for k, v in sorted(out.items())]


def main():
    include_mods = "--mods" in sys.argv
    check = "--check" in sys.argv
    events = load_events(include_mods or check)

    missing = [e for e in events if not e[1]]
    if check:
        for eid, _path, source, _music in missing:
            print(f"  !! '{eid}' ({source}) has no FMOD path", file=sys.stderr)
        print(f"{len(events)} events, {len(missing)} without an FMOD path")
        return 1 if missing else 0

    scope = "base + packs" if include_mods else "base game"
    print(f"# {len(events)} events to create in FMOD Studio ({scope})")
    print("# Folder structure follows the event paths; music events go in a")
    print("# looping event, one-shots in a regular event.\n")
    width = max((len(e[0]) for e in events), default=0)
    for eid, path, source, music in events:
        kind = "music " if music else "      "
        tag = "" if source == "base" else f"   [{source}]"
        print(f"{kind}{eid:<{width}}  ->  {path}{tag}")
    return 0


if __name__ == "__main__":
    sys.exit(main())
