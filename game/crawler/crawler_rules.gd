class_name CrawlerRules
extends RefCounted

## Session rules that only apply while the hosted mode is crawler or sandbox.
##
## Crawler is still a string id on [member NetworkManager.session_options]. This
## file is the one place gameplay asks that question, so hero UI, the HUD, and
## the starter kit stay in agreement. Sandbox hosts the same loop, with a full
## city store, story-style tilde patches and names, and four Tab-menu cheats.
## Invincible and fast (full speed, quicker acceleration, infinite flight)
## start on.

const MODE_ID := "crawler"
const SANDBOX_ID := "sandbox"
const CHEAT_MOBS := "sandbox_no_mobs"
const CHEAT_INVINCIBLE := "sandbox_invincible"
const CHEAT_FAST := "sandbox_fast"
const CHEAT_GOLD := "sandbox_infinite_gold"
const SANDBOX_GOLD := 999999
const SANDBOX_FAST_ACCEL := 2.5
const ABILITY_SLOTS := 3
const ABILITY_SLOTS_MAX := 4
const ENABLED_ABILITIES: PackedStringArray = [
	"laser_eyes", "kame", "nausicaa", "lightning", "meteor_punch", "hero_punch",
	"starfire", "light_bolt", "icicle", "teleport", "fus", "nuke", "mini_nuke", "wall", "roar", "toxic_blast",
	"charming_aura", "freeze_blast", "static_field", "toxic_field",
	"freeze_field", "healing_field", "overdrive",
]
const LASER_DAMAGE := 50.0
const LASER_COOLDOWN := 0.5
const LASER_DURATION := 0.4
const LASER_RANGE := 60.0
const LASER_RANGE_PER_RANK := 15.0
const LASER_KNOCKBACK := 8.0
const LASER_KNOCKBACK_PER_RANK := 2.5
const LASER_SLOTS := 3
const KAME_DAMAGE := 85.0
const KAME_COOLDOWN := 2.2
const KAME_DURATION := 2.2
const KAME_RANGE := 240.0
const KAME_RANGE_PER_RANK := 48.0
const KAME_RADIUS := 0.72
const KAME_BEAM_WIDTH := 1.2
const KAME_DAMAGE_HZ := 16.0
const KAME_LOOK_SCALE := 0.38
const KAME_KNOCKBACK := 12.0
const KAME_KNOCKBACK_PER_RANK := 3.5
const KAME_DAMAGE_PER_RANK := 18.0
const KAME_COOLDOWN_PER_RANK := 0.15
const KAME_COOLDOWN_MIN := 1.1
const KAME_DURATION_PER_RANK := 0.20
const KAME_SIZE_PER_RANK := 0.10
const KAME_SLOTS := 3
const NAUSICAA_DAMAGE := 95.0
const NAUSICAA_PLAYER_DAMAGE := 10.0
const NAUSICAA_COOLDOWN := 6.0
const NAUSICAA_DURATION := 0.75
const NAUSICAA_RANGE := 18.0
const NAUSICAA_RANGE_PER_RANK := 3.5
const NAUSICAA_RADIUS := 5.0
const NAUSICAA_BEAM_WIDTH := 1.0
const NAUSICAA_DELAY := 1.0
const NAUSICAA_PAINT_RADIUS := 0.85
const NAUSICAA_PAINT_SPACING := 1.25
const NAUSICAA_CHAIN_INTERVAL := 0.09
const NAUSICAA_CRATER_RADIUS := 2.0
const NAUSICAA_CRATER_DEPTH := 0.55
const NAUSICAA_KNOCKBACK := 14.0
const NAUSICAA_KNOCKBACK_PER_RANK := 3.0
const NAUSICAA_LIFT := 6.0
const NAUSICAA_EXPLOSION := 0.5
const NAUSICAA_DAMAGE_PER_RANK := 18.0
const NAUSICAA_COOLDOWN_PER_RANK := 0.40
const NAUSICAA_COOLDOWN_MIN := 3.4
const NAUSICAA_DURATION_PER_RANK := 0.08
const NAUSICAA_SIZE_PER_RANK := 0.10
const NAUSICAA_SLOTS := 3
const LIGHTNING_DAMAGE := 42.0
const LIGHTNING_COOLDOWN := 0.55
const LIGHTNING_DURATION := 0.35
const LIGHTNING_RANGE := 48.0
const LIGHTNING_RANGE_PER_RANK := 12.0
const LIGHTNING_KNOCKBACK := 6.0
const LIGHTNING_KNOCKBACK_PER_RANK := 2.0
const LIGHTNING_RADIUS := 0.32
const LIGHTNING_BEAM_WIDTH := 0.7
const LIGHTNING_DAMAGE_PER_RANK := 10.0
const LIGHTNING_COOLDOWN_PER_RANK := 0.05
const LIGHTNING_COOLDOWN_MIN := 0.22
const LIGHTNING_DURATION_PER_RANK := 0.05
const LIGHTNING_SIZE_PER_RANK := 0.10
const LIGHTNING_ARCS := 1
const LIGHTNING_ARCS_PER_RANK := 1
const LIGHTNING_ARC_RANGE := 9.0
const LIGHTNING_SHOCK := 0.0
const LIGHTNING_SHOCK_PER_RANK := 1.8
const LIGHTNING_SLOTS := 3
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
const LIGHT_BOLT_DAMAGE := 16.0
const LIGHT_BOLT_IMPACT := 22.0
const LIGHT_BOLT_COOLDOWN := 0.10
const LIGHT_BOLT_RANGE := 48.0
const LIGHT_BOLT_SPEED := 70.0
const LIGHT_BOLT_RADIUS := 0.85
const LIGHT_BOLT_PROJECTILE_RADIUS := 0.10
const LIGHT_BOLT_CRATER_RADIUS := 0.45
const LIGHT_BOLT_CRATER_DEPTH := 0.10
const LIGHT_BOLT_KNOCKBACK := 3.5
const LIGHT_BOLT_SLOTS := 3
const LIGHT_BOLT_DAMAGE_PER_RANK := 4.0
const LIGHT_BOLT_COOLDOWN_PER_RANK := 0.006
const LIGHT_BOLT_COOLDOWN_MIN := 0.05
const LIGHT_BOLT_RANGE_PER_RANK := 8.0
const LIGHT_BOLT_SPEED_PER_RANK := 12.0
const LIGHT_BOLT_SIZE_PER_RANK := 0.10
const LIGHT_BOLT_KNOCKBACK_PER_RANK := 0.8
const ICICLE_DAMAGE := 72.0
const ICICLE_COLD_DAMAGE := 8.0
const ICICLE_COLD := 1.6
const ICICLE_COOLDOWN := 0.48
const ICICLE_RANGE := 44.0
const ICICLE_SPEED := 82.0
const ICICLE_RADIUS := 2.2
const ICICLE_PROJECTILE_RADIUS := 0.16
const ICICLE_KNOCKBACK := 6.0
const ICICLE_SLOTS := 3
const ICICLE_DAMAGE_PER_RANK := 16.0
const ICICLE_COLD_DAMAGE_PER_RANK := 3.0
const ICICLE_COLD_PER_RANK := 0.35
const ICICLE_COOLDOWN_PER_RANK := 0.03
const ICICLE_COOLDOWN_MIN := 0.22
const ICICLE_RANGE_PER_RANK := 8.0
const ICICLE_SPEED_PER_RANK := 12.0
const ICICLE_RADIUS_COLD_PER_RANK := 0.45
const ICICLE_SIZE_PER_RANK := 0.10
const ICICLE_KNOCKBACK_PER_RANK := 1.4
const TELEPORT_COOLDOWN := 4.5
const TELEPORT_COOLDOWN_PER_RANK := 0.35
const TELEPORT_COOLDOWN_MIN := 2.0
const TELEPORT_RANGE := 42.0
const TELEPORT_RANGE_PER_RANK := 8.0
const TELEPORT_SPEED := 36.0
const TELEPORT_SPEED_PER_RANK := 6.0
const TELEPORT_RADIUS := 1.2
const TELEPORT_PROJECTILE_RADIUS := 0.22
const TELEPORT_SIZE_PER_RANK := 0.10
const TELEPORT_GRAVITY := 28.0
const TELEPORT_LOFT := 0.38
const TELEPORT_SLOTS := 3
const TELEPORT_SWAP_MAX := 1
const FUS_DAMAGE := 8.0
const FUS_COOLDOWN := 3.2
const FUS_COOLDOWN_PER_RANK := 0.18
const FUS_COOLDOWN_MIN := 1.4
const FUS_RANGE := 20.0
const FUS_RANGE_PER_RANK := 3.5
const FUS_SPEED := 42.0
const FUS_SPEED_PER_RANK := 6.0
const FUS_RADIUS := 3.8
const FUS_PROJECTILE_RADIUS := 3.8
const FUS_KNOCKBACK := 72.0
const FUS_SLOTS := 3
const FUS_DAMAGE_PER_RANK := 2.0
const FUS_SIZE_PER_RANK := 0.12
const FUS_KNOCKBACK_PER_RANK := 12.0
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
const HERO_PUNCH_DAMAGE := 40.0
const HERO_PUNCH_COOLDOWN := 0.40
const HERO_PUNCH_COOLDOWN_PER_RANK := 0.03
const HERO_PUNCH_COOLDOWN_MIN := 0.22
const HERO_PUNCH_RANGE := 3.8
const HERO_PUNCH_RANGE_PER_RANK := 0.45
const HERO_PUNCH_RADIUS := 1.15
const HERO_PUNCH_KNOCKBACK := 8.0
const HERO_PUNCH_KNOCKBACK_PER_RANK := 2.0
const HERO_PUNCH_DAMAGE_PER_RANK := 8.0
const HERO_PUNCH_SIZE_PER_RANK := 0.10
const HERO_PUNCH_SLOTS := 3
const OVERDRIVE_BOOST := 0.25
const OVERDRIVE_BOOST_PER_RANK := 0.08
const OVERDRIVE_DURATION := 8.0
const OVERDRIVE_DURATION_PER_RANK := 1.5
const OVERDRIVE_COOLDOWN := 14.0
const OVERDRIVE_COOLDOWN_PER_RANK := 1.2
const OVERDRIVE_COOLDOWN_MIN := 6.0
const OVERDRIVE_SLOTS := 1
const OVERDRIVE_BOOST_STATS: PackedStringArray = [
	"damage", "impact", "player_damage", "range", "radius", "size",
	"knockback", "duration", "beam_width", "projectile_radius",
	"crater_radius", "crater_depth", "paint_radius", "wall_width",
	"wall_height", "wall_thickness", "lift", "impact_radius",
	"shock", "toxic", "freeze", "cold", "cold_damage",
]
const ROAR_DAMAGE := 18.0
const ROAR_TOXIC_DAMAGE := 8.0
const ROAR_CHARM_DAMAGE := 0.0
const ROAR_FREEZE_DAMAGE := 0.0
const ROAR_RADIUS := 14.0
const ROAR_DURATION := 4.0
const ROAR_KNOCKBACK := 16.0
const ROAR_OTHER_KNOCKBACK := 0.0
const ROAR_COOLDOWN := 5.0
const ROAR_SLOTS := 3
const ROAR_DAMAGE_PER_RANK := 4.0
const ROAR_RADIUS_PER_RANK := 2.0
const ROAR_DURATION_PER_RANK := 0.45
const ROAR_KNOCKBACK_PER_RANK := 3.0
const ROAR_WINDUP := 0.35
const ROAR_EXPAND := 0.75
const ROAR_ANIMATION := 1.15
const FIELD_RADIUS := 7.0
const FIELD_DURATION := 6.0
const FIELD_FADE := 2.4
const FIELD_COOLDOWN := 8.0
const FIELD_CAST := 1.0
const FIELD_CAST_PER_RANK := 0.12
const FIELD_CAST_MIN := 0.20
const FIELD_CAST_BREAK := 2.5
const FIELD_ANIMATION := 0.9
const FIELD_SLOTS := 3
const FIELD_STATIC_DAMAGE := 16.0
const FIELD_TOXIC_DAMAGE := 5.0
const FIELD_FREEZE_DAMAGE := 0.0
const FIELD_SHOCK := 2.0
const FIELD_SHOCK_PER_RANK := 1.2
const FIELD_TOXIC := 4.0
const FIELD_TOXIC_PER_RANK := 0.8
const FIELD_FREEZE := 72.0
const FIELD_FREEZE_PER_RANK := 6.0
const FIELD_FREEZE_MAX := 92.0
const FIELD_HEAL := 8.0
const FIELD_HEAL_PER_RANK := 2.0
const FIELD_DAMAGE_PER_RANK := 4.0
const FIELD_COOLDOWN_PER_RANK := 0.45
const FIELD_COOLDOWN_MIN := 3.5
const FIELD_RADIUS_PER_RANK := 1.2
const FIELD_DURATION_PER_RANK := 0.8
const FIELD_SIZE_PER_RANK := 0.10
const ELEM_TOXIC_DPS := 8.0
const ELEM_TOXIC_DPS_PER_RANK := 4.0
const ELEM_TOXIC_HOLD := 4.0
const ELEM_TOXIC_HOLD_PER_RANK := 0.8
const ELEM_SHOCK_HOLD := 2.0
const ELEM_SHOCK_HOLD_PER_RANK := 1.2
const ELEM_CHARM_HOLD := 4.0
const ELEM_CHARM_HOLD_PER_RANK := 0.45
const ELEM_ICE_HOLD := 2.0
const ELEM_ICE_HOLD_PER_RANK := 0.45
const ELEM_ICE_FIELD := 12.0
const ELEM_ICE_FIELD_PER_RANK := 6.0
const ELEM_MAX_RANK := 8
const WALL_COOLDOWN := 5.0
const WALL_COOLDOWN_PER_RANK := 0.35
const WALL_COOLDOWN_MIN := 2.4
const WALL_RANGE := 4.0
const WALL_RANGE_PER_RANK := 0.8
const WALL_DURATION := 7.0
const WALL_DURATION_PER_RANK := 0.8
const WALL_WIDTH := 8.0
const WALL_HEIGHT := 4.0
const WALL_THICKNESS := 0.35
const WALL_FADE := 4.0
const WALL_SIZE_PER_RANK := 0.12
const WALL_SLOTS := 3
const WALL_PROJECT_SPEED := 3.5
const WALL_FIRE_DAMAGE := 14.0
const WALL_HOUSE_MAX := 1
const BIG_SIZE_MAX_RANK := 10
const BIG_SIZE_BASE := 1.22
const BIG_SIZE_GROWTH := 1.26
const TYPE_BEAM := "beam"
const TYPE_SHOCKWAVE := "shockwave"
const TYPE_PROJECTILE := "projectile"
const TYPE_LIMITED := "limited"
const TYPE_MISC := "misc"
const TYPE_FIELD := "field"
const NUKE_AMMO := 3
const MINI_NUKE_DAMAGE := 8000.0
const MINI_NUKE_IMPACT := 6000.0
const MINI_NUKE_PLAYER_DAMAGE := 36.0
const MINI_NUKE_SPEED := 130.0
const MINI_NUKE_RANGE := 300.0
const MINI_NUKE_RADIUS := 38.0
const MINI_NUKE_COOLDOWN := 4.5
const MINI_NUKE_PROJECTILE_RADIUS := 0.55
const MINI_NUKE_CRATER_RADIUS := 24.0
const MINI_NUKE_CRATER_DEPTH := 7.0
const MINI_NUKE_CRATER_WARP := 0.3
const MINI_NUKE_KNOCKBACK := 32.0
const MINI_NUKE_LIFT := 12.0
const MINI_NUKE_SELF_LAUNCH := 28.0
const MINI_NUKE_EXPLOSION := 0.85
const MINI_NUKE_AMMO := 5
const MINI_NUKE_SLOTS := 3
const MINI_NUKE_DAMAGE_PER_RANK := 1400.0
const MINI_NUKE_COOLDOWN_PER_RANK := 0.25
const MINI_NUKE_COOLDOWN_MIN := 2.0
const MINI_NUKE_RANGE_PER_RANK := 24.0
const MINI_NUKE_SIZE_PER_RANK := 0.12
const MINI_NUKE_KNOCKBACK_PER_RANK := 5.0
const CLIP_BASE_MUL := 2
const CLIP_MAX_RANK := 2
const MULTI_SHOTS_BASE := 2
const MULTI_SHOTS_MAX := 5
const MULTI_MAX_RANK := 3
const MULTI_BEAM_YAW := 45.0
const MULTI_SPLIT_TRAVEL := 1.6
const MULTI_ECHO_GAP := 1.0
const MULTI_WALL_GAP := 0.45
const MULTI_PUNCH_GAP := 0.36
const REACH_RANGE_MUL := 1.28
const REACH_RANGE_PER_RANK := 0.12
const REACH_MAX_RANK := 8
const REACH_FAR_CAST := 2.0
const REACH_FAR_CAST_PER_RANK := 0.6
const BOUNCE_BASE := 1
const BOUNCE_MAX := 5
const BOUNCE_MAX_RANK := 4
const HOMING_STEER_BASE := 4.5
const HOMING_STEER_PER_RANK := 1.5
const HOMING_RANGE_BASE := 8.0
const HOMING_RANGE_PER_RANK := 3.0
const HOMING_MAX_RANK := 6
const BUBBLE_DAMAGE := 12.0
const BUBBLE_DAMAGE_PER_RANK := 5.0
const BUBBLE_SIZE := 0.28
const BUBBLE_SIZE_PER_RANK := 0.07
const BUBBLE_LINGER := 2.4
const BUBBLE_LINGER_PER_RANK := 0.45
const BUBBLE_HOMING_PER_RANK := 2.6
const BUBBLE_POP_PER_RANK := 1.2
const BUBBLE_SPEED := 3.8
const BUBBLE_SPEED_PER_RANK := 0.9
const MISSILE_HAT_COUNT := 3
const MISSILE_HAT_EXTRA_PER_RANK := 2
const MISSILE_HAT_INTERVAL := 2.5
const MISSILE_HAT_INTERVAL_SHRINK := 0.22
const MISSILE_HAT_DAMAGE := 14.0
const MISSILE_HAT_DAMAGE_PER_RANK := 0.25
const MISSILE_HAT_RANGE := 24.0
const MISSILE_HAT_SPEED := 16.0
const MISSILE_HAT_SIZE := 0.14
const MISSILE_HAT_LINGER := 3.6
const MISSILE_HAT_STEER := 11.0
const MINE_HAT_INTERVAL := 3.2
const MINE_HAT_INTERVAL_SHRINK := 0.18
const MINE_HAT_FUSE := 1.0
const MINE_HAT_DAMAGE := 22.0
const MINE_HAT_DAMAGE_PER_RANK := 0.28
const MINE_HAT_RADIUS := 3.4
const MINE_HAT_RADIUS_PER_RANK := 0.35
const MINE_HAT_SIZE := 0.22
const VAMPIRE_STEAL := 0.08
const VAMPIRE_STEAL_PER_RANK := 0.04
const PHASE_CHANCE := 0.25
const PHASE_CHANCE_PER_RANK := 0.10
const PHASE_CHANCE_MAX := 0.75
const JUKE_HAT_DAMAGE := 16.0
const JUKE_HAT_DAMAGE_PER_RANK := 0.30
const JUKE_HAT_RADIUS := 1.15
const FOOL_CAPE_MIN := 5.0
const FOOL_CAPE_LIKELY := 20.0
const FOOL_CAPE_MAX := 2500.0
const FOOL_CAPE_CORE_CHANCE := 0.88
const FOOL_CAPE_TAIL_POWER := 14.0
const FOOL_CAPE_TRIES := 28
const FOOL_CAPE_LOCK := 0.35
const BUBBLE_BEAM_SPACING := 4.0
const BUBBLE_BEAM_ALONG_MIN := 3
const BUBBLE_BEAM_ALONG_MAX := 6
const BUBBLE_SHOCKWAVE_COUNT := 8
const BUBBLE_BLAST_COUNT := 14
const BUBBLE_TRAIL_SPACING := 1.25
const BUBBLE_FIELD_COUNT := 3
const BUBBLE_FIELD_INTERVAL := 0.42
const BUBBLE_UPGRADE_MAX := 8
const BUBBLE_SPREADER_MAX := 1
const LINGER_SECONDS := 1.45
const LINGER_SECONDS_PER_RANK := 0.35
const LINGER_BEAM_MUL := 0.62
const LINGER_RADIUS := 1.35
const LINGER_DAMAGE := 8.0
const LINGER_SLOW_PER_RANK := 12.0
const LINGER_SLOW_MAX := 72.0
const LINGER_BEAM_SPACING := 2.0
const LINGER_SHOCK_COUNT := 6
const LINGER_BLAST_COUNT := 7
const LINGER_TRAIL_SPACING := 1.55
const LINGER_FIELD_COUNT := 2
const LINGER_BUBBLE_BONUS := 0.8
const LINGER_BUBBLE_BONUS_PER_RANK := 0.28
const LINGER_UPGRADE_MAX := 8
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
const CITY_CRESCENT_SITE_ID := "city_crescent"
const CITY_CRESCENT_TITLE := "Crescent Market"
const CITY_LEE_SITE_ID := "city_lee"
const CITY_LEE_TITLE := "Lee Reach"
const CITY_OUTPOST_METRES := 750.0
const CITY_MAP_DELAY := 2.8
const CRESCENT_VILLAGE := "res://assets/runtime/environment/crescent_market_village.glb"
const START_ENTER_RADIUS := 100.0
const TOWER_PATCH := "Far Beacon 4"
const CASTLE_PATCH := "Long Shore 4"
const GOBLIN_KINDS: PackedStringArray = ["gruk", "nix", "vex"]
const GOBLIN_GARRISON := 64
const GOBLIN_INTERIOR := 28
const GOBLIN_INNER_MIN := 12.0
const GOBLIN_INNER_MAX := 46.0
const GOBLIN_OUTER_MIN := 62.0
const GOBLIN_OUTER_MAX := 165.0
const GOBLIN_STANDOFF := 20.0
const GOBLIN_MORTAR_SPEED := 16.0
const GOBLIN_GOLDEN := 2.399963229728653
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
const DEMON_KINDS: PackedStringArray = ["gloam", "vesper", "threnody"]
## Local keep around Stormwatch and Meridian Tower. The Voronoi cells stay
## neighbourhood-scale so Tide Margin 4 keeps its name; demons only field
## inside this ring, not across the whole castle or office tile.
const DEMON_SITE_RANGE := 380.0
const START_NEAR_RANGE := 80.0
const START_HEALTH_SCALE := 0.1
const LIVE_AROUND := 28
const KIND_CAP_BASE := {
	"ranger": 11,
	"rhino": 9,
	"rammer": 9,
	"rift_hulk": 1,
	"gloam": 12,
	"vesper": 5,
	"threnody": 1,
}
const GLOAM_BITE_REACH := 1.9
const GLOAM_BITE_SECONDS := 0.55
const GLOAM_FLEE_GAP := 14.0
const GLOAM_AIR_MATCH := 1.05
const GLOAM_LAND_GAP := 8.5
const GLOAM_FLOCK := 4
const VESPER_STANDOFF_MIN := 22.0
const VESPER_STANDOFF_MAX := 38.0
const VESPER_ENGAGE_MIN := 18.0
const VESPER_ENGAGE_MAX := 48.0
const VESPER_CHARGE := 1.15
const VESPER_FIRE := 1.4
const VESPER_BEAM_RADIUS := 0.55
const THRENODY_STANDOFF_MIN := 50.0
const THRENODY_STANDOFF_MAX := 70.0
const THRENODY_LIFT := 10.0
const THRENODY_PERCEPTION := 160.0
const THRENODY_COLUMN_RADIUS := 7.5
const THRENODY_COLUMN_HEIGHT := 28.0
const THRENODY_COLUMN_DURATION := 6.0
const THRENODY_COLUMN_CAP := 3
const THRENODY_FIRE := 4.5
const THRENODY_LOOP_X := 36.0
const THRENODY_LOOP_Z := 22.0
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
const MOB_LOD_COLD := 0
const MOB_LOD_WARM := 1
const MOB_LOD_HOT := 2
const MOB_LOD_HOT_RANGE := 72.0
const MOB_LOD_WARM_RANGE := 160.0
const MOB_THINK_BUDGET := 14
const MOB_ATTACK_BUDGET := 3
const MOB_SPAWN_BUILD := 2
const MOB_SPAWN_QUEUE := 48
const MOB_COLD_STRIDE := 8
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


