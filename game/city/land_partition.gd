class_name LandPartition
extends RefCounted

## Buildable land on the planet, cut into neighbourhood-scale territories that
## share borders and leave no dry gaps.
##
## The globe is 8 km in radius — equator about 50 km — so a Chicago-sized
## 40 km × 25 km city will not fit. The patches here are neighbourhood-scale
## territories over every shore that is not ice, volcano, or a named
## giant-mountain site, stopping at the waterline. About ten to fifteen fit
## in one of the earlier 4.5 km cells.
##
## The cut is a Voronoi partition of an icosphere restricted to buildable
## vertices, so neighbouring patches meet on a shared edge and a peninsula stays
## with the land it is attached to rather than jumping a bay. The first cut is
## the neighbourhood used by cities and spawn recipes. A second cut splits each
## of those into smaller named cells for the tilde map without moving that
## first-cut geography. The line between two cells is the spherical
## perpendicular bisector of their seeds — that is the boundary later city
## logic should test against, not the hex mesh edges.

class Patch:
	var id := -1
	var name := ""
	## Seed used for the Voronoi cut, unit direction.
	var seed := Vector3.UP
	var direction := Vector3.UP
	var area := 0.0
	var span := 0.0
	## First-cut territory this cell belongs to. Same as [member id] when
	## the cell was not split.
	var parent_id := -1
	## Name used for crawler recipes and reserved-site rules. Stays on the
	## first-cut territory so spawn tables do not move when cells split.
	var recipe_name := ""


class BorderChain:
	## Dual crossings along the contact, used for coastline draping and as
	## the endpoints of an interior bisector.
	var dirs := PackedVector3Array()
	var closed := false
	var patch_a := -1
	## Other side of the chain. -1 means unowned ground (shore, ice, lava).
	var patch_b := -1


## Icosphere depth for ownership. Borders are the seed bisectors, so this
## only has to be fine enough to know which patches touch.
const SUBDIVISIONS := 6
const FROST_LIMIT := 0.08
const VOLCANO_LIMIT := 0.02
const MAX_PATCHES := 2048

const NAMES: PackedStringArray = [
	"Aurel Reach", "Vesper Coast", "Cinder Marches", "Lumen Shelf",
	"Amber Flats", "Sable Highlands", "Ivory Strand", "Copper Downs",
	"Thorn Basin", "Glass Peninsula", "Ember Ridges", "Mistwood",
	"Salt Prairie", "Quartz Headland", "Bracken Vale", "Dusk Harbor",
	"Iron Coast", "Pearl Isthmus", "Cedar Table", "Storm Cape",
	"Ochre Banks", "Silver Fen", "Umber Hills", "Coral Shelf",
	"Haze Meadow", "Granite Sound", "Willow Barrens", "Sunken Terrace",
	"Far Beacon", "Lowland Fold", "North Haven", "South March",
	"West Prospect", "East Haven", "Inner Prairie", "Outer Strand",
	"High Table", "Deep Hollow", "Long Shore", "Wide Clearing",
	"Broken Bench", "Quiet Inlet", "Open Country", "Green Interval",
	"Red Interval", "Wind Gap", "Stone Garden", "Tide Margin",
]

var patches: Array[Patch] = []
## First-cut neighbourhoods. Cells in [member patches] inherit spawn and
## city keys from these so a finer overlay does not move the world.
var territories: Array[Patch] = []
## Unit directions of the icosphere vertices.
var vertices: PackedVector3Array = PackedVector3Array()
## Patch id per vertex, or -1 where the ground is not a city territory.
var owners: PackedInt32Array = PackedInt32Array()
var border_chains: Array[BorderChain] = []
var buildable_count := 0
var buildable_area := 0.0
## Mesh adjacency kept after bake so [method owner_at] can hill-climb
## to a first guess instead of scanning every icosphere vertex.
var _neighbors: Array[PackedInt32Array] = []
## One owned vertex per cubemap cell, used as the climb seed.
var _owner_seed: PackedInt32Array = PackedInt32Array()
## Every owned vertex, bucketed by cubemap cell for the exact search.
var _owner_buckets: Array[PackedInt32Array] = []
var _owner_centers: PackedVector3Array = PackedVector3Array()
var _owner_filled: PackedInt32Array = PackedInt32Array()
## Max angle from a cell centre to an owned vertex stored in that cell.
var _owner_cell_span := 0.12
var _owner_hint := 0
const OWNER_GRID := 24


