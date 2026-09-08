extends Node

## Rendering-free checks for the ability catalogue and the ability base class.
##
##     godot --headless --path . dev/_ability_model_test.tscn
##
## The catalogue half needs nothing at all. The gating half needs a body, so it
## builds one — without the planet, which means no water to stand in, so the
## submersion guard is driven through the lava reading instead. That is the same
## number [method OnlinePlayer.submerged_share] answers with and the same guard
## it feeds, and a beam refusing to fire from inside a lava lake is right anyway.

const PLAYER := preload("res://game/player/player.tscn")

var _failures := 0
var _player: OnlinePlayer


## Gated the way [LaserEyes] is, without the beams.
class GatedAbility extends Ability:
	func _configure() -> void:
		blocked_underwater = true


## Gated the way [MeteorPunch] is.
class GroundAbility extends Ability:
	func _configure() -> void:
		allowed_stances = [OnlinePlayer.Stance.STAND, OnlinePlayer.Stance.FLY]


func _ready() -> void:
	_check_catalogue()
	_check_authored_ability_shapes()
	_check_stat_lines()
	_check_slot_filters()

	multiplayer.multiplayer_peer = OfflineMultiplayerPeer.new()
	for item_id: String in ItemDB.ITEMS:
		ItemIcons._cache[item_id] = ImageTexture.new()
	_player = PLAYER.instantiate() as OnlinePlayer
	_player.peer_id = multiplayer.get_unique_id()
	add_child(_player)
	# Nothing here moves; the body is only here to be asked questions.
	_player.set_process(false)
	_player.set_physics_process(false)
	await get_tree().process_frame

	_check_starfire_alternation()
	_check_hero_punch_alternation()
	_check_starfire_motion()
	_check_starfire_rejection()
	await _check_new_ability_runtime()
	await _check_blast_self_launch()
	await _check_blast_presentation()
	_check_training_dummy()
	_check_cooldown()
	_check_gating()
	_check_controller()
	_check_eye_points()
	_check_laser_beam_placement()

	_player.queue_free()
	await get_tree().process_frame
	print("ability_model_test: %s" % (
		"all checks passed" if _failures == 0 else "%d check(s) failed" % _failures))
	get_tree().quit(1 if _failures > 0 else 0)


func _check_catalogue() -> void:
	var ids := ItemDB.ability_ids()
	var expected := PackedStringArray(
		["laser_eyes", "kame", "meteor_punch", "hero_punch", "starfire",
			"nuke", "mini_nuke", "wall", "nausicaa", "lightning",
			"light_bolt", "icicle", "teleport", "fus",
			"roar", "toxic_blast", "charming_aura", "freeze_blast",
			"static_field", "toxic_field", "freeze_field", "healing_field",
			"overdrive"])
	_expect(ids == expected, "all twenty-three abilities are in manifest order")
	for id: String in expected:
		_expect(ItemDB.kind_of(id) == ItemDB.KIND_ABILITY,
			"%s is an ability" % id)
		_expect(not ItemDB.description(id).is_empty(),
			"%s has a description for the menu" % id)
		var path := ItemDB.ability_script(id)
		_expect(ResourceLoader.exists(path),
			"%s names a script that exists" % id)
		var script := load(path) as GDScript
		_expect(script != null and script.new() is Ability,
			"%s script is an Ability" % id)
		_expect(ItemDB.ability_icon(id) != null,
			"%s has a menu icon" % id)
		var stats := ItemDB.stats_of(id)
		_expect(stats.has("damage") and stats.has("range")
			and stats.has("cooldown"),
			"%s quotes damage, range and cooldown" % id)


