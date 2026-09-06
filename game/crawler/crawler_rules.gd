class_name CrawlerRules
extends RefCounted

## Session rules that only apply while the hosted mode is crawler.
##
## Crawler is still a string id on [member NetworkManager.session_options]. This
## file is the one place gameplay asks that question, so hero UI, the HUD, and
## the starter kit stay in agreement.

const MODE_ID := "crawler"
const ABILITY_SLOTS := 3
const ENABLED_ABILITIES: PackedStringArray = [
	"laser_eyes", "meteor_punch", "starfire",
]
const LASER_DAMAGE := 50.0
const LASER_COOLDOWN := 0.5
const LASER_DURATION := 0.4
const LASER_RANGE := 60.0
const LASER_RANGE_PER_RANK := 15.0
const LASER_KNOCKBACK := 8.0
const LASER_KNOCKBACK_PER_RANK := 2.5
const LASER_SLOTS := 3
const STARFIRE_DAMAGE := 350.0
const STARFIRE_IMPACT := 650.0
const STARFIRE_COOLDOWN := 2.0
const STARFIRE_RANGE := 70.0
const STARFIRE_RADIUS := 4.5
const STARFIRE_PROJECTILE_RADIUS := 0.36
const STARFIRE_CRATER_RADIUS := 3.0
const STARFIRE_SLOTS := 3
const STARFIRE_DAMAGE_PER_RANK := 90.0
const STARFIRE_COOLDOWN_PER_RANK := 0.20
const STARFIRE_COOLDOWN_MIN := 0.8
const STARFIRE_RANGE_PER_RANK := 12.0
const STARFIRE_SIZE_PER_RANK := 0.12
const STARFIRE_KNOCKBACK := 12.0
const STARFIRE_KNOCKBACK_PER_RANK := 3.5
const METEOR_DAMAGE := 180.0
const METEOR_IMPACT := 320.0
const METEOR_COOLDOWN := 3.2
const METEOR_COOLDOWN_PER_RANK := 0.28
const METEOR_COOLDOWN_MIN := 1.4
const METEOR_RANGE := 36.0
const METEOR_RANGE_PER_RANK := 8.0
const METEOR_RADIUS := 2.4
const METEOR_CRATER_RADIUS := 3.6
const METEOR_CRATER_DEPTH := 1.6
const METEOR_SPEED := 160.0
const METEOR_SIZE_PER_RANK := 0.12
const METEOR_KNOCKBACK := 18.0
const METEOR_KNOCKBACK_PER_RANK := 4.0
const METEOR_SLOTS := 3
const BIG_SIZE_MAX_RANK := 10
const BIG_SIZE_BASE := 1.22
const BIG_SIZE_GROWTH := 1.26
const INVENTORY_COLUMNS := 11
const INVENTORY_ROWS := 2
const INVENTORY_SLOTS := INVENTORY_COLUMNS * INVENTORY_ROWS
const MAX_MOD_SLOTS := 8
const START_CITIES := 0
const START_PATCH := "Tide Margin 4"
## Coordinate-plate reading for the Relay 07 pad: lat 3.09 N, lon 1.28 W.
const SPAWN_LATITUDE_DEG := 3.09
const SPAWN_LONGITUDE_DEG := -1.28
const CITY_PATCH := "Quiet Inlet 4"
## Coordinate-plate reading for Neon Fjord: lat 0.18 N, lon 4.78 E.
const CITY_LATITUDE_DEG := 0.18
const CITY_LONGITUDE_DEG := 4.78
const START_SITE_ID := "start"
const CITY_SITE_ID := "city"
const START_SITE_TITLE := "Tide Margin"
const CITY_SITE_TITLE := "Neon Fjord"
const START_ENTER_RADIUS := 100.0
const TOWER_PATCH := "Far Beacon 4"
const CASTLE_PATCH := "Long Shore 4"
const CITY_RING_PUSH := 420.0
const CITY_RING_RADIUS := 96.0
const CITY_RING_HEIGHT := 110.0
const CITY_RING_WALL := 5.0
const CITY_RING_OPENING := 16.0
const SPEED_SCALE := 0.30
const FLY_SPEED := 85.0
const FLOAT_SPEED := 5.5
const CLIMB_SPEED := 3.5
const FLIGHT_SECONDS := 3.8
const FLIGHT_BOOST_DRAIN := 2.4
const FLIGHT_REGEN := 0.16
const WILD_STREAM_IN := 280.0
const WILD_STREAM_OUT := 420.0
const START_ENCOUNTER := 240.0
const START_AMBUSH := 4
const START_CHASE := 2
const WILD_KINDS: PackedStringArray = ["ranger", "rammer", "rhino"]
const START_NEAR_KINDS: PackedStringArray = ["ranger", "rhino"]
const START_FAR_KINDS: PackedStringArray = ["ranger", "rhino", "rammer"]
const START_NEAR_RANGE := 80.0
const START_HEALTH_SCALE := 0.1
const LIVE_AROUND := 28
const KIND_CAP_BASE := {
	"ranger": 11,
	"rhino": 9,
	"rammer": 9,
	"rift_hulk": 1,
}
const KIND_CAP_EVERY := 2
const FLYER_CEILING_BASE := 16.0
const FLYER_CEILING_PER_LEVEL := 7.0
const AGRO_SHARE := 0.0
const SPAWN_MIN := 90.0
const SPAWN_MAX := 240.0
const SPAWN_LEAD := 1.4
const SPAWN_BAND := 42.0
const SPAWN_CONE := 0.34
const SPAWN_TRAVEL_MIN := 2.8
const SPAWN_AGRO_PAD := 32.0
const START_RING_STEP := TAU * 0.381966
const SPAWN_LEAD_SPEED := 16.0
const SPAWN_LEAD_PACK := 6
const SPAWN_LEAD_KIND := 3
const KILL_COOLDOWN := 5.0
const KILL_RADIUS := 34.0
const KILL_REFILL := 3.5
const RAMMER_SPAWN := 90.0
const RAMMER_SPAWN_LEAD := 1.4
const RAMMER_LIFT := 1.8
const RAMMER_TOP := 24.0
const RAMMER_TOP_SHARE := 0.15
const RAMMER_ACCEL := 10.0
const PACK_KEEP := 260.0
const AGRO_RANGE := 36.0
const DEAGRO_RANGE := 110.0
const IDLE_DESPAWN := 7.5
const CITY_SAFE_PAD := 48.0
const CITY_ENTER_RADIUS := CITY_RING_RADIUS + CITY_SAFE_PAD
const PERCEPTION := 120.0
const PATROL_RADIUS := 72.0
const RANGER_STANDOFF_MIN := 24.0
const RANGER_STANDOFF_MAX := 42.0
const RANGER_STANDOFF_PER_LEVEL := 8.0
const RANGER_ENGAGE_MIN := 20.0
const RANGER_ENGAGE_MAX := 52.0
const RANGER_ENGAGE_PER_LEVEL := 16.0
const RANGER_MATCH_LAG := 0.22
const RANGER_MATCH_LAG_PER_LEVEL := 0.14
const RANGER_MATCH_FLOOR := 5.0
const RANGER_MATCH_FLOOR_PER_LEVEL := 3.5
const RANGER_MATCH_SHARE := 0.56
const RANGER_MATCH_SHARE_PER_LEVEL := 0.16
const RANGER_MATCH_PAD := 10.0
const RANGER_MATCH_PAD_PER_LEVEL := 8.0
const RANGER_MATCH_LOCK := 1.6
const RANGER_MATCH_LOCK_PER_LEVEL := 2.4
const RANGER_SHOT_SPEED := 24.0
const RANGER_SHOT_SPEED_PER_LEVEL := 4.0
const RANGER_SHOT_BALL := 0.62
const RANGER_SHOT_BALL_PER_LEVEL := -0.06
const RANGER_SHOT_HIT := 1.45
const RANGER_SHOT_HIT_PER_LEVEL := -0.10
const RANGER_SHOT_AOE := 3.6
const RANGER_SHOT_AOE_SHARE := 2.4
const RANGER_SHOT_AOE_FALLOFF := 0.55
const RANGER_CROWN_CLEAR := 20.0
const RANGER_AIM_SECONDS := 1.0
const RHINO_MATCH_SHARE := 0.82
const RHINO_MATCH_PAD := 5.5
const RHINO_INTERCEPT_MAX := 2.2
const RHINO_RUN_SPEED := 8.0
const RHINO_BACKUP := 7.5
const RHINO_LEAD := 14.0
const SAFE_BOX_INNER := 20.0
const SAFE_BOX_WALL := 2.6
const SAFE_BOX_HEIGHT := 14.0
const SAFE_BOX_OPENING := 6.0
const SAFE_HEAL_PER_SECOND := 22.0
const CITY_HEAL_PER_SECOND := 16.0
const THREAT_SPEED := 1.12
const THREAT_HEALTH := 1.18
const THREAT_FIRE := 0.88
const THREAT_DAMAGE := 1.16
const CITY_DESTROY_RATIO := 0.6
const CITY_INFLUENCE_METRES := 560.0
const CITY_WAYPOINT_GROUP := &"crawler_city_waypoint"
const SITE_GROUP := &"crawler_sites"


