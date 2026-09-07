extends Node

## Central session coordinator. Add this script as the "NetworkManager" autoload.
## The host owns the roster and world spawning; player movement is validated and
## relayed by the host in player.gd.

signal status_changed(message: String)
signal lobby_list_changed(lobbies: Array)
signal lobby_entered
signal lobby_left
signal roster_changed
signal invite_received(lobby_id: int, data: Dictionary, inviter_name: String)
signal player_registered(peer_id: int, metadata: Dictionary)
signal player_left(peer_id: int)
signal session_started
signal session_ended

enum SessionState {
	IDLE,
	STARTING,
	CONNECTING,
	LOBBY,
	IN_GAME,
	ERROR,
}

const WORLD_SCENE := "res://game/world.tscn"
const TextModerationScript := preload("res://core/text_moderation.gd")
const DEFAULT_PORT := 7777
const DEFAULT_MAX_PLAYERS := 8
const MAX_STEAM_PLAYERS := 8
const PLAYER_NAME_MAX_LENGTH := 12
const GAME_MODES: Array[String] = ["story", "crawler", "duels", "sandbox"]
const DUELS_MODES: Array[String] = ["battle", "race"]

var state: SessionState = SessionState.IDLE
var is_single_player := false
var is_host := false
var session_options: Dictionary = {}
var players: Dictionary = {}
var local_player_name := "Player"
## Leaving a game reloads the world with no session in it, which is the home
## screen: there is no separate menu scene to go back to.
var menu_scene_path := WORLD_SCENE
## The world in the tree, which registers itself. Asking it directly rather than
## reading `current_scene` also answers for a harness, which loads the world as a
## child of its own root.
var active_world: Node
var last_status := "Ready"
var _join_code := ""
var _rejection_pending := false
var _pending_invite: Dictionary = {}
var _kicked_steam_ids: Dictionary = {}

var _enet_peer: ENetMultiplayerPeer
var _steam_peer: SteamMultiplayerPeer


func _ready() -> void:
	multiplayer.peer_connected.connect(_on_peer_connected)
	multiplayer.peer_disconnected.connect(_on_peer_disconnected)
	multiplayer.connected_to_server.connect(_on_connected_to_server)
	multiplayer.connection_failed.connect(_on_connection_failed)
	multiplayer.server_disconnected.connect(_on_server_disconnected)
	SteamLobby.lobby_created.connect(_on_steam_lobby_created)
	SteamLobby.lobby_joined.connect(_on_steam_lobby_joined)
	SteamLobby.lobby_list_changed.connect(_on_lobby_list_changed)
	SteamLobby.operation_failed.connect(_on_steam_operation_failed)
	SteamLobby.invite_received.connect(_on_steam_invite_received)
	_set_status(SessionState.IDLE, "Ready")
	if "--server" in OS.get_cmdline_user_args():
		call_deferred("_start_from_command_line")


func start_single_player(game_mode := "story", duels_mode := "") -> void:
	_reset_session(false)
	is_single_player = true
	is_host = true
	local_player_name = saved_player_name()
	var selected_mode := sanitize_game_mode(game_mode)
	session_options = {
		"name": "Single Player",
		"max_players": 1,
		"port": 0,
		"mode": selected_mode,
		"duels_mode": (
			sanitize_duels_mode(duels_mode) if selected_mode == "duels" else ""),
	}
	if CrawlerRules.uses_mode(selected_mode):
		CrawlerKit.clear_session()
		CrawlerProgress.clear_session()
		CrawlerRules.clear_sandbox_cheats()
		CrawlerRules.apply_sandbox_defaults()
	multiplayer.multiplayer_peer = OfflineMultiplayerPeer.new()
	players[1] = _sanitize_player_metadata(_local_look_metadata(1))
	_set_status(SessionState.STARTING, "Starting single-player game...")
	_open_world()


