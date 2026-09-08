class_name GameSave
extends RefCounted

## One disk slot for the live run. Profile data (settings, meta gems, journal)
## already lives in settings.cfg. This file is the expedition itself: kit,
## gold, position, shops, the ground, and the sky.

const PATH := "user://game_save.json"
const VERSION := 1

static var pending: Dictionary = {}


static func has_save() -> bool:
	return FileAccess.file_exists(PATH)


static func clear_file() -> void:
	pending = {}
	if not FileAccess.file_exists(PATH):
		return
	var dir := DirAccess.open("user://")
	if dir != null:
		dir.remove(PATH.get_file())


static func can_write(tree: SceneTree) -> bool:
	if NetworkManager == null or not NetworkManager.is_host:
		return false
	var world := world_of(tree)
	return world != null and world.has_method(&"session_is_open") \
		and bool(world.call(&"session_is_open"))


static func can_apply(tree: SceneTree) -> bool:
	if not has_save():
		return false
	var world := world_of(tree)
	if world != null and world.has_method(&"session_is_open") \
			and bool(world.call(&"session_is_open")):
		return NetworkManager != null and NetworkManager.is_host
	return true


static func world_of(tree: SceneTree) -> Node:
	if NetworkManager != null and NetworkManager.active_world is Node:
		return NetworkManager.active_world as Node
	if tree == null:
		return null
	return tree.current_scene as Node


static func queue_pending(payload: Dictionary) -> void:
	pending = payload.duplicate(true)


static func take_pending() -> Dictionary:
	var held := pending.duplicate(true)
	pending = {}
	return held


static func apply_run_payloads(payload: Dictionary) -> void:
	var progress: Variant = payload.get("progress", {})
	if progress is Dictionary:
		CrawlerProgress.session_payload = (progress as Dictionary).duplicate(true)
	var kit: Variant = payload.get("kit", {})
	if kit is Dictionary:
		CrawlerKit.session_payload = (kit as Dictionary).duplicate(true)


static func mode_of(payload: Dictionary) -> String:
	var session: Variant = payload.get("session", {})
	if session is Dictionary:
		return str((session as Dictionary).get("mode", "crawler"))
	return "crawler"


static func is_coop_save(payload: Dictionary) -> bool:
	if bool(payload.get("coop", false)):
		return true
	var held: Variant = payload.get("players", [])
	return held is Array and (held as Array).size() > 1


static func roster_of(payload: Dictionary) -> Array:
	var held: Variant = payload.get("players", [])
	if held is Array and not (held as Array).is_empty():
		return held
	var row := {}
	var player_state: Variant = payload.get("player", {})
	if player_state is Dictionary:
		row = (player_state as Dictionary).duplicate(true)
	if not row.has("peer_id"):
		row["peer_id"] = 1
	if not row.has("progress"):
		row["progress"] = payload.get("progress", {})
	if not row.has("kit"):
		row["kit"] = payload.get("kit", {})
	return [row]


static func match_roster(payload: Dictionary, peer_id: int, metadata: Dictionary) -> Dictionary:
	var roster := roster_of(payload)
	var steam := int(metadata.get("steam_id", 0))
	if steam > 0:
		for row_variant: Variant in roster:
			if row_variant is Dictionary \
					and int((row_variant as Dictionary).get("steam_id", 0)) == steam:
				return row_variant
	var player_name := str(metadata.get("name", "")).strip_edges()
	if not player_name.is_empty():
		for row_variant: Variant in roster:
			if row_variant is Dictionary \
					and str((row_variant as Dictionary).get("name", "")).strip_edges() \
					== player_name:
				return row_variant
	for row_variant: Variant in roster:
		if row_variant is Dictionary \
				and int((row_variant as Dictionary).get("peer_id", 0)) == peer_id:
			return row_variant
	return {}


static func write_from_world(world: Node) -> bool:
	if world == null or not world.has_method(&"session_is_open"):
		return false
	if not bool(world.call(&"session_is_open")):
		return false
	return write_payload(capture(world))


static func write_payload(payload: Dictionary) -> bool:
	var packed: Variant = pack(payload)
	if typeof(packed) != TYPE_DICTIONARY:
		return false
	var file := FileAccess.open(PATH, FileAccess.WRITE)
	if file == null:
		return false
	file.store_string(JSON.stringify(packed, "\t"))
	return true


static func read() -> Dictionary:
	if not has_save():
		return {}
	var file := FileAccess.open(PATH, FileAccess.READ)
	if file == null:
		return {}
	var parsed: Variant = JSON.parse_string(file.get_as_text())
	if typeof(parsed) != TYPE_DICTIONARY:
		return {}
	var unpacked: Variant = unpack(parsed)
	if typeof(unpacked) != TYPE_DICTIONARY:
		return {}
	var payload := unpacked as Dictionary
	if int(payload.get("version", 0)) < 1:
		return {}
	return payload


