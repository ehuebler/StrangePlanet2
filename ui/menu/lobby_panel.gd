class_name LobbyPanel
extends Control

## Steam lobby authoring, browser, and waiting room. The player identity comes
## from the home-screen character; this screen never asks for an IP address.

signal closed
signal notice(message: String, is_error: bool)

enum Tab { CREATE, JOIN }

const TextModerationScript := preload("res://core/text_moderation.gd")
const TAB_LABELS: Array[String] = ["Create Lobby", "Join Lobby"]
const RED := Color("ef151f")
const RED_BRIGHT := Color("ff3445")
const RED_TEXT := Color("ff9ca4")
const RED_MUTED := Color("b94a53")
const GREEN := Color("45df68")
const GREEN_TEXT := Color("8ff3a5")
const MODE_GREEN := Color("59ff7a")
const BLACK_42 := Color(0.0, 0.0, 0.0, 0.42)
const BLACK_68 := Color(0.0, 0.0, 0.0, 0.68)
const BLACK_86 := Color(0.0, 0.0, 0.0, 0.86)
const CREATE_UPPER_HEIGHT := 360.0
const LOBBY_SETTINGS_WIDTH := 310.0
const ROSTER_CARD_SIZE := Vector2(238.0, 274.0)
const ROSTER_PORTRAIT_SIZE := Vector2(220.0, 190.0)
const GAME_MODES: Array[Dictionary] = [
	{
		"id": "crawler",
		"label": "Crawler Mode",
		"description": "Push through hostile sites as a co-op crew.",
	},
]
const DUELS_MODES: Array[Dictionary] = [
	{"id": "battle", "label": "Battle"},
	{"id": "race", "label": "Race"},
]
const ACCESS_LABELS: Array[String] = [
	"Public",
	"Friends Only",
	"Private - Password",
]
const ACCESS_IDS: Array[String] = ["public", "friends", "private"]
const MODE_FILTER_LABELS: Array[String] = [
	"All Game Types",
	"Story",
	"Crawler",
	"Duels",
	"Sandbox",
]
const MODE_FILTER_IDS: Array[String] = ["", "story", "crawler", "duels", "sandbox"]

var _tab := Tab.CREATE
var _frame: PanelContainer
var _tabs: HBoxContainer
var _content: VBoxContainer
var _lobby_list: VBoxContainer
var _search: LineEdit
var _mode_filter: OptionButton
var _public_only: Button
var _known_lobbies: Array = []

var _lobby_name := ""
var _visibility := "public"
var _private_code := ""
var _max_players := 8
var _selected_mode := "crawler"
var _selected_duels_mode := "battle"


func _ready() -> void:
	name = "SteamLobbyPanel"
	size_flags_horizontal = Control.SIZE_EXPAND_FILL
	size_flags_vertical = Control.SIZE_EXPAND_FILL
	add_theme_constant_override("separation", 0)

	_frame = PanelContainer.new()
	_frame.name = "OnlineFrame"
	_frame.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	_frame.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_frame.size_flags_vertical = Control.SIZE_EXPAND_FILL
	_frame.add_theme_stylebox_override(
		&"panel",
		_style(Color(0.0, 0.0, 0.0, 0.42), Color(RED_BRIGHT, 0.96), 2, 0.0)
	)
	var frame_glow := RedGlowPanel.add_to(_frame)
	frame_glow.fill_color = Color(0.0, 0.0, 0.0, 0.16)
	frame_glow.border_color = Color(RED_BRIGHT, 0.98)
	frame_glow.border_width = 2.0
	frame_glow.glow_intensity = 1.45
	frame_glow.glow_spread = 11.0
	frame_glow.glow_layers = 5
	add_child(_frame)

	var frame_inset := MarginContainer.new()
	for side: StringName in [
			&"margin_left", &"margin_top", &"margin_right", &"margin_bottom"
	]:
		frame_inset.add_theme_constant_override(side, 14)
	_frame.add_child(frame_inset)

	var shell := VBoxContainer.new()
	shell.name = "OnlineShell"
	shell.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	shell.size_flags_vertical = Control.SIZE_EXPAND_FILL
	shell.add_theme_constant_override(&"separation", 10)
	frame_inset.add_child(shell)

	var header := HBoxContainer.new()
	header.name = "OnlineHeader"
	header.add_theme_constant_override(&"separation", 10)
	shell.add_child(header)

	var back := _button("BACK")
	back.name = "Back"
	back.custom_minimum_size = Vector2(116, 46)
	back.pressed.connect(_on_back_pressed)
	header.add_child(back)

	_tabs = HBoxContainer.new()
	_tabs.name = "LobbyTabs"
	_tabs.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_tabs.add_theme_constant_override("separation", 10)
	header.add_child(_tabs)

	var page_scroll := ScrollContainer.new()
	page_scroll.name = "OnlinePageScroll"
	page_scroll.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	page_scroll.size_flags_vertical = Control.SIZE_EXPAND_FILL
	page_scroll.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	page_scroll.vertical_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	_style_scrollbar(page_scroll.get_v_scroll_bar())
	shell.add_child(page_scroll)

	var scroll_inset := MarginContainer.new()
	scroll_inset.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	scroll_inset.add_theme_constant_override(&"margin_right", 12)
	page_scroll.add_child(scroll_inset)
	_content = VBoxContainer.new()
	_content.name = "LobbyContent"
	_content.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_content.size_flags_vertical = Control.SIZE_EXPAND_FILL
	_content.add_theme_constant_override("separation", 10)
	scroll_inset.add_child(_content)

	_reset_page_state()
	_connect_network_signals()
	_build_current()
	CrtType.watch(self)
	if NetworkManager.has_pending_invite():
		call_deferred("_consume_pending_invite")


