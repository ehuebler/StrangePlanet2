class_name GameWorld
extends Node3D

## The world is also the home screen. It is loaded once, empty, and the menu is a
## camera and an overlay put over it (see ui/menu/home_screen.gd); players are
## spawned only once a session exists. Nothing between the title and playing is a
## scene change, which is what keeps the planet's quadtree built across it.

const PLAYER_SCENE := preload("res://game/player/player.tscn")
const TRAINING := preload("res://game/crawler/crawler_training.gd")

## The title view opens at the light the authored cycle reaches after three
## minutes: low over Vacationer's Landing and close to local sunset. Story
## gameplay still begins from phase zero in [method _begin_session]. A crawler
## session instead opens at local twilight on the Tide Margin pad.
const HOME_SUN_ADVANCE_SECONDS := 180.0
## Just inside the coordinate plate's dusk band (+8° to −17°) at the spawn pad.
const CRAWLER_SPAWN_SUN_ELEVATION := 6.0
const DROP_FORWARD_DISTANCE := 1.55
const DROP_SURFACE_CLEARANCE := 0.08
const CRAWLER_DROP_FORWARD := 1.6
## Slightly wider than the 2.4 m interaction ray to allow for the player's eye,
## the pickup's raised centre and a sloping surface, but still an arm's-length
## server check rather than trusting that a client ray hit.
const PICKUP_MAX_DISTANCE := 3.2
## How often the host tells everyone what has actually broken. Slower than the
## damage itself, because this is a correction and not the mechanism: the peers
## have already worked it out for themselves.
const FLORA_CONFIRM_INTERVAL := 0.4
const RESPAWN_CLEARANCE := 0.35
## A ring around the landing waypoint, still visibly at the shore.
const RESPAWN_SPACING := 14.0
## Metres above the nearest city's pad when holding Respawn in the Tab menu.
const CITY_RESPAWN_CLEARANCE := 96.0

@onready var spawn_points: Node3D = $SpawnPoints
@onready var celestial_cycle: CelestialCycle = $CelestialCycle

var _spawned_players: Dictionary = {}
## On the server these are the authoritative finite world records. Clients keep
## the replicated subset in the same shape so duplicate join/live spawns and
## despawns are harmless.
var _pickups: Dictionary = {}
var _pickup_nodes: Dictionary = {}
var _next_pickup_id := 1
var _ability_constructs: Dictionary = {}
var _next_ability_construct_id := 1
var _locally_paused := false
var _simulation_frozen := false
var _time_scale_before_pause := 1.0
var _home_screen: HomeScreen
## Set once a session has been opened here, so a second `session_started` — the
## one a client gets on connecting, after the host's — cannot spawn twice.
var _session_open := false
var _spawn_override := Transform3D.IDENTITY
var _has_spawn_override := false
var _force_spawn_override := false
var _restore_payload: Dictionary = {}
## Look the home screen was showing when New Game was pressed. Wins over the
## roster metadata for the local peer so the body that starts is the one that
## was on screen, not a stale settings read.
var _look_override: Dictionary = {}
var _has_look_override := false
## Seconds until the next flora reconciliation pass. See
## [method confirm_flora_breaks].
var _flora_confirm_left := 0.0
## Host-only respawn counter per player peer id, so a late or duplicated
## respawn packet cannot put an already-living body back at the colony.
var _respawn_sequence: Dictionary = {}
var _crawler_city_queue: Array = []
var _crawler_city_gift_id := 0
var _crawler_city_gift_claimed := false
var _peer_spawns: Dictionary = {}
var _duel_active := false
var _duel_returns: Dictionary = {}
var _training_active := false
var _training_returns: Dictionary = {}
var _training_level := 1


func _ready() -> void:
	# The GameMenu opts into ALWAYS processing itself. The world must remain
	# pausable so its inherited gameplay, physics, audio, timers, and animations
	# all stop beneath that menu in a single-player session.
	process_mode = Node.PROCESS_MODE_PAUSABLE
	NetworkManager.active_world = self
	NetworkManager.player_registered.connect(_on_player_registered)
	NetworkManager.player_left.connect(_despawn_player)
	NetworkManager.session_started.connect(_begin_session)

	if NetworkManager.state == NetworkManager.SessionState.IN_GAME:
		_begin_session()
	else:
		_open_home_screen()


func _physics_process(delta: float) -> void:
	_flora_confirm_left -= delta
	if _flora_confirm_left > 0.0:
		return
	_flora_confirm_left = FLORA_CONFIRM_INTERVAL
	confirm_flora_breaks()


func _exit_tree() -> void:
	if NetworkManager.active_world == self:
		NetworkManager.active_world = null
	if NetworkManager.player_registered.is_connected(_on_player_registered):
		NetworkManager.player_registered.disconnect(_on_player_registered)
	if NetworkManager.player_left.is_connected(_despawn_player):
		NetworkManager.player_left.disconnect(_despawn_player)
	if NetworkManager.session_started.is_connected(_begin_session):
		NetworkManager.session_started.disconnect(_begin_session)
	_pickups.clear()
	_pickup_nodes.clear()
	_ability_constructs.clear()
	_respawn_sequence.clear()


func local_player() -> OnlinePlayer:
	return _spawned_players.get(multiplayer.get_unique_id()) as OnlinePlayer


func session_is_open() -> bool:
	return _session_open


func next_pickup_id() -> int:
	return _next_pickup_id


func next_ability_construct_id() -> int:
	return _next_ability_construct_id


func city_gift_id() -> int:
	return _crawler_city_gift_id


func city_gift_claimed() -> bool:
	return _crawler_city_gift_claimed


func duel_active() -> bool:
	return _duel_active


func duel_snapshot() -> Dictionary:
	return {
		"active": _duel_active,
		"returns": _duel_returns.duplicate(true),
	}


func training_active() -> bool:
	return _training_active


func training_level() -> int:
	return _training_level


func training_snapshot() -> Dictionary:
	return {
		"active": _training_active,
		"returns": _training_returns.duplicate(true),
		"level": _training_level,
	}


func planet() -> Planet:
	return get_node_or_null("Planet") as Planet


## Stable ids are allocated only by the host and then carried by the caster's
## approved spawn event to every peer.
func allocate_ability_construct_id() -> int:
	if multiplayer.has_multiplayer_peer() and not multiplayer.is_server():
		return 0
	var next_id := _next_ability_construct_id
	_next_ability_construct_id += 1
	return next_id


func spawn_ability_barrier_local(construct_id: int, owner_peer: int,
		at: Transform3D, size: Vector3, duration: float,
		fade_duration: float, tint: Color,
		initial_alpha := 0.52, extras: Dictionary = {}) -> AbilityBarrier:
	if construct_id <= 0:
		return null
	var existing := _ability_constructs.get(construct_id) as AbilityBarrier
	if is_instance_valid(existing):
		return existing
	var barrier := AbilityBarrier.create(
		self, construct_id, owner_peer, at, size,
		duration, fade_duration, tint, initial_alpha, extras)
	if barrier == null:
		return null
	_ability_constructs[construct_id] = barrier
	barrier.expired.connect(_on_ability_construct_expired)
	barrier.tree_exited.connect(func() -> void:
		if _ability_constructs.get(construct_id) == barrier:
			_ability_constructs.erase(construct_id)
	)
	return barrier


func _on_ability_construct_expired(construct_id: int) -> void:
	if multiplayer.has_multiplayer_peer():
		if multiplayer.is_server():
			_apply_ability_construct_despawn.rpc(construct_id)
		return
	_apply_ability_construct_despawn(construct_id)


@rpc("authority", "call_local", "reliable")
func _apply_ability_construct_despawn(construct_id: int) -> void:
	if construct_id <= 0:
		return
	var barrier := _ability_constructs.get(construct_id) as AbilityBarrier
	_ability_constructs.erase(construct_id)
	if is_instance_valid(barrier):
		barrier.queue_free()


func ability_construct_snapshot() -> Array:
	var snapshot: Array = []
	for id_variant: Variant in _ability_constructs:
		var construct_id := int(id_variant)
		var barrier := _ability_constructs.get(construct_id) as AbilityBarrier
		if not is_instance_valid(barrier) or barrier.remaining() <= 0.0:
			continue
		snapshot.append({
			"construct_id": construct_id,
			"owner_peer": barrier.owner_peer,
			"transform": barrier.global_transform,
			"size": barrier.size(),
			"remaining": barrier.remaining(),
			"fade_duration": barrier.fade_duration(),
			"tint": barrier.tint(),
			"alpha": barrier.current_alpha(),
			"extras": barrier.extras(),
		})
	return snapshot


func apply_ability_construct_snapshot(snapshot: Array) -> void:
	for entry_variant: Variant in snapshot:
		if not entry_variant is Dictionary:
			continue
		var entry := entry_variant as Dictionary
		var extras: Dictionary = {}
		var held: Variant = entry.get("extras", {})
		if held is Dictionary:
			extras = held
		var size_raw: Variant = GameSave.unpack(entry.get("size", Vector3(8.0, 4.0, 0.35)))
		var tint_raw: Variant = GameSave.unpack(entry.get("tint", Color(0.27, 0.69, 1.0)))
		spawn_ability_barrier_local(
			int(entry.get("construct_id", 0)),
			int(entry.get("owner_peer", 0)),
			GameSave.unpack_transform(entry.get("transform", {})),
			size_raw if size_raw is Vector3 else Vector3(8.0, 4.0, 0.35),
			float(entry.get("remaining", 0.0)),
			float(entry.get("fade_duration", 0.0)),
			tint_raw if tint_raw is Color else Color(0.27, 0.69, 1.0),
			float(entry.get("alpha", 0.52)),
			extras)


func active_ability_wall_count() -> int:
	var count := 0
	for barrier_variant: Variant in _ability_constructs.values():
		if is_instance_valid(barrier_variant):
			count += 1
	return count


## Asks for a mark to be cut into the ground.
##
## Host-authoritative, like every other change to shared world state here: a
## client sends the request and waits to be told, so two peers cannot end up
## with craters the other does not have. The host applies it to itself through
## the same broadcast, so there is one code path and no chance of the two
## drifting.
func request_scar(scar: TerrainScars.Scar) -> void:
	if scar == null:
		return
	if not multiplayer.has_multiplayer_peer():
		_apply_scar(scar.to_wire())
		return
	if multiplayer.is_server():
		_apply_scar.rpc(scar.to_wire())
	else:
		_request_scar_from_client.rpc_id(1, scar.to_wire())


@rpc("any_peer", "call_remote", "reliable")
func _request_scar_from_client(wire: Dictionary) -> void:
	if not multiplayer.is_server():
		return
	var sender := multiplayer.get_remote_sender_id()
	if NetworkManager.state != NetworkManager.SessionState.IN_GAME \
			or not NetworkManager.is_peer_registered(sender):
		return
	_apply_scar.rpc(wire)


@rpc("authority", "call_local", "reliable")
func _apply_scar(wire: Dictionary) -> void:
	var world_planet := planet()
	if world_planet == null:
		return
	var scar := TerrainScars.Scar.from_wire(wire)
	var absorbed := _absorb_city_scars(scar)
	if absorbed > 0.0:
		scar.depth = maxf(scar.depth - absorbed, 0.0)
	if scar.depth > 0.05:
		world_planet.add_scar(scar)


func _absorb_city_scars(scar: TerrainScars.Scar) -> float:
	if scar == null or not is_inside_tree():
		return 0.0
	var absorbed := 0.0
	for node in get_tree().get_nodes_in_group(PatchCity.PAD_GROUP):
		var city := node as PatchCity
		if city == null:
			continue
		absorbed = maxf(absorbed, city.absorb_scar(scar))
	return absorbed


## Every mark on the ground, for a peer joining a session that has already been
## fought over.
func scar_snapshot() -> Array:
	var world_planet := planet()
	if world_planet == null or world_planet.shape == null:
		return []
	return world_planet.shape.scars.to_wire()


func apply_scar_snapshot(wire: Array) -> void:
	var world_planet := planet()
	if world_planet == null or world_planet.shape == null:
		return
	world_planet.shape.scars.from_wire(wire)
	# One sweep rather than one per scar: the registry is already populated, and
	# a joining peer has every chunk to build anyway.
	for entry in wire:
		if entry is Dictionary:
			# Read back off a scar rather than out of the wire, so the widest
			# reach of a warped rim is the thing invalidated here too.
			var scar := TerrainScars.Scar.from_wire(entry)
			_absorb_city_scars(scar)
			world_planet.mark_region_stale(
				scar.direction, scar.outer, scar.depth)


## What every flora field has lost so far, keyed by the field's path under this
## world. Paths rather than names because the fields are scattered through the
## planet's children, and every peer loads the same scene so the same path
## resolves to the same field.
func flora_snapshot() -> Dictionary:
	var state := {}
	for field in get_tree().get_nodes_in_group(DamageHit.FIELD_GROUP):
		if not (field is Node) or not DamageHit.in_same_world(self, field) \
				or not field.has_method(&"broken_keys"):
			continue
		var keys: PackedInt32Array = field.call(&"broken_keys")
		if not keys.is_empty():
			state[String(get_path_to(field))] = keys
	return state


func apply_flora_snapshot(state: Dictionary) -> void:
	for path: String in state:
		var raw: Variant = state[path]
		var keys := PackedInt32Array()
		if raw is PackedInt32Array:
			keys = raw
		elif raw is Array:
			for item: Variant in raw:
				keys.append(int(item))
		_apply_flora_breaks(path, keys)


