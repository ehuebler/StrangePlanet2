class_name CrawlerImpactCast
extends RefCounted

## Seated Impact Cast: other equipped abilities fire from a host impact.


const SKIP := [
	"overdrive",
	"grapple",
	"lasso",
	"teleport",
	"wall",
]
const MIN_GAP := 0.28

static var _echoing := 0
static var _last_msec: Dictionary = {}


static func enabled(stats: Dictionary) -> bool:
	return float(stats.get("impact_cast", 0.0)) > 0.0 \
		and float(stats.get("_impact_echo", 0.0)) <= 0.0


static func is_echo(stats: Dictionary) -> bool:
	return float(stats.get("_impact_echo", 0.0)) > 0.0


static func can_echo(catalog_id: String) -> bool:
	var clean := CrawlerCatalog.catalog_id(catalog_id)
	if clean.is_empty() or not CrawlerCatalog.is_ability(clean):
		return false
	return not SKIP.has(clean)


static func guests(player: OnlinePlayer, host_id: String) -> PackedStringArray:
	var out := PackedStringArray()
	if player == null or player.crawler_kit == null or player.abilities == null:
		return out
	var host := CrawlerCatalog.catalog_id(host_id)
	var seen := {}
	for index in player.abilities.size():
		var card := player.crawler_kit.equipped_card(index)
		if card == null or card.id.is_empty() or card.id == host:
			continue
		if not can_echo(card.id) or seen.has(card.id):
			continue
		seen[card.id] = true
		out.append(card.id)
	return out


static func random_along(normal: Vector3, up: Vector3 = Vector3.UP) -> Vector3:
	var face := normal
	if face.length_squared() < 0.000001:
		face = up
	if face.length_squared() < 0.000001:
		face = Vector3.UP
	face = face.normalized()
	var rng := RandomNumberGenerator.new()
	rng.randomize()
	var jitter := Vector3(
		rng.randf_range(-1.0, 1.0),
		rng.randf_range(-1.0, 1.0),
		rng.randf_range(-1.0, 1.0))
	var along := (face * 1.15 + jitter).normalized()
	if along.length_squared() < 0.000001:
		return face
	if along.dot(face) < 0.12:
		along = (along + face).normalized()
	return along


static func echo_overlay(player: OnlinePlayer, guest_id: String) -> Dictionary:
	var overlay := {}
	if player != null and player.has_method(&"crawler_ability_overlay"):
		overlay = player.crawler_ability_overlay(guest_id).duplicate(true)
	overlay["impact_cast"] = 0.0
	overlay["_impact_echo"] = 1.0
	return overlay


static func emit(shooter: OnlinePlayer, host_id: String, at: Vector3,
		normal: Vector3, host_stats: Dictionary = {}) -> void:
	if _echoing > 0 or shooter == null or not shooter.is_inside_tree():
		return
	if not at.is_finite() or not enabled(host_stats):
		return
	if shooter.has_method(&"_is_host_authority") \
			and not bool(shooter.call(&"_is_host_authority")):
		return
	var listed := guests(shooter, host_id)
	if listed.is_empty():
		return
	var up := CrawlerMulti.up_of(shooter)
	var face := normal if normal.length_squared() > 0.000001 else up
	for guest_id: String in listed:
		if not _ready(shooter, host_id, guest_id):
			continue
		var along := random_along(face, up)
		var from := at + face.normalized() * 0.28 + along * 0.12
		var overlay := echo_overlay(shooter, guest_id)
		if shooter.has_method(&"publish_impact_cast"):
			shooter.call(&"publish_impact_cast", guest_id, from, along, overlay)
		else:
			play(shooter, guest_id, from, along, overlay)


