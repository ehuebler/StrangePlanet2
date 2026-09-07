extends Node

## Headless ability + mod + hat/cape fire harness.
##
##     godot --headless --path . res://dev/_ability_combo_test.tscn
##     godot --headless --path . res://dev/_ability_combo_test.tscn -- small
##     godot --headless --path . res://dev/_ability_combo_test.tscn -- pairs
##     godot --headless --path . res://dev/_ability_combo_test.tscn -- pairs 24
##
## Slot specs accept ability/mod upgrade ranks, extra hotbar cards, and hat/cape
## ids. The run writes `dev/logs/ability_combo_latest.json` plus a `.txt` report
## with timestamps, durations, damage, statuses, and auto-anomalies.

const PLAYER := preload("res://game/player/player.tscn")
const TEST_CYCLE := preload("res://dev/_multiplayer_test_cycle.gd")
const LOG_DIR := "res://dev/logs"
const STEP := 0.05
const WORLD_AFTER := 1.20
const DEFAULT_HOLD := 0.85

var _player: OnlinePlayer
var _world: GameWorld
var _probes: Array[Probe] = []
var _clock := 0.0
var _events: Array = []
var _report: Dictionary = {}
var _peak_bubbles := 0
var _peak_lingers := 0
var _peak_fields := 0
var _peak_projectiles := 0


class HarnessWorld extends GameWorld:
	func _ready() -> void:
		process_mode = Node.PROCESS_MODE_INHERIT
		NetworkManager.active_world = self
		set_physics_process(false)
		set_process(false)


class Probe extends StaticBody3D:
	var probe_id := 0
	var block_shots := false
	var taken := 0.0
	var hits: Array = []
	var statuses := CombatStatuses.new()
	var clock_ref: Callable = Callable()

	func _ready() -> void:
		add_to_group(DamageHit.COMBATANT_GROUP)
		collision_layer = 0xFFFFFFFF if block_shots else 0
		collision_mask = 0
		var shape := CollisionShape3D.new()
		var sphere := SphereShape3D.new()
		sphere.radius = 0.85 if block_shots else 0.55
		shape.shape = sphere
		add_child(shape)

	func apply_damage(hit: DamageHit) -> float:
		if hit == null:
			return 0.0
		var amount := float(hit.amount)
		taken += amount
		var stamp := {
			"t": _now(),
			"probe": probe_id,
			"amount": amount,
			"ability": str(hit.ability_id),
			"status": String(hit.status),
			"status_duration": float(hit.status_duration),
			"status_strength": float(hit.status_strength),
			"statuses": _status_rows(hit),
		}
		hits.append(stamp)
		CrawlerElements.apply_to_combatant(self, hit)
		return amount

	func combat_position() -> Vector3:
		return global_position

	func combat_radius() -> float:
		return 0.55

	func combat_faction() -> int:
		return DamageHit.Faction.ENEMY

	func is_alive() -> bool:
		return true

	func is_dead() -> bool:
		return false

	func is_charmed() -> bool:
		return statuses.has(CombatStatuses.CHARM)

	func _now() -> float:
		if clock_ref.is_valid():
			return float(clock_ref.call())
		return 0.0

	func _status_rows(hit: DamageHit) -> Array:
		var rows: Array = []
		if hit == null:
			return rows
		for raw: Variant in hit.status_entries():
			if raw is Dictionary:
				rows.append((raw as Dictionary).duplicate(true))
		return rows


func _ready() -> void:
	CrawlerCatalog.reload()
	CrawlerMeta.begin_test()
	Journal.begin_test()
	NetworkManager.session_options = {"mode": "crawler"}
	CrawlerKit.clear_session()
	CrawlerProgress.clear_session()
	multiplayer.multiplayer_peer = OfflineMultiplayerPeer.new()
	NetworkManager.is_single_player = true
	NetworkManager.is_host = true
	NetworkManager.state = NetworkManager.SessionState.IN_GAME
	_world = _make_world()
	add_child(_world)
	_player = PLAYER.instantiate() as OnlinePlayer
	_player.peer_id = multiplayer.get_unique_id()
	_world.add_child(_player)
	_player.set_process(false)
	_player.set_physics_process(false)
	var controller := _player.ability_controller()
	if controller != null:
		controller.set_physics_process(false)
	await get_tree().process_frame
	_player.global_position = Vector3(0.0, 2.0, 0.0)
	_player.global_rotation = Vector3.ZERO
	_run()
	_write_logs()
	_print_summary()
	_player.queue_free()
	await get_tree().process_frame
	NetworkManager.session_options.clear()
	CrawlerKit.clear_session()
	CrawlerProgress.clear_session()
	CrawlerMeta.end_test()
	Journal.end_test()
	get_tree().quit(0)


func _make_world() -> GameWorld:
	var world := HarnessWorld.new()
	world.name = "HarnessWorld"
	var spawn_points := Node3D.new()
	spawn_points.name = "SpawnPoints"
	var marker := Marker3D.new()
	marker.name = "Spawn1"
	marker.position = Vector3(0.0, 2.0, 0.0)
	spawn_points.add_child(marker)
	world.add_child(spawn_points)
	var cycle := TEST_CYCLE.new() as CelestialCycle
	cycle.name = "CelestialCycle"
	world.add_child(cycle)
	return world


