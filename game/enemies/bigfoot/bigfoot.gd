class_name BigfootBoss
extends CharacterBody3D

## Host-authoritative forest boss. Clients present replicated motion, clips, and
## VFX only; every hit and scar is decided on the host (or offline session).

signal health_changed(current: float, maximum: float)
signal engaged_changed(engaged: bool)
signal damaged_flash(strength: float)
signal arena_reset

const GROUP := &"bigfoot_boss"
## What the boss bar calls him, and what a death notice calls him.
const DISPLAY_NAME := "Bigfoot"
const ROAR_WAVE := preload("res://game/enemies/bigfoot/bigfoot_roar_wave.gd")
const ARENA_BOUNDARY := preload(
	"res://game/enemies/bigfoot/bigfoot_arena_boundary.gd")
const RIM_SURFACE := preload(
	"res://game/enemies/bigfoot/bigfoot_surface.tres")
## By path rather than by its global class name, like the shell above it. A
## global name is resolved out of the project-wide class list, which is rebuilt
## by a filesystem scan; a script that reaches for a newly added neighbour before
## that scan has caught up does not fail to find it, it fails to parse, and this
## script failing to parse is the boss missing from the world.
const ROCK := preload("res://game/enemies/bigfoot/bigfoot_rock.gd")

const MAX_HEALTH := 10000.0
## A 400 m diameter gives his fifty-metre sprint room to cross, flank, and
## disappear into cover without the encounter resetting after one long pass.
const ARENA_RADIUS := 200.0
const DETECT_RADIUS := 190.0
## The red line belongs to the encounter, not to Bigfoot's pathfinding. Keep his
## body and most of a meteor shock inside it, then begin bending a sprint home
## early enough that the hard limit is only a last-resort guard.
const ARENA_RUN_MARGIN := 6.0
const ARENA_RUN_RADIUS := ARENA_RADIUS - ARENA_RUN_MARGIN
const ARENA_STEER_BAND := 45.0
## Leaving is a warning, not an instant wipe. If the whole living party stays
## outside for this long the encounter resets; any return clears the countdown.
const RESET_DEBOUNCE := 5.0
const SYNC_INTERVAL := 1.0 / 20.0
## Reference pace for the Walk clip's playback rate, not a speed he travels at.
const WANDER_SPEED := 2.2
## He is never found standing on his own landmark. The arena is his and he is
## crossing it at a jog when you arrive, which is also what makes the waypoint
## read as a territory rather than as a marker pinned to a statue.
const PATROL_SPEED := 11.5
const PATROL_MIN := 16.0
const PATROL_MAX := 42.0
const PATROL_ARRIVED := 3.0
const PATROL_MIN_TURN := 0.9
const PATROL_MAX_TURN := 2.4

## He owns this jungle and crosses it faster than anything on foot should. The
## top speed is what he reaches on a long run through the trees, not what he
## carries into contact: the closing pace is interpolated down to [constant
## CHASE_SPEED] over the last few metres so he arrives able to stop and swing
## rather than sliding past his target every time.
const CHASE_SPEED := 18.0
const SPRINT_SPEED := 50.0
## Far sooner than the old sixty-two-metre ramp. Fifty remains a top speed, not
## a pace he teleports to, but a thirty-metre close is now a sprint rather than
## a jog that ends before it ever gets going.
const SPRINT_AT := 45.0
const CONTACT_AT := 8.0
const GROUND_ACCEL := 80.0
const GROUND_BRAKE := 90.0
const RUN_CLIP_AT := 6.0
## Run is a 0.8 s cycle authored for a heavy jog. Past this the stride is played
## faster, and past the cap it simply reads as speed rather than as a cartoon.
const RUN_CLIP_SPEED := 9.0
const RUN_CLIP_MAX := 2.1

## Three metres of shoulder does not pick its way through undergrowth. Anything
## short enough to walk over goes down as he passes, which is both why the jungle
## reads as his and why he stops snagging on scenery he should be flattening.
##
## The canopy is exempt: he lives under those trees and levelling them over a
## long fight would leave his arena a field. [constant TRAMPLE_TALLEST] sits
## above the shrubs, boulders and small mushrooms and below every authored tree.
##
## The lawn is exempt from the other end. Grass is not what he snags on, a fallen
## blade is not something anyone sees him fell, and there are three hundred
## thousand of them standing within sight of him — sweeping those every stride
## costs more than the rest of the fight put together.
const TRAMPLE_RADIUS := 2.2
const TRAMPLE_SHORTEST := 0.6
const TRAMPLE_TALLEST := 4.0
## Enough to take anything short in a single pass. Deliberately not a small
## number applied often: a ledger accumulates, and cover he half-burns on every
## lap would char the whole arena brown.
const TRAMPLE_DAMAGE := 900.0
## Paced by ground covered rather than by the clock, because ground covered is
## what there is to flatten. What a sweep costs barely depends on how long the
## stretch is — nearly all of it is offering the volume to every plant standing
## near him — so cutting one long corridor is most of a whole second's worth of
## short ones, and standing still costs nothing at all.
const TRAMPLE_STRIDE := 3.5
## Eight a second, whatever he is doing. Only a sprint reaches it, and without it
## fifty metres a second would ask for one every other frame.
const TRAMPLE_MIN_GAP := 0.125
## Longer than the mark can legitimately fall behind him at a full sprint under
## that cap, which makes it the tell that he did not run the distance at all.
const TRAMPLE_MAX_SPAN := 12.0

## What counts as being stopped by something, and how he answers it. Trunks are
## the one thing in his jungle he will not break, so meeting one has to turn into
## going around it rather than into leaning on it until the fight ends.
const BLOCKED_SHARE := 0.45
const BLOCKED_AFTER := 0.2
## Once a trunk has stopped him, keep taking the chosen side long enough to get
## his shoulders past it. Dropping the avoidance as soon as one tangential step
## counted as movement made him turn straight back into a broad trunk.
const OBSTACLE_CLEAR_TIME := 0.45
## Outward lean mixed into the tangent around a wall. Without it he can follow a
## round canopy trunk forever at exactly his own collision radius.
const OBSTACLE_CLEAR_BIAS := 0.65
## Contacts flatter than this are ground, including crater walls he is allowed
## to climb. Only near-vertical faces are obstacles to steer around.
const OBSTACLE_MAX_UP := 0.55
const OBSTACLE_LOOK_MIN := 3.5
const OBSTACLE_LOOK_MAX := 9.0
const OBSTACLE_LOOK_TIME := 0.18
const OBSTACLE_PROBE_HEIGHT := 1.25
const OBSTACLE_PROBE_SIDE := 0.62

## How far the ground he can touch is allowed to sit below the ground the height
## field describes before [method _snap_to_ground] calls it a hole in the world
## and lifts him out of it, in metres.
##
## Chunks are triangulations, so the two disagree by up to the sag of one chord
## across whatever the surface is doing — a quarter of a metre inside his own
## craters, which are the sharpest curve anything digs at the metre and a half
## chunks are built at. This is set well clear of that, because everything it
## exists to catch — a chunk that has no collider yet, a body that has gone
## through one — is metres deep rather than centimetres.
const GROUND_CHORD := 0.6

## Being shot at is what breaks his line. A charge straight up the middle of a
## sustained beam is free damage for the player, so once he is taking hits he
## crosses the open ground in cuts instead — long enough on each side to have to
## be re-aimed at, short enough that he is still arriving.
const UNDER_FIRE_HIT := 0.9
## A beam is one continuous hit rather than a series of them, so it refreshes
## this every tick and keeps him weaving for as long as it is held on him.
const UNDER_FIRE_BEAM := 1.6
const JUKE_MIN := 0.30
const JUKE_MAX := 0.55
## How far off the straight line each cut leans, as a share of it. Past about
## one he stops closing and starts orbiting.
const JUKE_LEAN := 1.05
## Even without a beam on him, the middle of an approach bends across the
## player's view. He still closes — this is a shallow arc, not the full cooldown
## orbit below — but no longer spends the whole encounter shuttling down one
## line through the player and back up it.
const APPROACH_STRAFE_AT := 38.0
const APPROACH_STRAFE_LEAN := 0.55

## After anything lands in melee he runs a fast arc around the target instead of
## reversing down the line he arrived on. The radial correction holds this band
## while the tangent is what reads as a strafe.
const RETREAT_MIN := 3.2
const RETREAT_MAX := 6.0
const ORBIT_RADIUS_MIN := 24.0
const ORBIT_RADIUS_MAX := 36.0
const ORBIT_RADIAL_SPAN := 12.0

## The pressure front is the attack, not a warning that expires before an
## invisible area check. It remains alive until it has crossed the full arena,
## with a short recovery after the outer edge.
const ROAR_DURATION := 2.3
const ROAR_WAVE_START := 0.4
const ROAR_WAVE_END := 2.1
const ROAR_HORIZONTAL := ARENA_RADIUS
const ROAR_ALTITUDE := 260.0
const ROAR_FLIGHTLESS := 10.0
const ROAR_REFLECT := 25.0
const ROAR_COOLDOWN := 9.0
## A true sphere has to reach the diagonal of the authored horizontal / vertical
## eligibility column. Eligibility remains the column; only the visible front
## and its arrival clock use this larger 3D reach.
const ROAR_WAVE_RADIUS := 335.0
const ROAR_WAVE_SPEED := ROAR_WAVE_RADIUS / (
	ROAR_WAVE_END - ROAR_WAVE_START)

const METEOR_WINDUP := 1.6
const METEOR_FLY_SPEED := 120.0
const METEOR_RANGE := 50.0
const METEOR_FLY_MAX := METEOR_RANGE / METEOR_FLY_SPEED
const METEOR_SWEEP_HZ := 20.0
const METEOR_SWEEP_STEP := 1.0 / METEOR_SWEEP_HZ
## The shock drawn off the fist is the hit box, so this one number is both the
## red bow wave the player sees coming and the cylinder it cuts.
const METEOR_FIST_RADIUS := 9.0
const METEOR_FLORA_RADIUS := 5.5
## Plants are cut at half the rate the shock is offered to players. A capsule
## this wide dragged forward in six metre steps crosses each plant it passes two
## or three times over, and testing the same jungle floor again on the next tick
## was most of what a charge through cover cost. Twelve metre steps cut the same
## corridor and the trees still come down behind him as he runs.
const METEOR_FLORA_EVERY := 2
const METEOR_SWEEP_KNOCKBACK := 26.0
## His heaviest blow by a wide margin, and still one a player at full health
## walks away from. Nothing he has may kill outright from full: being killed by
## something is a fight you lost, and being deleted by it is a fight you were
## never in. Every number below is set against [constant PlayerStats.STATS]'s
## hundred-point bar, and `_bigfoot_boss_test` holds them to it.
const METEOR_IMPACT_DAMAGE := 70.0
const METEOR_SWEEP_DAMAGE := 120.0
const METEOR_SPREAD := 26.0
## How much jungle the landing actually uproots. See [method _land_meteor].
## Wider than the hole it digs, because everything standing over that hole has to
## come out of the ground with it.
const METEOR_FLATTEN := 9.0
## What the landing deals to plants, which has nothing to do with what it deals to
## players. Sharing that number left grass — a hundred and fifty odd health, where
## he hits for seventy — scorched but rooted, standing in the air above a crater
## whose floor had just dropped three metres out from under it. Cover is either
## uprooted here or it floats, so this is set high enough to take a full-grown
## tree or an ordinary boulder in the one pass, through the toughness that
## normally makes stone shrug an ability off. The monumental species are exempt
## from ability damage at the source and are unaffected by any number written
## here, which is the right answer for a landmark rooted far below the few metres
## he dug away.
const METEOR_FLATTEN_DAMAGE := 6000.0
## The hole, which is a different thing from the blast. Ground that is dug out
## has to be rebuilt with its collision the same frame — the terrain will not
## leave a player standing on a floor that is no longer there — and the cost of
## that goes up sharply with the radius, because a wider mark is resolved by more
## levels of the quadtree as well as by more chunks at each. At fourteen metres
## every landing cost a quarter-second stall; at this it is one frame. What the
## fight sees is unchanged: the damage, the knockback and the red shock are all
## [constant METEOR_SPREAD] wide and are not this.
const METEOR_CRATER_RADIUS := 8.5
const METEOR_CRATER_DEPTH := 3.4
const METEOR_COOLDOWN := 18.0
const METEOR_MIN_RANGE := 22.0

## Melee is thrown at a moving target, so both swings keep walking in through
## their wind-up and stay live for a window rather than for the single frame the
## clip happens to be on. A one-frame sphere test around the fist is why the grab
## used to close on empty ground.
const MELEE_STEP_SPEED := 20.0
const MELEE_STAND_OFF := 1.9

## The authored clips are deliberately heavy, but their original playback left
## him planted in front of the player for a third to half a second before a hand
## moved. Run the whole melee sequence faster and scale every authored cue by
## the same factor so the hit still agrees with the animated fist.
const MELEE_CLIP_SPEED := 1.75
const PUNCH_CLIP_DURATION := 0.8
const GRAB_CLIP_DURATION := 1.0
const THROW_CLIP_DURATION := 1.2

