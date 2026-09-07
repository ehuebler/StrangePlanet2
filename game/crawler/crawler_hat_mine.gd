class_name CrawlerHatMine
extends Node3D

## Ground mine dropped by the Trail Cap. Every peer sees the fuse; only the
## host turns the burst into damage.

const GROUP := &"crawler_hat_mines"
const CORE_COLOR := Color(1.00, 0.46, 0.14)
const GLOW_COLOR := Color(1.00, 0.28, 0.06)
const HALO_COLOR := Color(1.00, 0.62, 0.18, 0.42)
const PULSE_HZ := 6.4

var shooter: OnlinePlayer
var damage := 0.0
var blast_radius := 3.4
var fuse := 1.0
var size := 0.22
var authoritative := false

var _age := 0.0
var _core: MeshInstance3D
var _halo: MeshInstance3D
var _spent := false


static func drop(world: Node, source: OnlinePlayer, at: Vector3,
		recipe: Dictionary, owns_hit := true) -> CrawlerHatMine:
	if world == null or source == null or not at.is_finite():
		return null
	var mine := CrawlerHatMine.new()
	mine.shooter = source
	mine.damage = maxf(float(recipe.get("damage", CrawlerRules.MINE_HAT_DAMAGE)), 0.0)
	mine.blast_radius = maxf(
		float(recipe.get("radius", CrawlerRules.MINE_HAT_RADIUS)), 0.4)
	mine.fuse = maxf(float(recipe.get("fuse", CrawlerRules.MINE_HAT_FUSE)), 0.15)
	mine.size = maxf(float(recipe.get("size", CrawlerRules.MINE_HAT_SIZE)), 0.08)
	mine.authoritative = owns_hit
	world.add_child(mine)
	mine.global_position = at
	mine._sit(at)
	return mine


func _ready() -> void:
	name = "CrawlerHatMine"
	add_to_group(GROUP)
	var radius := size
	var body := SphereMesh.new()
	body.radius = radius
	body.height = radius * 2.0
	body.radial_segments = 14
	body.rings = 8
	_core = MeshInstance3D.new()
	_core.mesh = body
	var material := StandardMaterial3D.new()
	material.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	material.albedo_color = CORE_COLOR
	material.emission_enabled = true
	material.emission = GLOW_COLOR
	material.emission_energy_multiplier = 6.4
	_core.material_override = material
	_core.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	add_child(_core)
	var halo_mesh := SphereMesh.new()
	halo_mesh.radius = radius * 1.85
	halo_mesh.height = radius * 3.7
	halo_mesh.radial_segments = 14
	halo_mesh.rings = 8
	_halo = MeshInstance3D.new()
	_halo.mesh = halo_mesh
	var halo_material := StandardMaterial3D.new()
	halo_material.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	halo_material.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	halo_material.blend_mode = BaseMaterial3D.BLEND_MODE_ADD
	halo_material.cull_mode = BaseMaterial3D.CULL_DISABLED
	halo_material.albedo_color = HALO_COLOR
	halo_material.emission_enabled = true
	halo_material.emission = GLOW_COLOR
	halo_material.emission_energy_multiplier = 3.8
	_halo.material_override = halo_material
	_halo.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	add_child(_halo)
	var lamp := OmniLight3D.new()
	lamp.light_color = GLOW_COLOR
	lamp.light_energy = 2.8
	lamp.omni_range = maxf(radius * 12.0, 2.4)
	lamp.shadow_enabled = false
	add_child(lamp)


func _physics_process(delta: float) -> void:
	if _spent:
		return
	_age += delta
	var left := maxf(fuse - _age, 0.0)
	var hurry := 1.0 + (1.0 - clampf(left / maxf(fuse, 0.01), 0.0, 1.0)) * 2.4
	var wave := 0.72 + 0.28 * (0.5 + 0.5 * sin(_age * TAU * PULSE_HZ * hurry))
	if is_instance_valid(_core):
		_core.scale = Vector3.ONE * wave
	if is_instance_valid(_halo):
		_halo.scale = Vector3.ONE * (0.86 + (1.0 - wave) * 0.4)
	if _age < fuse:
		return
	_burst()


func _burst() -> void:
	if _spent:
		return
	_spent = true
	var at := global_position
	if authoritative:
		_hurt(at)
	EnergyExplosion.burst(get_parent(), at, maxf(blast_radius * 0.55, 0.8),
		GLOW_COLOR, 0.28)
	queue_free()


func _hurt(at: Vector3) -> void:
	if not is_inside_tree() or not is_instance_valid(shooter):
		return
	var hit := DamageHit.area(at, blast_radius, damage, 1.0)
	hit.ability_id = "hat_mine"
	hit.affects_flora = false
	hit.explosive = true
	hit.faction = DamageHit.Faction.PLAYER
	hit.set_source(shooter, shooter.peer_id)
	for node_variant: Variant in get_tree().get_nodes_in_group(DamageHit.COMBATANT_GROUP):
		var node := node_variant as Node
		if node == null or node == shooter or not hit.affects_combatant(node):
			continue
		var delivered := hit.resolved_for(node)
		var result: Variant = node.call(&"apply_damage", delivered)
		var dealt := float(result) if result is float or result is int else 0.0
		if dealt > 0.0 and shooter.has_method(&"combat_damage_dealt"):
			shooter.call(&"combat_damage_dealt", node, dealt, delivered)


func _sit(at: Vector3) -> void:
	var up := at.normalized() if at.length_squared() > 0.01 else Vector3.UP
	var right := up.cross(Vector3.FORWARD)
	if right.length_squared() < 0.0001:
		right = up.cross(Vector3.RIGHT)
	right = right.normalized()
	var forward := right.cross(up).normalized()
	global_basis = Basis(right, up, forward)
	global_position = at + up * size
