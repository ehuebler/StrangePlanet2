"""Build settler-weighted headwear garments.

Each hat is one lofted mesh (not stacked primitives), bound 100% to Head on the
same CharacterRig as player_character_3.glb, and written to
assets/runtime/apparel/apparel_c3_<slug>.glb for the hat slot.

Covering hats are hollow shells that wrap the skull. Brims and bands are tubes
with the hole left open, so a cap disk never cuts through the head. Tall crowns
only become solid above the scalp. After each export the in-memory mesh is
measured by audit_headwear.py; a hat that clips or floats fails the build.

Run from the project root:

    & "C:\\Program Files\\Blender Foundation\\Blender 5.1\\blender.exe" `
        --background --factory-startup `
        --python assets/source/blender/build_headwear.py

    # one item:
    ... --python assets/source/blender/build_headwear.py -- --only party_hat
"""

from __future__ import annotations

import argparse
import math
import os
import sys

import bmesh
import bpy
from mathutils import Vector

SOURCE_DIR = os.path.dirname(os.path.abspath(__file__))
if SOURCE_DIR not in sys.path:
    sys.path.insert(0, SOURCE_DIR)

from propkit import (
    add_loft,
    add_path_loft,
    add_sphere,
    circle_profile,
    ensure_materials,
    new_object,
    reset_scene,
    ring as place_ring,
)

ROOT = os.path.abspath(os.path.join(SOURCE_DIR, os.pardir, os.pardir, os.pardir))
CHAR_GLB = os.path.join(ROOT, "assets", "runtime", "characters", "player_character_3.glb")
APPAREL_DIR = os.path.join(ROOT, "assets", "runtime", "apparel")

TAU = math.tau
SEGS = 28


# --------------------------------------------------------------------------
# Head fit, measured off the imported settler
# --------------------------------------------------------------------------

class Fit:
    def __init__(self, body: bpy.types.Object, rig: bpy.types.Object):
        bones = rig.data.bones
        self.body = body
        self.skull = bones["Head"].head_local.copy()
        self.neck = bones["Neck"].head_local.copy()
        self.cx = self.skull.x
        self.cy = self.skull.y
        self.top = max(vert.co.z for vert in body.data.vertices)
        head = [vert.co for vert in body.data.vertices if vert.co.z > self.skull.z]
        self.rx_skin = max(abs(vert.x - self.cx) for vert in head)
        self.ry_front = max(vert.y - self.cy for vert in head)
        self.ry_back = max(self.cy - vert.y for vert in head)
        self.skull_h = self.top - self.skull.z
        self.brim_z = self.skull.z + self.skull_h * 0.26
        self.brow_z = self.skull.z + self.skull_h * 0.44
        self.band_z = self.skull.z + self.skull_h * 0.58
        self.crown_z = self.top + 0.004
        pad = 1.07
        self.rx = self.rx_skin * pad
        self.ry_f = self.ry_front * pad
        self.ry_b = self.ry_back * pad
        self.r = max(self.rx, self.ry_f, self.ry_b)

    def centre(self, z: float) -> Vector:
        return Vector((self.cx, self.cy, z))

    def width_at(self, z: float, band: float = 0.018) -> tuple[float, float, float]:
        verts = [vert.co for vert in self.body.data.vertices if abs(vert.co.z - z) < band]
        if not verts:
            t = max(0.0, min(1.0, (z - self.skull.z) / max(self.skull_h, 1e-6)))
            shrink = 1.0 - 0.22 * t * t
            return self.rx * shrink, self.ry_b * shrink, self.ry_f * shrink
        rx = max(abs(vert.x - self.cx) for vert in verts) * 1.06
        ry_f = max(0.0, max(vert.y - self.cy for vert in verts)) * 1.06
        ry_b = max(0.0, max(self.cy - vert.y for vert in verts)) * 1.06
        return max(rx, 0.04), max(ry_b, 0.04), max(ry_f, 0.04)


def oval(cx: float, cy: float, z: float, rx: float, ry_b: float, ry_f: float,
         segs: int) -> list[Vector]:
    points = []
    step = TAU / segs
    for i in range(segs):
        angle = i * step
        cosine = math.cos(angle)
        sine = math.sin(angle)
        ry = ry_f if sine >= 0.0 else ry_b
        points.append(Vector((cx + rx * cosine, cy + ry * sine, z)))
    return points


def circle(fit: Fit, z: float, radius: float, segs: int = SEGS) -> list[Vector]:
    return oval(fit.cx, fit.cy, z, radius, radius, radius, segs)


def skin_ring(fit: Fit, z: float, pad: float = 1.0, segs: int = SEGS) -> list[Vector]:
    rx, ry_b, ry_f = fit.width_at(z)
    return oval(fit.cx, fit.cy, z, rx * pad, ry_b * pad, ry_f * pad, segs)


def tip(fit: Fit, z: float, segs: int) -> list[Vector]:
    return [fit.centre(z)] * segs


def offset_ring(points: list[Vector], delta: Vector) -> list[Vector]:
    return [point + delta for point in points]


def scale_ring(points: list[Vector], fit: Fit, scale_x: float, scale_y: float
               ) -> list[Vector]:
    out = []
    for point in points:
        out.append(Vector((
            fit.cx + (point.x - fit.cx) * scale_x,
            fit.cy + (point.y - fit.cy) * scale_y,
            point.z,
        )))
    return out


# --------------------------------------------------------------------------
# Mesh helpers
# --------------------------------------------------------------------------

def add_revolve(bm, fit: Fit, profile: list[tuple[float, float]], slot: int,
                segs: int = SEGS, cap_start: bool = False, cap_end: bool = False):
    """Loft a circular silhouette. profile is (radius, z) rings.

    End caps stay off by default. A start-cap on a brow-sized ring is a disk
    through the skull; only use one when the first ring is already above the
    scalp or smaller than a pom-pom.
    """
    rings = [circle(fit, z, radius, segs) for radius, z in profile]
    return add_loft(bm, rings, slot, cap_start=cap_start, cap_end=cap_end)


def add_wrap(bm, rings, slot):
    """Closed tube. The first ring is not capped, so the hole stays a hole."""
    if len(rings) < 2:
        return []
    return add_loft(bm, list(rings) + [rings[0]], slot, cap_start=False, cap_end=False)


def add_hollow_cap(bm, fit: Fit, z_lo: float, z_hi: float, inner_pad: float,
                   outer_pad: float, slot: int, segs: int = SEGS,
                   samples: int = 6, bulge: float = 0.0):
    """Thin shell that wraps the skull instead of filling it.

    The inner wall follows the scalp. A shallow lid just above the hair closes
    the axis so a vertical ray seats on the crown instead of flying through an
    open hole to a distant peak. Anything taller than the scalp is lofted on
    top of that lid, never down through the head.
    """
    count = max(3, samples)
    outer = []
    inner = []
    for i in range(count):
        t = i / (count - 1)
        z = z_lo + (fit.top - z_lo) * t
        swell = 1.0 + bulge * math.sin(t * math.pi)
        outer.append(skin_ring(fit, z, outer_pad * swell, segs))
        inner.append(skin_ring(fit, z, inner_pad, segs))
    add_loft(bm, outer, slot, cap_start=False, cap_end=False)
    add_loft(bm, list(reversed(inner)), slot, cap_start=False, cap_end=False)
    add_loft(bm, [outer[0], inner[0]], slot, cap_start=False, cap_end=False)
    add_loft(bm, [outer[-1], inner[-1]], slot, cap_start=False, cap_end=False)
    lid_mid = skin_ring(fit, fit.top + 0.003, max(inner_pad * 0.42, 0.18), segs)
    add_loft(bm, [inner[-1], lid_mid, tip(fit, fit.top + 0.008, segs)],
             slot, cap_start=False, cap_end=True)
    if z_hi > fit.top + 0.016:
        peak = [outer[-1]]
        steps = 5
        for i in range(1, steps):
            t = i / (steps - 1)
            z = fit.top + (z_hi - fit.top) * t
            radius = fit.r * outer_pad * max(0.10, 1.0 - 0.90 * t)
            peak.append(tip(fit, z, segs) if i == steps - 1
                        else circle(fit, z, radius, segs))
        add_loft(bm, peak, slot, cap_start=False, cap_end=True)


def add_brim(bm, fit: Fit, z: float, r_inner: float, r_outer: float,
             thick: float, slot: int, segs: int = SEGS,
             roll: float = 0.0, snap: float = 0.0):
    """Annular brim. roll lifts the sides; snap drops the front."""
    def shaped(radius, height):
        points = circle(fit, height, radius, segs)
        if roll == 0.0 and snap == 0.0:
            return points
        shaped_points = []
        for i, point in enumerate(points):
            angle = i * TAU / segs
            side = abs(math.cos(angle))
            front = max(0.0, math.sin(angle))
            lift = roll * side * side - snap * front
            shaped_points.append(Vector((point.x, point.y, point.z + lift)))
        return shaped_points

    add_wrap(bm, [
        shaped(max(r_inner, fit.r * 0.92), z),
        shaped(r_outer, z + roll * 0.15),
        shaped(r_outer, z + thick + roll * 0.15),
        shaped(max(r_inner, fit.r * 0.92), z + thick),
    ], slot)


def on_skin(fit: Fit, z: float, side: float, pad: float = 1.16,
            back: float = 0.0) -> Vector:
    rx, _ry_b, _ry_f = fit.width_at(z)
    return Vector((fit.cx + side * rx * pad, fit.cy - back, z))


def add_band(bm, fit: Fit, z_lo: float, z_hi: float, thick: float, slot: int,
             segs: int = SEGS, pad: float = 1.08):
    add_wrap(bm, [
        skin_ring(fit, z_lo, pad, segs),
        skin_ring(fit, z_hi, pad, segs),
        skin_ring(fit, z_hi, pad + thick / fit.rx, segs),
        skin_ring(fit, z_lo, pad + thick / fit.rx, segs),
    ], slot)


