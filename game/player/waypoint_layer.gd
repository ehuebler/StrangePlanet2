class_name WaypointLayer
extends Control

## Names the places on the planet that are too far away to recognise.
##
## One marker per [Landmark] in the [constant Landmark.GROUP] group, drawn where
## that landmark projects onto the screen, and pinned to the nearest edge when it
## is off to one side or behind. Added to the local player's HUD; nobody sees
## anyone else's.
##
## A marker is a diamond and two lines of type in the landmark's own colour, with
## an ink outline behind the letters and nothing else — no plate. The plate was
## the honest thing to draw while there was one waypoint, because [AuroraSurface]
## is how everything else in this game keeps text legible over the world. Once
## several are visible it stops being legibility and becomes opaque cards
## hanging in the sky, so the outline does that job instead: it costs no area,
## and unlike a drop shadow it works over both the pale sky and the dark sea.
##
## This is now an explicit navigation overlay rather than ambient HUD furniture.
## It begins off, tilde toggles the whole set, and while open every selected
## landmark remains visible regardless of distance or whether the planet is
## between it and the camera. Far-side marks therefore act as compass bearings
## instead of disappearing exactly when they are most useful.

## How close to the screen's edge a pinned marker is allowed to sit.
const MARGIN := 46.0
## How close to the edge the type may come. Separate from [constant MARGIN]
## because the type slides along the edge to stay on screen while the diamond
## stays put at the point it is actually indicating.
const EDGE := 10.0
const TITLE_SIZE := 12
const DISTANCE_SIZE := 10
## Ink around the type, in pixels. Enough to close up under the letterforms at
## these sizes, which is what stops them breaking up against busy ground; more
## than this and the outlines of neighbouring glyphs merge into a slab and the
## plate is back. The two sizes above are left where they were through the change
## of face: this type is not in a box that can run out, and Bungee sets about a
## fifth larger and a good deal heavier than what it replaced, which over grass
## and sea is the direction to be wrong in.
const TITLE_OUTLINE := 4
const DISTANCE_OUTLINE := 3
## Half-width of the diamond, in pixels.
const DIAMOND := 4.5
## How much longer the diamond gets along the way it points, once pinned. The
## same shape either way: a diamond marks a spot and a stretched one aims at it,
## so nothing has to appear or disappear as a marker leaves the screen.
const POINT_STRETCH := 2.6
## Ink around the diamond, in pixels, added as an offset rather than a scale so
## the stretched one is not outlined more heavily along its long axis.
const DIAMOND_OUTLINE := 1.6
## Gap between the diamond and the first line of type.
const GAP := 7.0
const PALETTE: UIPalette = preload("res://ui/themes/ui_palette.tres")
## Ion cyan over a teammate's head. Palette blue, not the gold used for places.
const MATE_TINT := Color("6fdcf2")
const MATE_LIFT := 0.45

## Whether any marker is drawn. Navigation is opt-in and starts closed.
var enabled := false

var _camera: Camera3D
## Landmark to the marker drawn for it, so markers are built once rather than per
## frame and a landmark that goes out of range keeps its own.
var _markers: Dictionary = {}
## Remote coop players to the marker over their head.
var _mates: Dictionary = {}
## One-shot unlock presentation. Tilde stays closed; only this landmark is drawn,
## then it fades. The layer remembers the landmark so the diamond can pulse even
## while [member enabled] is false.
var _reveal: Landmark
var _reveal_alpha := 0.0
var _reveal_pulse := 0.0


func _init() -> void:
	name = "Waypoints"
	mouse_filter = Control.MOUSE_FILTER_IGNORE
	set_anchors_preset(Control.PRESET_FULL_RECT)


## The camera the markers are projected through. Without one there is nothing to
## project against and the layer draws nothing.
func bind(camera: Camera3D) -> void:
	_camera = camera


## Presents [param landmark] outside the tilde overlay. [param alpha] is the
## blink/fade, [param pulse] drives the radar rings (0..1 and beyond).
func set_reveal(landmark: Landmark, alpha: float, pulse: float) -> void:
	_reveal = landmark
	_reveal_alpha = clampf(alpha, 0.0, 1.0)
	_reveal_pulse = maxf(pulse, 0.0)
	if landmark != null and _markers.has(landmark):
		(_markers[landmark] as Control).queue_redraw()


