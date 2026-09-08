class_name PlayerStats
extends RefCounted

## What the player is made of, as numbers a menu can list and other systems can
## read: two of them today, health and speed.
##
## This exists as its own object rather than as more fields on [OnlinePlayer]
## because the inventory screen has to *enumerate* stats — draw a row per stat
## with a name, a value and a bar — and a screen that hard-codes "health then
## speed" has to be edited every time a third one is added. [constant STATS] is
## the table it walks, so a new stat is one row here and appears in the menu
## and in a save with no UI change.
##
## Two kinds of number are kept apart on purpose:
##
## - The **base** is what the character is worth, and it is what gets saved.
## - The **effective** value is the base after whatever the world is currently
##   doing to it, which is where a speed bonus from apparel or a debuff from deep
##   snow would go. Nothing modifies anything yet, so the two agree; the split is
##   here so that when something does, the menu shows the modified figure while
##   the saved figure stays clean.

## Stat id → how to present it. `unit` is appended to the value, `maximum` is
## where a bar reads full, and `precision` is the decimals shown — health is a
## whole number and speed is not.
const STATS := {
	"health": {
		"title": "Health",
		"description": "How much damage you can take before you go down.",
		"base": 100.0,
		"minimum": 1.0,
		"maximum": 400.0,
		"unit": " HP",
		"precision": 0,
	},
	"speed": {
		"title": "Speed",
		"description": "How fast you move on foot. Sprinting and flying scale from this.",
		"base": 4.6,
		"minimum": 1.0,
		"maximum": 20.0,
		"unit": " m/s",
		"precision": 1,
	},
}

const HEALTH := &"health"
const SPEED := &"speed"

## Emitted for one stat when its base changes, so a screen can redraw one row
## rather than rebuilding its whole list.
signal changed(id: StringName, value: float)

var _base: Dictionary = {}
## Current health, which is the one stat with a live value distinct from its
## ceiling: the base is the maximum and this is what is left of it.
var _health := 0.0


func _init() -> void:
	for id: String in STATS:
		_base[id] = float(STATS[id]["base"])
	_health = base_of(HEALTH)


static func ids() -> PackedStringArray:
	return PackedStringArray(STATS.keys())


static func has_stat(id: StringName) -> bool:
	return STATS.has(String(id))


static func title_of(id: StringName) -> String:
	return String(_field(id, "title", String(id)))


static func description_of(id: StringName) -> String:
	return String(_field(id, "description", ""))


static func minimum_of(id: StringName) -> float:
	return float(_field(id, "minimum", 0.0))


static func maximum_of(id: StringName) -> float:
	return float(_field(id, "maximum", 100.0))


## The value as a menu should write it, unit and all.
static func format(id: StringName, value: float) -> String:
	var digits := int(_field(id, "precision", 0))
	return ("%.*f%s" % [digits, value, String(_field(id, "unit", ""))])


func base_of(id: StringName) -> float:
	return float(_base.get(String(id), 0.0))


## The base after whatever is currently acting on it. Identical to the base until
## something starts modifying stats; see the header for why the two are separate.
func value_of(id: StringName) -> float:
	return base_of(id)


func set_base(id: StringName, value: float) -> void:
	if not has_stat(id):
		return
	var clamped := clampf(value, minimum_of(id), maximum_of(id))
	if is_equal_approx(clamped, base_of(id)):
		return
	_base[String(id)] = clamped
	if id == HEALTH:
		_health = minf(_health, clamped)
	changed.emit(id, clamped)


## What is left of health, against `base_of(HEALTH)` as the full bar.
func health() -> float:
	return _health


func set_health(value: float) -> void:
	_health = clampf(value, 0.0, base_of(HEALTH))
	changed.emit(HEALTH, base_of(HEALTH))


## Everything the menu needs for one row, so the screen holds no knowledge of
## which stats exist or how they are written.
func row(id: StringName) -> Dictionary:
	var full := base_of(id)
	var now := _health if id == HEALTH else value_of(id)
	return {
		"id": id,
		"title": title_of(id),
		"description": description_of(id),
		"text": format(id, now),
		"value": now,
		"maximum": maxf(full, 0.001),
		"share": clampf(now / maxf(full, 0.001), 0.0, 1.0),
	}


static func _field(id: StringName, key: String, fallback: Variant) -> Variant:
	var stat: Variant = STATS.get(String(id), {})
	if stat is Dictionary and (stat as Dictionary).has(key):
		return (stat as Dictionary)[key]
	return fallback
