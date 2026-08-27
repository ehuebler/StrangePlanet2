class_name PatchCity
extends Node3D

## One generated city sitting on its patch.
##
## Phase 0 draws the layout: district tiles and a floating loop, no collision.
## Phase 1 paves grouped district tiles as level slabs (peak plus a lift,
## thickness into the hill). A merged pad that stands more than 20 m off the
## ground is split and paved again as a lower slab. Then a thick highway that
## stays above those slabs, then exits that leave the highway at its real deck.
## Phase 2 draws the city map from those paved outlines, names every district,
## the road and each exit, then lays streets, alleys and buildings on the pads
## — ghosted, no collision — and keeps them as [CityPlace] records with type,
## health, variant and location. Those names appear on the HUD mini-map rather
## than as world labels.
## Phase 3 builds the city: solid buildings on the pad, painted pavement
## (black roads, light-pink walk), and street lamps that light at night.
## Phase 4 paints the walks and facades: district ground patterns, then
## windows, doors and night glow.

const PAD_GROUP := &"city_pads"
const MAP_GROUP := &"city_maps"
const PHASE_LAYOUT := 0
const PHASE_PAVED := 1
const PHASE_MAPPED := 2
const PHASE_BUILT := 3
const PHASE_PAINTED := 4
const PALETTE: UIPalette = preload("res://ui/themes/ui_palette.tres")
const FABRIC := preload("res://game/city/patch_fabric.gd")
const WALL_SHADER: Shader = preload("res://game/city/city_wall.gdshader")
const WINDOW_SHADER: Shader = preload("res://game/city/city_window.gdshader")
const GROUND_SHADER: Shader = preload("res://game/city/city_ground.gdshader")
const SURFACE_MATERIAL: ShaderMaterial = preload("res://game/planet/planet_surface.tres")
const MAP_FONT: FontFile = preload("res://fonts/Bungee-Regular.ttf")
const CITY_BUILDING_SCRIPT := preload("res://game/city/city_building.gd")
const BAKE := preload("res://game/city/patch_city_bake.gd")

const DISTRICT_LIFT := 2.5
## Level slab: one height for a whole touching group, a little above its peak.
const GROUND_LIFT := 0.8
const GROUND_EMBED := 3.0
## Walkable apron from a pad rim down to the true surface. 0.18 is about
## 10 degrees, steep enough to finish in a short run without a cliff.
const RAMP_GRADE := 0.18
const RAMP_WIDTH := 8.0
const RAMP_MIN_DROP := 0.55
const RAMP_MIN_RUN := 6.0
const RAMP_MAX_RUN := 52.0
const RAMP_SPACING := 42.0
const RAMP_CLEAR := 8.0
const RAMP_THICK := 0.48
## How far the walkable top sits above the true surface. Chunk interpolation
## bows the planet mesh above a single sample; too little lift leaves an
## invisible collider in the gap under the pad.
const APRON_CLEAR := 0.85
const APRON_VISUAL := 0.55
## If a merged pad sits this far above the ground, that stretch is split off
## and paved again as its own, lower slab.
const PAD_FLOAT := 20.0
## A district whose pad is under the true surface on more than this share of
## its area is lifted as a whole so streets and buildings sit on the slab.
const BURIED_SHARE := 0.40
const PAD_TERRACE_DEPTH := 8
## How finely the pad hunts for the true surface under it. Hoodoos are a few
## metres across and the first feature spacing fades, so a 22 m tile sample
## never sees their tips.
const PAD_PEAK_STEP := 0.75
## Fine-only relief the pad will not stamp. Matches the layout skip so a
## hoodoo field is a hole in the city instead of a slab through the spikes.
const SPIKE_RELIEF := 5.5
## Paving grid as a share of a district tile. Fine enough that a shoreline can
## curve instead of tracing the 22 m layout squares.
const PAD_FINE := 0.18
## Disk stamped for each layout tile, in district-cell metres, so neighbours
## melt into one blob and the outline is not a sawtooth of squares.
const PAD_STAMP := 0.72
const PAD_ROUNDS := 2
const HIGHWAY_OVER_PAD := 0.5
const HIGHWAY_THICK := 0.42
const EXIT_THICK := 0.38
## Metres the ramp runs along the highway shoulder before it peels.
const EXIT_MERGE_RUN := 48.0
const EXIT_HANDLE := 110.0
const EXIT_STEP := 2.4
## How much the ramp overlaps the highway edge, metres. Inner edge meets the
## shoulder instead of the centreline.
const EXIT_OVERLAP := 0.9
const ROAD_LIFT := 9.0
const ROAD_STEP := 6.0
const LOOP_HALF := 11.0
const HIGHWAY_HALF := 8.0
const HIGHWAY_LIFT := 6.0
const HIGHWAY_MIN_LIFT := 2.4
const HIGHWAY_STEP := 5.0
const HIGHWAY_SMOOTH := 180.0
## Steep is fine; this is the cap on height change per metre of run so a pad
## edge becomes a ramp instead of a fold.
const HIGHWAY_GRADE := 0.22
const EXIT_GRADE := 0.28
## How far the pave pass looks when it patches a sharp fold in the deck.
const HIGHWAY_PATCH_SPAN := 48.0
const HIGHWAY_PATCH_ROUNDS := 8
const DECK_ROUNDS := 2
const EXIT_HALF := 6.2
const ARTERIAL_HALF := 10.0
const COLLECTOR_HALF := 6.5
const LOCAL_HALF := 4.0
const LOOP_COLOR := Color(0.16, 0.16, 0.18, 1.0)
const HIGHWAY_COLOR := Color(0.18, 0.18, 0.20, 1.0)
const MAP_LIFT := 1.9
const MAP_DISTRICT_HALF := 2.0
const MAP_ROAD_HALF := 3.2
const MAP_EXIT_HALF := 2.4
const MAP_STEP := 8.0
const STREET_LIFT := 0.22
const FABRIC_ALPHA := 0.58
const VARIANT_RECT := 0
const VARIANT_CYLINDER := 1
const VARIANT_RECT_CAP := 2
const VARIANT_GABLE := 3
const VARIANT_ROUND_END := 4
const VARIANT_TAPER := 5
const VARIANT_POINT_HALF := 6
const VARIANT_SLANT_HALF := 7
const VARIANT_CYL_HALF := 8
const PAVEMENT_WALK := Color(1.0, 0.78, 0.84, 1.0)
const PAVEMENT_ROAD := Color(0.05, 0.05, 0.06, 1.0)
const PAVEMENT_LIFT := 0.06
const PAVEMENT_THICK := 0.55
## How far pavement walls bury into the true surface so a drop at the rim
## cannot be walked under.
const PAVEMENT_EMBED := 2.4
const PAVE_CHUNK := 8
## Crater depth that would punch a hole in the deck. Hole punching is off for
## now (full remesh hitch); the slab only absorbs depth.
const PAVEMENT_BREAK := 0.40
const PAVEMENT_SUB := 4
const PAINT_SUB := 4
const PAVEMENT_BLEND := 1.25
const WALL_SHADE := 7.0
const GROUND_GRASS := 0
const GROUND_RUST := 1
const GROUND_PURPLE := 2
const GROUND_BRICK := 3
const PAINT_SKY_DARK := 10
const PAINT_SKY_SILVER := 11
const PAINT_SKY_COPPER := 12
const PAINT_SKY_ORANGE := 13
const PAINT_NEON := 18
const TYPE_HOUSE := 0
const TYPE_TOWNHOUSE := 1
const TYPE_APARTMENT := 2
const TYPE_SHOP := 3
const TYPE_TOWER := 4
const TYPE_SKY := 5
const TYPE_LANDMARK := 6
const TYPE_TOWN_CENTER := 7
const GROUND_TEXEL := 0.38
const GROUND_TEX_MIN := 768
const GROUND_TEX_MAX := 4096
const LAMP_SPACING := 22.0
const LAMP_KEEP := 9.5
const LAMP_HEIGHT := 5.1
const LAMP_LIGHTS := 32
const LAMP_SEEK := 78.0
const LAMP_HOLD := 1.6
const LAMP_POOL_M := 13.0
const LAMP_MAP_MAX := 1024
const MINIMAP_NEAR := 78.0
const MINIMAP_FAR_ALT := 380.0
const STREET_LABEL_ALT := 120.0
const SPECIAL_NEAR := 25.0
const PATCH_NAME_ALT := 240.0
const COMPASS: PackedStringArray = [
	"North", "Northeast", "East", "Southeast",
	"South", "Southwest", "West", "Northwest",
]
## Layout tiles and paved slabs share one untyped grey. Zoning colour comes later.
const DISTRICT_COLOR := Color(0.32, 0.32, 0.34, 1.0)
const ARTERIAL_COLOR := Color(0.20, 0.20, 0.22, 1.0)
const COLLECTOR_COLOR := Color(0.25, 0.25, 0.27, 1.0)
const LOCAL_COLOR := Color(0.32, 0.32, 0.34, 1.0)

static var _flora_pads: Array = []
static var _flora_centres := PackedVector3Array()
static var _flora_coss := PackedFloat32Array()


class CityPlace extends RefCounted:
	## One named spot on a generated city, kept so later work (quests, the
	## coordinate plate, another city's map) can ask for a district or an exit
	## by id rather than by walking meshes.
	##
	## `id` is stable for the life of the city: `{patch}/{kind}/{key}`. `node_name`
	## is the [Landmark] that stands here, which is what [JournalDB] already keys
	## on. Coordinates use the same lat/lon frame as the coordinate plate.
	const KIND_DISTRICT := &"district"
	const KIND_ROAD := &"road"
	const KIND_EXIT := &"exit"
	const KIND_STREET := &"street"
	const KIND_ALLEY := &"alley"
	const KIND_BUILDING := &"building"
	const KIND_LANDMARK := &"landmark"
	const KIND_TOWN_CENTER := &"town_center"

	var id := ""
	var kind := KIND_DISTRICT
	var name := ""
	var node_name := ""
	var patch_id := -1
	var patch_name := ""
	var district_id := -1
	var direction := Vector3.UP
	var latitude := 0.0
	var longitude := 0.0
	var span := 0.0
	var typology := -1
	var variant := 0
	var design := ""
	var health := 0.0
	var max_health := 0.0
	var stories := 0.0
	var width := 0.0
	var depth := 0.0
	var lot_index := -1

	func bind(at: Vector3) -> void:
		direction = at.normalized()
		if direction.length_squared() < 0.5:
			direction = Vector3.UP
		latitude = rad_to_deg(asin(clampf(direction.y, -1.0, 1.0)))
		longitude = rad_to_deg(atan2(direction.x, direction.z))


class PadCover extends RefCounted:
	var centre := Vector3.UP
	var span_cos := 0.0
	var cell := 22.0
	var radius := 8000.0
	var east := Vector3.RIGHT
	var north := Vector3.FORWARD
	var keys: Dictionary = {}

	func covers(direction: Vector3) -> bool:
		var at := direction.normalized()
		if at.dot(centre) < span_cos:
			return false
		if keys.is_empty() or cell <= 0.1:
			return false
		var q := at - centre * at.dot(centre)
		var uv := Vector2(q.dot(east), q.dot(north)) * radius
		var key := Vector2i(roundi(uv.x / cell), roundi(uv.y / cell))
		return keys.has(key)


class PadIsland extends RefCounted:
	var cells: Dictionary = {}
	var dilated: Dictionary = {}
	var cell := 22.0
	var max_h := -1.0e9
	var min_h := 1.0e9
	var top_h := 0.0
	var bot_h := 0.0


var plan: PatchCityGenerator.Plan
var phase := PHASE_LAYOUT
## True when this node was restored from a baked PackedScene rather than
## generated in the running game.
var from_bake := false
## Named districts, road and exits after the map is drawn. Quest code looks
## these up by [member CityPlace.id] or by the landmark [member CityPlace.node_name].
var places: Array[CityPlace] = []
var _districts: MeshInstance3D
var _road: MeshInstance3D
var _ground: MeshInstance3D
var _highway: MeshInstance3D
var _ground_body: StaticBody3D
var _highway_body: StaticBody3D
var _apron: MeshInstance3D
var _apron_body: StaticBody3D
var _map: Node3D
var _map_mesh: MeshInstance3D
var _map_names: Node3D
var _map_marks: Node3D
var _fabric_streets: MeshInstance3D
var _fabric_buildings: MeshInstance3D
var _solid_buildings: MeshInstance3D
var _solid_body: StaticBody3D
var _paint_small: MeshInstance3D
var _paint_large: MeshInstance3D
var _windows_small: MeshInstance3D
var _windows_large: MeshInstance3D
var _window_small_mat: ShaderMaterial
var _window_large_mat: ShaderMaterial
var _wall_small_mat: ShaderMaterial
var _wall_large_mat: ShaderMaterial
var _pavement_mat: ShaderMaterial
var _apron_mat: ShaderMaterial
var _lot_root: Node3D
var _buildings: Array = []
var _pending_blasts: Array = []
var _planet_shape: PlanetShape
var _pavement: MeshInstance3D
var _pavement_body: StaticBody3D
var _pavement_holes: Dictionary = {}
var _pave_chunk_shapes: Dictionary = {}
var _hole_rim: MeshInstance3D
var _rubble: Node3D
var _break_image: Image
var _break_tex: ImageTexture
var _break_origin := Vector2.ZERO
var _break_span := Vector2.ONE
var _rim: MeshInstance3D
var _lamps: Node3D
var _lamp_bulb_mat: StandardMaterial3D
var _lamp_spots := PackedVector3Array()
var _lamp_uvs := PackedVector2Array()
var _lamp_map: ImageTexture
var _lamp_lights: Array[OmniLight3D] = []
var _lamp_bind := PackedInt32Array()
var _road_index: Array = []
var _road_bins: Dictionary = {}
var _wall_dist: Dictionary = {}
var _district_ground: Dictionary = {}
var _district_accent: Dictionary = {}
var _ground_image: Image
var _ground_tex: ImageTexture
var _ground_origin := Vector2.ZERO
var _ground_span := Vector2.ONE
var _dressed := false
var fabric: Dictionary = {}
var _fabric_layout = null
var _fabric_arteries: Dictionary = {}
## 2D strokes for the HUD mini-map, in the city's UV metre frame.
var minimap: Dictionary = {}
var _city_extent := 0.0
var _up := Vector3.UP
var _east := Vector3.RIGHT
var _north := Vector3.FORWARD
var _radius := 8000.0
var _pad: PadCover
var _pad_tops: Dictionary = {}
var _pad_owner: Dictionary = {}
var _pad_islands: Array = []
var _pad_cell := 22.0
var _highway_dirs := PackedVector3Array()
var _highway_deck := PackedFloat32Array()
var _highway_spur := PackedVector3Array()
var _exit_paths: Array = []


func apply(next: PatchCityGenerator.Plan, shape: PlanetShape) -> void:
	from_bake = false
	plan = next
	phase = PHASE_LAYOUT
	places.clear()
	name = "City_%s" % next.patch_name.replace(" ", "")
	_bind_frame(shape)
	_discard_node(_map)
	_map = null
	_map_mesh = null
	_map_names = null
	_map_marks = null
	_discard_node(_fabric_streets)
	_fabric_streets = null
	_discard_node(_fabric_buildings)
	_fabric_buildings = null
	_discard_node(_solid_buildings)
	_solid_buildings = null
	_discard_node(_solid_body)
	_solid_body = null
	_discard_node(_paint_small)
	_paint_small = null
	_discard_node(_paint_large)
	_paint_large = null
	_discard_node(_windows_small)
	_windows_small = null
	_discard_node(_windows_large)
	_windows_large = null
	_window_small_mat = null
	_window_large_mat = null
	_wall_small_mat = null
	_wall_large_mat = null
	_discard_node(_lot_root)
	_lot_root = null
	_buildings.clear()
	_pending_blasts.clear()
	if is_in_group(DamageHit.BUILDING_GROUP):
		remove_from_group(DamageHit.BUILDING_GROUP)
	_discard_node(_pavement)
	_pavement = null
	_pavement_mat = null
	_discard_node(_pavement_body)
	_pavement_body = null
	_pavement_holes.clear()
	_pave_chunk_shapes.clear()
	_discard_node(_hole_rim)
	_hole_rim = null
	_discard_node(_rubble)
	_rubble = null
	_break_image = null
	_break_tex = null
	_break_origin = Vector2.ZERO
	_break_span = Vector2.ONE
	_discard_node(_rim)
	_rim = null
	_discard_node(_apron)
	_apron = null
	_apron_mat = null
	_discard_node(_apron_body)
	_apron_body = null
	_pad_islands.clear()
	_discard_node(_lamps)
	_lamps = null
	_lamp_bulb_mat = null
	_lamp_spots = PackedVector3Array()
	_lamp_uvs = PackedVector2Array()
	_lamp_map = null
	_lamp_lights.clear()
	_lamp_bind = PackedInt32Array()
	_road_index.clear()
	_road_bins.clear()
	_wall_dist.clear()
	_district_ground.clear()
	_district_accent.clear()
	_ground_image = null
	_ground_tex = null
	_ground_origin = Vector2.ZERO
	_ground_span = Vector2.ONE
	_dressed = false
	fabric = {}
	minimap = {}
	_city_extent = 0.0
	set_process(false)
	_build_districts(shape)
	_build_road(shape)


func advance(shape: PlanetShape) -> bool:
	if plan == null or shape == null:
		return false
	if phase == PHASE_LAYOUT:
		phase = PHASE_PAVED
		_bind_frame(shape)
		_discard_node(_districts)
		_districts = null
		_discard_node(_road)
		_road = null
		_build_ground(shape)
		_build_highway(shape)
		_register_flora_pad()
		_clear_flora()
		return true
	if phase == PHASE_PAVED:
		phase = PHASE_MAPPED
		_bind_frame(shape)
		_name_map()
		_build_map(shape)
		if is_inside_tree() and not is_in_group(MAP_GROUP):
			add_to_group(MAP_GROUP)
		return true
	if phase == PHASE_MAPPED:
		phase = PHASE_BUILT
		_bind_frame(shape)
		_build_city(shape)
		return true
	if phase == PHASE_BUILT:
		phase = PHASE_PAINTED
		_bind_frame(shape)
		_dress_city(shape)
		return true
	return false


func capture_bake(layout_id := "first_planet") -> Resource:
	var bake = BAKE.new()
	bake.layout_id = layout_id
	if plan != null:
		bake.patch_id = plan.patch_id
		bake.patch_name = plan.patch_name
		bake.plan = _plan_to_wire(plan)
	bake.phase = phase
	bake.fabric = fabric.duplicate(true)
	bake.places = _places_to_wire()
	bake.minimap = minimap.duplicate(true)
	bake.pad_cell = _pad_cell
	_export_pad_grid(bake)
	bake.lamp_spots = _lamp_spots.duplicate()
	bake.highway_dirs = _highway_dirs.duplicate()
	bake.highway_deck = _highway_deck.duplicate()
	bake.highway_spur = _highway_spur.duplicate()
	bake.exit_paths = _exit_paths.duplicate(true)
	bake.ground_origin = _ground_origin
	bake.ground_span = _ground_span
	bake.ground_image = _ground_image
	bake.city_extent = city_extent()
	bake.dressed = _dressed
	bake.district_ground = _district_ground.duplicate()
	bake.district_accent = _district_accent.duplicate()
	bake.scene = _pack_tree()
	if bake.scene == null:
		push_error("patch_city: pack failed for %s phase %d"
			% [bake.patch_name, bake.phase])
	return bake


func restore_bake(bake: Resource, shape: PlanetShape) -> void:
	if bake == null:
		return
	from_bake = true
	plan = _plan_from_wire(bake.plan)
	phase = bake.phase
	if plan != null and not plan.patch_name.is_empty():
		name = "City_%s" % plan.patch_name.replace(" ", "")
	fabric = bake.fabric.duplicate(true)
	places.clear()
	for place in _places_from_wire(bake.places):
		places.append(place)
	minimap = bake.minimap.duplicate(true)
	_pad_cell = bake.pad_cell
	_import_pad_grid(bake)
	_lamp_spots = bake.lamp_spots.duplicate()
	_highway_dirs = bake.highway_dirs.duplicate()
	_highway_deck = bake.highway_deck.duplicate()
	_highway_spur = bake.highway_spur.duplicate()
	_exit_paths = bake.exit_paths.duplicate(true)
	_ground_origin = bake.ground_origin
	_ground_span = bake.ground_span
	_ground_image = bake.ground_image
	if _ground_image != null:
		_ground_tex = ImageTexture.create_from_image(_ground_image)
	_city_extent = bake.city_extent
	_dressed = bake.dressed
	_district_ground = bake.district_ground.duplicate()
	_district_accent = bake.district_accent.duplicate()
	_bind_frame(shape)
	_rebind_packed_nodes()
	_rebind_buildings(shape)
	_rebind_pavement()
	_rebind_lamps()
	if phase >= PHASE_BUILT:
		_index_city_roads()
		_place_lamps(shape)
		set_process(true)
	if phase >= PHASE_PAINTED:
		_refresh_baked_night_paint(shape)
	if phase >= PHASE_PAVED:
		_register_flora_pad()
	if phase >= PHASE_MAPPED and is_inside_tree() and not is_in_group(MAP_GROUP):
		add_to_group(MAP_GROUP)
	if phase >= PHASE_PAINTED and is_inside_tree() \
			and not is_in_group(DamageHit.BUILDING_GROUP):
		add_to_group(DamageHit.BUILDING_GROUP)


func _export_pad_grid(bake: Resource) -> void:
	var xs := PackedInt32Array()
	var ys := PackedInt32Array()
	var heights := PackedFloat32Array()
	xs.resize(_pad_tops.size())
	ys.resize(_pad_tops.size())
	heights.resize(_pad_tops.size())
	var index := 0
	for key in _pad_tops:
		var at: Vector2i = key
		xs[index] = at.x
		ys[index] = at.y
		heights[index] = float(_pad_tops[key])
		index += 1
	bake.pad_keys_x = xs
	bake.pad_keys_y = ys
	bake.pad_heights = heights
	var ox := PackedInt32Array()
	var oy := PackedInt32Array()
	var owners := PackedInt32Array()
	ox.resize(_pad_owner.size())
	oy.resize(_pad_owner.size())
	owners.resize(_pad_owner.size())
	index = 0
	for key in _pad_owner:
		var at: Vector2i = key
		ox[index] = at.x
		oy[index] = at.y
		owners[index] = int(_pad_owner[key])
		index += 1
	bake.pad_owner_x = ox
	bake.pad_owner_y = oy
	bake.pad_owners = owners


func _import_pad_grid(bake: Resource) -> void:
	_pad_tops.clear()
	_pad_owner.clear()
	var count := mini(bake.pad_keys_x.size(), bake.pad_keys_y.size())
	count = mini(count, bake.pad_heights.size())
	for index in count:
		_pad_tops[Vector2i(bake.pad_keys_x[index], bake.pad_keys_y[index])] = \
			bake.pad_heights[index]
	count = mini(bake.pad_owner_x.size(), bake.pad_owner_y.size())
	count = mini(count, bake.pad_owners.size())
	for index in count:
		_pad_owner[Vector2i(bake.pad_owner_x[index], bake.pad_owner_y[index])] = \
			bake.pad_owners[index]


func _rebind_packed_nodes() -> void:
	_districts = get_node_or_null("Districts") as MeshInstance3D
	_road = get_node_or_null("CityRoad") as MeshInstance3D
	_ground = get_node_or_null("DistrictGround") as MeshInstance3D
	_ground_body = get_node_or_null("DistrictGroundBody") as StaticBody3D
	_highway = get_node_or_null("Highway") as MeshInstance3D
	_highway_body = get_node_or_null("HighwayBody") as StaticBody3D
	_apron = get_node_or_null("CityApron") as MeshInstance3D
	if _apron == null:
		_apron = get_node_or_null("CityRamps") as MeshInstance3D
	_apron_body = get_node_or_null("CityApronBody") as StaticBody3D
	if _apron_body == null:
		_apron_body = get_node_or_null("CityRampsBody") as StaticBody3D
	_map = get_node_or_null("CityMap") as Node3D
	if is_instance_valid(_map):
		_map_mesh = _map.get_node_or_null("CityMapMesh") as MeshInstance3D
		_map_names = _map.get_node_or_null("StreetNames") as Node3D
		_map_marks = _map.get_node_or_null("SpecialMarks") as Node3D
	_fabric_streets = get_node_or_null("FabricStreets") as MeshInstance3D
	_fabric_buildings = get_node_or_null("FabricBuildings") as MeshInstance3D
	_solid_buildings = get_node_or_null("CityBuildings") as MeshInstance3D
	_solid_body = get_node_or_null("CityBuildingsBody") as StaticBody3D
	_paint_small = get_node_or_null("CityPaintSmall") as MeshInstance3D
	_paint_large = get_node_or_null("CityPaintLarge") as MeshInstance3D
	_windows_small = get_node_or_null("CityWindowsSmall") as MeshInstance3D
	_windows_large = get_node_or_null("CityWindowsLarge") as MeshInstance3D
	_lot_root = get_node_or_null("CityLots") as Node3D
	_pavement = get_node_or_null("PavementPaint") as MeshInstance3D
	_pavement_body = get_node_or_null("PavementPaintBody") as StaticBody3D
	_hole_rim = get_node_or_null("PavementBreaks") as MeshInstance3D
	_rubble = get_node_or_null("PavementRubble") as Node3D
	_rim = get_node_or_null("CityRim") as MeshInstance3D
	_lamps = get_node_or_null("CityLamps") as Node3D
	if is_instance_valid(_paint_small):
		_wall_small_mat = _paint_small.material_override as ShaderMaterial
	if is_instance_valid(_paint_large):
		_wall_large_mat = _paint_large.material_override as ShaderMaterial
	if is_instance_valid(_windows_small):
		_window_small_mat = _windows_small.material_override as ShaderMaterial
	if is_instance_valid(_windows_large):
		_window_large_mat = _windows_large.material_override as ShaderMaterial
	_ensure_wall_materials()
	_ensure_window_materials()
	if is_instance_valid(_paint_small):
		_paint_small.material_override = _wall_small_mat
	if is_instance_valid(_paint_large):
		_paint_large.material_override = _wall_large_mat
	if is_instance_valid(_windows_small):
		_windows_small.material_override = _window_small_mat
	if is_instance_valid(_windows_large):
		_windows_large.material_override = _window_large_mat


func _rebind_buildings(shape: PlanetShape) -> void:
	_buildings.clear()
	if not is_instance_valid(_lot_root):
		return
	var lots: Array = fabric.get("lots", [])
	for child in _lot_root.get_children():
		if not child.has_method(&"rebind"):
			continue
		var index := -1
		var child_name := String(child.name)
		if child_name.begins_with("Building_"):
			index = int(child_name.trim_prefix("Building_"))
		var lot: Dictionary = lots[index] if index >= 0 and index < lots.size() else {}
		child.rebind(self, index, lot, shape)
		_buildings.append(child)


func _rebind_pavement() -> void:
	_pave_chunk_shapes.clear()
	if is_instance_valid(_pavement_body):
		for child in _pavement_body.get_children():
			var collider := child as CollisionShape3D
			if collider == null:
				continue
			var n := String(collider.name)
			if not n.begins_with("Chunk_"):
				continue
			var parts := n.trim_prefix("Chunk_").split("_")
			if parts.size() < 2:
				continue
			_pave_chunk_shapes[Vector2i(int(parts[0]), int(parts[1]))] = collider
	if is_instance_valid(_pavement):
		var material := _pavement.material_override as ShaderMaterial
		if material != null:
			if _ground_tex == null:
				var mapped: Variant = material.get_shader_parameter(&"ground_map")
				if mapped is ImageTexture:
					_ground_tex = mapped
			material.set_shader_parameter(&"ground_map", _ground_tex)
			material.set_shader_parameter(&"map_span", _ground_span)
			material.set_shader_parameter(&"map_origin", _ground_origin)
			_pavement_mat = material
			_bind_lamp_map(material)


func _rebind_lamps() -> void:
	_lamp_lights.clear()
	_lamp_bulb_mat = null
	if not is_instance_valid(_lamps):
		return
	var bulbs := _lamps.get_node_or_null("Bulbs") as MultiMeshInstance3D
	if bulbs != null:
		_lamp_bulb_mat = bulbs.material_override as StandardMaterial3D
	for child in _lamps.get_children():
		var light := child as OmniLight3D
		if light != null:
			_lamp_lights.append(light)


func _refresh_baked_night_paint(shape: PlanetShape) -> void:
	if shape == null or _buildings.is_empty():
		return
	_ensure_window_materials()
	if is_instance_valid(_windows_small):
		_windows_small.material_override = _window_small_mat
	if is_instance_valid(_windows_large):
		_windows_large.material_override = _window_large_mat
	if not _baked_night_paint_stale():
		return
	_assign_paint_styles()
	for building in _buildings:
		if building == null or not is_instance_valid(building):
			continue
		if not building.has_method(&"refresh_facade"):
			continue
		var authored := false
		var large := false
		if building.has_method(&"uses_authored_design"):
			authored = bool(building.call(&"uses_authored_design"))
		if building.has_method(&"is_large"):
			large = bool(building.call(&"is_large"))
		if authored or large:
			building.call(&"refresh_facade")


func _baked_night_paint_stale() -> bool:
	var seen := 0
	var neon_trim := 0
	var white_panes := 0
	var colour_panes := 0
	for building in _buildings:
		if building == null or not is_instance_valid(building):
			continue
		if not building.has_method(&"is_large") or not bool(building.call(&"is_large")):
			continue
		seen += 1
		var hull: Mesh = building.call(&"hull_mesh") if building.has_method(&"hull_mesh") else null
		if hull != null and hull.get_surface_count() > 0:
			var cols: PackedColorArray = hull.surface_get_arrays(0)[Mesh.ARRAY_COLOR]
			var step := maxi(int(cols.size() / 24), 1)
			var index := 0
			while index < cols.size():
				if absi(int(round(cols[index].a * 20.0)) - PAINT_NEON) == 0:
					neon_trim += 1
					break
				index += step
		var glass: Mesh = building.call(&"glass_mesh") if building.has_method(&"glass_mesh") else null
		if glass != null and glass.get_surface_count() > 0:
			var panes: PackedColorArray = glass.surface_get_arrays(0)[Mesh.ARRAY_COLOR]
			var step := maxi(int(panes.size() / 20), 1)
			var index := 0
			while index < panes.size():
				var pane: Color = panes[index]
				var sat := maxf(pane.r, maxf(pane.g, pane.b)) - minf(pane.r, minf(pane.g, pane.b))
				var lum := pane.r * 0.22 + pane.g * 0.67 + pane.b * 0.11
				if sat > 0.28:
					colour_panes += 1
				elif lum > 0.72:
					white_panes += 1
				index += step
		if seen >= 14:
			break
	return seen > 0 and (neon_trim == 0 or white_panes == 0 or colour_panes == 0)


func _pack_tree() -> PackedScene:
	_own_tree(self, self)
	var packed := PackedScene.new()
	if packed.pack(self) != OK:
		return null
	return packed


func _own_tree(node: Node, owner: Node) -> void:
	for child in node.get_children():
		child.owner = owner
		_own_tree(child, owner)


func _plan_to_wire(next: PatchCityGenerator.Plan) -> Dictionary:
	if next == null:
		return {}
	var districts: Array = []
	for district in next.districts:
		districts.append({
			"id": district.id,
			"kind": district.kind,
			"name": district.name,
			"colour": district.colour,
			"centre": district.centre,
			"dirs": district.dirs,
			"span": district.span,
			"grade": district.grade,
		})
	var streets: Array = []
	for street in next.streets:
		streets.append({
			"rank": street.rank,
			"dirs": street.dirs,
			"terrace": street.terrace,
		})
	var exits: Array = []
	for exit in next.exits:
		exits.append({
			"road": exit.road,
			"land": exit.land,
			"district_id": exit.district_id,
			"name": exit.name,
		})
	return {
		"patch_id": next.patch_id,
		"patch_name": next.patch_name,
		"road_name": next.road_name,
		"cell_size": next.cell_size,
		"loop": next.loop,
		"extension": next.extension,
		"nodes": next.nodes,
		"districts": districts,
		"streets": streets,
		"exits": exits,
	}


