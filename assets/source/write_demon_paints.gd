extends SceneTree

## Deterministic 256² color-paints for Gloam, Vesper, and Threnody.
##
##     godot --headless --path . -s assets/source/write_demon_paints.gd

const SIZE := 256
const DEST := {
	"gloam": "res://assets/runtime/biomes/paint/gloam_paint.png",
	"vesper": "res://assets/runtime/biomes/paint/vesper_paint.png",
	"threnody": "res://assets/runtime/biomes/paint/threnody_paint.png",
}


func _init() -> void:
	_write("gloam", Color(0.18, 0.06, 0.07), Color(0.08, 0.04, 0.05),
		Color(0.62, 0.16, 0.10), 0.0)
	_write("vesper", Color(0.12, 0.05, 0.18), Color(0.06, 0.03, 0.10),
		Color(0.46, 0.28, 0.72), 1.2)
	_write("threnody", Color(0.10, 0.04, 0.16), Color(0.04, 0.02, 0.08),
		Color(0.72, 0.28, 0.95), 2.4)
	quit()


func _write(kind: String, base: Color, deep: Color, mark: Color, twist: float) -> void:
	var image := Image.create(SIZE, SIZE, false, Image.FORMAT_RGBA8)
	for y in SIZE:
		for x in SIZE:
			var u := float(x) / float(SIZE - 1)
			var v := float(y) / float(SIZE - 1)
			var band := 0.5 + 0.5 * sin((v * 7.0 + u * twist) * TAU)
			var rib := 0.5 + 0.5 * sin((u * 5.0 - v * 1.4 + twist) * TAU)
			var blot := 0.5 + 0.5 * sin(u * 9.2 + v * 6.1 + twist)
			var colour := base.lerp(deep, clampf(band * 0.65 + blot * 0.35, 0.0, 1.0))
			var mark_w := clampf(pow(rib, 2.2) * 0.55, 0.0, 0.55)
			colour = colour.lerp(mark, mark_w)
			image.set_pixel(x, y, colour)
	var path := ProjectSettings.globalize_path(String(DEST[kind]))
	DirAccess.make_dir_recursive_absolute(path.get_base_dir())
	var err := image.save_png(path)
	if err != OK:
		push_error("write_demon_paints: could not write %s" % path)
	else:
		print("write_demon_paints: wrote %s %dx%d" % [DEST[kind], SIZE, SIZE])
