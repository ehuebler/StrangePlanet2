class_name WeaponPose
extends SkeletonModifier3D

## Poses the arms around whatever the character is holding, on top of whatever the
## AnimationPlayer is playing.
##
## The locomotion clips are full-body, so a hold cannot be a clip of its own
## without authoring one per weapon per gait. The arms are solved here instead,
## after the animation has been applied: each hold gives a target for both hands
## relative to the sternum, a two-link solve puts the elbows somewhere plausible,
## and the weapon is aimed along the line through both hands.
##
## That last part is what keeps a two-handed grip honest. The support hand is on
## the weapon by construction rather than by an angle that has to be re-tuned
## whenever a pose moves, and a swing is then just the two targets travelling: the
## blade follows because it is defined by them.
##
## Arm lengths come off the rig, so re-proportioning the character in Blender needs
## no numbers changed here.

const HOLD_NONE := ""
const HOLD_BLADE := "blade"
const HOLD_RIFLE := "rifle"

## Sternum-space targets: +X the character's right, +Y up, -Z the way it faces,
## origin at the base of the neck. On this 1.45 m character an arm reaches about
## 0.385 m from its shoulder, and the solve clamps anything further.
##
## `aim_from_support` says which way the weapon lies along the line through the
## hands: a sword's blade continues up past the leading hand, a rifle's barrel
## continues forward past the supporting one. `up_hint` rolls the weapon about that
## line — the sword's flat and the rifle's sight rail.
const HOLDS := {
	## Held off the character's right with the support hand reaching across for it,
	## which is as far right as an arm this length will go: the support hand is the
	## one that runs out of reach, not the hand holding the sword.
	"blade": {
		"main": Vector3(0.145, 0.055, -0.175),
		"support": Vector3(0.12, -0.07, -0.165),
		"aim_from_support": true,
		"up_hint": Vector3.BACK,
		"twist": 0.13,
	},
	## Both hands sit close to the middle of the chest, because the barrel runs
	## through them: holding the grip out by the right pec would leave the carbine
	## aiming across the character rather than in front of it.
	## The twist is doing two jobs: it turns the chest away the way a shooter's does,
	## and because the targets ride the chest it also steers the barrel. Each pose's
	## twist is set to leave the carbine pointing where the character faces, which is
	## the `cant` dev/_weapon_test.gd measures.
	"rifle": {
		"main": Vector3(0.065, -0.10, -0.12),
		"support": Vector3(0.015, -0.085, -0.30),
		"aim_from_support": false,
		"up_hint": Vector3.UP,
		"twist": -0.24,
	},
	## Brought up to the eye, as far as arms this short will bring it. The trigger
	## hand comes back almost to the shoulder rather than staying out in front,
	## which is the only way to keep the hands a carbine's width apart while the
	## support hand is already at the end of its reach.
	"rifle_aimed": {
		"main": Vector3(0.05, 0.255, -0.05),
		"support": Vector3(0.02, 0.24, -0.235),
		"aim_from_support": false,
		"up_hint": Vector3.UP,
		"twist": -0.15,
	},
}

## How much of the player's look angle each hold takes on. A carbine has to follow
## it or a shot aimed up leaves a level barrel; a sword only leans with it.
const PITCH_FOLLOW := {
	"blade": 0.25,
	"rifle": 1.0,
}

## A cut from the character's right to its left: wound back over the shoulder,
## driven across the body, then recovered into the hold. Each key is reached at
## `time` seconds; the pose eases out of, and back into, whatever hold is active.
const SWING := [
	{
		"time": 0.10,
		"main": Vector3(0.235, 0.135, -0.02),
		"support": Vector3(0.145, 0.015, -0.03),
		"twist": 0.42,
	},
	{
		"time": 0.24,
		"main": Vector3(-0.075, 0.075, -0.265),
		"support": Vector3(0.075, -0.02, -0.235),
		"twist": -0.34,
	},
	{
		"time": 0.44,
		"main": Vector3(-0.115, -0.06, -0.185),
		"support": Vector3(0.005, -0.11, -0.195),
		"twist": -0.22,
	},
]
const SWING_TIME := 0.62

