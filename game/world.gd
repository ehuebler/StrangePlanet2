class_name GameWorld
extends Node3D

## The world is also the home screen. It is loaded once, empty, and the menu is a
## camera and an overlay put over it (see ui/menu/home_screen.gd); players are
## spawned only once a session exists. Nothing between the title and playing is a
## scene change, which is what keeps the planet's quadtree built across it.

const PLAYER_SCENE := preload("res://game/player/player.tscn")

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
## Shoulder-to-shoulder separation at the orbital start used by an online
## sandbox. Wide enough that two flight capsules cannot begin intersecting, but
## close enough that the party enters the world as one visible group.
const ONLINE_SANDBOX_SPAWN_SPACING := 4.0

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
## Stable host-assigned formation slot per online sandbox player. Peer ids from
## Steam and ENet are identities, not roster indices; modulo-ing one by the
## number of authored markers can put two different peers on the same marker.
var _sandbox_spawn_slots: Dictionary = {}
var _crawler_city_queue: Array = []
var _crawler_city_gift_id := 0
var _crawler_city_gift_claimed := false


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
	_sandbox_spawn_slots.clear()


func local_player() -> OnlinePlayer:
	return _spawned_players.get(multiplayer.get_unique_id()) as OnlinePlayer


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
		initial_alpha := 0.52) -> AbilityBarrier:
	if construct_id <= 0:
		return null
	var existing := _ability_constructs.get(construct_id) as AbilityBarrier
	if is_instance_valid(existing):
		return existing
	var barrier := AbilityBarrier.create(
		self, construct_id, owner_peer, at, size,
		duration, fade_duration, tint, initial_alpha)
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
		})
	return snapshot


func apply_ability_construct_snapshot(snapshot: Array) -> void:
	for entry_variant: Variant in snapshot:
		if not entry_variant is Dictionary:
			continue
		var entry := entry_variant as Dictionary
		spawn_ability_barrier_local(
			int(entry.get("construct_id", 0)),
			int(entry.get("owner_peer", 0)),
			entry.get("transform", Transform3D.IDENTITY),
			entry.get("size", Vector3(8.0, 4.0, 0.35)),
			float(entry.get("remaining", 0.0)),
			float(entry.get("fade_duration", 0.0)),
			entry.get("tint", Color(0.27, 0.69, 1.0)),
			float(entry.get("alpha", 0.52)))


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
	if wire.is_empty():
		return
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
		_apply_flora_breaks(path, state[path])


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
		if progress == null or not progress.spend_respawn_ticket():
			return
	respawn_player_at_colony(sender)


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
	var seated := overlay.crawler_spawn_transform(1.35)
	if seated.origin.length_squared() > 1.0:
		return seated
	var patch_id := overlay.patch_id_named(CrawlerRules.START_PATCH)
	if patch_id < 0 and not overlay.partition.patches.is_empty():
		patch_id = overlay.partition.patches[0].id
	return overlay.high_surface_transform_for_patch(patch_id, 1.35)


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
	var at := overlay.crawler_spawn_transform(0.0)
	if at.origin.length_squared() < 1.0:
		var patch_id := overlay.patch_id_named(CrawlerRules.START_PATCH)
		if patch_id < 0 and not overlay.partition.patches.is_empty():
			patch_id = overlay.partition.patches[0].id
		at = overlay.high_surface_transform_for_patch(patch_id, 0.0)
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
	var at := _crawler_start_transform()
	if at.origin.length_squared() < 1.0:
		return
	_sync_crawler_twilight()
	for player_variant: Variant in _spawned_players.values():
		var player := player_variant as OnlinePlayer
		if not is_instance_valid(player):
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
		snapshots.append({
			"pickup_id": pickup_id,
			"item_id": str(record.get("item_id", "")),
			"transform": record.get("transform", Transform3D.IDENTITY),
		})
	return snapshots


## Where the local player will be put when a session opens, overriding the spawn
## markers. The home screen uses it to start the player exactly where the
## character it has been showing was standing.
func override_local_spawn(at_transform: Transform3D) -> void:
	_spawn_override = at_transform
	_has_spawn_override = true


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
		_server_crawler_pickup(local_id, pickup_id, player.inventory_generation())
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
	_server_crawler_pickup(sender, pickup_id, generation)


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
	_spawn_crawler_pickup_local(pickup_id, payload, at_transform)
	if multiplayer.has_multiplayer_peer():
		_spawn_crawler_pickup.rpc(pickup_id, payload, at_transform)
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
			or player.global_position.distance_to(at_transform.origin) \
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
	_spawn_crawler_pickup_local(pickup_id, payload, at_transform)
	if multiplayer.has_multiplayer_peer():
		_spawn_crawler_pickup.rpc(pickup_id, payload, at_transform)
	return pickup_id


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
		at_transform: Transform3D
	) -> void:
	_spawn_crawler_pickup_local(pickup_id, payload, at_transform)


