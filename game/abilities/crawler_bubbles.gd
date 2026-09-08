class_name CrawlerBubbles
extends RefCounted

## Per-card Bubble recipes and the three host-type emitters.
##
## Two seated Bubble cards emit two independent streams. A card with homing
## only pulls its own orbs; Big on the host scales every orb; Wobble only
## changes the beam path the orbs leave.

static func recipes_for(ability: Ability) -> Array[Dictionary]:
	if ability == null or ability.player == null:
		return []
	return recipes_for_player(ability.player, ability.ability_id)


static func recipes_for_player(player: OnlinePlayer, ability_id: String) -> Array[Dictionary]:
	var card := _host_card(player, ability_id)
	if card == null or player == null or player.crawler_kit == null:
		return []
	var host_stats := player.crawler_kit.stats_for(card)
	var out: Array[Dictionary] = []
	for index in card.slot_count:
		var child := card.mod_at(index)
		if child == null or child.id != "bubble":
			continue
		out.append(recipe_from(child, card, host_stats, player))
	return out


static func recipe_from(mod: CrawlerCard, host: CrawlerCard,
		host_stats: Dictionary, player: OnlinePlayer = null) -> Dictionary:
	var damage_rank := 0
	var size_rank := 0
	var linger_rank := 0
	var homing_rank := 0
	var pop_rank := 0
	var speed_rank := 0
	var spreader_on := false
	if mod != null:
		damage_rank = mod.upgrade_rank("damage")
		size_rank = mod.upgrade_rank("size")
		linger_rank = mod.upgrade_rank("duration")
		homing_rank = mod.upgrade_rank("homing")
		pop_rank = mod.upgrade_rank("pop")
		speed_rank = mod.upgrade_rank("speed")
		spreader_on = mod.upgrade_rank("spreader") > 0
	var host_scale := host_size_scale(host.id if host != null else "", host_stats)
	var recipe := {
		"ability_id": host.id if host != null else "bubble",
		"damage": CrawlerRules.scaled_stat(CrawlerRules.BUBBLE_DAMAGE, damage_rank),
		"size": CrawlerRules.scaled_stat(CrawlerRules.BUBBLE_SIZE, size_rank) * host_scale,
		"linger": CrawlerRules.scaled_stat(CrawlerRules.BUBBLE_LINGER, linger_rank)
			+ CrawlerLingers.bubble_bonus(host),
		"homing": CrawlerRules.BUBBLE_HOMING_PER_RANK
			* CrawlerRules.upgrade_steps(homing_rank)
			+ CrawlerHoming.range_of(host_stats),
		"steer": maxf(CrawlerBubble.STEER, CrawlerHoming.steer_of(host_stats)),
		"pop": CrawlerRules.BUBBLE_POP_PER_RANK * CrawlerRules.upgrade_steps(pop_rank),
		"speed": CrawlerRules.scaled_stat(CrawlerRules.BUBBLE_SPEED, speed_rank),
		"spreader": spreader_on,
		"bounce": CrawlerBounce.count(host_stats),
		"status_id": "",
		"status_duration": 0.0,
		"status_strength": 0.0,
		"statuses": [],
	}
	if player != null and player.has_method(&"crawler_damage_scale"):
		recipe["damage"] = float(recipe["damage"]) \
			* float(player.call(&"crawler_damage_scale"))
	if host != null:
		var carried := CrawlerElements.payload(
			player, host.id, host_stats)
		recipe["statuses"] = carried
		if not carried.is_empty():
			recipe["status_id"] = str(carried[0].get("id", ""))
			recipe["status_duration"] = float(carried[0].get("duration", 0.0))
			recipe["status_strength"] = float(carried[0].get("strength", 0.0))
		elif spreader_on:
			var native := host_status(host.id, host_stats, player)
			recipe["status_id"] = str(native.get("id", ""))
			recipe["status_duration"] = float(native.get("duration", 0.0))
			recipe["status_strength"] = float(native.get("strength", 0.0))
	return recipe