func _run() -> void:
	var mode := _requested_mode()
	var cases: Array = _small_cases()
	if mode == "pairs":
		cases.append_array(_pair_cases(_pair_cap()))
	_report = {
		"started": Time.get_datetime_string_from_system(true, true),
		"mode": mode,
		"case_count": cases.size(),
		"cases": [],
		"anomalies": [],
		"by_id": {},
	}
	var index := 0
	for raw: Variant in cases:
		if not (raw is Dictionary):
			continue
		index += 1
		var spec := raw as Dictionary
		var row := _run_case(spec, index)
		(_report["cases"] as Array).append(row)
		(_report["by_id"] as Dictionary)[str(row.get("id", ""))] = row
		print("ability_combo: %s  dmg=%.2f hits=%d bubbles=%d lingers=%d fields=%d shots=%d"
			% [
				str(row.get("id", "")),
				float(row.get("damage", 0.0)),
				int(row.get("hit_count", 0)),
				int(row.get("bubbles", 0)),
				int(row.get("lingers", 0)),
				int(row.get("fields", 0)),
				int(row.get("projectiles", 0)),
			])
	_detect_anomalies()
	_report["finished"] = Time.get_datetime_string_from_system(true, true)
	_report["anomaly_count"] = (_report["anomalies"] as Array).size()


func _requested_mode() -> String:
	var args := OS.get_cmdline_user_args()
	if args.is_empty():
		return "small"
	var mode := str(args[0]).strip_edges().to_lower()
	if mode.is_empty():
		return "small"
	return mode


func _pair_cap() -> int:
	var args := OS.get_cmdline_user_args()
	if args.size() < 2:
		return 0
	return maxi(int(args[1]), 0)


func _small_cases() -> Array:
	return [
		_case("hero_punch", {
			"slots": [_slot("hero_punch")],
			"expect_damage": true,
		}),
		_case("hero_punch_toxic", {
			"slots": [_slot("hero_punch", {}, [_mod("toxic")])],
			"expect_damage": true,
			"expect_toxic": true,
		}),
		_case("hero_punch_bubble", {
			"slots": [_slot("hero_punch", {}, [_mod("bubble")])],
			"expect_damage": true,
			"expect_bubbles": true,
		}),
		_case("hero_punch_bubble_toxic", {
			"slots": [_slot("hero_punch", {}, [_mod("bubble"), _mod("toxic")])],
			"expect_damage": true,
			"expect_bubbles": true,
			"expect_toxic": true,
			"expect_bubble_toxic": true,
		}),
		_case("hero_punch_bubble_toxic_up1", {
			"slots": [_slot("hero_punch", {}, [
				_mod("bubble"),
				_mod("toxic", {"toxic": 1}),
			])],
			"expect_damage": true,
			"expect_bubbles": true,
			"expect_toxic": true,
			"expect_bubble_toxic": true,
			"compare": "hero_punch_bubble_toxic",
			"compare_metric": "toxic_strength",
		}),
		_case("laser_eyes", {
			"slots": [_slot("laser_eyes")],
			"hold": 0.50,
			"expect_damage": true,
		}),
		_case("laser_eyes_bubble_toxic", {
			"slots": [_slot("laser_eyes", {}, [_mod("bubble"), _mod("toxic")])],
			"hold": 0.50,
			"expect_damage": true,
			"expect_bubbles": true,
			"expect_toxic": true,
			"expect_bubble_toxic": true,
		}),
		_case("laser_eyes_bubble_toxic_up1", {
			"slots": [_slot("laser_eyes", {}, [
				_mod("bubble"),
				_mod("toxic", {"toxic": 1}),
			])],
			"hold": 0.50,
			"expect_damage": true,
			"expect_bubbles": true,
			"expect_toxic": true,
			"expect_bubble_toxic": true,
			"compare": "laser_eyes_bubble_toxic",
			"compare_metric": "toxic_strength",
		}),
		_case("roar_bubble", {
			"slots": [_slot("roar", {}, [_mod("bubble")])],
			"hold": CrawlerRules.ROAR_WINDUP + CrawlerRules.ROAR_EXPAND,
			"expect_damage": true,
			"expect_bubbles": true,
		}),
		_case("hero_punch_linger", {
			"slots": [_slot("hero_punch", {}, [_mod("linger")])],
			"expect_damage": true,
			"expect_lingers": true,
		}),
		_case("hero_punch_gale_hat", {
			"slots": [_slot("hero_punch")],
			"hat": CrawlerProgress.HAT_ID,
			"expect_damage": true,
		}),
		_case("hero_punch_fool_cape", {
			"slots": [_slot("hero_punch")],
			"cape": CrawlerProgress.CAPE_FOOL,
			"expect_damage": true,
		}),
		_case("overdrive_toxic_then_laser", {
			"slots": [
				_slot("laser_eyes"),
				_slot("overdrive", {}, [_mod("toxic")]),
			],
			"sequence": [
				{"slot": 1, "hold": 0.20},
				{"slot": 0, "hold": 0.50},
			],
			"expect_damage": true,
			"expect_toxic": true,
		}),
		_case("starfire", {
			"slots": [_slot("starfire")],
			"hold": 0.45,
			"expect_damage": true,
			"expect_projectiles": true,
		}),
		_case("starfire_bubble", {
			"slots": [_slot("starfire", {}, [_mod("bubble")])],
			"hold": 0.45,
			"expect_damage": true,
			"expect_bubbles": true,
			"expect_projectiles": true,
		}),
		_case("fus", {
			"slots": [_slot("fus")],
			"expect_damage": true,
			"expect_projectiles": true,
		}),
		_case("static_field", {
			"slots": [_slot("static_field")],
			"hold": CrawlerRules.FIELD_CAST + 0.35,
			"world_after": 1.60,
			"expect_damage": true,
			"expect_fields": true,
		}),
		_case("toxic_field", {
			"slots": [_slot("toxic_field")],
			"hold": CrawlerRules.FIELD_CAST + 0.35,
			"world_after": 1.60,
			"expect_fields": true,
			"expect_toxic": true,
		}),
		_case("nuke", {
			"slots": [_slot("nuke")],
			"hold": 0.35,
			"world_after": 3.20,
			"expect_damage": true,
			"expect_projectiles": true,
		}),
		_case("nuke_bubble", {
			"slots": [_slot("nuke", {}, [_mod("bubble")])],
			"hold": 0.35,
			"world_after": 3.20,
			"expect_damage": true,
			"expect_bubbles": true,
			"expect_projectiles": true,
		}),
	]