# --- Colony respawn ---------------------------------------------------------

## Asked for by the death screen, rather than run down by a clock: being dead is
## the one moment a player is reading the screen instead of the world, and a
## timer that takes the body back mid-sentence loses them the only account they
## get of what killed them.
@rpc("any_peer", "call_local", "reliable")
func request_colony_respawn() -> void:
	if not _is_host_authority():
		return
	var sender := multiplayer.get_remote_sender_id()
	if sender <= 0:
		sender = multiplayer.get_unique_id()
	var player := _spawned_players.get(sender) as OnlinePlayer
	if not is_instance_valid(player) or not player.is_dead():
		return
	if CrawlerRules.active():
		var progress := player.crawler_progress
		if progress == null:
			return
		if not progress.has_respawn_ticket() \
				and int(CrawlerProgress.session_payload.get("tickets", 0)) > 0:
			progress.from_dict(CrawlerProgress.session_payload)
		if not progress.spend_respawn_ticket():
			return
	respawn_player_at_colony(sender)


@rpc("any_peer", "call_local", "reliable")
func request_revive_player(target_peer: int) -> void:
	if not _is_host_authority():
		return
	if not CrawlerRules.active() or CrawlerRules.duel_active() \
			or CrawlerRules.training_active():
		return
	var sender := multiplayer.get_remote_sender_id()
	if sender <= 0:
		sender = multiplayer.get_unique_id()
	var healer := _spawned_players.get(sender) as OnlinePlayer
	var target := _spawned_players.get(target_peer) as OnlinePlayer
	if not is_instance_valid(healer) or healer.is_dead() or healer.training_enemy:
		return
	if not is_instance_valid(target) or not target.is_dead() \
			or target.training_enemy:
		return
	if healer.global_position.distance_to(target.global_position) \
			> CrawlerRules.REVIVE_REACH + 0.35:
		return
	var sequence := int(_respawn_sequence.get(target_peer, 0)) + 1
	_respawn_sequence[target_peer] = sequence
	var at_transform := target.global_transform
	if multiplayer.has_multiplayer_peer() and not multiplayer.get_peers().is_empty():
		_apply_colony_respawn.rpc(target_peer, at_transform, sequence)
	else:
		_apply_colony_respawn(target_peer, at_transform, sequence)


func note_crawler_party_changed() -> void:
	if not _is_host_authority():
		return
	if not CrawlerRules.active() or CrawlerRules.duel_active() \
			or CrawlerRules.training_active():
		return
	if multiplayer.has_multiplayer_peer() and not multiplayer.get_peers().is_empty():
		_refresh_crawler_death.rpc()
	else:
		_refresh_crawler_death()


@rpc("authority", "call_local", "reliable")
func _refresh_crawler_death() -> void:
	var player := local_player()
	if player != null and player.has_method(&"refresh_crawler_death_overlay"):
		player.refresh_crawler_death_overlay()


func respawn_player_at_colony(peer_id: int) -> bool:
	if not _is_host_authority():
		return false
	var player := _spawned_players.get(peer_id) as OnlinePlayer
	if not is_instance_valid(player):
		return false
	var sequence := int(_respawn_sequence.get(peer_id, 0)) + 1
	_respawn_sequence[peer_id] = sequence
	var at_transform := _respawn_transform(peer_id)
	if multiplayer.has_multiplayer_peer() and not multiplayer.get_peers().is_empty():
		_apply_colony_respawn.rpc(peer_id, at_transform, sequence)
	else:
		_apply_colony_respawn(peer_id, at_transform, sequence)
	return true


@rpc("any_peer", "call_local", "reliable")
func request_city_respawn() -> void:
	if not _is_host_authority():
		return
	var sender := multiplayer.get_remote_sender_id()
	if sender <= 0:
		sender = multiplayer.get_unique_id()
	respawn_player_above_city(sender)


func respawn_player_above_city(peer_id: int) -> bool:
	if not _is_host_authority():
		return false
	var player := _spawned_players.get(peer_id) as OnlinePlayer
	if not is_instance_valid(player):
		return false
	var sequence := int(_respawn_sequence.get(peer_id, 0)) + 1
	_respawn_sequence[peer_id] = sequence
	var at_transform := _respawn_transform(peer_id, player.global_position)
	if multiplayer.has_multiplayer_peer() and not multiplayer.get_peers().is_empty():
		_apply_colony_respawn.rpc(peer_id, at_transform, sequence)
	else:
		_apply_colony_respawn(peer_id, at_transform, sequence)
	return true


func _respawn_transform(peer_id: int, from := Vector3.ZERO) -> Transform3D:
	if CrawlerRules.active():
		var start := _crawler_start_transform()
		if start.origin.length_squared() > 1.0:
			return start
	if from.length_squared() > 0.0001:
		return nearest_city_respawn_transform(from, peer_id)
	return safe_colony_respawn_transform(peer_id)


func nearest_city_respawn_transform(from: Vector3, peer_id: int) -> Transform3D:
	if CrawlerRules.active():
		var start := _crawler_start_transform()
		if start.origin.length_squared() > 1.0:
			return start
	var city := _nearest_city(from)
	if city == null:
		return safe_colony_respawn_transform(peer_id)
	var at := city.hover_point(CITY_RESPAWN_CLEARANCE)
	var up := city.world_up()
	var facing := from - at
	facing -= up * facing.dot(up)
	if facing.length_squared() < 0.0001:
		facing = Vector3.FORWARD
	return Transform3D(_upright_basis(facing.normalized(), up), at)


func _seed_crawler_cities(tries := 0) -> void:
	if not CrawlerRules.active():
		return
	var overlay := _land_patches()
	if overlay == null or not overlay.ensure_ready():
		if tries < 8:
			call_deferred(&"_seed_crawler_cities", tries + 1)
		return
	if CrawlerRun.active():
		var layout := CrawlerRunLayout.ensure(self)
		if layout != null:
			layout.place_opening()
			if not CrawlerProgress.session_payload.is_empty():
				var ledger := CrawlerProgress.new()
				ledger.from_dict(CrawlerProgress.session_payload)
				layout.apply_saved_progress(ledger)
		_ensure_crawler_horde()
		_park_crawler_players()
		return
	_ensure_crawler_ring(tries)
	_ensure_crawler_horde()
	_park_crawler_players()


func _ensure_crawler_ring(tries := 0) -> void:
	if not CrawlerRules.active():
		return
	if get_node_or_null("CrawlerCityRing") != null:
		_ensure_crawler_start_site()
		_apply_crawler_site_progress()
		_ensure_crawler_city_gift()
		_ensure_later_crawler_cities(tries)
		return
	var overlay := _land_patches()
	if overlay == null or not overlay.ensure_ready():
		if tries < 8:
			call_deferred(&"_ensure_crawler_ring", tries + 1)
		return
	var at := overlay.crawler_city_transform(0.35)
	if at.origin.length_squared() < 1.0:
		var named_id := overlay.patch_id_named(CrawlerRules.CITY_PATCH)
		if named_id < 0:
			named_id = _fallback_crawler_city_id(overlay)
		var start_id := overlay.patch_id_named(CrawlerRules.START_PATCH)
		var from := overlay.flat_direction_for_patch(start_id) if start_id >= 0 \
				else Vector3.ZERO
		at = overlay.flat_surface_transform_away_from(
			named_id, from, CrawlerRules.CITY_RING_PUSH, 0.35)
	if at.origin.length_squared() < 1.0:
		if tries < 8:
			call_deferred(&"_ensure_crawler_ring", tries + 1)
		return
	var patch_id := overlay.patch_id_at(at.origin)
	if patch_id < 0:
		patch_id = overlay.patch_id_named(CrawlerRules.CITY_PATCH)
	if patch_id < 0:
		patch_id = _fallback_crawler_city_id(overlay)
	var ring = load("res://game/crawler/crawler_city_ring.gd").new()
	ring.name = "CrawlerCityRing"
	ring.configure(patch_id, at)
	add_child(ring)
	NetworkManager.session_options["crawler_cities"] = [patch_id]
	_ensure_crawler_start_site()
	_apply_crawler_site_progress()
	_ensure_crawler_city_gift()
	_ensure_later_crawler_cities(tries)


func _ensure_later_crawler_cities(tries := 0) -> void:
	if not CrawlerRules.active():
		return
	if get_node_or_null("CrawlerCrescentRing") != null \
			and get_node_or_null("CrawlerLeeRing") != null:
		return
	var overlay := _land_patches()
	if overlay == null or not overlay.ensure_ready():
		if tries < 8:
			call_deferred(&"_ensure_later_crawler_cities", tries + 1)
		return
	var first := get_node_or_null("CrawlerCityRing") as CrawlerCityRing
	if first == null:
		if tries < 8:
			call_deferred(&"_ensure_later_crawler_cities", tries + 1)
		return
	var city_dir := first.world_up()
	if city_dir.length_squared() < 0.0001:
		city_dir = CrawlerRules.city_direction()
	var tower_id := overlay.patch_id_named(CrawlerRules.TOWER_PATCH)
	var castle_id := overlay.patch_id_named(CrawlerRules.CASTLE_PATCH)
	var heading := Vector3.ZERO
	if tower_id >= 0 and castle_id >= 0:
		heading = CrawlerRules.city_pair_heading(
			city_dir,
			overlay.flat_direction_for_patch(tower_id),
			overlay.flat_direction_for_patch(castle_id)
		)
	var radius := _crawler_planet_radius()
	var crescent_id := overlay.patch_id_named_exact(CrawlerRules.CITY_CRESCENT_PATCH)
	if crescent_id < 0:
		crescent_id = overlay.compass_cell_named("Far Beacon 4", "Northwest")
	var crescent_dir := overlay.flat_direction_for_patch(crescent_id) \
			if crescent_id >= 0 else Vector3.ZERO
	if crescent_dir.length_squared() < 0.0001 and heading.length_squared() > 0.0001:
		crescent_dir = CrawlerRules.slide_direction(
			city_dir, heading, CrawlerRules.CITY_OUTPOST_METRES, radius)
	_place_later_crawler_city(
		"CrawlerCrescentRing",
		crescent_dir,
		CrawlerRules.CITY_CRESCENT_SITE_ID,
		CrawlerRules.CITY_CRESCENT_TITLE,
		CrawlerRules.CRESCENT_VILLAGE,
		crescent_id
	)
	var lee_id := overlay.rest_cell_named(CrawlerRules.CITY_LEE_PATCH)
	if lee_id < 0:
		lee_id = overlay.patch_id_named(CrawlerRules.CITY_LEE_PATCH)
	var lee_dir := overlay.flat_direction_for_patch(lee_id) \
			if lee_id >= 0 else Vector3.ZERO
	if lee_dir.length_squared() < 0.0001 and heading.length_squared() > 0.0001:
		lee_dir = CrawlerRules.slide_direction(
			city_dir, heading, -CrawlerRules.CITY_OUTPOST_METRES, radius)
	_place_later_crawler_city(
		"CrawlerLeeRing",
		lee_dir,
		CrawlerRules.CITY_LEE_SITE_ID,
		CrawlerRules.CITY_LEE_TITLE,
		CrawlerCityRing.VILLAGE_MODEL,
		lee_id
	)


func _place_later_crawler_city(
		node_name: String,
		direction: Vector3,
		next_site: String,
		next_title: String,
		next_model: String,
		patch_id := -1
	) -> void:
	if get_node_or_null(node_name) != null:
		return
	var overlay := _land_patches()
	if overlay == null:
		return
	var at := Transform3D()
	if patch_id >= 0:
		at = overlay.flat_surface_transform_for_patch(patch_id, 0.35)
	if at.origin.length_squared() < 1.0:
		at = overlay.surface_transform_for_direction(direction, 0.35)
	if at.origin.length_squared() < 1.0:
		return
	if patch_id < 0:
		patch_id = overlay.patch_id_at(at.origin)
	var ring = load("res://game/crawler/crawler_city_ring.gd").new()
	ring.name = node_name
	ring.configure(patch_id, at, next_site, next_title, next_model, next_site)
	add_child(ring)
	_record_crawler_city(next_site)


func _record_crawler_city(key: Variant) -> void:
	var listed: Array = []
	var held: Variant = NetworkManager.session_options.get("crawler_cities", [])
	if held is Array:
		listed = (held as Array).duplicate()
	if not listed.has(key):
		listed.append(key)
	NetworkManager.session_options["crawler_cities"] = listed


func _crawler_planet_radius() -> float:
	var host := planet()
	if host != null and host.shape != null:
		return maxf(host.shape.radius, 1.0)
	return 8000.0


func _place_next_crawler_city() -> void:
	if not CrawlerRules.active() or _crawler_city_queue.is_empty():
		return
	var overlay := _land_patches()
	if overlay == null:
		return
	var patch_id := int(_crawler_city_queue.pop_front())
	overlay.place_cities([patch_id])
	if not _crawler_city_queue.is_empty():
		call_deferred(&"_place_next_crawler_city")
	else:
		_park_crawler_players()


