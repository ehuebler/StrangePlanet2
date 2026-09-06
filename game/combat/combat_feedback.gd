class_name CombatFeedback
extends Node

## Local-only combat presentation. It never writes the player transform,
## velocity, look pitch, or any other authoritative state.

signal damage_number(event: DamageNumberEvent)

const DAMAGE_SHAKE_TIME := 0.28
const STATUS_SHAKE_TIME := 0.22
const FLORA_SHAKE_GAP := 0.07
const MAX_SHAKE_OFFSET := 0.035
## A roar arrives as pressure rather than as an impact, so it rolls the view
## instead of rattling it. Kept short and well under a tenth of a turn: this
## reads as being knocked off balance, and anything longer reads as a bug.
const STATUS_WOBBLE_TIME := 0.5
const MAX_WOBBLE_ROLL := 0.10
const WOBBLE_HZ := 3.4

const BLAST_FLASH_SHADER := preload("res://game/combat/blast_flash.gdshader")
## How long a detonation holds the view inside out. About a second, because that
## is long enough to read as the world having been wrong for a moment and short
## enough that nobody starts trying to play through it.
const BLAST_FLASH_TIME := 1.05
## Share of that spent on the white wash. The flash is an instant and the negative
## it leaves behind is the part that lasts.
const BLAST_BLEACH_SHARE := 0.16
## Share of it the negative holds at full before easing back.
const BLAST_INVERT_HOLD := 0.55

var _camera: Camera3D
var _hud: CanvasLayer
var _flash: ColorRect
var _blast: ColorRect
var _blast_material: ShaderMaterial
var _blast_strength := 0.0
var _blast_left := 0.0
var _numbers: DamageNumberLayer
var _hit_marker: HitMarker
var _shake_strength := 0.0
var _shake_left := 0.0
var _shake_span := 0.0
var _shake_phase := 0.0
var _wobble_strength := 0.0
var _wobble_left := 0.0
var _wobble_span := 0.0
var _flora_gap_left := 0.0
var _base_h_offset := 0.0
var _base_v_offset := 0.0
var _base_roll := 0.0


func configure(camera: Camera3D, hud: CanvasLayer) -> void:
	_camera = camera
	_hud = hud
	if _camera != null:
		_base_h_offset = _camera.h_offset
		_base_v_offset = _camera.v_offset
		_base_roll = _camera.rotation.z
	if _hud == null:
		return
	# Added before the damage flash and the readouts, and so drawn under them:
	# what a detonation turns negative should be the world and the reticle over
	# it, not the numbers telling the player what just happened to them.
	_blast_material = ShaderMaterial.new()
	_blast_material.shader = BLAST_FLASH_SHADER
	_blast = ColorRect.new()
	_blast.name = "BlastFlash"
	_blast.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	_blast.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_blast.material = _blast_material
	_blast.visible = false
	_hud.add_child(_blast)
	_flash = ColorRect.new()
	_flash.name = "DamageFlash"
	_flash.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	_flash.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_flash.color = Color(0.82, 0.02, 0.03, 0.0)
	_hud.add_child(_flash)
	_hit_marker = HitMarker.new()
	_hit_marker.name = "HitMarker"
	# Lives on the reticle so a menu or death that hides the crosshair also
	# hides the confirmation sitting on it.
	var reticle := _hud.get_node_or_null("Reticle") as Control
	if reticle != null:
		reticle.add_child(_hit_marker)
	else:
		_hud.add_child(_hit_marker)
	_numbers = DamageNumberLayer.new()
	_numbers.name = "DamageNumbers"
	_hud.add_child(_numbers)


func _exit_tree() -> void:
	_reset_camera()


## Actual damage: red flash, shake, and an incoming number.
func damage_taken(amount: float, at: Vector3, source_peer := 0,
		source_name := "", ability_name := "") -> void:
	if amount <= 0.0:
		return
	if _flash != null:
		_flash.color.a = maxf(_flash.color.a, clampf(0.28 + amount / 90.0, 0.34, 0.78))
	shake(clampf(0.28 + amount / 75.0, 0.32, 1.0), DAMAGE_SHAKE_TIME)
	var event := DamageNumberEvent.new()
	event.amount = amount
	event.world_position = at
	event.incoming = true
	event.source_peer = source_peer
	event.source_name = _resolve_source_name(source_peer, source_name)
	event.ability_name = ability_name.strip_edges()
	_show_number(event)


## Roars and other zero-damage status impacts shake without a red flash, and
## roll the view as the pressure front goes through.
func status_impact(strength := 0.55) -> void:
	shake(clampf(strength, 0.1, 1.0), STATUS_SHAKE_TIME)
	wobble(clampf(strength, 0.1, 1.0), STATUS_WOBBLE_TIME)


