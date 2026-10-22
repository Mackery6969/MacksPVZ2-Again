class_name CoinToken
extends Collectable
## A coin: dropped by a coin bag at the end of a level, banked into the
## player's wallet when it reaches the coin counter.

## PVZGE's silver and gold coins.
const SILVER := 10
const GOLD := 50

var value: int = SILVER

@export var silver_color: Color = Color("d9dde3")
@export var gold_color: Color = Color("f2c53d")
@export var rim_color: Color = Color("8a8f96")


func _init() -> void:
	radius = 14.0
	# Coins from a bag fly in on their own; these only matter for a stray one.
	lifetime = 8.0


func art_id() -> StringName:
	return &"coin_gold" if value >= GOLD else &"coin_silver"


func _draw() -> void:
	if art != null:
		return
	draw_circle(Vector2.ZERO, radius, rim_color)
	draw_circle(Vector2.ZERO, radius - 2.5, gold_color if value >= GOLD else silver_color)
	draw_rect(Rect2(-2.0, -radius * 0.5, 4.0, radius), rim_color)
