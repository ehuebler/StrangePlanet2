class_name CharacterDB
extends RefCounted

## The bodies a player can be. Each entry names the .glb, the collider/eye heights
## that fit it, and the apparel items that sit on its skeleton. Garments from one
## body are not offered on another: they share slot names so the equipment column
## stays the same shape, but the meshes only bind cleanly to the skeleton they
## were cut from.
##
## `playable` is what the home screen and the character editor offer. The
## astronaut is switched off rather than deleted: its body, its five garments and
## its `ItemDB` entries are all still good, `dev/_check_character.gd` and friends
## still measure it, and turning it back on is this one flag. What being off means
## is that [method sanitize_body] sends it to the default, so a `settings.cfg`
## saved when it was the default quietly becomes a settler rather than spawning a
## body nothing offers.

const DEFAULT_BODY := "settler"
const HOTBAR_SLOTS := 3
const ABILITY_SLOTS := 2
const BACKPACK_SLOTS := 36
## One-time ownership seed. Revision five repairs the known partial-wardrobe
## state where Settler Hair alone was never granted. Revision six grants the
## first twenty-five settler hats. Revision seven grants the next batch. Other
## missing pieces remain finite ownership: once this revision is recorded,
## dropped apparel stays gone.
const STARTER_INVENTORY_REVISION := 7

## Headwear added after the original settler wardrobe. Granted once by revision
## six without resurrecting garments a player already dropped.
const SETTLER_HEADWEAR := [
	"c3_party_hat", "c3_bunny_ears", "c3_top_hat", "c3_crown", "c3_beanie",
	"c3_cowboy_hat", "c3_propeller_cap", "c3_flower_crown", "c3_antlers",
	"c3_halo", "c3_wizard_hat", "c3_sombrero", "c3_newsboy_cap", "c3_helmet",
	"c3_pirate_hat", "c3_chef_toque", "c3_jester_hat", "c3_mushroom_cap",
	"c3_antennae", "c3_visor", "c3_bow", "c3_horned_helm", "c3_fedora",
	"c3_santa_hat", "c3_cat_ears",
]

## Second hat drop. Granted once by revision seven; dropped first-batch hats
## stay dropped.
const SETTLER_HEADWEAR_MORE := [
	"c3_beret", "c3_baseball_cap", "c3_sun_hat", "c3_hard_hat", "c3_ushanka",
	"c3_turban", "c3_devil_horns", "c3_unicorn_horn", "c3_headphones", "c3_tiara",
	"c3_bandana", "c3_rice_hat", "c3_laurel", "c3_nightcap", "c3_deerstalker",
	"c3_frog_hood", "c3_rainbow", "c3_paper_crown", "c3_space_helmet",
	"c3_cake_hat", "c3_leaf_wreath", "c3_mohawk",
]

## Paint schemes laid over a body without changing its mesh, skeleton or
## measurements. A skin is kept separate from `body`: all three painted designs
## use the same settler and the same wardrobe, so treating them as bodies would
## duplicate every physical field and make apparel compatibility lie.
const SKINS := {
	"luke": {
		"title": "Luke",
		"texture": "res://assets/runtime/characters/luke.png",
	},
	"clean_robotic": {
		"title": "Clean Robotic",
		"texture": "res://assets/runtime/characters/character_3_clean_robotic.png",
	},
	"integrated_robotic": {
		"title": "Integrated Robotic",
		"texture": "res://assets/runtime/characters/character_3_integrated_robotic.png",
	},
}

