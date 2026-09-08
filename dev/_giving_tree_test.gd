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
	_expect(is_equal_approx(float(tree.call(&"battle_radius")), 50.0),
		"the fight is a 50 m ring")
	_expect(int(tree.call(&"bushel_count")) >= 22,
		"the authored foliage chunks are shootable bushels")
	_expect(not bool(tree.call(&"blocks_field_spawns")),
		"idle trees do not keep field packs off")
	var poke := DamageHit.impact(tree.call(&"combat_position"), 2.0, 40.0)
	poke.faction = DamageHit.Faction.PLAYER
	_expect(is_equal_approx(float(tree.call(&"apply_damage", poke)), 0.0),
		"the trunk is locked until phase two")
	_expect(get_tree().get_nodes_in_group(&"giving_tree_bushels").size() >= 22,
		"bushels register as combatants")
	tree.queue_free()
	await get_tree().process_frame


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
	add_child(host)
	var card := TITLE.present(host, "BOSS BATTLE", "The Giving Tree", true, true)
	_expect(card != null and String(card._headline) == "BOSS BATTLE",
		"the intro title mounts on the HUD")
	host.queue_free()


func _check_leaf() -> void:
	var disk: Node = LEAF.new()
	_expect(disk.call(&"launch", self, Vector3(0, 12, 0), Vector3.FORWARD, self, 24.0),
		"leaf disks launch from above the crown")


func _check_keepout() -> void:
	var pad := PatchMonument.new()
	pad.monument_id = "boss1"
	pad.encounter = CrawlerRules.BOSS_ENCOUNTER_TREE
	pad.keepout_radius = CrawlerRules.TREE_BATTLE_RADIUS
	_expect(not pad.blocks_spawn(Vector3.ZERO),
		"an idle giving tree pad still allows field packs")
	pad.free()
	_expect(is_equal_approx(CrawlerRules.TREE_BATTLE_RADIUS, 50.0)
			and is_equal_approx(CrawlerRules.TREE_FLORA_CLEAR, 1.0),
		"the giving tree keeps flora except a 1 m trunk hole")


func _expect(ok: bool, label: String) -> void:
	if ok:
		return
	_failures += 1
	push_error("giving_tree_test failed: %s" % label)