func _plan_from_wire(wire: Dictionary) -> PatchCityGenerator.Plan:
	var next := PatchCityGenerator.Plan.new()
	if wire.is_empty():
		return next
	next.patch_id = int(wire.get("patch_id", -1))
	next.patch_name = String(wire.get("patch_name", ""))
	next.road_name = String(wire.get("road_name", ""))
	next.cell_size = float(wire.get("cell_size", PatchCityGenerator.CELL))
	next.loop = PackedVector3Array(wire.get("loop", PackedVector3Array()))
	next.extension = PackedVector3Array(wire.get("extension", PackedVector3Array()))
	next.nodes = PackedVector3Array(wire.get("nodes", PackedVector3Array()))
	for row_variant in wire.get("districts", []):
		if not row_variant is Dictionary:
			continue
		var row: Dictionary = row_variant
		var district := PatchCityGenerator.District.new()
		district.id = int(row.get("id", -1))
		district.kind = int(row.get("kind", 0))
		district.name = String(row.get("name", ""))
		district.colour = row.get("colour", Color.WHITE)
		district.centre = row.get("centre", Vector3.UP)
		district.dirs = PackedVector3Array(row.get("dirs", PackedVector3Array()))
		district.span = float(row.get("span", 0.0))
		district.grade = float(row.get("grade", 0.0))
		next.districts.append(district)
	for row_variant in wire.get("streets", []):
		if not row_variant is Dictionary:
			continue
		var row: Dictionary = row_variant
		var street := PatchCityGenerator.Street.new()
		street.rank = int(row.get("rank", 0))
		street.dirs = PackedVector3Array(row.get("dirs", PackedVector3Array()))
		street.terrace = bool(row.get("terrace", false))
		next.streets.append(street)
	for row_variant in wire.get("exits", []):
		if not row_variant is Dictionary:
			continue
		var row: Dictionary = row_variant
		var exit := PatchCityGenerator.RoadExit.new()
		exit.road = row.get("road", Vector3.UP)
		exit.land = row.get("land", Vector3.UP)
		exit.district_id = int(row.get("district_id", -1))
		exit.name = String(row.get("name", ""))
		next.exits.append(exit)
	return next


func _places_to_wire() -> Array:
	var out: Array = []
	for place in places:
		out.append({
			"id": place.id,
			"kind": String(place.kind),
			"name": place.name,
			"node_name": place.node_name,
			"patch_id": place.patch_id,
			"patch_name": place.patch_name,
			"district_id": place.district_id,
			"direction": place.direction,
			"latitude": place.latitude,
			"longitude": place.longitude,
			"span": place.span,
			"typology": place.typology,
			"variant": place.variant,
			"design": place.design,
			"health": place.health,
			"max_health": place.max_health,
			"stories": place.stories,
			"width": place.width,
			"depth": place.depth,
			"lot_index": place.lot_index,
		})
	return out


func _places_from_wire(wire: Array) -> Array:
	var out: Array[CityPlace] = []
	for row_variant in wire:
		if not row_variant is Dictionary:
			continue
		var row: Dictionary = row_variant
		var place := CityPlace.new()
		place.id = String(row.get("id", ""))
		place.kind = StringName(String(row.get("kind", "district")))
		place.name = String(row.get("name", ""))
		place.node_name = String(row.get("node_name", ""))
		place.patch_id = int(row.get("patch_id", -1))
		place.patch_name = String(row.get("patch_name", ""))
		place.district_id = int(row.get("district_id", -1))
		place.direction = row.get("direction", Vector3.UP)
		place.latitude = float(row.get("latitude", 0.0))
		place.longitude = float(row.get("longitude", 0.0))
		place.span = float(row.get("span", 0.0))
		place.typology = int(row.get("typology", -1))
		place.variant = int(row.get("variant", 0))
		place.design = String(row.get("design", ""))
		place.health = float(row.get("health", 0.0))
		place.max_health = float(row.get("max_health", 0.0))
		place.stories = float(row.get("stories", 0.0))
		place.width = float(row.get("width", 0.0))
		place.depth = float(row.get("depth", 0.0))
		place.lot_index = int(row.get("lot_index", -1))
		out.append(place)
	return out


func place_named(id: String) -> CityPlace:
	for place in places:
		if place.id == id:
			return place
	return null


static func find_place(tree: SceneTree, id: String) -> CityPlace:
	if tree == null or id.is_empty():
		return null
	for node in tree.get_nodes_in_group(MAP_GROUP):
		var city := node as PatchCity
		if city == null:
			continue
		var place := city.place_named(id)
		if place != null:
			return place
	return null


func contains_world(at: Vector3) -> bool:
	if phase < PHASE_MAPPED:
		return false
	var uv := world_to_uv(at)
	if _pad != null:
		var local := to_local(at) if is_inside_tree() else at
		if local.length_squared() > 0.01 and _pad.covers(local.normalized()):
			return true
	return uv.length() <= city_extent() + 90.0


func world_to_uv(at: Vector3) -> Vector2:
	var local := to_local(at) if is_inside_tree() else at
	if local.length_squared() < 0.0001:
		return Vector2.ZERO
	return _to_uv(local.normalized())


func place_uv(place: CityPlace) -> Vector2:
	return _to_uv(place.direction)


func heading_uv(forward: Vector3) -> Vector2:
	var local := forward
	if is_inside_tree():
		local = global_transform.basis.inverse() * forward
	var q := local - _up * local.dot(_up)
	var uv := Vector2(q.dot(_east), q.dot(_north))
	if uv.length_squared() < 0.0001:
		return Vector2(0, 1)
	return uv.normalized()


func city_extent() -> float:
	return _city_extent if _city_extent > 1.0 else _measure_extent()


func minimap_view_metres(altitude: float) -> float:
	var far := maxf(city_extent() * 0.62, 420.0)
	var t := clampf((altitude - 6.0) / MINIMAP_FAR_ALT, 0.0, 1.0)
	t = t * t * (3.0 - 2.0 * t)
	return lerpf(MINIMAP_NEAR, far, t)


func refresh_map(overlay_on: bool, eye: Vector3) -> void:
	if not is_instance_valid(_map):
		return
	if not overlay_on or phase < PHASE_MAPPED:
		_map.visible = false
		return
	_map.visible = true
	var alt := _eye_altitude(eye)
	var inside := contains_world(eye)
	if is_instance_valid(_map_mesh):
		_map_mesh.visible = false
	if is_instance_valid(_map_names):
		_map_names.visible = inside and alt < STREET_LABEL_ALT
	if is_instance_valid(_map_marks):
		for child in _map_marks.get_children():
			var mark := child as Node3D
			if mark == null:
				continue
			var away := eye.distance_to(mark.global_position)
			mark.visible = inside and away > SPECIAL_NEAR
			if mark.visible:
				var up := mark.global_position.normalized()
				var toward := eye - mark.global_position
				if toward.length_squared() > 0.25 and absf(up.dot(toward.normalized())) < 0.995:
					mark.look_at(eye, up)


func world_centre() -> Vector3:
	var local := _up.normalized() * _radius
	return global_transform * local if is_inside_tree() else local


func world_up() -> Vector3:
	var up := _up.normalized()
	if not is_inside_tree():
		return up
	return (global_transform.basis * up).normalized()


func hover_point(clearance := 96.0) -> Vector3:
	var up := _up.normalized()
	var height := 0.0
	for key in _pad_tops:
		height = maxf(height, float(_pad_tops[key]))
	var planet := _planet_host()
	if height < 0.5 and planet != null and planet.shape != null:
		height = planet.shape.elevation(up, 0.0)
	var local := up * (_radius + height + maxf(clearance, 8.0))
	return global_transform * local if is_inside_tree() else local


static func flora_covers(direction: Vector3) -> bool:
	var at := direction.normalized()
	for pad in _flora_pads:
		if pad.covers(at):
			return true
	return false


## Intact city deck under this bearing, which is what stops a crater settle
## pulling a body through pavement that is still there.
static func deck_blocks(direction: Vector3, tree: SceneTree) -> bool:
	return not is_nan(deck_radius(direction, tree))


## Planet-local radius of intact pavement under this bearing, or NAN when the
## ground there is the height field rather than a city deck.
static func deck_radius(direction: Vector3, tree: SceneTree) -> float:
	if tree == null:
		return NAN
	var at := direction.normalized()
	for node in tree.get_nodes_in_group(PAD_GROUP):
		var city := node as PatchCity
		if city == null or not city.has_intact_pavement(at):
			continue
		var top := city._pad_top_at(at)
		if is_nan(top):
			continue
		return city._radius + top + PAVEMENT_LIFT
	return NAN


func has_intact_pavement(direction: Vector3) -> bool:
	if phase < PHASE_BUILT or _pad_tops.is_empty() or _pad_cell <= 0.1:
		return false
	var at := direction.normalized()
	if _pad != null and not _pad.covers(at):
		return false
	var uv := _to_uv(at)
	var key := Vector2i(roundi(uv.x / _pad_cell), roundi(uv.y / _pad_cell))
	return _pad_tops.has(key) and not _pavement_holes.has(key)


func pavement_hole_count() -> int:
	return _pavement_holes.size()


## The paved deck does not crater. Hits still spend depth on the slab so the
## ground under a city is not carved out from below.
func absorb_scar(scar: TerrainScars.Scar) -> float:
	if scar == null or phase < PHASE_BUILT or _pad_tops.is_empty() or _pad_cell <= 0.1:
		return 0.0
	if scar.depth < 0.05 or scar.radius < 0.4:
		return 0.0
	scar.settle()
	var at := scar.direction.normalized()
	if at.length_squared() < 0.5:
		return 0.0
	if _pad != null and not _pad.covers(at):
		return 0.0
	if not has_intact_pavement(at):
		return 0.0
	return minf(scar.depth, PAVEMENT_THICK)


static func flora_centres() -> PackedVector3Array:
	return _flora_centres


static func flora_coss() -> PackedFloat32Array:
	return _flora_coss


func clear_flora() -> void:
	_clear_flora()


func _notification(what: int) -> void:
	# Reparenting fires tree_exiting without destroying the city. Only drop the
	# flora pad when this node is actually going away.
	if what == NOTIFICATION_PREDELETE:
		_unregister_flora_pad()


func _bind_frame(shape: PlanetShape) -> void:
	_planet_shape = shape
	_radius = shape.radius
	_up = Vector3.UP
	if plan != null:
		var acc := Vector3.ZERO
		for district in plan.districts:
			acc += district.centre * float(maxi(district.dirs.size(), 1))
		for direction in plan.loop:
			acc += direction
		if acc.length_squared() > 0.001:
			_up = acc.normalized()
	_east = _up.cross(Vector3.UP if absf(_up.y) < 0.9 else Vector3.RIGHT).normalized()
	_north = _up.cross(_east)


func _build_districts(shape: PlanetShape) -> void:
	_discard_node(_districts)
	_districts = null
	if plan == null or plan.districts.is_empty() or shape == null:
		return
	var st := SurfaceTool.new()
	st.begin(Mesh.PRIMITIVE_TRIANGLES)
	var half := plan.cell_size * 0.40
	for district in plan.districts:
		for direction in district.dirs:
			var up := direction.normalized()
			var east := up.cross(Vector3.UP if absf(up.y) < 0.9 else Vector3.RIGHT).normalized()
			var north := up.cross(east)
			var corners: Array[Vector3] = []
			var offsets: Array[Vector2] = [
				Vector2(-half, -half), Vector2(half, -half),
				Vector2(half, half), Vector2(-half, half),
			]
			for step in offsets:
				var at := (up + (east * step.x + north * step.y) / shape.radius).normalized()
				corners.append(shape.surface_point(at) + at * DISTRICT_LIFT)
			_quad(st, corners[0], corners[1], corners[2], corners[3], DISTRICT_COLOR)
	_districts = _commit_mesh(st, "Districts", true)


func _build_road(shape: PlanetShape) -> void:
	_discard_node(_road)
	_road = null
	if plan == null or shape == null:
		return
	var st := SurfaceTool.new()
	st.begin(Mesh.PRIMITIVE_TRIANGLES)
	_ribbon(st, shape, plan.loop, LOOP_HALF, LOOP_COLOR, ROAD_LIFT)
	_ribbon(st, shape, plan.extension, LOOP_HALF * 0.72, LOOP_COLOR, ROAD_LIFT)
	_road = _commit_mesh(st, "CityRoad", true)
	if is_instance_valid(_road):
		_road.sorting_offset = 2.0


func _build_ground(shape: PlanetShape) -> void:
	_discard_node(_ground)
	_ground = null
	_discard_node(_ground_body)
	_ground_body = null
	_discard_node(_apron)
	_apron = null
	_apron_mat = null
	_discard_node(_apron_body)
	_apron_body = null
	_pad_tops.clear()
	_pad_owner.clear()
	_pad_islands.clear()
	if plan == null or plan.districts.is_empty():
		return
	var st := SurfaceTool.new()
	st.begin(Mesh.PRIMITIVE_TRIANGLES)
	var islands := _group_islands(shape)
	_lift_buried_pads(shape, islands)
	_pad_islands = islands
	for island in islands:
		_emit_island(st, shape, island)
	_ground = _commit_mesh(st, "DistrictGround", false)
	_ground_body = _collide(
		_ground.mesh if _ground != null else null, "DistrictGroundBody")
	_emit_island_aprons(shape, islands)


func _build_highway(shape: PlanetShape) -> void:
	_discard_node(_highway)
	_highway = null
	_discard_node(_highway_body)
	_highway_body = null
	if plan == null:
		return
	_highway_dirs = PackedVector3Array()
	_highway_deck = PackedFloat32Array()
	_highway_spur = PackedVector3Array()
	_exit_paths.clear()
	var st := SurfaceTool.new()
	st.begin(Mesh.PRIMITIVE_TRIANGLES)
	var loop := _pave_run(shape, _densify_path(shape, plan.loop, true), true, HIGHWAY_GRADE)
	var loop_samples: PackedVector3Array = loop["dirs"]
	var loop_deck: PackedFloat32Array = loop["deck"]
	_highway_dirs = loop_samples
	_highway_deck = loop_deck
	_emit_highway_strip(
		st, loop_samples, loop_deck, HIGHWAY_HALF, HIGHWAY_THICK, true)
	_highway_spur = _graded_highway(st, shape, plan.extension, HIGHWAY_HALF * 0.72)
	var highway := _curve_from_run(loop_samples, loop_deck, true)
	for exit in plan.exits:
		_emit_exit(st, shape, exit, highway)
	_highway = _commit_mesh(st, "Highway", false)
	_highway_body = _collide(
		_highway.mesh if _highway != null else null, "HighwayBody")


func _group_islands(shape: PlanetShape) -> Array:
	var coarse := plan.cell_size
	var cell := maxf(coarse * PAD_FINE, 3.2)
	_pad_cell = cell
	var stamp := coarse * PAD_STAMP
	var reach := int(ceili(stamp / cell))
	var owned: Dictionary = {}
	var heights: Dictionary = {}
	for district in plan.districts:
		for direction in district.dirs:
			var uv := _to_uv(direction)
			var height := shape.elevation(direction, coarse)
			var cx := roundi(uv.x / cell)
			var cy := roundi(uv.y / cell)
			for ox in range(-reach, reach + 1):
				for oy in range(-reach, reach + 1):
					var key := Vector2i(cx + ox, cy + oy)
					var at := Vector2(float(key.x) * cell, float(key.y) * cell)
					if at.distance_to(uv) > stamp:
						continue
					if not owned.has(key) or height > float(heights[key]):
						owned[key] = district.id
						heights[key] = height
	_drop_spiky_keys(shape, owned, cell)
	var prune: Array = []
	for key in heights:
		if not owned.has(key):
			prune.append(key)
	for key in prune:
		heights.erase(key)
	var peaks: Dictionary = {}
	var floors: Dictionary = {}
	var seen: Dictionary = {}
	var islands: Array = []
	for start in owned:
		if seen.has(start):
			continue
		var island := PadIsland.new()
		island.cell = cell
		var stack: Array = [start]
		while not stack.is_empty():
			var at: Vector2i = stack.pop_back()
			if seen.has(at) or not owned.has(at):
				continue
			seen[at] = true
			island.cells[at] = DISTRICT_COLOR
			for ox in range(-1, 2):
				for oy in range(-1, 2):
					if ox == 0 and oy == 0:
						continue
					var next := Vector2i(at.x + ox, at.y + oy)
					if owned.has(next) and not seen.has(next):
						stack.append(next)
		if island.cells.is_empty():
			continue
		islands.append_array(
			_terrace_island(island, owned, shape, cell, peaks, floors, 0))
	return islands


func _terrace_island(
		island: PadIsland,
		owned: Dictionary,
		shape: PlanetShape,
		cell: float,
		peaks: Dictionary,
		floors: Dictionary,
		depth: int
	) -> Array:
	if island.cells.is_empty():
		return []
	_dilate_island(island, owned)
	_drop_spiky_keys(shape, island.dilated, cell)
	_drop_spiky_keys(shape, island.cells, cell)
	if island.cells.is_empty():
		return []
	_fill_island_holes(island, owned)
	_drop_spiky_keys(shape, island.dilated, cell)
	_survey_keys(shape, island.dilated, cell, peaks, floors)
	_apply_island_heights(island, peaks, floors)
	if depth >= PAD_TERRACE_DEPTH:
		return [_finish_island(island, owned)]
	var core_top := -1.0e9
	for key in island.cells:
		core_top = maxf(core_top, float(peaks.get(key, -1.0e9)))
	core_top += GROUND_LIFT
	var keep: Dictionary = {}
	var drop: Dictionary = {}
	for key in island.cells:
		var ground := float(peaks.get(key, core_top))
		if core_top - ground > PAD_FLOAT:
			drop[key] = island.cells[key]
		else:
			keep[key] = island.cells[key]
	if drop.is_empty() or keep.is_empty():
		return [_finish_island(island, owned)]
	var out: Array = []
	var high := PadIsland.new()
	high.cell = cell
	high.cells = keep
	out.append_array(
		_terrace_island(high, owned, shape, cell, peaks, floors, depth + 1))
	for part in _connected_cells(drop):
		var low := PadIsland.new()
		low.cell = cell
		low.cells = part
		out.append_array(
			_terrace_island(low, owned, shape, cell, peaks, floors, depth + 1))
	return out


func _finish_island(island: PadIsland, owned: Dictionary) -> PadIsland:
	var fallback := -1
	for key in island.cells:
		fallback = int(owned.get(key, -1))
		break
	for key in island.dilated:
		_pad_tops[key] = island.top_h
		_pad_owner[key] = int(owned.get(key, fallback))
	return island


func _lift_buried_pads(shape: PlanetShape, islands: Array) -> void:
	if shape == null or _pad_tops.is_empty():
		return
	var cell := _pad_cell
	var by_district: Dictionary = {}
	for key in _pad_owner:
		var district_id: int = int(_pad_owner[key])
		if district_id < 0:
			continue
		var keys: Array = by_district.get(district_id, [])
		keys.append(key)
		by_district[district_id] = keys
	for district_id in by_district:
		var keys: Array = by_district[district_id]
		if keys.is_empty():
			continue
		var buried := 0
		var ceiling := -1.0e9
		for key in keys:
			var at: Vector2i = key
			var pad := float(_pad_tops.get(at, -1.0e9))
			var peak := _cell_ground_peak(shape, at, cell)
			ceiling = maxf(ceiling, peak)
			if peak > pad + 0.15:
				buried += 1
		if float(buried) / float(keys.size()) <= BURIED_SHARE:
			continue
		var lifted := ceiling + GROUND_LIFT
		for key in keys:
			_pad_tops[key] = maxf(float(_pad_tops.get(key, lifted)), lifted)
	for island in islands:
		var slab: PadIsland = island
		var ring := _chaikin_loop(_island_outline(slab.dilated, cell), PAD_ROUNDS)
		var outline_n := ring.size()
		var outline_buried := 0
		var pad_top := slab.top_h
		for key in slab.dilated:
			pad_top = maxf(pad_top, float(_pad_tops.get(key, pad_top)))
		var outline_top := slab.top_h
		for point in ring:
			var ground := shape.elevation(_from_uv(point), 0.0)
			outline_top = maxf(outline_top, ground + GROUND_LIFT)
			if ground > slab.top_h + 0.15:
				outline_buried += 1
		var lift_outline := (
			outline_n > 0
			and float(outline_buried) / float(outline_n) > BURIED_SHARE)
		var island_lifted := pad_top > slab.top_h + 0.05
		if not island_lifted and not lift_outline:
			continue
		if lift_outline:
			pad_top = maxf(pad_top, outline_top)
		slab.top_h = pad_top
		for key in slab.dilated:
			_pad_tops[key] = slab.top_h


func _cell_ground_peak(shape: PlanetShape, at: Vector2i, cell: float) -> float:
	var origin := Vector2(float(at.x) * cell, float(at.y) * cell)
	var inset := cell * 0.35
	var peak := -1.0e9
	var probes := PackedVector2Array()
	probes.append(Vector2.ZERO)
	probes.append(Vector2(-inset, -inset))
	probes.append(Vector2(inset, -inset))
	probes.append(Vector2(inset, inset))
	probes.append(Vector2(-inset, inset))
	probes.append(Vector2(-inset, 0.0))
	probes.append(Vector2(inset, 0.0))
	probes.append(Vector2(0.0, -inset))
	probes.append(Vector2(0.0, inset))
	for offset in probes:
		peak = maxf(peak, shape.elevation(_from_uv(origin + offset), 0.0))
	return peak


func _drop_spiky_keys(shape: PlanetShape, keys: Dictionary, cell: float) -> void:
	if keys.is_empty() or cell <= 0.1:
		return
	var gone: Array = []
	for key in keys:
		var at: Vector2i = key
		if _cell_has_spikes(shape, at, cell):
			gone.append(at)
	for key in gone:
		keys.erase(key)


func _cell_has_spikes(shape: PlanetShape, at: Vector2i, cell: float) -> bool:
	var origin := Vector2(float(at.x) * cell, float(at.y) * cell)
	var floor_h := shape.elevation(_from_uv(origin), cell)
	return _cell_ground_peak(shape, at, cell) - floor_h > SPIKE_RELIEF


func _apply_island_heights(
		island: PadIsland,
		peaks: Dictionary,
		floors: Dictionary
	) -> void:
	island.max_h = -1.0e9
	island.min_h = 1.0e9
	for key in island.dilated:
		island.max_h = maxf(island.max_h, float(peaks.get(key, island.max_h)))
		island.min_h = minf(island.min_h, float(floors.get(key, island.min_h)))
	island.top_h = island.max_h + GROUND_LIFT
	island.bot_h = island.min_h - GROUND_EMBED


func _connected_cells(cells: Dictionary) -> Array:
	var seen: Dictionary = {}
	var groups: Array = []
	for start in cells:
		if seen.has(start):
			continue
		var group: Dictionary = {}
		var stack: Array = [start]
		while not stack.is_empty():
			var at: Vector2i = stack.pop_back()
			if seen.has(at) or not cells.has(at):
				continue
			seen[at] = true
			group[at] = cells[at]
			for ox in range(-1, 2):
				for oy in range(-1, 2):
					if ox == 0 and oy == 0:
						continue
					var next := Vector2i(at.x + ox, at.y + oy)
					if cells.has(next) and not seen.has(next):
						stack.append(next)
		if not group.is_empty():
			groups.append(group)
	return groups


func _dilate_island(island: PadIsland, owned: Dictionary) -> void:
	island.dilated = island.cells.duplicate()
	for key in island.cells:
		var at: Vector2i = key
		for ox in range(-1, 2):
			for oy in range(-1, 2):
				var next := Vector2i(at.x + ox, at.y + oy)
				if owned.has(next) or island.dilated.has(next) or _pad_tops.has(next):
					continue
				island.dilated[next] = island.cells[at]


func _survey_keys(
		shape: PlanetShape,
		keys: Dictionary,
		cell: float,
		peaks: Dictionary,
		floors: Dictionary
	) -> void:
	var step := minf(PAD_PEAK_STEP, cell)
	var half := cell * 0.5
	for key in keys:
		if peaks.has(key):
			continue
		var at: Vector2i = key
		var origin := Vector2(float(at.x) * cell, float(at.y) * cell)
		var hi := -1.0e9
		var lo := 1.0e9
		var probes := PackedVector2Array()
		probes.append(Vector2.ZERO)
		probes.append(Vector2(-half, -half))
		probes.append(Vector2(half, -half))
		probes.append(Vector2(half, half))
		probes.append(Vector2(-half, half))
		var inset := cell * 0.35
		probes.append(Vector2(-inset, -inset))
		probes.append(Vector2(inset, -inset))
		probes.append(Vector2(inset, inset))
		probes.append(Vector2(-inset, inset))
		probes.append(Vector2(-inset, 0.0))
		probes.append(Vector2(inset, 0.0))
		probes.append(Vector2(0.0, -inset))
		probes.append(Vector2(0.0, inset))
		var x := -half
		while x <= half + 0.0001:
			var y := -half
			while y <= half + 0.0001:
				probes.append(Vector2(x, y))
				y += step
			x += step
		for offset in probes:
			var height := shape.elevation(_from_uv(origin + offset), 0.0)
			hi = maxf(hi, height)
			lo = minf(lo, height)
		peaks[key] = hi
		floors[key] = lo


func _fill_island_holes(island: PadIsland, owned: Dictionary) -> void:
	if island.dilated.is_empty():
		return
	var min_x := 1000000000
	var max_x := -1000000000
	var min_y := 1000000000
	var max_y := -1000000000
	var fill := DISTRICT_COLOR
	for key in island.dilated:
		var at: Vector2i = key
		min_x = mini(min_x, at.x)
		max_x = maxi(max_x, at.x)
		min_y = mini(min_y, at.y)
		max_y = maxi(max_y, at.y)
	var exterior: Dictionary = {}
	var stack: Array = []
	for x in range(min_x - 1, max_x + 2):
		stack.append(Vector2i(x, min_y - 1))
		stack.append(Vector2i(x, max_y + 1))
	for y in range(min_y, max_y + 1):
		stack.append(Vector2i(min_x - 1, y))
		stack.append(Vector2i(max_x + 1, y))
	while not stack.is_empty():
		var at: Vector2i = stack.pop_back()
		if at.x < min_x - 1 or at.x > max_x + 1 or at.y < min_y - 1 or at.y > max_y + 1:
			continue
		if exterior.has(at) or island.dilated.has(at):
			continue
		exterior[at] = true
		stack.append(Vector2i(at.x + 1, at.y))
		stack.append(Vector2i(at.x - 1, at.y))
		stack.append(Vector2i(at.x, at.y + 1))
		stack.append(Vector2i(at.x, at.y - 1))
	for x in range(min_x, max_x + 1):
		for y in range(min_y, max_y + 1):
			var key := Vector2i(x, y)
			if island.dilated.has(key) or exterior.has(key):
				continue
			if _pad_tops.has(key):
				continue
			if owned.has(key) and not island.cells.has(key):
				continue
			island.dilated[key] = fill


func _emit_island(st: SurfaceTool, _shape: PlanetShape, island: PadIsland) -> void:
	var cell := island.cell if island.cell > 0.1 else plan.cell_size
	var ring := _island_ring(island)
	var indices := PackedInt32Array()
	if ring.size() >= 3:
		indices = Geometry2D.triangulate_polygon(ring)
	if indices.size() < 3 and ring.size() >= 3:
		var flipped := PackedVector2Array()
		for step in ring.size():
			flipped.append(ring[ring.size() - 1 - step])
		ring = flipped
		indices = Geometry2D.triangulate_polygon(ring)
	if indices.size() < 3:
		_emit_island_squares(st, island, cell)
		return
	var colour := DISTRICT_COLOR
	var centroid := Vector2.ZERO
	for key in island.dilated:
		var at: Vector2i = key
		centroid += Vector2(float(at.x) * cell, float(at.y) * cell)
	centroid /= float(maxi(island.dilated.size(), 1))
	var tops: Array[Vector3] = []
	var bottoms: Array[Vector3] = []
	tops.resize(ring.size())
	bottoms.resize(ring.size())
	for index in ring.size():
		var direction := _from_uv(ring[index]).normalized()
		tops[index] = direction * (_radius + island.top_h)
		bottoms[index] = direction * (_radius + island.bot_h)
	for step in range(0, indices.size(), 3):
		var a: int = indices[step]
		var b: int = indices[step + 1]
		var c: int = indices[step + 2]
		if (tops[b] - tops[a]).cross(tops[c] - tops[a]).dot(tops[a]) < 0.0:
			_paint_tri(st, tops[a], tops[c], tops[b], colour, tops[a])
		else:
			_paint_tri(st, tops[a], tops[b], tops[c], colour, tops[a])
		if (bottoms[c] - bottoms[a]).cross(bottoms[b] - bottoms[a]).dot(-bottoms[a]) < 0.0:
			_paint_tri(st, bottoms[a], bottoms[b], bottoms[c], colour, -bottoms[a])
		else:
			_paint_tri(st, bottoms[a], bottoms[c], bottoms[b], colour, -bottoms[a])


func _emit_island_squares(st: SurfaceTool, island: PadIsland, cell: float) -> void:
	for key in island.dilated:
		var at: Vector2i = key
		var colour := DISTRICT_COLOR
		var corners := _cell_corners(at, cell)
		var top: Array[Vector3] = []
		var bottom: Array[Vector3] = []
		for corner in corners:
			var direction := _from_uv(corner).normalized()
			top.append(direction * (_radius + island.top_h))
			bottom.append(direction * (_radius + island.bot_h))
		_face(st, top[0], top[1], top[2], top[3], colour, top[0])
		_face(st, bottom[0], bottom[1], bottom[2], bottom[3], colour, -bottom[0])


func _island_ring(island: PadIsland) -> PackedVector2Array:
	var cell := island.cell if island.cell > 0.1 else _pad_cell
	var rounds := PAD_ROUNDS + 2
	return _chaikin_loop(_island_outline(island.dilated, cell), rounds)


func _densify_ring(ring: PackedVector2Array, step: float) -> PackedVector2Array:
	if ring.size() < 3 or step < 0.4:
		return ring
	var out := PackedVector2Array()
	for index in ring.size():
		var a: Vector2 = ring[index]
		var b: Vector2 = ring[(index + 1) % ring.size()]
		var run := a.distance_to(b)
		var pieces := maxi(1, int(ceili(run / step)))
		for piece in pieces:
			out.append(a.lerp(b, float(piece) / float(pieces)))
	return out


func _resample_ring(ring: PackedVector2Array, step: float) -> PackedVector2Array:
	if ring.size() < 3 or step < 0.4:
		return ring
	var lengths := PackedFloat32Array()
	lengths.resize(ring.size())
	var total := 0.0
	for index in ring.size():
		var run := ring[index].distance_to(ring[(index + 1) % ring.size()])
		lengths[index] = run
		total += run
	if total < step * 3.0:
		return ring
	var count := maxi(4, int(round(total / step)))
	var stride := total / float(count)
	var out := PackedVector2Array()
	out.resize(count)
	var want := 0.0
	var edge := 0
	var along := 0.0
	for i in count:
		while edge < ring.size() and along + float(lengths[edge]) < want - 0.0001:
			along += float(lengths[edge])
			edge += 1
		if edge >= ring.size():
			out[i] = ring[0]
			continue
		var span := maxf(float(lengths[edge]), 0.0001)
		var t := clampf((want - along) / span, 0.0, 1.0)
		out[i] = ring[edge].lerp(ring[(edge + 1) % ring.size()], t)
		want += stride
	return out


func _emit_island_aprons(shape: PlanetShape, islands: Array) -> void:
	if islands.is_empty():
		return
	_discard_node(_apron)
	_apron = null
	_apron_mat = null
	_discard_node(_apron_body)
	_apron_body = null
	if shape == null:
		return
	var st := SurfaceTool.new()
	st.begin(Mesh.PRIMITIVE_TRIANGLES)
	for island in islands:
		_emit_island_apron(st, shape, island)
	_apron = _commit_mesh(st, "CityApron", false)
	_bind_apron_material()
	_apron_body = _collide(
		_apron.mesh if _apron != null else null, "CityApronBody")


