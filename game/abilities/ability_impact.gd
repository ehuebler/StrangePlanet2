class_name AbilityImpact
extends RefCounted

## Shared impact dispatcher for data-authored abilities.
##
## Projectile and grapple implementations only report a point and facing. The
## definition decides whether that point is merely visual, an explosion, or a
## crater-producing slam; all target damage still travels through DamageHit and
## all terrain changes still travel through TerrainScars.

const FLORA_MARGIN := 0.6
const MIN_FLORA_DAMAGE := 6000.0


static func apply(shooter: OnlinePlayer, definition: AbilityDefinition,
		at: Vector3, facing: Vector3, stats_override: Dictionary = {}) -> void:
	if not is_instance_valid(shooter) or definition == null or not at.is_finite():
		return
	if facing.length_squared() < 0.001 or not facing.is_finite():
		facing = Vector3.UP
	facing = facing.normalized()
	match definition.impact_type:
		AbilityDefinition.ImpactType.EXPLOSION_CRATER, \
				AbilityDefinition.ImpactType.GRAPPLE_SLAM:
			_crater_blast(shooter, definition, at, facing, stats_override)
		AbilityDefinition.ImpactType.MASSIVE_BLAST, \
				AbilityDefinition.ImpactType.DELAYED_BLAST:
			_massive_blast(shooter, definition, at, facing, stats_override)


static func _stats_of(definition: AbilityDefinition, overlay: Dictionary) -> Dictionary:
	if overlay.is_empty():
		return definition.stats
	var merged := definition.stats.duplicate(true)
	merged.merge(overlay, true)
	return merged


static func _scaled_knockback(shooter: OnlinePlayer, stats: Dictionary) -> float:
	var knockback := maxf(float(stats.get("knockback", 0.0)), 0.0)
	if shooter != null and CrawlerRules.active() \
			and shooter.has_method(&"crawler_knockback_scale"):
		knockback *= float(shooter.call(&"crawler_knockback_scale"))
	return knockback


static func _crater_blast(shooter: OnlinePlayer,
		definition: AbilityDefinition, at: Vector3, facing: Vector3,
		stats_override: Dictionary = {}) -> void:
	var stats := _stats_of(definition, stats_override)
	var ability_id := definition.ability_id
	var direct_radius := maxf(float(stats.get("projectile_radius", 0.5)) * 2.0, 0.5)
	var direct := DamageHit.impact(at, direct_radius,
		maxf(float(stats.get("damage", 0.0)), 0.0))
	direct.ability_id = ability_id
	direct.affects_flora = false
	shooter.deal_damage(direct)

	var blast_radius := maxf(float(stats.get("radius", 1.0)), 0.1)
	var blast := DamageHit.area(at, blast_radius,
		maxf(float(stats.get("impact", stats.get("damage", 0.0))), 0.0), 1.0)
	blast.ability_id = ability_id
	blast.affects_flora = false
	var knockback := _scaled_knockback(shooter, stats)
	if knockback > 0.0:
		blast.radial_impulse = knockback
		blast.radial_lift = knockback * 0.18
	shooter.deal_damage(blast)

	shooter.play_ability_explosion(at, blast_radius, definition.tint)
	shooter.play_meteor_impact_dust(
		at, facing, maxf(blast_radius, 0.5),
		1.25 if definition.impact_type == AbilityDefinition.ImpactType.GRAPPLE_SLAM
		else 0.85)

	var crater_radius := maxf(float(stats.get("crater_radius", 0.0)), 0.0)
	var crater_depth := maxf(float(stats.get("crater_depth", 0.0)), 0.0)
	if crater_radius <= 0.0 or crater_depth <= 0.0:
		return
	var ground := _ground_contact(shooter, at, crater_radius * 1.75)
	if ground.is_empty():
		return
	var centre: Vector3 = ground["position"]
	var world_planet: Planet = ground["planet"]

	var flatten := DamageHit.area(centre, crater_radius + FLORA_MARGIN,
		maxf(MIN_FLORA_DAMAGE, float(stats.get("impact", 0.0))), 0.0)
	flatten.ability_id = ability_id
	flatten.affects_combatants = false
	flatten.plant_break_effects = false
	shooter.deal_damage(flatten)

	var scar := TerrainScars.Scar.new()
	scar.direction = world_planet.to_local(centre).normalized()
	scar.radius = crater_radius
	scar.depth = crater_depth
	scar.profile = TerrainScars.Profile.BOWL
	scar.warp = maxf(float(stats.get("crater_warp", 0.0)), 0.0)
	scar.seed = _rim_seed(centre)
	scar.char = 0.52 if definition.impact_type \
		== AbilityDefinition.ImpactType.EXPLOSION_CRATER else 0.34
	scar.tint = Color(0.20, 0.10, 0.24) if definition.impact_type \
		== AbilityDefinition.ImpactType.EXPLOSION_CRATER \
		else Color(0.16, 0.13, 0.11)
	shooter.request_scar(scar)


