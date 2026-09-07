class_name CrawlerGoblin
extends CrawlerMob

## Grounded castle garrison. Cheap: the director keeps far bodies cold,
## skip the all-mob charm scan, and charge or hold without flyer logic.

const CLIP_SWING := "Swing"
const WALK_SPEED := 2.2
const RUN_SPEED := 6.0
const SWING_SECONDS := 0.42
const HEIGHT := 1.75
const WIDTH := 0.62
const INK := Color(0.22, 0.34, 0.16)


var _swing_left := 0.0
var _staff: Node3D
var _authored_mats: Array[StandardMaterial3D] = []
var _authored_energy: Array[float] = []


func _ready() -> void:
	persistent = true
	_faces_motion = true
	super._ready()
	motion_mode = MOTION_MODE_FLOATING


func _build_body() -> void:
	var shape := CollisionShape3D.new()
	var capsule := CapsuleShape3D.new()
	capsule.radius = body_width() * 0.48
	capsule.height = maxf(body_height() * 0.72, capsule.radius * 2.0 + 0.05)
	shape.shape = capsule
	add_child(shape)
	var packed := CrawlerGoblinModels.scene(wild_kind())
	if packed != null:
		_attach_authored(packed, body_height())
	else:
		_build_fallback(body_ink())


func body_height() -> float:
	return HEIGHT


func body_width() -> float:
	return WIDTH


func body_ink() -> Color:
	return INK


func flies() -> bool:
	return false


func is_persistent() -> bool:
	return true


func combat_display_name() -> String:
	return CrawlerMobs.title(wild_kind(), maxi(threat_level, 1))


func combat_position() -> Vector3:
	return global_position + _up() * (body_height() * 0.22)


func combat_radius() -> float:
	return body_width() * 0.55


func swing_reach() -> float:
	return body_width() + 1.35


func _hunt_target(delta: float) -> Node3D:
	if is_charmed():
		return super._hunt_target(delta)
	var player := _nearest_player()
	if player == null or not tick_agro(player, delta):
		return null
	return player


func _tick_ai(delta: float) -> void:
	_swing_left = maxf(_swing_left - delta, 0.0)
	_stick_to_ground()
	if _attacking():
		velocity = velocity.move_toward(Vector3.ZERO, 28.0 * delta)
		return
	var player := _hunt_target(delta)
	if player == null:
		velocity = velocity.move_toward(Vector3.ZERO, 16.0 * delta)
		return
	_charge_melee(player, delta)


func _charge_melee(player: Node, delta: float) -> void:
	var at := _combat_position_of(player)
	var along := _flat_toward(at)
	var gap := along.length()
	var reach := swing_reach()
	if player.has_method(&"combat_radius"):
		reach += float(player.call(&"combat_radius"))
	_match_speed(move_speed(), delta, 0.7, 8.0)
	if along.length_squared() > 0.0001:
		_steer_toward(along.normalized() * _cruise, delta, 12.0)
	if gap <= reach and _swing_left <= 0.0:
		_swing(player)


func _swing(player: Node) -> void:
	if not _begin_attack(SWING_SECONDS):
		return
	_swing_left = maxf(fire_scale(), 0.55)
	var reach := swing_reach() + 0.45
	var hit := DamageHit.impact(combat_position(), reach, damage())
	hit.faction = outgoing_faction()
	hit.ability_id = "crawler_%s_swing" % wild_kind()
	hit.affects_flora = false
	hit.affects_combatants = true
	hit.set_source(self)
	if not is_charmed() and player != null \
			and player.has_method(&"combat_peer_id"):
		hit.target_peer = int(player.call(&"combat_peer_id"))
	if DamageHit.game_world_of(self) != null:
		DamageHit.apply_to_combatants(self, hit)
	elif player != null and player.has_method(&"apply_damage"):
		player.call(&"apply_damage", hit)


