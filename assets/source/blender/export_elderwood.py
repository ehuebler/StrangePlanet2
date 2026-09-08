"""Export The Giving Tree (Elderwood) blend to a runtime GLB."""

from __future__ import annotations

import json
import sys
from pathlib import Path

import bpy


BLEND = Path(r"c:\Users\ellio\Desktop\office\deliverables\elderwood\Elderwood_Giant_Tree.blend")
OUT = Path(r"c:\Users\ellio\Desktop\Strange Planet\assets\runtime\crawler\bosses\elderwood.glb")
REPORT = Path(r"c:\Users\ellio\Desktop\Strange Planet\assets\runtime\crawler\bosses\elderwood_export.json")


def _aabb() -> dict:
    mins = [1e9, 1e9, 1e9]
    maxs = [-1e9, -1e9, -1e9]
    found = False
    for obj in bpy.data.objects:
        if obj.type != "MESH":
            continue
        for corner in obj.bound_box:
            world = obj.matrix_world @ __import__("mathutils").Vector(corner)
            for i in range(3):
                mins[i] = min(mins[i], world[i])
                maxs[i] = max(maxs[i], world[i])
            found = True
    if not found:
        return {}
    return {
        "min": mins,
        "max": maxs,
        "size": [maxs[i] - mins[i] for i in range(3)],
        "height": maxs[2] - mins[2],
    }


def _report() -> dict:
    actions = sorted(action.name for action in bpy.data.actions)
    meshes = []
    for obj in bpy.data.objects:
        if obj.type != "MESH":
            continue
        keys = []
        if obj.data.shape_keys is not None:
            keys = [key.name for key in obj.data.shape_keys.key_blocks]
        meshes.append({
            "name": obj.name,
            "verts": len(obj.data.vertices),
            "shape_keys": keys,
        })
    armatures = [obj.name for obj in bpy.data.objects if obj.type == "ARMATURE"]
    return {
        "actions": actions,
        "armatures": armatures,
        "meshes": meshes,
        "bounds": _aabb(),
    }


def main() -> None:
    bpy.ops.wm.open_mainfile(filepath=str(BLEND))
    payload = _report()
    OUT.parent.mkdir(parents=True, exist_ok=True)
    kwargs = {
        "filepath": str(OUT),
        "export_format": "GLB",
        "use_selection": False,
        "export_texcoords": True,
        "export_normals": True,
        "export_materials": "EXPORT",
        "export_skins": True,
        "export_morph": True,
        "export_animations": True,
        "export_apply": False,
    }
    # Blender 4.5 uses export_animation_mode; older builds used export_nla_strips.
    try:
        bpy.ops.export_scene.gltf(export_animation_mode="ACTIONS", **kwargs)
    except TypeError:
        bpy.ops.export_scene.gltf(export_nla_strips=False, **kwargs)
    payload["glb"] = str(OUT)
    payload["glb_bytes"] = OUT.stat().st_size if OUT.exists() else 0
    REPORT.write_text(json.dumps(payload, indent=2), encoding="utf-8")
    print("elderwood export", json.dumps(payload["bounds"], indent=2))
    print("actions", payload["actions"])
    print("wrote", OUT, payload["glb_bytes"])


if __name__ == "__main__":
    # Blender keeps its own flags in argv; this script is launched with --python.
    sys.argv = [sys.argv[0]]
    main()
