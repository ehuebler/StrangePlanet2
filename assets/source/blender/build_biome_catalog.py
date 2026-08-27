"""Generate Godot materials, PlantSpecies resources and biome field scene.

The geometry factory lives in ``build_biome_assets.py``. This companion keeps
the runtime catalogue equally data-driven: habitat tuning is a table below and
the emitted ``.tres``/``.tscn`` files are ordinary reviewable Godot resources.

Run from the repository root after building/importing the GLBs, either through
system Python or Blender's bundled Python:

    python assets/source/blender/build_biome_catalog.py
    blender --background --factory-startup \
        --python assets/source/blender/build_biome_catalog.py --

The script intentionally owns only the new biome library. Existing grass,
flowers, coral, flower trees and fish remain hand-tuned resources.
"""

from __future__ import annotations

import argparse
import json
from pathlib import Path
import sys


SOURCE_DIR = Path(__file__).resolve().parent
PROJECT_DIR = SOURCE_DIR.parents[2]
OUTPUT_DIR = PROJECT_DIR / "game" / "props" / "biomes"
SHADER = "res://shaders/vivid/vivid_plant.gdshader"
SPECIES_SCRIPT = "res://game/props/plant_species.gd"
MODEL_ROOT = "res://assets/runtime/biomes/models"
PAINT_ROOT = "res://assets/runtime/biomes/paint"


def material(**parameters: str) -> dict[str, str]:
    common = {
        "base_color": "Color(1, 1, 1, 1)",
        "saturation": "1.25",
        "brightness": "1.05",
        "tone_variation": "0.2",
        "roughness": "0.72",
        "specular": "0.24",
        "translucency": "0.18",
        "region_albedo": "0.22",
        "region_sheen": "0.22",
        "region_rim": "0.32",
        "rigidity": "2.2",
        "calm_from": "16.0",
        "calm_to": "48.0",
        "wind_sway": "7.0",
        "wind_speed": "0.8",
        "gust_length": "28.0",
        "push_sway": "24.0",
        "max_bend": "34.0",
    }
    common.update(parameters)
    return common


MATERIALS: dict[str, dict[str, str]] = {
    "seaweed": material(
        saturation="1.42", brightness="1.12", roughness="0.58",
        translucency="0.42", region_albedo="0.12", rigidity="1.35",
        calm_from="28.0", calm_to="75.0", wind_sway="18.0",
        wind_speed="0.24", gust_length="64.0", push_sway="34.0",
        max_bend="48.0", underwater="true",
    ),
    "seaweed_glow": material(
        saturation="1.5", brightness="1.16", roughness="0.52",
        translucency="0.48", region_albedo="0.08", rigidity="1.45",
        calm_from="28.0", calm_to="75.0", wind_sway="16.0",
        wind_speed="0.2", gust_length="72.0", push_sway="30.0",
        max_bend="45.0", underwater="true",
        night_emission_color="Color(0.55, 0.8, 1, 1)",
        night_emission_energy="1.15", night_emission_albedo="0.82",
        night_pulse_amount="0.12", night_pulse_speed="0.19",
        night_twinkle_amount="0.18", night_twinkle_speed="0.48",
    ),
    "grass_variant": material(
        saturation="1.18", brightness="1.3", roughness="0.84",
        specular="0.18", translucency="0.0", region_albedo="0.62",
        region_sheen="0.25", rigidity="1.55", calm_from="3.0",
        calm_to="10.0", wind_sway="13.0", wind_speed="0.9",
        gust_length="24.0", push_sway="54.0", max_bend="64.0",
        purple_shift="0.1", custom_z_is_glow="true",
        glow_strength="2.6",
    ),
    "leaf": material(
        saturation="1.3", brightness="1.08", roughness="0.78",
        translucency="0.32", region_albedo="0.42", rigidity="2.1",
        calm_from="18.0", calm_to="55.0", wind_sway="8.0",
        wind_speed="0.72", gust_length="34.0", push_sway="32.0",
        max_bend="42.0",
    ),
    "heather_glow": material(
        saturation="1.55", brightness="1.08", roughness="0.7",
        translucency="0.36", region_albedo="0.3", rigidity="2.35",
        wind_sway="6.0", wind_speed="0.62", gust_length="38.0",
        night_emission_color="Color(0.46, 0.035, 0.78, 1)",
        night_emission_energy="1.6", night_emission_albedo="0.66",
        night_pulse_amount="0.08", night_pulse_speed="0.22",
        night_twinkle_amount="0.55", night_twinkle_speed="0.72",
    ),
    "tree": material(
        saturation="1.28", brightness="1.08", roughness="0.76",
        translucency="0.2", region_albedo="0.3", rigidity="3.65",
        calm_from="40.0", calm_to="110.0", wind_sway="1.8",
        wind_speed="0.48", gust_length="58.0", push_sway="0.0",
        max_bend="4.0",
    ),
    "tree_glow": material(
        saturation="1.38", brightness="1.12", roughness="0.68",
        translucency="0.24", region_albedo="0.24", rigidity="3.65",
        calm_from="40.0", calm_to="110.0", wind_sway="1.8",
        wind_speed="0.48", gust_length="58.0", push_sway="0.0",
        max_bend="4.0",
        night_emission_color="Color(0.42, 0.78, 1, 1)",
        night_emission_energy="1.25", night_emission_albedo="0.78",
        night_pulse_amount="0.18", night_pulse_speed="0.16",
    ),
    "mushroom": material(
        saturation="1.38", brightness="1.08", roughness="0.64",
        translucency="0.24", region_albedo="0.18", rigidity="4.0",
        wind_sway="0.8", push_sway="2.0", max_bend="2.0",
    ),
    "mushroom_glow": material(
        saturation="1.55", brightness="1.12", roughness="0.58",
        translucency="0.3", region_albedo="0.12", rigidity="4.0",
        wind_sway="0.8", push_sway="2.0", max_bend="2.0",
        night_emission_color="Color(0.18, 0.8, 1, 1)",
        night_emission_energy="2.35", night_emission_albedo="0.72",
        night_pulse_amount="0.2", night_pulse_speed="0.24",
        night_twinkle_amount="0.28", night_twinkle_speed="0.55",
    ),
    # A six metre cap fills far more of the screen than a knee-high lantern, so
    # it cannot carry the same emission energy: at 2.35 the giants clipped to
    # white and lost the colour entirely. Lower energy, violet to match the
    # light they cast.
    "mushroom_giant_glow": material(
        saturation="1.45", brightness="1.05", roughness="0.6",
        translucency="0.26", region_albedo="0.14", rigidity="4.0",
        wind_sway="0.6", push_sway="1.4", max_bend="1.6",
        night_emission_color="Color(0.52, 0.22, 1, 1)",
        night_emission_energy="1.25", night_emission_albedo="0.6",
        night_pulse_amount="0.24", night_pulse_speed="0.18",
        night_twinkle_amount="0.12", night_twinkle_speed="0.4",
    ),
    "rock": material(
        saturation="0.92", brightness="0.94", tone_variation="0.28",
        roughness="0.94", specular="0.08", translucency="0.0",
        region_albedo="0.3", region_sheen="0.08", region_rim="0.18",
        rigidity="4.0", wind_sway="0.0", push_sway="0.0",
        max_bend="0.0",
    ),
    "ice_glow": material(
        saturation="1.08", brightness="1.2", tone_variation="0.16",
        roughness="0.28", specular="0.66", translucency="0.26",
        region_albedo="0.18", region_sheen="0.55", region_rim="0.6",
        rigidity="4.0", wind_sway="0.0", push_sway="0.0",
        max_bend="0.0",
        night_emission_color="Color(0.12, 0.48, 1, 1)",
        night_emission_energy="0.52", night_emission_albedo="0.8",
        night_twinkle_amount="0.48", night_twinkle_speed="0.34",
    ),
    "crystal_emerald_glow": material(
        saturation="1.38", brightness="1.08", tone_variation="0.14",
        roughness="0.24", specular="0.72", translucency="0.16",
        region_albedo="0.12", region_sheen="0.42", region_rim="0.58",
        rigidity="4.0", wind_sway="0.0", push_sway="0.0",
        max_bend="0.0", emission_from_paint_alpha="true",
        day_emission_color="Color(0.12, 1, 0.48, 1)",
        day_emission_energy="0.95", day_emission_albedo="0.18",
        night_emission_color="Color(0.08, 1, 0.42, 1)",
        night_emission_energy="1.15", night_emission_albedo="0.22",
        night_pulse_amount="0.08", night_pulse_speed="0.13",
    ),
    "crystal_amethyst_glow": material(
        saturation="1.42", brightness="1.08", tone_variation="0.16",
        roughness="0.27", specular="0.7", translucency="0.18",
        region_albedo="0.11", region_sheen="0.46", region_rim="0.62",
        rigidity="4.0", wind_sway="0.0", push_sway="0.0",
        max_bend="0.0", emission_from_paint_alpha="true",
        day_emission_color="Color(0.7, 0.16, 1, 1)",
        day_emission_energy="0.24", day_emission_albedo="0.2",
        night_emission_color="Color(0.72, 0.18, 1, 1)",
        night_emission_energy="1.6", night_emission_albedo="0.2",
        night_pulse_amount="0.12", night_pulse_speed="0.16",
        night_twinkle_amount="0.28", night_twinkle_speed="0.42",
    ),
    "crystal_spire_glow": material(
        saturation="1.3", brightness="1.1", tone_variation="0.12",
        roughness="0.2", specular="0.76", translucency="0.2",
        region_albedo="0.1", region_sheen="0.52", region_rim="0.66",
        rigidity="4.0", wind_sway="0.0", push_sway="0.0",
        max_bend="0.0", emission_from_paint_alpha="true",
        day_emission_color="Color(0.08, 0.82, 1, 1)",
        day_emission_energy="1.18", day_emission_albedo="0.14",
        night_emission_color="Color(0.08, 0.88, 1, 1)",
        night_emission_energy="1.25", night_emission_albedo="0.18",
        night_pulse_amount="0.1", night_pulse_speed="0.1",
    ),
    "rune_monolith_glow": material(
        saturation="1.18", brightness="0.94", tone_variation="0.18",
        roughness="0.84", specular="0.12", translucency="0.0",
        region_albedo="0.22", region_sheen="0.12", region_rim="0.24",
        rigidity="4.0", wind_sway="0.0", push_sway="0.0",
        max_bend="0.0", emission_from_paint_alpha="true",
        day_emission_color="Color(0.1, 1, 0.78, 1)",
        day_emission_energy="0.16", day_emission_albedo="0.08",
        night_emission_color="Color(0.08, 1, 0.76, 1)",
        night_emission_energy="1.85", night_emission_albedo="0.08",
        night_pulse_amount="0.18", night_pulse_speed="0.11",
    ),
    "rune_boulder_glow": material(
        saturation="1.2", brightness="0.96", tone_variation="0.2",
        roughness="0.9", specular="0.1", translucency="0.0",
        region_albedo="0.24", region_sheen="0.1", region_rim="0.22",
        rigidity="4.0", wind_sway="0.0", push_sway="0.0",
        max_bend="0.0", emission_from_paint_alpha="true",
        night_emission_color="Color(0.72, 0.18, 1, 1)",
        night_emission_energy="1.55", night_emission_albedo="0.1",
        night_pulse_amount="0.1", night_pulse_speed="0.17",
        night_twinkle_amount="0.2", night_twinkle_speed="0.38",
    ),
    "cactus": material(
        saturation="1.24", brightness="1.06", roughness="0.8",
        translucency="0.06", region_albedo="0.3", rigidity="4.0",
        wind_sway="0.45", push_sway="1.5", max_bend="1.5",
    ),
    "lantern_plant": material(
        saturation="1.42", brightness="1.14", roughness="0.56",
        translucency="0.42", region_albedo="0.16", rigidity="1.8",
        calm_from="14.0", calm_to="44.0", wind_sway="9.0",
        wind_speed="0.86", gust_length="26.0", push_sway="30.0",
        max_bend="38.0",
        night_emission_color="Color(1, 0.86, 0.32, 1)",
        night_emission_energy="2.6", night_emission_albedo="0.7",
        night_pulse_amount="0.22", night_pulse_speed="0.3",
        night_twinkle_amount="0.72", night_twinkle_speed="1.35",
    ),
    "moth_perch": material(
        saturation="1.18", brightness="1.05", roughness="0.62",
        translucency="0.3", region_albedo="0.28", rigidity="2.0",
        wind_sway="10.0", wind_speed="0.78", gust_length="30.0",
        push_sway="34.0", max_bend="40.0",
        night_emission_color="Color(0.62, 0.5, 1, 1)",
        night_emission_energy="0.95", night_emission_albedo="0.85",
        night_pulse_amount="0.14", night_pulse_speed="0.42",
        night_twinkle_amount="0.4", night_twinkle_speed="0.9",
    ),
    "cactus_glow": material(
        saturation="1.35", brightness="1.08", roughness="0.76",
        translucency="0.08", region_albedo="0.25", rigidity="4.0",
        wind_sway="0.45", push_sway="1.5", max_bend="1.5",
        night_emission_color="Color(0.12, 0.72, 0.28, 1)",
        night_emission_energy="0.72", night_emission_albedo="0.68",
        night_pulse_amount="0.15", night_pulse_speed="0.11",
    ),
}