func staff_tip() -> Vector3:
	if _staff is MeshInstance3D:
		var mesh := _staff as MeshInstance3D
		var box := mesh.get_aabb()
		var local := Vector3(
			box.get_center().x,
			box.position.y + box.size.y,
			box.get_center().z)
		return mesh.to_global(local)
	if _staff is Node3D:
		return _staff.global_position + _up() * 0.08
	return global_position + _up() * (body_height() * 0.92) \
		- global_transform.basis.z * (body_width() * 0.55)


func _stick_to_ground() -> void:
	if _planet == null:
		return
	var local := _planet.to_local(global_position)
	if local.length_squared() < 0.0001:
		local = Vector3.UP
	var surface := _planet.surface_position(local)
	var up := _planet.up_at(surface)
	global_position = surface + up * (body_height() * 0.5)
	velocity -= up * velocity.dot(up)


func _flat_toward(at: Vector3) -> Vector3:
	var up := _up()
	var along := at - global_position
	along -= up * along.dot(up)
	return along


func _desired_clip() -> String:
	if not _alive:
		return CLIP_HIT
	if _attack_left > 0.0:
		return CLIP_ATTACK
	if _flash_left > 0.04:
		return CLIP_HIT
	var speed := velocity.length()
	if speed >= RUN_SPEED:
		return CLIP_RUN
	if speed >= WALK_SPEED:
		return CLIP_WALK
	return CLIP_IDLE


func _resolve_clip(clip: String) -> String:
	if _animator == null or clip.is_empty():
		return ""
	if _clip_names.has(clip):
		return str(_clip_names[clip])
	var resolved := ""
	for alias: String in _clip_aliases(clip):
		var hit := _match_clip(alias)
		if not hit.is_empty():
			resolved = hit
			break
	_clip_names[clip] = resolved
	return resolved


func _clip_aliases(clip: String) -> PackedStringArray:
	match clip:
		CLIP_ATTACK:
			return PackedStringArray([CLIP_SWING, "swing", CLIP_ATTACK, "attack"])
		CLIP_WALK:
			return PackedStringArray([CLIP_WALK, "walk", "Walking", "walking"])
		CLIP_RUN:
			return PackedStringArray([CLIP_RUN, "run", "Running", "running"])
		CLIP_IDLE:
			return PackedStringArray([CLIP_IDLE, "idle", CLIP_WALK, "walk"])
		CLIP_HIT:
			return PackedStringArray([CLIP_HIT, "Hit", "hit", CLIP_IDLE, CLIP_WALK])
	return PackedStringArray([clip])


func _match_clip(clip: String) -> String:
	if _animator.has_animation(clip):
		return clip
	var need := clip.to_lower()
	for listed: String in _animator.get_animation_list():
		var tail := listed.get_file().to_lower()
		if tail == need or tail.ends_with("/" + need) or tail.ends_with("|" + need):
			return listed
	return ""


func _bind_animator(model: Node) -> void:
	super._bind_animator(model)
	if _animator == null:
		return
	for clip: String in [CLIP_IDLE, CLIP_WALK, CLIP_RUN]:
		var resolved := _resolve_clip(clip)
		if not resolved.is_empty() and _animator.has_animation(resolved):
			_animator.get_animation(resolved).loop_mode = Animation.LOOP_LINEAR


func _attach_authored(scene: PackedScene, visual_height: float) -> void:
	var root := Node3D.new()
	root.name = "Creature"
	add_child(root)
	var model := scene.instantiate()
	root.add_child(model)
	var authored := _model_height(model)
	var scale := visual_height / maxf(authored, 0.01)
	root.scale = Vector3.ONE * scale
	root.position.y = -visual_height * 0.5
	_collect_authored_materials(model)
	_bind_animator(model)
	_cache_staff(model)


