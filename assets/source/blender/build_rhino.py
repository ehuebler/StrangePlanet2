"""Build the runtime Cinder-Plate Rhino from the read-only MeshMaker sculpt.

Run from the project root with Blender 5.1:

    & "C:\\Program Files\\Blender Foundation\\Blender 5.1\\blender.exe" `
        --background --factory-startup `
        --python assets/source/blender/build_rhino.py

The source is an armour-plated quadruped facing Blender -X, carrying a three-leg
MeshMaker rig that cannot pose a four-legged animal. This recipe opens it
read-only, turns it to Blender +Y (Godot -Z), fits it to a triangle budget, and
builds a twenty-bone skeleton measured off the sculpt by _inspect_rhino.py — the
horn included, because a charge is aimed along the horn and the horn has to be a
bone before it can be aimed.

The clips are what the charge needs rather than a general quadruped set: a
looping Paw that telegraphs the run-up, a Charge that levels the horn, and a Gore
that snaps the head through the target at impact.

Two contracts are shared with the rest of the library. Animations are authored
here but baked and exported by build_animations.py, so every project character
uses one per-frame, world-axis pose format and one NLA export path. Colour comes
from the fauna population-art contract: semantic COLOR_0 regions, TEXCOORD_0
paint UVs into a palette atlas, and one deterministic external PNG whose alpha is
the night-emission mask.
"""

from __future__ import annotations

import hashlib
import importlib.util
import json
import math
import os
import sys

import bpy
from mathutils import Matrix, Vector


SOURCE_DIR = os.path.dirname(os.path.abspath(__file__))
ROOT = os.path.abspath(os.path.join(
    SOURCE_DIR, os.pardir, os.pardir, os.pardir))
if SOURCE_DIR not in sys.path:
    sys.path.insert(0, SOURCE_DIR)

import build_biome_assets as biome

NAME = "cinder_plate_rhino"
DISPLAY_NAME = "Cinder-Plate Rhino"
SRC_BLEND = os.path.join(
    ROOT, "assets", "source", "meshmaker", "rhino.blend")
OUT_BLEND = os.path.join(ROOT, "assets", "work", "rhino_rigged.blend")
OUT_GLB = os.path.join(
    ROOT, "assets", "runtime", "fauna", "models", NAME + ".glb")
PAINT_PNG = os.path.join(
    ROOT, "assets", "runtime", "biomes", "paint", NAME + "_paint.png")
MANIFEST = os.path.join(
    ROOT, "assets", "runtime", "fauna", "manifests", "fauna_assets.json")
PREVIEW_DIR = os.path.join(ROOT, "assets", "previews", "fauna")

TARGET_HEIGHT = 1.85
TARGET_TRIANGLES = 8000
TRIANGLE_BUDGET = (5200, 8400)
FPS = 30
SEED = 20268134
PAINT_SIZE = 512
EMISSION_STRENGTH = 1.9
## The sculpt faces Blender -X; the rig faces +Y like every other character.
FACING_TURN = -math.pi * 0.5

# Authored bright, because the runtime multiplies this paint by the semantic
# COLOR_0 built from the same palette. Both together land on the intended shade,
# which is why an animal meant to read as dark slate is authored two stops above
# it: paint it the shade you want and the square of it comes out nearly black.
PALETTE = tuple(map(biome._rgba, (
    "9A8FB8",  # 0 hide: slate-violet, pebbled
    "BCC8E0",  # 1 plate: cool grey-blue armour over back and flanks
    "F2D9A8",  # 2 horn: pale amber, banded
    "5A5568",  # 3 hoof: dark feet and lower legs
    "FF8340",  # 4 ember: molten seams between the plates
    "CE8A9A",  # 5 belly: dusty rose underside and throat
)))
PAINT_STYLE = (
    "pebbled slate-violet hide, broad grey-blue plate strata over the back and "
    "flanks, banded amber horn, near-black hooves, dusty rose belly, and "
    "mip-safe molten ember seams carried in PNG alpha"
)
EMISSION_STYLE = "plate seams and horn base glow like cooling slag after sunset"

REQUIRED_CLIPS = (
    "Idle", "Walk", "Run", "Paw", "Charge", "Gore", "HitReact", "Defeat",
)

# Measured off the normalized sculpt by _inspect_rhino.py and expressed as
# shares of total height, so the skeleton follows the body if the target size
# ever changes. +Y is the head, +Z is up, and the feet sit on Z=0.
FRONT_FOOT_Y = 0.130
HIND_FOOT_Y = -0.400
FOOT_X = 0.202
LEG_TOP_Z = 0.335
KNEE_Z = 0.173
ANKLE_Z = 0.070

BONES = (
    # name, parent, head, tail, connected
    ("Root", None, (0.0, -0.06, 0.0), (0.0, -0.06, 0.10), False),
    ("Hips", "Root", (0.0, -0.335, 0.515), (0.0, -0.135, 0.552), False),
    ("Spine", "Hips", (0.0, -0.135, 0.552), (0.0, 0.027, 0.595), True),
    ("Chest", "Spine", (0.0, 0.027, 0.595), (0.0, 0.190, 0.635), True),
    ("Neck", "Chest", (0.0, 0.190, 0.650), (0.0, 0.340, 0.628), False),
    ("Head", "Neck", (0.0, 0.340, 0.628), (0.0, 0.500, 0.560), True),
    # The horn leaves the nose and rakes up and forward to the measured tip.
    ("Horn", "Head", (0.0, 0.470, 0.548), (0.0, 0.622, 0.748), False),
    ("Tail", "Hips", (0.0, -0.535, 0.470), (0.0, -0.615, 0.340), False),
)
LEG_ENDS = (
    ("Front", FRONT_FOOT_Y, 0.055),
    ("Hind", HIND_FOOT_Y, 0.070),
)
SIDES = (("Left", -1.0), ("Right", 1.0))


