"""Shared authoring kit for rigged Strange Planet land fauna.

Creatures are grown as one connected organic mesh from an anatomical vertex
tree (Blender's Skin modifier plus subdivision), the same base-mesh tactic
used for production characters. Limbs are branches of that tree, not separate
cylinders parented onto a box. A skeleton is then measured from the same
joints the skin grew from, so bones sit inside the forms they deform.
"""

from __future__ import annotations

from dataclasses import dataclass, field
import hashlib
import importlib.util
import json
import math
import os
import struct
import sys
from typing import Callable, Optional, Sequence

import bpy
from mathutils import Matrix, Vector


SOURCE_DIR = os.path.dirname(os.path.abspath(__file__))
ROOT = os.path.abspath(os.path.join(SOURCE_DIR, os.pardir, os.pardir, os.pardir))
if SOURCE_DIR not in sys.path:
    sys.path.insert(0, SOURCE_DIR)

import build_biome_assets as biome


MODEL_DIR = os.path.join(ROOT, "assets", "runtime", "fauna", "models")
PAINT_DIR = os.path.join(ROOT, "assets", "runtime", "biomes", "paint")
WORK_DIR = os.path.join(ROOT, "assets", "work")
MANIFEST = os.path.join(
    ROOT, "assets", "runtime", "fauna", "manifests", "fauna_assets.json")
PREVIEW_DIR = os.path.join(ROOT, "assets", "previews", "fauna")
GENERATOR = "assets/source/blender/build_fauna_creatures.py"
FPS = 30
PAINT_SIZE = 512

REQUIRED_CORE_CLIPS = (
    "Idle", "Walk", "Run", "Attack", "HitReact", "Defeat",
)


@dataclass
class Joint:
    """One anatomical landmark. Volume-only joints add flesh, not bones."""

    name: str
    parent: Optional[str]
    position: tuple[float, float, float]
    radius: float | tuple[float, float]
    deform: bool = True
    volume_only: bool = False
    connected: bool = False
    tail: Optional[tuple[float, float, float]] = None


@dataclass
class CreatureSpec:
    name: str
    display_name: str
    form: str
    seed: int
    height: float
    palette: tuple
    triangle_budget: tuple[int, int]
    collision_hint: dict
    paint_style: str
    emission_style: str
    emission_strength: float
    joints: Sequence[Joint]
    limb_groups: Sequence[Sequence[str]]
    clips: tuple[str, ...]
    region_of: Callable[[Vector, float], int]
    paint_pixel: Callable[[int, float, float], tuple[float, float, float, float]]
    animations: Callable[object, list]
    roughness: float = 0.58


def rgba(*hex_values: str) -> tuple:
    return tuple(biome._rgba(value) for value in hex_values)


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
                 for index in range(len(first)))


def ease(value: float) -> float:
    value = clamp01(value)
    return value * value * (3.0 - 2.0 * value)


def pulse(time: float, start: float, peak: float, end: float) -> float:
    if time <= start or time >= end:
        return 0.0
    if time < peak:
        return ease((time - start) / max(peak - start, 1.0e-6))
    return 1.0 - ease((time - peak) / max(end - peak, 1.0e-6))


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


def load_sibling(filename: str, suffix: str):
    path = os.path.join(SOURCE_DIR, filename)
    spec = importlib.util.spec_from_file_location(
        os.path.splitext(filename)[0] + suffix, path)
    module = importlib.util.module_from_spec(spec)
    spec.loader.exec_module(module)
    return module


def joint_map(joints: Sequence[Joint]) -> dict[str, Joint]:
    mapped = {joint.name: joint for joint in joints}
    if len(mapped) != len(joints):
        raise SystemExit("duplicate joint names")
    return mapped


def deform_bones(joints: Sequence[Joint]) -> tuple[str, ...]:
    return tuple(joint.name for joint in joints
                 if not joint.volume_only and joint.deform and joint.name != "Root")


# --------------------------------------------------------------------------
# Organic base mesh
# --------------------------------------------------------------------------

def reset_scene() -> None:
    biome._reset_scene()
    scene = bpy.context.scene
    scene.unit_settings.system = "METRIC"
    scene.unit_settings.length_unit = "METERS"
    scene.render.fps = FPS


