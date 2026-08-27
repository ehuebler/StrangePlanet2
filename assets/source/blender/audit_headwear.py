"""Audit settler hats against the live skull, from every useful angle.

A hat fails when the head punches through it, when the hat is buried in the
skull, or when the part that should sit on the scalp is floating. Decorative
bits (ear tips, brims, a halo) are allowed to stand off; the seat is not.

Run from the project root after the hats are exported:

    & "C:\\Program Files\\Blender Foundation\\Blender 5.1\\blender.exe" `
        --background --factory-startup `
        --python assets/source/blender/audit_headwear.py

    ... -- --only party_hat,beanie --no-render
"""

from __future__ import annotations

import argparse
import math
import os
import sys

import bpy
from mathutils import Vector
from mathutils.bvhtree import BVHTree

SOURCE_DIR = os.path.dirname(os.path.abspath(__file__))
if SOURCE_DIR not in sys.path:
    sys.path.insert(0, SOURCE_DIR)

from build_headwear import (  # noqa: E402
    APPAREL_DIR,
    CHAR_GLB,
    Fit,
    HATS,
    load_settler,
)
from previewkit import Preview  # noqa: E402

ROOT = os.path.abspath(os.path.join(SOURCE_DIR, os.pardir, os.pardir, os.pardir))
PREVIEW_DIR = os.path.join(ROOT, "assets", "previews", "apparel", "fit")

# How each hat is allowed to meet the skull. The seat is what is judged; ears,
# horns, brims and a halo are scenery around it.
#
# cover  — wraps the crown. Upper-hemisphere rays must hit the hat just outside
#          the scalp. Used for beanies, helmets, brimmed hats with a real crown.
# perch  — sits on the top of the head. Only near-vertical rays are required.
# band   — a ring around the temples. Open crown is fine; the band must seat.
# float  — meant to hover (halo). Must stay above the scalp and off the face.
KIND = {
    "party_hat": "perch",
    "bunny_ears": "band",
    "top_hat": "cover",
    "crown": "band",
    "beanie": "cover",
    "cowboy_hat": "cover",
    "propeller_cap": "cover",
    "flower_crown": "band",
    "antlers": "band",
    "halo": "float",
    "wizard_hat": "cover",
    "sombrero": "cover",
    "newsboy_cap": "cover",
    "helmet": "cover",
    "pirate_hat": "cover",
    "chef_toque": "cover",
    "jester_hat": "cover",
    "mushroom_cap": "cover",
    "antennae": "band",
    "visor": "front",
    "bow": "perch",
    "horned_helm": "cover",
    "fedora": "cover",
    "santa_hat": "cover",
    "cat_ears": "band",
    "beret": "cover",
    "baseball_cap": "cover",
    "sun_hat": "cover",
    "hard_hat": "cover",
    "ushanka": "cover",
    "turban": "cover",
    "devil_horns": "band",
    "unicorn_horn": "perch",
    "headphones": "band",
    "tiara": "band",
    "bandana": "cover",
    "rice_hat": "cover",
    "laurel": "band",
    "nightcap": "cover",
    "deerstalker": "cover",
    "frog_hood": "cover",
    "rainbow": "perch",
    "paper_crown": "band",
    "space_helmet": "cover",
    "cake_hat": "perch",
    "leaf_wreath": "band",
    "mohawk": "perch",
}

# Millimetres. Tight enough that a hat perched a finger above the scalp fails,
# loose enough that a 1 cm fashion gap and a hollow lining both pass.
BURY_MM = 8.0
POKE_MM = 7.0
FLOAT_MM = 22.0
SEAT_MIN_MM = 1.0
FACE_CLEAR_MM = 4.0

AZIMUTHS = 16
ELEVATIONS = (-8.0, 8.0, 22.0, 38.0, 52.0, 68.0, 82.0)
BAND_ELEVATIONS = (-2.0, 0.0, 2.0, 6.0)
COVER_ELEV = 40.0
PERCH_ELEV = 64.0
BAND_ELEV = (-4.0, 8.0)

