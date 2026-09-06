# Godot Co-op Template

A reusable Godot 4.7 starter for offline play and Steam player-hosted online co-op. It includes a responsive colored-pencil menu, persistent settings, Steam lobby discovery and friend invites, relay-backed multiplayer, a networked test world, an animated first/third person character controller, inventory-based apparel and weapons, and text and push-to-talk voice chat.

This file explains how each system works and why. Asset provenance, regeneration commands and runtime contracts are documented in `assets/README.md`.

## Run it

Open `project.godot` in Godot 4.7 and press **F6/F5**.

- **Start Game** launches the world with an offline multiplayer peer.
- **Online > Create Lobby** creates a public, friends-only, or password-protected Steam lobby, then opens its waiting room.
- **Online > Join Lobby** searches Steam sessions by name and game mode. Steam friend invites enter through the same screen; no IP address is exposed.
- Press **Escape** in the world to resume or leave.

Controls:

| Input | Action |
| --- | --- |
| WASD, mouse | Move and look |
| Space | Jump, with coyote time and input buffering. Pressed again in clear air, take off and fly |
| Shift | Sprint, or boost a flight to over 200 m/s |
| Ctrl | Crouch, or slide when held while already moving. Brake, while flying |
| C | Cycle first person, third person close, third person far |
| Q | Swap the camera to the other shoulder |
| E | Use whatever the crosshair is on, within arm's reach |
| Tab | Open your inventory, from anywhere |
| 1 - 5, wheel | Draw a weapon. Numbers reach any slot, the wheel only stops on filled ones |
| Left click | Swing the sword, or fire the carbine |
| Right click, held | Sight down the carbine's optic |
| Enter | Type a line of chat; Enter again sends it, Escape throws it away |
| V, held | Talk to everyone in the session |
| Escape | Pause |

While flying, the mouse is the steering: hold forward and you go wherever you are looking, including straight down. There is no cancel key: ground ends a flight, while entering the sea hands it directly to swimming and carries 85% of the arrival speed into the water. The separate two-press launch from swimming remains a flight under water until it reaches the air. Space climbs. The controls and the current speed are on a card in the bottom-left corner for as long as the feet are off the ground.

**Tab** opens your inventory anywhere: what you are wearing, a live model of it, your numbered hotbar, and your pockets. Drag a garment onto a body slot to put it on, or shift-click it to send it straight to the slot it belongs in. Weapons and usable items go to the hotbar that the HUD mirrors. Hovering a tile names the item and describes it.

Sensitivity, invert-Y, and FOV can be changed under **Settings > Gameplay** and are saved in `user://settings.cfg`. Ledges up to about shin height are stepped over automatically; see `step_height` in `game/player/player.gd`.

## Test Steam multiplayer

The project includes GodotSteam 4.21 GDExtension for Windows x64. Steam must be running and the testing accounts must have access to **My Strange Planet Playtest (5098060)**.

1. Sign into two different Steam accounts on separate machines or VMs.
2. Start a Playtest build on both.
3. Create a lobby on one machine, then either find it under **Join Lobby** or press **Invite Steam Friends**.
4. For a private lobby, the joining player is admitted to the game roster only after the host verifies the password.
5. The host presses **Start** after the roster is ready.

Steam supplies discovery, NAT traversal, and relay routing; one player's game remains the authoritative host. Valve is not running the world simulation as a dedicated server.

Development selects the Playtest ID with `steam/initialization/app_data/app_type=2` in `project.godot`. Change that App Type to `0` for the full store application **5098010**. Export with the normal Godot Windows templates; the GDExtension package carries the Steam runtime DLL.

## Optional local headless transport test

Godot can start a local host without navigating the menus:

```powershell
godot --headless --path . -- --server --port=7777 --max-players=8 --lobby-name="Local Test"
```

Replace `godot` with the full path to your Godot 4.7 executable if it is not on `PATH`. Stop the server with Ctrl+C. This hidden ENet path exists only for automated two-process chat checks. It is not used by the Online menu.

Add `--private --lobby-code=YOURCODE` to exercise host-side admission in that local harness. Steam lobby passwords likewise stay out of lobby metadata and are checked by the host before a player is registered.

## Customize the template

- UI control styling, spacing, and typography: `ui/themes/main_theme.tres`. The menus are drawn by the same colored-pencil shader as the world, so the theme deliberately leaves the styleboxes empty for the surfaces `ui/themes/pencil_surface.gd` paints; see `shaders/pencil/README.md`.
- Menu color tokens, i.e. the surfaces and the things drawn on them: `ui/themes/ui_palette.tres`. Five colors run the whole UI: Midnight Violet `#2d1e2f` is every panel, Vanilla Custard `#fcf6b1` is the type on those panels and the ring around whatever holds focus, Sunflower Gold `#f7b32b` is the default action of a screen and the color of its headings, Celadon `#a9e5bb` is every other button, and Burnt Tangerine `#e3170a` is reserved for leaving and for failing. The remaining tones — card and row sheets, secondary and muted type — are mixes of the first two, so recoloring the UI means editing those five and letting the mixes follow. Note that `main_theme.tres` cannot read the tokens and repeats them as floats, and that it owns the tab, popup, slider, and scrollbar fills as ordinary style boxes.

  The scheme is dark-surface, and it is held together by one rule: a control is never the color of the surface behind it. Panels are violet with custard type; buttons are filled with one of the bright colors and carry violet type. Hover and press shade a fill further in without changing its hue, so color says what a thing *is* and shading says what state it is in.
- Typeface: `fonts/Bungee-Regular.ttf`, set as the theme's default font and as `[gui] theme/custom_font` so anything outside the theme matches. It is imported with antialiasing, hinting, and subpixel positioning on. The size ladder is 15–17 for captions and dense in-game panels, 26 for body, 28 for buttons, and 32–64 for headings; swapping faces still requires checking those sizes because cap heights differ.
- Game title, drawn top left of the home screen: `title` under `[game]` in `project.godot`
- Home screen, camera poses and the hand-over into gameplay: `ui/menu/home_screen.gd`; the forms it puts up are `ui/menu/settings_panel.gd` and `ui/menu/lobby_panel.gd`
- Settings defaults and persistence: `core/settings_manager.gd`
- Test world: `game/world.tscn`. The round props deliberately collide as straight-sided cylinders: art that curves in under itself overhangs the player's feet, and a capsule character wedges under that instead of sliding off it.
- Alien-tech formations: `game/props/tech_formation_sites.gd` owns five deterministic 1.4 km-wide fields, including the north-pole floe. Each contains 36 instances ranging from the original room-sized shards to 300 m fragments, all from the one 562-panel mesh owned by `assets/source/blender/build_tech_fragment.py`; `game/props/tech_formation.tres` owns their reflective magenta/turquoise film. The five fields and the four tallest natural summits are orbital-range waypoints.
- Player tuning: exported values in `game/player/player.gd`, including the whole `Flight` group
- Items and their descriptions: `ItemDB.ITEMS` in `game/items/item_db.gd`
- Starter apparel and weapons: `STARTER_INVENTORY_REVISION` and `ensure_starter_inventory()` in `game/player/character_db.gd`
- Chat pacing, length limit and scrollback: constants in `core/chat_manager.gd`; the panel's size and how long it lingers: `ui/chat/chat_hud.gd`
- Voice bandwidth against quality: `RATE`, `PACKET_SAMPLES` and `PREBUFFER` in `core/voice_chat.gd`
- Colored pencil material and its test bed: `shaders/pencil/README.md`
- Player character proportions: section tables in `assets/source/blender/build_character.py`
- Character animation: pose tables in `assets/source/blender/build_animations.py`, arms via `arm_hang`
- How a weapon is held, and the swing: `HOLDS` and `SWING` in `game/player/weapon_pose.gd`

The settings file is intentionally stored outside the project at `user://settings.cfg`. Use **Reset Defaults** to restore template values.

## City patches

The planet is cut into neighbourhood-scale territories — the first layer of city building. Tilde (the navigation overlay) draws their borders on the ground and writes each territory's name at its centre, like country names on a globe. Waypoints and the coordinate plate stay up with them.

`game/city/land_partition.gd` owns the cut. `game/city/land_patch_overlay.gd` draws it. The partition is an icosphere Voronoi restricted to **buildable land**: above the waterline, outside the ice caps, outside the south-pole volcano, and clear of the four Giant Mountain sites. Neighbouring patches share an edge, so there is no empty dry ground between them. Ocean, ice, lava and those mountain sites are holes, not leftover land.

Chicago is about 40 km by 25 km. This globe is 8 km in radius (equator ~50 km), so a Chicago will not fit. The patches are neighbourhood-scale territories on this world: about 1.3 km across, tiling every shore that can take a city. Typical width is `target_span` on the overlay node. About ten to fifteen of them fit in one of the earlier 4.5 km cells.