def leg_bones() -> tuple:
    """Three bones per leg, planted under the measured foot cluster."""
    specs = []
    for end, foot_y, toe_reach in LEG_ENDS:
        for side, sign in SIDES:
            prefix = side + end
            hip_x = FOOT_X * sign * 0.88
            foot_x = FOOT_X * sign
            # Front legs stand slightly under the chest and hind legs slightly
            # ahead of the rump, which is where the sculpt's columns already are.
            hip_y = foot_y - 0.025 if end == "Front" else foot_y + 0.040
            specs.extend((
                (prefix + "UpperLeg", "Chest" if end == "Front" else "Hips",
                 (hip_x, hip_y, LEG_TOP_Z), (foot_x, foot_y, KNEE_Z), False),
                (prefix + "LowerLeg", prefix + "UpperLeg",
                 (foot_x, foot_y, KNEE_Z),
                 (foot_x, foot_y + 0.014, ANKLE_Z), True),
                (prefix + "Foot", prefix + "LowerLeg",
                 (foot_x, foot_y + 0.014, ANKLE_Z),
                 (foot_x, foot_y + toe_reach, 0.012), True),
            ))
    return tuple(specs)


ALL_BONES = BONES + leg_bones()
DEFORM_BONES = tuple(spec[0] for spec in ALL_BONES if spec[0] != "Root")
LEG_PREFIXES = tuple(
    side + end for end, _, _ in LEG_ENDS for side, _ in SIDES)


def metres(point) -> Vector:
    return Vector((point[0], point[1], point[2])) * TARGET_HEIGHT


def load_sibling(filename: str, suffix: str):
    path = os.path.join(SOURCE_DIR, filename)
    spec = importlib.util.spec_from_file_location(
        os.path.splitext(filename)[0] + suffix, path)
    module = importlib.util.module_from_spec(spec)
    spec.loader.exec_module(module)
    return module


def activate(obj: bpy.types.Object) -> None:
    if bpy.context.object is not None and bpy.context.object.mode != "OBJECT":
        bpy.ops.object.mode_set(mode="OBJECT")
    for other in bpy.context.view_layer.objects:
        if other is not None:
            other.select_set(False)
    obj.hide_viewport = False
    obj.hide_render = False
    obj.select_set(True)
    bpy.context.view_layer.objects.active = obj


def file_sha256(path: str) -> str:
    digest = hashlib.sha256()
    with open(path, "rb") as handle:
        for chunk in iter(lambda: handle.read(1024 * 1024), b""):
            digest.update(chunk)
    return digest.hexdigest()


def triangle_count(mesh: bpy.types.Mesh) -> int:
    return sum(max(len(polygon.vertices) - 2, 0) for polygon in mesh.polygons)


def mesh_bounds(mesh_obj: bpy.types.Object) -> tuple[Vector, Vector]:
    points = [mesh_obj.matrix_world @ vertex.co
              for vertex in mesh_obj.data.vertices]
    low = Vector(tuple(min(point[axis] for point in points)
                       for axis in range(3)))
    high = Vector(tuple(max(point[axis] for point in points)
                        for axis in range(3)))
    return low, high


# --------------------------------------------------------------------------
# Source
# --------------------------------------------------------------------------

def source_mesh() -> bpy.types.Object:
    """The sculpt, whatever MeshMaker happened to call it in this file."""
    named = bpy.data.objects.get("geometry_0")
    if named is not None and named.type == "MESH":
        return named
    meshes = [obj for obj in bpy.data.objects if obj.type == "MESH"]
    if not meshes:
        raise SystemExit("no mesh in " + SRC_BLEND)
    return max(meshes, key=lambda obj: len(obj.data.vertices))


def normalize_source() -> tuple[bpy.types.Object, str]:
    """Open the sculpt read-only and return it turned, scaled, and grounded."""
    if not os.path.isfile(SRC_BLEND):
        raise SystemExit("rhino source is missing: " + SRC_BLEND)
    source_hash = file_sha256(SRC_BLEND)
    bpy.ops.wm.open_mainfile(filepath=SRC_BLEND)

    mesh_obj = source_mesh()
    if mesh_obj.data.color_attributes.get("Color") is None:
        raise SystemExit("the rhino sculpt must carry a Color attribute")

    low, high = mesh_bounds(mesh_obj)
    source_height = high.z - low.z
    scale = TARGET_HEIGHT / source_height
    # The horn projects toward source -X. Blender +Y is Godot -Z, the direction
    # a creature actor faces, so bake that quarter turn into the vertices.
    base = Matrix.Scale(scale, 4) @ Matrix.Rotation(FACING_TURN, 4, "Z")
    turned = [base @ (mesh_obj.matrix_world @ vertex.co)
              for vertex in mesh_obj.data.vertices]
    turned_low = Vector(tuple(min(point[axis] for point in turned)
                              for axis in range(3)))
    turned_high = Vector(tuple(max(point[axis] for point in turned)
                               for axis in range(3)))
    offset = Vector((
        -(turned_low.x + turned_high.x) * 0.5,
        0.0,
        -turned_low.z,
    ))
    for vertex, point in zip(mesh_obj.data.vertices, turned):
        vertex.co = point + offset
    mesh_obj.data.update()
    mesh_obj.parent = None
    mesh_obj.matrix_parent_inverse = Matrix.Identity(4)
    mesh_obj.matrix_world = Matrix.Identity(4)
    for modifier in list(mesh_obj.modifiers):
        mesh_obj.modifiers.remove(modifier)
    # MeshMaker rigged this one with three leg chains. Nothing here can use them
    # and their groups would be mistaken for a skin, so the sculpt is taken bare.
    mesh_obj.vertex_groups.clear()

    for obj in list(bpy.data.objects):
        if obj is not mesh_obj:
            bpy.data.objects.remove(obj, do_unlink=True)
    for action in list(bpy.data.actions):
        bpy.data.actions.remove(action)

    mesh_obj.name = "Character"
    mesh_obj.data.name = "RhinoMesh"
    scene = bpy.context.scene
    scene.unit_settings.system = "METRIC"
    scene.unit_settings.length_unit = "METERS"
    scene.render.fps = FPS

    print("source: {0} verts, {1} tris, {2:.3f} m; sha256={3}".format(
        len(mesh_obj.data.vertices), triangle_count(mesh_obj.data),
        source_height, source_hash))
    print("normalize: scale={0:.6f}, turn={1:.0f} deg, target={2:.3f} m".format(
        scale, math.degrees(FACING_TURN), TARGET_HEIGHT))
    return mesh_obj, source_hash


