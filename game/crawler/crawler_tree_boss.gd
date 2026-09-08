class_name CrawlerTreeBoss
extends CharacterBody3D

## The Giving Tree. Rooted first-ring boss: bushels, leaf disks, then fruit
## and a damageable trunk.

signal died

const GROUP := &"crawler_boss"
const MODEL_PATH := "res://assets/runtime/crawler/bosses/elderwood.glb"
const BOUNDARY := preload("res://game/enemies/bigfoot/bigfoot_arena_boundary.gd")
const WAVE := preload("res://game/enemies/bigfoot/bigfoot_roar_wave.gd")
const CUTSCENE := preload("res://game/crawler/crawler_boss_cutscene.gd")
const TITLE := preload("res://ui/combat/crawler_boss_title.gd")
const BUSHEL := preload("res://game/crawler/crawler_tree_bushel.gd")
const LEAF := preload("res://game/crawler/crawler_tree_leaf_disk.gd")
const FRUIT := preload("res://game/crawler/crawler_tree_fruit.gd")

const DISPLAY_NAME := "The Giving Tree"
const MAX_HEALTH := 500.0
const TARGET_HEIGHT := 68.0
const TRUNK := 8.4
const THREAT := 8
const RESET_DEBOUNCE := 5.0
const DISK_GAP := 1.05
const SWEEP_GAP := 6.2
const SWEEP_WINDUP := 0.55
const SWEEP_DAMAGE := 18.0
const SWEEP_REACH := 16.0
const FRUIT_COUNT := 10
const SPOIL_GOLD := 100
const SPOIL_GEMS := 10
const SPOIL_XP := 25
const ACHIEVEMENT := "first_boss"

enum Phase { IDLE, INTRO, PHASE1, PHASE2_INTRO, PHASE2, FAILED, SLAIN }

var site_id := ""
var statuses := CombatStatuses.new()
var last_source_peer := 0
var _health := MAX_HEALTH
var _alive := true
var _phase: Phase = Phase.IDLE
var _planet: Planet
var _model: Node3D
var _animator: AnimationPlayer
var _face_meshes: Array[MeshInstance3D] = []
var _bushels: Array[Node] = []
var _boundary: Node
var _wave: Node
var _cutscene: Node
var _front := Vector3.FORWARD
var _intro_seen := false
var _phase2_seen := false
var _leave_left := 0.0
var _disk_left := 0.0
var _sweep_left := 0.0
var _sweep_wind := 0.0
var _rng := RandomNumberGenerator.new()
var _authored_height := 12.0
var _fruit_host: Node
var _scream_fired := false
var _scream_hold := 0.0


func configure(id: String) -> void:
	site_id = id


func _ready() -> void:
	motion_mode = MOTION_MODE_FLOATING
	collision_layer = 1
	collision_mask = 0
	process_mode = Node.PROCESS_MODE_ALWAYS
	_planet = _find_planet()
	_health = MAX_HEALTH
	_rng.randomize()
	_build_body()
	_bind_boundary()
	_clear_flora()
	add_to_group(GROUP)
	add_to_group(BossAdapter.CRAWLER_GROUP)
	_set_face("happy")


func _physics_process(delta: float) -> void:
	if not _alive:
		return
	if _phase == Phase.SLAIN:
		return
	_tick_leave(delta)
	if not _is_host():
		return
	match _phase:
		Phase.IDLE, Phase.FAILED:
			_watch_enter()
		Phase.INTRO, Phase.PHASE2_INTRO:
			_tick_cutscene(delta)
		Phase.PHASE1:
			_tick_phase1(delta)
		Phase.PHASE2:
			_tick_phase2(delta)


static func shields_player(player: Node) -> bool:
	if player == null or not player.is_inside_tree():
		return false
	for node_variant: Variant in player.get_tree().get_nodes_in_group(GROUP):
		var boss := node_variant as Node
		if boss != null and boss.has_method(&"protects") \
				and bool(boss.call(&"protects", player)):
			return true
	return false


