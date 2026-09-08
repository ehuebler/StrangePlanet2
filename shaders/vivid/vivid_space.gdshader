// Everything behind the planet: daytime sky at sea level, open space above it,
// and one continuous climb between the two.
//
// There is no second scene for space and no swap at a boundary. The camera's own
// height above the planet — read from the same frame the ground uses — fades the
// atmosphere out and the stars in, so a flight up from a beach thins the blue,
// darkens the zenith first, and finishes with the sun burning in front of a
// nebula. Coming back down runs it in reverse.
//
// TIME is deliberately not used anywhere in here. A sky shader that reads it
// forces the radiance cubemap to be rebuilt every single frame, and this sky is
// the scene's ambient light source.
shader_type sky;

#include "res://shaders/vivid/vivid_lib.gdshaderinc"

group_uniforms Atmosphere;
uniform vec3 zenith_color : source_color = vec3(0.07, 0.26, 0.72);
uniform vec3 horizon_color : source_color = vec3(0.60, 0.84, 0.97);
// What is below the horizon at altitude, before the planet itself covers it.
uniform vec3 haze_color : source_color = vec3(0.44, 0.58, 0.62);
// Higher values keep the pale band tight to the horizon.
uniform float horizon_falloff : hint_range(1.0, 12.0) = 3.4;
// Metres of climb over which the sky gives way to space. It is a look, not a
// physical scale height: this is the altitude at which flying feels like leaving.
uniform float atmosphere_height = 2400.0;
// How much of the region below colours the air above it. At 1 the sky keeps its
// vertical gradient as brightness and takes the whole of its hue from the ground
// it stands over; at 0 it is the plain blue of zenith_color and horizon_color.
// Well up the range on purpose: zenith_color and horizon_color are a strongly
// blue, nearly white pair, so anything under about 0.7 leaves most of that blue
// standing and the region reads as a faint cast over a normal sky rather than as
// the colour of the place.
uniform float sky_region_tint : hint_range(0.0, 1.0) = 0.85;
// How much of that is given up at the zenith. Straight up is the shortest path
// through the air and the least of it, so the tint thins overhead — but only
// partly, because the whole sky is meant to read as belonging to the region.
uniform float sky_region_lift : hint_range(0.0, 1.0) = 0.2;
group_uniforms;

group_uniforms Night;
// Night is the second way out of the air, and for anyone standing on the ground
// it is the only one. Without these the sky had exactly one state — the daytime
// blue above — so the unlit half of the planet was black ground under a bright
// noon sky, and the stars, gated on altitude alone, could not be seen from any
// surface anywhere.
//
// The two dusk numbers are the sine of the sun's elevation where the sky starts
// going out and where it is fully out: 0.14 is about eight degrees up, which is
// when the first stars appear, and -0.30 is seventeen degrees under, which is
// past the end of astronomical twilight.
uniform float dusk_low : hint_range(-0.8, 0.0) = -0.30;
uniform float dusk_high : hint_range(0.0, 0.8) = 0.14;
// What the air keeps once the sun is fully down. Not zero: air still scatters
// starlight and airglow, and a horizon that reaches pure black stops reading as
// a horizon at all.
uniform float night_air : hint_range(0.0, 0.5) = 0.05;
group_uniforms;

group_uniforms Scattering;
// How far the wavelength model in `vivid_air_scatter` is allowed to take the
// sky's hue over from `zenith_color`/`horizon_color`. Multiplied by the
// `air_chroma` global, so the player's setting scales this rather than replacing
// it and the tuning here survives being switched off and on.
//
// Not 1.0. The authored pair is a good blue and the scattering is better at the
// horizon and at dusk than it is overhead; leaving a quarter of the original
// standing keeps the zenith from going the slightly cyan blue the raw
// inverse-fourth ratio gives.
uniform float scatter_strength : hint_range(0.0, 1.0) = 0.75;
// Thickness of the air, as a multiple of the model's own vertical atmosphere.
// Higher reddens the low sun earlier and pales the horizon further up the sky.
uniform float scatter_density : hint_range(0.2, 3.0) = 1.0;
// Share of that density still there once the camera has left the atmosphere.
// Not zero: the limb of the planet is exactly where the air is thickest, and a
// sky in orbit that has stopped scattering leaves the shell drawing a coloured
// rim against a horizon that no longer agrees with it.
uniform float scatter_vacuum : hint_range(0.0, 1.0) = 0.3;
group_uniforms;