## Neon Fjord is the one place tilde should name from the first frame.
## Spawn, monuments, and later cities wait until the player walks in.
static func starts_visible(site_id: String) -> bool:
	return site_id == CITY_SITE_ID


## Planet-local radial from a coordinate-plate reading. Latitude is asin(y),
## longitude is atan2(x, z), east toward +X.
static func direction_from_plate(latitude_deg: float, longitude_deg: float) -> Vector3:
	var lat := deg_to_rad(latitude_deg)
	var lon := deg_to_rad(longitude_deg)
	var east := cos(lat)
	return Vector3(east * sin(lon), sin(lat), east * cos(lon)).normalized()


static func spawn_direction() -> Vector3:
	return direction_from_plate(SPAWN_LATITUDE_DEG, SPAWN_LONGITUDE_DEG)


static func city_direction() -> Vector3:
	return direction_from_plate(CITY_LATITUDE_DEG, CITY_LONGITUDE_DEG)


static func active() -> bool:
	return NetworkManager != null \
		and str(NetworkManager.session_options.get("mode", "")) == MODE_ID


static func ability_slots() -> int:
	return ABILITY_SLOTS if active() else CharacterDB.ABILITY_SLOTS


static func ability_enabled(id: String) -> bool:
	var clean := id
	if id.begins_with("ck:"):
		var bits := id.split(":")
		clean = bits[2] if bits.size() >= 4 else id
	return ENABLED_ABILITIES.has(clean)


