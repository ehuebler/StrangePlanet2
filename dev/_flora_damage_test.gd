extends Node

## Checks that flora has health, that ability damage spends it, and that the
## sweep queries reach the plants nothing else can.
##
##     godot --headless --path . dev/_flora_damage_test.tscn
##
## Two halves. The first is arithmetic and loads only resources: every species
## resource is checked for a sane, derived break speed, and the toughness table
## is checked to be doing what it claims. The second needs real plants, because
## the thing most worth proving cannot be proved without them — grass, shrubs
## and most cover have **no colliders at all**, so nothing but these queries can
## find them, and a test built on a stand-in field would be a test of the
## stand-in. So it opens the world, waits for the ground and the flora to
## stream, and burns a hole in an actual lawn.

const WORLD := preload("res://game/world.tscn")
const SPECIES_DIRS := ["res://game/props/", "res://game/props/biomes/"]

## Frames to let the planet build. The same wait the player harness uses; the
## flora only streams once there are chunks under it.
const TERRAIN_FRAMES := 130

## Metres around the player that count as "here" when tallying what is still
## standing. Wider than anything the test fires, so a plant that is merely out
## of range is not mistaken for one that has been destroyed.
## Half-length and radius of the sweep. Broad, because the landing site is a
## sparse desert and a hairline beam through it would be testing the biome
## rather than the query.
const SWEEP_LENGTH := 20.0
const SWEEP_RADIUS := 8.0
const BLAST_RADIUS := 34.0

## Ground the regrow check winds back — wider than anything the test destroyed —
## and how long the streamer is given to sow it again.
const REGROW_RADIUS := 94.0
const REGROW_FRAMES := 200
## Above the undergrowth and below every authored tree. Matches what the boss
## tramples with; the point of the check is that the two agree.
const CANOPY_CAP := 4.0

var _failures := 0
var _planet: Planet


func _ready() -> void:
	_check_species_resources()
	_check_toughness()
	_check_damage_geometry()

	multiplayer.multiplayer_peer = OfflineMultiplayerPeer.new()
	NetworkManager.is_single_player = true
	NetworkManager.is_host = true
	NetworkManager.players[1] = {"name": "Player", "peer_id": 1}
	NetworkManager.state = NetworkManager.SessionState.IN_GAME
	var world := WORLD.instantiate()
	add_child(world)
	await _wait(10)
	_planet = world.find_child("Planet", true, false) as Planet
	var site := world.find_child("LandingSite", true, false) as Node3D
	var player := get_tree().get_first_node_in_group("network_players") \
		as OnlinePlayer
	if _planet == null or site == null or player == null:
		push_error("flora_damage_test: planet=%s site=%s player=%s" % [
			_planet, site, player])
		get_tree().quit(1)
		return
	# Flora streams around whatever is looking at it, and a player spawns in
	# orbit. Nothing grows within kilometres of the camera until the body is put
	# on the ground.
	player.global_transform = site.global_transform
	player.velocity = Vector3.ZERO
	await _wait(TERRAIN_FRAMES)

	_check_fields_registered()
	# Aimed at a plant that is actually there rather than at the player, who is
	# standing on a cleared landing pad. Which biome the site sits in is not
	# something this test should depend on.
	var target := _a_standing_plant()
	if target == Vector3.INF:
		_expect(false, "found a streamed plant to aim at")
	else:
		_check_cover_damage(player, target, _planet.up_at(target))
	_check_break_keys()
	if target != Vector3.INF:
		await _check_regrow(target)
		# On the ground that just grew back, which is also what proves it did.
		_check_capped_damage(target)

	print("flora_damage_test: %s" % (
		"all checks passed" if _failures == 0 else "%d check(s) failed" % _failures))
	get_tree().quit(1 if _failures > 0 else 0)


