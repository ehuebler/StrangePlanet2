class_name CrawlerSproutling
extends Node3D

## One friendly village meep. Wanderers walk the roads and sometimes
## stand still. Shop and hidden folk stay put.

enum Role {
	WANDER,
	SHOP,
	HIDDEN,
}

const MODEL_DIR := "res://assets/runtime/characters/sproutlings/"
const VARIANTS := ["Luma", "Mochi", "Ember", "Cosmo", "Sunny"]
const WALK_NEEDLE := "Walk_Basic"
const WALK_SPEED := 1.12
const ARRIVE := 0.55

var role: Role = Role.WANDER
var variant := "Luma"
var display_name := ""

var _animator: AnimationPlayer
var _walk_clip := ""
var _waypoints: PackedVector3Array = PackedVector3Array()
var _goal := Vector3.ZERO
var _idle_left := 0.0
var _walking := false
var _rng := RandomNumberGenerator.new()


func configure(
		kind: String,
		job: Role,
		seed: int,
		title := "",
		path: PackedVector3Array = PackedVector3Array()
	) -> void:
	variant = kind if VARIANTS.has(kind) else VARIANTS[0]
	role = job
	display_name = title
	_waypoints = path
	_rng.seed = maxi(seed, 1)
	name = _node_name()
	set_meta(&"sproutling_role", _role_id())
	set_meta(&"sproutling_variant", variant)
	set_meta(&"sproutling_name", display_name)
	_mount_model()
	if not display_name.is_empty():
		_mount_name()
	if role == Role.WANDER:
		_idle_left = _rng.randf_range(0.4, 2.8)
		set_process(true)
	else:
		set_process(false)
		_play_walk(false)


func rest_now() -> void:
	_walking = false
	_idle_left = maxf(_idle_left, 1.0)
	_play_walk(false)


func face_local(dir: Vector3) -> void:
	var planar := Vector3(dir.x, 0.0, dir.z)
	if planar.length_squared() < 0.0001:
		return
	planar = planar.normalized()
	rotation.y = atan2(planar.x, planar.z)


func _process(delta: float) -> void:
	if role != Role.WANDER:
		return
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
	var step := minf(WALK_SPEED * delta, span)
	position += delta_xz / span * step
	position.y = 0.0
	face_local(delta_xz)
	_play_walk(true)


func _arrive() -> void:
	_walking = false
	_idle_left = _rng.randf_range(1.6, 5.5)
	_play_walk(false)


func _pick_goal() -> void:
	if _waypoints.is_empty():
		_idle_left = 4.0
		return
	if _rng.randf() < 0.34:
		_idle_left = _rng.randf_range(2.2, 6.0)
		_play_walk(false)
		return
	var here := Vector3(position.x, 0.0, position.z)
	var best := _waypoints[_rng.randi_range(0, _waypoints.size() - 1)]
	var best_gap := INF
	for index in mini(5, _waypoints.size()):
		var candidate := _waypoints[_rng.randi_range(0, _waypoints.size() - 1)]
		var gap := Vector2(candidate.x - here.x, candidate.z - here.z).length()
		if gap < 1.2:
			continue
		if gap < best_gap:
			best_gap = gap
			best = candidate
	_goal = Vector3(
		best.x + _rng.randf_range(-0.55, 0.55),
		0.0,
		best.z + _rng.randf_range(-0.55, 0.55)
	)
	_walking = true
	_play_walk(true)


func _mount_model() -> void:
	var path := "%s%s.glb" % [MODEL_DIR, variant]
	if not ResourceLoader.exists(path):
		push_warning("CrawlerSproutling: missing %s" % path)
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
	_walk_clip = _resolve_walk()
	if _animator != null and not _walk_clip.is_empty():
		var anim := _animator.get_animation(_walk_clip)
		if anim != null:
			anim.loop_mode = Animation.LOOP_LINEAR
		_animator.playback_default_blend_time = 0.12
	_play_walk(false)


func _mount_name() -> void:
	var tag := Label3D.new()
	tag.name = "SproutlingName"
	tag.text = display_name.to_upper()
	tag.position = Vector3(0.0, 1.42, 0.0)
	tag.pixel_size = 0.0065
	tag.font_size = 26
	tag.outline_size = 8
	tag.modulate = Color("f4f0ff")
	tag.outline_modulate = Color(0.04, 0.03, 0.08, 0.92)
	tag.billboard = BaseMaterial3D.BILLBOARD_ENABLED
	tag.no_depth_test = false
	add_child(tag)


func _play_walk(on: bool) -> void:
	if _animator == null or _walk_clip.is_empty():
		return
	if on:
		if _animator.current_animation != _walk_clip:
			_animator.play(_walk_clip)
		return
	_animator.stop()
	_animator.seek(0.0, true)


func _resolve_walk() -> String:
	if _animator == null:
		return ""
	for listed in _animator.get_animation_list():
		if listed.ends_with(WALK_NEEDLE) or listed.contains(WALK_NEEDLE):
			return listed
	return ""


func _role_id() -> String:
	match role:
		Role.SHOP:
			return "shop"
		Role.HIDDEN:
			return "hidden"
	return "wander"


func _node_name() -> String:
	if not display_name.is_empty():
		return "Sproutling_%s" % display_name
	return "Sproutling_%s" % variant