func start_saved_game(payload: Dictionary) -> void:
	if payload.is_empty():
		return
	_reset_session(false)
	is_single_player = true
	is_host = true
	local_player_name = saved_player_name()
	var session: Dictionary = {}
	var held: Variant = payload.get("session", {})
	if held is Dictionary:
		session = held
	var selected_mode := sanitize_game_mode(str(session.get("mode", "crawler")))
	session_options = {
		"name": "Single Player",
		"max_players": 1,
		"port": 0,
		"mode": selected_mode,
		"duels_mode": (
			sanitize_duels_mode(str(session.get("duels_mode", "")))
			if selected_mode == "duels" else ""),
	}
	for key: String in [
		"crawler_cities",
		CrawlerRules.CHEAT_MOBS,
		CrawlerRules.CHEAT_INVINCIBLE,
		CrawlerRules.CHEAT_FAST,
		CrawlerRules.CHEAT_GOLD,
	]:
		if session.has(key):
			session_options[key] = session[key]
	GameSave.apply_run_payloads(payload)
	GameSave.queue_pending(payload)
	if CrawlerRules.uses_mode(selected_mode):
		CrawlerRules.apply_sandbox_defaults()
	multiplayer.multiplayer_peer = OfflineMultiplayerPeer.new()
	players[1] = _sanitize_player_metadata(_local_look_metadata(1))
	_set_status(SessionState.STARTING, "Loading saved game...")
	_open_world()


func host_game(options: Dictionary) -> void:
	_reset_session(false)
	_rejection_pending = false
	var max_players := clampi(
		int(options.get("max_players", DEFAULT_MAX_PLAYERS)),
		2,
		MAX_STEAM_PLAYERS
	)
	local_player_name = _clean_name(str(options.get("player_name", "Host")))
	session_options = options.duplicate(true)
	session_options["max_players"] = max_players
	session_options["name"] = _clean_lobby_name(str(options.get("name", "%s's game" % local_player_name)))
	session_options["visibility"] = str(options.get("visibility", "public"))
	session_options["code"] = str(options.get("code", "")).strip_edges()
	session_options["mode"] = "crawler"
	session_options["duels_mode"] = ""
	if CrawlerRules.uses_mode(str(session_options["mode"])):
		CrawlerKit.clear_session()
		CrawlerProgress.clear_session()
		CrawlerRules.clear_sandbox_cheats()
		CrawlerRules.apply_sandbox_defaults()
	if not TextModerationScript.is_allowed(local_player_name) or not TextModerationScript.is_allowed(session_options["name"]):
		_fail("Player and lobby names must use appropriate language.")
		return
	if session_options["visibility"] == "private" and session_options["code"].length() < 4:
		_fail("Private lobbies require a code.")
		return
	if not SteamLobby.available:
		_fail(SteamLobby.last_error)
		return
	_set_status(SessionState.STARTING, "Creating Steam lobby...")
	SteamLobby.create_lobby(session_options)


## Player-facing Steam join. The lobby ID comes from discovery, a friend invite,
## or Steam's +connect_lobby launch argument; there is no address field.
func join_steam_lobby(
		lobby_id: int,
		player_name: String,
		lobby_code := ""
	) -> void:
	_reset_session(false)
	_rejection_pending = false
	local_player_name = _clean_name(player_name)
	_join_code = str(lobby_code).strip_edges()
	if lobby_id <= 0:
		_fail("That Steam lobby is no longer available.")
		return
	if not SteamLobby.available:
		_fail(SteamLobby.last_error)
		return
	_set_status(SessionState.CONNECTING, "Joining Steam lobby...")
	SteamLobby.join_lobby(lobby_id)


## Hidden local transport retained for the two-process headless chat harness.
## It is deliberately not reachable from the Online menu.
func join_game(address: String, port: int, player_name: String, lobby_code := "") -> void:
	_reset_session(false)
	_rejection_pending = false
	var clean_address := address.strip_edges()
	if clean_address.is_empty():
		_fail("Enter a host address.")
		return
	if port < 1 or port > 65535:
		_fail("Port must be between 1 and 65535.")
		return

	local_player_name = _clean_name(player_name)
	_join_code = str(lobby_code).strip_edges()
	_enet_peer = ENetMultiplayerPeer.new()
	var error := _enet_peer.create_client(clean_address, port)
	if error != OK:
		_enet_peer = null
		_fail("Could not start connection (%s)." % error_string(error))
		return

	multiplayer.multiplayer_peer = _enet_peer
	_set_status(SessionState.CONNECTING, "Connecting...")