static func laser_start_stats() -> Dictionary:
	return {
		"damage": LASER_DAMAGE,
		"cooldown": LASER_COOLDOWN,
		"duration": LASER_DURATION,
		"range": LASER_RANGE,
		"knockback": LASER_KNOCKBACK,
	}


static func meteor_start_stats() -> Dictionary:
	return {
		"damage": METEOR_DAMAGE,
		"impact": METEOR_IMPACT,
		"cooldown": METEOR_COOLDOWN,
		"range": METEOR_RANGE,
		"size": 1.0,
		"radius": METEOR_RADIUS,
		"crater_radius": METEOR_CRATER_RADIUS,
		"crater_depth": METEOR_CRATER_DEPTH,
		"speed": METEOR_SPEED,
		"knockback": METEOR_KNOCKBACK,
	}


static func upgrade_stats_for(catalog_id: String) -> PackedStringArray:
	match catalog_id:
		"laser_eyes":
			return PackedStringArray(
				["damage", "cooldown", "duration", "range", "size",
					"knockback", "slots"])
		"meteor_punch":
			return PackedStringArray(
				["damage", "cooldown", "size", "range", "knockback", "slots"])
		"starfire":
			return PackedStringArray(
				["damage", "cooldown", "size", "range", "knockback", "slots"])
		"wobble":
			return PackedStringArray(["wobble"])
		"big":
			return PackedStringArray(["size"])
		_:
			return PackedStringArray()


## Stats shown on the hero sheet. Empty means every numeric stat the card has.
static func display_stats_for(catalog_id: String) -> PackedStringArray:
	if catalog_id == "starfire":
		return PackedStringArray(
			["damage", "cooldown", "size", "range", "knockback", "slots"])
	if catalog_id == "meteor_punch":
		return PackedStringArray(
			["damage", "cooldown", "size", "range", "knockback", "slots"])
	if catalog_id == "laser_eyes":
		return PackedStringArray(
			["damage", "cooldown", "duration", "range", "size",
				"knockback", "slots"])
	return PackedStringArray()


