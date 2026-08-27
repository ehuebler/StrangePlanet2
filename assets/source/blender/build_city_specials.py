"""Walk-in civic buildings: hollow shells with interiors and exteriors.

Run from the repository root with Blender 5.1:

    & "C:\\Program Files\\Blender Foundation\\Blender 5.1\\blender.exe" `
        --background --factory-startup `
        --python assets/source/blender/build_city_specials.py

Door face 0 is the front (-Y). Interiors stay empty so Godot trimesh
collision lets the player walk through the doorway.
"""

from __future__ import annotations

import argparse
import json
import math
import os
import sys

import bpy
from mathutils import Vector

SOURCE_DIR = os.path.dirname(os.path.abspath(__file__))
PROJECT_DIR = os.path.abspath(os.path.join(
    SOURCE_DIR, os.pardir, os.pardir, os.pardir))
if SOURCE_DIR not in sys.path:
    sys.path.insert(0, SOURCE_DIR)

import building_kit as kit
import previewkit

MODEL_ROOT = os.path.join(PROJECT_DIR, "assets", "runtime", "cities", "models")
PAINT_ROOT = os.path.join(PROJECT_DIR, "assets", "runtime", "cities", "paint")
MANIFEST_PATH = os.path.join(
    PROJECT_DIR, "assets", "runtime", "cities", "manifests", "buildings.json")
PREVIEW_DIR = os.path.join(PROJECT_DIR, "assets", "previews", "cities")

PREVIEW_SAMPLES = 12
PREVIEW_RESOLUTION = (640, 640)
STORY = kit.STORY
WALL = kit.WALL_THICK
FLOOR = kit.FLOOR_THICK


def _recipe(name, display_name, seed, width, depth, stories, builder, notes,
            **extra):
    fields = dict(
        window_style="well", bevel_width=0.02, glow_family="mixed",
        ground_scale=1.0, bay_width=2.40, paint_size=512,
        triangle_budget=(800, 18000), uv_mode="unique",
        walkable=True, door_width=1.70, door_height=2.28, auto_windows=True,
    )
    fields.update(extra)
    return kit.BuildingRecipe(
        name=name, category="specials", display_name=display_name, seed=seed,
        width=width, depth=depth, stories=stories, builder=builder,
        notes=notes, **fields)


def _rel(path):
    return os.path.relpath(path, PROJECT_DIR).replace("\\", "/")


def _box(ctx, lo, hi, region=kit.REGION_TRIM):
    kit.furniture_box(ctx, lo, hi, region)


def _rect(ox, oy, sx, sy, chamfer=0.0):
    return kit.rect_profile(sx, sy, chamfer=chamfer, centre=(ox, oy))


def _room_h(recipe, stories=1):
    return STORY * max(int(stories), 1)


def _inset(recipe, extra=0.12):
    return WALL + extra


def _sign(ctx, x, y, z, w, h, d=0.08, region=kit.REGION_ACCENT):
    _box(ctx, (x - w * 0.5, y - d * 0.5, z), (x + w * 0.5, y + d * 0.5, z + h),
         region)


def _pole(ctx, x, y, z0, z1, half=0.06, region=kit.REGION_TRIM):
    _box(ctx, (x - half, y - half, z0), (x + half, y + half, z1), region)


def _stool(ctx, x, y, z0, seat=0.48):
    _pole(ctx, x, y, z0, z0 + seat, half=0.04, region=kit.REGION_TRIM)
    _box(ctx, (x - 0.16, y - 0.16, z0 + seat),
         (x + 0.16, y + 0.16, z0 + seat + 0.05), kit.REGION_ACCENT)


def _bench(ctx, x, y, z0, along="x", length=1.8):
    if along == "x":
        _box(ctx, (x - length * 0.5, y - 0.22, z0),
             (x + length * 0.5, y + 0.22, z0 + 0.42), kit.REGION_TRIM)
        _box(ctx, (x - length * 0.5, y + 0.10, z0 + 0.42),
             (x + length * 0.5, y + 0.22, z0 + 0.78), kit.REGION_TRIM)
    else:
        _box(ctx, (x - 0.22, y - length * 0.5, z0),
             (x + 0.22, y + length * 0.5, z0 + 0.42), kit.REGION_TRIM)
        _box(ctx, (x + 0.10, y - length * 0.5, z0 + 0.42),
             (x + 0.22, y + length * 0.5, z0 + 0.78), kit.REGION_TRIM)


def _table(ctx, x, y, z0, sx=1.2, sy=0.8, h=0.74):
    _box(ctx, (x - sx * 0.5, y - sy * 0.5, z0 + h - 0.06),
         (x + sx * 0.5, y + sy * 0.5, z0 + h), kit.REGION_TRIM)
    for dx, dy in ((-sx * 0.4, -sy * 0.35), (sx * 0.4, -sy * 0.35),
                   (-sx * 0.4, sy * 0.35), (sx * 0.4, sy * 0.35)):
        _pole(ctx, x + dx, y + dy, z0, z0 + h - 0.06, half=0.04)


def _desk(ctx, x, y, z0, sx=2.2, sy=0.7, h=0.92):
    _box(ctx, (x - sx * 0.5, y - sy * 0.5, z0),
         (x + sx * 0.5, y + sy * 0.5, z0 + h), kit.REGION_TRIM)
    _box(ctx, (x - sx * 0.46, y - sy * 0.42, z0 + 0.12),
         (x + sx * 0.46, y + sy * 0.20, z0 + h - 0.08), kit.REGION_BASE)


