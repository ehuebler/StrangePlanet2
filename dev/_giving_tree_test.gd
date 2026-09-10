extends Node

## Headless checks for The Giving Tree.
##
##     godot --headless --path . dev/_giving_tree_test.tscn

const TREE_BOSS := preload("res://game/crawler/crawler_tree_boss.gd")
const LEAF := preload("res://game/crawler/crawler_tree_leaf_disk.gd")
const TITLE := preload("res://ui/combat/crawler_boss_title.gd")

var _failures := 0


func _ready() -> void:
	NetworkManager.session_options = {"mode": "crawler"}
	CrawlerCatalog.reload()
	CrawlerMeta.begin_test()
	Journal.begin_test()
	multiplayer.multiplayer_peer = OfflineMultiplayerPeer.new()
	NetworkManager.is_single_player = true
	NetworkManager.is_host = true
	NetworkManager.state = NetworkManager.SessionState.IN_GAME
	await _check_boss()
	await _check_phase2()
	_check_journal()
	_check_title()
	_check_leaf()
	await _check_keepout()
	Journal.end_test()
	CrawlerMeta.end_test()
	print("giving_tree_test: %s" % ("ok" if _failures == 0 else "FAILED"))
	get_tree().quit(0 if _failures == 0 else 1)


func _check_boss() -> void:
	var tree: Node = TREE_BOSS.new()
	tree.name = "TreeBoss"
	add_child(tree)
	await get_tree().process_frame
	_expect(str(tree.call(&"combat_display_name")) == "The Giving Tree",
		"the boss is named The Giving Tree")
	_expect(tree.is_in_group(BossAdapter.CRAWLER_GROUP),
		"the tree is a crawler boss")
	_expect(is_equal_approx(float(tree.call(&"maximum_health")), 500.0)
			and is_equal_approx(float(tree.call(&"health")), 500.0),
		"the trunk is 500 health")
	_expect(is_equal_approx(float(tree.call(&"battle_radius")), 200.0),
		"the fight is a 200 m ring")
	_expect(int(tree.call(&"bushel_count")) >= 22,
		"the authored foliage chunks are shootable bushels")
	_expect(not bool(tree.call(&"blocks_field_spawns")),
		"idle trees do not keep field packs off")
	var shot: Dictionary = tree.call(&"_intro_shot")
	var face: Vector3 = tree.call(&"_face_point")
	var from: Vector3 = shot.get("from", Vector3.ZERO)
	var at: Vector3 = shot.get("at", Vector3.ZERO)
	_expect(from.is_finite() and at.is_finite()
			and at.distance_to(face) < 2.0
			and from.distance_to(at) >= 50.0,
		"the intro camera stands off the face and looks at it")
	var toward := (at - from).normalized()
	var to_face := (face - from).normalized()
	_expect(toward.dot(to_face) > 0.92,
		"the intro camera points at the tree's face")
	_check_face_follow(tree)
	var poke := DamageHit.impact(tree.call(&"combat_position"), 2.0, 40.0)
	poke.faction = DamageHit.Faction.PLAYER
	_expect(is_equal_approx(float(tree.call(&"apply_damage", poke)), 0.0),
		"the trunk is locked until phase two")
	_expect(get_tree().get_nodes_in_group(&"giving_tree_bushels").size() >= 22,
		"bushels register as combatants")
	_check_bushel_hits(tree)
	_check_health_bar(tree)
	_check_scream_wave(tree)
	_check_arena(tree)
	tree.queue_free()
	await get_tree().process_frame


func _check_face_follow(tree: Node) -> void:
	var bait := Node3D.new()
	bait.name = "FaceBait"
	bait.add_to_group(&"network_players")
	add_child(bait)
	var up: Vector3 = tree.call(&"_up")
	var face: Vector3 = tree.call(&"_face_point")
	var along: Vector3 = tree.call(&"_facing")
	var right := up.cross(along)
	if right.length_squared() < 0.0001:
		right = up.cross(Vector3.RIGHT)
	right = right.normalized()
	bait.global_position = face + right * 40.0
	tree.call(&"_orient_face", 1.0)
	var after: Vector3 = tree.call(&"_facing")
	var look: Vector3 = tree.call(&"_face_point")
	var want := bait.global_position - look
	want -= up * want.dot(up)
	_expect(want.length_squared() > 0.04 and after.dot(want.normalized()) > 0.92,
		"the tree face turns to look at the player")
	bait.queue_free()


