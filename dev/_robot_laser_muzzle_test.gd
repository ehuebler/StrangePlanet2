extends Node

## A gatling bolt must not crash if its gunner dies during the arm delay,
## and it must re-aim from the live muzzle when the delay ends.
##
##     godot --headless --path . dev/_robot_laser_muzzle_test.tscn

var _failures := 0


class FakeGunner extends Node3D:
	var muzzle := Vector3.ZERO

	func muzzle_point() -> Vector3:
		return muzzle


func _ready() -> void:
	_check_dead_gunner()
	_check_reaim_after_muzzle_climb()
	print("robot_laser_muzzle_test: %s" % (
		"all checks passed" if _failures == 0 else "%d check(s) failed" % _failures))
	get_tree().quit(1 if _failures > 0 else 0)


func _check_dead_gunner() -> void:
	var dummy := Node3D.new()
	dummy.name = "DeadGunner"
	add_child(dummy)
	var bolt := CrawlerRobotLaser.new()
	bolt.arm_delay = 0.2
	_expect(bolt.launch_anywhere(
			self, Vector3(0.0, 2.0, 0.0), Vector3.FORWARD, dummy),
		"a delayed laser can leave a dummy muzzle")
	dummy.free()
	bolt._physics_process(0.016)
	_expect(is_instance_valid(bolt),
		"a delayed laser survives after its gunner is freed")
	if is_instance_valid(bolt):
		bolt.queue_free()


func _check_reaim_after_muzzle_climb() -> void:
	var gunner := FakeGunner.new()
	gunner.name = "Kestrel"
	gunner.muzzle = Vector3(0.0, 8.0, 0.0)
	add_child(gunner)
	var prey := Node3D.new()
	prey.name = "StillPlayer"
	add_child(prey)
	prey.global_position = Vector3(0.0, 1.0, 16.0)
	var bolt := CrawlerRobotLaser.new()
	bolt.arm_delay = 0.2
	bolt.shot_speed = 50.0
	bolt.prey = prey
	# Windup heading is level. After Fire_Burst lifts the gun, that line
	# passes over a still player.
	_expect(bolt.launch_anywhere(
			self, gunner.muzzle, Vector3(0.0, 0.0, 1.0), gunner),
		"a delayed laser accepts a stale windup heading")
	gunner.muzzle = Vector3(0.0, 12.0, 0.0)
	bolt._physics_process(0.21)
	var along := bolt._velocity.normalized()
	var wanted := (prey.global_position - gunner.muzzle).normalized()
	_expect(along.dot(wanted) > 0.98,
		"gatling re-aims from the live muzzle instead of flying the windup heading")
	_expect(along.y < -0.2,
		"the re-aimed bolt drops toward a still player instead of passing over")
	bolt.queue_free()
	gunner.queue_free()
	prey.queue_free()


func _expect(ok: bool, label: String) -> void:
	if ok:
		return
	_failures += 1
	push_error("robot_laser_muzzle_test failed: %s" % label)
