extends SceneTree

## Broad purple field with red splotches for the Fool's Teleport Cape.
##
##     godot --headless --path . -s assets/source/paint_fool_cape.gd

const DEST := "res://assets/runtime/apparel/cape_fool_paint.png"
const SIZE := 256
const PURPLE := Color(0.36, 0.12, 0.54, 1.0)
const PURPLE_DEEP := Color(0.22, 0.06, 0.38, 1.0)
const RED := Color(0.86, 0.14, 0.18, 1.0)
const SPLOTCHES := [
	Vector4(0.72, 0.38, 0.20, 1.00),
	Vector4(0.28, 0.62, 0.13, 0.86),
	Vector4(0.18, 0.22, 0.10, 0.78),
	Vector4(0.54, 0.18, 0.09, 0.72),
	Vector4(0.46, 0.78, 0.11, 0.70),
	Vector4(0.82, 0.74, 0.08, 0.64),
	Vector4(0.38, 0.42, 0.07, 0.58),
]


func _init() -> void:
	var image := Image.create(SIZE, SIZE, false, Image.FORMAT_RGBA8)
	for y in SIZE:
		for x in SIZE:
			var u := float(x) / float(SIZE - 1)
			var v := float(y) / float(SIZE - 1)
			var cloud := 0.5 + 0.5 * sin(u * 6.2 + v * 4.1) * cos(v * 5.3 - u * 2.4)
			var colour := PURPLE.lerp(PURPLE_DEEP, clampf(cloud, 0.0, 1.0))
			for blob: Vector4 in SPLOTCHES:
				var fall := _splotch(u - blob.x, v - blob.y, blob.z)
				colour = colour.lerp(RED, clampf(fall * blob.w, 0.0, 1.0))
			image.set_pixel(x, y, colour)
	var path := ProjectSettings.globalize_path(DEST)
	DirAccess.make_dir_recursive_absolute(path.get_base_dir())
	var err := image.save_png(path)
	if err != OK:
		push_error("paint_fool_cape: could not write %s" % path)
	else:
		print("paint_fool_cape: wrote %s %dx%d" % [DEST, SIZE, SIZE])
	quit()


func _splotch(dx: float, dy: float, radius: float) -> float:
	var d := sqrt(dx * dx + dy * dy)
	if d >= radius:
		return 0.0
	var t := 1.0 - d / radius
	return t * t * (3.0 - 2.0 * t)
