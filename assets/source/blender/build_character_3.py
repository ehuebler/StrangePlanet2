"""Turn `assets/source/meshmaker/character_3.blend` into the settler: a rigged, animated body
plus three garments cut out of `assets/source/meshmaker/dressed.blend`.

Run headless from the project root:

    & "C:\\Program Files\\Blender Foundation\\Blender 5.1\\blender.exe" --background --python assets/source/blender/build_character_3.py

The MeshMaker source arrives as a T-posed mesh under a 12-bone stick rig that is
not inside it. Everything here is measured off the mesh instead, because the two
source files disagree about almost everything: `dressed.blend` is a *different*
sculpt, 1.75 m against 1.60 m (all of it hair), and standing with its heel on the
origin. Nothing may be carried across by coordinate; only by landmark.

**Both sculpts arrive facing -Y and the whole project faces +Y.** `load_body`
turns the body and `extract_garments` turns the sculpt, and neither trusts the
file: they measure the feet and turn whatever they find. A body left facing the
wrong way does not fail loudly, because every landmark here is symmetric in y
except the feet - it builds a rig whose toe bones are in its heels, passes the
toes-in-front check in `_check_character.gd` on those bones, and only shows up as
a character who moonwalks.

Two of the three garments are grown off this body rather than cut out of the
sculpt, using `build_apparel.carve_shell` - the same code the astronaut's clothes
come from. A shell is a copy of the body's own faces pushed out along their
normals, so it fits by construction, arrives carrying the body's skin weights,
and cannot poke through. Cutting the coat out of the other sculpt and scaling it
onto this one is what produced the shredded rag this file used to build: no box
fit between two different bodies is close enough, and the per-vertex clearance
pass that followed tore the cloth into fringe wherever the fit had buried it.
The sculpt still supplies the hair, which is an accessory sitting off the scalp
rather than a garment following a body, and it supplies all three colours.

The astronaut in `player_character.blend` stays the reference for bone names and
for the pose tables, so `build_animations.py` bakes both bodies from one set of
clips. It cannot bake this one from the astronaut's numbers though: the settler's
legs are 47% of its height against the astronaut's 36%, and it rests in a true
T-pose rather than a wide A. Those measurements are handed over in
`bake_locomotion`.
"""

from __future__ import annotations

import collections
import math
import os

import bmesh
import bpy
from mathutils import Matrix, Vector
from mathutils.bvhtree import BVHTree

SOURCE_DIR = os.path.dirname(os.path.abspath(__file__))
ROOT = os.path.abspath(os.path.join(
    SOURCE_DIR, os.pardir, os.pardir, os.pardir))
MESHMAKER_DIR = os.path.join(ROOT, "assets", "source", "meshmaker")
WORK_DIR = os.path.join(ROOT, "assets", "work")
CHARACTER_DIR = os.path.join(ROOT, "assets", "runtime", "characters")
APPAREL_DIR = os.path.join(ROOT, "assets", "runtime", "apparel")

SRC_BLEND = os.path.join(MESHMAKER_DIR, "character_3.blend")
DRESSED_BLEND = os.path.join(MESHMAKER_DIR, "dressed.blend")
OUT_BLEND = os.path.join(WORK_DIR, "character_3_rigged.blend")
OUT_GLB = os.path.join(CHARACTER_DIR, "player_character_3.glb")
DEFAULT_SKIN = os.path.join(CHARACTER_DIR, "luke.png")

# Garments ship white because their colour wheel is their entire authored
# colour. The body does not: `character_3_skins.py` restates the two supplied
# front/back robotic concepts against this mesh's measured body and bakes them
# through the UV atlas it creates here; Luke is a third painting authored
# directly on that atlas. A tint still multiplies any finished design at runtime,
# while no tint leaves the authored paint intact.
WHITE = (1.0, 1.0, 1.0, 1.0)
# Camera-following silhouette light. Blender uses these values in the authored
# Layer Weight -> Color Ramp -> Mix Shader graph; player_suit.tres mirrors them
# in Godot because glTF cannot carry arbitrary Blender shader graphs.
RIM_COLOR = (0.20, 1.0, 0.58, 1.0)
RIM_STRENGTH = 1.25
RIM_RAMP_DARK = 0.68
RIM_RAMP_LIGHT = 0.84

# Where the hair is cut out of the dressed sculpt, as a box in that sculpt's own
# metres once it has been turned to face +Y. The other two regions are no longer
# read for colour — see WHITE — but are kept because they are what says the
# figure is divided into three at all, and re-measuring them off the sculpt is
# an hour nobody should have to spend twice.
#
# The boxes are measured off the sculpt and written down, not derived. Landmark
# detection is no use over there, because every landmark it looks for is under
# cloth: run on the dressed figure it reports the ankle at the top of a boot and
# the shoulder out on a flared sleeve. What the numbers are: the hairline crosses
# the brow at 1.52, the coat runs from a hem at 0.66 to a collar at 1.31, and the
# boots stop at 0.45 where the bare leg reappears. The coat's box is also held
# inside |x| < 0.22 so the sample is coat and not the paler skin of the hands
# hanging out of its sleeves.
SCULPT_REGIONS = {
    "hair": {"z": (1.52, 99.0)},
    "tunic": {"z": (0.66, 1.31), "x": 0.22},
    "boots": {"z": (-99.0, 0.45)},
}

# How the hair is carried from the sculpt's head onto this one: `slack` is how
# much looser than the skull it sits, `lift` how far above the crown its own top
# goes as a share of the skull's height, and `stretch` how far its vertical scale
# may depart from the other two.
HAIR_FIT = {"slack": 1.06, "lift": 0.10, "stretch": (0.85, 1.15)}


# --------------------------------------------------------------------------
# Scene helpers
# --------------------------------------------------------------------------

def activate(obj: bpy.types.Object) -> None:
    if bpy.context.object is not None and bpy.context.object.mode != "OBJECT":
        bpy.ops.object.mode_set(mode="OBJECT")
    for other in bpy.context.view_layer.objects:
        other.select_set(False)
    obj.hide_viewport = False
    obj.select_set(True)
    bpy.context.view_layer.objects.active = obj


def world_coords(obj: bpy.types.Object) -> list[Vector]:
    mw = obj.matrix_world
    return [mw @ v.co for v in obj.data.vertices]


def centroid(points: list[Vector]) -> Vector:
    total = Vector()
    for point in points:
        total += point
    return total / max(len(points), 1)


def bounds(points: list[Vector]) -> tuple[Vector, Vector]:
    lo = Vector((min(p.x for p in points), min(p.y for p in points), min(p.z for p in points)))
    hi = Vector((max(p.x for p in points), max(p.y for p in points), max(p.z for p in points)))
    return lo, hi


