"""Profile rhino.blend after normalization, to place bones from measurements.

    & "C:\\Program Files\\Blender Foundation\\Blender 5.1\\blender.exe" `
        --background "assets/source/meshmaker/rhino.blend" `
        --python assets/source/blender/_inspect_rhino.py

Same questions as the alpaca inspection asks, plus the two this animal adds: how
far the head reaches past the shoulders and where along it the horn sits, because
a charge is aimed with the horn and the horn has to be found before it can be
aimed with.
"""

import math
import os

import bpy
from mathutils import Matrix, Vector

SOURCE_DIR = os.path.dirname(os.path.abspath(__file__))
ROOT = os.path.abspath(os.path.join(
    SOURCE_DIR, os.pardir, os.pardir, os.pardir))
VIEW_DIR = os.path.join(ROOT, "assets", "previews", "authoring")

TARGET_HEIGHT = 1.85
BANDS = 16
## The sculpt faces Blender -X. The rigged animal faces +Y, the way every other
## character here does, so every measurement below is taken after that turn.
FACING_TURN = -math.pi * 0.5


def mesh_object():
    """The sculpt, whatever it happens to be called in this file."""
    named = bpy.data.objects.get("geometry_0")
    if named is not None:
        return named
    meshes = [obj for obj in bpy.data.objects if obj.type == "MESH"]
    if not meshes:
        raise SystemExit("rhino.blend contains no mesh")
    return max(meshes, key=lambda obj: len(obj.data.vertices))


def normalized_points(obj):
    points = [obj.matrix_world @ vertex.co for vertex in obj.data.vertices]
    low = [min(p[i] for p in points) for i in range(3)]
    high = [max(p[i] for p in points) for i in range(3)]
    scale = TARGET_HEIGHT / (high[2] - low[2])
    base = Matrix.Scale(scale, 4) @ Matrix.Rotation(FACING_TURN, 4, "Z")
    turned = [base @ p for p in points]
    tl = [min(p[i] for p in turned) for i in range(3)]
    th = [max(p[i] for p in turned) for i in range(3)]
    offset = Vector((-(tl[0] + th[0]) * 0.5, 0.0, -tl[2]))
    return [p + offset for p in turned]


def span(values):
    return (min(values), max(values)) if values else (float("nan"),) * 2


def inventory(obj):
    print("--- objects ---")
    for other in bpy.data.objects:
        print("%-20s %-10s verts=%s" % (
            other.name, other.type,
            len(other.data.vertices) if other.type == "MESH" else "-"))
        if other.type == "ARMATURE":
            print("  bones: %s" % ", ".join(
                bone.name for bone in other.data.bones))
    mesh = obj.data
    print("--- %s ---" % obj.name)
    print("verts=%d polys=%d tris=%d" % (
        len(mesh.vertices), len(mesh.polygons),
        sum(max(len(p.vertices) - 2, 0) for p in mesh.polygons)))
    print("uv layers: %s" % ([layer.name for layer in mesh.uv_layers] or "none"))
    print("color attributes: %s" % ([
        "%s(%s/%s)" % (c.name, c.domain, c.data_type)
        for c in mesh.color_attributes] or "none"))
    print("materials: %s" % ([m.name if m else None
                              for m in mesh.materials] or "none"))
    print("vertex groups: %s" % ([g.name for g in obj.vertex_groups] or "none"))


def render_views(obj):
    """Three flat views of the sculpt, because numbers do not say which end is
    the head. Workbench with vertex colour, the same look the other authoring
    checks in this folder use."""
    scene = bpy.context.scene
    scene.render.engine = "BLENDER_WORKBENCH"
    scene.display.shading.light = "STUDIO"
    scene.display.shading.color_type = "VERTEX"
    scene.display.shading.show_shadows = True
    scene.display.shading.show_cavity = True
    scene.render.image_settings.file_format = "PNG"
    scene.render.film_transparent = False
    scene.render.resolution_x = 720
    scene.render.resolution_y = 540
    scene.render.resolution_percentage = 100

    points = [obj.matrix_world @ vertex.co for vertex in obj.data.vertices]
    low = Vector([min(p[i] for p in points) for i in range(3)])
    high = Vector([max(p[i] for p in points) for i in range(3)])
    middle = (low + high) * 0.5
    reach = max(high - low) * 1.5

    camera_data = bpy.data.cameras.new("InspectCamera")
    camera_data.type = "ORTHO"
    camera_data.ortho_scale = max(high - low) * 1.15
    camera = bpy.data.objects.new("InspectCamera", camera_data)
    scene.collection.objects.link(camera)
    scene.camera = camera
    os.makedirs(VIEW_DIR, exist_ok=True)
    for name, offset in (
            ("plus_x", Vector((reach, 0.0, 0.0))),
            ("plus_y", Vector((0.0, reach, 0.0))),
            ("top", Vector((0.0, 0.0, reach))),
            ("three_quarter", Vector((reach, reach, reach * 0.55))),
    ):
        camera.location = middle + offset
        camera.rotation_euler = (
            middle - camera.location).to_track_quat("-Z", "Y").to_euler()
        scene.render.filepath = os.path.join(
            VIEW_DIR, "rhino_source_%s.png" % name)
        bpy.ops.render.render(write_still=True)
        print("wrote " + scene.render.filepath)


