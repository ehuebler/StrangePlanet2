"""Authored city-building library: 50 hull+glass GLBs and ten paint PNGs each.

Run from the repository root with Blender 5.1:

    & "C:\\Program Files\\Blender Foundation\\Blender 5.1\\blender.exe" `
        --background --factory-startup `
        --python assets/source/blender/build_city_buildings.py

Optional arguments belong after Blender's ``--`` separator:

    ... --python assets/source/blender/build_city_buildings.py -- `
        --only hearth_cottage --skip-previews

Door face 0 is the front (-Y). Volumes use building_kit plan-centre
ox/oy, size sx/sy, and elevations z0/z1.
"""

from __future__ import annotations

import argparse
import json
import math
import os
import sys

import bmesh
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

CATEGORY_DEFAULTS = {
    "small_houses": {
        "window_style": "well", "bevel_width": 0.04, "glow_family": "warm",
        "ground_scale": 1.10, "bay_width": 2.05,
    },
    "medium_apartments": {
        "window_style": "glass", "bevel_width": 0.055, "glow_family": "warm",
        "ground_scale": 1.18, "bay_width": 2.35,
    },
    "medium_buildings": {
        "window_style": "glass", "bevel_width": 0.06, "glow_family": "mixed",
        "ground_scale": 1.28, "bay_width": 2.55,
    },
    "large_towers": {
        "window_style": "glass", "bevel_width": 0.08, "glow_family": "cool",
        "ground_scale": 1.22, "bay_width": 2.80,
    },
    "skyscrapers": {
        "window_style": "glass", "bevel_width": 0.10, "glow_family": "cool",
        "ground_scale": 1.30, "bay_width": 3.10,
    },
}


def _recipe(name, category, display_name, seed, width, depth, stories, builder,
            notes=""):
    fields = dict(CATEGORY_DEFAULTS[category])
    fields.update(
        paint_size=512, triangle_budget=(400, 28000), uv_mode="unique")
    return kit.BuildingRecipe(
        name=name, category=category, display_name=display_name, seed=seed,
        width=width, depth=depth, stories=stories, builder=builder,
        notes=notes, **fields)


def _rel(path):
    return os.path.relpath(path, PROJECT_DIR).replace("\\", "/")


def _story_z(recipe, index):
    return recipe.ground_h + index * kit.STORY


def _box(ctx, lo, hi, region):
    kit.add_box(ctx.hull, lo, hi, region)


def _quoins(ctx, ox, oy, sx, sy, z0, z1, inset=0.18, thick=0.28):
    hx, hy = sx * 0.5 - inset, sy * 0.5 - inset
    for x, y in ((-hx, -hy), (hx, -hy), (hx, hy), (-hx, hy)):
        _box(ctx,
             (ox + x - thick * 0.5, oy + y - thick * 0.5, z0),
             (ox + x + thick * 0.5, oy + y + thick * 0.5, z1),
             kit.REGION_TRIM)


def _posts(ctx, points, z0, z1, half=0.11):
    for x, y in points:
        _box(ctx, (x - half, y - half, z0), (x + half, y + half, z1),
             kit.REGION_TRIM)


def _rect(ox, oy, sx, sy, chamfer=0.0):
    return kit.rect_profile(sx, sy, chamfer=chamfer, centre=(ox, oy))


def _prism(ctx, ox, oy, sx, sy, z0, z1, region=kit.REGION_WALL, chamfer=0.0,
           profile=None, facades=None, register=None):
    if profile is None:
        profile = _rect(ox, oy, sx, sy, chamfer)
    if register is None:
        register = facades
    if register is None:
        return kit.prism(ctx, profile, z0, z1, region=region)
    return kit.prism(ctx, profile, z0, z1, region=region, register=register)


def _cornice(ctx, ox, oy, sx, sy, z, width=0.20, height=0.14):
    return kit.cornice(ctx, _rect(ox, oy, sx, sy), z, width=width, height=height)


def _parapet(ctx, ox, oy, sx, sy, z, thickness=0.12, height=0.55):
    return kit.parapet(ctx, _rect(ox, oy, sx, sy), z, height=height,
                       thickness=thickness)


def _gable(ctx, ox, oy, sx, sy, z0, rise, ridge_axis="x", overhang=0.22):
    return kit.gable_roof(ctx, _rect(ox, oy, sx, sy), z0, rise,
                          ridge_axis=ridge_axis, overhang=overhang)


def _hip(ctx, ox, oy, sx, sy, z0, rise, overhang=0.20):
    return kit.hip_roof(ctx, _rect(ox, oy, sx, sy), z0, rise, overhang=overhang)


def _shed(ctx, ox, oy, sx, sy, z0, rise, fall_axis="y", fall_dir=-1,
          overhang=0.16):
    axis = fall_axis if fall_dir >= 0 else "-" + fall_axis
    return kit.shed_roof(ctx, _rect(ox, oy, sx, sy), z0, rise,
                         fall_axis=axis, overhang=overhang)


def _slab(ctx, ox, oy, sx, sy, z0, thickness=0.10):
    return kit.roof_slab(ctx, _rect(ox, oy, sx, sy), z0, thickness=thickness)


def _mansard(ctx, ox, oy, sx, sy, z0, rise, inset=0.42):
    return kit.mansard_roof(ctx, _rect(ox, oy, sx, sy), z0, rise=rise,
                            inset=inset)


def _steps(ctx, x, y, width, depth, z0, count=3):
    return kit.steps(ctx, x, y, z0, width=width, depth=depth, count=count)


def _chimney(ctx, x, y, sx, sy, z0, height):
    return kit.chimney(ctx, x, y, z0, height, size=(sx + sy) * 0.5)


def _plinth(ctx, ox, oy, sx, sy, z1, scale=1.08):
    _prism(ctx, ox, oy, sx * scale, sy * scale, 0.0, z1,
           region=kit.REGION_BASE, register=False)


def _tiers(ctx, recipe, w, d, rows):
    last = len(rows) - 1
    for i, (start, end, scale) in enumerate(rows):
        z0 = 0.0 if start == 0 else _story_z(recipe, start)
        z1 = recipe.wall_h if i == last else _story_z(recipe, end)
        _prism(ctx, 0.0, 0.0, w * scale, d * scale, z0, z1)
        _cornice(ctx, 0.0, 0.0, w * scale, d * scale, z1,
                 width=0.14, height=0.1)


def build_hearth_cottage(ctx, recipe):
    w, d, z1 = recipe.width, recipe.depth, recipe.wall_h
    _plinth(ctx, 0.0, 0.0, w, d, recipe.ground_h)
    _prism(ctx, 0.0, 0.0, w, d, recipe.ground_h, z1)
    _quoins(ctx, 0.0, 0.0, w, d, recipe.ground_h, z1)
    _cornice(ctx, 0.0, 0.0, w, d, z1, width=0.16, height=0.12)
    _gable(ctx, 0.0, 0.0, w, d, z1, 1.45, ridge_axis="x", overhang=0.38)
    porch_w, porch_d, porch_y = 4.4, 1.7, -d * 0.5 - 0.85
    _posts(ctx, ((-1.85, porch_y - 0.45), (1.85, porch_y - 0.45)),
           0.0, recipe.ground_h + 2.35)
    _shed(ctx, 0.0, porch_y, porch_w, porch_d, recipe.ground_h + 2.25,
                  0.85, fall_axis="y", fall_dir=-1, overhang=0.16)
    _steps(ctx, 0.0, porch_y - 1.1, 2.1, 0.95, 0.0, count=3)
    _chimney(ctx, 2.15, 1.1, 0.55, 0.48, z1 + 0.85, 1.55)


