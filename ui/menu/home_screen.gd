class_name HomeScreen
extends Node3D

## The home screen, which is the world itself seen from the spawn point rather
## than a scene in front of it. Nothing the player picks here changes scene: the
## planet, the sun and the starfield are already the ones they will be playing in,
## and the character on the left is standing where they will start.
##
## That is the whole reason this is a Node3D living under the world instead of a
## Control living on its own. Rebuilding the planet's quadtree behind a menu costs
## seconds, so any cut between "home screen" and "playing" would be a cut the
## player could see. Here, New Game is a camera move.
##
## Three views, each a camera pose over the same scene:
##   HOME      character to the left, planet to the right, menu under it
##   ONLINE    Steam create/join frame over the live planet
##   SETTINGS  the shared red settings card over the Tab menu background

signal handed_over

const PALETTE: UIPalette = preload("res://ui/themes/ui_palette.tres")

enum View { HOME, ONLINE, SETTINGS, CHARACTER, UPGRADES, ACHIEVEMENTS, HATS }

## Camera poses, in the spawn point's frame: metres from the spawn, then degrees
## of yaw and pitch (positive is up) off its facing, and the field of view. The
## rows are indexed by View for HOME/ONLINE/SETTINGS; CHARACTER reuses HOME.
##
## Three things about the HOME row are worked out rather than picked, because the
## spawn is nine kilometres above a planet eight across and that fixes most of it:
##
##   - The planet subtends 56 degrees from here. No amount of yaw turns something
##     that wide into the contained ball the mock-up draws, so the field of view
##     is opened to 90 rather than the planet being moved; at 90 it covers about
##     three fifths of the frame's height and reads as a globe.
##   - The character is metres away and the planet is kilometres away, so the only
##     thing that can separate them across the frame is parallax. Standing the
##     camera a metre and a half to the side throws the character 60 degrees off
##     the planet's bearing; the yaw then slides the pair over until the character
##     sits a quarter of the way in and the planet fills the right.
##   - Pitching down lifts the planet in the frame, which is what opens the dark
##     sky under it for the menu.
##   - The camera's height is the character's own centre and not the pitch's, and
##     those are two different jobs on this shot. Pitch decides where in the
##     frame things land; height decides what angle the near one is seen from,
##     because the planet is nine kilometres off and does not move for a camera
##     that rises a metre. Raised to 1.7 to sit level with the pitch, the camera
##     looked 25 degrees down onto a figure whose middle is at 0.9, and the home
##     screen showed the top of its head. Dropping to the figure's own height
##     rides it up the frame, which the shorter pitch then pays for.
##   - The HOME row was moved in until the figure fills three fifths of the frame
##     rather than two fifths, and the height went **up** to pay for it. Those are
##     the same two dials as above doing the same two jobs: coming in makes the
##     figure bigger about wherever it already was, and at this size that put the
##     hair through the top edge; rising drops the whole figure down the frame and
##     leaves the planet where it was, because nine kilometres does not care about
##     a foot of camera. Reaching for the pitch instead is the mistake — it would
##     have brought the planet down with it and closed the band the menu sits in.
##     The head now lands about a sixth of the way down and the feet three
##     quarters, which leaves the name plate and the menu row the bottom quarter.
const POSE_OFFSETS := [
	Vector3(1.50, 1.15, 0.77),
	Vector3(0.0, 2.2, -2.0),
	Vector3(-2.0, 1.2, 3.5),
]
const POSE_YAWS := [30.0, 0.0, 180.0]
const POSE_PITCHES := [-12.0, 8.0, 12.0]

## How far off dead-on the figure stands. Float draws one knee up and across the
## other, and that is the whole silhouette that says hovering rather than
## standing — but it is drawn up *forward*, so a camera square to the chest
## foreshortens it to nothing and the pose reads as a body at attention. A turn
## of this much still shows the face, which is what the low camera was for, and
## opens the knee. It also turns the figure into the frame rather than out of it.
const PREVIEW_TURN := -32.0
const POSE_FOVS := [90.0, 62.0, 58.0]

## Type over space is outlined in near-black rather than in the palette's own
## ink: the planet's lit face passes under this text as the camera moves, and a
## deep indigo on a pale limb is not a strong enough edge to hold the letterforms
## apart.
const SKY_OUTLINE := Color(0.02, 0.01, 0.03, 0.92)
## Side of the pencil beside the name field, in pixels.
const PENCIL_SIZE := 34.0

## Mode cards remain for Online host setup. The home Start Game button
## launches crawler directly. The identifier is stored in
## NetworkManager.session_options even before the modes grow different rules, so
## save files and future mode systems do not have to infer it from a button label.
const MODES: Array[Dictionary] = [
	{
		"label": "Story Mode",
		"id": "story",
		"description": "Explore the planet and follow its story.",
	},
	{
		"label": "Crawler Mode",
		"id": "crawler",
		"description": "Push through hostile sites as an expedition.",
	},
	{
		"label": "Duels Mode",
		"id": "duels",
		"description": "Compete in Battle or Race rounds.",
	},
	{
		"label": "Sandbox Mode",
		"id": "sandbox",
		"description": "Crawler rules, plus Tab-menu tools to quiet mobs, go invincible, fly fast, and spend freely.",
	},
]
const DUELS_MODES: Array[Dictionary] = [
	{"label": "Battle", "id": "battle"},
	{"label": "Race", "id": "race"},
]

const TITLE_ART := preload("res://ui/menu/my_strange_planet_title.png")
const SETTINGS_BACKGROUND := preload("res://assets/runtime/ui/menu_background.png")
## The logo is a terrain-following patch, measured in degrees around the globe.
## Its wide arc visibly turns away at both ends instead of reading as a flat card.
const PLANET_TITLE_ARC := Vector2(104.0, 58.0)
const PLANET_TITLE_OFFSET := Vector2(4.0, 14.0)
const PLANET_TITLE_GRID := Vector2i(32, 18)
## Clear enough of coarse terrain LOD to avoid z-fighting, but still hundreds of
## metres beneath the cloud deck so weather naturally crosses in front of it.
const PLANET_TITLE_CLEARANCE := 32.0
const HOME_RED := Color("ef151f")
const HOME_RED_BRIGHT := Color("ff3445")
const HOME_RED_TEXT := Color("ff9ca4")
const HOME_RED_MUTED := Color("b94a53")
const HOME_GREEN := Color("45df68")
const HOME_GREEN_TEXT := Color("59ff7a")
const HOME_BLACK := Color(0.0, 0.0, 0.0, 0.78)
const HOME_ACTION_FONT_SIZE := 28
const MODE_PANEL_HEIGHT := 226.0

## Two text rows at the foot of the window, and how far the stack sits off
## the bottom edge. The actions stretch across most of the window so the
## longer labels keep their first and last letters.
const MENU_ROW_HEIGHT := 36.0
const MENU_ROW_GAP := 4.0
const MENU_STACK_HEIGHT := 76.0
const MENU_ROW_INSET := 28.0
const MENU_SIDE_INSET := 40.0
const MENU_ACTION_GAP := 36.0
const MENU_ACTION_MIN_WIDTH := 160.0
const MENU_ACTION_PAD_X := 26.0
const MENU_ACTION_CRT_PAD := 18.0
## Horizontally centred, at the preview figure's feet — about three quarters
## down the frame, not on the window's bottom edge.
const LOADING_BAR_WIDTH := 248.0
const LOADING_BAR_HEIGHT := 10.0
const LOADING_BAR_ANCHOR_Y := 0.76
## Share of the window the character editor's card is allowed, measured from the
## right edge. The rest is the figure, which is the whole reason the editor has no
## preview of its own — see [method _character_editor].
const EDITOR_CARD_SHARE := 0.58
## Where a screen's card starts: below the upper navigation band for full-width
## pages. The illustrated title itself belongs to HOME and is hidden on pages.
## `dev/_menu_shot.tscn` prints what the card wants against what it is given.
const TITLE_BAND := 136.0
## Higher again since the editor grew a tab strip, which is 54 px the card has to
## find from somewhere.
const EDITOR_TOP := 52.0

const MOVE_TIME := 0.85
## The sweep from the home pose to behind the character. Long enough to read as a
## camera move, short enough not to be a cutscene.
const HANDOVER_TIME := 1.15
const FADE_IN_TIME := 0.9
const SCREEN_FADE_TIME := 0.35
const SCREEN_FADE_DELAY := MOVE_TIME * 0.45
const SPIN_PER_PIXEL := 0.008
## Front key for the preview figure. The lamp sits on the camera's side of the
## face rather than along the lens: the home shot looks at the planet, so a
## camera-forward cone only grazes the head. Energy rises once the sun leaves
## the face, and the range stays short so the planet is not recast.
const PREVIEW_FILL_DAY := 1.6
const PREVIEW_FILL_NIGHT := 5.4
const PREVIEW_FILL_STANDOFF := 0.58

## Set by the world before this enters the tree: the spawn the local player will
## use, and the frame every camera pose is measured in.
var frame := Transform3D.IDENTITY

var _camera: Camera3D
var _preview_fill: SpotLight3D
var _preview: Node3D
## The facing the preview was built with, kept apart from the drag so a spin is
## always measured from where the character was put rather than from itself.
var _preview_rest := Basis.IDENTITY
var _preview_spin := 0.0
var _dragging := false

var _view := View.HOME
var _layer: CanvasLayer
var _root: Control
var _settings_background: TextureRect
var _title: MeshInstance3D
var _title_material: StandardMaterial3D
var _menu: VBoxContainer
## New Game opens a two-stage panel: mode cards, then mode settings and an
## explicit Start Game action.
var _picking_mode := false
var _selected_home_mode := ""
var _selected_home_duels_mode := "battle"
var _mode_panel: PanelContainer
var _mode_content: VBoxContainer
var _back: Button
var _screen_host: MarginContainer
var _screen: Control
var _notice: Label
var _gems: Label
var _fade: ColorRect
var _move: Tween
var _background_fade: Tween

