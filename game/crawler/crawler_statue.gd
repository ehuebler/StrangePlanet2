class_name CrawlerStatue
extends SurfaceAnchor

## A crawler shrine. Standing in its aura fills the bar on the pedestal; a full
## bar spends the statue and grants one luck-weighted blessing from its pool.

const GROUP := &"crawler_statues"
const KIND_WINGS := "wings"
const KIND_HEALTH := "health"
const KIND_STRENGTH := "strength"
const KIND_WEALTH := "wealth"
const KIND_MISC := "misc"
const KINDS := [
	KIND_WEALTH, KIND_WINGS, KIND_HEALTH, KIND_STRENGTH, KIND_MISC,
]
const HEAL_ID := "heal"
const FILL_SECONDS := 3.6
const POP_LIFE := 1.65
const AURA_RADIUS := 5.2
const BAR_FILL_WIDTH := 1.36
const BAR_LEFT := -0.68
const FIGURE_HEIGHT := 3.4
const WATCH_METRES := 64.0
const PORTRAIT := {
	KIND_WINGS: "res://assets/runtime/crawler/statues/wings.png",
	KIND_HEALTH: "res://assets/runtime/crawler/statues/health.png",
	KIND_STRENGTH: "res://assets/runtime/crawler/statues/strength.png",
	KIND_WEALTH: "res://assets/runtime/crawler/statues/wealth.png",
	KIND_MISC: "res://assets/runtime/crawler/statues/misc.png",
}
const MODEL := {
	KIND_WINGS: "res://assets/runtime/crawler/statues/wing-statue.glb",
	KIND_HEALTH: "res://assets/runtime/crawler/statues/health-statue.glb",
	KIND_STRENGTH: "res://assets/runtime/crawler/statues/strength-statue.glb",
	KIND_WEALTH: "res://assets/runtime/crawler/statues/wealth-statue.glb",
	KIND_MISC: "res://assets/runtime/crawler/statues/misc-statue.glb",
}
const TINTS := {
	KIND_WINGS: Color("2ec8d6"),
	KIND_HEALTH: Color("3dcc6a"),
	KIND_STRENGTH: Color("ef6a2f"),
	KIND_WEALTH: Color("e4b22a"),
	KIND_MISC: Color("8a4dff"),
}

var kind := KIND_MISC
var claim_id := KIND_MISC
var claimed := false
var fill := 0.0

var _inside: Array[OnlinePlayer] = []
var _figure: Node3D
var _figure_material: ShaderMaterial
var _aura: MeshInstance3D
var _aura_material: StandardMaterial3D
var _sign: Node3D
var _bar_fill: MeshInstance3D
var _title: Label3D
var _zone: Area3D
var _blessing_pop: Label3D
var _pop_age := 0.0

static var _baked_meshes: Dictionary = {}
static var _watch_frame := -1
static var _watch_at := Vector3.INF


static func is_kind(id: String) -> bool:
	return KINDS.has(id)


static func title_of(id: String) -> String:
	match id:
		KIND_WINGS:
			return "Wing Statue"
		KIND_HEALTH:
			return "Health Statue"
		KIND_STRENGTH:
			return "Strength Statue"
		KIND_WEALTH:
			return "Wealth Statue"
		KIND_MISC:
			return "Curious Statue"
		_:
			return "Statue"


static func pool_for(id: String) -> PackedStringArray:
	match id:
		KIND_WINGS:
			return PackedStringArray([
				CrawlerProgress.STAT_FLIGHT, CrawlerProgress.STAT_DEXTERITY,
			])
		KIND_STRENGTH:
			return PackedStringArray([
				CrawlerProgress.STAT_DAMAGE, CrawlerProgress.STAT_DEFENSE,
			])
		KIND_WEALTH:
			return PackedStringArray([
				CrawlerProgress.STAT_GOLD, CrawlerProgress.STAT_XP,
				CrawlerProgress.STAT_GEMS,
			])
		KIND_MISC:
			return PackedStringArray([
				CrawlerProgress.STAT_DODGE, CrawlerProgress.STAT_JUKE,
				CrawlerProgress.STAT_JUKE_DISTANCE,
				CrawlerProgress.STAT_KNOCKBACK, CrawlerProgress.STAT_RANGE,
				CrawlerProgress.STAT_CAST, CrawlerProgress.STAT_LUCK,
			])
		KIND_HEALTH:
			return PackedStringArray([CrawlerProgress.STAT_HEALTH, HEAL_ID])
		_:
			return PackedStringArray()


