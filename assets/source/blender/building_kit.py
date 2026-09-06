"""Shared Blender kit for authored Strange Planet city buildings.

Builders assemble a hull bmesh and a glass bmesh in world metres (Z-up), then
this module dresses windows, writes the unique four-tile paint atlas, and
exports a two-node GLB (hull + glass) with COLOR_0 and TEXCOORD_0.

Imported by build_city_buildings.py. Blender `--python` does not put this
folder on sys.path, so the builder inserts it before import.
"""

from __future__ import annotations

from dataclasses import dataclass, field
import json
import math
import os
import struct

import bmesh
import bpy
from mathutils import Matrix, Vector


STORY = 3.15
COLOR_ATTRIBUTE = "Color"
PAINT_UV_NAME = "PaintUV"

REGION_WALL = 0
REGION_TRIM = 1
REGION_ROOF = 2
REGION_BASE = 3
REGION_ACCENT = 4
REGION_GLASS = 5

REGION_TINT = {
    REGION_WALL: (0.78, 0.74, 0.68, 1.0),
    REGION_TRIM: (0.88, 0.84, 0.76, 1.0),
    REGION_ROOF: (0.40, 0.38, 0.36, 1.0),
    REGION_BASE: (0.52, 0.48, 0.44, 1.0),
    REGION_ACCENT: (0.70, 0.50, 0.38, 1.0),
    REGION_GLASS: (0.32, 0.38, 0.44, 1.0),
}

PAINT_STYLES = (
    "terracotta_bond",
    "clapboard_pine",
    "lime_stucco",
    "charcoal_panel",
    "ashlar_sand",
    "verdigris_tile",
    "chalk_wash",
    "rust_plate",
    "amethyst_stucco",
    "neon_night",
)

# Five colour skins for the old procedural lot masses (rect, gable, taper…).
VARIANT_PAINT_STYLES = (
    "terracotta_bond",
    "clapboard_pine",
    "verdigris_tile",
    "amethyst_stucco",
    "rust_plate",
)

VARIANT_SHAPES = (
    "rect",
    "cylinder",
    "rect_cap",
    "gable",
    "round_end",
    "taper",
    "point_half",
    "slant_half",
    "cyl_half",
)

KEEP_MATERIALS = ("BuildingHull", "BuildingGlass")
_JSON_CHUNK = 0x4E4F534A
_BIN_CHUNK = 0x004E4942
_SLAB = 0.10


# --------------------------------------------------------------------------
# Helpers
# --------------------------------------------------------------------------

def clamp01(value):
    return 0.0 if value < 0.0 else 1.0 if value > 1.0 else float(value)


def mix(a, b, t):
    t = clamp01(t)
    if isinstance(a, (int, float)):
        return a * (1.0 - t) + b * t
    return type(a)(mix(x, y, t) for x, y in zip(a, b))


def hash01(*values):
    h = 2166136261
    for value in values:
        h ^= int(abs(float(value)) * 100003.0) & 0xFFFFFFFF
        h = (h * 16777619) & 0xFFFFFFFF
        h ^= (h << 13) & 0xFFFFFFFF
        h ^= h >> 17
        h = (h * 2246822519) & 0xFFFFFFFF
    return (h & 0xFFFFFF) / float(0xFFFFFF)


def rotate_xy(point, angle, centre=(0.0, 0.0)):
    x = point[0] - centre[0]
    y = point[1] - centre[1]
    cosine, sine = math.cos(angle), math.sin(angle)
    return (centre[0] + x * cosine - y * sine, centre[1] + x * sine + y * cosine)


def _as_xy(point):
    return (float(point[0]), float(point[1]))


def _vec(point, z=0.0):
    if len(point) >= 3:
        return Vector((float(point[0]), float(point[1]), float(point[2])))
    return Vector((float(point[0]), float(point[1]), z))


def _profile_bounds(profile):
    xs = [p[0] for p in profile]
    ys = [p[1] for p in profile]
    return min(xs), max(xs), min(ys), max(ys)


def _profile_centre(profile):
    x0, x1, y0, y1 = _profile_bounds(profile)
    return ((x0 + x1) * 0.5, (y0 + y1) * 0.5)


def _offset_profile(profile, amount):
    count = len(profile)
    out = []
    for i in range(count):
        prev = Vector((profile[(i - 1) % count][0], profile[(i - 1) % count][1], 0.0))
        curr = Vector((profile[i][0], profile[i][1], 0.0))
        nxt = Vector((profile[(i + 1) % count][0], profile[(i + 1) % count][1], 0.0))
        d0 = curr - prev
        d1 = nxt - curr
        if d0.length < 1.0e-6 or d1.length < 1.0e-6:
            out.append(_as_xy(profile[i]))
            continue
        d0.normalize()
        d1.normalize()
        n0 = Vector((d0.y, -d0.x, 0.0))
        n1 = Vector((d1.y, -d1.x, 0.0))
        bisector = n0 + n1
        if bisector.length < 1.0e-5:
            bisector = n0
        bisector.normalize()
        miter = max(bisector.dot(n0), 0.22)
        out.append((curr.x + bisector.x * amount / miter, curr.y + bisector.y * amount / miter))
    return out


def _face_id_from_normal(normal):
    if abs(normal.x) >= abs(normal.y):
        return 1 if normal.x >= 0.0 else 3
    return 2 if normal.y >= 0.0 else 0


def _wall_local_u(recipe, face_id, point):
    if face_id == 0:
        return clamp01((point[0] + recipe.width * 0.5) / max(recipe.width, 1.0e-5))
    if face_id == 1:
        return clamp01((point[1] + recipe.depth * 0.5) / max(recipe.depth, 1.0e-5))
    if face_id == 2:
        return clamp01((recipe.width * 0.5 - point[0]) / max(recipe.width, 1.0e-5))
    return clamp01((recipe.depth * 0.5 - point[1]) / max(recipe.depth, 1.0e-5))


def _set_region(faces, region):
    for face in faces:
        if face is not None:
            face.material_index = region
    return faces


# --------------------------------------------------------------------------
# Profiles (CCW from +Z so loft sides face outward)
# --------------------------------------------------------------------------

def rect_profile(width, depth, chamfer=0.0, centre=(0.0, 0.0)):
    cx, cy = centre
    hx, hy = width * 0.5, depth * 0.5
    cut = min(max(float(chamfer), 0.0), hx * 0.45, hy * 0.45)
    if cut <= 1.0e-5:
        return [
            (cx - hx, cy - hy),
            (cx + hx, cy - hy),
            (cx + hx, cy + hy),
            (cx - hx, cy + hy),
        ]
    return [
        (cx - hx + cut, cy - hy),
        (cx + hx - cut, cy - hy),
        (cx + hx, cy - hy + cut),
        (cx + hx, cy + hy - cut),
        (cx + hx - cut, cy + hy),
        (cx - hx + cut, cy + hy),
        (cx - hx, cy + hy - cut),
        (cx - hx, cy - hy + cut),
    ]


def circle_profile(radius, segments=16, centre=(0.0, 0.0)):
    cx, cy = centre
    step = math.tau / max(int(segments), 3)
    return [
        (cx + radius * math.cos(i * step), cy + radius * math.sin(i * step))
        for i in range(max(int(segments), 3))
    ]


def stadium_profile(width, depth, segments=8, centre=(0.0, 0.0)):
    cx, cy = centre
    hx, hy = width * 0.5, depth * 0.5
    segments = max(int(segments), 4)
    points = []
    if width >= depth:
        radius = hy
        run = max(hx - radius, 0.0)
        points.append((cx - run, cy - radius))
        points.append((cx + run, cy - radius))
        for i in range(1, segments):
            angle = -math.pi * 0.5 + math.pi * i / segments
            points.append((cx + run + radius * math.cos(angle), cy + radius * math.sin(angle)))
        points.append((cx + run, cy + radius))
        points.append((cx - run, cy + radius))
        for i in range(1, segments):
            angle = math.pi * 0.5 + math.pi * i / segments
            points.append((cx - run + radius * math.cos(angle), cy + radius * math.sin(angle)))
    else:
        radius = hx
        run = max(hy - radius, 0.0)
        points.append((cx - radius, cy - run))
        points.append((cx - radius, cy + run))
        for i in range(1, segments):
            angle = math.pi - math.pi * i / segments
            points.append((cx + radius * math.cos(angle), cy + run + radius * math.sin(angle)))
        points.append((cx + radius, cy + run))
        points.append((cx + radius, cy - run))
        for i in range(1, segments):
            angle = -math.pi * i / segments
            points.append((cx + radius * math.cos(angle), cy - run + radius * math.sin(angle)))
    return points


def l_profile(width, depth, wing_x=None, wing_y=None, centre=(0.0, 0.0)):
    cx, cy = centre
    hx, hy = width * 0.5, depth * 0.5
    wing_x = width * 0.55 if wing_x is None else wing_x
    wing_y = depth * 0.55 if wing_y is None else wing_y
    inner_x = cx - hx + wing_x
    inner_y = cy - hy + wing_y
    return [
        (cx - hx, cy - hy),
        (cx + hx, cy - hy),
        (cx + hx, inner_y),
        (inner_x, inner_y),
        (inner_x, cy + hy),
        (cx - hx, cy + hy),
    ]


