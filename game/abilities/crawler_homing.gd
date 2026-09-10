class_name CrawlerHoming
extends RefCounted

## Seated Homing: beams arc, shots turn, punches lock, and leftover clouds follow.


const ARC_STEPS := 10
const CLOUD_SPEED := 2.4


static func enabled(stats: Dictionary) -> bool:
	return steer_of(stats) > 0.001 and range_of(stats) > 0.001


static func steer_of(stats: Dictionary) -> float:
	return maxf(float(stats.get("homing", 0.0)), 0.0)


static func range_of(stats: Dictionary) -> float:
	return maxf(float(stats.get("homing_range", 0.0)), 0.0)


static func combat_at(node: Node) -> Vector3:
	return CombatantSense.aim_point(node)


static func is_live(node: Node) -> bool:
	if node == null or not is_instance_valid(node):
		return false
	if node.has_method(&"is_alive") and not bool(node.call(&"is_alive")):
		return false
	if node.has_method(&"is_dead") and bool(node.call(&"is_dead")):
		return false
	return true


static func nearest(anywhere: Node, from: Vector3, along: Vector3,
		stats: Dictionary, keep := -1.0) -> Node:
	if anywhere == null or not anywhere.is_inside_tree() or not from.is_finite() \
			or not enabled(stats):
		return null
	var face := along.normalized() if along.length_squared() > 0.000001 \
		else Vector3.ZERO
	return CrawlerShotSense.prey(anywhere, from, range_of(stats), anywhere,
		face, keep, 0.12, true)


static func foes(anywhere: Node) -> Array[Node]:
	if anywhere == null or not anywhere.is_inside_tree():
		return []
	return CombatantSense.collect(anywhere, anywhere, DamageHit.Faction.ENEMY)


static func aim(from: Vector3, along: Vector3, stats: Dictionary,
		anywhere: Node, keep := 0.12) -> Vector3:
	var face := along.normalized() if along.length_squared() > 0.000001 \
		else Vector3.FORWARD
	if not enabled(stats):
		return face
	var prey := nearest(anywhere, from, face, stats, keep)
	if prey == null:
		return face
	var toward := combat_at(prey) - from
	if toward.length_squared() < 0.0001:
		return face
	var pull := clampf(steer_of(stats) / (steer_of(stats) + 6.0), 0.18, 0.9)
	var homed := face.lerp(toward.normalized(), pull)
	if homed.length_squared() < 0.0001:
		return face
	homed = homed.normalized()
	if keep > 0.0 and homed.dot(face) < keep:
		var side := (toward.normalized() - face * toward.normalized().dot(face))
		if side.length_squared() < 0.0001:
			return face
		var max_turn := sqrt(maxf(1.0 - keep * keep, 0.0))
		homed = (face * keep + side.normalized() * max_turn).normalized()
	return homed


static func turn(along: Vector3, toward: Vector3, stats: Dictionary,
		delta: float) -> Vector3:
	var face := along.normalized() if along.length_squared() > 0.000001 \
		else Vector3.FORWARD
	if toward.length_squared() < 0.0001 or not enabled(stats):
		return face
	var blend := 1.0 - exp(-delta * steer_of(stats))
	var homed := face.lerp(toward.normalized(), blend)
	if homed.length_squared() < 0.0001:
		return face
	return homed.normalized()


static func steer(velocity: Vector3, from: Vector3, stats: Dictionary,
		anywhere: Node, delta: float, speed := 0.0) -> Vector3:
	if not enabled(stats) or not from.is_finite():
		return velocity
	var prey := nearest(anywhere, from, velocity, stats, -1.0)
	if prey == null:
		return velocity
	var toward := combat_at(prey) - from
	if toward.length_squared() < 0.0001:
		return velocity
	var pace := speed if speed > 0.001 else maxf(velocity.length(), 1.0)
	var wanted := toward.normalized() * pace
	var blend := 1.0 - exp(-delta * steer_of(stats))
	return velocity.lerp(wanted, blend)


static func lock(anywhere: Node, from: Vector3, along: Vector3,
		stats: Dictionary, keep := 0.08) -> Node:
	return nearest(anywhere, from, along, stats, keep)


static func snap_point(from: Vector3, at: Vector3, stats: Dictionary,
		anywhere: Node) -> Vector3:
	if not at.is_finite() or not enabled(stats):
		return at
	var along := at - from
	var prey := nearest(anywhere, from, along, stats, 0.08)
	if prey == null:
		return at
	return combat_at(prey)


static func arc(from: Vector3, dest: Vector3, along: Vector3,
		stats: Dictionary) -> PackedVector3Array:
	var points := PackedVector3Array()
	if not from.is_finite() or not dest.is_finite():
		return points
	var span := dest - from
	var length := span.length()
	if length < 0.08:
		points.append(from)
		points.append(dest)
		return points
	var dir := along.normalized() if along.length_squared() > 0.000001 \
		else span / length
	var pull := dest - (from + dir * length)
	var strength := clampf(steer_of(stats) / 10.0, 0.16, 0.82)
	var control := from.lerp(dest, 0.46) + pull * strength
	for index in ARC_STEPS + 1:
		var t := float(index) / float(ARC_STEPS)
		var a := from.lerp(control, t)
		var b := control.lerp(dest, t)
		points.append(a.lerp(b, t))
	return points


static func trace(shooter: OnlinePlayer, from: Vector3, along: Vector3,
		reach: float, stats: Dictionary) -> Dictionary:
	var points := PackedVector3Array()
	var hits := PackedVector3Array()
	if not from.is_finite() or along.length_squared() < 0.000001:
		return {"points": points, "hits": hits, "landed": false}
	var dir := aim(from, along, stats, shooter)
	var dest := from + dir * maxf(reach, 0.5)
	var prey := nearest(shooter, from, dir, stats, 0.08)
	if prey != null:
		var at := combat_at(prey)
		if from.distance_to(at) <= maxf(reach, 0.5) + 1.2:
			dest = at
	var landed := false
	if shooter != null and shooter.is_inside_tree():
		var wall := LaserEyes._surface(shooter, from, dest)
		if not wall.is_empty():
			var wall_at := wall.get("position", dest) as Vector3
			if prey == null or from.distance_to(wall_at) \
					< from.distance_to(combat_at(prey)) - 0.15:
				dest = wall_at
				landed = true
				prey = null
	if prey != null:
		dest = combat_at(prey)
		landed = true
	points = arc(from, dest, along, stats)
	if landed:
		hits.append(dest)
	return {"points": points, "hits": hits, "landed": landed}


static func uses_path(stats: Dictionary) -> bool:
	return enabled(stats) or CrawlerBounce.count(stats) > 0
