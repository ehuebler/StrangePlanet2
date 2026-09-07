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
		at: Vector3, facing: Vector3, stats_override: Dictionary = {},
		struck: Node = null) -> void:
	if not is_instance_valid(shooter) or definition == null or not at.is_finite():
		return
	if facing.length_squared() < 0.001 or not facing.is_finite():
		facing = Vector3.UP
	facing = facing.normalized()
	match definition.impact_type:
		AbilityDefinition.ImpactType.EXPLOSION_CRATER, \
				AbilityDefinition.ImpactType.GRAPPLE_SLAM:
			_crater_blast(shooter, definition, at, facing, stats_override)
		AbilityDefinition.ImpactType.FROST_BURST:
			_frost_burst(shooter, definition, at, facing, stats_override)
		AbilityDefinition.ImpactType.TELEPORT:
			_teleport(shooter, definition, at, facing, stats_override, struck)
		AbilityDefinition.ImpactType.MASSIVE_BLAST, \
				AbilityDefinition.ImpactType.DELAYED_BLAST:
			_massive_blast(shooter, definition, at, facing, stats_override)
		AbilityDefinition.ImpactType.KNOCKBACK_BURST:
			_knockback_burst(shooter, definition, at, facing, stats_override, struck)


static func strike_force(shooter: OnlinePlayer, definition: AbilityDefinition,
		at: Vector3, facing: Vector3, stats_override: Dictionary,
		combatant: Node) -> void:
	if not is_instance_valid(shooter) or definition == null \
			or not is_instance_valid(combatant) \
			or not combatant.has_method(&"apply_damage"):
		return
	var stats := _stats_of(definition, stats_override)
	var reach := maxf(float(stats.get("radius", CrawlerRules.FUS_RADIUS)), 0.8)
	var hit := DamageHit.impact(at, reach,
		maxf(float(stats.get("damage", 0.0)), 0.0))
	hit.faction = DamageHit.Faction.PLAYER
	hit.ability_id = definition.ability_id
	hit.affects_flora = false
	hit.projectile = true
	hit.reaction = DamageHit.Reaction.KNOCKBACK
	var knockback := _scaled_knockback(shooter, stats)
	if knockback > 0.0:
		var along := facing.normalized() if facing.length_squared() > 0.001 \
			else Vector3.FORWARD
		hit.world_impulse = along * knockback
		hit.radial_impulse = knockback * 0.35
		hit.radial_lift = knockback * 0.30
	CrawlerElements.stamp(hit, shooter, definition.ability_id, stats)
	hit.set_source(shooter)
	combatant.call(&"apply_damage", hit.resolved_for(combatant))


static func _knockback_burst(shooter: OnlinePlayer,
		definition: AbilityDefinition, at: Vector3, facing: Vector3,
		stats_override: Dictionary = {}, struck: Node = null) -> void:
	if is_instance_valid(struck):
		strike_force(shooter, definition, at, facing, stats_override, struck)
		return
	if shooter == null or not shooter.is_inside_tree():
		return
	var stats := _stats_of(definition, stats_override)
	var reach := maxf(float(stats.get("radius", CrawlerRules.FUS_RADIUS)), 0.8)
	for node_variant: Variant in shooter.get_tree().get_nodes_in_group(
			DamageHit.COMBATANT_GROUP):
		var combatant := node_variant as Node
		if combatant == null or combatant == shooter:
			continue
		if not combatant.has_method(&"apply_damage") \
				or not combatant.has_method(&"combat_faction"):
			continue
		if int(combatant.call(&"combat_faction")) != DamageHit.Faction.ENEMY:
			continue
		if combatant.has_method(&"is_alive") \
				and not bool(combatant.call(&"is_alive")):
			continue
		var point := at
		if combatant.has_method(&"combat_position"):
			point = combatant.call(&"combat_position")
		elif combatant is Node3D:
			point = (combatant as Node3D).global_position
		var bounds := 0.4
		if combatant.has_method(&"combat_radius"):
			bounds = float(combatant.call(&"combat_radius"))
		if point.distance_to(at) > reach + bounds:
			continue
		strike_force(shooter, definition, at, facing, stats_override, combatant)


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
	direct.projectile = true
	direct.explosive = true
	CrawlerElements.stamp(direct, shooter, ability_id, stats)
	shooter.deal_damage(direct)

	var blast_radius := maxf(float(stats.get("radius", 1.0)), 0.1)
	var blast := DamageHit.area(at, blast_radius,
		maxf(float(stats.get("impact", stats.get("damage", 0.0))), 0.0), 1.0)
	blast.ability_id = ability_id
	blast.affects_flora = false
	blast.explosive = true
	var knockback := _scaled_knockback(shooter, stats)
	if knockback > 0.0:
		blast.radial_impulse = knockback
		blast.radial_lift = knockback * 0.18
	CrawlerElements.stamp(blast, shooter, ability_id, stats)
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


