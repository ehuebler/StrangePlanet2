class_name FaunaSpawner
extends Node3D

## Host-authoritative fauna streamed through deterministic spherical cells.
##
## Species own habitat, density, appearance, vitality, temperament, and moves.
## This node only decides which stable cells are live around the current players,
## guarantees authored showcase packs beside Vacationer's Landing, and replicates the
## resulting actors. Unlike flora, mobs carry state, so clients never generate
## their own independent simulation.

const CELL_CACHE_LIMIT := 2048
const GLOBAL_CENTRE_ATTEMPTS := 4
const PACK_PLACEMENT_ATTEMPTS := 6
const COLONY_PLACEMENT_ATTEMPTS := 64
const CACHE_KEEP_GENERATIONS := 3
const FLOOR_CLEARANCE := 0.025
const LIGHT_UPDATE_INTERVAL := 0.05

@export var species: Array[FaunaSpecies] = []
@export var planet_path: NodePath
@export var terrain_claims: NodePath
@export var colony_anchor: NodePath

@export_category("Streaming")
@export_range(0.1, 10.0, 0.05) var survey_interval := 0.75
## Keeps terrain sampling and global actor construction out of the opening frame.
@export_range(0.0, 10.0, 0.05) var initial_survey_delay := 1.5
@export_range(1, 64) var max_spawns_per_survey := 4
@export_range(16, 2048) var candidate_limit_per_species := 256

@export_category("Pooled night lights")
@export_range(0, 24) var light_limit := 7
@export_range(1.0, 500.0) var lights_within := 95.0
@export_range(0.1, 30.0) var light_follow_speed := 9.0
@export_range(0.1, 30.0) var light_fade_speed := 5.0

var _planet: Planet
var _cover: GroundCover
var _colony: Node3D
var _species_by_id: Dictionary = {}
var _grids: Dictionary = {}
var _actors: Dictionary = {}
var _global_ids: Dictionary = {}
var _cell_cache: Dictionary = {}
var _cache_generation := 0
var _pending_states: Dictionary = {}
var _survey_left := 0.0
var _light_elapsed := 0.0
var _built := false
var _last_survey_micros := 0
var _last_survey_placement_checks := 0
var _last_colony_micros := 0
var _last_colony_placement_checks := 0
var _survey_placement_checks := 0

var _lights: Array[OmniLight3D] = []
var _light_actor_ids: PackedStringArray = PackedStringArray()


func _ready() -> void:
	set_process(false)
	if Engine.is_editor_hint():
		return
	call_deferred(&"_build")


func _build() -> void:
	_planet = _find_planet()
	if _planet == null or _planet.shape == null:
		push_error("FaunaSpawner must be under, or point to, a Planet")
		return
	_planet.shape.prepare()
	if not terrain_claims.is_empty():
		_cover = get_node_or_null(terrain_claims) as GroundCover
		if _cover == null:
			push_warning("FaunaSpawner terrain_claims does not point to GroundCover")
	if _cover == null:
		_cover = _planet.get_node_or_null("GlobalGrass") as GroundCover
	if not colony_anchor.is_empty():
		_colony = get_node_or_null(colony_anchor) as Node3D
	if _colony == null:
		_colony = _planet.get_node_or_null("VacationersLanding") as Node3D

	for definition in species:
		if definition == null:
			continue
		for problem in definition.validate():
			push_error("FaunaSpawner: %s" % problem)
		if not definition.enabled:
			continue
		if definition.species_id.is_empty() \
				or _species_by_id.has(definition.species_id):
			push_error("FaunaSpawner has an empty or duplicate species id '%s'"
				% definition.species_id)
			continue
		_species_by_id[definition.species_id] = definition
		definition.prepare()
		if definition.global_population:
			_grids[definition.species_id] = SphericalCoverGrid.new(
				_planet.shape.radius, definition.cell_size)

	_make_light_pool()
	_built = true
	set_physics_process(true)
	if _is_host():
		var colony_began := Time.get_ticks_usec()
		_survey_placement_checks = 0
		_place_colony_populations()
		_last_colony_micros = Time.get_ticks_usec() - colony_began
		_last_colony_placement_checks = _survey_placement_checks
		_survey_left = maxf(initial_survey_delay, 0.0)
	elif multiplayer.has_multiplayer_peer():
		_request_fauna_snapshot.rpc_id(1)
	set_process(true)