def optimize(mesh_obj: bpy.types.Object) -> None:
    before = triangle_count(mesh_obj.data)
    if before > TARGET_TRIANGLES:
        modifier = mesh_obj.modifiers.new("HerdBudget", "DECIMATE")
        modifier.decimate_type = "COLLAPSE"
        modifier.ratio = TARGET_TRIANGLES / float(before)
        modifier.use_collapse_triangulate = True
        activate(mesh_obj)
        bpy.ops.object.modifier_apply(modifier=modifier.name)
    after = triangle_count(mesh_obj.data)
    minimum, maximum = TRIANGLE_BUDGET
    if not minimum <= after <= maximum:
        raise SystemExit("rhino has {0} triangles, budget is {1}..{2}".format(
            after, minimum, maximum))
    for polygon in mesh_obj.data.polygons:
        polygon.use_smooth = True
    mesh_obj.data.update()
    print("optimize: {0} -> {1} tris, {2} verts".format(
        before, after, len(mesh_obj.data.vertices)))


# --------------------------------------------------------------------------
# Skeleton and skin
# --------------------------------------------------------------------------

def build_armature() -> bpy.types.Object:
    armature = bpy.data.armatures.new("CharacterSkeleton")
    rig = bpy.data.objects.new("CharacterRig", armature)
    bpy.context.collection.objects.link(rig)
    activate(rig)
    bpy.ops.object.mode_set(mode="EDIT")
    for name, parent, head, tail, connected in ALL_BONES:
        bone = armature.edit_bones.new(name)
        bone.head = metres(head)
        bone.tail = metres(tail)
        if (bone.tail - bone.head).length < 1.0e-4:
            raise SystemExit(name + " has no length")
        if parent is not None:
            bone.parent = armature.edit_bones[parent]
            bone.use_connect = connected
    bpy.ops.armature.calculate_roll(type="GLOBAL_POS_Y")
    bpy.ops.object.mode_set(mode="OBJECT")
    # Root only carries the body; posing it would slide the whole animal.
    armature.bones["Root"].use_deform = False
    print("rig: {0} bones, {1} deforming".format(
        len(armature.bones), len(DEFORM_BONES)))
    return rig


def side_and_end(group_name: str) -> tuple[float, str] | None:
    """Which quadrant a leg vertex group belongs to, or None for a body bone."""
    for end, _, _ in LEG_ENDS:
        for side, sign in SIDES:
            if group_name.startswith(side + end):
                return sign, end
    return None


def skin(mesh_obj: bpy.types.Object, rig: bpy.types.Object) -> None:
    """Heat-diffusion weights, then a deterministic clean-up of the legs.

    Same reasoning as the other sculpted quadruped: the source skin is unusable,
    the hide has no seams to guide an analytic falloff, and what heat diffusion
    gets wrong on a barrel body is reach. This animal is stumpier than the
    alpaca, so its legs sit closer to the belly and closer to each other, which
    makes the cross-quadrant bleed worse rather than better. Every leg weight
    outside that leg's own quadrant is dropped and the vertex renormalized.
    """
    activate(mesh_obj)
    mesh_obj.select_set(True)
    rig.select_set(True)
    bpy.context.view_layer.objects.active = rig
    bpy.ops.object.parent_set(type="ARMATURE_AUTO")

    groups = {group.name: group for group in mesh_obj.vertex_groups}
    missing = [name for name in DEFORM_BONES if name not in groups]
    if missing:
        raise SystemExit("automatic weights skipped: " + ", ".join(missing))

    # Halfway between the measured foot clusters: no foreleg owns hide behind it.
    split_y = (FRONT_FOOT_Y + HIND_FOOT_Y) * 0.5 * TARGET_HEIGHT
    band = TARGET_HEIGHT * 0.05
    rows: list[dict[str, float]] = []
    dropped = 0
    for vertex in mesh_obj.data.vertices:
        mapped: dict[str, float] = {}
        for assignment in vertex.groups:
            name = mesh_obj.vertex_groups[assignment.group].name
            amount = assignment.weight
            if amount <= 1.0e-6:
                continue
            limb = side_and_end(name)
            if limb is not None:
                sign, end = limb
                if vertex.co.x * sign < -band:
                    dropped += 1
                    continue
                if end == "Front" and vertex.co.y < split_y - band:
                    dropped += 1
                    continue
                if end == "Hind" and vertex.co.y > split_y + band:
                    dropped += 1
                    continue
            mapped[name] = mapped.get(name, 0.0) + amount
        kept = sorted(mapped.items(), key=lambda item: item[1],
                      reverse=True)[:4]
        total = sum(amount for _, amount in kept)
        if total < 1.0e-6:
            # Hide that lost every claim belongs to the body it hangs from.
            nearest = "Chest" if vertex.co.y > split_y else "Hips"
            kept = [(nearest, 1.0)]
            total = 1.0
        rows.append({name: amount / total for name, amount in kept})

    mesh_obj.vertex_groups.clear()
    rebuilt = {name: mesh_obj.vertex_groups.new(name=name)
               for name in DEFORM_BONES}
    counts = {name: 0 for name in DEFORM_BONES}
    for index, mapped in enumerate(rows):
        for name, amount in mapped.items():
            rebuilt[name].add([index], amount, "REPLACE")
            counts[name] += 1

    empty = [name for name, count in counts.items() if count == 0]
    if empty:
        raise SystemExit("unweighted bones: " + ", ".join(empty))
    print("skin: max 4 influences, {0} stray leg weights dropped".format(
        dropped))
    print("  " + ", ".join("{0}:{1}".format(name, counts[name])
                           for name in DEFORM_BONES))


# --------------------------------------------------------------------------
# Colour paint
# --------------------------------------------------------------------------

def recipe() -> biome.AssetRecipe:
    # "flyer" is chosen only for its paint projection: it is the archetype whose
    # polygons are projected on their dominant axis at a broad motif scale, which
    # is what a horizontal barrel body needs. A trunk-style cylindrical unwrap
    # would smear the atlas along the animal's length.
    return biome.AssetRecipe(
        NAME, "fauna", "flyer", "rhino", SEED, TARGET_HEIGHT, PALETTE,
        TRIANGLE_BUDGET,
        {
            "shape": "capsule",
            "radius": 0.52,
            "height": 1.10,
            "centre": [0.0, 0.66, 0.0],
        },
        PAINT_STYLE, EMISSION_STYLE, EMISSION_STRENGTH,
        roughness=0.72, smooth=True,
    )


