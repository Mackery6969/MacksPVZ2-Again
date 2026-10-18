#!/usr/bin/env python3
"""Convert PVZGE's monolithic prop sheets into per-entity native files.

Two transforms happen here.

1. Layout: one 268KB ZombieProps.json becomes one file per zombie, so a mod can
   override a single entity without touching (or merge-conflicting on) the rest.

2. Ownership inversion: PopCap stores interactions as negative, plant-named
   booleans on the zombie (`CannotBeSwallowedByChomper`). That means shipping a
   new plant requires editing every zombie. We invert it - the zombie declares
   positive capability TAGS describing what it is, and each plant carries its
   own rule naming the tags it needs. A new plant then touches zero zombies.
"""
import json, os, sys, collections

# Negative PopCap flag -> positive capability tag.
# Absent flag means the zombie HAS the capability, so we emit the tag when the
# flag is missing or false, and withhold it when the flag is true.
CAPABILITY_FLAGS = {
    "CannotBeSwallowedByChomper":      "swallowable",
    "CannotBeGrabbedByPtero":          "grabbable",
    "CannotBeTossedByCitron":          "tossable",
    "CannotBeDraggedByTangleKelp":     "draggable",
    "CannotBeEnlightenedBySolarSage":  "enlightenable",
    "CannotBeTransformedByWitchHazel": "transformable",
    "CannotBeHypnotizedByProjectiles": "hypnotizable",
    "CannotBeKnockedBackByProjectiles": "knockbackable",
    "CannotBeCarriedByFanStorm":       "carriable",
    "CannotBeGummedByGumnut":          "gummable",
    "CannotBePushedBySliders":         "pushable",
    "CannotBeChompedByTyranno":        "chompable",
    "CannotBeDetectedByPowerToss":     "toss_detectable",
    "CannotBeFlickedByPowerToss":      "flickable",
    "CannotChangeLaneByPowerToss":     "lane_movable",
    "CannotBeDetectedBySapfling":      "sap_detectable",
    "CannotCarryPlantfoodsInWaves":    "plantfood_carrier",
    "ImmuneToGarlic":                  "divertable",
    "ImmuneToShrinkingViolet":         "shrinkable",
    "ImmuneToSweetPotato":             "attractable",
    "ImmuneToSporeShroom":             "sporeable",
    "ImmuneToZomboss":                 "zomboss_damageable",
    "IgnoredBySnapPea":                "snap_targetable",
    "IgnoredByHomingThistle":          "homing_targetable",
    "IgnoredByThymeWarp":              "warpable",
}

# Descriptive flags that stay as positive tags in their own right.
TRAIT_FLAGS = {
    "LivesInDeepWater": "deep_water",
    "IsMetal":          "metal",
    "NormalDeathWhenMowed": "normal_death_when_mowed",
}

# Core numeric stats: PopCap name -> native name.
STATS = {
    "Toughness":     "toughness",
    "WalkSPS":       "speed",
    "EatDPS":        "eat_dps",
    "WavePointCost": "wave_cost",
    "Weight":        "weight",
}