## Neon Fjord is the opening destination: tilde can name it from the first
## frame, and the spawn reveal points the player at it before tilde is needed.
## Spawn, monuments, and later cities wait until the player walks in.
static func starts_visible(site_id: String) -> bool:
	return site_id == CITY_SITE_ID


static func later_city_ids() -> PackedStringArray:
	var ids: PackedStringArray = []
	ids.append(CITY_CRESCENT_SITE_ID)
	ids.append(CITY_LEE_SITE_ID)
	return ids


static func is_later_city(site_id: String) -> bool:
	return later_city_ids().has(site_id)


static func city_site_ids() -> PackedStringArray:
	var ids: PackedStringArray = []
	ids.append(CITY_SITE_ID)
	for id: String in later_city_ids():
		ids.append(id)
	return ids


static func arc_metres(from_dir: Vector3, to_dir: Vector3, radius := 8000.0) -> float:
	if from_dir.length_squared() < 0.0001 or to_dir.length_squared() < 0.0001:
		return 0.0
	return from_dir.normalized().angle_to(to_dir.normalized()) * maxf(radius, 1.0)


## Tangent from the first city toward the midpoint of two monuments.
static func city_pair_heading(
		city_dir: Vector3, first_dir: Vector3, second_dir: Vector3) -> Vector3:
	var origin := city_dir.normalized() if city_dir.length_squared() > 0.0001 \
			else Vector3.UP
	var toward := _tangent_at(origin, first_dir) + _tangent_at(origin, second_dir)
	toward -= origin * toward.dot(origin)
	if toward.length_squared() < 0.0001:
		toward = _tangent_at(origin, first_dir)
	if toward.length_squared() < 0.0001:
		toward = origin.cross(Vector3.RIGHT)
	if toward.length_squared() < 0.0001:
		toward = origin.cross(Vector3.FORWARD)
	return toward.normalized()


