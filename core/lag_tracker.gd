extends Node

## Rolling 30-second performance log. Lives as an autoload so a hitch can be
## named and exported after the fact from the admin tab.

const WINDOW_SEC := 30.0
const CAPACITY := 7200
const MAX_EVENTS := 480
const MAX_HITCHES := 16
const HITCH_MS := 50.0
const HITCH_MULT := 2.6
const HITCH_GAP_SEC := 0.35
const EXPORT_DIR := "user://lag_exports"

const CHANNELS: Array[Dictionary] = [
	{"id": "frame", "label": "Frame ms", "color": Color("ff6188")},
	{"id": "process", "label": "Process ms", "color": Color("6fdcf2")},
	{"id": "physics", "label": "Physics ms", "color": Color("b3a5f7")},
	{"id": "draw", "label": "Draw calls", "color": Color("45df68")},
	{"id": "prims", "label": "Prims k", "color": Color("e6c14a")},
	{"id": "nodes", "label": "Nodes", "color": Color("8ff3a5")},
	{"id": "vram", "label": "VRAM MB", "color": Color("ff8d98")},
	{"id": "objects", "label": "Objects", "color": Color("e6eaff")},
	{"id": "terrain", "label": "Terrain ms", "color": Color("f2a65a")},
	{"id": "flora", "label": "Flora ms", "color": Color("6fdc9a")},
	{"id": "pipes", "label": "Shader compiles", "color": Color("c9a0ff")},
]

signal hitch_recorded(index: int)
signal changed

var _frozen := false
var _head := 0
var _count := 0
var _times := PackedFloat64Array()
var _values: Dictionary = {}
var _gauges: Dictionary = {}
var _events: Array[Dictionary] = []
var _hitches: Array[Dictionary] = []
var _frame_hist := PackedFloat32Array()
var _last_hitch_at := -1000.0
var _last_objects := -1
var _last_draw := -1.0
var _last_prims := -1.0
var _last_nodes := -1.0
var _last_vram := -1.0
var _last_mem := -1.0
var _last_bodies := -1
var _throttle: Dictionary = {}


func _init() -> void:
	name = "LagTracker"
	process_mode = Node.PROCESS_MODE_ALWAYS
	_times.resize(CAPACITY)
	for channel in CHANNELS:
		var series := PackedFloat32Array()
		series.resize(CAPACITY)
		_values[String(channel["id"])] = series
	_frame_hist.resize(90)
	_frame_hist.fill(16.6)


func _ready() -> void:
	note("boot", "lag tracker started")


func _process(_delta: float) -> void:
	if _frozen:
		return
	_sample()


func set_frozen(on: bool) -> void:
	if _frozen == on:
		return
	_frozen = on
	note("ui", "sampling %s" % ("paused" if on else "resumed"))
	changed.emit()


func is_frozen() -> bool:
	return _frozen


func note(channel: String, message: String, extra: Dictionary = {}) -> void:
	var row := {
		"t": _now(),
		"channel": channel,
		"message": message,
		"extra": extra,
	}
	_events.append(row)
	if _events.size() > MAX_EVENTS:
		_events = _events.slice(_events.size() - MAX_EVENTS)
	changed.emit()


func note_throttled(channel: String, key: String, message: String,
		gap := 0.45, extra: Dictionary = {}) -> bool:
	var now := _now()
	if now - float(_throttle.get(key, -1000.0)) < gap:
		return false
	_throttle[key] = now
	note(channel, message, extra)
	return true


func set_gauge(id: String, value: float) -> void:
	_gauges[id] = value


func channels() -> Array[Dictionary]:
	return CHANNELS


func events_in_window(from_t: float = -1.0, to_t: float = -1.0) -> Array[Dictionary]:
	var lo := from_t
	var hi := to_t
	if lo < 0.0 or hi < 0.0:
		var span := window_span()
		lo = span.x
		hi = span.y
	var out: Array[Dictionary] = []
	for row in _events:
		var at := float(row.get("t", 0.0))
		if at >= lo and at <= hi + 0.05:
			out.append(row)
	return out


func hitches() -> Array[Dictionary]:
	return _hitches


func window_span() -> Vector2:
	if _count <= 0:
		var now := _now()
		return Vector2(now, now)
	return Vector2(_time_at(0), _time_at(_count - 1))


func sample_count() -> int:
	return _count


func series(id: String) -> PackedFloat32Array:
	var out := PackedFloat32Array()
	if not _values.has(id) or _count <= 0:
		return out
	out.resize(_count)
	var src: PackedFloat32Array = _values[id]
	for i in _count:
		out[i] = src[_index(i)]
	return out


func times() -> PackedFloat64Array:
	var out := PackedFloat64Array()
	out.resize(_count)
	for i in _count:
		out[i] = _time_at(i)
	return out


func latest(id: String) -> float:
	if _count <= 0 or not _values.has(id):
		return 0.0
	var src: PackedFloat32Array = _values[id]
	return src[_index(_count - 1)]