func bake(
		shape: PlanetShape,
		mountain_dirs: PackedVector3Array,
		mountain_clearance: float,
		target_span: float,
		cell_span := -1.0
	) -> void:
	patches.clear()
	territories.clear()
	vertices = PackedVector3Array()
	owners = PackedInt32Array()
	border_chains.clear()
	_neighbors.clear()
	_owner_seed = PackedInt32Array()
	_owner_buckets.clear()
	_owner_centers = PackedVector3Array()
	_owner_filled = PackedInt32Array()
	_owner_cell_span = 0.12
	_owner_hint = 0
	buildable_count = 0
	buildable_area = 0.0
	if shape == null:
		return
	shape.prepare()
	var mesh := _icosphere(SUBDIVISIONS)
	vertices = mesh["vertices"]
	var faces: PackedInt32Array = mesh["faces"]
	var count := vertices.size()
	var adjacency := _adjacency(count, faces)
	var mountain_cos := cos(mountain_clearance / maxf(shape.radius, 1.0)) \
			if mountain_clearance > 0.0 else -1.0
	owners.resize(count)
	var buildable: PackedByteArray = PackedByteArray()
	buildable.resize(count)
	for index in count:
		var allowed := _buildable(
			shape, vertices[index], mountain_dirs, mountain_cos)
		buildable[index] = 1 if allowed else 0
		owners[index] = -1
		if allowed:
			buildable_count += 1
	if buildable_count == 0:
		return
	var vertex_area := 4.0 * PI * shape.radius * shape.radius / float(count)
	buildable_area = float(buildable_count) * vertex_area
	var target_area := maxf(target_span * target_span, vertex_area * 4.0)
	var next_id := 0
	var seen: PackedByteArray = PackedByteArray()
	seen.resize(count)
	for start in count:
		if buildable[start] == 0 or seen[start] != 0:
			continue
		var component := _flood(start, buildable, adjacency, seen)
		next_id = _cut_component(
			component, adjacency, vertex_area, target_area, next_id)
	_name_patches()
	_measure_patches(shape, vertex_area)
	_snapshot_territories()
	var fine_span := cell_span if cell_span > 0.0 else target_span * 0.5
	if fine_span > 0.0 and fine_span < target_span - 0.5:
		_subdivide_cells(adjacency, vertex_area, fine_span)
		_measure_patches(shape, vertex_area)
		_name_cells()
	_collect_borders(faces, shape)
	_neighbors = adjacency
	_build_owner_index()


func _buildable(
		shape: PlanetShape,
		direction: Vector3,
		mountain_dirs: PackedVector3Array,
		mountain_cos: float
	) -> bool:
	if shape.elevation(direction, 0.0) < 0.0:
		return false
	if shape.frost(direction) > FROST_LIMIT:
		return false
	if shape.volcano_influence(direction) > VOLCANO_LIMIT:
		return false
	for mountain in mountain_dirs:
		if direction.dot(mountain) >= mountain_cos:
			return false
	return true


func _cut_component(
		component: PackedInt32Array,
		adjacency: Array[PackedInt32Array],
		vertex_area: float,
		target_area: float,
		next_id: int
	) -> int:
	var area := float(component.size()) * vertex_area
	var wanted := mini(
		MAX_PATCHES - next_id,
		maxi(1, int(round(area / target_area))))
	var seeds := _place_seeds(component, adjacency, wanted)
	var assigned := _assign(seeds, component, adjacency)
	var remap: Dictionary = {}
	for vertex in component:
		var seed: int = assigned.get(vertex, seeds[0])
		if not remap.has(seed):
			if next_id >= MAX_PATCHES:
				remap[seed] = next_id - 1
			else:
				remap[seed] = next_id
				var patch := Patch.new()
				patch.id = next_id
				patch.seed = vertices[int(seed)]
				patches.append(patch)
				next_id += 1
		owners[vertex] = int(remap[seed])
	return next_id


func _place_seeds(
		component: PackedInt32Array,
		_adjacency: Array[PackedInt32Array],
		wanted: int
	) -> PackedInt32Array:
	var seeds := PackedInt32Array()
	var centre := Vector3.ZERO
	for vertex in component:
		centre += vertices[vertex]
	centre = centre.normalized() if centre.length_squared() > 0.001 \
			else vertices[component[0]]
	var first := int(component[0])
	var best := -2.0
	for vertex in component:
		var score := vertices[vertex].dot(centre)
		if score > best:
			best = score
			first = int(vertex)
	seeds.append(first)
	# Angular farthest-point, not graph hops: one pass per extra seed instead
	# of a BFS each, which stays cheap on the subdiv-7 mesh.
	var closest_dot: Dictionary = {}
	var first_dir := vertices[first]
	for vertex in component:
		closest_dot[vertex] = vertices[vertex].dot(first_dir)
	while seeds.size() < wanted:
		var far := first
		var far_dot := 2.0
		for vertex in component:
			var toward: float = float(closest_dot[vertex])
			if toward < far_dot:
				far_dot = toward
				far = int(vertex)
		if far_dot > 0.999:
			break
		seeds.append(far)
		var added := vertices[far]
		for vertex in component:
			closest_dot[vertex] = maxf(
				float(closest_dot[vertex]), vertices[vertex].dot(added))
	return seeds


