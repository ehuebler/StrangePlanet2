class_name CombatHud
extends Control

## Local combat HUD coordinator: boss bar, transient statuses, parry readiness,
## incoming hit log, and mob damage flash hooks. Drawing lives in child
## components.

const OVERDRIVE_VIGNETTE := preload("res://ui/combat/overdrive_vignette.gd")
const FIELD_VIGNETTE := preload("res://ui/combat/field_vignette.gd")
const GOLD_CAPE_VIGNETTE := preload("res://ui/combat/gold_cape_vignette.gd")
const FPS_OVERLAY := preload("res://ui/combat/fps_overlay.gd")

var _player: Node3D
var _coordinates: CoordinatePlate
var _boss_bar: BossBar
var _status_layer: StatusChipLayer
var _parry: ParryIndicator
var _crawler_vitals: CrawlerVitalsPlate
var _entering: CrawlerEnteringNote
var _hit_log: HitLog
var _fps: Control
var _overdrive: Control
var _field: Control
var _gold_cape: Control

var _menu_open := false
var _cutscene := false
var _session_engaged := false
var _last_boss_health := -1.0
var _boss: Node
var _weapon_bar: Control


func _init() -> void:
	name = "CombatHud"
	mouse_filter = Control.MOUSE_FILTER_IGNORE
	set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)


func configure(player: Node3D, _hud: CanvasLayer,
		coordinates: CoordinatePlate, weapon_bar: Control) -> void:
	_player = player
	_coordinates = coordinates
	_weapon_bar = weapon_bar
	_boss_bar = BossBar.new()
	_status_layer = StatusChipLayer.new()
	_parry = ParryIndicator.new()
	for child: Control in [_boss_bar, _status_layer]:
		child.mouse_filter = Control.MOUSE_FILTER_IGNORE
		add_child(child)
	_parry.mouse_filter = Control.MOUSE_FILTER_IGNORE
	if weapon_bar is WeaponBar:
		(weapon_bar as WeaponBar).add_vitals(_parry)
	else:
		add_child(_parry)
	if CrawlerRules.active():
		_crawler_vitals = CrawlerVitalsPlate.new()
		_crawler_vitals.mouse_filter = Control.MOUSE_FILTER_IGNORE
		add_child(_crawler_vitals)
		_entering = CrawlerEnteringNote.new()
		_entering.mouse_filter = Control.MOUSE_FILTER_IGNORE
		add_child(_entering)
	_hit_log = HitLog.new()
	_hit_log.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(_hit_log)
	_fps = FPS_OVERLAY.new()
	_fps.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(_fps)
	_overdrive = OVERDRIVE_VIGNETTE.new()
	add_child(_overdrive)
	_field = FIELD_VIGNETTE.new()
	add_child(_field)
	_gold_cape = GOLD_CAPE_VIGNETTE.new()
	add_child(_gold_cape)
	if _player != null:
		if _player.has_signal(&"status_changed") \
				and not _player.status_changed.is_connected(_on_status_changed):
			_player.status_changed.connect(_on_status_changed)
		if _player.has_signal(&"enemy_damaged") \
				and not _player.enemy_damaged.is_connected(_on_enemy_damaged):
			_player.enemy_damaged.connect(_on_enemy_damaged)
		if _player.has_signal(&"parry_started") \
				and not _player.parry_started.is_connected(_on_parry_started):
			_player.parry_started.connect(_on_parry_started)
		if _player.has_signal(&"parry_blocked") \
				and not _player.parry_blocked.is_connected(_on_parry_blocked):
			_player.parry_blocked.connect(_on_parry_blocked)
		if _player.has_method(&"combat_feedback"):
			var feedback: Variant = _player.call(&"combat_feedback")
			if feedback is CombatFeedback:
				var stream := feedback as CombatFeedback
				if not stream.damage_number.is_connected(_on_damage_number):
					stream.damage_number.connect(_on_damage_number)


func set_menu_open(open: bool) -> void:
	_menu_open = open
	if _hit_log != null:
		_hit_log.set_suppressed(_hud_hidden())
	if _hud_hidden():
		_set_boss_boundary(false)


func set_cutscene(on: bool) -> void:
	_cutscene = on
	if _hit_log != null:
		_hit_log.set_suppressed(_hud_hidden())
	if _weapon_bar != null:
		_weapon_bar.visible = not on
	if on:
		_set_boss_boundary(false)


func is_cutscene() -> bool:
	return _cutscene


func _hud_hidden() -> bool:
	return _menu_open or _cutscene


func _exit_tree() -> void:
	_set_boss_boundary(false)


func refresh(delta: float) -> void:
	if _player == null:
		return
	if _overdrive != null and _overdrive.has_method(&"refresh"):
		_overdrive.call(&"refresh", _player, _hud_hidden(), delta)
	if _field != null and _field.has_method(&"refresh"):
		_field.call(&"refresh", _player, _hud_hidden(), delta)
	if _gold_cape != null and _gold_cape.has_method(&"refresh"):
		_gold_cape.call(&"refresh", _player, _hud_hidden(), delta)
	if _hud_hidden():
		if _boss_bar != null:
			_boss_bar.visible = false
		_set_boss_boundary(false)
		if _status_layer != null:
			_status_layer.visible = false
		if _parry != null:
			_parry.visible = false
		if _crawler_vitals != null:
			_crawler_vitals.visible = false
		if _hit_log != null:
			_hit_log.set_suppressed(true)
		if _entering != null:
			_entering.visible = false
		if _fps != null:
			_fps.visible = false
		return
	if _fps != null:
		_fps.visible = true
	_poll_boss(delta)
	_sync_statuses()
	if _parry != null:
		_parry.refresh(_player)
	if _crawler_vitals != null:
		_crawler_vitals.refresh(_player)
	_place_hit_log()


