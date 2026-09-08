extends Node

## Real ENet verification that two peers end up with the same battered ground.
##
##     godot --headless --path . dev/_ability_net_test.tscn
##
## Host, client and late joiner run as separate MultiplayerAPI branches in one
## process, the same arrangement [code]_multiplayer_pickup_test.gd[/code] uses.
## Everything below crosses a socket: nothing calls the receiving side directly,
## because the claim being made is about the wire and about who is allowed to
## change the world, and a direct call proves neither.
##
## The flora here is a stub rather than a biome. What a real [GroundCover] does
## with a hit is already settled in [code]_flora_damage_test.gd[/code]; what is
## unsettled is whether the volume and the confirmed break keys survive the trip,
## and a field with nothing growing in it answers that without standing three
## planets' worth of vegetation up in one process.

const PLAYER: PackedScene = preload("res://game/player/player.tscn")
const TEST_CYCLE := preload("res://dev/_multiplayer_test_cycle.gd")
const SETTINGS_PATH := "user://settings.cfg"
const CONNECT_FRAMES := 360
const RPC_FRAMES := 240

## Somewhere on the sphere to cut, and something to cut with. Nothing depends on
## the numbers beyond their being distinctive enough to recognise on the far end.
const SCAR_RADIUS := 5.0
const SCAR_DEPTH := 2.25

## Plants the host decides are gone. Any three numbers: a break key is opaque to
## everything between the field that made it and the field that receives it.
static var BREAK_KEYS := PackedInt32Array([17, 41, 99])

var _failures := 0
var _port := 0

var _server_branch: Node
var _owner_branch: Node
var _late_branch: Node
var _server_api: SceneMultiplayer
var _owner_api: SceneMultiplayer
var _late_api: SceneMultiplayer
var _server_peer: ENetMultiplayerPeer
var _owner_peer: ENetMultiplayerPeer
var _late_peer: ENetMultiplayerPeer

var _server_world: GameWorld
var _owner_world: GameWorld
var _late_world: GameWorld
var _owner_player: OnlinePlayer
var _owner_id := 0
## The volume the client sent, as the far end should find it.
var _expected_hit: DamageHit
var _server_enemy: TestEnemy
var _server_boss: BigfootBoss
var _owner_boss: BigfootBoss
var _late_boss: BigfootBoss
var _expected_boss_health := 0.0

var _saved_players: Dictionary
var _saved_state: int
var _saved_single_player := false
var _saved_host := false
var _settings_existed := false
var _settings_bytes := PackedByteArray()


## A damageable field with nothing growing in it: a ledger of what it was asked
## to absorb, and of what it has been told is gone.
class TestCover extends Node3D:
	var absorbed: Array[DamageHit] = []
	var broken := PackedInt32Array()
	var _fresh := PackedInt32Array()

	func _ready() -> void:
		process_mode = Node.PROCESS_MODE_ALWAYS
		add_to_group(DamageHit.FIELD_GROUP)

	func apply_damage(hit: DamageHit) -> float:
		absorbed.append(hit)
		return 0.0

	## Stands in for a plant that the damage finished off on this peer only.
	func break_here(keys: PackedInt32Array) -> void:
		for key in keys:
			if broken.find(key) < 0:
				broken.append(key)
			_fresh.append(key)

	func broken_keys() -> PackedInt32Array:
		return broken

	func drain_new_breaks() -> PackedInt32Array:
		var keys := _fresh
		_fresh = PackedInt32Array()
		return keys

	func apply_broken_keys(keys: PackedInt32Array) -> void:
		for key in keys:
			if broken.find(key) < 0:
				broken.append(key)

	## Whether a volume with these numbers was offered here.
	func saw(hit: DamageHit) -> bool:
		for seen in absorbed:
			if is_equal_approx(seen.amount, hit.amount) \
					and seen.origin.is_equal_approx(hit.origin) \
					and seen.toward.is_equal_approx(hit.toward) \
					and is_equal_approx(seen.radius, hit.radius) \
					and seen.kind == hit.kind \
					and is_equal_approx(seen.falloff, hit.falloff) \
					and seen.source_peer == hit.source_peer \
					and seen.ability_id == hit.ability_id:
				return true
		return false


class TestEnemy extends Node3D:
	var reflected := 0.0
	var reflected_by := 0

	func _ready() -> void:
		add_to_group(DamageHit.COMBATANT_GROUP)

	func combat_faction() -> int:
		return DamageHit.Faction.ENEMY

	func combat_position() -> Vector3:
		return global_position

	func combat_radius() -> float:
		return 0.5

	func apply_damage(hit: DamageHit) -> float:
		return hit.amount

	func receive_reflected_damage(amount: float, source_peer: int) -> void:
		reflected += amount
		reflected_by = source_peer


func _ready() -> void:
	process_mode = Node.PROCESS_MODE_ALWAYS
	_snapshot_settings()
	_saved_players = NetworkManager.players.duplicate(true)
	_saved_state = int(NetworkManager.state)
	_saved_single_player = NetworkManager.is_single_player
	_saved_host = NetworkManager.is_host
	for item_id: String in ItemDB.ITEMS:
		ItemIcons._cache[item_id] = ImageTexture.new()
	NetworkManager.players.clear()
	NetworkManager.state = NetworkManager.SessionState.IN_GAME
	NetworkManager.is_single_player = false
	NetworkManager.is_host = true

	if not await _start_peers():
		await _finish()
		return
	await _build_worlds()
	if _owner_player == null:
		_expect(false, "the client has a player of its own")
		await _finish()
		return

	await _check_request_rejections()
	await _check_scars()
	await _check_damage_volume()
	await _check_combat_authority()
	await _check_boss_replication()
	await _check_new_ability_networking()
	await _check_impact_cloud()
	await _check_break_confirmation()
	await _check_late_join()
	await _finish()