def report():
    obj = mesh_object()
    inventory(obj)
    render_views(obj)
    points = normalized_points(obj)
    low = [min(p[i] for p in points) for i in range(3)]
    high = [max(p[i] for p in points) for i in range(3)]
    height = high[2] - low[2]
    print("bounds low=%s high=%s" % (
        tuple(round(v, 3) for v in low), tuple(round(v, 3) for v in high)))

    print("--- z bands (x span, y span, count) ---")
    for band in range(BANDS):
        z0 = low[2] + height * band / BANDS
        z1 = low[2] + height * (band + 1) / BANDS
        inside = [p for p in points if z0 <= p.z < z1]
        xs = span([p.x for p in inside])
        ys = span([p.y for p in inside])
        print("z %.3f..%.3f  n=%4d  x %.3f..%.3f  y %.3f..%.3f" % (
            z0, z1, len(inside), xs[0], xs[1], ys[0], ys[1]))

    print("--- y bands (front +Y is the head) ---")
    y_low, y_high = low[1], high[1]
    for band in range(BANDS):
        y0 = y_low + (y_high - y_low) * band / BANDS
        y1 = y_low + (y_high - y_low) * (band + 1) / BANDS
        inside = [p for p in points if y0 <= p.y < y1]
        xs = span([p.x for p in inside])
        zs = span([p.z for p in inside])
        print("y %.3f..%.3f  n=%4d  x %.3f..%.3f  z %.3f..%.3f" % (
            y0, y1, len(inside), xs[0], xs[1], zs[0], zs[1]))

    print("--- foot clusters: verts below 12%% height, by side and end ---")
    ankle_band = [p for p in points if p.z < low[2] + height * 0.12]
    for side_name, keep_x in (("Left(x<0)", lambda x: x < 0.0),
                              ("Right(x>0)", lambda x: x >= 0.0)):
        for end_name, keep_y in (("Front(+Y)", lambda y: y > 0.0),
                                 ("Back(-Y)", lambda y: y <= 0.0)):
            inside = [p for p in ankle_band
                      if keep_x(p.x) and keep_y(p.y)]
            if not inside:
                print("%s %s: empty" % (side_name, end_name))
                continue
            centre = sum(inside, Vector()) / len(inside)
            xs = span([p.x for p in inside])
            ys = span([p.y for p in inside])
            print("%s %s n=%4d centre=%s x %.3f..%.3f y %.3f..%.3f" % (
                side_name, end_name, len(inside),
                tuple(round(v, 3) for v in centre), xs[0], xs[1],
                ys[0], ys[1]))

    print("--- leg columns: x span per (y band, low z) to find leg tops ---")
    for band in range(8):
        z0 = low[2] + height * band / 8.0
        z1 = low[2] + height * (band + 1) / 8.0
        inside = [p for p in points if z0 <= p.z < z1]
        front = [p for p in inside if p.y > 0.0]
        back = [p for p in inside if p.y <= 0.0]
        print("z %.3f..%.3f  front n=%4d x %s | back n=%4d x %s" % (
            z0, z1, len(front), tuple(round(v, 3) for v in span(
                [p.x for p in front])),
            len(back), tuple(round(v, 3) for v in span(
                [p.x for p in back]))))

    # The horn: whatever sticks furthest forward, and how narrow it is there.
    print("--- nose end: the forward tenth, sliced along +Y ---")
    nose_from = y_high - (y_high - y_low) * 0.10
    for step in range(6):
        y0 = nose_from + (y_high - nose_from) * step / 6.0
        y1 = nose_from + (y_high - nose_from) * (step + 1) / 6.0
        inside = [p for p in points if y0 <= p.y <= y1]
        xs = span([p.x for p in inside])
        zs = span([p.z for p in inside])
        print("y %.3f..%.3f  n=%4d  width %.3f  x %.3f..%.3f  z %.3f..%.3f" % (
            y0, y1, len(inside), (xs[1] - xs[0]) if inside else float("nan"),
            xs[0], xs[1], zs[0], zs[1]))
    tip = max(points, key=lambda p: p.y)
    tallest_front = max((p for p in points if p.y > y_high * 0.55),
                        key=lambda p: p.z, default=None)
    print("furthest forward vertex: %s" % (
        tuple(round(v, 3) for v in tip),))
    if tallest_front is not None:
        print("highest vertex ahead of mid-body: %s" % (
            tuple(round(v, 3) for v in tallest_front),))


report()