def split_zombie(name, entry, prop_lookup):
    d = entry.get("objdata") or {}
    out = collections.OrderedDict()
    out["id"] = name

    based_on = d.get("ZombieBasedOn")
    if based_on and based_on != name:
        out["extends"] = based_on          # inheritance: archetype chain

    props_ref = d.get("Properties")
    props = prop_lookup(props_ref) if props_ref else {}
    merged = {**props, **{k: v for k, v in d.items()
                          if k not in ("ZombieBasedOn", "Properties")}}

    stats = {}
    for src, dst in STATS.items():
        if merged.get(src) is not None:
            stats[dst] = merged[src]
    if stats:
        out["stats"] = stats

    if merged.get("ZombieSort"):
        out["sort"] = merged["ZombieSort"]

    # Capability tags (positive) - the inversion.
    tags = []
    for flag, tag in CAPABILITY_FLAGS.items():
        if not merged.get(flag):
            tags.append(tag)
    for flag, tag in TRAIT_FLAGS.items():
        if merged.get(flag):
            tags.append(tag)
    if tags:
        out["tags"] = sorted(tags)

    # Composition: armor is already component-shaped in the source data.
    components = []
    for armor in (merged.get("StartingArmors") or []):
        if isinstance(armor, dict):
            components.append({
                "type": "armor",
                "armor": strip_rtid(armor.get("ArmorType") or armor.get("Type")),
                "slot": armor.get("AttachmentName") or armor.get("Slot"),
            })
        else:
            components.append({"type": "armor", "armor": strip_rtid(armor)})
    if merged.get("AttackRect"):
        components.append({"type": "attack_rect", "rect": strip_rtid(merged["AttackRect"])})
    if merged.get("HitRect"):
        components.append({"type": "hit_rect", "rect": strip_rtid(merged["HitRect"])})
    if components:
        out["components"] = components

    known = (set(STATS) | set(CAPABILITY_FLAGS) | set(TRAIT_FLAGS)
             | {"ZombieSort", "StartingArmors", "AttackRect", "HitRect",
                "ZombieBasedOn", "Properties"})
    rest = {k: v for k, v in merged.items() if k not in known}
    if rest:
        out["extra"] = rest
    return out


def fresh_dir(path):
    """Create `path`, clearing any .json this tool wrote on a previous run.

    Without this, an entity that moves between categories - a potion leaving
    plants/ for objects/ - would still be loaded from its old location.
    """
    os.makedirs(path, exist_ok=True)
    for name in os.listdir(path):
        if name.endswith(".json"):
            os.remove(os.path.join(path, name))
    return path


def strip_rtid(v):
    if isinstance(v, str) and v.startswith("RTID(") and "@" in v:
        return v[5:].split("@")[0]
    return v




# --------------------------------------------------------------------------
# plants
# --------------------------------------------------------------------------

# PopCap's "Family" tells us what a plant fundamentally does, which maps
# cleanly onto one behaviour component. Each entry lists the component type
# and the source fields it draws its config from.
FAMILY_COMPONENTS = {
    "Peashooter": ("shooter", {"PeaType": "projectile", "ShootInterval": "interval",
                               "ShootIntervalAdditional": "interval_jitter",
                               "PeaTypePlantfood": "projectile_plantfood",
                               "PlantfoodPeaCount": "plantfood_count"}),
    # SunValue is deliberately NOT mapped: every sun is worth SunToken.VALUE,
    # so the amount is not a per-plant knob. It falls through to `extra`,
    # preserved but not advertised as live config.
    "Sun":        ("sun_producer", {"ProduceInterval": "interval",
                                    "ProduceIntervalAdditional": "interval_jitter",
                                    "ProduceCountdownStart": "first_delay",
                                    "ProduceCountdownStartAdditional": "first_delay_jitter"}),
    "Lobber":     ("lobber", {"CabbageType": "projectile", "ThrowInterval": "interval",
                              "ThrowIntervalAdditional": "interval_jitter",
                              "CabbageTypePlantfood": "projectile_plantfood"}),
    "Melee":      ("melee", {"Damage": "damage", "DamageHeavy": "damage_heavy",
                             "AttackInterval": "interval",
                             "ZombieDetectorWidth": "detect_width",
                             "TombDetectorWidth": "tomb_detect_width"}),
    "Explosive":  ("explosive", {"Damage": "damage", "ChargeTime": "charge_time",
                                 "PlantfoodChildrenCount": "plantfood_children"}),
    "Defence":    ("blocker", {"ArmorToughness": "armor_toughness"}),
}

PLANT_STATS = {
    "SunCost":       "sun_cost",
    "Toughness":     "toughness",
    "Cooldown":      "cooldown",
    "CooldownFrom":  "cooldown_from",
    "BeghouledCost": "beghouled_cost",
}