func _exit_tree() -> void:
	var bindings: Array[Array] = [
		[NetworkManager.lobby_list_changed, _on_lobby_list_changed],
		[NetworkManager.lobby_entered, _on_lobby_entered],
		[NetworkManager.lobby_left, _on_lobby_left],
		[NetworkManager.roster_changed, _on_roster_changed],
	]
	for binding: Array in bindings:
		var source: Signal = binding[0]
		var callback: Callable = binding[1]
		if source.is_connected(callback):
			source.disconnect(callback)


func _connect_network_signals() -> void:
	NetworkManager.lobby_list_changed.connect(_on_lobby_list_changed)
	NetworkManager.lobby_entered.connect(_on_lobby_entered)
	NetworkManager.lobby_left.connect(_on_lobby_left)
	NetworkManager.roster_changed.connect(_on_roster_changed)


func _build_current() -> void:
	var waiting := NetworkManager.state == NetworkManager.SessionState.LOBBY
	var visible_tab := Tab.CREATE if waiting else _tab
	_clear(_tabs)
	for index in TAB_LABELS.size():
		var tab_button := _button(TAB_LABELS[index], index == int(visible_tab))
		tab_button.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		tab_button.custom_minimum_size.y = 46
		var chosen := index
		tab_button.pressed.connect(func() -> void: _show_tab(chosen as Tab))
		_tabs.add_child(tab_button)
	for tab_button: Node in _tabs.get_children():
		var button := CrtType.inner(tab_button) as Button
		if button != null:
			button.disabled = waiting

	_clear(_content)
	if waiting:
		_build_create_page(true)
	elif _tab == Tab.CREATE:
		_build_create_page(false)
	else:
		_build_join_page()


func _show_tab(next_tab: Tab) -> void:
	if NetworkManager.state == NetworkManager.SessionState.LOBBY:
		return
	_tab = next_tab
	_build_current()
	if _tab == Tab.JOIN:
		_refresh_lobbies()


func _build_create_page(waiting: bool) -> void:
	var upper := HBoxContainer.new()
	upper.name = "CreateLobbyUpper"
	upper.custom_minimum_size.y = CREATE_UPPER_HEIGHT
	upper.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	upper.add_theme_constant_override("separation", 12)
	_content.add_child(upper)

	_build_lobby_settings(upper, waiting)
	_build_roster(upper, waiting)
	_build_game_modes(waiting)


func _build_lobby_settings(parent: Control, waiting: bool) -> void:
	var settings := _card(parent, 12, true)
	settings.name = "LobbySettings"
	var settings_panel := settings.get_parent().get_parent() as PanelContainer
	settings_panel.size_flags_horizontal = Control.SIZE_SHRINK_BEGIN
	settings_panel.custom_minimum_size.x = LOBBY_SETTINGS_WIDTH
	settings.custom_minimum_size.x = LOBBY_SETTINGS_WIDTH - 24.0
	settings.add_child(_heading("LOBBY SETTINGS", 18))
	settings.add_child(_rule())

	var form := _scroll_area(settings, 180.0)
	var lobby_name := _field(
		form, "Lobby name", _current_option("name", _lobby_name), "Name your lobby")
	lobby_name.name = "LobbyName"
	lobby_name.max_length = 48
	lobby_name.editable = not waiting
	lobby_name.text_changed.connect(func(value: String) -> void:
		_lobby_name = value
	)

	var access_group := _option_row(
		"Lobby access",
		ACCESS_LABELS,
		maxi(ACCESS_IDS.find(_current_option("visibility", _visibility)), 0),
		func(index: int) -> void:
			_visibility = ACCESS_IDS[index]
			_build_current()
	)
	access_group.name = "LobbyAccess"
	form.add_child(access_group)
	var access := access_group.get_child(1) as OptionButton
	access.disabled = waiting

	var shown_visibility := _current_option("visibility", _visibility)
	if shown_visibility == "private":
		var code := _field(
			form,
			"Lobby password",
			_private_code if not waiting else "",
			"4-12 letters or numbers"
		)
		code.name = "LobbyPassword"
		code.max_length = 12
		code.secret = true
		code.editable = not waiting
		code.text_changed.connect(func(value: String) -> void:
			_private_code = value
		)
		if waiting:
			code.placeholder_text = "Password set"

	var maximum := _number_field(
		form,
		"Max players",
		2,
		NetworkManager.MAX_STEAM_PLAYERS,
		float(int(NetworkManager.session_options.get(
			"max_players", _max_players)) if waiting else _max_players)
	)
	maximum.name = "MaxPlayers"
	maximum.editable = not waiting
	maximum.value_changed.connect(func(value: float) -> void:
		_max_players = int(value)
		if not waiting:
			_build_current()
	)

	var steam_status := _caption(NetworkManager.steam_status())
	steam_status.name = "SteamStatus"
	settings.add_child(steam_status)