func boss_bar() -> BossBar:
	return _boss_bar


func status_layer() -> StatusChipLayer:
	return _status_layer


func parry_indicator() -> ParryIndicator:
	return _parry


func city_counter() -> CrawlerCityCounter:
	return null


func city_siege_bar() -> CrawlerCitySiegeBar:
	return null


func hit_log() -> HitLog:
	return _hit_log


func fps_overlay() -> Control:
	return _fps


func show_entering(place: String, gems := 0) -> void:
	if _entering == null:
		_entering = CrawlerEnteringNote.new()
		_entering.mouse_filter = Control.MOUSE_FILTER_IGNORE
		add_child(_entering)
	_entering.present(place, gems)


func show_note(title: String, detail := "") -> void:
	if _entering == null:
		_entering = CrawlerEnteringNote.new()
		_entering.mouse_filter = Control.MOUSE_FILTER_IGNORE
		add_child(_entering)
	_entering.present_lines(title, detail)


func entering_text() -> String:
	return _entering.current_text() if _entering != null else ""


func entering_bonus() -> String:
	return _entering.bonus_text() if _entering != null else ""


func _sync_statuses() -> void:
	if _player == null or _status_layer == null:
		return
	if not _player.has_method(&"status_rows"):
		return
	var rows: Array = _player.call(&"status_rows")
	_status_layer.sync_rows(rows)
	_status_layer.visible = not rows.is_empty()


func _poll_boss(delta: float) -> void:
	if _player == null or _boss_bar == null:
		_set_boss_boundary(false)
		return
	var found := BossAdapter.find_in_tree(_player)
	if found != _boss:
		_set_boss_boundary(false)
		_boss = found
		if _boss != null:
			_boss_bar.set_title(BossAdapter.display_name(_boss))
	if _boss == null:
		_session_engaged = false
		_last_boss_health = -1.0
		_boss_bar.visible = false
		return

	var radius := BossAdapter.battle_radius(_boss)
	var distance := BossAdapter.arena_distance_to(_boss, _player)
	var health := BossAdapter.health(_boss)
	var maximum := BossAdapter.maximum_health(_boss)
	var authoritative_engagement := BossAdapter.is_engaged(_boss)

	if authoritative_engagement:
		_session_engaged = true

	if _last_boss_health >= 0.0 and health + 0.01 < _last_boss_health:
		_session_engaged = true
		_flash_boss()
	_last_boss_health = health

	# The host keeps the encounter alive for its exit grace. Preserve the title,
	# bar and ground line for that same window; the pulsing whole-control
	# modulation is the warning to turn around. Once the authoritative reset
	# arrives, clear the local latch instead of leaving a stale warning behind.
	if distance > radius and not authoritative_engagement:
		_session_engaged = false
		_last_boss_health = -1.0
		_boss_bar.visible = false
		_boss_bar.reset_display()
		_set_boss_boundary(false)
		return

	var engaged := authoritative_engagement or _session_engaged
	if not engaged:
		_boss_bar.visible = false
		_set_boss_boundary(false)
		return

	if distance > radius:
		_boss_bar.visible = true
		_boss_bar.set_encounter(1.0, health, maximum, delta, true)
		_set_boss_boundary(true)
		return

	var alpha := BossAdapter.arena_alpha(distance, radius)
	if alpha <= 0.001:
		_boss_bar.visible = false
		_set_boss_boundary(false)
		return

	_boss_bar.visible = true
	_boss_bar.set_encounter(alpha, health, maximum, delta, false)
	_set_boss_boundary(true)


func _set_boss_boundary(shown: bool) -> void:
	if _boss != null and is_instance_valid(_boss) \
			and _boss.has_method(&"set_arena_boundary_visible"):
		_boss.call(&"set_arena_boundary_visible", shown)


func _flash_boss() -> void:
	var root := BossAdapter.model_root(_boss)
	if root != null:
		CombatantFlash.flash(root)


func _on_enemy_damaged(target: Node, amount: float, _hit: DamageHit) -> void:
	if amount <= 0.0 or target == null:
		return
	if not BossAdapter.is_boss_node(target):
		return
	_session_engaged = true
	CombatantFlash.flash(BossAdapter.model_root(target))
	# The host-side damage signal and the replicated-health poll describe the
	# same hit. Baseline the poll now so it does not retrigger the flash on the
	# next frame; remote observers, which receive no source-player signal, still
	# flash from their health drop.
	_last_boss_health = BossAdapter.health(target)


func _on_status_changed(_id: StringName, _remaining: float) -> void:
	_sync_statuses()


func _on_parry_started() -> void:
	if _parry != null and _player != null and not _hud_hidden():
		_parry.refresh(_player)


func _on_parry_blocked(_perfect: bool, _hit: DamageHit) -> void:
	if _parry != null and _player != null and not _hud_hidden():
		_parry.refresh(_player)


func _on_damage_number(event: DamageNumberEvent) -> void:
	if _hit_log == null or event == null or not event.incoming or event.amount <= 0.0:
		return
	_hit_log.record(event.source_name, event.amount, event.ability_name)


func _place_hit_log() -> void:
	if _hit_log == null:
		return
	_hit_log.set_suppressed(_hud_hidden())
	var lift := 0.0
	if _coordinates != null and _coordinates.visible:
		lift = _coordinates.size.y + 8.0
	_hit_log.set_floor_lift(lift)