func protects(player: Node) -> bool:
	if not _fighting() or player == null or not player is Node3D:
		return false
	return _arena_distance(player as Node3D) <= battle_radius()


func blocks_field_spawns() -> bool:
	return _fighting()


func combat_faction() -> int:
	return DamageHit.Faction.ENEMY


func combat_peer_id() -> int:
	return 0


func combat_display_name() -> String:
	return DISPLAY_NAME


func combat_position() -> Vector3:
	return global_position + _up() * (TARGET_HEIGHT * 0.22)


func combat_radius() -> float:
	return TRUNK * 0.55


func combat_aabb() -> AABB:
	var half := combat_radius()
	var at := combat_position()
	return AABB(at - Vector3.ONE * half, Vector3.ONE * (half * 2.0))


func health() -> float:
	if _phase == Phase.PHASE1 or _phase == Phase.INTRO:
		return MAX_HEALTH
	return _health


func maximum_health() -> float:
	return MAX_HEALTH


func is_alive() -> bool:
	return _alive


func is_engaged() -> bool:
	return _fighting() or _leave_left > 0.0


func battle_radius() -> float:
	return CrawlerRules.TREE_BATTLE_RADIUS


func arena_radius() -> float:
	return battle_radius()


func wild_kind() -> String:
	return "tree"


func set_arena_boundary_visible(shown: bool) -> void:
	if _boundary != null and _boundary.has_method(&"set_active"):
		_boundary.call(&"set_active", shown and _alive and _fighting())


func apply_damage(hit: DamageHit) -> float:
	if hit == null or not _alive or not _is_host() or not _accepts_hit(hit):
		return 0.0
	if _phase != Phase.PHASE2:
		return 0.0
	var actual := minf(maxf(hit.amount, 0.0) if is_finite(hit.amount) else 0.0, _health)
	if actual <= 0.0:
		return 0.0
	_health -= actual
	if hit.source_peer > 0:
		last_source_peer = hit.source_peer
	_set_face("hurt")
	_publish_health()
	if _health <= 0.0:
		_slay()
	return actual


func _accepts_hit(hit: DamageHit) -> bool:
	return hit.faction == DamageHit.Faction.PLAYER


func _fighting() -> bool:
	return _phase == Phase.PHASE1 or _phase == Phase.PHASE2 \
		or _phase == Phase.INTRO or _phase == Phase.PHASE2_INTRO


func _watch_enter() -> void:
	var insider := _nearest_inside()
	if insider == null:
		return
	if _phase == Phase.FAILED or _intro_seen:
		_restart_fight()
		return
	_begin_intro()


func _begin_intro() -> void:
	_phase = Phase.INTRO
	_intro_seen = true
	_health = MAX_HEALTH
	_restore_bushels()
	_clear_minions()
	_dismiss_field()
	_scream_fired = false
	_set_trunk_hittable(false)
	_set_face("happy")
	_play_clip("sway")
	_present_titles(true)
	_start_cutscene()
	_leave_left = 0.0


func _restart_fight() -> void:
	_phase = Phase.PHASE1
	_health = MAX_HEALTH
	_restore_bushels()
	_clear_minions()
	_dismiss_field()
	_set_trunk_hittable(false)
	_set_face("angry")
	_play_clip("scream")
	_scream_hold = 1.15
	_shockwave()
	_disk_left = 0.4
	_leave_left = 0.0
	_publish_health()


func _begin_phase2() -> void:
	if _phase2_seen or CrawlerRules.coop():
		_enter_phase2()
		return
	_phase = Phase.PHASE2_INTRO
	_phase2_seen = true
	_set_face("angry")
	_play_clip("tentacle")
	_present_skip()
	_start_cutscene()