var _handover_from := Transform3D.IDENTITY
var _handover_fov := 0.0
var _handover_at := 0.0
var _handover_target: OnlinePlayer
var _body_from := Basis.IDENTITY
var _awaiting_player := false
## Raised while the invisible pre-game warm-up is running. The menu remains
## unchanged, but a second New Game must not start another warm-up beside it.
var _warming := false
var _loading_bar: StartLoadingBar
var _loading_note: Label
var _loading_block: ColorRect
var _preview_hold_speed := 1.0
var _edit_button: Button
var _name_row: VBoxContainer
var _name_field: LineEdit
var _rank_label: Label
var _look: Dictionary = {}
## The containers the character editor is built against, held here rather than in
## the screen so the look survives the editor being closed and opened again.
var _worn_slots: ItemContainer
var _apparel_rail: ItemContainer
var _designer: PlayerDesignerPanel
## Stocking a container fires its changed signal, which is the same signal the
## player dragging a garment fires; without this the editor would read its own
## restock back as a change and write it out again.
var _stocking := false


func _ready() -> void:
	_build_camera()
	_build_planet_title()
	_build_preview()
	_build_overlay()
	_apply_pose(_view, true)
	Input.mouse_mode = Input.MOUSE_MODE_VISIBLE
	NetworkManager.session_started.connect(_on_session_started)
	NetworkManager.status_changed.connect(_on_status_changed)
	NetworkManager.invite_received.connect(_on_steam_invite_received)
	if NetworkManager.has_pending_invite():
		call_deferred("show_view", View.ONLINE)


func _exit_tree() -> void:
	if NetworkManager.session_started.is_connected(_on_session_started):
		NetworkManager.session_started.disconnect(_on_session_started)
	if NetworkManager.status_changed.is_connected(_on_status_changed):
		NetworkManager.status_changed.disconnect(_on_status_changed)
	if NetworkManager.invite_received.is_connected(_on_steam_invite_received):
		NetworkManager.invite_received.disconnect(_on_steam_invite_received)


func _process(delta: float) -> void:
	if _awaiting_player:
		# On a join the local body arrives with the host's spawn broadcast, which
		# is some frames after the session says it has started.
		var player := _world().local_player()
		if player != null:
			_awaiting_player = false
			_begin_handover(player)
	if _handover_target != null:
		_advance_handover(delta)
	_update_preview_fill()


func _unhandled_input(event: InputEvent) -> void:
	if event.is_action_pressed("pause") and _handover_target == null:
		if _view == View.HOME and _picking_mode:
			_pick_mode(false)
			get_viewport().set_input_as_handled()
		elif _view != View.HOME:
			show_view(View.HOME)
			get_viewport().set_input_as_handled()
		return
	# Turnable while the editor is open as well as from the home view: with no
	# preview of its own, the figure standing in the world *is* the editor's
	# model, and being able to look at its back is most of what dressing one is.
	if (_view != View.HOME and _view != View.CHARACTER) or _handover_target != null:
		return
	if event is InputEventMouseButton and event.button_index == MOUSE_BUTTON_LEFT:
		_dragging = event.pressed
	elif event is InputEventMouseMotion and _dragging:
		# Direct manipulation: the model follows the pointer instead of turning
		# against it.
		_preview_spin += event.relative.x * SPIN_PER_PIXEL
		_apply_preview_basis()


# --- The scene ---------------------------------------------------------------


func _build_camera() -> void:
	_camera = Camera3D.new()
	_camera.name = "MenuCamera"
	# The planet is nine kilometres off and eight across, so the far plane is the
	# player camera's rather than the default fifty metres.
	_camera.near = 0.05
	_camera.far = 60000.0
	add_child(_camera)
	_camera.current = true
	_build_preview_fill()


## Sits on the menu camera so the figure is always lit from the viewer's side,
## including the character editor that reuses this pose.
func _build_preview_fill() -> void:
	if _camera == null or _camera.get_node_or_null("PreviewFillLight") != null:
		return
	var fill := SpotLight3D.new()
	fill.name = "PreviewFillLight"
	fill.light_energy = PREVIEW_FILL_NIGHT
	fill.light_color = Color(1.0, 0.96, 0.90)
	fill.light_specular = 0.18
	fill.spot_range = 8.0
	fill.spot_attenuation = 0.32
	fill.spot_angle = 48.0
	fill.shadow_enabled = false
	# Same mask as the other character lamps: every layer except terrain.
	fill.light_cull_mask = 0xFFFFD
	_preview_fill = fill
	_camera.add_child(fill)


## How bright the front key is for a given amount of remaining daylight.
## Night is 0, noon is 1. Exposed so the loadout test can check the night
## boost without standing a planet up.
static func preview_fill_energy(daylight: float) -> float:
	return lerpf(PREVIEW_FILL_NIGHT, PREVIEW_FILL_DAY, clampf(daylight, 0.0, 1.0))


func _update_preview_fill() -> void:
	if _preview_fill == null or _camera == null:
		return
	if _handover_target != null:
		_preview_fill.light_energy = 0.0
		return
	var face := _preview_face_point()
	var to_camera := _camera.global_position - face
	if to_camera.length_squared() < 0.0001:
		return
	var toward := to_camera.normalized()
	_preview_fill.global_position = face + toward * PREVIEW_FILL_STANDOFF
	var up := frame.basis.y
	if absf(up.dot(toward)) > 0.96:
		up = _camera.global_basis.x
	_preview_fill.look_at(face, up)
	_preview_fill.light_energy = preview_fill_energy(_preview_daylight())


func _preview_face_point() -> Vector3:
	var up := frame.basis.y
	if is_instance_valid(_preview):
		var skeleton := Wardrobe.skeleton_of(_preview)
		var head := CharacterRig.find_bone(skeleton, &"Head")
		if skeleton != null and head >= 0:
			return skeleton.to_global(skeleton.get_bone_global_pose(head).origin)
		return _preview.global_position + up * 1.35
	return frame.origin + up * 1.35


func _preview_daylight() -> float:
	var world := _world()
	if world == null or world.celestial_cycle == null:
		return 0.0
	var up := frame.basis.y
	var planet := world.planet()
	if planet != null:
		up = (frame.origin - planet.global_position).normalized()
	return smoothstep(-6.0, 18.0, world.celestial_cycle.local_elevation_degrees(up))


## Wraps the unchanged logo PNG across the actual height field. The title is
## transparent geometry rather than Canvas UI so the cloud and atmosphere shells,
## whose render priorities are 1 and 2, can paint naturally over its priority 0.
func _build_planet_title() -> void:
	var planet := _world().planet()
	if planet == null or planet.shape == null:
		return

	var home_pose := _pose(View.HOME)
	var face := planet.to_local(home_pose.origin).normalized()
	var inverse_planet_basis := planet.global_basis.inverse()
	var screen_right := (inverse_planet_basis * home_pose.basis.x).slide(face)
	var screen_up := (inverse_planet_basis * home_pose.basis.y).slide(face)
	if screen_right.length_squared() < 0.0001 or screen_up.length_squared() < 0.0001:
		return
	screen_right = screen_right.normalized()
	screen_up = screen_up.normalized()

	var centre := (
		face
		+ screen_right * tan(deg_to_rad(PLANET_TITLE_OFFSET.x))
		+ screen_up * tan(deg_to_rad(PLANET_TITLE_OFFSET.y))
	).normalized()
	var right := screen_right.slide(centre).normalized()
	var up := screen_up.slide(centre).slide(right).normalized()
	if up.length_squared() < 0.0001:
		up = centre.cross(right).normalized()
	if up.dot(screen_up) < 0.0:
		up = -up

	var vertices := PackedVector3Array()
	var normals := PackedVector3Array()
	var uvs := PackedVector2Array()
	var indices := PackedInt32Array()
	var columns := PLANET_TITLE_GRID.x
	var rows := PLANET_TITLE_GRID.y
	var half_arc := PLANET_TITLE_ARC * (PI / 360.0)
	var inverse_home_basis := global_basis.inverse()

	for row in rows + 1:
		var v := float(row) / float(rows)
		var vertical_angle := lerpf(half_arc.y, -half_arc.y, v)
		for column in columns + 1:
			var u := float(column) / float(columns)
			var horizontal_angle := lerpf(-half_arc.x, half_arc.x, u)
			var direction := (
				centre
				+ right * tan(horizontal_angle)
				+ up * tan(vertical_angle)
			).normalized()
			var surface := planet.shape.surface_point(direction)
			var world_position := planet.to_global(
				surface + direction * PLANET_TITLE_CLEARANCE
			)
			var world_normal := (planet.global_basis * direction).normalized()
			vertices.append(to_local(world_position))
			normals.append((inverse_home_basis * world_normal).normalized())
			uvs.append(Vector2(u, v))

	for row in rows:
		for column in columns:
			var corner := row * (columns + 1) + column
			var below := corner + columns + 1
			indices.append(corner)
			indices.append(below)
			indices.append(corner + 1)
			indices.append(corner + 1)
			indices.append(below)
			indices.append(below + 1)

	var arrays: Array = []
	arrays.resize(Mesh.ARRAY_MAX)
	arrays[Mesh.ARRAY_VERTEX] = vertices
	arrays[Mesh.ARRAY_NORMAL] = normals
	arrays[Mesh.ARRAY_TEX_UV] = uvs
	arrays[Mesh.ARRAY_INDEX] = indices
	var mesh := ArrayMesh.new()
	mesh.add_surface_from_arrays(Mesh.PRIMITIVE_TRIANGLES, arrays)

	_title_material = StandardMaterial3D.new()
	_title_material.resource_name = "PlanetTitleMaterial"
	_title_material.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	_title_material.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	_title_material.cull_mode = BaseMaterial3D.CULL_DISABLED
	_title_material.albedo_texture = TITLE_ART
	_title_material.albedo_color = Color.WHITE
	_title_material.disable_receive_shadows = true
	_title_material.render_priority = 0

	_title = MeshInstance3D.new()
	_title.name = "MyStrangePlanetTitle"
	_title.mesh = mesh
	_title.material_override = _title_material
	_title.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	add_child(_title)