def split_plant(name, entry, prop_lookup):
    d = entry.get("objdata") or {}
    out = collections.OrderedDict()
    out["id"] = name

    based_on = d.get("PlantBasedOn")
    if based_on and based_on != name:
        out["extends"] = based_on

    props = prop_lookup(d.get("Properties")) if d.get("Properties") else {}
    merged = {**props, **{k: v for k, v in d.items()
                          if not k.startswith("//") and k not in ("PlantBasedOn", "Properties")}}

    family = merged.get("Family")
    if family:
        out["family"] = family

    stats = {}
    for src, dst in PLANT_STATS.items():
        if merged.get(src) is not None:
            stats[dst] = merged[src]
    if stats:
        out["stats"] = stats

    used = set(PLANT_STATS) | {"Family", "MintBoostedProps"}
    components = []
    if family in FAMILY_COMPONENTS:
        ctype, fields = FAMILY_COMPONENTS[family]
        cfg = {"type": ctype}
        for src, dst in fields.items():
            if merged.get(src) is not None:
                cfg[dst] = strip_rtid(merged[src])
                used.add(src)
        components.append(cfg)
    if components:
        out["components"] = components

    tags = []
    if name in AQUATIC_PLANTS:
        tags.append("aquatic")
    if name in CARRIER_PLANTS:
        # "provides:<tag>" is what the board reads to mark a cell satisfied.
        tags.append("provides:" + CARRIER_PLANTS[name])
    if tags:
        out["tags"] = tags

    if merged.get("MintBoostedProps"):
        mb = merged["MintBoostedProps"]
        out["mint_boost"] = {"resistance": mb.get("ResistanceMult"),
                             "speed": mb.get("SpeedMult"),
                             "plantfood": mb.get("Plantfood")}

    rest = {k: v for k, v in merged.items() if k not in used}
    if rest:
        out["extra"] = rest
    return out


def write_plants(data_dir, out_root):
    types = json.load(open(os.path.join(data_dir, "PlantTypes.json"), encoding="utf-8"))
    props = json.load(open(os.path.join(data_dir, "PlantProps.json"), encoding="utf-8"))

    def prop_lookup(ref):
        entry = props.get(strip_rtid(ref))
        return (entry.get("objdata") or {}) if entry else {}

    out_dir = fresh_dir(os.path.join(out_root, "plants"))
    manifest, fam = {}, collections.Counter()
    for name, entry in sorted(types.items()):
        if name in PLANTS_THAT_ARE_OBJECTS:
            continue  # emitted by write_objects instead
        native = split_plant(name, entry, prop_lookup)
        open(os.path.join(out_dir, f"{name}.json"), "w", encoding="utf-8").write(
            json.dumps(native, ensure_ascii=False, indent=1))
        manifest[name] = {"file": f"plants/{name}.json", "family": native.get("family")}
        fam[native.get("family")] += 1
    json.dump(manifest, open(os.path.join(out_root, "plants.manifest.json"), "w"), indent=1)
    print(f"wrote {len(manifest)} plant files -> {out_dir}")
    print("families:", dict(fam.most_common(8)))