def species(
    name: str,
    model_name: str,
    material_name: str,
    **properties: object,
) -> dict[str, object]:
    return {
        "name": name,
        "model": model_name,
        "material": material_name,
        "properties": properties,
    }


def rock_species(
    name: str,
    model_name: str,
    material_name: str,
    **properties: object,
) -> dict[str, object]:
    # This generator cannot read CharacterDB; 1.6 m is the tallest playable body.
    properties["ground_sink_share"] = 0.18
    properties["ground_sink_above"] = 1.6
    return species(name, model_name, material_name, **properties)


# Ground enum: 1 grass, 2 sand, 3 stone, 4 ice.
# Collision enum: 0 cylinder, 1 sphere, 2 box, 3 convex hull, 4 trimesh.
# Impact enum: 0 solid, 1 breakable, 2 mushroom bounce, 3 unbreakable.
# Break-effect enum: 0 organic, 1 wood, 2 crystal.
# Toughness enum: 0 soft, 1 woody, 2 stone, 3 crystal. Health is the durability
# number and the run-through speed is derived from it, at twelve hit points per
# metre a second; toughness scales ability damage only, so a boulder can still
# be shouldered aside at eight metres a second while shrugging off a beam.
# The two catalogue grasses are deliberately sparse. GlobalGrass already lays
# the base lawn everywhere grass is painted; these are the taller seed heads and
# fans standing through it, so their density is a garnish on that field rather
# than a second one. Doubling the lawn here cost about forty per cent of the
# frame in temperate country for no visible gain.
SPECIES: list[dict[str, object]] = [
    species("kelp_ribbon", "kelp_ribbon", "seaweed",
        resource_name="RibbonKelp", height=4.4, height_variation=0.55,
        width_scale=1.15, tilt=16.0, above_water=-38.0, below=-5.0,
        max_slope=18.0, steady_over=2.4, steady_within=1.05,
        ground_layer=2, minimum_claim=0.04, per_square_metre=0.026,
        clump_count=2, clump_radius=1.2, bare_share=0.7, patch_size=48.0,
        random_seed=20261001, draw_within=230.0, thin_from=28.0,
        thin_to=105.0, far_density=0.055, shadow_within=0.0),
    species("sea_fan", "sea_fan", "seaweed_glow",
        resource_name="LuminousSeaFan", height=2.1, height_variation=0.45,
        width_scale=1.2, tilt=13.0, above_water=-34.0, below=-6.0,
        max_slope=20.0, steady_over=2.0, steady_within=0.95,
        ground_layer=2, minimum_claim=0.05, local_light_color="Color(0.65, 0.08, 1, 1)",
        local_light_energy=1.2, per_square_metre=0.013, clump_count=2,
        clump_radius=0.9, bare_share=0.77, patch_size=38.0,
        random_seed=20261002, draw_within=210.0, thin_from=26.0,
        thin_to=95.0, far_density=0.05, shadow_within=0.0),
    species("bulb_seaweed", "bulb_seaweed", "seaweed_glow",
        resource_name="BulbSeaweed", height=1.35, height_variation=0.52,
        width_scale=1.05, tilt=18.0, above_water=-30.0, below=-4.0,
        max_slope=22.0, steady_over=1.7, steady_within=0.82,
        ground_layer=2, minimum_claim=0.04, local_light_color="Color(0.04, 0.75, 1, 1)",
        local_light_energy=1.0, per_square_metre=0.032, clump_count=3,
        clump_radius=0.8, bare_share=0.56, patch_size=30.0,
        random_seed=20261003, draw_within=190.0, thin_from=24.0,
        thin_to=86.0, far_density=0.06, shadow_within=0.0),

    species("grass_feather", "grass_feather", "grass_variant",
        resource_name="FeatherGrass", height=0.72, height_variation=0.48,
        width_scale=1.35, tilt=13.0, above_water=7.0, below=260.0,
        max_slope=23.0, steady_over=1.5, steady_within=0.74,
        ground_layer=1, minimum_claim=0.035, maximum_arid=0.48,
        maximum_frost=0.58, terrain_tint=True, glowing_patches=0.12,
        glow_patch_size=34.0, glow_seed=20261101, per_square_metre=0.11,
        local_light_color="Color(0.34, 0.06, 0.78, 1)",
        local_light_energy=0.75,
        clump_count=3, clump_radius=1.0, bare_share=0.62, patch_size=72.0,
        random_seed=20261102, draw_within=165.0, thin_from=24.0,
        thin_to=78.0, far_density=0.07, shadow_within=0.0),
    species("grass_fan", "grass_fan", "grass_variant",
        resource_name="FanGrass", height=0.48, height_variation=0.42,
        width_scale=1.5, tilt=11.0, above_water=7.0, below=220.0,
        max_slope=24.0, steady_over=1.4, steady_within=0.7,
        ground_layer=1, minimum_claim=0.03, maximum_arid=0.55,
        maximum_frost=0.48, terrain_tint=True, glowing_patches=0.06,
        glow_patch_size=42.0, glow_seed=20261103, per_square_metre=0.15,
        local_light_color="Color(0.08, 0.48, 0.88, 1)",
        local_light_energy=0.65,
        clump_count=4, clump_radius=1.15, bare_share=0.48, patch_size=58.0,
        random_seed=20261104, draw_within=150.0, thin_from=22.0,
        thin_to=72.0, far_density=0.075, shadow_within=0.0),
    species("shrub_broadleaf", "shrub_broadleaf", "leaf",
        resource_name="BroadleafShrub", height=1.45, height_variation=0.5,
        width_scale=1.18, tilt=10.0, above_water=8.0, below=230.0,
        max_slope=25.0, steady_over=2.2, steady_within=1.0,
        ground_layer=1, minimum_claim=0.05, maximum_arid=0.4,
        maximum_frost=0.3, per_square_metre=0.018, clump_count=2,
        clump_radius=1.4, bare_share=0.68, patch_size=54.0,
        random_seed=20261201, draw_within=180.0, thin_from=32.0,
        thin_to=105.0, far_density=0.055, shadow_within=18.0,
        collision_enabled=False),
    species("shrub_heather", "shrub_heather", "heather_glow",
        resource_name="TwinklingHeather", height=0.78, height_variation=0.45,
        width_scale=1.3, tilt=12.0, above_water=9.0, below=280.0,
        max_slope=27.0, steady_over=1.9, steady_within=0.9,
        ground_layer=1, minimum_claim=0.04, maximum_arid=0.58,
        maximum_frost=0.55, local_light_color="Color(0.45, 0.035, 0.8, 1)",
        local_light_energy=1.0, per_square_metre=0.026, clump_count=3,
        clump_radius=1.1, bare_share=0.58, patch_size=42.0,
        random_seed=20261202, draw_within=170.0, thin_from=28.0,
        thin_to=94.0, far_density=0.05, shadow_within=0.0,
        collision_enabled=False),
    species("shrub_silver", "shrub_silver", "leaf",
        resource_name="SilverUplandShrub", height=1.05, height_variation=0.52,
        width_scale=1.1, tilt=14.0, above_water=20.0, below=340.0,
        max_slope=29.0, steady_over=2.1, steady_within=1.05,
        ground_layer=1, minimum_claim=0.035, minimum_arid=0.16,
        maximum_arid=0.72, maximum_frost=0.42, per_square_metre=0.014,
        clump_count=2, clump_radius=1.25, bare_share=0.65, patch_size=68.0,
        random_seed=20261203, draw_within=185.0, thin_from=34.0,
        thin_to=110.0, far_density=0.05, shadow_within=16.0,
        collision_enabled=False),

    species("tree_canopy", "tree_canopy", "tree",
        resource_name="CanopyTree", height=8.5, height_variation=0.52,
        width_scale=1.0, tilt=5.0, above_water=10.0, below=230.0,
        max_slope=18.0, steady_over=3.2, steady_within=1.25,
        ground_layer=1, minimum_claim=0.06, maximum_arid=0.34,
        maximum_frost=0.22, per_square_metre=0.0014, bare_share=0.45,
        patch_size=110.0, random_seed=20261301, draw_within=260.0,
        thin_from=90.0, thin_to=190.0, far_density=0.12,
        shadow_within=70.0, collision_enabled=True, collision_within=28.0,
        collision_radius_share=0.085, collision_height_share=0.84,
        impact_mode=1, health=180.0, health_per_metre=24.0, toughness=1,
        break_momentum_keep=0.7, break_effect=1,
        break_effect_color="Color(0.42, 0.2, 0.09, 1)"),
    species("tree_spiral", "tree_spiral", "tree_glow",
        resource_name="SpiralTree", height=10.5, height_variation=0.48,
        width_scale=0.95, tilt=4.0, above_water=24.0, below=340.0,
        max_slope=20.0, steady_over=3.4, steady_within=1.35,
        ground_layer=1, minimum_claim=0.055, maximum_arid=0.4,
        minimum_frost=0.0, maximum_frost=0.6,
        local_light_color="Color(0.12, 0.48, 1, 1)",
        local_light_energy=1.35, per_square_metre=0.0009,
        bare_share=0.55, patch_size=135.0, random_seed=20261302,
        draw_within=280.0, thin_from=100.0, thin_to=210.0,
        far_density=0.13, shadow_within=75.0, collision_enabled=True,
        collision_within=30.0, collision_radius_share=0.07,
        collision_height_share=0.9, impact_mode=1, health=192.0,
        health_per_metre=25.2, toughness=1, break_momentum_keep=0.65,
        break_effect=1, break_effect_color="Color(0.35, 0.22, 0.16, 1)"),
    species("tree_umbrella", "tree_umbrella", "tree",
        resource_name="UmbrellaTree", height=7.4, height_variation=0.5,
        width_scale=1.12, tilt=6.0, above_water=8.0, below=190.0,
        max_slope=19.0, steady_over=3.0, steady_within=1.2,
        ground_layer=1, minimum_claim=0.05, maximum_arid=0.52,
        maximum_frost=0.18, per_square_metre=0.0012, bare_share=0.5,
        patch_size=96.0, random_seed=20261303, draw_within=250.0,
        thin_from=85.0, thin_to=180.0, far_density=0.11,
        shadow_within=65.0, collision_enabled=True, collision_within=27.0,
        collision_radius_share=0.09, collision_height_share=0.82,
        impact_mode=1, health=168.0, health_per_metre=21.6, toughness=1,
        break_momentum_keep=0.74, break_effect=1,
        break_effect_color="Color(0.47, 0.25, 0.1, 1)"),
    # Cool, damp skywood: tall needles gather in tight clumps and overlap the
    # older spiral-tree range on uplands. The small primitive follows only the
    # narrow trunk; individual canopy leaves are intentionally non-colliding.
    species("tree_skyneedle", "tree_skyneedle", "tree",
        resource_name="SkyneedleTree", height=22.0, height_variation=0.46,
        width_scale=0.86, tilt=3.0, above_water=18.0, below=420.0,
        max_slope=15.0, steady_over=4.2, steady_within=1.55,
        ground_layer=1, minimum_claim=0.065, maximum_arid=0.34,
        minimum_frost=0.06, maximum_frost=0.58,
        per_square_metre=0.0065, clump_count=7, clump_radius=7.5,
        bare_share=0.58, patch_size=118.0, random_seed=20261304,
        draw_within=390.0, thin_from=125.0, thin_to=310.0,
        far_density=0.16, shadow_within=125.0,
        collision_enabled=True, collision_within=38.0,
        collision_radius_share=0.028, collision_height_share=0.94,
        impact_mode=1, health=240.0, health_per_metre=20.4, toughness=1,
        break_momentum_keep=0.48, break_effect=1,
        break_effect_color="Color(0.32, 0.22, 0.15, 1)"),
    # Humid lowland canopy: broad overlapping leaves make a true shadow roof.
    # Collision remains a cylinder around the trunk and stops below the crown.
    species("tree_cloudbough", "tree_cloudbough", "tree",
        resource_name="CloudboughTree", height=19.5, height_variation=0.52,
        width_scale=1.08, tilt=4.0, above_water=7.0, below=185.0,
        max_slope=14.0, steady_over=4.5, steady_within=1.65,
        ground_layer=1, minimum_claim=0.07, maximum_arid=0.25,
        maximum_frost=0.24, per_square_metre=0.00135,
        clump_count=3, clump_radius=13.0, bare_share=0.48,
        patch_size=142.0, random_seed=20261305, draw_within=420.0,
        thin_from=140.0, thin_to=330.0, far_density=0.17,
        shadow_within=170.0, collision_enabled=True,
        collision_within=44.0, collision_radius_share=0.062,
        collision_height_share=0.70, impact_mode=1, health=228.0,
        health_per_metre=21.6, toughness=1, break_momentum_keep=0.5,
        break_effect=1, break_effect_color="Color(0.38, 0.24, 0.12, 1)"),
    # Ancient giants use a broad habitat but an extremely sparse, high-bare
    # patch field, so they appear as solitary landmarks instead of forests.
    species("tree_orb_giant", "tree_orb_giant", "tree",
        resource_name="AncientOrbTree", height=42.0, height_variation=0.62,
        width_scale=1.0, tilt=2.5, above_water=16.0, below=480.0,
        max_slope=13.0, steady_over=6.0, steady_within=2.2,
        ground_layer=1, minimum_claim=0.08, maximum_arid=0.50,
        maximum_frost=0.48, per_square_metre=0.00011,
        bare_share=0.66, patch_size=270.0, random_seed=20261306,
        draw_within=610.0, thin_from=190.0, thin_to=500.0,
        far_density=0.24, shadow_within=240.0,
        collision_enabled=True, collision_within=58.0,
        collision_radius_share=0.145, collision_height_share=0.72,
        impact_mode=3),
    # Warm grass/sand ecotones get a playful luminous woodland that combines
    # with umbrella trees, fan grass and the first desert shrubs.
    species("tree_corkscrew", "tree_corkscrew", "tree_glow",
        resource_name="CorkscrewTree", height=14.0, height_variation=0.58,
        width_scale=1.02, tilt=7.0, above_water=9.0, below=270.0,
        max_slope=18.0, steady_over=3.5, steady_within=1.35,
        ground_layer=1, minimum_claim=0.055, minimum_arid=0.30,
        maximum_arid=0.68, maximum_frost=0.20,
        local_light_color="Color(0.12, 0.72, 0.58, 1)",
        local_light_energy=1.2, per_square_metre=0.00085,
        clump_count=2, clump_radius=8.0, bare_share=0.52,
        patch_size=154.0, random_seed=20261307, draw_within=350.0,
        thin_from=110.0, thin_to=270.0, far_density=0.14,
        shadow_within=105.0, collision_enabled=True,
        collision_within=36.0, collision_radius_share=0.075,
        collision_height_share=0.88, impact_mode=1, health=216.0,
        health_per_metre=22.8, toughness=1, break_momentum_keep=0.58,
        break_effect=1, break_effect_color="Color(0.27, 0.31, 0.18, 1)"),

    species("mushroom_cluster", "mushroom_cluster", "mushroom",
        resource_name="MushroomCluster", height=0.38, height_variation=0.48,
        width_scale=1.2, tilt=9.0, above_water=8.0, below=180.0,
        max_slope=24.0, steady_over=1.4, steady_within=0.72,
        ground_layer=1, minimum_claim=0.04, maximum_arid=0.32,
        maximum_frost=0.3, per_square_metre=0.055, clump_count=3,
        clump_radius=0.7, bare_share=0.55, patch_size=26.0,
        random_seed=20261401, draw_within=115.0, thin_from=20.0,
        thin_to=62.0, far_density=0.045, shadow_within=0.0,
        collision_enabled=True, collision_within=10.0,
        collision_primitive=1, collision_radius_share=0.7,
        collision_height_share=0.7, impact_mode=1, health=60.0,
        health_per_metre=6.0, break_momentum_keep=1.0,
        break_effect_color="Color(0.78, 0.3, 0.54, 1)"),
    species("mushroom_lantern", "mushroom_lantern", "mushroom_glow",
        resource_name="LanternMushroom", height=0.82, height_variation=0.5,
        width_scale=1.1, tilt=8.0, above_water=8.0, below=210.0,
        max_slope=24.0, steady_over=1.6, steady_within=0.78,
        ground_layer=1, minimum_claim=0.045, maximum_arid=0.38,
        maximum_frost=0.42, local_light_color="Color(0.08, 0.68, 1, 1)",
        local_light_energy=1.4, per_square_metre=0.022, clump_count=2,
        clump_radius=0.8, bare_share=0.45, patch_size=32.0,
        random_seed=20261402, draw_within=145.0, thin_from=24.0,
        thin_to=76.0, far_density=0.05, shadow_within=0.0,
        collision_enabled=True, collision_within=11.0,
        collision_primitive=1, collision_radius_share=0.62,
        collision_height_share=0.72, impact_mode=2, health=72.0,
        health_per_metre=7.8, break_momentum_keep=1.0,
        bounce_up_share=1.2, bounce_min_up=20.0, bounce_max_up=76.0,
        break_effect_color="Color(0.08, 0.68, 1, 1)"),
    species("mushroom_giant", "mushroom_giant", "mushroom_giant_glow",
        resource_name="GiantMushroom", height=6.2, height_variation=0.62,
        width_scale=1.05, tilt=7.0, above_water=10.0, below=190.0,
        max_slope=18.0, steady_over=3.0, steady_within=1.2,
        ground_layer=1, minimum_claim=0.06, maximum_arid=0.3,
        maximum_frost=0.28, local_light_color="Color(0.3, 0.08, 1, 1)",
        local_light_energy=1.8, per_square_metre=0.0007,
        bare_share=0.45, patch_size=88.0, random_seed=20261403,
        draw_within=230.0, thin_from=75.0, thin_to=165.0,
        far_density=0.1, shadow_within=55.0, collision_enabled=True,
        collision_within=24.0, collision_radius_share=0.11,
        collision_height_share=0.72, impact_mode=2, health=144.0,
        health_per_metre=10.8, break_momentum_keep=1.0,
        bounce_up_share=1.1, bounce_min_up=24.0, bounce_max_up=95.0,
        break_effect_color="Color(0.3, 0.08, 1, 1)"),

    species("firefly_lantern_plant", "firefly_lantern", "lantern_plant",
        resource_name="LanternPodPlant", height=1.15, height_variation=0.48,
        width_scale=1.05, tilt=11.0, above_water=8.0, below=200.0,
        max_slope=24.0, steady_over=1.8, steady_within=0.85,
        ground_layer=1, minimum_claim=0.045, maximum_arid=0.42,
        maximum_frost=0.34, local_light_color="Color(1, 0.82, 0.28, 1)",
        local_light_energy=1.6, per_square_metre=0.02, clump_count=2,
        clump_radius=0.9, bare_share=0.68, patch_size=36.0,
        random_seed=20261405, draw_within=150.0, thin_from=26.0,
        thin_to=82.0, far_density=0.05, shadow_within=0.0,
        collision_enabled=False),
    species("moth_perch_plant", "moth_glimmer", "moth_perch",
        resource_name="MothPerchPlant", height=1.05, height_variation=0.5,
        width_scale=1.0, tilt=13.0, above_water=8.0, below=340.0,
        max_slope=25.0, steady_over=1.9, steady_within=0.88,
        ground_layer=2, minimum_claim=0.05, minimum_arid=0.5,
        maximum_frost=0.2, local_light_color="Color(0.58, 0.46, 1, 1)",
        local_light_energy=0.9, per_square_metre=0.0055,
        bare_share=0.5, patch_size=58.0, random_seed=20261605,
        draw_within=160.0, thin_from=32.0, thin_to=98.0,
        far_density=0.05, shadow_within=0.0, collision_enabled=False),

    rock_species("rock_weathered", "rock_weathered", "rock",
        resource_name="WeatheredRock", height=1.4, height_variation=0.72,
        width_scale=1.35, tilt=18.0, above_water=0.5, below=460.0,
        max_slope=42.0, steady_over=2.0, steady_within=1.8,
        ground_layer=3, minimum_claim=0.06, maximum_frost=0.0,
        per_square_metre=0.008,
        clump_count=2, clump_radius=1.8, bare_share=0.45, patch_size=64.0,
        random_seed=20261501, draw_within=210.0, thin_from=55.0,
        thin_to=145.0, far_density=0.08, shadow_within=60.0,
        collision_enabled=True, collision_within=22.0,
        collision_primitive=3, impact_mode=1, health=60.0,
        health_per_metre=8.4, toughness=2, break_momentum_keep=0.88,
        break_effect=2, break_effect_color="Color(0.35, 0.32, 0.28, 1)"),
    rock_species("rock_basalt", "rock_basalt", "rock",
        resource_name="BasaltOutcrop", height=2.8, height_variation=0.68,
        width_scale=1.05, tilt=12.0, above_water=1.0, below=500.0,
        max_slope=38.0, steady_over=2.5, steady_within=2.0,
        ground_layer=3, minimum_claim=0.08, maximum_frost=0.0,
        per_square_metre=0.0026,
        clump_count=2, clump_radius=2.2, bare_share=0.45, patch_size=82.0,
        random_seed=20261502, draw_within=235.0, thin_from=70.0,
        thin_to=165.0, far_density=0.09, shadow_within=75.0,
        collision_enabled=True, collision_within=25.0,
        collision_primitive=3, impact_mode=1, health=72.0,
        health_per_metre=9.6, toughness=2, break_momentum_keep=0.84,
        break_effect=2, break_effect_color="Color(0.12, 0.11, 0.12, 1)"),
    species("glacier_shard", "glacier_shard", "ice_glow",
        resource_name="GlacierShard", height=5.0, height_variation=0.76,
        width_scale=1.1, tilt=15.0, above_water=2.0, below=520.0,
        max_slope=30.0, steady_over=3.0, steady_within=2.2,
        ground_layer=4, minimum_claim=0.08, minimum_frost=0.58,
        local_light_color="Color(0.08, 0.35, 1, 1)",
        local_light_energy=0.9, per_square_metre=0.0016,
        clump_count=2, clump_radius=3.2, bare_share=0.45, patch_size=110.0,
        random_seed=20261503, draw_within=285.0, thin_from=95.0,
        thin_to=215.0, far_density=0.11, shadow_within=90.0,
        collision_enabled=True, collision_within=28.0,
        collision_primitive=3, impact_mode=1, health=84.0,
        health_per_metre=12.0, toughness=3, break_momentum_keep=0.8,
        break_effect=2, break_effect_color="Color(0.35, 0.72, 1, 1)"),
    rock_species("ice_erratic", "rock_weathered", "rock",
        resource_name="PolarErratic", height=1.8, height_variation=0.78,
        width_scale=1.4, tilt=20.0, above_water=2.0, below=500.0,
        max_slope=28.0, steady_over=2.2, steady_within=1.7,
        ground_layer=4, minimum_claim=0.06, minimum_frost=0.62,
        per_square_metre=0.0035, clump_count=2, clump_radius=2.4,
        bare_share=0.4, patch_size=130.0, random_seed=20261504,
        draw_within=220.0, thin_from=65.0, thin_to=155.0,
        far_density=0.075, shadow_within=65.0, collision_enabled=True,
        collision_within=22.0, collision_primitive=3, impact_mode=1,
        health=72.0, health_per_metre=9.6, toughness=3,
        break_momentum_keep=0.86, break_effect=2,
        break_effect_color="Color(0.55, 0.65, 0.72, 1)"),
    # Broad-climate boulders are the baseline geology in every dry biome.
    # Clumps make a field read as a fall/deposit instead of evenly salted props.
    rock_species("boulder_round", "boulder_round", "rock",
        resource_name="RoundedBoulder", height=2.5, height_variation=0.35,
        width_scale=1.2, tilt=20.0,
        above_water=1.0, below=580.0,
        max_slope=42.0, steady_over=5.0, steady_within=3.5,
        maximum_frost=0.0,
        per_square_metre=0.00045, clump_count=4, clump_radius=7.0,
        bare_share=0.55, patch_size=105.0, random_seed=20261505,
        draw_within=340.0, thin_from=85.0, thin_to=250.0,
        far_density=0.12, shadow_within=110.0, collision_enabled=True,
        collision_within=38.0, collision_primitive=3, impact_mode=1,
        health=96.0, health_per_metre=13.2, toughness=2,
        break_momentum_keep=0.8, break_effect=2,
        break_effect_color="Color(0.36, 0.33, 0.28, 1)"),
    rock_species("boulder_layered", "boulder_layered", "rock",
        resource_name="LayeredBoulder", height=3.4, height_variation=0.4,
        width_scale=1.18, tilt=14.0, above_water=2.0, below=560.0,
        max_slope=34.0, steady_over=8.0, steady_within=5.5,
        minimum_arid=0.08, maximum_frost=0.0,
        per_square_metre=0.00016, clump_count=4, clump_radius=18.0,
        bare_share=0.66, patch_size=185.0, random_seed=20261506,
        draw_within=540.0, thin_from=150.0, thin_to=410.0,
        far_density=0.18, shadow_within=185.0, collision_enabled=True,
        collision_within=70.0, collision_primitive=3, impact_mode=1,
        health=108.0, health_per_metre=14.4, toughness=2,
        break_momentum_keep=0.72, break_effect=2,
        break_effect_color="Color(0.55, 0.38, 0.22, 1)"),
    rock_species("basalt_hex_field", "basalt_hex_field", "rock",
        resource_name="HexLavaFormation", height=4.0,
        height_variation=0.25, width_scale=1.12, tilt=5.0,
        above_water=3.0, below=540.0, max_slope=28.0,
        steady_over=12.0, steady_within=8.0, minimum_arid=0.32,
        maximum_frost=0.0, per_square_metre=0.00011,
        clump_count=3, clump_radius=26.0, bare_share=0.72,
        patch_size=240.0, random_seed=20261507, draw_within=720.0,
        thin_from=210.0, thin_to=560.0, far_density=0.22,
        shadow_within=240.0, collision_enabled=True,
        collision_within=90.0, collision_primitive=3, impact_mode=1,
        health=120.0, health_per_metre=15.6, toughness=2,
        break_momentum_keep=0.68, break_effect=2,
        break_effect_color="Color(0.12, 0.1, 0.09, 1)"),
    species("crystal_emerald", "crystal_emerald",
        "crystal_emerald_glow", resource_name="EmeraldCrystalCluster",
        height=15.0, height_variation=0.72, width_scale=1.04, tilt=8.0,
        above_water=3.0, below=560.0, max_slope=28.0,
        steady_over=10.0, steady_within=6.5, maximum_arid=0.62,
        maximum_frost=0.0, local_light_color="Color(0.08, 1, 0.4, 1)",
        local_light_energy=1.9, glow_patch_size=34.0,
        per_square_metre=0.00012, clump_count=4, clump_radius=22.0,
        bare_share=0.66, patch_size=210.0, random_seed=20261508,
        draw_within=680.0, thin_from=190.0, thin_to=530.0,
        far_density=0.2, shadow_within=210.0, collision_enabled=True,
        collision_within=82.0, collision_primitive=3, impact_mode=1,
        health=108.0, health_per_metre=14.4, toughness=3,
        break_momentum_keep=0.7, break_effect=2,
        break_effect_color="Color(0.08, 1, 0.4, 1)"),
    species("crystal_amethyst", "crystal_amethyst",
        "crystal_amethyst_glow", resource_name="AmethystCrystalCluster",
        height=22.0, height_variation=0.72, width_scale=1.0, tilt=9.0,
        above_water=4.0, below=570.0, max_slope=27.0,
        steady_over=13.0, steady_within=8.0, minimum_arid=0.08,
        minimum_frost=0.0, maximum_frost=0.0,
        local_light_color="Color(0.66, 0.12, 1, 1)",
        local_light_energy=2.1, glow_patch_size=42.0,
        per_square_metre=0.00012, clump_count=3, clump_radius=30.0,
        bare_share=0.72, patch_size=265.0, random_seed=20261509,
        draw_within=820.0, thin_from=245.0, thin_to=650.0,
        far_density=0.24, shadow_within=260.0, collision_enabled=True,
        collision_within=105.0, collision_primitive=3, impact_mode=1,
        health=120.0, health_per_metre=14.4, toughness=3,
        break_momentum_keep=0.66, break_effect=2,
        break_effect_color="Color(0.66, 0.12, 1, 1)"),
    rock_species("rune_boulder", "rune_boulder", "rune_boulder_glow",
        resource_name="TattooRuneBoulder", height=3.6,
        height_variation=0.35, width_scale=1.14, tilt=16.0,
        above_water=2.0, below=575.0, max_slope=34.0,
        steady_over=7.0, steady_within=4.8, maximum_frost=0.0,
        local_light_color="Color(0.68, 0.12, 1, 1)",
        local_light_energy=1.9, glow_patch_size=32.0,
        per_square_metre=0.000075, fractional_density=True,
        clump_count=5, clump_radius=22.0,
        bare_share=0.75, patch_size=280.0, random_seed=20261510,
        draw_within=620.0, thin_from=175.0, thin_to=490.0,
        far_density=0.2, shadow_within=180.0, collision_enabled=True,
        collision_within=65.0, collision_primitive=3, impact_mode=1,
        health=96.0, health_per_metre=13.2, toughness=2,
        break_momentum_keep=0.74, break_effect=2,
        break_effect_color="Color(0.68, 0.12, 1, 1)"),

    # This field remains site-forming, but rock members are capped at ordinary
    # boulder scale. Only the crystal and rune silhouettes remain monumental.
    rock_species("boulder_colossus", "boulder_colossus", "rock",
        resource_name="ColossalBoulderSite", height=3.8,
        height_variation=0.3, width_scale=1.1, tilt=7.0,
        above_water=12.0, below=540.0, max_slope=16.0,
        steady_over=30.0, steady_within=20.0, maximum_frost=0.0,
        per_square_metre=0.000007, fractional_density=True,
        clump_count=6, clump_radius=150.0, clump_resurvey=True,
        bare_share=0.93, patch_size=920.0, random_seed=20261511,
        draw_within=2200.0, thin_from=650.0, thin_to=1750.0,
        far_density=0.55, shadow_within=520.0, collision_enabled=True,
        collision_within=420.0, collision_primitive=3, impact_mode=3),
    rock_species("basalt_citadel", "basalt_citadel", "rock",
        resource_name="BasaltCitadel", height=4.0, height_variation=0.25,
        width_scale=1.02, tilt=3.0, above_water=14.0, below=525.0,
        max_slope=14.0, steady_over=36.0, steady_within=24.0,
        minimum_arid=0.38, maximum_frost=0.0,
        per_square_metre=0.000005, fractional_density=True,
        clump_count=4, clump_radius=220.0, clump_resurvey=True,
        bare_share=0.94, patch_size=1100.0, random_seed=20261512,
        draw_within=3000.0, thin_from=850.0, thin_to=2450.0,
        far_density=0.62, shadow_within=650.0, collision_enabled=True,
        collision_within=520.0, collision_primitive=3, impact_mode=3),
    species("crystal_spire", "crystal_spire", "crystal_spire_glow",
        resource_name="SkyCrystalSpire", height=190.0,
        height_variation=0.58, width_scale=1.0, tilt=4.0,
        above_water=10.0, below=550.0, max_slope=17.0,
        steady_over=32.0, steady_within=22.0, maximum_arid=0.88,
        maximum_frost=0.0,
        local_light_color="Color(0.06, 0.78, 1, 1)",
        local_light_energy=2.8, glow_patch_size=120.0,
        per_square_metre=0.000004, fractional_density=True,
        clump_count=3, clump_radius=170.0, clump_resurvey=True,
        bare_share=0.94, patch_size=1180.0, random_seed=20261513,
        draw_within=3200.0, thin_from=900.0, thin_to=2650.0,
        far_density=0.65, shadow_within=700.0, collision_enabled=True,
        collision_within=480.0, collision_primitive=3, impact_mode=3),
    rock_species("rune_monolith", "rune_monolith", "rune_monolith_glow",
        resource_name="RuneMonolithSite", height=105.0,
        height_variation=0.66, width_scale=1.0, tilt=6.0,
        above_water=9.0, below=560.0, max_slope=18.0,
        steady_over=24.0, steady_within=17.0, maximum_frost=0.0,
        local_light_color="Color(0.06, 1, 0.72, 1)",
        local_light_energy=2.6, glow_patch_size=90.0,
        per_square_metre=0.000006, fractional_density=True,
        clump_count=5, clump_radius=120.0, clump_resurvey=True,
        bare_share=0.93, patch_size=960.0, random_seed=20261514,
        draw_within=2300.0, thin_from=680.0, thin_to=1850.0,
        far_density=0.58, shadow_within=560.0, collision_enabled=True,
        collision_within=380.0, collision_primitive=3, impact_mode=3),

    species("cactus_barrel", "cactus_barrel", "cactus_glow",
        resource_name="GlowBarrelCactus", height=1.45, height_variation=0.6,
        width_scale=1.0, tilt=9.0, above_water=7.0, below=340.0,
        max_slope=22.0, steady_over=2.0, steady_within=0.9,
        ground_layer=2, minimum_claim=0.06, minimum_arid=0.55,
        maximum_frost=0.16, local_light_color="Color(0.08, 0.62, 0.22, 1)",
        local_light_energy=0.9, per_square_metre=0.0075,
        bare_share=0.45, patch_size=52.0, random_seed=20261601,
        draw_within=190.0, thin_from=48.0, thin_to=125.0,
        far_density=0.07, shadow_within=42.0, collision_enabled=True,
        collision_within=18.0, collision_radius_share=0.36,
        collision_height_share=0.8, impact_mode=1, health=120.0,
        health_per_metre=14.4, toughness=1, break_momentum_keep=0.82,
        break_effect_color="Color(0.1, 0.52, 0.2, 1)"),
    species("cactus_branching", "cactus_branching", "cactus",
        resource_name="BranchingCactus", height=3.6, height_variation=0.62,
        width_scale=1.0, tilt=8.0, above_water=8.0, below=380.0,
        max_slope=21.0, steady_over=2.5, steady_within=1.1,
        ground_layer=2, minimum_claim=0.065, minimum_arid=0.58,
        maximum_frost=0.14, per_square_metre=0.0022,
        bare_share=0.45, patch_size=72.0, random_seed=20261602,
        draw_within=230.0, thin_from=65.0, thin_to=155.0,
        far_density=0.08, shadow_within=58.0, collision_enabled=True,
        collision_within=22.0, collision_radius_share=0.16,
        collision_height_share=0.88, impact_mode=1, health=156.0,
        health_per_metre=18.0, toughness=1, break_momentum_keep=0.74,
        break_effect_color="Color(0.08, 0.45, 0.16, 1)"),
    species("joshua_tree", "joshua_tree", "tree",
        resource_name="JoshuaTree", height=7.2, height_variation=0.64,
        width_scale=1.0, tilt=7.0, above_water=9.0, below=390.0,
        max_slope=20.0, steady_over=3.0, steady_within=1.25,
        ground_layer=2, minimum_claim=0.07, minimum_arid=0.62,
        maximum_frost=0.12, per_square_metre=0.0008,
        bare_share=0.55, patch_size=120.0, random_seed=20261603,
        draw_within=270.0, thin_from=90.0, thin_to=195.0,
        far_density=0.1, shadow_within=70.0, collision_enabled=True,
        collision_within=26.0, collision_radius_share=0.09,
        collision_height_share=0.86, impact_mode=1, health=168.0,
        health_per_metre=24.0, toughness=1, break_momentum_keep=0.7,
        break_effect=1, break_effect_color="Color(0.43, 0.25, 0.12, 1)"),
    species("desert_silver_scrub", "shrub_silver", "leaf",
        resource_name="DesertSilverScrub", height=0.82, height_variation=0.56,
        width_scale=1.25, tilt=16.0, above_water=7.0, below=380.0,
        max_slope=24.0, steady_over=1.8, steady_within=0.85,
        ground_layer=2, minimum_claim=0.055, minimum_arid=0.64,
        maximum_frost=0.12, per_square_metre=0.016,
        clump_count=2, clump_radius=1.1, bare_share=0.4, patch_size=46.0,
        random_seed=20261604, draw_within=170.0, thin_from=38.0,
        thin_to=105.0, far_density=0.055, shadow_within=0.0,
        collision_enabled=False),
]