static func roll_blessing(
		id: String,
		rng: RandomNumberGenerator,
		luck_rank: float
	) -> Dictionary:
	var pool := pool_for(id)
	if pool.is_empty() or rng == null:
		return {}
	var pick := pool[rng.randi_range(0, pool.size() - 1)]
	if pick == HEAL_ID:
		return {
			"id": HEAL_ID,
			"rarity": CrawlerProgress.RARITY_COMMON,
			"amount": 0.0,
		}
	return CrawlerProgress.make_offer(pick, CrawlerProgress.roll_rarity(rng, luck_rank))


static func blessing_text(blessing: Dictionary) -> String:
	var id := str(blessing.get("id", ""))
	if id == HEAL_ID:
		return "Healed to full"
	var rarity := int(blessing.get("rarity", CrawlerProgress.RARITY_COMMON))
	var amount := float(blessing.get("amount", 0.0))
	return "%s %s" % [
		CrawlerProgress.rarity_title(rarity),
		CrawlerProgress.offer_boost_text(id, amount),
	]


static func popup_text(blessing: Dictionary) -> String:
	var id := str(blessing.get("id", ""))
	if id == HEAL_ID:
		return "HEALTH  HEALED TO FULL"
	var amount := float(blessing.get("amount", 0.0))
	return "%s  %s" % [
		CrawlerProgress.stat_title(id).to_upper(),
		CrawlerProgress.offer_boost_text(id, amount),
	]


func configure(statue_kind: String, at := Vector3.ZERO, slot := -1) -> void:
	kind = statue_kind if is_kind(statue_kind) else KIND_MISC
	claim_id = kind if slot < 0 else "%s_%d" % [kind, slot]
	name = "CrawlerStatue_%s" % claim_id
	if at.length_squared() > 0.25:
		direction = at.normalized()
	if is_inside_tree():
		place()
		_apply_claimed_from_ledger()
		_refresh_look()


func _ready() -> void:
	add_to_group(GROUP)
	super()
	_build()
	_apply_claimed_from_ledger()
	_refresh_look()
	if claimed or get_parent() is CrawlerStatues:
		set_physics_process(false)


func should_simulate(near: bool) -> bool:
	if claimed:
		return _blessing_pop != null and is_instance_valid(_blessing_pop)
	return near or not _inside.is_empty()


func _physics_process(delta: float) -> void:
	_advance_pop(delta)
	if claimed:
		if _blessing_pop == null or not is_instance_valid(_blessing_pop):
			set_physics_process(false)
		return
	if _inside.is_empty() and not _visitor_near():
		return
	_face_visitor()
	_prune_inside()
	tick_presence(delta, not _inside.is_empty(), _occupant())


func _visitor_near() -> bool:
	var frame := Engine.get_physics_frames()
	if frame != _watch_frame:
		_watch_frame = frame
		_watch_at = Vector3.INF
		if is_inside_tree():
			var camera := get_viewport().get_camera_3d()
			if camera != null:
				_watch_at = camera.global_position
	if not _watch_at.is_finite():
		return true
	return global_position.distance_squared_to(_watch_at) <= WATCH_METRES * WATCH_METRES


## Advances the pedestal bar. A full bar spends the shrine for [param player].
func tick_presence(
		delta: float,
		present: bool,
		player: OnlinePlayer = null
	) -> Dictionary:
	if claimed:
		return {}
	if present:
		fill = minf(1.0, fill + maxf(delta, 0.0) / FILL_SECONDS)
	_sync_bar()
	if fill < 1.0:
		return {}
	var who := player if player != null else _occupant()
	if who == null:
		return {}
	return complete_for(who)