def build_long_shotgun(ctx, recipe):
    w, d, z1 = recipe.width, recipe.depth, recipe.wall_h
    _plinth(ctx, 0.0, 0.0, w, d, recipe.ground_h, scale=1.06)
    _prism(ctx, 0.0, 0.0, w, d, recipe.ground_h, z1)
    _gable(ctx, 0.0, 0.0, w, d, z1, 1.35, ridge_axis="y", overhang=0.32)
    stoop_y = -d * 0.5 - 0.7
    _posts(ctx, ((-0.7, stoop_y), (0.7, stoop_y)), 0.0, recipe.ground_h + 2.15)
    _steps(ctx, 0.0, stoop_y - 0.55, 1.7, 0.8, 0.0, count=3)


def build_hip_bungalow(ctx, recipe):
    w, d, z1 = recipe.width, recipe.depth, recipe.wall_h
    _plinth(ctx, 0.0, 0.0, w, d, recipe.ground_h)
    _prism(ctx, 0.0, 0.0, w, d, recipe.ground_h, z1)
    _hip(ctx, 0.0, 0.0, w, d, z1, 1.55, overhang=0.42)
    porch_w, porch_d, porch_y = w * 0.72, 2.0, -d * 0.5 - 0.9
    _posts(ctx, ((-porch_w * 0.4, porch_y - 0.55),
                 (porch_w * 0.4, porch_y - 0.55)),
           0.0, recipe.ground_h + 2.4)
    _hip(ctx, 0.0, porch_y, porch_w, porch_d, recipe.ground_h + 2.3,
                 0.95, overhang=0.18)
    _steps(ctx, 0.0, porch_y - 1.1, 2.0, 0.85, 0.0, count=3)


def build_saltbox_home(ctx, recipe):
    w, d = recipe.width, recipe.depth
    front_d, back_d = d * 0.58, d * 0.46
    front_y = -d * 0.5 + front_d * 0.5
    back_y = d * 0.5 - back_d * 0.5
    _plinth(ctx, 0.0, 0.0, w, d, recipe.ground_h, scale=1.05)
    _prism(ctx, 0.0, front_y, w, front_d, recipe.ground_h, recipe.wall_h)
    _prism(ctx, 0.0, back_y, w, back_d, recipe.ground_h,
              recipe.ground_h + kit.STORY)
    _shed(ctx, 0.0, 0.0, w + 0.45, d + 0.55, recipe.wall_h - 0.08, 2.55,
                  fall_axis="y", fall_dir=1, overhang=0.3)
    _steps(ctx, 0.0, -d * 0.5 - 0.7, 1.9, 0.85, 0.0, count=3)
    _chimney(ctx, -1.8, front_y + 0.4, 0.5, 0.46, recipe.wall_h + 0.2, 1.35)


def build_ell_cottage(ctx, recipe):
    # One L prism only — do not add a second wing box.
    w, d, z1 = recipe.width, recipe.depth, recipe.wall_h
    arm_x, arm_y = w * 0.42, d * 0.55
    _plinth(ctx, 0.0, 0.0, w, d, recipe.ground_h, scale=1.04)
    _prism(ctx, 0.0, 0.0, w, d, recipe.ground_h, z1,
              profile=kit.l_profile(w, d, arm_x, arm_y))
    _gable(ctx, 0.0, -d * 0.5 + arm_y * 0.5, w + 0.35, arm_y + 0.35,
                   z1, 1.35, ridge_axis="x", overhang=0.22)
    _gable(ctx, -w * 0.5 + arm_x * 0.5,
                   -d * 0.5 + arm_y + (d - arm_y) * 0.5,
                   arm_x + 0.3, (d - arm_y) + 0.3, z1, 1.2,
                   ridge_axis="y", overhang=0.2)
    _steps(ctx, 0.0, -d * 0.5 - 0.65, 1.8, 0.8, 0.0, count=3)


def build_apse_cabin(ctx, recipe):
    w, d, z1 = recipe.width, recipe.depth, recipe.wall_h
    _plinth(ctx, 0.0, 0.0, w, d, recipe.ground_h, scale=1.05)
    _prism(ctx, 0.0, 0.0, w, d, recipe.ground_h, z1,
              profile=kit.stadium_profile(w, d))
    _hip(ctx, 0.0, 0.0, w + 0.25, d + 0.25, z1, 1.5, overhang=0.28)
    _steps(ctx, 0.0, -d * 0.5 - 0.6, 1.8, 0.75, 0.0, count=3)
    _chimney(ctx, 0.0, d * 0.18, 0.48, 0.44, z1 + 0.7, 1.25)


def build_turret_house(ctx, recipe):
    w, d, z1 = recipe.width, recipe.depth, recipe.wall_h
    _plinth(ctx, 0.0, 0.0, w, d, recipe.ground_h)
    _prism(ctx, 0.0, 0.0, w, d, recipe.ground_h, z1)
    _gable(ctx, 0.0, 0.0, w, d, z1, 1.3, ridge_axis="x", overhang=0.3)
    kit.cylinder(ctx, w * 0.38, d * 0.38, 1.45, 0.0, z1 + 0.85, segments=14,
                 region=kit.REGION_WALL, register=True)
    kit.cone_roof(ctx, w * 0.38, d * 0.38, 1.53, z1 + 0.85, 1.85, segments=14)
    _steps(ctx, 0.0, -d * 0.5 - 0.65, 1.85, 0.8, 0.0, count=3)


def build_shed_studio(ctx, recipe):
    w, d, z1 = recipe.width, recipe.depth, recipe.wall_h
    _plinth(ctx, 0.0, 0.0, w, d, recipe.ground_h, scale=1.05)
    _prism(ctx, 0.0, 0.0, w, d, recipe.ground_h, z1, chamfer=0.55)
    _prism(ctx, 0.0, d * 0.12, w * 0.72, d * 0.55, z1, z1 + 1.35,
              chamfer=0.2, register=True)
    _shed(ctx, 0.0, 0.0, w + 0.4, d + 0.45, z1 + 1.35, 1.7,
                  fall_axis="y", fall_dir=-1, overhang=0.28)
    _steps(ctx, 0.0, -d * 0.5 - 0.6, 1.7, 0.75, 0.0, count=3)


def build_court_cottage(ctx, recipe):
    w, d, z1 = recipe.width, recipe.depth, recipe.wall_h
    arm = d * 0.38
    _plinth(ctx, 0.0, 0.0, w, d, recipe.ground_h, scale=1.03)
    _prism(ctx, 0.0, 0.0, w, d, recipe.ground_h, z1,
              profile=kit.u_profile(w, d, arm))
    _hip(ctx, 0.0, d * 0.5 - arm * 0.5, w + 0.2, arm + 0.25, z1, 1.2,
                 overhang=0.18)
    wing_x = w * 0.5 - arm * 0.45
    _hip(ctx, -wing_x, -d * 0.08, arm + 0.2, d * 0.72, z1, 1.05,
                 overhang=0.14)
    _hip(ctx, wing_x, -d * 0.08, arm + 0.2, d * 0.72, z1, 1.05,
                 overhang=0.14)
    _steps(ctx, 0.0, -d * 0.5 + 0.4, 1.6, 0.7, 0.0, count=2)