func _check_bushel_hits(tree: Node) -> void:
	var bushel: CrawlerTreeBushel = null
	for node_variant: Variant in get_tree().get_nodes_in_group(&"giving_tree_bushels"):
		var candidate := node_variant as CrawlerTreeBushel
		if candidate != null and candidate.is_alive():
			bushel = candidate
			break
	_expect(bushel != null, "a live leaf bushel is seated")
	if bushel == null:
		return
	var box := bushel.combat_aabb()
	var mesh := bushel._mesh
	_expect(mesh != null and mesh.mesh != null, "the bushel keeps its foliage mesh")
	if mesh == null or mesh.mesh == null:
		return
	var foliage := mesh.global_transform * mesh.mesh.get_aabb()
	_expect(box.size.length() > 0.4
			and box.get_center().distance_to(foliage.get_center()) < 1.2
			and box.intersects(foliage),
		"bushel hit bounds sit on the visible leaf chunk")
	_expect(not box.has_point(tree.global_position)
			or foliage.has_point(tree.global_position),
		"leaf hitboxes are not parked on the trunk origin")
	var through := DamageHit.beam(
		box.get_center() + Vector3(0.0, 0.0, 10.0),
		box.get_center() - Vector3(0.0, 0.0, 10.0),
		0.45,
		24.0)
	through.faction = DamageHit.Faction.PLAYER
	_expect(through.reaches_aabb(box),
		"a beam through the foliage reaches the bushel")
	var before := bushel.health()
	_expect(float(bushel.apply_damage(through)) > 0.0
			and bushel.health() < before,
		"phase-one leaf bunches take beam damage")
	_expect(mesh.find_child("DamageFlashOverlay", true, false) != null,
		"a hit leaf chunk flashes red")
	var hitbox := bushel.find_child("BushelHit", true, false) as StaticBody3D
	_expect(hitbox != null and hitbox.collision_layer == 4,
		"each leaf bunch has a beam-visible hitbox")
	var walk: Node = hitbox
	var owns_box := false
	while walk != null:
		if walk == bushel:
			owns_box = true
			break
		walk = walk.get_parent()
	_expect(owns_box, "a hit on the leaf box belongs to that bushel")
	tree.call(&"_enter_phase1")
	var bar_before := float(tree.call(&"health"))
	var poke := DamageHit.impact(bushel.combat_position(), 8.0, 40.0)
	poke.faction = DamageHit.Faction.PLAYER
	bushel.apply_damage(poke)
	_expect(float(tree.call(&"health")) < bar_before,
		"the boss bar tracks remaining leaf bunches in phase one")
	_expect(BossAdapter.is_boss_node(bushel),
		"a leaf bunch counts as the tree for the encounter bar")


func _check_health_bar(tree: Node) -> void:
	var decoy := Node3D.new()
	decoy.name = "IdleBigfoot"
	decoy.add_to_group(BossAdapter.GROUP)
	add_child(decoy)
	tree.call(&"_enter_phase1")
	_expect(BossAdapter.find_in_tree(tree) == tree,
		"the HUD picks the live giving tree over idle Bigfoot")
	_expect(bool(tree.call(&"is_engaged")),
		"phase one keeps the encounter bar armed")
	decoy.queue_free()


func _check_scream_wave(tree: Node) -> void:
	tree.call(&"_shockwave")
	var wave: Node = tree.get(&"_wave")
	_expect(wave != null, "the scream builds a shockwave shell")
	if wave == null:
		return
	tree.call(&"_tick_wave", 0.2)
	_expect(float(wave.get(&"radius")) > 1.0, "the shockwave expands outward")
	tree.call(&"_tick_wave", 2.0)
	_expect(is_equal_approx(float(wave.get(&"radius")), 0.0)
			and not bool(tree.get(&"_wave_live")),
		"the shockwave shell clears when the front is done")


func _check_journal() -> void:
	_expect(JournalDB.has_entry("first_boss"),
		"first boss is an achievement")
	_expect(JournalDB.category_of("first_boss") == "Combat",
		"the first-boss achievement is Combat")
	_expect(JournalDB.gems_of("first_boss") == 10
			and JournalDB.xp_of("first_boss") == 100
			and JournalDB.auto_gems_of("first_boss") == 0,
		"the first boss pays 100 XP now and 10 gems on claim")
	var journal := Journal.new()
	_expect(journal.complete("first_boss")
			and journal.is_done("first_boss")
			and journal.can_claim("first_boss"),
		"the first-boss reward waits to be claimed")


func _check_title() -> void:
	var host := Control.new()
	host.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	host.size = Vector2(1280, 720)
	add_child(host)
	var card := TITLE.present(host, "BOSS BATTLE", "The Giving Tree", true, true)
	_expect(card != null and String(card._headline) == "BOSS BATTLE",
		"the intro title mounts on the HUD")
	if card != null:
		card.size = Vector2(1280, 720)
		card._drive()
		_expect(card._title != null and card._title.visible
				and card._title.text == "BOSS BATTLE",
			"BOSS BATTLE falls in as the headline")
		_expect(card._sub != null and card._sub.visible
				and card._sub.text == "The Giving Tree",
			"The Giving Tree is the subtitle")
		var start_top := 0.0
		if card._column != null:
			start_top = card._column.offset_top
		card._age = 0.4
		card._drive()
		_expect(card._column != null and card._column.offset_top > start_top,
			"the boss title falls from the top of the screen")
	host.queue_free()