def write_simple_sheet(data_dir, out_root, types_file, props_file, subdir,
                       stat_map, id_key):
    """Emit a simple per-entity sheet (projectiles, armors) with no archetypes."""
    types_path = os.path.join(data_dir, types_file)
    props = json.load(open(os.path.join(data_dir, props_file), encoding="utf-8"))
    types = (json.load(open(types_path, encoding="utf-8"))
             if os.path.exists(types_path) else {k: {} for k in props})

    out_dir = fresh_dir(os.path.join(out_root, subdir))
    manifest = {}
    for name in sorted(set(list(types) + list(props))):
        tdata = (types.get(name, {}).get("objdata") or {})
        ref = tdata.get("Properties")
        pdata = {}
        if ref:
            entry = props.get(strip_rtid(ref))
            pdata = (entry.get("objdata") or {}) if entry else {}
        if not pdata:
            entry = props.get(name)
            pdata = (entry.get("objdata") or {}) if entry else {}
        merged = {**pdata, **{k: v for k, v in tdata.items()
                              if not k.startswith("//") and k != "Properties"}}

        out = collections.OrderedDict()
        out["id"] = name
        based = merged.pop(id_key, None)
        if based and based != name:
            out["extends"] = based
        stats = {}
        for src, dst in stat_map.items():
            if merged.get(src) is not None:
                stats[dst] = merged[src]
        if stats:
            out["stats"] = stats
        rest = {k: v for k, v in merged.items() if k not in stat_map}
        if rest:
            out["extra"] = rest
        open(os.path.join(out_dir, f"{name}.json"), "w", encoding="utf-8").write(
            json.dumps(out, ensure_ascii=False, indent=1))
        manifest[name] = {"file": f"{subdir}/{name}.json"}
    json.dump(manifest, open(os.path.join(out_root, f"{subdir}.manifest.json"), "w"), indent=1)
    print(f"wrote {len(manifest)} {subdir} files")




# --------------------------------------------------------------------------
# graves and objects
# --------------------------------------------------------------------------

# PVZGE files these under PlantTypes, but they are zombie-side board objects,
# not plants. Leaving them as plants pollutes seed banks and level generation,
# so they are reclassified here.
PLANTS_THAT_ARE_OBJECTS = {
    "zombiepotion_invisibility",
    "zombiepotion_speed",
    "zombiepotion_toughness",
}

# Terrain the game needs but PVZGE does not ship as tiles. Big Wave Beach
# water and Sky's open air are board properties there (BoardGridMapProps),
# not entries in the tile list, so they are defined here instead - as data,
# with the same rules, which is what lets one mechanism serve both.
EXTRA_TERRAIN = {
    "water": {
        "category": "liquid",
        "stats": {"requires_tag": "aquatic"},
        "comment": "Only aquatic plants go here, or anything on a lily pad.",
    },
    "deep_water": {
        "category": "liquid",
        "stats": {"blocks_planting": True},
        "comment": "Nothing can be planted in deep water.",
    },
    "sky_gap": {
        "category": "tile",
        "stats": {"requires_tag": "airborne"},
        "comment": "Sky's open air - needs a plant that can sit on nothing, "
                   "or a platform placed first.",
    },
    "sky_void": {
        "category": "tile",
        "stats": {"blocks_planting": True},
        "comment": "Open air with no platform possible.",
    },
}

# Terrain rules for tiles PVZGE ships without them. The rules are the same
# shape for every case, which is the point: pool tiles and Sky's open air are
# both "needs a tag", lava and craters are both "nothing here".
TERRAIN_RULES = {
    # Standing water, including the side-quest pothole pools.
    "potholepool": {"requires_tag": "aquatic"},
    "potholepuddle": {"requires_tag": "aquatic"},
    # Lava and molten pools destroy anything placed in them.
    "lava": {"blocks_planting": True},
    "lava_mint": {"blocks_planting": True},
    "lavaguava": {"blocks_planting": True},
    "moltenpool": {"blocks_planting": True},
    "moltenpool_mint": {"blocks_planting": True},
    # The endangered tile holds the plant a level asks you to protect, so it
    # is occupied rather than open.
    "endangered": {"blocks_planting": True},
}

# Plants that cope with water, and the ones that make a cell viable for
# others. A lily pad provides what water requires, which is the whole of the
# rule - no special case for lily pads anywhere in the board code.
AQUATIC_PLANTS = {"lilypad", "tanglekelp", "guacodile", "bowlingbulb",
                  "rotobaga", "banana_launcher"}
CARRIER_PLANTS = {"lilypad": "aquatic", "skyplatform": "airborne"}

GRAVE_STATS = {
    "Toughness": "toughness",
    "Flying": "flying",
    "GraveBusterPlantable": "gravebuster_plantable",
    "HotPotatoMeltable": "hot_potato_meltable",
    "PlantfoodCount": "plantfood_count",
}