## Requests that fail host validation get an explicit answer instead of making
## the owner spend a cooldown while waiting.
func _check_request_rejections() -> void:
	var server_player := _server_world._spawned_players.get(
		_owner_id) as OnlinePlayer
	if not _expect(server_player != null,
			"the host has a player copy for ability request validation"):
		return

	server_player._dead = true
	var projectile_request := _owner_player.fire_ability_projectile(
		"starfire", _owner_player.combat_position(), Vector3.FORWARD, 0)
	_expect(projectile_request > 0
		and _owner_player.ability_projectile_request_state(projectile_request)
			== OnlinePlayer.ProjectileRequestState.PENDING,
		"a client waits for host approval before committing Starfire")
	var projectile_rejected := await _wait_until(
		_owner_projectile_rejected.bind(projectile_request), RPC_FRAMES)
	server_player._dead = false
	_expect(projectile_rejected,
		"host rejection returns to the Starfire owner")

	var inherited := Vector3(12.0, 3.0, -4.0)
	_owner_player.velocity = inherited
	server_player.velocity = inherited
	var approved_request := _owner_player.fire_ability_projectile(
		"starfire", _owner_player.combat_position(), Vector3.FORWARD, 0)
	var projectile_approved := await _wait_until(
		_owner_projectile_accepted.bind(approved_request), RPC_FRAMES)
	var copies_spawned := await _wait_until(
		_projectile_copies_spawned, RPC_FRAMES)
	var owner_projectile := _projectile_under(_owner_world)
	var server_projectile := _projectile_under(_server_world)
	_expect(projectile_approved and copies_spawned
		and owner_projectile._velocity.is_equal_approx(
			server_projectile._velocity)
		and owner_projectile._velocity.is_equal_approx(
			owner_projectile._along * owner_projectile._speed + inherited),
		"Starfire inherited velocity replicates unchanged to every peer")
	_owner_player.velocity = Vector3.ZERO
	for projectile: AbilityProjectile in [owner_projectile, server_projectile]:
		if is_instance_valid(projectile):
			projectile.queue_free()


## A crater asked for by a client is the host's to grant, and once granted it is
## in the same place on both peers' ground.
func _check_scars() -> void:
	var here := Vector3(0.3, 0.9, 0.2).normalized()
	_owner_world.request_scar(_scar(here))
	_expect(_scars(_owner_world).count() == 0,
		"a client does not cut its own ground while it waits")
	var granted := await _wait_until(_client_has_one_scar, RPC_FRAMES)
	_expect(granted, "the host grants a client's crater and it comes back")
	if not granted:
		return
	_expect(_scars(_server_world).count() == 1,
		"and the host cut the same one into its own ground")
	_expect(is_equal_approx(_scars(_server_world).depth_at(here),
			_scars(_owner_world).depth_at(here))
		and _scars(_owner_world).depth_at(here) > SCAR_DEPTH * 0.5,
		"both peers' ground has dropped by the same amount")

	# The other direction, which is the one the host itself punches through.
	var there := Vector3(-0.4, 0.8, 0.45).normalized()
	_server_world.request_scar(_scar(there))
	var shared := await _wait_until(_client_has_two_scars, RPC_FRAMES)
	_expect(shared, "a crater the host makes reaches the client too")


## The damage itself replicates as the volume rather than as its consequences,
## so what has to survive the trip is every number that decides who is inside it.
func _check_damage_volume() -> void:
	var hit := DamageHit.beam(
		Vector3(4.0, 1.5, 0.0), Vector3(9.0, 1.5, 2.0), 0.35, 18.0)
	hit.ability_id = "laser_eyes"
	_expected_hit = DamageHit.from_wire(hit.to_wire())
	_expected_hit.source_peer = _owner_id
	_owner_player.deal_damage(hit)
	var arrived := await _wait_until(_host_saw_the_volume, RPC_FRAMES)
	_expect(arrived, "a client's damage volume reaches the host unchanged")
	_expect(_cover(_owner_world).saw(_expected_hit),
		"and the client applied the same volume to its own flora")