const PUNCH_DURATION := PUNCH_CLIP_DURATION / MELEE_CLIP_SPEED
const PUNCH_STRIKE := 0.42 / MELEE_CLIP_SPEED
const PUNCH_WINDOW := 0.18
const PUNCH_REACH := 3.4
## What he does while the meteor is cooling: frequent, cheap for him to throw,
## and well under the blow he is waiting to land. Four of them kill.
const PUNCH_DAMAGE := 28.0
## Deliberately under [constant OnlinePlayer.CRASH_SPEED]: this is a shove that
## staggers you and puts ground between you, not a hit that puts you down. The
## throw is the move that ragdolls.
const PUNCH_KNOCKBACK := 15.0
const PUNCH_LIFT := 2.5
const PUNCH_START_RANGE := 4.2
const PUNCH_COOLDOWN := 3.5

const GRAB_DURATION := GRAB_CLIP_DURATION / MELEE_CLIP_SPEED
const GRAB_CONNECT := 0.34 / MELEE_CLIP_SPEED
const GRAB_WINDOW := 0.30
const GRAB_REACH := 3.0
## The grab and the throw it always leads into are read as one attack, so what
## matters is their sum: together they come to about half a meteor. Most of what
## being thrown costs is the ground you lose and the time on your back, not HP.
const GRAB_DAMAGE := 12.0
const GRAB_START_RANGE := 5.5
const GRAB_COOLDOWN := 7.0
## Closing on someone who stepped aside costs him a moment, not the full cycle.
const GRAB_WHIFF_COOLDOWN := 1.8

const THROW_DURATION := THROW_CLIP_DURATION / MELEE_CLIP_SPEED
const THROW_RELEASE := 0.38 / MELEE_CLIP_SPEED
const THROW_DAMAGE := 22.0
const THROW_SPEED := 22.0

## His answer to distance, and to the sky. He tears a stone out of the ground
## mid-stride, plants, throws it and runs on — which is what stops a retreat into
## the trees from being a free reload for whoever he is retreating from, and what
## makes hovering out of reach of everything else a bad plan.
const ROCK_DURATION := 0.85
const ROCK_RELEASE := 0.30
## Above a punch, because it reaches where a punch cannot and knocks you down
## when it arrives; below the meteor, which is the thing he has to close for.
const ROCK_DAMAGE := 38.0
## The stone leaves his hand at this, and gravity is added on top, so the flight
## is lofted rather than flat over anything but the shortest throw.
const ROCK_SPEED := 46.0
## Where they will be by the time it arrives, not where they were when it left.
## Short of one on purpose: a perfectly led throw is unavoidable, and this one
## should be beatable by changing what you were doing.
const ROCK_LEAD := 0.7
const ROCK_KNOCKBACK := 24.0
const ROCK_LIFT := 8.0
## Inside this he has better things to do with his hands.
const ROCK_MIN_RANGE := 11.0
const ROCK_MAX_RANGE := 80.0
const ROCK_COOLDOWN := 5.5

## Death: the collapse clip plays out, then the carcass topples onto the ground
## rather than being left kneeling in the air at the clip's last key.
const DEFEAT_HOLD := 1.1
const DEFEAT_FALL := 1.0
const DEFEAT_PITCH := 1.50
const DEFEAT_LIFT := 0.62

const CLIP_IDLE := "Idle"
const CLIP_WALK := "Walk"
const CLIP_RUN := "Run"
const CLIP_BLEND := 0.12

enum Phase { WANDER, AGGRO, DEFEATED }

@export var mouth_marker: NodePath = ^"Mouth"
@export var right_fist_marker: NodePath = ^"RightFist"
@export var left_fist_marker: NodePath = ^"LeftFist"
@export var grab_marker: NodePath = ^"GrabSocket"

var _health := MAX_HEALTH
var _engaged := false
var _defeated := false
var _target_peer := 0
var _phase := Phase.WANDER

var _spawn_transform := Transform3D.IDENTITY
var _site_direction := Vector3.UP
var _wander_step := 0
var _wander_left := 0.0
var _wander_goal := Vector3.ZERO
var _patrol_angle := 0.0

var _attack := &""
var _attack_left := 0.0
var _attack_sequence := 0
var _attack_fired := false
var _grab_strike_done := false
var _throw_released := false
var _attack_hit_peers: Dictionary = {}
var _cooldowns: Dictionary = {}
var _melee_whiffed := false
## A landed punch makes the next close exchange a grab. Cooldown timing alone
## could never do that: the run into and out of the jungle lasted longer than a
## punch cooldown, so punch was ready first on every return.
var _grab_pending := false

var _roar_elapsed := 0.0
var _roar_radius := 0.0
var _roar_origin := Vector3.ZERO
var _roar_wave_peers: Dictionary = {}

var _meteor_along := Vector3.FORWARD
var _meteor_fist := Vector3.ZERO
## Start of the stretch of jungle not yet cut, and how many sweeps have gone by
## since it was. See [constant METEOR_FLORA_EVERY].
var _meteor_flora_from := Vector3.INF
var _meteor_flora_step := 0
var _meteor_sweep_left := 0.0
var _meteor_landed := false

var _grabbed_peer := 0
## The inverse of Bigfoot's own grab: a player ability is carrying the boss.
var _grappled := false
var _grapple_carrier_peer := 0
var _grapple_carrier: Node3D
var _lassoed := false
var _lasso_source_peer := 0
var _lasso_knockback_left := 0.0
var _arena_empty_left := 0.0

var _ground_speed := 0.0
var _trample_from := Vector3.INF
var _trample_left := 0.0
var _blocked := 0.0
var _blocked_wall := Vector3.ZERO
var _avoid_left := 0.0
var _avoid_side := 1.0
var _under_fire := 0.0
var _juke_left := 0.0
var _juke_side := 1.0
var _retreat_left := 0.0
var _retreat_goal := Vector3.ZERO
var _orbit_side := 1.0
var _orbit_radius := 30.0
var _defeat_elapsed := 0.0
var _defeat_basis := Basis.IDENTITY

var _clip := CLIP_IDLE
var _clip_speed := 1.0
var _clip_seek := -1.0
var _clip_playing := ""

var _animator: AnimationPlayer
var _skeleton: Skeleton3D
var _mouth: Marker3D
var _right_fist: Marker3D
var _left_fist: Marker3D
var _grab_socket: Marker3D
var _meteor_shock: MeteorShock
var _roar_wave: Node3D
var _arena_boundary: MeshInstance3D

## Resolved once. Both of these were being looked up several times a frame: the
## planet by walking the parent chain, the bones by name through the skeleton's
## string table, on a node whose whole job is to run every physics tick.
var _cached_planet: Planet
var _bone_indices: PackedInt32Array = PackedInt32Array()
## Reused rather than allocated: the living-player list is asked for two or three
## times a frame and never outlives the frame it is built in.
var _players_buffer: Array = []

var _sync_left := 0.0
var _sync_sequence := 0
var _last_sync_sequence := 0
var _event_sequence := 0
var _last_event_sequence := 0

var _target_transform := Transform3D.IDENTITY
var _target_velocity := Vector3.ZERO
var _has_target := false
var _extrapolated := 0.0


func _ready() -> void:
	add_to_group(GROUP)
	add_to_group(DamageHit.COMBATANT_GROUP)
	_bind_visuals()
	var site := get_parent()
	if site != null and site.has_method(&"survey_metrics"):
		if site.get(&"direction") is Vector3:
			_site_direction = (site.get("direction") as Vector3).normalized()
	call_deferred(&"_capture_spawn")
	if _is_host():
		_publish_sync(true)
	else:
		_target_transform = global_transform
		_has_target = true


func _capture_spawn() -> void:
	if not is_inside_tree():
		return
	# Every arena reset restores this transform verbatim, so it has to be level
	# with the surface. An authored anchor is; a boss dropped in by a test or a
	# tool is not, and a tilted spawn quietly tilts him again on every wipe.
	_level_to_surface()
	_spawn_transform = global_transform
	var planet := _planet()
	if is_instance_valid(_arena_boundary) and planet != null \
			and planet.shape != null:
		var local_centre := planet.to_local(_spawn_transform.origin)
		if local_centre.length_squared() > 0.5 \
				and _arena_boundary.has_method(&"configure"):
			_arena_boundary.call(
				&"configure", planet, local_centre.normalized(), ARENA_RADIUS)
	# Given somewhere to be from the moment he loads, so nobody ever arrives to
	# find him standing to attention on his own landmark.
	_wander_goal = _pick_wander_goal()
	_wander_left = 5.0


func _level_to_surface() -> void:
	var planet := _planet()
	if planet == null:
		return
	var up := planet.up_at(global_position)
	if not up.is_finite() or up.length_squared() < 0.5:
		return
	var axis := global_basis.y.cross(up)
	if axis.length_squared() < 0.000001:
		return
	global_basis = (Basis(axis.normalized(), global_basis.y.angle_to(up))
		* global_basis).orthonormalized()


func _upright_basis(forward: Vector3, up: Vector3) -> Basis:
	up = up.normalized()
	forward -= up * forward.dot(up)
	if forward.length_squared() < 0.001:
		var hint := Vector3.FORWARD if absf(up.z) < 0.9 else Vector3.RIGHT
		forward = hint - up * hint.dot(up)
	forward = forward.normalized()
	var right := forward.cross(up).normalized()
	return Basis(right, up, right.cross(up).normalized()).orthonormalized()


func _physics_process(delta: float) -> void:
	if _grappled:
		_tick_grappled(delta)
		_update_presentation(delta)
		return
	if _lassoed:
		_update_presentation(delta)
		return
	if _lasso_knockback_left > 0.0 and _is_host():
		_lasso_knockback_left = maxf(_lasso_knockback_left - delta, 0.0)
		var up := _up()
		up_direction = up
		var gravity := float(ProjectSettings.get_setting(
			"physics/3d/default_gravity", 34.0))
		velocity -= up * gravity * delta
		move_and_slide()
		if is_on_floor():
			velocity = velocity.move_toward(Vector3.ZERO, 20.0 * delta)
		_sync_left -= delta
		if _sync_left <= 0.0:
			_sync_left = SYNC_INTERVAL
			_publish_sync(false)
		_update_presentation(delta)
		return
	# Reading bone poses forces the skeleton to resolve, and nothing looks at a
	# fist or a mouth unless he is swinging one or carrying somebody. While he is
	# simply crossing his jungle the markers ride along as ordinary children.
	if not _attack.is_empty() or _grabbed_peer > 0:
		_update_bone_markers()
	if _is_host():
		_host_tick(delta)
		_sync_left -= delta
		if _sync_left <= 0.0:
			_sync_left = SYNC_INTERVAL
			_publish_sync(false)
	else:
		_client_tick(delta)
	_update_presentation(delta)


func _tick_grappled(delta: float) -> void:
	if not is_instance_valid(_grapple_carrier) and _grapple_carrier_peer > 0:
		_grapple_carrier = _player_by_peer(_grapple_carrier_peer) as Node3D
	if is_instance_valid(_grapple_carrier) \
			and _grapple_carrier.has_method(&"grapple_carry_point"):
		grapple_follow(
			_grapple_carrier.call(&"grapple_carry_point"),
			_grapple_carrier.global_basis.y)
	elif _is_host():
		end_grapple(global_position, _up())
	if _is_host():
		_process_cooldowns(delta)
		_sync_left -= delta
		if _sync_left <= 0.0:
			_sync_left = SYNC_INTERVAL
			_publish_sync(false)


func _host_tick(delta: float) -> void:
	_process_cooldowns(delta)
	_under_fire = maxf(_under_fire - delta, 0.0)
	if _defeated:
		# A win is persistent for the session. In particular, do not run the
		# empty-arena reset after the surviving player walks away: that path
		# regrows the trees and corridors, which is only correct after a wipe or
		# an abandoned fight.
		_settle_defeat(delta)
		return
	_update_arena_presence(delta)
	if not _engaged:
		_wander(delta)
		_contain_inside_arena()
		_snap_to_ground()
		_trample(delta)
		return
	var target := _target_player()
	if target == null or arena_distance_to(target) > ARENA_RADIUS:
		if _all_living_players_outside():
			return
		_pick_target()
		target = _target_player()
	if target == null:
		return
	if _attack.is_empty():
		_chase_or_attack(target, delta)
	else:
		_tick_attack(delta, target)
	_contain_inside_arena()
	_snap_to_ground()
	# The meteor cuts its own corridor, wider and on its own clock. Trampling the
	# same ground behind it would be paying for the jungle twice.
	if _attack != &"meteor":
		_trample(delta)


