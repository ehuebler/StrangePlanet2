class_name DamageNumberLayer
extends Control

## Lightweight local HUD for reusable [DamageNumberEvent]s.

const RISE := 52.0
const LIFETIME := 0.78
## How long a running total stays open to further hits on the same target.
##
## Sustained fire arrives as a damage event every tick, and one outlined label
## per tick is both a blizzard to read and a steady churn of Controls and Tweens
## for the twenty a second the laser lands. Adding into the number already on
## screen is cheaper and says more.
const MERGE_WINDOW := 0.32
const SCATTER_X := 22.0
const SCATTER_Y := 14.0
const WORLD_SCATTER := 0.55
const WORLD_LIFT := 0.42
const DRIFT_X := 16.0
const DRIFT_Y := 6.0
const JIGGLE := 7.5
const JIGGLE_HZ := 3.5
const SPIN := 0.14

var _open: Dictionary = {}
var _rng := RandomNumberGenerator.new()


func _ready() -> void:
	set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	mouse_filter = Control.MOUSE_FILTER_IGNORE
	_rng.randomize()


func show_event(event: DamageNumberEvent, camera: Camera3D) -> void:
	if event == null or camera == null or event.amount <= 0.0:
		return
	var key := _key(event)
	var running: Variant = _open.get(key)
	if event.kind != DamageNumberEvent.Kind.CHARM \
			and event.kind != DamageNumberEvent.Kind.SHOCK \
			and running is Dictionary and _merge(running, event, camera):
		return

	var nudge := _world_nudge(camera)
	var scatter := Vector2(
		_rng.randf_range(-SCATTER_X, SCATTER_X),
		_rng.randf_range(-SCATTER_Y, SCATTER_Y))
	var drift := Vector2(
		_rng.randf_range(-DRIFT_X, DRIFT_X),
		_rng.randf_range(-DRIFT_Y, DRIFT_Y * 0.4))
	var spin := _rng.randf_range(-SPIN, SPIN)
	var label := Label.new()
	label.mouse_filter = Control.MOUSE_FILTER_IGNORE
	label.text = event.caption()
	label.add_theme_font_size_override(&"font_size", 24 if event.critical else 20)
	label.add_theme_color_override(&"font_color", _colour(event))
	label.add_theme_color_override(&"font_outline_color", Color(0.03, 0.04, 0.08, 0.9))
	label.add_theme_constant_override(&"outline_size", 5)
	add_child(label)
	_place(label, event, camera, nudge, scatter)
	_open[key] = {
		"label": label,
		"total": event.amount,
		"opened": Time.get_ticks_msec(),
		"nudge": nudge,
		"scatter": scatter,
		"drift": drift,
		"spin": spin,
		"tween": _animate(label, label.position, drift, spin),
	}


## Folds a hit into the number already climbing for this target. Returns false
## when that number has finished or drifted out of its window, so the caller
## starts a fresh one.
func _merge(running: Dictionary, event: DamageNumberEvent,
		camera: Camera3D) -> bool:
	# Checked before the cast: the label is freed the moment its rise finishes,
	# and casting a freed object is an error rather than a null.
	var held: Variant = running.get("label")
	if not is_instance_valid(held):
		return false
	var label := held as Label
	if label == null:
		return false
	if Time.get_ticks_msec() - int(running["opened"]) > int(MERGE_WINDOW * 1000.0):
		return false
	var total := float(running["total"]) + event.amount
	running["total"] = total
	label.text = event.caption(total)
	# Held at the point of the latest hit and given its full life back, so a
	# stream of damage reads as one number climbing rather than one fading. The
	# rise it was already partway through has to go, or two tweens race over the
	# same label and both queue it free. Scatter stays put so a laser does not
	# hop to a new random pixel every tick.
	var previous := running.get("tween") as Tween
	if previous != null and previous.is_valid():
		previous.kill()
	var nudge: Vector3 = running.get("nudge", Vector3.ZERO)
	var scatter: Vector2 = running.get("scatter", Vector2.ZERO)
	var drift: Vector2 = running.get("drift", Vector2.ZERO)
	var spin := float(running.get("spin", 0.0))
	_place(label, event, camera, nudge, scatter)
	label.modulate.a = 1.0
	running["tween"] = _animate(label, label.position, drift, spin)
	return true