func _build_preview() -> void:
	_look = CharacterDB.load_look()
	_spawn_preview()


func _spawn_preview() -> void:
	var spin := _preview_spin
	var rest := _preview_rest
	if is_instance_valid(_preview):
		_preview.queue_free()
		_preview = null
	var packed := CharacterDB.scene(str(_look.get("body", CharacterDB.DEFAULT_BODY)))
	if packed == null:
		return
	_preview = packed.instantiate() as Node3D
	_preview.name = "PreviewCharacter"
	add_child(_preview)
	CharacterRig.normalize_body(_preview)
	SurfaceSkin.apply(_preview, true)
	_dress_preview()
	_preview.global_position = frame.origin
	if rest != Basis.IDENTITY:
		_preview_rest = rest
		_preview_spin = spin
		_apply_preview_basis()
	else:
		_face_camera()
	# The spawn hangs in orbit with nothing under it, so the body that stands
	# there is floating, and so is the one the player takes over.
	var animator := CharacterRig.animator_of(_preview)
	if animator != null:
		CharacterRig.prepare(animator, CharacterDB.extra_animation_paths(
			str(_look.get("body", CharacterDB.DEFAULT_BODY))))
		var clip := CharacterRig.resolve_clip(animator, "Float")
		if animator.has_animation(clip):
			animator.play(clip)


## Re-dresses the figure from scratch every time, garments and all. A tint
## multiplies the albedo it lands on, so laying a second one over the first would
## give the product of the two rather than the second; stripping back to the
## authored colours first is what makes picking a colour repeatable.
func _dress_preview() -> void:
	if not is_instance_valid(_preview):
		return
	var worn: Dictionary = _look.get("worn", {})
	for slot: String in ItemDB.SLOT_ORDER:
		Wardrobe.unequip(_preview, slot)
	SurfaceSkin.apply(_preview, true)
	var body_id := CharacterDB.sanitize_body(str(_look.get("body", CharacterDB.DEFAULT_BODY)))
	var skin_id := CharacterDB.sanitize_skin(body_id, str(_look.get("skin", "")))
	SurfaceSkin.set_body_texture(_preview, CharacterDB.skin_texture(body_id, skin_id))
	for slot: String in worn:
		var item_id := str(worn[slot])
		if item_id.is_empty() or not ItemDB.has_item(item_id):
			continue
		var garment := Wardrobe.equip(_preview, str(slot), ItemDB.scene_path(item_id))
		if garment != null:
			SurfaceSkin.paint(garment, {}, true)
	var tints: Dictionary = _look.get("tints", {})
	if tints.has("body"):
		var body_tint := Color.html(str(tints["body"]))
		for node in _preview.find_children("*", "MeshInstance3D", true, false):
			var mesh_instance := node as MeshInstance3D
			if String(mesh_instance.name).begins_with(Wardrobe.NODE_PREFIX):
				continue
			SurfaceSkin.tint(mesh_instance, body_tint)
	for slot: String in ItemDB.SLOT_ORDER:
		if not tints.has(slot):
			continue
		for node in _preview.find_children(Wardrobe.NODE_PREFIX + slot, "MeshInstance3D", true, false):
			SurfaceSkin.tint(node as MeshInstance3D, Color.html(str(tints[slot])))
	SurfaceSkin.apply_outline_tint(_preview, tints)


## Turned to face the home camera and then PREVIEW_TURN off it, flattened against
## the spawn's up so the body stays upright however the pose is angled.
func _face_camera() -> void:
	var up := frame.basis.y
	var to_camera := _pose(View.HOME).origin - frame.origin
	to_camera -= up * to_camera.dot(up)
	if to_camera.length_squared() < 0.0001:
		return
	_preview.look_at(frame.origin + to_camera, up)
	_preview.global_basis = _preview.global_basis * Basis(Vector3.UP, deg_to_rad(PREVIEW_TURN))
	_preview_rest = _preview.global_basis
	_apply_preview_basis()


func _apply_preview_basis() -> void:
	if is_instance_valid(_preview):
		_preview.global_basis = _preview_rest * Basis(Vector3.UP, _preview_spin)


func _pose(view: int) -> Transform3D:
	var basis := frame.basis \
		* Basis(Vector3.UP, deg_to_rad(POSE_YAWS[view])) \
		* Basis(Vector3.RIGHT, deg_to_rad(POSE_PITCHES[view]))
	return Transform3D(basis, frame * POSE_OFFSETS[view])


func _apply_pose(view: int, immediate: bool) -> void:
	var target := _pose(view)
	if immediate:
		_camera.global_transform = target
		_camera.fov = POSE_FOVS[view]
		return
	if _move != null and _move.is_valid():
		_move.kill()
	_move = create_tween().set_parallel(true)
	_move.set_trans(Tween.TRANS_CUBIC).set_ease(Tween.EASE_IN_OUT)
	_move.tween_property(_camera, "global_transform", target, MOVE_TIME)
	_move.tween_property(_camera, "fov", POSE_FOVS[view], MOVE_TIME)


# --- The overlay -------------------------------------------------------------


func _build_overlay() -> void:
	_layer = CanvasLayer.new()
	_layer.layer = 10
	add_child(_layer)

	_root = Control.new()
	_root.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	_root.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_root.theme = preload("res://ui/themes/main_theme.tres")
	_layer.add_child(_root)

	_settings_background = TextureRect.new()
	_settings_background.name = "SettingsBackground"
	_settings_background.texture = SETTINGS_BACKGROUND
	_settings_background.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	_settings_background.stretch_mode = TextureRect.STRETCH_SCALE
	_settings_background.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_settings_background.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	_settings_background.visible = false
	_root.add_child(_settings_background)

	# The artwork belongs to HOME only, so BACK keeps a stable upper-left home of
	# its own rather than moving with the curved planet title.
	_back = _sky_button("BACK", func() -> void: show_view(View.HOME))
	_back.set_anchors_and_offsets_preset(Control.PRESET_TOP_LEFT)
	_back.position = Vector2(56.0, 54.0)
	_back.visible = false
	_root.add_child(_back)

	# Two centred rows of bare type along the foot of the window. The figure
	# owns the middle of the frame, so the actions stay low and do not sit on
	# a plate.
	_menu = VBoxContainer.new()
	_menu.name = "HomeMenu"
	_menu.set_anchors_preset(Control.PRESET_BOTTOM_WIDE)
	_menu.offset_left = MENU_SIDE_INSET
	_menu.offset_top = -(MENU_STACK_HEIGHT + MENU_ROW_INSET)
	_menu.offset_right = -MENU_SIDE_INSET
	_menu.offset_bottom = -MENU_ROW_INSET
	_menu.alignment = BoxContainer.ALIGNMENT_CENTER
	_menu.add_theme_constant_override("separation", MENU_ROW_GAP)
	_root.add_child(_menu)
	_fill_menu_row()
	_build_mode_panel()

	_build_name_row()

	# A margin rather than a centring container: screens are told how tall they
	# may be and fill it, instead of growing to their contents and being centred
	# past both edges of the window when the contents are taller than it.
	_screen_host = MarginContainer.new()
	_screen_host.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	# Clear of the upper navigation band.
	_screen_host.offset_top = TITLE_BAND
	_screen_host.offset_bottom = -28.0
	_screen_host.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_root.add_child(_screen_host)

	_notice = _sky_label("", 16)
	_notice.set_anchors_preset(Control.PRESET_BOTTOM_WIDE)
	_notice.offset_top = -38.0
	_notice.offset_bottom = -12.0
	_notice.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_notice.visible = false
	_root.add_child(_notice)

	_gems = _sky_label("0 GEMS", 22)
	_gems.name = "HomeGemCounter"
	_gems.set_anchors_preset(Control.PRESET_TOP_RIGHT)
	_gems.offset_left = -240.0
	_gems.offset_top = 18.0
	_gems.offset_right = -36.0
	_gems.offset_bottom = 52.0
	_gems.horizontal_alignment = HORIZONTAL_ALIGNMENT_RIGHT
	_gems.add_theme_color_override("font_color", HOME_GREEN_TEXT)
	_gems.visible = false
	_root.add_child(_gems)
	_refresh_gem_counter()

	# There is no boot sheet any more: the first thing the game shows is this
	# scene, and it fades up out of the dark the starfield is already made of.
	_fade = ColorRect.new()
	_fade.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	_fade.color = Color(0.004, 0.006, 0.016)
	_fade.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_root.add_child(_fade)
	_build_start_loading()
	CrtType.watch(_root)
	create_tween().tween_property(_fade, "modulate:a", 0.0, FADE_IN_TIME) \
		.set_trans(Tween.TRANS_SINE)


