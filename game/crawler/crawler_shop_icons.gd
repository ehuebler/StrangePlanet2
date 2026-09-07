class_name CrawlerShopIcons
extends RefCounted

## Shared store-sign glyphs. Used on tilde city names, city-store tabs, and
## the rotating stall markers. Rest stop and locker stay off this list.

const SIZE := 32
const INK := Color("ef151f")
const FILL := Color("45df68")
const EDGE := Color("f4f0ff")

const STALL_MARKS := {
	"hats": "INTERACT_HATS",
	"caps": "INTERACT_FUSION",
	"capes": "INTERACT_CAPES",
	"cards": "INTERACT_MODS",
	"abilities": "INTERACT_ABILITIES",
	"upgrades": "INTERACT_UPGRADES",
	"inventory": "INTERACT_STASH",
	"quests": "INTERACT_QUESTS",
	"duals": "INTERACT_DUALS",
	"market": "INTERACT_MARKET",
}

const STALL_NAMES := {
	"hats": "01_Hats",
	"caps": "02_Caps",
	"capes": "03_Capes",
	"cards": "04_Mods",
	"abilities": "05_Abilities",
	"upgrades": "06_Upgrades",
	"inventory": "07_Inventory",
	"quests": "08_Quests",
	"duals": "09_Duals",
	"market": "Community_Hall",
}

static var _cache: Dictionary = {}


static func texture_for(shop_id: String) -> Texture2D:
	var id := shop_id.strip_edges()
	if id.is_empty():
		return null
	if _cache.has(id):
		return _cache[id] as Texture2D
	var image := Image.create(SIZE, SIZE, false, Image.FORMAT_RGBA8)
	image.fill(Color(0, 0, 0, 0))
	_paint(image, id)
	var tex := ImageTexture.create_from_image(image)
	_cache[id] = tex
	return tex


static func shows_sign(shop_id: String) -> bool:
	var id := shop_id.strip_edges()
	return not id.is_empty() and id != "reststop" and id != "locker"


static func stall_mark(shop_id: String) -> String:
	return str(STALL_MARKS.get(shop_id, ""))


static func stall_name(shop_id: String) -> String:
	return str(STALL_NAMES.get(shop_id, ""))


static func _paint(image: Image, shop_id: String) -> void:
	_fill_box(image, 3, 3, 26, 26, Color(0.04, 0.03, 0.05, 0.72))
	_stroke_box(image, 3, 3, 26, 26, INK)
	match shop_id:
		"hats":
			_fill_box(image, 8, 14, 16, 8, FILL)
			_fill_box(image, 12, 8, 8, 8, EDGE)
		"caps":
			_fill_box(image, 6, 16, 10, 6, FILL)
			_fill_box(image, 16, 12, 10, 8, EDGE)
		"capes":
			_fill_box(image, 10, 7, 12, 4, EDGE)
			_fill_box(image, 8, 11, 16, 12, FILL)
		"cards":
			_fill_box(image, 10, 7, 12, 18, FILL)
			_fill_box(image, 13, 10, 6, 4, EDGE)
		"abilities":
			_fill_box(image, 14, 6, 4, 20, FILL)
			_fill_box(image, 8, 14, 16, 4, FILL)
		"upgrades":
			_fill_box(image, 14, 7, 4, 16, FILL)
			_fill_box(image, 10, 11, 12, 4, FILL)
			_fill_box(image, 12, 7, 8, 4, EDGE)
		"inventory":
			_fill_box(image, 8, 10, 16, 14, FILL)
			_fill_box(image, 12, 7, 8, 5, EDGE)
		"quests":
			_fill_box(image, 9, 7, 14, 18, EDGE)
			_fill_box(image, 12, 11, 8, 3, FILL)
			_fill_box(image, 12, 16, 8, 3, FILL)
		"market":
			_fill_box(image, 8, 14, 16, 10, FILL)
			_fill_box(image, 11, 8, 4, 8, EDGE)
			_fill_box(image, 17, 8, 4, 8, EDGE)
		"duals":
			_fill_box(image, 7, 10, 8, 12, FILL)
			_fill_box(image, 17, 10, 8, 12, EDGE)
		_:
			_fill_box(image, 12, 12, 8, 8, FILL)


static func _fill_box(
		image: Image, x: int, y: int, w: int, h: int, colour: Color) -> void:
	for yy in range(y, mini(y + h, SIZE)):
		for xx in range(x, mini(x + w, SIZE)):
			if xx >= 0 and yy >= 0:
				image.set_pixel(xx, yy, colour)


static func _stroke_box(
		image: Image, x: int, y: int, w: int, h: int, colour: Color) -> void:
	for xx in range(x, mini(x + w, SIZE)):
		if xx >= 0:
			if y >= 0 and y < SIZE:
				image.set_pixel(xx, y, colour)
			var bottom := y + h - 1
			if bottom >= 0 and bottom < SIZE:
				image.set_pixel(xx, bottom, colour)
	for yy in range(y, mini(y + h, SIZE)):
		if yy >= 0:
			if x >= 0 and x < SIZE:
				image.set_pixel(x, yy, colour)
			var right := x + w - 1
			if right >= 0 and right < SIZE:
				image.set_pixel(right, yy, colour)
