#!/usr/bin/env python3
"""Lay every PVZGE audio clip into an FMOD project's Assets as a folder tree.

The clips come out of the build as UUID filenames in one flat directory.
`build_audio_index.py` recovers their real names; this sorts those names into a
tree so the Studio asset browser is navigable.

Classification is by name, since that is all PVZGE gives us for most clips -
except the music, which carries a real `music/inGame/<world>/...` path and is
filed by that instead. Anything no rule claims is grouped by the token before
its first underscore; a group too small to be worth its own folder is filed
under `Other/_misc/<letter>` instead, so the tail stays organised without
sprouting hundreds of near-empty directories.

    python3 tools/fmod_stage_library.py <project dir> <audio_index.json> <mp3 dir> [--dry-run]
"""
import json, os, re, shutil, sys, collections

# (regex on the name, destination subtree). First match wins, so order matters.
RULES = [
    # --- music ------------------------------------------------------------
    (r'^(LP|CYS|P[1-4]|Stage[1-4]|ZB|ZB_\w+)_', "Music/Lawn"),
    (r'^(VIC|LOSE|LEAVE)_', "Music/Outcome"),
    (r'^(UB|ZBI|MG)_', "Music/Special"),
    (r'^(Ballad|Metal|Pop|Rap|Punk|EightBit|Eightbit)(_|\d|$)', "Music/Minigame"),
    (r'^(Dialogue|dropMusic|WorldMap|WorldMusic|BackgroundMusic|Music)', "Music/Misc"),
    (r'^Zomboss', "Music/Boss"),

    # --- the zen garden ---------------------------------------------------
    # zen00..zen17 are music, not effects: the garden scene shuffles them as
    # a playlist. They are filed as music despite the bare "zen" name.
    (r'^zen\d', "Music/ZenGarden"),

    # --- ambience ---------------------------------------------------------
    (r'^ambience', "SFX/Ambience"),

    # --- shared between plants and zombies --------------------------------
    # Chewing is not a zombie sound. Chomper, Tangle Kelp and friends chew
    # too, so these belong to neither side.
    (r'^(chew|gulp|mouth|munch)', "SFX/Shared/Eat"),

    # --- zombie voice and body -------------------------------------------
    (r'^groan', "SFX/Zombies/Groan"),
    (r'^(say|Say_|Excited_|Playful_|Tired|tired|appear_say|deathSay|death_say)',
     "SFX/Zombies/Voice"),
    (r'^(death|Death|die)', "SFX/Zombies/Death"),
    (r'^(step|Step|walk|move)', "SFX/Zombies/Move"),
    (r'^(Eat|eat)', "SFX/Zombies/Eat"),
    # Chomping is shared as well - a Chomper does it to zombies.
    (r'^chomp', "SFX/Shared/Eat"),
    (r'^(attack|stab|smash|swing|Swing|punch|slam)', "SFX/Zombies/Attack"),
    (r'^(hit|Hit|splat|impact|afterSplat)', "SFX/Zombies/Hit"),
    (r'^(armor|helmet|bucket|cone|shield|break|bd_break)', "SFX/Zombies/Armor"),
    (r'^(spawn|rise|emerge|burrow)', "SFX/Zombies/Spawn"),

    # --- plants -----------------------------------------------------------
    (r'^(foodStart|foodSay|foodEnd|foodShoot|foodLob|foodHit|food|plantFood)',
     "SFX/Plants/PlantFood"),
    (r'^(shoot|Shoot|preshoot|bigShoot|reload|spit|firing)', "SFX/Plants/Shoot"),
    (r'^(lob|throw|plantThrow|catapult|pult)', "SFX/Plants/Lob"),
    (r'^(expl|explode)', "SFX/Plants/Explode"),
    (r'^(plant1|plant2|planting|seedling|grow)', "SFX/Plants/Place"),
    (r'^(charge|chargeup|idle)', "SFX/Plants/Idle"),

    # --- board, ui, pickups ----------------------------------------------
    (r'^(collect|coinCollect|gemCollect|keyCollect|mapCollect|sauceCollect'
     r'|powerupCollect|upgradeCollect|dangerroomCollect)', "SFX/Collect"),
    (r'^(drop|coinDrop|bug_drop)', "SFX/Collect/Drop"),
    # The 2x toggle. PVZGE's UI calls the control s2xButton, so these are the
    # fast-forward sounds - unlike speed_up/speedup*, which belong to a zombie
    # animation and are filed with the zombies.
    (r'^2x(_|$)', "SFX/UI/FastForward"),
    (r'^(seed|shovel|Button|click|Click|Brain|tap|refuse|buzz)', "SFX/UI"),
    (r'^(wave|hugewave|finalwave|flag)', "SFX/Board/Wave"),
    (r'^(engine|wheel|cart|rail)', "SFX/Board/Vehicle"),
    (r'^(shake|dig|DoorShake|DoorPull)', "SFX/Board"),
    # Everything else zen-named is a garden effect (jukebox, watering, tools).
    (r'^(zen|Zen)', "SFX/ZenGarden"),
    (r'^(intro|outro|celebrate|starting)', "SFX/Flow"),
]

