#!/usr/bin/env python3
"""Pull a named prefab's art out of the PVZGE build: skeleton, atlas and PNG.

`res.config.json` names 2868 assets - `plants/SunflowerPLANT`,
`zombies/BasicZOMBIE`, `armors/BasicConeARMOR` - which is the only place in
the build where anything has a readable name. Everything else is addressed by
a compressed UUID, so this starts from a name and follows the graph.

Three things have to be resolved, and none of them sits where you would hope:

1. An asset is either a standalone `import/xx/<uuid>.json` or a member of a
   pack, positionally aligned with the pack's instance array.
2. The DragonBones skeleton and atlas are not files. They are the serialized
   asset's own JSON held as an escaped STRING inside the envelope, so they are
   found by parsing strings rather than by reading a path. This is why the
   assets are identified by content: a string that parses and has "armature"
   is a skeleton, one with "SubTexture" is an atlas.
3. The atlas PNG is whichever dependency UUID exists as a file under
   `native/`. The atlas JSON names it (`PlantAnimate_tex.png`) but that name
   appears nowhere on disk.

    python3 tools/extract_prefabs.py <import dir> <res.config.json> <out dir> \\
        [--native <dir>] [pattern ...]

A pattern is matched against the asset path, case-insensitively, as a
substring: `plants/Sunflower` takes both the PLANT and the DIS prefab. With no
pattern nothing is written and the matching names are listed instead.
"""
import io, json, os, re, subprocess, sys, tarfile

IMAGE = "gaozih/pvzge:latest"
NATIVE_IN_IMAGE = "/usr/share/nginx/html/assets/resources/native"
PNG_MAGIC = b"\x89PNG\r\n\x1a\n"

B64 = "ABCDEFGHIJKLMNOPQRSTUVWXYZabcdefghijklmnopqrstuvwxyz0123456789+/"
VALUES = {c: i for i, c in enumerate(B64)}
HEX = "0123456789abcdef"


def decode_uuid(short):
    """Cocos ships UUIDs base64-compressed to 22 chars; expand to the real 36."""
    base = short.split("@")[0]
    if len(base) != 22:
        return base
    out = [base[0], base[1]]
    for i in range(2, 22, 2):
        lhs, rhs = VALUES[base[i]], VALUES[base[i + 1]]
        out += [HEX[lhs >> 2], HEX[((lhs & 3) << 2) | (rhs >> 4)], HEX[rhs & 0xF]]
    h = "".join(out)
    return f"{h[:8]}-{h[8:12]}-{h[12:16]}-{h[16:20]}-{h[20:32]}"


def safe_name(value, fallback):
    """One path component, so an asset's own name cannot escape the out dir."""
    name = os.path.basename(str(value).replace("\\", "/"))
    name = re.sub(r"[^A-Za-z0-9._-]", "_", name)
    return name if name not in ("", ".", "..") else fallback


