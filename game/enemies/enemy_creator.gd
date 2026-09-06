class_name EnemyCreator
extends StaticBody3D

## Tilde-menu dummy factory. A blue capsule, about player-sized, that stays
## planted so more enemies can be queued from the same mark.

const GROUP := &"enemy_creators"
const HEIGHT := 1.45
const RADIUS := 0.38
const PLACE_AHEAD := 2.6
const SPAWN_AHEAD := 4.2
const SPAWN_DELAY := 5.0
const SURFACE_CLEARANCE := 0.04
static var _next_bot_id := -1000

var _menu: EnemyCreatorMenu
var _menu_user: OnlinePlayer
var _pending: Array[Dictionary] = []


func _init() -> void:
	name = "EnemyCreator"
	collision_layer = 1
	collision_mask = 0


func _ready() -> void:
	add_to_group(GROUP)
	_build_visual()


func _physics_process(delta: float) -> void:
	var index := 0
	while index < _pending.size():
		var job: Dictionary = _pending[index]
		job["left"] = float(job.get("left", 0.0)) - delta
		var ghost := job.get("ghost") as Node3D
		if is_instance_valid(ghost):
			var label := ghost.get_node_or_null("Countdown") as Label3D
			if label != null:
				label.text = str(ceili(maxf(float(job["left"]), 0.0)))
		if float(job["left"]) <= 0.0:
			_finish_spawn(job)
			_pending.remove_at(index)
		else:
			_pending[index] = job
			index += 1


func interact_prompt() -> String:
	return "Configure enemy"


func interact(user: OnlinePlayer) -> void:
	if user == null or user.training_enemy or _menu != null:
		return
	_menu = EnemyCreatorMenu.new()
	_menu_user = user
	_menu.closed.connect(_on_menu_closed)
	_menu.spawn_requested.connect(
		func(abilities: PackedStringArray, behavior: int) -> void:
			queue_spawn(user, abilities, behavior as EnemyPlayerAI.Behavior)
	)
	user.open_menu()
	user.hud.add_child(_menu)


func queue_spawn(user: OnlinePlayer, abilities: PackedStringArray,
		behavior: EnemyPlayerAI.Behavior) -> void:
	if user == null:
		return
	var at := _spawn_transform(user)
	var ghost := _make_ghost(at)
	get_parent().add_child(ghost)
	_pending.append({
		"abilities": abilities,
		"behavior": behavior,
		"transform": at,
		"look": _copied_look(user),
		"left": SPAWN_DELAY,
		"ghost": ghost,
	})


func place_ahead_of(user: OnlinePlayer) -> void:
	global_transform = _ahead_transform(user, PLACE_AHEAD, 0.0)


func queued_spawn_count() -> int:
	return _pending.size()


func force_finish_spawns() -> void:
	while not _pending.is_empty():
		_finish_spawn(_pending[0])
		_pending.remove_at(0)


static func next_bot_id() -> int:
	_next_bot_id -= 1
	return _next_bot_id + 1


func _on_menu_closed() -> void:
	_menu = null
	var user := _menu_user
	_menu_user = null
	if user != null and is_instance_valid(user) \
			and user.hud.get_node_or_null("GameMenu") == null:
		user.close_menu()


func _finish_spawn(job: Dictionary) -> void:
	var ghost := job.get("ghost") as Node
	if is_instance_valid(ghost):
		ghost.queue_free()
	var world := get_parent()
	if world == null:
		return
	var packed := load("res://game/player/player.tscn") as PackedScene
	if packed == null:
		return
	var enemy := packed.instantiate() as OnlinePlayer
	if enemy == null:
		return
	var abilities: PackedStringArray = job.get("abilities", PackedStringArray())
	enemy.become_training_enemy(next_bot_id(),
		maxi(abilities.size(), OnlinePlayer.TRAINING_ABILITY_SLOTS))
	world.add_child(enemy)
	var look: Dictionary = job.get("look", {})
	look["abilities"] = abilities
	enemy.apply_look(look)
	enemy.apply_abilities(abilities)
	var at: Transform3D = job.get("transform", global_transform)
	enemy.global_transform = at
	enemy.reset_physics_interpolation()
	var brain := EnemyPlayerAI.new()
	brain.name = "EnemyAI"
	brain.configure(enemy, self, job.get("behavior", EnemyPlayerAI.Behavior.ATTACK))
	enemy.add_child(brain)


func _copied_look(user: OnlinePlayer) -> Dictionary:
	var worn: Dictionary = {}
	for index in ItemDB.SLOT_ORDER.size():
		var item_id := user.equipment.get_item(index)
		if not item_id.is_empty():
			worn[ItemDB.SLOT_ORDER[index]] = item_id
	return {
		"body": user.body_id(),
		"skin": user.skin_id(),
		"worn": worn,
		"tints": user.tints(),
	}