static func _massive_blast(shooter: OnlinePlayer,
		definition: AbilityDefinition, at: Vector3, facing: Vector3,
		stats_override: Dictionary = {}) -> void:
	# Projectile and delayed marker visuals exist on every peer. Only the host is
	# allowed to turn one into actor state, flora damage, or real terrain.
	if shooter.multiplayer.has_multiplayer_peer() \
			and not shooter.multiplayer.is_server():
		return
	var stats := _stats_of(definition, stats_override)
	var ability_id := definition.ability_id
	var blast_radius := maxf(float(stats.get("radius", 1.0)), 0.1)
	# Move the damage origin just off the struck surface. This is important for
	# occlusion: a barrier hit on its near face should protect actors behind it
	# rather than beginning the visibility ray inside the barrier.
	var effect_at := at + facing * minf(blast_radius * 0.01, 0.12)
	var reaction := clampi(
		definition.reaction_type, 0, DamageHit.Reaction.size() - 1) \
		as DamageHit.Reaction
	var knockback := _scaled_knockback(shooter, stats)
	var lift := maxf(float(stats.get("lift", 0.0)), 0.0)

	var direct_radius := maxf(
		float(stats.get("projectile_radius", 0.5)) * 2.0, 0.5)
	var direct := DamageHit.impact(
		effect_at, direct_radius, maxf(float(stats.get("damage", 0.0)), 0.0))
	direct.ability_id = ability_id
	direct.affects_flora = false
	shooter.deal_authoritative_ability_damage(direct)

	var blast := DamageHit.area(effect_at, blast_radius,
		maxf(float(stats.get("impact", stats.get("damage", 0.0))), 0.0), 1.0)
	blast.ability_id = ability_id
	blast.affects_flora = false
	blast.reaction = reaction
	blast.radial_impulse = knockback
	blast.radial_lift = lift
	blast.blocked_by_world = definition.blast_occlusion
	shooter.deal_authoritative_ability_damage(blast)

	if definition.affects_players:
		var player_blast := DamageHit.area(effect_at, blast_radius,
			maxf(float(stats.get("player_damage", 0.0)), 0.0), 1.0)
		player_blast.ability_id = ability_id
		player_blast.reaction = reaction
		player_blast.radial_impulse = knockback
		player_blast.radial_lift = lift
		player_blast.blocked_by_world = definition.blast_occlusion
		shooter.deal_authoritative_player_damage(player_blast)

	if definition.self_launch:
		_launch_source(shooter, definition, effect_at, blast_radius, facing)

	var nuclear := definition.impact_type \
		== AbilityDefinition.ImpactType.MASSIVE_BLAST
	shooter.play_ability_explosion(effect_at, blast_radius, definition.tint,
		maxf(float(stats.get("explosion_duration", 0.8)), 0.2), true, nuclear)
	shooter.play_meteor_impact_dust(
		at, facing, maxf(blast_radius, 0.5), 2.0)

	var crater_radius := maxf(float(stats.get("crater_radius", 0.0)), 0.0)
	var crater_depth := maxf(float(stats.get("crater_depth", 0.0)), 0.0)

	# Flora goes with the blast rather than with the hole, and before the ground
	# contact is known so that an air burst still strips what it reached. Clearing
	# only out to the crater rim left grass standing well inside a fireball, which
	# is the one thing a blast this size cannot be seen to do.
	var flatten := DamageHit.area(effect_at,
		maxf(blast_radius, crater_radius + FLORA_MARGIN),
		maxf(MIN_FLORA_DAMAGE, float(stats.get("damage", 0.0))), 0.0)
	flatten.ability_id = ability_id
	flatten.affects_combatants = false
	flatten.plant_break_effects = false
	shooter.deal_authoritative_ability_damage(flatten)

	if crater_radius <= 0.0 or crater_depth <= 0.0:
		return
	var ground := _ground_contact(shooter, at, crater_radius * 1.75)
	if ground.is_empty():
		return
	var centre: Vector3 = ground["position"]
	var world_planet: Planet = ground["planet"]

	var scar := TerrainScars.Scar.new()
	scar.direction = world_planet.to_local(centre).normalized()
	scar.radius = crater_radius
	scar.depth = crater_depth
	scar.profile = TerrainScars.Profile.BOWL
	scar.warp = maxf(float(stats.get("crater_warp", 0.0)), 0.0)
	scar.seed = _rim_seed(centre)
	scar.char = 0.76
	scar.tint = Color(0.12, 0.055, 0.035) \
		if definition.impact_type == AbilityDefinition.ImpactType.MASSIVE_BLAST \
		else Color(0.06, 0.16, 0.15)
	shooter.request_scar(scar)


