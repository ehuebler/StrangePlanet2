class_name DroppedCrawlerCard
extends StaticBody3D

## A crawler ability or modifier resting in the world as a thick rounded tile.
##
## Ordinary [DroppedItem] nodes show a garment mesh. Crawler cards keep their
## modifiers in the pickup payload, so the world object is a spinning icon plate
## rather than a second inventory rule.

const TILE := 0.72
const THICKNESS := 0.16
const TARGET_SIZE := Vector3(0.86, 0.92, 0.28)

var pickup_id := 0
var payload: Dictionary = {}
var _visual: Node3D
var _visual_origin := Vector3.ZERO
var _motion: Dictionary = {}


func configure(id: int, card_payload: Dictionary) -> void:
	pickup_id = id
	payload = card_payload.duplicate(true)
	name = "DroppedCrawlerCard_%d" % pickup_id


func catalog_id() -> String:
	return str(payload.get("id", ""))


func interact_prompt() -> String:
	var title := CrawlerCatalog.title_of(catalog_id())
	if title.is_empty():
		title = "card"
	return "Pick up %s" % title


func begin_settle() -> void:
	_motion = DroppedWorldMotion.start(self, DroppedWorldMotion.HOVER_HEIGHT)


func begin_settle_to(at: Vector3) -> void:
	_motion = DroppedWorldMotion.start_to(self, at)


func begin_hover() -> void:
	_motion = DroppedWorldMotion.hover(self)


func interact(player: OnlinePlayer) -> void:
	if player == null:
		return
	var ancestor := get_parent()
	while ancestor != null:
		if ancestor is GameWorld:
			(ancestor as GameWorld).request_crawler_pickup(pickup_id, player.peer_id)
			return
		ancestor = ancestor.get_parent()


func _ready() -> void:
	collision_layer = 1
	collision_mask = 0
	process_mode = Node.PROCESS_MODE_PAUSABLE
	_build_visual()
	_build_collision()
	DroppedWorldMotion.attach_beacon(self)


func _process(delta: float) -> void:
	if _motion.is_empty():
		begin_hover()
	DroppedWorldMotion.tick(self, _visual, _motion, delta, _visual_origin)


func _build_visual() -> void:
	_visual = Node3D.new()
	_visual.name = "CardVisual"
	add_child(_visual)

	var plate := _rounded_plate_texture()
	var core := MeshInstance3D.new()
	var box := BoxMesh.new()
	box.size = Vector3(TILE * 0.78, TILE * 0.78, THICKNESS * 0.72)
	var plate_material := StandardMaterial3D.new()
	plate_material.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	plate_material.albedo_color = Color("1a2740")
	plate_material.emission_enabled = true
	plate_material.emission = Color("2a4d88")
	plate_material.emission_energy_multiplier = 0.55
	box.material = plate_material
	core.mesh = box
	_visual.add_child(core)

	_visual.add_child(_face_quad(plate, -THICKNESS * 0.5, true))
	_visual.add_child(_face_quad(plate, THICKNESS * 0.5, false))

	var icon_texture := _icon_texture()
	if icon_texture != null:
		_visual.add_child(_icon_quad(icon_texture, -THICKNESS * 0.5 - 0.006, true))
		_visual.add_child(_icon_quad(icon_texture, THICKNESS * 0.5 + 0.006, false))

	_visual_origin = _visual.position


func _face_quad(texture: Texture2D, depth: float, toward_player: bool) -> MeshInstance3D:
	var face := MeshInstance3D.new()
	var quad := QuadMesh.new()
	quad.size = Vector2(TILE, TILE)
	var material := StandardMaterial3D.new()
	material.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	material.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	material.cull_mode = BaseMaterial3D.CULL_DISABLED
	material.albedo_texture = texture
	material.texture_filter = BaseMaterial3D.TEXTURE_FILTER_LINEAR
	quad.material = material
	face.mesh = quad
	face.position.z = depth
	if toward_player:
		face.rotation_degrees.y = 180.0
	return face


func _icon_quad(texture: Texture2D, depth: float, toward_player: bool) -> MeshInstance3D:
	var icon := MeshInstance3D.new()
	var quad := QuadMesh.new()
	quad.size = Vector2(TILE * 0.46, TILE * 0.46)
	var material := StandardMaterial3D.new()
	material.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	material.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	material.cull_mode = BaseMaterial3D.CULL_DISABLED
	material.albedo_texture = texture
	material.albedo_color = Color.WHITE
	quad.material = material
	icon.mesh = quad
	icon.position.z = depth
	if toward_player:
		icon.rotation_degrees.y = 180.0
	return icon


func _rounded_plate_texture() -> Texture2D:
	const SIZE := 128
	const RADIUS := 22.0
	const BORDER := 11.0
	var image := Image.create(SIZE, SIZE, false, Image.FORMAT_RGBA8)
	var half := Vector2(SIZE, SIZE) * 0.5
	var box := half - Vector2.ONE
	var fill := Color("1a2740")
	var rim := Color("ef151f")
	for y in SIZE:
		for x in SIZE:
			var point := Vector2(x + 0.5, y + 0.5) - half
			var distance := _sd_rounded_box(point, box, RADIUS)
			if distance > 0.5:
				image.set_pixel(x, y, Color(0, 0, 0, 0))
			elif distance > -BORDER:
				image.set_pixel(x, y, rim)
			else:
				image.set_pixel(x, y, fill)
	return ImageTexture.create_from_image(image)


func _sd_rounded_box(point: Vector2, half_size: Vector2, radius: float) -> float:
	var q := Vector2(absf(point.x), absf(point.y)) - half_size + Vector2(radius, radius)
	return Vector2(maxf(q.x, 0.0), maxf(q.y, 0.0)).length() \
		+ minf(maxf(q.x, q.y), 0.0) - radius


func _icon_texture() -> Texture2D:
	return CrawlerCatalog.texture_for(catalog_id())


func _build_collision() -> void:
	var shape := BoxShape3D.new()
	shape.size = TARGET_SIZE
	var collider := CollisionShape3D.new()
	collider.shape = shape
	add_child(collider)