func _pair_cases(cap: int) -> Array:
	var out: Array = []
	var mods := _modifier_ids()
	for ability_id: String in CrawlerRules.ENABLED_ABILITIES:
		if not CrawlerCatalog.is_ability(ability_id):
			continue
		out.append(_case("%s__bare" % ability_id, {
			"slots": [_slot(ability_id)],
			"hold": _hold_for(ability_id),
			"world_after": _world_after_for(ability_id),
			"expect_damage": _expects_direct_damage(ability_id),
			"expect_projectiles": _expects_projectile(ability_id),
			"expect_fields": CrawlerRules.is_field_ability(ability_id),
			"expect_toxic": ability_id == "toxic_field" or ability_id == "toxic_blast",
		}))
		if cap > 0 and out.size() >= cap:
			return out
		for mod_id: String in mods:
			if not CrawlerCatalog.compatible(mod_id, ability_id):
				continue
			var flags := {
				"slots": [_slot(ability_id, {}, [_mod(mod_id)])],
				"hold": _hold_for(ability_id),
				"world_after": _world_after_for(ability_id),
				"expect_damage": _expects_direct_damage(ability_id),
				"expect_projectiles": _expects_projectile(ability_id),
				"expect_fields": CrawlerRules.is_field_ability(ability_id),
			}
			if mod_id == "bubble" and _emits_mods(ability_id):
				flags["expect_bubbles"] = true
			if mod_id == "linger" and _emits_mods(ability_id):
				flags["expect_lingers"] = true
			if mod_id == "toxic":
				flags["expect_toxic"] = ability_id != "wall" \
					and _emits_mods(ability_id)
			elif ability_id == "toxic_field" or ability_id == "toxic_blast":
				flags["expect_toxic"] = true
			out.append(_case("%s__%s" % [ability_id, mod_id], flags))
			if cap > 0 and out.size() >= cap:
				return out
	return out


func _case(id: String, extra: Dictionary) -> Dictionary:
	var spec := {
		"id": id,
		"slots": [],
		"sequence": [],
		"hat": "",
		"cape": "",
		"hold": DEFAULT_HOLD,
		"world_after": WORLD_AFTER,
		"expect_damage": false,
		"expect_bubbles": false,
		"expect_lingers": false,
		"expect_toxic": false,
		"expect_bubble_toxic": false,
		"expect_projectiles": false,
		"expect_fields": false,
		"compare": "",
		"compare_metric": "",
	}
	spec.merge(extra, true)
	return spec


func _slot(ability_id: String, upgrades: Dictionary = {},
		mods: Array = []) -> Dictionary:
	return {
		"ability": ability_id,
		"upgrades": upgrades,
		"mods": mods,
	}


func _mod(id: String, upgrades: Dictionary = {}) -> Dictionary:
	return {"id": id, "upgrades": upgrades}


func _run_case(spec: Dictionary, index: int) -> Dictionary:
	_clock = 0.0
	_events.clear()
	_peak_bubbles = 0
	_peak_lingers = 0
	_peak_fields = 0
	_peak_projectiles = 0
	_cleanup_world()
	_reset_combatant()
	_reset_look(str(spec.get("hat", "")), str(spec.get("cape", "")))
	var setup := _setup_loadout(spec)
	_spawn_probes()
	var fire_log: Array = []
	var sequence: Array = spec.get("sequence", []) as Array
	if sequence.is_empty():
		sequence = [{"slot": 0, "hold": float(spec.get("hold", DEFAULT_HOLD))}]
	for raw: Variant in sequence:
		if not (raw is Dictionary):
			continue
		var step := raw as Dictionary
		fire_log.append(_fire_slot(
			int(step.get("slot", 0)),
			float(step.get("hold", spec.get("hold", DEFAULT_HOLD)))))
	_step_world(float(spec.get("world_after", WORLD_AFTER)))
	var row := _collect_row(spec, index, setup, fire_log)
	_cleanup_world()
	return row


func _setup_loadout(spec: Dictionary) -> Dictionary:
	CrawlerKit.clear_session()
	var kit := _player.crawler_kit
	kit.seed_starter()
	var seated: Array = []
	var slot_index := 0
	for raw: Variant in spec.get("slots", []) as Array:
		if not (raw is Dictionary):
			continue
		var slot := raw as Dictionary
		var ability_id := str(slot.get("ability", ""))
		var card := CrawlerCatalog.make_ability(ability_id)
		var placed := false
		if card != null:
			placed = kit.place_card(card, CrawlerKit.SOURCE_EQUIP, slot_index)
			_apply_upgrades(kit, card.uid, slot.get("upgrades", {}) as Dictionary)
		var mods_seated: Array = []
		if card != null and placed:
			var mod_index := 0
			for mod_raw: Variant in slot.get("mods", []) as Array:
				if not (mod_raw is Dictionary):
					continue
				var wanted := mod_raw as Dictionary
				var mod_id := str(wanted.get("id", ""))
				var compatible := CrawlerCatalog.compatible(mod_id, ability_id)
				var mod := CrawlerCatalog.make_modifier(mod_id)
				var seated_ok := false
				if mod != null:
					kit.register(mod)
					var rack := kit.mod_rack(slot_index)
					if rack != null:
						var bag := kit.inventory.first_accepting(mod.token())
						if bag >= 0:
							kit.inventory.set_item(bag, mod.token())
							seated_ok = ItemContainer.transfer(
								kit.inventory, bag, rack, mod_index)
						if not seated_ok:
							rack.set_item(mod_index, mod.token())
							seated_ok = rack.get_item(mod_index) == mod.token()
					_apply_upgrades(kit, mod.uid, wanted.get("upgrades", {}) as Dictionary)
					seated_ok = _card_holds_mod(kit.equipped_card(slot_index), mod.uid)
				mods_seated.append({
					"id": mod_id,
					"compatible": compatible,
					"seated": seated_ok,
					"upgrades": (wanted.get("upgrades", {}) as Dictionary).duplicate(true),
					"ranks": _mod_ranks(mod),
				})
				mod_index += 1
		var live := kit.equipped_card(slot_index)
		seated.append({
			"slot": slot_index,
			"wanted": ability_id,
			"placed": placed and live != null and live.id == ability_id,
			"id": live.id if live != null else "",
			"uid": live.uid if live != null else "",
			"mods": live.filled_modifier_ids() if live != null else PackedStringArray(),
			"mod_setup": mods_seated,
			"stats": kit.stats_for(live) if live != null else {},
		})
		slot_index += 1
	var controller := _player.ability_controller()
	if controller != null:
		controller.refresh_crawler_stats()
	return {"slots": seated}