## Every authored species, checked for the one thing the migration could have
## broken: a break speed that is still derived from health and still lands
## somewhere a body could plausibly reach.
func _check_species_resources() -> void:
	var seen := 0
	var buried_rocks := 0
	var sink_math_holds := true
	for path in _species_paths():
		var plant := load(path) as PlantSpecies
		if plant == null:
			continue
		seen += 1
		var name := path.get_file()
		if not _expect(plant.health > 0.0, "%s has health" % name):
			continue
		# The derivation itself. If these two ever stop agreeing, a species can
		# be tuned to shrug off a sprint and then fall to a glancing beam, which
		# is exactly what deriving one from the other was for.
		var tall := plant.height
		var expected := plant.health_for(tall) \
			/ PlantSpecies.HEALTH_PER_BREAK_SPEED \
			* PlantSpecies.BREAK_THRESHOLD_SCALE
		_expect(is_equal_approx(plant.impact_threshold(tall), expected),
			"%s derives its break speed from its health" % name)
		# A species a walk flattens is an authoring mistake. A species nothing
		# can run through is not: the landmark formations are scenery and are
		# authored unbreakable outright. What must not happen is a species that
		# is *nominally* breakable and yet needs a speed no body can reach,
		# because that is indestructible by accident rather than on purpose.
		var speed := plant.impact_threshold(tall)
		_expect(speed > 0.5,
			"%s is not flattened by a walk (%.1f m/s)" % [name, speed])
		_expect(speed < 100.0 or not plant.takes_ability_damage(),
			"%s is only unbreakable if it says so (%.0f m/s)" % [name, speed])
		_expect(plant.health_for(2.0) > plant.health_for(0.0)
			or is_zero_approx(plant.health_per_metre),
			"%s is tougher when it is bigger, or says it is not" % name)
		if plant.ground_sink_share > 0.0:
			buried_rocks += 1
			var large := plant.ground_sink_above + 1.0
			sink_math_holds = sink_math_holds \
				and is_zero_approx(plant.ground_sink_for(plant.ground_sink_above)) \
				and is_equal_approx(plant.ground_sink_for(large),
					large * plant.ground_sink_share)
	_expect(seen >= 40, "the whole species catalogue was read (%d)" % seen)
	_expect(buried_rocks >= 10, "all rock species opt into scaled burial (%d)" % buried_rocks)
	_expect(sink_math_holds, "rock burial begins above the player and scales with height")


func _check_toughness() -> void:
	var soft := PlantSpecies.new()
	soft.toughness = PlantSpecies.Toughness.SOFT
	var stone := PlantSpecies.new()
	stone.toughness = PlantSpecies.Toughness.STONE
	_expect(is_equal_approx(soft.damage_taken(100.0), 100.0),
		"soft flora takes a beam at full value")
	_expect(stone.damage_taken(100.0) < soft.damage_taken(100.0) * 0.25,
		"stone shrugs most of it off")
	var unbreakable := PlantSpecies.new()
	unbreakable.impact_mode = PlantSpecies.ImpactMode.UNBREAKABLE
	_expect(is_zero_approx(unbreakable.damage_taken(1000.0)),
		"unbreakable flora takes nothing")
	_expect(not unbreakable.takes_ability_damage(),
		"and says so before it is asked")