def build_drum_hut(ctx, recipe):
    radius = min(recipe.width, recipe.depth) * 0.5
    z1 = recipe.wall_h
    kit.cylinder(ctx, 0.0, 0.0, radius + 0.18, 0.0, recipe.ground_h,
                 segments=16, region=kit.REGION_BASE, register=False)
    kit.cylinder(ctx, 0.0, 0.0, radius, recipe.ground_h, z1,
                 segments=16, region=kit.REGION_WALL, register=True)
    kit.cone_roof(ctx, 0.0, 0.0, radius + 0.2, z1, 2.15, segments=16)
    _steps(ctx, 0.0, -radius - 0.55, 1.6, 0.7, 0.0, count=3)


def build_brick_walkup(ctx, recipe):
    w, d = recipe.width, recipe.depth
    base_top = _story_z(recipe, 1)
    _plinth(ctx, 0.0, 0.0, w, d, recipe.ground_h, scale=1.06)
    _prism(ctx, 0.0, 0.0, w * 1.04, d * 1.04, recipe.ground_h, base_top,
              region=kit.REGION_BASE, register=True)
    _prism(ctx, 0.0, 0.0, w, d, base_top, recipe.wall_h)
    kit.pilasters(ctx, _rect(0.0, 0.0, w, d), recipe.ground_h, recipe.wall_h,
                  width=0.32, depth=0.12)
    _cornice(ctx, 0.0, 0.0, w, d, recipe.wall_h, width=0.22, height=0.18)
    _parapet(ctx, 0.0, 0.0, w, d, recipe.wall_h, thickness=0.16, height=0.55)


def build_court_walkup(ctx, recipe):
    w, d = recipe.width, recipe.depth
    _prism(ctx, 0.0, 0.0, w, d, 0.0, recipe.wall_h,
              profile=kit.u_profile(w, d, d * 0.34))
    _cornice(ctx, 0.0, 0.0, w, d, recipe.wall_h, width=0.18, height=0.14)
    _parapet(ctx, 0.0, 0.0, w, d, recipe.wall_h, thickness=0.14, height=0.5)


def build_step_walkup(ctx, recipe):
    w, d = recipe.width, recipe.depth
    split = _story_z(recipe, 3)
    _prism(ctx, 0.0, 0.0, w, d, 0.0, split)
    _prism(ctx, w * 0.12, 0.0, w * 0.76, d * 0.92, split, recipe.wall_h)
    _cornice(ctx, w * 0.12, 0.0, w * 0.76, d * 0.92, recipe.wall_h)
    _parapet(ctx, w * 0.12, 0.0, w * 0.76, d * 0.92, recipe.wall_h)


def build_bay_walkup(ctx, recipe):
    w, d = recipe.width, recipe.depth
    _prism(ctx, 0.0, 0.0, w, d, 0.0, recipe.wall_h)
    for x in (-w * 0.28, w * 0.28):
        _prism(ctx, x, -d * 0.5 - 0.38, 2.15, 0.85,
                  recipe.ground_h + 0.35, recipe.wall_h - 0.4,
                  region=kit.REGION_ACCENT, register=True)
    _cornice(ctx, 0.0, 0.0, w, d, recipe.wall_h)
    _parapet(ctx, 0.0, 0.0, w, d, recipe.wall_h)


def build_twin_bar(ctx, recipe):
    w, d = recipe.width, recipe.depth
    bar_w, gap = w * 0.38, w * 0.12
    _prism(ctx, -(bar_w + gap) * 0.5, 0.0, bar_w, d, 0.0, recipe.wall_h)
    _prism(ctx, (bar_w + gap) * 0.5, 0.0, bar_w, d, 0.0, recipe.wall_h)
    _prism(ctx, 0.0, 0.0, gap + 0.8, d * 0.42, 0.0, _story_z(recipe, 2),
              register=True)
    _parapet(ctx, -(bar_w + gap) * 0.5, 0.0, bar_w, d, recipe.wall_h)
    _parapet(ctx, (bar_w + gap) * 0.5, 0.0, bar_w, d, recipe.wall_h)


def build_apse_block(ctx, recipe):
    w, d = recipe.width, recipe.depth
    _prism(ctx, 0.0, 0.0, w, d, 0.0, recipe.wall_h,
              profile=kit.stadium_profile(w, d))
    _cornice(ctx, 0.0, 0.0, w, d, recipe.wall_h, width=0.16, height=0.14)
    _parapet(ctx, 0.0, 0.0, w, d, recipe.wall_h)


def build_turret_block(ctx, recipe):
    w, d = recipe.width, recipe.depth
    _prism(ctx, 0.0, 0.0, w, d, 0.0, recipe.wall_h)
    kit.cylinder(ctx, w * 0.36, d * 0.34, 2.15, 0.0, recipe.wall_h + 2.4,
                 segments=14, register=True)
    kit.cone_roof(ctx, w * 0.36, d * 0.34, 2.25, recipe.wall_h + 2.4, 2.6)
    _parapet(ctx, 0.0, 0.0, w, d, recipe.wall_h)


def build_mansard_block(ctx, recipe):
    w, d = recipe.width, recipe.depth
    shaft_top = recipe.wall_h - kit.STORY * 0.85
    _prism(ctx, 0.0, 0.0, w, d, 0.0, shaft_top)
    _mansard(ctx, 0.0, 0.0, w, d, shaft_top, kit.STORY * 0.95, inset=0.42)
    _cornice(ctx, 0.0, 0.0, w, d, shaft_top, width=0.2, height=0.14)


def build_balcony_slab(ctx, recipe):
    w, d = recipe.width, recipe.depth
    _prism(ctx, 0.0, 0.0, w, d, 0.0, recipe.wall_h)
    for story in range(1, recipe.stories):
        z = _story_z(recipe, story) - 0.14
        _box(ctx, (-w * 0.48, -d * 0.5 - 0.55, z),
             (w * 0.48, -d * 0.5 - 0.06, z + 0.09), kit.REGION_TRIM)
    _parapet(ctx, 0.0, 0.0, w, d, recipe.wall_h, thickness=0.12, height=0.42)


def build_podium_bar(ctx, recipe):
    w, d = recipe.width, recipe.depth
    podium = _story_z(recipe, 2)
    _prism(ctx, 0.0, 0.0, w, d, 0.0, podium, region=kit.REGION_BASE,
              register=True)
    _prism(ctx, 0.0, 0.0, w * 0.78, d * 0.72, podium, recipe.wall_h)
    _cornice(ctx, 0.0, 0.0, w, d, podium)
    _parapet(ctx, 0.0, 0.0, w * 0.78, d * 0.72, recipe.wall_h)