func _apply_upgrades(kit: CrawlerKit, uid: String, upgrades: Dictionary) -> void:
	if kit == null or uid.is_empty():
		return
	for key: Variant in upgrades.keys():
		var stat_id := str(key)
		var count := maxi(int(upgrades.get(key, 0)), 0)
		for _step in count:
			if not kit.upgrade_card(uid, stat_id):
				break


func _card_holds_mod(card: CrawlerCard, uid: String) -> bool:
	if card == null or uid.is_empty():
		return false
	for index in card.slot_count:
		var child := card.mod_at(index)
		if child != null and child.uid == uid:
			return true
	return false


func _mod_ranks(mod: CrawlerCard) -> Dictionary:
	var out := {}
	if mod == null:
		return out
	for stat_id: String in CrawlerRules.upgrade_stats_for(mod.id):
		out[stat_id] = mod.upgrade_rank(stat_id)
	return out


func _reset_look(hat: String, cape: String) -> void:
	var progress := _player.crawler_progress
	if progress == null:
		return
	progress.note_worn("")
	progress.note_worn_cape("")
	if not hat.is_empty():
		if progress.owns_hat(hat):
			progress.note_worn(hat)
		else:
			progress.grant_hat(hat, true)
	if not cape.is_empty():
		if progress.owns_cape(cape):
			progress.note_worn_cape(cape)
		else:
			progress.grant_cape(cape, true)
	_player.refresh_crawler_look()


func _spawn_probes() -> void:
	for probe: Probe in _probes:
		if is_instance_valid(probe):
			probe.queue_free()
	_probes.clear()
	var sockets: Array[Vector3] = [
		_player.combat_position(),
		_player.merged_hand_point(),
		_player.mouth_point(),
	]
	var close_distances := [1.4, 2.6]
	var wall_depths := [8.0, 14.0]
	var wall_sides := [-6.0, -3.0, 0.0, 3.0, 6.0]
	var index := 0
	var up := Vector3.UP
	for socket: Vector3 in sockets:
		var from := socket if socket.is_finite() else _player.combat_position()
		var along := _player.aim_direction(from)
		if along.length_squared() < 0.0001:
			along = -_player.global_basis.z
		along = along.normalized()
		var right := along.cross(up)
		if right.length_squared() < 0.0001:
			right = Vector3.RIGHT
		else:
			right = right.normalized()
		for distance: float in close_distances:
			index = _add_probe(index, from + along * distance, false)
		for depth: float in wall_depths:
			for side: float in wall_sides:
				index = _add_probe(index, from + along * depth + right * side, true)
	_sync_bodies()


func _add_probe(index: int, at: Vector3, block_shots: bool) -> int:
	var probe := Probe.new()
	probe.probe_id = index
	probe.block_shots = block_shots
	probe.name = "Probe_%d" % index
	probe.clock_ref = Callable(self, "_clock_now")
	_world.add_child(probe)
	probe.global_position = at
	probe.force_update_transform()
	_probes.append(probe)
	return index + 1


func _clock_now() -> float:
	return _clock


func _fire_slot(slot: int, hold: float) -> Dictionary:
	var ability := _ability_for(slot)
	var started := _clock
	var pressed := false
	if ability != null:
		var card := _player.crawler_kit.equipped_card(slot)
		if card != null:
			ability.apply_crawler(card)
		pressed = ability.press()
	_note("press", {
		"slot": slot,
		"ability": ability.ability_id if ability != null else "",
		"ok": pressed,
		"can_use": ability.can_use() if ability != null else false,
		"can_attack": _player.can_attack(),
		"stance": _player.stance(),
		"t": started,
	})
	var ticks := 0
	var limit := maxf(hold, STEP)
	while _clock - started < limit:
		_advance(STEP)
		if ability != null:
			ability.tick(STEP)
		ticks += 1
	if ability != null and ability.is_held():
		ability.release()
		_note("release", {"slot": slot, "t": _clock})
		_advance(STEP)
		ability.tick(STEP)
	return {
		"slot": slot,
		"ability": ability.ability_id if ability != null else "",
		"pressed": pressed,
		"ticks": ticks,
		"started": started,
		"ended": _clock,
		"held": limit,
	}


func _ability_for(slot: int) -> Ability:
	var controller := _player.ability_controller()
	if controller != null:
		var live := controller.ability_in(slot)
		if live != null:
			return live
	var card := _player.crawler_kit.equipped_card(slot)
	if card == null:
		return null
	var path := ItemDB.ability_script(card.id)
	if path.is_empty():
		return null
	var script := load(path) as Script
	if script == null:
		return null
	var ability := script.new() as Ability
	if ability == null:
		return null
	ability.configure(_player, slot, card.id, ItemDB.ability_definition(card.id))
	ability.apply_crawler(card)
	return ability


