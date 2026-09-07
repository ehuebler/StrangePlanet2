class_name ItemIcons
extends Node

## Renders item icons from the garment .glb files themselves.
##
## Hand-drawn icons would be a second copy of the art to keep in step with the
## meshes, so each item is instead photographed once into an ImageTexture: its
## garment, shaded with the same pencil material it is worn in, lit and framed to
## fill the tile. The cache is static, so a session pays for each icon once
## however many times the wardrobe is opened.
##
## Rendering needs a frame, so callers ask with `request()` and hang the result on
## `icon_ready`; `cached()` returns what has already arrived.

signal icon_ready(id: String, texture: Texture2D)

## Rendered well above tile size and scaled down when drawn. The outline pass
## measures its strokes in pixels, so a 44-pixel render would be mostly outline.
const SIZE := 256
## The garment is viewed from front-left and slightly above, which reads better
## than a flat elevation for shoes and a hat brim.
const VIEW_DIRECTION := Vector3(-0.55, 0.4, -1.0)

static var _cache: Dictionary = {}

var _viewport: SubViewport
var _camera: Camera3D
var _queue: Array[String] = []
var _draining := false


static func cached(id: String) -> Texture2D:
	var texture: Texture2D = _cache.get(id, null)
	if texture != null:
		return texture
	if CrawlerCatalog.is_token(id):
		return _cache.get(CrawlerCatalog.catalog_id(id), null)
	return null


func _ready() -> void:
	_viewport = SubViewport.new()
	_viewport.size = Vector2i(SIZE, SIZE)
	_viewport.transparent_bg = true
	# Its own world, so the wardrobe's own lighting and the scene behind the menu
	# cannot reach into the icon.
	_viewport.own_world_3d = true
	_viewport.render_target_update_mode = SubViewport.UPDATE_DISABLED
	add_child(_viewport)

	# No environment of its own: the transparent target already clears to nothing,
	# and the pencil material ignores ambient light, so the only thing an
	# Environment here could do is escape into the world's own lighting.

	# The pencil material disables ambient light and hatches from real lights, so
	# an unlit icon would come out as a flat silhouette.
	var key := DirectionalLight3D.new()
	key.rotation_degrees = Vector3(-38.0, 148.0, 0.0)
	key.light_energy = 1.15
	_viewport.add_child(key)

	_camera = Camera3D.new()
	_camera.projection = Camera3D.PROJECTION_ORTHOGONAL
	_viewport.add_child(_camera)


## Renders any of `ids` that are not cached yet, in the background.
func request(ids: Array) -> void:
	for id_variant in ids:
		var id := CrawlerCatalog.catalog_id(String(id_variant))
		if id.is_empty() or _cache.has(id) or _queue.has(id):
			continue
		_queue.append(id)
	if not _draining:
		_drain()


func _drain() -> void:
	_draining = true
	while not _queue.is_empty():
		var id: String = _queue.pop_front()
		var texture := await _render(id)
		if texture != null:
			_cache[id] = texture
			icon_ready.emit(id, texture)
	_draining = false


func _render(id: String) -> Texture2D:
	# Abilities carry deliberately authored vector glyphs in their generated
	# definitions. They need no viewport frame and remain crisp in both the HUD
	# and the larger Tab-menu record.
	var ability_icon := ItemDB.ability_icon(CrawlerCatalog.catalog_id(id))
	if ability_icon != null:
		return ability_icon
	var garment := _load_garment(ItemDB.scene_path(id), id)
	if garment == null:
		return null
	_viewport.add_child(garment)
	_frame(garment)
	_viewport.render_target_update_mode = SubViewport.UPDATE_ONCE
	await RenderingServer.frame_post_draw
	var image := _viewport.get_texture().get_image()
	garment.queue_free()
	if image == null or image.is_empty():
		return null
	return ImageTexture.create_from_image(image)


## The garment mesh on its own, cut loose from the skeleton its .glb ships with so
## it renders in the rest pose without one.
func _load_garment(path: String, item_id := "") -> MeshInstance3D:
	if path.is_empty():
		return null
	var scene := load(path) as PackedScene
	if scene == null:
		return null
	var instance := scene.instantiate()
	if instance.has_method(&"apply_item") and not item_id.is_empty():
		instance.call(&"apply_item", item_id)
	var found: MeshInstance3D = null
	for node in instance.find_children("*", "MeshInstance3D", true, false):
		found = node as MeshInstance3D
		break
	if found == null:
		instance.free()
		return null
	found.get_parent().remove_child(found)
	instance.free()
	found.transform = Transform3D.IDENTITY
	found.skin = null
	found.skeleton = NodePath()
	SurfaceSkin.paint(found)
	return found


func _frame(garment: MeshInstance3D) -> void:
	var box: AABB = garment.mesh.get_aabb()
	var centre := box.get_center()
	# Fitted to the garment's longest side rather than its diagonal, so a hat
	# fills its tile as much as a pair of trousers does.
	var reach := maxf(maxf(box.size.x, box.size.y), box.size.z)
	_camera.size = maxf(reach * 1.22, 0.05)
	_camera.position = centre + VIEW_DIRECTION.normalized() * maxf(reach * 3.0, 1.0)
	_camera.look_at(centre, Vector3.UP)
