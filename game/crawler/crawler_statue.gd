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
const AURA_RADIUS := 4.6
const PORTRAIT := {
	KIND_WINGS: "res://assets/runtime/crawler/statues/wings.png",
	KIND_HEALTH: "res://assets/runtime/crawler/statues/health.png",
	KIND_STRENGTH: "res://assets/runtime/crawler/statues/strength.png",
	KIND_WEALTH: "res://assets/runtime/crawler/statues/wealth.png",
	KIND_MISC: "res://assets/runtime/crawler/statues/misc.png",
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
var _figure: MeshInstance3D
var _figure_material: ShaderMaterial
var _aura: MeshInstance3D
var _aura_material: StandardMaterial3D
var _bar_fill: MeshInstance3D
var _title: Label3D
var _zone: Area3D


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


func _physics_process(delta: float) -> void:
	_face_visitor()
	if claimed:
		return
	_prune_inside()
	tick_presence(delta, not _inside.is_empty(), _occupant())


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
	_build_bar()
	_build_title()
	_build_zone()
	_build_plinth()


func _build_figure() -> void:
	var mesh := QuadMesh.new()
	mesh.size = Vector2(2.35, 2.35)
	_figure = MeshInstance3D.new()
	_figure.name = "StatueFigure"
	_figure.position = Vector3(0.0, 1.18, 0.0)
	_figure.rotation.y = PI
	_figure.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	_figure_material = ShaderMaterial.new()
	_figure_material.shader = load("res://game/crawler/crawler_statue.gdshader") as Shader
	var texture := load(String(PORTRAIT.get(kind, ""))) as Texture2D
	if texture != null:
		_figure_material.set_shader_parameter(&"albedo", texture)
	_figure.material_override = _figure_material
	_figure.mesh = mesh
	add_child(_figure)


func _build_aura() -> void:
	var mesh := SphereMesh.new()
	mesh.radius = AURA_RADIUS
	mesh.height = AURA_RADIUS * 2.0
	mesh.radial_segments = 24
	mesh.rings = 16
	_aura = MeshInstance3D.new()
	_aura.name = "StatueAura"
	_aura.position = Vector3(0.0, 1.15, 0.0)
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


func _build_bar() -> void:
	var track := MeshInstance3D.new()
	track.name = "StatueBarTrack"
	track.position = Vector3(0.0, 2.52, 0.0)
	track.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	var track_mesh := BoxMesh.new()
	track_mesh.size = Vector3(1.46, 0.07, 0.07)
	var track_material := StandardMaterial3D.new()
	track_material.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	track_material.albedo_color = Color(0.04, 0.04, 0.05, 0.88)
	track_material.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	track.material_override = track_material
	track.mesh = track_mesh
	add_child(track)
	_bar_fill = MeshInstance3D.new()
	_bar_fill.name = "StatueBarFill"
	_bar_fill.position = Vector3(-0.68, 2.52, 0.02)
	_bar_fill.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	var fill_mesh := BoxMesh.new()
	fill_mesh.size = Vector3(1.36, 0.05, 0.05)
	var fill_material := StandardMaterial3D.new()
	fill_material.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	fill_material.albedo_color = _tint()
	_bar_fill.material_override = fill_material
	_bar_fill.mesh = fill_mesh
	add_child(_bar_fill)
	_sync_bar()


func _build_title() -> void:
	_title = Label3D.new()
	_title.name = "StatueTitle"
	_title.position = Vector3(0.0, 2.78, 0.0)
	_title.pixel_size = 0.008
	_title.font_size = 28
	_title.outline_size = 8
	_title.modulate = _tint().lightened(0.28)
	_title.outline_modulate = Color(0.02, 0.02, 0.03, 0.92)
	_title.billboard = BaseMaterial3D.BILLBOARD_DISABLED
	_title.text = title_of(kind).to_upper()
	add_child(_title)


func _build_zone() -> void:
	_zone = Area3D.new()
	_zone.name = "StatueAuraZone"
	_zone.monitoring = true
	_zone.monitorable = false
	_zone.collision_layer = 0
	_zone.collision_mask = 1
	_zone.position = Vector3(0.0, 1.15, 0.0)
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
	cylinder.radius = 0.52
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
	var visitor := _occupant()
	if visitor == null:
		var world := _world()
		if world != null:
			visitor = world.local_player()
	if visitor == null or _figure == null:
		return
	var away := visitor.global_position - global_position
	var up := global_basis.y.normalized()
	away -= up * away.dot(up)
	if away.length_squared() < 0.0004:
		return
	var look := Basis.looking_at(-away.normalized(), up)
	var local := global_basis.inverse() * look
	_figure.rotation.y = local.get_euler().y
	if _title != null:
		_title.rotation.y = _figure.rotation.y


func _sync_bar() -> void:
	if _bar_fill == null:
		return
	var amount := 1.0 if claimed else fill
	_bar_fill.scale = Vector3(maxf(amount, 0.001), 1.0, 1.0)
	_bar_fill.position.x = -0.68 + 0.68 * (1.0 - amount)
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
	if _aura_material != null:
		var colour := _tint()
		colour.a = 0.05 if claimed else 0.11
		_aura_material.albedo_color = colour
	if _figure_material != null:
		_figure_material.set_shader_parameter(&"fade", 0.62 if claimed else 1.0)
	_sync_bar()


func _announce(player: OnlinePlayer, blessing: Dictionary) -> void:
	var hud := player.combat_hud() if player != null else null
	if hud != null and hud.has_method(&"show_note"):
		hud.call(&"show_note", title_of(kind), blessing_text(blessing))


func _tint() -> Color:
	return TINTS.get(kind, Color("8a4dff")) as Color


func _world() -> GameWorld:
	var node: Node = self
	while node != null:
		if node is GameWorld:
			return node as GameWorld
		node = node.get_parent()
	return null
