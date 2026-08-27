class_name DamageNumberLayer
extends Control

## Lightweight local HUD for reusable [DamageNumberEvent]s.

const RISE := 48.0
const LIFETIME := 0.75
## How long a running total stays open to further hits on the same target.
##
## Sustained fire arrives as a damage event every tick, and one outlined label
## per tick is both a blizzard to read and a steady churn of Controls and Tweens
## for the twenty a second the laser lands. Adding into the number already on
## screen is cheaper and says more.
const MERGE_WINDOW := 0.32

var _open: Dictionary = {}


func _ready() -> void:
	set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	mouse_filter = Control.MOUSE_FILTER_IGNORE


func show_event(event: DamageNumberEvent, camera: Camera3D) -> void:
	if event == null or camera == null or event.amount <= 0.0:
		return
	var point := size * 0.5
	if event.world_position != Vector3.ZERO \
			and not camera.is_position_behind(event.world_position):
		point = camera.unproject_position(event.world_position)

	var key := _key(event)
	var running: Variant = _open.get(key)
	if running is Dictionary and _merge(running, event, point):
		return

	var label := Label.new()
	label.mouse_filter = Control.MOUSE_FILTER_IGNORE
	label.text = str(roundi(event.amount))
	label.add_theme_font_size_override(&"font_size", 24 if event.critical else 20)
	label.add_theme_color_override(&"font_color", _colour(event))
	label.add_theme_color_override(&"font_outline_color", Color(0.03, 0.04, 0.08, 0.9))
	label.add_theme_constant_override(&"outline_size", 5)
	add_child(label)
	label.position = point - Vector2(16.0, 10.0)
	_open[key] = {
		"label": label,
		"total": event.amount,
		"opened": Time.get_ticks_msec(),
		"tween": _animate(label),
	}


## Folds a hit into the number already climbing for this target. Returns false
## when that number has finished or drifted out of its window, so the caller
## starts a fresh one.
func _merge(running: Dictionary, event: DamageNumberEvent,
		point: Vector2) -> bool:
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
	label.text = str(roundi(total))
	# Held at the point of the latest hit and given its full life back, so a
	# stream of damage reads as one number climbing rather than one fading. The
	# rise it was already partway through has to go, or two tweens race over the
	# same label and both queue it free.
	var previous := running.get("tween") as Tween
	if previous != null and previous.is_valid():
		previous.kill()
	label.position = point - Vector2(16.0, 10.0)
	label.modulate.a = 1.0
	running["tween"] = _animate(label)
	return true


func _animate(label: Label) -> Tween:
	var tween := label.create_tween()
	tween.set_parallel(true)
	tween.tween_property(label, "position:y", label.position.y - RISE, LIFETIME) \
		.set_trans(Tween.TRANS_QUAD).set_ease(Tween.EASE_OUT)
	tween.tween_property(label, "modulate:a", 0.0, LIFETIME) \
		.set_trans(Tween.TRANS_QUAD).set_ease(Tween.EASE_IN)
	tween.set_parallel(false)
	tween.tween_callback(label.queue_free)
	return tween


## One running total per target and direction: your damage to the boss and his
## to you are different numbers even when they land in the same instant.
func _key(event: DamageNumberEvent) -> String:
	if not event.merge_key.is_empty():
		return "%s:%d:%d" % [
			event.merge_key, event.source_peer, 1 if event.incoming else 0]
	return "%d:%d:%d" % [
		event.target_peer, event.source_peer, 1 if event.incoming else 0]


func _colour(event: DamageNumberEvent) -> Color:
	if event.blocked:
		return Color(0.55, 0.82, 1.0)
	if event.critical:
		return Color(1.0, 0.78, 0.2)
	if event.incoming or event.structure:
		return Color(1.0, 0.3, 0.25)
	return Color(1.0, 0.95, 0.72)