def grow_skin(joints: Sequence[Joint]) -> bpy.types.Object:
    """Grow one watertight body from the anatomical tree.

    Root is armature-only. Leaving it in the skin tree grew a visible stalk
    from the ground up to the hips, so the flesh starts at the first real joint.
    Extra volume joints thicken chests, necks, and waists so limbs grow out of
    the body instead of hanging beside a separate torso blob.
    """
    usable: list[Joint] = []
    for joint in joints:
        if joint.name == "Root":
            continue
        parent = None if joint.parent in (None, "Root") else joint.parent
        usable.append(Joint(
            joint.name, parent, joint.position, joint.radius,
            joint.deform, joint.volume_only, joint.connected, joint.tail))
    joints = usable
    names = [joint.name for joint in joints]
    index = {name: i for i, name in enumerate(names)}
    vertices = [Vector(joint.position) for joint in joints]
    edges: list[tuple[int, int]] = []
    for joint in joints:
        if joint.parent is None:
            continue
        if joint.parent not in index:
            raise SystemExit(
                "{0} parent {1} is missing".format(joint.name, joint.parent))
        edges.append((index[joint.parent], index[joint.name]))
    if not edges:
        raise SystemExit("anatomical tree has no connections")

    mesh = bpy.data.meshes.new("CreatureMesh")
    mesh.from_pydata([tuple(point) for point in vertices], edges, [])
    mesh.update()
    mesh_obj = bpy.data.objects.new("Character", mesh)
    bpy.context.collection.objects.link(mesh_obj)
    activate(mesh_obj)

    skin = mesh_obj.modifiers.new("Skin", "SKIN")
    skin.use_smooth_shade = True
    skin.use_x_symmetry = False
    skin.use_y_symmetry = False
    skin.use_z_symmetry = False
    if hasattr(skin, "branch_smoothing"):
        skin.branch_smoothing = 0.62

    if not mesh.skin_vertices:
        raise SystemExit("Skin modifier created no vertex radii")
    layer = mesh.skin_vertices[0]
    rooted = False
    for i, joint in enumerate(joints):
        radius = joint.radius
        if not isinstance(radius, tuple):
            radius = (radius, radius)
        layer.data[i].radius = (float(radius[0]), float(radius[1]))
        is_root = joint.parent is None and not rooted
        layer.data[i].use_root = is_root
        if is_root:
            rooted = True

    subdiv = mesh_obj.modifiers.new("OrganicSubD", "SUBSURF")
    subdiv.levels = 2
    subdiv.render_levels = 2
    subdiv.subdivision_type = "CATMULL_CLARK"
    activate(mesh_obj)
    bpy.ops.object.modifier_apply(modifier=skin.name)
    bpy.ops.object.modifier_apply(modifier=subdiv.name)

    smooth = mesh_obj.modifiers.new("OrganicSmooth", "LAPLACIANSMOOTH")
    smooth.lambda_factor = 0.30
    smooth.iterations = 6
    if hasattr(smooth, "use_normalized"):
        smooth.use_normalized = True
    bpy.ops.object.modifier_apply(modifier=smooth.name)

    for polygon in mesh_obj.data.polygons:
        polygon.use_smooth = True
    mesh_obj.data.update()
    print("  skin: {0} verts, {1} tris from {2} joints".format(
        len(mesh_obj.data.vertices), triangle_count(mesh_obj.data),
        len(joints)))
    return mesh_obj


def normalize_grown(
    mesh_obj: bpy.types.Object,
    joints: Sequence[Joint],
    target_height: float,
) -> list[Joint]:
    """Fit the grown body to authored height, ground it, and move the joints with it."""
    low, high = mesh_bounds(mesh_obj)
    span = high.z - low.z
    if span < 1.0e-4:
        raise SystemExit("grown mesh has no height")
    scale = target_height / span
    mid_x = (low.x + high.x) * 0.5
    for vertex in mesh_obj.data.vertices:
        point = vertex.co
        vertex.co = Vector((
            (point.x - mid_x) * scale,
            point.y * scale,
            (point.z - low.z) * scale,
        ))
    mesh_obj.data.update()
    mesh_obj.matrix_world = Matrix.Identity(4)

    def transformed(point: tuple[float, float, float]) -> tuple[float, float, float]:
        return (
            (point[0] - mid_x) * scale,
            point[1] * scale,
            (point[2] - low.z) * scale,
        )

    moved: list[Joint] = []
    for joint in joints:
        moved.append(Joint(
            joint.name,
            joint.parent,
            transformed(joint.position),
            (
                (joint.radius[0] * scale, joint.radius[1] * scale)
                if isinstance(joint.radius, tuple)
                else joint.radius * scale
            ),
            joint.deform,
            joint.volume_only,
            joint.connected,
            None if joint.tail is None else transformed(joint.tail),
        ))
    low, high = mesh_bounds(mesh_obj)
    print("  normalize: scale={0:.4f}, height={1:.3f}, floor={2:+.4f}".format(
        scale, high.z - low.z, low.z))
    return moved


def fit_triangle_budget(mesh_obj: bpy.types.Object,
                        budget: tuple[int, int]) -> None:
    minimum, maximum = budget
    target = (minimum + maximum) // 2
    count = triangle_count(mesh_obj.data)
    if count < minimum:
        subdiv = mesh_obj.modifiers.new("BudgetSubD", "SUBSURF")
        subdiv.levels = 1
        subdiv.render_levels = 1
        activate(mesh_obj)
        bpy.ops.object.modifier_apply(modifier=subdiv.name)
        count = triangle_count(mesh_obj.data)
    if count > maximum:
        modifier = mesh_obj.modifiers.new("HerdBudget", "DECIMATE")
        modifier.decimate_type = "COLLAPSE"
        modifier.ratio = max(target / float(count), 0.05)
        modifier.use_collapse_triangulate = True
        activate(mesh_obj)
        bpy.ops.object.modifier_apply(modifier=modifier.name)
        count = triangle_count(mesh_obj.data)
    if not minimum <= count <= maximum:
        raise SystemExit("mesh has {0} triangles, budget is {1}..{2}".format(
            count, minimum, maximum))
    for polygon in mesh_obj.data.polygons:
        polygon.use_smooth = True
    mesh_obj.data.update()
    print("  budget: {0} tris".format(count))