def _stairs(ctx, x, y, z0, rise, run=0.28, width=1.15, count=None, facing=(0.0, 1.0)):
    count = int(count if count is not None else max(round(rise / 0.18), 4))
    step_h = rise / float(count)
    fx, fy = facing
    length = math.hypot(fx, fy) or 1.0
    fx, fy = fx / length, fy / length
    rx, ry = -fy, fx
    for i in range(count):
        along0 = run * i
        along1 = run * (i + 1)
        cx0, cy0 = x + fx * along0, y + fy * along0
        cx1, cy1 = x + fx * along1, y + fy * along1
        xs = (cx0 - rx * width * 0.5, cx0 + rx * width * 0.5,
              cx1 - rx * width * 0.5, cx1 + rx * width * 0.5)
        ys = (cy0 - ry * width * 0.5, cy0 + ry * width * 0.5,
              cy1 - ry * width * 0.5, cy1 + ry * width * 0.5)
        _box(ctx, (min(xs), min(ys), z0),
             (max(xs), max(ys), z0 + step_h * (i + 1)), kit.REGION_BASE)


def _plant(ctx, x, y, z0, h=0.7):
    _box(ctx, (x - 0.22, y - 0.22, z0), (x + 0.22, y + 0.22, z0 + 0.18),
         kit.REGION_BASE)
    _box(ctx, (x - 0.16, y - 0.16, z0 + 0.18),
         (x + 0.16, y + 0.16, z0 + 0.18 + h), kit.REGION_ACCENT)


# --------------------------------------------------------------------------
# Specials
# --------------------------------------------------------------------------

def build_police_station(ctx, recipe):
    w, d = recipe.width, recipe.depth
    ground = _room_h(recipe, 1)
    upper = recipe.wall_h
    kit.hollow_rect(ctx, 0.0, 0.0, w, d, 0.0, ground)
    kit.prism(ctx, _rect(0.0, 0.0, w, d), ground, upper, register=True)
    kit.cornice(ctx, _rect(0.0, 0.0, w, d), upper, width=0.16, height=0.12)
    kit.parapet(ctx, _rect(0.0, 0.0, w, d), upper, height=0.48, thickness=0.12)
    porch_y = -d * 0.5 - 1.15
    kit.steps(ctx, 0.0, porch_y - 0.2, 0.0, width=2.4, depth=1.1, count=3)
    _pole(ctx, -1.1, porch_y, 0.0, 2.6)
    _pole(ctx, 1.1, porch_y, 0.0, 2.6)
    kit.shed_roof(ctx, _rect(0.0, porch_y, 3.4, 1.6), 2.45, 0.55,
                  fall_axis="-y", overhang=0.12)
    _sign(ctx, 0.0, -d * 0.5 - 0.12, ground + 0.35, 4.6, 0.7)
    _pole(ctx, w * 0.42, -d * 0.5 - 0.35, 0.0, upper + 1.4, half=0.05)
    _box(ctx, (w * 0.42 - 0.55, -d * 0.5 - 0.42, upper + 1.15),
         (w * 0.42 + 0.05, -d * 0.5 - 0.28, upper + 1.55), kit.REGION_ACCENT)
    inset = _inset(recipe)
    z = FLOOR
    _desk(ctx, 0.0, 1.15, z, sx=3.4, sy=0.85, h=1.05)
    _bench(ctx, -3.4, -2.4, z, along="x", length=2.4)
    _bench(ctx, 3.4, -2.4, z, along="x", length=2.4)
    # Holding cells at the back.
    cell_y = d * 0.5 - inset - 1.7
    for sx in (-3.2, 0.0, 3.2):
        _box(ctx, (sx - 1.35, cell_y - 1.35, z),
             (sx + 1.35, cell_y + 1.35, z + 0.08), kit.REGION_BASE)
        for t in range(5):
            px = sx - 1.15 + t * 0.58
            _pole(ctx, px, cell_y - 1.35, z, z + 2.15, half=0.035,
                  region=kit.REGION_TRIM)
        _box(ctx, (sx - 1.35, cell_y + 1.15, z),
             (sx + 1.35, cell_y + 1.35, z + 2.15), kit.REGION_WALL)
        _box(ctx, (sx - 0.45, cell_y - 0.35, z),
             (sx + 0.45, cell_y + 0.55, z + 0.38), kit.REGION_TRIM)
    _stairs(ctx, w * 0.5 - inset - 0.2, -1.6, z, ground - z,
            facing=(0.0, 1.0), width=1.15, count=12)


