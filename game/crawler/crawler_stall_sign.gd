class_name CrawlerStallSign
extends Sprite3D

## Shop glyph that floats over an open stall and turns in place.

const SPIN := 1.15


func _ready() -> void:
	billboard = BaseMaterial3D.BILLBOARD_DISABLED
	pixel_size = 0.06
	shaded = false
	double_sided = true
	centered = true
	no_depth_test = false
	set_process(true)


func _process(delta: float) -> void:
	rotate_y(delta * SPIN)