static func _frost_burst(shooter: OnlinePlayer,
		definition: AbilityDefinition, at: Vector3, facing: Vector3,
		stats_override: Dictionary = {}) -> void:
	var stats := _stats_of(definition, stats_override)
	var ability_id := definition.ability_id
	var direct_radius := maxf(float(stats.get("projectile_radius", 0.16)) * 2.0, 0.35)
	var direct := DamageHit.impact(at, direct_radius,
		maxf(float(stats.get("damage", 0.0)), 0.0))
	direct.ability_id = ability_id
	direct.affects_flora = false
	direct.projectile = true
	var knockback := _scaled_knockback(shooter, stats)
	if knockback > 0.0:
		direct.radial_impulse = knockback
		direct.radial_lift = knockback * 0.12
	CrawlerElements.stamp(direct, shooter, ability_id, stats)
	shooter.deal_damage(direct)

	var blast_radius := maxf(float(stats.get("radius", 2.2)), 0.2)
	var frost := DamageHit.area(at, blast_radius, 0.0, 0.0)
	frost.ability_id = ability_id
	frost.affects_flora = false
	frost.projectile = true
	CrawlerElements.stamp(frost, shooter, ability_id, stats)
	shooter.deal_damage(frost)

	var white := Color(0.95, 0.98, 1.0)
	shooter.play_ability_explosion(at, blast_radius, white, 0.42)
	CrawlerBurst.snow(shooter.get_parent(), at, facing, blast_radius)


static func _teleport(shooter: OnlinePlayer, definition: AbilityDefinition,
		at: Vector3, facing: Vector3, stats_override: Dictionary = {},
		struck: Node = null) -> void:
	var stats := _stats_of(definition, stats_override)
	var swap := float(stats.get("swap", 0.0)) > 0.5
	var stand_off := maxf(float(stats.get("radius",
		CrawlerRules.TELEPORT_RADIUS)), 0.4)
	var prey := struck if _is_swap_target(struck, shooter) else null
	var from := shooter.global_position
	var dest := at
	var look := -facing
	if prey != null:
		var prey_at: Vector3 = prey.global_position if prey is Node3D \
			else _combat_point(prey)
		look = prey_at - from
		if look.length_squared() < 0.001:
			look = -shooter.global_basis.z
		if swap:
			dest = prey_at
			_warp_combatant(prey, from)
		else:
			var away := look.normalized()
			var gap := stand_off + shooter.combat_radius()
			if prey.has_method(&"combat_radius"):
				gap += float(prey.call(&"combat_radius"))
			dest = prey_at - away * gap
	var white := Color(1.0, 1.0, 1.0)
	shooter.play_ability_explosion(from, 0.7, white, 0.28)
	shooter.play_ability_explosion(dest, 0.85, white, 0.32)
	shooter.warp_to(dest, look)


static func _is_swap_target(node: Node, shooter: OnlinePlayer) -> bool:
	if node == null or node == shooter or not is_instance_valid(node):
		return false
	if node is OnlinePlayer:
		return false
	if node.has_method(&"is_alive") and not bool(node.call(&"is_alive")):
		return false
	if node.has_method(&"is_dead") and bool(node.call(&"is_dead")):
		return false
	if node.has_method(&"combat_faction"):
		return int(node.call(&"combat_faction")) == DamageHit.Faction.ENEMY
	return node is CrawlerMob


static func _warp_combatant(node: Node, at: Vector3) -> void:
	if node != null and node.has_method(&"warp_to"):
		node.call(&"warp_to", at)
		return
	if node is Node3D and at.is_finite():
		(node as Node3D).global_position = at


static func _combat_point(node: Node) -> Vector3:
	if node != null and node.has_method(&"combat_position"):
		return node.call(&"combat_position")
	if node is Node3D:
		return (node as Node3D).global_position
	return Vector3.ZERO


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
	direct.projectile = true
	direct.explosive = true
	CrawlerElements.stamp(direct, shooter, ability_id, stats)
	shooter.deal_authoritative_ability_damage(direct)

	var blast := DamageHit.area(effect_at, blast_radius,
		maxf(float(stats.get("impact", stats.get("damage", 0.0))), 0.0), 1.0)
	blast.ability_id = ability_id
	blast.affects_flora = false
	blast.explosive = true
	blast.reaction = reaction
	blast.radial_impulse = knockback
	blast.radial_lift = lift
	blast.blocked_by_world = definition.blast_occlusion
	CrawlerElements.stamp(blast, shooter, ability_id, stats)
	shooter.deal_authoritative_ability_damage(blast)

	if definition.affects_players:
		var player_blast := DamageHit.area(effect_at, blast_radius,
			maxf(float(stats.get("player_damage", 0.0)), 0.0), 1.0)
		player_blast.ability_id = ability_id
		player_blast.explosive = true
		player_blast.reaction = reaction
		player_blast.radial_impulse = knockback
		player_blast.radial_lift = lift
		player_blast.blocked_by_world = definition.blast_occlusion
		CrawlerElements.stamp(player_blast, shooter, ability_id, stats)
		shooter.deal_authoritative_player_damage(player_blast)

	if definition.self_launch:
		_launch_source(shooter, definition, effect_at, blast_radius, facing, stats)

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
		facing: Vector3, stats: Dictionary = {}) -> void:
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
	var numbers := stats if not stats.is_empty() else definition.stats
	var speed := maxf(float(numbers.get("self_launch_speed", 0.0)), 0.0)
	var lift := maxf(float(numbers.get("lift", 0.0)), 0.0)
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