func complete_for(player: OnlinePlayer) -> Dictionary:
	if claimed or player == null or player.crawler_progress == null:
		return {}
	var progress := player.crawler_progress
	if progress.statue_claimed(claim_id):
		claimed = true
		_refresh_look()
		return {}
	var blessing := roll_blessing(kind, progress.offer_rng(), progress.luck_rank())
	if blessing.is_empty():
		return {}
	if not apply_blessing(player, blessing):
		return {}
	progress.claim_statue(claim_id)
	claimed = true
	fill = 1.0
	_refresh_look()
	_celebrate(blessing)
	_announce(player, blessing)
	return blessing


static func apply_blessing(player: OnlinePlayer, blessing: Dictionary) -> bool:
	if player == null or player.crawler_progress == null or blessing.is_empty():
		return false
	var id := str(blessing.get("id", ""))
	if id == HEAL_ID:
		player.apply_heal(player.maximum_health())
		return true
	return player.crawler_progress.grant_boost(
		id, float(blessing.get("amount", 0.0)))


func _build() -> void:
	_build_figure()
	_build_aura()
	_build_sign()
	_build_zone()
	_build_plinth()


func _build_figure() -> void:
	_figure = Node3D.new()
	_figure.name = "StatueFigure"
	add_child(_figure)
	if _attach_model():
		_fit_figure()
		return
	_build_card()


func _attach_model() -> bool:
	var path := String(MODEL.get(kind, ""))
	if path.is_empty() or not ResourceLoader.exists(path):
		return false
	var baked := _baked_mesh(kind, path)
	if baked != null:
		var visual := MeshInstance3D.new()
		visual.name = "StatueMesh"
		visual.mesh = baked
		_figure.add_child(visual)
		return true
	var loaded: Variant = load(path)
	var packed := loaded as PackedScene
	if packed == null:
		return false
	var raw := packed.instantiate() as Node3D
	if raw == null:
		return false
	raw.name = "StatueMesh"
	_figure.add_child(raw)
	return true


func _build_card() -> void:
	var mesh := QuadMesh.new()
	mesh.size = Vector2(2.35, 2.35)
	var card := MeshInstance3D.new()
	card.name = "StatueCard"
	card.position = Vector3(0.0, 1.18, 0.0)
	card.rotation.y = PI
	card.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	_figure_material = ShaderMaterial.new()
	_figure_material.shader = load("res://game/crawler/crawler_statue.gdshader") as Shader
	var texture := load(String(PORTRAIT.get(kind, ""))) as Texture2D
	if texture != null:
		_figure_material.set_shader_parameter(&"albedo", texture)
	card.material_override = _figure_material
	card.mesh = mesh
	_figure.add_child(card)


func _build_aura() -> void:
	var mesh := SphereMesh.new()
	mesh.radius = AURA_RADIUS
	mesh.height = AURA_RADIUS * 2.0
	mesh.radial_segments = 24
	mesh.rings = 16
	_aura = MeshInstance3D.new()
	_aura.name = "StatueAura"
	_aura.position = Vector3(0.0, _sign_height() * 0.42, 0.0)
	_aura.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	_aura_material = StandardMaterial3D.new()
	_aura_material.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	_aura_material.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	_aura_material.cull_mode = BaseMaterial3D.CULL_DISABLED
	_aura_material.albedo_color = _tint().lightened(0.12)
	_aura_material.albedo_color.a = 0.11
	_aura.material_override = _aura_material
	_aura.mesh = mesh
	add_child(_aura)