def build_shop_terrace(ctx, recipe):
    w, d = recipe.width, recipe.depth
    shop = _story_z(recipe, 1)
    _prism(ctx, 0.0, 0.0, w, d, 0.0, shop, region=kit.REGION_BASE,
              register=True)
    _prism(ctx, 0.0, 0.0, w * 0.96, d * 0.94, shop, recipe.wall_h)
    kit.pilasters(ctx, _rect(0.0, 0.0, w, d), 0.0, shop, width=0.26, depth=0.1)
    _cornice(ctx, 0.0, 0.0, w, d, shop, width=0.2, height=0.16)
    _parapet(ctx, 0.0, 0.0, w * 0.96, d * 0.94, recipe.wall_h)
    _box(ctx, (-w * 0.46, -d * 0.5 - 0.55, shop - 0.12),
         (w * 0.46, -d * 0.5 - 0.08, shop - 0.02), kit.REGION_TRIM)


def build_market_nave(ctx, recipe):
    w, d = recipe.width, recipe.depth
    aisle = recipe.ground_h + kit.STORY * 1.35
    nave = recipe.wall_h
    _prism(ctx, 0.0, 0.0, w, d, 0.0, aisle, register=True)
    _prism(ctx, 0.0, 0.0, w * 0.48, d * 0.88, aisle, nave, register=True)
    _prism(ctx, 0.0, 0.0, w * 0.36, d * 0.7, nave, nave + 1.15,
              region=kit.REGION_TRIM, register=True)
    _gable(ctx, 0.0, 0.0, w * 0.52, d * 0.92, nave + 1.1, 2.4,
                   ridge_axis="y", overhang=0.35)


def build_clock_block(ctx, recipe):
    w, d = recipe.width, recipe.depth
    _prism(ctx, 0.0, 0.0, w, d, 0.0, recipe.wall_h)
    _cornice(ctx, 0.0, 0.0, w, d, recipe.wall_h)
    tw, td, tx, ty = 3.6, 3.4, -w * 0.32, -d * 0.28
    tower_h = recipe.wall_h + 4.8
    _prism(ctx, tx, ty, tw, td, 0.0, tower_h, region=kit.REGION_ACCENT,
              register=True)
    _hip(ctx, tx, ty, tw + 0.2, td + 0.2, tower_h, 1.6, overhang=0.16)
    _box(ctx, (tx - 0.85, ty - td * 0.52, tower_h - 2.6),
         (tx + 0.85, ty - td * 0.46, tower_h - 1.1), kit.REGION_ACCENT)


def build_arcade_block(ctx, recipe):
    w, d = recipe.width, recipe.depth
    arcade = _story_z(recipe, 1)
    _prism(ctx, 0.0, 0.0, w, d, 0.0, recipe.wall_h)
    kit.pilasters(ctx, _rect(0.0, 0.0, w, d), 0.0, arcade, width=0.3, depth=0.14)
    _cornice(ctx, 0.0, 0.0, w, d, arcade, width=0.2, height=0.16)
    _parapet(ctx, 0.0, 0.0, w, d, recipe.wall_h)


def build_sawtooth_works(ctx, recipe):
    w, d = recipe.width, recipe.depth
    hall = recipe.ground_h + kit.STORY * 1.7
    _prism(ctx, 0.0, 0.0, w, d, 0.0, hall)
    tooth_w = w / 3.0
    for i in range(3):
        ox = -w * 0.5 + tooth_w * (i + 0.5)
        _shed(ctx, ox, 0.0, tooth_w + 0.15, d + 0.2, hall, 2.15,
                      fall_axis="x", fall_dir=-1, overhang=0.12)


def build_civic_rotunda(ctx, recipe):
    w, d = recipe.width, recipe.depth
    wing_w, wing_d = w * 0.34, d * 0.72
    _prism(ctx, -w * 0.33, 0.0, wing_w, wing_d, 0.0, recipe.wall_h)
    _prism(ctx, w * 0.33, 0.0, wing_w, wing_d, 0.0, recipe.wall_h)
    radius = min(w, d) * 0.28
    kit.cylinder(ctx, 0.0, 0.0, radius, 0.0, recipe.wall_h + 1.4,
                 segments=16, register=True)
    kit.dome_roof(ctx, 0.0, 0.0, radius + 0.15, recipe.wall_h + 1.4, 3.2,
                  segments=16)
    _cornice(ctx, -w * 0.33, 0.0, wing_w, wing_d, recipe.wall_h)
    _cornice(ctx, w * 0.33, 0.0, wing_w, wing_d, recipe.wall_h)


def build_hotel_h(ctx, recipe):
    w, d = recipe.width, recipe.depth
    _prism(ctx, 0.0, 0.0, w, d, 0.0, recipe.wall_h,
              profile=kit.h_profile(w, d, bar=d * 0.28, stem=w * 0.22))
    _cornice(ctx, 0.0, 0.0, w, d, recipe.wall_h)
    _parapet(ctx, 0.0, 0.0, w, d, recipe.wall_h)


def build_grid_office(ctx, recipe):
    w, d = recipe.width, recipe.depth
    _prism(ctx, 0.0, 0.0, w, d, 0.0, recipe.wall_h)
    kit.fins(ctx, _rect(0.0, 0.0, w, d), recipe.ground_h, recipe.wall_h,
             width=0.1, depth=0.16)
    _slab(ctx, 0.0, 0.0, w + 0.55, d + 0.55, recipe.wall_h,
                  thickness=0.22)
    _parapet(ctx, 0.0, 0.0, w, d, recipe.wall_h + 0.22, thickness=0.12,
                height=0.4)


def build_playhouse(ctx, recipe):
    w, d = recipe.width, recipe.depth
    hall = recipe.wall_h
    _prism(ctx, 0.0, -d * 0.08, w, d * 0.78, 0.0, hall)
    fly_h = hall + kit.STORY * 1.65
    _prism(ctx, 0.0, d * 0.32, w * 0.62, d * 0.36, 0.0, fly_h,
              region=kit.REGION_ACCENT, register=True)
    _gable(ctx, 0.0, -d * 0.08, w + 0.3, d * 0.82, hall, 2.1,
                   ridge_axis="x", overhang=0.28)
    _slab(ctx, 0.0, d * 0.32, w * 0.66, d * 0.4, fly_h, thickness=0.16)


def build_vault_hall(ctx, recipe):
    w, d = recipe.width, recipe.depth
    walls = recipe.ground_h + kit.STORY * 1.55
    _prism(ctx, 0.0, 0.0, w, d, 0.0, walls)
    kit.barrel_vault(ctx, 0.0, 0.0, w * 0.92, d * 0.88, walls, 3.4,
                     axis="y", segments=10)


def build_setback_tower(ctx, recipe):
    w, d = recipe.width, recipe.depth
    _tiers(ctx, recipe, w, d, ((0, 5, 1.00), (5, 9, 0.78), (9, 12, 0.60),
                              (12, 14, 0.44)))
    _parapet(ctx, 0.0, 0.0, w * 0.44, d * 0.44, recipe.wall_h)
    kit.antenna(ctx, 0.0, 0.0, recipe.wall_h + 0.5, 5.5)


def build_point_tower(ctx, recipe):
    w, d = recipe.width, recipe.depth
    shaft = recipe.wall_h - 4.2
    _prism(ctx, 0.0, 0.0, w, d, 0.0, shaft)
    _prism(ctx, 0.0, 0.0, w * 0.62, d * 0.62, shaft, recipe.wall_h)
    kit.cone_roof(ctx, 0.0, 0.0, min(w, d) * 0.38, recipe.wall_h, 6.4,
                  segments=8)
    kit.antenna(ctx, 0.0, 0.0, recipe.wall_h + 6.2, 4.2)