func _check_combat_authority() -> void:
	var server_player := _server_world._spawned_players.get(
		_owner_id) as OnlinePlayer
	if not _expect(server_player != null,
			"the host has a combat copy of the client player"):
		return

	# Enemy-authored fields on a hero packet never survive the host boundary.
	var before_packets := _cover(_server_world).absorbed.size()
	var forged := DamageHit.impact(Vector3(7.0, 1.0, 0.0), 1.0, 3.0)
	forged.reaction = DamageHit.Reaction.RAGDOLL
	forged.world_impulse = Vector3(100.0, 0.0, 0.0)
	forged.radial_impulse = 100.0
	forged.radial_lift = 40.0
	forged.blocked_by_world = true
	forged.status = CombatStatuses.FLIGHTLESS
	forged.status_duration = 30.0
	forged.parryable = true
	forged.reflection = 40.0
	_owner_player.deal_damage(forged)
	var sanitized := await _wait_until(
		_server_received_packet_after.bind(before_packets),
		RPC_FRAMES)
	_expect(sanitized, "a forged hero packet reaches host sanitization")
	if sanitized:
		var seen := _cover(_server_world).absorbed.back() as DamageHit
		_expect(seen.faction == DamageHit.Faction.PLAYER
			and seen.reaction == DamageHit.Reaction.NONE
			and seen.world_impulse == Vector3.ZERO
			and is_zero_approx(seen.radial_impulse)
			and is_zero_approx(seen.radial_lift)
			and not seen.blocked_by_world
			and seen.status.is_empty() and not seen.parryable
			and is_zero_approx(seen.reflection),
			"host strips forged status, reaction, impulse and reflection")

	# Sending the same reliable request twice applies exactly once.
	var duplicate := DamageHit.impact(Vector3(8.0, 1.0, 0.0), 1.0, 2.0)
	var duplicate_wire := duplicate.to_wire()
	var request_sequence := _owner_player._combat_event_sequence + 1
	before_packets = _cover(_server_world).absorbed.size()
	_owner_player._request_hero_combat_hit.rpc_id(
		1, request_sequence, duplicate_wire)
	_owner_player._request_hero_combat_hit.rpc_id(
		1, request_sequence, duplicate_wire)
	# These requests deliberately bypass deal_damage, so keep the owner's next
	# real sequence beyond the packet we just authored by hand.
	_owner_player._combat_event_sequence = request_sequence
	var one_arrived := await _wait_until(
		_server_received_packet_after.bind(before_packets),
		RPC_FRAMES)
	await _network_frames(6)
	_expect(one_arrived
		and _cover(_server_world).absorbed.size() == before_packets + 1,
		"combat request sequence deduplicates retransmission")

	_server_enemy = TestEnemy.new()
	_server_enemy.name = "Enemy"
	_server_world.add_child(_server_enemy)
	_server_enemy.global_position = server_player.combat_position()
	_expect(_owner_player.request_parry(),
		"client sends a parry request")
	var parry_shared := await _wait_until(_parry_state_shared, RPC_FRAMES)
	_expect(parry_shared, "host validates and broadcasts the parry window")
	if not parry_shared:
		return

	var health_before := server_player.health()
	var roar := DamageHit.impact(server_player.combat_position(), 2.0, 0.0)
	roar.faction = DamageHit.Faction.ENEMY
	roar.target_peer = _owner_id
	roar.set_source(_server_enemy)
	roar.status = CombatStatuses.FLIGHTLESS
	roar.status_duration = 8.0
	roar.reaction = DamageHit.Reaction.RAGDOLL
	roar.parryable = true
	roar.reflection = 6.0
	DamageHit.apply_to_world(_server_enemy, roar)
	await _network_frames(6)
	_expect(is_equal_approx(server_player.health(), health_before)
		and is_equal_approx(_owner_player.health(), health_before)
		and not server_player.has_status(CombatStatuses.FLIGHTLESS)
		and not _owner_player.has_status(CombatStatuses.FLIGHTLESS),
		"host parry blocks Roar damage, status and reaction on both peers")
	_expect(is_equal_approx(_server_enemy.reflected, 6.0)
		and _server_enemy.reflected_by == _owner_id,
		"perfect network parry reflects through the source hook")

	server_player._tick_combat(0.4)
	_owner_player._tick_combat(0.4)
	var event_before := server_player._parry_event_sequence
	_owner_player.request_parry()
	await _network_frames(6)
	_expect(server_player._parry_event_sequence == event_before,
		"host rejects parry during authoritative cooldown")

	var hit := DamageHit.impact(server_player.combat_position(), 2.0, 10.0)
	hit.faction = DamageHit.Faction.ENEMY
	hit.target_peer = _owner_id
	hit.set_source(_server_enemy)
	hit.status = CombatStatuses.FLIGHTLESS
	hit.status_duration = 5.0
	DamageHit.apply_to_world(_server_enemy, hit)
	var state_shared := await _wait_until(
		_owner_combat_state_matches.bind(health_before - 10.0),
		RPC_FRAMES)
	_expect(state_shared,
		"host health and Flightless replicate to the owning client")

	var host_stance := server_player.stance()
	_owner_player._submit_state.rpc_id(
		1, _owner_player.global_transform, Vector3.ZERO, 0.0,
		OnlinePlayer.Stance.FLY)
	await _network_frames(6)
	_expect(server_player.stance() == host_stance
		and server_player.stance() != OnlinePlayer.Stance.FLY,
		"host rejects a Flightless client claiming FLY")


## Meteor is simulated only by its owner, so its broad cosmetic cloud has one
## small RPC of its own. Both ends must play it once.
func _check_impact_cloud() -> void:
	var server_player := _server_world._spawned_players.get(
		_owner_id) as OnlinePlayer
	if not _expect(server_player != null, "the host mirrors the client's player"):
		return
	var owner_before := _owner_player.dust.impact_count
	var server_before := server_player.dust.impact_count
	_owner_player.play_meteor_impact_dust(
		Vector3(8.0, 1.0, 2.0), Vector3.UP, 6.0, 1.0)
	_expect(_owner_player.dust.impact_count == owner_before + 1,
		"the Meteor owner plays its impact dust once")
	var arrived := await _wait_until(
		_server_dust_count_is.bind(server_before + 1),
		RPC_FRAMES)
	_expect(arrived, "Meteor impact dust reaches the other peer")