func _client_tick(delta: float) -> void:
	if not _has_target:
		return
	_extrapolated += delta
	var blend := clampf(_extrapolated / SYNC_INTERVAL, 0.0, 1.0)
	global_transform = _target_transform.interpolate_with(global_transform, 1.0 - blend)
	velocity = _target_velocity
	# Smooth the very fast spherical front between 20 Hz authority samples.
	if _attack == &"roar" and _roar_elapsed >= ROAR_WAVE_START \
			and _roar_elapsed <= ROAR_WAVE_END:
		_roar_elapsed = minf(_roar_elapsed + delta, ROAR_WAVE_END)
		_roar_radius = (_roar_elapsed - ROAR_WAVE_START) * ROAR_WAVE_SPEED


func _update_arena_presence(delta: float) -> void:
	var any_inside := false
	var any_detected := false
	for player in _living_players_in_world():
		var distance := arena_distance_to(player)
		if distance <= ARENA_RADIUS:
			any_inside = true
		if distance <= DETECT_RADIUS:
			any_detected = true
	if not _engaged:
		_arena_empty_left = 0.0
		if any_detected:
			_begin_aggro()
		return
	if any_inside:
		_arena_empty_left = 0.0
		return
	_arena_empty_left += delta
	if _arena_empty_left >= RESET_DEBOUNCE:
		_reset_arena()


func _begin_aggro() -> void:
	_engaged = true
	_phase = Phase.AGGRO
	engaged_changed.emit(true)
	_pick_target()


func _reset_arena() -> void:
	_release_grabbed()
	_clear_player_grapple()
	_clear_player_lasso()
	set_arena_boundary_visible(false)
	_attack = &""
	_attack_left = 0.0
	_attack_fired = false
	_grab_strike_done = false
	_throw_released = false
	_attack_hit_peers.clear()
	_cooldowns.clear()
	_roar_elapsed = 0.0
	_roar_radius = 0.0
	_roar_wave_peers.clear()
	_meteor_landed = false
	_grabbed_peer = 0
	_grab_pending = false
	_engaged = false
	_defeated = false
	_defeat_elapsed = 0.0
	_ground_speed = 0.0
	_trample_from = Vector3.INF
	_blocked = 0.0
	_blocked_wall = Vector3.ZERO
	_avoid_left = 0.0
	_under_fire = 0.0
	_juke_left = 0.0
	_retreat_left = 0.0
	_target_peer = 0
	_phase = Phase.WANDER
	_health = MAX_HEALTH
	health_changed.emit(_health, MAX_HEALTH)
	engaged_changed.emit(false)
	global_transform = _spawn_transform
	velocity = Vector3.ZERO
	_wander_step += 1
	_wander_left = 0.0
	_clip = CLIP_IDLE
	_regrow_arena()
	arena_reset.emit()
	_publish_event({"kind": "reset"})
	_publish_sync(true)


## Puts the jungle back the way he found it.
##
## Tied to the arena reset rather than to his death on purpose. Killing him
## leaves the ground as the fight left it — the flattened corridors and the
## crater are what happened here — and it is walking away or dying that winds the
## whole encounter back, him included.
func _regrow_arena() -> void:
	var world := _world()
	if world == null or not world.has_method(&"regrow_flora"):
		return
	world.call(&"regrow_flora", _spawn_transform.origin, ARENA_RADIUS)


func _wander(delta: float) -> void:
	_wander_left -= delta
	if _wander_left <= 0.0 \
			or global_position.distance_to(_wander_goal) < PATROL_ARRIVED:
		_wander_goal = _pick_wander_goal()
		_wander_left = 5.0 + float(_wander_step % 4)
	_travel(_flat_on_surface(_wander_goal - global_position),
		PATROL_SPEED, delta, 3.0)


## The next place in the jungle worth being, walked around the landmark rather
## than measured off his own facing.
##
## A facing-relative turn recomputed on arrival lands back roughly where he is
## standing, so he would reach one goal and then park on it, which is how he
## ended up waiting on the waypoint. Carrying an angle around the arena instead
## means every goal is somewhere he has not just been.
func _pick_wander_goal() -> Vector3:
	_wander_step += 1
	var rng := RandomNumberGenerator.new()
	rng.seed = hash(_wander_step) ^ hash(_site_direction)
	_patrol_angle = wrapf(
		_patrol_angle + rng.randf_range(PATROL_MIN_TURN, PATROL_MAX_TURN),
		0.0, TAU)
	var distance := rng.randf_range(PATROL_MIN, PATROL_MAX)
	var up := _up()
	var east := _tangent_east(up)
	var north := up.cross(east).normalized()
	var offset := (east * cos(_patrol_angle) + north * sin(_patrol_angle)) \
		* distance
	return _clamp_to_arena(_spawn_transform.origin + offset)


func _chase_or_attack(target: Node, delta: float) -> void:
	var dist := _distance_to_player(target)
	# The roar exists to bring fliers down, so it is only ever spent on one.
	# Grounded players never see it, which is what makes taking off a decision.
	if _cooldown_ready(&"roar") and _any_flier_in_arena():
		_start_attack(&"roar")
		return
	if _retreat_left > 0.0:
		_retreat_left -= delta
		if _cooldown_ready(&"meteor") and dist >= METEOR_MIN_RANGE:
			_retreat_left = 0.0
		else:
			# Breaking off is not the same as being done with you. He stops
			# where he is in the undergrowth, throws, and carries on running;
			# the retreat clock is still counting while he does it.
			if _rock_ready(dist, target):
				_start_attack(&"rock")
				return
			_run_cooldown_orbit(target, dist, delta)
			return
	if dist >= METEOR_MIN_RANGE and _cooldown_ready(&"meteor"):
		_start_attack(&"meteor")
		return
	if _rock_ready(dist, target):
		_start_attack(&"rock")
		return
	# A punch explicitly queues the grab that follows it. Cooldowns could not
	# enforce this rhythm by themselves: the trip through the trees was longer
	# than the punch cooldown, so punch won this ordering on every return.
	if _grab_pending and dist <= GRAB_START_RANGE \
			and _cooldown_ready(&"grab"):
		_start_attack(&"grab")
		return
	if dist <= PUNCH_START_RANGE and _cooldown_ready(&"punch"):
		_start_attack(&"punch")
		return
	if dist <= GRAB_START_RANGE and _cooldown_ready(&"grab"):
		_start_attack(&"grab")
		return
	if not _cooldown_ready(&"punch") and not _cooldown_ready(&"grab"):
		# Nothing left to land. Keep crossing the player's view rather than
		# shadow-boxing or reversing down the same line.
		_begin_retreat(target)
		_run_cooldown_orbit(target, dist, delta)
		return
	_travel(_chase_heading(target, dist, delta), _closing_speed(dist), delta,
		6.0)


## The line he actually runs at somebody he is closing on.
##
## A long charge begins straight, bends across the target through its middle,
## and squares up for the last stride. Once he is taking fire that shallow arc
## becomes a hard side-to-side cut, held for a beat before it flips.
func _chase_heading(target: Node, distance: float, delta: float) -> Vector3:
	var straight := _flat_on_surface(
		_combat_position(target) - global_position)
	if distance <= CONTACT_AT or straight.length_squared() < 0.01:
		return straight
	var reach := straight.length()
	var along := straight / reach
	var side := _up().cross(along).normalized()
	if _under_fire <= 0.0:
		if distance > APPROACH_STRAFE_AT:
			return straight
		return (along + side * (_orbit_side * APPROACH_STRAFE_LEAN)) \
			.normalized() * reach
	_juke_left -= delta
	if _juke_left <= 0.0:
		_wander_step += 1
		var rng := RandomNumberGenerator.new()
		rng.seed = hash(_wander_step) ^ hash(_site_direction)
		_juke_left = rng.randf_range(JUKE_MIN, JUKE_MAX)
		_juke_side = -_juke_side
	# Leaned rather than turned: he is still closing, just not along a line
	# anybody can hold something on.
	return (along + side * (_juke_side * JUKE_LEAN)).normalized() * reach


## Whether a stone thrown now is worth throwing: off cooldown, far enough away
## to be worth doing instead of hitting them, and with something other than a
## tree trunk in the way.
func _rock_ready(distance: float, target: Node) -> bool:
	if not _cooldown_ready(&"rock"):
		return false
	if distance < ROCK_MIN_RANGE or distance > ROCK_MAX_RANGE:
		return false
	return _can_see(target)


## Line of sight from the hand that would throw. Only the near cover carries
## collision, so this is a cheap way of not lobbing rocks into the trunk he is
## standing behind.
func _can_see(target: Node) -> bool:
	if target == null:
		return false
	var from := _throw_origin()
	var to := _combat_position(target)
	var query := PhysicsRayQueryParameters3D.create(from, to)
	query.exclude = DamageHit.rid_list(get_rid())
	var blocked := get_world_3d().direct_space_state.intersect_ray(query)
	if blocked.is_empty():
		return true
	var struck: Variant = blocked.get("collider")
	return struck == target


## How fast he wants to be going with that far still to cover. Long stretches
## through the jungle are flat out; the last few metres are walked down to a
## pace he can plant a foot and swing from.
func _closing_speed(distance: float) -> float:
	return lerpf(CHASE_SPEED, SPRINT_SPEED,
		clampf(inverse_lerp(CONTACT_AT, SPRINT_AT, distance), 0.0, 1.0))


func _begin_retreat(target: Node) -> void:
	if _retreat_left > 0.0:
		return
	_wander_step += 1
	var rng := RandomNumberGenerator.new()
	rng.seed = hash(_wander_step) ^ hash(_site_direction)
	_retreat_left = rng.randf_range(RETREAT_MIN, RETREAT_MAX)
	_orbit_radius = rng.randf_range(ORBIT_RADIUS_MIN, ORBIT_RADIUS_MAX)
	_orbit_side = -1.0 if rng.randi_range(0, 1) == 0 else 1.0
	var up := _up()
	var away := _flat_on_surface(global_position - _combat_position(target))
	if away.length_squared() < 0.01:
		away = _flat_on_surface(-global_basis.z)
	if away.length_squared() < 0.01:
		away = _tangent_east(up)
	away = away.normalized()
	var side := up.cross(away).normalized()
	# Kept for snapshots/tests and as a readable first point on the arc; the
	# actual heading below is recomputed around a moving player every frame.
	_retreat_goal = _clamp_to_arena(
		global_position + side * (_orbit_side * _orbit_radius))


## Sprint tangentially around the target while correcting gently toward an
## authored radius. This replaces the old fixed retreat point, which was behind
## him by construction and made the whole fight alternate between one line in
## and the same line back out.
func _run_cooldown_orbit(target: Node, distance: float, delta: float) -> void:
	var away := _flat_on_surface(global_position - _combat_position(target))
	if away.length_squared() < 0.01:
		away = _flat_on_surface(-global_basis.z)
	if away.length_squared() < 0.01:
		away = _tangent_east(_up())
	away = away.normalized()
	var tangent := _up().cross(away).normalized() * _orbit_side
	var radial := clampf(
		(_orbit_radius - distance) / ORBIT_RADIAL_SPAN, -0.75, 0.75)
	var heading := tangent + away * radial

	# An orbit centred on a player near the arena edge can otherwise arc out of
	# the encounter and reset it. Fold the outer third back toward home without
	# changing which side of the player he is crossing.
	var from_home := _flat_on_surface(global_position - _spawn_transform.origin)
	var home_distance := from_home.length()
	var edge_start := ARENA_RADIUS * 0.58
	if home_distance > edge_start and from_home.length_squared() > 0.01:
		var home_share := clampf(inverse_lerp(
			edge_start, ARENA_RADIUS * 0.75, home_distance), 0.0, 1.0)
		heading -= from_home.normalized() * (home_share * 1.4)
	_travel(heading, SPRINT_SPEED, delta, 8.0)


func _clamp_to_arena(point: Vector3) -> Vector3:
	var planet := _planet()
	if planet == null or planet.shape == null:
		return point
	var centre := _spawn_transform.origin
	var offset := _flat_on_surface(point - centre)
	var limit := ARENA_RADIUS * 0.7
	if offset.length() > limit:
		offset = offset.normalized() * limit
	return centre + offset


## Turns a requested run back into the arena before the body reaches the line.
##
## Restricting only authored goals is not enough: chase, juking, obstacle
## avoidance and a player-centred cooldown orbit all create headings every frame.
## The allowed outward component closes gradually through the steering band, so
## he runs an arc along the jungle edge instead of visibly bouncing off a wall.
func _steer_inside_arena(direction: Vector3) -> Vector3:
	var flat := _flat_on_surface(direction)
	var length := flat.length()
	if length < 0.0001:
		return flat
	var distance := _arena_distance_from_home(global_position)
	var steer_start := ARENA_RUN_RADIUS - ARENA_STEER_BAND
	if distance <= steer_start:
		return flat
	var inward := _flat_on_surface(_spawn_transform.origin - global_position)
	if inward.length_squared() < 0.0001:
		return flat
	inward = inward.normalized()
	var along := flat / length
	var share := clampf(inverse_lerp(
		steer_start, ARENA_RUN_RADIUS, distance), 0.0, 1.0)
	# At the start, every heading is legal. At the line, the next stride must
	# point home. Between them, an outward sprint becomes a tangent first.
	var minimum_inward := lerpf(-1.0, 0.65, share)
	if distance >= ARENA_RUN_RADIUS - 0.05:
		minimum_inward = 1.0
	var inward_share := along.dot(inward)
	if inward_share >= minimum_inward:
		return flat
	var tangent := along - inward * inward_share
	if tangent.length_squared() < 0.0001:
		tangent = _up().cross(inward) * _orbit_side
	if tangent.length_squared() < 0.0001:
		tangent = _tangent_east(_up())
	var tangent_share := sqrt(maxf(1.0 - minimum_inward * minimum_inward, 0.0))
	return (inward * minimum_inward
		+ tangent.normalized() * tangent_share).normalized() * length


