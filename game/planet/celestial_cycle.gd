class_name CelestialCycle
extends Node

## Orbits the light and the celestial sphere while the planet remains still.
##
## The orbit axis is [member PlanetShape.frost_axis], the centre of the north
## polar cloud circle. The sun is constrained to the plane perpendicular to that
## axis, so the terminator always passes through both poles: exactly half of the
## ice cap is day and half is night at every phase.

## Mirrors the deliberately tiny analytical model in vivid_lib.gdshaderinc for
## the compositor's tint. Raw RenderingDevice shaders cannot read Godot shader
## globals or include a gdshaderinc, so the three wavelength coefficients have
## to cross the CPU/GPU boundary here if the god rays are to match the sun disc.
const AIR_RAYLEIGH := Vector3(0.19, 0.43, 1.0)
const AIR_DEPTH := 0.62
const SUNSET_REGION := 0.55
const SUNSET_HORIZON_INNER := 0.035
const SUNSET_HORIZON_OUTER := 0.34
const SKY_SCATTER_STRENGTH := 0.75

@export var planet: Planet
@export var sun: DirectionalLight3D
@export var world_environment: WorldEnvironment
## The place under the sun at phase zero. Its radial is projected onto the
## equatorial orbit plane, making this the brightest/noon point possible without
## giving the sun a declination that would light the polar cap unevenly.
@export var noon_anchor: SurfaceAnchor
@export var period_seconds := 960.0
## Zero updates the realtime sky and light smoothly every frame. A positive
## interval is retained for low-end overrides, but should not be used with an
## incremental Sky: restarting that multi-frame radiance bake on a timer creates
## a regular whole-frame hitch.
@export_range(0.0, 1.0, 0.01) var update_interval := 0.0
@export_range(-1.0, 1.0) var orbit_direction := 1.0
@export var day_ambient_energy := 0.38
@export var night_ambient_energy := 0.055

@export_group("God rays")
## How far off the edge of the screen the sun may be and still throw shafts
## across it, in screen widths. Shafts converge on the sun, so a sun just past
## the corner is exactly when the effect looks best; cutting it off at the edge
## makes the whole thing switch off as the player turns.
@export_range(0.0, 1.5, 0.05) var ray_margin := 0.6
## Sine of the sun's elevation where the shafts have fully faded and where they
## are at full strength. Shafts are light through the air and there is none of it
## once the sun is down; the pass is skipped entirely below the first figure.
@export_range(-0.5, 0.5) var ray_dusk_low := -0.04
@export_range(0.0, 1.0) var ray_dusk_high := 0.16

var _phase := 0.0
var _phase_anchor := 0.0
## Full planetary orbits completed in this world session. Phase alone wraps and
## cannot tell one night from the next; this is the deterministic palette key
## shared with joining peers.
var _day_index := 0
var _clock_anchor_msec := 0
var _time_paused := false
var _processing_before_pause := true
var _until_update := 0.0
var _pole := Vector3.UP
var _noon_to_sun := Vector3.FORWARD
var _to_sun := Vector3.FORWARD
var _god_rays: GodRaysEffect
var _air_chroma := 1.0
var _region_axis := Vector3(0.28, 0.95, 0.14).normalized()
var _region_turns := 3.0
var _region_phase := 0.0
var _region_chroma := 0.85


func _ready() -> void:
	process_mode = Node.PROCESS_MODE_ALWAYS
	if planet == null or planet.shape == null or sun == null:
		push_error("CelestialCycle needs its planet and directional sun")
		set_process(false)
		return
	_pole = (planet.global_basis * planet.shape.frost_axis).normalized()
	var noon := sun.global_basis.z.normalized()
	if noon_anchor != null:
		noon = (planet.global_basis * noon_anchor.direction.normalized()).normalized()
	noon -= _pole * noon.dot(_pole)
	if noon.is_zero_approx():
		noon = _pole.cross(Vector3.FORWARD
			if absf(_pole.z) < 0.9 else Vector3.RIGHT)
	_noon_to_sun = noon.normalized()
	_phase_anchor = _phase
	_clock_anchor_msec = Time.get_ticks_msec()
	_read_region_wheel()
	_find_god_rays()
	_follow_god_rays_setting()
	_apply()