def build_corner_bar(ctx, recipe):
    w, d = recipe.width, recipe.depth
    h = recipe.wall_h
    kit.hollow_rect(ctx, 0.0, 0.0, w, d, 0.0, h)
    kit.gable_roof(ctx, _rect(0.0, 0.0, w, d), h, 1.35, ridge_axis="x",
                   overhang=0.28)
    # False front.
    _box(ctx, (-w * 0.5 - 0.08, -d * 0.5 - 0.10, 0.0),
         (w * 0.5 + 0.08, -d * 0.5 + 0.08, h + 1.15), kit.REGION_WALL)
    _sign(ctx, 0.0, -d * 0.5 - 0.16, h + 0.25, 4.8, 0.7)
    kit.steps(ctx, 0.0, -d * 0.5 - 0.85, 0.0, width=2.0, depth=0.9, count=2)
    kit.shed_roof(ctx, _rect(0.0, -d * 0.5 - 0.7, w * 0.72, 1.15), 2.35, 0.4,
                  fall_axis="-y", overhang=0.08)
    z = FLOOR
    inset = _inset(recipe)
    # Bar along the back.
    _box(ctx, (-w * 0.5 + inset, d * 0.5 - inset - 1.15, z),
         (w * 0.5 - inset - 1.6, d * 0.5 - inset, z + 1.08), kit.REGION_TRIM)
    _box(ctx, (-w * 0.5 + inset + 0.12, d * 0.5 - inset - 1.28, z + 1.08),
         (w * 0.5 - inset - 1.7, d * 0.5 - inset - 0.08, z + 1.18),
         kit.REGION_ACCENT)
    for i in range(5):
        _stool(ctx, -3.2 + i * 1.15, d * 0.5 - inset - 1.7, z)
    # Bottle shelves.
    _box(ctx, (-w * 0.5 + inset, d * 0.5 - inset - 0.22, z + 1.2),
         (w * 0.5 - inset - 1.7, d * 0.5 - inset, z + 2.35), kit.REGION_WALL)
    for i in range(8):
        _box(ctx, (-3.6 + i * 0.85, d * 0.5 - inset - 0.18, z + 1.35),
             (-3.4 + i * 0.85, d * 0.5 - inset - 0.04, z + 1.7),
             kit.REGION_ACCENT)
    _table(ctx, -2.4, -1.15, z, sx=1.15, sy=0.75)
    _table(ctx, 0.2, -1.15, z, sx=1.15, sy=0.75)
    _bench(ctx, -2.4, -1.85, z, along="x", length=1.3)
    _bench(ctx, 0.2, -1.85, z, along="x", length=1.3)
    _box(ctx, (w * 0.5 - inset - 1.45, -0.8, z),
         (w * 0.5 - inset, 1.6, z + 0.35), kit.REGION_BASE)
    _pole(ctx, w * 0.5 - inset - 0.7, 0.4, z + 0.35, z + 1.8, half=0.08,
          region=kit.REGION_ACCENT)


def build_neon_casino(ctx, recipe):
    w, d = recipe.width, recipe.depth
    ground = _room_h(recipe, 1) + 0.25
    kit.hollow_rect(ctx, 0.0, 0.0, w, d, 0.0, ground, door_width=2.1)
    kit.prism(ctx, _rect(0.0, 0.0, w * 0.72, d * 0.62, chamfer=0.8),
              ground, recipe.wall_h, register=True)
    kit.cornice(ctx, _rect(0.0, 0.0, w, d), ground, width=0.22, height=0.14)
    kit.dome_roof(ctx, 0.0, 0.0, min(w, d) * 0.22, recipe.wall_h, rise=1.8,
                  segments=12)
    canopy_y = -d * 0.5 - 1.35
    kit.prism(ctx, _rect(0.0, canopy_y, 6.4, 2.2, chamfer=0.6), 2.15, 2.45,
              region=kit.REGION_ACCENT, register=False)
    _pole(ctx, -2.6, canopy_y - 0.6, 0.0, 2.2)
    _pole(ctx, 2.6, canopy_y - 0.6, 0.0, 2.2)
    kit.steps(ctx, 0.0, canopy_y - 0.15, 0.0, width=2.6, depth=1.1, count=3)
    _sign(ctx, 0.0, -d * 0.5 - 0.14, ground + 0.2, 7.2, 0.85)
    z = FLOOR
    inset = _inset(recipe)
    # Cashier cage.
    _box(ctx, (-w * 0.5 + inset, d * 0.5 - inset - 2.2, z),
         (-w * 0.5 + inset + 3.2, d * 0.5 - inset, z + 1.15), kit.REGION_TRIM)
    for t in range(6):
        _pole(ctx, -w * 0.5 + inset + 0.25 + t * 0.5, d * 0.5 - inset - 2.2,
              z + 1.15, z + 2.15, half=0.03)
    # Tables.
    spots = ((-3.6, -1.2), (-0.2, -1.2), (3.4, -1.2),
             (-3.6, 1.6), (-0.2, 1.6), (3.4, 1.6))
    for x, y in spots:
        _table(ctx, x, y, z, sx=1.35, sy=1.35, h=0.78)
        _box(ctx, (x - 0.55, y - 0.55, z + 0.78),
             (x + 0.55, y + 0.55, z + 0.86), kit.REGION_ACCENT)
    _box(ctx, (-0.7, 3.1, z), (0.7, 4.3, z + 0.22), kit.REGION_BASE)
    _pole(ctx, 0.0, 3.7, z + 0.22, z + 2.6, half=0.07, region=kit.REGION_ACCENT)
    _box(ctx, (-0.55, 3.15, z + 2.55), (0.55, 4.25, z + 2.85), kit.REGION_TRIM)
    _stairs(ctx, w * 0.5 - inset - 0.15, -2.0, z, ground - z,
            facing=(0.0, 1.0), width=1.2, count=13)


