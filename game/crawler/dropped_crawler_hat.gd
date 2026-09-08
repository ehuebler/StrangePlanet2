class_name DroppedCrawlerHat
extends StaticBody3D

## A basic city hat resting in the world as its own mesh, lit and spinning.

const DISPLAY_REACH := 0.78
const TARGET_SIZE := Vector3(0.82, 0.88, 0.82)

var pickup_id := 0
var item_id := ""
var _visual: Node3D
var _visual_origin := Vector3.ZERO
var _motion: Dictionary = {}


func configure(id: int, hat_id: String) -> void:
	pickup_id = id
	item_id = hat_id
	name = "DroppedCrawlerHat_%d" % pickup_id


func interact_prompt() -> String:
	return "Pick up %s" % ItemDB.title(item_id)


func interact(player: OnlinePlayer) -> void:
	if player == null or item_id.is_empty():
		return
	var ancestor := get_parent()
	while ancestor != null:
		if ancestor is GameWorld:
			(ancestor as GameWorld).request_crawler_pickup(pickup_id, player.peer_id)
			return
		ancestor = ancestor.get_parent()


func begin_settle() -> void:
	_motion = DroppedWorldMotion.start(self, DroppedWorldMotion.HOVER_HEIGHT)


func begin_settle_to(at: Vector3) -> void:
	_motion = DroppedWorldMotion.start_to(self, at)


func begin_hover() -> void:
	_motion = DroppedWorldMotion.hover(self)


func _ready() -> void:
	collision_layer = 1
	collision_mask = 0
	process_mode = Node.PROCESS_MODE_PAUSABLE
	_build_visual()
	_build_collision()
	var tint := ItemDB.tint(item_id)
	if tint.a <= 0.0:
		tint = DroppedWorldMotion.BEACON_TINT
	DroppedWorldMotion.attach_beacon(self, tint.lerp(DroppedWorldMotion.BEACON_TINT, 0.45))


func _process(delta: float) -> void:
	if _motion.is_empty():
		begin_hover()
	DroppedWorldMotion.tick(self, _visual, _motion, delta, _visual_origin)


func _build_visual() -> void:
	var path := ItemDB.scene_path(item_id)
	var packed := load(path) as PackedScene if not path.is_empty() else null
	if packed != null:
		_visual = packed.instantiate() as Node3D
	if _visual == null:
		_visual = Node3D.new()
		var mesh_instance := MeshInstance3D.new()
		var mesh := SphereMesh.new()
		mesh.radius = 0.22
		mesh.height = 0.44
		mesh_instance.mesh = mesh
		_visual.add_child(mesh_instance)
	_visual.name = "HatVisual"
	add_child(_visual)
	SurfaceSkin.apply(_visual)
	_fit_visual()
	_light_visual()
	_visual_origin = _visual.position


func _fit_visual() -> void:
	var span := 0.0
	var lowest := INF
	for node in _visual.find_children("*", "MeshInstance3D", true, false):
		var mesh_instance := node as MeshInstance3D
		if mesh_instance.mesh == null:
			continue
		var box := mesh_instance.mesh.get_aabb()
		span = maxf(span, maxf(maxf(box.size.x, box.size.y), box.size.z))
		lowest = minf(lowest, box.position.y)
	var fit := DISPLAY_REACH / maxf(span, 0.01)
	_visual.scale = Vector3.ONE * minf(fit, 1.35)
	if lowest != INF:
		_visual.position.y = -lowest * _visual.scale.y + 0.10


func _light_visual() -> void:
	var tint := ItemDB.tint(item_id)
	if tint.a <= 0.0:
		tint = Color(0.72, 0.46, 1.0)
	for node in _visual.find_children("*", "MeshInstance3D", true, false):
		var mesh_instance := node as MeshInstance3D
		var material := mesh_instance.material_override as StandardMaterial3D
		if material == null:
			var active := mesh_instance.get_active_material(0)
			if active is StandardMaterial3D:
				material = (active as StandardMaterial3D).duplicate()
				mesh_instance.material_override = material
		if material == null:
			continue
		material.emission_enabled = true
		material.emission = tint.lightened(0.18)
		material.emission_energy_multiplier = maxf(
			material.emission_energy_multiplier, 2.8)
	var halo := MeshInstance3D.new()
	halo.name = "HatGlow"
	var halo_mesh := SphereMesh.new()
	halo_mesh.radius = 0.42
	halo_mesh.height = 0.84
	halo.mesh = halo_mesh
	var halo_material := StandardMaterial3D.new()
	halo_material.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	halo_material.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	halo_material.blend_mode = BaseMaterial3D.BLEND_MODE_ADD
	halo_material.cull_mode = BaseMaterial3D.CULL_DISABLED
	halo_material.albedo_color = Color(tint, 0.34)
	halo_material.emission_enabled = true
	halo_material.emission = tint
	halo_material.emission_energy_multiplier = 3.6
	halo.material_override = halo_material
	halo.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	halo.position.y = 0.22
	_visual.add_child(halo)
	var lamp := OmniLight3D.new()
	lamp.name = "HatLamp"
	lamp.light_color = tint.lightened(0.22)
	lamp.light_energy = 4.8
	lamp.omni_range = 3.8
	lamp.shadow_enabled = false
	lamp.position.y = 0.28
	_visual.add_child(lamp)


func _build_collision() -> void:
	var shape := BoxShape3D.new()
	shape.size = TARGET_SIZE
	var collider := CollisionShape3D.new()
	collider.position.y = shape.size.y * 0.45
	collider.shape = shape
	add_child(collider)