static func play(shooter: OnlinePlayer, guest_id: String, from: Vector3,
		along: Vector3, overlay: Dictionary = {}) -> void:
	if shooter == null or not shooter.is_inside_tree() or not from.is_finite():
		return
	if along.length_squared() < 0.000001:
		return
	var id := CrawlerCatalog.catalog_id(guest_id)
	if not can_echo(id):
		return
	_echoing += 1
	along = along.normalized()
	var stats := overlay.duplicate(true) if not overlay.is_empty() \
		else echo_overlay(shooter, id)
	var world: Node = DamageHit.game_world_of(shooter)
	if world == null:
		world = shooter.get_parent()
	var owns := not shooter.multiplayer.has_multiplayer_peer() \
		or shooter.multiplayer.is_server()
	if _uses_projectile(id):
		AbilityProjectile.launch(
			world, shooter, id, from, along, owns, Vector3.ZERO, stats)
	elif id == "meteor_punch":
		ImpactCastMeteor.launch(world, shooter, from, along, stats, owns)
	elif id == "hero_punch":
		_play_hero(shooter, from, along, stats, owns)
	elif CrawlerRules.is_roar_ability(id):
		_play_roar(shooter, id, from, stats, owns)
	elif CrawlerRules.is_field_ability(id):
		var definition := ItemDB.ability_definition(id)
		var tint: Color = Color.WHITE
		if definition != null:
			tint = definition.tint
		elif CrawlerFieldVolume.TINTS.has(id):
			tint = CrawlerFieldVolume.TINTS[id] as Color as Color
		CrawlerFieldVolume.create(world, shooter, id, from, stats, tint, owns)
	elif id == "nausicaa":
		_play_nausicaa(shooter, from, along, stats, owns)
	elif id == "lightning":
		_play_lightning(shooter, from, along, stats)
	elif CrawlerRules.ability_type(id) == CrawlerRules.TYPE_BEAM:
		_play_beam(shooter, id, from, along, stats)
	_echoing = maxi(_echoing - 1, 0)


static func _ready(shooter: OnlinePlayer, host_id: String, guest_id: String) -> bool:
	var key := "%s:%s:%s" % [shooter.get_instance_id(), host_id, guest_id]
	var now := Time.get_ticks_msec()
	var wait := int(round(_gap(shooter, guest_id) * 1000.0))
	if now - int(_last_msec.get(key, 0)) < wait:
		return false
	_last_msec[key] = now
	return true


static func _gap(shooter: OnlinePlayer, guest_id: String) -> float:
	var overlay := echo_overlay(shooter, guest_id)
	return maxf(float(overlay.get("cooldown", 0.0)), MIN_GAP)


static func _uses_projectile(id: String) -> bool:
	var definition := ItemDB.ability_definition(id)
	return definition != null and definition.projectile_type in [
		AbilityDefinition.ProjectileType.ENERGY_DISK,
		AbilityDefinition.ProjectileType.ENERGY_ORB,
		AbilityDefinition.ProjectileType.ENERGY_BOLT,
		AbilityDefinition.ProjectileType.ENERGY_ICICLE,
		AbilityDefinition.ProjectileType.ENERGY_CONE,
	]


static func _play_beam(shooter: OnlinePlayer, id: String, from: Vector3,
		along: Vector3, stats: Dictionary) -> void:
	var reach := maxf(float(stats.get("range", 60.0)), 4.0)
	var dest := from + along * reach
	var landed := false
	var hit := LaserEyes._surface(shooter, from, dest)
	if not hit.is_empty():
		dest = hit.get("position", dest) as Vector3
		landed = true
	var width := maxf(float(stats.get("beam_width", 1.0)), 0.35)
	var wobble := maxf(float(stats.get("wobble", 0.0)), 0.0)
	var radius := maxf(float(stats.get("radius", 0.45)), 0.05)
	var damage := maxf(float(stats.get("damage", 0.0)), 0.0)
	var pulse := minf(maxf(float(stats.get("duration", 0.4)), 0.1), 0.4)
	var knockback := maxf(float(stats.get("knockback", 0.0)), 0.0)
	var impact_radius := LaserEyes.IMPACT_RADIUS
	if stats.has("impact_radius"):
		impact_radius = float(stats.get("impact_radius", impact_radius))
	elif width > 1.0:
		impact_radius *= width
	LaserEyes._apply_one(
		shooter, id, stats, from, dest, landed, radius, impact_radius,
		damage * pulse, knockback, pulse, width)
	CrawlerBubbles.emit_beam(
		shooter, id, from, from, dest, wobble, 0,
		PackedVector3Array([from, dest]))
	CrawlerLingers.emit_beam_trail(shooter, id, from, dest)