def build_night_club(ctx, recipe):
    w, d = recipe.width, recipe.depth
    h = recipe.wall_h + 0.8
    kit.hollow_rect(ctx, 0.0, 0.0, w, d, 0.0, h, door_width=1.9)
    kit.roof_slab(ctx, _rect(0.0, 0.0, w, d), h, thickness=0.16, overhang=0.12)
    for x in (-w * 0.42, -w * 0.14, w * 0.14, w * 0.42):
        _box(ctx, (x - 0.08, -d * 0.5 - 0.18, 0.6),
             (x + 0.08, -d * 0.5 + 0.06, h - 0.2), kit.REGION_ACCENT)
    kit.shed_roof(ctx, _rect(0.0, -d * 0.5 - 0.85, 5.2, 1.5), 2.5, 0.45,
                  fall_axis="-y", overhang=0.1)
    _pole(ctx, -2.1, -d * 0.5 - 1.35, 0.0, 2.5)
    _pole(ctx, 2.1, -d * 0.5 - 1.35, 0.0, 2.5)
    _sign(ctx, 0.0, -d * 0.5 - 0.16, h - 1.1, 5.6, 0.7)
    kit.steps(ctx, 0.0, -d * 0.5 - 0.9, 0.0, width=2.2, depth=0.95, count=2)
    z = FLOOR
    inset = _inset(recipe)
    # Dance floor.
    _box(ctx, (-2.6, -1.6, z), (2.6, 1.8, z + 0.04), kit.REGION_ACCENT)
    # DJ booth.
    _box(ctx, (-1.6, d * 0.5 - inset - 1.5, z),
         (1.6, d * 0.5 - inset, z + 1.05), kit.REGION_TRIM)
    _box(ctx, (-1.1, d * 0.5 - inset - 1.15, z + 1.05),
         (1.1, d * 0.5 - inset - 0.15, z + 1.18), kit.REGION_ACCENT)
    # Side bar.
    _box(ctx, (-w * 0.5 + inset, -0.4, z),
         (-w * 0.5 + inset + 0.85, 2.6, z + 1.02), kit.REGION_TRIM)
    for i in range(4):
        _stool(ctx, -w * 0.5 + inset + 1.25, -0.1 + i * 0.85, z)
    # Booths.
    for y in (-2.4, 0.1, 2.6):
        _bench(ctx, w * 0.5 - inset - 0.85, y, z, along="y", length=1.7)
        _table(ctx, w * 0.5 - inset - 1.7, y, z, sx=0.7, sy=1.1)


def build_civic_hospital(ctx, recipe):
    w, d = recipe.width, recipe.depth
    ground = _room_h(recipe, 1)
    kit.hollow_rect(ctx, 0.0, 0.0, w, d, 0.0, ground, door_width=2.0)
    kit.prism(ctx, _rect(0.0, 0.0, w, d), ground, recipe.wall_h, register=True)
    kit.cornice(ctx, _rect(0.0, 0.0, w, d), recipe.wall_h, width=0.18, height=0.12)
    kit.roof_slab(ctx, _rect(0.0, 0.0, w, d), recipe.wall_h, thickness=0.14,
                  overhang=0.2)
    # Ambulance bay.
    bay_x = -w * 0.5 - 2.4
    kit.prism(ctx, _rect(bay_x, -0.4, 4.4, 7.2), 0.0, 3.4,
              region=kit.REGION_BASE, register=False)
    kit.shed_roof(ctx, _rect(bay_x, -0.4, 4.6, 7.4), 3.25, 0.55,
                  fall_axis="-x", overhang=0.1)
    _pole(ctx, bay_x - 1.7, -3.4, 0.0, 3.25)
    _pole(ctx, bay_x - 1.7, 2.6, 0.0, 3.25)
    # Cross.
    _box(ctx, (-0.22, -d * 0.5 - 0.14, recipe.wall_h * 0.55),
         (0.22, -d * 0.5 + 0.08, recipe.wall_h * 0.55 + 2.4), kit.REGION_ACCENT)
    _box(ctx, (-0.85, -d * 0.5 - 0.14, recipe.wall_h * 0.55 + 0.85),
         (0.85, -d * 0.5 + 0.08, recipe.wall_h * 0.55 + 1.35), kit.REGION_ACCENT)
    kit.steps(ctx, 0.0, -d * 0.5 - 0.95, 0.0, width=2.5, depth=1.05, count=3)
    z = FLOOR
    inset = _inset(recipe)
    _desk(ctx, 0.0, 1.4, z, sx=4.2, sy=0.9, h=1.0)
    _bench(ctx, -5.2, -2.8, z, along="x", length=2.6)
    _bench(ctx, -2.2, -2.8, z, along="x", length=2.6)
    _bench(ctx, 2.2, -2.8, z, along="x", length=2.6)
    _bench(ctx, 5.2, -2.8, z, along="x", length=2.6)
    # Exam rooms as open bays with beds.
    for i, sx in enumerate((-5.4, -1.8, 1.8, 5.4)):
        _box(ctx, (sx - 1.5, d * 0.5 - inset - 3.4, z),
             (sx + 1.5, d * 0.5 - inset, z + 0.06), kit.REGION_BASE)
        _box(ctx, (sx - 1.5, d * 0.5 - inset - 0.16, z),
             (sx + 1.5, d * 0.5 - inset, z + 2.4), kit.REGION_WALL)
        if i > 0:
            _box(ctx, (sx - 1.58, d * 0.5 - inset - 3.4, z),
                 (sx - 1.42, d * 0.5 - inset, z + 2.4), kit.REGION_WALL)
        _box(ctx, (sx - 0.85, d * 0.5 - inset - 2.5, z + 0.06),
             (sx + 0.85, d * 0.5 - inset - 0.7, z + 0.55), kit.REGION_TRIM)
        _box(ctx, (sx - 0.55, d * 0.5 - inset - 1.35, z + 0.55),
             (sx + 0.55, d * 0.5 - inset - 0.85, z + 0.7), kit.REGION_ACCENT)
    _plant(ctx, -7.2, -1.2, z)
    _plant(ctx, 7.2, -1.2, z)
    _stairs(ctx, w * 0.5 - inset - 0.15, -1.8, z, ground - z,
            facing=(0.0, 1.0), width=1.2, count=12)