func _emit_island_apron(st: SurfaceTool, shape: PlanetShape, island: PadIsland) -> void:
	if shape == null:
		return
	var ring := _resample_ring(_island_ring(island), 5.4)
	if ring.size() < 4:
		return
	var n := ring.size()
	var centroid := Vector2.ZERO
	for point in ring:
		centroid += point
	centroid /= float(n)
	var outward := PackedVector2Array()
	outward.resize(n)
	for index in n:
		var prev: Vector2 = ring[(index + n - 1) % n]
		var next: Vector2 = ring[(index + 1) % n]
		var chord := next - prev
		var out := Vector2(-chord.y, chord.x)
		if out.length_squared() < 0.0001:
			out = ring[index] - centroid
		if out.length_squared() < 0.0001:
			out = Vector2.RIGHT
		out = out.normalized()
		if (ring[index] - centroid).dot(out) < 0.0:
			out = -out
		if Geometry2D.is_point_in_polygon(ring[index] + out * 1.4, ring):
			out = -out
		outward[index] = out
	for _pass in 2:
		var smooth := PackedVector2Array()
		smooth.resize(n)
		for index in n:
			var mix := outward[(index + n - 1) % n] + outward[index] * 2.0 \
				+ outward[(index + 1) % n]
			if mix.length_squared() < 0.0001:
				smooth[index] = outward[index]
				continue
			mix = mix.normalized()
			if mix.dot(outward[index]) < 0.2:
				mix = outward[index]
			smooth[index] = mix
		outward = smooth
	var pad_h := island.top_h
	if _dressed or not _road_index.is_empty():
		pad_h += PAVEMENT_LIFT
	var runs := PackedFloat32Array()
	runs.resize(n)
	for index in n:
		runs[index] = _apron_run(
			shape, island, ring[index], outward[index], pad_h)
	for _pass in 2:
		var next := PackedFloat32Array()
		next.resize(n)
		for index in n:
			next[index] = (
				runs[(index + n - 1) % n] + runs[index] * 2.0
				+ runs[(index + 1) % n]) * 0.25
		runs = next
	var farthest := 4.0
	for index in n:
		farthest = maxf(farthest, runs[index])
	var rows := clampi(int(ceili(farthest / 5.0)), 5, 14)
	var prev_top: Array = []
	var prev_bot: Array = []
	var prev_col: Array = []
	for row in rows + 1:
		var t := float(row) / float(rows)
		var ease := 0.5 - 0.5 * cos(PI * t)
		var top_row: Array = []
		var bot_row: Array = []
		var col_row: Array = []
		top_row.resize(n)
		bot_row.resize(n)
		col_row.resize(n)
		for index in n:
			var out: Vector2 = outward[index]
			var run := float(runs[index])
			var inner: Vector2 = ring[index] - out * 0.45
			var outer: Vector2 = ring[index] + out * run
			var uv := inner.lerp(outer, t)
			var ground := _apron_ground(shape, uv, t)
			var h := lerpf(pad_h, ground + APRON_CLEAR, ease)
			# Mid-ramp extra lift: chunk interpolation bows the planet mesh
			# above a single sample, and a chord sitting on that sample sinks.
			var mid := sin(PI * t)
			h += (APRON_CLEAR * 0.85 + APRON_VISUAL) * mid
			h = maxf(h, ground + APRON_CLEAR * 0.7 + APRON_VISUAL * mid)
			if t >= 0.999:
				h = ground + APRON_CLEAR
			var bot := lerpf(
				island.bot_h,
				minf(h - RAMP_THICK, ground - 0.7),
				ease)
			top_row[index] = _height_mark(uv, h)
			bot_row[index] = _height_mark(uv, bot)
			col_row[index] = _apron_ink(shape, uv, t)
		if prev_top.size() == n:
			for index in n:
				var next := (index + 1) % n
				if float(runs[index]) < 0.35 and float(runs[next]) < 0.35:
					continue
				_face_cols(
					st, prev_top[index], prev_top[next], top_row[next], top_row[index],
					prev_col[index], prev_col[next], col_row[next], col_row[index],
					top_row[index])
		prev_top = top_row
		prev_bot = bot_row
		prev_col = col_row
	for index in n:
		var next := (index + 1) % n
		if float(runs[index]) < 0.35 and float(runs[next]) < 0.35:
			continue
		_face_cols(
			st, prev_top[index], prev_top[next], prev_bot[next], prev_bot[index],
			prev_col[index], prev_col[next], prev_col[next], prev_col[index],
			prev_top[index] - prev_bot[index])


func _apron_run(
		shape: PlanetShape,
		island: PadIsland,
		uv: Vector2,
		out: Vector2,
		pad_h: float
	) -> float:
	var cell := _pad_cell if _pad_cell > 0.1 else 4.0
	var home := _island_owner(island)
	var probe := uv + out * 2.6
	var ground := _apron_surface_h(shape, probe)
	if ground < 0.0:
		ground = _apron_surface_h(shape, uv)
	var drop := pad_h - ground
	var want := 2.4
	if drop >= 0.12:
		want = clampf(drop / RAMP_GRADE, RAMP_MIN_RUN, RAMP_MAX_RUN)
	var run := want
	var step := 1.4
	var dist := step
	var own_pad := 0
	while dist <= want + 0.01:
		var at: Vector2 = uv + out * dist
		var key := Vector2i(roundi(at.x / cell), roundi(at.y / cell))
		if _pad_tops.has(key):
			var owner := int(_pad_owner.get(key, -1))
			if owner != home:
				run = minf(run, maxf(dist - cell * 0.55, 0.0))
				break
			own_pad += 1
			if own_pad >= 4 and dist > cell * 3.2:
				run = minf(run, dist - cell * 0.5)
				break
		else:
			own_pad = 0
		var h := _apron_surface_h(shape, at)
		if h < 0.0:
			run = minf(run, maxf(dist - 1.1, 1.2))
			break
		dist += step
	return run


func _apron_surface_h(shape: PlanetShape, uv: Vector2) -> float:
	if shape == null:
		return 0.0
	var direction := _from_uv(uv)
	var high := shape.elevation(direction, 0.0)
	if shape.has_method(&"natural_elevation"):
		high = maxf(high, float(shape.natural_elevation(direction, 0.0)))
	return high


func _apron_ground(shape: PlanetShape, uv: Vector2, t: float) -> float:
	if shape == null:
		return 0.0
	var high := _apron_surface_h(shape, uv)
	# Neighbours matter where the ramp meets the planet mesh; near the pad
	# the top is the slab and a single sample is enough.
	if t < 0.28:
		return high
	var step := 2.2
	for offset in [Vector2(step, 0.0), Vector2(-step, 0.0),
			Vector2(0.0, step), Vector2(0.0, -step),
			Vector2(step, step), Vector2(-step, step),
			Vector2(step, -step), Vector2(-step, -step)]:
		high = maxf(high, _apron_surface_h(shape, uv + offset))
	return high


func _apron_ink(shape: PlanetShape, uv: Vector2, t: float) -> Color:
	var biome := DISTRICT_COLOR
	biome.a = 0.0
	if shape != null:
		# Same dry-land sample the chunks write, without city lawn/concrete
		# and without wetness in alpha — the planet shader treats 1.0 as ocean.
		biome = shape.biome_color_at(_from_uv(uv), 0.0)
		biome.a = 0.0
	if t <= 0.12 and (_dressed or not _road_index.is_empty()):
		var paint := _pavement_ink(uv)
		paint.a = 0.0
		return paint.lerp(biome, clampf(t / 0.12, 0.0, 1.0))
	return biome


func _island_owner(island: PadIsland) -> int:
	for key in island.cells:
		return int(_pad_owner.get(key, -1))
	return -1


func _home_pad_at(uv: Vector2, island: PadIsland) -> bool:
	var cell := _pad_cell if _pad_cell > 0.1 else 4.0
	var key := Vector2i(roundi(uv.x / cell), roundi(uv.y / cell))
	return island.dilated.has(key)


func _height_mark(uv: Vector2, height: float) -> Vector3:
	var up := _from_uv(uv).normalized()
	return up * (_radius + height)


func _island_outline(cells: Dictionary, cell: float) -> PackedVector2Array:
	var outgoing: Dictionary = {}
	for key in cells:
		var at: Vector2i = key
		var corners := _cell_corners(at, cell)
		if not cells.has(Vector2i(at.x, at.y - 1)):
			_add_edge(outgoing, corners[0], corners[1])
		if not cells.has(Vector2i(at.x + 1, at.y)):
			_add_edge(outgoing, corners[1], corners[2])
		if not cells.has(Vector2i(at.x, at.y + 1)):
			_add_edge(outgoing, corners[2], corners[3])
		if not cells.has(Vector2i(at.x - 1, at.y)):
			_add_edge(outgoing, corners[3], corners[0])
	if outgoing.is_empty():
		return PackedVector2Array()
	var start_key: Vector2i = outgoing.keys()[0]
	for key in outgoing:
		var candidate: Vector2i = key
		if candidate.x < start_key.x or (candidate.x == start_key.x and candidate.y < start_key.y):
			start_key = candidate
	var start: Vector2 = (outgoing[start_key] as Array)[0]
	var ring := PackedVector2Array()
	var here := start
	var guard := cells.size() * 8 + 8
	while guard > 0:
		guard -= 1
		ring.append(here)
		var key := _uv_key(here)
		if not outgoing.has(key):
			break
		var choices: Array = outgoing[key]
		if choices.is_empty():
			break
		var next: Vector2 = choices.pop_back()
		if choices.is_empty():
			outgoing.erase(key)
		if next.distance_squared_to(start) < 0.01 and ring.size() >= 3:
			break
		here = next
	return ring


func _add_edge(outgoing: Dictionary, from: Vector2, to: Vector2) -> void:
	var key := _uv_key(from)
	var choices: Array = outgoing.get(key, [])
	choices.append(to)
	outgoing[key] = choices


func _uv_key(at: Vector2) -> Vector2i:
	return Vector2i(roundi(at.x * 40.0), roundi(at.y * 40.0))


func _chaikin_loop(ring: PackedVector2Array, rounds: int) -> PackedVector2Array:
	if ring.size() < 4 or rounds <= 0:
		return ring
	var points := ring
	for _round in rounds:
		var next := PackedVector2Array()
		for index in points.size():
			var a: Vector2 = points[index]
			var b: Vector2 = points[(index + 1) % points.size()]
			next.append(a.lerp(b, 0.25))
			next.append(a.lerp(b, 0.75))
		points = next
	return points


func _cell_corners(at: Vector2i, cell: float) -> PackedVector2Array:
	var half := cell * 0.5
	var centre := Vector2(float(at.x) * cell, float(at.y) * cell)
	var corners := PackedVector2Array()
	corners.append(centre + Vector2(-half, -half))
	corners.append(centre + Vector2(half, -half))
	corners.append(centre + Vector2(half, half))
	corners.append(centre + Vector2(-half, half))
	return corners


func _graded_highway(
		st: SurfaceTool,
		shape: PlanetShape,
		dirs: PackedVector3Array,
		half_width: float
	) -> PackedVector3Array:
	var closed := dirs.size() >= 3 and dirs[0].dot(dirs[dirs.size() - 1]) > 0.999
	var samples := _densify_path(shape, dirs, closed)
	if samples.size() < 3:
		return PackedVector3Array()
	var run := _pave_run(shape, samples, closed, HIGHWAY_GRADE)
	_emit_highway_strip(
		st,
		run["dirs"],
		run["deck"],
		half_width,
		HIGHWAY_THICK,
		closed)
	return run["dirs"]


func _densify_path(
		shape: PlanetShape,
		dirs: PackedVector3Array,
		closed: bool
	) -> PackedVector3Array:
	var samples := PackedVector3Array()
	if dirs.size() < 2:
		return samples
	var unique := PackedVector3Array()
	var limit := dirs.size() - 1 if closed else dirs.size()
	for index in limit:
		unique.append(dirs[index])
	if unique.size() < 2:
		return samples
	var count := unique.size()
	var segments := count if closed else count - 1
	for index in segments:
		var a := unique[index]
		var b := unique[(index + 1) % count]
		var arc := a.angle_to(b) * shape.radius
		var pieces := maxi(1, int(ceili(arc / HIGHWAY_STEP)))
		for piece in pieces:
			var direction := a.slerp(b, float(piece) / float(pieces))
			if shape.elevation(direction, HIGHWAY_STEP) < 0.0:
				continue
			samples.append(direction.normalized())
	if not closed:
		var last := unique[count - 1]
		if shape.elevation(last, HIGHWAY_STEP) >= 0.0:
			samples.append(last.normalized())
	return samples


func _emit_exit(
		st: SurfaceTool,
		shape: PlanetShape,
		exit: PatchCityGenerator.RoadExit,
		highway: Curve3D
	) -> void:
	var run := _exit_centerline(shape, exit, highway)
	var path: PackedVector3Array = run.get("path", PackedVector3Array())
	var deck: PackedFloat32Array = run.get("deck", PackedFloat32Array())
	if path.size() < 4 or deck.size() != path.size():
		return
	_exit_paths.append(path)
	_emit_highway_strip(st, path, deck, EXIT_HALF, EXIT_THICK, false)


func _exit_centerline(
		shape: PlanetShape,
		exit: PatchCityGenerator.RoadExit,
		highway: Curve3D
	) -> Dictionary:
	var empty := {"path": PackedVector3Array(), "deck": PackedFloat32Array()}
	if highway == null or highway.get_baked_length() < 8.0:
		return empty
	var land := exit.land.normalized()
	var end_h := _pad_top_at(land)
	if is_nan(end_h):
		end_h = shape.elevation(land, HIGHWAY_STEP) + GROUND_LIFT
	else:
		end_h += 0.08
	var branch := _pick_branch(highway, exit)
	var offset: float = branch["offset"]
	var sign: float = branch["sign"]
	var length := highway.get_baked_length()
	var seed := _frame_at(highway, offset, length)
	if seed.is_empty():
		return empty
	var land_pos := land * (_radius + end_h)
	var to_land: Vector3 = land_pos - seed["pos"]
	var seed_up: Vector3 = seed["up"]
	to_land -= seed_up * to_land.dot(seed_up)
	var travel: Vector3 = seed["forward"] * sign
	var outward: Vector3 = seed_up.cross(travel)
	if outward.length_squared() < 0.0001:
		return empty
	outward = outward.normalized()
	if outward.dot(to_land) < 0.0:
		outward = -outward
	var shoulder_m := HIGHWAY_HALF + EXIT_HALF - EXIT_OVERLAP
	var path := PackedVector3Array()
	var deck := PackedFloat32Array()
	var merge_steps := maxi(4, int(ceili(EXIT_MERGE_RUN / EXIT_STEP)))
	var last_out := outward
	var last_travel := travel
	for step in merge_steps:
		var at := _curve_wrap(length, offset + sign * float(step) * EXIT_STEP)
		var frame := _frame_at(highway, at, length)
		if frame.is_empty():
			continue
		var up: Vector3 = frame["up"]
		var along: Vector3 = frame["forward"] * sign
		if along.length_squared() < 0.0001:
			along = last_travel
		along = (along - up * along.dot(up)).normalized()
		var side := up.cross(along)
		if side.length_squared() < 0.0001:
			side = last_out
		side = side.normalized()
		if side.dot(last_out) < 0.0:
			side = -side
		last_out = side
		last_travel = along
		var world: Vector3 = frame["pos"] + side * shoulder_m
		var span := world.length()
		if span < 1.0:
			continue
		path.append(world / span)
		deck.append(float(frame["h"]))
	if path.size() < 4:
		return empty
	var mouth_h: float = deck[deck.size() - 1]
	var mouth_pos := path[path.size() - 1] * (_radius + mouth_h)
	var chord := maxf(mouth_pos.distance_to(land_pos), 90.0)
	var handle0 := clampf(chord * 0.58, 70.0, EXIT_HANDLE)
	var handle1 := clampf(chord * 0.45, 55.0, EXIT_HANDLE)
	var arrive := land_pos - mouth_pos
	arrive -= land_pos.normalized() * arrive.dot(land_pos.normalized())
	if arrive.length_squared() < 0.01:
		arrive = last_out
	arrive = arrive.normalized()
	var peel := Curve3D.new()
	peel.bake_interval = 2.0
	peel.add_point(mouth_pos, Vector3.ZERO, last_travel * handle0)
	peel.add_point(land_pos, -arrive * handle1, Vector3.ZERO)
	var peel_len := peel.get_baked_length()
	if peel_len < 8.0:
		return empty
	var pieces := maxi(24, int(ceili(peel_len / EXIT_STEP)))
	var slope0 := 0.0
	var run := path[path.size() - 1].angle_to(path[path.size() - 2]) * _radius
	if run > 0.2:
		slope0 = (deck[deck.size() - 1] - deck[deck.size() - 2]) / run * peel_len
	for piece in range(1, pieces + 1):
		var t := float(piece) / float(pieces)
		var pos := peel.sample_baked(peel_len * t, true)
		var span := pos.length()
		if span < 1.0:
			continue
		var direction := pos / span
		var height := _hermite_height(t, mouth_h, end_h, slope0, 0.0)
		if piece < pieces:
			height = maxf(height, _floor_height(shape, direction))
		else:
			height = end_h
			direction = land
		path.append(direction)
		deck.append(height)
	path[path.size() - 1] = land
	deck[deck.size() - 1] = end_h
	return {"path": path, "deck": deck}


func _frame_at(curve: Curve3D, offset: float, length: float) -> Dictionary:
	var pos := curve.sample_baked(_curve_wrap(length, offset), true)
	var span := pos.length()
	if span < 1.0:
		return {}
	var up := pos / span
	var forward := _curve_forward(curve, offset, length)
	forward = (forward - up * forward.dot(up)).normalized()
	if forward.length_squared() < 0.0001:
		return {}
	return {
		"pos": pos,
		"up": up,
		"forward": forward,
		"h": span - _radius,
	}


func _pick_branch(highway: Curve3D, exit: PatchCityGenerator.RoadExit) -> Dictionary:
	var length := highway.get_baked_length()
	var seed := highway.get_closest_offset(exit.road.normalized() * _radius)
	var best_t := seed
	var best_sign := 1.0
	var best_cost := 1.0e12
	var scan := -220.0
	while scan <= 220.0:
		var at := _curve_wrap(length, seed + scan)
		var pos := highway.sample_baked(at, true)
		var up := pos.normalized()
		var forward := _curve_forward(highway, at, length)
		forward = (forward - up * forward.dot(up)).normalized()
		if forward.length_squared() < 0.0001:
			scan += 6.0
			continue
		var to_land := exit.land.normalized() * pos.length() - pos
		to_land -= up * to_land.dot(up)
		var along := to_land.dot(forward)
		var heading := 1.0
		if along < 0.0:
			along = -along
			heading = -1.0
		var lateral := (to_land - forward * heading * along).length()
		var cost := absf(lateral - 140.0) + absf(along - 70.0) * 0.45
		if lateral < 55.0:
			cost += (55.0 - lateral) * 4.0
		if along < 28.0:
			cost += (28.0 - along) * 3.0
		if cost < best_cost:
			best_cost = cost
			best_t = at
			best_sign = heading
		scan += 6.0
	return {"offset": best_t, "sign": best_sign}


func _curve_from_run(
		samples: PackedVector3Array,
		deck: PackedFloat32Array,
		closed: bool
	) -> Curve3D:
	var curve := Curve3D.new()
	curve.bake_interval = 4.0
	var n := samples.size()
	if n < 2 or deck.size() != n:
		return curve
	var points := PackedVector3Array()
	points.resize(n)
	for index in n:
		points[index] = samples[index] * (_radius + deck[index])
	var count := n + 1 if closed else n
	for index in count:
		var at := index % n
		var prev: Vector3 = points[(at - 1 + n) % n]
		var next: Vector3 = points[(at + 1) % n]
		if not closed:
			if at == 0:
				prev = points[0]
				next = points[mini(1, n - 1)]
			elif at == n - 1:
				prev = points[maxi(n - 2, 0)]
				next = points[n - 1]
		var handle := (next - prev) / 6.0
		curve.add_point(points[at], -handle, handle)
	return curve


func _curve_wrap(length: float, offset: float) -> float:
	if length <= 0.001:
		return 0.0
	return fposmod(offset, length)


func _curve_forward(curve: Curve3D, offset: float, length: float) -> Vector3:
	var a := curve.sample_baked(_curve_wrap(length, offset - 1.5), true)
	var b := curve.sample_baked(_curve_wrap(length, offset + 1.5), true)
	var tangent := b - a
	if tangent.length_squared() < 0.0001:
		var xform := curve.sample_baked_with_rotation(offset, true)
		tangent = xform.basis.z
	return tangent.normalized()


func _hermite_height(t: float, h0: float, h1: float, m0: float, m1: float) -> float:
	var u := clampf(t, 0.0, 1.0)
	var u2 := u * u
	var u3 := u2 * u
	return h0 * (2.0 * u3 - 3.0 * u2 + 1.0) \
		+ h1 * (-2.0 * u3 + 3.0 * u2) \
		+ m0 * (u3 - 2.0 * u2 + u) \
		+ m1 * (u3 - u2)


func _emit_highway_strip(
		st: SurfaceTool,
		samples: PackedVector3Array,
		deck: PackedFloat32Array,
		half_width: float,
		thick: float,
		closed: bool,
		skip_first: int = 0,
		half_end: float = -1.0
	) -> void:
	var n := samples.size()
	if n < 3 or deck.size() != n:
		return
	var end_w := half_width if half_end < 0.0 else half_end
	var tops := PackedVector3Array()
	var bottoms := PackedVector3Array()
	tops.resize(n)
	bottoms.resize(n)
	for index in n:
		var up := samples[index]
		var height: float = deck[index]
		tops[index] = up * (_radius + height)
		bottoms[index] = up * (_radius + height - thick)
	var sides := PackedVector3Array()
	sides.resize(n)
	var previous := Vector3.ZERO
	for index in n:
		var before := tops[n - 1] if index == 0 else tops[index - 1]
		var after := tops[0] if index == n - 1 else tops[index + 1]
		if not closed:
			if index == 0:
				before = tops[index]
			if index == n - 1:
				after = tops[index]
		var tangent := after - before
		var up := samples[index]
		var side := up.cross(tangent)
		if side.length_squared() < 0.0001:
			side = previous if previous.length_squared() > 0.0001 else up.cross(Vector3.RIGHT)
		side = side.normalized()
		if previous.length_squared() > 0.0001 and side.dot(previous) < 0.0:
			side = -side
		previous = side
		var u := 0.0 if closed or n <= 1 else float(index) / float(n - 1)
		sides[index] = side * lerpf(half_width, end_w, u)
	var quads := n if closed else n - 1
	for index in quads:
		if index < skip_first:
			continue
		var next := (index + 1) % n
		var a := tops[index] - sides[index]
		var b := tops[index] + sides[index]
		var c := tops[next] + sides[next]
		var d := tops[next] - sides[next]
		var e := bottoms[index] - sides[index]
		var f := bottoms[index] + sides[index]
		var g := bottoms[next] + sides[next]
		var h := bottoms[next] - sides[next]
		_face(st, a, b, c, d, HIGHWAY_COLOR, tops[index])
		_face(st, e, h, g, f, HIGHWAY_COLOR, -bottoms[index])
		_face(st, a, d, h, e, HIGHWAY_COLOR, -sides[index])
		_face(st, b, f, g, c, HIGHWAY_COLOR, sides[index])
	if not closed and quads > skip_first:
		var last := n - 1
		var along := tops[last] - tops[maxi(last - 1, 0)]
		var a := tops[last] - sides[last]
		var b := tops[last] + sides[last]
		var f := bottoms[last] + sides[last]
		var e := bottoms[last] - sides[last]
		_face(st, a, b, f, e, HIGHWAY_COLOR, along)
	if not closed and skip_first <= 0:
		var along := tops[0] - tops[mini(1, n - 1)]
		var a := tops[0] - sides[0]
		var b := tops[0] + sides[0]
		var f := bottoms[0] + sides[0]
		var e := bottoms[0] - sides[0]
		_face(st, a, e, f, b, HIGHWAY_COLOR, along)


func _pave_run(
		shape: PlanetShape,
		samples: PackedVector3Array,
		closed: bool,
		grade: float
	) -> Dictionary:
	var empty := {"dirs": samples, "deck": PackedFloat32Array()}
	if samples.size() < 3:
		return empty
	var floors := _sample_floors(shape, samples)
	var deck := _preferred_deck(shape, samples, closed)
	for index in samples.size():
		deck[index] = maxf(deck[index], floors[index])
	deck = _grade_limit(samples, deck, floors, closed, grade)
	var curved := _chaikin_ribbon(samples, deck, closed)
	samples = curved[0]
	deck = curved[1]
	floors = _sample_floors(shape, samples)
	for index in samples.size():
		deck[index] = maxf(deck[index], floors[index])
	deck = _grade_limit(samples, deck, floors, closed, grade)
	deck = _patch_deck(samples, deck, floors, closed, grade)
	return {"dirs": samples, "deck": deck}


func _sample_floors(shape: PlanetShape, samples: PackedVector3Array) -> PackedFloat32Array:
	var floors := PackedFloat32Array()
	floors.resize(samples.size())
	for index in samples.size():
		floors[index] = maxf(
			shape.elevation(samples[index], 2.0) + HIGHWAY_MIN_LIFT,
			_road_over_pad(samples[index]))
	return floors


func _preferred_deck(
		shape: PlanetShape,
		samples: PackedVector3Array,
		closed: bool
	) -> PackedFloat32Array:
	var n := samples.size()
	var elev := PackedFloat32Array()
	elev.resize(n)
	for index in n:
		elev[index] = shape.elevation(samples[index], HIGHWAY_STEP)
	var window := maxi(1, int(round(HIGHWAY_SMOOTH / HIGHWAY_STEP)))
	var deck := PackedFloat32Array()
	deck.resize(n)
	for index in n:
		var acc := 0.0
		var taken := 0
		for offset in range(-window, window + 1):
			var at := index + offset
			if closed:
				at = (at % n + n) % n
			elif at < 0 or at >= n:
				continue
			acc += elev[at]
			taken += 1
		var average := acc / float(maxi(taken, 1))
		deck[index] = maxf(average + HIGHWAY_LIFT, elev[index] + HIGHWAY_MIN_LIFT)
	return deck


func _grade_limit(
		samples: PackedVector3Array,
		deck: PackedFloat32Array,
		floors: PackedFloat32Array,
		closed: bool,
		grade: float
	) -> PackedFloat32Array:
	var n := samples.size()
	if n < 2 or deck.size() != n or floors.size() != n:
		return deck
	var out := deck.duplicate()
	for index in n:
		out[index] = maxf(out[index], floors[index])
	var rounds := 2 if closed else 1
	for _round in rounds:
		for index in n:
			var next := (index + 1) % n
			if not closed and index == n - 1:
				break
			var cap := grade * maxf(samples[index].angle_to(samples[next]) * _radius, 0.25)
			out[next] = maxf(out[next], out[index] - cap)
			out[next] = maxf(out[next], floors[next])
		for step in n:
			var index := n - 1 - step
			var prev := (index - 1 + n) % n
			if not closed and index == 0:
				break
			var cap := grade * maxf(samples[index].angle_to(samples[prev]) * _radius, 0.25)
			out[prev] = maxf(out[prev], out[index] - cap)
			out[prev] = maxf(out[prev], floors[prev])
	return out


func _patch_deck(
		samples: PackedVector3Array,
		deck: PackedFloat32Array,
		floors: PackedFloat32Array,
		closed: bool,
		grade: float
	) -> PackedFloat32Array:
	var n := samples.size()
	if n < 4 or deck.size() != n or floors.size() != n:
		return deck
	var out := deck.duplicate()
	for _round in HIGHWAY_PATCH_ROUNDS:
		for index in n:
			out[index] = maxf(out[index], floors[index])
		for index in n:
			_patch_window(samples, out, floors, index, 1, closed, grade)
			_patch_window(samples, out, floors, index, -1, closed, grade)
		out = _grade_limit(samples, out, floors, closed, grade)
	for index in n:
		out[index] = maxf(out[index], floors[index])
	return out


func _patch_window(
		samples: PackedVector3Array,
		deck: PackedFloat32Array,
		floors: PackedFloat32Array,
		start: int,
		heading: int,
		closed: bool,
		grade: float
	) -> void:
	var n := samples.size()
	var at := start
	var run := 0.0
	var guard := 0
	while run < HIGHWAY_PATCH_SPAN and guard < n:
		guard += 1
		var nxt := at + heading
		if closed:
			nxt = (nxt % n + n) % n
		elif nxt < 0 or nxt >= n:
			break
		if nxt == start:
			break
		run += samples[at].angle_to(samples[nxt]) * _radius
		at = nxt
		if run < 0.4:
			continue
		var cap := grade * run
		if deck[start] > deck[at] + cap:
			if deck[start] <= floors[start] + 0.05:
				deck[at] = maxf(deck[at], deck[start] - cap)
				deck[at] = maxf(deck[at], floors[at])
			else:
				deck[start] = maxf(floors[start], deck[at] + cap)
		elif deck[at] > deck[start] + cap:
			if deck[at] <= floors[at] + 0.05:
				deck[start] = maxf(deck[start], deck[at] - cap)
				deck[start] = maxf(deck[start], floors[start])
			else:
				deck[at] = maxf(floors[at], deck[start] + cap)


func _reach_along(
		samples: PackedVector3Array,
		start: int,
		heading: int,
		closed: bool,
		want: float
	) -> Dictionary:
	var n := samples.size()
	var at := start
	var run := 0.0
	var guard := 0
	while run < want and guard < n:
		guard += 1
		var nxt := at + heading
		if closed:
			nxt = (nxt % n + n) % n
		elif nxt < 0 or nxt >= n:
			break
		if nxt == start:
			break
		run += samples[at].angle_to(samples[nxt]) * _radius
		at = nxt
	return {"at": at, "run": run}


func _chaikin_ribbon(
		samples: PackedVector3Array,
		deck: PackedFloat32Array,
		closed: bool
	) -> Array:
	var n := samples.size()
	if n < 3 or deck.size() != n or DECK_ROUNDS <= 0:
		return [samples, deck]
	var points := PackedVector3Array()
	points.resize(n)
	for index in n:
		points[index] = samples[index] * (_radius + deck[index])
	for _round in DECK_ROUNDS:
		var next := PackedVector3Array()
		if closed:
			for index in points.size():
				var a: Vector3 = points[index]
				var b: Vector3 = points[(index + 1) % points.size()]
				next.append(a.lerp(b, 0.25))
				next.append(a.lerp(b, 0.75))
		else:
			next.append(points[0])
			for index in points.size() - 1:
				var a: Vector3 = points[index]
				var b: Vector3 = points[index + 1]
				if index > 0:
					next.append(a.lerp(b, 0.25))
				next.append(a.lerp(b, 0.75))
			next.append(points[points.size() - 1])
		points = next
	var dirs := PackedVector3Array()
	var heights := PackedFloat32Array()
	dirs.resize(points.size())
	heights.resize(points.size())
	for index in points.size():
		var at: Vector3 = points[index]
		var span := at.length()
		if span < 1.0:
			dirs[index] = samples[0]
			heights[index] = deck[0]
			continue
		dirs[index] = at / span
		heights[index] = span - _radius
	return [dirs, heights]


func _register_flora_pad() -> void:
	_unregister_flora_pad()
	if plan == null:
		return
	var pad := PadCover.new()
	pad.centre = _up
	pad.cell = _pad_cell if _pad_cell > 0.1 else plan.cell_size
	pad.radius = _radius
	pad.east = _east
	pad.north = _north
	pad.keys = _pad_tops.duplicate()
	_stamp_flora_run(pad.keys, pad.cell, plan.loop, HIGHWAY_HALF + 4.0)
	_stamp_flora_run(pad.keys, pad.cell, plan.extension, HIGHWAY_HALF * 0.72 + 4.0)
	for exit in plan.exits:
		_stamp_flora_run(pad.keys, pad.cell, _exit_flora_run(exit), EXIT_HALF + 4.0)
	var farthest := 0.0
	for key in pad.keys:
		var at: Vector2i = key
		var sample := _from_uv(Vector2(float(at.x) * pad.cell, float(at.y) * pad.cell))
		farthest = maxf(farthest, _up.angle_to(sample))
	pad.span_cos = cos(farthest + 24.0 / _radius) if farthest > 0.0 else 2.0
	_pad = pad
	var next: Array = _flora_pads.duplicate()
	next.append(pad)
	_flora_pads = next
	_publish_flora_pads()
	add_to_group(PAD_GROUP)


func _stamp_flora_run(keys: Dictionary, cell: float, dirs: PackedVector3Array, half: float) -> void:
	if dirs.is_empty() or cell <= 0.1:
		return
	var reach := maxi(1, int(ceili(half / cell)))
	for direction in dirs:
		var uv := _to_uv(direction)
		var cx := roundi(uv.x / cell)
		var cy := roundi(uv.y / cell)
		for ox in range(-reach, reach + 1):
			for oy in range(-reach, reach + 1):
				var key := Vector2i(cx + ox, cy + oy)
				var at := Vector2(float(key.x) * cell, float(key.y) * cell)
				if at.distance_to(uv) <= half:
					keys[key] = true


