class_name JournalDB
extends RefCounted

## The one catalogue of quests and achievements.
##
## Both are the same kind of thing — a titled goal with a description, a category
## to filter by, and a condition that decides when it is done — so they are one
## table with a `kind` field rather than two tables that would drift. The Quests
## and Achievements tabs of [GameMenu] are the same page class handed a different
## kind, for the same reason.
##
## Conditions are **data, not code**. Today the only kind is `landmark`: be within
## `within` metres of the [Landmark] node of that name. That covers both starter
## entries and it means [Journal] has one thing to check rather than a match
## statement that grows with the table. A condition nothing knows how to check is
## left permanently incomplete rather than treated as done, so a half-written entry
## is visible instead of silently rewarding itself.

const QUEST := &"quest"
const ACHIEVEMENT := &"achievement"

## Entry id → kind, the category it filters under, how it reads, and what finishes
## it. `landmark` is the **node name** in `game/world.tscn`, not the title: the
## title is what a player reads and is free to be reworded.
const ENTRIES := {
	"see_vacationers_landing": {
		"kind": "quest",
		"category": "Main",
		"title": "Vacationer's Landing",
		"summary": "Travel to Vacationer's Landing.",
		"detail": "The only city on the planet, on the coast of the daylit side. "
			+ "Fly toward the waypoint until the roads are under you.",
		"reward": "The run of the place.",
		"landmark": "VacationersLanding",
		"within": 340.0,
	},
	"stand_on_iceland": {
		"kind": "achievement",
		"category": "Exploration",
		"title": "Iceland",
		"summary": "Reach Iceland, at the north pole.",
		"detail": "The pole is pack ice under a foot of snow, walled in by cloud. "
			+ "Getting there is the achievement; getting back is your problem.",
		"reward": "",
		"landmark": "Iceland",
		"within": 400.0,
	},
	"kill_10_mobs": {
		"kind": "achievement",
		"category": "Combat",
		"title": "Kill 10 mobs",
		"summary": "Defeat ten crawler enemies.",
		"detail": "Any crawler kill counts. The tenth one unlocks five gems. "
			+ "Claim them from Achievements in the menu.",
		"reward": "5 gems",
		"gems": 5,
		"kills": 10,
	},
}


static func ids_of_kind(kind: StringName) -> PackedStringArray:
	var out := PackedStringArray()
	for id: String in ENTRIES:
		if StringName(str(ENTRIES[id].get("kind", ""))) == kind:
			out.append(id)
	return out


## Every category present for a kind, with "All" first, which is what the filter
## at the top of the page lists. Derived rather than declared so a new entry in a
## new category needs no second edit.
static func categories_of_kind(kind: StringName) -> PackedStringArray:
	var out := PackedStringArray(["All"])
	for id in ids_of_kind(kind):
		var category := String(field(id, "category", ""))
		if not category.is_empty() and not category in out:
			out.append(category)
	return out


static func has_entry(id: String) -> bool:
	return ENTRIES.has(id)


static func kind_of(id: String) -> StringName:
	return StringName(str(field(id, "kind", "")))


static func title_of(id: String) -> String:
	return String(field(id, "title", id))


static func summary_of(id: String) -> String:
	return String(field(id, "summary", ""))


static func detail_of(id: String) -> String:
	return String(field(id, "detail", ""))


static func category_of(id: String) -> String:
	return String(field(id, "category", ""))


static func reward_of(id: String) -> String:
	return String(field(id, "reward", ""))


## The landmark node this entry sends you to, or empty if it is not that kind of
## condition.
static func landmark_of(id: String) -> String:
	return String(field(id, "landmark", ""))


static func within_of(id: String) -> float:
	return float(field(id, "within", 0.0))


static func kills_of(id: String) -> int:
	return maxi(int(field(id, "kills", 0)), 0)


static func gems_of(id: String) -> int:
	return maxi(int(field(id, "gems", 0)), 0)


static func field(id: String, key: String, fallback: Variant) -> Variant:
	var entry: Variant = ENTRIES.get(id, {})
	if entry is Dictionary and (entry as Dictionary).has(key):
		return (entry as Dictionary)[key]
	return fallback