func _spawn_crawler_pickup_local(
		pickup_id: int,
		payload: Dictionary,
		at_transform: Transform3D
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
			or player.global_position.distance_to(at_transform.origin) \
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


## Floats a crawler card in front of the player's look, at their current height.
## Flight keeps that pose in the air; the tile is never snapped to the terrain.
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
	if CrawlerRules.active():
		look["worn"] = {}
	player.apply_look(look)
	if CrawlerRules.active() and player.has_method(&"refresh_crawler_look"):
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
	_sandbox_spawn_slots.erase(peer_id)
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
		_spawn_pickup_local(
			pickup_id,
			str(pickup.get("item_id", "")),
			pickup.get("transform", Transform3D.IDENTITY))


func _spawn_transform(peer_id: int) -> Transform3D:
	if CrawlerRules.active():
		var crawler := _crawler_start_transform()
		if crawler.origin.length_squared() > 1.0:
			return crawler
	if _is_online_sandbox():
		return _online_sandbox_spawn_transform(peer_id)
	if _has_spawn_override and peer_id == multiplayer.get_unique_id():
		return _spawn_override
	var points := spawn_points.get_children()
	if points.is_empty():
		return Transform3D(Basis.IDENTITY, Vector3(0.0, 2.0, 0.0))
	var index := posmod(peer_id - 1, points.size())
	return (points[index] as Node3D).global_transform


func _is_online_sandbox() -> bool:
	return NetworkManager.state == NetworkManager.SessionState.IN_GAME \
		and not NetworkManager.is_single_player \
		and str(NetworkManager.session_options.get("mode", "")) == "sandbox"


## A compact line across the first orbital marker's view plane. Slots alternate
## right and left of the host (0, +1, -1, +2, -2...) so adding somebody never
## moves a player who has already spawned.
func _online_sandbox_spawn_transform(peer_id: int) -> Transform3D:
	var anchor := _sandbox_spawn_anchor()
	var centre_node := get_node_or_null("Planet") as Node3D
	var centre := centre_node.global_position if centre_node != null \
		else anchor.origin - anchor.basis.z
	var anchor_basis := _planet_facing_basis(
		anchor.origin, centre, anchor.basis.y, -anchor.basis.z)
	var slot := _sandbox_spawn_slot(peer_id)
	var lane := ceili(float(slot) * 0.5)
	var side := 1.0 if slot % 2 == 1 else -1.0
	var origin := anchor.origin + anchor_basis.x \
		* (float(lane) * side * ONLINE_SANDBOX_SPAWN_SPACING)
	var basis := _planet_facing_basis(
		origin, centre, anchor_basis.y, -anchor_basis.z)
	return Transform3D(basis, origin)


func _sandbox_spawn_anchor() -> Transform3D:
	if _has_spawn_override:
		return _spawn_override
	var points := spawn_points.get_children()
	if not points.is_empty() and points[0] is Node3D:
		return (points[0] as Node3D).global_transform
	return Transform3D(Basis.IDENTITY, Vector3(0.0, 2.0, 0.0))


func _sandbox_spawn_slot(peer_id: int) -> int:
	if _sandbox_spawn_slots.has(peer_id):
		return int(_sandbox_spawn_slots[peer_id])
	var slot := 0
	var occupied := _sandbox_spawn_slots.values()
	while occupied.has(slot):
		slot += 1
	_sandbox_spawn_slots[peer_id] = slot
	return slot


## Keeps the body's -Z aimed at the planet while retaining a stable visual up
## across the formation. The fallbacks also keep a stripped test world useful
## when its anchor happens to sit at the nominal centre.
func _planet_facing_basis(origin: Vector3, centre: Vector3, up_hint: Vector3,
		forward_fallback: Vector3) -> Basis:
	var forward := centre - origin
	if forward.length_squared() < 0.0001:
		forward = forward_fallback
	if forward.length_squared() < 0.0001:
		forward = Vector3.FORWARD
	forward = forward.normalized()
	up_hint -= forward * up_hint.dot(forward)
	if up_hint.length_squared() < 0.0001:
		var hint := Vector3.UP if absf(forward.y) < 0.9 else Vector3.RIGHT
		up_hint = hint - forward * hint.dot(forward)
	return _upright_basis(forward, up_hint.normalized())


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