func _exit_flora_run(exit: PatchCityGenerator.RoadExit) -> PackedVector3Array:
	var samples := PackedVector3Array()
	var a := exit.road.normalized()
	var b := exit.land.normalized()
	var pieces := maxi(2, int(ceili(a.angle_to(b) * _radius / 6.0)))
	for step in pieces + 1:
		samples.append(a.slerp(b, float(step) / float(pieces)))
	return samples


func _unregister_flora_pad() -> void:
	if _pad == null:
		return
	var next: Array = []
	for pad in _flora_pads:
		if pad != _pad:
			next.append(pad)
	_flora_pads = next
	_pad = null
	_publish_flora_pads()
	if is_inside_tree() and is_in_group(PAD_GROUP):
		remove_from_group(PAD_GROUP)


func _publish_flora_pads() -> void:
	var centres := PackedVector3Array()
	var coss := PackedFloat32Array()
	for pad in _flora_pads:
		centres.append(pad.centre)
		coss.append(pad.span_cos)
	_flora_centres = centres
	_flora_coss = coss


func _clear_flora() -> void:
	if not is_inside_tree() or plan == null:
		return
	var reach := 400.0
	if _pad != null:
		reach = acos(clampf(_pad.span_cos, -1.0, 1.0)) * _radius + 80.0
	var origin := _up
	if _pad != null:
		origin = _pad.centre
	for node in get_tree().get_nodes_in_group(DamageHit.FIELD_GROUP):
		if not is_instance_valid(node):
			continue
		if node.has_method(&"replant_around"):
			node.call(&"replant_around", origin, reach)
		if node.has_method(&"hide_under_city"):
			node.call(&"hide_under_city")


func _name_map() -> void:
	places.clear()
	if plan == null:
		return
	var slug := _slug(plan.patch_name)
	plan.road_name = "%s Road" % plan.patch_name
	var taken: Dictionary = {}
	for index in plan.exits.size():
		var branch := plan.exits[index]
		var base := "%s Exit" % _compass_of(branch.land)
		var title := base
		var extra := 2
		while taken.has(title):
			title = "%s %d" % [base, extra]
			extra += 1
		taken[title] = true
		branch.name = title
		places.append(_make_place(
			"%s/exit/%d" % [slug, index],
			CityPlace.KIND_EXIT,
			title,
			"City_%s_Exit%d" % [slug, index + 1],
			branch.land,
			180.0,
			branch.district_id))
	for district in plan.districts:
		places.append(_make_place(
			"%s/district/%d" % [slug, district.id],
			CityPlace.KIND_DISTRICT,
			district.name,
			"City_%s_District%d" % [slug, district.id],
			district.centre,
			maxf(district.span, 120.0),
			district.id))
	var road_at := _road_label_dir()
	places.append(_make_place(
		"%s/road" % slug,
		CityPlace.KIND_ROAD,
		plan.road_name,
		"City_%s_Road" % slug,
		road_at,
		maxf(_loop_span(), 400.0),
		-1))


func _make_place(
		id: String,
		kind: StringName,
		title: String,
		node_name: String,
		direction: Vector3,
		span: float,
		district_id: int
	) -> CityPlace:
	var place := CityPlace.new()
	place.id = id
	place.kind = kind
	place.name = title
	place.node_name = node_name
	place.patch_id = plan.patch_id
	place.patch_name = plan.patch_name
	place.district_id = district_id
	place.span = span
	place.bind(direction)
	return place


func _build_map(shape: PlanetShape) -> void:
	_discard_node(_map)
	_map = null
	_map_mesh = null
	_map_names = null
	_map_marks = null
	if plan == null or shape == null:
		return
	_map = Node3D.new()
	_map.name = "CityMap"
	_map.visible = false
	add_child(_map)
	var buckets := _district_map_cells()
	_build_fabric(shape, buckets)
	var district_rings: Array = []
	for district in plan.districts:
		var cells: Dictionary = buckets.get(district.id, {})
		if cells.is_empty():
			continue
		var ring := _chaikin_loop(_island_outline(cells, _pad_cell), PAD_ROUNDS)
		district_rings.append({
			"uv": ring,
			"id": district.id,
			"name": district.name,
		})
	_cache_minimap(district_rings)
	_raise_place_landmarks()
	_raise_street_names(shape)
	_raise_special_marks(shape)
	if _cull_overlapping_lots() > 0:
		_refill_fabric_gaps()
		_cull_overlapping_lots()
		_emit_fabric_buildings(shape)


func _district_map_cells() -> Dictionary:
	var buckets: Dictionary = {}
	if plan == null:
		return buckets
	var cell := _pad_cell if _pad_cell > 0.1 else plan.cell_size
	var stamp := plan.cell_size * PAD_STAMP
	var reach := int(ceili(stamp / maxf(cell, 1.0)))
	var claimed: Dictionary = {}
	var claimed_d2: Dictionary = {}
	for district in plan.districts:
		var centre := _to_uv(district.centre)
		for direction in district.dirs:
			var uv := _to_uv(direction)
			var cx := roundi(uv.x / cell)
			var cy := roundi(uv.y / cell)
			for ox in range(-reach, reach + 1):
				for oy in range(-reach, reach + 1):
					var key := Vector2i(cx + ox, cy + oy)
					if not _pad_tops.has(key):
						continue
					var at := Vector2(float(key.x) * cell, float(key.y) * cell)
					if at.distance_to(uv) > stamp:
						continue
					var d2 := at.distance_squared_to(centre)
					if claimed.has(key) and d2 >= float(claimed_d2[key]):
						continue
					claimed[key] = district.id
					claimed_d2[key] = d2
	for key in claimed:
		var district_id: int = claimed[key]
		var cells: Dictionary = buckets.get(district_id, {})
		cells[key] = true
		buckets[district_id] = cells
	return buckets


func _build_fabric(shape: PlanetShape, buckets: Dictionary) -> void:
	_discard_node(_fabric_streets)
	_fabric_streets = null
	_discard_node(_fabric_buildings)
	_fabric_buildings = null
	fabric = {}
	var arteries := {
		"highway": _dirs_to_uv(_highway_dirs),
		"highway_half": HIGHWAY_HALF,
		"spur": _dirs_to_uv(_highway_spur),
		"spur_half": HIGHWAY_HALF * 0.72,
		"exits": _exit_uvs(),
		"exit_half": EXIT_HALF,
	}
	_fabric_arteries = arteries
	_fabric_layout = FABRIC.new()
	fabric = _fabric_layout.build(plan, buckets, _pad_cell, _up, _east, _north, _radius, arteries)
	_cull_overlapping_lots()
	_refill_fabric_gaps()
	_cull_overlapping_lots()
	_name_fabric()
	var streets: Array = fabric.get("streets", [])
	var street_st := SurfaceTool.new()
	street_st.begin(Mesh.PRIMITIVE_TRIANGLES)
	for street in streets:
		var row: Dictionary = street
		var half := float(row["half"])
		var rank: int = int(row["rank"])
		var colour := Color(0.20, 0.20, 0.22, FABRIC_ALPHA)
		if rank == 2:
			colour = Color(0.26, 0.24, 0.22, FABRIC_ALPHA * 0.9)
		elif rank == 0:
			colour = Color(0.17, 0.17, 0.19, FABRIC_ALPHA)
		_deck_ribbon(street_st, shape, row["uv"], half, colour, fabric.get("junctions", []))
	for junction in fabric.get("junctions", []):
		var row: Dictionary = junction
		var rank: int = int(row.get("rank", 1))
		var colour := Color(0.20, 0.20, 0.22, FABRIC_ALPHA)
		if rank == 2:
			colour = Color(0.26, 0.24, 0.22, FABRIC_ALPHA * 0.9)
		elif rank == 0:
			colour = Color(0.17, 0.17, 0.19, FABRIC_ALPHA)
		_deck_pad(street_st, shape, row["at"], float(row["half"]), colour)
	_fabric_streets = _commit_ghost(street_st, "FabricStreets")
	_emit_fabric_buildings(shape)
	print("patch_city: fabric %s — %d streets, %d buildings"
		% [plan.patch_name, streets.size(), fabric.get("lots", []).size()])


func _refill_fabric_gaps() -> void:
	if _fabric_layout == null:
		return
	_fabric_layout.take_lots(fabric.get("lots", []))
	fabric["lots"] = _fabric_layout.refill_leftovers(_fabric_arteries)


func _emit_fabric_buildings(shape: PlanetShape) -> void:
	_discard_node(_fabric_buildings)
	_fabric_buildings = null
	var lots: Array = fabric.get("lots", [])
	var build_st := SurfaceTool.new()
	build_st.begin(Mesh.PRIMITIVE_TRIANGLES)
	for lot in lots:
		if not _lot_on_slab(lot):
			continue
		_emit_lot_box(build_st, shape, lot)
	_fabric_buildings = _commit_ghost(build_st, "FabricBuildings")


func _build_city(shape: PlanetShape) -> void:
	_index_city_roads()
	_paint_pavement(shape)
	_solidify_buildings(shape)
	_place_lamps(shape)
	if is_instance_valid(_fabric_streets):
		_fabric_streets.visible = false
	if is_instance_valid(_fabric_buildings):
		_fabric_buildings.visible = false
	set_process(true)
	print("patch_city: built %s — %d buildings, %d lamps"
		% [plan.patch_name, fabric.get("lots", []).size(), _lamp_spots.size()])


func _dress_city(shape: PlanetShape) -> void:
	_dressed = true
	_assign_paint_styles()
	_bake_wall_shade()
	print("patch_city: painting walks %s" % plan.patch_name)
	_paint_ground_map()
	if not _pad_islands.is_empty():
		_emit_island_aprons(shape, _pad_islands)
	print("patch_city: painting facades %s" % plan.patch_name)
	_dress_buildings(shape)
	print("patch_city: painted %s — %d buildings"
		% [plan.patch_name, fabric.get("lots", []).size()])


func _assign_paint_styles() -> void:
	_district_ground.clear()
	_district_accent.clear()
	if plan == null:
		return
	var rng := RandomNumberGenerator.new()
	rng.seed = hash([plan.patch_id, plan.patch_name, "dress"])
	var city_ground: int = rng.randi() % 4
	var same := rng.randf() < 0.42
	for district in plan.districts:
		var style := city_ground
		if not same and rng.randf() > 0.52:
			style = rng.randi() % 4
		_district_ground[district.id] = style
		_district_accent[district.id] = Color(
			rng.randf_range(0.18, 0.92),
			rng.randf_range(0.16, 0.88),
			rng.randf_range(0.14, 0.84))
	var small_tints: Array = [
		Color(0.64, 0.34, 0.26),
		Color(0.50, 0.34, 0.20),
		Color(0.52, 0.50, 0.46),
		Color(0.84, 0.44, 0.24),
		Color(0.54, 0.34, 0.60),
		Color(0.34, 0.54, 0.36),
	]
	var by_district: Dictionary = {}
	for lot in fabric.get("lots", []):
		var row: Dictionary = lot
		var district_id: int = int(row.get("district_id", -1))
		var list: Array = by_district.get(district_id, [])
		list.append(row)
		by_district[district_id] = list
	var mega_family: Dictionary = {}
	var pack_family: Dictionary = {}
	var next_family := rng.randi() % 4
	for district_id in by_district:
		var has_mega := false
		for item in by_district[district_id]:
			if bool((item as Dictionary).get("mega", false)):
				has_mega = true
				break
		if has_mega:
			mega_family[district_id] = PAINT_SKY_DARK + next_family
			next_family = (next_family + 1 + rng.randi() % 3) % 4
	for district_id in by_district:
		var list: Array = by_district[district_id]
		var small_primary: int = rng.randi() % 3
		for item in list:
			var row: Dictionary = item
			var large := int(row.get("typology", 0)) >= 4
			var centre: Vector2 = row.get("centre", Vector2.ZERO)
			var cluster := Vector2i(int(floor(centre.x / 36.0)), int(floor(centre.y / 36.0)))
			var roll := rng.randf()
			if large:
				var style := PAINT_SKY_DARK
				if bool(row.get("mega", false)):
					style = int(mega_family.get(district_id, PAINT_SKY_DARK))
				else:
					var pack := Vector2i(
						int(floor(centre.x / 108.0)), int(floor(centre.y / 108.0)))
					if not pack_family.has(pack):
						pack_family[pack] = PAINT_SKY_DARK + absi(pack.x * 3 + pack.y * 7 + int(district_id)) % 4
					style = int(pack_family[pack])
					if roll > 0.86:
						style = PAINT_SKY_DARK + rng.randi() % 4
				_paint_sky_lot(row, style, rng)
				if String(row.get("design", "")).is_empty():
					_paint_variant_lot(row, rng)
			else:
				var style := small_primary
				if absi(cluster.x + cluster.y * 11) % 3 == 2:
					style = (small_primary + 1) % 3
				if roll > 0.74:
					style = rng.randi() % 3
				row["paint_style"] = style
				row["paint_name"] = ["brick", "wood", "stone"][style]
				row["paint_tint"] = small_tints[style]
				row["paint_trim"] = Color(0.22, 0.14, 0.10)
				_paint_variant_lot(row, rng)
	_ensure_sky_paint(rng)


func _paint_variant_lot(row: Dictionary, rng: RandomNumberGenerator) -> void:
	var styles := CityBuildingCatalog.VARIANT_PAINT_STYLES
	if styles.is_empty():
		return
	var district_id := int(row.get("district_id", 0))
	var centre: Vector2 = row.get("centre", Vector2.ZERO)
	var cluster := Vector2i(int(floor(centre.x / 36.0)), int(floor(centre.y / 36.0)))
	var pick := posmod(district_id + int(row.get("variant", 0)), styles.size())
	if absi(cluster.x + cluster.y * 11) % 3 == 2:
		pick = posmod(pick + 2, styles.size())
	if rng.randf() > 0.78:
		pick = rng.randi() % styles.size()
	row["paint_name"] = styles[pick]


func _paint_sky_lot(row: Dictionary, style: int, rng: RandomNumberGenerator) -> void:
	var family := clampi(style, PAINT_SKY_DARK, PAINT_SKY_ORANGE)
	var tints := _sky_paint_tints(family)
	row["paint_style"] = family
	row["paint_name"] = CityBuildingCatalog.paint_style_name(row)
	row["paint_tint"] = tints[rng.randi() % tints.size()]
	row["paint_trim"] = _sky_paint_trim(family)
	row["paint_glass"] = _sky_paint_glass(family)
	var neons := _sky_paint_neons(family)
	var pick := rng.randi() % neons.size()
	row["paint_neon"] = neons[pick]
	row["paint_neon_alt"] = neons[(pick + 1 + rng.randi() % maxi(neons.size() - 1, 1)) % neons.size()]
	row["night_trim"] = true
	row["night_crown"] = rng.randf() < 0.52


func _ensure_sky_paint(rng: RandomNumberGenerator) -> void:
	var seen: Dictionary = {}
	var spare: Array = []
	for lot in fabric.get("lots", []):
		var row: Dictionary = lot
		if int(row.get("typology", 0)) < 4:
			continue
		var style := int(row.get("paint_style", PAINT_SKY_DARK))
		seen[style] = true
		if not bool(row.get("mega", false)):
			spare.append(row)
	for family in [
			PAINT_SKY_DARK, PAINT_SKY_SILVER, PAINT_SKY_COPPER, PAINT_SKY_ORANGE
		]:
		if seen.has(family):
			continue
		if spare.is_empty():
			break
		var pick: Dictionary = spare[rng.randi() % spare.size()]
		_paint_sky_lot(pick, family, rng)
		seen[family] = true


func _sky_paint_tints(style: int) -> Array:
	match style:
		PAINT_SKY_SILVER:
			return [
				Color(0.84, 0.86, 0.90),
				Color(0.78, 0.82, 0.88),
				Color(0.92, 0.93, 0.96),
			]
		PAINT_SKY_COPPER:
			return [
				Color(0.32, 0.56, 0.44),
				Color(0.42, 0.58, 0.38),
				Color(0.28, 0.50, 0.46),
			]
		PAINT_SKY_ORANGE:
			return [
				Color(0.96, 0.64, 0.36),
				Color(1.0, 0.74, 0.44),
				Color(0.90, 0.54, 0.30),
			]
	return [
		Color(0.32, 0.34, 0.42),
		Color(0.36, 0.30, 0.44),
		Color(0.28, 0.32, 0.40),
	]


func _sky_paint_trim(style: int) -> Color:
	match style:
		PAINT_SKY_SILVER:
			return Color(0.52, 0.56, 0.62)
		PAINT_SKY_COPPER:
			return Color(0.46, 0.28, 0.16)
		PAINT_SKY_ORANGE:
			return Color(0.62, 0.30, 0.14)
	return Color(0.10, 0.10, 0.14)


func _sky_paint_glass(style: int) -> Color:
	match style:
		PAINT_SKY_SILVER:
			return Color(0.58, 0.70, 0.82)
		PAINT_SKY_COPPER:
			return Color(0.18, 0.30, 0.26)
		PAINT_SKY_ORANGE:
			return Color(0.42, 0.24, 0.14)
	return Color(0.16, 0.18, 0.26)


func _sky_paint_neons(style: int) -> Array:
	match style:
		PAINT_SKY_SILVER:
			return [
				Color(0.18, 0.92, 1.0),
				Color(0.28, 0.52, 1.0),
				Color(0.12, 0.78, 0.92),
			]
		PAINT_SKY_COPPER:
			return [
				Color(0.32, 1.0, 0.42),
				Color(0.12, 0.92, 0.72),
				Color(0.72, 1.0, 0.28),
			]
		PAINT_SKY_ORANGE:
			return [
				Color(1.0, 0.52, 0.10),
				Color(1.0, 0.22, 0.28),
				Color(1.0, 0.78, 0.16),
			]
	return [
		Color(1.0, 0.18, 0.72),
		Color(0.68, 0.22, 1.0),
		Color(0.28, 0.48, 1.0),
	]


func _bake_wall_shade() -> void:
	_wall_dist.clear()
	if _pad_cell <= 0.1:
		return
	var cell := _pad_cell
	for lot in fabric.get("lots", []):
		var row: Dictionary = lot
		if not _lot_on_slab(row):
			continue
		var centre: Vector2 = row.get("centre", Vector2.ZERO)
		var along: Vector2 = row.get("along", Vector2.RIGHT)
		if along.length_squared() < 0.0001:
			along = Vector2.RIGHT
		along = along.normalized()
		var across := Vector2(-along.y, along.x)
		var half_w := float(row.get("width", 8.0)) * 0.5
		var half_d := float(row.get("depth", 8.0)) * 0.5
		var reach := maxf(half_w, half_d) + WALL_SHADE
		var x0 := int(floor((centre.x - reach) / cell))
		var x1 := int(ceil((centre.x + reach) / cell))
		var y0 := int(floor((centre.y - reach) / cell))
		var y1 := int(ceil((centre.y + reach) / cell))
		for gx in range(x0, x1 + 1):
			for gy in range(y0, y1 + 1):
				var key := Vector2i(gx, gy)
				if not _pad_tops.has(key):
					continue
				var uv := Vector2(float(gx) * cell, float(gy) * cell)
				var local := uv - centre
				var dx := absf(local.dot(along)) - half_w
				var dy := absf(local.dot(across)) - half_d
				var d := maxf(dx, dy)
				if dx > 0.0 and dy > 0.0:
					d = Vector2(dx, dy).length()
				var prev := float(_wall_dist.get(key, 1.0e4))
				if d < prev:
					_wall_dist[key] = d


func _wall_signed(uv: Vector2) -> float:
	if _pad_cell <= 0.1:
		return 1.0e4
	var key := Vector2i(roundi(uv.x / _pad_cell), roundi(uv.y / _pad_cell))
	return float(_wall_dist.get(key, 1.0e4))


func _walk_paint(uv: Vector2) -> Color:
	var edge := _road_signed(uv)
	var painted := _walk_pattern(uv)
	var blend := clampf(edge / maxf(PAVEMENT_BLEND, 0.001), 0.0, 1.0)
	blend = blend * blend * (3.0 - 2.0 * blend)
	return PAVEMENT_ROAD.lerp(painted, blend)


func _walk_pattern(uv: Vector2) -> Color:
	var colour := _walk_base(uv, _district_at_uv(uv))
	var wall := _wall_signed(uv)
	var shade := clampf(wall / WALL_SHADE, 0.0, 1.0)
	shade = shade * shade * (3.0 - 2.0 * shade)
	return colour.darkened(0.38 * (1.0 - shade))


func _walk_base(uv: Vector2, district_id: int) -> Color:
	var style: int = int(_district_ground.get(district_id, GROUND_GRASS))
	var n := _hash21(uv * 0.07)
	var n2 := _hash21(uv * 0.29 + Vector2(4.2, 1.7))
	var n3 := _hash21(uv * 0.91 + Vector2(9.4, 3.1))
	var n4 := _hash21(uv * 3.6 + Vector2(2.2, 8.8))
	var n5 := _hash21(uv * 11.0)
	var accent := Color(0.55, 0.50, 0.42)
	if _district_accent.has(district_id):
		accent = _district_accent[district_id] as Color
	var colour := Color(0.78, 0.86, 0.62, 1.0)
	match style:
		GROUND_RUST:
			var blot := _hash21(uv * 0.09)
			var blot2 := _hash21(uv * 0.37)
			colour = Color(0.40, 0.38, 0.36).lerp(Color(0.62, 0.30, 0.16), blot)
			colour = colour.lerp(Color(0.58, 0.44, 0.32), blot2 * 0.55)
			colour = colour.lerp(Color(0.70, 0.64, 0.56), n3 * 0.28)
			if n4 > 0.84:
				colour = colour.lerp(Color(0.28, 0.24, 0.22), 0.45)
		GROUND_PURPLE:
			colour = Color(0.70, 0.58, 0.80).lerp(Color(0.52, 0.42, 0.68), n)
			colour = colour.lerp(Color(0.62, 0.54, 0.72), n2)
			if n3 > 0.78:
				colour = colour.lerp(Color(0.86, 0.74, 0.92), 0.50)
			if n4 > 0.88:
				colour = colour.lerp(Color(0.38, 0.30, 0.48), 0.40)
		GROUND_BRICK:
			var gx := fposmod(uv.x / 0.92, 1.0)
			var gy := fposmod(uv.y / 0.46 + floor(uv.x / 0.92) * 0.5, 1.0)
			if gx < 0.12 or gy < 0.18:
				colour = Color(0.38, 0.34, 0.32).lerp(Color(0.46, 0.42, 0.38), n5)
			else:
				var brick := Color(0.60, 0.30, 0.24).lerp(Color(0.74, 0.42, 0.30), n)
				brick = brick.lerp(Color(0.52, 0.28, 0.22), n3 * 0.35)
				colour = brick
			if n4 > 0.92:
				colour = colour.lerp(Color(0.22, 0.20, 0.18), 0.55)
		_:
			colour = Color(0.26, 0.46, 0.22).lerp(Color(0.40, 0.58, 0.26), n)
			colour = colour.lerp(Color(0.34, 0.52, 0.24), n2)
			if n2 > 0.80:
				colour = colour.lerp(Color(0.42, 0.34, 0.22), 0.55)
			if n3 > 0.90:
				var petal := int(floor(_hash21(uv * 3.1) * 4.0))
				if petal == 0:
					colour = Color(0.92, 0.42, 0.58)
				elif petal == 1:
					colour = Color(0.96, 0.86, 0.28)
				elif petal == 2:
					colour = Color(0.96, 0.94, 0.90)
				else:
					colour = Color(0.52, 0.62, 0.92)
			colour = colour.lerp(colour * (0.82 + 0.28 * n5), 0.35)
	colour = colour.lerp(accent, 0.14)
	colour = colour.lerp(colour * (0.90 + 0.18 * n4), 0.40)
	return colour


func _paint_ground_map() -> void:
	if _pad_tops.is_empty() or _pad_cell <= 0.1:
		return
	var bounds := _pad_uv_bounds()
	if bounds.size.x < 4.0 or bounds.size.y < 4.0:
		return
	_ground_origin = bounds.position
	_ground_span = bounds.size
	var span_m := maxf(_ground_span.x, _ground_span.y)
	var size := clampi(int(round(span_m / GROUND_TEXEL)), GROUND_TEX_MIN, GROUND_TEX_MAX)
	var data := PackedByteArray()
	data.resize(size * size * 3)
	_fill_ground_pixels(data, size)
	_stamp_wall_shade(data, size)
	_stamp_roads(data, size)
	var img := Image.create(size, size, false, Image.FORMAT_RGB8)
	img.set_data(size, size, false, Image.FORMAT_RGB8, data)
	img.generate_mipmaps()
	_ground_image = img
	_ground_tex = ImageTexture.create_from_image(img)
	_remap_pavement_map()
	print("patch_city:     ground map %dx%d  %.2f m/px" % [
		size, size, span_m / float(size)])


func _pad_uv_bounds() -> Rect2:
	var cell := _pad_cell
	var min_x := 1.0e9
	var min_y := 1.0e9
	var max_x := -1.0e9
	var max_y := -1.0e9
	for key in _pad_tops:
		var at: Vector2i = key
		var x := float(at.x) * cell
		var y := float(at.y) * cell
		min_x = minf(min_x, x)
		min_y = minf(min_y, y)
		max_x = maxf(max_x, x)
		max_y = maxf(max_y, y)
	var pad := cell * 1.5
	return Rect2(
		Vector2(min_x - pad, min_y - pad),
		Vector2(max_x - min_x + pad * 2.0, max_y - min_y + pad * 2.0))


func _city_to_px(uv: Vector2, size: int) -> Vector2i:
	var x := int(floor((uv.x - _ground_origin.x) / _ground_span.x * float(size)))
	var y := int(floor((uv.y - _ground_origin.y) / _ground_span.y * float(size)))
	return Vector2i(clampi(x, 0, size - 1), clampi(y, 0, size - 1))


func _px_to_city(px: int, py: int, size: int) -> Vector2:
	return _ground_origin + Vector2(
		(float(px) + 0.5) / float(size) * _ground_span.x,
		(float(py) + 0.5) / float(size) * _ground_span.y)


func _put_rgb(data: PackedByteArray, size: int, px: int, py: int, colour: Color) -> void:
	var o := (py * size + px) * 3
	if o < 0 or o + 2 >= data.size():
		return
	data[o] = clampi(int(colour.r * 255.0), 0, 255)
	data[o + 1] = clampi(int(colour.g * 255.0), 0, 255)
	data[o + 2] = clampi(int(colour.b * 255.0), 0, 255)


func _get_rgb(data: PackedByteArray, size: int, px: int, py: int) -> Color:
	var o := (py * size + px) * 3
	if o < 0 or o + 2 >= data.size():
		return Color.BLACK
	return Color(
		float(data[o]) / 255.0,
		float(data[o + 1]) / 255.0,
		float(data[o + 2]) / 255.0)


func _fill_ground_pixels(data: PackedByteArray, size: int) -> void:
	var cell := _pad_cell
	for key in _pad_tops:
		var at: Vector2i = key
		var district_id := int(_pad_owner.get(at, -1))
		var origin := Vector2(float(at.x) * cell, float(at.y) * cell)
		var a := _city_to_px(origin + Vector2(-cell * 0.5, -cell * 0.5), size)
		var b := _city_to_px(origin + Vector2(cell * 0.5, cell * 0.5), size)
		var x0 := mini(a.x, b.x)
		var x1 := maxi(a.x, b.x)
		var y0 := mini(a.y, b.y)
		var y1 := maxi(a.y, b.y)
		for py in range(y0, y1 + 1):
			for px in range(x0, x1 + 1):
				var uv := _px_to_city(px, py, size)
				_put_rgb(data, size, px, py, _walk_base(uv, district_id))


func _stamp_wall_shade(data: PackedByteArray, size: int) -> void:
	var cell := _pad_cell
	for lot in fabric.get("lots", []):
		var row: Dictionary = lot
		if not _lot_on_slab(row):
			continue
		var centre: Vector2 = row.get("centre", Vector2.ZERO)
		var along: Vector2 = row.get("along", Vector2.RIGHT)
		if along.length_squared() < 0.0001:
			along = Vector2.RIGHT
		along = along.normalized()
		var across := Vector2(-along.y, along.x)
		var half_w := float(row.get("width", 8.0)) * 0.5
		var half_d := float(row.get("depth", 8.0)) * 0.5
		var reach := maxf(half_w, half_d) + WALL_SHADE
		var a := _city_to_px(centre - Vector2(reach, reach), size)
		var b := _city_to_px(centre + Vector2(reach, reach), size)
		var x0 := mini(a.x, b.x)
		var x1 := maxi(a.x, b.x)
		var y0 := mini(a.y, b.y)
		var y1 := maxi(a.y, b.y)
		for py in range(y0, y1 + 1):
			for px in range(x0, x1 + 1):
				var uv := _px_to_city(px, py, size)
				var key := Vector2i(roundi(uv.x / cell), roundi(uv.y / cell))
				if not _pad_tops.has(key):
					continue
				var local := uv - centre
				var dx := absf(local.dot(along)) - half_w
				var dy := absf(local.dot(across)) - half_d
				var d := maxf(dx, dy)
				if dx > 0.0 and dy > 0.0:
					d = Vector2(dx, dy).length()
				if d > WALL_SHADE:
					continue
				var shade := clampf(maxf(d, 0.0) / WALL_SHADE, 0.0, 1.0)
				shade = shade * shade * (3.0 - 2.0 * shade)
				var colour := _get_rgb(data, size, px, py)
				if colour.r + colour.g + colour.b < 0.04:
					continue
				_put_rgb(data, size, px, py, colour.darkened(0.38 * (1.0 - shade)))


func _stamp_roads(data: PackedByteArray, size: int) -> void:
	var cell := _pad_cell
	var blend := PAVEMENT_BLEND
	for item in _road_index:
		var row: Dictionary = item
		var a: Vector2 = row["a"]
		var b: Vector2 = row["b"]
		var half := float(row["half"])
		var pad := half + blend + 1.6
		var min_uv := Vector2(minf(a.x, b.x) - pad, minf(a.y, b.y) - pad)
		var max_uv := Vector2(maxf(a.x, b.x) + pad, maxf(a.y, b.y) + pad)
		var pa := _city_to_px(min_uv, size)
		var pb := _city_to_px(max_uv, size)
		var x0 := mini(pa.x, pb.x)
		var x1 := maxi(pa.x, pb.x)
		var y0 := mini(pa.y, pb.y)
		var y1 := maxi(pa.y, pb.y)
		for py in range(y0, y1 + 1):
			for px in range(x0, x1 + 1):
				var uv := _px_to_city(px, py, size)
				var key := Vector2i(roundi(uv.x / cell), roundi(uv.y / cell))
				if not _pad_tops.has(key):
					continue
				var edge := _seg_distance(uv, a, b) - half
				if edge > blend:
					continue
				var t := clampf((edge + blend) / maxf(blend * 2.0, 0.001), 0.0, 1.0)
				t = t * t * (3.0 - 2.0 * t)
				var walk := _get_rgb(data, size, px, py)
				var n := _hash21(uv * 6.4)
				var asphalt := Color(0.045, 0.045, 0.05).lerp(Color(0.09, 0.09, 0.10), n * 0.55)
				_put_rgb(data, size, px, py, asphalt.lerp(walk, t))


func _remap_pavement_map() -> void:
	if _ground_tex == null or _pad_tops.is_empty():
		return
	_discard_node(_pavement)
	_pavement = null
	_pavement_mat = null
	var st := SurfaceTool.new()
	st.begin(Mesh.PRIMITIVE_TRIANGLES)
	var cell := _pad_cell
	for key in _pad_tops:
		if _pavement_holes.has(key):
			continue
		var at: Vector2i = key
		_emit_mapped_cell(st, at, cell)
	var mesh := st.commit()
	if mesh.get_surface_count() == 0:
		return
	var material := ShaderMaterial.new()
	material.shader = GROUND_SHADER
	material.set_shader_parameter(&"ground_map", _ground_tex)
	material.set_shader_parameter(&"map_span", _ground_span)
	material.set_shader_parameter(&"map_origin", _ground_origin)
	material.set_shader_parameter(&"night", 0.0)
	_lamp_map = null
	_bind_lamp_map(material)
	_pavement_mat = material
	_pavement = MeshInstance3D.new()
	_pavement.name = "PavementPaint"
	_pavement.mesh = mesh
	_pavement.material_override = material
	_pavement.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_ON
	_pavement.sorting_offset = 0.0
	add_child(_pavement)
	_bind_break_map()