func _physics_process(_delta: float) -> void:
	if _built:
		CrawlerMobSense.ensure_frame(get_tree())


func _process(delta: float) -> void:
	if not _built:
		return
	_survey_left -= delta
	if _is_host() and _survey_left <= 0.0:
		_survey_left = maxf(survey_interval, 0.1)
		_survey_global()
	_light_elapsed += delta
	if _light_elapsed >= LIGHT_UPDATE_INTERVAL:
		_update_lights(_light_elapsed)
		_light_elapsed = 0.0


func _find_planet() -> Planet:
	if not planet_path.is_empty():
		var explicit := get_node_or_null(planet_path) as Planet
		if explicit != null:
			return explicit
	var walk := get_parent()
	while walk != null:
		if walk is Planet:
			return walk as Planet
		walk = walk.get_parent()
	return null


# --- Deterministic placement ------------------------------------------------

func _place_colony_populations() -> void:
	if _colony == null:
		if not species.is_empty():
			push_warning("FaunaSpawner has no Vacationer's Landing anchor")
		return
	var anchor_local := _planet.to_local(_colony.global_position)
	if anchor_local.length_squared() < 1.0:
		return
	var anchor := anchor_local.normalized()
	var axes := _tangent_axes(anchor)
	var occupied := PackedVector3Array()
	for definition in species:
		if definition == null or not definition.enabled \
				or definition.colony_count <= 0:
			continue
		var rng := RandomNumberGenerator.new()
		rng.seed = _mixed_seed(
			definition.random_seed, Vector3i(-1, definition.colony_count, 0), 0)
		var near := minf(definition.colony_near, definition.colony_far)
		var far := maxf(definition.colony_near, definition.colony_far)
		for index in definition.colony_count:
			var accepted := {}
			var direction := anchor
			for _attempt in COLONY_PLACEMENT_ATTEMPTS:
				var reach := sqrt(lerpf(near * near, far * far, rng.randf()))
				var angle := rng.randf() * TAU
				direction = (anchor + (
					axes[0] * cos(angle) + axes[1] * sin(angle))
					* (reach / _planet.shape.radius)).normalized()
				accepted = _placement(definition, direction, true)
				if accepted.is_empty() \
						or not _clear_of_colony_mobs(
							accepted["point"] as Vector3, occupied,
							_definition_clearance(definition)):
					accepted = {}
					continue
				break
			if accepted.is_empty():
				push_warning("FaunaSpawner could not place colony %s %d"
					% [definition.species_id, index])
				continue
			var point: Vector3 = accepted["point"]
			occupied.append(point)
			var id := "c_%s_%d" % [definition.species_id, index]
			var record := _record_for(
				definition, id, direction, accepted, rng,
				_mixed_seed(definition.random_seed,
					Vector3i(-1, index, 0), index))
			_spawn_authoritative(record, false)


func _clear_of_colony_mobs(point: Vector3, occupied: PackedVector3Array,
		clearance: float) -> bool:
	for other in occupied:
		if point.distance_to(other) < clearance:
			return false
	return true


func _definition_clearance(definition: FaunaSpecies) -> float:
	return maxf(definition.height * definition.collision_radius_share * 2.4, 1.2)