func _process(delta: float) -> void:
	# Outside the phase gate below. The shafts converge on the sun's place on
	# screen, and that moves when the camera turns as much as when the sun does —
	# so this is per frame even when the orbit is stopped or is being updated on
	# an interval, or the effect lags a fast look by however long that interval
	# is and the shafts visibly slide back into place.
	_update_god_rays()
	if period_seconds <= 0.0:
		return
	# A monotonic clock makes the sixteen minutes literal real time and prevents
	# pause/process cadence from slowing or silently stopping the celestial orbit.
	var elapsed := float(Time.get_ticks_msec() - _clock_anchor_msec) / 1000.0
	var next_phase := fposmod(_phase_anchor + elapsed / period_seconds, 1.0)
	if next_phase < _phase - 0.5:
		_day_index += 1
	_phase = next_phase
	if update_interval <= 0.0:
		_apply()
		return
	_until_update -= delta
	if _until_update > 0.0:
		return
	_until_update = update_interval
	_apply()


func _apply() -> void:
	var angle := _phase * TAU * orbit_direction
	var to_sun := (Basis(_pole, angle) * _noon_to_sun).normalized()
	_to_sun = to_sun
	# A DirectionalLight3D shines down -Z; +Z is therefore the direction from the
	# planet toward the sun, the same convention vivid_space receives as
	# LIGHT0_DIRECTION.
	var right := _pole.cross(to_sun).normalized()
	if right.is_zero_approx():
		right = to_sun.cross(Vector3.RIGHT
			if absf(to_sun.x) < 0.9 else Vector3.FORWARD).normalized()
	var up := to_sun.cross(right).normalized()
	sun.global_transform = Transform3D(Basis(right, up, to_sun),
		sun.global_position)
	if world_environment != null and world_environment.environment != null \
			and noon_anchor != null:
		var landing_up := (
			planet.global_basis * noon_anchor.direction.normalized()).normalized()
		var landing_daylight := smoothstep(-0.12, 0.18, landing_up.dot(to_sun))
		world_environment.environment.ambient_light_energy = lerpf(
			night_ambient_energy, day_ambient_energy, landing_daylight)
	RenderingServer.global_shader_parameter_set(&"celestial_angle", angle)


## Caches the broad region wheel used to tint the compositor's sunbeams.
##
## The sky samples the full two-octave boundary warp per pixel. Repeating that
## noise in GDScript every frame would spend far more CPU than colouring one
## low-opacity post effect warrants, so this follows the same approximation as
## GroundCover's handful of pooled region lights: same axis, turns, latitude
## bend, phase and chroma, with only the local boundary wander omitted.
func _read_region_wheel() -> void:
	var axis_setting: Dictionary = ProjectSettings.get_setting(
		"shader_globals/region_axis", {})
	var turns_setting: Dictionary = ProjectSettings.get_setting(
		"shader_globals/region_turns", {})
	var phase_setting: Dictionary = ProjectSettings.get_setting(
		"shader_globals/region_phase", {})
	var chroma_setting: Dictionary = ProjectSettings.get_setting(
		"shader_globals/region_chroma", {})
	_region_axis = (axis_setting.get("value", _region_axis) as Vector3).normalized()
	_region_turns = float(turns_setting.get("value", _region_turns))
	_region_phase = float(phase_setting.get("value", _region_phase))
	_region_chroma = float(chroma_setting.get("value", _region_chroma))


## Finds the god-rays effect on the environment's compositor, if there is one.
##
## Looked up rather than exported so that a scene without the effect, or a
## harness that stands its own environment up, simply has no rays instead of a
## broken reference.
func _find_god_rays() -> void:
	if world_environment == null:
		return
	# On the node and not on its Environment: a compositor is a set of render
	# passes rather than a description of the air, so Godot hangs it off
	# WorldEnvironment and Camera3D directly.
	var compositor := world_environment.compositor
	if compositor == null:
		return
	for effect: CompositorEffect in compositor.compositor_effects:
		if effect is GodRaysEffect:
			_god_rays = effect
			return


