"""Rigged crawler siege bodies: a hanging knell-bell and a winged oculus.

These are the ranger and rammer stand-ins. They grow from one skin-tree, the
same kit as the land fauna, then sit on the flying siege actors instead of a
capsule or a sphere.

Run from the project root with Blender 5.1:

    & "C:\\Program Files\\\\Blender Foundation\\\\Blender 5.1\\\\blender.exe" `
        --background --factory-startup `
        --python assets/source/blender/build_crawler_creatures.py

Or through the shared fauna entry point:

    ... --python assets/source/blender/build_fauna_creatures.py -- --only knell_bell rift_oculus
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
    joints = []
    previous = parent
    for index, (name, position, radius) in enumerate(steps):
        joints.append(J(
            name, previous, position, radius,
            connected=connected and index > 0))
        previous = name
    return joints


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


def core_table(idle, walk, run, attack, hit, defeat):
    return [
        ("Idle", 84, True, idle),
        ("Walk", 32, True, walk),
        ("Run", 22, True, run),
        ("Attack", 28, False, attack),
        ("HitReact", 16, False, hit),
        ("Defeat", 42, False, defeat),
    ]


# --------------------------------------------------------------------------
# Knell-Bell — flying ranger
# --------------------------------------------------------------------------

def knell_bell() -> CreatureSpec:
    """A squat temple bell: rounded dome, wide lip, clapper, short tassels."""
    h = 2.40
    palette = rgba("3A1218", "C42828", "E8C04A", "F3E6D0", "8B1E3F", "6FE05A")
    joints = [
        J("Root", None, (0.0, 0.0, 0.01), 0.02, deform=False),
        J("Hips", "Root", (0.0, 0.02, 0.62), 0.92),
        J("RimFlare", "Hips", (0.0, 0.00, 0.52), 1.02, volume=True),
        J("Belly", "Hips", (0.0, 0.04, 1.02), 0.72, connected=True),
        J("Waist", "Belly", (0.0, 0.04, 1.38), 0.58, connected=True),
        J("Dome", "Waist", (0.0, 0.03, 1.72), 0.46, connected=True),
        J("Crown", "Dome", (0.0, 0.02, 2.02), 0.22, connected=True),
        J("Knob", "Crown", (0.0, 0.00, 2.22), 0.09, connected=True),
        J("Lip", "Hips", (0.0, 0.06, 0.36), 0.74, connected=True),
        J("Mouth", "Lip", (0.0, 0.08, 0.18), 0.26, connected=True),
        J("Clapper", "Mouth", (0.0, 0.04, 0.06), 0.11, connected=True),
        J("FrontLip", "Lip", (0.0, 0.28, 0.34), 0.12, volume=True),
    ]
    limbs: list[tuple] = [("Mouth", "Clapper")]
    for index in range(6):
        angle = TAU * index / 6.0 + 0.18
        sx = math.sin(angle)
        sy = math.cos(angle)
        a = "Tendril{0}A".format(index + 1)
        b = "Tendril{0}B".format(index + 1)
        c = "Tendril{0}C".format(index + 1)
        joints += chain("Hips", [
            (a, (0.86 * sx, 0.86 * sy, 0.38), 0.042),
            (b, (0.98 * sx, 0.98 * sy, 0.20), 0.028),
            (c, (1.06 * sx, 1.06 * sy, 0.05), 0.016),
        ])
        limbs.append((a, b, c))

    def region_of(centre, height):
        x, y, z = shares(centre, height)
        radial = math.hypot(x, y)
        if z > 0.88:
            return 5
        if z < 0.08:
            return 4
        if z < 0.20 and radial < 0.14:
            return 3
        if radial > 0.30 and z < 0.42:
            return 2
        if z < 0.40 and radial > 0.16:
            return 1
        return 0

    def animations(anim):
        rot = anim.rot

        def tendrils(pose, phase, amount, trail=0.0):
            for index in range(6):
                wave = phase + TAU * index / 6.0
                prefix = "Tendril{0}".format(index + 1)
                pose[prefix + "A"] = rot(
                    ("X", amount * math.sin(wave) + 10.0 * trail),
                    ("Y", 8.0 * math.cos(wave)))
                pose[prefix + "B"] = rot(
                    ("X", amount * 1.15 * math.sin(wave + 0.55)))
                pose[prefix + "C"] = rot(
                    ("X", amount * 0.85 * math.sin(wave + 1.05)))

        def idle_pose(t):
            breath = math.sin(t * TAU)
            pose = {
                "Hips": {"loc": (0.0, 0.0, 0.012 * breath)},
                "Belly": rot(("X", 1.6 * breath)),
                "Dome": rot(("X", 2.2 * breath)),
                "Crown": rot(("Z", 3.0 * math.sin(t * TAU * 0.5))),
                "Knob": rot(("X", 4.0 * breath)),
                "Clapper": rot(("X", 6.0 * math.sin(t * TAU * 0.7)),
                               ("Z", 4.0 * math.sin(t * TAU * 0.45))),
                "Lip": rot(("X", 1.2 * breath)),
            }
            tendrils(pose, t * TAU, 9.0)
            return pose

        def walk_pose(t):
            phase = t * TAU
            pulse_z = 0.028 * abs(math.sin(phase * 2.0))
            pose = {
                "Hips": {"rot": [("Z", 6.0 * math.sin(phase))],
                         "loc": (0.0, 0.0, pulse_z)},
                "Belly": rot(("X", 5.0 * math.sin(phase * 2.0))),
                "Waist": rot(("X", 4.0 * math.sin(phase * 2.0))),
                "Dome": rot(("X", -3.0 * math.sin(phase * 2.0))),
                "Crown": rot(("Z", 5.0 * math.sin(phase))),
                "Lip": rot(("X", 4.0 * math.sin(phase * 2.0))),
                "Clapper": rot(("X", 14.0 * math.sin(phase)),
                               ("Z", 8.0 * math.cos(phase))),
            }
            tendrils(pose, phase, 24.0, trail=0.15)
            return pose

        def run_pose(t):
            phase = t * TAU
            pose = {
                "Hips": {"rot": [("X", -6.0), ("Z", 8.0 * math.sin(phase))],
                         "loc": (0.0, 0.0, 0.04 * abs(math.sin(phase * 2.0)))},
                "Belly": rot(("X", 8.0 * math.sin(phase * 2.0))),
                "Waist": rot(("X", -5.0)),
                "Dome": rot(("X", 4.0 * math.sin(phase * 2.0))),
                "Lip": rot(("X", 6.0 * math.sin(phase * 2.0))),
                "Clapper": rot(("X", 18.0 * math.sin(phase * 2.0))),
            }
            tendrils(pose, phase * 1.35, 34.0, trail=0.35)
            return pose

        def attack_pose(t):
            wind = pulse(t, 0.0, 0.22, 0.40)
            ring = pulse(t, 0.22, 0.48, 0.82)
            pose = {
                "Hips": {"rot": [("X", 8.0 * wind - 4.0 * ring)],
                         "loc": (0.0, 0.04 * ring, 0.02 * wind)},
                "Belly": rot(("X", 6.0 * wind)),
                "Waist": rot(("X", -8.0 * ring)),
                "Dome": rot(("X", 10.0 * wind - 6.0 * ring)),
                "Crown": rot(("X", 8.0 * wind)),
                "Lip": rot(("X", -12.0 * wind + 16.0 * ring)),
                "Mouth": rot(("X", 18.0 * ring)),
                "Clapper": rot(("X", -16.0 * wind + 52.0 * ring),
                               ("Z", 10.0 * ring)),
            }
            tendrils(pose, 0.4, 10.0 + 16.0 * wind, trail=-0.25 + 0.7 * ring)
            return pose

        def hit_pose(t):
            hit = math.sin(math.pi * min(t, 1.0))
            pose = {
                "Hips": {"rot": [("Z", -12.0 * hit)],
                         "loc": (0.0, -0.03 * hit, -0.02 * hit)},
                "Dome": rot(("X", 10.0 * hit)),
                "Crown": rot(("X", -8.0 * hit)),
                "Clapper": rot(("X", -18.0 * hit)),
            }
            tendrils(pose, math.pi, 20.0 * hit)
            return pose

        def defeat_pose(t):
            fall = ease(t)
            pose = {
                "Hips": {"rot": [("X", 22.0 * fall), ("Z", 12.0 * fall)],
                         "loc": (0.0, 0.0, -0.16 * fall)},
                "Belly": rot(("X", 10.0 * fall)),
                "Dome": rot(("X", 14.0 * fall)),
                "Crown": rot(("X", -16.0 * fall)),
                "Lip": rot(("X", -10.0 * fall)),
                "Clapper": rot(("X", 24.0 * fall)),
            }
            tendrils(pose, 1.4, 8.0, trail=0.55 * fall)
            return pose

        return core_table(
            idle_pose, walk_pose, run_pose, attack_pose, hit_pose, defeat_pose)

    return CreatureSpec(
        "knell_bell", "Knell-Bell", "bell", 20260951, h, palette,
        (4000, 8200),
        {"shape": "capsule", "radius": 0.88, "height": 2.20,
         "centre": [0.0, 1.10, 0.0]},
        "Wine hide streaks, ember rim bands, gold lip rings, cream mouth blaze, "
        "magenta clapper spots, and lime crown discs",
        "crown knob and clapper glow after sunset",
        1.70, joints, limbs, REQUIRED_CORE_CLIPS, region_of,
        painter(palette, 20260951,
                ("streaks", "bands", "rings", "blaze", "spots", "spots")),
        animations, roughness=0.48)


# --------------------------------------------------------------------------
# Rift-Oculus — ramming eyeball with wings
# --------------------------------------------------------------------------

def rift_oculus() -> CreatureSpec:
    """A round eyeball with a cornea, lids, and a pair of membrane wings."""
    h = 2.05
    palette = rgba("F3E6D0", "2A4A8C", "1A1A20", "E85CA8", "6B3FA0", "C42828")
    joints = [
        J("Root", None, (0.0, 0.0, 0.01), 0.02, deform=False),
        # Hips sits in the cornea so the centre of a round globe is not a
        # deform bone hanging in empty space (the kit rejects that).
        J("Hips", "Root", (0.0, 0.40, 1.02), 0.36),
        J("Globe", "Hips", (0.0, 0.00, 1.02), 0.70, volume=True),
        J("Front", "Hips", (0.0, 0.58, 1.02), 0.28, volume=True),
        J("Back", "Hips", (0.0, -0.48, 1.02), 0.32, volume=True),
        J("Top", "Hips", (0.0, 0.08, 1.56), 0.30, volume=True),
        J("Bottom", "Hips", (0.0, 0.08, 0.48), 0.30, volume=True),
        J("LeftBulge", "Hips", (-0.50, 0.08, 1.02), 0.30, volume=True),
        J("RightBulge", "Hips", (0.50, 0.08, 1.02), 0.30, volume=True),
        J("Iris", "Hips", (0.0, 0.58, 1.02), 0.22, connected=True),
        J("Pupil", "Iris", (0.0, 0.76, 1.02), 0.11, connected=True),
        J("LidUpper", "Hips", (0.0, 0.50, 1.36), 0.12),
        J("LidLower", "Hips", (0.0, 0.50, 0.68), 0.11),
        J("Optic", "Hips", (0.0, -0.28, 1.00), 0.08),
    ]
    joints += [
        J("LeftWingShoulder", "Hips", (-0.62, 0.02, 1.14), (0.11, 0.05)),
        J("RightWingShoulder", "Hips", (0.62, 0.02, 1.14), (0.11, 0.05)),
    ]
    joints += chain("LeftWingShoulder", [
        ("LeftWingLeadA", (-0.96, 0.04, 1.26), (0.20, 0.032)),
        ("LeftWingLeadB", (-1.22, 0.02, 1.22), (0.15, 0.024)),
        ("LeftWingLeadTip", (-1.40, -0.04, 1.12), (0.06, 0.014)),
    ])
    joints += chain("LeftWingShoulder", [
        ("LeftWingTrailA", (-0.94, -0.14, 1.00), (0.18, 0.030)),
        ("LeftWingTrailB", (-1.18, -0.20, 0.94), (0.13, 0.022)),
        ("LeftWingTrailTip", (-1.36, -0.26, 0.90), (0.05, 0.014)),
    ])
    joints += chain("RightWingShoulder", [
        ("RightWingLeadA", (0.96, 0.04, 1.26), (0.20, 0.032)),
        ("RightWingLeadB", (1.22, 0.02, 1.22), (0.15, 0.024)),
        ("RightWingLeadTip", (1.40, -0.04, 1.12), (0.06, 0.014)),
    ])
    joints += chain("RightWingShoulder", [
        ("RightWingTrailA", (0.94, -0.14, 1.00), (0.18, 0.030)),
        ("RightWingTrailB", (1.18, -0.20, 0.94), (0.13, 0.022)),
        ("RightWingTrailTip", (1.36, -0.26, 0.90), (0.05, 0.014)),
    ])
    limbs = (
        ("Iris", "Pupil"),
        ("LeftWingShoulder", "LeftWingLeadA", "LeftWingLeadB", "LeftWingLeadTip"),
        ("LeftWingTrailA", "LeftWingTrailB", "LeftWingTrailTip"),
        ("RightWingShoulder", "RightWingLeadA", "RightWingLeadB", "RightWingLeadTip"),
        ("RightWingTrailA", "RightWingTrailB", "RightWingTrailTip"),
    )

    def region_of(centre, height):
        x, y, z = shares(centre, height)
        if y > 0.28 and abs(x) < 0.14:
            return 2 if y > 0.36 else 1
        if abs(x) > 0.30:
            return 4
        if y > 0.14 and (z > 0.70 or z < 0.30):
            return 3
        if y < -0.20:
            return 5
        return 0

    def animations(anim):
        rot = anim.rot

        def wings(pose, flap, fold=0.0, sweep=0.0):
            for side, sign in (("Left", -1.0), ("Right", 1.0)):
                pose[side + "WingShoulder"] = rot(
                    ("Y", sign * (10.0 + 30.0 * flap - 16.0 * fold)),
                    ("X", -8.0 * fold + 6.0 * sweep))
                pose[side + "WingLeadA"] = rot(
                    ("Y", sign * (20.0 * flap - 8.0 * fold)),
                    ("X", 4.0 * sweep))
                pose[side + "WingLeadB"] = rot(("Y", sign * 14.0 * flap))
                pose[side + "WingLeadTip"] = rot(
                    ("Y", sign * 10.0 * flap), ("X", 6.0 * flap))
                pose[side + "WingTrailA"] = rot(
                    ("Y", sign * (16.0 * flap - 6.0 * fold)),
                    ("X", 8.0 * fold))
                pose[side + "WingTrailB"] = rot(("Y", sign * 12.0 * flap))
                pose[side + "WingTrailTip"] = rot(("Y", sign * 8.0 * flap))

        def lids(pose, close):
            pose["LidUpper"] = rot(("X", -28.0 * close))
            pose["LidLower"] = rot(("X", 22.0 * close))

        def idle_pose(t):
            breath = math.sin(t * TAU)
            blink = max(0.0, math.sin(t * TAU * 0.35) ** 16)
            pose = {
                "Hips": {"loc": (0.0, 0.0, 0.010 * breath)},
                "Iris": rot(("X", 3.0 * math.sin(t * TAU * 0.5)),
                            ("Z", 4.0 * math.sin(t * TAU * 0.4))),
                "Pupil": rot(("X", 2.0 * breath)),
                "Optic": rot(("X", 3.0 * breath)),
            }
            lids(pose, blink)
            wings(pose, 0.14 * breath, 0.12)
            return pose

        def walk_pose(t):
            phase = t * TAU
            pose = {
                "Hips": {"rot": [("Z", 5.0 * math.sin(phase))],
                         "loc": (0.0, 0.0, 0.024 * abs(math.sin(phase * 2.0)))},
                "Iris": rot(("X", 4.0 * math.sin(phase * 2.0))),
                "Pupil": rot(("X", 3.0 * math.sin(phase))),
                "Optic": rot(("X", -6.0 * math.sin(phase))),
            }
            lids(pose, 0.0)
            wings(pose, 0.55 * math.sin(phase * 2.0), 0.05, sweep=0.15)
            return pose

        def run_pose(t):
            phase = t * TAU
            pose = {
                "Hips": {"rot": [("X", -8.0), ("Z", 7.0 * math.sin(phase))],
                         "loc": (0.0, 0.0, 0.036 * abs(math.sin(phase * 2.0)))},
                "Iris": rot(("X", 5.0 * math.sin(phase * 2.0))),
                "Pupil": rot(("X", 4.0)),
                "Optic": rot(("X", -10.0)),
            }
            lids(pose, 0.08)
            wings(pose, 0.85 * math.sin(phase * 2.0), 0.0, sweep=0.35)
            return pose

        def attack_pose(t):
            wind = pulse(t, 0.0, 0.20, 0.38)
            lunge = pulse(t, 0.22, 0.48, 0.82)
            pose = {
                "Hips": {"rot": [("X", 8.0 * wind - 10.0 * lunge)],
                         "loc": (0.0, 0.08 * lunge, 0.01 * wind)},
                "Iris": rot(("X", -6.0 * wind + 8.0 * lunge)),
                "Pupil": rot(("X", 12.0 * lunge)),
                "Optic": rot(("X", 16.0 * wind - 8.0 * lunge)),
            }
            lids(pose, 0.15 * wind + 0.55 * lunge)
            wings(pose, 0.20 + 0.15 * wind, 0.55 * lunge, sweep=0.6 * lunge)
            return pose

        def hit_pose(t):
            hit = math.sin(math.pi * min(t, 1.0))
            pose = {
                "Hips": {"rot": [("Z", -10.0 * hit)],
                         "loc": (0.0, -0.03 * hit, -0.02 * hit)},
                "Iris": rot(("X", 8.0 * hit)),
                "Pupil": rot(("X", -6.0 * hit)),
            }
            lids(pose, 0.7 * hit)
            wings(pose, 0.45 * hit, 0.1)
            return pose

        def defeat_pose(t):
            fall = ease(t)
            pose = {
                "Hips": {"rot": [("X", 28.0 * fall), ("Z", 16.0 * fall)],
                         "loc": (0.0, 0.0, -0.18 * fall)},
                "Iris": rot(("X", -12.0 * fall)),
                "Pupil": rot(("X", 8.0 * fall)),
                "Optic": rot(("X", 10.0 * fall)),
            }
            lids(pose, 0.9 * fall)
            wings(pose, -0.15 * fall, 0.7 * fall)
            return pose

        return core_table(
            idle_pose, walk_pose, run_pose, attack_pose, hit_pose, defeat_pose)

    return CreatureSpec(
        "rift_oculus", "Rift-Oculus", "oculus", 20260952, h, palette,
        (3800, 8200),
        {"shape": "sphere", "radius": 0.82, "height": 1.64,
         "centre": [0.0, 1.02, 0.0]},
        "Cream sclera blaze, indigo iris rings, black pupil disc, pink lid "
        "streaks, violet wing bands, and red optic veins",
        "iris ring and wing-edge glow after sunset",
        1.80, joints, limbs, REQUIRED_CORE_CLIPS, region_of,
        painter(palette, 20260952,
                ("blaze", "rings", "spots", "streaks", "bands", "chevrons")),
        animations, roughness=0.34)


CRAWLER_CREATURES = (
    knell_bell(),
    rift_oculus(),
)
CRAWLER_BY_NAME = {spec.name: spec for spec in CRAWLER_CREATURES}


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
        return list(CRAWLER_CREATURES)
    requested: list[str] = []
    for value in only:
        requested.extend(
            name.strip() for name in value.split(",") if name.strip())
    unknown = sorted(set(requested) - set(CRAWLER_BY_NAME))
    if unknown:
        raise SystemExit("unknown crawler creature(s): " + ", ".join(unknown))
    wanted = set(requested)
    return [spec for spec in CRAWLER_CREATURES if spec.name in wanted]


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
    print("built {0} crawler creature(s)".format(len(specs)))


if __name__ == "__main__":
    main()
