extends Node
## Loads entity and level definitions, resolves inheritance, and layers mods.
##
## Definitions can be authored as `.tres` resources (typed, inspector-editable)
## or as `.json` (text-friendly, what the PVZGE importer emits). Both are read
## into the same typed EntityDef subclasses, so nothing downstream cares which
## form an entity came from.
##
## Sources and their order come from `Mods`, which lists them base game first
## and highest-priority pack last. A file whose id already exists REPLACES the
## definition from every source below it; a file with a new id ADDS an entity.
##
## Registered as an autoload singleton named `Data`, loaded after `Mods`.

signal loaded

const BASE_DIR := "res://data/native"
const MODS_DIR := "res://mods"
const DEF_EXTENSIONS := [".json", ".tres", ".res"]

var zombies: Dictionary = {}      ## StringName -> ZombieDef
var plants: Dictionary = {}       ## StringName -> PlantDef
var projectiles: Dictionary = {}  ## StringName -> ProjectileDef
var armors: Dictionary = {}       ## StringName -> ArmorDef
var graves: Dictionary = {}       ## StringName -> GraveDef
var objects: Dictionary = {}      ## StringName -> ObjectDef
var archetypes: Dictionary = {}   ## StringName -> Dictionary (raw)
var levels: Dictionary = {}       ## StringName -> Dictionary (raw)
var campaigns: Dictionary = {}    ## StringName -> CampaignDef
var lawns: Dictionary = {}        ## StringName -> Dictionary (raw)

var _mod_order: Array[StringName] = [&"base"]
var _errors: Array[String] = []


func _ready() -> void:
	load_all()


func load_all() -> void:
	for pool in [zombies, plants, projectiles, armors, graves, objects,
			archetypes, levels, campaigns, lawns]:
		pool.clear()
	_errors.clear()
	_mod_order = [&"base"]

	for source in _sources():
		var mod_id := StringName(source["id"])
		if mod_id != &"base":
			_mod_order.append(mod_id)
		_load_source(String(source["root"]), mod_id)

	_resolve_all()
	if not _errors.is_empty():
		push_warning("DataRegistry: %d problem(s) during load" % _errors.size())
		for e in _errors:
			push_warning("  " + e)
	loaded.emit()


## Content roots in application order. Falls back to the base directory alone
## if the mod loader is unavailable, so the game still runs.
func _sources() -> Array[Dictionary]:
	var mods := get_node_or_null(^"/root/Mods")
	if mods != null and mods.has_method("data_sources"):
		return mods.data_sources()
	return [{"id": &"base", "root": BASE_DIR}]


func _load_source(root: String, mod: StringName) -> void:
	_load_dir(root.path_join("archetypes"), archetypes, mod)
	_load_dir(root.path_join("zombies"), zombies, mod)
	_load_dir(root.path_join("plants"), plants, mod)
	_load_dir(root.path_join("projectiles"), projectiles, mod)
	_load_dir(root.path_join("armors"), armors, mod)
	_load_dir(root.path_join("graves"), graves, mod)
	_load_dir(root.path_join("objects"), objects, mod)
	_load_dir(root.path_join("levels"), levels, mod)
	_load_dir(root.path_join("lawns"), lawns, mod)
	_load_campaigns(root.path_join("campaigns"), mod)


## Reads every definition file in `dir` into `target`, keyed by id. JSON is
## kept as a Dictionary for the resolve pass; `.tres` is loaded straight into
## its EntityDef and resolved the same way.
func _load_dir(dir_path: String, target: Dictionary, mod: StringName) -> void:
	var dir := DirAccess.open(dir_path)
	if dir == null:
		return
	dir.list_dir_begin()
	var fname := dir.get_next()
	while fname != "":
		if not dir.current_is_dir():
			var path := dir_path.path_join(fname)
			if fname.ends_with(".json"):
				var parsed = _read_json(path)
				if parsed is Dictionary:
					parsed["__mod"] = mod
					parsed["__path"] = path
					target[StringName(parsed.get("id", fname.get_basename()))] = parsed
				else:
					_errors.append("%s: not a JSON object" % path)
			elif fname.ends_with(".tres") or fname.ends_with(".res"):
				var res = load(path)
				if res is EntityDef:
					var def: EntityDef = res
					def.source_mod = mod
					def.source_path = path
					if def.id == &"":
						def.id = StringName(fname.get_basename())
					target[def.id] = def
				else:
					_errors.append("%s: not an EntityDef resource" % path)
		fname = dir.get_next()
	dir.list_dir_end()


