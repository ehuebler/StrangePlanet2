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
const DISK_SPHERE := 13.0
const DISK_SPHERE_INNER := 8.5
const SWEEP_GAP := 6.2
const SWEEP_WINDUP := 0.72
const SWEEP_RECOVER := 0.42
const SWEEP_DAMAGE := 18.0
const SWEEP_REACH := 32.0
const SWEEP_LEAN := 0.88
const FRUIT_COUNT := 10
const SPOIL_GOLD := 100
const SPOIL_GEMS := 10
const SPOIL_XP := 25
const ACHIEVEMENT := "first_boss"
const WAVE_EXPAND := 0.8

enum Phase { IDLE, INTRO, PHASE1, PHASE2_INTRO, PHASE2, FAILED, SLAIN }
enum IntroBeat { PAN, ROAR, TITLE, RETURN }

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
var _sweep_recover := 0.0
var _rng := RandomNumberGenerator.new()
var _authored_height := 12.0
var _fruit_host: Node
var _fruits: Array[Node] = []
var _model_rest := Transform3D.IDENTITY
var _model_rest_ready := false
var _scream_fired := false
var _scream_hold := 0.0
var _intro_beat := 0
var _roar_left := 0.0
var _title_card: Control
var _wave_age := 0.0
var _wave_live := false
var _arena_pulse := 0.0
var _bushel_pool := 0.0


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
	_seat_boundary()
	_clear_flora()
	_remember_bushel_pool()
	add_to_group(GROUP)
	add_to_group(BossAdapter.CRAWLER_GROUP)
	_set_face("happy")


func _physics_process(delta: float) -> void:
	if not _alive:
		_clear_wave()
		_hide_arena()
		return
	_tick_wave(delta)
	_tick_arena(delta)
	_orient_face(delta)
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
		var pool := _bushel_pool_max()
		if pool > 0.001:
			return MAX_HEALTH * (_bushel_pool_health() / pool)
		return MAX_HEALTH
	return _health


func maximum_health() -> float:
	return MAX_HEALTH


func is_alive() -> bool:
	return _alive


func is_engaged() -> bool:
	return _arena_live()


func battle_radius() -> float:
	return CrawlerRules.TREE_BATTLE_RADIUS


func arena_radius() -> float:
	return battle_radius()


func wild_kind() -> String:
	return "tree"


func set_arena_boundary_visible(shown: bool) -> void:
	_seat_boundary()
	if _boundary != null and _boundary.has_method(&"set_active"):
		_boundary.call(&"set_active", shown and _arena_live())


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


func _arena_live() -> bool:
	return _alive and (_fighting() or _leave_left > 0.0)


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
	_intro_beat = IntroBeat.PAN
	_roar_left = 0.0
	_title_card = null
	_set_trunk_hittable(false)
	_set_face("happy")
	_play_clip("sway")
	_start_cutscene()
	_leave_left = 0.0
	_arena_pulse = 0.0
	_tick_arena(0.0)
	_publish_health()


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
	_arena_pulse = 0.0
	_tick_arena(0.0)
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
	_start_cutscene(1.15)
	_publish_health()


func _enter_phase2() -> void:
	_phase = Phase.PHASE2
	_phase2_seen = true
	_set_trunk_hittable(true)
	_set_face("angry")
	_play_clip("tentacle")
	_spawn_fruit()
	_sweep_left = 1.1
	_sweep_wind = 0.0
	_sweep_recover = 0.0
	_sweep_pose(0.0)
	_publish_health()


func _tick_cutscene(delta: float) -> void:
	if _phase == Phase.PHASE2_INTRO:
		if _cutscene != null and _cutscene.has_method(&"is_playing") \
				and bool(_cutscene.call(&"is_playing")):
			return
		_enter_phase2()
		return
	_tick_intro(delta)


