class_name DamageHit
extends RefCounted

## One combat/effect volume, handed to everything standing inside it.
##
## Abilities do not know what they are hitting. They describe a shape, an amount
## and how the amount falls off across it, and every damageable field works out
## for itself which of the things it owns are inside. That is what lets one laser
## tick damage grass, a tree and the ground with the same object, and what keeps
## the ability files free of any knowledge of MultiMesh buffers or tile cells.
##
## Capsules remain the default used by beams and point impacts. A flat-ended
## cylinder is also available for authored waves such as a roar.
##
## Nothing here is per-target state. A hit is built, offered around, and dropped;
## the accumulated damage lives with whatever absorbed it.

## Group every field that can be damaged by an ability joins. Abilities reach
## their targets through this rather than through node paths, the same way
## [ImpactBreakEffects] is found.
const FIELD_GROUP := &"flora_damage_fields"
## Nodes that answer `combat_faction`, `combat_position`, and `apply_damage`.
const COMBATANT_GROUP := &"combatants"
## Cities that own destructible lots. Applied on every peer, like flora.
const BUILDING_GROUP := &"city_damage_fields"
## Player-facing names for authored attacks. Internal IDs survive the network
## with the hit, but exposing those IDs on a death screen would turn
## `bigfoot_rock` into implementation detail instead of useful information.
const ABILITY_DISPLAY_NAMES := {
	"bigfoot_rock": "Rock Throw",
	"bigfoot_meteor": "Meteor Punch",
	"bigfoot_punch": "Punch",
	"bigfoot_grab": "Grab",
	"bigfoot_throw": "Grab Throw",
	"bigfoot_roar": "Roar",
	"bigfoot_trample": "Trample",
	"grapple": "Grapple",
	"lasso": "Lasso",
	"laser_eyes": "Laser Eyes",
	"meteor_punch": "Meteor Punch",
	"nausicaa": "Nausicaä",
	"nuke": "Nuke",
	"building_collapse": "Collapse",
	"parry_reflect": "Parry Reflection",
	"starfire": "Starfire",
	"wall": "Wall",
}

enum Shape {
	CAPSULE,
	CYLINDER,
}

enum Faction {
	NEUTRAL,
	PLAYER,
	ENEMY,
}

enum Reaction {
	NONE,
	STAGGER,
	KNOCKBACK,
	RAGDOLL,
}

const REACTION_FULL_RAGDOLL := Reaction.RAGDOLL


static func rid_list(rid: RID = RID()) -> Array[RID]:
	var out: Array[RID]
	if rid.is_valid():
		out.append(rid)
	return out


enum Kind {
	## A sustained cutting line, such as the laser. Damages along its length.
	BEAM,
	## A single violent contact, such as the meteor fist.
	IMPACT,
	## The dissipating spread left behind by an impact.
	AREA,
}