const BODIES := {
	"astronaut": {
		"title": "Astronaut",
		"playable": false,
		"scene": "res://assets/runtime/characters/player_character.glb",
		"height": 1.45,
		"eye_height": 1.29,
		"eye_offset": Vector3(0.076, 0.102, -0.192),
		"lean_pivot": 0.72,
		"apparel": ["straw_hat", "flight_goggles", "rust_long_sleeve", "denim_trousers",
			"leather_shoes"],
		"skins": [],
	},
	"settler": {
		"title": "Settler",
		"playable": true,
		"scene": "res://assets/runtime/characters/player_character_3.glb",
		"height": 1.6,
		"eye_height": 1.45,
		"eye_offset": Vector3(0.048, 0.104, -0.084),
		"lean_pivot": 0.85,
		"apparel": [
			"c3_hair",
			"c3_party_hat", "c3_bunny_ears", "c3_top_hat", "c3_crown", "c3_beanie",
			"c3_cowboy_hat", "c3_propeller_cap", "c3_flower_crown", "c3_antlers",
			"c3_halo", "c3_wizard_hat", "c3_sombrero", "c3_newsboy_cap", "c3_helmet",
			"c3_pirate_hat", "c3_chef_toque", "c3_jester_hat", "c3_mushroom_cap",
			"c3_antennae", "c3_visor", "c3_bow", "c3_horned_helm", "c3_fedora",
			"c3_santa_hat", "c3_cat_ears",
			"c3_beret", "c3_baseball_cap", "c3_sun_hat", "c3_hard_hat", "c3_ushanka",
			"c3_turban", "c3_devil_horns", "c3_unicorn_horn", "c3_headphones",
			"c3_tiara", "c3_bandana", "c3_rice_hat", "c3_laurel", "c3_nightcap",
			"c3_deerstalker", "c3_frog_hood", "c3_rainbow", "c3_paper_crown",
			"c3_space_helmet", "c3_cake_hat", "c3_leaf_wreath", "c3_mohawk",
			"c3_goggles", "c3_tunic", "c3_boots",
		],
		# First is the fallback for an old settings file with no skin key.
		"skins": ["luke", "clean_robotic", "integrated_robotic"],
	},
}


static func body_ids() -> PackedStringArray:
	return PackedStringArray(BODIES.keys())


## The bodies anybody is allowed to choose, which is what the home screen and the
## editor list. Anything walking the bodies to *offer* one wants this; anything
## walking them to measure or check an asset wants [method body_ids].
static func playable_ids() -> PackedStringArray:
	var out := PackedStringArray()
	for id: String in BODIES:
		if bool(_field(id, "playable", false)):
			out.append(id)
	return out


static func is_playable(id: String) -> bool:
	return bool(_field(id, "playable", false))


static func has_body(id: String) -> bool:
	return BODIES.has(id)


static func title(id: String) -> String:
	return String(_field(id, "title", id))


static func scene_path(id: String) -> String:
	return String(_field(id, "scene", BODIES[DEFAULT_BODY]["scene"]))


static func scene(id: String) -> PackedScene:
	return load(scene_path(id)) as PackedScene


static func height(id: String) -> float:
	return float(_field(id, "height", 1.45))


static func eye_height(id: String) -> float:
	return float(_field(id, "eye_height", 1.29))


## Where one eye sits relative to the head joint, in the *body's* space: x out to
## the character's right, y up, and z backwards — so a point on the face has a
## negative z, the same as every other forward vector in the engine. The other
## eye is the same offset with x negated, because no body here has an asymmetric
## face and storing both would only be two numbers to keep in agreement.
##
## Deliberately not in head-bone space, which is what these used to be and is a
## trap: the two characters' Head bones are turned half a circle from each other,
## so the same numbers point at the face on one and out of the back of the neck
## on the other. [method OnlinePlayer.eye_points] converts.
##
## Measured off each body rather than estimated — the front of the face at eye
## height, and for the settler the goggles, which are worn on the eyes and so say
## where the eyes are. `dev/_eye_probe.tscn` prints what a new body needs.
##
## Distinct from [method eye_height], which is where the *camera* sits. That one
## is a comfortable viewing height; this one has to land on the actual face,
## because a beam that leaves the middle of the forehead looks wrong from the
## outside even when it is aimed perfectly.
static func eye_offset(id: String) -> Vector3:
	return _field(id, "eye_offset", Vector3(0.048, 0.104, -0.084))


static func lean_pivot(id: String) -> float:
	return float(_field(id, "lean_pivot", 0.72))


static func skin_ids(body_id: String) -> PackedStringArray:
	var raw: Variant = _field(body_id, "skins", [])
	var out := PackedStringArray()
	for entry: Variant in raw:
		var id := str(entry)
		if SKINS.has(id):
			out.append(id)
	return out


static func default_skin(body_id: String) -> String:
	var ids := skin_ids(body_id)
	return ids[0] if not ids.is_empty() else ""


static func sanitize_skin(body_id: String, skin_id: String) -> String:
	return skin_id if skin_id in skin_ids(body_id) else default_skin(body_id)


static func skin_title(skin_id: String) -> String:
	var skin: Dictionary = SKINS.get(skin_id, {})
	return str(skin.get("title", skin_id))


