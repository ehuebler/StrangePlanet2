class_name LaserEyes
extends Ability

## Two beams out of the eyes, converging on whatever the player is looking at.
##
## The beams cut everything standing along their length, not only what they
## land on: a stand of grass between the player and a boulder is gone before the
## boulder starts to glow. That is why the damage is a capsule swept from the
## face to the landing point rather than a hit at the end of a ray, and it is
## the difference between this and the carbine.
##
## Nothing about the body changes while it fires. There is no clip and no pose:
## the player walks, runs, flies and swims exactly as before, with the beams
## following the head. The one place it will not work is under water, which is
## why [member Ability.blocked_underwater] exists at all.
##
## Damage runs at a fixed [constant DAMAGE_HZ] rather than every physics tick,
## because each tick is also a packet: every peer applies the same volume to its
## own copy of the flora, which is deterministic from the seed, so the beam
## clears the same plants on every machine without anything being told which
## plants those were.

## How often damage lands and a beam packet goes out. Ten a second is fine
## enough that sweeping the beam leaves a continuous cut, and coarse enough to
## be a sane packet rate for something that can be held for four seconds.
const DAMAGE_HZ := 10.0
const DAMAGE_STEP := 1.0 / DAMAGE_HZ

## How much of a tick's damage the landing point gets on top of what the beam
## has already dealt along its length. The requirement is damage along the beam
## *and* where it lands, and this is the "and".
const IMPACT_SHARE := 2.0
## Metres around the landing point that share gets spread over.
const IMPACT_RADIUS := 1.4

## Seconds the beam has to sit on one spot before it burns a mark into the
## ground. Below this it is being swept, and a swept beam leaves soot rather
## than a trench.
const SCAR_DWELL := 0.25
## How far the landing point may wander before it counts as a different spot.
const SCAR_SPACING := 1.5
const SCAR_RADIUS := 2.0
const SCAR_DEPTH := 0.2
const SCAR_CHAR := 0.9

## Radius of the immediate soot mark, which is wider and much fainter than the
## trench. The mesh is about 1.5 m per vertex at its finest, so the baked tint
## alone cannot draw a burn this small; the decal is what makes it read.
const SCORCH_RADIUS := 1.5
## How far the landing may travel before a new soot mark is laid. Dust already
## relocates at a similar distance; matching it keeps a sweep from stamping a
## decal ten times a second.
const SCORCH_SPACING := 0.75

## Plant colliders a beam will pass through before it gives up looking for
## something solid. Used only when a field's cached bodies are stale and a
## leftover trunk still sits on the ray.
const MAX_FLORA_PIERCED := 2

var _left := 0.0
var _since_damage := 0.0
var _gap_left := 0.0
## Direction from the planet centre to the spot the beam is currently sitting
## on, or the zero vector when it is not landing on anything.
var _dwell_at := Vector3.ZERO
var _dwell := 0.0
var _dwell_burned := false


func _press() -> bool:
	_gap_left = 0.0
	_left = stat("duration", 4.0)
	_since_damage = DAMAGE_STEP
	_forget_dwell()
	if _left <= 0.0:
		return false
	# Aim on the press frame, not the next physics tick, so the first drawn
	# beam is already leaving the eyes.
	_aim_beams()
	return true


func _pulse_mode() -> bool:
	# Crawler keeps a cooldown between bursts. Damage inside a burst is still
	# a rate: duration is how long the beam cooks, not a one-shot projectile.
	return cooldown() > 0.0 and stat("duration", 4.0) <= 1.0


func _tick(delta: float) -> void:
	# Walking into the sea with the beam on ends it, the same as trying to start
	# it there. Checked before the duration so the refusal is immediate.
	if player.submerged_share() > 0.0:
		release()
		return
	if _pulse_mode():
		_tick_pulse(delta)
		return
	_left -= delta
	if _left <= 0.0:
		release()
		return

	var shot := _aim_beams()
	_step_damage(delta, shot["eyes"], shot["at"], bool(shot["landed"]))


func _tick_pulse(delta: float) -> void:
	if _gap_left > 0.0:
		_gap_left = maxf(_gap_left - delta, 0.0)
		if _gap_left > 0.0:
			return
		_left = stat("duration", 0.4)
		_since_damage = DAMAGE_STEP
		_forget_dwell()
		return
	_left -= delta
	if _left <= 0.0:
		player.laser_beams().stop()
		_forget_dwell()
		_gap_left = cooldown()
		return
	var shot := _aim_beams()
	_step_damage(delta, shot["eyes"], shot["at"], bool(shot["landed"]))


func _aim_beams() -> Dictionary:
	var empty: Array[Vector3] = [Vector3.ZERO, Vector3.ZERO]
	if player == null:
		return {"eyes": empty, "at": Vector3.ZERO, "landed": false}
	var eyes := player.eye_points()
	var from: Vector3 = (eyes[0] + eyes[1]) * 0.5
	var landing := _landing(from)
	var at: Vector3 = landing["at"]
	player.laser_beams().aim(
		eyes[0], eyes[1], at, LaserBeams.COLOR, _beam_width(), _wobble_amount())
	return {"eyes": eyes, "at": at, "landed": landing["landed"]}