def faces_forward(coords: list[Vector]) -> bool:
    """Whether this sculpt's toes point +Y, which is the direction of travel.

    A foot is the one part of a body that is decisively longer in front than
    behind, so the sole reaches further from the ankle on the toe side. Faces,
    chests and hair are all far weaker signals on a stylised sculpt, and this
    one's hair reads backwards on every one of them.
    """
    lo, hi = bounds(coords)
    height = hi.z - lo.z
    sole = [p for p in coords if p.z < lo.z + height * 0.04]
    shin = [p for p in coords if lo.z + height * 0.14 < p.z < lo.z + height * 0.2]
    if not sole or not shin:
        raise SystemExit("cannot tell which way the sculpt faces: no feet found")
    ankle_y = sum(p.y for p in shin) / len(shin)
    return (max(p.y for p in sole) - ankle_y) > (ankle_y - min(p.y for p in sole))


def turn_to_face_forward(obj: bpy.types.Object) -> bool:
    """Spin `obj` about Z until its toes point +Y, and bake the turn in."""
    if faces_forward(world_coords(obj)):
        return False
    activate(obj)
    obj.matrix_world = Matrix.Rotation(math.pi, 4, "Z") @ obj.matrix_world
    bpy.ops.object.transform_apply(location=True, rotation=True, scale=True)
    return True


def adjacency(mesh: bpy.types.Mesh) -> dict[int, set[int]]:
    adj: dict[int, set[int]] = collections.defaultdict(set)
    for edge in mesh.edges:
        a, b = edge.vertices
        adj[a].add(b)
        adj[b].add(a)
    return adj


def components(indices: set[int], adj: dict[int, set[int]]) -> list[list[int]]:
    seen: set[int] = set()
    out: list[list[int]] = []
    for start in indices:
        if start in seen:
            continue
        seen.add(start)
        stack = [start]
        group = []
        while stack:
            current = stack.pop()
            group.append(current)
            for neighbour in adj[current]:
                if neighbour in indices and neighbour not in seen:
                    seen.add(neighbour)
                    stack.append(neighbour)
        out.append(group)
    return sorted(out, key=len, reverse=True)


# --------------------------------------------------------------------------
# Landmarks
#
# Every joint below is found by a rule about the mesh rather than by a fraction
# of its height. A fraction is what the first pass used, and it is what put the
# hip 13 cm above the crotch and the head bone in the middle of the skull: the
# settler is 47% leg and 19% head, so any constant borrowed from a normally
# proportioned figure lands somewhere inside the wrong body part.
# --------------------------------------------------------------------------

