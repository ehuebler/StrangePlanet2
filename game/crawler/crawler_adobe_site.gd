class_name CrawlerAdobeSite
extends RefCounted

## Adobe crawler sites. Every city ring seats the one authored blob village.
## The office and castle each seat one authored mass. Every site rolls its
## own three-colour palette; shared paths stay gray; the plaster grain stays
## the same.

const VILLAGE_MODEL := "res://assets/runtime/environment/adobe/adobe_blob_village.glb"
const CITY_BUILDINGS: PackedStringArray = [VILLAGE_MODEL]
const CASTLE_MODEL := "res://assets/runtime/environment/adobe/adobe_castle.glb"
const OFFICE_MODEL := "res://assets/runtime/environment/adobe/adobe_office.glb"
const SHADER := preload("res://shaders/vivid/adobe_plaster.gdshader")
const CITY_SCALE := 1.5
const MONUMENT_SCALE := 1.07
const FLORA_PAD := 1.25
const PRIMARY := Color(0.8, 0.025, 0.035)
const SECONDARY := Color(1.0, 0.64, 0.015)
const TERTIARY := Color(0.015, 0.10, 0.85)
const PATH_GREY := Color(0.56, 0.53, 0.48)


static func city_ready() -> bool:
	for path: String in CITY_BUILDINGS:
		if not ResourceLoader.exists(path):
			return false
	return true


static func monuments_ready() -> bool:
	return ResourceLoader.exists(CASTLE_MODEL) and ResourceLoader.exists(OFFICE_MODEL)


static func footprint_metres(root: Node) -> float:
	return BuildingFloraClear.mesh_span(root)


static func building_count(host: Node) -> int:
	if host == null:
		return 0
	var village := host.get_node_or_null("Village") as Node
	var root := village if village != null else host
	var count := 0
	for child in root.get_children():
		if str(child.name).begins_with("adobe_"):
			count += 1
	return count


static func palette_for(key: String) -> PackedColorArray:
	var rng := RandomNumberGenerator.new()
	rng.seed = _seed(key)
	var hue := rng.randf()
	var colours := PackedColorArray()
	for index in 3:
		var turn := fmod(hue + float(index) * 0.3333 + rng.randf_range(-0.05, 0.05), 1.0)
		if turn < 0.0:
			turn += 1.0
		var sat := rng.randf_range(0.58, 0.92)
		var val := rng.randf_range(0.55, 0.96)
		if index == 2:
			sat = rng.randf_range(0.70, 0.95)
			val = rng.randf_range(0.42, 0.78)
		colours.append(Color.from_hsv(turn, sat, val))
	return colours


static func prepare(root: Node3D, key: String, planet: Planet) -> void:
	if root == null:
		return
	root.scale = Vector3.ONE * MONUMENT_SCALE
	PatchMonuments.wire_visible_collision(root)
	paint(root, palette_for(key))
	BuildingFoundation.seat(root, planet)


static func scatter_city(village: Node3D, key: String, _radius: float, planet: Planet) -> int:
	if village == null or not city_ready():
		return 0
	var packed := load(VILLAGE_MODEL) as PackedScene
	if packed == null:
		return 0
	var body := packed.instantiate() as Node3D
	if body == null:
		return 0
	body.name = VILLAGE_MODEL.get_file().get_basename()
	body.position = Vector3.ZERO
	body.rotation = Vector3.ZERO
	body.scale = Vector3.ONE * CITY_SCALE
	village.add_child(body)
	PatchMonuments.wire_visible_collision(body)
	BuildingFoundation.seat(body, planet, BuildingFoundation.DEFAULT_TINT,
		PackedStringArray(), true)
	paint(body, palette_for(key))
	return 1


static func paint(root: Node, palette: PackedColorArray) -> void:
	if root == null or palette.size() < 3:
		return
	var cache: Array = [null, null, null]
	_paint_node(root, palette, cache)


static func _paint_node(
		node: Node,
		palette: PackedColorArray,
		cache: Array
	) -> void:
	if node is MeshInstance3D:
		var mesh_i := node as MeshInstance3D
		if String(mesh_i.name) == BuildingFoundation.SKIRT_NAME:
			return
		var count := mesh_i.mesh.get_surface_count() if mesh_i.mesh != null else 0
		for surface in count:
			var source := mesh_i.get_active_material(surface)
			if String(mesh_i.name) == BuildingFoundation.PATH_SKIRT_NAME \
					or _is_shared_path(mesh_i, source):
				if cache.size() < 4:
					cache.resize(4)
				if cache[3] == null:
					cache[3] = _adobe_material(PATH_GREY)
				mesh_i.set_surface_override_material(surface, cache[3])
				continue
			var slot := _slot_of(_albedo_of(source), source)
			if cache[slot] == null:
				cache[slot] = _adobe_material(palette[slot])
			mesh_i.set_surface_override_material(surface, cache[slot])
	for child in node.get_children():
		_paint_node(child, palette, cache)


static func _adobe_material(colour: Color) -> ShaderMaterial:
	var material := ShaderMaterial.new()
	material.shader = SHADER
	material.set_shader_parameter(&"albedo", colour)
	return material


static func _albedo_of(material: Material) -> Color:
	if material is ShaderMaterial:
		var painted: Variant = (material as ShaderMaterial).get_shader_parameter(&"albedo")
		if painted is Color:
			return painted as Color
	if material is BaseMaterial3D:
		return (material as BaseMaterial3D).albedo_color
	return PRIMARY


static func _is_shared_path(mesh_i: MeshInstance3D, material: Material) -> bool:
	if BuildingFoundation.is_path_mesh(mesh_i.name):
		return true
	var named := String(mesh_i.name).to_lower()
	if named.contains("gray_adobe") or named.contains("grey_adobe"):
		return true
	var mat_name := ""
	if material != null:
		mat_name = String(material.resource_name).to_lower()
		if mat_name.is_empty():
			mat_name = material.resource_path.get_file().to_lower()
	return mat_name.contains("gray adobe") or mat_name.contains("grey adobe") \
			or mat_name.contains("shared path") or mat_name.contains("quiet warm")


static func _slot_of(colour: Color, material: Material = null) -> int:
	var named := ""
	if material != null:
		named = String(material.resource_name).to_lower()
		if named.is_empty():
			named = material.resource_path.get_file().to_lower()
	if named.contains("yellow") or named.contains("interior"):
		return 1
	if named.contains("blue") or named.contains("opening") or named.contains("lip"):
		return 2
	if named.contains("red") or named.contains("exterior"):
		return 0
	var red := _colour_gap(colour, PRIMARY)
	var yellow := _colour_gap(colour, SECONDARY)
	var blue := _colour_gap(colour, TERTIARY)
	if yellow < red and yellow < blue:
		return 1
	if blue < red:
		return 2
	return 0


static func _colour_gap(a: Color, b: Color) -> float:
	return Vector3(a.r, a.g, a.b).distance_to(Vector3(b.r, b.g, b.b))


static func _seed(key: String) -> int:
	var text := key.strip_edges()
	if text.is_empty():
		text = "city"
	var hashed := text.hash()
	return hashed if hashed != 0 else 1