func _check_authored_ability_shapes() -> void:
	var meteor := ItemDB.ability_definition("meteor_punch")
	var hero_punch := ItemDB.ability_definition("hero_punch")
	var starfire := ItemDB.ability_definition("starfire")
	var nuke := ItemDB.ability_definition("nuke")
	var mini_nuke := ItemDB.ability_definition("mini_nuke")
	var wall := ItemDB.ability_definition("wall")
	var kame := ItemDB.ability_definition("kame")
	var nausicaa := ItemDB.ability_definition("nausicaa")
	var lightning := ItemDB.ability_definition("lightning")
	var light_bolt := ItemDB.ability_definition("light_bolt")
	var icicle := ItemDB.ability_definition("icicle")
	var teleport := ItemDB.ability_definition("teleport")
	var fus := ItemDB.ability_definition("fus")
	var roar := ItemDB.ability_definition("roar")
	var toxic := ItemDB.ability_definition("toxic_blast")
	var charm := ItemDB.ability_definition("charming_aura")
	var frost := ItemDB.ability_definition("freeze_blast")
	var static_field := ItemDB.ability_definition("static_field")
	var toxic_field := ItemDB.ability_definition("toxic_field")
	var freeze_field := ItemDB.ability_definition("freeze_field")
	var healing_field := ItemDB.ability_definition("healing_field")
	var overdrive := ItemDB.ability_definition("overdrive")
	_expect(starfire != null
		and starfire.activation_type
			== AbilityDefinition.ActivationType.SUSTAINED
		and starfire.projectile_type
			== AbilityDefinition.ProjectileType.ENERGY_DISK
		and starfire.impact_type
			== AbilityDefinition.ImpactType.EXPLOSION_CRATER,
		"Starfire dispatches a sustained stream of exploding energy disks")
	_expect(starfire != null and not starfire.animation.is_empty()
		and not starfire.alternate_animation.is_empty()
		and not starfire.hover_animation.is_empty()
		and not starfire.alternate_hover_animation.is_empty()
		and starfire.animation != starfire.alternate_animation,
		"Starfire has left and right jab clips")
	_expect(hero_punch != null
		and hero_punch.activation_type
			== AbilityDefinition.ActivationType.SUSTAINED
		and hero_punch.projectile_type
			== AbilityDefinition.ProjectileType.NONE
		and hero_punch.reaction_type
			== AbilityDefinition.ReactionType.KNOCKBACK
		and hero_punch.animation == &"Fighting_Right_Jab"
		and hero_punch.alternate_animation == &"Fighting_Left_Jab"
		and hero_punch.hover_animation == &"Fighting_Right_Jab"
		and hero_punch.alternate_hover_animation == &"Fighting_Left_Jab"
		and float(hero_punch.stats.get("damage", 0.0)) > 0.0
		and float(hero_punch.stats.get("range", 0.0)) > 0.0
		and float(hero_punch.stats.get("radius", 0.0)) > 0.0
		and float(hero_punch.stats.get("cooldown", 0.0)) > 0.0,
		"Hero Punch is a sustained close-range jab with Starfire's left/right clips")
	_expect(String(CharacterRig.CLIP_ALIASES.get("HeroPunchRight", ""))
			== "Fighting_Right_Jab"
		and String(CharacterRig.CLIP_ALIASES.get("HeroPunchLeft", ""))
			== "Fighting_Left_Jab",
		"Hero Punch aliases the same jab clips Starfire uses")
	_expect(meteor != null and starfire != null
		and is_equal_approx(
			float(starfire.stats.get("crater_radius", 0.0)) * 2.0,
			float(meteor.stats.get("crater_radius", -1.0)))
		and is_equal_approx(
			float(starfire.stats.get("crater_depth", 0.0)) * 2.0,
			float(meteor.stats.get("crater_depth", -1.0))),
		"Starfire's crater dimensions are half Meteor Punch's")
	_expect(nuke != null
		and nuke.projectile_type
			== AbilityDefinition.ProjectileType.ENERGY_ORB
		and nuke.impact_type
			== AbilityDefinition.ImpactType.MASSIVE_BLAST
		and nuke.reaction_type == AbilityDefinition.ReactionType.RAGDOLL
		and nuke.affects_players and nuke.self_launch
		and nuke.blast_occlusion
		and nuke.animation == &"Kame"
		and nuke.hover_animation.is_empty()
		and is_equal_approx(float(nuke.stats.get("animation_duration", 0.0)), 0.28),
		"Nuke authors a host-resolved occluded orb blast and self-launch")
	_expect(nuke != null
		and is_equal_approx(float(nuke.stats.get("range", 0.0)), 240.0)
		and is_equal_approx(float(nuke.stats.get("radius", 0.0)), 110.0)
		and is_equal_approx(
			float(nuke.stats.get("crater_radius", 0.0)), 72.0)
		and is_equal_approx(
			float(nuke.stats.get("crater_depth", 0.0)), 20.0)
		and float(nuke.stats.get("crater_warp", 0.0)) > 0.0,
		"Nuke carries the authored range, blast, and massive crater profile")
	# The blast has to stay inside the reach it can be thrown, or every shot of it
	# catches its own caster and there is no way to use it at a distance.
	_expect(nuke != null
		and float(nuke.stats.get("range", 0.0))
			> float(nuke.stats.get("radius", 0.0)),
		"and can be thrown further than it reaches")
	_expect(mini_nuke != null
		and mini_nuke.projectile_type
			== AbilityDefinition.ProjectileType.ENERGY_ORB
		and mini_nuke.impact_type
			== AbilityDefinition.ImpactType.MASSIVE_BLAST
		and mini_nuke.implementation == nuke.implementation
		and mini_nuke.animation == &"Kame"
		and mini_nuke.hover_animation.is_empty()
		and is_equal_approx(
			float(mini_nuke.stats.get("animation_duration", 0.0)), 0.28)
		and float(mini_nuke.stats.get("radius", 0.0))
			< float(nuke.stats.get("radius", 0.0))
		and float(mini_nuke.stats.get("speed", 0.0))
			> float(nuke.stats.get("speed", 0.0))
		and float(mini_nuke.stats.get("range", 0.0))
			> float(nuke.stats.get("range", 0.0))
		and float(mini_nuke.stats.get("range", 0.0))
			> float(mini_nuke.stats.get("radius", 0.0)),
		"Mini Nuke authors a smaller, faster, longer-flying orb blast")
	_expect(wall != null
		and wall.construct_type == AbilityDefinition.ConstructType.BARRIER
		and is_equal_approx(float(wall.stats.get("wall_width", 0.0)), 8.0)
		and is_equal_approx(float(wall.stats.get("wall_height", 0.0)), 4.0)
		and is_equal_approx(float(wall.stats.get("duration", 0.0)), 7.0)
		and is_equal_approx(
			float(wall.stats.get("fade_duration", 0.0)), 4.0),
		"Wall authors an eight-by-four indestructible fading barrier")
	_expect(kame != null
		and kame.activation_type
			== AbilityDefinition.ActivationType.COMMITTED
		and kame.projectile_type
			== AbilityDefinition.ProjectileType.BEAM
		and kame.impact_type
			== AbilityDefinition.ImpactType.BURN
		and kame.animation == &"Kame"
		and kame.blocked_underwater
		and float(kame.stats.get("damage", 0.0))
			> float(ItemDB.stats_of("laser_eyes").get("damage", 0.0))
		and float(kame.stats.get("range", 0.0))
			> float(ItemDB.stats_of("laser_eyes").get("range", 0.0))
		and float(kame.stats.get("radius", 0.0))
			> float(ItemDB.stats_of("laser_eyes").get("radius", 0.0))
		and float(kame.stats.get("cooldown", 0.0))
			> float(ItemDB.stats_of("laser_eyes").get("cooldown", 0.0))
		and is_equal_approx(float(kame.stats.get("beam_width", 0.0)), 1.2)
		and is_equal_approx(float(kame.stats.get("damage_hz", 0.0)), 16.0),
		"Kame authors a committed rooted two-hand burst, stronger than Laser Eyes")
	_expect(String(CharacterRig.CLIP_ALIASES.get("Kame", "")) == "Two-hand_Blast",
		"Kame plays the two-hand blast clip")
	_expect(nausicaa != null
		and nausicaa.activation_type
			== AbilityDefinition.ActivationType.SUSTAINED
		and nausicaa.impact_type
			== AbilityDefinition.ImpactType.DELAYED_BLAST
		and nausicaa.blast_occlusion
		and nausicaa.animation.is_empty()
		and nausicaa.hover_animation.is_empty()
		and is_equal_approx(
			float(nausicaa.stats.get("delay", 0.0)), 1.0)
		and is_equal_approx(
			float(nausicaa.stats.get("duration", 0.0)), 0.75)
		and float(nausicaa.stats.get("duration", 0.0))
			< float(ItemDB.stats_of("laser_eyes").get("duration", 0.0))
		and is_equal_approx(
			float(nausicaa.stats.get("paint_spacing", 0.0)), 1.25)
		and is_equal_approx(
			float(nausicaa.stats.get("crater_depth", 0.0)), 0.55)
		and is_equal_approx(
			float(nausicaa.stats.get("range", 0.0)), CrawlerRules.NAUSICAA_RANGE),
		"Nausicaä authors a short delayed beam with shallow indents")
	_expect(lightning != null
		and lightning.activation_type
			== AbilityDefinition.ActivationType.SUSTAINED
		and lightning.projectile_type
			== AbilityDefinition.ProjectileType.BEAM
		and lightning.blocked_underwater
		and is_equal_approx(float(lightning.stats.get("arcs", 0.0)), 1.0)
		and is_equal_approx(float(lightning.stats.get("shock", -1.0)), 0.0),
		"Lightning authors a snapping eye bolt that can chain and shock")
	_expect(load(ItemDB.ability_script("lightning")).new() is LaserEyes,
		"Lightning reuses the pulsed-beam contract")
	_expect(light_bolt != null
			and light_bolt.activation_type
				== AbilityDefinition.ActivationType.SUSTAINED
			and light_bolt.projectile_type
				== AbilityDefinition.ProjectileType.ENERGY_BOLT
			and light_bolt.impact_type
				== AbilityDefinition.ImpactType.EXPLOSION_CRATER
			and light_bolt.animation.is_empty()
			and is_equal_approx(float(light_bolt.stats.get("speed", 0.0)),
				CrawlerRules.LIGHT_BOLT_SPEED)
			and float(light_bolt.stats.get("cooldown", 1.0))
				< float(ItemDB.stats_of("starfire").get("cooldown", 0.0)),
		"Light Bolt authors a fast eye-cast particle stream")
	_expect(icicle != null
			and icicle.activation_type
				== AbilityDefinition.ActivationType.SUSTAINED
			and icicle.projectile_type
				== AbilityDefinition.ProjectileType.ENERGY_ICICLE
			and icicle.impact_type
				== AbilityDefinition.ImpactType.FROST_BURST
			and icicle.animation == starfire.animation
			and icicle.alternate_animation == starfire.alternate_animation
			and icicle.hover_animation == starfire.hover_animation
			and icicle.alternate_hover_animation
				== starfire.alternate_hover_animation
			and is_equal_approx(float(icicle.stats.get("speed", 0.0)),
				CrawlerRules.ICICLE_SPEED)
			and is_equal_approx(float(icicle.stats.get("cold", 0.0)),
				CrawlerRules.ICICLE_COLD)
			and is_equal_approx(float(icicle.stats.get("cold_damage", 0.0)),
				CrawlerRules.ICICLE_COLD_DAMAGE),
		"Icicle authors a Starfire-jabbed frost spear with a cold burst")
	_expect(teleport != null
			and teleport.activation_type
				== AbilityDefinition.ActivationType.INSTANT
			and teleport.projectile_type
				== AbilityDefinition.ProjectileType.TELEPORT_ORB
			and teleport.impact_type
				== AbilityDefinition.ImpactType.TELEPORT
			and teleport.animation == &"NukeThrow"
			and teleport.hover_animation == &"NukeFloatThrow"
			and is_equal_approx(float(teleport.stats.get("damage", 1.0)), 0.0)
			and is_equal_approx(float(teleport.stats.get("speed", 0.0)),
				CrawlerRules.TELEPORT_SPEED)
			and is_equal_approx(float(teleport.stats.get("swap", 1.0)), 0.0),
		"Teleport authors a no-damage overhand marker")
	_expect(fus != null
			and fus.activation_type
				== AbilityDefinition.ActivationType.COMMITTED
			and fus.projectile_type
				== AbilityDefinition.ProjectileType.ENERGY_CONE
			and fus.impact_type
				== AbilityDefinition.ImpactType.KNOCKBACK_BURST
			and fus.reaction_type
				== AbilityDefinition.ReactionType.KNOCKBACK
			and fus.animation == &"Roar"
			and is_equal_approx(float(fus.stats.get("damage", 0.0)),
				CrawlerRules.FUS_DAMAGE)
			and is_equal_approx(float(fus.stats.get("knockback", 0.0)),
				CrawlerRules.FUS_KNOCKBACK)
			and float(fus.stats.get("knockback", 0.0))
				> CrawlerRules.ROAR_KNOCKBACK
			and float(fus.stats.get("damage", 0.0))
				< CrawlerRules.ROAR_DAMAGE,
		"Fus authors a roar-posed green force cone with light damage and huge knockback")
	_expect(load(ItemDB.ability_script("fus")).new() is Fus,
		"Fus uses its own committed shout script")
	_expect(roar != null and toxic != null and charm != null and frost != null
			and roar.animation == &"Roar"
			and toxic.animation == &"Roar"
			and charm.animation == &"Roar"
			and frost.animation == &"Roar"
			and roar.implementation == toxic.implementation,
		"the four shockwaves share the Roar animation and script")
	_expect(static_field != null and toxic_field != null and freeze_field != null
			and healing_field != null
			and static_field.animation == &"FieldCast"
			and toxic_field.animation == &"FieldCast"
			and freeze_field.animation == &"FieldCast"
			and healing_field.animation == &"FieldCast"
			and static_field.implementation == toxic_field.implementation
			and freeze_field.implementation == static_field.implementation
			and healing_field.implementation == static_field.implementation
			and is_equal_approx(float(static_field.stats.get("radius", 0.0)), 7.0)
			and is_equal_approx(float(static_field.stats.get("cast", 0.0)), 1.0)
			and is_equal_approx(float(static_field.stats.get("shock", 0.0)), 2.0)
			and is_equal_approx(float(toxic_field.stats.get("toxic", 0.0)), 4.0)
			and is_equal_approx(float(freeze_field.stats.get("freeze", 0.0)), 72.0)
			and is_equal_approx(float(healing_field.stats.get("heal", 0.0)), 8.0),
		"the four fields share the levitate-enter cast and expand to seven metres")
	_expect(String(CharacterRig.CLIP_ALIASES.get("FieldCast", ""))
			== "Spell_Simple_Enter",
		"Field casts play the levitate entrance clip")
	_expect(load(ItemDB.ability_script("static_field")).new() is CrawlerField,
		"Field abilities share the expanding-sphere script")
	_expect(overdrive != null
			and overdrive.activation_type
				== AbilityDefinition.ActivationType.COMMITTED
			and overdrive.animation == &"Roar"
			and overdrive.implementation != roar.implementation
			and float(overdrive.stats.get("boost", 0.0)) > 0.0
			and float(overdrive.stats.get("duration", 0.0)) > 0.0
			and float(overdrive.stats.get("cooldown", 0.0)) > 0.0,
		"Overdrive is a committed roar-pose buff with its own script")