class Build:
    """The asset graph: name -> index -> container -> payload."""

    def __init__(self, import_dir, config_path):
        cfg = json.load(open(config_path, encoding="utf-8"))
        self.import_dir = import_dir
        self.uuids = [decode_uuid(u) for u in cfg["uuids"]]
        # A Texture2D is a sub-asset of an ImageAsset, which Cocos marks with
        # an "@" suffix on the reference. That makes it a useful tie-breaker
        # when several images happen to share the atlas's dimensions.
        self.subasset = {i for i, u in enumerate(cfg["uuids"]) if "@" in u}
        self.paths = {int(k): v for k, v in cfg["paths"].items()}
        self.types = cfg.get("types", [])
        self.by_name = {v[0]: i for i, v in self.paths.items()}
        self.by_uuid = {u: i for i, u in enumerate(self.uuids)}
        # An asset in a pack is found by its position in the member list.
        self.in_pack = {}
        for pack, members in cfg.get("packs", {}).items():
            for position, member in enumerate(members):
                self.in_pack.setdefault(member, (pack, position))
        self._cache = {}
        self._packs = cfg.get("packs", {})

    def type_of(self, index):
        row = self.paths.get(index)
        if row and len(row) > 1 and isinstance(row[1], int) and row[1] < len(self.types):
            return self.types[row[1]]
        return None

    def container(self, index):
        """-> the parsed envelope holding this asset, or None."""
        if index in self._cache:
            return self._cache[index]
        uuid = self.uuids[index] if index < len(self.uuids) else None
        candidates = []
        if index in self.in_pack:
            pack = self.in_pack[index][0]
            candidates.append(os.path.join(self.import_dir, pack[:2], pack + ".json"))
        if uuid:
            candidates.append(os.path.join(self.import_dir, uuid[:2], uuid + ".json"))
        data = None
        for path in candidates:
            if not os.path.exists(path):
                continue
            try:
                data = json.load(open(path, encoding="utf-8"))
                break
            except (json.JSONDecodeError, UnicodeDecodeError):
                continue
        self._cache[index] = data
        return data

    def instance(self, index):
        """-> just this asset's own slice of its container.

        A pack holds several assets in one file, so searching the whole
        container finds a neighbour's payload - which is how Potato Mine came
        out as Crazy Dave and the basic zombie as a gargantuar. The member
        list is positionally aligned with the instance array, so the asset's
        own entry can be picked out exactly.
        """
        data = self.container(index)
        if not isinstance(data, list):
            return None
        if index in self.in_pack:
            pack, position = self.in_pack[index]
            members = self._packs.get(pack, [])
            if (len(data) > 5 and isinstance(data[5], list)
                    and len(data[5]) == len(members) and position < len(data[5])):
                return data[5][position]
        return data


    def deps(self, index):
        """-> asset indices this asset's container depends on."""
        data = self.container(index)
        if not (isinstance(data, list) and len(data) > 1 and isinstance(data[1], list)):
            return []
        out = []
        for short in data[1]:
            if not isinstance(short, str):
                continue
            hit = self.by_uuid.get(decode_uuid(short))
            if hit is not None:
                out.append(hit)
        return out


def embedded(node, marker, depth=0):
    """-> every JSON object reachable from `node` that has `marker` as a key.

    Walks strings as well as structure, because that is where Cocos keeps the
    DragonBones payloads.
    """
    found = []
    if depth > 12:
        return found
    if isinstance(node, dict):
        if marker in node:
            found.append(node)
        for value in node.values():
            found += embedded(value, marker, depth + 1)
    elif isinstance(node, list):
        for value in node:
            found += embedded(value, marker, depth + 1)
    elif isinstance(node, str) and len(node) > 32 and ('"%s"' % marker) in node:
        try:
            found += embedded(json.loads(node), marker, depth + 1)
        except json.JSONDecodeError:
            pass
    return found


def find_payloads(build, index, marker, prefer=None):
    """Looks for `marker` here, then outwards through the dependency graph.

    Breadth-first on purpose. Depth-first dives through the first dependency
    and comes back with whatever skeleton it met on the way down - which is
    how the basic zombie came out as a gargantuar, three hops away, while its
    real skeleton sat in the second dependency.

    `prefer` is the set of names the asset itself mentions. When several
    skeletons are in reach, the one holding an armature the prefab actually
    names wins.

    Returns the payloads AND the asset that held them, because the atlas's own
    container is the only place its texture UUID can be read unambiguously.
    """
    seen, frontier = {index}, [index]
    fallback = ([], None)
    while frontier:
        nxt = []
        for i in frontier:
            hits = embedded(build.instance(i), marker)
            if hits:
                if prefer is None:
                    return hits, i
                names = {a.get("name") for h in hits
                         for a in h.get("armature", []) if isinstance(a, dict)}
                if names & prefer:
                    return hits, i
                if fallback[1] is None:
                    fallback = (hits, i)
            for dep in build.deps(i):
                if dep not in seen:
                    seen.add(dep)
                    nxt.append(dep)
        frontier = nxt
    return fallback


