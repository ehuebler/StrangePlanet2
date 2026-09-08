"""Re-export the three energy VFX roots from the saved review blend.

    & "C:\\Program Files\\Blender Foundation\\Blender 5.1\\blender.exe" `
        --background --factory-startup `
        --python assets/source/blender/export_energy_review.py
"""

from __future__ import annotations

import os
import shutil

import bpy

SOURCE_DIR = os.path.dirname(os.path.abspath(__file__))
PROJECT_DIR = os.path.abspath(os.path.join(
    SOURCE_DIR, os.pardir, os.pardir, os.pardir))
REVIEW_DIR = os.path.join(PROJECT_DIR, "assets", "source", "vfx", "energy_review")
RUNTIME_DIR = os.path.join(PROJECT_DIR, "assets", "runtime", "vfx", "energy")
BLEND_PATH = os.path.join(REVIEW_DIR, "energy_review.blend")

ROOTS = (
    ("Projectile", "energy_projectile.glb"),
    ("BeamCore", "energy_beam_core.glb"),
    ("BeamStreams", "energy_beam_streams.glb"),
)


def _ensure_dir(path: str) -> str:
    os.makedirs(path, exist_ok=True)
    return path


def export_root(root: bpy.types.Object, path: str) -> None:
    meshes = [root] + [
        child for child in root.children_recursive if child.type in {
            "MESH", "EMPTY", "ARMATURE"
        }
    ]
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
        obj.hide_set(False)
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


def main() -> None:
    if not os.path.isfile(BLEND_PATH):
        raise FileNotFoundError(BLEND_PATH)
    bpy.ops.wm.open_mainfile(filepath=BLEND_PATH)
    _ensure_dir(REVIEW_DIR)
    _ensure_dir(RUNTIME_DIR)
    for object_name, filename in ROOTS:
        root = bpy.data.objects.get(object_name)
        if root is None:
            raise RuntimeError("missing object {0} in {1}".format(
                object_name, BLEND_PATH))
        dest = os.path.join(REVIEW_DIR, filename)
        export_root(root, dest)
        runtime = os.path.join(RUNTIME_DIR, filename)
        shutil.copy2(dest, runtime)
        print("copied", runtime)


if __name__ == "__main__":
    main()
