#!/usr/bin/env python3
"""Create the game's events inside an FMOD Studio project.

Reads the audio catalog and writes an `.xml` per missing event into the
project's `Metadata/Event/`, plus any `Metadata/EventFolder/` the paths imply.

The object graph is copied from an event FMOD Studio wrote itself, with the
content-specific parts (audio file, loop region, group track) removed - so what
lands on disk is a shape Studio is known to accept, just empty. Bank assignment
is deliberately left alone: the reference event carries none, and guessing at
the relationship name risks a project that will not open.

Existing events and folders are never touched, so this is safe to re-run as the
catalog grows.

    python3 tools/fmod_create_events.py <project.fspro dir> [--dry-run]
"""
import json, glob, os, re, sys, uuid
from xml.sax.saxutils import escape, unescape

CATALOG = "data/native/audio/events.json"


def guid():
    return "{%s}" % uuid.uuid4()


def read_catalog(include_mods=False):
    """-> [(id, fmod_path, is_music)] from base, optionally plus packs."""
    out = {}
    sources = [CATALOG]
    if include_mods:
        sources += sorted(glob.glob("mods/*/audio/events.json"))
    for path in sources:
        if not os.path.exists(path):
            continue
        with open(path, encoding="utf-8") as fh:
            for entry in json.load(fh).get("events", []):
                if isinstance(entry, dict) and entry.get("fmod"):
                    out[entry["id"]] = (entry["fmod"], bool(entry.get("music")))
    return [(k, *v) for k, v in sorted(out.items())]


def scan_project(root):
    """-> (master_event_folder_id, {folder path -> id}, {event path -> id})."""
    meta = os.path.join(root, "Metadata")
    master = None
    folders = {}     # id -> (name, parent_id)
    events = {}      # id -> (name, folder_id)

    for path in glob.glob(os.path.join(meta, "EventFolder", "*.xml")):
        text = open(path, encoding="utf-8").read()
        fid = re.search(r'class="(?:Master)?EventFolder" id="(\{[^}]+\})"', text)
        if not fid:
            continue
        name = re.search(r'<property name="name">\s*<value>([^<]*)</value>', text)
        parent = re.search(r'<relationship name="folder">\s*<destination>(\{[^}]+\})',
                           text)
        if 'class="MasterEventFolder"' in text:
            master = fid.group(1)
        folders[fid.group(1)] = (unescape(name.group(1)) if name else "",
                                 parent.group(1) if parent else None)

    for path in glob.glob(os.path.join(meta, "Event", "*.xml")):
        text = open(path, encoding="utf-8").read()
        eid = re.search(r'class="Event" id="(\{[^}]+\})"', text)
        if not eid:
            continue
        name = re.search(r'<property name="name">\s*<value>([^<]*)</value>', text)
        parent = re.search(r'<relationship name="folder">\s*<destination>(\{[^}]+\})',
                           text)
        events[eid.group(1)] = (unescape(name.group(1)) if name else "",
                                parent.group(1) if parent else None)

    def path_of(fid, table):
        parts = []
        seen = set()
        while fid and fid in table and fid != master and fid not in seen:
            seen.add(fid)
            name, parent = table[fid]
            parts.append(name)
            fid = parent
        return "/".join(reversed(parts))

    folder_paths = {path_of(fid, folders): fid for fid in folders if fid != master}
    event_paths = {}
    for eid, (name, parent) in events.items():
        prefix = path_of(parent, folders) if parent and parent != master else ""
        event_paths[("%s/%s" % (prefix, name)).lstrip("/")] = eid
    return master, folder_paths, event_paths


def master_bus_id(root):
    text = open(os.path.join(root, "Metadata", "Master.xml"), encoding="utf-8").read()
    m = re.search(r'class="MixerMaster" id="(\{[^}]+\})"', text)
    return m.group(1) if m else None


HEADER = '<?xml version="1.0" encoding="UTF-8"?>\n<objects serializationModel="%s">\n'


def serialization_model(root):
    text = open(os.path.join(root, "PVZGE.fspro"), encoding="utf-8").read() \
        if os.path.exists(os.path.join(root, "PVZGE.fspro")) else ""
    m = re.search(r'serializationModel="([^"]+)"', text)
    if m:
        return m.group(1)
    text = open(os.path.join(root, "Metadata", "Master.xml"), encoding="utf-8").read()
    return re.search(r'serializationModel="([^"]+)"', text).group(1)


def folder_xml(model, fid, name, parent):
    return (HEADER % model
            + '\t<object class="EventFolder" id="%s">\n' % fid
            + '\t\t<property name="name">\n\t\t\t<value>%s</value>\n\t\t</property>\n' % escape(name)
            + '\t\t<relationship name="folder">\n\t\t\t<destination>%s</destination>\n'
              '\t\t</relationship>\n' % parent
            + '\t</object>\n</objects>\n')


