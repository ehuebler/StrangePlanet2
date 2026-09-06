"""Build the rigged land-fauna creatures from connected organic skin-trees.

Run from the project root with Blender 5.1:

    & "C:\\Program Files\\Blender Foundation\\Blender 5.1\\blender.exe" `
        --background --factory-startup `
        --python assets/source/blender/build_fauna_creatures.py

    # one species:
    ... --python assets/source/blender/build_fauna_creatures.py -- --only tide_latch_crab
"""

from __future__ import annotations

import argparse
import math
import os
import sys

SOURCE_DIR = os.path.dirname(os.path.abspath(__file__))
if SOURCE_DIR not in sys.path:
    sys.path.insert(0, SOURCE_DIR)

from creature_kit import (
    CreatureSpec,
    Joint,
    REQUIRED_CORE_CLIPS,
    build_creature,
    ease,
    motif_bands,
    motif_blaze,
    motif_chevrons,
    motif_rings,
    motif_spots,
    motif_streaks,
    pulse,
    rgba,
)


TAU = math.tau


def J(name, parent, position, radius, *, deform=True, volume=False,
      connected=False, tail=None) -> Joint:
    return Joint(
        name, parent, position, radius,
        deform=deform, volume_only=volume, connected=connected, tail=tail)


def chain(parent: str, steps: list[tuple], *, connected=True) -> list[Joint]:
    """steps: (name, position, radius). First bone hangs from parent, the rest connect."""
    joints = []
    previous = parent
    for index, (name, position, radius) in enumerate(steps):
        joints.append(J(
            name, previous, position, radius,
            connected=connected and index > 0))
        previous = name
    return joints


def quad_leg(side: str, end: str, parent: str, hip, knee, foot,
             radius=(0.045, 0.032, 0.028)) -> list[Joint]:
    prefix = side + end
    return chain(parent, [
        (prefix + "UpperLeg", hip, radius[0]),
        (prefix + "LowerLeg", knee, radius[1]),
        (prefix + "Foot", foot, radius[2]),
    ])


def quad_limb_groups() -> tuple:
    return tuple(
        (side + end + "UpperLeg", side + end + "LowerLeg", side + end + "Foot")
        for end in ("Front", "Hind")
        for side in ("Left", "Right")
    )


def painter(palette, seed, styles):
    def paint_pixel(index, u, v):
        phase = seed * 0.00041 + index * 0.23
        base = palette[index]
        style = styles[index]
        if style == "streaks":
            return motif_streaks(base, u, v, phase)
        if style == "bands":
            accent = palette[min(index + 1, len(palette) - 1)]
            return motif_bands(base, accent, u, v, phase)
        if style == "spots":
            return motif_spots(base, u, v, phase)
        if style == "chevrons":
            return motif_chevrons(base, u, v, phase)
        if style == "rings":
            return motif_rings(base, u, v, phase)
        return motif_blaze(base, u, v, phase)
    return paint_pixel


def shares(centre, height):
    return (
        centre.x / height,
        centre.y / height,
        centre.z / height,
    )


# --------------------------------------------------------------------------
# Animation factories
# --------------------------------------------------------------------------

def core_table(idle, walk, run, attack, hit, defeat, graze=None):
    table = [
        ("Idle", 84, True, idle),
        ("Walk", 32, True, walk),
        ("Run", 22, True, run),
    ]
    if graze is not None:
        table.append(("Graze", 100, True, graze))
    table.extend([
        ("Attack", 28, False, attack),
        ("HitReact", 16, False, hit),
        ("Defeat", 42, False, defeat),
    ])
    return table


def quadruped_animations(anim, prefixes, attack="headbutt", graze=False):
    rot = anim.rot
    walk_order = {
        prefixes[0]: 0.0, prefixes[1]: 0.25,
        prefixes[2]: 0.5, prefixes[3]: 0.75,
    }
    # prefixes: LeftFront, RightFront, LeftHind, RightHind
    walk_order = {
        "LeftFront": 0.0, "LeftHind": 0.25,
        "RightFront": 0.5, "RightHind": 0.75,
    }
    trot_order = {
        "LeftFront": 0.0, "RightHind": 0.0,
        "RightFront": 0.5, "LeftHind": 0.5,
    }

    def stride(pose, phase, order, swing, knee, foot, share=1.0):
        for prefix, offset in order.items():
            leg = phase + offset * TAU
            reach = math.sin(leg)
            fold = max(0.0, -math.cos(leg)) ** 1.4
            direction = -1.0 if prefix.endswith("Front") else 1.0
            pose[prefix + "UpperLeg"] = rot(("X", swing * reach * share))
            pose[prefix + "LowerLeg"] = rot(
                ("X", direction * knee * fold * share))
            pose[prefix + "Foot"] = rot(
                ("X", (foot * fold - swing * reach * 0.45) * share))

    def planted(pose, drop, spread=0.0, fold=0.0):
        for prefix in ("LeftFront", "RightFront", "LeftHind", "RightHind"):
            sign = -1.0 if prefix.startswith("Left") else 1.0
            direction = -1.0 if prefix.endswith("Front") else 1.0
            pose[prefix + "UpperLeg"] = rot(
                ("X", drop * (1.0 if prefix.endswith("Front") else -0.55)),
                ("Y", -sign * spread))
            pose[prefix + "LowerLeg"] = rot(("X", direction * fold))
            pose[prefix + "Foot"] = rot(("X", -direction * fold * 0.45))

    def idle_pose(t):
        breath = math.sin(t * TAU)
        sway = math.sin(t * TAU * 0.5)
        pose = {
            "Hips": {"rot": [("Z", 1.2 * sway)],
                     "loc": (0.0, 0.0, 0.004 * breath)},
            "Spine": rot(("X", 1.0 * breath), ("Z", -0.8 * sway)),
            "Chest": rot(("X", -1.0 + 1.2 * breath)),
            "Neck": rot(("X", 2.2 + 1.6 * breath), ("Z", 1.8 * sway)),
            "Head": rot(("X", -1.4 - 1.0 * breath), ("Z", 2.4 * sway)),
        }
        if "Tail" in {"Tail"}:
            pose["Tail"] = rot(("Z", 8.0 * math.sin(t * TAU * 1.4)))
        stride(pose, 0.0, walk_order, 0.0, 0.0, 0.0)
        return pose

    def walk_pose(t):
        phase = t * TAU
        pose = {}
        stride(pose, phase, walk_order, swing=18.0, knee=28.0, foot=12.0)
        dip = -0.012 * (1.0 - math.cos(phase * 2.0)) * 0.5
        pose["Hips"] = {
            "rot": [("Z", 3.2 * math.sin(phase)), ("Y", 2.4 * math.sin(phase))],
            "loc": (0.003 * math.sin(phase), 0.0, dip),
        }
        pose["Spine"] = rot(("Z", -2.2 * math.sin(phase)))
        pose["Chest"] = rot(("X", -1.0), ("Z", -2.6 * math.sin(phase)))
        pose["Neck"] = rot(("X", 2.6 + 2.0 * math.sin(phase * 2.0)))
        pose["Head"] = rot(("X", -1.8 - 1.6 * math.sin(phase * 2.0)))
        pose["Tail"] = rot(("Z", 12.0 * math.sin(phase)))
        return pose

    def run_pose(t):
        phase = t * TAU
        pose = {}
        stride(pose, phase, trot_order, swing=30.0, knee=42.0, foot=18.0)
        pose["Hips"] = {
            "rot": [("X", -2.0), ("Z", 3.6 * math.sin(phase))],
            "loc": (0.0, 0.0, 0.012 - 0.022 * (1.0 - math.cos(phase * 2.0)) * 0.5),
        }
        pose["Spine"] = rot(("X", 2.0), ("Z", -3.0 * math.sin(phase)))
        pose["Chest"] = rot(("X", -4.0))
        pose["Neck"] = rot(("X", -8.0 + 3.0 * math.sin(phase * 2.0)))
        pose["Head"] = rot(("X", 3.0 - 2.0 * math.sin(phase * 2.0)))
        pose["Tail"] = rot(("X", 14.0), ("Z", 14.0 * math.sin(phase * 2.0)))
        return pose

    def attack_pose(t):
        draw = ease(t / 0.36)
        throw = ease((t - 0.36) / 0.22)
        settle = ease((t - 0.64) / 0.36)
        active = 1.0 - settle
        pose = {}
        planted(pose, drop=-4.0 * active, spread=4.0 * active, fold=6.0 * active)
        if attack == "bite":
            pose["Hips"] = {"rot": [("X", 6.0 * draw * active - 8.0 * throw * active)],
                            "loc": (0.0, 0.02 * throw * active, 0.0)}
            pose["Neck"] = rot(("X", 16.0 * draw * active - 38.0 * throw * active))
            pose["Head"] = rot(("X", 12.0 * draw * active + 22.0 * throw * active))
            pose["Jaw"] = rot(("X", 28.0 * draw * active - 20.0 * throw * active))
        else:
            pose["Hips"] = {"rot": [("X", 4.0 * draw * active)],
                            "loc": (0.0, 0.016 * throw * active, 0.0)}
            pose["Spine"] = rot(("X", 6.0 * draw * active - 5.0 * throw * active))
            pose["Chest"] = rot(("X", 8.0 * draw * active - 10.0 * throw * active))
            pose["Neck"] = rot(("X", 18.0 * draw * active - 36.0 * throw * active))
            pose["Head"] = rot(("X", 10.0 * draw * active + 20.0 * throw * active))
        pose["Tail"] = rot(("X", 12.0 * draw * active))
        return pose

    def hit_pose(t):
        hit = math.sin(math.pi * min(t, 1.0))
        pose = {}
        planted(pose, drop=-6.0 * hit, spread=6.0 * hit, fold=8.0 * hit)
        pose["Hips"] = {"rot": [("Z", -5.0 * hit), ("X", -6.0 * hit)],
                        "loc": (0.0, -0.01 * hit, -0.02 * hit)}
        pose["Neck"] = rot(("X", 14.0 * hit), ("Z", -8.0 * hit))
        pose["Head"] = rot(("X", -12.0 * hit))
        pose["Tail"] = rot(("X", -16.0 * hit))
        return pose

    def defeat_pose(t):
        buckle = ease(t / 0.4)
        limp = ease((t - 0.32) / 0.68)
        pose = {}
        planted(pose, drop=-16.0 * buckle, spread=16.0 * buckle, fold=46.0 * buckle)
        pose["Hips"] = {
            "rot": [("X", -12.0 * buckle), ("Z", -12.0 * limp)],
            "loc": (0.0, -0.01 * buckle, -0.12 * buckle),
        }
        pose["Neck"] = rot(("X", 8.0 * buckle - 40.0 * limp))
        pose["Head"] = rot(("X", 4.0 * buckle - 22.0 * limp))
        pose["Tail"] = rot(("X", -20.0 * limp))
        return pose

    def graze_pose(t):
        nibble = math.sin(t * TAU)
        pose = {}
        planted(pose, drop=-4.0, spread=4.0, fold=6.0)
        pose["Hips"] = {"rot": [("X", -2.0)], "loc": (0.0, 0.0, -0.014)}
        pose["Spine"] = rot(("X", -4.0))
        pose["Chest"] = rot(("X", -8.0))
        pose["Neck"] = rot(("X", -58.0 - 2.0 * nibble))
        pose["Head"] = rot(("X", 8.0 - 5.0 * nibble))
        pose["Tail"] = rot(("Z", 7.0 * math.sin(t * TAU * 1.4)))
        return pose

    return core_table(
        idle_pose, walk_pose, run_pose, attack_pose, hit_pose, defeat_pose,
        graze=graze_pose if graze else None)


