@tool
class_name FaunaSpecies
extends Resource

## One data-driven land-creature variant.
##
## The habitat and appearance vocabulary deliberately mirrors PlantSpecies:
## both populations use the same terrain claims, climate bands, authored size,
## health/toughness scale, deterministic seeds, external color paint, and local
## night-light rules. Fauna adds temperament and a move set because each live
## instance is a host-authoritative actor rather than a MultiMesh transform.

enum Disposition {
	FRIENDLY,
	PASSIVE,
	HOSTILE,
}

enum Locomotion {
	WALKER,
	## Rolls continuously on the body's rounded side, like a wheel.
	ROLLER,
	## Travels along its long axis by transferring from one end to the other.
	END_OVER_END,
}

enum AttackStyle {
	NONE,
	CONTACT,
	BODY_SLAP,
	## Spits a short-lived ball of liquid at whoever provoked it.
	SPIT,
}

enum Move {
	WALK = 1,
	RUN = 2,
	ATTACK = 4,
}

@export_category("Identity")
## Stable wire/catalogue key. Changing it changes deterministic spawn IDs.
@export var species_id := ""
@export var display_name := "Alien Creature"
## Disabled species stay in the generated catalogue but create no populations.
@export var enabled := true
@export var disposition: Disposition = Disposition.PASSIVE
@export_flags("Walk", "Run", "Attack") var move_set: int = Move.WALK
@export var locomotion: Locomotion = Locomotion.WALKER
@export var attack_style: AttackStyle = AttackStyle.NONE

@export_category("Appearance")
@export var model: PackedScene
## Runtime PNG sampled through the model's TEXCOORD_0. COLOR_0 remains available
## for broad semantic part colors and the PNG alpha is the night-emission mask.
@export var paint_texture: Texture2D
@export var paint_style := ""
@export var material: ShaderMaterial
@export var height := 1.0
@export_range(0.0, 0.6) var height_variation := 0.12
## Mild per-creature multipliers keep a population varied without replacing the
## authored color-paint pattern.
@export var variant_tint_a := Color.WHITE
@export var variant_tint_b := Color.WHITE
@export_range(0.0, 2.0) var saturation := 1.25
@export_range(0.0, 2.0) var brightness := 1.08
@export var terrain_tint := true
@export_range(0.0, 1.0) var biome_tint_strength := 0.18

@export_group("Night glow")
@export var glow_night_only := true
@export var night_emission_color := Color(0.2, 0.9, 1.0)
@export_range(0.0, 8.0) var night_emission_energy := 1.4
@export_range(0.0, 1.0) var night_emission_albedo := 0.45
@export_range(0.0, 0.5) var night_pulse_amount := 0.12
@export_range(0.0, 2.0) var night_pulse_speed := 0.3
## A bounded pool on FaunaSpawner casts this shader glow onto nearby ground.
@export var local_light_color := Color(0.2, 0.9, 1.0)
@export_range(0.0, 8.0) var local_light_energy := 1.4
@export_range(0.0, 40.0) var local_light_range := 8.0
@export_range(0.0, 3.0) var local_light_height_share := 0.55

@export_category("Size and collision")
@export_range(0.05, 1.5) var collision_radius_share := 0.38
@export_range(0.1, 1.0) var collision_height_share := 0.82
@export_range(0.0, 1.0) var combat_radius_share := 0.46

@export_category("Habitat")
@export var ground_layer: PlantSpecies.Ground = PlantSpecies.Ground.ANYWHERE
@export_range(0.0, 1.0) var minimum_ground_claim := 0.0
@export var above_water := 5.0
@export var below := 420.0
@export_range(0.0, 1.0) var minimum_arid := 0.0
@export_range(0.0, 1.0) var maximum_arid := 1.0
@export_range(0.0, 1.0) var minimum_frost := 0.0
@export_range(0.0, 1.0) var maximum_frost := 1.0
@export_range(0.0, 60.0) var max_slope := 24.0
## The worst height change allowed across this many metres.
@export_range(0.0, 30.0) var steady_over := 2.0
@export_range(0.0, 20.0) var steady_within := 1.0
@export var avoid_inland_water := true