static func big_size_scale(rank: int) -> float:
	var clamped := clampi(rank, 0, BIG_SIZE_MAX_RANK)
	return BIG_SIZE_BASE * pow(BIG_SIZE_GROWTH, float(clamped))


static func upgrade_max_rank(catalog_id: String, stat_id: String) -> int:
	if catalog_id == "big" and stat_id == "size":
		return BIG_SIZE_MAX_RANK
	return 0


static func format_mul(mul: float) -> String:
	if is_equal_approx(mul, round(mul)):
		return "%.0fx" % mul
	if is_equal_approx(mul * 10.0, round(mul * 10.0)):
		return "%.1fx" % mul
	return "%.2fx" % mul


static func mod_progress_lines(catalog_id: String, level: int, ranks: Dictionary) -> PackedStringArray:
	var lines := PackedStringArray()
	var listed := upgrade_stats_for(catalog_id)
	var level_cap := 0
	for stat_id: String in listed:
		level_cap = maxi(level_cap, upgrade_max_rank(catalog_id, stat_id))
	if level_cap > 0:
		lines.append("LEVEL  //  %d / %d" % [mini(maxi(level, 0), level_cap), level_cap])
	else:
		lines.append("LEVEL  //  %d" % maxi(level, 0))
	for stat_id: String in listed:
		var rank := maxi(int(ranks.get(stat_id, 0)), 0)
		var cap := upgrade_max_rank(catalog_id, stat_id)
		var title := upgrade_stat_title(stat_id).to_upper()
		if cap > 0:
			lines.append("%s  //  %d / %d" % [title, mini(rank, cap), cap])
		else:
			lines.append("%s  //  %d" % [title, rank])
	return lines


static func upgrade_stat_title(stat_id: String) -> String:
	match stat_id:
		"damage":
			return "Damage"
		"cooldown":
			return "Cooldown"
		"duration":
			return "Firing time"
		"range":
			return "Range"
		"size":
			return "Size"
		"slots":
			return "Modifier slots"
		"knockback":
			return "Knockback"
		"wobble":
			return "Wobble"
		_:
			return stat_id.capitalize()


static func upgrade_stat_blurb(catalog_id: String, stat_id: String) -> String:
	if catalog_id == "wobble":
		return "Stronger wave. Wider spray, less damage on a tight point."
	if catalog_id == "big":
		return "Exponential size. Starts at %s and reaches %s at level %d." % [
			format_mul(big_size_scale(0)),
			format_mul(big_size_scale(BIG_SIZE_MAX_RANK)),
			BIG_SIZE_MAX_RANK,
		]
	if catalog_id == "starfire":
		match stat_id:
			"damage":
				return "Each disk hits harder."
			"cooldown":
				return "Shorter wait between disks."
			"size":
				return "Bigger disks and a wider burst."
			"range":
				return "The disks travel farther."
			"knockback":
				return "The burst throws mobs farther."
			"slots":
				return "One more modifier seat."
			_:
				return ""
	if catalog_id == "meteor_punch":
		match stat_id:
			"damage":
				return "The flying fist hits harder."
			"cooldown":
				return "Shorter wait after you land."
			"size":
				return "A thicker fist and a wider crater."
			"range":
				return "The punch carries farther before it spends out."
			"knockback":
				return "Mobs are thrown farther by the punch."
			"slots":
				return "One more modifier seat."
			_:
				return ""
	match stat_id:
		"damage":
			return "More damage each second the beam is on a target."
		"cooldown":
			return "Shorter wait between pulses."
		"duration":
			return "Each pulse stays on a little longer."
		"range":
			return "The beams reach farther."
		"size":
			return "A thicker beam and a wider cut."
		"knockback":
			return "The beam shoves mobs farther along its cut."
		"slots":
			return "One more modifier seat."
		_:
			return ""


static func is_city_destroyed(wrecked: int, total: int) -> bool:
	return total > 0 and float(wrecked) / float(total) > CITY_DESTROY_RATIO


static func destruction_ratio(wrecked: int, total: int) -> float:
	return 0.0 if total <= 0 else float(wrecked) / float(total)


static func city_density_weight(distance: float, radius := CITY_INFLUENCE_METRES) -> float:
	if radius <= 0.0 or distance >= radius:
		return 0.0
	var t := 1.0 - distance / radius
	return t * t


