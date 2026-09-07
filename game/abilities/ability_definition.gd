class_name AbilityDefinition
extends Resource

## Authored, data-only description of one player ability.
##
## These resources are generated from the ability manifest, in the same spirit
## as PlantSpecies resources: the catalogue and UI can inspect the complete
## ability without instantiating its runtime behaviour. Ability subclasses own
## timing and decisions; this resource owns identity, presentation, dispatch
## types, animation names, and tunable numbers.

enum ActivationType {
	INSTANT,
	SUSTAINED,
	COMMITTED,
}

enum ProjectileType {
	NONE,
	BEAM,
	SELF,
	ENERGY_DISK,
	ENERGY_ORB,
	TETHER,
	ENERGY_BOLT,
	ENERGY_ICICLE,
	TELEPORT_ORB,
	ENERGY_CONE,
}

enum ImpactType {
	NONE,
	BURN,
	METEOR_CRATER,
	EXPLOSION_CRATER,
	GRAPPLE_SLAM,
	MASSIVE_BLAST,
	DELAYED_BLAST,
	FROST_BURST,
	TELEPORT,
	KNOCKBACK_BURST,
}

enum GrappleType {
	NONE,
	CARRY_SLAM,
	PHYSICS_TETHER,
}

enum ConstructType {
	NONE,
	BARRIER,
}

enum ReactionType {
	NONE,
	STAGGER,
	KNOCKBACK,
	RAGDOLL,
}

@export var ability_id := ""
@export var title := ""
@export_multiline var description := ""
@export var implementation: Script
@export var icon: Texture2D
@export var tint := Color(0.6, 0.6, 0.6)

@export var activation_type := ActivationType.INSTANT
@export var projectile_type := ProjectileType.NONE
@export var impact_type := ImpactType.NONE
@export var grapple_type := GrappleType.NONE
@export var construct_type := ConstructType.NONE
@export var reaction_type := ReactionType.NONE
## High-consequence flags remain data-authored, but are only trusted after the
## host has resolved the cast against this definition.
@export var affects_players := false
@export var self_launch := false
@export var blast_occlusion := false

## Primary, alternating-hand, low-speed hover variants, held variants, and
## landing clips respectively. Empty names intentionally mean ordinary
## locomotion remains in control or that the corresponding primary clip is the
## fallback.
@export var animation := &""
@export var alternate_animation := &""
@export var hover_animation := &""
@export var alternate_hover_animation := &""
@export var held_animation := &""
@export var held_hover_animation := &""
@export var impact_animation := &""

@export var blocked_underwater := false
## OnlinePlayer.Stance integer values. An empty list allows every stance.
@export var allowed_stances := PackedInt32Array()
@export var stats: Dictionary = {}


func valid() -> bool:
	return not ability_id.is_empty() and implementation != null


func profile_line() -> String:
	var parts := PackedStringArray()
	parts.append(_enum_label(ActivationType, activation_type))
	if projectile_type != ProjectileType.NONE:
		parts.append(_enum_label(ProjectileType, projectile_type))
	if impact_type != ImpactType.NONE:
		parts.append(_enum_label(ImpactType, impact_type))
	if grapple_type != GrappleType.NONE:
		parts.append(_enum_label(GrappleType, grapple_type))
	if construct_type != ConstructType.NONE:
		parts.append(_enum_label(ConstructType, construct_type))
	if reaction_type != ReactionType.NONE:
		parts.append(_enum_label(ReactionType, reaction_type))
	return "  //  ".join(parts)


static func _enum_label(values: Dictionary, value: int) -> String:
	for key: Variant in values:
		if int(values[key]) == value:
			return String(key).replace("_", " ")
	return "UNKNOWN"