func _build_start_loading() -> void:
	_loading_block = ColorRect.new()
	_loading_block.name = "StartLoadingBlocker"
	_loading_block.color = Color(0.0, 0.0, 0.0, 0.0)
	_loading_block.mouse_filter = Control.MOUSE_FILTER_STOP
	_loading_block.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	_loading_block.visible = false
	_root.add_child(_loading_block)
	_loading_bar = StartLoadingBar.new()
	_loading_bar.anchor_left = 0.5
	_loading_bar.anchor_right = 0.5
	_loading_bar.anchor_top = LOADING_BAR_ANCHOR_Y
	_loading_bar.anchor_bottom = LOADING_BAR_ANCHOR_Y
	_loading_bar.offset_left = -LOADING_BAR_WIDTH * 0.5
	_loading_bar.offset_right = LOADING_BAR_WIDTH * 0.5
	_loading_bar.offset_top = -LOADING_BAR_HEIGHT * 0.5
	_loading_bar.offset_bottom = LOADING_BAR_HEIGHT * 0.5
	_loading_bar.visible = false
	_root.add_child(_loading_bar)
	_loading_note = Label.new()
	_loading_note.name = "StartLoadingNote"
	_loading_note.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_loading_note.vertical_alignment = VERTICAL_ALIGNMENT_TOP
	_loading_note.anchor_left = 0.5
	_loading_note.anchor_right = 0.5
	_loading_note.anchor_top = LOADING_BAR_ANCHOR_Y
	_loading_note.anchor_bottom = LOADING_BAR_ANCHOR_Y
	_loading_note.offset_left = -220.0
	_loading_note.offset_right = 220.0
	_loading_note.offset_top = LOADING_BAR_HEIGHT * 0.5 + 10.0
	_loading_note.offset_bottom = LOADING_BAR_HEIGHT * 0.5 + 36.0
	_loading_note.add_theme_font_size_override("font_size", 16)
	_loading_note.add_theme_color_override("font_color", Color(0.86, 0.90, 0.84))
	_loading_note.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_loading_note.visible = false
	_root.add_child(_loading_note)


## The permanent home actions, split across two rows of CRT type.
func _fill_menu_row() -> void:
	for child in _menu.get_children():
		_menu.remove_child(child)
		child.queue_free()
	var rows: Array = [
		[
			{
				"name": "HomeNewGame",
				"label": "Start Game",
				"callback": func() -> void: start_new_game("crawler"),
			},
			{
				"name": "HomeLoad",
				"label": "Load",
				"callback": func() -> void: start_saved_game(),
			},
			{
				"name": "HomeOnline",
				"label": "Online",
				"callback": func() -> void: show_view(View.ONLINE),
			},
			{
				"name": "HomeSandbox",
				"label": "Sandbox",
				"callback": func() -> void: start_new_game("sandbox"),
			},
		],
		[
			{
				"name": "HomeUpgrades",
				"label": "Unlocks",
				"callback": func() -> void: show_view(View.UPGRADES),
			},
			{
				"name": "HomeAchievements",
				"label": "Achievements",
				"callback": func() -> void: show_view(View.ACHIEVEMENTS),
			},
			{
				"name": "HomeSettings",
				"label": "Settings",
				"callback": func() -> void: show_view(View.SETTINGS),
			},
			{
				"name": "HomeQuit",
				"label": "Quit",
				"callback": func() -> void: get_tree().quit(),
				"destructive": true,
			},
		],
	]
	for row_index in rows.size():
		var row := HBoxContainer.new()
		row.name = "HomeMenuRow%d" % (row_index + 1)
		row.alignment = BoxContainer.ALIGNMENT_CENTER
		row.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		row.add_theme_constant_override("separation", int(MENU_ACTION_GAP))
		_menu.add_child(row)
		for action: Dictionary in rows[row_index]:
			var button := _home_action_button(
				String(action["label"]),
				action["callback"] as Callable,
				bool(action.get("destructive", false))
			)
			button.name = String(action["name"])
			if String(action["name"]) == "HomeSandbox":
				_style_sandbox_button(button)
			if String(action["name"]) == "HomeLoad":
				_style_load_button(button)
			row.add_child(button.crt_host())


func _build_mode_panel() -> void:
	_mode_panel = PanelContainer.new()
	_mode_panel.name = "NewGameModePanel"
	_mode_panel.set_anchors_preset(Control.PRESET_BOTTOM_WIDE)
	_mode_panel.offset_left = 44.0
	_mode_panel.offset_top = -(MODE_PANEL_HEIGHT + 36.0)
	_mode_panel.offset_right = -44.0
	_mode_panel.offset_bottom = -36.0
	_mode_panel.add_theme_stylebox_override(
		&"panel",
		_home_style(HOME_BLACK, Color(HOME_RED_BRIGHT, 0.98), 2, 12.0)
	)
	var glow := RedGlowPanel.add_to(_mode_panel)
	glow.fill_color = Color(0.0, 0.0, 0.0, 0.50)
	glow.border_color = Color(HOME_RED_BRIGHT, 0.98)
	glow.border_width = 2.0
	glow.glow_intensity = 1.35
	glow.glow_spread = 10.0
	glow.glow_layers = 5
	_root.add_child(_mode_panel)

	_mode_content = VBoxContainer.new()
	_mode_content.name = "NewGameModeContent"
	_mode_content.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_mode_content.size_flags_vertical = Control.SIZE_EXPAND_FILL
	_mode_content.add_theme_constant_override(&"separation", 8)
	_mode_panel.add_child(_mode_content)
	_mode_panel.visible = false


func _rebuild_mode_panel() -> void:
	if _mode_content == null:
		return
	for child: Node in _mode_content.get_children():
		_mode_content.remove_child(child)
		child.queue_free()

	var header := HBoxContainer.new()
	header.name = "NewGameHeader"
	header.add_theme_constant_override(&"separation", 10)
	var title_text := (
		"NEW GAME  //  SELECT GAME MODE"
		if _selected_home_mode.is_empty()
		else "NEW GAME  //  MODE SETTINGS"
	)
	var title := _home_label(title_text, 22, HOME_GREEN_TEXT)
	title.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	header.add_child(title)
	var back := _home_button(
		"BACK",
		_back_to_mode_cards if not _selected_home_mode.is_empty()
			else func() -> void: _pick_mode(false)
	)
	back.name = "NewGameBack"
	back.custom_minimum_size = Vector2(124.0, 38.0)
	header.add_child(back)
	_mode_content.add_child(header)
	_mode_content.add_child(_home_rule())

	if _selected_home_mode.is_empty():
		_build_mode_cards()
	else:
		_build_mode_settings()


func _build_mode_cards() -> void:
	var row := HBoxContainer.new()
	row.name = "HomeModeCards"
	row.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	row.size_flags_vertical = Control.SIZE_EXPAND_FILL
	row.add_theme_constant_override(&"separation", 10)
	_mode_content.add_child(row)
	for mode: Dictionary in MODES:
		var mode_id := String(mode["id"])
		var locked := mode_id == "sandbox" and not CrawlerMeta.sandbox_unlocked()
		var card := _home_mode_card(
			mode,
			false,
			func() -> void: _select_home_mode(mode_id),
			locked
		)
		card.name = "HomeMode_%s" % mode_id
		if locked:
			card.disabled = true
			card.tooltip_text = "Reach your first city to unlock Sandbox."
		row.add_child(card)


func _build_mode_settings() -> void:
	var row := HBoxContainer.new()
	row.name = "HomeModeSettings"
	row.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	row.size_flags_vertical = Control.SIZE_EXPAND_FILL
	row.add_theme_constant_override(&"separation", 12)
	_mode_content.add_child(row)

	var selected_mode := _mode_record(_selected_home_mode)
	var selected_card := _home_mode_card(selected_mode, true, Callable())
	selected_card.name = "SelectedHomeMode"
	selected_card.custom_minimum_size.x = 310.0
	selected_card.size_flags_horizontal = Control.SIZE_SHRINK_BEGIN
	row.add_child(selected_card)

	var settings := VBoxContainer.new()
	settings.name = "HomeModeSettingControls"
	settings.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	settings.size_flags_vertical = Control.SIZE_EXPAND_FILL
	settings.add_theme_constant_override(&"separation", 8)
	settings.add_child(_home_label("MODE SETTINGS //", 15, HOME_GREEN_TEXT))
	settings.add_child(_home_rule())
	if _selected_home_mode == "duels":
		var duel_row := HBoxContainer.new()
		duel_row.name = "HomeDuelsOptions"
		duel_row.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		duel_row.size_flags_vertical = Control.SIZE_EXPAND_FILL
		duel_row.add_theme_constant_override(&"separation", 8)
		for option: Dictionary in DUELS_MODES:
			var option_id := String(option["id"])
			var duel := _home_button(
				String(option["label"]),
				func() -> void: _pick_home_duels_mode(option_id),
				option_id == _selected_home_duels_mode
			)
			duel.name = "HomeDuels_%s" % option_id
			duel.size_flags_horizontal = Control.SIZE_EXPAND_FILL
			duel.size_flags_vertical = Control.SIZE_EXPAND_FILL
			duel_row.add_child(duel)
		settings.add_child(duel_row)
	else:
		var standard := PanelContainer.new()
		standard.name = "HomeStandardModeSettings"
		standard.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		standard.size_flags_vertical = Control.SIZE_EXPAND_FILL
		standard.add_theme_stylebox_override(
			&"panel",
			_home_style(
				Color(0.0, 0.13, 0.035, 0.78),
				Color(HOME_GREEN, 0.88),
				1,
				10.0
			)
		)
		var copy := _home_label(
			"STANDARD RULESET\nNO EXTRA MODE OPTIONS",
			12,
			HOME_GREEN_TEXT,
			true
		)
		copy.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
		copy.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
		standard.add_child(copy)
		settings.add_child(standard)
	row.add_child(_home_frame(settings, "HomeModeSettingsFrame", 10.0))

	var start := _home_button(
		"START GAME",
		func() -> void:
			start_new_game(
				_selected_home_mode,
				_selected_home_duels_mode if _selected_home_mode == "duels" else ""
			),
		true
	)
	start.name = "HomeStartGame"
	start.custom_minimum_size = Vector2(220.0, 0.0)
	start.size_flags_vertical = Control.SIZE_EXPAND_FILL
	row.add_child(start)


func _mode_record(mode_id: String) -> Dictionary:
	for mode: Dictionary in MODES:
		if String(mode["id"]) == mode_id:
			return mode
	return MODES[0]


func _pick_mode(picking: bool) -> void:
	_picking_mode = picking
	if not picking:
		_selected_home_mode = ""
	if _mode_panel != null:
		_mode_panel.visible = _view == View.HOME and _picking_mode
	if _menu != null:
		_menu.visible = _view == View.HOME and not _picking_mode
	if is_instance_valid(_name_row):
		_name_row.visible = _view == View.HOME and not _picking_mode
	if _picking_mode:
		_rebuild_mode_panel()


