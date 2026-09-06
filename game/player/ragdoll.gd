class_name Ragdoll
extends PhysicalBoneSimulator3D

## A physics ragdoll built onto the character's own skeleton at run time.
##
## The character is one imported .glb with no physical bones in it, and adding
## them in Blender is not an option: the exporter writes a skeleton and clips,
## not rigid bodies. So the bodies are made here from the rest pose, which also
## means a change to the character's proportions carries through with no second
## table to keep in step.
##
## It is a [SkeletonModifier3D], so it runs after the locomotion clip and after
## [WeaponPose] and overrides both — the same trick the weapon hold uses, for the
## same reason. Idle it costs nothing: [member SkeletonModifier3D.active] is off
## until something goes limp.
##
## It goes limp two ways. [method go_limp] hands the whole body over and is what
## a crash uses; [method take_hit] hands over one limb and leaves the rest
## walking, which is what a knock uses. Everything below is shared between them.
##
## Add it as the *last* child of the skeleton. See [method OnlinePlayer._begin_crash]
## and [method OnlinePlayer._knock_limb] for the callers.

## The bones that get a rigid body, each named with the bone its capsule reaches
## toward. In hierarchy order, and deliberately not every bone in the rig: the
## shoulders, hands and toes are short enough that a body and a joint for each
## buys nothing but three more things for the solver to argue about, and they
## ride along on their parent's pose.
##
## The spine is two segments and not four for the same reason, arrived at the
## hard way. A joint that cannot be held to an angle — see [constant LIMITS] —
## is a joint that will eventually reach any angle, so the only reliable way to
## stop a back folding double is to give it fewer places to fold. `Spine` and
## `UpperChest` therefore get no body and stay where the clip puts them, between
## a physics-driven pelvis and a physics-driven ribcage.
const CHAIN := {
	&"Hips": &"Chest",
	&"Chest": &"Neck",
	&"Neck": &"Head",
	&"Head": &"head_leaf",
	&"LeftUpperArm": &"LeftLowerArm",
	&"LeftLowerArm": &"LeftHand",
	&"RightUpperArm": &"RightLowerArm",
	&"RightLowerArm": &"RightHand",
	&"LeftUpperLeg": &"LeftLowerLeg",
	&"LeftLowerLeg": &"LeftFoot",
	&"LeftFoot": &"LeftToes",
	&"RightUpperLeg": &"RightLowerLeg",
	&"RightLowerLeg": &"RightFoot",
	&"RightFoot": &"RightToes",
}

## Fallback capsule radius per bone, in metres, for a body whose mesh cannot be
## measured — no skin, no vertex weights, or a bone nothing is weighted to.
## [method _measure] is the real source: these are the astronaut's numbers and
## they fit nothing else.
const GIRTH := {
	&"Hips": 0.11, &"Spine": 0.10, &"Chest": 0.10, &"UpperChest": 0.10,
	&"Neck": 0.035, &"Head": 0.085,
	&"LeftUpperArm": 0.045, &"LeftLowerArm": 0.038,
	&"RightUpperArm": 0.045, &"RightLowerArm": 0.038,
	&"LeftUpperLeg": 0.07, &"LeftLowerLeg": 0.055, &"LeftFoot": 0.04,
	&"RightUpperLeg": 0.07, &"RightLowerLeg": 0.055, &"RightFoot": 0.04,
}

## Kilograms per bone, summing to about seventy. What matters is the ratio: a
## head as heavy as a thigh drags the body onto its face every time.
const MASS := {
	&"Hips": 12.0, &"Spine": 8.0, &"Chest": 8.0, &"UpperChest": 8.0,
	&"Neck": 1.5, &"Head": 5.0,
	&"LeftUpperArm": 2.5, &"LeftLowerArm": 1.5,
	&"RightUpperArm": 2.5, &"RightLowerArm": 1.5,
	&"LeftUpperLeg": 7.0, &"LeftLowerLeg": 3.5, &"LeftFoot": 1.0,
	&"RightUpperLeg": 7.0, &"RightLowerLeg": 3.5, &"RightFoot": 1.0,
}

## How far a bone with nothing after it reaches, in metres. Bones in this rig run
## along their own Y, so this is measured up that axis.
const LEAF_SPAN := 0.16

## Which of a bone's own vertices decides how thick its capsule is: 0.5 would be
## the median and hug the mesh, 1.0 the single furthest vertex and be inflated by
## a cuff or a shoulder pad. High enough that most of the limb is inside the
## capsule, low enough that one spike does not set the width.
const GIRTH_PERCENTILE := 0.82
## The stretch of a bone that is measured, as a fraction of its length from root
## to tip. The ends are skipped because that is where limbs flare into their
## joints: a foot read end to end is as thick as the toe box is long, which on
## one of the two characters here came out as a capsule wider than the foot,
## holding the legs apart and the body off the ground.
const GIRTH_BAND := Vector2(0.2, 0.8)
## Bounds on a measured radius, in metres, and the fewest vertices worth reading
## a percentile from. A hand-sized sample says more about which vertices happened
## to be weighted there than about how thick the limb is.
const GIRTH_MIN := 0.02
const GIRTH_MAX := 0.30
const GIRTH_SAMPLE := 12