## Damage at the centre of the volume, before falloff and before the target's
## own toughness. For a sustained effect this is already the per-tick share, not
## a rate: an ability that ticks ten times a second passes a tenth of its
## quoted damage each time.
var amount := 0.0
## Ends of the capsule's axis, in world space. Equal for a point impact.
var origin := Vector3.ZERO
var toward := Vector3.ZERO
## Radius of the capsule in metres.
var radius := 1.0
var kind := Kind.IMPACT
var shape := Shape.CAPSULE
## How much of the damage survives to the edge of the radius. 0 keeps the full
## amount everywhere inside (a clean cut), 1 falls linearly to nothing (the
## dissipating spread of a landing).
var falloff := 0.0
## The band of species this volume touches, by authored height in metres. Zero
## at either end, the default, means no bound at that end.
##
## Something walking through undergrowth flattens the undergrowth; it does not
## level the canopy it is walking under, and it does not mow the lawn either.
## Expressed as species heights rather than as a smaller damage number because a
## ledger accumulates: a volume weak enough to leave a tree standing on one pass
## fells it on the twentieth.
##
## The floor is also what makes a volume like that affordable. Ground cover is
## most of the plants on the planet — a third of a million blades of grass stand
## within sight of a jungle floor — and a volume that cannot break any of them
## can be turned away by a whole field at a time instead of being offered every
## blade.
var min_plant_height := 0.0
var max_plant_height := 0.0
## Whether deterministic flora fields are offered this volume.
##
## Actor and terrain footprints often differ. Keeping this explicit avoids
## scanning a wide knockback blast through every blade only to follow it with
## the smaller, categorical uproot that owns the crater.
var affects_flora := true
## Whether actors are offered this volume after flora has taken it.
##
## Most hits affect both. A terrain-cutting impact is the exception: the blast
## players feel dissipates toward its edge, while every root over the ground
## that was physically removed has to be uprooted at full strength. Keeping the
## second volume flora-only lets those two truths coexist without turning the
## visual crater radius into a lethal actor hit.
var affects_combatants := true
## Whether each plant this uproots throws its own burst of fragments.
##
## On for everything a player can watch happen: one shrub coming apart is the
## whole feedback that it came apart. Off for volumes wide enough that nobody is
## looking at any single plant in them — a meteor landing takes seventeen
## thousand instances in one frame, and asking the pooled effect for seventeen
## thousand bursts inside its own explosion costs twenty-five milliseconds and
## puts nothing on screen that the explosion was not already covering.
var plant_break_effects := true
## Who caused it, so a host can attribute a break, and the ability that did, so
## a field can pick a matching break effect.
var source_peer := 0
var ability_id := ""
## Path under the containing GameWorld. Relative paths cannot address a
## combatant in another world branch.
var source_path := NodePath()
## Optional direct player target. Zero means every eligible combatant in shape.
var target_peer := 0
var faction := Faction.NEUTRAL
var reaction := Reaction.NONE
## World-space velocity/impulse authored by the attack.
var world_impulse := Vector3.ZERO
## Host-authored outward and local-up impulse. These are resolved separately for
## each combatant, unlike `world_impulse`, which points the same way for all.
var radial_impulse := 0.0
var radial_lift := 0.0
## When true, solid layer-one geometry between the volume centre and an actor
## protects that actor. Kept opt-in because existing melee and flora volumes are
## intentionally geometric rather than visibility queries.
var blocked_by_world := false
var status := &""
var status_duration := 0.0
var parryable := false
## Damage dealt back to the source by a perfect parry. Zero falls back to amount.
var reflection := 0.0
## Reliable combat event sequence. Networking code owns assignment.
var sequence := 0


## A cutting line between two points.
static func beam(from: Vector3, to: Vector3, beam_radius: float,
		damage: float) -> DamageHit:
	var hit := DamageHit.new()
	hit.kind = Kind.BEAM
	hit.shape = Shape.CAPSULE
	hit.origin = from
	hit.toward = to
	hit.radius = maxf(beam_radius, 0.01)
	hit.amount = damage
	return hit


## A point contact with no spread.
static func impact(at: Vector3, impact_radius: float,
		damage: float) -> DamageHit:
	var hit := DamageHit.new()
	hit.kind = Kind.IMPACT
	hit.shape = Shape.CAPSULE
	hit.origin = at
	hit.toward = at
	hit.radius = maxf(impact_radius, 0.01)
	hit.amount = damage
	return hit


## A spread that dissipates toward its edge.
static func area(at: Vector3, area_radius: float, damage: float,
		edge_falloff := 1.0) -> DamageHit:
	var hit := DamageHit.new()
	hit.kind = Kind.AREA
	hit.shape = Shape.CAPSULE
	hit.origin = at
	hit.toward = at
	hit.radius = maxf(area_radius, 0.01)
	hit.amount = damage
	hit.falloff = clampf(edge_falloff, 0.0, 1.0)
	return hit


## A flat-ended volume running from [param from] to [param to].
static func cylinder(from: Vector3, to: Vector3, cylinder_radius: float,
		damage: float, edge_falloff := 0.0) -> DamageHit:
	var hit := DamageHit.new()
	hit.kind = Kind.AREA
	hit.shape = Shape.CYLINDER
	hit.origin = from
	hit.toward = to
	hit.radius = maxf(cylinder_radius, 0.01)
	hit.amount = damage
	hit.falloff = clampf(edge_falloff, 0.0, 1.0)
	return hit


func set_source(source: Node, peer := -1) -> DamageHit:
	if source == null:
		return self
	var world := game_world_of(source)
	if world != null:
		source_path = world.get_path_to(source)
	if peer >= 0:
		source_peer = peer
	elif source.has_method(&"combat_peer_id"):
		source_peer = int(source.call(&"combat_peer_id"))
	return self