func _ensure_crawler_city_gift() -> void:
	if not CrawlerRules.active():
		return
	if multiplayer.has_multiplayer_peer() and not multiplayer.is_server():
		return
	if _crawler_city_gift_claimed:
		return
	if _crawler_city_gift_id > 0:
		var existing := _pickup_nodes.get(_crawler_city_gift_id) as Node
		if is_instance_valid(existing):
			return
	var ring := get_node_or_null("CrawlerCityRing") as CrawlerCityRing
	if ring == null:
		return
	var card := CrawlerCatalog.make_ability("starfire")
	if card == null:
		return
	var pickup_id := _next_pickup_id
	_next_pickup_id += 1
	_crawler_city_gift_id = pickup_id
	var at_transform := ring.gift_stand_transform()
	_pickups[pickup_id] = {
		"kind": "crawler",
		"payload": card.to_dict(),
		"transform": at_transform,
		"claimed": false,
	}
	_spawn_crawler_pickup_local(pickup_id, card.to_dict(), at_transform)
	if multiplayer.has_multiplayer_peer():
		_spawn_crawler_pickup.rpc(pickup_id, card.to_dict(), at_transform)


func _fallback_crawler_city_id(overlay: LandPatchOverlay) -> int:
	var start_id := overlay.patch_id_named(CrawlerRules.START_PATCH)
	var best := -1
	var best_span := -1.0
	for patch in overlay.partition.patches:
		if patch.id == start_id or CrawlerRules.reserved_patch(patch.name):
			continue
		if patch.span > best_span:
			best_span = patch.span
			best = patch.id
	return best


func _ensure_crawler_start_site() -> void:
	if not CrawlerRules.active():
		return
	_ensure_crawler_spawn_pad()
	if _crawler_start_site() != null:
		return
	var at := _crawler_start_transform()
	if at.origin.length_squared() < 1.0:
		return
	var host := planet()
	var site := CrawlerSite.new()
	site.name = "CrawlerStartSite"
	site.site_id = CrawlerRules.START_SITE_ID
	site.title = CrawlerRules.START_SITE_TITLE
	site.enter_radius = CrawlerRules.START_ENTER_RADIUS
	site.waypoint = false
	site.hide_beyond = 0.0
	site.show_beyond = 0.0
	site.aimed_beyond = 0.0
	site.clearance = 2.0
	site.direction = at.origin.normalized()
	site.planet = host
	if host != null:
		host.add_child(site)
	else:
		add_child(site)


func _crawler_start_site() -> CrawlerSite:
	var existing := get_node_or_null("CrawlerStartSite") as CrawlerSite
	if existing != null:
		return existing
	var host := planet()
	if host != null:
		return host.get_node_or_null("CrawlerStartSite") as CrawlerSite
	return null


func _apply_crawler_site_progress() -> void:
	if CrawlerProgress.session_payload.is_empty() or not is_inside_tree():
		return
	var ledger := CrawlerProgress.new()
	ledger.from_dict(CrawlerProgress.session_payload)
	CrawlerSites.apply_progress(ledger, get_tree())


## Sets the orbit so the sun sits just into twilight at the crawler pad.
## Host only; clients inherit the phase from the world snapshot.
func _sync_crawler_twilight(tries := 0) -> void:
	if not CrawlerRules.active() or celestial_cycle == null:
		return
	if multiplayer.has_multiplayer_peer() and not multiplayer.is_server():
		return
	var at := _crawler_start_transform()
	if at.origin.length_squared() < 1.0:
		if tries < 8:
			call_deferred(&"_sync_crawler_twilight", tries + 1)
		return
	var host := planet()
	var up := at.basis.y
	if host != null:
		var from_centre := at.origin - host.global_position
		if from_centre.length_squared() > 0.0001:
			up = from_centre
	if up.length_squared() < 0.0001:
		return
	celestial_cycle.set_phase(celestial_cycle.phase_for_local_elevation(
		up, CRAWLER_SPAWN_SUN_ELEVATION, true))


func _crawler_start_transform() -> Transform3D:
	_ensure_crawler_spawn_pad()
	var pad := _crawler_spawn_pad()
	if pad != null:
		var seated := pad.player_spawn_transform()
		if seated.origin.length_squared() > 1.0:
			return seated
	var overlay := _land_patches()
	if overlay == null or not overlay.ensure_ready():
		return Transform3D()
	var patch_id := overlay.crawler_start_patch_id()
	if patch_id >= 0:
		var seated := overlay.high_surface_transform_for_patch(patch_id, 1.35)
		if seated.origin.length_squared() > 1.0:
			return seated
	return overlay.crawler_spawn_transform(1.35)


func _crawler_pad_transform(peer_id: int) -> Transform3D:
	_ensure_crawler_spawn_pad()
	var pad := _crawler_spawn_pad()
	var peers: Array = NetworkManager.players.keys() if NetworkManager != null else []
	peers.sort()
	var index := peers.find(peer_id)
	if index < 0:
		index = maxi(peer_id - 1, 0)
	var count := maxi(peers.size(), 1)
	if pad != null:
		var seated := pad.player_spawn_transform_for(index, count)
		if seated.origin.length_squared() > 1.0:
			return seated
	var base := _crawler_start_transform()
	if count <= 1:
		return base
	var up := base.basis.y
	if up.length_squared() < 0.0001:
		up = Vector3.UP
	up = up.normalized()
	var right := up.cross(Vector3.FORWARD)
	if right.length_squared() < 0.0001:
		right = up.cross(Vector3.RIGHT)
	right = right.normalized()
	var forward := up.cross(right).normalized()
	var angle := TAU * float(posmod(index, count)) / float(count)
	base.origin += (right * cos(angle) + forward * sin(angle)) * 2.4
	return base


func _crawler_spawn_pad() -> CrawlerSpawnPad:
	var existing := get_node_or_null("CrawlerSpawnPad") as CrawlerSpawnPad
	if existing != null:
		return existing
	var host := planet()
	if host != null:
		return host.get_node_or_null("CrawlerSpawnPad") as CrawlerSpawnPad
	return null


func _ensure_crawler_spawn_pad(tries := 0) -> void:
	if not CrawlerRules.active():
		return
	if _crawler_spawn_pad() != null:
		return
	var overlay := _land_patches()
	if overlay == null or not overlay.ensure_ready():
		if tries < 8:
			call_deferred(&"_ensure_crawler_spawn_pad", tries + 1)
		return
	var at := Transform3D()
	if CrawlerRun.active():
		at = overlay.surface_transform_for_direction(CrawlerRun.spawn_direction(), 0.0)
	if at.origin.length_squared() < 1.0:
		var patch_id := overlay.crawler_start_patch_id()
		if patch_id < 0 and not overlay.partition.patches.is_empty():
			patch_id = overlay.partition.patches[0].id
		at = overlay.high_surface_transform_for_patch(patch_id, 0.0)
	if at.origin.length_squared() < 1.0:
		at = overlay.crawler_spawn_transform(0.0)
	if at.origin.length_squared() < 1.0:
		if tries < 8:
			call_deferred(&"_ensure_crawler_spawn_pad", tries + 1)
		return
	var pad := CrawlerSpawnPad.new()
	pad.name = "CrawlerSpawnPad"
	pad.configure(at)
	var host := planet()
	if host != null:
		host.add_child(pad)
	else:
		add_child(pad)
	_sync_crawler_twilight()


func _park_crawler_players() -> void:
	if not CrawlerRules.active():
		return
	_sync_crawler_twilight()
	for player_variant: Variant in _spawned_players.values():
		var player := player_variant as OnlinePlayer
		if not is_instance_valid(player):
			continue
		var at := _crawler_pad_transform(player.peer_id)
		if at.origin.length_squared() < 1.0:
			continue
		player.global_transform = at
		player.reset_physics_interpolation()
		player.reset_network_state(at)
		if player.has_method(&"settle_on_ground"):
			player.call(&"settle_on_ground")
		if player.has_method(&"play_spawn_arrival"):
			player.call(&"play_spawn_arrival")


func _land_patches() -> LandPatchOverlay:
	var overlay := get_node_or_null("Planet/LandPatches") as LandPatchOverlay
	if overlay != null:
		return overlay
	if not is_inside_tree():
		return null
	return get_tree().get_first_node_in_group(LandPatchOverlay.GROUP) \
		as LandPatchOverlay


func _ensure_crawler_horde() -> void:
	if not CrawlerRules.active():
		return
	if get_node_or_null("CrawlerHorde") != null:
		return
	var horde := CrawlerHorde.new()
	horde.name = "CrawlerHorde"
	add_child(horde)


func _ensure_crawler_statues(tries := 0) -> void:
	if not CrawlerRules.active():
		return
	var host := planet()
	var statues := (
		host.get_node_or_null("CrawlerStatues") as CrawlerStatues
		if host != null else get_node_or_null("CrawlerStatues") as CrawlerStatues
	)
	if statues == null:
		statues = CrawlerStatues.new()
		statues.name = "CrawlerStatues"
		if host != null:
			host.add_child(statues)
		else:
			add_child(statues)
	if statues.ensure_placed():
		return
	if tries < 12:
		call_deferred(&"_ensure_crawler_statues", tries + 1)


func _nearest_city(from: Vector3) -> PatchCity:
	var overlay := get_node_or_null("Planet/LandPatches") as LandPatchOverlay
	if overlay == null:
		overlay = get_tree().get_first_node_in_group(LandPatchOverlay.GROUP) \
			as LandPatchOverlay
	if overlay == null:
		return null
	var best: PatchCity = null
	var nearest := 1.0e30
	for held in overlay.all_cities():
		var city := held as PatchCity
		if city == null:
			continue
		var away := from.distance_squared_to(city.world_centre())
		if away < nearest:
			nearest = away
			best = city
	return best


## Terrain-sampled, deterministic positions beside Vacationer's Landing (or the
## landing-site fallback). The host computes and broadcasts the exact transform,
## so peers need not agree on their local terrain streaming state that frame.
func safe_colony_respawn_transform(peer_id: int) -> Transform3D:
	if CrawlerRules.active():
		var start := _crawler_start_transform()
		if start.origin.length_squared() > 1.0:
			return start
	var anchor := get_node_or_null("Planet/VacationersLanding") as Node3D
	if anchor == null:
		anchor = get_node_or_null("Planet/LandingSite") as Node3D
	if anchor == null:
		return _spawn_transform(peer_id)
	var world_planet := planet()
	var up := anchor.global_basis.y.normalized()
	var forward := -anchor.global_basis.z
	forward -= up * forward.dot(up)
	if forward.length_squared() < 0.0001:
		forward = anchor.global_basis.x
	forward = forward.normalized()
	var right := forward.cross(up).normalized()
	var slot := posmod(peer_id - 1, 8)
	var angle := TAU * float(slot) / 8.0
	var offset := (right * cos(angle) + forward * sin(angle)) \
		* RESPAWN_SPACING
	if world_planet == null or world_planet.shape == null:
		return Transform3D(_upright_basis(forward, up),
			anchor.global_position + offset + up * RESPAWN_CLEARANCE)

	var local := world_planet.to_local(anchor.global_position + offset)
	if local.length_squared() < 1.0:
		return Transform3D(_upright_basis(forward, up),
			anchor.global_position + offset + up * RESPAWN_CLEARANCE)
	var direction := local.normalized()
	var spacing := world_planet.finest_spacing()
	var normal_local := world_planet.shape.normal_at(direction, spacing).normalized()
	var surface_local := world_planet.shape.surface_point(direction, spacing)
	var normal := (world_planet.global_basis * normal_local).normalized()
	var facing := forward - normal * forward.dot(normal)
	if facing.length_squared() < 0.0001:
		facing = right.cross(normal)
	return Transform3D(_upright_basis(facing.normalized(), normal),
		world_planet.to_global(surface_local) + normal * RESPAWN_CLEARANCE)


@rpc("authority", "call_local", "reliable")
func _apply_colony_respawn(peer_id: int, at_transform: Transform3D,
		sequence: int) -> void:
	var player := _spawned_players.get(peer_id) as OnlinePlayer
	if is_instance_valid(player):
		player.respawn_at(at_transform, sequence)


func _is_host_authority() -> bool:
	return not multiplayer.has_multiplayer_peer() or multiplayer.is_server()


## Runs on the host only, a few times a second. Anything that has broken since
## the last pass is told to everyone.
##
## Every peer has already applied the same damage volumes to the same
## deterministic flora and should already agree; this is the correction for when
## they do not, and it is cheap precisely because agreement is the normal case
## and the list is nearly always empty.
func confirm_flora_breaks() -> void:
	var broadcasting := multiplayer.has_multiplayer_peer() \
		and multiplayer.is_server() and multiplayer.get_peers().size() > 0
	for field in get_tree().get_nodes_in_group(DamageHit.FIELD_GROUP):
		if not (field is Node) or not DamageHit.in_same_world(self, field) \
				or not field.has_method(&"drain_new_breaks"):
			continue
		# Drained whether or not it is going anywhere. On a client nothing reads
		# the list, and left alone it would grow all session.
		var keys: PackedInt32Array = field.call(&"drain_new_breaks")
		if broadcasting and not keys.is_empty():
			_apply_flora_breaks.rpc(String(get_path_to(field)), keys)


@rpc("authority", "call_remote", "reliable")
func _apply_flora_breaks(path: String, keys: PackedInt32Array) -> void:
	var field := get_node_or_null(NodePath(path))
	if field != null and field.has_method(&"apply_broken_keys"):
		field.call(&"apply_broken_keys", keys)


## Undoes every break inside a sphere and reports how many plants stood back up.
##
## The sphere goes over the wire rather than the plants in it: flora is placed
## deterministically, so every peer can work out for itself which of its own
## instances the volume covers, exactly as it already does for the damage that
## broke them. Called by an encounter that resets the ground it was fought over.
func regrow_flora(centre: Vector3, radius: float) -> int:
	if not _is_host_authority():
		return 0
	if multiplayer.has_multiplayer_peer() and not multiplayer.get_peers().is_empty():
		_apply_flora_regrow.rpc(centre, radius)
	return _regrow_flora_here(centre, radius)