func _select_home_mode(mode_id: String) -> void:
	if mode_id == "sandbox" and not CrawlerMeta.sandbox_unlocked():
		return
	_selected_home_mode = NetworkManager.sanitize_game_mode(mode_id)
	if _selected_home_mode == "duels":
		_selected_home_duels_mode = NetworkManager.sanitize_duels_mode(
			_selected_home_duels_mode
		)
	_rebuild_mode_panel()


func _back_to_mode_cards() -> void:
	_selected_home_mode = ""
	_rebuild_mode_panel()


func _pick_home_duels_mode(mode_id: String) -> void:
	_selected_home_duels_mode = NetworkManager.sanitize_duels_mode(mode_id)
	_rebuild_mode_panel()


## The name under the figure, and the pencil beside it.
##
## Under the character rather than in the menu on the right, because it is that
## figure's name and the list on the right is about game modes. The field is a drawn
## input and not outlined sky type like everything else up here: a name you can type
## into has to look like somewhere you can type, and a caret blinking in open space
## does not. The pencil opens the editor, which is the same name field again — being
## able to rename yourself without leaving the title screen is the point of having
## it here, and the editor is where you go when you want to change more than that.
func _build_name_row() -> void:
	var column := VBoxContainer.new()
	column.name = "HomeNameRow"
	column.add_theme_constant_override("separation", 2)
	column.alignment = BoxContainer.ALIGNMENT_CENTER
	column.set_anchors_preset(Control.PRESET_CENTER_LEFT)
	# Between the figure's feet and the menu row along the bottom, which is the
	# band left over once the figure was brought in close. Anchored across rather
	# than placed in pixels from the left edge: the figure's own position in the
	# frame is a fraction of the width — it is parallax off a camera a metre and a
	# half to the side — so a pixel offset only holds at one window size.
	column.anchor_top = 0.75
	column.anchor_bottom = 0.75
	# The field itself, rather than the field-plus-pencil group, is centred under
	# the figure. The pencil remains the small action immediately to its right.
	column.anchor_left = 0.328
	column.anchor_right = 0.328
	column.offset_left = -75.0
	column.offset_right = 117.0
	column.offset_top = -18.0
	column.offset_bottom = 42.0
	_root.add_child(column)

	var row := HBoxContainer.new()
	row.name = "HomeNameFields"
	row.add_theme_constant_override("separation", 8)
	column.add_child(row)

	_name_field = LineEdit.new()
	_name_field.name = "HomeNameInput"
	_name_field.text = NetworkManager.saved_player_name()
	_name_field.placeholder_text = "YOUR NAME"
	_name_field.max_length = NetworkManager.PLAYER_NAME_MAX_LENGTH
	_name_field.custom_minimum_size = Vector2(150.0, 36.0)
	_name_field.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	_name_field.alignment = HORIZONTAL_ALIGNMENT_CENTER
	_style_home_input(_name_field)
	_name_field.text_submitted.connect(func(value: String) -> void: _rename(value))
	_name_field.focus_exited.connect(func() -> void: _rename(_name_field.text))
	row.add_child(_name_field)

	_edit_button = _pencil_button()
	_edit_button.pressed.connect(func() -> void: show_view(View.CHARACTER))
	row.add_child(_edit_button)

	_rank_label = _sky_label("LV 1   NEWBIE", 13)
	_rank_label.name = "HomePlayerRank"
	_rank_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_rank_label.add_theme_color_override("font_color", HOME_GREEN_TEXT)
	column.add_child(_rank_label)
	_name_row = column
	_refresh_player_rank()


## A pencil, drawn rather than set as text: no display face here carries a glyph
## for one, and a missing glyph comes out as a stray sliver rather than as a
## visible box. Two polygons over a dark rim, so it reads against the starfield
## the same way the outlined type beside it does.
func _pencil_button() -> Button:
	var button := Button.new()
	button.name = "HomeEditCharacter"
	button.flat = true
	button.focus_mode = Control.FOCUS_ALL
	button.tooltip_text = "Edit character"
	button.custom_minimum_size = Vector2(PENCIL_SIZE, PENCIL_SIZE)
	button.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	button.mouse_default_cursor_shape = Control.CURSOR_POINTING_HAND
	for state: StringName in [&"normal", &"hover", &"pressed", &"focus", &"disabled"]:
		button.add_theme_stylebox_override(state, StyleBoxEmpty.new())
	button.draw.connect(func() -> void:
		var lit := button.has_focus() or button.is_hovered() or button.button_pressed
		var ink := HOME_GREEN if lit else HOME_GREEN_TEXT
		var s := minf(button.size.x, button.size.y)
		var along := Vector2(1.0, -1.0).normalized()
		var across := Vector2(1.0, 1.0).normalized() * (s * 0.15)
		var tip := Vector2(0.14, 0.86) * s
		var shoulder := tip + along * (s * 0.26)
		var back := Vector2(0.86, 0.14) * s
		var body := PackedVector2Array([
			shoulder + across, back + across, back - across, shoulder - across])
		var point := PackedVector2Array([tip, shoulder + across, shoulder - across])
		for shape: PackedVector2Array in [body, point]:
			button.draw_polyline(shape + PackedVector2Array([shape[0]]),
				Color(0.0, 0.0, 0.0, 0.96), s * 0.14)
		for shape: PackedVector2Array in [body, point]:
			button.draw_colored_polygon(shape, ink)
		# The band where the paint stops and the wood begins, which is most of what
		# tells a pencil apart from a slash at this size.
		var band := shoulder + along * (s * 0.14)
		button.draw_line(band + across, band - across, SKY_OUTLINE, s * 0.07)
	)
	# The fill and the rim are both read off the button's state, so a redraw has to
	# be asked for whenever that changes; a flat Button repaints on neither.
	for signal_name: StringName in [&"mouse_entered", &"mouse_exited",
			&"focus_entered", &"focus_exited"]:
		button.connect(signal_name, button.queue_redraw)
	return button


## Saves the typed name, or puts the field back to the stored one if it was
## refused. Moderation lives in [NetworkManager] so that the one rule covers this
## field, the two in the lobby and every chat line; all this does is report it.
func _rename(value: String) -> void:
	if NetworkManager.save_player_name(value):
		_set_notice("", false)
	else:
		_set_notice("That name is not allowed.", true)
	var stored := NetworkManager.saved_player_name()
	if _name_field.text != stored:
		_name_field.text = stored
	if is_instance_valid(_designer):
		_designer.set_player_name(stored)


## Type over the starfield cannot sit on a drawn plate the way the in-game HUD
## does — the mock-up is bare text on space, and a sheet of paper in the middle of
## it would read as a menu bolted over the game rather than part of it. So the
## legibility comes from an ink outline instead, which holds up over both the
## black of space and the lit face of the planet.
func _sky_label(text: String, size: int) -> Label:
	var label := Label.new()
	label.text = text
	label.add_theme_font_size_override("font_size", size)
	label.add_theme_color_override("font_color", PALETTE.text_primary)
	label.add_theme_color_override("font_outline_color", SKY_OUTLINE)
	label.add_theme_constant_override("outline_size", 10)
	label.mouse_filter = Control.MOUSE_FILTER_IGNORE
	return label


## On a card the label stays dark and only the focus rim moves; over space a dark
## label is invisible, so here the text itself carries the state. The meaning is
## the one that holds everywhere else in the UI: starlight at rest, and the
## screen's own cyan for the one item the player is on.
func _sky_button(text: String, callback: Callable) -> Button:
	var button := Button.new()
	button.text = text
	button.flat = true
	button.alignment = HORIZONTAL_ALIGNMENT_LEFT
	button.add_theme_font_size_override("font_size", 27)
	button.add_theme_color_override("font_color", PALETTE.text_primary)
	button.add_theme_color_override("font_hover_color", PALETTE.accent)
	button.add_theme_color_override("font_focus_color", PALETTE.accent)
	button.add_theme_color_override("font_pressed_color", PALETTE.accent)
	button.add_theme_color_override("font_outline_color", SKY_OUTLINE)
	button.add_theme_constant_override("outline_size", 10)
	button.pressed.connect(callback)
	return button


func _home_action_width(text: String) -> float:
	var font: Font = ThemeDB.fallback_font
	if _root != null and _root.theme != null and _root.theme.default_font != null:
		font = _root.theme.default_font
	var measured := font.get_string_size(
		text.to_upper(),
		HORIZONTAL_ALIGNMENT_LEFT,
		-1,
		HOME_ACTION_FONT_SIZE
	).x
	return maxf(
		MENU_ACTION_MIN_WIDTH,
		measured + MENU_ACTION_PAD_X * 2.0 + MENU_ACTION_CRT_PAD
	)


func _home_action_button(
		text: String,
		callback: Callable,
		destructive := false
	) -> HomeActionButton:
	var button := HomeActionButton.new()
	button.text = text.to_upper()
	button.set_destructive(destructive)
	button.custom_minimum_size = Vector2(_home_action_width(text), MENU_ROW_HEIGHT)
	button.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	button.clip_text = false
	button.add_theme_font_size_override(&"font_size", HOME_ACTION_FONT_SIZE)
	var ink := HOME_RED_BRIGHT if destructive else HOME_GREEN_TEXT
	button.add_theme_color_override(&"font_color", ink)
	button.add_theme_color_override(&"font_hover_color", ink)
	button.add_theme_color_override(&"font_pressed_color", ink)
	button.add_theme_color_override(&"font_focus_color", ink)
	button.add_theme_color_override(&"font_disabled_color", Color(ink, 0.42))
	button.add_theme_color_override(&"font_outline_color", Color(0, 0, 0, 0))
	button.add_theme_constant_override(&"outline_size", 0)
	if callback.is_valid():
		button.pressed.connect(callback)
	return button