@export_category("Distribution")
@export var global_population := true
## Stable cube-sphere cell width and chance that a suitable cell has a pack.
@export_range(8.0, 500.0, 1.0, "or_greater") var cell_size := 70.0
@export_range(0.0, 1.0) var spawn_chance := 0.3
@export_range(1, 12) var pack_min := 1
@export_range(1, 12) var pack_max := 3
@export_range(0.0, 30.0) var pack_radius := 4.0
@export_range(0, 128) var maximum_instances := 14
@export_range(10.0, 2000.0) var spawn_within := 220.0
@export_range(10.0, 3000.0) var despawn_beyond := 285.0
@export var random_seed := 20260813
## Guaranteed showcase population around Vacationer's Landing. It still requires dry,
## walkable ground but deliberately ignores biome tint bands at this one site.
@export_range(0, 32) var colony_count := 0
@export_range(0.0, 500.0) var colony_near := 28.0
@export_range(0.0, 800.0) var colony_far := 80.0

@export_category("Vitality")
@export var health := 100.0
@export var health_per_metre := 18.0
@export var toughness: PlantSpecies.Toughness = PlantSpecies.Toughness.SOFT
@export_range(0.0, 120.0) var respawn_delay := 14.0

@export_category("Movement")
@export_range(0.0, 30.0) var walk_speed := 1.8
@export_range(0.0, 60.0) var run_speed := 5.5
@export_range(0.0, 80.0) var move_acceleration := 18.0
@export_range(0.0, 20.0) var turn_speed := 7.0
@export_range(0.0, 100.0) var wander_radius := 18.0
@export_range(0.0, 30.0) var wander_pause := 2.0
@export_range(0.0, 100.0) var notice_range := 18.0
@export_range(0.0, 100.0) var flee_range := 7.0
## How near a player a creature must be to walk as a physics body, sweeping its
## capsule against the world and being blocked by what it meets.
##
## Beyond this it walks the height field directly instead. Nobody is close enough
## to watch it brush past a boulder, and a swept capsule query against a distant
## terrain chunk — coarse, and rebuilt whenever the level of detail changes under
## it — costs tens of milliseconds, which is the most expensive thing a creature
## can do to a frame. Zero keeps every creature a physics body.
@export_range(0.0, 400.0) var physics_within := 45.0

@export_group("Idling and temperament")
## Grazing creatures spend some of their wander pauses with their head down
## instead of standing still, which is what makes a herd read as feeding.
@export var graze := false
@export_range(0.0, 1.0) var graze_chance := 0.55
@export_range(0.0, 30.0) var graze_seconds := 4.0
## Flees in bounding leaps rather than a flat run, for animals whose escape is a
## series of hops. Requires a bound clip in the model.
@export var bound_when_fleeing := false
## How long a creature that is not otherwise hostile fights back after being
## hurt. Zero leaves it purely defenceless, fleeing and nothing more.
@export_range(0.0, 120.0) var provoked_seconds := 0.0
## While provoked, the ring it tries to hold around whoever hurt it, and how
## fast it circles. Keeping its distance while it attacks is the whole point.
@export_range(0.0, 60.0) var strafe_radius := 7.0
@export_range(0.0, 30.0) var strafe_speed := 4.0

@export_group("Procedural gait")
## Uses COLOR_0 as a semantic leg mask while preserving one runtime mesh.
@export var quadruped_gait := false
@export var leg_mask_color := Color(0.09, 0.14, 0.23)
@export_range(0.01, 1.0) var leg_mask_tolerance := 0.16
@export_range(0.1, 3.0) var gait_stride_share := 0.9
@export_range(0.0, 0.5) var gait_swing_share := 0.13
@export_range(0.0, 0.3) var gait_lift_share := 0.055
@export_range(0.1, 0.8) var gait_leg_top_share := 0.42
@export_range(0.0, 30.0) var body_rock_degrees := 0.0
@export_range(0.0, 0.2) var body_bob_share := 0.025