def mentioned(node, out=None, depth=0):
    """-> short strings the asset itself carries, which include the armature
    name an ArmatureDisplay was configured with."""
    out = out if out is not None else set()
    if depth > 12:
        return out
    if isinstance(node, dict):
        for v in node.values():
            mentioned(v, out, depth + 1)
    elif isinstance(node, list):
        for v in node:
            mentioned(v, out, depth + 1)
    elif isinstance(node, str) and 1 < len(node) < 40:
        out.add(node)
    return out


def region_coverage(png_bytes, atlas):
    """-> the share of the atlas's regions that hold visible pixels.

    Dimensions alone can leave several images matching one atlas. This is the
    check that actually decides: the right image has artwork where the atlas
    says artwork is, and a wrong one of the same size has empty rectangles.
    Returns -1.0 when the image cannot be read, so it loses rather than wins.
    """
    try:
        from PIL import Image
    except ImportError:
        return 0.0
    try:
        img = Image.open(io.BytesIO(png_bytes)).convert("RGBA")
    except Exception:
        return -1.0
    regions = [r for r in atlas.get("SubTexture", []) if isinstance(r, dict)]
    if not regions:
        return 0.0
    alpha = img.getchannel("A")
    filled = 0
    for r in regions:
        box = (int(r.get("x", 0)), int(r.get("y", 0)),
               int(r.get("x", 0)) + int(r.get("width", 0)),
               int(r.get("y", 0)) + int(r.get("height", 0)))
        if box[2] <= box[0] or box[3] <= box[1]:
            continue
        if max(alpha.crop(box).getextrema()) > 8:
            filled += 1
    return filled / float(len(regions))


def png_sizes(native_dir, listing):
    """-> {uuid: (width, height)} from each PNG's IHDR.

    The atlas JSON states its own width and height, and a pack's dependency
    list is shared by every asset in it, so dimensions are what actually
    pairs an atlas to its image. It is also self-checking: a mismatch means
    the pairing is wrong rather than quietly producing scrambled art.
    """
    pngs = sorted(r for r in listing if r.endswith(".png"))
    heads = {}
    if native_dir:
        for rel in pngs:
            with open(os.path.join(native_dir, rel), "rb") as fh:
                heads[rel] = fh.read(26)
    else:
        # 26 bytes each for 600-odd files: one container, one small read.
        blob = subprocess.run(
            ["docker", "run", "--rm", "-i", IMAGE, "sh", "-c",
             "cd %s && while read f; do printf '@@%%s\\n' \"$f\"; "
             "head -c 26 \"$f\" | od -An -v -tx1 | tr -d ' \\n'; echo; done"
             % NATIVE_IN_IMAGE],
            input="\n".join(pngs), capture_output=True, text=True).stdout
        current = None
        for line in blob.splitlines():
            if line.startswith("@@"):
                current = line[2:]
            elif current:
                try:
                    heads[current] = bytes.fromhex(line)
                except ValueError:
                    pass
                current = None
    out = {}
    for rel, head in heads.items():
        if len(head) < 24 or head[:8] != PNG_MAGIC:
            continue
        width = int.from_bytes(head[16:20], "big")
        height = int.from_bytes(head[20:24], "big")
        out[os.path.basename(rel)[:-4]] = (width, height)
    return out


def native_listing(native_dir):
    """-> the set of media paths the build actually has, as `xx/<uuid>.png`."""
    if native_dir:
        out = set()
        for sub in os.listdir(native_dir):
            d = os.path.join(native_dir, sub)
            if os.path.isdir(d):
                out |= {"%s/%s" % (sub, f) for f in os.listdir(d)}
        return out
    listed = subprocess.run(
        ["docker", "run", "--rm", IMAGE, "sh", "-c",
         "cd %s && find . -type f | sed 's|^\\./||'" % NATIVE_IN_IMAGE],
        capture_output=True, text=True).stdout
    return set(listed.split())


