class_name CrawlerTreeFruit
extends CrawlerRammer

## Phase-two fruit: a shiny red, blue, or orange rammer that keeps its wings.

const TINTS: Array[Color] = [
	Color(0.96, 0.10, 0.08),
	Color(0.14, 0.32, 0.96),
	Color(0.98, 0.46, 0.06),
]

var fruit_tint := Color(0.96, 0.10, 0.08)


func configure_fruit(tint: Color) -> void:
	fruit_tint = tint


func _ready() -> void:
	persistent = true
	chase = true
	ever_chased = true
	super._ready()


func _build_body() -> void:
	var shape := CollisionShape3D.new()
	var ball := SphereShape3D.new()
	ball.radius = RADIUS
	shape.shape = ball
	add_child(shape)
	_attach_creature(
		MODEL, PAINT, AUTHORED_HEIGHT, RADIUS * 2.0, fruit_tint)
	var creature := get_node_or_null("Creature")
	if creature != null:
		for node_variant: Variant in creature.find_children("*", "MeshInstance3D", true, false):
			var mesh := node_variant as MeshInstance3D
			if mesh == null:
				continue
			if mesh.name.to_lower().contains("wing"):
				mesh.material_override = _enemy_material(
					Color(0.18, 0.05, 0.06), PAINT, 1.0)
				continue
			var material := mesh.material_override as ShaderMaterial
			if material != null:
				material.set_shader_parameter(&"emit_color", fruit_tint)
				material.set_shader_parameter(&"emit_energy", 2.6)


func wild_kind() -> String:
	return "fruit"


func combat_display_name() -> String:
	return "Fruit"


func is_boss_minion() -> bool:
	return true