func _check_stat_lines() -> void:
	var lines := ItemDB.stat_lines("laser_eyes")
	_expect(lines.size() == ItemDB.stats_of("laser_eyes").size() - 1,
		"every stat but the damage unit gets a line")
	var written := "\n".join(lines)
	_expect(written.contains("Damage\t1200/s"),
		"the damage unit is appended to the number")
	_expect(written.contains("Range\t60 m"), "range is written in metres")
	# Against the catalogue rather than against a copy of the number in it. What
	# this line is for is the label, the tab and the unit suffix; pinning the
	# value as well only means the formatting test fails when somebody retunes
	# the ability, which is the one thing it has no opinion about.
	_expect(written.contains("Cooldown\t%d s" % int(
		ItemDB.stats_of("laser_eyes").get("cooldown", -1))),
		"cooldown is written in seconds")
	_expect(not written.contains(".0"),
		"whole numbers lose their decimal point")
	_expect(ItemDB.stat_lines("sword").is_empty(),
		"an item with no stats gets no lines")


func _check_slot_filters() -> void:
	var abilities := ItemContainer.new(CharacterDB.ABILITY_SLOTS)
	for index in abilities.size():
		abilities.set_filter(index, ItemDB.ABILITY)
	abilities.set_item(0, "laser_eyes")
	abilities.set_item(1, "sword")
	_expect(abilities.get_item(0) == "laser_eyes",
		"an ability slot takes an ability")
	_expect(abilities.get_item(1).is_empty(),
		"an ability slot still refuses a weapon")