## Seconds for the arms to take up a hold, and to let it go again.
const RAISE_TIME := 0.16
## How far a shot throws the muzzle up, and how long the arms take to settle.
const KICK_ANGLE := 0.17
const KICK_TIME := 0.22

const BONES := {
	"chest": "Chest",
	"sternum": "UpperChest",
	"main_upper": "RightUpperArm",
	"main_lower": "RightLowerArm",
	"main_hand": "RightHand",
	"support_upper": "LeftUpperArm",
	"support_lower": "LeftLowerArm",
	"support_hand": "LeftHand",
}

## Where the elbows are pushed when the solve has a choice: down and away from the
## body, which is what stops an arm folding through the chest.
const MAIN_POLE := Vector3(0.55, -1.0, 0.15)
const SUPPORT_POLE := Vector3(-0.65, -1.0, 0.1)

var _hold := HOLD_NONE
var _pitch := 0.0
var _aimed := 0.0
var _aim_target := 0.0
var _weight := 0.0
var _swing_elapsed := -1.0
var _kick := 0.0
var _bones: Dictionary = {}


## Takes up `kind`, one of the HOLDS keys, or drops to empty hands with HOLD_NONE.
func hold(kind: String) -> void:
	if kind == _hold:
		return
	_hold = kind
	_swing_elapsed = -1.0
	_kick = 0.0
	if kind == HOLD_NONE:
		_aim_target = 0.0


func held() -> String:
	return _hold


## The player's look angle in radians, positive looking up. The hold is tilted by
## as much of it as PITCH_FOLLOW allows.
func set_pitch(radians: float) -> void:
	_pitch = radians


## Whether the weapon is brought up to the eye. Blended, so it can be held down
## again mid-transition.
func set_aimed(on: bool) -> void:
	_aim_target = 1.0 if on else 0.0


func aim_amount() -> float:
	return _aimed


func swing() -> void:
	_swing_elapsed = 0.0


func swinging() -> bool:
	return _swing_elapsed >= 0.0 and _swing_elapsed < SWING_TIME


## The moment in a swing the blade is travelling fastest, which is when a hit
## would land.
func swing_striking() -> bool:
	return _swing_elapsed >= float(SWING[0]["time"]) and _swing_elapsed < float(SWING[1]["time"])


## Drops transient attack motion while preserving the item held in both hands.
func interrupt_attack() -> void:
	_swing_elapsed = -1.0
	_kick = 0.0
	_aim_target = 0.0


func kick() -> void:
	_kick = 1.0


func _process(delta: float) -> void:
	var raise_rate := delta / RAISE_TIME
	_weight = move_toward(_weight, 1.0 if _hold != HOLD_NONE else 0.0, raise_rate)
	_aimed = move_toward(_aimed, _aim_target, delta / 0.13)
	_kick = maxf(_kick - delta / KICK_TIME, 0.0)
	if _swing_elapsed >= 0.0:
		_swing_elapsed += delta
		if _swing_elapsed >= SWING_TIME:
			_swing_elapsed = -1.0


# Both hooks exist across 4.x; whichever this build calls, the work happens once.
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

	var pose := _resolved()
	var weight := clampf(_weight * influence, 0.0, 1.0)

	# The torso leads: twisting it first carries the shoulders round, and the hand
	# targets with them, because they are given in sternum space.
	_twist(skeleton, _bones["chest"], float(pose["twist"]) * 0.35, weight)
	_twist(skeleton, _bones["sternum"], float(pose["twist"]) * 0.65, weight)

	var chest := _chest_frame(skeleton)
	var main_point: Vector3 = chest * (pose["main"] as Vector3)
	var support_point: Vector3 = chest * (pose["support"] as Vector3)

	var along := main_point - support_point
	if not bool(pose["aim_from_support"]):
		along = -along
	if along.length_squared() < 0.000001:
		along = -chest.basis.z
	var aim := _look_along(along, chest.basis * (pose["up_hint"] as Vector3))
	if _kick > 0.0:
		# A shot throws the muzzle up around the character's own right, so the kick
		# reads the same whichever way it is facing.
		aim = Basis(chest.basis.x, KICK_ANGLE * _kick) * aim

	# Targets say where the hands hold the weapon, so each arm is solved to where
	# its wrist has to be for its grip to land there.
	_arm(skeleton, "main", main_point - _grip_offset(skeleton, _bones["main_hand"], aim),
		chest.basis * MAIN_POLE, aim, weight)
	_arm(skeleton, "support", support_point - _grip_offset(skeleton, _bones["support_hand"], aim),
		chest.basis * SUPPORT_POLE, aim, weight)