func _spawn_transform(user: OnlinePlayer) -> Transform3D:
	return _ahead_transform(user, SPAWN_AHEAD, 0.0)


func _ahead_transform(user: OnlinePlayer, distance: float,
		lift: float) -> Transform3D:
	var up := user.global_basis.y.normalized()
	if up.length_squared() < 0.5:
		up = Vector3.UP
	var forward := -user.global_basis.z
	forward -= up * forward.dot(up)
	if forward.length_squared() < 0.0001:
		forward = user.global_basis.x
	forward = forward.normalized()
	var world := user.get_parent() as GameWorld
	var planet := world.planet() if world != null else null
	if planet == null or planet.shape == null:
		return Transform3D(_basis_from(forward, up),
			user.global_position + forward * distance + up * lift)
	var player_local := planet.to_local(user.global_position)
	if player_local.length_squared() < 1.0:
		return Transform3D(_basis_from(forward, up),
			user.global_position + forward * distance + up * lift)
	var radial := player_local.normalized()
	var forward_local := planet.global_basis.inverse() * forward
	forward_local -= radial * forward_local.dot(radial)
	if forward_local.length_squared() < 0.0001:
		var hint := Vector3.FORWARD if absf(radial.z) < 0.9 else Vector3.RIGHT
		forward_local = (hint - radial * hint.dot(radial)).normalized()
	else:
		forward_local = forward_local.normalized()
	var angle := distance / maxf(planet.shape.radius, 1.0)
	var direction := (radial * cos(angle) + forward_local * sin(angle)).normalized()
	var spacing := planet.finest_spacing()
	var normal := planet.shape.normal_at(direction, spacing).normalized()
	var surface := planet.shape.surface_point(direction, spacing)
	var facing := forward_local - normal * forward_local.dot(normal)
	if facing.length_squared() < 0.0001:
		facing = direction.cross(normal)
	return planet.global_transform * Transform3D(
		_basis_from(facing.normalized(), normal),
		surface + normal * (SURFACE_CLEARANCE + lift))


func _basis_from(forward: Vector3, up: Vector3) -> Basis:
	up = up.normalized()
	forward -= up * forward.dot(up)
	if forward.length_squared() < 0.0001:
		forward = Vector3.FORWARD
	forward = forward.normalized()
	var right := up.cross(forward).normalized()
	forward = right.cross(up).normalized()
	return Basis(right, up, -forward)


func _build_visual() -> void:
	var shape := CylinderShape3D.new()
	shape.radius = RADIUS
	shape.height = HEIGHT
	var collider := CollisionShape3D.new()
	collider.shape = shape
	collider.position = Vector3(0.0, HEIGHT * 0.5, 0.0)
	add_child(collider)
	var mesh := CylinderMesh.new()
	mesh.top_radius = RADIUS
	mesh.bottom_radius = RADIUS
	mesh.height = HEIGHT
	mesh.radial_segments = 18
	var body := MeshInstance3D.new()
	body.mesh = mesh
	body.position = Vector3(0.0, HEIGHT * 0.5, 0.0)
	body.material_override = _blue_material(0.42)
	add_child(body)
	var label := Label3D.new()
	label.text = "ENEMY"
	label.font_size = 28
	label.modulate = Color(0.45, 0.82, 1.0)
	label.billboard = BaseMaterial3D.BILLBOARD_ENABLED
	label.no_depth_test = true
	label.position = Vector3(0.0, HEIGHT + 0.28, 0.0)
	add_child(label)


func _make_ghost(at: Transform3D) -> Node3D:
	var ghost := Node3D.new()
	ghost.name = "EnemySpawnGhost"
	ghost.global_transform = at
	var mesh := CylinderMesh.new()
	mesh.top_radius = RADIUS
	mesh.bottom_radius = RADIUS
	mesh.height = HEIGHT
	var body := MeshInstance3D.new()
	body.mesh = mesh
	body.position = Vector3(0.0, HEIGHT * 0.5, 0.0)
	body.material_override = _blue_material(0.22)
	ghost.add_child(body)
	var label := Label3D.new()
	label.name = "Countdown"
	label.text = str(ceili(SPAWN_DELAY))
	label.font_size = 48
	label.modulate = Color(0.55, 0.88, 1.0)
	label.billboard = BaseMaterial3D.BILLBOARD_ENABLED
	label.no_depth_test = true
	label.position = Vector3(0.0, HEIGHT + 0.4, 0.0)
	ghost.add_child(label)
	return ghost


func _blue_material(alpha: float) -> StandardMaterial3D:
	var material := StandardMaterial3D.new()
	material.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	material.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	material.albedo_color = Color(0.18, 0.55, 1.0, alpha)
	material.emission_enabled = true
	material.emission = Color(0.12, 0.42, 0.95)
	material.emission_energy_multiplier = 1.4
	return material