static func capture(world: Node) -> Dictionary:
	var player: OnlinePlayer = null
	if world != null and world.has_method(&"local_player"):
		player = world.call(&"local_player") as OnlinePlayer
	if player != null:
		if player.crawler_progress != null:
			player.crawler_progress.remember()
		if player.crawler_kit != null:
			player.crawler_kit.remember()
	var session := {}
	if NetworkManager != null:
		session = NetworkManager.session_options.duplicate(true)
	var player_state := {}
	if player != null:
		player_state = {
			"peer_id": player.peer_id,
			"transform": player.global_transform,
			"pitch": player.look_pitch(),
			"combat": player.combat_snapshot(),
			"worn": player.worn_items(),
			"held": player.held_item(),
			"body": player.body_id(),
		}
	var roster: Array = []
	if world != null and world.has_method(&"player_roster_snapshot"):
		var held: Variant = world.call(&"player_roster_snapshot")
		if held is Array:
			roster = held
	var world_state := {}
	if world != null:
		var cycle: Node = null
		var cycle_raw: Variant = world.get("celestial_cycle")
		if cycle_raw is Node:
			cycle = cycle_raw
		world_state = {
			"phase": cycle.call(&"phase") if cycle != null and cycle.has_method(&"phase") else 0.0,
			"day_index": cycle.call(&"day_index") if cycle != null and cycle.has_method(&"day_index") else 0,
			"pickups": world.call(&"pickup_snapshots") if world.has_method(&"pickup_snapshots") else [],
			"scars": world.call(&"scar_snapshot") if world.has_method(&"scar_snapshot") else [],
			"flora": world.call(&"flora_snapshot") if world.has_method(&"flora_snapshot") else {},
			"bigfoot": world.call(&"bigfoot_snapshot") if world.has_method(&"bigfoot_snapshot") else {},
			"constructs": world.call(&"ability_construct_snapshot") if world.has_method(&"ability_construct_snapshot") else [],
			"horde": world.call(&"horde_snapshot") if world.has_method(&"horde_snapshot") else {},
			"next_pickup_id": int(world.call(&"next_pickup_id")) if world.has_method(&"next_pickup_id") else 1,
			"next_construct_id": int(world.call(&"next_ability_construct_id")) if world.has_method(&"next_ability_construct_id") else 1,
			"city_gift_id": int(world.call(&"city_gift_id")) if world.has_method(&"city_gift_id") else 0,
			"city_gift_claimed": bool(world.call(&"city_gift_claimed")) if world.has_method(&"city_gift_claimed") else false,
			"duel": world.call(&"duel_snapshot") if world.has_method(&"duel_snapshot") else {},
			"training": world.call(&"training_snapshot") \
				if world.has_method(&"training_snapshot") else {},
		}
	return {
		"version": VERSION,
		"saved_at": int(Time.get_unix_time_from_system()),
		"coop": NetworkManager != null and not NetworkManager.is_single_player,
		"session": session,
		"progress": CrawlerProgress.session_payload.duplicate(true),
		"kit": CrawlerKit.session_payload.duplicate(true),
		"look": CharacterDB.load_look(),
		"player": player_state,
		"players": roster,
		"world": world_state,
	}


static func player_transform(payload: Dictionary) -> Transform3D:
	var player_state: Variant = payload.get("player", {})
	if player_state is Dictionary:
		return unpack_transform((player_state as Dictionary).get("transform", {}))
	return Transform3D.IDENTITY


static func pack(value: Variant) -> Variant:
	match typeof(value):
		TYPE_NIL, TYPE_BOOL, TYPE_INT, TYPE_FLOAT, TYPE_STRING:
			return value
		TYPE_VECTOR2:
			var v2: Vector2 = value
			return {"$": "v2", "x": v2.x, "y": v2.y}
		TYPE_VECTOR3:
			var v3: Vector3 = value
			return {"$": "v3", "x": v3.x, "y": v3.y, "z": v3.z}
		TYPE_COLOR:
			var colour: Color = value
			return {"$": "c", "r": colour.r, "g": colour.g, "b": colour.b, "a": colour.a}
		TYPE_TRANSFORM3D:
			var xf: Transform3D = value
			return {
				"$": "xf",
				"o": pack(xf.origin),
				"x": pack(xf.basis.x),
				"y": pack(xf.basis.y),
				"z": pack(xf.basis.z),
			}
		TYPE_DICTIONARY:
			var packed := {}
			for key: Variant in value:
				packed[str(key)] = pack(value[key])
			return packed
		TYPE_ARRAY:
			return _pack_list(value)
		TYPE_PACKED_STRING_ARRAY:
			return _pack_list(value)
		TYPE_PACKED_INT32_ARRAY:
			return _pack_list(value)
		TYPE_PACKED_FLOAT32_ARRAY:
			return _pack_list(value)
		_:
			return str(value)


static func _pack_list(value: Variant) -> Array:
	var items: Array = []
	for item: Variant in value:
		items.append(pack(item))
	return items


static func unpack(value: Variant) -> Variant:
	if value is Dictionary:
		var data := value as Dictionary
		match str(data.get("$", "")):
			"v2":
				return Vector2(float(data.get("x", 0.0)), float(data.get("y", 0.0)))
			"v3":
				return Vector3(
					float(data.get("x", 0.0)),
					float(data.get("y", 0.0)),
					float(data.get("z", 0.0)))
			"c":
				return Color(
					float(data.get("r", 0.0)),
					float(data.get("g", 0.0)),
					float(data.get("b", 0.0)),
					float(data.get("a", 1.0)))
			"xf":
				return unpack_transform(data)
			_:
				var out := {}
				for key: Variant in data:
					out[str(key)] = unpack(data[key])
				return out
	if value is Array:
		var items: Array = []
		for item: Variant in value:
			items.append(unpack(item))
		return items
	return value


static func unpack_transform(value: Variant) -> Transform3D:
	if value is Transform3D:
		return value
	if value is Dictionary:
		var data := value as Dictionary
		var origin: Variant = unpack(data.get("o", {}))
		var axis_x: Variant = unpack(data.get("x", {}))
		var axis_y: Variant = unpack(data.get("y", {}))
		var axis_z: Variant = unpack(data.get("z", {}))
		if origin is Vector3 and axis_x is Vector3 \
				and axis_y is Vector3 and axis_z is Vector3:
			return Transform3D(
				Basis(axis_x, axis_y, axis_z), origin)
	return Transform3D.IDENTITY
