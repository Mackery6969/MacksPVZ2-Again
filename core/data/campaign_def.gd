class_name CampaignDef
extends Resource
## An ordered run of levels, and the thread that ties one level to the next.
##
## Kept as data rather than hardcoded so a pack can add its own campaign, or
## insert levels into an existing one, without touching game code.

@export var id: StringName = &""
@export var display_name: String = ""
## Level ids, played in this order.
@export var levels: Array[StringName] = []
## Shown when the last level is cleared.
@export var completion_message: String = "Campaign complete!"

var source_mod: StringName = &"base"
var source_path: String = ""


static func from_dict(d: Dictionary) -> CampaignDef:
	var c := CampaignDef.new()
	c.id = StringName(d.get("id", &""))
	c.display_name = String(d.get("name", d.get("id", "")))
	c.completion_message = String(d.get("completion_message", c.completion_message))
	for level_id in (d.get("levels", []) as Array):
		c.levels.append(StringName(level_id))
	return c


func first_level() -> StringName:
	return levels[0] if not levels.is_empty() else &""


func index_of(level_id: StringName) -> int:
	return levels.find(level_id)


## The level after `level_id`, or &"" when that was the last one.
func next_after(level_id: StringName) -> StringName:
	var i := index_of(level_id)
	if i < 0 or i + 1 >= levels.size():
		return &""
	return levels[i + 1]


func is_last(level_id: StringName) -> bool:
	return index_of(level_id) == levels.size() - 1