def region_of(centre: Vector) -> int:
    """Which semantic palette region one polygon belongs to."""
    x = centre.x / TARGET_HEIGHT
    y = centre.y / TARGET_HEIGHT
    z = centre.z / TARGET_HEIGHT

    # The horn first: it is the one part whose silhouette has to read from far
    # enough away that the player knows what is coming.
    if y > 0.455 and z > 0.500:
        return 2
    if z < 0.115:
        return 3  # hooves
    if y < -0.500:
        return 5  # tail and rump crease
    # Ember seams run across the back and down between the flank plates, spaced
    # a body-length apart so they stay separate bands under minification.
    seam = math.sin((y + 0.30) * math.tau * 1.15)
    if z > 0.60 and abs(seam) < 0.16 and -0.46 < y < 0.34:
        return 4
    if abs(x) > 0.185 and 0.30 < z < 0.62 and abs(seam) < 0.13:
        return 4
    if z > 0.62 and -0.50 < y < 0.36:
        return 1  # plate strata over the back, hump, and shoulders
    if abs(x) > 0.175 and 0.28 < z < 0.66:
        return 1  # flank plates
    if z < 0.30 and abs(x) < 0.165 and -0.44 < y < 0.30:
        return 5  # belly
    if 0.30 < y < 0.46 and z < 0.50:
        return 5  # throat and lower jaw
    return 0


def paint_regions(mesh_obj: bpy.types.Object,
                  asset: biome.AssetRecipe) -> dict[int, int]:
    mesh = mesh_obj.data
    existing = mesh.color_attributes.get(biome.COLOR_ATTRIBUTE)
    if existing is not None:
        mesh.color_attributes.remove(existing)
    for layer in list(mesh.uv_layers):
        mesh.uv_layers.remove(layer)
    colour = mesh.color_attributes.new(
        name=biome.COLOR_ATTRIBUTE, type="BYTE_COLOR", domain="CORNER")
    paint_uv = mesh.uv_layers.new(name=biome.PAINT_UV_NAME)

    tally: dict[int, int] = {index: 0 for index in range(len(PALETTE))}
    for polygon in mesh.polygons:
        palette_index = region_of(polygon.center)
        tally[palette_index] += 1
        polygon.material_index = 0
        coordinates = [
            mesh.vertices[mesh.loops[loop].vertex_index].co
            for loop in polygon.loop_indices
        ]
        uvs = biome._polygon_paint_uvs(
            asset, polygon, coordinates, palette_index)
        for loop, uv in zip(polygon.loop_indices, uvs):
            coordinate = mesh.vertices[mesh.loops[loop].vertex_index].co
            colour.data[loop].color = biome._colour_value(
                PALETTE[palette_index], coordinate, TARGET_HEIGHT, SEED,
                palette_index)
            paint_uv.data[loop].uv = uv
    mesh.color_attributes.active_color_name = biome.COLOR_ATTRIBUTE
    mesh.color_attributes.render_color_index = 0
    mesh.uv_layers.active = paint_uv
    mesh.uv_layers.active_index = list(mesh.uv_layers).index(paint_uv)
    mesh.materials.clear()
    mesh.materials.append(biome._make_material(asset))
    mesh.update()
    print("paint regions: " + ", ".join(
        "{0}:{1}".format(index, tally[index]) for index in sorted(tally)))
    if min(tally.values()) <= 0:
        raise SystemExit("a palette region claimed no polygons")
    return tally


def clamp01(value: float) -> float:
    return max(0.0, min(1.0, value))


def smoothstep(low: float, high: float, value: float) -> float:
    if high <= low:
        return 1.0 if value >= high else 0.0
    share = clamp01((value - low) / (high - low))
    return share * share * (3.0 - 2.0 * share)


def mix(first, second, share: float):
    amount = clamp01(share)
    return tuple(first[index] * (1.0 - amount) + second[index] * amount
                 for index in range(4))


def paint_pixel(palette_index: int, u: float, v: float):
    """One motif of broad, mip-safe markings for one semantic region."""
    base = PALETTE[palette_index]
    pale = mix(base, (1.0, 1.0, 1.0, 1.0), 0.30)
    deep = (base[0] * 0.46, base[1] * 0.48, base[2] * 0.56, 1.0)
    tau = math.tau
    phase = SEED * 0.00037 + palette_index * 0.19
    result = base
    emission = 0.04

    if palette_index == 0:
        # Hide: coarse pebbling under wide skin folds, no fine speckle.
        fold = 0.5 + 0.5 * math.sin(
            tau * (v * 1.6 + 0.22 * math.sin(tau * (u * 1.2 + phase)) + phase))
        pebble = 0.5 + 0.5 * math.sin(tau * (u * 3.0 + phase * 2.1)) \
            * math.sin(tau * (v * 3.0 - phase))
        result = mix(result, deep, (1.0 - fold) * 0.30)
        result = mix(result, pale, pebble * fold * 0.16)
        emission = 0.03 + fold * 0.04
    elif palette_index == 1:
        # Plate: one thick stratum per motif with a bevelled lip, the way a
        # rhino's shoulder shield reads at any distance.
        stratum = math.sin(tau * (v * 0.65 + 0.08 * math.sin(tau * u) + phase))
        lip = 1.0 - smoothstep(0.06, 0.26, abs(stratum))
        result = mix(result, deep, clamp01(-stratum) * 0.48)
        result = mix(result, pale, clamp01(stratum) * 0.30)
        result = mix(result, PALETTE[4], lip * 0.30)
        emission = 0.06 + lip * 0.48
    elif palette_index == 2:
        # Horn: growth rings along its length, pale at the tip, scorched at the
        # base where it grinds against everything the animal charges.
        rings = 0.5 + 0.5 * math.sin(tau * (v * 3.2 + phase))
        result = mix(result, deep, (1.0 - smoothstep(0.0, 0.55, v)) * 0.55)
        result = mix(result, pale, smoothstep(0.55, 1.0, v) * 0.45)
        result = mix(result, deep, rings * 0.16)
        result = mix(result, PALETTE[4],
                     (1.0 - smoothstep(0.0, 0.30, v)) * 0.34)
        emission = 0.05 + (1.0 - smoothstep(0.0, 0.32, v)) * 0.44
    elif palette_index == 3:
        # Hoof: black at the ground, one broad ash ring above it.
        rise = smoothstep(0.0, 0.85, v)
        ring = 1.0 - smoothstep(
            0.10, 0.26, abs(math.sin(tau * (v * 1.2 + phase))))
        result = mix(result, deep, (1.0 - rise) * 0.60)
        result = mix(result, pale, rise * 0.26)
        result = mix(result, PALETTE[4], ring * 0.22)
        emission = 0.04 + ring * 0.30
    elif palette_index == 4:
        # Ember: one molten crack down the middle of the motif, hottest in its
        # core and cooling outward, kept well inside the band so minification
        # dims it evenly instead of breaking it into speckle.
        crack = abs(v - 0.5) + 0.10 * math.sin(tau * (u * 1.4 + phase))
        core = 1.0 - smoothstep(0.05, 0.17, crack)
        glow = 1.0 - smoothstep(0.14, 0.40, crack)
        result = mix(PALETTE[0], base, glow * 0.85)
        result = mix(result, mix(base, (1.0, 1.0, 0.86, 1.0), 0.55), core)
        emission = clamp01(0.10 + glow * 0.45 + core * 0.62)
    else:
        # Belly: soft mottling, and a darker crease where it meets the plates.
        mottle = 0.5 + 0.5 * math.sin(tau * (u * 1.1 + v * 0.9 + phase))
        crease = 1.0 - smoothstep(0.0, 0.28, v)
        result = mix(result, pale, mottle * 0.26)
        result = mix(result, deep, crease * 0.40)
        emission = 0.05 + mottle * 0.10

    drift = 0.96 + 0.04 * math.sin(tau * (u * 0.7 + v * 0.5 + phase * 0.5))
    return (
        clamp01(result[0] * drift),
        clamp01(result[1] * drift),
        clamp01(result[2] * drift),
        clamp01(emission),
    )