func _assign(
		seeds: PackedInt32Array,
		component: PackedInt32Array,
		_adjacency: Array[PackedInt32Array]
	) -> Dictionary:
	var nearest: Dictionary = {}
	for vertex in component:
		var best := int(seeds[0])
		var best_dot := -2.0
		var at := vertices[vertex]
		for seed in seeds:
			var toward := at.dot(vertices[seed])
			if toward > best_dot:
				best_dot = toward
				best = int(seed)
		nearest[vertex] = best
	return nearest


func _flood(
		start: int,
		buildable: PackedByteArray,
		adjacency: Array[PackedInt32Array],
		seen: PackedByteArray
	) -> PackedInt32Array:
	var found := PackedInt32Array()
	var queue: Array[int] = [start]
	seen[start] = 1
	var cursor := 0
	while cursor < queue.size():
		var at: int = queue[cursor]
		cursor += 1
		found.append(at)
		for other in adjacency[at]:
			if buildable[other] == 0 or seen[other] != 0:
				continue
			seen[other] = 1
			queue.append(int(other))
	return found


func _name_patches() -> void:
	for index in patches.size():
		var patch := patches[index]
		if index < NAMES.size():
			patch.name = NAMES[index]
		else:
			patch.name = "%s %d" % [
				NAMES[index % NAMES.size()], index / NAMES.size() + 1]
		patch.parent_id = patch.id
		patch.recipe_name = patch.name


func _snapshot_territories() -> void:
	territories.clear()
	for patch in patches:
		territories.append(_copy_patch(patch))


func _copy_patch(src: Patch) -> Patch:
	var out := Patch.new()
	out.id = src.id
	out.name = src.name
	out.seed = src.seed
	out.direction = src.direction
	out.area = src.area
	out.span = src.span
	out.parent_id = src.parent_id
	out.recipe_name = src.recipe_name
	return out


func _subdivide_cells(
		adjacency: Array[PackedInt32Array],
		vertex_area: float,
		cell_span: float
	) -> void:
	if territories.is_empty() or vertices.is_empty():
		return
	var groups: Array[PackedInt32Array] = []
	groups.resize(territories.size())
	for index in territories.size():
		groups[index] = PackedInt32Array()
	for vertex in vertices.size():
		var owner := owners[vertex]
		if owner < 0 or owner >= groups.size():
			continue
		groups[owner].append(vertex)
	var target_area := maxf(cell_span * cell_span, vertex_area * 4.0)
	var next_id := 0
	var next_patches: Array[Patch] = []
	var next_owners := owners.duplicate()
	for parent in territories:
		if parent.id < 0 or parent.id >= groups.size():
			continue
		var component := groups[parent.id]
		if component.is_empty():
			continue
		var area := float(component.size()) * vertex_area
		var wanted := mini(
			MAX_PATCHES - next_id,
			maxi(1, int(round(area / target_area))))
		if wanted <= 1 or component.size() < 6:
			var kept := _make_cell(next_id, parent, parent.seed)
			next_patches.append(kept)
			for vertex in component:
				next_owners[vertex] = next_id
			next_id += 1
			continue
		var seeds := _place_seeds(component, adjacency, wanted)
		if seeds.is_empty():
			continue
		var assigned: Dictionary = _assign(seeds, component, adjacency)
		var remap: Dictionary = {}
		var parent_first := next_id
		for vertex in component:
			var raw: Variant = assigned.get(vertex, seeds[0])
			var seed := int(raw)
			if not remap.has(seed):
				if next_id >= MAX_PATCHES:
					remap[seed] = maxi(parent_first, next_id - 1)
				else:
					remap[seed] = next_id
					next_patches.append(_make_cell(next_id, parent, vertices[seed]))
					next_id += 1
			next_owners[vertex] = int(remap[seed])
	if next_patches.is_empty():
		return
	patches = next_patches
	owners = next_owners


func _make_cell(id: int, parent: Patch, seed: Vector3) -> Patch:
	var cell := Patch.new()
	cell.id = id
	cell.seed = seed
	cell.parent_id = parent.id
	cell.recipe_name = parent.name
	cell.name = parent.name
	return cell


func _name_cells() -> void:
	var used: Dictionary = {}
	var by_parent: Dictionary = {}
	for patch in patches:
		var kids: Variant = by_parent.get(patch.parent_id, [])
		if not (kids is Array):
			kids = []
		(kids as Array).append(patch)
		by_parent[patch.parent_id] = kids
	for parent in territories:
		var raw: Variant = by_parent.get(parent.id, [])
		if not (raw is Array):
			continue
		var kids := raw as Array
		if kids.is_empty():
			continue
		var keep: Patch = kids[0]
		var best := -2.0
		for item: Variant in kids:
			var kid := item as Patch
			if kid == null:
				continue
			var score := kid.direction.dot(parent.seed)
			if score > best:
				best = score
				keep = kid
		if keep != null:
			keep.name = _unique_name(parent.name, used)
		for item: Variant in kids:
			var kid := item as Patch
			if kid == null or kid == keep:
				continue
			var suffix := _compass_suffix(parent.direction, kid.direction)
			kid.name = _unique_name("%s %s" % [parent.name, suffix], used)