func _build_roster(parent: Control, waiting: bool) -> void:
	var roster := _card(parent, 12, true)
	roster.name = "PlayerRoster"
	roster.size_flags_horizontal = Control.SIZE_EXPAND_FILL

	var header := HBoxContainer.new()
	header.add_theme_constant_override("separation", 10)
	roster.add_child(header)
	var title := _heading(
		"PLAYERS  %d/%d" % [_roster_players(waiting).size(), _roster_limit(waiting)],
		18
	)
	title.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	header.add_child(title)
	if waiting:
		var invite := _button("INVITE STEAM FRIENDS")
		invite.name = "InviteFriends"
		invite.pressed.connect(NetworkManager.invite_friends)
		header.add_child(invite)
	roster.add_child(_rule())

	var scroll := ScrollContainer.new()
	scroll.name = "RosterScroll"
	scroll.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	scroll.size_flags_vertical = Control.SIZE_EXPAND_FILL
	scroll.vertical_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	scroll.custom_minimum_size.y = ROSTER_CARD_SIZE.y
	_style_scrollbar(scroll.get_h_scroll_bar())
	roster.add_child(scroll)

	var cards := HBoxContainer.new()
	cards.name = "RosterCards"
	cards.add_theme_constant_override("separation", 10)
	scroll.add_child(cards)
	var roster_players := _roster_players(waiting)
	for metadata_variant: Variant in roster_players:
		if metadata_variant is Dictionary:
			cards.add_child(_player_card(metadata_variant, waiting))
	for slot in maxi(_roster_limit(waiting) - roster_players.size(), 0):
		cards.add_child(_empty_player_card(slot))


func _roster_players(waiting: bool) -> Array:
	if waiting:
		var result: Array = []
		var ids := NetworkManager.players.keys()
		ids.sort()
		for peer_variant: Variant in ids:
			var metadata := NetworkManager.get_player_metadata(int(peer_variant))
			metadata["peer_id"] = int(peer_variant)
			result.append(metadata)
		return result
	var look := CharacterDB.load_look()
	return [{
		"name": NetworkManager.saved_player_name(),
		"peer_id": 1,
		"steam_id": SteamLobby.local_steam_id if SteamLobby.available else 0,
		"body": look.get("body", CharacterDB.DEFAULT_BODY),
		"skin": look.get("skin", ""),
		"worn": look.get("worn", {}),
		"tints": look.get("tints", {}),
	}]


func _roster_limit(waiting: bool) -> int:
	return int(NetworkManager.session_options.get(
		"max_players", _max_players)) if waiting else _max_players


func _player_card(metadata: Dictionary, waiting: bool) -> PanelContainer:
	var panel := PanelContainer.new()
	panel.custom_minimum_size = ROSTER_CARD_SIZE
	panel.add_theme_stylebox_override(
		&"panel", _style(Color(0.0, 0.0, 0.0, 0.52), Color(RED, 0.72), 1, 0.0)
	)
	var margin := MarginContainer.new()
	for side: String in ["left", "top", "right", "bottom"]:
		margin.add_theme_constant_override("margin_%s" % side, 8)
	panel.add_child(margin)
	var column := VBoxContainer.new()
	column.add_theme_constant_override("separation", 3)
	margin.add_child(column)
	column.add_child(_player_portrait(metadata))

	var peer_id := int(metadata.get("peer_id", 0))
	var host := peer_id == 1
	var name_label := Label.new()
	name_label.text = str(metadata.get("name", "Player"))
	name_label.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	_style_label(name_label, GREEN_TEXT, 12)
	column.add_child(name_label)
	column.add_child(_caption(
		"HOST" if host else "STEAM PLAYER"))
	var steam_id := int(metadata.get("steam_id", 0))
	if steam_id > 0:
		column.add_child(_caption("Steam ID …%s" % str(steam_id).right(6)))

	if waiting and NetworkManager.is_host and not host:
		var spacer := Control.new()
		spacer.size_flags_vertical = Control.SIZE_EXPAND_FILL
		column.add_child(spacer)
		var kick := _button("KICK", false, true)
		kick.name = "Kick%d" % peer_id
		kick.pressed.connect(NetworkManager.kick_player.bind(peer_id))
		column.add_child(kick)
	return panel


func _player_portrait(metadata: Dictionary) -> Control:
	if DisplayServer.get_name() == "headless":
		var placeholder := Control.new()
		placeholder.name = "PlayerPortrait"
		placeholder.custom_minimum_size = ROSTER_PORTRAIT_SIZE
		return placeholder
	var equipment := ItemContainer.new(ItemDB.SLOT_ORDER.size())
	var worn: Dictionary = metadata.get("worn", {})
	for index in ItemDB.SLOT_ORDER.size():
		var slot: String = ItemDB.SLOT_ORDER[index]
		equipment.set_filter(index, slot)
		equipment.set_item(index, str(worn.get(slot, "")))
	var preview := RedCharacterPreview.new()
	preview.name = "PlayerPortrait"
	preview.view_size = ROSTER_PORTRAIT_SIZE
	preview.camera_height_scale = 1.08
	preview.configure(
		equipment,
		str(metadata.get("body", CharacterDB.DEFAULT_BODY)),
		str(metadata.get("skin", "")),
		metadata.get("tints", {})
	)
	preview.tooltip_text = "Drag to rotate"
	return preview


func _empty_player_card(slot: int) -> PanelContainer:
	var panel := PanelContainer.new()
	panel.custom_minimum_size = ROSTER_CARD_SIZE
	panel.add_theme_stylebox_override(
		&"panel", _style(Color(0.0, 0.0, 0.0, 0.52), Color(RED, 0.48), 1, 10.0)
	)
	var label := _caption("OPEN SLOT %d\nWAITING FOR A STEAM FRIEND…" % (slot + 1))
	label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	label.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	panel.add_child(label)
	return panel


