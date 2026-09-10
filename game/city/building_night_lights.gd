extends Node3D

## Raster emission on the Astra buildings only paints the glowing mesh. These
## OmniLights are the real lamps those strips, runes, LEDs, and hearths imply,
## so nearby walls, floors, and props pick up the same colour after dark.

const NODE_NAME := "NightLights"
const MAX_LIGHTS := 28
const CLUSTER := 6.5
const MIN_EMIT := 0.18
const HUE_MERGE := 0.14

var _planet: Planet
var _base_energy: PackedFloat32Array = PackedFloat32Array()
var _lights: Array[OmniLight3D] = []


static func bind(root: Node3D, planet: Planet) -> Node3D:
	if root == null:
		return null
	var existing := root.get_node_or_null(NODE_NAME) as Node3D
	if existing != null:
		existing.set(&"_planet", planet)
		return existing
	var script := load("res://game/city/building_night_lights.gd") as GDScript
	var rig := script.new() as Node3D
	rig.name = NODE_NAME
	rig.set(&"_planet", planet)
	root.add_child(rig)
	rig.call(&"_build", root)
	return rig


func _ready() -> void:
	set_process(not _lights.is_empty())
	_apply_night(_night_amount())


func _process(_delta: float) -> void:
	_apply_night(_night_amount())


func _build(root: Node3D) -> void:
	var sources := _collect(root, root)
	if sources.is_empty():
		set_process(false)
		return
	var clusters := _cluster(sources)
	_add_fills(root, clusters)
	clusters.sort_custom(func(a: Dictionary, b: Dictionary) -> bool:
		return float(a.get("energy", 0.0)) > float(b.get("energy", 0.0))
	)
	if clusters.size() > MAX_LIGHTS:
		clusters.resize(MAX_LIGHTS)
	_base_energy.resize(clusters.size())
	for index in clusters.size():
		var cluster: Dictionary = clusters[index]
		var light := OmniLight3D.new()
		light.name = "Lamp_%d" % index
		light.position = cluster["position"]
		light.light_color = cluster["color"]
		light.light_energy = 0.0
		light.omni_range = float(cluster.get("reach", 12.0))
		light.omni_attenuation = 1.55
		light.light_size = 0.7
		light.light_specular = 0.12
		light.shadow_enabled = false
		light.visible = false
		add_child(light)
		_lights.append(light)
		_base_energy[index] = float(cluster.get("energy", 1.8))
	set_process(not _lights.is_empty())


func _collect(root: Node3D, node: Node) -> Array:
	var found: Array = []
	if node == self:
		return found
	if node is MeshInstance3D:
		var sample := _sample_mesh(root, node as MeshInstance3D)
		if not sample.is_empty():
			found.append(sample)
	elif node is Node3D and _is_light_marker(node):
		found.append(_sample_marker(root, node as Node3D))
	for child in node.get_children():
		found.append_array(_collect(root, child))
	return found


func _is_light_marker(node: Node) -> bool:
	var folded := String(node.name).to_lower()
	return folded == "light_source" \
			or folded.ends_with("_light_source") \
			or folded.ends_with("-light_source")


func _sample_marker(root: Node3D, marker: Node3D) -> Dictionary:
	return {
		"position": root.to_local(marker.global_position),
		"color": Color(1.0, 0.78, 0.42),
		"energy": 2.1,
		"reach": 14.0,
	}