def u_profile(width, depth, thickness=None, centre=(0.0, 0.0)):
    cx, cy = centre
    hx, hy = width * 0.5, depth * 0.5
    thick = min(width, depth) * 0.32 if thickness is None else thickness
    thick = min(thick, width * 0.42, depth * 0.42)
    return [
        (cx - hx, cy - hy),
        (cx - hx + thick, cy - hy),
        (cx - hx + thick, cy + hy - thick),
        (cx + hx - thick, cy + hy - thick),
        (cx + hx - thick, cy - hy),
        (cx + hx, cy - hy),
        (cx + hx, cy + hy),
        (cx - hx, cy + hy),
    ]


def h_profile(width, depth, bar=None, stem=None, centre=(0.0, 0.0)):
    cx, cy = centre
    hx, hy = width * 0.5, depth * 0.5
    stem = min(width, depth) * 0.28 if stem is None else stem
    bar = depth * 0.34 if bar is None else bar
    stem = min(stem, width * 0.36)
    bar = min(bar, depth * 0.7)
    left = cx - hx + stem
    right = cx + hx - stem
    low = cy - bar * 0.5
    high = cy + bar * 0.5
    return [
        (cx - hx, cy - hy),
        (left, cy - hy),
        (left, low),
        (right, low),
        (right, cy - hy),
        (cx + hx, cy - hy),
        (cx + hx, cy + hy),
        (right, cy + hy),
        (right, high),
        (left, high),
        (left, cy + hy),
        (cx - hx, cy + hy),
    ]


def plus_profile(width, depth, arm=None, centre=(0.0, 0.0)):
    cx, cy = centre
    hx, hy = width * 0.5, depth * 0.5
    arm = min(width, depth) * 0.34 if arm is None else arm
    ax, ay = arm * 0.5, arm * 0.5
    return [
        (cx - ax, cy - hy),
        (cx + ax, cy - hy),
        (cx + ax, cy - ay),
        (cx + hx, cy - ay),
        (cx + hx, cy + ay),
        (cx + ax, cy + ay),
        (cx + ax, cy + hy),
        (cx - ax, cy + hy),
        (cx - ax, cy + ay),
        (cx - hx, cy + ay),
        (cx - hx, cy - ay),
        (cx - ax, cy - ay),
    ]


# --------------------------------------------------------------------------
# Bmesh primitives
# --------------------------------------------------------------------------

def add_box(bm, lo, hi, region=REGION_WALL):
    lo, hi = Vector(lo), Vector(hi)
    size = hi - lo
    if min(size.x, size.y, size.z) <= 1.0e-6:
        return []
    matrix = Matrix.Translation((lo + hi) * 0.5) @ Matrix.Diagonal(size.to_4d())
    result = bmesh.ops.create_cube(bm, size=1.0, matrix=matrix, calc_uvs=False)
    faces = {face for vert in result["verts"] for face in vert.link_faces}
    return _set_region(faces, region)


def add_quad(bm, a, b, c, d, region=REGION_WALL):
    points = [_vec(point) for point in (a, b, c, d)]
    unique = []
    for point in points:
        if unique and (point - unique[-1]).length < 1.0e-6:
            continue
        if unique and (point - unique[0]).length < 1.0e-6:
            continue
        unique.append(point)
    if len(unique) < 3:
        return None
    verts = [bm.verts.new(point) for point in unique]
    try:
        face = bm.faces.new(verts)
    except ValueError:
        return None
    face.material_index = region
    return face


def add_tri(bm, a, b, c, region=REGION_WALL):
    return add_quad(bm, a, b, c, c, region=region)


def _ear_clip_cap(bm, verts, flip, region):
    points = [Vector((vert.co.x, vert.co.y)) for vert in verts]
    indices = list(range(len(verts)))
    faces = []

    def area2(i0, i1, i2):
        a, b, c = points[i0], points[i1], points[i2]
        return (b.x - a.x) * (c.y - a.y) - (b.y - a.y) * (c.x - a.x)

    def inside(i0, i1, i2, i):
        a, b, c, p = points[i0], points[i1], points[i2], points[i]
        v0, v1, v2 = c - a, b - a, p - a
        dot00, dot01, dot02 = v0.dot(v0), v0.dot(v1), v0.dot(v2)
        dot11, dot12 = v1.dot(v1), v1.dot(v2)
        denom = dot00 * dot11 - dot01 * dot01
        if abs(denom) < 1.0e-12:
            return False
        u = (dot11 * dot02 - dot01 * dot12) / denom
        v = (dot00 * dot12 - dot01 * dot02) / denom
        return u >= -1.0e-6 and v >= -1.0e-6 and (u + v) <= 1.0 + 1.0e-6

    guard = 0
    while len(indices) > 3 and guard < 64:
        guard += 1
        clipped = False
        count = len(indices)
        for i in range(count):
            i0, i1, i2 = indices[(i - 1) % count], indices[i], indices[(i + 1) % count]
            if area2(i0, i1, i2) <= 1.0e-8:
                continue
            if any(inside(i0, i1, i2, indices[j])
                   for j in range(count)
                   if indices[j] not in (i0, i1, i2)):
                continue
            ring = (verts[i0], verts[i1], verts[i2])
            face = bm.faces.new(ring if not flip else tuple(reversed(ring)))
            face.material_index = region
            faces.append(face)
            del indices[i]
            clipped = True
            break
        if not clipped:
            break
    if len(indices) >= 3:
        ring = [verts[i] for i in indices]
        try:
            face = bm.faces.new(ring if not flip else list(reversed(ring)))
            face.material_index = region
            faces.append(face)
        except ValueError:
            pass
    return faces


def _fill_cap(bm, verts, flip=False, region=REGION_WALL):
    if len(verts) < 3:
        return []
    if len(verts) == 3:
        ring = verts if not flip else list(reversed(verts))
        face = bm.faces.new(ring)
        face.material_index = region
        return [face]
    edges = []
    count = len(verts)
    for i in range(count):
        pair = (verts[i], verts[(i + 1) % count])
        edge = bm.edges.get(pair)
        if edge is None:
            try:
                edge = bm.edges.new(pair)
            except ValueError:
                edge = bm.edges.get((pair[1], pair[0]))
        if edge is not None:
            edges.append(edge)
    before = set(bm.faces)
    try:
        bmesh.ops.triangle_fill(bm, edges=edges, use_beauty=True)
    except Exception:
        return _ear_clip_cap(bm, verts, flip, region)
    faces = [face for face in bm.faces if face not in before]
    if not faces:
        return _ear_clip_cap(bm, verts, flip, region)
    if flip:
        bmesh.ops.reverse_faces(bm, faces=faces)
    return _set_region(faces, region)


def _loft_rings(bm, lower, upper, cap_start=False, cap_end=False, region=REGION_WALL):
    if len(lower) != len(upper) or len(lower) < 3:
        return []
    bottom = [bm.verts.new(_vec(point)) for point in lower]
    top = [bm.verts.new(_vec(point)) for point in upper]
    faces = []
    count = len(bottom)
    for i in range(count):
        j = (i + 1) % count
        faces.append(bm.faces.new((bottom[i], bottom[j], top[j], top[i])))
    if cap_start:
        faces.extend(_fill_cap(bm, bottom, flip=True, region=region))
    if cap_end:
        faces.extend(_fill_cap(bm, top, flip=False, region=region))
    return _set_region(faces, region)


def add_loft_profile(bm, profile, z0, z1, region=REGION_WALL):
    profile = [_as_xy(point) for point in profile]
    if len(profile) < 3:
        return []
    lower = [(x, y, z0) for x, y in profile]
    upper = [(x, y, z1) for x, y in profile]
    return _loft_rings(bm, lower, upper, cap_start=True, cap_end=True, region=region)


# --------------------------------------------------------------------------
# Recipe, context, facades
# --------------------------------------------------------------------------

@dataclass
class BuildingRecipe:
    name: str
    category: str
    display_name: str
    seed: int
    width: float
    depth: float
    stories: int
    builder: object
    ground_scale: float = 1.10
    bay_width: float = 2.05
    paint_size: int = 512
    triangle_budget: tuple = (400, 28000)
    uv_mode: str = "unique"
    window_style: str = "well"
    bevel_width: float = 0.04
    glow_family: str = "warm"
    notes: str = ""
    walkable: bool = False
    door_width: float = 1.70
    door_height: float = 2.28
    auto_windows: bool = True

    @property
    def ground_h(self):
        return STORY * float(self.ground_scale)

    @property
    def wall_h(self):
        extra = max(int(self.stories) - 1, 0)
        return self.ground_h + STORY * extra

    @property
    def bays_x(self):
        return max(1, int(round(self.width / max(self.bay_width, 0.4))))

    @property
    def bays_y(self):
        return max(1, int(round(self.depth / max(self.bay_width, 0.4))))


@dataclass
class Facade:
    origin: Vector
    right: Vector
    outward: Vector
    width: float
    height: float
    face_id: int
    bays: int
    stories: int


@dataclass
class WindowSpec:
    origin: Vector
    right: Vector
    up: Vector
    outward: Vector
    width: float
    height: float
    face_id: int
    uv: tuple
    lit: bool
    glow: tuple
    bay: int = 0
    story: int = 0