func _model_height(model: Node) -> float:
	var bounds := AABB()
	var started := false
	for node_variant: Variant in model.find_children("*", "MeshInstance3D", true, false):
		var mesh := node_variant as MeshInstance3D
		if mesh == null:
			continue
		var box := mesh.transform * mesh.get_aabb()
		if started:
			bounds = bounds.merge(box)
		else:
			bounds = box
			started = true
	if not started or bounds.size.y <= 0.05:
		return 1.8
	return bounds.size.y


func _collect_authored_materials(model: Node) -> void:
	for node_variant: Variant in model.find_children("*", "MeshInstance3D", true, false):
		var mesh := node_variant as MeshInstance3D
		if mesh == null:
			continue
		mesh.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
		if _visual == null:
			_visual = mesh
		var material := mesh.get_active_material(0)
		if material is StandardMaterial3D:
			var copy := (material as StandardMaterial3D).duplicate() as StandardMaterial3D
			mesh.material_override = copy
			_authored_mats.append(copy)
			_authored_energy.append(copy.emission_energy_multiplier)
		elif material is ShaderMaterial:
			var shader_copy := (material as ShaderMaterial).duplicate() as ShaderMaterial
			mesh.material_override = shader_copy
			_materials.append(shader_copy)
			_material = shader_copy


func _cache_staff(model: Node) -> void:
	for node_variant: Variant in model.find_children("*", "MeshInstance3D", true, false):
		var mesh := node_variant as MeshInstance3D
		if mesh == null:
			continue
		var folded := mesh.name.to_lower()
		if folded.contains("staff") or folded.contains("wand") or folded.contains("stick"):
			_staff = mesh
			return
	for node_variant: Variant in model.find_children("*", "Node3D", true, false):
		var node := node_variant as Node3D
		if node == null:
			continue
		var folded := node.name.to_lower()
		if folded.contains("staff") or folded.contains("wand"):
			_staff = node
			return
	var hand_name := ""
	var staff_name := ""
	var skeleton: Skeleton3D
	for node_variant: Variant in model.find_children("*", "Skeleton3D", true, false):
		skeleton = node_variant as Skeleton3D
		if skeleton == null:
			continue
		for bone in skeleton.get_bone_count():
			var name := skeleton.get_bone_name(bone)
			var folded := name.to_lower()
			if staff_name.is_empty() and (folded.contains("staff")
					or folded.contains("wand") or folded.contains("weapon")):
				staff_name = name
			if hand_name.is_empty() and (folded.contains("righthand")
					or folded.contains("hand_r") or folded.ends_with("right_hand")):
				hand_name = name
		if not staff_name.is_empty() or not hand_name.is_empty():
			break
	if skeleton == null:
		return
	var attach := BoneAttachment3D.new()
	attach.bone_name = staff_name if not staff_name.is_empty() else hand_name
	if attach.bone_name.is_empty():
		return
	skeleton.add_child(attach)
	var tip := Marker3D.new()
	tip.position = Vector3(0.0, 0.48 if staff_name.is_empty() else 0.36, 0.0)
	attach.add_child(tip)
	_staff = tip


func _build_fallback(colour: Color) -> void:
	var mesh := CapsuleMesh.new()
	mesh.radius = body_width() * 0.38
	mesh.height = body_height() * 0.86
	_make_mesh(mesh, colour, 1.1)
	if _visual != null:
		_visual.position.y = 0.0


func _update_flash() -> void:
	super._update_flash()
	var flash := 0.0
	if _flash_left > 0.0:
		flash = clampf(_flash_left / DAMAGE_FLASH_SECONDS, 0.0, 1.0)
	for index in _authored_mats.size():
		var material := _authored_mats[index]
		if material == null:
			continue
		var rest := _authored_energy[index] if index < _authored_energy.size() else 0.0
		material.emission_enabled = flash > 0.04 or rest > 0.02
		material.emission = Color(1.0, 0.28, 0.18) if flash > 0.04 \
			else material.emission
		material.emission_energy_multiplier = lerpf(rest, 3.4, flash)