func _sample_mesh(root: Node3D, mesh_i: MeshInstance3D) -> Dictionary:
	if mesh_i.mesh == null or not mesh_i.visible:
		return {}
	var folded := String(mesh_i.name).to_lower()
	if folded.contains("colonly") \
			or folded == BuildingFoundation.SKIRT_NAME.to_lower() \
			or folded == BuildingFoundation.PATH_SKIRT_NAME.to_lower():
		return {}
	var colour := Color.BLACK
	var strength := 0.0
	for surf in mesh_i.mesh.get_surface_count():
		var mat := mesh_i.get_active_material(surf)
		if not (mat is StandardMaterial3D):
			continue
		var std := mat as StandardMaterial3D
		if not std.emission_enabled:
			continue
		var emit := std.emission
		var energy := maxf(std.emission_energy_multiplier, 0.0)
		var weight := emit.get_luminance() * energy
		if weight > strength:
			strength = weight
			colour = emit
	if strength < MIN_EMIT:
		var hinted := _name_colour(folded)
		if hinted.a <= 0.0:
			return {}
		colour = hinted
		strength = 2.2
	var aabb := mesh_i.mesh.get_aabb()
	var centre := root.to_local(mesh_i.to_global(aabb.get_center()))
	var span := maxf(maxf(aabb.size.x, aabb.size.y), aabb.size.z)
	var lift := clampf(span * 0.18, 0.45, 1.8)
	centre += Vector3.UP * lift
	var reach := clampf(span * 1.35 + 7.0, 8.0, 22.0)
	var energy := clampf(0.85 + strength * 0.55, 1.4, 3.8)
	return {
		"position": centre,
		"color": _lit_colour(colour),
		"energy": energy,
		"reach": reach,
	}


func _name_colour(folded: String) -> Color:
	if folded.contains("neon cyan"):
		return Color(0.12, 0.92, 1.0)
	if folded.contains("neon pink"):
		return Color(1.0, 0.18, 0.48)
	if folded.contains("neon amber"):
		return Color(1.0, 0.48, 0.08)
	if folded.contains("neon violet"):
		return Color(0.48, 0.16, 1.0)
	if folded.contains("neon"):
		return Color(0.22, 0.86, 1.0)
	if folded.contains("led"):
		return Color(0.86, 0.94, 1.0)
	if folded.contains("flame") or folded.contains("fire heart") \
			or (folded.contains("fire") and not folded.contains("fireplace")):
		return Color(1.0, 0.42, 0.08)
	if folded.contains("purple") and _glow_fixture(folded):
		return Color(0.62, 0.12, 1.0)
	if folded.contains("green") and _glow_fixture(folded):
		return Color(0.18, 1.0, 0.28)
	if folded.contains("red") and _glow_fixture(folded):
		return Color(1.0, 0.12, 0.14)
	return Color(0, 0, 0, 0)


func _glow_fixture(folded: String) -> bool:
	return folded.contains("pad") or folded.contains("console") \
			or folded.contains("pylon") or folded.contains("halo") \
			or folded.contains("dynamo") or folded.contains("telemetry") \
			or folded.contains("coolant") or folded.contains("cable") \
			or folded.contains("lane") or folded.contains("deck")


func _lit_colour(colour: Color) -> Color:
	var lit := colour
	if lit.get_luminance() < 0.22:
		lit = lit.lerp(Color.WHITE, 0.35)
	return Color(lit.r, lit.g, lit.b)


func _cluster(sources: Array) -> Array:
	var remaining: Array = sources.duplicate()
	remaining.sort_custom(func(a: Dictionary, b: Dictionary) -> bool:
		return float(a.get("energy", 0.0)) > float(b.get("energy", 0.0))
	)
	var clusters: Array = []
	var used := PackedByteArray()
	used.resize(remaining.size())
	for index in remaining.size():
		if used[index] != 0:
			continue
		var seed: Dictionary = remaining[index]
		var members: Array = [seed]
		used[index] = 1
		for other in remaining.size():
			if used[other] != 0:
				continue
			var sample: Dictionary = remaining[other]
			if _same_lamp(seed, sample):
				members.append(sample)
				used[other] = 1
		clusters.append(_merge(members))
	return clusters


func _same_lamp(a: Dictionary, b: Dictionary) -> bool:
	var pa: Vector3 = a["position"]
	var pb: Vector3 = b["position"]
	if pa.distance_to(pb) > CLUSTER:
		return false
	return _hue_close(a["color"], b["color"])