Borders between two territories are the spherical perpendicular bisector of their seeds — a single well-defined geodesic, draped onto the hills every few metres. `LandPartition.owner_at()` returns which patch a direction belongs to. Coastline against water, ice, or lava follows the waterline on the same mesh.

With the tilde map up, look at a patch and press E to found its city. `game/city/patch_city_generator.gd` lays the city road first: a closed race loop around the whole territory, sometimes a circle, sometimes a flower. Districts are seated after that, inside and outside the road. The first draw is opaque district tiles and the dark grey loop, with no collision. Press E again on the same patch to pave it: the loop becomes a graded highway with collision, off-ramps from the highway into nearby districts, and the districts become solid coloured ground just above the terrain, clearing flora. Internal streets come later.

```powershell
godot --headless --path . dev/_land_patch_test.tscn
godot --headless --path . dev/_patch_city_test.tscn
```

## Flight

Press space in mid-air and the character takes off: it hovers upright with one knee drawn up, steers wherever the camera is pointing, climbs on space, and winds up past 200 m/s on a held shift while the body goes over from that hover into a flat-out flying line. Ctrl hauls it back down again. `dev/_player_test.tscn -- --flight` runs the whole arc and writes each pose to `dev/captures/`.

Flight is a fourth `Stance`, not a flag beside the other three. That one decision pays for most of the feature: the stance is already synced to every peer and already indexes the collider and eye-height tables, so a remote player animates and leans correctly with nothing added to the wire, and the host already knows which stance a submitted packet claims to be in. It borrows the standing capsule, which is why taking off and landing never have to ask whether there is room the way standing up out of a crouch does.

Four things are worth knowing before retuning it.

**The boost is a target, not an acceleration.** `_cruise` is the speed the player is asking for; `boost_time`, `ease_time` and `brake_time` move it across the whole range, and the velocity chases it with an acceleration that grows with it. Keeping the two apart is what lets the boost read as a long wind-up while a turn at 200 m/s stays a wide arc and a turn at hovering speed stays a pivot. Steering comes off the **camera's** basis rather than the body's, so looking down and holding forward is a dive; only the head pitches, so the camera's own X stays level and a strafe never rolls the flight path.

**The lean is the animation.** The two clips only cover the ends; everything between them is `character.rotation.x`, driven by one smoothed `_fly_blend` that also opens the field of view and picks the clip. It turns about the hips rather than the feet, because pitching about the feet would swing the head most of a body length forward and bury the shoulders. Pointed straight up, the same formula stands the body back upright; straight down, it goes head first.

**Water entry is a momentum handoff.** A flight arriving from the air changes to `SWIM` as soon as it is clearly through the surface, keeps `swim_entry_keep` of its velocity in the same direction, and lets the ordinary water drag slow it from there. The stroke target and swim lean are seeded from that carried speed, so the body starts in `Swim` rather than briefly standing upright in `Tread`. A flight deliberately launched by double-pressing space while swimming is exempt until it clears the sea; once airborne, its next entry becomes a swim normally.

**Space in clear air and space about to land are the same press.** The jump buffer exists to catch a press made just before touchdown, and a take-off would eat exactly those presses, so take-off additionally requires `TAKEOFF_CLEARANCE` of clear air below the feet. Under a metre, space is still asking to jump on landing. `dev/_player_test.gd` checks both halves, because getting one right silently breaks the other.

Two limits are deliberate. The host's teleport check and speed clamp are worked out from the stance in the packet, so a flying player is allowed the hundred-odd metres they can honestly cover between two 20 Hz updates — which means the ceiling on a client lying about its position is that much higher while it claims to be flying. And remote players are now dead-reckoned forward on their last known velocity for up to two packets, because sitting on a 50 ms-old position leaves a flying peer a building behind; a peer that goes quiet coasts to a stop rather than flying off on its last heading.

The test world's floor is 32 m across, which a boosted flight leaves in well under a second. That is fine for trying flight out and is not a bug to fix in `player.gd` — a game that keeps the player flying wants a world with something in it to fly over.

## Player character asset

`assets/runtime/characters/player_character.glb` is the rigged stylised character, bare. It imports in Godot as `Node3D > CharacterRig > Skeleton3D > Character`, and garments are added under that same skeleton at runtime.

- 1.45 m tall, feet on `y = 0`, faces Godot forward (`-Z`), so it can be dropped straight under a `CharacterBody3D`. The collider and eye heights in `player.gd` are derived from this height, so they need revisiting if the proportions change. Clothes deliberately do not change them: a hat is not a reason to stop fitting through a gap.
- One continuous 20.5k-quad body skin, decimated on export. There are no separate head/arm/leg objects and no seams to hide.
- 23 bones named to match Godot's `SkeletonProfileHumanoid` (`Hips`, `Spine`, `Chest`, `UpperChest`, `Neck`, `Head`, `Left/RightShoulder`, `UpperArm`, `LowerArm`, `Hand`, `UpperLeg`, `LowerLeg`, `Foot`, `Toes`), so retargeting and `BoneMap` work without renaming. `Root` is a transport handle and carries no weights.
- Modelled in an A-pose with at most four bone influences per vertex.
- One material, `CharacterBody`. `SurfaceSkin` gives every imported surface its own copy of `player_suit.tres` and copies that surface's albedo colour and texture into the vivid shader, so recolouring anything in Blender needs no script change. The body, its garments and the menu's model preview all go through it.
- The `Apparel` collection in the `.blend` is **excluded from this export**, because `build_apparel.py` writes each garment as its own `.glb` for the runtime equipment system to put on and take off. Exporting them into the body would weld the clothes to the character.
- Thirteen baked clips, imported as an `AnimationPlayer` beside the rig.

### Settler robotic textures

`assets/runtime/characters/player_character_3.glb` is the 1.60 m settler body. Its default look is `assets/runtime/characters/luke.png`; `character_3_clean_robotic.png` (red, cream and gold with cyan cores) and `character_3_integrated_robotic.png` (violet skin under graphite, silver and red armour with cyan lights) remain selectable alternatives. They are texture schemes on one body, not separate bodies: the skeleton, collider, animation set and `c3_*` apparel are shared.

Mixamo clips from `m2m_player.glb` are retargeted onto this same humanoid and stored in `player_character_3_m2m.glb`. The authored locomotion and ability names on the body stay as they are; new work should play the Mixamo clip names (`Idle_A`, `Melee_Hook`, `Dance_Simple`, …). `Walk` and `Slide` already exist on the body, so those two Mixamo motions ship as `m2m_Walk` and `m2m_Slide`. Rebuild the library with `assets/source/blender/merge_m2m_animations.py`.

The supplied front/back concept sheets are elevations of different proportions, not UV maps, and the source sculpt has no UV coordinates. `assets/source/blender/character_3_skins.py` therefore owns the adaptation. `build_character_3.py` asks it to make one packed atlas, evaluates those two designs in the mesh's original 3D metres, and rasterises both PNGs through that atlas. Luke is painted directly against the same atlas and is put on the exported material as the default:

```powershell
& $blender --background --python assets/source/blender/build_character_3.py
& $godot --headless --path . --import
```

The home-screen Hero Design tab lists all three schemes from `CharacterDB.SKINS`. The saved look and player metadata carry a `skin` id beside `body`; peers therefore draw the same scheme without duplicating the `.glb`. The colour wheel remains a multiplicative wash over the selected texture. **No tint** removes that sparse tint entry rather than saving white, so the authored texture is restored exactly and later texture edits are not hidden behind an override.

Both skins can be rendered from the same generated `.blend` without rebuilding:

```powershell
& $blender --background assets/work/character_3_rigged.blend --python dev/_render_dressed.py -- --hide=apparel --skin=integrated_robotic --out=c3_integrated
```

### Animation clips

| Clip | Loops | Driven by |
| --- | --- | --- |
| `Idle` | yes | Standing still |
| `Walk`, `Run` | yes | Ground speed, resampled with `speed_scale` so the feet keep up |
| `CrouchIdle`, `CrouchWalk` | yes | Crouch stance |
| `JumpRise`, `Fall`, `AirRun` | rise and air-run no, fall yes | Airborne: rise/fall initially, then a held landing stride after one second |
| `Land` | no | Touchdown, skipped if you land still running |
| `Slide` | no | Slide stance; eases into the pose and holds it |
| `Float`, `Fly` | yes | Flight stance, split on how much of the boost is in |
| `Tread`, `Swim` | yes | Swim stance, split the same way on how fast the stroke is going |

`player.gd` picks a clip from stance, speed and ground contact in `_update_animation()` and crossfades with `CLIP_BLEND`. glTF carries no loop flag, so the looping set is marked in `LOOPING_CLIPS` at load.

Two of those pairs are authored **upright**, and the game pitches the whole body forward as speed builds, so in the `.blend` "up" is the direction of travel: `Fly`'s arms swept behind the hips become a pair streaming off the shoulders, and its straight legs a trailing line, the moment the body leans over. `Swim` is the same trick under water — a front crawl written vertically, which is why its arms sweep the whole way round the shoulder rather than reaching forward. That split is what makes the hover and the flight one continuum rather than two unrelated poses, and the tread and the crawl likewise: the lean carries the change, and the clips only have to be right at each end of it. Authoring either flat-out clip lying down would fight the rig's rest pose and leave nothing usable at the hovering end.