## Takes both atmosphere toggles from the player's settings and keeps taking
## them. God rays use their own switch; the scattering switch controls whether
## their low-sun tint follows the coloured atmosphere or the old fixed sun.
##
## [member CompositorEffect.enabled] and not a strength of zero. Disabled effects
## are dropped before the render buffers are configured, so off costs no depth
## resolve, no compute dispatch and no composite — which a zero multiplier would
## still pay all three of.
func _follow_god_rays_setting() -> void:
	var settings := get_node_or_null("/root/SettingsManager") as GameSettingsManager
	if settings == null or _god_rays == null:
		return
	_god_rays.enabled = bool(settings.get_setting(&"graphics", &"god_rays", true))
	_air_chroma = 1.0 if bool(settings.get_setting(
		&"graphics", &"atmospheric_scattering", true)) else 0.0
	settings.settings_changed.connect(
		func(section: StringName, key: StringName, value: Variant) -> void:
			if section != &"graphics":
				return
			if key == &"god_rays" and _god_rays != null:
				_god_rays.enabled = bool(value)
			elif key == &"atmospheric_scattering":
				_air_chroma = 1.0 if bool(value) else 0.0)


## Broad local region hue, matching vivid_region apart from its small boundary
## warp. Takes a unit radial in world space.
func _region_hue(unit: Vector3) -> float:
	var axis := _region_axis.normalized()
	var hint := Vector3.UP if absf(axis.y) < 0.9 else Vector3.RIGHT
	var side := axis.cross(hint).normalized()
	var front := axis.cross(side)
	var longitude := atan2(unit.dot(side), unit.dot(front)) / TAU
	var latitude := asin(clampf(unit.dot(axis), -1.0, 1.0)) / PI
	return fposmod(
		longitude * _region_turns + latitude * 0.5 + _region_phase, 1.0)


## The sky shader's low-sun colour for the compositor.
##
## Kept as a named function because this is testable without drawing a frame:
## noon must preserve [param base], the horizon must change it, and two places
## on the wheel must not produce the same sunset. Those three facts catch a
## fixed orange tint that would technically be a sunset but miss the requested
## planet-scale variation.
func _sunset_tint(base: Color, up: Vector3, elevation: float) -> Color:
	var near_horizon := 1.0 - smoothstep(
		SUNSET_HORIZON_INNER, SUNSET_HORIZON_OUTER, absf(elevation))
	var blend := clampf(
		near_horizon * _air_chroma * SKY_SCATTER_STRENGTH, 0.0, 1.0)
	if blend <= 0.0:
		return base

	var air_mass := 1.0 / (maxf(elevation, 0.0) + 0.15)
	var depth := air_mass * AIR_DEPTH
	var transmitted := Vector3(
		exp(-AIR_RAYLEIGH.x * depth),
		exp(-AIR_RAYLEIGH.y * depth),
		exp(-AIR_RAYLEIGH.z * depth))
	transmitted /= maxf(maxf(transmitted.x, transmitted.y), transmitted.z)

	var hue := _region_hue(up.normalized())
	var spectrum := Vector3(
		0.5 + 0.5 * cos(TAU * hue),
		0.5 + 0.5 * cos(TAU * (hue + 0.33)),
		0.5 + 0.5 * cos(TAU * (hue + 0.67)))
	var local := transmitted.lerp(spectrum, _region_chroma * SUNSET_REGION)
	var authored := Vector3(base.r, base.g, base.b)
	local *= authored
	var base_peak := maxf(maxf(authored.x, authored.y), authored.z)
	local *= base_peak / maxf(maxf(maxf(local.x, local.y), local.z), 0.0001)
	return base.lerp(Color(local.x, local.y, local.z, base.a), blend)