class Body:
    """Measured joint positions for one T-posed, +Y-facing character mesh."""

    def __init__(self, coords: list[Vector], mesh: bpy.types.Mesh) -> None:
        self.coords = coords
        self.mesh = mesh
        self.adj = adjacency(mesh)
        lo, hi = bounds(coords)
        self.floor = lo.z
        self.top = hi.z
        self.height = hi.z - lo.z
        tol = self.height / 100.0

        self.crotch_z = self._crotch(tol)
        self.hip_z = self.crotch_z + self.height * 0.013
        self.arm_z, self.reach = self._arm_axis()
        self.shoulder_x = self._shoulder_x()
        self.neck_z = self._neck()
        self.neck_base_z, self.skull_z = self._neck_span()
        self.ankle_z = self._ankle()
        self.knee_z = self.ankle_z + (self.hip_z - self.ankle_z) * 0.48

    # -- torso -------------------------------------------------------------

    def slab(self, z: float, half: float, x_limit: float = 1e9) -> list[Vector]:
        return [p for p in self.coords if abs(p.z - z) <= half and abs(p.x) <= x_limit]

    def centre_line(self, z: float) -> float:
        """Front-to-back centre of the torso at `z`, so the spine follows the body."""
        pts = self.slab(z, self.height * 0.0125, x_limit=self.height * 0.1)
        if not pts:
            return 0.0
        return (min(p.y for p in pts) + max(p.y for p in pts)) * 0.5

    def _crotch(self, tol: float) -> float:
        """Lowest height at which the two legs have merged into one solid.

        Below the crotch there is a gap on the mid-plane; above it there is not.
        Scanning for the gap closing is exact and needs no guess about how long
        a leg should be.
        """
        step = self.height / 200.0
        z = self.floor + self.height * 0.2
        while z < self.floor + self.height * 0.7:
            near_axis = [p for p in self.coords if abs(p.z - z) <= step and abs(p.x) <= tol]
            if len(near_axis) >= 4:
                return z
            z += step
        return self.floor + self.height * 0.47

    def _arm_axis(self) -> tuple[float, float]:
        """Height of the outspread arms, and how far they reach."""
        reach = max(abs(p.x) for p in self.coords)
        wing = [p for p in self.coords if abs(p.x) > reach * 0.62]
        zs = [p.z for p in wing]
        return (min(zs) + max(zs)) * 0.5, reach

    def _shoulder_x(self) -> float:
        """Where the arm stops being arm and becomes torso.

        Measured on the height of the column standing at each x, over everything
        from the waist up. An arm slice is one limb thick; a torso slice runs
        from the waist to the crown. The window has to be open at the top for
        that to show - capping it at the arm's own band caps the very difference
        being looked for, which is what first reported the shoulder at half its
        real width.
        """
        upright = [p for p in self.coords if p.z > self.hip_z]
        step = self.height / 200.0
        x = self.reach * 0.9
        thin = None
        while x > self.height * 0.02:
            column = [p for p in upright if abs(abs(p.x) - x) < step]
            if column:
                spread = max(p.z for p in column) - min(p.z for p in column)
                if thin is not None and spread > thin * 2.0:
                    return x + step
                thin = spread if thin is None else min(thin, spread)
            x -= step
        return self.reach * 0.3

    def _section_area(self, z: float, x_limit: float) -> float:
        pts = self.slab(z, self.height * 0.00625, x_limit=x_limit)
        if len(pts) < 4:
            return 1e9
        return ((max(p.x for p in pts) - min(p.x for p in pts))
                * (max(p.y for p in pts) - min(p.y for p in pts)))

    def _neck(self) -> float:
        """Narrowest slice between the shoulders and the crown."""
        limit = self.shoulder_x * 1.4
        step = self.height / 200.0
        best_z, best = self.arm_z, 1e9
        z = self.arm_z + self.height * 0.02
        while z < self.top - self.height * 0.08:
            area = self._section_area(z, limit)
            if area < best:
                best, best_z = area, z
            z += step
        return best_z

    def _neck_span(self) -> tuple[float, float]:
        """Where the neck leaves the shoulders and where the skull starts.

        Both ends are the same test - the slice has grown by half again from the
        neck's narrowest - run once downward and once upward. Taking the narrow
        point itself as the base is what left a 16 mm neck bone: that point is
        the middle of a neck, not the bottom of one.
        """
        limit = self.shoulder_x * 1.4
        step = self.height / 200.0
        narrow = self._section_area(self.neck_z, limit)
        base = self.neck_z
        z = self.neck_z
        while z > self.arm_z - self.height * 0.06:
            if self._section_area(z, limit) > narrow * 1.5:
                base = z
                break
            z -= step
        skull = self.neck_z + self.height * 0.02
        z = self.neck_z
        while z < self.top - self.height * 0.1:
            if self._section_area(z, limit) > narrow * 1.5:
                skull = z
                break
            z += step
        return base, skull

    # -- legs --------------------------------------------------------------

    def leg_slab(self, z: float, side: float) -> list[Vector]:
        half = self.height * 0.00625
        return [p for p in self.coords
                if abs(p.z - z) <= half and p.x * side > self.height * 0.006]

    def _leg_depth(self, z: float) -> float:
        pts = self.leg_slab(z, -1.0)
        if len(pts) < 4:
            return 0.0
        return max(p.y for p in pts) - min(p.y for p in pts)

    def _ankle(self) -> float:
        """Where the shin stops and the foot starts flaring out around it.

        The shin's own depth just below the knee is the reference, and the ankle
        is the highest point below it where the slice has grown by a quarter.
        The reference has to be one height rather than the thinnest of several:
        the leg tapers all the way up, so a minimum taken over the whole shin
        comes from the top of it and sets a threshold the calf already passes.
        """
        step = self.height / 200.0
        reference = self._leg_depth(self.floor + self.height * 0.22)
        if reference <= 0.0:
            return self.floor + self.height * 0.12
        z = self.floor + self.height * 0.3
        while z > self.floor + self.height * 0.01:
            if self._leg_depth(z) > reference * 1.25:
                return z + step
            z -= step
        return self.floor + self.height * 0.12

    def leg_centre(self, z: float, side: float) -> Vector:
        pts = self.leg_slab(z, side)
        if not pts:
            return Vector((side * self.height * 0.07, 0.0, z))
        return Vector((centroid(pts).x, centroid(pts).y, z))

    def foot(self, side: float) -> dict[str, Vector]:
        pts = [p for p in self.coords
               if p.z < self.ankle_z and p.x * side > self.height * 0.006]
        if not pts:
            pts = [p for p in self.coords if p.z < self.ankle_z]
        toe_y = max(p.y for p in pts)
        heel_y = min(p.y for p in pts)
        mid_x = centroid(pts).x
        ankle = self.leg_centre(self.ankle_z, side)
        ankle.x = mid_x
        # The ball carries the toe hinge, so it goes where the sole actually
        # touches down rather than at the tip of an upswept boot.
        sole = [p for p in pts if p.z < self.floor + self.height * 0.03]
        ball_y = (max(p.y for p in sole) if sole else toe_y * 0.6)
        return {
            "ankle": ankle,
            "ball": Vector((mid_x, ball_y, self.floor + self.height * 0.028)),
            "toe": Vector((mid_x, toe_y, self.floor + self.height * 0.022)),
            "heel_y": heel_y,
        }

    # -- arms --------------------------------------------------------------

    def arm_slab(self, x: float, side: float) -> list[Vector]:
        half = self.height * 0.004
        band = self.height * 0.06
        return [p for p in self.coords
                if abs(p.x * side - x) <= half and abs(p.z - self.arm_z) < band]

    def arm_centre(self, x: float, side: float) -> Vector:
        pts = self.arm_slab(x, side)
        if not pts:
            return Vector((side * x, 0.0, self.arm_z))
        c = centroid(pts)
        return Vector((side * x, c.y, c.z))

    def _arm_flatness(self, x: float, side: float) -> float:
        pts = self.arm_slab(x, side)
        if len(pts) < 6:
            return 0.0
        dy = max(p.y for p in pts) - min(p.y for p in pts)
        dz = max(p.z for p in pts) - min(p.z for p in pts)
        return dy / max(dz, 1e-5)

    def wrist_x(self, side: float) -> float:
        """Where the round forearm starts flattening into the hand.

        A hand is wide and thin, a forearm is round, so the aspect ratio of the
        slice separates them where the area cannot - this forearm thickens all
        the way to the palm. It is the *start* of the flattening that is wanted,
        not the flattest slice: taking the peak puts the wrist out among the
        knuckles, and the short digits behind it are then never seen at all.
        """
        step = self.height / 400.0
        first = self.shoulder_x + (self.reach - self.shoulder_x) * 0.4
        stations = []
        x = first
        while x < self.reach - self.height * 0.02:
            stations.append((x, self._arm_flatness(x, side)))
            x += step
        if not stations:
            return first
        peak = max(stations, key=lambda s: s[1])
        threshold = 1.0 + (peak[1] - 1.0) * 0.3
        for x, flat in stations:
            if flat >= threshold:
                return x
        return peak[0]

    def elbow_x(self, side: float, wrist: float) -> float:
        """Thinnest slice in the middle of the upper arm-to-wrist span.

        The search is clamped to the middle sixth because this arm is a smooth
        taper with no anatomical elbow in it: left free, the thinnest slice lands
        wherever the sculpt happens to pinch, and it landed in two different
        places on the two arms of a symmetric mesh.
        """
        step = self.height / 400.0
        joint = self.shoulder_x - self.height * 0.02
        lo = joint + (wrist - joint) * 0.44
        hi = joint + (wrist - joint) * 0.56
        best_x, best = (lo + hi) * 0.5, 1e9
        x = lo
        while x < hi:
            pts = self.arm_slab(x, side)
            if len(pts) >= 6:
                dy = max(p.y for p in pts) - min(p.y for p in pts)
                dz = max(p.z for p in pts) - min(p.z for p in pts)
                if dy * dz < best:
                    best, best_x = dy * dz, x
            x += step
        return best_x

    def digits(self, side: float, wrist: float) -> list[dict]:
        """Split the hand into fingers by watching the mesh come apart.

        Sweeping a cut plane in from the fingertips, each digit appears as its own
        island before the islands merge back into the palm; the merge is the
        knuckle. This finds however many digits the sculpt has - four here, not
        the five a layout table would have assumed - and finds them where they
        actually are.

        New islands are only accepted in the outer part of the hand. Further in,
        an island is a hole in the palm rather than a finger, and the sweep still
        has to run all the way to the wrist so the last digits get their length.
        """
        hand = {i for i, p in enumerate(self.coords) if p.x * side > wrist}
        if not hand:
            return []
        step = self.height / 400.0
        far = max(self.coords[i].x * side for i in hand)
        births_end = wrist + (far - wrist) * 0.3
        seeds: list[dict] = []
        cut = far - step
        while cut > wrist:
            for group in components({i for i in hand if self.coords[i].x * side > cut}, self.adj):
                if len(group) < 6:
                    continue
                members = set(group)
                touching = [s for s in seeds if s["verts"] & members]
                if not touching:
                    if cut > births_end:
                        seeds.append({"verts": members, "done": False})
                elif len(touching) == 1 and not touching[0]["done"]:
                    touching[0]["verts"] = members
                else:
                    # Two digits have met: this island is the palm, so both stop.
                    for seed in touching:
                        seed["done"] = True
            cut -= step
        out = []
        for seed in seeds:
            pts = [self.coords[i] for i in seed["verts"]]
            if len(pts) < 8:
                continue
            inner = min(p.x * side for p in pts)
            base = centroid([p for p in pts if p.x * side < inner + step * 2.0])
            tip = max(pts, key=lambda p: p.x * side)
            out.append({"base": base, "tip": Vector(tip), "size": len(pts)})
        # Palm-down in a T-pose puts the thumb forward, so +Y orders the hand.
        out.sort(key=lambda d: d["base"].y)
        return out

    def report(self) -> None:
        print("body: height={0:.3f} crotch={1:.3f} hip={2:.3f} knee={3:.3f} ankle={4:.3f}".format(
            self.height, self.crotch_z, self.hip_z, self.knee_z, self.ankle_z))
        print("      arm_z={0:.3f} reach={1:.3f} shoulder_x={2:.3f} neck={3:.3f}..{4:.3f} skull={5:.3f}".format(
            self.arm_z, self.reach, self.shoulder_x, self.neck_base_z, self.neck_z, self.skull_z))