## Walk [param metres] along the sphere from [param from_dir] toward a tangent.
static func slide_direction(
		from_dir: Vector3,
		heading: Vector3,
		metres: float,
		radius := 8000.0
	) -> Vector3:
	var origin := from_dir.normalized() if from_dir.length_squared() > 0.0001 \
			else Vector3.UP
	var tangent := heading - origin * heading.dot(origin)
	if tangent.length_squared() < 0.0001 or metres == 0.0:
		return origin
	var axis := origin.cross(tangent.normalized())
	if axis.length_squared() < 0.0001:
		return origin
	var span := metres / maxf(radius, 1.0)
	return origin.rotated(axis.normalized(), span).normalized()


static func _tangent_at(origin: Vector3, toward: Vector3) -> Vector3:
	if toward.length_squared() < 0.0001:
		return Vector3.ZERO
	var dir := toward.normalized()
	return dir - origin * origin.dot(dir)


static func is_first_city(city_key: String) -> bool:
	var clean := city_key.strip_edges()
	if clean.is_empty() or clean == CITY_SITE_ID:
		return true
	if NetworkManager == null:
		return false
	var listed: Variant = NetworkManager.session_options.get("crawler_cities", [])
	if listed is Array and not (listed as Array).is_empty():
		return str((listed as Array)[0]) == clean
	return false


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