## The frame the targets are given in: sitting at the sternum, turned by however
## much the animation has turned the torso, and otherwise square with the
## character.
##
## It cannot just be the sternum bone's own pose. Blender lays a bone's axes out
## along the bone, which on this rig leaves the chest's +X pointing to the
## character's left and its +Z forwards, so targets written in it come out mirrored.
## Dividing the bone's rest out leaves only what the animation added, which is the
## part that should be followed.
func _chest_frame(skeleton: Skeleton3D) -> Transform3D:
	var bone: int = _bones["sternum"]
	var pose := _global_pose(skeleton, bone)
	var basis := pose.basis * _rest_basis(skeleton, bone).inverse()
	# Tilted with the look, about the character's right, so the whole hold pitches
	# together and the weapon keeps lying through both hands.
	var follow := float(PITCH_FOLLOW.get(_hold, 0.0))
	if absf(_pitch * follow) > 0.0001:
		basis = Basis(basis.x.normalized(), _pitch * follow) * basis
	return Transform3D(basis, pose.origin)


## How far a wrist trails the grip it is holding. A weapon sits GRIP_ALONG_HAND of
## the way down the hand bone, and the hand's own direction follows from the aim, so
## this is the same offset Weapons mounts the model with.
func _grip_offset(skeleton: Skeleton3D, hand: int, aim: Basis) -> Vector3:
	var length := skeleton.get_bone_rest(hand).origin.length() * Weapons.GRIP_ALONG_HAND
	return (aim * _rest_basis(skeleton, hand)).y.normalized() * length


## The hold in force this frame: the scoped variant blended in, then overridden by
## a swing in progress.
func _resolved() -> Dictionary:
	var base: Dictionary = HOLDS.get(_hold, HOLDS["blade"])
	var pose := base.duplicate()
	var aimed_key := _hold + "_aimed"
	if _aimed > 0.0 and HOLDS.has(aimed_key):
		var aimed: Dictionary = HOLDS[aimed_key]
		pose["main"] = (base["main"] as Vector3).lerp(aimed["main"], _aimed)
		pose["support"] = (base["support"] as Vector3).lerp(aimed["support"], _aimed)
		pose["twist"] = lerpf(base["twist"], aimed["twist"], _aimed)
	if _swing_elapsed < 0.0:
		return pose

	# Ease out of the hold into the first key, key to key, then back to the hold.
	var from := pose
	var elapsed := _swing_elapsed
	var start := 0.0
	for key_variant in SWING:
		var key: Dictionary = key_variant
		var until := float(key["time"])
		if elapsed <= until:
			return _blend(from, key, smoothstep(0.0, 1.0, (elapsed - start) / maxf(until - start, 0.0001)))
		from = key
		start = until
	return _blend(from, pose, smoothstep(0.0, 1.0, (elapsed - start) / maxf(SWING_TIME - start, 0.0001)))


func _blend(from: Dictionary, to: Dictionary, amount: float) -> Dictionary:
	var pose := from.duplicate()
	pose["main"] = (from["main"] as Vector3).lerp(to["main"], amount)
	pose["support"] = (from["support"] as Vector3).lerp(to["support"], amount)
	pose["twist"] = lerpf(float(from["twist"]), float(to["twist"]), amount)
	# Swing keys carry no aim of their own; the hold's is kept throughout.
	pose["aim_from_support"] = from.get("aim_from_support", to.get("aim_from_support", true))
	pose["up_hint"] = from.get("up_hint", to.get("up_hint", Vector3.UP))
	return pose