@dataclass
class BuildContext:
    recipe: BuildingRecipe
    hull: bmesh.types.BMesh = field(default=None)
    glass: bmesh.types.BMesh = field(default=None)
    facades: list = field(default_factory=list)
    windows: list = field(default_factory=list)
    masses: list = field(default_factory=list)
    wall_top: float = 0.0
    roof_top: float = 0.0

    def __post_init__(self):
        if self.hull is None:
            self.hull = bmesh.new()
        if self.glass is None:
            self.glass = bmesh.new()
        if self.glass.loops.layers.uv.get(PAINT_UV_NAME) is None:
            self.glass.loops.layers.uv.new(PAINT_UV_NAME)
        if self.glass.loops.layers.color.get(COLOR_ATTRIBUTE) is None:
            self.glass.loops.layers.color.new(COLOR_ATTRIBUTE)
        if self.wall_top <= 0.0:
            self.wall_top = self.recipe.wall_h
        if self.roof_top <= 0.0:
            self.roof_top = self.recipe.wall_h


def _touch_top(ctx, z, wall=False):
    ctx.roof_top = max(ctx.roof_top, z)
    if wall:
        ctx.wall_top = max(ctx.wall_top, z)


def cardinal_faces(width, depth, z0, z1, centre=(0.0, 0.0), bays_x=1, bays_y=1, stories=1):
    cx, cy = centre
    hx, hy = width * 0.5, depth * 0.5
    height = z1 - z0
    origin_z = z0
    specs = (
        (Vector((cx - hx, cy - hy, origin_z)), Vector((1.0, 0.0, 0.0)), Vector((0.0, -1.0, 0.0)), width, 0, bays_x),
        (Vector((cx + hx, cy - hy, origin_z)), Vector((0.0, 1.0, 0.0)), Vector((1.0, 0.0, 0.0)), depth, 1, bays_y),
        (Vector((cx + hx, cy + hy, origin_z)), Vector((-1.0, 0.0, 0.0)), Vector((0.0, 1.0, 0.0)), width, 2, bays_x),
        (Vector((cx - hx, cy + hy, origin_z)), Vector((0.0, -1.0, 0.0)), Vector((-1.0, 0.0, 0.0)), depth, 3, bays_y),
    )
    faces = []
    for origin, right, outward, span, face_id, bays in specs:
        faces.append(Facade(
            origin=origin,
            right=right,
            outward=outward,
            width=span,
            height=height,
            face_id=face_id,
            bays=max(1, int(bays)),
            stories=max(1, int(stories)),
        ))
    return faces


def register_box_facades(ctx, width, depth, z0, z1, centre=(0.0, 0.0)):
    stories = max(1, int(round((z1 - z0) / STORY)))
    bays_x = max(1, int(round(width / max(ctx.recipe.bay_width, 0.4))))
    bays_y = max(1, int(round(depth / max(ctx.recipe.bay_width, 0.4))))
    faces = cardinal_faces(width, depth, z0, z1, centre, bays_x, bays_y, stories)
    ctx.facades.extend(faces)
    _touch_top(ctx, z1, wall=True)
    return faces


def _register_profile_facades(ctx, profile, z0, z1):
    height = z1 - z0
    stories = max(1, int(round(height / STORY)))
    skip = max(0.55, ctx.recipe.bay_width * 0.32)
    count = len(profile)
    for i in range(count):
        a = Vector((profile[i][0], profile[i][1], z0))
        b = Vector((profile[(i + 1) % count][0], profile[(i + 1) % count][1], z0))
        right = b - a
        width = right.length
        if width < skip:
            continue
        right.normalize()
        outward = Vector((right.y, -right.x, 0.0))
        ctx.facades.append(Facade(
            origin=a,
            right=right,
            outward=outward,
            width=width,
            height=height,
            face_id=_face_id_from_normal(outward),
            bays=max(1, int(round(width / max(ctx.recipe.bay_width, 0.4)))),
            stories=stories,
        ))


# --------------------------------------------------------------------------
# Massing
# --------------------------------------------------------------------------

def _point_in_profile(profile, x, y):
    inside = False
    count = len(profile)
    for i in range(count):
        x1, y1 = profile[i][0], profile[i][1]
        x2, y2 = profile[(i + 1) % count][0], profile[(i + 1) % count][1]
        if (y1 > y) != (y2 > y):
            at = (x2 - x1) * (y - y1) / ((y2 - y1) if abs(y2 - y1) > 1.0e-9 else 1.0e-9) + x1
            if x < at:
                inside = not inside
    return inside


def prism(ctx, profile, z0, z1, region=REGION_WALL, register=None):
    profile = [_as_xy(point) for point in profile]
    faces = add_loft_profile(ctx.hull, profile, z0, z1, region=region)
    _touch_top(ctx, z1, wall=region in (REGION_WALL, REGION_BASE))
    if region in (REGION_WALL, REGION_BASE):
        ctx.masses.append({"profile": profile, "z0": z0, "z1": z1})
    if register is None:
        register = region == REGION_WALL
    if register:
        _register_profile_facades(ctx, profile, z0, z1)
    return faces


def cylinder(ctx, cx, cy, radius, z0, z1, segments=16, region=REGION_WALL, register=None):
    return prism(
        ctx, circle_profile(radius, segments, centre=(cx, cy)),
        z0, z1, region=region, register=register)


DOOR_CLEAR = 0.08
WALL_THICK = 0.30
FLOOR_THICK = 0.08
CEILING_THICK = 0.10


def hollow_rect(
        ctx, ox, oy, sx, sy, z0, z1,
        wall=WALL_THICK, door=True, register=True,
        door_width=None, door_height=None, floor=True, ceiling=True):
    """Room shell: floor, four walls, optional -Y door, optional ceiling.

    Walls are thin boxes, so the volume stays empty for walk-in collision.
    """
    recipe = ctx.recipe
    dw = float(door_width if door_width is not None else recipe.door_width)
    dh = min(float(door_height if door_height is not None else recipe.door_height),
             max(z1 - z0 - 0.18, 1.8))
    hx, hy = sx * 0.5, sy * 0.5
    faces = []
    if floor:
        faces.extend(add_box(
            ctx.hull,
            (ox - hx, oy - hy, z0),
            (ox + hx, oy + hy, z0 + FLOOR_THICK),
            REGION_BASE))
    if ceiling:
        faces.extend(add_box(
            ctx.hull,
            (ox - hx, oy - hy, z1 - CEILING_THICK),
            (ox + hx, oy + hy, z1),
            REGION_ROOF))
    # Left / right / back walls.
    faces.extend(add_box(
        ctx.hull,
        (ox - hx, oy - hy, z0),
        (ox - hx + wall, oy + hy, z1),
        REGION_WALL))
    faces.extend(add_box(
        ctx.hull,
        (ox + hx - wall, oy - hy, z0),
        (ox + hx, oy + hy, z1),
        REGION_WALL))
    faces.extend(add_box(
        ctx.hull,
        (ox - hx, oy + hy - wall, z0),
        (ox + hx, oy + hy, z1),
        REGION_WALL))
    front_y1 = oy - hy + wall
    front_y0 = oy - hy
    if door:
        gap0 = ox - dw * 0.5
        gap1 = ox + dw * 0.5
        faces.extend(add_box(
            ctx.hull,
            (ox - hx, front_y0, z0),
            (gap0, front_y1, z1),
            REGION_WALL))
        faces.extend(add_box(
            ctx.hull,
            (gap1, front_y0, z0),
            (ox + hx, front_y1, z1),
            REGION_WALL))
        faces.extend(add_box(
            ctx.hull,
            (gap0, front_y0, z0 + dh),
            (gap1, front_y1, z1),
            REGION_WALL))
        # Frame so the opening reads as a door, not a missing wall.
        trim = 0.08
        faces.extend(add_box(
            ctx.hull,
            (gap0 - trim, front_y0 - 0.04, z0),
            (gap0, front_y1 + 0.04, z0 + dh),
            REGION_TRIM))
        faces.extend(add_box(
            ctx.hull,
            (gap1, front_y0 - 0.04, z0),
            (gap1 + trim, front_y1 + 0.04, z0 + dh),
            REGION_TRIM))
        faces.extend(add_box(
            ctx.hull,
            (gap0 - trim, front_y0 - 0.04, z0 + dh),
            (gap1 + trim, front_y1 + 0.04, z0 + dh + trim),
            REGION_TRIM))
    else:
        faces.extend(add_box(
            ctx.hull,
            (ox - hx, front_y0, z0),
            (ox + hx, front_y1, z1),
            REGION_WALL))
    _touch_top(ctx, z1, wall=True)
    if register:
        register_box_facades(ctx, sx, sy, z0, z1, centre=(ox, oy))
    return faces


def furniture_box(ctx, lo, hi, region=REGION_TRIM):
    return add_box(ctx.hull, lo, hi, region)


def add_glass_pane(ctx, origin, right, up, outward, width, height, glow, face_id=0):
    """One glass quad plus a WindowSpec so finish_mesh can colour it."""
    origin = Vector(origin)
    right_n = Vector(right).normalized()
    up_n = Vector(up).normalized()
    outward_n = Vector(outward).normalized()
    a = origin
    b = origin + right_n * width
    c = origin + right_n * width + up_n * height
    d = origin + up_n * height
    add_quad(ctx.glass, a, b, c, d, REGION_GLASS)
    uvs = (
        (face_id * 0.25, 0.0),
        (face_id * 0.25 + 0.24, 0.0),
        (face_id * 0.25 + 0.24, 0.70),
        (face_id * 0.25, 0.70),
    )
    ctx.windows.append(WindowSpec(
        origin=origin,
        right=right_n,
        up=up_n,
        outward=outward_n,
        width=width,
        height=height,
        face_id=face_id,
        uv=uvs,
        lit=True,
        glow=tuple(glow),
    ))