## The shape maths, which is what decides whether a plant is in a hit at all.
func _check_damage_geometry() -> void:
	var beam := DamageHit.beam(Vector3.ZERO, Vector3(10.0, 0.0, 0.0), 1.0, 50.0)
	_expect(is_equal_approx(beam.damage_at(Vector3(5.0, 0.0, 0.0)), 50.0),
		"a beam damages the middle of its length, not only its end")
	_expect(is_zero_approx(beam.damage_at(Vector3(5.0, 3.0, 0.0))),
		"and nothing outside its radius")
	_expect(is_equal_approx(beam.damage_at(Vector3(10.0, 0.0, 0.0)), 50.0),
		"a flat beam is as strong at the end as anywhere")

	var burst := DamageHit.area(Vector3.ZERO, 10.0, 100.0, 1.0)
	_expect(is_equal_approx(burst.damage_at(Vector3.ZERO), 100.0),
		"an area hit is full strength at its centre")
	_expect(burst.damage_at(Vector3(9.0, 0.0, 0.0)) < 20.0,
		"and has almost dissipated at its edge")
	_expect(is_zero_approx(burst.damage_at(Vector3(11.0, 0.0, 0.0))),
		"and nothing beyond it")

	var wire := DamageHit.from_wire(beam.to_wire())
	_expect(is_equal_approx(wire.damage_at(Vector3(5.0, 0.0, 0.0)), 50.0)
		and wire.kind == beam.kind,
		"a hit survives the round trip to the wire")


func _check_fields_registered() -> void:
	var fields := get_tree().get_nodes_in_group(DamageHit.FIELD_GROUP)
	_expect(fields.size() > 0,
		"flora fields joined the damage group (%d)" % fields.size())
	var covers := 0
	for field in fields:
		_expect(field.has_method(&"apply_damage"),
			"%s answers apply_damage" % field.name)
		if field is GroundCover:
			covers += 1
	_expect(covers > 0, "and some of them are ground cover")


## The part that needs real plants: a volume placed over live ground has to find
## the instances nothing else can, and take them down.
func _check_cover_damage(player: OnlinePlayer, at: Vector3, up: Vector3) -> void:
	var before := _standing_total()
	_expect(before > 0, "there is streamed cover to damage (%d)" % before)
	if before == 0:
		return
	# A beam first, drawn along the ground rather than aimed at a point on it,
	# because damaging along its length is the half of the requirement a point
	# hit would not prove. Enormous on purpose: this is a check that the query
	# reaches the plants, not a check of the balance. Applied through Laser
	# Eyes so a cheaper landing ray still leaves the same cut.
	var across := _across(up)
	var from := at + up - across * SWEEP_LENGTH
	var toward := at + up + across * SWEEP_LENGTH
	LaserEyes.apply_effect(
		player, "laser_eyes", from, from, toward, true,
		SWEEP_RADIUS, 1.0, 0.0, true)
	# One authored tick may only char a rock. The follow-up is the same
	# corridor at a dose that will fell whatever is actually standing there.
	var beam := DamageHit.beam(from, toward, SWEEP_RADIUS, 100000.0)
	beam.plant_break_effects = false
	var cut := _apply_everywhere(beam)
	var after_beam := _standing_total()
	_expect(cut > 0.0 or after_beam < before,
		"a beam along the ground cut something (%.0f, %d of %d)" % [
			cut, before - after_beam, before])
	_expect(after_beam < before,
		"plants with no colliders fell to it (%d of %d)" % [
			before - after_beam, before])
	var past := LaserEyes._surface(player, at + up * 3.0, at - up * 4.0)
	if not past.is_empty():
		_expect(not LaserEyes._is_flora(past),
			"the landing ray passes through flora colliders")

	var blast := DamageHit.area(at, BLAST_RADIUS, 100000.0, 0.0)
	var absorbed := _apply_everywhere(blast)
	var after := _standing_total()
	_expect(absorbed > 0.0, "a blast absorbed as well (%.0f)" % absorbed)
	_expect(after < after_beam,
		"and cleared what the beam missed (%d left of %d)" % [after, before])
	# A second identical blast must find almost nothing left to spend itself on,
	# which is what says the damage was recorded and not merely drawn.
	var again := _apply_everywhere(blast)
	_expect(again < absorbed * 0.05,
		"a second blast over the same ground finds almost nothing standing")