func clear_reveal() -> void:
	if _reveal != null and _markers.has(_reveal):
		(_markers[_reveal] as Control).visible = false
	_reveal = null
	_reveal_alpha = 0.0
	_reveal_pulse = 0.0


func is_revealing() -> bool:
	return _reveal != null and is_instance_valid(_reveal)


func reveal_alpha() -> float:
	return _reveal_alpha


func pulse_amount() -> float:
	return _reveal_pulse


## Which places are being named right now, in the order they were first drawn.
## Whether a marker is up is the whole of this layer's behaviour, and it is far
## easier to read off a list than off a screenshot — which is why the harness
## asks for this rather than counting pixels.
##
## [param least] is the alpha a marker has to reach to count. The default is what
## a player would call named; drop it to catch a marker that has begun to fade in
## but cannot be read yet, which is the difference between the range a name
## arrives at and the range it arrives by.
func drawn(least := 0.5) -> PackedStringArray:
	var titles := PackedStringArray()
	for key in _markers:
		if not is_instance_valid(key):
			continue
		var landmark := key as Landmark
		if landmark == null:
			continue
		var marker: Control = _markers[landmark]
		if marker.visible and marker.modulate.a > least:
			titles.append(landmark.title)
	for key in _mates:
		if not is_instance_valid(key):
			continue
		var player := key as OnlinePlayer
		if player == null:
			continue
		var marker: Control = _mates[player]
		if marker.visible and marker.modulate.a > least:
			titles.append(player.display_name)
	return titles


func _process(_delta: float) -> void:
	if not enabled and not is_revealing():
		# Markers already built are hidden rather than freed, so switching back on
		# is the same one line and does not have to rebuild anything.
		_hide_markers()
		return
	if _camera == null or not _camera.is_inside_tree():
		return
	var eye := _camera.global_position
	var half := size * 0.5
	for node in get_tree().get_nodes_in_group(Landmark.GROUP):
		if not is_instance_valid(node):
			continue
		var landmark := node as Landmark
		if landmark == null:
			continue
		var revealing := is_revealing() and landmark == _reveal
		if is_revealing() and not revealing:
			# Unlock presentation is exclusive: the map overlay stays dark so
			# only the new mark can be read.
			if _markers.has(landmark):
				(_markers[landmark] as Control).visible = false
			continue
		if not enabled and not revealing:
			if _markers.has(landmark):
				(_markers[landmark] as Control).visible = false
			continue
		if not _shows_landmark(landmark) and not revealing:
			# Only hidden if it has ever been drawn, so a landmark that is
			# silent from the start never has a marker built for it at all.
			if _markers.has(landmark):
				(_markers[landmark] as Control).visible = false
			continue
		_place(landmark, _marker_for(landmark), eye, half)
	_place_mates(eye, half)


func _shows_landmark(landmark: Landmark) -> bool:
	if landmark == null or not landmark.waypoint:
		return false
	if CrawlerRules.crawler():
		return landmark.is_in_group(CrawlerRules.CITY_WAYPOINT_GROUP) \
				or (landmark.is_in_group(PatchMonument.KEEP_GROUP) and landmark.waypoint)
	return true


func _place(landmark: Landmark, marker: Control, eye: Vector3,
		half: Vector2) -> void:
	var at := landmark.global_position
	var away := eye.distance_to(at)

	var revealing := is_revealing() and landmark == _reveal
	if CrawlerRules.active():
		CrawlerRules.apply_crawler_waypoint_tint(landmark)
	_sync_marker_tint(marker, landmark.tint)
	marker.visible = true
	if revealing:
		marker.modulate.a = _reveal_alpha
	else:
		marker.modulate.a = 1.0
	if revealing:
		marker.queue_redraw()
	(marker.get_meta(&"distance") as Label).text = Landmark.distance_text(away)
	var icons := marker.get_meta(&"shop_icons") as HBoxContainer
	if icons != null and icons.get_child_count() == 0:
		_fill_shop_icons(landmark, icons)
	_pin_marker(marker, at, half)