static func host_size_scale(ability_id: String, stats: Dictionary) -> float:
	var size := float(stats.get("size", 0.0))
	if size > 0.001:
		return size
	var radius := float(stats.get("radius", 0.0))
	if CrawlerRules.is_roar_ability(ability_id) and radius > 0.0:
		return radius / CrawlerRules.ROAR_RADIUS
	if ability_id == "laser_eyes" and radius > 0.0:
		return radius / 0.45
	if ability_id == "kame" and radius > 0.0:
		return radius / CrawlerRules.KAME_RADIUS
	if ability_id == "nausicaa" and radius > 0.0:
		return radius / CrawlerRules.NAUSICAA_RADIUS
	if ability_id == "lightning" and radius > 0.0:
		return radius / CrawlerRules.LIGHTNING_RADIUS
	if CrawlerRules.is_field_ability(ability_id) and radius > 0.0:
		return radius / CrawlerRules.FIELD_RADIUS
	if CrawlerRules.is_orb_blast(ability_id) and radius > 0.0:
		var authored := CrawlerRules.MINI_NUKE_RADIUS \
			if ability_id == "mini_nuke" else 110.0
		return radius / authored
	return 1.0


static func host_status(ability_id: String, stats: Dictionary,
		player: OnlinePlayer = null) -> Dictionary:
	var entries := CrawlerElements.payload(player, ability_id, stats)
	if entries.is_empty():
		return {"id": "", "duration": 0.0, "strength": 0.0}
	return entries[0]


static func emit_beam(player: OnlinePlayer, ability_id: String,
		left_eye: Vector3, right_eye: Vector3, at: Vector3,
		wobble := 0.0, pulse_index := 0,
		path_override := PackedVector3Array()) -> Array[CrawlerBubble]:
	var recipes := recipes_for_player(player, ability_id)
	if recipes.is_empty() or player == null:
		return []
	var beams := player.laser_beams() if player.has_method(&"laser_beams") else null
	var spawned: Array[CrawlerBubble] = []
	var world := _world_of(player)
	for recipe: Dictionary in recipes:
		var path := path_override if path_override.size() >= 2 \
			else _beam_path(beams, left_eye, right_eye, at, wobble, pulse_index)
		if path.size() < 2:
			continue
		var count := _beam_along_count(path)
		for index in count:
			var walk := _walk_path(path, _beam_share(index, count, pulse_index, recipe))
			var along: Vector3 = walk["along"]
			var sample: Vector3 = walk["at"]
			var away := _outward_from_beam(along, sample, index, count, recipe)
			var bubble := CrawlerBubble.launch(
				world, player, recipe, sample + away * 0.14, away)
			if bubble != null:
				spawned.append(bubble)
	return spawned


static func emit_shockwave(player: OnlinePlayer, ability_id: String,
		origin: Vector3, reach: float) -> Array[CrawlerBubble]:
	return _emit_isotropic(player, ability_id, origin, reach,
		CrawlerRules.BUBBLE_SHOCKWAVE_COUNT, 0.18, 3)


static func emit_blast(player: OnlinePlayer, ability_id: String,
		origin: Vector3, reach: float) -> Array[CrawlerBubble]:
	var recipes := recipes_for_player(player, ability_id)
	if recipes.is_empty() or player == null:
		return []
	var world := _world_of(player)
	var up := origin.normalized() if origin.length_squared() > 0.01 else Vector3.UP
	var east := up.cross(Vector3.RIGHT if absf(up.y) > 0.9 else Vector3.UP)
	if east.length_squared() < 0.0001:
		east = Vector3.RIGHT
	east = east.normalized()
	var north := up.cross(east).normalized()
	var spawned: Array[CrawlerBubble] = []
	var ring := maxf(reach, 1.0)
	for recipe: Dictionary in recipes:
		for index in CrawlerRules.BUBBLE_BLAST_COUNT:
			var t := TAU * (float(index) + 0.27) \
				/ float(CrawlerRules.BUBBLE_BLAST_COUNT)
			var radial := (east * cos(t) + north * sin(t)).normalized()
			var span := ring * (0.14 + 0.78 * _hash01(index, recipe, 5))
			var lift := ring * (0.42 * _hash01(index, recipe, 11) - 0.16)
			var at := origin + radial * span + up * lift
			var bubble := CrawlerBubble.launch(
				world, player, recipe, at, radial + up * 0.18)
			if bubble != null:
				spawned.append(bubble)
	return spawned