static func influence_radius_for_extent(extent: float) -> float:
	return maxf(extent, 0.0) + CITY_INFLUENCE_METRES


static func reserved_patch(name: String) -> bool:
	var clean := name.strip_edges()
	return clean == START_PATCH or clean == CITY_PATCH \
		or clean.begins_with(START_PATCH + " ") \
		or clean.begins_with(CITY_PATCH + " ")


static func safe_patch(_name: String) -> bool:
	return false


static func start_patch(name: String) -> bool:
	var clean := name.strip_edges()
	return clean == START_PATCH or clean.begins_with(START_PATCH + " ")


static func patch_recipe(patch_key: Variant = "", from_start := -1.0) -> Dictionary:
	var name := _recipe_name(patch_key)
	var kinds := CrawlerMobs.kinds_for(name, from_start)
	if kinds.is_empty():
		kinds = START_FAR_KINDS if start_patch(name) \
				and from_start > START_NEAR_RANGE else (
			START_NEAR_KINDS if start_patch(name) else WILD_KINDS)
	return {
		"kinds": kinds,
		"live": LIVE_AROUND,
		"agro_share": AGRO_SHARE,
		"min_range": SPAWN_MIN,
		"max_range": SPAWN_MAX,
		"health_scale": START_HEALTH_SCALE if start_patch(name) else 1.0,
	}


static func kind_cap(kind: String, level: int) -> int:
	return CrawlerMobs.kind_cap(kind, level)


static func kind_cap_fallback(kind: String, level: int) -> int:
	var base := int(KIND_CAP_BASE.get(kind, 1))
	return base + maxi(level - 1, 0) / KIND_CAP_EVERY


static func pack_limit(kinds: PackedStringArray, level: int) -> int:
	var total := 0
	for kind: String in kinds:
		total += kind_cap(kind, level)
	return maxi(total, 0)


static func flies(kind: String) -> bool:
	return kind == "ranger" or kind == "rammer"


static func flyer_ceiling(level: int) -> float:
	return CrawlerMobs.number(
		"ranger", level, "flyer_ceiling",
		FLYER_CEILING_BASE + FLYER_CEILING_PER_LEVEL * float(maxi(level - 1, 0)))


static func ranger_rank(level: int) -> int:
	return maxi(level, 1)


static func ranger_standoff_min(level: int) -> float:
	return CrawlerMobs.number("ranger", level, "standoff_min", RANGER_STANDOFF_MIN)


static func ranger_standoff_max(level: int) -> float:
	return CrawlerMobs.number(
		"ranger", level, "standoff_max",
		RANGER_STANDOFF_MAX + RANGER_STANDOFF_PER_LEVEL * float(ranger_rank(level) - 1))


static func ranger_engage_min(level: int) -> float:
	return CrawlerMobs.number("ranger", level, "engage_min", RANGER_ENGAGE_MIN)


static func ranger_engage_max(level: int) -> float:
	return CrawlerMobs.number(
		"ranger", level, "engage_max",
		RANGER_ENGAGE_MAX + RANGER_ENGAGE_PER_LEVEL * float(ranger_rank(level) - 1))


static func ranger_match_lag(level: int) -> float:
	return RANGER_MATCH_LAG + RANGER_MATCH_LAG_PER_LEVEL * float(ranger_rank(level) - 1)


static func ranger_match_floor(level: int) -> float:
	return RANGER_MATCH_FLOOR + RANGER_MATCH_FLOOR_PER_LEVEL * float(ranger_rank(level) - 1)


static func ranger_match_lock(level: int) -> float:
	return RANGER_MATCH_LOCK + RANGER_MATCH_LOCK_PER_LEVEL * float(ranger_rank(level) - 1)


static func ranger_match_slack(player_speed: float, level: int) -> float:
	var extra := float(ranger_rank(level) - 1)
	return maxf(maxf(player_speed, 0.0) * (0.07 + 0.025 * extra), 7.0 + 5.0 * extra)


static func ranger_shot_speed(_player_speed: float, level: int) -> float:
	var extra := float(ranger_rank(level) - 1)
	return CrawlerMobs.number(
		"ranger", level, "shot_speed",
		RANGER_SHOT_SPEED + RANGER_SHOT_SPEED_PER_LEVEL * extra)