## Degrees a joint may swing off its parent's line, and twist about it, per bone.
## One span for the whole body is what lets a ragdoll fold into itself: the four
## torso segments each spending 55 degrees is a spine that curls through more
## than two right angles, and a body that can touch its own heels to its neck
## will. The torso is therefore stiff, the neck barely moves, and the slack is
## spent where a limp body really is slack — the shoulders and hips.
##
## These are cones, so they are symmetric: an elbow held to 40 degrees bends 40
## the right way and 40 the wrong way. Stopping the wrong way outright wants a
## hinge, which wants a bend axis per joint and a mirrored one per side, and is
## worth doing only once the folding is gone.
##
## They are a target for [method _hold_joints] and not a rule the engine holds,
## and read the caveat on [constant LIMIT_GAIN] before trusting them. Handing
## these same numbers to a cone-twist joint tears the body apart: over four
## seeded drops a character, every drop came apart, with bones leaving at up to a
## kilometre a second, monotonically worse the tighter the limits were. The same
## bodies on pin joints — nothing for the solver to enforce — held together every
## time and were lying still inside two seconds. The engine's own limit
## correction was the whole of the energy.
const LIMITS := {
	&"Hips": Vector2(20.0, 15.0),
	&"Spine": Vector2(14.0, 10.0),
	&"Chest": Vector2(12.0, 10.0),
	&"UpperChest": Vector2(12.0, 10.0),
	&"Neck": Vector2(22.0, 18.0),
	&"Head": Vector2(25.0, 20.0),
	&"LeftUpperArm": Vector2(70.0, 40.0), &"RightUpperArm": Vector2(70.0, 40.0),
	&"LeftLowerArm": Vector2(45.0, 15.0), &"RightLowerArm": Vector2(45.0, 15.0),
	&"LeftUpperLeg": Vector2(55.0, 25.0), &"RightUpperLeg": Vector2(55.0, 25.0),
	&"LeftLowerLeg": Vector2(40.0, 12.0), &"RightLowerLeg": Vector2(40.0, 12.0),
	&"LeftFoot": Vector2(25.0, 12.0), &"RightFoot": Vector2(25.0, 12.0),
}
const DEFAULT_LIMIT := Vector2(45.0, 25.0)

## How hard a joint past its span is pulled back toward it, in reciprocal
## seconds, and the fastest it may be pulled, in radians a second.
##
## Be clear about what this buys: it is a bias, not a limit. It nudges velocity
## once a tick and the solver is free to spend that nudge on the contacts and the
## joint the same step, so it shades the pose the body settles into and does not
## enforce anything. Measured over four drops a character it moved the worst
## joint by a few degrees, and raising the cap from 5 to 60 changed nothing —
## which is the tell that the ceiling is the mechanism and not the strength.
##
## It stays because it is cheap, bounded and pulls the right way. What it is not
## is the reason the spine no longer folds; that is [constant CHAIN] having two
## torso joints instead of four. Making an angle actually hold wants a constraint
## the solver owns, and the one the engine offers is what the pins replaced.
const LIMIT_GAIN := 9.0
const LIMIT_MAX_RATE := 5.0

## How much of the spin a bone has *relative to the one above it* is bled off per
## second. This is the stiffness. With none of it the body is a puppet with cut
## strings: every limb keeps whatever the impact gave it and windmills. With
## this, a joint resists being moved quickly but not being moved, so the body
## gives way under its own weight and then lies still.
const JOINT_FRICTION := 6.0

## The bones collide with the world and with each other, and never with the
## capsule they came out of.
##
## Self-collision is the whole of what stops an arm lying inside the chest, but
## turned on flat it is also what makes a ragdoll buzz itself across a field:
## neighbouring capsules overlap where they meet, so the solver spends every tick
## pushing two bones apart that a joint is holding together. [method _unlink] is
## the answer — anything already interpenetrating in the rest pose is excused,
## everything else collides — and it is measured rather than listed so it holds
## for a body of any shape.
const BONE_LAYER := 1 << 4
const WORLD_MASK := 1
## Metres of overlap allowed before two capsules are taken to be resting inside
## each other. Slightly generous, because the pose a body is in when it goes limp
## is not the rest pose and a shoulder can close on a chest by a centimetre or so
## without either being wrong.
const REST_SLACK := 0.015

## Radians a second the whole body is thrown tumbling at. A body that leaves a
## collision with pure linear velocity slides rather than tumbles.
##
## One rate about one axis for every bone, not a fresh random spin per bone. The
## chain starts as a single rigid object turning about its own middle, which is a
## motion the joints already agree with; sixteen bodies each spinning a different
## way is sixteen joint violations on the first tick, and the solver answers
## those by throwing the body apart.
const SPIN := 3.0

## Ceilings on how fast a limp bone may move, in m/s and radians a second,
## applied every tick.
##
## This is the backstop rather than the fix. A ragdoll gets its explosions from
## starting inside something — the terrain it just hit, or another bone — and the
## solver answering a deep overlap with whatever impulse clears it in one tick.
## The causes are handled above and below; this is what makes the failure mode a
## limb that moves oddly for a frame instead of a body that leaves the planet.
## Both are far above anything a falling body reaches: a crash slides at 11 m/s
## and gathers about 17 more over the second and a half it is down.
##
## A speed the body was *handed* is the exception, and [method go_limp] raises the
## linear ceiling to it: a blast that launches its victim at seventy metres a
## second is an authored motion and not a solver accident, and clamping it here
## leaves the collider and the camera climbing while the body they belong to
## crawls up behind them. See [member _ceiling] for how the allowance is given
## back.
const MAX_SPEED := 32.0
const MAX_SPIN := 14.0


