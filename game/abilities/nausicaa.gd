class_name Nausicaa
extends Ability

## A short blue eye beam that paints only real planet terrain.
##
## Each sufficiently separated landing point becomes its own replicated glow.
## Because the points are submitted in draw order and every one keeps the same
## one-second fuse, they erupt in that same order instead of turning the whole
## trail into one simultaneous blast.

var _request_sequence := 0
var _left := 0.0
var _since_paint := 0.0
var _since_bubble := 0.0
var _last_painted: Array[Vector3] = []
var _last_paths: Array[PackedVector3Array] = []


func _press() -> bool:
	if definition == null or definition.impact_type \
			!= AbilityDefinition.ImpactType.DELAYED_BLAST:
		return false
	var eyes := _cast_eyes()
	var from: Vector3 = (eyes[0] + eyes[1]) * 0.5
	var landings := _fan_landings(from)
	if landings.is_empty():
		return false
	_left = maxf(stat("duration", 0.75), 0.05)
	_since_paint = 0.0
	_since_bubble = 0.0
	_last_painted.clear()
	_last_paths.clear()
	var painted := false
	for landing: Dictionary in landings:
		var path: PackedVector3Array = landing.get("path", PackedVector3Array())
		if path.size() >= 2:
			_last_paths.append(path)
		painted = _paint(eyes, from, landing, _last_painted.size()) or painted
	return painted


func _tick(delta: float) -> void:
	if player.submerged_share() > 0.0:
		release()
		return
	_left -= delta
	if _left <= 0.0:
		release()
		return

	var eyes := _cast_eyes()
	var from: Vector3 = (eyes[0] + eyes[1]) * 0.5
	var landings := _fan_landings(from)
	if landings.is_empty():
		player.laser_beams().stop()
		return
	var targets := PackedVector3Array()
	var paths: Array[PackedVector3Array] = []
	for landing: Dictionary in landings:
		targets.append(landing["position"])
		var path: PackedVector3Array = landing.get("path", PackedVector3Array())
		if path.size() >= 2:
			paths.append(path)
	_last_paths = paths
	player.laser_beams().aim_many(
		eyes[0], eyes[1], targets, definition.tint, _beam_width(),
		_wobble_amount(), LaserBeams.FOLLOW_EYES, CrawlerReach.far_cast(stats),
		paths)
	_since_bubble += delta
	if _since_bubble >= LaserEyes.DAMAGE_STEP:
		_since_bubble = fmod(_since_bubble, LaserEyes.DAMAGE_STEP)
		var pulse := int(Time.get_ticks_msec() / 100)
		for landing: Dictionary in landings:
			var at: Vector3 = landing["position"]
			var path: PackedVector3Array = landing.get(
				"path", PackedVector3Array())
			CrawlerBubbles.emit_beam(
				player, ability_id, eyes[0], eyes[1], at, _wobble_amount(),
				pulse, path)

	_since_paint += delta
	var interval := maxf(stat("chain_interval", 0.08), 0.03)
	if _since_paint < interval:
		return
	_since_paint = fmod(_since_paint, interval)
	var spacing := maxf(stat("paint_spacing", 0.8), 0.1)
	for index in landings.size():
		var at: Vector3 = landings[index]["position"]
		if index < _last_painted.size() \
				and _last_painted[index] != Vector3.ZERO \
				and at.distance_to(_last_painted[index]) < spacing:
			continue
		_paint(eyes, from, landings[index], index)


func _release() -> void:
	if player != null:
		var eyes := _cast_eyes()
		var from: Vector3 = (eyes[0] + eyes[1]) * 0.5
		if not _last_paths.is_empty():
			for path: PackedVector3Array in _last_paths:
				if path.size() >= 2:
					CrawlerLingers.emit_path(
						player, ability_id, path, CrawlerRules.LINGER_BEAM_MUL)
		else:
			for at: Vector3 in _last_painted:
				if at != Vector3.ZERO:
					CrawlerLingers.emit_beam_trail(player, ability_id, from, at)
	_request_sequence = 0
	_left = 0.0
	_since_paint = 0.0
	_since_bubble = 0.0
	_last_painted.clear()
	_last_paths.clear()
	if player != null:
		player.laser_beams().stop()


func _paint(eyes: Array[Vector3], from: Vector3,
		landing: Dictionary, slot: int) -> bool:
	var at: Vector3 = landing["position"]
	var along: Vector3 = landing.get("along", player.aim_direction(from))
	_request_sequence = player.fire_ability_delayed_blast(
		ability_id, from, along)
	if _request_sequence <= 0:
		return false
	while _last_painted.size() <= slot:
		_last_painted.append(Vector3.ZERO)
	_last_painted[slot] = at
	return true


func _cast_eyes() -> Array[Vector3]:
	if player == null:
		return [Vector3.ZERO, Vector3.ZERO]
	var eyes := player.eye_points()
	var from: Vector3 = (eyes[0] + eyes[1]) * 0.5
	return CrawlerReach.shift_pair(
		eyes[0], eyes[1], player.aim_direction(from), stats)


func _fan_landings(from: Vector3) -> Array[Dictionary]:
	var reach := maxf(stat("range", 14.0), 1.0)
	var center := player.aim_direction(from)
	var dirs := CrawlerMulti.fan_dirs(
		center, CrawlerMulti.shots(stats), CrawlerMulti.up_of(player))
	var bounces := CrawlerBounce.count(stats)
	var out: Array[Dictionary] = []
	for along: Vector3 in dirs:
		if CrawlerHoming.enabled(stats):
			along = CrawlerHoming.aim(from, along, stats, player, 0.4)
		if bounces > 0:
			var traced := CrawlerBounce.trace(
				player, from, along, reach, bounces, stats)
			var points: PackedVector3Array = traced.get(
				"points", PackedVector3Array())
			if points.size() < 2:
				continue
			var hits: PackedVector3Array = traced.get(
				"hits", PackedVector3Array())
			var at: Vector3 = hits[hits.size() - 1] if not hits.is_empty() \
				else points[points.size() - 1]
			out.append({
				"position": at,
				"along": along,
				"path": points,
			})
			continue
		var hit := LaserEyes.terrain_surface(
			player, from, from + along * reach)
		if hit.is_empty():
			continue
		hit["along"] = along
		if CrawlerHoming.enabled(stats):
			var dest := hit.get("position", from + along * reach) as Vector3
			hit["path"] = CrawlerHoming.arc(from, dest, along, stats)
		out.append(hit)
	return out


func _beam_width() -> float:
	return maxf(stat("beam_width", 1.0), 0.35)


func _wobble_amount() -> float:
	return maxf(stat("wobble", 0.0), 0.0)