func _survey_global() -> void:
	var began := Time.get_ticks_usec()
	_survey_placement_checks = 0
	var viewers := _viewer_positions()
	if viewers.is_empty():
		_last_survey_micros = Time.get_ticks_usec() - began
		_last_survey_placement_checks = 0
		return
	_cache_generation += 1
	var desired := {}
	for definition in species:
		if definition == null or not definition.global_population \
				or definition.maximum_instances <= 0:
			continue
		var grid := _grids.get(definition.species_id) as SphericalCoverGrid
		if grid == null:
			continue
		var keys: Array[Vector3i] = []
		var seen := {}
		var enumerate_reach := maxf(
			definition.spawn_within, definition.despawn_beyond)
		for viewer in viewers:
			var local_viewer := _planet.to_local(viewer)
			if local_viewer.length_squared() < 1.0:
				continue
			for key in _candidate_keys(
					grid, local_viewer.normalized(), enumerate_reach):
				if seen.has(key):
					continue
				seen[key] = true
				keys.append(key)
				if keys.size() >= candidate_limit_per_species:
					break
			if keys.size() >= candidate_limit_per_species:
				break

		var candidates: Array[Dictionary] = []
		for key in keys:
			for record_variant: Variant in _records_for_cell(
					definition, grid, key):
				var record := record_variant as Dictionary
				var away := _nearest_distance(
					(record["transform"] as Transform3D).origin, viewers)
				var id := String(record["id"])
				var existing := _actors.has(id)
				if (existing and away > definition.despawn_beyond) \
						or (not existing and away > definition.spawn_within):
					continue
				record = record.duplicate()
				record["away"] = away
				# Existing cells get a small hysteresis advantage so two packs
				# crossing rank do not despawn and respawn every survey.
				record["rank"] = away - (
					definition.cell_size * 0.28 if existing else 0.0)
				candidates.append(record)
		candidates.sort_custom(func(a: Dictionary, b: Dictionary) -> bool:
			var rank_a := float(a["rank"])
			var rank_b := float(b["rank"])
			if not is_equal_approx(rank_a, rank_b):
				return rank_a < rank_b
			return String(a["id"]) < String(b["id"]))
		if candidates.size() > definition.maximum_instances:
			candidates.resize(definition.maximum_instances)
		for record in candidates:
			desired[String(record["id"])] = record

	for id_variant: Variant in _global_ids.keys():
		var id := String(id_variant)
		if not desired.has(id):
			_despawn_authoritative(id)

	var spawn_budget := max_spawns_per_survey
	var wanted_ids := desired.keys()
	wanted_ids.sort()
	for id_variant: Variant in wanted_ids:
		if spawn_budget <= 0:
			break
		var id := String(id_variant)
		if _actors.has(id):
			continue
		_spawn_authoritative(desired[id] as Dictionary, true)
		spawn_budget -= 1
	_prune_cell_cache()
	_last_survey_micros = Time.get_ticks_usec() - began
	_last_survey_placement_checks = _survey_placement_checks


func _candidate_keys(grid: SphericalCoverGrid, eye_direction: Vector3,
		reach: float) -> Array[Vector3i]:
	var axes := _tangent_axes(eye_direction)
	var keys: Array[Vector3i] = []
	var seen := {}
	var rings := ceili(reach / maxf(
		2.0 * grid.radius / float(grid.resolution), 1.0)) + 2
	for ring in rings + 1:
		for row in range(-ring, ring + 1):
			for col in range(-ring, ring + 1):
				if maxi(absi(col), absi(row)) != ring:
					continue
				var offset := Vector2(col, row) \
					* (2.0 * grid.radius / float(grid.resolution))
				if offset.length() > reach + 2.0 * grid.radius \
						/ float(grid.resolution):
					continue
				var direction := (
					eye_direction + (axes[0] * offset.x + axes[1] * offset.y)
					/ _planet.shape.radius).normalized()
				var key := grid.key_for(direction)
				if seen.has(key):
					continue
				seen[key] = true
				keys.append(key)
				if keys.size() >= candidate_limit_per_species:
					return keys
	return keys


func _records_for_cell(definition: FaunaSpecies, grid: SphericalCoverGrid,
		key: Vector3i) -> Array:
	var cache_key := "%s:%d:%d:%d" % [
		definition.species_id, key.x, key.y, key.z]
	if _cell_cache.has(cache_key):
		var cached := _cell_cache[cache_key] as Dictionary
		cached["seen"] = _cache_generation
		return cached["records"] as Array
	var records: Array = []
	var rng := RandomNumberGenerator.new()
	rng.seed = _mixed_seed(definition.random_seed, key, 0)
	if rng.randf() <= definition.spawn_chance:
		var centre := grid.centre(key)
		var centre_placement := {}
		for _attempt in GLOBAL_CENTRE_ATTEMPTS:
			centre = grid.direction_in(
				key, rng.randf_range(0.16, 0.84), rng.randf_range(0.16, 0.84))
			centre_placement = _placement(definition, centre, false)
			if not centre_placement.is_empty():
				break
		if not centre_placement.is_empty():
			var count := rng.randi_range(
				definition.pack_min, definition.pack_max)
			var axes := _tangent_axes(centre)
			for index in count:
				var direction := centre
				var accepted := centre_placement if index == 0 else {}
				if index > 0:
					for _attempt in PACK_PLACEMENT_ATTEMPTS:
						var reach := sqrt(rng.randf()) * definition.pack_radius
						var angle := rng.randf() * TAU
						direction = (centre + (
							axes[0] * cos(angle) + axes[1] * sin(angle))
							* (reach / _planet.shape.radius)).normalized()
						accepted = _placement(definition, direction, false)
						if not accepted.is_empty():
							break
				if accepted.is_empty():
					continue
				var id := "g_%s_%d_%d_%d_%d" % [
					definition.species_id, key.x, key.y, key.z, index]
				records.append(_record_for(
					definition, id, direction, accepted, rng,
					_mixed_seed(definition.random_seed, key, index + 1)))
	_cell_cache[cache_key] = {
		"records": records,
		"seen": _cache_generation,
	}
	return records


