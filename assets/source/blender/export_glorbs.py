"""Export each Glorb collection from the seven-creature blend as its own GLB."""

import os
import re

import bpy

BLEND = os.path.join(
    os.path.expanduser("~"),
    "Documents",
    "ChatGPT",
    "Strange Planet",
    "Glorbs",
    "Ethereal",
    "Strange_Planet_Seven_Glorbs_Ethereal.blend",
)
PROJECT = os.path.abspath(os.path.join(
    os.path.dirname(os.path.abspath(__file__)), os.pardir, os.pardir, os.pardir))
OUT = os.path.join(PROJECT, "assets", "runtime", "crawler", "glorbs")
KINDS = {
    "Jellyfish": "glorb_jellyfish",
    "Rhino": "glorb_rhino",
    "Eyeball": "glorb_eyeball",
    "Punching": "glorb_punching",
    "OneArmed": "glorb_one_armed",
    "Spider": "glorb_spider",
    "Angel": "glorb_angel",
}


def _kind_of(name):
    folded = re.sub(r"[^a-z]", "", name.lower())
    for kind, slug in KINDS.items():
        if kind.lower() in folded:
            return slug
    return ""


def _exportable(obj):
    if obj.type in {"MESH", "ARMATURE"}:
        return True
    if obj.type != "EMPTY":
        return False
    folded = obj.name.lower()
    return "review" not in folded and "instance" not in folded


def _objects_for(slug):
    found = []
    seen = set()
    for obj in bpy.data.objects:
        if not _exportable(obj) or obj.name in seen:
            continue
        hit = _kind_of(obj.name) == slug
        if not hit:
            for col in obj.users_collection:
                if _kind_of(col.name) == slug:
                    hit = True
                    break
        if not hit:
            continue
        found.append(obj)
        seen.add(obj.name)
    return found


def _pack_skin_uvs(obj):
    mesh = obj.data
    coord = mesh.attributes.get("EtherealCoord")
    eyes = mesh.attributes.get("EtherealEyes")
    if coord is None:
        print("  no EtherealCoord on", obj.name)
        return
    if len(mesh.uv_layers) < 1:
        mesh.uv_layers.new(name="UVMap")
    if len(mesh.uv_layers) < 2:
        mesh.uv_layers.new(name="EtherealMask")
    uv_xy = mesh.uv_layers[0]
    uv_ze = mesh.uv_layers[1]
    for loop in mesh.loops:
        vertex = loop.vertex_index
        at = coord.data[vertex].vector
        mask = eyes.data[vertex].value if eyes is not None else 0.0
        uv_xy.data[loop.index].uv = (at.x, at.y)
        uv_ze.data[loop.index].uv = (at.z, mask)
    print("  packed skin uvs", obj.name)


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


def _fresh_scene(slug, objects):
    name = "glorb_export"
    if name in bpy.data.scenes:
        bpy.data.scenes.remove(bpy.data.scenes[name])
    scene = bpy.data.scenes.new(name)
    bpy.context.window.scene = scene
    for obj in objects:
        try:
            scene.collection.objects.link(obj)
        except RuntimeError:
            pass
    print("  scene", scene.name, "slug", slug)
    return scene


def _ensure_nla(objects, slug):
    actions = [action for action in bpy.data.actions if _kind_of(action.name) == slug]
    for obj in objects:
        if obj.type != "ARMATURE":
            continue
        ad = obj.animation_data_create()
        ad.action = None
        for track in list(ad.nla_tracks):
            ad.nla_tracks.remove(track)
        have = {track.name for track in ad.nla_tracks}
        for action in actions:
            if action.name in have:
                continue
            track = ad.nla_tracks.new()
            track.name = action.name
            start = int(action.frame_range[0])
            strip = track.strips.new(action.name, start, action)
            for slot in getattr(action, "slots", []):
                ident = "%s%s" % (getattr(slot, "identifier", ""), getattr(slot, "name_display", ""))
                if obj.name in ident:
                    strip.action_slot = slot
                    break
            have.add(action.name)
        print("  nla", obj.name, [track.name for track in ad.nla_tracks])


def _export(slug, objects):
    os.makedirs(OUT, exist_ok=True)
    path = os.path.join(OUT, slug + ".glb")
    _ensure_nla(objects, slug)
    for obj in objects:
        if obj.type == "MESH":
            _pack_skin_uvs(obj)
    view = bpy.context.view_layer
    for obj in objects:
        _show(obj)
    view.update()
    for obj in objects:
        obj.hide_viewport = False
    for obj in view.objects:
        obj.select_set(False)
    selected = []
    for obj in objects:
        if obj.name not in view.objects:
            raise RuntimeError("%s not in the view layer: %s" % (slug, obj.name))
        obj.select_set(True)
        selected.append(obj.name)
    view.objects.active = objects[0]
    print("exporting", slug, selected)
    bpy.ops.export_scene.gltf(
        filepath=path,
        export_format="GLB",
        use_selection=True,
        export_apply=True,
        export_texcoords=True,
        export_normals=True,
        export_skins=True,
        export_animations=True,
        export_animation_mode="NLA_TRACKS",
        export_frame_range=False,
        export_force_sampling=True,
        export_yup=True,
    )
    print("wrote", path, "%.1f KB" % (os.path.getsize(path) / 1024.0))


def _purge_others(keep):
    keep_set = set(keep)
    for obj in list(bpy.data.objects):
        if obj in keep_set:
            _show(obj)
            continue
        if obj.animation_data:
            obj.animation_data_clear()
        for col in list(obj.users_collection):
            try:
                col.objects.unlink(obj)
            except RuntimeError:
                pass


def main():
    missing = []
    for slug in KINDS.values():
        bpy.ops.wm.open_mainfile(filepath=BLEND)
        print("blend", bpy.data.filepath, "slug", slug)
        objects = _objects_for(slug)
        if not objects:
            missing.append(slug)
            print("MISSING", slug)
            continue
        _purge_others(objects)
        _fresh_scene(slug, objects)
        _export(slug, objects)
    if missing:
        raise SystemExit("no objects for %s" % missing)


if __name__ == "__main__":
    main()