## Winding a patch of ground back to how it grew.
##
## Damage is permanent for the rest of the session everywhere else — that is the
## whole point of the ledger surviving streaming — so this is the one path that
## undoes it, for an encounter that resets the ground it was fought over.
func _check_regrow(at: Vector3) -> void:
	var world := _planet.get_parent() as GameWorld
	if world == null:
		return
	var broken := _broken_total()
	var flattened := _standing_total()
	_expect(broken > 0, "there is destruction to undo (%d keys)" % broken)
	var restored := world.regrow_flora(at, REGROW_RADIUS)
	_expect(restored > 0,
		"the regrow reports what it stood back up (%d)" % restored)
	_expect(_broken_total() == 0,
		"and the world no longer calls anything there broken")
	_expect(_pending_break_total() == 0,
		"and no pre-reset break is still queued to knock restored flora down again")
	# The plants themselves come back through the streamer, on its own clock.
	await _wait(REGROW_FRAMES)
	var standing := _standing_total()
	_expect(standing > flattened,
		"the cover grew back where it was cut (%d, was %d)" % [
			standing, flattened])


## A volume that spares the canopy. This cap is the only thing keeping something
## that flattens its way around an arena from levelling the trees it lives under,
## and a plain reduction in damage would not do it: the ledger accumulates, so
## anything left standing on one pass falls on the twentieth.
func _check_capped_damage(at: Vector3) -> void:
	for field in get_tree().get_nodes_in_group(DamageHit.FIELD_GROUP):
		field.call(&"drain_new_breaks")
	var blast := DamageHit.area(at, BLAST_RADIUS, 100000.0, 0.0)
	blast.max_plant_height = CANOPY_CAP
	_apply_everywhere(blast)
	var short_broken := 0
	var tall_broken := 0
	for field in get_tree().get_nodes_in_group(DamageHit.FIELD_GROUP):
		var keys: PackedInt32Array = field.call(&"drain_new_breaks")
		if keys.is_empty():
			continue
		var cover := field as GroundCover
		if cover == null:
			# A tree colony's keys are tree indices, and every tree in one
			# stands well above the cap.
			tall_broken += keys.size()
			continue
		var entry := 3
		while entry < keys.size():
			var plant := cover.species[keys[entry]] as PlantSpecies
			if plant != null and plant.height > CANOPY_CAP:
				tall_broken += 1
			else:
				short_broken += 1
			entry += 5
	_expect(short_broken > 0,
		"a capped volume still flattens undergrowth (%d)" % short_broken)
	_expect(tall_broken == 0,
		"and leaves everything above the cap standing (%d felled)" % tall_broken)


## Plants every field currently calls broken.
func _broken_total() -> int:
	var keys := 0
	for field in get_tree().get_nodes_in_group(DamageHit.FIELD_GROUP):
		keys += (field.call(&"broken_keys") as PackedInt32Array).size()
	return keys


func _pending_break_total() -> int:
	var keys := 0
	for field in get_tree().get_nodes_in_group(DamageHit.FIELD_GROUP):
		keys += (field.call(&"drain_new_breaks") as PackedInt32Array).size()
	return keys


func _apply_everywhere(hit: DamageHit) -> float:
	var absorbed := 0.0
	for field in get_tree().get_nodes_in_group(DamageHit.FIELD_GROUP):
		absorbed += float(field.call(&"apply_damage", hit))
	return absorbed


## Everything still standing anywhere, across every damageable field.
##
## A total rather than a tally around the hit, because a field owns its own
## streaming and there is no promise here about which species grows where. Only
## the plants inside the volume can fall, so a total that drops is a total that
## dropped where the volume was.
## Cover only, and deliberately. A [FlowerTreeField] places its trees with
## `set_instance_transform`, and reading a MultiMesh's buffer back after that
## does not return what was written — the same trap [GroundCover] documents on
## its own buffer. Trees are checked through the break keys instead.
func _standing_total() -> int:
	var alive := 0
	for field in get_tree().get_nodes_in_group(DamageHit.FIELD_GROUP):
		if not (field is GroundCover):
			continue
		# Internal children, not `find_children`, which does not return them. A
		# cover field puts every one of its stands in internally so a few
		# hundred of them stay out of the Scene dock, and a walk that skips them
		# counts none of the grass on the planet.
		for stand in _stands_under(field):
			alive += _standing(stand)
	return alive


