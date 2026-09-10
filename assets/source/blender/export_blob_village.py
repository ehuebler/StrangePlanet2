"""Export the Blob Village blend as one runtime GLB for every city site."""

import os
import re
import sys

import bpy
from mathutils import Vector

SOURCE_DIR = os.path.dirname(os.path.abspath(__file__))
PROJECT_DIR = os.path.abspath(os.path.join(SOURCE_DIR, os.pardir, os.pardir, os.pardir))
BLEND = os.path.join(
    os.path.expanduser("~"),
    "Documents",
    "ChatGPT",
    "Strange Planet",
    "Blob Village",
    "Strange_Planet_Blob_Village.blend",
)
OUT = os.path.join(
    PROJECT_DIR, "assets", "runtime", "environment", "adobe", "adobe_blob_village.glb")
# Whole-word tokens only. Substring "light" used to drop "Skylight Commons".
SKIP_NAME = ("camera", "light", "empty", "curve")
SKIP_MESH = ("neutral ground", "quiet warm")
_NAME_WORDS = re.compile(r"[a-z0-9]+")


def _skip(obj):
    folded = obj.name.lower()
    words = set(_NAME_WORDS.findall(folded))
    if words.intersection(SKIP_NAME):
        return True
    if any(token in folded for token in SKIP_MESH):
        return True
    if folded == "plane" or folded.startswith("plane."):
        return True
    for slot in obj.material_slots:
        mat = slot.material
        if mat is not None and "quiet warm" in mat.name.lower():
            return True
    return False


def _meshes():
    found = []
    for obj in bpy.data.objects:
        if obj.type != "MESH" or obj.data is None:
            continue
        if _skip(obj):
            continue
        found.append(obj)
    return found


def _dump(objects):
    print("blend", bpy.data.filepath)
    print("scenes", [(scene.name, len(scene.objects)) for scene in bpy.data.scenes])
    print("materials", [mat.name for mat in bpy.data.materials])
    mins = Vector((1.0e9, 1.0e9, 1.0e9))
    maxs = Vector((-1.0e9, -1.0e9, -1.0e9))
    for obj in objects:
        keys = {key: obj[key] for key in obj.keys() if key not in {"_RNA_UI"}}
        print("  MESH", obj.name, "verts=%d" % len(obj.data.vertices), "props=%s" % keys)
        for corner in obj.bound_box:
            world = obj.matrix_world @ Vector(corner)
            mins.x = min(mins.x, world.x)
            mins.y = min(mins.y, world.y)
            mins.z = min(mins.z, world.z)
            maxs.x = max(maxs.x, world.x)
            maxs.y = max(maxs.y, world.y)
            maxs.z = max(maxs.z, world.z)
    print("bounds {0:.2f} x {1:.2f} x {2:.2f} m  floor={3:.3f}".format(
        maxs.x - mins.x, maxs.y - mins.y, maxs.z - mins.z, mins.z))
    print("center", ((mins + maxs) * 0.5))


def _show(obj):
    obj.hide_viewport = False
    obj.hide_render = False
    try:
        obj.hide_set(False)
    except RuntimeError:
        pass
    scene_col = bpy.context.scene.collection
    if obj.name not in scene_col.objects:
        try:
            scene_col.objects.link(obj)
        except RuntimeError:
            pass


def _recenter(objects):
    mins = Vector((1.0e9, 1.0e9, 1.0e9))
    maxs = Vector((-1.0e9, -1.0e9, -1.0e9))
    for obj in objects:
        for corner in obj.bound_box:
            world = obj.matrix_world @ Vector(corner)
            mins.x = min(mins.x, world.x)
            mins.y = min(mins.y, world.y)
            mins.z = min(mins.z, world.z)
            maxs.x = max(maxs.x, world.x)
            maxs.y = max(maxs.y, world.y)
            maxs.z = max(maxs.z, world.z)
    delta = Vector((-(mins.x + maxs.x) * 0.5, -(mins.y + maxs.y) * 0.5, -mins.z))
    for obj in objects:
        world = obj.matrix_world.copy()
        obj.parent = None
        obj.matrix_world = world
        obj.matrix_world.translation += delta
    print("recentered by", tuple(round(value, 3) for value in delta))


def main():
    if not bpy.data.filepath:
        bpy.ops.wm.open_mainfile(filepath=BLEND)
    objects = _meshes()
    if not objects:
        raise SystemExit("no village meshes")
    _dump(objects)
    _recenter(objects)
    view = bpy.context.view_layer
    for obj in objects:
        _show(obj)
    view.update()
    for obj in objects:
        obj.hide_viewport = False
    for obj in view.objects:
        obj.select_set(False)
    for obj in objects:
        if obj.name not in view.objects:
            raise RuntimeError("not in view layer: %s" % obj.name)
        obj.select_set(True)
    view.objects.active = objects[0]
    os.makedirs(os.path.dirname(OUT), exist_ok=True)
    bpy.ops.export_scene.gltf(
        filepath=OUT,
        export_format="GLB",
        use_selection=True,
        export_apply=True,
        export_texcoords=True,
        export_normals=True,
        export_materials="EXPORT",
        export_animations=False,
        export_yup=True,
    )
    print("wrote", OUT, "%.1f KB" % (os.path.getsize(OUT) / 1024.0), "meshes", len(objects))


if __name__ == "__main__":
    try:
        main()
    except Exception as err:
        print("EXPORT FAILED:", err, file=sys.stderr)
        raise