@rpc("authority", "call_remote", "reliable")
func _apply_flora_regrow(centre: Vector3, radius: float) -> void:
	_regrow_flora_here(centre, radius)


func _regrow_flora_here(centre: Vector3, radius: float) -> int:
	var restored := 0
	for field in get_tree().get_nodes_in_group(DamageHit.FIELD_GROUP):
		if not (field is Node) or not DamageHit.in_same_world(self, field) \
				or not field.has_method(&"restore_within"):
			continue
		restored += int(field.call(&"restore_within", centre, radius))
	return restored


func pickup_node(pickup_id: int) -> DroppedItem:
	return _pickup_nodes.get(pickup_id) as DroppedItem


## Stable join-in-progress representation of every live, unclaimed pickup.
func pickup_snapshots() -> Array:
	var snapshots: Array = []
	var ids := _pickups.keys()
	ids.sort()
	for id_variant in ids:
		var pickup_id := int(id_variant)
		var record: Dictionary = _pickups.get(pickup_id, {})
		if record.is_empty() or bool(record.get("claimed", false)):
			continue
		var kind := str(record.get("kind", ""))
		if kind == "crawler":
			snapshots.append({
				"pickup_id": pickup_id,
				"kind": "crawler",
				"payload": record.get("payload", {}),
				"transform": record.get("transform", Transform3D.IDENTITY),
			})
			continue
		if kind == "crawler_hat":
			snapshots.append({
				"pickup_id": pickup_id,
				"kind": "crawler_hat",
				"item_id": str(record.get("item_id", "")),
				"transform": record.get("transform", Transform3D.IDENTITY),
			})
			continue
		snapshots.append({
			"pickup_id": pickup_id,
			"item_id": str(record.get("item_id", "")),
			"transform": record.get("transform", Transform3D.IDENTITY),
		})
	return snapshots


## Where the local player will be put when a session opens, overriding the spawn
## markers. The home screen uses it to start the player exactly where the
## character it has been showing was standing.
func override_local_spawn(at_transform: Transform3D, force := false) -> void:
	_spawn_override = at_transform
	_has_spawn_override = true
	_force_spawn_override = force


func override_local_look(look: Dictionary) -> void:
	_look_override = look.duplicate(true)
	_has_look_override = true


func _open_home_screen() -> void:
	if celestial_cycle != null and celestial_cycle.period_seconds > 0.0:
		celestial_cycle.set_phase(
			HOME_SUN_ADVANCE_SECONDS / celestial_cycle.period_seconds)
	_home_screen = HomeScreen.new()
	_home_screen.name = "HomeScreen"
	_home_screen.frame = _spawn_transform(1)
	add_child(_home_screen)


func _begin_session() -> void:
	if _session_open:
		return
	var restore := GameSave.take_pending()
	if not restore.is_empty():
		_begin_saved_session(restore)
		return
	_session_open = true
	LagTracker.note("session", "world session opened  host=%s" % multiplayer.is_server())
	if multiplayer.is_server():
		# The world is already rendering behind the title screen. Story starts
		# at authored noon over the landing; crawler starts at dusk on the pad.
		# Joining clients receive this phase below.
		celestial_cycle.set_day_index(0)
		if CrawlerRules.active():
			_sync_crawler_twilight()
		else:
			celestial_cycle.set_phase(0.0)
		for peer_id in NetworkManager.players:
			_spawn_player(
				int(peer_id),
				NetworkManager.get_player_metadata(int(peer_id)),
				_spawn_transform(int(peer_id)),
				not CrawlerRules.active()
			)
	else:
		_request_world_state.rpc_id(1)
	if CrawlerRules.active():
		call_deferred(&"_seed_crawler_cities", 0)
		call_deferred(&"_ensure_crawler_horde")
		call_deferred(&"_ensure_crawler_statues", 0)


func _begin_saved_session(payload: Dictionary) -> void:
	_session_open = true
	_restore_payload = payload
	LagTracker.note("session", "world session restored from disk")
	_prepare_saved_spawns(payload)
	var look: Variant = payload.get("look", {})
	if look is Dictionary and not (look as Dictionary).is_empty():
		override_local_look(look)
	var world_state: Dictionary = payload.get("world", {})
	if celestial_cycle != null:
		celestial_cycle.set_day_index(int(world_state.get("day_index", 0)))
		var phase := float(world_state.get("phase", -1.0))
		if phase >= 0.0:
			celestial_cycle.set_phase(phase)
	_crawler_city_gift_claimed = true
	if multiplayer.is_server():
		for peer_id in NetworkManager.players:
			_spawn_player(
				int(peer_id),
				NetworkManager.get_player_metadata(int(peer_id)),
				_spawn_transform(int(peer_id)),
				not CrawlerRules.active()
			)
		_restore_roster(payload)
	if CrawlerRules.active():
		call_deferred(&"_seed_crawler_cities", 0)
		call_deferred(&"_ensure_crawler_horde")
		call_deferred(&"_ensure_crawler_statues", 0)
	call_deferred(&"_finish_saved_world", 0)


func _finish_saved_world(tries := 0) -> void:
	if _restore_payload.is_empty():
		return
	if CrawlerRules.active() and get_node_or_null("CrawlerCityRing") == null \
			and tries < 12:
		call_deferred(&"_finish_saved_world", tries + 1)
		return
	apply_saved_world(_restore_payload)
	_restore_payload = {}


func apply_disk_save(payload: Dictionary, broadcast := true) -> bool:
	if payload.is_empty() or not _session_open:
		return false
	GameSave.apply_run_payloads(payload)
	var session: Variant = payload.get("session", {})
	if session is Dictionary:
		for key: Variant in session:
			NetworkManager.session_options[str(key)] = (session as Dictionary)[key]
	_prepare_saved_spawns(payload)
	var player := local_player()
	if player != null:
		var look: Variant = payload.get("look", {})
		if look is Dictionary and not (look as Dictionary).is_empty():
			CharacterDB.save_look(look)
			player.apply_look(look)
	_restore_roster(payload)
	apply_saved_world(payload)
	if broadcast and multiplayer.is_server() and not NetworkManager.is_single_player:
		_apply_remote_save.rpc(payload)
	return true


@rpc("authority", "call_remote", "reliable")
func _apply_remote_save(payload: Dictionary) -> void:
	apply_disk_save(payload, false)


func apply_saved_world(payload: Dictionary) -> void:
	var world_state: Variant = payload.get("world", {})
	if typeof(world_state) != TYPE_DICTIONARY:
		return
	var state := world_state as Dictionary
	if celestial_cycle != null:
		celestial_cycle.set_day_index(int(state.get("day_index", celestial_cycle.day_index())))
		var phase := float(state.get("phase", -1.0))
		if phase >= 0.0:
			celestial_cycle.set_phase(phase)
	_clear_live_pickups()
	var pickups: Variant = state.get("pickups", [])
	if pickups is Array:
		for pickup_variant: Variant in pickups:
			if pickup_variant is Dictionary:
				_restore_saved_pickup(pickup_variant)
	apply_scar_snapshot(state.get("scars", []) as Array if state.get("scars", []) is Array else [])
	var flora: Variant = state.get("flora", {})
	if flora is Dictionary:
		apply_flora_snapshot(flora)
	var boss: Variant = state.get("bigfoot", {})
	if boss is Dictionary:
		apply_bigfoot_snapshot(boss)
	_clear_ability_constructs()
	var constructs: Variant = state.get("constructs", [])
	if constructs is Array:
		apply_ability_construct_snapshot(constructs)
	var horde: Variant = state.get("horde", {})
	if horde is Dictionary:
		apply_horde_snapshot(horde)
	_next_pickup_id = maxi(int(state.get("next_pickup_id", _next_pickup_id)), _next_pickup_id)
	_next_ability_construct_id = maxi(
		int(state.get("next_construct_id", _next_ability_construct_id)),
		_next_ability_construct_id)
	_crawler_city_gift_id = int(state.get("city_gift_id", _crawler_city_gift_id))
	_crawler_city_gift_claimed = bool(state.get("city_gift_claimed", _crawler_city_gift_claimed))
	var duel: Variant = state.get("duel", {})
	if duel is Dictionary:
		_apply_duel_snapshot(duel)
	else:
		_duel_active = false
		_duel_returns.clear()
	var training: Variant = state.get("training", {})
	if training is Dictionary:
		_apply_training_snapshot(training)
	else:
		_training_active = false
		_training_returns.clear()
		_training_level = 1


func _apply_saved_player(player: OnlinePlayer, player_state: Variant) -> void:
	if player == null or typeof(player_state) != TYPE_DICTIONARY:
		return
	var state := player_state as Dictionary
	var xf := GameSave.unpack_transform(state.get("transform", {}))
	if xf.origin.length_squared() > 0.01:
		player.global_transform = xf
	if state.has("pitch"):
		player.set_look_pitch(float(state.get("pitch", 0.0)))
	var combat: Variant = state.get("combat", {})
	if combat is Dictionary and not (combat as Dictionary).is_empty():
		player.apply_combat_snapshot(combat)
	if state.has("worn"):
		var worn := PackedStringArray()
		var worn_raw: Variant = state.get("worn", [])
		if worn_raw is PackedStringArray:
			worn = worn_raw
		elif worn_raw is Array:
			for item: Variant in worn_raw:
				worn.append(str(item))
		player.apply_worn(worn)
	if state.has("held"):
		player.apply_held(str(state.get("held", "")))


func player_roster_snapshot() -> Array:
	var roster: Array = []
	var ids: Array = _spawned_players.keys()
	ids.sort()
	for id_variant: Variant in ids:
		var peer_id := int(id_variant)
		var player := _spawned_players.get(peer_id) as OnlinePlayer
		if not is_instance_valid(player):
			continue
		if player.crawler_progress != null:
			player.crawler_progress.remember()
		if player.crawler_kit != null:
			player.crawler_kit.remember()
		var meta := NetworkManager.get_player_metadata(peer_id)
		roster.append({
			"peer_id": peer_id,
			"steam_id": int(meta.get("steam_id", 0)),
			"name": str(meta.get("name", player.display_name)),
			"transform": player.global_transform,
			"pitch": player.look_pitch(),
			"combat": player.combat_snapshot(),
			"worn": player.worn_items(),
			"held": player.held_item(),
			"body": player.body_id(),
			"progress": player.crawler_progress.to_dict() if player.crawler_progress != null else {},
			"kit": player.crawler_kit.to_dict() if player.crawler_kit != null else {},
		})
	return roster


func _prepare_saved_spawns(payload: Dictionary) -> void:
	_peer_spawns.clear()
	if NetworkManager == null:
		return
	for peer_variant: Variant in NetworkManager.players.keys():
		var peer_id := int(peer_variant)
		var meta := NetworkManager.get_player_metadata(peer_id)
		var entry := GameSave.match_roster(payload, peer_id, meta)
		if not entry.is_empty():
			var xf := GameSave.unpack_transform(entry.get("transform", {}))
			if xf.origin.length_squared() > 0.01:
				_peer_spawns[peer_id] = xf
				if peer_id == multiplayer.get_unique_id():
					override_local_spawn(xf, true)
				continue
		_peer_spawns[peer_id] = _crawler_pad_transform(peer_id)


func _restore_roster(payload: Dictionary) -> void:
	var coop := GameSave.is_coop_save(payload)
	for id_variant: Variant in _spawned_players.keys():
		var peer_id := int(id_variant)
		var player := _spawned_players.get(peer_id) as OnlinePlayer
		if not is_instance_valid(player):
			continue
		var entry := GameSave.match_roster(
			payload, peer_id, NetworkManager.get_player_metadata(peer_id))
		if entry.is_empty():
			player.global_transform = _crawler_pad_transform(peer_id)
			player.reset_physics_interpolation()
			player.reset_network_state(player.global_transform)
			if not coop:
				_seed_guest_crawler(player)
			continue
		_apply_saved_roster_player(player, entry)


func _apply_saved_roster_player(player: OnlinePlayer, entry: Dictionary) -> void:
	var progress: Variant = entry.get("progress", {})
	if player.crawler_progress != null and progress is Dictionary \
			and not (progress as Dictionary).is_empty():
		player.crawler_progress.from_dict(progress)
		player.crawler_progress.remember()
		player.refresh_crawler_look()
		CrawlerSites.apply_progress(player.crawler_progress, get_tree())
	var kit: Variant = entry.get("kit", {})
	if player.crawler_kit != null and kit is Dictionary \
			and not (kit as Dictionary).is_empty():
		player.crawler_kit.from_dict(kit)
		player.crawler_kit.remember()
		player.sync_crawler_ability_bar()
	_apply_saved_player(player, entry)


func _seed_guest_crawler(player: OnlinePlayer) -> void:
	if player.crawler_progress != null:
		player.crawler_progress.from_dict({})
		var meta := NetworkManager.get_player_metadata(player.peer_id)
		if meta.is_empty() and player.peer_id == multiplayer.get_unique_id():
			var look := CharacterDB.load_look()
			player.crawler_progress.seed_look_hat(look)
			player.crawler_progress.seed_look_cape(look)
		else:
			player.crawler_progress.seed_look_hat(meta)
			player.crawler_progress.seed_look_cape(meta)
		player.crawler_progress.remember()
		player.refresh_crawler_look()
	if player.crawler_kit != null:
		player.crawler_kit.seed_starter()
		player.crawler_kit.remember()
		player.sync_crawler_ability_bar()


