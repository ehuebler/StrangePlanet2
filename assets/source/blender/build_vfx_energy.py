"""Build three review-only energy VFX: a stringy projectile, a cored beam,
and a stream beam with no solid core.

These are not wired into the game. Open the saved .blend and press play, or
look at the preview stills and loops.

    & "C:\\Program Files\\Blender Foundation\\Blender 5.1\\blender.exe" `
        --background --factory-startup `
        --python assets/source/blender/build_vfx_energy.py
"""

from __future__ import annotations

import math
import os
import random
import sys

import bmesh
import bpy
from bpy_extras import anim_utils
from mathutils import Matrix, Vector

SOURCE_DIR = os.path.dirname(os.path.abspath(__file__))
PROJECT_DIR = os.path.abspath(os.path.join(
    SOURCE_DIR, os.pardir, os.pardir, os.pardir))
REVIEW_DIR = os.path.join(PROJECT_DIR, "assets", "source", "vfx", "energy_review")
BLEND_PATH = os.path.join(REVIEW_DIR, "energy_review.blend")
PREVIEW_DIR = os.path.join(REVIEW_DIR, "previews")
if SOURCE_DIR not in sys.path:
    sys.path.insert(0, SOURCE_DIR)

from propkit import reset_scene  # noqa: E402

FPS = 24
FRAME_END = 48
TAU = math.tau


def _ensure_dir(path: str) -> str:
    os.makedirs(path, exist_ok=True)
    return path


def _clear_orphans() -> None:
    reset_scene()
    for block in (
        bpy.data.materials,
        bpy.data.curves,
        bpy.data.lights,
        bpy.data.cameras,
        bpy.data.images,
        bpy.data.actions,
        bpy.data.node_groups,
    ):
        for item in list(block):
            if item.users == 0:
                block.remove(item)


def _look_at(obj, location, target) -> None:
    obj.location = Vector(location)
    obj.rotation_euler = (Vector(target) - Vector(location)).to_track_quat(
        "-Z", "Y").to_euler()


def _object_from_bm(name: str, bm: bmesh.types.BMesh, material) -> bpy.types.Object:
    bmesh.ops.recalc_face_normals(bm, faces=bm.faces[:])
    for face in bm.faces:
        face.smooth = True
    bm.normal_update()
    mesh = bpy.data.meshes.new(name + "Mesh")
    bm.to_mesh(mesh)
    bm.free()
    if not mesh.uv_layers:
        mesh.uv_layers.new(name="UVMap")
    obj = bpy.data.objects.new(name, mesh)
    bpy.context.scene.collection.objects.link(obj)
    if material is not None:
        mesh.materials.append(material)
    obj.display_type = "TEXTURED"
    return obj


def _frame_along(points: list[Vector], index: int) -> tuple[Vector, Vector, Vector]:
    count = len(points)
    prev_i = max(index - 1, 0)
    next_i = min(index + 1, count - 1)
    tangent = points[next_i] - points[prev_i]
    if tangent.length_squared < 1e-8:
        tangent = Vector((0.0, 0.0, 1.0))
    tangent.normalize()
    helper = Vector((0.0, 0.0, 1.0)) if abs(tangent.z) < 0.92 else Vector((1.0, 0.0, 0.0))
    right = tangent.cross(helper)
    if right.length_squared < 1e-8:
        right = tangent.cross(Vector((0.0, 1.0, 0.0)))
    right.normalize()
    up = right.cross(tangent).normalized()
    return tangent, right, up


def loft_tube(
        points: list[Vector],
        radius: float,
        closed: bool = False,
        segments: int = 6,
        taper: float = 1.0,
) -> bmesh.types.BMesh:
    bm = bmesh.new()
    if len(points) < 2:
        return bm
    rings: list[list[bmesh.types.BMVert]] = []
    last = len(points) - 1
    for index, point in enumerate(points):
        _tangent, right, up = _frame_along(points, index)
        along = index / last if last else 0.0
        width = radius * (1.0 - (1.0 - taper) * along)
        ring = []
        for spoke in range(segments):
            angle = TAU * spoke / segments
            offset = (right * math.cos(angle) + up * math.sin(angle)) * width
            ring.append(bm.verts.new(point + offset))
        rings.append(ring)
    ring_count = len(rings)
    uv_layer = bm.loops.layers.uv.new("UVMap")
    span = ring_count if closed else ring_count - 1
    for level in range(span):
        a = rings[level]
        b = rings[(level + 1) % ring_count]
        v0 = level / max(span, 1)
        v1 = (level + 1) / max(span, 1)
        for spoke in range(segments):
            nxt = (spoke + 1) % segments
            try:
                face = bm.faces.new((a[spoke], a[nxt], b[nxt], b[spoke]))
            except ValueError:
                continue
            u0 = spoke / segments
            u1 = (spoke + 1) / segments
            uvs = ((u0, v0), (u1, v0), (u1, v1), (u0, v1))
            for loop, uv in zip(face.loops, uvs):
                loop[uv_layer].uv = uv
    if not closed:
        try:
            cap0 = bm.faces.new(list(reversed(rings[0])))
            cap1 = bm.faces.new(rings[-1])
            for face in (cap0, cap1):
                for loop in face.loops:
                    loop[uv_layer].uv = (0.5, 0.5)
        except ValueError:
            pass
    return bm


def join_meshes(name: str, meshes: list[bmesh.types.BMesh], material) -> bpy.types.Object:
    bm = bmesh.new()
    uv_dest = bm.loops.layers.uv.new("UVMap")
    for piece in meshes:
        uv_src = piece.loops.layers.uv.active
        mapping = {}
        for vert in piece.verts:
            mapping[vert] = bm.verts.new(vert.co)
        bm.verts.ensure_lookup_table()
        for face in piece.faces:
            verts = [mapping[vert] for vert in face.verts]
            if len(set(verts)) < 3:
                continue
            try:
                new_face = bm.faces.new(verts)
            except ValueError:
                continue
            if uv_src is not None:
                for src_loop, dest_loop in zip(face.loops, new_face.loops):
                    dest_loop[uv_dest].uv = src_loop[uv_src].uv
        piece.free()
    return _object_from_bm(name, bm, material)


def add_star(name: str, size: float, material) -> bpy.types.Object:
    bm = bmesh.new()
    tips = [
        Vector((0.0, size, 0.0)),
        Vector((size * 0.12, size * 0.12, 0.0)),
        Vector((size, 0.0, 0.0)),
        Vector((size * 0.12, -size * 0.12, 0.0)),
        Vector((0.0, -size, 0.0)),
        Vector((-size * 0.12, -size * 0.12, 0.0)),
        Vector((-size, 0.0, 0.0)),
        Vector((-size * 0.12, size * 0.12, 0.0)),
    ]
    verts = [bm.verts.new(point) for point in tips]
    front = bm.faces.new(verts)
    back = [bm.verts.new(Vector((point.x, point.y, -0.001))) for point in tips]
    rear = bm.faces.new(list(reversed(back)))
    uv_layer = bm.loops.layers.uv.new("UVMap")
    for face in (front, rear):
        for loop in face.loops:
            point = loop.vert.co
            loop[uv_layer].uv = (
                point.x / max(size, 1e-6) * 0.5 + 0.5,
                point.y / max(size, 1e-6) * 0.5 + 0.5,
            )
    return _object_from_bm(name, bm, material)


