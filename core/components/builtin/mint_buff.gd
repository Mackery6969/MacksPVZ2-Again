extends EntityComponent
## A Mint: boosts every plant of its own family for a while, then is spent.
##
## The mint's `Family` is its target - ailmint is Poison and boosts poison
## plants, armamint is Lobber and boosts lobbers. The per-plant numbers come
## from each plant's own `mint_boost` block, so the mint does not need to know
## anything about the plants it helps.
##
## Config: duration, damage_multiplier, lifespan.

var duration: float = 20.0

var _applied: bool = false
var _life_left: float = 0.0


func setup() -> void:
	duration = float(cfg(&"duration", cfg(&"lifespan", 20.0)))
	_life_left = duration


func _process(delta: float) -> void:
	if host.is_dead:
		return

	if not _applied:
		_applied = true
		_boost()
		Audio.play(&"plant.food", host.position)

	# A mint lives out its span - several of them also attack while it runs -
	# and only then is spent.
	_life_left -= delta
	if _life_left <= 0.0:
		host.die()


## -> how many plants were boosted.
func _boost() -> int:
	var family := _target_family()
	if family == &"":
		return 0
	var extra := float(cfg(&"damage_multiplier", 1.0))
	var count := 0
	for row in host.board.rows:
		for col in host.board.cols:
			var plant = host.board.plant_at(row, col)
			if plant == null or plant == host or not plant.has_tag(family):
				continue
			var boost: Dictionary = plant.def.extra.get("mint_boost", {})
			if boost.is_empty() and plant.def != null:
				boost = plant.def.extra.get("MintBoostedProps", {})
			var rate := float(boost.get("speed", boost.get("SpeedMult", 2.0)))
			var resist := float(boost.get("resistance", boost.get("ResistanceMult", 1.0)))
			plant.apply_buff(rate * maxf(extra, 1.0), resist, duration)
			count += 1
	return count


## The family tag this mint targets, taken from its own family.
func _target_family() -> StringName:
	for tag in host.def.tag_list():
		if String(tag).begins_with("family:"):
			return tag
	return &""