def write_paint_texture() -> bpy.types.Image:
    """One deterministic PNG: an atlas band per semantic region, alpha is glow."""
    os.makedirs(os.path.dirname(PAINT_PNG), exist_ok=True)
    image = bpy.data.images.new(
        NAME + "_paint", width=PAINT_SIZE, height=PAINT_SIZE,
        alpha=True, float_buffer=False)
    try:
        image.colorspace_settings.name = "sRGB"
    except TypeError:
        pass
    count = len(PALETTE)
    # The same gutter share _polygon_paint_uvs reserves, so no motif is sampled
    # across a band seam once the texture is minified.
    gutter = biome.PAINT_GUTTER / (biome.PAINT_SIZE / count)
    usable = max(1.0 - gutter * 2.0, 1.0e-5)
    pixels: list[float] = []
    for row in range(PAINT_SIZE):
        atlas_v = (row + 0.5) / PAINT_SIZE * count
        palette_index = min(int(atlas_v), count - 1)
        local_v = clamp01((atlas_v - palette_index - gutter) / usable)
        for column in range(PAINT_SIZE):
            pixels.extend(paint_pixel(
                palette_index, (column + 0.5) / PAINT_SIZE, local_v))
    image.pixels.foreach_set(pixels)
    image.filepath_raw = PAINT_PNG
    image.file_format = "PNG"
    image.save()
    if not os.path.isfile(PAINT_PNG) or os.path.getsize(PAINT_PNG) <= 0:
        raise SystemExit("colour paint did not produce " + PAINT_PNG)
    print("paint: {0} ({1:.1f} KB)".format(
        os.path.basename(PAINT_PNG), os.path.getsize(PAINT_PNG) / 1024.0))
    return image


# --------------------------------------------------------------------------
# Animation
# --------------------------------------------------------------------------

