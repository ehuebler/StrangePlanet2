class_name CrawlerLingers
extends RefCounted

## Per-card Linger recipes and the host-type emitters.


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
		if child == null or child.id != "linger":
			continue
		out.append(recipe_from(child, card, host_stats, player))
	return out


static func recipe_from(mod: CrawlerCard, host: CrawlerCard,
		host_stats: Dictionary, player: OnlinePlayer = null) -> Dictionary:
	var duration_rank := 0
	var toxic_rank := 0
	var freeze_rank := 0
	var slow_rank := 0
	if mod != null:
		duration_rank = mod.upgrade_rank("duration")
		toxic_rank = mod.upgrade_rank("toxic")
		freeze_rank = mod.upgrade_rank("freeze")
		slow_rank = mod.upgrade_rank("slow")
	var host_id := host.id if host != null else "linger"
	var host_scale := CrawlerBubbles.host_size_scale(host_id, host_stats)
	var recipe := {
		"ability_id": host_id,
		"duration": CrawlerRules.scaled_stat(
			CrawlerRules.LINGER_SECONDS, duration_rank),
		"radius": CrawlerRules.LINGER_RADIUS * maxf(host_scale, 0.55),
		"damage": CrawlerRules.LINGER_DAMAGE,
		"slow": minf(CrawlerRules.LINGER_SLOW_PER_RANK
			* CrawlerRules.upgrade_steps(slow_rank),
			CrawlerRules.LINGER_SLOW_MAX),
		"homing": CrawlerHoming.range_of(host_stats),
		"steer": CrawlerHoming.steer_of(host_stats),
		"statuses": [],
		"tint": tint_for(host_id, []),
	}
	if player != null and player.has_method(&"crawler_damage_scale"):
		recipe["damage"] = float(recipe["damage"]) \
			* float(player.call(&"crawler_damage_scale"))
	var carried: Array[Dictionary] = []
	if host != null:
		carried = CrawlerElements.payload(player, host.id, host_stats)
	if toxic_rank > 0:
		carried.append({
			"id": String(CombatStatuses.POISON),
			"duration": CrawlerRules.scaled_stat(
				CrawlerRules.ELEM_TOXIC_HOLD, toxic_rank),
			"strength": CrawlerRules.scaled_stat(
				CrawlerRules.ELEM_TOXIC_DPS, maxi(toxic_rank - 1, 0)),
			"stack": true,
		})
	if freeze_rank > 0:
		carried.append({
			"id": String(CombatStatuses.FREEZE),
			"duration": CrawlerRules.scaled_stat(
				CrawlerRules.ELEM_ICE_HOLD, freeze_rank),
			"strength": 0.0,
			"stack": false,
		})
	recipe["statuses"] = carried
	recipe["tint"] = tint_for(host_id, carried)
	return recipe


static func tint_for(ability_id: String, statuses: Array) -> Color:
	var base: Color = CrawlerFieldVolume.TINTS.get(ability_id,
		Color(0.62, 0.88, 1.0))
	if ability_id == "toxic_blast":
		base = Color(0.32, 0.92, 0.22)
	elif ability_id == "freeze_blast":
		base = Color(0.45, 0.82, 1.0)
	elif ability_id == "charming_aura":
		base = Color(0.95, 0.38, 0.72)
	elif ability_id == "lightning" or ability_id == "static_field":
		base = Color(0.95, 0.85, 0.25)
	elif ability_id == "icicle":
		base = Color(0.62, 0.88, 1.0)
	return CrawlerElements.tint_of(base, statuses)


static func emit_beam_trail(player: OnlinePlayer, ability_id: String,
		from: Vector3, at: Vector3) -> Array[CrawlerLingerCloud]:
	var span := at - from
	var length := span.length()
	if length < 0.2:
		return []
	var count := clampi(int(ceil(length / CrawlerRules.LINGER_BEAM_SPACING)),
		2, 36)
	var path := PackedVector3Array()
	for index in count:
		var share := float(index) / float(count - 1)
		path.append(from.lerp(at, share))
	return emit_path(player, ability_id, path, CrawlerRules.LINGER_BEAM_MUL)