func with_status(id: StringName, duration: float) -> DamageHit:
	status = id
	status_duration = maxf(duration, 0.0)
	return self


## Middle of the volume, which is what a field measures its tiles against.
## Offers a hit to every in-world flora field and, on the host, every eligible
## combatant. Returns how much was absorbed.
##
## [param anywhere] is any node already in the tree; only its tree is used. The
## Groups are the addressing; filtering by the containing GameWorld prevents
## sibling ENet test worlds from hearing each other's events.
static func apply_to_world(anywhere: Node, hit: DamageHit) -> float:
	if hit == null:
		return 0.0
	var absorbed := apply_to_fields(anywhere, hit) if hit.affects_flora else 0.0
	if hit.affects_combatants:
		absorbed += apply_to_buildings(anywhere, hit)
	# Flora is deterministic and therefore applied by every peer. Actors are
	# canonical only on the host.
	if not hit.affects_combatants:
		return absorbed
	return absorbed + apply_to_combatants(anywhere, hit)


## The flora half on its own.
##
## Split out because what a blast does to a jungle and what it does to the people
## standing in it are not always the same size. Flattening scales with the ground
## it covers — every plant inside is tested, charred or broken, and each break is
## its own effect — so a wide push that also uprooted everything it pushed was a
## quarter of a second in one frame.
static func apply_to_fields(anywhere: Node, hit: DamageHit) -> float:
	if anywhere == null or hit == null or not anywhere.is_inside_tree():
		return 0.0
	if game_world_of(anywhere) == null:
		return 0.0
	var absorbed := 0.0
	for field in anywhere.get_tree().get_nodes_in_group(FIELD_GROUP):
		if field is Node and in_same_world(anywhere, field) \
				and field.has_method(&"apply_damage"):
			absorbed += float(field.call(&"apply_damage", hit))
	return absorbed


## Painted city lots. Deterministic like flora, so every peer wrecks the same
## buildings from the same volume.
static func apply_to_buildings(anywhere: Node, hit: DamageHit) -> float:
	if anywhere == null or hit == null or not anywhere.is_inside_tree():
		return 0.0
	var absorbed := 0.0
	var has_world := game_world_of(anywhere) != null
	for node in anywhere.get_tree().get_nodes_in_group(BUILDING_GROUP):
		var city := node as PatchCity
		if city == null or not city.has_method(&"apply_damage"):
			continue
		if has_world and not in_same_world(anywhere, city):
			continue
		absorbed += city.apply_damage(hit)
	return absorbed


## The actor half on its own. Host authority, as every hit on a body is.
static func apply_to_combatants(anywhere: Node, hit: DamageHit) -> float:
	if anywhere == null or hit == null or not anywhere.is_inside_tree():
		return 0.0
	if game_world_of(anywhere) == null or not _is_host(anywhere):
		return 0.0
	var absorbed := 0.0
	var source := hit.source_node(anywhere)
	for combatant_variant: Variant in anywhere.get_tree().get_nodes_in_group(
			COMBATANT_GROUP):
		var combatant := combatant_variant as Node
		if combatant == null or not in_same_world(anywhere, combatant) \
				or combatant == source or not hit.affects_combatant(combatant):
			continue
		# Resolve radial falloff against the target's body bounds before handing
		# over the immutable event. Flora already calls damage_at per instance;
		# combatants need the same dissipating-area contract.
		var delivered := hit if hit.falloff <= 0.0 \
				and hit.radial_impulse <= 0.0 and hit.radial_lift <= 0.0 \
			else hit.resolved_for(combatant)
		if hit.blocked_by_world and hit._world_blocks(anywhere, source, combatant):
			continue
		var result: Variant = combatant.call(&"apply_damage", delivered)
		var dealt := float(result) if result is float or result is int else 0.0
		absorbed += maxf(dealt, 0.0)
		if dealt > 0.0 and source != null \
				and source.has_method(&"combat_damage_dealt"):
			source.call(&"combat_damage_dealt", combatant, dealt, delivered)
	return absorbed


static func game_world_of(node: Node) -> GameWorld:
	var walk := node
	while walk != null:
		if walk is GameWorld:
			return walk as GameWorld
		walk = walk.get_parent()
	return null