def biped_animations(anim, four_arms=False, monster=False):
    rot = anim.rot
    arms = [("Left", -1.0), ("Right", 1.0)]
    extra = [("Left", -1.0, "B"), ("Right", 1.0, "B")] if four_arms else []

    def hang(pose, side, sign, out, swing=0.0, flex=0.0, suffix=""):
        pose[side + "UpperArm" + suffix] = rot(("Y", sign * (12.0 - out)), ("X", swing))
        pose[side + "LowerArm" + suffix] = rot(("X", flex))

    def idle_pose(t):
        breath = math.sin(t * TAU)
        pose = {
            "Hips": {"rot": [("X", 0.6 * breath)], "loc": (0.0, 0.0, 0.005 * breath)},
            "Spine": rot(("X", -0.8 * breath + (-12.0 if monster else 0.0))),
            "Chest": rot(("X", 1.2 * breath)),
            "Neck": rot(("X", -1.0 * breath)),
            "Head": rot(("X", 0.8 * breath), ("Z", 2.0 * math.sin(t * TAU * 0.5))),
        }
        for side, sign, offset in (("Left", -1.0, math.pi), ("Right", 1.0, 0.0)):
            pose[side + "UpperLeg"] = rot(("X", 2.0 * breath), ("Y", -sign * 4.0))
            pose[side + "LowerLeg"] = rot(("X", -6.0 if monster else -4.0))
            hang(pose, side, sign, out=14.0 + 1.0 * breath, swing=-18.0 if monster else 2.0,
                 flex=18.0 if monster else 12.0)
        for side, sign, suffix in extra:
            hang(pose, side, sign, out=20.0, swing=-8.0, flex=16.0, suffix=suffix)
        pose["Jaw"] = rot(("X", 2.0 * breath))
        return pose

    def walk_pose(t):
        phase = t * TAU
        pose = {}
        for side, sign, offset in (("Left", -1.0, math.pi), ("Right", 1.0, 0.0)):
            leg = phase + offset
            pose[side + "UpperLeg"] = rot(("X", 26.0 * math.sin(leg)), ("Y", -sign * 4.0))
            pose[side + "LowerLeg"] = rot(("X", min(-8.0, -32.0 + 26.0 * math.sin(leg - 1.1))))
            pose[side + "Foot"] = rot(("X", 10.0 * math.sin(leg + 0.5)))
            hang(pose, side, sign, out=14.0,
                 swing=(-28.0 if monster else -22.0) * math.sin(leg),
                 flex=16.0 + 8.0 * max(0.0, math.sin(leg)))
        for side, sign, suffix in extra:
            hang(pose, side, sign, out=18.0,
                 swing=-16.0 * math.sin(phase + (0.0 if sign > 0 else math.pi)),
                 flex=14.0, suffix=suffix)
        pose["Hips"] = {"rot": [("Z", 6.0 * math.sin(phase))],
                        "loc": (0.008 * math.sin(phase), 0.0,
                                -0.018 * (1.0 - math.cos(2.0 * phase)) * 0.5)}
        pose["Spine"] = rot(("Z", -4.0 * math.sin(phase)),
                            ("X", -10.0 if monster else 3.0))
        pose["Chest"] = rot(("Z", -5.0 * math.sin(phase)))
        pose["Head"] = rot(("Z", 3.0 * math.sin(phase)))
        return pose

    def run_pose(t):
        phase = t * TAU
        pose = {}
        for side, sign, offset in (("Left", -1.0, math.pi), ("Right", 1.0, 0.0)):
            leg = phase + offset
            pose[side + "UpperLeg"] = rot(("X", 40.0 * math.sin(leg)))
            pose[side + "LowerLeg"] = rot(("X", -50.0 + 36.0 * math.sin(leg - 1.0)))
            hang(pose, side, sign, out=18.0, swing=-40.0 * math.sin(leg), flex=22.0)
        pose["Hips"] = {"rot": [("X", -4.0), ("Z", 8.0 * math.sin(phase))],
                        "loc": (0.0, 0.0, -0.03 * (1.0 - math.cos(2.0 * phase)) * 0.5)}
        pose["Spine"] = rot(("X", -18.0 if monster else -8.0))
        pose["Chest"] = rot(("X", -10.0))
        pose["Head"] = rot(("X", 12.0))
        return pose

    def attack_pose(t):
        wind = pulse(t, 0.0, 0.32, 0.52)
        strike = pulse(t, 0.28, 0.50, 0.78)
        pose = {
            "Hips": {"rot": [("X", 6.0 * wind - 8.0 * strike)],
                     "loc": (0.0, 0.03 * strike, 0.0)},
            "Spine": rot(("X", 8.0 * wind - 12.0 * strike), ("Y", 10.0 * strike)),
            "Chest": rot(("Y", 16.0 * strike)),
            "Head": rot(("X", -8.0 * strike)),
            "Jaw": rot(("X", 24.0 * wind)),
        }
        hang(pose, "Right", 1.0, out=28.0,
             swing=-40.0 * wind + 110.0 * strike, flex=20.0 - 12.0 * strike)
        hang(pose, "Left", -1.0, out=16.0, swing=20.0 * strike, flex=24.0)
        if four_arms:
            hang(pose, "Right", 1.0, out=24.0,
                 swing=80.0 * strike, flex=10.0, suffix="B")
            hang(pose, "Left", -1.0, out=24.0,
                 swing=70.0 * strike, flex=10.0, suffix="B")
        for side, sign in (("Left", -1.0), ("Right", 1.0)):
            pose[side + "UpperLeg"] = rot(("X", -6.0 * strike), ("Y", -sign * 5.0))
            pose[side + "LowerLeg"] = rot(("X", -10.0 * strike))
        return pose

    def hit_pose(t):
        hit = math.sin(math.pi * min(t, 1.0))
        pose = {
            "Hips": {"rot": [("Z", -8.0 * hit), ("X", -8.0 * hit)],
                     "loc": (0.0, -0.02 * hit, -0.03 * hit)},
            "Spine": rot(("X", 10.0 * hit)),
            "Head": rot(("X", -16.0 * hit), ("Z", -8.0 * hit)),
        }
        for side, sign in (("Left", -1.0), ("Right", 1.0)):
            pose[side + "UpperLeg"] = rot(("X", -8.0 * hit), ("Y", -sign * 8.0))
            hang(pose, side, sign, out=22.0, swing=16.0 * hit, flex=28.0 * hit)
        return pose

    def defeat_pose(t):
        fall = ease(t)
        pose = {
            "Hips": {"rot": [("X", -18.0 * fall), ("Z", -16.0 * fall)],
                     "loc": (0.0, -0.04 * fall, -0.16 * fall)},
            "Spine": rot(("X", -20.0 * fall)),
            "Chest": rot(("X", -12.0 * fall)),
            "Head": rot(("X", -28.0 * fall)),
            "Jaw": rot(("X", 18.0 * fall)),
        }
        for side, sign in (("Left", -1.0), ("Right", 1.0)):
            pose[side + "UpperLeg"] = rot(("X", -20.0 * fall), ("Y", -sign * 16.0))
            pose[side + "LowerLeg"] = rot(("X", -70.0 * fall))
            hang(pose, side, sign, out=8.0, swing=-24.0 * fall, flex=40.0 * fall)
        return pose

    return core_table(
        idle_pose, walk_pose, run_pose, attack_pose, hit_pose, defeat_pose)