func _tick_intro(delta: float) -> void:
	var live := _cutscene != null and _cutscene.has_method(&"is_playing") \
			and bool(_cutscene.call(&"is_playing"))
	if not live:
		_dismiss_title()
		_enter_phase1()
		return
	match _intro_beat:
		IntroBeat.PAN:
			if _cutscene.has_method(&"has_arrived") \
					and bool(_cutscene.call(&"has_arrived")):
				if not _scream_fired:
					_set_face("angry")
				_fire_intro_roar()
				_intro_beat = IntroBeat.ROAR
		IntroBeat.ROAR:
			_roar_left = maxf(_roar_left - maxf(delta, 0.0), 0.0)
			if _roar_left <= 0.0:
				_title_card = _present_titles(true)
				_intro_beat = IntroBeat.TITLE
		IntroBeat.TITLE:
			if _title_card == null or not is_instance_valid(_title_card):
				if _cutscene.has_method(&"go_home"):
					_cutscene.call(&"go_home")
				_intro_beat = IntroBeat.RETURN
		IntroBeat.RETURN:
			pass


func _enter_phase1() -> void:
	_phase = Phase.PHASE1
	_set_face("angry")
	_play_clip("sway")
	_disk_left = 0.2
	_arena_pulse = 0.0
	_tick_arena(0.0)
	_publish_health()


func _fire_intro_roar() -> void:
	if _scream_fired:
		return
	_scream_fired = true
	_set_face("scream")
	_play_clip("scream")
	_shockwave()
	_roar_left = _clip_length("scream")
	if _roar_left <= 0.08:
		_roar_left = 1.15


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
		var wind := 1.0 - _sweep_wind / SWEEP_WINDUP
		_sweep_pose(-0.58 * wind)
		if _sweep_wind <= 0.0:
			_play_clip_now("tentacle")
			_sweep_pose(1.0)
			_slam_sweep()
			_sweep_recover = SWEEP_RECOVER
	elif _sweep_recover > 0.0:
		_sweep_recover = maxf(_sweep_recover - delta, 0.0)
		_sweep_pose(_sweep_recover / SWEEP_RECOVER)
		if _sweep_recover <= 0.0:
			_sweep_pose(0.0)
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
	_clear_wave()
	_present_fail()
	_publish_health()


func _slay() -> void:
	if not _alive:
		return
	_alive = false
	_phase = Phase.SLAIN
	_clear_wave()
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


func _start_cutscene(auto_return := -1.0) -> void:
	if _cutscene != null:
		_cutscene.queue_free()
	var local := _local_inside()
	_cutscene = CUTSCENE.new()
	add_child(_cutscene)
	if local == null:
		return
	_orient_face(1.0)
	_front = _facing()
	var shot := _intro_shot()
	_cutscene.call(
		&"play",
		local,
		shot["from"],
		shot["at"],
		not CrawlerRules.coop(),
		shot["fov"],
		auto_return,
		_up())


func _intro_shot() -> Dictionary:
	var up := _up()
	var face := _face_point()
	var front := _face_front(face, up)
	var trunk := global_position
	var above := (trunk + up * TARGET_HEIGHT - face).dot(up) + 6.0
	var below := (face - trunk).dot(up) + 6.0
	var need := maxf(maxf(above, below), TARGET_HEIGHT * 0.42)
	var fov := 70.0
	var dist := need / tan(deg_to_rad(fov * 0.5))
	dist = clampf(dist, 52.0, 120.0)
	return {
		"from": face + front * dist,
		"at": face,
		"fov": fov,
	}


func _face_point() -> Vector3:
	if not _face_meshes.is_empty() and _face_meshes[0] != null:
		var mesh := _face_meshes[0]
		if mesh.mesh != null:
			return mesh.to_global(mesh.get_aabb().get_center())
		return mesh.global_position
	return global_position + _up() * (TARGET_HEIGHT * 0.55)


