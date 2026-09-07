class_name CharacterRig
extends RefCounted

## Shared names for the two player skeletons: the authored humanoid (Hips,
## LeftHand, Idle) and the Mixamo/UE5 source in m2m_player.glb (pelvis,
## hand_l, Idle_A). Callers keep using the humanoid names; this file finds the
## bone or clip that actually exists on the body that is loaded.
##
## Mixamo clips are retargeted onto player_character_3 and stored in
## player_character_3_m2m.glb. Existing character-3 names stay on the body.

const BONES := {
	&"Hips": [&"Hips", &"pelvis"],
	&"Spine": [&"Spine", &"spine_01"],
	&"Chest": [&"Chest", &"spine_02"],
	&"UpperChest": [&"UpperChest", &"spine_03"],
	&"Neck": [&"Neck", &"neck_01"],
	&"Head": [&"Head", &"head"],
	&"LeftShoulder": [&"LeftShoulder", &"clavicle_l"],
	&"LeftUpperArm": [&"LeftUpperArm", &"upperarm_l"],
	&"LeftLowerArm": [&"LeftLowerArm", &"lowerarm_l"],
	&"LeftHand": [&"LeftHand", &"hand_l"],
	&"RightShoulder": [&"RightShoulder", &"clavicle_r"],
	&"RightUpperArm": [&"RightUpperArm", &"upperarm_r"],
	&"RightLowerArm": [&"RightLowerArm", &"lowerarm_r"],
	&"RightHand": [&"RightHand", &"hand_r"],
	&"LeftUpperLeg": [&"LeftUpperLeg", &"thigh_l"],
	&"LeftLowerLeg": [&"LeftLowerLeg", &"calf_l"],
	&"LeftFoot": [&"LeftFoot", &"foot_l"],
	&"LeftToes": [&"LeftToes", &"ball_l"],
	&"RightUpperLeg": [&"RightUpperLeg", &"thigh_r"],
	&"RightLowerLeg": [&"RightLowerLeg", &"calf_r"],
	&"RightFoot": [&"RightFoot", &"foot_r"],
	&"RightToes": [&"RightToes", &"ball_r"],
	&"head_leaf": [&"head_leaf"],
}

## Logical locomotion / ability names the rest of the game still speaks, mapped
## onto the Mixamo pack. A body that already has the logical name (the
## astronaut) is left alone.
const CLIP_ALIASES := {
	"Idle": "Idle_A",
	"Walk": "Walk",
	"Run": "Sprint",
	"Jog": "Jog",
	"CrouchIdle": "Crouch_Idle",
	"CrouchWalk": "Crouch_Walk",
	"Fall": "Jump_air",
	"JumpRise": "Jump_Start",
	"Land": "Jump_Land",
	"AirRun": "Run_Jump",
	"Float": "Levitate_Idle",
	"Fly": "Flying_Forward",
	"Swim": "Swim_Fwd",
	"Tread": "Swim_Idle",
	"Slide": "Slide",
	"Death_A": "Death_A",
	"Death_C": "Death_C",
	"MeteorFly": "Flying_Forward_Super",
	"HeroLand": "Land_Three_Point",
	"StarfireRight": "Fighting_Right_Jab",
	"StarfireLeft": "Fighting_Left_Jab",
	"StarfireFloatRight": "Fighting_Right_Jab",
	"StarfireFloatLeft": "Fighting_Left_Jab",
	"HeroPunchRight": "Fighting_Right_Jab",
	"HeroPunchLeft": "Fighting_Left_Jab",
	"HeroPunchFloatRight": "Fighting_Right_Jab",
	"HeroPunchFloatLeft": "Fighting_Left_Jab",
	"GrappleGrab": "Melee_Hook",
	"GrappleCarry": "Walk_Carry",
	"NukeThrow": "OverhandThrow",
	"NukeFloatThrow": "Throw_Object",
	"LassoThrow": "Throw_Object",
	"LassoFloatThrow": "OverhandThrow",
	"LassoHold": "Fighting_Idle",
	"LassoFloatHold": "Levitate_Idle",
	"WallPlace": "Two-hand_Blast",
	"WallFloatPlace": "Spell_Simple_Enter",
	"FieldCast": "Spell_Simple_Enter",
	"Roar": "Two-hand_Blast",
	"Kame": "Two-hand_Blast",
	"NausicaMark": "Spell_Simple_Shoot",
	"NausicaFloatMark": "Spell_Simple_Shoot",
}