OBJECT_STATS = {
    "Toughness": "toughness",
    "DefaultRecoverDelay": "recover_delay",
}


def write_lawns(data_dir, out_root):
    """Stage -> lawn settings, including which music track it plays.

    This is what lets worlds scale: a level names a stage, the stage names a
    track, and the audio catalog maps that track to an FMOD event. Adding a
    world means adding data, not code.
    """
    lawns = json.load(open(os.path.join(data_dir, "LawnProps.json"), encoding="utf-8"))
    out_dir = fresh_dir(os.path.join(out_root, "lawns"))
    manifest = {}
    for name, entry in sorted(lawns.items()):
        d = entry.get("objdata") or {}
        out = collections.OrderedDict()
        out["id"] = name
        if d.get("Music"):
            out["music"] = d["Music"]
        if d.get("Mower"):
            out["mower"] = d["Mower"]
        if d.get("RailCart"):
            out["railcart"] = d["RailCart"]
        out["night"] = bool(d.get("IsAtNight", False))

        # The zombie roster a stage substitutes in for generic wave slots.
        roster = {}
        for key, value in d.items():
            if key.endswith("_Zombie") and isinstance(value, list):
                roster[key[:-len("_Zombie")].lower()] = value
        if roster:
            out["zombie_roster"] = roster
        if d.get("Gravestone"):
            out["gravestones"] = d["Gravestone"]

        known = {"Music", "Mower", "RailCart", "IsAtNight", "Gravestone"}
        rest = {k: v for k, v in d.items()
                if k not in known and not k.endswith("_Zombie")}
        if rest:
            out["extra"] = rest

        open(os.path.join(out_dir, f"{name}.json"), "w", encoding="utf-8").write(
            json.dumps(out, ensure_ascii=False, indent=1))
        manifest[name] = {"file": f"lawns/{name}.json", "music": out.get("music")}
    json.dump(manifest, open(os.path.join(out_root, "lawns.manifest.json"), "w"), indent=1)
    tracks = sorted({m["music"] for m in manifest.values() if m["music"]})
    print(f"wrote {len(manifest)} lawn files ({len(tracks)} music tracks)")


def write_graves(data_dir, out_root):
    """Gravestones: destroyable board objects that can fire grid-item events."""
    gi = json.load(open(os.path.join(data_dir, "GridItemTypes.json"), encoding="utf-8"))
    props = json.load(open(os.path.join(data_dir, "TombstoneProps.json"), encoding="utf-8"))

    out_dir = fresh_dir(os.path.join(out_root, "graves"))
    manifest = {}
    for name, entry in sorted(gi.items()):
        if entry.get("objclass") != "TombstoneType":
            continue
        d = entry.get("objdata") or {}
        ref = strip_rtid(d.get("Properties")) or name
        pdata = (props.get(ref, {}).get("objdata") or {})
        merged = {**pdata, **{k: v for k, v in d.items()
                              if not k.startswith("//") and k != "Properties"}}

        out = collections.OrderedDict()
        out["id"] = name
        based = merged.pop("TombstoneBasedOn", None)
        if based and based != name:
            out["extends"] = based

        stats = {}
        for src, dst in GRAVE_STATS.items():
            if merged.get(src) is not None:
                stats[dst] = merged[src]
        if stats:
            out["stats"] = stats

        components = []
        if merged.get("HitRect"):
            components.append({"type": "hit_rect", "rect": strip_rtid(merged["HitRect"])})
        # A grave that summons on a timer is the "grid item event" case.
        if merged.get("SummonInterval") or merged.get("SummonnedZombies"):
            spawn = {"type": "grave_summon"}
            iv = merged.get("SummonInterval")
            if isinstance(iv, dict):
                spawn["interval_min"] = iv.get("Min")
                spawn["interval_max"] = iv.get("Max")
            if merged.get("SummonnedZombies"):
                spawn["zombies"] = [
                    {"type": strip_rtid(z.get("Type")), "weight": z.get("Weight")}
                    if isinstance(z, dict) else {"type": strip_rtid(z)}
                    for z in merged["SummonnedZombies"]]
            components.append(spawn)
        if components:
            out["components"] = components

        used = set(GRAVE_STATS) | {"HitRect", "SummonInterval", "SummonnedZombies",
                                   "TombstoneBasedOn", "Properties"}
        rest = {k: v for k, v in merged.items() if k not in used}
        if rest:
            out["extra"] = rest

        open(os.path.join(out_dir, f"{name}.json"), "w", encoding="utf-8").write(
            json.dumps(out, ensure_ascii=False, indent=1))
        manifest[name] = {"file": f"graves/{name}.json"}
    json.dump(manifest, open(os.path.join(out_root, "graves.manifest.json"), "w"), indent=1)
    print(f"wrote {len(manifest)} grave files")


