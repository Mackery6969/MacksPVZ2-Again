class_name SeedPacketView
extends Button
## One seed packet, drawn the way PVZGE draws it: the world's packet backing,
## the plant's portrait, the price, the recharge shade and the selection rim.
##
## PVZGE builds a packet out of nested rigs (`SeedPacker`'s Card holds a
## background rig, a plant rig with one display per plant, a cooldown rig and
## so on), each switched by a zero-length animation. The pictures are all one
## atlas, so this draws them straight from it at the places the rigs put them,
## which keeps a packet a single control rather than eight armatures.
##
## Without the art it is an ordinary button with the plant's name and cost.

const PACKET := Vector2(239, 151)

## The bundle and the backing, from the `hud:seed_packet` mapping.
var bundle: StringName = &"rigs_SeedPacker_Card"
var background: StringName = &"bk_modernday"

var kind: StringName = &"plant"
var id: StringName = &""
var cost: int = 0
var hotkey: String = ""
## 0 just planted, 1 ready.
var recharged: float = 1.0
var affordable: bool = true
var chosen: bool = false
## Recharged and paid for. An unusable packet still takes clicks, so that
## main can refuse it with PVZGE's sound and sun warning.
var usable: bool = true

var _source: ArmatureSet = null
var _portrait: AtlasTexture = null
var _portrait_at := Vector2.ZERO
var _hover: bool = false


func setup(packet_kind: StringName, packet_id: StringName, price: int, key: String) -> void:
	kind = packet_kind
	id = packet_id
	cost = price
	hotkey = key
	focus_mode = Control.FOCUS_NONE
	var entry := Art.mapping(&"hud", &"seed_packet")
	bundle = StringName(entry.get("bundle", bundle))
	background = StringName(entry.get("background", background))
	_source = Art.set_for(bundle)
	_find_portrait(entry.get("portraits", {}))
	if has_art():
		text = ""
		flat = true
	else:
		text = "%s%s\n%d" % [key, String(id).capitalize(), cost]
	mouse_entered.connect(func(): _hover = true; queue_redraw())
	mouse_exited.connect(func(): _hover = false; queue_redraw())
	queue_redraw()


func has_art() -> bool:
	return _source != null and _portrait != null


## Brings the packet up to date. Called whenever sun, recharge or the
## selection change.
func show_state(fraction: float, can_afford: bool, is_chosen: bool) -> void:
	recharged = clampf(fraction, 0.0, 1.0)
	affordable = can_afford
	chosen = is_chosen
	usable = recharged >= 1.0 and affordable
	if not has_art():
		# The plain button's old look: darker the more recharge is left.
		if chosen:
			modulate = Color(0.7, 1.0, 0.7)
		elif recharged < 1.0:
			modulate = Color.WHITE.darkened(0.55 * (1.0 - recharged))
		elif not affordable:
			modulate = Color(0.75, 0.75, 0.75)
		else:
			modulate = Color.WHITE
	queue_redraw()


## The portrait is one display among 258 on the `plants` rig's body slot;
## its own transform says where it sits on the packet.
func _find_portrait(overrides: Dictionary) -> void:
	if _source == null:
		return
	var wanted: Array[String] = []
	if overrides.has(String(id)):
		wanted.append(String(overrides[String(id)]))
	wanted.append(String(id))
	wanted.append(String(id).replace("_", ""))
	var displays := {}
	for skin in (_source.armature(&"plants").get("skin", []) as Array):
		for slot in (skin.get("slot", []) as Array):
			if slot.get("name", "") != "plant_body":
				continue
			for d in (slot.get("display", []) as Array):
				displays[String(d.get("name", ""))] = d
	for name in wanted:
		var region := _source.region(StringName(name))
		if region == null:
			continue
		_portrait = region
		var xf: Dictionary = (displays.get(name, {}) as Dictionary).get("transform", {})
		_portrait_at = Vector2(float(xf.get("x", 0.0)), float(xf.get("y", 0.0))) \
				+ _source.region_offset(StringName(name))
		return


func _draw() -> void:
	if not has_art():
		return
	var k := minf(size.x / PACKET.x, size.y / PACKET.y)
	var centre := size * 0.5
	var dim := Color.WHITE if affordable else Color(0.55, 0.55, 0.55)

	_blit(background, Vector2(-0.16, -0.16), k, centre, dim)
	_blit_texture(_portrait, _portrait_at, k, centre, dim)
	_blit(&"bk_top", Vector2(-2.25, 7.1), k, centre, dim)
	_blit(&"bk_price_tab", Vector2(61.43, 25.05), k, centre, dim)

	# Recharge: PVZGE pulls a translucent shade up off the packet. Drawn as
	# the share still to go, from the top.
	if recharged < 1.0:
		var shade := Rect2(Vector2.ZERO, Vector2(size.x, size.y * (1.0 - recharged)))
		draw_rect(shade, Color(0, 0, 0, 0.45), true)

	var font := get_theme_default_font()
	var price := str(cost)
	var fs := maxi(10, int(34.0 * k))
	var tab := centre + Vector2(61.43, 25.05) * k
	var w := font.get_string_size(price, HORIZONTAL_ALIGNMENT_CENTER, -1, fs).x
	draw_string_outline(font, tab + Vector2(-w * 0.5, fs * 0.35), price,
			HORIZONTAL_ALIGNMENT_LEFT, -1, fs, maxi(2, int(6 * k)), Color.BLACK)
	draw_string(font, tab + Vector2(-w * 0.5, fs * 0.35), price,
			HORIZONTAL_ALIGNMENT_LEFT, -1, fs, Color.WHITE)
	if hotkey != "":
		var hs := maxi(9, int(26.0 * k))
		draw_string_outline(font, Vector2(4, hs), hotkey.strip_edges(),
				HORIZONTAL_ALIGNMENT_LEFT, -1, hs, 3, Color.BLACK)
		draw_string(font, Vector2(4, hs), hotkey.strip_edges(),
				HORIZONTAL_ALIGNMENT_LEFT, -1, hs, Color.WHITE)

	if chosen:
		_blit(&"bk_select", Vector2(-2.17, -0.54), k, centre, Color.WHITE)
	elif _hover and usable and not disabled:
		_blit(&"bk_pointed", Vector2(-2.17, -0.54), k, centre, Color.WHITE)


## Draws one atlas image centred at `at` (rig units from the packet centre).
func _blit(name: StringName, at: Vector2, k: float, centre: Vector2, tint: Color) -> void:
	var region := _source.region(name)
	if region != null:
		_blit_texture(region, at + _source.region_offset(name), k, centre, tint)


func _blit_texture(tex: Texture2D, at: Vector2, k: float, centre: Vector2, tint: Color) -> void:
	var s := tex.get_size() * k
	draw_texture_rect(tex, Rect2(centre + at * k - s * 0.5, s), false, tint)