## Absolute host-side guard for every movement path, including a meteor charge.
##
## Steering should normally make this a sub-metre correction. Keeping the guard
## separate still protects against a low physics frame, collision recovery or a
## future attack that moves without using `_travel`.
func _contain_inside_arena() -> bool:
	var distance := _arena_distance_from_home(global_position)
	if distance <= ARENA_RUN_RADIUS:
		return false
	var planet := _planet()
	if planet != null and planet.shape != null:
		var centre_local := planet.to_local(_spawn_transform.origin)
		var point_local := planet.to_local(global_position)
		if centre_local.length_squared() < 1.0 or point_local.length_squared() < 1.0:
			return false
		var centre_direction := centre_local.normalized()
		var point_direction := point_local.normalized()
		var axis := centre_direction.cross(point_direction)
		if axis.length_squared() < 0.000001:
			axis = _tangent_east(centre_direction)
		var limit_angle := ARENA_RUN_RADIUS / planet.shape.radius
		var clamped_direction := (
			Basis(axis.normalized(), limit_angle) * centre_direction
		).normalized()
		global_position = planet.to_global(
			clamped_direction * point_local.length())
	else:
		var offset := _flat_on_surface(global_position - _spawn_transform.origin)
		if offset.length_squared() < 0.0001:
			return false
		global_position = _spawn_transform.origin \
			+ offset.normalized() * ARENA_RUN_RADIUS
	var outward := _flat_on_surface(global_position - _spawn_transform.origin)
	if outward.length_squared() > 0.0001:
		outward = outward.normalized()
		var outward_speed := velocity.dot(outward)
		if outward_speed > 0.0:
			velocity -= outward * outward_speed
	# Never turn a correction into a synthetic flora-damage corridor.
	_trample_from = global_position
	return true


func _arena_distance_from_home(point: Vector3) -> float:
	var planet := _planet()
	if planet == null or planet.shape == null:
		return _flat_on_surface(point - _spawn_transform.origin).length()
	var centre_local := planet.to_local(_spawn_transform.origin)
	var point_local := planet.to_local(point)
	if centre_local.length_squared() < 1.0 or point_local.length_squared() < 1.0:
		return 0.0
	return centre_local.normalized().angle_to(point_local.normalized()) \
		* planet.shape.radius


func _run_to(goal: Vector3, speed: float, delta: float) -> void:
	_travel(_flat_on_surface(goal - global_position), speed, delta, 6.0)


## Walks the last stride of a swing in without touching the clip: the attack owns
## the animation, this owns only the metres. Planting a foot the instant the
## wind-up starts and swinging at the space a running player has already left is
## what made his melee feel like it was not there.
func _close_on(target: Node, delta: float) -> void:
	if target == null:
		velocity = Vector3.ZERO
		_ground_speed = 0.0
		return
	var to_target := _flat_on_surface(
		_combat_position(target) - global_position)
	var heading := _steer_inside_arena(to_target)
	_face_along(heading, delta, 7.0)
	var gap := to_target.length() - MELEE_STAND_OFF
	if gap <= 0.05:
		velocity = Vector3.ZERO
		_ground_speed = 0.0
		return
	# Never overshoot inside one frame: he should end up in front of the player,
	# not through them.
	_ground_speed = minf(MELEE_STEP_SPEED, gap / maxf(delta, 0.001))
	velocity = heading.normalized() * _ground_speed
	move_and_slide()


## Whether a swing thrown this frame would land on [param target].
##
## Measured from the fist, which is where the clip puts the blow, but against a
## reach rather than a fixed sphere so the test survives the target moving during
## the wind-up.
func _melee_connects(target: Node, reach: float) -> bool:
	if target == null:
		return false
	var from := _right_fist.global_position if _right_fist != null \
		else combat_position()
	return from.distance_to(_combat_position(target)) \
		<= reach + _combat_radius(target)


## One place that turns a wish direction and a wish speed into motion, so every
## behaviour accelerates and brakes on the same ramp instead of teleporting
## between paces the moment a state changes.
func _travel(direction: Vector3, wish_speed: float, delta: float,
		turn_rate: float) -> void:
	var flat := _steer_inside_arena(direction)
	if flat.length_squared() < 0.25:
		wish_speed = 0.0
	var rate := GROUND_ACCEL if wish_speed > _ground_speed else GROUND_BRAKE
	_ground_speed = move_toward(_ground_speed, maxf(wish_speed, 0.0),
		rate * delta)
	if _ground_speed <= 0.05 or flat.length_squared() < 0.0001:
		_ground_speed = 0.0
		velocity = Vector3.ZERO
		_play_clip(CLIP_IDLE)
		move_and_slide()
		return
	var wanted := flat.normalized()
	_avoid_left = maxf(_avoid_left - delta, 0.0)
	_probe_obstacle(wanted)
	if _blocked >= BLOCKED_AFTER and _avoid_left <= 0.0:
		_start_avoidance(wanted)
	var along := _around_obstacle(wanted) if _avoid_left > 0.0 else wanted
	# Avoidance owns which side of a trunk to take, but not permission to take
	# that side through the arena line.
	along = _steer_inside_arena(along).normalized()
	velocity = along * _ground_speed
	_face_along(along, delta, turn_rate)
	if _ground_speed >= RUN_CLIP_AT:
		_play_clip(CLIP_RUN,
			clampf(_ground_speed / RUN_CLIP_SPEED, 1.0, RUN_CLIP_MAX))
	else:
		_play_clip(CLIP_WALK,
			clampf(_ground_speed / WANDER_SPEED, 0.6, 1.8))
	var was := global_position
	move_and_slide()
	_note_progress(was, delta, wanted)


## Notices that he is pushing against something instead of travelling.
##
## The undergrowth he flattens stops mattering the moment it breaks, but a trunk
## does not break, and [method move_and_slide] against one will happily grind him
## in place for as long as his goal is on the far side of it.
func _note_progress(was: Vector3, delta: float,
		wanted := Vector3.ZERO) -> void:
	if _ground_speed < 1.0:
		_blocked = 0.0
		return
	if wanted.length_squared() > 0.0001:
		wanted = _flat_on_surface(wanted).normalized()
	_remember_obstacle(wanted)
	var moved := _flat_on_surface(global_position - was)
	var progress := moved.dot(wanted) if wanted.length_squared() > 0.0001 \
		else moved.length()
	if progress >= _ground_speed * delta * BLOCKED_SHARE:
		_blocked = maxf(_blocked - delta * 2.0, 0.0)
		return
	_blocked += delta


## Looks a stride ahead with a narrow three-ray shoulder fan. Post-contact
## steering is still the fallback, but at sprint speed waiting until his capsule
## is already wrapped around a broad trunk gives the solver almost no useful
## direction to recover in.
func _probe_obstacle(wanted: Vector3) -> void:
	if wanted.length_squared() < 0.0001 or not is_inside_tree():
		return
	var space := get_world_3d().direct_space_state
	if space == null:
		return
	var up := _up()
	var side := up.cross(wanted).normalized()
	var look := clampf(
		_ground_speed * OBSTACLE_LOOK_TIME,
		OBSTACLE_LOOK_MIN, OBSTACLE_LOOK_MAX)
	var best_facing := 0.15
	var best_wall := Vector3.ZERO
	for lane: float in [-OBSTACLE_PROBE_SIDE, 0.0, OBSTACLE_PROBE_SIDE]:
		var from: Vector3 = global_position \
			+ up * OBSTACLE_PROBE_HEIGHT + side * lane
		var query := PhysicsRayQueryParameters3D.create(from, from + wanted * look)
		query.exclude = DamageHit.rid_list(get_rid())
		query.collision_mask = collision_mask
		var result := space.intersect_ray(query)
		if result.is_empty():
			continue
		var collider := result.get("collider") as Node
		if collider != null and collider.is_in_group(DamageHit.COMBATANT_GROUP):
			continue
		if _probe_hit_is_breakable_cover(result):
			continue
		var raw: Vector3 = result.get("normal", Vector3.ZERO)
		if raw.dot(up) > OBSTACLE_MAX_UP:
			continue
		var wall := _flat_on_surface(raw)
		if wall.length_squared() < 0.0001:
			continue
		wall = wall.normalized()
		var facing := wanted.dot(-wall)
		if facing > best_facing:
			best_facing = facing
			best_wall = wall
	if best_wall == Vector3.ZERO:
		return
	_blocked_wall = best_wall
	_blocked = maxf(_blocked, BLOCKED_AFTER)
	if _avoid_left <= 0.0:
		_start_avoidance(wanted)


## Low breakable cover is not an obstacle: `_trample` removes it behind the
## stride. Canopy trunks carry the same metadata at a height above the trample
## band and therefore remain a thing to route around.
func _probe_hit_is_breakable_cover(result: Dictionary) -> bool:
	var body := result.get("collider") as CollisionObject3D
	if body == null:
		return false
	var shape_index := int(result.get("shape", -1))
	if shape_index < 0:
		return false
	var owner_id := body.shape_find_owner(shape_index)
	if owner_id < 0:
		return false
	var shape := body.shape_owner_get_owner(owner_id) as CollisionShape3D
	if shape == null or shape.get_meta(&"impact_break_owner", null) == null:
		return false
	var height := float(shape.get_meta(&"impact_break_height", INF))
	return height >= TRAMPLE_SHORTEST and height <= TRAMPLE_TALLEST


## Remembers the near-vertical face this move met. Measuring the displacement in
## the desired direction above matters for round trunks: sliding sideways along
## one is motion, but it is not progress toward anything and must not clear the
## blocked clock.
func _remember_obstacle(wanted: Vector3) -> void:
	var facing := -0.2
	var wall := Vector3.ZERO
	var up := _up()
	for index in get_slide_collision_count():
		var raw := get_slide_collision(index).get_normal()
		if raw.dot(up) > OBSTACLE_MAX_UP:
			continue
		var normal := _flat_on_surface(raw)
		if normal.length_squared() < 0.0001:
			continue
		normal = normal.normalized()
		var head_on := wanted.dot(-normal) \
			if wanted.length_squared() > 0.0001 else 0.0
		if head_on > facing:
			facing = head_on
			wall = normal
	if wall != Vector3.ZERO:
		_blocked_wall = wall


func _start_avoidance(wanted: Vector3) -> void:
	_avoid_left = OBSTACLE_CLEAR_TIME
	if _blocked_wall.length_squared() < 0.0001:
		return
	var side := _up().cross(_blocked_wall).normalized()
	var favoured := side.dot(wanted)
	if absf(favoured) > 0.15:
		_avoid_side = 1.0 if favoured > 0.0 else -1.0
	else:
		# Square-on has no geometrically preferred side. Alternate if the same
		# obstacle earns a second attempt instead of repeating a failed one.
		_avoid_side = -_avoid_side


## The way past whatever he has run into: along its face rather than through it.
##
## Taken from the contact he is most squarely against, turned a quarter turn to
## the side his heading already favours, and leaned slightly off the surface so
## he peels away from it instead of tracking along it forever.
func _around_obstacle(along: Vector3) -> Vector3:
	if _blocked_wall.length_squared() < 0.0001:
		return along
	var wall := _blocked_wall.normalized()
	var side := _up().cross(wall).normalized() * _avoid_side
	return (side + wall * OBSTACLE_CLEAR_BIAS).normalized()


## Flattens the stretch of undergrowth he has just crossed.
##
## Rate limited and measured between marks rather than run every frame, so what
## it costs depends on how much ground he covered and not on how often it was
## asked — the same arrangement the meteor charge cuts its corridor with.
func _trample(delta: float) -> void:
	_trample_left -= delta
	if _trample_left > 0.0:
		return
	var at := global_position
	if not _trample_from.is_finite():
		_trample_from = at
		return
	var span := _trample_from.distance_to(at)
	if span < TRAMPLE_STRIDE:
		return
	# Further than running could have carried him: a meteor flight, or the reset
	# putting him back at his waypoint. The mark moves up without a sweep rather
	# than cutting a corridor across ground he was never on.
	if span > TRAMPLE_MAX_SPAN:
		_trample_from = at
		return
	_trample_left = TRAMPLE_MIN_GAP
	var up := _up()
	var hit := DamageHit.beam(_trample_from + up * 0.5, at + up * 0.5,
		TRAMPLE_RADIUS, TRAMPLE_DAMAGE)
	hit.faction = DamageHit.Faction.ENEMY
	hit.min_plant_height = TRAMPLE_SHORTEST
	hit.max_plant_height = TRAMPLE_TALLEST
	hit.ability_id = "bigfoot_trample"
	hit.set_source(self)
	DamageHit.apply_to_fields(self, hit)
	_trample_from = at


