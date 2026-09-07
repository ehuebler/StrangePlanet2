class_name Lightning
extends LaserEyes

## One bolt from the eyes. It snaps onto a body, then jumps to a nearby one.
##
## Base fire hits two targets when a second stands close enough. The Arcs
## upgrade adds one more hop per rank. Shock, when bought, locks the victim,
## lets them twitch free, then locks them again.

const COLOR := Color(0.48, 0.86, 1.0)
const SNAP_RADIUS := 7.0
const HOP_RANGE := 9.0

var _linger_hops: PackedVector3Array = PackedVector3Array()
var _linger_origin := Vector3.ZERO


func _origin_points() -> Array[Vector3]:
	if player == null:
		return [Vector3.ZERO, Vector3.ZERO]
	var eyes := player.eye_points()
	var mid: Vector3 = (eyes[0] + eyes[1]) * 0.5
	return [mid, mid]


func _beam_tint() -> Color:
	if definition != null:
		return definition.tint
	return COLOR


func _beam_width() -> float:
	return maxf(stat("beam_width", CrawlerRules.LIGHTNING_BEAM_WIDTH), 0.28)


func _beam_radius() -> float:
	return maxf(stat("radius", CrawlerRules.LIGHTNING_RADIUS), 0.05)


func _aim_beams() -> Dictionary:
	var empty: Array[Vector3] = [Vector3.ZERO, Vector3.ZERO]
	if player == null:
		return {"eyes": empty, "at": Vector3.ZERO, "landed": false}
	var origins := _cast_origins()
	var from: Vector3 = origins[0]
	var landing := _landing(from)
	var splits := CrawlerMulti.shots(stats)
	var aimed := CrawlerHoming.snap_point(from, landing["at"], stats, player)
	var seeds := CrawlerMulti.fan_points(
		from, aimed, splits, CrawlerMulti.up_of(player))
	var chains: Array = []
	var first: PackedVector3Array = PackedVector3Array()
	var snap := SNAP_RADIUS + CrawlerHoming.range_of(stats) * 0.45
	for seed: Vector3 in seeds:
		var hops := collect_hops(
			player, from, seed, int(round(stat("arcs", 1.0))),
			stat("hop_range", HOP_RANGE), snap)
		if hops.is_empty():
			hops = PackedVector3Array([seed])
		chains.append(hops)
		if first.is_empty():
			first = hops
	player.lightning_bolts().aim_many(
		from, chains, _beam_tint(), _beam_width(), CrawlerReach.far_cast(stats))
	_linger_origin = from
	_linger_hops = first
	var at: Vector3 = landing["at"] if splits > 1 \
		else (first[0] if not first.is_empty() else landing["at"])
	return {"eyes": origins, "at": at, "landed": not first.is_empty() \
		or bool(landing["landed"])}


func _on_beam_dark() -> void:
	if player != null and _linger_hops.size() >= 1:
		var path := PackedVector3Array()
		path.append(_linger_origin)
		path.append_array(_linger_hops)
		CrawlerLingers.emit_path(
			player, ability_id, path, CrawlerRules.LINGER_BEAM_MUL)
	_linger_hops = PackedVector3Array()
	_linger_ready = false


func _release() -> void:
	if player != null:
		player.lightning_bolts().stop()
		player.laser_beams().stop()
	_forget_dwell()
	_on_beam_dark()