## Where one live cover instance is, in the world, or [constant Vector3.INF].
func _a_standing_plant() -> Vector3:
	for field in get_tree().get_nodes_in_group(DamageHit.FIELD_GROUP):
		if not (field is GroundCover):
			continue
		for stand in _stands_under(field):
			var showing := stand.multimesh.visible_instance_count
			if showing < 0:
				showing = stand.multimesh.instance_count
			var buffer := stand.multimesh.buffer
			for index in showing:
				var at := index * 12
				if (at + 11) >= buffer.size():
					break
				if Vector3(buffer[at], buffer[at + 4],
						buffer[at + 8]).length() <= 0.001:
					continue
				return stand.global_transform * Vector3(
					buffer[at + 3], buffer[at + 7], buffer[at + 11])
	return Vector3.INF


func _stands_under(node: Node) -> Array[MultiMeshInstance3D]:
	var found: Array[MultiMeshInstance3D] = []
	for child in node.get_children(true):
		var stand := child as MultiMeshInstance3D
		if stand != null and stand.visible and stand.multimesh != null:
			found.append(stand)
		found.append_array(_stands_under(child))
	return found


## Any direction along the ground, for pointing a beam somewhere other than
## straight down.
func _across(up: Vector3) -> Vector3:
	var side := up.cross(Vector3.UP if absf(up.normalized().y) < 0.9
		else Vector3.RIGHT)
	return side.normalized() if side.length_squared() > 0.000001 \
		else Vector3.RIGHT


func _check_break_keys() -> void:
	var world := _planet.get_parent() as GameWorld
	if world == null:
		_expect(false, "the planet is under a GameWorld")
		return
	var snapshot := world.flora_snapshot()
	_expect(not snapshot.is_empty(),
		"the destruction shows up in the join snapshot")
	var total := 0
	for path: String in snapshot:
		var keys: PackedInt32Array = snapshot[path]
		_expect(world.get_node_or_null(NodePath(path)) != null,
			"the snapshot's path resolves (%s)" % path)
		total += keys.size()
	_expect(total > 0, "and it lists broken plants (%d integers)" % total)
	# Applying a snapshot to a field that already has it must be a no-op rather
	# than an error, because that is what a peer does when it rejoins.
	world.apply_flora_snapshot(snapshot)
	_expect(world.flora_snapshot().size() == snapshot.size(),
		"re-applying a snapshot changes nothing")


## Instances of one stand that are still there.
##
## A destroyed instance is scaled to nothing rather than removed, so the count
## of instances never changes and the basis length is what has to be read.
func _standing(stand: MultiMeshInstance3D) -> int:
	var showing := stand.multimesh.visible_instance_count
	if showing < 0:
		showing = stand.multimesh.instance_count
	var alive := 0
	var buffer := stand.multimesh.buffer
	for index in showing:
		var at := index * 12
		if (at + 11) >= buffer.size():
			break
		if Vector3(buffer[at], buffer[at + 4], buffer[at + 8]).length() > 0.001:
			alive += 1
	return alive


func _species_paths() -> PackedStringArray:
	var paths := PackedStringArray()
	for directory: String in SPECIES_DIRS:
		for file in DirAccess.get_files_at(directory):
			if file.ends_with(".tres"):
				paths.append(directory + file)
	return paths


func _wait(frames: int) -> void:
	for _index in frames:
		await get_tree().process_frame


func _expect(condition: bool, message: String) -> bool:
	if condition:
		print("flora_damage_test: PASS  %s" % message)
		return true
	_failures += 1
	push_error("flora_damage_test: FAIL  %s" % message)
	return false