# --------------------------------------------------------------------------
# Creatures
# --------------------------------------------------------------------------

def crab() -> CreatureSpec:
    h = 0.40
    palette = rgba("C45A3A", "F2D3B0", "2FA6A0", "E8B84A", "5CE0FF", "E85CA8")
    joints = [
        J("Root", None, (0.0, 0.0, 0.01), 0.018, deform=False),
        J("Hips", "Root", (0.0, -0.02, 0.15), (0.12, 0.068)),
        J("Carapace", "Hips", (0.0, 0.02, 0.20), (0.16, 0.062)),
        J("CarapaceL", "Hips", (-0.10, 0.00, 0.18), (0.09, 0.050), volume=True),
        J("CarapaceR", "Hips", (0.10, 0.00, 0.18), (0.09, 0.050), volume=True),
        J("CarapaceRear", "Hips", (0.0, -0.12, 0.15), (0.10, 0.046), volume=True),
        J("Chest", "Carapace", (0.0, 0.10, 0.16), (0.10, 0.055)),
        J("Head", "Chest", (0.0, 0.16, 0.15), 0.050),
        J("LeftEye", "Head", (-0.045, 0.18, 0.23), 0.015),
        J("RightEye", "Head", (0.045, 0.18, 0.23), 0.015),
    ]
    joints += chain("Chest", [
        ("LeftClawUpper", (-0.10, 0.14, 0.14), 0.034),
        ("LeftClawLower", (-0.13, 0.22, 0.11), 0.030),
        ("LeftClawTip", (-0.12, 0.28, 0.09), 0.016),
    ])
    joints += chain("Chest", [
        ("RightClawUpper", (0.10, 0.14, 0.14), 0.034),
        ("RightClawLower", (0.13, 0.22, 0.11), 0.030),
        ("RightClawTip", (0.12, 0.28, 0.09), 0.016),
    ])
    for index, y in ((1, -0.08), (2, 0.00), (3, 0.08)):
        parent = "Hips" if index < 3 else "Chest"
        joints += chain(parent, [
            ("Left{0}Upper".format(index), (-0.13, y, 0.12), 0.020),
            ("Left{0}Lower".format(index), (-0.20, y - 0.01, 0.06), 0.015),
            ("Left{0}Foot".format(index), (-0.24, y - 0.02, 0.012), 0.018),
        ])
        joints += chain(parent, [
            ("Right{0}Upper".format(index), (0.13, y, 0.12), 0.020),
            ("Right{0}Lower".format(index), (0.20, y - 0.01, 0.06), 0.015),
            ("Right{0}Foot".format(index), (0.24, y - 0.02, 0.012), 0.018),
        ])

    def region_of(centre, height):
        x, y, z = shares(centre, height)
        if z > 0.52 and abs(x) > 0.06 and y > 0.25:
            return 4
        if y > 0.55:
            return 5
        if z < 0.22 and abs(x) > 0.18:
            return 3
        if z < 0.28 and abs(y) < 0.20:
            return 1
        if abs(x) > 0.22 and z > 0.30:
            return 2
        return 0

    def animations(anim):
        rot = anim.rot
        legs = [
            ("Left1", 0.0), ("Right2", 0.0), ("Left3", 0.0),
            ("Right1", 0.5), ("Left2", 0.5), ("Right3", 0.5),
        ]

        def cycle(pose, phase, swing, fold):
            for prefix, offset in legs:
                wave = phase + offset * TAU
                sign = -1.0 if prefix.startswith("Left") else 1.0
                pose[prefix + "Upper"] = rot(
                    ("Y", sign * swing * math.sin(wave)),
                    ("X", 8.0 * math.sin(wave)))
                pose[prefix + "Lower"] = rot(("X", fold * max(0.0, -math.cos(wave))))
                pose[prefix + "Foot"] = rot(("X", -0.4 * fold * max(0.0, -math.cos(wave))))

        def idle_pose(t):
            breath = math.sin(t * TAU)
            pose = {
                "Hips": {"rot": [("Z", 1.5 * math.sin(t * TAU * 0.5))],
                         "loc": (0.0, 0.0, 0.003 * breath)},
                "Carapace": rot(("X", 1.2 * breath)),
                "Head": rot(("Z", 3.0 * math.sin(t * TAU * 0.5))),
                "LeftEye": rot(("X", 6.0 * breath)),
                "RightEye": rot(("X", -4.0 * breath)),
                "LeftClawUpper": rot(("Y", -6.0), ("X", 4.0 * breath)),
                "RightClawUpper": rot(("Y", 6.0), ("X", -4.0 * breath)),
            }
            cycle(pose, 0.0, 0.0, 0.0)
            return pose

        def walk_pose(t):
            phase = t * TAU
            pose = {
                "Hips": {"rot": [("Z", 4.0 * math.sin(phase)), ("Y", 6.0)],
                         "loc": (0.006 * math.sin(phase), 0.0,
                                 -0.008 * (1.0 - math.cos(phase * 2.0)) * 0.5)},
                "Carapace": rot(("Y", 3.0 * math.sin(phase))),
                "Head": rot(("Z", 4.0 * math.sin(phase))),
                "LeftClawUpper": rot(("Y", -8.0), ("X", 6.0 * math.sin(phase))),
                "RightClawUpper": rot(("Y", 8.0), ("X", -6.0 * math.sin(phase))),
            }
            cycle(pose, phase, 14.0, 16.0)
            return pose

        def run_pose(t):
            phase = t * TAU
            pose = {
                "Hips": {"rot": [("Y", 8.0), ("Z", 5.0 * math.sin(phase))],
                         "loc": (0.0, 0.0, 0.01)},
                "Carapace": rot(("X", -4.0)),
            }
            cycle(pose, phase, 18.0, 20.0)
            return pose

        def attack_pose(t):
            snap = pulse(t, 0.18, 0.42, 0.70)
            wind = pulse(t, 0.0, 0.22, 0.40)
            pose = {
                "Hips": {"rot": [("X", 6.0 * wind)], "loc": (0.0, 0.02 * snap, 0.0)},
                "Head": rot(("X", -8.0 * snap)),
                "LeftClawUpper": rot(("Y", -18.0 * wind + 28.0 * snap),
                                     ("X", 16.0 * wind)),
                "LeftClawLower": rot(("X", 22.0 * wind - 40.0 * snap)),
                "RightClawUpper": rot(("Y", 18.0 * wind - 28.0 * snap),
                                      ("X", 16.0 * wind)),
                "RightClawLower": rot(("X", 22.0 * wind - 40.0 * snap)),
            }
            cycle(pose, 0.0, 0.0, 8.0 * wind)
            return pose

        def hit_pose(t):
            hit = math.sin(math.pi * min(t, 1.0))
            return {
                "Hips": {"rot": [("Z", -10.0 * hit)],
                         "loc": (0.0, -0.015 * hit, -0.012 * hit)},
                "Carapace": rot(("X", 8.0 * hit)),
                "LeftClawUpper": rot(("Y", 16.0 * hit)),
                "RightClawUpper": rot(("Y", -16.0 * hit)),
            }

        def defeat_pose(t):
            fall = ease(t)
            return {
                "Hips": {"rot": [("Z", -22.0 * fall), ("X", -8.0 * fall)],
                         "loc": (0.0, 0.0, -0.06 * fall)},
                "Carapace": rot(("X", 12.0 * fall)),
                "LeftClawUpper": rot(("Y", 30.0 * fall)),
                "RightClawUpper": rot(("Y", -30.0 * fall)),
            }

        return core_table(
            idle_pose, walk_pose, run_pose, attack_pose, hit_pose, defeat_pose)

    limbs = [
        ("LeftClawUpper", "LeftClawLower", "LeftClawTip"),
        ("RightClawUpper", "RightClawLower", "RightClawTip"),
    ]
    for index in (1, 2, 3):
        for side in ("Left", "Right"):
            limbs.append((
                "{0}{1}Upper".format(side, index),
                "{0}{1}Lower".format(side, index),
                "{0}{1}Foot".format(side, index),
            ))
    return CreatureSpec(
        "tide_latch_crab", "Tide-Latch Crab", "crab", 20268201, h, palette,
        (2400, 5600),
        {"shape": "capsule", "radius": 0.22, "height": 0.34,
         "centre": [0.0, 0.17, 0.0]},
        "Coral carapace bands, cream belly, teal limb joints, gold claw plates, "
        "cyan eye-glow discs, and magenta pincer tips",
        "eye stalks and claw-seam glow after sunset",
        1.45, joints, limbs, REQUIRED_CORE_CLIPS, region_of,
        painter(palette, 20268201,
                ("bands", "blaze", "streaks", "rings", "spots", "chevrons")),
        animations, roughness=0.48)