VIEWS = (
    ("front", Vector((0.00, 0.42, 0.04))),
    ("back", Vector((0.00, -0.42, 0.06))),
    ("left", Vector((-0.42, 0.00, 0.05))),
    ("right", Vector((0.42, 0.00, 0.05))),
    ("threequarter", Vector((0.32, 0.34, 0.10))),
    ("top", Vector((0.02, 0.08, 0.42))),
)


def parse_args():
    argv = sys.argv[sys.argv.index("--") + 1:] if "--" in sys.argv else []
    parser = argparse.ArgumentParser()
    parser.add_argument("--only", default="")
    parser.add_argument("--no-render", action="store_true")
    return parser.parse_args(argv)


def wanted_slugs(raw: str) -> list[str]:
    catalog = [slug for slug, _fn in HATS]
    if not raw.strip():
        return catalog
    asked = [item.strip() for item in raw.split(",") if item.strip()]
    missing = [slug for slug in asked if slug not in catalog]
    if missing:
        raise SystemExit("unknown hat(s): {0}".format(", ".join(missing)))
    return asked


def hat_path(slug: str) -> str:
    return os.path.join(APPAREL_DIR, "apparel_c3_{0}.glb".format(slug))


def import_hat_mesh(slug: str) -> bpy.types.Object:
    path = hat_path(slug)
    if not os.path.isfile(path):
        raise SystemExit("missing {0}".format(path))
    before = set(bpy.data.objects)
    bpy.ops.import_scene.gltf(filepath=path)
    added = [obj for obj in bpy.data.objects if obj not in before]
    mesh = next((obj for obj in added if obj.type == "MESH"
                 and "Character" not in obj.name and "Icosphere" not in obj.name),
                None)
    if mesh is None:
        for obj in added:
            bpy.data.objects.remove(obj, do_unlink=True)
        raise SystemExit("{0}: imported GLB has no hat mesh".format(slug))
    for obj in added:
        if obj != mesh and obj.type != "ARMATURE":
            bpy.data.objects.remove(obj, do_unlink=True)
    return mesh


def drop_hat(mesh: bpy.types.Object) -> None:
    rig = mesh.parent
    bpy.data.objects.remove(mesh, do_unlink=True)
    if rig is not None and rig.type == "ARMATURE" and rig.name != "CharacterRig":
        bpy.data.objects.remove(rig, do_unlink=True)


def world_tree(obj: bpy.types.Object) -> BVHTree:
    return BVHTree.FromObject(obj, bpy.context.evaluated_depsgraph_get())


def world_verts(obj: bpy.types.Object) -> list[Vector]:
    matrix = obj.matrix_world
    return [matrix @ vert.co.copy() for vert in obj.data.vertices]


def signed_out(point: Vector, tree: BVHTree) -> float | None:
    location, normal, _index, _distance = tree.find_nearest(point)
    if location is None:
        return None
    return (point - location).dot(normal)


def ray_hits(tree: BVHTree, origin: Vector, direction: Vector, reach: float
             ) -> float | None:
    location, _normal, _index, distance = tree.ray_cast(origin, direction, reach)
    if location is None:
        return None
    return distance


def head_centre(fit: Fit) -> Vector:
    return Vector((fit.cx, fit.cy, fit.skull.z + fit.skull_h * 0.55))


def seat_origin(fit: Fit, kind: str) -> Vector:
    if kind == "front":
        return Vector((fit.cx, fit.cy, fit.brow_z + 0.004))
    if kind == "band":
        return Vector((fit.cx, fit.cy, fit.band_z))
    return head_centre(fit)