func _build_game_modes(waiting: bool) -> void:
	var modes := _card(_content, 12, true)
	modes.name = "GameModes"
	modes.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	modes.add_child(_heading("GAME MODES", 22, MODE_GREEN))
	modes.add_child(_rule())

	if _selected_mode == "sandbox" and not CrawlerMeta.sandbox_unlocked():
		_selected_mode = "crawler"
	var selected_mode := _current_option("mode", _selected_mode)
	if waiting:
		var hosted := HBoxContainer.new()
		hosted.name = "HostedMode"
		hosted.add_theme_constant_override("separation", 14)
		modes.add_child(hosted)
		hosted.add_child(_mode_card(_mode_record(selected_mode), true, Callable()))
		if selected_mode == "duels":
			var choices := VBoxContainer.new()
			choices.size_flags_horizontal = Control.SIZE_EXPAND_FILL
			choices.add_theme_constant_override("separation", 8)
			hosted.add_child(choices)
			for option: Dictionary in DUELS_MODES:
				var chosen := str(option["id"]) == _current_option(
					"duels_mode", _selected_duels_mode)
				var duel := _button(str(option["label"]), chosen)
				duel.disabled = not NetworkManager.is_host
				duel.pressed.connect(_pick_hosted_duels_mode.bind(str(option["id"])))
				choices.add_child(duel)
		_add_waiting_actions(hosted)
		return

	var row := HBoxContainer.new()
	row.name = "ModeCards"
	row.add_theme_constant_override("separation", 10)
	modes.add_child(row)
	for mode: Dictionary in GAME_MODES:
		var mode_id := str(mode["id"])
		var locked := mode_id == "sandbox" and not CrawlerMeta.sandbox_unlocked()
		var card := _mode_card(
			mode,
			mode_id == _selected_mode and not locked,
			func() -> void:
				if mode_id == "sandbox" and not CrawlerMeta.sandbox_unlocked():
					return
				_selected_mode = mode_id
				_build_current()
		)
		if locked:
			card.disabled = true
			card.tooltip_text = "Reach your first city to unlock Sandbox."
		row.add_child(card)

	var host := _button("HOST LOBBY", true)
	host.name = "HostLobby"
	host.custom_minimum_size = Vector2(300, 34)
	host.size_flags_horizontal = Control.SIZE_SHRINK_CENTER
	host.disabled = not NetworkManager.steam_available()
	host.pressed.connect(_host_lobby)
	modes.add_child(host)


func _mode_card(
		mode: Dictionary,
		selected: bool,
		callback: Callable
	) -> Button:
	var card := _button("", selected)
	card.custom_minimum_size = Vector2(190, 82)
	card.size_flags_horizontal = Control.SIZE_EXPAND_FILL

	var inset := MarginContainer.new()
	inset.mouse_filter = Control.MOUSE_FILTER_IGNORE
	inset.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	for side: StringName in [
			&"margin_left", &"margin_top", &"margin_right", &"margin_bottom"
	]:
		inset.add_theme_constant_override(side, 7)
	card.add_child(inset)

	var copy := VBoxContainer.new()
	copy.mouse_filter = Control.MOUSE_FILTER_IGNORE
	copy.alignment = BoxContainer.ALIGNMENT_BEGIN
	copy.add_theme_constant_override(&"separation", 7)
	inset.add_child(copy)

	var title := Label.new()
	title.name = "ModeTitle"
	title.text = String(mode.get("label", "Mode")).to_upper()
	title.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	title.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	title.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_style_label(title, MODE_GREEN, 17)
	copy.add_child(title)

	var description := Label.new()
	description.name = "ModeDescription"
	description.text = String(mode.get("description", "")).to_upper()
	description.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	description.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	description.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_style_label(description, Color(0.96, 0.98, 1.0), 12)
	copy.add_child(description)
	if callback.is_valid():
		card.pressed.connect(callback)
	else:
		card.disabled = true
	return card


func _add_waiting_actions(parent: HBoxContainer) -> void:
	var actions := VBoxContainer.new()
	actions.custom_minimum_size.x = 230
	actions.alignment = BoxContainer.ALIGNMENT_CENTER
	actions.add_theme_constant_override("separation", 8)
	parent.add_child(actions)
	if NetworkManager.is_host:
		var start := _button("START", true)
		start.name = "StartLobby"
		start.custom_minimum_size.y = 48
		start.pressed.connect(NetworkManager.start_hosted_game)
		actions.add_child(start)
		if GameSave.has_save():
			var load_start := _button("START FROM SAVE")
			load_start.name = "StartLobbyFromSave"
			load_start.custom_minimum_size.y = 48
			load_start.pressed.connect(NetworkManager.start_hosted_game_from_save)
			actions.add_child(load_start)
	else:
		var waiting := _caption("WAITING FOR THE HOST TO START…")
		waiting.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
		actions.add_child(waiting)


