#!/usr/bin/env python3
"""Attach an audio file to an event in an FMOD Studio project.

Copies the file into the project's `Assets/`, writes the `AudioFile` metadata
Studio expects, and adds a sound module to the event's timeline - the same
object shape Studio produces when you drag a file onto an event.

    python3 tools/fmod_attach_audio.py <project dir> <event path> <audio file> [--loop]

`event path` is as the game addresses it, e.g. SFX/Plants/Shoot.
"""
import os, re, glob, shutil, subprocess, sys, uuid


def guid():
    return "{%s}" % uuid.uuid4()


def probe(path):
    """-> (seconds, khz, channels) via ffprobe."""
    def field(entries):
        return subprocess.run(
            ["ffprobe", "-v", "error", "-show_entries", entries,
             "-of", "csv=p=0", path], capture_output=True, text=True).stdout.strip()
    dur = float(field("format=duration") or 0)
    rate = field("stream=sample_rate").split("\n")[0] or "44100"
    ch = field("stream=channels").split("\n")[0] or "1"
    return round(dur, 3), round(int(rate) / 1000), int(ch)


def model_of(root):
    text = open(os.path.join(root, "Metadata", "Master.xml"), encoding="utf-8").read()
    return re.search(r'serializationModel="([^"]+)"', text).group(1)


def master_asset_folder(root):
    for f in glob.glob(os.path.join(root, "Metadata", "Asset", "*.xml")):
        t = open(f, encoding="utf-8").read()
        m = re.search(r'class="MasterAssetFolder" id="(\{[^}]+\})"', t)
        if m:
            return m.group(1)
    return None


def find_event(root, event_path):
    """-> (file, text, event_id) for the event at `event_path`."""
    folders, master = {}, None
    for f in glob.glob(os.path.join(root, "Metadata", "EventFolder", "*.xml")):
        t = open(f, encoding="utf-8").read()
        i = re.search(r'class="(Master)?EventFolder" id="(\{[^}]+\})"', t)
        n = re.search(r'<property name="name">\s*<value>([^<]*)', t)
        p = re.search(r'<relationship name="folder">\s*<destination>(\{[^}]+\})', t)
        if i.group(1):
            master = i.group(2)
        folders[i.group(2)] = (n.group(1) if n else "", p.group(1) if p else None)

    def path_of(fid):
        parts = []
        while fid and fid in folders and fid != master:
            nm, par = folders[fid]
            parts.append(nm)
            fid = par
        return "/".join(reversed(parts))

    for f in glob.glob(os.path.join(root, "Metadata", "Event", "*.xml")):
        t = open(f, encoding="utf-8").read()
        n = re.search(r'<property name="name">\s*<value>([^<]*)', t)
        p = re.search(r'<relationship name="folder">\s*<destination>(\{[^}]+\})', t)
        e = re.search(r'class="Event" id="(\{[^}]+\})"', t)
        key = ("%s/%s" % (path_of(p.group(1)) if p else "", n.group(1))).lstrip("/")
        if key == event_path:
            return f, t, e.group(1)
    return None, None, None