static func in_same_world(a: Node, b: Node) -> bool:
	var a_world := game_world_of(a)
	return a_world != null and a_world == game_world_of(b)


static func _is_host(anywhere: Node) -> bool:
	return not anywhere.multiplayer.has_multiplayer_peer() \
		or anywhere.multiplayer.is_server()


## What to call whoever authored this hit, for a death notice or a kill feed.
## Empty when the attacker cannot be named — a fall, a hazard, or a source that
## has already left the tree — which reads better as "You died" than as a guess.
func attacker_name(anywhere: Node) -> String:
	var source := source_node(anywhere)
	if source != null and source.has_method(&"combat_display_name"):
		var named := String(source.call(&"combat_display_name"))
		if not named.is_empty():
			return named
	if source_peer > 0:
		return String(NetworkManager.get_player_metadata(source_peer).get(
			"name", "Player"))
	return ""


## Human-readable attack carried by this hit, or empty for a generic strike.
func ability_display_name() -> String:
	return String(ABILITY_DISPLAY_NAMES.get(ability_id, ""))


func source_node(anywhere: Node) -> Node:
	var world := game_world_of(anywhere)
	if world == null or source_path.is_empty() or source_path.is_absolute():
		return null
	for index in source_path.get_name_count():
		if source_path.get_name(index) == &"..":
			return null
	return world.get_node_or_null(source_path)


func affects_combatant(combatant: Node) -> bool:
	if combatant == null or not combatant.has_method(&"apply_damage") \
			or not combatant.has_method(&"combat_faction"):
		return false
	var target_faction := int(combatant.call(&"combat_faction"))
	match faction:
		Faction.PLAYER:
			if target_faction != Faction.ENEMY:
				return false
		Faction.ENEMY:
			if target_faction != Faction.PLAYER:
				return false
	if target_peer > 0:
		if not combatant.has_method(&"combat_peer_id") \
				or int(combatant.call(&"combat_peer_id")) != target_peer:
			return false
	var point := Vector3.ZERO
	if combatant.has_method(&"combat_position"):
		point = combatant.call(&"combat_position") as Vector3
	elif combatant is Node3D:
		point = (combatant as Node3D).global_position
	else:
		return false
	if not point.is_finite():
		return false
	var bounds := 0.0
	if combatant.has_method(&"combat_radius"):
		bounds = maxf(float(combatant.call(&"combat_radius")), 0.0)
	return reaches(point, bounds)


func centre() -> Vector3:
	return (origin + toward) * 0.5


## Distance from the centre out to the furthest point the volume can touch. A
## field uses this to reject whole tiles with one comparison.
func extent() -> float:
	return origin.distance_to(toward) * 0.5 + radius


## Shortest distance from a point to the capsule's axis.
func distance_to(point: Vector3) -> float:
	var along := toward - origin
	var length_squared := along.length_squared()
	if length_squared < 0.000001:
		return point.distance_to(origin)
	var raw_share := (point - origin).dot(along) / length_squared
	if shape == Shape.CYLINDER and (raw_share < 0.0 or raw_share > 1.0):
		return INF
	var share := clampf(raw_share, 0.0, 1.0)
	return point.distance_to(origin + along * share)


## Share of [member amount] a point receives, 0 outside the volume.
func share_at(point: Vector3) -> float:
	var away := distance_to(point)
	if away >= radius:
		return 0.0
	if falloff <= 0.0:
		return 1.0
	return lerpf(1.0, 1.0 - falloff, away / radius)


## Damage a point receives, before the target's own toughness.
func damage_at(point: Vector3) -> float:
	return amount * share_at(point)


## A per-combatant copy whose amount includes radial falloff at the nearest
## point on the target's spherical combat bounds. The authored hit remains
## untouched and can still be offered to every other target and flora field.
func resolved_for(combatant: Node) -> DamageHit:
	var delivered := _copy()
	var point := _combatant_position(combatant)
	if not point.is_finite():
		delivered.amount = 0.0
		return delivered
	var bounds := _combatant_radius(combatant)
	var away := 0.0
	if shape == Shape.CYLINDER:
		if _cylinder_solid_distance(point) > bounds:
			delivered.amount = 0.0
			return delivered
		away = maxf(_radial_axis_distance(point) - bounds, 0.0)
	else:
		away = maxf(distance_to(point) - bounds, 0.0)
	var share := _share_for_distance(away)
	delivered.amount = amount * share
	if radial_impulse > 0.0 or radial_lift > 0.0:
		var up := Vector3.UP
		if combatant is Node3D:
			up = (combatant as Node3D).global_basis.y.normalized()
		var outward := point - centre()
		if outward.length_squared() < 0.001:
			outward = up
		else:
			outward = outward.normalized()
		delivered.world_impulse += outward * radial_impulse * share \
			+ up * radial_lift * share
	return delivered


