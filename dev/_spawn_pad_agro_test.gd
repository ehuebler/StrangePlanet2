extends Node

## Field packs ignore a player still standing on the Relay 07 teleporter.
##
##     godot --headless --path . dev/_spawn_pad_agro_test.tscn

const PLAYER := preload("res://game/player/player.tscn")
const MOB_SENSE := preload("res://game/crawler/crawler_mob_sense.gd")

var _failures := 0


func _ready() -> void:
	multiplayer.multiplayer_peer = OfflineMultiplayerPeer.new()
	var player := PLAYER.instantiate() as OnlinePlayer
	player.peer_id = multiplayer.get_unique_id()
	add_child(player)
	player.set_process(false)
	player.set_physics_process(false)
	var pad := CrawlerSpawnPad.new()
	pad.position = Vector3(40.0, 0.0, 0.0)
	add_child(pad)
	var hunter := CrawlerRanger.new()
	hunter.configure(
		"pad_agro",
		Transform3D(Basis(), pad.global_position + Vector3(8.0, 2.0, 0.0)),
		1, false)
	add_child(hunter)
	hunter.set_physics_process(false)
	await get_tree().process_frame

	player.global_position = pad.global_position + Vector3(0.0, 1.5, 0.0)
	MOB_SENSE.invalidate()
	MOB_SENSE.begin_frame(get_tree())
	_expect(MOB_SENSE.player_on_spawn_pad(player)
			and pad.holds_standing(player.global_position),
		"standing on the teleporter is still on the deck")
	_expect(MOB_SENSE.nearest_player(hunter) == null,
		"packs do not take a player on the teleporter as prey")
	_expect(not hunter.tick_agro(player, 0.16) and not hunter.chase,
		"mobs do not agro a player on the teleporter")

	player.global_position = pad.global_position + Vector3(14.0, 1.5, 0.0)
	MOB_SENSE.invalidate()
	MOB_SENSE.begin_frame(get_tree())
	_expect(not MOB_SENSE.player_on_spawn_pad(player),
		"walking off the teleporter leaves the deck")
	_expect(MOB_SENSE.nearest_player(hunter) == player,
		"packs hunt the player after they leave the teleporter")
	_expect(hunter.tick_agro(player, 0.16) and hunter.chase,
		"mobs agro once the player steps off the teleporter")

	player.global_position = pad.global_position + Vector3(0.0, 1.5, 0.0)
	MOB_SENSE.invalidate()
	MOB_SENSE.begin_frame(get_tree())
	_expect(not hunter.tick_agro(player, 0.16) and not hunter.chase,
		"agro drops if the player steps back onto the teleporter")

	print("spawn_pad_agro_test: %s" % (
		"all checks passed" if _failures == 0 else "%d check(s) failed" % _failures))
	get_tree().quit(1 if _failures > 0 else 0)


func _expect(ok: bool, message: String) -> bool:
	if not ok:
		_failures += 1
		push_error("spawn_pad_agro_test failed: %s" % message)
	return ok