func request_start_duel() -> void:
	if multiplayer.has_multiplayer_peer() and not multiplayer.is_server():
		_request_start_duel.rpc_id(1)
		return
	_start_city_duel()


@rpc("any_peer", "reliable")
func _request_start_duel() -> void:
	if multiplayer.is_server():
		_start_city_duel()


func request_end_duel() -> void:
	if multiplayer.has_multiplayer_peer() and not multiplayer.is_server():
		_request_end_duel.rpc_id(1)
		return
	_end_city_duel()


@rpc("any_peer", "reliable")
func _request_end_duel() -> void:
	if multiplayer.is_server():
		_end_city_duel()


func request_duel_respawn() -> void:
	if multiplayer.has_multiplayer_peer() and not multiplayer.is_server():
		_request_duel_respawn.rpc_id(1)
		return
	_duel_respawn_peer(multiplayer.get_unique_id())


@rpc("any_peer", "reliable")
func _request_duel_respawn() -> void:
	if multiplayer.is_server():
		_duel_respawn_peer(multiplayer.get_remote_sender_id())


func _start_city_duel() -> void:
	if _duel_active or _training_active or not CrawlerRules.coop():
		return
	if NetworkManager == null or NetworkManager.players.size() < 2:
		return
	_duel_active = true
	_duel_returns.clear()
	var ids: Array = _spawned_players.keys()
	ids.sort()
	var centre := _duel_centre_transform()
	var count := maxi(ids.size(), 1)
	var returns := {}
	var poses := {}
	var index := 0
	for id_variant: Variant in ids:
		var peer_id := int(id_variant)
		var player := _spawned_players.get(peer_id) as OnlinePlayer
		if not is_instance_valid(player):
			continue
		returns[str(peer_id)] = player.global_transform
		poses[str(peer_id)] = _ring_offset(centre, index, count, 6.0)
		index += 1
	_duel_returns = returns
	if multiplayer.has_multiplayer_peer() and not multiplayer.get_peers().is_empty():
		_apply_duel_start.rpc(returns, poses)
	else:
		_apply_duel_start(returns, poses)


func _end_city_duel() -> void:
	if not _duel_active:
		return
	var returns := _duel_returns.duplicate(true)
	if multiplayer.has_multiplayer_peer() and not multiplayer.get_peers().is_empty():
		_apply_duel_end.rpc(returns)
	else:
		_apply_duel_end(returns)


func _duel_respawn_peer(peer_id: int) -> void:
	if not _duel_active or peer_id <= 0:
		return
	var player := _spawned_players.get(peer_id) as OnlinePlayer
	if not is_instance_valid(player):
		return
	var at := player.global_transform
	var ids: Array = _spawned_players.keys()
	ids.sort()
	var index := ids.find(peer_id)
	if index < 0:
		index = 0
	at = _ring_offset(_duel_centre_transform(), index, maxi(ids.size(), 1), 6.0)
	var sequence := int(_respawn_sequence.get(peer_id, 0)) + 1
	_respawn_sequence[peer_id] = sequence
	if multiplayer.has_multiplayer_peer() and not multiplayer.get_peers().is_empty():
		_apply_colony_respawn.rpc(peer_id, at, sequence)
	else:
		_apply_colony_respawn(peer_id, at, sequence)


@rpc("authority", "call_local", "reliable")
func _apply_duel_start(returns: Dictionary, poses: Dictionary) -> void:
	_duel_active = true
	_duel_returns = returns.duplicate(true)
	var horde := get_node_or_null("CrawlerHorde")
	if horde != null and horde.has_method(&"clear_wild"):
		horde.call(&"clear_wild")
	for id_variant: Variant in _spawned_players.keys():
		var peer_id := int(id_variant)
		var player := _spawned_players.get(peer_id) as OnlinePlayer
		if not is_instance_valid(player):
			continue
		var at := GameSave.unpack_transform(poses.get(str(peer_id), {}))
		if at.origin.length_squared() < 0.01:
			continue
		if player.is_dead():
			player.respawn_at(at)
		else:
			player.global_transform = at
			player.reset_physics_interpolation()
			player.reset_network_state(at)
		if player.has_method(&"apply_heal"):
			player.apply_heal(player.maximum_health())


@rpc("authority", "call_local", "reliable")
func _apply_duel_end(returns: Dictionary) -> void:
	_duel_active = false
	for id_variant: Variant in _spawned_players.keys():
		var peer_id := int(id_variant)
		var player := _spawned_players.get(peer_id) as OnlinePlayer
		if not is_instance_valid(player):
			continue
		var at := GameSave.unpack_transform(returns.get(str(peer_id), {}))
		if at.origin.length_squared() < 0.01:
			continue
		if player.is_dead():
			player.respawn_at(at)
		else:
			player.global_transform = at
			player.reset_physics_interpolation()
			player.reset_network_state(at)
	_duel_returns.clear()


func _apply_duel_snapshot(wire: Dictionary) -> void:
	_duel_active = bool(wire.get("active", false))
	var held: Variant = wire.get("returns", {})
	_duel_returns = held.duplicate(true) if held is Dictionary else {}


func request_start_training() -> void:
	if multiplayer.has_multiplayer_peer() and not multiplayer.is_server():
		_request_start_training.rpc_id(1)
		return
	_start_training_session()


@rpc("any_peer", "reliable")
func _request_start_training() -> void:
	if multiplayer.is_server():
		_start_training_session()


func request_end_training() -> void:
	if multiplayer.has_multiplayer_peer() and not multiplayer.is_server():
		_request_end_training.rpc_id(1)
		return
	_end_training_session()


@rpc("any_peer", "reliable")
func _request_end_training() -> void:
	if multiplayer.is_server():
		_end_training_session()


func request_training_level(level: int) -> void:
	if multiplayer.has_multiplayer_peer() and not multiplayer.is_server():
		_request_training_level.rpc_id(1, level)
		return
	_set_training_level(level)


@rpc("any_peer", "reliable")
func _request_training_level(level: int) -> void:
	if multiplayer.is_server():
		_set_training_level(level)


func request_training_respawn() -> void:
	if multiplayer.has_multiplayer_peer() and not multiplayer.is_server():
		_request_training_respawn.rpc_id(1)
		return
	_training_respawn_peer(multiplayer.get_unique_id())


@rpc("any_peer", "reliable")
func _request_training_respawn() -> void:
	if multiplayer.is_server():
		_training_respawn_peer(multiplayer.get_remote_sender_id())


func _start_training_session() -> void:
	if _training_active or _duel_active or not CrawlerRules.active():
		return
	_training_active = true
	_training_level = 1
	_training_returns.clear()
	var ids: Array = _spawned_players.keys()
	ids.sort()
	var centre := _training_centre_transform()
	var returns := {}
	var poses := {}
	var index := 0
	for id_variant: Variant in ids:
		var peer_id := int(id_variant)
		var player := _spawned_players.get(peer_id) as OnlinePlayer
		if not is_instance_valid(player):
			continue
		returns[str(peer_id)] = player.global_transform
		poses[str(peer_id)] = _ring_offset(centre, index, maxi(ids.size(), 1), 8.0)
		index += 1
	_training_returns = returns
	if multiplayer.has_multiplayer_peer() and not multiplayer.get_peers().is_empty():
		_apply_training_start.rpc(returns, poses, _training_level)
	else:
		_apply_training_start(returns, poses, _training_level)


func _end_training_session() -> void:
	if not _training_active:
		return
	var returns := _training_returns.duplicate(true)
	if multiplayer.has_multiplayer_peer() and not multiplayer.get_peers().is_empty():
		_apply_training_end.rpc(returns)
	else:
		_apply_training_end(returns)


func _set_training_level(level: int) -> void:
	if not _training_active:
		return
	var next := TRAINING.clamp_level(level)
	if multiplayer.has_multiplayer_peer() and not multiplayer.get_peers().is_empty():
		_apply_training_level.rpc(next)
	else:
		_apply_training_level(next)


func _training_respawn_peer(peer_id: int) -> void:
	if not _training_active or peer_id <= 0:
		return
	var player := _spawned_players.get(peer_id) as OnlinePlayer
	if not is_instance_valid(player):
		return
	var ids: Array = _spawned_players.keys()
	ids.sort()
	var index := ids.find(peer_id)
	if index < 0:
		index = 0
	var at := _ring_offset(_training_centre_transform(), index, maxi(ids.size(), 1), 8.0)
	var sequence := int(_respawn_sequence.get(peer_id, 0)) + 1
	_respawn_sequence[peer_id] = sequence
	if multiplayer.has_multiplayer_peer() and not multiplayer.get_peers().is_empty():
		_apply_colony_respawn.rpc(peer_id, at, sequence)
	else:
		_apply_colony_respawn(peer_id, at, sequence)


@rpc("authority", "call_local", "reliable")
func _apply_training_start(returns: Dictionary, poses: Dictionary, level: int) -> void:
	_training_active = true
	_training_returns = returns.duplicate(true)
	_training_level = TRAINING.clamp_level(level)
	_seat_training_players(poses)
	_register_training_flora()
	_ensure_crawler_horde()
	var horde := get_node_or_null("CrawlerHorde") as CrawlerHorde
	if horde != null:
		horde.spawn_training_field(_training_centre_transform(), _training_level)


@rpc("authority", "call_local", "reliable")
func _apply_training_end(returns: Dictionary) -> void:
	var horde := get_node_or_null("CrawlerHorde") as CrawlerHorde
	if horde != null:
		horde.clear_training()
	BuildingFloraClear.unregister(TRAINING.CLEAR_ID)
	_training_active = false
	for id_variant: Variant in _spawned_players.keys():
		var peer_id := int(id_variant)
		var player := _spawned_players.get(peer_id) as OnlinePlayer
		if not is_instance_valid(player):
			continue
		var at := GameSave.unpack_transform(returns.get(str(peer_id), {}))
		if at.origin.length_squared() < 0.01:
			continue
		if player.is_dead():
			player.respawn_at(at)
		else:
			player.global_transform = at
			player.reset_physics_interpolation()
			player.reset_network_state(at)
	_training_returns.clear()
	_training_level = 1


@rpc("authority", "call_local", "reliable")
func _apply_training_level(level: int) -> void:
	_training_level = TRAINING.clamp_level(level)
	var horde := get_node_or_null("CrawlerHorde") as CrawlerHorde
	if horde != null:
		horde.set_training_level(_training_level)


func _apply_training_snapshot(wire: Dictionary) -> void:
	_training_active = bool(wire.get("active", false))
	var held: Variant = wire.get("returns", {})
	_training_returns = held.duplicate(true) if held is Dictionary else {}
	_training_level = TRAINING.clamp_level(int(wire.get("level", 1)))
	if _training_active:
		_register_training_flora()
		call_deferred(&"_ensure_training_field")


func _ensure_training_field() -> void:
	if not _training_active:
		return
	var horde := get_node_or_null("CrawlerHorde") as CrawlerHorde
	if horde == null:
		return
	if horde.training_count() > 0:
		return
	if multiplayer.has_multiplayer_peer() and not multiplayer.is_server():
		return
	horde.spawn_training_field(_training_centre_transform(), _training_level)


func _seat_training_players(poses: Dictionary) -> void:
	for id_variant: Variant in _spawned_players.keys():
		var peer_id := int(id_variant)
		var player := _spawned_players.get(peer_id) as OnlinePlayer
		if not is_instance_valid(player):
			continue
		var at := GameSave.unpack_transform(poses.get(str(peer_id), {}))
		if at.origin.length_squared() < 0.01:
			continue
		if player.is_dead():
			player.respawn_at(at)
		else:
			player.global_transform = at
			player.reset_physics_interpolation()
			player.reset_network_state(at)
		if player.has_method(&"apply_heal"):
			player.apply_heal(player.maximum_health())


func _register_training_flora() -> void:
	var centre := _training_centre_transform()
	if centre.origin.length_squared() < 0.01:
		return
	var radius := 8000.0
	var host := planet()
	if host != null and host.shape != null:
		radius = host.shape.radius
	BuildingFloraClear.register(
		TRAINING.CLEAR_ID, centre.origin, TRAINING.FLORA_CLEAR, radius, 0.0)


func _training_centre_transform() -> Transform3D:
	var overlay := _land_patches()
	if overlay != null:
		var seated := overlay.surface_transform_for_direction(_training_direction(), 1.35)
		if seated.origin.length_squared() > 1.0:
			return seated
	var fallback := Transform3D(Basis.IDENTITY, TRAINING.FALLBACK_ORIGIN)
	var start := _crawler_start_transform()
	if start.origin.length_squared() > 1.0:
		var dir := _training_direction()
		fallback.origin = dir * maxf(start.origin.length(), 1.0) \
			+ Vector3(0.0, TRAINING.FALLBACK_ORIGIN.y, 0.0)
	return fallback


func _training_direction() -> Vector3:
	var start := _crawler_start_transform().origin
	if start.length_squared() < 0.01:
		start = Vector3.FORWARD
	var axis := start.cross(Vector3.UP)
	if axis.length_squared() < 0.01:
		axis = start.cross(Vector3.RIGHT)
	if axis.length_squared() < 0.01:
		return Vector3.RIGHT
	return start.rotated(axis.normalized(), PI * 0.5).normalized()