static func apply_effect(shooter: OnlinePlayer, id: String, left_eye: Vector3,
		right_eye: Vector3, at: Vector3, landed: bool,
		radius := -1.0, beam_width := 1.0, wobble := 0.0, _pulse := false) -> void:
	if shooter == null:
		return
	var stats := LaserEyes._resolved_stats(shooter, id)
	var step := 1.0 / LaserEyes._damage_hz_for(id, stats)
	var from: Vector3 = (left_eye + right_eye) * 0.5
	var splits := CrawlerMulti.shots(stats)
	var aimed := CrawlerHoming.snap_point(from, at, stats, shooter)
	var seeds := PackedVector3Array([aimed])
	if splits > 1:
		seeds = CrawlerMulti.fan_points(
			from, aimed, splits, CrawlerMulti.up_of(shooter))
	var chains: Array = []
	var first: PackedVector3Array = PackedVector3Array()
	var snap := SNAP_RADIUS + CrawlerHoming.range_of(stats) * 0.45
	for seed: Vector3 in seeds:
		var hops := collect_hops(
			shooter, from, seed, int(round(float(stats.get("arcs", 1.0)))),
			float(stats.get("hop_range", HOP_RANGE)), snap)
		if hops.is_empty():
			hops = PackedVector3Array([seed])
		chains.append(hops)
		if first.is_empty():
			first = hops
	shooter.lightning_bolts().aim_many(
		from, chains, _tint_of(shooter, id), maxf(beam_width, 0.28),
		CrawlerReach.far_cast(stats))
	var per_tick := float(stats.get("damage", 0.0))
	if CrawlerRules.active() and shooter.has_method(&"crawler_damage_scale"):
		per_tick *= float(shooter.call(&"crawler_damage_scale"))
	per_tick *= step
	if radius < 0.0:
		radius = float(stats.get("radius", CrawlerRules.LIGHTNING_RADIUS))
	var knockback := maxf(float(stats.get("knockback", 0.0)), 0.0)
	if CrawlerRules.active() and shooter.has_method(&"crawler_knockback_scale"):
		knockback *= float(shooter.call(&"crawler_knockback_scale"))
	var pulse := int(Time.get_ticks_msec() / 100)
	for chain_variant: Variant in chains:
		var hops: PackedVector3Array = chain_variant
		if hops.is_empty():
			continue
		var bolt := PackedVector3Array()
		bolt.append(from)
		bolt.append_array(hops)
		CrawlerBubbles.emit_beam(
			shooter, id, from, from, hops[hops.size() - 1], wobble, pulse, bolt)
		var last := from
		for hop in hops:
			_strike_segment(
				shooter, id, last, hop, radius, per_tick, knockback * step, stats)
			last = hop
	if first.is_empty():
		return
	if not landed and first.size() <= 1 and splits <= 1:
		return
	var facing := Vector3.UP
	var world_planet := shooter.planet()
	if world_planet != null:
		facing = world_planet.up_at(first[0])
	shooter.play_laser_impact_dust(first[0], facing, true)
	var last_at: Vector3 = first[first.size() - 1]
	var prev_at: Vector3 = first[first.size() - 2] if first.size() > 1 else from
	var along := last_at - prev_at
	if along.length_squared() > 0.000001:
		facing = along.normalized()
	elif world_planet != null:
		facing = world_planet.up_at(last_at)
	CrawlerImpactCast.emit(shooter, id, last_at, facing, stats)


static func collect_hops(anywhere: Node, from: Vector3, seed_at: Vector3,
		extra: int, hop_range: float, snap_radius: float) -> PackedVector3Array:
	var hops := PackedVector3Array()
	var used: Array[Node] = []
	var first := _snap_combatant(anywhere, from, seed_at, snap_radius)
	var cursor := seed_at
	if first != null:
		cursor = _body_at(first)
		used.append(first)
		hops.append(cursor)
	else:
		if seed_at.is_finite():
			hops.append(seed_at)
	var hops_left := maxi(extra, 0)
	while hops_left > 0:
		var next := _nearest_unused(anywhere, cursor, hop_range, used)
		if next == null:
			break
		cursor = _body_at(next)
		used.append(next)
		hops.append(cursor)
		hops_left -= 1
	return hops