func _emit_mapped_cell(st: SurfaceTool, at: Vector2i, cell: float) -> void:
	var top_h := float(_pad_tops[at]) + PAVEMENT_LIFT
	var corners := _cell_corners(at, cell)
	var pts := PackedVector3Array()
	var uvs := PackedVector2Array()
	pts.resize(4)
	uvs.resize(4)
	for index in 4:
		var uv: Vector2 = corners[index]
		pts[index] = _from_uv(uv).normalized() * (_radius + top_h)
		uvs[index] = Vector2(
			(uv.x - _ground_origin.x) / _ground_span.x,
			(uv.y - _ground_origin.y) / _ground_span.y)
	_face_uv(st, pts[0], pts[1], pts[2], pts[3], uvs[0], uvs[1], uvs[2], uvs[3], pts[0])


func _ground_map_color(uv: Vector2) -> Color:
	if _ground_image == null:
		return Color.BLACK
	var w := _ground_image.get_width()
	var h := _ground_image.get_height()
	if w < 2 or h < 2 or _ground_span.x < 0.1 or _ground_span.y < 0.1:
		return Color.BLACK
	var px := clampi(
		int(floor((uv.x - _ground_origin.x) / _ground_span.x * float(w))), 0, w - 1)
	var py := clampi(
		int(floor((uv.y - _ground_origin.y) / _ground_span.y * float(h))), 0, h - 1)
	return _ground_image.get_pixel(px, py)


func _recolor_walks() -> void:
	_paint_ground_map()


func _district_at_uv(uv: Vector2) -> int:
	if _pad_cell <= 0.1:
		return -1
	var key := Vector2i(roundi(uv.x / _pad_cell), roundi(uv.y / _pad_cell))
	return int(_pad_owner.get(key, -1))


func _hash21(p: Vector2) -> float:
	var n := sin(p.dot(Vector2(127.1, 311.7))) * 43758.5453
	return n - floor(n)


func _lot_paint_albedo(lot: Dictionary) -> Color:
	var tint: Color = lot.get("paint_tint", Color(0.62, 0.50, 0.40))
	tint.a = float(int(lot.get("paint_style", 0))) / 20.0
	return tint


func _lot_wall_polys(lot: Dictionary) -> Array:
	var variant: int = int(lot.get("variant", VARIANT_RECT))
	if variant == VARIANT_CYLINDER:
		var cylinder := _lot_cylinder_uv(lot)
		if _poly_building_ok(cylinder):
			return [cylinder]
		return []
	if variant == VARIANT_ROUND_END:
		var round_end := _lot_round_end_uv(lot)
		if _poly_building_ok(round_end):
			return [round_end]
		return []
	var footprints: Array = lot.get("footprints", [])
	var kept: Array = []
	for piece in footprints:
		var poly: PackedVector2Array = piece
		if _poly_building_ok(poly):
			kept.append(poly)
	return kept


func _lot_body_frac(variant: int) -> float:
	match variant:
		VARIANT_RECT_CAP:
			return 0.70
		VARIANT_GABLE:
			return 0.74
		VARIANT_POINT_HALF, VARIANT_SLANT_HALF:
			return 0.78
		VARIANT_CYL_HALF:
			return 0.52
	return 1.0


func _lot_wall_rise(lot: Dictionary) -> float:
	return float(lot["stories"]) * 3.15 * _lot_body_frac(int(lot.get("variant", VARIANT_RECT)))


func _lot_cap_scale(variant: int) -> float:
	if variant == VARIANT_CYL_HALF:
		return 0.46
	return 0.36


func _lot_facade_rings(lot: Dictionary) -> Array:
	var rise := float(lot["stories"]) * 3.15
	var variant: int = int(lot.get("variant", VARIANT_RECT))
	var body := _lot_wall_rise(lot)
	var pieces := _lot_wall_polys(lot)
	var rings: Array = []
	if variant == VARIANT_TAPER:
		var levels := _taper_levels(lot)
		var story := rise / float(levels)
		for piece in pieces:
			var poly: PackedVector2Array = piece
			for index in levels:
				var t := float(index) / float(maxi(levels - 1, 1))
				var scaled := _scale_poly(poly, 1.0 - 0.18 * t)
				if not _poly_building_ok(scaled):
					continue
				rings.append({
					"poly": scaled,
					"lift": story * float(index),
					"height": story,
					"door": index == 0,
					"bury": true,
				})
		return rings
	for piece in pieces:
		var poly: PackedVector2Array = piece
		rings.append({
			"poly": poly,
			"lift": 0.0,
			"height": body,
			"door": true,
			"bury": true,
		})
	if variant != VARIANT_CYL_HALF and variant != VARIANT_RECT_CAP:
		return rings
	var cap_h := rise - body
	if cap_h < 2.2:
		return rings
	var scale := _lot_cap_scale(variant)
	for piece in pieces:
		var poly: PackedVector2Array = piece
		var drum := _lot_cap_cylinder_uv(lot, poly, scale)
		if drum.size() < 6 or not _poly_building_ok(drum):
			continue
		rings.append({
			"poly": drum,
			"lift": body,
			"height": cap_h,
			"door": false,
			"bury": false,
		})
	return rings


func _taper_levels(lot: Dictionary) -> int:
	return clampi(int(round(float(lot["stories"]))), 3, 24)


func _facade_story_count(wall_h: float, win_h: float) -> int:
	var y := 0.48
	var top := wall_h - 0.28 - win_h
	var n := 0
	while y <= top + 0.001 and n < 80:
		n += 1
		y += 3.15
	return n


func _dress_buildings(shape: PlanetShape) -> void:
	_discard_node(_paint_small)
	_paint_small = null
	_discard_node(_paint_large)
	_paint_large = null
	_discard_node(_windows_small)
	_windows_small = null
	_discard_node(_windows_large)
	_windows_large = null
	_window_small_mat = null
	_window_large_mat = null
	_discard_node(_lot_root)
	_lot_root = null
	_buildings.clear()
	_pending_blasts.clear()
	_ensure_wall_materials()
	_ensure_window_materials()
	var lots: Array = fabric.get("lots", [])
	if lots.is_empty():
		return
	_lot_root = Node3D.new()
	_lot_root.name = "CityLots"
	add_child(_lot_root)
	if not is_in_group(DamageHit.BUILDING_GROUP):
		add_to_group(DamageHit.BUILDING_GROUP)
	for index in lots.size():
		var row: Dictionary = lots[index]
		if not _lot_on_slab(row):
			continue
		var building = CITY_BUILDING_SCRIPT.new()
		_lot_root.add_child(building)
		building.setup(self, index, row, shape)
		_buildings.append(building)
	_paint_small = _make_paint_hook("CityPaintSmall", false)
	_paint_large = _make_paint_hook("CityPaintLarge", true)
	_windows_small = _make_window_hook("CityWindowsSmall", false)
	_windows_large = _make_window_hook("CityWindowsLarge", true)
	if is_instance_valid(_solid_buildings):
		_solid_buildings.visible = false
	if is_instance_valid(_solid_body):
		_solid_body.collision_layer = 0
		_solid_body.collision_mask = 0


func _dress_lot_facade(
		hull: SurfaceTool,
		glass: SurfaceTool,
		shape: PlanetShape,
		lot: Dictionary,
		large: bool
	) -> void:
	var trim: Color = lot.get("paint_trim", Color(0.16, 0.16, 0.18))
	trim.a = 19.0 / 20.0
	var door := Color(0.12, 0.12, 0.14) if large else Color(0.22, 0.14, 0.10)
	door.a = 19.0 / 20.0
	var glass_col: Color = lot.get(
		"paint_glass", Color(0.70, 0.78, 0.84) if large else Color(0.16, 0.14, 0.12))
	var road_at := _nearest_road_point(lot.get("centre", Vector2.ZERO))
	var pitch := 2.35 if large else 3.15
	var win_w := 1.55 if large else 1.15
	var win_h := 2.15 if large else 1.45
	var door_w := 2.7 if large else 1.2
	var door_h := 3.4 if large else 2.4
	var blockers := _lot_wall_polys(lot)
	for ring in _lot_facade_rings(lot):
		var row: Dictionary = ring
		var poly: PackedVector2Array = row["poly"]
		var lift := float(row["lift"])
		var wall_h := float(row["height"])
		if poly.size() < 3 or wall_h < 2.2 or not _poly_building_ok(poly):
			continue
		_dress_poly_facade(
			hull, glass, shape, lot, poly, lift, wall_h, large, bool(row["door"]),
			bool(row.get("bury", true)), blockers, road_at, trim, door, glass_col,
			pitch, win_w, win_h, door_w, door_h)


func _dress_poly_facade(
		hull: SurfaceTool,
		glass: SurfaceTool,
		shape: PlanetShape,
		lot: Dictionary,
		poly: PackedVector2Array,
		lift: float,
		wall_h: float,
		large: bool,
		want_door: bool,
		bury: bool,
		blockers: Array,
		road_at: Vector2,
		trim: Color,
		door: Color,
		glass_col: Color,
		pitch: float,
		win_w: float,
		win_h: float,
		door_w: float,
		door_h: float
	) -> void:
	var mid := _poly_mid(poly)
	var door_edge := _door_edge(poly, mid, road_at) if want_door else -1
	var stories := _facade_story_count(wall_h, win_h)
	var neon := _lot_neon_trim(lot, large)
	for index in poly.size():
		var a: Vector2 = poly[index]
		var b: Vector2 = poly[(index + 1) % poly.size()]
		var chord := b - a
		var run := chord.length()
		if run < (0.85 if lift > 0.5 else 1.6):
			continue
		var along := chord / run
		var out2 := Vector2(-along.y, along.x)
		if (mid - (a + b) * 0.5).dot(out2) > 0.0:
			out2 = -out2
		if bury and _edge_buried(a, b, out2, poly, blockers):
			continue
		var up_a := _from_uv(a).normalized()
		var up_b := _from_uv(b).normalized()
		var base_a := _deck_mark(shape, up_a, STREET_LIFT)
		var base_b := _deck_mark(shape, up_b, STREET_LIFT)
		var up_mid := up_a.lerp(up_b, 0.5).normalized()
		var out3 := (base_b - base_a).cross(up_mid).normalized()
		var inward := _deck_mark(shape, _from_uv(mid).normalized(), STREET_LIFT)
		var edge_pt := base_a.lerp(base_b, 0.5)
		if out3.dot(inward - edge_pt) > 0.0:
			out3 = -out3
		var bays := clampi(int(round(run / pitch)), 1, 40)
		var half := minf((win_w * 0.5) / run, 0.42)
		var is_door := index == door_edge
		if large:
			if neon.a > 0.5:
				var alt: Color = lot.get("paint_neon_alt", neon)
				alt.a = neon.a
				_emit_neon_trims(
					hull, base_a, base_b, up_a, up_b, out3, lift, wall_h, run, neon, alt,
					bool(lot.get("night_crown", false)))
			else:
				_emit_facade_span(
					hull, base_a, base_b, up_a, up_b, out3,
					0.5, lift + 0.0, 0.48, 0.52, trim, 0.03)
				_emit_facade_span(
					hull, base_a, base_b, up_a, up_b, out3,
					0.5, lift + wall_h - 0.40, 0.48, 0.36, trim, 0.03)
		if is_door:
			_emit_facade_span(
				hull, base_a, base_b, up_a, up_b, out3,
				0.5, lift + 0.12, minf((door_w * 0.5) / run, 0.42), door_h, door, 0.05)
		for story in stories:
			var y0 := lift + 0.48 + 3.15 * float(story)
			if y0 + win_h > lift + wall_h - 0.28:
				continue
			for bay in bays:
				var t := (float(bay) + 0.5) / float(bays)
				if is_door and story == 0 and absf(t - 0.5) < (door_w * 0.7) / run:
					continue
				_emit_facade_span(
					glass, base_a, base_b, up_a, up_b, out3,
					t, y0, half, win_h,
					_lit_window_color(lot, story, bay, index, large, glass_col), 0.012)


func _lot_neon_trim(lot: Dictionary, large: bool) -> Color:
	if not large:
		return Color(0, 0, 0, 0)
	if not bool(lot.get("night_crown", false)) and not bool(lot.get("night_trim", false)):
		return Color(0, 0, 0, 0)
	var neon: Color = lot.get("paint_neon", Color(0, 0, 0, 0))
	if neon.r + neon.g + neon.b < 0.45:
		return Color(0, 0, 0, 0)
	neon.a = float(PAINT_NEON) / 20.0
	return neon


func _emit_neon_trims(
		st: SurfaceTool,
		base_a: Vector3,
		base_b: Vector3,
		up_a: Vector3,
		up_b: Vector3,
		out3: Vector3,
		lift: float,
		wall_h: float,
		run: float,
		neon: Color,
		alt: Color,
		crown: bool
	) -> void:
	_emit_facade_span(
		st, base_a, base_b, up_a, up_b, out3,
		0.5, lift, 0.48, 0.22, neon, 0.06)
	_emit_facade_span(
		st, base_a, base_b, up_a, up_b, out3,
		0.5, lift + wall_h - 0.22, 0.48, 0.22, neon, 0.06)
	var band := 3.15 * 4.0
	var y := lift + band
	var use_alt := false
	while y < lift + wall_h - 0.55:
		_emit_facade_span(
			st, base_a, base_b, up_a, up_b, out3,
			0.5, y, 0.48, 0.11, alt if use_alt else neon, 0.055)
		use_alt = not use_alt
		y += band
	var vhalf := minf(0.09 / maxf(run, 0.2), 0.04)
	_emit_facade_span(
		st, base_a, base_b, up_a, up_b, out3,
		vhalf, lift, vhalf, wall_h, neon, 0.05)
	_emit_facade_span(
		st, base_a, base_b, up_a, up_b, out3,
		1.0 - vhalf, lift, vhalf, wall_h, alt, 0.05)
	if crown:
		_emit_facade_span(
			st, base_a, base_b, up_a, up_b, out3,
			0.5, lift + wall_h - 0.62, 0.50, 0.42, alt, 0.085)
		_emit_facade_span(
			st, base_a, base_b, up_a, up_b, out3,
			0.5, lift + wall_h * 0.58, 0.50, 0.16, neon, 0.07)
		var edge := minf(0.14 / maxf(run, 0.2), 0.06)
		_emit_facade_span(
			st, base_a, base_b, up_a, up_b, out3,
			edge, lift, edge, wall_h, alt, 0.065)
		_emit_facade_span(
			st, base_a, base_b, up_a, up_b, out3,
			1.0 - edge, lift, edge, wall_h, neon, 0.065)


func _lit_window_color(
		lot: Dictionary,
		story: int,
		bay: int,
		edge: int,
		large: bool,
		_glass_col: Color
	) -> Color:
	var centre: Vector2 = lot.get("centre", Vector2.ZERO)
	if not large:
		# Houses and walk-ups: occupied rooms glow warm orange.
		var house := _hash21(centre + Vector2(
			float(story) * 2.11 + float(edge) * 0.37,
			float(bay) * 4.07))
		if house < 0.18:
			return Color(0.22, 0.16, 0.10)
		if house < 0.34:
			return Color(1.0, 0.42, 0.06)
		return Color(1.0, 0.50, 0.08)
	var roll := _hash21(centre + Vector2(
		float(story) * 1.73 + float(edge) * 0.41,
		float(bay) * 3.11))
	if roll < 0.14:
		return Color(0.10, 0.11, 0.13)
	if roll < 0.68:
		return Color(0.90, 0.94, 1.0)
	if roll < 0.78:
		return Color(1.0, 0.82, 0.56)
	if roll < 0.90:
		var neon: Color = lot.get("paint_neon", Color(1.0, 0.18, 0.72))
		neon.a = 1.0
		return neon
	var alt: Color = lot.get("paint_neon_alt", Color(0.18, 0.92, 1.0))
	alt.a = 1.0
	return alt


func _extra_neon_color(roll: float) -> Color:
	var pal: Array = [
		Color(1.0, 0.18, 0.72),
		Color(0.18, 0.92, 1.0),
		Color(0.68, 0.22, 1.0),
		Color(0.32, 1.0, 0.42),
		Color(1.0, 0.52, 0.10),
	]
	return pal[int(floor(roll * 80.0)) % pal.size()]


func _door_edge(poly: PackedVector2Array, mid: Vector2, road_at: Vector2) -> int:
	var want := road_at - mid
	if want.length_squared() < 0.01:
		want = Vector2.RIGHT
	want = want.normalized()
	var best := 0
	var score := -1.0e9
	for index in poly.size():
		var a: Vector2 = poly[index]
		var b: Vector2 = poly[(index + 1) % poly.size()]
		var chord := b - a
		if chord.length_squared() < 1.0:
			continue
		var along := chord.normalized()
		var out2 := Vector2(-along.y, along.x)
		var edge_mid := (a + b) * 0.5
		if (mid - edge_mid).dot(out2) > 0.0:
			out2 = -out2
		var d := out2.dot(want)
		if d > score:
			score = d
			best = index
	return best


func _edge_buried(
		a: Vector2,
		b: Vector2,
		out2: Vector2,
		self_poly: PackedVector2Array,
		blockers: Array
	) -> bool:
	var probe: Vector2 = (a + b) * 0.5 + out2 * 0.65
	var self_ring := _poly_ccw(self_poly)
	if self_ring.size() >= 3 and Geometry2D.is_point_in_polygon(probe, self_ring):
		return true
	var home := _poly_mid(self_poly)
	for item in blockers:
		var other: PackedVector2Array = item
		if other.size() < 3:
			continue
		var ring := _poly_ccw(other)
		if ring.size() < 3:
			continue
		if Geometry2D.is_point_in_polygon(home, ring):
			continue
		if Geometry2D.is_point_in_polygon(probe, ring):
			return true
	return false


func _poly_ccw(poly: PackedVector2Array) -> PackedVector2Array:
	var ring := PackedVector2Array(poly)
	if ring.size() >= 3 and Geometry2D.is_polygon_clockwise(ring):
		ring.reverse()
	return ring


func _nearest_road_point(uv: Vector2) -> Vector2:
	var best := uv
	var dist := 1.0e9
	var bin := 36.0
	var cx := int(floor(uv.x / bin))
	var cy := int(floor(uv.y / bin))
	for ox in range(-1, 2):
		for oy in range(-1, 2):
			var key := Vector2i(cx + ox, cy + oy)
			if not _road_bins.has(key):
				continue
			var list: Array = _road_bins[key]
			for idx in list:
				var row: Dictionary = _road_index[int(idx)]
				var a: Vector2 = row["a"]
				var b: Vector2 = row["b"]
				var ab := b - a
				var run := ab.length_squared()
				var t := 0.0
				if run >= 0.0001:
					t = clampf((uv - a).dot(ab) / run, 0.0, 1.0)
				var at := a.lerp(b, t)
				var d := uv.distance_squared_to(at)
				if d < dist:
					dist = d
					best = at
	return best


func _emit_facade_span(
		st: SurfaceTool,
		base_a: Vector3,
		base_b: Vector3,
		up_a: Vector3,
		up_b: Vector3,
		out3: Vector3,
		t: float,
		lift: float,
		half: float,
		height: float,
		colour: Color,
		push: float
	) -> void:
	var t0 := clampf(t - half, 0.0, 1.0)
	var t1 := clampf(t + half, 0.0, 1.0)
	var p0 := _facade_point(base_a, base_b, up_a, up_b, t0, lift, out3, push)
	var p1 := _facade_point(base_a, base_b, up_a, up_b, t1, lift, out3, push)
	var p2 := _facade_point(base_a, base_b, up_a, up_b, t1, lift + height, out3, push)
	var p3 := _facade_point(base_a, base_b, up_a, up_b, t0, lift + height, out3, push)
	_face(st, p0, p1, p2, p3, colour, out3)


func _facade_point(
		base_a: Vector3,
		base_b: Vector3,
		up_a: Vector3,
		up_b: Vector3,
		t: float,
		lift: float,
		out3: Vector3,
		push: float
	) -> Vector3:
	var up := up_a.lerp(up_b, t).normalized()
	return base_a.lerp(base_b, t) + up * lift + out3 * push


func _commit_wall_mesh(st: SurfaceTool, mesh_name: String, large: bool) -> MeshInstance3D:
	var mesh := st.commit()
	if mesh.get_surface_count() == 0:
		return null
	var instance := MeshInstance3D.new()
	instance.name = mesh_name
	instance.mesh = mesh
	instance.material_override = wall_material_for(large)
	instance.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_ON
	add_child(instance)
	return instance


func _commit_window_mesh(st: SurfaceTool, mesh_name: String, large: bool) -> MeshInstance3D:
	var mesh := st.commit()
	if mesh.get_surface_count() == 0:
		return null
	var instance := MeshInstance3D.new()
	instance.name = mesh_name
	instance.mesh = mesh
	instance.material_override = window_material_for(large)
	instance.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	add_child(instance)
	return instance


func wall_material_for(large: bool) -> ShaderMaterial:
	_ensure_wall_materials()
	return _wall_large_mat if large else _wall_small_mat


func window_material_for(large: bool) -> ShaderMaterial:
	_ensure_window_materials()
	return _window_large_mat if large else _window_small_mat


func _ensure_wall_materials() -> void:
	if _wall_small_mat == null:
		_wall_small_mat = ShaderMaterial.new()
		_wall_small_mat.shader = WALL_SHADER
		_wall_small_mat.set_shader_parameter(&"roughness_val", 0.88)
		_wall_small_mat.set_shader_parameter(&"metallic_val", 0.05)
		_wall_small_mat.set_shader_parameter(&"night", 0.0)
		_wall_small_mat.set_shader_parameter(&"use_paint", 0.0)
	if _wall_large_mat == null:
		_wall_large_mat = ShaderMaterial.new()
		_wall_large_mat.shader = WALL_SHADER
		_wall_large_mat.set_shader_parameter(&"roughness_val", 0.52)
		_wall_large_mat.set_shader_parameter(&"metallic_val", 0.08)
		_wall_large_mat.set_shader_parameter(&"night", 0.0)
		_wall_large_mat.set_shader_parameter(&"use_paint", 0.0)


func _ensure_window_materials() -> void:
	if _window_small_mat == null:
		_window_small_mat = ShaderMaterial.new()
		_window_small_mat.shader = WINDOW_SHADER
		_window_small_mat.set_shader_parameter(&"night", 0.0)
	_window_small_mat.shader = WINDOW_SHADER
	_window_small_mat.set_shader_parameter(
		&"fallback_glow", Color(1.0, 0.52, 0.16))
	if _window_large_mat == null:
		_window_large_mat = ShaderMaterial.new()
		_window_large_mat.shader = WINDOW_SHADER
		_window_large_mat.set_shader_parameter(&"night", 0.0)
	_window_large_mat.shader = WINDOW_SHADER
	_window_large_mat.set_shader_parameter(
		&"fallback_glow", Color(0.88, 0.93, 1.0))


func _make_paint_hook(mesh_name: String, large: bool) -> MeshInstance3D:
	var mesh: Mesh
	for building in _buildings:
		if building.is_large() != large:
			continue
		mesh = building.hull_mesh()
		if mesh != null:
			break
	if mesh == null:
		return null
	var instance := MeshInstance3D.new()
	instance.name = mesh_name
	instance.mesh = mesh
	instance.material_override = wall_material_for(large)
	instance.visible = false
	instance.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	add_child(instance)
	return instance


func _make_window_hook(mesh_name: String, large: bool) -> MeshInstance3D:
	var mesh: Mesh
	for building in _buildings:
		if building.is_large() != large:
			continue
		mesh = building.glass_mesh()
		if mesh != null:
			break
	if mesh == null:
		return null
	var instance := MeshInstance3D.new()
	instance.name = mesh_name
	instance.mesh = mesh
	instance.material_override = window_material_for(large)
	instance.visible = false
	instance.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	add_child(instance)
	return instance


func destructible_buildings() -> Array:
	return _buildings


func apply_damage(hit: DamageHit) -> float:
	if hit == null or _buildings.is_empty():
		return 0.0
	var origin := Vector3.ZERO
	if is_inside_tree():
		origin = global_transform * (_up * _radius)
	else:
		origin = _up * _radius
	if not hit.reaches(origin, city_extent() + 80.0):
		return 0.0
	var absorbed := 0.0
	for building in _buildings:
		if is_instance_valid(building):
			var lost: float = float(building.apply_hit(hit))
			absorbed += lost
			if lost > 0.0:
				_report_building_hit(building, lost, hit)
	return absorbed


func _report_building_hit(building: Node, amount: float, hit: DamageHit) -> void:
	var source := hit.source_node(self)
	if source == null and hit != null and hit.source_peer > 0 and is_inside_tree():
		for node in get_tree().get_nodes_in_group(DamageHit.COMBATANT_GROUP):
			if node == null or not node.has_method(&"combat_peer_id") \
					or int(node.call(&"combat_peer_id")) != hit.source_peer:
				continue
			source = node
			break
	if source != null and source.has_method(&"building_damage_dealt"):
		source.call(&"building_damage_dealt", building, amount, hit)


func queue_building_blast(building: Node) -> void:
	if building == null or not is_instance_valid(building):
		return
	_pending_blasts.append(building)
	call_deferred(&"_flush_building_blasts")


func flush_building_blasts() -> void:
	_flush_building_blasts()


func _flush_building_blasts() -> void:
	if _pending_blasts.is_empty():
		return
	var pending: Array = _pending_blasts.duplicate()
	_pending_blasts.clear()
	for building_variant in pending:
		var building: Node = building_variant
		if building == null or not is_instance_valid(building):
			continue
		if not building.has_method(&"collapse_hit"):
			continue
		var hit: DamageHit = building.call(&"collapse_hit")
		if hit == null:
			continue
		if DamageHit.game_world_of(self) != null:
			DamageHit.apply_to_world(self, hit)
		else:
			apply_damage(hit)


func _solidify_buildings(shape: PlanetShape) -> void:
	_cull_overlapping_lots()
	_discard_node(_solid_buildings)
	_solid_buildings = null
	_discard_node(_solid_body)
	_solid_body = null
	var lots: Array = fabric.get("lots", [])
	if lots.is_empty():
		return
	var st := SurfaceTool.new()
	st.begin(Mesh.PRIMITIVE_TRIANGLES)
	for lot in lots:
		if not _lot_on_slab(lot):
			continue
		_emit_lot_box(st, shape, lot, true)
	_solid_buildings = _commit_mesh(st, "CityBuildings", false)
	if is_instance_valid(_solid_buildings):
		_solid_buildings.sorting_offset = 0.0
		_solid_body = _collide(_solid_buildings.mesh, "CityBuildingsBody")


func _paint_pavement(shape: PlanetShape, visual_only: bool = false) -> void:
	_discard_node(_pavement)
	_pavement = null
	_pavement_mat = null
	if not visual_only:
		_discard_node(_pavement_body)
		_pavement_body = null
	if _pad_tops.is_empty() or shape == null:
		return
	var vis := SurfaceTool.new()
	vis.begin(Mesh.PRIMITIVE_TRIANGLES)
	var cell := _pad_cell
	for key in _pad_tops:
		if _pavement_holes.has(key):
			continue
		var at: Vector2i = key
		_emit_pavement_top(vis, at, cell)
	_pavement = _commit_mesh(vis, "PavementPaint", false)
	if is_instance_valid(_pavement):
		_pavement.sorting_offset = 0.0
	if not _pad_islands.is_empty():
		_emit_island_aprons(shape, _pad_islands)
	_rebuild_city_rim(shape)
	if is_instance_valid(_ground):
		_ground.visible = false
	if visual_only:
		return
	_build_pavement_collision(shape)
	if is_instance_valid(_ground_body):
		_ground_body.collision_layer = 0
		_ground_body.collision_mask = 0


func _emit_pavement_cell(
		st: SurfaceTool,
		shape: PlanetShape,
		at: Vector2i,
		cell: float,
		colour: Color
	) -> void:
	var top_h := float(_pad_tops[at]) + PAVEMENT_LIFT
	var corners := _cell_corners(at, cell)
	var top: Array[Vector3] = []
	var bottom: Array[Vector3] = []
	for corner in corners:
		var direction := _from_uv(corner).normalized()
		top.append(direction * (_radius + top_h))
		bottom.append(direction * (_radius + _pavement_bot(shape, corner, top_h)))
	# Walkable lid only. A closed box that buried into the planet put every
	# stride on the hillside *inside* a concave volume, which is how a body
	# walked into terrain and could not get out.
	_face(st, top[0], top[1], top[2], top[3], colour, top[0])
	if _pavement_edge(at, Vector2i(at.x + 1, at.y), top_h):
		_face(st, top[1], top[2], bottom[2], bottom[1], colour, top[1] - top[0])
	if _pavement_edge(at, Vector2i(at.x - 1, at.y), top_h):
		_face(st, top[3], top[0], bottom[0], bottom[3], colour, top[0] - top[1])
	if _pavement_edge(at, Vector2i(at.x, at.y + 1), top_h):
		_face(st, top[2], top[3], bottom[3], bottom[2], colour, top[2] - top[1])
	if _pavement_edge(at, Vector2i(at.x, at.y - 1), top_h):
		_face(st, top[0], top[1], bottom[1], bottom[0], colour, top[1] - top[2])


func _emit_pavement_top(st: SurfaceTool, at: Vector2i, cell: float) -> void:
	var top_h := float(_pad_tops[at]) + PAVEMENT_LIFT
	var origin := Vector2(float(at.x) * cell, float(at.y) * cell)
	var half := cell * 0.5
	var corners := _cell_corners(at, cell)
	var edge := _road_signed(origin)
	if absf(edge) > cell * 0.72 + PAVEMENT_BLEND:
		var top: Array[Vector3] = []
		for corner in corners:
			var direction := _from_uv(corner).normalized()
			top.append(direction * (_radius + top_h))
		_face(st, top[0], top[1], top[2], top[3], _pavement_from_signed(edge), top[0])
		return
	var sub := PAINT_SUB if _dressed else PAVEMENT_SUB
	var step := cell / float(sub)
	var n := sub + 1
	var inks: Array = []
	var pts: Array = []
	inks.resize(n * n)
	pts.resize(n * n)
	for iy in n:
		for ix in n:
			var uv := Vector2(
				origin.x - half + step * float(ix),
				origin.y - half + step * float(iy))
			var slot := iy * n + ix
			inks[slot] = _pavement_ink(uv)
			pts[slot] = _from_uv(uv).normalized() * (_radius + top_h)
	for iy in sub:
		for ix in sub:
			var i00 := iy * n + ix
			var i10 := iy * n + ix + 1
			var i01 := (iy + 1) * n + ix
			var i11 := (iy + 1) * n + ix + 1
			_face_cols(
				st, pts[i00], pts[i10], pts[i11], pts[i01],
				inks[i00], inks[i10], inks[i11], inks[i01],
				pts[i00])


func _emit_pavement_skirts(
		st: SurfaceTool,
		shape: PlanetShape,
		at: Vector2i,
		cell: float
	) -> void:
	var top_h := float(_pad_tops[at]) + PAVEMENT_LIFT
	var corners := _cell_corners(at, cell)
	var top: Array[Vector3] = []
	var bottom: Array[Vector3] = []
	var inks: Array = []
	for corner in corners:
		var direction := _from_uv(corner).normalized()
		top.append(direction * (_radius + top_h))
		bottom.append(direction * (_radius + _pavement_bot(shape, corner, top_h)))
		inks.append(_rim_albedo(corner))
	if _pavement_edge(at, Vector2i(at.x + 1, at.y), top_h):
		_emit_rim_face(st, top[1], top[2], bottom[2], bottom[1], inks[1], inks[2])
	if _pavement_edge(at, Vector2i(at.x - 1, at.y), top_h):
		_emit_rim_face(st, top[3], top[0], bottom[0], bottom[3], inks[3], inks[0])
	if _pavement_edge(at, Vector2i(at.x, at.y + 1), top_h):
		_emit_rim_face(st, top[2], top[3], bottom[3], bottom[2], inks[2], inks[3])
	if _pavement_edge(at, Vector2i(at.x, at.y - 1), top_h):
		_emit_rim_face(st, top[0], top[1], bottom[1], bottom[0], inks[0], inks[1])