static func session_mode() -> String:
	if NetworkManager == null:
		return ""
	return str(NetworkManager.session_options.get("mode", ""))


static func uses_mode(mode: String) -> bool:
	return mode == MODE_ID or mode == SANDBOX_ID


static func active() -> bool:
	return uses_mode(session_mode())


static func crawler() -> bool:
	return session_mode() == MODE_ID


static func sandbox() -> bool:
	return session_mode() == SANDBOX_ID


static func coop() -> bool:
	return NetworkManager != null and not NetworkManager.is_single_player


static func duel_active() -> bool:
	if NetworkManager == null or NetworkManager.active_world == null:
		return false
	var world := NetworkManager.active_world
	return world.has_method(&"duel_active") and bool(world.call(&"duel_active"))


static func sandbox_no_mobs() -> bool:
	return sandbox_cheat(CHEAT_MOBS)


static func sandbox_invincible() -> bool:
	return sandbox_cheat(CHEAT_INVINCIBLE)


static func sandbox_fast() -> bool:
	return sandbox_cheat(CHEAT_FAST)


static func sandbox_fast_accel() -> float:
	return SANDBOX_FAST_ACCEL if sandbox_fast() else 1.0


static func sandbox_infinite_gold() -> bool:
	return sandbox_cheat(CHEAT_GOLD)


static func sandbox_cheat_default(cheat: String) -> bool:
	return cheat == CHEAT_INVINCIBLE or cheat == CHEAT_FAST


static func sandbox_cheat(cheat: String) -> bool:
	if not sandbox() or NetworkManager == null:
		return false
	if not NetworkManager.session_options.has(cheat):
		return sandbox_cheat_default(cheat)
	return bool(NetworkManager.session_options[cheat])


static func set_sandbox_cheat(cheat: String, on: bool) -> void:
	if not sandbox() or NetworkManager == null:
		return
	if cheat != CHEAT_MOBS and cheat != CHEAT_INVINCIBLE \
			and cheat != CHEAT_FAST and cheat != CHEAT_GOLD:
		return
	NetworkManager.session_options[cheat] = on


static func apply_sandbox_defaults() -> void:
	if not sandbox() or NetworkManager == null:
		return
	if not NetworkManager.session_options.has(CHEAT_INVINCIBLE):
		NetworkManager.session_options[CHEAT_INVINCIBLE] = true
	if not NetworkManager.session_options.has(CHEAT_FAST):
		NetworkManager.session_options[CHEAT_FAST] = true


static func clear_sandbox_cheats() -> void:
	if NetworkManager == null:
		return
	for cheat: String in [CHEAT_MOBS, CHEAT_INVINCIBLE, CHEAT_FAST, CHEAT_GOLD]:
		NetworkManager.session_options.erase(cheat)


static func ability_slots() -> int:
	return ABILITY_SLOTS if active() else CharacterDB.ABILITY_SLOTS


## Most hops land in 5–20 m. Past that the leftover chance decays hard toward
## zero, so a 2500 m throw is possible and almost never happens.
static func fool_cape_distance(rng: RandomNumberGenerator) -> float:
	if rng == null:
		return FOOL_CAPE_MIN
	if rng.randf() < FOOL_CAPE_CORE_CHANCE:
		return rng.randf_range(FOOL_CAPE_MIN, FOOL_CAPE_LIKELY)
	var tail := pow(rng.randf(), FOOL_CAPE_TAIL_POWER)
	return FOOL_CAPE_LIKELY + (FOOL_CAPE_MAX - FOOL_CAPE_LIKELY) * tail


static func ability_enabled(id: String) -> bool:
	var clean := id
	if id.begins_with("ck:"):
		var bits := id.split(":")
		clean = bits[2] if bits.size() >= 4 else id
	if ENABLED_ABILITIES.has(clean):
		return true
	return sandbox() and CrawlerCatalog.is_ability(clean)


static func laser_start_stats() -> Dictionary:
	return {
		"damage": LASER_DAMAGE,
		"cooldown": LASER_COOLDOWN,
		"duration": LASER_DURATION,
		"range": LASER_RANGE,
		"knockback": LASER_KNOCKBACK,
	}


static func kame_start_stats() -> Dictionary:
	return {
		"damage": KAME_DAMAGE,
		"cooldown": KAME_COOLDOWN,
		"duration": KAME_DURATION,
		"range": KAME_RANGE,
		"knockback": KAME_KNOCKBACK,
		"radius": KAME_RADIUS,
		"beam_width": KAME_BEAM_WIDTH,
		"damage_hz": KAME_DAMAGE_HZ,
	}


static func nausicaa_start_stats() -> Dictionary:
	return {
		"damage": NAUSICAA_DAMAGE,
		"player_damage": NAUSICAA_PLAYER_DAMAGE,
		"cooldown": NAUSICAA_COOLDOWN,
		"duration": NAUSICAA_DURATION,
		"range": NAUSICAA_RANGE,
		"knockback": NAUSICAA_KNOCKBACK,
		"delay": NAUSICAA_DELAY,
		"radius": NAUSICAA_RADIUS,
		"beam_width": NAUSICAA_BEAM_WIDTH,
		"paint_radius": NAUSICAA_PAINT_RADIUS,
		"paint_spacing": NAUSICAA_PAINT_SPACING,
		"chain_interval": NAUSICAA_CHAIN_INTERVAL,
		"crater_radius": NAUSICAA_CRATER_RADIUS,
		"crater_depth": NAUSICAA_CRATER_DEPTH,
		"lift": NAUSICAA_LIFT,
		"explosion_duration": NAUSICAA_EXPLOSION,
		"size": 1.0,
	}


static func lightning_start_stats() -> Dictionary:
	return {
		"damage": LIGHTNING_DAMAGE,
		"cooldown": LIGHTNING_COOLDOWN,
		"duration": LIGHTNING_DURATION,
		"range": LIGHTNING_RANGE,
		"knockback": LIGHTNING_KNOCKBACK,
		"radius": LIGHTNING_RADIUS,
		"beam_width": LIGHTNING_BEAM_WIDTH,
		"arcs": float(LIGHTNING_ARCS),
		"shock": LIGHTNING_SHOCK,
		"hop_range": LIGHTNING_ARC_RANGE,
	}


static func is_pulsed_beam(catalog_id: String) -> bool:
	return catalog_id == "laser_eyes" or catalog_id == "kame" \
		or catalog_id == "lightning"


static func wall_start_stats() -> Dictionary:
	return {
		"cooldown": WALL_COOLDOWN,
		"range": WALL_RANGE,
		"duration": WALL_DURATION,
		"size": 1.0,
		"wall_width": WALL_WIDTH,
		"wall_height": WALL_HEIGHT,
		"wall_thickness": WALL_THICKNESS,
		"fade_duration": WALL_FADE,
		"project": 0.0,
		"firewall": 0.0,
		"house": 0.0,
	}


static func wall_project_speed(rank: int) -> float:
	return WALL_PROJECT_SPEED * float(maxi(rank, 0))