def build_glass_greenhouse(ctx, recipe):
    w, d = recipe.width, recipe.depth
    h = 4.4
    recipe.auto_windows = False
    wall = 0.16
    kit.hollow_rect(ctx, 0.0, 0.0, w, d, 0.0, h, wall=wall, door_width=1.8,
                    door_height=2.2, register=False, ceiling=False)
    # Iron ribs.
    for x in (-w * 0.5, 0.0, w * 0.5):
        _box(ctx, (x - 0.07, -d * 0.5, 0.0), (x + 0.07, d * 0.5, h),
             kit.REGION_TRIM)
    for y in (-d * 0.5, 0.0, d * 0.5):
        _box(ctx, (-w * 0.5, y - 0.07, 0.0), (w * 0.5, y + 0.07, h),
             kit.REGION_TRIM)
    kit.gable_roof(ctx, _rect(0.0, 0.0, w, d), h, 1.65, ridge_axis="x",
                   overhang=0.18)
    kit.steps(ctx, 0.0, -d * 0.5 - 0.75, 0.0, width=2.0, depth=0.8, count=2)
    glow = kit.glow_for(recipe, "lime_stucco")
    # Glass walls (skip the door bay on -Y).
    hx, hy = w * 0.5 - 0.05, d * 0.5 - 0.05
    panes = (
        (Vector((-hx, -hy, 0.12)), Vector((1, 0, 0)), Vector((0, -1, 0)), w - 0.1, 0),
        (Vector((hx, -hy, 0.12)), Vector((0, 1, 0)), Vector((1, 0, 0)), d - 0.1, 1),
        (Vector((hx, hy, 0.12)), Vector((-1, 0, 0)), Vector((0, 1, 0)), w - 0.1, 2),
        (Vector((-hx, hy, 0.12)), Vector((0, -1, 0)), Vector((-1, 0, 0)), d - 0.1, 3),
    )
    door_w = 1.8
    for origin, right, outward, span, face in panes:
        if face == 0:
            left = (span - door_w) * 0.5
            kit.add_glass_pane(ctx, origin, right, Vector((0, 0, 1)), outward,
                               left, h - 0.3, glow, face)
            kit.add_glass_pane(
                ctx, origin + right.normalized() * (left + door_w),
                right, Vector((0, 0, 1)), outward, left, h - 0.3, glow, face)
            kit.add_glass_pane(
                ctx, origin + right.normalized() * left + Vector((0, 0, 2.25)),
                right, Vector((0, 0, 1)), outward, door_w, h - 2.55, glow, face)
        else:
            kit.add_glass_pane(ctx, origin, right, Vector((0, 0, 1)), outward,
                               span, h - 0.3, glow, face)
    z = FLOOR
    inset = wall + 0.35
    # Path and beds.
    _box(ctx, (-0.7, -d * 0.5 + inset, z),
         (0.7, d * 0.5 - inset, z + 0.03), kit.REGION_BASE)
    beds = (
        (-w * 0.28, -2.4, 3.4, 2.0), (w * 0.28, -2.4, 3.4, 2.0),
        (-w * 0.28, 1.6, 3.4, 2.2), (w * 0.28, 1.6, 3.4, 2.2),
    )
    for x, y, sx, sy in beds:
        _box(ctx, (x - sx * 0.5, y - sy * 0.5, z),
             (x + sx * 0.5, y + sy * 0.5, z + 0.32), kit.REGION_BASE)
        for ox in (-sx * 0.28, 0.0, sx * 0.28):
            for oy in (-sy * 0.22, sy * 0.22):
                _plant(ctx, x + ox, y + oy, z + 0.32, h=0.55 + (ox + oy) * 0.08)
    _box(ctx, (-0.35, 0.1, z), (0.35, 0.9, z + 0.2), kit.REGION_TRIM)
    _box(ctx, (-0.22, 0.22, z + 0.2), (0.22, 0.78, z + 1.6), kit.REGION_ACCENT)
    _bench(ctx, 0.0, -d * 0.5 + inset + 1.1, z, along="x", length=1.6)