static func skin_texture_path(body_id: String, skin_id: String) -> String:
	var clean := sanitize_skin(body_id, skin_id)
	var skin: Dictionary = SKINS.get(clean, {})
	return str(skin.get("texture", ""))


static func skin_texture(body_id: String, skin_id: String) -> Texture2D:
	var path := skin_texture_path(body_id, skin_id)
	return load(path) as Texture2D if not path.is_empty() else null


## Item ids that belong on this body, in the order the editor lists them.
static func apparel_ids(id: String) -> PackedStringArray:
	var raw: Variant = _field(id, "apparel", [])
	var out := PackedStringArray()
	for entry in raw:
		out.append(String(entry))
	return out


## True when this garment was authored for this body's skeleton.
static func apparel_fits(body_id: String, item_id: String) -> bool:
	return item_id in apparel_ids(body_id)


static func sanitize_body(id: String) -> String:
	return id if is_playable(id) else DEFAULT_BODY


## Look dictionary written by the home-screen editor and read when a body is
## previewed or spawned. `skin` is a texture scheme allowed by that body, `worn`
## is slot → item id and `tints` is "body" or a slot → HTML colour, both sparse.
## Hotbar, abilities and backpack are positional. `rack` mirrors hotbar while old
## pages and harnesses still use that name.
static func default_look() -> Dictionary:
	var hotbar := _empty_slots(HOTBAR_SLOTS)
	return {
		"body": DEFAULT_BODY,
		"skin": default_skin(DEFAULT_BODY),
		"worn": {},
		"hotbar": hotbar,
		"abilities": _empty_slots(ABILITY_SLOTS),
		"backpack": [],
		"rack": hotbar.duplicate(),
		"tints": {},
	}


static func load_look() -> Dictionary:
	var look := default_look()
	# Autoload global — do not path through /root; that fails outside a live tree
	# and was returning the astronaut default even when settings.cfg said settler.
	if SettingsManager == null:
		return look
	look["body"] = sanitize_body(str(SettingsManager.get_setting(
		&"appearance", &"body", DEFAULT_BODY)))
	look["skin"] = sanitize_skin(str(look["body"]), str(SettingsManager.get_setting(
		&"appearance", &"skin", default_skin(str(look["body"])))))
	var worn_raw: Variant = SettingsManager.get_setting(&"appearance", &"worn", {})
	if worn_raw is Dictionary:
		var worn: Dictionary = {}
		for slot: Variant in worn_raw:
			var item_id := str(worn_raw[slot])
			if ItemDB.has_item(item_id) and apparel_fits(str(look["body"]), item_id):
				worn[str(slot)] = item_id
		look["worn"] = worn
	var hotbar_raw: Variant = SettingsManager.get_setting(
		&"appearance", &"hotbar", null)
	if not _is_item_sequence(hotbar_raw):
		hotbar_raw = SettingsManager.get_setting(&"appearance", &"rack", [])
	var clean_hotbar := hotbar_items({"hotbar": hotbar_raw}, HOTBAR_SLOTS)
	look["hotbar"] = _plain_array(clean_hotbar)
	look["rack"] = _plain_array(clean_hotbar)
	var abilities_raw: Variant = SettingsManager.get_setting(
		&"appearance", &"abilities", [])
	look["abilities"] = _plain_array(ability_items(
		{"abilities": abilities_raw}, ABILITY_SLOTS))
	var backpack_raw: Variant = SettingsManager.get_setting(
		&"appearance", &"backpack", [])
	look["backpack"] = _trimmed_array(backpack_items(
		{"backpack": backpack_raw}, BACKPACK_SLOTS))
	var tint_raw: Variant = SettingsManager.get_setting(&"appearance", &"tints", {})
	if tint_raw is Dictionary:
		look["tints"] = (tint_raw as Dictionary).duplicate(true)
	_seed_starter_inventory(look)
	return look