func _check_boss_replication() -> void:
	if not _expect(_server_boss != null and _owner_boss != null,
			"both live peers contain the deterministic Bigfoot node"):
		return
	_server_boss.set("_health", 731.0)
	_server_boss.set("_engaged", true)
	_server_boss.set("_clip", "Roar")
	_server_boss.set("_attack", &"roar")
	_server_boss.set("_attack_left", 1.1)
	_server_boss.set("_roar_elapsed", 0.7)
	_server_boss.set("_roar_radius", 51.0)
	_server_boss.set("_meteor_along", Vector3(0.2, 0.0, -0.98).normalized())
	_server_boss.set("_cooldowns", {&"meteor": 4.5, &"grab": 2.0})
	_expected_boss_health = 731.0
	_server_boss.call(&"_publish_sync", true)
	var state_arrived := await _wait_until(_owner_boss_synced, RPC_FRAMES)
	_expect(state_arrived,
		"reliable boss state reaches the client through the real ENet RPC path")
	if state_arrived:
		var owner_snapshot := _owner_boss.boss_snapshot()
		_expect(String(owner_snapshot.get("attack", "")) == "roar"
			and float((owner_snapshot.get("cooldowns", {}) as Dictionary).get(
				&"meteor", 0.0)) > 4.0,
			"boss attack phase and cooldowns survive replication")

	var hit := DamageHit.impact(
		_owner_boss.combat_position(), _owner_boss.combat_radius() + 0.5, 31.0)
	hit.ability_id = "laser_eyes"
	_owner_player.deal_damage(hit)
	_expected_boss_health = 700.0
	var host_damaged := await _wait_until(_host_boss_health_matches, RPC_FRAMES)
	_expect(host_damaged,
		"client-authored hero damage is applied to Bigfoot only by the host")
	if not host_damaged:
		return
	_server_boss.call(&"_publish_sync", true)
	_expect(await _wait_until(_owner_boss_synced, RPC_FRAMES),
		"authoritative Bigfoot health returns to the attacking client")


