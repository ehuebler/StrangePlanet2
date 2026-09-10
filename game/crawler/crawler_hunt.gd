class_name CrawlerHunt
extends RefCounted

## Shared post-spawn hunt for field packs. Idle bodies wake into agro, may
## pursue only from agro, drop to deagro past 50 m, and reagro inside 25 m.
## Roles pick the motion: melee charge, flying standoff, or ground standoff.

enum Stance { IDLE, AGRO, PURSUE, DEAGRO, REAGRO }
enum Role { NONE, MELEE, FLY_RANGE, GROUND_RANGE }

const DEAGRO := 50.0
const REAGRO := 25.0
const FIRST_AGRO := 36.0
const SPAWN_TICK := 2
const PURSUIT_LEAD := 14.0
const PURSUIT_EYE := 1.65
const PURSUIT_PAD := 12.0
const TANGLEMAW_PURSUIT := 0.38
const STRAFE_SECONDS := 1.9
const CROWN_CLEAR := 20.0
const SCOUT_FIRE := 2.6
const MELEE_LAND := 3.6

const MELEE_KINDS: PackedStringArray = [
	"rammer", "gloam", "tanglemaw", "glorb_eyeball", "glorb_punching"]
const FLY_KINDS: PackedStringArray = [
	"scout", "ranger", "vesper", "kestrel", "threnody",
	"glorb_jellyfish", "glorb_angel"]
const GROUND_KINDS: PackedStringArray = [
	"bastion", "weaver", "gray", "rhino",
	"glorb_rhino", "glorb_one_armed", "glorb_spider"]
const FAR_HOLD_KINDS: PackedStringArray = ["threnody"]


static func role(kind: String) -> Role:
	var clean := kind.strip_edges()
	if MELEE_KINDS.has(clean):
		return Role.MELEE
	if FLY_KINDS.has(clean):
		return Role.FLY_RANGE
	if GROUND_KINDS.has(clean):
		return Role.GROUND_RANGE
	return Role.NONE


static func hunting(stance: Stance) -> bool:
	return stance == Stance.AGRO or stance == Stance.PURSUE \
		or stance == Stance.REAGRO


static func prefer_ring(kind: String) -> int:
	if FAR_HOLD_KINDS.has(kind.strip_edges()):
		return CrawlerRules.FIELD_RING_FAR
	return CrawlerRules.FIELD_RING_MID


static func hold_band(kind: String) -> Vector2:
	return CrawlerRules.field_ring_band(prefer_ring(kind))


static func hold_min(kind: String) -> float:
	return maxf(hold_band(kind).x, CROWN_CLEAR)


static func hold_max(kind: String) -> float:
	return maxf(hold_band(kind).y, hold_min(kind) + 6.0)


static func shot_min(kind: String, level := 1) -> float:
	var catalog := CrawlerMobs.number(kind, level, "engage_min", 0.0)
	if catalog > 0.01:
		return catalog
	return hold_min(kind) * 0.72


static func shot_max(kind: String, level := 1) -> float:
	var catalog := CrawlerMobs.number(kind, level, "engage_max", 0.0)
	if catalog > 0.01:
		return maxf(catalog, shot_min(kind, level) + 6.0)
	return hold_max(kind) + 8.0


static func pursuit_speed(kind: String, player_speed: float, agro_speed: float) -> float:
	var clean := kind.strip_edges()
	if clean == "glorb_spider":
		return 15.0
	if clean == "glorb_punching":
		return minf(maxf(agro_speed, 0.0), 15.0)
	var pace := maxf(player_speed, 0.0) + PURSUIT_PAD
	if clean == "tanglemaw":
		return maxf(agro_speed, 0.0) * TANGLEMAW_PURSUIT \
			+ maxf(player_speed, 0.0) * 0.35
	return maxf(pace, agro_speed * 1.15)


static func uses_hunt(kind: String) -> bool:
	return role(kind) != Role.NONE


## Melee packs drop at 50 m. Flyers and ground guns keep the catalog leash so
## a vesper or threnody is not deagroed inside the ring it is meant to hold.
static func drop_gap(kind: String, catalog: float) -> float:
	if role(kind) == Role.MELEE:
		return DEAGRO
	return maxf(catalog, hold_max(kind) + 16.0)


static func wake_gap(kind: String, catalog: float) -> float:
	return maxf(catalog, 0.0)


static func rewake_gap(kind: String, catalog: float) -> float:
	if role(kind) == Role.MELEE:
		return REAGRO
	return maxf(catalog, REAGRO)