static func _strike_segment(shooter: OnlinePlayer, id: String, from: Vector3,
		to: Vector3, radius: float, damage: float, knock: float,
		stats: Dictionary) -> void:
	var along := to - from
	if along.length_squared() > 0.0001:
		along = along.normalized()
	else:
		along = Vector3.ZERO
	var cut := DamageHit.beam(from, to, radius, damage)
	cut.ability_id = id
	cut.faction = shooter.combat_faction()
	cut.set_source(shooter, shooter.peer_id)
	cut.plant_break_effects = false
	cut.affects_combatants = false
	if knock > 0.0 and along != Vector3.ZERO:
		cut.world_impulse = along * knock
	DamageHit.apply_to_world(shooter, cut)
	var zap := DamageHit.impact(to, maxf(radius * 2.4, 0.8), damage)
	zap.ability_id = id
	zap.faction = shooter.combat_faction()
	zap.set_source(shooter, shooter.peer_id)
	zap.plant_break_effects = false
	if knock > 0.0 and along != Vector3.ZERO:
		zap.world_impulse = along * knock
	CrawlerElements.stamp(zap, shooter, id, stats)
	DamageHit.apply_to_world(shooter, zap)


static func _snap_combatant(anywhere: Node, from: Vector3, seed_at: Vector3,
		snap_radius: float) -> Node:
	var along := seed_at - from
	var reach := along.length()
	if reach < 0.001:
		return _nearest_unused(anywhere, seed_at, snap_radius, [])
	var dir := along / reach
	var best: Node
	var best_score := snap_radius
	for combatant in _foes(anywhere):
		var at := _body_at(combatant)
		var away := at - from
		var along_ray := away.dot(dir)
		if along_ray < -0.4 or along_ray > reach + snap_radius:
			continue
		var onto := from + dir * clampf(along_ray, 0.0, reach)
		var off := at.distance_to(onto)
		if off > snap_radius:
			continue
		if off < best_score:
			best_score = off
			best = combatant
	return best


static func _nearest_unused(anywhere: Node, from: Vector3, reach: float,
		used: Array[Node]) -> Node:
	var best: Node
	var best_away := reach
	for combatant in _foes(anywhere):
		if used.has(combatant):
			continue
		var away := from.distance_to(_body_at(combatant))
		if away <= best_away:
			best_away = away
			best = combatant
	return best


static func _foes(anywhere: Node) -> Array[Node]:
	var out: Array[Node] = []
	if anywhere == null or not anywhere.is_inside_tree():
		return out
	var source_faction := DamageHit.Faction.PLAYER
	if anywhere.has_method(&"combat_faction"):
		source_faction = int(anywhere.call(&"combat_faction"))
	for combatant_variant: Variant in anywhere.get_tree().get_nodes_in_group(
			DamageHit.COMBATANT_GROUP):
		var combatant := combatant_variant as Node
		if combatant == null or combatant == anywhere:
			continue
		if not DamageHit.in_same_world(anywhere, combatant) \
				and DamageHit.game_world_of(anywhere) != null:
			continue
		if combatant.has_method(&"is_alive") \
				and not bool(combatant.call(&"is_alive")):
			continue
		if combatant.has_method(&"is_dead") \
				and bool(combatant.call(&"is_dead")):
			continue
		if not combatant.has_method(&"combat_faction"):
			continue
		var theirs := int(combatant.call(&"combat_faction"))
		if source_faction == DamageHit.Faction.PLAYER \
				and theirs != DamageHit.Faction.ENEMY:
			continue
		if source_faction == DamageHit.Faction.ENEMY \
				and theirs != DamageHit.Faction.PLAYER:
			continue
		out.append(combatant)
	return out


static func _body_at(combatant: Node) -> Vector3:
	if combatant != null and combatant.has_method(&"combat_position"):
		var at: Variant = combatant.call(&"combat_position")
		if at is Vector3 and (at as Vector3).is_finite():
			return at
	if combatant is Node3D:
		return (combatant as Node3D).global_position
	return Vector3.ZERO


static func _tint_of(shooter: OnlinePlayer, id: String) -> Color:
	var definition := ItemDB.ability_definition(id)
	if definition != null:
		return definition.tint
	return COLOR