def _door_uv_range(recipe, facade):
    if not recipe.walkable or facade.face_id != 0:
        return None
    span = max(facade.width, 1.0e-5)
    half = recipe.door_width * 0.5 / span
    v1 = recipe.door_height / max(facade.height, 1.0e-5)
    return (0.5 - half, 0.5 + half, v1)


def cornice(ctx, profile, z, width=0.20, height=0.14, region=REGION_TRIM):
    outer = _offset_profile(profile, width)
    faces = add_loft_profile(ctx.hull, outer, z, z + height, region=region)
    _touch_top(ctx, z + height)
    return faces


def parapet(ctx, profile, z, height=0.55, thickness=0.12, region=REGION_TRIM):
    faces = []
    count = len(profile)
    for i in range(count):
        a = Vector((profile[i][0], profile[i][1], z))
        b = Vector((profile[(i + 1) % count][0], profile[(i + 1) % count][1], z))
        along = b - a
        if along.length < 0.12:
            continue
        along.normalize()
        outward = Vector((along.y, -along.x, 0.0))
        mid = (a + b) * 0.5 + outward * (thickness * 0.5)
        half = along * ((b - a).length * 0.5 + 0.02)
        lo = mid - half - outward * (thickness * 0.5) + Vector((0.0, 0.0, 0.0))
        hi = mid + half + outward * (thickness * 0.5) + Vector((0.0, 0.0, height))
        faces.extend(add_box(
            ctx.hull,
            (min(lo.x, hi.x), min(lo.y, hi.y), z),
            (max(lo.x, hi.x), max(lo.y, hi.y), z + height),
            region=region,
        ))
    _touch_top(ctx, z + height)
    return faces


def _vertical_strips(ctx, points, z0, z1, width, depth, outward_hint, region):
    faces = []
    up = z1 - z0
    if up <= 0.05:
        return faces
    for point in points:
        origin = Vector((point[0], point[1], z0))
        outward = Vector((outward_hint[0], outward_hint[1], 0.0))
        if outward.length < 1.0e-5:
            outward = Vector((origin.x, origin.y, 0.0))
        if outward.length < 1.0e-5:
            outward = Vector((0.0, -1.0, 0.0))
        outward.normalize()
        tangent = Vector((-outward.y, outward.x, 0.0))
        centre = origin + outward * (depth * 0.5)
        lo = centre - tangent * (width * 0.5) - outward * (depth * 0.5)
        hi = centre + tangent * (width * 0.5) + outward * (depth * 0.5) + Vector((0.0, 0.0, up))
        faces.extend(add_box(
            ctx.hull,
            (min(lo.x, hi.x), min(lo.y, hi.y), z0),
            (max(lo.x, hi.x), max(lo.y, hi.y), z1),
            region=region,
        ))
    return faces


def pilasters(ctx, profile=None, z0=None, z1=None, width=0.18, depth=0.10, region=REGION_TRIM):
    faces = []
    if profile is not None:
        z_bot = ctx.recipe.ground_h if z0 is None else z0
        z_top = ctx.wall_top if z1 is None else z1
        centre = _profile_centre(profile)
        for point in profile:
            outward = (point[0] - centre[0], point[1] - centre[1])
            faces.extend(_vertical_strips(ctx, [point], z_bot, z_top, width, depth, outward, region))
        return faces
    for facade in ctx.facades:
        z_bot = facade.origin.z if z0 is None else z0
        z_top = facade.origin.z + facade.height if z1 is None else z1
        for i in range(facade.bays + 1):
            share = i / float(facade.bays)
            point = facade.origin + facade.right * (share * facade.width)
            faces.extend(_vertical_strips(
                ctx, [(point.x, point.y)], z_bot, z_top, width, depth,
                (facade.outward.x, facade.outward.y), region))
    return faces


def fins(ctx, profile=None, z0=None, z1=None, width=0.06, depth=0.14, region=REGION_TRIM):
    if profile is not None:
        return pilasters(ctx, profile, z0, z1, width=width, depth=depth, region=region)
    return pilasters(ctx, None, z0, z1, width=width, depth=depth, region=region)


def chimney(ctx, x, y, z0, height=1.8, size=0.48, region=REGION_ACCENT):
    half = size * 0.5
    faces = add_box(
        ctx.hull,
        (x - half, y - half, z0),
        (x + half, y + half, z0 + height),
        region=region,
    )
    cap = size * 0.16
    faces.extend(add_box(
        ctx.hull,
        (x - half - cap * 0.4, y - half - cap * 0.4, z0 + height),
        (x + half + cap * 0.4, y + half + cap * 0.4, z0 + height + cap),
        region=region,
    ))
    _touch_top(ctx, z0 + height + cap)
    return faces


def antenna(ctx, x, y, z0, height=2.6, radius=0.045, region=REGION_ACCENT):
    faces = add_loft_profile(
        ctx.hull, circle_profile(radius, 8, centre=(x, y)),
        z0, z0 + height, region=region)
    ball = circle_profile(radius * 2.2, 8, centre=(x, y))
    faces.extend(add_loft_profile(ctx.hull, ball, z0 + height, z0 + height + radius * 3.0, region=region))
    _touch_top(ctx, z0 + height + radius * 3.0)
    return faces


def steps(ctx, x, y, z0, width=1.8, depth=1.2, count=3, facing=(0.0, -1.0), region=REGION_BASE):
    facing = Vector((facing[0], facing[1], 0.0))
    if facing.length < 1.0e-5:
        facing = Vector((0.0, -1.0, 0.0))
    facing.normalize()
    right = Vector((-facing.y, facing.x, 0.0))
    count = max(int(count), 1)
    run = depth / count
    rise = max(z0 / count, 0.12)
    faces = []
    for i in range(count):
        out0 = facing * (run * i)
        out1 = facing * (run * (i + 1))
        top = max(z0 - rise * i, 0.02)
        centre = Vector((x, y, 0.0)) + (out0 + out1) * 0.5
        lo = centre - right * (width * 0.5) + facing * (-run * 0.5)
        hi = centre + right * (width * 0.5) + facing * (run * 0.5)
        faces.extend(add_box(
            ctx.hull,
            (min(lo.x, hi.x), min(lo.y, hi.y), 0.0),
            (max(lo.x, hi.x), max(lo.y, hi.y), top),
            region=region,
        ))
    return faces


# --------------------------------------------------------------------------
# Roofs
# --------------------------------------------------------------------------

def roof_slab(ctx, profile, z0, thickness=_SLAB, overhang=0.18, region=REGION_ROOF):
    outer = _offset_profile(profile, overhang)
    faces = add_loft_profile(ctx.hull, outer, z0, z0 + thickness, region=region)
    ctx.wall_top = max(ctx.wall_top, z0)
    _touch_top(ctx, z0 + thickness)
    return faces


def _rect_corners(profile, overhang=0.0):
    x0, x1, y0, y1 = _profile_bounds(profile)
    x0 -= overhang
    x1 += overhang
    y0 -= overhang
    y1 += overhang
    return x0, x1, y0, y1


def gable_roof(ctx, profile, z0, rise, ridge_axis="x", overhang=0.22, region=REGION_ROOF):
    roof_slab(ctx, profile, z0, thickness=_SLAB, overhang=overhang, region=region)
    z1 = z0 + _SLAB
    x0, x1, y0, y1 = _rect_corners(profile, overhang)
    peak = z1 + rise
    if ridge_axis in ("y", "Y"):
        ridge_x = (x0 + x1) * 0.5
        add_quad(ctx.hull, (x0, y0, z1), (ridge_x, y0, peak), (ridge_x, y1, peak), (x0, y1, z1), region=region)
        add_quad(ctx.hull, (x1, y0, z1), (x1, y1, z1), (ridge_x, y1, peak), (ridge_x, y0, peak), region=region)
        add_tri(ctx.hull, (x0, y0, z1), (x1, y0, z1), (ridge_x, y0, peak), region=REGION_WALL)
        add_tri(ctx.hull, (x1, y1, z1), (x0, y1, z1), (ridge_x, y1, peak), region=REGION_WALL)
    else:
        ridge_y = (y0 + y1) * 0.5
        add_quad(ctx.hull, (x0, y0, z1), (x1, y0, z1), (x1, ridge_y, peak), (x0, ridge_y, peak), region=region)
        add_quad(ctx.hull, (x1, y1, z1), (x0, y1, z1), (x0, ridge_y, peak), (x1, ridge_y, peak), region=region)
        add_tri(ctx.hull, (x0, y0, z1), (x0, y1, z1), (x0, ridge_y, peak), region=REGION_WALL)
        add_tri(ctx.hull, (x1, y1, z1), (x1, y0, z1), (x1, ridge_y, peak), region=REGION_WALL)
    _touch_top(ctx, peak)
    return peak