func _build_sign() -> void:
	_sign = Node3D.new()
	_sign.name = "StatueSign"
	_sign.position = Vector3(0.0, _sign_height(), 0.0)
	add_child(_sign)
	var track := MeshInstance3D.new()
	track.name = "StatueBarTrack"
	track.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	var track_mesh := BoxMesh.new()
	track_mesh.size = Vector3(1.46, 0.07, 0.07)
	var track_material := StandardMaterial3D.new()
	track_material.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	track_material.albedo_color = Color(0.04, 0.04, 0.05, 0.88)
	track_material.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	track.material_override = track_material
	track.mesh = track_mesh
	_sign.add_child(track)
	_bar_fill = MeshInstance3D.new()
	_bar_fill.name = "StatueBarFill"
	_bar_fill.position = Vector3(BAR_LEFT, 0.0, 0.02)
	_bar_fill.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	var fill_mesh := BoxMesh.new()
	fill_mesh.size = Vector3(BAR_FILL_WIDTH, 0.05, 0.05)
	var fill_material := StandardMaterial3D.new()
	fill_material.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	fill_material.albedo_color = _tint()
	_bar_fill.material_override = fill_material
	_bar_fill.mesh = fill_mesh
	_sign.add_child(_bar_fill)
	_title = Label3D.new()
	_title.name = "StatueTitle"
	_title.position = Vector3(0.0, 0.26, 0.0)
	_title.pixel_size = 0.008
	_title.font_size = 28
	_title.outline_size = 8
	_title.modulate = _tint().lightened(0.28)
	_title.outline_modulate = Color(0.02, 0.02, 0.03, 0.92)
	_title.billboard = BaseMaterial3D.BILLBOARD_DISABLED
	_title.text = title_of(kind).to_upper()
	_sign.add_child(_title)
	_sync_bar()


func _build_zone() -> void:
	_zone = Area3D.new()
	_zone.name = "StatueAuraZone"
	_zone.monitoring = true
	_zone.monitorable = false
	_zone.collision_layer = 0
	_zone.collision_mask = 1
	_zone.position = Vector3(0.0, _sign_height() * 0.42, 0.0)
	var shape := CollisionShape3D.new()
	var sphere := SphereShape3D.new()
	sphere.radius = AURA_RADIUS
	shape.shape = sphere
	_zone.add_child(shape)
	_zone.body_entered.connect(_on_body_entered)
	_zone.body_exited.connect(_on_body_exited)
	add_child(_zone)


func _build_plinth() -> void:
	var body := StaticBody3D.new()
	body.name = "StatuePlinth"
	body.collision_layer = 1
	body.collision_mask = 0
	var shape := CollisionShape3D.new()
	var cylinder := CylinderShape3D.new()
	var aabb := _local_aabb(_figure)
	var radius := 0.52
	if aabb.size.length_squared() > 0.0001:
		radius = maxf(maxf(aabb.size.x, aabb.size.z) * _figure.scale.x * 0.42, 0.52)
	cylinder.radius = radius
	cylinder.height = 0.38
	shape.position = Vector3(0.0, 0.19, 0.0)
	shape.shape = cylinder
	body.add_child(shape)
	add_child(body)


func _on_body_entered(body: Node) -> void:
	var player := body as OnlinePlayer
	if player == null or _inside.has(player):
		return
	_inside.append(player)
	if not claimed:
		set_physics_process(true)


func _on_body_exited(body: Node) -> void:
	var player := body as OnlinePlayer
	if player == null:
		return
	_inside.erase(player)


func _prune_inside() -> void:
	var kept: Array[OnlinePlayer] = []
	for player: OnlinePlayer in _inside:
		if is_instance_valid(player) and player.is_inside_tree() and not player.is_dead():
			kept.append(player)
	_inside = kept


func _occupant() -> OnlinePlayer:
	_prune_inside()
	return _inside[0] if not _inside.is_empty() else null


func _face_visitor() -> void:
	if _sign == null:
		return
	var from := _look_from()
	if from == Vector3.INF:
		return
	var away := from - _sign.global_position
	var up := global_basis.y.normalized()
	away -= up * away.dot(up)
	if away.length_squared() < 0.0004:
		return
	var look := Basis.looking_at(-away.normalized(), up)
	var local := global_basis.inverse() * look
	_sign.rotation.y = local.get_euler().y