func _unique_name(wanted: String, used: Dictionary) -> String:
	if not used.has(wanted):
		used[wanted] = true
		return wanted
	var step := 2
	var named := "%s %d" % [wanted, step]
	while used.has(named):
		step += 1
		named = "%s %d" % [wanted, step]
	used[named] = true
	return named


func _compass_suffix(parent_dir: Vector3, child_dir: Vector3) -> String:
	var up := parent_dir.normalized() if parent_dir.length_squared() > 0.0001 \
			else Vector3.UP
	var pole := Vector3.UP if absf(up.y) < 0.9 else Vector3.RIGHT
	var east := up.cross(pole)
	if east.length_squared() < 0.0001:
		return "Center"
	east = east.normalized()
	var north := east.cross(up)
	var child := child_dir.normalized() if child_dir.length_squared() > 0.0001 \
			else up
	var local := child - up * child.dot(up)
	if local.length_squared() < 0.00008:
		return "Center"
	local = local.normalized()
	var angle := atan2(local.dot(east), local.dot(north))
	var sector := int(round(angle / (PI * 0.25))) % 8
	if sector < 0:
		sector += 8
	match sector:
		0:
			return "North"
		1:
			return "Northeast"
		2:
			return "East"
		3:
			return "Southeast"
		4:
			return "South"
		5:
			return "Southwest"
		6:
			return "West"
		7:
			return "Northwest"
		_:
			return "Center"


func recipe_name_of(patch_id: int) -> String:
	if patch_id < 0 or patch_id >= patches.size():
		return ""
	var named := patches[patch_id].recipe_name
	return named if not named.is_empty() else patches[patch_id].name


func territory_id_of(patch_id: int) -> int:
	if patch_id < 0 or patch_id >= patches.size():
		return -1
	var parent := patches[patch_id].parent_id
	return parent if parent >= 0 else patches[patch_id].id


func territory_of(patch_id: int) -> Patch:
	if patch_id < 0 or patch_id >= patches.size():
		return null
	var tid := patches[patch_id].parent_id
	if tid >= 0 and tid < territories.size():
		return territories[tid]
	return patches[patch_id]


func first_cell_of(territory_id: int) -> int:
	var keep := -1
	for patch in patches:
		if patch.parent_id != territory_id:
			continue
		if keep < 0:
			keep = patch.id
		if patch.name == patch.recipe_name:
			return patch.id
	return keep


func belongs_to(direction: Vector3, query_id: int) -> bool:
	return same_territory(owner_at(direction), query_id)


func same_territory(owner_id: int, query_id: int) -> bool:
	var a := territory_id_of(owner_id)
	var b := territory_id_of(query_id)
	if a >= 0 and b >= 0:
		return a == b
	return owner_id == query_id and owner_id >= 0


func _measure_patches(shape: PlanetShape, vertex_area: float) -> void:
	var sums: Array[Vector3] = []
	var counts: PackedInt32Array = PackedInt32Array()
	var farthest: PackedFloat32Array = PackedFloat32Array()
	sums.resize(patches.size())
	counts.resize(patches.size())
	farthest.resize(patches.size())
	for index in vertices.size():
		var owner := owners[index]
		if owner < 0:
			continue
		sums[owner] += vertices[index]
		counts[owner] += 1
	for index in patches.size():
		var patch := patches[index]
		var total := sums[index]
		patch.direction = total.normalized() if total.length_squared() > 0.001 \
				else Vector3.UP
		patch.area = float(counts[index]) * vertex_area
	for index in vertices.size():
		var owner := owners[index]
		if owner < 0:
			continue
		farthest[owner] = maxf(
			farthest[owner],
			patches[owner].direction.angle_to(vertices[index]))
	for index in patches.size():
		patches[index].span = farthest[index] * shape.radius * 2.0


func _collect_borders(faces: PackedInt32Array, shape: PlanetShape) -> void:
	var crossing: Dictionary = {}
	var adj: Dictionary = {}
	var face_count := faces.size() / 3
	for face in face_count:
		var i0 := faces[face * 3]
		var i1 := faces[face * 3 + 1]
		var i2 := faces[face * 3 + 2]
		var mixed: Array[Vector2i] = []
		_note_mixed(i0, i1, mixed, crossing, shape)
		_note_mixed(i1, i2, mixed, crossing, shape)
		_note_mixed(i2, i0, mixed, crossing, shape)
		if mixed.size() == 2:
			_dual_link(mixed[0], mixed[1], adj)
		elif mixed.size() == 3:
			var junction := Vector2i(-face - 1, -1)
			crossing[junction] = _junction_dir(mixed, crossing)
			for edge in mixed:
				_dual_link(junction, edge, adj)
	var used: Dictionary = {}
	for node_key in adj:
		var node: Vector2i = node_key
		if (adj[node] as Dictionary).size() == 2:
			continue
		for other_key in adj[node]:
			var other: Vector2i = other_key
			var key := _undirected(node, other)
			if used.has(key):
				continue
			_record_chain(_walk_dual(node, other, adj, used, true), false, crossing)
	for node_key in adj:
		var node: Vector2i = node_key
		for other_key in adj[node]:
			var other: Vector2i = other_key
			var key := _undirected(node, other)
			if used.has(key):
				continue
			_record_chain(_walk_dual(node, other, adj, used, false), true, crossing)


