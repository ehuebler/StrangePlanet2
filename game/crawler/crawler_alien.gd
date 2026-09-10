class_name CrawlerAlien
extends CrawlerMob

## Shared authored visitor body. Unique hunt still lives in each kind's
## `_tick_ai`.

const MODELS := preload("res://game/crawler/crawler_alien_models.gd")
const CLIP_AIM := "Aim_Fire"
const CLIP_BITE := "Bite"
const CLIP_CRAWL := "Crawl"
const CLIP_SCUTTLE := "Scuttle"
const CLIP_DOWNED := "Downed"
const WALK_SPEED := 1.4
const RUN_SPEED := 5.2
const BODY_SCALE := 1.35
const INK := Color(0.47, 0.53, 0.51)

var _muzzle: Node3D
var _fire_left := 0.0
var _act := ""


func _ready() -> void:
	_faces_motion = true
	_uses_model_front = true
	super._ready()
	motion_mode = MOTION_MODE_FLOATING


func _build_body() -> void:
	var shape := CollisionShape3D.new()
	var capsule := CapsuleShape3D.new()
	capsule.radius = body_width() * 0.48
	capsule.height = maxf(body_height() * 0.72, capsule.radius * 2.0 + 0.05)
	shape.shape = capsule
	add_child(shape)
	var packed := MODELS.scene(wild_kind())
	if packed != null:
		_attach_skinned(packed, body_height())
		var model := find_child("Creature", true, false)
		if model != null:
			var bone := muzzle_bone()
			if not bone.is_empty():
				_muzzle = MODELS.bind_socket(model, bone)
	else:
		_build_fallback()


func body_height() -> float:
	return 1.8 * BODY_SCALE


func body_width() -> float:
	return 0.7 * BODY_SCALE


func muzzle_bone() -> String:
	return ""


func combat_display_name() -> String:
	return CrawlerMobs.title(wild_kind(), maxi(threat_level, 1))


func combat_position() -> Vector3:
	if _hit_ready:
		return super.combat_position()
	return global_position + _up() * (body_height() * 0.22)


func combat_radius() -> float:
	if _hit_ready:
		return super.combat_radius()
	return body_width() * 0.55


func ground_clearance() -> float:
	return body_height() * 0.5


func muzzle_point() -> Vector3:
	if _muzzle is Node3D:
		return _muzzle.global_position
	return combat_position() + global_transform.basis.z * (body_width() * 0.7)


func _flat_toward(at: Vector3) -> Vector3:
	var up := _up()
	var along := at - global_position
	along -= up * along.dot(up)
	return along


func _reach_of(player: Node, extra := 0.0) -> float:
	var reach := extra
	if player != null and player.has_method(&"combat_radius"):
		reach += float(player.call(&"combat_radius"))
	return reach


func _melee(player: Node, reach: float, ability: String) -> DamageHit:
	var hit := DamageHit.impact(combat_position(), reach, damage())
	hit.faction = outgoing_faction()
	hit.ability_id = ability
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
	return hit


func _desired_clip() -> String:
	if not _alive:
		return CLIP_DOWNED if _resolve_clip(CLIP_DOWNED) != "" else CLIP_HIT
	if not _act.is_empty() and _attack_left > 0.0:
		return _act
	if _attack_left > 0.0:
		return CLIP_ATTACK
	if _flash_left > 0.04:
		return CLIP_HIT
	if flies():
		return CLIP_FLY if velocity.length() > 1.4 else CLIP_IDLE
	var speed := velocity.length()
	if speed >= RUN_SPEED:
		return CLIP_RUN
	if speed >= WALK_SPEED:
		return CLIP_WALK
	return CLIP_IDLE


func _clip_aliases(clip: String) -> PackedStringArray:
	match clip:
		CLIP_ATTACK:
			return PackedStringArray([
				CLIP_AIM, CLIP_BITE, "Tentacle_Lash", CLIP_ATTACK, "Strike"])
		CLIP_HIT:
			return PackedStringArray(["Hit_React", CLIP_HIT, "Hit"])
		CLIP_DOWNED:
			return PackedStringArray([CLIP_DOWNED, "Hit_React", CLIP_HIT])
		CLIP_WALK:
			return PackedStringArray([CLIP_CRAWL, CLIP_WALK])
		CLIP_RUN:
			return PackedStringArray([CLIP_SCUTTLE, CLIP_RUN])
		CLIP_AIM:
			return PackedStringArray([CLIP_AIM])
		CLIP_BITE:
			return PackedStringArray([CLIP_BITE])
	return super._clip_aliases(clip)


func _build_fallback() -> void:
	var mesh := CapsuleMesh.new()
	mesh.radius = body_width() * 0.38
	mesh.height = body_height() * 0.86
	var visual := MeshInstance3D.new()
	visual.mesh = mesh
	visual.material_override = _enemy_material(INK, null, 0.0)
	visual.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	add_child(visual)
	_visual = visual