## The beams leave the face.
##
## They used to leave the back of the neck: the offset was measured out along the
## Head bone's own axes, and on this body that bone's forward is the model's
## backward. Worth a standing check rather than a one-off look, because the
## symptom is only visible from outside the character — aim it from the back of
## the head and it still lands on the crosshair, so nothing else in the game
## notices.
func _check_eye_points() -> void:
	var eyes := _player.eye_points()
	var to_body := _player.global_transform.affine_inverse()
	var left := to_body * eyes[0]
	var right := to_body * eyes[1]
	var middle := (left + right) * 0.5
	# The head joint sits on the body's centre line, so anything on the face is
	# ahead of the origin in z and anything on the neck is behind it.
	_expect(middle.z < -0.05,
		"the eyes are out on the face, %.3f m ahead of the body's centre"
		% -middle.z)
	_expect(left.x < right.x, "the left eye is the left one")
	var apart := right.x - left.x
	_expect(apart > 0.02 and apart < 0.2,
		"and the two are a face apart (%.3f m)" % apart)
	_expect(middle.y > 1.0, "at head height (%.2f m)" % middle.y)
	# Both eyes, not just their midpoint: a pair straddling the nose averages out
	# to the right place even if one of them is inside an ear.
	_expect(absf(left.z - right.z) < 0.02 and absf(left.y - right.y) < 0.02,
		"and they are level with each other")


func _check_laser_beam_placement() -> void:
	var left := Vector3(-0.05, 1.4, -0.2)
	var right := Vector3(0.05, 1.4, -0.2)
	var at := Vector3(0.0, 1.2, -8.0)
	var beams := _player.laser_beams()
	beams.aim(left, right, at)
	var core := beams._beams[0][0] as Node3D
	_expect(core != null and core.visible, "the first aim shows the left beam")
	if core != null:
		var along := (at - left).normalized()
		_expect(core.global_position.distance_to(left.lerp(at, 0.5)) < 0.02,
			"the beam sits on the eye-to-target line")
		_expect(core.global_transform.basis.y.normalized().dot(along) > 0.99,
			"the beam points out of the eye")
	_expect(beams.physics_interpolation_mode
			== Node.PHYSICS_INTERPOLATION_MODE_OFF,
		"the beam is not interpolated from a previous pose")
	beams.stop()


func _check_starfire_alternation() -> void:
	var definition := ItemDB.ability_definition("starfire")
	var ability := Starfire.new()
	ability.configure(_player, 0, "starfire", definition)
	var fired := ability.press()
	var first_clip := _player._ability_clip
	ability.tick(0.0)
	ability.tick(ability.cooldown() + 0.01)
	var second_clip := _player._ability_clip
	ability.tick(0.0)
	ability.tick(ability.cooldown() + 0.01)
	var third_clip := _player._ability_clip
	ability.tick(0.0)
	_expect(fired and ability.is_held(),
		"holding Starfire launches each authored disk automatically")
	_expect(first_clip == String(definition.animation)
		and second_clip == String(definition.alternate_animation)
		and third_clip == String(definition.animation),
		"Starfire casts right, left, then right again")
	ability.release()
	for child: Node in get_children():
		if child is AbilityProjectile:
			child.queue_free()


func _check_hero_punch_alternation() -> void:
	var definition := ItemDB.ability_definition("hero_punch")
	var ability := HeroPunch.new()
	ability.configure(_player, 0, "hero_punch", definition)
	var fired := ability.press()
	var first_clip := _player._ability_clip
	ability.tick(0.0)
	ability.tick(ability.cooldown() + 0.01)
	var second_clip := _player._ability_clip
	ability.tick(0.0)
	ability.tick(ability.cooldown() + 0.01)
	var third_clip := _player._ability_clip
	ability.tick(0.0)
	_expect(fired and ability.is_held(),
		"holding Hero Punch throws each jab automatically")
	_expect(first_clip == String(definition.animation)
		and second_clip == String(definition.alternate_animation)
		and third_clip == String(definition.animation),
		"Hero Punch casts right, left, then right again")
	ability.release()
	var hover := HeroPunch.new()
	hover.configure(_player, 0, "hero_punch", definition)
	_player._apply_stance(OnlinePlayer.Stance.FLY)
	_player._fly_blend = 0.0
	_expect(hover.press(), "Hero Punch jabs while floating")
	_expect(_player._ability_clip == String(definition.hover_animation),
		"a floating Hero Punch still plays the matching jab")
	hover.release()
	_player._fly_blend = 0.0
	_player._apply_stance(OnlinePlayer.Stance.STAND)