static func _play_lightning(shooter: OnlinePlayer, from: Vector3,
		along: Vector3, stats: Dictionary) -> void:
	var reach := maxf(float(stats.get("range", 28.0)), 4.0)
	var dest := from + along * reach
	var hops := Lightning.collect_hops(
		shooter, from, dest, int(round(float(stats.get("arcs", 1.0)))),
		float(stats.get("hop_range", Lightning.HOP_RANGE)), Lightning.SNAP_RADIUS)
	if hops.is_empty():
		hops = PackedVector3Array([dest])
	var radius := maxf(float(stats.get("radius", CrawlerRules.LIGHTNING_RADIUS)), 0.05)
	var damage := maxf(float(stats.get("damage", 0.0)), 0.0)
	var pulse := minf(maxf(float(stats.get("duration", 0.4)), 0.1), 0.4)
	var knockback := maxf(float(stats.get("knockback", 0.0)), 0.0) * pulse
	var last := from
	for hop: Vector3 in hops:
		Lightning._strike_segment(
			shooter, "lightning", last, hop, radius, damage * pulse, knockback,
			stats)
		last = hop
	var bolt := PackedVector3Array()
	bolt.append(from)
	bolt.append_array(hops)
	CrawlerBubbles.emit_beam(
		shooter, "lightning", from, from, hops[hops.size() - 1], 0.0, 0, bolt)


static func _play_nausicaa(shooter: OnlinePlayer, from: Vector3,
		along: Vector3, stats: Dictionary, owns: bool) -> void:
	var definition := ItemDB.ability_definition("nausicaa")
	if definition == null:
		return
	var reach := maxf(float(stats.get("range", 14.0)), 2.0)
	var hit := LaserEyes.terrain_surface(shooter, from, from + along * reach)
	if hit.is_empty():
		return
	var at: Vector3 = hit.get("position", from)
	var normal: Vector3 = hit.get("normal", along)
	var world: Node = DamageHit.game_world_of(shooter)
	if world == null:
		world = shooter.get_parent()
	var warning := maxf(float(stats.get("delay", 1.0)), 0.1)
	AbilityDelayedBlast.create(
		world, shooter, definition, from, at, normal, warning, owns, stats)


static func _play_hero(shooter: OnlinePlayer, from: Vector3, along: Vector3,
		stats: Dictionary, owns: bool) -> void:
	var reach := maxf(float(stats.get("range", 3.5)), 0.5)
	var radius := maxf(float(stats.get("radius", 1.15)), 0.2)
	var damage := maxf(float(stats.get("damage", 0.0)), 0.0)
	var knockback := maxf(float(stats.get("knockback", 0.0)), 0.0)
	var prey := CrawlerHoming.lock(shooter, from, along, stats)
	if prey != null:
		along = CrawlerHoming.aim(from, along, stats, shooter)
	var at := from + along * minf(reach, maxf(radius + 0.35, 0.8))
	if prey != null:
		var dest := CrawlerHoming.combat_at(prey)
		if from.distance_to(dest) <= reach + radius:
			at = dest
	if owns:
		for slide: float in CrawlerMulti.punch_offsets(CrawlerMulti.shots(stats)):
			var hit := DamageHit.impact(at + along * slide, radius, damage)
			hit.ability_id = "hero_punch"
			hit.faction = DamageHit.Faction.PLAYER
			if knockback > 0.0:
				hit.world_impulse = along * knockback
			CrawlerElements.stamp(hit, shooter, "hero_punch", stats)
			hit.set_source(shooter)
			DamageHit.apply_to_world(shooter, hit)
	CrawlerBubbles.emit_blast(shooter, "hero_punch", at, maxf(radius, 0.8))
	CrawlerLingers.emit_blast(shooter, "hero_punch", at, maxf(radius, 0.8))


static func _play_roar(shooter: OnlinePlayer, id: String, from: Vector3,
		stats: Dictionary, owns: bool) -> void:
	var reach := maxf(float(stats.get("range", CrawlerRules.ROAR_RADIUS)), 1.0)
	if owns:
		var hit := DamageHit.area(
			from, reach, maxf(float(stats.get("damage", 0.0)), 0.0), 0.2)
		hit.ability_id = id
		hit.faction = DamageHit.Faction.PLAYER
		hit.affects_flora = false
		var knockback := maxf(float(stats.get("knockback", 0.0)), 0.0)
		if knockback > 0.0:
			hit.reaction = DamageHit.Reaction.KNOCKBACK
			hit.radial_impulse = knockback
			hit.radial_lift = knockback * 0.22
		CrawlerElements.stamp(hit, shooter, id, stats)
		hit.set_source(shooter)
		DamageHit.apply_to_world(shooter, hit)
	CrawlerBubbles.emit_shockwave(shooter, id, from, reach)
	CrawlerLingers.emit_shockwave(shooter, id, from, reach)
	var wave := PlayerRoarWave.new()
	shooter.add_child(wave)
	wave.set_color(CrawlerRoar.TINTS.get(id, CrawlerRoar.TINTS["roar"]) as Color)
	wave.set_wave(from, reach)
	shooter.get_tree().create_timer(0.42).timeout.connect(wave.queue_free)