func refresh_lobbies() -> void:
	_set_status(state, "Searching Steam lobbies...")
	SteamLobby.refresh_lobbies()


func invite_friends() -> void:
	SteamLobby.invite_friends()


func leave_lobby() -> void:
	if state == SessionState.IN_GAME:
		return
	_reset_session(false, true)
	_set_status(SessionState.IDLE, "Left Steam lobby")


func start_hosted_game() -> void:
	if not is_host or state != SessionState.LOBBY:
		return
	SteamLobby.set_joinable(false)
	_begin_network_game.rpc()


func start_hosted_game_from_save() -> void:
	if not is_host or state != SessionState.LOBBY:
		return
	var payload := GameSave.read()
	if payload.is_empty():
		start_hosted_game()
		return
	SteamLobby.set_joinable(false)
	_begin_network_game_from_save.rpc(payload)


@rpc("authority", "call_local", "reliable")
func _begin_network_game_from_save(payload: Dictionary) -> void:
	if not payload.is_empty():
		GameSave.apply_run_payloads(payload)
		GameSave.queue_pending(payload)
	_open_world()


func kick_player(peer_id: int) -> void:
	if not is_host or peer_id <= 1 or not players.has(peer_id):
		return
	var steam_id := int(get_player_metadata(peer_id).get("steam_id", 0))
	if steam_id > 0:
		_kicked_steam_ids[steam_id] = true
	_reject_peer(peer_id, "The host removed you from the lobby.")


func is_peer_registered(peer_id: int) -> bool:
	return peer_id > 0 and players.has(peer_id)


func steam_available() -> bool:
	return SteamLobby.available


func steam_status() -> String:
	return "Connected to Steam as %s" % SteamLobby.local_persona_name \
		if SteamLobby.available else SteamLobby.last_error


func has_pending_invite() -> bool:
	return not _pending_invite.is_empty()


func take_pending_invite() -> Dictionary:
	var invite := _pending_invite.duplicate(true)
	_pending_invite.clear()
	return invite


func leave_game() -> void:
	_reset_session(true, true)
	_set_status(SessionState.IDLE, "Disconnected")
	session_ended.emit()


func _start_from_command_line() -> void:
	var options := {
		"player_name": "Server",
		"name": "Local Co-op Server",
		"port": DEFAULT_PORT,
		"max_players": DEFAULT_MAX_PLAYERS,
		"visibility": "public",
		"code": "",
		"mode": "story",
		"duels_mode": "",
	}
	for argument in OS.get_cmdline_user_args():
		if argument.begins_with("--port="):
			options["port"] = int(argument.trim_prefix("--port="))
		elif argument.begins_with("--max-players="):
			options["max_players"] = int(argument.trim_prefix("--max-players="))
		elif argument.begins_with("--lobby-name="):
			options["name"] = argument.trim_prefix("--lobby-name=")
		elif argument.begins_with("--player-name="):
			options["player_name"] = argument.trim_prefix("--player-name=")
		elif argument == "--private":
			options["visibility"] = "private"
		elif argument.begins_with("--lobby-code="):
			options["code"] = argument.trim_prefix("--lobby-code=")
		elif argument.begins_with("--game-mode="):
			options["mode"] = argument.trim_prefix("--game-mode=")
		elif argument.begins_with("--duels-mode="):
			options["duels_mode"] = argument.trim_prefix("--duels-mode=")
	_host_enet_test(options)