## Campaigns are their own kind: not entities, so they skip the inheritance
## pass, but still typed rather than raw dictionaries.
func _load_campaigns(dir_path: String, mod: StringName) -> void:
	var dir := DirAccess.open(dir_path)
	if dir == null:
		return
	dir.list_dir_begin()
	var fname := dir.get_next()
	while fname != "":
		if not dir.current_is_dir():
			var path := dir_path.path_join(fname)
			var campaign: CampaignDef = null
			if fname.ends_with(".json"):
				var parsed = _read_json(path)
				if parsed is Dictionary:
					campaign = CampaignDef.from_dict(parsed)
					if campaign.id == &"":
						campaign.id = StringName(fname.get_basename())
				else:
					_errors.append("%s: not a JSON object" % path)
			elif fname.ends_with(".tres") or fname.ends_with(".res"):
				var res = load(path)
				if res is CampaignDef:
					campaign = res
				else:
					_errors.append("%s: not a CampaignDef resource" % path)
			if campaign != null:
				campaign.source_mod = mod
				campaign.source_path = path
				campaigns[campaign.id] = campaign
		fname = dir.get_next()
	dir.list_dir_end()


func _read_json(path: String) -> Variant:
	var f := FileAccess.open(path, FileAccess.READ)
	if f == null:
		_errors.append("%s: cannot open" % path)
		return null
	var text := f.get_as_text()
	f.close()
	var result = JSON.parse_string(text)
	if result == null:
		_errors.append("%s: invalid JSON" % path)
	return result


func _resolve_all() -> void:
	for pair in [[zombies, &"zombie"], [plants, &"plant"],
			[projectiles, &"projectile"], [armors, &"armor"],
			[graves, &"grave"], [objects, &"object"]]:
		var pool: Dictionary = pair[0]
		var kind: StringName = pair[1]
		var raw := pool.duplicate()
		pool.clear()
		for id in raw:
			pool[id] = _resolve(id, raw[id], raw, kind, [])


func _new_def(kind: StringName) -> EntityDef:
	match kind:
		&"zombie": return ZombieDef.new()
		&"plant": return PlantDef.new()
		&"projectile": return ProjectileDef.new()
		&"armor": return ArmorDef.new()
		&"grave": return GraveDef.new()
		&"object": return ObjectDef.new()
	return EntityDef.new()