func _record_for(definition: FaunaSpecies, id: String, direction: Vector3,
		placement: Dictionary, rng: RandomNumberGenerator, seed: int) -> Dictionary:
	var normal: Vector3 = placement["normal"]
	var axes := _tangent_axes(normal)
	var heading := axes[0].rotated(normal, rng.randf() * TAU)
	var local_transform := Transform3D(
		_upright_basis(heading, normal), placement["point"] as Vector3)
	return {
		"id": id,
		"species_id": definition.species_id,
		"seed": seed,
		"transform": _planet.global_transform * local_transform,
		"biome": placement.get("biome", Color.WHITE),
	}


func _placement(definition: FaunaSpecies, direction: Vector3,
		colony_showcase: bool) -> Dictionary:
	_survey_placement_checks += 1
	var at := direction.normalized()
	var spacing := _planet.finest_spacing()
	var elevation := _planet.shape.elevation(at, spacing)
	if elevation < minf(definition.above_water, definition.below) \
			or elevation > maxf(definition.above_water, definition.below):
		return {}
	var sample := _planet.shape.sample(at)
	if definition.avoid_inland_water and (
			float(sample.get("river", 0.0)) > 0.0
			or float(sample.get("lake", 0.0)) > 0.0):
		return {}
	var normal := _planet.shape.normal_at(at, spacing).normalized()
	var slope := rad_to_deg(acos(clampf(normal.dot(at), -1.0, 1.0)))
	if slope > definition.max_slope:
		return {}
	if not _steady_enough(definition, at, elevation, spacing):
		return {}
	var biome := _planet.shape.color_at(at, elevation, normal)
	if not colony_showcase:
		var arid := float(sample.get("arid", 0.0))
		if arid < minf(definition.minimum_arid, definition.maximum_arid) \
				or arid > maxf(
					definition.minimum_arid, definition.maximum_arid):
			return {}
		var frost := _planet.shape.frost(at)
		if frost < minf(definition.minimum_frost, definition.maximum_frost) \
				or frost > maxf(
					definition.minimum_frost, definition.maximum_frost):
			return {}
		if definition.ground_layer != PlantSpecies.Ground.ANYWHERE:
			var claimed := _cover.terrain_claims(
				at, elevation, normal, biome, definition.ground_layer,
				definition.minimum_ground_claim) if _cover != null \
				else _fallback_terrain_claim(
					definition, at, elevation, normal, biome)
			if not claimed:
				return {}
	return {
		"height": elevation,
		"normal": normal,
		"biome": biome,
		"point": at * (_planet.shape.radius + elevation + FLOOR_CLEARANCE),
	}


func _steady_enough(definition: FaunaSpecies, direction: Vector3,
		centre_height: float, spacing: float) -> bool:
	if definition.steady_over <= 0.0 or definition.steady_within <= 0.0:
		return true
	var axes := _tangent_axes(direction)
	var step := definition.steady_over / _planet.shape.radius
	var low := centre_height
	var high := centre_height
	for axis in axes:
		for sign_value in [-1.0, 1.0]:
			var sample_direction: Vector3 = (
				direction + axis * step * sign_value).normalized()
			var height := _planet.shape.elevation(sample_direction, spacing)
			low = minf(low, height)
			high = maxf(high, height)
	return high - low <= definition.steady_within