## Gives a new character its finite starter wardrobe and weapons once. Later
## revisions also repair older marked-complete states where the whole compatible
## wardrobe is absent. Owning even one compatible garment proves the wardrobe
## was established, so missing individual pieces stay missing except for the
## revision-five Settler Hair rollout repair below.
static func _seed_starter_inventory(look: Dictionary) -> void:
	if SettingsManager == null:
		return
	var revision := int(SettingsManager.get_setting(
		&"appearance", &"starter_inventory_revision", 0))
	if revision >= STARTER_INVENTORY_REVISION:
		return

	var owned := {}
	var worn_raw: Variant = look.get("worn", {})
	if worn_raw is Dictionary:
		for item_variant: Variant in (worn_raw as Dictionary).values():
			var worn_id := str(item_variant)
			if not worn_id.is_empty():
				owned[worn_id] = true
	var backpack: Array = []
	var backpack_raw: Variant = look.get("backpack", [])
	if _is_item_sequence(backpack_raw):
		for item_variant: Variant in backpack_raw:
			var item_id := str(item_variant)
			if item_id.is_empty():
				continue
			backpack.append(item_id)
			owned[item_id] = true
	var hotbar: Array = []
	var hotbar_raw: Variant = look.get("hotbar", [])
	if _is_item_sequence(hotbar_raw):
		for item_variant: Variant in hotbar_raw:
			var item_id := str(item_variant)
			hotbar.append(item_id)
			if not item_id.is_empty():
				owned[item_id] = true
	hotbar.resize(HOTBAR_SLOTS)
	for index in hotbar.size():
		if hotbar[index] == null:
			hotbar[index] = ""

	var body_id := sanitize_body(str(look.get("body", DEFAULT_BODY)))
	var wardrobe := apparel_ids(body_id)
	var should_seed := revision < 1
	if revision >= 1:
		should_seed = true
		for item_id: String in wardrobe:
			if owned.has(item_id):
				should_seed = false
				break
	if should_seed:
		for item_id: String in wardrobe:
			if owned.has(item_id) or backpack.size() >= BACKPACK_SLOTS:
				continue
			backpack.append(item_id)
			owned[item_id] = true
	# Revision four treated any one owned garment as proof that the whole starter
	# wardrobe had been granted. That preserved genuinely dropped items, but it
	# also preserved the specific broken rollout now seen in existing profiles:
	# goggles, tunic and boots present while Settler Hair never existed. Repair
	# that known item once without manufacturing every other absent garment.
	if revision < 5 and body_id == "settler" and not owned.has("c3_hair") \
			and backpack.size() < BACKPACK_SLOTS:
		backpack.append("c3_hair")
		owned["c3_hair"] = true
	if revision < 6 and body_id == "settler":
		for item_id: String in SETTLER_HEADWEAR:
			if owned.has(item_id) or backpack.size() >= BACKPACK_SLOTS:
				continue
			backpack.append(item_id)
			owned[item_id] = true
	if revision < 7 and body_id == "settler":
		for item_id: String in SETTLER_HEADWEAR_MORE:
			if owned.has(item_id) or backpack.size() >= BACKPACK_SLOTS:
				continue
			backpack.append(item_id)
			owned[item_id] = true
	# Weapons were authored before finite ownership was introduced, but older
	# profiles were never granted them. Fill open numbered slots first so both
	# weapons are immediately usable without disturbing an existing assignment.
	for item_id: String in ItemDB.weapon_ids():
		if owned.has(item_id):
			continue
		var target := hotbar.find("")
		if target >= 0:
			hotbar[target] = item_id
		elif backpack.size() < BACKPACK_SLOTS:
			backpack.append(item_id)
		else:
			continue
		owned[item_id] = true
	look["hotbar"] = hotbar
	look["rack"] = hotbar.duplicate()
	look["backpack"] = backpack
	SettingsManager.set_setting(
		&"appearance", &"hotbar", hotbar.duplicate(), false)
	SettingsManager.set_setting(
		&"appearance", &"rack", hotbar.duplicate(), false)
	SettingsManager.set_setting(
		&"appearance", &"backpack", backpack.duplicate(), false)
	SettingsManager.set_setting(
		&"appearance", &"starter_inventory_revision",
		STARTER_INVENTORY_REVISION, false)
	SettingsManager.save_settings()


