class_name ParryIndicator
extends Control

## Textless player-vital bars beneath the hotbar. Orange is juke cooldown,
## blue is flight fuel in crawler or parry readiness otherwise, and health
## sits at the bottom.

const WIDTH := 276.0
const JUKE_HEIGHT := 8.0
const SHIELD_HEIGHT := 8.0
const HEALTH_HEIGHT := 10.0
const GOLD := Color(1.0, 0.68, 0.12, 1.0)
const JUKE_ORANGE := Color("ff7a18")

var _juke: ProgressBar
var _shield: ProgressBar
var _health: ProgressBar


func _init() -> void:
	name = "ParryIndicator"
	mouse_filter = Control.MOUSE_FILTER_IGNORE
	custom_minimum_size = Vector2(
		WIDTH, JUKE_HEIGHT + SHIELD_HEIGHT + HEALTH_HEIGHT + 6.0)
	size_flags_horizontal = Control.SIZE_SHRINK_CENTER


func _ready() -> void:
	_build()


func refresh(player: Node3D) -> void:
	if player == null:
		visible = false
		return
	if _juke != null:
		_juke.value = _juke_share(player)
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
	visible = true


func juke_share() -> float:
	return float(_juke.value) if _juke != null else 0.0


func shield_share() -> float:
	return float(_shield.value) if _shield != null else 0.0


func health_share() -> float:
	return float(_health.value) if _health != null else 0.0


func _build() -> void:
	var column := VBoxContainer.new()
	column.name = "VitalBars"
	column.add_theme_constant_override(&"separation", 3)
	column.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(column)

	_juke = _bar("JukeBar", JUKE_HEIGHT, JUKE_ORANGE)
	column.add_child(_juke)
	_shield = _bar("ShieldBar", SHIELD_HEIGHT, RedHudTheme.BLUE)
	column.add_child(_shield)
	_health = _bar("HealthBar", HEALTH_HEIGHT, RedHudTheme.HEALTH)
	column.add_child(_health)


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


func _juke_share(player: Node3D) -> float:
	if player == null or not player.has_method(&"juke_cooldown_remaining"):
		return 1.0
	var total := 0.85
	if player.has_method(&"juke_cooldown"):
		total = float(player.call(&"juke_cooldown"))
	return clampf(1.0 - float(player.call(&"juke_cooldown_remaining"))
		/ maxf(total, 0.01), 0.0, 1.0)


func _set_shield_color(color: Color) -> void:
	var radius := roundi(SHIELD_HEIGHT * 0.5)
	_shield.add_theme_stylebox_override(
		&"fill",
		RedHudTheme.style(color, color, 1, 0.0, radius)
	)