## Tells the effect where the sun is on screen and how much of it to draw.
##
## The projection is done here, on the main thread, through the camera's own
## [method Camera3D.unproject_position] rather than by multiplying matrices on the
## render thread. It is the same answer for a fraction of the risk: the camera
## already knows its projection, its Y convention and its viewport, and every one
## of those three is a sign error waiting to be made by hand — one of which would
## put the shafts converging on a point mirrored across the screen.
func _update_god_rays() -> void:
	if _god_rays == null or not _god_rays.enabled:
		return
	var camera := get_viewport().get_camera_3d() if is_inside_tree() else null
	if camera == null:
		_god_rays.set_sun(Vector2.ZERO, Color.WHITE, 0.0, Vector2(1.0, 0.0))
		return

	# The sun is a direction, so it is projected as a point far enough along that
	# direction that the camera's own translation cannot move it.
	var at := camera.global_position + _to_sun * 1.0e7
	if camera.is_position_behind(at):
		_god_rays.set_sun(Vector2.ZERO, Color.WHITE, 0.0, Vector2(1.0, 0.0))
		return
	var extent := camera.get_viewport().get_visible_rect().size
	if extent.x <= 0.0 or extent.y <= 0.0:
		_god_rays.set_sun(Vector2.ZERO, Color.WHITE, 0.0, Vector2(1.0, 0.0))
		return
	var uv := camera.unproject_position(at) / extent

	# How far outside the screen the sun has wandered, as the larger of the two
	# axes' overshoot, and the fade that goes with it. Without the fade the effect
	# pops off at the margin instead of thinning out.
	var overshoot := maxf(
		maxf(-uv.x, uv.x - 1.0),
		maxf(-uv.y, uv.y - 1.0))
	var edge := 1.0 - smoothstep(ray_margin * 0.4, ray_margin, maxf(overshoot, 0.0))
	# Elevation is taken where the camera is standing, not at the landing site:
	# a player who has flown to the night side should have no shafts even while
	# it is noon over the anchor.
	var up := Vector3.UP
	if planet != null:
		up = (camera.global_position - planet.global_position).normalized()
	var daylight := smoothstep(ray_dusk_low, ray_dusk_high, up.dot(_to_sun))
	var energy := edge * daylight
	var ray_tint := _sunset_tint(
		sun.light_color if sun != null else Color.WHITE,
		up, up.dot(_to_sun))
	# Zero rather than a small number, so a sun behind the player or under the
	# horizon skips both passes outright.
	_god_rays.set_sun(uv, ray_tint,
		energy if energy > 0.002 else 0.0, _veil_depths(camera))


## The effect's two veil distances as raw depth values, which is what its shader
## compares the depth buffer against.
##
## Not through [method Camera3D.get_camera_projection]. That returns the projection
## the camera was built with, and the depth buffer is written under the reverse-Z
## correction the renderer applies on top of it — so its z runs the other way and
## over a different range. Using it directly made the shader reject every pixel
## including the sky, and the effect drew nothing at all.
##
## What is used instead is the mapping the rest of this project already reads depth
## under, stated at both ends: [code]raw[/code] is one at the near plane, zero at
## the far plane, and therefore zero where nothing was drawn. That last equality is
## why [code]vivid_water.gdshader[/code] can test [code]raw > 0.0[/code] for "is
## there a bed here", and it is the same convention god_rays.glsl marches under.
func _veil_depths(camera: Camera3D) -> Vector2:
	var near := maxf(camera.near, 0.001)
	var far := maxf(camera.far, near * 2.0)
	var depths := Vector2.ZERO
	for index in 2:
		var distance := maxf(
			_god_rays.veil_near if index == 0 else _god_rays.veil_far, near)
		depths[index] = near * (far / distance - 1.0) / (far - near)
	return depths


## Direction toward the sun at a given phase, in world space. Phase zero is
## noon over [member noon_anchor]; the orbit then turns about the frost axis.
func sun_direction_at(phase_value: float) -> Vector3:
	var angle := fposmod(phase_value, 1.0) * TAU * orbit_direction
	if _noon_to_sun.length_squared() < 0.0001:
		return _to_sun
	return (Basis(_pole, angle) * _noon_to_sun).normalized()


