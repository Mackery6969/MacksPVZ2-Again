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
# I-Zombie needs a placement cost per zombie, and PopCap's data has none -
# those costs are a PvZ1 mechanic. WavePointCost already encodes how much a
# zombie is "worth" when a wave spends its budget, so the cost is derived from
# it and snapped to 25s to keep the economy readable. A zombie file can state
# its own `sun_cost` to override this.
SUN_COST_BASE = 50
SUN_COST_PER_WAVE_POINT = 0.12
SUN_COST_SNAP = 25
SUN_COST_MAX = 500


def derive_sun_cost(wave_cost):
    """-> a placement cost for I-Zombie style levels."""
    raw = SUN_COST_BASE + float(wave_cost or 0) * SUN_COST_PER_WAVE_POINT
    snapped = int(round(raw / SUN_COST_SNAP) * SUN_COST_SNAP)
    return max(SUN_COST_SNAP, min(snapped, SUN_COST_MAX))


STATS = {
    "Toughness":     "toughness",
    "WalkSPS":       "speed",
    "EatDPS":        "eat_dps",
    "WavePointCost": "wave_cost",
    "Weight":        "weight",
}


# Zombie behaviour, derived the same way plant behaviour is: from the fields
# an entry carries. ZombieSort is the tempting discriminator and the wrong one
# - it separates Normal from Gargantuar from Zomboss, which says nothing about
# what a zombie does. Unlike plants, a zombie can match several of these at
# once: a gargantuar both smashes and throws an imp.
# Health fraction a gargantuar throws its imp at when the entry does not say.
DEFAULT_IMP_THROW_AT = 0.5


def flatten_range(cfg, slot, value):
    """Write `value` into `cfg[slot]`, splitting PopCap's {Min, Max} pairs.

    A range becomes `slot` and `slot_max`, which is what cfg_range reads at
    runtime. Keeping both ends rather than a midpoint and a jitter means a
    `{Min: 0, Max: 1}` column range stays exactly that.
    """
    if isinstance(value, dict) and ("Min" in value or "Max" in value):
        low = value.get("Min", value.get("Max"))
        high = value.get("Max", low)
        cfg[slot] = low
        if high != low:
            cfg[slot + "_max"] = high
    else:
        cfg[slot] = value

ZOMBIE_BEHAVIOURS = [
    ("smasher", ("SmashDamage",),
     {"SmashDamage": "damage", "SmashDistance": "distance",
      "MaxSmashTargetCount": "max_targets", "HammerDuration": "windup",
      "RestDuration": "rest"}),

    ("spawn_inside", ("ZombieInside",),
     {"ZombieInside": "zombie", "ProtectsInside": "protects"}),

    ("escort", ("TeammateType",),
     {"TeammateType": "teammate", "TeamMemberCount": "count"}),

    ("summoner", ("ZombiesToSummon", "ZombieCountToSummon", "ZombiesToSpawn"),
     {"ZombiesToSummon": "zombies", "ZombieTypesToSummonBecomingFlag": "zombies",
      "ZombiesToSpawn": "zombies",
      "ZombieCountToSummon": "count", "SummonCount": "count",
      "TimeBeforeSummon": "first_delay", "TimeBetweenSummon": "interval",
      "SummonTime": "interval", "ZombieSummonDistance": "distance"}),

    # A zombie that is only around for a while: the Kung-Fu bronze statue
    # stands spawning gargantuars until its time runs out.
    ("lifespan", ("Lifespan", "LifeSpan"),
     {"Lifespan": "duration", "LifeSpan": "duration"}),

    ("enrage", ("EnragedDamageScale", "EnragedSpeedScale", "EnrageHealthPct"),
     {"EnragedDamageScale": "damage_scale",
      "EnragedEatingDamageScale": "damage_scale",
      "EnragedSpeedScale": "speed_scale",
      "EnragedWalkingSpeedScale": "speed_scale",
      "EnrageHealthPct": "health_pct"}),
]

# Extra health pools PopCap stores as a bare number rather than as an entry in
# ArmorProps. They behave exactly like armor - destroyed before the body takes
# a hit - so they become armor components with an inline toughness. A poncho
# zombie carries two, which is why these stack rather than pick one.
# BugToughness is deliberately absent: every zombie carrying it reads 0.
INLINE_ARMOR = {
    "ShieldToughness": "plate",
    "PonchoToughness": "poncho",
    "BalloonToughness": "balloon",
    "BoardToughness": "board",
    "GlacierToughness": "glacier",
    "NewspaperHealth": "newspaper",
}