def rhino_animations(anim):
    """Rhino clips in build_animations.py's shared world-axis pose format."""
    rot = anim.rot
    tau = math.tau

    # A heavy quadruped walks laterally and gallops in diagonal pairs.
    walk_order = {
        "LeftHind": 0.0, "LeftFront": 0.28,
        "RightHind": 0.5, "RightFront": 0.78,
    }
    gallop_order = {
        "LeftFront": 0.0, "RightFront": 0.10,
        "LeftHind": 0.48, "RightHind": 0.58,
    }

    def ease(value):
        value = clamp01(value)
        return value * value * (3.0 - 2.0 * value)

    def pulse(t, start, peak, end):
        if t <= start or t >= end:
            return 0.0
        if t < peak:
            return ease((t - start) / max(peak - start, 1.0e-6))
        return 1.0 - ease((t - peak) / max(end - peak, 1.0e-6))

    def stride(pose, phase, order, swing, knee, foot, share=1.0):
        """Swing four legs from the hip, folding each as it leaves the ground."""
        for prefix, offset in order.items():
            leg = phase + offset * tau
            reach = math.sin(leg)
            # The fold peaks in the middle of the swing, when the foot is off
            # the ground, and returns to zero as the hoof is planted again.
            fold = max(0.0, -math.cos(leg)) ** 1.4
            # A carpus folds back under the animal, a hock folds forward.
            direction = -1.0 if prefix.endswith("Front") else 1.0
            pose[prefix + "UpperLeg"] = rot(("X", swing * reach * share))
            pose[prefix + "LowerLeg"] = rot(
                ("X", direction * knee * fold * share))
            pose[prefix + "Foot"] = rot(
                ("X", (foot * fold - swing * reach * 0.40) * share))

    def planted_legs(pose, drop, spread=0.0, fold=0.0):
        """All four braced, for a standing telegraph and for collapsing."""
        for prefix in LEG_PREFIXES:
            sign = -1.0 if prefix.startswith("Left") else 1.0
            direction = -1.0 if prefix.endswith("Front") else 1.0
            pose[prefix + "UpperLeg"] = rot(
                ("X", drop * (1.0 if prefix.endswith("Front") else -0.6)),
                ("Y", -sign * spread))
            pose[prefix + "LowerLeg"] = rot(("X", direction * fold))
            pose[prefix + "Foot"] = rot(("X", -direction * fold * 0.5))

    def head_low(pose, amount, sway=0.0):
        """Neck down and horn levelled, which is the animal's whole threat."""
        pose["Neck"] = rot(("X", -16.0 * amount), ("Z", sway))
        pose["Head"] = rot(("X", -8.0 * amount), ("Z", sway * 0.6))
        pose["Horn"] = rot(("X", 4.0 * amount))

    def idle_pose(t):
        breath = math.sin(t * tau)
        sway = math.sin(t * tau * 0.5)
        pose = {
            "Hips": {"rot": [("Z", 1.0 * sway)],
                     "loc": (0.0, 0.0, 0.006 * breath)},
            "Spine": rot(("X", 1.4 * breath), ("Z", -0.8 * sway)),
            "Chest": rot(("X", -1.6 + 1.6 * breath)),
            "Neck": rot(("X", -2.0 + 1.4 * breath), ("Z", 2.4 * sway)),
            "Head": rot(("X", 1.0 - 1.0 * breath), ("Z", 3.4 * sway)),
            "Horn": rot(("X", 0.0)),
            "Tail": rot(("X", 3.0 * breath),
                        ("Z", 11.0 * math.sin(t * tau * 1.5))),
        }
        stride(pose, 0.0, walk_order, 0.0, 0.0, 0.0)
        return pose

    def walk_pose(t):
        phase = t * tau
        pose = {}
        stride(pose, phase, walk_order, swing=15.0, knee=22.0, foot=10.0)
        # Two dips per cycle, one for each diagonal pair taking the weight, and
        # a heavy roll across the shoulders that a light animal would not have.
        dip = -0.018 * (1.0 - math.cos(phase * 2.0)) * 0.5
        pose["Hips"] = {
            "rot": [("Z", 2.6 * math.sin(phase)), ("Y", 5.0 * math.sin(phase))],
            "loc": (0.006 * math.sin(phase), 0.0, dip),
        }
        pose["Spine"] = rot(("Z", -1.8 * math.sin(phase)),
                            ("Y", -3.0 * math.sin(phase)))
        pose["Chest"] = rot(("X", -2.0), ("Y", 4.0 * math.sin(phase)))
        pose["Neck"] = rot(("X", -6.0 + 3.0 * math.sin(phase * 2.0)),
                           ("Z", 2.0 * math.sin(phase)))
        pose["Head"] = rot(("X", 2.0 - 2.4 * math.sin(phase * 2.0)),
                           ("Z", 2.6 * math.sin(phase)))
        pose["Horn"] = rot(("X", 0.0))
        pose["Tail"] = rot(("Z", 14.0 * math.sin(phase)))
        return pose

    def run_pose(t):
        phase = t * tau
        pose = {}
        stride(pose, phase, gallop_order, swing=27.0, knee=40.0, foot=18.0)
        dip = -0.026 * (1.0 - math.cos(phase * 2.0)) * 0.5
        pose["Hips"] = {
            "rot": [("X", -3.0), ("Z", 3.0 * math.sin(phase))],
            "loc": (0.0, 0.0, 0.014 + dip),
        }
        pose["Spine"] = rot(("X", 3.0), ("Z", -2.4 * math.sin(phase)))
        pose["Chest"] = rot(("X", -5.0))
        head_low(pose, 0.55, 2.0 * math.sin(phase))
        pose["Tail"] = rot(("X", 14.0), ("Z", 14.0 * math.sin(phase * 2.0)))
        return pose

    def paw_pose(t):
        """The telegraph: head down, weight back, one foreleg scraping.

        This one loops, because the run-up is held for as long as the creature
        takes to decide, and a one-shot would snap back to rest under it.
        """
        scrape = math.sin(t * tau)
        forward = max(0.0, scrape)
        back = max(0.0, -scrape)
        pose = {}
        planted_legs(pose, drop=-5.0, spread=3.0, fold=6.0)
        # The right foreleg does the pawing; the other three stay braced.
        pose["RightFrontUpperLeg"] = rot(("X", 26.0 * forward - 16.0 * back))
        pose["RightFrontLowerLeg"] = rot(("X", -34.0 * forward - 6.0))
        pose["RightFrontFoot"] = rot(("X", 20.0 * forward + 8.0 * back))
        pose["Hips"] = {"rot": [("X", 4.0), ("Z", 1.6 * scrape)],
                        "loc": (0.0, -0.030, -0.014)}
        pose["Spine"] = rot(("X", -3.0), ("Z", -1.2 * scrape))
        pose["Chest"] = rot(("X", -7.0))
        head_low(pose, 1.0, 4.0 * scrape)
        pose["Tail"] = rot(("X", -18.0), ("Z", 16.0 * math.sin(t * tau * 2.0)))
        return pose

    def charge_pose(t):
        """Flat-out, horn levelled: the gallop the damage is dealt from."""
        phase = t * tau
        pose = {}
        stride(pose, phase, gallop_order, swing=34.0, knee=52.0, foot=22.0)
        drive = -0.034 * (1.0 - math.cos(phase * 2.0)) * 0.5
        pose["Hips"] = {
            "rot": [("X", -6.0), ("Z", 2.0 * math.sin(phase))],
            "loc": (0.0, 0.0, 0.020 + drive),
        }
        pose["Spine"] = rot(("X", 5.0), ("Z", -1.6 * math.sin(phase)))
        pose["Chest"] = rot(("X", -9.0))
        head_low(pose, 1.35, 1.4 * math.sin(phase))
        pose["Tail"] = rot(("X", 24.0), ("Z", 9.0 * math.sin(phase * 2.0)))
        return pose

    def gore_pose(t):
        """The horn goes through whatever the charge caught and throws it up."""
        drop = ease(t / 0.22)
        toss = ease((t - 0.22) / 0.24)
        settle = ease((t - 0.62) / 0.38)
        active = 1.0 - settle
        pose = {}
        planted_legs(pose, drop=-8.0 * active, spread=5.0 * active,
                     fold=9.0 * active)
        pose["Hips"] = {"rot": [("X", -7.0 * drop * active + 6.0 * toss)],
                        "loc": (0.0, 0.024 * toss * active, 0.0)}
        pose["Spine"] = rot(("X", -6.0 * drop * active + 8.0 * toss * active))
        pose["Chest"] = rot(("X", -12.0 * drop * active + 14.0 * toss * active))
        pose["Neck"] = rot(
            ("X", -26.0 * drop * active + 46.0 * toss * active),
            ("Z", -9.0 * toss * active))
        pose["Head"] = rot(
            ("X", -10.0 * drop * active + 30.0 * toss * active),
            ("Z", -12.0 * toss * active))
        pose["Horn"] = rot(("X", 6.0 * toss * active))
        pose["Tail"] = rot(("X", 26.0 * toss * active))
        return pose

    def hit_react_pose(t):
        hit = math.sin(math.pi * clamp01(t))
        pose = {}
        planted_legs(pose, drop=-7.0 * hit, spread=7.0 * hit, fold=9.0 * hit)
        pose["Hips"] = {"rot": [("Z", -6.0 * hit), ("X", -6.0 * hit)],
                        "loc": (0.0, -0.016 * hit, -0.024 * hit)}
        pose["Spine"] = rot(("X", 8.0 * hit), ("Z", 7.0 * hit))
        pose["Chest"] = rot(("X", 6.0 * hit))
        pose["Neck"] = rot(("X", 14.0 * hit), ("Z", -9.0 * hit))
        pose["Head"] = rot(("X", -12.0 * hit), ("Z", -11.0 * hit))
        pose["Horn"] = rot(("X", -4.0 * hit))
        pose["Tail"] = rot(("X", -20.0 * hit))
        return pose

    def defeat_pose(t):
        buckle = ease(t / 0.40)
        limp = ease((t - 0.32) / 0.68)
        pose = {}
        planted_legs(pose, drop=-18.0 * buckle, spread=20.0 * buckle,
                     fold=54.0 * buckle)
        pose["Hips"] = {
            "rot": [("X", -14.0 * buckle), ("Z", -15.0 * limp)],
            "loc": (0.0, -0.014 * buckle, -0.165 * buckle),
        }
        pose["Spine"] = rot(("X", -10.0 * buckle), ("Z", 12.0 * limp))
        pose["Chest"] = rot(("X", -16.0 * buckle), ("Z", 9.0 * limp))
        pose["Neck"] = rot(("X", -14.0 * buckle - 20.0 * limp),
                           ("Z", -8.0 * limp))
        pose["Head"] = rot(("X", -8.0 * buckle - 14.0 * limp))
        pose["Horn"] = rot(("X", -6.0 * limp))
        pose["Tail"] = rot(("X", -24.0 * limp))
        return pose

    return [
        ("Idle", 96, True, idle_pose),
        ("Walk", 36, True, walk_pose),
        ("Run", 22, True, run_pose),
        ("Paw", 30, True, paw_pose),
        ("Charge", 18, True, charge_pose),
        ("Gore", 24, False, gore_pose),
        ("HitReact", 16, False, hit_react_pose),
        ("Defeat", 54, False, defeat_pose),
    ]