group_uniforms Sun;
uniform vec3 sun_color : source_color = vec3(1.0, 0.94, 0.82);
uniform float sun_size_degrees : hint_range(0.2, 12.0) = 1.6;
// The disc is the brightest thing on screen and the only thing meant to bloom,
// so it sits just far enough over the glow threshold to do it and no further.
uniform float sun_intensity : hint_range(0.0, 12.0) = 2.6;
uniform float sun_glow : hint_range(0.0, 4.0) = 0.45;
// Tightness of the glow around the disc. Lower spreads it across the whole sky.
uniform float sun_glow_falloff : hint_range(1.0, 64.0) = 14.0;
group_uniforms;

group_uniforms Space;
uniform vec3 space_color : source_color = vec3(0.012, 0.016, 0.038);
uniform float star_brightness : hint_range(0.0, 4.0) = 1.4;
// Cells per unit of direction. Each layer is a different star size and count.
//
// Coarser than it looks like it should be, and that is the whole trick to a full
// sky. A cell at density 500 subtends a fifth of a pixel at any sane field of
// view, so a layer up there adds hundreds of thousands of stars that cannot be
// seen and only cost a hash — the first version of this ran at 180/420/850 and
// read as a nearly empty sky *because* of it. Star count is bought with
// [member star_fill], which costs nothing, and the density is then set by how
// big a star should be rather than by how many there are.
uniform vec3 star_densities = vec3(110.0, 240.0, 520.0);
uniform float star_size : hint_range(0.05, 0.6) = 0.26;
// Share of cells in a layer holding a star at all.
uniform float star_fill : hint_range(0.01, 0.9) = 0.62;
// Share of the coarsest cells holding a bright one. A sky is a hierarchy and not
// a speckle: without a scattering of stars an order brighter than the rest, a
// field of evenly matched dots reads as sensor noise however many of them there
// are, which is the trap in being asked for more stars.
uniform float star_beacons : hint_range(0.0, 0.4) = 0.055;
// The milky wash down the band: stars too small to be stars.
//
// A fourth lattice cannot do this. Below about a pixel a point is not a disc any
// more, it is a lift in the background, and lattice points that small alias into
// a speckle that crawls as the camera turns. A noise field at the pitch those
// stars would have had is what the eye is actually being shown.
// Fine, and faint. At the scale a nebula is drawn at this reads as grey mould
// over the whole sky rather than as a galaxy; it has to be near the pitch of the
// stars themselves, and it has to stay under them.
uniform float star_haze : hint_range(0.0, 2.0) = 0.22;
uniform float star_haze_scale = 130.0;
// Pole of the galactic band. Stars and nebula both crowd its equator.
uniform vec3 galaxy_axis = vec3(0.32, 0.86, -0.4);
uniform float galaxy_band : hint_range(0.0, 1.0) = 0.85;
// Space is mostly empty and reads as empty. Past about 0.5 the clouds stop
// being a backdrop and start being weather.
uniform float nebula_amount : hint_range(0.0, 3.0) = 0.3;
uniform float nebula_scale = 2.1;
// Where the nebula sits on the same colour wheel the planet's regions use, so
// the sky a region gleams under belongs to it. 0.14 is the violet end; the
// middle of the range is green, which reads as a fault rather than as a nebula.
uniform float nebula_hue : hint_range(0.0, 1.0) = 0.14;
// How far the hue drifts along the clouds. Zero is one flat wash of colour.
uniform float nebula_hue_spread : hint_range(0.0, 1.0) = 0.45;
group_uniforms;


// Express a sky direction in a lattice that is not the world cube. A unit
// sphere cut by an axis-aligned grid is a stack of rings around X, Y and Z;
// four layers on that same grid just draw the same rings four times. Each
// layer gets its own orthonormal frame so the bands miss each other and the
// field reads as isotropic.
vec3 star_frame(vec3 direction, vec3 seed) {
	vec3 w = normalize(seed);
	vec3 u = normalize(cross(w, abs(w.x) > 0.2 ? vec3(0.0, 1.0, 0.0) : vec3(1.0, 0.0, 0.0)));
	vec3 v = cross(w, u);
	return vec3(dot(direction, u), dot(direction, v), dot(direction, w));
}