func _check_new_ability_networking() -> void:
	var server_player := _server_world._spawned_players.get(
		_owner_id) as OnlinePlayer
	if not _expect(server_player != null,
			"the host mirrors the caster for new ability validation"):
		return

	# The owner predicts only the flight visual. Contact authority belongs to the
	# server copy, including when the owner is the client.
	var nuke_request := _owner_player.fire_ability_projectile(
		"nuke", _owner_player.hand_point(false), Vector3.FORWARD, 0)
	var nuke_approved := await _wait_until(
		_owner_projectile_accepted.bind(nuke_request), RPC_FRAMES)
	var nuke_copies := await _wait_until(
		_projectile_copies_spawned_for.bind("nuke"), RPC_FRAMES)
	var owner_orb := _projectile_of(_owner_world, "nuke")
	var server_orb := _projectile_of(_server_world, "nuke")
	_expect(nuke_approved and nuke_copies and owner_orb != null \
		and server_orb != null and not owner_orb.authoritative \
		and server_orb.authoritative,
		"Nuke flight replicates while only the host copy owns impact")
	for projectile: AbilityProjectile in [owner_orb, server_orb]:
		if is_instance_valid(projectile):
			projectile.queue_free()

	# Keep Bigfoot outside the blast while checking the caster-only Nuke rule, and
	# well outside rather than just beyond the rim: a boss clipped by the edge of
	# this is still picking itself up when later checks want a standing target.
	# Taken from the authored radius so widening the blast does not quietly move
	# the boss back inside it.
	var clear_of_blast := Vector3.RIGHT * (
		float(ItemDB.stats_of("nuke").get("radius", 0.0)) * 2.0 + 40.0)
	_server_boss.global_position = clear_of_blast
	_owner_boss.global_position = clear_of_blast
	server_player._clear_ragdoll()
	_owner_player._clear_ragdoll()
	server_player.velocity = Vector3.ZERO
	_owner_player.velocity = Vector3.ZERO
	var health_before := server_player.health()
	var nuke_flora_before := _cover(_owner_world).absorbed.size()
	AbilityImpact.apply(
		server_player, ItemDB.ability_definition("nuke"),
		server_player.combat_position(), Vector3.UP,
		{"player_damage": 8.0})
	var self_launch_shared := await _wait_until(
		func() -> bool:
			return server_player._forced_ragdoll \
				and _owner_player._forced_ragdoll,
		RPC_FRAMES)
	_expect(self_launch_shared
		and server_player.health() < health_before
		and _owner_player.health() < health_before
		and server_player.velocity.length() > 1.0
		and _owner_player.velocity.length() > 1.0,
		"Nuke self-launch ragdolls its caster on both peers and deals self-damage")
	server_player.stats.set_health(server_player.maximum_health())
	_owner_player.stats.set_health(_owner_player.maximum_health())
	var flora_shared := await _wait_until(
		func() -> bool:
			return _cover(_owner_world).absorbed.size() > nuke_flora_before,
		RPC_FRAMES)
	var flora_hit := _cover(_owner_world).absorbed.back() as DamageHit \
		if flora_shared else null
	_expect(flora_hit != null and flora_hit.ability_id == "nuke"
		and is_equal_approx(flora_hit.radius,
			float(ItemDB.stats_of("nuke").get("radius", 0.0)))
		and not flora_hit.affects_combatants
		and is_zero_approx(flora_hit.falloff),
		"Nuke clears grass and trees across its full blast, not only its crater")
	var owner_cover_before := _cover(_owner_world).absorbed.size()
	var trusted := DamageHit.area(
		Vector3(30.0, 2.0, 0.0), 5.0, 3.0, 1.0)
	trusted.ability_id = "nuke"
	trusted.affects_combatants = false
	trusted.radial_impulse = 33.0
	trusted.radial_lift = 7.0
	trusted.blocked_by_world = true
	server_player.deal_authoritative_ability_damage(trusted)
	var trusted_shared := await _wait_until(
		func() -> bool:
			return _cover(_owner_world).absorbed.size() > owner_cover_before,
		RPC_FRAMES)
	var trusted_seen := _cover(_owner_world).absorbed.back() as DamageHit \
		if trusted_shared else null
	_expect(trusted_seen != null
		and is_equal_approx(trusted_seen.radial_impulse, 33.0)
		and is_equal_approx(trusted_seen.radial_lift, 7.0)
		and trusted_seen.blocked_by_world,
		"trusted host reactions and occlusion survive replication intact")
	server_player._clear_ragdoll()
	_owner_player._clear_ragdoll()
	server_player.velocity = Vector3.ZERO
	_owner_player.velocity = Vector3.ZERO

	# Move the boss clear before resolving the delayed blast.
	_server_boss.global_position = Vector3(100.0, 0.0, 0.0)
	_owner_boss.global_position = Vector3(100.0, 0.0, 0.0)
	var eyes := _owner_player.eye_points()
	var from: Vector3 = (eyes[0] + eyes[1]) * 0.5
	var first_request := _owner_player.fire_ability_delayed_blast(
		"nausicaa", from, _owner_player.aim_direction(from))
	var first_approved := await _wait_until(
		func() -> bool:
			return _owner_player.ability_delayed_blast_request_state(
				first_request) == OnlinePlayer.ProjectileRequestState.ACCEPTED,
		RPC_FRAMES)
	var first_shared := await _wait_until(
		func() -> bool:
			return _delayed_blasts_under(_owner_world).size() == 1 \
				and _delayed_blasts_under(_server_world).size() == 1,
		RPC_FRAMES)
	var second_request := _owner_player.fire_ability_delayed_blast(
		"nausicaa", from, _owner_player.aim_direction(from))
	var second_approved := await _wait_until(
		func() -> bool:
			return _owner_player.ability_delayed_blast_request_state(
				second_request) == OnlinePlayer.ProjectileRequestState.ACCEPTED,
		RPC_FRAMES)
	var trail_shared := await _wait_until(
		func() -> bool:
			return _delayed_blasts_under(_owner_world).size() == 2 \
				and _delayed_blasts_under(_server_world).size() == 2,
		RPC_FRAMES)
	var owner_warnings := _delayed_blasts_under(_owner_world)
	var server_warnings := _delayed_blasts_under(_server_world)
	var tip_span := 0.0
	if not owner_warnings.is_empty():
		tip_span = owner_warnings[0].from.distance_to(owner_warnings[0].at)
	_expect(first_approved and first_shared and second_approved and trail_shared
		and not owner_warnings[0].simulates
		and server_warnings[0].simulates
		and is_equal_approx(tip_span, CrawlerRules.NAUSICAA_RANGE)
		and _owner_player.laser_beams()._colour \
			== ItemDB.ability_definition("nausicaa").tint,
		"Nausicaä paints the beam tip in empty air and only the host detonates it")
	var owner_explosions := _explosion_count(_owner_world)
	var server_explosions := _explosion_count(_server_world)
	var first_ordered := false
	if trail_shared:
		for warning: AbilityDelayedBlast in owner_warnings + server_warnings:
			warning.set_process(false)
			warning._age = 0.0
		server_warnings[0]._process(1.01)
		owner_warnings[0]._process(1.01)
		first_ordered = server_warnings[0]._detonated \
			and not server_warnings[1]._detonated
	var first_detonation_shared := await _wait_until(
		func() -> bool:
			return _explosion_count(_owner_world) > owner_explosions \
				and _explosion_count(_server_world) > server_explosions,
		RPC_FRAMES)
	_expect(first_detonation_shared and first_ordered,
		"Nausicaä detonates the first painted trail segment first")
	var second_ordered := false
	if trail_shared:
		server_warnings[1]._process(1.01)
		owner_warnings[1]._process(1.01)
		second_ordered = server_warnings[1]._detonated
	var chain_shared := await _wait_until(
		func() -> bool:
			return _explosion_count(_owner_world) >= owner_explosions + 2 \
				and _explosion_count(_server_world) >= server_explosions + 2,
		RPC_FRAMES)
	_expect(chain_shared and second_ordered,
		"Nausicaä advances the host-published explosion along the trail")

	var wall_request := _owner_player.place_ability_wall("wall")
	var wall_approved := await _wait_until(
		func() -> bool:
			return _owner_player.ability_wall_request_state(wall_request) \
				== OnlinePlayer.ProjectileRequestState.ACCEPTED,
		RPC_FRAMES)
	var walls_shared := await _wait_until(
		func() -> bool:
			return _owner_world.active_ability_wall_count() == 1 \
				and _server_world.active_ability_wall_count() == 1,
		RPC_FRAMES)
	_expect(wall_approved and walls_shared,
		"temporary Wall collision spawns once on each live peer")

	# Give the client copy a deliberately longer local timer. It can disappear
	# promptly only if the host's authoritative expiry is broadcast by id.
	var expiry_id := _server_world.allocate_ability_construct_id()
	var expiry_at := Transform3D(Basis.IDENTITY, Vector3(40.0, 2.0, 0.0))
	_server_world.spawn_ability_barrier_local(
		expiry_id, 1, expiry_at, Vector3(2.0, 2.0, 0.2),
		0.2, 0.1, Color(0.27, 0.69, 1.0))
	_owner_world.spawn_ability_barrier_local(
		expiry_id, 1, expiry_at, Vector3(2.0, 2.0, 0.2),
		5.0, 1.0, Color(0.27, 0.69, 1.0))
	var expiry_shared := await _wait_until(
		func() -> bool:
			return _owner_world.active_ability_wall_count() == 2 \
				and _server_world.active_ability_wall_count() == 2,
		RPC_FRAMES)
	var expiry_removed := await _wait_until(
		func() -> bool:
			return _owner_world.active_ability_wall_count() == 1 \
				and _server_world.active_ability_wall_count() == 1,
		RPC_FRAMES)
	_expect(expiry_shared and expiry_removed,
		"Wall expiry is broadcast by its stable construct id")