static func ranger_shot_ball(level: int) -> float:
	return CrawlerMobs.number(
		"ranger", level, "shot_ball",
		maxf(RANGER_SHOT_BALL + RANGER_SHOT_BALL_PER_LEVEL * float(
			ranger_rank(level) - 1), 0.16))


static func ranger_shot_hit(level: int) -> float:
	return CrawlerMobs.number(
		"ranger", level, "shot_hit",
		maxf(RANGER_SHOT_HIT + RANGER_SHOT_HIT_PER_LEVEL * float(
			ranger_rank(level) - 1), 0.62))


static func ranger_shot_aoe(level: int) -> float:
	return ranger_shot_aoe_from_hit(ranger_shot_hit(level))


static func ranger_shot_aoe_from_hit(hit: float) -> float:
	return maxf(RANGER_SHOT_AOE, maxf(hit, 0.0) * RANGER_SHOT_AOE_SHARE)


static func rammer_spawn_range(speed: float) -> float:
	return spawn_ahead_range(speed).x


static func rammer_top_speed(player_speed: float, level: int) -> float:
	var extra := float(maxi(level, 1) - 1)
	var base := CrawlerMobs.number(
		"rammer", level, "ram_top", RAMMER_TOP + 4.0 * extra)
	return base + maxf(player_speed, 0.0) * RAMMER_TOP_SHARE


static func rammer_launch_point(from: Vector3, look: Vector3, up: Vector3,
		speed: float) -> Vector3:
	var home := spawn_ahead_point(from, look, up, rammer_spawn_range(speed))
	if not home.is_finite():
		return from
	var rise := _spawn_rise(up, from)
	var ahead := look if look.is_finite() else Vector3.ZERO
	var lift := clampf(RAMMER_LIFT + ahead.dot(rise) * 5.0, 1.1, 7.5)
	return home - rise * 1.6 + rise * lift


static func rhino_running(player_speed: float) -> bool:
	return maxf(player_speed, 0.0) >= RHINO_RUN_SPEED


static func rhino_chase_speed(player_speed: float, level: int, urgent := false) -> float:
	var extra := float(maxi(level, 1) - 1)
	var share := RHINO_MATCH_SHARE + 0.06 * extra
	var pad := RHINO_MATCH_PAD + 2.0 * extra
	if urgent:
		share += 0.10
		pad += 5.0
	return maxf(player_speed, 0.0) * share + pad


static func ground_intercept(from: Vector3, target: Vector3, velocity: Vector3,
		speed: float, up: Vector3, max_time := RHINO_INTERCEPT_MAX) -> Vector3:
	if not from.is_finite() or not target.is_finite():
		return target
	var rise := up.normalized() if up.length_squared() > 0.0001 else Vector3.UP
	var motion := velocity if velocity.is_finite() else Vector3.ZERO
	motion -= rise * motion.dot(rise)
	var close := maxf(speed, 1.0)
	var flight := from.distance_to(target) / close
	for _step in 4:
		var guess := target + motion * clampf(flight, 0.0, max_time)
		var along := guess - from
		along -= rise * along.dot(rise)
		flight = along.length() / close
	return target + motion * clampf(flight, 0.0, max_time)


static func ranger_chase_speed(player_speed: float, level: int, urgent := false) -> float:
	var extra := float(ranger_rank(level) - 1)
	var share := RANGER_MATCH_SHARE + RANGER_MATCH_SHARE_PER_LEVEL * extra
	var pad := RANGER_MATCH_PAD + RANGER_MATCH_PAD_PER_LEVEL * extra
	if urgent:
		share += 0.10
		pad += 8.0
	return maxf(player_speed, 0.0) * share + pad


static func spawn_ahead_range(speed: float) -> Vector2:
	var floor_r := maxf(SPAWN_MIN, AGRO_RANGE + SPAWN_AGRO_PAD)
	var near := floor_r + maxf(speed, 0.0) * SPAWN_LEAD
	near = minf(near, SPAWN_MAX - SPAWN_BAND * 0.45)
	var far := minf(near + SPAWN_BAND, SPAWN_MAX)
	return Vector2(near, maxf(far, near + 8.0))