# --------------------------------------------------------------------------
# Skeleton and weights
# --------------------------------------------------------------------------

def _bone_tail(joint: Joint, children: Sequence[Joint]) -> Vector:
    if joint.tail is not None:
        return Vector(joint.tail)
    deform_children = [child for child in children if not child.volume_only]
    if deform_children:
        return Vector(deform_children[0].position)
    head = Vector(joint.position)
    if joint.parent is None:
        return head + Vector((0.0, 0.0, 0.08))
    return head + Vector((0.0, 0.03, 0.02))


def build_armature(joints: Sequence[Joint]) -> bpy.types.Object:
    children: dict[str, list[Joint]] = {joint.name: [] for joint in joints}
    for joint in joints:
        if joint.parent is not None:
            children.setdefault(joint.parent, []).append(joint)

    armature = bpy.data.armatures.new("CharacterSkeleton")
    rig = bpy.data.objects.new("CharacterRig", armature)
    bpy.context.collection.objects.link(rig)
    activate(rig)
    bpy.ops.object.mode_set(mode="EDIT")
    created = 0
    for joint in joints:
        if joint.volume_only:
            continue
        bone = armature.edit_bones.new(joint.name)
        bone.head = Vector(joint.position)
        bone.tail = _bone_tail(joint, children.get(joint.name, ()))
        if (bone.tail - bone.head).length < 1.0e-4:
            bone.tail = bone.head + Vector((0.0, 0.02, 0.02))
        if joint.parent is not None and joint.parent in armature.edit_bones:
            bone.parent = armature.edit_bones[joint.parent]
            bone.use_connect = joint.connected
        created += 1
    bpy.ops.armature.calculate_roll(type="GLOBAL_POS_Y")
    bpy.ops.object.mode_set(mode="OBJECT")
    if "Root" in armature.bones:
        armature.bones["Root"].use_deform = False
    print("  rig: {0} bones".format(created))
    return rig


def _limb_lookup(limb_groups: Sequence[Sequence[str]]) -> dict[str, int]:
    lookup: dict[str, int] = {}
    for index, group in enumerate(limb_groups):
        for name in group:
            lookup[name] = index
    return lookup


def skin(mesh_obj: bpy.types.Object, rig: bpy.types.Object,
         limb_groups: Sequence[Sequence[str]],
         deform_names: Sequence[str]) -> None:
    activate(mesh_obj)
    mesh_obj.select_set(True)
    rig.select_set(True)
    bpy.context.view_layer.objects.active = rig
    bpy.ops.object.parent_set(type="ARMATURE_AUTO")

    groups = {group.name: group for group in mesh_obj.vertex_groups}
    missing = [name for name in deform_names if name not in groups]
    if missing:
        raise SystemExit("automatic weights skipped: " + ", ".join(missing))

    bone_heads = {
        bone.name: Vector(bone.head_local)
        for bone in rig.data.bones if bone.use_deform
    }
    lookup = _limb_lookup(limb_groups)
    dropped = 0
    rows: list[dict[str, float]] = []
    for vertex in mesh_obj.data.vertices:
        mapped: dict[str, float] = {}
        nearest_limb = None
        nearest_gap = 1.0e9
        for name, head in bone_heads.items():
            limb = lookup.get(name)
            if limb is None:
                continue
            gap = (vertex.co - head).length
            if gap < nearest_gap:
                nearest_gap = gap
                nearest_limb = limb
        for assignment in vertex.groups:
            name = mesh_obj.vertex_groups[assignment.group].name
            amount = assignment.weight
            if amount <= 1.0e-6:
                continue
            limb = lookup.get(name)
            if limb is not None and nearest_limb is not None \
                    and limb != nearest_limb:
                dropped += 1
                continue
            mapped[name] = mapped.get(name, 0.0) + amount
        kept = sorted(mapped.items(), key=lambda item: item[1],
                      reverse=True)[:4]
        total = sum(amount for _, amount in kept)
        if total < 1.0e-6:
            fallback = "Hips" if "Hips" in bone_heads else deform_names[0]
            nearest = min(bone_heads.items(),
                          key=lambda item: (vertex.co - item[1]).length)
            fallback = nearest[0] if nearest[0] in deform_names else fallback
            kept = [(fallback, 1.0)]
            total = 1.0
        rows.append({name: amount / total for name, amount in kept})

    mesh_obj.vertex_groups.clear()
    rebuilt = {name: mesh_obj.vertex_groups.new(name=name)
               for name in deform_names}
    counts = {name: 0 for name in deform_names}
    for index, mapped in enumerate(rows):
        for name, amount in mapped.items():
            if name not in rebuilt:
                continue
            rebuilt[name].add([index], amount, "REPLACE")
            counts[name] += 1
    empty = [name for name, count in counts.items() if count == 0]
    if empty:
        # Heat weights skip tiny feature bones (eye stalks, fangs, crests).
        # Claim the nearest vertices so the bone still deforms its own flesh.
        claimed = 0
        for name in empty:
            head = bone_heads.get(name)
            if head is None:
                continue
            nearest = sorted(
                range(len(mesh_obj.data.vertices)),
                key=lambda index: (
                    mesh_obj.data.vertices[index].co - head).length)
            for index in nearest[:8]:
                rebuilt[name].add([index], 0.85, "REPLACE")
                counts[name] += 1
                claimed += 1
        empty = [name for name, count in counts.items() if count == 0]
        if empty:
            raise SystemExit("unweighted bones: " + ", ".join(empty))
        print("  skin: claimed {0} verts for tiny feature bones".format(claimed))
    print("  skin: max 4 influences, {0} stray limb weights dropped".format(
        dropped))