func _animate(label: Label, origin: Vector2, drift: Vector2, spin: float) -> Tween:
	var tween := label.create_tween()
	tween.set_parallel(true)
	tween.tween_method(
		_drive_pop.bind(label, origin, drift, spin), 0.0, 1.0, LIFETIME)
	tween.tween_property(label, "modulate:a", 0.0, LIFETIME) \
		.set_trans(Tween.TRANS_QUAD).set_ease(Tween.EASE_IN)
	tween.set_parallel(false)
	tween.tween_callback(label.queue_free)
	return tween


func _drive_pop(gone: float, label: Label, origin: Vector2, drift: Vector2,
		spin: float) -> void:
	if not is_instance_valid(label):
		return
	var t := clampf(gone, 0.0, 1.0)
	var ease := 1.0 - (1.0 - t) * (1.0 - t)
	var fade := 1.0 - t * t
	var wobble := sin(t * TAU * JIGGLE_HZ) * JIGGLE * fade
	label.position = origin + Vector2(drift.x * ease + wobble, -RISE * ease + drift.y * ease)
	label.rotation = spin * (1.0 - ease * 0.7)


func _place(label: Label, event: DamageNumberEvent, camera: Camera3D,
		nudge: Vector3, scatter: Vector2) -> void:
	var point := size * 0.5
	var at := event.world_position + nudge
	if at != Vector3.ZERO and not camera.is_position_behind(at):
		point = camera.unproject_position(at)
	label.position = _anchor(label, point, event.screen_offset + scatter)
	var wide := label.get_minimum_size()
	label.pivot_offset = Vector2(maxf(wide.x, 8.0) * 0.5, wide.y * 0.5)


func _world_nudge(camera: Camera3D) -> Vector3:
	var right := camera.global_basis.x
	var lift := camera.global_basis.y
	if right.length_squared() < 0.0001:
		right = Vector3.RIGHT
	if lift.length_squared() < 0.0001:
		lift = Vector3.UP
	return right.normalized() * _rng.randf_range(-WORLD_SCATTER, WORLD_SCATTER) \
		+ lift.normalized() * _rng.randf_range(-WORLD_SCATTER * 0.35, WORLD_LIFT)


## One running total per target and direction: your damage to the boss and his
## to you are different numbers even when they land in the same instant.
func _key(event: DamageNumberEvent) -> String:
	if event.kind != DamageNumberEvent.Kind.DAMAGE:
		return "%d:%s:%.0f:%.0f:%.0f" % [
			event.kind, event.merge_key,
			event.world_position.x, event.world_position.y, event.world_position.z]
	if not event.merge_key.is_empty():
		return "%s:%d:%d" % [
			event.merge_key, event.source_peer, 1 if event.incoming else 0]
	return "%d:%d:%d" % [
		event.target_peer, event.source_peer, 1 if event.incoming else 0]


func _colour(event: DamageNumberEvent) -> Color:
	if event.kind == DamageNumberEvent.Kind.GOLD:
		return Color(1.0, 0.82, 0.18)
	if event.kind == DamageNumberEvent.Kind.XP:
		return Color(0.32, 0.62, 1.0)
	if event.kind == DamageNumberEvent.Kind.GEM:
		return Color(0.55, 0.92, 1.0)
	if event.kind == DamageNumberEvent.Kind.POISON:
		return Color(0.35, 0.92, 0.28)
	if event.kind == DamageNumberEvent.Kind.CHARM:
		return Color(1.0, 0.42, 0.72)
	if event.kind == DamageNumberEvent.Kind.SHOCK:
		return Color(0.75, 0.92, 1.0)
	if event.kind == DamageNumberEvent.Kind.FREEZE:
		return Color(0.72, 0.92, 1.0)
	if event.blocked:
		return Color(0.55, 0.82, 1.0)
	if event.critical:
		return Color(1.0, 0.78, 0.2)
	if event.incoming or event.structure:
		return Color(1.0, 0.3, 0.25)
	return Color(1.0, 0.95, 0.72)


func _anchor(label: Label, point: Vector2, shift: Vector2) -> Vector2:
	var wide := label.get_minimum_size().x
	if wide < 8.0:
		wide = 32.0
	return point - Vector2(wide * 0.5, 10.0) + shift