func _face_front(face: Vector3, up: Vector3) -> Vector3:
	var along := face - global_position
	along -= up * along.dot(up)
	if along.length_squared() > 0.04:
		return along.normalized()
	if not _face_meshes.is_empty() and _face_meshes[0] != null:
		var mesh := _face_meshes[0]
		for axis: Vector3 in [
			-mesh.global_transform.basis.z,
			mesh.global_transform.basis.z,
			mesh.global_transform.basis.x,
			-mesh.global_transform.basis.x
		]:
			var flat := axis - up * axis.dot(up)
			if flat.length_squared() > 0.04:
				return flat.normalized()
	return _facing()


func _present_titles(skip_hint: bool) -> Control:
	var local := _local_inside()
	if local == null:
		return null
	var hud := local.combat_hud()
	var host: Node = hud if hud != null else local
	return TITLE.present(host, "BOSS BATTLE", DISPLAY_NAME, true, skip_hint)


func _dismiss_title() -> void:
	if _title_card != null and is_instance_valid(_title_card):
		_title_card.queue_free()
	_title_card = null
	var local := _local_inside()
	if local == null:
		return
	var hud := local.combat_hud()
	var host: Node = hud if hud != null else local
	var layer := host.get_node_or_null("CrawlerBossTitleLayer")
	if layer != null:
		layer.queue_free()


func _clip_length(need: String) -> float:
	if _animator == null:
		return 0.0
	var clip := _find_clip(need)
	if clip.is_empty() or not _animator.has_animation(clip):
		return 0.0
	return _animator.get_animation(clip).length


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


func _tick_arena(delta: float) -> void:
	if not _arena_live():
		_hide_arena()
		return
	if _boundary == null or _boundary.get(&"mesh") == null \
			or not _boundary.has_method(&"arena_radius") \
			or not is_equal_approx(
				float(_boundary.call(&"arena_radius")), battle_radius()):
		_seat_boundary()
	if _boundary != null and _boundary.has_method(&"set_active"):
		_boundary.call(&"set_active", true)
	if not _is_host():
		return
	_arena_pulse = maxf(_arena_pulse - maxf(delta, 0.0), 0.0)
	if _arena_pulse > 0.0:
		return
	_arena_pulse = 0.25
	_dismiss_field()


func _hide_arena() -> void:
	if _boundary != null and _boundary.has_method(&"set_active"):
		_boundary.call(&"set_active", false)


func _fire_disk() -> void:
	var host := get_parent()
	if host == null:
		return
	var disk: Node = LEAF.new()
	disk.call(
		&"launch",
		host,
		_disk_spawn_point(),
		Vector3.ZERO,
		self,
		_rng.randf_range(20.0, 50.0),
		CrawlerTreeLeafDisk.HOVER)


func _disk_spawn_point() -> Vector3:
	var up := _up()
	var centre := global_position + up * (TARGET_HEIGHT * 0.38)
	var dir := _random_unit()
	var at := centre + dir * _rng.randf_range(DISK_SPHERE_INNER, DISK_SPHERE)
	var height := (at - global_position).dot(up)
	if height < 2.4:
		at += up * (2.4 - height)
	return at


func _random_unit() -> Vector3:
	var dir := Vector3(
		_rng.randf_range(-1.0, 1.0),
		_rng.randf_range(-1.0, 1.0),
		_rng.randf_range(-1.0, 1.0))
	if dir.length_squared() < 0.0001:
		return _up()
	return dir.normalized()


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
	_wave_live = true
	_wave_age = 0.0
	if _wave.has_method(&"clear"):
		_wave.call(&"clear")
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


func _tick_wave(delta: float) -> void:
	if not _wave_live:
		return
	_wave_age += maxf(delta, 0.0)
	var reach := battle_radius() * 0.92
	var share := clampf(_wave_age / WAVE_EXPAND, 0.0, 1.0)
	if _wave != null and _wave.has_method(&"set_wave"):
		_wave.call(&"set_wave", combat_position(), reach * share)
	if _wave_age >= WAVE_EXPAND:
		_clear_wave()


func _clear_wave() -> void:
	_wave_live = false
	_wave_age = 0.0
	if _wave != null and _wave.has_method(&"clear"):
		_wave.call(&"clear")