func _build_join_page() -> void:
	var browser := _card(_content, 12, true)
	browser.name = "JoinLobbyBrowser"
	browser.size_flags_horizontal = Control.SIZE_EXPAND_FILL

	var filters := HBoxContainer.new()
	filters.name = "LobbyFilters"
	filters.add_theme_constant_override("separation", 10)
	browser.add_child(filters)

	_search = LineEdit.new()
	_search.name = "LobbySearch"
	_search.placeholder_text = "Search lobby name"
	_search.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_style_input(_search)
	_search.text_changed.connect(func(_value: String) -> void: _rebuild_join_rows())
	filters.add_child(_search)

	_mode_filter = OptionButton.new()
	_mode_filter.name = "GameTypeFilter"
	for label: String in MODE_FILTER_LABELS:
		_mode_filter.add_item(label)
	_mode_filter.item_selected.connect(func(_index: int) -> void: _rebuild_join_rows())
	_style_option(_mode_filter)
	filters.add_child(_mode_filter)

	_public_only = _button("PUBLIC ONLY")
	_public_only.name = "PublicOnly"
	_public_only.toggle_mode = true
	_public_only.toggled.connect(func(enabled: bool) -> void:
		_public_only.text = "PUBLIC ONLY" if enabled else "PUBLIC + PRIVATE"
		_style_button(_public_only, enabled)
		_rebuild_join_rows()
	)
	filters.add_child(_public_only)

	var refresh := _button("REFRESH", true)
	refresh.name = "RefreshLobbies"
	refresh.pressed.connect(_refresh_lobbies)
	filters.add_child(refresh)
	browser.add_child(_rule())

	var scroll := ScrollContainer.new()
	scroll.name = "LobbyResultsScroll"
	scroll.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	scroll.size_flags_vertical = Control.SIZE_EXPAND_FILL
	scroll.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	scroll.custom_minimum_size.y = 380
	_style_scrollbar(scroll.get_v_scroll_bar())
	browser.add_child(scroll)
	var inset := MarginContainer.new()
	inset.add_theme_constant_override("margin_right", 20)
	inset.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	scroll.add_child(inset)
	_lobby_list = VBoxContainer.new()
	_lobby_list.name = "LobbyResults"
	_lobby_list.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_lobby_list.add_theme_constant_override("separation", 8)
	inset.add_child(_lobby_list)
	_rebuild_join_rows()


func _refresh_lobbies() -> void:
	notice.emit("Searching Steam lobbies…", false)
	NetworkManager.refresh_lobbies()


func _on_lobby_list_changed(lobbies: Array) -> void:
	_known_lobbies = lobbies.duplicate(true)
	if _tab == Tab.JOIN and _lobby_list != null and is_instance_valid(_lobby_list):
		_rebuild_join_rows()


func _rebuild_join_rows() -> void:
	if _lobby_list == null or not is_instance_valid(_lobby_list):
		return
	_clear(_lobby_list)
	var search_text := _search.text.strip_edges().to_lower() \
		if is_instance_valid(_search) else ""
	var mode_id := MODE_FILTER_IDS[_mode_filter.selected] \
		if is_instance_valid(_mode_filter) else ""
	var public_only := _public_only.button_pressed \
		if is_instance_valid(_public_only) else false
	var shown := 0
	for lobby_variant: Variant in _known_lobbies:
		if not lobby_variant is Dictionary:
			continue
		var data: Dictionary = lobby_variant
		var lobby_name := str(data.get("name", "Lobby"))
		if not TextModerationScript.is_allowed(lobby_name):
			continue
		if not search_text.is_empty() and not lobby_name.to_lower().contains(search_text):
			continue
		if not mode_id.is_empty() and str(data.get("mode", "")) != mode_id:
			continue
		if public_only and str(data.get("visibility", "public")) != "public":
			continue
		_lobby_list.add_child(_make_lobby_row(data))
		shown += 1
	if shown == 0:
		var message := "No matching Steam lobbies."
		if not NetworkManager.steam_available():
			message = NetworkManager.steam_status()
		var empty := _caption(message)
		empty.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
		_lobby_list.add_child(empty)


func _make_lobby_row(data: Dictionary) -> PanelContainer:
	var panel := PanelContainer.new()
	panel.custom_minimum_size.y = 62
	panel.size_flags_vertical = Control.SIZE_SHRINK_BEGIN
	panel.add_theme_stylebox_override(
		&"panel", _style(Color(0.0, 0.0, 0.0, 0.52), Color(RED, 0.68), 1, 0.0)
	)
	var margin := MarginContainer.new()
	for side: String in ["left", "top", "right", "bottom"]:
		margin.add_theme_constant_override("margin_%s" % side, 12)
	panel.add_child(margin)
	var row := HBoxContainer.new()
	row.alignment = BoxContainer.ALIGNMENT_CENTER
	row.add_theme_constant_override("separation", 12)
	margin.add_child(row)

	var name_label := Label.new()
	name_label.name = "LobbyRowName"
	name_label.text = str(data.get("name", "Lobby"))
	name_label.custom_minimum_size.x = 220
	name_label.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	name_label.autowrap_mode = TextServer.AUTOWRAP_OFF
	name_label.clip_text = true
	name_label.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	_style_label(name_label, GREEN_TEXT, 13)
	row.add_child(name_label)
	var mode := str(data.get("mode", "story")).capitalize()
	if mode == "Duels":
		mode += " · %s" % str(data.get("duels_mode", "battle")).capitalize()
	row.add_child(_lobby_row_caption(mode, "LobbyRowMode", 112.0))
	row.add_child(_lobby_row_caption("%d/%d players" % [
		int(data.get("players", 0)),
		int(data.get("max_players", 0)),
	], "LobbyRowPlayers", 96.0))
	var access := str(data.get("visibility", "public"))
	row.add_child(_lobby_row_caption(
		"PASSWORD" if bool(data.get("passworded", false))
		else "FRIENDS" if access == "friends"
		else "PUBLIC",
		"LobbyRowAccess",
		86.0
	))

	var join := _button("JOIN", true)
	join.name = "JoinLobby"
	join.custom_minimum_size = Vector2(84, 38)
	join.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	join.pressed.connect(func() -> void: _join_from_data(data))
	row.add_child(join)
	return panel


func _lobby_row_caption(text: String, node_name: String, width: float) -> Label:
	var label := _caption(text)
	label.name = node_name
	label.custom_minimum_size.x = width
	label.autowrap_mode = TextServer.AUTOWRAP_OFF
	label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	label.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	return label