static func emit_path(player: OnlinePlayer, ability_id: String,
		path: PackedVector3Array, duration_mul := 1.0) -> Array[CrawlerLingerCloud]:
	var recipes := recipes_for_player(player, ability_id)
	if recipes.is_empty() or player == null or path.size() < 2:
		return []
	var world := _world_of(player)
	var owns := _owns(player)
	var spawned: Array[CrawlerLingerCloud] = []
	for recipe: Dictionary in recipes:
		var row := recipe.duplicate(true)
		row["duration"] = float(row.get("duration", CrawlerRules.LINGER_SECONDS)) \
			* duration_mul
		for at: Vector3 in path:
			var cloud := CrawlerLingerCloud.spawn(world, player, row, at, owns)
			if cloud != null:
				spawned.append(cloud)
	return spawned


static func emit_shockwave(player: OnlinePlayer, ability_id: String,
		origin: Vector3, reach: float) -> Array[CrawlerLingerCloud]:
	return _scatter(player, ability_id, origin, reach,
		CrawlerRules.LINGER_SHOCK_COUNT, 7)


static func emit_blast(player: OnlinePlayer, ability_id: String,
		origin: Vector3, reach: float) -> Array[CrawlerLingerCloud]:
	return _scatter(player, ability_id, origin, reach,
		CrawlerRules.LINGER_BLAST_COUNT, 11)


static func emit_field(player: OnlinePlayer, ability_id: String,
		origin: Vector3, reach: float) -> Array[CrawlerLingerCloud]:
	return _scatter(player, ability_id, origin, reach,
		CrawlerRules.LINGER_FIELD_COUNT, 13)


static func emit_trail(player: OnlinePlayer, ability_id: String,
		at: Vector3, along: Vector3) -> Array[CrawlerLingerCloud]:
	var recipes := recipes_for_player(player, ability_id)
	if recipes.is_empty() or player == null:
		return []
	var world := _world_of(player)
	var owns := _owns(player)
	var back := -along.normalized() if along.length_squared() > 0.0001 \
		else Vector3.UP
	var spawned: Array[CrawlerLingerCloud] = []
	for recipe: Dictionary in recipes:
		var cloud := CrawlerLingerCloud.spawn(
			world, player, recipe, at + back * 0.25, owns)
		if cloud != null:
			spawned.append(cloud)
	return spawned


static func bubble_bonus(host: CrawlerCard) -> float:
	if host == null:
		return 0.0
	var extra := 0.0
	for index in host.slot_count:
		var child := host.mod_at(index)
		if child == null or child.id != "linger":
			continue
		extra += CrawlerRules.scaled_stat(
			CrawlerRules.LINGER_BUBBLE_BONUS, child.upgrade_rank("duration"))
	return extra


static func _scatter(player: OnlinePlayer, ability_id: String,
		origin: Vector3, reach: float, count: int,
		salt: int) -> Array[CrawlerLingerCloud]:
	var recipes := recipes_for_player(player, ability_id)
	if recipes.is_empty() or player == null:
		return []
	var world := _world_of(player)
	var owns := _owns(player)
	var up := origin.normalized() if origin.length_squared() > 0.01 else Vector3.UP
	var east := up.cross(Vector3.RIGHT if absf(up.y) > 0.9 else Vector3.UP)
	if east.length_squared() < 0.0001:
		east = Vector3.RIGHT
	east = east.normalized()
	var north := up.cross(east).normalized()
	var spawned: Array[CrawlerLingerCloud] = []
	var ring := maxf(reach, 0.8)
	for recipe: Dictionary in recipes:
		for index in count:
			var t := TAU * (float(index) + 0.21 + _hash01(index, recipe, salt)) \
				/ float(count)
			var radial := (east * cos(t) + north * sin(t)).normalized()
			var span := ring * (0.16 + 0.74 * _hash01(index, recipe, salt + 5))
			var lift := ring * (0.28 * _hash01(index, recipe, salt + 9) - 0.08)
			var at := origin + radial * span + up * lift
			var cloud := CrawlerLingerCloud.spawn(world, player, recipe, at, owns)
			if cloud != null:
				spawned.append(cloud)
	return spawned


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


static func _owns(player: OnlinePlayer) -> bool:
	return player != null and (
		not player.multiplayer.has_multiplayer_peer()
		or player.multiplayer.is_server())


static func _hash01(pulse: int, recipe: Dictionary, salt: int) -> float:
	var seed := pulse * 73856093 + salt * 19349663 \
		+ int(float(recipe.get("slow", 0.0)) * 100.0) * 83492791
	return fposmod(float(seed % 10000) / 10000.0, 1.0)