func _note_mixed(
		a: int,
		b: int,
		mixed: Array[Vector2i],
		crossing: Dictionary,
		shape: PlanetShape
	) -> void:
	if owners[a] == owners[b]:
		return
	if owners[a] < 0 and owners[b] < 0:
		return
	var edge := Vector2i(mini(a, b), maxi(a, b))
	if not crossing.has(edge):
		crossing[edge] = _edge_crossing(a, b, shape)
	mixed.append(edge)


func _edge_crossing(a: int, b: int, shape: PlanetShape) -> Vector3:
	var oa := owners[a]
	var ob := owners[b]
	if oa >= 0 and ob >= 0:
		return _bisector_on_edge(
			vertices[a], vertices[b], patches[oa].seed, patches[ob].seed)
	var ea := shape.elevation(vertices[a], 0.0)
	var eb := shape.elevation(vertices[b], 0.0)
	if ea * eb < 0.0 and absf(ea - eb) > 0.0001:
		var t := clampf(ea / (ea - eb), 0.0, 1.0)
		return vertices[a].slerp(vertices[b], t)
	return vertices[a].slerp(vertices[b], 0.5)


func _bisector_on_edge(a: Vector3, b: Vector3, seed_a: Vector3, seed_b: Vector3) -> Vector3:
	var delta := seed_a - seed_b
	var da := a.dot(delta)
	var db := b.dot(delta)
	var t := 0.5
	if absf(da - db) > 0.0000001:
		t = clampf(da / (da - db), 0.0, 1.0)
	return a.slerp(b, t)


func _junction_dir(mixed: Array[Vector2i], crossing: Dictionary) -> Vector3:
	var ids: Dictionary = {}
	for edge in mixed:
		var oa := owners[edge.x]
		var ob := owners[edge.y]
		if oa >= 0:
			ids[oa] = true
		if ob >= 0:
			ids[ob] = true
	if ids.size() == 3:
		var seeds: Array[Vector3] = []
		for id in ids:
			seeds.append(patches[int(id)].seed)
		return _circumcenter(seeds[0], seeds[1], seeds[2])
	var acc := Vector3.ZERO
	for edge in mixed:
		acc += crossing[edge]
	return acc.normalized() if acc.length_squared() > 0.0001 else Vector3.UP


func _circumcenter(a: Vector3, b: Vector3, c: Vector3) -> Vector3:
	var p := (a - b).cross(b - c)
	if p.length_squared() < 0.0000000001:
		return (a + b + c).normalized()
	p = p.normalized()
	if p.dot(a + b + c) < 0.0:
		p = -p
	return p


func _dual_link(a: Vector2i, b: Vector2i, adj: Dictionary) -> void:
	if not adj.has(a):
		adj[a] = {}
	if not adj.has(b):
		adj[b] = {}
	adj[a][b] = true
	adj[b][a] = true


func _undirected(a: Vector2i, b: Vector2i) -> Vector4i:
	if a.x < b.x or (a.x == b.x and a.y < b.y):
		return Vector4i(a.x, a.y, b.x, b.y)
	return Vector4i(b.x, b.y, a.x, a.y)


func _walk_dual(
		start: Vector2i,
		first: Vector2i,
		adj: Dictionary,
		used: Dictionary,
		stop_at_junctions: bool
	) -> Array[Vector2i]:
	var nodes: Array[Vector2i] = []
	nodes.append(start)
	var prev := start
	var at := first
	while true:
		used[_undirected(prev, at)] = true
		nodes.append(at)
		var options: Dictionary = adj[at]
		var onward := Vector2i(2147483647, 2147483647)
		var found := false
		for cand in options:
			var other: Vector2i = cand
			if other == prev:
				continue
			if used.has(_undirected(at, other)):
				continue
			onward = other
			found = true
			break
		if not found:
			break
		if stop_at_junctions and options.size() != 2:
			break
		if not stop_at_junctions and onward == start:
			used[_undirected(at, onward)] = true
			break
		prev = at
		at = onward
	return nodes


