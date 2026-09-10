extends Node

## A scout wreck must drop its gray to the ground, not hang it in the air.
##
##     godot --headless --path . dev/_gray_drop_test.tscn

var _failures := 0


func _ready() -> void:
	CrawlerCatalog.reload()
	NetworkManager.session_options = {"mode": "crawler"}
	NetworkManager.is_single_player = true
	NetworkManager.is_host = true
	NetworkManager.state = NetworkManager.SessionState.IN_GAME
	multiplayer.multiplayer_peer = OfflineMultiplayerPeer.new()
	var horde := CrawlerHorde.new()
	add_child(horde)
	horde.set_process(false)
	horde.set_physics_process(false)
	var scout := horde.spawn_test_mob("scout", Vector3(0.0, 14.0, 0.0), false, 1)
	_expect(scout != null and scout.flies(), "a scout can spawn in the air")
	if scout != null:
		scout.call("_die")
	await get_tree().process_frame
	var dropped: CrawlerGray
	for mob_variant: Variant in horde._mobs.values():
		var mob := mob_variant as CrawlerMob
		if mob != null and mob.wild_kind() == "gray":
			dropped = mob as CrawlerGray
			break
	_expect(dropped != null and dropped.dropping(),
		"a killed scout drops a falling gray")
	if dropped != null:
		var hung := dropped.global_position
		var up := dropped._up()
		dropped.set_physics_process(false)
		for _tick in 24:
			dropped._physics_process(0.05)
		var fallen := (hung - dropped.global_position).dot(up)
		_expect(dropped.dropping() and fallen > 2.0,
			"the gray falls out of the wreck instead of hanging in the air")
		dropped.set_director_lod(CrawlerRules.MOB_LOD_WARM)
		_expect(dropped.is_physics_processing(),
			"a falling gray keeps physics on away from the player")
	await _check_nearby_agro(horde)
	await _check_walks_on_floor(horde)
	horde.queue_free()
	await get_tree().process_frame
	print("gray_drop_test: %s" % (
		"all checks passed" if _failures == 0 else "%d check(s) failed" % _failures))
	get_tree().quit(1 if _failures > 0 else 0)


func _check_nearby_agro(horde: CrawlerHorde) -> void:
	var prey := Node3D.new()
	prey.name = "GrayPrey"
	prey.add_to_group(&"network_players")
	add_child(prey)
	prey.global_position = Vector3(2.0, 12.0, 0.0)
	var gray := horde.spawn_test_mob("gray", Vector3(5.0, 12.0, 0.0), false, 1) \
		as CrawlerGray
	_expect(gray != null and not gray.chase,
		"a field gray starts idle")
	if gray == null:
		prey.queue_free()
		return
	gray.set_physics_process(false)
	CrawlerMobSense.invalidate()
	CrawlerMobSense.begin_frame(get_tree())
	while CrawlerMobSense.take_think(null, true):
		pass
	gray._physics_process(0.05)
	_expect(gray.chase,
		"an idle gray standing next to the player agros even when think is spent")
	_expect(_faces_player(gray, prey),
		"an agroed gray faces the player instead of its walk")
	prey.global_position = gray.global_position + gray._flat_toward(
		gray.global_position + Vector3.RIGHT).normalized() * 4.0
	gray.call("_close_and_aim", prey, 0.05)
	_expect(_faces_player(gray, prey),
		"a kiting gray still faces the player")
	prey.queue_free()
	if is_instance_valid(gray):
		gray.queue_free()


func _check_walks_on_floor(horde: CrawlerHorde) -> void:
	var pad := StaticBody3D.new()
	var pad_shape := CollisionShape3D.new()
	var pad_box := BoxShape3D.new()
	pad_box.size = Vector3(24.0, 0.4, 24.0)
	pad_shape.shape = pad_box
	pad.add_child(pad_shape)
	add_child(pad)
	pad.global_position = Vector3(0.0, 400.0, 0.0)
	var gray := horde.spawn_test_mob("gray", Vector3(0.0, 408.0, 0.0), false, 1) \
		as CrawlerGray
	_expect(gray != null, "a field gray can spawn over a floor")
	if gray == null:
		pad.queue_free()
		return
	gray.set_physics_process(false)
	gray._planet = null
	gray.global_position = Vector3(0.0, 408.0, 0.0)
	gray._cached_up = Vector3.UP
	gray._cached_up_at = gray.global_position
	gray.hang_origin = gray.global_position
	gray._patrol_goal = gray.global_position + Vector3(6.0, 0.0, 0.0)
	await get_tree().physics_frame
	CrawlerMobSense.invalidate()
	CrawlerMobSense.begin_frame(get_tree())
	while CrawlerMobSense.take_think(null, true):
		pass
	gray.velocity = Vector3(4.0, 0.0, 0.0)
	for _tick in 16:
		gray._cached_up = Vector3.UP
		gray._cached_up_at = gray.global_position
		gray._physics_process(0.05)
	var planted := gray.global_position.y
	var want := 400.2 + gray.ground_clearance()
	_expect(absf(planted - want) < 0.45,
		"a wandering gray walks on the floor instead of through the air")
	if is_instance_valid(gray):
		gray.queue_free()
	pad.queue_free()


func _faces_player(gray: CrawlerGray, prey: Node3D) -> bool:
	if gray == null or prey == null:
		return false
	var look := gray._flat_toward(prey.global_position)
	if look.length_squared() < 0.0001:
		return false
	var wanted := gray._look_basis(look.normalized(), gray._up())
	return gray.global_transform.basis.z.normalized().dot(
		wanted.z.normalized()) > 0.98


func _expect(ok: bool, label: String) -> void:
	if ok:
		return
	_failures += 1
	push_error("gray_drop_test failed: %s" % label)