The three poses the body holds at speed — `Run`, `JumpRise` and `Fly` — all sweep the arms **back**. Every one of them carried the arms forward first, which is what a body really does; the arm swing is where a third of a jump's height comes from. But at the top of that swing the palms are up and the elbows are bent, and with nothing else in the pose doing any work it reads as somebody feeling their way along a dark corridor. Arms back with the chest driven forward is the posture that says speed, and the legs then carry what separates the three: a stride, a split tuck, and a straight line. `Fly` spent a while on one arm up and one back as well, which reads at any size but dates the whole thing and is the one pose a held weapon cannot survive.

The clips are authored as code in `assets/source/blender/build_animations.py`, which opens the `.blend`, replaces every action, pushes each into its own NLA track and re-exports the `.glb`:

```powershell
& $blender --background --factory-startup assets/source/blender/player_character.blend --python assets/source/blender/build_animations.py
```

Each clip is a function of cycle phase returning per-bone rotations in **world** axes (X pitch, Y roll, Z yaw) rather than bone-local ones, because bone-local axes depend on whatever roll the rig builder calculated. Crouch, land and slide depths run through `leg_fold()`, a two-link solve that folds the legs by exactly as much as the hips drop, which is what keeps the soles on the floor; changing the depth of one of those poses is a single number. `dev/_player_test.gd` measures foot bone heights across every clip so a pose that sinks the boots shows up as a number rather than needing to be spotted by eye.

Arms go through `arm_hang()` for a similar reason. The rig rests in a wide A — 42 degrees out from vertical at the shoulder — so a clip that wants hands at the hips has to bring the arms most of the way down, and the forearm inherits the shoulder's part of that and would otherwise be adducted twice and end up across the body. So a pose names the angles the finished arm should read as, out from vertical and bent at the elbow, and the helper works out the rotations. It also matters that the drop is listed before the swing: rotations apply in order, and swinging an arm that is still held out sideways twists it rather than swinging it.

`assets/source/blender/_arm_check.py` reports the rest angles those numbers are relative to, and, for every clip, how close the arms come to the body:

```powershell
& $blender --background --factory-startup assets/source/blender/player_character.blend --python assets/source/blender/_arm_check.py
```

It compares the deformed mesh, not the bones, so an arm that has been brought in far enough to sink into a hip is a number in the output. Every clip currently clears by at least 7 mm.

### Regenerating the mesh

Everything under `assets/source/blender/` is the authoring side and is hidden from Godot by a `.gdignore`. The character is generated by script rather than hand-sculpted, so proportions are edited as numbers and rebuilt:

```powershell
$blender = "C:\Program Files\Blender Foundation\Blender 5.1\blender.exe"
& $blender --background --factory-startup --python assets/source/blender/build_character.py
& $blender --background --factory-startup assets/source/blender/player_character.blend --python assets/source/blender/render_previews.py
```

The first command rewrites `assets/source/blender/player_character.blend` and exports `assets/runtime/characters/player_character.glb`. The second writes orthographic, three-quarter, wireframe, and posed previews to `assets/previews/authoring/` for eyeballing changes.

### Re-exporting after editing the .blend by hand

`build_character.py` **overwrites the .blend**, discarding hand edits to the mesh and every baked action with it. Use the export-only script to pick up manual edits, which reads the file and writes the `.glb` without modifying or saving anything:

```powershell
& $blender --background assets/source/blender/player_character.blend --python assets/source/blender/export_glb.py
```

Run it with the Blender version that last saved the file; opening a newer `.blend` in an older Blender drops data silently. It prints the mesh and bone counts, modifier settings, bounds, floor offset, and the object list it is about to export, so a change that would break the Godot import is visible in the output.

Prefer it over Blender's **File > Export > glTF** dialog. The dialog defaults to the "Actions" animation mode, which writes nothing for the slotted actions Blender 4.4+ produces and so ships a `.glb` with no `AnimationPlayer` at all; `export_glb.py` exports the NLA tracks the clips actually live in.

Silhouette lives in the section tables at the top of `build_character.py`: `TORSO`, `ARM`, `LEG`, and `BOOT` are control points holding a centre plus a width and depth radius. They are resampled along a Catmull-Rom spline, lofted into closed tubes, then fused into a single watertight surface by a voxel remesh and a relaxation pass, which is what rounds the shoulders and hips instead of leaving intersecting primitives. `source/reference.png` is the concept sketch the proportions target.

Run `dev/_check_character.gd` to re-verify the export after a rebuild:

```powershell
godot --headless --path . --script dev/_check_character.gd
```

It prints the imported node tree, the bone list, the mesh bounds, and whether the character still faces `-Z`.

## Apparel, items and getting dressed

The physical changing-room prop has been retired. Apparel is owned by the player and managed from the Inventory tab, so dressing works from anywhere without a second storage container or interaction scene.

Four pieces move the clothes around, and only the last one knows anything about menus:

| Script | Holds |
| --- | --- |
| `game/items/item_db.gd` | Every item: title, description, the slot it occupies, and its `.glb` |
| `game/items/item_container.gd` | A run of slots holding item ids, with per-slot filters and the move rules |
| `game/player/wardrobe.gd` | Putting a garment `.glb` onto a character's skeleton, and taking it off |
| `ui/inventory/inventory_page.gd` | The screen: tiles, drag and drop, shift-click, tooltips, and a live model |

Every grid on the screen is an `ItemContainer`: the player's `equipment`, numbered hotbar and `backpack`. That is what keeps equipping from being a special case. An equipment slot carries a filter naming its body slot, so it refuses a pair of shoes on the head; dropping a hat there is an ordinary move, and the player, watching its own equipment container, is what turns that into a garment on the skeleton. The same change drives the model in the menu, so the preview cannot drift from the body in the world.

The numbered hotbar accepts weapons and ordinary usable items. It is the same container the HUD bar along the bottom of the screen shows, so an item dropped there is immediately on the bar without anything being copied.

Adding a garment is an entry in `ItemDB.ITEMS` plus its `.glb`, followed by adding its id to the compatible body in `CharacterDB`. The item's icon is rendered from its own mesh by `ui/inventory/item_icons.gd`, so there is no second copy of the art to keep in step.

Two things about the 3D bits inside a menu are worth knowing before changing them. The icons and the model preview are rendered well above the size they are drawn at and scaled down, because the outline pass measures its strokes in pixels and would otherwise ring a 44-pixel icon in strokes as thick as the garment. And neither viewport is given an `Environment`: the pencil material ignores ambient light, so the only thing one could do there is escape into the world's own lighting.

Over the network, a player owns their own look: equipment changes are broadcast, other peers apply them to that player's skeleton, and a peer joining later is told what everyone has on with the rest of the world state.

Run the headless apparel check after changing a body or garment:

```powershell
godot --headless --path . --script dev/_check_apparel.gd
```

It equips every compatible garment on both bodies and verifies skeleton bindings, surfaces and imported clips.

## Weapons

`assets/runtime/items/sword.glb` and `assets/runtime/items/laser_rifle.glb` are the two weapons. Each imports as a single `MeshInstance3D` with no skeleton and no animation. Both are held two-handed, with one hand on the grip and the other supporting.

They share one mount convention, so either weapon works in either hand:

| | |
| --- | --- |
| origin | the centre of the grip, i.e. the point that sits inside the fist |
| `-Z` | the direction the weapon points — blade tip, muzzle |
| `+Y` | the weapon's up — sword flat, rifle sight rail |

That means a weapon parented to a hand with an identity basis points where the character faces, since `-Z` is Godot forward.

- **Sword**, 0.823 m: a 0.61 m tapered blade with a hexagonal section and a drawn-out point, a brass crossguard, a waisted leather grip with four wrap ridges, and a brass pommel. 990 faces, 3 materials.
- **Laser rifle**, 0.613 m: a 0.10 m calibre cylindrical barrel with cooling rings and glowing energy bands, a flared muzzle with an emitter lens, an underslung power cell, a sight rail and optic, and a raked pistol grip. 2014 faces, 4 materials, with the glow surfaces carrying emission.

Sizes come out at 57% and 42% of the character's height, which are the same ratios a one-handed sword and a carbine have to a real person.

### Fitting the hands

Grips are **measured off `player_character.glb`**, not written down. `assets/source/blender/character_ref.py` finds the vertices weighted to each `Hand` bone and reports the fist's radius and where its centroid sits along the bone; grip thickness and length are ratios of that radius. Editing the character's hands and re-exporting is enough to keep the weapons fitting — there is no second copy of the character's dimensions anywhere.