def main():
    if len(sys.argv) < 4:
        print(__doc__)
        return 2
    root, event_path, audio = sys.argv[1], sys.argv[2], sys.argv[3]
    loop = "--loop" in sys.argv

    ev_file, text, event_id = find_event(root, event_path)
    if not ev_file:
        print("no event '%s' in the project" % event_path, file=sys.stderr)
        return 1
    if "class=\"SingleSound\"" in text:
        print("'%s' already has audio - leaving it alone" % event_path)
        return 0

    model = model_of(root)
    asset_root = master_asset_folder(root)
    seconds, khz, channels = probe(audio)

    # Copy the file in, mirroring the event's own folder structure.
    rel_dir = os.path.dirname(event_path)
    dest_dir = os.path.join(root, "Assets", rel_dir)
    os.makedirs(dest_dir, exist_ok=True)
    fname = "%s%s" % (os.path.basename(event_path), os.path.splitext(audio)[1])
    shutil.copy2(audio, os.path.join(dest_dir, fname))
    asset_path = "%s/%s" % (rel_dir, fname) if rel_dir else fname

    audio_id = guid()
    af = ('<?xml version="1.0" encoding="UTF-8"?>\n<objects serializationModel="%s">\n'
          '\t<object class="AudioFile" id="%s">\n'
          '\t\t<property name="assetPath">\n\t\t\t<value>%s</value>\n\t\t</property>\n'
          '\t\t<property name="frequencyInKHz">\n\t\t\t<value>%d</value>\n\t\t</property>\n'
          '\t\t<property name="channelCount">\n\t\t\t<value>%d</value>\n\t\t</property>\n'
          '\t\t<property name="length">\n\t\t\t<value>%s</value>\n\t\t</property>\n'
          '\t\t<relationship name="masterAssetFolder">\n\t\t\t<destination>%s</destination>\n'
          '\t\t</relationship>\n\t</object>\n</objects>\n'
          % (model, audio_id, asset_path, khz, channels, seconds, asset_root))
    os.makedirs(os.path.join(root, "Metadata", "AudioFile"), exist_ok=True)
    with open(os.path.join(root, "Metadata", "AudioFile", "%s.xml" % audio_id),
              "w", encoding="utf-8") as fh:
        fh.write(af)

    # A sound on a group track, routed to the event's master bus - the shape
    # Studio builds when a file is dropped onto a new audio track.
    sound, track, grp = guid(), guid(), guid()
    chain, pan, fader = guid(), guid(), guid()
    emm = re.search(r'class="EventMixerMaster" id="(\{[^}]+\})"', text).group(1)
    timeline = re.search(
        r'<relationship name="timeline">\s*<destination>(\{[^}]+\})', text).group(1)

    def rel(name, dest):
        return ('\t\t<relationship name="%s">\n\t\t\t<destination>%s</destination>\n'
                '\t\t</relationship>\n' % (name, dest))

    # Point the event at the new group track.
    text = text.replace(
        '\t\t<relationship name="timeline">',
        rel("groupTracks", track).replace("\t\t", "\t\t", 1) +
        '\t\t<relationship name="timeline">', 1)
    # Give the timeline the sound module.
    text = re.sub(r'(<object class="Timeline" id="%s")\s*/>' % re.escape(timeline),
                  r'\1>\n%s\t</object>' % rel("modules", sound), text)

    extra = ''
    extra += '\t<object class="GroupTrack" id="%s">\n%s%s\t</object>\n' % (
        track, rel("modules", sound), rel("mixerGroup", grp))
    extra += ('\t<object class="SingleSound" id="%s">\n'
              '\t\t<property name="length">\n\t\t\t<value>%s</value>\n\t\t</property>\n'
              '%s%s\t</object>\n'
              % (sound, seconds,
                 '\t\t<property name="isLooping">\n\t\t\t<value>true</value>\n\t\t</property>\n'
                 if loop else '',
                 rel("audioFile", audio_id)))
    extra += '\t<object class="EventMixerGroup" id="%s">\n' % grp
    extra += '\t\t<property name="name">\n\t\t\t<value>Audio 1</value>\n\t\t</property>\n'
    extra += rel("effectChain", chain) + rel("panner", pan) + rel("output", emm)
    extra += '\t</object>\n'
    extra += '\t<object class="MixerBusEffectChain" id="%s">\n%s\t</object>\n' % (
        chain, rel("effects", fader))
    extra += '\t<object class="MixerBusPanner" id="%s" />\n' % pan
    extra += '\t<object class="MixerBusFader" id="%s" />\n' % fader

    text = text.replace("</objects>", extra + "</objects>")
    with open(ev_file, "w", encoding="utf-8") as fh:
        fh.write(text)

    print("%-26s <- %s  (%.3fs, %dkHz, %dch)"
          % (event_path, os.path.basename(audio), seconds, khz, channels))
    return 0


if __name__ == "__main__":
    sys.exit(main())