## What actually broke is a correction, sent by the host a few times a second.
## Driven by hand here: every world in this process shares one scene tree and so
## one damage-field group, and a client left to its own timer would drain the
## host's pending breaks before the host had said them out loud.
func _check_break_confirmation() -> void:
	_cover(_server_world).break_here(BREAK_KEYS)
	_expect(_cover(_owner_world).broken_keys().is_empty(),
		"a break on the host has not reached the client by itself")
	_server_world.confirm_flora_breaks()
	var told := await _wait_until(_client_told_of_breaks, RPC_FRAMES)
	_expect(told, "the host's confirmed breaks reach the client")
	if not told:
		return
	_expect(_same_keys(_cover(_owner_world).broken_keys(), BREAK_KEYS),
		"and they are the same plants")
	_server_world.confirm_flora_breaks()
	await _network_frames(4)
	_expect(_cover(_owner_world).broken_keys().size() == BREAK_KEYS.size(),
		"a second pass confirms nothing twice")


## Somebody arriving after the fight gets the ground as it was left.
func _check_late_join() -> void:
	if not await _start_late_joiner():
		return
	_late_world._request_world_state.rpc_id(1)
	var caught_up := await _wait_until(_late_joiner_caught_up, RPC_FRAMES)
	_expect(caught_up, "a late joiner is told about the craters and the losses")
	if not caught_up:
		return
	_expect(_same_keys(_cover(_late_world).broken_keys(), BREAK_KEYS),
		"and about exactly the plants that are gone")
	_expect(_late_boss != null
		and is_equal_approx(_late_boss.health(), _server_boss.health())
		and _late_boss.engaged() == _server_boss.engaged(),
		"and receives Bigfoot's health and engagement snapshot")
	_expect(await _wait_until(
		func() -> bool:
			return _late_world.active_ability_wall_count() == 1,
		RPC_FRAMES),
		"and receives the remaining lifetime of an active Wall")


func _client_has_one_scar() -> bool:
	return _scars(_owner_world).count() == 1


func _client_has_two_scars() -> bool:
	return _scars(_owner_world).count() == 2


func _host_saw_the_volume() -> bool:
	return _cover(_server_world).saw(_expected_hit)


func _server_received_packet_after(count: int) -> bool:
	return _cover(_server_world).absorbed.size() > count


func _owner_projectile_rejected(request_sequence: int) -> bool:
	return _owner_player != null \
		and _owner_player.ability_projectile_request_state(request_sequence) \
			== OnlinePlayer.ProjectileRequestState.REJECTED


func _owner_projectile_accepted(request_sequence: int) -> bool:
	return _owner_player != null \
		and _owner_player.ability_projectile_request_state(request_sequence) \
			== OnlinePlayer.ProjectileRequestState.ACCEPTED


func _projectile_copies_spawned() -> bool:
	return _projectile_under(_owner_world) != null \
		and _projectile_under(_server_world) != null


func _projectile_under(world: GameWorld) -> AbilityProjectile:
	if world == null:
		return null
	for child: Node in world.get_children():
		if child is AbilityProjectile:
			return child as AbilityProjectile
	return null


func _projectile_of(world: GameWorld, id: String) -> AbilityProjectile:
	if world == null:
		return null
	for child: Node in world.get_children():
		if child is AbilityProjectile:
			var projectile := child as AbilityProjectile
			if projectile.definition != null \
					and projectile.definition.ability_id == id:
				return projectile
	return null


func _projectile_copies_spawned_for(id: String) -> bool:
	return _projectile_of(_owner_world, id) != null \
		and _projectile_of(_server_world, id) != null


func _delayed_blasts_under(world: GameWorld) -> Array[AbilityDelayedBlast]:
	var found: Array[AbilityDelayedBlast] = []
	if world == null:
		return found
	for child: Node in world.get_children():
		if child is AbilityDelayedBlast:
			found.append(child as AbilityDelayedBlast)
	return found


func _explosion_count(world: GameWorld) -> int:
	var count := 0
	if world == null:
		return count
	for child: Node in world.get_children():
		if child is EnergyExplosion and not child.is_queued_for_deletion():
			count += 1
	return count


func _parry_state_shared() -> bool:
	var server_player := _server_world._spawned_players.get(
		_owner_id) as OnlinePlayer
	return server_player != null and server_player.parry_active() \
		and _owner_player != null and _owner_player.parry_active()