FIELDS = [
    {
        "name": "OceanPlants",
        "species": ["kelp_ribbon", "sea_fan", "bulb_seaweed"],
        "tile_size": 28.0, "survey_interval": 0.41, "push_reach": 2.8,
        "glow_light_limit": 4, "glow_light_range": 22.0,
        "glow_light_energy": 3.5, "glow_light_height": 1.0,
        "glow_light_night_only": True, "glow_light_use_region_color": False,
        "glow_light_color": "Color(0.1, 0.45, 1, 1)",
        "glow_light_pulse_amount": 0.1, "glow_light_pulse_speed": 0.19,
    },
    {
        "name": "TemperateFlora",
        "species": [
            "grass_feather", "grass_fan", "shrub_broadleaf",
            "shrub_heather", "shrub_silver", "mushroom_cluster",
            "mushroom_lantern", "firefly_lantern_plant",
        ],
        "tile_size": 26.0, "survey_interval": 0.37, "push_reach": 2.9,
        "clear_of": "NodePath(\"../../VacationersLanding\")", "keep_back": 190.0,
        "keep_back_fade": 1.8, "glow_light_limit": 3,
        "glow_light_range": 22.0, "glow_light_energy": 3.4,
        "glow_light_height": 0.65, "glow_light_night_only": True,
        "glow_light_use_region_color": False,
        "glow_light_color": "Color(0.3, 0.08, 0.9, 1)",
        "glow_light_pulse_amount": 0.16, "glow_light_pulse_speed": 0.31,
    },
    {
        "name": "ForestGiants",
        "species": [
            "tree_canopy", "tree_spiral", "tree_umbrella",
            "mushroom_giant",
        ],
        "tile_size": 42.0, "survey_interval": 0.47, "push_reach": 1.5,
        "clear_of": "NodePath(\"../../VacationersLanding\")", "keep_back": 220.0,
        "keep_back_fade": 1.7, "glow_light_limit": 3,
        "glow_light_range": 44.0, "glow_light_energy": 6.0,
        "glow_light_height": 5.0, "glow_light_night_only": True,
        "glow_light_use_region_color": False,
        "glow_light_color": "Color(0.16, 0.42, 1, 1)",
        "glow_light_pulse_amount": 0.15, "glow_light_pulse_speed": 0.16,
    },
    # These fields overlap TemperateFlora and ForestGiants. The species habitat
    # filters then form distinct combinations rather than parallel copies:
    # humid cloudbough+mushroom forest, cool skyneedle+spiral uplands, sparse
    # orb-tree clearings, and warm corkscrew+umbrella savanna.
    {
        "name": "SkywoodGroves",
        "species": ["tree_skyneedle", "tree_cloudbough"],
        "tile_size": 50.0, "survey_interval": 0.51, "push_reach": 1.2,
        "clear_of": "NodePath(\"../../VacationersLanding\")", "keep_back": 225.0,
        "keep_back_fade": 1.8,
    },
    {
        "name": "GiantOrbClearings",
        "species": ["tree_orb_giant"],
        "tile_size": 72.0, "survey_interval": 0.63, "push_reach": 0.0,
        "clear_of": "NodePath(\"../../VacationersLanding\")", "keep_back": 260.0,
        "keep_back_fade": 2.0,
    },
    {
        "name": "CorkscrewSavanna",
        "species": ["tree_corkscrew"],
        "tile_size": 48.0, "survey_interval": 0.49, "push_reach": 1.0,
        "clear_of": "NodePath(\"../../VacationersLanding\")", "keep_back": 215.0,
        "keep_back_fade": 1.7, "glow_light_limit": 2,
        "glow_light_range": 36.0, "glow_light_energy": 4.2,
        "glow_light_height": 4.2, "glow_light_night_only": True,
        "glow_light_use_region_color": False,
        "glow_light_color": "Color(0.12, 0.72, 0.58, 1)",
        "glow_light_pulse_amount": 0.13, "glow_light_pulse_speed": 0.18,
    },
    {
        "name": "PlanetGeology",
        "species": [
            "rock_weathered", "rock_basalt", "glacier_shard",
        ],
        "tile_size": 44.0, "survey_interval": 0.53, "push_reach": 0.0,
        "glow_light_limit": 2, "glow_light_range": 40.0,
        "glow_light_energy": 3.6, "glow_light_height": 2.5,
        "glow_light_night_only": True, "glow_light_use_region_color": False,
        "glow_light_color": "Color(0.08, 0.32, 1, 1)",
        "glow_light_pulse_amount": 0.05, "glow_light_pulse_speed": 0.12,
    },
    {
        "name": "BoulderGeology",
        "species": [
            "boulder_round", "boulder_layered", "basalt_hex_field",
        ],
        "tile_size": 100.0, "survey_interval": 0.55, "push_reach": 0.0,
        "clear_of": "NodePath(\"../../VacationersLanding\")", "keep_back": 130.0,
        "keep_back_fade": 1.6,
    },
    {
        "name": "CrystalGeology",
        "species": ["crystal_emerald", "crystal_amethyst"],
        "tile_size": 120.0, "survey_interval": 0.57, "push_reach": 0.0,
        "clear_of": "NodePath(\"../../VacationersLanding\")", "keep_back": 180.0,
        "keep_back_fade": 1.7, "glow_light_limit": 4,
        "glow_light_range": 110.0, "glow_light_energy": 8.5,
        "glow_light_height": 7.0, "glow_light_night_only": False,
        "glow_light_use_region_color": False,
        "glow_light_color": "Color(0.18, 0.8, 1, 1)",
        "glow_light_pulse_amount": 0.08, "glow_light_pulse_speed": 0.13,
    },
    {
        "name": "RuneGeology",
        "species": ["rune_boulder"],
        "tile_size": 130.0, "survey_interval": 0.59, "push_reach": 0.0,
        "clear_of": "NodePath(\"../../VacationersLanding\")", "keep_back": 160.0,
        "keep_back_fade": 1.7, "glow_light_limit": 3,
        "glow_light_range": 90.0, "glow_light_energy": 7.5,
        "glow_light_height": 4.0, "glow_light_night_only": True,
        "glow_light_use_region_color": False,
        "glow_light_color": "Color(0.68, 0.12, 1, 1)",
        "glow_light_pulse_amount": 0.1, "glow_light_pulse_speed": 0.17,
    },
    {
        "name": "GiantBoulderSites",
        "species": [
            "boulder_colossus", "basalt_citadel",
            "crystal_spire", "rune_monolith",
        ],
        "tile_size": 420.0, "survey_interval": 0.74, "push_reach": 0.0,
        "clear_of": "NodePath(\"../../VacationersLanding\")", "keep_back": 650.0,
        "keep_back_fade": 1.5, "glow_light_limit": 5,
        "glow_light_range": 320.0, "glow_light_energy": 16.0,
        "glow_light_height": 24.0, "glow_light_night_only": False,
        "glow_light_use_region_color": False,
        "glow_light_color": "Color(0.08, 0.82, 0.9, 1)",
        "glow_light_pulse_amount": 0.07, "glow_light_pulse_speed": 0.1,
    },
    {
        "name": "DesertFlora",
        "species": [
            "cactus_barrel", "cactus_branching", "joshua_tree",
            "desert_silver_scrub", "moth_perch_plant",
        ],
        "tile_size": 38.0, "survey_interval": 0.43, "push_reach": 1.3,
        "glow_light_limit": 2, "glow_light_range": 30.0,
        "glow_light_energy": 3.6, "glow_light_height": 1.1,
        "glow_light_night_only": True, "glow_light_use_region_color": False,
        "glow_light_color": "Color(0.08, 0.58, 0.2, 1)",
        "glow_light_pulse_amount": 0.11, "glow_light_pulse_speed": 0.11,
    },
]