def directions(kind: str) -> list[tuple[float, float, Vector]]:
    elevations = BAND_ELEVATIONS if kind in {"band", "front"} else ELEVATIONS
    out = []
    for az_i in range(AZIMUTHS):
        azimuth = az_i * 360.0 / AZIMUTHS
        for elevation in elevations:
            az = math.radians(azimuth)
            el = math.radians(elevation)
            direction = Vector((
                math.cos(el) * math.sin(az),
                math.cos(el) * math.cos(az),
                math.sin(el),
            )).normalized()
            out.append((azimuth, elevation, direction))
    return out


def seat_rays(kind: str, elevation: float, azimuth: float) -> bool:
    if kind == "cover":
        return elevation >= COVER_ELEV
    if kind == "perch":
        return elevation >= PERCH_ELEV
    if kind == "band":
        return BAND_ELEV[0] <= elevation <= BAND_ELEV[1]
    if kind == "front":
        front = min(azimuth, 360.0 - azimuth) <= 70.0
        return front and BAND_ELEV[0] <= elevation <= BAND_ELEV[1]
    return False


def measure(slug: str, hat: bpy.types.Object, body: bpy.types.Object, fit: Fit
            ) -> dict:
    kind = KIND.get(slug, "cover")
    body_tree = world_tree(body)
    hat_tree = world_tree(hat)
    origin = seat_origin(fit, kind)
    hat_points = world_verts(hat)

    bury_mm = 0.0
    buried = 0
    for point in hat_points:
        if point.z < fit.skull.z:
            continue
        # Halo and ear tips are allowed well off the skull; only points that
        # claim to occupy the head volume are a burial.
        radial = Vector((point.x - fit.cx, point.y - fit.cy, 0.0))
        if radial.length > fit.r * 1.35 and point.z < fit.top + 0.02:
            continue
        outside = signed_out(point, body_tree)
        if outside is None or outside >= -BURY_MM / 1000.0:
            continue
        buried += 1
        bury_mm = max(bury_mm, -outside * 1000.0)

    poke_mm = 0.0
    poked = 0
    if kind == "cover":
        matrix = body.matrix_world
        for vert in body.data.vertices:
            point = matrix @ vert.co
            if point.z < fit.skull.z + fit.skull_h * 0.62:
                continue
            location, normal, _index, _distance = hat_tree.find_nearest(point)
            if location is None:
                continue
            if normal.dot(vert.normal) < 0.15:
                continue
            depth = (point - location).dot(normal)
            if depth <= POKE_MM / 1000.0:
                continue
            poked += 1
            poke_mm = max(poke_mm, depth * 1000.0)

    float_mm = 0.0
    floating = 0
    seated = 0
    closest_mm = 1.0e9
    missing = 0
    inside = 0
    judged = 0
    for azimuth, elevation, direction in directions(kind):
        if kind == "float":
            continue
        if not seat_rays(kind, elevation, azimuth):
            continue
        judged += 1
        body_t = ray_hits(body_tree, origin, direction, 0.55)
        hat_t = ray_hits(hat_tree, origin, direction, 0.70)
        if body_t is None:
            continue
        if hat_t is None:
            missing += 1
            continue
        gap_mm = (hat_t - body_t) * 1000.0
        closest_mm = min(closest_mm, gap_mm)
        if gap_mm < -BURY_MM:
            inside += 1
            bury_mm = max(bury_mm, -gap_mm)
        elif gap_mm > FLOAT_MM:
            floating += 1
            float_mm = max(float_mm, gap_mm)
        elif gap_mm >= SEAT_MIN_MM:
            seated += 1

    face_hits = 0
    if kind == "float":
        for point in hat_points:
            if point.z >= fit.top - 0.008:
                continue
            outside = signed_out(point, body_tree)
            if outside is not None and outside < FACE_CLEAR_MM / 1000.0:
                face_hits += 1

    zs = [point.z for point in hat_points]
    problems = []
    if bury_mm > BURY_MM and (buried >= 8 or inside >= 3):
        problems.append("buried {0:.1f} mm in the skull".format(bury_mm))
    if poke_mm > POKE_MM and poked >= 6:
        problems.append("head pokes through {0:.1f} mm".format(poke_mm))
    if kind != "float" and judged:
        if kind == "cover" and missing > judged * 0.40:
            problems.append(
                "crown exposed from {0} of {1} seat rays".format(missing, judged))
        if kind in {"band", "front", "perch"} and seated < 3 and missing > judged * 0.75:
            problems.append("does not seat on the scalp")
        # A slouch or a brim can stand off on some rays. Fail only when the
        # closest contact is still a float.
        if closest_mm != 1.0e9 and closest_mm > FLOAT_MM:
            problems.append("floats {0:.1f} mm off the scalp".format(closest_mm))
    if kind == "float":
        if min(zs) < fit.top - 0.012:
            problems.append("halo drops into the crown")
        if face_hits >= 4:
            problems.append("intersects the face")
    if min(zs) < fit.neck.z - 0.05:
        problems.append("hem hangs below the neck")

    return {
        "slug": slug,
        "kind": kind,
        "ok": not problems,
        "problems": problems,
        "bury_mm": bury_mm,
        "poke_mm": poke_mm,
        "float_mm": 0.0 if closest_mm == 1.0e9 else max(0.0, closest_mm) if floating == 0
        else float_mm,
        "closest_mm": 0.0 if closest_mm == 1.0e9 else closest_mm,
        "seated": seated,
        "missing": missing,
        "judged": judged,
        "z_min": min(zs),
        "z_max": max(zs),
    }


