class_name CrawlerBounce
extends RefCounted

## Seated Bounce ranks, plus the ricochet path a beam or shot follows.


static func count(stats: Dictionary) -> int:
	var listed := int(round(float(stats.get("bounce", 0.0))))
	if listed <= 0:
		return 0
	return clampi(listed, 1, CrawlerRules.BOUNCE_MAX)


static func reflect(incoming: Vector3, normal: Vector3) -> Vector3:
	if incoming.length_squared() < 0.000001:
		return Vector3.ZERO
	var face := normal
	if face.length_squared() < 0.000001:
		return incoming.normalized()
	face = face.normalized()
	var outgoing := incoming.bounce(face)
	if outgoing.length_squared() < 0.000001:
		return face
	outgoing = outgoing.normalized()
	if outgoing.dot(face) < 0.08:
		outgoing = (outgoing + face * 0.2).normalized()
	return outgoing


static func nudge(at: Vector3, normal: Vector3, outgoing: Vector3) -> Vector3:
	var face := normal.normalized() if normal.length_squared() > 0.000001 \
		else Vector3.UP
	var away := outgoing.normalized() if outgoing.length_squared() > 0.000001 \
		else face
	return at + face * 0.06 + away * 0.08


static func explodes_on_bounce(definition: AbilityDefinition) -> bool:
	if definition == null:
		return false
	return definition.impact_type in [
		AbilityDefinition.ImpactType.EXPLOSION_CRATER,
		AbilityDefinition.ImpactType.MASSIVE_BLAST,
		AbilityDefinition.ImpactType.DELAYED_BLAST,
		AbilityDefinition.ImpactType.FROST_BURST,
	]


static func trace(shooter: OnlinePlayer, from: Vector3, along: Vector3,
		reach: float, bounces: int, stats: Dictionary = {}) -> Dictionary:
	var points := PackedVector3Array()
	var hits := PackedVector3Array()
	if not from.is_finite() or along.length_squared() < 0.000001:
		return {"points": points, "hits": hits, "landed": false}
	var dir := along.normalized()
	if CrawlerHoming.enabled(stats):
		dir = CrawlerHoming.aim(from, dir, stats, shooter)
	var left := maxf(reach, 0.0)
	var cursor := from
	points.append(from)
	var remaining := maxi(bounces, 0)
	while left > 0.02:
		var to := cursor + dir * left
		var prey := CrawlerHoming.lock(shooter, cursor, dir, stats) \
			if CrawlerHoming.enabled(stats) else null
		var prey_at := CrawlerHoming.combat_at(prey) if prey != null \
			else Vector3.ZERO
		var prey_span := cursor.distance_to(prey_at) if prey != null else INF
		var hit := _surface(shooter, cursor, to)
		var dest := to
		var landed := false
		var wall := false
		if not hit.is_empty():
			var wall_at := hit.get("position", to) as Vector3
			if wall_at.is_finite():
				dest = wall_at
				landed = true
				wall = true
		if prey != null and prey_span <= left + 1.2 \
				and (not wall or prey_span < cursor.distance_to(dest) - 0.15):
			dest = prey_at
			landed = true
			wall = false
			remaining = 0
		points = _append_hop(points, cursor, dest, dir, stats)
		if not landed:
			return {"points": points, "hits": hits, "landed": false}
		hits.append(dest)
		left -= maxf(cursor.distance_to(dest), 0.02)
		if remaining <= 0:
			return {"points": points, "hits": hits, "landed": true}
		var normal := hit.get("normal", -dir) as Vector3
		var outgoing := reflect(dir, normal)
		if outgoing.length_squared() < 0.000001:
			return {"points": points, "hits": hits, "landed": true}
		cursor = nudge(dest, normal, outgoing)
		dir = outgoing
		if CrawlerHoming.enabled(stats):
			dir = CrawlerHoming.aim(cursor, dir, stats, shooter)
		remaining -= 1
	return {"points": points, "hits": hits, "landed": not hits.is_empty()}


static func _append_hop(points: PackedVector3Array, from: Vector3, dest: Vector3,
		along: Vector3, stats: Dictionary) -> PackedVector3Array:
	if CrawlerHoming.enabled(stats):
		var curved := CrawlerHoming.arc(from, dest, along, stats)
		var start := 1 if not points.is_empty() else 0
		for index in range(start, curved.size()):
			points.append(curved[index])
		if curved.size() <= start:
			points.append(dest)
		return points
	points.append(dest)
	return points


static func _surface(shooter: OnlinePlayer, from: Vector3, to: Vector3) -> Dictionary:
	if shooter == null or not shooter.is_inside_tree() \
			or not from.is_finite() or not to.is_finite():
		return {}
	return LaserEyes._surface(shooter, from, to)