def godot_value(value: object) -> str:
    if isinstance(value, bool):
        return "true" if value else "false"
    if isinstance(value, float):
        return repr(value)
    if isinstance(value, int):
        return str(value)
    if isinstance(value, str):
        if value.startswith(("Color(", "Vector", "NodePath(", "ExtResource(")):
            return value
        return json.dumps(value)
    raise TypeError(f"unsupported Godot value {value!r}")


def write(path: Path, text: str) -> None:
    path.parent.mkdir(parents=True, exist_ok=True)
    path.write_text(text.rstrip() + "\n", encoding="utf-8", newline="\n")


def build_materials() -> None:
    for name, parameters in MATERIALS.items():
        lines = [
            "[gd_resource type=\"ShaderMaterial\" load_steps=2 format=3]",
            "",
            f"[ext_resource type=\"Shader\" path=\"{SHADER}\" id=\"1_shader\"]",
            "",
            "[resource]",
            f"resource_name = {json.dumps('Biome ' + name.replace('_', ' ').title())}",
            "shader = ExtResource(\"1_shader\")",
        ]
        lines.extend(
            f"shader_parameter/{key} = {value}"
            for key, value in parameters.items()
        )
        write(OUTPUT_DIR / f"{name}.tres", "\n".join(lines))


def build_species(check_assets: bool) -> None:
    for entry in SPECIES:
        name = str(entry["name"])
        model_name = str(entry["model"])
        material_name = str(entry["material"])
        model_disk = (
            PROJECT_DIR / "assets" / "runtime" / "biomes" / "models"
            / f"{model_name}.glb"
        )
        paint_disk = (
            PROJECT_DIR / "assets" / "runtime" / "biomes" / "paint"
            / f"{model_name}_paint.png"
        )
        if check_assets and not model_disk.exists():
            raise FileNotFoundError(model_disk)
        if check_assets and not paint_disk.exists():
            raise FileNotFoundError(paint_disk)
        lines = [
            "[gd_resource type=\"Resource\" script_class=\"PlantSpecies\" "
            "load_steps=5 format=3]",
            "",
            f"[ext_resource type=\"Script\" path=\"{SPECIES_SCRIPT}\" id=\"1_species\"]",
            f"[ext_resource type=\"PackedScene\" path=\"{MODEL_ROOT}/{model_name}.glb\" id=\"2_model\"]",
            f"[ext_resource type=\"Material\" path=\"res://game/props/biomes/{material_name}.tres\" id=\"3_material\"]",
            f"[ext_resource type=\"Texture2D\" path=\"{PAINT_ROOT}/{model_name}_paint.png\" id=\"4_paint\"]",
            "",
            "[resource]",
            "script = ExtResource(\"1_species\")",
            "model = ExtResource(\"2_model\")",
            "material = ExtResource(\"3_material\")",
            "paint_texture = ExtResource(\"4_paint\")",
        ]
        for key, value in dict(entry["properties"]).items():
            lines.append(f"{key} = {godot_value(value)}")
        write(OUTPUT_DIR / f"{name}.tres", "\n".join(lines))