func _advance(delta: float) -> void:
	_clock += delta
	_step_world_once(delta)


func _step_world(seconds: float) -> void:
	var left := maxf(seconds, 0.0)
	while left > 0.0:
		var step := minf(left, STEP)
		_advance(step)
		left -= step


func _step_world_once(delta: float) -> void:
	_claim_world()
	_attract_probes_to_effects()
	_sync_bodies()
	for node: Node in get_tree().get_nodes_in_group(CrawlerBubble.GROUP):
		if node is CrawlerBubble:
			(node as CrawlerBubble)._physics_process(delta)
	for node: Node in get_tree().get_nodes_in_group(CrawlerLingerCloud.GROUP):
		if node.has_method(&"_physics_process"):
			node.call(&"_physics_process", delta)
	for node: Node in get_tree().get_nodes_in_group(CrawlerFieldVolume.GROUP):
		if node.has_method(&"_process"):
			node.call(&"_process", delta)
		if node.has_method(&"_physics_process"):
			node.call(&"_physics_process", delta)
	for child: Node in _world.get_children():
		if child is AbilityProjectile:
			(child as AbilityProjectile)._physics_process(delta)
	for probe: Probe in _probes:
		if is_instance_valid(probe):
			probe.statuses.tick(delta)
	_note_peaks()
	_flush_queued()


func _claim_world() -> void:
	for node: Node in get_tree().get_nodes_in_group(CrawlerBubble.GROUP):
		node.set_physics_process(false)
		node.set_process(false)
	for node: Node in get_tree().get_nodes_in_group(CrawlerLingerCloud.GROUP):
		node.set_physics_process(false)
		node.set_process(false)
	for node: Node in get_tree().get_nodes_in_group(CrawlerFieldVolume.GROUP):
		node.set_physics_process(false)
		node.set_process(false)
	for child: Node in _world.get_children():
		if child is AbilityProjectile:
			child.set_physics_process(false)
			child.set_process(false)


func _collect_row(spec: Dictionary, index: int, setup: Dictionary,
		fire_log: Array) -> Dictionary:
	var hits: Array = []
	var damage := 0.0
	for probe: Probe in _probes:
		if not is_instance_valid(probe):
			continue
		damage += probe.taken
		hits.append_array(probe.hits)
	var host_id := _primary_ability(spec)
	var recipes := CrawlerBubbles.recipes_for_player(_player, host_id)
	var linger_recipes := CrawlerLingers.recipes_for_player(_player, host_id)
	var payload := CrawlerElements.payload(
		_player, host_id, _host_stats(setup, 0))
	_note_peaks()
	var bubble_nodes := get_tree().get_nodes_in_group(CrawlerBubble.GROUP)
	var linger_nodes := get_tree().get_nodes_in_group(CrawlerLingerCloud.GROUP)
	var field_nodes := get_tree().get_nodes_in_group(CrawlerFieldVolume.GROUP)
	var shots := 0
	for child: Node in _world.get_children():
		if child is AbilityProjectile:
			shots += 1
	var bubbles := maxi(_peak_bubbles, bubble_nodes.size())
	var linger_count := maxi(_peak_lingers, linger_nodes.size())
	var fields := maxi(_peak_fields, field_nodes.size())
	shots = maxi(_peak_projectiles, shots)
	var toxic := _toxic_from(payload)
	var bubble_toxic := _toxic_from_recipes(recipes)
	var pressed := false
	for raw: Variant in fire_log:
		if raw is Dictionary and bool((raw as Dictionary).get("pressed", false)):
			pressed = true
	return {
		"id": str(spec.get("id", "case_%d" % index)),
		"index": index,
		"hat": str(spec.get("hat", "")),
		"cape": str(spec.get("cape", "")),
		"ability": host_id,
		"setup": setup,
		"fire": fire_log,
		"pressed": pressed,
		"duration": _clock,
		"damage": damage,
		"hit_count": hits.size(),
		"hits": hits,
		"bubbles": bubbles,
		"lingers": linger_count,
		"fields": fields,
		"projectiles": shots,
		"bubble_recipes": recipes.size(),
		"linger_recipes": linger_recipes.size(),
		"bubble_recipe_damage": _recipe_damage(recipes),
		"bubble_toxic_strength": float(bubble_toxic.get("strength", 0.0)),
		"toxic_strength": float(toxic.get("strength", 0.0)),
		"toxic_duration": float(toxic.get("duration", 0.0)),
		"payload": payload,
		"recipes": recipes,
		"linger_recipes_data": linger_recipes,
		"events": _events.duplicate(true),
		"expect_damage": bool(spec.get("expect_damage", false)),
		"expect_bubbles": bool(spec.get("expect_bubbles", false)),
		"expect_lingers": bool(spec.get("expect_lingers", false)),
		"expect_toxic": bool(spec.get("expect_toxic", false)),
		"expect_bubble_toxic": bool(spec.get("expect_bubble_toxic", false)),
		"expect_projectiles": bool(spec.get("expect_projectiles", false)),
		"expect_fields": bool(spec.get("expect_fields", false)),
		"compare": str(spec.get("compare", "")),
		"compare_metric": str(spec.get("compare_metric", "")),
		"poison_hits": _count_status_hits(hits, CombatStatuses.POISON),
		"bubble_hits": _count_ability_hits(hits, "bubble"),
	}


func _primary_ability(spec: Dictionary) -> String:
	var slots: Array = spec.get("slots", []) as Array
	if slots.is_empty() or not (slots[0] is Dictionary):
		return ""
	return str((slots[0] as Dictionary).get("ability", ""))