static func wall_firewall_damage(rank: int) -> float:
	return WALL_FIRE_DAMAGE * float(maxi(rank, 0))


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


static func hero_punch_start_stats() -> Dictionary:
	return {
		"damage": HERO_PUNCH_DAMAGE,
		"cooldown": HERO_PUNCH_COOLDOWN,
		"range": HERO_PUNCH_RANGE,
		"size": 1.0,
		"radius": HERO_PUNCH_RADIUS,
		"knockback": HERO_PUNCH_KNOCKBACK,
	}


static func overdrive_start_stats() -> Dictionary:
	return {
		"boost": OVERDRIVE_BOOST,
		"duration": OVERDRIVE_DURATION,
		"cooldown": OVERDRIVE_COOLDOWN,
		"animation_duration": ROAR_ANIMATION,
		"range": ROAR_RADIUS,
		"radius": ROAR_RADIUS,
		"size": 1.0,
		"damage": 0.0,
	}


static func overdrive_boost_mul(boost: float) -> float:
	return 1.0 + maxf(boost, 0.0)


static func overdrive_body_scale(boost: float, has_big: bool, big_rank := 0) -> float:
	var scale := overdrive_boost_mul(boost)
	if has_big:
		scale *= big_size_scale(big_rank)
	return scale


static func upgrade_stats_for(catalog_id: String) -> PackedStringArray:
	match catalog_id:
		"laser_eyes", "kame", "nausicaa":
			return PackedStringArray(
				["damage", "cooldown", "duration", "range", "size",
					"knockback", "slots"])
		"lightning":
			return PackedStringArray(
				["damage", "cooldown", "duration", "range", "size",
					"knockback", "arcs", "shock", "slots"])
		"meteor_punch", "hero_punch":
			return PackedStringArray(
				["damage", "cooldown", "size", "range", "knockback", "slots"])
		"starfire":
			return PackedStringArray(
				["damage", "cooldown", "size", "range", "knockback", "slots"])
		"light_bolt":
			return PackedStringArray(
				["damage", "cooldown", "size", "range", "knockback", "speed",
					"slots"])
		"icicle":
			return PackedStringArray(
				["damage", "cooldown", "size", "range", "knockback", "speed",
					"cold", "slots"])
		"teleport":
			return PackedStringArray(
				["cooldown", "size", "range", "speed", "swap", "slots"])
		"fus":
			return PackedStringArray(
				["damage", "cooldown", "size", "range", "knockback", "speed",
					"slots"])
		"mini_nuke":
			return PackedStringArray(
				["damage", "cooldown", "size", "range", "knockback", "slots"])
		"wall":
			return PackedStringArray(
				["cooldown", "range", "duration", "size",
					"project", "firewall", "house", "slots"])
		"roar":
			return PackedStringArray(
				["damage", "range", "knockback", "slots"])
		"toxic_blast", "charming_aura", "freeze_blast":
			return PackedStringArray(
				["damage", "range", "duration", "knockback", "slots"])
		"static_field":
			return PackedStringArray(
				["damage", "cooldown", "cast", "duration", "range", "size",
					"shock", "slots"])
		"toxic_field":
			return PackedStringArray(
				["damage", "cooldown", "cast", "duration", "range", "size",
					"toxic", "slots"])
		"freeze_field":
			return PackedStringArray(
				["damage", "cooldown", "cast", "duration", "range", "size",
					"freeze", "slots"])
		"healing_field":
			return PackedStringArray(
				["heal", "cooldown", "cast", "duration", "range", "size",
					"slots"])
		"overdrive":
			return PackedStringArray(
				["boost", "duration", "cooldown", "slots"])
		"wobble":
			return PackedStringArray(["wobble"])
		"big":
			return PackedStringArray(["size"])
		"bubble":
			return PackedStringArray(
				["damage", "size", "duration", "homing", "pop", "speed",
					"spreader"])
		"clip":
			return PackedStringArray(["ammo"])
		"endless":
			return PackedStringArray()
		"toxic":
			return PackedStringArray(["toxic", "duration"])
		"shock":
			return PackedStringArray(["shock"])
		"charm":
			return PackedStringArray(["charm"])
		"ice":
			return PackedStringArray(["freeze"])
		"multi":
			return PackedStringArray(["multi"])
		"reach":
			return PackedStringArray(["range", "far_cast"])
		"bounce":
			return PackedStringArray(["bounce"])
		"impact_cast":
			return PackedStringArray()
		"homing":
			return PackedStringArray(["homing", "range"])
		"linger":
			return PackedStringArray(["duration", "toxic", "freeze", "slow"])
		_:
			return PackedStringArray()


## Stats shown on the hero sheet. Empty means every numeric stat the card has.
static func display_stats_for(catalog_id: String) -> PackedStringArray:
	if catalog_id == "starfire":
		return PackedStringArray(
			["damage", "cooldown", "size", "range", "knockback", "slots"])
	if catalog_id == "light_bolt":
		return PackedStringArray(
			["damage", "cooldown", "size", "range", "knockback", "speed",
				"slots"])
	if catalog_id == "icicle":
		return PackedStringArray(
			["damage", "cooldown", "size", "range", "knockback", "speed",
				"cold", "slots"])
	if catalog_id == "teleport":
		return PackedStringArray(
			["cooldown", "size", "range", "speed", "swap", "slots"])
	if catalog_id == "fus":
		return PackedStringArray(
			["damage", "cooldown", "size", "range", "knockback", "speed",
				"slots"])
	if catalog_id == "mini_nuke":
		return PackedStringArray(
			["damage", "cooldown", "size", "range", "knockback", "slots"])
	if catalog_id == "meteor_punch" or catalog_id == "hero_punch":
		return PackedStringArray(
			["damage", "cooldown", "size", "range", "knockback", "slots"])
	if catalog_id == "laser_eyes" or catalog_id == "kame" \
			or catalog_id == "nausicaa":
		return PackedStringArray(
			["damage", "cooldown", "duration", "range", "size",
				"knockback", "slots"])
	if catalog_id == "lightning":
		return PackedStringArray(
			["damage", "cooldown", "duration", "range", "size",
				"knockback", "arcs", "shock", "slots"])
	if catalog_id == "roar":
		return PackedStringArray(["damage", "range", "knockback", "slots"])
	if is_roar_ability(catalog_id):
		return PackedStringArray(
			["damage", "range", "duration", "knockback", "slots"])
	if catalog_id == "healing_field":
		return PackedStringArray(
			["heal", "cooldown", "cast", "duration", "range", "size", "slots"])
	if is_field_ability(catalog_id):
		var extra := "shock"
		if catalog_id == "toxic_field":
			extra = "toxic"
		elif catalog_id == "freeze_field":
			extra = "freeze"
		return PackedStringArray(
			["damage", "cooldown", "cast", "duration", "range", "size", extra,
				"slots"])
	if catalog_id == "overdrive":
		return PackedStringArray(["boost", "duration", "cooldown", "slots"])
	if catalog_id == "bubble":
		return PackedStringArray(
			["damage", "size", "duration", "homing", "pop", "speed",
				"spreader"])
	if catalog_id == "clip":
		return PackedStringArray(["ammo"])
	if catalog_id == "toxic":
		return PackedStringArray(["toxic", "duration"])
	if catalog_id == "shock":
		return PackedStringArray(["shock"])
	if catalog_id == "charm":
		return PackedStringArray(["charm"])
	if catalog_id == "ice":
		return PackedStringArray(["freeze"])
	if catalog_id == "multi":
		return PackedStringArray(["multi"])
	if catalog_id == "reach":
		return PackedStringArray(["range", "far_cast"])
	if catalog_id == "bounce":
		return PackedStringArray(["bounce"])
	if catalog_id == "impact_cast":
		return PackedStringArray()
	if catalog_id == "homing":
		return PackedStringArray(["homing", "range"])
	if catalog_id == "linger":
		return PackedStringArray(["duration", "toxic", "freeze", "slow"])
	if catalog_id == "wall":
		return PackedStringArray(
			["cooldown", "range", "duration", "size",
				"project", "firewall", "house", "slots"])
	return PackedStringArray()


static func big_size_scale(rank: int) -> float:
	var clamped := clampi(rank, 0, BIG_SIZE_MAX_RANK)
	return BIG_SIZE_BASE * pow(BIG_SIZE_GROWTH, float(clamped))