func _start_attack(id: StringName) -> void:
	_attack = id
	_attack_sequence += 1
	_attack_left = _attack_duration(id)
	_attack_fired = false
	_grab_strike_done = false
	_throw_released = false
	_melee_whiffed = false
	_attack_hit_peers.clear()
	_meteor_landed = false
	_meteor_sweep_left = METEOR_SWEEP_STEP
	_meteor_flora_from = Vector3.INF
	_meteor_flora_step = 0
	_roar_elapsed = 0.0
	_roar_radius = 0.0
	_roar_wave_peers.clear()
	_ground_speed = 0.0
	match id:
		&"roar":
			_play_clip("Roar")
			_roar_origin = _mouth.global_position
			_publish_event({"kind": "roar_start", "at": _roar_origin})
		&"meteor":
			_play_clip("MeteorWindup")
			_meteor_along = _steer_inside_arena(_flat_on_surface(
				_target_player().global_position - global_position))
			if _meteor_along.length_squared() < 0.01:
				_meteor_along = -global_basis.z
			_meteor_along = _meteor_along.normalized()
			_face_along(_meteor_along, 0.0, 999.0)
		&"punch":
			_play_clip("Punch", MELEE_CLIP_SPEED)
		&"grab":
			_grab_pending = false
			_play_clip("Grab", MELEE_CLIP_SPEED)
		&"throw":
			_play_clip("Throw", MELEE_CLIP_SPEED)
		&"rock":
			# The same overhand the grab throw ends on, hurried: this is one
			# stride's pause in the middle of a run, not a set piece.
			_play_clip("Throw", THROW_CLIP_DURATION / ROCK_DURATION)
	_publish_event({"kind": "attack_start", "attack": String(id),
		"sequence": _attack_sequence})


func _attack_duration(id: StringName) -> float:
	match id:
		&"roar":
			return ROAR_DURATION
		&"meteor":
			return METEOR_WINDUP + METEOR_FLY_MAX + 1.2
		&"punch":
			return PUNCH_DURATION
		&"grab":
			return GRAB_DURATION + THROW_DURATION
		&"throw":
			return THROW_DURATION
		&"rock":
			return ROCK_DURATION
	return 1.0


func _tick_attack(delta: float, target: Node) -> void:
	_attack_left -= delta
	match _attack:
		&"roar":
			_tick_roar(delta)
		&"meteor":
			_tick_meteor(delta, target)
		&"punch":
			_tick_punch(delta, target)
		&"grab":
			_tick_grab_throw(delta, target)
		&"rock":
			_tick_rock(delta, target)
	if _attack_left <= 0.0:
		_finish_attack()


func _finish_attack() -> void:
	if _attack == &"grab" and _grabbed_peer > 0:
		_release_grabbed()
	match _attack:
		&"roar":
			_cooldowns[&"roar"] = ROAR_COOLDOWN
			if is_instance_valid(_roar_wave) and _roar_wave.has_method(&"clear"):
				_roar_wave.call(&"clear")
			_publish_event({"kind": "roar_end"})
		&"meteor":
			_cooldowns[&"meteor"] = METEOR_COOLDOWN
			if is_instance_valid(_meteor_shock):
				_meteor_shock.stop()
		&"punch":
			_cooldowns[&"punch"] = PUNCH_COOLDOWN
			# Cover is what you break for after landing something. Swinging at
			# air and then jogging off would just look like he gave up.
			if not _melee_whiffed:
				_begin_retreat(_target_player())
		&"grab":
			_cooldowns[&"grab"] = GRAB_WHIFF_COOLDOWN if _melee_whiffed \
				else GRAB_COOLDOWN
			if _melee_whiffed:
				_grab_pending = true
			if not _melee_whiffed:
				_begin_retreat(_target_player())
		&"rock":
			_cooldowns[&"rock"] = ROCK_COOLDOWN
	_attack = &""
	_attack_fired = false
	_grab_strike_done = false
	_throw_released = false
	_melee_whiffed = false
	_attack_hit_peers.clear()
	velocity = Vector3.ZERO
	_ground_speed = 0.0


func _peer_id(player: Node) -> int:
	if player == null:
		return 0
	if player.has_method(&"combat_peer_id"):
		return int(player.call(&"combat_peer_id"))
	return int(player.get("peer_id"))


func _combat_position(player: Node) -> Vector3:
	if player == null:
		return Vector3.ZERO
	if player.has_method(&"combat_position"):
		return player.call(&"combat_position")
	return player.global_position


func _combat_radius(player: Node) -> float:
	if player == null:
		return 0.4
	if player.has_method(&"combat_radius"):
		return float(player.call(&"combat_radius"))
	return 0.4


func _player_is_grabbed(player: Node) -> bool:
	return player != null and player.has_method(&"is_grabbed") \
		and bool(player.call(&"is_grabbed"))


func _player_is_dead(player: Node) -> bool:
	return player != null and player.has_method(&"is_dead") \
		and bool(player.call(&"is_dead"))


func _player_is_flying(player: Node) -> bool:
	return player != null and player.has_method(&"stance") \
		and int(player.call(&"stance")) == OnlinePlayer.Stance.FLY


## Whether anyone in the arena is currently airborne. In co-op this is the whole
## party, not just his current target: the roar is an answer to the sky, and one
## flier circling overhead is enough reason to use it.
func _any_flier_in_arena() -> bool:
	for player in _living_players_in_world():
		if _player_is_flying(player) and _roar_eligible(player):
			return true
	return false


func _player_grab_at_socket(player: Node, socket: Node3D) -> bool:
	if player == null or socket == null or not player.has_method(&"grab_at_socket"):
		return false
	# Put the player's combat centre in his hand while preserving the player's
	# current orientation at the instant of capture. Identity put their feet on
	# the socket, so even a successful grab looked like a near miss with a body
	# dangling a full torso below the animated hand.
	var held := (player as Node3D).global_transform if player is Node3D \
		else Transform3D.IDENTITY
	held.origin += socket.global_position - _combat_position(player)
	var offset := socket.global_transform.affine_inverse() * held
	return bool(player.call(&"grab_at_socket", socket, offset))


func _player_release_grab(player: Node, throw_velocity := Vector3.ZERO) -> void:
	if player != null and player.has_method(&"release_grab"):
		player.call(&"release_grab", throw_velocity)


func _tick_roar(delta: float) -> void:
	velocity = Vector3.ZERO
	_face_along(-global_basis.z, delta, 2.0)
	_roar_elapsed += delta
	if _roar_elapsed < ROAR_WAVE_START:
		_roar_radius = 0.0
		return
	if _roar_elapsed <= ROAR_WAVE_END:
		_roar_radius = (_roar_elapsed - ROAR_WAVE_START) * ROAR_WAVE_SPEED
		_roar_origin = _mouth.global_position if _mouth != null \
			else combat_position()
		# Copied: applying a hit can kill somebody, and the shared buffer this
		# comes out of is refilled by anything that asks who is still alive.
		for player in _living_players_in_world().duplicate():
			var peer := _peer_id(player)
			if _roar_wave_peers.has(peer):
				continue
			if not _roar_eligible(player):
				continue
			var point := _combat_position(player)
			var reach := _roar_radius + _combat_radius(player)
			if point.distance_to(_roar_origin) > reach:
				continue
			_roar_wave_peers[peer] = true
			_apply_roar_to_player(player)
		return
	_roar_radius = ROAR_WAVE_RADIUS


func _roar_eligible(player: Node) -> bool:
	if arena_distance_to(player) > ROAR_HORIZONTAL:
		return false
	return _altitude_of(player) <= ROAR_ALTITUDE


func _apply_roar_to_player(player: Node) -> void:
	var hit := DamageHit.impact(_combat_position(player), 1.0, 0.0)
	hit.faction = DamageHit.Faction.ENEMY
	hit.target_peer = _peer_id(player)
	hit.parryable = true
	hit.reflection = ROAR_REFLECT
	hit.status = CombatStatuses.FLIGHTLESS
	hit.status_duration = ROAR_FLIGHTLESS
	hit.reaction = DamageHit.Reaction.RAGDOLL \
		if player.has_method(&"stance") \
		and int(player.call(&"stance")) == OnlinePlayer.Stance.FLY \
		else DamageHit.Reaction.NONE
	hit.ability_id = "bigfoot_roar"
	hit.set_source(self)
	_apply_player_hit(player, hit)


func _tick_meteor(delta: float, target: Node) -> void:
	var elapsed := _attack_duration(&"meteor") - _attack_left
	if elapsed < METEOR_WINDUP:
		velocity = Vector3.ZERO
		_face_along(_meteor_along, delta, 5.0)
		return
	if not _meteor_landed:
		if elapsed < METEOR_WINDUP + 0.05:
			_play_clip("MeteorFly")
			_meteor_fist = _right_fist.global_position
			_meteor_flora_from = _meteor_fist
		velocity = _meteor_along * METEOR_FLY_SPEED
		_face_along(_meteor_along, delta, 8.0)
		move_and_slide()
		var reached_edge := _contain_inside_arena()
		if reached_edge:
			# The fist markers are driven manually from the skeleton and must
			# follow the corrected body before the final sweep and impact.
			_update_bone_markers()
		_meteor_sweep_left -= delta
		if _meteor_sweep_left <= 0.0:
			_meteor_sweep_left = METEOR_SWEEP_STEP
			_sweep_meteor_fist()
		var fly_time := elapsed - METEOR_WINDUP
		if reached_edge or fly_time >= METEOR_FLY_MAX or _meteor_hit_terrain() \
				or _flat_on_surface(
				target.global_position - global_position).length() < 2.5:
			_land_meteor(target)
		return
	velocity = Vector3.ZERO


func _sweep_meteor_fist() -> void:
	var fist := _right_fist.global_position
	var tick_damage := METEOR_SWEEP_DAMAGE * METEOR_SWEEP_STEP
	for player in _living_players_in_world().duplicate():
		var peer := _peer_id(player)
		if _attack_hit_peers.has(peer):
			continue
		var point := _combat_position(player)
		var beam := DamageHit.beam(_meteor_fist, fist, METEOR_FIST_RADIUS, tick_damage)
		if not beam.reaches(point, _combat_radius(player)):
			continue
		_attack_hit_peers[peer] = true
		beam.faction = DamageHit.Faction.ENEMY
		beam.target_peer = peer
		beam.parryable = true
		# Anything the red shock sweeps through is thrown clear of it, so the
		# visible bow wave is a thing that happens to you and not a decoration.
		beam.reaction = DamageHit.Reaction.KNOCKBACK
		beam.world_impulse = _meteor_along * METEOR_SWEEP_KNOCKBACK \
			+ _up() * 7.0
		beam.ability_id = "bigfoot_meteor"
		beam.set_source(self)
		_apply_player_hit(player, beam)
	_meteor_flora_step += 1
	if _meteor_flora_step >= METEOR_FLORA_EVERY:
		_cut_flora(_meteor_flora_from, fist)
		_meteor_flora_from = fist
		_meteor_flora_step = 0
	_meteor_fist = fist


## The jungle along one stretch of the charge. Narrower than the fist's own hit
## box, but categorical inside it: the shock is cutting a corridor rather than
## slowly burning one. Reusing actor damage here only dealt twelve points per
## sampled stretch, leaving even grass rooted over the disturbed ground.
func _cut_flora(from: Vector3, to: Vector3) -> void:
	if not from.is_finite():
		return
	var hit := DamageHit.beam(from, to, METEOR_FLORA_RADIUS,
		METEOR_FLATTEN_DAMAGE)
	hit.faction = DamageHit.Faction.ENEMY
	hit.ability_id = "bigfoot_meteor"
	# One debris burst for every blade in a five-metre corridor costs more than
	# the flight and draws nothing the bow shock is not already covering.
	hit.plant_break_effects = false
	hit.set_source(self)
	DamageHit.apply_to_fields(self, hit)


func _meteor_hit_terrain() -> bool:
	for index in get_slide_collision_count():
		var collision := get_slide_collision(index)
		if collision.get_normal().dot(_meteor_along) < -0.3:
			return true
	return false