func _duel_centre_transform() -> Transform3D:
	var from := Vector3.ZERO
	var local := local_player()
	if local != null:
		from = local.global_position
	var best := Transform3D()
	var best_d := INF
	if is_inside_tree():
		for node in get_tree().get_nodes_in_group(PatchCity.PAD_GROUP):
			var city := node as Node3D
			if city == null:
				continue
			var d := city.global_position.distance_squared_to(from) if from.length_squared() > 0.0001 \
				else 0.0
			if d < best_d:
				best_d = d
				best = city.global_transform
				var up := best.basis.y
				if up.length_squared() < 0.0001:
					up = Vector3.UP
				best.origin += up.normalized() * 2.0
	if best.origin.length_squared() > 1.0:
		return best
	return _crawler_start_transform()


func _ring_offset(centre: Transform3D, index: int, count: int, radius: float) -> Transform3D:
	var at := centre
	var n := maxi(count, 1)
	if n <= 1:
		return at
	var up := at.basis.y
	if up.length_squared() < 0.0001:
		up = Vector3.UP
	up = up.normalized()
	var right := up.cross(Vector3.FORWARD)
	if right.length_squared() < 0.0001:
		right = up.cross(Vector3.RIGHT)
	right = right.normalized()
	var forward := up.cross(right).normalized()
	var angle := TAU * float(posmod(index, n)) / float(n)
	var along := (right * cos(angle) + forward * sin(angle))
	at.origin += along * radius
	if along.length_squared() > 0.0001:
		at.basis = Basis.looking_at(-along, up)
	return at


func _restore_saved_pickup(pickup: Dictionary) -> void:
	var pickup_id := int(pickup.get("pickup_id", 0))
	if pickup_id <= 0:
		return
	var at: Transform3D = GameSave.unpack_transform(pickup.get("transform", {}))
	if str(pickup.get("kind", "")) == "crawler" or pickup.has("payload"):
		_spawn_crawler_pickup_local(pickup_id, pickup.get("payload", {}), at)
		return
	if str(pickup.get("kind", "")) == "crawler_hat":
		_spawn_crawler_hat_pickup_local(pickup_id, str(pickup.get("item_id", "")), at)
		return
	_spawn_pickup_local(pickup_id, str(pickup.get("item_id", "")), at)


func _clear_live_pickups() -> void:
	var ids: Array = _pickups.keys()
	for id_variant: Variant in ids:
		_despawn_pickup_local(int(id_variant))


func _clear_ability_constructs() -> void:
	var ids: Array = _ability_constructs.keys()
	for id_variant: Variant in ids:
		_apply_ability_construct_despawn(int(id_variant))


func horde_snapshot() -> Dictionary:
	var horde := get_node_or_null("CrawlerHorde")
	if horde != null and horde.has_method(&"horde_snapshot"):
		var held: Variant = horde.call(&"horde_snapshot")
		return held as Dictionary if held is Dictionary else {}
	return {}


func apply_horde_snapshot(wire: Dictionary) -> void:
	if wire.is_empty():
		return
	_ensure_crawler_horde()
	var horde := get_node_or_null("CrawlerHorde")
	if horde != null and horde.has_method(&"apply_horde_snapshot"):
		horde.call(&"apply_horde_snapshot", wire)


## What being in a menu costs. Escape used to raise a pause card of the world's
## own; now [GameMenu] is that card and calls this instead, but the policy stays
## here because it is about the session and not about the menu:
##
## - **Single player** really stops. There is nobody else in the world to keep it
##   turning for, and stopping means you can read a settings page without falling
##   out of the sky while you do.
## - **In company** nothing stops. The other players are still playing, so all this
##   can honestly do is take the mouse and stop taking this player's input — which
##   [method OnlinePlayer.open_menu] has already done by the time this is called.
func set_local_pause(paused: bool) -> void:
	var freeze_simulation := paused and NetworkManager.is_single_player
	if paused != _locally_paused or freeze_simulation != _simulation_frozen:
		LagTracker.note("ui", "local pause %s  freeze=%s" % [paused, freeze_simulation])
	_locally_paused = paused
	if freeze_simulation == _simulation_frozen:
		get_tree().paused = freeze_simulation
		return
	_simulation_frozen = freeze_simulation
	if freeze_simulation:
		_time_scale_before_pause = Engine.time_scale
		if celestial_cycle != null:
			celestial_cycle.set_time_paused(true)
		# SceneTree pause stops nodes; zero time scale also freezes shader TIME,
		# so wind, water, clouds, lava, and other material animation do not keep
		# moving behind the translucent menu.
		Engine.time_scale = 0.0
		get_tree().paused = true
		return

	get_tree().paused = false
	Engine.time_scale = _time_scale_before_pause
	if celestial_cycle != null:
		celestial_cycle.set_time_paused(false)


## Whether a menu is holding this player out of the world. Not the same question as
## `get_tree().paused`, which is only true in single player, and the reason this is
## worth asking separately: in company the world keeps turning and this is still the
## honest answer to "am I in a menu".
func locally_paused() -> bool:
	return _locally_paused


## Drop the session and go back to the home screen. Reached from GameMenu's
## HOLD LEAVE action; the menu raises it rather than doing it, because what a
## world is is this node's business.
func leave_session() -> void:
	set_local_pause(false)
	NetworkManager.leave_game()
	if NetworkManager.menu_scene_path.is_empty():
		queue_free()


## Public red-menu entry point. A client sends only the source claim; the server
## derives the owner from the RPC sender. A host/single-player call is accepted
## only for its own local peer, so this API cannot be used to name another body.
func request_drop(
		peer_id: int,
		source: String,
		index: int,
		expected_item_id: String
	) -> void:
	var local_id := multiplayer.get_unique_id()
	if peer_id != local_id:
		return
	var player := _spawned_players.get(local_id) as OnlinePlayer
	if not is_instance_valid(player):
		return
	if multiplayer.is_server():
		_server_drop(local_id, source, index, expected_item_id,
			player.inventory_generation())
		return
	player.sync_loadout_to_server()
	_request_drop_from_client.rpc_id(
		1, source, index, expected_item_id, player.inventory_generation())


@rpc("any_peer", "call_remote", "reliable")
func _request_drop_from_client(
		source: String,
		index: int,
		expected_item_id: String,
		generation: int
	) -> void:
	if not multiplayer.is_server():
		return
	var sender := multiplayer.get_remote_sender_id()
	if NetworkManager.state != NetworkManager.SessionState.IN_GAME \
			or not NetworkManager.is_peer_registered(sender):
		return
	_server_drop(sender, source, index, expected_item_id, generation)


## Public DroppedItem entry point, with the same sender derivation as drop.
func request_pickup(pickup_id: int, peer_id: int) -> void:
	var local_id := multiplayer.get_unique_id()
	if peer_id != local_id:
		return
	var player := _spawned_players.get(local_id) as OnlinePlayer
	if not is_instance_valid(player):
		return
	if multiplayer.is_server():
		_server_pickup(local_id, pickup_id, player.inventory_generation())
		return
	player.sync_loadout_to_server()
	_request_pickup_from_client.rpc_id(
		1, pickup_id, player.inventory_generation())


@rpc("any_peer", "call_remote", "reliable")
func _request_pickup_from_client(pickup_id: int, generation: int) -> void:
	if not multiplayer.is_server():
		return
	var sender := multiplayer.get_remote_sender_id()
	if NetworkManager.state != NetworkManager.SessionState.IN_GAME \
			or not NetworkManager.is_peer_registered(sender):
		return
	_server_pickup(sender, pickup_id, generation)


func request_crawler_drop(
		peer_id: int,
		source: String,
		index: int,
		expected_token: String
	) -> void:
	var local_id := multiplayer.get_unique_id()
	if peer_id != local_id:
		return
	var player := _spawned_players.get(local_id) as OnlinePlayer
	if not is_instance_valid(player) or player.crawler_kit == null:
		return
	if multiplayer.is_server():
		_server_crawler_drop(
			local_id, source, index, expected_token, player.inventory_generation())
		return
	player.sync_loadout_to_server()
	_request_crawler_drop_from_client.rpc_id(
		1, source, index, expected_token, player.inventory_generation())


@rpc("any_peer", "call_remote", "reliable")
func _request_crawler_drop_from_client(
		source: String,
		index: int,
		expected_token: String,
		generation: int
	) -> void:
	if not multiplayer.is_server():
		return
	var sender := multiplayer.get_remote_sender_id()
	if NetworkManager.state != NetworkManager.SessionState.IN_GAME \
			or not NetworkManager.is_peer_registered(sender):
		return
	_server_crawler_drop(sender, source, index, expected_token, generation)


func request_crawler_pickup(pickup_id: int, peer_id: int) -> void:
	var local_id := multiplayer.get_unique_id()
	if peer_id != local_id:
		return
	var player := _spawned_players.get(local_id) as OnlinePlayer
	if not is_instance_valid(player):
		return
	if multiplayer.is_server():
		_dispatch_crawler_pickup(local_id, pickup_id, player.inventory_generation())
		return
	player.sync_loadout_to_server()
	_request_crawler_pickup_from_client.rpc_id(
		1, pickup_id, player.inventory_generation())


@rpc("any_peer", "call_remote", "reliable")
func _request_crawler_pickup_from_client(pickup_id: int, generation: int) -> void:
	if not multiplayer.is_server():
		return
	var sender := multiplayer.get_remote_sender_id()
	if NetworkManager.state != NetworkManager.SessionState.IN_GAME \
			or not NetworkManager.is_peer_registered(sender):
		return
	_dispatch_crawler_pickup(sender, pickup_id, generation)


func _server_crawler_drop(
		peer_id: int,
		source: String,
		index: int,
		expected_token: String,
		generation: int
	) -> int:
	if not multiplayer.is_server():
		return 0
	var player := _spawned_players.get(peer_id) as OnlinePlayer
	if not is_instance_valid(player) or player.crawler_kit == null \
			or not player.authoritative_inventory_ready() \
			or generation != player.inventory_generation():
		return 0
	var payload := player.crawler_kit.extract(source, index, expected_token)
	if payload.is_empty():
		return 0
	var next_generation := player.advance_inventory_generation()
	var pickup_id := _next_pickup_id
	_next_pickup_id += 1
	var at_transform := _crawler_drop_transform(player)
	_pickups[pickup_id] = {
		"kind": "crawler",
		"payload": payload,
		"transform": at_transform,
		"claimed": false,
	}
	_spawn_crawler_pickup_local(pickup_id, payload, at_transform, true)
	if multiplayer.has_multiplayer_peer():
		_spawn_crawler_pickup.rpc(pickup_id, payload, at_transform, true)
	if peer_id != multiplayer.get_unique_id():
		_confirm_crawler_drop.rpc_id(
			peer_id, pickup_id, source, index, expected_token, next_generation)
	return pickup_id


func _server_crawler_pickup(peer_id: int, pickup_id: int, generation: int) -> bool:
	if not multiplayer.is_server():
		return false
	var player := _spawned_players.get(peer_id) as OnlinePlayer
	var record: Dictionary = _pickups.get(pickup_id, {})
	if not is_instance_valid(player) or player.crawler_kit == null \
			or not player.authoritative_inventory_ready() \
			or generation != player.inventory_generation() or record.is_empty() \
			or bool(record.get("claimed", false)) \
			or str(record.get("kind", "")) != "crawler":
		return false
	var payload: Dictionary = record.get("payload", {})
	var at_transform: Transform3D = record.get(
		"transform", Transform3D.IDENTITY)
	if payload.is_empty() \
			or player.global_position.distance_to(
				_pickup_world_origin(pickup_id, at_transform.origin)) \
				> PICKUP_MAX_DISTANCE:
		return false
	record["claimed"] = true
	_pickups[pickup_id] = record
	var granted := player.crawler_kit.grant(payload, player.selected_ability_index())
	if not bool(granted.get("ok", false)):
		record["claimed"] = false
		_pickups[pickup_id] = record
		return false
	var next_generation := player.advance_inventory_generation()
	if pickup_id == _crawler_city_gift_id:
		_crawler_city_gift_claimed = true
	if peer_id != multiplayer.get_unique_id():
		_grant_crawler_pickup.rpc_id(
			peer_id, pickup_id, payload, next_generation)
	_despawn_pickup_local(pickup_id)
	if multiplayer.has_multiplayer_peer():
		_despawn_pickup.rpc(pickup_id)
	var displaced: Variant = granted.get("displaced", {})
	if displaced is Dictionary and not (displaced as Dictionary).is_empty():
		_server_crawler_spawn(player, displaced as Dictionary)
	return true


func spawn_displaced_crawler_card(player: OnlinePlayer, payload: Dictionary) -> int:
	if player == null or payload.is_empty():
		return 0
	if multiplayer.has_multiplayer_peer() and not multiplayer.is_server():
		return 0
	return _server_crawler_spawn(player, payload)


func _server_crawler_spawn(player: OnlinePlayer, payload: Dictionary) -> int:
	var pickup_id := _next_pickup_id
	_next_pickup_id += 1
	var at_transform := _crawler_drop_transform(player)
	_pickups[pickup_id] = {
		"kind": "crawler",
		"payload": payload,
		"transform": at_transform,
		"claimed": false,
	}
	_spawn_crawler_pickup_local(pickup_id, payload, at_transform, true)
	if multiplayer.has_multiplayer_peer():
		_spawn_crawler_pickup.rpc(pickup_id, payload, at_transform, true)
	return pickup_id


func spawn_crawler_card_loot(payload: Dictionary, at: Vector3) -> int:
	if payload.is_empty() or not at.is_finite():
		return 0
	if multiplayer.has_multiplayer_peer() and not multiplayer.is_server():
		return 0
	return _server_crawler_loot_spawn(payload, _loot_drop_transform(at, 0))