# --------------------------------------------------------------------------
# Colour paint
# --------------------------------------------------------------------------

def recipe_for(spec: CreatureSpec) -> biome.AssetRecipe:
    return biome.AssetRecipe(
        spec.name, "fauna", "flyer", spec.form, spec.seed, spec.height,
        spec.palette, spec.triangle_budget, spec.collision_hint,
        spec.paint_style, spec.emission_style, spec.emission_strength,
        roughness=spec.roughness, smooth=True,
    )


def paint_regions(mesh_obj: bpy.types.Object, spec: CreatureSpec,
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
    tally = {index: 0 for index in range(len(spec.palette))}
    for polygon in mesh.polygons:
        palette_index = spec.region_of(polygon.center, spec.height)
        palette_index = max(0, min(palette_index, len(spec.palette) - 1))
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
                spec.palette[palette_index], coordinate, spec.height,
                spec.seed, palette_index)
            paint_uv.data[loop].uv = uv
    mesh.color_attributes.active_color_name = biome.COLOR_ATTRIBUTE
    mesh.color_attributes.render_color_index = 0
    mesh.uv_layers.active = paint_uv
    mesh.uv_layers.active_index = list(mesh.uv_layers).index(paint_uv)
    mesh.materials.clear()
    mesh.materials.append(biome._make_material(asset))
    mesh.update()
    unused = [index for index, count in tally.items() if count <= 0]
    if unused:
        # A grown organic mesh can miss a tiny authored region. Steal a handful
        # of faces from the largest band so every palette slot still ships.
        donor = max(tally, key=tally.get)
        stolen = 0
        for polygon in mesh.polygons:
            if stolen >= len(unused):
                break
            if spec.region_of(polygon.center, spec.height) != donor:
                continue
            palette_index = unused[stolen]
            tally[donor] -= 1
            tally[palette_index] += 1
            stolen += 1
            coordinates = [
                mesh.vertices[mesh.loops[loop].vertex_index].co
                for loop in polygon.loop_indices
            ]
            uvs = biome._polygon_paint_uvs(
                asset, polygon, coordinates, palette_index)
            for loop, uv in zip(polygon.loop_indices, uvs):
                coordinate = mesh.vertices[mesh.loops[loop].vertex_index].co
                colour.data[loop].color = biome._colour_value(
                    spec.palette[palette_index], coordinate, spec.height,
                    spec.seed, palette_index)
                paint_uv.data[loop].uv = uv
        unused = [index for index, count in tally.items() if count <= 0]
        if unused:
            raise SystemExit(
                "palette regions claimed no polygons: " + str(unused))
    print("  paint regions: " + ", ".join(
        "{0}:{1}".format(index, tally[index]) for index in sorted(tally)))
    return tally


def write_paint_texture(spec: CreatureSpec) -> bpy.types.Image:
    path = os.path.join(PAINT_DIR, spec.name + "_paint.png")
    os.makedirs(os.path.dirname(path), exist_ok=True)
    image = bpy.data.images.new(
        spec.name + "_paint", width=PAINT_SIZE, height=PAINT_SIZE,
        alpha=True, float_buffer=False)
    try:
        image.colorspace_settings.name = "sRGB"
    except TypeError:
        pass
    count = len(spec.palette)
    gutter = biome.PAINT_GUTTER / (biome.PAINT_SIZE / count)
    usable = max(1.0 - gutter * 2.0, 1.0e-5)
    pixels: list[float] = []
    for row in range(PAINT_SIZE):
        atlas_v = (row + 0.5) / PAINT_SIZE * count
        palette_index = min(int(atlas_v), count - 1)
        local_v = clamp01((atlas_v - palette_index - gutter) / usable)
        for column in range(PAINT_SIZE):
            pixels.extend(spec.paint_pixel(
                palette_index, (column + 0.5) / PAINT_SIZE, local_v))
    image.pixels.foreach_set(pixels)
    image.filepath_raw = path
    image.file_format = "PNG"
    image.save()
    if not os.path.isfile(path) or os.path.getsize(path) <= 0:
        raise SystemExit("colour paint did not produce " + path)
    print("  paint: {0} ({1:.1f} KB)".format(
        os.path.basename(path), os.path.getsize(path) / 1024.0))
    return image


# --------------------------------------------------------------------------
# Shared paint motifs (broad, mip-safe)
# --------------------------------------------------------------------------

def _finish_motif(result, emission, u, v, phase):
    drift = 0.96 + 0.04 * math.sin(math.tau * (u * 0.8 + v * 0.6 + phase * 0.5))
    return (
        clamp01(result[0] * drift),
        clamp01(result[1] * drift),
        clamp01(result[2] * drift),
        clamp01(emission),
    )