func _emit_rim_face(
		st: SurfaceTool,
		a: Vector3,
		b: Vector3,
		c: Vector3,
		d: Vector3,
		ca: Color,
		cb: Color
	) -> void:
	var outward: Vector3 = (b - a).cross(d - a)
	if outward.length_squared() < 0.0001:
		outward = a
	outward = outward.normalized() * 0.03
	var along := b - a
	if along.length_squared() > 0.0001:
		along = along.normalized() * 0.12
	else:
		along = Vector3.ZERO
	_face_cols(
		st,
		a + outward - along,
		b + outward + along,
		c + outward + along,
		d + outward - along,
		ca, cb, cb, ca, outward)


func _rim_albedo(uv: Vector2) -> Color:
	var n := _hash21(uv * 0.09)
	var colour := Color(0.17, 0.17, 0.19).lerp(Color(0.29, 0.29, 0.31), n)
	colour.a = 19.0 / 20.0
	return colour


func _commit_rim_mesh(st: SurfaceTool) -> MeshInstance3D:
	var mesh := st.commit()
	if mesh.get_surface_count() == 0:
		return null
	var material := ShaderMaterial.new()
	material.shader = WALL_SHADER
	material.set_shader_parameter(&"roughness_val", 0.94)
	material.set_shader_parameter(&"metallic_val", 0.02)
	material.set_shader_parameter(&"paving_wall", 1.0)
	var instance := MeshInstance3D.new()
	instance.name = "CityRim"
	instance.mesh = mesh
	instance.material_override = material
	instance.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_ON
	add_child(instance)
	return instance


func _pavement_bot(shape: PlanetShape, uv: Vector2, top_h: float) -> float:
	var ground := shape.elevation(_from_uv(uv), 0.0)
	return minf(top_h - PAVEMENT_THICK, ground - PAVEMENT_EMBED)


func _pavement_ink(uv: Vector2) -> Color:
	if _dressed:
		return _walk_paint(uv)
	return _pavement_from_signed(_road_signed(uv))


func _pavement_from_signed(edge: float) -> Color:
	var t := clampf((edge + PAVEMENT_BLEND) / maxf(PAVEMENT_BLEND * 2.0, 0.001), 0.0, 1.0)
	t = t * t * (3.0 - 2.0 * t)
	return PAVEMENT_ROAD.lerp(PAVEMENT_WALK, t)


func _pavement_edge(at: Vector2i, other: Vector2i, top_h: float) -> bool:
	if _pavement_holes.has(other):
		return true
	if _pad_tops.has(other):
		return absf(float(_pad_tops[other]) + PAVEMENT_LIFT - top_h) > 0.04
	return false


func _pave_chunk_of(key: Vector2i) -> Vector2i:
	return Vector2i(
		int(floor(float(key.x) / float(PAVE_CHUNK))),
		int(floor(float(key.y) / float(PAVE_CHUNK))))


func _build_pavement_collision(shape: PlanetShape) -> void:
	_discard_node(_pavement_body)
	_pavement_body = null
	_pave_chunk_shapes.clear()
	if shape == null or _pad_tops.is_empty():
		return
	_pavement_body = StaticBody3D.new()
	_pavement_body.name = "PavementPaintBody"
	_pavement_body.collision_layer = 1
	_pavement_body.collision_mask = 1
	add_child(_pavement_body)
	var dirty: Dictionary = {}
	for key in _pad_tops:
		if _pavement_holes.has(key):
			continue
		dirty[_pave_chunk_of(key)] = true
	for chunk_variant in dirty:
		_rebuild_pave_chunk(shape, chunk_variant as Vector2i)


func _rebuild_pave_chunk(shape: PlanetShape, chunk: Vector2i) -> void:
	if not is_instance_valid(_pavement_body) or shape == null:
		return
	var st := SurfaceTool.new()
	st.begin(Mesh.PRIMITIVE_TRIANGLES)
	var cell := _pad_cell
	var origin := Vector2i(chunk.x * PAVE_CHUNK, chunk.y * PAVE_CHUNK)
	for ox in PAVE_CHUNK:
		for oy in PAVE_CHUNK:
			var key := Vector2i(origin.x + ox, origin.y + oy)
			if not _pad_tops.has(key) or _pavement_holes.has(key):
				continue
			_emit_pavement_cell(st, shape, key, cell, PAVEMENT_WALK)
	var mesh := st.commit()
	var collider := _pave_chunk_shapes.get(chunk) as CollisionShape3D
	if mesh.get_surface_count() == 0:
		if is_instance_valid(collider):
			collider.queue_free()
			_pave_chunk_shapes.erase(chunk)
		return
	var shape3d := mesh.create_trimesh_shape()
	if shape3d == null:
		return
	if shape3d is ConcavePolygonShape3D:
		(shape3d as ConcavePolygonShape3D).backface_collision = true
	if not is_instance_valid(collider):
		collider = CollisionShape3D.new()
		collider.name = "Chunk_%d_%d" % [chunk.x, chunk.y]
		_pavement_body.add_child(collider)
		_pave_chunk_shapes[chunk] = collider
	collider.shape = shape3d


func _rebuild_broken_pavement(shape: PlanetShape) -> void:
	_discard_node(_hole_rim)
	_hole_rim = null
	if shape == null:
		return
	if _ground_tex != null:
		_remap_pavement_map()
	else:
		_rebuild_pavement_top()
	_rebuild_city_rim(shape)


func _rebuild_pavement_top() -> void:
	_discard_node(_pavement)
	_pavement = null
	_pavement_mat = null
	if _pad_tops.is_empty():
		return
	var vis := SurfaceTool.new()
	vis.begin(Mesh.PRIMITIVE_TRIANGLES)
	var cell := _pad_cell
	for key in _pad_tops:
		if _pavement_holes.has(key):
			continue
		_emit_pavement_top(vis, key as Vector2i, cell)
	_pavement = _commit_mesh(vis, "PavementPaint", false)
	if is_instance_valid(_pavement):
		_pavement.sorting_offset = 0.0


func _rebuild_city_rim(_shape: PlanetShape) -> void:
	_discard_node(_rim)
	_rim = null


func _spawn_pavement_rubble(direction: Vector3, reach: float) -> void:
	if not is_instance_valid(_rubble):
		_rubble = Node3D.new()
		_rubble.name = "PavementRubble"
		add_child(_rubble)
	var up := direction.normalized()
	var height := 0.0
	if _planet_shape != null:
		height = _planet_shape.elevation(up, 0.0)
	var origin := up * (_radius + height + 0.35)
	var east := up.cross(Vector3.UP if absf(up.y) < 0.9 else Vector3.RIGHT).normalized()
	var north := up.cross(east)
	var count := clampi(int(round(reach * 0.7)), 5, 16)
	var seed_n := int(absf(direction.x * 7919.0 + direction.z * 104729.0))
	for index in count:
		var bit := float((seed_n + index * 17) % 1000) / 1000.0
		var turn := TAU * bit
		var away := reach * (0.12 + 0.55 * float((seed_n + index * 31) % 1000) / 1000.0)
		var at := origin + (east * cos(turn) + north * sin(turn)) * away
		var chunk := MeshInstance3D.new()
		var box := BoxMesh.new()
		box.size = Vector3(
			0.35 + bit * 0.55,
			0.16 + (1.0 - bit) * 0.28,
			0.28 + absf(0.5 - bit) * 0.5)
		chunk.mesh = box
		var mat := StandardMaterial3D.new()
		mat.albedo_color = Color(0.38, 0.34, 0.30).lerp(Color(0.22, 0.20, 0.18), bit)
		mat.roughness = 0.92
		chunk.material_override = mat
		chunk.position = at
		chunk.basis = Basis(up, turn * 1.7)
		_rubble.add_child(chunk)
	var dust := GPUParticles3D.new()
	dust.amount = clampi(count * 3, 12, 40)
	dust.lifetime = 2.4
	dust.one_shot = true
	dust.explosiveness = 0.86
	dust.local_coords = true
	var east_axis := up.cross(Vector3.UP if absf(up.y) < 0.9 else Vector3.RIGHT).normalized()
	var north_axis := up.cross(east_axis)
	dust.transform = Transform3D(Basis(east_axis, up, north_axis), origin)
	var process := ParticleProcessMaterial.new()
	process.direction = Vector3(0, 1, 0)
	process.spread = 70.0
	process.initial_velocity_min = 2.2
	process.initial_velocity_max = 7.5
	process.gravity = Vector3(0, -9.4, 0)
	process.scale_min = 0.18
	process.scale_max = 0.55
	process.color = Color(0.32, 0.28, 0.24, 0.82)
	dust.process_material = process
	var quad := QuadMesh.new()
	quad.size = Vector2(0.7, 0.7)
	var puff := StandardMaterial3D.new()
	puff.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	puff.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	puff.billboard_mode = BaseMaterial3D.BILLBOARD_ENABLED
	puff.albedo_color = Color(0.34, 0.30, 0.26, 0.7)
	quad.material = puff
	dust.draw_pass_1 = quad
	_rubble.add_child(dust)
	dust.emitting = true


func _ensure_break_map() -> void:
	if _break_image != null and _break_tex != null:
		return
	if _pad_tops.is_empty() or _pad_cell <= 0.1:
		return
	var bounds := _pad_uv_bounds()
	var cell := _pad_cell
	var w := maxi(int(ceili(bounds.size.x / cell)) + 2, 8)
	var h := maxi(int(ceili(bounds.size.y / cell)) + 2, 8)
	_break_origin = bounds.position - Vector2(cell, cell)
	_break_span = Vector2(float(w) * cell, float(h) * cell)
	_break_image = Image.create(w, h, false, Image.FORMAT_RF)
	_break_image.fill(Color.BLACK)
	_break_tex = ImageTexture.create_from_image(_break_image)


func _stamp_break_cell(key: Vector2i, amount: float) -> void:
	_ensure_break_map()
	if _break_image == null:
		return
	var cell := _pad_cell
	var uv := Vector2(float(key.x) * cell, float(key.y) * cell)
	if _break_span.x < 0.1 or _break_span.y < 0.1:
		return
	var px := clampi(int(floor((uv.x - _break_origin.x) / _break_span.x * float(_break_image.get_width()))), 0, _break_image.get_width() - 1)
	var py := clampi(int(floor((uv.y - _break_origin.y) / _break_span.y * float(_break_image.get_height()))), 0, _break_image.get_height() - 1)
	var was := _break_image.get_pixel(px, py).r
	_break_image.set_pixel(px, py, Color(maxf(was, amount), 0, 0))


func _bind_break_map() -> void:
	if _break_image != null and _break_tex != null:
		_break_tex.update(_break_image)
	if not is_instance_valid(_pavement):
		return
	var material := _pavement.material_override as ShaderMaterial
	if material == null or material.shader != GROUND_SHADER:
		return
	_pavement_mat = material
	_ensure_break_map()
	material.set_shader_parameter(&"ground_map", _ground_tex)
	material.set_shader_parameter(&"map_span", _ground_span)
	material.set_shader_parameter(&"map_origin", _ground_origin)
	if _break_tex != null:
		material.set_shader_parameter(&"break_map", _break_tex)
		material.set_shader_parameter(&"break_origin", _break_origin)
		material.set_shader_parameter(&"break_span", _break_span)
		material.set_shader_parameter(&"has_breaks", 1.0 if not _pavement_holes.is_empty() else 0.0)
	_bind_lamp_map(material)


func _bind_apron_material() -> void:
	if not is_instance_valid(_apron):
		_apron_mat = null
		return
	# The homemade apron shader re-graded the biome and skipped the ground
	# photographs, so a desert ramp came out a flat darker (or lighter) card.
	# Use the planet's surface so the bank is the same sand the eye is already
	# standing on. Vertex normals stay planet-up so the slope is not painted
	# as cliff rock.
	_apron_mat = SURFACE_MATERIAL.duplicate() as ShaderMaterial
	_apron_mat.render_priority = 1
	_apron.material_override = _apron_mat
	_apron.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_ON
	_apron.sorting_offset = 0.12


func _bake_lamp_map() -> void:
	_lamp_map = null
	if _lamp_uvs.is_empty() or _ground_span.x < 4.0 or _ground_span.y < 4.0:
		return
	var span_m := maxf(_ground_span.x, _ground_span.y)
	var size := clampi(int(round(span_m / 1.15)), 256, LAMP_MAP_MAX)
	var img := Image.create(size, size, false, Image.FORMAT_RGB8)
	img.fill(Color.BLACK)
	var radius_px := maxi(int(ceili(LAMP_POOL_M / span_m * float(size))), 3)
	var warm := Color(1.0, 0.82, 0.52)
	for uv in _lamp_uvs:
		var cx := (uv.x - _ground_origin.x) / _ground_span.x * float(size)
		var cy := (uv.y - _ground_origin.y) / _ground_span.y * float(size)
		var x0 := clampi(int(floor(cx)) - radius_px, 0, size - 1)
		var x1 := clampi(int(ceil(cx)) + radius_px, 0, size - 1)
		var y0 := clampi(int(floor(cy)) - radius_px, 0, size - 1)
		var y1 := clampi(int(ceil(cy)) + radius_px, 0, size - 1)
		var reach := float(radius_px)
		for py in range(y0, y1 + 1):
			for px in range(x0, x1 + 1):
				var dx := float(px) + 0.5 - cx
				var dy := float(py) + 0.5 - cy
				var t := 1.0 - sqrt(dx * dx + dy * dy) / reach
				if t <= 0.0:
					continue
				var fall := t * t
				var was := img.get_pixel(px, py)
				img.set_pixel(px, py, Color(
					maxf(was.r, warm.r * fall),
					maxf(was.g, warm.g * fall),
					maxf(was.b, warm.b * fall)))
	img.generate_mipmaps()
	_lamp_map = ImageTexture.create_from_image(img)


func _bind_lamp_map(material: ShaderMaterial) -> void:
	if material == null:
		return
	if _lamp_map == null:
		_bake_lamp_map()
	if _lamp_map != null:
		material.set_shader_parameter(&"lamp_map", _lamp_map)
		material.set_shader_parameter(&"has_lamps", 1.0)
	else:
		material.set_shader_parameter(&"has_lamps", 0.0)


func _apply_city_night(night: float) -> void:
	if _pavement_mat != null:
		_pavement_mat.set_shader_parameter(&"night", night)
	elif is_instance_valid(_pavement):
		var material := _pavement.material_override as ShaderMaterial
		if material != null:
			material.set_shader_parameter(&"night", night)
	# Apron uses the planet surface shader; it already follows local night.


func _index_city_roads() -> void:
	_road_index.clear()
	_road_bins.clear()
	_add_road_corridor(_dirs_to_uv(_highway_dirs), HIGHWAY_HALF, true)
	_add_road_corridor(_dirs_to_uv(_highway_spur), HIGHWAY_HALF * 0.72, false)
	for path in _exit_uvs():
		_add_road_corridor(path, EXIT_HALF, false)
	for street in fabric.get("streets", []):
		var row: Dictionary = street
		_add_road_corridor(row["uv"], float(row["half"]), false)


func _add_road_corridor(path: PackedVector2Array, half: float, closed: bool) -> void:
	if path.size() < 2 or half <= 0.1:
		return
	var bin := 36.0
	var count := path.size()
	var segments := count if closed and count >= 3 else count - 1
	if closed and count >= 3 and path[0].distance_to(path[count - 1]) < 2.0:
		segments = count - 1
	for index in segments:
		var a: Vector2 = path[index]
		var b: Vector2 = path[(index + 1) % count]
		var idx := _road_index.size()
		_road_index.append({
			"a": a,
			"b": b,
			"half": half,
		})
		var run := a.distance_to(b)
		var pieces := maxi(1, int(ceili(run / 12.0)))
		for piece in pieces + 1:
			var at := a.lerp(b, float(piece) / float(pieces))
			var key := Vector2i(int(floor(at.x / bin)), int(floor(at.y / bin)))
			var list: Array = _road_bins.get(key, [])
			if not list.has(idx):
				list.append(idx)
				_road_bins[key] = list


func _uv_on_road(uv: Vector2) -> bool:
	return _road_signed(uv) < 0.0


func _road_signed(uv: Vector2) -> float:
	var best := 1.0e4
	var bin := 36.0
	var cx := int(floor(uv.x / bin))
	var cy := int(floor(uv.y / bin))
	for ox in range(-1, 2):
		for oy in range(-1, 2):
			var key := Vector2i(cx + ox, cy + oy)
			if not _road_bins.has(key):
				continue
			var list: Array = _road_bins[key]
			for idx in list:
				var row: Dictionary = _road_index[int(idx)]
				best = minf(best, _seg_distance(uv, row["a"] as Vector2, row["b"] as Vector2) - float(row["half"]))
	return best


func _seg_distance(at: Vector2, a: Vector2, b: Vector2) -> float:
	var ab := b - a
	var run := ab.length_squared()
	var t := 0.0
	if run >= 0.0001:
		t = clampf((at - a).dot(ab) / run, 0.0, 1.0)
	return at.distance_to(a.lerp(b, t))


func _path_distance(at: Vector2, path: PackedVector2Array, closed: bool) -> float:
	var nearest := 1.0e12
	if path.size() <= 1:
		return at.distance_to(path[0]) if path.size() == 1 else nearest
	var count := path.size()
	var segments := count if closed and count >= 3 else count - 1
	if closed and count >= 3 and path[0].distance_to(path[count - 1]) < 2.0:
		segments = count - 1
	for index in segments:
		var a: Vector2 = path[index]
		var b: Vector2 = path[(index + 1) % count]
		var ab := b - a
		var run := ab.length_squared()
		var t := 0.0
		if run >= 0.0001:
			t = clampf((at - a).dot(ab) / run, 0.0, 1.0)
		nearest = minf(nearest, at.distance_to(a.lerp(b, t)))
	return nearest


func _place_lamps(shape: PlanetShape) -> void:
	_discard_node(_lamps)
	_lamps = null
	_lamp_spots = PackedVector3Array()
	_lamp_uvs = PackedVector2Array()
	_lamp_map = null
	_lamp_lights.clear()
	_lamp_bind = PackedInt32Array()
	_lamp_bulb_mat = null
	var posts := _collect_lamp_posts()
	if posts.is_empty():
		return
	_lamps = Node3D.new()
	_lamps.name = "CityLamps"
	add_child(_lamps)
	var pole_mesh := CylinderMesh.new()
	pole_mesh.top_radius = 0.07
	pole_mesh.bottom_radius = 0.09
	pole_mesh.height = LAMP_HEIGHT
	pole_mesh.radial_segments = 6
	var pole_mat := StandardMaterial3D.new()
	pole_mat.albedo_color = Color(0.18, 0.18, 0.20)
	pole_mat.roughness = 0.7
	var poles := MultiMesh.new()
	poles.transform_format = MultiMesh.TRANSFORM_3D
	poles.mesh = pole_mesh
	poles.instance_count = posts.size()
	var bulb_mesh := SphereMesh.new()
	bulb_mesh.radius = 0.26
	bulb_mesh.height = 0.42
	bulb_mesh.radial_segments = 8
	bulb_mesh.rings = 4
	_lamp_bulb_mat = StandardMaterial3D.new()
	_lamp_bulb_mat.albedo_color = Color(1.0, 0.92, 0.72)
	_lamp_bulb_mat.emission_enabled = true
	_lamp_bulb_mat.emission = Color(1.0, 0.88, 0.62)
	_lamp_bulb_mat.emission_energy_multiplier = 0.0
	var bulbs := MultiMesh.new()
	bulbs.transform_format = MultiMesh.TRANSFORM_3D
	bulbs.mesh = bulb_mesh
	bulbs.instance_count = posts.size()
	for index in posts.size():
		var post: Dictionary = posts[index]
		var uv: Vector2 = post["uv"]
		var on_highway := _uv_on_highway(uv)
		var lift := HIGHWAY_OVER_PAD + 0.12 if on_highway else STREET_LIFT
		var origin := _deck_mark(shape, _from_uv(uv), lift)
		var up := origin.normalized()
		var east := up.cross(Vector3.RIGHT)
		if east.length_squared() < 0.0001:
			east = up.cross(Vector3.FORWARD)
		east = east.normalized()
		var toward := east.cross(up).normalized()
		var basis := Basis(east, up, toward)
		var pole_top := origin + up * LAMP_HEIGHT
		var bulb_at := pole_top + up * 0.24
		poles.set_instance_transform(
			index, Transform3D(basis, origin + up * (LAMP_HEIGHT * 0.5)))
		bulbs.set_instance_transform(index, Transform3D(basis, bulb_at))
		_lamp_spots.append(bulb_at)
		_lamp_uvs.append(uv)
	var pole_inst := MultiMeshInstance3D.new()
	pole_inst.name = "Poles"
	pole_inst.multimesh = poles
	pole_inst.material_override = pole_mat
	_lamps.add_child(pole_inst)
	var bulb_inst := MultiMeshInstance3D.new()
	bulb_inst.name = "Bulbs"
	bulb_inst.multimesh = bulbs
	bulb_inst.material_override = _lamp_bulb_mat
	_lamps.add_child(bulb_inst)
	_lamp_bind.resize(LAMP_LIGHTS)
	_lamp_bind.fill(-1)
	for _i in LAMP_LIGHTS:
		var light := OmniLight3D.new()
		light.light_color = Color(1.0, 0.86, 0.62)
		light.light_energy = 0.0
		light.omni_range = 28.0
		light.omni_attenuation = 0.7
		light.light_size = 0.45
		light.shadow_enabled = false
		_lamps.add_child(light)
		_lamp_lights.append(light)
	if _ground_image != null:
		_bake_lamp_map()
		if _pavement_mat != null:
			_bind_lamp_map(_pavement_mat)
		elif is_instance_valid(_pavement):
			var paved := _pavement.material_override as ShaderMaterial
			if paved != null:
				_pavement_mat = paved
				_bind_lamp_map(paved)


func _collect_lamp_posts() -> Array:
	var posts: Array = []
	var taken := PackedVector2Array()
	for street in fabric.get("streets", []):
		var row: Dictionary = street
		var spacing := LAMP_SPACING * (1.45 if int(row.get("rank", 1)) == 2 else 1.0)
		_sample_lamp_path(
			row["uv"], float(row["half"]) + 2.05, false, spacing, posts, taken)
	_sample_lamp_path(
		_dirs_to_uv(_highway_dirs), HIGHWAY_HALF + 2.2, true, LAMP_SPACING * 1.1,
		posts, taken)
	_sample_lamp_path(
		_dirs_to_uv(_highway_spur), HIGHWAY_HALF * 0.72 + 2.0, false,
		LAMP_SPACING * 1.1, posts, taken)
	for path in _exit_uvs():
		_sample_lamp_path(path, EXIT_HALF + 1.9, false, LAMP_SPACING * 1.15, posts, taken)
	return posts


func _sample_lamp_path(
		path: PackedVector2Array,
		offset: float,
		closed: bool,
		spacing: float,
		posts: Array,
		taken: PackedVector2Array
	) -> void:
	if path.size() < 2:
		return
	var count := path.size()
	var segments := count if closed and count >= 3 else count - 1
	if closed and count >= 3 and path[0].distance_to(path[count - 1]) < 2.0:
		segments = count - 1
	var stride := maxf(spacing, 8.0)
	for side_i in 2:
		var side := -1.0 if side_i == 0 else 1.0
		var traveled := 0.0
		var next_at := stride * (0.28 if side > 0.0 else 0.72)
		for index in segments:
			var a: Vector2 = path[index]
			var b: Vector2 = path[(index + 1) % count]
			var chord := b - a
			var run := chord.length()
			if run < 0.4:
				continue
			var perp := Vector2(-chord.y, chord.x)
			if perp.length_squared() < 0.0001:
				traveled += run
				continue
			perp = perp.normalized()
			while traveled + run >= next_at:
				var t := (next_at - traveled) / run
				var at := a.lerp(b, t)
				var spot: Vector2 = at + perp * (offset * side)
				var inward: Vector2 = -perp * side
				if _lamp_uv_ok(spot, taken):
					taken.append(spot)
					posts.append({"uv": spot, "inward": inward})
				next_at += stride
			traveled += run


func _lamp_uv_ok(uv: Vector2, spots: PackedVector2Array) -> bool:
	var cell := _pad_cell if _pad_cell > 0.1 else 4.0
	var key := Vector2i(roundi(uv.x / cell), roundi(uv.y / cell))
	if not _pad_tops.has(key):
		return false
	for other in spots:
		if uv.distance_squared_to(other) < LAMP_KEEP * LAMP_KEEP:
			return false
	return true


func _uv_on_highway(uv: Vector2) -> bool:
	var hw := _dirs_to_uv(_highway_dirs)
	if hw.size() >= 2 and _path_distance(uv, hw, true) < HIGHWAY_HALF + 2.0:
		return true
	var spur := _dirs_to_uv(_highway_spur)
	if spur.size() >= 2 and _path_distance(uv, spur, false) < HIGHWAY_HALF * 0.72 + 2.0:
		return true
	return false


func _night_at(world: Vector3) -> float:
	var planet := _planet_host()
	if planet == null or planet.sun == null:
		return 0.0
	var up := (world - planet.global_position).normalized()
	if up.length_squared() < 0.01:
		up = world.normalized()
	var to_sun := planet.sun.global_basis.z.normalized()
	return 1.0 - smoothstep(-0.16, 0.12, up.dot(to_sun))


func _process(_delta: float) -> void:
	if phase < PHASE_BUILT:
		return
	var origin := global_transform * (_up * _radius) if is_inside_tree() else _up * _radius
	var night := _night_at(origin)
	if _lamp_bulb_mat != null:
		_lamp_bulb_mat.emission_energy_multiplier = night * 6.4
		_retarget_lamp_lights(night)
	_apply_city_night(night)
	if phase >= PHASE_PAINTED:
		if _window_small_mat != null:
			_window_small_mat.set_shader_parameter(&"night", night)
		if _window_large_mat != null:
			_window_large_mat.set_shader_parameter(&"night", night)
		if _wall_small_mat != null:
			_wall_small_mat.set_shader_parameter(&"night", night)
		if _wall_large_mat != null:
			_wall_large_mat.set_shader_parameter(&"night", night)
		for building in _buildings:
			if building != null and is_instance_valid(building) \
					and building.has_method(&"set_night"):
				building.call(&"set_night", night)


func _retarget_lamp_lights(night: float) -> void:
	if _lamp_lights.is_empty() or _lamp_spots.is_empty():
		return
	if _lamp_bind.size() != _lamp_lights.size():
		_lamp_bind.resize(_lamp_lights.size())
		_lamp_bind.fill(-1)
	if night <= 0.02:
		for light in _lamp_lights:
			light.light_energy = 0.0
		return
	var eye := Vector3.ZERO
	var cam := get_viewport().get_camera_3d() if is_inside_tree() else null
	if cam != null:
		eye = cam.global_position
	elif is_inside_tree():
		eye = global_position
	var eye_local := global_transform.affine_inverse() * eye if is_inside_tree() else eye
	var seek2 := LAMP_SEEK * LAMP_SEEK
	var ranked: Array = []
	for index in _lamp_spots.size():
		var dist := _lamp_spots[index].distance_squared_to(eye_local)
		if dist <= seek2:
			ranked.append({"i": index, "d": dist})
	if ranked.size() < mini(_lamp_lights.size(), _lamp_spots.size()):
		ranked.clear()
		for index in _lamp_spots.size():
			ranked.append({
				"i": index,
				"d": _lamp_spots[index].distance_squared_to(eye_local),
			})
	ranked.sort_custom(_closer_lamp)
	var claimed: Dictionary = {}
	var hold2 := seek2 * LAMP_HOLD * LAMP_HOLD
	for slot in _lamp_lights.size():
		var cur := int(_lamp_bind[slot])
		if cur < 0 or cur >= _lamp_spots.size() or claimed.has(cur):
			_lamp_bind[slot] = -1
			continue
		var keep := _lamp_spots[cur].distance_squared_to(eye_local)
		if keep <= hold2:
			claimed[cur] = slot
		else:
			_lamp_bind[slot] = -1
	var next := 0
	for slot in _lamp_lights.size():
		if _lamp_bind[slot] >= 0:
			continue
		while next < ranked.size() and claimed.has(int(ranked[next]["i"])):
			next += 1
		if next >= ranked.size():
			break
		var pick := int(ranked[next]["i"])
		_lamp_bind[slot] = pick
		claimed[pick] = slot
		next += 1
	var energy := night * 5.6
	for slot in _lamp_lights.size():
		var light := _lamp_lights[slot]
		var lamp_i := int(_lamp_bind[slot])
		if lamp_i < 0:
			light.light_energy = 0.0
			continue
		light.position = _lamp_spots[lamp_i]
		light.light_energy = energy


func _closer_lamp(p: Dictionary, q: Dictionary) -> bool:
	return float(p["d"]) < float(q["d"])


func _dirs_to_uv(dirs: PackedVector3Array) -> PackedVector2Array:
	var uvs := PackedVector2Array()
	for direction in dirs:
		uvs.append(_to_uv(direction))
	return uvs


func _exit_uvs() -> Array:
	var out: Array = []
	for path in _exit_paths:
		out.append(_dirs_to_uv(path))
	return out


func _name_fabric() -> void:
	if plan == null:
		return
	var slug := _slug(plan.patch_name)
	var streets: Array = fabric.get("streets", [])
	for index in streets.size():
		var row: Dictionary = streets[index]
		var rank: int = int(row["rank"])
		var kind := CityPlace.KIND_ALLEY if rank == 2 else CityPlace.KIND_STREET
		var mid: Vector2 = row["mid"]
		var place := _make_place(
			"%s/%s/%d" % [slug, String(kind), index],
			kind,
			String(row["name"]),
			"City_%s_%s%d" % [slug, String(kind), index],
			_from_uv(mid),
			maxf(float(row["half"]) * 18.0, 70.0),
			int(row["district_id"]))
		places.append(place)
	var lots: Array = fabric.get("lots", [])
	for index in lots.size():
		var row: Dictionary = lots[index]
		var town := bool(row.get("town_center", false)) or int(row["typology"]) == 7
		var landmark := bool(row.get("landmark", false)) or int(row["typology"]) == 6
		var kind := CityPlace.KIND_BUILDING
		var key := "building"
		if town:
			kind = CityPlace.KIND_TOWN_CENTER
			key = "town_center"
		elif landmark:
			kind = CityPlace.KIND_LANDMARK
			key = "landmark"
		var place := _make_place(
			"%s/%s/%d" % [slug, key, index],
			kind,
			String(row["name"]),
			"City_%s_%s%d" % [slug, key.capitalize(), index],
			_from_uv(row["centre"]),
			maxf(float(row["width"]), 24.0),
			int(row["district_id"]))
		place.typology = int(row["typology"])
		place.variant = int(row.get("variant", VARIANT_RECT))
		place.design = String(row.get("design", ""))
		place.health = float(row.get("health", 0.0))
		place.max_health = float(row.get("max_health", place.health))
		place.stories = float(row.get("stories", 0.0))
		place.width = float(row.get("width", 0.0))
		place.depth = float(row.get("depth", 0.0))
		place.lot_index = index
		places.append(place)


func _uv_dirs(uvs: Variant) -> PackedVector3Array:
	var dirs := PackedVector3Array()
	var path: PackedVector2Array = uvs
	for index in path.size():
		dirs.append(_from_uv(path[index]).normalized())
	return dirs


func _deck_loop(
		st: SurfaceTool,
		shape: PlanetShape,
		uvs: PackedVector2Array,
		half_width: float,
		colour: Color
	) -> void:
	if uvs.size() < 2:
		return
	var path := PackedVector2Array()
	path.append_array(uvs)
	if path[0].distance_squared_to(path[path.size() - 1]) > 0.01:
		path.append(path[0])
	var points := PackedVector3Array()
	var step := 1.4
	for index in path.size() - 1:
		var a: Vector2 = path[index]
		var b: Vector2 = path[index + 1]
		var run := a.distance_to(b)
		var pieces := maxi(1, int(ceili(run / step)))
		for piece in pieces:
			var t := float(piece) / float(pieces)
			if not points.is_empty() and piece == 0:
				continue
			points.append(_deck_mark(shape, _from_uv(a.lerp(b, t)), STREET_LIFT))
		points.append(_deck_mark(shape, _from_uv(b), STREET_LIFT))
	var n := points.size()
	if n < 2:
		return
	for index in n - 1:
		var pa := points[index]
		var pb := points[index + 1]
		var chord := pb - pa
		if chord.length_squared() < 0.01:
			continue
		var up := ((pa + pb) * 0.5).normalized()
		var side := up.cross(chord)
		if side.length_squared() < 0.0001:
			continue
		side = side.normalized() * half_width
		st.set_color(colour)
		st.set_normal(up)
		st.add_vertex(pa - side)
		st.add_vertex(pa + side)
		st.add_vertex(pb + side)
		st.add_vertex(pa - side)
		st.add_vertex(pb + side)
		st.add_vertex(pb - side)