func _host_stats(setup: Dictionary, slot: int) -> Dictionary:
	var slots: Array = setup.get("slots", []) as Array
	if slot < 0 or slot >= slots.size() or not (slots[slot] is Dictionary):
		return {}
	var raw: Variant = (slots[slot] as Dictionary).get("stats", {})
	return raw as Dictionary if raw is Dictionary else {}


func _toxic_from(payload: Array) -> Dictionary:
	for raw: Variant in payload:
		if not (raw is Dictionary):
			continue
		var row := raw as Dictionary
		if str(row.get("id", "")) == String(CombatStatuses.POISON):
			return row
	return {}


func _toxic_from_recipes(recipes: Array) -> Dictionary:
	for raw: Variant in recipes:
		if not (raw is Dictionary):
			continue
		var recipe := raw as Dictionary
		if str(recipe.get("status_id", "")) == String(CombatStatuses.POISON):
			return {
				"id": String(CombatStatuses.POISON),
				"strength": float(recipe.get("status_strength", 0.0)),
				"duration": float(recipe.get("status_duration", 0.0)),
			}
		var carried: Variant = recipe.get("statuses", [])
		if carried is Array:
			var found := _toxic_from(carried as Array)
			if not found.is_empty():
				return found
	return {}


func _recipe_damage(recipes: Array) -> float:
	var total := 0.0
	for raw: Variant in recipes:
		if raw is Dictionary:
			total += float((raw as Dictionary).get("damage", 0.0))
	return total


func _attract_probes_to_effects() -> void:
	if _probes.is_empty():
		return
	var parked := 0
	var fields := get_tree().get_nodes_in_group(CrawlerFieldVolume.GROUP)
	for raw: Variant in fields:
		if parked >= _probes.size():
			break
		if raw is Node3D:
			_place_probe(parked, (raw as Node3D).global_position)
			parked += 1
	var bubbles := get_tree().get_nodes_in_group(CrawlerBubble.GROUP)
	if not bubbles.is_empty() and parked < _probes.size():
		var bubble := bubbles[0] as Node3D
		if bubble != null:
			var along := Vector3.FORWARD
			if bubble is CrawlerBubble:
				var travel := (bubble as CrawlerBubble).velocity
				if travel.length_squared() > 0.0001:
					along = travel.normalized()
			_place_probe(parked, bubble.global_position + along * 0.12)
			parked += 1
	var linger_nodes := get_tree().get_nodes_in_group(CrawlerLingerCloud.GROUP)
	if parked == 0 and not linger_nodes.is_empty() and linger_nodes[0] is Node3D:
		_place_probe(0, (linger_nodes[0] as Node3D).global_position)


func _flush_queued() -> void:
	var doomed: Array = []
	for node: Node in get_tree().get_nodes_in_group(CrawlerBubble.GROUP):
		if node.is_queued_for_deletion():
			doomed.append(node)
	for node: Node in get_tree().get_nodes_in_group(CrawlerLingerCloud.GROUP):
		if node.is_queued_for_deletion():
			doomed.append(node)
	for node: Node in get_tree().get_nodes_in_group(CrawlerFieldVolume.GROUP):
		if node.is_queued_for_deletion():
			doomed.append(node)
	for child: Node in _world.get_children():
		if child == _player or child is Probe:
			continue
		if child is AbilityProjectile and child.is_queued_for_deletion():
			doomed.append(child)
	_free_nodes(doomed)


func _place_probe(index: int, at: Vector3) -> void:
	if index < 0 or index >= _probes.size() or not at.is_finite():
		return
	var probe := _probes[index]
	if not is_instance_valid(probe):
		return
	probe.global_position = at
	probe.force_update_transform()


func _sync_bodies() -> void:
	for probe: Probe in _probes:
		if is_instance_valid(probe):
			probe.force_update_transform()


func _note_peaks() -> void:
	_peak_bubbles = maxi(_peak_bubbles,
		get_tree().get_nodes_in_group(CrawlerBubble.GROUP).size())
	_peak_lingers = maxi(_peak_lingers,
		get_tree().get_nodes_in_group(CrawlerLingerCloud.GROUP).size())
	_peak_fields = maxi(_peak_fields,
		get_tree().get_nodes_in_group(CrawlerFieldVolume.GROUP).size())
	var shots := 0
	for child: Node in _world.get_children():
		if child is AbilityProjectile:
			shots += 1
	_peak_projectiles = maxi(_peak_projectiles, shots)


func _count_ability_hits(hits: Array, ability_id: String) -> int:
	var count := 0
	for raw: Variant in hits:
		if raw is Dictionary \
				and str((raw as Dictionary).get("ability", "")) == ability_id:
			count += 1
	return count


func _count_status_hits(hits: Array, status_id: StringName) -> int:
	var count := 0
	for raw: Variant in hits:
		if not (raw is Dictionary):
			continue
		var hit := raw as Dictionary
		if str(hit.get("status", "")) == String(status_id):
			count += 1
			continue
		var rows: Variant = hit.get("statuses", [])
		if not (rows is Array):
			continue
		for entry: Variant in rows:
			if entry is Dictionary \
					and str((entry as Dictionary).get("id", "")) == String(status_id):
				count += 1
				break
	return count


