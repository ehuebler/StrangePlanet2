class_name RedCharacterPreview
extends TextureRect

## Rotatable floating character portrait for the red Hero page.
##
## Kept separate from [InventoryPage]'s standing editor portrait because the
## in-game mock-up asks for the title-screen Float pose and a much taller frame.
## The body is still the same CharacterDB scene and every garment is read directly
## from the player's equipment container.

const VIEW_SIZE := Vector2(230.0, 320.0)
const SUPERSAMPLE := 3
const SPIN_PER_PIXEL := 0.01
const BOB_HEIGHT := 0.22
const BOB_PIXELS := 11.0
const BOB_RATE := 0.72

var _equipment: ItemContainer
var _body_id := CharacterDB.DEFAULT_BODY
var _skin_id := ""
var _tints: Dictionary = {}
var _viewport: SubViewport
var _pivot: Node3D
var _character: Node3D
var _camera: Camera3D
var _worn: Dictionary = {}
var _spin := -0.42
var _dragging := false
var _bob_time := 0.0
## When true the portrait recenters itself and adds a visible 2D hover so a
## parent CenterContainer or animation track cannot hide the float.
var hover_in_frame := false
## Portraits in roster cards use the same renderer in a shorter frame.
var view_size := VIEW_SIZE
## Orthographic room around the body, expressed as a share of body height.
## Roster portraits lower this so the player fills the available viewer while
## the full Hero preview keeps its wider breathing room.
var camera_height_scale := 1.35


func configure(equipment: ItemContainer, body_id: String, skin_id: String,
		tints: Dictionary) -> void:
	_equipment = equipment
	_body_id = CharacterDB.sanitize_body(body_id)
	_skin_id = CharacterDB.sanitize_skin(_body_id, skin_id)
	_tints = tints.duplicate(true)


func _init() -> void:
	process_mode = Node.PROCESS_MODE_ALWAYS


func _ready() -> void:
	process_mode = Node.PROCESS_MODE_ALWAYS
	custom_minimum_size = view_size
	expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_CENTERED
	mouse_filter = Control.MOUSE_FILTER_STOP
	mouse_default_cursor_shape = Control.CURSOR_DRAG
	_build()
	set_process(true)
	set_physics_process(false)
	if _equipment != null and not _equipment.changed.is_connected(refresh):
		_equipment.changed.connect(refresh)


func _exit_tree() -> void:
	if _equipment != null and _equipment.changed.is_connected(refresh):
		_equipment.changed.disconnect(refresh)


func _gui_input(event: InputEvent) -> void:
	var button := event as InputEventMouseButton
	if button != null and button.button_index == MOUSE_BUTTON_LEFT:
		_dragging = button.pressed
		accept_event()
		return
	var motion := event as InputEventMouseMotion
	if motion != null and _dragging:
		# Hero and online portraits use direct manipulation: drag right and the
		# character turns right with the pointer.
		_spin += motion.relative.x * SPIN_PER_PIXEL
		if is_instance_valid(_pivot):
			_pivot.basis = Basis(Vector3.UP, _spin)
		accept_event()


func _process(delta: float) -> void:
	_bob_time += delta
	var wave := sin(_bob_time * TAU * BOB_RATE)
	if is_instance_valid(_pivot):
		# Lift the whole figure, not the posed skeleton. Float writes the body
		# transform every frame, so bobbing the character node itself never shows.
		_pivot.position.y = wave * BOB_HEIGHT
	if hover_in_frame:
		var parent := get_parent() as Control
		if parent != null:
			position = (parent.size - size) * 0.5 + Vector2(0.0, wave * BOB_PIXELS)


func refresh() -> void:
	if not is_instance_valid(_character) or _equipment == null:
		return
	var repaint := false
	for index in _equipment.size():
		var body_slot := _equipment.filter_of(index)
		var id := _equipment.get_item(index)
		if str(_worn.get(body_slot, "")) == id:
			continue
		_worn[body_slot] = id
		repaint = true
		Wardrobe.unequip(_character, body_slot)
		if id.is_empty():
			continue
		var garment := Wardrobe.equip(_character, body_slot,
			ItemDB.scene_path(id))
		if garment != null:
			SurfaceSkin.paint(garment, {}, true)
	if repaint:
		_paint()


func set_tints(tints: Dictionary) -> void:
	_tints = tints.duplicate(true)
	_paint()


func _build() -> void:
	_viewport = SubViewport.new()
	_viewport.process_mode = Node.PROCESS_MODE_ALWAYS
	_viewport.size = Vector2i(view_size * SUPERSAMPLE)
	_viewport.transparent_bg = true
	_viewport.own_world_3d = true
	_viewport.handle_input_locally = true
	_viewport.render_target_update_mode = SubViewport.UPDATE_ALWAYS
	add_child(_viewport)
	texture = _viewport.get_texture()

	var key := DirectionalLight3D.new()
	key.rotation_degrees = Vector3(-34.0, 152.0, 0.0)
	key.light_energy = 1.2
	_viewport.add_child(key)

	_pivot = Node3D.new()
	_pivot.basis = Basis(Vector3.UP, _spin)
	_viewport.add_child(_pivot)
	var packed := CharacterDB.scene(_body_id)
	_character = packed.instantiate() as Node3D if packed != null else Node3D.new()
	_pivot.add_child(_character)
	CharacterRig.normalize_body(_character)
	SurfaceSkin.apply(_character, true)
	SurfaceSkin.set_body_texture(_character,
		CharacterDB.skin_texture(_body_id, _skin_id))
	_play_float()

	_camera = Camera3D.new()
	_camera.projection = Camera3D.PROJECTION_ORTHOGONAL
	_camera.size = CharacterDB.height(_body_id) * camera_height_scale
	var height := CharacterDB.height(_body_id)
	var eye := Vector3(-0.48, height * 0.55, -2.1)
	var target := Vector3(0.0, height * 0.52, 0.0)
	_camera.transform = Transform3D(
		Basis.looking_at(target - eye, Vector3.UP), eye)
	_viewport.add_child(_camera)
	_camera.current = true
	refresh()
	_paint()


func _play_float() -> void:
	var animator := _character.find_child("*", true, false) as AnimationPlayer
	for node in _character.find_children("*", "AnimationPlayer", true, false):
		animator = node as AnimationPlayer
		break
	if animator == null:
		return
	animator.process_mode = Node.PROCESS_MODE_ALWAYS
	CharacterRig.prepare(animator, CharacterDB.extra_animation_paths(_body_id))
	var clip := CharacterRig.resolve_clip(animator, "Float")
	if not animator.has_animation(clip):
		return
	animator.play(clip)


func _paint() -> void:
	if not is_instance_valid(_character):
		return
	var groups: Dictionary = {}
	for node in _character.find_children("*", "MeshInstance3D", true, false):
		var mesh := node as MeshInstance3D
		var named := String(mesh.name)
		var target := named.trim_prefix(Wardrobe.NODE_PREFIX) \
			if named.begins_with(Wardrobe.NODE_PREFIX) else "body"
		groups.get_or_add(target, []).append(mesh)
	for target: String in groups:
		var derived: Dictionary = {}
		for mesh: MeshInstance3D in groups[target]:
			SurfaceSkin.paint(mesh, derived, true)
			if target == "body":
				SurfaceSkin.set_texture(mesh,
					CharacterDB.skin_texture(_body_id, _skin_id))
		if not _tints.has(target):
			continue
		var tint := Color.html(str(_tints[target]))
		for material: Variant in derived.values():
			SurfaceSkin.tint_material(material as ShaderMaterial, tint)