def event_xml(model, name, folder, bus):
    """An empty event, shaped exactly like one Studio wrote."""
    e, mixer, track, minput = guid(), guid(), guid(), guid()
    props, marker, timeline, emm = guid(), guid(), guid(), guid()
    ec_in, pan_in, fader_in = guid(), guid(), guid()
    ec_m, pan_m, fader_m = guid(), guid(), guid()

    def rel(rname, dest):
        return ('\t\t<relationship name="%s">\n\t\t\t<destination>%s</destination>\n'
                '\t\t</relationship>\n' % (rname, dest))

    x = HEADER % model
    x += '\t<object class="Event" id="%s">\n' % e
    x += '\t\t<property name="name">\n\t\t\t<value>%s</value>\n\t\t</property>\n' % escape(name)
    x += '\t\t<property name="outputFormat">\n\t\t\t<value>1</value>\n\t\t</property>\n'
    x += rel("folder", folder) + rel("mixer", mixer) + rel("masterTrack", track)
    x += rel("mixerInput", minput) + rel("automatableProperties", props)
    x += rel("markerTracks", marker) + rel("timeline", timeline)
    x += '\t</object>\n'

    x += '\t<object class="EventMixer" id="%s">\n%s\t</object>\n' % (
        mixer, rel("masterBus", emm))
    x += '\t<object class="MasterTrack" id="%s">\n%s\t</object>\n' % (
        track, rel("mixerGroup", emm))
    x += '\t<object class="MixerInput" id="%s">\n%s%s%s\t</object>\n' % (
        minput, rel("effectChain", ec_in), rel("panner", pan_in), rel("output", bus))
    x += '\t<object class="EventAutomatableProperties" id="%s" />\n' % props
    x += '\t<object class="MarkerTrack" id="%s" />\n' % marker
    x += '\t<object class="Timeline" id="%s" />\n' % timeline
    x += '\t<object class="EventMixerMaster" id="%s">\n%s%s%s\t</object>\n' % (
        emm, rel("effectChain", ec_m), rel("panner", pan_m), rel("mixer", mixer))
    for chain, fader in ((ec_in, fader_in), (ec_m, fader_m)):
        x += '\t<object class="MixerBusEffectChain" id="%s">\n%s\t</object>\n' % (
            chain, rel("effects", fader))
    for pan in (pan_in, pan_m):
        x += '\t<object class="MixerBusPanner" id="%s" />\n' % pan
    for fader in (fader_in, fader_m):
        x += '\t<object class="MixerBusFader" id="%s" />\n' % fader
    x += '</objects>\n'
    return e, x


def main():
    if len(sys.argv) < 2:
        print(__doc__)
        return 2
    root = sys.argv[1]
    dry = "--dry-run" in sys.argv
    include_mods = "--mods" in sys.argv

    if not os.path.isdir(os.path.join(root, "Metadata")):
        print("not an FMOD Studio project: %s" % root, file=sys.stderr)
        return 1

    model = serialization_model(root)
    bus = master_bus_id(root)
    master, folders, events = scan_project(root)
    if not (master and bus):
        print("could not find the master event folder or master bus", file=sys.stderr)
        return 1
    print("project: model=%s  existing events=%d  folders=%d"
          % (model, len(events), len(folders)))

    new_folders, new_events = [], []
    for eid, path, _music in read_catalog(include_mods):
        if not path.startswith("event:/"):
            continue
        parts = path[len("event:/"):].split("/")
        name, dirs = parts[-1], parts[:-1]

        parent = master
        walked = []
        for d in dirs:
            walked.append(d)
            key = "/".join(walked)
            if key not in folders:
                fid = guid()
                folders[key] = fid
                new_folders.append((fid, d, parent, key))
            parent = folders[key]

        key = "/".join(dirs + [name])
        if key in events:
            continue
        new_events.append((name, parent, key, eid))

    print("to create: %d folders, %d events" % (len(new_folders), len(new_events)))
    for _fid, _name, _parent, key in new_folders:
        print("   folder  %s" % key)
    for name, _parent, key, eid in new_events:
        print("   event   %-34s (%s)" % (key, eid))
    if dry:
        print("\n--dry-run: nothing written")
        return 0

    meta = os.path.join(root, "Metadata")
    os.makedirs(os.path.join(meta, "EventFolder"), exist_ok=True)
    os.makedirs(os.path.join(meta, "Event"), exist_ok=True)
    for fid, name, parent, _key in new_folders:
        with open(os.path.join(meta, "EventFolder", "%s.xml" % fid), "w",
                  encoding="utf-8") as fh:
            fh.write(folder_xml(model, fid, name, parent))
    for name, parent, _key, _eid in new_events:
        eid_guid, xml = event_xml(model, name, parent, bus)
        with open(os.path.join(meta, "Event", "%s.xml" % eid_guid), "w",
                  encoding="utf-8") as fh:
            fh.write(xml)

    print("\nwrote %d folders and %d events" % (len(new_folders), len(new_events)))
    print("Open the project in FMOD Studio, select the new events and assign "
          "them to the Sound bank - they are created unassigned, matching how "
          "the existing event is stored.")
    return 0


if __name__ == "__main__":
    sys.exit(main())