func frame_summary() -> Dictionary:
	return _summarize(series("frame"))


func snapshot(from_t: float = -1.0, to_t: float = -1.0) -> Dictionary:
	var span := window_span()
	var lo := span.x if from_t < 0.0 else from_t
	var hi := span.y if to_t < 0.0 else to_t
	var channels := {}
	var stamps := times()
	for channel in CHANNELS:
		var id := String(channel["id"])
		var src := series(id)
		var pts: Array = []
		for i in src.size():
			var t := stamps[i]
			if t >= lo and t <= hi:
				pts.append([snappedf(t, 0.001), snappedf(src[i], 0.01)])
		channels[id] = {
			"label": String(channel["label"]),
			"samples": pts,
		}
	return {
		"from": lo,
		"to": hi,
		"duration": hi - lo,
		"summary": _summarize(series("frame")),
		"channels": channels,
		"events": events_in_window(lo, hi),
	}


func export_named(title: String, hitch_index := -1) -> String:
	var snap: Dictionary
	var kind := "window"
	if hitch_index >= 0 and hitch_index < _hitches.size():
		snap = (_hitches[hitch_index] as Dictionary).get("snapshot", {})
		kind = "hitch"
	else:
		snap = snapshot()
	var clean := _safe_name(title)
	if clean.is_empty():
		clean = kind
	var stamp := Time.get_datetime_string_from_system(true, true).replace(":", "").replace(" ", "_")
	var dir := ProjectSettings.globalize_path(EXPORT_DIR)
	DirAccess.make_dir_recursive_absolute(dir)
	var path := dir.path_join("lag_%s_%s.json" % [stamp, clean])
	var payload := {
		"name": title.strip_edges(),
		"kind": kind,
		"exported_at": Time.get_datetime_string_from_system(true, true),
		"window_sec": WINDOW_SEC,
		"snapshot": snap,
	}
	var file := FileAccess.open(path, FileAccess.WRITE)
	if file == null:
		note("export", "failed to write %s" % path)
		return ""
	file.store_string(JSON.stringify(payload, "\t"))
	note("export", "wrote %s" % path.get_file())
	return path


func open_export_folder() -> void:
	var dir := ProjectSettings.globalize_path(EXPORT_DIR)
	DirAccess.make_dir_recursive_absolute(dir)
	OS.shell_show_in_file_manager(dir, false)


func export_dir() -> String:
	return ProjectSettings.globalize_path(EXPORT_DIR)


func _sample() -> void:
	var now := _now()
	var frame_ms := float(Performance.get_monitor(Performance.TIME_PROCESS)) * 1000.0
	if frame_ms <= 0.001:
		frame_ms = (1.0 / maxf(Engine.get_frames_per_second(), 1.0)) * 1000.0
	_write("frame", now, frame_ms)
	_write("process", now, float(Performance.get_monitor(Performance.TIME_PROCESS)) * 1000.0)
	_write("physics", now, float(Performance.get_monitor(Performance.TIME_PHYSICS_PROCESS)) * 1000.0)
	_write("draw", now, float(Performance.get_monitor(Performance.RENDER_TOTAL_DRAW_CALLS_IN_FRAME)))
	_write("prims", now, float(Performance.get_monitor(Performance.RENDER_TOTAL_PRIMITIVES_IN_FRAME)) / 1000.0)
	_write("nodes", now, float(Performance.get_monitor(Performance.OBJECT_NODE_COUNT)))
	_write("vram", now, float(Performance.get_monitor(Performance.RENDER_VIDEO_MEM_USED)) / 1048576.0)
	_write("objects", now, float(Performance.get_monitor(Performance.OBJECT_COUNT)))
	_write("terrain", now, float(_gauges.get("terrain", 0.0)))
	_write("flora", now, float(_gauges.get("flora", 0.0)))
	_write("pipes", now, _pipeline_compiles())
	_count = mini(_count + 1, CAPACITY)
	_head = (_head + 1) % CAPACITY
	_drop_old(now)
	_watch_jumps()
	_watch_hitch(now, frame_ms)


func _write(id: String, _now_t: float, value: float) -> void:
	if not _values.has(id):
		return
	var src: PackedFloat32Array = _values[id]
	src[_head] = value
	_values[id] = src
	_times[_head] = _now_t


func _drop_old(now: float) -> void:
	var cut := now - WINDOW_SEC
	while _count > 1 and _time_at(0) < cut:
		_count -= 1