func _join_from_data(data: Dictionary) -> void:
	if bool(data.get("passworded", false)):
		_ask_for_code(data)
		return
	_join_lobby(int(data.get("lobby_id", 0)), "")


func _ask_for_code(data: Dictionary) -> void:
	var dialog := ConfirmationDialog.new()
	dialog.name = "PrivateLobbyPassword"
	dialog.title = str(data.get("name", "Private Steam Lobby"))
	dialog.ok_button_text = "JOIN"
	dialog.cancel_button_text = "CANCEL"
	dialog.add_theme_stylebox_override(
		&"panel", _style(BLACK_86, Color(RED_BRIGHT, 0.96), 2, 14.0)
	)
	_style_button(dialog.get_ok_button(), true)
	_style_button(dialog.get_cancel_button(), false)
	var code := LineEdit.new()
	code.name = "Password"
	code.placeholder_text = "Lobby password"
	code.max_length = 12
	code.secret = true
	code.custom_minimum_size = Vector2(320, 48)
	_style_input(code)
	dialog.add_child(code)
	dialog.register_text_enter(code)
	add_child(dialog)
	dialog.confirmed.connect(func() -> void:
		var entered := code.text.strip_edges()
		if not _is_valid_code(entered):
			notice.emit("Enter the 4-12 character lobby password.", true)
			return
		_join_lobby(int(data.get("lobby_id", 0)), entered)
	)
	dialog.canceled.connect(dialog.queue_free)
	dialog.visibility_changed.connect(func() -> void:
		if not dialog.visible:
			dialog.queue_free()
	)
	dialog.popup_centered()
	code.grab_focus()


func _join_lobby(lobby_id: int, code: String) -> void:
	var player_name := NetworkManager.saved_player_name()
	if not _validate(player_name):
		return
	NetworkManager.join_steam_lobby(lobby_id, player_name, code)


func _host_lobby() -> void:
	var player_name := NetworkManager.saved_player_name()
	if not _validate(player_name, _lobby_name):
		return
	if _visibility == "private" and not _is_valid_code(_private_code):
		notice.emit("Private passwords must be 4-12 letters or numbers.", true)
		return
	if _selected_mode == "sandbox" and not CrawlerMeta.sandbox_unlocked():
		notice.emit("Reach your first city to unlock Sandbox.", true)
		return
	NetworkManager.host_game({
		"player_name": player_name,
		"name": _lobby_name.strip_edges(),
		"max_players": _max_players,
		"mode": "crawler",
		"duels_mode": "",
		"visibility": _visibility,
		"code": _private_code if _visibility == "private" else "",
		"map": "world",
	})


func _pick_hosted_duels_mode(mode_id: String) -> void:
	if not NetworkManager.is_host:
		return
	_selected_duels_mode = mode_id
	NetworkManager.session_options["duels_mode"] = mode_id
	NetworkManager.update_lobby_metadata({"duels_mode": mode_id})
	_build_current()


func _consume_pending_invite() -> void:
	var invite := NetworkManager.take_pending_invite()
	if invite.is_empty():
		return
	_tab = Tab.JOIN
	_build_current()
	var data: Dictionary = invite.get("data", {})
	if data.is_empty():
		data = {
			"lobby_id": int(invite.get("lobby_id", 0)),
			"name": "Steam Friend's Lobby",
			"passworded": false,
		}
	var inviter := str(invite.get("inviter_name", ""))
	if not inviter.is_empty():
		notice.emit("%s invited you to a Steam lobby." % inviter, false)
	if bool(data.get("passworded", false)):
		_ask_for_code(data)
	else:
		_join_lobby(int(invite.get("lobby_id", 0)), "")


func _on_lobby_entered() -> void:
	_build_current()


func _on_back_pressed() -> void:
	if NetworkManager.state == NetworkManager.SessionState.LOBBY:
		NetworkManager.leave_lobby()
	closed.emit()


func _on_lobby_left() -> void:
	_reset_page_state()
	_build_current()


func _on_roster_changed() -> void:
	if NetworkManager.state == NetworkManager.SessionState.LOBBY:
		_build_current()


func _reset_page_state() -> void:
	_tab = Tab.CREATE
	_known_lobbies.clear()
	_lobby_name = "%s's Lobby" % NetworkManager.saved_player_name()
	_visibility = "public"
	_private_code = ""
	_max_players = 8
	_selected_mode = "crawler"
	_selected_duels_mode = "battle"


func _current_option(key: String, fallback: String) -> String:
	if NetworkManager.state == NetworkManager.SessionState.LOBBY:
		return str(NetworkManager.session_options.get(key, fallback))
	return fallback


func _mode_record(mode_id: String) -> Dictionary:
	for mode: Dictionary in GAME_MODES:
		if str(mode["id"]) == mode_id:
			return mode
	return GAME_MODES[0]


func _validate(player_name: String, lobby_name := "") -> bool:
	if player_name.strip_edges().is_empty():
		notice.emit("Set your player name on the home screen first.", true)
		return false
	if not TextModerationScript.is_allowed(player_name):
		notice.emit("Please choose an appropriate player name.", true)
		return false
	if not lobby_name.is_empty() and not TextModerationScript.is_allowed(lobby_name):
		notice.emit("Please choose an appropriate lobby name.", true)
		return false
	return true


func _is_valid_code(value: String) -> bool:
	if value.length() < 4 or value.length() > 12:
		return false
	for character in value:
		var codepoint := character.to_lower().to_ascii_buffer()[0]
		var is_number := codepoint >= 48 and codepoint <= 57
		var is_letter := codepoint >= 97 and codepoint <= 122
		if not is_number and not is_letter:
			return false
	return true