# --------------------------------------------------------------------------
# Rig
# --------------------------------------------------------------------------

FINGER_NAMES = ["Index", "Middle", "Ring", "Little"]


def build_armature(body: Body) -> bpy.types.Object:
    data = bpy.data.armatures.new("CharacterSkeleton")
    rig = bpy.data.objects.new("CharacterRig", data)
    bpy.context.collection.objects.link(rig)
    activate(rig)
    bpy.ops.object.mode_set(mode="EDIT")
    edit = data.edit_bones

    def add(name, parent, head, tail, connect=False):
        bone = edit.new(name)
        bone.head = Vector(head)
        bone.tail = Vector(tail)
        if (bone.tail - bone.head).length < 1e-4:
            bone.tail = bone.head + Vector((0.0, 0.0, body.height * 0.02))
        if parent is not None:
            bone.parent = edit[parent]
            bone.use_connect = connect
        return bone

    # Spine: four bones spread between the hip and the base of the neck, each
    # following the torso's own front-to-back centre so the chain sits inside
    # the body rather than cutting the corner of a leaning back.
    span = body.neck_base_z - body.hip_z
    stops = [body.hip_z + span * f for f in (0.0, 0.32, 0.62, 0.84)]
    points = [Vector((0.0, body.centre_line(z), z)) for z in stops]
    neck = Vector((0.0, body.centre_line(body.neck_base_z), body.neck_base_z))
    skull = Vector((0.0, body.centre_line(body.skull_z), body.skull_z))
    crown = Vector((0.0, skull.y, body.top))

    add("Root", None, Vector((0.0, 0.0, body.floor)),
        Vector((0.0, 0.0, body.floor + body.height * 0.08)))
    add("Hips", "Root", points[0], points[1])
    add("Spine", "Hips", points[1], points[2], True)
    add("Chest", "Spine", points[2], points[3], True)
    add("UpperChest", "Chest", points[3], neck, True)
    add("Neck", "UpperChest", neck, skull, True)
    add("Head", "Neck", skull, crown, True)

    # Only the left half is measured; the right is its reflection. The mesh is
    # symmetric, so any difference between the two sides is measurement noise,
    # and noise in a limb is a rig whose two arms bend in different places.
    def mirror(point: Vector, side: float) -> Vector:
        return Vector((point.x * -side, point.y, point.z))

    wrist_x = body.wrist_x(-1.0)
    elbow_x = body.elbow_x(-1.0, wrist_x)
    # The joint sits inside the silhouette, not out on the skin where the arm
    # meets the torso, or every shoulder rotation shears the armpit.
    joint_x = body.shoulder_x - body.height * 0.02
    left_shoulder = body.arm_centre(joint_x, -1.0)
    left_elbow = body.arm_centre(elbow_x, -1.0)
    left_wrist = body.arm_centre(wrist_x, -1.0)
    left_clavicle = Vector((-body.height * 0.035, left_shoulder.y,
                            left_shoulder.z + body.height * 0.012))
    left_digits = body.digits(-1.0, wrist_x)
    left_palm = (centroid([d["base"] for d in left_digits]) if left_digits
                 else body.arm_centre(min(wrist_x + body.height * 0.03, body.reach), -1.0))

    for prefix, side in (("Left", -1.0), ("Right", 1.0)):
        shoulder = mirror(left_shoulder, side)
        add(f"{prefix}Shoulder", "UpperChest", mirror(left_clavicle, side), shoulder)
        add(f"{prefix}UpperArm", f"{prefix}Shoulder", shoulder, mirror(left_elbow, side), True)
        add(f"{prefix}LowerArm", f"{prefix}UpperArm",
            mirror(left_elbow, side), mirror(left_wrist, side), True)
        add(f"{prefix}Hand", f"{prefix}LowerArm",
            mirror(left_wrist, side), mirror(left_palm, side), True)

        # The most forward digit on a palm-down T-pose is the thumb; it gets two
        # bones and the rest three, which is the humanoid profile's shape.
        for index, digit in enumerate(reversed(left_digits)):
            if index == 0:
                label, joints = "Thumb", 2
            else:
                label = FINGER_NAMES[min(index - 1, len(FINGER_NAMES) - 1)]
                joints = 3
            start = mirror(digit["base"], side)
            end = mirror(digit["tip"], side)
            parent = f"{prefix}Hand"
            for j in range(joints):
                name = f"{prefix}{label}{j + 1}"
                add(name, parent, start.lerp(end, j / joints),
                    start.lerp(end, (j + 1) / joints), connect=(j > 0))
                parent = name

    # The hip joint takes its height from the pelvis but its width from the top
    # of the thigh, just under the crotch. Measured at hip height the two legs
    # have already merged, so the "leg" there is half a pelvis and its centre is
    # most of the way to the midline - which builds a rig knock-kneed from the
    # hip down.
    left_hip = Vector((body.leg_centre(body.crotch_z - body.height * 0.02, -1.0).x,
                       body.centre_line(body.hip_z), body.hip_z))
    left_knee = body.leg_centre(body.knee_z, -1.0)
    left_foot = body.foot(-1.0)
    for prefix, side in (("Left", -1.0), ("Right", 1.0)):
        hip = mirror(left_hip, side)
        knee = mirror(left_knee, side)
        ankle = mirror(left_foot["ankle"], side)
        ball = mirror(left_foot["ball"], side)
        add(f"{prefix}UpperLeg", "Hips", hip, knee)
        add(f"{prefix}LowerLeg", f"{prefix}UpperLeg", knee, ankle, True)
        add(f"{prefix}Foot", f"{prefix}LowerLeg", ankle, ball, True)
        add(f"{prefix}Toes", f"{prefix}Foot", ball, mirror(left_foot["toe"], side), True)

    bpy.ops.armature.calculate_roll(type="GLOBAL_POS_Y")
    bpy.ops.object.mode_set(mode="OBJECT")
    data.bones["Root"].use_deform = False
    print("rig: {0} bones".format(len(data.bones)))
    return rig