def export_runtime(rig: bpy.types.Object,
                   mesh_obj: bpy.types.Object) -> None:
    os.makedirs(os.path.dirname(OUT_GLB), exist_ok=True)
    if bpy.context.object is not None and bpy.context.object.mode != "OBJECT":
        bpy.ops.object.mode_set(mode="OBJECT")
    for obj in bpy.context.view_layer.objects:
        if obj is not None:
            obj.select_set(False)
    for obj in (rig, mesh_obj):
        obj.hide_viewport = False
        obj.hide_render = False
        obj.select_set(True)
    bpy.context.view_layer.objects.active = rig
    bpy.ops.export_scene.gltf(
        filepath=OUT_GLB,
        export_format="GLB",
        use_selection=True,
        export_apply=True,
        export_skins=True,
        export_animations=True,
        export_animation_mode="NLA_TRACKS",
        export_frame_range=False,
        export_force_sampling=True,
        export_yup=True,
        # The runtime samples the paint PNG through TEXCOORD_0 and reads COLOR_0
        # as the semantic region mask, so both streams must survive the export.
        export_texcoords=True,
        export_vertex_color="ACTIVE",
        export_all_vertex_colors=False,
    )
    print("wrote {0} ({1:.1f} KB)".format(
        OUT_GLB, os.path.getsize(OUT_GLB) / 1024.0))


# --------------------------------------------------------------------------
# Previews, manifest, validation
# --------------------------------------------------------------------------

def preview_with_paint(material: bpy.types.Material,
                       image: bpy.types.Image) -> None:
    """Show the same PNG the game samples, with its alpha driving the glow."""
    nodes = material.node_tree.nodes
    links = material.node_tree.links
    principled = nodes.get("Principled BSDF")
    if principled is None:
        raise SystemExit("preview material has no Principled BSDF")
    texture = nodes.new("ShaderNodeTexImage")
    texture.name = "BiomeColorPaint"
    texture.image = image
    texture.interpolation = "Linear"
    texture.extension = "REPEAT"
    for socket_name in ("Base Color", "Emission Color", "Emission"):
        socket = principled.inputs.get(socket_name)
        if socket is None:
            continue
        for link in list(socket.links):
            links.remove(link)
        links.new(texture.outputs["Color"], socket)
    strength = principled.inputs.get("Emission Strength")
    if strength is not None:
        multiplier = nodes.new("ShaderNodeMath")
        multiplier.operation = "MULTIPLY"
        multiplier.inputs[1].default_value = EMISSION_STRENGTH
        links.new(texture.outputs["Alpha"], multiplier.inputs[0])
        links.new(multiplier.outputs[0], strength)


def render_pose(rig: bpy.types.Object, clip: str, share: float,
                path: str) -> None:
    """Render one frame of one clip, so a bake can be judged without the game.

    The clip is chosen by soloing its NLA track rather than by assigning its
    action, because the exported tracks are the authority on what the game will
    play, and because reading one back through the action slot API would be
    testing a different path from the one that shipped.
    """
    strip = None
    for track in rig.animation_data.nla_tracks:
        track.mute = track.name != clip
        if track.name == clip and track.strips:
            strip = track.strips[0]
    if strip is None:
        raise SystemExit("no baked NLA track named " + clip)
    rig.animation_data.action = None
    bpy.context.scene.frame_set(int(round(
        strip.frame_start
        + (strip.frame_end - strip.frame_start) * clamp01(share))))
    bpy.context.view_layer.update()
    bpy.context.scene.render.filepath = path
    os.makedirs(os.path.dirname(path), exist_ok=True)
    bpy.ops.render.render(write_still=True)
    if not os.path.isfile(path):
        raise SystemExit("pose preview did not produce " + path)