def fetch_native(uuids, out_dir, native_dir, listing):
    """Copies each uuid's image out of the build. -> {uuid: filename}.

    One container for the whole set. A `docker run` per file turns a
    fifteen-second job into a ten-minute one, and passing the file list as
    arguments overruns argv, so the list goes in on stdin.
    """
    wanted = {}
    for uuid in uuids:
        for ext in (".png", ".jpg", ".webp"):
            rel = "%s/%s%s" % (uuid[:2], uuid, ext)
            if rel in listing:
                wanted[rel] = uuid + ext
                break
    if not wanted:
        return {}

    written = {}
    if native_dir:
        for rel, name in wanted.items():
            payload = open(os.path.join(native_dir, rel), "rb").read()
            if payload[:8] == PNG_MAGIC:
                open(os.path.join(out_dir, name), "wb").write(payload)
                written[os.path.splitext(name)[0]] = name
        return written

    blob = subprocess.run(
        ["docker", "run", "--rm", "-i", IMAGE, "sh", "-c",
         "cd %s && tar -cf - -T -" % NATIVE_IN_IMAGE],
        input="\n".join(wanted).encode(), capture_output=True).stdout
    with tarfile.open(fileobj=io.BytesIO(blob), mode="r:") as tf:
        for member in tf.getmembers():
            handle = tf.extractfile(member)
            if handle is None:
                continue
            payload = handle.read()
            # A PNG is the only thing expected; anything else means the uuid
            # pointed at a different kind of media.
            if payload[:8] != PNG_MAGIC:
                continue
            name = os.path.basename(member.name)
            open(os.path.join(out_dir, name), "wb").write(payload)
            written[os.path.splitext(name)[0]] = name
    return written