static func save_look(look: Dictionary) -> void:
	if SettingsManager == null:
		return
	var body_id := sanitize_body(str(look.get("body", DEFAULT_BODY)))
	var clean_worn: Dictionary = {}
	var worn_raw: Variant = look.get("worn", {})
	if worn_raw is Dictionary:
		for slot: String in ItemDB.SLOT_ORDER:
			var item_id := str((worn_raw as Dictionary).get(slot, ""))
			if apparel_fits(body_id, item_id):
				clean_worn[slot] = item_id
	var clean_hotbar := hotbar_items(look, HOTBAR_SLOTS)
	var clean_abilities := ability_items(look, ABILITY_SLOTS)
	var clean_backpack := backpack_items(look, BACKPACK_SLOTS)
	var clean_tints: Dictionary = {}
	var tint_raw: Variant = look.get("tints", {})
	if tint_raw is Dictionary:
		clean_tints = (tint_raw as Dictionary).duplicate(true)
	SettingsManager.set_setting(&"appearance", &"body", body_id, false)
	SettingsManager.set_setting(&"appearance", &"skin",
		sanitize_skin(body_id, str(look.get("skin", ""))), false)
	SettingsManager.set_setting(&"appearance", &"worn", clean_worn, false)
	SettingsManager.set_setting(&"appearance", &"hotbar",
		_plain_array(clean_hotbar), false)
	SettingsManager.set_setting(&"appearance", &"abilities",
		_plain_array(clean_abilities), false)
	SettingsManager.set_setting(&"appearance", &"backpack",
		_trimmed_array(clean_backpack), false)
	# Compatibility mirror for code that has not moved from rack to hotbar yet.
	SettingsManager.set_setting(&"appearance", &"rack",
		_plain_array(clean_hotbar), false)
	SettingsManager.set_setting(&"appearance", &"tints", clean_tints, false)
	SettingsManager.save_settings()


## Slot-ordered item ids for the wire / equipment container.
static func worn_items(look: Dictionary) -> PackedStringArray:
	var body_id := sanitize_body(str(look.get("body", DEFAULT_BODY)))
	var worn: Dictionary = look.get("worn", {})
	var out := PackedStringArray()
	out.resize(ItemDB.SLOT_ORDER.size())
	for index in ItemDB.SLOT_ORDER.size():
		var slot: String = ItemDB.SLOT_ORDER[index]
		var item_id := str(worn.get(slot, ""))
		out[index] = item_id if apparel_fits(body_id, item_id) else ""
	return out


## Numbered weapon/item slots. New code should use this method; unlike the old
## rack it also accepts ordinary usable items.
static func hotbar_items(look: Dictionary, slots := HOTBAR_SLOTS) -> PackedStringArray:
	var raw: Variant = look.get("hotbar", look.get("rack", []))
	return _filtered_items(raw, slots, ItemDB.HOTBAR)


static func ability_items(look: Dictionary, slots := ABILITY_SLOTS) -> PackedStringArray:
	return _filtered_items(look.get("abilities", []), slots, ItemDB.ABILITY)


static func backpack_items(look: Dictionary, slots := BACKPACK_SLOTS) -> PackedStringArray:
	return _filtered_items(look.get("backpack", []), slots, ItemDB.BACKPACK)


## Compatibility alias for old menu/editor code.
static func racked_items(look: Dictionary, slots: int) -> PackedStringArray:
	return hotbar_items(look, slots)


static func _filtered_items(raw: Variant, slots: int, filter: String) -> PackedStringArray:
	var out := PackedStringArray()
	out.resize(maxi(slots, 0))
	if not _is_item_sequence(raw):
		return out
	for index in mini(out.size(), raw.size()):
		var item_id := str(raw[index])
		out[index] = item_id if ItemDB.accepts(filter, item_id) else ""
	return out


static func _is_item_sequence(value: Variant) -> bool:
	return value is Array or value is PackedStringArray


static func _empty_slots(count: int) -> Array:
	var out: Array = []
	out.resize(maxi(count, 0))
	out.fill("")
	return out


static func _plain_array(items: PackedStringArray) -> Array:
	var out: Array = []
	for item_id: String in items:
		out.append(item_id)
	return out


static func _trimmed_array(items: PackedStringArray) -> Array:
	var out := _plain_array(items)
	while not out.is_empty() and str(out.back()).is_empty():
		out.pop_back()
	return out


## Reads a field off any body this file knows about, playable or not — which is
## deliberately a weaker test than [method sanitize_body]. Being switched off
## decides what may be *chosen*; it must not change what the astronaut's own
## measurements are, or `scene_path("astronaut")` starts returning the settler and
## every asset check quietly measures the wrong body.
static func _field(id: String, key: String, fallback: Variant) -> Variant:
	var body: Variant = BODIES.get(id if has_body(id) else DEFAULT_BODY, {})
	if body is Dictionary and (body as Dictionary).has(key):
		return (body as Dictionary)[key]
	return fallback