def _set_blend(material: bpy.types.Material) -> None:
    if hasattr(material, "surface_render_method"):
        material.surface_render_method = "BLENDED"
    elif hasattr(material, "blend_method"):
        material.blend_method = "BLEND"
    material.use_backface_culling = False
    if hasattr(material, "shadow_method"):
        material.shadow_method = "NONE"


def _sock(collection, names):
    if isinstance(names, (int, str)):
        names = (names,)
    for name in names:
        try:
            return collection[name]
        except (KeyError, IndexError, TypeError):
            continue
    raise KeyError(names)


def _link(tree, node_a, out_name, node_b, in_name) -> None:
    tree.links.new(_sock(node_a.outputs, out_name), _sock(node_b.inputs, in_name))


def _mix_color(tree):
    try:
        node = tree.nodes.new("ShaderNodeMix")
        node.data_type = "RGBA"
        return node
    except (RuntimeError, TypeError):
        return tree.nodes.new("ShaderNodeMixRGB")


def _set_color(node, socket_name, color) -> None:
    socket = node.inputs[socket_name]
    socket.default_value = (*color, 1.0)


def _mix_out(node) -> str:
    return "Result" if "Result" in node.outputs else "Color"


def _new_tree(name: str):
    material = bpy.data.materials.new(name)
    material.use_nodes = True
    _set_blend(material)
    tree = material.node_tree
    for node in list(tree.nodes):
        tree.nodes.remove(node)
    return material, tree


def emission_mix(tree, color, strength, alpha_socket):
    emission = tree.nodes.new("ShaderNodeEmission")
    emission.inputs["Color"].default_value = (*color, 1.0)
    emission.inputs["Strength"].default_value = strength
    transparent = tree.nodes.new("ShaderNodeBsdfTransparent")
    mix = tree.nodes.new("ShaderNodeMixShader")
    tree.links.new(alpha_socket, mix.inputs[0])
    tree.links.new(transparent.outputs["BSDF"], mix.inputs[1])
    tree.links.new(emission.outputs["Emission"], mix.inputs[2])
    output = tree.nodes.new("ShaderNodeOutputMaterial")
    tree.links.new(mix.outputs["Shader"], output.inputs["Surface"])
    return emission, mix


def make_core_material(name: str, color, strength: float) -> bpy.types.Material:
    material, tree = _new_tree(name)
    emission = tree.nodes.new("ShaderNodeEmission")
    emission.inputs["Color"].default_value = (*color, 1.0)
    emission.inputs["Strength"].default_value = strength
    output = tree.nodes.new("ShaderNodeOutputMaterial")
    tree.links.new(emission.outputs["Emission"], output.inputs["Surface"])
    if hasattr(material, "surface_render_method"):
        material.surface_render_method = "DITHERED"
    return material


def make_radial_plasma(
        name: str,
        inner,
        mid,
        outer,
        strength: float,
        noise_scale: float,
        stretch: tuple[float, float, float],
        filament: float,
) -> bpy.types.Material:
    material, tree = _new_tree(name)
    texcoord = tree.nodes.new("ShaderNodeTexCoord")
    mapping = tree.nodes.new("ShaderNodeMapping")
    mapping.name = "Scroll"
    mapping.inputs["Scale"].default_value = stretch
    _link(tree, texcoord, "Generated", mapping, "Vector")

    noise = tree.nodes.new("ShaderNodeTexNoise")
    noise.noise_dimensions = "3D"
    noise.inputs["Scale"].default_value = noise_scale
    noise.inputs["Detail"].default_value = 8.0
    noise.inputs["Roughness"].default_value = 0.62
    noise.inputs["Lacunarity"].default_value = 2.3
    _link(tree, mapping, "Vector", noise, "Vector")

    voronoi = tree.nodes.new("ShaderNodeTexVoronoi")
    voronoi.voronoi_dimensions = "3D"
    voronoi.feature = "F1"
    voronoi.inputs["Scale"].default_value = noise_scale * 0.55
    _link(tree, mapping, "Vector", voronoi, "Vector")

    stringy = tree.nodes.new("ShaderNodeMath")
    stringy.operation = "POWER"
    stringy.inputs[1].default_value = 2.4
    # Distance-to-cell edges become bright threads.
    invert = tree.nodes.new("ShaderNodeMath")
    invert.operation = "SUBTRACT"
    invert.inputs[0].default_value = 1.0
    _link(tree, voronoi, ("Distance", "Fac", "Factor"), invert, 1)
    _link(tree, invert, "Value", stringy, 0)

    mix_noise = tree.nodes.new("ShaderNodeMath")
    mix_noise.operation = "MAXIMUM"
    _link(tree, noise, ("Fac", "Factor"), mix_noise, 0)
    _link(tree, stringy, "Value", mix_noise, 1)

    separate = tree.nodes.new("ShaderNodeSeparateXYZ")
    _link(tree, texcoord, "Generated", separate, "Vector")
    radial = tree.nodes.new("ShaderNodeVectorMath")
    radial.operation = "LENGTH"
    _link(tree, texcoord, "Generated", radial, 0)
    # Generated 0-1 cube, so centre is about 0.85 after remap. Use object.
    obj_len = tree.nodes.new("ShaderNodeVectorMath")
    obj_len.operation = "LENGTH"
    _link(tree, texcoord, "Object", obj_len, 0)

    ramp = tree.nodes.new("ShaderNodeValToRGB")
    ramp.color_ramp.elements[0].position = 0.0
    ramp.color_ramp.elements[0].color = (*inner, 1.0)
    if len(ramp.color_ramp.elements) < 3:
        ramp.color_ramp.elements.new(0.38)
    ramp.color_ramp.elements[1].position = 0.34
    ramp.color_ramp.elements[1].color = (*mid, 1.0)
    extra = ramp.color_ramp.elements.new(0.72)
    extra.color = (*outer, 1.0)
    edge = ramp.color_ramp.elements.new(1.0)
    edge.color = (outer[0] * 0.1, outer[1] * 0.1, outer[2] * 0.1, 0.0)
    _link(tree, obj_len, "Value", ramp, "Fac")

    layer = tree.nodes.new("ShaderNodeLayerWeight")
    layer.inputs["Blend"].default_value = 0.42
    alpha_mul = tree.nodes.new("ShaderNodeMath")
    alpha_mul.operation = "MULTIPLY"
    _link(tree, mix_noise, "Value", alpha_mul, 0)
    facing = tree.nodes.new("ShaderNodeMath")
    facing.operation = "SUBTRACT"
    facing.inputs[0].default_value = 1.0
    _link(tree, layer, ("Facing", "Fresnel"), facing, 1)
    alpha = tree.nodes.new("ShaderNodeMath")
    alpha.operation = "MULTIPLY"
    _link(tree, alpha_mul, "Value", alpha, 0)
    _link(tree, facing, "Value", alpha, 1)
    alpha.inputs[0].default_value = filament

    color_mix = _mix_color(tree)
    # Keep a hotter thread colour on the bright filaments.
    hot = _mix_color(tree)
    _set_color(hot, "A", outer)
    _set_color(hot, "B", inner)
    _link(tree, stringy, "Value", hot, "Factor")
    _link(tree, ramp, "Color", color_mix, "A")
    _link(tree, hot, _mix_out(hot), color_mix, "B")
    _link(tree, mix_noise, "Value", color_mix, "Factor")

    emission = tree.nodes.new("ShaderNodeEmission")
    emission.inputs["Strength"].default_value = strength
    _link(tree, color_mix, _mix_out(color_mix), emission, "Color")
    transparent = tree.nodes.new("ShaderNodeBsdfTransparent")
    mix = tree.nodes.new("ShaderNodeMixShader")
    _link(tree, alpha, "Value", mix, 0)
    tree.links.new(transparent.outputs["BSDF"], mix.inputs[1])
    tree.links.new(emission.outputs["Emission"], mix.inputs[2])
    output = tree.nodes.new("ShaderNodeOutputMaterial")
    tree.links.new(mix.outputs["Shader"], output.inputs["Surface"])
    return material