func _place_mates(eye: Vector3, half: Vector2) -> void:
	if not enabled or is_revealing() or not CrawlerRules.coop():
		_hide_mates()
		return
	var seen: Dictionary = {}
	var tree := get_tree()
	if tree == null:
		_hide_mates()
		return
	for node_variant: Variant in tree.get_nodes_in_group(&"network_players"):
		var player := node_variant as OnlinePlayer
		if not _is_teammate(player):
			continue
		seen[player] = true
		var marker := _mate_marker(player)
		var at := _mate_point(player)
		marker.visible = true
		marker.modulate.a = 1.0
		var title := marker.get_meta(&"title") as Label
		if title != null:
			title.text = player.display_name
		(marker.get_meta(&"distance") as Label).text = Landmark.distance_text(
			eye.distance_to(at))
		_pin_marker(marker, at, half)
	var stale: Array = []
	for key in _mates:
		if not seen.has(key):
			stale.append(key)
	for key: Variant in stale:
		var marker: Control = _mates[key]
		if marker != null:
			marker.visible = false
		if not is_instance_valid(key):
			if marker != null:
				marker.queue_free()
			_mates.erase(key)


func _is_teammate(player: OnlinePlayer) -> bool:
	if player == null or not is_instance_valid(player):
		return false
	if player.training_enemy:
		return false
	var host := _local_player()
	return host != null and player != host


func _mate_point(player: OnlinePlayer) -> Vector3:
	var at := player.global_position
	if player.head != null:
		at = player.head.global_position
	var up := player.global_basis.y
	if up.length_squared() < 0.25:
		up = Vector3.UP
	return at + up.normalized() * MATE_LIFT


func _pin_marker(marker: Control, at: Vector3, half: Vector2) -> void:
	var pinned := false
	var toward := Vector2.ZERO
	var screen := half
	if _camera.is_position_behind(at):
		# unproject_position mirrors anything behind the lens, so the only usable
		# direction back there is the one in the camera's own space.
		var local := _camera.global_transform.affine_inverse() * at
		toward = -Vector2(local.x, -local.y)
		pinned = true
	else:
		screen = _camera.unproject_position(at)
		toward = screen - half
		pinned = absf(toward.x) > half.x - MARGIN or absf(toward.y) > half.y - MARGIN
	if pinned:
		screen = half + _to_edge(toward, half - Vector2(MARGIN, MARGIN))
	marker.position = screen
	var aimed := toward.normalized() if pinned else Vector2.ZERO
	if marker.get_meta(&"toward") != aimed:
		marker.set_meta(&"toward", aimed)
		marker.queue_redraw()
	_lay_out(marker, screen)


## Puts the type under the diamond, or over it near the bottom of the screen, and
## slides it along the edge rather than letting a long name run off the side. The
## diamond does not move with it: it is pointing at something.
func _lay_out(marker: Control, screen: Vector2) -> void:
	var column := marker.get_meta(&"column") as Control
	column.size = column.get_combined_minimum_size()
	# Cleared for the pointed diamond whether or not it is pointing, so the type
	# does not hop by a dozen pixels at the moment a marker crosses the edge of
	# the screen and the diamond grows.
	var reach := DIAMOND * POINT_STRETCH + GAP
	var below := screen.y + reach + column.size.y < size.y - EDGE
	column.position = Vector2(
		clampf(screen.x - column.size.x * 0.5, EDGE, maxf(EDGE, size.x - column.size.x - EDGE)) - screen.x,
		reach if below else -(reach + column.size.y))


## Scales a direction until it lands on the edge of a box that size, which is
## what pins an off-screen marker to the side it is actually off.
func _to_edge(toward: Vector2, half: Vector2) -> Vector2:
	var reach := INF
	if absf(toward.x) > 0.001:
		reach = minf(reach, half.x / absf(toward.x))
	if absf(toward.y) > 0.001:
		reach = minf(reach, half.y / absf(toward.y))
	if reach == INF:
		return Vector2.ZERO
	return toward * reach


# --- Markers ----------------------------------------------------------------