func _host_enet_test(options: Dictionary) -> void:
	_reset_session(false)
	var port := clampi(int(options.get("port", DEFAULT_PORT)), 1, 65535)
	var max_players := clampi(
		int(options.get("max_players", DEFAULT_MAX_PLAYERS)), 2, 32)
	local_player_name = _clean_name(str(options.get("player_name", "Server")))
	session_options = options.duplicate(true)
	session_options["port"] = port
	session_options["max_players"] = max_players
	session_options["name"] = _clean_lobby_name(str(
		options.get("name", "Local Test Server")))
	session_options["mode"] = "crawler"
	session_options["duels_mode"] = ""
	if CrawlerRules.uses_mode(str(session_options["mode"])):
		CrawlerKit.clear_session()
		CrawlerProgress.clear_session()
		CrawlerRules.clear_sandbox_cheats()
		CrawlerRules.apply_sandbox_defaults()

	_enet_peer = ENetMultiplayerPeer.new()
	var error := _enet_peer.create_server(port, max_players)
	if error != OK:
		_enet_peer = null
		_fail("Could not create the local test host (%s)." % error_string(error))
		return
	is_host = true
	multiplayer.multiplayer_peer = _enet_peer
	players[1] = _sanitize_player_metadata(_local_look_metadata(1))
	roster_changed.emit()
	_set_status(SessionState.STARTING, "Starting local test host...")
	_open_world()


func _on_steam_lobby_created(_created_lobby_id: int) -> void:
	_steam_peer = SteamMultiplayerPeer.new()
	_steam_peer.server_relay = true
	var error := _steam_peer.create_host(0)
	if error != OK:
		_steam_peer = null
		SteamLobby.leave_lobby()
		_fail("Could not start the Steam host (%s)." % error_string(error))
		return
	is_host = true
	multiplayer.multiplayer_peer = _steam_peer
	players[1] = _sanitize_player_metadata(_local_look_metadata(1))
	roster_changed.emit()
	_set_status(SessionState.LOBBY, "Steam lobby ready")
	lobby_entered.emit()


func _on_steam_lobby_joined(joined_lobby_id: int, owner_steam_id: int) -> void:
	if is_host:
		return
	_steam_peer = SteamMultiplayerPeer.new()
	_steam_peer.server_relay = true
	var error := _steam_peer.create_client(owner_steam_id, 0)
	if error != OK:
		_steam_peer = null
		SteamLobby.leave_lobby()
		_fail("Could not connect to the Steam host (%s)." % error_string(error))
		return
	multiplayer.multiplayer_peer = _steam_peer
	_set_status(
		SessionState.CONNECTING,
		"Connecting to %s..." % str(
			SteamLobby.lobby_data(joined_lobby_id).get("owner_name", "host"))
	)


func _on_steam_operation_failed(message: String) -> void:
	if state not in [
			SessionState.STARTING,
			SessionState.CONNECTING,
			SessionState.LOBBY,
		]:
		status_changed.emit(message)
		return
	_reset_session(false)
	_fail(message)


func _on_steam_invite_received(
		invited_lobby_id: int,
		data: Dictionary,
		inviter_name: String
	) -> void:
	_pending_invite = {
		"lobby_id": invited_lobby_id,
		"data": data.duplicate(true),
		"inviter_name": inviter_name,
	}
	invite_received.emit(invited_lobby_id, data, inviter_name)


func get_local_peer_id() -> int:
	return multiplayer.get_unique_id()


## In a session with other people in it, which is what chat and voice wait for:
## a single-player game reaches IN_GAME too, and has nobody to talk to.
func in_multiplayer_session() -> bool:
	return state == SessionState.IN_GAME and not is_single_player


func get_player_metadata(peer_id: int) -> Dictionary:
	return players.get(peer_id, {}).duplicate(true)


func update_lobby_metadata(changes: Dictionary) -> void:
	if not is_host or is_single_player:
		return
	for key in changes:
		if key in ["name", "map", "mode", "duels_mode", "passworded"]:
			session_options[key] = changes[key]
	SteamLobby.update_lobby_data(_lobby_metadata())


## The world is usually already loaded: the home screen lives inside it, so a
## session started from the menu only has to say so. Reloading the scene there
## would rebuild the planet's quadtree behind the menu and turn what should be a
## camera move into a cut. The scene change is left for the cases that really do
## arrive without a world, such as a dedicated server booting from the command
## line, or a client that has just been dropped back to a fresh menu.
func _open_world() -> void:
	if not is_instance_valid(active_world):
		LagTracker.note("session", "loading world scene")
		var error := get_tree().change_scene_to_file(WORLD_SCENE)
		if error != OK:
			_fail("Could not load the game world (%s)." % error_string(error))
			return
	_set_status(SessionState.IN_GAME, "In game")
	session_started.emit()