def build_slant_tower(ctx, recipe):
    w, d = recipe.width, recipe.depth
    slices = 4
    slice_h = recipe.stories / float(slices)
    for i in range(slices):
        z0 = 0.0 if i == 0 else _story_z(recipe, int(round(i * slice_h)))
        z1 = (recipe.wall_h if i == slices - 1
              else _story_z(recipe, int(round((i + 1) * slice_h))))
        _prism(ctx, 0.0, (i - 1.4) * 1.15, w * (1.0 - i * 0.06), d * 0.88,
                  z0, z1)
    _parapet(ctx, 0.0, 1.84, w * 0.82, d * 0.88, recipe.wall_h)


def build_drum_crown(ctx, recipe):
    w, d = recipe.width, recipe.depth
    crown = recipe.wall_h - kit.STORY * 2.1
    _prism(ctx, 0.0, 0.0, w, d, 0.0, crown)
    radius = min(w, d) * 0.42
    kit.cylinder(ctx, 0.0, 0.0, radius, crown, recipe.wall_h + 1.1,
                 segments=16, register=True)
    _cornice(ctx, 0.0, 0.0, radius * 2.05, radius * 2.05, recipe.wall_h + 1.1)
    _slab(ctx, 0.0, 0.0, radius * 2.1, radius * 2.1, recipe.wall_h + 1.1,
                  thickness=0.18)
    kit.antenna(ctx, 0.0, 0.0, recipe.wall_h + 1.3, 5.8)


def build_twin_slab(ctx, recipe):
    w, d = recipe.width, recipe.depth
    slab_w = w * 0.36
    _prism(ctx, -w * 0.28, 0.0, slab_w, d, 0.0, recipe.wall_h)
    _prism(ctx, w * 0.28, 0.0, slab_w, d, 0.0, recipe.wall_h)
    _prism(ctx, 0.0, 0.0, w * 0.22, d * 0.34, 0.0, _story_z(recipe, 3),
              region=kit.REGION_BASE, register=True)
    _parapet(ctx, -w * 0.28, 0.0, slab_w, d, recipe.wall_h)
    _parapet(ctx, w * 0.28, 0.0, slab_w, d, recipe.wall_h)


def build_chamfer_tower(ctx, recipe):
    w, d = recipe.width, recipe.depth
    _prism(ctx, 0.0, 0.0, w, d, 0.0, recipe.wall_h, chamfer=w * 0.14)
    _cornice(ctx, 0.0, 0.0, w, d, recipe.wall_h, width=0.18, height=0.14)
    _parapet(ctx, 0.0, 0.0, w * 0.92, d * 0.92, recipe.wall_h)
    kit.antenna(ctx, 0.0, 0.0, recipe.wall_h + 0.5, 6.2)


def build_podium_shaft(ctx, recipe):
    w, d = recipe.width, recipe.depth
    podium = _story_z(recipe, 3)
    _prism(ctx, 0.0, 0.0, w, d, 0.0, podium, region=kit.REGION_BASE,
              register=True)
    _prism(ctx, 0.0, 0.0, w * 0.52, d * 0.48, podium, recipe.wall_h)
    _cornice(ctx, 0.0, 0.0, w, d, podium)
    _parapet(ctx, 0.0, 0.0, w * 0.52, d * 0.48, recipe.wall_h)
    kit.antenna(ctx, 0.0, 0.0, recipe.wall_h + 0.45, 6.8)


def build_offset_stack(ctx, recipe):
    w, d = recipe.width, recipe.depth
    slices = ((0, 4, -1.1, -0.6, 1.0), (4, 8, 1.0, 0.5, 0.86),
              (8, 11, -0.4, 1.1, 0.72), (11, 14, 0.7, -0.3, 0.58))
    for start, end, ox, oy, scale in slices:
        z0 = 0.0 if start == 0 else _story_z(recipe, start)
        z1 = recipe.wall_h if end == recipe.stories else _story_z(recipe, end)
        _prism(ctx, ox, oy, w * scale, d * scale, z0, z1)
    _parapet(ctx, 0.7, -0.3, w * 0.58, d * 0.58, recipe.wall_h)


def build_round_tower(ctx, recipe):
    radius = min(recipe.width, recipe.depth) * 0.5
    kit.cylinder(ctx, 0.0, 0.0, radius, 0.0, recipe.wall_h, segments=16,
                 register=True)
    kit.cylinder(ctx, 0.0, 0.0, radius * 0.72, recipe.wall_h,
                 recipe.wall_h + 2.4, segments=16, register=True,
                 region=kit.REGION_TRIM)
    kit.cone_roof(ctx, 0.0, 0.0, radius * 0.78, recipe.wall_h + 2.4, 3.8)
    kit.antenna(ctx, 0.0, 0.0, recipe.wall_h + 6.1, 4.6)


def build_cross_tower(ctx, recipe):
    w, d = recipe.width, recipe.depth
    _prism(ctx, 0.0, 0.0, w, d, 0.0, recipe.wall_h,
              profile=kit.plus_profile(w, d, min(w, d) * 0.34))
    _cornice(ctx, 0.0, 0.0, w * 0.4, d * 0.4, recipe.wall_h)
    _parapet(ctx, 0.0, 0.0, w * 0.36, d * 0.36, recipe.wall_h)
    kit.antenna(ctx, 0.0, 0.0, recipe.wall_h + 0.5, 6.0)


def build_deco_spire(ctx, recipe):
    w, d = recipe.width, recipe.depth
    _tiers(ctx, recipe, w, d, ((0, 6, 1.00), (6, 16, 0.82), (16, 26, 0.64),
                              (26, 33, 0.46), (33, 36, 0.30)))
    kit.cone_roof(ctx, 0.0, 0.0, min(w, d) * 0.18, recipe.wall_h, 8.8,
                  segments=8)
    kit.antenna(ctx, 0.0, 0.0, recipe.wall_h + 8.6, 7.5)


def build_glass_slab(ctx, recipe):
    w, d = recipe.width, recipe.depth
    podium = _story_z(recipe, 3)
    _prism(ctx, 0.0, 0.0, w * 1.12, d * 1.04, 0.0, podium,
              region=kit.REGION_BASE, register=True)
    _prism(ctx, 0.0, 0.0, w, d, podium, recipe.wall_h)
    kit.fins(ctx, _rect(0.0, 0.0, w, d), podium, recipe.wall_h,
             width=0.08, depth=0.12)
    _slab(ctx, 0.0, 0.0, w + 0.4, d + 0.4, recipe.wall_h, thickness=0.2)
    kit.antenna(ctx, 0.0, d * 0.2, recipe.wall_h + 0.2, 8.5)


def build_taper_prism(ctx, recipe):
    w, d = recipe.width, recipe.depth
    _tiers(ctx, recipe, w, d, ((0, 7, 1.00), (7, 14, 0.87), (14, 21, 0.74),
                              (21, 28, 0.61), (28, 34, 0.48)))
    kit.antenna(ctx, 0.0, 0.0, recipe.wall_h + 0.4, 9.2)