// One layer of stars, from a lattice of cells in space rather than a grid on the
// sphere: a lat/long grid piles every one of its stars onto the poles.
//
// Only the cell the direction falls in is tested, so a star is jittered by less
// than it would take to cross an edge and get clipped.
vec3 star_layer(vec3 direction, float density, float size, float fill, vec3 seed) {
	vec3 point = star_frame(direction, seed) * density;
	vec3 cell = floor(point);
	vec3 random = vivid_hash33(cell);
	if (random.z > fill) {
		return vec3(0.0);
	}
	vec3 center = cell + 0.5 + (random - 0.5) * 0.72;
	float radius = size * mix(0.4, 1.0, random.x);
	float core = smoothstep(radius, 0.0, length(point - center));
	// Blue-white through to amber, the way a real field of stars sorts itself.
	vec3 tint = mix(vec3(0.70, 0.80, 1.0), vec3(1.0, 0.84, 0.62), random.y);
	// Squared rather than cubed. The exponent decides how much of a star's disc
	// survives, and at three the faint two thirds of every layer fall under a
	// pixel and the sky reads as a handful of bright dots on black.
	return tint * (core * core) * mix(0.25, 1.0, random.x);
}


vec3 deep_space(vec3 direction, float band) {
	vec3 color = space_color;
	// Nebula: one field decides where it is, a second decides its hue, so the
	// clouds change colour along their length instead of being one wash.
	float cloud = vivid_fbm3(direction * nebula_scale + 11.7, 5);
	// A high threshold on purpose: the clouds are meant to be somewhere in the
	// sky rather than over all of it.
	float veil = smoothstep(0.55, 0.95, cloud) * mix(0.08, 1.0, band);
	float hue = nebula_hue
		+ (vivid_fbm3(direction * nebula_scale * 0.45 + 3.1, 3) - 0.5) * nebula_hue_spread;
	color += vivid_spectrum(hue) * veil * nebula_amount * 0.5;
	// A dust lane through the middle of the band, which is what stops the
	// galaxy from reading as a symmetrical smear.
	float dust = smoothstep(0.55, 0.95, vivid_ridge3(direction * nebula_scale * 1.7, 3));
	color *= mix(1.0, 0.35, dust * band * 0.8);

	// Unresolved stars first, so the discs sit on top of their own glow. Cubed,
	// where the discs only take the band as a lean: a haze that reaches the
	// galactic pole at all is not a band, it is a dirty lens.
	color += vec3(0.60, 0.68, 0.92) * star_haze * band * band * band
		* smoothstep(0.48, 0.95, vivid_fbm3(direction * star_haze_scale, 3));

	vec3 stars = star_layer(direction, star_densities.x * 0.42, star_size * 1.15,
			star_beacons, vec3(1.00, 0.31, 0.72)) * 1.6
		+ star_layer(direction, star_densities.x, star_size, star_fill,
			vec3(0.22, 1.00, 0.48))
		+ star_layer(direction, star_densities.y, star_size * 0.8, star_fill,
			vec3(0.63, 0.18, 1.00)) * 0.7
		+ star_layer(direction, star_densities.z, star_size * 0.62, star_fill,
			vec3(0.41, 0.87, 0.23)) * 0.45;
	// The band is where the sky is crowded; away from it stars thin out — but
	// only thin out. The floor was low enough that three quarters of the sky was
	// effectively empty, and since the galactic pole is wherever galaxy_axis
	// happens to point, which half of the planet got a sky was luck.
	return color + stars * star_brightness * mix(0.8, 1.8, band);
}


// Reads the fixed procedural star field through the inverse of the celestial
// orbit. The visible stars therefore travel around frost_axis with the sun while
// the planet, its clouds and its coloured regions remain still.
vec3 celestial_direction(vec3 direction) {
	vec3 axis = normalize(frost_axis);
	float angle = -celestial_angle;
	float cosine = cos(angle);
	float sine = sin(angle);
	return direction * cosine + cross(axis, direction) * sine
		+ axis * dot(axis, direction) * (1.0 - cosine);
}