## A marker is one zero-sized [Control] parked at the projected point, with the
## diamond drawn about its own origin and the type in a box hung off it. Zero
## sized on purpose: everything about the marker is positioned relative to the
## one point that means anything, and a rect would only be something else to keep
## in step with it.
func _sync_marker_tint(marker: Control, tint: Color) -> void:
	if marker == null:
		return
	if marker.get_meta(&"tint") is Color and marker.get_meta(&"tint") == tint:
		return
	marker.set_meta(&"tint", tint)
	var title := marker.get_meta(&"title") as Label
	if title != null:
		title.add_theme_color_override(&"font_color", tint)
	var distance := marker.get_meta(&"distance") as Label
	if distance != null:
		distance.add_theme_color_override(&"font_color", tint.lerp(PALETTE.text_muted, 0.55))
	marker.queue_redraw()


func _marker_for(landmark: Landmark) -> Control:
	if _markers.has(landmark):
		return _markers[landmark]

	var marker := Control.new()
	marker.mouse_filter = Control.MOUSE_FILTER_IGNORE
	marker.set_meta(&"toward", Vector2.ZERO)
	marker.set_meta(&"tint", landmark.tint)
	marker.draw.connect(_draw_marker.bind(marker))
	add_child(marker)

	var column := VBoxContainer.new()
	column.mouse_filter = Control.MOUSE_FILTER_IGNORE
	column.add_theme_constant_override(&"separation", 2)
	marker.add_child(column)

	var title := _line(landmark.title, TITLE_SIZE, TITLE_OUTLINE, landmark.tint)
	column.add_child(title)
	var icons := HBoxContainer.new()
	icons.name = "ShopIcons"
	icons.mouse_filter = Control.MOUSE_FILTER_IGNORE
	icons.alignment = BoxContainer.ALIGNMENT_CENTER
	icons.add_theme_constant_override(&"separation", 3)
	column.add_child(icons)
	var distance := _line("", DISTANCE_SIZE, DISTANCE_OUTLINE,
		landmark.tint.lerp(PALETTE.text_muted, 0.55))
	column.add_child(distance)

	marker.set_meta(&"column", column)
	marker.set_meta(&"title", title)
	marker.set_meta(&"distance", distance)
	marker.set_meta(&"shop_icons", icons)
	_fill_shop_icons(landmark, icons)
	_markers[landmark] = marker
	return marker


func _mate_marker(player: OnlinePlayer) -> Control:
	if _mates.has(player):
		return _mates[player]
	var marker := Control.new()
	marker.name = "MateMark_%d" % player.peer_id
	marker.mouse_filter = Control.MOUSE_FILTER_IGNORE
	marker.set_meta(&"toward", Vector2.ZERO)
	marker.set_meta(&"tint", MATE_TINT)
	marker.draw.connect(_draw_marker.bind(marker))
	add_child(marker)
	var column := VBoxContainer.new()
	column.mouse_filter = Control.MOUSE_FILTER_IGNORE
	column.add_theme_constant_override(&"separation", 2)
	marker.add_child(column)
	var title := _line(player.display_name, TITLE_SIZE, TITLE_OUTLINE, MATE_TINT)
	column.add_child(title)
	var distance := _line("", DISTANCE_SIZE, DISTANCE_OUTLINE,
		MATE_TINT.lerp(PALETTE.text_muted, 0.55))
	column.add_child(distance)
	marker.set_meta(&"column", column)
	marker.set_meta(&"title", title)
	marker.set_meta(&"distance", distance)
	_mates[player] = marker
	return marker


func tint_of(title: String) -> Color:
	var wanted := title.strip_edges()
	for key in _markers:
		if not is_instance_valid(key):
			continue
		var landmark := key as Landmark
		if landmark != null and landmark.title == wanted:
			var held: Variant = (_markers[landmark] as Control).get_meta(&"tint")
			return held if held is Color else Color.BLACK
	for key in _mates:
		if not is_instance_valid(key):
			continue
		var player := key as OnlinePlayer
		if player != null and player.display_name == wanted:
			var held: Variant = (_mates[player] as Control).get_meta(&"tint")
			return held if held is Color else Color.BLACK
	return Color.BLACK


func shop_icon_ids(landmark: Landmark) -> PackedStringArray:
	var ids: PackedStringArray = []
	if landmark == null or not _markers.has(landmark):
		return ids
	var row := (_markers[landmark] as Control).get_meta(&"shop_icons") as HBoxContainer
	if row == null:
		return ids
	for child: Node in row.get_children():
		ids.append(str(child.name).trim_prefix("ShopIcon_"))
	return ids


