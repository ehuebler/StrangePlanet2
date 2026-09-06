extends Node

## Where each body's face is, so [member CharacterDB.eye_offset] can be measured
## rather than estimated.
##
##     godot --headless --path . dev/_eye_probe.tscn
##
## Run this when a new character is added. It prints the Head bone's rest frame,
## the front of the head sliced by height, and — for a body that has them — where
## the goggles sit, which is the eye line stated by the art rather than guessed
## at. It then reads the catalogue's current offset back against those, and says
## how far off the face it lands.
##
## It exists because the beams were leaving the back of the neck. The offsets
## were authored along the Head bone's own axes, and the two bodies' Head bones
## are turned half a circle from one another, so one of the two was always going
## to be backwards.

const WORLD := preload("res://game/world.tscn")


func _ready() -> void:
	multiplayer.multiplayer_peer = OfflineMultiplayerPeer.new()
	NetworkManager.is_single_player = true
	NetworkManager.is_host = true
	NetworkManager.players[1] = {"name": "Player", "peer_id": 1}
	NetworkManager.state = NetworkManager.SessionState.IN_GAME
	var world := WORLD.instantiate() as GameWorld
	add_child(world)
	for _frame in 30:
		await get_tree().process_frame
	var player := get_tree().get_first_node_in_group("network_players") \
		as OnlinePlayer
	if player == null:
		push_error("eye_probe: no player")
		get_tree().quit(1)
		return

	var skeleton := Wardrobe.skeleton_of(player.character)
	if skeleton == null:
		push_error("eye_probe: no skeleton")
		get_tree().quit(1)
		return
	var bone := CharacterRig.find_bone(skeleton, &"Head")
	print("eye_probe: body=%s bone=%d of %d" % [
		player._body_id, bone, skeleton.get_bone_count()])

	var rest := skeleton.get_bone_global_rest(bone)
	var pose := skeleton.get_bone_global_pose(bone)
	print("eye_probe: rest origin  %s" % rest.origin)
	print("eye_probe: rest x %s" % rest.basis.x)
	print("eye_probe: rest y %s" % rest.basis.y)
	print("eye_probe: rest z %s" % rest.basis.z)
	print("eye_probe: pose origin  %s" % pose.origin)

	# Which way the body faces, in the same space the bone rest is given in.
	var to_skeleton := skeleton.global_transform.affine_inverse()
	var body_ahead := to_skeleton.basis * (-player.global_basis.z)
	var body_up := to_skeleton.basis * player.global_basis.y
	print("eye_probe: body ahead in skeleton space %s" % body_ahead)
	print("eye_probe: body up    in skeleton space %s" % body_up)
	print("eye_probe: bone z . ahead = %.3f, bone y . up = %.3f, bone x . ahead = %.3f"
		% [rest.basis.z.normalized().dot(body_ahead),
			rest.basis.y.normalized().dot(body_up),
			rest.basis.x.normalized().dot(body_ahead)])

	# Where the eyes come out today, measured against the face rather than
	# described: how far ahead of the body's centre line, and how far up.
	var eyes := player.eye_points()
	var middle: Vector3 = (eyes[0] + eyes[1]) * 0.5
	var local := player.global_transform.affine_inverse() * middle
	print("eye_probe: eye midpoint in body space %s" % local)
	print("eye_probe: ahead %.3f m, up %.3f m, apart %.3f m" % [
		-local.z, local.y, eyes[0].distance_to(eyes[1])])

	# The face itself, which is what "on the eyes" has to be measured against.
	# The whole-mesh box is no use for this: it is as deep as the shoulders and
	# as wide as a T-pose. What matters is the front of the head, so the head's
	# own vertices are picked out by height and asked where they end.
	var mesh := _head_mesh(skeleton)
	if mesh == null:
		get_tree().quit()
		return
	var box := mesh.get_aabb()
	print("eye_probe: whole mesh aabb %s size %s" % [box.position, box.size])
	_measure_head(mesh, rest.origin.y, box.position.y + box.size.y)
	# Goggles are worn on the eyes, so where they sit is the eye line measured
	# rather than eyeballed — which is the whole difficulty with a stylised face
	# that has no eye bones to ask.
	await _measure_goggles(player)

	# Every body, not only the one that happens to be loaded. The offset is
	# per-character data and the same mistake is in all of it.
	for id: String in CharacterDB.BODIES:
		_measure_body(id)
	get_tree().quit()