## Seconds a knocked limb stays loose, and how much of that is spent easing back
## into the clip. Short: this is a flinch, and a limb that hangs about for a
## second reads as an injury the game has no way to end.
const KNOCK_TIME := 0.45
const KNOCK_EASE := 0.25

## How much of the speed driving a bone into the ground comes back out of it.
## Small: a ragdoll that keeps a quarter of what it arrives with reads as a body
## hitting dirt, and one that keeps much more reads as a rubber toy.
const GROUND_BOUNCE := 0.22

## Fastest the ground guard will push a bone back out of itself, in m/s. Its
## purpose is to be quick enough that nothing is ever seen inside the planet and
## slow enough that a bone which starts deep — because the ground moved under it
## while a chunk coarsened — climbs out rather than being fired into orbit.
const ESCAPE_SPEED := 5.0

## Damping, in e-foldings a second, replacing whatever the space provides:
## nothing else in this game uses rigid bodies, so the project's defaults have
## never been tuned and inheriting them is inheriting an accident.
##
## The angular figure is what "limp, with some stiffness" is made of. A body with
## little of it windmills — every limb keeps whatever spin the impact gave it and
## the ragdoll reads as a puppet with cut strings. Heavy angular damping bleeds
## that off within a few tenths of a second, so the body folds under gravity and
## then lies still, which is what a person hitting the ground does.
const LINEAR_DAMP := 0.35
const ANGULAR_DAMP := 7.0

var _bones: Array[PhysicalBone3D] = []
## Bone names in the same order as [member _bones], for the partial simulations
## in [method take_hit], which the engine addresses by name.
var _names: Array[StringName] = []
## Each bone's capsule radius, kept beside it so the ground guard can stop the
## surface of a limb at the ground rather than its axis.
var _girth: PackedFloat32Array = []
## Half each bone's length, for laying its capsule out in world space when the
## pose has to be measured — see [method _live_gap].
var _half: PackedFloat32Array = []
## Bone pairs excused from colliding for the duration of one simulation because
## they were already inside each other when it started. Undone on getting up, so
## the next crash is judged on its own pose.
var _excused: Array[Vector2i] = []
## How far each bone may swing off the one that carries it, in radians, and how
## far off it already is when standing in the rest pose — a limit is measured
## from where the limb rests, not from straight.
var _limit: PackedFloat32Array = []
var _rest_angle: PackedFloat32Array = []
## The bone above each one, as an index into [member _bones], or -1 for the hips.
var _above: PackedInt32Array = []
## Each bone's rest segment in skeleton space, root then tip. Only used while
## building, to work out which capsules already overlap, and kept off the hot
## path afterwards.
var _rest_root: PackedVector3Array = []
var _rest_tip: PackedVector3Array = []
## Skeleton bone id per entry in [member _bones], so [method _downstream] can ask
## the rig what hangs off what instead of keeping a second copy of the hierarchy.
var _ids: PackedInt32Array = []
var _skeleton: Skeleton3D
## Which bones the physics server is currently moving: all of them during a
## crash, one limb during a knock, none at rest.
var _live: PackedInt32Array = []
## Seconds left of a knock, or zero during a crash, which the player times.
var _knock_left := 0.0
## Force per kilogram, set from outside every frame: the world is a sphere, and
## the physics server's own gravity points down the global Y, which is out of the
## ground on exactly one spot of it.
var _pull := Vector3.ZERO
## The ground as a sphere — the planet's centre and the radius the height field
## puts the surface at under the body. Negative means nobody has said, and the
## guard stands down.
var _floor_center := Vector3.ZERO
var _floor_radius := -1.0
## The linear ceiling in force this tick, at or above [constant MAX_SPEED]. A
## launch raises it and it is walked back down at the rate gravity is taking the
## launch away, so the allowance lasts exactly as long as the speed it was granted
## for and the backstop is whole again by the time the body is merely falling.
var _ceiling := MAX_SPEED


func _ready() -> void:
	set_physics_process(false)
	active = false
	var skeleton := get_parent() as Skeleton3D
	if skeleton == null:
		push_warning("ragdoll: has to be a child of a Skeleton3D")
		return
	_skeleton = skeleton
	var measured := _measure(skeleton)
	for bone_name: StringName in CHAIN:
		var id := CharacterRig.find_bone(skeleton, bone_name)
		if id < 0:
			continue
		var actual := StringName(skeleton.get_bone_name(id))
		var girth: float = measured.get(bone_name, GIRTH.get(bone_name, 0.05))
		var bone := _build(skeleton, id, actual, girth)
		if bone == null:
			continue
		bone.mass = float(MASS.get(bone_name, 2.0))
		add_child(bone)
		_bones.append(bone)
		_names.append(actual)
		_ids.append(id)
		_girth.append(girth)
		_half.append(_reach(skeleton, id, bone_name).length() * 0.5)
		_limit.append(deg_to_rad(float(LIMITS.get(bone_name, DEFAULT_LIMIT).x)))
	# Both are second passes, because they are about pairs of bones: every bone
	# has to exist before it can be asked what carries it or which of the others
	# it is already sitting inside. _link runs first — _unlink drops the rest
	# pose that both of them read.
	_link(skeleton)
	_unlink(skeleton)


## Enough of the rig found to be worth using. A character exported without its
## skeleton, or renamed away from the humanoid profile, falls back to the tumble.
func built() -> bool:
	return _bones.size() >= 6