WORLDS = ["beach", "cowboy", "dark", "dino", "egypt", "eighties", "future",
          "iceage", "kongfu", "lostcity", "modern", "pirate", "sky", "tutorial",
          "jam", "zomboss", "victory"]


## A leftover group needs at least this many clips to get its own folder.
MIN_GROUP = 4


def fallback_group(name):
    """The token a leftover clip is grouped under."""
    return re.split(r'[_0-9]', name, maxsplit=1)[0] or "misc"


def classify(name, path):
    """-> destination subtree for this clip, before small groups are merged."""
    # Music carries a real asset path; trust it over any name rule.
    if path and path.startswith("music/"):
        parts = path.split("/")
        if len(parts) >= 3 and parts[1] == "inGame":
            return "Music/InGame/" + parts[2].capitalize()
        return "Music/" + (parts[1].capitalize() if len(parts) > 2 else "Misc")

    for pattern, dest in RULES:
        if re.match(pattern, name):
            # Fan world-flavoured clips out per world so the big families split.
            lowered = name.lower()
            for world in WORLDS:
                if world in lowered:
                    return "%s/%s" % (dest, world.capitalize())
            return dest

    # Unclaimed: group by the token before the first underscore, which in
    # practice is the entity or system the clip belongs to.
    return "SFX/Other/" + fallback_group(name)


def main():
    if len(sys.argv) < 4:
        print(__doc__)
        return 2
    project, index_path, mp3_dir = sys.argv[1], sys.argv[2], sys.argv[3]
    dry = "--dry-run" in sys.argv

    index = json.load(open(index_path, encoding="utf-8"))
    root = os.path.join(project, "Assets", "PVZGE")

    # Locate every extracted file by uuid, whatever subdirectory it sits in.
    on_disk = {}
    for dirpath, _dirs, files in os.walk(mp3_dir):
        for f in files:
            if f.endswith(".mp3"):
                on_disk[f[:-len(".mp3")]] = os.path.join(dirpath, f)
    print("files on disk: %d   named assets: %d" % (len(on_disk), len(index)))

    # First pass: how big is each leftover group? Small ones get merged so the
    # tree does not end up mostly one-file folders.
    group_size = collections.Counter()
    for info in index.values():
        dest = classify(info["name"], info.get("path"))
        if dest.startswith("SFX/Other/"):
            group_size[dest] += 1
    merged = {g for g, n in group_size.items() if n < MIN_GROUP}

    planned = collections.defaultdict(list)
    taken = set()
    missing = 0
    for uid, info in sorted(index.items(), key=lambda kv: kv[1]["name"].lower()):
        src = on_disk.get(uid)
        if src is None:
            missing += 1
            continue
        dest_dir = classify(info["name"], info.get("path"))
        if dest_dir in merged:
            initial = (fallback_group(info["name"])[:1] or "_").upper()
            dest_dir = "SFX/Other/_misc/%s" % (initial if initial.isalpha() else "_")
        # 462 names are reused across assets; keep both rather than clobber.
        # 462 names are reused across assets; keep both rather than clobber.
        # Probing for a free name rather than appending a counter matters
        # because some clips are already called "foo_2", and a blind suffix
        # would land on top of one.
        base = info["name"]
        fname = "%s.mp3" % base
        n = 1
        while "%s/%s" % (dest_dir, fname) in taken:
            n += 1
            fname = "%s__%d.mp3" % (base, n)
        taken.add("%s/%s" % (dest_dir, fname))
        planned[dest_dir].append((src, fname))

    total = sum(len(v) for v in planned.values())
    print("to stage: %d clips into %d folders (%d indexed but not on disk)"
          % (total, len(planned), missing))
    for dest in sorted(planned)[:24]:
        print("   %-34s %4d" % (dest, len(planned[dest])))
    if len(planned) > 24:
        print("   ... and %d more folders" % (len(planned) - 24))
    if dry:
        print("\n--dry-run: nothing written")
        return 0

    if os.path.isdir(root):
        shutil.rmtree(root)
    copied = 0
    for dest, items in planned.items():
        out = os.path.join(root, dest)
        os.makedirs(out, exist_ok=True)
        for src, fname in items:
            shutil.copy2(src, os.path.join(out, fname))
            copied += 1
    print("\nstaged %d clips -> %s" % (copied, root))
    return 0


if __name__ == "__main__":
    sys.exit(main())