`game/player/weapons.gd` derives the same offset on the Godot side from the skeleton alone: the hand bone gives the direction and its rest translation gives the length. A weapon hangs off a `BoneAttachment3D` on the hand bone, so it follows the hand through every clip the body plays without its own skeleton or animations.

```gdscript
const WeaponsScript := preload("res://game/player/weapons.gd")
WeaponsScript.dual_wield(character)                          # sword right, rifle left
WeaponsScript.equip(character, "left", "sword")              # or one hand at a time
WeaponsScript.unequip(character, "right")
```

`OnlinePlayer` builds its pencil materials by walking every `MeshInstance3D` under the character, so equip before that runs and weapons are shaded like the body, picking up the colours baked into their `.glb`.

### Holding them

A mount alone leaves a weapon pointing out of a hand that hangs at the side, because the rig's rest pose is an A-pose. The stance is not a clip: locomotion is full-body, so a hold clip would have to be authored per weapon per gait. `game/player/weapon_pose.gd` is a `SkeletonModifier3D` that solves the arms *after* the animation has been applied, which is why the same two holds work over idle, walk, run, crouch and mid-air alike.

Each hold in `WeaponPose.HOLDS` is written as two points relative to the sternum — where each hand grips — and the weapon is then aimed **along the line through both hands**. That is the part worth keeping: the support hand is on the weapon by construction rather than by an angle that needs re-tuning whenever a pose moves, and a swing is just the two points travelling, with the blade following from them.

The rest is bookkeeping the rig forces:

- A two-link solve puts each elbow somewhere plausible, pushed away from the body by a pole vector, and clamps a target that is out of reach. Bone lengths come off the rest pose, so re-proportioning the character needs nothing changed here.
- Targets are given in a frame that sits at the sternum and carries only what the animation *added* to it. Blender lays a bone's axes along the bone, which leaves this chest's `+X` pointing to the character's left, so targets written in the bone's own space come out mirrored.
- A hand is turned to the rotation that lands the weapon on the aim, and solved to where its wrist has to be for its grip — not its wrist — to reach the target, using the same `GRIP_ALONG_HAND` fraction the mount uses.
- `PITCH_FOLLOW` decides how much of the player's look angle a hold takes on: all of it for the carbine, so a shot aimed upwards does not leave a level barrel, and a quarter of it for the sword.

The holds themselves: the sword is two-handed off the character's right, blade straight up, with the support hand reaching across for it, and a cut travels right to left through three keys with the torso leading. The carbine is held with the trigger hand in and the support hand forward under the barrel; sighting in raises both to the eye. Each pose's `twist` turns the chest, and because the targets ride the chest it also steers the weapon, so the twists are set to leave the carbine pointing where the character faces.

Arms on this character reach about 0.385 m, which is what limits both holds: the support hand is the one that runs out of reach, and both poses sit at the edge of it.

### Drawing and firing

`ItemDB` carries three extra fields for a weapon — which hold takes it, whether the attack is a swing or a shot, and how many shots its cell holds — so arming the character is the same container move as putting on a hat. `OnlinePlayer.weapons` is the rack; selecting a slot equips what is in it and sets the hold, and selecting an empty slot puts the weapon away.

- The **sword** cuts on left click and ignores further clicks until the swing is done. It has no hit detection: there is nothing in this template to hit yet.
- The **carbine** fires `game/weapons/laser_bolt.gd`, which sweeps a ray over the ground it covered each frame rather than being a physics body, because a body at 74 m/s tunnels through walls. Bolts leave the muzzle but are aimed at the crosshair, so a shot lands where the player aimed instead of parallel to it. Its cell holds twelve and trickles one back every 0.85 s after a short pause, which paces the weapon without a reload key.
- Sighting in narrows the field of view, halves mouse sensitivity, draws the crosshair in, and raises the hold.

In first person the body is drawn as shadow only, but what is in the hands is not: a sword rising into view or a carbine held at the chest is most of the feedback there is. The exception is a weapon brought within 0.3 m of the eye, which is a wall of polygons rather than a weapon, so sighting in hides the model and leaves the zoom and the crosshair to say so.

Over the network only the weapon **in hand** is broadcast, since nobody can see anyone else's rack, and a peer joining later is told it with the rest of the world state. Swings and shots are sent as events rather than derived from state: both are instants, and a peer that misses the packet should miss the swing rather than play it late.

`dev/_weapon_test.gd` photographs every hold, the swing, and a bolt in flight into `dev/captures/`, and measures the parts that cannot be judged by eye:

```powershell
godot --path . dev/_weapon_test.tscn
```

For each pose it reports where the weapon points, how far the support hand sits off the weapon's axis, how far apart the two grips are, and the `cant` — how far off the character's facing the weapon points, which is what a rifle held across the chest shows up as. It also confirms the wheel skips empty slots, that a shot leaves along the crosshair and spends a charge, that the cell recovers, and that shift-clicking a weapon into the hotbar equips it. Hands are measured through `BoneAttachment3D` probes rather than `get_bone_global_pose()`, which reads a cache a frame behind the modifier that moved them.

### Regenerating

The weapons are built from the shared bmesh primitives in `assets/source/blender/propkit.py`. The build reads `player_character.glb`, so export the character first if you have changed it.

```powershell
$blender = "C:\Program Files\Blender Foundation\Blender 5.1\blender.exe"
& $blender --background --factory-startup --python assets/source/blender/build_weapons.py
& $blender --background assets/source/blender/weapons.blend --python assets/source/blender/render_weapons.py
```

The first command writes `assets/source/blender/weapons.blend` and both `.glb` files, printing the measured fist and the grip it derived. The second writes previews to `assets/previews/authoring/`: each weapon on its own, both dual wielded on the character, and `weapons_grip`, a close-up that shows the grip inside the mitten.

Run `dev/_check_weapons.gd` after a rebuild:

```powershell
godot --headless --path . --script dev/_check_weapons.gd
```

It checks the surfaces and dimensions, confirms the grip it derives lands within a couple of millimetres of the fist `character_ref.py` measured, and swings each arm to confirm the weapon stays locked to the hand. It poses bones directly rather than playing a clip: an `AnimationPlayer` never applies a pose in a headless `SceneTree` script, and `Skeleton3D.get_bone_global_pose()` reads a cache that is only refreshed while processing frames, so a clip-driven check silently measures the rest pose and passes for the wrong reason.

## Backpack

`assets/runtime/items/backpack.glb` is a soft-sided pack with a leather lid, a buckled closing tongue, a grab handle, side rivets and two padded shoulder straps. It imports as a single `MeshInstance3D` — 4,916 triangles, 3 materials — with no skeleton and no animation.

The pack body is 0.245 m wide, 0.307 m tall and stands 0.147 m off the back, which is 21% of the character's height; the mesh as a whole is wider and deeper than that because the straps reach out to the shoulders and forward to the chest.

It is a **rigid prop, not a skinned garment**. A pack does not deform, so it belongs on a bone rather than in the skin, and it uses the same convention as the weapons:

| | |
| --- | --- |
| origin | the `UpperChest` bone, so a `BoneAttachment3D` there needs no offset of its own |
| `-Z` | the direction the character faces, so the pack hangs off the `+Z` side |
| `+Y` | up |

Nothing in `game/` mounts it yet.

### Fitting the back

Every dimension is **measured off `player_character.glb`** by `character_ref.py` rather than written down, and two of those measurements are the difference between a pack that fits and one that does not.

The back panel **follows the spine's contour** instead of being flat. `ray_to_surface()` casts at each cross-section and sets that section's front face on the surface it hits. A flat panel set at the deepest point of the back stands off everywhere the back is shallower, which leaves a visible gap under the shoulder blades.

The straps **cross outboard of the head**. This character is a big head sitting almost straight on the body with no trapezius, so there is no gap beside the neck for a strap to pass through: the head reaches out to x ≈ 0.19 and the shoulder surface only begins at x ≈ 0.20. `shoulder_crossing()` walks outward casting downward and takes the first sharp drop, which finds that saddle. Two things follow from measuring it rather than assuming it:

- Nearest-point projection is useless here — beside the head the top of the shoulder and the side of the head are nearly equidistant, so it is a coin toss which one a strap lands on. A downward ray can only hit the shoulder.
- The pack hangs off the shoulder **surface**, not the shoulder **bone**, which sits 0.08 m below it. Placed off the bone the pack rides down by the whole difference and reads as a satchel on the mid-back.

Straps are then splined through ten ray hits along the route. Fewer waypoints and the curve cuts the corner and stands off the shoulder in a loop, and the run up the back is pinned just under the shoulder's rear slope — that slope is lower than the top of the pack, so letting the strap climb to the pack's top first makes it rise, dip and rise again in a visible kink.

### Regenerating

```powershell
$blender = "C:\Program Files\Blender Foundation\Blender 5.1\blender.exe"
& $blender --background --factory-startup --python assets/source/blender/build_backpack.py
& $blender --background assets/source/blender/backpack.blend --python assets/source/blender/render_backpack.py
```