def print_row(report: dict) -> None:
    mark = "PASS" if report["ok"] else "FAIL"
    print("  {0:<16} {1}  kind={2:<5}  bury={3:5.1f} poke={4:5.1f} "
          "seat={5:5.1f}  z[{6:.3f},{7:.3f}]  rays {8}/{9}".format(
              report["slug"], mark, report["kind"],
              report["bury_mm"], report["poke_mm"], report["closest_mm"],
              report["z_min"], report["z_max"],
              report["seated"], report["judged"]))
    for problem in report["problems"]:
        print("    - {0}".format(problem))


def render_views(slug: str, fit: Fit, preview: Preview) -> None:
    focus = Vector((fit.cx, fit.cy, fit.skull.z + fit.skull_h * 0.72))
    preview.lights(focus, spread=0.55, gain=1.15)
    for name, offset in VIEWS:
        preview.hero(focus + offset, focus, lens=70.0 if name != "top" else 55.0)
        preview.shot("{0}_{1}".format(slug, name), (640, 720))


def isolate(body: bpy.types.Object, hat: bpy.types.Object) -> None:
    for obj in bpy.data.objects:
        if obj.type == "MESH":
            obj.hide_render = obj not in (body, hat)
            obj.hide_viewport = obj not in (body, hat)


def main() -> None:
    args = parse_args()
    slugs = wanted_slugs(args.only)
    body, rig = load_settler()
    fit = Fit(body, rig)
    print("audit headwear  skull={0:.3f} top={1:.3f} r={2:.3f}".format(
        fit.skull.z, fit.top, fit.r))
    print("limits  bury<{0:.0f}mm  poke<{1:.0f}mm  float<{2:.0f}mm".format(
        BURY_MM, POKE_MM, FLOAT_MM))

    preview = None
    if not args.no_render:
        preview = Preview(PREVIEW_DIR, samples=12)

    reports = []
    failed = 0
    for slug in slugs:
        hat = import_hat_mesh(slug)
        bpy.context.view_layer.update()
        report = measure(slug, hat, body, fit)
        print_row(report)
        reports.append(report)
        if not report["ok"]:
            failed += 1
        if preview is not None:
            isolate(body, hat)
            render_views(slug, fit, preview)
            isolate(body, body)
        drop_hat(hat)

    print("audited {0}  failed {1}".format(len(reports), failed))
    if preview is not None:
        print("views in {0}".format(PREVIEW_DIR))
    if failed:
        raise SystemExit(1)


if __name__ == "__main__":
    main()