func _enter_phase2() -> void:
	_phase = Phase.PHASE2
	_phase2_seen = true
	_set_trunk_hittable(true)
	_set_face("angry")
	_play_clip("tentacle")
	_spawn_fruit()
	_sweep_left = 2.4
	_sweep_wind = 0.0


func _tick_cutscene(delta: float) -> void:
	if _cutscene != null and _cutscene.has_method(&"is_playing") \
			and bool(_cutscene.call(&"is_playing")):
		if _phase == Phase.INTRO:
			if _age_of_cutscene() > 0.4 and _age_of_cutscene() < 0.55:
				_set_face("angry")
			if not _scream_fired and _age_of_cutscene() > 0.62:
				_scream_fired = true
				_set_face("scream")
				_play_clip("scream")
				_shockwave()
		return
	if _phase == Phase.INTRO:
		_phase = Phase.PHASE1
		_set_face("angry")
		_play_clip("sway")
		_disk_left = 0.2
	elif _phase == Phase.PHASE2_INTRO:
		_enter_phase2()
	delta = maxf(delta, 0.0)


func _age_of_cutscene() -> float:
	if _cutscene == null:
		return 0.0
	if _cutscene.has_method(&"age"):
		return float(_cutscene.call(&"age"))
	return float(_cutscene.get("_age"))


func _tick_phase1(delta: float) -> void:
	_set_face("angry")
	_scream_hold = maxf(_scream_hold - delta, 0.0)
	if _scream_hold <= 0.0:
		_play_clip("sway")
	_disk_left = maxf(_disk_left - delta, 0.0)
	if _disk_left <= 0.0:
		_fire_disk()
		_disk_left = DISK_GAP
	if _bushels_left() <= 0:
		_begin_phase2()


func _tick_phase2(delta: float) -> void:
	_play_clip("tentacle")
	_sweep_left = maxf(_sweep_left - delta, 0.0)
	if _sweep_wind > 0.0:
		_sweep_wind = maxf(_sweep_wind - delta, 0.0)
		_lean(1.0 - _sweep_wind / SWEEP_WINDUP)
		if _sweep_wind <= 0.0:
			_slam_sweep()
			_lean(0.0)
	elif _sweep_left <= 0.0:
		_sweep_wind = SWEEP_WINDUP
		_sweep_left = SWEEP_GAP
	if _fruit_alive() < 4:
		_spawn_fruit(4)


func _tick_leave(delta: float) -> void:
	if not _fighting() or _phase == Phase.INTRO or _phase == Phase.PHASE2_INTRO:
		return
	if _anyone_inside():
		_leave_left = 0.0
		return
	_leave_left += delta
	if _leave_left < RESET_DEBOUNCE:
		return
	_fail_battle()


func _fail_battle() -> void:
	_phase = Phase.FAILED
	_leave_left = 0.0
	_set_trunk_hittable(false)
	_clear_minions()
	_set_face("happy")
	_play_clip("sway")
	set_arena_boundary_visible(false)
	_present_fail()
	_publish_health()


func _slay() -> void:
	if not _alive:
		return
	_alive = false
	_phase = Phase.SLAIN
	_set_trunk_hittable(false)
	_clear_minions()
	set_arena_boundary_visible(false)
	_present_slain()
	_pay_spoils()
	_drop_ability()
	_heal_insiders()
	_complete_achievement()
	died.emit()
	_publish_health()
	var model := get_node_or_null("Model") as Node3D
	if model != null:
		model.visible = false
	var world := DamageHit.game_world_of(self)
	CrawlerBurst.leaves(
		world if world != null else get_parent(),
		combat_position(), _up(), 8.0)


func _start_cutscene() -> void:
	if _cutscene != null:
		_cutscene.queue_free()
	var local := _local_inside()
	_cutscene = CUTSCENE.new()
	add_child(_cutscene)
	if local == null:
		return
	var look_at := global_position + _up() * (TARGET_HEIGHT * 0.52)
	var from := look_at + _front * 36.0 + _up() * 6.0
	_cutscene.call(&"play", local, from, look_at, not CrawlerRules.coop())