func _record_chain(
		nodes: Array[Vector2i],
		closed: bool,
		crossing: Dictionary
	) -> void:
	if nodes.size() < 2:
		return
	var chain := BorderChain.new()
	chain.closed = closed
	chain.dirs.resize(nodes.size())
	for index in nodes.size():
		chain.dirs[index] = crossing[nodes[index]]
	var pair := Vector2i(-2, -2)
	for node in nodes:
		if node.x < 0:
			continue
		pair = Vector2i(owners[node.x], owners[node.y])
		break
	if pair.x < 0:
		chain.patch_a = pair.y
		chain.patch_b = -1
	elif pair.y < 0:
		chain.patch_a = pair.x
		chain.patch_b = -1
	elif pair.x <= pair.y:
		chain.patch_a = pair.x
		chain.patch_b = pair.y
	else:
		chain.patch_a = pair.y
		chain.patch_b = pair.x
	border_chains.append(chain)


func directions_of(patch_id: int) -> PackedVector3Array:
	var dirs := PackedVector3Array()
	var tid := territory_id_of(patch_id)
	for index in vertices.size():
		var owner := owners[index]
		if owner < 0:
			continue
		if owner == patch_id or (tid >= 0 and territory_id_of(owner) == tid):
			dirs.append(vertices[index])
	return dirs


func cell_directions_of(patch_id: int) -> PackedVector3Array:
	var dirs := PackedVector3Array()
	for index in vertices.size():
		if owners[index] == patch_id:
			dirs.append(vertices[index])
	return dirs


func neighbors_of(patch_id: int) -> PackedInt32Array:
	var seen: Dictionary = {}
	for chain in border_chains:
		var other := -1
		if chain.patch_a == patch_id:
			other = chain.patch_b
		elif chain.patch_b == patch_id:
			other = chain.patch_a
		if other >= 0:
			seen[other] = true
	var out := PackedInt32Array()
	for key: Variant in seen.keys():
		out.append(int(key))
	return out


func owner_at(direction: Vector3) -> int:
	if vertices.is_empty() or owners.size() != vertices.size():
		return -1
	if not direction.is_finite() or direction.length_squared() < 0.0001:
		return -1
	var toward := direction.normalized()
	if _neighbors.size() != vertices.size() or _owner_seed.is_empty():
		return owner_at_scan(toward)
	var start := _owner_seed_at(toward)
	if start >= 0 and start < vertices.size() \
			and _owner_hint >= 0 and _owner_hint < vertices.size() \
			and owners[_owner_hint] >= 0 \
			and vertices[_owner_hint].dot(toward) \
				> vertices[start].dot(toward):
		start = _owner_hint
	if start < 0 or start >= vertices.size():
		return owner_at_scan(toward)
	var best := _climb_owned(toward, start)
	if best >= 0 and best < vertices.size() \
			and vertices[best].dot(toward) >= 0.9995:
		best = _search_local_buckets(toward, best)
	else:
		best = _search_owned_buckets(toward, best)
	_owner_hint = best
	return owners[best] if best >= 0 else -1


## Linear scan of every owned vertex. Same answer as [method owner_at];
## kept for bake tests and as a fallback when the climb index is missing.
func owner_at_scan(direction: Vector3) -> int:
	var toward := direction.normalized()
	var best := -1
	var best_dot := -2.0
	for index in vertices.size():
		if owners[index] < 0:
			continue
		var score := toward.dot(vertices[index])
		if score > best_dot:
			best_dot = score
			best = index
	return owners[best] if best >= 0 else -1


func _build_owner_index() -> void:
	var cells := OWNER_GRID * OWNER_GRID * 6
	_owner_seed.resize(cells)
	_owner_seed.fill(-1)
	_owner_centers.resize(cells)
	_owner_buckets.clear()
	_owner_buckets.resize(cells)
	_owner_cell_span = 0.12
	if vertices.is_empty() or owners.size() != vertices.size():
		return
	var bags: Array = []
	bags.resize(cells)
	for slot in cells:
		bags[slot] = PackedInt32Array()
		_owner_centers[slot] = _cube_dir(slot)
	var max_span := 0.0
	for index in vertices.size():
		if owners[index] < 0:
			continue
		var slot := _cube_slot(vertices[index])
		if slot < 0 or slot >= cells:
			continue
		var bag: PackedInt32Array = bags[slot]
		bag.append(index)
		bags[slot] = bag
		var toward_center := vertices[index].dot(_owner_centers[slot])
		max_span = maxf(max_span, acos(clampf(toward_center, -1.0, 1.0)))
		if _owner_seed[slot] < 0 \
				or toward_center > vertices[_owner_seed[slot]].dot(
					_owner_centers[slot]):
			_owner_seed[slot] = index
	_owner_filled = PackedInt32Array()
	for slot in cells:
		_owner_buckets[slot] = bags[slot]
		if _owner_seed[slot] >= 0:
			_owner_filled.append(slot)
	_owner_cell_span = maxf(max_span, 0.02) + 0.012
	_owner_hint = 0
	for index in vertices.size():
		if owners[index] >= 0:
			_owner_hint = index
			break