def dolphin() -> CreatureSpec:
    h = 0.58
    palette = rgba("6EC4E0", "F4F1E6", "2A7F8C", "3550A8", "F0C85A", "F2A0C8")
    joints = [
        J("Root", None, (0.0, 0.12, 0.01), 0.02, deform=False),
        J("Hips", "Root", (0.0, -0.10, 0.18), 0.090),
        J("Spine", "Hips", (0.0, 0.08, 0.21), 0.125),
        J("Chest", "Spine", (0.0, 0.28, 0.21), 0.115),
        J("Neck", "Chest", (0.0, 0.46, 0.19), 0.080),
        J("Head", "Neck", (0.0, 0.60, 0.19), 0.072),
        J("Snout", "Head", (0.0, 0.76, 0.16), 0.028, connected=True),
        J("Melon", "Head", (0.0, 0.58, 0.25), 0.048, volume=True),
        J("Belly", "Spine", (0.0, 0.12, 0.11), 0.090, volume=True),
        J("Keel", "Chest", (0.0, 0.30, 0.13), 0.070, volume=True),
        J("Dorsal", "Spine", (0.0, 0.10, 0.32), (0.024, 0.055)),
        J("DorsalTip", "Dorsal", (0.0, 0.08, 0.40), (0.016, 0.028), volume=True),
        J("LeftPectoral", "Chest", (-0.13, 0.26, 0.14), (0.055, 0.018)),
        J("RightPectoral", "Chest", (0.13, 0.26, 0.14), (0.055, 0.018)),
    ]
    joints += chain("Hips", [
        ("Tail", (0.0, -0.28, 0.17), 0.042),
        ("TailMid", (0.0, -0.46, 0.15), 0.028),
        ("Fluke", (0.0, -0.62, 0.14), (0.12, 0.020)),
    ])
    joints += [
        J("FlukeL", "Fluke", (-0.10, -0.64, 0.14), (0.060, 0.016), volume=True),
        J("FlukeR", "Fluke", (0.10, -0.64, 0.14), (0.060, 0.016), volume=True),
    ]

    def region_of(centre, height):
        x, y, z = shares(centre, height)
        if z > 0.58:
            return 4
        if y < -0.85:
            return 3
        if y > 0.95:
            return 5
        if z < 0.28:
            return 1
        if abs(x) > 0.16 and 0.20 < y < 0.70:
            return 2
        return 0

    def animations(anim):
        rot = anim.rot

        def wave(pose, phase, amount):
            pose["Hips"] = {"rot": [("X", amount * 0.35 * math.sin(phase))],
                            "loc": (0.0, 0.0, 0.006 * math.sin(phase))}
            pose["Spine"] = rot(("X", amount * 0.55 * math.sin(phase + 0.4)))
            pose["Chest"] = rot(("X", amount * 0.45 * math.sin(phase + 0.8)))
            pose["Neck"] = rot(("X", amount * 0.35 * math.sin(phase + 1.1)))
            pose["Head"] = rot(("X", amount * 0.25 * math.sin(phase + 1.4)))
            pose["Snout"] = rot(("X", amount * 0.15 * math.sin(phase + 1.6)))
            pose["Tail"] = rot(("X", amount * 0.80 * math.sin(phase + 3.2)))
            pose["TailMid"] = rot(("X", amount * 1.10 * math.sin(phase + 3.6)))
            pose["Fluke"] = rot(("X", amount * 1.30 * math.sin(phase + 4.0)))
            pose["LeftPectoral"] = rot(("Z", 12.0 * math.sin(phase)))
            pose["RightPectoral"] = rot(("Z", -12.0 * math.sin(phase)))
            pose["Dorsal"] = rot(("Y", 4.0 * math.sin(phase)))

        def idle_pose(t):
            pose = {}
            wave(pose, t * TAU, 6.0)
            return pose

        def walk_pose(t):
            pose = {}
            wave(pose, t * TAU, 18.0)
            return pose

        def run_pose(t):
            pose = {}
            wave(pose, t * TAU, 28.0)
            return pose

        def attack_pose(t):
            ram = pulse(t, 0.20, 0.46, 0.78)
            wind = pulse(t, 0.0, 0.22, 0.40)
            pose = {
                "Hips": {"rot": [("X", -8.0 * wind + 10.0 * ram)],
                         "loc": (0.0, 0.04 * ram, 0.0)},
                "Spine": rot(("X", -6.0 * wind + 8.0 * ram)),
                "Neck": rot(("X", 10.0 * wind - 22.0 * ram)),
                "Head": rot(("X", 8.0 * wind + 16.0 * ram)),
                "Snout": rot(("X", 6.0 * ram)),
                "Tail": rot(("X", -16.0 * ram)),
            }
            return pose

        def hit_pose(t):
            hit = math.sin(math.pi * min(t, 1.0))
            return {
                "Hips": {"rot": [("Z", -10.0 * hit)],
                         "loc": (0.0, -0.02 * hit, -0.01 * hit)},
                "Head": rot(("X", -12.0 * hit)),
                "Tail": rot(("X", 14.0 * hit)),
            }

        def defeat_pose(t):
            fall = ease(t)
            return {
                "Hips": {"rot": [("Z", 24.0 * fall), ("X", -8.0 * fall)],
                         "loc": (0.0, 0.0, -0.08 * fall)},
                "Tail": rot(("X", 20.0 * fall)),
                "Head": rot(("X", -16.0 * fall)),
            }

        return core_table(
            idle_pose, walk_pose, run_pose, attack_pose, hit_pose, defeat_pose)

    return CreatureSpec(
        "prism_fin_dolphin", "Prism-Fin Dolphin", "dolphin", 20268202, h, palette,
        (3200, 6800),
        {"shape": "capsule", "radius": 0.20, "height": 0.48,
         "centre": [0.0, 0.24, 0.0]},
        "Silver-blue flank streaks, cream belly blaze, teal side-stripe, indigo "
        "flukes, gold dorsal marks, and a pink melon glow",
        "melon and dorsal leading-edge glow after sunset",
        1.55, joints,
        (("LeftPectoral",), ("RightPectoral",),
         ("Tail", "TailMid", "Fluke"), ("Dorsal",)),
        REQUIRED_CORE_CLIPS, region_of,
        painter(palette, 20268202,
                ("streaks", "blaze", "bands", "chevrons", "spots", "blaze")),
        animations, roughness=0.32)