# Interaction modifiers. PopCap writes these as per-plant exceptions on the
# zombie; the ones with a consumer in this build become typed stats or tags,
# and the rest stay in `extra` until the plant they answer to exists.
#
# ChiliStunDurationMult reads 0 on all 54 zombies that carry it, so it is
# flatly "cannot be stunned" rather than a scale - but it is imported as the
# scale it is named for, so a mod can hand out partial resistance.
ZOMBIE_MODIFIERS = {
    "ChiliStunDurationMult": "stun_scale",
    "SpeedScaleInWater": "water_speed_scale",
}

ZOMBIE_TRAITS = {
    # Ice hits these, but it chills instead of holding them still.
    "ChillInsteadOfFreeze": "chill_only",
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
    # Only derive it when the data has not said otherwise.
    if merged.get("SunCost") is not None:
        stats["sun_cost"] = merged["SunCost"]
    else:
        # A zombie with no wave cost still must not be free to place.
        stats["sun_cost"] = derive_sun_cost(stats.get("wave_cost", 0))

    for src_key, dst in ZOMBIE_MODIFIERS.items():
        if merged.get(src_key) is not None:
            stats[dst] = merged[src_key]
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
    for flag, tag in ZOMBIE_TRAITS.items():
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

    known = (set(STATS) | set(CAPABILITY_FLAGS) | set(TRAIT_FLAGS)
             | set(ZOMBIE_MODIFIERS) | set(ZOMBIE_TRAITS)
             | {"SunCost", "ZombieSort", "StartingArmors", "AttackRect",
                "HitRect", "ZombieBasedOn", "Properties"})

    for field, slot in INLINE_ARMOR.items():
        if merged.get(field):
            components.append({"type": "armor", "slot": slot,
                               "toughness": merged[field]})
            known.add(field)

    for ctype, triggers, fields in ZOMBIE_BEHAVIOURS:
        if not any(merged.get(t) is not None for t in triggers):
            continue
        cfg = {"type": ctype}
        for src_key, dst in fields.items():
            if merged.get(src_key) is None:
                continue
            flatten_range(cfg, dst, strip_rtid(merged[src_key]))
            known.add(src_key)
        known.update(triggers)
        components.append(cfg)

    # Carrying an imp means one of two different things, and the field that
    # tells them apart is SmashDamage. A gargantuar throws its imp over the
    # plants as it is worn down; a barrel, a bull or a dropship simply lets
    # its rider out when it breaks, which is ZombieInside's mechanic.
    #
    # The throw thresholds are only stated for three zombies. Every other
    # gargantuar throws at half health, which the game hard-codes and the data
    # therefore omits - so that default lives here rather than in 24 files.
    imp = merged.get("ImpTypes") or merged.get("ImpType")
    if imp is not None:
        thresholds = [merged[k] for k in ("HealthPercentThrowImp0",
                                          "HealthPercentThrowImp1",
                                          "HealthPercentThrowImp2")
                      if merged.get(k) is not None]
        if thresholds or merged.get("SmashDamage") is not None:
            comp = {"type": "imp_thrower"}
            if isinstance(imp, list):
                comp["imps"] = [strip_rtid(i) for i in imp]
            else:
                comp["imp"] = strip_rtid(imp)
            comp["throw_at"] = thresholds or [DEFAULT_IMP_THROW_AT]
            if merged.get("ImpThrowDistance") is not None:
                comp["distance"] = merged["ImpThrowDistance"]
            if merged.get("ImpCount") is not None:
                comp["count"] = merged["ImpCount"]
            components.append(comp)
        else:
            inside = {"type": "spawn_inside"}
            inside["zombie"] = (strip_rtid(imp[0]) if isinstance(imp, list)
                                else strip_rtid(imp))
            if merged.get("ImpCount") is not None:
                inside["count"] = merged["ImpCount"]
            components.append(inside)
        known.update(("ImpType", "ImpTypes", "ImpCount", "ImpThrowDistance",
                      "HealthPercentThrowImp0", "HealthPercentThrowImp1",
                      "HealthPercentThrowImp2"))

    # Two unrelated things summon. An abbot gives one shout and a group walks
    # on - the field is literally ZombieTypesToSummonBecomingFlag, a one-off as
    # it turns into the wave's flag zombie. A gong or a bronze statue keeps
    # calling on a timer. Having an interval is what tells them apart.
    for comp in components:
        if comp["type"] != "summoner" or "interval" in comp:
            continue
        comp["once"] = True
        # An abbot's count says how many to pick from its list. A statue
        # states a list and no count, which reads as one of each - that is
        # the three bronze gargantuars, not three rolls of the same die.
        if "count" not in comp:
            comp["each"] = True

    # Losing the last of its protection is what enrages a newspaper zombie;
    # the data says only how much faster and harder it gets.
    for comp in components:
        if comp["type"] == "enrage" and "health_pct" not in comp:
            comp["on_armor_broken"] = True

    if components:
        out["components"] = components

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

# What a plant DOES is written in the fields it carries, not in its Family.
# Family is a damage type - Shadow and Poison each contain both shooters and
# lobbers, and Sharp contains shooters and melee - so matching on it mislabels
# plants and leaves most of them with no behaviour at all. These signatures
# read the data instead; Family stays on as a tag.
#
# Ordered: the first signature that matches wins, so the specific ones come
# before the general ones.
BEHAVIOUR_SIGNATURES = [
    ("sun_producer", ("ProduceInterval", "SunValue"),
     {"ProduceInterval": "interval", "ProduceIntervalAdditional": "interval_jitter",
      "ProduceCountdownStart": "first_delay",
      "ProduceCountdownStartAdditional": "first_delay_jitter"}),

    ("shooter", ("PeaType", "BoltType", "ProjectileType"),
     {"PeaType": "projectile", "BoltType": "projectile",
      "ProjectileType": "projectile", "ShootInterval": "interval",
      "ShootIntervalAdditional": "interval_jitter",
      "PeaTypePlantfood": "projectile_plantfood",
      "PlantfoodPeaCount": "plantfood_count",
      "PeaCountPerShot": "count_per_shot"}),

    ("lobber", ("CabbageType", "ThrowInterval"),
     {"CabbageType": "projectile", "ThrowInterval": "interval",
      "ThrowIntervalAdditional": "interval_jitter",
      "CabbageTypePlantfood": "projectile_plantfood"}),

    ("timed_shooter", ("AttackProjectileType",),
     {"AttackProjectileType": "projectile", "DetectInterval": "detect_interval",
      "PlantfoodFlickCount": "plantfood_count"}),

    ("area_attacker", ("AttackDPS", "WarmingRadius"),
     {"AttackDPS": "dps", "AttackDistanceMin": "min_distance",
      "AttackDistanceMax": "max_distance", "AttackDuration": "duration",
      "ChargingTime": "charge_time"}),

    ("freeze_burst", ("FreezeDuration", "ChillDuration"),
     {"Damage": "damage", "FreezeDuration": "freeze_duration",
      "ChillDuration": "chill_duration"}),

    ("wind_burst", ("BlowDuration",),
     {"BlowDuration": "duration"}),

    ("stunner", ("StunDuration",),
     {"StunDuration": "duration", "RestTime": "rest_time"}),

    ("tile_placer", ("TileType",),
     {"TileType": "tile"}),

    ("explosive", ("ChargeTime", "ChargingTime", "ExplosionDamage",
                   "Explode0Damage"),
     {"Damage": "damage", "ExplosionDamage": "damage",
      "Explode0Damage": "damage", "ChargeTime": "charge_time",
      "ChargingTime": "charge_time",
      "PlantfoodChildrenCount": "plantfood_children"}),

    ("melee", ("AttackInterval",),
     {"Damage": "damage", "DamageHeavy": "damage_heavy",
      "AttackInterval": "interval", "ZombieDetectorWidth": "detect_width",
      "TombDetectorWidth": "tomb_detect_width", "AttackDistance": "detect_width",
      "DamagePlantfood": "damage_plantfood"}),

    ("blocker", ("ArmorToughness",),
     {"ArmorToughness": "armor_toughness"}),

    ("instant_damage", ("Damage",),
     {"Damage": "damage", "PoisonDPS": "poison_dps",
      "PoisonDuration": "poison_duration"}),

    # Last: a plant with a Lifespan and none of the attack fields above is a
    # Mint - it exists for a while and buffs its family rather than acting.
    ("mint_buff", ("Lifespan",),
     {"Lifespan": "duration", "DamageMultiplier": "damage_multiplier"}),
]

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
    for ctype, triggers, fields in BEHAVIOUR_SIGNATURES:
        if not any(merged.get(t) is not None for t in triggers):
            continue
        cfg = {"type": ctype}
        for src, dst in fields.items():
            if merged.get(src) is not None:
                cfg[dst] = strip_rtid(merged[src])
                used.add(src)
        used.update(triggers)
        components.append(cfg)
        break

    # A Mint both acts and buffs - Bombard Mint explodes, Arma-mint lobs - so
    # the buff is additive rather than an alternative to its attack.
    if merged.get("Lifespan") is not None and not any(
            c["type"] == "mint_buff" for c in components):
        buff = {"type": "mint_buff", "duration": merged["Lifespan"]}
        if merged.get("DamageMultiplier") is not None:
            buff["damage_multiplier"] = merged["DamageMultiplier"]
        components.append(buff)
        used.update(("Lifespan", "DamageMultiplier"))

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


def majority(built, members, extract):
    """-> the set of values `extract` yields for more than half of `members`."""
    counts = collections.Counter()
    for m in members:
        counts.update(set(extract(built[m])))
    half = len(members) / 2
    return {v for v, c in counts.items() if c > half}


def component_keys(entry):
    """-> each component as a canonical string, so whole components compare."""
    return [json.dumps(c, sort_keys=True) for c in entry.get("components", [])]


def modal_stats(built, members):
    """-> the most common value for each stat, over members that state it."""
    per_key = collections.defaultdict(collections.Counter)
    for m in members:
        for key, value in (built[m].get("stats") or {}).items():
            per_key[key][json.dumps(value, sort_keys=True)] += 1
    out = {}
    for key, counts in per_key.items():
        value, count = counts.most_common(1)[0]
        # A stat only defaults when most of the archetype agrees on it;
        # otherwise every member had better state its own.
        if count > len(members) / 2:
            out[key] = json.loads(value)
    return out


def component_delta(native, default_keys):
    """-> this entry's components as a plain list, or an add/remove delta.

    Stating a type the archetype already has replaces it, so only components
    the archetype does not already carry verbatim need listing. A type the
    archetype has and this entry does not has to be removed by name - a
    bronze statue is a gargantuar that does not smash.
    """
    mine = component_keys(native)
    keep = [json.loads(k) for k in mine if k not in default_keys]
    default_types = {json.loads(k)["type"] for k in default_keys}
    drop = sorted(default_types - {c["type"] for c in native.get("components", [])})
    if not drop:
        return keep
    delta = {}
    if keep:
        delta["add"] = keep
    delta["remove"] = drop
    return delta


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
    # An archetype is the shape its members agree on - tags, stats and whole
    # components. Every world's gargantuar is the same 3600-health smasher
    # that throws an imp at half health, so that belongs in one file and each
    # world's entry says only which imp.
    archetypes = {}
    for sort, members in by_sort.items():
        archetypes[sort] = {
            "tags": majority(built, members, lambda e: e.get("tags", [])),
            "stats": modal_stats(built, members),
            "components": majority(built, members, component_keys),
        }

    arch_dir = os.path.join(out_root, "archetypes")
    out_dir = os.path.join(out_root, "zombies")
    fresh_dir(arch_dir)
    fresh_dir(out_dir)

    for sort, shape in archetypes.items():
        slug = sort.lower()
        out = collections.OrderedDict()
        out["id"] = slug
        out["kind"] = "zombie_archetype"
        out["tags"] = sorted(shape["tags"])
        out["stats"] = shape["stats"]
        out["components"] = [json.loads(k) for k in sorted(shape["components"])]
        open(os.path.join(arch_dir, f"{slug}.json"), "w", encoding="utf-8").write(
            json.dumps(out, ensure_ascii=False, indent=1))

    # split_zombie already resolved every entry in full, so an entry that
    # extends another zombie can be trimmed against that parent's complete
    # shape just as one extending an archetype is trimmed against its
    # defaults. Captured up front because the loop below consumes `tags`.
    full = {n: {"tags": set(e.get("tags", [])),
                "stats": e.get("stats") or {},
                "components": set(component_keys(e))}
            for n, e in built.items()}

    manifest = {}
    before = after = 0
    comps_before = comps_after = 0
    for name, native in built.items():
        sort = native.get("sort") or "Normal"
        mine = set(native.pop("tags", []))
        before += len(mine)
        comps_before += len(native.get("components", []))

        parent = native.pop("extends", None)
        shape = full[parent] if parent in full else archetypes[sort]

        default = set(shape["tags"])
        delta = {}
        added, removed = sorted(mine - default), sorted(default - mine)
        if added:
            delta["add"] = added
        if removed:
            delta["remove"] = removed
        after += len(added) + len(removed)

        native["stats"] = {k: v for k, v in native.get("stats", {}).items()
                           if shape["stats"].get(k) != v}
        native["components"] = component_delta(native, shape["components"])
        for k in ("stats", "components"):
            if not native.get(k):
                native.pop(k, None)
        comps_after += len(native.get("components", []) if
                           isinstance(native.get("components"), list) else
                           native.get("components", {}).get("add", []))

        # Rebuild in a stable, readable key order.
        out = collections.OrderedDict()
        out["id"] = native["id"]
        out["extends"] = parent or sort.lower()
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
    print(f"component entries: {comps_before} -> {comps_after}"
          f"  ({(1-comps_after/comps_before)*100:.0f}% less repetition)")

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