def write_objects(data_dir, out_root):
    """Board objects: tiles, liquids, traps, and the misfiled evil potions."""
    gi = json.load(open(os.path.join(data_dir, "GridItemTypes.json"), encoding="utf-8"))
    tile_props = json.load(open(os.path.join(data_dir, "TileProps.json"), encoding="utf-8"))
    plant_props = json.load(open(os.path.join(data_dir, "PlantProps.json"), encoding="utf-8"))

    out_dir = fresh_dir(os.path.join(out_root, "objects"))
    manifest = {}

    def emit(name, merged, category, based_key=None):
        out = collections.OrderedDict()
        out["id"] = name
        out["category"] = category
        based = merged.pop(based_key, None) if based_key else None
        if based and based != name:
            out["extends"] = based
        stats = {}
        for src, dst in OBJECT_STATS.items():
            if merged.get(src) is not None:
                stats[dst] = merged[src]
        # Sliders carry a plant along the lane, which is behaviour rather than
        # a placement rule, so they get a component instead of terrain flags.
        if name.startswith("slider_"):
            direction = "up" if "_up" in name else "down"
            out["components"] = [{"type": "slide_tile", "direction": direction}]
        stats.update(TERRAIN_RULES.get(name, {}))
        if stats:
            out["stats"] = stats
        rest = {k: v for k, v in merged.items() if k not in OBJECT_STATS}
        if rest:
            out["extra"] = rest
        open(os.path.join(out_dir, f"{name}.json"), "w", encoding="utf-8").write(
            json.dumps(out, ensure_ascii=False, indent=1))
        manifest[name] = {"file": f"objects/{name}.json", "category": category}

    for name, entry in sorted(gi.items()):
        cls = entry.get("objclass")
        if cls not in ("TileType", "TileLiquidType"):
            continue
        d = entry.get("objdata") or {}
        ref = strip_rtid(d.get("Properties")) or name
        pdata = (tile_props.get(ref, {}).get("objdata") or {})
        merged = {**pdata, **{k: v for k, v in d.items()
                              if not k.startswith("//") and k != "Properties"}}
        emit(name, merged, "liquid" if cls == "TileLiquidType" else "tile",
             "TileBasedOn")

    for name, spec in sorted(EXTRA_TERRAIN.items()):
        out = collections.OrderedDict()
        out["id"] = name
        if spec.get("comment"):
            out["//"] = spec["comment"]
        out["category"] = spec["category"]
        out["stats"] = spec["stats"]
        open(os.path.join(out_dir, f"{name}.json"), "w", encoding="utf-8").write(
            json.dumps(out, ensure_ascii=False, indent=1))
        manifest[name] = {"file": f"objects/{name}.json",
                          "category": spec["category"]}

    for name in sorted(PLANTS_THAT_ARE_OBJECTS):
        entry = plant_props.get(name)
        if entry is None:
            continue
        merged = dict(entry.get("objdata") or {})
        merged.pop("Family", None)
        emit(name, merged, "potion")

    json.dump(manifest, open(os.path.join(out_root, "objects.manifest.json"), "w"), indent=1)
    print(f"wrote {len(manifest)} object files "
          f"({len(PLANTS_THAT_ARE_OBJECTS)} reclassified from plants, "
          f"{len(EXTRA_TERRAIN)} terrain types defined here)")