@export_category("Skeletal animation")
## Plays clips baked into the model's GLB instead of the procedural pivot gait.
## The two presentations are exclusive: a rigged creature must not also have its
## vertices displaced by the shader gait, which knows nothing of the skeleton.
@export var skeletal_clips := false
@export var clip_idle := "Idle"
@export var clip_walk := "Walk"
@export var clip_run := "Run"
@export var clip_graze := "Graze"
@export var clip_bound := "Bound"
@export var clip_strafe := "Strafe"
@export var clip_attack := "Spit"
@export var clip_hit := "HitReact"
@export var clip_dead := "Defeat"
## Cadence trim, applied on top of matching playback rate to ground speed. It
## exists so a stride can be tuned against the terrain without a rebake.
@export_range(0.1, 4.0) var clip_speed_scale := 1.0
@export_range(0.0, 1.0) var clip_blend := 0.16

@export_category("Attack")
@export_range(0.0, 1000.0) var attack_damage := 10.0
@export_range(0.0, 20.0) var attack_range := 1.2
@export_range(0.0, 20.0) var attack_radius := 0.8
@export_range(0.0, 10.0) var attack_windup := 0.28
@export_range(0.05, 20.0) var attack_cooldown := 1.2
@export_range(0.0, 100.0) var attack_knockback := 5.0
@export var attack_parryable := false

@export_group("Spit")
## Where the ball leaves the animal, as shares of body height: up from the feet
## and forward from the centre, which together put it at the muzzle.
@export_range(0.0, 1.5) var spit_from_height_share := 0.80
@export_range(0.0, 1.5) var spit_from_forward_share := 0.62
@export_range(1.0, 80.0) var spit_speed := 17.0
## Deliberately far lighter than world gravity. A wet ball thrown by an animal
## should carry to its target on a shallow arc, not lob like a mortar shell.
@export_range(0.0, 40.0) var spit_gravity := 9.0
@export_range(0.02, 2.0) var spit_ball_radius := 0.13
## Sweep radius for the hit test, which is wider than the ball so being clipped
## by one reads as being hit rather than as a near miss.
@export_range(0.05, 4.0) var spit_hit_radius := 0.62
@export var spit_color := Color(0.58, 0.93, 1.0)
@export_range(0.0, 8.0) var spit_glow := 1.8

var _template_material: ShaderMaterial
var _template_mesh: Mesh
var _prepared := false


## Builds the one material every creature of this species copies, the way
## PlantSpecies prepares a field's material once instead of once per plant.
##
## Nothing here is deep-duplicated. A deep copy would clone the Shader and the
## paint texture as well as the uniforms, which hands every creature a private
## shader for the renderer to compile and a private texture to upload the first
## frame it is drawn — a several-hundred-millisecond stall per arrival, on a
## population that streams in and out as the player walks.
func prepare() -> void:
	if _prepared:
		return
	_prepared = true
	_template_mesh = _first_mesh()
	if material == null:
		return
	_template_material = material.duplicate(false) as ShaderMaterial
	var runtime := _template_material
	runtime.set_shader_parameter(&"base_texture", paint_texture)
	runtime.set_shader_parameter(&"use_vertex_color", true)
	runtime.set_shader_parameter(&"saturation", saturation)
	runtime.set_shader_parameter(&"region_albedo",
		biome_tint_strength if terrain_tint else 0.0)
	runtime.set_shader_parameter(&"night_emission_color", Vector3(
		night_emission_color.r,
		night_emission_color.g,
		night_emission_color.b))
	runtime.set_shader_parameter(
		&"night_emission_energy", night_emission_energy)
	runtime.set_shader_parameter(&"night_emission_from_texture_alpha", true)
	runtime.set_shader_parameter(&"night_emission_albedo", night_emission_albedo)
	runtime.set_shader_parameter(&"night_pulse_amount", night_pulse_amount)
	runtime.set_shader_parameter(&"night_pulse_speed", night_pulse_speed)
	runtime.set_shader_parameter(&"quadruped_gait", quadruped_gait)
	runtime.set_shader_parameter(&"gait_leg_mask_color", Vector3(
		leg_mask_color.r, leg_mask_color.g, leg_mask_color.b))
	runtime.set_shader_parameter(&"gait_leg_mask_tolerance", leg_mask_tolerance)
	runtime.set_shader_parameter(&"gait_authored_height", height)
	runtime.set_shader_parameter(&"gait_leg_top_share", gait_leg_top_share)
	runtime.set_shader_parameter(&"gait_swing", height * gait_swing_share)
	runtime.set_shader_parameter(&"gait_lift", height * gait_lift_share)


