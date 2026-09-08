class_name CrawlerNix
extends CrawlerGoblin

## Smaller castle runner. Same charge-and-swing as Gruk, just quicker.

const NIX_HEIGHT := 1.58
const NIX_WIDTH := 0.52
const NIX_INK := Color(0.18, 0.32, 0.22)


func _ready() -> void:
	_base_health = 4.0
	_base_damage = 5.0
	_base_speed = 11.0
	super._ready()


func wild_kind() -> String:
	return "nix"


func body_height() -> float:
	return NIX_HEIGHT


func body_width() -> float:
	return NIX_WIDTH


func body_ink() -> Color:
	return NIX_INK
