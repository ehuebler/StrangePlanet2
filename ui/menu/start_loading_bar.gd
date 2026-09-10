class_name StartLoadingBar
extends Control

## Thin red trough with a green fill. Sits over the still home-screen world
## while the run is chosen. Crawler shaders and terrain finish in-game.

const RED := Color("ef151f")
const GREEN := Color("45df68")
const TROUGH := Color(0.08, 0.02, 0.03, 0.82)

var share := 0.0:
	set(value):
		share = clampf(value, 0.0, 1.0)
		queue_redraw()


func _ready() -> void:
	name = "StartLoadingBar"
	mouse_filter = Control.MOUSE_FILTER_IGNORE
	custom_minimum_size = Vector2(248.0, 10.0)


func _draw() -> void:
	var box := Rect2(Vector2.ZERO, size)
	draw_rect(box, TROUGH, true)
	if share > 0.0:
		var fill := Rect2(
			Vector2(2.0, 2.0),
			Vector2((size.x - 4.0) * share, size.y - 4.0))
		draw_rect(fill, GREEN, true)
	draw_rect(box, RED, false, 2.0)