def build_crown_drum_sky(ctx, recipe):
    w, d = recipe.width, recipe.depth
    crown = recipe.wall_h - kit.STORY * 3.2
    _prism(ctx, 0.0, 0.0, w, d, 0.0, crown)
    radius = min(w, d) * 0.4
    kit.cylinder(ctx, 0.0, 0.0, radius, crown, recipe.wall_h + 1.6,
                 segments=16, register=True)
    kit.dome_roof(ctx, 0.0, 0.0, radius + 0.12, recipe.wall_h + 1.6, 4.4)
    kit.antenna(ctx, 0.0, 0.0, recipe.wall_h + 5.8, 7.2)


def build_bundle_tubes(ctx, recipe):
    w, d = recipe.width, recipe.depth
    radius = min(w, d) * 0.2
    for ox, oy, scale in ((-0.28, -0.22, 1.00), (0.26, -0.18, 0.88),
                          (-0.2, 0.24, 0.76), (0.24, 0.22, 0.64)):
        top = recipe.ground_h + recipe.stories * kit.STORY * scale
        kit.cylinder(ctx, w * ox, d * oy, radius, 0.0, top, segments=12,
                     register=True)
        _slab(ctx, w * ox, d * oy, radius * 2.1, radius * 2.1, top,
                      thickness=0.16)
    kit.antenna(ctx, -w * 0.28, -d * 0.22, recipe.wall_h + 0.2, 8.0)


def build_twist_stack(ctx, recipe):
    w, d = recipe.width, recipe.depth
    slices = 6
    span = recipe.stories / float(slices)
    for i in range(slices):
        angle = i * 0.18
        scale = 1.0 - i * 0.05
        profile = [kit.rotate_xy(point, angle)
                   for point in kit.rect_profile(w * scale, d * scale)]
        z0 = 0.0 if i == 0 else _story_z(recipe, int(round(i * span)))
        z1 = (recipe.wall_h if i == slices - 1
              else _story_z(recipe, int(round((i + 1) * span))))
        _prism(ctx, 0.0, 0.0, w * scale, d * scale, z0, z1, profile=profile)
    kit.antenna(ctx, 0.0, 0.0, recipe.wall_h + 0.4, 8.4)


def build_pagoda_steps(ctx, recipe):
    w, d = recipe.width, recipe.depth
    tiers = 6
    span = recipe.stories / float(tiers)
    for i in range(tiers):
        scale = 1.0 - i * 0.11
        z0 = 0.0 if i == 0 else _story_z(recipe, int(round(i * span)))
        z1 = (recipe.wall_h if i == tiers - 1
              else _story_z(recipe, int(round((i + 1) * span))))
        _prism(ctx, 0.0, 0.0, w * scale, d * scale, z0, z1)
        _slab(ctx, 0.0, 0.0, w * scale + 0.85, d * scale + 0.85, z1,
                      thickness=0.16)
    _hip(ctx, 0.0, 0.0, w * 0.42, d * 0.4, recipe.wall_h + 0.16, 2.8,
                 overhang=0.2)
    kit.antenna(ctx, 0.0, 0.0, recipe.wall_h + 2.9, 6.5)


def build_needle_spire(ctx, recipe):
    w, d = recipe.width, recipe.depth
    _prism(ctx, 0.0, 0.0, w * 1.08, d * 1.08, 0.0, _story_z(recipe, 2),
              region=kit.REGION_BASE, register=True)
    _prism(ctx, 0.0, 0.0, w, d, _story_z(recipe, 2), recipe.wall_h * 0.72)
    _prism(ctx, 0.0, 0.0, w * 0.55, d * 0.55, recipe.wall_h * 0.72,
              recipe.wall_h)
    kit.cone_roof(ctx, 0.0, 0.0, min(w, d) * 0.3, recipe.wall_h, 12.5,
                  segments=8)
    kit.antenna(ctx, 0.0, 0.0, recipe.wall_h + 12.3, 9.5)


def build_twin_podium(ctx, recipe):
    w, d = recipe.width, recipe.depth
    podium = _story_z(recipe, 3)
    _prism(ctx, 0.0, 0.0, w, d, 0.0, podium, region=kit.REGION_BASE,
              register=True)
    shaft_w, shaft_d = w * 0.34, d * 0.72
    _prism(ctx, -w * 0.26, 0.0, shaft_w, shaft_d, podium, recipe.wall_h)
    _prism(ctx, w * 0.26, 0.0, shaft_w, shaft_d, podium, recipe.wall_h)
    _parapet(ctx, -w * 0.26, 0.0, shaft_w, shaft_d, recipe.wall_h)
    _parapet(ctx, w * 0.26, 0.0, shaft_w, shaft_d, recipe.wall_h)
    kit.antenna(ctx, -w * 0.26, 0.0, recipe.wall_h + 0.4, 7.4)
    kit.antenna(ctx, w * 0.26, 0.0, recipe.wall_h + 0.4, 6.2)


def build_sky_bridge(ctx, recipe):
    w, d = recipe.width, recipe.depth
    shaft_w = w * 0.32
    _prism(ctx, -w * 0.3, 0.0, shaft_w, d, 0.0, recipe.wall_h)
    _prism(ctx, w * 0.3, 0.0, shaft_w, d, 0.0, recipe.wall_h)
    bridge_z = _story_z(recipe, max(recipe.stories - 8, 8))
    _prism(ctx, 0.0, 0.0, w * 0.42, d * 0.38, bridge_z,
              bridge_z + kit.STORY * 1.15, region=kit.REGION_ACCENT,
              register=True)
    _parapet(ctx, -w * 0.3, 0.0, shaft_w, d, recipe.wall_h)
    _parapet(ctx, w * 0.3, 0.0, shaft_w, d, recipe.wall_h)
    kit.antenna(ctx, -w * 0.3, 0.0, recipe.wall_h + 0.35, 6.8)