static func spawn_travel(velocity: Vector3, look: Vector3, up := Vector3.ZERO) -> Vector3:
	var rise := _spawn_rise(up, Vector3.ZERO)
	var motion := velocity if velocity.is_finite() else Vector3.ZERO
	motion -= rise * motion.dot(rise)
	if motion.length() >= SPAWN_TRAVEL_MIN:
		return motion.normalized()
	var facing := look if look.is_finite() else Vector3.ZERO
	facing -= rise * facing.dot(rise)
	if facing.length_squared() > 0.0001:
		return facing.normalized()
	return Vector3.ZERO


static func uses_lead_pack(player_speed: float) -> bool:
	return maxf(player_speed, 0.0) >= SPAWN_LEAD_SPEED


static func spawn_lead_count(player_speed: float) -> int:
	if not uses_lead_pack(player_speed):
		return 0
	var share := clampf((maxf(player_speed, 0.0) - SPAWN_LEAD_SPEED) / 40.0, 0.0, 1.0)
	return clampi(2 + int(round(float(SPAWN_LEAD_PACK - 2) * share)), 2, SPAWN_LEAD_PACK)


static func spawn_going(velocity: Vector3, up := Vector3.ZERO) -> Vector3:
	return spawn_travel(velocity, Vector3.ZERO, up)


static func spawn_ring_range() -> Vector2:
	return spawn_ahead_range(0.0)


static func spawn_lead_range(speed: float) -> Vector2:
	var ring := spawn_ring_range()
	var ahead := spawn_ahead_range(speed)
	var near := maxf(ring.y + 8.0, ahead.x)
	var far := minf(maxf(ahead.y, near + 16.0), WILD_STREAM_IN - 24.0)
	return Vector2(near, maxf(far, near + 8.0))


static func spawn_ring_point(from: Vector3, up: Vector3, yaw: float,
		reach: float) -> Vector3:
	if not from.is_finite():
		return from
	var rise := _spawn_rise(up, from)
	var east := rise.cross(Vector3.RIGHT)
	if east.length_squared() < 0.01:
		east = rise.cross(Vector3.FORWARD)
	if east.length_squared() < 0.0001:
		return from + rise * 1.6
	east = east.normalized()
	var north := rise.cross(east).normalized()
	return from + (east * cos(yaw) + north * sin(yaw)) * maxf(reach, 0.0) \
		+ rise * 1.6


static func spawn_too_close(at: Vector3, player_at: Vector3, velocity: Vector3,
		up := Vector3.ZERO) -> bool:
	if not at.is_finite() or not player_at.is_finite():
		return true
	var rise := _spawn_rise(up, player_at)
	var speed := velocity.length() if velocity.is_finite() else 0.0
	var clear := spawn_player_clear(speed)
	return _flat_span(at, player_at, rise) < clear \
		or at.distance_to(player_at) < clear


static func spawn_ahead_point(from: Vector3, travel: Vector3, up: Vector3,
		reach: float) -> Vector3:
	if not from.is_finite():
		return from
	var rise := _spawn_rise(up, from)
	var flat := travel if travel.is_finite() else Vector3.ZERO
	flat -= rise * flat.dot(rise)
	if flat.length_squared() < 0.0001:
		return from + rise * 1.6
	return from + flat.normalized() * maxf(reach, 0.0) + rise * 1.6


static func spawn_in_travel_cone(at: Vector3, player_at: Vector3, travel: Vector3,
		up := Vector3.ZERO, half_angle := SPAWN_CONE) -> bool:
	if not at.is_finite() or not player_at.is_finite():
		return false
	if not travel.is_finite() or travel.length_squared() < 0.0001:
		return true
	var rise := _spawn_rise(up, player_at)
	var delta := at - player_at
	delta -= rise * delta.dot(rise)
	if delta.length_squared() < 0.0001:
		return false
	var heading := travel - rise * travel.dot(rise)
	if heading.length_squared() < 0.0001:
		return true
	return delta.normalized().dot(heading.normalized()) >= cos(half_angle)


static func spawn_player_clear(speed: float) -> float:
	return spawn_ahead_range(speed).x * 0.85


static func spawn_blocked_by_player(at: Vector3, player_at: Vector3,
		velocity: Vector3, up := Vector3.ZERO, look := Vector3.ZERO) -> bool:
	if spawn_too_close(at, player_at, velocity, up):
		return true
	var rise := _spawn_rise(up, player_at)
	var travel := spawn_travel(velocity, look, rise)
	if travel.length_squared() < 0.0001:
		return false
	return not spawn_in_travel_cone(at, player_at, travel, rise)


