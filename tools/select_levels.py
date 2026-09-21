#!/usr/bin/env python3
"""Copy a subset of converted levels into the game's content folder.

The full conversion produces 1258 levels; the game only ships the ones that are
actually wired up. This picks them by stage and gives them readable ids, so the
selection is repeatable instead of a one-off copy.

    python3 tools/select_levels.py <native_dir> <dest> [stage] [match] [prefix]

`match` filters on the level's comment, which is needed because a few levels
carry a stage they do not belong to (a Beach level tagged TutorialStage).

`prefix` names files `<prefix>_<number>.json` instead of using the comment.
PVZGE reuses "Tutorial 1" as the comment for level 4, so for an ordered set
the level number is the reliable name.
"""
import json, glob, os, re, sys

DEFAULT_STAGE = "TutorialStage"


def slugify(text, fallback):
    slug = re.sub(r"[^a-z0-9]+", "_", (text or "").lower()).strip("_")
    return slug or fallback


def main():
    src = sys.argv[1]
    dest = sys.argv[2] if len(sys.argv) > 2 else "data/native/levels"
    stage = sys.argv[3] if len(sys.argv) > 3 else DEFAULT_STAGE
    match = sys.argv[4] if len(sys.argv) > 4 else ""
    prefix = sys.argv[5] if len(sys.argv) > 5 else ""

    # Clear the destination first. Without this a level renamed by a change of
    # naming scheme lingers under its old name and is still loaded.
    os.makedirs(dest, exist_ok=True)
    for name in os.listdir(dest):
        if name.endswith(".json"):
            os.remove(os.path.join(dest, name))

    candidates = []
    for path in sorted(glob.glob(os.path.join(src, "*.json"))):
        level = json.load(open(path, encoding="utf-8"))
        if (level.get("stage") or "") != stage:
            continue
        # Levels without a number are the level-of-the-day variants; skip them.
        if level.get("number") is None:
            continue
        if match and match.lower() not in (level.get("comment") or "").lower():
            continue
        candidates.append(level)

    # Name in level order, so level 1 gets the unsuffixed name rather than
    # whichever file the glob happened to reach first.
    candidates.sort(key=lambda l: l["number"])

    picked = []
    used = set()
    for level in candidates:
        number = level["number"]
        if prefix:
            name = f"{prefix}_{number}.json"
        else:
            slug = slugify(level.get("comment"), f"level_{number}")
            name = f"{slug}.json"
            if name in used:
                # "Tutorial 1" is reused as a title by a later level.
                name = f"{slug}_n{number}.json"
        used.add(name)
        level["id"] = name[:-len(".json")]
        with open(os.path.join(dest, name), "w", encoding="utf-8") as fh:
            json.dump(level, fh, ensure_ascii=False, indent=1)
        picked.append((number, name, level))

    for number, name, level in picked:
        seeds = (level.get("seedbank") or {}).get("preset")
        rows = level.get("plantable_rows")
        extras = []
        if rows:
            extras.append(f"lanes={rows}")
        if level.get("tutorial_script"):
            extras.append(f"script={level['tutorial_script']}")
        print(f"  #{number}  {name:20} waves={len(level.get('waves', [])):<3}"
              f" seeds={seeds} {' '.join(extras)}")
    print(f"\n{len(picked)} levels -> {dest}")


if __name__ == "__main__":
    main()