def motif_streaks(base, u, v, phase, emission_base=0.05):
    pale = mix(base, (1.0, 1.0, 1.0, 1.0), 0.28)
    deep = (base[0] * 0.55, base[1] * 0.56, base[2] * 0.62, 1.0)
    fibre = 0.5 + 0.5 * math.sin(
        math.tau * (v * 2.1 + 0.16 * math.sin(math.tau * (u * 1.4 + phase)) + phase))
    clump = 0.5 + 0.5 * math.sin(math.tau * (u * 1.3 - v * 0.7 + phase * 1.3))
    result = mix(mix(base, deep, (1.0 - fibre) * 0.22), pale, fibre * clump * 0.28)
    return _finish_motif(result, emission_base + fibre * 0.07, u, v, phase)


def motif_bands(base, accent, u, v, phase, emission_boost=0.42):
    pale = mix(base, (1.0, 1.0, 1.0, 1.0), 0.24)
    deep = (base[0] * 0.52, base[1] * 0.54, base[2] * 0.60, 1.0)
    band = math.sin(math.tau * (v * 0.85 + 0.10 * math.sin(math.tau * u) + phase))
    edge = 1.0 - smoothstep(0.12, 0.36, abs(band))
    result = mix(mix(base, deep, clamp01(-band) * 0.40), pale, clamp01(band) * 0.24)
    result = mix(result, accent, edge * 0.32)
    return _finish_motif(result, 0.08 + edge * emission_boost, u, v, phase)


def motif_spots(base, u, v, phase, emission_boost=0.55):
    pale = mix(base, (1.0, 1.0, 1.0, 1.0), 0.36)
    radius = math.hypot((u - 0.5) * 1.05, (v - 0.5) * 1.05)
    wobble = 0.04 * math.sin(math.tau * (u * 2.0 + phase))
    core = 1.0 - smoothstep(0.16, 0.34, radius + wobble)
    halo = 1.0 - smoothstep(0.30, 0.48, radius)
    result = mix(mix(base, pale, halo * 0.55), pale, core * 0.55)
    return _finish_motif(
        result, clamp01(0.10 + halo * 0.36 + core * emission_boost), u, v, phase)


def motif_chevrons(base, u, v, phase, emission_boost=0.48):
    pale = mix(base, (1.0, 1.0, 1.0, 1.0), 0.30)
    deep = (base[0] * 0.50, base[1] * 0.52, base[2] * 0.60, 1.0)
    sweep = abs(u - 0.5) * 1.6 + v * 1.4 + phase
    chevron = 1.0 - smoothstep(0.14, 0.34, abs((sweep - math.floor(sweep)) - 0.5))
    result = mix(mix(base, deep, (1.0 - chevron) * 0.32), pale, chevron * 0.32)
    return _finish_motif(result, 0.08 + chevron * emission_boost, u, v, phase)


def motif_rings(base, u, v, phase, emission_boost=0.40):
    pale = mix(base, (1.0, 1.0, 1.0, 1.0), 0.22)
    deep = (base[0] * 0.48, base[1] * 0.50, base[2] * 0.58, 1.0)
    rise = smoothstep(0.0, 0.9, v)
    rings = 1.0 - smoothstep(
        0.07, 0.22, abs(math.sin(math.tau * (v * 1.6 + phase))))
    result = mix(mix(base, deep, (1.0 - rise) * 0.52), pale, rise * 0.20)
    result = mix(result, pale, rings * 0.28)
    return _finish_motif(result, 0.05 + rings * emission_boost, u, v, phase)


def motif_blaze(base, u, v, phase, emission_boost=0.16):
    pale = mix(base, (1.0, 1.0, 1.0, 1.0), 0.40)
    deep = (base[0] * 0.62, base[1] * 0.64, base[2] * 0.68, 1.0)
    blaze = 1.0 - smoothstep(0.16, 0.46, abs(u - 0.5))
    result = mix(mix(base, pale, blaze * 0.40), deep,
                 smoothstep(0.62, 1.0, v) * 0.18)
    return _finish_motif(result, 0.06 + blaze * emission_boost, u, v, phase)


# --------------------------------------------------------------------------
# Export, previews, manifest
# --------------------------------------------------------------------------

def export_runtime(rig: bpy.types.Object, mesh_obj: bpy.types.Object,
                   glb_path: str) -> None:
    os.makedirs(os.path.dirname(glb_path), exist_ok=True)
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
        filepath=glb_path,
        export_format="GLB",
        use_selection=True,
        export_apply=True,
        export_skins=True,
        export_animations=True,
        export_animation_mode="NLA_TRACKS",
        export_frame_range=False,
        export_force_sampling=True,
        export_yup=True,
        export_texcoords=True,
        export_vertex_color="ACTIVE",
        export_all_vertex_colors=False,
    )
    print("  wrote {0} ({1:.1f} KB)".format(
        glb_path, os.path.getsize(glb_path) / 1024.0))


def preview_with_paint(material: bpy.types.Material, image: bpy.types.Image,
                       emission_strength: float) -> None:
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
        multiplier.inputs[1].default_value = emission_strength
        links.new(texture.outputs["Alpha"], multiplier.inputs[0])
        links.new(multiplier.outputs[0], strength)


