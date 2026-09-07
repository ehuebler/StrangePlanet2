class_name CrawlerSite
extends Landmark

## Named crawler place. The first city lights its tilde mark immediately;
## the spawn reveal turns the player to see it before tilde is needed.
## Spawn and later sites wait until the player walks in. Monuments keep
## their own [PatchMonument] type and join the same poll.

var site_id := ""
var city_key := ""
var enter_radius := 120.0


func _init() -> void:
	waypoint = false


func _ready() -> void:
	add_to_group(CrawlerRules.SITE_GROUP)
	add_to_group(Landmark.GROUP)
	set_notify_transform(Engine.is_editor_hint())
	if CrawlerRules.starts_visible(site_id):
		unlock_waypoint()
	if planet_host() != null:
		place()


func unlock_waypoint(announce := true) -> void:
	var first := not waypoint
	waypoint = true
	if not is_in_group(CrawlerRules.CITY_WAYPOINT_GROUP):
		add_to_group(CrawlerRules.CITY_WAYPOINT_GROUP)
	if first and announce:
		CrawlerSites.announce_unlock(self)
