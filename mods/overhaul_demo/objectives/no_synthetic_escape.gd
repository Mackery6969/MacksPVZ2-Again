extends Objective
## A new win/lose rule: no synthetic zombie may reach the house.
##
## Shows that an overhaul can add goals the base game has no concept of - this
## one keys off a tag the pack itself invented, so nothing in core knows about
## "synthetic" and nothing had to.
##
## Config: tag - the tag that must not get through (default "synthetic").

var tag: StringName = &"synthetic"

var _escaped: int = 0


func setup() -> void:
	tag = StringName(cfg(&"tag", &"synthetic"))


func on_zombie_reached_house(zombie: Node) -> void:
	if zombie.has_tag(tag):
		_escaped += 1
		notify_progress()
		fail()


func is_met() -> bool:
	return _escaped == 0


func describe() -> String:
	return "No %s through: %s" % [tag, "broken" if _escaped else "holding"]
