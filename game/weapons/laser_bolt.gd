class_name LaserBolt
extends Node3D

## A shot from the laser carbine: a lit sliver that travels until it meets
## something.
##
## Built in code rather than as a scene, because the whole thing is one capsule and
## one lamp. It is deliberately not a physics body — a body that fast tunnels
## through walls, so each frame it sweeps a ray over the ground it just covered and
## stops at whatever that hits.
##
## Unshaded and emissive on purpose. Everything else in the world is drawn in
## pencil, and a bolt reading as light rather than as a drawn object is what makes
## it obviously the thing that just left the muzzle.

const SPEED := 74.0
const LIFETIME := 1.5
const RADIUS := 0.022
const LENGTH := 0.42
const COLOR := Color(0.42, 0.98, 0.92)
## How long the flash where a bolt lands stays up.
const SPARK_TIME := 0.09

var _direction := Vector3.FORWARD
var _shooter_rid := RID()
var _shooter: Node
var _live := 0.0
var _spark := -1.0
var _mesh: MeshInstance3D
var _lamp: OmniLight3D


## Puts a bolt in `world` and sets it going. `shooter` is skipped by the sweep, so
## a shot cannot hit the body that fired it.
static func fire(world: Node, from: Vector3, along: Vector3, shooter: CollisionObject3D = null) -> LaserBolt:
	if world == null:
		return null
	var bolt := LaserBolt.new()
	bolt._direction = along.normalized() if along.length_squared() > 0.0 else Vector3.FORWARD
	if shooter != null:
		bolt._shooter_rid = shooter.get_rid()
		bolt._shooter = shooter
	world.add_child(bolt)
	bolt.global_position = from
	bolt.look_at(from + bolt._direction, Vector3.UP)
	return bolt


func _ready() -> void:
	var capsule := CapsuleMesh.new()
	capsule.radius = RADIUS
	capsule.height = LENGTH
	capsule.radial_segments = 6
	capsule.rings = 1

	var material := StandardMaterial3D.new()
	material.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	material.albedo_color = COLOR
	material.emission_enabled = true
	material.emission = COLOR
	material.emission_energy_multiplier = 2.4
	capsule.material = material

	_mesh = MeshInstance3D.new()
	_mesh.mesh = capsule
	# A capsule stands along +Y, and a bolt lies along the way it is going.
	_mesh.rotation.x = -PI * 0.5
	add_child(_mesh)

	# Enough to catch on whatever it passes without washing the shooter cyan.
	_lamp = OmniLight3D.new()
	_lamp.light_color = COLOR
	_lamp.light_energy = 1.0
	_lamp.omni_range = 1.7
	add_child(_lamp)


func _physics_process(delta: float) -> void:
	if _spark >= 0.0:
		_spark -= delta
		if _spark <= 0.0:
			queue_free()
		return

	_live += delta
	if _live >= LIFETIME:
		queue_free()
		return

	var from := global_position
	var to := from + _direction * SPEED * delta
	var query := PhysicsRayQueryParameters3D.create(from, to)
	query.exclude = DamageHit.rid_list(_shooter_rid)
	var hit := get_world_3d().direct_space_state.intersect_ray(query)
	if hit.is_empty():
		global_position = to
		return
	global_position = hit["position"]
	_land(hit["normal"] as Vector3)


func _land(normal: Vector3) -> void:
	_mesh.visible = false
	_lamp.light_energy = 2.6
	_lamp.omni_range = 2.6
	_spark = SPARK_TIME
	if is_instance_valid(_shooter) \
			and _shooter.has_method(&"play_laser_impact_dust"):
		_shooter.call(&"play_laser_impact_dust", global_position, normal, false)
