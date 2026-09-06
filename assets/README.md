# Asset pipeline

`assets/` separates editable inputs from files Godot loads at runtime. Do not
put runtime resources under `source/` or `work/`; both are hidden from Godot by
`.gdignore`.

## Layout

- `source/blender/` contains Blender Python recipes, shared helpers, the authored
  astronaut `.blend`, and title-art source.
- `source/meshmaker/` contains read-only MeshMaker `.blend` inputs. Builders may
  open them but must never save over them.
- `source/texture_inputs/` contains source sheets used to bake terrain textures.
- `runtime/characters/`, `runtime/apparel/`, `runtime/items/` and
  `runtime/environment/` contain directly loaded models and character textures.
- `runtime/biomes/models/` and `runtime/biomes/paint/` contain the model/PNG
  pairs used by `PlantSpecies`.
- `runtime/cities/models/` and `runtime/cities/paint/` contain authored building
  GLBs and ten facade paints each. These are not wired into `PatchCity` yet.
- `runtime/biomes/manifests/` records provenance, authored size, triangle
  budgets, collision hints, color-paint paths and paint styles.
- `runtime/vat/` keeps each VAT mesh, EXR and JSON bundle together.
- `runtime/materials/meshmaker/` contains the external materials used by direct
  MeshMaker scenery imports.
- `work/` contains regenerable intermediate `.blend` files.
- `previews/` contains regenerable authoring and biome renders. It is ignored by
  Git and is not a runtime asset source.

## Regeneration

Run commands from the repository root with Blender 5.1:

```powershell
$blender = "C:\Program Files\Blender Foundation\Blender 5.1\blender.exe"

# Characters and apparel
& $blender --background --factory-startup --python assets/source/blender/build_character.py
& $blender --background --python assets/source/blender/build_character_3.py
# Mixamo clips onto the settler skeleton (also runs at the end of the line above)
& $blender --background --factory-startup --python assets/source/blender/merge_m2m_animations.py
& $blender --background --factory-startup --python assets/source/blender/build_bigfoot.py
& $blender --background assets/source/blender/player_character.blend --python assets/source/blender/build_apparel.py

# Bigfoot authoring previews (run after its build)
& $blender --background assets/work/bigfoot_rigged.blend --python assets/source/blender/render_bigfoot_previews.py

# Procedural biome library and Godot catalogue
& $blender --background --factory-startup --python assets/source/blender/build_biome_assets.py
& $blender --background --factory-startup --python assets/source/blender/build_flower_tree.py
& $blender --background --factory-startup --python assets/source/blender/build_biome_catalog.py

# Rigged land fauna (skin-tree creatures + catalogue)
& $blender --background --factory-startup --python assets/source/blender/build_fauna_creatures.py
& $blender --background --factory-startup --python assets/source/build_fauna_catalog.py

# MeshMaker processing
& $blender --background --factory-startup --python assets/source/blender/build_landing.py
& $blender --background --factory-startup --python assets/source/blender/build_reef_assets.py
& $blender --background --factory-startup --python assets/source/blender/build_vat_assets.py

# Terrain texture arrays and title art
& $blender --background --factory-startup --python assets/source/blender/build_ground_textures.py
& $blender --background --factory-startup --python assets/source/blender/build_title_art.py

# Authored city buildings (GLB + ten night-window paints each)
& $blender --background --factory-startup --python assets/source/blender/build_city_buildings.py

# Walk-in civic specials (interior + exterior, then merged into buildings.json)
& $blender --background --factory-startup --python assets/source/blender/build_city_specials.py

# Five colour paints for each old procedural lot mass (rect, gable, taper…)
& $blender --background --factory-startup --python assets/source/blender/build_city_variants.py
```

The catalogue builder can also run with a normal Python interpreter because it
does not import `bpy`.

## Bigfoot boss character

`source/meshmaker/bigfoot.blend` is read-only. `build_bigfoot.py` hashes it
before and after every run, then writes the regenerable rigged file to
`work/bigfoot_rigged.blend` and the Godot asset to
`runtime/characters/bigfoot.glb`.