func _present_titles(skip_hint: bool) -> void:
	var local := _local_inside()
	if local == null:
		return
	var hud := local.combat_hud()
	var host: Node = hud if hud != null else local
	TITLE.present(host, "BOSS BATTLE", DISPLAY_NAME, true, skip_hint)


func _present_skip() -> void:
	var local := _local_inside()
	if local == null:
		return
	var hud := local.combat_hud()
	TITLE.present_skip(hud if hud != null else local)


func _present_fail() -> void:
	var local := _local_audience()
	if local == null:
		return
	var hud := local.combat_hud()
	TITLE.present(hud if hud != null else local, "Battle Failed")


func _present_slain() -> void:
	var local := _local_audience()
	if local == null:
		return
	var hud := local.combat_hud()
	TITLE.present(hud if hud != null else local, "Boss Slain")


func _pay_spoils() -> void:
	for player: OnlinePlayer in _players_inside():
		if player.crawler_progress != null:
			player.crawler_progress.grant_spoils(SPOIL_GOLD, SPOIL_GEMS, SPOIL_XP)


func _heal_insiders() -> void:
	for player: OnlinePlayer in _players_inside():
		if player.has_method(&"apply_heal") and player.has_method(&"maximum_health"):
			player.call(&"apply_heal", float(player.call(&"maximum_health")))


func _complete_achievement() -> void:
	for player: OnlinePlayer in _players_inside():
		if player.journal != null:
			player.journal.complete(ACHIEVEMENT)


func _drop_ability() -> void:
	var world := DamageHit.game_world_of(self) as GameWorld
	if world == null or not world.has_method(&"spawn_crawler_card_loot"):
		return
	var ability := CrawlerCatalog.make_ability("starfire")
	if ability == null:
		return
	ability.add_shop_rank()
	ability.add_upgrade_rank("damage")
	var mod := CrawlerCatalog.make_modifier("toxic")
	if mod != null:
		mod.add_shop_rank()
		mod.add_upgrade_rank("duration")
		ability.place_mod(0, mod)
	var at := global_position + _front * 8.0 + _up() * 1.2
	world.call(&"spawn_crawler_card_loot", ability.to_dict(), at)


func _dismiss_field() -> void:
	var horde := CrawlerHorde.instance(get_tree())
	if horde != null:
		horde.dismiss_near(global_position, battle_radius())


func _fire_disk() -> void:
	var host := get_parent()
	if host == null:
		return
	var from := global_position + _up() * (TARGET_HEIGHT * 0.92)
	var yaw := _rng.randf() * TAU
	var east := _up().cross(Vector3.RIGHT)
	if east.length_squared() < 0.01:
		east = _up().cross(Vector3.FORWARD)
	east = east.normalized()
	var north := _up().cross(east).normalized()
	var along := (east * cos(yaw) + north * sin(yaw)).normalized()
	var disk: Node = LEAF.new()
	disk.call(&"launch", host, from, along, self, _rng.randf_range(20.0, 50.0))


func _slam_sweep() -> void:
	var hit := DamageHit.area(combat_position(), SWEEP_REACH, SWEEP_DAMAGE, 0.3)
	hit.kind = DamageHit.Kind.AREA
	hit.faction = DamageHit.Faction.ENEMY
	hit.ability_id = "giving_tree_sweep"
	hit.affects_flora = false
	hit.affects_combatants = true
	hit.reaction = DamageHit.Reaction.KNOCKBACK
	hit.radial_impulse = 12.0
	hit.radial_lift = 5.0
	hit.set_source(self)
	DamageHit.apply_to_combatants(self, hit)