func _fallback_terrain_claim(definition: FaunaSpecies, at: Vector3,
		height: float, normal: Vector3, biome: Color) -> bool:
	var brightest := maxf(maxf(biome.r, biome.g), biome.b)
	var darkest := minf(minf(biome.r, biome.g), biome.b)
	var chroma := brightest - darkest
	var green := clampf(
		(biome.g - maxf(biome.r, biome.b)) * 7.0, 0.0, 1.0)
	var red := clampf(
		(biome.r - maxf(biome.g, biome.b)) * 7.0, 0.0, 1.0)
	var grey := 1.0 - clampf(chroma * 7.0, 0.0, 1.0)
	var cool := clampf((biome.b - biome.r) * 7.0, 0.0, 1.0)
	var pale := maxf(grey, cool) * clampf(
		(brightest - 0.7) * 7.0, 0.0, 1.0)
	var frozen := _planet.shape.frost(at)
	var shore := 1.0 - smoothstep(0.0, 7.0, height)
	var ice := maxf(pale, frozen * 1.3)
	var sand := (red + shore) * (1.0 - minf(ice, 1.0))
	var slope := 1.0 - clampf(normal.dot(at), 0.0, 1.0)
	var cliff := smoothstep(0.22, 0.55, slope)
	var stone := maxf(grey - pale, 0.0) + cliff * 1.1
	var grass := maxf(green, 0.3 - maxf(maxf(sand, stone), ice))
	var scores := [grass, sand, stone, ice]
	var layer_index := int(definition.ground_layer) - 1
	var mine: float = scores[layer_index]
	if mine < definition.minimum_ground_claim:
		return false
	var ahead := 0
	for index in scores.size():
		if index != layer_index and float(scores[index]) > mine:
			ahead += 1
	return ahead <= 1


func _prune_cell_cache() -> void:
	if _cell_cache.size() <= CELL_CACHE_LIMIT:
		return
	var keep_after := _cache_generation - CACHE_KEEP_GENERATIONS
	for key in _cell_cache.keys():
		var cached := _cell_cache[key] as Dictionary
		if int(cached["seen"]) < keep_after:
			_cell_cache.erase(key)
			if _cell_cache.size() <= CELL_CACHE_LIMIT:
				return


# --- Actor lifetime and replication ----------------------------------------

func _spawn_authoritative(record: Dictionary, global_actor: bool) -> void:
	var id := String(record.get("id", ""))
	if id.is_empty() or _actors.has(id):
		return
	_spawn_local(record)
	if global_actor:
		_global_ids[id] = true
	if _has_remote_peers():
		_spawn_actor.rpc(record, global_actor)


@rpc("authority", "call_remote", "reliable")
func _spawn_actor(record: Dictionary, global_actor: bool) -> void:
	var id := String(record.get("id", ""))
	_spawn_local(record)
	if global_actor and not id.is_empty():
		_global_ids[id] = true


func _spawn_local(record: Dictionary) -> void:
	var id := String(record.get("id", ""))
	var definition := _species_by_id.get(
		String(record.get("species_id", ""))) as FaunaSpecies
	var transform_value: Variant = record.get("transform", Transform3D.IDENTITY)
	if id.is_empty() or _actors.has(id) or definition == null \
			or not transform_value is Transform3D:
		return
	var biome_value: Variant = record.get("biome", Color.WHITE)
	var biome := biome_value as Color if biome_value is Color else Color.WHITE
	var mob := FaunaMob.new()
	mob.name = id
	mob.configure(
		definition, id, maxi(int(record.get("seed", 1)), 1),
		transform_value as Transform3D, biome, self)
	add_child(mob)
	_actors[id] = mob
	if _pending_states.has(id):
		mob.apply_network_state(_pending_states[id] as Dictionary, true)
		_pending_states.erase(id)


func _despawn_authoritative(id: String) -> void:
	if not _actors.has(id):
		_global_ids.erase(id)
		return
	_despawn_local(id)
	if _has_remote_peers():
		_despawn_actor.rpc(id)


@rpc("authority", "call_remote", "reliable")
func _despawn_actor(id: String) -> void:
	_despawn_local(id)


func _despawn_local(id: String) -> void:
	var mob := _actors.get(id) as FaunaMob
	_actors.erase(id)
	_global_ids.erase(id)
	_pending_states.erase(id)
	if is_instance_valid(mob):
		mob.queue_free()


func publish_actor_state(id: String, wire: Dictionary) -> void:
	if not _is_host() or not _actors.has(id) or not _has_remote_peers():
		return
	_apply_actor_state.rpc(id, wire)