const LOOPING_CLIPS := [
	"Idle", "Idle_A", "Idle_Subtle", "Walk", "m2m_Walk", "Jog", "Run", "Sprint",
	"CrouchIdle", "Crouch_Idle", "CrouchWalk", "Crouch_Walk",
	"Fall", "Jump_air", "AirRun", "Run_Jump",
	"Float", "Levitate_Idle", "Fly", "Flying_Forward", "Flying_Forward_Super",
	"Glide", "Swim", "Swim_Fwd", "Tread", "Swim_Idle", "Slide", "m2m_Slide",
	"GrappleCarry", "Walk_Carry", "LassoHold", "LassoFloatHold",
	"Fighting_Idle", "Spell_Simple_Idle", "Crawl", "Crawl_RM",
	"Idle_Talking", "Idle_FoldArms", "Idle_Listening", "Idle_Hurt",
	"Idle_Lantern", "Idle_Rail", "Idle_Shield", "Idle_Sword", "Idle_Torch",
	"Walk_Backwards", "Walk_Female", "Walk_Formal",
	"Walk_Large", "Walk_Stealth", "Strafe_left", "Strafe_right",
	"Run_Anime", "Run_Female", "Run_Stealth", "Zombie_Idle", "Zombie_Walk",
	"Zombie_Walk_2", "Zombie_Idle_Crouch", "Driving", "Push", "Climb_Ladder",
	"Climb_Wall", "Pipe_Climb", "Ladder_Idle", "Ledge_Hang", "Meditate",
	"Sleeping", "Sitting_Idle", "Sitting_Talking", "Shivering", "Dizzy",
	"NinjaJump_Idle", "Pistol_Idle",
]


static func animator_of(root: Node) -> AnimationPlayer:
	if root == null:
		return null
	var direct := root.get_node_or_null("AnimationPlayer") as AnimationPlayer
	if direct != null:
		return direct
	for node in root.find_children("*", "AnimationPlayer", true, false):
		return node as AnimationPlayer
	return null


## The Mixamo export names its skinned mesh `Skinned Mesh 0` and faces +Z.
## The rest of the game looks for `Character` and walks toward -Z, so the first
## skinned mesh is renamed and a backward-facing rest is turned around once
## after the body is instanced.
static func normalize_body(root: Node) -> void:
	if root == null:
		return
	for node in root.find_children("*", "MeshInstance3D", true, false):
		var mesh := node as MeshInstance3D
		if mesh.skin == null:
			continue
		if String(mesh.name).begins_with(Wardrobe.NODE_PREFIX) \
				or String(mesh.name).begins_with(Weapons.NODE_PREFIX):
			continue
		mesh.name = "Character"
		break
	var skeleton: Skeleton3D = null
	for node in root.find_children("*", "Skeleton3D", true, false):
		skeleton = node as Skeleton3D
		break
	if skeleton == null or not (root is Node3D):
		return
	var foot := find_bone(skeleton, &"LeftFoot")
	var toes := find_bone(skeleton, &"LeftToes")
	if foot < 0 or toes < 0:
		return
	var ankle := skeleton.get_bone_global_rest(foot).origin
	var toe := skeleton.get_bone_global_rest(toes).origin
	if toe.z >= ankle.z:
		(root as Node3D).rotate_y(PI)


static func find_bone(skeleton: Skeleton3D, name: StringName) -> int:
	if skeleton == null:
		return -1
	var id := skeleton.find_bone(String(name))
	if id >= 0:
		return id
	var key := canonical_bone(name)
	for alias: StringName in BONES.get(key, [name]):
		id = skeleton.find_bone(String(alias))
		if id >= 0:
			return id
	return -1


static func bone_name(skeleton: Skeleton3D, name: StringName) -> StringName:
	var id := find_bone(skeleton, name)
	if id < 0:
		return name
	return StringName(skeleton.get_bone_name(id))


static func canonical_bone(name: StringName) -> StringName:
	if BONES.has(name):
		return name
	for key: StringName in BONES:
		for alias: StringName in BONES[key]:
			if alias == name:
				return key
	return name


static func resolve_clip(animator: AnimationPlayer, clip: String) -> String:
	if animator == null or clip.is_empty():
		return clip
	if animator.has_animation(clip):
		return clip
	var mapped := String(CLIP_ALIASES.get(clip, clip))
	if mapped != clip and animator.has_animation(mapped):
		return mapped
	return clip


static func has_clip(animator: AnimationPlayer, clip: String) -> bool:
	if animator == null or clip.is_empty():
		return false
	return animator.has_animation(resolve_clip(animator, clip))


static var _extra_clip_cache: Dictionary = {}