def hip_roof(ctx, profile, z0, rise, overhang=0.20, hip=0.35, region=REGION_ROOF):
    roof_slab(ctx, profile, z0, thickness=_SLAB, overhang=overhang, region=region)
    z1 = z0 + _SLAB
    x0, x1, y0, y1 = _rect_corners(profile, overhang)
    width, depth = x1 - x0, y1 - y0
    inset = min(hip, width * 0.28, depth * 0.28)
    peak = z1 + rise
    if width >= depth:
        rx0, rx1 = x0 + inset, x1 - inset
        ry = (y0 + y1) * 0.5
        add_quad(ctx.hull, (x0, y0, z1), (x1, y0, z1), (rx1, ry, peak), (rx0, ry, peak), region=region)
        add_quad(ctx.hull, (x1, y1, z1), (x0, y1, z1), (rx0, ry, peak), (rx1, ry, peak), region=region)
        add_tri(ctx.hull, (x1, y0, z1), (x1, y1, z1), (rx1, ry, peak), region=region)
        add_tri(ctx.hull, (x0, y1, z1), (x0, y0, z1), (rx0, ry, peak), region=region)
    else:
        ry0, ry1 = y0 + inset, y1 - inset
        rx = (x0 + x1) * 0.5
        add_quad(ctx.hull, (x0, y0, z1), (rx, ry0, peak), (rx, ry1, peak), (x0, y1, z1), region=region)
        add_quad(ctx.hull, (x1, y1, z1), (rx, ry1, peak), (rx, ry0, peak), (x1, y0, z1), region=region)
        add_tri(ctx.hull, (x0, y0, z1), (x1, y0, z1), (rx, ry0, peak), region=region)
        add_tri(ctx.hull, (x1, y1, z1), (x0, y1, z1), (rx, ry1, peak), region=region)
    _touch_top(ctx, peak)
    return peak


def shed_roof(ctx, profile, z0, rise, high_side="-y", overhang=0.16, region=REGION_ROOF, fall_axis=None):
    if fall_axis in ("y", "+y"):
        high_side = "-y"
    elif fall_axis == "-y":
        high_side = "+y"
    elif fall_axis in ("x", "+x"):
        high_side = "-x"
    elif fall_axis == "-x":
        high_side = "+x"
    roof_slab(ctx, profile, z0, thickness=_SLAB, overhang=overhang, region=region)
    z1 = z0 + _SLAB
    x0, x1, y0, y1 = _rect_corners(profile, overhang)
    high = z1 + rise
    z_sw = z_se = z_ne = z_nw = z1
    if high_side == "-y":
        z_sw = z_se = high
    elif high_side == "+y":
        z_nw = z_ne = high
    elif high_side == "-x":
        z_sw = z_nw = high
    else:
        z_se = z_ne = high
    add_quad(ctx.hull, (x0, y0, z_sw), (x1, y0, z_se), (x1, y1, z_ne), (x0, y1, z_nw), region=region)
    _touch_top(ctx, high)
    return high


def mansard_roof(ctx, profile, z0, rise=2.2, deck=0.35, inset=0.55, overhang=0.16, region=REGION_ROOF):
    roof_slab(ctx, profile, z0, thickness=_SLAB, overhang=overhang, region=region)
    z1 = z0 + _SLAB
    lower = _offset_profile(profile, overhang)
    mid = _offset_profile(profile, -max(inset * 0.45, 0.12))
    top = _offset_profile(profile, -inset)
    break_z = z1 + rise * 0.62
    deck_z = z1 + rise
    _loft_rings(
        ctx.hull,
        [(p[0], p[1], z1) for p in lower],
        [(p[0], p[1], break_z) for p in mid],
        cap_start=False, cap_end=False, region=region)
    _loft_rings(
        ctx.hull,
        [(p[0], p[1], break_z) for p in mid],
        [(p[0], p[1], deck_z) for p in top],
        cap_start=False, cap_end=True, region=region)
    _touch_top(ctx, deck_z + deck * 0.0)
    if deck > 0.05:
        add_loft_profile(ctx.hull, top, deck_z, deck_z + 0.08, region=region)
        _touch_top(ctx, deck_z + 0.08)
    return deck_z


def cone_roof(ctx, cx, cy, radius, z0, rise, segments=16, top_radius=None, region=REGION_ROOF):
    top_radius = radius * 0.08 if top_radius is None else top_radius
    top_radius = max(top_radius, 0.05)
    lower = [(p[0], p[1], z0) for p in circle_profile(radius, segments, centre=(cx, cy))]
    upper = [(p[0], p[1], z0 + rise) for p in circle_profile(top_radius, segments, centre=(cx, cy))]
    faces = _loft_rings(ctx.hull, lower, upper, cap_start=False, cap_end=True, region=region)
    _touch_top(ctx, z0 + rise)
    return faces


def dome_roof(ctx, cx, cy, radius, z0, rise=None, segments=16, steps=6, region=REGION_ROOF):
    rise = radius * 0.92 if rise is None else rise
    steps = max(int(steps), 3)
    rings = []
    for i in range(steps + 1):
        t = i / steps
        angle = t * math.pi * 0.5
        ring_r = max(radius * math.cos(angle), radius * 0.06)
        rings.append((
            [(p[0], p[1], z0 + rise * math.sin(angle))
             for p in circle_profile(ring_r, segments, centre=(cx, cy))],
        ))
    faces = []
    for i in range(steps):
        faces.extend(_loft_rings(
            ctx.hull, rings[i][0], rings[i + 1][0],
            cap_start=False, cap_end=(i == steps - 1), region=region))
    _touch_top(ctx, z0 + rise)
    return faces


def barrel_vault(ctx, cx, cy, width, depth, z0, rise=None, axis="x", segments=10, region=REGION_ROOF):
    segments = max(int(segments), 4)
    if axis in ("y", "Y"):
        rise = width * 0.5 if rise is None else rise
        half = depth * 0.5
        stations = (-half, half)
        faces = []
        for i in range(segments):
            t0 = i / segments
            t1 = (i + 1) / segments
            a0 = math.pi * t0
            a1 = math.pi * t1
            y0s = [cy + s for s in stations]
            p00 = (cx + math.cos(a0) * (width * 0.5), y0s[0], z0 + math.sin(a0) * rise)
            p01 = (cx + math.cos(a1) * (width * 0.5), y0s[0], z0 + math.sin(a1) * rise)
            p11 = (cx + math.cos(a1) * (width * 0.5), y0s[1], z0 + math.sin(a1) * rise)
            p10 = (cx + math.cos(a0) * (width * 0.5), y0s[1], z0 + math.sin(a0) * rise)
            faces.append(add_quad(ctx.hull, p00, p01, p11, p10, region=region))
        _touch_top(ctx, z0 + rise)
        return faces
    rise = depth * 0.5 if rise is None else rise
    half = width * 0.5
    faces = []
    for i in range(segments):
        t0 = i / segments
        t1 = (i + 1) / segments
        a0 = math.pi * t0
        a1 = math.pi * t1
        p00 = (cx - half, cy + math.cos(a0) * (depth * 0.5), z0 + math.sin(a0) * rise)
        p01 = (cx - half, cy + math.cos(a1) * (depth * 0.5), z0 + math.sin(a1) * rise)
        p11 = (cx + half, cy + math.cos(a1) * (depth * 0.5), z0 + math.sin(a1) * rise)
        p10 = (cx + half, cy + math.cos(a0) * (depth * 0.5), z0 + math.sin(a0) * rise)
        faces.append(add_quad(ctx.hull, p00, p01, p11, p10, region=region))
    _touch_top(ctx, z0 + rise)
    return faces


# --------------------------------------------------------------------------
# Windows
# --------------------------------------------------------------------------

_STYLE_GLOW = {
    "terracotta_bond": (1.0, 0.76, 0.38),
    "clapboard_pine": (1.0, 0.84, 0.55),
    "lime_stucco": (0.95, 0.72, 0.4),
    "charcoal_panel": (0.7, 0.84, 1.0),
    "ashlar_sand": (0.86, 0.78, 0.62),
    "verdigris_tile": (0.4, 0.9, 0.78),
    "chalk_wash": (1.0, 0.88, 0.7),
    "rust_plate": (1.0, 0.55, 0.32),
    "amethyst_stucco": (0.78, 0.55, 1.0),
    "neon_night": (0.45, 0.95, 1.0),
}


def glow_for(recipe, style=None):
    family = recipe.glow_family
    if style == "terracotta_bond":
        return (0.72, 0.86, 1.0) if family == "cool" else (1.0, 0.76, 0.38)
    if style == "neon_night":
        return (0.45, 0.95, 1.0) if family == "cool" else (0.78, 0.55, 1.0)
    if style in _STYLE_GLOW:
        return _STYLE_GLOW[style]
    if family == "cool":
        return (0.70, 0.84, 1.0)
    if family == "mixed":
        return (1.0, 0.70, 0.48)
    return (1.0, 0.76, 0.38)


def lit_rate(recipe, style=None):
    rate = {
        "small_houses": 0.62,
        "medium_apartments": 0.52,
        "medium_buildings": 0.48,
        "large_towers": 0.46,
        "skyscrapers": 0.54,
        "specials": 0.58,
        "variants": 0.50,
    }.get(recipe.category, 0.5)
    if style == "neon_night":
        rate = min(0.88, rate + 0.22)
    return rate


def window_is_lit(recipe, face_id, bay, story, style=None):
    return hash01(recipe.seed, face_id + 1.0, bay + 3.0, story + 5.0, 17.0) < lit_rate(recipe, style)