func publish_actor_event(id: String, wire: Dictionary) -> void:
	if not _is_host() or not _actors.has(id) or not _has_remote_peers():
		return
	_apply_actor_event.rpc(id, wire)


@rpc("authority", "call_remote", "unreliable_ordered")
func _apply_actor_state(id: String, wire: Dictionary) -> void:
	var mob := _actors.get(id) as FaunaMob
	if is_instance_valid(mob):
		mob.apply_network_state(wire)
	else:
		_pending_states[id] = wire


@rpc("authority", "call_remote", "reliable")
func _apply_actor_event(id: String, wire: Dictionary) -> void:
	var mob := _actors.get(id) as FaunaMob
	if is_instance_valid(mob):
		mob.apply_network_state(wire)
	else:
		_pending_states[id] = wire


@rpc("any_peer", "call_remote", "reliable")
func _request_fauna_snapshot() -> void:
	if not _is_host():
		return
	var sender := multiplayer.get_remote_sender_id()
	if sender <= 0:
		return
	_apply_fauna_snapshot.rpc_id(sender, fauna_snapshot())


@rpc("authority", "call_remote", "reliable")
func _apply_fauna_snapshot(snapshot: Array) -> void:
	var wanted := {}
	for entry_variant: Variant in snapshot:
		if not entry_variant is Dictionary:
			continue
		var entry := entry_variant as Dictionary
		var spawn_value: Variant = entry.get("spawn", {})
		var state_value: Variant = entry.get("state", {})
		if not spawn_value is Dictionary:
			continue
		var spawn := spawn_value as Dictionary
		var id := String(spawn.get("id", ""))
		if id.is_empty():
			continue
		wanted[id] = true
		_spawn_local(spawn)
		if bool(entry.get("global", false)):
			_global_ids[id] = true
		var mob := _actors.get(id) as FaunaMob
		if is_instance_valid(mob) and state_value is Dictionary:
			mob.apply_network_state(state_value as Dictionary, true)
	for id_variant: Variant in _actors.keys():
		var id := String(id_variant)
		if not wanted.has(id):
			_despawn_local(id)


func fauna_snapshot() -> Array:
	var snapshot: Array = []
	var ids := _actors.keys()
	ids.sort()
	for id_variant: Variant in ids:
		var id := String(id_variant)
		var mob := _actors[id] as FaunaMob
		if not is_instance_valid(mob) or mob.species == null:
			continue
		snapshot.append({
			"spawn": {
				"id": id,
				"species_id": mob.species.species_id,
				"seed": mob.spawn_seed,
				"transform": mob.global_transform,
				"biome": mob.biome_tint(),
			},
			"state": mob.state_wire(),
			"global": _global_ids.has(id),
		})
	return snapshot


# --- Bounded physical night lights -----------------------------------------

func _make_light_pool() -> void:
	for index in light_limit:
		var light := OmniLight3D.new()
		light.name = "FaunaLight%d" % index
		light.light_energy = 0.0
		light.shadow_enabled = false
		light.visible = false
		add_child(light, false, Node.INTERNAL_MODE_BACK)
		_lights.append(light)
		_light_actor_ids.append("")


func _update_lights(delta: float) -> void:
	if _lights.is_empty() or _planet == null:
		return
	var eye := _planet.to_global(_planet.viewer_position())
	var candidates: Array[Dictionary] = []
	for id_variant: Variant in _actors.keys():
		var id := String(id_variant)
		var mob := _actors[id] as FaunaMob
		if not is_instance_valid(mob) or not mob.is_alive() \
				or mob.species.local_light_energy <= 0.0:
			continue
		var away := eye.distance_to(mob.glow_position())
		if away <= lights_within:
			candidates.append({"id": id, "away": away, "mob": mob})
	candidates.sort_custom(func(a: Dictionary, b: Dictionary) -> bool:
		return float(a["away"]) < float(b["away"]))
	if candidates.size() > _lights.size():
		candidates.resize(_lights.size())

	for index in _lights.size():
		var light := _lights[index]
		var target_energy := 0.0
		if index < candidates.size():
			var candidate := candidates[index]
			var mob := candidate["mob"] as FaunaMob
			var definition := mob.species
			_light_actor_ids[index] = String(candidate["id"])
			var follow := 1.0 - exp(-delta * light_follow_speed)
			light.global_position = light.global_position.lerp(
				mob.glow_position() + mob.global_basis.y \
					* definition.local_light_height_share * mob.instance_height(),
				clampf(follow, 0.0, 1.0))
			light.light_color = definition.local_light_color
			light.omni_range = definition.local_light_range
			var night := _night_at(mob.global_position) \
				if definition.glow_night_only else 1.0
			target_energy = definition.local_light_energy * night
		else:
			_light_actor_ids[index] = ""
		light.light_energy = move_toward(
			light.light_energy, target_energy,
			delta * maxf(maxf(target_energy, light.light_energy), 0.1)
				* light_fade_speed)
		light.visible = light.light_energy > 0.001