def paint_stripes(bm, slot_a: int, slot_b: int, bands: int = 6):
    for face in bm.faces:
        if face.material_index != slot_a:
            continue
        centre = face.calc_center_median()
        angle = math.atan2(centre.x, centre.y - 0.008)
        if int(((angle + math.pi) / TAU) * bands) % 2 == 1:
            face.material_index = slot_b


def materials(slug: str, parts: list[tuple]) -> list[str]:
    spec = {}
    for name, colour, roughness, metallic in parts:
        spec["Hat_{0}_{1}".format(slug, name)] = {
            "colour": colour + (1.0,),
            "roughness": roughness,
            "metallic": metallic,
        }
    return ensure_materials(spec)


def bind_to_head(obj: bpy.types.Object, body: bpy.types.Object,
                 rig: bpy.types.Object) -> None:
    obj.vertex_groups.clear()
    for group in body.vertex_groups:
        obj.vertex_groups.new(name=group.name)
    head = obj.vertex_groups.get("Head")
    if head is None:
        head = obj.vertex_groups.new(name="Head")
    head.add([vert.index for vert in obj.data.vertices], 1.0, "REPLACE")
    world = obj.matrix_world.copy()
    obj.parent = rig
    obj.matrix_world = world
    modifier = obj.modifiers.new("Armature", "ARMATURE")
    modifier.object = rig


def finish(name: str, bm, slots: list[str], body, rig, bevel: float = 0.0014):
    if bm.verts:
        bmesh.ops.remove_doubles(bm, verts=list(bm.verts), dist=0.0004)
    obj = new_object(
        name, bm, slots,
        bevel_width=bevel, bevel_segments=2, bevel_angle=36.0, smooth_angle=34.0)
    bind_to_head(obj, body, rig)
    return obj


def export_garment(garment: bpy.types.Object, rig: bpy.types.Object) -> str:
    path = os.path.join(APPAREL_DIR, garment.name + ".glb")
    os.makedirs(APPAREL_DIR, exist_ok=True)
    if bpy.context.object is not None and bpy.context.object.mode != "OBJECT":
        bpy.ops.object.mode_set(mode="OBJECT")
    view = bpy.context.view_layer
    for obj in view.objects:
        obj.select_set(False)
    for obj in (garment, rig):
        obj.hide_viewport = False
        obj.select_set(True)
    view.objects.active = rig
    bpy.ops.export_scene.gltf(
        filepath=path,
        export_format="GLB",
        use_selection=True,
        export_apply=True,
        export_skins=True,
        export_animations=False,
        export_yup=True,
    )
    return path


# --------------------------------------------------------------------------
# Hats
# --------------------------------------------------------------------------

def hat_party_hat(bm, fit: Fit) -> list[str]:
    slots = materials("party_hat", [
        ("paper", (0.92, 0.18, 0.48), 0.62, 0.0),
        ("stripe", (0.12, 0.72, 0.90), 0.58, 0.0),
        ("pom", (0.98, 0.88, 0.20), 0.48, 0.0),
    ])
    add_wrap(bm, [
        skin_ring(fit, fit.top - 0.003, 1.06, 32),
        skin_ring(fit, fit.top - 0.003, 1.16, 32),
        skin_ring(fit, fit.top + 0.010, 1.14, 32),
        skin_ring(fit, fit.top + 0.010, 1.04, 32),
    ], 2)
    z0 = fit.top + 0.008
    add_revolve(bm, fit, [
        (fit.r * 0.78, z0),
        (fit.r * 0.62, z0 + 0.04),
        (fit.r * 0.42, z0 + 0.10),
        (fit.r * 0.22, z0 + 0.18),
        (0.012, z0 + 0.26),
    ], 0, segs=32)
    paint_stripes(bm, 0, 1, bands=8)
    add_sphere(bm, fit.centre(z0 + 0.275), 0.022, 2, segments=16)
    return slots


def hat_bunny_ears(bm, fit: Fit) -> list[str]:
    slots = materials("bunny_ears", [
        ("fur", (0.96, 0.93, 0.88), 0.78, 0.0),
        ("inner", (0.95, 0.52, 0.62), 0.70, 0.0),
    ])
    add_band(bm, fit, fit.band_z - 0.012, fit.band_z + 0.016, 0.011, 0, segs=24)
    for side in (-1.0, 1.0):
        base = on_skin(fit, fit.band_z + 0.012, side, pad=1.16, back=0.006)
        path = [
            base,
            base + Vector((side * 0.018, -0.012, 0.08)),
            base + Vector((side * 0.028, -0.022, 0.16)),
            base + Vector((side * 0.012, -0.034, 0.215)),
        ]
        sections = [(0.028, 0.012), (0.026, 0.011), (0.020, 0.009), (0.007, 0.005)]
        add_path_loft(bm, path, sections, 0, wide_hint=(side, 0.0, 0.0),
                      segments=14, cap_start=True, cap_end=True)
        inner = [point + Vector((0.0, 0.006, 0.0)) for point in path]
        inner_sec = [(w * 0.62, t * 0.55) for w, t in sections]
        add_path_loft(bm, inner, inner_sec, 1, wide_hint=(side, 0.0, 0.0),
                      segments=12, cap_start=True, cap_end=True)
    return slots


def hat_top_hat(bm, fit: Fit) -> list[str]:
    slots = materials("top_hat", [
        ("felt", (0.07, 0.06, 0.07), 0.62, 0.0),
        ("band", (0.72, 0.58, 0.16), 0.42, 0.15),
    ])
    z0 = fit.brow_z + 0.012
    r = fit.r * 0.98
    add_brim(bm, fit, z0 - 0.006, r * 1.02, r + 0.075, 0.009, 0, segs=32)
    add_hollow_cap(bm, fit, z0, fit.top + 0.012, 1.06, 1.16, 0, segs=28,
                   samples=5, bulge=0.01)
    add_revolve(bm, fit, [
        (r * 0.96, fit.top + 0.006),
        (r * 0.94, fit.top + 0.08),
        (r * 0.96, fit.top + 0.14),
        (r * 1.00, fit.top + 0.168),
        (0.004, fit.top + 0.174),
    ], 0, segs=28)
    add_band(bm, fit, z0 + 0.010, z0 + 0.036, 0.012, 1, segs=28, pad=1.14)
    return slots


def hat_crown(bm, fit: Fit) -> list[str]:
    slots = materials("crown", [
        ("gold", (0.90, 0.70, 0.18), 0.32, 0.65),
        ("gem", (0.18, 0.42, 0.88), 0.18, 0.20),
    ])
    z0 = fit.band_z - 0.004
    r = fit.r * 1.08
    add_band(bm, fit, z0, z0 + 0.034, 0.012, 0, segs=32, pad=1.12)
    points = 7
    for i in range(points):
        angle = i * TAU / points - math.pi * 0.5
        tip_p = Vector((
            fit.cx + math.cos(angle) * r * 1.01,
            fit.cy + math.sin(angle) * r * 1.01,
            z0 + 0.155,
        ))
        left = Vector((
            fit.cx + math.cos(angle - 0.22) * r * 1.03,
            fit.cy + math.sin(angle - 0.22) * r * 1.03,
            z0 + 0.034,
        ))
        right = Vector((
            fit.cx + math.cos(angle + 0.22) * r * 1.03,
            fit.cy + math.sin(angle + 0.22) * r * 1.03,
            z0 + 0.034,
        ))
        mid = (left + right) * 0.5 + Vector((0.0, 0.0, 0.012))
        add_path_loft(bm, [left, mid, tip_p],
                      [(0.010, 0.006), (0.009, 0.005), (0.003, 0.003)],
                      0, wide_hint=(-math.sin(angle), math.cos(angle), 0.0),
                      segments=8)
        add_path_loft(bm, [right, mid, tip_p],
                      [(0.010, 0.006), (0.009, 0.005), (0.003, 0.003)],
                      0, wide_hint=(-math.sin(angle), math.cos(angle), 0.0),
                      segments=8)
        add_sphere(bm, tip_p + Vector((0.0, 0.0, 0.006)), 0.008, 1, segments=10)
    add_sphere(bm, fit.centre(z0 + 0.022) + Vector((0.0, r * 0.92, 0.0)),
               0.010, 1, segments=10)
    return slots


def hat_beanie(bm, fit: Fit) -> list[str]:
    slots = materials("beanie", [
        ("knit", (0.16, 0.50, 0.46), 0.82, 0.0),
        ("cuff", (0.12, 0.40, 0.38), 0.80, 0.0),
    ])
    add_band(bm, fit, fit.brow_z + 0.004, fit.brow_z + 0.028, 0.014, 1, segs=26)
    add_hollow_cap(bm, fit, fit.brow_z + 0.018, fit.top + 0.012, 1.06, 1.20, 0,
                   segs=26, samples=6, bulge=0.08)
    slouch = fit.centre(fit.top + 0.036) + Vector((0.020, -0.014, 0.0))
    add_sphere(bm, slouch, 0.042, 0, segments=14, scale=(1.15, 1.05, 0.55))
    return slots