func _hue_close(a: Color, b: Color) -> bool:
	if a.s < 0.22 or b.s < 0.22:
		return true
	return absf(a.h - b.h) <= HUE_MERGE \
			or absf(a.h - b.h) >= (1.0 - HUE_MERGE)


func _merge(members: Array) -> Dictionary:
	var weight := 0.0
	var pos := Vector3.ZERO
	var colour := Color.BLACK
	var energy := 0.0
	var reach := 0.0
	for raw: Variant in members:
		var sample: Dictionary = raw
		var w := maxf(float(sample.get("energy", 1.0)), 0.2)
		weight += w
		pos += sample["position"] * w
		colour += sample["color"] * w
		energy = maxf(energy, float(sample.get("energy", 0.0)))
		reach = maxf(reach, float(sample.get("reach", 0.0)))
	if weight <= 0.0:
		weight = 1.0
	pos /= weight
	colour /= weight
	energy = minf(energy * (1.0 + 0.06 * float(members.size() - 1)), 4.2)
	reach = minf(reach + float(members.size() - 1) * 0.45, 26.0)
	return {
		"position": pos,
		"color": _lit_colour(colour),
		"energy": energy,
		"reach": reach,
	}


func _add_fills(root: Node3D, clusters: Array) -> void:
	var bounds := _mesh_bounds(root)
	if bounds.size.y < 8.0 and maxf(bounds.size.x, bounds.size.z) < 16.0:
		return
	var span := maxf(maxf(bounds.size.x, bounds.size.y), bounds.size.z)
	var fills := 1
	if bounds.size.y > 26.0:
		fills = 2
	var tint := Color(1.0, 0.86, 0.62)
	if not clusters.is_empty():
		tint = _lit_colour(clusters[0]["color"]).lerp(Color(1.0, 0.9, 0.72), 0.45)
	for index in fills:
		var t := 0.28 if fills == 1 else (0.22 + 0.42 * float(index))
		clusters.append({
			"position": bounds.position + bounds.size * Vector3(0.5, t, 0.5),
			"color": tint,
			"energy": 1.15 if fills == 1 else 1.35,
			"reach": clampf(span * 0.42, 14.0, 34.0),
		})


func _mesh_bounds(root: Node3D) -> AABB:
	var min_p := Vector3(INF, INF, INF)
	var max_p := Vector3(-INF, -INF, -INF)
	var found := false
	var stack: Array[Node] = [root]
	while not stack.is_empty():
		var node: Node = stack.pop_back()
		if node == self:
			continue
		if node is MeshInstance3D:
			var mesh_i := node as MeshInstance3D
			if mesh_i.mesh != null and mesh_i.visible \
					and not String(mesh_i.name).to_lower().contains("colonly"):
				var centre := root.to_local(mesh_i.to_global(
					mesh_i.mesh.get_aabb().get_center()))
				var ext := mesh_i.mesh.get_aabb().size * 0.5
				min_p = min_p.min(centre - ext)
				max_p = max_p.max(centre + ext)
				found = true
		for child in node.get_children():
			stack.append(child)
	if not found:
		return AABB(Vector3(-4.0, 0.0, -4.0), Vector3(8.0, 6.0, 8.0))
	return AABB(min_p, max_p - min_p)


func _night_amount() -> float:
	if _planet == null or _planet.sun == null or not is_inside_tree():
		return 0.0
	var up := (global_position - _planet.global_position).normalized()
	if up.length_squared() < 0.01:
		up = global_transform.basis.y.normalized()
	var to_sun := _planet.sun.global_basis.z.normalized()
	return 1.0 - smoothstep(-0.16, 0.12, up.dot(to_sun))


func _apply_night(night: float) -> void:
	var on := night > 0.02
	for index in _lights.size():
		var light := _lights[index]
		light.visible = on
		light.light_energy = _base_energy[index] * night if on else 0.0
