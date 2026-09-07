class_name CrawlerGruk
extends CrawlerGoblin

## Castle bruiser. Runs at the player and swings.

const GRUK_HEIGHT := 1.95
const GRUK_WIDTH := 0.72
const GRUK_INK := Color(0.28, 0.40, 0.16)


func _ready() -> void:
	_base_health = 70.0
	_base_damage = 14.0
	_base_speed = 8.5
	super._ready()


func wild_kind() -> String:
	return "gruk"


func body_height() -> float:
	return GRUK_HEIGHT


func body_width() -> float:
	return GRUK_WIDTH


func body_ink() -> Color:
	return GRUK_INK