def hat_cowboy_hat(bm, fit: Fit) -> list[str]:
    slots = materials("cowboy_hat", [
        ("felt", (0.52, 0.36, 0.20), 0.70, 0.0),
        ("band", (0.22, 0.14, 0.10), 0.58, 0.0),
    ])
    z0 = fit.brow_z
    r = fit.r * 0.98
    add_brim(bm, fit, z0 - 0.004, r * 1.02, r + 0.13, 0.010, 0, segs=36,
             roll=0.042, snap=0.012)
    add_hollow_cap(bm, fit, z0, fit.top + 0.012, 1.06, 1.16, 0, segs=28,
                   samples=5, bulge=0.02)
    pinched = [
        scale_ring(circle(fit, fit.top + 0.004, r * 0.82, 28), fit, 0.70, 1.08),
        scale_ring(circle(fit, fit.top + 0.028, r * 0.68, 28), fit, 0.62, 1.12),
        scale_ring(circle(fit, fit.top + 0.048, r * 0.74, 28), fit, 0.70, 1.06),
        tip(fit, fit.top + 0.056, 28),
    ]
    add_loft(bm, pinched, 0, cap_start=False, cap_end=True)
    add_band(bm, fit, z0 + 0.002, z0 + 0.022, 0.012, 1, segs=28, pad=1.14)
    return slots


def hat_propeller_cap(bm, fit: Fit) -> list[str]:
    slots = materials("propeller_cap", [
        ("wool", (0.82, 0.16, 0.14), 0.76, 0.0),
        ("button", (0.88, 0.82, 0.16), 0.40, 0.15),
        ("blade", (0.18, 0.20, 0.22), 0.45, 0.05),
    ])
    add_hollow_cap(bm, fit, fit.brow_z + 0.008, fit.top + 0.028, 1.06, 1.18, 0,
                   segs=26, samples=5, bulge=0.04)
    hub = fit.centre(fit.top + 0.030)
    add_sphere(bm, hub, 0.014, 1, segments=12)
    for side in (-1.0, 1.0):
        path = [
            hub,
            hub + Vector((side * 0.06, 0.0, 0.004)),
            hub + Vector((side * 0.12, 0.02, 0.002)),
        ]
        add_path_loft(bm, path, [(0.012, 0.003), (0.028, 0.0025), (0.018, 0.002)],
                      2, wide_hint=(0.0, 0.0, 1.0), segments=10)
    return slots


def hat_flower_crown(bm, fit: Fit) -> list[str]:
    slots = materials("flower_crown", [
        ("vine", (0.22, 0.48, 0.18), 0.72, 0.0),
        ("petal", (0.90, 0.42, 0.62), 0.58, 0.0),
        ("centre", (0.95, 0.82, 0.18), 0.48, 0.0),
    ])
    add_band(bm, fit, fit.band_z - 0.010, fit.band_z + 0.016, 0.012, 0, segs=28)
    count = 8
    for i in range(count):
        angle = i * TAU / count
        radial = Vector((math.cos(angle), math.sin(angle), 0.0))
        centre = fit.centre(fit.band_z + 0.028) + radial * (fit.r * 1.06)
        lean = radial * 0.010 + Vector((0.0, 0.0, 0.010))
        add_sphere(bm, centre + lean, 0.022 + 0.004 * (i % 3), 2, segments=10,
                   scale=(1.0, 1.0, 0.55))
        for p in range(5):
            pa = angle + p * TAU / 5.0
            petal = centre + Vector((math.cos(pa), math.sin(pa), 0.25)) * 0.026
            add_sphere(bm, petal + Vector((0.0, 0.0, 0.006)), 0.016, 1,
                       segments=8, scale=(1.35, 0.70, 0.45))
    return slots


def hat_antlers(bm, fit: Fit) -> list[str]:
    slots = materials("antlers", [
        ("horn", (0.42, 0.26, 0.14), 0.55, 0.0),
        ("band", (0.28, 0.18, 0.12), 0.68, 0.0),
    ])
    add_band(bm, fit, fit.band_z - 0.012, fit.band_z + 0.016, 0.012, 1, segs=22)
    for side in (-1.0, 1.0):
        root = on_skin(fit, fit.band_z + 0.012, side, pad=1.16, back=0.010)
        main = [
            root,
            root + Vector((side * 0.02, -0.02, 0.07)),
            root + Vector((side * 0.05, -0.04, 0.14)),
            root + Vector((side * 0.08, -0.05, 0.20)),
            root + Vector((side * 0.07, -0.06, 0.26)),
        ]
        add_path_loft(bm, main,
                      [(0.016, 0.014), (0.014, 0.012), (0.011, 0.010),
                       (0.008, 0.007), (0.004, 0.004)],
                      0, wide_hint=(0.0, 1.0, 0.0), segments=10)
        branch_a = [
            main[1],
            main[1] + Vector((side * 0.04, 0.01, 0.05)),
            main[1] + Vector((side * 0.06, 0.02, 0.09)),
        ]
        add_path_loft(bm, branch_a, [(0.010, 0.009), (0.007, 0.006), (0.003, 0.003)],
                      0, wide_hint=(0.0, 1.0, 0.0), segments=8)
        branch_b = [
            main[2],
            main[2] + Vector((side * -0.01, 0.03, 0.05)),
            main[2] + Vector((side * -0.02, 0.04, 0.09)),
        ]
        add_path_loft(bm, branch_b, [(0.009, 0.008), (0.006, 0.005), (0.003, 0.003)],
                      0, wide_hint=(0.0, 1.0, 0.0), segments=8)
    return slots


def hat_halo(bm, fit: Fit) -> list[str]:
    slots = materials("halo", [
        ("gold", (0.98, 0.84, 0.32), 0.28, 0.55),
    ])
    z = fit.top + 0.055
    r = fit.r * 0.78
    tube = 0.011
    rings = []
    for i in range(SEGS):
        angle = i * TAU / SEGS
        centre = Vector((
            fit.cx + math.cos(angle) * r,
            fit.cy + math.sin(angle) * r,
            z,
        ))
        tangent = Vector((-math.sin(angle), math.cos(angle), 0.0))
        normal = Vector((0.0, 0.0, 1.0))
        wide = tangent.cross(normal)
        rings.append(place_ring(centre, wide * tube, normal * tube, circle_profile(10)))
    vert_rings = []
    for points in rings:
        vert_rings.append([bm.verts.new(point) for point in points])
    for lower, upper in zip(vert_rings, vert_rings[1:] + [vert_rings[0]]):
        count = len(lower)
        for i in range(count):
            j = (i + 1) % count
            face = bm.faces.new([lower[i], lower[j], upper[j], upper[i]])
            face.material_index = 0
    return slots


def hat_wizard_hat(bm, fit: Fit) -> list[str]:
    slots = materials("wizard_hat", [
        ("cloth", (0.28, 0.14, 0.48), 0.72, 0.0),
        ("band", (0.82, 0.66, 0.16), 0.40, 0.20),
        ("buckle", (0.90, 0.78, 0.22), 0.32, 0.55),
    ])
    z0 = fit.brow_z
    r = fit.r * 1.04
    add_brim(bm, fit, z0 - 0.004, r * 1.02, r + 0.08, 0.010, 0, segs=32)
    add_hollow_cap(bm, fit, z0, fit.top + 0.012, 1.06, 1.18, 0, segs=26,
                   samples=5, bulge=0.02)
    rings = []
    height = 0.28
    for i in range(8):
        t = i / 7.0
        radius = r * (0.92 - 0.84 * t ** 0.85)
        bend = Vector((0.0, -0.018, 0.0)) * (t ** 1.6) * 8.0
        rings.append(offset_ring(
            circle(fit, fit.top + 0.006 + height * t, max(radius, 0.008), 26), bend))
    rings.append(offset_ring(tip(fit, fit.top + height + 0.016, 26),
                             Vector((0.0, -0.085, 0.0))))
    add_loft(bm, rings, 0, cap_start=False, cap_end=True)
    add_band(bm, fit, z0 + 0.004, z0 + 0.028, 0.012, 1, segs=26, pad=1.14)
    buckle = fit.centre(z0 + 0.018) + Vector((0.0, r * 1.05, 0.0))
    add_sphere(bm, buckle, 0.012, 2, segments=10, scale=(1.2, 0.45, 1.0))
    return slots


def hat_sombrero(bm, fit: Fit) -> list[str]:
    slots = materials("sombrero", [
        ("straw", (0.78, 0.60, 0.26), 0.74, 0.0),
        ("trim", (0.72, 0.12, 0.10), 0.55, 0.0),
    ])
    z0 = fit.brow_z - 0.006
    r = fit.r * 0.98
    add_brim(bm, fit, z0, r * 1.04, r + 0.20, 0.011, 0, segs=36, roll=0.055)
    add_hollow_cap(bm, fit, z0 + 0.008, fit.top + 0.012, 1.06, 1.16, 0, segs=28,
                   samples=5, bulge=0.03)
    add_revolve(bm, fit, [
        (r * 0.90, fit.top + 0.004),
        (r * 0.72, fit.top + 0.028),
        (r * 0.78, fit.top + 0.048),
        (0.01, fit.top + 0.056),
    ], 0, segs=28)
    add_band(bm, fit, z0 + 0.008, z0 + 0.030, 0.012, 1, segs=28, pad=1.14)
    add_wrap(bm, [
        circle(fit, z0 + 0.008, r + 0.188, 36),
        circle(fit, z0 + 0.018, r + 0.200, 36),
        circle(fit, z0 + 0.022, r + 0.196, 36),
        circle(fit, z0 + 0.012, r + 0.184, 36),
    ], 1)
    return slots


def hat_newsboy_cap(bm, fit: Fit) -> list[str]:
    slots = materials("newsboy_cap", [
        ("tweed", (0.28, 0.34, 0.26), 0.78, 0.0),
        ("button", (0.18, 0.16, 0.12), 0.50, 0.05),
    ])
    z0 = fit.brow_z + 0.006
    visor_path = []
    for i in range(7):
        t = i / 6.0
        angle = math.radians(-55 + 110 * t)
        visor_path.append(Vector((
            fit.cx + math.sin(angle) * fit.r * 1.16,
            fit.cy + math.cos(angle) * fit.r * 1.10,
            z0 - 0.004 - 0.010 * math.cos(angle * 0.4),
        )))
    add_path_loft(bm, visor_path,
                  [(0.018, 0.004)] * 7, 0, wide_hint=(0.0, 0.0, 1.0), segments=8)
    add_hollow_cap(bm, fit, z0, fit.top + 0.016, 1.06, 1.20, 0, segs=24,
                   samples=5, bulge=0.08)
    add_sphere(bm, fit.centre(fit.top + 0.018), 0.010, 1, segments=10)
    return slots


