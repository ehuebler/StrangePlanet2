class_name RoarPose
extends SkeletonModifier3D

## Upper-body roar: scrunch with arms bent forward, then throw the head back
## and open the arms as the shockwave leaves.

const WINDUP := 0.35
const RELEASE_BLEND := 0.18
const FADE := 0.14
const BONES := {
	"chest": "Chest",
	"sternum": "UpperChest",
	"neck": "Neck",
	"head": "Head",
	"main_upper": "RightUpperArm",
	"main_lower": "RightLowerArm",
	"main_hand": "RightHand",
	"support_upper": "LeftUpperArm",
	"support_lower": "LeftLowerArm",
	"support_hand": "LeftHand",
}
const SCRUNCH := {
	"main": Vector3(0.10, -0.02, -0.17),
	"support": Vector3(-0.10, -0.02, -0.17),
	"chest": 0.42,
	"head": 0.28,
}
const RELEASE := {
	"main": Vector3(0.36, 0.18, 0.02),
	"support": Vector3(-0.36, 0.18, 0.02),
	"chest": -0.32,
	"head": -0.72,
}
const MAIN_POLE := Vector3(0.55, -1.0, 0.15)
const SUPPORT_POLE := Vector3(-0.65, -1.0, 0.1)

var _elapsed := -1.0
var _duration := 1.15
var _weight := 0.0
var _bones := {}


func play(duration: float) -> void:
	_duration = maxf(duration, WINDUP + RELEASE_BLEND)
	_elapsed = 0.0
	active = true


func playing() -> bool:
	return _elapsed >= 0.0


func _process(delta: float) -> void:
	if _elapsed >= 0.0:
		_elapsed += delta
		_weight = move_toward(_weight, 1.0, delta / 0.08)
		if _elapsed >= _duration:
			_elapsed = -1.0
		return
	_weight = move_toward(_weight, 0.0, delta / FADE)
	if _weight <= 0.001:
		active = false


func _process_modification() -> void:
	_apply()


func _process_modification_with_delta(_delta: float) -> void:
	_apply()


func _apply() -> void:
	var skeleton := get_skeleton()
	if skeleton == null or _weight <= 0.001:
		return
	if _bones.is_empty() and not _find_bones(skeleton):
		return
	var release := 0.0
	if _elapsed >= 0.0:
		release = clampf((_elapsed - WINDUP) / RELEASE_BLEND, 0.0, 1.0)
		release = release * release * (3.0 - 2.0 * release)
	var weight := clampf(_weight * influence, 0.0, 1.0)
	var chest_pitch := lerpf(float(SCRUNCH["chest"]), float(RELEASE["chest"]), release)
	var head_pitch := lerpf(float(SCRUNCH["head"]), float(RELEASE["head"]), release)
	_pitch_bone(skeleton, int(_bones["chest"]), chest_pitch * 0.45, weight)
	_pitch_bone(skeleton, int(_bones["sternum"]), chest_pitch * 0.55, weight)
	_pitch_bone(skeleton, int(_bones["neck"]), head_pitch * 0.35, weight)
	_pitch_bone(skeleton, int(_bones["head"]), head_pitch * 0.65, weight)

	var chest := _chest_frame(skeleton)
	var main: Vector3 = (SCRUNCH["main"] as Vector3).lerp(RELEASE["main"], release)
	var support: Vector3 = (SCRUNCH["support"] as Vector3).lerp(
		RELEASE["support"], release)
	var main_point := chest * main
	var support_point := chest * support
	_arm(skeleton, "main", main_point, chest.basis * MAIN_POLE, weight)
	_arm(skeleton, "support", support_point, chest.basis * SUPPORT_POLE, weight)


func _pitch_bone(skeleton: Skeleton3D, bone: int, angle: float, weight: float) -> void:
	if absf(angle) < 0.0001:
		return
	var turn := Quaternion(Vector3.RIGHT, angle * weight)
	skeleton.set_bone_pose_rotation(
		bone, skeleton.get_bone_pose_rotation(bone) * turn)