func _home_button(
		text: String,
		callback := Callable(),
		selected := false,
		destructive := false
	) -> Button:
	var button := Button.new()
	button.text = text.to_upper()
	button.alignment = HORIZONTAL_ALIGNMENT_CENTER
	button.mouse_default_cursor_shape = Control.CURSOR_POINTING_HAND
	button.focus_mode = Control.FOCUS_ALL
	_style_home_button(button, selected, destructive)
	if callback.is_valid():
		button.pressed.connect(callback)
	else:
		button.mouse_filter = Control.MOUSE_FILTER_IGNORE
		button.focus_mode = Control.FOCUS_NONE
	return button


func _home_mode_card(
		mode: Dictionary,
		selected: bool,
		callback: Callable,
		locked := false
	) -> Button:
	var card := _home_button("", callback, selected)
	card.custom_minimum_size = Vector2(220.0, 116.0)
	card.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	card.size_flags_vertical = Control.SIZE_EXPAND_FILL

	var inset := MarginContainer.new()
	inset.mouse_filter = Control.MOUSE_FILTER_IGNORE
	inset.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	for side: StringName in [
			&"margin_left", &"margin_top", &"margin_right", &"margin_bottom"
	]:
		inset.add_theme_constant_override(side, 10)
	card.add_child(inset)

	var copy := VBoxContainer.new()
	copy.mouse_filter = Control.MOUSE_FILTER_IGNORE
	copy.alignment = BoxContainer.ALIGNMENT_BEGIN
	copy.add_theme_constant_override(&"separation", 9)
	inset.add_child(copy)

	var title := _home_label(
		String(mode.get("label", "Mode")),
		18,
		HOME_GREEN_TEXT,
		true
	)
	title.name = "ModeTitle"
	title.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	copy.add_child(title)

	var description := _home_label(
		"Reach your first city to unlock." if locked \
			else String(mode.get("description", "")),
		15,
		Color(0.96, 0.98, 1.0),
		true
	)
	description.name = "ModeDescription"
	description.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	copy.add_child(description)
	return card


func _home_frame(
		content: Control,
		node_name: String,
		padding: float
	) -> PanelContainer:
	var frame_control := PanelContainer.new()
	frame_control.name = node_name
	frame_control.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	frame_control.size_flags_vertical = Control.SIZE_EXPAND_FILL
	frame_control.add_theme_stylebox_override(
		&"panel",
		_home_style(
			Color(0.0, 0.0, 0.0, 0.66),
			Color(HOME_RED_BRIGHT, 0.88),
			1,
			padding
		)
	)
	frame_control.add_child(content)
	return frame_control


func _home_label(
		text: String,
		font_size: int,
		colour: Color,
		wrap := false
	) -> Label:
	var label := Label.new()
	label.text = text.to_upper()
	label.add_theme_font_size_override(&"font_size", font_size)
	label.add_theme_color_override(&"font_color", colour)
	label.add_theme_color_override(
		&"font_outline_color", Color(0.08, 0.0, 0.0, 0.96)
	)
	label.add_theme_constant_override(&"outline_size", 1)
	if wrap:
		label.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	return label


func _home_rule() -> PanelContainer:
	var rule := PanelContainer.new()
	rule.custom_minimum_size.y = 2.0
	rule.mouse_filter = Control.MOUSE_FILTER_IGNORE
	rule.add_theme_stylebox_override(
		&"panel",
		_home_style(Color(HOME_RED, 0.46), HOME_RED_BRIGHT, 1, 0.0)
	)
	return rule


func _style_home_button(
		button: Button,
		selected: bool,
		destructive := false
	) -> void:
	var accent := (
		HOME_RED_BRIGHT
		if destructive
		else HOME_GREEN
		if selected
		else HOME_RED
	)
	var text_colour := (
		HOME_RED_BRIGHT
		if destructive
		else HOME_GREEN_TEXT
	)
	var fill := (
		Color(0.0, 0.15, 0.04, 0.86)
		if selected
		else Color(0.0, 0.0, 0.0, 0.76)
	)
	var interaction_accent := HOME_RED_BRIGHT if destructive else HOME_GREEN
	var interaction_fill := (
		Color(0.16, 0.0, 0.015, 0.90)
		if destructive
		else Color(0.0, 0.10, 0.025, 0.90)
	)
	button.add_theme_font_size_override(&"font_size", 19)
	button.add_theme_color_override(&"font_color", text_colour)
	button.add_theme_color_override(
		&"font_hover_color",
		HOME_RED_BRIGHT if destructive else HOME_GREEN_TEXT
	)
	button.add_theme_color_override(
		&"font_pressed_color", interaction_accent)
	button.add_theme_color_override(
		&"font_focus_color",
		HOME_RED_BRIGHT if destructive else HOME_GREEN_TEXT
	)
	button.add_theme_stylebox_override(
		&"normal",
		_home_style(fill, Color(accent, 0.94), 2 if selected else 1, 8.0)
	)
	button.add_theme_stylebox_override(
		&"hover",
		_home_style(interaction_fill, interaction_accent, 2, 8.0)
	)
	button.add_theme_stylebox_override(
		&"pressed",
		_home_style(
			Color(0.24, 0.0, 0.025, 0.94)
			if destructive
			else Color(0.0, 0.19, 0.05, 0.94),
			interaction_accent,
			2,
			8.0
		)
	)
	button.add_theme_stylebox_override(
		&"focus",
		_home_style(Color.TRANSPARENT, interaction_accent, 2, 7.0)
	)
	button.add_theme_stylebox_override(
		&"disabled",
		_home_style(
			Color(0.0, 0.0, 0.0, 0.54),
			Color(HOME_RED_MUTED, 0.36),
			1,
			8.0
		)
	)


func _style_home_input(field: LineEdit) -> void:
	field.add_theme_font_size_override(&"font_size", 16)
	field.add_theme_color_override(&"font_color", HOME_GREEN_TEXT)
	field.add_theme_color_override(
		&"font_outline_color", Color(0.01, 0.02, 0.01, 0.96))
	field.add_theme_constant_override(&"outline_size", 2)
	field.add_theme_color_override(
		&"font_placeholder_color", Color(HOME_RED_MUTED, 0.72)
	)
	field.add_theme_color_override(&"caret_color", HOME_GREEN)
	field.add_theme_color_override(&"selection_color", Color(HOME_GREEN, 0.42))
	field.add_theme_stylebox_override(
		&"normal",
		_home_style(Color.TRANSPARENT, Color.TRANSPARENT, 0, 2.0)
	)
	field.add_theme_stylebox_override(
		&"focus",
		_home_style(Color.TRANSPARENT, Color.TRANSPARENT, 0, 2.0)
	)


func _home_style(
		fill: Color,
		border: Color,
		border_width: int,
		padding: float
	) -> StyleBoxFlat:
	var box := StyleBoxFlat.new()
	box.bg_color = fill
	box.border_color = border
	box.set_border_width_all(border_width)
	box.set_corner_radius_all(0)
	box.content_margin_left = padding
	box.content_margin_top = padding
	box.content_margin_right = padding
	box.content_margin_bottom = padding
	return box


func _refresh_player_rank() -> void:
	if _rank_label == null:
		return
	_rank_label.text = "LV %d   %s" % [
		CrawlerMeta.global_level(),
		CrawlerMeta.title().to_upper(),
	]


func _style_sandbox_button(button: Button) -> void:
	var open := CrawlerMeta.sandbox_unlocked()
	button.disabled = not open
	button.tooltip_text = "" if open else "Reach your first city to unlock Sandbox."


func _style_load_button(button: Button) -> void:
	var open := GameSave.has_save()
	button.disabled = not open
	button.tooltip_text = "" if open else "No saved game yet."
	if open:
		button.add_theme_color_override(
			&"font_disabled_color", Color(HOME_GREEN_TEXT, 0.42)
		)
		if button.has_meta(&"crt_keep_disabled_ink"):
			button.remove_meta(&"crt_keep_disabled_ink")
		return
	var gray := Color(0.76, 0.76, 0.78)
	button.add_theme_color_override(&"font_disabled_color", gray)
	button.set_meta(&"crt_keep_disabled_ink", true)


func _refresh_load_button() -> void:
	if _menu == null:
		return
	var button := _menu.find_child("HomeLoad", true, false) as Button
	if button != null:
		_style_load_button(button)


func _refresh_sandbox_button() -> void:
	if _menu == null:
		return
	var button := _menu.find_child("HomeSandbox", true, false) as Button
	if button != null:
		_style_sandbox_button(button)
	_refresh_load_button()


func _refresh_gem_counter() -> void:
	if _gems == null:
		return
	_gems.text = "%d GEMS" % CrawlerMeta.gems()
	_gems.visible = _view == View.CHARACTER or _view == View.UPGRADES \
		or _view == View.HATS or _view == View.ACHIEVEMENTS


func _pose_view(view: View) -> View:
	match view:
		View.ONLINE, View.UPGRADES, View.HATS, View.ACHIEVEMENTS:
			return View.ONLINE
		View.SETTINGS:
			return View.SETTINGS
		_:
			return View.HOME


func _planet_overlay(view: View) -> bool:
	return view == View.ONLINE or view == View.UPGRADES \
		or view == View.HATS or view == View.ACHIEVEMENTS


func _transition_framed_background(view: View) -> bool:
	var framed := view == View.ONLINE or view == View.SETTINGS \
		or view == View.UPGRADES or view == View.HATS \
		or view == View.ACHIEVEMENTS
	if _background_fade != null and _background_fade.is_valid():
		_background_fade.kill()
	if not framed:
		_settings_background.visible = false
		_settings_background.modulate.a = 0.0
		return false

	# Online fills almost the entire illustrated rim. Settings is intentionally
	# shorter and centred, so its copy of UI Background 2 follows that card
	# instead of floating as a much larger unrelated sheet behind it.
	if view == View.SETTINGS:
		_settings_background.offset_left = 60.0
		_settings_background.offset_top = 76.0
		_settings_background.offset_right = -60.0
		_settings_background.offset_bottom = -28.0
	else:
		_settings_background.offset_left = 28.0
		_settings_background.offset_top = 28.0
		_settings_background.offset_right = -28.0
		_settings_background.offset_bottom = -28.0
	_settings_background.modulate.a = 0.0
	_settings_background.visible = true
	_background_fade = create_tween()
	_background_fade.tween_property(
		_settings_background,
		"modulate:a",
		1.0,
		SCREEN_FADE_TIME
	).set_delay(SCREEN_FADE_DELAY).set_trans(Tween.TRANS_SINE)
	return true