static func emit_field(player: OnlinePlayer, ability_id: String,
		origin: Vector3, reach: float) -> Array[CrawlerBubble]:
	return _emit_isotropic(player, ability_id, origin, reach,
		CrawlerRules.BUBBLE_FIELD_COUNT, 0.31, 7)


static func emit_trail(player: OnlinePlayer, ability_id: String,
		at: Vector3, along: Vector3) -> Array[CrawlerBubble]:
	var recipes := recipes_for_player(player, ability_id)
	if recipes.is_empty() or player == null:
		return []
	var world := _world_of(player)
	var back := -along.normalized() if along.length_squared() > 0.0001 \
		else Vector3.UP
	var spawned: Array[CrawlerBubble] = []
	for recipe: Dictionary in recipes:
		var side := back.cross(Vector3.UP if absf(back.y) < 0.9 else Vector3.RIGHT)
		if side.length_squared() < 0.0001:
			side = Vector3.RIGHT
		side = side.normalized() * (0.6 if spawned.size() % 2 == 0 else -0.6)
		var bubble := CrawlerBubble.launch(
			world, player, recipe, at + back * 0.35, back + side)
		if bubble != null:
			spawned.append(bubble)
	return spawned


static func _emit_isotropic(player: OnlinePlayer, ability_id: String,
		origin: Vector3, reach: float, count: int, spin: float,
		salt: int) -> Array[CrawlerBubble]:
	var recipes := recipes_for_player(player, ability_id)
	if recipes.is_empty() or player == null:
		return []
	var world := _world_of(player)
	var spawned: Array[CrawlerBubble] = []
	var ring := maxf(reach, 0.8)
	for recipe: Dictionary in recipes:
		for index in count:
			var radial := _isotropic_dir(origin, index, count,
				spin + _hash01(index, recipe, salt) * 0.4)
			var span := ring * (0.22 + 0.74 * _hash01(index, recipe, salt + 6))
			var at := origin + radial * span
			var bubble := CrawlerBubble.launch(world, player, recipe, at, radial)
			if bubble != null:
				spawned.append(bubble)
	return spawned


static func _isotropic_dir(origin: Vector3, index: int, count: int,
		spin: float) -> Vector3:
	var up := origin.normalized() if origin.length_squared() > 0.01 else Vector3.UP
	var east := up.cross(Vector3.RIGHT if absf(up.y) > 0.9 else Vector3.UP)
	if east.length_squared() < 0.0001:
		east = Vector3.RIGHT
	east = east.normalized()
	var north := up.cross(east).normalized()
	var n := maxi(count, 1)
	var y := 1.0 - ((float(index) + 0.5) / float(n)) * 2.0
	var r := sqrt(maxf(1.0 - y * y, 0.0))
	var theta := PI * (3.0 - sqrt(5.0)) * float(index) + spin
	var dir := east * (cos(theta) * r) + up * y + north * (sin(theta) * r)
	if dir.length_squared() < 0.0001:
		return up
	return dir.normalized()


static func _host_card(player: OnlinePlayer, ability_id: String) -> CrawlerCard:
	if player == null or player.crawler_kit == null or player.abilities == null:
		return null
	var wanted := CrawlerCatalog.ability_id(ability_id)
	if wanted.is_empty():
		wanted = ability_id
	for index in player.abilities.size():
		var card := player.crawler_kit.equipped_card(index)
		if card != null and card.id == wanted:
			return card
	return null