def make_stretched_glow(
        name: str,
        inner,
        outer,
        strength: float,
        noise_scale: float,
        stretch: tuple[float, float, float],
        core_soft: float = 0.18,
) -> bpy.types.Material:
    material, tree = _new_tree(name)
    texcoord = tree.nodes.new("ShaderNodeTexCoord")
    mapping = tree.nodes.new("ShaderNodeMapping")
    mapping.name = "Scroll"
    mapping.inputs["Scale"].default_value = stretch
    _link(tree, texcoord, "Generated", mapping, "Vector")

    noise = tree.nodes.new("ShaderNodeTexNoise")
    noise.noise_dimensions = "3D"
    noise.inputs["Scale"].default_value = noise_scale
    noise.inputs["Detail"].default_value = 6.0
    noise.inputs["Roughness"].default_value = 0.48
    _link(tree, mapping, "Vector", noise, "Vector")

    wave = tree.nodes.new("ShaderNodeTexWave")
    wave.wave_type = "BANDS"
    wave.bands_direction = "Z"
    wave.wave_profile = "SIN"
    wave.inputs["Scale"].default_value = 18.0
    wave.inputs["Distortion"].default_value = 4.5
    _link(tree, mapping, "Vector", wave, "Vector")

    threads = tree.nodes.new("ShaderNodeMath")
    threads.operation = "MAXIMUM"
    _link(tree, noise, ("Fac", "Factor"), threads, 0)
    _link(tree, wave, ("Fac", "Factor", "Color"), threads, 1)

    ramp = tree.nodes.new("ShaderNodeValToRGB")
    ramp.color_ramp.elements[0].color = (*outer, 1.0)
    ramp.color_ramp.elements[1].position = 0.72
    ramp.color_ramp.elements[1].color = (*inner, 1.0)
    _link(tree, threads, "Value", ramp, "Fac")

    layer = tree.nodes.new("ShaderNodeLayerWeight")
    layer.inputs["Blend"].default_value = core_soft
    alpha = tree.nodes.new("ShaderNodeMath")
    alpha.operation = "MULTIPLY"
    facing = tree.nodes.new("ShaderNodeMath")
    facing.operation = "SUBTRACT"
    facing.inputs[0].default_value = 1.0
    _link(tree, layer, ("Facing", "Fresnel"), facing, 1)
    _link(tree, threads, "Value", alpha, 0)
    _link(tree, facing, "Value", alpha, 1)

    emission = tree.nodes.new("ShaderNodeEmission")
    emission.inputs["Strength"].default_value = strength
    _link(tree, ramp, "Color", emission, "Color")
    transparent = tree.nodes.new("ShaderNodeBsdfTransparent")
    mix = tree.nodes.new("ShaderNodeMixShader")
    _link(tree, alpha, "Value", mix, 0)
    tree.links.new(transparent.outputs["BSDF"], mix.inputs[1])
    tree.links.new(emission.outputs["Emission"], mix.inputs[2])
    output = tree.nodes.new("ShaderNodeOutputMaterial")
    tree.links.new(mix.outputs["Shader"], output.inputs["Surface"])
    return material


def make_stream_material(name: str, hot, glow, strength: float) -> bpy.types.Material:
    material, tree = _new_tree(name)
    texcoord = tree.nodes.new("ShaderNodeTexCoord")
    separate = tree.nodes.new("ShaderNodeSeparateXYZ")
    _link(tree, texcoord, "UV", separate, "Vector")

    # UV u is across the ribbon: hot centre, coloured edges.
    ramp = tree.nodes.new("ShaderNodeValToRGB")
    ramp.color_ramp.elements[0].position = 0.0
    ramp.color_ramp.elements[0].color = (*glow, 0.0)
    mid = ramp.color_ramp.elements.new(0.5)
    mid.color = (*hot, 1.0)
    ramp.color_ramp.elements[1].position = 1.0
    ramp.color_ramp.elements[1].color = (*glow, 0.0)
    # Distance from ribbon centre.
    center = tree.nodes.new("ShaderNodeMath")
    center.operation = "SUBTRACT"
    center.inputs[1].default_value = 0.5
    _link(tree, separate, "X", center, 0)
    absv = tree.nodes.new("ShaderNodeMath")
    absv.operation = "ABSOLUTE"
    _link(tree, center, "Value", absv, 0)
    edge = tree.nodes.new("ShaderNodeMath")
    edge.operation = "SUBTRACT"
    edge.inputs[0].default_value = 1.0
    mul = tree.nodes.new("ShaderNodeMath")
    mul.operation = "MULTIPLY"
    mul.inputs[1].default_value = 2.0
    _link(tree, absv, "Value", mul, 0)
    _link(tree, mul, "Value", edge, 1)
    _link(tree, edge, "Value", ramp, "Fac")

    mapping = tree.nodes.new("ShaderNodeMapping")
    mapping.name = "Scroll"
    mapping.inputs["Scale"].default_value = (1.0, 8.0, 1.0)
    _link(tree, texcoord, "UV", mapping, "Vector")
    noise = tree.nodes.new("ShaderNodeTexNoise")
    noise.inputs["Scale"].default_value = 12.0
    noise.inputs["Detail"].default_value = 4.0
    _link(tree, mapping, "Vector", noise, "Vector")

    alpha = tree.nodes.new("ShaderNodeMath")
    alpha.operation = "MULTIPLY"
    _link(tree, edge, "Value", alpha, 0)
    _link(tree, noise, ("Fac", "Factor"), alpha, 1)

    emission = tree.nodes.new("ShaderNodeEmission")
    emission.inputs["Strength"].default_value = strength
    _link(tree, ramp, "Color", emission, "Color")
    transparent = tree.nodes.new("ShaderNodeBsdfTransparent")
    mix = tree.nodes.new("ShaderNodeMixShader")
    _link(tree, alpha, "Value", mix, 0)
    tree.links.new(transparent.outputs["BSDF"], mix.inputs[1])
    tree.links.new(emission.outputs["Emission"], mix.inputs[2])
    output = tree.nodes.new("ShaderNodeOutputMaterial")
    tree.links.new(mix.outputs["Shader"], output.inputs["Surface"])
    return material


