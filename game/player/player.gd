class_name OnlinePlayer
extends CharacterBody3D

## Networked first/third person character. The local player simulates itself and
## broadcasts state; everyone else is interpolated toward the state they receive.

enum Stance { STAND, CROUCH, SLIDE, FLY, CRASH, SWIM, HERO, METEOR, GRAPPLE }
enum CameraMode { FIRST, THIRD_NEAR, THIRD_FAR }
enum ProjectileRequestState { PENDING, ACCEPTED, REJECTED }

## Extension points for item and ability definitions that do not exist yet.
## Empty slots never emit either signal.
signal item_activated(item_id: String)
signal ability_activated(slot: int, ability_id: String)
## The ability button came back up. Sustained abilities need both edges; a
## one-shot ability simply ignores this one.
signal ability_released(slot: int)
signal health_changed(current: float, maximum: float)
signal died(source_peer: int, cause: String)
signal respawned
signal status_changed(id: StringName, remaining: float)
signal parry_started
signal parry_blocked(perfect: bool, hit: DamageHit)
## Public foundation for a future enemy flash and outgoing damage numbers.
signal enemy_damaged(target: Node, amount: float, hit: DamageHit)
signal grabbed(socket: Node)
signal released_from_grab(throw_velocity: Vector3)

const SYNC_INTERVAL := 1.0 / 20.0
const DEFAULT_STAGGER_TIME := 0.28
const DAMAGE_RAGDOLL_TIME := 0.75
## Floor under the teleport check, in metres between two packets. What a flying
## player can legitimately cover is far more than this, so the real limit is
## worked out from their stance; see `_speed_limit`.
const MAX_ACCEPTED_STEP := 4.0
const CityMinimap := preload("res://game/city/city_minimap.gd")
const CrawlerCityRingScript := preload("res://game/crawler/crawler_city_ring.gd")
const CrawlerArrivalFlashScript := preload("res://game/crawler/crawler_arrival_flash.gd")
const TrainingField := preload("res://game/crawler/crawler_training.gd")
const CrawlerLevelMenuScript := preload("res://ui/menu/crawler_level_menu.gd")
const JukeAfterimageScript := preload("res://game/player/juke_afterimage.gd")

## How far in front of the eyes something can be interacted with. Measured from
## the body, not the camera, so third person is not a longer arm.
const REACH := 2.4
## How far above the collider the interaction ray hit to look for the script that
## knows what using it means. See [method _interactable].
const INTERACT_ANCESTOR_HOPS := 6
const BACKPACK_SLOTS := CharacterDB.BACKPACK_SLOTS

## Numbered weapon/item slots remain for leftover saves. Combat uses four
## ability slots. WEAPON_SLOTS is retained as an alias while old pages still
## call the item row a weapon rack.
const HOTBAR_SLOTS := CharacterDB.HOTBAR_SLOTS
const ABILITY_SLOTS := CharacterDB.ABILITY_SLOTS
## Training enemies carry a three-ability kit so a dummy can practise a short
## roster without matching the player's four hotbar slots.
const TRAINING_ABILITY_SLOTS := 3
const WEAPON_SLOTS := HOTBAR_SLOTS
## Weapons are two-handed here, so one hand carries them and the other supports.
const WEAPON_HAND := "right"
## Where a shot is aimed: far enough that the muzzle's offset from the eye does not
## bend the line noticeably.
const AIM_RANGE := 60.0
## Field of view while sighted down the optic, as a fraction of the usual one.
const AIM_FOV_SCALE := 0.55
## Seconds a cell takes to win back one shot, and the pause after firing before it
## starts. A carbine that never reloads still has to be paced.
const CELL_RECHARGE := 0.85
const CELL_PAUSE := 0.55

## Logical clip names the stance machine speaks. Mixamo bodies resolve them
## through [CharacterRig]; glTF still carries no loop flag, so the cycles are
## marked in [method CharacterRig.prepare].
const CLIP_BLEND := 0.14
const ANIM_PICKER_HOLD := 0.18
## Crawler pad arrival: Death_C played backwards, from the ground up.
const SPAWN_ARRIVAL_CLIP := "Death_C"
const SPAWN_ARRIVAL_SPEED := -1.0
const WAYPOINT_REVEAL_TURN := 0.72
const WAYPOINT_REVEAL_BLINK := 0.88
const WAYPOINT_REVEAL_HOLD := 0.55
const WAYPOINT_REVEAL_FADE := 0.8
const WAYPOINT_REVEAL_TURN_RATE := 3.4
const WAYPOINT_REVEAL_NEAR := 50.0
## A normal hop lands before this. Longer arcs earn a deliberate landing stride
## instead of leaving the arms-back launch pose to sag in a looping fall.
const AIR_RUN_DELAY := 1.0
const AIR_RUN_BLEND := 0.55
## `Run` has its right leg forward one quarter through the cycle, matching
## `AirRun`'s offered landing foot.
const AIR_RUN_TO_RUN_PHASE := 0.25
## How long the landing clip owns the body before locomotion takes over again.
const LAND_TIME := 0.28

# Everything below is indexed by Stance, so the rows must stay in enum order.
# Sized to the bare body in player_character.glb, which stands 1.45 m tall and
# crouches to roughly 1.2 m in the CrouchIdle pose. Worn garments deliberately do
# not resize it: a hat is not a reason to stop fitting through a gap. Flight and
# swimming both borrow the standing capsule, which is why taking off, landing and
# wading out never have to ask whether there is room.
const COLLIDER_HEIGHTS := [1.45, 1.2, 0.9, 1.45, 0.9, 1.45, 0.9, 1.45, 1.45]
const EYE_HEIGHTS := [1.29, 1.06, 0.78, 1.29, 0.6, 1.29, 0.72, 1.29, 1.29]

## Fraction of `fly_speed` at which the body has finished going over from an
## upright hover to flat-out flight. A quarter, so almost the whole boost is
## spent in the flying silhouette rather than on the way into it.
const FLAT_OUT := 0.25
## Flight pitches the body about its hips, in metres off the floor: turning about
## the feet would swing the head most of a body length forward. A sprint leans
## from the ankles instead, which is what keeps the feet where the clip plants
## them, so its pivot is the floor.
const LEAN_PIVOT := 0.72
## How far a flat-out run leans, in radians, and the fraction of `run_top_speed`
## at which it has finished leaning. The clip only resamples so far before the
## legs stop reading, so past a point the lean is what carries the speed.
const SPRINT_LEAN := 0.35
const GROUND_FLAT_OUT := 0.35
## Seventy-five degrees clears the south-pole caldera's inner wall while leaving
## cliffs and building walls outside the floor cone. `FLOOR_FACE` is cos(75°)
## and is used anywhere raw collision normals must make the same choice as
## CharacterBody3D's `floor_max_angle`.
const MAX_WALK_SLOPE_DEGREES := 75.0
const FLOOR_FACE := 0.258819
## How far off the ground a face has to lean before running into it ends the run
## rather than being ridden over. `_steepest_contact` measures 0 for flat ground
## and 1 for a vertical wall, so 0.8 reserves this for cliffs and buildings.
const RUN_BREAK_FACE := 0.8
## Clear air needed under the feet before space takes off rather than buffering a
## jump. Both read the same press in the same state, and without this the buffer
## would never fire again: a press made just before landing is exactly the press
## it exists to catch. Under a metre, space is still asking to jump on landing.
const TAKEOFF_CLEARANCE := 0.9
## How fast the body rolls square to the ground under it, in e-foldings a second
## at full blend. Roughly a third of a second to settle, which is slow enough to
## read as the planet taking hold and fast enough that a walk never lags the
## curve it is walking over.
const ALIGN_RATE := 3.0
## How far under the body a chunk collider counts as the ground it is standing
## on, in metres. The chunk mesh is a triangulation of the same height field the
## guard reads, band-limited to whatever depth that chunk happens to be at, so it
## can sit a couple of decimetres below the value sampled here. Wherever that
## mesh exists it wins: it is the surface the player can see, and arguing with it
## over the decimetre between the two is what made a body standing still jitter.
const GROUND_MARGIN := 0.5
## How far under the field the body has to be before the mesh stops getting the
## benefit of the doubt, in metres. Past this it is not resting on a triangle
## that dips, it is inside the world, and no collider gets a vote.
const TUNNEL_DEPTH := 0.8
## How close to the field counts as having something under the feet, in metres.
## `is_on_floor` asks only about the move that just happened, and on the planet
## it says no far more often than the ground warrants — a run at speed spends
## most of its frames a centimetre or two clear of the mesh, and a body that is
## airborne on a technicality gets air control, no floor snapping and no stair
## step, which is most of what "caught on every bump" is made of.
const FOOT_REACH := 0.35
## The most pieces one tick's travel is cut into for the height field to be
## asked about along it rather than only at the end of it. The pieces are the
## field's own finest spacing — about 1.5 m at the planet's defaults, which is
## the narrowest ridge it can hold — so this cap is what actually binds: it is
## reached at around 1400 m/s, and past that the pieces get longer rather than
## more numerous. See [method _rewind_to_entry].
const SWEEP_PARTS := 16
## Halvings spent narrowing a crossing once a piece has found one. Four takes a
## metre and a half down to nine centimetres, which is well inside the
## `GROUND_MARGIN` the field and the mesh disagree by anyway.
const SWEEP_REFINE := 4
## How far the camera keeps off the ground, in metres. Its near plane is 0.1 m
## and the field is a smoothed copy of the mesh, so this is that plane plus the
## couple of decimetres the two can differ by.
const CAMERA_CLEARANCE := 0.45

## How hard a flight has to meet something solid before it becomes a crash, in
## metres a second into the surface. Well above `float_speed`, so nudging a wall
## while hovering just stops the body, and well under a boost, so any real flight
## into a hillside puts the player down.
const CRASH_SPEED := 26.0
## CollisionShape3D metadata published by GroundCover and FlowerTreeField.
## Requiring this explicit owner keeps cliffs, buildings and ring sites on the
## ordinary crash path even though all of them are StaticBody3D on layer one.
const IMPACT_BREAK_OWNER_META := &"impact_break_owner"
## A fast floor impact steeper than this fraction of velocity into the ground
## becomes a planted one-knee landing. Shallower arrivals keep their tangential
## momentum and run out of the landing instead. 0.55 is about 33 degrees down.
const HERO_LANDING_ANGLE := 0.55
const HERO_LANDING_TIME := 0.8

# Meteor punch. The reach, the top speed and the damage are the ability's, out
# of `ItemDB`, so the menu and the body quote the same numbers; what is written
# here is only what the movement itself needs.
## Slowest a punch ever leaves at, for someone who threw it standing still. Fast
## enough that the first tick already reads as a launch rather than a step.
## Right-click dash. Two metres at base, short i-frames, and afterimages.
const JUKE_DISTANCE := 2.0
const JUKE_TIME := 0.18
const JUKE_COOLDOWN := 5.0
const JUKE_GHOST_GAP := 0.04
const METEOR_LAUNCH_SPEED := 60.0
## Metres a second squared up to the ability's top speed. Reaches two hundred
## from a standing launch in about a third of a second, which is a third of the
## fifty-metre reach spent winding up — enough to feel like acceleration and not
## so much that the punch lands before it has got going.
const METEOR_ACCELERATION := 420.0
## How often the fist deals damage on its way through, and the share of the
## ability's quoted damage each of those turns is worth.
##
## Not every physics tick, for the same reason the laser is not: a turn is also
## a packet and a sweep of every damageable field in the world, and at sixty
## hertz that was eight milliseconds a frame for the whole flight. The volume is
## swept from where the fist was to where it is, so a slower clock does not
## leave gaps in what it cuts — it only makes each capsule longer. Twenty hertz
## is ten metres of capsule at the punch's top speed, against a fist four metres
## across, so the flora sees a continuous cylinder either way.
const METEOR_DAMAGE_HZ := 20.0
const METEOR_DAMAGE_STEP := 1.0 / METEOR_DAMAGE_HZ
const METEOR_TICK_SHARE := METEOR_DAMAGE_STEP
## Fallback fist cylinder, used only if the catalogue entry omits its radius.
const METEOR_FIST_RADIUS := 4.0
## Metres the landing blow dissipates over, well past the fist's own reach.
const METEOR_SPREAD := 12.0
const METEOR_CRATER_RADIUS := 6.0
const METEOR_CRATER_DEPTH := 2.5
## Flora damage is separate from actor damage at a landing. The latter fades
## across the visible blast; the former must remove every root over ground the
## crater no longer contains, including stone-tough cover at its rim.
const METEOR_FLORA_DAMAGE := 6000.0
## Roots and the sampled crater edge are not infinitely thin. This small lip
## keeps plants whose origins round just outside the last terrain sample from
## being left overhanging it.
const METEOR_FLORA_MARGIN := 0.75
## How much bigger a fast arrival digs, at most. `fly_speed` is 1000 m/s, so a
## dive can arrive five times faster than the punch's own top speed and a hole
## the same size either way makes the dive pointless. Square-rooted rather than
## linear on the way there, which is roughly how a real impact scales and, more
## to the point, keeps the biggest hole to four times the area rather than
## twenty-five: the crater's footprint is terrain that has to be rebuilt, and
## that is the one thing about this move that costs a frame.
const METEOR_CRATER_MAX_SCALE := 2.0
## How steeply a punch has to be aimed down before it counts as a dive at the
## planet rather than a punch thrown out across it. Shares the sense of
## [constant METEOR_CONTACT_FACING] and, near enough, its value.
const METEOR_DIVE_FACING := 0.3
## Seconds of flight the ground can be away and still have a dive commit to it
## once its powered reach is spent. Measured in time rather than in metres
## because that is what makes it scale with the thing it is about: a dive at a
## thousand metres a second is committed from a kilometre up, and one at sixty
## is not committed until it is nearly there.
const METEOR_COMMIT_LEAD := 1.5
## How far ahead of the feet a landing with nothing struck opens its cone.
const METEOR_CONE_AHEAD := 3.0
## How squarely a surface has to face a punch before it counts as struck. A flat
## punch thrown from a standing start skims the ground it left, and a floor
## brushed underfoot is not a hillside driven into: only a surface leaning back
## towards the fist ends the move.
const METEOR_CONTACT_FACING := 0.3
## Metres a ground launch lifts the body before it sets off, so the punch travels
## through the air over the ground rather than grinding along it.
const METEOR_GROUND_LIFT := 1.1
## Seconds a landed punch goes on waiting for its own crater to turn up. A host
## has one on the frame it asks; a client is granted one a round trip later, so
## this is sized for a poor connection rather than a good one. Past it the hole
## is treated as refused and the body is left to the ordinary ground rules.
const CRATER_SETTLE := 1.0
## Metres the ground has to drop before it counts as the crater arriving rather
## than as the height field being resampled at a finer spacing underfoot.
const CRATER_STEP := 0.25
## How fast the body goes over into the punch's lean. Flat inside a fifth of a
## second, which at the speeds involved is the first few metres.
const METEOR_LEAN_RATE := 18.0
## Seconds the punch's pose takes to cross-fade in. Short: at two hundred metres
## a second the usual quarter-second blend is the whole first half of the move
## spent between two poses.
const METEOR_CLIP_BLEND := 0.08
const RUN_LANDING_KEEP := 0.88
## Slight automatic nose-up applied only when a fast jump enters Fly directly.
const FAST_TAKEOFF_LOOK := 0.12
## How hard a surface has to be met before the limb that met it is knocked loose,
## in metres a second into it. Above a sprint, so walking into a doorway does
## nothing, and well under `CRASH_SPEED`, so there is a band of impacts that are
## worth feeling without being worth falling over.
const KNOCK_SPEED := 9.0
## The impulse a knock is worth, in newton-seconds per metre a second of impact,
## and the speed past which more of it buys nothing. An arm is a couple of kilos,
## so a graze at the threshold moves it at walking pace and the hardest knock
## short of a crash throws it at a run. Anything more and a clipped shoulder
## looks like a dislocation.
const KNOCK_WEIGHT := 1.2
const KNOCK_SPEED_CAP := 20.0
## Seconds spent on the ground before getting up, and how much of that is spent
## getting up rather than lying there.
const CRASH_TIME := 1.7
const CRASH_RISE := 0.55
## What the body keeps of the impact, in m/s along the ground. A crash is a
## tumble, not a redirection: 200 m/s carried into the slide would take the
## player most of a kilometre from where they hit.
const CRASH_SLIDE := 11.0
## How quickly the tumble sheds that, in m/s².
const CRASH_FRICTION := 9.0
## Seconds the capsule takes to close whatever gap has opened between it and the
## limp body, and the m/s it is allowed to spend doing it. The cap is what keeps
## a bone that has found its way somewhere the capsule cannot follow from firing
## the player across the ground after it.
const CRASH_CHASE_TIME := 0.22
const CRASH_CHASE_SPEED := 26.0
## How far away the body may be and still be worth chasing, metres. Past this it
## is not a tumble that got ahead of the capsule, it is a body somewhere the
## capsule was never going to reach — through a wall, down a shaft, or left
## behind by a teleport. Chasing it then tows the player across the world, which
## is a worse answer than losing sight of them for the second it takes to stand
## back up.
const CRASH_CHASE_REACH := 6.0
## Radians a second the body rolls at, per metre a second of impact, and the
## range that is allowed to reach. Taken from the whole impact rather than from
## the speed left along the ground: a dive straight down has almost no ground
## speed and would otherwise stand bolt upright through its own crash.
const TUMBLE_PER_SPEED := 0.16
const TUMBLE_RATE_RANGE := Vector2(4.0, 13.0)
## How fast the roll winds down, in e-foldings a second.
const TUMBLE_DECAY := 1.6
## How much of the body has to be under water before the feet stop being any use,
## and how little of it has to be left under before they are again. Two numbers
## rather than one, because a swimmer floats at `1 / buoyancy` submerged and a
## single threshold anywhere near that would flicker between stroke and stride.
## The gap reads as: swim once the water is chest deep, stand up again in knee
## deep water with something under the feet.
const SWIM_ENTER := 0.7
const SWIM_EXIT := 0.5
## A flight arriving from the air becomes a swim as soon as more than a skim of
## the feet has crossed the surface. An intentional launch from inside the water
## is exempt until it has cleared the sea.
const FLIGHT_SWIM_ENTER := 0.05
## Seconds a swimmer has to press jump a second time to launch into flight, and
## the reason the first press is not enough: jump is also the up-stroke, so a
## single press has to stay the way a swimmer reaches the surface or nobody can
## surface at all. Holding sprint was the old rule and did the same job, but it
## is a key combination nobody finds; two presses of the one key already in the
## swimmer's hand is the same idea written where it can be discovered.
const SWIM_LAUNCH_WINDOW := 0.4
## How hard the surface has to be crossed before it is worth a splash, in m/s
## along the radius. Wading in makes none.
const SPLASH_SPEED := 3.5

## How far the soles may be off the height field and still be in the snow, in
## metres. A stride is not level and the guard leaves a little slack under the
## feet, so this is a hand's width and not zero.
const PRINT_FOOTING := 0.6
## Ground a tick may cover and still count as walking, in metres. Above the
## 3.4 m a fully wound run covers in a frame, and far below any teleport: this
## is what stops a spawn or a ground-guard rewind stamping a print.
const PRINT_MAX_STEP := 4.5

## Degrees the view opens by, flat out on the ground or in the air. Speed reads as
## how much of the world is in shot, and at 200 m/s there is no scenery close
## enough to read it any other way. Absolute rather than a fraction of the
## player's own field of view, which the Settings screen lets them take to 110
## before this is added to it.
const SPEED_FOV_RUSH := 18.0

# Indexed by CameraMode.
const ARM_LENGTHS := [0.0, 1.9, 3.8]
const SHOULDER_OFFSETS := [0.0, 0.45, 0.62]
## HeroLand gets a brief, level shoulder shot even if the impact arrived while
## the flight camera was pitched into the ground. It does not change the chosen
## camera mode or shoulder; the blend simply borrows the near-third-person
## framing, then returns to the player's selection as the character stands.
const HERO_CAMERA_EYE := 1.18
## Slow enough to be a move you watch happen. The whole shot is only worth
## having if the camera travels to it; arriving there is a cut.
const HERO_CAMERA_IN_RATE := 5.0
const HERO_CAMERA_OUT_RATE := 3.5
## How fast the dive's look pitch is flown up to the horizon during the pose.
## Sized against HERO_LANDING_TIME: four time constants inside the 0.8 s means
## the view is level before the character stands.
const HERO_PITCH_RATE := 5.0
## Ordinary walking follows the body's horizontal motion immediately but eases
## its visible height. The capsule rides every small change between terrain
## triangles; putting those directly through the eye or character mesh makes the
## planet appear to shake and the character rattle. Faster movement and every
## airborne stance bypass this filter.
##
## The rate is set from the ground covered rather than from the clock, which is
## the only form of it that survives the walk being retuned. A filter fixed in
## seconds lags by speed times that many seconds, so the same seven e-foldings
## that were imperceptible at a stroll would have held the body two thirds of a
## metre of hillside behind the collider at a brisk walk — feet through the
## ground going up, floating coming down. Held to a fixed *distance* the lag is
## the same slice of hillside at any pace, and the eye reads it as the body
## being on the ground at both.
const WALK_CAMERA_LAG_METRES := 0.66
## Floor and ceiling on that rate. The floor is what settles the body when it is
## barely moving, where the distance rule on its own would divide by nothing and
## stop tracking altogether.
const WALK_CAMERA_RATE_RANGE := Vector2(4.0, 20.0)
const WALK_CAMERA_RELEASE_RATE := 14.0
const WALK_CAMERA_SPEED_SHARE := 1.35

@export var peer_id := 1
@export var display_name := "Player"

@export_group("Movement")
## Brisk rather than strolling, and the pace the `Walk` clip's stride is scaled
## against. The same arms-swinging stride carries through an ordinary sprint;
## [member arms_back_speed] is the separate threshold for the flat-out pose.
@export var walk_speed := 9.0
## What shift gives immediately, and what a held shift then winds the run up to
## over `run_spool_time`. There is no stamina anywhere in here: the only things
## that end a run are letting go of forward and hitting something.
##
## The spool time is the whole cost of the wind-up, and it is deliberately long:
## the top speed crosses a chunk of ground per second, so reaching it in a few
## seconds means arriving somewhere unread. At 30 s the target climbs about
## 6.6 m/s², which is a shade under the planet's own pull and leaves plenty of
## time to see what is coming and turn off it.
@export var sprint_speed := 13.0
## The ordinary arms-swinging sprint remains active through this speed. Only
## after it is exceeded does the body switch to the both-arms-back, flat-out
## `Run` clip. This is deliberately separate from [member sprint_speed]:
## pressing shift still steps immediately to 13 m/s, then the normal sprint
## winds through to 18 m/s before its posture changes.
@export var arms_back_speed := 18.0
@export var run_top_speed := 205.0
@export var run_spool_time := 30.0
## Extra friction per m/s above a sprint, once forward is released. Zero below a
## sprint, so an ordinary walk still stops on `ground_friction` alone and only a
## real run skids.
@export var coast_drag := 0.8
## Metres of floor snapping per m/s of run, on top of the body's own. At 200 m/s
## the feet cross three and a half metres between frames, and ground that falls
## away faster than the scene's 0.3 m over that distance throws the body into the
## air: without this a run over rolling ground is a series of involuntary jumps.
## Nine centimetres per m/s reaches eighteen metres flat out, which is about what
## a crest on this terrain drops over one frame's worth of ground.
@export var run_snap := 0.09
@export var crouch_speed := 2.3
## Launch speed of a standing jump, m/s. Against the planet's 34 m/s² that is an
## apex of `v² / 68` and an airtime of `v / 17`, so fifteen buys 3.3 m and just
## under nine tenths of a second in the air.
##
## The airtime is the point of the number and the height is a side effect. Space
## in mid-air takes off, and take-off needs `TAKEOFF_CLEARANCE` of clear ground
## underneath — so a jump whose whole arc is shorter than that cannot become a
## flight at all, however early the key is pressed. At 5.6 the apex was 0.46 m
## and it never could: the only ways into the air were a sprint jump and a
## ledge. Twelve leaves rather more than half a second above the line, which is
## a window rather than a frame to hit.
@export var jump_velocity := 15.0
## How much taller a jump gets at the top of a run, as a multiple of the standing
## one. Speed carried into a jump is already kept; this is the run also buying
## height, so a flat-out leap clears things a sprint could not.
##
## Multiplies the standing jump: a flat-out leap is 27 m/s and about eleven
## metres. Speed carried into a clean landing
## is safe; only meeting a steep face turns the leap into a crash.
@export var jump_speed_gain := 0.8
## Grace windows that make jumping forgiving: `coyote_time` still lets you jump
## just after walking off an edge, `jump_buffer` remembers a press made just
## before landing.
@export var coyote_time := 0.12
@export var jump_buffer := 0.12
@export var ground_accel := 60.0
@export var ground_friction := 48.0
## Deliberately weak, so speed carried into a jump survives the flight.
@export var air_accel := 14.0

@export_group("Steps")
## Ledges up to about shin height are climbed on the way past, so kerbs and prop
## edges do not stop a run dead.
@export var step_height := 0.3
## Seconds for the visuals to catch up after a step, so a climb eases instead of
## snapping the camera upwards.
@export var step_smooth_time := 0.08

@export_group("Flight")
## Hovering speed, and the speed a held boost winds up to. Deliberately an order
## of magnitude apart: the point of the boost is that the world changes character
## on the way up, not that the character gets a little brisker.
##
## The hover is faster on the level and on the way down than it is straight up.
## Climbing is the one direction that is worked for, so it is the one direction
## that is not free; everything else reads as gliding and wants the pace to match.
@export var float_speed := 20.0
@export var climb_speed := 11.0
@export var fly_speed := 1000.0
## Seconds to cross the whole speed range, on the boost and coasting back off it.
## There is no brake key: the only way down from a thousand metres a second is to
## stop asking for a direction, which is also the only thing a body at that speed
## could plausibly do.
@export var boost_time := 4.0
@export var ease_time := 2.4
## Acceleration onto a new heading, and how much of it is bought back per metre
## per second of cruise. The second term is what makes a turn at 200 m/s a wide
## arc and a turn at hovering speed a pivot.
@export var flight_accel := 34.0
@export var flight_turn := 2.0
## Drag with nothing held. The second term is per m/s carried, because a flat
## rate that stops a hover in a quarter of a second would take half a minute to
## shed a thousand.
@export var flight_drag := 42.0
@export var flight_coast := 0.9
## How close the feet may come to the ground while floating before the flight
## simply ends, in metres. Only while floating: at speed the ground arrives
## faster than any probe could warn about it, and `is_on_floor` catches that.
@export var land_clearance := 1.4

@export_group("Swim")
## Steady stroke, and how quickly the body gets onto it. Slow on purpose: an
## unhurried swim is the contrast the boost below is measured against.
@export var swim_speed := 3.4
@export var swim_accel := 16.0
## What a held sprint winds the stroke up to, and the seconds it takes to get
## there and to coast back off it. The same idea as the flight boost and a fifth
## of its pace: the sea is nine kilometres of open water on this planet and
## crossing it at walking speed is not a swim, it is a wait.
##
## Only ever wound up while a direction is being asked for, for the reason given
## in [method _fly_move] — otherwise a player holding sprint while treading water
## charges a launch they cannot see coming.
@export var swim_sprint_speed := 100.0
@export var swim_boost_time := 6.0
@export var swim_ease_time := 2.0
## Extra stroke acceleration per m/s of the wound-up target. **Must stay above
## [member water_drag]**, and that is a hard requirement rather than a taste: drag
## takes `water_drag * v` off the body every second, so a target the stroke cannot
## push that hard against is a target the body never arrives at. At 2.6 e-foldings
## and a hundred metres a second the stroke has to find 260 m/s² just to stand
## still, against the 16 an unhurried one uses.
@export var swim_surge := 4.0
## Lift as a multiple of the planet's own pull, at full submersion. Written as a
## ratio rather than in m/s² so that retuning gravity does not quietly sink
## everyone: the body settles at `1 / buoyancy` of itself under, which at 1.25 is
## floating with the head and shoulders out.
@export var buoyancy := 1.25
## Share of a flight's velocity carried into the swim it becomes. Water drag
## takes over from there; this is only the small impact loss at the surface.
@export_range(0.0, 1.0) var swim_entry_keep := 0.85
## Drag under the surface, in e-foldings a second. It is what makes an entry from
## a dive stop in tens of metres rather than hundreds. It also reins in an
## intentional underwater flight, which remains a flight until it clears the sea.
@export var water_drag := 2.6

@export_group("Lava")
## Lava borrows the swim stance but not the sea's freedom of movement. These are
## deliberately below walking pace and the surface guard below removes every
## inward component, producing a slow stroke over the crust without a dive.
@export var lava_swim_speed := 2.2
@export var lava_sprint_speed := 5.4
@export var lava_swim_accel := 7.5
@export var lava_coast_drag := 5.8
@export_range(0.0, 1.0) var lava_entry_keep := 0.34

@export_group("Slide")
@export var slide_speed := 10.5
## Horizontal speed needed before crouch turns into a slide instead of a crouch.
@export var slide_entry_speed := 4.6
@export var slide_exit_speed := 3.6
@export var slide_friction := 5.2
@export var slide_max_time := 1.3
## Seconds added to a slide at the top of a run. The slide is as long as the run
## that earned it; see `_start_slide` for why the duration is the dial and the
## friction is solved from it.
@export var slide_time_gain := 2.0
@export var slide_cooldown := 0.4
@export var slide_steer := 2.4

@export_group("Arctic")
## What pack ice does to the walk, as multipliers on the ordinary numbers.
##
## The friction is the whole effect and the acceleration only sells it: ice does
## not push you along, it stops taking anything back, so a stride that would
## have been spent against `ground_friction` is kept and the next one is added to
## it. That reads as accelerating faster even though the accel term barely moves,
## and it is also what makes stopping a problem, which is the point.
@export var ice_friction := 0.06
@export var ice_accel := 1.3
## And what a foot of snow does, which is the opposite of all three: slower to
## reach, slower once reached, and quicker to give up.
@export var snow_speed := 0.6
@export var snow_accel := 0.45
@export var snow_friction := 1.7

@export_group("Look")
@export var mouse_sensitivity := 0.0025
@export var invert_y := false

@export_group("Parry")
@export_range(0.05, 1.0, 0.01) var parry_window := 0.32
@export_range(0.01, 0.5, 0.01) var parry_perfect_window := 0.10
@export_range(0.1, 5.0, 0.05) var parry_cooldown := 1.5

@onready var collider: CollisionShape3D = $CollisionShape3D
@onready var ceiling_check: RayCast3D = $CeilingCheck
@onready var character: Node3D = $Character
## Absent when the .glb was exported without its clips, which the controller has
## to survive: the character is still fully playable, just stiff.
@onready var animator: AnimationPlayer = get_node_or_null("Character/AnimationPlayer")
@onready var head: Node3D = $Head
@onready var camera_arm: SpringArm3D = $Head/CameraArm
@onready var camera: Camera3D = $Head/CameraArm/Camera3D
@onready var aim_ray: RayCast3D = $Head/CameraArm/Camera3D/AimRay
@onready var dust: PlayerDust = $Dust
@onready var hud: CanvasLayer = $HUD
@onready var reticle: Reticle = $HUD/Reticle
## Each HUD line is a label on a drawn plate, and the plate is what gets hidden:
## an empty one would read as a blank sticker over the world.
@onready var target_plate: Control = $HUD/Prompts/TargetPlate
@onready var prompt_plate: Control = $HUD/Prompts/PromptPlate
@onready var target_name: Label = $HUD/Prompts/TargetPlate/Panel/Padding/TargetName
@onready var interact_prompt: Label = $HUD/Prompts/PromptPlate/Panel/Padding/InteractPrompt

var controls_enabled := true

## Set before the node enters the tree to spawn the local player without giving it
## the viewport or the mouse. The home screen does this so it can keep its own
## camera and sweep it into place, which is what makes starting a game read as a
## camera move rather than a cut.
var defer_camera := false

## Set before entering the tree. A tilde-menu dummy uses the same body, clips
## and ability scripts as a player, but it never takes the camera or the mouse.
var training_enemy := false
var _training_move := Vector2.ZERO
var _training_sprint := false
var _training_jump := false
var _training_crouch := false
var _training_jump_edge := false
var _training_land_edge := false
var _training_crouch_edge := false

## Public loadout containers for the current and forthcoming pages.
var equipment := ItemContainer.new(ItemDB.SLOT_ORDER.size())
var hotbar := ItemContainer.new(HOTBAR_SLOTS)
var abilities := ItemContainer.new(ABILITY_SLOTS)
var backpack := ItemContainer.new(BACKPACK_SLOTS)
## Present only in crawler and sandbox sessions. Story and the other modes keep
## the catalogue-id ability row and never instantiate this.
var crawler_kit: CrawlerKit
var crawler_progress: CrawlerProgress
var _crawler_cast_stats: Dictionary = {}
var _crawler_speed_base := 0.0
var _authored_ground_accel := 0.0
var _authored_air_accel := 0.0
var _authored_flight_accel := 0.0
var _authored_boost_time := 0.0
var _authored_ease_time := 0.0
var _full_speeds := Vector4.ZERO
var _full_fly_speed := 0.0
var _full_float_speed := 0.0
var _full_climb_speed := 0.0

## Compatibility alias for pages and tests written against the old rack model.
var weapons: ItemContainer:
	get:
		return hotbar

## What this player is made of, listed on the inventory tab.
## Health is host-authoritative; Speed is wired through to movement.
var stats := PlayerStats.new()
var statuses := CombatStatuses.new()

## Quests and achievements. Local and never replicated — a session shares a world,
## not a diary — which is why this is built here rather than handed down from the
## host with the rest of the spawn metadata.
var journal := Journal.new()
var _achievement_toasts: Array[Dictionary] = []

var _stance: int = Stance.STAND
var _camera_mode: int = CameraMode.FIRST
var _shoulder := 1.0
var _hero_camera_blend := 0.0
## The speed the run has wound up to, which is what the legs are actually asked
## for. It survives letting go of shift — that is the whole point of winding it
## up — and only forward being released or something solid takes it away.
var _run_speed := 0.0
var _slide_time := 0.0
## This slide's own length and the friction solved to fit it, both fixed when it
## started, because both are proportional to the run that earned it.
var _slide_span := 0.0
var _slide_drag := 0.0
var _slide_ready_in := 0.0
var _coyote_left := 0.0
var _jump_buffered := 0.0
var _pitch := 0.0
## Mouse yaw collected on render/input frames and consumed by the next physics
## tick. Physics interpolation can only smooth a transform whose movement stays
## on that fixed clock; writing the body directly from mouse events defeats it.
var _pending_yaw := 0.0
var _eye_height := EYE_HEIGHTS[Stance.STAND]
## Distance the visuals still trail the collider by after a step, always <= 0.
var _step_offset := 0.0
## Smoothed world-space radius of the walking body. The head and visible
## character remain children of the physics-interpolated collider, so the
## difference from its unfiltered radius is applied as local counter-motion.
var _walk_camera_radius := 0.0
var _walk_camera_offset := 0.0
var _walk_camera_tracking := false
## The speed flight is currently asking for, which the boost and the brake move
## and the velocity chases. Holding the target apart from the velocity is what
## lets the boost read as a long wind-up rather than as raw acceleration.
var _cruise := 0.0
## The same, for a swim. Separate from `_cruise` rather than shared, because an
## intentional underwater launch clamps that one to a hover and a swimmer
## surfacing into a launch would inherit whichever of the two ran last.
var _stroke := 0.0
## Seconds left face down after a crash, and how far the body has rolled getting
## there. The roll is an angle rather than a clip because there is no crash clip
## to play: the tumble is the body's own lean pivot driven round instead.
var _crash_left := 0.0
var _hero_left := 0.0
## Landing pose selected by the ability definition that committed this landing.
## Ordinary high-speed flight keeps the same HeroLand fallback.
var _hero_clip := "HeroLand"
## Meteor punch: the launch direction. Homing can turn it toward a locked mob.
var _meteor_along := Vector3.FORWARD
var _meteor_lock: Node
var _meteor_speed := 0.0
var _meteor_travelled := 0.0
var _meteor_range := 0.0
var _meteor_top_speed := 0.0
## Whether it was launched out of a flight, which is what decides where an
## unspent punch puts the player back.
var _meteor_flew := false
## Set once the range is spent from a standing launch: the punch keeps its pose
## and its fist but gravity has it now, and it ends at the ground.
var _meteor_falling := false
## Where the fist was at the end of the previous tick, so a tick's damage is a
## swept volume rather than a stamp at wherever the body happened to land.
var _meteor_fist := Vector3.ZERO
## Seconds since the fist last dealt damage, against [constant
## METEOR_DAMAGE_STEP].
var _meteor_since_sweep := 0.0
## Numbers from the ability's catalogue entry, kept here for the duration of the
## flight so the movement code does not have to hold a reference to the ability.
var _meteor_stats: Dictionary = {}
## Ground height a punch landed on, and how long is left to watch it for the
## crater that punch asked for. Zero when no hole is owed.
var _crater_floor := 0.0
var _crater_left := 0.0
var _tumble := 0.0
var _tumble_rate := 0.0
## How far the limp bones sat above the capsule's feet when the crash began. The
## height the capsule tries to hold over the body while it is off the ground; see
## [method _crash_move].
var _crash_body_lift := 0.0
## Crashes since the body spawned. Only the harness reads it.
var _crashes := 0
## What the flight was doing at the start of the last frame it flew. The speed at
## the moment of a collision is already gone by the time the collision can be
## noticed, so this is what says whether the ground was landed on or hit.
var _flight_velocity := Vector3.ZERO
## The jump press that entered flight is consumed until released. Jump is also
## flight's climb control; without this latch one press did both jobs and bent a
## fast horizontal jump upward on the first flying frame.
var _flight_jump_latched := false
## Remaining flight in crawler. 1 is a full tank; the HUD blue bar reads this
## instead of the parry shield.
var _flight_fuel := 1.0
## A flight deliberately launched by a swimmer may stay a flight under water.
## Once it reaches air this is cleared, so coming back through the surface takes
## the ordinary flight-to-swim path.
var _underwater_launch := false
## 0 hovering upright, 1 flat out, smoothed. It drives the body's lean, the
## camera's field of view and which of the two flight clips plays, and all three
## would pop on landing if they read the speed directly.
var _fly_blend := 0.0
## The same, for a swim: 0 treading water, 1 laid out along the stroke. Separate
## from `_fly_blend` because that one also opens the field of view, and a 3.4 m/s
## breaststroke has no business doing that.
var _swim_blend := 0.0
## How much of the swim boost is engaged, smoothed: 0 on the unhurried stroke, 1
## wound right up. This is the swim's half of the field of view, and it is a
## second number rather than `_swim_blend` for the reason written above that one —
## the lean is finished by the second stroke and the rush has barely started.
var _swim_rush := 0.0
## The same, for a run: 0 at a sprint, 1 flat out along the ground.
var _run_blend := 0.0
## Time left on the window a swimmer's second jump press has to land in to become
## a take-off. See [constant SWIM_LAUNCH_WINDOW].
var _swim_launch_left := 0.0
## The scene's own floor snapping, put back when the feet come down. Snapping is
## what would otherwise pull a low hover onto the ground.
var _floor_snap := 0.0
var _planet: Planet
var _lava_field: Node
var _lava_state: Dictionary = {}
var _on_lava := false
## Whether there was ground under the feet at the end of the last physics frame,
## by the height field rather than by the collider. Set in [method _catch_ground],
## read through [method _grounded]. A frame stale, which at a walk is a couple of
## centimetres and at a run is ground the guard has already had its say about.
var _footed := false
## Radius the height field puts the ground at under the body, as of the last
## [method _catch_ground], or negative where there is no planet to measure from.
## Kept so the ragdoll can be handed the number the guard has just worked out
## rather than working it out again. A sample is 2 us — cheap enough that the
## sweep below spends twenty of them a tick without it showing — so this is
## tidiness, not thrift, and anything that wants its own may take one.
var _ground_radius := -1.0
## Where this physics tick's movement started, so the height field can be asked
## about the path the body took and not only about where it ended up. Written
## once at the top of [method _simulate_local_player], which is the one place
## every move in this file goes through.
var _swept_from := Vector3.ZERO
## Whether this physics tick began with ground under the feet. A grounded stride
## starts on the height field by definition and must not be treated as a flight
## path entering it; see [method _rewind_to_entry].
var _swept_grounded := false
## How arctic the ground under the feet is, 0 to 1, and whether that ground is
## pack ice rather than snow over land. Read once a tick by
## [method _read_surface] because the walk needs them *before* it accelerates,
## and [method _catch_ground] — the only other place that talks to the height
## field — does not run until after.
var _frost := 0.0
var _on_ice := false
## Metres walked since the last footprint was put down, which foot is next, and
## where the body was when the count was last taken. The last of the three is
## kept here rather than reusing [member _swept_from] because prints are tracked
## for remote players too, and nothing writes that one for a body that is
## interpolated rather than simulated.
var _since_print := 0.0
var _left_foot := false
var _print_from := Vector3.INF
## The ragdoll on the character's skeleton, or null on a body whose .glb came
## without one — in which case a crash falls back to the tumble in [method _lay_out].
var _ragdoll: Ragdoll
var _dead := false
## What the death screen says happened, decided by the host at the killing blow
## and carried in the combat snapshot. The hit that did it is dropped straight
## afterwards, so nothing downstream can work this out for itself later.
var _death_cause := ""
## Local player only, and only while they are dead.
var _death_screen: DeathScreen
## Seconds the local player has been holding E over a downed teammate.
var _revive_elapsed := 0.0
var _stagger_left := 0.0
## Damage/throw ragdolls do not start blending upright until they have landed.
var _forced_ragdoll := false
var _forced_recovery_started := false
var _forced_ragdoll_left := 0.0
var _grabbed := false
var _lassoed := false
var _lasso_source_peer := 0
var _grab_socket_path := NodePath()
var _grab_socket_node: Node3D
var _grab_offset := Transform3D.IDENTITY
var _parry_window_left := 0.0
var _parry_perfect_left := 0.0
var _parry_cooldown_left := 0.0
var _parry_request_sequence := 0
var _last_parry_request_sequence := 0
var _parry_event_sequence := 0
var _last_parry_event_sequence := 0
var _combat_event_sequence := 0
var _host_combat_publish_sequence := 0
var _last_combat_request_sequence := 0
var _last_combat_event_sequence := 0
var _beam_request_sequence := 0
var _last_beam_request_sequence := 0
var _host_beam_sequence := 0
var _last_beam_sequence := 0
var _projectile_request_sequence := 0
var _last_projectile_request_sequence := 0
var _host_projectile_sequence := 0
var _last_projectile_sequence := 0
var _projectile_result_sequence := 0
var _projectile_result: int = ProjectileRequestState.REJECTED
var _ability_explosion_request_sequence := 0
var _last_ability_explosion_request_sequence := 0
var _host_ability_explosion_sequence := 0
var _last_ability_explosion_sequence := 0
var _ability_wall_request_sequence := 0
var _last_ability_wall_request_sequence := 0
var _host_ability_wall_sequence := 0
var _last_ability_wall_sequence := 0
var _ability_wall_result_sequence := 0
var _ability_wall_result: int = ProjectileRequestState.REJECTED
var _ability_field_request_sequence := 0
var _last_ability_field_request_sequence := 0
var _host_ability_field_sequence := 0
var _last_ability_field_sequence := 0
var _delayed_blast_request_sequence := 0
var _last_delayed_blast_request_sequence := 0
var _host_delayed_blast_sequence := 0
var _last_delayed_blast_sequence := 0
var _delayed_blast_result_sequence := 0
var _delayed_blast_result: int = ProjectileRequestState.REJECTED
var _host_impact_cast_sequence := 0
var _last_impact_cast_sequence := 0
var _host_hero_punch_sequence := 0
var _last_hero_punch_sequence := 0
var _combat_state_sequence := 0
var _last_combat_state_sequence := 0
var _feedback_sequence := 0
var _last_feedback_sequence := 0
var _grab_sequence := 0
var _last_grab_sequence := 0
var _respawn_sequence := 0
var _parry_shield: ParryShield
var _juke_left := 0.0
var _juke_cooldown_left := 0.0
var _juke_along := Vector3.ZERO
var _juke_carry := Vector3.ZERO
var _juke_request_sequence := 0
var _last_juke_request_sequence := 0
var _juke_event_sequence := 0
var _last_juke_event_sequence := 0
var _juke_ghost_acc := 0.0
var _ward_bubble: CrawlerWardBubble
var _ward_up := false
var _ward_hits_left := 0
var _ward_recharge := 0.0
var _missile_cooldown := 0.0
var _mine_cooldown := 0.0
var _repeater_cooldown := 0.0
var _fool_cape_lock := 0.0
var _fool_cape_rng := RandomNumberGenerator.new()
var _fool_cape_distance_override := -1.0
var _fool_cape_dir_override := Vector3.ZERO
var _gold_cape_left := 0.0
var _gold_cape_cooldown_left := 0.0
var _gold_cape_request_sequence := 0
var _last_gold_cape_request_sequence := 0
var _gold_cape_event_sequence := 0
var _last_gold_cape_event_sequence := 0
var _gold_cape_sparkle_acc := 0.0
var _gold_cape_light: OmniLight3D
var _juke_struck: Dictionary = {}
var _dodge_rng := RandomNumberGenerator.new()
## When >= 0, apply_damage uses this instead of a random roll. Tests set it.
var _dodge_roll_override := -1.0
## Present only on the owning peer.
var _combat_feedback: CombatFeedback
## Whether the feet were under the surface last frame. Only the change matters —
## it is what a splash is drawn from — and it is tracked for remote players too,
## so everyone sees everyone else go in.
var _submerged := false
var _character_meshes: Array[MeshInstance3D] = []
## Body slot to the item worn in it, so only garments that changed are reloaded.
var _worn: Dictionary = {}
var _menu_open := false
var _cutscene_hud := false
var _combat_pos := Vector3.ZERO
var _combat_pos_frame := -1
## Which CharacterDB body this player is wearing. Drives the .glb under
## `character`, the collider heights, and which apparel is allowed on it.
var _body_id := CharacterDB.DEFAULT_BODY
## Texture scheme on that body. Kept apart from `_body_id` because both robotic
## designs share one skeleton, collider and wardrobe.
var _skin_id := ""
var _body_height := 1.45
var _body_eye := 1.29
var _body_lean := LEAN_PIVOT
## Sparse slot/"body" → Color, applied after SurfaceSkin so a tint washes the
## authored albedo rather than replacing the material.
var _tints: Dictionary = {}
## Walk, sprint, crouch and arms-back thresholds as the exports were authored,
## captured before the Speed stat is allowed to scale them. Kept because the
## stat is a multiplier over all four: reading them back off themselves would
## compound every change, so a player set to 6 m/s and back to 4.6 would not end
## up where it started.
var _authored_speeds := Vector4.ZERO

## The numbered slot most recently selected, whether it is currently drawn, and
## the item id actually in the hands.
var _weapon_slot := 0
## Selected ability hotbar index. Scroll, click, and keys 1-4 change this;
## click fires the selected slot.
var _ability_slot := 0
## Slot started by the current left-click, so a scroll mid-hold still releases
## the ability that was actually pressed.
var _held_ability_slot := -1
var _hotbar_drawn := false
var _held := ""
var _held_mesh: MeshInstance3D
var _weapon_pose: WeaponPose
var _roar_pose: RoarPose
var _weapon_pose_before_roar := true
var _roar_held_arms := false
var _overdrive_left := 0.0
var _overdrive_boost := 0.0
var _overdrive_body_scale := 1.0
var _overdrive_card_uid := ""
var _overdrive_mods: Array[CrawlerCard] = []
var _base_capsule_radius := 0.32
var _weapon_bar: WeaponBar
## Built for the local player only, in [method _ready].
var _ability_controller: AbilityController
## Built on demand, on every peer: a remote player's beams are driven by the
## packets their machine sends, not by an ability of ours.
var _laser_beams: LaserBeams
var _lightning_bolts: LightningBolts
## Also built on demand and also on every peer, and for the same reason: the
## stance a punch is drawn from replicates, the ability behind it does not.
var _meteor_shock: MeteorShock
## Container transfers emit once for each side. Coalescing their persistence to a
## deferred write records the completed move and prevents save/change recursion.
var _applying_loadout := false
var _loadout_save_queued := false
var _saving_loadout := false
## Private loadout state is mirrored to the server in coalesced, reliable
## snapshots. The generation is advanced only by authoritative world operations;
## it makes a snapshot already in flight before a drop/pickup harmless instead of
## letting it restore the item the server just moved.
var _loadout_snapshot_queued := false
var _loadout_snapshot_revision := 0
var _server_snapshot_revision := 0
var _inventory_generation := 0
var _server_has_loadout_snapshot := false
var _confirmed_drop_ids: Dictionary = {}
var _received_pickup_ids: Dictionary = {}
var _waypoints: WaypointLayer
## Tilde opens the planet-wide navigation overlay. It is deliberately false on
## spawn: no landmark, including Vacationer's Landing, is ambient HUD furniture. The
## compact diagnostic plate follows the same toggle so it is absent from ordinary
## play and available beside the navigation context when requested.
var _waypoints_wanted := false
## Where the player is, in terms that can be read out to somebody else. Hidden
## until the tilde navigation overlay is requested.
var _coordinates: CoordinatePlate
var _coordinates_wanted := false
var _minimap: CityMinimap
var _land_patches: LandPatchOverlay
## Present only on the owning peer.
var _combat_hud: Node
## Charge left per weapon id, kept while a weapon is put away so switching is not
## a way to refill it. Fractional, because it trickles back up.
var _cells: Dictionary = {}
var _cell_pause := 0.0
var _base_fov := 75.0
var _clip := ""
## Hold-B animation picker. `_anim_preview` stays after release so a clicked
## clip can be watched; walking clears it.
var _anim_picker: AnimationPicker
var _anim_hold := 0.0
var _anim_preview := ""
var _ability_clip := ""
var _ability_clip_left := 0.0
var _beam_root := 0.0
var _beam_root_wanted := 0.0
var _beam_look_scale := 1.0
var _field_cast := false
## Reverse Death_C on the Tide Margin pad. Armed at spawn/respawn, held
## while the home-screen body is still hidden, then consumed once.
var _arrival_armed := false
var _arrival_pending := false
var _arrival_left := 0.0
var _arrival_clip := ""
var _arrival_speed := 1.0
## One-shot unlock presentation: turn to the new mark, blink it in with a radar
## pulse, then fade it. Tilde stays closed; later views use the overlay.
var _reveal_landmark: Landmark
var _reveal_left := 0.0
var _reveal_age := 0.0
var _reveal_queue: Array[Landmark] = []
var _revealed_waypoints: Dictionary = {}
var _opening_reveal_done := false
var _opening_reveal_wait := 0.0
var _land_left := 0.0
var _was_airborne := false
var _airborne_time := 0.0
## Fastest downward speed held during the current arc. Landing has already spent
## its velocity by the time the presentation pass sees the feet come down, so the
## previous airborne frames are the only honest measure of how large its dust
## ring should be.
var _landing_speed := 0.0

var _sync_elapsed := 0.0
var _target_transform := Transform3D.IDENTITY
var _target_velocity := Vector3.ZERO
var _target_pitch := 0.0
var _host_last_position := Vector3.ZERO
var _host_has_state := false
## Seconds the remote target has been carried forward on its own velocity since
## the last packet, so a peer that has gone quiet coasts to a stop rather than
## flying off on the last heading it was seen holding.
var _extrapolated := 0.0


func _ready() -> void:
	if training_enemy:
		add_to_group(&"training_enemies")
	else:
		add_to_group("network_players")
	add_to_group(DamageHit.COMBATANT_GROUP)
	_dodge_rng.randomize()
	floor_max_angle = deg_to_rad(MAX_WALK_SLOPE_DEGREES)
	var settings := get_node_or_null("/root/SettingsManager")
	if settings != null and settings.has_method("get_setting"):
		mouse_sensitivity = float(settings.call("get_setting", &"gameplay", &"mouse_sensitivity", 0.35)) / 140.0
		invert_y = bool(settings.call("get_setting", &"gameplay", &"invert_y", false))
		camera.fov = float(settings.call("get_setting", &"gameplay", &"fov", 75.0))

	_base_fov = camera.fov
	_floor_snap = floor_snap_length
	_cruise = float_speed
	_run_speed = walk_speed

	# The exports are where feel is tuned, so the stat starts from them rather than
	# from its own table default, and the table's figure is only a fallback for
	# anything holding stats without a body.
	_authored_speeds = Vector4(walk_speed, sprint_speed, crouch_speed, arms_back_speed)
	stats.set_base(PlayerStats.SPEED, walk_speed)
	stats.changed.connect(_on_stat_changed)
	statuses.changed.connect(_on_status_changed)

	if not training_enemy and not journal.completed.is_connected(_on_journal_completed):
		journal.completed.connect(_on_journal_completed)
	_prepare_crawler_loadout()
	_apply_crawler_limits()
	for index in ItemDB.SLOT_ORDER.size():
		equipment.set_filter(index, ItemDB.SLOT_ORDER[index])
	equipment.changed.connect(_on_equipment_changed)
	for index in HOTBAR_SLOTS:
		hotbar.set_filter(index, ItemDB.HOTBAR)
	hotbar.changed.connect(_on_weapons_changed)
	for index in abilities.size():
		abilities.set_filter(index, ItemDB.ABILITY)
	abilities.changed.connect(_on_abilities_changed)
	for index in BACKPACK_SLOTS:
		backpack.set_filter(index, ItemDB.BACKPACK)
	backpack.changed.connect(_on_backpack_changed)
	# Local players take the saved look; remote peers get apply_look from the
	# spawn metadata a moment later, which swaps the body before the first frame
	# of gameplay if it differs from the scene default. Training enemies keep
	# the scene body until the creator copies the live player's look.
	if peer_id == multiplayer.get_unique_id() and not training_enemy:
		apply_look(CharacterDB.load_look())
		_restore_crawler_progress()
		if crawler_kit != null:
			sync_crawler_ability_bar()
			crawler_kit.restore_or_seed()
		_apply_meta_progress()
	else:
		_bind_character_nodes()
		_character_meshes = SurfaceSkin.apply(character, true)
		_prepare_animations()
		_add_weapon_pose()
		_add_roar_pose()
		_add_ragdoll()
	# The arm would otherwise pull the camera in on our own capsule, and the aim
	# ray would report us as the thing under the crosshair in third person.
	camera_arm.add_excluded_object(get_rid())
	aim_ray.add_exception(self)
	_capture_base_capsule_radius()
	_apply_stance(_stance)
	_parry_shield = ParryShield.new()
	_parry_shield.name = "ParryShield"
	add_child(_parry_shield, false, Node.INTERNAL_MODE_BACK)
	_parry_shield.fit_body(_body_height)
	_ward_bubble = CrawlerWardBubble.new()
	_ward_bubble.name = "CrawlerWardBubble"
	add_child(_ward_bubble, false, Node.INTERNAL_MODE_BACK)
	_ward_bubble.fit_body(_body_height)

	# The plate is drawn behind the padding rather than behind the wrapper, so it
	# hugs the text instead of spanning the screen.
	for panel: PanelContainer in [
		$HUD/Prompts/TargetPlate/Panel,
		$HUD/Prompts/PromptPlate/Panel,
	]:
		RedHudTheme.panel(panel)
	RedHudTheme.label(target_name, 14)
	RedHudTheme.label(interact_prompt, 14)

	var is_local := peer_id == multiplayer.get_unique_id() and not training_enemy
	camera.current = is_local and not defer_camera
	hud.visible = is_local and not defer_camera
	_target_transform = global_transform
	_host_last_position = global_position
	if training_enemy:
		_ability_controller = AbilityController.new()
		_ability_controller.name = "Abilities"
		add_child(_ability_controller)
	elif is_local:
		_combat_feedback = CombatFeedback.new()
		_combat_feedback.name = "CombatFeedback"
		add_child(_combat_feedback)
		_combat_feedback.configure(camera, hud)
		# Only the local player simulates their own abilities. A remote peer's
		# beam arrives as broadcast effects, the same way their shots do.
		_ability_controller = AbilityController.new()
		_ability_controller.name = "Abilities"
		add_child(_ability_controller)
		# Only the local player needs a bar: each one carries a viewport for its
		# icons, and nobody sees anyone else's HUD.
		_weapon_bar = WeaponBar.new()
		hud.add_child(_weapon_bar)
		_weapon_bar.bind_loadout(abilities, hotbar)
		_weapon_bar.bind_ability_controller(_ability_controller)
		_weapon_bar.select(_ability_slot)
		# Behind the bar, so a waypoint pinned to the bottom of the screen does
		# not sit over the weapon icons.
		_waypoints = WaypointLayer.new()
		hud.add_child(_waypoints)
		hud.move_child(_waypoints, 0)
		_waypoints.bind(camera)
		_waypoints.enabled = _waypoints_wanted
		_waypoints.visible = _waypoints_wanted
		_coordinates = CoordinatePlate.new()
		_coordinates.body = self
		_coordinates.aim_ray = aim_ray
		_coordinates.visible = _coordinates_wanted
		hud.add_child(_coordinates)
		_land_patches = _find_land_patches()
		_apply_tilde_overlay()
		_combat_hud = load("res://ui/combat/combat_hud.gd").new()
		_combat_hud.configure(self, hud, _coordinates, _weapon_bar)
		hud.add_child(_combat_hud)
		_minimap = CityMinimap.new()
		_minimap.bind(_coordinates)
		hud.add_child(_minimap)
		CrtType.watch(hud, false)
		# Only the person who died is told about it. Everyone else sees a body.
		died.connect(_on_died)
		respawned.connect(_on_respawned)
		if not defer_camera:
			Input.mouse_mode = Input.MOUSE_MODE_CAPTURED
		# A host already owns its canonical containers. A client sends the
		# private part of the look after _ready has finished, so the server has a
		# complete mirror before it accepts a finite-item operation.
		if multiplayer.is_server():
			_server_has_loadout_snapshot = true
		else:
			_queue_loadout_snapshot()


## Takes the viewport, the mouse and the HUD, for a player spawned with
## [member defer_camera] set. Idempotent: a player that already has them keeps
## them.
func look_pitch() -> float:
	return _pitch


func set_look_pitch(value: float) -> void:
	_pitch = clampf(value, -1.48, 1.48)
	_target_pitch = _pitch
	if head != null:
		head.rotation.x = _pitch


func take_camera() -> void:
	defer_camera = false
	if peer_id != multiplayer.get_unique_id():
		return
	visible = true
	camera.current = true
	hud.visible = true
	controls_enabled = true
	Input.mouse_mode = Input.MOUSE_MODE_CAPTURED
	if _arrival_pending:
		play_spawn_arrival()
	elif CrawlerRules.active():
		_try_opening_waypoint_reveal()


func set_camera_mode(mode: CameraMode) -> void:
	_camera_mode = mode


func reset_network_state(at_transform: Transform3D) -> void:
	_target_transform = at_transform
	_host_last_position = at_transform.origin
	_host_has_state = true
	_extrapolated = 0.0


func warp_to(at: Vector3, look_along := Vector3.ZERO,
		keep_momentum := false, snap_ground := true) -> bool:
	if not at.is_finite() or _dead:
		return false
	if multiplayer.has_multiplayer_peer() and not multiplayer.is_server():
		return false
	var posed := _warp_transform_at(at, look_along, snap_ground)
	var carry := velocity if keep_momentum and velocity.is_finite() else Vector3.ZERO
	_apply_warp(posed, carry)
	if _has_listeners():
		_apply_warp.rpc(posed, carry)
	return true


func _warp_transform_at(at: Vector3, look_along: Vector3,
		snap_ground := true) -> Transform3D:
	var world_planet := planet()
	var up := _up()
	var point := at
	if world_planet != null:
		var local := world_planet.to_local(at)
		if local.length_squared() > 0.0001:
			var surface := world_planet.surface_position(local)
			up = world_planet.up_at(surface)
			if not snap_ground:
				var floor := maxf(_stance_height(_stance) * 0.5, 0.45)
				var altitude := (at - surface).dot(up)
				if altitude < floor:
					point = surface + up * floor
			elif _stance == Stance.FLY:
				var altitude := (at - surface).dot(up)
				if altitude < 0.6:
					point = surface + up * 0.6
			else:
				point = surface + up * maxf(_stance_height(_stance) * 0.5, 0.45)
	var forward := look_along
	if forward.length_squared() < 0.001:
		forward = -global_basis.z
	forward = forward - up * forward.dot(up)
	if forward.length_squared() < 0.001:
		forward = -global_basis.z
	forward = forward.normalized()
	return Transform3D(Basis.looking_at(forward, up), point)


func _unhandled_input(event: InputEvent) -> void:
	if training_enemy or peer_id != multiplayer.get_unique_id() \
			or not controls_enabled:
		return
	# Clicking back into a window that has let the cursor go is only ever about
	# taking it again, so it happens before the click can also be an attack.
	if event is InputEventMouseButton and event.pressed and Input.mouse_mode != Input.MOUSE_MODE_CAPTURED:
		if _anim_picker != null:
			return
		Input.mouse_mode = Input.MOUSE_MODE_CAPTURED
		return

	if event is InputEventMouseMotion and Input.mouse_mode == Input.MOUSE_MODE_CAPTURED \
			and _reveal_left <= 0.0:
		# Sighted down the optic, the same hand movement should cover less ground.
		var sensitivity := mouse_sensitivity * (1.0 - 0.5 * _aim_amount()) \
			* beam_look_scale()
		# About the body's own up rather than the parent's. `rotate_y` takes its
		# axis in parent space, which on a sphere is the way up at exactly one
		# point on it; anywhere else it tips the body off the ground instead of
		# turning it on the spot, and the radial alignment then hauls it back.
		# What is left of the turn is the part of the mouse that happened to lie
		# along the local up, which near the equator of the parent's Y is none of
		# it — a view that will not turn.
		_pending_yaw -= event.relative.x * sensitivity
		var vertical_sign := -1.0 if not invert_y else 1.0
		_pitch = clampf(_pitch + event.relative.y * sensitivity * vertical_sign, -1.48, 1.48)
		head.rotation.x = _pitch
	elif event.is_action_pressed("cycle_camera"):
		_camera_mode = wrapi(_camera_mode + 1, 0, CameraMode.size())
	elif event.is_action_pressed("swap_shoulder"):
		# L flips the camera shoulder. With the tilde map up it still founds
		# the MeshMaker yard city instead of flipping the camera.
		if _try_found_yard_city():
			get_viewport().set_input_as_handled()
		else:
			_shoulder = -_shoulder
	elif event.is_action_pressed("cape_ability"):
		if request_cape_ability():
			get_viewport().set_input_as_handled()
	elif event.is_action_pressed("interact"):
		if nearest_downed_teammate() != null:
			get_viewport().set_input_as_handled()
		elif CrawlerRules.active():
			if CrawlerRules.training_active():
				_open_training_menu()
			elif CrawlerRules.duel_active():
				_open_duel_end_menu()
			elif not _interact() and in_crawler_city():
				_open_crawler_field_menu()
		elif not _interact():
			# Tilde map: E renders the patch city from the live generator.
			# Empty space with the map down still holsters.
			if not _try_found_city_live():
				holster()
	elif event is InputEventKey and event.pressed and not event.echo \
			and event.physical_keycode == KEY_J:
		if _try_place_baked_city():
			get_viewport().set_input_as_handled()
	elif event is InputEventKey and event.pressed and not event.echo \
			and event.physical_keycode == KEY_K:
		if _handle_crawler_auto_key():
			get_viewport().set_input_as_handled()
		elif _try_place_all_baked_cities():
			get_viewport().set_input_as_handled()
	elif event is InputEventKey and event.pressed and not event.echo \
			and event.physical_keycode == KEY_T:
		if _try_place_enemy_creator():
			get_viewport().set_input_as_handled()
	elif event is InputEventKey and event.pressed and not event.echo \
			and event.physical_keycode == KEY_M:
		if _try_open_glorb_spawn_menu():
			get_viewport().set_input_as_handled()
	elif event.is_action_pressed("parry"):
		request_parry()
	elif event.is_action_pressed("aim") and not _weapon_can_aim():
		request_juke()
	elif event.is_action_pressed("waypoints"):
		_waypoints_wanted = not _waypoints_wanted
		_apply_tilde_overlay()
	elif event.is_action_pressed("inventory"):
		_open_game_menu(GameMenu.Tab.HERO)
	elif event.is_action_pressed("pause"):
		_open_game_menu(GameMenu.Tab.SETTINGS)
	elif event.is_action_pressed("holster"):
		holster()
	elif event.is_action_pressed("attack"):
		activate_primary()
	elif event.is_action_released("attack"):
		# A weapon's trigger has no release behaviour. Empty hands release the
		# ability this click started, even if the wheel moved the selection.
		if _held_ability_slot >= 0:
			release_ability(_held_ability_slot)
			_held_ability_slot = -1
	elif event.is_action_pressed("weapon_next"):
		_cycle_ability(1)
	elif event.is_action_pressed("weapon_prev"):
		_cycle_ability(-1)
	else:
		for index in abilities.size():
			if event.is_action_pressed("weapon_%d" % (index + 1)):
				select_ability(index)
				return


func _process(delta: float) -> void:
	_update_step_offset(delta)
	_update_walking_ground_offset(delta)
	_update_body_lean(delta)
	_update_camera(delta)
	_ability_clip_left = maxf(_ability_clip_left - delta, 0.0)
	_tick_spawn_arrival(delta)
	if _opening_reveal_wait > 0.0 and not _opening_reveal_done:
		_opening_reveal_wait = maxf(_opening_reveal_wait - delta, 0.0)
		_try_opening_waypoint_reveal()
	_tick_waypoint_reveal(delta)
	_update_anim_picker(delta)
	_update_animation(delta)
	_update_dust_trails()
	_update_meteor_shock()
	_update_parry_shield()
	_update_ward_bubble()
	_update_juke_afterimages(delta)
	if _weapon_pose != null:
		# Everyone's, not just our own: a remote player's pitch is synced, and their
		# barrel should point where they are looking.
		_weapon_pose.set_pitch(_pitch)
	_sync_roar_pose()
	if peer_id == multiplayer.get_unique_id():
		_update_weapon(delta)
		_update_hud(delta)


func _physics_process(delta: float) -> void:
	_tick_combat(delta)
	if _grabbed:
		_follow_grab_socket()
		_track_water_crossing()
		_track_footprints()
		return
	if _lassoed:
		_track_water_crossing()
		_track_footprints()
		return
	var is_local := peer_id == multiplayer.get_unique_id() and not training_enemy
	# A remote player normally predicts their own movement. Damage reactions are
	# the exception: the host advances the same crash/stagger path and relays it,
	# so a client cannot submit movement that walks out of an authored reaction.
	var host_driven_reaction := not is_local and not training_enemy \
		and _is_host_authority() \
		and (_dead or _forced_ragdoll or _stagger_left > 0.0)
	# A corpse keeps simulating with its controls taken away, because the death
	# screen takes them: a body that stopped there would hang wherever it was
	# killed instead of coming down. Nothing it reads is input —
	# [method _simulate_local_player] puts the dead straight into a crash.
	# Training enemies are local-only dummies: they always run the same body
	# simulation the player does, steered by AI rather than the keyboard.
	if training_enemy \
			or (is_local and (controls_enabled or _dead)) \
			or host_driven_reaction:
		_simulate_local_player(delta)
		if training_enemy:
			_consume_training_edges()
		if is_local:
			_update_target_label()
			journal.track(global_position, get_tree(), delta)
		if not training_enemy:
			_sync_elapsed += delta
			if _sync_elapsed >= SYNC_INTERVAL:
				_sync_elapsed = 0.0
				if _is_host_authority():
					_host_last_position = global_position
					_host_has_state = true
					_apply_state.rpc(global_transform, velocity, _pitch, _stance)
				else:
					_submit_state.rpc_id(1, global_transform, velocity, _pitch, _stance)
	elif not is_local:
		# A packet is 50 ms of travel, which at flight speed is ten metres: sitting
		# on the last one until the next arrives would leave a flying peer a whole
		# building behind where they are. The target is carried forward on its own
		# velocity instead, for a couple of packets' worth and no further.
		if _extrapolated < SYNC_INTERVAL * 2.0:
			_target_transform.origin += _target_velocity * delta
			_extrapolated += delta
		global_transform = global_transform.interpolate_with(_target_transform, minf(delta * 14.0, 1.0))
		velocity = _target_velocity
		_pitch = lerpf(_pitch, _target_pitch, minf(delta * 14.0, 1.0))
		head.rotation.x = _pitch
	# For everyone, and outside both branches: a remote player's position and
	# velocity are both known here, so their entry throws up its own splash
	# without a packet having to be spent saying so.
	_track_water_crossing()
	_track_footprints()


# --- Interaction and clothes ------------------------------------------------

## Whatever is under the crosshair within arm's reach, if it is something that
## can be used. Cast from the camera so it agrees with what the player is looking
## at, and lengthened by the spring arm so third person does not shorten the
## reach measured from the body.
func _interact_target() -> Node:
	var from := camera.global_position
	var query := PhysicsRayQueryParameters3D.create(
		from, from - camera.global_basis.z * (REACH + camera_arm.spring_length))
	query.exclude = DamageHit.rid_list(get_rid())
	var hit := get_world_3d().direct_space_state.intersect_ray(query)
	var collider: Variant = hit.get("collider")
	if not is_instance_valid(collider):
		return null
	return _interactable(collider as Node)


## The nearest thing at or above [param collider] that can be used.
##
## A dropped item is its own collider, but anything built from an imported .glb is
## not: the ship's shape arrives as a [StaticBody3D] somewhere inside a hull whose
## node names MeshMaker chose, and the script that knows what using it means is the
## anchor the whole model hangs off. So the collider is where the search starts
## rather than where it ends.
##
## Bounded rather than walked to the root, because the top of every chain is the
## planet and then the world, and a scene that ever grows an `interact` up there
## should not turn every rock on it into a button.
func _interactable(collider: Node) -> Node:
	var node := collider
	var hops := INTERACT_ANCESTOR_HOPS
	while node != null and hops >= 0:
		if node.has_method("interact") and node.has_method("interact_prompt"):
			return node
		node = node.get_parent()
		hops -= 1
	return null


func _interact() -> bool:
	if _dead or _grabbed or _lassoed:
		return false
	var target := _interact_target()
	if target != null:
		target.call("interact", self)
		return true
	return false


## Tab and Escape are the same menu opened at a different tab. Both are handled
## here rather than in the world, because everything on the menu's first page — the
## containers, the stats, the body — belongs to this player, and the pause overlay
## they replaced had nothing on it that did not.
func _open_game_menu(tab: GameMenu.Tab) -> void:
	if _menu_open:
		return
	var menu := GameMenu.new()
	menu.configure(self)
	menu.show_tab(tab)
	menu.closed.connect(_on_game_menu_closed)
	menu.leave_requested.connect(_on_leave_requested)
	menu.respawn_requested.connect(_on_city_respawn_requested)
	open_menu()
	hud.add_child(menu)
	# The world decides what being in a menu costs: a real stop in single player, a
	# local one in company. Asked after open_menu, which is what took the mouse.
	var world := NetworkManager.active_world as GameWorld
	if world != null:
		world.set_local_pause(true)


func _on_game_menu_closed() -> void:
	# Dying with the menu open leaves the death screen behind it. Closing the
	# menu hands the mouse to that rather than back to the world.
	if is_instance_valid(_death_screen):
		open_menu()
	else:
		close_menu()
	var world := NetworkManager.active_world as GameWorld
	if world != null:
		world.set_local_pause(false)


## Only ever reached on the peer that owns this body; nobody is shown anyone
## else's death. The world is left running underneath: in company it has to be,
## and alone a frozen ragdoll reads as the game having hung rather than as a
## death.
func _on_died(_source_peer: int, cause: String) -> void:
	if CrawlerRules.duel_active():
		var world := DamageHit.game_world_of(self)
		if world != null and world.has_method(&"request_duel_respawn"):
			world.call(&"request_duel_respawn")
		return
	if CrawlerRules.training_active():
		var world := DamageHit.game_world_of(self)
		if world != null and world.has_method(&"request_training_respawn"):
			world.call(&"request_training_respawn")
		return
	if is_instance_valid(_death_screen):
		if CrawlerRules.active():
			_present_crawler_death(cause)
		else:
			_death_screen.set_notice(cause)
		_bind_death_screen_actions()
		return
	_death_screen = DeathScreen.new()
	if CrawlerRules.active():
		_present_crawler_death(cause)
	else:
		_death_screen.set_notice(cause)
	_bind_death_screen_actions()
	open_menu()
	hud.add_child(_death_screen)


func _on_respawned() -> void:
	if not is_instance_valid(_death_screen):
		return
	_death_screen.queue_free()
	_death_screen = null
	# Unless the Tab menu is what is now in front of them, which owns the mouse
	# until it is closed.
	if hud.get_node_or_null("GameMenu") == null:
		close_menu()


## The host decides, as it does for every other way a body changes state. A
## client that asks twice, or asks while alive, is simply ignored.
func _on_respawn_requested() -> void:
	# The world this body is in, rather than whichever one is current: the RPC
	# has to arrive at the same node on the host as it left on the client.
	var world := DamageHit.game_world_of(self)
	if world == null:
		return
	if multiplayer.has_multiplayer_peer() and not multiplayer.is_server():
		world.request_colony_respawn.rpc_id(1)
	else:
		world.request_colony_respawn()


func _bind_death_screen_actions() -> void:
	if not is_instance_valid(_death_screen):
		return
	if not _death_screen.home_requested.is_connected(_on_leave_requested):
		_death_screen.home_requested.connect(_on_leave_requested)
	if not _death_screen.respawn_requested.is_connected(_on_respawn_requested):
		_death_screen.respawn_requested.connect(_on_respawn_requested)


func _on_leave_requested() -> void:
	var world := DamageHit.game_world_of(self)
	if world == null:
		world = NetworkManager.active_world as GameWorld
	if world != null:
		world.leave_session()
		return
	NetworkManager.leave_game()


func _on_city_respawn_requested() -> void:
	var world := DamageHit.game_world_of(self)
	if world == null:
		world = NetworkManager.active_world as GameWorld
	if world == null:
		return
	if multiplayer.has_multiplayer_peer() and not multiplayer.is_server():
		world.request_city_respawn.rpc_id(1)
	else:
		world.request_city_respawn()


## Sparse slot/"body"/"outline" → HTML colour, as CharacterDB stores them, for a
## menu that wants to show what is already applied.
func tints() -> Dictionary:
	var out: Dictionary = {}
	for target: String in _tints:
		out[target] = Color(_tints[target]).to_html()
	return out


## Recolours one garment or the skin, on the body and in the saved look. Called by
## the colour strip on the inventory tab; the tint is not replicated, for the same
## reason the rest of the look is broadcast by whoever changed it rather than by the
## host — see [method broadcast_look].
func set_tint(target: String, colour: Color) -> void:
	_tints[target] = colour
	_apply_tints()
	if peer_id != multiplayer.get_unique_id():
		return
	var look := CharacterDB.load_look()
	var saved: Dictionary = look.get("tints", {})
	saved[target] = colour.to_html()
	look["tints"] = saved
	CharacterDB.save_look(look)


func clear_tint(target: String) -> void:
	_tints.erase(target)
	_apply_tints()
	if peer_id != multiplayer.get_unique_id():
		return
	var look := CharacterDB.load_look()
	var saved: Dictionary = look.get("tints", {})
	saved.erase(target)
	look["tints"] = saved
	CharacterDB.save_look(look)


## The Speed stat is one multiplier over all three speed exports, taken against
## what they were authored as. Scaling them together is what keeps a sprint faster
## than a walk however far the stat is moved.
func _on_stat_changed(id: StringName, value: float) -> void:
	if id == PlayerStats.HEALTH:
		health_changed.emit(stats.health(), stats.base_of(PlayerStats.HEALTH))
		return
	if id != PlayerStats.SPEED:
		return
	var scale := value / maxf(_authored_speeds.x, 0.01)
	walk_speed = _authored_speeds.x * scale
	sprint_speed = _authored_speeds.y * scale
	crouch_speed = _authored_speeds.z * scale
	arms_back_speed = _authored_speeds.w * scale


func _on_status_changed(id: StringName, remaining: float) -> void:
	status_changed.emit(id, remaining)
	if id == CombatStatuses.FLIGHTLESS and remaining > 0.0 \
			and _stance == Stance.FLY:
		_end_flight()


## A menu has the mouse. The body keeps being simulated so it still falls and is
## still synced, but it stops taking input and the crosshair gets out of the way.
func open_menu() -> void:
	_menu_open = true
	controls_enabled = false
	if _weapon_pose != null:
		_weapon_pose.set_aimed(false)
	reticle.visible = false
	prompt_plate.visible = false
	target_name.text = ""
	target_plate.visible = false
	if _waypoints != null:
		_waypoints.visible = false
	if _coordinates != null:
		_coordinates.visible = false
	if _minimap != null:
		_minimap.visible = false
	if _land_patches != null:
		_land_patches.set_overlay_enabled(false)
	if _combat_hud != null:
		_combat_hud.set_menu_open(true)
	Input.mouse_mode = Input.MOUSE_MODE_VISIBLE
	LagTracker.set_frozen(true)
	LagTracker.note("ui", "menu opened")


func close_menu() -> void:
	_menu_open = false
	controls_enabled = true
	reticle.visible = not _cutscene_hud
	# Back to what it was, not to on: the menu is not a reason to undo a toggle.
	_apply_tilde_overlay()
	if _combat_hud != null:
		_combat_hud.set_menu_open(false)
	if not _cutscene_hud:
		Input.mouse_mode = Input.MOUSE_MODE_CAPTURED
	LagTracker.set_frozen(false)
	LagTracker.note("ui", "menu closed")


func set_cutscene_hud(on: bool) -> void:
	_cutscene_hud = on
	if _combat_hud != null and _combat_hud.has_method(&"set_cutscene"):
		_combat_hud.call(&"set_cutscene", on)
	if on:
		reticle.visible = false
		prompt_plate.visible = false
		target_name.text = ""
		target_plate.visible = false
		if _weapon_bar != null:
			_weapon_bar.visible = false
		if _minimap != null:
			_minimap.visible = false
		if _coordinates != null:
			_coordinates.visible = false
		return
	if not _menu_open:
		reticle.visible = true
		if _weapon_bar != null:
			_weapon_bar.visible = true
	_apply_tilde_overlay()


## The look other peers should draw this player in, for someone who has just
## joined and missed the change.
func worn_items() -> PackedStringArray:
	return equipment.items()


func body_id() -> String:
	return _body_id


func skin_id() -> String:
	return _skin_id


## Body, clothes and tints in one shot. Used by the spawn path (metadata) and by
## the local player's own _ready. Swapping the .glb rewires animation, weapon
## pose and ragdoll, because all three hang off the skeleton that just changed.
func apply_look(look: Dictionary) -> void:
	var started := Time.get_ticks_msec()
	var was_applying := _applying_loadout
	_applying_loadout = true
	var next_body := CharacterDB.sanitize_body(str(look.get("body", CharacterDB.DEFAULT_BODY)))
	_skin_id = CharacterDB.sanitize_skin(next_body, str(look.get("skin", "")))
	_tints = {}
	var tint_raw: Variant = look.get("tints", {})
	if tint_raw is Dictionary:
		for key: Variant in tint_raw:
			var parsed := Color.html(str(tint_raw[key]))
			_tints[str(key)] = parsed
	_set_body(next_body)
	var worn := CharacterDB.worn_items(look)
	if worn.is_empty() and look.get("worn", null) == null:
		worn = equipment.items()
	apply_worn(worn)
	# Private containers are absent from remote spawn metadata.
	if look.has("hotbar") or look.has("rack"):
		apply_hotbar(CharacterDB.hotbar_items(look, hotbar.size()))
	if look.has("abilities") and crawler_kit == null:
		apply_abilities(CharacterDB.ability_items(look, abilities.size()))
	if look.has("backpack"):
		apply_backpack(CharacterDB.backpack_items(look, backpack.size()))
	_apply_tints()
	_applying_loadout = was_applying
	var elapsed := Time.get_ticks_msec() - started
	if elapsed >= 4:
		LagTracker.note("look", "apply_look %s in %d ms" % [_body_id, elapsed])


func _set_body(next_body: String) -> void:
	next_body = CharacterDB.sanitize_body(next_body)
	_body_height = CharacterDB.height(next_body)
	_body_eye = CharacterDB.eye_height(next_body)
	_body_lean = CharacterDB.lean_pivot(next_body)
	_bind_character_nodes()
	# player.tscn ships the astronaut. Meta records which .glb is actually under
	# `character`, so a second apply_look with the same id is a no-op and a first
	# apply from the scene default still swaps when the id is settler.
	var mounted := ""
	if character != null and is_instance_valid(character):
		mounted = String(character.get_meta("character_body_id", ""))
	if mounted == next_body and _body_id == next_body:
		return
	_body_id = next_body
	var packed := CharacterDB.scene(next_body)
	if packed == null:
		push_error("OnlinePlayer: missing body scene for '%s'" % next_body)
		return
	LagTracker.note("look", "body swap %s -> %s" % [
		mounted if not mounted.is_empty() else "none", next_body])
	var fresh := packed.instantiate() as Node3D
	fresh.set_meta("character_body_id", next_body)
	# The old body has to leave before the new one arrives: two siblings cannot
	# both be called "Character", and Godot resolves that by renaming the one
	# being added. Everything downstream looks the body up by that name, so the
	# swap used to leave the player with no character at all.
	var parent: Node = self
	var index := -1
	var old := character
	if old != null and is_instance_valid(old):
		parent = old.get_parent()
		index = old.get_index()
		parent.remove_child(old)
		old.free()
	fresh.name = "Character"
	parent.add_child(fresh)
	if index >= 0:
		parent.move_child(fresh, index)
	_worn.clear()
	CharacterRig.normalize_body(fresh)
	_bind_character_nodes()
	_character_meshes = SurfaceSkin.apply(character, true)
	_prepare_animations()
	_add_weapon_pose()
	_add_roar_pose()
	_add_ragdoll()
	_apply_stance(_stance)
	if _parry_shield != null:
		_parry_shield.fit_body(_body_height * overdrive_size_scale())
	if _ward_bubble != null:
		_ward_bubble.fit_body(_body_height * overdrive_size_scale())
	_apply_overdrive_visual()


func _bind_character_nodes() -> void:
	character = get_node_or_null("Character") as Node3D
	animator = get_node_or_null("Character/AnimationPlayer") as AnimationPlayer
	if animator == null and character != null:
		animator = CharacterRig.animator_of(character)


func _apply_tints() -> void:
	# Re-paint from the mesh albedo first so a second dress cannot compound a
	# previous tint into a darker and darker wash.
	var body_tint: Color = _tints.get("body", Color.WHITE)
	for mesh_instance in _character_meshes:
		if mesh_instance == null or not is_instance_valid(mesh_instance):
			continue
		if String(mesh_instance.name).begins_with(Wardrobe.NODE_PREFIX) \
				or (
					mesh_instance.get_parent() != null
					and String(mesh_instance.get_parent().name).begins_with(
						Wardrobe.NODE_PREFIX)
				):
			continue
		SurfaceSkin.paint(
			mesh_instance, {}, String(mesh_instance.name) == "Character")
		if String(mesh_instance.name) == "Character":
			SurfaceSkin.set_texture(mesh_instance,
				CharacterDB.skin_texture(_body_id, _skin_id))
		if body_tint != Color.WHITE:
			SurfaceSkin.tint(mesh_instance, body_tint)
	for slot: String in ItemDB.SLOT_ORDER:
		var garment := Wardrobe.worn_mesh(character, slot)
		if garment == null:
			continue
		SurfaceSkin.paint(garment, {}, true)
		if _tints.has(slot):
			SurfaceSkin.tint(garment, _tints[slot])
	if character != null and is_instance_valid(character):
		SurfaceSkin.apply_outline_tint(character, _tints)


func apply_worn(worn: PackedStringArray) -> void:
	# Routed through the container rather than straight onto the skeleton, so a
	# remote player's look is held in the same place as the local player's and
	# only one function ever adds or removes a garment.
	for index in equipment.size():
		equipment.set_item(index, worn[index] if index < worn.size() else "")


func apply_hotbar(items: PackedStringArray) -> void:
	for index in hotbar.size():
		hotbar.set_item(index, items[index] if index < items.size() else "")


func apply_abilities(items: PackedStringArray) -> void:
	for index in abilities.size():
		abilities.set_item(index, items[index] if index < items.size() else "")


func _prepare_crawler_loadout() -> void:
	if training_enemy or not CrawlerRules.active():
		return
	abilities = ItemContainer.new(CrawlerRules.ABILITY_SLOTS)
	crawler_kit = CrawlerKit.new()
	crawler_kit.bind(self)
	crawler_kit.changed.connect(_on_abilities_changed)
	crawler_progress = CrawlerProgress.new()
	crawler_progress.run_path = CrawlerRun.path
	crawler_progress.bind(self)
	crawler_progress.changed.connect(_on_crawler_progress_changed)
	crawler_progress.leveled_up.connect(_on_crawler_leveled_up)


func _apply_crawler_limits() -> void:
	if training_enemy or not CrawlerRules.active():
		return
	if _full_speeds == Vector4.ZERO:
		_full_speeds = Vector4(walk_speed, sprint_speed, crouch_speed, arms_back_speed)
		_full_fly_speed = fly_speed
		_full_float_speed = float_speed
		_full_climb_speed = climb_speed
		_authored_ground_accel = ground_accel
		_authored_air_accel = air_accel
		_authored_flight_accel = flight_accel
		_authored_boost_time = boost_time
		_authored_ease_time = ease_time
	if _authored_boost_time <= 0.0:
		_authored_boost_time = boost_time
		_authored_ease_time = ease_time
	var fast := CrawlerRules.sandbox_fast()
	var scale := 1.0 if fast else CrawlerRules.SPEED_SCALE
	var accel := CrawlerRules.sandbox_fast_accel()
	walk_speed = _full_speeds.x * scale
	sprint_speed = _full_speeds.y * scale
	crouch_speed = _full_speeds.z * scale
	arms_back_speed = _full_speeds.w * scale
	_authored_speeds = Vector4(walk_speed, sprint_speed, crouch_speed, arms_back_speed)
	_crawler_speed_base = walk_speed
	stats.set_base(PlayerStats.SPEED, walk_speed)
	fly_speed = _full_fly_speed if fast else CrawlerRules.FLY_SPEED
	float_speed = _full_float_speed if fast else CrawlerRules.FLOAT_SPEED
	climb_speed = _full_climb_speed if fast else CrawlerRules.CLIMB_SPEED
	boost_time = _authored_boost_time / accel
	ease_time = _authored_ease_time / accel
	_cruise = float_speed
	_run_speed = walk_speed
	_flight_fuel = 1.0
	_apply_crawler_progress()


func set_sandbox_cheat(cheat: String, on: bool) -> void:
	if training_enemy or not CrawlerRules.sandbox():
		return
	if not _has_listeners() or multiplayer.is_server():
		_publish_sandbox_cheat(cheat, on)
		return
	_request_sandbox_cheat.rpc_id(1, cheat, on)


func _publish_sandbox_cheat(cheat: String, on: bool) -> void:
	if not _has_listeners():
		_apply_sandbox_cheat(cheat, on)
		return
	_apply_sandbox_cheat.rpc(cheat, on)


@rpc("any_peer", "call_remote", "reliable")
func _request_sandbox_cheat(cheat: String, on: bool) -> void:
	if not multiplayer.is_server():
		return
	if multiplayer.get_remote_sender_id() != peer_id:
		return
	_publish_sandbox_cheat(cheat, on)


@rpc("authority", "call_local", "reliable")
func _apply_sandbox_cheat(cheat: String, on: bool) -> void:
	CrawlerRules.set_sandbox_cheat(cheat, on)
	if cheat == CrawlerRules.CHEAT_FAST:
		_apply_crawler_limits()
	elif cheat == CrawlerRules.CHEAT_GOLD and on and crawler_progress != null:
		crawler_progress.grant_sandbox_gold()
	elif cheat == CrawlerRules.CHEAT_MOBS and on:
		_clear_sandbox_mobs()


func _clear_sandbox_mobs() -> void:
	if not _is_host_authority():
		return
	var world := get_parent()
	if world == null:
		return
	var horde := world.get_node_or_null("CrawlerHorde") as CrawlerHorde
	if horde != null:
		horde.clear_wild()


func _apply_tilde_overlay() -> void:
	var marks := _waypoints_wanted and not _menu_open and not _cutscene_hud
	var extras := marks and not CrawlerRules.crawler()
	_coordinates_wanted = _waypoints_wanted and not CrawlerRules.crawler()
	if _waypoints != null:
		# Reveal is a one-shot: keep tilde closed so only that landmark is drawn.
		_waypoints.enabled = _waypoints_wanted and not is_revealing_waypoint()
		_waypoints.visible = marks or is_revealing_waypoint()
	if _coordinates != null:
		_coordinates.visible = extras
	if _land_patches != null:
		_land_patches.set_overlay_enabled(extras)
	if _minimap != null and not extras:
		_minimap.visible = false


func flight_fuel_share() -> float:
	return clampf(_flight_fuel, 0.0, 1.0)


func settle_on_ground() -> void:
	if _stance == Stance.FLY:
		_end_flight()
	velocity = Vector3.ZERO
	_cruise = float_speed
	_flight_velocity = Vector3.ZERO


func arm_spawn_arrival() -> void:
	_arrival_armed = true


func play_spawn_arrival() -> void:
	if training_enemy or not _arrival_armed:
		return
	if not CrawlerRules.active():
		return
	# Home-screen handover makes the body visible while the title camera is
	# still sweeping in. Wait until this player owns the view or the flash
	# is gone before anyone can see it.
	if not visible or defer_camera:
		_arrival_pending = true
		return
	_arrival_armed = false
	_arrival_pending = false
	_start_spawn_arrival()


func spawn_arrival_left() -> float:
	return _arrival_left


func is_playing_spawn_arrival() -> bool:
	return _arrival_left > 0.0


func _start_spawn_arrival() -> void:
	_clip = ""
	_arrival_clip = SPAWN_ARRIVAL_CLIP
	_arrival_speed = SPAWN_ARRIVAL_SPEED
	var duration := 1.8
	if animator != null:
		var actual := CharacterRig.resolve_clip(animator, SPAWN_ARRIVAL_CLIP)
		if animator.has_animation(actual):
			var clip := animator.get_animation(actual)
			if clip != null and clip.length > 0.01:
				duration = clip.length / maxf(absf(SPAWN_ARRIVAL_SPEED), 0.01)
		else:
			_arrival_clip = ""
	_arrival_left = duration
	if not _arrival_clip.is_empty():
		_play(_arrival_clip, _arrival_speed, 0.0)
	_play_spawn_flash()


func _tick_spawn_arrival(delta: float) -> void:
	if _arrival_left <= 0.0:
		return
	_arrival_left = maxf(_arrival_left - delta, 0.0)
	if _arrival_left > 0.0:
		return
	_arrival_clip = ""
	_clip = ""
	_try_opening_waypoint_reveal()


func _try_opening_waypoint_reveal() -> void:
	if _opening_reveal_done or training_enemy or not CrawlerRules.active():
		return
	if defer_camera or not visible:
		return
	var city := _city_waypoint_landmark()
	if city == null:
		_opening_reveal_wait = 2.5
		return
	_opening_reveal_done = true
	_opening_reveal_wait = 0.0
	CrawlerSites.unlock(city)
	reveal_waypoint(city)


func _city_waypoint_landmark() -> Landmark:
	if not is_inside_tree():
		return null
	for node_variant: Variant in get_tree().get_nodes_in_group(CrawlerRules.SITE_GROUP):
		var site := node_variant as CrawlerSite
		if site != null and CrawlerRules.starts_visible(site.site_id):
			return site
	for node_variant: Variant in get_tree().get_nodes_in_group(CrawlerRules.CITY_WAYPOINT_GROUP):
		var mark := node_variant as Landmark
		if mark != null and mark.title == CrawlerRules.CITY_SITE_TITLE:
			return mark
	return null


## Turns the local player toward a newly unlocked landmark and blinks its
## waypoint in outside tilde. After the fade, only tilde shows it again.
func reveal_waypoint(landmark: Landmark) -> void:
	if landmark == null or not is_instance_valid(landmark):
		return
	if _reveal_left > 0.0 and _reveal_landmark != landmark:
		if not _reveal_queue.has(landmark):
			_reveal_queue.append(landmark)
		return
	_begin_waypoint_reveal(landmark)


func notice_waypoint_unlocked(landmark: Landmark) -> void:
	if training_enemy or defer_camera or not CrawlerRules.active():
		return
	if landmark == null or not is_instance_valid(landmark):
		return
	if _is_underfoot_waypoint(landmark):
		return
	if _revealed_waypoints.has(_reveal_key(landmark)):
		return
	reveal_waypoint(landmark)


func is_revealing_waypoint() -> bool:
	return _reveal_left > 0.0


func waypoint_reveal_left() -> float:
	return _reveal_left


func _begin_waypoint_reveal(landmark: Landmark) -> void:
	_reveal_landmark = landmark
	_reveal_age = 0.0
	_reveal_left = WAYPOINT_REVEAL_TURN + WAYPOINT_REVEAL_BLINK \
		+ WAYPOINT_REVEAL_HOLD + WAYPOINT_REVEAL_FADE
	_revealed_waypoints[_reveal_key(landmark)] = true
	_pending_yaw = 0.0
	if _waypoints != null:
		_waypoints.set_reveal(landmark, 0.0, 0.0)
	_apply_tilde_overlay()


func _tick_waypoint_reveal(delta: float) -> void:
	if _reveal_left <= 0.0:
		return
	if _reveal_landmark == null or not is_instance_valid(_reveal_landmark):
		_finish_waypoint_reveal()
		return
	_reveal_age += delta
	_reveal_left = maxf(_reveal_left - delta, 0.0)
	_steer_look_toward(_reveal_landmark.global_position, delta)
	var visual := _waypoint_reveal_visual(_reveal_age)
	if _waypoints != null:
		_waypoints.set_reveal(
			_reveal_landmark, float(visual.alpha), float(visual.pulse))
	_apply_tilde_overlay()
	if peer_id == multiplayer.get_unique_id():
		_update_camera(delta)
	if _reveal_left <= 0.0:
		_finish_waypoint_reveal()


func _finish_waypoint_reveal() -> void:
	_reveal_landmark = null
	_reveal_left = 0.0
	_reveal_age = 0.0
	if _waypoints != null:
		_waypoints.clear_reveal()
	_apply_tilde_overlay()
	if _reveal_queue.is_empty():
		return
	var next := _reveal_queue[0]
	_reveal_queue.remove_at(0)
	reveal_waypoint(next)


func _waypoint_reveal_visual(age: float) -> Dictionary:
	var appear_at := WAYPOINT_REVEAL_TURN * 0.55
	if age < appear_at:
		return {"alpha": 0.0, "pulse": 0.0}
	var t := age - appear_at
	if t < WAYPOINT_REVEAL_BLINK:
		var flashes := 3.0
		var wave := absf(sin(t / WAYPOINT_REVEAL_BLINK * flashes * PI))
		return {"alpha": wave, "pulse": t / WAYPOINT_REVEAL_BLINK}
	t -= WAYPOINT_REVEAL_BLINK
	if t < WAYPOINT_REVEAL_HOLD:
		return {"alpha": 1.0, "pulse": 1.0 + t}
	t -= WAYPOINT_REVEAL_HOLD
	var fade := clampf(1.0 - t / WAYPOINT_REVEAL_FADE, 0.0, 1.0)
	return {"alpha": fade, "pulse": 1.55 + (1.0 - fade)}


func _steer_look_toward(world_point: Vector3, delta: float) -> void:
	if not world_point.is_finite():
		return
	var up := _up()
	if up.length_squared() < 0.5:
		up = Vector3.UP
	up = up.normalized()
	var to := world_point - global_position
	var flat := to - up * to.dot(up)
	if flat.length_squared() > 0.0001:
		var desired := flat.normalized()
		var current := -global_basis.z
		var current_flat := current - up * current.dot(up)
		if current_flat.length_squared() > 0.0001:
			var angle := current_flat.normalized().signed_angle_to(desired, up)
			var step := clampf(
				angle, -WAYPOINT_REVEAL_TURN_RATE * delta, WAYPOINT_REVEAL_TURN_RATE * delta)
			rotate_object_local(Vector3.UP, step)
	_pending_yaw = 0.0
	var from := head.global_position if head != null \
		else global_position + up * _body_eye
	var look := world_point - from
	if look.length_squared() > 0.0001:
		look = look.normalized()
		var wanted := clampf(-asin(clampf(look.dot(up), -1.0, 1.0)), -1.48, 1.48)
		_pitch = lerpf(_pitch, wanted, clampf(delta * 3.2, 0.0, 1.0))
		if head != null:
			head.rotation.x = _pitch


func _is_underfoot_waypoint(landmark: Landmark) -> bool:
	if not landmark is Node3D:
		return true
	var span := global_position.distance_to((landmark as Node3D).global_position)
	if landmark is CrawlerSite:
		return span <= maxf((landmark as CrawlerSite).enter_radius, WAYPOINT_REVEAL_NEAR)
	if landmark is PatchMonument:
		return span <= maxf((landmark as PatchMonument).keepout_radius, WAYPOINT_REVEAL_NEAR)
	return span < WAYPOINT_REVEAL_NEAR


func _reveal_key(landmark: Landmark) -> String:
	if landmark is CrawlerSite:
		var site_id := (landmark as CrawlerSite).site_id
		if not site_id.is_empty():
			return "site:%s" % site_id
	if landmark is PatchMonument:
		var monument_id := (landmark as PatchMonument).monument_id
		if not monument_id.is_empty():
			return "monument:%s" % monument_id
	if not landmark.title.strip_edges().is_empty():
		return "title:%s" % landmark.title.strip_edges()
	return "id:%d" % landmark.get_instance_id()


func _play_spawn_flash() -> void:
	if not is_inside_tree():
		return
	CrawlerArrivalFlashScript.play(self, combat_position(), _up())


func _open_duel_end_menu() -> void:
	if _menu_open or not CrawlerRules.duel_active():
		return
	var menu = load("res://ui/menu/crawler_duel_menu.gd").new()
	if menu.has_method(&"configure"):
		menu.configure(self)
	menu.closed.connect(_on_game_menu_closed)
	open_menu()
	hud.add_child(menu)


func _open_training_menu() -> void:
	if _menu_open or not CrawlerRules.training_active():
		return
	var menu = load("res://ui/menu/crawler_training_menu.gd").new()
	if menu.has_method(&"configure"):
		menu.configure(self)
	menu.closed.connect(_on_game_menu_closed)
	open_menu()
	hud.add_child(menu)


func _open_crawler_field_menu() -> void:
	if _menu_open or CrawlerRules.duel_active() \
			or CrawlerRules.training_active() or not in_crawler_city():
		return
	var menu = load("res://ui/menu/crawler_field_menu.gd").new()
	if menu.has_method(&"configure"):
		menu.configure(self)
	menu.closed.connect(_on_game_menu_closed)
	open_menu()
	hud.add_child(menu)
	var world := NetworkManager.active_world as GameWorld
	if world != null:
		world.set_local_pause(true)


func _try_open_glorb_spawn_menu() -> bool:
	if _menu_open or _dead or hud == null or not CrawlerRules.active():
		return false
	if hud.get_node_or_null("CrawlerGlorbSpawnMenu") != null:
		return false
	var menu = load("res://ui/menu/crawler_glorb_spawn_menu.gd").new()
	if menu.has_method(&"configure"):
		menu.configure(self)
	menu.closed.connect(_on_game_menu_closed)
	open_menu()
	hud.add_child(menu)
	return true


func _restore_crawler_progress() -> void:
	if crawler_progress == null:
		return
	crawler_progress.restore_or_seed()
	refresh_crawler_look()
	CrawlerSites.apply_progress(crawler_progress, get_tree())


func refresh_crawler_look() -> void:
	if crawler_progress == null:
		return
	var keep_hat := crawler_progress.worn_hat
	var keep_cape := crawler_progress.worn_cape
	_strip_foreign_crawler_apparel()
	if crawler_progress.owns_hat(keep_hat):
		crawler_progress.note_worn(keep_hat)
	if crawler_progress.owns_cape(keep_cape):
		crawler_progress.note_worn_cape(keep_cape)
	_applying_loadout = true
	apply_worn(_crawler_worn())
	_applying_loadout = false
	_apply_crawler_progress()
	sync_crawler_ability_bar()
	_sync_ward_from_hat()
	_sync_rubber_from_hat()


func sync_crawler_ability_bar() -> void:
	if training_enemy or not CrawlerRules.active() or abilities == null:
		return
	var wanted := CrawlerRules.ABILITY_SLOTS
	if crawler_progress != null:
		wanted = crawler_progress.ability_bar_slots()
	wanted = clampi(wanted, CrawlerRules.ABILITY_SLOTS, CrawlerRules.ABILITY_SLOTS_MAX)
	var overflow := PackedStringArray()
	if abilities.size() != wanted:
		overflow = abilities.resize(wanted)
	for index in abilities.size():
		abilities.set_filter(index, ItemDB.ABILITY)
	if crawler_kit == null:
		return
	for token: String in overflow:
		if token.is_empty():
			continue
		var dest := crawler_kit.inventory.first_accepting(token)
		if dest >= 0:
			crawler_kit.inventory.set_item(dest, token)


func wear_crawler_hat(on := true) -> bool:
	if crawler_progress == null or not crawler_progress.owns_hat(CrawlerProgress.HAT_ID):
		return false
	crawler_progress.note_worn(CrawlerProgress.HAT_ID if on else "")
	refresh_crawler_look()
	_sync_ward_from_hat()
	return true


func _crawler_worn() -> PackedStringArray:
	var worn := PackedStringArray()
	worn.resize(ItemDB.SLOT_ORDER.size())
	if crawler_progress == null:
		return worn
	for index in ItemDB.SLOT_ORDER.size():
		var slot: String = ItemDB.SLOT_ORDER[index]
		var item_id := ""
		match slot:
			"hat":
				item_id = crawler_progress.worn_hat
				if not crawler_progress.owns_hat(item_id):
					item_id = ""
			"cape":
				item_id = crawler_progress.worn_cape
				if not crawler_progress.owns_cape(item_id):
					item_id = ""
		worn[index] = item_id
	return worn


func _strip_foreign_crawler_apparel() -> void:
	if crawler_progress == null or equipment.size() <= 0:
		return
	var next := equipment.items()
	var dirty := false
	for index in mini(next.size(), ItemDB.SLOT_ORDER.size()):
		var item_id := next[index]
		if item_id.is_empty():
			continue
		var slot: String = ItemDB.SLOT_ORDER[index]
		var keep := (
			(slot == "hat" and crawler_progress.owns_hat(item_id))
			or (slot == "cape" and crawler_progress.owns_cape(item_id))
		)
		if keep:
			continue
		next[index] = ""
		dirty = true
	if not dirty:
		return
	_applying_loadout = true
	apply_worn(next)
	_applying_loadout = false


func _apply_meta_progress() -> void:
	if training_enemy:
		return
	if CrawlerRules.active():
		_apply_crawler_progress()
		return
	var health_bonus := CrawlerProgress.HEALTH_PER_RANK \
		* float(CrawlerMeta.rank_of(CrawlerProgress.STAT_HEALTH))
	var next_max := float(PlayerStats.STATS["health"]["base"]) + health_bonus
	var before_max := stats.base_of(PlayerStats.HEALTH)
	stats.set_base(PlayerStats.HEALTH, next_max)
	if next_max > before_max:
		stats.set_health(stats.health() + (next_max - before_max))
	var dex := CrawlerRules.upgrade_scale(
		CrawlerMeta.rank_of(CrawlerProgress.STAT_DEXTERITY))
	walk_speed = _authored_speeds.x * dex
	sprint_speed = _authored_speeds.y * dex
	crouch_speed = _authored_speeds.z * dex
	arms_back_speed = _authored_speeds.w * dex
	stats.set_base(PlayerStats.SPEED, walk_speed)
	_run_speed = walk_speed


func _apply_crawler_progress() -> void:
	if crawler_progress == null or not CrawlerRules.active():
		return
	var next_max := crawler_progress.health_maximum()
	var before_max := stats.base_of(PlayerStats.HEALTH)
	var gained := next_max - before_max
	stats.set_base(PlayerStats.HEALTH, next_max)
	if gained > 0.0:
		stats.set_health(stats.health() + gained)
	var dex := crawler_progress.dex_scale()
	var accel := CrawlerRules.sandbox_fast_accel()
	var speed := maxf(_crawler_speed_base, 0.01) * dex
	stats.set_base(PlayerStats.SPEED, speed)
	ground_accel = _authored_ground_accel * dex * accel
	air_accel = _authored_air_accel * dex * accel
	flight_accel = _authored_flight_accel * dex * accel
	_run_speed = walk_speed


func _on_crawler_progress_changed() -> void:
	_apply_crawler_progress()
	sync_crawler_ability_bar()
	_sync_rubber_from_hat()
	if _is_host_authority():
		var quiet := DamageHit.impact(combat_position(), 0.1, 0.0)
		quiet.faction = DamageHit.Faction.NEUTRAL
		_broadcast_combat_state(0.0, quiet, false, false, false)


func _on_crawler_leveled_up() -> void:
	_apply_crawler_level_heal()
	if crawler_progress != null and (
			CrawlerRules.coop() or CrawlerMeta.auto_select()):
		crawler_progress.auto_claim_level_offers()
		_apply_crawler_progress()
	_play_crawler_level_burst()


func _apply_crawler_level_heal() -> void:
	if not _is_host_authority() or crawler_progress == null:
		return
	var gained := crawler_progress.last_levels_gained
	if gained <= 0:
		gained = 1
	crawler_progress.last_levels_gained = 0
	apply_heal(maximum_health() * CrawlerProgress.LEVEL_HEAL * float(gained))


func _play_crawler_level_burst() -> void:
	if hud == null or not is_inside_tree():
		_open_crawler_level_menu()
		return
	if hud.get_node_or_null("CrawlerLevelBurst") != null:
		return
	if hud.get_node_or_null("CrawlerLevelMenu") != null:
		return
	var burst = load("res://ui/combat/crawler_level_burst.gd").new()
	burst.finished.connect(_on_crawler_level_burst_finished, CONNECT_ONE_SHOT)
	hud.add_child(burst)


func _on_crawler_level_burst_finished() -> void:
	if not CrawlerRules.coop() and not CrawlerMeta.auto_select():
		_open_crawler_level_menu()
		if hud != null and hud.get_node_or_null("CrawlerLevelMenu") != null:
			return
	_flush_achievement_toasts()


func _on_journal_completed(id: String) -> void:
	if JournalDB.kind_of(id) != JournalDB.ACHIEVEMENT:
		return
	_queue_achievement_burst(
		JournalDB.title_of(id),
		JournalDB.instant_reward_lines(id)
	)


func _queue_achievement_burst(
		title: String,
		rewards: PackedStringArray = PackedStringArray()
	) -> void:
	if hud == null or not is_inside_tree() or title.strip_edges().is_empty():
		return
	var payload := {"title": title, "rewards": rewards}
	if hud.get_node_or_null("AchievementBurst") != null \
			or hud.get_node_or_null("CrawlerLevelBurst") != null \
			or hud.get_node_or_null("CrawlerLevelMenu") != null:
		for held: Dictionary in _achievement_toasts:
			if str(held.get("title", "")) == title:
				return
		_achievement_toasts.append(payload)
		return
	_play_achievement_burst(title, rewards)


func _play_achievement_burst(
		title: String,
		rewards: PackedStringArray = PackedStringArray()
	) -> void:
	if hud == null or not is_inside_tree():
		return
	var burst = load("res://ui/combat/achievement_burst.gd").new()
	if burst.has_method(&"configure"):
		burst.configure(title, rewards)
	burst.finished.connect(_on_achievement_burst_finished, CONNECT_ONE_SHOT)
	hud.add_child(burst)


func _on_achievement_burst_finished() -> void:
	_flush_achievement_toasts()


func _flush_achievement_toasts() -> void:
	if hud == null or hud.get_node_or_null("AchievementBurst") != null:
		return
	var level_menu := hud.get_node_or_null("CrawlerLevelMenu")
	if level_menu != null and not level_menu.is_queued_for_deletion():
		return
	if _achievement_toasts.is_empty():
		return
	var next: Dictionary = _achievement_toasts.pop_front()
	_play_achievement_burst(
		str(next.get("title", "")),
		PackedStringArray(next.get("rewards", PackedStringArray()))
	)


func _open_crawler_level_menu() -> void:
	if CrawlerRules.coop() or CrawlerMeta.auto_select():
		return
	if hud == null or not is_inside_tree():
		return
	if hud.get_node_or_null("CrawlerLevelMenu") != null:
		return
	if crawler_progress == null or crawler_progress.unspent <= 0:
		return
	_attach_crawler_level_menu(false)


func _open_crawler_auto_prefs() -> void:
	if hud == null or not is_inside_tree():
		return
	var open := hud.get_node_or_null("CrawlerLevelMenu") as CrawlerLevelMenu
	if open != null:
		if open.has_method(&"show_tab"):
			open.call(&"show_tab", CrawlerLevelMenu.Tab.PREFS)
		return
	_attach_crawler_level_menu(true)


func _attach_crawler_level_menu(prefs_only: bool) -> void:
	if hud == null:
		return
	if hud.get_node_or_null("CrawlerLevelMenu") != null:
		return
	var menu = CrawlerLevelMenuScript.new()
	if menu.has_method(&"configure"):
		menu.configure(self, prefs_only)
	menu.closed.connect(_on_crawler_level_menu_closed)
	if not _menu_open:
		open_menu()
		var world := NetworkManager.active_world as GameWorld
		if world != null:
			world.set_local_pause(true)
	hud.add_child(menu)


func claim_crawler_auto_offers() -> void:
	if crawler_progress == null or crawler_progress.unspent <= 0:
		return
	crawler_progress.auto_claim_level_offers()
	_apply_crawler_progress()


func set_crawler_auto_select(on: bool) -> void:
	CrawlerMeta.set_auto_select(on)
	if on:
		claim_crawler_auto_offers()
		return
	if CrawlerRules.coop():
		return
	if crawler_progress != null and crawler_progress.unspent > 0:
		_open_crawler_level_menu()


func toggle_crawler_auto_select() -> void:
	set_crawler_auto_select(not CrawlerMeta.auto_select())


func _handle_crawler_auto_key() -> bool:
	if not CrawlerRules.active() or training_enemy:
		return false
	if hud != null and (
			hud.get_node_or_null("GameMenu") != null \
			or hud.get_node_or_null("CrawlerFieldMenu") != null):
		return false
	if CrawlerRules.coop():
		var open := hud.get_node_or_null("CrawlerLevelMenu") if hud != null else null
		if open != null and open.has_method(&"close"):
			open.call(&"close")
		else:
			_open_crawler_auto_prefs()
		return true
	toggle_crawler_auto_select()
	return true


func _on_crawler_level_menu_closed() -> void:
	if hud != null and (
			hud.get_node_or_null("GameMenu") != null \
			or hud.get_node_or_null("CrawlerFieldMenu") != null):
		_flush_achievement_toasts()
		return
	close_menu()
	var world := NetworkManager.active_world as GameWorld
	if world != null:
		world.set_local_pause(false)
	_flush_achievement_toasts()


func spend_crawler_stat(stat_id: String, amount := 1.0) -> bool:
	if crawler_progress == null:
		return false
	return crawler_progress.spend(stat_id, amount)


func spend_crawler_offer(stat_id: String) -> bool:
	if crawler_progress == null:
		return false
	return crawler_progress.spend_offer(stat_id)


func reroll_crawler_offers() -> bool:
	if crawler_progress == null:
		return false
	return crawler_progress.reroll_level_offers()


func crawler_shop_open(shop_id: String) -> bool:
	if crawler_progress == null:
		return not CrawlerRules.crawler()
	return crawler_progress.shop_open(shop_id, crawler_city_key())


func buy_crawler_hat(item_id := CrawlerProgress.HAT_ID) -> bool:
	if crawler_progress == null or not in_crawler_city() \
			or not crawler_shop_open("hats"):
		return false
	var city := crawler_city_key()
	if not crawler_progress.shop_has_unsold("hats", item_id, city):
		return false
	if not crawler_progress.buy_hat(item_id, city):
		return false
	crawler_progress.mark_shop_sold("hats", item_id, city)
	_applying_loadout = true
	apply_worn(_crawler_worn())
	_applying_loadout = false
	_sync_ward_from_hat()
	return true


func merge_crawler_hats(keep_uid: String, other_uid: String) -> bool:
	if crawler_progress == null or not in_crawler_city() \
			or not crawler_shop_open("caps"):
		return false
	var city := crawler_city_key()
	if city.is_empty() or not crawler_progress.cap_merge_free(city):
		return false
	if not crawler_progress.merge_hats(keep_uid, other_uid, city):
		return false
	crawler_progress.mark_cap_merged(city)
	_applying_loadout = true
	apply_worn(_crawler_worn())
	_applying_loadout = false
	_sync_ward_from_hat()
	return true


func buy_crawler_cape(item_id := CrawlerProgress.CAPE_ID) -> bool:
	if crawler_progress == null or not in_crawler_city() \
			or not crawler_shop_open("capes"):
		return false
	if not crawler_progress.buy_cape(item_id):
		return false
	_applying_loadout = true
	apply_worn(_crawler_worn())
	_applying_loadout = false
	return true


func buy_crawler_quest(quest_id: String) -> bool:
	if crawler_progress == null or not in_crawler_city() \
			or not crawler_shop_open("quests"):
		return false
	if not crawler_progress.buy_quest(quest_id):
		return false
	if CrawlerRun.active():
		var layout := CrawlerRunLayout.instance(get_tree())
		var revealed := ""
		if layout != null:
			revealed = layout.reveal_quest_site(self, quest_id)
		if not revealed.is_empty() and not crawler_progress.quest_reveals.has(revealed):
			crawler_progress.quest_reveals.append(revealed)
			crawler_progress.remember()
		return true
	PatchMonument.enable_waypoint(quest_id)
	return true


func buy_crawler_ticket() -> bool:
	if crawler_progress == null or not in_crawler_city() \
			or not crawler_shop_open("market"):
		return false
	return crawler_progress.buy_respawn_ticket()


func buy_crawler_rest_health() -> bool:
	if crawler_progress == null or not in_crawler_city():
		return false
	var city := crawler_city_key()
	if city.is_empty():
		return false
	if health() >= maximum_health() - 0.001:
		return false
	var price := crawler_progress.rest_health_price_for(city)
	if price > 0 and not crawler_progress.spend_gold(price):
		return false
	var gained := apply_heal(maximum_health())
	if gained <= 0.0:
		crawler_progress.refund_gold(price)
		return false
	crawler_progress.mark_rested_health(city)
	return true


func buy_crawler_rest_ammo() -> bool:
	if crawler_progress == null or crawler_kit == null or not in_crawler_city():
		return false
	var city := crawler_city_key()
	if city.is_empty():
		return false
	if not crawler_kit.needs_ammo_refill():
		return false
	var price := crawler_progress.rest_ammo_price_for(city)
	if price > 0 and not crawler_progress.spend_gold(price):
		return false
	if not crawler_kit.refill_all_ammo():
		crawler_progress.refund_gold(price)
		return false
	crawler_progress.mark_rested_ammo(city)
	return true


func grant_crawler_rest_gold() -> bool:
	return set_crawler_unlimited_gold(true)


func set_crawler_unlimited_gold(enabled: bool) -> bool:
	if crawler_progress == null or not in_crawler_city():
		return false
	crawler_progress.set_gold_unlimited(enabled)
	return true


func enable_crawler_unlimited_shops() -> bool:
	if crawler_progress == null or not in_crawler_city():
		return false
	crawler_progress.set_shops_unlimited(true)
	return true


func buy_crawler_card(catalog_id: String) -> bool:
	if crawler_kit == null or crawler_progress == null or not in_crawler_city():
		return false
	var stall := "abilities" if CrawlerCatalog.is_ability(catalog_id) else "cards"
	if not crawler_shop_open(stall):
		return false
	if CrawlerCatalog.is_ability(catalog_id):
		if not CrawlerProgress.ability_stock().has(catalog_id):
			return false
	elif not CrawlerCatalog.is_modifier(catalog_id):
		return false
	var city := crawler_city_key()
	var kind := "abilities" if CrawlerCatalog.is_ability(catalog_id) else "mods"
	if not crawler_progress.shop_has_unsold(kind, catalog_id, city):
		return false
	var price := CrawlerProgress.card_price(catalog_id)
	if price <= 0 or not crawler_progress.has_gold(price):
		return false
	if not crawler_progress.spend_gold(price):
		return false
	var granted := crawler_kit.shop_grant_result(
		catalog_id, selected_ability_index())
	if bool(granted.get("ok", false)):
		crawler_progress.mark_shop_sold(kind, catalog_id, city)
		_spawn_displaced_crawler_card(granted.get("displaced", {}))
		return true
	crawler_progress.refund_gold(price)
	return false


func refresh_crawler_shop(kind: String) -> bool:
	if crawler_progress == null or not in_crawler_city():
		return false
	var stall := "cards" if kind == "mods" else kind
	if not crawler_shop_open(stall):
		return false
	return crawler_progress.refresh_shop_offers(kind, crawler_city_key())


func _spawn_displaced_crawler_card(payload: Variant) -> void:
	if not (payload is Dictionary) or (payload as Dictionary).is_empty():
		return
	var world := get_parent() as GameWorld
	if world == null:
		world = NetworkManager.active_world as GameWorld
	if world != null:
		world.spawn_displaced_crawler_card(self, payload as Dictionary)


func upgrade_crawler_card(uid: String, stat_id := "") -> bool:
	if crawler_kit == null or crawler_progress == null or not in_crawler_city() \
			or not crawler_shop_open("upgrades"):
		return false
	var card := crawler_kit.cards.get(uid) as CrawlerCard
	if card == null:
		return false
	var wanted := stat_id
	if wanted.is_empty():
		var listed := CrawlerRules.upgrade_stats_for(card.id)
		wanted = listed[0] if not listed.is_empty() else ""
	if not crawler_progress.upgrade_in_stock(card.id, wanted, crawler_city_key()):
		return false
	var price := CrawlerProgress.upgrade_price(crawler_kit.shop_rank_for(card), card.id)
	if not crawler_progress.spend_gold(price):
		return false
	if crawler_kit.upgrade_card(uid, wanted):
		return true
	crawler_progress.refund_gold(price)
	return false


func award_crawler_kill(
		mob_level: int, kind := "", at: Variant = null, gem_roll := -1.0
	) -> void:
	if crawler_progress == null or not _is_host_authority():
		return
	var gold := crawler_progress.scaled_kill_gold(mob_level)
	var xp := crawler_progress.scaled_kill_xp(mob_level, kind)
	var roll := gem_roll
	if roll < 0.0:
		roll = crawler_progress.offer_rng().randf()
	var gems := crawler_progress.scaled_kill_gems(mob_level, roll)
	crawler_progress.award_kill(mob_level, kind, roll)
	CrawlerMeta.add_gems(gems)
	if journal != null:
		journal.note_kill()
	if at is Vector3 and (at as Vector3).is_finite():
		_publish_crawler_kill_loot(gold, xp, gems, at)
		_roll_crawler_kill_drops(at)


func _roll_crawler_kill_drops(at: Vector3) -> void:
	if crawler_progress == null or not at.is_finite():
		return
	var world := get_parent() as GameWorld
	if world == null:
		return
	world.spawn_crawler_kill_loot(
		CrawlerLoot.roll_kill_drops(crawler_progress, crawler_progress.offer_rng()),
		at)


func _publish_crawler_kill_loot(gold: int, xp: int, gems: int, at: Vector3) -> void:
	if gold <= 0 and xp <= 0 and gems <= 0:
		return
	_feedback_sequence += 1
	if _has_listeners():
		_apply_crawler_kill_loot.rpc(_feedback_sequence, gold, xp, gems, at)
	else:
		_apply_crawler_kill_loot(_feedback_sequence, gold, xp, gems, at)


func crawler_owned_hats() -> PackedStringArray:
	if crawler_progress == null:
		return PackedStringArray()
	return crawler_progress.owned_hats.duplicate()


func crawler_owned_capes() -> PackedStringArray:
	if crawler_progress == null:
		return PackedStringArray()
	return crawler_progress.owned_capes.duplicate()


func crawler_damage_scale() -> float:
	return crawler_progress.damage_scale() if crawler_progress != null else 1.0


func crawler_base_damage() -> float:
	return CrawlerRules.player_hit_damage(self)


func crawler_knockback_scale() -> float:
	return crawler_progress.knockback_scale() if crawler_progress != null else 1.0


func crawler_cast_trim() -> float:
	return crawler_progress.cast_trim() if crawler_progress != null else 0.0


func crawler_range_scale() -> float:
	return crawler_progress.range_scale() if crawler_progress != null else 1.0


func crawler_element_scale() -> float:
	return crawler_progress.elemental_scale() if crawler_progress != null else 1.0


func crawler_dodge_chance() -> float:
	if not CrawlerRules.active() or crawler_progress == null:
		return 0.0
	return crawler_progress.dodge_chance()


func crawler_defense_share() -> float:
	if not CrawlerRules.active() or crawler_progress == null:
		return 0.0
	return crawler_progress.defense_share()


func juke_cooldown() -> float:
	if CrawlerRules.active() and crawler_progress != null:
		return crawler_progress.juke_cooldown()
	return JUKE_COOLDOWN


func juke_distance() -> float:
	if CrawlerRules.active() and crawler_progress != null:
		return crawler_progress.juke_distance()
	return JUKE_DISTANCE


func _crawler_dodge_roll() -> float:
	if _dodge_roll_override >= 0.0:
		return _dodge_roll_override
	return _dodge_rng.randf()


func _try_crawler_dodge(hit: DamageHit) -> bool:
	if not CrawlerRules.active() or training_enemy:
		return false
	var amount := hit.amount if hit != null and is_finite(hit.amount) else 0.0
	if amount <= 0.0:
		return false
	var chance := crawler_dodge_chance()
	if chance <= 0.0:
		return false
	return _crawler_dodge_roll() < chance


func crawler_flight_seconds() -> float:
	return crawler_progress.flight_seconds() if crawler_progress != null \
		else CrawlerRules.FLIGHT_SECONDS


func crawler_vitals_text() -> String:
	if crawler_progress == null:
		return ""
	return "LV %d   XP %d/%d   G %s" % [
		crawler_progress.level,
		crawler_progress.xp,
		crawler_progress.xp_to_next(),
		crawler_progress.gold_text(),
	]


func in_crawler_city() -> bool:
	if not CrawlerRules.active() or not is_inside_tree():
		return false
	if CrawlerCityRingScript.contains_any(self):
		return true
	var overlay := get_tree().get_first_node_in_group(LandPatchOverlay.GROUP) \
		as LandPatchOverlay
	if overlay == null:
		return false
	for held in overlay.all_cities():
		var city := held as PatchCity
		if city != null and city.contains_world(global_position):
			return true
	return false


func crawler_city_key() -> String:
	if not CrawlerRules.active() or not is_inside_tree():
		return ""
	var ring_key := CrawlerCityRingScript.city_key_for(self)
	if not ring_key.is_empty():
		return ring_key
	var overlay := get_tree().get_first_node_in_group(LandPatchOverlay.GROUP) \
		as LandPatchOverlay
	if overlay == null:
		return ""
	for held in overlay.all_cities():
		var city := held as PatchCity
		if city == null or not city.contains_world(global_position):
			continue
		var patch_id := city.city_id()
		return str(patch_id) if patch_id >= 0 else "city"
	return ""


func note_crawler_cast(overlay: Dictionary) -> void:
	_crawler_cast_stats = overlay.duplicate(true)


func crawler_cast_overlay() -> Dictionary:
	return _crawler_cast_stats.duplicate(true)


func crawler_ability_overlay(ability_id: String) -> Dictionary:
	if crawler_kit != null and abilities != null:
		var wanted := CrawlerCatalog.ability_id(ability_id)
		if wanted.is_empty():
			wanted = ability_id
		for index in abilities.size():
			var card := crawler_kit.equipped_card(index)
			if card != null and card.id == wanted:
				return crawler_kit.stats_for(card)
	return crawler_cast_overlay()


func apply_backpack(items: PackedStringArray) -> void:
	for index in backpack.size():
		backpack.set_item(index, items[index] if index < items.size() else "")


## Current item in one of the three finite physical containers. Abilities are
## intentionally absent: they are known powers, not objects that can enter the
## world.
func physical_item_at(source: String, index: int) -> String:
	var container := _physical_container(source)
	return container.get_item(index) if container != null else ""


func backpack_slot_for(item_id: String) -> int:
	return backpack.first_accepting(item_id)


func inventory_generation() -> int:
	return _inventory_generation


## False on the server until a remote owner has supplied its first complete,
## filtered private snapshot. Local host state is canonical as soon as _ready
## finishes.
func authoritative_inventory_ready() -> bool:
	return _server_has_loadout_snapshot


## Flushes a pending owner snapshot before a reliable world request. Both RPCs
## use the reliable default channel, so the server observes this state first.
func sync_loadout_to_server() -> void:
	if _applying_loadout or peer_id != multiplayer.get_unique_id() \
			or not multiplayer.has_multiplayer_peer() or multiplayer.is_server():
		return
	_loadout_snapshot_queued = false
	_send_loadout_snapshot()


## Server-only removal used after GameWorld has validated the source claim.
## Container callbacks remain the one place that undresses/holsters: the host's
## local body also persists and replicates normally, while a remote server mirror
## suppresses owner-only saves and network echoes.
func authoritative_remove_item(source: String, index: int, expected_item_id: String) -> bool:
	if not multiplayer.is_server():
		return false
	var container := _physical_container(source)
	if container == null or index < 0 or index >= container.size() \
			or container.get_item(index) != expected_item_id:
		return false
	var was_applying := _applying_loadout
	if peer_id != multiplayer.get_unique_id():
		_applying_loadout = true
	container.set_item(index, "")
	_applying_loadout = was_applying
	return container.get_item(index).is_empty()


## Grants into the canonical server backpack and returns the chosen slot.
func authoritative_grant_backpack(item_id: String) -> int:
	if not multiplayer.is_server() or not ItemDB.accepts_backpack(item_id):
		return -1
	var target := backpack.first_accepting(item_id)
	if target < 0:
		return -1
	var was_applying := _applying_loadout
	if peer_id != multiplayer.get_unique_id():
		_applying_loadout = true
	backpack.set_item(target, item_id)
	_applying_loadout = was_applying
	return target if backpack.get_item(target) == item_id else -1


func advance_inventory_generation() -> int:
	if multiplayer.is_server():
		_inventory_generation += 1
	return _inventory_generation


## Applies a reliable server confirmation on the owning client. If the player
## rearranged the bag while the request was in flight, remove one matching
## physical item wherever it moved; pickup_id makes a duplicate confirmation a
## no-op rather than a second removal.
func confirm_authoritative_drop(
		pickup_id: int,
		source: String,
		index: int,
		item_id: String,
		generation: int
	) -> bool:
	if peer_id != multiplayer.get_unique_id() or pickup_id <= 0 \
			or generation < _inventory_generation:
		return false
	_inventory_generation = generation
	if _confirmed_drop_ids.has(pickup_id):
		return false
	_confirmed_drop_ids[pickup_id] = true

	var container := _physical_container(source)
	var remove_index := index
	if container == null or container.get_item(remove_index) != item_id:
		container = null
		for candidate in [equipment, hotbar, backpack]:
			var found := (candidate as ItemContainer).find(item_id)
			if found >= 0:
				container = candidate as ItemContainer
				remove_index = found
				break
	if container == null:
		push_warning("OnlinePlayer: confirmed drop %d could not find '%s'" % [
			pickup_id, item_id])
		_queue_loadout_snapshot()
		return false
	container.set_item(remove_index, "")
	return container.get_item(remove_index).is_empty()


## Applies one server grant on the owning client. The server-chosen slot is used
## when still free; otherwise another accepting slot preserves the finite item.
## The pickup id is recorded only after insertion succeeds.
func grant_authoritative_pickup(
		pickup_id: int,
		item_id: String,
		backpack_index: int,
		generation: int
	) -> bool:
	if peer_id != multiplayer.get_unique_id() or pickup_id <= 0 \
			or generation < _inventory_generation \
			or not ItemDB.accepts_backpack(item_id):
		return false
	_inventory_generation = generation
	if _received_pickup_ids.has(pickup_id):
		return false
	var target := backpack_index
	if target < 0 or target >= backpack.size() \
			or not backpack.get_item(target).is_empty() \
			or not backpack.accepts(target, item_id):
		target = backpack.first_accepting(item_id)
	if target < 0:
		push_warning("OnlinePlayer: no room for authoritative pickup %d" % pickup_id)
		_queue_loadout_snapshot()
		return false
	backpack.set_item(target, item_id)
	if backpack.get_item(target) != item_id:
		return false
	_received_pickup_ids[pickup_id] = true
	return true


func _physical_container(source: String) -> ItemContainer:
	match source:
		"equipment":
			return equipment
		"hotbar":
			return hotbar
		"backpack":
			return backpack
	return null


## Compatibility alias for the old weapon-only rack.
func apply_rack(rack: PackedStringArray) -> void:
	apply_hotbar(rack)


## Places a catalogue id in a numbered slot. Container transfer remains the API
## when the caller needs the displaced item moved somewhere rather than replaced.
func equip_hotbar(item_id: String, index := -1) -> bool:
	if not ItemDB.accepts_hotbar(item_id):
		return false
	var target := index if index >= 0 else hotbar.first_accepting(item_id)
	if target < 0 or target >= hotbar.size():
		return false
	hotbar.set_item(target, item_id)
	return hotbar.get_item(target) == item_id


func equip_ability(ability_id: String, index := -1) -> bool:
	if not ItemDB.accepts_ability(ability_id):
		return false
	var target := index if index >= 0 else abilities.first_accepting(ability_id)
	if target < 0 or target >= abilities.size():
		return false
	abilities.set_item(target, ability_id)
	return abilities.get_item(target) == ability_id


func _on_equipment_changed() -> void:
	_dress()
	if crawler_progress != null and equipment.size() > 0:
		crawler_progress.note_worn(equipment.get_item(0))
		if equipment.size() > 1:
			crawler_progress.note_worn_cape(equipment.get_item(1))
		_apply_crawler_progress()
		_sync_ward_from_hat()
	if _applying_loadout:
		return
	if peer_id == multiplayer.get_unique_id() and multiplayer.has_multiplayer_peer():
		_wear.rpc(equipment.items())
	_queue_loadout_save()


func _on_abilities_changed() -> void:
	if _weapon_bar != null:
		_weapon_bar.refresh()
	_queue_loadout_save()


func _on_backpack_changed() -> void:
	_queue_loadout_save()


func _queue_loadout_save() -> void:
	_queue_loadout_snapshot()
	if _applying_loadout or _saving_loadout \
			or peer_id != multiplayer.get_unique_id() or _loadout_save_queued:
		return
	_loadout_save_queued = true
	call_deferred("_persist_loadout")


func _queue_loadout_snapshot() -> void:
	if _applying_loadout or peer_id != multiplayer.get_unique_id() \
			or not multiplayer.has_multiplayer_peer() or multiplayer.is_server() \
			or _loadout_snapshot_queued:
		return
	_loadout_snapshot_queued = true
	call_deferred("_flush_loadout_snapshot")


func _flush_loadout_snapshot() -> void:
	if not _loadout_snapshot_queued:
		return
	_loadout_snapshot_queued = false
	_send_loadout_snapshot()


func _send_loadout_snapshot() -> void:
	if _applying_loadout or peer_id != multiplayer.get_unique_id() \
			or not multiplayer.has_multiplayer_peer() or multiplayer.is_server():
		return
	_loadout_snapshot_revision += 1
	_submit_loadout_snapshot.rpc_id(1, {
		"equipment": equipment.items(),
		"hotbar": hotbar.items(),
		"abilities": abilities.items(),
		"backpack": backpack.items(),
		"crawler_kit": crawler_kit.to_dict() if crawler_kit != null else {},
	}, _inventory_generation, _loadout_snapshot_revision)


## A complete snapshot is accepted only from this body's owner and only against
## the current authoritative generation. Values are passed through the actual
## destination filters while _applying_loadout blocks persistence and echoes.
@rpc("any_peer", "call_remote", "reliable")
func _submit_loadout_snapshot(
		snapshot: Dictionary,
		generation: int,
		revision: int
	) -> void:
	if not multiplayer.is_server() \
			or multiplayer.get_remote_sender_id() != peer_id \
			or generation != _inventory_generation \
			or revision <= _server_snapshot_revision:
		return
	var clean := _sanitize_loadout_snapshot(snapshot)
	if clean.is_empty():
		return
	_server_snapshot_revision = revision
	var was_applying := _applying_loadout
	_applying_loadout = true
	apply_worn(clean["equipment"])
	apply_hotbar(clean["hotbar"])
	apply_backpack(clean["backpack"])
	if crawler_kit != null and snapshot.get("crawler_kit", null) is Dictionary:
		crawler_kit.from_dict(snapshot["crawler_kit"])
	else:
		apply_abilities(clean["abilities"])
	_applying_loadout = was_applying
	_server_has_loadout_snapshot = true


func _sanitize_loadout_snapshot(snapshot: Dictionary) -> Dictionary:
	var expected_sizes := {
		"equipment": equipment.size(),
		"hotbar": hotbar.size(),
		"abilities": abilities.size(),
		"backpack": backpack.size(),
	}
	for key in ["equipment", "hotbar", "abilities", "backpack"]:
		if not snapshot.has(key):
			return {}
		var raw: Variant = snapshot[key]
		if (not raw is Array and not raw is PackedStringArray) \
				or raw.size() != int(expected_sizes[key]):
			return {}
	var clean_equipment: PackedStringArray = _sanitize_snapshot_container(
		snapshot["equipment"], equipment, true)
	var clean_hotbar: PackedStringArray = _sanitize_snapshot_container(
		snapshot["hotbar"], hotbar)
	var clean_abilities: PackedStringArray = _sanitize_snapshot_container(
		snapshot["abilities"], abilities)
	var clean_backpack: PackedStringArray = _sanitize_snapshot_container(
		snapshot["backpack"], backpack)
	return {
		"equipment": clean_equipment,
		"hotbar": clean_hotbar,
		"abilities": clean_abilities,
		"backpack": clean_backpack,
	}


func _sanitize_snapshot_container(
		raw: Variant,
		container: ItemContainer,
		check_body_fit := false
	) -> PackedStringArray:
	if not raw is Array and not raw is PackedStringArray:
		return PackedStringArray()
	var clean := PackedStringArray()
	clean.resize(container.size())
	for index in mini(raw.size(), container.size()):
		var item_id := str(raw[index])
		if item_id.is_empty():
			continue
		if not ItemDB.has_item(item_id) or not container.accepts(index, item_id):
			continue
		if check_body_fit and not CharacterDB.apparel_fits(_body_id, item_id):
			continue
		clean[index] = item_id
	return clean


func _persist_loadout() -> void:
	_loadout_save_queued = false
	if _applying_loadout or _saving_loadout \
			or peer_id != multiplayer.get_unique_id():
		return
	_saving_loadout = true
	var look := CharacterDB.load_look()
	look["body"] = _body_id
	look["skin"] = _skin_id
	if not CrawlerRules.active():
		var worn: Dictionary = {}
		for index in equipment.size():
			var item_id := equipment.get_item(index)
			if not item_id.is_empty():
				worn[equipment.filter_of(index)] = item_id
		look["worn"] = worn
	var numbered := _container_array(hotbar)
	look["hotbar"] = numbered
	look["rack"] = numbered.duplicate()
	if crawler_kit == null:
		look["abilities"] = _container_array(abilities)
	look["backpack"] = _container_array(backpack)
	CharacterDB.save_look(look)
	if crawler_kit != null:
		crawler_kit.remember()
	if crawler_progress != null:
		crawler_progress.remember()
	_saving_loadout = false


func _container_array(container: ItemContainer) -> Array:
	var out: Array = []
	for item_id: String in container.items():
		out.append(item_id)
	return out


## Puts the body in step with the equipment container, garment by garment.
func _dress() -> void:
	for index in ItemDB.SLOT_ORDER.size():
		var body_slot: String = ItemDB.SLOT_ORDER[index]
		var id := equipment.get_item(index)
		# Refuse garments cut for a different skeleton — they would bind, but the
		# weights would be nonsense and the silhouette would clip through itself.
		if not id.is_empty() and not CharacterDB.apparel_fits(_body_id, id):
			id = ""
		if String(_worn.get(body_slot, "")) == id:
			continue
		_worn[body_slot] = id
		if id.is_empty():
			Wardrobe.unequip(character, body_slot)
			continue
		var garment := Wardrobe.equip(character, body_slot, ItemDB.scene_path(id))
		var worn := Wardrobe.worn_node(character, body_slot)
		if worn != null and worn.has_method(&"apply_item"):
			worn.call(&"apply_item", id)
		if garment != null:
			SurfaceSkin.paint(garment, {}, true)
			LagTracker.note_throttled("look", "dress_%s" % id, "equipped %s" % id, 0.4)
	_refresh_mesh_list()
	_apply_tints()


## The shadow-casting list drives every frame, so a garment that has just come off,
## or a weapon that has just been put away, has to leave it with the same breath.
func _refresh_mesh_list() -> void:
	_character_meshes.assign(character.find_children("*", "MeshInstance3D", true, false))
	for mesh_instance in _character_meshes:
		# A skinned mesh keeps the bounds it was imported with, and a ragdoll puts
		# the bones a couple of metres from where the pose says they are. Without
		# the margin the whole body disappears the moment the camera turns.
		mesh_instance.extra_cull_margin = 3.0


# --- Weapons ----------------------------------------------------------------

## The arms are posed by a modifier on the skeleton rather than by clips, so one
## hold works over every gait the body can be in. See weapon_pose.gd.
func _add_weapon_pose() -> void:
	if _weapon_pose != null and is_instance_valid(_weapon_pose):
		_weapon_pose.queue_free()
		_weapon_pose = null
	var skeleton := Weapons.skeleton_of(character)
	if skeleton == null:
		return
	_weapon_pose = WeaponPose.new()
	_weapon_pose.name = "WeaponPose"
	skeleton.add_child(_weapon_pose)


func _add_roar_pose() -> void:
	if _roar_pose != null and is_instance_valid(_roar_pose):
		_roar_pose.queue_free()
		_roar_pose = null
	var skeleton := Weapons.skeleton_of(character)
	if skeleton == null:
		return
	_roar_pose = RoarPose.new()
	_roar_pose.name = "RoarPose"
	skeleton.add_child(_roar_pose)


func begin_roar(duration: float) -> bool:
	if _roar_pose == null or not is_instance_valid(_roar_pose):
		_add_roar_pose()
	if _roar_pose == null:
		return false
	if _weapon_pose != null:
		_weapon_pose_before_roar = _weapon_pose.active
		_weapon_pose.active = false
		_roar_held_arms = true
	_roar_pose.play(duration)
	return true


func roar_playing() -> bool:
	return _roar_pose != null and _roar_pose.playing()


func begin_overdrive(overlay: Dictionary, card: CrawlerCard) -> void:
	var duration := maxf(float(overlay.get("duration",
		CrawlerRules.OVERDRIVE_DURATION)), 0.05)
	var boost := maxf(float(overlay.get("boost", CrawlerRules.OVERDRIVE_BOOST)), 0.0)
	_overdrive_left = duration
	_overdrive_boost = boost
	_overdrive_card_uid = card.uid if card != null else ""
	_overdrive_mods.clear()
	var has_big := false
	var big_rank := 0
	if card != null:
		for child: CrawlerCard in card.filled_mods():
			_overdrive_mods.append(child)
			if child.id == "big":
				has_big = true
				big_rank = maxi(child.upgrade_rank("size"), 0)
	_overdrive_body_scale = CrawlerRules.overdrive_body_scale(boost, has_big, big_rank)
	_apply_overdrive_visual()
	_refresh_crawler_ability_stats()
	if _has_listeners():
		_sync_overdrive.rpc(_overdrive_left, _overdrive_boost, _overdrive_body_scale)


func overdrive_active() -> bool:
	return _overdrive_left > 0.0


func overdrive_boost() -> float:
	return _overdrive_boost if overdrive_active() else 0.0


func overdrive_boost_mul() -> float:
	return CrawlerRules.overdrive_boost_mul(_overdrive_boost) \
		if overdrive_active() else 1.0


func overdrive_size_scale() -> float:
	return _overdrive_body_scale if overdrive_active() else 1.0


func overdrive_borrowed_mods() -> Array[CrawlerCard]:
	if not overdrive_active():
		return []
	if not _overdrive_card_uid.is_empty() and crawler_kit != null:
		var live := crawler_kit.cards.get(_overdrive_card_uid) as CrawlerCard
		if live != null:
			return live.filled_mods()
	return _overdrive_mods


func overdrive_left() -> float:
	return _overdrive_left


func end_overdrive() -> void:
	if _overdrive_left <= 0.0 and is_equal_approx(_overdrive_body_scale, 1.0) \
			and _overdrive_mods.is_empty():
		return
	_overdrive_left = 0.0
	_overdrive_boost = 0.0
	_overdrive_body_scale = 1.0
	_overdrive_card_uid = ""
	_overdrive_mods.clear()
	_apply_overdrive_visual()
	_refresh_crawler_ability_stats()
	if _has_listeners():
		_sync_overdrive.rpc(0.0, 0.0, 1.0)


func _tick_overdrive(delta: float) -> void:
	if _overdrive_left <= 0.0:
		return
	_overdrive_left = maxf(_overdrive_left - delta, 0.0)
	if _overdrive_left <= 0.0:
		end_overdrive()


func _refresh_crawler_ability_stats() -> void:
	if is_instance_valid(_ability_controller) \
			and _ability_controller.has_method(&"refresh_crawler_stats"):
		_ability_controller.call(&"refresh_crawler_stats")


func _capture_base_capsule_radius() -> void:
	if collider == null or overdrive_active():
		return
	var capsule := collider.shape as CapsuleShape3D
	if capsule != null and capsule.radius > 0.0:
		_base_capsule_radius = capsule.radius


func _apply_overdrive_visual() -> void:
	var scale := overdrive_size_scale()
	if character != null and is_instance_valid(character):
		character.scale = Vector3(scale, scale, scale)
	_apply_stance(_stance)
	if _parry_shield != null:
		_parry_shield.fit_body(_body_height * scale)
	if _ward_bubble != null:
		_ward_bubble.fit_body(_body_height * scale)


func _sync_roar_pose() -> void:
	if _roar_pose != null and _roar_pose.playing():
		return
	if not _roar_held_arms or _weapon_pose == null:
		return
	_weapon_pose.active = _weapon_pose_before_roar
	_roar_held_arms = false


## Rigid bodies built onto the same skeleton, idle until a crash. Added after the
## weapon pose so it runs after it: modifiers on a skeleton apply in tree order,
## and while the body is limp the ragdoll is the one that should win.
func _add_ragdoll() -> void:
	if _ragdoll != null and is_instance_valid(_ragdoll):
		_ragdoll.queue_free()
		_ragdoll = null
	var skeleton := Weapons.skeleton_of(character)
	if skeleton == null:
		return
	_ragdoll = Ragdoll.new()
	_ragdoll.name = "Ragdoll"
	skeleton.add_child(_ragdoll)
	if not _ragdoll.built():
		_ragdoll.queue_free()
		_ragdoll = null
		return
	_ragdoll.ignore(self)


## The weapon this player has in hand, for a peer that has just joined.
func held_item() -> String:
	return _held


func apply_held(id: String) -> void:
	var clean := id if ItemDB.accepts_hotbar(id) else ""
	_hotbar_drawn = not clean.is_empty()
	_take_up(clean)


func is_holstered() -> bool:
	return not _hotbar_drawn


## Selects an ability hotbar slot without firing it. Scroll and the numbered
## keys use this; click fires the selected slot.
func selected_ability_index() -> int:
	return _ability_slot


func select_ability(index: int) -> void:
	if index < 0 or index >= abilities.size():
		return
	_ability_slot = index
	if _weapon_bar != null:
		_weapon_bar.select(index)


## Wheel only stops on slots holding something, matching the old weapon cycle.
func _cycle_ability(step: int) -> void:
	var filled: Array[int] = []
	for index in abilities.size():
		if not abilities.get_item(index).is_empty():
			filled.append(index)
	if filled.is_empty():
		return
	var at := filled.find(_ability_slot)
	if at >= 0:
		select_ability(filled[wrapi(at + step, 0, filled.size())])
		return
	var next := filled[0] if step > 0 else filled[filled.size() - 1]
	for index in filled:
		if step > 0 and index > _ability_slot:
			next = index
			break
		if step < 0 and index < _ability_slot:
			next = index
	select_ability(next)


## Draws a numbered slot. Selecting an empty slot leaves the hands in ability
## mode, just like pressing E with no interactable under the crosshair.
func select_hotbar(index: int) -> void:
	if index < 0 or index >= hotbar.size():
		return
	_weapon_slot = index
	var item_id := hotbar.get_item(index)
	_hotbar_drawn = not item_id.is_empty()
	if _hotbar_drawn:
		if _weapon_bar != null:
			_weapon_bar.select(index)
		_take_up(item_id)
	else:
		holster()


## Compatibility alias for existing tests and menu code.
func select_weapon(index: int) -> void:
	select_hotbar(index)


func holster() -> void:
	_hotbar_drawn = false
	if _weapon_bar != null:
		_weapon_bar.holster()
	_take_up("")


## The wheel only stops on slots holding something, which is the point of having
## three numbered slots and potentially fewer carried items.
func _cycle_weapon(step: int) -> void:
	var filled: Array[int] = []
	for index in hotbar.size():
		if not hotbar.get_item(index).is_empty():
			filled.append(index)
	if filled.is_empty():
		return
	var at := filled.find(_weapon_slot)
	if at >= 0 and _hotbar_drawn:
		select_hotbar(filled[wrapi(at + step, 0, filled.size())])
		return
	# Coming off an empty slot: carry on in the direction asked for rather than
	# jumping back to the first weapon.
	var next := filled[0] if step > 0 else filled[filled.size() - 1]
	for index in filled:
		if step > 0 and index > _weapon_slot:
			next = index
			break
		if step < 0 and index < _weapon_slot:
			next = index
	select_hotbar(next)


## Puts `id` in the hands, or empties them for "". Everything that depends on what
## is held hangs off here, including what other peers are told.
func _take_up(id: String) -> void:
	id = id if ItemDB.accepts_hotbar(id) else ""
	if id == _held:
		return
	_held = id
	Weapons.unequip(character, WEAPON_HAND)
	_held_mesh = null
	if _weapon_pose != null:
		_weapon_pose.set_aimed(false)
		_weapon_pose.hold(ItemDB.hold_of(id))
	var source := ItemDB.scene_path(id)
	if not id.is_empty() and not source.is_empty():
		_held_mesh = Weapons.equip(character, WEAPON_HAND, id, source)
		if _held_mesh != null:
			SurfaceSkin.paint(_held_mesh)
		var cell := ItemDB.cell_size(id)
		if cell > 0 and not _cells.has(id):
			_cells[id] = float(cell)
		LagTracker.note_throttled("weapon", "equip_%s" % id, "drew %s" % id, 0.5)
	_refresh_mesh_list()
	if peer_id == multiplayer.get_unique_id() and multiplayer.has_multiplayer_peer():
		_hold.rpc(_held)


func _on_weapons_changed() -> void:
	# Editing a holstered loadout must not draw it. If a drawn slot is changed,
	# that slot remains authoritative for what the hands show.
	if _hotbar_drawn:
		var item_id := hotbar.get_item(_weapon_slot)
		if item_id.is_empty():
			holster()
		else:
			_take_up(item_id)
	if _weapon_bar != null:
		_weapon_bar.refresh()
	_queue_loadout_save()


func activate_primary() -> void:
	if crawler_holds_abilities():
		_play_safe_zone_dance()
		return
	if not can_attack():
		return
	if _hotbar_drawn and not _held.is_empty():
		_attack()
	else:
		_held_ability_slot = _ability_slot
		activate_ability(_ability_slot)


## Whether this body can begin or continue an offensive action.
##
## Controls remain enabled during a crash because the local body still has to
## simulate its fall. That must not also leave the weapon and ability entry
## points live while its hands are attached to a grab socket or physically limp.
func can_attack() -> bool:
	return not _dead and not _grabbed and not _lassoed and not _forced_ragdoll \
		and _stance != Stance.CRASH and _stance != Stance.GRAPPLE \
		and _arrival_left <= 0.0 \
		and _reveal_left <= 0.0 \
		and not is_status_locked() \
		and not crawler_holds_abilities()


func in_crawler_safe_zone() -> bool:
	return CrawlerRules.active() and CrawlerSafeBox.contains_any(self)


## Cities and safe boxes both wear the Safe Zone chip. Combat stays off in
## either, and a fire click becomes a dance instead of a shot.
func crawler_holds_abilities() -> bool:
	return in_crawler_city() or in_crawler_safe_zone()


func can_edit_crawler_mods() -> bool:
	if not CrawlerRules.active():
		return true
	if crawler_progress != null and crawler_progress.wearing_kit_hat():
		return true
	return crawler_holds_abilities()


func cancel_combat_actions() -> void:
	_interrupt_combat_actions()


func flight_speed() -> float:
	return _cruise if _stance == Stance.FLY else velocity.length()


func world_up() -> Vector3:
	return _up()


## Which of [enum Stance] the body is in. Abilities gate on this — a meteor
## punch means something different from the air than from a run — and nothing
## outside this file should be reading the private field to find out.
func stance() -> int:
	return _stance


## Whether flight presentation is currently using its raised-knee hover end.
## Ability casts capture this into their replicated animation variant.
func uses_float_pose() -> bool:
	return _stance == Stance.FLY and _fly_blend <= 0.45


## How much of the body is under water, 0 to 1. The public form of the same
## question [method _submersion] answers internally.
func submerged_share() -> float:
	return _submersion()


## Where the player is looking, as a unit vector. The camera's forward rather
## than the body's, because on this planet the body is aligned to the ground and
## the head is what aims.
func look_direction() -> Vector3:
	return -camera.global_basis.z


## The point a beam or a shot converges on, given where it starts. The same rule
## weapon fire uses, so an ability aimed at the crosshair lands where a bullet
## aimed at the crosshair would.
func aim_direction(from: Vector3) -> Vector3:
	return _shot_direction(from)


## The ability machinery, or null on a remote peer. For the harnesses.
func ability_controller() -> AbilityController:
	return _ability_controller


## The planet this player is standing on, or null out in space.
func planet() -> Planet:
	return _planet_below()


## Where the two eyes are in the world, left first.
##
## Taken from the [code]Head[/code] bone rather than from the camera, so beams
## leave the face and follow it through whatever clip is playing — including on
## a remote peer, who has no camera of ours to read. The offsets are a property
## of the body, not of this file, which is why they live in [CharacterDB]: the
## next character added will have its own face and nothing here should change.
func eye_points() -> Array[Vector3]:
	var offset := CharacterDB.eye_offset(_body_id)
	var skeleton := Wardrobe.skeleton_of(character) if character != null else null
	if skeleton != null:
		var bone := CharacterRig.find_bone(skeleton, &"Head")
		if bone >= 0:
			# Placed in the body's own space and then carried through the bone,
			# rather than measured out along the bone's own axes.
			#
			# A Head bone's axes are whatever the exporter chose, and the two
			# characters here already disagree: the settler's are the model's,
			# and the astronaut's are turned through half a circle. An offset
			# authored as "so far forward" therefore means opposite things on
			# the two of them, and on the settler it meant backwards — which
			# put the beams out of the back of the neck.
			#
			# `pose * rest⁻¹` is the bone's movement *away from* its rest pose,
			# so applying it to a point placed against the resting body moves
			# that point exactly as the head moves and not at all while the head
			# is still. Nothing here has to know which way the bone faces.
			var rest := skeleton.get_bone_global_rest(bone)
			var frame := skeleton.global_transform \
				* skeleton.get_bone_global_pose(bone) * rest.affine_inverse()
			var middle := rest.origin + Vector3(0.0, offset.y, offset.z)
			var side := Vector3(offset.x, 0.0, 0.0)
			return [frame * (middle - side), frame * (middle + side)]
	# No rig, or a body exported without a head joint. Do not use the camera:
	# in third person it sits behind the skull, and a beam that starts there
	# leaves the back of the head. The body's facing and the camera pivot
	# height keep the sockets on the face instead.
	var eye := global_position \
		+ global_basis.y * head.position.y \
		+ global_basis * Vector3(0.0, 0.0, offset.z)
	var side_step := global_basis.x * offset.x
	return [eye - side_step, eye + side_step]


## The beams this player is firing, built the first time anything asks. Remote
## peers get one too: the packet that drives it arrives before any ability does.
func laser_beams() -> LaserBeams:
	if not is_instance_valid(_laser_beams):
		_laser_beams = LaserBeams.new()
		_laser_beams.name = "LaserBeams"
		add_child(_laser_beams, false, Node.INTERNAL_MODE_BACK)
	return _laser_beams


func lightning_bolts() -> LightningBolts:
	if not is_instance_valid(_lightning_bolts):
		_lightning_bolts = LightningBolts.new()
		_lightning_bolts.name = "LightningBolts"
		add_child(_lightning_bolts, false, Node.INTERNAL_MODE_BACK)
	return _lightning_bolts


## The shock standing off this player's fist, built the first time anything
## asks. Sized to the fist's own damage cylinder, so what is drawn is what the
## punch cuts.
func meteor_shock() -> MeteorShock:
	if not is_instance_valid(_meteor_shock):
		_meteor_shock = MeteorShock.new()
		_meteor_shock.name = "MeteorShock"
		_meteor_shock.radius = METEOR_FIST_RADIUS
		add_child(_meteor_shock, false, Node.INTERNAL_MODE_BACK)
	return _meteor_shock


## Sends one tick of a beam ability to every peer, including this one.
##
## The volume is what travels, not its consequences. Each machine applies it to
## its own flora, which is generated from the same seed and so is the same
## flora — the alternative, listing every plant that was cut, is a packet that
## grows with the size of the field being mown down.
func fire_beam(id: String, left_eye: Vector3, right_eye: Vector3, at: Vector3,
		landed: bool, radius := -1.0, beam_width := 1.0, wobble := 0.0,
		pulse := false) -> void:
	if not can_attack():
		return
	_beam_request_sequence += 1
	if not _has_listeners():
		if id == "lightning":
			Lightning.apply_effect(
				self, id, left_eye, right_eye, at, landed, radius, beam_width,
				wobble, pulse)
		else:
			LaserEyes.apply_effect(
				self, id, left_eye, right_eye, at, landed, radius, beam_width,
				wobble, pulse)
	elif multiplayer.is_server():
		_publish_ability_beam(
			id, left_eye, right_eye, at, landed, radius, beam_width, wobble,
			pulse)
	else:
		_request_ability_beam.rpc_id(
			1, _beam_request_sequence, id, left_eye, right_eye, at, landed,
			radius, beam_width, wobble, pulse)


func _publish_ability_beam(id: String, left_eye: Vector3,
		right_eye: Vector3, at: Vector3, landed: bool,
		radius := -1.0, beam_width := 1.0, wobble := 0.0, pulse := false) -> void:
	if not can_attack() or not _is_replicated_beam(id) \
			or not ItemDB.accepts_ability(id) \
			or not left_eye.is_finite() \
			or not right_eye.is_finite() or not at.is_finite():
		return
	_host_beam_sequence += 1
	_apply_ability_beam.rpc(
		_host_beam_sequence, id, left_eye, right_eye, at, landed,
		radius, beam_width, wobble, pulse)


## Launches a definition-selected projectile on every peer.
func fire_ability_projectile(id: String, from: Vector3, along: Vector3,
		variant := 0) -> int:
	var definition := ItemDB.ability_definition(id)
	var inherited_velocity := velocity
	if not can_attack() or definition == null \
			or not _uses_launched_projectile(definition) \
			or not from.is_finite() or not along.is_finite() \
			or not inherited_velocity.is_finite() \
			or along.length_squared() < 0.001:
		return 0
	_projectile_request_sequence += 1
	_projectile_result_sequence = _projectile_request_sequence
	_projectile_result = ProjectileRequestState.PENDING
	var overlay := crawler_ability_overlay(id)
	if not _has_listeners():
		var spawned := _spawn_ability_projectile(
			id, from, along, inherited_velocity, variant, overlay)
		_projectile_result = ProjectileRequestState.ACCEPTED \
			if spawned else ProjectileRequestState.REJECTED
		return _projectile_request_sequence if spawned else 0
	if multiplayer.is_server():
		var accepted := _publish_ability_projectile(
			_projectile_request_sequence, id, from, along,
			inherited_velocity, variant, overlay)
		if not accepted:
			_projectile_result = ProjectileRequestState.REJECTED
		elif _projectile_result == ProjectileRequestState.PENDING:
			_projectile_result = ProjectileRequestState.ACCEPTED
		return _projectile_request_sequence if accepted else 0
	_request_ability_projectile.rpc_id(
		1, _projectile_request_sequence, id, from, along,
		inherited_velocity, variant, overlay)
	return _projectile_request_sequence


func ability_projectile_request_state(request_sequence: int) -> int:
	if request_sequence <= 0 or request_sequence != _projectile_result_sequence:
		return ProjectileRequestState.REJECTED
	return _projectile_result


func _uses_launched_projectile(definition: AbilityDefinition) -> bool:
	return definition != null and definition.projectile_type in [
		AbilityDefinition.ProjectileType.ENERGY_DISK,
		AbilityDefinition.ProjectileType.ENERGY_ORB,
		AbilityDefinition.ProjectileType.ENERGY_BOLT,
		AbilityDefinition.ProjectileType.ENERGY_ICICLE,
		AbilityDefinition.ProjectileType.TELEPORT_ORB,
		AbilityDefinition.ProjectileType.ENERGY_CONE,
	]


func _publish_ability_projectile(request_sequence: int, id: String,
		from: Vector3, along: Vector3, inherited_velocity: Vector3,
		variant: int, overlay: Dictionary = {}) -> bool:
	var definition := ItemDB.ability_definition(id)
	if not inherited_velocity.is_finite():
		return false
	var from_left := (variant & 1) != 0
	var socket := _projectile_socket(id, from_left)
	var host_along := aim_direction(socket).normalized()
	var host_from := CrawlerReach.shift(socket, host_along, overlay)
	var claimed_along := along.normalized() \
		if along.length_squared() > 0.001 else Vector3.ZERO
	var spawn_tolerance := maxf(
		2.5, velocity.length() * SYNC_INTERVAL * 3.0)
	spawn_tolerance += CrawlerReach.far_cast(overlay) + 0.75
	if not can_attack() or definition == null \
			or not _uses_launched_projectile(definition) \
			or not from.is_finite() or not along.is_finite() \
			or along.length_squared() < 0.001 \
			or from.distance_to(host_from) > spawn_tolerance \
			or host_along.dot(claimed_along) < 0.35 \
			or inherited_velocity.length() > _speed_limit(Stance.FLY) * 1.25:
		return false
	var authoritative_velocity := velocity \
		if velocity.is_finite() else Vector3.ZERO
	_host_projectile_sequence += 1
	_apply_ability_projectile.rpc(
		_host_projectile_sequence, request_sequence, id,
		host_from, host_along, authoritative_velocity, variant, overlay)
	return true


func mouth_point() -> Vector3:
	var up := up_direction if up_direction.length_squared() > 0.01 \
		else Vector3.UP
	return combat_position() + up * 0.22


func _projectile_socket(id: String, from_left: bool) -> Vector3:
	if id == "fus":
		return mouth_point()
	if id == "light_bolt":
		var eyes := eye_points()
		if eyes.size() >= 2:
			return eyes[0] if from_left else eyes[1]
		if not eyes.is_empty():
			return eyes[0]
		return combat_position()
	if CrawlerRules.is_orb_blast(id):
		return merged_hand_point()
	return hand_point(from_left)


func _spawn_ability_projectile(id: String, from: Vector3, along: Vector3,
		inherited_velocity: Vector3, variant: int,
		overlay: Dictionary = {}) -> bool:
	var definition := ItemDB.ability_definition(id)
	if definition == null:
		return false
	# Every peer draws the same flight, but only the host resolves its collision.
	# That keeps reactions, player damage, and terrain deformation out of a
	# client-authored packet while retaining responsive local projectile motion.
	var owns_impact := not multiplayer.has_multiplayer_peer() \
		or multiplayer.is_server()
	var projectile := AbilityProjectile.launch(
		get_parent(), self, id, from, along, owns_impact, inherited_velocity,
		overlay)
	if projectile == null:
		return false
	var from_left := (variant & 1) != 0
	var from_hover := (variant & 2) != 0
	var clip := definition.animation
	if from_hover and from_left \
			and not definition.alternate_hover_animation.is_empty():
		clip = definition.alternate_hover_animation
	elif from_hover and not definition.hover_animation.is_empty():
		clip = definition.hover_animation
	elif from_left and not definition.alternate_animation.is_empty():
		clip = definition.alternate_animation
	if id != "fus":
		play_ability_animation(clip,
			float(definition.stats.get("animation_duration", 0.32)))
	if id == "icicle":
		CrawlerBurst.snow(get_parent(), from, along, 1.05)
	return true


func fire_hero_punch(id: String, from_left := false) -> bool:
	var definition := ItemDB.ability_definition(id)
	if not can_attack() or definition == null or definition.ability_id != id:
		return false
	var overlay := crawler_ability_overlay(id)
	var variant := 1 if from_left else 0
	if uses_float_pose():
		variant |= 2
	if not _has_listeners() or multiplayer.is_server():
		return _publish_hero_punch(id, variant, overlay)
	_request_hero_punch.rpc_id(1, id, variant)
	return true


func _publish_hero_punch(id: String, variant: int, overlay: Dictionary) -> bool:
	var definition := ItemDB.ability_definition(id)
	if not can_attack() or definition == null:
		return false
	_host_hero_punch_sequence += 1
	if not _has_listeners():
		_apply_hero_punch(_host_hero_punch_sequence, id, variant, overlay)
	else:
		_apply_hero_punch.rpc(_host_hero_punch_sequence, id, variant, overlay)
	return true


func play_ability_animation(clip: StringName, duration: float) -> void:
	if clip.is_empty():
		return
	_ability_clip = String(clip)
	_ability_clip_left = maxf(duration, 0.0)


func clear_ability_animation() -> void:
	_ability_clip = ""
	_ability_clip_left = 0.0


func set_beam_root(on: bool, look_scale := 1.0) -> void:
	_beam_root_wanted = 1.0 if on else 0.0
	_beam_look_scale = clampf(look_scale, 0.12, 1.0) if on else 1.0


func beam_look_scale() -> float:
	if _beam_root <= 0.001:
		return 1.0
	return lerpf(1.0, _beam_look_scale, _beam_root)


func set_field_cast(on: bool) -> void:
	_field_cast = on
	if on:
		_beam_root_wanted = 1.0
		_beam_root = 1.0
		_beam_look_scale = 1.0
	else:
		_beam_root_wanted = 0.0
		_beam_root = 0.0
		_beam_look_scale = 1.0


func field_casting() -> bool:
	return _field_cast


func _update_beam_root(delta: float) -> void:
	var rate := 3.4 if _beam_root_wanted > _beam_root else 7.0
	_beam_root = move_toward(_beam_root, _beam_root_wanted, rate * delta)


func _apply_beam_root_brake(delta: float) -> void:
	if _beam_root <= 0.001:
		return
	var brake := 12.0 * _beam_root
	var speed := velocity.length()
	velocity = velocity.move_toward(Vector3.ZERO, maxf(speed, 10.0) * brake * delta)
	if _stance == Stance.FLY:
		_cruise = move_toward(_cruise, 0.0, 70.0 * _beam_root * delta)


func _is_replicated_beam(id: String) -> bool:
	return id == "laser_eyes" or id == "kame" or id == "lightning"


## Cosmetic dust at a laser landing. Beam packets and carbine bolts already run
## on every peer, so this must not send another packet; each copy calls it from
## the impact it resolved locally.
func play_laser_impact_dust(at: Vector3, facing: Vector3,
		sustained := true) -> bool:
	if not is_instance_valid(dust):
		return false
	return dust.laser_impact(
		at, facing,
		0.6 if sustained else 0.82,
		0.55 if sustained else 0.78,
		not sustained)


## Sends the one-off Meteor cloud to every peer. Unlike the beam and bolt, the
## landing itself is simulated only by the player who threw the punch.
func play_meteor_impact_dust(at: Vector3, facing: Vector3,
		radius: float, strength: float) -> void:
	if _has_listeners():
		_meteor_impact_cloud.rpc(at, facing, radius, strength)
	else:
		_meteor_impact_cloud(at, facing, radius, strength)


## Replicated emissive pulse used by data-authored explosive impacts.
func play_ability_explosion(at: Vector3, radius: float, tint: Color,
		duration := EnergyExplosion.LIFE, massive := false,
		nuclear := false) -> void:
	if not at.is_finite() or not is_finite(radius) or not is_finite(duration):
		return
	_ability_explosion_request_sequence += 1
	if not _has_listeners():
		_spawn_ability_explosion(at, radius, tint, duration, massive, nuclear)
	elif multiplayer.is_server():
		_publish_ability_explosion(
			at, radius, tint, duration, massive, nuclear, false)
	else:
		# The owner sees the contact immediately; the host-approved event below
		# supplies the server and every other client.
		_spawn_ability_explosion(at, radius, tint, duration, massive, nuclear)
		_request_ability_explosion.rpc_id(
			1, _ability_explosion_request_sequence, at, radius, tint,
			duration, massive, nuclear)


func _publish_ability_explosion(at: Vector3, radius: float,
		tint: Color, duration: float, massive: bool, nuclear: bool,
		predicted_owner: bool) -> void:
	if not at.is_finite() or not is_finite(radius) or not is_finite(duration):
		return
	_host_ability_explosion_sequence += 1
	_apply_ability_explosion.rpc(
		_host_ability_explosion_sequence, at,
		clampf(radius, 0.2, EnergyExplosion.MAX_RADIUS),
		tint, clampf(duration, 0.12, 2.0), massive, nuclear, predicted_owner)


func _spawn_ability_explosion(at: Vector3, radius: float,
		tint: Color, duration := EnergyExplosion.LIFE,
		massive := false, nuclear := false) -> void:
	EnergyExplosion.burst(
		get_parent(), at, clampf(radius, 0.2, EnergyExplosion.MAX_RADIUS), tint,
		clampf(duration, 0.12, 2.0), massive, nuclear)


## Asks the world to cut a mark into the ground. Routed through the player
## because an ability holds one and should not be hunting for the world node.
func request_scar(scar: TerrainScars.Scar) -> void:
	var world := get_parent() as GameWorld
	if world != null:
		world.request_scar(scar)


# --- Combat -----------------------------------------------------------------

func combat_faction() -> int:
	return DamageHit.Faction.ENEMY if training_enemy else DamageHit.Faction.PLAYER


func combat_peer_id() -> int:
	return 0 if training_enemy else peer_id


func combat_display_name() -> String:
	return "Enemy Player" if training_enemy else display_name


func is_training_enemy() -> bool:
	return training_enemy


func combat_position() -> Vector3:
	var frame := Engine.get_physics_frames()
	if frame == _combat_pos_frame:
		return _combat_pos
	_combat_pos_frame = frame
	_combat_pos = global_position + _up() * (_stance_height(_stance) * 0.5)
	return _combat_pos


func combat_radius() -> float:
	return maxf(_stance_height(_stance) * 0.42, 0.35)


func health() -> float:
	return stats.health()


func maximum_health() -> float:
	return stats.base_of(PlayerStats.HEALTH)


func is_dead() -> bool:
	return _dead


## Why this player is on the floor, as the death screen puts it. Empty while
## alive.
func death_cause() -> String:
	return _death_cause


## The overlay in front of the local player, or null: while alive, and on every
## body but their own.
func death_screen() -> DeathScreen:
	return _death_screen if is_instance_valid(_death_screen) else null


func nearest_downed_teammate() -> OnlinePlayer:
	if _dead or training_enemy:
		return null
	return CrawlerRules.nearest_downed_teammate(self) as OnlinePlayer


func revive_hold_progress() -> float:
	if CrawlerRules.REVIVE_HOLD <= 0.0:
		return 0.0
	return clampf(_revive_elapsed / CrawlerRules.REVIVE_HOLD, 0.0, 1.0)


func tick_revive_hold(delta: float, holding: bool) -> void:
	var target := nearest_downed_teammate()
	if target == null or not holding or _dead or _menu_open:
		_revive_elapsed = 0.0
		return
	_revive_elapsed += maxf(delta, 0.0)
	if _revive_elapsed + 0.0001 >= CrawlerRules.REVIVE_HOLD:
		_revive_elapsed = 0.0
		try_revive_nearby()


func try_revive_nearby() -> bool:
	var target := nearest_downed_teammate()
	if target == null:
		return false
	var world := DamageHit.game_world_of(self)
	if world != null and world.has_method(&"request_revive_player"):
		if multiplayer.has_multiplayer_peer() and not multiplayer.is_server():
			world.request_revive_player.rpc_id(1, target.peer_id)
		else:
			world.request_revive_player(target.peer_id)
		return true
	return _apply_revive_local(target)


func refresh_crawler_death_overlay() -> void:
	if not _dead or training_enemy:
		return
	if peer_id != multiplayer.get_unique_id():
		return
	if not is_instance_valid(_death_screen):
		return
	_present_crawler_death(_death_cause)
	_bind_death_screen_actions()


func _present_crawler_death(cause: String) -> void:
	if not is_instance_valid(_death_screen):
		return
	if CrawlerRules.coop() and not CrawlerRules.crawler_party_wiped():
		_death_screen.present_downed(cause, CrawlerRules.crawler_has_respawn_ticket())
		return
	var progress := crawler_progress
	var can_ticket := CrawlerRules.crawler_has_respawn_ticket()
	var can_respawn := can_ticket or CrawlerRules.crawler_free_respawn()
	var recap := {}
	if progress != null and not can_ticket:
		recap = CrawlerMeta.settle_run(progress, journal)
	_death_screen.present_crawler(
		cause,
		progress.run_summary() if progress != null else "",
		can_respawn,
		recap
	)


func _apply_revive_local(target: OnlinePlayer) -> bool:
	if target == null or not is_instance_valid(target) or not target.is_dead():
		return false
	if _dead or training_enemy:
		return false
	if global_position.distance_to(target.global_position) \
			> CrawlerRules.REVIVE_REACH + 0.35:
		return false
	target.respawn_at(target.global_transform)
	return true


func _notify_crawler_party_changed() -> void:
	if training_enemy or not CrawlerRules.active():
		return
	if CrawlerRules.duel_active() or CrawlerRules.training_active():
		return
	var world := DamageHit.game_world_of(self)
	if world != null and world.has_method(&"note_crawler_party_changed"):
		world.note_crawler_party_changed()
		return
	for player_variant: Variant in CrawlerRules.crawler_party():
		var player := player_variant as OnlinePlayer
		if player != null and player.has_method(&"refresh_crawler_death_overlay"):
			player.refresh_crawler_death_overlay()


func is_status_locked() -> bool:
	return statuses.movement_locked()


func has_status(id: StringName) -> bool:
	return statuses.has(id)


func status_remaining(id: StringName) -> float:
	return statuses.remaining(id)


func status_rows() -> Array[Dictionary]:
	var rows := statuses.rows()
	if crawler_holds_abilities():
		rows.append({
			"id": &"safe_zone",
			"title": "Safe Zone",
			"description": "Ability mods can be moved.",
			"remaining": 0.0,
			"lasting": true,
			"text": "",
		})
	if gold_cape_active():
		rows.append({
			"id": &"gold_cape",
			"title": "Gold Cape",
			"description": "Hits bounce back.",
			"remaining": _gold_cape_left,
			"lasting": false,
			"text": "",
		})
	return rows


func status_snapshot() -> Dictionary:
	return statuses.to_wire()


func can_fly() -> bool:
	if CrawlerRules.active() and not CrawlerRules.sandbox_fast() \
			and _flight_fuel <= 0.02:
		return false
	return not _dead and not _grabbed and not _lassoed \
		and not statuses.has(CombatStatuses.FLIGHTLESS)


## Stable late-join representation. Every key has a safe fallback in
## [method apply_combat_snapshot], so snapshots made before combat existed still
## load as a living, full-health player.
func combat_snapshot() -> Dictionary:
	return {
		"health": stats.health(),
		"maximum_health": stats.base_of(PlayerStats.HEALTH),
		"dead": _dead,
		"death_cause": _death_cause,
		"statuses": statuses.to_wire(),
		"parry_window": _parry_window_left,
		"parry_perfect": _parry_perfect_left,
		"parry_cooldown": _parry_cooldown_left,
		"ward_up": _ward_up,
		"ward_hits": _ward_hits_left,
		"ward_recharge": _ward_recharge,
		"stagger": _stagger_left,
		"forced_ragdoll": _forced_ragdoll,
		"velocity": velocity,
		"grabbed": _grabbed,
		"grab_socket": String(_grab_socket_path),
		"grab_offset": _grab_offset,
		"lassoed": _lassoed,
		"lasso_source_peer": _lasso_source_peer,
		"flight_fuel": _flight_fuel,
		"crawler": crawler_progress.to_dict() if crawler_progress != null else {},
	}


func apply_combat_snapshot(snapshot: Dictionary) -> void:
	var maximum := float(snapshot.get(
		"maximum_health", stats.base_of(PlayerStats.HEALTH)))
	if is_finite(maximum) and maximum > 0.0:
		stats.set_base(PlayerStats.HEALTH, maximum)
	var next_health := float(snapshot.get(
		"health", stats.base_of(PlayerStats.HEALTH)))
	stats.set_health(next_health if is_finite(next_health) else maximum)
	var status_wire: Variant = snapshot.get("statuses", {})
	statuses.apply_wire(status_wire as Dictionary if status_wire is Dictionary else {})
	_parry_window_left = maxf(float(snapshot.get("parry_window", 0.0)), 0.0)
	_parry_perfect_left = minf(maxf(
		float(snapshot.get("parry_perfect", 0.0)), 0.0), _parry_window_left)
	_parry_cooldown_left = maxf(float(snapshot.get("parry_cooldown", 0.0)), 0.0)
	_ward_up = bool(snapshot.get("ward_up", _ward_up))
	_ward_hits_left = maxi(int(snapshot.get("ward_hits", _ward_hits_left)), 0)
	_ward_recharge = maxf(float(snapshot.get("ward_recharge", _ward_recharge)), 0.0)
	_update_ward_bubble()
	_stagger_left = maxf(float(snapshot.get("stagger", 0.0)), 0.0)
	if snapshot.has("flight_fuel"):
		_flight_fuel = clampf(float(snapshot.get("flight_fuel", 1.0)), 0.0, 1.0)
	var crawler_wire: Variant = snapshot.get("crawler", {})
	if crawler_progress != null and crawler_wire is Dictionary \
			and not (crawler_wire as Dictionary).is_empty():
		crawler_progress.from_dict(crawler_wire)
		_apply_crawler_progress()
		CrawlerSites.apply_progress(crawler_progress, get_tree())
	var velocity_variant: Variant = snapshot.get("velocity", velocity)
	if velocity_variant is Vector3 and (velocity_variant as Vector3).is_finite():
		velocity = velocity_variant
	_grabbed = bool(snapshot.get("grabbed", false))
	_grab_socket_path = NodePath(String(snapshot.get("grab_socket", ""))) \
		if _grabbed else NodePath()
	_grab_socket_node = null
	var offset_variant: Variant = snapshot.get(
		"grab_offset", Transform3D.IDENTITY)
	_grab_offset = offset_variant as Transform3D \
		if offset_variant is Transform3D else Transform3D.IDENTITY
	_lassoed = bool(snapshot.get("lassoed", false))
	_lasso_source_peer = maxi(int(snapshot.get("lasso_source_peer", 0)), 0) \
		if _lassoed else 0
	if collider != null:
		collider.set_deferred(&"disabled", _grabbed)
	var was_dead := _dead
	_dead = bool(snapshot.get("dead", false))
	_death_cause = String(snapshot.get(
		"death_cause", DeathScreen.DEFAULT_NOTICE)) if _dead else ""
	var snapshot_forced := bool(snapshot.get("forced_ragdoll", false))
	if _grabbed or _lassoed:
		_interrupt_combat_actions()
	if _dead:
		if not _forced_ragdoll:
			_force_full_ragdoll_local(velocity, DAMAGE_RAGDOLL_TIME)
		if not was_dead:
			_interrupt_combat_actions()
			died.emit(0, _death_cause)
	elif snapshot_forced and not _dead:
		if not _forced_ragdoll:
			_force_full_ragdoll_local(velocity, DAMAGE_RAGDOLL_TIME)
	elif not _dead and (was_dead or _forced_ragdoll):
		_clear_ragdoll()


func respawn_at(at_transform: Transform3D, sequence := 0) -> void:
	if sequence > 0 and sequence <= _respawn_sequence:
		return
	_respawn_sequence = maxi(sequence, _respawn_sequence + 1)
	_dead = false
	_death_cause = ""
	_grabbed = false
	_lassoed = false
	_lasso_source_peer = 0
	_grab_socket_path = NodePath()
	_grab_socket_node = null
	_grab_offset = Transform3D.IDENTITY
	collider.set_deferred(&"disabled", false)
	statuses.clear()
	_parry_window_left = 0.0
	_parry_perfect_left = 0.0
	_parry_cooldown_left = 0.0
	_juke_left = 0.0
	_juke_cooldown_left = 0.0
	_juke_carry = Vector3.ZERO
	_gold_cape_left = 0.0
	_gold_cape_cooldown_left = 0.0
	_sync_gold_cape_visual()
	if crawler_progress != null and crawler_progress.wearing_ward_hat():
		_raise_ward_bubble()
		_ward_recharge = 0.0
	else:
		_ward_up = false
		_ward_hits_left = 0
		_ward_recharge = 0.0
	_clear_ragdoll()
	stats.set_health(stats.base_of(PlayerStats.HEALTH))
	velocity = Vector3.ZERO
	global_transform = at_transform
	reset_physics_interpolation()
	reset_network_state(at_transform)
	if CrawlerRules.active() and not training_enemy:
		arm_spawn_arrival()
		play_spawn_arrival()
	respawned.emit()
	_notify_crawler_party_changed()
	LagTracker.note("spawn", "respawn peer %d" % peer_id)


## Host-authoritative entry point used by [DamageHit]. Returns actual HP lost.
func apply_damage(hit: DamageHit) -> float:
	if hit == null or _dead or not _is_host_authority():
		return 0.0
	if CrawlerRules.sandbox_invincible() and not training_enemy:
		_preview_incoming_hit(hit)
		return 0.0
	if training_enemy:
		if hit.faction != DamageHit.Faction.PLAYER:
			return 0.0
	elif hit.faction != DamageHit.Faction.ENEMY:
		return 0.0
	if not training_enemy and hit.target_peer > 0 and hit.target_peer != peer_id:
		return 0.0
	if gold_cape_active():
		_accept_gold_cape_hit(hit)
		return 0.0
	if juke_active():
		return 0.0
	if hit.parryable and parry_active():
		_accept_parry_hit(hit)
		return 0.0
	if _try_crawler_dodge(hit):
		_broadcast_combat_state(0.0, hit, false, false, false, true)
		return 0.0
	if _phase_hat_blocks(hit):
		_broadcast_combat_state(0.0, hit, false, false, false, true)
		return 0.0
	if _ordinance_hat_blocks(hit):
		_broadcast_combat_state(0.0, hit, false, false, false)
		return 0.0
	if _rubber_hat_blocks(hit):
		_broadcast_combat_state(0.0, hit, false, false, false)
		return 0.0
	if _absorb_ward_hit(hit):
		return 0.0

	var before := stats.health()
	var authored_amount := _incoming_hit_amount(hit)
	var actual := minf(authored_amount, before)
	if actual > 0.0:
		stats.set_health(before - actual)
	var status_impact := CrawlerElements.apply_to_combatant(self, hit)
	var became_dead := stats.health() <= 0.0 and before > 0.0
	if became_dead:
		_die(hit)
	_broadcast_combat_state(actual, hit, status_impact, false, false)
	if actual > 0.0 and not became_dead:
		_trigger_fool_hat()
	return actual


func apply_heal(amount: float) -> float:
	if not _is_host_authority() or _dead:
		return 0.0
	var before := stats.health()
	var next := minf(before + maxf(amount, 0.0), maximum_health())
	if next <= before:
		return 0.0
	stats.set_health(next)
	var hit := DamageHit.impact(combat_position(), 0.1, 0.0)
	hit.faction = DamageHit.Faction.NEUTRAL
	_broadcast_combat_state(0.0, hit, false, false, false)
	return next - before


func _accept_gold_cape_hit(hit: DamageHit) -> void:
	var source := hit.source_node(self)
	var reflected := hit.amount if hit != null and is_finite(hit.amount) else 0.0
	if source != null and reflected > 0.0 \
			and source.has_method(&"receive_reflected_damage"):
		source.call(&"receive_reflected_damage", reflected, peer_id)
	if character != null:
		CombatantFlash.flash(
			character,
			Color(1.0, 0.84, 0.22),
			0.22,
			0.72,
			"GoldCapeFlashOverlay"
		)
	_broadcast_combat_state(0.0, hit, false, false, false)


func _accept_parry_hit(hit: DamageHit) -> void:
	var perfect := parry_perfect_active()
	parry_blocked.emit(perfect, hit)
	if perfect:
		var source := hit.source_node(self)
		var reflected := hit.reflection if hit.reflection > 0.0 else hit.amount
		if not is_finite(reflected):
			reflected = 0.0
		if source != null and reflected > 0.0 \
				and source.has_method(&"receive_reflected_damage"):
			source.call(&"receive_reflected_damage", reflected, peer_id)
	_broadcast_combat_state(0.0, hit, false, true, perfect)


## Forces the existing full-body ragdoll without changing HP. Future enemy code
## can use this for authored grabs/throws without reaching into controller state.
func force_full_ragdoll(throw_velocity := Vector3.ZERO) -> bool:
	if not _is_host_authority() or _dead:
		return false
	var hit := DamageHit.impact(combat_position(), combat_radius(), 0.0)
	hit.faction = DamageHit.Faction.ENEMY
	hit.target_peer = peer_id
	hit.reaction = DamageHit.Reaction.RAGDOLL
	hit.world_impulse = throw_velocity
	_broadcast_combat_state(0.0, hit, false, false, false)
	return true


## Attaches every network copy to the same world-relative socket.
func grab_at_socket(socket: Node3D,
		offset := Transform3D.IDENTITY) -> bool:
	if not _is_host_authority() or _dead or socket == null \
			or not DamageHit.in_same_world(self, socket):
		return false
	var world := DamageHit.game_world_of(self)
	if world == null:
		return false
	_grab_sequence += 1
	var path := world.get_path_to(socket)
	if _has_listeners():
		_apply_grab_state.rpc(_grab_sequence, String(path), offset, Vector3.ZERO)
	else:
		_apply_grab_state(_grab_sequence, String(path), offset, Vector3.ZERO)
	return true


func attach_to_socket(socket: Node3D,
		offset := Transform3D.IDENTITY) -> bool:
	return grab_at_socket(socket, offset)


## Releases a socket and, when given velocity, throws directly into the full
## ragdoll path.
func release_grab(throw_velocity := Vector3.ZERO) -> bool:
	if not _is_host_authority() or not _grabbed:
		return false
	_grab_sequence += 1
	if _has_listeners():
		_apply_grab_state.rpc(_grab_sequence, "", Transform3D.IDENTITY,
			throw_velocity)
	else:
		_apply_grab_state(_grab_sequence, "", Transform3D.IDENTITY,
			throw_velocity)
	return true


func is_grabbed() -> bool:
	return _grabbed


func can_be_lassoed() -> bool:
	return not _dead and not _grabbed and not _lassoed \
		and not _forced_ragdoll


func begin_lasso(source: Node3D) -> bool:
	if not can_be_lassoed() or source == null:
		return false
	_lassoed = true
	_lasso_source_peer = int(source.get("peer_id")) \
		if source.get("peer_id") != null else 0
	_interrupt_combat_actions()
	if collider != null:
		collider.set_deferred(&"disabled", false)
	return true


func lasso_simulate(motion: Vector3,
		next_velocity: Vector3) -> Dictionary:
	if not _is_host_authority() or not _lassoed \
			or not motion.is_finite() or not next_velocity.is_finite():
		return {}
	var collision := move_and_collide(motion)
	velocity = next_velocity
	_host_last_position = global_position
	_host_has_state = true
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
	if _is_host_authority() or not _lassoed \
			or not at.is_finite() or not next_velocity.is_finite():
		return
	global_transform = at
	velocity = next_velocity
	_target_transform = at
	_target_velocity = next_velocity
	_extrapolated = 0.0
	reset_physics_interpolation()


func end_lasso(throw_velocity: Vector3) -> void:
	if not _lassoed:
		return
	_lassoed = false
	_lasso_source_peer = 0
	if throw_velocity.is_finite():
		velocity = throw_velocity
	if collider != null:
		collider.set_deferred(&"disabled", false)
	if _is_host_authority() and velocity.length_squared() > 1.0:
		force_full_ragdoll(velocity)


func lasso_mass() -> float:
	return 1.0


func is_lassoed() -> bool:
	return _lassoed


func grab_socket() -> Node3D:
	if is_instance_valid(_grab_socket_node):
		return _grab_socket_node
	var world := DamageHit.game_world_of(self)
	if world == null or _grab_socket_path.is_empty():
		return null
	_grab_socket_node = world.get_node_or_null(_grab_socket_path) as Node3D
	return _grab_socket_node


func request_parry() -> bool:
	if CrawlerRules.active():
		return false
	if peer_id != multiplayer.get_unique_id() or not can_attack():
		return false
	_parry_request_sequence += 1
	if _is_host_authority():
		return _server_accept_parry(_parry_request_sequence, peer_id)
	_request_parry.rpc_id(1, _parry_request_sequence)
	return true


func parry_active() -> bool:
	return _parry_window_left > 0.0


func parry_perfect_active() -> bool:
	return _parry_perfect_left > 0.0 and _parry_window_left > 0.0


func parry_window_remaining() -> float:
	return _parry_window_left


func parry_perfect_remaining() -> float:
	return _parry_perfect_left


func parry_cooldown_remaining() -> float:
	return _parry_cooldown_left


func request_juke() -> bool:
	if peer_id != multiplayer.get_unique_id() or not can_juke():
		return false
	var along := _juke_wish_direction()
	if along.length_squared() < 0.0001:
		return false
	_juke_request_sequence += 1
	if _is_host_authority():
		return _server_accept_juke(_juke_request_sequence, peer_id, along)
	_request_juke.rpc_id(1, _juke_request_sequence, along)
	return true


func can_juke() -> bool:
	return can_attack() \
		and not _field_cast \
		and _juke_cooldown_left <= 0.0 \
		and _juke_left <= 0.0 \
		and _stance != Stance.METEOR \
		and _stance != Stance.GRAPPLE \
		and _stance != Stance.HERO


func juke_active() -> bool:
	return _juke_left > 0.0


func juke_direction() -> Vector3:
	return _juke_along


func juke_cooldown_remaining() -> float:
	return _juke_cooldown_left


func wearing_gold_cape() -> bool:
	return crawler_progress != null and crawler_progress.wearing_gold_cape()


func gold_cape_active() -> bool:
	return _gold_cape_left > 0.0


func cape_ability_id() -> String:
	if wearing_gold_cape():
		return CrawlerProgress.CAPE_GOLD
	if gold_cape_active() or _gold_cape_cooldown_left > 0.0:
		return CrawlerProgress.CAPE_GOLD
	return ""


func cape_hud_visible() -> bool:
	return not cape_ability_id().is_empty()


func cape_ability_cooldown() -> float:
	return CrawlerRules.GOLD_CAPE_COOLDOWN


func cape_ability_cooldown_remaining() -> float:
	return _gold_cape_cooldown_left


func can_use_cape_ability() -> bool:
	return not training_enemy and not _dead and not _grabbed \
			and not _lassoed and not _forced_ragdoll \
			and wearing_gold_cape() \
			and _gold_cape_left <= 0.0 \
			and _gold_cape_cooldown_left <= 0.0


func request_cape_ability() -> bool:
	if peer_id != multiplayer.get_unique_id() or not can_use_cape_ability():
		return false
	_gold_cape_request_sequence += 1
	if _is_host_authority():
		return _server_accept_cape_ability(_gold_cape_request_sequence, peer_id)
	_request_cape_ability.rpc_id(1, _gold_cape_request_sequence)
	return true


func _server_accept_cape_ability(request_sequence: int, sender: int) -> bool:
	if not _is_host_authority() or sender != peer_id \
			or request_sequence <= _last_gold_cape_request_sequence:
		return false
	_last_gold_cape_request_sequence = request_sequence
	if not can_use_cape_ability():
		return false
	_gold_cape_event_sequence += 1
	var duration := CrawlerRules.GOLD_CAPE_DURATION
	var wait := CrawlerRules.GOLD_CAPE_COOLDOWN
	if _has_listeners():
		_apply_cape_ability_state.rpc(_gold_cape_event_sequence, duration, wait)
	else:
		_apply_cape_ability_state(_gold_cape_event_sequence, duration, wait)
	return true


func _juke_wish_direction() -> Vector3:
	var input := _steer_vector()
	var airborne := _stance == Stance.FLY or _stance == Stance.SWIM
	var along := Vector3.ZERO
	if input.length_squared() > 0.0001:
		# Same WASD frame walking and flying already use, so W jukes the
		# way the body already runs and S is the only back dash.
		if airborne:
			along = camera.global_basis * Vector3(input.x, 0.0, input.y)
		else:
			along = _flat(global_basis * Vector3(input.x, 0.0, input.y))
	else:
		# No steer key: dash toward the look, not back through the camera.
		along = look_direction()
		if not airborne:
			along = _flat(along)
			if along.length_squared() < 0.0001:
				along = _flat(-global_basis.z)
	if along.length_squared() < 0.0001:
		along = look_direction() if airborne else -global_basis.z
	return along.normalized()


func _server_accept_juke(request_sequence: int, sender: int,
		along: Vector3) -> bool:
	if not _is_host_authority() or sender != peer_id \
			or request_sequence <= _last_juke_request_sequence:
		return false
	_last_juke_request_sequence = request_sequence
	if not can_juke() or not along.is_finite() \
			or along.length_squared() < 0.0001:
		return false
	_juke_event_sequence += 1
	along = along.normalized()
	var wait := juke_cooldown()
	var carry := velocity if velocity.is_finite() else Vector3.ZERO
	if _has_listeners():
		_apply_juke_state.rpc(
			_juke_event_sequence, along, JUKE_TIME, wait, carry)
	else:
		_apply_juke_state(
			_juke_event_sequence, along, JUKE_TIME, wait, carry)
	return true


func _juke_move(delta: float) -> void:
	var burst := juke_distance() / maxf(JUKE_TIME, 0.01)
	if _juke_along.length_squared() > 0.0001:
		var carry := _juke_carry if _juke_carry.is_finite() else Vector3.ZERO
		velocity = carry + _juke_along * burst
	if _stance == Stance.FLY:
		_flight_velocity = velocity
	floor_snap_length = _floor_snap if _grounded() else 0.0
	var carried := velocity
	move_and_slide()
	_resolve_flora_contacts(carried)
	_catch_ground()
	_juke_hat_strike()


func _update_juke_afterimages(delta: float) -> void:
	if _juke_left <= 0.0:
		_juke_ghost_acc = 0.0
		return
	_juke_ghost_acc += delta
	while _juke_ghost_acc >= JUKE_GHOST_GAP:
		_juke_ghost_acc -= JUKE_GHOST_GAP
		_spawn_juke_afterimage()


func _spawn_juke_afterimage() -> void:
	if character == null or not is_instance_valid(character):
		return
	var world := get_parent()
	if world == null:
		return
	JukeAfterimageScript.spawn(character, world)


func _server_accept_parry(request_sequence: int, sender: int) -> bool:
	if not _is_host_authority() or sender != peer_id \
			or request_sequence <= _last_parry_request_sequence:
		return false
	_last_parry_request_sequence = request_sequence
	if not can_attack() or _parry_cooldown_left > 0.0:
		return false
	_parry_event_sequence += 1
	var window := maxf(parry_window, 0.01)
	var perfect := minf(maxf(parry_perfect_window, 0.0), window)
	var cooldown := maxf(parry_cooldown, window)
	if _has_listeners():
		_apply_parry_state.rpc(
			_parry_event_sequence, window, perfect, cooldown)
	else:
		_apply_parry_state(
			_parry_event_sequence, window, perfect, cooldown)
	return true


func _incoming_hit_amount(hit: DamageHit) -> float:
	if hit == null or not is_finite(hit.amount):
		return 0.0
	var authored := maxf(hit.amount, 0.0)
	if authored <= 0.0:
		return 0.0
	return authored * (1.0 - crawler_defense_share())


func _preview_incoming_hit(hit: DamageHit) -> void:
	var shown := _incoming_hit_amount(hit)
	if shown <= 0.0:
		return
	_broadcast_combat_state(shown, hit, false, false, false)


func _incoming_popup_at() -> Vector3:
	return combat_position() + _up() * 0.55


func _broadcast_combat_state(actual_damage: float, hit: DamageHit,
		status_impact: bool, blocked: bool, perfect: bool,
		dodged := false) -> void:
	_combat_state_sequence += 1
	var negated := blocked or dodged
	var effect := {
		"actual_damage": maxf(actual_damage, 0.0),
		"at": hit.centre(),
		"source_peer": hit.source_peer,
		"source_name": hit.attacker_name(self),
		"ability_name": hit.ability_display_name(),
		"reaction": int(DamageHit.Reaction.NONE if negated else hit.reaction),
		"world_impulse": Vector3.ZERO if negated else hit.world_impulse,
		"status_impact": status_impact and not negated,
		"blocked": blocked,
		"perfect": perfect,
		"dodged": dodged,
	}
	if _dead and not negated:
		effect["reaction"] = DamageHit.Reaction.RAGDOLL
	if _has_listeners():
		_apply_combat_state.rpc(
			_combat_state_sequence, combat_snapshot(), effect)
	else:
		_apply_combat_state(
			_combat_state_sequence, combat_snapshot(), effect)


func _die(hit: DamageHit) -> void:
	if _dead:
		return
	_dead = true
	_death_cause = _death_notice(hit)
	end_overdrive()
	_interrupt_combat_actions()
	_grabbed = false
	_lassoed = false
	_lasso_source_peer = 0
	_grab_socket_path = NodePath()
	_grab_socket_node = null
	if collider != null:
		collider.set_deferred(&"disabled", false)
	died.emit(hit.source_peer if hit != null else 0, _death_cause)
	_notify_crawler_party_changed()


## One line for the death screen. Named attackers get the credit; anything that
## cannot be attributed — a source already gone from the tree, a future hazard —
## reads as a plain death rather than as a killer called nothing.
func _death_notice(hit: DamageHit) -> String:
	if hit == null:
		return DeathScreen.DEFAULT_NOTICE
	var attacker := hit.attacker_name(self)
	if attacker.is_empty():
		return DeathScreen.DEFAULT_NOTICE
	var attack := hit.ability_display_name()
	if not attack.is_empty():
		return "Killed by %s: %s" % [attacker, attack]
	return "Killed by %s" % attacker


func _cancel_active_abilities() -> void:
	if is_instance_valid(_ability_controller) \
			and _ability_controller.has_method(&"cancel_all"):
		_ability_controller.call(&"cancel_all")
	for index in abilities.size():
		release_ability(index)


func _interrupt_combat_actions() -> void:
	_cancel_active_abilities()
	_parry_window_left = 0.0
	_parry_perfect_left = 0.0
	_juke_left = 0.0
	if _weapon_pose != null:
		_weapon_pose.interrupt_attack()


func _apply_authoritative_reaction(effect: Dictionary) -> void:
	var reaction := clampi(int(effect.get("reaction", DamageHit.Reaction.NONE)),
		0, DamageHit.Reaction.size() - 1)
	var impulse_variant: Variant = effect.get("world_impulse", Vector3.ZERO)
	var impulse := impulse_variant as Vector3 if impulse_variant is Vector3 \
		else Vector3.ZERO
	if not impulse.is_finite():
		impulse = Vector3.ZERO
	match reaction:
		DamageHit.Reaction.STAGGER:
			_stagger_left = maxf(_stagger_left, DEFAULT_STAGGER_TIME)
			velocity += impulse * 0.35
			if _ragdoll != null and _ragdoll.built() and not _ragdoll.limp():
				_ragdoll.take_hit(
					effect.get("at", combat_position()), impulse,
					-_up() * _gravity())
		DamageHit.Reaction.KNOCKBACK:
			_stagger_left = maxf(_stagger_left, DEFAULT_STAGGER_TIME)
			velocity += impulse
		DamageHit.Reaction.RAGDOLL:
			var carried := velocity + impulse
			velocity = carried
			_force_full_ragdoll_local(carried, DAMAGE_RAGDOLL_TIME)


func _force_full_ragdoll_local(carried: Vector3, minimum_time: float) -> void:
	if _stance != Stance.CRASH:
		_begin_crash(carried, true)
	_forced_ragdoll = true
	_forced_recovery_started = false
	_forced_ragdoll_left = maxf(minimum_time, DAMAGE_RAGDOLL_TIME)
	_crash_left = maxf(_crash_left, maxf(minimum_time, DAMAGE_RAGDOLL_TIME))


func _clear_ragdoll() -> void:
	_forced_ragdoll = false
	_forced_recovery_started = false
	_forced_ragdoll_left = 0.0
	_stagger_left = 0.0
	if _ragdoll != null:
		_ragdoll.stand_up()
	if _weapon_pose != null:
		_weapon_pose.active = true
	floor_snap_length = _floor_snap
	_apply_stance(Stance.STAND)


func _tick_combat(delta: float) -> void:
	_parry_window_left = maxf(_parry_window_left - delta, 0.0)
	_parry_perfect_left = minf(
		maxf(_parry_perfect_left - delta, 0.0), _parry_window_left)
	_parry_cooldown_left = maxf(_parry_cooldown_left - delta, 0.0)
	_juke_left = maxf(_juke_left - delta, 0.0)
	_juke_cooldown_left = maxf(_juke_cooldown_left - delta, 0.0)
	_gold_cape_left = maxf(_gold_cape_left - delta, 0.0)
	_gold_cape_cooldown_left = maxf(_gold_cape_cooldown_left - delta, 0.0)
	_tick_gold_cape_visual(delta)
	_stagger_left = maxf(_stagger_left - delta, 0.0)
	_tick_ward(delta)
	_tick_missile_hat(delta)
	_tick_mine_hat(delta)
	_tick_repeater_hat(delta)
	_fool_cape_lock = maxf(_fool_cape_lock - delta, 0.0)
	_tick_overdrive(delta)
	var expired := statuses.tick(delta)
	_emit_local_status_floats()
	if expired and _is_host_authority():
		var quiet := DamageHit.impact(combat_position(), 0.01, 0.0)
		quiet.faction = DamageHit.Faction.ENEMY
		_broadcast_combat_state(0.0, quiet, false, false, false)


func _update_parry_shield() -> void:
	if _parry_shield == null:
		return
	var share := _parry_window_left / maxf(parry_window, 0.01)
	_parry_shield.set_state(
		parry_active(), parry_perfect_active(), clampf(share, 0.0, 1.0))


func ward_active() -> bool:
	return _ward_up and crawler_progress != null \
		and crawler_progress.wearing_ward_hat() and not _dead


func ward_recharge_left() -> float:
	return _ward_recharge


func _absorb_ward_hit(hit: DamageHit) -> bool:
	if not ward_active():
		return false
	var amount := hit.amount if hit != null and is_finite(hit.amount) else 0.0
	if amount <= 0.0:
		return false
	_ward_hits_left = maxi(_ward_hits_left - 1, 0)
	if _ward_hits_left <= 0:
		_ward_up = false
		_ward_recharge = CrawlerProgress.WARD_RESPAWN
	_update_ward_bubble()
	_broadcast_combat_state(0.0, hit, false, false, false)
	return true


func _tick_ward(delta: float) -> void:
	if not _is_host_authority():
		return
	if crawler_progress == null or not crawler_progress.wearing_ward_hat() \
			or _dead:
		if _ward_up or _ward_recharge > 0.0:
			_ward_up = false
			_ward_hits_left = 0
			_ward_recharge = 0.0
		return
	if _ward_up:
		return
	var before := _ward_recharge
	_ward_recharge = maxf(_ward_recharge - delta, 0.0)
	if before > 0.0 and _ward_recharge <= 0.0:
		_raise_ward_bubble()
		_update_ward_bubble()
		var quiet := DamageHit.impact(combat_position(), 0.01, 0.0)
		quiet.faction = DamageHit.Faction.ENEMY
		_broadcast_combat_state(0.0, quiet, false, false, false)


func _sync_ward_from_hat() -> void:
	if crawler_progress != null and crawler_progress.wearing_ward_hat() \
			and not _dead:
		if not _ward_up and _ward_recharge <= 0.0:
			_raise_ward_bubble()
		elif _ward_up:
			_ward_hits_left = maxi(_ward_hits_left, 1)
	else:
		_ward_up = false
		_ward_hits_left = 0
		_ward_recharge = 0.0
	_update_ward_bubble()


func _raise_ward_bubble() -> void:
	_ward_up = true
	var charges := crawler_progress.ward_charges() if crawler_progress != null else 1
	_ward_hits_left = maxi(charges, 1)


func _tick_missile_hat(delta: float) -> void:
	if not _is_host_authority() or not CrawlerRules.active():
		return
	if crawler_progress == null or not crawler_progress.wearing_missile_hat() \
			or _dead:
		_missile_cooldown = 0.0
		return
	_missile_cooldown = maxf(_missile_cooldown - delta, 0.0)
	if _missile_cooldown > 0.0:
		return
	var prey := _nearest_missile_mob()
	if prey == null:
		return
	_missile_cooldown = crawler_progress.missile_interval()
	var from := combat_position() + _up() * 0.85
	var toward := _combat_point_of(prey) - from
	if toward.length_squared() < 0.0001:
		toward = -global_basis.z
	_publish_hat_missiles(
		from,
		toward,
		crawler_progress.missile_count(),
		crawler_progress.missile_damage(),
		crawler_progress.missile_range()
	)


func _nearest_missile_mob() -> Node:
	if not is_inside_tree() or crawler_progress == null:
		return null
	var best: Node = null
	var best_span := crawler_progress.missile_range()
	var at := combat_position()
	for node_variant: Variant in get_tree().get_nodes_in_group(CrawlerMob.GROUP):
		var node := node_variant as Node
		if node == null or not _is_missile_prey(node):
			continue
		var span := _planar_span(at, _combat_point_of(node))
		if span >= best_span:
			continue
		best = node
		best_span = span
	return best


func _planar_span(from: Vector3, to: Vector3) -> float:
	if not from.is_finite() or not to.is_finite():
		return INF
	var up := from.normalized() if from.length_squared() > 1.0 else Vector3.UP
	var delta := to - from
	return (delta - up * delta.dot(up)).length()


func _is_missile_prey(node: Node) -> bool:
	if node == null or node == self:
		return false
	if node.has_method(&"is_alive") and not bool(node.call(&"is_alive")):
		return false
	if node.has_method(&"is_dead") and bool(node.call(&"is_dead")):
		return false
	if node.has_method(&"is_charmed") and bool(node.call(&"is_charmed")):
		return false
	return true


func _combat_point_of(node: Node) -> Vector3:
	if node.has_method(&"combat_position"):
		return node.call(&"combat_position")
	var body := node as Node3D
	return body.global_position if body != null else combat_position()


func _publish_hat_missiles(
		from: Vector3, toward: Vector3, count: int, damage: float,
		reach: float
	) -> void:
	if not from.is_finite() or not toward.is_finite() or count <= 0 \
			or damage <= 0.0 or reach <= 0.0:
		return
	if _has_listeners() and is_multiplayer_authority():
		_apply_hat_missiles.rpc(from, toward, count, damage, reach)
		return
	_spawn_hat_missiles(from, toward, count, damage, reach)


func _tick_mine_hat(delta: float) -> void:
	if not _is_host_authority() or not CrawlerRules.active():
		return
	if crawler_progress == null or not crawler_progress.wearing_mine_hat() \
			or _dead:
		_mine_cooldown = 0.0
		return
	_mine_cooldown = maxf(_mine_cooldown - delta, 0.0)
	if _mine_cooldown > 0.0:
		return
	_mine_cooldown = crawler_progress.mine_interval()
	var at := combat_position() - _up() * 0.85
	_publish_hat_mine(
		at, crawler_progress.mine_damage(), crawler_progress.mine_radius())


func _publish_hat_mine(at: Vector3, damage: float, reach: float) -> void:
	if not at.is_finite() or damage <= 0.0 or reach <= 0.0:
		return
	if _has_listeners():
		_apply_hat_mine.rpc(at, damage, reach)
		return
	_spawn_hat_mine(at, damage, reach)


func _tick_repeater_hat(delta: float) -> void:
	if _ability_controller == null or not CrawlerRules.active():
		return
	if crawler_progress == null or not crawler_progress.wearing_repeater_hat() \
			or _dead:
		_repeater_cooldown = 0.0
		return
	_repeater_cooldown = maxf(_repeater_cooldown - delta, 0.0)
	if _repeater_cooldown > 0.0:
		return
	if _fire_repeater_hat() <= 0:
		return
	_repeater_cooldown = crawler_progress.repeater_interval()


func _fire_repeater_hat() -> int:
	if _ability_controller == null or not can_attack():
		return 0
	var fired := 0
	for index in abilities.size():
		var ability := _ability_controller.ability_in(index)
		if ability == null or ability.is_held() or not ability.can_auto_use():
			continue
		ability.clear_cooldown()
		if activate_ability(index):
			fired += 1
			release_ability(index)
	return fired


func _spawn_hat_mine(at: Vector3, damage: float, reach: float) -> void:
	CrawlerHatMine.drop(get_parent(), self, at, {
		"damage": damage,
		"radius": reach,
		"fuse": CrawlerRules.MINE_HAT_FUSE,
		"size": CrawlerRules.MINE_HAT_SIZE,
	}, _is_host_authority())


func _phase_hat_blocks(hit: DamageHit) -> bool:
	if hit == null or not hit.projectile or not CrawlerRules.active():
		return false
	if crawler_progress == null or not crawler_progress.wearing_phase_hat():
		return false
	var amount := hit.amount if is_finite(hit.amount) else 0.0
	if amount <= 0.0:
		return false
	var chance := crawler_progress.phase_chance()
	if chance <= 0.0:
		return false
	return _crawler_dodge_roll() < chance


func _ordinance_hat_blocks(hit: DamageHit) -> bool:
	if hit == null or not hit.explosive or not CrawlerRules.active():
		return false
	return crawler_progress != null and crawler_progress.wearing_ordinance_hat()


func _rubber_hat_blocks(hit: DamageHit) -> bool:
	if hit == null or not CrawlerRules.active() or not shock_immune():
		return false
	return hit.ability_id == "lightning" or hit.ability_id == "static_field"


func shock_immune() -> bool:
	return crawler_progress != null and crawler_progress.wearing_rubber_hat()


func _tick_gold_cape_visual(delta: float) -> void:
	_sync_gold_cape_visual()
	if not gold_cape_active():
		_gold_cape_sparkle_acc = 0.0
		return
	_gold_cape_sparkle_acc += delta
	if _gold_cape_sparkle_acc < 0.12:
		return
	_gold_cape_sparkle_acc = 0.0
	if character == null:
		return
	CombatantFlash.flash(
		character,
		Color(1.0, 0.88, 0.28),
		0.28,
		0.58,
		"GoldCapeFlashOverlay"
	)
	var cloth := Wardrobe.worn_node(character, "cape")
	if cloth is CapeCloth:
		CombatantFlash.flash(
			cloth,
			Color(1.0, 0.92, 0.40),
			0.24,
			0.70,
			"GoldCapeFlashOverlay"
		)


func _sync_gold_cape_visual() -> void:
	var on := gold_cape_active()
	var cloth := Wardrobe.worn_node(character, "cape") if character != null else null
	if cloth is CapeCloth:
		(cloth as CapeCloth).set_sparkle(on)
	if on:
		if _gold_cape_light == null or not is_instance_valid(_gold_cape_light):
			_gold_cape_light = OmniLight3D.new()
			_gold_cape_light.name = "GoldCapeLight"
			_gold_cape_light.light_color = Color(1.0, 0.84, 0.28)
			_gold_cape_light.omni_range = 4.2
			_gold_cape_light.shadow_enabled = false
			add_child(_gold_cape_light)
		_gold_cape_light.light_energy = 2.4 + 1.1 * sin(Time.get_ticks_msec() * 0.018)
		_gold_cape_light.position = Vector3(0.0, 1.1, -0.2)
	elif _gold_cape_light != null and is_instance_valid(_gold_cape_light):
		_gold_cape_light.queue_free()
		_gold_cape_light = null


func wearing_fool_hat() -> bool:
	return crawler_progress != null and crawler_progress.wearing_fool_hat()


func _trigger_fool_hat() -> bool:
	if not _is_host_authority() or not CrawlerRules.active() or _dead:
		return false
	if not wearing_fool_hat() or _fool_cape_lock > 0.0:
		return false
	var dest := _fool_cape_destination()
	if not dest.is_finite():
		return false
	_fool_cape_lock = CrawlerRules.FOOL_HAT_LOCK
	var from := global_position
	play_ability_explosion(from, 0.55, Color(0.62, 0.18, 0.72), 0.22)
	play_ability_explosion(dest, 0.7, Color(0.86, 0.16, 0.22), 0.26)
	return warp_to(dest, -global_basis.z, true, false)


func _fool_cape_destination() -> Vector3:
	var from := global_position
	if not from.is_finite():
		return Vector3.INF
	for _try in CrawlerRules.FOOL_HAT_TRIES:
		var along := _fool_cape_dir_override
		if along.length_squared() < 0.0001:
			along = Vector3(
				_fool_cape_rng.randf_range(-1.0, 1.0),
				_fool_cape_rng.randf_range(-1.0, 1.0),
				_fool_cape_rng.randf_range(-1.0, 1.0)
			)
		if along.length_squared() < 0.0001:
			along = -global_basis.z
		along = along.normalized()
		var span := _fool_cape_distance_override
		if span < 0.0:
			span = CrawlerRules.fool_hat_distance(_fool_cape_rng)
		var at := _fool_cape_resolve(from + along * span)
		if _fool_cape_spot_clear(at):
			return at
	return Vector3.INF


func _fool_cape_resolve(at: Vector3) -> Vector3:
	if not at.is_finite():
		return Vector3.INF
	var world_planet := planet()
	if world_planet == null:
		return at
	var local := world_planet.to_local(at)
	if local.length_squared() < 0.0001:
		return at
	var surface := world_planet.surface_position(local)
	var up := world_planet.up_at(surface)
	var floor := maxf(_stance_height(_stance) * 0.5, 0.45)
	var altitude := (at - surface).dot(up)
	if altitude < floor:
		return surface + up * floor
	return at


func _fool_cape_spot_clear(at: Vector3) -> bool:
	if not at.is_finite() or not is_inside_tree():
		return false
	var space := get_world_3d().direct_space_state
	if space == null or collider == null or collider.shape == null:
		return true
	var query := PhysicsShapeQueryParameters3D.new()
	query.shape = collider.shape
	query.transform = Transform3D(global_transform.basis, at)
	query.exclude = DamageHit.rid_list(get_rid())
	query.collision_mask = collision_mask
	query.collide_with_areas = false
	return space.intersect_shape(query, 1).is_empty()


func _sync_rubber_from_hat() -> void:
	if shock_immune() and statuses.has(CombatStatuses.SHOCK):
		statuses.clear(CombatStatuses.SHOCK)


func _vampire_hat_heal(target: Node, amount: float) -> void:
	if crawler_progress == null or not crawler_progress.wearing_vampire_hat():
		return
	if target == null or target == self:
		return
	var share := crawler_progress.vampire_steal()
	if share <= 0.0:
		return
	apply_heal(amount * share)


func _juke_hat_strike() -> void:
	if not _is_host_authority() or not CrawlerRules.active():
		return
	if crawler_progress == null or not crawler_progress.wearing_juke_hat():
		return
	var damage := crawler_progress.juke_hat_damage()
	if damage <= 0.0 or not is_inside_tree():
		return
	var at := combat_position()
	var reach := CrawlerRules.JUKE_HAT_RADIUS + combat_radius()
	for node_variant: Variant in get_tree().get_nodes_in_group(DamageHit.COMBATANT_GROUP):
		var node := node_variant as Node
		if node == null or node == self or not is_instance_valid(node):
			continue
		if node.has_method(&"is_alive") and not bool(node.call(&"is_alive")):
			continue
		if node.has_method(&"is_dead") and bool(node.call(&"is_dead")):
			continue
		if node.has_method(&"is_charmed") and bool(node.call(&"is_charmed")):
			continue
		var id := node.get_instance_id()
		if _juke_struck.has(id):
			continue
		var them := _combat_point_of(node)
		var bounds := 0.4
		if node.has_method(&"combat_radius"):
			bounds = float(node.call(&"combat_radius"))
		if at.distance_to(them) > reach + bounds:
			continue
		_juke_struck[id] = true
		var hit := DamageHit.impact(them, maxf(bounds, 0.4), damage)
		hit.ability_id = "hat_juke"
		hit.affects_flora = false
		hit.faction = combat_faction()
		hit.set_source(self, peer_id)
		if not node.has_method(&"apply_damage"):
			continue
		var result: Variant = node.call(&"apply_damage", hit.resolved_for(node))
		var dealt := float(result) if result is float or result is int else 0.0
		if dealt > 0.0:
			combat_damage_dealt(node, dealt, hit)


func _spawn_hat_missiles(
		from: Vector3, toward: Vector3, count: int, damage: float,
		reach: float
	) -> void:
	CrawlerMissile.volley(get_parent(), self, from, toward, count, {
		"damage": damage,
		"range": reach,
		"speed": CrawlerRules.MISSILE_HAT_SPEED,
		"size": CrawlerRules.MISSILE_HAT_SIZE,
		"linger": CrawlerRules.MISSILE_HAT_LINGER,
	})


func _update_ward_bubble() -> void:
	if _ward_bubble == null:
		return
	_ward_bubble.set_state(ward_active())


func _follow_grab_socket() -> void:
	var socket := grab_socket()
	if socket == null:
		if _is_host_authority():
			release_grab()
		return
	global_transform = socket.global_transform * _grab_offset
	velocity = Vector3.ZERO
	reset_physics_interpolation()


## Explicit local feedback hooks are useful to hazards and focused tests without
## granting either one access to camera transforms.
func combat_feedback() -> CombatFeedback:
	return _combat_feedback


func combat_hud() -> Node:
	return _combat_hud


func damage_feedback(amount: float, at := Vector3.ZERO,
		source_peer := 0, source_name := "", ability_name := "") -> void:
	if _combat_feedback != null:
		_combat_feedback.damage_taken(
			amount, at, source_peer, source_name, ability_name)


func status_impact_feedback(strength := 0.55) -> void:
	if _combat_feedback != null:
		_combat_feedback.status_impact(strength)


func camera_shake(strength: float, duration: float) -> void:
	if _combat_feedback != null:
		_combat_feedback.shake(strength, duration)


func flora_contact_feedback(speed: float) -> void:
	if _combat_feedback != null:
		_combat_feedback.flora_contact(speed)


func combat_world_float(kind: int, amount: float, at: Vector3,
		merge_key := "") -> void:
	if not _is_host_authority() or amount <= 0.0:
		return
	_feedback_sequence += 1
	var event := DamageNumberEvent.new()
	event.kind = kind as DamageNumberEvent.Kind
	event.amount = amount
	event.world_position = at
	event.source_peer = peer_id
	event.merge_key = merge_key
	if _has_listeners():
		_apply_outgoing_feedback.rpc(_feedback_sequence, event.to_wire())
	else:
		_apply_outgoing_feedback(_feedback_sequence, event.to_wire())


func _emit_local_status_floats() -> void:
	if _combat_feedback == null:
		return
	if statuses.consume_pulse(CombatStatuses.CHARM, CombatStatuses.CHARM_PULSE):
		_show_local_status_float(DamageNumberEvent.Kind.CHARM, 1.0)
	if statuses.consume_shock_pulse():
		_show_local_status_float(DamageNumberEvent.Kind.SHOCK, 1.0)


func _show_local_status_float(kind: int, amount: float) -> void:
	var event := DamageNumberEvent.new()
	event.kind = kind as DamageNumberEvent.Kind
	event.amount = amount
	event.world_position = combat_position()
	event.incoming = true
	_combat_feedback.world_float(event)


func combat_damage_dealt(target: Node, amount: float, hit: DamageHit) -> void:
	if not _is_host_authority() or amount <= 0.0:
		return
	_vampire_hat_heal(target, amount)
	enemy_damaged.emit(target, amount, hit)
	_feedback_sequence += 1
	var target_peer_id := int(target.call(&"combat_peer_id")) \
		if target != null and target.has_method(&"combat_peer_id") else 0
	var event := DamageNumberEvent.new()
	event.amount = amount
	event.world_position = hit.centre()
	if target != null and target.has_method(&"combat_position"):
		var target_position: Variant = target.call(&"combat_position")
		if target_position is Vector3 and (target_position as Vector3).is_finite():
			event.world_position = target_position
	elif target is Node3D:
		event.world_position = (target as Node3D).global_position
	event.source_peer = peer_id
	event.target_peer = target_peer_id
	event.killed = _combatant_just_killed(target)
	if CrawlerRules.training_active():
		event.source_name = TrainingField.hit_who(target, hit)
	if _has_listeners():
		_apply_outgoing_feedback.rpc(_feedback_sequence, event.to_wire())
	else:
		_apply_outgoing_feedback(_feedback_sequence, event.to_wire())


func _combatant_just_killed(target: Node) -> bool:
	if target == null or not is_instance_valid(target):
		return false
	if target.has_method(&"is_alive"):
		return not bool(target.call(&"is_alive"))
	if target.has_method(&"is_dead"):
		return bool(target.call(&"is_dead"))
	return false


## Buildings are simulated on every peer, like flora, so the number is local
## presentation rather than a host-replicated combat event.
func building_damage_dealt(target: Node, amount: float, hit: DamageHit) -> void:
	if amount <= 0.0 or _combat_feedback == null:
		return
	var at := hit.centre() if hit != null else Vector3.ZERO
	if target != null and target.has_method(&"nearest_hit_point") and hit != null:
		var pointed: Variant = target.call(&"nearest_hit_point", hit.centre())
		if pointed is Vector3 and (pointed as Vector3).is_finite():
			at = pointed
	elif target != null and target.has_method(&"combat_position"):
		var pointed: Variant = target.call(&"combat_position")
		if pointed is Vector3 and (pointed as Vector3).is_finite():
			at = pointed
	var merge := str(target.get_instance_id()) if target != null else "building"
	_combat_feedback.outgoing_damage(amount, at, 0, false, true, merge)


## Returns whether a real ability was dispatched. Empty or invalid slots are a
## safe no-op until ability definitions are introduced.
func activate_ability(index: int) -> bool:
	if not can_attack() or index < 0 or index >= abilities.size():
		return false
	var ability_id := abilities.get_item(index)
	if not ItemDB.accepts_ability(ability_id):
		return false
	ability_activated.emit(index, ability_id)
	LagTracker.note_throttled("combat", "ability_%s" % ability_id, "ability %s" % ability_id, 0.35)
	return true


## The other edge of the same button. Emitted whether or not the slot holds
## anything, because an ability that was running when its slot was emptied still
## has to be told to stop.
func release_ability(index: int) -> void:
	if index < 0 or index >= abilities.size():
		return
	ability_released.emit(index)


func _attack() -> void:
	if not can_attack() or _held.is_empty():
		return
	if ItemDB.is_item(_held):
		item_activated.emit(_held)
		return
	if _weapon_pose == null:
		return
	match ItemDB.attack_of(_held):
		ItemDB.ATTACK_SWING:
			if not _weapon_pose.swinging():
				_swing_weapon.rpc()
		ItemDB.ATTACK_SHOOT:
			_shoot()


func _shoot() -> void:
	if not can_attack() or _charge() < 1:
		return
	_cells[_held] = float(_cells.get(_held, 0.0)) - 1.0
	_cell_pause = CELL_PAUSE
	_weapon_pose.kick()
	var from := _muzzle_point()
	_fire_bolt.rpc(from, _shot_direction(from))


## The tip of whatever is in hand. A weapon's own -Z is the way it points, so the
## muzzle is the far face of its bounding box along that axis.
func _muzzle_point() -> Vector3:
	if _held_mesh == null:
		return camera.global_position - camera.global_basis.z * 0.4
	var box := _held_mesh.get_aabb()
	var centre := box.get_center()
	return _held_mesh.global_transform * Vector3(centre.x, centre.y, box.position.z)


## Bolts leave the muzzle but go where the crosshair is, so a shot lands where the
## player aimed rather than parallel to it.
func _shot_direction(from: Vector3) -> Vector3:
	var target := camera.global_position - camera.global_basis.z * AIM_RANGE
	var along := target - from
	if along.length_squared() < 0.0001:
		return -camera.global_basis.z
	return along.normalized()


## Shots left in the held weapon, rounded down: a cell part way to its next shot
## cannot fire it yet.
func _charge() -> int:
	if ItemDB.cell_size(_held) <= 0:
		return 0
	return floori(float(_cells.get(_held, 0.0)))


func _aim_amount() -> float:
	return _weapon_pose.aim_amount() if _weapon_pose != null else 0.0


func _weapon_can_aim() -> bool:
	return _hotbar_drawn and ItemDB.attack_of(_held) == ItemDB.ATTACK_SHOOT


func _update_weapon(delta: float) -> void:
	if _weapon_pose == null:
		return
	# Only something that shoots can be sighted, and only while the body is under
	# the player's control.
	var can_aim := controls_enabled and can_attack() and _weapon_can_aim()
	_weapon_pose.set_aimed(can_aim and Input.is_action_pressed("aim"))

	var cell := ItemDB.cell_size(_held)
	if cell > 0:
		_cell_pause = maxf(_cell_pause - delta, 0.0)
		if _cell_pause <= 0.0:
			_cells[_held] = minf(float(_cells.get(_held, 0.0)) + delta / CELL_RECHARGE, float(cell))


# --- Movement ---------------------------------------------------------------

func _simulate_local_player(delta: float) -> void:
	# Before anything moves. Every branch below finishes in `_catch_ground`, and
	# what it needs to know is where the body set off from.
	_swept_from = global_position
	_update_beam_root(delta)
	if absf(_pending_yaw) > 0.000001:
		rotate_object_local(Vector3.UP, _pending_yaw)
		_pending_yaw = 0.0
	_align_to_planet(delta)
	_read_surface()
	_read_lava()
	# Before the stance branches. A punch lands in HERO but the pose is short and
	# the crater is not always here yet, so this must outlive the stance that
	# asked for it rather than hang off one.
	_settle_into_crater(delta)
	var grounded := _grounded()
	_swept_grounded = grounded
	if _dead and _stance != Stance.CRASH:
		_force_full_ragdoll_local(velocity, DAMAGE_RAGDOLL_TIME)
	if _stance == Stance.CRASH:
		_crash_move(delta)
		return
	if _stagger_left > 0.0:
		if not grounded:
			velocity -= _up() * (_gravity() * delta)
		move_and_slide()
		_catch_ground()
		return
	if _arrival_left > 0.0 or _reveal_left > 0.0:
		velocity = Vector3.ZERO
		if not grounded:
			velocity -= _up() * (_gravity() * delta)
		move_and_slide()
		_catch_ground()
		return
	if is_status_locked():
		velocity = Vector3.ZERO
		if not grounded:
			velocity -= _up() * (_gravity() * delta)
		move_and_slide()
		_catch_ground()
		return
	if _stance == Stance.HERO:
		_hero_land_move(delta)
		return
	if _stance == Stance.METEOR:
		_meteor_move(delta)
		return
	if _juke_left > 0.0:
		_juke_move(delta)
		return
	_update_flight_state(delta, grounded)
	_update_crawler_flight(delta, grounded)
	_update_crawler_city_heal(delta)
	_update_flight_water_state()
	if _stance == Stance.FLY:
		_fly_move(delta)
		_apply_beam_root_brake(delta)
		# No stair step: there is no floor under a flight, and the probe only ever
		# runs against one.
		var carried := velocity
		_flight_velocity = carried
		move_and_slide()
		# Before the ground guard, which teleports the body: the slide collisions
		# describe the move that just happened and reading them after moving it
		# out from under them is not safe.
		# A floor has its own angle-aware landing below. Flight still crashes
		# against rocks, walls, cliffs and ceilings.
		var flora := _resolve_flora_contacts(carried)
		var bounced := _apply_flora_response(carried, flora)
		var handled: Dictionary = flora["handled"]
		if not bounced:
			var struck := _hit_something_solid(carried, false, handled)
			_catch_ground()
			if struck:
				_begin_crash(carried)
			else:
				_knock_limb(carried, handled)
		return

	var fill := _submersion()
	_update_water_state(fill, grounded)
	if _stance == Stance.SWIM:
		if _on_lava:
			_lava_swim_move(delta)
		else:
			_swim_move(delta, fill)
		# No stair step and no run to break: there is nothing under a swimmer to
		# climb, and the height field still backs up the sea bed.
		var carried := velocity
		move_and_slide()
		var flora := _resolve_flora_contacts(carried)
		if not _apply_flora_response(carried, flora):
			_catch_ground()
		return

	var input := _steer_vector()
	# Already tangential: the body's own X and Z lie in the ground plane once the
	# body is aligned, so there is nothing to flatten out of it.
	var wish := global_basis * Vector3(input.x, 0.0, input.y)
	if wish.length_squared() > 0.0001:
		wish = wish.normalized()
	else:
		wish = Vector3.ZERO
	if _field_cast:
		wish = Vector3.ZERO
	elif _beam_root > 0.001:
		wish *= 1.0 - _beam_root
		if wish.length_squared() < 0.0001:
			wish = Vector3.ZERO

	_update_stance(delta, grounded)
	_update_run_speed(delta, wish != Vector3.ZERO)
	# Only while the feet are already down. A jump sets an upward velocity, which
	# `move_and_slide` will not snap against, but leaving the long reach on while
	# airborne would still have the body groping for ground it has left.
	floor_snap_length = maxf(_floor_snap, _horizontal_speed() * run_snap) if grounded \
		else _floor_snap
	# Contact, not [method _grounded]. The two differ by design: `_footed` calls
	# the body grounded whenever the field puts ground within `FOOT_REACH`, which
	# is what air control, the stair step and the snap reach above all want, and
	# is deliberately generous. Gravity is the one term that must not be that
	# generous. Suspending it on the field's say-so left a body that had stopped
	# short of the surface with nothing to close the gap: it hung wherever it
	# happened to stop, up to a boot's depth over ground the flowers were growing
	# out of, and because it never touched down `is_on_floor` never latched — so
	# `move_and_slide` never snapped either, and `run_snap` below, which exists to
	# hold a run against rolling ground, had never once run. Falling the last few
	# centimetres costs a frame and fixes both.
	if not is_on_floor():
		velocity -= _up() * (_gravity() * delta)
	_try_jump(delta, grounded)

	if _stance == Stance.SLIDE:
		_slide_move(delta, wish)
	else:
		_walk_move(delta, wish, grounded)
	_apply_beam_root_brake(delta)
	# Kept from before the move, because the collision spends it: this is the
	# speed that says whether the ground was landed on or hit.
	var carried := velocity
	_move_and_step(delta, grounded)
	# A run or an ordinary jump only crashes against a steep face. The impact
	# speed may be enormous on a flat landing when it was carried into the jump,
	# but the floor is where that motion is meant to end.
	var flora := _resolve_flora_contacts(carried)
	var bounced := _apply_flora_response(carried, flora)
	var handled: Dictionary = flora["handled"]
	if not bounced:
		if _hit_something_solid(carried, false, handled):
			_begin_crash(carried)
		else:
			_knock_limb(carried, handled)
	# After the collisions above have been read and before the guard below, for
	# the same reason the guard is last: both move the body, and a slide
	# collision describes where it was, not where it has been put since.
	if not bounced:
		_regain_footing()
		_catch_ground()


func _steer_vector() -> Vector2:
	if training_enemy:
		return _training_move
	return Input.get_vector("move_left", "move_right", "move_forward", "move_backward")


func _steer_held(action: StringName) -> bool:
	if training_enemy:
		match action:
			&"sprint":
				return _training_sprint
			&"jump":
				return _training_jump
			&"crouch":
				return _training_crouch
			_:
				return false
	return Input.is_action_pressed(action)


func _steer_just(action: StringName) -> bool:
	if training_enemy:
		match action:
			&"jump":
				return _training_jump_edge
			&"land":
				return _training_land_edge
			&"crouch":
				return _training_crouch_edge
			_:
				return false
	return Input.is_action_just_pressed(action)


func _consume_training_edges() -> void:
	_training_jump_edge = false
	_training_land_edge = false
	_training_crouch_edge = false


## Hands a dummy its WASD-equivalent for the next physics tick. `move` is the
## same vector [method Input.get_vector] would have produced: X is strafe, Y is
## forward (negative) / back (positive).
func set_training_move(move: Vector2, sprint := false) -> void:
	_training_move = move.limit_length(1.0)
	_training_sprint = sprint


func set_training_jump_held(held: bool) -> void:
	_training_jump = held


func pulse_training_jump() -> void:
	_training_jump = true
	_training_jump_edge = true


func pulse_training_land() -> void:
	_training_land_edge = true


## Turns the body and the head so abilities that read [method look_direction]
## and [method aim_direction] land on [param world_point].
func aim_training_at(world_point: Vector3) -> void:
	if not world_point.is_finite():
		return
	var up := _up()
	if up.length_squared() < 0.5:
		up = Vector3.UP
	var to := world_point - global_position
	var flat := to - up * to.dot(up)
	if flat.length_squared() > 0.0001:
		var desired := -flat.normalized()
		var current := -global_basis.z
		var current_flat := current - up * current.dot(up)
		if current_flat.length_squared() > 0.0001:
			rotate_object_local(
				Vector3.UP,
				current_flat.normalized().signed_angle_to(desired, up))
	var from := head.global_position if head != null \
		else global_position + up * _body_eye
	var look := world_point - from
	if look.length_squared() > 0.0001:
		look = look.normalized()
		_pitch = clampf(-asin(clampf(look.dot(up), -1.0, 1.0)), -1.48, 1.48)
		if head != null:
			head.rotation.x = _pitch


## Configures this body as a tilde-menu dummy. Must be called before the node
## enters the tree so [method _ready] builds an AbilityController and skips HUD.
func become_training_enemy(bot_id: int, slot_count := TRAINING_ABILITY_SLOTS) -> void:
	training_enemy = true
	peer_id = bot_id
	defer_camera = true
	controls_enabled = false
	display_name = "Enemy Player"
	abilities = ItemContainer.new(maxi(slot_count, 1))


## What is underfoot, as far as the walk cares: how arctic it is, and whether it
## is pack ice or snow over ground.
##
## Read at the top of the tick and not in [method _catch_ground], which is the
## other place this file talks to the height field, because the guard runs
## *after* the move and the accel and friction terms are wanted before it. It
## costs one dot product and a smoothstep — [method PlanetShape.frost] takes no
## noise samples — so a tick is no more expensive for asking.
##
## Ice is told from snow by the radius, which works because [method
## PlanetShape._freeze] put the floe at exactly [constant PlanetShape.ICE_TOP]
## and left everything higher alone. [member _ground_radius] is last tick's
## sample, which at a sprint is under a decimetre away and always the same
## surface — and the alternative, sampling here as well, is a second call for a
## number the guard is about to produce anyway.
func _read_surface() -> void:
	_frost = 0.0
	_on_ice = false
	var planet := _planet_below()
	if planet == null or planet.shape == null:
		return
	var local := planet.to_local(global_position)
	var span := local.length()
	if span < 1.0:
		return
	_frost = planet.shape.frost(local / span)
	_on_ice = _frost > 0.5 and _ground_radius > 0.0 \
		and _ground_radius - planet.shape.radius <= PlanetShape.ICE_TOP + 0.05


## Which way is out of the ground here. The world is a sphere, so this is not a
## constant and nothing below may say `Vector3.UP` or read `velocity.y`. Taken
## from the body rather than from the planet because `_align_to_planet` has
## already put the two in agreement, and the body's own frame is what `wish`, the
## stair probe and the camera are all expressed in.
func _up() -> Vector3:
	return global_basis.y


## The part of a vector that lies along the ground, and the part that leaves it.
func _flat(vector: Vector3) -> Vector3:
	var up := _up()
	return vector - up * vector.dot(up)


func _rise() -> float:
	return velocity.dot(_up())


## How hard the planet pulls, in m/s². It lives in `project.godot` rather than
## among the exports here because it belongs to the world and not to the body
## falling through it — a second planet would want its own, and that is the day to
## move it onto `Planet`. The fallback only ever applies to a scene opened without
## the project's settings, so it is written to match what is set there.
func _gravity() -> float:
	return float(ProjectSettings.get_setting("physics/3d/default_gravity", 24.0))


## Turns the body's up to point out of the planet's centre. This one call is what
## lets the rest of the file treat a sphere as a floor: `up_direction` is what
## `move_and_slide` calls a floor, and the body's basis is what every direction
## here is built from.
##
## Reapplied every frame rather than only on landing, because walking is what
## changes it: a run across 500 m of an 8 km planet turns the local up by three
## and a half degrees, and nothing else would ever put it right.
##
## `up_direction` is set whatever the altitude, because it costs nothing and the
## floor checks want it. The *body* is only turned by [method _alignment_blend],
## which is zero out in space — see there for why that matters.
func _align_to_planet(delta: float) -> void:
	var planet := _planet_below()
	var up := planet.up_at(global_position) if planet != null else Vector3.UP
	up_direction = up
	var blend := _alignment_blend(planet)
	if blend <= 0.0:
		return
	var axis := global_basis.y.cross(up)
	# Already square to the ground, or exactly upside down over the far side —
	# which has no shortest way round and is not reachable by flying there.
	if axis.length_squared() < 0.000000001:
		return
	# Eased rather than snapped, so descending into the air rolls the body upright
	# over a few seconds instead of flicking it. Written as an exponential
	# approach so the turn takes the same time whatever the frame rate.
	var angle := global_basis.y.angle_to(up)
	var taken := angle * (1.0 - exp(-blend * ALIGN_RATE * delta))
	global_basis = (Basis(axis.normalized(), taken) * global_basis).orthonormalized()


## How hard the body is pulled square to the ground: 0 out in space, 1 once there
## is ground to speak of underneath.
##
## The gate exists because at the orbital spawn the planet is dead ahead and the
## way out of its centre is straight behind, so there is no heading left to keep
## once up is forced radial — the view whips sideways and the spawn is ruined.
## Out there nothing needs a floor anyway. Flying down through the air is what
## earns the orientation, and by the ground it is complete.
func _alignment_blend(planet: Planet) -> float:
	if planet == null:
		return 0.0
	# Anything not flying is on its way to the floor and needs the floor to be a
	# floor: gravity, the stair probe and `is_on_floor` all measure off this.
	if _stance != Stance.FLY:
		return 1.0
	var ceiling := planet.atmosphere_height
	if ceiling <= 0.0:
		return 1.0
	var altitude := global_position.distance_to(planet.global_position) - planet.shape.radius
	var depth := 1.0 - clampf(altitude / ceiling, 0.0, 1.0)
	# Slowing down is the other half of it: at a float there is nothing to do but
	# settle, while hauling the body upright in the middle of a 200 m/s dive
	# fights the steering. Never to zero, or a fast descent would arrive sideways.
	return depth * (1.0 - 0.6 * clampf(_cruise / maxf(fly_speed, 1.0), 0.0, 1.0))


## The planet's collider is not the planet. A chunk only gets a
## [ConcavePolygonShape3D] once it is near enough, deep enough *and* finished
## building on the thread pool, so there is always a window in which the ground
## is drawn but not solid — and a flight arriving at 200 m/s can be inside that
## window when it reaches a hillside. The height field answers the same question
## in constant time and without a mesh, which is why it, and not the collider, is
## what finally stops anything going through the world.
##
## It also answers the smaller question the collider is bad at: is there ground
## under the feet at all. Where there is no chunk body, [method is_on_floor] can
## only ever say no, and a body that believes it is falling gets air control, no
## floor snapping and no stair step — which is the whole of walking. So this sets
## [member _footed] as well as pushing out, and the two together are what the
## rest of the file means by grounded.
func _catch_ground() -> bool:
	_footed = is_on_floor()
	_ground_radius = -1.0
	if _catch_lava_surface():
		return true
	var planet := _planet_below()
	if planet == null or planet.shape == null:
		return false
	# The ground that is drawn, not the ground the field could describe. A chunk
	# that has not refined yet has no canyon in it, and a body must be held up by
	# the surface it can see rather than by the one under it.
	var spacing := planet.spacing_underfoot()
	# First for an airborne path, because at speed the place the move finished is
	# not necessarily the place it met the ground. Never sweep a grounded stride:
	# its start lies on (and often a few millimetres inside) the sampled field by
	# definition. Once a stride exceeded one 1.5 m field spacing — around 90 m/s
	# at 60 Hz — `_rewind_to_entry` saw that start as an entry and restored it
	# every frame while leaving velocity intact: the exact run-in-place failure.
	var crossed := _rewind_to_entry(planet, spacing) \
		if not _swept_grounded or _stance == Stance.FLY else false
	var local := planet.to_local(global_position)
	if local.length_squared() < 1.0:
		return false
	var out := local.normalized()
	var floor_radius := planet.shape.radius + planet.shape.elevation(out, spacing)
	# Intact pavement is the floor the body can see. Using the planet field
	# here would treat a raised deck as air, then later push a clipped stride
	# *into* the hillside the slab was overlapping.
	var pad_radius := PatchCity.deck_radius(out, get_tree())
	if not is_nan(pad_radius):
		floor_radius = maxf(floor_radius, pad_radius)
	_ground_radius = floor_radius
	var under := floor_radius - local.length()
	# A crossing has already been narrowed down to the surface it crossed, so
	# every test below would measure it as a graze and wave it through. It is
	# not a graze: the body was on the far side of that ground a moment ago.
	if not crossed:
		if under < -FOOT_REACH:
			return false
		# Within a boot's depth of the surface and not on the way up: the ground
		# is there whether or not the last move happened to touch it. Not for a
		# flight or a swim, both of which pass close to ground they are not
		# standing on and have their own tests for arriving.
		if _stance != Stance.FLY and _stance != Stance.SWIM:
			_footed = _footed or _rise() <= 0.1
		if under <= 0.0:
			return false
		# The mesh gets the benefit of the doubt while it is shallow enough to be
		# a triangle that dips rather than a body inside the world.
		if under < TUNNEL_DEPTH and _footing_within(GROUND_MARGIN):
			return false
	global_position = planet.to_global(out * floor_radius)
	# Whatever was driving the body into the ground is spent; what it had along
	# the surface is not, so a graze keeps its heading.
	velocity = _flat(velocity)
	_footed = true
	if _stance == Stance.FLY:
		_end_flight()
	return true


## Puts the body back where its path first went under the height field, and says
## whether it found such a place.
##
## The guard above is a point test, and a point test only stands in for a swept
## one while the point moves less than the smallest thing it must not miss. A
## boost covers seventeen metres in a tick. A ridge that thick is crossed
## *between* two samples: the body is above the ground where the tick started,
## above the ground on the far side where it ended, and nothing in the frame
## ever saw the mountain in between. That is the whole of what flying through
## the planet is, and pushing harder on the guard cannot fix it — there is
## nothing wrong with the answer it gives, only with where it was asked.
##
## `move_and_slide` does not have the problem, because it sweeps its capsule.
## But at that speed almost none of the ground ahead has a collider yet, so
## there is nothing for the sweep to find and the field is all there is.
##
## The chord therefore gets walked in pieces the width of the field's own finest
## feature, and the first piece that ends underground is halved a few times for
## the crossing. It is arithmetic and no physics query: a handful of noise
## lookups at a boost, and one length and a comparison at every other speed,
## which is every tick the player spends walking.
func _rewind_to_entry(planet: Planet, spacing: float) -> bool:
	var travelled := global_position - _swept_from
	var reach := travelled.length()
	if reach <= spacing:
		return false
	var parts := mini(ceili(reach / spacing), SWEEP_PARTS)
	# The start counts. A body that was already inside — because a chunk
	# coarsened under it, or because the last tick left it there — has its whole
	# path underground, and the loop below would otherwise find no crossing on it
	# and hand back the far end.
	if _clearance(planet, _swept_from, spacing) <= 0.0:
		global_position = _swept_from
		return true
	var clear := 0.0
	for part in range(1, parts + 1):
		var at := float(part) / float(parts)
		if _clearance(planet, _swept_from + travelled * at, spacing) > 0.0:
			clear = at
			continue
		var inside := at
		for _refine in SWEEP_REFINE:
			var middle := (clear + inside) * 0.5
			if _clearance(planet, _swept_from + travelled * middle, spacing) > 0.0:
				clear = middle
			else:
				inside = middle
		global_position = _swept_from + travelled * clear
		return true
	return false


## How far a point is above the height field, in metres, negative inside it.
func _clearance(planet: Planet, at: Vector3, spacing: float) -> float:
	var local := planet.to_local(at)
	var span := local.length()
	if span < 1.0:
		return -span
	return span - (planet.shape.radius + planet.shape.elevation(local / span, spacing))


## Ground under the feet, from either of the two things that can provide it. Every
## floor question in the movement code goes through here rather than through
## [method is_on_floor], which knows only about chunk colliders.
func _grounded() -> bool:
	return is_on_floor() or _footed


## Cached: the search is by type rather than by name, so it costs a walk of the
## world's children and the planet never moves between them.
func _planet_below() -> Planet:
	if is_instance_valid(_planet):
		return _planet
	var parent := get_parent()
	if parent == null:
		return null
	for sibling in parent.get_children():
		if sibling is Planet:
			_planet = sibling as Planet
			return _planet
	return null


func _find_land_patches() -> LandPatchOverlay:
	if is_instance_valid(_land_patches):
		return _land_patches
	var planet := _planet_below()
	if planet != null:
		var named := planet.get_node_or_null("LandPatches") as LandPatchOverlay
		if named != null:
			_land_patches = named
			return named
	var grouped := get_tree().get_first_node_in_group(LandPatchOverlay.GROUP) \
			as LandPatchOverlay
	if grouped != null:
		_land_patches = grouped
	return grouped


func _aimed_patch_id() -> int:
	if not _waypoints_wanted:
		return -1
	var overlay := _find_land_patches()
	if overlay == null or not overlay.visible:
		return -1
	var planet := _planet_below()
	if planet == null or planet.shape == null:
		return -1
	aim_ray.force_raycast_update()
	if not aim_ray.is_colliding():
		return -1
	var local := planet.to_local(aim_ray.get_collision_point())
	if local.length_squared() < 1.0:
		return -1
	return overlay.partition.owner_at(local.normalized())


func _try_found_city_live() -> bool:
	if CrawlerRules.active():
		return false
	if not _waypoints_wanted:
		return false
	var overlay := _find_land_patches()
	if overlay == null:
		return false
	var patch_id := _aimed_patch_id()
	if patch_id < 0:
		return false
	return overlay.render_live_city(patch_id)


func _try_found_yard_city() -> bool:
	if CrawlerRules.active() or not _waypoints_wanted:
		return false
	var overlay := _find_land_patches()
	if overlay == null:
		return false
	var patch_id := _aimed_patch_id()
	if patch_id < 0:
		return false
	return overlay.render_yard_city(patch_id)


func _try_place_baked_city() -> bool:
	if CrawlerRules.active() or not _waypoints_wanted:
		return false
	var overlay := _find_land_patches()
	if overlay == null:
		return false
	var patch_id := _aimed_patch_id()
	if patch_id < 0:
		return false
	return overlay.place_baked_city(patch_id)


func _try_place_all_baked_cities() -> bool:
	if CrawlerRules.active() or not _waypoints_wanted:
		return false
	var overlay := _find_land_patches()
	if overlay == null:
		return false
	return overlay.place_all_baked_cities() > 0


func _try_place_enemy_creator() -> bool:
	if CrawlerRules.active() or not _waypoints_wanted or _dead or _grabbed or _lassoed:
		return false
	var world := get_parent() as GameWorld
	if world == null:
		return false
	var creator_script := load("res://game/enemies/enemy_creator.gd") as GDScript
	if creator_script == null:
		return false
	var creator := creator_script.new() as Node3D
	world.add_child(creator)
	if creator.has_method(&"place_ahead_of"):
		creator.call(&"place_ahead_of", self)
	return true


## move_and_slide plus a stair step. Without it a capsule stops dead against any
## lip it cannot slide over, which is most prop edges and kerbs.
func _move_and_step(delta: float, grounded: bool) -> void:
	var intended := _flat(velocity) * delta
	var before := global_position
	move_and_slide()
	if not is_on_wall() or intended.length() < 0.001:
		return
	var achieved := _flat(global_position - before)
	# Slopes and glancing walls legitimately eat some motion; only a real
	# obstruction, which eats most of it, is worth lifting the body for.
	if achieved.dot(intended) >= intended.length_squared() * 0.8:
		return
	if (grounded or _footing_within(step_height)) and _climb_step(intended):
		return
	# Only something close to vertical ends a run. `is_on_wall` means no more
	# than "steeper than `floor_max_angle`", which on a procedural planet is
	# most hillsides, and a run that died on every slope would never get out of
	# the valley it started in.
	if _steepest_contact() >= RUN_BREAK_FACE:
		_break_run()


## Is there anything to stand on within `reach` under the body? `is_on_floor` asks
## the same question of the move that just happened, and on the planet it says no
## far more often than the ground under the feet warrants: the terrain is a
## triangulation that dips between its vertices, the height-field guard works to a
## margin of half a metre, and a run at speed spends most of its frames a
## centimetre or two clear of the mesh. A body that is airborne on a technicality
## will not climb a kerb, and every small bump becomes a wall.
func _footing_within(reach: float) -> bool:
	return test_move(global_transform, -_up() * reach)


## How far the steepest thing just hit leans off the ground: 1 is a vertical face,
## 0 is ground you could stand on.
func _steepest_contact() -> float:
	var up := _up()
	var worst := 0.0
	for index in get_slide_collision_count():
		worst = maxf(worst, 1.0 - absf(get_slide_collision(index).get_normal().dot(up)))
	return worst


func _climb_step(intended: Vector3) -> bool:
	var direction := intended.normalized()
	# The probe starts a few millimetres back off the obstruction and reaches a
	# little past it: the slide leaves the capsule flush against the wall, and a
	# shape that starts in contact reports a collision even for motion running
	# parallel to the surface it is touching.
	var clearance := 0.03
	var start := global_transform.translated(-direction * clearance)
	# Far enough past the lip that the body comes down on the step's top face
	# rather than balancing on its edge.
	var forward := direction * (maxf(intended.length(), 0.12) + clearance)
	# Raised higher than the tallest allowed step, so a step right at the limit
	# still has room to pass over it. How far the body may actually rise is
	# judged from the landing below, not from this probe.
	var lift := up_direction * (step_height + 0.05)
	if test_move(start, lift):
		return false
	var lifted := start.translated(lift)
	if test_move(lifted, forward):
		return false

	var over := lifted.translated(forward)
	var landing := KinematicCollision3D.new()
	# No ground under the raised body means this is a gap or a cliff, not a step.
	if not test_move(over, -lift * 1.2, landing):
		return false
	# Anything that is not a wall will do: coming down on the edge of a step
	# reports a slanted normal, and the rise is bounded either way.
	if landing.get_normal().dot(up_direction) < 0.3:
		return false
	var target := over.origin + landing.get_travel()
	var rise := (target - global_position).dot(_up())
	if rise > step_height + 0.01 or rise < -0.01:
		return false

	_step_offset -= rise
	global_position = target
	return true


## Puts the feet back on ground they have just skimmed off.
##
## `move_and_slide` does its own snapping, and it is deliberately one-way: it
## will only reach for a floor the body was standing on at the start of the move.
## Lose contact for a single frame — which a run does constantly, over a crest,
## on a triangle edge, or on the tick a chunk swaps detail — and the snap is
## latched off until the body physically falls back down. Traced at a sprint,
## every touch was followed by six frames of free fall and another touch, which
## is the bounce, and no amount of [member run_snap] could reach it because the
## reach was never consulted.
##
## Only ever downward, and only for ground the guard has just measured within
## [constant FOOT_REACH]: past that the body is not skimming, it has run off
## something, and the fall is the honest answer. A rise is left alone as well,
## which is the whole of what keeps this off a jump and off a ramp: both leave
## the ground travelling outward, and by the time gravity has turned either of
## them back down the body is long past the reach tested here.
##
## Called at the end of the tick rather than straight after `move_and_slide`,
## because snapping both moves the body and rewrites the contact state, and two
## things in between still need those as the move left them: the stair step
## reads `is_on_wall`, and the crash test reads the slide collisions.
func _regain_footing() -> void:
	if is_on_floor() or not _footed or _rise() > 0.0:
		return
	apply_floor_snap()


func _try_jump(delta: float, grounded: bool) -> void:
	_coyote_left = coyote_time if grounded else maxf(_coyote_left - delta, 0.0)
	_jump_buffered = jump_buffer if _steer_just(&"jump") else maxf(_jump_buffered - delta, 0.0)
	if _jump_buffered <= 0.0 or _coyote_left <= 0.0 or _beam_root > 0.4:
		return
	_jump_buffered = 0.0
	_coyote_left = 0.0
	velocity = _flat(velocity) + _up() * (jump_velocity * (1.0 + jump_speed_gain * _run_amount()))
	# Jumping out of a slide keeps the boosted speed, which is the payoff for
	# chaining a slide into a hop, and the slide's speed is what sizes the jump.
	if _stance != Stance.STAND:
		_try_stand()


## Shift winds the run up and letting go of shift leaves it where it got to. Only
## releasing forward gives the speed back, which is what makes a run something
## held rather than something spent — there is no stamina here to spend.
func _update_run_speed(delta: float, steering: bool) -> void:
	# A slide is not a run, and the slide's own friction owns the speed while it
	# lasts; `_update_stance` hands the run back whatever the slide leaves.
	if _stance == Stance.SLIDE:
		return
	if not steering:
		_run_speed = walk_speed
		return
	if _steer_held(&"sprint"):
		_run_speed = maxf(_run_speed, sprint_speed)
		_run_speed = move_toward(_run_speed, run_top_speed,
			(run_top_speed - sprint_speed) / maxf(run_spool_time, 0.01) * delta)
	# The target can never run far ahead of the legs. Without this, anything that
	# bleeds the real speed — a crouch, a slide, a hill — would leave the wind-up
	# intact and hand it all back for free the moment the body stood up again.
	_run_speed = clampf(_run_speed, walk_speed,
		maxf(sprint_speed, _horizontal_speed() * 1.25 + walk_speed))


## How far into a run the player is: 0 at a sprint, 1 flat out. The lean, the
## field of view and the height of a jump all read it, so they agree.
func _run_amount() -> float:
	return clampf(
		inverse_lerp(sprint_speed, run_top_speed * GROUND_FLAT_OUT, _horizontal_speed()), 0.0, 1.0)


## A run ends against anything it cannot climb or slide past. Momentum built over
## several seconds is not something to carry on through a pillar, and nothing else
## in the movement code notices the collision: `move_and_slide` would happily
## redirect the whole 200 m/s along the wall.
func _break_run() -> void:
	if _run_speed <= sprint_speed:
		return
	_run_speed = walk_speed
	velocity = _flat(velocity).limit_length(walk_speed) + _up() * _rise()
	if _stance == Stance.SLIDE:
		_slide_ready_in = slide_cooldown
		_try_stand()


func _walk_move(delta: float, wish: Vector3, grounded: bool) -> void:
	var flat := _flat(velocity)
	var target_speed := _target_speed()
	if wish == Vector3.ZERO:
		if grounded:
			flat = flat.move_toward(Vector3.ZERO, _coast_drag(flat.length()) * delta)
	elif grounded:
		flat = flat.move_toward(wish * target_speed, _ground_accel() * delta)
	elif flat.length() > target_speed:
		# Airborne and already faster than we could run: steer without braking.
		flat = flat.move_toward(wish * flat.length(), air_accel * delta)
	else:
		flat = flat.move_toward(wish * target_speed, air_accel * delta)
	velocity = flat + _up() * _rise()


## Friction once forward is released. `ground_friction` alone would take four
## seconds to shed a run, so it grows with whatever the run is carrying above a
## sprint; below a sprint the extra term is zero and a walk stops as it always did.
##
## The surface scales the whole thing, the speed term included. Letting the run
## skid keep its full bite on ice would give the odd result that a sprint stops
## dead on a floe while a walk slithers about on it.
func _coast_drag(speed: float) -> float:
	return (ground_friction + maxf(speed - sprint_speed, 0.0) * coast_drag) * _grip()


## Acceleration underfoot. Ice gives a little more and snow a lot less; see the
## Arctic exports for why the two are not symmetrical.
func _ground_accel() -> float:
	if _on_ice:
		return ground_accel * ice_accel
	return ground_accel * lerpf(1.0, snow_accel, _frost)


## How much of the ordinary friction this surface is willing to apply.
func _grip() -> float:
	if _on_ice:
		return ice_friction
	return lerpf(1.0, snow_friction, _frost)


func _slide_move(delta: float, wish: Vector3) -> void:
	var flat := _flat(velocity)
	var speed := maxf(flat.length() - _slide_drag * delta, 0.0)
	var direction := flat.normalized() if flat.length_squared() > 0.0001 else -global_basis.z
	if wish != Vector3.ZERO:
		direction = (direction + wish * slide_steer * delta).normalized()
	velocity = direction * speed + _up() * _rise()


## Top speed the walk is steering toward. Deep snow holds it down; ice does not
## raise it, because what ice does is let the body keep speed rather than help it
## reach any — and a target above the run would have a player on a floe outrunning
## one on grass, which is not what slipping feels like.
func _target_speed() -> float:
	var top := crouch_speed if _stance == Stance.CROUCH else _run_speed
	var pace := statuses.move_scale() if statuses != null else 1.0
	if _on_ice:
		return top * pace
	return top * lerpf(1.0, snow_speed, _frost) * pace


func _horizontal_speed() -> float:
	return _flat(velocity).length()


# --- Flight -----------------------------------------------------------------

## Puts the player in the air without a take-off, for spawning somewhere that has
## no ground under it. Take-off proper wants clearance below and a jump press,
## and both are answers to questions that do not arise in orbit.
func start_flying() -> void:
	if _stance == Stance.FLY or not can_fly():
		return
	var starts_underwater := _submersion() >= FLIGHT_SWIM_ENTER
	velocity = Vector3.ZERO
	_cruise = float_speed
	_jump_buffered = 0.0
	_flight_velocity = Vector3.ZERO
	_flight_jump_latched = false
	_underwater_launch = starts_underwater
	floor_snap_length = 0.0
	_apply_stance(Stance.FLY)


## Space in mid-air takes off, and space twice does it out of the water. A flight
## ends at the floor, drifting down near it while floating, entering the sea from
## the air, or the land key — the only way out of a hover over an empty hole.
func _update_crawler_flight(delta: float, grounded: bool) -> void:
	if not CrawlerRules.active():
		return
	if CrawlerRules.sandbox_fast():
		_flight_fuel = 1.0
		return
	if _stance == Stance.FLY:
		var rate := 1.0 / maxf(crawler_flight_seconds(), 0.1)
		if _steer_held(&"sprint") and _steer_vector().length_squared() > 0.0001:
			rate *= CrawlerRules.FLIGHT_BOOST_DRAIN
		_flight_fuel = maxf(_flight_fuel - rate * delta, 0.0)
		if _flight_fuel <= 0.0:
			_end_flight(true)
	elif grounded:
		_flight_fuel = minf(_flight_fuel + CrawlerRules.FLIGHT_REGEN * delta, 1.0)


func _update_crawler_city_heal(delta: float) -> void:
	if not CrawlerRules.active() or not _is_host_authority() or _dead:
		return
	if not in_crawler_city():
		return
	apply_heal(CrawlerRules.CITY_HEAL_PER_SECOND * delta)


func _update_flight_state(delta: float, grounded: bool) -> void:
	_swim_launch_left = maxf(_swim_launch_left - delta, 0.0)
	if _stance == Stance.FLY:
		if not can_fly():
			_end_flight(CrawlerRules.active() and _flight_fuel <= 0.02)
			return
		if grounded or (_steer_just(&"land") and _beam_root < 0.25):
			_end_flight()
		elif _beam_root < 0.25 and velocity.length() <= float_speed * 1.6 \
				and test_move(global_transform, -_up() * land_clearance):
			_end_flight()
		return
	if not can_fly() or _beam_root > 0.4:
		return
	var launched_from_swim := _stance == Stance.SWIM
	if launched_from_swim:
		# Out of the water takes two presses; see SWIM_LAUNCH_WINDOW. The coyote
		# window is skipped rather than checked, because a swim is entered from a
		# fall as often as from a wade and the window is still open on the way in.
		if not _swim_launch_pressed():
			return
	# The coyote window belongs to the jump, so walking off a ledge and pressing
	# space is still a jump and not a take-off.
	elif grounded or _coyote_left > 0.0 or not _steer_just(&"jump"):
		return
	# Only on the land path. The clearance is there to keep a take-off apart from
	# a buffered jump, and a swimmer has no jump to buffer; asking for it in the
	# water as well would refuse a launch out of anything shallower than a metre.
	elif test_move(global_transform, -_up() * TAKEOFF_CLEARANCE):
		return
	# A take-off below the start of the Float-to-Fly speed band becomes a hover
	# as before. Above it, the body is already travelling too fast to hover:
	# keep the jump's velocity and direction, seed cruise from that speed, and
	# start fully in Fly instead of passing through the upright Float pose.
	var inherited_flight := velocity.length() >= float_speed * 1.4
	if inherited_flight:
		_cruise = clampf(velocity.length(), float_speed, fly_speed)
		_fly_blend = 1.0
		# Enough sky to keep a ground-parallel jump from immediately steering
		# back into the terrain, but small enough not to take the view away.
		_pitch = maxf(_pitch, FAST_TAKEOFF_LOOK)
		head.rotation.x = _pitch
	else:
		velocity = velocity.limit_length(float_speed)
		_cruise = float_speed
	_flight_jump_latched = true
	_jump_buffered = 0.0
	_swim_launch_left = 0.0
	_underwater_launch = launched_from_swim and _submersion() > 0.0
	floor_snap_length = 0.0
	_apply_stance(Stance.FLY)


## Second press of jump inside [constant SWIM_LAUNCH_WINDOW]. The first press
## arms the window and is otherwise left alone, so it still does what it always
## did in [method _swim_move]: pull the body toward the surface.
func _swim_launch_pressed() -> bool:
	if not _steer_just(&"jump"):
		return false
	if _swim_launch_left > 0.0:
		return true
	_swim_launch_left = SWIM_LAUNCH_WINDOW
	return false


# --- Crashing ---------------------------------------------------------------

## Breaks any explicitly tagged flora contacts before the ordinary static-body
## crash policy reads the same slide list. The velocity supplied here is the
## pre-slide value, preserving the impact speed move_and_slide has already
## consumed.
func _resolve_flora_contacts(carried: Vector3) -> Dictionary:
	var handled: Dictionary = {}
	var broke := false
	var momentum_keep := 1.0
	var bounce_up := 0.0
	for index in get_slide_collision_count():
		var hit := get_slide_collision(index)
		if not (hit.get_collider() is StaticBody3D):
			continue
		var collider := _impact_shape(hit)
		if collider == null or handled.has(collider.get_instance_id()):
			continue
		if not collider.has_meta(IMPACT_BREAK_OWNER_META):
			continue
		var owner := collider.get_meta(IMPACT_BREAK_OWNER_META) as Node
		if owner == null or not is_instance_valid(owner) \
				or not owner.has_method(&"resolve_flora_impact"):
			continue
		var impact_speed := -hit.get_normal().dot(carried)
		if impact_speed <= 0.0:
			continue
		var value: Variant = owner.call(
			&"resolve_flora_impact", collider, impact_speed, hit.get_position())
		if not value is Dictionary:
			continue
		var result: Dictionary = value
		if not bool(result.get("handled", false)):
			continue
		handled[collider.get_instance_id()] = true
		broke = broke or bool(result.get("broken", false))
		momentum_keep = minf(momentum_keep,
			float(result.get("momentum_keep", 1.0)))
		bounce_up = maxf(bounce_up, float(result.get("bounce_up", 0.0)))
	if not handled.is_empty():
		flora_contact_feedback(carried.length())
	return {
		"handled": handled,
		"broken": broke,
		"momentum_keep": momentum_keep,
		"bounce_up": bounce_up,
	}


## Applies the soft pass-through or the one-use mushroom launch. A bounce
## returns true so the caller does not immediately flatten the new radial
## velocity through the ground guard or convert it into a hero landing.
func _apply_flora_response(carried: Vector3, response: Dictionary) -> bool:
	var bounce_up := float(response.get("bounce_up", 0.0))
	if bounce_up > 0.0:
		var forward := _flat(carried)
		velocity = forward + _up() * bounce_up
		_footed = false
		_ground_radius = -1.0
		_coyote_left = 0.0
		_jump_buffered = 0.0
		floor_snap_length = 0.0
		_flight_velocity = Vector3.ZERO
		_underwater_launch = false
		_cruise = float_speed
		_run_speed = clampf(forward.length(), walk_speed, run_top_speed)
		_apply_stance(Stance.STAND)
		return true
	if bool(response.get("broken", false)):
		var keep := clampf(float(response.get("momentum_keep", 1.0)), 0.0, 1.0)
		velocity = carried * keep
		if _stance == Stance.FLY:
			_flight_velocity = velocity
		elif _stance != Stance.SWIM:
			_run_speed = maxf(_run_speed,
				minf(_flat(velocity).length(), run_top_speed))
	return false


## CollisionShape3D is returned directly by ordinary node-authored bodies.
## Shape-owner lookup is a fallback for physics backends that expose only the
## body-local shape index through KinematicCollision3D.
func _impact_shape(hit: KinematicCollision3D) -> CollisionShape3D:
	var direct := hit.get_collider_shape()
	if direct is CollisionShape3D:
		return direct as CollisionShape3D
	var body := hit.get_collider() as CollisionObject3D
	if body == null:
		return null
	var owner_id := body.shape_find_owner(hit.get_collider_shape_index())
	if owner_id < 0:
		return null
	return body.shape_owner_get_owner(owner_id) as CollisionShape3D


func _impact_was_handled(hit: KinematicCollision3D,
		handled: Dictionary) -> bool:
	if handled.is_empty():
		return false
	var collider := _impact_shape(hit)
	return collider != null and handled.has(collider.get_instance_id())


## Did that move put the body into something that does not move, hard?
##
## Measured against the velocity the frame *started* with, because the slide has
## already redirected whatever survived along the surface and the number that
## says how hard it hit is gone by the time anything can ask.
##
## Flight crashes on any hard impact, including a flat landing. Running,
## jumping and falling pass `floors_crash = false`: a face the character
## controller classifies as floor is then a safe landing regardless of speed,
## while a rock, cliff, wall or ceiling still causes a crash.
func _hit_something_solid(carried: Vector3, floors_crash: bool,
		handled: Dictionary = {}) -> bool:
	for index in get_slide_collision_count():
		var hit := get_slide_collision(index)
		# Only things that cannot be pushed. Flying into another player is their
		# problem as much as yours and should floor neither of you.
		if not (hit.get_collider() is StaticBody3D):
			continue
		if _impact_was_handled(hit, handled):
			continue
		var normal := hit.get_normal()
		if _impact_crashes(normal, carried, floors_crash):
			return true
	return false


## The crash policy without the collision plumbing, kept separate so all three
## movement cases can be tested directly rather than depending on a particular
## piece of test terrain producing the desired contact normal.
func _impact_crashes(normal: Vector3, carried: Vector3, floors_crash: bool) -> bool:
	if not floors_crash and normal.dot(_up()) > FLOOR_FACE:
		return false
	return -normal.dot(carried) >= CRASH_SPEED


## The tier below a crash: a hit hard enough to be felt but not to put the player
## down, which knocks the part of the body that met the wall and leaves the rest
## walking. Catching a shoulder on a rock at a sprint should cost a flinch, and
## before this it cost either nothing at all or the whole second and a half of
## lying on the floor.
##
## Floors are skipped. Every landing arrives at some speed into a surface, and a
## jump is not an accident — the `Land` clip already has that job.
func _knock_limb(carried: Vector3, handled: Dictionary = {}) -> void:
	if _ragdoll == null or not _ragdoll.built() or _ragdoll.limp():
		return
	var hardest := 0.0
	var at := Vector3.ZERO
	var away := Vector3.ZERO
	for index in get_slide_collision_count():
		var hit := get_slide_collision(index)
		if not (hit.get_collider() is StaticBody3D):
			continue
		if _impact_was_handled(hit, handled):
			continue
		var normal := hit.get_normal()
		if normal.dot(_up()) > FLOOR_FACE:
			continue
		var speed := -normal.dot(carried)
		if speed > hardest:
			hardest = speed
			at = hit.get_position()
			away = normal
	if hardest < KNOCK_SPEED:
		return
	var planet := _planet_below()
	if planet != null and _ground_radius > 0.0:
		_ragdoll.set_floor(planet.global_position, _ground_radius)
	# Out of the surface, not along the travel: what the body does is rebound off
	# the thing it hit. Capped because a flight clipping a spire at 300 m/s would
	# otherwise fire one arm over the horizon while the player walked on.
	_ragdoll.take_hit(at, away * minf(hardest, KNOCK_SPEED_CAP) * KNOCK_WEIGHT,
		-_up() * _gravity())


func _begin_crash(carried: Vector3, preserve_velocity := false) -> void:
	# One crash per crash. A flight into a hillside reaches here twice — once
	# through `_end_flight`, which the ground guard calls, and once from the
	# guard's own answer back in the move — and a second pass would restart the
	# timer and count the fall twice while the ragdoll, already limp, ignored it.
	if _stance == Stance.CRASH:
		return
	LagTracker.note("combat", "crash at %.1f m/s" % carried.length())
	_crash_left = CRASH_TIME
	_tumble = 0.0
	_tumble_rate = clampf(carried.length() * TUMBLE_PER_SPEED,
		TUMBLE_RATE_RANGE.x, TUMBLE_RATE_RANGE.y)
	_crashes += 1
	floor_snap_length = _floor_snap
	# Ordinary impacts settle into a ground slide. An authored combat throw keeps
	# all three axes so the capsule and newly limp bones receive the same launch.
	velocity = carried if preserve_velocity \
		else _flat(carried).limit_length(CRASH_SLIDE)
	# Spent. Left standing it would have the next landing judged by this crash.
	_flight_velocity = Vector3.ZERO
	_underwater_launch = false
	_run_speed = 0.0
	_cruise = float_speed
	_apply_stance(Stance.CRASH)
	_interrupt_combat_actions()
	if _ragdoll != null and _ragdoll.built():
		# The hold is arms placed by IK, and a limp body has no use for either.
		if _weapon_pose != null:
			_weapon_pose.active = false
		# Guarded from the tick it goes limp, not from the next one. The frame a
		# crash starts is the fastest the bones will ever be moving.
		var planet := _planet_below()
		if planet != null and _ground_radius > 0.0:
			_ragdoll.set_floor(planet.global_position, _ground_radius)
		_ragdoll.go_limp(velocity, -_up() * _gravity())
		# How high the bones sat over the capsule's feet at the moment they were
		# handed over, which is the offset the crash should keep. Measured rather
		# than assumed: it is the average of whichever bones this rig turned out
		# to have, taken from whatever pose the body happened to be in.
		_crash_body_lift = (_ragdoll.centre() - global_position).dot(_up())


## No steering and no jumping: the whole point is that the player is not driving
## for a moment. Gravity and friction are all that act, and the body gets up the
## instant it is allowed to — which is not while something is over it.
##
## The capsule chases the limp body rather than coasting on its own friction.
## Everything that is attached to the player and not to the bones hangs off the
## capsule — the camera above all, but also the eye line, the interaction ray and
## the position other peers are told about — so a capsule that stops where the
## crash started while the body tumbles on leaves the view pointed at the ground
## the player used to be lying on, and stands them up a few metres from their own
## corpse.
##
## Chasing is not the same as being dragged. The capsule is still swept by
## `move_and_slide`, so a wall stops it whatever the bones did, and the speed it
## may spend closing the gap is capped: a limb that finds its way somewhere the
## capsule cannot follow pulls the view for a moment and then gives up, rather
## than firing the player across the world after it.
##
## What is followed is both what the body is doing and where it has got to. Along
## the ground, always. Up the surface normal, only while the capsule is off it: on
## the ground that correction would answer a bone the surface has nudged by
## lifting the capsule off the floor it is waiting to get up from, so there it
## does no more than hold the climb down to the body's own.
func _crash_move(delta: float) -> void:
	var grounded_before := _grounded()
	var can_recover := not _dead
	if _forced_ragdoll:
		_forced_ragdoll_left = maxf(_forced_ragdoll_left - delta, 0.0)
		if not _dead and grounded_before and _forced_ragdoll_left <= 0.0:
			if not _forced_recovery_started:
				_forced_recovery_started = true
				_crash_left = CRASH_RISE
			else:
				_crash_left = maxf(_crash_left - delta, 0.0)
		else:
			# Keep the physics influence fully limp while airborne (and forever
			# while dead), even after the minimum reaction time has elapsed.
			_crash_left = maxf(_crash_left, CRASH_RISE)
			can_recover = false
	else:
		_crash_left = maxf(_crash_left - delta, 0.0)
	if not grounded_before:
		velocity -= _up() * (_gravity() * delta)
	var limp := _ragdoll != null and _ragdoll.limp()
	var along := _flat(velocity)
	var rise := _rise()
	var gap := _flat(_ragdoll.centre() - global_position) if limp else Vector3.ZERO
	if limp and gap.length() <= CRASH_CHASE_REACH:
		# What the body is doing, plus a bounded pull toward where it has got to.
		# The pull on its own — which is what this was — trails a body that is
		# still travelling by the chase time, and that is a hand's breadth at
		# tumbling speed and tens of metres behind a blast that throws the player
		# at sixty. Straight at the body rather than a force toward it, because a
		# spring would overshoot a tumble that is still turning.
		var drift := _ragdoll.drift()
		along = _flat(drift) \
			+ (gap / CRASH_CHASE_TIME).limit_length(CRASH_CHASE_SPEED)
		var climb := drift.dot(_up())
		if not grounded_before:
			# Off the ground the height is followed as well, back to the offset
			# the crash started with: a body launched off its feet pushes off the
			# ground on the way, so it does not arrive at the top of an arc the
			# capsule's own gravity would have put it at, and the camera hanging
			# off the capsule is looking somewhere the character is not.
			#
			# Only while airborne. On the ground the same correction would answer
			# a bone the surface has nudged upward by lifting the capsule off the
			# floor it is waiting to get up from.
			var lift := (_ragdoll.centre() - global_position).dot(_up())
			rise = climb + clampf(
				(lift - _crash_body_lift) / CRASH_CHASE_TIME,
				-CRASH_CHASE_SPEED, CRASH_CHASE_SPEED)
		elif rise > 0.0:
			# Held down to what the body is climbing at, never lifted up to it,
			# and never past a standstill: the capsule has to stay free to fall.
			rise = minf(rise, maxf(climb, 0.0))
	else:
		along = along.move_toward(Vector3.ZERO, CRASH_FRICTION * delta)
	velocity = along + _up() * rise
	move_and_slide()
	_catch_ground()
	if limp:
		_ragdoll.set_pull(-_up() * _gravity())
		# Half the crashes worth having happen where the collider budget has not
		# reached yet, and bones with nothing to land on go through the planet
		# while the capsule stops on top of it. The guard the capsule already has
		# is handed to them, at the radius it has just measured.
		var planet := _planet_below()
		if planet != null and _ground_radius > 0.0:
			_ragdoll.set_floor(planet.global_position, _ground_radius)
		# The last of the crash is the pose easing out of where the body actually
		# landed and into the clip that stands it up, which is what makes getting
		# up a movement rather than a cut.
		if can_recover and _crash_left < CRASH_RISE:
			_ragdoll.settle(_crash_left / CRASH_RISE)
	if can_recover and _crash_left <= 0.0 and _grounded():
		# The chase is a means of keeping up, not momentum the player earned, so
		# it does not survive into the stance that can be steered.
		var completed_forced_reaction := _forced_ragdoll
		velocity = _up() * _rise()
		if _ragdoll != null:
			_ragdoll.stand_up()
		if _weapon_pose != null:
			_weapon_pose.active = true
		_forced_ragdoll = false
		_forced_recovery_started = false
		_forced_ragdoll_left = 0.0
		_try_stand()
		# Reliable completion keeps an owning client from predicting out of the
		# reaction a frame before the host and then ignoring the final correction.
		if completed_forced_reaction and _is_host_authority():
			var quiet := DamageHit.impact(combat_position(), 0.01, 0.0)
			quiet.faction = DamageHit.Faction.ENEMY
			_broadcast_combat_state(0.0, quiet, false, false, false)


func _end_flight(carry_air := false) -> void:
	_flight_jump_latched = false
	_underwater_launch = false
	# Every way out of flight comes through here. Only an actual floor contact
	# gets landing treatment; the land key in open air still cancels normally.
	# `_flight_velocity` is used because collision has already spent or redirected
	# the velocity that describes the arrival.
	var landed := _grounded() or test_move(global_transform, -_up() * land_clearance)
	if landed and _flight_velocity.length() >= CRASH_SPEED:
		_land_fast_flight(_flight_velocity)
		return
	_flight_velocity = Vector3.ZERO
	floor_snap_length = _floor_snap
	# A thousand metres a second does not survive contact with the floor, and it
	# should not survive the cancel key either. Without this the run that follows
	# would inherit the flight's speed, and the walk clip would strobe while the
	# player slid across the world at a sprint's hundred times over.
	# An empty tank is the other case: the body is still in the air, so the
	# flight's heading stays and the ordinary jump-fall takes over — gravity and
	# weak air steer, without braking a coast that is already faster than a run.
	if landed or not carry_air:
		velocity = _flat(velocity).limit_length(sprint_speed)
	_cruise = float_speed
	_apply_stance(Stance.STAND)


## Resolves a fast flight into flat ground by its approach angle. Steep arrivals
## plant into the authored one-knee pose; shallow ones carry most of their speed
## into a run. Non-floor impacts never arrive here — they remain crashes.
func _land_fast_flight(carried: Vector3) -> void:
	var speed := carried.length()
	var into_ground := maxf(-carried.dot(_up()), 0.0)
	var steep := into_ground / maxf(speed, 0.001) >= HERO_LANDING_ANGLE
	_flight_velocity = Vector3.ZERO
	_cruise = float_speed
	floor_snap_length = _floor_snap
	_land_left = 0.0
	if steep:
		velocity = _flat(carried).limit_length(walk_speed)
		_run_speed = walk_speed
		_hero_clip = "HeroLand"
		_hero_left = HERO_LANDING_TIME
		# The look pitch is *not* reset here. A dive arrives with the view aimed
		# into the floor and HeroLand wants it on the horizon, but snapping it
		# is a cut: the camera is somewhere else on the very next frame. It is
		# flown up to level over the pose instead, in `_hero_land_move`.
		_apply_stance(Stance.HERO)
		return
	var running := (_flat(carried) * RUN_LANDING_KEEP).limit_length(run_top_speed)
	velocity = running
	_run_speed = clampf(running.length(), walk_speed, run_top_speed)
	_apply_stance(Stance.STAND)


## Holds the planted hero pose briefly, spending the small amount of horizontal
## motion a steep arrival may still have, then hands control back standing.
func _hero_land_move(delta: float) -> void:
	_hero_left = maxf(_hero_left - delta, 0.0)
	# The dive's pitch, flown up to the horizon rather than cut there. The
	# camera blend in `_update_camera` is already easing the framing off this
	# same value, so both halves of the move arrive together and what is left at
	# the end of the pose is a level view the walk can simply keep.
	_pitch = lerpf(_pitch, 0.0, 1.0 - exp(-delta * HERO_PITCH_RATE))
	var along := _flat(velocity).move_toward(Vector3.ZERO, ground_friction * delta)
	velocity = along + _up() * minf(_rise(), 0.0)
	move_and_slide()
	_catch_ground()
	if _hero_left <= 0.0:
		velocity = Vector3.ZERO
		_try_stand()


func _grapple_target_from_path(path_text: String) -> Node3D:
	var path := NodePath(path_text)
	if path.is_empty() or path.is_absolute():
		return null
	for index in path.get_name_count():
		if path.get_name(index) == &"..":
			return null
	var world := DamageHit.game_world_of(self)
	return world.get_node_or_null(path) as Node3D if world != null else null


func apply_construct_carry(motion: Vector3) -> void:
	if not motion.is_finite():
		return
	velocity = motion
	_flight_velocity = motion
	if _stance == Stance.FLY:
		_cruise = motion.length()


func spawn_ability_field(id: String) -> bool:
	if not can_attack() or not CrawlerRules.is_field_ability(id):
		return false
	if not _has_listeners() or multiplayer.is_server():
		return _publish_ability_field(id)
	_ability_field_request_sequence += 1
	_request_ability_field.rpc_id(1, _ability_field_request_sequence, id)
	return true


func field_cast_origin() -> Vector3:
	var up := _up().normalized()
	var forward := look_direction()
	forward -= up * forward.dot(up)
	if forward.length_squared() < 0.001:
		forward = -global_basis.z
		forward -= up * forward.dot(up)
	if forward.length_squared() < 0.001:
		forward = Vector3.FORWARD
	forward = forward.normalized()
	return combat_position() + up * 0.12 + forward * 0.55


func _publish_ability_field(id: String) -> bool:
	if not can_attack() or not CrawlerRules.is_field_ability(id):
		return false
	var definition := ItemDB.ability_definition(id)
	if definition == null:
		return false
	var stats := definition.stats.duplicate(true)
	var overlay := crawler_ability_overlay(id)
	for key: Variant in overlay:
		stats[str(key)] = overlay[key]
	if has_method(&"crawler_element_scale"):
		stats["element"] = maxf(float(call(&"crawler_element_scale")), 0.0)
	var at := field_cast_origin()
	_host_ability_field_sequence += 1
	if not _has_listeners():
		_apply_ability_field(_host_ability_field_sequence, id, at, stats)
	else:
		_apply_ability_field.rpc(_host_ability_field_sequence, id, at, stats)
	return true


func place_ability_wall(id: String) -> int:
	var definition := ItemDB.ability_definition(id)
	if not can_attack() or definition == null \
			or definition.construct_type \
				!= AbilityDefinition.ConstructType.BARRIER:
		return 0
	_ability_wall_request_sequence += 1
	_ability_wall_result_sequence = _ability_wall_request_sequence
	_ability_wall_result = ProjectileRequestState.PENDING
	if not _has_listeners() or multiplayer.is_server():
		var accepted := _publish_ability_wall(
			_ability_wall_request_sequence, id)
		_ability_wall_result = ProjectileRequestState.ACCEPTED \
			if accepted else ProjectileRequestState.REJECTED
		return _ability_wall_request_sequence if accepted else 0
	_request_ability_wall.rpc_id(
		1, _ability_wall_request_sequence, id)
	return _ability_wall_request_sequence


func ability_wall_request_state(request_sequence: int) -> int:
	if request_sequence <= 0 \
			or request_sequence != _ability_wall_result_sequence:
		return ProjectileRequestState.REJECTED
	return _ability_wall_result


func _publish_ability_wall(request_sequence: int, id: String) -> bool:
	var definition := ItemDB.ability_definition(id)
	if not can_attack() or definition == null \
			or definition.construct_type \
				!= AbilityDefinition.ConstructType.BARRIER:
		return false
	var stats := definition.stats.duplicate(true)
	var overlay := crawler_ability_overlay(id)
	for key: Variant in overlay:
		stats[str(key)] = overlay[key]
	var size := Vector3(
		maxf(float(stats.get("wall_width", 8.0)), 0.2),
		maxf(float(stats.get("wall_height", 4.0)), 0.2),
		maxf(float(stats.get("wall_thickness", 0.35)), 0.05))
	var house := float(stats.get("house", 0.0)) > 0.0
	var project_speed := maxf(float(stats.get("project", 0.0)), 0.0)
	var firewall := maxf(float(stats.get("firewall", 0.0)), 0.0)
	var up := _up().normalized()
	var forward := look_direction()
	forward -= up * forward.dot(up)
	if forward.length_squared() < 0.001:
		forward = -global_basis.z
		forward -= up * forward.dot(up)
	forward = forward.normalized()
	var right := forward.cross(up).normalized()
	var basis := Basis(right, up, right.cross(up)).orthonormalized()
	var origin := global_position + up * (size.y * 0.5 + 0.18)
	if house:
		origin = global_position + up * (size.y * 0.5 - size.z * 0.5)
	else:
		origin += forward * maxf(float(stats.get("range", 4.0)), 1.0) \
			* crawler_range_scale()
	var world := DamageHit.game_world_of(self) as GameWorld
	if world == null:
		return false
	var extras := {
		"ability_id": id,
		"house": house,
		"project_speed": project_speed,
		"project_along": forward,
		"firewall": firewall,
	}
	var variant := 2 if uses_float_pose() else 0
	var duration := maxf(float(stats.get("duration", 7.0)), 0.2)
	var fade := maxf(float(stats.get("fade_duration", 4.0)), 0.0)
	var offsets := PackedFloat32Array([0.0])
	if not house:
		offsets = CrawlerMulti.wall_offsets(CrawlerMulti.shots(stats), size.x)
	var placed := 0
	for slide: float in offsets:
		var at := Transform3D(basis, origin + right * slide)
		if not house and not _ability_wall_space_clear(at, size):
			if placed == 0:
				return false
			continue
		var construct_id := world.allocate_ability_construct_id()
		if construct_id <= 0:
			return placed > 0
		_host_ability_wall_sequence += 1
		if not _has_listeners():
			_apply_ability_wall(
				_host_ability_wall_sequence, request_sequence, construct_id,
				id, at, size, duration, fade, definition.tint, variant, extras)
		else:
			_apply_ability_wall.rpc(
				_host_ability_wall_sequence, request_sequence, construct_id,
				id, at, size, duration, fade, definition.tint, variant, extras)
		placed += 1
	return placed > 0


func _ability_wall_space_clear(at: Transform3D,
		size: Vector3) -> bool:
	var shape := BoxShape3D.new()
	# Placement keeps a small visible/collision gap around existing bodies.
	shape.size = size + Vector3.ONE * 0.08
	var query := PhysicsShapeQueryParameters3D.new()
	query.shape = shape
	query.transform = at
	query.collision_mask = 1
	query.collide_with_areas = false
	query.exclude = DamageHit.rid_list(get_rid())
	return get_world_3d().direct_space_state \
		.intersect_shape(query, 1).is_empty()


func fire_ability_delayed_blast(id: String, from: Vector3,
		along: Vector3) -> int:
	var definition := ItemDB.ability_definition(id)
	if not can_attack() or definition == null \
			or definition.impact_type \
				!= AbilityDefinition.ImpactType.DELAYED_BLAST \
			or not from.is_finite() or not along.is_finite() \
			or along.length_squared() < 0.001:
		return 0
	_delayed_blast_request_sequence += 1
	_delayed_blast_result_sequence = _delayed_blast_request_sequence
	_delayed_blast_result = ProjectileRequestState.PENDING
	if not _has_listeners() or multiplayer.is_server():
		var accepted := _publish_ability_delayed_blast(
			_delayed_blast_request_sequence, id, from, along)
		_delayed_blast_result = ProjectileRequestState.ACCEPTED \
			if accepted else ProjectileRequestState.REJECTED
		return _delayed_blast_request_sequence if accepted else 0
	_request_ability_delayed_blast.rpc_id(
		1, _delayed_blast_request_sequence, id, from, along)
	return _delayed_blast_request_sequence


func ability_delayed_blast_request_state(request_sequence: int) -> int:
	if request_sequence <= 0 \
			or request_sequence != _delayed_blast_result_sequence:
		return ProjectileRequestState.REJECTED
	return _delayed_blast_result


func _publish_ability_delayed_blast(request_sequence: int, id: String,
		from: Vector3, along: Vector3) -> bool:
	var definition := ItemDB.ability_definition(id)
	var overlay := crawler_ability_overlay(id)
	var far := CrawlerReach.far_cast(overlay)
	if not can_attack() or definition == null \
			or definition.projectile_type \
				!= AbilityDefinition.ProjectileType.BEAM \
			or definition.impact_type \
				!= AbilityDefinition.ImpactType.DELAYED_BLAST \
			or not from.is_finite() or not along.is_finite() \
			or from.distance_to(combat_position()) > 5.0 + far + 1.0 \
			or along.length_squared() < 0.001:
		return false
	var host_eyes := eye_points()
	var host_from: Vector3 = (host_eyes[0] + host_eyes[1]) * 0.5
	var host_along := aim_direction(host_from).normalized()
	var used_along := along.normalized() \
		if along.length_squared() > 0.001 else host_along
	if host_along.dot(used_along) < 0.35:
		return false
	host_from = CrawlerReach.shift(host_from, used_along, overlay)
	var reach := maxf(float(overlay.get(
			"range", definition.stats.get("range", CrawlerRules.NAUSICAA_RANGE))), 1.0) \
		* crawler_range_scale()
	var warning := maxf(float(overlay.get("delay", definition.stats.get("delay", 1.0))), 0.1)
	var variant := 2 if uses_float_pose() else 0
	var plan := Nausicaa.plan_landing(self, host_from, used_along, reach, overlay)
	var at: Vector3 = plan.get("position", host_from + used_along * reach)
	var normal: Vector3 = plan.get("normal", -used_along)
	if not at.is_finite() or not normal.is_finite():
		return false
	var follow := plan.get("follow") as Node
	var follow_path := _delayed_blast_follow_path(follow)
	_host_delayed_blast_sequence += 1
	if not _has_listeners():
		_apply_ability_delayed_blast(
			_host_delayed_blast_sequence, request_sequence, id,
			host_from, at, normal, warning, variant, overlay, follow_path)
	else:
		_apply_ability_delayed_blast.rpc(
			_host_delayed_blast_sequence, request_sequence, id,
			host_from, at, normal, warning, variant, overlay, follow_path)
	return true


## Throws the body forward, fist first. Returns whether the punch started.
##
## The direction is taken once and kept, unless Homing is seated, in which
## case the fist locks onto a nearby mob and turns toward them.
func begin_meteor_punch(stats: Dictionary) -> bool:
	if not can_attack() or _stance == Stance.METEOR or _stance == Stance.HERO:
		return false
	_meteor_stats = stats
	_meteor_along = look_direction()
	if _meteor_along.length_squared() < 0.5:
		return false
	_meteor_lock = CrawlerHoming.lock(
		self, global_position, _meteor_along, stats)
	if _meteor_lock != null:
		_meteor_along = CrawlerHoming.aim(
			global_position, _meteor_along, stats, self)
	_meteor_range = maxf(float(stats.get("range", 50.0)), 1.0) \
		* crawler_range_scale()
	# Whatever they already had, or a shove if they were standing still. Taking
	# the larger is what lets a dive be added to rather than thrown away.
	_meteor_speed = maxf(velocity.length(), METEOR_LAUNCH_SPEED)
	# And the catalogue's top speed is what the punch can reach *on its own*,
	# not a ceiling on what it may arrive at. Flight tops out at five times it,
	# so reading this as a limit had a dive at speed spend its whole punch being
	# braked by it — the opposite of what throwing one at that speed is for.
	_meteor_top_speed = maxf(float(stats.get("speed", 200.0)), _meteor_speed)
	_meteor_travelled = 0.0
	_meteor_flew = _stance == Stance.FLY
	_meteor_falling = false
	_meteor_fist = fist_point()
	# Due immediately, so the first thing the fist passes through is cut on the
	# tick it passes through it rather than a twentieth of a second later.
	_meteor_since_sweep = METEOR_DAMAGE_STEP
	_flight_velocity = Vector3.ZERO
	_underwater_launch = false
	_footed = false
	_ground_radius = -1.0
	_coyote_left = 0.0
	_jump_buffered = 0.0
	# The body leaves the ground on the first tick, and a snap length would drag
	# it back down onto whatever it launched off.
	floor_snap_length = 0.0
	if not _meteor_flew:
		global_position += _up() * METEOR_GROUND_LIFT
	velocity = _meteor_along * _meteor_speed
	_apply_stance(Stance.METEOR)
	return true


func meteor_flying() -> bool:
	return _stance == Stance.METEOR


func _meteor_knockback() -> float:
	return maxf(float(_meteor_stats.get("knockback", 0.0)), 0.0) \
		* crawler_knockback_scale()


func _apply_meteor_knockback(hit: DamageHit, force := 1.0) -> void:
	if hit == null:
		return
	var knockback := _meteor_knockback() * maxf(force, 0.0)
	if knockback <= 0.0:
		return
	hit.world_impulse = _meteor_along * knockback
	hit.radial_impulse = knockback * 0.55
	hit.radial_lift = knockback * 0.2


## The punch, from launch to the crater.
##
## Flora is resolved but its answer is thrown away, which is the difference
## between this and every other movement here: a punch that could be slowed by a
## hedge is not a punch. The tree still breaks — [method _resolve_flora_contacts]
## does that — the body simply does not notice.
func _meteor_move(delta: float) -> void:
	if _meteor_falling:
		velocity += -_up() * _gravity() * delta
	else:
		if CrawlerHoming.enabled(_meteor_stats):
			if not CrawlerHoming.is_live(_meteor_lock):
				_meteor_lock = CrawlerHoming.lock(
					self, global_position, _meteor_along, _meteor_stats)
			if _meteor_lock != null:
				_meteor_along = CrawlerHoming.turn(
					_meteor_along,
					CrawlerHoming.combat_at(_meteor_lock) - global_position,
					_meteor_stats, delta)
		_meteor_speed = move_toward(_meteor_speed, _meteor_top_speed,
			METEOR_ACCELERATION * delta)
		velocity = _meteor_along * _meteor_speed
	var carried := velocity
	var was := global_position
	var fist_was := _meteor_fist
	move_and_slide()
	_meteor_travelled += global_position.distance_to(was)
	var flora := _resolve_flora_contacts(carried)
	var handled: Dictionary = flora["handled"]
	_sweep_fist(delta)
	var blocked := _meteor_obstruction(was, fist_was)
	var slid := _meteor_contact(handled)
	var contact := _prefer_building_contact(blocked, slid)
	if not contact.is_empty() and _collider_is_building(contact.get("collider")):
		_land_meteor_on_building(contact, carried.length())
		return
	# Before the guard, which plants the body on the surface and takes the
	# inward speed off it. That speed is what the punch arrived with and what
	# the size of the hole is worked out from, so it has to be read first.
	var arrival := carried.length()
	var caught := _catch_ground()
	if not contact.is_empty():
		_land_meteor(contact["at"], true, arrival)
		return
	# The guard planting the body is an arrival too, and past a certain speed it
	# is the *only* one. A dive covers sixteen metres in a frame at flight's top
	# speed and goes clean through a chunk collider without ever generating a
	# slide collision; the guard's swept test is what notices, and until it was
	# listened to here the punch simply carried on over ground it had already
	# gone through. Filtered the same way a slide contact is, and for the same
	# reason: a flat charge grazes the field it is travelling over.
	if caught and _meteor_along.dot(_up()) < -METEOR_CONTACT_FACING:
		_land_meteor(global_position, true, arrival)
		return
	if _meteor_falling:
		if _grounded():
			_land_meteor(global_position, false, arrival)
		return
	if _meteor_travelled < _meteor_range:
		return
	# The reach is spent with nothing hit. A punch thrown out across the sky is
	# over, and from the air that means handing the flight back. One thrown *at*
	# the planet is not over: the reach is how far the punch carries under its
	# own power, not how long it is allowed to last, and a dive that used its
	# powered distance up in the first fifty metres of a long fall is still a
	# dive. It keeps the pose and the fist and lets what it already has finish
	# the job — the same ending a flat charge gets when it runs out of ground.
	if _meteor_flew and not _diving_at_ground():
		_flight_velocity = velocity
		_apply_stance(Stance.FLY)
	else:
		_meteor_falling = true


## One tick of the fist's damage: a cylinder swept from where the fist was to
## where it is. Swept rather than stamped because at two hundred metres a second
## the fist covers three metres between ticks, and a stamp would leave the flora
## between them standing.
func _sweep_fist(delta: float) -> void:
	_meteor_since_sweep += delta
	if _meteor_since_sweep < METEOR_DAMAGE_STEP:
		return
	_meteor_since_sweep -= METEOR_DAMAGE_STEP
	var fist := fist_point()
	var knockback := _meteor_knockback()
	for slide: float in CrawlerMulti.punch_offsets(CrawlerMulti.shots(_meteor_stats)):
		var from := _meteor_fist + _meteor_along * slide
		var to := fist + _meteor_along * slide
		var hit := DamageHit.beam(from, to,
			float(_meteor_stats.get("radius", METEOR_FIST_RADIUS)),
			float(_meteor_stats.get("damage", 0.0)) * METEOR_TICK_SHARE)
		hit.ability_id = "meteor_punch"
		if knockback > 0.0:
			hit.world_impulse = _meteor_along * knockback * METEOR_TICK_SHARE
		CrawlerElements.stamp(hit, self, "meteor_punch", _meteor_stats)
		deal_damage(hit)
	_meteor_fist = fist


## Whether the punch is coming down at the planet rather than crossing it, which
## is what separates a dive that should be allowed to finish from one thrown out
## over a landscape that should give the flight back once its reach is spent.
func _diving_at_ground() -> bool:
	if _meteor_along.dot(_up()) > -METEOR_DIVE_FACING:
		return false
	return _altitude() <= velocity.length() * METEOR_COMMIT_LEAD


## Metres between the body and the height field under it, negative inside the
## ground. [constant INF] where there is no planet to measure against, so that
## every caller's distance test simply fails rather than reading as zero.
func _altitude() -> float:
	var planet := _planet_below()
	if planet == null:
		return INF
	# The guard works this out every frame and leaves it here. Only worth asking
	# the shape again if it did not get that far, which is the frames before the
	# first one it runs on.
	var radius := _ground_radius if _ground_radius > 0.0 else _field_radius_here()
	if radius <= 0.0:
		return INF
	return planet.to_local(global_position).length() - radius


## The first thing the punch ran into that was not flora, or nothing.
func _meteor_contact(handled: Dictionary) -> Dictionary:
	for index in get_slide_collision_count():
		var hit := get_slide_collision(index)
		# Only static things stop it. Punching another player through a hillside
		# is a fight this game does not have yet, and it should not end the move.
		if not (hit.get_collider() is StaticBody3D):
			continue
		# The ground a flat punch was thrown from is met at a graze on every
		# tick, and stopping on it would end the move where it started.
		if hit.get_normal().dot(_meteor_along) > -METEOR_CONTACT_FACING:
			continue
		if _impact_was_handled(hit, handled):
			continue
		return {
			"at": hit.get_position(),
			"normal": hit.get_normal(),
			"collider": hit.get_collider(),
		}
	return {}


## Swept test so a punch at flight speed cannot tunnel through a tower the
## same way it used to tunnel through a hillside. Slide contacts are still
## consulted; this is the backup that notices a face between two samples.
func _meteor_obstruction(from: Vector3, fist_from: Vector3) -> Dictionary:
	var space := get_world_3d().direct_space_state
	var exclude := DamageHit.rid_list(get_rid())
	var hits: Array[Dictionary] = []
	var fist := fist_point()
	hits.append(_meteor_ray(space, from, global_position, exclude))
	hits.append(_meteor_ray(space, fist_from, fist, exclude))
	var best: Dictionary = {}
	var nearest := 1.0e9
	for hit in hits:
		if hit.is_empty():
			continue
		var at: Vector3 = hit.get("at", Vector3.ZERO)
		var away := from.distance_squared_to(at)
		if away < nearest:
			nearest = away
			best = hit
	return best


func _meteor_ray(space: PhysicsDirectSpaceState3D, from: Vector3, to: Vector3,
		exclude: Array[RID]) -> Dictionary:
	if from.distance_squared_to(to) < 0.0001:
		return {}
	var skipped := DamageHit.rid_list()
	for rid in exclude:
		skipped.append(rid)
	var query := PhysicsRayQueryParameters3D.create(from, to)
	query.hit_from_inside = true
	query.hit_back_faces = true
	query.collision_mask = collision_mask
	for _step in 6:
		query.exclude = skipped
		var hit := space.intersect_ray(query)
		if hit.is_empty():
			return {}
		var collider = hit.get("collider")
		if not (collider is StaticBody3D):
			return {}
		if _collider_is_building(collider):
			return {
				"at": hit.get("position"),
				"normal": hit.get("normal", -_meteor_along),
				"collider": collider,
			}
		if hit.get("normal", Vector3.UP).dot(_meteor_along) > -METEOR_CONTACT_FACING:
			if collider is CollisionObject3D:
				skipped.append((collider as CollisionObject3D).get_rid())
				continue
			return {}
		return {
			"at": hit.get("position"),
			"normal": hit.get("normal", -_meteor_along),
			"collider": collider,
		}
	return {}


func _prefer_building_contact(a: Dictionary, b: Dictionary) -> Dictionary:
	if _collider_is_building(a.get("collider")):
		return a
	if _collider_is_building(b.get("collider")):
		return b
	if not a.is_empty():
		return a
	return b


func _collider_is_building(collider: Variant) -> bool:
	if collider == null:
		return false
	if CityBuilding.from_collider(collider) != null:
		return true
	var node := collider as Node
	while node != null:
		if node is StaticBody3D and String(node.name) == "CityBuildingsBody":
			return true
		node = node.get_parent()
	return false


## Punch met a building rather than the planet: damage the lot at the contact
## and stop there. Digging a crater along the radial would teleport the body
## through the tower onto the ground beneath it.
func _land_meteor_on_building(contact: Dictionary, arrival: float) -> void:
	var at: Vector3 = contact.get("at", global_position)
	var normal: Vector3 = contact.get("normal", -_meteor_along)
	if not at.is_finite():
		at = global_position
	if normal.length_squared() < 0.001 or not normal.is_finite():
		normal = -_meteor_along
	normal = normal.normalized()
	var force := _impact_scale(arrival)
	var reach := maxf(float(_meteor_stats.get("radius", METEOR_FIST_RADIUS)) * 1.6, 2.4)
	for slide: float in CrawlerMulti.punch_offsets(CrawlerMulti.shots(_meteor_stats)):
		var blow_at := at + _meteor_along * slide
		var blow := DamageHit.impact(blow_at, reach,
			float(_meteor_stats.get("impact", 0.0)) * force)
		blow.ability_id = "meteor_punch"
		blow.affects_flora = false
		blow.explosive = true
		_apply_meteor_knockback(blow, force)
		CrawlerElements.stamp(blow, self, "meteor_punch", _meteor_stats)
		deal_damage(blow)
		CrawlerBubbles.emit_blast(self, "meteor_punch", blow_at, reach)
		CrawlerLingers.emit_blast(self, "meteor_punch", blow_at, reach)
		if slide > 0.001:
			play_meteor_impact_dust(blow_at, normal, METEOR_FIST_RADIUS * force, force)
	play_meteor_impact_dust(at, normal, METEOR_FIST_RADIUS * force, force)
	global_position = at + normal * 0.65
	_swept_from = global_position
	var bounce := velocity.bounce(normal)
	velocity = bounce.limit_length(walk_speed * 2.4) + normal * 6.0
	_meteor_falling = false
	_meteor_stats = {}
	_flight_velocity = Vector3.ZERO
	floor_snap_length = _floor_snap
	_land_left = 0.0
	_crater_left = 0.0
	if _meteor_flew:
		_flight_velocity = velocity
		_apply_stance(Stance.FLY)
	else:
		_apply_stance(Stance.STAND)


## The end of the punch: a crater, a spreading blow, and the planted pose.
##
## [param struck] separates the two endings. Hitting something cuts a bowl where
## the fist met it. Running out of reach and coming down instead cuts a cone
## ahead of the feet — the ground opened by a landing rather than by a blow, and
## the shape the requirement asks for.
func _land_meteor(at: Vector3, struck: bool, arrival: float) -> void:
	var force := _impact_scale(arrival)
	var crater_radius := maxf(
		float(_meteor_stats.get("crater_radius", METEOR_CRATER_RADIUS)), 0.1)
	var crater_depth := maxf(
		float(_meteor_stats.get("crater_depth", METEOR_CRATER_DEPTH)), 0.1)
	var spread := METEOR_SPREAD * maxf(float(_meteor_stats.get("size", 1.0)), 1.0)
	var world_planet := _planet_below()
	var impact_up := world_planet.up_at(at) if world_planet != null else _up()
	var copies := CrawlerMulti.shots(_meteor_stats)
	for slide: float in CrawlerMulti.punch_offsets(copies):
		var blow_at := at + _meteor_along * slide
		var blow := DamageHit.area(blow_at, spread * force,
			float(_meteor_stats.get("impact", 0.0)) * force, 1.0)
		blow.ability_id = "meteor_punch"
		blow.explosive = true
		_apply_meteor_knockback(blow, force)
		# Flora gets the smaller categorical crater volume below. Offering this
		# wider actor spread to it first both left a tapered rim and paid for the
		# densest part of the jungle twice on the landing frame.
		blow.affects_flora = false
		CrawlerElements.stamp(blow, self, "meteor_punch", _meteor_stats)
		deal_damage(blow)
		CrawlerBubbles.emit_blast(self, "meteor_punch", blow_at, spread * force)
		CrawlerLingers.emit_blast(self, "meteor_punch", blow_at, spread * force)
		if slide > 0.001:
			play_meteor_impact_dust(
				blow_at, impact_up, crater_radius * force, force)

	# Measured before the hole is cut, so that whenever it does turn up — this
	# frame on a host, a round trip later on a client — there is something to
	# recognise it against.
	_await_crater()

	play_meteor_impact_dust(
		at, impact_up, crater_radius * force, force)
	if world_planet != null:
		var centre := at
		if not struck:
			centre = at + _flat(_meteor_along).normalized() * METEOR_CONE_AHEAD
		# The combat blast above deliberately dissipates. Terrain does not:
		# anywhere inside this circle loses its surface, so a plant there either
		# comes out by the root or hangs in the air over the new floor. This
		# second, flora-only volume is flat across the scar and quiet under the
		# impact cloud; it cannot increase what another combatant takes.
		var flatten := DamageHit.area(centre,
			crater_radius * force + METEOR_FLORA_MARGIN,
			maxf(METEOR_FLORA_DAMAGE,
				float(_meteor_stats.get("impact", 0.0)) * force), 0.0)
		flatten.ability_id = "meteor_punch"
		flatten.affects_combatants = false
		flatten.plant_break_effects = false
		deal_damage(flatten)
		var scar := TerrainScars.Scar.new()
		scar.direction = world_planet.to_local(centre).normalized()
		scar.radius = crater_radius * force
		scar.depth = crater_depth * force
		scar.profile = TerrainScars.Profile.BOWL if struck \
			else TerrainScars.Profile.CONE
		# Broken ground rather than burned. A punch does not scorch, and the
		# faint darkening is the soil that has been turned over.
		scar.char = 0.35
		scar.tint = Color(0.16, 0.13, 0.11)
		request_scar(scar)

	_meteor_falling = false
	_meteor_stats = {}
	_flight_velocity = Vector3.ZERO
	_cruise = float_speed
	floor_snap_length = _floor_snap
	_land_left = 0.0
	_run_speed = walk_speed
	velocity = _flat(velocity).limit_length(walk_speed)
	# The same pose a steep flight landing gets, and for the same reason: the
	# crater is already in the height field by the time the pose finishes, so
	# the player stands up at the bottom of the hole they just made.
	var definition := ItemDB.ability_definition("meteor_punch")
	_hero_clip = String(definition.impact_animation) \
		if definition != null and not definition.impact_animation.is_empty() \
		else "HeroLand"
	_hero_left = HERO_LANDING_TIME
	_apply_stance(Stance.HERO)
	# Once now, because on a host and in a single-player session the hole was cut
	# inside `request_scar` above and the body can be put in it on this very
	# frame. A client is owed one and takes it up in `_settle_into_crater`.
	_settle_into_crater(0.0)


## How much bigger than an ordinary punch this arrival is worth, from the speed
## it came in at.
##
## Measured against the ability's *quoted* top speed rather than against the one
## this particular punch was allowed, so a punch thrown at the speed the menu
## advertises digs exactly the hole it always did and only a dive that beat it
## digs a bigger one. Square-rooted, because that is near enough how a real
## impact scales and because the alternative — a crater growing with the square
## of the speed — is a hole the size of the town at flight's top speed.
func _impact_scale(arrival: float) -> float:
	var quoted := maxf(float(_meteor_stats.get("speed", 200.0)), 1.0)
	return clampf(sqrt(arrival / quoted), 1.0, METEOR_CRATER_MAX_SCALE)


## Starts watching for the crater a punch has just asked for, from the ground
## height that punch landed on.
func _await_crater() -> void:
	_crater_left = CRATER_SETTLE
	_crater_floor = _field_radius_here()


## Follows the punch's own crater down, so the body ends standing at the bottom
## of the hole rather than dropped into it a moment afterwards.
##
## Nothing else in the file does this, and nothing else should. [method
## _catch_ground] only ever pushes a body *out* of ground it has ended up
## inside; there is deliberately no path that pulls one *down* onto ground that
## has gone away beneath it, because for ordinary terrain that is a body falling
## and falling is correct. A crater is the one case where the ground moving is
## the whole point, and the body that moved it should go with it.
##
## Watched for over a window rather than done once, because the hole does not
## always exist yet. A host cuts it inside [method GameWorld.request_scar] on
## the same frame; a client has to ask for it and is granted it a round trip
## later, and until then its own height field still describes level ground.
func _settle_into_crater(delta: float) -> void:
	if _crater_left <= 0.0:
		return
	_crater_left -= delta
	var floor_radius := _field_radius_here()
	if floor_radius <= 0.0 or floor_radius > _crater_floor - CRATER_STEP:
		return
	var planet := _planet_below()
	var out := planet.to_local(global_position).normalized()
	if PatchCity.deck_blocks(out, get_tree()):
		_crater_left = 0.0
		return
	global_position = planet.to_global(out * floor_radius)
	# The ground guard reads this as the place the body set off from and rewinds
	# to where it crossed the surface. Being planted is not a move it made, and
	# leaving the old spot here would have the guard undo it as a tunnel.
	_swept_from = global_position
	velocity = _flat(velocity)
	_footed = true
	_crater_left = 0.0


## Distance from the planet's centre to the ground directly under the body,
## read from the height field at the spacing the ground is actually drawn at.
## Zero when there is no planet to ask.
func _field_radius_here() -> float:
	var planet := _planet_below()
	if planet == null or planet.shape == null:
		return 0.0
	var local := planet.to_local(global_position)
	if local.length_squared() < 1.0:
		return 0.0
	return planet.shape.radius + planet.shape.elevation(
		local.normalized(), planet.spacing_underfoot())


## Where either animated hand is in the world. Starfire alternates these, while
## Meteor Punch keeps the right-hand convenience wrapper below.
func hand_points() -> Array[Vector3]:
	return [hand_point(true), hand_point(false)]


## Midpoint of both palms. Kame's beam and the nuke cores leave from here.
func merged_hand_point() -> Vector3:
	var hands := hand_points()
	return (hands[0] + hands[1]) * 0.5


func hand_point(left := false) -> Vector3:
	var skeleton := Wardrobe.skeleton_of(character) if character != null else null
	if skeleton != null:
		var bone_name := &"LeftHand" if left else &"RightHand"
		var bone := CharacterRig.find_bone(skeleton, bone_name)
		if bone >= 0:
			return skeleton.global_transform \
				* skeleton.get_bone_global_pose(bone) * Vector3.ZERO
	return global_position + _up() * (_body_height * 0.6) \
		- global_basis.z * (_body_height * 0.35) \
		+ global_basis.x * (-0.28 if left else 0.28)


## Where the right fist is in the world. The punch's damage hangs off this, so
## it follows the arm through the clip rather than sitting at the body's centre.
func fist_point() -> Vector3:
	return hand_point(false)


## Hands one volume of damage to every peer, including this one.
##
## The wire form is the hit itself, so an ability that invents a new shape needs
## nothing added here. Reliable: a dropped packet is a plant left standing on
## one machine and gone on another.
func deal_damage(hit: DamageHit) -> void:
	if hit == null or not can_attack():
		return
	hit.faction = combat_faction()
	hit.set_source(self, peer_id)
	_combat_event_sequence += 1
	hit.sequence = _combat_event_sequence
	# Training enemies are local dummies. Their outgoing hits must be able to
	# reach the live player (ENEMY faction), which the hero-packet path refuses.
	if training_enemy:
		if _is_host_authority():
			DamageHit.apply_to_world(self, hit)
		return
	if not _has_listeners():
		DamageHit.apply_to_world(self,
			DamageHit.sanitize_player_packet(hit.to_wire(), peer_id, self))
	elif multiplayer.is_server():
		_publish_hero_combat_hit(
			DamageHit.sanitize_player_packet(hit.to_wire(), peer_id, self))
	else:
		_request_hero_combat_hit.rpc_id(
			1, _combat_event_sequence, hit.to_wire())


## Host-only path for an effect whose cast was already approved and whose
## consequence was built from its AbilityDefinition. Unlike a client hero
## packet, the trusted reaction and radial impulse must survive serialization.
func deal_authoritative_ability_damage(hit: DamageHit) -> void:
	if hit == null or not _is_host_authority() \
			or ItemDB.ability_definition(hit.ability_id) == null:
		return
	hit.faction = DamageHit.Faction.PLAYER
	hit.set_source(self, peer_id)
	if not _has_listeners():
		DamageHit.apply_to_world(self, hit)
	else:
		_publish_hero_combat_hit(hit, false)


## Host-only explosive self-hit. Source exclusion would skip the caster, and
## coop partners must not take this volume, so it is applied to this body only.
func deal_authoritative_self_explosion(hit: DamageHit) -> void:
	if hit == null or not _is_host_authority():
		return
	hit.faction = DamageHit.Faction.ENEMY
	hit.affects_flora = false
	hit.explosive = true
	hit.target_peer = peer_id
	if hit.source_node(self) == null:
		hit.set_source(self, peer_id)
	apply_damage(hit.resolved_for(self))


## Kept for older call sites. Explosive player damage now only hits the caster.
func deal_authoritative_player_damage(hit: DamageHit) -> void:
	deal_authoritative_self_explosion(hit)


func _publish_hero_combat_hit(hit: DamageHit,
		require_attack := true) -> void:
	if hit == null or (require_attack and not can_attack()):
		return
	# The server's event sequence is independent from a client's request
	# sequence, so reconnects and two sources cannot collide.
	_host_combat_publish_sequence += 1
	hit.sequence = _host_combat_publish_sequence
	_apply_hero_combat_hit.rpc(hit.sequence, hit.to_wire())


## Whether sending an ability tick to the network would reach anybody.
##
## A single-player session still has a multiplayer peer — an offline one — so
## asking whether a peer exists is not the same question and answering it sent
## every beam and fist tick through the serialiser to be delivered back to the
## machine that wrote it. These run tens of times a second while an ability is
## held, so the call that goes nowhere is worth not making.
func _has_listeners() -> bool:
	return multiplayer.has_multiplayer_peer() \
		and not multiplayer.get_peers().is_empty()


func _is_host_authority() -> bool:
	return not multiplayer.has_multiplayer_peer() or multiplayer.is_server()


func _fly_move(delta: float) -> void:
	var input := _steer_vector()
	# The camera's basis rather than the body's, because looking is the steering:
	# hold forward while looking down and you dive. Only the head pitches, so the
	# camera's own X stays level and a strafe never rolls the flight path.
	var wish := camera.global_basis * Vector3(input.x, 0.0, input.y)
	if not _steer_held(&"jump"):
		_flight_jump_latched = false
	if _steer_held(&"jump") and not _flight_jump_latched and _beam_root < 0.4:
		wish += _up()
	if _beam_root > 0.001:
		wish *= 1.0 - _beam_root
	var steering := wish.length_squared() > 0.0001

	# Level or on the way down the hover runs at its full pace; the more of the
	# heading is straight up, the more it gives back. Read off the wish rather
	# than off the velocity, so the cap changes with what is being asked for and
	# not with what the body has not finished doing yet.
	var climbing := clampf(wish.normalized().dot(_up()), 0.0, 1.0) if steering else 0.0
	var hover := lerpf(float_speed, climb_speed, climbing)

	# Only winds up while there is a direction to wind up in. Otherwise a player
	# holding the boost while stationary would be charging a target they cannot
	# see, and the next tap of forward would launch them at a thousand metres a
	# second out of nowhere.
	var wanted := fly_speed if steering and _steer_held(&"sprint") else hover
	wanted *= statuses.move_scale() if statuses != null else 1.0
	# One rate across the whole range whichever way it is travelling, so each of
	# the two times reads as the seconds it takes end to end.
	var seconds := boost_time if wanted > _cruise else ease_time
	_cruise = move_toward(_cruise, wanted, (fly_speed - float_speed) / maxf(seconds, 0.01) * delta)

	if steering:
		velocity = velocity.move_toward(
			wish.normalized() * _cruise, (flight_accel + _cruise * flight_turn) * delta)
	else:
		velocity = velocity.move_toward(
			Vector3.ZERO, (flight_drag + velocity.length() * flight_coast) * delta)

	# An intentional launch by a swimmer may remain a flight under the surface.
	# A flight arriving from the air has already become a swim before reaching
	# this function. Underwater, the boost cannot wind up and the entry speed is
	# shed over tens of metres instead of carrying on to the sea bed.
	var fill := _submersion()
	if fill > 0.0:
		_cruise = minf(_cruise, float_speed)
		velocity *= exp(-water_drag * fill * delta)


## Where a speed lies on the same Float-to-Fly continuum used by the visible
## body. Keeping this as one calculation prevents takeoff policy and pose
## selection from quietly acquiring different thresholds.
func _flight_pose_amount(speed: float) -> float:
	return clampf(
		inverse_lerp(float_speed * 1.4, fly_speed * FLAT_OUT, speed), 0.0, 1.0)


# --- Water ------------------------------------------------------------------

## The active local lava field. Kept by identity after the first group lookup;
## unlike the sea it is an irregular set of analytical surfaces rather than one
## radius around the whole planet.
func _lava() -> Node:
	if is_instance_valid(_lava_field):
		return _lava_field
	for candidate in get_tree().get_nodes_in_group(&"lava_fields"):
		var field := candidate as Node
		if field != null and field.has_method("lava_sample"):
			_lava_field = field
			return field
	return null


func _lava_at(point: Vector3) -> Dictionary:
	var field: Node = _lava()
	return field.call("lava_sample", point) as Dictionary if field != null else {}


## Refreshes the pre-move liquid state. Contact is sampled again after movement
## by [method _catch_lava_surface], because a fast entry can begin above it.
func _read_lava() -> void:
	_lava_state = _lava_at(global_position)
	_on_lava = _stance == Stance.SWIM and not _lava_state.is_empty() \
		and float(_lava_state.get("depth", -1.0)) >= 0.0


## Holds a body on the molten surface and converts an arrival into the swim
## stance. The pool floor remains ordinary terrain several metres below, but the
## player never reaches it: this analytical guard runs before the ground guard
## and moves the feet back to a shallow, fixed sink.
func _catch_lava_surface() -> bool:
	var sample := _lava_at(global_position)
	if sample.is_empty() or float(sample.get("depth", -1.0)) <= 0.0:
		return false
	var up: Vector3 = sample["up"]
	# A deliberate flight out of the lava is allowed to clear it. Downward and
	# tangential arrivals are caught; without this exception the launch would be
	# projected back onto the surface on the same tick it began.
	if _stance == Stance.FLY and velocity.dot(up) > 0.5:
		return false
	var entering := _stance != Stance.SWIM or not _on_lava
	global_position = (sample["surface"] as Vector3) \
		- up * float(sample.get("sink", 0.24))
	var along := velocity - up * velocity.dot(up)
	if entering:
		along *= lava_entry_keep
		if _stance == Stance.FLY:
			_enter_swim_from_flight()
		else:
			_run_speed = walk_speed
			floor_snap_length = 0.0
			_apply_stance(Stance.SWIM)
		_stroke = clampf(along.length(), lava_swim_speed, lava_sprint_speed)
	velocity = along
	_underwater_launch = false
	_footed = false
	_on_lava = true
	_lava_state = sample
	_lava_state["depth"] = float(sample.get("sink", 0.24))
	return true


## The sea, or null on a planet without one — which includes every scene that has
## no planet at all, so nothing here may assume it exists.
func _water() -> PlanetWater:
	var planet := _planet_below()
	return planet.water if planet != null else null


## How much of the body is under water: 0 clear of it, 1 with the head under.
##
## Read from the sea's own radius rather than from a collider or an area, so it is
## exact at any depth anywhere on the planet, and true whether or not any ground
## has been built nearby — the same reason the ground guard reads the height
## field instead of the chunk meshes.
func _submersion() -> float:
	if not _lava_state.is_empty():
		var lava_depth := float(_lava_state.get("depth", -1.0))
		if lava_depth > 0.0:
			return clampf(
				lava_depth / maxf(_stance_height(_stance), 0.1), 0.0, 1.0)
	var water := _water()
	if water == null:
		return 0.0
	return clampf(water.depth_at(global_position) / maxf(_stance_height(_stance), 0.1), 0.0, 1.0)


## Air-to-water is a change of movement mode, not a slow flight. A launch made
## by a swimmer is the deliberate exception: it remains flight while submerged,
## then loses that exemption as soon as it reaches air.
func _update_flight_water_state() -> void:
	if _stance != Stance.FLY:
		return
	var fill := _submersion()
	if _underwater_launch:
		if fill <= 0.0:
			_underwater_launch = false
		return
	if fill >= FLIGHT_SWIM_ENTER:
		_enter_swim_from_flight()


## Keeps the arrival's direction and most of its speed, then hands both to the
## swim's stroke and drag. Seeding the visible swim continuum prevents a fast
## entry from spending its first moments in the upright treading pose.
func _enter_swim_from_flight() -> void:
	velocity *= swim_entry_keep
	_flight_velocity = Vector3.ZERO
	_flight_jump_latched = false
	_underwater_launch = false
	_jump_buffered = 0.0
	_swim_launch_left = 0.0
	_cruise = float_speed
	_run_speed = walk_speed
	_stroke = clampf(velocity.length(), swim_speed, swim_sprint_speed)
	var stroking := clampf(
		inverse_lerp(swim_speed * 0.2, swim_speed * 0.75, velocity.length()), 0.0, 1.0)
	var rushing := clampf(
		inverse_lerp(swim_speed, swim_sprint_speed, _stroke), 0.0, 1.0)
	_swim_blend = maxf(_swim_blend, stroking)
	_swim_rush = maxf(_swim_rush, rushing)
	floor_snap_length = 0.0
	_apply_stance(Stance.SWIM)


## Splashes on the way in and on the way out, at the speed the surface was crossed
## at. Runs for every player: a remote peer's position and velocity are both known
## locally, so their entry throws up its own splash with no packet spent saying so.
func _track_water_crossing() -> void:
	var water := _water()
	if water == null:
		return
	var under := water.depth_at(global_position) > 0.0
	if under == _submerged:
		return
	_submerged = under
	var speed := absf(velocity.dot(_up()))
	if speed >= SPLASH_SPEED:
		water.splash(water.surface_above(global_position), speed)


## Prints in the snow, one every [constant Snowfield.STRIDE] metres of ground
## covered. Runs for every player, for the same reason splashes do.
##
## Measured in distance and not off the walk cycle, which is the tempting way to
## do it and the wrong one: the clip is resampled by speed, so its cycle is a
## fixed number of *seconds* and prints taken from it would be a pace apart at a
## walk and a stride apart at a run — feet do the opposite.
##
## Everything it needs it asks the planet for rather than reading the walk's own
## [member _frost] and [member _on_ice], because those are written by the local
## simulation and a remote body never runs one. That costs one height-field
## sample a tick per player, behind a frost test that is a dot product and is
## false everywhere outside the cap.
func _track_footprints() -> void:
	var from := _print_from
	_print_from = global_position
	if _stance == Stance.FLY or _stance == Stance.SWIM or _stance == Stance.CRASH:
		return
	var step := from.distance_to(global_position)
	# Nothing covered, or a jump rather than a walk: the ground guard's rewind, a
	# spawn, a scene change. `_print_from` starts at INF so the first tick after
	# either is caught here and not drawn as a stride across the map.
	if step <= 0.0 or step > PRINT_MAX_STEP:
		return
	var planet := _planet_below()
	if planet == null or planet.shape == null or planet.snowfield == null:
		return
	var local := planet.to_local(global_position)
	var span := local.length()
	if span < 1.0:
		return
	var out := local / span
	if planet.shape.frost(out) <= 0.05:
		return
	var ground := planet.shape.radius \
		+ planet.shape.elevation(out, planet.finest_spacing())
	# Feet in the snow, and the snow not a floe: pack ice sits at exactly
	# PlanetShape.ICE_TOP and takes no prints.
	if absf(span - ground) > PRINT_FOOTING \
			or ground - planet.shape.radius <= PlanetShape.ICE_TOP + 0.05:
		return
	_since_print += step
	if _since_print < Snowfield.STRIDE:
		return
	_since_print = 0.0
	_left_foot = not _left_foot
	var travel := _flat(velocity)
	var facing := travel.normalized() if travel.length_squared() > 0.01 \
		else -global_basis.z
	planet.snowfield.stamp(global_position, _up(), facing, _left_foot)


## Chest deep is swimming; knee deep with something under the feet is not.
## Anything between is whichever it already was.
func _update_water_state(fill: float, grounded: bool) -> void:
	if _on_lava:
		if _stance != Stance.SWIM:
			_stroke = lava_swim_speed
			floor_snap_length = 0.0
			_apply_stance(Stance.SWIM)
		return
	if _stance != Stance.SWIM:
		if fill >= SWIM_ENTER:
			_run_speed = walk_speed
			# Every swim starts on the unhurried stroke, boost held or not. Left
			# where the last one ended, a swimmer who surfaced flat out and went
			# straight back in would be handed the whole wind-up again for free.
			_stroke = swim_speed
			# Snapping would haul a swimmer down onto any ground that passed
			# within reach underneath them.
			floor_snap_length = 0.0
			_apply_stance(Stance.SWIM)
		return
	# Clear of the water entirely means thrown out of it rather than stood up in
	# it, and the body falls from there like anything else in the air.
	if fill <= 0.0 or (fill <= SWIM_EXIT and grounded):
		floor_snap_length = _floor_snap
		# Wading out of the shallows is not a launch. A boosted stroke is worth
		# more than a wound-up run and the ground has no way to have earned it, so
		# it is spent here — but only with something under the feet, because the
		# other way out of this branch is breaking the surface on the way up, and
		# that one is meant to throw the body clear.
		if grounded:
			velocity = velocity.limit_length(sprint_speed)
		_try_stand()


## Steered by the camera, like flight: under water forward is wherever you are
## looking, and the surface is above you as often as it is ahead.
##
## [param fill] is how much of the body the water has hold of, and it scales all
## three terms. A stroke taken half out of the water pushes half as hard, and the
## lift is the same fraction, which is what makes the surface somewhere the body
## settles rather than a line it has to be clamped to.
##
## Which is also why [member swim_surge] is written per m/s asked for rather than
## as a flat figure: the stroke and the drag are then both linear in `fill`, they
## cancel, and the boost reaches the same speed with the shoulders out as it does
## ten metres down. A flat acceleration large enough to beat the drag while
## submerged would be an enormous one at the surface.
func _lava_swim_move(delta: float) -> void:
	var input := _steer_vector()
	var wish := camera.global_basis * Vector3(input.x, 0.0, input.y)
	wish -= _up() * wish.dot(_up())
	var steering := wish.length_squared() > 0.0001
	var wanted := lava_sprint_speed \
		if steering and _steer_held(&"sprint") else lava_swim_speed
	_stroke = move_toward(
		_stroke, wanted, maxf(lava_swim_accel * 0.55, 0.1) * delta)

	var along := _flat(velocity)
	if steering:
		along = along.move_toward(
			wish.normalized() * _stroke, lava_swim_accel * delta)
	else:
		along = along.move_toward(
			Vector3.ZERO, lava_coast_drag * delta)
	# No inward wish, crouch dive, gravity or buoyancy. The post-move guard
	# restores the shallow sink and removes any radial numerical drift.
	velocity = along


func _swim_move(delta: float, fill: float) -> void:
	var input := _steer_vector()
	var wish := camera.global_basis * Vector3(input.x, 0.0, input.y)
	if _steer_held(&"jump"):
		wish += _up()
	elif _steer_held(&"crouch"):
		wish -= _up()
	var steering := wish.length_squared() > 0.0001

	# The boost, wound the same way the flight's is: one rate across the whole
	# range whichever way it is going, so each of the two times reads as the
	# seconds it takes end to end.
	var wanted := swim_sprint_speed if steering and _steer_held(&"sprint") \
		else swim_speed
	var seconds := swim_boost_time if wanted > _stroke else swim_ease_time
	_stroke = move_toward(_stroke, wanted,
		(swim_sprint_speed - swim_speed) / maxf(seconds, 0.01) * delta)

	if steering:
		# Both terms are scaled by `fill`, and so is the drag below, so the two
		# stay in the ratio that decides the top speed however much of the body
		# the water has hold of. A swimmer with their shoulders out is pushing
		# against half as much water and half as much of it is pushing back.
		velocity = velocity.move_toward(wish.normalized() * _stroke,
			(swim_accel + _stroke * swim_surge) * fill * delta)
	# Buoyancy against gravity, and nothing else pulls down in this branch: below
	# the float line the first term wins and the body rises, above it the second
	# does, and they cross with the head out.
	velocity += _up() * (_gravity() * (buoyancy * fill - 1.0) * delta)
	velocity *= exp(-water_drag * fill * delta)


# --- Stance -----------------------------------------------------------------

func _update_stance(delta: float, grounded: bool) -> void:
	_slide_ready_in = maxf(_slide_ready_in - delta, 0.0)
	var crouch_held := _steer_held(&"crouch")

	if _stance == Stance.SLIDE:
		_slide_time += delta
		var spent := _slide_time >= _slide_span or _horizontal_speed() <= slide_exit_speed
		if not grounded or not crouch_held or spent:
			_slide_ready_in = slide_cooldown
			# The run resumes from what the slide left, not from what it started
			# with, or the friction would cost nothing and every run would be
			# worth sliding indefinitely.
			_run_speed = clampf(_horizontal_speed(), walk_speed, run_top_speed)
			if crouch_held and grounded:
				_apply_stance(Stance.CROUCH)
			else:
				_try_stand()
		return

	if _steer_just(&"crouch"):
		if grounded and _slide_ready_in <= 0.0 and _horizontal_speed() >= slide_entry_speed:
			_start_slide()
		else:
			_apply_stance(Stance.CROUCH)
	elif not crouch_held and _stance == Stance.CROUCH:
		_try_stand()


func _start_slide() -> void:
	var flat := _flat(velocity)
	var direction := flat.normalized() if flat.length_squared() > 0.0001 else -global_basis.z
	var speed := maxf(flat.length() * 1.15, slide_speed)
	velocity = direction * speed + _up() * _rise()
	_slide_time = 0.0
	# A slide is as long as the run that earned it, so the duration is the dial
	# and the friction is solved to fit: bleed exactly this speed away over
	# exactly this time. Tuning the friction instead would leave the timer and
	# the speed floor cutting each other short at different speeds.
	_slide_span = slide_max_time + slide_time_gain * _run_amount()
	_slide_drag = maxf(slide_friction, (speed - slide_exit_speed) / _slide_span)
	_apply_stance(Stance.SLIDE)


## Stands up only when there is room, so crouching under something is not a way
## to clip through it.
func _try_stand() -> bool:
	ceiling_check.force_raycast_update()
	if ceiling_check.is_colliding():
		return false
	_apply_stance(Stance.STAND)
	return true


func _apply_stance(next: int) -> void:
	if next == Stance.FLY and not can_fly():
		next = Stance.STAND
	var entered_hero := next == Stance.HERO and _stance != Stance.HERO
	_stance = next
	var capsule := collider.shape as CapsuleShape3D
	var height := _stance_height(_stance)
	capsule.height = height
	capsule.radius = _base_capsule_radius * overdrive_size_scale()
	collider.position.y = height * 0.5
	# HERO is always an impact pose: steep flight and Meteor both enter it once.
	# Driving the pop from the transition makes remote players see it from the
	# replicated stance without adding a cosmetic network packet.
	if entered_hero and is_instance_valid(dust):
		dust.pop_ground(_dust_ground_point(), _up(), 2.0)


## Stance heights scale with the body's authored height so a 1.6 m settler does
## not crouch inside a 1.45 m capsule.
func _stance_height(stance: int) -> float:
	return COLLIDER_HEIGHTS[stance] * (_body_height / COLLIDER_HEIGHTS[Stance.STAND]) \
		* overdrive_size_scale()


func _stance_eye(stance: int) -> float:
	return EYE_HEIGHTS[stance] * (_body_eye / EYE_HEIGHTS[Stance.STAND]) \
		* overdrive_size_scale()


# --- Camera and presentation ------------------------------------------------

## The collider is lifted onto a step in one physics frame; the mesh and the eye
## line are left behind by that much and slid back up over `step_smooth_time`.
func _update_step_offset(delta: float) -> void:
	if absf(_step_offset) < 0.001:
		_step_offset = 0.0
	else:
		_step_offset *= exp(-delta / maxf(step_smooth_time, 0.001))


## Where the visible body sits and how far over it has gone. The collider never
## tips — a flying player is still a standing capsule — so the whole difference
## between hovering and flying flat out is drawn here and in the two clips.
##
## Runs for everyone, not just the local player: stance and velocity are both
## synced, so a remote player leans from the same two numbers.
func _update_body_lean(delta: float) -> void:
	if _stance == Stance.HERO:
		_fly_blend = 0.0
		_swim_blend = 0.0
		_swim_rush = 0.0
		_run_blend = 0.0
		character.rotation.x = 0.0
		character.position = Vector3(0.0, _visual_ground_offset(), 0.0)
		return
	if _stance == Stance.CRASH:
		if _ragdoll != null and _ragdoll.limp():
			# The bones are lying where they fell, in world space. Leaning the
			# node they hang off would move the whole ragdoll out from under
			# itself.
			_fly_blend = lerpf(_fly_blend, 0.0, 1.0 - exp(-delta * 8.0))
			_swim_blend = lerpf(_swim_blend, 0.0, 1.0 - exp(-delta * 8.0))
			_swim_rush = lerpf(_swim_rush, 0.0, 1.0 - exp(-delta * 8.0))
			_run_blend = 0.0
			character.rotation.x = 0.0
			character.position = Vector3(0.0, _visual_ground_offset(), 0.0)
			return
		_lay_out(delta)
		return
	var flying := _stance == Stance.FLY or _stance == Stance.METEOR
	var flat_out := 0.0
	# A flight leans over as it picks up speed; a punch is already flat out. The
	# fifty metres of a punch are gone in under a second, so the flight's own
	# easing would spend most of one standing the body up in mid-air.
	var lean_rate := 5.0
	if _stance == Stance.METEOR:
		flat_out = 1.0
		lean_rate = METEOR_LEAN_RATE
	elif flying:
		flat_out = _flight_pose_amount(velocity.length())
	_fly_blend = lerpf(_fly_blend, flat_out, 1.0 - exp(-delta * lean_rate))
	# Water is the same continuum an order of magnitude slower: treading upright
	# at a standstill, laid out along the stroke once the body is going anywhere.
	# It finishes well short of `swim_speed`, because a swimmer is flat by the
	# second stroke rather than at the top speed of the fastest one.
	var stroking := 0.0
	var rushing := 0.0
	if _stance == Stance.SWIM:
		stroking = clampf(
			inverse_lerp(swim_speed * 0.2, swim_speed * 0.75, velocity.length()), 0.0, 1.0)
		# Off the target the boost is winding toward rather than off the speed
		# reached, which is the same choice `_cruise` exists for: the wind-up is
		# already seconds long and smooth, and reading the velocity instead would
		# have the view breathe with every turn taken at speed.
		rushing = clampf(inverse_lerp(swim_speed, swim_sprint_speed, _stroke), 0.0, 1.0)
	_swim_blend = lerpf(_swim_blend, stroking, 1.0 - exp(-delta * 4.0))
	_swim_rush = lerpf(_swim_rush, rushing, 1.0 - exp(-delta * 4.0))
	_run_blend = lerpf(_run_blend, 0.0 if flying else _run_amount(), 1.0 - exp(-delta * 4.0))

	# Flat out and level, the body lies horizontal; pointed straight up it stands
	# upright again, and straight down it goes head first. Hovering it does none
	# of this, which is what the blend scales. Flight and swimming never overlap,
	# so the larger of the two is whichever one is happening — and taking the
	# larger rather than the sum is what carries the lean through a launch out of
	# the water instead of standing the body up for the frames both are moving.
	var fly_lean := -(PI * 0.5 - atan2(_rise(), _horizontal_speed())) \
		* maxf(_fly_blend, _swim_blend)
	var lean := fly_lean - SPRINT_LEAN * _run_blend
	character.rotation.x = lean
	# One rotation, so the pivot is shared: weighted towards the hips by however
	# much of the lean is the flight's, and towards the floor by however much of
	# it is the run's. They only overlap for the moment after a landing.
	var pivot := Vector3.ZERO
	if absf(lean) > 0.0001:
		pivot.y = _body_lean * fly_lean / lean
	character.position = Vector3(0.0, _visual_ground_offset(), 0.0) \
		+ pivot - Basis(Vector3.RIGHT, lean) * pivot


## The fallback crash, for a character whose .glb arrived without a skeleton the
## ragdoll could be built on. Everything with the stock character goes limp
## instead; see [Ragdoll].
##
## The tumble, and then the pick-up. While the body is still travelling it rolls
## with the ground going past it; once it stops it eases to the nearest whole
## half-turn, which is face down or face up rather than halfway onto its side.
## The last `CRASH_RISE` seconds unwind that back to upright, so standing up is
## the same motion played out instead of a snap.
##
## Turned about the hips like the flight lean, because a body rolling about its
## feet describes an arc a body length across and leaves the ground.
func _lay_out(delta: float) -> void:
	_fly_blend = lerpf(_fly_blend, 0.0, 1.0 - exp(-delta * 8.0))
	_swim_blend = lerpf(_swim_blend, 0.0, 1.0 - exp(-delta * 8.0))
	_swim_rush = lerpf(_swim_rush, 0.0, 1.0 - exp(-delta * 8.0))
	_run_blend = 0.0
	_tumble += _tumble_rate * delta
	_tumble_rate *= exp(-delta * TUMBLE_DECAY)
	# Once the roll has run out, settle onto the nearest whole half-turn, which is
	# face down or face up rather than stopped halfway onto one shoulder.
	if _tumble_rate < 1.0:
		_tumble = lerpf(_tumble, roundf(_tumble / PI) * PI, 1.0 - exp(-delta * 6.0))
	if _crash_left < CRASH_RISE:
		_tumble_rate = 0.0
		_tumble = lerpf(_tumble, 0.0, 1.0 - exp(-delta * 7.0))
	character.rotation.x = _tumble
	var pivot := Vector3(0.0, _body_lean, 0.0)
	character.position = Vector3(0.0, _visual_ground_offset(), 0.0) \
		+ pivot - Basis(Vector3.RIGHT, _tumble) * pivot


func _update_camera(delta: float) -> void:
	var hero_wanted := 1.0 if _stance == Stance.HERO else 0.0
	var hero_rate := HERO_CAMERA_IN_RATE if hero_wanted > _hero_camera_blend \
		else HERO_CAMERA_OUT_RATE
	_hero_camera_blend = lerpf(_hero_camera_blend, hero_wanted,
		1.0 - exp(-delta * hero_rate))
	# The rig normally chases its target hard enough to be invisible, which is
	# right when the target is barely moving. HeroLand moves it a long way — out
	# of first person and over a shoulder — so while that is happening the chase
	# is slowed to the blend's own rate and the two travel together.
	var weight := 1.0 - exp(-delta
		* lerpf(12.0, HERO_CAMERA_IN_RATE, maxf(_hero_camera_blend, hero_wanted)))

	# HeroLand borrows the close shoulder rig regardless of the selected camera.
	# The sign remains the selected shoulder, and because `_camera_mode` itself is
	# untouched this naturally eases back to first/near/far after the pose.
	var arm_target := lerpf(ARM_LENGTHS[_camera_mode],
		ARM_LENGTHS[CameraMode.THIRD_NEAR], _hero_camera_blend)
	var shoulder_target := lerpf(SHOULDER_OFFSETS[_camera_mode],
		SHOULDER_OFFSETS[CameraMode.THIRD_NEAR], _hero_camera_blend) * _shoulder
	camera_arm.spring_length = lerpf(camera_arm.spring_length, arm_target, weight)
	camera_arm.position.x = lerpf(camera_arm.position.x, shoulder_target, weight)
	var eye_target := lerpf(_stance_eye(_stance), HERO_CAMERA_EYE, _hero_camera_blend)
	_eye_height = lerpf(_eye_height, eye_target, weight)
	var eye_line := _eye_height + _step_offset
	head.position.y = eye_line + _walk_camera_offset
	head.rotation.x = lerp_angle(_pitch, 0.0, _hero_camera_blend)
	_pull_camera_out_of_the_ground()
	camera.fov = lerpf(
		_base_fov + SPEED_FOV_RUSH * maxf(maxf(_fly_blend, _run_blend), _swim_rush),
		_base_fov * AIM_FOV_SCALE, _aim_amount())

	# Own body is hidden while the camera sits inside its head. Hiding is a
	# visibility switch and not SHADOWS_ONLY, because SurfaceSkin has already put
	# every character mesh's shadow out and that setting would light one back up
	# for the one case that used to want it.
	var inside_head := peer_id == multiplayer.get_unique_id() and camera_arm.spring_length < 0.35
	# What is in the hands keeps being drawn where the body is not: it is held out in
	# front of the eyes, so hiding it with the body would leave first person with no
	# weapon at all. The exception is a weapon brought right up to the eye, which
	# from inside is a wall of polygons rather than a weapon.
	var hide_weapon := false
	if _held_mesh != null and inside_head:
		hide_weapon = _held_mesh.global_position.distance_to(camera.global_position) < 0.3
	for mesh_instance in _character_meshes:
		mesh_instance.visible = not (hide_weapon if mesh_instance == _held_mesh else inside_head)


## Counteracts only radial collider-height changes during an ordinary walk.
## Horizontal translation, animation and mouse look are never filtered. Reading
## the interpolated body transform is important: `global_position` is the newest
## physics pose, not the pose being drawn between the last two physics ticks.
func _update_walking_ground_offset(delta: float) -> void:
	var local_player := peer_id == multiplayer.get_unique_id()
	var walking_stance := _stance == Stance.STAND or _stance == Stance.CROUCH
	var walking_speed := _horizontal_speed() <= maxf(walk_speed, crouch_speed) \
		* WALK_CAMERA_SPEED_SHARE
	var planet := _planet_below()
	var can_smooth := local_player and controls_enabled and walking_stance \
		and walking_speed and _grounded() and planet != null
	if not can_smooth:
		_walk_camera_tracking = false
		_walk_camera_offset = lerpf(_walk_camera_offset, 0.0,
			1.0 - exp(-delta * WALK_CAMERA_RELEASE_RATE))
		return

	var rendered_body := get_global_transform_interpolated()
	var body_radius := planet.to_local(rendered_body.origin).length()
	if body_radius < 1.0:
		_walk_camera_tracking = false
		_walk_camera_offset = 0.0
		return
	if not _walk_camera_tracking:
		_walk_camera_radius = body_radius
		_walk_camera_tracking = true
	else:
		var rate := clampf(_horizontal_speed() / WALK_CAMERA_LAG_METRES,
			WALK_CAMERA_RATE_RANGE.x, WALK_CAMERA_RATE_RANGE.y)
		_walk_camera_radius = lerpf(_walk_camera_radius, body_radius,
			1.0 - exp(-delta * rate))
	_walk_camera_offset = _walk_camera_radius - body_radius


func _visual_ground_offset() -> float:
	return _step_offset + _walk_camera_offset


## The spring arm shortens against anything it can cast a sphere at, which covers
## props, players and any chunk of planet that has a collider. The planet is the
## one thing that regularly has none: a chunk is only given a body once it is near
## enough and finished building, and the third-person arm reaches four metres into
## ground that may be drawn and not yet solid. So the same height field that stops
## the body going through the world is asked about the camera as well, and the arm
## is halved until the eye is out in the air.
##
## Only ever shortens what the arm already worked out, so it cannot push the
## camera through something the cast did find.
func _pull_camera_out_of_the_ground() -> void:
	# First person has no arm to shorten, and the eye is inside a body that is
	# already kept out of the ground by the guard.
	if camera_arm.spring_length < 0.05:
		return
	var planet := _planet_below()
	if planet == null or planet.shape == null:
		return
	var origin := camera_arm.global_position
	var along := -camera_arm.global_basis.z
	var length := camera_arm.spring_length
	for step in 4:
		if length < 0.05:
			length = 0.0
			break
		var local := planet.to_local(origin + along * length)
		var out := local.normalized()
		var floor_radius := planet.shape.radius \
			+ planet.shape.elevation(out, planet.finest_spacing())
		if local.length() >= floor_radius + CAMERA_CLEARANCE:
			return
		length *= 0.5
	camera_arm.spring_length = length


func _prepare_animations() -> void:
	if animator == null:
		push_warning("player: %s has no AnimationPlayer; re-export the .glb with its clips"
			% character.name)
		return
	# glTF has no loop flag, so the cycles are marked here. Aliases let the
	# stance machine keep speaking Idle/Walk/Run on a Mixamo body. The
	# Animation resources are shared by every player, which is fine: this is
	# idempotent.
	CharacterRig.prepare(animator, CharacterDB.extra_animation_paths(_body_id))
	_play("Idle")


func _update_anim_picker(delta: float) -> void:
	if peer_id != multiplayer.get_unique_id():
		return
	if ChatHud != null and ChatHud.typing:
		_anim_hold = 0.0
		_close_anim_picker()
		return
	if _menu_open and _anim_picker == null:
		_anim_hold = 0.0
		return
	var holding := Input.is_physical_key_pressed(KEY_B)
	if holding:
		_anim_hold += delta
		if _anim_hold >= ANIM_PICKER_HOLD and _anim_picker == null:
			_open_anim_picker()
	else:
		_anim_hold = 0.0
		_close_anim_picker()


func _open_anim_picker() -> void:
	if _anim_picker != null or hud == null or animator == null:
		return
	CharacterRig.prepare(animator, CharacterDB.extra_animation_paths(_body_id))
	_anim_picker = AnimationPicker.new()
	_anim_picker.configure(animator.get_animation_list(), _anim_preview)
	_anim_picker.clip_chosen.connect(_on_anim_picked)
	hud.add_child(_anim_picker)
	Input.mouse_mode = Input.MOUSE_MODE_VISIBLE


func _close_anim_picker() -> void:
	if _anim_picker == null:
		return
	_anim_picker.queue_free()
	_anim_picker = null
	if not _menu_open:
		Input.mouse_mode = Input.MOUSE_MODE_CAPTURED


func _on_anim_picked(clip: String) -> void:
	_anim_preview = clip
	_clip = ""
	_play(clip)
	if _anim_picker != null:
		_anim_picker.set_current(clip)


func _play_safe_zone_dance() -> void:
	var clip := CharacterRig.random_dance_clip(animator)
	if clip.is_empty():
		return
	_on_anim_picked(clip)


func _play(clip: String, speed := 1.0, blend := CLIP_BLEND) -> void:
	if animator == null:
		return
	var actual := CharacterRig.resolve_clip(animator, clip)
	if clip != _clip and animator.has_animation(actual):
		var previous := _clip
		if speed < 0.0:
			animator.play_backwards(actual, blend)
		else:
			animator.play(actual, blend)
		if previous == "AirRun" and clip == "Run":
			animator.seek(animator.get_animation(actual).length * AIR_RUN_TO_RUN_PHASE, true)
		_clip = clip
	animator.speed_scale = absf(speed) if speed < 0.0 else speed


## Stands the shock off the fist while a punch is in the air, and lets it go
## when the punch ends.
##
## In the presentation pass rather than in [method _meteor_move], because
## [method _meteor_move] only runs on the machine throwing the punch and this
## has to be drawn on all of them. The stance is what replicates, so the stance
## is what it is driven from.
##
## Aimed along the velocity rather than along [member _meteor_along]: a remote
## peer is never told the direction a punch was thrown in, only where the body
## is and how fast it is going, and for the punch itself the two agree by
## construction. They part company once a ground charge runs out of reach and
## starts to fall, and there the velocity is the one that is right — the shock
## belongs in front of where the body is actually going.
func _update_meteor_shock() -> void:
	if _stance != Stance.METEOR:
		if is_instance_valid(_meteor_shock):
			_meteor_shock.stop()
		return
	var speed := velocity.length()
	var along := velocity / speed if speed > 0.01 else _meteor_along
	meteor_shock().aim(
		fist_point(), along, speed, CrawlerMulti.shots(_meteor_stats))


func _update_animation(delta: float) -> void:
	var airborne := not _grounded_for_display()
	var took_off := not _was_airborne and airborne
	var landed := _was_airborne and not airborne
	if airborne:
		_landing_speed = maxf(_landing_speed, maxf(-_rise(), 0.0))
	# Positive launch speed separates a jump (and an intentional flora bounce)
	# from simply walking off a ledge or spawning in the air.
	if took_off and _stance == Stance.STAND \
			and _rise() >= jump_velocity * 0.35 and is_instance_valid(dust):
		dust.pop_ground(_dust_ground_point(), _up(), 0.7)
	if landed:
		_land_left = LAND_TIME
		# A normal hop keeps its landing clean. The longer arc that earns
		# AirRun, or an unusually fast fall, gets the circular ground pop. HERO
		# is excluded because its stance transition has already made the larger
		# version above.
		var big_jump := _airborne_time >= AIR_RUN_DELAY \
			or _landing_speed >= jump_velocity * 0.85
		if big_jump and _stance != Stance.HERO and is_instance_valid(dust):
			var strength := clampf(maxf(
				_airborne_time / maxf(AIR_RUN_DELAY, 0.01),
				_landing_speed / maxf(jump_velocity, 0.01)), 1.0, 1.65)
			dust.pop_ground(_dust_ground_point(), _up(), strength)
		_landing_speed = 0.0
	_was_airborne = airborne
	if airborne and _stance == Stance.STAND:
		_airborne_time += delta
	else:
		_airborne_time = 0.0
	_land_left = maxf(_land_left - delta, 0.0)

	var speed := _horizontal_speed()
	if _arrival_left > 0.0 and not _arrival_clip.is_empty():
		_play(_arrival_clip, _arrival_speed, 0.0)
		return
	if not _anim_preview.is_empty():
		if speed > 0.35:
			_anim_preview = ""
			if _anim_picker != null:
				_anim_picker.set_current("")
		else:
			_play(_anim_preview)
			return
	if _stance == Stance.HERO:
		_play(_hero_clip)
	elif _stance == Stance.CRASH:
		# There is no crash clip. `Fall` is the loosest pose the character has and
		# the tumble is what sells it; `Land` is a knee bend, which read the right
		# way round is someone pushing themselves back up.
		_play("Land" if _crash_left < CRASH_RISE else "Fall")
	elif _stance == Stance.METEOR:
		var meteor_definition := ItemDB.ability_definition("meteor_punch")
		var meteor_clip := String(meteor_definition.animation) \
			if meteor_definition != null \
				and not meteor_definition.animation.is_empty() else "MeteorFly"
		_play(meteor_clip, 1.0, METEOR_CLIP_BLEND)
	elif _ability_clip_left > 0.0 and not _ability_clip.is_empty():
		_play(_ability_clip, 1.0, METEOR_CLIP_BLEND)
	elif _stance == Stance.FLY:
		# The two ends of one continuum, crossfaded at the point the body is about
		# halfway over: the lean is doing most of the work either side of it.
		_play("Fly" if _fly_blend > 0.45 else "Float")
	elif _stance == Stance.SWIM:
		# The same two ends as flight, at a tenth of the speed: sculling upright,
		# or laid out along a crawl. The stroke is resampled the way a stride is,
		# so a drift reads as a drift rather than as a sprint through treacle.
		if _swim_blend > 0.45:
			_play("Swim", clampf(velocity.length() / swim_speed, 0.6, 1.5))
		else:
			_play("Tread")
	elif _stance == Stance.SLIDE:
		_play("Slide")
	elif airborne:
		if _airborne_time >= AIR_RUN_DELAY:
			_play("AirRun", 1.0, AIR_RUN_BLEND)
		else:
			_play("JumpRise" if _rise() > 0.6 else "Fall")
	elif _land_left > 0.0 and speed < walk_speed * 0.6:
		# Skipped when you land already running, where a knee-bend would read as
		# a stumble rather than as absorbing the drop.
		_play("Land")
	elif _stance == Stance.CROUCH:
		if speed > 0.4:
			_play("CrouchWalk", clampf(speed / crouch_speed, 0.6, 1.6))
		else:
			_play("CrouchIdle")
	elif speed > 0.4:
		# Stride length is baked in, so the clip is resampled to the real speed
		# instead of letting the feet skate.
		# Shift starts the sprint at `sprint_speed`, but does not change the pose.
		# The ordinary arms-swinging stride keeps accelerating through 18 m/s;
		# only a run wound beyond `arms_back_speed` earns the both-arms-back
		# flat-out posture.
		var arms_back_at := maxf(arms_back_speed, sprint_speed)
		if speed > arms_back_at:
			# The clip stops reading as a stride somewhere past twice its own
			# speed, so the ceiling is low and the forward lean takes over from
			# there. Resampling all the way to 200 m/s would be a blur.
			_play("Run", clampf(speed / arms_back_at, 0.7, 1.9))
		else:
			# Ceiling taken from the two speeds rather than written down, because
			# the arms-swinging stride has to hold out through the normal sprint
			# and a fixed one would quietly start dragging the feet if either
			# threshold is retuned.
			_play("Walk", clampf(speed / walk_speed, 0.6,
				maxf(1.5, arms_back_at / maxf(walk_speed, 0.01))))
	else:
		_play("Idle")


## Keeps the two emitters on the animated feet, but leaves every puff behind in
## world space. Velocity rather than the sprint key is the public fact here:
## remote peers do not know our input and a locally released sprint is still a
## sprint until its earned momentum has actually been spent.
func _update_dust_trails() -> void:
	if not is_instance_valid(dust):
		return
	var speed := _horizontal_speed()
	var sprinting := _stance == Stance.STAND and _grounded_for_display() \
		and speed >= sprint_speed * 0.95
	dust.update_trails(character, _up(), _flat(velocity), speed, sprinting)


## Ground directly under the feet. A physics face wins so a jump from a roof
## pops on the roof; the height field is the fallback that keeps the effect on
## terrain whose nearby chunk collider has not finished streaming yet.
func _dust_ground_point() -> Vector3:
	var up := _up()
	if is_inside_tree():
		var query := PhysicsRayQueryParameters3D.create(
			global_position + up * 0.45, global_position - up * 2.5)
		query.exclude = DamageHit.rid_list(get_rid())
		query.collision_mask = collision_mask
		query.collide_with_areas = false
		var hit := get_world_3d().direct_space_state.intersect_ray(query)
		if hit.has("position"):
			return hit["position"] as Vector3
	var planet := _planet_below()
	if planet == null or planet.shape == null:
		return global_position
	var local := planet.to_local(global_position)
	if local.length_squared() < 1.0:
		return global_position
	var out := local.normalized()
	var radius := planet.shape.radius \
		+ planet.shape.elevation(out, planet.spacing_underfoot())
	return planet.to_global(out * radius)


## Remote players are interpolated rather than simulated, so is_on_floor() never
## fires for them. A velocity-only guess calls the apex of every jump a landing;
## that used to be merely the wrong clip for a few frames, but with take-off dust
## it would also throw a second ring in mid-air. Ask collision first for roofs and
## streamed terrain, then the height field for planet ground whose collider has
## not arrived yet.
func _grounded_for_display() -> bool:
	if peer_id == multiplayer.get_unique_id():
		return _grounded()
	if test_move(global_transform, -_up() * FOOT_REACH):
		return true
	var planet := _planet_below()
	if planet != null and planet.shape != null:
		var local := planet.to_local(global_position)
		var span := local.length()
		if span >= 1.0:
			var out := local / span
			var ground := planet.shape.radius \
				+ planet.shape.elevation(out, planet.spacing_underfoot())
			return absf(span - ground) <= FOOT_REACH
	# Scene tests without a planet retain the old conservative inference.
	return absf(_rise()) < 1.5


func _update_hud(delta: float) -> void:
	# Sighted down the optic the crosshair draws in, which is most of what says the
	# shot has settled.
	reticle.set_spread(_horizontal_speed() / sprint_speed * (1.0 - 0.7 * _aim_amount()))
	if _coordinates != null and _coordinates.visible:
		_coordinates.set_motion_info(
			_hud_motion_state(),
			_hud_pov(),
			velocity.length() if _stance == Stance.FLY else _horizontal_speed()
		)
		_coordinates.refresh(global_position, _planet_below(), delta)
	if _minimap != null:
		var look := -global_transform.basis.z
		if camera != null:
			look = -camera.global_transform.basis.z
		_minimap.refresh(
			global_position,
			look,
			_planet_below(),
			_coordinates_wanted and not _menu_open
		)
	if _combat_hud != null:
		_combat_hud.refresh(delta)
	if CrawlerRules.active() and not training_enemy and not _dead:
		CrawlerSites.poll(self)
		if in_crawler_city() and journal != null:
			journal.note_city()
	if _weapon_bar != null:
		var cell := ItemDB.cell_size(_held)
		_weapon_bar.show_cell("cell  %d / %d" % [_charge(), cell] if cell > 0 else "")
	if not _menu_open and not _cutscene_hud:
		tick_revive_hold(delta, Input.is_action_pressed("interact"))
		var downed := nearest_downed_teammate()
		var target := _interact_target()
		if downed != null:
			prompt_plate.visible = true
			if _revive_elapsed > 0.0:
				interact_prompt.text = "Hold E    Revive    %d%%" % int(round(
					revive_hold_progress() * 100.0))
			else:
				interact_prompt.text = "Hold E    Revive"
		elif target != null:
			prompt_plate.visible = true
			interact_prompt.text = "E    %s" % target.call("interact_prompt")
		else:
			var overlay := _find_land_patches()
			var patch_id := _aimed_patch_id()
			if overlay != null and patch_id >= 0 \
					and patch_id < overlay.partition.patches.size() \
					and not CrawlerRules.active():
				var patch := overlay.partition.patches[patch_id]
				prompt_plate.visible = true
				interact_prompt.text = "E    Generate %s    L    Yards" % patch.name
				if overlay.has_baked_city(patch_id):
					interact_prompt.text += "    J    Place baked"
				interact_prompt.text += "    K    Place all    T    Enemy creator"
			elif CrawlerRules.training_active():
				prompt_plate.visible = true
				interact_prompt.text = "E    Training"
			elif CrawlerRules.duel_active():
				prompt_plate.visible = true
				interact_prompt.text = "E    End Duel"
			elif _waypoints_wanted and not CrawlerRules.active():
				prompt_plate.visible = true
				interact_prompt.text = "K    Place all baked    T    Enemy creator"
			else:
				prompt_plate.visible = false


func _hud_motion_state() -> String:
	match _stance:
		Stance.FLY:
			return "flying" if _fly_blend > 0.45 else "floating"
		Stance.CROUCH:
			return "crouched"
		Stance.SLIDE:
			return "sliding"
		Stance.SWIM:
			return "swimming"
		Stance.HERO:
			return "hero landing"
		Stance.METEOR:
			return "meteor punch"
		Stance.GRAPPLE:
			return "grappling"
		Stance.CRASH:
			return "crashed"
	if _horizontal_speed() > sprint_speed:
		return "running"
	if _horizontal_speed() > 0.2:
		return "walking"
	return "standing"


func _hud_pov() -> String:
	match _camera_mode:
		CameraMode.THIRD_NEAR:
			return "third close, %s" % (
				"left shoulder" if _shoulder < 0.0 else "right shoulder"
			)
		CameraMode.THIRD_FAR:
			return "third far, %s" % (
				"left shoulder" if _shoulder < 0.0 else "right shoulder"
			)
	return "first person"


func _update_target_label() -> void:
	aim_ray.force_raycast_update()
	target_name.text = ""
	if aim_ray.is_colliding():
		var collider_hit := aim_ray.get_collider()
		if collider_hit is OnlinePlayer and collider_hit != self:
			target_name.text = (collider_hit as OnlinePlayer).display_name
	target_plate.visible = not target_name.text.is_empty()


# --- Networking -------------------------------------------------------------

## The fastest a player in `stance` could honestly be travelling. A swim may have
## just inherited a flight and is allowed that decaying entry speed; claiming Fly
## already grants the still-higher ceiling, so this does not widen what a client
## could lie about.
func _speed_limit(stance: int) -> float:
	if stance == Stance.FLY:
		return fly_speed * 1.2
	if stance == Stance.SWIM:
		return maxf(swim_sprint_speed, fly_speed * swim_entry_keep) * 1.2
	if stance == Stance.GRAPPLE:
		return 70.0
	# A slide leaves the ground run at 1.15 times what it entered on.
	return run_top_speed * 1.25


## Clients submit predicted movement. The server rejects wrong senders and
## implausible single-packet teleports, then relays accepted state to everyone.
@rpc("any_peer", "unreliable_ordered")
func _submit_state(next_transform: Transform3D, next_velocity: Vector3, look_pitch: float, stance: int) -> void:
	if not multiplayer.is_server():
		return
	var sender := multiplayer.get_remote_sender_id()
	if sender != peer_id:
		return
	var next_stance := clampi(stance, 0, Stance.size() - 1)
	if _dead or _grabbed or _lassoed or _stagger_left > 0.0 \
			or _forced_ragdoll \
			or (next_stance == Stance.FLY
				and statuses.has(CombatStatuses.FLIGHTLESS)):
		_apply_state.rpc_id(sender, global_transform, velocity, _pitch, _stance)
		return
	var limit := _speed_limit(next_stance)
	# What counts as a teleport depends on what the sender claims to be doing: a
	# flying player covers ten metres between packets, so a fixed few metres would
	# reject every honest one of them.
	var step := maxf(MAX_ACCEPTED_STEP, limit * SYNC_INTERVAL * 3.0)
	if _host_has_state and next_transform.origin.distance_to(_host_last_position) > step:
		_apply_state.rpc_id(sender, global_transform, velocity, _pitch, _stance)
		return
	_host_has_state = true
	_host_last_position = next_transform.origin
	global_transform = next_transform
	# Split against the sender's own up, which on a sphere is wherever they are
	# standing. Clamping the world's Y here would call a run across the equator a
	# vertical one.
	var up := next_transform.basis.y.normalized()
	var climb := next_velocity.dot(up)
	var flat := (next_velocity - up * climb).limit_length(limit)
	# The fastest anything can honestly leave the ground is a flat-out leap, so
	# the ceiling is written from the two numbers that decide one rather than as
	# a multiple of the standing jump — which a run already beats on its own, and
	# which therefore used to clamp every sprint jump anyone else made.
	var rise := maxf(jump_velocity * (1.0 + jump_speed_gain) * 1.2, limit)
	velocity = flat + up * clampf(climb, -maxf(80.0, limit), rise)
	_pitch = clampf(look_pitch, -1.48, 1.48)
	head.rotation.x = _pitch
	_apply_stance(next_stance)
	_target_transform = global_transform
	_apply_state.rpc(global_transform, velocity, _pitch, _stance)


## A player owns their own look: everyone else applies what they are told, and the
## host relays it on to peers that cannot hear the sender directly.
@rpc("any_peer", "call_remote", "reliable")
func _wear(worn: PackedStringArray) -> void:
	if multiplayer.get_remote_sender_id() != peer_id:
		return
	apply_worn(worn)


## Only what is in the hands is broadcast, not the whole rack: the rack is private
## and nobody else can see it.
@rpc("any_peer", "call_remote", "reliable")
func _hold(id: String) -> void:
	if multiplayer.get_remote_sender_id() != peer_id:
		return
	apply_held(id)


## Swings and shots are sent rather than derived from state, because both are
## instants: a peer that missed the packet should miss the swing, not play it late.
## `call_local` means the shooter takes the same path as everyone else.
@rpc("any_peer", "call_local", "reliable")
func _swing_weapon() -> void:
	if not _sender_owns_this_player() or not can_attack():
		return
	if _weapon_pose != null:
		_weapon_pose.swing()


@rpc("any_peer", "call_local", "reliable")
func _fire_bolt(from: Vector3, along: Vector3) -> void:
	if not _sender_owns_this_player() or not can_attack():
		return
	LaserBolt.fire(get_parent(), from, along, self)


@rpc("any_peer", "call_remote", "reliable")
func _request_ability_beam(request_sequence: int, id: String,
		left_eye: Vector3, right_eye: Vector3, at: Vector3,
		landed: bool, radius := -1.0, beam_width := 1.0, wobble := 0.0,
		pulse := false) -> void:
	if not multiplayer.is_server():
		return
	var sender := multiplayer.get_remote_sender_id()
	if sender != peer_id or request_sequence <= _last_beam_request_sequence:
		return
	_last_beam_request_sequence = request_sequence
	if not can_attack():
		return
	_publish_ability_beam(
		id, left_eye, right_eye, at, landed, radius, beam_width, wobble, pulse)


## One host-approved tick of a sustained beam. Every peer applies its flora;
## only the host dispatches the generated player-faction hit to combatants.
@rpc("authority", "call_local", "reliable")
func _apply_ability_beam(event_sequence: int, id: String,
		left_eye: Vector3, right_eye: Vector3, at: Vector3,
		landed: bool, radius := -1.0, beam_width := 1.0, wobble := 0.0,
		pulse := false) -> void:
	if event_sequence <= _last_beam_sequence:
		return
	_last_beam_sequence = event_sequence
	if not _is_replicated_beam(id) or not ItemDB.accepts_ability(id) \
			or not left_eye.is_finite() \
			or not right_eye.is_finite() or not at.is_finite():
		return
	if id == "lightning":
		Lightning.apply_effect(
			self, id, left_eye, right_eye, at, landed, radius, beam_width,
			wobble, pulse)
	else:
		LaserEyes.apply_effect(
			self, id, left_eye, right_eye, at, landed, radius, beam_width,
			wobble, pulse)


@rpc("any_peer", "call_remote", "reliable")
func _request_ability_projectile(request_sequence: int, id: String,
		from: Vector3, along: Vector3, inherited_velocity: Vector3,
		variant: int, overlay: Dictionary = {}) -> void:
	if not multiplayer.is_server():
		return
	var sender := multiplayer.get_remote_sender_id()
	if sender != peer_id \
			or request_sequence <= _last_projectile_request_sequence:
		return
	_last_projectile_request_sequence = request_sequence
	if not _publish_ability_projectile(
			request_sequence, id, from, along, inherited_velocity, variant,
			overlay):
		_reject_ability_projectile.rpc_id(sender, request_sequence)


@rpc("authority", "call_remote", "reliable")
func _reject_ability_projectile(request_sequence: int) -> void:
	if request_sequence == _projectile_result_sequence:
		_projectile_result = ProjectileRequestState.REJECTED


@rpc("authority", "call_local", "reliable")
func _apply_ability_projectile(event_sequence: int, request_sequence: int,
		id: String, from: Vector3, along: Vector3,
		inherited_velocity: Vector3, variant: int,
		overlay: Dictionary = {}) -> void:
	if event_sequence <= _last_projectile_sequence:
		return
	_last_projectile_sequence = event_sequence
	var definition := ItemDB.ability_definition(id)
	if definition == null \
			or definition.projectile_type == AbilityDefinition.ProjectileType.NONE \
			or not from.is_finite() or not along.is_finite() \
			or not inherited_velocity.is_finite() \
			or along.length_squared() < 0.001:
		return
	if not overlay.is_empty():
		note_crawler_cast(overlay)
	var spawned := _spawn_ability_projectile(
		id, from, along.normalized(), inherited_velocity, clampi(variant, 0, 3),
		overlay)
	if peer_id == multiplayer.get_unique_id() \
			and request_sequence == _projectile_result_sequence:
		_projectile_result = ProjectileRequestState.ACCEPTED \
			if spawned else ProjectileRequestState.REJECTED


@rpc("authority", "call_local", "reliable")
func _apply_hat_missiles(
		from: Vector3, toward: Vector3, count: int, damage: float,
		reach: float
	) -> void:
	if not from.is_finite() or not toward.is_finite() \
			or toward.length_squared() < 0.0001 \
			or count <= 0 or damage <= 0.0 or reach <= 0.0:
		return
	_spawn_hat_missiles(
		from, toward, clampi(count, 1, 24), damage, reach)


@rpc("authority", "call_local", "reliable")
func _apply_hat_mine(at: Vector3, damage: float, reach: float) -> void:
	if not at.is_finite() or damage <= 0.0 or reach <= 0.0:
		return
	_spawn_hat_mine(at, damage, reach)


@rpc("any_peer", "call_remote", "reliable")
func _request_ability_field(request_sequence: int, id: String) -> void:
	if not multiplayer.is_server():
		return
	var sender := multiplayer.get_remote_sender_id()
	if sender != peer_id \
			or request_sequence <= _last_ability_field_request_sequence:
		return
	_last_ability_field_request_sequence = request_sequence
	_publish_ability_field(id)


@rpc("authority", "call_local", "reliable")
func _apply_ability_field(event_sequence: int, id: String, at: Vector3,
		stats: Dictionary) -> void:
	if event_sequence <= _last_ability_field_sequence or not at.is_finite() \
			or not CrawlerRules.is_field_ability(id):
		return
	var definition := ItemDB.ability_definition(id)
	if definition == null:
		return
	_last_ability_field_sequence = event_sequence
	var world: Node = DamageHit.game_world_of(self)
	if world == null:
		world = get_parent()
	if world == null:
		return
	var owns := not multiplayer.has_multiplayer_peer() or multiplayer.is_server()
	CrawlerFieldVolume.create(
		world, self, id, at, stats, definition.tint, owns)
	if not field_casting():
		play_ability_animation(
			definition.animation,
			float(stats.get("animation_duration", CrawlerRules.FIELD_ANIMATION)))


@rpc("any_peer", "call_remote", "reliable")
func _request_ability_wall(request_sequence: int, id: String) -> void:
	if not multiplayer.is_server():
		return
	var sender := multiplayer.get_remote_sender_id()
	if sender != peer_id \
			or request_sequence <= _last_ability_wall_request_sequence:
		return
	_last_ability_wall_request_sequence = request_sequence
	if not _publish_ability_wall(request_sequence, id):
		_reject_ability_wall.rpc_id(sender, request_sequence)


@rpc("authority", "call_remote", "reliable")
func _reject_ability_wall(request_sequence: int) -> void:
	if request_sequence == _ability_wall_result_sequence:
		_ability_wall_result = ProjectileRequestState.REJECTED


@rpc("authority", "call_local", "reliable")
func _apply_ability_wall(event_sequence: int, request_sequence: int,
		construct_id: int, id: String, at: Transform3D, size: Vector3,
		duration: float, fade_duration: float, tint: Color,
		variant: int, extras: Dictionary = {}) -> void:
	if event_sequence <= _last_ability_wall_sequence or construct_id <= 0 \
			or not at.is_finite() or not size.is_finite() \
			or not is_finite(duration) or not is_finite(fade_duration):
		return
	var definition := ItemDB.ability_definition(id)
	if definition == null or definition.construct_type \
			!= AbilityDefinition.ConstructType.BARRIER:
		return
	_last_ability_wall_sequence = event_sequence
	var world := DamageHit.game_world_of(self) as GameWorld
	if world == null:
		return
	world.spawn_ability_barrier_local(
		construct_id, peer_id, at, size,
		clampf(duration, 0.2, 30.0),
		clampf(fade_duration, 0.0, clampf(duration, 0.2, 30.0)), tint,
		0.52, extras)
	if bool(extras.get("house", false)) \
			and float(extras.get("project_speed", 0.0)) > 0.001:
		var along: Variant = extras.get("project_along", Vector3.ZERO)
		if along is Vector3 and (along as Vector3).is_finite():
			apply_construct_carry(
				(along as Vector3).normalized()
				* float(extras.get("project_speed", 0.0)))
	var clip := definition.hover_animation \
		if (variant & 2) != 0 and not definition.hover_animation.is_empty() \
		else definition.animation
	play_ability_animation(
		clip, float(definition.stats.get("animation_duration", 0.45)))
	if peer_id == multiplayer.get_unique_id() \
			and request_sequence == _ability_wall_result_sequence:
		_ability_wall_result = ProjectileRequestState.ACCEPTED


@rpc("any_peer", "call_remote", "reliable")
func _request_hero_punch(id: String, variant: int) -> void:
	if not multiplayer.is_server():
		return
	var sender := multiplayer.get_remote_sender_id()
	if sender != peer_id:
		return
	_publish_hero_punch(id, variant, crawler_ability_overlay(id))


@rpc("authority", "call_local", "reliable")
func _apply_hero_punch(event_sequence: int, id: String, variant: int,
		overlay: Dictionary = {}) -> void:
	if event_sequence <= _last_hero_punch_sequence:
		return
	var definition := ItemDB.ability_definition(id)
	if definition == null:
		return
	_last_hero_punch_sequence = event_sequence
	var from_left := (variant & 1) != 0
	var from_hover := (variant & 2) != 0
	var clip := definition.animation
	if from_hover and from_left \
			and not definition.alternate_hover_animation.is_empty():
		clip = definition.alternate_hover_animation
	elif from_hover and not definition.hover_animation.is_empty():
		clip = definition.hover_animation
	elif from_left and not definition.alternate_animation.is_empty():
		clip = definition.alternate_animation
	play_ability_animation(clip,
		float(overlay.get("animation_duration",
			definition.stats.get("animation_duration", 0.32))))
	if not _is_host_authority():
		return
	var stats := definition.stats.duplicate(true)
	stats.merge(overlay, true)
	var from := hand_point(from_left)
	var along := aim_direction(from)
	if along.length_squared() < 0.001:
		along = -global_basis.z
	along = along.normalized()
	var reach := maxf(float(stats.get("range", 3.5)), 0.5) * crawler_range_scale()
	var radius := maxf(float(stats.get("radius", 1.15)), 0.2)
	var damage := maxf(float(stats.get("damage", 0.0)), 0.0)
	if CrawlerRules.active():
		damage = CrawlerRules.paired_hit_damage(self, damage)
	var knockback := maxf(float(stats.get("knockback", 0.0)), 0.0)
	if CrawlerRules.active():
		knockback *= crawler_knockback_scale()
	var prey := CrawlerHoming.lock(self, from, along, stats)
	if prey != null:
		along = CrawlerHoming.aim(from, along, stats, self)
	var at := from + along * minf(reach, maxf(radius + 0.35, 0.8))
	if prey != null:
		var dest := CrawlerHoming.combat_at(prey)
		if from.distance_to(dest) <= reach + radius:
			at = dest
	for slide: float in CrawlerMulti.punch_offsets(CrawlerMulti.shots(stats)):
		var hit := DamageHit.impact(at + along * slide, radius, damage)
		hit.ability_id = id
		if knockback > 0.0:
			hit.world_impulse = along * knockback
		CrawlerElements.stamp(hit, self, id, stats)
		deal_damage(hit)
	CrawlerBubbles.emit_blast(self, id, at, maxf(radius, 0.8))
	CrawlerLingers.emit_blast(self, id, at, maxf(radius, 0.8))


@rpc("any_peer", "call_remote", "reliable")
func _request_ability_delayed_blast(request_sequence: int, id: String,
		from: Vector3, along: Vector3) -> void:
	if not multiplayer.is_server():
		return
	var sender := multiplayer.get_remote_sender_id()
	if sender != peer_id \
			or request_sequence <= _last_delayed_blast_request_sequence:
		return
	_last_delayed_blast_request_sequence = request_sequence
	if not _publish_ability_delayed_blast(
			request_sequence, id, from, along):
		_reject_ability_delayed_blast.rpc_id(sender, request_sequence)


@rpc("authority", "call_remote", "reliable")
func _reject_ability_delayed_blast(request_sequence: int) -> void:
	if request_sequence == _delayed_blast_result_sequence:
		_delayed_blast_result = ProjectileRequestState.REJECTED


func publish_impact_cast(guest_id: String, from: Vector3, along: Vector3,
		overlay: Dictionary = {}) -> void:
	if not _is_host_authority():
		return
	if guest_id.is_empty() or not from.is_finite() or not along.is_finite() \
			or along.length_squared() < 0.000001:
		return
	_host_impact_cast_sequence += 1
	if _has_listeners():
		_apply_impact_cast.rpc(
			_host_impact_cast_sequence, guest_id, from, along, overlay)
	else:
		_apply_impact_cast(
			_host_impact_cast_sequence, guest_id, from, along, overlay)


@rpc("authority", "call_local", "reliable")
func _apply_impact_cast(event_sequence: int, guest_id: String,
		from: Vector3, along: Vector3, overlay: Dictionary = {}) -> void:
	if event_sequence <= _last_impact_cast_sequence \
			or not from.is_finite() or not along.is_finite() \
			or along.length_squared() < 0.000001:
		return
	_last_impact_cast_sequence = event_sequence
	CrawlerImpactCast.play(self, guest_id, from, along, overlay)


func _delayed_blast_follow_path(follow: Node) -> String:
	if follow == null or not is_instance_valid(follow) \
			or not follow.is_inside_tree():
		return ""
	var world := DamageHit.game_world_of(self)
	if world == null:
		return ""
	var path := world.get_path_to(follow)
	if path.is_empty() or path.is_absolute():
		return ""
	for index in path.get_name_count():
		if path.get_name(index) == &"..":
			return ""
	return String(path)


@rpc("authority", "call_local", "reliable")
func _apply_ability_delayed_blast(event_sequence: int,
		request_sequence: int, id: String, from: Vector3,
		at: Vector3, normal: Vector3, warning: float,
		variant: int, overlay: Dictionary = {},
		follow_path: String = "") -> void:
	if event_sequence <= _last_delayed_blast_sequence \
			or not from.is_finite() or not at.is_finite() \
			or not normal.is_finite() or not is_finite(warning):
		return
	var definition := ItemDB.ability_definition(id)
	if definition == null or definition.impact_type \
			!= AbilityDefinition.ImpactType.DELAYED_BLAST:
		return
	_last_delayed_blast_sequence = event_sequence
	var world := DamageHit.game_world_of(self)
	if world == null:
		return
	var eyes := eye_points()
	var mid: Vector3 = (eyes[0] + eyes[1]) * 0.5
	var along := at - mid
	eyes = CrawlerReach.shift_pair(eyes[0], eyes[1], along, overlay)
	var width := maxf(float(overlay.get("beam_width", 1.0)), 0.35)
	var wobble := maxf(float(overlay.get("wobble", 0.0)), 0.0)
	var tint := EnergyVfx.TINT_PURPLE if id == "nausicaa" else definition.tint
	laser_beams().aim(
		eyes[0], eyes[1], at, tint, width, wobble,
		LaserBeams.FOLLOW_EYES, CrawlerReach.far_cast(overlay),
		id == "kame")
	AbilityDelayedBlast.create(
		world, self, definition, from, at, normal,
		clampf(warning, 0.1, 5.0), _is_host_authority(), overlay,
		_grapple_target_from_path(follow_path))
	var clip := definition.hover_animation \
		if (variant & 2) != 0 and not definition.hover_animation.is_empty() \
		else definition.animation
	play_ability_animation(
		clip, float(definition.stats.get("animation_duration", 0.4)))
	if peer_id == multiplayer.get_unique_id() \
			and request_sequence == _delayed_blast_result_sequence:
		_delayed_blast_result = ProjectileRequestState.ACCEPTED


## Backward-compatible local helper retained for older harnesses.
func _ability_beam(id: String, left_eye: Vector3, right_eye: Vector3,
		at: Vector3, landed: bool) -> void:
	if not can_attack():
		return
	LaserEyes.apply_effect(self, id, left_eye, right_eye, at, landed)


@rpc("any_peer", "call_local", "reliable")
func _meteor_impact_cloud(at: Vector3, facing: Vector3,
		radius: float, strength: float) -> void:
	if not _sender_owns_this_player() or not is_instance_valid(dust):
		return
	if not at.is_finite() or not facing.is_finite():
		return
	dust.impact_cloud(at, facing, radius, strength)


@rpc("any_peer", "call_remote", "reliable")
func _request_ability_explosion(request_sequence: int, at: Vector3,
		radius: float, tint: Color, duration: float, massive: bool,
		nuclear: bool) -> void:
	if not multiplayer.is_server():
		return
	var sender := multiplayer.get_remote_sender_id()
	if sender != peer_id \
			or request_sequence <= _last_ability_explosion_request_sequence:
		return
	_last_ability_explosion_request_sequence = request_sequence
	_publish_ability_explosion(
		at, radius, tint, duration, massive, nuclear, true)


@rpc("authority", "call_local", "reliable")
func _apply_ability_explosion(event_sequence: int, at: Vector3,
		radius: float, tint: Color, duration: float, massive: bool,
		nuclear: bool, predicted_owner: bool) -> void:
	if event_sequence <= _last_ability_explosion_sequence \
			or not at.is_finite() or not is_finite(radius) \
			or not is_finite(duration):
		return
	_last_ability_explosion_sequence = event_sequence
	if predicted_owner and not multiplayer.is_server() \
			and peer_id == multiplayer.get_unique_id():
		return
	_spawn_ability_explosion(at, radius, tint, duration, massive, nuclear)


@rpc("any_peer", "call_remote", "reliable")
func _request_hero_combat_hit(request_sequence: int,
		wire: Dictionary) -> void:
	if not multiplayer.is_server():
		return
	var sender := multiplayer.get_remote_sender_id()
	if sender != peer_id or request_sequence <= _last_combat_request_sequence:
		return
	_last_combat_request_sequence = request_sequence
	if not can_attack():
		return
	_publish_hero_combat_hit(
		DamageHit.sanitize_player_packet(wire, sender, self))


@rpc("authority", "call_local", "reliable")
func _apply_hero_combat_hit(event_sequence: int,
		wire: Dictionary) -> void:
	if event_sequence <= _last_combat_event_sequence:
		return
	_last_combat_event_sequence = event_sequence
	var hit := DamageHit.from_wire(wire)
	if hit.faction != DamageHit.Faction.PLAYER \
			or hit.source_peer != peer_id:
		return
	DamageHit.apply_to_world(self, hit)


## Backward-compatible local entry; unlike the old RPC it still passes through
## the player-packet sanitizer.
func _ability_damage(wire: Dictionary) -> void:
	if not can_attack():
		return
	var hit := DamageHit.sanitize_player_packet(wire, peer_id, self)
	DamageHit.apply_to_world(self, hit)


@rpc("any_peer", "call_remote", "reliable")
func _request_parry(request_sequence: int) -> void:
	if not multiplayer.is_server():
		return
	_server_accept_parry(
		request_sequence, multiplayer.get_remote_sender_id())


@rpc("authority", "call_local", "reliable")
func _apply_parry_state(event_sequence: int, window: float,
		perfect: float, cooldown: float) -> void:
	if event_sequence <= _last_parry_event_sequence:
		return
	_last_parry_event_sequence = event_sequence
	if not can_attack():
		return
	_parry_window_left = clampf(window, 0.0, 1.0)
	_parry_perfect_left = clampf(perfect, 0.0, _parry_window_left)
	_parry_cooldown_left = clampf(cooldown, _parry_window_left, 5.0)
	parry_started.emit()


@rpc("any_peer", "call_remote", "reliable")
func _request_cape_ability(request_sequence: int) -> void:
	if not multiplayer.is_server():
		return
	_server_accept_cape_ability(
		request_sequence, multiplayer.get_remote_sender_id())


@rpc("authority", "call_local", "reliable")
func _apply_cape_ability_state(
		event_sequence: int, duration: float, cooldown: float
	) -> void:
	if event_sequence <= _last_gold_cape_event_sequence:
		return
	_last_gold_cape_event_sequence = event_sequence
	_gold_cape_left = maxf(duration, 0.01)
	_gold_cape_cooldown_left = maxf(cooldown, _gold_cape_left)
	_gold_cape_sparkle_acc = 0.0
	_sync_gold_cape_visual()


@rpc("any_peer", "call_remote", "reliable")
func _request_juke(request_sequence: int, along: Vector3) -> void:
	if not multiplayer.is_server():
		return
	_server_accept_juke(
		request_sequence, multiplayer.get_remote_sender_id(), along)


@rpc("authority", "call_local", "reliable")
func _apply_juke_state(event_sequence: int, along: Vector3,
		duration: float, cooldown: float, carry := Vector3.ZERO) -> void:
	if event_sequence <= _last_juke_event_sequence:
		return
	_last_juke_event_sequence = event_sequence
	if not can_juke() and _juke_left <= 0.0:
		return
	if not along.is_finite() or along.length_squared() < 0.0001:
		return
	_juke_along = along.normalized()
	_juke_carry = carry if carry.is_finite() else Vector3.ZERO
	_juke_left = clampf(duration, 0.01, 1.0)
	_juke_cooldown_left = maxf(cooldown, _juke_left)
	_juke_ghost_acc = 0.0
	_juke_struck.clear()
	_spawn_juke_afterimage()


@rpc("authority", "call_local", "reliable")
func _apply_combat_state(event_sequence: int, snapshot: Dictionary,
		effect: Dictionary) -> void:
	if event_sequence <= _last_combat_state_sequence:
		return
	_last_combat_state_sequence = event_sequence
	# The host already mutated canonical HP/status state before publishing this
	# snapshot. Reapplying it there would emit every changed signal twice.
	if not _is_host_authority():
		apply_combat_snapshot(snapshot)
	_apply_authoritative_reaction(effect)
	if peer_id != multiplayer.get_unique_id() or _combat_feedback == null:
		return
	var actual := maxf(float(effect.get("actual_damage", 0.0)), 0.0)
	var at := _incoming_popup_at()
	if bool(effect.get("dodged", false)):
		_combat_feedback.dodge_feedback(at)
	elif actual > 0.0:
		_combat_feedback.damage_taken(
			actual, at, int(effect.get("source_peer", 0)),
			String(effect.get("source_name", "")),
			String(effect.get("ability_name", "")))
	elif bool(effect.get("status_impact", false)) \
			or int(effect.get("reaction", DamageHit.Reaction.NONE)) \
				!= DamageHit.Reaction.NONE:
		_combat_feedback.status_impact()
	if bool(effect.get("blocked", false)):
		var perfect := bool(effect.get("perfect", false))
		_combat_feedback.parry_feedback(perfect, at)
		if perfect and _parry_shield != null:
			_parry_shield.celebrate_perfect()


@rpc("authority", "call_local", "reliable")
func _apply_outgoing_feedback(event_sequence: int,
		wire: Dictionary) -> void:
	if event_sequence <= _last_feedback_sequence:
		return
	_last_feedback_sequence = event_sequence
	if peer_id != multiplayer.get_unique_id() or _combat_feedback == null:
		return
	var event := DamageNumberEvent.from_wire(wire)
	if event.kind != DamageNumberEvent.Kind.DAMAGE:
		_combat_feedback.world_float(event)
		return
	_combat_feedback.outgoing_damage(
		event.amount, event.world_position, event.target_peer, event.critical,
		event.structure, event.merge_key, event.killed)
	if CrawlerRules.training_active():
		var hud := combat_hud() as CombatHud
		if hud != null and hud.hit_log() != null:
			hud.hit_log().record(event.source_name, event.amount)


@rpc("authority", "call_local", "reliable")
func _apply_crawler_kill_loot(event_sequence: int, gold: int, xp: int,
		gems: int, at: Vector3) -> void:
	if event_sequence <= _last_feedback_sequence:
		return
	_last_feedback_sequence = event_sequence
	if peer_id != multiplayer.get_unique_id() or _combat_feedback == null:
		return
	_combat_feedback.loot_gained(gold, xp, at, gems)


@rpc("authority", "call_local", "reliable")
func _apply_grab_state(event_sequence: int, socket_path: String,
		offset: Transform3D, throw_velocity: Vector3) -> void:
	if event_sequence <= _last_grab_sequence:
		return
	_last_grab_sequence = event_sequence
	if not throw_velocity.is_finite():
		throw_velocity = Vector3.ZERO
	if not socket_path.is_empty():
		var path := NodePath(socket_path)
		if path.is_absolute():
			return
		for index in path.get_name_count():
			if path.get_name(index) == &"..":
				return
		_grab_socket_path = path
		_grab_socket_node = null
		_grab_offset = offset
		_grabbed = true
		_clear_ragdoll()
		_interrupt_combat_actions()
		collider.set_deferred(&"disabled", true)
		grabbed.emit(grab_socket())
		return
	_grabbed = false
	_grab_socket_path = NodePath()
	_grab_socket_node = null
	_grab_offset = Transform3D.IDENTITY
	collider.set_deferred(&"disabled", false)
	velocity = throw_velocity
	released_from_grab.emit(throw_velocity)
	if throw_velocity.length_squared() > 0.0001:
		_force_full_ragdoll_local(throw_velocity, DAMAGE_RAGDOLL_TIME)


## A local call reports no sender, so that stands for this player themselves.
func _sender_owns_this_player() -> bool:
	var sender := multiplayer.get_remote_sender_id()
	return sender == 0 or sender == peer_id


@rpc("authority", "call_remote", "reliable")
func _apply_warp(at_transform: Transform3D, carried := Vector3.ZERO) -> void:
	if not at_transform.origin.is_finite():
		return
	velocity = carried if carried.is_finite() else Vector3.ZERO
	if _stance == Stance.FLY:
		_flight_velocity = velocity
	global_transform = at_transform
	reset_physics_interpolation()
	reset_network_state(at_transform)


@rpc("authority", "call_remote", "unreliable_ordered")
func _apply_state(next_transform: Transform3D, next_velocity: Vector3, look_pitch: float, stance: int) -> void:
	var local_owner := peer_id == multiplayer.get_unique_id()
	var authoritative_override := _dead or _grabbed or _lassoed \
		or _stagger_left > 0.0 \
		or _forced_ragdoll \
		or (statuses.has(CombatStatuses.FLIGHTLESS) and _stance == Stance.FLY)
	if local_owner and not authoritative_override:
		return
	var next_stance := clampi(stance, 0, Stance.size() - 1)
	if _stance == Stance.CRASH and next_stance != Stance.CRASH and not _dead:
		_clear_ragdoll()
	if local_owner:
		global_transform = next_transform
		velocity = next_velocity
		_pitch = clampf(look_pitch, -1.48, 1.48)
		head.rotation.x = _pitch
		_apply_stance(next_stance)
		reset_physics_interpolation()
		return
	_target_transform = next_transform
	_target_velocity = next_velocity
	_target_pitch = clampf(look_pitch, -1.48, 1.48)
	_extrapolated = 0.0
	_apply_stance(next_stance)


@rpc("any_peer", "call_remote", "reliable")
func _sync_overdrive(left: float, boost: float, body_scale: float) -> void:
	_overdrive_left = maxf(left, 0.0)
	_overdrive_boost = maxf(boost, 0.0)
	_overdrive_body_scale = body_scale if _overdrive_left > 0.0 else 1.0
	if _overdrive_left <= 0.0:
		_overdrive_card_uid = ""
		_overdrive_mods.clear()
	_apply_overdrive_visual()
	if peer_id == multiplayer.get_unique_id():
		_refresh_crawler_ability_stats()