func _world_blocks(anywhere: Node, source: Node, combatant: Node) -> bool:
	if anywhere == null or combatant == null or not anywhere.is_inside_tree():
		return false
	var to := _combatant_position(combatant)
	var from := centre()
	if not from.is_finite() or not to.is_finite() \
			or from.distance_squared_to(to) < 0.001:
		return false
	var query := PhysicsRayQueryParameters3D.create(from, to, 1)
	var excluded := rid_list()
	if source is CollisionObject3D:
		excluded.append((source as CollisionObject3D).get_rid())
	query.collide_with_areas = false
	if not anywhere is Node3D:
		return false
	var space := (anywhere as Node3D).get_world_3d().direct_space_state
	# Combatants do not shield one another from a blast. Walk past up to eight
	# bodies until the ray reaches its target or finds actual world geometry.
	for _step in 8:
		query.exclude = excluded
		var hit := space.intersect_ray(query)
		if hit.is_empty():
			return false
		var collider := hit.get("collider") as Node
		var walk := collider
		var other_combatant: Node
		while walk != null:
			if walk == combatant:
				return false
			if other_combatant == null \
					and walk.is_in_group(COMBATANT_GROUP):
				other_combatant = walk
			walk = walk.get_parent()
		if other_combatant == null:
			return true
		if collider is CollisionObject3D:
			excluded.append((collider as CollisionObject3D).get_rid())
			continue
		return false
	return false


## Whether a sphere of [param bounds] around [param at] can touch this volume at
## all. Deliberately generous: it is the cheap test that lets a field skip a
## tile without decoding a single instance transform.
func reaches(at: Vector3, bounds: float) -> bool:
	if shape == Shape.CYLINDER:
		return _cylinder_solid_distance(at) <= maxf(bounds, 0.0)
	return distance_to(at) <= radius + maxf(bounds, 0.0)


## Whether this volume overlaps a capsule from [param a] to [param b].
##
## Buildings are tall relative to their plan, so a sphere at mid-height misses
## a strike on the crown. Treating the lot as a vertical capsule keeps the hit
## on the storey that was actually struck.
func reaches_segment(a: Vector3, b: Vector3, bounds: float) -> bool:
	var pad := radius + maxf(bounds, 0.0)
	if shape == Shape.CYLINDER:
		return _segment_distance(origin, toward, a, b) <= pad \
			and _cylinder_overlaps_segment(a, b, pad)
	return _segment_distance(origin, toward, a, b) <= pad


func _cylinder_overlaps_segment(a: Vector3, b: Vector3, pad: float) -> bool:
	var along := toward - origin
	var length := along.length()
	if length < 0.000001:
		return a.distance_to(origin) <= pad or b.distance_to(origin) <= pad
	var axis := along / length
	for point_variant in [a, b, a.lerp(b, 0.5)]:
		var point: Vector3 = point_variant
		var axial := (point - origin).dot(axis)
		if axial >= -pad and axial <= length + pad:
			return true
	return false


func _segment_distance(p1: Vector3, q1: Vector3, p2: Vector3, q2: Vector3) -> float:
	var d1 := q1 - p1
	var d2 := q2 - p2
	var r := p1 - p2
	var a := d1.length_squared()
	var e := d2.length_squared()
	var s := 0.0
	var t := 0.0
	if a <= 0.0000001 and e <= 0.0000001:
		return p1.distance_to(p2)
	if a <= 0.0000001:
		t = clampf(d2.dot(r) / e, 0.0, 1.0)
	elif e <= 0.0000001:
		s = clampf(-d1.dot(r) / a, 0.0, 1.0)
	else:
		var b := d1.dot(d2)
		var c := d1.dot(r)
		var f := d2.dot(r)
		var denom := a * e - b * b
		if denom > 0.0000001:
			s = clampf((b * f - c * e) / denom, 0.0, 1.0)
		t = (b * s + f) / e
		if t < 0.0:
			t = 0.0
			s = clampf(-c / a, 0.0, 1.0)
		elif t > 1.0:
			t = 1.0
			s = clampf((b - c) / a, 0.0, 1.0)
	return (p1 + d1 * s).distance_to(p2 + d2 * t)


