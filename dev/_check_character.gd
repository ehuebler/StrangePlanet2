extends SceneTree

## Bones, facing and bounds for every body .glb, or one named with
## `-- --body=settler`.
##
## The paths are repeated here rather than read off CharacterDB: `--script` runs
## without autoloads, and CharacterDB reaches SettingsManager to load the saved
## look, so importing it here fails to compile before the first line runs.

const CharacterRigScript := preload("res://game/player/character_rig.gd")

const BODIES := {
	"astronaut": "res://assets/runtime/characters/player_character.glb",
	"settler": "res://assets/runtime/characters/player_character_3.glb",
}

## Clips whose pose is measured as well as listed, because they are the ones a
## pose-table edit is most likely to have reached on only one body: the
## astronaut is baked by build_animations.py and the settler by
## build_character_3.py calling into it, and re-running the first alone leaves
## the second on the old poses with no error anywhere. Both should report the
## same lean and roughly the same reach, scaled by the difference in height.
const POSED := ["Idle", "Run", "JumpRise", "Fall", "AirRun", "Float", "Fly",
	"Swim", "Tread", "NukeThrow", "NukeFloatThrow", "LassoThrow",
	"LassoFloatThrow", "LassoHold", "LassoFloatHold", "WallPlace",
	"WallFloatPlace", "NausicaMark", "NausicaFloatMark"]

## Clips that play straight into one another, and so have to agree at the join.
## `[from, to, what]`, measured at the end of the first and the start of the
## second.
##
## `JumpRise` into `Fall` is the one that mattered: a jump reaches its apex in
## about a third of a second and the switch is on vertical speed, so the seam is
## in the air in front of the player on every single jump. Fall's arms used to
## swing forward into a bent-elbow hang while the leap had them swept back, and
## the character spent the top of every jump reaching out in front of itself.
## Nothing here could see it, because both clips looked right on their own.
const SEAMS := [
	["JumpRise", "Fall", "the top of a jump"],
]

## How far a hand may move across a seam, in metres, **measured in the chest's own
## frame**. A hand's whole reach is about 0.6 m, and the crossfade is 0.12 s: a few
## centimetres is the clips relaxing into each other, a fifth of a metre is one of
## them changing its mind.
##
## Taken against the chest and not against the hips because the two things that
## move a hand here want opposite verdicts. A torso settling out of the leap's arch
## carries the shoulders 15 cm on its own and looks like exactly what it is,
## somebody relaxing; an arm reversing under a chest that did not move is the fault
## being looked for. Measured from the hips the first drowns out the second.
const SEAM_TOLERANCE := 0.09


func _print_tree(node: Node, depth: int) -> void:
	print("  ".repeat(depth) + node.name + " [" + node.get_class() + "]")
	for child in node.get_children():
		_print_tree(child, depth + 1)


func _initialize() -> void:
	var wanted := PackedStringArray()
	for argument in OS.get_cmdline_user_args():
		if argument.begins_with("--body="):
			wanted.append(argument.trim_prefix("--body="))
	if wanted.is_empty():
		wanted = PackedStringArray(BODIES.keys())
	for body_id in wanted:
		print("=== ", body_id, " ===")
		_check(String(BODIES.get(body_id, body_id)))
	quit()


func _check(path: String) -> void:
	var scene: PackedScene = load(path)
	var root: Node = scene.instantiate()
	_print_tree(root, 0)

	var skeleton := root.find_child("Skeleton3D", true, false) as Skeleton3D
	if skeleton == null:
		print("RESULT: no Skeleton3D found")
	else:
		print("RESULT bone_count=", skeleton.get_bone_count())
		print("RESULT bones=", range(skeleton.get_bone_count()).map(
			func(i: int) -> String: return skeleton.get_bone_name(i)))

	if skeleton != null:
		var ankle := skeleton.get_bone_global_rest(
			CharacterRigScript.find_bone(skeleton, &"LeftFoot")).origin
		var toe := skeleton.get_bone_global_rest(
			CharacterRigScript.find_bone(skeleton, &"LeftToes")).origin
		print("RESULT ankle=", ankle, " toe=", toe)
		# Godot's -Z is forward, so the toes have to sit in front of the ankle.
		print("RESULT faces_forward=", toe.z < ankle.z)
		# And the left hand has to be on the left, which in Godot is +X.
		print("RESULT left_hand_x=",
			skeleton.get_bone_global_rest(
				CharacterRigScript.find_bone(skeleton, &"LeftHand")).origin.x)
		var nose := skeleton.get_bone_global_rest(
			CharacterRigScript.find_bone(skeleton, &"Head")).origin
		print("RESULT head_at=", nose)

	for child in skeleton.get_children():
		if child is MeshInstance3D:
			var aabb := (child as MeshInstance3D).mesh.get_aabb()
			print("RESULT aabb_pos=", aabb.position, " aabb_size=", aabb.size)
			print("RESULT surfaces=", (child as MeshInstance3D).mesh.get_surface_count())
	if skeleton != null:
		_poses(root, skeleton)
	root.free()