def make_star_material(name: str, color, strength: float) -> bpy.types.Material:
    material, tree = _new_tree(name)
    texcoord = tree.nodes.new("ShaderNodeTexCoord")
    separate = tree.nodes.new("ShaderNodeSeparateXYZ")
    _link(tree, texcoord, "UV", separate, "Vector")
    # Soft diamond falloff from the face centre.
    dx = tree.nodes.new("ShaderNodeMath")
    dx.operation = "SUBTRACT"
    dx.inputs[1].default_value = 0.5
    dy = tree.nodes.new("ShaderNodeMath")
    dy.operation = "SUBTRACT"
    dy.inputs[1].default_value = 0.5
    _link(tree, separate, "X", dx, 0)
    _link(tree, separate, "Y", dy, 0)
    ax = tree.nodes.new("ShaderNodeMath")
    ax.operation = "ABSOLUTE"
    ay = tree.nodes.new("ShaderNodeMath")
    ay.operation = "ABSOLUTE"
    _link(tree, dx, "Value", ax, 0)
    _link(tree, dy, "Value", ay, 0)
    add = tree.nodes.new("ShaderNodeMath")
    add.operation = "ADD"
    _link(tree, ax, "Value", add, 0)
    _link(tree, ay, "Value", add, 1)
    fall = tree.nodes.new("ShaderNodeMath")
    fall.operation = "SUBTRACT"
    fall.inputs[0].default_value = 1.0
    _link(tree, add, "Value", fall, 1)
    clamp = tree.nodes.new("ShaderNodeClamp")
    _link(tree, fall, "Value", clamp, "Value")
    emission = tree.nodes.new("ShaderNodeEmission")
    emission.inputs["Color"].default_value = (*color, 1.0)
    emission.inputs["Strength"].default_value = strength
    transparent = tree.nodes.new("ShaderNodeBsdfTransparent")
    mix = tree.nodes.new("ShaderNodeMixShader")
    _link(tree, clamp, ("Result", "Value"), mix, 0)
    tree.links.new(transparent.outputs["BSDF"], mix.inputs[1])
    tree.links.new(emission.outputs["Emission"], mix.inputs[2])
    output = tree.nodes.new("ShaderNodeOutputMaterial")
    tree.links.new(mix.outputs["Shader"], output.inputs["Surface"])
    return material


def make_ground_material() -> bpy.types.Material:
    material = bpy.data.materials.new("ReviewGround")
    material.use_nodes = True
    bsdf = material.node_tree.nodes["Principled BSDF"]
    bsdf.inputs["Base Color"].default_value = (0.008, 0.007, 0.01, 1.0)
    bsdf.inputs["Roughness"].default_value = 0.92
    return material


def jittered_icosphere(radius: float, subdivisions: int, noise: float, rng: random.Random) -> bmesh.types.BMesh:
    bm = bmesh.new()
    bmesh.ops.create_icosphere(bm, subdivisions=subdivisions, radius=radius)
    for vert in bm.verts:
        vert.co += vert.co.normalized() * rng.uniform(-noise, noise)
    return bm


def yarn_loop(rng: random.Random, radius: float, waves: int, points: int = 40) -> list[Vector]:
    axis = Vector((rng.uniform(-1.0, 1.0), rng.uniform(-1.0, 1.0), rng.uniform(-1.0, 1.0)))
    if axis.length_squared < 1e-6:
        axis = Vector((0.0, 1.0, 0.0))
    axis.normalize()
    helper = Vector((0.0, 0.0, 1.0)) if abs(axis.z) < 0.9 else Vector((1.0, 0.0, 0.0))
    right = axis.cross(helper).normalized()
    up = right.cross(axis).normalized()
    tilt = rng.uniform(-0.35, 0.35)
    phase = rng.uniform(0.0, TAU)
    path = []
    for index in range(points):
        angle = TAU * index / points
        wobble = 1.0 + 0.18 * math.sin(angle * waves + phase)
        wobble += 0.08 * math.sin(angle * (waves + 3) + phase * 1.7)
        circle = (right * math.cos(angle) + up * math.sin(angle)) * radius * wobble
        lift = axis * (math.sin(angle * 2.0 + phase) * radius * tilt)
        path.append(circle + lift)
    return path


def tendril(rng: random.Random, direction: Vector, start: float, length: float) -> list[Vector]:
    direction = direction.normalized()
    helper = Vector((0.0, 0.0, 1.0)) if abs(direction.z) < 0.9 else Vector((1.0, 0.0, 0.0))
    right = direction.cross(helper).normalized()
    up = right.cross(direction).normalized()
    path = []
    steps = 14
    for index in range(steps):
        along = index / (steps - 1)
        point = direction * (start + length * along)
        swirl = (
            right * math.sin(along * 7.0 + rng.random() * TAU) * 0.07 * (0.3 + along)
            + up * math.cos(along * 5.5 + rng.random() * TAU) * 0.07 * (0.3 + along)
        )
        path.append(point + swirl)
    return path


def lightning_path(rng: random.Random, z0: float, z1: float, wander: float) -> list[Vector]:
    path = []
    steps = 22
    x = rng.uniform(-wander * 0.3, wander * 0.3)
    y = rng.uniform(-wander * 0.3, wander * 0.3)
    for index in range(steps):
        along = index / (steps - 1)
        x += rng.uniform(-wander, wander) * (0.35 + along * 0.4)
        y += rng.uniform(-wander, wander) * (0.35 + along * 0.4)
        x *= 0.72
        y *= 0.72
        path.append(Vector((x, y, z0 + (z1 - z0) * along)))
    return path


def ribbon(height: float, width: float, z0: float, waves: int, phase: float, yaw: float) -> list[Vector]:
    path = []
    steps = 28
    for index in range(steps):
        along = index / (steps - 1)
        z = z0 + height * along
        offset = math.sin(along * waves * TAU + phase) * width * 0.35
        x = math.cos(yaw) * offset
        y = math.sin(yaw) * offset
        path.append(Vector((x, y, z)))
    return path


def parent(child: bpy.types.Object, root: bpy.types.Object) -> None:
    child.parent = root


