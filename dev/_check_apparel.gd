extends SceneTree

## Verifies the apparel .glb files wear correctly on the imported character.
##
## Run headless from the project root:
##
##     & "C:\Users\ellio\Downloads\godot47\Godot_v4.7-stable_win64_console.exe" --headless --path . --script dev/_check_apparel.gd
##
## It checks the things that silently break a shared-skeleton wardrobe: that each
## garment binds to the body's own Skeleton3D rather than dragging in a second
## one, that its skin binds resolve against the body's bones by name, and that
## the body's clips actually move the garment.

# Preloaded rather than used via its class_name, so this runs before the editor
# has refreshed its global class cache.
const WardrobeScript := preload("res://game/player/wardrobe.gd")

# Repeated here rather than read off CharacterDB: `--script` runs without
# autoloads, and CharacterDB reaches SettingsManager for the saved look.
const BODIES := {
	"astronaut": {
		"scene": "res://assets/runtime/characters/player_character.glb",
		"apparel": ["shoes", "pants", "long_sleeve", "hat", "goggles"],
	},
	"settler": {
		"scene": "res://assets/runtime/characters/player_character_3.glb",
		"apparel": [
			"c3_boots", "c3_tunic", "c3_hair", "c3_goggles",
			"c3_party_hat", "c3_bunny_ears", "c3_top_hat", "c3_crown", "c3_beanie",
			"c3_cowboy_hat", "c3_propeller_cap", "c3_flower_crown", "c3_antlers",
			"c3_halo", "c3_wizard_hat", "c3_sombrero", "c3_newsboy_cap", "c3_helmet",
			"c3_pirate_hat", "c3_chef_toque", "c3_jester_hat", "c3_mushroom_cap",
			"c3_antennae", "c3_visor", "c3_bow", "c3_horned_helm", "c3_fedora",
			"c3_santa_hat", "c3_cat_ears",
			"c3_beret", "c3_baseball_cap", "c3_sun_hat", "c3_hard_hat", "c3_ushanka",
			"c3_turban", "c3_devil_horns", "c3_unicorn_horn", "c3_headphones",
			"c3_tiara", "c3_bandana", "c3_rice_hat", "c3_laurel", "c3_nightcap",
			"c3_deerstalker", "c3_frog_hood", "c3_rainbow", "c3_paper_crown",
			"c3_space_helmet", "c3_cake_hat", "c3_leaf_wreath", "c3_mohawk",
		],
	},
}

const APPAREL_PATH := "res://assets/runtime/apparel/apparel_%s.glb"


func _init() -> void:
	for body_id: String in BODIES:
		print("=== ", body_id, " ===")
		_check(BODIES[body_id])
	quit()


func _check(body: Dictionary) -> void:
	var scene := load(String(body["scene"])) as PackedScene
	var character := scene.instantiate()
	get_root().add_child(character)

	var skeleton := WardrobeScript.skeleton_of(character)
	print("skeleton: %s, %d bones" % [skeleton.name, skeleton.get_bone_count()])

	var player: AnimationPlayer = null
	for node in character.find_children("*", "AnimationPlayer", true, false):
		player = node
		break
	var clips := player.get_animation_list() if player != null else PackedStringArray()
	print("clips: %s" % [clips])

	var bones := {}
	for index in skeleton.get_bone_count():
		bones[skeleton.get_bone_name(index)] = index

	print("--- equipping ---")
	var worn: Array[MeshInstance3D] = []
	for slug: String in body["apparel"]:
		var garment := WardrobeScript.equip(character, slug, APPAREL_PATH % slug)
		if garment != null:
			worn.append(garment)
	for mesh in worn:
		var skin := mesh.skin
		var binds := skin.get_bind_count() if skin != null else 0
		var unresolved := []
		for bind in binds:
			var bone_name := skin.get_bind_name(bind)
			if not bones.has(bone_name):
				unresolved.append(bone_name)
		print("  %-22s parent=%s skeleton_ok=%s surfaces=%d binds=%d unresolved=%s" % [
			mesh.name,
			mesh.get_parent().name,
			mesh.get_node_or_null(mesh.skeleton) == skeleton,
			mesh.mesh.get_surface_count(),
			binds,
			unresolved,
		])

	# A garment is only really driven if moving the skeleton moves its vertices.
	# Comparing the skinned bounds before and after advancing a clip is the check
	# that would catch a garment silently stuck in the rest pose.
	if player != null and clips.has("Walk"):
		var before := _skinned_extent(skeleton)
		player.play("Walk")
		player.advance(0.35)
		var after := _skinned_extent(skeleton)
		print("--- Walk ---")
		print("  right foot y %.4f -> %.4f (moved=%s)" % [before, after, absf(after - before) > 0.001])

	print("tree under skeleton: %s" % [_child_names(skeleton)])
	character.queue_free()


func _skinned_extent(skeleton: Skeleton3D) -> float:
	var index := skeleton.find_bone("RightFoot")
	if index < 0:
		return 0.0
	return skeleton.get_bone_global_pose(index).origin.z


func _child_names(node: Node) -> Array:
	var names := []
	for child in node.get_children():
		names.append("%s(%s)" % [child.name, child.get_class()])
	return names