func _check_starfire_motion() -> void:
	var definition := ItemDB.ability_definition("starfire")
	var ability := Starfire.new()
	ability.configure(_player, 0, "starfire", definition)
	_player._apply_stance(OnlinePlayer.Stance.FLY)
	_player._fly_blend = 0.0
	var carried := Vector3(7.0, 2.0, -3.0)
	_player.velocity = carried
	_expect(ability.press(), "Starfire throws while floating")
	_expect(_player.animator != null
		and _player.animator.has_animation(definition.hover_animation)
		and _player.animator.has_animation(definition.alternate_hover_animation),
		"the player rig ships both Starfire jab clips")
	var projectile: AbilityProjectile
	for child: Node in get_children():
		if child is AbilityProjectile:
			projectile = child as AbilityProjectile
	_expect(_player._ability_clip == String(definition.hover_animation),
		"a floating throw still plays the matching jab")
	_expect(projectile != null and projectile._velocity.is_equal_approx(
		projectile._along * projectile._speed + carried),
		"Starfire adds the player's velocity to disk launch velocity")
	_expect(projectile != null and is_zero_approx(projectile._disk.rotation.x),
		"the disk leads on its thin rim like a frisbee")
	ability.tick(0.0)
	ability.release()
	_player.velocity = Vector3.ZERO
	_player._fly_blend = 0.0
	_player._apply_stance(OnlinePlayer.Stance.STAND)
	for child: Node in get_children():
		if child is AbilityProjectile:
			child.queue_free()


func _check_starfire_rejection() -> void:
	var definition := ItemDB.ability_definition("starfire")
	var ability := Starfire.new()
	ability.configure(_player, 0, "starfire", definition)
	_expect(ability.press(), "Starfire can wait for projectile approval")
	_player._projectile_result = OnlinePlayer.ProjectileRequestState.REJECTED
	ability.tick(0.0)
	_expect(not ability.is_held() and ability.can_use(),
		"a rejected Starfire cast spends no cooldown")

	_player._ability_clip = ""
	_expect(ability.press(), "Starfire retries immediately after rejection")
	ability.tick(0.0)
	_expect(_player._ability_clip == String(definition.animation),
		"a rejected cast does not advance the alternating hand")
	ability.release()
	for child: Node in get_children():
		if child is AbilityProjectile:
			child.queue_free()