func _spawn_fruit(want := FRUIT_COUNT) -> void:
	var host := _minion_host()
	if host == null:
		return
	_fruit_host = host
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
		var xform := _surface_xform(at)
		fruit.call(&"configure", "fruit-%d" % _rng.randi(), xform, 3, true)
		host.add_child(fruit)
		if fruit is Node3D:
			(fruit as Node3D).global_transform = xform
		if fruit is CrawlerMob:
			(fruit as CrawlerMob).hang_origin = at
		_fruits.append(fruit)


func _minion_host() -> Node:
	if is_inside_tree():
		var horde := CrawlerHorde.instance(get_tree())
		if horde != null:
			return horde
	var world := DamageHit.game_world_of(self)
	if world != null:
		return world
	if _planet != null:
		return _planet
	var found := _find_planet()
	if found != null:
		return found
	return get_parent()


func _surface_xform(at: Vector3) -> Transform3D:
	var up := _up()
	if _planet != null and at.is_finite() and _planet.has_method(&"up_at"):
		var radial: Vector3 = _planet.call(&"up_at", at)
		if radial.length_squared() > 0.0001:
			up = radial.normalized()
	var east := up.cross(Vector3.RIGHT)
	if east.length_squared() < 0.01:
		east = up.cross(Vector3.FORWARD)
	east = east.normalized()
	var north := east.cross(up).normalized()
	return Transform3D(Basis(east, up, north), at)


func _fruit_alive() -> int:
	var live := 0
	var kept: Array[Node] = []
	for fruit: Node in _fruits:
		if fruit == null or not is_instance_valid(fruit):
			continue
		if fruit.has_method(&"is_alive") and not bool(fruit.call(&"is_alive")):
			continue
		kept.append(fruit)
		live += 1
	_fruits = kept
	if live > 0 or not is_inside_tree():
		return live
	for node_variant: Variant in get_tree().get_nodes_in_group(CrawlerMob.GROUP):
		var node := node_variant as Node
		if node != null and is_instance_valid(node) and node.get_script() == FRUIT:
			live += 1
	return live


func _clear_minions() -> void:
	for fruit: Node in _fruits:
		if fruit != null and is_instance_valid(fruit):
			fruit.queue_free()
	_fruits.clear()
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
	_remember_bushel_pool()


func _bushel_pool_health() -> float:
	var total := 0.0
	for bushel: Node in _bushels:
		if bushel != null and bushel.has_method(&"health") \
				and bushel.has_method(&"is_alive") \
				and bool(bushel.call(&"is_alive")):
			total += maxf(float(bushel.call(&"health")), 0.0)
	return total


func _bushel_pool_max() -> float:
	if _bushel_pool > 0.001:
		return _bushel_pool
	var total := 0.0
	for bushel: Node in _bushels:
		if bushel != null and bushel.has_method(&"maximum_health"):
			total += maxf(float(bushel.call(&"maximum_health")), 0.0)
	return total


func _remember_bushel_pool() -> void:
	_bushel_pool = 0.0
	for bushel: Node in _bushels:
		if bushel != null and bushel.has_method(&"maximum_health"):
			_bushel_pool += maxf(float(bushel.call(&"maximum_health")), 0.0)


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
	_model_rest = model.transform
	_model_rest_ready = true
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
	# Seat the combatant on the foliage mesh so a ray that hits the leaf box
	# walks up to the bushel, not only the trunk.
	mesh.add_child(bushel)
	_bushels.append(bushel)


func _seat_boundary() -> void:
	if _boundary == null:
		_boundary = BOUNDARY.new()
		add_child(_boundary)
	if _planet == null:
		_planet = _find_planet()
	if _planet == null or not _boundary.has_method(&"configure"):
		return
	var direction := Vector3.ZERO
	var site := get_parent()
	if site is PatchMonument:
		direction = (site as PatchMonument).direction
	if direction.length_squared() < 0.25:
		direction = global_position.normalized() \
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
		var mesh := _face_meshes[0]
		var at := mesh.global_position
		if mesh.mesh != null:
			at = mesh.to_global(mesh.get_aabb().get_center())
		var along := at - global_position
		along -= up * along.dot(up)
		if along.length_squared() > 0.04:
			return along.normalized()
	var along := -global_basis.z
	along -= up * along.dot(up)
	if along.length_squared() > 0.04:
		return along.normalized()
	return up.cross(Vector3.RIGHT).normalized()