## Something the bones may not collide with: the capsule they came out of,
## chiefly, which would otherwise punt the body across the ground.
func ignore(body: PhysicsBody3D) -> void:
	for bone in _bones:
		bone.add_collision_exception_with(body)


func limp() -> bool:
	return is_simulating_physics()


## Hands the body over to the physics server, thrown at [param carried] and
## spinning. [param pull] is gravity as a vector, which on a sphere only the
## caller knows.
func go_limp(carried: Vector3, pull: Vector3) -> void:
	if not built():
		return
	LagTracker.note_throttled("combat", "ragdoll", "ragdoll go_limp", 0.4)
	# A knock already running is a smaller version of this and gives way to it.
	# Without this the early return below would leave a player who is clipped on
	# the shoulder and then hits a cliff with one loose arm and nothing else.
	if _knock_left > 0.0:
		_release()
	elif limp():
		return
	_pull = pull
	_live = _every()
	_ceiling = maxf(MAX_SPEED, carried.length())
	active = true
	influence = 1.0
	physical_bones_start_simulation()
	# Excused before the first tick, because the pose the body goes limp in is
	# not the pose the permanent exceptions were worked out from.
	_unlink_pose()
	# One rigid tumble: a single spin about the body's middle, with each bone
	# given the velocity that rotation implies where it happens to be standing.
	# Handing every bone the same linear velocity and a different angular one
	# describes no motion at all, and the joints spend the first tick saying so.
	var spin := Vector3(randf_range(-1.0, 1.0), randf_range(-1.0, 1.0),
		randf_range(-1.0, 1.0)).normalized() * randf_range(SPIN * 0.4, SPIN)
	var middle := _middle()
	for bone in _bones:
		bone.linear_velocity = carried + spin.cross(bone.global_position - middle)
		bone.angular_velocity = spin
	set_physics_process(true)


## Knocks one part of the body about while the rest keeps walking: the bone
## nearest [param at] and everything hanging off it go limp, take [param impulse],
## and are eased back into the animation about half a second later. Returns
## whether anything was actually knocked.
##
## This is the difference between clipping a shoulder on a doorway and crashing.
## A crash is the whole body giving up; this is one arm losing an argument, and
## it is the same machinery either way because [PhysicalBoneSimulator3D] takes a
## list of bones and leaves every bone not on it to the clip that is playing.
##
## The bones that are *not* simulated stay in the world as kinematic bodies, so
## the loose arm lands against the chest it belongs to rather than inside it.
func take_hit(at: Vector3, impulse: Vector3, pull: Vector3) -> bool:
	if not built() or limp():
		return false
	var struck := _nearest(at)
	if struck < 0:
		return false
	_pull = pull
	_live = _downstream(struck)
	_ceiling = MAX_SPEED
	var names: Array[StringName] = []
	for index in _live:
		names.append(_names[index])
	active = true
	influence = 1.0
	physical_bones_start_simulation(names)
	_unlink_pose()
	_bones[struck].apply_central_impulse(impulse)
	_knock_left = KNOCK_TIME
	set_physics_process(true)
	return true


func set_pull(pull: Vector3) -> void:
	_pull = pull


## Where the ground is, as the sphere the bones may not sink into. Handed over
## every frame by the caller, because on a planet it is a different sphere at
## every point on the surface and only the player knows which one it is standing
## over. See [method _keep_above_ground] for why the bones need telling at all.
func set_floor(center: Vector3, radius: float) -> void:
	_floor_center = center
	_floor_radius = radius


## Eases the simulated pose back into whatever the clips are playing, over
## [param amount] from 1 to 0, and lets go at the end. Getting up is a movement
## rather than a cut because of this: the skeleton blends the two poses, so the
## body rises out of where it actually landed.
func settle(amount: float) -> void:
	if not limp():
		return
	influence = clampf(amount, 0.0, 1.0)
	if influence <= 0.001:
		stand_up()


func stand_up() -> void:
	if not limp():
		return
	_release()
	_floor_radius = -1.0


func _release() -> void:
	physical_bones_stop_simulation()
	set_physics_process(false)
	active = false
	influence = 1.0
	_knock_left = 0.0
	_ceiling = MAX_SPEED
	_live = PackedInt32Array()
	for pair in _excused:
		_bones[pair.x].remove_collision_exception_with(_bones[pair.y])
		_bones[pair.y].remove_collision_exception_with(_bones[pair.x])
	_excused.clear()


## The same excusing [method _unlink] does at build time, redone against the pose
## the body is actually in as it goes limp, and undone when it gets up.
##
## The rest pose is a T-pose standing still and nothing goes limp from one. A
## crash arrives mid-stride, mid-crouch or mid-fall, with a forearm across the
## chest or a heel drawn up into a thigh — capsules that clear each other
## standing up and are a third of the way inside each other here. Left to
## collide, the solver's first act is to separate them, and the impulse that
## clears a five-centimetre overlap in one tick throws the limb across the field.
func _unlink_pose() -> void:
	for a in _bones.size():
		for b in range(a + 1, _bones.size()):
			if _bones[a].get_collision_exceptions().has(_bones[b]):
				continue
			var reach: float = _girth[a] + _girth[b] - REST_SLACK
			if _live_gap(a, b) >= reach:
				continue
			_bones[a].add_collision_exception_with(_bones[b])
			_bones[b].add_collision_exception_with(_bones[a])
			_excused.append(Vector2i(a, b))