func spawn_crawler_kill_loot(drops: Array, at: Vector3) -> PackedInt32Array:
	var ids := PackedInt32Array()
	if not at.is_finite() or drops.is_empty():
		return ids
	if multiplayer.has_multiplayer_peer() and not multiplayer.is_server():
		return ids
	var index := 0
	for drop_variant: Variant in drops:
		if not drop_variant is Dictionary:
			continue
		var drop: Dictionary = drop_variant
		var kind := str(drop.get("kind", ""))
		var pose := _loot_drop_transform(at, index)
		index += 1
		if kind == CrawlerLoot.KIND_HAT:
			var hat_id := str(drop.get("id", ""))
			if CrawlerProgress.is_city_hat(hat_id):
				ids.append(_server_crawler_hat_spawn(hat_id, pose))
			continue
		var payload := CrawlerLoot.card_payload(drop)
		if not payload.is_empty():
			ids.append(_server_crawler_loot_spawn(payload, pose))
	return ids


func _dispatch_crawler_pickup(peer_id: int, pickup_id: int, generation: int) -> bool:
	var record: Dictionary = _pickups.get(pickup_id, {})
	if str(record.get("kind", "")) == "crawler_hat":
		return _server_crawler_hat_pickup(peer_id, pickup_id, generation)
	return _server_crawler_pickup(peer_id, pickup_id, generation)


func _server_crawler_loot_spawn(payload: Dictionary, at_transform: Transform3D) -> int:
	if payload.is_empty():
		return 0
	var pickup_id := _next_pickup_id
	_next_pickup_id += 1
	_pickups[pickup_id] = {
		"kind": "crawler",
		"payload": payload,
		"transform": at_transform,
		"claimed": false,
	}
	_spawn_crawler_pickup_local(pickup_id, payload, at_transform, true)
	if multiplayer.has_multiplayer_peer():
		_spawn_crawler_pickup.rpc(pickup_id, payload, at_transform, true)
	return pickup_id


func _server_crawler_hat_spawn(item_id: String, at_transform: Transform3D) -> int:
	if not CrawlerProgress.is_city_hat(item_id):
		return 0
	var pickup_id := _next_pickup_id
	_next_pickup_id += 1
	_pickups[pickup_id] = {
		"kind": "crawler_hat",
		"item_id": item_id,
		"transform": at_transform,
		"claimed": false,
	}
	_spawn_crawler_hat_pickup_local(pickup_id, item_id, at_transform, true)
	if multiplayer.has_multiplayer_peer():
		_spawn_crawler_hat_pickup.rpc(pickup_id, item_id, at_transform, true)
	return pickup_id


func _server_crawler_hat_pickup(peer_id: int, pickup_id: int, generation: int) -> bool:
	if not multiplayer.is_server():
		return false
	var player := _spawned_players.get(peer_id) as OnlinePlayer
	var record: Dictionary = _pickups.get(pickup_id, {})
	if not is_instance_valid(player) or player.crawler_progress == null \
			or not player.authoritative_inventory_ready() \
			or generation != player.inventory_generation() or record.is_empty() \
			or bool(record.get("claimed", false)) \
			or str(record.get("kind", "")) != "crawler_hat":
		return false
	var item_id := str(record.get("item_id", ""))
	var at_transform: Transform3D = record.get(
		"transform", Transform3D.IDENTITY)
	if not CrawlerProgress.is_city_hat(item_id) \
			or player.global_position.distance_to(
				_pickup_world_origin(pickup_id, at_transform.origin)) \
				> PICKUP_MAX_DISTANCE:
		return false
	record["claimed"] = true
	_pickups[pickup_id] = record
	var uid := player.crawler_progress.grant_hat(item_id)
	if uid.is_empty():
		record["claimed"] = false
		_pickups[pickup_id] = record
		return false
	player.refresh_crawler_look()
	var next_generation := player.advance_inventory_generation()
	if peer_id != multiplayer.get_unique_id():
		_grant_crawler_hat.rpc_id(peer_id, pickup_id, item_id, next_generation)
	_despawn_pickup_local(pickup_id)
	if multiplayer.has_multiplayer_peer():
		_despawn_pickup.rpc(pickup_id)
	return true


func _pickup_world_origin(pickup_id: int, fallback: Vector3) -> Vector3:
	var node := _pickup_nodes.get(pickup_id) as Node3D
	if node != null and is_instance_valid(node):
		return node.global_position
	return fallback


func _loot_drop_transform(at: Vector3, index: int) -> Transform3D:
	var up := at.normalized() if at.length_squared() > 0.01 else Vector3.UP
	var east := up.cross(Vector3.RIGHT if absf(up.y) > 0.9 else Vector3.UP)
	if east.length_squared() < 0.0001:
		east = Vector3.RIGHT
	east = east.normalized()
	var north := up.cross(east).normalized()
	var angle := TAU * (float(index) * 0.37 + 0.18)
	var span := 0.45 + 0.18 * float(index)
	var origin := at + (east * cos(angle) + north * sin(angle)) * span + up * 1.8
	return Transform3D(_upright_basis(north, up), origin)


@rpc("authority", "call_remote", "reliable")
func _spawn_crawler_hat_pickup(
		pickup_id: int,
		item_id: String,
		at_transform: Transform3D,
		settle_to_ground := false
	) -> void:
	_spawn_crawler_hat_pickup_local(pickup_id, item_id, at_transform, settle_to_ground)


func _spawn_crawler_hat_pickup_local(
		pickup_id: int,
		item_id: String,
		at_transform: Transform3D,
		settle_to_ground := false
	) -> void:
	if pickup_id <= 0 or not CrawlerProgress.is_city_hat(item_id):
		return
	var existing := _pickup_nodes.get(pickup_id) as Node
	if is_instance_valid(existing):
		return
	_pickups[pickup_id] = {
		"kind": "crawler_hat",
		"item_id": item_id,
		"transform": at_transform,
		"claimed": false,
	}
	var dropped := DroppedCrawlerHat.new()
	dropped.configure(pickup_id, item_id)
	add_child(dropped, true)
	dropped.global_transform = at_transform
	dropped.reset_physics_interpolation()
	if settle_to_ground:
		dropped.begin_settle()
	else:
		dropped.begin_hover()
	_pickup_nodes[pickup_id] = dropped


@rpc("authority", "call_remote", "reliable")
func _grant_crawler_hat(
		_pickup_id: int,
		item_id: String,
		generation: int
	) -> void:
	var player := local_player()
	if is_instance_valid(player) and player.crawler_progress != null:
		player.crawler_progress.grant_hat(item_id)
		player.refresh_crawler_look()
		player._inventory_generation = generation


@rpc("authority", "call_remote", "reliable")
func _confirm_crawler_drop(
		_pickup_id: int,
		source: String,
		index: int,
		token: String,
		generation: int
	) -> void:
	var player := local_player()
	if is_instance_valid(player) and player.crawler_kit != null:
		player.crawler_kit.extract(source, index, token)
		player._inventory_generation = generation


@rpc("authority", "call_remote", "reliable")
func _grant_crawler_pickup(
		_pickup_id: int,
		payload: Dictionary,
		generation: int
	) -> void:
	var player := local_player()
	if is_instance_valid(player) and player.crawler_kit != null:
		player.crawler_kit.grant(payload, player.selected_ability_index())
		player._inventory_generation = generation


@rpc("authority", "call_remote", "reliable")
func _spawn_crawler_pickup(
		pickup_id: int,
		payload: Dictionary,
		at_transform: Transform3D,
		settle_to_ground := false
	) -> void:
	_spawn_crawler_pickup_local(pickup_id, payload, at_transform, settle_to_ground)


func _spawn_crawler_pickup_local(
		pickup_id: int,
		payload: Dictionary,
		at_transform: Transform3D,
		settle_to_ground := false
	) -> void:
	if pickup_id <= 0 or payload.is_empty():
		return
	var existing := _pickup_nodes.get(pickup_id) as Node
	if is_instance_valid(existing):
		return
	_pickups[pickup_id] = {
		"kind": "crawler",
		"payload": payload,
		"transform": at_transform,
		"claimed": false,
	}
	var dropped := DroppedCrawlerCard.new()
	dropped.configure(pickup_id, payload)
	add_child(dropped, true)
	dropped.global_transform = at_transform
	dropped.reset_physics_interpolation()
	if settle_to_ground:
		dropped.begin_settle()
	else:
		dropped.begin_hover()
	_pickup_nodes[pickup_id] = dropped


## Returns the spawned id for focused tests; public callers intentionally ignore
## it and learn the result through the reliable spawn/confirmation messages.
func _server_drop(
		peer_id: int,
		source: String,
		index: int,
		expected_item_id: String,
		generation: int
	) -> int:
	if not multiplayer.is_server() or not _is_physical_item(expected_item_id):
		return 0
	var player := _spawned_players.get(peer_id) as OnlinePlayer
	if not is_instance_valid(player) or not player.authoritative_inventory_ready() \
			or generation != player.inventory_generation() \
			or not _source_accepts_item(source, expected_item_id) \
			or player.physical_item_at(source, index) != expected_item_id:
		return 0

	# The finite item leaves canonical inventory before an id is allocated or a
	# world node exists. A failed claim therefore cannot create anything.
	if not player.authoritative_remove_item(source, index, expected_item_id):
		return 0
	var next_generation := player.advance_inventory_generation()
	var pickup_id := _next_pickup_id
	_next_pickup_id += 1
	var at_transform := _drop_transform(player)
	_pickups[pickup_id] = {
		"item_id": expected_item_id,
		"transform": at_transform,
		"claimed": false,
	}
	_spawn_pickup_local(pickup_id, expected_item_id, at_transform)
	if multiplayer.has_multiplayer_peer():
		_spawn_pickup.rpc(pickup_id, expected_item_id, at_transform)

	# The host already mutated its owning container above. A remote owner takes
	# the same normal container callback path on confirmation, preserving dress,
	# held-item replication and local persistence.
	if peer_id != multiplayer.get_unique_id():
		_confirm_drop.rpc_id(peer_id, pickup_id, source, index,
			expected_item_id, next_generation)
	return pickup_id


func _server_pickup(peer_id: int, pickup_id: int, generation: int) -> bool:
	if not multiplayer.is_server():
		return false
	var player := _spawned_players.get(peer_id) as OnlinePlayer
	var record: Dictionary = _pickups.get(pickup_id, {})
	if not is_instance_valid(player) or not player.authoritative_inventory_ready() \
			or generation != player.inventory_generation() or record.is_empty() \
			or bool(record.get("claimed", false)):
		return false
	var item_id := str(record.get("item_id", ""))
	var at_transform: Transform3D = record.get(
		"transform", Transform3D.IDENTITY)
	if not _is_physical_item(item_id) \
			or player.global_position.distance_to(
				_pickup_world_origin(pickup_id, at_transform.origin)) \
				> PICKUP_MAX_DISTANCE \
			or player.backpack_slot_for(item_id) < 0:
		return false

	# Claim first. A second request arriving anywhere below this line sees the
	# flag (or, after despawn, no record) and cannot grant the same finite item.
	record["claimed"] = true
	_pickups[pickup_id] = record
	var backpack_index := player.authoritative_grant_backpack(item_id)
	if backpack_index < 0:
		record["claimed"] = false
		_pickups[pickup_id] = record
		return false
	var next_generation := player.advance_inventory_generation()
	if peer_id != multiplayer.get_unique_id():
		_grant_pickup.rpc_id(peer_id, pickup_id, item_id,
			backpack_index, next_generation)
	_despawn_pickup_local(pickup_id)
	if multiplayer.has_multiplayer_peer():
		_despawn_pickup.rpc(pickup_id)
	return true


@rpc("authority", "call_remote", "reliable")
func _confirm_drop(
		pickup_id: int,
		source: String,
		index: int,
		item_id: String,
		generation: int
	) -> void:
	var player := local_player()
	if is_instance_valid(player):
		player.confirm_authoritative_drop(
			pickup_id, source, index, item_id, generation)


@rpc("authority", "call_remote", "reliable")
func _grant_pickup(
		pickup_id: int,
		item_id: String,
		backpack_index: int,
		generation: int
	) -> void:
	var player := local_player()
	if is_instance_valid(player):
		player.grant_authoritative_pickup(
			pickup_id, item_id, backpack_index, generation)


@rpc("authority", "call_remote", "reliable")
func _spawn_pickup(
		pickup_id: int,
		item_id: String,
		at_transform: Transform3D
	) -> void:
	_spawn_pickup_local(pickup_id, item_id, at_transform)


func _spawn_pickup_local(
		pickup_id: int,
		item_id: String,
		at_transform: Transform3D
	) -> void:
	if pickup_id <= 0 or not _is_physical_item(item_id):
		return
	var existing := _pickup_nodes.get(pickup_id) as DroppedItem
	if is_instance_valid(existing):
		return
	_pickups[pickup_id] = {
		"item_id": item_id,
		"transform": at_transform,
		"claimed": false,
	}
	var dropped := DroppedItem.new()
	dropped.configure(pickup_id, item_id)
	add_child(dropped, true)
	dropped.global_transform = at_transform
	dropped.reset_physics_interpolation()
	_pickup_nodes[pickup_id] = dropped


@rpc("authority", "call_remote", "reliable")
func _despawn_pickup(pickup_id: int) -> void:
	_despawn_pickup_local(pickup_id)