func _on_connected_to_server() -> void:
	_set_status(SessionState.CONNECTING, "Checking lobby admission...")
	call_deferred("_send_registration")


func _send_registration() -> void:
	var payload := _local_look_metadata(multiplayer.get_unique_id())
	payload["code"] = _join_code
	_register_player.rpc_id(1, payload)


func _on_peer_connected(peer_id: int) -> void:
	if is_host:
		_set_status(state, "Player %d connected; waiting for profile..." % peer_id)


func _on_peer_disconnected(peer_id: int) -> void:
	if not is_host:
		return
	if players.erase(peer_id):
		player_left.emit(peer_id)
		_remove_player.rpc(peer_id)
		roster_changed.emit()
		SteamLobby.update_lobby_data(_lobby_metadata())
	_set_status(state, "Player disconnected")


func _on_connection_failed() -> void:
	_reset_session(false)
	_fail("Connection failed.")


func _on_server_disconnected() -> void:
	if _rejection_pending:
		_rejection_pending = false
		return
	_reset_session(true)
	_fail("The host disconnected.")
	session_ended.emit()


@rpc("any_peer", "reliable")
func _register_player(metadata: Dictionary) -> void:
	if not multiplayer.is_server():
		return
	var sender := multiplayer.get_remote_sender_id()
	if sender <= 1:
		return
	if not TextModerationScript.is_allowed(str(metadata.get("name", ""))):
		_reject_peer(sender, "Please choose an appropriate player name.")
		return
	if _steam_peer != null:
		var transport_steam_id := int(
			_steam_peer.get_steam_id_for_peer_id(sender))
		if transport_steam_id <= 0 \
				or transport_steam_id != int(metadata.get("steam_id", 0)) \
				or not _steam_member_is_present(transport_steam_id) \
				or _kicked_steam_ids.has(transport_steam_id):
			_reject_peer(sender, "Steam could not verify this lobby member.")
			return
	if players.size() >= int(session_options.get(
			"max_players", DEFAULT_MAX_PLAYERS)):
		_reject_peer(sender, "The lobby is full.")
		return
	if str(session_options.get("visibility", "public")) == "private":
		var expected_code := str(session_options.get("code", ""))
		if expected_code.is_empty() or str(metadata.get("code", "")) != expected_code:
			_reject_peer(sender, "The private lobby code is incorrect.")
			return
	var clean := _sanitize_player_metadata(metadata)
	clean["peer_id"] = sender
	clean["name"] = _unique_player_name(str(clean["name"]))
	players[sender] = clean
	player_registered.emit(sender, clean)
	roster_changed.emit()
	_set_player_metadata.rpc(sender, clean)
	_receive_roster.rpc_id(sender, players)
	_receive_session_options.rpc_id(sender, _shared_session_options())
	_admit_to_lobby.rpc_id(sender)
	SteamLobby.update_lobby_data(_lobby_metadata())
	_set_status(state, "%s joined" % clean["name"])
	if state == SessionState.IN_GAME:
		_begin_network_game.rpc_id(sender)


@rpc("authority", "reliable")
func _set_player_metadata(peer_id: int, metadata: Dictionary) -> void:
	var was_present := players.has(peer_id)
	players[peer_id] = metadata.duplicate(true)
	if not was_present:
		player_registered.emit(peer_id, metadata)
	roster_changed.emit()


@rpc("authority", "reliable")
func _receive_roster(roster: Dictionary) -> void:
	players = roster.duplicate(true)
	roster_changed.emit()


@rpc("authority", "reliable")
func _receive_session_options(options: Dictionary) -> void:
	session_options = options.duplicate(true)


@rpc("authority", "reliable")
func _admit_to_lobby() -> void:
	_set_status(SessionState.LOBBY, "Joined Steam lobby")
	lobby_entered.emit()


@rpc("authority", "call_local", "reliable")
func _begin_network_game() -> void:
	_open_world()


@rpc("authority", "call_local", "reliable")
func _remove_player(peer_id: int) -> void:
	players.erase(peer_id)
	player_left.emit(peer_id)
	roster_changed.emit()


@rpc("authority", "reliable")
func _reject_connection(message: String) -> void:
	_rejection_pending = true
	_reset_session(true)
	_fail(message)
	session_ended.emit()