## Closest approach between two bones as they stand right now. A bone's body sits
## at the middle of its capsule with the capsule laid along its own Z, so the
## segment is its position give or take half a length that way.
func _live_gap(a: int, b: int) -> float:
	var a_axis := _bones[a].global_basis.z * _half[a]
	var b_axis := _bones[b].global_basis.z * _half[b]
	var a_at := _bones[a].global_position
	var b_at := _bones[b].global_position
	return _segment_gap(a_at - a_axis, a_at + a_axis, b_at - b_axis, b_at + b_axis)


## Gives the body its joints back: bleeds the spin between each bone and the one
## carrying it, and eases anything bent past its span in [constant LIMITS] back
## toward range.
##
## Both work on velocity rather than force, and both are capped, which is the
## whole reason this is here rather than on the joints. A limit the engine owns
## is answered with whatever impulse clears the violation this tick; a limit
## owned here is answered with at most [constant LIMIT_MAX_RATE], so a bone that
## starts a long way out of range folds back over a few ticks and a bone that
## cannot get back — because it is lying under the rest of the body — simply
## stays there instead of firing the body across the map.
func _hold_joints(delta: float) -> void:
	var bleed := minf(JOINT_FRICTION * delta, 1.0)
	for index in _live:
		var above := _above[index]
		if above < 0:
			continue
		var bone := _bones[index]
		var carrier := _bones[above]
		bone.angular_velocity -= (bone.angular_velocity - carrier.angular_velocity) * bleed
		# A bone runs along the negative Z of its own body; see `body_offset`.
		var axis := -bone.global_basis.z
		var along := -carrier.global_basis.z
		var turn := axis.cross(along)
		var swing := turn.length()
		if swing < 0.0001:
			continue
		var bent := atan2(swing, axis.dot(along)) - _rest_angle[index]
		if bent <= _limit[index]:
			continue
		# Turning about axis x along carries the bone back toward its carrier's
		# line, which is the short way out of range by construction.
		var push := (turn / swing) * minf(
			(bent - _limit[index]) * LIMIT_GAIN, LIMIT_MAX_RATE)
		# Equal and opposite, split by mass: a pin joint leaves relative rotation
		# free, so what has to change is the *relative* spin of the two bones, and
		# pushing only the child leaves the carrier to absorb it.
		var share := carrier.mass / (bone.mass + carrier.mass)
		bone.angular_velocity += push * share
		carrier.angular_velocity -= push * (1.0 - share)


## Where the body actually is, in world space, while it is limp — which is not
## where the capsule it came out of is. The caller wants this to put the camera
## and the collider back over the body; see [method OnlinePlayer._crash_move].
func centre() -> Vector3:
	return _middle()


## How fast the body as a whole is travelling while it is limp, averaged over the
## simulated bones the same way [method centre] averages their positions. The
## caller needs this because the collider it is carrying has no business climbing
## faster than the body it is meant to be following; see
## [method OnlinePlayer._crash_move].
func drift() -> Vector3:
	if _live.is_empty():
		return Vector3.ZERO
	var sum := Vector3.ZERO
	for index in _live:
		sum += _bones[index].linear_velocity
	return sum / float(_live.size())


## Where the body is, as the average of its bones. Good enough for a tumble axis
## and cheaper than a mass-weighted centre nobody would be able to tell apart.
func _middle() -> Vector3:
	var sum := Vector3.ZERO
	for bone in _bones:
		sum += bone.global_position
	return sum / maxf(float(_bones.size()), 1.0)


func _physics_process(delta: float) -> void:
	# Gravity is the only thing that took speed off the launch this tick, so it is
	# the rate the allowance above MAX_SPEED is handed back at.
	_ceiling = move_toward(_ceiling, MAX_SPEED, _pull.length() * delta)
	for index in _live:
		var bone := _bones[index]
		bone.apply_central_impulse(_pull * (bone.mass * delta))
		if _floor_radius > 0.0:
			_keep_above_ground(bone, _girth[index], delta)
		# Last, so it catches the ground guard as well as the solver.
		if bone.linear_velocity.length_squared() > _ceiling * _ceiling:
			bone.linear_velocity = bone.linear_velocity.limit_length(_ceiling)
		if bone.angular_velocity.length_squared() > MAX_SPIN * MAX_SPIN:
			bone.angular_velocity = bone.angular_velocity.limit_length(MAX_SPIN)
	_hold_joints(delta)
	if _knock_left <= 0.0:
		return
	# A knock runs itself out. A full crash does not: the player owns that clock,
	# because getting up has to wait for the body to be on the ground and only
	# the capsule knows whether it is.
	_knock_left -= delta
	if _knock_left <= 0.0:
		stand_up()
	elif _knock_left < KNOCK_EASE:
		influence = _knock_left / KNOCK_EASE