static func _world_of(player: OnlinePlayer) -> Node:
	if player == null:
		return null
	var world := player.get_parent()
	return world if world != null else player


static func _beam_along_count(path: PackedVector3Array) -> int:
	var length := _path_length(path)
	if length < 0.2:
		return CrawlerRules.BUBBLE_BEAM_ALONG_MIN
	return clampi(int(ceil(length / CrawlerRules.BUBBLE_BEAM_SPACING)),
		CrawlerRules.BUBBLE_BEAM_ALONG_MIN, CrawlerRules.BUBBLE_BEAM_ALONG_MAX)


static func _beam_share(index: int, count: int, pulse_index: int,
		recipe: Dictionary) -> float:
	var n := maxi(count, 1)
	var jitter := (_hash01(pulse_index, recipe, index + 11) - 0.5) * (0.7 / float(n))
	return clampf((float(index) + 0.5) / float(n) + jitter, 0.08, 0.92)


static func _path_length(path: PackedVector3Array) -> float:
	var length := 0.0
	for index in path.size() - 1:
		length += path[index].distance_to(path[index + 1])
	return length


static func _walk_path(path: PackedVector3Array, t: float) -> Dictionary:
	if path.is_empty():
		return {"at": Vector3.ZERO, "along": Vector3.FORWARD}
	if path.size() == 1:
		return {"at": path[0], "along": Vector3.FORWARD}
	var total := _path_length(path)
	var along := path[1] - path[0]
	if total <= 0.0001:
		if along.length_squared() < 0.0001:
			along = Vector3.FORWARD
		return {"at": path[0], "along": along.normalized()}
	var want := clampf(t, 0.0, 1.0) * total
	var walked := 0.0
	for index in path.size() - 1:
		var span := path[index + 1] - path[index]
		var length := span.length()
		if length <= 0.0001:
			continue
		if walked + length >= want or index == path.size() - 2:
			var share := clampf((want - walked) / length, 0.0, 1.0)
			return {
				"at": path[index].lerp(path[index + 1], share),
				"along": span / length,
			}
		walked += length
	along = path[path.size() - 1] - path[path.size() - 2]
	if along.length_squared() < 0.0001:
		along = Vector3.FORWARD
	return {"at": path[path.size() - 1], "along": along.normalized()}


static func _outward_from_beam(along: Vector3, sample: Vector3, index: int,
		count: int, recipe: Dictionary) -> Vector3:
	var dir := along.normalized() if along.length_squared() > 0.0001 \
		else Vector3.FORWARD
	var away := dir.cross(Vector3.UP if absf(dir.y) < 0.9 else Vector3.RIGHT)
	if away.length_squared() < 0.0001:
		away = dir.cross(sample.normalized() if sample.length_squared() > 0.01 \
			else Vector3.FORWARD)
	if away.length_squared() < 0.0001:
		away = Vector3.RIGHT
	away = away.normalized()
	var twist := TAU * ((float(index) + 0.5) / float(maxi(count, 1))) \
		+ _hash01(index, recipe, 23) * 0.7
	return away.rotated(dir, twist)


static func _beam_path(beams: LaserBeams, left_eye: Vector3, right_eye: Vector3,
		at: Vector3, wobble: float, pulse_index: int) -> PackedVector3Array:
	if beams != null and beams.has_method(&"path_points"):
		var live: PackedVector3Array = beams.call(
			&"path_points", pulse_index & 1, at)
		if live.size() >= 2:
			return live
	var from: Vector3 = left_eye if (pulse_index & 1) == 0 else right_eye
	if wobble <= 0.001:
		return PackedVector3Array([from, at])
	return PackedVector3Array([from, from.lerp(at, 0.5), at])


static func _hash01(pulse: int, recipe: Dictionary, salt: int) -> float:
	var seed := pulse * 73856093 + salt * 19349663 \
		+ int(float(recipe.get("homing", 0.0)) * 100.0) * 83492791
	return fposmod(float(seed % 10000) / 10000.0, 1.0)
