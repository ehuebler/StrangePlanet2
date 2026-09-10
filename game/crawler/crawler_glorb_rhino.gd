class_name CrawlerGlorbRhino
extends CrawlerRhino

## Ethereal rhino Glorb. Same meteor charge; Ram plays the paw, Run the dash.
## The authored GLB faces +Z, so this kind uses the model-front look basis.


func _ready() -> void:
	_uses_model_front = true
	super._ready()


func wild_kind() -> String:
	return CrawlerGlorb.KIND_RHINO


func combat_display_name() -> String:
	return "Glorb Rhino"


func _build_body() -> void:
	CrawlerGlorb.mount(self, wild_kind())


func _tick_idle(delta: float) -> void:
	if _maybe_glorb_inbound(delta):
		return
	super._tick_idle(delta)
	_face_travel(delta)


func _tick_ai(delta: float) -> void:
	if _maybe_glorb_inbound(delta):
		return
	super._tick_ai(delta)
	_face_travel(delta)


func _face_combat_player(delta: float) -> void:
	if not _face_travel(delta):
		super._face_combat_player(delta)


func _face_travel(delta: float) -> bool:
	if _phase == Phase.PAW or _phase == Phase.CHARGE or _phase == Phase.RECOVER:
		return false
	if velocity.length_squared() < 0.3:
		return false
	_face_along(velocity, delta)
	return true


func _clip_aliases(clip: String) -> PackedStringArray:
	if clip == CLIP_PAW or clip == CLIP_CHARGE or clip == CLIP_GORE \
			or clip == CLIP_ATTACK:
		return PackedStringArray(["Ram", clip])
	return super._clip_aliases(clip)


func _glorb_travel_clip(clip: String) -> String:
	if clip == CLIP_PAW or clip == CLIP_GORE or clip == CLIP_HIT:
		return clip
	var speed := velocity.length()
	if _phase == Phase.CHARGE or _phase == Phase.RECOVER \
			or glorb_inbound() or chase or hunting() \
			or speed >= CrawlerRules.RHINO_RUN_SPEED \
			or speed >= move_speed() * 0.7:
		return CLIP_RUN
	if speed >= 0.55 or _phase == Phase.STALK:
		return CLIP_WALK
	return CLIP_IDLE