func _deck_ribbon(
		st: SurfaceTool,
		shape: PlanetShape,
		uvs: Variant,
		half_width: float,
		colour: Color,
		junctions: Array = []
	) -> void:
	var path: PackedVector2Array = uvs
	path = _trim_street_ends(path, junctions)
	if path.size() < 2:
		return
	var points := PackedVector3Array()
	for index in path.size() - 1:
		var a: Vector2 = path[index]
		var b: Vector2 = path[index + 1]
		var run := a.distance_to(b)
		var pieces := maxi(1, int(ceili(run / MAP_STEP)))
		for piece in pieces:
			var t := float(piece) / float(pieces)
			points.append(_deck_mark(shape, _from_uv(a.lerp(b, t)), STREET_LIFT))
	points.append(_deck_mark(shape, _from_uv(path[path.size() - 1]), STREET_LIFT))
	var n := points.size()
	if n < 2:
		return
	for index in n - 1:
		var pa := points[index]
		var pb := points[index + 1]
		var chord := pb - pa
		if chord.length_squared() < 0.01:
			continue
		var up := ((pa + pb) * 0.5).normalized()
		var side := up.cross(chord)
		if side.length_squared() < 0.0001:
			continue
		side = side.normalized() * half_width
		st.set_color(colour)
		st.set_normal(up)
		st.add_vertex(pa - side)
		st.add_vertex(pa + side)
		st.add_vertex(pb + side)
		st.add_vertex(pa - side)
		st.add_vertex(pb + side)
		st.add_vertex(pb - side)


func _trim_street_ends(path: PackedVector2Array, junctions: Array) -> PackedVector2Array:
	if path.size() < 2 or junctions.is_empty():
		return path
	var start := _junction_at(path[0], junctions)
	var stop := _junction_at(path[path.size() - 1], junctions)
	if start.is_empty() and stop.is_empty():
		return path
	var trimmed := path
	if not start.is_empty():
		trimmed = _walk_off_pad(trimmed, float(start["half"]) * 0.82, true)
	if trimmed.size() < 2:
		return PackedVector2Array()
	if not stop.is_empty():
		trimmed = _walk_off_pad(trimmed, float(stop["half"]) * 0.82, false)
	return trimmed


func _walk_off_pad(path: PackedVector2Array, radius: float, from_start: bool) -> PackedVector2Array:
	if path.size() < 2 or radius <= 0.2:
		return path
	var need := radius
	if from_start:
		var index := 0
		while index < path.size() - 1 and need > 0.0:
			var run := path[index].distance_to(path[index + 1])
			if run <= 0.001:
				index += 1
				continue
			if run <= need:
				need -= run
				index += 1
				continue
			var out := PackedVector2Array()
			out.append(path[index].lerp(path[index + 1], need / run))
			for rest in range(index + 1, path.size()):
				out.append(path[rest])
			return out
		return PackedVector2Array()
	var index := path.size() - 1
	while index > 0 and need > 0.0:
		var run := path[index - 1].distance_to(path[index])
		if run <= 0.001:
			index -= 1
			continue
		if run <= need:
			need -= run
			index -= 1
			continue
		var out := PackedVector2Array()
		for rest in range(0, index):
			out.append(path[rest])
		out.append(path[index - 1].lerp(path[index], 1.0 - need / run))
		return out
	return PackedVector2Array()


func _junction_at(uv: Vector2, junctions: Array) -> Dictionary:
	var best: Dictionary = {}
	var nearest := 2.2
	for junction in junctions:
		var row: Dictionary = junction
		var away := uv.distance_to(row["at"])
		if away < nearest:
			nearest = away
			best = row
	return best


func _deck_pad(
		st: SurfaceTool,
		shape: PlanetShape,
		uv: Vector2,
		half: float,
		colour: Color
	) -> void:
	var radius := maxf(half, 1.6) * 1.12
	var ring: Array = []
	for index in 8:
		var ang := TAU * float(index) / 8.0
		var at := uv + Vector2(cos(ang), sin(ang)) * radius
		ring.append(_deck_mark(shape, _from_uv(at), STREET_LIFT))
	var origin := _deck_mark(shape, _from_uv(uv), STREET_LIFT)
	var up := origin.normalized()
	for index in ring.size():
		var a: Vector3 = ring[index]
		var b: Vector3 = ring[(index + 1) % ring.size()]
		st.set_color(colour)
		st.set_normal(up)
		st.add_vertex(origin)
		st.add_vertex(a)
		st.add_vertex(b)


func _lot_on_pad_centre(lot: Dictionary) -> bool:
	if _pad_cell <= 0.1:
		return false
	var uv: Vector2 = lot.get("centre", Vector2.ZERO)
	var key := Vector2i(roundi(uv.x / _pad_cell), roundi(uv.y / _pad_cell))
	return _pad_tops.has(key)


func _lot_on_slab(lot: Dictionary) -> bool:
	if _pad_cell <= 0.1:
		return false
	var centre: Vector2 = lot.get("centre", Vector2.ZERO)
	var centre_key := Vector2i(roundi(centre.x / _pad_cell), roundi(centre.y / _pad_cell))
	if not _pad_tops.has(centre_key):
		return false
	var spots: Array = [centre]
	for piece in lot.get("footprints", []):
		var poly: PackedVector2Array = piece
		for point in poly:
			spots.append(point)
	var hits := 0
	for uv in spots:
		var key := Vector2i(roundi(uv.x / _pad_cell), roundi(uv.y / _pad_cell))
		if _pad_tops.has(key):
			hits += 1
	return hits * 2 >= spots.size()


func _cull_overlapping_lots() -> int:
	var lots: Array = fabric.get("lots", [])
	if lots.size() < 2:
		return 0
	var n := lots.size()
	var polys: Array = []
	var boxes: Array = []
	var scores := PackedFloat32Array()
	polys.resize(n)
	boxes.resize(n)
	scores.resize(n)
	var bins: Dictionary = {}
	var cell := 32.0
	for index in n:
		var row: Dictionary = lots[index]
		var pieces := _lot_mesh_polys(row)
		polys[index] = pieces
		var box := _pieces_aabb(pieces)
		boxes[index] = box
		scores[index] = _lot_keep_score(row)
		if pieces.is_empty():
			continue
		var x0 := int(floor(box.position.x / cell))
		var y0 := int(floor(box.position.y / cell))
		var x1 := int(floor(box.end.x / cell))
		var y1 := int(floor(box.end.y / cell))
		for ox in range(x0, x1 + 1):
			for oy in range(y0, y1 + 1):
				var key := Vector2i(ox, oy)
				var bucket: Array = bins.get(key, [])
				bucket.append(index)
				bins[key] = bucket
	var drop: Dictionary = {}
	for index in n:
		if drop.has(index) or (polys[index] as Array).is_empty():
			continue
		var box: Rect2 = boxes[index]
		var seen: Dictionary = {}
		var x0 := int(floor(box.position.x / cell))
		var y0 := int(floor(box.position.y / cell))
		var x1 := int(floor(box.end.x / cell))
		var y1 := int(floor(box.end.y / cell))
		for ox in range(x0, x1 + 1):
			for oy in range(y0, y1 + 1):
				var bucket: Array = bins.get(Vector2i(ox, oy), [])
				for other_i in bucket:
					var other: int = int(other_i)
					if other <= index or drop.has(other) or seen.has(other):
						continue
					seen[other] = true
					var other_box: Rect2 = boxes[other]
					if not box.intersects(other_box):
						continue
					if not _pieces_overlap(polys[index], polys[other], 8.0):
						continue
					if scores[index] >= scores[other]:
						drop[other] = true
					else:
						drop[index] = true
						break
			if drop.has(index):
				break
	if drop.is_empty():
		return 0
	var kept: Array = []
	for index in n:
		if not drop.has(index):
			kept.append(lots[index])
	fabric["lots"] = kept
	_prune_lot_places()
	print("patch_city: dropped %d overlapping buildings (%d remain)"
		% [drop.size(), kept.size()])
	return drop.size()


func _lot_keep_score(lot: Dictionary) -> float:
	var score := float(lot.get("typology", 0)) * 1000.0
	score += float(lot.get("width", 0.0)) * float(lot.get("depth", 0.0))
	score += float(lot.get("stories", 0.0)) * 40.0
	if bool(lot.get("town_center", false)) or int(lot.get("typology", 0)) == TYPE_TOWN_CENTER:
		score += 1.0e7
	if bool(lot.get("landmark", false)) or int(lot.get("typology", 0)) == TYPE_LANDMARK:
		score += 1.0e6
	if bool(lot.get("mega", false)):
		score += 5.0e5
	if bool(lot.get("apartment_pack", false)):
		score += 1.5e5
	if bool(lot.get("infill", false)):
		score -= 80.0
	if not String(lot.get("special", "")).is_empty() or bool(lot.get("walkable", false)):
		score += 2.0e5
	return score


func _lot_mesh_polys(lot: Dictionary) -> Array:
	var variant := int(lot.get("variant", VARIANT_RECT))
	if variant == VARIANT_CYLINDER:
		var ring := _poly_ccw(_lot_cylinder_uv(lot))
		return [ring] if _poly_building_ok(ring) else []
	if variant == VARIANT_ROUND_END:
		var ring := _poly_ccw(_lot_round_end_uv(lot))
		return [ring] if _poly_building_ok(ring) else []
	var out: Array = []
	for piece in lot.get("footprints", []):
		var poly := _poly_ccw(piece)
		if _poly_building_ok(poly):
			out.append(poly)
	if out.is_empty():
		var rect := _poly_ccw(_lot_rect_uv(lot))
		if _poly_building_ok(rect):
			out.append(rect)
	return out


func _pieces_aabb(pieces: Array) -> Rect2:
	var box := Rect2()
	var started := false
	for piece in pieces:
		var poly: PackedVector2Array = piece
		for point in poly:
			if not started:
				box = Rect2(point, Vector2.ZERO)
				started = true
			else:
				box = box.expand(point)
	return box


func _pieces_overlap(a_pieces: Array, b_pieces: Array, min_area: float) -> bool:
	for a in a_pieces:
		var pa: PackedVector2Array = a
		for b in b_pieces:
			var pb: PackedVector2Array = b
			var hits := Geometry2D.intersect_polygons(pa, pb)
			for hit in hits:
				if _poly_area2(hit) >= min_area:
					return true
	return false


func _prune_lot_places() -> void:
	if places.is_empty():
		return
	var names: Dictionary = {}
	var lots: Array = fabric.get("lots", [])
	for index in lots.size():
		var row: Dictionary = lots[index]
		names[String(row.get("name", ""))] = index
	var kept: Array = []
	for item in places:
		var place := item as CityPlace
		if place == null:
			continue
		if place.kind != CityPlace.KIND_BUILDING \
				and place.kind != CityPlace.KIND_LANDMARK \
				and place.kind != CityPlace.KIND_TOWN_CENTER:
			kept.append(place)
			continue
		if names.has(place.name):
			place.lot_index = int(names[place.name])
			kept.append(place)
	places.clear()
	for item in kept:
		places.append(item)


func _emit_lot_box(st: SurfaceTool, shape: PlanetShape, lot: Dictionary, solid: bool = false) -> void:
	var rise := float(lot["stories"]) * 3.15
	var colour := _lot_color(int(lot["typology"]), solid)
	if bool(lot.get("mega", false)) and not _dressed:
		colour = Color(0.20, 0.26, 0.38, 1.0 if solid else 0.70)
	if _dressed:
		colour = _lot_paint_albedo(lot)
	if bool(lot.get("ruin_wreck", false)):
		colour = Color(0.11, 0.09, 0.08, 1.0)
	var jagged := bool(lot.get("ruin_jagged", false))
	var variant: int = int(lot.get("variant", VARIANT_RECT))
	if variant == VARIANT_CYLINDER:
		var cylinder := _lot_cylinder_uv(lot)
		if _poly_building_ok(cylinder):
			_emit_lot_prism(st, shape, cylinder, rise, colour, solid, 0.0, true, jagged)
		return
	if variant == VARIANT_ROUND_END:
		var round_end := _lot_round_end_uv(lot)
		if _poly_building_ok(round_end):
			_emit_lot_prism(st, shape, round_end, rise, colour, solid, 0.0, true, jagged)
		return
	var footprints: Array = lot.get("footprints", [])
	for piece in footprints:
		var poly: PackedVector2Array = piece
		if not _poly_building_ok(poly):
			continue
		_emit_lot_variant(st, shape, lot, poly, rise, colour, solid, variant, jagged)


func _emit_lot_variant(
		st: SurfaceTool,
		shape: PlanetShape,
		lot: Dictionary,
		poly: PackedVector2Array,
		rise: float,
		colour: Color,
		solid: bool,
		variant: int,
		jagged: bool = false
	) -> void:
	if jagged:
		_emit_lot_prism(st, shape, poly, rise, colour, solid, 0.0, true, true)
		return
	match variant:
		VARIANT_RECT_CAP:
			var body := rise * _lot_body_frac(variant)
			_emit_lot_prism(st, shape, poly, body, colour, solid)
			_emit_lot_prism(
				st, shape, _lot_cap_cylinder_uv(lot, poly, _lot_cap_scale(variant)),
				rise - body, colour, solid, body, false)
		VARIANT_GABLE:
			var body := rise * _lot_body_frac(variant)
			_emit_lot_prism(st, shape, poly, body, colour, solid)
			_emit_peak_cap(st, shape, lot, poly, body, rise - body, Vector2.ZERO, colour, solid)
		VARIANT_TAPER:
			_emit_taper_tower(st, shape, lot, poly, rise, colour, solid)
		VARIANT_POINT_HALF:
			var body := rise * _lot_body_frac(variant)
			_emit_lot_prism(st, shape, poly, body, colour, solid)
			_emit_peak_cap(st, shape, lot, poly, body, rise - body, Vector2.ZERO, colour, solid)
		VARIANT_SLANT_HALF:
			var body := rise * _lot_body_frac(variant)
			_emit_lot_prism(st, shape, poly, body, colour, solid)
			var shift := _lot_across(lot) * (float(lot["depth"]) * 0.14)
			_emit_peak_cap(st, shape, lot, poly, body, rise - body, shift, colour, solid)
		VARIANT_CYL_HALF:
			var body := rise * _lot_body_frac(variant)
			_emit_lot_prism(st, shape, poly, body, colour, solid)
			_emit_lot_prism(
				st, shape, _lot_cap_cylinder_uv(lot, poly, _lot_cap_scale(variant)),
				rise - body, colour, solid, body, false)
		_:
			_emit_lot_prism(st, shape, poly, rise, colour, solid)


func lot_has_design(lot: Dictionary) -> bool:
	var design := String(lot.get("design", ""))
	return not design.is_empty() and CityBuildingCatalog.has_design(design)


func _emit_authored_lot(
		st: SurfaceTool,
		shape: PlanetShape,
		lot: Dictionary,
		solid: bool
	) -> bool:
	var design := String(lot.get("design", ""))
	var mesh := CityBuildingCatalog.hull_mesh(design)
	if mesh == null:
		return false
	var colour := Color.WHITE
	if not solid:
		colour = _lot_color(int(lot.get("typology", 0)), false)
		colour.a = minf(colour.a, FABRIC_ALPHA)
	elif bool(lot.get("mega", false)) and not _dressed:
		colour = Color(0.20, 0.26, 0.38, 1.0)
	_append_mesh_tinted(st, mesh, _lot_model_xform(shape, lot), colour, solid)
	return true


func _emit_authored_glass(st: SurfaceTool, shape: PlanetShape, lot: Dictionary) -> bool:
	var design := String(lot.get("design", ""))
	var mesh := CityBuildingCatalog.glass_mesh(design)
	if mesh == null:
		return false
	_append_authored_night_glass(st, mesh, _lot_model_xform(shape, lot), lot)
	return true


func _dress_authored_neon(
		hull: SurfaceTool,
		shape: PlanetShape,
		lot: Dictionary,
		large: bool
	) -> void:
	var neon := _lot_neon_trim(lot, large)
	if neon.a <= 0.5:
		return
	var alt: Color = lot.get("paint_neon_alt", neon)
	alt.a = neon.a
	var crown := bool(lot.get("night_crown", false))
	var blockers := _lot_wall_polys(lot)
	for ring in _lot_facade_rings(lot):
		var row: Dictionary = ring
		var poly: PackedVector2Array = row["poly"]
		var lift := float(row["lift"])
		var wall_h := float(row["height"])
		if poly.size() < 3 or wall_h < 2.2 or not _poly_building_ok(poly):
			continue
		var mid := _poly_mid(poly)
		for index in poly.size():
			var a: Vector2 = poly[index]
			var b: Vector2 = poly[(index + 1) % poly.size()]
			var chord := b - a
			var run := chord.length()
			if run < (0.85 if lift > 0.5 else 1.6):
				continue
			var along := chord / run
			var out2 := Vector2(-along.y, along.x)
			if (mid - (a + b) * 0.5).dot(out2) > 0.0:
				out2 = -out2
			if bool(row.get("bury", true)) and _edge_buried(a, b, out2, poly, blockers):
				continue
			var up_a := _from_uv(a).normalized()
			var up_b := _from_uv(b).normalized()
			var base_a := _deck_mark(shape, up_a, STREET_LIFT)
			var base_b := _deck_mark(shape, up_b, STREET_LIFT)
			var up_mid := up_a.lerp(up_b, 0.5).normalized()
			var out3 := (base_b - base_a).cross(up_mid).normalized()
			var inward := _deck_mark(shape, _from_uv(mid).normalized(), STREET_LIFT)
			var edge_pt := base_a.lerp(base_b, 0.5)
			if out3.dot(inward - edge_pt) > 0.0:
				out3 = -out3
			_emit_neon_trims(
				hull, base_a, base_b, up_a, up_b, out3, lift, wall_h, run, neon, alt,
				crown)


func _lot_model_xform(shape: PlanetShape, lot: Dictionary) -> Transform3D:
	var centre: Vector2 = lot.get("centre", Vector2.ZERO)
	var along: Vector2 = lot.get("along", Vector2.RIGHT)
	if along.length_squared() < 0.0001:
		along = Vector2.RIGHT
	along = along.normalized()
	var across: Vector2 = lot.get("across", Vector2(-along.y, along.x))
	if across.length_squared() < 0.0001:
		across = Vector2(-along.y, along.x)
	across = across.normalized()
	var up := _from_uv(centre).normalized()
	var origin := _deck_mark(shape, up, STREET_LIFT)
	var z_axis := (_from_uv(centre + across).normalized() - up)
	z_axis = (z_axis - up * z_axis.dot(up)).normalized()
	if z_axis.length_squared() < 0.0001:
		z_axis = up.cross(Vector3.RIGHT)
		if z_axis.length_squared() < 0.0001:
			z_axis = up.cross(Vector3.FORWARD)
		z_axis = z_axis.normalized()
	var x_axis := up.cross(z_axis).normalized()
	var along_t := (_from_uv(centre + along).normalized() - up)
	along_t = (along_t - up * along_t.dot(up)).normalized()
	if x_axis.dot(along_t) < 0.0:
		x_axis = -x_axis
	z_axis = x_axis.cross(up).normalized()
	var design := String(lot.get("design", ""))
	var authored_w := CityBuildingCatalog.authored_width(design, float(lot.get("width", 8.0)))
	var authored_d := CityBuildingCatalog.authored_depth(design, float(lot.get("depth", 8.0)))
	var authored_h := CityBuildingCatalog.authored_height(
		design, float(lot.get("stories", 2.0)) * 3.15)
	var sx := float(lot.get("width", authored_w)) / maxf(authored_w, 0.5)
	var sz := float(lot.get("depth", authored_d)) / maxf(authored_d, 0.5)
	var sy := (float(lot.get("stories", 2.0)) * 3.15) / maxf(authored_h, 1.0)
	sx = minf(sx, 2.2)
	sz = minf(sz, 2.2)
	sy = clampf(sy, 0.45, 2.8)
	if bool(lot.get("walkable", false)):
		var uni := minf(minf(sx, sz), 1.28)
		sx = uni
		sz = uni
		sy = uni
	else:
		var typology := int(lot.get("typology", 0))
		if bool(lot.get("mega", false)) or typology >= TYPE_TOWER:
			var plan := minf(minf(sx, sz), 1.55)
			sx = plan
			sz = plan
	return Transform3D(Basis(x_axis * sx, up * sy, z_axis * sz), origin)


func _append_authored_night_glass(
		st: SurfaceTool,
		mesh: Mesh,
		xform: Transform3D,
		lot: Dictionary
	) -> void:
	for surf in mesh.get_surface_count():
		var arrays := mesh.surface_get_arrays(surf)
		if arrays.is_empty():
			continue
		var verts: PackedVector3Array = arrays[Mesh.ARRAY_VERTEX]
		var norms: Variant = arrays[Mesh.ARRAY_NORMAL]
		var cols: Variant = arrays[Mesh.ARRAY_COLOR]
		var uvs: Variant = arrays[Mesh.ARRAY_TEX_UV]
		var indices: Variant = arrays[Mesh.ARRAY_INDEX]
		if indices is PackedInt32Array and not (indices as PackedInt32Array).is_empty():
			for index in indices:
				_emit_authored_vertex(
					st, verts, norms, cols, uvs, xform, Color.WHITE, true, int(index),
					lot, true)
		else:
			for index in verts.size():
				_emit_authored_vertex(
					st, verts, norms, cols, uvs, xform, Color.WHITE, true, index,
					lot, true)


func _night_glass_vertex_color(lot: Dictionary, world: Vector3, src: Color) -> Color:
	var lum := src.r * 0.22 + src.g * 0.67 + src.b * 0.11
	var sat := maxf(src.r, maxf(src.g, src.b)) - minf(src.r, minf(src.g, src.b))
	if lum < 0.32 and sat < 0.10:
		return src
	var large := int(lot.get("typology", 0)) >= TYPE_TOWER
	var centre: Vector2 = lot.get("centre", Vector2.ZERO)
	var up := _from_uv(centre).normalized()
	if up.length_squared() < 0.01:
		up = world.normalized()
	var story := clampi(int(floor((world.dot(up) - _radius) / 3.15)), 0, 80)
	var bay := int(floor(world.x * 0.55 + centre.x * 0.12))
	var edge := int(floor(absf(world.z * 2.1 + world.y)))
	return _lit_window_color(lot, story, bay, edge, large, src)


func _append_mesh_tinted(
		st: SurfaceTool,
		mesh: Mesh,
		xform: Transform3D,
		tint: Color,
		keep_vertex_color: bool
	) -> void:
	for surf in mesh.get_surface_count():
		var arrays := mesh.surface_get_arrays(surf)
		if arrays.is_empty():
			continue
		var verts: PackedVector3Array = arrays[Mesh.ARRAY_VERTEX]
		var norms: Variant = arrays[Mesh.ARRAY_NORMAL]
		var cols: Variant = arrays[Mesh.ARRAY_COLOR]
		var uvs: Variant = arrays[Mesh.ARRAY_TEX_UV]
		var indices: Variant = arrays[Mesh.ARRAY_INDEX]
		if indices is PackedInt32Array and not (indices as PackedInt32Array).is_empty():
			for index in indices:
				_emit_authored_vertex(
					st, verts, norms, cols, uvs, xform, tint, keep_vertex_color, int(index))
		else:
			for index in verts.size():
				_emit_authored_vertex(
					st, verts, norms, cols, uvs, xform, tint, keep_vertex_color, index)


func _emit_authored_vertex(
		st: SurfaceTool,
		verts: PackedVector3Array,
		norms: Variant,
		cols: Variant,
		uvs: Variant,
		xform: Transform3D,
		tint: Color,
		keep_vertex_color: bool,
		index: int,
		lot: Dictionary = {},
		night_glass: bool = false
	) -> void:
	if index < 0 or index >= verts.size():
		return
	var normal := Vector3.UP
	if norms is PackedVector3Array and index < (norms as PackedVector3Array).size():
		normal = (xform.basis * (norms as PackedVector3Array)[index]).normalized()
		if normal.length_squared() < 0.01:
			normal = Vector3.UP
	var colour := tint
	var src := tint
	if keep_vertex_color and cols is PackedColorArray and index < (cols as PackedColorArray).size():
		src = (cols as PackedColorArray)[index]
		colour = Color(src.r * tint.r, src.g * tint.g, src.b * tint.b, src.a)
	var world := xform * verts[index]
	if night_glass and not lot.is_empty():
		colour = _night_glass_vertex_color(lot, world, src)
	var uv := Vector2.ZERO
	if uvs is PackedVector2Array and index < (uvs as PackedVector2Array).size():
		uv = (uvs as PackedVector2Array)[index]
	st.set_uv(uv)
	st.set_normal(normal)
	st.set_color(colour)
	st.add_vertex(world)


func _lot_across(lot: Dictionary) -> Vector2:
	var along: Vector2 = lot.get("along", Vector2.RIGHT)
	if along.length_squared() < 0.0001:
		along = Vector2.RIGHT
	along = along.normalized()
	var across: Vector2 = lot.get("across", Vector2(-along.y, along.x))
	if across.length_squared() < 0.0001:
		across = Vector2(-along.y, along.x)
	return across.normalized()


func _lot_round_end_uv(lot: Dictionary) -> PackedVector2Array:
	var centre: Vector2 = lot["centre"]
	var along: Vector2 = lot.get("along", Vector2.RIGHT)
	if along.length_squared() < 0.0001:
		along = Vector2.RIGHT
	along = along.normalized()
	var across := _lot_across(lot)
	var half_w := float(lot["width"]) * 0.5
	var half_d := float(lot["depth"]) * 0.5
	var toward := along * (1.0 if int(lot.get("round_dir", 1)) >= 0 else -1.0)
	var radius := minf(half_w, half_d)
	var cap_at := centre + toward * (half_w - radius)
	var square_at := centre - toward * half_w
	var ring := PackedVector2Array()
	ring.append(square_at - across * half_d)
	ring.append(square_at + across * half_d)
	var steps := 8
	for index in steps:
		var t := float(index) / float(maxi(steps - 1, 1))
		var ang := PI * 0.5 - t * PI
		var point := cap_at + toward * cos(ang) * radius + across * sin(ang) * radius
		if ring[ring.size() - 1].distance_squared_to(point) < 0.04:
			continue
		ring.append(point)
	if ring.size() >= 3 and ring[0].distance_squared_to(ring[ring.size() - 1]) < 0.04:
		ring.remove_at(ring.size() - 1)
	return ring


func _lot_cap_cylinder_uv(
		lot: Dictionary, poly: PackedVector2Array, scale: float = 0.36
	) -> PackedVector2Array:
	var centre := _poly_mid(poly)
	if centre == Vector2.ZERO:
		centre = lot["centre"]
	var radius := _poly_inradius(poly) * scale * 2.0
	if radius < 1.2:
		radius = minf(float(lot["width"]), float(lot["depth"])) * scale
	if radius < 1.2:
		return PackedVector2Array()
	var ring := PackedVector2Array()
	var sides := clampi(int(round(TAU * radius / 3.2)), 10, 20)
	for index in sides:
		var ang := TAU * float(index) / float(sides)
		ring.append(centre + Vector2(cos(ang), sin(ang)) * radius)
	return ring


func _poly_inradius(poly: PackedVector2Array) -> float:
	if poly.size() < 3:
		return 0.0
	var mid := _poly_mid(poly)
	var best := 1.0e9
	for index in poly.size():
		var a: Vector2 = poly[index]
		var b: Vector2 = poly[(index + 1) % poly.size()]
		var ab := b - a
		var run := ab.length_squared()
		var away := mid.distance_to(a)
		if run >= 0.0001:
			var t := clampf((mid - a).dot(ab) / run, 0.0, 1.0)
			away = mid.distance_to(a.lerp(b, t))
		best = minf(best, away)
	if best > 1.0e8:
		return 0.0
	return best


func _poly_area2(poly: PackedVector2Array) -> float:
	var area := 0.0
	var n := poly.size()
	if n < 3:
		return 0.0
	for index in n:
		var a: Vector2 = poly[index]
		var b: Vector2 = poly[(index + 1) % n]
		area += a.x * b.y - b.x * a.y
	return absf(area) * 0.5


func _poly_building_ok(poly: PackedVector2Array) -> bool:
	if poly.size() < 3:
		return false
	if _poly_area2(poly) < 8.0:
		return false
	var radius := _poly_inradius(poly)
	if radius < 1.55:
		return false
	var box := Rect2(poly[0], Vector2.ZERO)
	for index in range(1, poly.size()):
		box = box.expand(poly[index])
	if minf(box.size.x, box.size.y) < 3.1:
		return false
	var mid := _poly_mid(poly)
	var farthest := 0.0
	for point in poly:
		farthest = maxf(farthest, point.distance_to(mid))
	return farthest <= radius * 12.0


func _poly_mid(poly: PackedVector2Array) -> Vector2:
	var mid := Vector2.ZERO
	if poly.is_empty():
		return mid
	for point in poly:
		mid += point
	return mid / float(poly.size())


func _scale_poly(poly: PackedVector2Array, scale: float) -> PackedVector2Array:
	var mid := _poly_mid(poly)
	var out := PackedVector2Array()
	for point in poly:
		out.append(mid + (point - mid) * scale)
	return out


func _emit_taper_tower(
		st: SurfaceTool,
		shape: PlanetShape,
		lot: Dictionary,
		poly: PackedVector2Array,
		rise: float,
		colour: Color,
		solid: bool
	) -> void:
	var floors := _taper_levels(lot)
	var story := rise / float(floors)
	for index in floors:
		var t := float(index) / float(maxi(floors - 1, 1))
		var scale := 1.0 - 0.18 * t
		_emit_lot_prism(
			st, shape, _scale_poly(poly, scale), story, colour, solid, story * float(index), index == 0)


func _peak_cap_height(lot: Dictionary, peak_h: float) -> float:
	if peak_h < 0.2:
		return peak_h
	var span := minf(float(lot.get("width", 8.0)), float(lot.get("depth", 8.0)))
	return minf(peak_h, maxf(span * 0.48, 1.8))


func _emit_peak_cap(
		st: SurfaceTool,
		shape: PlanetShape,
		lot: Dictionary,
		poly: PackedVector2Array,
		lift: float,
		peak_h: float,
		shift: Vector2,
		colour: Color,
		solid: bool
	) -> void:
	if poly.size() < 3:
		return
	var height := _peak_cap_height(lot, peak_h)
	if height < 0.2:
		return
	var ring := PackedVector2Array(poly)
	if Geometry2D.is_polygon_clockwise(ring):
		ring.reverse()
	var top_uv := _scale_poly(ring, 0.50)
	if shift.length_squared() > 0.01:
		var moved := PackedVector2Array()
		for point in top_uv:
			moved.append(point + shift)
		top_uv = moved
	var base: Array[Vector3] = []
	var top: Array[Vector3] = []
	base.resize(ring.size())
	top.resize(ring.size())
	for index in ring.size():
		var up := _from_uv(ring[index]).normalized()
		base[index] = _deck_mark(shape, up, STREET_LIFT) + up * lift
		var top_up := _from_uv(top_uv[index]).normalized()
		top[index] = _deck_mark(shape, top_up, STREET_LIFT) + top_up * (lift + height)
	var indices := Geometry2D.triangulate_polygon(top_uv)
	if indices.size() < 3:
		var flipped := PackedVector2Array(top_uv)
		flipped.reverse()
		indices = Geometry2D.triangulate_polygon(flipped)
	for step in range(0, indices.size(), 3):
		var a: int = indices[step]
		var b: int = indices[step + 1]
		var c: int = indices[step + 2]
		if a < 0 or b < 0 or c < 0 or a >= top.size() or b >= top.size() or c >= top.size():
			continue
		var mid: Vector3 = (top[a] + top[b] + top[c]) / 3.0
		if solid:
			_paint_tri(st, top[a], top[b], top[c], colour, mid)
		else:
			_ghost_tri(st, top[a], top[b], top[c], colour, mid)
	for index in ring.size():
		var next := (index + 1) % ring.size()
		if ring[index].distance_squared_to(ring[next]) < 0.16:
			continue
		var outward: Vector3 = (base[next] - base[index]).cross(top[index] - base[index])
		if solid:
			_face(st, base[index], base[next], top[next], top[index], colour, outward)
		else:
			_ghost_quad(st, base[index], base[next], top[next], top[index], colour, outward)