## The same backstop the player's own capsule has, and needed for the same
## reason: the height field knows where the ground is whether or not the chunk
## under it has been given a collider yet, and a crash at flight speed almost
## always happens somewhere the collider budget has not reached. Without this
## the bones sail on through the planet while the capsule stops on top of it,
## which is exactly what a ragdoll clipping through the world looks like.
##
## It works in velocity and never moves a bone. A body teleported out of the
## ground drags its joints with it and the chain snaps taut across the whole
## ragdoll, and the write would be overwritten by the server's own sync in the
## same tick regardless.
func _keep_above_ground(bone: PhysicalBone3D, girth: float, delta: float) -> void:
	var local := bone.global_position - _floor_center
	var span := local.length()
	if span < 1.0:
		return
	var out := local / span
	var under := _floor_radius + girth - span
	if under <= 0.0:
		return
	var carried := bone.linear_velocity
	var into := carried.dot(out)
	if into < 0.0:
		# What was driving the bone into the ground comes back out, less most of
		# itself. What it had along the surface is untouched, so a body still
		# travelling slides and rolls rather than stopping dead where it landed.
		carried -= out * (into * (1.0 + GROUND_BOUNCE))
	# Brought *up to* the escape speed rather than given it on top of whatever it
	# already had. Added blindly it is free upward speed for every bone the
	# surface reads as grazed, which on a body that has just been launched off the
	# ground is most of them — the whole ragdoll then outclimbs the capsule that
	# was handed the same launch, and the character ends up above its own camera.
	var escape := minf(under / delta, ESCAPE_SPEED)
	var leaving := carried.dot(out)
	if leaving < escape:
		carried += out * (escape - leaving)
	bone.linear_velocity = carried


func _build(skeleton: Skeleton3D, id: int, bone_name: StringName,
		girth: float) -> PhysicalBone3D:
	var along := _reach(skeleton, id, bone_name)
	var span := along.length()
	if span < 0.02:
		return null
	var half := span * 0.5
	var rest := skeleton.get_bone_global_rest(id)
	_rest_root.append(rest.origin)
	_rest_tip.append(rest * along)

	var capsule := CapsuleShape3D.new()
	capsule.radius = girth
	capsule.height = maxf(span, girth * 2.0 + 0.01)
	var shape := CollisionShape3D.new()
	shape.shape = capsule
	# A capsule stands along its own Y; a physical bone runs along its -Z. This
	# quarter turn is the whole of the difference between the two conventions.
	shape.basis = Basis(Vector3.RIGHT, -PI * 0.5)

	var bone := PhysicalBone3D.new()
	bone.name = "Bone%s" % bone_name
	# Named before it is parented. A physical bone that enters the tree without
	# one binds itself to bone -1, and the simulator indexes its list with that.
	bone.bone_name = bone_name
	bone.add_child(shape)
	# The body sits at the middle of the bone with -Z pointing along it, and the
	# joint to whatever is above sits back at the bone's own root. Both are
	# expressed relative to the bone, so the rig's proportions carry through.
	var facing := Basis.looking_at(along, _up_hint(along))
	bone.body_offset = Transform3D(facing, facing * Vector3(0.0, 0.0, -half))
	bone.joint_offset = Transform3D(Basis.IDENTITY, Vector3(0.0, 0.0, half))
	# A ball joint: it holds the bone onto the one above and constrains nothing
	# else. Every limit this ragdoll has is applied in _hold_joints, where the
	# correction can be capped. See LIMITS for what the engine's own did.
	bone.joint_type = PhysicalBone3D.JOINT_TYPE_PIN

	bone.mass = float(MASS.get(bone_name, 2.0))
	bone.friction = 0.9
	bone.bounce = GROUND_BOUNCE
	# The space's own gravity points down the global Y, which is out of the ground
	# at one spot on a sphere. It arrives as an impulse along the radius instead;
	# see `_pull`.
	bone.gravity_scale = 0.0
	bone.linear_damp_mode = PhysicalBone3D.DAMP_MODE_REPLACE
	bone.linear_damp = LINEAR_DAMP
	bone.angular_damp_mode = PhysicalBone3D.DAMP_MODE_REPLACE
	bone.angular_damp = ANGULAR_DAMP
	bone.collision_layer = BONE_LAYER
	bone.collision_mask = WORLD_MASK | BONE_LAYER
	# A limb capsule is four centimetres thick and the terrain is a triangle soup
	# with no thickness at all, so a bone falling at thirty metres a second
	# crosses the ground and everything under it inside one tick. Continuous
	# detection is the only thing that catches that, and it is reached through
	# the server because PhysicalBone3D is not a RigidBody3D and does not expose
	# the flag the way one does.
	PhysicsServer3D.body_set_enable_continuous_collision_detection(bone.get_rid(), true)
	return bone


func _every() -> PackedInt32Array:
	var all: PackedInt32Array = []
	for index in _bones.size():
		all.append(index)
	return all


## The bone whose capsule [param at] is nearest to, in world space. Measured to
## the surface rather than to the centre, so a graze along a forearm picks the
## forearm and not the much fatter chest a little further off.
func _nearest(at: Vector3) -> int:
	var best := -1
	var closest := INF
	for index in _bones.size():
		var gap := _bones[index].global_position.distance_to(at) - _girth[index]
		if gap < closest:
			closest = gap
			best = index
	return best


## The struck bone and everything the rig hangs off it. Asked of the skeleton,
## not of [constant CHAIN], because the answer has to include the bones that were
## skipped: a hit to an upper arm should take the hand with it even though no
## hand has a body of its own.
func _downstream(struck: int) -> PackedInt32Array:
	var limb: PackedInt32Array = [struck]
	if _skeleton == null:
		return limb
	for index in _bones.size():
		if index == struck:
			continue
		var walk := _skeleton.get_bone_parent(_ids[index])
		while walk >= 0:
			if walk == _ids[struck]:
				limb.append(index)
				break
			walk = _skeleton.get_bone_parent(walk)
	return limb