func _check_new_ability_runtime() -> void:
	var nuke_definition := ItemDB.ability_definition("nuke")
	var nuke := Nuke.new()
	nuke.configure(_player, 0, "nuke", nuke_definition)
	_player.velocity = Vector3(4.0, 1.0, -2.0)
	_expect(nuke.press(), "Nuke launches its host-approved hand projectile")
	_expect(_player._ability_clip == "Kame"
			and is_equal_approx(_player._ability_clip_left, 0.28),
		"Nuke snaps the kame pose instead of holding it")
	var orb: AbilityProjectile
	for child: Node in get_children():
		if child is AbilityProjectile \
				and (child as AbilityProjectile).definition == nuke_definition:
			orb = child as AbilityProjectile
	_expect(orb != null and orb._disk.mesh is SphereMesh
		and orb.authoritative,
		"Nuke builds a spherical orb whose offline copy owns impact")
	if orb != null:
		_expect(orb.global_position.distance_to(_player.merged_hand_point()) < 0.05,
			"Nuke leaves from the front of both hands")
	nuke.tick(0.0)
	_player.velocity = Vector3.ZERO
	if orb != null:
		orb.queue_free()

	var mini_definition := ItemDB.ability_definition("mini_nuke")
	var mini_orb := AbilityProjectile.launch(
		self, _player, "mini_nuke",
		Vector3(0.0, 2.0, 0.0), Vector3(0.0, 0.0, -1.0), true)
	_expect(mini_orb != null and mini_definition != null
			and mini_orb._disk.mesh is SphereMesh
			and mini_orb._emits_blast_bubbles()
			and mini_orb._speed > float(nuke_definition.stats.get("speed", 0.0))
			and mini_orb._range > float(nuke_definition.stats.get("range", 0.0)),
		"Mini Nuke builds a faster, longer-flying orb that blooms bubbles from the blast")
	if mini_orb != null:
		mini_orb.queue_free()
	var disk := AbilityProjectile.launch(
		self, _player, "starfire",
		Vector3(0.0, 2.0, 0.0), Vector3(0.0, 0.0, -1.0), true)
	_expect(disk != null and not disk._emits_blast_bubbles(),
		"Starfire still leaves bubbles along its path")
	if disk != null:
		disk.queue_free()
	var bolt := AbilityProjectile.launch(
		self, _player, "light_bolt",
		Vector3(0.0, 2.0, 0.0), Vector3(0.0, 0.0, -1.0), true)
	_expect(bolt != null and bolt._disk is EnergyVfx
			and (bolt._disk as EnergyVfx).kind == EnergyVfx.Kind.PROJECTILE
			and is_equal_approx(bolt._speed, CrawlerRules.LIGHT_BOLT_SPEED)
			and not bolt._emits_blast_bubbles(),
		"Light Bolt builds a small pulsating particle bolt")
	if bolt != null:
		bolt.queue_free()
	var spear := AbilityProjectile.launch(
		self, _player, "icicle",
		Vector3(0.0, 2.0, 0.0), Vector3(0.0, 0.0, -1.0), true)
	_expect(spear != null and spear._disk.mesh is CylinderMesh
			and spear._halo != null
			and is_equal_approx(spear._speed, CrawlerRules.ICICLE_SPEED)
			and not spear._emits_blast_bubbles(),
		"Icicle builds a sharp flying spear")
	if spear != null:
		spear.queue_free()
	var marker := AbilityProjectile.launch(
		self, _player, "teleport",
		Vector3(0.0, 2.0, 0.0), Vector3(0.0, 0.0, -1.0), true)
	_expect(marker != null and marker._disk is EnergyVfx
			and (marker._disk as EnergyVfx).kind == EnergyVfx.Kind.PROJECTILE
			and marker._persist_trail != null
			and is_equal_approx(marker._speed, CrawlerRules.TELEPORT_SPEED)
			and marker._velocity.y > 0.0
			and not marker._emits_blast_bubbles(),
		"Teleport builds a lofted white marker with a lasting trail")
	if marker != null:
		marker.queue_free()
	var cone := AbilityProjectile.launch(
		self, _player, "fus",
		Vector3(0.0, 2.0, 0.0), Vector3(0.0, 0.0, -1.0), true)
	_expect(cone != null and is_instance_valid(cone._cone_beam)
			and cone._cone_beam.kind == EnergyVfx.Kind.BEAM_STREAMS
			and is_equal_approx(cone._speed, CrawlerRules.FUS_SPEED)
			and not cone._emits_blast_bubbles(),
		"Fus builds a travelling white stream beam")
	if cone != null:
		cone.queue_free()
	var thrown := Teleport.new()
	thrown.configure(_player, 0, "teleport", ItemDB.ability_definition("teleport"))
	_expect(thrown.press() and _player._ability_clip == "NukeThrow",
		"Teleport casts with the overhand throw")
	thrown.release()
	for child: Node in get_children():
		if child is AbilityProjectile \
				and (child as AbilityProjectile).definition != null \
				and (child as AbilityProjectile).definition.ability_id \
					== "teleport":
			child.queue_free()

	var clips := [
		"OverhandThrow", "Throw_Object",
		"Fighting_Idle", "Levitate_Idle",
		"Fighting_Left_Jab", "Fighting_Right_Jab",
		"Two-hand_Blast", "Spell_Simple_Enter",
	]
	var clips_present := _player.animator != null
	for clip: String in clips:
		clips_present = clips_present and _player.animator.has_animation(clip)
	_expect(clips_present,
		"both character exports expose the authored cast and hover clips")

	var barrier := AbilityBarrier.create(
		self, 77, _player.peer_id, Transform3D.IDENTITY,
		Vector3(8.0, 4.0, 0.35), 7.0, 4.0, Color.CORNFLOWER_BLUE)
	_expect(barrier != null and barrier.collision_layer == 1
		and barrier.size().is_equal_approx(Vector3(8.0, 4.0, 0.35)),
		"Wall creates solid layer-one collision at its authored size")
	if barrier != null:
		barrier._process(4.0)
		_expect(barrier._material.albedo_color.a < 0.52
			and barrier.remaining() > 0.0,
			"Wall fades gradually while its lifetime is still active")
		barrier.queue_free()

	var house := AbilityBarrier.create(
		self, 78, _player.peer_id, Transform3D.IDENTITY,
		Vector3(8.0, 4.0, 0.35), 7.0, 4.0, Color.CORNFLOWER_BLUE,
		0.52, {"house": true, "firewall": 14.0})
	_expect(house != null and house.is_house() and house.panel_count() >= 7
			and house.firewall_damage() > 0.0
			and house._burn_areas.size() >= 4
			and house._burn_areas.size() < house.panel_count(),
		"House builds a box with a doorway and burns only the walls")
	if house != null:
		house.queue_free()

	var sliding := AbilityBarrier.create(
		self, 79, _player.peer_id, Transform3D.IDENTITY,
		Vector3(8.0, 4.0, 0.35), 7.0, 4.0, Color.CORNFLOWER_BLUE,
		0.52, {
			"house": true,
			"project_speed": 3.5,
			"project_along": Vector3(0.0, 0.0, -1.0),
		})
	_expect(sliding != null and sliding.is_house()
			and is_equal_approx(sliding.project_speed(), 3.5),
		"House and project can share one barrier")
	if sliding != null:
		sliding.sync_to_physics = false
		var start := sliding.global_position
		sliding._physics_process(1.0)
		_expect(start.distance_to(sliding.global_position) > 3.0,
			"Project slides the wall forward")
		sliding.queue_free()

	var first_warning := AbilityDelayedBlast.create(
		self, _player, ItemDB.ability_definition("nausicaa"),
		Vector3(0.0, 2.0, 0.0), Vector3(0.0, 0.0, -8.0),
		Vector3.UP, 1.0, false)
	var second_warning := AbilityDelayedBlast.create(
		self, _player, ItemDB.ability_definition("nausicaa"),
		Vector3(0.0, 2.0, 0.0), Vector3(1.4, 0.0, -8.0),
		Vector3.UP, 1.0, false)
	_expect(first_warning != null and second_warning != null
		and first_warning._marker.mesh is CylinderMesh
		and first_warning._lamp.light_color \
			== ItemDB.ability_definition("nausicaa").tint,
		"Nausicaä paints replicated blue glow patches instead of a ground line")
	if first_warning != null and second_warning != null:
		first_warning.set_process(false)
		second_warning.set_process(false)
		# The second patch is painted a tenth of a second later. Equal fuses
		# therefore preserve draw order without a separate chain controller.
		first_warning._process(0.1)
		first_warning._process(0.91)
		second_warning._process(0.91)
		_expect(first_warning._detonated and not second_warning._detonated,
			"Nausicaä's first painted patch detonates first after one second")
		second_warning._process(0.1)
		_expect(second_warning._detonated,
			"Nausicaä's detonation then advances along the painted trail")

	var beams := _player.laser_beams()
	beams.aim(Vector3(-0.05, 1.8, 0.0), Vector3(0.05, 1.8, 0.0),
		Vector3(0.0, 0.0, -8.0), EnergyVfx.TINT_PURPLE)
	var drawn: EnergyVfx = null
	if not beams._beams.is_empty() and not beams._beams[0].is_empty():
		drawn = beams._beams[0][0] as EnergyVfx
	_expect(beams._colour == EnergyVfx.TINT_PURPLE
		and drawn != null
		and drawn.current_tint() == EnergyVfx.TINT_PURPLE,
		"Nausicaä reuses the Laser Eyes beams with a purple glow")
	beams.stop()

	var player_target := PLAYER.instantiate() as OnlinePlayer
	player_target.peer_id = 2
	player_target.defer_camera = true
	add_child(player_target)
	player_target.set_process(false)
	player_target.set_physics_process(false)

	var ally_health := player_target.health()
	var caster_health := _player.health()
	_player.global_position = Vector3.ZERO
	player_target.global_position = Vector3.ZERO
	AbilityImpact.apply(
		_player,
		ItemDB.ability_definition("nuke"),
		_player.combat_position(),
		Vector3.UP,
		{"player_damage": 12.0, "self_launch_speed": 0.0}
	)
	_expect(_player.health() < caster_health,
		"Nuke explosion damages its caster")
	_expect(is_equal_approx(player_target.health(), ally_health),
		"Nuke explosion does not damage other coop players")
	_player.stats.set_health(_player.maximum_health())
	_player._clear_ragdoll()
	_player.velocity = Vector3.ZERO
	player_target._clear_ragdoll()
	player_target.stats.set_health(player_target.maximum_health())

	var disk_health := _player.health()
	AbilityImpact.apply(
		_player,
		ItemDB.ability_definition("starfire"),
		_player.combat_position(),
		Vector3.UP,
		{"player_damage": 8.0}
	)
	_expect(_player.health() < disk_health,
		"Starfire explosion damages its caster")
	_player.stats.set_health(_player.maximum_health())
	_player.velocity = Vector3.ZERO

	_player.global_position = Vector3.ZERO
	player_target.global_position = Vector3(4.0, 0.0, 0.0)
	var blocker := StaticBody3D.new()
	blocker.collision_layer = 1
	var blocker_shape := CollisionShape3D.new()
	var blocker_box := BoxShape3D.new()
	blocker_box.size = Vector3(0.25, 3.0, 3.0)
	blocker_shape.shape = blocker_box
	blocker.add_child(blocker_shape)
	add_child(blocker)
	blocker.global_position = Vector3(
		2.0, player_target.combat_position().y, 0.0)
	await get_tree().physics_frame
	var occluded := DamageHit.area(
		_player.combat_position(), 10.0, 1.0, 1.0)
	occluded.blocked_by_world = true
	_expect(occluded._world_blocks(_player, _player, player_target),
		"opt-in blast damage is stopped by layer-one Wall geometry")
	blocker.queue_free()
	player_target.queue_free()