def main():
    if len(sys.argv) < 4:
        print(__doc__)
        return 2
    import_dir, config_path, out_root = sys.argv[1:4]
    native_dir = None
    if "--native" in sys.argv:
        native_dir = sys.argv[sys.argv.index("--native") + 1]
    patterns = [a for a in sys.argv[4:]
                if not a.startswith("--") and a != native_dir]

    build = Build(import_dir, config_path)
    if not patterns:
        print("%d named assets. Pass a pattern; these are the prefabs:"
              % len(build.by_name))
        for name in sorted(build.by_name):
            if build.type_of(build.by_name[name]) == "cc.Prefab":
                print("   %s" % name)
        return 0

    targets = sorted(
        (name, index) for name, index in build.by_name.items()
        if any(p.lower() in name.lower() for p in patterns))
    if not targets:
        print("nothing matched %s" % patterns)
        return 1

    os.makedirs(out_root, exist_ok=True)
    index_out = {}
    textures_needed = {}
    atlas_of = {}
    for name, idx in targets:
        slug = safe_name(name.replace("/", "_"), "asset_%d" % idx)
        dest = os.path.join(out_root, slug)
        entry = {"path": name, "uuid": build.uuids[idx],
                 "type": build.type_of(idx)}

        names = mentioned(build.instance(idx))
        skeletons, _ = find_payloads(build, idx, "armature", prefer=names)
        atlases, atlas_owner = find_payloads(build, idx, "SubTexture")
        if not skeletons and not atlases:
            entry["note"] = "no DragonBones payload reachable"
            index_out[slug] = entry
            continue
        os.makedirs(dest, exist_ok=True)
        if skeletons:
            ske = skeletons[0]
            json.dump(ske, open(os.path.join(dest, "skeleton.json"), "w",
                                encoding="utf-8"),
                      ensure_ascii=False, separators=(",", ":"))
            entry["skeleton"] = ske.get("name")
            entry["frame_rate"] = ske.get("frameRate")
            armatures = [a for a in ske.get("armature", []) if isinstance(a, dict)]
            # Which armature this prefab actually displays. A dozen zombies
            # share one ZombieAnimate skeleton, so the file alone does not say.
            used = [a.get("name") for a in armatures if a.get("name") in names]
            entry["armature"] = used[0] if used else (
                armatures[0].get("name") if armatures else None)
            entry["armatures"] = [
                {"name": a.get("name"),
                 "bones": len(a.get("bone", [])),
                 "slots": len(a.get("slot", [])),
                 "animations": [an.get("name") for an in a.get("animation", [])]}
                for a in armatures]
        if atlases:
            atlas = atlases[0]
            json.dump(atlas, open(os.path.join(dest, "atlas.json"), "w",
                                  encoding="utf-8"),
                      ensure_ascii=False, separators=(",", ":"))
            atlas_of[slug] = atlas
            entry["atlas"] = {"name": atlas.get("name"),
                              "image": atlas.get("imagePath"),
                              "size": [atlas.get("width"), atlas.get("height")],
                              "regions": len(atlas.get("SubTexture", []))}
            entry["atlas_candidates"] = [
                build.uuids[d] for d in build.deps(atlas_owner)]
            entry["atlas_subassets"] = [
                build.uuids[d] for d in build.deps(atlas_owner)
                if d in build.subasset]
        index_out[slug] = entry

    media_dir = os.path.join(out_root, "_textures")
    os.makedirs(media_dir, exist_ok=True)
    listing = native_listing(native_dir)
    sizes = png_sizes(native_dir, listing)

    unpaired = []
    for slug, entry in index_out.items():
        want = tuple(entry.get("atlas", {}).get("size") or ())
        subassets = set(entry.pop("atlas_subassets", []))
        hits = [u for u in entry.pop("atlas_candidates", [])
                if sizes.get(u) == want]
        if len(hits) > 1 and len(set(hits) & subassets) == 1:
            hits = sorted(set(hits) & subassets)
        if len(hits) > 1:
            # Still several images of the atlas's exact size, so ask the
            # images themselves which one has art where the atlas says.
            scored = []
            for uuid in hits:
                blob = fetch_native([uuid], media_dir, native_dir, listing)
                name = blob.get(uuid)
                if name is None:
                    continue
                path = os.path.join(media_dir, name)
                score = region_coverage(open(path, "rb").read(), atlas_of[slug])
                scored.append((score, uuid))
                os.remove(path)
            scored.sort(reverse=True)
            if scored:
                entry["region_coverage"] = round(scored[0][0], 3)
                hits = [scored[0][1]]
                if len(scored) > 1 and scored[1][0] >= scored[0][0]:
                    entry["texture_ambiguous"] = [u for _, u in scored]
        if len(hits) == 1:
            textures_needed.setdefault(hits[0], []).append(slug)
        elif want:
            unpaired.append(slug)

    written = fetch_native(list(textures_needed), media_dir, native_dir, listing)
    for uuid, filename in written.items():
        for slug in textures_needed[uuid]:
            index_out[slug].setdefault("textures", []).append(filename)

    # Merged rather than replaced, so extracting a few more prefabs - or the
    # rigs from extract_rigs.py - keeps whatever was extracted before.
    index_path = os.path.join(out_root, "_index.json")
    merged = {}
    if os.path.exists(index_path):
        merged = json.load(open(index_path, encoding="utf-8"))
    merged.update(index_out)
    json.dump(merged, open(index_path, "w", encoding="utf-8"), indent=1,
              ensure_ascii=False)
    done = sum(1 for v in index_out.values() if "skeleton" in v)
    print("matched %d assets, %d with a skeleton, %d textures -> %s"
          % (len(index_out), done, len(written), out_root))
    for slug, v in sorted(index_out.items()):
        if "note" in v:
            print("   !! %-34s %s" % (slug, v["note"]))
        if "texture_ambiguous" in v:
            print("   ?? %-34s %d images match the atlas size"
                  % (slug, len(v["texture_ambiguous"])))
    for slug in unpaired:
        print("   !! %-34s no image matches the atlas size %s"
              % (slug, index_out[slug].get("atlas", {}).get("size")))
    return 0


if __name__ == "__main__":
    sys.exit(main())