func _chest_frame(skeleton: Skeleton3D) -> Transform3D:
	var bone: int = _bones["sternum"]
	var pose := _global_pose(skeleton, bone)
	var rest := _rest_basis(skeleton, bone)
	return Transform3D(pose.basis * rest.inverse(), pose.origin)


func _arm(
		skeleton: Skeleton3D, side: String, target: Vector3, pole: Vector3,
		weight: float
	) -> void:
	var upper: int = _bones[side + "_upper"]
	var lower: int = _bones[side + "_lower"]
	var hand: int = _bones[side + "_hand"]
	var shoulder := _global_pose(skeleton, upper).origin
	var upper_length: float = skeleton.get_bone_rest(lower).origin.length()
	var lower_length: float = skeleton.get_bone_rest(hand).origin.length()
	var elbow := _elbow(shoulder, target, upper_length, lower_length, pole)
	_aim_bone(skeleton, upper, elbow - shoulder, Vector3.BACK, weight)
	_aim_bone(skeleton, lower, target - elbow, Vector3.BACK, weight)


func _elbow(
		shoulder: Vector3, target: Vector3, upper: float, lower: float,
		pole: Vector3
	) -> Vector3:
	var to_target := target - shoulder
	var reach := to_target.length()
	if reach < 0.0001:
		return shoulder + Vector3.DOWN * upper
	var limited := clampf(reach, absf(upper - lower) + 0.005, upper + lower - 0.005)
	var axis := to_target / reach
	var along := (upper * upper - lower * lower + limited * limited) / (2.0 * limited)
	var out := sqrt(maxf(upper * upper - along * along, 0.0))
	var side := pole - axis * pole.dot(axis)
	if side.length_squared() < 0.000001:
		side = Vector3.DOWN - axis * Vector3.DOWN.dot(axis)
	return shoulder + axis * along + side.normalized() * out


func _aim_bone(
		skeleton: Skeleton3D, bone: int, direction: Vector3, hint: Vector3,
		weight: float
	) -> void:
	_set_global_basis(skeleton, bone, _basis_with_y(direction, hint), weight)


func _set_global_basis(
		skeleton: Skeleton3D, bone: int, target: Basis, weight: float
	) -> void:
	var parent := skeleton.get_bone_parent(bone)
	var parent_basis := Basis.IDENTITY if parent < 0 \
		else _global_pose(skeleton, parent).basis
	var local := parent_basis.inverse() * target
	var wanted := Quaternion(local.orthonormalized())
	skeleton.set_bone_pose_rotation(
		bone, skeleton.get_bone_pose_rotation(bone).slerp(wanted, weight))


func _global_pose(skeleton: Skeleton3D, bone: int) -> Transform3D:
	var result := Transform3D.IDENTITY
	var index := bone
	while index >= 0:
		result = skeleton.get_bone_pose(index) * result
		index = skeleton.get_bone_parent(index)
	return result


func _rest_basis(skeleton: Skeleton3D, bone: int) -> Basis:
	var result := Basis.IDENTITY
	var index := bone
	while index >= 0:
		result = skeleton.get_bone_rest(index).basis * result
		index = skeleton.get_bone_parent(index)
	return result


static func _basis_with_y(direction: Vector3, hint: Vector3) -> Basis:
	var y := direction.normalized()
	if y.length_squared() < 0.5:
		return Basis.IDENTITY
	var z := hint - y * hint.dot(y)
	if z.length_squared() < 0.000001:
		z = Vector3.FORWARD - y * Vector3.FORWARD.dot(y)
	if z.length_squared() < 0.000001:
		z = Vector3.RIGHT - y * Vector3.RIGHT.dot(y)
	z = z.normalized()
	return Basis(y.cross(z), y, z)


func _find_bones(skeleton: Skeleton3D) -> bool:
	for key in BONES:
		var index := CharacterRig.find_bone(skeleton, StringName(BONES[key]))
		if index < 0:
			_bones.clear()
			return false
		_bones[key] = index
	return true