// Named to_sun rather than sun_direction: the frame's own sun_direction is a
// global uniform, and a parameter shadowing it is a compile error.
//
// [param region_color] is the region's hue at full brightness,
// [param region_strength] is how strongly this one answers the light, and
// [param daylight] is how much sun there is where the camera is standing.
//
// [param region_hue] is the same region's place on the colour wheel, handed
// separately because the scattering wants the coordinate rather than the colour
// built from it, and [param density] is how much air the camera is standing in.
// [param direct_sun] is the authored sun colour after the same air and region
// have coloured it; sharing it keeps the disc, halo and shafts of forward
// scattering from disagreeing at sunset.
vec3 atmosphere(vec3 direction, vec3 up, vec3 to_sun, vec3 region_color,
		float region_strength, float daylight, float region_hue, float density,
		vec3 direct_sun, float amount) {
	float height = dot(direction, up);
	float lift = pow(clamp(height, 0.0, 1.0), 1.0 / horizon_falloff);
	vec3 color = mix(horizon_color, zenith_color, lift);
	// Started well above the horizon so the band under it arrives as haze rather
	// than as a line drawn across the sky at exactly eye level.
	color = mix(color, haze_color, smoothstep(0.06, -0.3, height));

	// The air over a region takes that region's hue.
	//
	// Applied to the sky's brightness and not to its colour, which is the whole
	// trick: multiplying a saturated blue by a hue the way the ground does can
	// only take channels away, so an orange region over a blue sky came out as
	// a darker blue rather than as an orange sky. Flattening to luminance first
	// throws away the blue and hands the hue over entirely, while the vertical
	// gradient that luminance was built from survives untouched.
	float luma = dot(color, vec3(0.2126, 0.7152, 0.0722));
	float region_luma = max(dot(region_color, vec3(0.2126, 0.7152, 0.0722)), 0.001);
	// Clamped because a hue weighted into the blue channel needs a factor of
	// four to reach the same luminance, and unclamped that puts the whole dome
	// over the glow threshold and blooms the sky into fog.
	vec3 hued = min(region_color * (luma / region_luma), vec3(1.0));
	color = mix(color, hued,
		sky_region_tint * region_strength * (1.0 - lift * sky_region_lift));

	// The wavelength model, taking over the hue of everything decided above and
	// leaving its brightness alone. The two terms below are the sun's own halo,
	// so they are added afterwards in `direct_sun`: the matching low-sun colour
	// computed once for the disc, halo and god-ray compositor.
	color = vivid_air_scatter(color, direction, up, to_sun, region_hue,
		density * scatter_density, amount);

	// Forward scattering: the sky brightens toward the sun and warms as it does,
	// which is most of what makes a low sun read as a low sun.
	float toward_sun = max(dot(direction, to_sun), 0.0);
	color += direct_sun * sun_glow * pow(toward_sun, sun_glow_falloff) * 0.55;
	// The broad half of that halo is the one thing the scattering duplicates —
	// its haze lobe is the same wide warm wash, only wavelength-aware — so this
	// gives way as the model comes in rather than being added on top of it. Left
	// standing, dusk near the sun ran two forward lobes together and bloomed the
	// whole western sky into a flat white sheet.
	color += direct_sun * sun_glow * pow(toward_sun, 2.4) * 0.12
		* (1.0 - amount * 0.75);
	// Put out with the sun, glow included. Air is not lit from nowhere, and this
	// is what turns the daytime dome into a night sky rather than leaving a blue
	// noon over a hemisphere with no sun in it.
	return color * mix(night_air, 1.0, daylight);
}