## Which set of rim lobes a hole here wanders on.
##
## Taken from the place it was struck rather than drawn at random: the host sends
## this on the wire so every peer digs the same hole either way, but a position
## also means two shots at the same spot leave the same shape and a harness can
## say what it expects to see.
static func _rim_seed(at: Vector3) -> float:
	return fposmod(at.x * 0.7391 + at.y * 1.4142 + at.z * 2.2360, TAU)


static func _launch_source(shooter: OnlinePlayer,
		definition: AbilityDefinition, at: Vector3, radius: float,
		facing: Vector3) -> void:
	var source_at := shooter.combat_position()
	var bounds := maxf(shooter.combat_radius(), 0.0)
	var away := maxf(source_at.distance_to(at) - bounds, 0.0)
	if away >= radius:
		return
	var share := 1.0 - away / radius
	var outward := source_at - at
	if outward.length_squared() < 0.001:
		outward = facing
	if outward.length_squared() < 0.001:
		outward = shooter.global_basis.y
	outward = outward.normalized()
	var up := shooter.global_basis.y.normalized()
	var speed := maxf(float(
		definition.stats.get("self_launch_speed", 0.0)), 0.0)
	var lift := maxf(float(definition.stats.get("lift", 0.0)), 0.0)
	shooter.force_full_ragdoll(
		outward * speed * share + up * lift * share)


static func _ground_contact(shooter: OnlinePlayer, at: Vector3,
		max_distance: float) -> Dictionary:
	var world_planet := shooter.planet()
	if world_planet == null or world_planet.shape == null:
		return {}
	var local := world_planet.to_local(at)
	if local.length_squared() < 1.0:
		return {}
	var direction := local.normalized()
	var spacing := world_planet.finest_spacing()
	var surface_local := world_planet.shape.surface_point(direction, spacing)
	var surface := world_planet.to_global(surface_local)
	if at.distance_to(surface) > maxf(max_distance, 0.5):
		return {}
	var normal_local := world_planet.shape.normal_at(direction, spacing).normalized()
	var normal := (world_planet.global_basis * normal_local).normalized()
	return {
		"planet": world_planet,
		"position": surface,
		"normal": normal,
	}