RECIPES = (
    _recipe("hearth_cottage", "small_houses", "Hearth Cottage", 11,
            8.6, 9.4, 2, build_hearth_cottage, "Gable cottage, porch, chimney."),
    _recipe("long_shotgun", "small_houses", "Long Shotgun", 23,
            5.8, 12.4, 1, build_long_shotgun,
            "Narrow gable house, ridge along Y, stoop."),
    _recipe("hip_bungalow", "small_houses", "Hip Bungalow", 31,
            10.4, 9.8, 1, build_hip_bungalow, "Hip roof and matching porch hip."),
    _recipe("saltbox_home", "small_houses", "Saltbox Home", 47,
            8.8, 10.2, 2, build_saltbox_home, "Two boxes and a long rear shed."),
    _recipe("ell_cottage", "small_houses", "Ell Cottage", 59,
            10.6, 9.6, 2, build_ell_cottage,
            "One L-profile prism and two gables."),
    _recipe("apse_cabin", "small_houses", "Apse Cabin", 67,
            8.2, 11.0, 1, build_apse_cabin, "Stadium plan under a hip roof."),
    _recipe("turret_house", "small_houses", "Turret House", 73,
            9.2, 9.0, 2, build_turret_house, "Box, corner cylinder, and cone."),
    _recipe("shed_studio", "small_houses", "Shed Studio", 83,
            8.8, 8.4, 2, build_shed_studio,
            "Chamfer box, clerestory, shed roof."),
    _recipe("court_cottage", "small_houses", "Court Cottage", 97,
            11.2, 10.4, 1, build_court_cottage,
            "U-profile court with three hips."),
    _recipe("drum_hut", "small_houses", "Drum Hut", 101,
            8.0, 8.0, 1, build_drum_hut, "Cylinder drum and cone roof."),
    _recipe("brick_walkup", "medium_apartments", "Brick Walk-up", 113,
            14.5, 12.2, 6, build_brick_walkup,
            "Corniced brick walk-up with pilasters."),
    _recipe("court_walkup", "medium_apartments", "Court Walk-up", 127,
            16.4, 14.0, 5, build_court_walkup, "U-profile apartment court."),
    _recipe("step_walkup", "medium_apartments", "Step Walk-up", 131,
            15.2, 12.6, 6, build_step_walkup,
            "Side setback above the third storey."),
    _recipe("bay_walkup", "medium_apartments", "Bay Walk-up", 149,
            14.8, 12.0, 5, build_bay_walkup, "Projecting front bays."),
    _recipe("twin_bar", "medium_apartments", "Twin Bar", 157,
            16.8, 12.4, 6, build_twin_bar, "Paired bars with a low link."),
    _recipe("apse_block", "medium_apartments", "Apse Block", 163,
            15.6, 11.8, 5, build_apse_block, "Stadium apartment block."),
    _recipe("turret_block", "medium_apartments", "Turret Block", 173,
            15.0, 12.8, 6, build_turret_block, "Walk-up with a corner turret."),
    _recipe("mansard_block", "medium_apartments", "Mansard Block", 181,
            14.6, 12.4, 6, build_mansard_block, "Shaft under a mansard cap."),
    _recipe("balcony_slab", "medium_apartments", "Balcony Slab", 191,
            16.2, 11.4, 7, build_balcony_slab, "Slab with balcony plates."),
    _recipe("podium_bar", "medium_apartments", "Podium Bar", 193,
            16.8, 13.2, 6, build_podium_bar, "Wide podium under a narrower bar."),
    _recipe("shop_terrace", "medium_buildings", "Shop Terrace", 199,
            16.4, 12.6, 4, build_shop_terrace, "Shop base with terrace housing."),
    _recipe("market_nave", "medium_buildings", "Market Nave", 211,
            18.5, 14.8, 3, build_market_nave, "Nave, clerestory, and gable."),
    _recipe("clock_block", "medium_buildings", "Clock Block", 223,
            16.8, 13.4, 4, build_clock_block, "Civic block with a clock tower."),
    _recipe("arcade_block", "medium_buildings", "Arcade Block", 227,
            17.2, 13.0, 4, build_arcade_block, "Ground arcade and shaft."),
    _recipe("sawtooth_works", "medium_buildings", "Sawtooth Works", 233,
            18.8, 14.2, 3, build_sawtooth_works, "Workshop with three shed teeth."),
    _recipe("civic_rotunda", "medium_buildings", "Civic Rotunda", 239,
            18.0, 14.0, 3, build_civic_rotunda, "Wings around a central dome."),
    _recipe("hotel_h", "medium_buildings", "Hotel H", 241,
            18.6, 15.2, 5, build_hotel_h, "H-profile hotel."),
    _recipe("grid_office", "medium_buildings", "Grid Office", 251,
            16.8, 14.4, 5, build_grid_office, "Finned office with a cap slab."),
    _recipe("playhouse", "medium_buildings", "Playhouse", 257,
            16.4, 15.6, 3, build_playhouse, "Auditorium and fly tower."),
    _recipe("vault_hall", "medium_buildings", "Vault Hall", 263,
            18.2, 14.6, 3, build_vault_hall, "Hall under a barrel vault."),
    _recipe("setback_tower", "large_towers", "Setback Tower", 269,
            16.4, 15.2, 14, build_setback_tower, "Stepped tower setbacks."),
    _recipe("point_tower", "large_towers", "Point Tower", 271,
            15.8, 15.0, 13, build_point_tower, "Shaft with a pointed cap."),
    _recipe("slant_tower", "large_towers", "Slant Tower", 277,
            15.6, 14.8, 13, build_slant_tower, "Sheared stacked masses."),
    _recipe("drum_crown", "large_towers", "Drum Crown", 281,
            16.2, 15.4, 14, build_drum_crown, "Shaft with a drum crown."),
    _recipe("twin_slab", "large_towers", "Twin Slab", 283,
            18.4, 14.2, 12, build_twin_slab, "Paired slabs on a low link."),
    _recipe("chamfer_tower", "large_towers", "Chamfer Tower", 293,
            16.0, 16.0, 14, build_chamfer_tower, "Chamfered square shaft."),
    _recipe("podium_shaft", "large_towers", "Podium Shaft", 307,
            18.8, 16.6, 15, build_podium_shaft, "Podium under a slim shaft."),
    _recipe("offset_stack", "large_towers", "Offset Stack", 311,
            16.6, 15.4, 14, build_offset_stack, "Offset stacked boxes."),
    _recipe("round_tower", "large_towers", "Round Tower", 313,
            15.2, 15.2, 13, build_round_tower, "Cylindrical tower and cone."),
    _recipe("cross_tower", "large_towers", "Cross Tower", 317,
            17.2, 17.2, 14, build_cross_tower, "Plus-plan tower."),
    _recipe("deco_spire", "skyscrapers", "Deco Spire", 331,
            22.0, 20.4, 36, build_deco_spire,
            "Art-deco setbacks and a needle."),
    _recipe("glass_slab", "skyscrapers", "Glass Slab", 337,
            18.4, 24.0, 32, build_glass_slab, "Podium and a glass slab."),
    _recipe("taper_prism", "skyscrapers", "Taper Prism", 347,
            21.0, 19.6, 34, build_taper_prism, "Stepped tapering prism."),
    _recipe("crown_drum_sky", "skyscrapers", "Crown Drum Sky", 349,
            20.4, 19.2, 30, build_crown_drum_sky, "Shaft with a drum crown."),
    _recipe("bundle_tubes", "skyscrapers", "Bundle Tubes", 353,
            22.8, 21.4, 34, build_bundle_tubes, "Bundled cylindrical tubes."),
    _recipe("twist_stack", "skyscrapers", "Twist Stack", 359,
            20.0, 20.0, 30, build_twist_stack, "Rotated stacked floors."),
    _recipe("pagoda_steps", "skyscrapers", "Pagoda Steps", 367,
            21.6, 20.2, 32, build_pagoda_steps, "Pagoda setbacks and eaves."),
    _recipe("needle_spire", "skyscrapers", "Needle Spire", 373,
            18.8, 18.8, 40, build_needle_spire, "Slim shaft and a tall needle."),
    _recipe("twin_podium", "skyscrapers", "Twin Podium", 379,
            24.4, 18.6, 28, build_twin_podium, "Shared podium, twin shafts."),
    _recipe("sky_bridge", "skyscrapers", "Sky Bridge", 383,
            23.6, 16.8, 26, build_sky_bridge, "Twin shafts joined by a bridge."),
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
    low, high = _bounds([hull, glass])
    size = high - low
    focus = (low + high) * 0.5
    reach = max(size.x, size.y, size.z, 4.0)
    preview = previewkit.Preview(PREVIEW_DIR, samples=PREVIEW_SAMPLES)
    preview.ground(level=low.z, size=max(reach * 2.4, 14.0))
    preview.lights(focus, spread=reach * 0.45)
    preview.hero(
        focus + Vector((reach * 0.85, -reach * 1.05, reach * 0.55)),
        focus, lens=50.0)
    preview.shot(recipe.name + "_close", PREVIEW_RESOLUTION)
    preview.hero(
        focus + Vector((reach * 1.55, -reach * 2.05, reach * 0.95)),
        focus, lens=42.0)
    preview.shot(recipe.name + "_gameplay", PREVIEW_RESOLUTION)
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


def _finish_objects(ctx, recipe):
    hull = kit.finish_mesh(ctx, ctx.hull, recipe.name, kind="hull")
    glass = kit.finish_mesh(ctx, ctx.glass, recipe.name + "_glass", kind="glass")
    return hull, glass


def build_one(recipe, skip_previews=False, skip_paints=False):
    print("\n=== {} ===".format(recipe.name))
    kit.reset_scene()
    ctx = kit.BuildContext(recipe)
    recipe.builder(ctx, recipe)
    kit.dress_windows(ctx)
    window_count = len(ctx.windows)
    hull, glass = _finish_objects(ctx, recipe)
    glass.parent = hull
    hull_mat = kit.make_hull_material()
    glass_mat = kit.make_glass_material()
    _assign_material(hull, hull_mat)
    _assign_material(glass, glass_mat)
    kit.ground_objects([hull, glass])

    model_dir = os.path.join(MODEL_ROOT, recipe.category)
    os.makedirs(model_dir, exist_ok=True)
    glb_path = os.path.join(model_dir, recipe.name + ".glb")
    kit.export_glb([hull, glass], glb_path)
    checked = kit.validate_glb(glb_path)
    validation = {
        "triangle_count": checked["triangles"],
        "glb_vertex_count": checked["vertices"],
        "primitive_count": checked["primitives"],
    }

    paint_dir = os.path.join(PAINT_ROOT, recipe.category)
    os.makedirs(paint_dir, exist_ok=True)
    os.makedirs(PREVIEW_DIR, exist_ok=True)
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
    if paint_images and not skip_previews:
        strip_path = os.path.join(PREVIEW_DIR, recipe.name + "_paint_strip.png")
        kit.write_paint_strip(paint_images, strip_path)
        if hull.data.materials:
            kit.bind_paint(hull.data.materials[0], paint_images[0])
    for extra in paint_images[1:]:
        if extra.name in bpy.data.images:
            bpy.data.images.remove(extra, do_unlink=True)

    previews = {
        "close": _rel(os.path.join(PREVIEW_DIR, recipe.name + "_close.png")),
        "gameplay": _rel(os.path.join(
            PREVIEW_DIR, recipe.name + "_gameplay.png")),
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
        "measured_size": [
            round(size.x, 6), round(size.y, 6), round(size.z, 6)],
        "floor": 0.0,
        "triangle_count": validation["triangle_count"],
        "glb_vertex_count": validation["glb_vertex_count"],
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
            "primitive_count": validation.get("primitive_count", 2),
            "ground_axis": "Godot/glTF +Y",
            "scale_note": (
                "Place at any storey height; paints are interchangeable "
                "per building"),
        },
        "file_size_bytes": os.path.getsize(glb_path),
    }