def build_scene() -> None:
    by_name = {str(entry["name"]): entry for entry in SPECIES}
    used = []
    for field in FIELDS:
        for name in field["species"]:
            if name not in by_name:
                raise KeyError(f"unknown species {name}")
            if name not in used:
                used.append(name)
    ext_ids = {name: f"{index + 3}_{name}" for index, name in enumerate(used)}
    lines = [
        f"[gd_scene load_steps={len(used) + 4} format=3]",
        "",
        "[ext_resource type=\"Script\" path=\"res://game/props/ground_cover.gd\" id=\"1_cover\"]",
        f"[ext_resource type=\"Script\" path=\"{SPECIES_SCRIPT}\" id=\"2_species\"]",
        "[ext_resource type=\"Script\" path=\"res://game/props/global_flora_glow.gd\" id=\"99_global_glow\"]",
    ]
    lines.extend(
        f"[ext_resource type=\"Resource\" path=\"res://game/props/biomes/{name}.tres\" id=\"{ext_ids[name]}\"]"
        for name in used
    )
    lines.extend([
        "",
        "[node name=\"BiomePopulations\" type=\"Node3D\"]",
        "script = ExtResource(\"99_global_glow\")",
    ])
    for field in FIELDS:
        lines.extend([
            "",
            f"[node name=\"{field['name']}\" type=\"Node3D\" parent=\".\"]",
            "script = ExtResource(\"1_cover\")",
            "direction = Vector3(-0.2881049, -0.1121179, 0.9510127)",
            "species = Array[ExtResource(\"2_species\")]([{}])".format(
                ", ".join(
                    f"ExtResource(\"{ext_ids[name]}\")"
                    for name in field["species"]
                )
            ),
            "global_cover = true",
            "wind_heading = 35.0",
            "pending_limit = 1",
            "applies_per_frame = 1",
        ])
        for key, value in field.items():
            if key in {"name", "species"}:
                continue
            lines.append(f"{key} = {godot_value(value)}")
    write(OUTPUT_DIR / "biome_populations.tscn", "\n".join(lines))