func _owner_combat_state_matches(expected_health: float) -> bool:
	return _owner_player != null \
		and is_equal_approx(_owner_player.health(), expected_health) \
		and _owner_player.has_status(CombatStatuses.FLIGHTLESS)


func _server_dust_count_is(expected: int) -> bool:
	var server_player := _server_world._spawned_players.get(
		_owner_id) as OnlinePlayer
	return server_player != null and server_player.dust.impact_count == expected


func _owner_connected() -> bool:
	return _owner_peer != null and _owner_peer.get_connection_status() \
		== MultiplayerPeer.CONNECTION_CONNECTED


func _late_connected() -> bool:
	return _late_peer != null and _late_peer.get_connection_status() \
		== MultiplayerPeer.CONNECTION_CONNECTED


func _client_told_of_breaks() -> bool:
	return _cover(_owner_world).broken_keys().size() == BREAK_KEYS.size()


func _late_joiner_caught_up() -> bool:
	return _scars(_late_world).count() == 2 \
		and _cover(_late_world).broken_keys().size() == BREAK_KEYS.size() \
		and _late_boss != null \
		and is_equal_approx(_late_boss.health(), _server_boss.health()) \
		and _late_boss.engaged() == _server_boss.engaged()


func _owner_boss_synced() -> bool:
	return _owner_boss != null \
		and is_equal_approx(_owner_boss.health(), _expected_boss_health) \
		and _owner_boss.engaged()


func _host_boss_health_matches() -> bool:
	return _server_boss != null \
		and is_equal_approx(_server_boss.health(), _expected_boss_health)


func _scar(direction: Vector3) -> TerrainScars.Scar:
	var scar := TerrainScars.Scar.new()
	scar.direction = direction
	scar.radius = SCAR_RADIUS
	scar.depth = SCAR_DEPTH
	scar.profile = TerrainScars.Profile.BOWL
	scar.char = 0.4
	return scar


func _scars(world: GameWorld) -> TerrainScars:
	return world.planet().shape.scars


func _cover(world: GameWorld) -> TestCover:
	return world.get_node("Planet/TestCover") as TestCover


func _same_keys(got: PackedInt32Array, want: PackedInt32Array) -> bool:
	for key in want:
		if got.find(key) < 0:
			return false
	return got.size() == want.size()


func _start_peers() -> bool:
	_server_branch = Node.new()
	_server_branch.name = "ServerBranch"
	add_child(_server_branch)
	_server_api = SceneMultiplayer.new()
	_server_peer = _listen()
	if _server_peer == null:
		_expect(false, "ENet server binds a local test port")
		return false
	_server_api.multiplayer_peer = _server_peer
	get_tree().set_multiplayer(_server_api, _server_branch.get_path())

	_owner_branch = Node.new()
	_owner_branch.name = "OwnerBranch"
	add_child(_owner_branch)
	_owner_api = SceneMultiplayer.new()
	_owner_peer = ENetMultiplayerPeer.new()
	if not _expect(_owner_peer.create_client("127.0.0.1", _port) == OK,
			"the client starts an ENet client"):
		return false
	_owner_api.multiplayer_peer = _owner_peer
	get_tree().set_multiplayer(_owner_api, _owner_branch.get_path())
	var connected := await _wait_until(_owner_connected, CONNECT_FRAMES)
	if not _expect(connected, "the client connects through ENet"):
		return false
	_owner_id = _owner_api.get_unique_id()
	_register_peer(1)
	_register_peer(_owner_id)
	return _expect(_owner_id > 1, "and is given a non-authority peer id")


## The host drops requests from peers that are not on its roster, so a harness
## that never registered anybody would have every client packet rejected for the
## right reason and fail for the wrong one. A registered roster also means the
## late joiner is sent player snapshots and spawns bodies for them; those bodies
## address peers whose cut-down worlds have no matching node, which is where the
## "Failed to get path from RPC" lines in a passing run come from.
func _register_peer(peer_id: int) -> void:
	NetworkManager.players[peer_id] = {
		"name": "Peer%d" % peer_id,
		"peer_id": peer_id,
		"steam_id": 0,
		"body": CharacterDB.DEFAULT_BODY,
		"skin": CharacterDB.default_skin(CharacterDB.DEFAULT_BODY),
		"worn": {},
		"tints": {},
	}


func _start_late_joiner() -> bool:
	_late_branch = Node.new()
	_late_branch.name = "LateBranch"
	add_child(_late_branch)
	_late_api = SceneMultiplayer.new()
	_late_peer = ENetMultiplayerPeer.new()
	if not _expect(_late_peer.create_client("127.0.0.1", _port) == OK,
			"the late joiner starts an ENet client"):
		return false
	_late_api.multiplayer_peer = _late_peer
	get_tree().set_multiplayer(_late_api, _late_branch.get_path())
	var connected := await _wait_until(_late_connected, CONNECT_FRAMES)
	if not _expect(connected, "the late joiner connects after the fight"):
		return false
	_register_peer(_late_api.get_unique_id())
	_late_world = _new_world()
	_late_branch.add_child(_late_world)
	_late_boss = _boss(_late_world)
	await _network_frames(4)
	return true


func _listen() -> ENetMultiplayerPeer:
	var first_port := 47100 + (OS.get_process_id() % 800)
	for offset in 12:
		var peer := ENetMultiplayerPeer.new()
		if peer.create_server(first_port + offset, 4) == OK:
			_port = first_port + offset
			return peer
	return null