def atlas_window_uv(ctx, facade, u0, v0, u1, v1):
    tile = 0.25
    base = facade.face_id * tile
    wall_top = max(ctx.wall_top, 1.0e-5)

    def corner(u, v):
        z = facade.origin.z + v * facade.height
        return (clamp01(base + clamp01(u) * tile), clamp01(0.72 * z / wall_top))

    return (corner(u0, v0), corner(u1, v0), corner(u1, v1), corner(u0, v1))


def _window_frame(ctx, origin, right, up, outward, width, height):
    frame = 0.055
    depth = 0.045
    pairs = (
        (origin - right * frame - up * frame, width + frame * 2.0, frame, depth),
        (origin + up * height - right * frame, width + frame * 2.0, frame, depth),
        (origin - right * frame, frame, height, depth),
        (origin + right * width, frame, height, depth),
    )
    for start, span_u, span_v, span_d in pairs:
        a = start - outward * 0.01
        b = start + right * span_u + up * span_v + outward * span_d
        add_box(
            ctx.hull,
            (min(a.x, b.x), min(a.y, b.y), min(a.z, b.z)),
            (max(a.x, b.x), max(a.y, b.y), max(a.z, b.z)),
            region=REGION_TRIM,
        )


def _window_inside_other_mass(ctx, origin, height):
    """Skip panes that sit in the overlap of a box and a drum."""
    x, y = float(origin.x), float(origin.y)
    z0 = float(origin.z)
    z1 = z0 + float(height)
    hits = 0
    for mass in ctx.masses:
        if mass["z1"] < z0 + 0.08 or mass["z0"] > z1 - 0.08:
            continue
        if _point_in_profile(mass["profile"], x, y):
            hits += 1
            if hits >= 2:
                return True
    return False


def dress_windows(ctx):
    recipe = ctx.recipe
    if not getattr(recipe, "auto_windows", True):
        return ctx.windows
    well = recipe.window_style == "well"
    house_frames = well and recipe.category == "small_houses"
    inset = 0.08 if well else 0.055
    glass_in = 0.055
    glow = glow_for(recipe)
    for facade in ctx.facades:
        margin_u = 0.18 + 0.06 * hash01(recipe.seed, facade.face_id, 2.0)
        margin_v = 0.22 + 0.04 * hash01(recipe.seed, facade.face_id, 9.0)
        for story in range(facade.stories):
            for bay in range(facade.bays):
                bay_u0 = bay / float(facade.bays)
                bay_u1 = (bay + 1) / float(facade.bays)
                story_v0 = story / float(facade.stories)
                story_v1 = (story + 1) / float(facade.stories)
                u0 = bay_u0 + (bay_u1 - bay_u0) * margin_u
                u1 = bay_u1 - (bay_u1 - bay_u0) * margin_u
                v0 = story_v0 + (story_v1 - story_v0) * margin_v
                v1 = story_v1 - (story_v1 - story_v0) * margin_v
                origin = (
                    facade.origin
                    + facade.right * (u0 * facade.width)
                    + Vector((0.0, 0.0, 1.0)) * (v0 * facade.height)
                )
                width = (u1 - u0) * facade.width
                height = (v1 - v0) * facade.height
                if width < 0.18 or height < 0.22:
                    continue
                if _window_inside_other_mass(ctx, origin, height):
                    continue
                door = _door_uv_range(recipe, facade)
                if door is not None:
                    du0, du1, dv1 = door
                    if story == 0 and not (u1 < du0 or u0 > du1) and v0 < dv1:
                        continue
                right = facade.right * width
                up = Vector((0.0, 0.0, height))
                outward = facade.outward
                if well:
                    inner = origin - outward * inset
                    add_quad(ctx.hull, inner, inner + right, inner + right + up, inner + up, REGION_WALL)
                    add_quad(ctx.hull, origin, inner, inner + up, origin + up, REGION_TRIM)
                    add_quad(ctx.hull, origin + right, origin + right + up, inner + right + up, inner + right, REGION_TRIM)
                    add_quad(ctx.hull, origin + up, inner + up, inner + right + up, origin + right + up, REGION_TRIM)
                    add_quad(ctx.hull, origin, origin + right, inner + right, inner, REGION_TRIM)
                if house_frames:
                    _window_frame(ctx, origin, facade.right, Vector((0.0, 0.0, 1.0)), outward, width, height)
                lit = window_is_lit(recipe, facade.face_id, bay, story)
                pane = glow if lit else (glow[0] * 0.38, glow[1] * 0.38, glow[2] * 0.38)
                uvs = atlas_window_uv(ctx, facade, u0, v0, u1, v1)
                g0 = origin - outward * glass_in
                add_quad(ctx.glass, g0, g0 + right, g0 + right + up, g0 + up, REGION_GLASS)
                ctx.windows.append(WindowSpec(
                    origin=g0,
                    right=facade.right,
                    up=Vector((0.0, 0.0, 1.0)),
                    outward=outward,
                    width=width,
                    height=height,
                    face_id=facade.face_id,
                    uv=uvs,
                    lit=lit,
                    glow=pane,
                    bay=bay,
                    story=story,
                ))
    return ctx.windows


# --------------------------------------------------------------------------
# Finish, materials, export
# --------------------------------------------------------------------------

def _shade_hull(bm, threshold=40.0):
    limit = math.radians(threshold)
    for face in bm.faces:
        face.smooth = True
    for edge in bm.edges:
        edge.smooth = len(edge.link_faces) == 2 and edge.calc_face_angle() <= limit


def _roof_band_uvs(recipe, coords):
    uvs = []
    for point in coords:
        u = clamp01((point.x + recipe.width * 0.5) / max(recipe.width, 1.0e-5))
        v = clamp01((point.y + recipe.depth * 0.5) / max(recipe.depth, 1.0e-5))
        uvs.append((clamp01(u), 0.72 + 0.28 * v))
    return uvs


def _polygon_uvs(recipe, polygon, coords, wall_top):
    normal = Vector(polygon.normal)
    if polygon.material_index == REGION_ROOF or abs(normal.z) >= 0.72:
        return _roof_band_uvs(recipe, coords)
    up = Vector((0.0, 0.0, 1.0))
    tangent = up.cross(normal)
    if tangent.length < 1.0e-4:
        return _roof_band_uvs(recipe, coords)
    tangent.normalize()
    face_id = _face_id_from_normal(normal)
    uvs = []
    for point in coords:
        local_u = _wall_local_u(recipe, face_id, point)
        # Face-plane measure keeps shallow jogs in the same tile.
        _ = point.dot(tangent)
        v = 0.72 * clamp01(point.z / max(wall_top, 1.0e-5))
        uvs.append((clamp01((face_id + local_u) * 0.25), clamp01(v)))
    return uvs


def _ensure_color(mesh, name=COLOR_ATTRIBUTE):
    layer = mesh.color_attributes.get(name)
    if layer is None:
        layer = mesh.color_attributes.new(name=name, type="FLOAT_COLOR", domain="CORNER")
    return layer


def finish_mesh(ctx, bm, name, kind="hull"):
    if kind == "hull" and bm.verts:
        bmesh.ops.remove_doubles(bm, verts=bm.verts[:], dist=1.0e-4)
    if bm.faces:
        bmesh.ops.recalc_face_normals(bm, faces=bm.faces[:])
        if kind == "hull":
            _shade_hull(bm)
        bm.normal_update()
    mesh = bpy.data.meshes.new(name + "Mesh")
    bm.to_mesh(mesh)
    mesh.validate(clean_customdata=False)
    mesh.update(calc_edges=True)

    paint_uv = mesh.uv_layers.get(PAINT_UV_NAME) or mesh.uv_layers.new(name=PAINT_UV_NAME)
    colour = _ensure_color(mesh)
    recipe = ctx.recipe

    if kind == "glass":
        for polygon, spec in zip(mesh.polygons, ctx.windows):
            glow = (spec.glow[0], spec.glow[1], spec.glow[2], 1.0)
            for loop_i, uv in zip(polygon.loop_indices, spec.uv):
                paint_uv.data[loop_i].uv = uv
                colour.data[loop_i].color = glow
        if not ctx.windows:
            dark = (0.34, 0.32, 0.30, 1.0)
            for polygon in mesh.polygons:
                for loop_i in polygon.loop_indices:
                    paint_uv.data[loop_i].uv = (0.0, 0.0)
                    colour.data[loop_i].color = dark
    else:
        for polygon in mesh.polygons:
            coords = [mesh.vertices[mesh.loops[loop_i].vertex_index].co.copy()
                      for loop_i in polygon.loop_indices]
            uvs = _polygon_uvs(recipe, polygon, coords, ctx.wall_top)
            tint = REGION_TINT.get(polygon.material_index, REGION_TINT[REGION_WALL])
            for loop_i, uv in zip(polygon.loop_indices, uvs):
                paint_uv.data[loop_i].uv = uv
                colour.data[loop_i].color = tint

    mesh.color_attributes.active_color_name = COLOR_ATTRIBUTE
    if hasattr(mesh.color_attributes, "render_color_index"):
        mesh.color_attributes.render_color_index = 0
    mesh.uv_layers.active = paint_uv
    mesh.update()

    obj = bpy.data.objects.new(name, mesh)
    bpy.context.scene.collection.objects.link(obj)
    if kind == "hull" and recipe.bevel_width > 0.0:
        bevel = obj.modifiers.new("Bevel", "BEVEL")
        bevel.width = recipe.bevel_width
        bevel.segments = 2
        bevel.limit_method = "ANGLE"
        bevel.angle_limit = math.radians(32.0)
    return obj


