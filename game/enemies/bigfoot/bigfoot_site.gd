@tool
extends Landmark

## Named deterministic anchor for Bigfoot's surveyed forest arena. Tilde's
## planet-wide navigation overlay points here from any distance.

const SITE_DIRECTION := Vector3(-0.959298134, 0.271219909, 0.078657165)

## Baked from dev/_bigfoot_site.gd against game/world.tscn's current
## PlanetShape and exact ForestGiants GroundCover species on 2026-08-11.
const SURVEY_SUMMARY := (
	"71.290 deg from VacationersLanding; ForestGiants score 60.9%, habitat 98.8%, "
	+ "patch 61.6%, dense samples 95.9%; elevation 28.4 m (23.3..31.5 m); "
	+ "dry/usable 100%/100%; centre/average/p90/max slope "
	+ "4.19/4.09/7.14/9.74 deg; 12 m footprint spread 1.80 m; "
	+ "nearest settlement 9661 m; SouthPoleVolcano centre/edge "
	+ "14764/13314 m."
)


func _init() -> void:
	direction = SITE_DIRECTION
	facing = 0.0
	title = "Bigfoot"
	tint = Color("f06a43")
	waypoint = true
	show_beyond = 0.0
	aimed_beyond = 0.0
	hide_beyond = 0.0


## Machine-readable copy used by the survey's baked-result validation. Keeping
## this beside the human summary makes terrain/species changes show exactly
## which placement assumptions went stale.
func survey_metrics() -> Dictionary:
	return {
		"arc_degrees": 71.290,
		"forest_score": 0.609,
		"habitat_share": 0.988,
		"patch_share": 0.616,
		"dense_share": 0.959,
		"elevation": 28.4,
		"elevation_min": 23.3,
		"elevation_max": 31.5,
		"dry_share": 1.0,
		"usable_share": 1.0,
		"center_slope_degrees": 4.19,
		"average_slope_degrees": 4.09,
		"p90_slope_degrees": 7.14,
		"max_slope_degrees": 9.74,
		"footprint_spread": 1.80,
		"settlement_clearance": 9661.0,
		"volcano_distance": 14764.0,
		"volcano_edge_clearance": 13314.0,
	}
