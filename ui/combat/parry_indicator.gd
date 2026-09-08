class_name ParryIndicator
extends Control

## Textless player-vital bars beneath the hotbar. Blue is flight fuel in
## crawler or parry readiness otherwise, and health sits at the bottom.

const WIDTH := 276.0
const SHIELD_HEIGHT := 8.0
const HEALTH_HEIGHT := 10.0
const GOLD := Color(1.0, 0.68, 0.12, 1.0)
const TOXIC := Color(0.22, 1.0, 0.18, 1.0)
const TOXIC_GOOP := preload("res://ui/combat/toxic_health_goop.gdshader")
const TOXIC_OUTLINE := 4

var _shield: ProgressBar
var _health: ProgressBar
var _goop: ColorRect
var _goop_mat: ShaderMaterial
var _toxic := false
var _phase := 0.0


func _init() -> void:
	name = "ParryIndicator"
	mouse_filter = Control.MOUSE_FILTER_IGNORE
	custom_minimum_size = Vector2(
		WIDTH, SHIELD_HEIGHT + HEALTH_HEIGHT + 3.0)
	size_flags_horizontal = Control.SIZE_SHRINK_CENTER
	set_process(false)


func _ready() -> void:
	_build()


func refresh(player: Node3D) -> void:
	if player == null:
		visible = false
		return
	if CrawlerRules.active() and player.has_method(&"flight_fuel_share"):
		_shield.value = clampf(float(player.call(&"flight_fuel_share")), 0.0, 1.0)
		_set_shield_color(RedHudTheme.BLUE)
	else:
		var cooldown_total := maxf(float(player.get("parry_cooldown")), 0.01)
		var cooldown_left := float(player.call(&"parry_cooldown_remaining"))
		var active := bool(player.call(&"parry_active"))
		var perfect := bool(player.call(&"parry_perfect_active"))
		var shield_share := clampf(
			1.0 - cooldown_left / cooldown_total,
			0.0,
			1.0
		)
		# The active window starts with the same empty bar as the cooldown. A perfect
		# parry flashes gold without replacing the blue readiness meaning.
		_shield.value = shield_share
		_set_shield_color(GOLD if active and perfect else RedHudTheme.BLUE)

	var health := float(player.call(&"health"))
	var maximum := maxf(float(player.call(&"maximum_health")), 0.001)
	_health.value = clampf(health / maximum, 0.0, 1.0)
	_set_toxic(player.has_method(&"has_status")
			and bool(player.call(&"has_status", CombatStatuses.POISON)))
	_sync_goop()
	visible = true


func shield_share() -> float:
	return float(_shield.value) if _shield != null else 0.0


func health_share() -> float:
	return float(_health.value) if _health != null else 0.0


func toxic_active() -> bool:
	return _toxic


func _build() -> void:
	var column := VBoxContainer.new()
	column.name = "VitalBars"
	column.add_theme_constant_override(&"separation", 3)
	column.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(column)

	_shield = _bar("ShieldBar", SHIELD_HEIGHT, RedHudTheme.BLUE)
	column.add_child(_shield)
	_health = _bar("HealthBar", HEALTH_HEIGHT, RedHudTheme.HEALTH)
	column.add_child(_health)
	_build_goop()


func _bar(node_name: String, height: float, color: Color) -> ProgressBar:
	var bar := ProgressBar.new()
	bar.name = node_name
	bar.min_value = 0.0
	bar.max_value = 1.0
	bar.step = 0.001
	bar.value = 1.0
	bar.show_percentage = false
	bar.custom_minimum_size = Vector2(WIDTH, height)
	bar.mouse_filter = Control.MOUSE_FILTER_IGNORE
	var radius := roundi(height * 0.5)
	bar.add_theme_stylebox_override(
		&"background",
		RedHudTheme.style(RedHudTheme.BLACK, color, 1, 0.0, radius)
	)
	bar.add_theme_stylebox_override(
		&"fill",
		RedHudTheme.style(color, color, 1, 0.0, radius)
	)
	return bar


func _set_shield_color(color: Color) -> void:
	var radius := roundi(SHIELD_HEIGHT * 0.5)
	_shield.add_theme_stylebox_override(
		&"fill",
		RedHudTheme.style(color, color, 1, 0.0, radius)
	)


func _build_goop() -> void:
	if _health == null or _goop != null:
		return
	_goop = ColorRect.new()
	_goop.name = "ToxicGoop"
	_goop.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_goop.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	_goop.color = Color.WHITE
	_goop_mat = ShaderMaterial.new()
	_goop_mat.shader = TOXIC_GOOP
	_goop_mat.set_shader_parameter(&"tint", TOXIC)
	_goop_mat.set_shader_parameter(&"strength", 1.0)
	_goop.material = _goop_mat
	_goop.visible = false
	_health.add_child(_goop)


func _set_toxic(on: bool) -> void:
	if _toxic == on:
		return
	_toxic = on
	set_process(on)
	if _goop != null:
		_goop.visible = on
	_paint_health()


func _paint_health() -> void:
	if _health == null:
		return
	var radius := roundi(HEALTH_HEIGHT * 0.5)
	if _toxic:
		var track := RedHudTheme.style(RedHudTheme.BLACK, TOXIC, TOXIC_OUTLINE, 0.0, radius)
		track.expand_margin_left = float(TOXIC_OUTLINE)
		track.expand_margin_right = float(TOXIC_OUTLINE)
		track.expand_margin_top = float(TOXIC_OUTLINE)
		track.expand_margin_bottom = float(TOXIC_OUTLINE)
		track.shadow_size = 6
		track.shadow_color = Color(TOXIC, 0.62)
		_health.add_theme_stylebox_override(&"background", track)
		_health.add_theme_stylebox_override(
			&"fill",
			RedHudTheme.style(RedHudTheme.HEALTH, TOXIC, 1, 0.0, radius)
		)
		return
	_health.add_theme_stylebox_override(
		&"background",
		RedHudTheme.style(RedHudTheme.BLACK, RedHudTheme.HEALTH, 1, 0.0, radius)
	)
	_health.add_theme_stylebox_override(
		&"fill",
		RedHudTheme.style(RedHudTheme.HEALTH, RedHudTheme.HEALTH, 1, 0.0, radius)
	)


func _sync_goop() -> void:
	if _goop_mat == null:
		return
	_goop_mat.set_shader_parameter(&"fill", float(_health.value) if _health != null else 1.0)
	_goop_mat.set_shader_parameter(&"phase", _phase)


func _process(delta: float) -> void:
	if not _toxic:
		return
	_phase += maxf(delta, 0.0)
	_sync_goop()