## Where each measured clip actually puts the body, read out of the shipped
## .glb. The animations are sampled as resources and posed by hand rather than
## played: headless has no rendering, and an AnimationPlayer stepped without one
## is the thing gotcha 19 says not to trust.
func _poses(root: Node, skeleton: Skeleton3D) -> void:
	var player := root.find_child("AnimationPlayer", true, false) as AnimationPlayer
	if player == null:
		print("RESULT: no AnimationPlayer")
		return
	print("RESULT clips=", player.get_animation_list())
	var authored_seams := player.has_animation("JumpRise")
	CharacterRigScript.prepare(player)
	for clip_name in POSED:
		var resolved := CharacterRigScript.resolve_clip(player, clip_name)
		if not player.has_animation(resolved):
			print("RESULT pose ", clip_name, " MISSING")
			continue
		clip_name = resolved
		var clip := player.get_animation(clip_name)
		# A quarter of the way in. Every cycle here is symmetric about its
		# midpoint, so phase 0 and phase 0.5 are the two frames where the arms
		# agree with each other and say nothing about which way they swing.
		var time := clip.length * 0.25
		var hips := _posed(skeleton, clip, time, "Hips").origin
		var neck := _posed(skeleton, clip, time, "Neck").origin
		var hand := _posed(skeleton, clip, time, "RightHand").origin
		var left := _posed(skeleton, clip, time, "LeftFoot").origin
		var right := _posed(skeleton, clip, time, "RightFoot").origin
		print("RESULT pose %-9s torso %+6.1f deg   right hand %+.2f fwd %+.2f up"
			% [clip_name, rad_to_deg(atan2(hips.z - neck.z, neck.y - hips.y)),
				hips.z - hand.z, hand.y - hips.y]
			+ "   feet %+.2f / %+.2f under hips" % [left.y - hips.y, right.y - hips.y])
	if authored_seams:
		_seams(skeleton, player)


## How far the hands jump, relative to the chest, where one clip hands over to the
## next.
func _seams(skeleton: Skeleton3D, player: AnimationPlayer) -> void:
	for seam: Array in SEAMS:
		var from := String(seam[0])
		var to := String(seam[1])
		if not player.has_animation(from) or not player.has_animation(to):
			continue
		var leaving := player.get_animation(from)
		var arriving := player.get_animation(to)
		var moved := 0.0
		for bone_name in ["RightHand", "LeftHand"]:
			var was := _in_chest(skeleton, leaving, leaving.length, bone_name)
			var now := _in_chest(skeleton, arriving, 0.0, bone_name)
			moved = maxf(moved, was.distance_to(now))
		print("RESULT seam %s into %s: hands move %.2f m against the chest at %s"
			% [from, to, moved, seam[2]])
		if moved > SEAM_TOLERANCE:
			printerr("FAIL: %s into %s moves a hand %.2f m, over the %.2f m the crossfade can hide"
				% [from, to, moved, SEAM_TOLERANCE])


func _in_chest(skeleton: Skeleton3D, clip: Animation, time: float, bone_name: String) -> Vector3:
	var chest := _posed(skeleton, clip, time, "UpperChest")
	return chest.affine_inverse() * _posed(skeleton, clip, time, bone_name).origin


## The bone's transform under one sampled frame of `clip`. Godot bone tracks
## carry the whole local transform rather than a delta from rest, so an
## untracked bone keeps its rest and a tracked one replaces it outright.
func _posed(skeleton: Skeleton3D, clip: Animation, time: float, bone_name: String) -> Transform3D:
	var chain: Array[int] = []
	var index := CharacterRigScript.find_bone(skeleton, StringName(bone_name))
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