func _owner_seed_at(toward: Vector3) -> int:
	if _owner_seed.is_empty():
		return -1
	var slot := _cube_slot(toward)
	if slot >= 0 and slot < _owner_seed.size() and _owner_seed[slot] >= 0:
		return _owner_seed[slot]
	var best := -1
	var best_dot := -2.0
	for index in _owner_seed.size():
		var vertex := _owner_seed[index]
		if vertex < 0:
			continue
		var score := vertices[vertex].dot(toward)
		if score > best_dot:
			best_dot = score
			best = vertex
	return best


func _climb_owned(toward: Vector3, start: int) -> int:
	var best := start
	if best < 0 or best >= vertices.size() or owners[best] < 0:
		best = _owner_seed_at(toward)
	if best < 0 or best >= vertices.size() or owners[best] < 0:
		return start
	var best_dot := vertices[best].dot(toward)
	var hops := 0
	var limit := mini(vertices.size(), 512)
	while hops < limit:
		hops += 1
		if best >= _neighbors.size():
			break
		var step := best
		var step_dot := best_dot
		for other in _neighbors[best]:
			if other < 0 or other >= owners.size() or owners[other] < 0:
				continue
			var score := vertices[other].dot(toward)
			if score > step_dot:
				step_dot = score
				step = other
		if step == best:
			break
		best = step
		best_dot = step_dot
	return best


func _search_local_buckets(toward: Vector3, guessed: int) -> int:
	var slots: Dictionary = {}
	var query_slot := _cube_slot(toward)
	if query_slot >= 0:
		slots[query_slot] = true
	if guessed >= 0 and guessed < vertices.size():
		slots[_cube_slot(vertices[guessed])] = true
		if guessed < _neighbors.size():
			for other in _neighbors[guessed]:
				if other >= 0 and other < vertices.size():
					slots[_cube_slot(vertices[other])] = true
	return _search_slots(toward, guessed, slots.keys())


func _search_slots(toward: Vector3, guessed: int, slots: Array) -> int:
	var best := guessed
	var best_dot := -2.0
	if best >= 0 and best < vertices.size() and owners[best] >= 0:
		best_dot = vertices[best].dot(toward)
	for slot_variant: Variant in slots:
		var slot := int(slot_variant)
		if slot < 0 or slot >= _owner_buckets.size():
			continue
		var bag := _owner_buckets[slot]
		for index in bag.size():
			var vertex := bag[index]
			var score := vertices[vertex].dot(toward)
			if score < best_dot:
				continue
			if score == best_dot and best >= 0 and vertex >= best:
				continue
			best_dot = score
			best = vertex
	return best


func _search_owned_buckets(toward: Vector3, guessed: int) -> int:
	if _owner_buckets.is_empty() or _owner_centers.size() != _owner_buckets.size():
		return guessed
	var best := guessed
	var best_dot := -2.0
	if best >= 0 and best < vertices.size() and owners[best] >= 0:
		best_dot = vertices[best].dot(toward)
	var min_center := -1.0
	if best_dot > -1.5:
		min_center = cos(minf(acos(clampf(best_dot, -1.0, 1.0)) + _owner_cell_span, PI))
	for filled in _owner_filled.size():
		var slot := _owner_filled[filled]
		if _owner_centers[slot].dot(toward) < min_center:
			continue
		var bag := _owner_buckets[slot]
		for index in bag.size():
			var vertex := bag[index]
			var score := vertices[vertex].dot(toward)
			if score < best_dot:
				continue
			if score == best_dot and best >= 0 and vertex >= best:
				continue
			best_dot = score
			best = vertex
			min_center = cos(minf(
				acos(clampf(best_dot, -1.0, 1.0)) + _owner_cell_span, PI))
	return best


func _cube_slot(direction: Vector3) -> int:
	if direction.length_squared() < 0.0001:
		return 0
	var n := direction.normalized()
	var ax := absf(n.x)
	var ay := absf(n.y)
	var az := absf(n.z)
	var face := 0
	var u := 0.0
	var v := 0.0
	if ax >= ay and ax >= az:
		if n.x >= 0.0:
			face = 0
			u = -n.z / ax
			v = n.y / ax
		else:
			face = 1
			u = n.z / ax
			v = n.y / ax
	elif ay >= az:
		if n.y >= 0.0:
			face = 2
			u = n.x / ay
			v = -n.z / ay
		else:
			face = 3
			u = n.x / ay
			v = n.z / ay
	else:
		if n.z >= 0.0:
			face = 4
			u = n.x / az
			v = n.y / az
		else:
			face = 5
			u = -n.x / az
			v = n.y / az
	var col := clampi(
		int(floor((u * 0.5 + 0.5) * float(OWNER_GRID))), 0, OWNER_GRID - 1)
	var row := clampi(
		int(floor((v * 0.5 + 0.5) * float(OWNER_GRID))), 0, OWNER_GRID - 1)
	return (face * OWNER_GRID + col) * OWNER_GRID + row