func _step_damage(delta: float, eyes: Array, at: Vector3, landed: bool) -> void:
	_since_damage += delta
	if _since_damage < DAMAGE_STEP:
		return
	_since_damage -= DAMAGE_STEP
	player.fire_beam(
		ability_id, eyes[0], eyes[1], at, landed,
		_beam_radius(), _beam_width(), _wobble_amount())
	if landed:
		# A damage step's worth, not a tick's: this runs once per step, so
		# adding the tick delta would count time at a sixth of its real rate
		# and the groove would take six times as long to appear as it reads.
		_burn(at, DAMAGE_STEP)
	else:
		_forget_dwell()


func _release() -> void:
	if player != null:
		player.laser_beams().stop()
	_forget_dwell()


## Where the beam stops, and whether it stopped on something or ran out of
## range. Flora is not in the answer: almost none of it has a collider, and a
## beam that cuts through a field of grass should not be stopped by the first
## blade of it either.
func _landing(from: Vector3) -> Dictionary:
	var reach := stat("range", 60.0)
	var along := _aim_along(from)
	var to := from + along * reach
	var hit := _surface(player, from, to)
	if hit.is_empty():
		return {"at": to, "landed": false}
	return {"at": hit["position"], "landed": true}


## What the beam runs into between two points, or nothing.
##
## Plants are skipped rather than hit. The big ones do have colliders — convex
## hulls and trimeshes — and piercing them one at a time while the head turns
## was eight physics queries a tick. Excluding every live flora body first
## finds the hillside in one ray. The capsule along the beam still cuts the
## plants; they just do not stop it.
static func _surface(shooter: OnlinePlayer, from: Vector3,
		to: Vector3) -> Dictionary:
	var query := PhysicsRayQueryParameters3D.create(from, to)
	var ignored := DamageHit.rid_list(shooter.get_rid())
	_exclude_flora(shooter, ignored)
	var space := shooter.get_world_3d().direct_space_state
	query.exclude = ignored
	var hit := space.intersect_ray(query)
	if hit.is_empty() or not _is_flora(hit):
		return hit
	# A body dressed after the cached RID list was built. Skip it and try once
	# more rather than walking the whole wood again.
	for _through in MAX_FLORA_PIERCED:
		var rid: RID = hit.get("rid", RID())
		if not rid.is_valid():
			return {}
		ignored.append(rid)
		query.exclude = ignored
		hit = space.intersect_ray(query)
		if hit.is_empty() or not _is_flora(hit):
			return hit
	return {}


## Appends every flora collision body in this world so one ray can ignore them.
static func _exclude_flora(anywhere: Node, ignored: Array[RID]) -> void:
	if anywhere == null or not anywhere.is_inside_tree():
		return
	for field_variant: Variant in anywhere.get_tree().get_nodes_in_group(
			DamageHit.FIELD_GROUP):
		var field := field_variant as Node
		if field == null or not DamageHit.in_same_world(anywhere, field) \
				or not field.has_method(&"collision_rids"):
			continue
		var extra: Variant = field.call(&"collision_rids")
		if extra is Array:
			ignored.append_array(extra)


## The first real terrain face between two points. Planet terrain colliders are
## internal StaticBody3Ds parented directly to Planet; requiring that exact
## relationship keeps a delayed terrain mark off props, actors and barriers.
static func terrain_surface(shooter: OnlinePlayer, from: Vector3,
		to: Vector3) -> Dictionary:
	var hit := _surface(shooter, from, to)
	if hit.is_empty():
		return {}
	var world_planet := shooter.planet()
	var collider := hit.get("collider") as Node
	if world_planet == null or collider == null \
			or collider.get_parent() != world_planet:
		return {}
	return hit


## Whether a ray hit a plant. Both fields hang the ownership metadata on the
## individual [CollisionShape3D] rather than on the body, because one body
## carries a whole tile of plants, so the shape has to be resolved before the
## question can be asked.
static func _is_flora(hit: Dictionary) -> bool:
	var body := hit.get("collider") as CollisionObject3D
	if body == null:
		return false
	var shape := body.shape_owner_get_owner(
		body.shape_find_owner(int(hit.get("shape", 0)))) as Node
	return shape != null and shape.has_meta(GroundCover.IMPACT_OWNER_META)


## Counts up how long the beam has rested on one spot and cuts the groove once
## it has been there long enough.
func _burn(at: Vector3, delta: float) -> void:
	var world_planet := player.planet()
	if world_planet == null:
		return
	var direction := world_planet.to_local(at).normalized()
	if direction.length_squared() < 0.5:
		return
	var moved := _dwell_at == Vector3.ZERO \
		or direction.distance_to(_dwell_at) * world_planet.shape.radius \
			> SCAR_SPACING
	if moved:
		_dwell_at = direction
		_dwell = 0.0
		_dwell_burned = false
	_dwell += delta
	if _dwell_burned or _dwell < SCAR_DWELL:
		return
	_dwell_burned = true
	var scar := TerrainScars.Scar.new()
	scar.direction = direction
	scar.radius = SCAR_RADIUS
	scar.depth = SCAR_DEPTH
	scar.profile = TerrainScars.Profile.GROOVE
	scar.char = SCAR_CHAR
	player.request_scar(scar)