func _shockwave() -> void:
	if _wave == null:
		_wave = WAVE.new()
		add_child(_wave)
	if _wave.has_method(&"set_wave"):
		_wave.call(&"set_wave", combat_position(), battle_radius() * 0.92)
	var hit := DamageHit.area(combat_position(), battle_radius(), 4.0, 0.2)
	hit.kind = DamageHit.Kind.AREA
	hit.faction = DamageHit.Faction.ENEMY
	hit.ability_id = "giving_tree_scream"
	hit.affects_flora = false
	hit.affects_combatants = true
	hit.reaction = DamageHit.Reaction.KNOCKBACK
	hit.radial_impulse = 14.0
	hit.radial_lift = 6.0
	hit.set_source(self)
	DamageHit.apply_to_combatants(self, hit)


func _spawn_fruit(want := FRUIT_COUNT) -> void:
	if _fruit_host == null:
		_fruit_host = get_parent()
	if _fruit_host == null:
		return
	var need := maxi(want - _fruit_alive(), 0)
	var tints: Array = FRUIT.TINTS
	for index in need:
		var fruit: Node = FRUIT.new()
		fruit.call(&"configure_fruit", tints[index % tints.size()])
		var yaw := _rng.randf() * TAU
		var reach := _rng.randf_range(12.0, 22.0)
		var east := _up().cross(Vector3.RIGHT)
		if east.length_squared() < 0.01:
			east = _up().cross(Vector3.FORWARD)
		east = east.normalized()
		var north := _up().cross(east).normalized()
		var at := global_position + (east * cos(yaw) + north * sin(yaw)) * reach + _up() * 2.2
		var xform := Transform3D(Basis(), at)
		fruit.call(&"configure", "fruit-%d" % _rng.randi(), xform, 3, true)
		_fruit_host.add_child(fruit)


func _fruit_alive() -> int:
	if not is_inside_tree():
		return 0
	var count := 0
	for node_variant: Variant in get_tree().get_nodes_in_group(CrawlerMob.GROUP):
		var node := node_variant as Node
		if node != null and is_instance_valid(node) and node.get_script() == FRUIT:
			count += 1
	return count


func _clear_minions() -> void:
	if not is_inside_tree():
		return
	for node_variant: Variant in get_tree().get_nodes_in_group(CrawlerMob.GROUP):
		var node := node_variant as Node
		if node != null and node.get_script() == FRUIT:
			node.queue_free()
	var host := get_parent()
	if host == null:
		return
	for child in host.get_children():
		if child.get_script() == LEAF:
			child.queue_free()


func _bushels_left() -> int:
	var live := 0
	for bushel: Node in _bushels:
		if bushel != null and bushel.has_method(&"is_alive") \
				and bool(bushel.call(&"is_alive")):
			live += 1
	return live


func _restore_bushels() -> void:
	for bushel: Node in _bushels:
		if bushel != null and bushel.has_method(&"restore"):
			bushel.call(&"restore")


func _build_body() -> void:
	var shape := CollisionShape3D.new()
	var cylinder := CylinderShape3D.new()
	cylinder.radius = TRUNK * 0.42
	cylinder.height = TARGET_HEIGHT * 0.55
	shape.shape = cylinder
	shape.position = Vector3(0.0, cylinder.height * 0.5, 0.0)
	add_child(shape)
	if not _attach_model():
		_build_fallback()
	_front = _facing()


func _attach_model() -> bool:
	if not ResourceLoader.exists(MODEL_PATH):
		return false
	var packed := load(MODEL_PATH) as PackedScene
	if packed == null:
		return false
	var model := packed.instantiate() as Node3D
	if model == null:
		return false
	model.name = "Model"
	add_child(model)
	_model = model
	_authored_height = maxf(_model_height(model), 4.0)
	var scale := TARGET_HEIGHT / _authored_height
	model.scale = Vector3.ONE * scale
	_animator = model.find_child("AnimationPlayer", true, false) as AnimationPlayer
	for node_variant: Variant in model.find_children("*", "MeshInstance3D", true, false):
		var mesh := node_variant as MeshInstance3D
		if mesh == null:
			continue
		var folded := mesh.name.to_lower()
		if folded.contains("face"):
			_face_meshes.append(mesh)
		if folded.contains("foliage") or folded.contains("damage"):
			_make_bushel(mesh)
	if _bushels.is_empty():
		_make_dummy_bushels(model)
	return true