void sky() {
	vec3 up = vivid_up(POSITION);
	// The sky is the one place the sun is known first hand, so it uses the light
	// rather than the frame's sun_direction.
	//
	// LIGHT0_DIRECTION already points **at** the sun, and is not the frame's
	// `sun_direction` with a different name: that one is where the light travels,
	// matching a DirectionalLight3D's -Z, while this is the +Z the engine hands a
	// sky shader so that `dot(EYEDIR, LIGHT0_DIRECTION)` peaks on the disc. Godot's
	// own ProceduralSkyMaterial uses it exactly that way. Negating it here — which
	// is what the comment this replaces assumed — drew the sun, its glow and the
	// whole forward-scattering warm half of the sky on the side of the planet
	// facing away from the light, so the lit hemisphere had a night sky over it
	// and the dark one had the sun.
	vec3 to_sun = LIGHT0_ENABLED
		? normalize(LIGHT0_DIRECTION)
		: normalize(vec3(0.35, 0.65, 0.45));
	float altitude = vivid_altitude(POSITION);
	// Two ways out of the daytime sky, and whichever has gone further wins.
	// Climbing thins the air away; the planet turning puts it out. A player on a
	// beach at night never reaches the first and the stars have to arrive by the
	// second, or the night side is a black ground under a blue noon.
	float in_space = smoothstep(atmosphere_height * 0.2, atmosphere_height, altitude);
	float daylight = smoothstep(dusk_low, dusk_high, dot(up, to_sun));
	float vacuum = max(in_space, 1.0 - daylight);
	// The region under the camera, not vivid_region_light: the hue is wanted at
	// full strength here, with the intensity kept apart as how far to carry it.
	// A dull region still colours its sky, or flying over one looks like flying
	// out of the effect altogether.
	vec2 region = vivid_region(up);
	vec3 region_color = mix(vec3(1.0), vivid_spectrum(region.x), region_chroma);
	float region_strength = mix(0.8, 1.0, region.y);
	// Air thins with the climb, on the same curve the blue fades out on, so a
	// flight up gets a deeper zenith and a shorter dusk band rather than the
	// scattering switching off at a boundary.
	float density = mix(1.0, scatter_vacuum, in_space);
	float amount = clamp(scatter_strength * air_chroma, 0.0, 1.0);
	// One answer shared by all three direct-light terms below. Near the horizon
	// it is the wavelength-filtered local region colour; overhead, or with
	// scattering switched off, it is `sun_color` exactly.
	vec3 direct_sun = vivid_sunset_light(sun_color, up, to_sun, region.x,
		density * scatter_density, amount);

	vec3 color;
	if (AT_CUBEMAP_PASS) {
		// The cubemap is the scene's ambient light. It wants the broad colour of
		// the sky and nothing that costs five octaves of noise per texel: stars
		// and nebula are worth no measurable ambient and are the whole cost.
		// The tint reaching it is deliberate — the light bouncing onto the
		// ground belongs to the same region the air over it does.
		color = mix(atmosphere(EYEDIR, up, to_sun, region_color, region_strength,
			daylight, region.x, density, direct_sun, amount), space_color, vacuum);
	} else {
		vec3 stars_at = celestial_direction(EYEDIR);
		float band = pow(1.0 - abs(dot(stars_at, normalize(galaxy_axis))), 4.0);
		band = mix(1.0, band, galaxy_band);
		color = mix(atmosphere(EYEDIR, up, to_sun, region_color, region_strength,
			daylight, region.x, density, direct_sun, amount),
			deep_space(stars_at, band), vacuum);
	}

	// The disc itself, drawn over both skies. Sized from the uniform rather than
	// LIGHT0_SIZE so that turning the sun into a shadow-casting point light does
	// not also make it invisible.
	float angle = acos(clamp(dot(EYEDIR, to_sun), -1.0, 1.0));
	float half_angle = radians(sun_size_degrees) * 0.5;
	float disc = 1.0 - smoothstep(half_angle * 0.75, half_angle, angle);
	// A halo that survives into space, where there is no air left to scatter it
	// and the raw brightness of the star is all there is to see.
	float halo = pow(max(dot(EYEDIR, to_sun), 0.0), 220.0);
	color += direct_sun * (
		disc * sun_intensity + halo * sun_glow * mix(0.4, 1.4, in_space));

	// Seen from under the sea, which the sky has to answer for even though nothing
	// about the sky is under water. A swimmer's view of it is through however much
	// sea the ray crosses on its way out, and that is a few metres straight up and
	// hundreds of metres anywhere near the horizon — so looking up keeps the sun
	// and Snell's window, and the band along the horizon where the sea's own disc
	// runs out goes to the same wash the bed does.
	//
	// Skipped for the cubemap pass, which is the scene's ambient light: a diver
	// still stands on ground lit by a whole sky, and dimming that here would take
	// the light off the bed twice.
	if (!AT_CUBEMAP_PASS && altitude < 0.0) {
		vec3 kept;
		vec3 wash;
		vivid_sea_veil(vivid_sea_chord(POSITION, EYEDIR), -altitude, daylight, kept, wash);
		color = color * kept + wash * (vec3(1.0) - kept);
	}

	COLOR = color;
}