func _radial_axis_distance(point: Vector3) -> float:
	var along := toward - origin
	var length_squared := along.length_squared()
	if length_squared < 0.000001:
		return point.distance_to(origin)
	var share := (point - origin).dot(along) / length_squared
	return point.distance_to(origin + along * share)


## Shortest distance from a point to the solid finite cylinder. This keeps
## spherical combat bounds generous at a flat cap without turning the authored
## cylinder into a capsule around its corners.
func _cylinder_solid_distance(point: Vector3) -> float:
	var along := toward - origin
	var length := along.length()
	if length < 0.000001:
		return maxf(point.distance_to(origin) - radius, 0.0)
	var axis := along / length
	var relative := point - origin
	var axial := relative.dot(axis)
	var radial := (relative - axis * axial).length()
	var axial_gap := maxf(maxf(-axial, axial - length), 0.0)
	var radial_gap := maxf(radial - radius, 0.0)
	return Vector2(axial_gap, radial_gap).length()


func _share_for_distance(away: float) -> float:
	if not is_finite(away) or away >= radius:
		return 0.0
	if falloff <= 0.0:
		return 1.0
	return lerpf(1.0, 1.0 - falloff, away / radius)


func _combatant_position(combatant: Node) -> Vector3:
	if combatant == null:
		return Vector3(INF, INF, INF)
	if combatant.has_method(&"combat_position"):
		var value: Variant = combatant.call(&"combat_position")
		if value is Vector3:
			return value
	if combatant is Node3D:
		return (combatant as Node3D).global_position
	return Vector3(INF, INF, INF)


func _combatant_radius(combatant: Node) -> float:
	if combatant != null and combatant.has_method(&"combat_radius"):
		return maxf(float(combatant.call(&"combat_radius")), 0.0)
	return 0.0


func _copy() -> DamageHit:
	var copy := DamageHit.new()
	copy.amount = amount
	copy.origin = origin
	copy.toward = toward
	copy.radius = radius
	copy.kind = kind
	copy.shape = shape
	copy.falloff = falloff
	copy.min_plant_height = min_plant_height
	copy.max_plant_height = max_plant_height
	copy.affects_flora = affects_flora
	copy.affects_combatants = affects_combatants
	copy.plant_break_effects = plant_break_effects
	copy.source_peer = source_peer
	copy.ability_id = ability_id
	copy.source_path = source_path
	copy.target_peer = target_peer
	copy.faction = faction
	copy.reaction = reaction
	copy.world_impulse = world_impulse
	copy.radial_impulse = radial_impulse
	copy.radial_lift = radial_lift
	copy.blocked_by_world = blocked_by_world
	copy.status = status
	copy.status_duration = status_duration
	copy.parryable = parryable
	copy.reflection = reflection
	copy.sequence = sequence
	return copy


## The wire form. Effect volumes replicate rather than per-instance damage, so
## every peer applies the identical shape to its own deterministic flora.
func to_wire() -> Dictionary:
	return {
		"amount": amount,
		"origin": origin,
		"toward": toward,
		"radius": radius,
		"kind": int(kind),
		"shape": int(shape),
		"falloff": falloff,
		"min_plant_height": min_plant_height,
		"max_plant_height": max_plant_height,
		"affects_flora": affects_flora,
		"affects_combatants": affects_combatants,
		"plant_break_effects": plant_break_effects,
		"source_peer": source_peer,
		"ability_id": ability_id,
		"source_path": String(source_path),
		"target_peer": target_peer,
		"faction": int(faction),
		"reaction": int(reaction),
		"world_impulse": world_impulse,
		"radial_impulse": radial_impulse,
		"radial_lift": radial_lift,
		"blocked_by_world": blocked_by_world,
		"status": String(status),
		"status_duration": status_duration,
		"parryable": parryable,
		"reflection": reflection,
		"sequence": sequence,
	}