func _land_meteor(target: Node) -> void:
	if _meteor_landed:
		return
	_meteor_landed = true
	_play_clip("MeteorImpact")
	var at := _right_fist.global_position
	# Flora runs at half the actor sampling rate. A landing can happen on the
	# odd sample; flush that final stretch instead of abandoning up to twelve
	# metres of the corridor immediately behind the fist.
	if _meteor_flora_from.is_finite() \
			and _meteor_flora_from.distance_squared_to(at) > 0.01:
		_cut_flora(_meteor_flora_from, at)
	_meteor_flora_from = Vector3.INF
	var blow := DamageHit.area(at, METEOR_SPREAD, METEOR_IMPACT_DAMAGE, 1.0)
	blow.faction = DamageHit.Faction.ENEMY
	blow.parryable = true
	blow.reaction = DamageHit.Reaction.KNOCKBACK
	blow.world_impulse = _meteor_along * 30.0 + _up() * 14.0
	blow.ability_id = "bigfoot_meteor"
	blow.set_source(self)
	DamageHit.apply_to_combatants(self, blow)
	# The jungle is flattened over a smaller circle than the party is thrown
	# across. Uprooting everything inside the full spread meant testing, charring
	# and breaking every plant in a twenty-six metre disc of dense cover in the
	# single frame he landed, which measured at 296 ms — the whole of the stall
	# people felt in this fight. What the blast looks like and what it does to a
	# body are unchanged.
	# Flat across the whole circle, and not the tapered share a body takes. A
	# blast that fades towards its edge leaves the rim of the crater ringed with
	# plants that survived by standing a metre further out than the ones that
	# did not — and the ground under that rim is gone too.
	var flatten := DamageHit.area(at, METEOR_FLATTEN, METEOR_FLATTEN_DAMAGE, 0.0)
	flatten.faction = DamageHit.Faction.ENEMY
	flatten.ability_id = "bigfoot_meteor"
	# Seventeen thousand instances go down here, and a burst of fragments for
	# each of them costs twenty-five milliseconds on the one frame in this fight
	# people already feel — to draw torn grass inside an explosion that is
	# covering the same ground with its own.
	flatten.plant_break_effects = false
	flatten.set_source(self)
	DamageHit.apply_to_fields(self, flatten)
	var planet := _planet()
	if planet != null:
		var centre := at
		var scar := TerrainScars.Scar.new()
		scar.direction = planet.to_local(centre).normalized()
		scar.radius = METEOR_CRATER_RADIUS
		scar.depth = METEOR_CRATER_DEPTH
		scar.profile = TerrainScars.Profile.BOWL
		scar.char = 0.35
		scar.tint = Color(0.16, 0.13, 0.11)
		var world := _world()
		if world != null:
			world.request_scar(scar)
	_publish_event({"kind": "meteor_land", "at": at})
	if is_instance_valid(_meteor_shock):
		_meteor_shock.stop()
	_attack_left = minf(_attack_left, 1.2)


func _tick_punch(delta: float, target: Node) -> void:
	var elapsed := PUNCH_DURATION - _attack_left
	if elapsed < PUNCH_STRIKE:
		_close_on(target, delta)
		return
	if _attack_fired:
		velocity = Vector3.ZERO
		_ground_speed = 0.0
		return
	if elapsed > PUNCH_STRIKE + PUNCH_WINDOW:
		velocity = Vector3.ZERO
		_ground_speed = 0.0
		_melee_whiffed = true
		return
	if not _melee_connects(target, PUNCH_REACH):
		# The fist is already moving, so keep the body coming with it through
		# the live window. Freezing at the nominal strike time made a near miss
		# look like he ran up, waited, and only then decided to punch.
		_close_on(target, delta)
		return
	velocity = Vector3.ZERO
	_ground_speed = 0.0
	_attack_fired = true
	_grab_pending = true
	var away := _flat_on_surface(_combat_position(target) - global_position)
	if away.length_squared() < 0.0001:
		away = _flat_on_surface(-global_basis.z)
	var hit := DamageHit.impact(_right_fist.global_position, PUNCH_REACH,
		PUNCH_DAMAGE)
	hit.faction = DamageHit.Faction.ENEMY
	hit.target_peer = _peer_id(target)
	hit.parryable = true
	# Knocked back and left staggered on your feet. The lift is small on purpose:
	# enough to skid you, not enough to arrive anywhere at crashing speed.
	hit.reaction = DamageHit.Reaction.KNOCKBACK
	hit.world_impulse = away.normalized() * PUNCH_KNOCKBACK + _up() * PUNCH_LIFT
	hit.ability_id = "bigfoot_punch"
	hit.set_source(self)
	_apply_player_hit(target, hit)


## One stride's pause, an overhand throw, and back to whatever he was doing. He
## plants for it — a stone thrown while sprinting lands nowhere — but the stop is
## short enough to read as part of the run rather than as a stance he takes.
func _tick_rock(delta: float, target: Node) -> void:
	velocity = Vector3.ZERO
	_ground_speed = 0.0
	_face_along(_flat_on_surface(
		_combat_position(target) - global_position), delta, 8.0)
	if _attack_fired or ROCK_DURATION - _attack_left < ROCK_RELEASE:
		return
	_attack_fired = true
	_hurl_rock(target)


## Works out the launch and tells every peer about it. The stone is thrown at
## where the target will be after its own flight time and lofted enough to fall
## back onto them, which is what lets the same throw reach somebody standing in
## the trees and somebody hovering over them.
func _hurl_rock(target: Node) -> void:
	if target == null:
		return
	_update_bone_markers()
	var from := _throw_origin()
	var lead := _combat_position(target)
	var flight := clampf(from.distance_to(lead) / ROCK_SPEED, 0.05, 2.5)
	lead += _player_velocity(target) * flight * ROCK_LEAD
	var fall := -_up() * float(ProjectSettings.get_setting(
		"physics/3d/default_gravity", 24.0))
	var launch := (lead - from) / flight - fall * flight * 0.5
	if not launch.is_finite():
		return
	_publish_event({"kind": "rock", "from": from, "launch": launch})


func _throw_origin() -> Vector3:
	if _right_fist != null:
		return _right_fist.global_position
	return combat_position() + _up() * 1.4


func _player_velocity(player: Node) -> Vector3:
	if player == null:
		return Vector3.ZERO
	var moving: Variant = player.get(&"velocity")
	if moving is Vector3 and (moving as Vector3).is_finite():
		return moving
	return Vector3.ZERO


func _spawn_rock(from: Vector3, launch: Vector3) -> void:
	var planet := _planet()
	if planet == null:
		return
	var rock := ROCK.new()
	if not rock.launch(planet, from, launch, self):
		rock.free()
		return
	rock.damage = ROCK_DAMAGE
	rock.knockback = ROCK_KNOCKBACK
	rock.lift = ROCK_LIFT


func _tick_grab_throw(delta: float, target: Node) -> void:
	var total := GRAB_DURATION + THROW_DURATION
	var elapsed := total - _attack_left
	if not _grab_strike_done:
		if elapsed < GRAB_CONNECT:
			_close_on(target, delta)
			return
		if elapsed > GRAB_CONNECT + GRAB_WINDOW:
			# Closed on somebody who was not there any more. Better to break off
			# than to stand holding an empty fist for the throw.
			velocity = Vector3.ZERO
			_ground_speed = 0.0
			_grab_strike_done = true
			_melee_whiffed = true
			_attack_left = 0.0
			return
		if not _melee_connects(target, GRAB_REACH):
			_close_on(target, delta)
			return
		velocity = Vector3.ZERO
		_ground_speed = 0.0
		_face_along(_flat_on_surface(
			_combat_position(target) - global_position), delta, 6.0)
		_grab_strike_done = true
		var hit := DamageHit.impact(_right_fist.global_position, GRAB_REACH,
			GRAB_DAMAGE)
		hit.faction = DamageHit.Faction.ENEMY
		hit.target_peer = _peer_id(target)
		hit.parryable = true
		hit.ability_id = "bigfoot_grab"
		hit.set_source(self)
		var dealt := _apply_player_hit(target, hit)
		if dealt > 0.0 and not _player_is_grabbed(target) \
				and not _player_is_dead(target) \
				and _player_grab_at_socket(target, _grab_socket):
			_grabbed_peer = _peer_id(target)
		else:
			# Parried, or he had hold of nothing worth throwing.
			_melee_whiffed = true
			_attack_left = 0.0
			return
	velocity = Vector3.ZERO
	_ground_speed = 0.0
	_face_along(_flat_on_surface(
		_combat_position(target) - global_position), delta, 5.0)
	if _grabbed_peer > 0 and elapsed >= GRAB_DURATION:
		if _clip != "Throw":
			_play_clip("Throw", MELEE_CLIP_SPEED)
	if elapsed >= GRAB_DURATION + THROW_RELEASE and _grabbed_peer > 0 \
			and not _throw_released:
		_throw_released = true
		var victim := _player_by_peer(_grabbed_peer)
		var throw_dir := _flat_on_surface(
			victim.global_position - global_position if victim != null
			else target.global_position - global_position)
		if throw_dir.length_squared() < 0.01:
			throw_dir = -global_basis.z
		throw_dir = throw_dir.normalized()
		var throw_velocity := throw_dir * THROW_SPEED + _up() * 4.0
		if victim != null:
			# The damaging reaction below owns the throw velocity. Releasing with
			# it too would add the same impulse twice on OnlinePlayer.
			_player_release_grab(victim, Vector3.ZERO)
			var throw_hit := DamageHit.impact(_combat_position(victim), 1.0,
				THROW_DAMAGE)
			throw_hit.faction = DamageHit.Faction.ENEMY
			throw_hit.target_peer = _peer_id(victim)
			throw_hit.parryable = false
			throw_hit.reaction = DamageHit.Reaction.RAGDOLL
			throw_hit.world_impulse = throw_velocity
			throw_hit.ability_id = "bigfoot_throw"
			throw_hit.set_source(self)
			_apply_player_hit(victim, throw_hit)
		_grabbed_peer = 0


func _apply_player_hit_once(player: Node, hit: DamageHit) -> float:
	var peer := _peer_id(player)
	if _attack_hit_peers.has(peer):
		return 0.0
	_attack_hit_peers[peer] = true
	return _apply_player_hit(player, hit)


func _apply_player_hit(player: Node, hit: DamageHit) -> float:
	if not _is_host() or player == null or not player.has_method(&"apply_damage"):
		return 0.0
	return player.call(&"apply_damage", hit)


func _release_grabbed() -> void:
	if _grabbed_peer <= 0:
		return
	var player := _player_by_peer(_grabbed_peer)
	if _player_is_grabbed(player):
		_player_release_grab(player)
	_grabbed_peer = 0


func _cooldown_ready(id: StringName) -> bool:
	return maxf(float(_cooldowns.get(id, 0.0)), 0.0) <= 0.0


func _process_cooldowns(delta: float) -> void:
	for id: Variant in _cooldowns.keys():
		_cooldowns[id] = maxf(float(_cooldowns[id]) - delta, 0.0)


# --- Public API -------------------------------------------------------------

func maximum_health() -> float:
	return MAX_HEALTH


func health() -> float:
	return _health


func engaged() -> bool:
	return _engaged


func defeated() -> bool:
	return _defeated


func battle_radius() -> float:
	return ARENA_RADIUS


## Local presentation hook used by CombatHud. Authority does not decide this:
## each co-op peer sees the line exactly while that peer's boss bar is visible.
func set_arena_boundary_visible(shown: bool) -> void:
	if is_instance_valid(_arena_boundary) \
			and _arena_boundary.has_method(&"set_active"):
		_arena_boundary.call(&"set_active", shown and not _defeated)


func arena_distance_to(player: Node3D) -> float:
	var planet := _planet()
	if planet == null or planet.shape == null or player == null:
		return INF
	var centre := _spawn_transform.origin
	var a := planet.to_local(centre).normalized()
	var b := planet.to_local(player.global_position).normalized()
	return a.angle_to(b) * planet.shape.radius


func flash_damage(strength := 1.0) -> void:
	damaged_flash.emit(clampf(strength, 0.0, 1.0))


func boss_snapshot() -> Dictionary:
	return {
		"health": _health,
		"maximum_health": MAX_HEALTH,
		"engaged": _engaged,
		"defeated": _defeated,
		"target_peer": _target_peer,
		"transform": global_transform,
		"velocity": velocity,
		"clip": _clip,
		"clip_speed": _clip_speed,
		"attack": String(_attack),
		"attack_sequence": _attack_sequence,
		"attack_left": _attack_left,
		"cooldowns": _cooldowns.duplicate(),
		"clip_position": _animation_position(),
		"meteor_along": _meteor_along,
		"roar_elapsed": _roar_elapsed,
		"roar_radius": _roar_radius,
		"roar_origin": _roar_origin,
		"grabbed_peer": _grabbed_peer,
		"grappled": _grappled,
		"grapple_carrier_peer": _grapple_carrier_peer,
		"lassoed": _lassoed,
		"lasso_source_peer": _lasso_source_peer,
		"meteor_landed": _meteor_landed,
		"sync_sequence": _sync_sequence,
	}