def bird() -> CreatureSpec:
    h = 0.56
    palette = rgba("6B3FA0", "F0C24A", "2EB5A8", "F3E6C8", "E85CA8", "B6F25A")
    joints = [
        J("Root", None, (0.0, 0.0, 0.01), 0.016, deform=False),
        J("Hips", "Root", (0.0, -0.02, 0.24), 0.080),
        J("Spine", "Hips", (0.0, 0.02, 0.30), 0.090),
        J("Chest", "Spine", (0.0, 0.06, 0.33), 0.088),
        J("Waist", "Hips", (0.0, 0.01, 0.27), 0.075, volume=True),
        J("Neck", "Chest", (0.0, 0.08, 0.43), 0.032),
        J("Head", "Neck", (0.0, 0.12, 0.51), 0.046),
        J("Beak", "Head", (0.0, 0.20, 0.48), 0.016, connected=True),
        J("Crest", "Head", (0.0, 0.11, 0.57), 0.018),
        J("Tail", "Hips", (0.0, -0.14, 0.25), (0.055, 0.016)),
        J("Breast", "Chest", (0.0, 0.08, 0.26), 0.065, volume=True),
    ]
    joints += chain("Hips", [
        ("LeftUpperLeg", (-0.035, 0.02, 0.15), 0.022),
        ("LeftLowerLeg", (-0.035, 0.03, 0.08), 0.014),
        ("LeftFoot", (-0.035, 0.055, 0.012), 0.018),
    ])
    joints += chain("Hips", [
        ("RightUpperLeg", (0.035, 0.02, 0.15), 0.022),
        ("RightLowerLeg", (0.035, 0.03, 0.08), 0.014),
        ("RightFoot", (0.035, 0.055, 0.012), 0.018),
    ])
    joints += chain("Chest", [
        ("LeftWingUpper", (-0.10, 0.04, 0.34), (0.055, 0.012)),
        ("LeftWingMid", (-0.18, 0.00, 0.32), (0.048, 0.010)),
        ("LeftWingTip", (-0.26, -0.06, 0.30), (0.028, 0.008)),
    ])
    joints += chain("Chest", [
        ("RightWingUpper", (0.10, 0.04, 0.34), (0.055, 0.012)),
        ("RightWingMid", (0.18, 0.00, 0.32), (0.048, 0.010)),
        ("RightWingTip", (0.26, -0.06, 0.30), (0.028, 0.008)),
    ])

    def region_of(centre, height):
        x, y, z = shares(centre, height)
        if z > 0.92:
            return 4
        if y > 0.28 and z > 0.78:
            return 3
        if y > 0.08 and z < 0.55:
            return 1
        if abs(x) > 0.16:
            return 2
        if y < -0.18:
            return 5
        return 0

    def animations(anim):
        rot = anim.rot

        def wings(pose, flap, fold=0.0):
            for side, sign in (("Left", -1.0), ("Right", 1.0)):
                pose[side + "WingUpper"] = rot(
                    ("Y", sign * (8.0 + 28.0 * flap)), ("X", -10.0 * fold))
                pose[side + "WingMid"] = rot(("Y", sign * 16.0 * flap))
                pose[side + "WingTip"] = rot(("Y", sign * 10.0 * flap))

        def idle_pose(t):
            breath = math.sin(t * TAU)
            pose = {
                "Hips": {"loc": (0.0, 0.0, 0.004 * breath)},
                "Chest": rot(("X", 1.4 * breath)),
                "Neck": rot(("X", 2.0 * breath), ("Z", 3.0 * math.sin(t * TAU * 0.5))),
                "Head": rot(("Z", 4.0 * math.sin(t * TAU * 0.5))),
                "Crest": rot(("X", 6.0 * breath)),
                "Tail": rot(("Z", 8.0 * math.sin(t * TAU))),
            }
            wings(pose, 0.12 * breath, 0.15)
            for side in ("Left", "Right"):
                pose[side + "UpperLeg"] = rot(("X", 2.0 * breath))
            return pose

        def walk_pose(t):
            phase = t * TAU
            pose = {
                "Hips": {"rot": [("Z", 4.0 * math.sin(phase))],
                         "loc": (0.0, 0.0,
                                 0.018 * abs(math.sin(phase)) - 0.004)},
                "Chest": rot(("X", 3.0 * math.sin(phase * 2.0))),
                "Neck": rot(("X", 6.0 + 4.0 * math.sin(phase * 2.0))),
                "Head": rot(("X", -4.0 * math.sin(phase * 2.0))),
                "Tail": rot(("Z", 10.0 * math.sin(phase))),
            }
            for side, sign, offset in (("Left", -1.0, 0.0), ("Right", 1.0, math.pi)):
                leg = phase + offset
                pose[side + "UpperLeg"] = rot(("X", 28.0 * math.sin(leg)))
                pose[side + "LowerLeg"] = rot(("X", -36.0 * max(0.0, -math.cos(leg))))
                pose[side + "Foot"] = rot(("X", 12.0 * math.sin(leg)))
            wings(pose, 0.22 * math.sin(phase * 2.0), 0.10)
            return pose

        def run_pose(t):
            phase = t * TAU
            pose = walk_pose(t)
            pose["Hips"]["loc"] = (0.0, 0.0, 0.03 * abs(math.sin(phase)))
            wings(pose, 0.55 * math.sin(phase * 2.0), 0.0)
            return pose

        def attack_pose(t):
            peck = pulse(t, 0.22, 0.48, 0.78)
            wind = pulse(t, 0.0, 0.20, 0.38)
            pose = {
                "Hips": {"rot": [("X", 6.0 * wind)],
                         "loc": (0.0, 0.02 * peck, 0.0)},
                "Chest": rot(("X", 8.0 * wind - 6.0 * peck)),
                "Neck": rot(("X", 18.0 * wind - 52.0 * peck)),
                "Head": rot(("X", 10.0 * wind + 16.0 * peck)),
                "Beak": rot(("X", 8.0 * peck)),
            }
            wings(pose, 0.15 + 0.25 * wind, 0.2)
            return pose

        def hit_pose(t):
            hit = math.sin(math.pi * min(t, 1.0))
            pose = {
                "Hips": {"rot": [("Z", -8.0 * hit)],
                         "loc": (0.0, -0.015 * hit, -0.01 * hit)},
                "Neck": rot(("X", 16.0 * hit)),
                "Head": rot(("X", -14.0 * hit)),
            }
            wings(pose, 0.45 * hit, 0.0)
            return pose

        def defeat_pose(t):
            fall = ease(t)
            pose = {
                "Hips": {"rot": [("Z", 20.0 * fall)],
                         "loc": (0.0, 0.0, -0.10 * fall)},
                "Neck": rot(("X", -24.0 * fall)),
                "Head": rot(("X", -18.0 * fall)),
            }
            wings(pose, -0.2 * fall, 0.6)
            return pose

        return core_table(
            idle_pose, walk_pose, run_pose, attack_pose, hit_pose, defeat_pose)

    return CreatureSpec(
        "glimmer_crest_bird", "Glimmer-Crest Bird", "bird", 20268203, h, palette,
        (2800, 6000),
        {"shape": "capsule", "radius": 0.16, "height": 0.48,
         "centre": [0.0, 0.24, 0.0]},
        "Violet body streaks, gold breast blaze, teal wing bands, cream face, "
        "magenta crest discs, and lime tail chevrons",
        "crest and wing-edge glow after sunset",
        1.60, joints,
        (("LeftUpperLeg", "LeftLowerLeg", "LeftFoot"),
         ("RightUpperLeg", "RightLowerLeg", "RightFoot"),
         ("LeftWingUpper", "LeftWingMid", "LeftWingTip"),
         ("RightWingUpper", "RightWingMid", "RightWingTip")),
        REQUIRED_CORE_CLIPS, region_of,
        painter(palette, 20268203,
                ("streaks", "blaze", "bands", "blaze", "spots", "chevrons")),
        animations, roughness=0.52)


def cow() -> CreatureSpec:
    h = 1.42
    palette = rgba("F0E2C4", "C7A8E8", "3A3F8C", "E0C36A", "4EE0C8", "F2A0C4")
    joints = [
        J("Root", None, (0.0, -0.06, 0.02), 0.04, deform=False),
        J("Hips", "Root", (0.0, -0.32, 0.78), 0.18),
        J("Spine", "Hips", (0.0, -0.08, 0.82), 0.20, connected=True),
        J("Chest", "Spine", (0.0, 0.22, 0.86), 0.19, connected=True),
        J("Withers", "Chest", (0.0, 0.28, 0.96), 0.12, volume=True),
        J("Neck", "Chest", (0.0, 0.38, 1.08), 0.11),
        J("Head", "Neck", (0.0, 0.58, 1.22), 0.11, connected=True),
        J("Muzzle", "Head", (0.0, 0.74, 1.12), 0.06, connected=True),
        J("Jaw", "Head", (0.0, 0.68, 1.08), 0.04),
        J("LeftHorn", "Head", (-0.08, 0.52, 1.36), 0.022),
        J("RightHorn", "Head", (0.08, 0.52, 1.36), 0.022),
        J("LeftEar", "Head", (-0.12, 0.50, 1.24), 0.03, volume=True),
        J("RightEar", "Head", (0.12, 0.50, 1.24), 0.03, volume=True),
        J("Dewlap", "Neck", (0.0, 0.42, 0.92), 0.07, volume=True),
        J("Barrel", "Spine", (0.0, 0.04, 0.70), 0.16, volume=True),
        J("Udder", "Hips", (0.0, -0.22, 0.42), 0.08, volume=True),
        J("Tail", "Hips", (0.0, -0.58, 0.80), 0.03),
        J("TailEnd", "Tail", (0.0, -0.72, 0.62), 0.04, connected=True),
    ]
    joints += quad_leg("Left", "Front", "Chest",
                       (-0.16, 0.28, 0.72), (-0.17, 0.30, 0.38),
                       (-0.17, 0.34, 0.04), (0.055, 0.038, 0.034))
    joints += quad_leg("Right", "Front", "Chest",
                       (0.16, 0.28, 0.72), (0.17, 0.30, 0.38),
                       (0.17, 0.34, 0.04), (0.055, 0.038, 0.034))
    joints += quad_leg("Left", "Hind", "Hips",
                       (-0.16, -0.34, 0.72), (-0.17, -0.38, 0.38),
                       (-0.17, -0.34, 0.04), (0.060, 0.040, 0.036))
    joints += quad_leg("Right", "Hind", "Hips",
                       (0.16, -0.34, 0.72), (0.17, -0.38, 0.38),
                       (0.17, -0.34, 0.04), (0.060, 0.040, 0.036))

    def region_of(centre, height):
        x, y, z = shares(centre, height)
        if z < 0.14 and abs(x) > 0.06:
            return 2
        if y < -0.42:
            return 5
        if z > 0.88 and y > 0.28:
            return 3
        if abs(x) > 0.14 and 0.35 < z < 0.70 and -0.20 < y < 0.28:
            return 1
        if z < 0.38 and abs(y + 0.12) < 0.12:
            return 4
        return 0

    clips = ("Idle", "Walk", "Run", "Graze", "Attack", "HitReact", "Defeat")

    def animations(anim):
        return quadruped_animations(anim, quad_limb_groups(), attack="headbutt",
                                    graze=True)

    return CreatureSpec(
        "lumen_hide_cow", "Lumen-Hide Cow", "cow", 20268204, h, palette,
        (4000, 7800),
        {"shape": "capsule", "radius": 0.38, "height": 1.16,
         "centre": [0.0, 0.58, 0.0]},
        "Cream hide streaks, lilac flank patches, indigo hooves, gold horn "
        "rings, teal udder glow, and a magenta tail switch",
        "udder and horn-ring glow after sunset",
        1.35, joints, quad_limb_groups(), clips, region_of,
        painter(palette, 20268204,
                ("streaks", "spots", "rings", "bands", "spots", "chevrons")),
        animations, roughness=0.64)