def render_pose(rig: bpy.types.Object, clip: str, share: float,
                path: str) -> None:
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


def render_previews(spec: CreatureSpec, rig: bpy.types.Object,
                    mesh_obj: bpy.types.Object, asset: biome.AssetRecipe,
                    image: bpy.types.Image) -> dict[str, str]:
    preview_with_paint(
        mesh_obj.data.materials[0], image, spec.emission_strength)
    rig.rotation_euler.z += math.pi
    close_path = os.path.join(PREVIEW_DIR, spec.name + "_close.png")
    biome._render_preview(mesh_obj, asset, close_path)
    written = {"close": close_path}
    for clip, share, key in (
            ("Walk", 0.28, "walk"),
            ("Attack", 0.48, "attack"),
    ):
        if clip not in {track.name for track in rig.animation_data.nla_tracks}:
            continue
        path = os.path.join(PREVIEW_DIR, "{0}_{1}.png".format(spec.name, key))
        render_pose(rig, clip, share, path)
        written[key] = path
    camera = bpy.data.objects.get("BiomePreviewCamera")
    ground = bpy.data.objects.get("BiomePreviewGround")
    if camera is not None:
        camera.data.ortho_scale *= 3.2
    if ground is not None:
        ground.scale.x = 3.5
        ground.scale.y = 3.5
    gameplay_path = os.path.join(PREVIEW_DIR, spec.name + "_gameplay.png")
    render_pose(rig, "Idle", 0.0, gameplay_path)
    written["gameplay"] = gameplay_path
    rig.rotation_euler.z -= math.pi
    return written


def merge_manifest(spec: CreatureSpec, mesh_obj: bpy.types.Object,
                   rig: bpy.types.Object, clips: Sequence[str]) -> None:
    manifest: dict = {}
    if os.path.isfile(MANIFEST):
        with open(MANIFEST, encoding="utf-8") as handle:
            manifest = json.load(handle)
    assets = manifest.setdefault("assets", {})
    low, high = mesh_bounds(mesh_obj)
    glb_path = os.path.join(MODEL_DIR, spec.name + ".glb")
    paint_path = os.path.join(PAINT_DIR, spec.name + "_paint.png")
    assets[spec.name] = {
        "name": spec.name,
        "display_name": spec.display_name,
        "category": "land_fauna",
        "form": spec.form,
        "seed": spec.seed,
        "generator": GENERATOR,
        "work_blend": "assets/work/{0}_rigged.blend".format(spec.name),
        "glb": "assets/runtime/fauna/models/{0}.glb".format(spec.name),
        "color_paint": (
            "assets/runtime/biomes/paint/{0}_paint.png".format(spec.name)),
        "close_preview": "assets/previews/fauna/{0}_close.png".format(spec.name),
        "gameplay_distance_preview": (
            "assets/previews/fauna/{0}_gameplay.png".format(spec.name)),
        "authored_height": round(high.z - low.z, 6),
        "triangle_count": triangle_count(mesh_obj.data),
        "collision_hint": spec.collision_hint,
        "color_paint_style": spec.paint_style,
        "emission_style": spec.emission_style,
        "emission_strength": spec.emission_strength,
        "runtime_contract": {
            "mesh_node": "Character",
            "vertex_colour": "COLOR_0 semantic region colors",
            "color_paint_uv": "TEXCOORD_0",
            "emission_mask": (
                "assets/runtime/biomes/paint/{0}_paint.png alpha; "
                "never transparency".format(spec.name)),
            "ground_axis": "Godot/glTF +Y",
            "forward_axis": "Godot local -Z",
            "skins": 1,
            "bones": len(rig.data.bones),
            "animations": list(clips),
        },
        "file_size_bytes": os.path.getsize(glb_path),
        "paint_size_bytes": os.path.getsize(paint_path),
    }
    os.makedirs(os.path.dirname(MANIFEST), exist_ok=True)
    with open(MANIFEST, "w", encoding="utf-8", newline="\n") as handle:
        json.dump(manifest, handle, indent=2)
        handle.write("\n")
    print("  recorded {0} in manifest".format(spec.name))


# --------------------------------------------------------------------------
# Audits
# --------------------------------------------------------------------------

def _nla_names(rig: bpy.types.Object) -> tuple[str, ...]:
    return tuple(track.name for track in rig.animation_data.nla_tracks)