## The same measurements against a character scene on its own, so a body nobody
## is currently wearing still gets checked.
func _measure_body(id: String) -> void:
	var path := String(CharacterDB.BODIES[id].get("scene", ""))
	if not ResourceLoader.exists(path):
		print("eye_probe: %s has no scene at %s" % [id, path])
		return
	var scene := (load(path) as PackedScene).instantiate()
	add_child(scene)
	var skeleton: Skeleton3D = null
	for node in scene.find_children("*", "Skeleton3D", true, false):
		skeleton = node as Skeleton3D
		break
	if skeleton == null:
		print("eye_probe: %s has no skeleton" % id)
		scene.queue_free()
		return
	var bone := CharacterRig.find_bone(skeleton, &"Head")
	var rest := skeleton.get_bone_global_rest(bone)
	var mesh := _head_mesh(skeleton)
	print("eye_probe: --- %s, head bone at %s" % [id, rest.origin])
	if mesh != null:
		var box := mesh.get_aabb()
		_measure_head(mesh, rest.origin.y, box.position.y + box.size.y)
	# What the catalogue currently asks for, in the same space as the numbers
	# above, so the two can simply be read against each other.
	var offset := CharacterDB.eye_offset(id)
	var eye := rest.origin + offset
	print("eye_probe: %s offset puts an eye at %s" % [id, eye])
	if mesh != null:
		print("eye_probe: %s face at that height is z %.4f, so the eye is %.3f m %s it"
			% [id, _face_at(mesh, eye.y), absf(eye.z - _face_at(mesh, eye.y)),
				"ahead of" if eye.z < _face_at(mesh, eye.y) else "behind"])
	scene.queue_free()


## The front of the head at one height, which is what an eye has to be level
## with. A centimetre either side of the height, so a single vertex ring cannot
## decide it.
func _face_at(mesh: MeshInstance3D, height: float) -> float:
	var front := INF
	for surface in mesh.mesh.get_surface_count():
		var arrays := mesh.mesh.surface_get_arrays(surface)
		for point: Vector3 in (arrays[Mesh.ARRAY_VERTEX] as PackedVector3Array):
			if absf(point.y - height) > 0.01 or absf(point.x) > 0.06:
				continue
			front = minf(front, point.z)
	return front


func _measure_goggles(player: OnlinePlayer) -> void:
	if player.equipment.size() > 0:
		player.equipment.set_item(0, "c3_hair")
	for _frame in 20:
		await get_tree().process_frame
	var worn_names := PackedStringArray()
	for worn in player.character.find_children("*", "MeshInstance3D", true, false):
		worn_names.append(worn.name)
	print("eye_probe: worn meshes %s" % ", ".join(worn_names))
	for worn in player.character.find_children("*", "MeshInstance3D", true, false):
		var piece := worn as MeshInstance3D
		if not piece.name.to_lower().contains("goggle"):
			continue
		var box := piece.get_aabb()
		var at := player.character.global_transform.affine_inverse() \
			* piece.global_transform
		var middle := at * (box.position + box.size * 0.5)
		print("eye_probe: goggles %s centre %s size %s front z %.4f" % [
			piece.name, middle, box.size,
			(at * (box.position + Vector3(box.size.x * 0.5, box.size.y * 0.5,
				0.0))).z])


## The front, top and sides of everything above the neck joint, sliced by height
## so the shape of the head can be read off rather than guessed at.
func _measure_head(mesh: MeshInstance3D, base: float, top: float) -> void:
	var points := PackedVector3Array()
	for surface in mesh.mesh.get_surface_count():
		var arrays := mesh.mesh.surface_get_arrays(surface)
		for point: Vector3 in (arrays[Mesh.ARRAY_VERTEX] as PackedVector3Array):
			if point.y >= base:
				points.append(point)
	if points.is_empty():
		print("eye_probe: no vertices above the neck")
		return
	print("eye_probe: %d vertices above y=%.3f, head is %.3f m tall"
		% [points.size(), base, top - base])
	# In bands, because a face is not a box: the brow is further forward than
	# the chin and the eyes sit between them.
	for band in 6:
		var low := base + (top - base) * float(band) / 6.0
		var high := base + (top - base) * float(band + 1) / 6.0
		var front := INF
		var wide := 0.0
		var found := 0
		for point in points:
			if point.y < low or point.y >= high:
				continue
			found += 1
			front = minf(front, point.z)
			wide = maxf(wide, absf(point.x))
		if found == 0:
			continue
		print("eye_probe:   y %.3f-%.3f  front z %.4f  half-width %.4f  (%d)"
			% [low, high, front, wide, found])


func _head_mesh(skeleton: Skeleton3D) -> MeshInstance3D:
	for child in skeleton.get_children():
		if child is MeshInstance3D:
			return child as MeshInstance3D
	return null