The first command writes `assets/source/blender/backpack.blend` and the `.glb`, printing the span it fitted, where the back surface put the front face, and where it found the shoulder crossing. The second writes previews to `assets/previews/authoring/`: the pack alone, worn from three angles, and `backpack_strap`, a close-up that shows whether the strap lies on the shoulder or through it.

Render scripts share the camera, world and light rig in `assets/source/blender/previewkit.py`.

## Workbench

`assets/runtime/items/workbench.glb` is a joiner's bench: a thick top with a tool well along the back, a pegged backboard, a slatted lower shelf, and a face vice at one end. It imports as two `MeshInstance3D` nodes — 5,292 triangles, 4 materials — with no skeleton and no animation.

| | |
| --- | --- |
| footprint | 1.28 m long by 0.56 m deep |
| work surface | 0.639 m, with the backboard reaching 0.859 m |
| origin | the centre of the footprint at floor level |
| `-Z` | the working side you stand at, matching the other props |
| `+Y` | up |

The vice's sliding half is a second object, `WorkbenchViceJaw`. Its origin sits on the screw axis where the jaws close, so Godot winds the vice open by moving it along `-Z` with no offset node in between. It is modelled 0.030 m open and has about 0.085 m of useful travel. There is no collision shape; a box per leg and one for the top is enough, and cheaper than a trimesh.

Nothing in `game/` places it yet.

### Bench height comes from the elbow, not the height

Bench height is ergonomic rather than architectural — it is set by the arms — so scaling a real 0.90 m bench down by this character's height gets it wrong. The character is 1.447 m tall but its head is a fifth of that, which puts the shoulders at 0.68 of standing height where an adult's are at 0.82. Working from stature would stand the top near mid-chest.

`character_ref.arm_drop()` measures it properly. The rest pose holds the arms out in an A-pose, about 55° below horizontal, so no arm joint's rest position is where it sits on a standing figure; the heights have to be derived by dropping the bone lengths from the shoulder. That gives a shoulder at 0.982 m, elbow at 0.722 m and wrist at 0.597 m. A general-purpose bench sits a hand's width below the elbow, so the top lands at **0.639 m** — 0.082 m under the elbow and 0.042 m over the wrist, which `workbench_scale` confirms is right where the character's hands hang.

That works out at 44% of standing height where a real bench is 51%, which is the character's short arms showing up rather than a mistake.

### Two things that did not work first time

**The tool well's depth is not a free parameter.** It is fixed at the thickness of the top, because the trough floor has to sit flush with the underside of the slabs either side of it. Dropping the floor lower to deepen the well opens a slot running the whole length of the bench along both sides of the trough — between the floor and the slabs above it there is nothing left to bound the well with. The ends need closing separately, or three slabs and a floor leave a trough that reads as a slot sawn through the bench.

**A vice made of two iron plates does not read as a vice.** Nearly shut, it renders as a black box bolted to the bench, indistinguishable from a drawer. Three changes fixed it: a wooden liner over each jaw so the colour breaks up the mass, a gap wide enough to see the screw and guide rods crossing it, and the tommy bar hung vertically rather than across the bench, where it lay over the jaw and merged with it into one dark shape.

The jaws are also kept wholly below the underside of the top. Bringing them up level with the front edge, which is where a real vice sits, puts the jaw plate's faces exactly on the top's front face, and two coincident coplanar faces z-fight.

### Regenerating

```powershell
$blender = "C:\Program Files\Blender Foundation\Blender 5.1\blender.exe"
& $blender --background --factory-startup --python assets/source/blender/build_workbench.py
& $blender --background assets/source/blender/workbench.blend --python assets/source/blender/render_workbench.py
```

The first writes `assets/source/blender/workbench.blend` and the `.glb`, printing the arm measurements it worked from and where they put the top. The second writes previews to `assets/previews/authoring/`: front, three-quarter, a high angle for the tool well and shelf, `workbench_open` with the vice wound out to check the jaw really slides along its screw, and two character shots — `workbench_scale` stands the character beside the bench for a straight height comparison and `workbench_use` puts them at it.

`previewkit.Preview.ground()` provides the floor. Furniture reads as floating without one, and more to the point there is no contact shadow, which is the only cue that tells you whether the legs reach the ground.

## Cave entry room

`assets/runtime/environment/cave_room.glb` is an enclosed cave chamber with a tunnel mouth broken through one wall and glowing crystal clusters for light. It imports as three `MeshInstance3D` nodes and six `OmniLight3D` nodes — 18,470 triangles, 4 materials, no skeleton and no animation.

| | |
| --- | --- |
| chamber | ~10.5 m nominal radius, bulging to 11.7 m where the rock swells; 9.6 m to the highest point of the ceiling |
| tunnel | roughly 5 m wide by 4.7 m tall at the mouth, running 24 m out from the centre and bending as it narrows |
| origin | the centre of the floor, so the room drops straight in at the world origin |
| `+X` | the direction the tunnel leads |
| `+Y` | up |

The floor is uneven but deliberately kept walkable, dipping to −0.45 m and rising to about +0.5 m. **There is no collision shape** — add a trimesh collider on import, or rename the shell to `CaveRoom-col` in the build script to have Godot generate one.

### Turning the rock inside out

The shell is authored as a **solid volume and inverted at the end**, which is what `flip_normals` on `propkit.new_object()` is for. Carving a room out of nothing is far more awkward than modelling the rock it displaces, and it makes the tunnel a plain boolean union of two lathed volumes rather than a hole that has to be cut and stitched. The build asserts both halves of that: the shell must have zero open edges, and rays cast outward from inside must all hit faces looking back at them. Get the winding backwards and the room renders as nothing at all once backface culling is on.

Displacement is a function of **position, not surface normal**. Two coincident vertices either side of the boolean seam carry different normals, so displacing along normals tears the shell open along the join. It is also applied *after* the union — displacing first gives the exact solver two noisy surfaces to intersect and it starts producing slivers.

Three things had to be true before the room read as a cave rather than as a smooth dome:

- **Noise frequency has to be a fraction of the room.** `mathutils.noise` has a feature size of about one unit, so a frequency of 0.085 puts the whole 21 m chamber inside a single noise feature and the displacement flattens into a uniform offset. Features of a few metres are what break up the walls.
- **The rock has to facet.** Smoothing the shell across its own lumps turns metres of displacement into soft gradients that read as fog. A 24° smoothing angle lets the facets show.
- **Surface noise alone is not enough.** The dripstone is what says "cave". Stalagmites and stalactites are placed by casting rays at the finished shell, so each one stands on the displaced rock instead of hovering over where a smooth dome would have been, and rays that land on a steep face are rejected rather than left sliding off the silhouette.

`mathutils.noise` seeds itself from the clock and its vector variants read that seed, so an unseeded build produces a different cave every run — and because the dripstone and crystals are positioned by raycasting at the rock, they all move too. `noise.seed_set()` makes the build reproducible; three consecutive builds now agree to the last decimal place.

### Keeping the hole dark and still visible

The tunnel's faces keep their own near-black material through the boolean, which is what makes the passage read as dark rather than as a lit alcove, and it bends away from the chamber so none of its capped far end is ever in view.

That alone is not enough to see it, though. The wall around the mouth was originally as unlit as the mouth itself, and a dark hole in dark rock is not a hole — it needs lit rock around it to read against. Two small crystal clusters flank the opening at roughly ±40°, far enough to either side that their light grazes the wall rather than reaching down the passage.

The crystals are emissive, but **emission lights nothing on its own** without ray-traced GI, so each significant cluster carries a point light. Those export through `KHR_lights_punctual`, which Godot imports as real `OmniLight3D` nodes. Their energies are in the low hundreds of watts: a point light falls off as the inverse square, and lighting a 20 m chamber from 5 m away takes a few hundred watts, not the few thousand that sounds reasonable for a lamp in a small room. At 2,400 W every surface clipped to flat saturated colour and the geometry disappeared entirely.

### Regenerating

```powershell
$blender = "C:\Program Files\Blender Foundation\Blender 5.1\blender.exe"
& $blender --background --factory-startup --python assets/source/blender/build_cave.py
& $blender --background assets/source/blender/cave_room.blend --python assets/source/blender/render_cave.py
```

The first writes `assets/source/blender/cave_room.blend` and the `.glb`, printing the chamber's measured size, the polygon budget per object, how much dripstone was placed, and the two shell integrity checks. The second writes previews to `assets/previews/authoring/`: the chamber, the tunnel mouth from across the room, the arrival view from inside the passage, the ceiling, the crystals, and `cave_scale`, which stands the character in the room.

Unlike the prop previews, `render_cave.py` sets up **no light rig** — the room's own crystals are the subject and a three-point rig would flood out the only thing worth looking at. The world is left nearly, but not quite, black: at zero, every surface the crystals do not reach renders as a flat silhouette and the dripstone in front of a glow turns into a paper cut-out.

## Abilities