func _cube_dir(slot: int) -> Vector3:
	var grid := OWNER_GRID
	var span := grid * grid
	var face := int(slot / span)
	var rem := slot - face * span
	var col := int(rem / grid)
	var row := rem - col * grid
	var u := ((float(col) + 0.5) / float(grid)) * 2.0 - 1.0
	var v := ((float(row) + 0.5) / float(grid)) * 2.0 - 1.0
	var dir := Vector3.ZERO
	match face:
		0:
			dir = Vector3(1.0, v, -u)
		1:
			dir = Vector3(-1.0, v, u)
		2:
			dir = Vector3(u, 1.0, -v)
		3:
			dir = Vector3(u, -1.0, v)
		4:
			dir = Vector3(u, v, 1.0)
		_:
			dir = Vector3(-u, v, -1.0)
	return dir.normalized()


func border_edge_count() -> int:
	var total := 0
	for chain in border_chains:
		total += maxi(chain.dirs.size() - 1, 0)
		if chain.closed:
			total += 1
	return total


func _adjacency(count: int, faces: PackedInt32Array) -> Array[PackedInt32Array]:
	var edges: Dictionary = {}
	var face_count := faces.size() / 3
	for face in face_count:
		var a := faces[face * 3]
		var b := faces[face * 3 + 1]
		var c := faces[face * 3 + 2]
		edges[Vector2i(mini(a, b), maxi(a, b))] = true
		edges[Vector2i(mini(b, c), maxi(b, c))] = true
		edges[Vector2i(mini(c, a), maxi(c, a))] = true
	var bags := []
	bags.resize(count)
	for index in count:
		bags[index] = []
	for key in edges:
		var edge := key as Vector2i
		bags[edge.x].append(edge.y)
		bags[edge.y].append(edge.x)
	var out: Array[PackedInt32Array] = []
	out.resize(count)
	for index in count:
		out[index] = PackedInt32Array(bags[index])
	return out


func _icosphere(subdiv: int) -> Dictionary:
	const T := 1.618033988749895
	var points: Array[Vector3] = [
		Vector3(-1, T, 0), Vector3(1, T, 0), Vector3(-1, -T, 0), Vector3(1, -T, 0),
		Vector3(0, -1, T), Vector3(0, 1, T), Vector3(0, -1, -T), Vector3(0, 1, -T),
		Vector3(T, 0, -1), Vector3(T, 0, 1), Vector3(-T, 0, -1), Vector3(-T, 0, 1),
	]
	for index in points.size():
		points[index] = points[index].normalized()
	var faces: Array[Vector3i] = [
		Vector3i(0, 11, 5), Vector3i(0, 5, 1), Vector3i(0, 1, 7),
		Vector3i(0, 7, 10), Vector3i(0, 10, 11), Vector3i(1, 5, 9),
		Vector3i(5, 11, 4), Vector3i(11, 10, 2), Vector3i(10, 7, 6),
		Vector3i(7, 1, 8), Vector3i(3, 9, 4), Vector3i(3, 4, 2),
		Vector3i(3, 2, 6), Vector3i(3, 6, 8), Vector3i(3, 8, 9),
		Vector3i(4, 9, 5), Vector3i(2, 4, 11), Vector3i(6, 2, 10),
		Vector3i(8, 6, 7), Vector3i(9, 8, 1),
	]
	for _pass in subdiv:
		var midpoints: Dictionary = {}
		var next: Array[Vector3i] = []
		for face in faces:
			var ab := _midpoint(face.x, face.y, points, midpoints)
			var bc := _midpoint(face.y, face.z, points, midpoints)
			var ca := _midpoint(face.z, face.x, points, midpoints)
			next.append(Vector3i(face.x, ab, ca))
			next.append(Vector3i(face.y, bc, ab))
			next.append(Vector3i(face.z, ca, bc))
			next.append(Vector3i(ab, bc, ca))
		faces = next
	var packed_faces := PackedInt32Array()
	packed_faces.resize(faces.size() * 3)
	for index in faces.size():
		packed_faces[index * 3] = faces[index].x
		packed_faces[index * 3 + 1] = faces[index].y
		packed_faces[index * 3 + 2] = faces[index].z
	var packed_verts := PackedVector3Array()
	packed_verts.resize(points.size())
	for index in points.size():
		packed_verts[index] = points[index]
	return {"vertices": packed_verts, "faces": packed_faces}


func _midpoint(
		a: int,
		b: int,
		points: Array[Vector3],
		midpoints: Dictionary
	) -> int:
	var key := Vector2i(mini(a, b), maxi(a, b))
	if midpoints.has(key):
		return int(midpoints[key])
	var made := points.size()
	points.append((points[a] + points[b]).normalized())
	midpoints[key] = made
	return made
