"""Five colour-paint PNGs for each old procedural city mass.

The runtime still emits VARIANT_RECT / GABLE / TAPER / … boxes. This writer
makes a regenerable atlas per shape so those masses can sample the same
city_wall paint path as the authored GLBs.

Run from the repository root with Blender 5.1:

    & "C:\\Program Files\\Blender Foundation\\Blender 5.1\\blender.exe" `
        --background --factory-startup `
        --python assets/source/blender/build_city_variants.py
"""

from __future__ import annotations

import argparse
import json
import os
import sys

import bpy

SOURCE_DIR = os.path.dirname(os.path.abspath(__file__))
PROJECT_DIR = os.path.abspath(os.path.join(
    SOURCE_DIR, os.pardir, os.pardir, os.pardir))
if SOURCE_DIR not in sys.path:
    sys.path.insert(0, SOURCE_DIR)

import building_kit as kit

PAINT_ROOT = os.path.join(PROJECT_DIR, "assets", "runtime", "cities", "paint")
MANIFEST_PATH = os.path.join(
    PROJECT_DIR, "assets", "runtime", "cities", "manifests", "buildings.json")

# Typical lot proportions so window bays and roof bands match each mass.
_SHAPE_SPEC = {
    "rect": dict(seed=101, width=10.0, depth=8.0, stories=3, glow="warm"),
    "cylinder": dict(seed=118, width=8.0, depth=8.0, stories=3, glow="warm"),
    "rect_cap": dict(seed=134, width=10.0, depth=8.0, stories=4, glow="warm"),
    "gable": dict(seed=151, width=10.0, depth=7.0, stories=2, glow="warm"),
    "round_end": dict(seed=167, width=12.0, depth=7.0, stories=2, glow="warm"),
    "taper": dict(seed=183, width=14.0, depth=14.0, stories=16, glow="cool"),
    "point_half": dict(seed=199, width=14.0, depth=12.0, stories=14, glow="cool"),
    "slant_half": dict(seed=211, width=14.0, depth=12.0, stories=14, glow="cool"),
    "cyl_half": dict(seed=227, width=14.0, depth=14.0, stories=18, glow="cool"),
}


def _noop(_ctx, _recipe):
    return


def _rel(path):
    return os.path.relpath(path, PROJECT_DIR).replace("\\", "/")


def _paint_path(name, style):
    return os.path.join(PAINT_ROOT, "variants", "{0}_{1}_paint.png".format(name, style))


def _recipe_for(name):
    spec = _SHAPE_SPEC[name]
    return kit.BuildingRecipe(
        name=name,
        category="variants",
        display_name=name.replace("_", " ").title(),
        seed=int(spec["seed"]),
        width=float(spec["width"]),
        depth=float(spec["depth"]),
        stories=int(spec["stories"]),
        builder=_noop,
        glow_family=str(spec["glow"]),
        paint_size=512,
        notes="procedural {0} mass colour atlas".format(name),
    )


def build_one(recipe, skip_paints=False):
    print("\n=== variant {} ===".format(recipe.name))
    paint_dir = os.path.join(PAINT_ROOT, "variants")
    os.makedirs(paint_dir, exist_ok=True)
    paint_entries = []
    for style in kit.VARIANT_PAINT_STYLES:
        path = _paint_path(recipe.name, style)
        if not skip_paints:
            image = kit.write_paint(recipe, style, path)
            if image is not None and image.name in bpy.data.images:
                bpy.data.images.remove(image, do_unlink=True)
        glow = kit.glow_for(recipe, style)
        paint_entries.append({
            "style": style,
            "path": _rel(path),
            "size": [recipe.paint_size, recipe.paint_size],
            "window_glow": [
                round(float(glow[0]), 4),
                round(float(glow[1]), 4),
                round(float(glow[2]), 4),
            ],
        })
    return {
        "name": recipe.name,
        "display_name": recipe.display_name,
        "category": "variants",
        "variant_id": kit.VARIANT_SHAPES.index(recipe.name),
        "notes": recipe.notes,
        "authored_width": recipe.width,
        "authored_depth": recipe.depth,
        "authored_stories": recipe.stories,
        "paints": paint_entries,
        "material": {
            "color_paint_uv": "TEXCOORD_0 or world-wrap on procedural hulls",
            "color_paint_alpha": (
                "night window emission mask; never used as transparency"),
        },
    }


def write_manifest(entries):
    manifest = {
        "schema": "authored_city_building_manifest",
        "version": 1,
        "generator": "assets/source/blender/build_city_variants.py",
        "assets": {},
        "paint_styles": list(kit.PAINT_STYLES),
        "variant_paint_styles": list(kit.VARIANT_PAINT_STYLES),
        "variants": {},
        "categories": [
            "small_houses", "medium_apartments", "medium_buildings",
            "large_towers", "skyscrapers", "specials",
        ],
    }
    if os.path.isfile(MANIFEST_PATH):
        with open(MANIFEST_PATH, "r", encoding="utf-8") as stream:
            existing = json.load(stream)
        if existing.get("schema") == manifest["schema"]:
            manifest.update({
                key: existing[key]
                for key in existing
                if key not in ("variants", "variant_paint_styles", "generator")
            })
            manifest["paint_styles"] = existing.get(
                "paint_styles", list(kit.PAINT_STYLES))
    manifest["generator"] = "assets/source/blender/build_city_variants.py"
    manifest["variant_paint_styles"] = list(kit.VARIANT_PAINT_STYLES)
    variants = dict(manifest.get("variants", {}))
    for entry in entries:
        variants[entry["name"]] = entry
    ordered = {}
    for name in kit.VARIANT_SHAPES:
        if name in variants:
            ordered[name] = variants[name]
    for name in sorted(set(variants) - set(ordered)):
        ordered[name] = variants[name]
    manifest["variants"] = ordered
    manifest["asset_count"] = len(manifest.get("assets", {}))
    os.makedirs(os.path.dirname(MANIFEST_PATH), exist_ok=True)
    with open(MANIFEST_PATH, "w", encoding="utf-8", newline="\n") as stream:
        json.dump(manifest, stream, indent=2, sort_keys=False)
        stream.write("\n")
    return MANIFEST_PATH


def arguments():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--only", nargs="+", metavar="NAME")
    parser.add_argument("--skip-paints", action="store_true")
    blender_arguments = (
        sys.argv[sys.argv.index("--") + 1:] if "--" in sys.argv else [])
    return parser.parse_args(blender_arguments)


def selected(options):
    names = list(kit.VARIANT_SHAPES)
    if options.only:
        wanted = []
        for value in options.only:
            wanted.extend(item.strip() for item in value.split(",") if item.strip())
        unknown = sorted(set(wanted) - set(kit.VARIANT_SHAPES))
        if unknown:
            raise SystemExit("unknown variant(s): " + ", ".join(unknown))
        names = wanted
    return [_recipe_for(name) for name in names]


def main():
    kit.reset_scene()
    options = arguments()
    recipes = selected(options)
    if not recipes:
        raise SystemExit("no variant shapes selected")
    entries = [build_one(recipe, skip_paints=options.skip_paints) for recipe in recipes]
    path = write_manifest(entries)
    print("\nCITY_VARIANT_SUMMARY")
    print(json.dumps({
        "manifest": path,
        "variant_count": len(entries),
        "styles": list(kit.VARIANT_PAINT_STYLES),
        "variants": [entry["name"] for entry in entries],
    }, indent=2, sort_keys=True))
    print("city variant paints complete")


if __name__ == "__main__":
    main()