def build_quiet_cemetery(ctx, recipe):
    w, d = recipe.width, recipe.depth
    # Grounds stay open. Chapel is the walk-in volume.
    chapel_w, chapel_d = 8.2, 7.4
    chapel_y = d * 0.5 - chapel_d * 0.5 - 0.6
    kit.hollow_rect(ctx, 0.0, chapel_y, chapel_w, chapel_d, 0.0, 3.35,
                    door_width=1.6)
    kit.gable_roof(ctx, _rect(0.0, chapel_y, chapel_w, chapel_d), 3.35, 1.55,
                   ridge_axis="x", overhang=0.28)
    _box(ctx, (-0.16, chapel_y + 0.1, 4.7),
         (0.16, chapel_y + 0.4, 6.1), kit.REGION_TRIM)
    _box(ctx, (-0.55, chapel_y + 0.1, 5.55),
         (0.55, chapel_y + 0.4, 5.85), kit.REGION_TRIM)
    kit.steps(ctx, 0.0, chapel_y - chapel_d * 0.5 - 0.7, 0.0,
              width=1.8, depth=0.8, count=2)
    # Fence with a gate on -Y.
    post = 0.08
    fence_h = 1.15
    hx, hy = w * 0.5, d * 0.5
    for x in (-hx, hx):
        _box(ctx, (x - post, -hy, 0.0), (x + post, hy, fence_h), kit.REGION_TRIM)
    _box(ctx, (-hx, hy - post, 0.0), (hx, hy + post, fence_h), kit.REGION_TRIM)
    gate = 2.2
    _box(ctx, (-hx, -hy - post, 0.0), (-gate * 0.5, -hy + post, fence_h),
         kit.REGION_TRIM)
    _box(ctx, (gate * 0.5, -hy - post, 0.0), (hx, -hy + post, fence_h),
         kit.REGION_TRIM)
    _pole(ctx, -gate * 0.5, -hy, 0.0, 1.55, half=0.07)
    _pole(ctx, gate * 0.5, -hy, 0.0, 1.55, half=0.07)
    # Headstones.
    rows = (-4.6, -2.2, 0.2)
    cols = (-7.2, -4.8, -2.4, 2.4, 4.8, 7.2)
    for y in rows:
        for x in cols:
            _box(ctx, (x - 0.28, y - 0.10, 0.0),
                 (x + 0.28, y + 0.12, 0.82), kit.REGION_BASE)
            _box(ctx, (x - 0.22, y - 0.08, 0.82),
                 (x + 0.22, y + 0.10, 1.15), kit.REGION_TRIM)
    # Path.
    _box(ctx, (-0.7, -hy, 0.0), (0.7, chapel_y - chapel_d * 0.5, 0.04),
         kit.REGION_BASE)
    # Chapel interior.
    z = FLOOR
    cy = chapel_y
    _box(ctx, (-1.1, cy + 2.2, z), (1.1, cy + 2.85, z + 0.95), kit.REGION_ACCENT)
    _box(ctx, (-0.35, cy + 1.85, z), (0.35, cy + 2.2, z + 0.85), kit.REGION_TRIM)
    for y in (cy - 0.9, cy + 0.5):
        _bench(ctx, -1.7, y, z, along="x", length=2.2)
        _bench(ctx, 1.7, y, z, along="x", length=2.2)


def build_civic_office(ctx, recipe):
    w, d = recipe.width, recipe.depth
    ground = _room_h(recipe, 1) + 0.15
    kit.hollow_rect(ctx, 0.0, 0.0, w, d, 0.0, ground, door_width=1.9)
    kit.prism(ctx, _rect(0.0, 0.0, w, d), ground, recipe.wall_h, register=True)
    kit.cornice(ctx, _rect(0.0, 0.0, w, d), recipe.wall_h, width=0.16, height=0.12)
    kit.roof_slab(ctx, _rect(0.0, 0.0, w, d), recipe.wall_h, thickness=0.14,
                  overhang=0.16)
    kit.fins(ctx, _rect(0.0, 0.0, w, d), 0.0, recipe.wall_h, width=0.07, depth=0.12)
    kit.steps(ctx, 0.0, -d * 0.5 - 0.9, 0.0, width=2.3, depth=1.0, count=3)
    _sign(ctx, 0.0, -d * 0.5 - 0.12, ground + 0.25, 5.2, 0.55)
    z = FLOOR
    inset = _inset(recipe)
    # Lobby desk.
    _desk(ctx, 0.0, 0.9, z, sx=3.6, sy=0.8, h=1.02)
    _bench(ctx, -3.8, -2.5, z, along="x", length=2.2)
    _bench(ctx, 3.8, -2.5, z, along="x", length=2.2)
    # Elevator core (closed).
    _box(ctx, (-1.15, d * 0.5 - inset - 2.4, z),
         (1.15, d * 0.5 - inset, z + ground - 0.12), kit.REGION_WALL)
    _box(ctx, (-0.7, d * 0.5 - inset - 2.45, z + 0.12),
         (0.7, d * 0.5 - inset - 2.32, z + 2.15), kit.REGION_TRIM)
    # Cubicles.
    for i, x in enumerate((-5.0, -2.5, 2.5, 5.0)):
        _box(ctx, (x - 1.05, 1.4, z), (x + 1.05, 3.5, z + 1.15), kit.REGION_TRIM)
        _box(ctx, (x - 0.85, 1.55, z + 0.72),
             (x + 0.85, 2.35, z + 0.78), kit.REGION_BASE)
        _box(ctx, (x - 0.18, 2.6, z + 0.78),
             (x + 0.22, 3.15, z + 1.05), kit.REGION_ACCENT)
    _table(ctx, 0.0, -1.4, z, sx=2.2, sy=1.1, h=0.74)
    _plant(ctx, -w * 0.5 + inset + 0.4, -2.6, z, h=0.9)
    _plant(ctx, w * 0.5 - inset - 0.4, -2.6, z, h=0.9)
    _stairs(ctx, w * 0.5 - inset - 0.15, -1.2, z, ground - z,
            facing=(0.0, 1.0), width=1.15, count=12)


RECIPES = (
    _recipe("police_station", "Police Station", 811, 15.2, 13.4, 2,
            build_police_station, "Walk-in precinct: lobby, desk, holding cells."),
    _recipe("corner_bar", "Bar", 823, 11.6, 9.8, 1,
            build_corner_bar, "Walk-in bar: counter, stools, booths."),
    _recipe("neon_casino", "Casino", 829, 17.4, 15.2, 2,
            build_neon_casino, "Walk-in casino: tables, cashier, canopy."),
    _recipe("night_club", "Night Club", 839, 13.8, 11.6, 1,
            build_night_club, "Walk-in club: dance floor, DJ booth, booths.",
            glow_family="cool", window_style="glass"),
    _recipe("civic_hospital", "Hospital", 853, 20.8, 16.6, 3,
            build_civic_hospital, "Walk-in hospital: lobby, bays, ambulance porch."),
    _recipe("glass_greenhouse", "Greenhouse", 859, 13.6, 15.4, 1,
            build_glass_greenhouse,
            "Walk-in greenhouse: iron frame, glass, planter beds.",
            auto_windows=False, glow_family="warm"),
    _recipe("quiet_cemetery", "Cemetery", 863, 19.2, 15.8, 1,
            build_quiet_cemetery,
            "Chapel you can enter, graves and a gated yard."),
    _recipe("civic_office", "Office", 877, 15.4, 13.2, 3,
            build_civic_office, "Walk-in office: lobby, cubicles, elevator core.",
            glow_family="cool", window_style="glass"),
)