func apply_boss_snapshot(wire: Dictionary) -> void:
	if wire.is_empty():
		return
	var sequence := int(wire.get("sync_sequence", 0))
	if sequence > 0:
		if sequence <= _last_sync_sequence:
			return
		_last_sync_sequence = sequence
	var maximum := float(wire.get("maximum_health", MAX_HEALTH))
	var next_health := float(wire.get("health", _health))
	if is_finite(maximum) and maximum > 0.0:
		pass
	var previous_health := _health
	if is_finite(next_health):
		_health = clampf(next_health, 0.0, MAX_HEALTH)
	if not is_equal_approx(previous_health, _health):
		health_changed.emit(_health, MAX_HEALTH)
	var was_engaged := _engaged
	_engaged = bool(wire.get("engaged", _engaged))
	_defeated = bool(wire.get("defeated", _defeated))
	_target_peer = int(wire.get("target_peer", 0))
	_grabbed_peer = int(wire.get("grabbed_peer", 0))
	_grappled = bool(wire.get("grappled", _grappled))
	_grapple_carrier_peer = int(wire.get(
		"grapple_carrier_peer", _grapple_carrier_peer))
	_grapple_carrier = _player_by_peer(_grapple_carrier_peer) as Node3D \
		if _grappled and _grapple_carrier_peer > 0 else null
	_set_grapple_collision(_grappled)
	_lassoed = bool(wire.get("lassoed", _lassoed))
	_lasso_source_peer = int(wire.get(
		"lasso_source_peer", _lasso_source_peer)) if _lassoed else 0
	_meteor_landed = bool(wire.get("meteor_landed", _meteor_landed))
	var transform_variant: Variant = wire.get("transform", global_transform)
	if transform_variant is Transform3D:
		var first_transform := not _has_target
		_target_transform = transform_variant
		if first_transform:
			global_transform = transform_variant
		_has_target = true
		_extrapolated = 0.0
	var velocity_variant: Variant = wire.get("velocity", velocity)
	if velocity_variant is Vector3 and (velocity_variant as Vector3).is_finite():
		velocity = velocity_variant
		_target_velocity = velocity
	var previous_clip := _clip
	_clip = String(wire.get("clip", _clip))
	# Only a genuine change of clip is worth seeking to. A finished one-shot
	# still reports the clip it is holding, and re-seeking that would restart
	# the collapse every time a snapshot arrived.
	if _clip != previous_clip or _clip_playing != _clip:
		_clip_seek = maxf(float(wire.get("clip_position", 0.0)), 0.0)
	_clip_speed = clampf(float(wire.get("clip_speed", 1.0)), 0.1, RUN_CLIP_MAX)
	_attack = StringName(String(wire.get("attack", "")))
	_attack_sequence = int(wire.get("attack_sequence", _attack_sequence))
	_attack_left = maxf(float(wire.get("attack_left", 0.0)), 0.0)
	var cooldown_wire: Variant = wire.get("cooldowns", {})
	if cooldown_wire is Dictionary:
		_cooldowns.clear()
		for id: Variant in cooldown_wire:
			_cooldowns[StringName(String(id))] = maxf(
				float((cooldown_wire as Dictionary)[id]), 0.0)
	var meteor_variant: Variant = wire.get("meteor_along", _meteor_along)
	if meteor_variant is Vector3 and (meteor_variant as Vector3).is_finite():
		_meteor_along = meteor_variant
	_roar_elapsed = maxf(float(wire.get("roar_elapsed", 0.0)), 0.0)
	_roar_radius = maxf(float(wire.get("roar_radius", 0.0)), 0.0)
	var roar_origin_variant: Variant = wire.get("roar_origin", _roar_origin)
	if roar_origin_variant is Vector3 and (roar_origin_variant as Vector3).is_finite():
		_roar_origin = roar_origin_variant
	if was_engaged != _engaged:
		engaged_changed.emit(_engaged)


# --- Combatant --------------------------------------------------------------

func combat_faction() -> int:
	return DamageHit.Faction.ENEMY


func combat_peer_id() -> int:
	return 0


func combat_display_name() -> String:
	return DISPLAY_NAME


func combat_position() -> Vector3:
	return global_position + _up() * 1.58


func combat_radius() -> float:
	return 0.72


func can_be_grappled() -> bool:
	return not _defeated and _health > 0.0 and not _grappled \
		and not _lassoed


func begin_grapple(carrier: Node3D) -> bool:
	if not can_be_grappled() or carrier == null:
		return false
	_release_grabbed()
	_attack = &""
	_attack_left = 0.0
	_attack_fired = false
	_grab_strike_done = false
	_throw_released = false
	_melee_whiffed = false
	_attack_hit_peers.clear()
	_ground_speed = 0.0
	velocity = Vector3.ZERO
	_grappled = true
	_grapple_carrier = carrier
	_grapple_carrier_peer = _peer_id(carrier)
	_set_grapple_collision(true)
	_play_clip(CLIP_IDLE)
	if is_instance_valid(_meteor_shock):
		_meteor_shock.stop()
	if is_instance_valid(_roar_wave) and _roar_wave.has_method(&"clear"):
		_roar_wave.call(&"clear")
	if _is_host():
		if not _engaged:
			_begin_aggro()
		_publish_sync(true)
	return true


func grapple_follow(centre: Vector3, up: Vector3) -> void:
	if not _grappled or not centre.is_finite():
		return
	up = up.normalized() if up.length_squared() > 0.001 else _up()
	global_position = centre - up * 1.58
	global_basis = _upright_basis(-global_basis.z, up)
	velocity = Vector3.ZERO
	reset_physics_interpolation()


func end_grapple(at: Vector3, up: Vector3) -> void:
	if not _grappled:
		return
	_clear_player_grapple()
	if at.is_finite():
		global_position = at
	if up.length_squared() > 0.001:
		global_basis = _upright_basis(-global_basis.z, up.normalized())
	_level_to_surface()
	_snap_to_ground()
	velocity = Vector3.ZERO
	_target_transform = global_transform
	_target_velocity = Vector3.ZERO
	_has_target = true
	_extrapolated = 0.0
	reset_physics_interpolation()
	if not _defeated:
		_play_clip(CLIP_IDLE)
	if _is_host():
		_publish_sync(true)


func can_be_lassoed() -> bool:
	return not _defeated and _health > 0.0 and not _grappled \
		and not _lassoed


func begin_lasso(source: Node3D) -> bool:
	if not can_be_lassoed() or source == null:
		return false
	_release_grabbed()
	_attack = &""
	_attack_left = 0.0
	_attack_fired = false
	_grab_pending = false
	_grab_strike_done = false
	_throw_released = false
	_melee_whiffed = false
	_attack_hit_peers.clear()
	_ground_speed = 0.0
	_lasso_knockback_left = 0.0
	velocity = Vector3.ZERO
	_lassoed = true
	_lasso_source_peer = int(source.get("peer_id")) \
		if source.get("peer_id") != null else 0
	_set_grapple_collision(false)
	_play_clip(CLIP_IDLE)
	if is_instance_valid(_meteor_shock):
		_meteor_shock.stop()
	if _is_host():
		if not _engaged:
			_begin_aggro()
		_publish_sync(true)
	return true


func lasso_simulate(motion: Vector3,
		next_velocity: Vector3) -> Dictionary:
	if not _is_host() or not _lassoed or not motion.is_finite() \
			or not next_velocity.is_finite():
		return {}
	var collision := move_and_collide(motion)
	velocity = next_velocity
	_target_transform = global_transform
	_target_velocity = velocity
	_has_target = true
	_extrapolated = 0.0
	if collision == null:
		return {"collided": false}
	return {
		"collided": true,
		"normal": collision.get_normal(),
		"position": collision.get_position(),
		"collider": collision.get_collider(),
	}


func lasso_apply_network_motion(at: Transform3D,
		next_velocity: Vector3) -> void:
	if _is_host() or not _lassoed or not at.is_finite() \
			or not next_velocity.is_finite():
		return
	global_transform = at
	_target_transform = at
	velocity = next_velocity
	_target_velocity = next_velocity
	_has_target = true
	_extrapolated = 0.0
	reset_physics_interpolation()


func end_lasso(throw_velocity: Vector3) -> void:
	if not _lassoed:
		return
	_clear_player_lasso()
	velocity = throw_velocity if throw_velocity.is_finite() else Vector3.ZERO
	_target_velocity = velocity
	_target_transform = global_transform
	_has_target = true
	_extrapolated = 0.0
	_lasso_knockback_left = 0.9 if velocity.length_squared() > 1.0 else 0.0
	reset_physics_interpolation()
	if _is_host():
		_publish_sync(true)


func lasso_mass() -> float:
	return 8.0


func is_lassoed() -> bool:
	return _lassoed


func _clear_player_grapple() -> void:
	_grappled = false
	_grapple_carrier_peer = 0
	_grapple_carrier = null
	_set_grapple_collision(false)


func _clear_player_lasso() -> void:
	_lassoed = false
	_lasso_source_peer = 0
	_set_grapple_collision(false)


func _set_grapple_collision(disabled: bool) -> void:
	var collision := get_node_or_null(^"CollisionShape3D") as CollisionShape3D
	if collision != null:
		collision.set_deferred(&"disabled", disabled)


func apply_damage(hit: DamageHit) -> float:
	if hit == null or not _is_host() or _defeated:
		return 0.0
	if hit.faction != DamageHit.Faction.PLAYER:
		return 0.0
	var before := _health
	var amount := minf(maxf(hit.amount if is_finite(hit.amount) else 0.0, 0.0),
		before)
	if amount > 0.0:
		# A beam is held on him rather than landed once, so it keeps this topped
		# up and he keeps cutting across it for as long as it is on him.
		_under_fire = maxf(_under_fire,
			UNDER_FIRE_BEAM if hit.kind == DamageHit.Kind.BEAM
			else UNDER_FIRE_HIT)
		_health = before - amount
		if not _lassoed and (hit.reaction == DamageHit.Reaction.KNOCKBACK \
				or hit.reaction == DamageHit.Reaction.RAGDOLL):
			var impulse := hit.world_impulse \
				if hit.world_impulse.is_finite() else Vector3.ZERO
			velocity += impulse / lasso_mass()
			_lasso_knockback_left = maxf(_lasso_knockback_left, 0.75)
		health_changed.emit(_health, MAX_HEALTH)
		_publish_event({"kind": "damaged", "amount": amount,
			"at": hit.centre()})
	if not _engaged and amount > 0.0:
		_begin_aggro()
	if _health <= 0.0 and before > 0.0:
		_defeated = true
		_clear_player_grapple()
		_clear_player_lasso()
		set_arena_boundary_visible(false)
		_phase = Phase.DEFEATED
		_release_grabbed()
		_attack = &""
		_defeat_elapsed = 0.0
		_defeat_basis = global_basis.orthonormalized()
		_ground_speed = 0.0
		velocity = Vector3.ZERO
		_play_clip("Defeat")
		_publish_event({"kind": "defeated"})
		_publish_sync(true)
	return amount


## Plays the collapse out and then tips the carcass over onto the terrain.
##
## The clip alone leaves him buckled but still on his feet, because it is baked
## against a flat floor and would stand him on a shoulder anywhere else. Rolling
## the whole body here instead means the last pose lands along whatever slope he
## died on, and it replicates for free with the transform.
func _settle_defeat(delta: float) -> void:
	_defeat_elapsed += delta
	velocity = Vector3.ZERO
	var share := clampf(
		(_defeat_elapsed - DEFEAT_HOLD) / DEFEAT_FALL, 0.0, 1.0)
	share = share * share * (3.0 - 2.0 * share)
	if share <= 0.0:
		_snap_to_ground()
		return
	var planet := _planet()
	if planet == null or planet.shape == null:
		return
	var local := planet.to_local(global_position)
	if local.length_squared() < 1.0:
		return
	var out := local.normalized()
	var floor_radius := planet.shape.radius \
		+ planet.shape.elevation(out, planet.finest_spacing())
	var up := planet.to_global(out * (floor_radius + 1.0)) \
		- planet.to_global(out * floor_radius)
	global_basis = Basis(_defeat_basis.x.normalized(), DEFEAT_PITCH * share) \
		* _defeat_basis
	global_position = planet.to_global(out * floor_radius) \
		+ up.normalized() * (DEFEAT_LIFT * share)


func receive_reflected_damage(amount: float, source_peer: int) -> void:
	if not _is_host() or amount <= 0.0:
		return
	var hit := DamageHit.impact(combat_position(), combat_radius(), amount)
	hit.faction = DamageHit.Faction.PLAYER
	hit.source_peer = source_peer
	hit.ability_id = "parry_reflect"
	var source := _player_by_peer(source_peer)
	if source != null:
		hit.set_source(source, source_peer)
	var dealt := apply_damage(hit)
	if dealt > 0.0 and source != null \
			and source.has_method(&"combat_damage_dealt"):
		source.call(&"combat_damage_dealt", self, dealt, hit)


# --- Networking -------------------------------------------------------------

func _publish_sync(reliable: bool) -> void:
	# Offline and single-player still ran the clock, built the snapshot twenty
	# times a second and threw it away.
	if not _has_listeners():
		return
	_sync_sequence += 1
	var wire := boss_snapshot()
	wire["sync_sequence"] = _sync_sequence
	if reliable:
		_apply_bigfoot_sync_reliable.rpc(_sync_sequence, wire)
	else:
		_apply_bigfoot_sync.rpc(_sync_sequence, wire)