def hat_helmet(bm, fit: Fit) -> list[str]:
    slots = materials("helmet", [
        ("steel", (0.42, 0.45, 0.50), 0.32, 0.55),
        ("ridge", (0.58, 0.60, 0.64), 0.28, 0.60),
    ])
    add_hollow_cap(bm, fit, fit.brow_z, fit.top + 0.042, 1.06, 1.20, 0,
                   segs=28, samples=6, bulge=0.02)
    crest = [
        Vector((fit.cx, fit.cy - fit.r * 0.15, fit.top + 0.012)),
        Vector((fit.cx, fit.cy, fit.top + 0.048)),
        Vector((fit.cx, fit.cy + fit.r * 0.12, fit.top + 0.016)),
    ]
    add_path_loft(bm, crest, [(0.010, 0.008), (0.012, 0.010), (0.008, 0.006)],
                  1, wide_hint=(1.0, 0.0, 0.0), segments=8)
    add_brim(bm, fit, fit.brow_z - 0.004, fit.r * 1.04, fit.r * 1.14, 0.008, 0,
             segs=28, snap=0.006)
    return slots


def hat_pirate_hat(bm, fit: Fit) -> list[str]:
    slots = materials("pirate_hat", [
        ("felt", (0.07, 0.06, 0.06), 0.64, 0.0),
        ("trim", (0.62, 0.12, 0.10), 0.50, 0.0),
    ])
    z0 = fit.brow_z + 0.004
    r = fit.r * 1.08
    corners = (math.pi * 0.5, math.pi * 0.5 + TAU / 3.0, math.pi * 0.5 + 2.0 * TAU / 3.0)

    def tricorne(radius, height, lift):
        points = []
        for i in range(32):
            angle = i * TAU / 32
            nearest = min(abs((angle - corner + math.pi) % TAU - math.pi)
                          for corner in corners)
            rise = lift * max(0.0, 1.0 - nearest / 0.70) ** 1.4 * 1.15
            points.append(Vector((
                fit.cx + math.cos(angle) * radius,
                fit.cy + math.sin(angle) * radius,
                height + rise,
            )))
        return points

    add_hollow_cap(bm, fit, z0, fit.top + 0.012, 1.06, 1.16, 0, segs=24,
                   samples=5, bulge=0.02)
    add_wrap(bm, [
        tricorne(max(r * 1.06, fit.r * 1.08), z0, 0.0),
        tricorne(r * 1.16, z0 + 0.004, 0.018),
        tricorne(r * 1.22, z0 + 0.012, 0.070),
        tricorne(r * 1.14, z0 + 0.020, 0.078),
        tricorne(max(r * 1.06, fit.r * 1.08), z0 + 0.018, 0.010),
    ], 0)
    add_loft(bm, [
        tricorne(r * 1.20, z0 + 0.014, 0.072),
        tricorne(r * 1.22, z0 + 0.018, 0.076),
    ], 1, cap_start=False, cap_end=False)
    return slots


def hat_chef_toque(bm, fit: Fit) -> list[str]:
    slots = materials("chef_toque", [
        ("linen", (0.96, 0.96, 0.93), 0.78, 0.0),
        ("band", (0.90, 0.90, 0.88), 0.70, 0.0),
    ])
    z0 = fit.brow_z + 0.004
    add_band(bm, fit, z0, z0 + 0.022, 0.012, 1, segs=26)
    add_hollow_cap(bm, fit, z0 + 0.018, fit.top + 0.010, 1.06, 1.16, 0, segs=26,
                   samples=4, bulge=0.02)
    rings = []
    for i in range(8):
        t = i / 7.0
        z = fit.top + 0.006 + 0.16 * t
        puff = 0.88 + 0.28 * math.sin(t * math.pi)
        if t > 0.82:
            puff *= 0.72
        pts = []
        for s in range(28):
            angle = s * TAU / 28
            pleat = 1.0 + 0.07 * math.sin(angle * 8.0)
            radius = fit.r * puff * pleat
            pts.append(Vector((
                fit.cx + math.cos(angle) * radius,
                fit.cy + math.sin(angle) * radius,
                z + 0.008 * math.sin(angle * 8.0) * t,
            )))
        rings.append(pts)
    rings.append(circle(fit, fit.top + 0.178, fit.r * 0.42, 28))
    rings.append(tip(fit, fit.top + 0.192, 28))
    add_loft(bm, rings, 0, cap_start=False, cap_end=True)
    return slots


def hat_jester_hat(bm, fit: Fit) -> list[str]:
    slots = materials("jester_hat", [
        ("violet", (0.42, 0.10, 0.52), 0.62, 0.0),
        ("gold", (0.86, 0.68, 0.14), 0.40, 0.18),
        ("bell", (0.90, 0.76, 0.18), 0.28, 0.55),
    ])
    add_hollow_cap(bm, fit, fit.brow_z + 0.006, fit.top + 0.012, 1.06, 1.16, 0,
                   segs=22, samples=4, bulge=0.03)
    tips = [
        Vector((0.11, 0.02, 0.20)),
        Vector((-0.10, 0.04, 0.18)),
        Vector((0.01, -0.12, 0.16)),
    ]
    for index, tip_off in enumerate(tips):
        slot = index % 2
        root = fit.centre(fit.top + 0.016)
        path = [
            root,
            root + tip_off * 0.35 + Vector((0.0, 0.0, 0.02)),
            root + tip_off * 0.70 + Vector((0.0, 0.0, -0.01)),
            root + tip_off + Vector((0.0, 0.0, -0.04)),
        ]
        add_path_loft(bm, path,
                      [(0.024, 0.016), (0.020, 0.014), (0.012, 0.010), (0.005, 0.005)],
                      slot, wide_hint=(1.0, 0.0, 0.0), segments=12)
        add_sphere(bm, path[-1], 0.014, 2, segments=10)
    return slots


def hat_mushroom_cap(bm, fit: Fit) -> list[str]:
    slots = materials("mushroom_cap", [
        ("cap", (0.80, 0.14, 0.12), 0.68, 0.0),
        ("spot", (0.96, 0.94, 0.90), 0.72, 0.0),
        ("gills", (0.90, 0.82, 0.62), 0.78, 0.0),
    ])
    z0 = fit.brow_z + 0.02
    add_hollow_cap(bm, fit, z0, fit.top + 0.012, 1.06, 1.18, 0, segs=28,
                   samples=5, bulge=0.04)
    add_loft(bm, [
        circle(fit, fit.top + 0.006, fit.r * 1.16, 32),
        circle(fit, fit.top + 0.018, fit.r * 1.40, 32),
        circle(fit, fit.top + 0.036, fit.r * 1.22, 32),
        circle(fit, fit.top + 0.050, fit.r * 0.62, 32),
        tip(fit, fit.top + 0.058, 32),
    ], 0, cap_start=False, cap_end=True)
    add_wrap(bm, [
        circle(fit, fit.top + 0.004, fit.r * 1.18, 28),
        circle(fit, fit.top + 0.014, fit.r * 1.38, 28),
        circle(fit, fit.top + 0.020, fit.r * 1.36, 28),
        circle(fit, fit.top + 0.008, fit.r * 1.16, 28),
    ], 2)
    spots = [
        (0.06, 0.04, 0.024, 0.018),
        (-0.07, -0.02, 0.028, 0.014),
        (0.00, -0.08, 0.020, 0.016),
        (0.08, -0.05, 0.018, 0.012),
        (-0.04, 0.08, 0.026, 0.013),
        (0.03, 0.09, 0.016, 0.011),
    ]
    for dx, dy, dz, radius in spots:
        add_sphere(bm, Vector((fit.cx + dx, fit.cy + dy, fit.top + dz)), radius, 1,
                   segments=10, scale=(1.2, 1.2, 0.45))
    return slots


def hat_antennae(bm, fit: Fit) -> list[str]:
    slots = materials("antennae", [
        ("band", (0.42, 0.44, 0.48), 0.40, 0.35),
        ("spring", (0.55, 0.58, 0.62), 0.35, 0.40),
        ("bulb", (0.28, 0.95, 0.22), 0.30, 0.05),
    ])
    add_band(bm, fit, fit.band_z - 0.010, fit.band_z + 0.016, 0.012, 0, segs=22)
    for side in (-1.0, 1.0):
        root = on_skin(fit, fit.band_z + 0.010, side, pad=1.16)
        path = []
        for i in range(9):
            t = i / 8.0
            path.append(root + Vector((
                side * 0.01 * t,
                0.012 * math.sin(t * TAU * 2.2),
                0.16 * t,
            )))
        add_path_loft(bm, path, [(0.006, 0.006)] * 9, 1,
                      wide_hint=(1.0, 0.0, 0.0), segments=8)
        add_sphere(bm, path[-1], 0.016, 2, segments=12)
    return slots


def hat_visor(bm, fit: Fit) -> list[str]:
    slots = materials("visor", [
        ("foam", (0.14, 0.78, 0.32), 0.62, 0.0),
        ("strap", (0.12, 0.12, 0.13), 0.55, 0.0),
    ])
    add_band(bm, fit, fit.brow_z - 0.008, fit.brow_z + 0.018, 0.012, 1, segs=24)
    path = []
    for i in range(9):
        t = i / 8.0
        angle = math.radians(-62 + 124 * t)
        path.append(Vector((
            fit.cx + math.sin(angle) * fit.r * 1.18,
            fit.cy + math.cos(angle) * fit.r * 1.08,
            fit.brow_z + 0.004 - 0.018 * math.cos((t - 0.5) * math.pi) * 0.15,
        )))
    add_path_loft(bm, path, [(0.028, 0.006)] * 9, 0,
                  wide_hint=(0.0, 0.0, 1.0), segments=10)
    return slots