## Works out what carries what, and how the two sit at rest, which is everything
## [method _hold_joints] needs to know to police a joint without the engine.
func _link(skeleton: Skeleton3D) -> void:
	for index in _bones.size():
		var carrier := _carrier(skeleton, _names[index])
		_above.append(-1 if carrier.is_empty() else _names.find(carrier))
		var above := _above[index]
		if above < 0:
			_rest_angle.append(0.0)
			continue
		_rest_angle.append((_rest_tip[index] - _rest_root[index]).normalized().angle_to(
			(_rest_tip[above] - _rest_root[above]).normalized()))


## Excuses every pair of capsules that is already inside its neighbour when the
## body is standing in its rest pose, and leaves the rest to collide.
##
## Two bones the solver is holding together cannot also be pushed apart. A
## shoulder capsule reaches into the chest, a neck into both, and the thighs meet
## at the hips; asked to resolve that every tick, the ragdoll shakes itself
## across the ground. The pairs that must not collide are exactly the pairs that
## start overlapping, so they are found by measuring the rest pose rather than
## written down — which is what makes this hold for a mesh nobody has seen yet.
func _unlink(skeleton: Skeleton3D) -> void:
	for a in _bones.size():
		for b in range(a + 1, _bones.size()):
			var reach: float = _girth[a] + _girth[b] - REST_SLACK
			if _segment_gap(_rest_root[a], _rest_tip[a], _rest_root[b], _rest_tip[b]) < reach:
				_bones[a].add_collision_exception_with(_bones[b])
				_bones[b].add_collision_exception_with(_bones[a])
	# Freed rather than kept: it is a couple of hundred bytes that only the pass
	# above ever reads, and leaving it invites a later frame to trust it after
	# the pose has moved on.
	_rest_root = PackedVector3Array()
	_rest_tip = PackedVector3Array()


## Closest approach between two segments. The standard clamped-parameter solve;
## the degenerate arms matter here because a foot bone is a couple of centimetres
## long and rounds to a point.
func _segment_gap(a0: Vector3, a1: Vector3, b0: Vector3, b1: Vector3) -> float:
	var u := a1 - a0
	var v := b1 - b0
	var w := a0 - b0
	var uu := u.dot(u)
	var vv := v.dot(v)
	var uv := u.dot(v)
	var uw := u.dot(w)
	var vw := v.dot(w)
	var denominator := uu * vv - uv * uv
	var s := 0.0
	var t := 0.0
	if denominator > 0.000001:
		s = clampf((uv * vw - vv * uw) / denominator, 0.0, 1.0)
	if vv > 0.000001:
		t = clampf((uv * s + vw) / vv, 0.0, 1.0)
	if uu > 0.000001:
		s = clampf((uv * t - uw) / uu, 0.0, 1.0)
	return (w + u * s - v * t).length()


## How thick each bone's limb actually is, taken from the mesh hanging on the
## skeleton: for every vertex, the bone it is mostly weighted to and how far it
## sits off that bone's axis.
##
## The alternative is the [constant GIRTH] table, and a table is a second copy of
## the character's proportions that nobody remembers to update. Swapping the
## astronaut for the settler already changes every one of these numbers, and the
## point of the ragdoll being built from the rest pose is that a new body needs
## no code — a hand-written girth is the one thing that broke that promise.
##
## Garments are skipped. A cloak would put the collision capsule a foot off the
## arm inside it, and what has to stay out of the chest is the arm.
func _measure(skeleton: Skeleton3D) -> Dictionary:
	var spread := {}
	for instance: MeshInstance3D in skeleton.find_children("*", "MeshInstance3D", true, false):
		if String(instance.name).begins_with(Wardrobe.NODE_PREFIX):
			continue
		_gather(instance, skeleton, spread)

	var measured := {}
	for bone_name: StringName in CHAIN:
		var offsets := PackedFloat32Array(spread.get(bone_name, []))
		if offsets.size() < GIRTH_SAMPLE:
			# Too few vertices to read a width from says more about which ones
			# happened to be weighted here than about the limb.
			measured[bone_name] = float(GIRTH.get(bone_name, 0.05))
			continue
		offsets.sort()
		var at := clampi(int(offsets.size() * GIRTH_PERCENTILE), 0, offsets.size() - 1)
		measured[bone_name] = clampf(offsets[at], GIRTH_MIN, GIRTH_MAX)
	_taper(skeleton, measured)
	return measured


## Holds every bone to the width of the one that carries it, which is the one
## thing that is true of every body: limbs get thinner away from the trunk. A
## forearm is not thicker than an upper arm and a foot is not thicker than a
## shin, whatever the vertices say.
##
## They can say a great deal. One of the two characters here has sixteen hundred
## vertices weighted to each foot — more than to its own thigh, and half of them
## further from the bone than the foot is long — which measures as a beach ball
## on each ankle, holds the legs apart and stands the body off the ground. That
## is a fault in how the mesh was weighted and not something this can fix, but it
## is something this must survive, because the next mesh will have its own.
##
## The head is the exception, and the only one: it is wider than the neck under
## it on every character anyone will ever load.
func _taper(skeleton: Skeleton3D, measured: Dictionary) -> void:
	# CHAIN is in hierarchy order, so a bone's carrier is always already done.
	for bone_name: StringName in CHAIN:
		if bone_name == &"Head":
			continue
		var carrier := _carrier(skeleton, bone_name)
		if carrier.is_empty():
			continue
		measured[bone_name] = minf(measured[bone_name], measured[carrier])