The recipe turns the source to Blender +Y/Godot -Z, scales and grounds it at
3.2 m, decimates 52,518 source triangles to 30,000, preserves the corner-domain
`Color` attribute as `COLOR_0`, and remaps the useful MeshMaker weights onto the
23-bone project skeleton. `LeftHand` and `RightHand` are real weighted bones,
not empty sockets, so `BoneAttachment3D` nodes can target them later.

The NLA clips are `Idle`, `Walk`, `Run`, `Roar`, `MeteorWindup`, `MeteorFly`,
`MeteorImpact`, `Punch`, `Grab`, `Throw`, `HitReact`, and `Defeat`. Idle, Walk,
Run, and MeteorFly have duplicate wrap keys for seamless looping; glTF itself
does not store a loop flag, so an eventual AnimationTree must configure those
states as loops.

After the export-safe GLB is written, the recipe adds the editable Layer Weight
→ Color Ramp → Emission → Mix Shader camera-rim graph to
`work/bigfoot_rigged.blend` and saves the work file again. Godot renders its
runtime equivalent with `game/enemies/bigfoot/bigfoot_surface.tres`.

Godot 4.7 has a confirmed glTF regression that imports `COLOR_0` but does not
automatically enable it on the generated material. The checked-in
`bigfoot.glb.import` maps `BigfootVertexColor` to the existing linear
`MeshMakerSurface.tres`; keep that remap as the import-safe fallback.
`BigfootBoss` then applies `bigfoot_surface.tres`, whose `use_vertex_color`
setting preserves the authored fur, face, horn, and eye colors while adding the
camera rim.

After rebuilding, import and validate it with:

```powershell
godot --headless --path . --editor --quit
godot --headless --path . --script dev/_check_bigfoot.gd
```

## Flora and fauna contract

Population assets are deterministic recipes rather than individually placed
scene nodes. Dense and medium populations use streamed `GroundCover` tiles and
one `MultiMesh` per species/tile; moving life uses bounded MultiMesh clusters
with shader or VAT motion.

The shared organic camera rim is implemented in `vivid_plant`, `vivid_fish`,
`vivid_swarm`, and `vivid_night_phenomena`; rigid flower trees enable the same
parameters on `vivid_surface`. It uses Character 3's neon-green Color Ramp
thresholds, with reduced emission on thin instanced growth so fields gain an
edge without turning into an emissive carpet.

Every flora, fungus, coral, geological growth and small-creature variant must:

1. Export a grounded, gameplay-ready GLB with `TEXCOORD_0` UVs and retained
   `COLOR_0` semantic data.
2. Have a deterministic external PNG under `runtime/biomes/paint/`.
3. Record that PNG and its species-appropriate paint style in the manifest.
4. Bind the PNG through its `PlantSpecies` resource and runtime material.
5. Preserve biome tint, night-emission masks, VAT data, collision hints and
   MultiMesh batching.

Paint patterns must be broad and mip-safe: bark bands and knots, leaf veins and
margins, petal markings, mushroom spots and gills, grass streaks, coral
striations, cactus ribs and areoles, rock strata and lichen, or creature
markings. Avoid single-pixel noise and thin high-contrast lines that shimmer at
gameplay distance.

Species remain biome-specific. Habitat checks combine terrain material claims,
aridity, frost, elevation, slope and steadiness. Shrubs, grass, small mushrooms,
seaweed and small stones do not collide; trunked trees, giant mushrooms, stout
cacti, large rocks, crystal spires and glacier shards use streamed primitive
collision near the viewer. Emissive species submit candidates to bounded local
light pools rather than creating one light per instance.

Rock instances taller than the 1.6 m playable body are buried by 18% of their
generated height. The relative sink reaches both the MultiMesh and its streamed
collision, closing the gap a wide rock would otherwise bridge over curved ground.

After changing a recipe, validate the GLB/PNG/manifest contract, Godot imports,
representative biome counts, and both a close preview and a normal
gameplay-distance view.