def audit_contract(spec: CreatureSpec, mesh_obj: bpy.types.Object,
                   rig: bpy.types.Object) -> list[str]:
    """First audit: topology, contract, bone placement, clip table."""
    problems: list[str] = []
    low, high = mesh_bounds(mesh_obj)
    size = high - low
    mesh = mesh_obj.data
    clips = _nla_names(rig)
    if clips != spec.clips:
        problems.append("NLA clips {0} != {1}".format(clips, spec.clips))
    if mesh.color_attributes.get(biome.COLOR_ATTRIBUTE) is None:
        problems.append("missing COLOR_0")
    if mesh.uv_layers.get(biome.PAINT_UV_NAME) is None:
        problems.append("missing paint UVs")
    if abs(size.z - spec.height) > 0.02:
        problems.append("height {0:.3f} != {1:.3f}".format(size.z, spec.height))
    if abs(low.z) > 0.02:
        problems.append("floor is {0:+.4f}".format(low.z))
    minimum, maximum = spec.triangle_budget
    count = triangle_count(mesh)
    if not minimum <= count <= maximum:
        problems.append("triangles {0} outside {1}..{2}".format(
            count, minimum, maximum))

    bones = rig.data.bones
    if "Root" in bones and bones["Root"].use_deform:
        problems.append("Root should not deform")
    for bone in bones:
        if bone.name.startswith("Left") and bone.head_local.x >= 0.02:
            problems.append("{0} is not on the left".format(bone.name))
        if bone.name.startswith("Right") and bone.head_local.x <= -0.02:
            problems.append("{0} is not on the right".format(bone.name))
        if bone.use_deform:
            head = Vector(bone.head_local)
            if (head.x < low.x - 0.05 or head.x > high.x + 0.05
                    or head.y < low.y - 0.05 or head.y > high.y + 0.05
                    or head.z < low.z - 0.05 or head.z > high.z + 0.08):
                problems.append("{0} sits outside the mesh bounds".format(
                    bone.name))

    groups = {group.name for group in mesh_obj.vertex_groups}
    for name in deform_bones(spec.joints):
        if name not in groups:
            problems.append("no weights for " + name)

    used = set()
    for edge in mesh.edges:
        used.add(edge.vertices[0])
        used.add(edge.vertices[1])
    loose = len(mesh.vertices) - len(used)
    if loose > 8:
        problems.append("{0} loose vertices".format(loose))

    print("  audit 1 (contract): {0}".format(
        "pass" if not problems else "{0} issue(s)".format(len(problems))))
    for problem in problems:
        print("    - " + problem)
    return problems


def _solo_clip(rig: bpy.types.Object, clip: str, share: float) -> None:
    strip = None
    for track in rig.animation_data.nla_tracks:
        track.mute = track.name != clip
        if track.name == clip and track.strips:
            strip = track.strips[0]
    if strip is None:
        raise SystemExit("missing clip " + clip)
    rig.animation_data.action = None
    bpy.context.scene.frame_set(int(round(
        strip.frame_start
        + (strip.frame_end - strip.frame_start) * clamp01(share))))
    bpy.context.view_layer.update()


def _posed_mesh(mesh_obj: bpy.types.Object) -> bpy.types.Object:
    depsgraph = bpy.context.evaluated_depsgraph_get()
    return mesh_obj.evaluated_get(depsgraph)


def _lowest_z(mesh_obj: bpy.types.Object) -> float:
    return min((mesh_obj.matrix_world @ vertex.co).z
               for vertex in mesh_obj.data.vertices)


def _bone_quaternion_delta(rig: bpy.types.Object) -> float:
    total = 0.0
    for pose_bone in rig.pose.bones:
        quat = pose_bone.matrix.to_quaternion()
        rest = pose_bone.bone.matrix_local.to_quaternion()
        total += abs(rest.rotation_difference(quat).angle)
    return total


def read_glb_document(path: str) -> dict:
    with open(path, "rb") as handle:
        magic, _version, _length = struct.unpack("<4sII", handle.read(12))
        if magic != b"glTF":
            raise SystemExit("not a GLB: " + path)
        chunk_len, chunk_type = struct.unpack("<I4s", handle.read(8))
        payload = handle.read(chunk_len)
        if chunk_type not in (b"JSON", b"json"):
            raise SystemExit("GLB JSON chunk missing in " + path)
        return json.loads(payload.decode("utf-8"))