def bind(mesh_obj: bpy.types.Object, rig: bpy.types.Object) -> None:
    activate(mesh_obj)
    mesh_obj.select_set(True)
    rig.select_set(True)
    bpy.context.view_layer.objects.active = rig
    try:
        bpy.ops.object.parent_set(type="ARMATURE_AUTO")
    except RuntimeError as error:
        print("heat weighting failed, falling back to envelopes:", error)
        bpy.ops.object.parent_set(type="ARMATURE_ENVELOPE")

    activate(mesh_obj)
    bpy.ops.object.mode_set(mode="WEIGHT_PAINT")
    try:
        # Light: a heavy smooth is what welded the two thighs together last time,
        # and a crotch that shares weights cannot take a stride.
        bpy.ops.object.vertex_group_smooth(group_select_mode="ALL", factor=0.25, repeat=2)
    except RuntimeError as error:
        print("weight smooth skipped:", error)
    bpy.ops.object.mode_set(mode="OBJECT")
    try:
        bpy.ops.object.vertex_group_limit_total(group_select_mode="ALL", limit=4)
        bpy.ops.object.vertex_group_normalize_all(group_select_mode="ALL", lock_active=False)
    except RuntimeError as error:
        print("weight cleanup skipped:", error)


# --------------------------------------------------------------------------
# Garments
#
# Two ways of making one, and which is which is decided by whether the garment
# has to follow the body. A tunic and a boot do, so they are shells grown off
# this body's own faces; hair does not, so it is cut out of the dressed sculpt
# and set on the skull.
# --------------------------------------------------------------------------

def load_module(filename: str):
    """Import a sibling build script by path.

    Blender runs `--python` scripts with the script's own directory off
    `sys.path`, so a plain import of a file sitting next to this one fails.
    """
    import importlib.util

    path = os.path.join(SOURCE_DIR, filename)
    spec = importlib.util.spec_from_file_location(filename[:-3] + "_settler", path)
    module = importlib.util.module_from_spec(spec)
    spec.loader.exec_module(module)
    return module


def shell_specs(apparel, landmarks) -> list[dict]:
    """The tunic, the boots and the goggles, as regions of this body in cloth.

    Written in the same shape as `build_apparel.garment_specs`, and consumed by
    the same `carve_shell`. Every height is read off a bone, so the two survive
    a reproportioned character.
    """
    L = landmarks
    ramp = apparel.ramp
    near_z = apparel.near_z
    up = Vector((0.0, 0.0, 1.0))
    down = Vector((0.0, 0.0, -1.0))

    def near_x(x: float, band: float):
        def test(point: Vector) -> bool:
            return abs(abs(point.x) - abs(x)) < band
        return test

    # Mid-shin, which is where the sculpt's boots stop. Taken off the knee
    # rather than off the floor so it stays mid-shin on a longer leg.
    boot_top = L.ankle.z + (L.knee.z - L.ankle.z) * 0.52

    def boot_region(point: Vector) -> bool:
        return point.z < boot_top

    def boot_displace(point: Vector, normal: Vector) -> Vector:
        # Thick at the sole and again at the collar: that pair of bulges is what
        # separates a boot from a sock, and the sculpt's are heavy ones.
        sole = 1.0 - ramp(point.z, L.floor, L.floor + 0.06)
        cuff = ramp(point.z, boot_top - 0.055, boot_top)
        return normal * (0.016 + 0.018 * sole + 0.011 * cuff)

    def boot_post(point: Vector) -> Vector:
        # Anything pushed under the floor becomes a flat sole standing on it.
        return Vector((point.x, point.y, max(point.z, L.floor)))

    # The hem sits just above the crotch because that is as low as a garment cut
    # from a body can go: below it the shell splits with the legs and a tunic
    # becomes a pair of shorts. The sculpt's coat does reach mid-thigh, and a
    # skirt that hangs free of the legs is not something this method can make.
    tunic_hem = L.hip.z - 0.010
    # Up the neck rather than at its base, so the shoulders are inside the
    # garment with room to spare. Cutting level with the shoulder line is what
    # left the last one with bare shoulders and two shredded straps.
    tunic_collar = L.neck.z + (L.skull.z - L.neck.z) * 0.35
    # A cap sleeve: a third of the way to the elbow, which covers the shoulder
    # and stops before the arm starts bending underneath it.
    sleeve_x = L.shoulder.x + (L.elbow.x - L.shoulder.x) * 0.35

    def tunic_region(point: Vector) -> bool:
        return tunic_hem < point.z < tunic_collar and abs(point.x) < sleeve_x

    def tunic_displace(point: Vector, normal: Vector) -> Vector:
        hem = 1.0 - ramp(point.z, tunic_hem, tunic_hem + 0.07)
        collar = ramp(point.z, tunic_collar - 0.05, tunic_collar)
        # The flare is what makes this a tunic and not a leotard. Following the
        # body all the way down means following it around the crotch, and a hem
        # that hugs a hip joint reads as swimwear whatever colour it is. Pushing
        # the bottom of it out from the vertical axis - not along the surface
        # normal, which at the crotch points inward between the legs - hangs the
        # cloth clear instead, and the hem plane keeps the rim flat and level.
        skirt = 1.0 - ramp(point.z, tunic_hem, tunic_hem + 0.16)
        radial = Vector((point.x, point.y, 0.0))
        flare = radial.normalized() * (0.052 * skirt ** 1.5) if radial.length > 1e-6 \
            else Vector()
        return normal * (0.013 + 0.008 * hem + 0.007 * collar) + flare

    return [
        {
            "slug": "c3_boots",
            "name": "apparel_c3_boots",
            "colour": WHITE,
            "roughness": 0.55,
            "region": boot_region,
            "displace": boot_displace,
            "post": boot_post,
            "cuts": [(Vector((0.0, 0.0, boot_top)), up, near_z(boot_top, 0.06))],
        },
        {
            "slug": "c3_tunic",
            "name": "apparel_c3_tunic",
            "colour": WHITE,
            "roughness": 0.76,
            "region": tunic_region,
            "displace": tunic_displace,
            "post": None,
            "cuts": [
                (Vector((0.0, 0.0, tunic_collar)), up,
                 near_z(tunic_collar, 0.05, sleeve_x * 1.3)),
                (Vector((0.0, 0.0, tunic_hem)), down,
                 near_z(tunic_hem, 0.05, sleeve_x * 1.3)),
                (Vector((sleeve_x, 0.0, 0.0)), Vector((1.0, 0.0, 0.0)),
                 near_x(sleeve_x, 0.05)),
                (Vector((-sleeve_x, 0.0, 0.0)), Vector((-1.0, 0.0, 0.0)),
                 near_x(sleeve_x, 0.05)),
            ],
        },
        # Not written here, because a pair of goggles is the same garment on
        # both bodies: `build_apparel` owns the shape and this asks for it in
        # this body's colour.
        apparel.goggles_spec(landmarks, slug="c3_goggles", name="apparel_c3_goggles",
                             colour=WHITE, roughness=0.30),
    ]


