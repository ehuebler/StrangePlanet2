class_name DroppedWorldMotion
extends RefCounted

## Shared settle-and-spin for world pickups. Tiles spawn in the air, fall to
## the ground they can see, and keep turning once they land.

const FALL_SECONDS := 0.9
const FALL_SPIN := 2.55
const GROUND_SPIN := 1.2
const BOB_HEIGHT := 0.045
const BOB_SPEED := 1.7
const MIN_FALL := 0.12


static func start(body: Node3D, clearance: float) -> Dictionary:
	if body == null:
		return _state(Vector3.ZERO, Vector3.ZERO, 1.0)
	var from := body.global_position
	var to := land_point(body, clearance)
	if from.distance_to(to) < MIN_FALL:
		return _state(from, from, 1.0)
	return _state(from, to, 0.0)


static func start_to(body: Node3D, at: Vector3) -> Dictionary:
	if body == null or not at.is_finite():
		return _state(Vector3.ZERO, Vector3.ZERO, 1.0)
	return _state(body.global_position, at, 0.0)


static func tick(
		body: Node3D,
		visual: Node3D,
		state: Dictionary,
		delta: float,
		visual_origin: Vector3
	) -> void:
	if body == null or state.is_empty():
		return
	state["clock"] = float(state.get("clock", 0.0)) + delta
	var t := float(state.get("t", 1.0))
	if t < 1.0:
		t = minf(t + delta / FALL_SECONDS, 1.0)
		state["t"] = t
		var from: Vector3 = state.get("from", body.global_position)
		var to: Vector3 = state.get("to", body.global_position)
		if from.is_finite() and to.is_finite():
			var weight := t * t * (3.0 - 2.0 * t)
			body.global_position = from.lerp(to, weight)
	if not is_instance_valid(visual):
		return
	var spin := FALL_SPIN if t < 1.0 else GROUND_SPIN
	visual.rotate_y(delta * spin)
	if t >= 1.0:
		visual.position = visual_origin + Vector3.UP \
			* (sin(float(state.get("clock", 0.0)) * BOB_SPEED) * BOB_HEIGHT)


static func landed(state: Dictionary) -> bool:
	return float(state.get("t", 1.0)) >= 1.0


static func land_point(body: Node3D, clearance: float) -> Vector3:
	if body == null or not body.is_inside_tree():
		return Vector3.ZERO
	var from := body.global_position
	var pad := maxf(clearance, 0.04)
	var planet := _planet_of(body)
	if planet != null and planet.shape != null:
		var local := planet.to_local(from)
		if local.length_squared() >= 0.25:
			var surface := planet.surface_position(local)
			var up := planet.up_at(surface)
			return surface + up * pad
	var up_guess := from.normalized() if from.length_squared() > 0.01 \
		else Vector3.UP
	var space := body.get_world_3d().direct_space_state
	if space != null:
		var query := PhysicsRayQueryParameters3D.create(
			from, from - up_guess * 80.0)
		query.exclude = [body.get_rid()] if body is CollisionObject3D \
			else []
		var hit := space.intersect_ray(query)
		if not hit.is_empty():
			var normal: Vector3 = hit.get("normal", up_guess)
			if not normal.is_finite() or normal.length_squared() < 0.0001:
				normal = up_guess
			return hit["position"] + normal.normalized() * pad
	return from


static func _planet_of(body: Node3D) -> Planet:
	var walk: Node = body
	while walk != null:
		if walk is Planet:
			return walk
		var child := walk.get_node_or_null("Planet")
		if child is Planet:
			return child
		walk = walk.get_parent()
	return null


static func _state(from: Vector3, to: Vector3, t: float) -> Dictionary:
	return {
		"from": from,
		"to": to,
		"t": t,
		"clock": 0.0,
	}