func _night_at(world_point: Vector3) -> float:
	if _planet.sun == null:
		return 1.0
	var local := _planet.to_local(world_point)
	if local.length_squared() < 1.0:
		return 0.0
	var world_up := (_planet.global_basis * local.normalized()).normalized()
	var to_sun := _planet.sun.global_basis.z.normalized()
	return 1.0 - smoothstep(-0.16, 0.12, world_up.dot(to_sun))


# --- Utilities and diagnostics ---------------------------------------------

func _viewer_positions() -> Array[Vector3]:
	var viewers: Array[Vector3] = []
	for player_variant: Variant in get_tree().get_nodes_in_group(&"network_players"):
		var player := player_variant as Node3D
		if player != null and DamageHit.in_same_world(self, player):
			viewers.append(player.global_position)
	if viewers.is_empty():
		viewers.append(_planet.to_global(_planet.viewer_position()))
	return viewers


func _nearest_distance(point: Vector3, viewers: Array[Vector3]) -> float:
	var nearest := INF
	for viewer in viewers:
		nearest = minf(nearest, point.distance_to(viewer))
	return nearest


func _tangent_axes(direction: Vector3) -> Array[Vector3]:
	var up := direction.normalized()
	var east := up.cross(Vector3.UP if absf(up.y) < 0.9 \
		else Vector3.RIGHT).normalized()
	return [east, up.cross(east).normalized()]


func _upright_basis(forward: Vector3, up: Vector3) -> Basis:
	up = up.normalized()
	forward -= up * forward.dot(up)
	if forward.length_squared() < 0.000001:
		forward = _tangent_axes(up)[0]
	forward = forward.normalized()
	var right := forward.cross(up).normalized()
	return Basis(right, up, right.cross(up).normalized()).orthonormalized()


func _mixed_seed(base: int, key: Vector3i, member: int) -> int:
	var mixed := int(base) ^ ((key.x + 17) * 73856093)
	mixed ^= (key.y + 104729) * 19349663
	mixed ^= (key.z + 130363) * 83492791
	mixed ^= (member + 8191) * 2654435761
	mixed ^= mixed >> 13
	mixed *= 1274126177
	mixed ^= mixed >> 16
	return absi(mixed) + 1


func _has_remote_peers() -> bool:
	return multiplayer.has_multiplayer_peer() \
		and multiplayer.is_server() and not multiplayer.get_peers().is_empty()


func _is_host() -> bool:
	return not multiplayer.has_multiplayer_peer() or multiplayer.is_server()


func actor_count() -> int:
	return _actors.size()


func actor_ids() -> PackedStringArray:
	var ids := PackedStringArray()
	for id_variant: Variant in _actors.keys():
		ids.append(String(id_variant))
	ids.sort()
	return ids


func species_count(species_id: String) -> int:
	var count := 0
	for mob_variant: Variant in _actors.values():
		var mob := mob_variant as FaunaMob
		if is_instance_valid(mob) and mob.species != null \
				and mob.species.species_id == species_id:
			count += 1
	return count


func colony_actor_count() -> int:
	var count := 0
	for id_variant: Variant in _actors.keys():
		if String(id_variant).begins_with("c_"):
			count += 1
	return count


func light_pool_size() -> int:
	return _lights.size()


func last_survey_micros() -> int:
	return _last_survey_micros


func last_survey_placement_checks() -> int:
	return _last_survey_placement_checks


func last_colony_micros() -> int:
	return _last_colony_micros


func last_colony_placement_checks() -> int:
	return _last_colony_placement_checks


func should_publish_actor_state() -> bool:
	return _has_remote_peers()