def key_scale_pulse(obj: bpy.types.Object, low: float, high: float) -> None:
    obj.scale = Vector((low, low, low))
    obj.keyframe_insert(data_path="scale", frame=1)
    obj.scale = Vector((high, high, high))
    obj.keyframe_insert(data_path="scale", frame=FRAME_END // 2)
    obj.scale = Vector((low, low, low))
    obj.keyframe_insert(data_path="scale", frame=FRAME_END + 1)
    _make_cyclic(obj)


def key_rotation(obj: bpy.types.Object, axis: str, turns: float) -> None:
    obj.rotation_mode = "XYZ"
    obj.rotation_euler = (0.0, 0.0, 0.0)
    obj.keyframe_insert(data_path="rotation_euler", frame=1)
    euler = [0.0, 0.0, 0.0]
    euler[{"X": 0, "Y": 1, "Z": 2}[axis]] = TAU * turns
    obj.rotation_euler = euler
    obj.keyframe_insert(data_path="rotation_euler", frame=FRAME_END + 1)
    _make_cyclic(obj)


def key_location_bob(obj: bpy.types.Object, delta: Vector) -> None:
    rest = obj.location.copy()
    obj.keyframe_insert(data_path="location", frame=1)
    obj.location = rest + delta
    obj.keyframe_insert(data_path="location", frame=FRAME_END // 2)
    obj.location = rest
    obj.keyframe_insert(data_path="location", frame=FRAME_END + 1)
    _make_cyclic(obj)


def key_visibility_flicker(obj: bpy.types.Object, rng: random.Random) -> None:
    for frame in range(1, FRAME_END + 2, 3):
        hidden = rng.random() < 0.18
        obj.hide_render = hidden
        obj.hide_viewport = hidden
        obj.keyframe_insert(data_path="hide_render", frame=frame)
        obj.keyframe_insert(data_path="hide_viewport", frame=frame)
        scale = 0.35 + rng.random() * 0.9
        obj.scale = Vector((scale, scale, scale))
        obj.keyframe_insert(data_path="scale", frame=frame)
    _make_cyclic(obj)


def _fcurves_for(id_data):
    anim = getattr(id_data, "animation_data", None)
    if anim is None or anim.action is None:
        return []
    slot = getattr(anim, "action_slot", None)
    bag = anim_utils.action_get_channelbag_for_slot(anim.action, slot)
    if bag is None and slot is not None:
        bag = anim_utils.action_ensure_channelbag_for_slot(anim.action, slot)
    if bag is None:
        return []
    return list(bag.fcurves)


def _make_cyclic(id_data) -> None:
    for fcurve in _fcurves_for(id_data):
        for modifier in fcurve.modifiers:
            if modifier.type == "CYCLES":
                break
        else:
            modifier = fcurve.modifiers.new("CYCLES")
            modifier.mode_before = "REPEAT"
            modifier.mode_after = "REPEAT"


def scroll_material(material: bpy.types.Material, axis: int, amount: float) -> None:
    tree = material.node_tree
    mapping = tree.nodes.get("Scroll")
    if mapping is None:
        return
    socket = mapping.inputs["Location"]
    value = list(socket.default_value)
    value[axis] = 0.0
    socket.default_value = value
    socket.keyframe_insert(data_path="default_value", index=axis, frame=1)
    value[axis] = amount
    socket.default_value = value
    socket.keyframe_insert(data_path="default_value", index=axis, frame=FRAME_END + 1)
    if tree.animation_data is None or tree.animation_data.action is None:
        return
    _make_cyclic(tree)


def push_nla(obj: bpy.types.Object, name: str) -> None:
    if obj.animation_data is None or obj.animation_data.action is None:
        return
    action = obj.animation_data.action
    action.name = "{0}_{1}".format(obj.name, name)
    action.use_fake_user = True
    obj.animation_data.action = None
    track = obj.animation_data.nla_tracks.new()
    track.name = name
    strip = track.strips.new(name, 1, action)
    strip.name = name
    strip.repeat = 8.0
    # Keep the action assigned so Play in the .blend works immediately.
    obj.animation_data.action = action


def build_projectile(origin: Vector) -> tuple[bpy.types.Object, list[bpy.types.Material]]:
    rng = random.Random(20260908)
    root = bpy.data.objects.new("Projectile", None)
    bpy.context.scene.collection.objects.link(root)
    root.location = origin
    root.empty_display_type = "SPHERE"
    root.empty_display_size = 0.2

    core_mat = make_core_material("ProjectileCore", (1.0, 1.0, 1.0), 28.0)
    inner_mat = make_radial_plasma(
        "ProjectileInner",
        (1.0, 1.0, 1.0),
        (0.10, 0.85, 1.0),
        (0.02, 0.35, 1.0),
        14.0, 8.0, (1.4, 1.4, 1.4), 1.1,
    )
    yarn_mat = make_radial_plasma(
        "ProjectileYarn",
        (0.75, 1.0, 0.45),
        (0.22, 1.0, 0.18),
        (0.04, 0.70, 0.06),
        11.0, 13.0, (2.1, 2.1, 2.1), 1.6,
    )
    wisp_mat = make_radial_plasma(
        "ProjectileWisps",
        (0.85, 1.0, 0.40),
        (0.18, 1.0, 0.12),
        (0.02, 0.45, 0.03),
        8.5, 10.0, (2.4, 2.4, 1.5), 1.8,
    )
    halo_mat = make_radial_plasma(
        "ProjectileHalo",
        (0.25, 1.0, 0.35),
        (0.06, 0.85, 0.14),
        (0.01, 0.22, 0.02),
        1.6, 6.5, (1.3, 1.3, 1.3), 0.35,
    )
    star_mat = make_star_material("ProjectileStar", (0.75, 1.0, 0.55), 8.0)

    core = _object_from_bm("ProjectileHotCore", jittered_icosphere(0.048, 2, 0.006, rng), core_mat)
    inner = _object_from_bm("ProjectileBlueShell", jittered_icosphere(0.11, 3, 0.010, rng), inner_mat)
    halo = _object_from_bm("ProjectileHalo", jittered_icosphere(0.42, 2, 0.055, rng), halo_mat)
    parent(core, root)
    parent(inner, root)
    parent(halo, root)

    loops = []
    for _index in range(22):
        path = yarn_loop(rng, rng.uniform(0.14, 0.30), rng.randint(3, 7))
        loops.append(loft_tube(path, rng.uniform(0.005, 0.011), closed=True, segments=5))
    yarn = join_meshes("ProjectileYarn", loops, yarn_mat)
    parent(yarn, root)

    wisps = []
    for _index in range(16):
        direction = Vector((rng.uniform(-1, 1), rng.uniform(-1, 1), rng.uniform(-1, 1)))
        wisps.append(loft_tube(
            tendril(rng, direction, 0.12, rng.uniform(0.22, 0.42)),
            0.005, closed=False, segments=4, taper=0.12,
        ))
    wisp = join_meshes("ProjectileWisps", wisps, wisp_mat)
    parent(wisp, root)

    stars = []
    for index in range(9):
        star = add_star("ProjectileStar_%02d" % index, rng.uniform(0.03, 0.07), star_mat)
        direction = Vector((rng.uniform(-1, 1), rng.uniform(-1, 1), rng.uniform(-1, 1)))
        star.location = direction.normalized() * rng.uniform(0.22, 0.42)
        star.rotation_euler = (
            rng.uniform(0, TAU), rng.uniform(0, TAU), rng.uniform(0, TAU))
        parent(star, root)
        stars.append(star)

    key_scale_pulse(core, 0.92, 1.18)
    key_scale_pulse(inner, 0.96, 1.08)
    key_scale_pulse(halo, 0.94, 1.12)
    key_rotation(yarn, "Z", 1.0)
    key_rotation(wisp, "Y", -0.7)
    for star in stars:
        key_visibility_flicker(star, rng)
        key_location_bob(star, Vector((
            rng.uniform(-0.03, 0.03),
            rng.uniform(-0.03, 0.03),
            rng.uniform(-0.03, 0.03),
        )))
    scroll_material(inner_mat, 0, 0.65)
    scroll_material(yarn_mat, 1, 0.85)
    scroll_material(wisp_mat, 2, 1.1)
    scroll_material(halo_mat, 0, 0.4)
    return root, [core_mat, inner_mat, yarn_mat, wisp_mat, halo_mat, star_mat]


def _thin_core_cross(height: float, thickness: float) -> bmesh.types.BMesh:
    bm = bmesh.new()
    half_h = height * 0.5
    half_t = thickness * 0.5
    # Two thin blades that read as a laser line from any side, not a pipe.
    for yaw in (0.0, math.pi * 0.5):
        matrix = Matrix.Rotation(yaw, 4, "Z")
        corners = [
            matrix @ Vector((-half_t, -thickness * 2.2, -half_h)),
            matrix @ Vector((half_t, -thickness * 2.2, -half_h)),
            matrix @ Vector((half_t, thickness * 2.2, -half_h)),
            matrix @ Vector((-half_t, thickness * 2.2, -half_h)),
            matrix @ Vector((-half_t, -thickness * 2.2, half_h)),
            matrix @ Vector((half_t, -thickness * 2.2, half_h)),
            matrix @ Vector((half_t, thickness * 2.2, half_h)),
            matrix @ Vector((-half_t, thickness * 2.2, half_h)),
        ]
        verts = [bm.verts.new(point) for point in corners]
        faces = (
            (0, 1, 2, 3), (4, 7, 6, 5), (0, 4, 5, 1),
            (1, 5, 6, 2), (2, 6, 7, 3), (3, 7, 4, 0),
        )
        for face in faces:
            bm.faces.new([verts[index] for index in face])
    return bm


def _impact_flare(radius: float) -> bmesh.types.BMesh:
    bm = bmesh.new()
    spokes = 16
    inner = []
    outer = []
    for index in range(spokes):
        angle = TAU * index / spokes
        reach = radius * (0.72 if index % 2 else 1.0)
        inner.append(bm.verts.new(Vector((
            math.cos(angle) * radius * 0.12,
            math.sin(angle) * radius * 0.12,
            0.01,
        ))))
        outer.append(bm.verts.new(Vector((
            math.cos(angle) * reach,
            math.sin(angle) * reach,
            0.0,
        ))))
    centre = bm.verts.new(Vector((0.0, 0.0, 0.03)))
    for index in range(spokes):
        nxt = (index + 1) % spokes
        bm.faces.new((centre, inner[index], inner[nxt]))
        bm.faces.new((inner[index], outer[index], outer[nxt], inner[nxt]))
    return bm


def _ground_ring(radius: float, width: float, spikes: int) -> bmesh.types.BMesh:
    bm = bmesh.new()
    inner = []
    outer = []
    for index in range(spikes):
        angle = TAU * index / spikes
        ripple = 1.0 + 0.08 * math.sin(angle * 5.0)
        inner.append(bm.verts.new(Vector((
            math.cos(angle) * (radius - width) * ripple,
            math.sin(angle) * (radius - width) * ripple,
            0.008,
        ))))
        outer.append(bm.verts.new(Vector((
            math.cos(angle) * radius * ripple,
            math.sin(angle) * radius * ripple,
            0.002,
        ))))
    for index in range(spikes):
        nxt = (index + 1) % spikes
        bm.faces.new((inner[index], outer[index], outer[nxt], inner[nxt]))
    return bm


def build_core_beam(origin: Vector) -> tuple[bpy.types.Object, list[bpy.types.Material]]:
    rng = random.Random(20260909)
    root = bpy.data.objects.new("BeamCore", None)
    bpy.context.scene.collection.objects.link(root)
    root.location = origin
    root.empty_display_type = "PLAIN_AXES"

    core_mat = make_core_material("BeamCoreLine", (1.0, 0.96, 1.0), 36.0)
    glow_mat = make_stretched_glow(
        "BeamCoreGlow",
        (0.95, 0.55, 1.0),
        (0.55, 0.08, 1.0),
        9.5, 8.0, (1.2, 1.2, 12.0), 0.18,
    )
    string_mat = make_stretched_glow(
        "BeamCoreStrings",
        (0.92, 0.42, 1.0),
        (0.48, 0.04, 0.95),
        7.8, 12.0, (1.6, 1.6, 18.0), 0.12,
    )
    flare_mat = make_radial_plasma(
        "BeamCoreFlare",
        (1.0, 0.95, 1.0),
        (0.78, 0.45, 1.0),
        (0.35, 0.08, 0.85),
        8.0, 5.0, (2.4, 2.4, 0.4), 0.9,
    )
    star_mat = make_star_material("BeamCoreStar", (0.92, 0.78, 1.0), 10.0)

    height = 3.2
    core = _object_from_bm("BeamCoreBlade", _thin_core_cross(height, 0.007), core_mat)
    core.location.z = height * 0.5
    parent(core, root)

    glow_shells = []
    for index in range(8):
        yaw = TAU * index / 8.0
        path = ribbon(height, 0.12, 0.0, 1, index * 0.4, yaw)
        glow_shells.append(loft_tube(path, 0.022, closed=False, segments=4, taper=0.7))
    glow = join_meshes("BeamCoreGlow", glow_shells, glow_mat)
    parent(glow, root)

    strings = []
    for index in range(11):
        yaw = TAU * index / 11.0 + 0.15
        path = ribbon(height * 0.98, 0.06, 0.02, 2 + index % 2, index * 0.8, yaw)
        strings.append(loft_tube(path, 0.0045, closed=False, segments=4, taper=0.45))
    stringy = join_meshes("BeamCoreStrings", strings, string_mat)
    parent(stringy, root)

    flare = _object_from_bm("BeamCoreFlare", _impact_flare(0.82), flare_mat)
    parent(flare, root)

    stars = []
    for index in range(22):
        star = add_star("BeamCoreStar_%02d" % index, rng.uniform(0.02, 0.08), star_mat)
        angle = rng.uniform(0, TAU)
        radius = rng.uniform(0.06, 0.48)
        star.location = Vector((
            math.cos(angle) * radius,
            math.sin(angle) * radius,
            rng.uniform(0.02, 0.55) if index < 16 else rng.uniform(0.4, 1.2),
        ))
        star.rotation_euler = (rng.uniform(0, TAU), 0.0, rng.uniform(0, TAU))
        parent(star, root)
        stars.append(star)

    key_scale_pulse(core, 0.98, 1.06)
    key_rotation(glow, "Z", 0.2)
    key_rotation(stringy, "Z", -0.4)
    key_scale_pulse(flare, 0.86, 1.22)
    for star in stars:
        key_visibility_flicker(star, rng)
        key_location_bob(star, Vector((0.0, 0.0, rng.uniform(0.04, 0.12))))
    scroll_material(glow_mat, 2, 1.4)
    scroll_material(string_mat, 2, 2.0)
    scroll_material(flare_mat, 0, 0.5)
    return root, [core_mat, glow_mat, string_mat, flare_mat, star_mat]


def build_stream_beam(origin: Vector) -> tuple[bpy.types.Object, list[bpy.types.Material]]:
    rng = random.Random(20260910)
    root = bpy.data.objects.new("BeamStreams", None)
    bpy.context.scene.collection.objects.link(root)
    root.location = origin
    root.empty_display_type = "PLAIN_AXES"

    stream_mat = make_stream_material(
        "BeamStreamLines", (1.0, 0.82, 1.0), (1.0, 0.08, 0.72), 22.0)
    cyan_mat = make_stream_material(
        "BeamStreamCyan", (0.75, 1.0, 1.0), (0.10, 0.85, 1.0), 18.0)
    bolt_mat = make_stretched_glow(
        "BeamStreamBolts",
        (0.85, 0.35, 1.0),
        (0.42, 0.06, 0.88),
        6.2, 9.0, (1.4, 1.4, 16.0), 0.12,
    )
    haze_mat = make_stretched_glow(
        "BeamStreamHaze",
        (0.72, 0.16, 1.0),
        (0.32, 0.03, 0.7),
        1.7, 4.0, (1.0, 1.0, 5.5), 0.42,
    )
    ring_mat = make_radial_plasma(
        "BeamStreamRing",
        (1.0, 0.85, 1.0),
        (0.95, 0.18, 1.0),
        (0.45, 0.04, 0.85),
        11.0, 4.8, (2.8, 2.8, 0.35), 0.95,
    )
    star_mat = make_star_material("BeamStreamStar", (1.0, 0.82, 1.0), 11.0)

    height = 3.4

    def _ribbon_mesh(yaw: float, radius: float, half_w: float) -> bmesh.types.BMesh:
        start = Vector((math.cos(yaw) * radius, math.sin(yaw) * radius, 0.02))
        end = Vector((math.cos(yaw) * radius * 0.92, math.sin(yaw) * radius * 0.92, height))
        bm = bmesh.new()
        across = Vector((-math.sin(yaw), math.cos(yaw), 0.0)) * half_w
        front = [
            bm.verts.new(start - across),
            bm.verts.new(start + across),
            bm.verts.new(end + across),
            bm.verts.new(end - across),
        ]
        face_f = bm.faces.new(front)
        back = [
            bm.verts.new(start - across),
            bm.verts.new(end - across),
            bm.verts.new(end + across),
            bm.verts.new(start + across),
        ]
        face_b = bm.faces.new(back)
        uv_layer = bm.loops.layers.uv.new("UVMap")
        for loop, uv in zip(face_f.loops, ((0.0, 0.0), (1.0, 0.0), (1.0, 1.0), (0.0, 1.0))):
            loop[uv_layer].uv = uv
        for loop, uv in zip(face_b.loops, ((0.0, 0.0), (0.0, 1.0), (1.0, 1.0), (1.0, 0.0))):
            loop[uv_layer].uv = uv
        return bm

    stream_meshes = []
    for index in range(10):
        yaw = TAU * index / 10.0
        radius = 0.15 + 0.05 * (index % 3)
        stream_meshes.append(_ribbon_mesh(yaw, radius, 0.016))
    streams = join_meshes("BeamStreamLines", stream_meshes, stream_mat)
    parent(streams, root)
    cyan = join_meshes(
        "BeamStreamCyan",
        [_ribbon_mesh(0.35, 0.20, 0.012), _ribbon_mesh(3.6, 0.18, 0.01)],
        cyan_mat,
    )
    parent(cyan, root)

    bolts = []
    for _index in range(7):
        bolts.append(loft_tube(
            lightning_path(rng, 0.04, height * 0.96, 0.13),
            0.006, closed=False, segments=4, taper=0.35,
        ))
    bolt = join_meshes("BeamStreamBolts", bolts, bolt_mat)
    parent(bolt, root)

    # Scalloped haze hull: loft a wobbling ring, not a cylinder of constant radius.
    haze_bm = bmesh.new()
    rings = []
    levels = 10
    spokes = 10
    for level in range(levels):
        along = level / (levels - 1)
        z = height * along
        radius = 0.22 + 0.10 * math.sin(along * math.pi) + 0.03 * math.sin(along * 8.0)
        ring = []
        for spoke in range(spokes):
            angle = TAU * spoke / spokes
            ripple = 1.0 + 0.12 * math.sin(angle * 3.0 + along * 5.0)
            ring.append(haze_bm.verts.new(Vector((
                math.cos(angle) * radius * ripple,
                math.sin(angle) * radius * ripple,
                z,
            ))))
        rings.append(ring)
    for level in range(levels - 1):
        for spoke in range(spokes):
            nxt = (spoke + 1) % spokes
            haze_bm.faces.new((
                rings[level][spoke], rings[level][nxt],
                rings[level + 1][nxt], rings[level + 1][spoke],
            ))
    haze = _object_from_bm("BeamStreamHaze", haze_bm, haze_mat)
    parent(haze, root)

    ring = _object_from_bm("BeamStreamRing", _ground_ring(0.48, 0.11, 22), ring_mat)
    parent(ring, root)
    inner_ring = _object_from_bm("BeamStreamRingInner", _ground_ring(0.22, 0.05, 16), ring_mat)
    parent(inner_ring, root)

    stars = []
    for index in range(28):
        star = add_star("BeamStreamStar_%02d" % index, rng.uniform(0.02, 0.09), star_mat)
        angle = rng.uniform(0, TAU)
        radius = rng.uniform(0.04, 0.38)
        star.location = Vector((
            math.cos(angle) * radius,
            math.sin(angle) * radius,
            rng.uniform(0.04, height * 0.85),
        ))
        star.rotation_euler = (rng.uniform(0, TAU), 0.0, rng.uniform(0, TAU))
        parent(star, root)
        stars.append(star)

    key_rotation(streams, "Z", 0.12)
    key_rotation(cyan, "Z", -0.18)
    key_rotation(bolt, "Z", -0.4)
    key_scale_pulse(haze, 0.94, 1.08)
    key_scale_pulse(ring, 0.9, 1.12)
    key_scale_pulse(inner_ring, 0.95, 1.08)
    for star in stars:
        key_visibility_flicker(star, rng)
        key_location_bob(star, Vector((0.0, 0.0, rng.uniform(0.05, 0.16))))
    scroll_material(stream_mat, 1, 1.8)
    scroll_material(cyan_mat, 1, 2.1)
    scroll_material(bolt_mat, 2, 2.2)
    scroll_material(haze_mat, 2, 1.0)
    scroll_material(ring_mat, 0, 0.6)
    return root, [stream_mat, cyan_mat, bolt_mat, haze_mat, ring_mat, star_mat]


def build_ground(size: float = 8.0) -> bpy.types.Object:
    bm = bmesh.new()
    bmesh.ops.create_grid(bm, x_segments=18, y_segments=18, size=size)
    rng = random.Random(44)
    for vert in bm.verts:
        crag = rng.uniform(-0.04, 0.05)
        radial = vert.co.xy.length
        vert.co.z = crag * (0.35 + min(radial * 0.15, 1.0))
    ground = _object_from_bm("ReviewGround", bm, make_ground_material())
    return ground


def setup_world() -> None:
    scene = bpy.context.scene
    scene.render.engine = "BLENDER_EEVEE_NEXT" if "BLENDER_EEVEE_NEXT" in dir(bpy.types) else "BLENDER_EEVEE"
    try:
        scene.render.engine = "BLENDER_EEVEE_NEXT"
    except TypeError:
        scene.render.engine = "BLENDER_EEVEE"
    scene.frame_start = 1
    scene.frame_end = FRAME_END
    scene.render.fps = FPS
    scene.render.resolution_x = 720
    scene.render.resolution_y = 720
    scene.render.film_transparent = False
    if hasattr(scene, "eevee"):
        scene.eevee.taa_render_samples = 32
        if hasattr(scene.eevee, "use_bloom"):
            scene.eevee.use_bloom = True
            scene.eevee.bloom_intensity = 0.22
            scene.eevee.bloom_radius = 7.5
    for transform in ("Standard", "Khronos PBR Neutral", "AgX", "Filmic"):
        try:
            scene.view_settings.view_transform = transform
            break
        except TypeError:
            continue
    scene.view_settings.look = "None"
    try:
        scene.view_settings.exposure = 0.1
    except TypeError:
        pass

    world = bpy.data.worlds.get("EnergyReviewWorld") or bpy.data.worlds.new("EnergyReviewWorld")
    if hasattr(world, "color"):
        world.color = (0.0, 0.0, 0.0)
    try:
        world.use_nodes = True
        background = world.node_tree.nodes.get("Background")
        if background is not None:
            background.inputs["Color"].default_value = (0.0, 0.0, 0.0, 1.0)
            background.inputs["Strength"].default_value = 0.0
    except Exception:
        pass
    scene.world = world
    _setup_bloom(scene)


def _setup_bloom(scene) -> None:
    tree = bpy.data.node_groups.new("EnergyReviewComp", "CompositorNodeTree")
    scene.compositing_node_group = tree
    render_layers = tree.nodes.new("CompositorNodeRLayers")
    render_layers.location = (0, 0)
    glare = tree.nodes.new("CompositorNodeGlare")
    glare.location = (280, 0)
    type_set = False
    if "Type" in glare.inputs:
        for glare_type in ("Bloom", "BLOOM", "Fog Glow", "FOG_GLOW"):
            try:
                glare.inputs["Type"].default_value = glare_type
                type_set = True
                break
            except (TypeError, ValueError):
                continue
    if not type_set and hasattr(glare, "glare_type"):
        for glare_type in ("BLOOM", "FOG_GLOW"):
            try:
                glare.glare_type = glare_type
                break
            except TypeError:
                continue
    for key, value in (
        ("Threshold", 0.22),
        ("Size", 9.0),
        ("Mix", 0.38),
        ("Strength", 1.55),
        ("Quality", "HIGH"),
    ):
        if key in glare.inputs:
            try:
                glare.inputs[key].default_value = value
            except (TypeError, ValueError):
                pass
    output = tree.nodes.new("NodeGroupOutput")
    output.location = (560, 0)
    tree.interface.new_socket(name="Image", in_out="OUTPUT", socket_type="NodeSocketColor")
    tree.links.new(render_layers.outputs["Image"], glare.inputs["Image"])
    tree.links.new(glare.outputs["Image"], output.inputs["Image"])
    if hasattr(scene.render, "use_compositing"):
        scene.render.use_compositing = True
    if hasattr(scene.render, "use_sequencer"):
        scene.render.use_sequencer = False


def add_camera(name: str, location, target) -> bpy.types.Object:
    data = bpy.data.cameras.new(name)
    data.lens = 50.0
    camera = bpy.data.objects.new(name, data)
    bpy.context.scene.collection.objects.link(camera)
    _look_at(camera, location, target)
    return camera


def add_fill_light(name: str, location, color, energy: float) -> bpy.types.Object:
    data = bpy.data.lights.new(name, type="POINT")
    data.color = color
    data.energy = energy
    data.shadow_soft_size = 0.6
    light = bpy.data.objects.new(name, data)
    light.location = location
    bpy.context.scene.collection.objects.link(light)
    return light


def export_root(root: bpy.types.Object, path: str) -> None:
    meshes = [root] + [child for child in root.children_recursive if child.type == "MESH"]
    view_layer = bpy.context.view_layer
    for obj in list(bpy.data.objects):
        if obj is None:
            continue
        try:
            obj.select_set(False)
        except RuntimeError:
            pass
    for obj in meshes:
        if obj is None:
            continue
        obj.hide_viewport = False
        try:
            obj.select_set(True)
        except RuntimeError:
            pass
    view_layer.objects.active = root
    bpy.ops.export_scene.gltf(
        filepath=path,
        export_format="GLB",
        use_selection=True,
        export_apply=False,
        export_animations=True,
        export_animation_mode="NLA_TRACKS",
        export_frame_range=False,
        export_force_sampling=True,
        export_yup=True,
    )
    print("wrote {0} ({1:.1f} KB)".format(path, os.path.getsize(path) / 1024.0))


def hide_except(keep: set[str]) -> None:
    for obj in bpy.data.objects:
        if obj.type == "CAMERA":
            continue
        if obj.type == "LIGHT":
            wanted = {
                "Projectile": "FillProjectile",
                "BeamCore": "FillCore",
                "BeamStreams": "FillStreams",
            }
            obj.hide_render = obj.name not in {
                wanted[name] for name in keep if name in wanted}
            obj.hide_viewport = obj.hide_render
            continue
        hidden = obj.name not in keep and (
            obj.parent is None or obj.parent.name not in keep)
        if obj.name in keep:
            hidden = False
        # Keep children of a kept root visible.
        walker = obj
        while walker is not None:
            if walker.name in keep:
                hidden = False
                break
            walker = walker.parent
        if obj.name == "ReviewGround":
            hidden = "BeamCore" not in keep and "BeamStreams" not in keep
        obj.hide_render = hidden
        obj.hide_viewport = hidden


def render_still(camera: bpy.types.Object, name: str, frame: int) -> None:
    scene = bpy.context.scene
    scene.camera = camera
    scene.frame_set(frame)
    scene.render.filepath = os.path.join(PREVIEW_DIR, name + ".png")
    bpy.ops.render.render(write_still=True)
    print("rendered", scene.render.filepath)


def render_loop(camera: bpy.types.Object, name: str) -> None:
    scene = bpy.context.scene
    scene.camera = camera
    folder = _ensure_dir(os.path.join(PREVIEW_DIR, name))
    scene.render.image_settings.file_format = "PNG"
    for frame in range(1, FRAME_END + 1, 6):
        scene.frame_set(frame)
        scene.render.filepath = os.path.join(folder, "frame_{0:02d}.png".format(frame))
        bpy.ops.render.render(write_still=True)
    print("rendered loop", folder)


def main() -> None:
    _ensure_dir(REVIEW_DIR)
    _ensure_dir(PREVIEW_DIR)
    _clear_orphans()
    setup_world()
    build_ground()

    projectile, _p_mats = build_projectile(Vector((-3.2, 0.0, 1.1)))
    core_beam, _c_mats = build_core_beam(Vector((0.0, 0.0, 0.0)))
    stream_beam, _s_mats = build_stream_beam(Vector((3.4, 0.0, 0.0)))

    add_fill_light("FillProjectile", (-3.2, -0.8, 1.3), (0.20, 1.0, 0.35), 5.0)
    add_fill_light("FillCore", (0.0, -0.6, 0.4), (0.55, 0.15, 1.0), 6.0)
    add_fill_light("FillStreams", (3.4, -0.6, 0.3), (0.95, 0.15, 0.85), 6.5)

    cam_p = add_camera("CamProjectile", (-3.2, -2.15, 1.35), (-3.2, 0.0, 1.15))
    cam_c = add_camera("CamBeamCore", (0.0, -3.4, 1.55), (0.0, 0.0, 1.35))
    cam_s = add_camera("CamBeamStreams", (3.4, -3.5, 1.55), (3.4, 0.0, 1.35))
    bpy.context.scene.camera = cam_p

    for obj in bpy.data.objects:
        if obj.animation_data and obj.animation_data.action:
            push_nla(obj, "Loop")

    export_root(projectile, os.path.join(REVIEW_DIR, "energy_projectile.glb"))
    export_root(core_beam, os.path.join(REVIEW_DIR, "energy_beam_core.glb"))
    export_root(stream_beam, os.path.join(REVIEW_DIR, "energy_beam_streams.glb"))

    bpy.ops.wm.save_as_mainfile(filepath=BLEND_PATH)
    print("wrote", BLEND_PATH)

    hide_except({"Projectile"})
    render_still(cam_p, "projectile_a", 8)
    render_still(cam_p, "projectile_b", 28)
    render_loop(cam_p, "projectile_loop")

    hide_except({"BeamCore", "ReviewGround"})
    render_still(cam_c, "beam_core_a", 8)
    render_still(cam_c, "beam_core_b", 28)
    render_loop(cam_c, "beam_core_loop")

    hide_except({"BeamStreams", "ReviewGround"})
    render_still(cam_s, "beam_streams_a", 8)
    render_still(cam_s, "beam_streams_b", 28)
    render_loop(cam_s, "beam_streams_loop")

    hide_except({"Projectile", "BeamCore", "BeamStreams", "ReviewGround"})
    print("energy review assets ready")


if __name__ == "__main__":
    main()
