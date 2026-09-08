extends Node

## Duals training field: every catalog mob idle on a 50 m grid, a hit log
## that names the damage, and an E menu that returns to the run.
##
##     godot --headless --path . dev/_training_session_test.tscn

const PLAYER := preload("res://game/player/player.tscn")
const FIELD_MENU := preload("res://ui/menu/crawler_field_menu.gd")
const TRAIN_MENU := preload("res://ui/menu/crawler_training_menu.gd")
const TRAINING := preload("res://game/crawler/crawler_training.gd")

var _failures := 0
var _player: OnlinePlayer
var _horde: CrawlerHorde


func _ready() -> void:
	NetworkManager.session_options = {"mode": "crawler"}
	CrawlerCatalog.reload()
	CrawlerMobs.reload()
	CrawlerProgress.clear_session()
	CrawlerMeta.begin_test()
	multiplayer.multiplayer_peer = OfflineMultiplayerPeer.new()
	NetworkManager.is_single_player = true
	NetworkManager.is_host = true
	NetworkManager.state = NetworkManager.SessionState.IN_GAME

	_player = PLAYER.instantiate() as OnlinePlayer
	_player.peer_id = multiplayer.get_unique_id()
	_player.defer_camera = true
	add_child(_player)
	_player.set_process(false)
	_player.set_physics_process(false)
	await get_tree().process_frame

	_horde = CrawlerHorde.new()
	_horde.name = "CrawlerHorde"
	add_child(_horde)
	_horde.set_process(false)
	_horde.set_physics_process(false)

	_check_duals_row()
	_check_grid_math()
	_check_hit_tags()
	await _check_field()
	_check_training_menu()

	_player.queue_free()
	_horde.queue_free()
	print("training_session_test: %s" % (
		"all checks passed" if _failures == 0 else "%d check(s) failed" % _failures))
	get_tree().quit(1 if _failures > 0 else 0)


func _check_duals_row() -> void:
	var menu = FIELD_MENU.new()
	menu.configure(_player)
	add_child(menu)
	menu._clear_list()
	menu._fill_duals()
	var empty := menu.find_child("StoreEmpty", true, false) as Label
	_expect(empty != null and empty.visible
			and empty.text.contains("co-op")
			and empty.text.contains("solo"),
		"solo Duals still explains city duels need co-op")
	var train := menu.find_child("DualsTrain", true, false) as Button
	_expect(train != null and train.visible and not train.disabled,
		"Duals offers a training start")
	menu.queue_free()


func _check_grid_math() -> void:
	var kinds := TRAINING.kinds()
	_expect(kinds.size() >= 12, "training fields every catalog mob")
	var a := TRAINING.grid_offset(0, kinds.size())
	var b := TRAINING.grid_offset(1, kinds.size())
	_expect(is_equal_approx(a.distance_to(b), TRAINING.SPACING),
		"neighbors sit 50 m apart")
	var centre := Transform3D(Basis.IDENTITY, TRAINING.FALLBACK_ORIGIN)
	var p0 := TRAINING.grid_point(centre, 0, kinds.size())
	var p1 := TRAINING.grid_point(centre, 1, kinds.size())
	_expect(is_equal_approx(p0.distance_to(p1), TRAINING.SPACING),
		"world points keep the 50 m spacing")


func _check_hit_tags() -> void:
	var aoe := DamageHit.area(Vector3.ZERO, 4.0, 12.0)
	aoe.ability_id = "starfire"
	aoe.with_status(CombatStatuses.POISON, 2.0, 1.0)
	var tags := TRAINING.hit_tags(aoe)
	_expect(tags.has("AOE") and tags.has("Toxic"),
		"area poison reads as AOE and Toxic")
	var beam := DamageHit.beam(Vector3.ZERO, Vector3.FORWARD, 0.2, 3.0)
	beam.ability_id = "laser_eyes"
	_expect(TRAINING.hit_tags(beam).has("Beam"),
		"a laser line reads as Beam")
	var who := TRAINING.hit_who(null, aoe)
	_expect(who.contains("Starfire") and who.contains("AOE")
			and who.contains("Toxic"),
		"the hit line names the ability and the kinds")
	var log := HitLog.new()
	add_child(log)
	log.record(who, 12.0)
	var lines := log.lines()
	_expect(not lines.is_empty() and lines[0].contains("12")
			and lines[0].contains("AOE"),
		"the hit log prints amount and kind")
	log.queue_free()


func _check_field() -> void:
	var centre := Transform3D(Basis.IDENTITY, TRAINING.FALLBACK_ORIGIN)
	var made := _horde.spawn_training_field(centre, 1)
	var kinds := TRAINING.kinds()
	_expect(made == kinds.size() and _horde.training_count() == kinds.size(),
		"the field seats one of every mob")
	await get_tree().process_frame
	var mobs := _horde.training_mobs()
	_expect(mobs.size() == kinds.size(), "training mobs stay listed")
	if mobs.size() >= 2:
		var gap := mobs[0].global_position.distance_to(mobs[1].global_position)
		_expect(gap > 45.0 and gap < 55.0, "live mobs keep the 50 m gap")
	if not mobs.is_empty():
		var dummy := mobs[0]
		_expect(dummy.is_training() and dummy.is_persistent()
				and not dummy.chase,
			"training mobs stand idle")
		var hit := DamageHit.area(dummy.combat_position(), 3.0, 4.0)
		hit.faction = DamageHit.Faction.PLAYER
		hit.ability_id = "toxic_blast"
		hit.with_status(CombatStatuses.POISON, 2.0, 1.0)
		dummy.apply_damage(hit)
		_expect(not dummy.chase, "a hit does not agro a training dummy")
		var tag := dummy.get_node_or_null("TrainingRange") as Label3D
		_expect(tag != null and tag.text.contains("m"),
			"each dummy wears a metre range tag")
	_expect(_horde.set_training_level(3) == kinds.size(),
		"raising the field levels every dummy")
	if not mobs.is_empty():
		_expect(mobs[0].threat_level == 3, "the raised dummies are level 3")
	_horde.clear_training()
	_expect(_horde.training_count() == 0, "clearing the field removes the dummies")


func _check_training_menu() -> void:
	var menu = TRAIN_MENU.new()
	menu.configure(_player)
	add_child(menu)
	_expect(menu.find_child("EndTraining", true, false) != null,
		"E offers a return to the run")
	_expect(menu.find_child("RaiseMobs", true, false) != null,
		"E offers a mob level raise")
	menu.queue_free()


func _expect(ok: bool, label: String) -> void:
	if ok:
		print("  ok  ", label)
	else:
		_failures += 1
		print("  FAIL  ", label)