static func prepare(animator: AnimationPlayer,
		extra_scenes: PackedStringArray = PackedStringArray()) -> void:
	if animator == null:
		return
	_merge_extra_scenes(animator, extra_scenes)
	_install_aliases(animator)
	for clip_name in LOOPING_CLIPS:
		if animator.has_animation(clip_name):
			animator.get_animation(clip_name).loop_mode = Animation.LOOP_LINEAR


static func _merge_extra_scenes(animator: AnimationPlayer,
		extra_scenes: PackedStringArray) -> void:
	if extra_scenes.is_empty() or animator.has_meta("extra_anims_merged"):
		return
	animator.set_meta("extra_anims_merged", true)
	var libraries := animator.get_animation_library_list()
	if libraries.is_empty():
		return
	var lib := animator.get_animation_library(libraries[0])
	if lib == null:
		return
	var skeleton := _skeleton_near(animator)
	for path: String in extra_scenes:
		var clips := _clips_from_scene(path)
		for clip_name: String in clips:
			if animator.has_animation(clip_name):
				continue
			var anim: Animation = clips[clip_name]
			lib.add_animation(clip_name, _retarget_animation(anim, animator, skeleton))


static func _clips_from_scene(path: String) -> Dictionary:
	if _extra_clip_cache.has(path):
		return _extra_clip_cache[path]
	var clips: Dictionary = {}
	if path.is_empty() or not ResourceLoader.exists(path):
		_extra_clip_cache[path] = clips
		return clips
	var packed := load(path) as PackedScene
	if packed == null:
		_extra_clip_cache[path] = clips
		return clips
	var extra := packed.instantiate()
	var src := animator_of(extra)
	if src != null:
		for clip_name in src.get_animation_list():
			var anim := src.get_animation(clip_name)
			if anim != null:
				clips[clip_name] = anim.duplicate(true)
	extra.free()
	_extra_clip_cache[path] = clips
	return clips


static func _skeleton_near(animator: AnimationPlayer) -> Skeleton3D:
	var root := animator.get_parent()
	if root == null:
		return null
	for node in root.find_children("*", "Skeleton3D", true, false):
		return node as Skeleton3D
	return null


static func _retarget_animation(anim: Animation, animator: AnimationPlayer,
		skeleton: Skeleton3D) -> Animation:
	var copy := anim.duplicate(true) as Animation
	if skeleton == null:
		return copy
	var prefix := _skeleton_track_prefix(animator, skeleton)
	if prefix.is_empty():
		return copy
	for index in copy.get_track_count():
		var bone := _bone_from_track_path(str(copy.track_get_path(index)))
		if bone.is_empty() or skeleton.find_bone(bone) < 0:
			continue
		copy.track_set_path(index, NodePath("%s:%s" % [prefix, bone]))
	return copy


## Bone tracks on the body .glb look like `CharacterRig/Skeleton3D:Hips`. The
## Mixamo sidecar can arrive as a node chain (`CharacterRig/Root/Hips`) when it
## is exported without a skin. Both have to land on the live skeleton.
static func _bone_from_track_path(path: String) -> String:
	var sep := path.rfind(":")
	if sep >= 0:
		return path.substr(sep + 1)
	var slash := path.rfind("/")
	return path.substr(slash + 1) if slash >= 0 else path


static func _skeleton_track_prefix(animator: AnimationPlayer, skeleton: Skeleton3D) -> String:
	if animator.has_animation("Idle"):
		var idle := animator.get_animation("Idle")
		for index in idle.get_track_count():
			var path := str(idle.track_get_path(index))
			var sep := path.rfind(":")
			if sep < 0:
				continue
			if skeleton.find_bone(path.substr(sep + 1)) >= 0:
				return path.substr(0, sep)
	if animator.is_inside_tree():
		var root := animator.get_node_or_null(animator.root_node)
		if root != null:
			return str(root.get_path_to(skeleton))
	return "CharacterRig/Skeleton3D"


static func _install_aliases(animator: AnimationPlayer) -> void:
	var libraries := animator.get_animation_library_list()
	if libraries.is_empty():
		return
	var lib := animator.get_animation_library(libraries[0])
	if lib == null:
		return
	for logical: String in CLIP_ALIASES:
		var actual := String(CLIP_ALIASES[logical])
		if actual == logical or not animator.has_animation(actual):
			continue
		if animator.has_animation(logical):
			if not logical.begins_with("Starfire"):
				continue
			lib.remove_animation(logical)
		lib.add_animation(logical, animator.get_animation(actual))