## Solves one arm onto `target` and turns its hand so the weapon it carries lands
## on `aim`.
func _arm(skeleton: Skeleton3D, side: String, target: Vector3, pole: Vector3, aim: Basis, weight: float) -> void:
	var upper: int = _bones[side + "_upper"]
	var lower: int = _bones[side + "_lower"]
	var hand: int = _bones[side + "_hand"]
	var shoulder := _global_pose(skeleton, upper).origin
	# Bone lengths are the rest offsets of the joints below them.
	var upper_length: float = skeleton.get_bone_rest(lower).origin.length()
	var lower_length: float = skeleton.get_bone_rest(hand).origin.length()
	var elbow := _elbow(shoulder, target, upper_length, lower_length, pole)

	_aim_bone(skeleton, upper, elbow - shoulder, aim.z, weight)
	_aim_bone(skeleton, lower, target - elbow, aim.z, weight)
	# The mount puts a weapon at the hand with the skeleton's own axes, so giving
	# the hand this rotation relative to its rest is what points the weapon.
	_set_global_basis(skeleton, hand, aim * _rest_basis(skeleton, hand), weight)


## Two-link solve: where the elbow goes for the hand to reach `target`, pushed
## towards `pole` out of the plane it would otherwise be free to spin in.
func _elbow(shoulder: Vector3, target: Vector3, upper: float, lower: float, pole: Vector3) -> Vector3:
	var to_target := target - shoulder
	var reach := to_target.length()
	if reach < 0.0001:
		return shoulder + Vector3.DOWN * upper
	# Kept just inside full extension and just outside the fold, so the arm never
	# locks straight or turns itself inside out.
	var limited := clampf(reach, absf(upper - lower) + 0.005, upper + lower - 0.005)
	var axis := to_target / reach
	var along := (upper * upper - lower * lower + limited * limited) / (2.0 * limited)
	var out := sqrt(maxf(upper * upper - along * along, 0.0))
	var side := pole - axis * pole.dot(axis)
	if side.length_squared() < 0.000001:
		side = Vector3.DOWN - axis * Vector3.DOWN.dot(axis)
	return shoulder + axis * along + side.normalized() * out


func _twist(skeleton: Skeleton3D, bone: int, angle: float, weight: float) -> void:
	if absf(angle) < 0.0001:
		return
	# Added to the animation rather than replacing it, so a walk still swings the
	# shoulders while the torso is turned.
	var turn := Quaternion(Vector3.UP, angle * weight)
	skeleton.set_bone_pose_rotation(bone, skeleton.get_bone_pose_rotation(bone) * turn)


## Turns `bone` so it runs along `direction`, rolled to keep `hint` as its back.
func _aim_bone(skeleton: Skeleton3D, bone: int, direction: Vector3, hint: Vector3, weight: float) -> void:
	_set_global_basis(skeleton, bone, _basis_with_y(direction, hint), weight)


func _set_global_basis(skeleton: Skeleton3D, bone: int, target: Basis, weight: float) -> void:
	var parent := skeleton.get_bone_parent(bone)
	var parent_basis := Basis.IDENTITY if parent < 0 else _global_pose(skeleton, parent).basis
	var local := parent_basis.inverse() * target
	var wanted := Quaternion(local.orthonormalized())
	skeleton.set_bone_pose_rotation(bone, skeleton.get_bone_pose_rotation(bone).slerp(wanted, weight))


## Pose of `bone` in skeleton space, walked from the poses themselves so it picks
## up the bones this pass has already moved.
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


## A basis pointing its -Z along `direction`, which is the way a weapon points.
## Rolls to `up` unless the two have come into line, which a swing can do.
static func _look_along(direction: Vector3, up: Vector3) -> Basis:
	var forward := direction.normalized()
	var roll := up.normalized()
	if absf(forward.dot(roll)) > 0.999:
		roll = _basis_with_y(forward, Vector3.BACK).z
	return Basis.looking_at(forward, roll)


## A basis whose +Y runs along `direction`, since that is the way this rig's bones
## point, rolled so its -Z is as close to `hint` as the direction allows.
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
			push_warning("WeaponPose: %s has no '%s' bone" % [skeleton.name, BONES[key]])
			_bones.clear()
			return false
		_bones[key] = index
	return true