func _reject_peer(peer_id: int, message: String) -> void:
	_reject_connection.rpc_id(peer_id, message)
	get_tree().create_timer(0.25).timeout.connect(func() -> void:
		var peer := multiplayer.multiplayer_peer
		if peer != null and peer.has_method("disconnect_peer"):
			peer.disconnect_peer(peer_id, true)
	)


func _reset_session(return_to_menu: bool, reset_online_page := false) -> void:
	var closing_steam_host := is_host and not is_single_player \
		and SteamLobby.lobby_id != 0
	# The replacement World checks this in _ready. Clear it before requesting the
	# scene change so it cannot mistake the old hosted game for a live session.
	state = SessionState.IDLE
	is_host = false
	if closing_steam_host:
		SteamLobby.close_hosted_lobby()
	if multiplayer.multiplayer_peer != null:
		multiplayer.multiplayer_peer.close()
	multiplayer.multiplayer_peer = OfflineMultiplayerPeer.new()
	SteamLobby.leave_lobby(reset_online_page)
	_enet_peer = null
	_steam_peer = null
	is_single_player = false
	players.clear()
	roster_changed.emit()
	session_options.clear()
	_join_code = ""
	_kicked_steam_ids.clear()
	if reset_online_page:
		_pending_invite.clear()
		lobby_list_changed.emit([])
		lobby_left.emit()
	get_tree().paused = false
	Input.mouse_mode = Input.MOUSE_MODE_VISIBLE
	if return_to_menu and not menu_scene_path.is_empty() and ResourceLoader.exists(menu_scene_path):
		get_tree().change_scene_to_file(menu_scene_path)


func _lobby_metadata() -> Dictionary:
	return {
		"name": session_options.get("name", "Co-op game"),
		"players": players.size(),
		"max_players": int(session_options.get("max_players", DEFAULT_MAX_PLAYERS)),
		"map": str(session_options.get("map", "world")),
		"mode": str(session_options.get("mode", "story")),
		"duels_mode": str(session_options.get("duels_mode", "")),
		"visibility": str(session_options.get("visibility", "public")),
		"passworded": str(session_options.get("visibility", "public")) == "private",
		"started": state == SessionState.IN_GAME,
	}


## Session configuration safe to hand to clients. The private code is
## deliberately absent: clients prove they know it while registering and never
## receive the host's copy back.
func _shared_session_options() -> Dictionary:
	var payload := {
		"name": str(session_options.get("name", "Game")),
		"map": str(session_options.get("map", "world")),
		"mode": str(session_options.get("mode", "story")),
		"duels_mode": str(session_options.get("duels_mode", "")),
		"max_players": int(session_options.get("max_players", DEFAULT_MAX_PLAYERS)),
		"visibility": str(session_options.get("visibility", "public")),
		"crawler_cities": session_options.get("crawler_cities", []),
	}
	if str(payload["mode"]) == CrawlerRules.SANDBOX_ID:
		payload[CrawlerRules.CHEAT_MOBS] = bool(session_options.get(
			CrawlerRules.CHEAT_MOBS, false))
		payload[CrawlerRules.CHEAT_INVINCIBLE] = bool(session_options.get(
			CrawlerRules.CHEAT_INVINCIBLE, true))
		payload[CrawlerRules.CHEAT_FAST] = bool(session_options.get(
			CrawlerRules.CHEAT_FAST, true))
		payload[CrawlerRules.CHEAT_GOLD] = bool(session_options.get(
			CrawlerRules.CHEAT_GOLD, false))
	return payload


func sanitize_game_mode(value: String) -> String:
	var clean := value.strip_edges().to_lower()
	return clean if clean in GAME_MODES else "story"


func sanitize_duels_mode(value: String) -> String:
	var clean := value.strip_edges().to_lower()
	return clean if clean in DUELS_MODES else "battle"