func _despawn_pickup_local(pickup_id: int) -> void:
	_pickups.erase(pickup_id)
	var dropped := _pickup_nodes.get(pickup_id) as Node
	_pickup_nodes.erase(pickup_id)
	if is_instance_valid(dropped):
		dropped.queue_free()


func _is_physical_item(item_id: String) -> bool:
	return not item_id.is_empty() and ItemDB.has_item(item_id) \
		and not ItemDB.is_ability(item_id)


func _source_accepts_item(source: String, item_id: String) -> bool:
	match source:
		"equipment":
			return ItemDB.is_apparel(item_id)
		"hotbar":
			return ItemDB.accepts_hotbar(item_id)
		"backpack":
			return ItemDB.accepts_backpack(item_id)
	return false


## Spawns a crawler card in front of the player's look. The tile then falls
## to the ground under [DroppedWorldMotion]; this pose is only the toss.
func _crawler_drop_transform(player: OnlinePlayer) -> Transform3D:
	var up := player.world_up()
	if up.length_squared() < 0.5:
		up = player.global_basis.y
	if up.length_squared() < 0.5:
		up = Vector3.UP
	up = up.normalized()
	var look := Vector3.ZERO
	if player.camera != null:
		look = player.look_direction()
	if look.length_squared() < 0.0001:
		look = -player.global_basis.z
	look = look.normalized()
	if absf(look.dot(up)) > 0.92:
		var along := -player.global_basis.z
		along -= up * along.dot(up)
		if along.length_squared() < 0.0001:
			along = player.global_basis.x
		look = look.lerp(along.normalized(), 0.35).normalized()
	return Transform3D(
		_upright_basis(-look, up),
		player.combat_position() + look * CRAWLER_DROP_FORWARD
	)


## Stands the pickup on the finest terrain query, one player-width ahead along
## the globe. Basis +Y follows the sampled terrain normal and -Z keeps facing in
## the player's projected forward direction.
func _drop_transform(player: OnlinePlayer) -> Transform3D:
	var up := player.global_basis.y.normalized()
	if up.length_squared() < 0.5:
		up = Vector3.UP
	var forward := -player.global_basis.z
	forward -= up * forward.dot(up)
	if forward.length_squared() < 0.0001:
		forward = player.global_basis.x
	forward = forward.normalized()

	var planet := get_node_or_null("Planet") as Planet
	if planet == null or planet.shape == null:
		return Transform3D(_upright_basis(forward, up),
			player.global_position + forward * DROP_FORWARD_DISTANCE
				+ up * DROP_SURFACE_CLEARANCE)

	var player_local := planet.to_local(player.global_position)
	if player_local.length_squared() < 1.0:
		return Transform3D(_upright_basis(forward, up),
			player.global_position + forward * DROP_FORWARD_DISTANCE
				+ up * DROP_SURFACE_CLEARANCE)
	var radial := player_local.normalized()
	var forward_local := planet.global_basis.inverse() * forward
	forward_local -= radial * forward_local.dot(radial)
	if forward_local.length_squared() < 0.0001:
		var hint := Vector3.FORWARD if absf(radial.z) < 0.9 else Vector3.RIGHT
		forward_local = (hint - radial * hint.dot(radial)).normalized()
	else:
		forward_local = forward_local.normalized()
	var angle := DROP_FORWARD_DISTANCE / maxf(planet.shape.radius, 1.0)
	var direction := (
		radial * cos(angle) + forward_local * sin(angle)).normalized()
	var spacing := planet.finest_spacing()
	var normal := planet.shape.normal_at(direction, spacing).normalized()
	var surface := planet.shape.surface_point(direction, spacing)
	var facing := forward_local - normal * forward_local.dot(normal)
	if facing.length_squared() < 0.0001:
		facing = direction.cross(normal)
	return planet.global_transform * Transform3D(
		_upright_basis(facing.normalized(), normal),
		surface + normal * DROP_SURFACE_CLEARANCE)


func _upright_basis(forward: Vector3, up: Vector3) -> Basis:
	up = up.normalized()
	forward -= up * forward.dot(up)
	if forward.length_squared() < 0.0001:
		var hint := Vector3.FORWARD if absf(up.z) < 0.9 else Vector3.RIGHT
		forward = hint - up * hint.dot(up)
	forward = forward.normalized()
	var right := forward.cross(up).normalized()
	return Basis(right, up, right.cross(up).normalized()).orthonormalized()


func _on_player_registered(peer_id: int, metadata: Dictionary) -> void:
	if not multiplayer.is_server() \
			or NetworkManager.state != NetworkManager.SessionState.IN_GAME:
		return
	_spawn_player.rpc(
		peer_id,
		metadata,
		_spawn_transform(peer_id),
		not CrawlerRules.active()
	)


## [param in_flight] is for the spawn markers, which hang in orbit with nothing
## under them. A player rebuilt from a late joiner's snapshot is placed wherever
## they already were, and their real stance arrives on the next sync packet.
@rpc("authority", "call_local", "reliable")
func _spawn_player(peer_id: int, metadata: Dictionary, at_transform: Transform3D, in_flight: bool) -> void:
	if _spawned_players.has(peer_id):
		return
	var started := Time.get_ticks_msec()
	var player := PLAYER_SCENE.instantiate() as OnlinePlayer
	player.name = str(peer_id)
	player.peer_id = peer_id
	player.display_name = str(metadata.get("name", "Player"))
	# The home screen still owns the viewport and the mouse; it hands both to the
	# body at the end of its sweep rather than losing them the moment it spawns.
	# Keep that body hidden too: it occupies the preview's exact transform, and
	# rendering both for even one handover frame makes their surfaces z-fight in
	# black patches that look like the old character-shadow flicker.
	player.defer_camera = is_instance_valid(_home_screen) \
		and peer_id == multiplayer.get_unique_id()
	if player.defer_camera:
		player.visible = false
		player.controls_enabled = false
	add_child(player, true)
	# Look arrives with the roster metadata so every peer builds the same body
	# before the first sync packet. The home screen can override the local peer
	# with the preview that was just on screen.
	var look := {
		"body": metadata.get("body", CharacterDB.DEFAULT_BODY),
		"skin": metadata.get("skin", ""),
		"worn": metadata.get("worn", {}),
		"tints": metadata.get("tints", {}),
	}
	if _has_look_override and peer_id == multiplayer.get_unique_id():
		look = _look_override.duplicate(true)
		_has_look_override = false
	player.apply_look(look)
	if CrawlerRules.active() and player.has_method(&"refresh_crawler_look") \
			and peer_id == multiplayer.get_unique_id() \
			and player.crawler_progress != null:
		player.crawler_progress.seed_look_hat(look)
		player.crawler_progress.seed_look_cape(look)
		player.call(&"refresh_crawler_look")
	if CrawlerRules.active() and player.has_method(&"arm_spawn_arrival"):
		player.call(&"arm_spawn_arrival")
	player.global_transform = at_transform
	# This is a spawn/teleport, not movement between two physics ticks. Without
	# resetting, interpolation draws one frame between the scene origin and the
	# orbital or home-screen handover position.
	player.reset_physics_interpolation()
	player.reset_network_state(at_transform)
	if in_flight:
		player.start_flying()
	_spawned_players[peer_id] = player
	if CrawlerRules.active() and player.has_method(&"play_spawn_arrival"):
		player.call(&"play_spawn_arrival")
	LagTracker.note("spawn", "player %d '%s' in %d ms" % [
		peer_id, player.display_name, Time.get_ticks_msec() - started])


@rpc("authority", "call_local", "reliable")
func _despawn_player(peer_id: int) -> void:
	var player := _spawned_players.get(peer_id) as OnlinePlayer
	_spawned_players.erase(peer_id)
	_respawn_sequence.erase(peer_id)
	if is_instance_valid(player):
		LagTracker.note("spawn", "despawn player %d" % peer_id)
		player.queue_free()


@rpc("any_peer", "reliable")
func _request_world_state() -> void:
	if not multiplayer.is_server():
		return
	var sender := multiplayer.get_remote_sender_id()
	if NetworkManager.state != NetworkManager.SessionState.IN_GAME \
			or not NetworkManager.is_peer_registered(sender):
		return
	var snapshots: Array = []
	for peer_id in NetworkManager.players:
		var id := int(peer_id)
		var player := _spawned_players.get(id) as OnlinePlayer
		var player_transform := player.global_transform if is_instance_valid(player) else _spawn_transform(id)
		var meta: Dictionary = NetworkManager.get_player_metadata(id)
		snapshots.append({
			"peer_id": id,
			"metadata": meta,
			"transform": player_transform,
			# Clothes and weapons are broadcast when they change, so a peer joining
			# later has to be told what everyone already has on and in hand.
			"worn": player.worn_items() if is_instance_valid(player) else PackedStringArray(),
			"held": player.held_item() if is_instance_valid(player) else "",
			"body": player.body_id() if is_instance_valid(player) else str(meta.get("body", CharacterDB.DEFAULT_BODY)),
			"combat": player.combat_snapshot() if is_instance_valid(player) else {},
		})
	# A joining peer loaded this scene later than the host. Send the host's sky
	# phase with the same snapshot so both see the same day rather than each
	# beginning their own sixteen-minute clock at noon. The ground they arrive on
	# has to match too: the craters cut before they joined and the plants already
	# cleared away are as much world state as the sky is.
	_receive_world_state.rpc_id(
		sender, snapshots, celestial_cycle.phase(), pickup_snapshots(),
		scar_snapshot(), flora_snapshot(), bigfoot_snapshot(),
		celestial_cycle.day_index(), ability_construct_snapshot())


@rpc("authority", "reliable")
func _receive_world_state(
		snapshots: Array,
		day_phase := -1.0,
		pickup_state: Array = [],
		scar_state: Array = [],
		flora_state: Dictionary = {},
		boss_state: Dictionary = {},
		day_number := 0,
		ability_construct_state: Array = []
	) -> void:
	if float(day_phase) >= 0.0:
		celestial_cycle.set_phase(float(day_phase))
	celestial_cycle.set_day_index(int(day_number))
	apply_scar_snapshot(scar_state)
	apply_flora_snapshot(flora_state)
	apply_bigfoot_snapshot(boss_state)
	apply_ability_construct_snapshot(ability_construct_state)
	for snapshot_variant in snapshots:
		if not snapshot_variant is Dictionary:
			continue
		var snapshot: Dictionary = snapshot_variant
		var peer_id := int(snapshot.get("peer_id", 0))
		var meta: Dictionary = snapshot.get("metadata", {})
		if snapshot.has("body"):
			meta = meta.duplicate(true)
			meta["body"] = snapshot.get("body")
		_spawn_player(
			peer_id,
			meta,
			snapshot.get("transform", Transform3D.IDENTITY),
			false
		)
		var player := _spawned_players.get(peer_id) as OnlinePlayer
		if is_instance_valid(player):
			player.apply_worn(snapshot.get("worn", PackedStringArray()))
			player.apply_held(String(snapshot.get("held", "")))
			var combat_state: Variant = snapshot.get("combat", null)
			if combat_state is Dictionary:
				player.apply_combat_snapshot(combat_state)
	for pickup_variant in pickup_state:
		if not pickup_variant is Dictionary:
			continue
		var pickup: Dictionary = pickup_variant
		var pickup_id := int(pickup.get("pickup_id", 0))
		if str(pickup.get("kind", "")) == "crawler" or pickup.has("payload"):
			_spawn_crawler_pickup_local(
				pickup_id,
				pickup.get("payload", {}),
				pickup.get("transform", Transform3D.IDENTITY))
			continue
		if str(pickup.get("kind", "")) == "crawler_hat":
			_spawn_crawler_hat_pickup_local(
				pickup_id,
				str(pickup.get("item_id", "")),
				pickup.get("transform", Transform3D.IDENTITY))
			continue
		_spawn_pickup_local(
			pickup_id,
			str(pickup.get("item_id", "")),
			pickup.get("transform", Transform3D.IDENTITY))


func _spawn_transform(peer_id: int) -> Transform3D:
	if _peer_spawns.has(peer_id):
		return _peer_spawns[peer_id]
	if _has_spawn_override and _force_spawn_override \
			and peer_id == multiplayer.get_unique_id():
		return _spawn_override
	if CrawlerRules.active():
		var crawler := _crawler_pad_transform(peer_id)
		if crawler.origin.length_squared() > 1.0:
			return crawler
	if _has_spawn_override and peer_id == multiplayer.get_unique_id():
		return _spawn_override
	var points := spawn_points.get_children()
	if points.is_empty():
		return Transform3D(Basis.IDENTITY, Vector3(0.0, 2.0, 0.0))
	var index := posmod(peer_id - 1, points.size())
	return (points[index] as Node3D).global_transform


func bigfoot_snapshot() -> Dictionary:
	for boss_variant: Variant in get_tree().get_nodes_in_group(&"bigfoot_boss"):
		var boss := boss_variant as Node
		if boss != null and DamageHit.in_same_world(self, boss) \
				and boss.has_method(&"boss_snapshot"):
			return boss.call(&"boss_snapshot") as Dictionary
	return {}


func apply_bigfoot_snapshot(wire: Dictionary) -> void:
	if wire.is_empty():
		return
	for boss_variant: Variant in get_tree().get_nodes_in_group(&"bigfoot_boss"):
		var boss := boss_variant as Node
		if boss != null and DamageHit.in_same_world(self, boss) \
				and boss.has_method(&"apply_boss_snapshot"):
			boss.call(&"apply_boss_snapshot", wire)
			return