## The species template, for pre-compiling this creature's draw before one exists.
func template_material() -> ShaderMaterial:
	prepare()
	return _template_material


## This creature's body mesh, read out of the model scene once. WorldWarmup needs
## it because no creature exists to be found in the tree at the title screen.
func template_mesh() -> Mesh:
	prepare()
	return _template_mesh


func _first_mesh() -> Mesh:
	if model == null:
		return null
	var probe := model.instantiate()
	var mesh: Mesh = null
	for node_variant: Variant in probe.find_children(
			"*", "MeshInstance3D", true, false):
		var mesh_instance := node_variant as MeshInstance3D
		if mesh_instance != null and mesh_instance.mesh != null:
			mesh = mesh_instance.mesh
			break
	probe.free()
	return mesh


## One creature's material. Shallow again: only the uniforms that vary per
## creature — its tint, its brightness, and its gait — are written here.
func instance_material(tint: Color, brightness: float) -> ShaderMaterial:
	var template := template_material()
	if template == null:
		return null
	var runtime := template.duplicate(false) as ShaderMaterial
	runtime.set_shader_parameter(&"base_color",
		Vector3(tint.r, tint.g, tint.b))
	runtime.set_shader_parameter(&"brightness", brightness)
	runtime.set_shader_parameter(&"gait_phase", 0.0)
	runtime.set_shader_parameter(&"gait_amount", 0.0)
	return runtime


func has_move(move: Move) -> bool:
	return (move_set & int(move)) != 0


func is_hostile() -> bool:
	return disposition == Disposition.HOSTILE


func is_passive() -> bool:
	return disposition == Disposition.PASSIVE


func health_for(instance_height: float) -> float:
	return maxf(health, 0.0) \
		+ maxf(instance_height, 0.0) * maxf(health_per_metre, 0.0)


## Reuses flora's authored toughness exchange rate so the same player ability has
## one understandable damage scale against wood, stone, plants, and creatures.
func damage_taken(raw: float) -> float:
	var index := clampi(int(toughness), 0, PlantSpecies.TOUGHNESS_SHARE.size() - 1)
	return maxf(raw, 0.0) * PlantSpecies.TOUGHNESS_SHARE[index]


func validate() -> PackedStringArray:
	var problems := PackedStringArray()
	if species_id.is_empty():
		problems.append("species_id is empty")
	if model == null:
		problems.append("%s has no model" % species_id)
	if paint_texture == null:
		problems.append("%s has no runtime color-paint PNG" % species_id)
	if material == null:
		problems.append("%s has no runtime material" % species_id)
	if height <= 0.0:
		problems.append("%s has non-positive height" % species_id)
	if pack_min > pack_max:
		problems.append("%s pack_min exceeds pack_max" % species_id)
	if global_population and maximum_instances > 0 \
			and despawn_beyond <= spawn_within:
		problems.append("%s despawn_beyond must exceed spawn_within" % species_id)
	if attack_style != AttackStyle.NONE and not has_move(Move.ATTACK):
		problems.append("%s has an attack style but no Attack move" % species_id)
	if skeletal_clips and quadruped_gait:
		problems.append(
			"%s cannot both play clips and be posed by the shader" % species_id)
	if provoked_seconds > 0.0 and attack_style == AttackStyle.NONE:
		problems.append(
			"%s fights back when provoked but has no attack" % species_id)
	if bound_when_fleeing and not has_move(Move.RUN):
		problems.append("%s bounds when fleeing but cannot run" % species_id)
	return problems