func _build_fallback() -> void:
	var mesh := CylinderMesh.new()
	mesh.top_radius = TRUNK * 0.16
	mesh.bottom_radius = TRUNK * 0.48
	mesh.height = TARGET_HEIGHT * 0.62
	var visual := MeshInstance3D.new()
	visual.name = "Model"
	visual.mesh = mesh
	visual.position = Vector3(0.0, mesh.height * 0.5, 0.0)
	add_child(visual)
	_model = visual
	_make_dummy_bushels(visual)


func _make_dummy_bushels(host: Node3D) -> void:
	for index in 6:
		var bulb := MeshInstance3D.new()
		bulb.name = "Foliage_%02d" % (index + 1)
		var ball := SphereMesh.new()
		ball.radius = 2.4
		bulb.mesh = ball
		bulb.position = Vector3(
			sin(float(index) * 1.1) * 6.0,
			TARGET_HEIGHT * 0.55,
			cos(float(index) * 1.1) * 6.0)
		host.add_child(bulb)
		_make_bushel(bulb)


func _make_bushel(mesh: MeshInstance3D) -> void:
	var hp := 50.0 + float(absi(hash(mesh.name)) % 51)
	var bushel: Node = BUSHEL.new()
	bushel.name = "Bushel_%s" % mesh.name
	bushel.call(&"configure", mesh.name, mesh, hp)
	add_child(bushel)
	_bushels.append(bushel)


func _bind_boundary() -> void:
	_boundary = BOUNDARY.new()
	add_child(_boundary)
	if _planet != null and _boundary.has_method(&"configure"):
		var direction := global_position.normalized() \
			if global_position.length_squared() > 0.01 else Vector3.UP
		_boundary.call(&"configure", _planet, direction, battle_radius())


func _clear_flora() -> void:
	var direction := global_position.normalized() \
		if global_position.length_squared() > 0.01 else Vector3.UP
	var site := get_parent()
	if site is PatchMonument:
		direction = (site as PatchMonument).direction
	BuildingFloraClear.register_node(
		self, _model if _model != null else self, direction,
		CrawlerRules.TREE_FLORA_CLEAR, 0.0)


func _model_height(root: Node3D) -> float:
	var bounds := AABB()
	var started := false
	for node_variant: Variant in root.find_children("*", "MeshInstance3D", true, false):
		var mesh := node_variant as MeshInstance3D
		if mesh == null or mesh.mesh == null:
			continue
		var box := mesh.global_transform * mesh.mesh.get_aabb()
		if started:
			bounds = bounds.merge(box)
		else:
			bounds = box
			started = true
	return bounds.size.y if started else 12.0


func _facing() -> Vector3:
	var up := _up()
	if not _face_meshes.is_empty() and _face_meshes[0] != null:
		var along := _face_meshes[0].global_position - global_position
		along -= up * along.dot(up)
		if along.length_squared() > 0.04:
			return along.normalized()
	var along := -global_basis.z
	along -= up * along.dot(up)
	if along.length_squared() > 0.04:
		return along.normalized()
	return up.cross(Vector3.RIGHT).normalized()


func _play_clip(need: String) -> void:
	if _animator == null:
		return
	_animator.process_mode = Node.PROCESS_MODE_ALWAYS
	var clip := _find_clip(need)
	if clip.is_empty() or not _animator.has_animation(clip):
		return
	if _animator.current_animation == clip and _animator.is_playing():
		return
	_animator.play(clip)


func _find_clip(need: String) -> String:
	if _animator == null:
		return ""
	var folded := need.to_lower()
	var any := ""
	for clip: String in _animator.get_animation_list():
		var name := clip.to_lower()
		if not name.contains(folded):
			continue
		if any.is_empty():
			any = clip
		if name.contains("body"):
			return clip
	return any