func _card(parent: Control, padding := 12, fill := false) -> VBoxContainer:
	var panel := PanelContainer.new()
	panel.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	panel.size_flags_vertical = (
		Control.SIZE_EXPAND_FILL if fill else Control.SIZE_SHRINK_BEGIN
	)
	panel.add_theme_stylebox_override(
		&"panel",
		_style(Color(0.0, 0.0, 0.0, 0.50), Color(RED_BRIGHT, 0.84), 1, 0.0)
	)
	var glow := RedGlowPanel.add_to(panel)
	glow.fill_color = Color(0.0, 0.0, 0.0, 0.20)
	glow.border_color = Color(RED, 0.82)
	glow.border_width = 1.25
	glow.glow_intensity = 0.85
	glow.glow_spread = 6.0
	glow.glow_layers = 3
	parent.add_child(panel)

	var margin := MarginContainer.new()
	for side: StringName in [
			&"margin_left", &"margin_top", &"margin_right", &"margin_bottom"
	]:
		margin.add_theme_constant_override(side, padding)
	panel.add_child(margin)

	var box := VBoxContainer.new()
	box.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	box.size_flags_vertical = (
		Control.SIZE_EXPAND_FILL if fill else Control.SIZE_SHRINK_BEGIN
	)
	box.add_theme_constant_override(&"separation", 8)
	margin.add_child(box)
	return box


func _heading(
		text: String,
		font_size := 18,
		colour: Color = RED_BRIGHT
	) -> Label:
	var label := Label.new()
	label.text = text.to_upper()
	_style_label(label, colour, font_size)
	return label


func _caption(text: String) -> Label:
	var label := Label.new()
	label.text = text.to_upper()
	label.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	_style_label(label, RED_MUTED, 10)
	return label


func _field(
		parent: Control,
		label_text: String,
		value: String,
		placeholder: String
	) -> LineEdit:
	var group := VBoxContainer.new()
	group.add_theme_constant_override(&"separation", 3)
	parent.add_child(group)
	group.add_child(_caption(label_text))

	var input := LineEdit.new()
	input.text = value
	input.placeholder_text = placeholder
	input.max_length = 64
	input.custom_minimum_size.y = 32
	_style_input(input)
	group.add_child(input)
	return input


func _number_field(
		parent: Control,
		label_text: String,
		minimum: float,
		maximum: float,
		value: float
	) -> SpinBox:
	var group := VBoxContainer.new()
	group.add_theme_constant_override(&"separation", 3)
	parent.add_child(group)
	group.add_child(_caption(label_text))

	var input := SpinBox.new()
	input.min_value = minimum
	input.max_value = maximum
	input.value = value
	input.allow_greater = false
	input.allow_lesser = false
	input.custom_minimum_size.y = 32
	_style_input(input.get_line_edit())
	group.add_child(input)
	return input


func _option_row(
		label_text: String,
		options: Array,
		selected: int,
		callback: Callable
	) -> VBoxContainer:
	var group := VBoxContainer.new()
	group.add_theme_constant_override(&"separation", 3)
	group.add_child(_caption(label_text))

	var option := OptionButton.new()
	option.custom_minimum_size.y = 32
	option.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	for item: Variant in options:
		option.add_item(String(item))
	option.select(clampi(selected, 0, maxi(options.size() - 1, 0)))
	option.item_selected.connect(callback)
	_style_option(option)
	group.add_child(option)
	return group


func _scroll_area(parent: Control, height := 140.0) -> VBoxContainer:
	var scroll := ScrollContainer.new()
	scroll.custom_minimum_size.y = height
	scroll.size_flags_vertical = Control.SIZE_EXPAND_FILL
	scroll.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	_style_scrollbar(scroll.get_v_scroll_bar())
	parent.add_child(scroll)

	var inset := MarginContainer.new()
	inset.add_theme_constant_override(&"margin_right", 12)
	inset.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	scroll.add_child(inset)

	var box := VBoxContainer.new()
	box.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	box.add_theme_constant_override(&"separation", 8)
	inset.add_child(box)
	return box


func _button(
		label_text: String,
		selected := false,
		destructive := false
	) -> Button:
	var button := Button.new()
	button.text = label_text.to_upper()
	button.custom_minimum_size.y = 34
	button.mouse_default_cursor_shape = Control.CURSOR_POINTING_HAND
	button.focus_mode = Control.FOCUS_ALL
	_style_button(button, selected, destructive)
	return button


func _style_button(
		button: Button,
		selected: bool,
		destructive := false
	) -> void:
	var accent := GREEN if selected else (RED_BRIGHT if destructive else RED)
	var text_color := GREEN_TEXT if selected else (
		RED_BRIGHT if destructive else RED_TEXT
	)
	var fill := Color(0.0, 0.15, 0.045, 0.84) if selected else BLACK_86
	button.add_theme_font_size_override(&"font_size", 11)
	button.add_theme_color_override(&"font_color", text_color)
	button.add_theme_color_override(&"font_hover_color", GREEN_TEXT)
	button.add_theme_color_override(&"font_pressed_color", GREEN)
	button.add_theme_color_override(&"font_focus_color", text_color)
	button.add_theme_color_override(
		&"font_disabled_color", Color(RED_MUTED, 0.42)
	)
	button.add_theme_color_override(
		&"font_outline_color", Color(0.08, 0.0, 0.0, 0.98)
	)
	button.add_theme_constant_override(&"outline_size", 1)
	button.add_theme_stylebox_override(
		&"normal", _style(fill, Color(accent, 0.94), 2 if selected else 1, 7.0)
	)
	button.add_theme_stylebox_override(
		&"hover",
		_style(BLACK_86, GREEN, 2, 7.0, Color(GREEN, 0.13), 3)
	)
	button.add_theme_stylebox_override(
		&"pressed",
		_style(Color(0.0, 0.19, 0.055, 0.92), GREEN, 2, 7.0)
	)
	button.add_theme_stylebox_override(
		&"focus", _style(Color.TRANSPARENT, GREEN, 1, 6.0)
	)
	button.add_theme_stylebox_override(
		&"disabled", _style(BLACK_42, Color(RED_MUTED, 0.30), 1, 7.0)
	)