## Flattens one entity: walks its `extends` chain, applies tag deltas, and
## merges stats and components from parent to child.
func _resolve(id: StringName, raw: Variant, pool: Dictionary,
		kind: StringName, seen: Array) -> EntityDef:
	# A .tres already is a definition; only its inheritance needs applying.
	var source: Dictionary = raw if raw is Dictionary else {}
	var def: EntityDef = _new_def(kind)
	def.id = id
	def.kind = kind

	if raw is EntityDef:
		def = raw
		def.kind = kind
		source = {"extends": raw.extends_id}
	else:
		def.source_path = source.get("__path", "")
		def.source_mod = source.get("__mod", &"base")

	if seen.has(id):
		_errors.append("%s: circular extends chain %s" % [id, str(seen)])
		return def
	seen = seen + [id]

	# Start from the parent, which may be another entity or an archetype.
	var parent_id := StringName(source.get("extends", &""))
	def.extends_id = parent_id
	var authored := raw is EntityDef
	if parent_id != &"":
		if pool.has(parent_id) and parent_id != id:
			var parent := _resolve(parent_id, pool[parent_id], pool, kind, seen)
			# An authored .tres is already complete, so the parent may only
			# fill gaps; a data-built definition is layered parent-first.
			if authored:
				def.merge_under(parent)
			else:
				def.inherit_from(parent)
		elif archetypes.has(parent_id):
			var arch_tags: Array = archetypes[parent_id].get("tags", [])
			if authored:
				for t in arch_tags:
					def.add_tag(StringName(t))
			else:
				def.set_tags(arch_tags)
		else:
			_errors.append("%s: unknown extends target '%s'" % [id, parent_id])

	if authored:
		return def

	def.apply_stats(source.get("stats", {}))

	# Tags are either a plain list (replace) or an add/remove delta.
	var tag_field = source.get("tags")
	if tag_field is Array:
		def.set_tags(tag_field)
	elif tag_field is Dictionary:
		for t in (tag_field.get("remove", []) as Array):
			def.remove_tag(StringName(t))
		for t in (tag_field.get("add", []) as Array):
			def.add_tag(StringName(t))

	for c in (source.get("components", []) as Array):
		if c is Dictionary:
			def.put_component(ComponentSpec.from_dict(c))

	# Family and sort are classification, not stats, so they are set directly.
	if source.has("family"):
		var family := StringName(str(source["family"]))
		if def is PlantDef:
			def.family = family
		def.add_tag(StringName("family:" + str(family).to_lower()))
	if source.has("sort") and def is ZombieDef:
		def.sort = StringName(str(source["sort"]))
	if source.has("category") and def is ObjectDef:
		def.category = ObjectDef.category_from_string(str(source["category"]))

	def.extra = source.get("extra", {})
	return def


# --- lookups -------------------------------------------------------------

func zombie(id: StringName) -> ZombieDef:
	return zombies.get(id)


func plant(id: StringName) -> PlantDef:
	return plants.get(id)


func projectile(id: StringName) -> ProjectileDef:
	return projectiles.get(id)


func armor(id: StringName) -> ArmorDef:
	return armors.get(id)


func grave(id: StringName) -> GraveDef:
	return graves.get(id)


## Named `board_object` because `object` is not usable as an identifier.
func board_object(id: StringName) -> ObjectDef:
	return objects.get(id)


func level(id: StringName) -> Dictionary:
	return levels.get(id, {})


## A stage's lawn settings: music track, mower, zombie roster.
func lawn(id: StringName) -> Dictionary:
	return lawns.get(id, {})


func campaign(id: StringName) -> CampaignDef:
	return campaigns.get(id)


## The campaign a level belongs to, or null if it is standalone.
func campaign_for_level(level_id: StringName) -> CampaignDef:
	for cid in campaigns:
		var c: CampaignDef = campaigns[cid]
		if c.index_of(level_id) >= 0:
			return c
	return null


## Damage for a projectile id, falling back to a sane default when a mod
## references a projectile that does not exist.
func projectile_damage(id: StringName, fallback: float = 20.0) -> float:
	var def: ProjectileDef = projectiles.get(id)
	return def.damage if def else fallback


## Every entity of `kind` carrying all of `required` and none of `excluded`.
func query(kind: StringName, required: Array, excluded: Array = []) -> Array[EntityDef]:
	var pool: Dictionary = zombies
	match kind:
		&"plant": pool = plants
		&"projectile": pool = projectiles
		&"armor": pool = armors
		&"grave": pool = graves
		&"object": pool = objects
	var out: Array[EntityDef] = []
	for id in pool:
		var def: EntityDef = pool[id]
		if def.matches(required, excluded):
			out.append(def)
	return out


func errors() -> Array[String]:
	return _errors


func mod_order() -> Array[StringName]:
	return _mod_order


func summary() -> String:
	return ("zombies=%d plants=%d projectiles=%d armors=%d graves=%d objects=%d "
			+ "archetypes=%d levels=%d campaigns=%d mods=%s errors=%d") % [
		zombies.size(), plants.size(), projectiles.size(), armors.size(),
		graves.size(), objects.size(), archetypes.size(), levels.size(),
		campaigns.size(), str(_mod_order), _errors.size()]