def pair_clearance(obj: bpy.types.Object) -> float | None:
    """Smallest gap between the two halves of a garment that comes in a pair.

    A boot shell is grown off the body's own foot, so the two can only touch if
    the offset is thicker than half the gap between the ankles. That is a number
    worth printing rather than a thing to look at: two shoes meeting is visible
    in a render only from straight on, and only when the light is right.

    `None` for a garment that crosses the midline in one piece, where the two
    sides are the same surface and the answer is always zero.
    """
    from mathutils.kdtree import KDTree

    left = [v.co.copy() for v in obj.data.vertices if v.co.x < 0.0]
    right = [v.co.copy() for v in obj.data.vertices if v.co.x > 0.0]
    if not left or not right:
        return None
    if any(abs(v.co.x) < 1e-3 for v in obj.data.vertices):
        return None
    tree = KDTree(len(right))
    for index, point in enumerate(right):
        tree.insert(point, index)
    tree.balance()
    return min(tree.find(point)[2] for point in left)


def push_out(points: list[Vector], adj: dict[int, set[int]], tree: BVHTree,
             clearance: float, rounds: int = 3, smoothing: int = 6) -> int:
    """Lift any garment vertex that ended up inside the body back onto it.

    The correction is *smoothed across the mesh before it is applied*, and that
    is the whole of the difference between cloth and confetti. Snapping each
    buried vertex individually onto the skin - which is what this used to do -
    leaves its neighbours a millimetre away exactly where they were, so a
    garment lying close to the body comes out as a fringe of alternating spikes
    and holes over its whole surface rather than a poke-through here and there.
    Spreading the same displacement over the neighbourhood lifts the cloth as a
    bulge instead, which is what a real garment does over a shoulder.

    Smoothing takes the peak off the correction as well as the edges, so the
    pass is run a few times over and converges rather than solving in one go.
    """
    touched: set[int] = set()
    for _ in range(rounds):
        delta = [Vector() for _ in points]
        pending = 0
        for index, point in enumerate(points):
            location, normal, _, _ = tree.find_nearest(point)
            if location is None:
                continue
            depth = clearance - (point - location).dot(normal)
            if depth <= 0.0:
                continue
            delta[index] = normal * depth
            touched.add(index)
            pending += 1
        if pending == 0:
            break
        for _ in range(smoothing):
            blurred = []
            for index, own in enumerate(delta):
                neighbours = adj[index]
                if not neighbours:
                    blurred.append(own)
                    continue
                total = own.copy()
                for other in neighbours:
                    total += delta[other]
                blurred.append(total / (len(neighbours) + 1))
            delta = blurred
        for index in range(len(points)):
            points[index] += delta[index]
    return len(touched)


def load_dressed() -> bpy.types.Object | None:
    """Bring in the dressed sculpt, name it, and turn it to face +Y."""
    with bpy.data.libraries.load(DRESSED_BLEND, link=False) as (src, dst):
        dst.objects = list(src.objects)
    source = None
    for obj in dst.objects:
        if obj is None:
            continue
        if obj.type == "MESH" and "Icosphere" not in obj.name:
            if source is None or len(obj.data.vertices) > len(source.data.vertices):
                source = obj
    if source is None:
        return None
    bpy.context.collection.objects.link(source)
    source.name = "DressedSource"
    turned = turn_to_face_forward(source)
    coords = world_coords(source)
    lo, hi = bounds(coords)
    print("dressed sculpt: height={0:.3f} reach={1:.3f} turned={2}".format(
        hi.z - lo.z, max(abs(p.x) for p in coords), turned))
    return source


def cut_hair(body: Body, body_obj: bpy.types.Object, source: bpy.types.Object,
             colour: tuple) -> bpy.types.Object | None:
    """Carve the sculpt's hair out of its head and set it on this one's.

    Hair is the one piece worth carrying across, because it is the sculpt's
    silhouette and no offset of a scalp would ever produce it. It is also the
    one piece a coarse fit suits: it hangs off the head rather than following a
    body, so all it has to do is sit around the skull at about the right size.
    """
    hair = source.copy()
    hair.data = source.data.copy()
    hair.name = "apparel_c3_hair"
    hair.modifiers.clear()
    bpy.context.collection.objects.link(hair)

    keep = SCULPT_REGIONS["hair"]
    activate(hair)
    bpy.ops.object.mode_set(mode="EDIT")
    bm = bmesh.from_edit_mesh(hair.data)
    bm.faces.ensure_lookup_table()
    doomed = [f for f in bm.faces if not in_box(f.calc_center_median(), keep)]
    bmesh.ops.delete(bm, geom=doomed, context="FACES")
    bmesh.update_edit_mesh(hair.data)
    bpy.ops.mesh.select_all(action="SELECT")
    bpy.ops.mesh.delete_loose()
    bpy.ops.object.mode_set(mode="OBJECT")

    if len(hair.data.polygons) < 20:
        print("WARNING: hair cut came out empty")
        bpy.data.objects.remove(hair, do_unlink=True)
        return None

    skull_lo, skull_hi = bounds([p for p in body.coords if p.z >= body.skull_z])
    verts = [v.co.copy() for v in hair.data.vertices]
    scale, offset = fit_to_box(skull_lo, skull_hi, verts, HAIR_FIT)
    placed = [Vector((p.x * scale.x + offset.x,
                      p.y * scale.y + offset.y,
                      p.z * scale.z + offset.z)) for p in verts]
    tree = BVHTree.FromObject(body_obj, bpy.context.evaluated_depsgraph_get())
    buried = push_out(placed, adjacency(hair.data), tree, body.height * 0.006)
    for vertex, point in zip(hair.data.vertices, placed):
        vertex.co = point
    hair.data.update()

    material = bpy.data.materials.new("C3Hair")
    material.use_nodes = True
    bsdf = material.node_tree.nodes.get("Principled BSDF")
    if bsdf is not None:
        bsdf.inputs["Base Color"].default_value = colour
        bsdf.inputs["Roughness"].default_value = 0.68
    hair.data.materials.clear()
    hair.data.materials.append(material)

    low, high = bounds(placed)
    print("  hair   {0:5d} faces  scale={1:.2f}/{2:.2f}  z[{3:.2f},{4:.2f}]"
          "  lifted {5}/{6}".format(
              len(hair.data.polygons), scale.x, scale.z, low.z, high.z,
              buried, len(placed)))
    return hair


def in_box(point: Vector, box: dict) -> bool:
    z_low, z_high = box.get("z", (-99.0, 99.0))
    return z_low <= point.z <= z_high and abs(point.x) <= box.get("x", 99.0)


def fit_to_box(target_lo: Vector, target_hi: Vector, verts: list[Vector], fit: dict
               ) -> tuple[Vector, Vector]:
    """Scale and offset carrying `verts` onto the target box, hanging from its top.

    One scale across x and y, so the piece stays as round as it was modelled; an
    axis-by-axis fit between two sculpts this different stretches it into
    whatever shape the difference happens to be. Height is the exception and is
    allowed to depart within `stretch`.
    """
    lo, hi = bounds(verts)
    size = hi - lo
    target = (target_hi - target_lo) * fit["slack"]

    def ratio(axis: int) -> float:
        return target[axis] / size[axis] if size[axis] > 1e-4 else 1.0

    flat = (ratio(0) + ratio(1)) * 0.5
    low, high = fit["stretch"]
    scale = Vector((flat, flat, max(min(ratio(2), flat * high), flat * low)))

    centre = (lo + hi) * 0.5
    target_centre = (target_lo + target_hi) * 0.5
    lift = (target_hi.z - target_lo.z) * fit["lift"]
    return scale, Vector((target_centre.x - centre.x * scale.x,
                          target_centre.y - centre.y * scale.y,
                          target_hi.z + lift - hi.z * scale.z))