def audit_production(spec: CreatureSpec, mesh_obj: bpy.types.Object,
                     rig: bpy.types.Object, image: bpy.types.Image) -> list[str]:
    """Second audit: posed deformation, paint sampling, and the exported GLB."""
    problems: list[str] = []

    _solo_clip(rig, "Idle", 0.0)
    idle_travel = _bone_quaternion_delta(rig)
    _solo_clip(rig, "Walk", 0.25)
    walk_travel = _bone_quaternion_delta(rig)
    walk_floor = _lowest_z(_posed_mesh(mesh_obj))
    _solo_clip(rig, "Walk", 0.55)
    walk_travel = max(walk_travel, _bone_quaternion_delta(rig))
    _solo_clip(rig, "Attack", 0.48)
    attack_travel = _bone_quaternion_delta(rig)
    if walk_travel < math.radians(18.0):
        problems.append("Walk barely moves the skeleton ({0:.1f} deg)".format(
            math.degrees(walk_travel)))
    if attack_travel < math.radians(14.0):
        problems.append("Attack barely moves the skeleton ({0:.1f} deg)".format(
            math.degrees(attack_travel)))
    if walk_travel <= idle_travel + math.radians(6.0):
        problems.append("Walk is not distinct from Idle")
    if walk_floor < -0.22 * spec.height:
        problems.append("Walk plants feet {0:.3f} m through the floor".format(
            walk_floor))

    # Bones must sit in the flesh, not hover beside a stacked primitive.
    rest_clear()
    activate(rig)
    bpy.ops.object.mode_set(mode="OBJECT")
    heads = [Vector(bone.head_local) for bone in rig.data.bones if bone.use_deform]
    vertices = [vertex.co.copy() for vertex in mesh_obj.data.vertices]
    far = []
    limit = spec.height * 0.30
    for bone in rig.data.bones:
        if not bone.use_deform:
            continue
        head = Vector(bone.head_local)
        gap = min((head - vertex).length for vertex in vertices)
        if gap > limit:
            far.append("{0} ({1:.3f} m)".format(bone.name, gap))
    if far:
        problems.append(
            "{0} deform bones sit more than {1:.3f} m from flesh: {2}".format(
                len(far), limit, ", ".join(far)))

    pixels = list(image.pixels)
    width, height = image.size
    variance = 0.0
    samples = 0
    last = None
    step = max(width // 16, 1)
    for row in range(0, height, step):
        for column in range(0, width, step):
            index = (row * width + column) * 4
            colour = pixels[index:index + 3]
            if last is not None:
                variance += sum(abs(a - b) for a, b in zip(colour, last))
            last = colour
            samples += 1
    if samples < 8 or variance / max(samples, 1) < 0.04:
        problems.append("paint PNG is nearly flat")
    alphas = [pixels[index + 3] for index in range(0, len(pixels), 4)]
    if max(alphas) - min(alphas) < 0.08:
        problems.append("paint alpha has no emission variation")

    glb_path = os.path.join(MODEL_DIR, spec.name + ".glb")
    document = read_glb_document(glb_path)
    animations = [entry.get("name") for entry in document.get("animations") or []]
    for clip in spec.clips:
        if clip not in animations:
            problems.append("GLB is missing animation " + clip)
    if not document.get("skins"):
        problems.append("GLB has no skin")
    attributes = set()
    for mesh in document.get("meshes") or []:
        for primitive in mesh.get("primitives") or []:
            attributes.update((primitive.get("attributes") or {}).keys())
    if "COLOR_0" not in attributes:
        problems.append("GLB lost COLOR_0")
    if "TEXCOORD_0" not in attributes:
        problems.append("GLB lost TEXCOORD_0")

    rest_clear()
    print("  audit 2 (production): {0}".format(
        "pass" if not problems else "{0} issue(s)".format(len(problems))))
    for problem in problems:
        print("    - " + problem)
    return problems


def rest_clear() -> None:
    rig = bpy.data.objects.get("CharacterRig")
    if rig is None or rig.animation_data is None:
        return
    for track in rig.animation_data.nla_tracks:
        track.mute = True
    rig.animation_data.action = None
    for pose_bone in rig.pose.bones:
        pose_bone.rotation_mode = "QUATERNION"
        pose_bone.rotation_quaternion = (1.0, 0.0, 0.0, 0.0)
        pose_bone.location = Vector((0.0, 0.0, 0.0))
        pose_bone.scale = Vector((1.0, 1.0, 1.0))
    bpy.context.scene.frame_set(1)
    bpy.context.view_layer.update()


def build_creature(spec: CreatureSpec, skip_previews: bool = False) -> dict:
    print("\n=== {0} ===".format(spec.display_name))
    reset_scene()
    # Joints are authored in metres at the target height; skin grows around them.
    mesh_obj = grow_skin(spec.joints)
    placed = normalize_grown(mesh_obj, spec.joints, spec.height)
    fit_triangle_budget(mesh_obj, spec.triangle_budget)
    spec_for_rig = CreatureSpec(
        **{**spec.__dict__, "joints": placed})
    rig = build_armature(placed)
    skin(mesh_obj, rig, spec.limb_groups, deform_bones(placed))
    asset = recipe_for(spec)
    paint_regions(mesh_obj, spec, asset)

    work_blend = os.path.join(WORK_DIR, spec.name + "_rigged.blend")
    glb_path = os.path.join(MODEL_DIR, spec.name + ".glb")
    os.makedirs(WORK_DIR, exist_ok=True)
    os.makedirs(MODEL_DIR, exist_ok=True)

    anim = load_sibling("build_animations.py", "_" + spec.name)
    anim.BODY_SCALE = spec.height
    animations = spec.animations(anim)
    names = tuple(entry[0] for entry in animations)
    if names != spec.clips:
        raise SystemExit("animation table {0} != {1}".format(names, spec.clips))
    anim.ANIMATIONS = animations
    anim.export = lambda rig_obj, mesh: export_runtime(rig_obj, mesh, glb_path)
    anim.bake_into_open_file(work_blend, glb_path)

    mesh_obj = bpy.data.objects["Character"]
    rig = bpy.data.objects["CharacterRig"]
    first = audit_contract(spec_for_rig, mesh_obj, rig)
    image = write_paint_texture(spec)
    written: dict[str, str] = {}
    if not skip_previews:
        written = render_previews(spec, rig, mesh_obj, asset, image)
        rest_clear()
    second = audit_production(spec, mesh_obj, rig, image)
    merge_manifest(spec, mesh_obj, rig, spec.clips)
    problems = first + second
    if problems:
        raise SystemExit("{0} failed audit:\n  {1}".format(
            spec.name, "\n  ".join(problems)))
    print("  ready: {0} bones, {1} clips, {2} tris".format(
        len(rig.data.bones), len(spec.clips), triangle_count(mesh_obj.data)))
    for key in sorted(written):
        print("  preview {0}: {1}".format(key, os.path.basename(written[key])))
    return {"name": spec.name, "problems": problems}