func _publish_event(event: Dictionary) -> void:
	_event_sequence += 1
	event["sequence"] = _event_sequence
	if not _has_listeners():
		_apply_bigfoot_event(_event_sequence, event)
	else:
		_apply_bigfoot_event.rpc(_event_sequence, event)


@rpc("authority", "call_local", "unreliable_ordered")
func _apply_bigfoot_sync(sequence: int, snapshot: Dictionary) -> void:
	if _is_host():
		return
	snapshot["sync_sequence"] = sequence
	apply_boss_snapshot(snapshot)


@rpc("authority", "call_local", "reliable")
func _apply_bigfoot_sync_reliable(sequence: int, snapshot: Dictionary) -> void:
	if _is_host():
		return
	snapshot["sync_sequence"] = sequence
	apply_boss_snapshot(snapshot)


@rpc("authority", "call_local", "reliable")
func _apply_bigfoot_event(sequence: int, event: Dictionary) -> void:
	if sequence <= _last_event_sequence:
		return
	_last_event_sequence = sequence
	match String(event.get("kind", "")):
		"damaged":
			var amount := float(event.get("amount", 0.0))
			flash_damage(clampf(amount / 120.0, 0.2, 1.0))
		"reset":
			arena_reset.emit()
		"roar_start":
			var at_variant: Variant = event.get("at", _mouth.global_position)
			if at_variant is Vector3:
				_roar_origin = at_variant
		"roar_end":
			if is_instance_valid(_roar_wave) and _roar_wave.has_method(&"clear"):
				_roar_wave.call(&"clear")
		"meteor_land":
			_meteor_landed = true
		"rock":
			# Every peer flies its own stone from the same launch, so the throw
			# arcs and shatters in the same place everywhere without a second
			# packet per frame to say where it got to.
			var from_variant: Variant = event.get("from", Vector3.ZERO)
			var launch_variant: Variant = event.get("launch", Vector3.ZERO)
			if from_variant is Vector3 and launch_variant is Vector3:
				_spawn_rock(from_variant, launch_variant)


func _has_listeners() -> bool:
	return multiplayer.has_multiplayer_peer() \
		and not multiplayer.get_peers().is_empty()


func _is_host() -> bool:
	return not multiplayer.has_multiplayer_peer() or multiplayer.is_server()


# --- Presentation -----------------------------------------------------------

func _bind_visuals() -> void:
	var model := get_node_or_null("Model")
	if model != null:
		_animator = model.find_child("AnimationPlayer", true, false) \
			as AnimationPlayer
		_skeleton = model.find_child("Skeleton3D", true, false) as Skeleton3D
		for node in model.find_children("*", "MeshInstance3D", true, false):
			(node as MeshInstance3D).material_override = RIM_SURFACE
	_mouth = get_node_or_null(mouth_marker) as Marker3D
	_right_fist = get_node_or_null(right_fist_marker) as Marker3D
	_left_fist = get_node_or_null(left_fist_marker) as Marker3D
	_grab_socket = get_node_or_null(grab_marker) as Marker3D
	if _animator != null:
		for clip_name in ["Idle", "Walk", "Run", "MeteorFly"]:
			if _animator.has_animation(clip_name):
				_animator.get_animation(clip_name).loop_mode = Animation.LOOP_LINEAR
	_meteor_shock = MeteorShock.new()
	_meteor_shock.name = "MeteorShock"
	_meteor_shock.radius = METEOR_FIST_RADIUS
	add_child(_meteor_shock, false, Node.INTERNAL_MODE_BACK)
	_roar_wave = ROAR_WAVE.new()
	_roar_wave.name = "RoarWave"
	add_child(_roar_wave, false, Node.INTERNAL_MODE_BACK)
	_arena_boundary = ARENA_BOUNDARY.new()
	_arena_boundary.name = "ArenaBoundary"
	add_child(_arena_boundary, false, Node.INTERNAL_MODE_BACK)


const MARKER_BONES: Array[String] = [
	"Head", "RightHand", "LeftHand", "RightHand"]
const MARKER_OFFSETS: Array[Vector3] = [
	Vector3(0.0, 0.12, -0.18),
	Vector3(0.0, 0.0, -0.12),
	Vector3(0.0, 0.0, -0.12),
	Vector3(0.08, -0.05, -0.22)]


func _update_bone_markers() -> void:
	if _skeleton == null:
		return
	if _bone_indices.is_empty():
		for bone_name in MARKER_BONES:
			_bone_indices.append(_skeleton.find_bone(bone_name))
	var skeleton_transform := _skeleton.global_transform
	_drive_marker(_mouth, 0, skeleton_transform)
	_drive_marker(_right_fist, 1, skeleton_transform)
	_drive_marker(_left_fist, 2, skeleton_transform)
	_drive_marker(_grab_socket, 3, skeleton_transform)


func _drive_marker(marker: Marker3D, slot: int,
		skeleton_transform: Transform3D) -> void:
	if marker == null or slot >= _bone_indices.size():
		return
	var index := _bone_indices[slot]
	if index < 0:
		return
	marker.global_transform = skeleton_transform \
		* _skeleton.get_bone_global_pose(index) \
		* Transform3D(Basis.IDENTITY, MARKER_OFFSETS[slot])


func _update_presentation(delta: float) -> void:
	if _animator != null and _animator.has_animation(_clip):
		# A one-shot that has run out clears `current_animation`, so testing
		# that alone restarts it every frame: Defeat looped forever and he never
		# finished falling over. Only a genuine change of clip replays, and a
		# finished one-shot is left holding its last pose.
		var looping := _animator.get_animation(_clip).loop_mode \
			!= Animation.LOOP_NONE
		var restart := _clip_playing != _clip \
			or (looping and _animator.current_animation.is_empty())
		if restart:
			_clip_playing = _clip
			_animator.play(_clip, CLIP_BLEND)
		if _clip_seek >= 0.0:
			if restart:
				var clip_length := _animator.get_animation(_clip).length
				_animator.seek(clampf(_clip_seek, 0.0, clip_length), true)
			_clip_seek = -1.0
		_animator.speed_scale = _clip_speed
	var meteor_elapsed := _attack_duration(&"meteor") - _attack_left
	if _attack == &"meteor" and meteor_elapsed >= METEOR_WINDUP \
			and not _meteor_landed \
			and is_instance_valid(_meteor_shock):
		_meteor_shock.aim(_right_fist.global_position,
			_meteor_along if _meteor_along.length_squared() > 0.01 else -global_basis.z,
			METEOR_FLY_SPEED)
	elif is_instance_valid(_meteor_shock):
		_meteor_shock.stop()
	if is_instance_valid(_roar_wave):
		if _roar_radius > 0.05 and _roar_elapsed >= ROAR_WAVE_START \
				and _roar_elapsed <= ROAR_WAVE_END + 0.2 \
				and _roar_wave.has_method(&"set_wave"):
			_roar_wave.call(&"set_wave", _roar_origin, _roar_radius)
		elif _roar_elapsed > ROAR_WAVE_END + 0.2 \
				and _roar_wave.has_method(&"clear"):
			_roar_wave.call(&"clear")


func _play_clip(clip: String, speed := 1.0) -> void:
	_clip = clip
	_clip_speed = speed


func _animation_position() -> float:
	if _animator == null or _animator.current_animation.is_empty():
		return 0.0
	return _animator.current_animation_position


# --- Planet helpers ---------------------------------------------------------

func _planet() -> Planet:
	if is_instance_valid(_cached_planet):
		return _cached_planet
	var walk: Node = self
	while walk != null:
		if walk is Planet:
			_cached_planet = walk as Planet
			return _cached_planet
		walk = walk.get_parent()
	return null


func _world() -> GameWorld:
	return DamageHit.game_world_of(self)


func _up() -> Vector3:
	return global_basis.y.normalized()


func _flat_on_surface(vector: Vector3) -> Vector3:
	var up := _up()
	return vector - up * vector.dot(up)


func _tangent_east(up: Vector3) -> Vector3:
	var hint := Vector3.UP if absf(up.y) < 0.9 else Vector3.FORWARD
	return up.cross(hint).normalized()


func _align_up(delta: float) -> void:
	var planet := _planet()
	if planet == null:
		return
	var up := planet.up_at(global_position)
	up_direction = up
	var axis := global_basis.y.cross(up)
	if axis.length_squared() < 0.000001:
		return
	var angle := global_basis.y.angle_to(up)
	var taken := angle * (1.0 - exp(-8.0 * delta))
	global_basis = (Basis(axis.normalized(), taken) * global_basis).orthonormalized()


func _face_along(forward: Vector3, delta: float, rate: float) -> void:
	var flat := _flat_on_surface(forward)
	if flat.length_squared() < 0.0001:
		return
	_align_up(delta)
	var up := _up()
	var want := flat.normalized()
	var current := _flat_on_surface(-global_basis.z)
	if current.length_squared() < 0.0001:
		current = want
	current = current.normalized()
	var angle := current.signed_angle_to(want, up)
	var turn := clampf(angle, -rate * delta, rate * delta)
	global_basis = Basis(up, turn) * global_basis


## Keeps him on the ground without driving him into it.
##
## He carries no weight of his own: every state he has sets a velocity along the
## surface and nothing pulls him down, so this is what makes him follow the
## terrain rather than walk out over it. It used to do that by setting his
## distance from the planet's middle to the height field's answer, once a tick,
## which is exactly right on the open ground he was written against and wrong on
## the one piece of terrain he makes for himself.
##
## A chunk's collider is a triangulation of that field, and inside the bowl of a
## crater the flat chords between samples stand above the curve they cut across —
## a quarter of a metre of it, at the metre and a half his own craters are built
## at. Planting him on the curve therefore planted him a quarter of a metre
## inside the mesh every tick, and the solver spent the next frame pushing him
## back out along the wall's normal, which points up and in. That is most of a
## stride at a run, aimed against the direction he was trying to leave in: he
## would climb to about seven metres from the middle of his own hole, at a full
## sprint, and stay there for as long as he was asked to.
##
## So the way down is swept now instead of teleported, and stops on the ground
## that is actually under him rather than on the ground the field describes. The
## way up is still a teleport, because a body that has gone through the world has
## nothing left to sweep against — but it waits for a gap deeper than a chord can
## account for, so ordinary ground that dips below its own height field is left
## alone to be stood on.
func _snap_to_ground() -> void:
	var planet := _planet()
	if planet == null or planet.shape == null:
		return
	var local := planet.to_local(global_position)
	if local.length_squared() < 1.0:
		return
	var out := local.normalized()
	var spacing := planet.finest_spacing()
	var floor_radius := planet.shape.radius + planet.shape.elevation(out, spacing)
	var under := floor_radius - local.length()
	if under > GROUND_CHORD:
		global_position = planet.to_global(out * floor_radius)
	elif under < 0.0:
		# Negative because `under` is: one call, down as far as the drop the
		# field asks for or as far as the collider allows, whichever comes
		# first.
		move_and_collide(_up() * under)
	velocity = _flat_on_surface(velocity)


func _altitude_of(player: Node) -> float:
	var planet := _planet()
	if planet == null or planet.shape == null:
		return INF
	var local := planet.to_local(player.global_position)
	if local.length_squared() < 1.0:
		return INF
	var out := local.normalized()
	var floor_radius := planet.shape.radius \
		+ planet.shape.elevation(out, planet.finest_spacing())
	return maxf(local.length() - floor_radius, 0.0)


## The living players in this world, in a buffer that is refilled rather than
## reallocated. Every caller reads it and drops it inside the same frame.
func _living_players_in_world() -> Array:
	_players_buffer.clear()
	var world := _world()
	if world == null:
		return _players_buffer
	for peer_id in world._spawned_players:
		var player: Node = world._spawned_players[peer_id]
		if player == null or not is_instance_valid(player):
			continue
		if player.has_method(&"is_dead") and bool(player.call(&"is_dead")):
			continue
		_players_buffer.append(player)
	return _players_buffer


func _all_living_players_outside() -> bool:
	for player: Node in _living_players_in_world():
		if arena_distance_to(player) <= ARENA_RADIUS:
			return false
	return true


func _pick_target() -> void:
	var best: Node = null
	var best_dist := INF
	for player in _living_players_in_world():
		if arena_distance_to(player) > ARENA_RADIUS:
			continue
		var dist := _distance_to_player(player)
		if dist < best_dist:
			best_dist = dist
			best = player
	if best != null:
		_target_peer = _peer_id(best)
	else:
		_target_peer = 0


func _distance_to_player(player: Node) -> float:
	if player == null:
		return INF
	var point := _combat_position(player)
	return combat_position().distance_to(point)


func _target_player() -> Node:
	return _player_by_peer(_target_peer)


func _player_by_peer(peer_id: int) -> Node:
	if peer_id <= 0:
		return null
	var world := _world()
	if world == null:
		return null
	return world._spawned_players.get(peer_id)