def main() -> None:
    parser = argparse.ArgumentParser()
    parser.add_argument(
        "--project-dir", type=Path, default=PROJECT_DIR,
        help="kept for build-orchestrator compatibility; current script is repo-local",
    )
    parser.add_argument(
        "--no-check-assets", action="store_true",
        help="emit resources before the Blender geometry build exists",
    )
    # Blender keeps its own CLI switches in sys.argv. Arguments after `--` belong
    # to this script; direct Python invocation has no separator.
    if "--" in sys.argv:
        argv = sys.argv[sys.argv.index("--") + 1:]
    elif Path(sys.argv[0]).stem.lower().startswith("blender"):
        # Blender's own switches are still present when a caller omits the
        # separator. Treat them as no catalogue arguments rather than handing
        # --background/--python to argparse.
        argv = []
    else:
        argv = sys.argv[1:]
    args = parser.parse_args(argv)
    if args.project_dir.resolve() != PROJECT_DIR.resolve():
        raise ValueError("this catalogue currently emits into its own repository")
    build_materials()
    build_species(not args.no_check_assets)
    build_scene()
    print(
        f"wrote {len(MATERIALS)} materials, {len(SPECIES)} species and "
        f"{len(FIELDS)} streamed fields under {OUTPUT_DIR}"
    )


if __name__ == "__main__":
    main()