def render_previews(rig: bpy.types.Object, mesh_obj: bpy.types.Object,
                    asset: biome.AssetRecipe,
                    image: bpy.types.Image) -> dict[str, str]:
    preview_with_paint(mesh_obj.data.materials[0], image)
    # The shared preview camera looks toward Blender +Y from the rear, and the
    # rhino faces +Y, so turn the animal to meet it.
    rig.rotation_euler.z += math.pi
    close_path = os.path.join(PREVIEW_DIR, NAME + "_close.png")
    biome._render_preview(mesh_obj, asset, close_path)
    written = {"close": close_path}

    camera = bpy.data.objects.get("BiomePreviewCamera")
    ground = bpy.data.objects.get("BiomePreviewGround")
    for clip, share, key in (
            ("Paw", 0.25, "paw"),
            ("Charge", 0.30, "charge"),
            ("Gore", 0.45, "gore"),
    ):
        path = os.path.join(PREVIEW_DIR, "{0}_{1}.png".format(NAME, key))
        render_pose(rig, clip, share, path)
        written[key] = path

    if camera is not None:
        camera.data.ortho_scale *= 3.2
    if ground is not None:
        ground.scale.x = 3.5
        ground.scale.y = 3.5
    # Standing at rest, from the distance the animal is normally first seen at,
    # which is the view the paint has to hold together in.
    gameplay_path = os.path.join(PREVIEW_DIR, NAME + "_gameplay.png")
    render_pose(rig, "Idle", 0.0, gameplay_path)
    written["gameplay"] = gameplay_path
    return written


def merge_manifest(mesh_obj: bpy.types.Object,
                   rig: bpy.types.Object) -> None:
    """Record this asset beside the procedurally generated fauna entries."""
    manifest: dict = {}
    if os.path.isfile(MANIFEST):
        with open(MANIFEST, encoding="utf-8") as handle:
            manifest = json.load(handle)
    assets = manifest.setdefault("assets", {})
    low, high = mesh_bounds(mesh_obj)
    assets[NAME] = {
        "name": NAME,
        "display_name": DISPLAY_NAME,
        "category": "land_fauna",
        "form": "rhino",
        "seed": SEED,
        "generator": "assets/source/blender/build_rhino.py",
        "source_sculpt": "assets/source/meshmaker/rhino.blend",
        "work_blend": "assets/work/rhino_rigged.blend",
        "glb": "assets/runtime/fauna/models/{0}.glb".format(NAME),
        "color_paint": (
            "assets/runtime/biomes/paint/{0}_paint.png".format(NAME)),
        "close_preview": "assets/previews/fauna/{0}_close.png".format(NAME),
        "gameplay_distance_preview": (
            "assets/previews/fauna/{0}_gameplay.png".format(NAME)),
        "authored_height": round(high.z - low.z, 6),
        "triangle_count": triangle_count(mesh_obj.data),
        "collision_hint": recipe().collision_hint,
        "color_paint_style": PAINT_STYLE,
        "emission_style": EMISSION_STYLE,
        "emission_strength": EMISSION_STRENGTH,
        "runtime_contract": {
            "mesh_node": "Character",
            "vertex_colour": "COLOR_0 semantic region colors",
            "color_paint_uv": "TEXCOORD_0",
            "emission_mask": (
                "assets/runtime/biomes/paint/{0}_paint.png alpha; "
                "never transparency".format(NAME)),
            "ground_axis": "Godot/glTF +Y",
            "forward_axis": "Godot local -Z",
            "skins": 1,
            "bones": len(rig.data.bones),
            "animations": list(REQUIRED_CLIPS),
        },
        "file_size_bytes": os.path.getsize(OUT_GLB),
        "paint_size_bytes": os.path.getsize(PAINT_PNG),
    }
    os.makedirs(os.path.dirname(MANIFEST), exist_ok=True)
    with open(MANIFEST, "w", encoding="utf-8", newline="\n") as handle:
        json.dump(manifest, handle, indent=2)
        handle.write("\n")
    print("recorded {0} in {1}".format(NAME, MANIFEST))


def validate(mesh_obj: bpy.types.Object, rig: bpy.types.Object) -> None:
    low, high = mesh_bounds(mesh_obj)
    size = high - low
    mesh = mesh_obj.data
    clips = tuple(track.name for track in rig.animation_data.nla_tracks)
    if clips != REQUIRED_CLIPS:
        raise SystemExit("unexpected NLA clips: " + repr(clips))
    if mesh.color_attributes.get(biome.COLOR_ATTRIBUTE) is None:
        raise SystemExit("the runtime mesh lost its COLOR_0 regions")
    if mesh.uv_layers.get(biome.PAINT_UV_NAME) is None:
        raise SystemExit("the runtime mesh lost its paint UVs")
    if abs(size.z - TARGET_HEIGHT) > 0.005 or abs(low.z) > 0.006:
        raise SystemExit("runtime bounds are not normalized and grounded")
    left = rig.data.bones["LeftFrontFoot"]
    if left.head_local.x >= 0.0:
        raise SystemExit("LeftFrontFoot is on the wrong Blender side")
    horn = rig.data.bones["Horn"]
    if horn.tail_local.y <= rig.data.bones["Head"].head_local.y \
            or horn.tail_local.z <= horn.head_local.z:
        raise SystemExit("the horn does not rake forward and up")
    print("final: bounds={0:.3f} x {1:.3f} x {2:.3f} m, floor={3:+.4f}, "
          "mesh={4} verts/{5} tris, bones={6}, clips={7}".format(
              size.x, size.y, size.z, low.z, len(mesh.vertices),
              triangle_count(mesh), len(rig.data.bones), len(clips)))


def main() -> None:
    os.makedirs(os.path.dirname(OUT_BLEND), exist_ok=True)
    mesh_obj, source_hash = normalize_source()
    optimize(mesh_obj)
    rig = build_armature()
    skin(mesh_obj, rig)
    asset = recipe()
    paint_regions(mesh_obj, asset)

    anim = load_sibling("build_animations.py", "_rhino")
    # Pose offsets are authored as shares of body height, the way the shared
    # tables are authored as shares of the player's.
    anim.BODY_SCALE = TARGET_HEIGHT
    animations = rhino_animations(anim)
    if tuple(spec[0] for spec in animations) != REQUIRED_CLIPS:
        raise SystemExit("the rhino animation table is incomplete")
    anim.ANIMATIONS = animations
    anim.export = export_runtime
    anim.bake_into_open_file(OUT_BLEND, OUT_GLB)

    validate(mesh_obj, rig)
    image = write_paint_texture()
    merge_manifest(mesh_obj, rig)
    written = render_previews(rig, mesh_obj, asset, image)
    for key in sorted(written):
        print("  preview {0}: {1}".format(key, os.path.basename(written[key])))
    if file_sha256(SRC_BLEND) != source_hash:
        raise SystemExit("the source sculpt changed during the build")
    print("source preserved: sha256=" + source_hash)


if __name__ == "__main__":
    main()