def main():
    data_dir, out_root = sys.argv[1], sys.argv[2]
    types = json.load(open(os.path.join(data_dir, "ZombieTypes.json"), encoding="utf-8"))
    props = json.load(open(os.path.join(data_dir, "ZombieProps.json"), encoding="utf-8"))

    def prop_lookup(ref):
        key = strip_rtid(ref)
        entry = props.get(key)
        return (entry.get("objdata") or {}) if entry else {}

    # Pass 1: build every entity, grouped by its ZombieSort archetype.
    built = {}
    by_sort = collections.defaultdict(list)
    for name, entry in sorted(types.items()):
        native = split_zombie(name, entry, prop_lookup)
        built[name] = native
        by_sort[native.get("sort") or "Normal"].append(name)

    # Derive each archetype's default tag set: tags held by a majority of its
    # members. Entities then store only their difference from that default.
    archetypes = {}
    for sort, members in by_sort.items():
        counts = collections.Counter()
        for m in members:
            for t in built[m].get("tags", []):
                counts[t] += 1
        half = len(members) / 2
        archetypes[sort] = sorted(t for t, c in counts.items() if c > half)

    arch_dir = os.path.join(out_root, "archetypes")
    out_dir = os.path.join(out_root, "zombies")
    fresh_dir(arch_dir)
    fresh_dir(out_dir)

    for sort, tags in archetypes.items():
        slug = sort.lower()
        json.dump({"id": slug, "kind": "zombie_archetype", "tags": tags},
                  open(os.path.join(arch_dir, f"{slug}.json"), "w", encoding="utf-8"),
                  ensure_ascii=False, indent=1)

    manifest = {}
    before = after = 0
    for name, native in built.items():
        sort = native.get("sort") or "Normal"
        default = set(archetypes[sort])
        mine = set(native.pop("tags", []))
        before += len(mine)

        delta = {}
        added, removed = sorted(mine - default), sorted(default - mine)
        if added:
            delta["add"] = added
        if removed:
            delta["remove"] = removed
        after += len(added) + len(removed)

        # Rebuild in a stable, readable key order.
        out = collections.OrderedDict()
        out["id"] = native["id"]
        out["extends"] = native.pop("extends", None) or sort.lower()
        for k in ("stats", "sort"):
            if k in native:
                out[k] = native[k]
        if delta:
            out["tags"] = delta
        for k in ("components", "extra"):
            if k in native:
                out[k] = native[k]

        open(os.path.join(out_dir, f"{name}.json"), "w", encoding="utf-8").write(
            json.dumps(out, ensure_ascii=False, indent=1))
        manifest[name] = {"file": f"zombies/{name}.json", "extends": out["extends"]}

    json.dump(manifest, open(os.path.join(out_root, "zombies.manifest.json"), "w"), indent=1)
    print(f"wrote {len(manifest)} zombies + {len(archetypes)} archetypes")
    print(f"archetypes: {sorted(archetypes)}")
    print(f"tag lines: {before} -> {after}  ({(1-after/before)*100:.0f}% less noise)")

    write_plants(data_dir, out_root)

    write_simple_sheet(data_dir, out_root, "ProjectileTypes.json", "ProjectileProps.json",
                       "projectiles", {"Damage": "damage"}, "ProjectileBasedOn")
    write_simple_sheet(data_dir, out_root, "ArmorTypes.json", "ArmorProps.json",
                       "armors", {"Toughness": "toughness",
                                  "BowlingLevel": "bowling_level",
                                  "isMetal": "is_metal", "isIce": "is_ice"},
                       "ArmorBasedOn")

    write_lawns(data_dir, out_root)
    write_graves(data_dir, out_root)
    write_objects(data_dir, out_root)


if __name__ == "__main__":
    main()