func _lot_rect_uv(lot: Dictionary) -> PackedVector2Array:
	var centre: Vector2 = lot["centre"]
	var along: Vector2 = lot["along"]
	var across: Vector2 = lot["across"]
	if along.length_squared() < 0.0001:
		along = Vector2.RIGHT
	along = along.normalized()
	if across.length_squared() < 0.0001:
		across = Vector2(-along.y, along.x)
	across = across.normalized()
	var x := along * (float(lot["width"]) * 0.5)
	var y := across * (float(lot["depth"]) * 0.5)
	var poly := PackedVector2Array()
	poly.append(centre - x - y)
	poly.append(centre + x - y)
	poly.append(centre + x + y)
	poly.append(centre - x + y)
	return poly


func _lot_cylinder_uv(lot: Dictionary) -> PackedVector2Array:
	var centre: Vector2 = lot["centre"]
	var radius := minf(float(lot["width"]), float(lot["depth"])) * 0.48
	var footprints: Array = lot.get("footprints", [])
	if not footprints.is_empty():
		var biggest: PackedVector2Array = footprints[0]
		var best := -1.0
		for piece in footprints:
			var poly: PackedVector2Array = piece
			var area := 0.0
			for index in poly.size():
				var a: Vector2 = poly[index]
				var b: Vector2 = poly[(index + 1) % poly.size()]
				area += a.x * b.y - b.x * a.y
			area = absf(area) * 0.5
			if area > best:
				best = area
				biggest = poly
		if biggest.size() >= 3:
			centre = Vector2.ZERO
			for point in biggest:
				centre += point
			centre /= float(biggest.size())
			radius = _poly_inradius(biggest) * 0.92
			if radius < 1.2:
				radius = minf(float(lot["width"]), float(lot["depth"])) * 0.38
	var ring := PackedVector2Array()
	var sides := 12
	for index in sides:
		var ang := TAU * float(index) / float(sides)
		ring.append(centre + Vector2(cos(ang), sin(ang)) * radius)
	return ring


func _emit_lot_prism(
		st: SurfaceTool,
		shape: PlanetShape,
		poly: PackedVector2Array,
		rise: float,
		colour: Color,
		solid: bool = false,
		lift: float = 0.0,
		emit_bottom: bool = true,
		jagged: bool = false
	) -> void:
	if poly.size() < 3:
		return
	if not _poly_building_ok(poly):
		return
	var ring := PackedVector2Array(poly)
	if Geometry2D.is_polygon_clockwise(ring):
		ring.reverse()
	var indices := Geometry2D.triangulate_polygon(ring)
	if indices.size() < 3:
		ring.reverse()
		indices = Geometry2D.triangulate_polygon(ring)
	if indices.size() < 3:
		return
	var base: Array[Vector3] = []
	var top: Array[Vector3] = []
	base.resize(ring.size())
	top.resize(ring.size())
	for index in ring.size():
		var up := _from_uv(ring[index]).normalized()
		var origin := _deck_mark(shape, up, STREET_LIFT) + up * lift
		base[index] = origin
		var drop := 0.0
		if jagged:
			var n := sin(ring[index].x * 0.37) * 12.9898 + cos(ring[index].y * 0.41) * 78.233
			var h := fposmod(sin(n) * 43758.5453, 1.0)
			drop = rise * (0.05 + 0.32 * h)
		top[index] = origin + up * maxf(rise - drop, rise * 0.42)
	for step in range(0, indices.size(), 3):
		var a: int = indices[step]
		var b: int = indices[step + 1]
		var c: int = indices[step + 2]
		var mid: Vector3 = (top[a] + top[b] + top[c]) / 3.0
		if solid:
			_paint_tri(st, top[a], top[b], top[c], colour, mid)
			if emit_bottom:
				_paint_tri(st, base[a], base[c], base[b], colour, -mid)
		else:
			_ghost_tri(st, top[a], top[b], top[c], colour, mid)
			if emit_bottom:
				_ghost_tri(st, base[a], base[c], base[b], colour, -mid)
	for index in ring.size():
		var next := (index + 1) % ring.size()
		if ring[index].distance_squared_to(ring[next]) < 0.16:
			continue
		var outward: Vector3 = (base[next] - base[index]).cross(top[index] - base[index])
		if solid:
			_face(st, base[index], base[next], top[next], top[index], colour, outward)
		else:
			_ghost_quad(st, base[index], base[next], top[next], top[index], colour, outward)


func _lot_color(typology: int, solid: bool = false) -> Color:
	var colour := Color(0.72, 0.62, 0.48, FABRIC_ALPHA)
	match typology:
		1:
			colour = Color(0.62, 0.52, 0.42, FABRIC_ALPHA)
		2:
			colour = Color(0.50, 0.48, 0.46, FABRIC_ALPHA)
		3:
			colour = Color(0.56, 0.40, 0.36, FABRIC_ALPHA)
		4:
			colour = Color(0.40, 0.44, 0.52, FABRIC_ALPHA)
		5:
			colour = Color(0.34, 0.38, 0.48, FABRIC_ALPHA)
		6:
			colour = Color(0.94, 0.72, 0.22, 0.78)
		7:
			colour = Color(0.38, 0.86, 0.94, 0.84)
	if solid:
		colour.a = 1.0
	return colour


func _ghost_quad(
		st: SurfaceTool,
		a: Vector3,
		b: Vector3,
		c: Vector3,
		d: Vector3,
		colour: Color,
		outward: Vector3
	) -> void:
	var aim := outward
	if aim.length_squared() < 0.0001:
		aim = (a + b + c + d)
	if (b - a).cross(c - a).dot(aim) < 0.0:
		_ghost_tri(st, a, c, b, colour, aim)
		_ghost_tri(st, a, d, c, colour, aim)
	else:
		_ghost_tri(st, a, b, c, colour, aim)
		_ghost_tri(st, a, c, d, colour, aim)


func _ghost_tri(
		st: SurfaceTool,
		a: Vector3,
		b: Vector3,
		c: Vector3,
		colour: Color,
		outward: Vector3
	) -> void:
	var normal := outward.normalized()
	if normal.length_squared() < 0.5:
		normal = (b - a).cross(c - a).normalized()
	var mid := (a + b + c) * (1.0 / 3.0)
	var up := mid.normalized()
	if up.length_squared() < 0.25:
		up = Vector3.UP
	var roof := absf(normal.dot(up))
	st.set_color(colour)
	st.set_normal(normal)
	st.set_uv(_mass_paint_uv(a, normal, up, roof))
	st.add_vertex(a)
	st.set_color(colour)
	st.set_normal(normal)
	st.set_uv(_mass_paint_uv(b, normal, up, roof))
	st.add_vertex(b)
	st.set_color(colour)
	st.set_normal(normal)
	st.set_uv(_mass_paint_uv(c, normal, up, roof))
	st.add_vertex(c)


func _commit_ghost(st: SurfaceTool, mesh_name: String) -> MeshInstance3D:
	var mesh := st.commit()
	if mesh.get_surface_count() == 0:
		return null
	var material := StandardMaterial3D.new()
	material.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	material.vertex_color_use_as_albedo = true
	material.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	material.cull_mode = BaseMaterial3D.CULL_DISABLED
	material.disable_receive_shadows = true
	material.no_depth_test = false
	var instance := MeshInstance3D.new()
	instance.name = mesh_name
	instance.mesh = mesh
	instance.material_override = material
	instance.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	instance.sorting_offset = 3.0
	add_child(instance)
	return instance


func _deck_mark(shape: PlanetShape, direction: Vector3, lift: float) -> Vector3:
	var up := direction.normalized()
	var pad := _pad_top_at(up)
	if is_nan(pad):
		pad = _nearby_pad_h(up, 3.6)
	if not is_nan(pad):
		return up * (_radius + pad + lift)
	var height := shape.elevation(up, MAP_STEP)
	return up * (_radius + height + lift)


func _nearby_pad_h(direction: Vector3, cells: float) -> float:
	if _pad_tops.is_empty():
		return NAN
	var cell := _pad_cell if _pad_cell > 0.1 else 4.0
	var uv := _to_uv(direction)
	var best := NAN
	var nearest := cell * cell * cells * cells
	for sample in _pad_tops:
		var at: Vector2i = sample
		var away := Vector2(float(at.x) * cell, float(at.y) * cell).distance_squared_to(uv)
		if away < nearest:
			nearest = away
			best = float(_pad_tops[at])
	return best


func _cache_minimap(district_rings: Array) -> void:
	var streets_out: Array = []
	for street in fabric.get("streets", []):
		var row: Dictionary = street
		streets_out.append({
			"uv": row["uv"],
			"half": float(row["half"]),
			"rank": int(row["rank"]),
		})
	var hall_id := -1
	for place in places:
		if place.kind == CityPlace.KIND_TOWN_CENTER:
			hall_id = place.district_id
			break
	minimap = {
		"districts": district_rings,
		"highway": _dirs_to_uv(_highway_dirs),
		"spur": _dirs_to_uv(_highway_spur),
		"exits": _exit_uvs(),
		"streets": streets_out,
		"town_district": hall_id,
	}
	_city_extent = _measure_extent()


func _measure_extent() -> float:
	var farthest := 120.0
	if plan != null:
		for district in plan.districts:
			var centre := _to_uv(district.centre)
			farthest = maxf(farthest, centre.length() + maxf(district.span, 80.0) * 0.5)
	for item in minimap.get("districts", []):
		var poly := PackedVector2Array()
		if item is Dictionary:
			poly = PackedVector2Array((item as Dictionary).get("uv", PackedVector2Array()))
		else:
			poly = PackedVector2Array(item)
		for point in poly:
			farthest = maxf(farthest, Vector2(point).length())
	for point in minimap.get("highway", PackedVector2Array()):
		farthest = maxf(farthest, Vector2(point).length())
	return farthest


func _ring_dirs(ring: PackedVector2Array) -> PackedVector3Array:
	var dirs := PackedVector3Array()
	for index in ring.size():
		dirs.append(_from_uv(ring[index]).normalized())
	return dirs


func _map_ribbon(
		st: SurfaceTool,
		shape: PlanetShape,
		dirs: PackedVector3Array,
		half_width: float,
		colour: Color,
		closed: bool
	) -> void:
	if dirs.size() < 2:
		return
	var unique := PackedVector3Array()
	var limit := dirs.size() - 1 if closed and dirs.size() > 2 else dirs.size()
	if closed and dirs.size() >= 3 and dirs[0].dot(dirs[dirs.size() - 1]) > 0.999:
		limit = dirs.size() - 1
	for index in limit:
		unique.append(dirs[index])
	if unique.size() < 2:
		return
	var points := PackedVector3Array()
	var count := unique.size()
	var segments := count if closed else count - 1
	for index in segments:
		var a := unique[index]
		var b := unique[(index + 1) % count]
		var arc := a.angle_to(b) * _radius
		var pieces := maxi(1, int(ceili(arc / MAP_STEP)))
		for piece in pieces:
			var t := float(piece) / float(pieces)
			points.append(_map_mark(shape, a.slerp(b, t)))
	if not closed:
		points.append(_map_mark(shape, unique[count - 1]))
	var n := points.size()
	if n < 2:
		return
	for index in n - 1:
		var pa := points[index]
		var pb := points[index + 1]
		var chord := pb - pa
		if chord.length_squared() < 0.01:
			continue
		var up := ((pa + pb) * 0.5).normalized()
		var side := up.cross(chord)
		if side.length_squared() < 0.0001:
			continue
		side = side.normalized() * half_width
		st.set_color(colour)
		st.set_normal(up)
		st.add_vertex(pa - side)
		st.add_vertex(pa + side)
		st.add_vertex(pb + side)
		st.add_vertex(pa - side)
		st.add_vertex(pb + side)
		st.add_vertex(pb - side)
	if closed and n >= 3:
		var pa := points[n - 1]
		var pb := points[0]
		var chord := pb - pa
		if chord.length_squared() >= 0.01:
			var up := ((pa + pb) * 0.5).normalized()
			var side := up.cross(chord)
			if side.length_squared() >= 0.0001:
				side = side.normalized() * half_width
				st.set_color(colour)
				st.set_normal(up)
				st.add_vertex(pa - side)
				st.add_vertex(pa + side)
				st.add_vertex(pb + side)
				st.add_vertex(pa - side)
				st.add_vertex(pb + side)
				st.add_vertex(pb - side)


func _map_mark(shape: PlanetShape, direction: Vector3) -> Vector3:
	var up := direction.normalized()
	var height := shape.elevation(up, MAP_STEP)
	var pad := _pad_top_at(up)
	if not is_nan(pad):
		height = maxf(height, pad)
	return up * (_radius + height + MAP_LIFT)


func _raise_place_landmarks() -> void:
	var host := _planet_host()
	if host == null:
		return
	var folder := _map.get_node_or_null("Gazetteer") as Node3D
	if folder == null:
		folder = Node3D.new()
		folder.name = "Gazetteer"
		_map.add_child(folder)
	for place in places:
		if place.kind == CityPlace.KIND_BUILDING and place.typology < 4:
			continue
		var mark := Landmark.new()
		mark.name = place.node_name
		mark.title = place.name
		mark.direction = place.direction
		mark.waypoint = false
		mark.planet = host
		mark.clearance = MAP_LIFT + 1.0
		folder.add_child(mark)


func _raise_street_names(shape: PlanetShape) -> void:
	_map_names = Node3D.new()
	_map_names.name = "StreetNames"
	_map.add_child(_map_names)
	for street in fabric.get("streets", []):
		var row: Dictionary = street
		if int(row.get("rank", 1)) == 2:
			continue
		var path: PackedVector2Array = row.get("uv", PackedVector2Array())
		if path.size() < 2:
			continue
		var run := 0.0
		for index in path.size() - 1:
			run += path[index].distance_to(path[index + 1])
		if run < 36.0:
			continue
		var mid: Vector2 = _poly_mid(path)
		if row.has("mid"):
			mid = row["mid"]
		var along := _street_along(path, mid)
		var up := _from_uv(mid).normalized()
		var at := _map_mark(shape, up) + up * 0.35
		var across := up.cross(along)
		if across.length_squared() < 0.0001:
			continue
		across = across.normalized()
		along = across.cross(up).normalized()
		var label := Label3D.new()
		label.text = String(row.get("name", ""))
		label.font = MAP_FONT
		label.font_size = 28
		label.pixel_size = 0.055
		label.modulate = Color(0.92, 0.93, 0.95, 0.92)
		label.outline_size = 10
		label.outline_modulate = PALETTE.ink
		label.billboard = BaseMaterial3D.BILLBOARD_DISABLED
		label.no_depth_test = false
		label.shaded = false
		label.double_sided = true
		label.position = at
		label.basis = Basis(along, across, -up)
		_map_names.add_child(label)


func _street_along(path: PackedVector2Array, mid: Vector2) -> Vector3:
	var best := 0
	var nearest := 1.0e12
	for index in path.size() - 1:
		var a: Vector2 = path[index]
		var b: Vector2 = path[index + 1]
		var ab := b - a
		var run := ab.length_squared()
		var t := 0.0
		if run >= 0.0001:
			t = clampf((mid - a).dot(ab) / run, 0.0, 1.0)
		var dist := mid.distance_squared_to(a.lerp(b, t))
		if dist < nearest:
			nearest = dist
			best = index
	var from: Vector2 = path[best]
	var to: Vector2 = path[mini(best + 1, path.size() - 1)]
	if from.distance_squared_to(to) < 0.0001:
		return _east
	return (_from_uv(to) - _from_uv(from)).normalized()


func _raise_special_marks(shape: PlanetShape) -> void:
	_map_marks = Node3D.new()
	_map_marks.name = "SpecialMarks"
	_map.add_child(_map_marks)
	var mesh := _diamond_mesh()
	for place in places:
		var special := false
		if place.lot_index >= 0:
			var lots: Array = fabric.get("lots", [])
			if place.lot_index < lots.size():
				special = bool((lots[place.lot_index] as Dictionary).get("walkable", false))
		if place.kind != CityPlace.KIND_LANDMARK \
				and place.kind != CityPlace.KIND_TOWN_CENTER \
				and not special:
			continue
		var up := place.direction.normalized()
		var rise := MAP_LIFT + maxf(place.stories * 3.15, 8.0) + 3.0
		var at := _map_mark(shape, up) + up * rise
		var mark := MeshInstance3D.new()
		mark.name = place.node_name
		mark.mesh = mesh
		mark.position = at
		mark.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
		var material := StandardMaterial3D.new()
		material.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
		material.cull_mode = BaseMaterial3D.CULL_DISABLED
		material.disable_receive_shadows = true
		if place.kind == CityPlace.KIND_TOWN_CENTER:
			material.albedo_color = Color(0.94, 0.72, 0.16, 1.0)
		elif special:
			material.albedo_color = Color(0.72, 0.88, 0.98, 1.0)
		else:
			material.albedo_color = Color(0.96, 0.84, 0.22, 1.0)
		mark.material_override = material
		_map_marks.add_child(mark)


func _diamond_mesh() -> ArrayMesh:
	var st := SurfaceTool.new()
	st.begin(Mesh.PRIMITIVE_TRIANGLES)
	var n := Vector3(0.0, 1.35, 0.0)
	var s := Vector3(0.0, -1.35, 0.0)
	var e := Vector3(0.85, 0.0, 0.0)
	var w := Vector3(-0.85, 0.0, 0.0)
	var f := Vector3(0.0, 0.0, 0.55)
	var b := Vector3(0.0, 0.0, -0.55)
	_diamond_tri(st, n, f, e)
	_diamond_tri(st, n, e, b)
	_diamond_tri(st, n, b, w)
	_diamond_tri(st, n, w, f)
	_diamond_tri(st, s, e, f)
	_diamond_tri(st, s, b, e)
	_diamond_tri(st, s, w, b)
	_diamond_tri(st, s, f, w)
	st.generate_normals()
	return st.commit()


func _diamond_tri(st: SurfaceTool, a: Vector3, b: Vector3, c: Vector3) -> void:
	st.add_vertex(a)
	st.add_vertex(b)
	st.add_vertex(c)


func _eye_altitude(eye: Vector3) -> float:
	var planet := _planet_host()
	if planet == null or planet.shape == null:
		return STREET_LABEL_ALT
	var local := planet.to_local(eye) if planet.is_inside_tree() else eye
	if local.length_squared() < 1.0:
		return 0.0
	var up := local.normalized()
	return local.length() - planet.shape.radius - planet.shape.elevation(
		up, planet.spacing_underfoot())


func _planet_host() -> Planet:
	var node := get_parent()
	while node != null:
		if node is Planet:
			return node as Planet
		node = node.get_parent()
	return null


func _road_label_dir() -> Vector3:
	if plan == null or plan.loop.is_empty():
		return _up
	var best := plan.loop[0]
	var nearest := -1.0
	for direction in plan.loop:
		var toward := direction.normalized().dot(_up)
		if toward > nearest:
			nearest = toward
			best = direction
	return best.normalized()


func _loop_span() -> float:
	if plan == null:
		return 0.0
	var farthest := 0.0
	for direction in plan.loop:
		farthest = maxf(farthest, _up.angle_to(direction))
	return farthest * _radius * 2.0


func _compass_of(direction: Vector3) -> String:
	var at := direction.normalized()
	var q := at - _up * at.dot(_up)
	if q.length_squared() < 0.000001:
		return COMPASS[0]
	var angle := atan2(q.dot(_east), q.dot(_north))
	var octant := int(roundi(fposmod(angle + TAU, TAU) / (TAU * 0.125))) % COMPASS.size()
	return COMPASS[octant]


func _slug(text: String) -> String:
	return text.replace(" ", "").replace("'", "").replace("-", "")


func _pad_top_at(direction: Vector3) -> float:
	if plan == null or _pad_tops.is_empty():
		return NAN
	var cell := _pad_cell if _pad_cell > 0.1 else plan.cell_size
	var uv := _to_uv(direction)
	var key := Vector2i(roundi(uv.x / cell), roundi(uv.y / cell))
	if _pad_tops.has(key):
		return float(_pad_tops[key])
	var best := NAN
	var nearest := cell * cell * 0.64
	for sample in _pad_tops:
		var at: Vector2i = sample
		var away := Vector2(float(at.x) * cell, float(at.y) * cell).distance_squared_to(uv)
		if away < nearest:
			nearest = away
			best = float(_pad_tops[at])
	return best


func _road_over_pad(direction: Vector3) -> float:
	var top := _pad_top_at(direction)
	if is_nan(top):
		return -1.0e9
	return top + HIGHWAY_OVER_PAD


func _floor_height(shape: PlanetShape, direction: Vector3) -> float:
	var floor_h := shape.elevation(direction, HIGHWAY_STEP) + GROUND_LIFT
	var pad := _pad_top_at(direction)
	if not is_nan(pad):
		floor_h = maxf(floor_h, pad)
	return floor_h


func _face(
		st: SurfaceTool,
		a: Vector3,
		b: Vector3,
		c: Vector3,
		d: Vector3,
		colour: Color,
		outward: Vector3
	) -> void:
	var aim := outward
	if aim.length_squared() < 0.0001:
		aim = a + b + c + d
	if (b - a).cross(c - a).dot(aim) < 0.0:
		_paint_tri(st, a, d, c, colour, aim)
		_paint_tri(st, a, c, b, colour, aim)
	else:
		_paint_tri(st, a, b, c, colour, aim)
		_paint_tri(st, a, c, d, colour, aim)


func _face_uv(
		st: SurfaceTool,
		a: Vector3,
		b: Vector3,
		c: Vector3,
		d: Vector3,
		ua: Vector2,
		ub: Vector2,
		uc: Vector2,
		ud: Vector2,
		outward: Vector3
	) -> void:
	var aim := outward
	if aim.length_squared() < 0.0001:
		aim = a + b + c + d
	if (b - a).cross(c - a).dot(aim) < 0.0:
		_paint_tri_uv(st, a, d, c, ua, ud, uc, aim)
		_paint_tri_uv(st, a, c, b, ua, uc, ub, aim)
	else:
		_paint_tri_uv(st, a, b, c, ua, ub, uc, aim)
		_paint_tri_uv(st, a, c, d, ua, uc, ud, aim)


func _paint_tri_uv(
		st: SurfaceTool,
		a: Vector3,
		b: Vector3,
		c: Vector3,
		ua: Vector2,
		ub: Vector2,
		uc: Vector2,
		outward: Vector3
	) -> void:
	var normal := outward.normalized()
	if normal.length_squared() < 0.5:
		normal = ((b - a).cross(c - a)).normalized()
	if normal.length_squared() < 0.5:
		normal = a.normalized()
	st.set_normal(normal)
	st.set_uv(ua)
	st.add_vertex(a)
	st.set_normal(normal)
	st.set_uv(ub)
	st.add_vertex(b)
	st.set_normal(normal)
	st.set_uv(uc)
	st.add_vertex(c)


func _face_cols(
		st: SurfaceTool,
		a: Vector3,
		b: Vector3,
		c: Vector3,
		d: Vector3,
		ca: Color,
		cb: Color,
		cc: Color,
		cd: Color,
		outward: Vector3
	) -> void:
	var aim := outward
	if aim.length_squared() < 0.0001:
		aim = a + b + c + d
	if (b - a).cross(c - a).dot(aim) < 0.0:
		_paint_tri_cols(st, a, d, c, ca, cd, cc, aim)
		_paint_tri_cols(st, a, c, b, ca, cc, cb, aim)
	else:
		_paint_tri_cols(st, a, b, c, ca, cb, cc, aim)
		_paint_tri_cols(st, a, c, d, ca, cc, cd, aim)


func _paint_tri_cols(
		st: SurfaceTool,
		a: Vector3,
		b: Vector3,
		c: Vector3,
		ca: Color,
		cb: Color,
		cc: Color,
		outward: Vector3
	) -> void:
	var normal := outward.normalized()
	if normal.length_squared() < 0.5:
		normal = ((b - a).cross(c - a)).normalized()
	if normal.length_squared() < 0.5:
		normal = a.normalized()
	var mid := (a + b + c) * (1.0 / 3.0)
	var up := mid.normalized()
	if up.length_squared() < 0.25:
		up = Vector3.UP
	var roof := absf(normal.dot(up))
	st.set_color(ca)
	st.set_normal(normal)
	st.set_uv(_mass_paint_uv(a, normal, up, roof))
	st.add_vertex(a)
	st.set_color(cb)
	st.set_normal(normal)
	st.set_uv(_mass_paint_uv(b, normal, up, roof))
	st.add_vertex(b)
	st.set_color(cc)
	st.set_normal(normal)
	st.set_uv(_mass_paint_uv(c, normal, up, roof))
	st.add_vertex(c)


func _paint_tri(
		st: SurfaceTool,
		a: Vector3,
		b: Vector3,
		c: Vector3,
		colour: Color,
		outward: Vector3
	) -> void:
	var normal := outward.normalized()
	if normal.length_squared() < 0.5:
		normal = ((b - a).cross(c - a)).normalized()
	if normal.length_squared() < 0.5:
		normal = a.normalized()
	var mid := (a + b + c) * (1.0 / 3.0)
	var up := mid.normalized()
	if up.length_squared() < 0.25:
		up = Vector3.UP
	var roof := absf(normal.dot(up))
	st.set_color(colour)
	st.set_normal(normal)
	st.set_uv(_mass_paint_uv(a, normal, up, roof))
	st.add_vertex(a)
	st.set_color(colour)
	st.set_normal(normal)
	st.set_uv(_mass_paint_uv(b, normal, up, roof))
	st.add_vertex(b)
	st.set_color(colour)
	st.set_normal(normal)
	st.set_uv(_mass_paint_uv(c, normal, up, roof))
	st.add_vertex(c)


func _mass_paint_uv(pos: Vector3, normal: Vector3, up: Vector3, roof: float) -> Vector2:
	var tangent := up.cross(normal)
	if tangent.length_squared() < 0.02:
		tangent = up.cross(Vector3.RIGHT)
	if tangent.length_squared() < 0.02:
		tangent = up.cross(Vector3.FORWARD)
	tangent = tangent.normalized()
	var along := pos.dot(tangent)
	var height := pos.dot(up)
	if roof > 0.72:
		return Vector2(fposmod(along * 0.06, 1.0), 0.72 + fposmod(height * 0.06, 1.0) * 0.28)
	var face := floorf(fposmod(atan2(normal.x, normal.z) * (2.0 / PI) + 8.0, 4.0))
	return Vector2(
		(face + fposmod(along * 0.08, 1.0)) * 0.25,
		fposmod(height * 0.065, 1.0) * 0.72)


func _discard_node(node: Node) -> void:
	if node == null or not is_instance_valid(node):
		return
	var parent := node.get_parent()
	if parent != null:
		parent.remove_child(node)
	node.free()


func _commit_mesh(st: SurfaceTool, mesh_name: String, unshaded: bool) -> MeshInstance3D:
	var mesh := st.commit()
	if mesh.get_surface_count() == 0:
		return null
	var material := StandardMaterial3D.new()
	material.shading_mode = (
		BaseMaterial3D.SHADING_MODE_UNSHADED if unshaded
		else BaseMaterial3D.SHADING_MODE_PER_PIXEL)
	material.vertex_color_use_as_albedo = true
	# Walked on from above and flown under from below; a one-sided slab is
	# invisible on the top and a box you cannot climb out of.
	material.cull_mode = BaseMaterial3D.CULL_DISABLED
	material.disable_receive_shadows = unshaded
	var instance := MeshInstance3D.new()
	instance.name = mesh_name
	instance.mesh = mesh
	instance.material_override = material
	instance.cast_shadow = (
		GeometryInstance3D.SHADOW_CASTING_SETTING_OFF if unshaded
		else GeometryInstance3D.SHADOW_CASTING_SETTING_ON)
	add_child(instance)
	return instance


func _collide(mesh: Mesh, body_name: String) -> StaticBody3D:
	if mesh == null or mesh.get_surface_count() == 0:
		return null
	var shape := mesh.create_trimesh_shape()
	if shape == null:
		return null
	if shape is ConcavePolygonShape3D:
		(shape as ConcavePolygonShape3D).backface_collision = true
	var body := StaticBody3D.new()
	body.name = body_name
	body.collision_layer = 1
	body.collision_mask = 1
	var collider := CollisionShape3D.new()
	collider.shape = shape
	body.add_child(collider)
	add_child(body)
	return body


func _rank_half(rank: int) -> float:
	match rank:
		1:
			return ARTERIAL_HALF
		2:
			return COLLECTOR_HALF
	return LOCAL_HALF


func _rank_color(rank: int) -> Color:
	match rank:
		1:
			return ARTERIAL_COLOR
		2:
			return COLLECTOR_COLOR
	return LOCAL_COLOR


func _ribbon(
		st: SurfaceTool,
		shape: PlanetShape,
		dirs: PackedVector3Array,
		half_width: float,
		colour: Color,
		lift: float,
		skip_wet: bool = true
	) -> void:
	if dirs.size() < 2:
		return
	var closed := dirs[0].dot(dirs[dirs.size() - 1]) > 0.999
	var unique := PackedVector3Array()
	var limit := dirs.size() - 1 if closed else dirs.size()
	for index in limit:
		unique.append(dirs[index])
	if unique.size() < 2:
		return
	var points := PackedVector3Array()
	var count := unique.size()
	var segments := count if closed else count - 1
	for index in segments:
		var a := unique[index]
		var b := unique[(index + 1) % count]
		var arc := a.angle_to(b) * shape.radius
		var pieces := maxi(1, int(ceili(arc / ROAD_STEP)))
		for piece in pieces:
			var t := float(piece) / float(pieces)
			var direction := a.slerp(b, t)
			if skip_wet and shape.elevation(direction, ROAD_STEP) < 0.0:
				continue
			points.append(shape.surface_point(direction) + direction * lift)
	if not closed:
		var last := unique[count - 1]
		if not skip_wet or shape.elevation(last, ROAD_STEP) >= 0.0:
			points.append(shape.surface_point(last) + last * lift)
	var n := points.size()
	if n < 2:
		return
	var sides: PackedVector3Array = PackedVector3Array()
	sides.resize(n)
	var previous := Vector3.ZERO
	for index in n:
		var before := points[n - 1] if index == 0 else points[index - 1]
		var after := points[0] if index == n - 1 else points[index + 1]
		if not closed:
			if index == 0:
				before = points[index]
			if index == n - 1:
				after = points[index]
		var tangent := after - before
		if tangent.length_squared() < 0.0001:
			tangent = after - points[index]
		var up := points[index].normalized()
		var side := up.cross(tangent)
		if side.length_squared() < 0.0001:
			side = previous if previous.length_squared() > 0.0001 else up.cross(Vector3.RIGHT)
		side = side.normalized()
		if previous.length_squared() > 0.0001 and side.dot(previous) < 0.0:
			side = -side
		previous = side
		sides[index] = side * half_width
	var quads := n if closed else n - 1
	for index in quads:
		var next := (index + 1) % n
		_quad(
			st,
			points[index] - sides[index],
			points[index] + sides[index],
			points[next] + sides[next],
			points[next] - sides[next],
			colour)


func _quad(
		st: SurfaceTool,
		a: Vector3,
		b: Vector3,
		c: Vector3,
		d: Vector3,
		colour: Color
	) -> void:
	_tri(st, a, b, c, colour)
	_tri(st, a, c, d, colour)


func _tri(
		st: SurfaceTool,
		a: Vector3,
		b: Vector3,
		c: Vector3,
		colour: Color
	) -> void:
	st.set_color(colour)
	st.set_normal(a.normalized())
	st.add_vertex(a)
	st.set_color(colour)
	st.set_normal(b.normalized())
	st.add_vertex(b)
	st.set_color(colour)
	st.set_normal(c.normalized())
	st.add_vertex(c)


func _to_uv(direction: Vector3) -> Vector2:
	var q := direction - _up * direction.dot(_up)
	return Vector2(q.dot(_east), q.dot(_north)) * _radius


func _from_uv(uv: Vector2) -> Vector3:
	return (_up + (_east * uv.x + _north * uv.y) / _radius).normalized()