def _manifest_base():
    return {
        "schema": "authored_city_building_manifest",
        "version": 1,
        "generator": "assets/source/blender/build_city_buildings.py",
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
            "external_color_paint": (
                "ten PNGs per building under assets/runtime/cities/paint/"),
            "night_windows": (
                "paint alpha plus glass COLOR_0; city_window.gdshader can "
                "drive the glass mesh when wired"),
            "skins": 0,
            "animations": 0,
        },
        "paint_styles": list(kit.PAINT_STYLES),
        "categories": [
            "small_houses", "medium_apartments", "medium_buildings",
            "large_towers", "skyscrapers",
        ],
        "assets": {},
    }


def write_manifest(entries, partial):
    manifest = _manifest_base()
    if os.path.isfile(MANIFEST_PATH):
        with open(MANIFEST_PATH, "r", encoding="utf-8") as stream:
            existing = json.load(stream)
        if existing.get("schema") == manifest["schema"]:
            if partial:
                manifest["assets"].update(existing.get("assets", {}))
            if existing.get("variants"):
                manifest["variants"] = existing["variants"]
            if existing.get("variant_paint_styles"):
                manifest["variant_paint_styles"] = existing["variant_paint_styles"]
    for entry in entries:
        manifest["assets"][entry["name"]] = entry
    ordered = {}
    assets = manifest["assets"]
    for recipe in RECIPES:
        if recipe.name in assets:
            ordered[recipe.name] = assets[recipe.name]
    for name in sorted(set(assets) - set(ordered)):
        ordered[name] = assets[name]
    manifest["assets"] = ordered
    manifest["asset_count"] = len(ordered)
    os.makedirs(os.path.dirname(MANIFEST_PATH), exist_ok=True)
    with open(MANIFEST_PATH, "w", encoding="utf-8", newline="\n") as stream:
        json.dump(manifest, stream, indent=2, sort_keys=False)
        stream.write("\n")
    return MANIFEST_PATH


def arguments():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument(
        "--only", nargs="+", metavar="NAME",
        help="build only named recipes; comma-separated names are accepted")
    parser.add_argument(
        "--category", nargs="+", metavar="CATEGORY",
        help="build only these categories")
    parser.add_argument(
        "--skip-previews", action="store_true",
        help="skip close/gameplay/night preview renders")
    parser.add_argument(
        "--skip-paints", action="store_true",
        help="skip writing the ten paint PNGs")
    blender_arguments = (
        sys.argv[sys.argv.index("--") + 1:] if "--" in sys.argv else [])
    return parser.parse_args(blender_arguments)


def selected(options):
    recipes = list(RECIPES)
    if options.category:
        cats = []
        for value in options.category:
            cats.extend(item.strip() for item in value.split(",") if item.strip())
        unknown = sorted(set(cats) - set(CATEGORY_DEFAULTS))
        if unknown:
            raise SystemExit("unknown category(-ies): " + ", ".join(unknown))
        recipes = [recipe for recipe in recipes if recipe.category in set(cats)]
    if options.only:
        names = []
        for value in options.only:
            names.extend(item.strip() for item in value.split(",") if item.strip())
        unknown = sorted(set(names) - set(RECIPE_BY_NAME))
        if unknown:
            raise SystemExit("unknown building(s): " + ", ".join(unknown))
        wanted = set(names)
        recipes = [recipe for recipe in recipes if recipe.name in wanted]
    return recipes


def main():
    options = arguments()
    recipes = selected(options)
    if not recipes:
        raise SystemExit("no city buildings selected")
    entries = []
    for recipe in recipes:
        entries.append(build_one(
            recipe,
            skip_previews=options.skip_previews,
            skip_paints=options.skip_paints,
        ))
    path = write_manifest(
        entries, partial=bool(options.only or options.category))
    print("\nCITY_BUILD_SUMMARY")
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
    print("city building build complete")


if __name__ == "__main__":
    main()
