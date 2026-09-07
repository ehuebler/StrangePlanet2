"""Generate typed Godot ability resources from the runtime manifest.

Run from the project root:

    python assets/source/build_ability_catalog.py

Or, on a machine using Blender's bundled Python:

    blender --background --factory-startup \
        --python assets/source/build_ability_catalog.py

Use ``--check`` in CI to verify the committed resources are current. The
Blender form places it after a separator: ``-- --check``. The
manifest is the authored source of truth; the generated .tres files are what
ItemDB, the menu, and AbilityController load at runtime.
"""

from __future__ import annotations

import argparse
import json
import sys
from pathlib import Path
from typing import Any


ROOT = Path(__file__).resolve().parents[2]
MANIFEST = ROOT / "assets/runtime/abilities/ability_manifest.json"
DEFINITION_DIR = ROOT / "game/abilities/definitions"
CATALOG = ROOT / "game/abilities/ability_catalog.gd"

ENUMS = {
    "activation_type": {
        "INSTANT": 0,
        "SUSTAINED": 1,
        "COMMITTED": 2,
    },
    "projectile_type": {
        "NONE": 0,
        "BEAM": 1,
        "SELF": 2,
        "ENERGY_DISK": 3,
        "ENERGY_ORB": 4,
        "TETHER": 5,
        "ENERGY_BOLT": 6,
        "ENERGY_ICICLE": 7,
        "TELEPORT_ORB": 8,
        "ENERGY_CONE": 9,
    },
    "impact_type": {
        "NONE": 0,
        "BURN": 1,
        "METEOR_CRATER": 2,
        "EXPLOSION_CRATER": 3,
        "GRAPPLE_SLAM": 4,
        "MASSIVE_BLAST": 5,
        "DELAYED_BLAST": 6,
        "FROST_BURST": 7,
        "TELEPORT": 8,
        "KNOCKBACK_BURST": 9,
    },
    "grapple_type": {
        "NONE": 0,
        "CARRY_SLAM": 1,
        "PHYSICS_TETHER": 2,
    },
    "construct_type": {
        "NONE": 0,
        "BARRIER": 1,
    },
    "reaction_type": {
        "NONE": 0,
        "STAGGER": 1,
        "KNOCKBACK": 2,
        "RAGDOLL": 3,
    },
}

STANCES = {
    "STAND": 0,
    "CROUCH": 1,
    "SLIDE": 2,
    "FLY": 3,
    "CRASH": 4,
    "SWIM": 5,
    "HERO": 6,
    "METEOR": 7,
    "GRAPPLE": 8,
}


def load_manifest() -> list[dict[str, Any]]:
    raw = json.loads(MANIFEST.read_text(encoding="utf-8"))
    if raw.get("version") != 1:
        raise ValueError("ability manifest version must be 1")
    abilities = raw.get("abilities")
    if not isinstance(abilities, list) or not abilities:
        raise ValueError("ability manifest must contain a non-empty abilities list")

    seen: set[str] = set()
    for entry in abilities:
        ability_id = entry.get("id", "")
        if not isinstance(ability_id, str) or not ability_id.replace("_", "").isalnum():
            raise ValueError(f"invalid ability id: {ability_id!r}")
        if ability_id in seen:
            raise ValueError(f"duplicate ability id: {ability_id}")
        seen.add(ability_id)
        for key in ("title", "description", "implementation", "icon", "tint"):
            if not entry.get(key):
                raise ValueError(f"{ability_id}: missing {key}")
        for key, values in ENUMS.items():
            value = entry.get(key, "NONE")
            if value not in values:
                raise ValueError(f"{ability_id}: invalid {key} {value!r}")
        stats = entry.get("stats")
        if not isinstance(stats, dict):
            raise ValueError(f"{ability_id}: stats must be an object")
        allowed_stances = entry.get("allowed_stances", [])
        if not isinstance(allowed_stances, list) or any(
            stance not in STANCES for stance in allowed_stances
        ):
            raise ValueError(
                f"{ability_id}: allowed_stances must contain known stance names"
            )
        for required in ("damage", "range", "cooldown"):
            if required not in stats:
                raise ValueError(f"{ability_id}: missing required stat {required}")
    return abilities


def godot_value(value: Any) -> str:
    if isinstance(value, bool):
        return "true" if value else "false"
    if isinstance(value, str):
        return json.dumps(value, ensure_ascii=False)
    if isinstance(value, int):
        return str(value)
    if isinstance(value, float):
        return repr(value)
    raise TypeError(f"unsupported Godot value: {value!r}")


def color_value(hex_color: str) -> str:
    clean = hex_color.removeprefix("#")
    if len(clean) == 6:
        clean += "FF"
    if len(clean) != 8:
        raise ValueError(f"invalid RGBA colour: {hex_color}")
    channels = [int(clean[index:index + 2], 16) / 255.0 for index in range(0, 8, 2)]
    return "Color({})".format(", ".join(f"{channel:.6f}" for channel in channels))