static func spawn_blocked_by_kill(at: Vector3, kill_at: Vector3, age: float) -> bool:
	if not at.is_finite() or not kill_at.is_finite():
		return true
	return age < KILL_COOLDOWN and at.distance_to(kill_at) < KILL_RADIUS


static func _flat_span(a: Vector3, b: Vector3, up: Vector3) -> float:
	var delta := a - b
	return (delta - up * delta.dot(up)).length()


static func _spawn_rise(up: Vector3, at: Vector3) -> Vector3:
	if up.length_squared() > 0.0001:
		return up.normalized()
	if at.length_squared() > 1.0:
		return at.normalized()
	return Vector3.UP


static func spawn_is_agro(_serial: int) -> bool:
	return false


static func should_agro(distance: float) -> bool:
	return distance <= AGRO_RANGE


static func should_deagro(distance: float) -> bool:
	return distance > DEAGRO_RANGE


static func should_despawn_idle(ever_chased: bool, chasing: bool, idle_seconds: float) -> bool:
	return ever_chased and not chasing and idle_seconds >= IDLE_DESPAWN


static func patch_level(from_dir: Vector3, patch_dir: Vector3) -> int:
	var a := from_dir.normalized() if from_dir.length_squared() > 0.0001 else Vector3.UP
	var b := patch_dir.normalized() if patch_dir.length_squared() > 0.0001 else Vector3.UP
	return 1 + int(a.angle_to(b) / 0.22)


## Field difficulty for a tile. Geographic only: player level and siege
## clears do not change it, and a pack already on the tile keeps this rank.
static func field_mob_level(from_dir: Vector3, patch_dir: Vector3) -> int:
	return maxi(patch_level(from_dir, patch_dir), 1)


static func patch_mob_count(from_dir: Vector3, patch_dir: Vector3) -> int:
	return pack_limit(WILD_KINDS, patch_level(from_dir, patch_dir))


static func wild_kind(patch_key: Variant, slot: int, from_start := -1.0) -> String:
	var kinds := _recipe_kinds(patch_key, from_start)
	if kinds.is_empty():
		return "ranger"
	return kinds[posmod(slot, kinds.size())]


static func _recipe_name(patch_key: Variant) -> String:
	return str(patch_key) if typeof(patch_key) == TYPE_STRING else ""


static func _recipe_kinds(patch_key: Variant, from_start := -1.0) -> PackedStringArray:
	var listed: Variant = patch_recipe(patch_key, from_start).get("kinds", WILD_KINDS)
	if listed is PackedStringArray:
		return listed
	var packed := PackedStringArray()
	if listed is Array:
		for item: Variant in listed:
			packed.append(str(item))
	return packed if not packed.is_empty() else WILD_KINDS


static func threat_speed(level: int) -> float:
	return pow(THREAT_SPEED, maxi(level, 0))


static func threat_health(level: int) -> float:
	return pow(THREAT_HEALTH, maxi(level, 0))


static func threat_fire(level: int) -> float:
	return pow(THREAT_FIRE, maxi(level, 0))


static func threat_damage(level: int) -> float:
	return pow(THREAT_DAMAGE, maxi(level, 0))


## Launch velocity that intercepts a moving body after gravity has pulled the
## shot back down. Iterated because the flight time depends on the aim point.
static func lead_launch(from: Vector3, target: Vector3, velocity: Vector3,
		speed: float, gravity: float, up: Vector3) -> Vector3:
	if speed <= 0.001 or not from.is_finite() or not target.is_finite():
		return Vector3.ZERO
	var motion := velocity if velocity.is_finite() else Vector3.ZERO
	var lift := up.normalized() if up.length_squared() > 0.0001 else Vector3.UP
	var at := target
	var flight := from.distance_to(at) / speed
	for _step in 5:
		at = target + motion * flight
		var along := at - from + lift * 0.5 * gravity * flight * flight
		if along.is_zero_approx():
			break
		flight = along.length() / speed
	var aim := at - from + lift * 0.5 * gravity * flight * flight
	if aim.is_zero_approx():
		return Vector3.ZERO
	return aim.normalized() * speed
