extends Node

## Warm city wisps load only at night while a player stands in the ring.
##
##     godot --headless --path . dev/_city_night_wisps_test.tscn

const WISPS := preload("res://game/city/city_night_wisps.gd")

var _failures := 0


func _ready() -> void:
	await _check_load_rules()
	await _check_light_reaches()
	await _check_only_occupied_city()
	print("city_night_wisps_test: %s" % (
		"all checks passed" if _failures == 0 else "%d check(s) failed" % _failures))
	get_tree().quit(1 if _failures > 0 else 0)


func _check_load_rules() -> void:
	var ring := CrawlerCityRing.new()
	ring.configure(-1, Transform3D.IDENTITY)
	add_child(ring)
	await get_tree().process_frame
	var wisps := _wisps_of(ring)
	_expect(wisps != null, "the ring seats a night-wisp host")
	if wisps == null:
		ring.queue_free()
		await get_tree().process_frame
		return
	wisps.night_override = 1.0
	wisps.advance(0.16)
	_expect(wisps.wisp_count() == 0, "an empty city does not load wisps")
	var visitor := _stand_in(Vector3(0.0, 2.0, 0.0))
	wisps.advance(0.16)
	_expect(wisps.wisp_count() == WISPS.WISP_COUNT,
		"night and a visitor load the city wisps")
	wisps.night_override = 0.0
	wisps.advance(0.16)
	_expect(wisps.wisp_count() == 0, "daylight unloads the wisps")
	wisps.night_override = 1.0
	wisps.advance(0.16)
	_expect(wisps.wisp_count() == WISPS.WISP_COUNT,
		"nightfall in the city brings the wisps back")
	visitor.global_position = Vector3(400.0, 2.0, 0.0)
	wisps.advance(0.16)
	_expect(wisps.wisp_count() == 0, "leaving the city unloads the wisps")
	visitor.queue_free()
	ring.queue_free()
	await get_tree().process_frame


func _check_light_reaches() -> void:
	var ring := CrawlerCityRing.new()
	ring.configure(3, Transform3D.IDENTITY)
	add_child(ring)
	var visitor := _stand_in(Vector3(8.0, 2.0, 0.0))
	await get_tree().process_frame
	var wisps := _wisps_of(ring)
	_expect(wisps != null, "the lit city still has a wisp host")
	if wisps == null:
		visitor.queue_free()
		ring.queue_free()
		await get_tree().process_frame
		return
	wisps.night_override = 1.0
	wisps.advance(0.16)
	var lamps: Array = wisps.omni_lights()
	_expect(lamps.size() == WISPS.WISP_COUNT,
		"each wisp carries a real omni light")
	if lamps.is_empty():
		visitor.queue_free()
		ring.queue_free()
		await get_tree().process_frame
		return
	var lamp: OmniLight3D = lamps[0]
	_expect(lamp.light_energy > 10.0, "the wisps are bright enough to wash adobe")
	_expect(lamp.omni_range >= 34.0, "the wash reaches nearby buildings")
	_expect(lamp.light_color.r > lamp.light_color.g
			and lamp.light_color.g > lamp.light_color.b,
		"the wisps are warm orange")
	_expect(lamp.light_cull_mask & 1 != 0, "the wash hits the default character layer")
	_expect(lamp.light_cull_mask & Planet.TERRAIN_RENDER_LAYER != 0,
		"the wash hits planet terrain")
	_expect(not lamp.shadow_enabled, "the wisps light without shadow maps")
	var first: Vector3 = lamp.global_position
	wisps.advance(8.0)
	_expect(first.distance_to(lamp.global_position) > 0.4,
		"the wisps drift through the air")
	var loft := INF
	var high := 0.0
	for lit: OmniLight3D in lamps:
		loft = minf(loft, lit.global_position.y)
		high = maxf(high, lit.global_position.y)
	_expect(loft >= 0.6 and high <= 3.6,
		"the wisps stay near the street, not the rooftops")
	var core := wisps.find_child("Core", true, false) as MeshInstance3D
	_expect(core != null and core.visible, "each wisp is a visible ember")
	visitor.queue_free()
	ring.queue_free()
	await get_tree().process_frame


func _check_only_occupied_city() -> void:
	var home := CrawlerCityRing.new()
	home.configure(1, Transform3D.IDENTITY)
	add_child(home)
	var other := CrawlerCityRing.new()
	other.configure(2, Transform3D(Basis(), Vector3(400.0, 0.0, 0.0)))
	add_child(other)
	var visitor := _stand_in(Vector3(0.0, 2.0, 0.0))
	await get_tree().process_frame
	var home_wisps := _wisps_of(home)
	var other_wisps := _wisps_of(other)
	_expect(home_wisps != null and other_wisps != null,
		"each city keeps its own wisp host")
	if home_wisps == null or other_wisps == null:
		visitor.queue_free()
		home.queue_free()
		other.queue_free()
		await get_tree().process_frame
		return
	home_wisps.night_override = 1.0
	other_wisps.night_override = 1.0
	home_wisps.advance(0.16)
	other_wisps.advance(0.16)
	_expect(home_wisps.wisp_count() == WISPS.WISP_COUNT,
		"the occupied city loads its wisps")
	_expect(other_wisps.wisp_count() == 0,
		"a distant city stays dark and unloaded")
	visitor.queue_free()
	home.queue_free()
	other.queue_free()
	await get_tree().process_frame


func _wisps_of(ring: CrawlerCityRing) -> Node:
	return ring.get_node_or_null("NightWisps")


func _stand_in(at: Vector3) -> Node3D:
	var body := Node3D.new()
	body.position = at
	body.add_to_group("network_players")
	add_child(body)
	return body


func _expect(ok: bool, label: String) -> void:
	if ok:
		return
	_failures += 1
	push_error("city_night_wisps_test failed: %s" % label)