def extract_garments(body: Body, body_obj: bpy.types.Object,
                     rig: bpy.types.Object) -> list[bpy.types.Object]:
    if not os.path.isfile(DRESSED_BLEND):
        print("WARNING: dressed.blend missing, no garments built")
        return []
    source = load_dressed()
    if source is None:
        print("WARNING: no mesh in dressed.blend")
        return []

    collection = bpy.data.collections.get("Apparel") or bpy.data.collections.new("Apparel")
    if collection.name not in bpy.context.scene.collection.children:
        bpy.context.scene.collection.children.link(collection)

    made = []
    hair = cut_hair(body, body_obj, source, WHITE)
    if hair is not None:
        transfer_weights(body_obj, hair)
        hair.parent = rig
        hair.modifiers.new(name="Armature", type="ARMATURE").object = rig
        collection.objects.link(hair)
        if hair.name in bpy.context.scene.collection.objects:
            bpy.context.scene.collection.objects.unlink(hair)
        made.append(hair)
    bpy.data.objects.remove(source, do_unlink=True)

    apparel = load_module("build_apparel.py")
    landmarks = apparel.Landmarks(body_obj, rig)
    for spec in shell_specs(apparel, landmarks):
        shell = apparel.build_garment(body_obj, rig, spec, collection)
        made.append(shell)
        gap = pair_clearance(shell)
        print("  {0:<6} {1:5d} faces  z[{2:.2f},{3:.2f}]  {4}".format(
            spec["slug"].removeprefix("c3_"), len(shell.data.polygons),
            min(v.co.z for v in shell.data.vertices),
            max(v.co.z for v in shell.data.vertices),
            "one piece" if gap is None else "left-to-right gap {0:.3f} m".format(gap)))
    return made


def transfer_weights(source: bpy.types.Object, target: bpy.types.Object) -> None:
    activate(target)
    target.vertex_groups.clear()
    for group in source.vertex_groups:
        target.vertex_groups.new(name=group.name)
    modifier = target.modifiers.new(name="WeightTransfer", type="DATA_TRANSFER")
    modifier.object = source
    modifier.use_vert_data = True
    modifier.data_types_verts = {"VGROUP_WEIGHTS"}
    modifier.vert_mapping = "POLYINTERP_NEAREST"
    bpy.ops.object.modifier_apply(modifier=modifier.name)
    try:
        bpy.ops.object.vertex_group_normalize_all(group_select_mode="ALL", lock_active=False)
    except RuntimeError:
        pass


# --------------------------------------------------------------------------
# Animation and export
# --------------------------------------------------------------------------

def bake_locomotion(rig: bpy.types.Object, body: Body) -> None:
    """Author the shared locomotion clips against this body's measurements."""
    anim = load_module("build_animations.py")
    bones = rig.data.bones

    def length(name: str) -> float:
        bone = bones[name]
        return (bone.tail_local - bone.head_local).length

    def from_down(name: str) -> float:
        bone = bones[name]
        direction = (bone.tail_local - bone.head_local).normalized()
        return math.degrees(math.acos(max(-1.0, min(1.0, direction.dot(Vector((0, 0, -1)))))))

    anim.LEG_ROOT_HEIGHT = bones["LeftUpperLeg"].head_local.z
    anim.ANKLE_HEIGHT = bones["LeftFoot"].head_local.z
    anim.THIGH_LENGTH = length("LeftUpperLeg")
    anim.SHIN_LENGTH = length("LeftLowerLeg")
    anim.ARM_REST_OUT = from_down("LeftUpperArm")
    anim.FOREARM_REST_OUT = from_down("LeftLowerArm")
    # The astronaut's forearm rests 4 degrees wider than its upper arm, which is
    # what keeps its hands off its hips. This rig rests in a true T, so the flare
    # is whatever the measurement says and usually nothing.
    anim.FOREARM_FLARE = max(0.0, anim.FOREARM_REST_OUT - anim.ARM_REST_OUT)
    # Hip dips, crouch depths and the slide's reach are all written in metres
    # against a 1.45 m body.
    anim.BODY_SCALE = body.height / 1.45
    # A stride is leg length times the swing angle, so a body that is 47% leg
    # rather than 36% would out-step its own height at the authored angles.
    astronaut_leg = 0.525 / 1.45
    settler_leg = anim.LEG_ROOT_HEIGHT / body.height
    anim.STRIDE_SCALE = astronaut_leg / settler_leg
    print("animation: leg_root={0:.3f} ankle={1:.3f} thigh={2:.3f} shin={3:.3f}".format(
        anim.LEG_ROOT_HEIGHT, anim.ANKLE_HEIGHT, anim.THIGH_LENGTH, anim.SHIN_LENGTH))
    print("           arm_out={0:.1f} forearm_out={1:.1f} body_scale={2:.2f} stride={3:.2f}".format(
        anim.ARM_REST_OUT, anim.FOREARM_REST_OUT, anim.BODY_SCALE, anim.STRIDE_SCALE))
    anim.bake_into_open_file(OUT_BLEND, OUT_GLB)


def export_garment(garment: bpy.types.Object, rig: bpy.types.Object) -> None:
    path = os.path.join(APPAREL_DIR, garment.name + ".glb")
    if bpy.context.object is not None and bpy.context.object.mode != "OBJECT":
        bpy.ops.object.mode_set(mode="OBJECT")
    for obj in bpy.context.view_layer.objects:
        obj.select_set(False)
    for obj in (garment, rig):
        obj.hide_viewport = False
        obj.select_set(True)
    bpy.context.view_layer.objects.active = rig
    bpy.ops.export_scene.gltf(
        filepath=path,
        export_format="GLB",
        use_selection=True,
        export_apply=True,
        export_skins=True,
        export_animations=False,
        export_yup=True,
    )
    print("  wrote", os.path.basename(path),
          "({0:.0f} KB)".format(os.path.getsize(path) / 1024.0))


def paint_body(mesh_obj: bpy.types.Object, texture_path: str) -> None:
    material = bpy.data.materials.get("SettlerSkin") or bpy.data.materials.new("SettlerSkin")
    material.use_nodes = True
    bsdf = material.node_tree.nodes.get("Principled BSDF")
    if bsdf is not None:
        bsdf.inputs["Base Color"].default_value = WHITE
        bsdf.inputs["Roughness"].default_value = 0.72
        texture = material.node_tree.nodes.get("SettlerSkinTexture")
        if texture is None:
            texture = material.node_tree.nodes.new("ShaderNodeTexImage")
            texture.name = "SettlerSkinTexture"
            texture.label = "Default selectable skin"
        texture.image = bpy.data.images.load(texture_path, check_existing=False)
        material.node_tree.links.new(texture.outputs["Color"], bsdf.inputs["Base Color"])
    mesh_obj.data.materials.clear()
    mesh_obj.data.materials.append(material)