RECIPE_BY_NAME = {recipe.name: recipe for recipe in RECIPES}


def _bounds(objects):
    low = Vector((1.0e9, 1.0e9, 1.0e9))
    high = Vector((-1.0e9, -1.0e9, -1.0e9))
    for obj in objects:
        for corner in obj.bound_box:
            world = obj.matrix_world @ Vector(corner)
            low.x, low.y, low.z = (
                min(low.x, world.x), min(low.y, world.y), min(low.z, world.z))
            high.x, high.y, high.z = (
                max(high.x, world.x), max(high.y, world.y), max(high.z, world.z))
    return low, high


def _assign_material(obj, material):
    if obj.data.materials:
        obj.data.materials[0] = material
    else:
        obj.data.materials.append(material)


def _paint_path(recipe, style):
    return os.path.join(
        PAINT_ROOT, recipe.category,
        "{}_{}_paint.png".format(recipe.name, style))


def _render_previews(recipe, hull, glass):
    os.makedirs(PREVIEW_DIR, exist_ok=True)
    live = [obj for obj in (hull, glass) if obj is not None]
    low, high = _bounds(live)
    size = high - low
    focus = (low + high) * 0.5
    reach = max(size.x, size.y, size.z, 4.0)
    preview = previewkit.Preview(PREVIEW_DIR, samples=PREVIEW_SAMPLES)
    preview.ground(level=low.z, size=max(reach * 2.4, 16.0))
    preview.lights(focus, spread=reach * 0.45)
    preview.hero(
        focus + Vector((reach * 0.85, -reach * 1.05, reach * 0.55)),
        focus, lens=50.0)
    preview.shot(recipe.name + "_close", PREVIEW_RESOLUTION)
    preview.hero(
        focus + Vector((reach * 1.55, -reach * 2.05, reach * 0.95)),
        focus, lens=42.0)
    preview.shot(recipe.name + "_gameplay", PREVIEW_RESOLUTION)
    # Inside, looking toward the door and furniture.
    interior = Vector((0.0, recipe.depth * 0.12, 1.45))
    preview.hero(
        interior + Vector((0.35, recipe.depth * 0.18, 0.15)),
        interior + Vector((0.0, -recipe.depth * 0.35, 0.05)),
        lens=46.0)
    preview.shot(recipe.name + "_interior", PREVIEW_RESOLUTION)
    night_path = _paint_path(recipe, "neon_night")
    if os.path.isfile(night_path) and hull.data.materials:
        image = bpy.data.images.load(night_path)
        kit.bind_paint(hull.data.materials[0], image)
    previewkit.Preview._set_world((0.012, 0.014, 0.02, 1.0))
    preview.lights(focus, spread=reach * 0.45, gain=0.18)
    preview.hero(
        focus + Vector((reach * 1.2, -reach * 1.55, reach * 0.72)),
        focus, lens=46.0)
    preview.shot(recipe.name + "_night", PREVIEW_RESOLUTION)


def build_one(recipe, skip_previews=False, skip_paints=False):
    print("\n=== {} ===".format(recipe.name))
    kit.reset_scene()
    ctx = kit.BuildContext(recipe)
    recipe.builder(ctx, recipe)
    kit.dress_windows(ctx)
    window_count = len(ctx.windows)
    hull = kit.finish_mesh(ctx, ctx.hull, recipe.name, kind="hull")
    glass = kit.finish_mesh(ctx, ctx.glass, recipe.name + "_glass", kind="glass")
    glass.parent = hull
    _assign_material(hull, kit.make_hull_material())
    _assign_material(glass, kit.make_glass_material())
    kit.ground_objects([hull, glass])

    model_dir = os.path.join(MODEL_ROOT, recipe.category)
    os.makedirs(model_dir, exist_ok=True)
    glb_path = os.path.join(model_dir, recipe.name + ".glb")
    kit.export_glb([hull, glass], glb_path)
    checked = kit.validate_glb(glb_path)

    paint_dir = os.path.join(PAINT_ROOT, recipe.category)
    os.makedirs(paint_dir, exist_ok=True)
    paint_entries = []
    paint_images = []
    for style in kit.PAINT_STYLES:
        paint_path = _paint_path(recipe, style)
        if not skip_paints:
            paint_images.append(kit.write_paint(recipe, style, paint_path))
        glow = kit.glow_for(recipe, style)
        paint_entries.append({
            "style": style,
            "path": _rel(paint_path),
            "size": [recipe.paint_size, recipe.paint_size],
            "window_glow": [round(float(glow[0]), 4),
                            round(float(glow[1]), 4),
                            round(float(glow[2]), 4)],
        })
    if paint_images and hull.data.materials:
        kit.bind_paint(hull.data.materials[0], paint_images[0])
    for extra in paint_images[1:]:
        if extra.name in bpy.data.images:
            bpy.data.images.remove(extra, do_unlink=True)

    previews = {
        "close": _rel(os.path.join(PREVIEW_DIR, recipe.name + "_close.png")),
        "gameplay": _rel(os.path.join(
            PREVIEW_DIR, recipe.name + "_gameplay.png")),
        "interior": _rel(os.path.join(
            PREVIEW_DIR, recipe.name + "_interior.png")),
        "night": _rel(os.path.join(PREVIEW_DIR, recipe.name + "_night.png")),
    }
    if not skip_previews:
        _render_previews(recipe, hull, glass)

    low, high = _bounds([hull, glass])
    size = high - low
    return {
        "name": recipe.name,
        "display_name": recipe.display_name,
        "category": recipe.category,
        "notes": recipe.notes,
        "glb": _rel(glb_path),
        "authored_width": recipe.width,
        "authored_depth": recipe.depth,
        "authored_stories": recipe.stories,
        "walkable": True,
        "door_face": 0,
        "door_width": recipe.door_width,
        "door_height": recipe.door_height,
        "measured_size": [
            round(size.x, 6), round(size.y, 6), round(size.z, 6)],
        "floor": 0.0,
        "triangle_count": checked["triangles"],
        "glb_vertex_count": checked["vertices"],
        "triangle_budget": {
            "minimum": recipe.triangle_budget[0],
            "maximum": recipe.triangle_budget[1],
        },
        "window_count": window_count,
        "paints": paint_entries,
        "previews": previews,
        "material": {
            "vertex_colour_attribute": "COLOR_0",
            "color_paint_uv": "TEXCOORD_0",
            "color_paint_alpha": (
                "night window emission mask; never used as transparency"),
            "glass_color": (
                "COLOR_0 RGB is the night glow read by city_window.gdshader"),
        },
        "runtime_contract": {
            "hull_node": recipe.name,
            "glass_node": recipe.name + "_glass",
            "mesh_nodes": 2,
            "walkable": True,
            "interior": True,
            "ground_axis": "Godot/glTF +Y",
        },
        "file_size_bytes": os.path.getsize(glb_path),
    }


