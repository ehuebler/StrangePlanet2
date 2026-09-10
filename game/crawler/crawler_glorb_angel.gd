class_name CrawlerGlorbAngel
extends CrawlerVesper

## Ethereal angel Glorb. Same four-wing vesper telegraph beam.


func wild_kind() -> String:
	return CrawlerGlorb.KIND_ANGEL


func combat_display_name() -> String:
	return "Glorb Angel"


func flyer_floor() -> float:
	return CrawlerGlorb.height(wild_kind()) * 0.55 + 3.2


func _build_body() -> void:
	CrawlerGlorb.mount(self, wild_kind())
	_line = EnergyVfx.make(EnergyVfx.Kind.BEAM_STREAMS, EnergyVfx.TINT_PURPLE)
	_line.name = "VesperBeam"
	_line.visible = false
	_line.top_level = true
	add_child(_line)


func _tick_idle(delta: float) -> void:
	if _maybe_glorb_inbound(delta):
		return
	super._tick_idle(delta)


func _tick_ai(delta: float) -> void:
	if _maybe_glorb_inbound(delta):
		return
	super._tick_ai(delta)


func _tick_far(delta: float) -> void:
	if _maybe_glorb_inbound(delta):
		return
	super._tick_far(delta)


func director_far_steer(delta: float, player: Node3D, in_city := false) -> void:
	if _maybe_glorb_inbound(maxf(delta, 0.0)):
		if flies():
			_director_climb()
		return
	super.director_far_steer(delta, player, in_city)


func _clip_aliases(clip: String) -> PackedStringArray:
	if clip == CLIP_FLY or clip == CLIP_WALK or clip == CLIP_RUN:
		return PackedStringArray([CLIP_FLY, "Fly", CLIP_RUN, "Hover", clip])
	return super._clip_aliases(clip)


func _glorb_travel_clip(clip: String) -> String:
	if clip != CLIP_IDLE and clip != CLIP_WALK and clip != CLIP_RUN \
			and clip != CLIP_FLY:
		return clip
	return CLIP_FLY