func show_view(view: View) -> void:
	if _handover_target != null:
		return
	_view = view
	# Character editing keeps the HOME camera. Unlocks and achievements
	# share the Online planet pose so those pages turn to the globe first.
	_apply_pose(_pose_view(view), false)
	_set_notice("", false)
	if is_instance_valid(_screen):
		_screen.queue_free()
		_screen = null
	_designer = null
	_menu.visible = view == View.HOME
	_pick_mode(false)
	if is_instance_valid(_title):
		_title.visible = view == View.HOME
		if view == View.HOME and _title_material != null:
			_title_material.albedo_color = Color.WHITE
	# Online keeps the planet pose and Settings keeps its space pose. Both place
	# ui_background2 inside a complete inset rim so the live scene remains visible
	# around every edge instead of being replaced by a full-screen sheet.
	var framed_background := _transition_framed_background(view)
	# LobbyPanel and SettingsPanel carry BACK inside their own inset frames. The
	# designer alone needs the sky button because its card intentionally occupies
	# only the right side of the home composition.
	_back.visible = view == View.CHARACTER
	# The editor carries a name field of its own, so the one under the figure would
	# be a second field for the same name sitting beside it.
	if is_instance_valid(_name_row):
		_name_row.visible = view == View.HOME
	if view == View.HOME:
		_refresh_player_rank()
		_refresh_sandbox_button()
	# Online is one framed overlay with air on every side. It fills enough of the
	# view to remain useful at 720p while leaving the live planet visible around
	# its complete red rim. Character stays on the home pose so the preview keeps
	# facing the camera while it is edited.
	_screen_host.offset_bottom = -36.0 if framed_background else -28.0
	# And the editor is held clear of the left of the frame, because the figure
	# standing there is the editor's preview. A full-width card would cover the
	# one thing it is for.
	#
	# Being over there is also what lets it start higher than every other screen:
	# it only needs to leave room for BACK, not the full-width navigation band.
	var editing := view == View.CHARACTER
	_screen_host.anchor_left = 1.0 - EDITOR_CARD_SHARE if editing else 0.0
	_screen_host.offset_left = 44.0 if framed_background else 0.0
	_screen_host.offset_right = (
		-28.0 if editing else -44.0 if framed_background else 0.0
	)
	_screen_host.offset_top = (
		EDITOR_TOP
		if editing
		else 36.0
		if _planet_overlay(view)
		else 92.0
		if view == View.SETTINGS
		else TITLE_BAND
	)
	match view:
		View.ONLINE:
			var lobby := LobbyPanel.new()
			lobby.closed.connect(func() -> void: show_view(View.HOME))
			lobby.notice.connect(_set_notice)
			_screen = lobby
		View.SETTINGS:
			var settings := SettingsPanel.new()
			settings.configure(false)
			settings.closed.connect(func() -> void: show_view(View.HOME))
			_screen = settings
		View.UPGRADES:
			_screen = _uplocks_panel(MetaUpgradesPanel.Tab.STATS)
		View.HATS:
			_screen = _uplocks_panel(MetaUpgradesPanel.Tab.HATS)
		View.ACHIEVEMENTS:
			var achievements := AchievementsPanel.new()
			achievements.closed.connect(func() -> void: show_view(View.HOME))
			achievements.gems_changed.connect(_refresh_gem_counter)
			_screen = achievements
		View.CHARACTER:
			_screen = _character_editor()
	if _screen != null:
		_screen.modulate.a = 0.0
		_screen_host.add_child(_screen)
		create_tween().tween_property(
			_screen,
			"modulate:a",
			1.0,
			SCREEN_FADE_TIME
		).set_delay(SCREEN_FADE_DELAY).set_trans(Tween.TRANS_SINE)
	_refresh_gem_counter()


func _uplocks_panel(tab: MetaUpgradesPanel.Tab) -> MetaUpgradesPanel:
	var shop := MetaUpgradesPanel.new()
	shop.opening_tab = tab
	shop.closed.connect(func() -> void: show_view(View.HOME))
	shop.gems_changed.connect(_refresh_gem_counter)
	return shop


# --- The character editor -----------------------------------------------------
#
# The designer has the same visual and container contracts as the in-game Hero
# and Hats pages, but not their combat concerns. There is no weapon editor,
# hotbar or stats here; the live figure beside the panel is already the preview.


func _character_editor() -> Control:
	var body_id := CharacterDB.sanitize_body(str(_look.get("body", CharacterDB.DEFAULT_BODY)))
	if _worn_slots == null:
		_worn_slots = ItemContainer.new(ItemDB.SLOT_ORDER.size())
		for index in ItemDB.SLOT_ORDER.size():
			_worn_slots.set_filter(index, ItemDB.SLOT_ORDER[index])
		# A stable apparel-only ownership rail. Equipping changes the filtered
		# worn slot while this list remains intact.
		_apparel_rail = ItemContainer.new(_catalogue_size())
		_worn_slots.changed.connect(_on_editor_changed)
	_stock_editor(body_id)

	_designer = PlayerDesignerPanel.new()
	_designer.configure(
		_worn_slots,
		_apparel_rail,
		body_id,
		str(_look.get("skin", CharacterDB.default_skin(body_id))),
		_look.get("tints", {}),
		NetworkManager.saved_player_name()
	)
	_designer.skin_picked.connect(_on_skin_picked)
	_designer.body_picked.connect(_on_body_picked)
	_designer.hat_unlocked.connect(_on_hat_unlocked)
	_designer.tint_picked.connect(_on_tint_picked)
	_designer.tint_cleared.connect(_on_tint_cleared)
	_designer.name_entered.connect(_rename)
	return _designer


## Puts the two appearance containers in step with the look. Weapons and ordinary
## inventory stay in the look but are deliberately absent from this designer.
##
## The rail listing the worn garments as well is what makes it a catalogue: an
## item is not in two places, it is in one list and worn or not, which is the only
## arrangement in which the grid can mark what is on the body.
func _stock_editor(body_id: String) -> void:
	_stocking = true
	var worn: Dictionary = _look.get("worn", {})
	for index in ItemDB.SLOT_ORDER.size():
		var slot: String = ItemDB.SLOT_ORDER[index]
		var item_id := str(worn.get(slot, ""))
		_worn_slots.set_item(index, item_id if CharacterDB.apparel_fits(body_id, item_id) else "")

	# Finite ownership, apparel only: gem-unlocked and free garments. Holding a
	# tile changes only the worn slot, never this rail.
	var owned := PackedStringArray()
	for item_id: String in _worn_slots.items():
		if not item_id.is_empty() and ItemDB.is_apparel(item_id) \
				and CrawlerMeta.owns_apparel(item_id) \
				and not owned.has(item_id):
			owned.append(item_id)
	for item_id: String in CharacterDB.backpack_items(
			_look, CharacterDB.BACKPACK_SLOTS):
		if not ItemDB.is_apparel(item_id) \
				or not CharacterDB.apparel_fits(body_id, item_id) \
				or owned.has(item_id):
			continue
		if not CrawlerMeta.owns_apparel(item_id):
			continue
		owned.append(item_id)
	for item_id: String in CharacterDB.apparel_ids(body_id):
		if not CrawlerMeta.owns_apparel(item_id) or owned.has(item_id):
			continue
		owned.append(item_id)
	if owned.size() > _apparel_rail.size():
		_apparel_rail = ItemContainer.new(owned.size())
	for index in _apparel_rail.size():
		_apparel_rail.set_item(index, owned[index] if index < owned.size() else "")
	_stocking = false


## Enough slots to show every apparel place at once. Empty tail slots disappear
## from the designer grid.
func _catalogue_size() -> int:
	var count := CharacterDB.BACKPACK_SLOTS + ItemDB.SLOT_ORDER.size()
	for body_id: String in CharacterDB.body_ids():
		count = maxi(count, CharacterDB.apparel_ids(body_id).size())
	return count


func _on_editor_changed() -> void:
	if _stocking:
		return
	_capture_worn()
	_dress_preview()


## Appearance edits update worn apparel and the apparel portion of the backpack.
## Hotbar, abilities, weapons and ordinary items remain byte-for-byte outside the
## designer's control.
func _capture_worn() -> void:
	var worn: Dictionary = {}
	for index in _worn_slots.size():
		var item_id := _worn_slots.get_item(index)
		if not item_id.is_empty():
			worn[_worn_slots.filter_of(index)] = item_id
	_look["worn"] = worn

	# The rail is a view of ownership, not another place items live. Whatever is
	# not worn belongs in the backpack. Existing non-apparel entries stay in their
	# current order while apparel is reconciled around them.
	var in_use := {}
	for item_id: Variant in worn.values():
		if not str(item_id).is_empty():
			in_use[str(item_id)] = true
	var available_apparel := PackedStringArray()
	for index in _apparel_rail.size():
		var item_id := _apparel_rail.get_item(index)
		if item_id.is_empty() or in_use.has(item_id) \
				or available_apparel.has(item_id):
			continue
		if ItemDB.is_apparel(item_id) and not CrawlerMeta.owns_apparel(item_id):
			continue
		available_apparel.append(item_id)

	var backpack: Array = []
	for item_id: String in CharacterDB.backpack_items(
			_look, CharacterDB.BACKPACK_SLOTS):
		if item_id.is_empty() or backpack.size() >= CharacterDB.BACKPACK_SLOTS:
			continue
		if not ItemDB.is_apparel(item_id):
			backpack.append(item_id)
		elif available_apparel.has(item_id):
			backpack.append(item_id)
			available_apparel.remove_at(available_apparel.find(item_id))
	for item_id: String in available_apparel:
		if backpack.size() >= CharacterDB.BACKPACK_SLOTS:
			break
		backpack.append(item_id)
	_look["backpack"] = backpack
	CharacterDB.save_look(_look)