def monster() -> CreatureSpec:
    h = 2.10
    palette = rgba("2A2A32", "E06A2A", "E8D2B0", "6FE05A", "C42828", "E8C04A")
    joints = [
        J("Root", None, (0.0, 0.0, 0.02), 0.05, deform=False),
        J("Hips", "Root", (0.0, -0.06, 0.92), 0.18),
        J("Spine", "Hips", (0.0, 0.10, 1.18), 0.17, connected=True),
        J("Chest", "Spine", (0.0, 0.22, 1.48), 0.20, connected=True),
        J("Gut", "Spine", (0.0, 0.12, 1.08), 0.14, volume=True),
        J("Neck", "Chest", (0.0, 0.34, 1.72), 0.11),
        J("Head", "Neck", (0.0, 0.50, 1.86), 0.13, connected=True),
        J("Jaw", "Head", (0.0, 0.58, 1.70), 0.08, connected=True),
        J("Brow", "Head", (0.0, 0.48, 1.98), 0.06, volume=True),
        J("Hump", "Spine", (0.0, 0.02, 1.36), 0.12, volume=True),
        J("LeftSpine", "Chest", (-0.08, 0.10, 1.66), 0.03),
        J("RightSpine", "Chest", (0.08, 0.10, 1.66), 0.03),
    ]
    joints += chain("Hips", [
        ("LeftUpperLeg", (-0.16, -0.02, 0.70), 0.09),
        ("LeftLowerLeg", (-0.16, 0.04, 0.36), 0.065),
        ("LeftFoot", (-0.16, 0.12, 0.05), 0.055),
    ])
    joints += chain("Hips", [
        ("RightUpperLeg", (0.16, -0.02, 0.70), 0.09),
        ("RightLowerLeg", (0.16, 0.04, 0.36), 0.065),
        ("RightFoot", (0.16, 0.12, 0.05), 0.055),
    ])
    joints += chain("Chest", [
        ("LeftUpperArm", (-0.28, 0.16, 1.40), 0.08),
        ("LeftLowerArm", (-0.32, 0.22, 0.88), 0.06),
        ("LeftHand", (-0.30, 0.28, 0.42), 0.07),
    ])
    joints += chain("Chest", [
        ("RightUpperArm", (0.28, 0.16, 1.40), 0.08),
        ("RightLowerArm", (0.32, 0.22, 0.88), 0.06),
        ("RightHand", (0.30, 0.28, 0.42), 0.07),
    ])

    def region_of(centre, height):
        x, y, z = shares(centre, height)
        if y > 0.22 and z > 0.78:
            return 4 if z < 0.88 else 2
        if z > 0.78 and abs(x) < 0.08:
            return 3
        if z < 0.18:
            return 5
        if abs(x) > 0.14 and 0.45 < z < 0.78:
            return 1
        return 0

    return CreatureSpec(
        "rift_hulk_monster", "Rift-Hulk Monster", "monster", 20268205, h, palette,
        (4800, 8600),
        {"shape": "capsule", "radius": 0.42, "height": 1.70,
         "centre": [0.0, 0.85, 0.0]},
        "Charcoal hide streaks, ember flank bands, bone-cream muzzle, toxic "
        "green back spines, red maw, and gold knuckle plates",
        "spine tips and maw glow after sunset",
        1.70, joints,
        (("LeftUpperLeg", "LeftLowerLeg", "LeftFoot"),
         ("RightUpperLeg", "RightLowerLeg", "RightFoot"),
         ("LeftUpperArm", "LeftLowerArm", "LeftHand"),
         ("RightUpperArm", "RightLowerArm", "RightHand")),
        REQUIRED_CORE_CLIPS, region_of,
        painter(palette, 20268205,
                ("streaks", "bands", "blaze", "chevrons", "spots", "rings")),
        lambda anim: biped_animations(anim, monster=True),
        roughness=0.70)


def alien_one() -> CreatureSpec:
    h = 1.76
    palette = rgba("7A4CB8", "D8C4F2", "3AD0D6", "E8C85A", "3A2A78", "F090C8")
    joints = [
        J("Root", None, (0.0, 0.0, 0.02), 0.03, deform=False),
        J("Hips", "Root", (0.0, -0.02, 0.92), 0.11),
        J("Spine", "Hips", (0.0, 0.00, 1.16), 0.10, connected=True),
        J("Chest", "Spine", (0.0, 0.02, 1.38), 0.11, connected=True),
        J("Waist", "Hips", (0.0, 0.00, 1.04), 0.09, volume=True),
        J("Neck", "Chest", (0.0, 0.02, 1.52), 0.055),
        J("Head", "Neck", (0.0, 0.04, 1.68), 0.12, connected=True),
        J("Cranium", "Head", (0.0, 0.00, 1.78), 0.08, volume=True),
        J("Jaw", "Head", (0.0, 0.08, 1.58), 0.04),
    ]
    joints += chain("Hips", [
        ("LeftUpperLeg", (-0.10, 0.00, 0.68), 0.045),
        ("LeftLowerLeg", (-0.10, 0.02, 0.34), 0.032),
        ("LeftFoot", (-0.10, 0.08, 0.04), 0.036),
    ])
    joints += chain("Hips", [
        ("RightUpperLeg", (0.10, 0.00, 0.68), 0.045),
        ("RightLowerLeg", (0.10, 0.02, 0.34), 0.032),
        ("RightFoot", (0.10, 0.08, 0.04), 0.036),
    ])
    joints += chain("Chest", [
        ("LeftUpperArm", (-0.16, 0.02, 1.34), 0.032),
        ("LeftLowerArm", (-0.18, 0.04, 1.08), 0.026),
        ("LeftHand", (-0.18, 0.06, 0.86), 0.028),
    ])
    joints += chain("Chest", [
        ("RightUpperArm", (0.16, 0.02, 1.34), 0.032),
        ("RightLowerArm", (0.18, 0.04, 1.08), 0.026),
        ("RightHand", (0.18, 0.06, 0.86), 0.028),
    ])

    def region_of(centre, height):
        x, y, z = shares(centre, height)
        if z > 0.90:
            return 2
        if z > 0.82 and y > 0.00:
            return 5
        if z < 0.12:
            return 3
        if abs(x) > 0.10 and 0.55 < z < 0.82:
            return 4
        if y > 0.02 and 0.45 < z < 0.75:
            return 1
        return 0

    return CreatureSpec(
        "violet_seeker_alien", "Violet Seeker", "alien", 20268206, h, palette,
        (4000, 7600),
        {"shape": "capsule", "radius": 0.22, "height": 1.46,
         "centre": [0.0, 0.73, 0.0]},
        "Violet skin streaks, lavender belly blaze, teal eye discs, gold "
        "knuckle marks, indigo limb bands, and pink cranial membranes",
        "eye discs and cranial membrane glow after sunset",
        1.80, joints,
        (("LeftUpperLeg", "LeftLowerLeg", "LeftFoot"),
         ("RightUpperLeg", "RightLowerLeg", "RightFoot"),
         ("LeftUpperArm", "LeftLowerArm", "LeftHand"),
         ("RightUpperArm", "RightLowerArm", "RightHand")),
        REQUIRED_CORE_CLIPS, region_of,
        painter(palette, 20268206,
                ("streaks", "blaze", "spots", "bands", "rings", "spots")),
        lambda anim: biped_animations(anim),
        roughness=0.42)


def alien_two() -> CreatureSpec:
    h = 1.52
    palette = rgba("D48A2A", "8C3A1C", "F0D8B0", "3AD6C8", "2A1A14", "E8B84A")
    joints = [
        J("Root", None, (0.0, 0.0, 0.02), 0.03, deform=False),
        J("Hips", "Root", (0.0, -0.02, 0.78), 0.12),
        J("Spine", "Hips", (0.0, 0.02, 0.98), 0.12, connected=True),
        J("Chest", "Spine", (0.0, 0.04, 1.16), 0.14, connected=True),
        J("Neck", "Chest", (0.0, 0.06, 1.28), 0.05),
        J("Head", "Neck", (0.0, 0.10, 1.38), 0.08, connected=True),
        J("Crest", "Head", (0.0, 0.04, 1.50), (0.02, 0.05)),
        J("Mandible", "Head", (0.0, 0.16, 1.30), 0.03),
        J("Plate", "Chest", (0.0, 0.00, 1.10), 0.10, volume=True),
    ]
    joints += chain("Hips", [
        ("LeftUpperLeg", (-0.12, 0.00, 0.56), 0.055),
        ("LeftLowerLeg", (-0.12, -0.04, 0.28), 0.038),
        ("LeftFoot", (-0.12, 0.06, 0.04), 0.040),
    ])
    joints += chain("Hips", [
        ("RightUpperLeg", (0.12, 0.00, 0.56), 0.055),
        ("RightLowerLeg", (0.12, -0.04, 0.28), 0.038),
        ("RightFoot", (0.12, 0.06, 0.04), 0.040),
    ])
    joints += chain("Chest", [
        ("LeftUpperArm", (-0.18, 0.04, 1.14), 0.04),
        ("LeftLowerArm", (-0.22, 0.08, 0.92), 0.032),
        ("LeftHand", (-0.22, 0.12, 0.72), 0.034),
    ])
    joints += chain("Chest", [
        ("RightUpperArm", (0.18, 0.04, 1.14), 0.04),
        ("RightLowerArm", (0.22, 0.08, 0.92), 0.032),
        ("RightHand", (0.22, 0.12, 0.72), 0.034),
    ])
    joints += chain("Spine", [
        ("LeftUpperArmB", (-0.16, 0.02, 0.96), 0.036),
        ("LeftLowerArmB", (-0.20, 0.06, 0.76), 0.028),
        ("LeftHandB", (-0.20, 0.10, 0.58), 0.030),
    ])
    joints += chain("Spine", [
        ("RightUpperArmB", (0.16, 0.02, 0.96), 0.036),
        ("RightLowerArmB", (0.20, 0.06, 0.76), 0.028),
        ("RightHandB", (0.20, 0.10, 0.58), 0.030),
    ])

    def region_of(centre, height):
        x, y, z = shares(centre, height)
        if z > 0.92:
            return 5
        if z > 0.82:
            return 2
        if z < 0.14:
            return 4
        if abs(x) > 0.12 and 0.50 < z < 0.82:
            return 1
        if 0.40 < z < 0.55:
            return 3
        return 0

    return CreatureSpec(
        "amber_stalker_alien", "Amber Stalker", "alien", 20268207, h, palette,
        (4200, 8000),
        {"shape": "capsule", "radius": 0.28, "height": 1.24,
         "centre": [0.0, 0.62, 0.0]},
        "Amber carapace bands, rust shoulder plates, cream joints, teal glow "
        "seams, dark claws, and a gold cranial crest",
        "crest and thoracic glow seams after sunset",
        1.65, joints,
        (("LeftUpperLeg", "LeftLowerLeg", "LeftFoot"),
         ("RightUpperLeg", "RightLowerLeg", "RightFoot"),
         ("LeftUpperArm", "LeftLowerArm", "LeftHand"),
         ("RightUpperArm", "RightLowerArm", "RightHand"),
         ("LeftUpperArmB", "LeftLowerArmB", "LeftHandB"),
         ("RightUpperArmB", "RightLowerArmB", "RightHandB")),
        REQUIRED_CORE_CLIPS, region_of,
        painter(palette, 20268207,
                ("bands", "streaks", "blaze", "spots", "rings", "chevrons")),
        lambda anim: biped_animations(anim, four_arms=True),
        roughness=0.50)