func _orient_face(delta: float) -> void:
	if not _alive:
		return
	if _sweep_wind > 0.0 or _sweep_recover > 0.0:
		return
	if (_phase == Phase.INTRO or _phase == Phase.PHASE2_INTRO) \
			and _cutscene != null and _cutscene.has_method(&"is_playing") \
			and bool(_cutscene.call(&"is_playing")):
		return
	var prey := _gaze_target()
	if prey == null:
		return
	var up := _up()
	var dest := prey.global_position
	if prey.has_method(&"combat_position"):
		var marked: Variant = prey.call(&"combat_position")
		if marked is Vector3 and (marked as Vector3).is_finite():
			dest = marked
	var want := dest - _face_point()
	want -= up * want.dot(up)
	if want.length_squared() < 0.04:
		return
	want = want.normalized()
	var current := _facing()
	if current.length_squared() < 0.0001:
		return
	var angle := current.signed_angle_to(want, up)
	if absf(angle) < 0.002:
		return
	var step := 1.0 if delta >= 0.999 else clampf(delta * 8.0, 0.0, 1.0)
	rotate(up, angle * step)


func _gaze_target() -> Node3D:
	if not is_inside_tree():
		return null
	var best: Node3D
	var best_span := INF
	for node_variant: Variant in get_tree().get_nodes_in_group(&"network_players"):
		var body := node_variant as Node3D
		if body == null or not is_instance_valid(body):
			continue
		var at := body.global_position
		if body.has_method(&"combat_position"):
			var marked: Variant = body.call(&"combat_position")
			if marked is Vector3 and (marked as Vector3).is_finite():
				at = marked
		var span := _face_point().distance_to(at)
		if span < best_span:
			best_span = span
			best = body
	return best


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


func _play_clip_now(need: String) -> void:
	if _animator == null:
		return
	_animator.process_mode = Node.PROCESS_MODE_ALWAYS
	var clip := _find_clip(need)
	if clip.is_empty() or not _animator.has_animation(clip):
		return
	_animator.stop()
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
	_sweep_pose(amount)


func _sweep_pose(amount: float) -> void:
	if _model == null:
		return
	if not _model_rest_ready:
		_model_rest = _model.transform
		_model_rest_ready = true
	var tilt := clampf(amount, -1.0, 1.0)
	if absf(tilt) < 0.001:
		_model.transform = _model_rest
		return
	var face := _sweep_along()
	var axis := _up().cross(face)
	if axis.length_squared() < 0.0001:
		_model.transform = _model_rest
		return
	axis = (global_transform.basis.inverse() * axis.normalized()).normalized()
	if axis.length_squared() < 0.0001:
		_model.transform = _model_rest
		return
	_model.transform = Transform3D(
		Basis(axis, SWEEP_LEAN * tilt), Vector3.ZERO) * _model_rest


func _sweep_along() -> Vector3:
	var up := _up()
	var prey := _gaze_target()
	var dest := Vector3.ZERO
	if prey != null:
		dest = prey.global_position
		if prey.has_method(&"combat_position"):
			var marked: Variant = prey.call(&"combat_position")
			if marked is Vector3 and (marked as Vector3).is_finite():
				dest = marked
	var along := dest - global_position if prey != null else _facing()
	along -= up * along.dot(up)
	if along.length_squared() > 0.04:
		return along.normalized()
	var face := _facing()
	face -= up * face.dot(up)
	if face.length_squared() > 0.04:
		return face.normalized()
	return up.cross(Vector3.RIGHT).normalized()


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
