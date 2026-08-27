class_name PatchCityBake
extends Resource

## One phase of a generated city, packed so the game can recreate it without
## running [PatchCityGenerator]. Layout id is the planet cut this bake belongs
## to; phase is [PatchCity] PHASE_*. `scene` is the node tree. The dictionaries
## and packed arrays are the script state PackedScene cannot keep.

const LAYOUT_FIRST_PLANET := "first_planet"
const PHASE_FILE := [
	"0_layout.res",
	"1_paved.res",
	"2_mapped.res",
	"3_built.res",
	"4_painted.res",
]

@export var layout_id := LAYOUT_FIRST_PLANET
@export var patch_id := -1
@export var patch_name := ""
@export var phase := 0
@export var plan: Dictionary = {}
@export var fabric: Dictionary = {}
@export var places: Array = []
@export var minimap: Dictionary = {}
@export var pad_cell := 22.0
@export var pad_keys_x: PackedInt32Array = PackedInt32Array()
@export var pad_keys_y: PackedInt32Array = PackedInt32Array()
@export var pad_heights: PackedFloat32Array = PackedFloat32Array()
@export var pad_owner_x: PackedInt32Array = PackedInt32Array()
@export var pad_owner_y: PackedInt32Array = PackedInt32Array()
@export var pad_owners: PackedInt32Array = PackedInt32Array()
@export var lamp_spots: PackedVector3Array = PackedVector3Array()
@export var highway_dirs: PackedVector3Array = PackedVector3Array()
@export var highway_deck: PackedFloat32Array = PackedFloat32Array()
@export var highway_spur: PackedVector3Array = PackedVector3Array()
@export var exit_paths: Array = []
@export var ground_origin := Vector2.ZERO
@export var ground_span := Vector2.ONE
@export var ground_image: Image
@export var city_extent := 0.0
@export var dressed := false
@export var district_ground: Dictionary = {}
@export var district_accent: Dictionary = {}
@export var scene: PackedScene