def hat_bow(bm, fit: Fit) -> list[str]:
    slots = materials("bow", [
        ("silk", (0.74, 0.10, 0.20), 0.42, 0.0),
        ("clip", (0.55, 0.42, 0.16), 0.36, 0.35),
    ])
    add_wrap(bm, [
        skin_ring(fit, fit.top - 0.002, 1.06, 16),
        skin_ring(fit, fit.top - 0.002, 1.14, 16),
        skin_ring(fit, fit.top + 0.010, 1.12, 16),
        skin_ring(fit, fit.top + 0.010, 1.04, 16),
    ], 1)
    knot = fit.centre(fit.top + 0.022) + Vector((0.0, -fit.r * 0.22, 0.012))
    add_sphere(bm, knot, 0.018, 0, segments=12, scale=(0.85, 0.70, 0.80))
    for side in (-1.0, 1.0):
        loop = [
            knot,
            knot + Vector((side * 0.05, 0.012, 0.016)),
            knot + Vector((side * 0.09, 0.00, 0.006)),
            knot + Vector((side * 0.05, -0.012, -0.006)),
            knot,
        ]
        add_path_loft(bm, loop,
                      [(0.016, 0.008), (0.032, 0.011), (0.034, 0.011),
                       (0.024, 0.008), (0.014, 0.006)],
                      0, wide_hint=(0.0, 0.0, 1.0), segments=12,
                      cap_start=False, cap_end=False)
        tail = [
            knot + Vector((side * 0.012, -0.016, -0.004)),
            knot + Vector((side * 0.038, -0.040, -0.02)),
            knot + Vector((side * 0.052, -0.062, -0.04)),
        ]
        add_path_loft(bm, tail, [(0.016, 0.004), (0.013, 0.003), (0.008, 0.002)],
                      0, wide_hint=(0.0, 0.0, 1.0), segments=8)
    add_sphere(bm, knot + Vector((0.0, 0.0, -0.006)), 0.008, 1, segments=8)
    return slots


def hat_horned_helm(bm, fit: Fit) -> list[str]:
    slots = materials("horned_helm", [
        ("iron", (0.32, 0.33, 0.36), 0.38, 0.50),
        ("horn", (0.88, 0.84, 0.74), 0.48, 0.0),
    ])
    add_hollow_cap(bm, fit, fit.brow_z - 0.006, fit.top + 0.038, 1.06, 1.20, 0,
                   segs=26, samples=6, bulge=0.015)
    add_brim(bm, fit, fit.brow_z - 0.010, fit.r * 1.04, fit.r * 1.12, 0.010, 0,
             segs=26)
    for side in (-1.0, 1.0):
        root = Vector((fit.cx + side * fit.r * 0.85, fit.cy - 0.01, fit.brow_z + 0.02))
        path = [
            root,
            root + Vector((side * 0.05, -0.02, 0.06)),
            root + Vector((side * 0.10, -0.01, 0.12)),
            root + Vector((side * 0.12, 0.02, 0.16)),
        ]
        add_path_loft(bm, path,
                      [(0.018, 0.016), (0.014, 0.012), (0.009, 0.008), (0.004, 0.004)],
                      1, wide_hint=(0.0, 0.0, 1.0), segments=10)
    return slots


def hat_fedora(bm, fit: Fit) -> list[str]:
    slots = materials("fedora", [
        ("felt", (0.28, 0.17, 0.11), 0.68, 0.0),
        ("band", (0.12, 0.08, 0.06), 0.55, 0.0),
    ])
    z0 = fit.brow_z + 0.006
    r = fit.r * 0.98
    add_brim(bm, fit, z0 - 0.005, r * 1.02, r + 0.068, 0.009, 0, segs=32,
             roll=0.010, snap=0.016)
    add_hollow_cap(bm, fit, z0, fit.top + 0.012, 1.06, 1.16, 0, segs=28,
                   samples=5, bulge=0.02)
    pinched = [
        scale_ring(circle(fit, fit.top + 0.004, r * 0.82, 28), fit, 0.72, 1.10),
        scale_ring(circle(fit, fit.top + 0.028, r * 0.70, 28), fit, 0.64, 1.12),
        scale_ring(circle(fit, fit.top + 0.048, r * 0.76, 28), fit, 0.70, 1.08),
        tip(fit, fit.top + 0.056, 28),
    ]
    add_loft(bm, pinched, 0, cap_start=False, cap_end=True)
    add_band(bm, fit, z0 + 0.002, z0 + 0.022, 0.012, 1, segs=26, pad=1.14)
    return slots


def hat_santa_hat(bm, fit: Fit) -> list[str]:
    slots = materials("santa_hat", [
        ("wool", (0.72, 0.07, 0.08), 0.78, 0.0),
        ("fur", (0.96, 0.95, 0.92), 0.82, 0.0),
    ])
    z0 = fit.brow_z + 0.004
    add_band(bm, fit, z0 - 0.004, z0 + 0.028, 0.016, 1, segs=28, pad=1.12)
    add_hollow_cap(bm, fit, z0 + 0.020, fit.top + 0.012, 1.06, 1.18, 0, segs=26,
                   samples=4, bulge=0.03)
    root = fit.centre(fit.top + 0.024)
    path = [
        root,
        root + Vector((0.02, -0.03, 0.06)),
        root + Vector((0.06, -0.08, 0.10)),
        root + Vector((0.12, -0.10, 0.06)),
        root + Vector((0.16, -0.08, 0.02)),
    ]
    add_path_loft(bm, path,
                  [(0.048, 0.022), (0.042, 0.020), (0.032, 0.016),
                   (0.020, 0.012), (0.010, 0.010)],
                  0, wide_hint=(0.0, 1.0, 0.0), segments=16)
    add_sphere(bm, path[-1], 0.024, 1, segments=14)
    return slots


def hat_cat_ears(bm, fit: Fit) -> list[str]:
    slots = materials("cat_ears", [
        ("fur", (0.10, 0.08, 0.08), 0.76, 0.0),
        ("inner", (0.94, 0.52, 0.62), 0.68, 0.0),
    ])
    add_band(bm, fit, fit.band_z - 0.012, fit.band_z + 0.016, 0.012, 0, segs=24)
    for side in (-1.0, 1.0):
        base = on_skin(fit, fit.band_z + 0.010, side, pad=1.16, back=0.004)
        path = [
            base + Vector((-side * 0.016, 0.004, 0.0)),
            base + Vector((side * 0.006, -0.008, 0.07)),
            base + Vector((side * 0.014, -0.012, 0.125)),
        ]
        add_path_loft(bm, path,
                      [(0.026, 0.010), (0.018, 0.008), (0.004, 0.003)],
                      0, wide_hint=(side, 0.0, 0.0), segments=12)
        inner = [point + Vector((0.0, 0.005, 0.0)) for point in path]
        add_path_loft(bm, inner,
                      [(0.016, 0.005), (0.011, 0.004), (0.003, 0.002)],
                      1, wide_hint=(side, 0.0, 0.0), segments=10)
    return slots


def hat_beret(bm, fit: Fit) -> list[str]:
    slots = materials("beret", [
        ("wool", (0.18, 0.16, 0.42), 0.80, 0.0),
        ("stem", (0.10, 0.08, 0.12), 0.55, 0.0),
    ])
    add_hollow_cap(bm, fit, fit.brow_z + 0.018, fit.top + 0.010, 1.06, 1.18, 0,
                   segs=26, samples=4, bulge=0.04)
    slouch = Vector((0.022, -0.010, 0.0))
    disk = []
    for i in range(5):
        t = i / 4.0
        z = fit.top + 0.004 + 0.018 * math.sin(t * math.pi)
        pad = 1.22 + 0.28 * math.sin(t * math.pi)
        disk.append(offset_ring(skin_ring(fit, min(fit.top, z), pad, 26), slouch * t))
    disk.append(offset_ring(tip(fit, fit.top + 0.028, 26), slouch * 1.05))
    add_loft(bm, disk, 0, cap_start=False, cap_end=True)
    add_sphere(bm, fit.centre(fit.top + 0.032) + slouch * 0.4, 0.008, 1, segments=8)
    return slots


def hat_baseball_cap(bm, fit: Fit) -> list[str]:
    slots = materials("baseball_cap", [
        ("cloth", (0.14, 0.32, 0.62), 0.70, 0.0),
        ("button", (0.10, 0.22, 0.48), 0.45, 0.05),
    ])
    add_hollow_cap(bm, fit, fit.brow_z + 0.008, fit.top + 0.016, 1.06, 1.18, 0,
                   segs=24, samples=5, bulge=0.04)
    path = []
    for i in range(8):
        t = i / 7.0
        angle = math.radians(-58 + 116 * t)
        path.append(Vector((
            fit.cx + math.sin(angle) * fit.r * 1.20,
            fit.cy + math.cos(angle) * fit.r * 1.14,
            fit.brow_z + 0.002 - 0.016 * math.cos((t - 0.5) * math.pi) * 0.2,
        )))
    add_path_loft(bm, path, [(0.026, 0.005)] * 8, 0,
                  wide_hint=(0.0, 0.0, 1.0), segments=10)
    add_sphere(bm, fit.centre(fit.top + 0.018), 0.009, 1, segments=10)
    return slots