Two of them, on the two mouse buttons whenever nothing is drawn: **Laser Eyes** on left, **Meteor Punch** on right. They are not weapons and they do not go in the weapon rack — `OnlinePlayer.abilities` is its own container, `ItemDB` marks their entries `KIND_ABILITY`, and the same slot filter that keeps a hat out of the weapon wheel keeps a sword out of an ability slot.

They exist as a framework rather than as two special cases, because most of what an ability needs is the same for all of them. `game/abilities/ability.gd` holds the cooldown, the stances it is allowed from, and whether water stops it; `ability_controller.gd` is a node under the player that builds one ability per filled slot from the catalogue and drives press, hold and release. Adding a third ability is a script and an `ItemDB` entry.

Their numbers live in `ItemDB.ITEMS` rather than in the scripts, so the ability that quotes 180 damage a second in the menu is the ability that deals it:

```gdscript
"laser_eyes": {
	"title": "Laser Eyes",
	"kind": KIND_ABILITY,
	"script": "res://game/abilities/laser_eyes.gd",
	"stats": {"damage": 180.0, "damage_unit": "/s", "duration": 4.0,
		"range": 60.0, "cooldown": 3.0, "radius": 0.35},
},
```

`ItemDB.stat_lines(id)` turns that into the lines the menu shows (`Damage   180 / s`, `Range   60 m`), so every ability is formatted by one table instead of by whoever wrote its panel.

### What they do to the world

Neither ability knows what it is hitting. Both describe a **volume** — `game/combat/damage_hit.gd`: a capsule, an amount, and how fast the amount falls off across it — and hand it to every field in the `flora_damage_fields` group, which works out for itself which of the things it owns are inside. That is what lets one laser tick damage grass, a tree trunk and the ground with the same object, and it is the only way to hit grass and shrubs at all, since they are `MultiMesh` instances with no colliders anywhere.

What absorbs it is flora health. `PlantSpecies` now authors `health`, `health_per_metre` and a `toughness` band, and **derives** the old run-through break speed from them, so the two cannot drift apart; the migration set `health = break_speed * 12` across all 46 species, which preserves every previous break speed exactly. Toughness is what makes the beam slice grass instantly and grind on an orb giant. Damage short of a kill chars: it is written into the free alpha channel of the instance colour, which `shaders/vivid/vivid_plant.gdshader` reads to darken the albedo and kill the night emission, leaving the RGB semantic mask alone.

The ground is `game/planet/terrain_scars.gd`, a bucketed registry hanging off `PlanetShape`. `elevation()` subtracts `scars.depth_at()` **last**, after the native field and the volcano, so a crater cuts through whatever the height field is as readily as through sand; `color_at()` takes the matching tint. A scar therefore lands in the same height field the mesh is built from, the collider generated from and the player's ground guard reads, so there is one answer to where the ground is rather than three that have to be kept in step. `Planet.mark_region_stale()` re-queues the affected chunks through the existing per-frame build budget, so a burst of craters degrades into a slightly slower refresh instead of a hitch — and only the chunks whose vertices are close enough together to draw the mark are re-queued at all, since the height field already fades a scar out at coarser spacings and rebuilding those would produce the ground they already have.

A rebuilt mesh comes back **on screen immediately**, which a newly built one deliberately does not. A first build waits for the next quadtree walk to choose it, and should: the coarse ancestor covering that ground is still drawn, and letting half-refined patches appear the moment they land is how ground pops through the mesh standing in for it. A rebuild has no such cover — the ancestor retired its own mesh when this chunk took the ground over — so switching the replacement on only at the next walk leaves that patch with nothing drawn over it at all, and what is behind the ground is the inside of the planet. Meshes are attached every frame and the walk runs at 30 Hz, so it was up to a walk interval of hole, several times a second under a held beam. The two cases are told apart by `Chunk.rebuilding`, which also keeps the `stranded` counter meaningful: a rebuild lands on a chunk that already holds a mesh every single time by design, and counting those alongside the genuine overwrite-and-orphan fault would bury it.

**Its collider comes back in the same breath, and that turned out to be the half that mattered.** Seeing through the ground while a beam is swept over it looks like a mesh problem and is not: the camera rides a `SpringArm3D`, which holds itself out of the scenery by casting at the **bodies** in it, so ground with no body under it is ground the arm cannot see. The camera runs into the hillside, draws its back faces, and you are looking through a mesh that was present and correct the entire time. Two things were opening that window several times a second, and both are shut:

- A rebuild used to free its collider and leave `_update_collision` to make the next one. That pass is budgeted by `bodies_per_frame` and shares its allowance with all the ordinary streaming, so the chunk could spend frames drawn with nothing under it. The faces are in hand when the build lands, the work is the same work either way, and only chunks that already had a body — the handful near the viewer — pay it, so it is done there and then. Measured against the deferred version the difference is noise: 162 ms of laser-groove rebuild became 164 ms.
- Marking a region stale used to drop every collider over it outright. That is right for a crater, where the alternative is standing on a ledge of ground that no longer exists, and it is what stopped the fall after a punch. It is wrong for a laser groove, which cuts 0.2 m four times a second wherever the player happens to be looking — very often at their own feet. `mark_region_stale` now takes the depth of the cut and only drops colliders past `COLLIDER_DROP`, a stride.

The invariant this restores is `floorless` in `Planet.statistics()`: drawn ground within reach of a walker that has no body under it. Zero is the only steady-state answer, and a swept beam had been sitting at one chunk per scar.

Vertex tint alone is not a burn. At the range a scorch mark is actually looked at, the ground is drawn from a photographic material and a tint spread over a handful of vertices does not read at all, so `game/planet/scorch_decals.gd` keeps a pooled ring of `Decal` nodes — fading ones for the beam, permanent ones for a committed scar. Marks landing on top of each other merge rather than stack, since a held beam lands ten a second on one spot and ten decals multiply into a hole with no soot edge left in it.

### Laser Eyes

Two beams from the eye offsets in `CharacterDB.BODIES`, converging on the aim point. Those offsets are in the **body's** space, not the Head bone's, and the distinction is not pedantry: the two characters' Head bones are turned half a circle from one another, so one set of numbers authored "so far forward along the bone" was always going to come out backwards, and it did — the settler fired out of the back of its neck for a while. `eye_points()` anchors the offset to the bone's rest pose and carries it through `pose * rest⁻¹`, which is the head's movement away from rest, so the beams sit on the face and follow it through a clip without anything having to know which way the bone happens to point. The numbers themselves are measured off each body by `dev/_eye_probe.tscn` — the front of the head at eye height, and for the settler the goggles, which are worn on the eyes and so state the eye line rather than estimating it. Both now sit 2 mm inside the skin. Damage runs at 10 Hz: a `damage_capsule` along the segment cuts everything standing in the beam, and a `damage_sphere` at the landing point takes the larger share. The ray that finds that landing point **passes through** plant colliders — up to eight of them — because a beam stopped by the first tree trunk is not a beam that cuts through a wood; the trunk is damaged by the capsule like everything else in the line, and the beam carries on to the ground. Sustained fire commits a shallow `GROOVE` scar, about 2 m across and 0.2 m deep, which is broad enough to register on a 1.5 m vertex grid. It refuses to fire while submerged and plays no animation clip, only the beams and the light.

### Meteor Punch

A stance rather than a thing standing next to the movement code: `Stance.METEOR` sits beside `HERO` and `CRASH` with its own `_meteor_move`. The launch takes whichever is larger, the speed already carried or 60 m/s, and accelerates toward 200 m/s along the look direction for 50 m. A 4 m cylinder swept from the fist feeds a damage volume every tick — swept rather than stamped, because at 200 m/s the fist covers three metres between ticks and a stamp leaves the flora in between standing. Flora is resolved but its answer is thrown away: a punch that could be slowed by a hedge is not a punch.

Thrown from the air it is a dive, and the ground it hits opens as a `BOWL` about 6 m across and 2.5 m deep — more if it arrives faster, of which more below. Thrown from the feet it is a flat charge: the body lifts clear of the ground it launched off, and a surface only counts as struck if it **leans back into** the punch, since a flat charge grazes the floor it is travelling over on every tick and stopping on that would end the move where it started. Spend the reach with nothing hit and a dive returns to flight while a ground charge falls out of the sky and cuts a `CONE` ahead of its feet. Either ending hands off to `Stance.HERO`, whose pose and camera blend already existed for steep flight landings.

**Diving at the planet is the case the numbers were all written against.** Flight tops out at 1000 m/s, five times the punch's own 200, and thrown at that speed the move used to fire and then quietly not happen — you arrived on the ground with no crater. Three separate things had to be true for that, and all three were:

- The catalogue's top speed was read as a **ceiling**. `move_toward` toward 200 m/s from an 800 m/s dive is a brake, so the punch spent itself slowing the player down. It is a floor now: the punch can always reach the quoted speed under its own power and never takes speed away from someone who brought their own.
- The fifty-metre reach was treated as a **lifetime**. At 600 m/s that is a twelfth of a second, so a dive from any real height spent its reach in the first fifty metres of the fall, handed the flight back, and came down as an ordinary landing. Reach is how far the punch carries under power, not how long it is allowed to last: a punch thrown out across the sky still gives the flight back when it runs out, but one aimed at the planet commits and rides it in. Committed by *time* to the ground rather than by distance — a second and a half of flight — because that is the quantity that scales with the thing it is about.
- Arrival was only ever noticed as a **slide collision**. At flight speed the body crosses sixteen metres in a frame, straight through a chunk collider without generating one. `_catch_ground`'s swept test already caught the tunnelling and quietly planted the body on the surface; the punch just was not listening to it. It is an arrival now, filtered by the same facing test a slide contact gets so a flat charge still skims the ground it is travelling over.

The hole then scales with the speed it was dug at, `sqrt` of the ratio to the quoted top speed and capped at twice — 12 m across and 5 m deep at the top end. Square root rather than linear because that is roughly how a real impact scales, and because the crater's footprint is terrain that has to be rebuilt: the cap keeps the biggest hole to four times the area rather than twenty-five. It costs almost nothing in practice — 28.6 ms against the ordinary punch's 27.8 — because the resolvability gate below means a wider mark still only invalidates the chunks fine enough to draw it.

Landing in the hole took two more things than having cut it, and both were the same mistake in different places: something describing ground that no longer existed. The height field drops the moment the scar is registered, but the **collider** is generated from the mesh and was only replaced when the rebuild landed a few frames later, so the body spent those frames standing on the surface it had just removed and then fell the crater's depth when the new collider arrived. Marking a chunk stale now retires its collider immediately; a mesh may lag the field by a frame without anyone noticing, but the thing bodies stand on may not, and the height-field guard is a floor in the meantime. The other half is that nothing pulled the body *down*. `_catch_ground` only ever pushes a body out of ground it has ended up inside, and for ordinary terrain that is right — ground falling away from under you is just falling. A crater is the one case where the ground moving is the point, so a landed punch watches for its own hole and plants the feet on it, over a window rather than in one go, because a host cuts the hole on the frame it asks and a client is granted it a round trip later.

**The boss digs craters too, and got caught in his own by the far end of that same disagreement.** A chunk's collider is a triangulation of the height field, so the two never quite agree, and the sag of one chord across a curve is the size of the error: inside a crater bowl — the sharpest thing anything cuts at the metre and a half chunks are built at — the flat chords stand a quarter of a metre *above* the curve they cross. Bigfoot carries no weight of his own, every state he has sets a velocity along the surface, and `_snap_to_ground` used to keep him on the ground by setting his distance from the planet's middle to the field's answer once a tick. On open ground that is invisible. Inside his own crater it planted him a quarter of a metre inside the wall on every tick, and the solver spent each following frame pushing him back out along a normal that points up and inward — against the direction he was leaving in, and worth most of a stride at a run. He would climb to about seven metres from the middle of a hole ten metres across, at a full sprint, and run there until the fight ended. The way down is a swept `move_and_collide` now, so it stops on the ground that is there rather than on the ground the field describes; the way up is still a teleport, because a body that has gone through the world has nothing left to sweep against, but it waits for a gap deeper than a chord can explain. Four of six craters held him before that and none do after. The runtime suite walks him out of a real one, and the headless suite stands him on a plate above the field, which is the same claim without needing a chunk to have built.

The pose is `MeteorFly` in `assets/source/blender/build_animations.py`, authored upright like the other two flight clips so that the game's own forward lean is what turns a raised arm into a punch. It leans and cross-fades far faster than a flight does: fifty metres are gone in under a second, and the flight's own easing would spend most of that standing the body back up in mid-air.

Ahead of the fist is the shock — `game/abilities/meteor_shock.gd` and `shaders/vivid/vivid_shock.gdshader`, a red bow wave standing off the punch the way a vapour cone stands off a plane going through the sound barrier. **Its radius is the fist's damage radius**, taken from the same constant, so what the player sees coming is exactly what the punch is about to cut and there is no second number to keep in step. The surface is a paraboloid built in code rather than a `SphereMesh`, because the shader places its travelling bands and both end fades by how far along the shell a fragment is and that has to be a number this side decides — and because a paraboloid is the right shape anyway, rounder at the nose than a cone and flatter at the skirt than a sphere. How far it is drawn out along the travel direction comes from the speed, so the shape itself reads as acceleration over the third of the reach the punch spends getting up to two hundred metres a second.

Almost all of the look is one Fresnel term. A shock is a surface, not a volume: face on there is nothing to see, and edge on you are looking through metres of squeezed air, which is why it reads as a bright rim around a clear middle — and why an eight-metre shell can sit between the player and the world without hiding any of it. The trailing circle is drawn separately from that, because on a shell this wide the Fresnel alone lights only the two points of the rim that happen to be edge on, and the ring is what the shape is read from when the camera is behind the punch, which is where the camera nearly always is. Blending is premultiplied alpha rather than additive for the reason the laser is two passes: additive alone disappears against bright ground, of which this planet is mostly made.

Like `LaserBeams`, it is driven from the player's presentation pass rather than from the ability, and for the same reason — the ability only exists on the machine that threw the punch. `Stance.METEOR` replicates like any other stance, so a remote punch is drawn by exactly the same code as a local one with nothing added to the wire. It is aimed along the velocity rather than the launch direction, which matters only at the one moment the two disagree: a ground charge that has run out of reach and started to fall wants its shock in front of where it is actually going.

### Over the network

Craters are few and cheap, so they are sent whole: any peer asks via `rpc_id(1)`, the host validates and broadcasts, and a client does not cut its own ground while it waits. Flora is the opposite — far too many instances to name — so what replicates is the **effect volume**, applied by every peer to its own deterministic flora, with the host additionally confirming the handful of break keys a few times a second in case they disagreed. Both the scar list and the accumulated breaks ride along in the join snapshot, so a late arrival sees the same battered ground.

### Checking it

Three headless suites and one that puts a real socket between two peers:

```powershell
godot --headless --path . dev/_ability_model_test.tscn
godot --headless --path . dev/_flora_damage_test.tscn
godot --headless --path . dev/_terrain_scar_test.tscn
godot --headless --path . dev/_ability_net_test.tscn
```

The model test covers the catalogue, the stat formatting, slot filters, cooldowns and the stance and underwater gating. The flora test proves the migrated health reproduces every previous break speed exactly, then streams real cover in and cuts it with a beam and a blast. The scar test is the one worth reading: it checks that the crater is in the *same* height field the mesh, the collider and the player's ground guard all use, which is a claim about the live planet rather than about a data structure. It then throws two real punches. One from a standing start, measured against the cratered field on the frame it lands and again once the rebuilt collider has arrived — the fall into one's own hole showed up as 1.7 m out on the first of those and 1.5 m lost between them. One out of a 600 m/s dive from 400 m up, which is the case that used to hand the flight back and land with no crater at all. That second one is worth reading for what it has to assert *before* the interesting part: a punch thrown from anything but a flight takes the other branch of a spent reach and lands whatever the flight branch does, so without a check that the player is actually flying, the test passes against the bug. Last it holds the beam down for a 260-frame sweep and watches the ground all round the player: every sample point still drawn, the eye never under the surface, and `floorless` never off zero. The sweep is what the standing single-scar case cannot show, because the fault only appears when rebuilds overlap one another. The net test runs a host, a client and a late joiner as three branches in one process and sends everything across ENet.

Watching a *rendered* sweep for the same thing was tried and thrown away, and the reason is worth keeping. Graded against the real sky it reported sixty holes that were all one patch of purple desert flowers, the sky here being much the same mauve; repainting the background a flat magenta fixed that and left it reporting nothing at all — including on a run with the visibility fault deliberately put back, and again with the quadtree walk slowed to 5 Hz to stretch the gap to a quarter of a second. Reading the framebuffer back stalls the harness below the rate it is trying to sample. A test that passes with a known fault in front of it is worse than no test, because its pass is the thing that stops you looking.

The visual half is `dev/_ability_shot.tscn`, which is not headless because the dummy renderer never draws a frame:

```powershell
godot --path . dev/_ability_shot.tscn
```

It photographs both abilities close up and at the distance they are played at, plus the mark each leaves once the effect is over. Each also gets a shot from off to one side, which is not a gameplay view and is not meant to be: the game is played from behind the player's own head, and that is the one angle at which a beam fired from that head is a dot rather than a line.

### What they cost

`dev/_ability_perf_test.tscn` measures the frame while an ability is being used against the same view standing still, and prices each of the pieces on its own, because a frame time says something is wrong and never what:

```powershell
godot --path . dev/_ability_perf_test.tscn
```

Both abilities now run at the idle frame cost, with one spike left at the moment a crater forms. Getting there was four things, and the first was worth more than the other three together:

**A mark only invalidates ground fine enough to draw it.** Every scar already fades out at vertex spacings too coarse to resolve it, which is what stops a two-metre burn aliasing into a spike. But `mark_region_stale` was marking every chunk whose footprint contained the burn — including the ancestors, up to root patches tens of thousands of vertices across — and `needs_script_build` was then routing each of those onto the per-vertex GDScript path to compute, slowly, the exact terrain it already had. One 2 m laser burn cost **550 ms of worker time** and a 64 ms frame, four times a second while the beam was held. Both now take the chunk's spacing into account, so a burn costs the one or two chunks that can show it. Average chunk build time across a session went from 6.9 ms to 1.6 ms.

**Plant roots are cached where the damage sweep can read them.** `MultiMesh.buffer` hands out a copy through the rendering server, and the volume walk was fetching one per stand just to ask whether anything was in range, which for almost every stand it was not. `Tile.roots` keeps the origins alongside the existing `glow_points` cache, so the question is answered without asking the server at all. Nothing moves a standing plant, so the cache holds until the tile is re-sown.

**And the buffer itself is never read back.** The paragraph above used to end by saying the buffer was fetched once a plant had actually been hit, which sounded like the cheap half of the problem and was in fact the expensive one. That getter is not a copy — it is a **round trip**: it has to catch up with the render thread before it can answer, and the wait is roughly the same whether the stand holds nine plants or nine thousand. Measured against this world it is about half a millisecond a call, and a volume dragged along the ground overlaps tens of stands: one tick of a meteor charge spent **16 ms doing nothing but waiting**, and the worst offenders were the fields holding the *fewest* plants, since a colony of three trees per tile pays the same half millisecond as a tile of five thousand blades of grass. `Tile.rows` now keeps what was uploaded, on this side of the server, and `_rows_of` is the only way in. The setter has no such cost — it queues the upload and returns — so writes are unchanged. A charge tick went from 16 ms to 7 ms, a trample stride from 9 ms to 0.5 ms, and a meteor landing over standing jungle from 38 ms to 14 ms. It costs about 38 MB of the 495 MB the session holds, nearly all of it the two grass fields, which is the price of not asking a question whose answer we already knew.

**None of which was visible headless, and that is the part worth remembering.** Headless streams a few hundred plants where a real session carries hundreds of thousands, and it has no render thread to wait for. Between them those two facts understated everything above by roughly fifty times, and the flora budgets in `dev/_bigfoot_perf_test.tscn` were being met for months by a run that was not touching a jungle at all. Run that suite both ways and believe the graphical one for anything involving cover.

**The rejection tests are arithmetic.** A volume is offered to seventeen fields holding three thousand streamed tiles between them, and cuts a dozen plants, so what matters is the cost of turning things away rather than the cost of the ones that stay. Tiles are rejected against the volume's bounding sphere before the capsule maths, plants against a squared distance that needs neither their height nor their up vector, and the whole flower-tree colony against one sphere. A beam volume went from 4.8 ms to 1.6 ms and a fist volume from 3.7 ms to 0.7 ms.

**The fist deals damage on a clock, not every tick.** The laser always ran its damage at 10 Hz because each turn is also a packet; the punch was sweeping at 60 Hz, which was eight milliseconds a frame for the whole flight. It is 20 Hz now, and since the volume is swept from where the fist was to where it is, a slower clock makes each capsule longer rather than leaving gaps. Single-player sessions also stopped serialising every one of those ticks through the RPC layer to deliver them back to themselves — an offline peer is still a peer, so `has_multiplayer_peer()` was the wrong question.

What is left is a single ~27 ms frame when a meteor crater lands, which is the terrain genuinely rebuilding: twelve chunks, their collision shapes, and the meshes going to the GPU. It is one dropped frame on the most violent thing in the game.

## Chat and voice

Both work anywhere a session is live. There is no separate waiting room in this template — hosting drops you straight into the world — so the two pieces live as autoloads rather than in a scene, show themselves whenever `NetworkManager.in_multiplayer_session()` is true, and go away again when you leave. They are on screen in the world, over the pause card, and would ride along into a lobby screen a project added later without being wired up again.

| Script | Holds |
| --- | --- |
| `core/chat_manager.gd` | The wire and the scrollback: sending, host validation, join and leave lines |
| `core/voice_chat.gd` | Push-to-talk: capture, compression, and a stream per talker |
| `ui/chat/chat_hud.gd` | The panel: the log, the line being typed, and who is talking |

**Enter** opens the line. Enter sends it, Escape throws it away — and Escape belongs to the field while it is open, so a half-typed message is not paid for with the pause menu. While the field has the keyboard the local player's controls are switched off: movement is polled rather than read from events, so a focused text field on its own would let W walk you away mid-sentence. Controls go back to what they were rather than to on, because chat can be opened over the inventory or a pause card that was already holding them.

The host is the authority on who said what. A client offers its line to the host, which paces it, moderates it with the same `core/text_moderation.gd` the lobby names use, and only then stamps it with the name from its own roster and sends it on, so a peer cannot put words in someone else's mouth. Someone arriving mid-conversation is handed the tail of the log; a blocked line is reported to its sender alone rather than repeated to the room.

**V**, held, talks. Godot ships no voice codec, so the compression here is deliberately plain: downmix, resample to 12 kHz, and one companded byte per sample on a square-law curve that spends its resolution on the quiet half of the range where speech lives. That costs 12 KB/s per talker for about 44 dB of signal to noise, and no dependencies. Packets are `unreliable_ordered`: a packet that arrives late is worth less than nothing, because waiting for it would delay everything behind it, so a lost one is left as a gap and the talker stays in real time.

Two details are load-bearing on the audio side. Capture runs on its own bus where the **order of the effects** keeps the microphone out of the speakers: the capture tap comes first and an amplifier at -80 dB comes after it, since muting that bus or pulling its volume down would silence the tap along with the output. And each talker is played through an `AudioStreamGenerator` fed from a short queue that holds back 100 ms before it starts — that prebuffer is what absorbs network jitter, and re-arming it when a talker goes quiet is what stops the next word arriving as a stutter. Voice plays on its own bus, so **Settings > Audio > Voice chat** rides on top of the master volume; the microphone needs `[audio] driver/enable_input` in `project.godot`, which is already set.

Voice is not positional: everyone in the session is heard at the same level wherever they are, which is what a co-op session usually wants. Making it spatial means moving the per-talker player to an `AudioStreamPlayer3D` on that peer's body, and deciding what should happen to a talker who has no body yet.

`dev/_comms_test.gd` drives both halves the way a player does, and measures the parts a screenshot cannot show:

```powershell
godot --path . dev/_comms_test.tscn
```

It types a line with real keystrokes and sends it, checks the body stays put while typing and walks again afterwards, checks V is a letter rather than the talk key while the field is open, and checks Escape closes the field without pausing — and, with the game already paused, that Escape closes the field and leaves it paused. Then it reports what the compression costs, plays a tone into the microphone bus to see it arrive at the capture tap at full level, holds the talk key over that tone to confirm audio is packetised at real time, feeds packets in as a second peer to watch a stream prime and drain, drives the real join and leave signals, and confirms leaving a session takes the panel, the scrollback and everyone's voice with it. Run it windowed: both halves need real devices.

That harness is one process with an offline peer, which makes it both ends of the wire at once and so cannot see the host doing its job. `dev/_chat_net_test.gd` is the other half, as a real client of a host in another process:

```powershell
godot --headless --path . -- --server --port=7777 --lobby-name="Chat Test"
godot --path . dev/_chat_net_test.tscn
```

It joins, waits for the announcement of its own arrival, says something, and checks the line comes back attributed to the name the **host** holds rather than one the client chose. Then it sends a burst to see the pacing drop most of it, and a line the moderation should stop, which comes back as a refusal addressed to nobody else.

## Multiplayer architecture

`SteamLobby` initializes GodotSteam, owns Steam lobby discovery/metadata, accepts friend-invite callbacks, and exposes the overlay invite dialog. `NetworkManager` owns the `SteamMultiplayerPeer`, admission, session state, scene changes, and the host-owned roster. `ChatManager` and `VoiceChat` are session-scoped in the same way and reject packets from peers that have not passed admission. Gameplay code talks to `NetworkManager`, not directly to the menu.

The host owns player spawning and validates/relays client movement snapshots. This starter is suitable for cooperative prototyping, but competitive games should replace snapshot validation with fully server-simulated input.

Hosting and starting are separate. Creating a Steam lobby opens a waiting room; connecting clients submit their profile and, for passworded lobbies, the password over Steam's encrypted transport. The host validates Steam membership and the password before adding that peer to the roster. Only the host can broadcast Start, which closes the lobby to late joins and opens the world for every admitted peer.

Public and passworded lobbies are discoverable in Steam's browser; friends-only lobbies are visible through Steam's relationship rules. Passwords are never lobby metadata. `+connect_lobby` launch arguments and in-game `join_requested` callbacks both return to the same Join UI, where a private invite asks for its password before connecting.