def octopus() -> CreatureSpec:
    h = 0.50
    palette = rgba("2EB8B0", "7A48C4", "E8C85A", "F3E6D0", "E85CA8", "B6F25A")
    joints = [
        J("Root", None, (0.0, 0.0, 0.02), 0.02, deform=False),
        J("Hips", "Root", (0.0, 0.0, 0.22), 0.10),
        J("Head", "Hips", (0.0, 0.04, 0.34), 0.11),
        J("Mantle", "Head", (0.0, -0.02, 0.44), 0.10),
        J("Siphon", "Head", (0.0, 0.10, 0.28), 0.03),
        J("LeftEye", "Head", (-0.06, 0.08, 0.36), 0.02),
        J("RightEye", "Head", (0.06, 0.08, 0.36), 0.02),
    ]
    limbs = []
    for index in range(8):
        angle = TAU * index / 8.0 + 0.4
        sign_x = math.sin(angle)
        sign_y = math.cos(angle)
        a = "Arm{0}A".format(index + 1)
        b = "Arm{0}B".format(index + 1)
        c = "Arm{0}C".format(index + 1)
        joints += chain("Hips", [
            (a, (0.10 * sign_x, 0.10 * sign_y, 0.14), 0.032),
            (b, (0.18 * sign_x, 0.18 * sign_y, 0.08), 0.024),
            (c, (0.26 * sign_x, 0.26 * sign_y, 0.016), 0.016),
        ])
        limbs.append((a, b, c))

    def region_of(centre, height):
        x, y, z = shares(centre, height)
        if z > 0.78:
            return 0
        if z > 0.62 and abs(x) > 0.08:
            return 5
        if z < 0.18:
            return 2
        if math.hypot(x, y) > 0.28:
            return 4
        if z < 0.40:
            return 3
        return 1

    def animations(anim):
        rot = anim.rot

        def wave_arms(pose, phase, amount, reach=0.0):
            for index in range(8):
                offset = TAU * index / 8.0
                wave = phase + offset
                prefix = "Arm{0}".format(index + 1)
                pose[prefix + "A"] = rot(
                    ("X", amount * math.sin(wave) + 8.0 * reach),
                    ("Y", 10.0 * math.cos(wave)))
                pose[prefix + "B"] = rot(("X", amount * 1.2 * math.sin(wave + 0.6)))
                pose[prefix + "C"] = rot(("X", amount * 0.8 * math.sin(wave + 1.1)))

        def idle_pose(t):
            pose = {
                "Head": rot(("Z", 3.0 * math.sin(t * TAU * 0.5))),
                "Mantle": rot(("X", 2.0 * math.sin(t * TAU))),
                "LeftEye": rot(("X", 4.0 * math.sin(t * TAU))),
                "RightEye": rot(("X", -3.0 * math.sin(t * TAU))),
            }
            wave_arms(pose, t * TAU, 8.0)
            return pose

        def walk_pose(t):
            pose = {
                "Hips": {"rot": [("Z", 4.0 * math.sin(t * TAU))],
                         "loc": (0.0, 0.0, 0.008 * math.sin(t * TAU * 2.0))},
                "Head": rot(("X", 3.0 * math.sin(t * TAU * 2.0))),
            }
            wave_arms(pose, t * TAU, 22.0)
            return pose

        def run_pose(t):
            pose = {
                "Hips": {"loc": (0.0, 0.0, 0.016 * math.sin(t * TAU * 2.0))},
                "Mantle": rot(("X", -6.0)),
            }
            wave_arms(pose, t * TAU, 32.0, reach=0.2)
            return pose

        def attack_pose(t):
            lash = pulse(t, 0.20, 0.48, 0.80)
            pose = {
                "Hips": {"loc": (0.0, 0.03 * lash, 0.0)},
                "Head": rot(("X", -8.0 * lash)),
            }
            wave_arms(pose, 0.0, 8.0, reach=lash)
            for index in (1, 2, 8):
                prefix = "Arm{0}".format(index)
                pose[prefix + "A"] = rot(("X", -10.0 + 40.0 * lash))
                pose[prefix + "B"] = rot(("X", 20.0 * lash))
            return pose

        def hit_pose(t):
            hit = math.sin(math.pi * min(t, 1.0))
            pose = {
                "Hips": {"rot": [("Z", -10.0 * hit)],
                         "loc": (0.0, -0.02 * hit, -0.01 * hit)},
                "Mantle": rot(("X", 8.0 * hit)),
            }
            wave_arms(pose, math.pi, 16.0 * hit)
            return pose

        def defeat_pose(t):
            fall = ease(t)
            pose = {
                "Hips": {"rot": [("X", -16.0 * fall)],
                         "loc": (0.0, 0.0, -0.08 * fall)},
                "Mantle": rot(("X", -12.0 * fall)),
                "Head": rot(("X", -10.0 * fall)),
            }
            wave_arms(pose, 1.2, 6.0, reach=-0.4 * fall)
            return pose

        return core_table(
            idle_pose, walk_pose, run_pose, attack_pose, hit_pose, defeat_pose)

    return CreatureSpec(
        "glass_coil_octopus", "Glass-Coil Octopus", "octopus", 20268208, h, palette,
        (3000, 6400),
        {"shape": "capsule", "radius": 0.22, "height": 0.42,
         "centre": [0.0, 0.21, 0.0]},
        "Teal mantle bands, violet arm streaks, gold sucker rings, cream "
        "underside, magenta arm-tip spots, and lime eye discs",
        "eye discs and sucker-ring glow after sunset",
        1.50, joints, limbs, REQUIRED_CORE_CLIPS, region_of,
        painter(palette, 20268208,
                ("bands", "streaks", "rings", "blaze", "spots", "spots")),
        animations, roughness=0.28)