def hat_sun_hat(bm, fit: Fit) -> list[str]:
    slots = materials("sun_hat", [
        ("straw", (0.86, 0.74, 0.38), 0.76, 0.0),
        ("ribbon", (0.62, 0.18, 0.28), 0.52, 0.0),
    ])
    z0 = fit.brow_z + 0.004
    add_brim(bm, fit, z0 - 0.006, fit.r * 1.06, fit.r + 0.18, 0.010, 0, segs=36,
             roll=0.028)
    add_hollow_cap(bm, fit, z0, fit.top + 0.014, 1.06, 1.16, 0, segs=26,
                   samples=5, bulge=0.03)
    add_band(bm, fit, z0 + 0.006, z0 + 0.024, 0.012, 1, segs=26, pad=1.14)
    return slots


def hat_hard_hat(bm, fit: Fit) -> list[str]:
    slots = materials("hard_hat", [
        ("shell", (0.90, 0.72, 0.10), 0.42, 0.08),
        ("ridge", (0.78, 0.62, 0.08), 0.38, 0.10),
    ])
    add_hollow_cap(bm, fit, fit.brow_z - 0.002, fit.top + 0.046, 1.06, 1.22, 0,
                   segs=26, samples=6, bulge=0.04)
    add_brim(bm, fit, fit.brow_z - 0.008, fit.r * 1.06, fit.r * 1.18, 0.009, 0,
             segs=26, snap=0.010)
    crest = [
        Vector((fit.cx, fit.cy - fit.r * 0.10, fit.top + 0.010)),
        Vector((fit.cx, fit.cy, fit.top + 0.052)),
        Vector((fit.cx, fit.cy + fit.r * 0.08, fit.top + 0.014)),
    ]
    add_path_loft(bm, crest, [(0.012, 0.008), (0.014, 0.010), (0.010, 0.006)],
                  1, wide_hint=(1.0, 0.0, 0.0), segments=8)
    return slots


def hat_ushanka(bm, fit: Fit) -> list[str]:
    slots = materials("ushanka", [
        ("fur", (0.42, 0.28, 0.16), 0.84, 0.0),
        ("flap", (0.36, 0.24, 0.14), 0.82, 0.0),
    ])
    add_hollow_cap(bm, fit, fit.brow_z + 0.004, fit.top + 0.028, 1.06, 1.24, 0,
                   segs=24, samples=5, bulge=0.06)
    add_band(bm, fit, fit.brow_z - 0.002, fit.brow_z + 0.022, 0.016, 0, segs=24,
             pad=1.14)
    for side in (-1.0, 1.0):
        flap = [
            Vector((fit.cx + side * fit.r * 0.92, fit.cy + 0.02, fit.brow_z + 0.02)),
            Vector((fit.cx + side * fit.r * 1.05, fit.cy + 0.01, fit.brow_z - 0.02)),
            Vector((fit.cx + side * fit.r * 1.00, fit.cy - 0.01, fit.brow_z - 0.08)),
        ]
        add_path_loft(bm, flap, [(0.034, 0.010), (0.038, 0.012), (0.028, 0.008)],
                      1, wide_hint=(0.0, 1.0, 0.0), segments=10)
    return slots


def hat_turban(bm, fit: Fit) -> list[str]:
    slots = materials("turban", [
        ("cloth", (0.72, 0.16, 0.18), 0.68, 0.0),
        ("jewel", (0.18, 0.55, 0.82), 0.22, 0.25),
    ])
    add_hollow_cap(bm, fit, fit.brow_z + 0.010, fit.top + 0.012, 1.06, 1.18, 0,
                   segs=24, samples=4, bulge=0.03)
    for i, (z_off, pad, thick) in enumerate((
            (0.000, 1.16, 0.018),
            (0.022, 1.22, 0.016),
            (0.044, 1.18, 0.014),
    )):
        add_band(bm, fit, fit.brow_z + 0.008 + z_off,
                 fit.brow_z + 0.008 + z_off + thick, 0.014, 0, segs=22, pad=pad)
    add_sphere(bm, fit.centre(fit.band_z + 0.012) + Vector((0.0, fit.r * 1.12, 0.0)),
               0.014, 1, segments=10)
    return slots


def hat_devil_horns(bm, fit: Fit) -> list[str]:
    slots = materials("devil_horns", [
        ("horn", (0.42, 0.06, 0.08), 0.48, 0.0),
        ("band", (0.12, 0.08, 0.08), 0.62, 0.0),
    ])
    add_band(bm, fit, fit.band_z - 0.012, fit.band_z + 0.016, 0.012, 1, segs=22)
    for side in (-1.0, 1.0):
        root = on_skin(fit, fit.band_z + 0.012, side, pad=1.16, back=0.008)
        path = [
            root,
            root + Vector((side * 0.03, -0.01, 0.06)),
            root + Vector((side * 0.06, 0.00, 0.12)),
            root + Vector((side * 0.05, 0.02, 0.17)),
        ]
        add_path_loft(bm, path,
                      [(0.016, 0.014), (0.013, 0.011), (0.008, 0.007), (0.003, 0.003)],
                      0, wide_hint=(0.0, 1.0, 0.0), segments=10)
    return slots


def hat_unicorn_horn(bm, fit: Fit) -> list[str]:
    slots = materials("unicorn_horn", [
        ("horn", (0.96, 0.90, 0.72), 0.36, 0.15),
        ("band", (0.78, 0.42, 0.72), 0.58, 0.0),
    ])
    add_band(bm, fit, fit.band_z - 0.006, fit.band_z + 0.012, 0.009, 1, segs=22)
    add_wrap(bm, [
        skin_ring(fit, fit.top - 0.002, 1.06, 16),
        skin_ring(fit, fit.top - 0.002, 1.14, 16),
        skin_ring(fit, fit.top + 0.010, 1.12, 16),
        skin_ring(fit, fit.top + 0.010, 1.04, 16),
    ], 1)
    root = fit.centre(fit.top + 0.014) + Vector((0.0, fit.r * 0.18, 0.0))
    path = []
    for i in range(8):
        t = i / 7.0
        twist = Vector((math.sin(t * TAU * 2.2) * 0.008, 0.0, 0.0))
        path.append(root + Vector((0.0, 0.012 * t, 0.14 * t)) + twist)
    add_path_loft(bm, path,
                  [(0.016, 0.016), (0.014, 0.014), (0.012, 0.012), (0.010, 0.010),
                   (0.008, 0.008), (0.006, 0.006), (0.004, 0.004), (0.002, 0.002)],
                  0, wide_hint=(1.0, 0.0, 0.0), segments=12)
    return slots


def hat_headphones(bm, fit: Fit) -> list[str]:
    slots = materials("headphones", [
        ("cup", (0.14, 0.14, 0.16), 0.42, 0.08),
        ("band", (0.22, 0.22, 0.24), 0.40, 0.10),
        ("pad", (0.18, 0.18, 0.20), 0.72, 0.0),
    ])
    add_band(bm, fit, fit.band_z - 0.012, fit.band_z + 0.016, 0.012, 1, segs=20,
             pad=1.10)
    arc = []
    height = fit.top - fit.band_z + 0.042
    for i in range(9):
        t = i / 8.0
        angle = math.radians(180.0 * t)
        arc.append(Vector((
            fit.cx + math.cos(angle) * fit.r * 1.22,
            fit.cy,
            fit.band_z + math.sin(angle) * height,
        )))
    add_path_loft(bm, arc, [(0.010, 0.006)] * 9, 1,
                  wide_hint=(0.0, 1.0, 0.0), segments=8)
    for side in (-1.0, 1.0):
        cup = Vector((fit.cx + side * fit.r * 1.16, fit.cy, fit.band_z + 0.004))
        add_sphere(bm, cup, 0.038, 0, segments=12, scale=(0.55, 0.90, 0.90))
        add_sphere(bm, cup + Vector((side * 0.012, 0.0, 0.0)), 0.032, 2,
                   segments=10, scale=(0.40, 0.95, 0.95))
    return slots


def hat_tiara(bm, fit: Fit) -> list[str]:
    slots = materials("tiara", [
        ("silver", (0.82, 0.84, 0.88), 0.28, 0.55),
        ("gem", (0.72, 0.18, 0.42), 0.18, 0.15),
    ])
    add_band(bm, fit, fit.band_z - 0.010, fit.band_z + 0.016, 0.012, 0, segs=28)
    points = 5
    for i in range(points):
        t = (i / (points - 1)) - 0.5
        angle = math.pi * 0.5 + t * 1.35
        height = 0.042 + 0.038 * math.cos(t * math.pi)
        tip_p = Vector((
            fit.cx + math.cos(angle) * fit.r * 1.10,
            fit.cy + math.sin(angle) * fit.r * 1.10,
            fit.band_z + height,
        ))
        base = Vector((
            fit.cx + math.cos(angle) * fit.r * 1.12,
            fit.cy + math.sin(angle) * fit.r * 1.12,
            fit.band_z + 0.014,
        ))
        add_path_loft(bm, [base, tip_p], [(0.008, 0.005), (0.003, 0.003)],
                      0, wide_hint=(-math.sin(angle), math.cos(angle), 0.0),
                      segments=6)
        add_sphere(bm, tip_p + Vector((0.0, 0.0, 0.004)), 0.006, 1, segments=8)
    return slots


def hat_bandana(bm, fit: Fit) -> list[str]:
    slots = materials("bandana", [
        ("cloth", (0.16, 0.42, 0.28), 0.74, 0.0),
        ("knot", (0.12, 0.34, 0.22), 0.70, 0.0),
    ])
    add_hollow_cap(bm, fit, fit.brow_z + 0.010, fit.top + 0.010, 1.06, 1.16, 0,
                   segs=24, samples=4, bulge=0.02)
    add_band(bm, fit, fit.brow_z + 0.004, fit.brow_z + 0.024, 0.012, 0, segs=24)
    knot = Vector((fit.cx, fit.cy - fit.r * 1.18, fit.brow_z + 0.008))
    add_sphere(bm, knot, 0.016, 1, segments=10, scale=(1.1, 0.8, 0.8))
    for side in (-1.0, 1.0):
        tail = [
            knot,
            knot + Vector((side * 0.03, -0.02, -0.02)),
            knot + Vector((side * 0.05, -0.04, -0.06)),
        ]
        add_path_loft(bm, tail, [(0.014, 0.004), (0.012, 0.003), (0.006, 0.002)],
                      0, wide_hint=(0.0, 0.0, 1.0), segments=8)
    return slots