static func upgrade_max_rank(catalog_id: String, stat_id: String) -> int:
	if catalog_id == "big" and stat_id == "size":
		return BIG_SIZE_MAX_RANK
	if catalog_id == "bubble":
		if stat_id == "spreader":
			return BUBBLE_SPREADER_MAX
		return BUBBLE_UPGRADE_MAX
	if catalog_id == "clip" and stat_id == "ammo":
		return CLIP_MAX_RANK
	if catalog_id == "multi" and stat_id == "multi":
		return MULTI_MAX_RANK
	if catalog_id == "linger":
		if stat_id == "toxic" or stat_id == "freeze":
			return ELEM_MAX_RANK
		return LINGER_UPGRADE_MAX
	if catalog_id == "reach" and (stat_id == "range" or stat_id == "far_cast"):
		return REACH_MAX_RANK
	if catalog_id == "bounce" and stat_id == "bounce":
		return BOUNCE_MAX_RANK
	if catalog_id == "homing" and (stat_id == "homing" or stat_id == "range"):
		return HOMING_MAX_RANK
	if catalog_id == "toxic" or catalog_id == "shock" \
			or catalog_id == "charm" or catalog_id == "ice":
		return ELEM_MAX_RANK
	if catalog_id == "wall" and stat_id == "house":
		return WALL_HOUSE_MAX
	if catalog_id == "teleport" and stat_id == "swap":
		return TELEPORT_SWAP_MAX
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
		var title := upgrade_stat_title(stat_id, catalog_id).to_upper()
		if cap > 0:
			lines.append("%s  //  %d / %d" % [title, mini(rank, cap), cap])
		else:
			lines.append("%s  //  %d" % [title, rank])
	return lines


static func is_ability_type(type_id: String) -> bool:
	return type_id == TYPE_BEAM or type_id == TYPE_SHOCKWAVE \
		or type_id == TYPE_PROJECTILE or type_id == TYPE_LIMITED \
		or type_id == TYPE_FIELD or type_id == TYPE_MISC


static func ability_type(catalog_id: String) -> String:
	match catalog_id:
		"laser_eyes", "nausicaa", "kame", "lightning":
			return TYPE_BEAM
		"roar", "toxic_blast", "charming_aura", "freeze_blast":
			return TYPE_SHOCKWAVE
		"static_field", "toxic_field", "freeze_field", "healing_field":
			return TYPE_FIELD
		"nuke", "mini_nuke", "starfire", "light_bolt", "icicle", "teleport", "fus":
			return TYPE_PROJECTILE
		_:
			return TYPE_MISC


static func uses_ammo(catalog_id: String) -> bool:
	return base_ammo(catalog_id) > 0


static func base_ammo(catalog_id: String) -> int:
	if catalog_id == "nuke":
		return NUKE_AMMO
	if catalog_id == "mini_nuke":
		return MINI_NUKE_AMMO
	return 0


static func is_orb_blast(catalog_id: String) -> bool:
	return catalog_id == "nuke" or catalog_id == "mini_nuke"


static func mini_nuke_start_stats() -> Dictionary:
	return {
		"damage": MINI_NUKE_DAMAGE,
		"impact": MINI_NUKE_IMPACT,
		"player_damage": MINI_NUKE_PLAYER_DAMAGE,
		"speed": MINI_NUKE_SPEED,
		"range": MINI_NUKE_RANGE,
		"size": 1.0,
		"radius": MINI_NUKE_RADIUS,
		"cooldown": MINI_NUKE_COOLDOWN,
		"projectile_radius": MINI_NUKE_PROJECTILE_RADIUS,
		"crater_radius": MINI_NUKE_CRATER_RADIUS,
		"crater_depth": MINI_NUKE_CRATER_DEPTH,
		"crater_warp": MINI_NUKE_CRATER_WARP,
		"knockback": MINI_NUKE_KNOCKBACK,
		"lift": MINI_NUKE_LIFT,
		"self_launch_speed": MINI_NUKE_SELF_LAUNCH,
		"explosion_duration": MINI_NUKE_EXPLOSION,
	}


static func light_bolt_start_stats() -> Dictionary:
	return {
		"damage": LIGHT_BOLT_DAMAGE,
		"impact": LIGHT_BOLT_IMPACT,
		"speed": LIGHT_BOLT_SPEED,
		"range": LIGHT_BOLT_RANGE,
		"size": 1.0,
		"radius": LIGHT_BOLT_RADIUS,
		"cooldown": LIGHT_BOLT_COOLDOWN,
		"projectile_radius": LIGHT_BOLT_PROJECTILE_RADIUS,
		"crater_radius": LIGHT_BOLT_CRATER_RADIUS,
		"crater_depth": LIGHT_BOLT_CRATER_DEPTH,
		"knockback": LIGHT_BOLT_KNOCKBACK,
	}


static func icicle_start_stats() -> Dictionary:
	return {
		"damage": ICICLE_DAMAGE,
		"cold_damage": ICICLE_COLD_DAMAGE,
		"cold": ICICLE_COLD,
		"speed": ICICLE_SPEED,
		"range": ICICLE_RANGE,
		"size": 1.0,
		"radius": ICICLE_RADIUS,
		"cooldown": ICICLE_COOLDOWN,
		"projectile_radius": ICICLE_PROJECTILE_RADIUS,
		"knockback": ICICLE_KNOCKBACK,
	}


static func teleport_start_stats() -> Dictionary:
	return {
		"damage": 0.0,
		"speed": TELEPORT_SPEED,
		"range": TELEPORT_RANGE,
		"size": 1.0,
		"radius": TELEPORT_RADIUS,
		"cooldown": TELEPORT_COOLDOWN,
		"projectile_radius": TELEPORT_PROJECTILE_RADIUS,
		"gravity": TELEPORT_GRAVITY,
		"loft": TELEPORT_LOFT,
		"swap": 0.0,
	}


static func is_particle_ability(catalog_id: String) -> bool:
	return catalog_id == "light_bolt" or catalog_id == "icicle" \
		or catalog_id == "teleport" or catalog_id == "fus"


static func fus_start_stats() -> Dictionary:
	return {
		"damage": FUS_DAMAGE,
		"speed": FUS_SPEED,
		"range": FUS_RANGE,
		"size": 1.0,
		"radius": FUS_RADIUS,
		"cooldown": FUS_COOLDOWN,
		"projectile_radius": FUS_PROJECTILE_RADIUS,
		"knockback": FUS_KNOCKBACK,
		"animation_duration": ROAR_ANIMATION,
	}


static func clip_ammo_mul(rank: int) -> int:
	return CLIP_BASE_MUL + clampi(rank, 0, CLIP_MAX_RANK)


static func multi_shots(rank: int) -> int:
	return clampi(
		MULTI_SHOTS_BASE + clampi(rank, 0, MULTI_MAX_RANK),
		MULTI_SHOTS_BASE, MULTI_SHOTS_MAX)


static func reach_range_mul(rank: int) -> float:
	return REACH_RANGE_MUL + REACH_RANGE_PER_RANK \
		* float(clampi(rank, 0, REACH_MAX_RANK))


static func far_cast_meters(rank: int) -> float:
	return REACH_FAR_CAST + REACH_FAR_CAST_PER_RANK \
		* float(clampi(rank, 0, REACH_MAX_RANK))


static func bounce_count(rank: int) -> int:
	return clampi(
		BOUNCE_BASE + clampi(rank, 0, BOUNCE_MAX_RANK),
		BOUNCE_BASE, BOUNCE_MAX)


static func homing_steer(rank: int) -> float:
	return HOMING_STEER_BASE + HOMING_STEER_PER_RANK \
		* float(clampi(rank, 0, HOMING_MAX_RANK))


static func homing_range(rank: int) -> float:
	return HOMING_RANGE_BASE + HOMING_RANGE_PER_RANK \
		* float(clampi(rank, 0, HOMING_MAX_RANK))


static func is_roar_ability(catalog_id: String) -> bool:
	return catalog_id == "roar" or catalog_id == "toxic_blast" \
		or catalog_id == "charming_aura" or catalog_id == "freeze_blast"


static func is_field_ability(catalog_id: String) -> bool:
	return catalog_id == "static_field" or catalog_id == "toxic_field" \
		or catalog_id == "freeze_field" or catalog_id == "healing_field"


static func field_base_damage(catalog_id: String) -> float:
	match catalog_id:
		"static_field":
			return FIELD_STATIC_DAMAGE
		"toxic_field":
			return FIELD_TOXIC_DAMAGE
		"freeze_field":
			return FIELD_FREEZE_DAMAGE
		_:
			return 0.0


static func field_start_stats(catalog_id: String) -> Dictionary:
	var stats := {
		"damage": field_base_damage(catalog_id),
		"cooldown": FIELD_COOLDOWN,
		"duration": FIELD_DURATION,
		"range": FIELD_RADIUS,
		"radius": FIELD_RADIUS,
		"size": 1.0,
		"fade_duration": FIELD_FADE,
		"cast": FIELD_CAST,
		"animation_duration": FIELD_ANIMATION,
		"shock": 0.0,
		"toxic": 0.0,
		"freeze": 0.0,
		"heal": 0.0,
	}
	if catalog_id == "static_field":
		stats["shock"] = FIELD_SHOCK
	elif catalog_id == "toxic_field":
		stats["toxic"] = FIELD_TOXIC
	elif catalog_id == "freeze_field":
		stats["freeze"] = FIELD_FREEZE
	elif catalog_id == "healing_field":
		stats["heal"] = FIELD_HEAL
	return stats


