#!/usr/bin/env python3
"""Rebuild timeline-based sound effects as action sheets.

A sound effect has nothing to lay out in time: it fires, it plays, it stops.
FMOD's action sheet says exactly that, and costs less than a timeline that is
only ever scrubbed from zero. Music is the opposite - it wants the timeline,
for markers, loop regions and transitions - so music events are left alone.

The shape is copied from action sheets FMOD Studio wrote in this project,
rather than invented:

    Event.parameters  -> ActionSheet
    ActionSheet.modules -> MultiSound        (the instrument)
    MasterTrack.modules -> the same MultiSound
    MultiSound.sounds -> SingleSound, or a nested MultiSound with
                         playlistMode 1 when there are several clips

The timeline track that held the sound goes away with its group track and
mixer group; the sounds themselves, the event's folder, mixer routing and
bank assignment are all kept.

    python3 tools/fmod_action_sheets.py <project dir> [--dry-run] [--only NAME ...]

Music events are skipped by reading `data/native/audio/events.json`, so an
event the catalog marks `"music": true` keeps its timeline.
"""
import json, os, sys, uuid
import xml.etree.ElementTree as ET

CATALOG = os.path.join(os.path.dirname(os.path.abspath(__file__)), "..",
                       "data", "native", "audio", "events.json")
NS = "Studio.02.03.00"


def guid():
    return "{%s}" % uuid.uuid4()


def obj(root, cls, oid=None):
    e = ET.SubElement(root, "object", {"class": cls, "id": oid or guid()})
    return e


def rel(parent, name, *destinations):
    r = ET.SubElement(parent, "relationship", {"name": name})
    for d in destinations:
        ET.SubElement(r, "destination").text = d
    return r


def prop(parent, name, value):
    p = ET.SubElement(parent, "property", {"name": name})
    ET.SubElement(p, "value").text = value
    return p


def event_name(root):
    for o in root.findall("object"):
        if o.get("class") == "Event":
            for p in o.findall("property"):
                if p.get("name") == "name":
                    return (p.findtext("value") or "").strip()
    return ""


def music_event_names(project):
    """-> the leaf names of every event the catalog calls music.

    Matching on the leaf name rather than the full path is enough here: no two
    music events share a leaf with a sound effect, and it avoids rebuilding
    the folder tree just to decide whether to skip something.
    """
    if not os.path.exists(CATALOG):
        return set()
    out = set()
    for e in json.load(open(CATALOG, encoding="utf-8"))["events"]:
        if e.get("music") and e.get("fmod", "").startswith("event:/"):
            out.add(e["fmod"].rsplit("/", 1)[-1])
    return out


def convert(path, dry):
    """-> 'converted', 'skipped: <why>' for one event file."""
    tree = ET.parse(path)
    root = tree.getroot()
    by_class = {}
    for o in root.findall("object"):
        by_class.setdefault(o.get("class"), []).append(o)

    if "ActionSheet" in by_class:
        return "skipped: already an action sheet"
    event = (by_class.get("Event") or [None])[0]
    master = (by_class.get("MasterTrack") or [None])[0]
    if event is None or master is None:
        return "skipped: no event or master track"

    group_tracks = by_class.get("GroupTrack") or []
    if not group_tracks:
        return "skipped: nothing on the timeline"

    # The sounds live on the group track; everything else about that track -
    # the track itself and its mixer group - exists only to place them in
    # time, which an action sheet does not do.
    sounds = []
    for track in group_tracks:
        for r in track.findall("relationship"):
            if r.get("name") == "modules":
                sounds += [d.text for d in r.findall("destination")]
    if not sounds:
        return "skipped: the track holds no sound"

    doomed = set()
    for track in group_tracks:
        doomed.add(track.get("id"))
        for r in track.findall("relationship"):
            if r.get("name") == "mixerGroup":
                for d in r.findall("destination"):
                    doomed.add(d.text)
    # The mixer group's own fader, panner and effect chain go with it.
    for o in list(root.findall("object")):
        if o.get("id") not in doomed:
            continue
        for r in o.findall("relationship"):
            if r.get("name") in ("effectChain", "panner"):
                for d in r.findall("destination"):
                    doomed.add(d.text)
    for o in list(root.findall("object")):
        if o.get("class") == "MixerBusEffectChain" and o.get("id") in doomed:
            for r in o.findall("relationship"):
                for d in r.findall("destination"):
                    doomed.add(d.text)

    if dry:
        return "would convert (%d sound%s)" % (len(sounds), "" if len(sounds) == 1 else "s")

    # Detach the timeline's modules; the Timeline object itself stays, empty,
    # exactly as Studio leaves it on its own action sheets.
    for timeline in by_class.get("Timeline", []):
        for r in list(timeline.findall("relationship")):
            if r.get("name") == "modules":
                timeline.remove(r)
    for r in list(event.findall("relationship")):
        if r.get("name") == "groupTracks":
            event.remove(r)
    for o in list(root.findall("object")):
        if o.get("id") in doomed:
            root.remove(o)

    instrument = guid()
    sheet = guid()
    rel(event, "parameters", sheet)
    rel(master, "modules", instrument)

    action = obj(root, "ActionSheet", sheet)
    rel(action, "modules", instrument)

    outer = obj(root, "MultiSound", instrument)
    if len(sounds) == 1:
        rel(outer, "sounds", sounds[0])
    else:
        # Several clips become one shuffled playlist - FMOD picks for us, so
        # the game never has to know a sound has variations.
        inner = guid()
        rel(outer, "sounds", inner)
        playlist = obj(root, "MultiSound", inner)
        prop(playlist, "playlistMode", "1")
        rel(playlist, "sounds", *sounds)

    ET.indent(tree, space="\t")
    tree.write(path, encoding="UTF-8", xml_declaration=True)
    return "converted (%d sound%s)" % (len(sounds), "" if len(sounds) == 1 else "s")


def main():
    if len(sys.argv) < 2:
        print(__doc__)
        return 2
    project = sys.argv[1]
    dry = "--dry-run" in sys.argv
    only = []
    if "--only" in sys.argv:
        only = [a for a in sys.argv[sys.argv.index("--only") + 1:]
                if not a.startswith("--")]

    music = music_event_names(project)
    counts = {}
    for path in sorted(os.listdir(os.path.join(project, "Metadata", "Event"))):
        if not path.endswith(".xml"):
            continue
        full = os.path.join(project, "Metadata", "Event", path)
        name = event_name(ET.parse(full).getroot())
        if only and name not in only:
            continue
        if name in music:
            result = "skipped: music keeps its timeline"
        else:
            result = convert(full, dry)
        counts[result.split(" (")[0]] = counts.get(result.split(" (")[0], 0) + 1
        if not result.startswith("skipped: already"):
            print("   %-22s %s" % (name, result))
    print()
    for key in sorted(counts):
        print("%-40s %d" % (key, counts[key]))
    return 0


if __name__ == "__main__":
    sys.exit(main())