func _style_input(input: LineEdit) -> void:
	input.add_theme_font_size_override(&"font_size", 11)
	input.add_theme_color_override(&"font_color", GREEN_TEXT)
	input.add_theme_color_override(&"font_selected_color", BLACK_86)
	input.add_theme_color_override(&"font_uneditable_color", RED_MUTED)
	input.add_theme_color_override(&"font_placeholder_color", Color(RED_MUTED, 0.72))
	input.add_theme_color_override(&"selection_color", Color(GREEN, 0.82))
	input.add_theme_stylebox_override(
		&"normal", _style(BLACK_86, Color(RED, 0.84), 1, 7.0)
	)
	input.add_theme_stylebox_override(
		&"focus",
		_style(BLACK_86, GREEN, 2, 7.0, Color(GREEN, 0.10), 3)
	)
	input.add_theme_stylebox_override(
		&"read_only", _style(BLACK_42, Color(RED_MUTED, 0.38), 1, 7.0)
	)


func _style_option(option: OptionButton) -> void:
	option.add_theme_font_size_override(&"font_size", 11)
	option.add_theme_color_override(&"font_color", GREEN_TEXT)
	option.add_theme_color_override(&"font_hover_color", GREEN_TEXT)
	option.add_theme_color_override(&"font_pressed_color", GREEN)
	option.add_theme_color_override(&"font_focus_color", GREEN_TEXT)
	option.add_theme_stylebox_override(
		&"normal", _style(BLACK_86, Color(RED, 0.84), 1, 7.0)
	)
	option.add_theme_stylebox_override(
		&"hover", _style(BLACK_86, GREEN, 2, 7.0)
	)
	option.add_theme_stylebox_override(
		&"pressed", _style(Color(0.0, 0.16, 0.045, 0.92), GREEN, 2, 7.0)
	)
	option.add_theme_stylebox_override(
		&"focus", _style(Color.TRANSPARENT, GREEN, 1, 6.0)
	)
	var popup := option.get_popup()
	popup.add_theme_font_size_override(&"font_size", 11)
	popup.add_theme_color_override(&"font_color", RED_TEXT)
	popup.add_theme_color_override(&"font_hover_color", GREEN_TEXT)
	popup.add_theme_color_override(&"font_checked_color", GREEN_TEXT)
	popup.add_theme_stylebox_override(
		&"panel", _style(BLACK_86, RED, 1, 6.0)
	)
	popup.add_theme_stylebox_override(
		&"hover", _style(Color(0.0, 0.15, 0.04, 0.90), GREEN, 1, 5.0)
	)


func _style_scrollbar(scrollbar: ScrollBar) -> void:
	scrollbar.custom_minimum_size.x = 9
	scrollbar.custom_minimum_size.y = 9
	scrollbar.add_theme_stylebox_override(
		&"scroll", _style(BLACK_86, Color(RED, 0.58), 1, 2.0)
	)
	scrollbar.add_theme_stylebox_override(
		&"grabber", _style(Color(0.0, 0.16, 0.045, 0.94), GREEN, 1, 2.0)
	)
	scrollbar.add_theme_stylebox_override(
		&"grabber_highlight",
		_style(Color(0.0, 0.22, 0.065, 0.98), GREEN_TEXT, 1, 2.0)
	)
	scrollbar.add_theme_stylebox_override(
		&"grabber_pressed", _style(GREEN, GREEN_TEXT, 1, 2.0)
	)


func _style_label(label: Label, color: Color, font_size: int) -> void:
	label.add_theme_font_size_override(&"font_size", font_size)
	label.add_theme_color_override(&"font_color", color)
	label.add_theme_color_override(
		&"font_outline_color", Color(0.10, 0.0, 0.0, 0.94)
	)
	label.add_theme_constant_override(&"outline_size", 1)


func _rule() -> PanelContainer:
	var rule := PanelContainer.new()
	rule.custom_minimum_size.y = 2
	rule.mouse_filter = Control.MOUSE_FILTER_IGNORE
	rule.add_theme_stylebox_override(
		&"panel", _style(Color(RED, 0.48), RED_BRIGHT, 1, 0.0)
	)
	return rule


func _style(
		fill: Color,
		border: Color,
		border_width: int,
		padding: float,
		shadow: Color = Color.TRANSPARENT,
		shadow_size: int = 0
	) -> StyleBoxFlat:
	var box := StyleBoxFlat.new()
	box.bg_color = fill
	box.border_color = border
	box.set_border_width_all(border_width)
	box.set_corner_radius_all(0)
	box.content_margin_left = padding
	box.content_margin_top = padding
	box.content_margin_right = padding
	box.content_margin_bottom = padding
	box.shadow_color = shadow
	box.shadow_size = shadow_size
	box.shadow_offset = Vector2.ZERO
	return box


func _clear(parent: Node) -> void:
	for child: Node in parent.get_children():
		parent.remove_child(child)
		child.queue_free()