static func field_cast_time(card_cast: float, trim := 0.0) -> float:
	return maxf(FIELD_CAST_MIN, maxf(card_cast, 0.0) - maxf(trim, 0.0))


static func roar_base_damage(catalog_id: String) -> float:
	match catalog_id:
		"roar":
			return ROAR_DAMAGE
		"toxic_blast":
			return ROAR_TOXIC_DAMAGE
		"charming_aura":
			return ROAR_CHARM_DAMAGE
		"freeze_blast":
			return ROAR_FREEZE_DAMAGE
		_:
			return 0.0


static func roar_base_knockback(catalog_id: String) -> float:
	return ROAR_KNOCKBACK if catalog_id == "roar" else ROAR_OTHER_KNOCKBACK


static func roar_start_stats(catalog_id: String) -> Dictionary:
	var stats := {
		"damage": roar_base_damage(catalog_id),
		"range": ROAR_RADIUS,
		"radius": ROAR_RADIUS,
		"knockback": roar_base_knockback(catalog_id),
		"cooldown": ROAR_COOLDOWN,
		"animation_duration": ROAR_ANIMATION,
	}
	if catalog_id != "roar":
		stats["duration"] = ROAR_DURATION
	return stats


static func upgrade_stat_title(stat_id: String, catalog_id := "") -> String:
	match stat_id:
		"damage":
			return "Damage"
		"cooldown":
			return "Cooldown"
		"boost":
			return "Boost"
		"duration":
			if catalog_id == "bubble":
				return "Lingering time"
			if catalog_id == "linger":
				return "Linger time"
			if catalog_id == "toxic":
				return "Hold"
			if catalog_id == "wall" or is_field_ability(catalog_id):
				return "Lifetime"
			if catalog_id == "overdrive":
				return "Overdrive time"
			return "Effect duration" if is_roar_ability(catalog_id) \
				else "Firing time"
		"range":
			if catalog_id == "reach":
				return "Reach"
			if catalog_id == "homing":
				return "Seek Range"
			return "Range"
		"far_cast":
			return "Far Cast"
		"cast":
			return "Cast Time"
		"speed":
			return "Particle Speed" if is_particle_ability(catalog_id) \
				or catalog_id == "bubble" else "Speed"
		"cold":
			return "Cold"
		"swap":
			return "Swap"
		"size":
			return "Size"
		"slots":
			return "Modifier slots"
		"knockback":
			return "Knockback"
		"arcs":
			return "Arcs"
		"shock":
			return "Shock"
		"toxic":
			return "Toxic"
		"freeze":
			return "Freeze"
		"charm":
			return "Charm"
		"wobble":
			return "Wobble"
		"homing":
			return "Intensity" if catalog_id == "homing" else "Homing range"
		"pop":
			return "Pop"
		"spreader":
			return "Spreader"
		"ammo":
			return "Ammo"
		"multi":
			return "Splits"
		"bounce":
			return "Bounces"
		"project":
			return "Project"
		"firewall":
			return "Firewall"
		"house":
			return "House"
		"heal":
			return "Heal"
		"slow":
			return "Slow"
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
	if catalog_id == "bubble":
		match stat_id:
			"damage":
				return "Each bubble hits harder."
			"size":
				return "Bigger glowing orbs."
			"duration":
				return "Bubbles linger longer before they pop."
			"homing":
				return "Bubbles drift toward nearby mobs. Starts at no pull."
			"pop":
				return "Bubbles burst. Higher ranks widen the blast and scar the ground."
			"spreader":
				return "On. Bubbles carry the host ability's effect, such as poison."
			"speed":
				return "The orbs travel faster."
			_:
				return ""
	if catalog_id == "wall":
		match stat_id:
			"cooldown":
				return "Shorter wait between casts."
			"range":
				return "The wall appears farther in front of you."
			"duration":
				return "The barrier stands longer before it fades."
			"size":
				return "A wider, taller wall. House uses this as the room size."
			"project":
				return "The wall slides forward. Higher ranks push it faster."
			"firewall":
				return "The wall burns anything that touches it. Higher ranks hit harder."
			"house":
				return "On. Casts a box around you with a doorway at your back."
			"slots":
				return "One more modifier seat."
			_:
				return ""
	if catalog_id == "toxic":
		match stat_id:
			"toxic":
				return "Adds stacking poison. Two cards add together, and it scales with Elemental."
			"duration":
				return "Poison from this card lasts longer."
			_:
				return ""
	if catalog_id == "shock":
		return "Adds the lock-and-twitch jolt. Two cards last longer, and it scales with Elemental."
	if catalog_id == "charm":
		return "Charms enemies this attack hits. Two cards last longer, and it scales with Elemental."
	if catalog_id == "ice":
		return "Freezes what this attack hits. On a field it also slows bodies and shots inside."
	if catalog_id == "clip":
		return "Starts at %s shots. Upgrade to %s, then %s." % [
			format_mul(float(clip_ammo_mul(0))),
			format_mul(float(clip_ammo_mul(1))),
			format_mul(float(clip_ammo_mul(CLIP_MAX_RANK))),
		]
	if catalog_id == "multi":
		return "Starts at %s. Upgrade through %s, %s, then %s." % [
			format_mul(float(multi_shots(0))),
			format_mul(float(multi_shots(1))),
			format_mul(float(multi_shots(2))),
			format_mul(float(multi_shots(MULTI_MAX_RANK))),
		]
	if catalog_id == "linger":
		match stat_id:
			"duration":
				return "Clouds hang longer. Also lengthens Bubble linger on the same ability."
			"toxic":
				return "Linger clouds stack poison on anything that walks through."
			"freeze":
				return "Linger clouds freeze bodies that pass through."
			"slow":
				return "Mobs and shots crawl while they are inside the cloud."
			_:
				return ""
	if catalog_id == "reach":
		match stat_id:
			"range":
				return "Beams and shots travel farther. Starts at %s and reaches %s at level %d." % [
					format_mul(reach_range_mul(0)),
					format_mul(reach_range_mul(REACH_MAX_RANK)),
					REACH_MAX_RANK,
				]
			"far_cast":
				return "Casts from farther in front of you. Starts at %.0f m and reaches %.1f m at level %d." % [
					REACH_FAR_CAST,
					far_cast_meters(REACH_MAX_RANK),
					REACH_MAX_RANK,
				]
			_:
				return ""
	if catalog_id == "bounce":
		return "Starts at %d bounce. Upgrade through %d, %d, %d, then %d." % [
			bounce_count(0),
			bounce_count(1),
			bounce_count(2),
			bounce_count(3),
			bounce_count(BOUNCE_MAX_RANK),
		]
	if catalog_id == "homing":
		match stat_id:
			"homing":
				return "How hard the attack turns. Starts at %.1f and reaches %.1f at level %d." % [
					homing_steer(0),
					homing_steer(HOMING_MAX_RANK),
					HOMING_MAX_RANK,
				]
			"range":
				return "How far it looks for a mob. Starts at %.0f m and reaches %.0f m at level %d." % [
					homing_range(0),
					homing_range(HOMING_MAX_RANK),
					HOMING_MAX_RANK,
				]
			_:
				return ""
	if catalog_id == "mini_nuke":
		match stat_id:
			"damage":
				return "The core and its burst hit harder."
			"cooldown":
				return "Shorter wait between throws."
			"size":
				return "A bigger core, a wider blast, and a larger crater."
			"range":
				return "The core flies farther before it detonates."
			"knockback":
				return "The blast throws mobs farther."
			"slots":
				return "One more modifier seat."
			_:
				return ""
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
	if catalog_id == "light_bolt":
		match stat_id:
			"damage":
				return "Each bolt hits harder."
			"cooldown":
				return "Faster stream. Shorter wait between bolts."
			"size":
				return "Bigger bolts and a wider pop."
			"range":
				return "The bolts travel farther."
			"knockback":
				return "The pop throws mobs farther."
			"speed":
				return "The bolts fly faster."
			"slots":
				return "One more modifier seat."
			_:
				return ""
	if catalog_id == "icicle":
		match stat_id:
			"damage":
				return "Each icicle hits harder."
			"cooldown":
				return "Shorter wait between throws."
			"size":
				return "A thicker spear and a wider frost cloud."
			"range":
				return "The icicles travel farther."
			"knockback":
				return "The spear throws mobs farther."
			"speed":
				return "The icicles fly faster."
			"cold":
				return "Colder bite. Longer freeze, more frost damage, and a wider snow burst."
			"slots":
				return "One more modifier seat."
			_:
				return ""
	if catalog_id == "teleport":
		match stat_id:
			"cooldown":
				return "Shorter wait between throws."
			"size":
				return "A bigger marker and more room in front of a struck mob."
			"range":
				return "The marker flies farther before it spends out."
			"speed":
				return "The marker flies faster."
			"swap":
				return "On. Hitting a mob trades places. Off, you appear in front of them."
			"slots":
				return "One more modifier seat."
			_:
				return ""
	if catalog_id == "fus":
		match stat_id:
			"damage":
				return "The cone chips a little harder."
			"cooldown":
				return "Shorter wait between shouts."
			"size":
				return "A wider force cone."
			"range":
				return "The burst travels farther."
			"knockback":
				return "The cone throws mobs much farther."
			"speed":
				return "The burst flies faster."
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
	if catalog_id == "overdrive":
		match stat_id:
			"boost":
				return "A larger jump to every combat stat while Overdrive is on."
			"duration":
				return "Overdrive lasts longer."
			"cooldown":
				return "Shorter wait before you can roar again."
			"slots":
				return "One more modifier seat. Those mods power your other abilities while Overdrive is on."
			_:
				return ""
	if catalog_id == "lightning":
		match stat_id:
			"damage":
				return "The bolt hits harder each time it snaps."
			"cooldown":
				return "Shorter wait between bolts."
			"duration":
				return "Each pulse stays live a little longer."
			"range":
				return "The bolt reaches farther before it spends out."
			"size":
				return "A thicker bolt and a wider snap."
			"knockback":
				return "The bolt shoves bodies farther along the chain."
			"arcs":
				return "The bolt jumps to one more nearby target."
			"shock":
				return "Locks the victim, lets them twitch free, then locks them again."
			"slots":
				return "One more modifier seat."
			_:
				return ""
	if catalog_id == "hero_punch":
		match stat_id:
			"damage":
				return "Each jab hits harder."
			"cooldown":
				return "Shorter wait between jabs."
			"size":
				return "A thicker fist."
			"range":
				return "The jab reaches farther."
			"knockback":
				return "Mobs are thrown farther by the jab."
			"slots":
				return "One more modifier seat."
			_:
				return ""
	if is_field_ability(catalog_id):
		match stat_id:
			"damage":
				if catalog_id == "toxic_field":
					return "Poison stacks faster while a mob stands in the field."
				if catalog_id == "freeze_field":
					return "The frost sphere chips bodies that linger inside."
				return "Mobs that enter the field take a harder jolt."
			"cooldown":
				return "Shorter wait between casts."
			"cast":
				return "Shorter stand-still before the field appears."
			"duration":
				return "The field stays up longer before it fades."
			"range":
				return "The sphere reaches farther from your chest."
			"size":
				return "A larger field."
			"shock":
				return "Shock lasts longer. Victims lock, twitch free, then lock again."
			"toxic":
				return "Poison from the field lasts longer."
			"freeze":
				return "Mobs and shots inside move even slower."
			"heal":
				return "Standing inside restores more health."
			"slots":
				return "One more modifier seat."
			_:
				return ""
	if is_roar_ability(catalog_id):
		match stat_id:
			"damage":
				if catalog_id == "toxic_blast":
					return "Poison ticks harder."
				if catalog_id == "freeze_blast":
					return "The frost front hits harder."
				if catalog_id == "charming_aura":
					return "Reserved for a later charm sting."
				return "The roar hits a little harder."
			"range":
				return "The shockwave travels farther."
			"duration":
				return "The shockwave's effect lasts longer."
			"knockback":
				return "The shockwave shoves mobs farther."
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
	return start_patch(name) or city_patch(name)