func _watch_jumps() -> void:
	var objects := int(Performance.get_monitor(Performance.OBJECT_COUNT))
	if _last_objects >= 0:
		var jump := objects - _last_objects
		if abs(jump) >= 250:
			note_throttled("objects", "objects", "%+d objects (now %d)" % [jump, objects], 0.4)
	_last_objects = objects
	_last_draw = _jump("draw", "draw calls", latest("draw"), _last_draw, 80.0)
	_last_prims = _jump("prims", "prims k", latest("prims"), _last_prims, 40.0)
	_last_nodes = _jump("nodes", "nodes", latest("nodes"), _last_nodes, 120.0)
	_last_vram = _jump("vram", "VRAM MB", latest("vram"), _last_vram, 24.0)
	var mem := float(Performance.get_monitor(Performance.MEMORY_STATIC)) / 1048576.0
	if _last_mem >= 0.0 and abs(mem - _last_mem) >= 12.0:
		note_throttled("memory", "memory", "%+.1f MB static (now %.1f)" % [mem - _last_mem, mem], 0.6)
	_last_mem = mem
	var bodies := int(Performance.get_monitor(Performance.PHYSICS_3D_ACTIVE_OBJECTS))
	if _last_bodies >= 0 and abs(bodies - _last_bodies) >= 8:
		note_throttled("physics", "bodies", "%+d physics bodies (now %d)" % [
			bodies - _last_bodies, bodies], 0.4)
	_last_bodies = bodies
	var pipes := latest("pipes")
	if pipes >= 1.0:
		note_throttled("pipes", "pipes", "%.0f shader pipeline compiles" % pipes, 0.2)
	var physics_ms := latest("physics")
	if physics_ms >= 12.0:
		note_throttled("physics", "physics_ms", "physics frame %.1f ms" % physics_ms, 0.4)


func _jump(channel: String, noun: String, value: float, last: float, threshold: float) -> float:
	if last >= 0.0 and abs(value - last) >= threshold:
		note_throttled(channel, channel, "%+.1f %s (now %.1f)" % [value - last, noun, value], 0.45)
	return value


func _pipeline_compiles() -> float:
	return float(Performance.get_monitor(Performance.PIPELINE_COMPILATIONS_CANVAS)) \
		+ float(Performance.get_monitor(Performance.PIPELINE_COMPILATIONS_MESH)) \
		+ float(Performance.get_monitor(Performance.PIPELINE_COMPILATIONS_SURFACE)) \
		+ float(Performance.get_monitor(Performance.PIPELINE_COMPILATIONS_DRAW)) \
		+ float(Performance.get_monitor(Performance.PIPELINE_COMPILATIONS_SPECIALIZATION))


func _watch_hitch(now: float, frame_ms: float) -> void:
	var slot := posmod(int(now * 60.0), _frame_hist.size())
	_frame_hist[slot] = frame_ms
	var typical := _typical_frame()
	var spiked := frame_ms >= HITCH_MS or frame_ms >= typical * HITCH_MULT
	if not spiked or now - _last_hitch_at < HITCH_GAP_SEC:
		return
	_last_hitch_at = now
	note("hitch", "frame %.1f ms (typical %.1f)" % [frame_ms, typical], {
		"frame_ms": frame_ms,
		"typical_ms": typical,
	})
	call_deferred("_capture_hitch", now, frame_ms, typical)


func _capture_hitch(now: float, frame_ms: float, typical: float) -> void:
	var hitch := {
		"t": now,
		"frame_ms": snappedf(frame_ms, 0.01),
		"typical_ms": snappedf(typical, 0.01),
		"snapshot": snapshot(now - WINDOW_SEC, now),
	}
	_hitches.append(hitch)
	if _hitches.size() > MAX_HITCHES:
		_hitches = _hitches.slice(_hitches.size() - MAX_HITCHES)
	hitch_recorded.emit(_hitches.size() - 1)


func _typical_frame() -> float:
	var copy := _frame_hist.duplicate()
	copy.sort()
	return copy[copy.size() / 2]


func _summarize(frames: PackedFloat32Array) -> Dictionary:
	if frames.is_empty():
		return {"fps": 0.0, "avg_ms": 0.0, "max_ms": 0.0, "p95_ms": 0.0, "samples": 0}
	var copy := frames.duplicate()
	copy.sort()
	var total := 0.0
	for value in copy:
		total += value
	var avg := total / float(copy.size())
	var p95 := copy[clampi(int(floor(float(copy.size() - 1) * 0.95)), 0, copy.size() - 1)]
	return {
		"fps": snappedf(1000.0 / maxf(avg, 0.01), 0.1),
		"avg_ms": snappedf(avg, 0.01),
		"max_ms": snappedf(copy[copy.size() - 1], 0.01),
		"p95_ms": snappedf(p95, 0.01),
		"samples": copy.size(),
	}


func _time_at(logical: int) -> float:
	return _times[_index(logical)]


func _index(logical: int) -> int:
	var start := (_head - _count + CAPACITY) % CAPACITY
	return (start + logical) % CAPACITY


func _now() -> float:
	return float(Time.get_ticks_msec()) * 0.001


func _safe_name(title: String) -> String:
	var out := ""
	for ch in title.strip_edges().to_lower():
		var code := ch.unicode_at(0)
		if (code >= 97 and code <= 122) or (code >= 48 and code <= 57) or ch in "-_":
			out += ch
		elif ch == " " and not out.ends_with("_"):
			out += "_"
	return out.substr(0, 40)