def hat_rice_hat(bm, fit: Fit) -> list[str]:
    slots = materials("rice_hat", [
        ("straw", (0.70, 0.58, 0.28), 0.78, 0.0),
        ("band", (0.22, 0.16, 0.10), 0.62, 0.0),
    ])
    add_hollow_cap(bm, fit, fit.brow_z + 0.006, fit.top + 0.012, 1.06, 1.16, 0,
                   segs=28, samples=4, bulge=0.02)
    add_loft(bm, [
        circle(fit, fit.brow_z + 0.004, fit.r * 1.08, 32),
        circle(fit, fit.brow_z + 0.018, fit.r * 1.35, 32),
        circle(fit, fit.top + 0.010, fit.r * 0.85, 32),
        tip(fit, fit.top + 0.072, 32),
    ], 0, cap_start=False, cap_end=True)
    add_band(bm, fit, fit.brow_z + 0.008, fit.brow_z + 0.022, 0.010, 1, segs=26)
    return slots


def hat_laurel(bm, fit: Fit) -> list[str]:
    slots = materials("laurel", [
        ("leaf", (0.28, 0.52, 0.18), 0.70, 0.0),
        ("stem", (0.22, 0.36, 0.12), 0.68, 0.0),
    ])
    add_band(bm, fit, fit.band_z - 0.010, fit.band_z + 0.016, 0.012, 1, segs=28)
    for i in range(16):
        angle = i * TAU / 16.0
        side = 1.0 if i < 8 else -1.0
        centre = fit.centre(fit.band_z + 0.016) + Vector((
            math.cos(angle) * fit.r * 1.10,
            math.sin(angle) * fit.r * 1.10,
            0.006 * (i % 3),
        ))
        leaf = [
            centre,
            centre + Vector((math.cos(angle) * 0.012, math.sin(angle) * 0.012, 0.010)),
            centre + Vector((math.cos(angle + side * 0.25) * 0.028,
                             math.sin(angle + side * 0.25) * 0.028, 0.004)),
        ]
        add_path_loft(bm, leaf, [(0.010, 0.003), (0.014, 0.003), (0.004, 0.002)],
                      0, wide_hint=(0.0, 0.0, 1.0), segments=6)
    return slots


def hat_nightcap(bm, fit: Fit) -> list[str]:
    slots = materials("nightcap", [
        ("cloth", (0.28, 0.18, 0.52), 0.74, 0.0),
        ("trim", (0.92, 0.88, 0.72), 0.70, 0.0),
    ])
    add_band(bm, fit, fit.brow_z + 0.004, fit.brow_z + 0.024, 0.012, 1, segs=24)
    add_hollow_cap(bm, fit, fit.brow_z + 0.018, fit.top + 0.012, 1.06, 1.16, 0,
                   segs=24, samples=4, bulge=0.02)
    root = fit.centre(fit.top + 0.020)
    path = [
        root,
        root + Vector((0.03, -0.04, 0.06)),
        root + Vector((0.08, -0.08, 0.04)),
        root + Vector((0.12, -0.06, -0.01)),
    ]
    add_path_loft(bm, path,
                  [(0.040, 0.018), (0.028, 0.014), (0.016, 0.010), (0.006, 0.006)],
                  0, wide_hint=(0.0, 1.0, 0.0), segments=12)
    add_sphere(bm, path[-1], 0.016, 1, segments=12)
    return slots


def hat_deerstalker(bm, fit: Fit) -> list[str]:
    slots = materials("deerstalker", [
        ("tweed", (0.36, 0.32, 0.22), 0.78, 0.0),
        ("flap", (0.30, 0.26, 0.18), 0.76, 0.0),
    ])
    add_hollow_cap(bm, fit, fit.brow_z + 0.006, fit.top + 0.018, 1.06, 1.18, 0,
                   segs=24, samples=5, bulge=0.05)
    for sign, snap in ((1.0, 0.012), (-1.0, 0.008)):
        path = []
        for i in range(7):
            t = i / 6.0
            angle = math.radians(-50 + 100 * t)
            path.append(Vector((
                fit.cx + math.sin(angle) * fit.r * 1.14,
                fit.cy + sign * math.cos(angle) * fit.r * 1.08,
                fit.brow_z - snap * math.cos((t - 0.5) * math.pi) * 0.4,
            )))
        add_path_loft(bm, path, [(0.016, 0.004)] * 7, 0,
                      wide_hint=(0.0, 0.0, 1.0), segments=8)
    for side in (-1.0, 1.0):
        flap = [
            Vector((fit.cx + side * fit.r * 0.95, fit.cy, fit.brow_z + 0.016)),
            Vector((fit.cx + side * fit.r * 1.08, fit.cy, fit.brow_z - 0.01)),
            Vector((fit.cx + side * fit.r * 1.02, fit.cy, fit.brow_z - 0.06)),
        ]
        add_path_loft(bm, flap, [(0.028, 0.006), (0.030, 0.006), (0.020, 0.004)],
                      1, wide_hint=(0.0, 1.0, 0.0), segments=8)
    return slots


def hat_frog_hood(bm, fit: Fit) -> list[str]:
    slots = materials("frog_hood", [
        ("skin", (0.28, 0.62, 0.22), 0.72, 0.0),
        ("belly", (0.78, 0.86, 0.42), 0.74, 0.0),
        ("eye", (0.12, 0.12, 0.10), 0.40, 0.0),
    ])
    add_hollow_cap(bm, fit, fit.brow_z - 0.004, fit.top + 0.034, 1.06, 1.26, 0,
                   segs=24, samples=6, bulge=0.08)
    add_band(bm, fit, fit.brow_z - 0.006, fit.brow_z + 0.016, 0.012, 1, segs=22,
             pad=1.14)
    for side in (-1.0, 1.0):
        eye = Vector((fit.cx + side * 0.048, fit.cy + fit.r * 0.42, fit.top + 0.012))
        add_sphere(bm, eye, 0.026, 0, segments=12, scale=(1.0, 0.90, 0.85))
        add_sphere(bm, eye + Vector((0.0, 0.008, 0.004)), 0.012, 2, segments=8)
    return slots


def hat_rainbow(bm, fit: Fit) -> list[str]:
    slots = materials("rainbow", [
        ("red", (0.88, 0.16, 0.16), 0.55, 0.0),
        ("gold", (0.92, 0.72, 0.16), 0.52, 0.0),
        ("blue", (0.18, 0.42, 0.86), 0.50, 0.0),
    ])
    add_wrap(bm, [
        skin_ring(fit, fit.top - 0.002, 1.06, 18),
        skin_ring(fit, fit.top - 0.002, 1.14, 18),
        skin_ring(fit, fit.top + 0.010, 1.12, 18),
        skin_ring(fit, fit.top + 0.010, 1.04, 18),
    ], 1)
    for index, radius in enumerate((0.11, 0.095, 0.08)):
        arc = []
        for i in range(9):
            t = i / 8.0
            angle = math.radians(12 + 156 * t)
            arc.append(Vector((
                fit.cx + math.cos(angle) * radius,
                fit.cy - 0.01,
                fit.top + 0.012 + math.sin(angle) * radius * 0.85,
            )))
        add_path_loft(bm, arc, [(0.010, 0.006)] * 9, index,
                      wide_hint=(0.0, 1.0, 0.0), segments=8)
    return slots


def hat_paper_crown(bm, fit: Fit) -> list[str]:
    slots = materials("paper_crown", [
        ("paper", (0.92, 0.22, 0.28), 0.68, 0.0),
        ("dot", (0.96, 0.86, 0.20), 0.55, 0.0),
    ])
    z0 = fit.band_z - 0.004
    add_band(bm, fit, z0, z0 + 0.028, 0.010, 0, segs=28)
    points = 8
    for i in range(points):
        angle = i * TAU / points
        tip_p = Vector((
            fit.cx + math.cos(angle) * fit.r * 1.10,
            fit.cy + math.sin(angle) * fit.r * 1.10,
            z0 + 0.072,
        ))
        base = Vector((
            fit.cx + math.cos(angle) * fit.r * 1.12,
            fit.cy + math.sin(angle) * fit.r * 1.12,
            z0 + 0.028,
        ))
        add_path_loft(bm, [base, tip_p], [(0.012, 0.004), (0.002, 0.002)],
                      0, wide_hint=(-math.sin(angle), math.cos(angle), 0.0),
                      segments=6)
        add_sphere(bm, tip_p, 0.006, 1, segments=8)
    return slots


def hat_space_helmet(bm, fit: Fit) -> list[str]:
    slots = materials("space_helmet", [
        ("glass", (0.55, 0.72, 0.82), 0.18, 0.08),
        ("collar", (0.42, 0.44, 0.48), 0.36, 0.40),
    ])
    add_hollow_cap(bm, fit, fit.brow_z - 0.020, fit.top + 0.070, 1.08, 1.32, 0,
                   segs=26, samples=7, bulge=0.10)
    add_band(bm, fit, fit.brow_z - 0.022, fit.brow_z + 0.006, 0.016, 1, segs=24,
             pad=1.20)
    return slots