def ground_objects(objects):
    live = [obj for obj in objects if obj is not None]
    if not live:
        return
    min_z = 1.0e9
    for obj in live:
        matrix = obj.matrix_world
        for vert in obj.data.vertices:
            min_z = min(min_z, (matrix @ vert.co).z)
    if min_z >= 1.0e8 or abs(min_z) < 1.0e-6:
        return
    shift = Matrix.Translation((0.0, 0.0, -min_z))
    for obj in live:
        obj.data.transform(shift)
        obj.data.update()


def _principled_graph(material, roughness, metallic=0.0):
    material.use_nodes = True
    nodes = material.node_tree.nodes
    links = material.node_tree.links
    nodes.clear()
    output = nodes.new("ShaderNodeOutputMaterial")
    bsdf = nodes.new("ShaderNodeBsdfPrincipled")
    attr = nodes.new("ShaderNodeAttribute")
    attr.attribute_name = COLOR_ATTRIBUTE
    if hasattr(attr, "attribute_type"):
        attr.attribute_type = "GEOMETRY"
    links.new(attr.outputs["Color"], bsdf.inputs["Base Color"])
    for socket_name in ("Emission Color", "Emission"):
        if socket_name in bsdf.inputs:
            links.new(attr.outputs["Color"], bsdf.inputs[socket_name])
            break
    if "Emission Strength" in bsdf.inputs:
        bsdf.inputs["Emission Strength"].default_value = 0.15
    bsdf.inputs["Roughness"].default_value = roughness
    if "Metallic" in bsdf.inputs:
        bsdf.inputs["Metallic"].default_value = metallic
    links.new(bsdf.outputs["BSDF"], output.inputs["Surface"])
    return material


def _set_opaque(material):
    if hasattr(material, "surface_render_method"):
        material.surface_render_method = "DITHERED"
    elif hasattr(material, "blend_method"):
        material.blend_method = "OPAQUE"
    if hasattr(material, "use_backface_culling"):
        material.use_backface_culling = False


def make_hull_material():
    material = bpy.data.materials.get("BuildingHull") or bpy.data.materials.new("BuildingHull")
    _principled_graph(material, roughness=0.82, metallic=0.04)
    _set_opaque(material)
    return material


def make_glass_material():
    material = bpy.data.materials.get("BuildingGlass") or bpy.data.materials.new("BuildingGlass")
    _principled_graph(material, roughness=0.16, metallic=0.18)
    for node in material.node_tree.nodes:
        if node.type == "BSDF_PRINCIPLED" and "Emission Strength" in node.inputs:
            node.inputs["Emission Strength"].default_value = 0.55
    _set_opaque(material)
    return material


def bind_paint(material, image, emission=1.8):
    nodes = material.node_tree.nodes
    links = material.node_tree.links
    bsdf = None
    for node in nodes:
        if node.type == "BSDF_PRINCIPLED":
            bsdf = node
            break
    if bsdf is None:
        return material
    for name in ("BuildingPaint", "BuildingEmitMul"):
        node = nodes.get(name)
        if node is not None:
            nodes.remove(node)
    texture = nodes.new("ShaderNodeTexImage")
    texture.name = "BuildingPaint"
    texture.image = image
    texture.interpolation = "Linear"
    texture.extension = "REPEAT"
    for socket_name in ("Base Color",):
        for link in list(bsdf.inputs[socket_name].links):
            links.remove(link)
        links.new(texture.outputs["Color"], bsdf.inputs[socket_name])
    for socket_name in ("Emission Color", "Emission"):
        if socket_name not in bsdf.inputs:
            continue
        for link in list(bsdf.inputs[socket_name].links):
            links.remove(link)
        links.new(texture.outputs["Color"], bsdf.inputs[socket_name])
        break
    strength = bsdf.inputs.get("Emission Strength")
    if strength is not None:
        for link in list(strength.links):
            links.remove(link)
        multiply = nodes.new("ShaderNodeMath")
        multiply.name = "BuildingEmitMul"
        multiply.operation = "MULTIPLY"
        multiply.inputs[1].default_value = emission
        links.new(texture.outputs["Alpha"], multiply.inputs[0])
        links.new(multiply.outputs[0], strength)
    return material


def reset_scene():
    for obj in list(bpy.data.objects):
        bpy.data.objects.remove(obj, do_unlink=True)
    for mesh in list(bpy.data.meshes):
        bpy.data.meshes.remove(mesh)
    for image in list(bpy.data.images):
        bpy.data.images.remove(image)
    for material in list(bpy.data.materials):
        if material.name in KEEP_MATERIALS:
            continue
        if material.users == 0:
            bpy.data.materials.remove(material)
    for light in list(bpy.data.lights):
        bpy.data.lights.remove(light)
    for camera in list(bpy.data.cameras):
        bpy.data.cameras.remove(camera)


def export_glb(objects, path):
    live = [obj for obj in objects if obj is not None]
    if not live:
        raise ValueError("export_glb has no objects")
    os.makedirs(os.path.dirname(path), exist_ok=True)
    view_layer = bpy.context.view_layer
    for obj in view_layer.objects:
        if obj is not None:
            obj.select_set(False)
    for obj in live:
        obj.hide_viewport = False
        obj.hide_render = False
        obj.select_set(True)
    view_layer.objects.active = live[0]
    settings = dict(
        filepath=path,
        export_format="GLB",
        use_selection=True,
        export_apply=True,
        export_yup=True,
        export_normals=True,
        export_tangents=False,
        export_texcoords=True,
        export_skins=False,
        export_animations=False,
        export_materials="EXPORT",
        export_cameras=False,
        export_lights=False,
    )
    try:
        bpy.ops.export_scene.gltf(
            export_vertex_color="ACTIVE",
            export_all_vertex_colors=False,
            **settings)
    except TypeError:
        try:
            bpy.ops.export_scene.gltf(export_vertex_color="ACTIVE", **settings)
        except TypeError:
            bpy.ops.export_scene.gltf(**settings)
    print("wrote {0} ({1:.1f} KB)".format(path, os.path.getsize(path) / 1024.0))
    return path


def _read_glb(path):
    with open(path, "rb") as stream:
        payload = stream.read()
    if len(payload) < 12:
        raise ValueError("{} is too short to be a GLB".format(path))
    magic, version, declared = struct.unpack_from("<4sII", payload, 0)
    if magic != b"glTF" or version != 2 or declared != len(payload):
        raise ValueError("{} has an invalid GLB header".format(path))
    document = None
    offset = 12
    while offset < len(payload):
        chunk_length, chunk_type = struct.unpack_from("<II", payload, offset)
        offset += 8
        chunk = payload[offset:offset + chunk_length]
        offset += chunk_length
        if chunk_type == _JSON_CHUNK:
            document = json.loads(chunk.decode("utf-8").rstrip(" \t\r\n\0"))
    if document is None:
        raise ValueError("{} has no JSON chunk".format(path))
    return document


def validate_glb(path):
    document = _read_glb(path)
    triangles = 0
    vertices = 0
    primitives = 0
    mesh_nodes = [node for node in document.get("nodes", []) if "mesh" in node]
    for mesh in document.get("meshes", []):
        for primitive in mesh.get("primitives", []):
            primitives += 1
            attributes = primitive.get("attributes", {})
            missing = {"COLOR_0", "TEXCOORD_0"} - set(attributes)
            if missing:
                raise ValueError("{} GLB is missing {}".format(path, sorted(missing)))
            if "POSITION" not in attributes:
                raise ValueError("{} GLB primitive has no POSITION".format(path))
            position = document["accessors"][attributes["POSITION"]]
            vertices += int(position["count"])
            if "indices" in primitive:
                triangles += int(document["accessors"][primitive["indices"]]["count"]) // 3
            else:
                triangles += int(position["count"]) // 3
    if primitives < 1:
        raise ValueError("{} has no mesh primitives".format(path))
    return {
        "triangles": triangles,
        "vertices": vertices,
        "primitives": primitives,
        "mesh_nodes": len(mesh_nodes),
    }


# --------------------------------------------------------------------------
# Paint
# --------------------------------------------------------------------------