static func from_wire(wire: Dictionary) -> DamageHit:
	var hit := DamageHit.new()
	var amount_value := float(wire.get("amount", 0.0))
	hit.amount = maxf(amount_value, 0.0) if is_finite(amount_value) else 0.0
	hit.origin = _finite_vector(wire.get("origin", Vector3.ZERO))
	hit.toward = _finite_vector(wire.get("toward", hit.origin), hit.origin)
	var radius_value := float(wire.get("radius", 1.0))
	hit.radius = maxf(radius_value, 0.01) if is_finite(radius_value) else 1.0
	hit.kind = clampi(int(wire.get("kind", Kind.IMPACT)), 0, Kind.size() - 1) \
		as Kind
	hit.shape = clampi(int(wire.get("shape", Shape.CAPSULE)), 0,
		Shape.size() - 1) as Shape
	var falloff_value := float(wire.get("falloff", 0.0))
	hit.falloff = clampf(falloff_value, 0.0, 1.0) \
		if is_finite(falloff_value) else 0.0
	var shortest_value := float(wire.get("min_plant_height", 0.0))
	hit.min_plant_height = maxf(shortest_value, 0.0) \
		if is_finite(shortest_value) else 0.0
	var tallest_value := float(wire.get("max_plant_height", 0.0))
	hit.max_plant_height = maxf(tallest_value, 0.0) \
		if is_finite(tallest_value) else 0.0
	hit.affects_flora = bool(wire.get("affects_flora", true))
	hit.affects_combatants = bool(wire.get("affects_combatants", true))
	hit.plant_break_effects = bool(wire.get("plant_break_effects", true))
	hit.source_peer = maxi(int(wire.get("source_peer", 0)), 0)
	hit.ability_id = String(wire.get("ability_id", ""))
	hit.source_path = NodePath(String(wire.get("source_path", "")))
	hit.target_peer = maxi(int(wire.get("target_peer", 0)), 0)
	hit.faction = clampi(int(wire.get("faction", Faction.NEUTRAL)), 0,
		Faction.size() - 1) as Faction
	hit.reaction = clampi(int(wire.get("reaction", Reaction.NONE)), 0,
		Reaction.size() - 1) as Reaction
	hit.world_impulse = _finite_vector(wire.get("world_impulse", Vector3.ZERO))
	var radial_value := float(wire.get("radial_impulse", 0.0))
	hit.radial_impulse = maxf(radial_value, 0.0) \
		if is_finite(radial_value) else 0.0
	var lift_value := float(wire.get("radial_lift", 0.0))
	hit.radial_lift = maxf(lift_value, 0.0) if is_finite(lift_value) else 0.0
	hit.blocked_by_world = bool(wire.get("blocked_by_world", false))
	hit.status = StringName(String(wire.get("status", "")))
	var duration_value := float(wire.get("status_duration", 0.0))
	hit.status_duration = clampf(
		duration_value, 0.0, CombatStatuses.MAX_DURATION) \
		if is_finite(duration_value) else 0.0
	hit.parryable = bool(wire.get("parryable", false))
	var reflection_value := float(wire.get("reflection", 0.0))
	hit.reflection = maxf(reflection_value, 0.0) \
		if is_finite(reflection_value) else 0.0
	hit.sequence = maxi(int(wire.get("sequence", 0)), 0)
	return hit


## Removes every enemy-authored consequence from a client hero packet.
static func sanitize_player_packet(wire: Dictionary, sender: int,
		source: Node) -> DamageHit:
	var hit := from_wire(wire)
	hit.source_peer = maxi(sender, 0)
	hit.faction = Faction.PLAYER
	hit.target_peer = 0
	hit.reaction = Reaction.NONE
	hit.world_impulse = Vector3.ZERO
	hit.radial_impulse = 0.0
	hit.radial_lift = 0.0
	hit.blocked_by_world = false
	hit.status = &""
	hit.status_duration = 0.0
	hit.parryable = false
	hit.reflection = 0.0
	hit.amount = clampf(hit.amount, 0.0, 100000.0)
	hit.source_path = NodePath()
	hit.set_source(source, sender)
	return hit


static func _finite_vector(value: Variant,
		fallback := Vector3.ZERO) -> Vector3:
	if value is Vector3 and (value as Vector3).is_finite():
		return value as Vector3
	return fallback
