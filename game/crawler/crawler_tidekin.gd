class_name CrawlerTidekin
extends Node3D

## One friendly Tidekin shrimp. Walks an office floor on authored clips,
## then idles. Not a combatant.

const MODEL_DIR := "res://assets/runtime/crawler/tidekin/"
const VARIANTS: PackedStringArray = ["PIP", "BRACK", "SERA"]
const WALK_SPEED := {
	"PIP": 0.72,
	"BRACK": 0.82,
	"SERA": 0.74,
}
const ARRIVE := 0.7
const FACE_YAW := PI

var variant := "PIP"
var _animator: AnimationPlayer
var _walk_clip := ""
var _idle_clip := ""
var _waypoints: PackedVector3Array = PackedVector3Array()
var _goal := Vector3.ZERO
var _floor_y := 1.0
var _idle_left := 0.0
var _walking := false
var _rng := RandomNumberGenerator.new()


func configure(
		kind: String,
		seed: int,
		path: PackedVector3Array = PackedVector3Array(),
		floor_y := 1.0
	) -> void:
	variant = kind if VARIANTS.has(kind) else VARIANTS[0]
	_waypoints = path
	_floor_y = floor_y
	_rng.seed = maxi(seed, 1)
	name = "Tidekin_%s" % variant
	set_meta(&"tidekin_variant", variant)
	set_meta(&"tidekin_friendly", true)
	_mount_model()
	_idle_left = _rng.randf_range(0.3, 2.4)
	set_process(true)


func _process(delta: float) -> void:
	if _walking:
		_step(delta)
		return
	_idle_left -= delta
	if _idle_left <= 0.0:
		_pick_goal()


func _step(delta: float) -> void:
	var delta_xz := _goal - position
	delta_xz.y = 0.0
	var span := delta_xz.length()
	if span <= ARRIVE:
		_arrive()
		return
	var step := minf(_speed() * delta, span)
	position += delta_xz / span * step
	position.y = _floor_y
	_face(delta_xz)
	_play(true)


func _arrive() -> void:
	_walking = false
	_idle_left = _rng.randf_range(1.8, 5.8)
	_play(false)


func _pick_goal() -> void:
	if _waypoints.is_empty():
		_idle_left = 4.0
		_play(false)
		return
	if _rng.randf() < 0.28:
		_idle_left = _rng.randf_range(2.0, 6.2)
		_play(false)
		return
	var here := Vector3(position.x, 0.0, position.z)
	var best := _waypoints[_rng.randi_range(0, _waypoints.size() - 1)]
	var best_gap := INF
	for _try in mini(6, _waypoints.size()):
		var candidate := _waypoints[_rng.randi_range(0, _waypoints.size() - 1)]
		var gap := Vector2(candidate.x - here.x, candidate.z - here.z).length()
		if gap < 1.6:
			continue
		if gap < best_gap:
			best_gap = gap
			best = candidate
	_goal = Vector3(
		best.x + _rng.randf_range(-0.8, 0.8),
		_floor_y,
		best.z + _rng.randf_range(-0.8, 0.8)
	)
	_walking = true
	_play(true)


func _mount_model() -> void:
	var path := "%s%s.glb" % [MODEL_DIR, variant]
	if not ResourceLoader.exists(path):
		push_warning("CrawlerTidekin: missing %s" % path)
		return
	var packed := load(path) as PackedScene
	if packed == null:
		return
	var model := packed.instantiate() as Node3D
	if model == null:
		return
	model.name = "Model"
	add_child(model)
	_animator = model.find_child("AnimationPlayer", true, false) as AnimationPlayer
	_walk_clip = _resolve_clip("Walk")
	_idle_clip = _resolve_clip("Idle")
	if _animator != null:
		_loop(_walk_clip)
		_loop(_idle_clip)
		_animator.playback_default_blend_time = 0.14
	_play(false)


func _play(walk: bool) -> void:
	if _animator == null:
		return
	var clip := _walk_clip if walk else _idle_clip
	if clip.is_empty():
		return
	if _animator.current_animation != clip:
		_animator.play(clip)


func _loop(clip: String) -> void:
	if _animator == null or clip.is_empty():
		return
	var anim := _animator.get_animation(clip)
	if anim != null:
		anim.loop_mode = Animation.LOOP_LINEAR


func _resolve_clip(needle: String) -> String:
	if _animator == null:
		return ""
	var folded := needle.to_lower()
	var variant_key := variant.to_lower()
	var fallback := ""
	for listed: String in _animator.get_animation_list():
		var clip_name := listed
		var low := clip_name.to_lower()
		if not low.contains(folded):
			continue
		if low.contains(variant_key):
			return clip_name
		if fallback.is_empty():
			fallback = clip_name
	return fallback


func _face(dir: Vector3) -> void:
	var planar := Vector3(dir.x, 0.0, dir.z)
	if planar.length_squared() < 0.0001:
		return
	planar = planar.normalized()
	rotation.y = atan2(planar.x, planar.z) + FACE_YAW


func _speed() -> float:
	return float(WALK_SPEED.get(variant, 0.74))