def style_palette(style):
    palettes = {
        "terracotta_bond": (
            (0.70, 0.36, 0.26), (0.46, 0.30, 0.24), (0.82, 0.50, 0.36), (0.38, 0.24, 0.20)),
        "clapboard_pine": (
            (0.60, 0.46, 0.30), (0.38, 0.28, 0.18), (0.78, 0.64, 0.44), (0.28, 0.20, 0.16)),
        "lime_stucco": (
            (0.78, 0.74, 0.62), (0.58, 0.56, 0.46), (0.90, 0.86, 0.72), (0.42, 0.40, 0.34)),
        "charcoal_panel": (
            (0.22, 0.24, 0.26), (0.12, 0.13, 0.14), (0.38, 0.40, 0.42), (0.16, 0.16, 0.18)),
        "ashlar_sand": (
            (0.70, 0.62, 0.48), (0.48, 0.42, 0.32), (0.84, 0.76, 0.60), (0.40, 0.34, 0.26)),
        "verdigris_tile": (
            (0.30, 0.52, 0.46), (0.18, 0.32, 0.30), (0.52, 0.70, 0.58), (0.22, 0.36, 0.32)),
        "chalk_wash": (
            (0.86, 0.84, 0.78), (0.68, 0.66, 0.60), (0.96, 0.94, 0.88), (0.50, 0.48, 0.44)),
        "rust_plate": (
            (0.52, 0.30, 0.20), (0.28, 0.16, 0.12), (0.70, 0.42, 0.26), (0.24, 0.16, 0.12)),
        "amethyst_stucco": (
            (0.52, 0.38, 0.62), (0.34, 0.24, 0.42), (0.72, 0.56, 0.80), (0.28, 0.20, 0.34)),
        "neon_night": (
            (0.10, 0.12, 0.16), (0.04, 0.05, 0.07), (0.22, 0.70, 0.78), (0.08, 0.08, 0.10)),
    }
    return palettes.get(style, palettes["lime_stucco"])


def _fract(value):
    return value - math.floor(value)


def _brick(u, v, palette, scale_u=5.2, scale_v=10.4, seed=0.0):
    base, joint, accent, _roof = palette
    row = v * scale_v
    stagger = 0.5 if int(math.floor(row)) % 2 else 0.0
    col = u * scale_u + stagger
    mortar = 0.10
    gx, gy = _fract(col), _fract(row)
    if gx < mortar or gy < mortar * 1.6:
        return joint
    tone = 0.86 + 0.18 * hash01(math.floor(col), math.floor(row), seed)
    brick = mix(base, accent, hash01(math.floor(col) + 3.0, math.floor(row), seed) * 0.35)
    return (brick[0] * tone, brick[1] * tone, brick[2] * tone)


def _plank(u, v, palette, scale_u=3.4, scale_v=14.0, seed=0.0):
    base, joint, accent, _roof = palette
    board = u * scale_u
    grain = 0.5 + 0.5 * math.sin((v * scale_v + hash01(math.floor(board), seed) * 6.0) * 0.7)
    if _fract(board) < 0.08:
        return joint
    tone = 0.88 + 0.16 * grain + 0.06 * hash01(math.floor(board), seed)
    wood = mix(base, accent, 0.22 * grain)
    return (wood[0] * tone, wood[1] * tone, wood[2] * tone)


def _panel(u, v, palette, scale_u=3.6, scale_v=4.8, seed=0.0):
    base, joint, accent, _roof = palette
    gx, gy = _fract(u * scale_u), _fract(v * scale_v)
    seam = gx < 0.06 or gy < 0.07
    if seam:
        return joint
    blot = 0.5 + 0.5 * math.sin(u * 11.0 + v * 7.0 + seed)
    return mix(base, accent, blot * 0.22)


def _stucco(u, v, palette, seed=0.0):
    base, joint, accent, _roof = palette
    blot = 0.5 + 0.28 * math.sin((u * 6.4 + seed) * math.tau) + 0.22 * math.sin((v * 8.1 - seed) * math.tau)
    blot += 0.12 * hash01(u * 18.0, v * 16.0, seed)
    return mix(mix(base, accent, 0.28), joint, clamp01(0.18 + blot * 0.22))


def _roof_tiles(u, v, palette, seed=0.0):
    _base, joint, accent, roof = palette
    row = v * 18.0
    stagger = 0.5 if int(math.floor(row)) % 2 else 0.0
    col = u * 10.0 + stagger
    if _fract(col) < 0.08 or _fract(row) < 0.12:
        return (joint[0] * 0.7 + roof[0] * 0.3, joint[1] * 0.7 + roof[1] * 0.3, joint[2] * 0.7 + roof[2] * 0.3)
    tone = 0.86 + 0.16 * hash01(math.floor(col), math.floor(row), seed + 4.0)
    tile = mix(roof, accent, 0.18)
    return (tile[0] * tone, tile[1] * tone, tile[2] * tone)


def paint_pixel(recipe, style, u, v):
    palette = style_palette(style)
    seed = float(recipe.seed)
    if v >= 0.72:
        colour = _roof_tiles((u * 4.0) % 1.0, (v - 0.72) / 0.28, palette, seed)
        return (clamp01(colour[0]), clamp01(colour[1]), clamp01(colour[2]), 0.03)

    face_id = min(3, int(u * 4.0))
    local_u = (u - face_id * 0.25) / 0.25
    wall_top = max(recipe.wall_h, 1.0e-5)
    z = (v / 0.72) * wall_top
    rel = z - recipe.ground_h
    story = int(math.floor(rel / STORY)) if rel >= 0.0 else -1
    story_v = _fract(rel / STORY) if rel >= 0.0 else 0.0
    bays = recipe.bays_x if face_id % 2 == 0 else recipe.bays_y
    bay = min(bays - 1, max(0, int(clamp01(local_u) * bays)))
    bay_u = local_u * bays - bay

    if style in ("terracotta_bond", "ashlar_sand"):
        scale = (4.6, 9.2) if style == "terracotta_bond" else (3.2, 5.4)
        colour = _brick(local_u, v / 0.72, palette, scale[0], scale[1], seed + face_id)
    elif style == "clapboard_pine":
        colour = _plank(local_u, v / 0.72, palette, seed=seed + face_id)
    elif style in ("charcoal_panel", "rust_plate", "neon_night"):
        colour = _panel(local_u, v / 0.72, palette, seed=seed + face_id)
    elif style == "verdigris_tile":
        colour = _brick(local_u, v / 0.72, palette, 6.4, 6.4, seed + face_id)
    else:
        colour = _stucco(local_u, v / 0.72, palette, seed + face_id)

    ao = 0.72 + 0.28 * clamp01(z / max(recipe.ground_h * 1.8, 0.45))
    ao *= 0.70 + 0.30 * clamp01((wall_top - z) / 1.15)
    colour = (colour[0] * ao, colour[1] * ao, colour[2] * ao)
    alpha = 0.018

    in_wall = story >= 0 and z < wall_top - 0.02
    window = in_wall and 0.18 <= bay_u <= 0.82 and 0.22 <= story_v <= 0.78
    if window:
        lit = window_is_lit(recipe, face_id, bay, story, style)
        glow = glow_for(recipe, style)
        if style == "neon_night":
            pane = glow if lit else (0.08, 0.10, 0.14)
        else:
            pane = glow if lit else (0.12, 0.13, 0.15)
        mullion = abs(bay_u - 0.5) < 0.03 or abs(story_v - 0.5) < 0.035
        if mullion:
            colour = mix(colour, palette[1], 0.65)
            alpha = 0.05
        else:
            colour = mix(colour, pane, 0.82 if lit else 0.55)
            alpha = 0.92 if lit else 0.07
    return (clamp01(colour[0]), clamp01(colour[1]), clamp01(colour[2]), clamp01(alpha))


def write_paint(recipe, style, path, size=None):
    size = int(size or recipe.paint_size)
    os.makedirs(os.path.dirname(path), exist_ok=True)
    image = bpy.data.images.new(
        "{0}_{1}_paint".format(recipe.name, style),
        width=size, height=size, alpha=True, float_buffer=False)
    try:
        image.colorspace_settings.name = "sRGB"
    except TypeError:
        pass
    pixels = [0.0] * (size * size * 4)
    index = 0
    for y in range(size):
        v = (y + 0.5) / size
        for x in range(size):
            u = (x + 0.5) / size
            pixel = paint_pixel(recipe, style, u, v)
            pixels[index:index + 4] = pixel
            index += 4
    image.pixels.foreach_set(pixels)
    mean_alpha = sum(pixels[3::4]) / float(size * size)
    min_alpha = 0.012 if recipe.walkable else 0.04
    if mean_alpha < min_alpha:
        raise ValueError("{0} {1} paint mean alpha {2:.4f} < {3:.4f}".format(
            recipe.name, style, mean_alpha, min_alpha))
    image.filepath_raw = path
    image.file_format = "PNG"
    image.save()
    if not os.path.isfile(path) or os.path.getsize(path) <= 0:
        raise ValueError("paint did not write {}".format(path))
    return image


def write_paint_strip(images, path, tile=128):
    live = [image for image in images if image is not None]
    if not live:
        raise ValueError("write_paint_strip has no images")
    os.makedirs(os.path.dirname(path), exist_ok=True)
    count = len(live)
    width, height = tile * count, tile
    strip = bpy.data.images.new("building_paint_strip", width=width, height=height, alpha=True)
    try:
        strip.colorspace_settings.name = "sRGB"
    except TypeError:
        pass
    pixels = [0.0] * (width * height * 4)
    for i, image in enumerate(live):
        src_w, src_h = int(image.size[0]), int(image.size[1])
        source = list(image.pixels)
        for y in range(tile):
            sy = min(src_h - 1, int((y + 0.5) * src_h / tile))
            for x in range(tile):
                sx = min(src_w - 1, int((x + 0.5) * src_w / tile))
                src = (sy * src_w + sx) * 4
                dst = (y * width + i * tile + x) * 4
                pixels[dst:dst + 4] = source[src:src + 4]
    strip.pixels.foreach_set(pixels)
    strip.filepath_raw = path
    strip.file_format = "PNG"
    strip.save()
    return strip