func _set_trunk_hittable(on: bool) -> void:
	if on:
		if not is_in_group(DamageHit.COMBATANT_GROUP):
			add_to_group(DamageHit.COMBATANT_GROUP)
	elif is_in_group(DamageHit.COMBATANT_GROUP):
		remove_from_group(DamageHit.COMBATANT_GROUP)


func bushel_count() -> int:
	return _bushels.size()


func _set_face(mood: String) -> void:
	var want := mood.to_lower()
	for mesh: MeshInstance3D in _face_meshes:
		if mesh == null or mesh.mesh == null:
			continue
		for index in mesh.get_blend_shape_count():
			var shape := String(mesh.mesh.get_blend_shape_name(index)).to_lower()
			var weight := 1.0 if shape.contains(want) else 0.0
			mesh.set_blend_shape_value(index, weight)


func _lean(amount: float) -> void:
	if _model == null:
		return
	_model.rotation.x = -0.38 * clampf(amount, 0.0, 1.0)


func _anyone_inside() -> bool:
	return _nearest_inside() != null


func _nearest_inside() -> OnlinePlayer:
	var best: OnlinePlayer
	var best_span := INF
	for player: OnlinePlayer in _all_players():
		var span := _arena_distance(player)
		if span <= battle_radius() and span < best_span:
			best_span = span
			best = player
	return best


func _players_inside() -> Array[OnlinePlayer]:
	var out: Array[OnlinePlayer] = []
	for player: OnlinePlayer in _all_players():
		if _arena_distance(player) <= battle_radius():
			out.append(player)
	return out


func _local_inside() -> OnlinePlayer:
	var local := _local_player()
	if local != null and _arena_distance(local) <= battle_radius():
		return local
	return null


func _local_audience() -> OnlinePlayer:
	var local := _local_player()
	if local != null and _arena_distance(local) <= battle_radius() * 2.0:
		return local
	return null


func _local_player() -> OnlinePlayer:
	if not is_inside_tree():
		return null
	var id := 1
	if multiplayer.has_multiplayer_peer():
		id = multiplayer.get_unique_id()
	for player: OnlinePlayer in _all_players():
		if player.peer_id == id:
			return player
	return null


func _all_players() -> Array[OnlinePlayer]:
	var out: Array[OnlinePlayer] = []
	if not is_inside_tree():
		return out
	for node_variant: Variant in get_tree().get_nodes_in_group(&"network_players"):
		var player := node_variant as OnlinePlayer
		if player != null:
			out.append(player)
	return out


func _arena_distance(body: Node3D) -> float:
	if body == null:
		return INF
	return BossAdapter.arena_distance_to(self, body)


func _up() -> Vector3:
	if _planet != null:
		var radial := _planet.up_at(global_position)
		if radial.length_squared() > 0.0001:
			return radial.normalized()
	if global_position.length_squared() > 0.01:
		return global_position.normalized()
	return Vector3.UP


func _find_planet() -> Planet:
	var walk := get_parent()
	while walk != null:
		if walk is Planet:
			return walk as Planet
		if walk is GameWorld:
			var found := (walk as GameWorld).planet()
			if found != null:
				return found
		walk = walk.get_parent()
	return null


func _is_host() -> bool:
	return not multiplayer.has_multiplayer_peer() or multiplayer.is_server()


func _publish_health() -> void:
	if not multiplayer.has_multiplayer_peer() or multiplayer.get_peers().is_empty():
		return
	_health_rpc.rpc(_health, _alive, int(_phase))


@rpc("authority", "unreliable")
func _health_rpc(hp: float, alive: bool, phase: int) -> void:
	_health = hp
	_alive = alive
	_phase = phase as Phase
	if not _alive and is_inside_tree():
		set_arena_boundary_visible(false)