func _detect_anomalies() -> void:
	var anomalies: Array = []
	var by_id: Dictionary = _report.get("by_id", {}) as Dictionary
	for raw: Variant in _report.get("cases", []) as Array:
		if not (raw is Dictionary):
			continue
		var row := raw as Dictionary
		var case_id := str(row.get("id", ""))
		if not bool(row.get("pressed", false)) \
				and not _needs_terrain(str(row.get("ability", ""))):
			anomalies.append(_anomaly(case_id, "press_failed",
				"ability press returned false"))
		if bool(row.get("expect_damage", false)) \
				and float(row.get("damage", 0.0)) <= 0.001 \
				and int(row.get("hit_count", 0)) <= 0 \
				and int(row.get("projectiles", 0)) <= 0:
			anomalies.append(_anomaly(case_id, "expected_damage_missing",
				"expected combat contact but probes took no hits"))
		if bool(row.get("expect_bubbles", false)) \
				and int(row.get("bubbles", 0)) <= 0:
			var recipes := int(row.get("bubble_recipes", 0))
			var detail := "bubble recipes=%d spawned=0" % recipes
			if recipes <= 0:
				detail = "no bubble recipes and no spawned orbs"
			anomalies.append(_anomaly(case_id, "expected_bubbles_missing", detail))
		if bool(row.get("expect_bubbles", false)) \
				and int(row.get("bubbles", 0)) > 0 \
				and int(row.get("bubble_hits", 0)) <= 0:
			anomalies.append(_anomaly(case_id, "bubbles_did_not_hit",
				"spawned %d orbs but none damaged a probe" % int(row.get("bubbles", 0))))
		if bool(row.get("expect_lingers", false)) \
				and int(row.get("lingers", 0)) <= 0:
			anomalies.append(_anomaly(case_id, "expected_lingers_missing",
				"linger recipes=%d spawned=0" % int(row.get("linger_recipes", 0))))
		if bool(row.get("expect_projectiles", false)) \
				and int(row.get("projectiles", 0)) <= 0 \
				and bool(row.get("pressed", false)):
			anomalies.append(_anomaly(case_id, "expected_projectile_missing",
				"projectile ability pressed but no shot spawned"))
		if bool(row.get("expect_fields", false)) \
				and int(row.get("fields", 0)) <= 0 \
				and bool(row.get("pressed", false)):
			anomalies.append(_anomaly(case_id, "expected_field_missing",
				"field ability pressed but no volume planted"))
		if bool(row.get("expect_toxic", false)) \
				and float(row.get("toxic_strength", 0.0)) <= 0.001 \
				and int(row.get("poison_hits", 0)) <= 0:
			anomalies.append(_anomaly(case_id, "expected_toxic_missing",
				"no poison payload and no poison hits"))
		if bool(row.get("expect_bubble_toxic", false)) \
				and float(row.get("bubble_toxic_strength", 0.0)) <= 0.001:
			anomalies.append(_anomaly(case_id, "expected_bubble_toxic_missing",
				"bubble recipes did not carry poison"))
		var setup: Variant = row.get("setup", {})
		if setup is Dictionary:
			_scan_mod_seats(case_id, setup as Dictionary, anomalies)
		var compare_id := str(row.get("compare", ""))
		if not compare_id.is_empty() and by_id.has(compare_id):
			var baseline := by_id[compare_id] as Dictionary
			var metric := str(row.get("compare_metric", "damage"))
			var before := float(baseline.get(metric, 0.0))
			var after := float(row.get(metric, 0.0))
			if after <= before + 0.001:
				anomalies.append(_anomaly(case_id, "upgrade_no_gain",
					"%s was %.3f, baseline %s was %.3f" % [
						metric, after, compare_id, before,
					]))
	_report["anomalies"] = anomalies


func _scan_mod_seats(case_id: String, setup: Dictionary, anomalies: Array) -> void:
	for raw: Variant in setup.get("slots", []) as Array:
		if not (raw is Dictionary):
			continue
		var slot := raw as Dictionary
		if not bool(slot.get("placed", false)):
			anomalies.append(_anomaly(case_id, "ability_not_placed",
				"wanted %s" % str(slot.get("wanted", ""))))
		for mod_raw: Variant in slot.get("mod_setup", []) as Array:
			if not (mod_raw is Dictionary):
				continue
			var mod := mod_raw as Dictionary
			if not bool(mod.get("seated", false)):
				anomalies.append(_anomaly(case_id, "mod_not_seated",
					"%s on %s (compatible=%s)" % [
						str(mod.get("id", "")),
						str(slot.get("wanted", "")),
						str(mod.get("compatible", false)),
					]))
			elif not bool(mod.get("compatible", true)):
				anomalies.append(_anomaly(case_id, "mod_incompatible_but_forced",
					"%s is not catalog-compatible with %s" % [
						str(mod.get("id", "")),
						str(slot.get("wanted", "")),
					]))


func _anomaly(case_id: String, kind: String, detail: String) -> Dictionary:
	return {"case": case_id, "kind": kind, "detail": detail}


func _cleanup_world() -> void:
	_free_nodes(get_tree().get_nodes_in_group(CrawlerBubble.GROUP))
	_free_nodes(get_tree().get_nodes_in_group(CrawlerLingerCloud.GROUP))
	_free_nodes(get_tree().get_nodes_in_group(CrawlerFieldVolume.GROUP))
	var extras: Array = []
	for child: Node in _world.get_children():
		if child is AbilityProjectile or child is Probe:
			extras.append(child)
	_free_nodes(extras)
	_probes.clear()
	if _player != null:
		_player.end_overdrive()


func _free_nodes(nodes: Array) -> void:
	var doomed: Array[Node] = []
	for raw: Variant in nodes:
		var node := raw as Node
		if node != null and is_instance_valid(node):
			doomed.append(node)
	for node: Node in doomed:
		if is_instance_valid(node):
			var parent := node.get_parent()
			if parent != null:
				parent.remove_child(node)
			node.free()


func _note(kind: String, payload: Dictionary) -> void:
	var row := payload.duplicate(true)
	row["kind"] = kind
	row["t"] = float(row.get("t", _clock))
	_events.append(row)


func _modifier_ids() -> PackedStringArray:
	var out := PackedStringArray()
	for id: String in CrawlerCatalog.ids():
		if CrawlerCatalog.is_modifier(id):
			out.append(id)
	return out