func _build_worlds() -> void:
	_server_world = _new_world()
	_server_branch.add_child(_server_world)
	_owner_world = _new_world()
	_owner_branch.add_child(_owner_world)
	await _network_frames(6)
	_server_boss = _boss(_server_world)
	_owner_boss = _boss(_owner_world)

	# Identical relative node paths on every peer: the player RPCs and the flora
	# confirmations are both addressed by path.
	_add_player(_server_world, _owner_id)
	_owner_player = _add_player(_owner_world, _owner_id)
	await _network_frames(4)


func _new_world() -> GameWorld:
	var world := GameWorld.new()
	world.name = "World"
	var spawn_points := Node3D.new()
	spawn_points.name = "SpawnPoints"
	var marker := Marker3D.new()
	marker.name = "Spawn1"
	spawn_points.add_child(marker)
	world.add_child(spawn_points)
	var cycle := TEST_CYCLE.new() as CelestialCycle
	cycle.name = "CelestialCycle"
	world.add_child(cycle)
	var planet := Planet.new()
	planet.name = "Planet"
	# Nothing is looked at here. A scar has to land in the height field and be
	# told to the other peer, and none of that wants a quadtree.
	planet.max_depth = 0
	planet.collision_range = 0.0
	planet.has_water = false
	planet.has_clouds = false
	world.add_child(planet)
	var territory := Node3D.new()
	territory.name = "BigfootTerritory"
	planet.add_child(territory)
	var boss := BigfootBoss.new()
	boss.name = "Bigfoot"
	boss.process_mode = Node.PROCESS_MODE_DISABLED
	boss.set_physics_process(false)
	boss.set_process(false)
	territory.add_child(boss)
	var cover := TestCover.new()
	cover.name = "TestCover"
	planet.add_child(cover)
	# Three worlds share one scene tree, and the reconciliation pass walks the
	# tree's damage-field group rather than its own children. Left running, each
	# world would drain the others' pending breaks. It is driven by hand instead.
	world.set_physics_process(false)
	return world


func _boss(world: GameWorld) -> BigfootBoss:
	return world.get_node_or_null("Planet/BigfootTerritory/Bigfoot") \
		as BigfootBoss


func _add_player(world: GameWorld, peer_id: int) -> OnlinePlayer:
	var player := PLAYER.instantiate() as OnlinePlayer
	player.name = str(peer_id)
	player.peer_id = peer_id
	player.defer_camera = true
	world.add_child(player, true)
	player.set_process(false)
	player.set_physics_process(false)
	player.global_transform = Transform3D.IDENTITY
	player.reset_network_state(player.global_transform)
	# Undressed. Nothing here looks at the body, and the default outfit's skins
	# are the only thing in this harness that needs a full skeleton.
	player.holster()
	player.equipment.clear()
	player.hotbar.clear()
	player.abilities.clear()
	player.backpack.clear()
	world._spawned_players[peer_id] = player
	return player


func _wait_until(test: Callable, frames: int) -> bool:
	for _frame in frames:
		_poll_network()
		if bool(test.call()):
			return true
		await get_tree().process_frame
	return bool(test.call())


func _network_frames(frames: int) -> void:
	for _frame in frames:
		_poll_network()
		await get_tree().process_frame


func _poll_network() -> void:
	for api: SceneMultiplayer in [_server_api, _owner_api, _late_api]:
		if api != null and api.has_multiplayer_peer():
			api.poll()


func _expect(condition: bool, message: String) -> bool:
	if condition:
		print("ability_net_test: PASS  %s" % message)
		return true
	_failures += 1
	push_error("ability_net_test: FAIL  %s" % message)
	return false


func _finish() -> void:
	for peer: ENetMultiplayerPeer in [_late_peer, _owner_peer, _server_peer]:
		if peer != null:
			peer.close()
	for branch: Node in [_late_branch, _owner_branch, _server_branch]:
		if is_instance_valid(branch):
			branch.queue_free()
	for _frame in 3:
		await get_tree().process_frame
	_restore_settings()
	NetworkManager.players.clear()
	NetworkManager.players.merge(_saved_players, true)
	NetworkManager.state = _saved_state as NetworkManager.SessionState
	NetworkManager.is_single_player = _saved_single_player
	NetworkManager.is_host = _saved_host
	print("ability_net_test: %s" % (
		"all checks passed" if _failures == 0
		else "%d check(s) failed" % _failures))
	get_tree().quit(1 if _failures > 0 else 0)


## The owner branch is a real local OnlinePlayer and the harness deliberately
## clears its containers. Preserve the human player's profile around that work:
## without this, the deferred loadout save turns a networking test into an
## apparel/ability wipe in user://settings.cfg.
func _snapshot_settings() -> void:
	var path := ProjectSettings.globalize_path(SETTINGS_PATH)
	_settings_existed = FileAccess.file_exists(path)
	if _settings_existed:
		_settings_bytes = FileAccess.get_file_as_bytes(path)


func _restore_settings() -> void:
	var path := ProjectSettings.globalize_path(SETTINGS_PATH)
	if not _settings_existed:
		if FileAccess.file_exists(path):
			DirAccess.remove_absolute(path)
		return
	var file := FileAccess.open(path, FileAccess.WRITE)
	if file == null:
		push_error("ability_net_test: could not restore %s" % path)
		return
	file.store_buffer(_settings_bytes)
	file.close()
