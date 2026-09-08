extends Node

## Nausicaä plants at the beam tip, or sticks the fuse to a mob in front.
##
##     godot --headless --path . dev/_nausicaa_beam_test.tscn

const PLAYER := preload("res://game/player/player.tscn")

var _failures := 0


class DummyPrey extends Node3D:
	func _ready() -> void:
		add_to_group(DamageHit.COMBATANT_GROUP)

	func combat_faction() -> int:
		return DamageHit.Faction.ENEMY

	func combat_position() -> Vector3:
		return global_position

	func combat_radius() -> float:
		return 0.45

	func is_alive() -> bool:
		return true

	func apply_damage(hit: DamageHit) -> float:
		return hit.amount


func _ready() -> void:
	var from := Vector3(0.0, 1.6, 0.0)
	var along := Vector3.FORWARD
	var reach := CrawlerRules.NAUSICAA_RANGE
	var tip := Nausicaa.plan_landing(self, from, along, reach, {})
	var wanted := from + along * reach
	_expect(tip.get("follow") == null
			and tip.get("position", Vector3.ZERO).is_equal_approx(wanted),
		"empty air plants the explosion at the beam tip")

	var prey := DummyPrey.new()
	prey.name = "NearPrey"
	add_child(prey)
	prey.global_position = from + along * 2.0
	var stuck := Nausicaa.plan_landing(self, from, along, reach, {})
	_expect(stuck.get("follow") == prey
			and stuck.get("position", Vector3.ZERO).is_equal_approx(
				prey.global_position),
		"a mob in front of the beam takes the explosion with it")

	var far := DummyPrey.new()
	far.name = "FarPrey"
	add_child(far)
	far.global_position = from + along * (reach + 3.0)
	var still_near := Nausicaa.plan_landing(self, from, along, reach, {})
	_expect(still_near.get("follow") == prey,
		"a mob past the beam tip does not steal the mark")

	var beside := DummyPrey.new()
	beside.name = "BesidePrey"
	add_child(beside)
	beside.global_position = from + along * 3.0 + Vector3.RIGHT * 4.0
	_expect(Nausicaa.first_beam_prey(
				self, from, from + along * reach, 0.5) == prey,
		"a mob well off the beam is ignored")

	multiplayer.multiplayer_peer = OfflineMultiplayerPeer.new()
	var player := PLAYER.instantiate() as OnlinePlayer
	player.peer_id = multiplayer.get_unique_id()
	player.defer_camera = true
	add_child(player)
	player.set_process(false)
	player.set_physics_process(false)
	var warning := AbilityDelayedBlast.create(
		self, player, ItemDB.ability_definition("nausicaa"),
		from, from + along * reach, -along, 1.0, false, {}, prey)
	_expect(warning != null and warning.follow == prey
			and warning.at.is_equal_approx(prey.global_position),
		"the painted mark starts on the followed mob")
	if warning != null:
		warning.set_process(false)
		prey.global_position = from + along * 3.4
		warning._process(0.05)
		_expect(warning.at.is_equal_approx(prey.global_position),
			"the painted mark rides a moving mob")
		var last := warning.at
		prey.free()
		warning._process(0.05)
		_expect(warning.follow == null and warning.at.is_equal_approx(last),
			"a freed mob leaves the mark at its last position")
		warning.queue_free()
	player.queue_free()

	print("nausicaa_beam_test: %s" % (
		"all checks passed" if _failures == 0 else "%d check(s) failed" % _failures))
	get_tree().quit(1 if _failures > 0 else 0)


func _expect(ok: bool, label: String) -> void:
	if ok:
		return
	_failures += 1
	push_error("nausicaa_beam_test failed: %s" % label)
