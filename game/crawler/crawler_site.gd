class_name CrawlerSite
extends Landmark

## Named crawler place. The first city lights its tilde mark immediately;
## spawn and later sites wait until the player walks in. Monuments keep
## their own [PatchMonument] type and join the same poll.

var site_id := ""
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


func unlock_waypoint() -> void:
	waypoint = true
	if not is_in_group(CrawlerRules.CITY_WAYPOINT_GROUP):
		add_to_group(CrawlerRules.CITY_WAYPOINT_GROUP)