## A blast that launches its caster has to take the caster's body with it. The
## camera, the eye line and the position peers are told about all hang off the
## capsule and not off the bones, so a launch the bones are not allowed to match
## is a view that flies up on its own while the character stays where it stood.
func _check_blast_self_launch() -> void:
	var ragdoll := _player._ragdoll
	if ragdoll == null or not ragdoll.built():
		_expect(false, "the test body has a ragdoll to launch")
		return
	_player.global_position = Vector3.ZERO
	var up := _player.global_basis.y.normalized()
	# Nuke's authored `self_launch_speed`, which is well past the ceiling the
	# ragdoll holds a body to once it is merely falling.
	var launch := up * 68.0
	_player.velocity = Vector3.ZERO
	_player._force_full_ragdoll_local(launch, 0.5)
	_expect(ragdoll.limp() and _player.velocity.is_equal_approx(launch),
		"a self-launch hands the capsule and the bones the same velocity")
	await get_tree().physics_frame
	_expect(ragdoll.drift().dot(up) > Ragdoll.MAX_SPEED,
		"limp bones keep an authored launch past their own safety ceiling")

	# Half a second of the arc, with the capsule driven the way its own physics
	# step would drive it. The bones shed some of the launch to their damping and
	# gain some off the ground they left; either way the capsule goes where they
	# go, because everything the player sees and aims with hangs off it.
	var from := _player.global_position
	var body_from := ragdoll.centre()
	for _frame in 30:
		await get_tree().physics_frame
		_player._crash_move(get_physics_process_delta_time())
	var capsule_climb := (_player.global_position - from).dot(up)
	var body_climb := (ragdoll.centre() - body_from).dot(up)
	# Left to its own gravity the capsule would be some thirty metres up by here,
	# which is the whole of the fault: it is the camera, and the body is not.
	_expect(body_climb > 1.0 and absf(capsule_climb - body_climb) < 1.0,
		"the crash capsule climbs with the launched body and not past it")
	_player._clear_ragdoll()
	_player.velocity = Vector3.ZERO
	_player.global_position = Vector3.ZERO


## The staged detonation. A nuclear burst is not one shell that swells and stops:
## it flashes, throws two fronts out along the ground, and stands a cloud up for
## several times as long as the fireball it came out of.
func _check_blast_presentation() -> void:
	var nuke := ItemDB.ability_definition("nuke")
	var radius := float(nuke.stats.get("radius", 0.0))
	_expect(radius <= EnergyExplosion.MAX_RADIUS,
		"the authored nuke fireball fits inside what the wire will carry (%.0f m)"
			% radius)

	var small := EnergyExplosion.burst(
		self, Vector3.ZERO, 4.0, Color.ORANGE, 0.3, false)
	var massive := EnergyExplosion.burst(
		self, Vector3.ZERO, 16.0, Color.CYAN, 0.9, true, false)
	var big := EnergyExplosion.burst(
		self, Vector3.ZERO, radius, nuke.tint,
		float(nuke.stats.get("explosion_duration", 0.8)), true, true)
	_expect(small != null and big != null
		and big.span() > small.span() * 4.0,
		"a nuclear burst outlasts its own fireball and a small one does not")
	_expect(massive != null and is_equal_approx(massive.span(), 0.9),
		"a massive non-nuclear blast keeps its brighter shell without the cloud")

	await get_tree().process_frame
	await get_tree().process_frame
	var rings := 0
	var clouds := 0
	var flashes := 0
	for child: Node in big.get_children():
		if not (child is Node3D and (child as Node3D).top_level):
			continue
		if child is MeshInstance3D:
			flashes += 1
		for piece: Node in child.get_children():
			var shape := piece as MeshInstance3D
			if shape == null:
				continue
			if shape.mesh is TorusMesh:
				rings += 1
			else:
				clouds += 1
	_expect(flashes == 1 and rings == 2 and clouds >= 3,
		"it builds a flash, two fronts, and a cloud (%d/%d/%d)"
			% [flashes, rings, clouds])
	# Both stand outside the fireball's own transform, which opens from a twelfth
	# of full size: parented under it they would be multiplied by it.
	_expect(big.scale.length() < radius,
		"and the fireball is still opening while they run")

	# The screen goes with it for anyone standing inside. Local only and nothing
	# is sent — every peer already has the blast, so every peer's own distance to
	# it is enough.
	var feedback := CombatFeedback.new()
	add_child(feedback)
	feedback.configure(null, null)
	_expect(is_zero_approx(feedback.blast_flash_remaining()),
		"a view outside a blast is left alone")
	feedback.blast_flash(0.8)
	_expect(feedback.blast_flash_remaining()
		> CombatFeedback.BLAST_FLASH_TIME * 0.9,
		"and one inside it is turned inside out for about a second")
	feedback.queue_free()
	small.queue_free()
	massive.queue_free()
	big.queue_free()