func _sync_bar() -> void:
	if _bar_fill == null:
		return
	var amount := 1.0 if claimed else fill
	_bar_fill.scale = Vector3(maxf(amount, 0.001), 1.0, 1.0)
	_bar_fill.position.x = BAR_LEFT + BAR_FILL_WIDTH * amount * 0.5
	_bar_fill.visible = amount > 0.001


func _apply_claimed_from_ledger() -> void:
	var payload: Variant = CrawlerProgress.session_payload.get("statues", [])
	if payload is Array and (payload as Array).has(claim_id):
		claimed = true
		fill = 1.0


func _refresh_look() -> void:
	if _title != null:
		_title.text = (
			"%s  //  BLESSED" % title_of(kind).to_upper()
			if claimed else title_of(kind).to_upper()
		)
	if _aura != null:
		_aura.visible = not claimed
	if _zone != null:
		_zone.monitoring = not claimed
	if _aura_material != null:
		var colour := _tint()
		colour.a = 0.11
		_aura_material.albedo_color = colour
	if _figure_material != null:
		_figure_material.set_shader_parameter(&"fade", 0.62 if claimed else 1.0)
	_fade_figure(0.62 if claimed else 1.0)
	_sync_bar()


func _celebrate(blessing: Dictionary) -> void:
	if not is_inside_tree() or blessing.is_empty():
		return
	var up := global_basis.y.normalized() if global_basis.y.length_squared() > 0.0001 \
		else Vector3.UP
	var at := global_position + up * 1.2
	if _figure != null:
		at = _figure.global_position + up * (FIGURE_HEIGHT * 0.35)
	CrawlerBurst.confetti(self, at, up, 2.4)
	_spawn_pop(popup_text(blessing))


func _spawn_pop(copy: String) -> void:
	if copy.is_empty():
		return
	if _blessing_pop != null and is_instance_valid(_blessing_pop):
		_blessing_pop.queue_free()
	_blessing_pop = Label3D.new()
	_blessing_pop.name = "StatueBlessing"
	_blessing_pop.text = copy
	_blessing_pop.position = Vector3(0.0, 2.35, 0.0)
	_blessing_pop.pixel_size = 0.012
	_blessing_pop.font_size = 42
	_blessing_pop.outline_size = 12
	_blessing_pop.modulate = _tint().lightened(0.35)
	_blessing_pop.outline_modulate = Color(0.02, 0.02, 0.03, 0.94)
	_blessing_pop.billboard = BaseMaterial3D.BILLBOARD_ENABLED
	_blessing_pop.no_depth_test = true
	add_child(_blessing_pop)
	_pop_age = 0.0


func _advance_pop(delta: float) -> void:
	if _blessing_pop == null or not is_instance_valid(_blessing_pop):
		_blessing_pop = null
		return
	_pop_age += maxf(delta, 0.0)
	var t := clampf(_pop_age / POP_LIFE, 0.0, 1.0)
	_blessing_pop.position.y = 2.35 + t * 1.7
	var fade := 1.0 - smoothstep(0.52, 1.0, t)
	var ink := _tint().lightened(0.35)
	ink.a = fade
	_blessing_pop.modulate = ink
	if t >= 1.0:
		_blessing_pop.queue_free()
		_blessing_pop = null


func _announce(player: OnlinePlayer, blessing: Dictionary) -> void:
	var hud := player.combat_hud() if player != null else null
	if hud != null and hud.has_method(&"show_note"):
		hud.call(&"show_note", title_of(kind), blessing_text(blessing))


func _tint() -> Color:
	return TINTS.get(kind, Color("8a4dff")) as Color


func _look_from() -> Vector3:
	if is_inside_tree():
		var camera := get_viewport().get_camera_3d()
		if camera != null:
			return camera.global_position
	var visitor := _occupant()
	if visitor == null:
		var world := _world()
		if world != null:
			visitor = world.local_player()
	if visitor == null and is_inside_tree():
		visitor = get_tree().get_first_node_in_group(&"network_players") as OnlinePlayer
	if visitor == null:
		return Vector3.INF
	if visitor.has_method(&"combat_position"):
		var at: Variant = visitor.call(&"combat_position")
		if at is Vector3 and (at as Vector3).is_finite():
			return at
	return visitor.global_position