func wobble(strength: float, duration: float) -> void:
	if strength <= 0.0 or duration <= 0.0 or _camera == null:
		return
	_wobble_strength = maxf(_wobble_strength, clampf(strength, 0.0, 1.0))
	_wobble_left = maxf(_wobble_left, duration)
	_wobble_span = maxf(_wobble_span, duration)


func wobble_remaining() -> float:
	return _wobble_left


func parry_feedback(perfect: bool, at := Vector3.ZERO) -> void:
	shake(0.38 if perfect else 0.22, 0.16)
	if at == Vector3.ZERO:
		return
	var event := DamageNumberEvent.new()
	event.amount = 1.0
	event.world_position = at
	event.blocked = true
	event.critical = perfect
	# A blocked label uses a symbol rather than displaying the sentinel amount.
	_show_number(event, "PERFECT" if perfect else "BLOCK")


func dodge_feedback(at := Vector3.ZERO) -> void:
	if at == Vector3.ZERO:
		return
	var event := DamageNumberEvent.new()
	event.amount = 1.0
	event.world_position = at
	event.blocked = true
	_show_number(event, "DODGE")


func outgoing_damage(amount: float, at: Vector3, target_peer := 0,
		critical := false, structure := false, merge_key := "",
		killed := false) -> void:
	if amount <= 0.0:
		return
	if _hit_marker != null:
		_hit_marker.flash(killed, critical)
	var event := DamageNumberEvent.new()
	event.amount = amount
	event.world_position = at
	event.target_peer = target_peer
	event.critical = critical
	event.structure = structure
	event.killed = killed
	event.merge_key = merge_key
	_show_number(event)


func hit_marker_remaining() -> float:
	return _hit_marker.remaining() if _hit_marker != null else 0.0


func hit_marker_is_kill() -> bool:
	return _hit_marker != null and _hit_marker.is_kill()


func _resolve_source_name(source_peer: int, named: String) -> String:
	var clean := named.strip_edges()
	if not clean.is_empty():
		return clean
	if source_peer > 0:
		return String(NetworkManager.get_player_metadata(source_peer).get(
			"name", "Player"))
	return ""


func loot_gained(gold: float, xp: float, at: Vector3, gems := 0.0) -> void:
	if gold > 0.0:
		var gold_event := DamageNumberEvent.new()
		gold_event.amount = gold
		gold_event.kind = DamageNumberEvent.Kind.GOLD
		gold_event.world_position = at
		gold_event.screen_offset = Vector2(-28.0, 8.0)
		gold_event.merge_key = "loot-gold"
		_show_number(gold_event)
	if xp > 0.0:
		var xp_event := DamageNumberEvent.new()
		xp_event.amount = xp
		xp_event.kind = DamageNumberEvent.Kind.XP
		xp_event.world_position = at
		xp_event.screen_offset = Vector2(26.0, -16.0)
		xp_event.merge_key = "loot-xp"
		_show_number(xp_event)
	if gems > 0.0:
		var gem_event := DamageNumberEvent.new()
		gem_event.amount = gems
		gem_event.kind = DamageNumberEvent.Kind.GEM
		gem_event.world_position = at
		gem_event.screen_offset = Vector2(0.0, -34.0)
		gem_event.merge_key = "loot-gem"
		_show_number(gem_event)


## Called by movement contacts. Slow brushes are silent; a sprint and a flight
## scale smoothly to the same capped visual kick.
func flora_contact(speed: float) -> void:
	if speed < 7.0 or _flora_gap_left > 0.0:
		return
	_flora_gap_left = FLORA_SHAKE_GAP
	shake(clampf(inverse_lerp(7.0, 120.0, speed), 0.08, 0.5), 0.12)


## Standing inside a detonation: a white wash, then a second of the view held
## inside out, and a kick to go with it.
##
## [param strength] is how much of it this view gets, which the effect works out
## from how far away it is. Nothing here is authoritative and nothing is sent —
## the blast already exists on every peer, so every peer's own distance to it is
## enough to decide what their screen does.
func blast_flash(strength := 1.0) -> void:
	var share := clampf(strength, 0.0, 1.0)
	if share <= 0.0:
		return
	_blast_strength = maxf(_blast_strength, share)
	_blast_left = maxf(_blast_left, BLAST_FLASH_TIME)
	shake(share * 0.9, DAMAGE_SHAKE_TIME * 1.6)
	wobble(share * 0.75, STATUS_WOBBLE_TIME)


## How long this view is still inside out for. Zero when it is not.
func blast_flash_remaining() -> float:
	return _blast_left


func shake(strength: float, duration: float) -> void:
	if strength <= 0.0 or duration <= 0.0 or _camera == null:
		return
	_shake_strength = maxf(_shake_strength, clampf(strength, 0.0, 1.0))
	_shake_left = maxf(_shake_left, duration)
	_shake_span = maxf(_shake_span, duration)


func shake_remaining() -> float:
	return _shake_left


