extends Node

## A gatling bolt must not crash if its gunner dies during the arm delay.
##
##     godot --headless --path . dev/_robot_laser_muzzle_test.tscn

var _failures := 0


func _ready() -> void:
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
	print("robot_laser_muzzle_test: %s" % (
		"all checks passed" if _failures == 0 else "%d check(s) failed" % _failures))
	get_tree().quit(1 if _failures > 0 else 0)


func _expect(ok: bool, label: String) -> void:
	if ok:
		return
	_failures += 1
	push_error("robot_laser_muzzle_test failed: %s" % label)
