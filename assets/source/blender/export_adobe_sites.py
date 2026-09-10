"""Export adobe city, castle, and office buildings to runtime GLBs.

    & "C:\\Program Files\\Blender Foundation\\Blender 5.1\\blender.exe" `
        --background --factory-startup `
        --python assets/source/blender/export_adobe_sites.py
"""

from __future__ import annotations

import os
import re
import sys

import bpy
from mathutils import Vector

SOURCE_DIR = os.path.dirname(os.path.abspath(__file__))
PROJECT_DIR = os.path.abspath(os.path.join(SOURCE_DIR, os.pardir, os.pardir, os.pardir))
CHAT_DIR = os.path.join(
    os.path.expanduser("~"), "Documents", "ChatGPT", "Strange Planet")
RUNTIME_DIR = os.path.join(
    PROJECT_DIR, "assets", "runtime", "environment", "adobe")

EIGHT = "Strange_Planet_Eight_Buildings_Adobe.blend"
EXPANDED = "Strange_Planet_Six_Expanded_Buildings_Adobe_Smooth_Join.blend"
CASTLE = "Strange_Planet_Blob_Castle_Adobe.blend"
HQ = "Strange_Planet_Corporate_HQ_Adobe.blend"

CITY_SLUGS = {
    1: "adobe_01_leaning_loaf",
    2: "adobe_02_high_shoulder",
    3: "adobe_03_three_roots",
    4: "adobe_04_twin_humps",
    5: "adobe_05_leaning_tower",
    6: "adobe_06_long_heel",
    7: "adobe_07_open_pavilion",
    8: "adobe_08_gentle_beast",
    11: "adobe_11_broad_shoulder_hall",
    12: "adobe_12_skylight_commons",
    13: "adobe_13_twin_shoulder_maison",
    14: "adobe_14_leaning_balcony",
    15: "adobe_15_roofstep_burrow",
    16: "adobe_16_three_arch_longhouse",
}

PREFIX = re.compile(r"^(\d{2})\s")


def _blend(name: str) -> str:
    path = os.path.join(CHAT_DIR, name)
    if os.path.isfile(path):
        return path
    fallback = os.path.join(PROJECT_DIR, "assets", "source", "environment", name)
    if os.path.isfile(fallback):
        return fallback
    raise FileNotFoundError(path)


def _dump_inventory() -> None:
    print("---- %s ----" % (bpy.data.filepath or "<unsaved>"), flush=True)
    print("scenes: %s" % [(scene.name, len(scene.objects)) for scene in bpy.data.scenes], flush=True)
    print("materials: %s" % [mat.name for mat in bpy.data.materials], flush=True)
    for obj in bpy.data.objects:
        if obj.type != "MESH" or obj.data is None:
            continue
        keys = {key: obj[key] for key in obj.keys() if key not in {"_RNA_UI"}}
        print("  MESH %s verts=%d props=%s" % (
            obj.name, len(obj.data.vertices), keys), flush=True)


def _mesh_objects() -> list:
    out = []
    for obj in bpy.data.objects:
        if obj.type != "MESH" or obj.data is None:
            continue
        name = obj.name.lower()
        if "camera" in name or name.startswith("00 ") or "route" in name:
            continue
        out.append(obj)
    return out


def _building_id(obj) -> int:
    raw = obj.get("Village addition")
    if raw not in (None,):
        try:
            return int(raw)
        except (TypeError, ValueError):
            pass
    match = PREFIX.match(obj.name)
    if match:
        return int(match.group(1))
    return -1


def _group_city(wanted: set[int]) -> dict[int, list]:
    groups: dict[int, list] = {key: [] for key in wanted}
    for obj in _mesh_objects():
        key = _building_id(obj)
        if key in groups:
            groups[key].append(obj)
    return groups


def _group_tagged(tag: str) -> list:
    found = []
    for obj in _mesh_objects():
        if obj.get(tag):
            found.append(obj)
    if found:
        return found
    return _mesh_objects()


def _detach(objects: list) -> None:
    for obj in objects:
        world = obj.matrix_world.copy()
        obj.parent = None
        obj.matrix_world = world


def _recenter(objects: list) -> None:
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
        obj.matrix_world.translation += delta
    print("  bounds {0:.1f} x {1:.1f} x {2:.1f} m".format(
        maxs.x - mins.x, maxs.y - mins.y, maxs.z - mins.z), flush=True)


def _export(objects: list, path: str) -> None:
    if not objects:
        raise RuntimeError("no meshes for %s" % path)
    _detach(objects)
    _recenter(objects)
    view = bpy.context.view_layer
    for obj in objects:
        obj.hide_viewport = False
        obj.hide_set(False)
    for obj in view.objects:
        obj.select_set(False)
    for obj in objects:
        obj.select_set(True)
    view.objects.active = objects[0]
    selected = [obj.name for obj in bpy.context.selected_objects]
    missing = [obj.name for obj in objects if obj.name not in selected]
    if missing:
        raise RuntimeError("selection failed for %s" % missing)
    os.makedirs(os.path.dirname(path), exist_ok=True)
    bpy.ops.export_scene.gltf(
        filepath=path,
        export_format="GLB",
        use_selection=True,
        export_apply=True,
        export_texcoords=True,
        export_normals=True,
        export_materials="EXPORT",
        export_animations=False,
        export_yup=True,
    )
    print("wrote {0} ({1:.1f} KB, {2} meshes)".format(
        path, os.path.getsize(path) / 1024.0, len(objects)), flush=True)


def _open(path: str) -> None:
    bpy.ops.wm.open_mainfile(filepath=path)
    scene = max(bpy.data.scenes, key=lambda item: len(item.objects))
    bpy.context.window.scene = scene
    _dump_inventory()


def export_city_blend(blend_name: str, wanted: set[int]) -> None:
    _open(_blend(blend_name))
    groups = _group_city(wanted)
    for key, objects in groups.items():
        slug = CITY_SLUGS.get(key)
        if slug is None:
            continue
        if not objects:
            raise RuntimeError("missing building %s in %s" % (key, blend_name))
        _export(objects, os.path.join(RUNTIME_DIR, slug + ".glb"))


def export_tagged(blend_name: str, tag: str, filename: str) -> None:
    _open(_blend(blend_name))
    _export(_group_tagged(tag), os.path.join(RUNTIME_DIR, filename))


def main() -> None:
    os.makedirs(RUNTIME_DIR, exist_ok=True)
    export_city_blend(EIGHT, {1, 2, 3, 4, 5, 6, 7, 8})
    export_city_blend(EXPANDED, {11, 12, 13, 14, 15, 16})
    export_tagged(CASTLE, "Castle element", "adobe_castle.glb")
    export_tagged(HQ, "HQ element", "adobe_office.glb")
    print("adobe site export done", flush=True)


if __name__ == "__main__":
    try:
        main()
    except Exception as err:
        print("EXPORT FAILED:", err, file=sys.stderr, flush=True)
        raise