static func safe_patch(_name: String) -> bool:
	return false


static func start_patch(name: String) -> bool:
	var clean := name.strip_edges()
	return clean == START_PATCH or clean.begins_with(START_PATCH + " ")


static func city_patch(name: String) -> bool:
	var clean := name.strip_edges()
	return clean == CITY_PATCH or clean.begins_with(CITY_PATCH + " ")


static func opening_route_patch(name: String) -> bool:
	var clean := name.strip_edges()
	return clean == "Tide Margin" or clean.begins_with("Tide Margin ") \
		or clean == "Quiet Inlet" or clean.begins_with("Quiet Inlet ")


static func demon_grounds(name: String) -> bool:
	var clean := name.strip_edges()
	return clean == CASTLE_PATCH or clean == TOWER_PATCH \
		or clean.begins_with(CASTLE_PATCH + " ") \
		or clean.begins_with(TOWER_PATCH + " ")


static func is_demon_kind(kind: String) -> bool:
	return DEMON_KINDS.has(kind.strip_edges())


static func near_demon_site(at: Vector3) -> bool:
	if not at.is_finite():
		return false
	var castle := PatchMonument.find_id(CrawlerProgress.QUEST_CASTLE)
	if castle != null and at.distance_to(castle.global_position) <= DEMON_SITE_RANGE:
		return true
	var tower := PatchMonument.find_id(CrawlerProgress.QUEST_TOWER)
	return tower != null and at.distance_to(tower.global_position) <= DEMON_SITE_RANGE


static func demon_sites_ready() -> bool:
	return PatchMonument.find_id(CrawlerProgress.QUEST_CASTLE) != null \
		or PatchMonument.find_id(CrawlerProgress.QUEST_TOWER) != null


static func can_field_demons(patch_name: String, at := Vector3.INF) -> bool:
	if reserved_patch(patch_name) or opening_route_patch(patch_name) \
			or not demon_grounds(patch_name):
		return false
	if not at.is_finite() or not demon_sites_ready():
		return true
	return near_demon_site(at)


static func field_kinds(patch_name: String, from_start := -1.0,
		at := Vector3.INF) -> PackedStringArray:
	var kinds := PackedStringArray()
	for kind: String in _recipe_kinds(patch_name, from_start):
		if is_demon_kind(kind) and not can_field_demons(patch_name, at):
			continue
		kinds.append(kind)
	return kinds


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


static func is_goblin_kind(kind: String) -> bool:
	return GOBLIN_KINDS.has(kind.strip_edges())


static func goblin_garrison_kind(index: int) -> String:
	var interior := index < GOBLIN_INTERIOR
	var local_i := index if interior else index - GOBLIN_INTERIOR
	var count := GOBLIN_INTERIOR if interior else maxi(GOBLIN_GARRISON - GOBLIN_INTERIOR, 1)
	var share := float(local_i) / float(maxi(count - 1, 1))
	if share >= 0.70:
		return "vex"
	return "gruk" if (index & 1) == 0 else "nix"


static func goblin_garrison_reach(index: int) -> float:
	var interior := index < GOBLIN_INTERIOR
	var local_i := index if interior else index - GOBLIN_INTERIOR
	var count := GOBLIN_INTERIOR if interior else maxi(GOBLIN_GARRISON - GOBLIN_INTERIOR, 1)
	var share := float(local_i) / float(maxi(count - 1, 1))
	if interior:
		return lerpf(GOBLIN_INNER_MIN, GOBLIN_INNER_MAX, share)
	return lerpf(GOBLIN_OUTER_MIN, GOBLIN_OUTER_MAX, share)


static func flies(kind: String) -> bool:
	return kind == "ranger" or kind == "rammer" or is_demon_kind(kind)


static func spawn_weight(kind: String) -> int:
	match kind:
		"gloam":
			return 8
		"vesper":
			return 2
		"threnody":
			return 1
		_:
			return 3


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


## Farther than the live lead pack. The horde stamps these as cheap
## surface points while the player is still approaching, so a fast flight
## does not have to solve homes in the same tick it instantiates them.
static func spawn_preview_range(speed: float) -> Vector2:
	var lead := spawn_lead_range(maxf(speed, SPAWN_LEAD_SPEED))
	var near := maxf(lead.y + 12.0, WILD_STREAM_IN)
	var far := WILD_STREAM_OUT - 28.0
	return Vector2(near, maxf(far, near + 24.0))


static func spawn_stream_range(speed: float) -> Vector2:
	var lead := spawn_lead_range(speed)
	if not uses_lead_pack(speed):
		return lead
	return Vector2(lead.x, spawn_preview_range(speed).y)


static func spawn_ready_count(speed: float) -> int:
	return 24 if uses_lead_pack(speed) else 12


static func mob_lod(gap: float) -> int:
	if gap <= MOB_LOD_HOT_RANGE:
		return MOB_LOD_HOT
	if gap <= MOB_LOD_WARM_RANGE:
		return MOB_LOD_WARM
	return MOB_LOD_COLD


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
