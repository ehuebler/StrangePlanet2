class_name Nausicaa
extends Ability

## A short blue eye beam that plants its fuse at the beam tip.
##
## A mob standing in front of the beam takes the mark with it. Terrain is no
## longer the target: bounce only folds the remaining range. Each sufficiently
## separated landing becomes its own replicated glow, and because the points
## are submitted in draw order with the same one-second fuse, they erupt in
## that same order.

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
		eyes[0], eyes[1], targets, EnergyVfx.TINT_PURPLE, _beam_width(),
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
	var reach := maxf(stat("range", CrawlerRules.NAUSICAA_RANGE), 1.0)
	var center := player.aim_direction(from)
	var dirs := CrawlerMulti.fan_dirs(
		center, CrawlerMulti.shots(stats), CrawlerMulti.up_of(player))
	var out: Array[Dictionary] = []
	for along: Vector3 in dirs:
		out.append(plan_landing(player, from, along, reach, stats))
	return out


## Beam tip, or the first living mob the capsule reaches. Bounce folds leftover
## range off a wall instead of planting on it.
static func plan_landing(shooter: Node, from: Vector3, along: Vector3,
		reach: float, stats: Dictionary) -> Dictionary:
	var dir := along.normalized() if along.length_squared() > 0.000001 \
		else Vector3.FORWARD
	var span := maxf(reach, 1.0)
	if CrawlerHoming.enabled(stats):
		dir = CrawlerHoming.aim(from, dir, stats, shooter, 0.4)
	var width := _beam_hit_radius(stats)
	var cursor := from
	var left := span
	var remaining := CrawlerBounce.count(stats)
	var path := PackedVector3Array()
	path.append(from)
	while left > 0.02:
		var tip := cursor + dir * left
		var prey := first_beam_prey(shooter, cursor, tip, width)
		if prey != null:
			var dest := CrawlerHoming.combat_at(prey)
			_append_plan_hop(path, cursor, dest, dir, stats)
			return _landing(dest, dir, prey, path)
		if remaining > 0 and shooter is OnlinePlayer:
			var wall := LaserEyes._surface(
				shooter as OnlinePlayer, cursor, tip)
			if not wall.is_empty():
				var at: Vector3 = wall.get("position", tip)
				var normal: Vector3 = wall.get("normal", -dir)
				var wall_span := cursor.distance_to(at)
				if at.is_finite() and wall_span < left - 0.02:
					_append_plan_hop(path, cursor, at, dir, stats)
					var outgoing := CrawlerBounce.reflect(dir, normal)
					if outgoing.length_squared() < 0.000001:
						return _landing(at, dir, null, path)
					cursor = CrawlerBounce.nudge(at, normal, outgoing)
					dir = outgoing
					if CrawlerHoming.enabled(stats):
						dir = CrawlerHoming.aim(cursor, dir, stats, shooter)
					left -= maxf(wall_span, 0.02)
					remaining -= 1
					continue
		_append_plan_hop(path, cursor, tip, dir, stats)
		return _landing(tip, dir, null, path)
	var fallback := from + dir * span
	return _landing(fallback, dir, null, PackedVector3Array([from, fallback]))


static func first_beam_prey(shooter: Node, from: Vector3, to: Vector3,
		width: float) -> Node:
	if shooter == null or not shooter.is_inside_tree() \
			or not from.is_finite() or not to.is_finite():
		return null
	var sweep := DamageHit.beam(from, to, maxf(width, 0.2), 0.0)
	var along := to - from
	var span2 := along.length_squared()
	if span2 < 0.000001:
		return null
	var best: Node = null
	var best_along := INF
	for node in CrawlerHoming.foes(shooter):
		var at := CrawlerHoming.combat_at(node)
		var bounds := 0.4
		if node.has_method(&"combat_radius"):
			bounds = maxf(float(node.call(&"combat_radius")), 0.15)
		if not sweep.reaches(at, bounds):
			continue
		var along_span := (at - from).dot(along)
		if along_span < 0.0 or along_span > span2 + 0.05:
			continue
		if along_span < best_along:
			best = node
			best_along = along_span
	return best


static func _beam_hit_radius(stats: Dictionary) -> float:
	return maxf(float(stats.get("beam_width", CrawlerRules.NAUSICAA_BEAM_WIDTH))
			* 0.5, 0.35)


static func _landing(at: Vector3, along: Vector3, follow: Node,
		path: PackedVector3Array) -> Dictionary:
	var dir := along.normalized() if along.length_squared() > 0.000001 \
		else Vector3.FORWARD
	return {
		"position": at,
		"along": dir,
		"normal": -dir,
		"follow": follow,
		"path": path,
	}


static func _append_plan_hop(path: PackedVector3Array, from: Vector3,
		dest: Vector3, along: Vector3, stats: Dictionary) -> void:
	if CrawlerHoming.enabled(stats):
		var curved := CrawlerHoming.arc(from, dest, along, stats)
		var start := 1 if not path.is_empty() else 0
		for index in range(start, curved.size()):
			path.append(curved[index])
		if curved.size() <= start:
			path.append(dest)
		return
	path.append(dest)


func _beam_width() -> float:
	return maxf(stat("beam_width", 1.0), 0.35)


func _wobble_amount() -> float:
	return maxf(stat("wobble", 0.0), 0.0)