func _check_leaf() -> void:
	var bait := Node3D.new()
	bait.name = "LeafBait"
	bait.add_to_group(&"network_players")
	add_child(bait)
	bait.global_position = Vector3(24.0, 12.0, 0.0)
	var disk: CrawlerTreeLeafDisk = LEAF.new()
	_expect(disk.launch(self, Vector3(0.0, 12.0, 0.0), Vector3.ZERO, self, 24.0),
		"leaf disks appear around the tree")
	var start := disk.global_position
	disk._physics_process(0.45)
	_expect(disk.hovering()
			and start.distance_to(disk.global_position) < 0.02,
		"a new leaf hangs still for a second")
	disk._physics_process(0.65)
	_expect(not disk.hovering()
			and disk.global_position.x > start.x + 0.4,
		"the leaf then flies at the player")
	disk.queue_free()
	bait.queue_free()


func _check_arena(tree: Node) -> void:
	tree.call(&"_enter_phase1")
	_expect(bool(tree.call(&"blocks_field_spawns"))
			and bool(tree.call(&"is_engaged")),
		"a live giving tree fight owns the arena")
	_expect(tree.get(&"_boundary") != null,
		"the tree builds the red arena ring")
	var probe := Node3D.new()
	add_child(probe)
	probe.global_position = (tree as Node3D).global_position + Vector3(120.0, 0.0, 0.0)
	_expect(bool(tree.call(&"protects", probe)),
		"players inside 200 m are shielded from field packs")
	probe.global_position = (tree as Node3D).global_position + Vector3(260.0, 0.0, 0.0)
	_expect(not bool(tree.call(&"protects", probe)),
		"players outside 200 m are not in the arena")
	var up: Vector3 = tree.call(&"_up")
	var centre: Vector3 = (tree as Node3D).global_position + up * 68.0 * 0.38
	var leaf_at: Vector3 = tree.call(&"_disk_spawn_point")
	var height := (leaf_at - (tree as Node3D).global_position).dot(up)
	_expect(leaf_at.distance_to(centre) <= 16.0 and height >= 2.3,
		"phase-one leaves appear in a small sphere around the tree")
	probe.queue_free()


func _check_phase2() -> void:
	var pad := Node3D.new()
	pad.name = "MonumentPad"
	pad.position = Vector3(180.0, 60.0, -90.0)
	add_child(pad)
	var tree: Node = TREE_BOSS.new()
	tree.name = "Phase2Tree"
	pad.add_child(tree)
	await get_tree().process_frame
	tree.call(&"_enter_phase2")
	await get_tree().process_frame
	await get_tree().process_frame
	_expect(int(tree.call(&"_fruit_alive")) >= 4,
		"phase two drops fruit around the trunk")
	var near := 0
	var fruits: Array = tree.get(&"_fruits")
	for fruit_variant: Variant in fruits:
		var fruit := fruit_variant as Node3D
		if fruit == null:
			continue
		var span := fruit.global_position.distance_to((tree as Node3D).global_position)
		if span >= 8.0 and span <= 32.0:
			near += 1
	_expect(near >= 4,
		"fruit sit in a ring around the tree, not inside the monument")
	var bait := Node3D.new()
	bait.name = "SweepBait"
	bait.add_to_group(&"network_players")
	add_child(bait)
	bait.global_position = (tree as Node3D).global_position + Vector3(16.0, 2.0, 0.0)
	var model := tree.get(&"_model") as Node3D
	_expect(model != null, "phase two still has the elderwood model")
	if model != null:
		var rest := model.transform
		tree.call(&"_sweep_pose", 1.0)
		var slammed := model.transform.basis.get_rotation_quaternion() \
			.angle_to(rest.basis.get_rotation_quaternion())
		_expect(slammed > 0.45,
			"a phase-two slam leans the trunk toward the player")
		tree.call(&"_sweep_pose", 0.0)
	var animator := tree.get(&"_animator") as AnimationPlayer
	if animator != null:
		var clip := String(tree.call(&"_find_clip", "tentacle"))
		_expect(not clip.is_empty() and animator.has_animation(clip),
			"phase two plays the authored branch-tentacle clip")
	bait.queue_free()
	tree.queue_free()
	pad.queue_free()
	await get_tree().process_frame


func _check_keepout() -> void:
	var pad := PatchMonument.new()
	pad.monument_id = "boss1"
	pad.encounter = CrawlerRules.BOSS_ENCOUNTER_TREE
	pad.keepout_radius = CrawlerRules.TREE_BATTLE_RADIUS
	_expect(not pad.blocks_spawn(Vector3.ZERO),
		"an idle giving tree pad still allows field packs")
	pad.free()
	_expect(is_equal_approx(CrawlerRules.TREE_BATTLE_RADIUS, 200.0)
			and is_equal_approx(CrawlerRules.TREE_FLORA_CLEAR, 1.0),
		"the giving tree fight is a 200 m ring with a 1 m trunk hole")


func _expect(ok: bool, label: String) -> void:
	if ok:
		return
	_failures += 1
	push_error("giving_tree_test failed: %s" % label)