def spider() -> CreatureSpec:
    h = 0.38
    palette = rgba("2A1638", "E8B84A", "2EB8B0", "F3E6D0", "E85CA8", "B6F25A")
    joints = [
        J("Root", None, (0.0, 0.0, 0.01), 0.014, deform=False),
        J("Hips", "Root", (0.0, 0.0, 0.14), 0.055),
        J("Cephalothorax", "Hips", (0.0, 0.04, 0.16), 0.06),
        J("Abdomen", "Hips", (0.0, -0.12, 0.18), 0.09),
        J("Head", "Cephalothorax", (0.0, 0.10, 0.16), 0.032),
        J("LeftFang", "Head", (-0.025, 0.13, 0.13), 0.018),
        J("RightFang", "Head", (0.025, 0.13, 0.13), 0.018),
        J("Orb", "Abdomen", (0.0, -0.16, 0.22), 0.04, volume=True),
    ]
    limbs = [
        ("LeftFang",),
        ("RightFang",),
    ]
    stations = (
        (1, -0.70, 0.18),
        (2, -0.28, 0.16),
        (3, 0.22, 0.16),
        (4, 0.68, 0.14),
    )
    for index, yaw, reach in stations:
        for side, sign in (("Left", -1.0), ("Right", 1.0)):
            prefix = "{0}{1}".format(side, index)
            hip = (0.05 * sign, 0.03 * math.sin(yaw), 0.14)
            mid = (0.12 * sign * reach, 0.10 * math.sin(yaw), 0.10)
            foot = (0.18 * sign * reach, 0.16 * math.sin(yaw), 0.012)
            joints += chain("Cephalothorax", [
                (prefix + "Upper", hip, 0.016),
                (prefix + "Mid", mid, 0.013),
                (prefix + "Lower", foot, 0.014),
            ])
            limbs.append((prefix + "Upper", prefix + "Mid", prefix + "Lower"))

    def region_of(centre, height):
        x, y, z = shares(centre, height)
        if y < -0.20 and z > 0.40:
            return 1
        if y < -0.28:
            return 4
        if y > 0.22 and z < 0.40:
            return 3
        if z < 0.18 and abs(x) > 0.12:
            return 2
        if z > 0.48 and y > 0.10:
            return 5
        return 0

    def animations(anim):
        rot = anim.rot
        # Alternating tetrapod: 1+3 vs 2+4 on each side, offset across the body.
        groups = (
            (("Left1", "Right2", "Left3", "Right4"), 0.0),
            (("Right1", "Left2", "Right3", "Left4"), 0.5),
        )

        def cycle(pose, phase, swing, fold):
            for prefixes, offset in groups:
                wave = phase + offset * TAU
                for prefix in prefixes:
                    sign = -1.0 if prefix.startswith("Left") else 1.0
                    pose[prefix + "Upper"] = rot(
                        ("Y", sign * swing * math.sin(wave)),
                        ("X", 10.0 * math.sin(wave)))
                    pose[prefix + "Mid"] = rot(
                        ("X", fold * max(0.0, -math.cos(wave))))
                    pose[prefix + "Lower"] = rot(
                        ("X", -0.45 * fold * max(0.0, -math.cos(wave))))

        def idle_pose(t):
            breath = math.sin(t * TAU)
            pose = {
                "Hips": {"loc": (0.0, 0.0, 0.003 * breath)},
                "Abdomen": rot(("X", 2.0 * breath)),
                "Head": rot(("Z", 3.0 * math.sin(t * TAU * 0.5))),
                "LeftFang": rot(("X", 4.0 * breath)),
                "RightFang": rot(("X", -4.0 * breath)),
            }
            cycle(pose, 0.0, 0.0, 0.0)
            return pose

        def walk_pose(t):
            phase = t * TAU
            pose = {
                "Hips": {"rot": [("Z", 3.0 * math.sin(phase))],
                         "loc": (0.0, 0.0,
                                 -0.006 * (1.0 - math.cos(phase * 2.0)) * 0.5)},
                "Abdomen": rot(("Z", -2.0 * math.sin(phase))),
                "Head": rot(("X", 2.0 * math.sin(phase * 2.0))),
            }
            cycle(pose, phase, 14.0, 16.0)
            return pose

        def run_pose(t):
            phase = t * TAU
            pose = {
                "Hips": {"loc": (0.0, 0.0, 0.01 * abs(math.sin(phase)))},
                "Abdomen": rot(("X", -6.0)),
            }
            cycle(pose, phase, 18.0, 20.0)
            return pose

        def attack_pose(t):
            lunge = pulse(t, 0.18, 0.44, 0.76)
            wind = pulse(t, 0.0, 0.20, 0.36)
            pose = {
                "Hips": {"rot": [("X", 8.0 * wind - 6.0 * lunge)],
                         "loc": (0.0, 0.03 * lunge, 0.01 * wind)},
                "Head": rot(("X", -12.0 * lunge)),
                "LeftFang": rot(("X", 18.0 * wind - 28.0 * lunge)),
                "RightFang": rot(("X", 18.0 * wind - 28.0 * lunge)),
                "Abdomen": rot(("X", 8.0 * wind)),
            }
            cycle(pose, 0.0, 4.0, 10.0 * wind)
            return pose

        def hit_pose(t):
            hit = math.sin(math.pi * min(t, 1.0))
            pose = {
                "Hips": {"rot": [("Z", -10.0 * hit)],
                         "loc": (0.0, -0.012 * hit, -0.01 * hit)},
                "Abdomen": rot(("X", -10.0 * hit)),
            }
            cycle(pose, math.pi, 8.0 * hit, 8.0 * hit)
            return pose

        def defeat_pose(t):
            fall = ease(t)
            pose = {
                "Hips": {"rot": [("Z", 18.0 * fall)],
                         "loc": (0.0, 0.0, -0.05 * fall)},
                "Abdomen": rot(("X", 16.0 * fall)),
                "LeftFang": rot(("X", 20.0 * fall)),
                "RightFang": rot(("X", 20.0 * fall)),
            }
            cycle(pose, 0.8, 6.0, 20.0 * fall)
            return pose

        return core_table(
            idle_pose, walk_pose, run_pose, attack_pose, hit_pose, defeat_pose)

    return CreatureSpec(
        "lantern_orb_spider", "Lantern-Orb Spider", "spider", 20268209, h, palette,
        (2600, 5800),
        {"shape": "capsule", "radius": 0.18, "height": 0.30,
         "centre": [0.0, 0.15, 0.0]},
        "Violet-black body streaks, gold abdomen orb, teal limb rings, cream "
        "fangs, magenta hourglass, and lime eye discs",
        "abdomen orb and fang glow after sunset",
        1.55, joints, limbs, REQUIRED_CORE_CLIPS, region_of,
        painter(palette, 20268209,
                ("streaks", "spots", "rings", "blaze", "chevrons", "spots")),
        animations, roughness=0.46)


def dog() -> CreatureSpec:
    h = 0.80
    palette = rgba("E0B46A", "F4EDE0", "3A3A78", "E8C04A", "3AD0D6", "F2A0C4")
    joints = [
        J("Root", None, (0.0, -0.04, 0.02), 0.025, deform=False),
        J("Hips", "Root", (0.0, -0.16, 0.40), 0.09),
        J("Spine", "Hips", (0.0, 0.02, 0.43), 0.10, connected=True),
        J("Chest", "Spine", (0.0, 0.16, 0.44), 0.10, connected=True),
        J("Neck", "Chest", (0.0, 0.24, 0.54), 0.05),
        J("Head", "Neck", (0.0, 0.34, 0.62), 0.07, connected=True),
        J("Muzzle", "Head", (0.0, 0.46, 0.56), 0.032, connected=True),
        J("Jaw", "Head", (0.0, 0.42, 0.52), 0.028),
        J("LeftEar", "Head", (-0.05, 0.30, 0.70), 0.018),
        J("RightEar", "Head", (0.05, 0.30, 0.70), 0.018),
        J("Mane", "Neck", (0.0, 0.18, 0.58), 0.06, volume=True),
        J("ChestVol", "Chest", (0.0, 0.18, 0.36), 0.08, volume=True),
        J("Tail", "Hips", (0.0, -0.30, 0.44), 0.022),
        J("TailEnd", "Tail", (0.0, -0.40, 0.50), 0.016, connected=True),
    ]
    joints += quad_leg("Left", "Front", "Chest",
                       (-0.08, 0.18, 0.36), (-0.08, 0.20, 0.18),
                       (-0.08, 0.22, 0.03), (0.032, 0.024, 0.022))
    joints += quad_leg("Right", "Front", "Chest",
                       (0.08, 0.18, 0.36), (0.08, 0.20, 0.18),
                       (0.08, 0.22, 0.03), (0.032, 0.024, 0.022))
    joints += quad_leg("Left", "Hind", "Hips",
                       (-0.08, -0.16, 0.36), (-0.08, -0.20, 0.18),
                       (-0.08, -0.16, 0.03), (0.034, 0.025, 0.022))
    joints += quad_leg("Right", "Hind", "Hips",
                       (0.08, -0.16, 0.36), (0.08, -0.20, 0.18),
                       (0.08, -0.16, 0.03), (0.034, 0.025, 0.022))

    def region_of(centre, height):
        x, y, z = shares(centre, height)
        if z < 0.16 and abs(x) > 0.05:
            return 2
        if y < -0.42:
            return 5
        if y > 0.38 and z > 0.62:
            return 1
        if z > 0.78 and abs(x) > 0.04:
            return 2
        if abs(x) < 0.06 and 0.40 < z < 0.70 and -0.05 < y < 0.30:
            return 1
        if abs(x) > 0.10 and 0.40 < z < 0.62:
            return 3
        return 0

    def animations(anim):
        return quadruped_animations(anim, quad_limb_groups(), attack="bite")

    return CreatureSpec(
        "star_mane_hound", "Star-Mane Hound", "dog", 20268210, h, palette,
        (3600, 7200),
        {"shape": "capsule", "radius": 0.22, "height": 0.66,
         "centre": [0.0, 0.33, 0.0]},
        "Warm sand coat streaks, cream chest blaze, indigo ears and socks, "
        "gold mane marks, teal eye rings, and a pink tail tip",
        "mane marks and eye rings glow after sunset",
        1.40, joints, quad_limb_groups(), REQUIRED_CORE_CLIPS, region_of,
        painter(palette, 20268210,
                ("streaks", "blaze", "rings", "bands", "spots", "chevrons")),
        animations, roughness=0.60)


from build_crawler_creatures import knell_bell, rift_oculus

CREATURES = (
    crab(),
    dolphin(),
    bird(),
    cow(),
    monster(),
    alien_one(),
    alien_two(),
    octopus(),
    spider(),
    dog(),
    knell_bell(),
    rift_oculus(),
)
CREATURE_BY_NAME = {spec.name: spec for spec in CREATURES}


def arguments() -> argparse.Namespace:
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument(
        "--only", nargs="+", metavar="NAME",
        help="build only named recipes; comma-separated names are accepted")
    parser.add_argument(
        "--skip-previews", action="store_true",
        help="skip close/gameplay/pose renders while iterating")
    blender_arguments = (
        sys.argv[sys.argv.index("--") + 1:] if "--" in sys.argv else [])
    return parser.parse_args(blender_arguments)


def selected(only) -> list[CreatureSpec]:
    if not only:
        return list(CREATURES)
    requested: list[str] = []
    for value in only:
        requested.extend(
            name.strip() for name in value.split(",") if name.strip())
    unknown = sorted(set(requested) - set(CREATURE_BY_NAME))
    if unknown:
        raise SystemExit("unknown creature(s): " + ", ".join(unknown))
    wanted = set(requested)
    return [spec for spec in CREATURES if spec.name in wanted]


def main() -> None:
    options = arguments()
    specs = selected(options.only)
    failures: list[str] = []
    for spec in specs:
        try:
            build_creature(spec, skip_previews=options.skip_previews)
        except (SystemExit, Exception) as error:
            failures.append("{0}: {1}".format(spec.name, error))
            print("FAILED {0}: {1}".format(spec.name, error))
    if failures:
        raise SystemExit(
            "{0} creature(s) failed:\n  {1}".format(
                len(failures), "\n  ".join(failures)))
    print("built {0} rigged fauna creature(s)".format(len(specs)))


if __name__ == "__main__":
    main()