def add_camera_rim(material: bpy.types.Material) -> None:
    """Build the editable camera-rim graph from the Render Recipes layout."""
    material.use_nodes = True
    tree = material.node_tree
    nodes = tree.nodes
    links = tree.links
    bsdf = nodes.get("Principled BSDF")
    output = nodes.get("Material Output")
    if bsdf is None or output is None:
        raise RuntimeError("camera rim needs Principled BSDF and Material Output: "
                           + material.name)

    layer_weight = nodes.get("Camera Rim Layer Weight")
    if layer_weight is None:
        layer_weight = nodes.new("ShaderNodeLayerWeight")
        layer_weight.name = "Camera Rim Layer Weight"
    layer_weight.label = "Camera-facing rim mask"
    layer_weight.inputs["Blend"].default_value = 0.35
    layer_weight.location = (120.0, -160.0)

    ramp = nodes.get("Camera Rim Color Ramp")
    if ramp is None:
        ramp = nodes.new("ShaderNodeValToRGB")
        ramp.name = "Camera Rim Color Ramp"
    ramp.label = "Rim thickness and sharpness"
    ramp.color_ramp.interpolation = "EASE"
    ramp.color_ramp.elements[0].position = RIM_RAMP_DARK
    ramp.color_ramp.elements[0].color = (0.0, 0.0, 0.0, 1.0)
    ramp.color_ramp.elements[-1].position = RIM_RAMP_LIGHT
    ramp.color_ramp.elements[-1].color = (1.0, 1.0, 1.0, 1.0)
    ramp.location = (340.0, -160.0)

    emission = nodes.get("Camera Rim Emission")
    if emission is None:
        emission = nodes.new("ShaderNodeEmission")
        emission.name = "Camera Rim Emission"
    emission.label = "Neon green rim"
    emission.inputs["Color"].default_value = RIM_COLOR
    emission.inputs["Strength"].default_value = RIM_STRENGTH
    emission.location = (350.0, 80.0)

    mix = nodes.get("Camera Rim Mix Shader")
    if mix is None:
        mix = nodes.new("ShaderNodeMixShader")
        mix.name = "Camera Rim Mix Shader"
    mix.label = "Base surface + camera rim"
    mix.location = (590.0, 120.0)
    output.location = (820.0, 120.0)

    # Replace only the four links owned by this rim graph. Texture-to-Principled
    # links stay intact, so selectable skins still author and preview correctly.
    for socket in (ramp.inputs["Fac"], mix.inputs[0], mix.inputs[1],
                   mix.inputs[2], output.inputs["Surface"]):
        for link in list(socket.links):
            links.remove(link)
    links.new(layer_weight.outputs["Fresnel"], ramp.inputs["Fac"])
    links.new(ramp.outputs["Color"], mix.inputs[0])
    links.new(bsdf.outputs["BSDF"], mix.inputs[1])
    links.new(emission.outputs["Emission"], mix.inputs[2])
    links.new(mix.outputs["Shader"], output.inputs["Surface"])


def add_camera_rim_to_character() -> list[str]:
    """Put the rim on the body and every garment visible in the work blend."""
    rimmed: list[str] = []
    seen: set[int] = set()
    for obj in bpy.data.objects:
        if obj.type != "MESH":
            continue
        for slot in obj.material_slots:
            material = slot.material
            if material is None or material.as_pointer() in seen:
                continue
            seen.add(material.as_pointer())
            add_camera_rim(material)
            rimmed.append(material.name)
    if not rimmed:
        raise RuntimeError("character 3 has no materials to receive the camera rim")
    return rimmed


def load_body() -> bpy.types.Object:
    bpy.ops.wm.open_mainfile(filepath=SRC_BLEND)
    if bpy.context.object is not None and bpy.context.object.mode != "OBJECT":
        bpy.ops.object.mode_set(mode="OBJECT")
    mesh_obj = None
    for obj in bpy.data.objects:
        if obj.type == "MESH" and "Icosphere" not in obj.name:
            if mesh_obj is None or len(obj.data.vertices) > len(mesh_obj.data.vertices):
                mesh_obj = obj
    if mesh_obj is None:
        raise SystemExit("no body mesh in " + SRC_BLEND)
    for obj in list(bpy.data.objects):
        if obj is not mesh_obj:
            bpy.data.objects.remove(obj, do_unlink=True)
    mesh_obj.name = "Character"
    for modifier in list(mesh_obj.modifiers):
        mesh_obj.modifiers.remove(modifier)
    mesh_obj.vertex_groups.clear()
    mesh_obj.parent = None
    mesh_obj.matrix_world = Matrix.Identity(4)
    activate(mesh_obj)
    bpy.ops.object.transform_apply(location=True, rotation=True, scale=True)
    if turn_to_face_forward(mesh_obj):
        print("body: arrived facing -Y, turned to +Y")
    return mesh_obj


def main() -> None:
    mesh_obj = load_body()
    body = Body(world_coords(mesh_obj), mesh_obj.data)
    print("settler body:")
    body.report()
    for side, label in ((-1.0, "left"), (1.0, "right")):
        wrist = body.wrist_x(side)
        found = body.digits(side, wrist)
        print("  {0} hand: wrist_x={1:.3f} elbow_x={2:.3f} digits={3}".format(
            label, wrist, body.elbow_x(side, wrist),
            [(round(d["base"].y, 3), d["size"]) for d in found]))
    rig = build_armature(body)
    bind(mesh_obj, rig)

    garments = extract_garments(body, mesh_obj, rig)
    # Garments export first: the animation bake re-exports the body .glb on its
    # way out and selects only the body to do it.
    print("exporting garments:")
    for garment in garments:
        export_garment(garment, rig)

    # Unwrap after the shell garments have been cut. They inherit every mesh
    # attribute the body has at that moment, and carrying this atlas into four
    # untextured garment GLBs adds half a megabyte with nothing to draw from it.
    skins = load_module("character_3_skins.py")
    skins.build(mesh_obj, body, CHARACTER_DIR)
    paint_body(mesh_obj, DEFAULT_SKIN)

    bake_locomotion(rig, body)
    merge_m2m = load_module("merge_m2m_animations.py")
    merge_m2m.merge_into_open_file(rig, mesh_obj)
    # Keep the GLB's PBR graph export-safe, then add the requested Blender-only
    # Mix Shader graph to the editable work file. Godot renders the same Fresnel
    # ramp through player_suit.tres/vivid_surface.gdshader.
    rimmed = add_camera_rim_to_character()
    bpy.ops.wm.save_as_mainfile(filepath=OUT_BLEND)
    print("camera rim:", ", ".join(sorted(rimmed)))
    print("wrote", OUT_BLEND)


if __name__ == "__main__":
    main()