func flash_amount() -> float:
	return _flash.color.a if _flash != null else 0.0


func _process(delta: float) -> void:
	_flora_gap_left = maxf(_flora_gap_left - delta, 0.0)
	if _flash != null and _flash.color.a > 0.0:
		_flash.color.a = maxf(_flash.color.a - delta * 1.9, 0.0)
	if _blast_left > 0.0:
		_blast_left = maxf(_blast_left - delta, 0.0)
		_drive_blast_flash()
	if _camera == null:
		return
	if _shake_left <= 0.0 and _wobble_left <= 0.0:
		_reset_camera()
		return
	if _shake_left > 0.0:
		_shake_left = maxf(_shake_left - delta, 0.0)
		_shake_phase += delta * 58.0
		var fade := _shake_left / maxf(_shake_span, 0.001)
		var magnitude := MAX_SHAKE_OFFSET * _shake_strength * fade * fade
		# Two incommensurate waves avoid a repeating diagonal while remaining
		# deterministic and allocation-free.
		_camera.h_offset = _base_h_offset \
			+ sin(_shake_phase * 1.17) * magnitude
		_camera.v_offset = _base_v_offset \
			+ sin(_shake_phase * 1.91 + 1.3) * magnitude
		if _shake_left <= 0.0:
			_shake_strength = 0.0
			_shake_span = 0.0
			_camera.h_offset = _base_h_offset
			_camera.v_offset = _base_v_offset
	if _wobble_left <= 0.0:
		return
	_wobble_left = maxf(_wobble_left - delta, 0.0)
	# A whole number of half-cycles over the span, so the roll is always back on
	# the level when the wobble runs out however long it was asked for.
	var travelled := 1.0 - _wobble_left / maxf(_wobble_span, 0.001)
	var swing := sin(travelled * TAU * WOBBLE_HZ * _wobble_span)
	_camera.rotation.z = _base_roll \
		+ swing * MAX_WOBBLE_ROLL * _wobble_strength * (1.0 - travelled)
	if _wobble_left <= 0.0:
		_wobble_strength = 0.0
		_wobble_span = 0.0
		_camera.rotation.z = _base_roll


func _drive_blast_flash() -> void:
	if _blast == null or _blast_material == null:
		return
	if _blast_left <= 0.0:
		_blast_strength = 0.0
		_blast.visible = false
		return
	var gone := 1.0 - _blast_left / BLAST_FLASH_TIME
	# White first, negative second. Inverting while the core is still white turns
	# the brightest part of the detonation into a black ball, which is exactly the
	# opposite of a flash. The two cross over near the end of the wash, then the
	# negative holds and eases back rather than snapping.
	var bleach := 1.0 - smoothstep(0.0, BLAST_BLEACH_SHARE, gone)
	var invert_in := smoothstep(
		BLAST_BLEACH_SHARE * 0.6, BLAST_BLEACH_SHARE, gone)
	var invert_out := 1.0 - smoothstep(BLAST_INVERT_HOLD, 1.0, gone)
	var invert := minf(invert_in, invert_out)
	_blast.visible = true
	_blast_material.set_shader_parameter(&"bleach", bleach * _blast_strength)
	_blast_material.set_shader_parameter(&"invert", invert * _blast_strength)


func _show_number(event: DamageNumberEvent, replacement := "") -> void:
	damage_number.emit(event)
	if _numbers == null:
		return
	if replacement.is_empty():
		_numbers.show_event(event, _camera)
		return
	# Keep the reusable event signal numeric while allowing the built-in layer
	# to render block language.
	var label := Label.new()
	label.text = replacement
	label.mouse_filter = Control.MOUSE_FILTER_IGNORE
	label.add_theme_font_size_override(&"font_size", 22)
	label.add_theme_color_override(&"font_color",
		Color(1.0, 0.8, 0.2) if event.critical else Color(0.55, 0.82, 1.0))
	label.add_theme_color_override(&"font_outline_color", Color(0.03, 0.04, 0.08, 0.9))
	label.add_theme_constant_override(&"outline_size", 5)
	_numbers.add_child(label)
	var point := _numbers.size * 0.5
	if _camera != null and event.world_position != Vector3.ZERO \
			and not _camera.is_position_behind(event.world_position):
		point = _camera.unproject_position(event.world_position)
	label.position = point - Vector2(36.0, 10.0)
	var tween := label.create_tween()
	tween.set_parallel(true)
	tween.tween_property(label, "position:y", label.position.y - 42.0, 0.65)
	tween.tween_property(label, "modulate:a", 0.0, 0.65)
	tween.set_parallel(false)
	tween.tween_callback(label.queue_free)


func _reset_camera() -> void:
	if _camera == null:
		return
	_camera.h_offset = _base_h_offset
	_camera.v_offset = _base_v_offset
	_camera.rotation.z = _base_roll