func _reset_combatant() -> void:
	if _player == null:
		return
	var controller := _player.ability_controller()
	if controller != null:
		controller.cancel_all()
	_player.cancel_combat_actions()
	_player.end_overdrive()
	_player.set_field_cast(false)
	_player._apply_stance(OnlinePlayer.Stance.STAND)
	_player._meteor_falling = false
	_player._meteor_stats = {}
	_player._forced_ragdoll = false
	_player.velocity = Vector3.ZERO
	_player.global_position = Vector3(0.0, 2.0, 0.0)
	_player.global_rotation = Vector3.ZERO


func _expects_direct_damage(ability_id: String) -> bool:
	match ability_id:
		"static_field":
			return true
		"overdrive", "teleport", "wall", "healing_field", "nausicaa", \
				"meteor_punch", "toxic_field", "freeze_field":
			return false
		_:
			return true


func _expects_projectile(ability_id: String) -> bool:
	return CrawlerRules.ability_type(ability_id) == CrawlerRules.TYPE_PROJECTILE \
		and not _needs_terrain(ability_id)


func _world_after_for(ability_id: String) -> float:
	if CrawlerRules.is_orb_blast(ability_id):
		return 3.20
	if CrawlerRules.is_field_ability(ability_id):
		return 1.60
	if CrawlerRules.ability_type(ability_id) == CrawlerRules.TYPE_PROJECTILE:
		return 1.60
	return WORLD_AFTER


func _needs_terrain(ability_id: String) -> bool:
	return ability_id == "nausicaa" or ability_id == "meteor_punch"


func _emits_mods(ability_id: String) -> bool:
	return not _needs_terrain(ability_id) and ability_id != "overdrive"


func _hold_for(ability_id: String) -> float:
	match CrawlerRules.ability_type(ability_id):
		CrawlerRules.TYPE_SHOCKWAVE:
			return CrawlerRules.ROAR_WINDUP + CrawlerRules.ROAR_EXPAND + 0.05
		CrawlerRules.TYPE_FIELD:
			return CrawlerRules.FIELD_CAST + 0.35
		CrawlerRules.TYPE_BEAM:
			return 0.55
		_:
			return DEFAULT_HOLD


func _write_logs() -> void:
	var abs_dir := ProjectSettings.globalize_path(LOG_DIR)
	DirAccess.make_dir_recursive_absolute(abs_dir)
	var stamp := Time.get_datetime_string_from_system(true, true).replace(":", "-")
	var latest_json := "%s/ability_combo_latest.json" % LOG_DIR
	var latest_txt := "%s/ability_combo_latest.txt" % LOG_DIR
	var stamped_json := "%s/ability_combo_%s.json" % [LOG_DIR, stamp]
	var body := JSON.stringify(_report, "\t")
	_store(latest_json, body)
	_store(stamped_json, body)
	_store(latest_txt, _text_report())
	print("ability_combo: wrote %s" % latest_json)


func _store(path: String, body: String) -> void:
	var file := FileAccess.open(path, FileAccess.WRITE)
	if file == null:
		push_error("ability_combo: could not write %s" % path)
		return
	file.store_string(body)


func _text_report() -> String:
	var bits: PackedStringArray = PackedStringArray()
	bits.append("Ability combo harness")
	bits.append("mode=%s cases=%d anomalies=%d" % [
		str(_report.get("mode", "")),
		int(_report.get("case_count", 0)),
		int(_report.get("anomaly_count", 0)),
	])
	bits.append("started %s  finished %s" % [
		str(_report.get("started", "")),
		str(_report.get("finished", "")),
	])
	bits.append("")
	bits.append("CASES")
	for raw: Variant in _report.get("cases", []) as Array:
		if not (raw is Dictionary):
			continue
		var row := raw as Dictionary
		bits.append("- %s  dmg=%.2f hits=%d poison_hits=%d bubble_hits=%d bubbles=%d/%d lingers=%d/%d fields=%d shots=%d toxic=%.3f bubble_toxic=%.3f pressed=%s dur=%.2f" % [
			str(row.get("id", "")),
			float(row.get("damage", 0.0)),
			int(row.get("hit_count", 0)),
			int(row.get("poison_hits", 0)),
			int(row.get("bubble_hits", 0)),
			int(row.get("bubbles", 0)),
			int(row.get("bubble_recipes", 0)),
			int(row.get("lingers", 0)),
			int(row.get("linger_recipes", 0)),
			int(row.get("fields", 0)),
			int(row.get("projectiles", 0)),
			float(row.get("toxic_strength", 0.0)),
			float(row.get("bubble_toxic_strength", 0.0)),
			str(row.get("pressed", false)),
			float(row.get("duration", 0.0)),
		])
	bits.append("")
	bits.append("ANOMALIES")
	var anomalies: Array = _report.get("anomalies", []) as Array
	if anomalies.is_empty():
		bits.append("(none)")
	for raw: Variant in anomalies:
		if raw is Dictionary:
			var row := raw as Dictionary
			bits.append("- [%s] %s: %s" % [
				str(row.get("kind", "")),
				str(row.get("case", "")),
				str(row.get("detail", "")),
			])
	return "\n".join(bits) + "\n"


func _print_summary() -> void:
	print("ability_combo: %d case(s), %d anomal%s" % [
		int(_report.get("case_count", 0)),
		int(_report.get("anomaly_count", 0)),
		"y" if int(_report.get("anomaly_count", 0)) == 1 else "ies",
	])
	for raw: Variant in _report.get("anomalies", []) as Array:
		if raw is Dictionary:
			var row := raw as Dictionary
			print("ability_combo ANOMALY [%s] %s: %s" % [
				str(row.get("kind", "")),
				str(row.get("case", "")),
				str(row.get("detail", "")),
			])