func _sanitize_player_metadata(metadata: Dictionary) -> Dictionary:
	var look := {
		"body": CharacterDB.sanitize_body(str(metadata.get("body", CharacterDB.DEFAULT_BODY))),
		"skin": "",
		"worn": {},
		"tints": {},
	}
	look["skin"] = CharacterDB.sanitize_skin(str(look["body"]), str(metadata.get("skin", "")))
	var worn_raw: Variant = metadata.get("worn", {})
	if worn_raw is Dictionary:
		for slot: Variant in worn_raw:
			var item_id := str(worn_raw[slot])
			if ItemDB.has_item(item_id) and CharacterDB.apparel_fits(str(look["body"]), item_id):
				look["worn"][str(slot)] = item_id
	var tint_raw: Variant = metadata.get("tints", {})
	if tint_raw is Dictionary:
		look["tints"] = (tint_raw as Dictionary).duplicate(true)
	return {
		"name": _clean_name(str(metadata.get("name", "Player"))),
		"peer_id": int(metadata.get("peer_id", 0)),
		"steam_id": int(metadata.get("steam_id", 0)),
		"body": look["body"],
		"skin": look["skin"],
		"worn": look["worn"],
		"tints": look["tints"],
	}


func _local_look_metadata(peer_id: int) -> Dictionary:
	var look := CharacterDB.load_look()
	return {
		"name": local_player_name,
		"peer_id": peer_id,
		"steam_id": SteamLobby.local_steam_id if SteamLobby.available else 0,
		"body": look.get("body", CharacterDB.DEFAULT_BODY),
		"skin": look.get("skin", CharacterDB.default_skin(
			str(look.get("body", CharacterDB.DEFAULT_BODY)))),
		"worn": look.get("worn", {}),
		"tints": look.get("tints", {}),
	}


## The name typed under the figure on the home screen. It is kept in settings
## rather than only in [member local_player_name] because it outlasts a session:
## single player uses it as-is, the lobby's two fields start on it, and it is what
## the host stamps on this peer's chat lines.
func saved_player_name() -> String:
	if SettingsManager == null:
		return _clean_name("")
	return _clean_name(str(SettingsManager.get_setting(&"appearance", &"name", "Player")))


## Stores the name and returns whether it was allowed. Moderated here rather than
## at the field, so the one rule in [code]core/text_moderation.gd[/code] covers
## the home screen the same way it already covers a lobby and a chat line — a name
## refused at the door of a lobby should never have been saveable.
func save_player_name(value: String) -> bool:
	var clean := _clean_name(value)
	if not TextModerationScript.is_allowed(clean):
		return false
	local_player_name = clean
	if SettingsManager != null:
		SettingsManager.set_setting(&"appearance", &"name", clean, false)
		SettingsManager.save_settings()
	return true


func _clean_name(value: String) -> String:
	var clean := value.strip_edges().substr(0, PLAYER_NAME_MAX_LENGTH)
	return clean if not clean.is_empty() else "Player"


func _clean_lobby_name(value: String) -> String:
	var clean := value.strip_edges().substr(0, 48)
	return clean if not clean.is_empty() else "Co-op game"


func _unique_player_name(requested: String) -> String:
	var used: Dictionary = {}
	for metadata_variant: Variant in players.values():
		if metadata_variant is Dictionary:
			used[str(metadata_variant.get("name", "")).to_lower()] = true
	if not used.has(requested.to_lower()):
		return requested
	var suffix := 1
	while true:
		var ending := " %d" % suffix
		var candidate := requested.substr(
			0,
			maxi(PLAYER_NAME_MAX_LENGTH - ending.length(), 1)
		) + ending
		if not used.has(candidate.to_lower()):
			return candidate
		suffix += 1
	return requested


func _set_status(new_state: SessionState, message: String) -> void:
	state = new_state
	last_status = message
	status_changed.emit(message)


func _fail(message: String) -> void:
	_set_status(SessionState.ERROR, message)
	push_error(message)


func _on_lobby_list_changed(lobbies: Array) -> void:
	lobby_list_changed.emit(lobbies)
	if state == SessionState.IDLE:
		status_changed.emit("Found %d Steam game(s)" % lobbies.size())


func _steam_member_is_present(steam_id: int) -> bool:
	for member_variant: Variant in SteamLobby.current_members():
		if member_variant is Dictionary \
				and int(member_variant.get("steam_id", 0)) == steam_id:
			return true
	return false
