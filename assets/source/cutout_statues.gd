extends SceneTree

## Punches the pale studio backdrop out of the statue stills.
##
##     godot --headless --path . -s assets/source/cutout_statues.gd

const SRC := "C:/Users/ellio/Desktop/office/output/statues-20260906"
const DEST := "res://assets/runtime/crawler/statues"
const NAMES := [
	"wings.png", "health.png", "strength.png", "misc.png", "wealth.png",
]


func _init() -> void:
	var dest_dir := ProjectSettings.globalize_path(DEST)
	DirAccess.make_dir_recursive_absolute(dest_dir)
	for file_name: String in NAMES:
		var loaded := Image.new()
		var err := loaded.load("%s/%s" % [SRC, file_name])
		if err != OK:
			push_error("cutout_statues: could not read %s" % file_name)
			continue
		var cut := _cutout(loaded)
		var dest := "%s/%s" % [dest_dir, file_name]
		err = cut.save_png(dest)
		if err != OK:
			push_error("cutout_statues: could not write %s" % dest)
			continue
		print("cutout_statues: wrote %s %dx%d" % [file_name, cut.get_width(), cut.get_height()])
	quit()


func _cutout(source: Image) -> Image:
	var image := source.duplicate() as Image
	image.convert(Image.FORMAT_RGBA8)
	var width := image.get_width()
	var height := image.get_height()
	var key := _corner_key(image)
	var marked := PackedByteArray()
	marked.resize(width * height)
	var queue: Array[Vector2i] = []
	for x in width:
		_try_enqueue(image, key, marked, queue, x, 0)
		_try_enqueue(image, key, marked, queue, x, height - 1)
	for y in height:
		_try_enqueue(image, key, marked, queue, 0, y)
		_try_enqueue(image, key, marked, queue, width - 1, y)
	var cursor := 0
	while cursor < queue.size():
		var at: Vector2i = queue[cursor]
		cursor += 1
		_try_enqueue(image, key, marked, queue, at.x - 1, at.y)
		_try_enqueue(image, key, marked, queue, at.x + 1, at.y)
		_try_enqueue(image, key, marked, queue, at.x, at.y - 1)
		_try_enqueue(image, key, marked, queue, at.x, at.y + 1)
	for y in height:
		for x in width:
			if marked[y * width + x] == 0:
				continue
			var colour := image.get_pixel(x, y)
			colour.a = 0.0
			image.set_pixel(x, y, colour)
	_soften(image, marked)
	return image


func _corner_key(image: Image) -> Color:
	var width := image.get_width()
	var height := image.get_height()
	var samples: Array[Color] = []
	for y in range(0, 10):
		for x in range(0, 10):
			samples.append(image.get_pixel(x, y))
			samples.append(image.get_pixel(width - 1 - x, y))
			samples.append(image.get_pixel(x, height - 1 - y))
			samples.append(image.get_pixel(width - 1 - x, height - 1 - y))
	var acc := Color(0, 0, 0, 0)
	for sample: Color in samples:
		acc += sample
	return acc / float(samples.size())


func _try_enqueue(
		image: Image,
		key: Color,
		marked: PackedByteArray,
		queue: Array[Vector2i],
		x: int,
		y: int
	) -> void:
	if x < 0 or y < 0 or x >= image.get_width() or y >= image.get_height():
		return
	var index := y * image.get_width() + x
	if marked[index] != 0:
		return
	if not _is_backdrop(image.get_pixel(x, y), key):
		return
	marked[index] = 1
	queue.append(Vector2i(x, y))


func _is_backdrop(colour: Color, key: Color) -> bool:
	if colour.s > 0.16:
		return false
	var fade := Vector3(colour.r, colour.g, colour.b).distance_to(
		Vector3(key.r, key.g, key.b))
	if fade <= 0.10:
		return true
	return colour.v >= 0.86 and colour.s <= 0.07 and fade <= 0.18


func _soften(image: Image, marked: PackedByteArray) -> void:
	var width := image.get_width()
	var height := image.get_height()
	for y in height:
		for x in width:
			var index := y * width + x
			if marked[index] != 0:
				continue
			var near := 0
			for oy in range(-1, 2):
				for ox in range(-1, 2):
					var nx := x + ox
					var ny := y + oy
					if nx < 0 or ny < 0 or nx >= width or ny >= height:
						continue
					if marked[ny * width + nx] != 0:
						near += 1
			if near <= 0:
				continue
			var colour := image.get_pixel(x, y)
			colour.a = clampf(colour.a * (1.0 - float(near) / 9.0), 0.0, 1.0)
			image.set_pixel(x, y, colour)