def write_manifest(entries, partial):
    manifest = {
        "schema": "authored_city_building_manifest",
        "version": 1,
        "generator": "assets/source/blender/build_city_specials.py",
        "coordinate_system": {
            "authoring": "Blender Z-up, metres",
            "runtime": "glTF/Godot Y-up, metres",
            "axis_conversion": "Blender (x, y, z) -> glTF/Godot (x, z, -y)",
            "ground_plane": "runtime Y=0",
        },
        "library_contract": {
            "hull_and_glass": True,
            "vertex_colour": "COLOR_0",
            "color_paint_uv": "TEXCOORD_0",
            "walkable_specials": True,
        },
        "paint_styles": list(kit.PAINT_STYLES),
        "categories": [
            "small_houses", "medium_apartments", "medium_buildings",
            "large_towers", "skyscrapers", "specials",
        ],
        "assets": {},
    }
    if os.path.isfile(MANIFEST_PATH):
        with open(MANIFEST_PATH, "r", encoding="utf-8") as stream:
            existing = json.load(stream)
        if existing.get("schema") == manifest["schema"]:
            manifest["assets"].update(existing.get("assets", {}))
            if existing.get("paint_styles"):
                manifest["paint_styles"] = existing["paint_styles"]
            cats = list(existing.get("categories", []))
            if "specials" not in cats:
                cats.append("specials")
            manifest["categories"] = cats
            if existing.get("variants"):
                manifest["variants"] = existing["variants"]
            if existing.get("variant_paint_styles"):
                manifest["variant_paint_styles"] = existing["variant_paint_styles"]
    for entry in entries:
        manifest["assets"][entry["name"]] = entry
    if "specials" not in manifest["categories"]:
        manifest["categories"].append("specials")
    manifest["asset_count"] = len(manifest["assets"])
    os.makedirs(os.path.dirname(MANIFEST_PATH), exist_ok=True)
    with open(MANIFEST_PATH, "w", encoding="utf-8", newline="\n") as stream:
        json.dump(manifest, stream, indent=2, sort_keys=False)
        stream.write("\n")
    return MANIFEST_PATH


def arguments():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--only", nargs="+", metavar="NAME")
    parser.add_argument("--skip-previews", action="store_true")
    parser.add_argument("--skip-paints", action="store_true")
    blender_arguments = (
        sys.argv[sys.argv.index("--") + 1:] if "--" in sys.argv else [])
    return parser.parse_args(blender_arguments)


def selected(options):
    recipes = list(RECIPES)
    if options.only:
        names = []
        for value in options.only:
            names.extend(item.strip() for item in value.split(",") if item.strip())
        unknown = sorted(set(names) - set(RECIPE_BY_NAME))
        if unknown:
            raise SystemExit("unknown special(s): " + ", ".join(unknown))
        wanted = set(names)
        recipes = [recipe for recipe in recipes if recipe.name in wanted]
    return recipes


def main():
    options = arguments()
    recipes = selected(options)
    if not recipes:
        raise SystemExit("no special buildings selected")
    entries = []
    for recipe in recipes:
        entries.append(build_one(
            recipe,
            skip_previews=options.skip_previews,
            skip_paints=options.skip_paints,
        ))
    path = write_manifest(entries, partial=bool(options.only))
    print("\nCITY_SPECIAL_SUMMARY")
    print(json.dumps({
        "manifest": path,
        "asset_count": len(entries),
        "assets": {
            entry["name"]: {
                "triangles": entry["triangle_count"],
                "windows": entry["window_count"],
                "glb_kib": round(entry["file_size_bytes"] / 1024.0, 1),
            }
            for entry in entries
        },
    }, indent=2, sort_keys=True))
    print("city special build complete")


if __name__ == "__main__":
    main()