def hat_cake_hat(bm, fit: Fit) -> list[str]:
    slots = materials("cake_hat", [
        ("sponge", (0.92, 0.74, 0.48), 0.70, 0.0),
        ("icing", (0.94, 0.42, 0.58), 0.52, 0.0),
        ("candle", (0.96, 0.92, 0.82), 0.48, 0.0),
    ])
    add_wrap(bm, [
        skin_ring(fit, fit.top - 0.002, 1.06, 22),
        skin_ring(fit, fit.top - 0.002, 1.16, 22),
        skin_ring(fit, fit.top + 0.010, 1.14, 22),
        skin_ring(fit, fit.top + 0.010, 1.04, 22),
    ], 0)
    z0 = fit.top + 0.008
    add_revolve(bm, fit, [
        (fit.r * 0.92, z0),
        (fit.r * 0.94, z0 + 0.028),
        (fit.r * 0.90, z0 + 0.032),
    ], 0, segs=22)
    add_revolve(bm, fit, [
        (fit.r * 0.78, z0 + 0.032),
        (fit.r * 0.80, z0 + 0.054),
        (fit.r * 0.74, z0 + 0.058),
    ], 1, segs=20)
    for i in range(6):
        angle = i * TAU / 6.0
        base = Vector((
            fit.cx + math.cos(angle) * fit.r * 0.42,
            fit.cy + math.sin(angle) * fit.r * 0.42,
            z0 + 0.058,
        ))
        add_path_loft(bm, [base, base + Vector((0.0, 0.0, 0.028))],
                      [(0.004, 0.004), (0.003, 0.003)], 2,
                      wide_hint=(1.0, 0.0, 0.0), segments=6)
        add_sphere(bm, base + Vector((0.0, 0.0, 0.032)), 0.006, 1, segments=8)
    return slots


def hat_leaf_wreath(bm, fit: Fit) -> list[str]:
    slots = materials("leaf_wreath", [
        ("leaf", (0.62, 0.36, 0.12), 0.72, 0.0),
        ("vine", (0.28, 0.22, 0.10), 0.70, 0.0),
    ])
    add_band(bm, fit, fit.band_z - 0.010, fit.band_z + 0.016, 0.012, 1, segs=26)
    for i in range(12):
        angle = i * TAU / 12.0
        centre = fit.centre(fit.band_z + 0.018) + Vector((
            math.cos(angle) * fit.r * 1.10,
            math.sin(angle) * fit.r * 1.10,
            0.004 * ((i % 2) * 2 - 1),
        ))
        leaf = [
            centre + Vector((math.cos(angle + 0.3) * 0.008, math.sin(angle + 0.3) * 0.008, 0.0)),
            centre,
            centre + Vector((math.cos(angle - 0.3) * 0.022, math.sin(angle - 0.3) * 0.022, 0.008)),
        ]
        add_path_loft(bm, leaf, [(0.008, 0.003), (0.016, 0.004), (0.005, 0.002)],
                      0, wide_hint=(0.0, 0.0, 1.0), segments=6)
    return slots


def hat_mohawk(bm, fit: Fit) -> list[str]:
    slots = materials("mohawk", [
        ("hair", (0.72, 0.12, 0.42), 0.76, 0.0),
        ("clip", (0.18, 0.16, 0.16), 0.45, 0.10),
    ])
    add_wrap(bm, [
        skin_ring(fit, fit.top - 0.002, 1.06, 16),
        skin_ring(fit, fit.top - 0.002, 1.14, 16),
        skin_ring(fit, fit.top + 0.010, 1.12, 16),
        skin_ring(fit, fit.top + 0.010, 1.04, 16),
    ], 1)
    ridge = []
    for i in range(7):
        t = i / 6.0
        ridge.append(Vector((
            fit.cx,
            fit.cy - fit.r * 0.55 + fit.r * 1.15 * t,
            fit.top + 0.010 + 0.070 * math.sin(t * math.pi),
        )))
    add_path_loft(bm, ridge,
                  [(0.018, 0.010), (0.022, 0.028), (0.024, 0.040), (0.024, 0.046),
                   (0.022, 0.036), (0.018, 0.022), (0.012, 0.008)],
                  0, wide_hint=(1.0, 0.0, 0.0), segments=10)
    return slots


HATS = [
    ("party_hat", hat_party_hat),
    ("bunny_ears", hat_bunny_ears),
    ("top_hat", hat_top_hat),
    ("crown", hat_crown),
    ("beanie", hat_beanie),
    ("cowboy_hat", hat_cowboy_hat),
    ("propeller_cap", hat_propeller_cap),
    ("flower_crown", hat_flower_crown),
    ("antlers", hat_antlers),
    ("halo", hat_halo),
    ("wizard_hat", hat_wizard_hat),
    ("sombrero", hat_sombrero),
    ("newsboy_cap", hat_newsboy_cap),
    ("helmet", hat_helmet),
    ("pirate_hat", hat_pirate_hat),
    ("chef_toque", hat_chef_toque),
    ("jester_hat", hat_jester_hat),
    ("mushroom_cap", hat_mushroom_cap),
    ("antennae", hat_antennae),
    ("visor", hat_visor),
    ("bow", hat_bow),
    ("horned_helm", hat_horned_helm),
    ("fedora", hat_fedora),
    ("santa_hat", hat_santa_hat),
    ("cat_ears", hat_cat_ears),
    ("beret", hat_beret),
    ("baseball_cap", hat_baseball_cap),
    ("sun_hat", hat_sun_hat),
    ("hard_hat", hat_hard_hat),
    ("ushanka", hat_ushanka),
    ("turban", hat_turban),
    ("devil_horns", hat_devil_horns),
    ("unicorn_horn", hat_unicorn_horn),
    ("headphones", hat_headphones),
    ("tiara", hat_tiara),
    ("bandana", hat_bandana),
    ("rice_hat", hat_rice_hat),
    ("laurel", hat_laurel),
    ("nightcap", hat_nightcap),
    ("deerstalker", hat_deerstalker),
    ("frog_hood", hat_frog_hood),
    ("rainbow", hat_rainbow),
    ("paper_crown", hat_paper_crown),
    ("space_helmet", hat_space_helmet),
    ("cake_hat", hat_cake_hat),
    ("leaf_wreath", hat_leaf_wreath),
    ("mohawk", hat_mohawk),
]


# --------------------------------------------------------------------------
# Scene and export
# --------------------------------------------------------------------------

def load_settler() -> tuple[bpy.types.Object, bpy.types.Object]:
    reset_scene()
    bpy.ops.import_scene.gltf(filepath=CHAR_GLB)
    rig = next(obj for obj in bpy.data.objects if obj.type == "ARMATURE")
    body = next(obj for obj in bpy.data.objects
                if obj.type == "MESH" and "Character" in obj.name)
    leftover = bpy.data.objects.get("Icosphere")
    if leftover is not None:
        bpy.data.objects.remove(leftover, do_unlink=True)
    rig.data.pose_position = "REST"
    bpy.context.view_layer.update()
    return body, rig


def build_one(slug: str, builder, fit: Fit, body, rig) -> bpy.types.Object:
    existing = bpy.data.objects.get("apparel_c3_" + slug)
    if existing is not None:
        bpy.data.objects.remove(existing, do_unlink=True)
    bm = bmesh.new()
    slots = builder(bm, fit)
    if not bm.faces:
        bm.free()
        raise SystemExit("{0}: builder produced no faces".format(slug))
    return finish("apparel_c3_" + slug, bm, slots, body, rig)


def describe(obj: bpy.types.Object, fit: Fit) -> None:
    zs = [vert.co.z for vert in obj.data.vertices]
    xs = [abs(vert.co.x) for vert in obj.data.vertices]
    print("  {0:<22} {1:5d} faces  z[{2:.3f},{3:.3f}]  width={4:.3f}".format(
        obj.name.removeprefix("apparel_c3_"),
        len(obj.data.polygons),
        min(zs), max(zs), max(xs) * 2.0))
    if min(zs) < fit.neck.z - 0.04:
        print("    WARNING hem drops below the neck")
    if max(zs) > fit.top + 0.55:
        print("    WARNING crown is unusually tall")


def parse_args():
    argv = sys.argv[sys.argv.index("--") + 1:] if "--" in sys.argv else []
    parser = argparse.ArgumentParser()
    parser.add_argument("--only", default="")
    parser.add_argument("--skip-audit", action="store_true")
    return parser.parse_args(argv)


def audit_built(slug: str, obj, body, fit: Fit) -> bool:
    import audit_headwear as audit
    report = audit.measure(slug, obj, body, fit)
    audit.print_row(report)
    return report["ok"]


def main():
    args = parse_args()
    wanted = {item.strip() for item in args.only.split(",") if item.strip()}
    catalog = HATS
    if wanted:
        catalog = [(slug, fn) for slug, fn in HATS if slug in wanted]
        missing = wanted - {slug for slug, _fn in catalog}
        if missing:
            raise SystemExit("unknown hat(s): {0}".format(", ".join(sorted(missing))))
        if not catalog:
            raise SystemExit("no hats selected")

    body, rig = load_settler()
    fit = Fit(body, rig)
    print("fit: skull={0:.3f} top={1:.3f} brim={2:.3f} r={3:.3f} rx={4:.3f}".format(
        fit.skull.z, fit.top, fit.brim_z, fit.r, fit.rx))

    built = 0
    failed = []
    for slug, builder in catalog:
        obj = build_one(slug, builder, fit, body, rig)
        describe(obj, fit)
        path = export_garment(obj, rig)
        print("  wrote {0} ({1:.1f} KB)".format(
            os.path.basename(path), os.path.getsize(path) / 1024.0))
        if not args.skip_audit:
            bpy.context.view_layer.update()
            if not audit_built(slug, obj, body, fit):
                failed.append(slug)
        built += 1
    print("built {0} headwear item(s)".format(built))
    if failed:
        raise SystemExit("fit audit failed: {0}".format(", ".join(failed)))


if __name__ == "__main__":
    main()
