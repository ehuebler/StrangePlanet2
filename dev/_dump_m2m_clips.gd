extends SceneTree

## Print Mixamo-sidecar track paths and posed bones after CharacterRig remaps
## them onto the live settler body.

const CharacterRigScript := preload("res://game/player/character_rig.gd")
const BODY := "res://assets/runtime/characters/player_character_3.glb"
const EXTRA := "res://assets/runtime/characters/player_character_3_m2m.glb"
const SAMPLE := ["Idle", "Idle_A", "Sprint", "Melee_Hook", "m2m_Walk", "Fighting_Idle"]
const BONES := ["Hips", "Spine", "LeftUpperArm", "LeftHand", "RightUpperArm", "RightHand"]


func _initialize() -> void:
	var extra_scene: PackedScene = load(EXTRA)
	var extra: Node = extra_scene.instantiate()
	print("=== sidecar tree ===")
	_print_tree(extra, 0)
	var extra_anim: AnimationPlayer = CharacterRigScript.animator_of(extra)
	if extra_anim != null and extra_anim.has_animation("Idle_A"):
		var raw := extra_anim.get_animation("Idle_A")
		print("sidecar Idle_A tracks=", raw.get_track_count(),
			" path0=", raw.track_get_path(0) if raw.get_track_count() > 0 else "")
	extra.free()

	var scene: PackedScene = load(BODY)
	var root: Node = scene.instantiate()
	var animator: AnimationPlayer = CharacterRigScript.animator_of(root)
	CharacterRigScript.prepare(animator, PackedStringArray([EXTRA]))
	var skeleton := root.find_child("Skeleton3D", true, false) as Skeleton3D
	print("clips=", animator.get_animation_list().size())
	print("--- rest")
	for bone_name in BONES:
		var bone := skeleton.find_bone(bone_name)
		var rest := skeleton.get_bone_rest(bone)
		print("  ", bone_name, " rest_pos=", rest.origin,
			" rest_q=", rest.basis.get_rotation_quaternion(),
			" global=", skeleton.get_bone_global_rest(bone).origin)
	for clip_name in SAMPLE:
		if not animator.has_animation(clip_name):
			print("MISSING ", clip_name)
			continue
		var anim := animator.get_animation(clip_name)
		print("--- ", clip_name, " tracks=", anim.get_track_count(), " len=", anim.length)
		if anim.get_track_count() > 0:
			print("  track0=", anim.track_get_path(0), " type=", anim.track_get_type(0))
		var colon := 0
		var node_paths := 0
		for index in anim.get_track_count():
			if str(anim.track_get_path(index)).contains(":"):
				colon += 1
			else:
				node_paths += 1
		print("  skeleton_tracks=", colon, " node_tracks=", node_paths)
		_print_track_keys(anim, "LeftUpperArm")
		for bone_name in BONES:
			var xf := _posed(skeleton, anim, 0.0, bone_name)
			print("  ", bone_name, " t0=", xf.origin)
		if anim.length > 0.2:
			print("  LeftHand t_mid=", _posed(skeleton, anim, anim.length * 0.5, "LeftHand").origin)
	root.free()
	quit()


func _posed(skeleton: Skeleton3D, clip: Animation, time: float, bone_name: String) -> Transform3D:
	var chain: Array[int] = []
	var index := skeleton.find_bone(bone_name)
	while index >= 0:
		chain.push_front(index)
		index = skeleton.get_bone_parent(index)
	var accumulated := Transform3D.IDENTITY
	for bone in chain:
		var local := skeleton.get_bone_rest(bone)
		var name := skeleton.get_bone_name(bone)
		var rotation := _track(clip, name, Animation.TYPE_ROTATION_3D)
		if rotation >= 0:
			local.basis = Basis(clip.rotation_track_interpolate(rotation, time))
		var position := _track(clip, name, Animation.TYPE_POSITION_3D)
		if position >= 0:
			local.origin = clip.position_track_interpolate(position, time)
		accumulated *= local
	return accumulated


func _track(clip: Animation, bone_name: String, type: int) -> int:
	for index in clip.get_track_count():
		if clip.track_get_type(index) == type \
				and String(clip.track_get_path(index)).ends_with(":" + bone_name):
			return index
	return -1


func _print_track_keys(anim: Animation, bone_name: String) -> void:
	for index in anim.get_track_count():
		var path := str(anim.track_get_path(index))
		if not path.ends_with(":" + bone_name) and not path.ends_with("/" + bone_name):
			continue
		if anim.track_get_key_count(index) == 0:
			continue
		print("  key0 ", anim.track_get_type(index), " ", path, " = ", anim.track_get_key_value(index, 0))
		if anim.track_get_key_count(index) > 1:
			print("  key1 ", anim.track_get_type(index), " ", path, " = ", anim.track_get_key_value(index, 1))


func _print_tree(node: Node, depth: int) -> void:
	var extra := ""
	if node is Skeleton3D:
		extra = " bones=%d" % (node as Skeleton3D).get_bone_count()
	elif node is MeshInstance3D:
		extra = " skin=%s" % ((node as MeshInstance3D).skin != null)
	print("  ".repeat(depth) + node.name + " [" + node.get_class() + "]" + extra)
	if depth < 6:
		for child in node.get_children():
			_print_tree(child, depth + 1)