func _sign_height() -> float:
	if _figure == null:
		return 2.52
	var aabb := _local_aabb(_figure)
	if aabb.size.y <= 0.01:
		return 2.52
	return _figure.position.y + (aabb.position.y + aabb.size.y) * _figure.scale.y + 0.22


func _fit_figure() -> void:
	var aabb := _local_aabb(_figure)
	if aabb.size.y <= 0.01:
		return
	var scale := FIGURE_HEIGHT / aabb.size.y
	_figure.scale = Vector3.ONE * scale
	_figure.position.y = -aabb.position.y * scale


func _fade_figure(fade: float) -> void:
	if _figure == null:
		return
	var hide := 1.0 - clampf(fade, 0.0, 1.0)
	for node_variant: Variant in _figure.find_children("*", "GeometryInstance3D", true, false):
		var geo := node_variant as GeometryInstance3D
		if geo != null:
			geo.transparency = hide


func _local_aabb(node: Node3D) -> AABB:
	if node == null:
		return AABB()
	var bounds := AABB()
	var started := false
	for node_variant: Variant in node.find_children("*", "VisualInstance3D", true, false):
		var vis := node_variant as VisualInstance3D
		if vis == null or not vis.visible:
			continue
		var box := vis.get_aabb()
		var xf := _relative_transform(vis, node)
		box = xf * box
		if not started:
			bounds = box
			started = true
		else:
			bounds = bounds.merge(box)
	return bounds


func _relative_transform(node: Node3D, root: Node3D) -> Transform3D:
	var xf := Transform3D.IDENTITY
	var walk: Node3D = node
	while walk != null and walk != root:
		xf = walk.transform * xf
		walk = walk.get_parent() as Node3D
	return xf


static func _baked_mesh(statue_kind: String, path: String) -> ArrayMesh:
	if _baked_meshes.has(statue_kind):
		return _baked_meshes[statue_kind] as ArrayMesh
	var loaded: Variant = load(path)
	var packed := loaded as PackedScene
	if packed == null:
		return null
	var raw := packed.instantiate() as Node3D
	if raw == null:
		return null
	var combined := _combine_meshes(raw)
	raw.free()
	if combined == null:
		return null
	_baked_meshes[statue_kind] = combined
	return combined


static func _combine_meshes(root: Node3D) -> ArrayMesh:
	var tools: Dictionary = {}
	var order: Array = []
	for node_variant: Variant in root.find_children("*", "MeshInstance3D", true, false):
		var mesh_i := node_variant as MeshInstance3D
		if mesh_i == null or mesh_i.mesh == null or not mesh_i.visible:
			continue
		var xf := Transform3D.IDENTITY
		var walk: Node3D = mesh_i
		while walk != null and walk != root:
			xf = walk.transform * xf
			walk = walk.get_parent() as Node3D
		for surface in mesh_i.mesh.get_surface_count():
			var material := mesh_i.get_active_material(surface)
			var key := str(material.get_instance_id()) if material != null else "none"
			if not tools.has(key):
				tools[key] = {
					"st": SurfaceTool.new(),
					"mat": material,
				}
				order.append(key)
			var bag: Dictionary = tools[key]
			var st: SurfaceTool = bag["st"]
			st.append_from(mesh_i.mesh, surface, xf)
	if order.is_empty():
		return null
	var out := ArrayMesh.new()
	for key: Variant in order:
		var bag: Dictionary = tools[key]
		var st: SurfaceTool = bag["st"]
		st.generate_normals()
		var next := out.get_surface_count()
		st.commit(out)
		var material: Variant = bag["mat"]
		if material is Material and next < out.get_surface_count():
			out.surface_set_material(next, material)
	return out


func _world() -> GameWorld:
	var node: Node = self
	while node != null:
		if node is GameWorld:
			return node as GameWorld
		node = node.get_parent()
	return null