func _fill_shop_icons(landmark: Landmark, row: HBoxContainer) -> void:
	if row == null:
		return
	for child: Node in row.get_children():
		row.remove_child(child)
		child.queue_free()
	var city := ""
	if landmark is CrawlerSite:
		city = (landmark as CrawlerSite).city_key
	if city.is_empty():
		return
	var progress := _player_progress()
	if progress == null:
		return
	for shop_id: String in progress.signed_shops_for(city):
		var tex := CrawlerShopIcons.texture_for(shop_id)
		if tex == null:
			continue
		var icon := TextureRect.new()
		icon.name = "ShopIcon_%s" % shop_id
		icon.texture = tex
		icon.custom_minimum_size = Vector2(14, 14)
		icon.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
		icon.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_CENTERED
		icon.mouse_filter = Control.MOUSE_FILTER_IGNORE
		row.add_child(icon)


func _local_player() -> OnlinePlayer:
	var walk: Node = get_parent()
	while walk != null:
		if walk is OnlinePlayer:
			return walk as OnlinePlayer
		walk = walk.get_parent()
	return null


func _player_progress() -> CrawlerProgress:
	var host := _local_player()
	if host != null:
		return host.crawler_progress
	if not CrawlerProgress.session_payload.is_empty():
		var ledger := CrawlerProgress.new()
		ledger.from_dict(CrawlerProgress.session_payload)
		return ledger
	return null


func _line(text: String, font_size: int, outline: int, colour: Color) -> Label:
	var label := Label.new()
	label.text = text
	label.mouse_filter = Control.MOUSE_FILTER_IGNORE
	label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	label.add_theme_font_size_override(&"font_size", font_size)
	label.add_theme_color_override(&"font_color", colour)
	label.add_theme_color_override(&"font_outline_color", PALETTE.ink)
	label.add_theme_constant_override(&"outline_size", outline)
	return label


## Drawn rather than typed: the pixel font has no diamond or arrow glyph, and a
## letter standing in for one reads as a letter.
func _hide_markers() -> void:
	for key in _markers:
		if not is_instance_valid(key):
			continue
		var marker: Control = _markers[key]
		if marker != null:
			marker.visible = false
	_hide_mates()


func _hide_mates() -> void:
	for key in _mates:
		if not is_instance_valid(key):
			continue
		var marker: Control = _mates[key]
		if marker != null:
			marker.visible = false


func _draw_marker(marker: Control) -> void:
	var toward: Vector2 = marker.get_meta(&"toward")
	var tint: Color = marker.get_meta(&"tint")
	if is_revealing() and _markers.get(_reveal) == marker:
		_draw_radar(marker, tint)
	marker.draw_colored_polygon(_diamond(toward, DIAMOND_OUTLINE), PALETTE.ink)
	marker.draw_colored_polygon(_diamond(toward, 0.0), tint)


func _draw_radar(marker: Control, tint: Color) -> void:
	if _reveal_alpha <= 0.01 or _reveal_pulse <= 0.001:
		return
	var ink := Color(PALETTE.ink, _reveal_alpha * 0.55)
	for ring in 3:
		var phase := fmod(_reveal_pulse * 0.95 + float(ring) * 0.33, 1.0)
		var radius := lerpf(8.0, 44.0, phase)
		var fade := (1.0 - phase) * _reveal_alpha
		var ring_tint := Color(tint.r, tint.g, tint.b, fade * 0.7)
		marker.draw_arc(Vector2.ZERO, radius + 1.4, 0.0, TAU, 36, ink, 2.4, true)
		marker.draw_arc(Vector2.ZERO, radius, 0.0, TAU, 36, ring_tint, 1.8, true)


func _diamond(toward: Vector2, grow: float) -> PackedVector2Array:
	var wide := DIAMOND + grow
	if toward == Vector2.ZERO:
		return PackedVector2Array([
			Vector2(0.0, -wide), Vector2(wide, 0.0),
			Vector2(0.0, wide), Vector2(-wide, 0.0)])
	var side := toward.orthogonal()
	return PackedVector2Array([
		toward * (DIAMOND * POINT_STRETCH + grow), side * wide,
		-toward * wide, -side * wide])