func _check_training_dummy() -> void:
	var packed := load(
		"res://game/enemies/training_dummy.tscn") as PackedScene
	var dummy := packed.instantiate() as TrainingDummy
	add_child(dummy)
	dummy.set_physics_process(false)
	_expect(not dummy.anchor_path.is_empty()
		and is_finite(dummy.anchor_right_offset)
		and is_finite(dummy.anchor_forward_offset),
		"the training dummy can settle beside an authored surface anchor")
	var carried_to := Vector3(3.0, 8.0, -2.0)
	_expect(dummy.begin_grapple(_player),
		"the training dummy accepts a grapple while alive")
	dummy.grapple_follow(carried_to, Vector3.UP)
	_expect(dummy.global_position.is_equal_approx(carried_to - Vector3.UP),
		"the training dummy follows the carry socket")
	dummy.end_grapple(Vector3(2.0, 0.0, 1.0), Vector3.UP)
	_expect(dummy.can_be_grappled(),
		"ending a carry releases the training dummy")
	_expect(dummy.begin_lasso(_player) and dummy.is_lassoed(),
		"the training dummy accepts a physical Lasso")
	dummy.end_lasso(Vector3(12.0, 4.0, 0.0))
	_expect(dummy.can_be_lassoed() and dummy.velocity.length() > 10.0,
		"Lasso release restores the dummy and preserves throw velocity")

	var radial := DamageHit.area(
		dummy.combat_position() - Vector3.RIGHT * 2.0, 10.0, 100.0, 1.0)
	radial.radial_impulse = 20.0
	radial.radial_lift = 5.0
	var resolved := radial.resolved_for(dummy)
	_expect(resolved.world_impulse.x > 0.0
		and resolved.world_impulse.y > 0.0,
		"host-authored radial reactions resolve outward impulse and lift")

	var hit := DamageHit.area(dummy.combat_position(), 2.0,
		dummy.maximum_health, 0.0)
	hit.faction = DamageHit.Faction.PLAYER
	_expect(is_equal_approx(dummy.apply_damage(hit), dummy.maximum_health)
		and not dummy.can_be_grappled(),
		"the training dummy takes lethal ability damage")
	dummy._physics_process(dummy.respawn_delay + 0.01)
	_expect(dummy.can_be_grappled()
		and is_equal_approx(dummy.health(), dummy.maximum_health),
		"the training dummy respawns at full health")
	dummy.queue_free()


func _check_cooldown() -> void:
	var ability := GatedAbility.new()
	ability.configure(_player, 0, "laser_eyes", {"cooldown": 2.0})
	_expect(ability.can_use(), "a fresh ability is ready")
	_expect(ability.press(), "pressing starts it")
	_expect(ability.is_held(), "and it stays held until released")
	ability.release()
	_expect(not ability.can_use(), "it is not ready again immediately")
	_expect(is_equal_approx(ability.cooldown_left(), 2.0),
		"releasing charges the whole cooldown")
	_expect(not ability.press(), "and pressing it again does nothing")
	ability.tick(1.5)
	_expect(not ability.can_use(), "it is still cooling down part way through")
	ability.tick(0.6)
	_expect(ability.can_use(), "it is ready once the cooldown runs out")


func _check_gating() -> void:
	var wet := GatedAbility.new()
	wet.configure(_player, 0, "laser_eyes", {})
	_player._lava_state = {"depth": 0.6}
	_expect(_player.submerged_share() > 0.0, "the body reads as submerged")
	_expect(not wet.can_use(), "an underwater ability refuses to start")
	_expect(not wet.press(), "and pressing it does nothing")
	_player._lava_state = {}
	_expect(wet.can_use(), "it works again out of the water")

	var grounded := GroundAbility.new()
	grounded.configure(_player, 1, "meteor_punch", {})
	_player._apply_stance(OnlinePlayer.Stance.SWIM)
	_expect(not grounded.can_use(), "a stance-gated ability refuses a swim")
	_player._apply_stance(OnlinePlayer.Stance.FLY)
	_expect(grounded.can_use(), "and allows a flight")
	# Cancelling rather than releasing is the path a player leaving the world
	# takes, and it must not leave a cooldown behind on an ability nobody owns.
	grounded.press()
	grounded.cancel()
	_expect(is_equal_approx(grounded.cooldown_left(), 0.0),
		"cancelling charges no cooldown")
	_player._apply_stance(OnlinePlayer.Stance.STAND)


## The slot plumbing: filling an ability slot builds the right ability, and the
## mouse button reaches it.
func _check_controller() -> void:
	var controller := _player.ability_controller()
	_expect(controller != null, "a local player has an ability controller")
	if controller == null:
		return
	_player.abilities.set_item(0, "laser_eyes")
	_expect(controller.ability_in(0) is LaserEyes,
		"filling a slot builds that ability")
	_player.abilities.set_item(1, "meteor_punch")
	_expect(controller.ability_in(1) is MeteorPunch,
		"the second slot builds its own")
	_player.abilities.set_item(0, "")
	_expect(controller.ability_in(0) == null,
		"emptying a slot takes the ability away")
	_expect(controller.ability_in(1) is MeteorPunch,
		"and leaves the other slot alone")
	_player.abilities.clear()


func _expect(condition: bool, message: String) -> void:
	if condition:
		print("ability_model_test: PASS  %s" % message)
		return
	_failures += 1
	push_error("ability_model_test: FAIL  %s" % message)