## Local sun elevation in degrees. Positive is above the horizon at [param world_up].
func local_elevation_degrees(world_up: Vector3) -> float:
	if world_up.length_squared() < 0.0001 or _to_sun.length_squared() < 0.0001:
		return 0.0
	return rad_to_deg(asin(clampf(
		world_up.normalized().dot(_to_sun), -1.0, 1.0)))


## Phase that puts the sun at [param elevation_degrees] for [param world_up].
## Evening (descending sun) is the default, so a spawn opens at dusk rather
## than at the matching dawn.
func phase_for_local_elevation(
		world_up: Vector3, elevation_degrees: float, evening := true) -> float:
	return solve_phase_for_elevation(
		_pole, _noon_to_sun, world_up, elevation_degrees, orbit_direction,
		evening)


## Closed-form dusk/dawn solver. Exposed so tests can check it without a live
## planet: A cos θ + B sin θ = sin(elevation) on the equatorial orbit.
static func solve_phase_for_elevation(
		pole: Vector3, noon_to_sun: Vector3, world_up: Vector3,
		elevation_degrees: float, orbit_dir: float,
		evening := true) -> float:
	if pole.length_squared() < 0.0001 or noon_to_sun.length_squared() < 0.0001 \
			or world_up.length_squared() < 0.0001:
		return 0.0
	var axis := pole.normalized()
	var noon := noon_to_sun.normalized()
	noon -= axis * noon.dot(axis)
	if noon.length_squared() < 0.0001:
		return 0.0
	noon = noon.normalized()
	var up := world_up.normalized()
	var east := axis.cross(noon)
	if east.length_squared() < 0.0001:
		return 0.0
	east = east.normalized()
	var along := up.dot(noon)
	var across := up.dot(east)
	var reach := sqrt(along * along + across * across)
	if reach < 0.0001:
		return 0.0
	var target := clampf(sin(deg_to_rad(elevation_degrees)), -reach, reach)
	var alpha := atan2(across, along)
	var delta := acos(clampf(target / reach, -1.0, 1.0))
	var angle_a := alpha + delta
	var angle_b := alpha - delta
	var deriv_a := -along * sin(angle_a) + across * cos(angle_a)
	var pick := angle_a
	var turning := 1.0 if orbit_dir >= 0.0 else -1.0
	if evening:
		if deriv_a * turning > 0.0:
			pick = angle_b
	elif deriv_a * turning < 0.0:
		pick = angle_b
	var phase_value := pick / TAU
	if orbit_dir < 0.0:
		phase_value = -phase_value
	return fposmod(phase_value, 1.0)


## Normalized 0..1 position in the sixteen-minute day. Used only to synchronize
## a client when it joins; after that every peer advances by the same delta.
func phase() -> float:
	return _phase


## Which full orbit this session is on. Used for visual systems whose palette
## should change from one night to the next.
func day_index() -> int:
	return _day_index


## Synchronizes a joining peer to the host's nightly palette.
func set_day_index(value: int) -> void:
	_day_index = maxi(value, 0)


## Freezes the real-time orbit without letting the monotonic clock count the
## pause as elapsed daylight. The cycle normally runs in ALWAYS mode so online
## sessions and title screens keep honest wall-clock time; single-player menus
## are the one place that explicitly stop it.
func set_time_paused(paused: bool) -> void:
	if paused == _time_paused:
		return
	_phase_anchor = _phase
	_clock_anchor_msec = Time.get_ticks_msec()
	_time_paused = paused
	if paused:
		_processing_before_pause = is_processing()
		set_process(false)
		return
	set_process(_processing_before_pause)
	if is_inside_tree() and sun != null:
		_apply()


func set_phase(value: float) -> void:
	_phase = fposmod(value, 1.0)
	_phase_anchor = _phase
	_clock_anchor_msec = Time.get_ticks_msec()
	_until_update = 0.0
	if is_inside_tree() and sun != null:
		_apply()