func _forget_dwell() -> void:
	_dwell_at = Vector3.ZERO
	_dwell = 0.0
	_dwell_burned = false


## One tick of beam, applied on every machine.
##
## Static, and reached from the player's beam RPC rather than from an ability
## instance, because only the firing player has an ability at all. Everyone else
## runs exactly this and nothing else, which is what keeps the flora the same on
## all of them.
func _aim_along(from: Vector3) -> Vector3:
	return player.aim_direction(from)


func _beam_radius() -> float:
	return maxf(stat("radius", 0.45), 0.05)


func _beam_width() -> float:
	return maxf(stat("beam_width", 1.0), 0.35)


func _wobble_amount() -> float:
	return maxf(stat("wobble", 0.0), 0.0)


static func apply_effect(shooter: OnlinePlayer, id: String, left_eye: Vector3,
		right_eye: Vector3, at: Vector3, landed: bool,
		radius := -1.0, beam_width := 1.0, wobble := 0.0, pulse := false) -> void:
	if shooter == null:
		return
	shooter.laser_beams().aim(
		left_eye, right_eye, at, LaserBeams.COLOR, beam_width, wobble)
	var stats := _resolved_stats(shooter, id)
	var per_tick := float(stats.get("damage", 0.0))
	if shooter != null and CrawlerRules.active() \
			and shooter.has_method(&"crawler_damage_scale"):
		per_tick *= float(shooter.call(&"crawler_damage_scale"))
	# Damage is a rate. A crawler burst used to dump the whole number once,
	# which made duration only a visual; each step now pays DAMAGE_STEP of the
	# authored per-second figure for as long as the beam stays on the target.
	per_tick *= DAMAGE_STEP
	if radius < 0.0:
		radius = float(stats.get("radius", 0.4))
	var impact_radius := IMPACT_RADIUS
	if stats.has("impact_radius"):
		impact_radius = float(stats.get("impact_radius", IMPACT_RADIUS))
	elif beam_width > 1.0:
		impact_radius *= beam_width
	var from: Vector3 = (left_eye + right_eye) * 0.5

	var beam := DamageHit.beam(from, at, radius, per_tick)
	beam.ability_id = id
	beam.faction = shooter.combat_faction()
	beam.set_source(shooter, shooter.peer_id)
	# A sweep through a meadow can break hundreds of blades a tick. Each one
	# used to restart a pooled debris burst; the impact dust already says the
	# beam is cutting, and the plants still hide and fall.
	beam.plant_break_effects = false
	var knockback := maxf(float(stats.get("knockback", 0.0)), 0.0)
	if shooter != null and CrawlerRules.active() \
			and shooter.has_method(&"crawler_knockback_scale"):
		knockback *= float(shooter.call(&"crawler_knockback_scale"))
	var along := at - from
	if along.length_squared() > 0.0001:
		along = along.normalized()
	else:
		along = Vector3.ZERO
	if knockback > 0.0 and along != Vector3.ZERO:
		beam.world_impulse = along * knockback * DAMAGE_STEP
	DamageHit.apply_to_world(shooter, beam)

	if not landed:
		return
	var burst := DamageHit.area(at, impact_radius,
		per_tick * IMPACT_SHARE, 1.0)
	burst.ability_id = id
	burst.faction = shooter.combat_faction()
	burst.set_source(shooter, shooter.peer_id)
	burst.plant_break_effects = false
	if knockback > 0.0:
		if along != Vector3.ZERO:
			burst.world_impulse = along * knockback
		burst.radial_impulse = knockback * 0.35
		burst.radial_lift = knockback * 0.12
	DamageHit.apply_to_world(shooter, burst)

	var world_planet := shooter.planet()
	# Laid along the face that was hit rather than along the planet's up, so a
	# burn and its dust on the side of a boulder stay on that face instead of
	# becoming a stripe and a vertical plume. The normal is re-found rather than
	# sent: each peer's own colliders are the ones its effects have to sit on.
	var facing := world_planet.up_at(at) if world_planet != null else Vector3.UP
	var found := _surface(shooter, from, at + (at - from).normalized() * 0.3)
	if not found.is_empty():
		var normal: Vector3 = found["normal"]
		if normal.length_squared() > 0.5:
			facing = normal
	shooter.play_laser_impact_dust(at, facing, true)
	if world_planet == null or world_planet.scorches == null:
		return
	if not shooter.laser_beams().take_scorch(at, SCORCH_SPACING):
		return
	world_planet.scorches.scorch(
		at, facing, SCORCH_RADIUS * maxf(beam_width, 1.0), 0.85)


static func _resolved_stats(shooter: OnlinePlayer, id: String) -> Dictionary:
	if shooter != null and shooter.crawler_kit != null:
		var kit := shooter.crawler_kit
		if shooter.abilities != null:
			for index in shooter.abilities.size():
				var card := kit.equipped_card(index)
				if card != null and card.id == id:
					return kit.stats_for(card)
	return ItemDB.stats_of(id)