## The nearest bone above this one that has a body of its own, skipping the
## shoulders and the like that [constant CHAIN] leaves out.
func _carrier(skeleton: Skeleton3D, bone_name: StringName) -> StringName:
	var walk := skeleton.get_bone_parent(CharacterRig.find_bone(skeleton, bone_name))
	while walk >= 0:
		var above := CharacterRig.canonical_bone(StringName(skeleton.get_bone_name(walk)))
		if CHAIN.has(above):
			return above
		walk = skeleton.get_bone_parent(walk)
	return &""


## Adds one mesh's vertices to the per-bone spread. Reading the arrays back costs
## a copy of the mesh, which is why this runs once when the body is built and
## never again.
func _gather(instance: MeshInstance3D, skeleton: Skeleton3D, spread: Dictionary) -> void:
	var mesh := instance.mesh as ArrayMesh
	var skin := instance.skin
	if mesh == null or skin == null:
		return
	# A vertex names its bone by position in the skin, not by index in the
	# skeleton, and the two agree only by accident.
	var to_bone: PackedInt32Array = []
	var to_local: Array[Transform3D] = []
	for bind in skin.get_bind_count():
		var id := skin.get_bind_bone(bind)
		if id < 0:
			id = skeleton.find_bone(skin.get_bind_name(bind))
		to_bone.append(id)
		# The bind pose is the inverse of where the bone rests, so it is also the
		# transform that takes a vertex out of the mesh and into that bone.
		to_local.append(skin.get_bind_pose(bind))

	for surface in mesh.get_surface_count():
		# Asked of the format, not of the arrays: an unskinned surface returns
		# null in those slots and null does not assign to a packed array.
		var format := mesh.surface_get_format(surface)
		if not (format & Mesh.ARRAY_FORMAT_BONES and format & Mesh.ARRAY_FORMAT_WEIGHTS):
			continue
		var arrays := mesh.surface_get_arrays(surface)
		var vertices: PackedVector3Array = arrays[Mesh.ARRAY_VERTEX]
		var bones: PackedInt32Array = arrays[Mesh.ARRAY_BONES]
		var weights: PackedFloat32Array = arrays[Mesh.ARRAY_WEIGHTS]
		if vertices.is_empty() or weights.size() != bones.size():
			continue
		var per_vertex := bones.size() / vertices.size()
		if per_vertex < 1:
			continue
		for index in vertices.size():
			var best := -1
			var heaviest := 0.0
			for slot in per_vertex:
				var weight := weights[index * per_vertex + slot]
				if weight > heaviest:
					heaviest = weight
					best = bones[index * per_vertex + slot]
			if best < 0 or best >= to_bone.size():
				continue
			var id := to_bone[best]
			if id < 0:
				continue
			var bone_name := CharacterRig.canonical_bone(StringName(skeleton.get_bone_name(id)))
			if not CHAIN.has(bone_name):
				continue
			var axis := _reach(skeleton, id, bone_name)
			var span := axis.length()
			if span < 0.02:
				continue
			var local := to_local[best] * vertices[index]
			var along := local.dot(axis) / span
			# Only the middle of the bone. Past the ends it is somebody else's
			# limb — a hand is weighted partly to the forearm, and counting it
			# measures the reach to the fingertips as the width of a wrist — and
			# at the ends themselves it is the joint flaring out.
			if along < GIRTH_BAND.x * span or along > GIRTH_BAND.y * span:
				continue
			var key := StringName(bone_name)
			if not spread.has(key):
				# A plain Array, not a packed one: this is appended to per vertex
				# and a packed array in a dictionary is copied on every write.
				spread[key] = [] as Array[float]
			var offsets: Array[float] = spread[key]
			offsets.append((local - axis / span * along).length())


## Which way the bone runs and how far, in its own space. Taken from the named
## next joint rather than from whichever child happens to come first, because the
## hips have three of them and only one of them is the spine.
func _reach(skeleton: Skeleton3D, id: int, bone_name: StringName) -> Vector3:
	var next := StringName(CHAIN.get(CharacterRig.canonical_bone(bone_name), &""))
	if not next.is_empty():
		var child := CharacterRig.find_bone(skeleton, next)
		# Measured through the rest pose rather than off the child's own rest
		# origin, so the next joint named may be a grandchild: the pelvis capsule
		# reaches past `Spine` to `Chest`, and the ribcage past `UpperChest` to
		# `Neck`. Falling back to a stub for those would give the torso two
		# sixteen-centimetre capsules and no back at all.
		if child >= 0:
			return skeleton.get_bone_global_rest(id).affine_inverse() \
				* skeleton.get_bone_global_rest(child).origin
	for child_id in skeleton.get_bone_count():
		if skeleton.get_bone_parent(child_id) == id:
			return skeleton.get_bone_global_rest(id).affine_inverse() \
				* skeleton.get_bone_global_rest(child_id).origin
	return Vector3(0.0, LEAF_SPAN, 0.0)


## Any direction that is not the bone's own. Which one does not matter — the
## capsule is round about its axis — but a parallel hint makes the basis
## degenerate, and the thighs run very nearly straight down.
func _up_hint(along: Vector3) -> Vector3:
	return Vector3.UP if absf(along.normalized().y) < 0.95 else Vector3.RIGHT