func _on_body_picked(body_id: String) -> void:
	var clean := CharacterDB.sanitize_body(body_id)
	if clean == str(_look.get("body", CharacterDB.DEFAULT_BODY)):
		return
	_look["body"] = clean
	_look["skin"] = CharacterDB.default_skin(clean)
	var worn: Dictionary = (_look.get("worn", {}) as Dictionary).duplicate()
	for slot: String in worn.keys():
		if not CharacterDB.apparel_fits(clean, str(worn[slot])):
			worn.erase(slot)
	_look["worn"] = worn
	CharacterDB.save_look(_look)
	_stock_editor(clean)
	if is_instance_valid(_designer):
		_designer.configure(
			_worn_slots,
			_apparel_rail,
			clean,
			str(_look.get("skin", CharacterDB.default_skin(clean))),
			_look.get("tints", {}),
			NetworkManager.saved_player_name()
		)
	_spawn_preview()


func _on_hat_unlocked(_item_id: String) -> void:
	_capture_worn()
	_refresh_gem_counter()


func _on_skin_picked(skin_id: String) -> void:
	var body_id := CharacterDB.sanitize_body(str(_look.get("body", CharacterDB.DEFAULT_BODY)))
	_look["skin"] = CharacterDB.sanitize_skin(body_id, skin_id)
	CharacterDB.save_look(_look)
	if is_instance_valid(_designer):
		_designer.set_skin(str(_look["skin"]))
	_dress_preview()


func _on_tint_picked(target: String, colour: Color) -> void:
	var tints: Dictionary = (_look.get("tints", {}) as Dictionary).duplicate()
	tints[target] = colour.to_html(false)
	_look["tints"] = tints
	CharacterDB.save_look(_look)
	if is_instance_valid(_designer):
		_designer.set_tints(tints)
	_dress_preview()


func _on_tint_cleared(target: String) -> void:
	var tints: Dictionary = (_look.get("tints", {}) as Dictionary).duplicate()
	tints.erase(target)
	_look["tints"] = tints
	CharacterDB.save_look(_look)
	if is_instance_valid(_designer):
		_designer.set_tints(tints)
	_dress_preview()


func _set_notice(message: String, is_error: bool) -> void:
	_notice.text = message
	_notice.visible = not message.is_empty()
	_notice.add_theme_color_override(
		"font_color", PALETTE.danger if is_error else PALETTE.text_primary)


func _on_status_changed(message: String) -> void:
	if NetworkManager.state == NetworkManager.SessionState.IDLE:
		return
	_set_notice(message, NetworkManager.state == NetworkManager.SessionState.ERROR)


func _on_steam_invite_received(
		_lobby_id: int,
		_data: Dictionary,
		_inviter_name: String
	) -> void:
	if _handover_target == null:
		show_view(View.ONLINE)


# --- Handing over ------------------------------------------------------------


func start_new_game(game_mode := "crawler", duels_mode := "") -> void:
	if _handover_target != null or _awaiting_player or _warming:
		return
	if str(game_mode) == "sandbox" and not CrawlerMeta.sandbox_unlocked():
		return
	# The player starts exactly where the character they have been looking at was
	# standing, facing the way it was facing. Anything else would be a jump on the
	# frame the real body replaces the preview.
	CharacterDB.save_look(_look)
	_world().override_local_spawn(_preview.global_transform)
	_world().override_local_look(_look)
	# Crawler drops the home chrome before warm-up so Start Game is not sitting
	# on a still-visible mode panel for a second.
	if CrawlerRules.uses_mode(NetworkManager.sanitize_game_mode(game_mode)):
		_dismiss_overlay()
	# Before the session rather than after it, because the point is to be holding
	# the player still while this happens. Once a session exists the world is
	# theirs and every millisecond of it is a frame they are flying in.
	await _warm_up(str(game_mode))
	NetworkManager.start_single_player(str(game_mode), str(duels_mode))


func start_saved_game() -> void:
	if _handover_target != null or _awaiting_player or _warming:
		return
	var payload := GameSave.read()
	if payload.is_empty():
		return
	CharacterDB.save_look(_look)
	var xf := GameSave.player_transform(payload)
	if xf.origin.length_squared() > 0.01:
		_world().override_local_spawn(xf, true)
	var look: Variant = payload.get("look", {})
	if look is Dictionary and not (look as Dictionary).is_empty():
		_world().override_local_look(look)
	else:
		_world().override_local_look(_look)
	if CrawlerRules.uses_mode(GameSave.mode_of(payload)):
		_dismiss_overlay()
	await _warm_up(GameSave.mode_of(payload))
	NetworkManager.start_saved_game(payload)


## Pays for the descent in advance without replacing the menu with a loading
## screen. [WorldWarmup] draws through its own offscreen viewport, so the meshes
## that force texture and shader preparation never enter this camera's world.
## A small red/green bar tracks that work so the still shot does not look hung.
func _warm_up(game_mode := "") -> void:
	_warming = true
	_hold_preview_still(true)
	_show_start_loading()
	var warmup := WorldWarmup.new()
	warmup.name = "WorldWarmup"
	warmup.progressed.connect(_on_warmup_progressed)
	_world().add_child(warmup)
	await warmup.run(_world(), _camera, game_mode)
	if warmup.progressed.is_connected(_on_warmup_progressed):
		warmup.progressed.disconnect(_on_warmup_progressed)
	warmup.queue_free()
	_hide_start_loading()
	_hold_preview_still(false)
	_warming = false


func _show_start_loading() -> void:
	if is_instance_valid(_menu):
		_menu.visible = false
	if is_instance_valid(_mode_panel):
		_mode_panel.visible = false
	if is_instance_valid(_loading_block):
		_loading_block.visible = true
	if is_instance_valid(_loading_bar):
		_loading_bar.share = 0.0
		_loading_bar.visible = true
	if is_instance_valid(_loading_note):
		_loading_note.text = ""
		_loading_note.visible = true


func _hide_start_loading() -> void:
	if is_instance_valid(_loading_bar):
		_loading_bar.visible = false
	if is_instance_valid(_loading_note):
		_loading_note.visible = false
	if is_instance_valid(_loading_block):
		_loading_block.visible = false


func _on_warmup_progressed(share: float, note: String) -> void:
	if is_instance_valid(_loading_bar):
		_loading_bar.share = share
	if is_instance_valid(_loading_note):
		_loading_note.text = note
		_loading_note.visible = true


func _hold_preview_still(hold: bool) -> void:
	if not is_instance_valid(_preview):
		return
	var animator := CharacterRig.animator_of(_preview)
	if animator == null:
		return
	if hold:
		_preview_hold_speed = animator.speed_scale
		animator.speed_scale = 0.0
	else:
		animator.speed_scale = _preview_hold_speed


func _on_session_started() -> void:
	if _handover_target != null:
		return
	_awaiting_player = true
	_dismiss_overlay()


func _dismiss_overlay() -> void:
	_picking_mode = false
	if _mode_panel != null:
		_mode_panel.visible = false
	if is_instance_valid(_name_row):
		_name_row.visible = false
	_menu.visible = false
	_back.visible = false
	# The framed artwork is a sibling of the lobby panel, so removing the panel
	# does not remove it. Hide it at session start instead of leaving it over the
	# camera handover until this HomeScreen is finally freed.
	_transition_framed_background(View.HOME)
	if is_instance_valid(_screen):
		_screen.queue_free()
		_screen = null
	if is_instance_valid(_title):
		_title.visible = false
	if _title_material != null:
		_title_material.albedo_color = Color(1.0, 1.0, 1.0, 0.0)
	_notice.visible = false


func _begin_handover(player: OnlinePlayer) -> void:
	_handover_target = player
	player.controls_enabled = false
	player.set_camera_mode(OnlinePlayer.CameraMode.THIRD_NEAR)
	# The real body is standing in the preview's shoes. Hide one before showing
	# the other so identical surfaces are never submitted together; queue_free()
	# alone is deferred and used to leave one startup frame of black z-fighting.
	if is_instance_valid(_preview):
		_preview.visible = false
		_preview.queue_free()
	player.visible = true
	if player.has_method(&"play_spawn_arrival"):
		player.call(&"play_spawn_arrival")
	if _move != null and _move.is_valid():
		_move.kill()
	_handover_from = _camera.global_transform
	_handover_fov = _camera.fov
	_handover_at = 0.0
	# On the home screen the character is turned to face the camera, so "behind
	# them" points at empty sky. They turn back towards the planet as the camera
	# settles in, which is both the shot the player wants to be left holding and
	# the reason the sweep stays short: the camera barely has to travel, because
	# it was already standing where third person wants to be.
	_body_from = player.global_basis


func _advance_handover(delta: float) -> void:
	var player := _handover_target
	if not is_instance_valid(player):
		_handover_target = null
		queue_free()
		return
	_handover_at = minf(_handover_at + delta / HANDOVER_TIME, 1.0)
	var eased := ease(_handover_at, -1.8)
	player.global_basis = _body_from.slerp(frame.basis, eased).orthonormalized()
	_camera.global_transform = _handover_from.interpolate_with(
		player.camera.global_transform, eased)
	_camera.fov = lerpf(_handover_fov, player.camera.fov, eased)
	if _handover_at < 1.0:
		return
	player.take_camera()
	handed_over.emit()
	queue_free()


func _world() -> GameWorld:
	return get_parent() as GameWorld