def definition_text(entry: dict[str, Any]) -> str:
    animations = entry.get("animations", {})
    allowed = ", ".join(
        str(STANCES[value]) for value in entry.get("allowed_stances", [])
    )
    stats = entry["stats"]
    stat_lines = ["stats = {"]
    for key, value in stats.items():
        stat_lines.append(f"{json.dumps(key)}: {godot_value(value)},")
    stat_lines.append("}")

    return "\n".join(
        [
            "[gd_resource type=\"Resource\" script_class=\"AbilityDefinition\" load_steps=4 format=3]",
            "",
            "[ext_resource type=\"Script\" path=\"res://game/abilities/ability_definition.gd\" id=\"1_definition\"]",
            f"[ext_resource type=\"Script\" path={json.dumps(entry['implementation'])} id=\"2_implementation\"]",
            f"[ext_resource type=\"Texture2D\" path={json.dumps(entry['icon'])} id=\"3_icon\"]",
            "",
            "[resource]",
            "script = ExtResource(\"1_definition\")",
            f"ability_id = {json.dumps(entry['id'])}",
            f"title = {json.dumps(entry['title'], ensure_ascii=False)}",
            f"description = {json.dumps(entry['description'], ensure_ascii=False)}",
            "implementation = ExtResource(\"2_implementation\")",
            "icon = ExtResource(\"3_icon\")",
            f"tint = {color_value(entry['tint'])}",
            f"activation_type = {ENUMS['activation_type'][entry['activation_type']]}",
            f"projectile_type = {ENUMS['projectile_type'][entry['projectile_type']]}",
            f"impact_type = {ENUMS['impact_type'][entry['impact_type']]}",
            f"grapple_type = {ENUMS['grapple_type'][entry['grapple_type']]}",
            f"construct_type = {ENUMS['construct_type'][entry.get('construct_type', 'NONE')]}",
            f"reaction_type = {ENUMS['reaction_type'][entry.get('reaction_type', 'NONE')]}",
            f"affects_players = {godot_value(bool(entry.get('affects_players', False)))}",
            f"self_launch = {godot_value(bool(entry.get('self_launch', False)))}",
            f"blast_occlusion = {godot_value(bool(entry.get('blast_occlusion', False)))}",
            f"animation = &{json.dumps(animations.get('primary', ''))}",
            f"alternate_animation = &{json.dumps(animations.get('alternate', ''))}",
            f"hover_animation = &{json.dumps(animations.get('hover', ''))}",
            f"alternate_hover_animation = &{json.dumps(animations.get('alternate_hover', ''))}",
            f"held_animation = &{json.dumps(animations.get('held', ''))}",
            f"held_hover_animation = &{json.dumps(animations.get('held_hover', ''))}",
            f"impact_animation = &{json.dumps(animations.get('impact', ''))}",
            f"blocked_underwater = {godot_value(bool(entry.get('blocked_underwater', False)))}",
            f"allowed_stances = PackedInt32Array({allowed})",
            *stat_lines,
            "",
        ]
    )


def catalog_text(abilities: list[dict[str, Any]]) -> str:
    ids = ", ".join(json.dumps(entry["id"]) for entry in abilities)
    paths = "\n".join(
        f"\t{json.dumps(entry['id'])}: "
        f"{json.dumps('res://game/abilities/definitions/' + entry['id'] + '.tres')},"
        for entry in abilities
    )
    return f"""# Generated by assets/source/build_ability_catalog.py. Do not hand-edit.
class_name AbilityCatalog
extends RefCounted

const ORDER := [{ids}]
const PATHS := {{
{paths}
}}

static var _cache: Dictionary = {{}}


static func ids() -> PackedStringArray:
\treturn PackedStringArray(ORDER)


static func has(id: String) -> bool:
\treturn PATHS.has(id)


static func definition(id: String) -> AbilityDefinition:
\tif not PATHS.has(id):
\t\treturn null
\tif not _cache.has(id):
\t\tvar loaded := load(String(PATHS[id])) as AbilityDefinition
\t\tif loaded == null or not loaded.valid() or loaded.ability_id != id:
\t\t\tpush_error("Ability definition '%s' is invalid" % id)
\t\t\t_cache[id] = null
\t\telse:
\t\t\t_cache[id] = loaded
\treturn _cache[id] as AbilityDefinition
"""


def write_or_check(path: Path, content: str, check: bool) -> bool:
    current = path.read_text(encoding="utf-8") if path.exists() else None
    if current == content:
        return True
    if check:
        print(f"out of date: {path.relative_to(ROOT)}")
        return False
    path.parent.mkdir(parents=True, exist_ok=True)
    path.write_text(content, encoding="utf-8", newline="\n")
    print(f"wrote {path.relative_to(ROOT)}")
    return True


def main() -> int:
    parser = argparse.ArgumentParser()
    parser.add_argument("--check", action="store_true")
    # Blender's bundled Python leaves Blender's own command-line switches in
    # sys.argv. Arguments after Blender's `--` separator belong to this script;
    # ordinary Python has no separator and can be parsed directly.
    if "--" in sys.argv:
        args = parser.parse_args(sys.argv[sys.argv.index("--") + 1:])
    else:
        args, _host_args = parser.parse_known_args()

    abilities = load_manifest()
    ok = True
    expected: set[Path] = set()
    for entry in abilities:
        path = DEFINITION_DIR / f"{entry['id']}.tres"
        expected.add(path)
        ok = write_or_check(path, definition_text(entry), args.check) and ok
    ok = write_or_check(CATALOG, catalog_text(abilities), args.check) and ok

    if DEFINITION_DIR.exists():
        stale = sorted(DEFINITION_DIR.glob("*.tres"))
        for path in stale:
            if path in expected:
                continue
            if args.check:
                print(f"stale generated file: {path.relative_to(ROOT)}")
                ok = False
            else:
                path.unlink()
                print(f"removed {path.relative_to(ROOT)}")
    return 0 if ok else 1


if __name__ == "__main__":
    raise SystemExit(main())
