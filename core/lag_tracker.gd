extends Node

## Left in place as an autoload so leftover call sites compile. Sampling,
## hitch naming, exports, and the event log are all off.

func _init() -> void:
	name = "LagTracker"
	process_mode = Node.PROCESS_MODE_DISABLED


func set_frozen(_on: bool) -> void:
	pass


func is_frozen() -> bool:
	return false


func note(_channel: String, _message: String, _extra: Dictionary = {}) -> void:
	pass


func note_throttled(_channel: String, _key: String, _message: String,
		_gap := 0.45, _extra: Dictionary = {}) -> bool:
	return false


func set_gauge(_id: String, _value: float) -> void:
	pass


func channels() -> Array[Dictionary]:
	var empty: Array[Dictionary] = []
	return empty


func events_in_window(_from_t: float = -1.0, _to_t: float = -1.0) -> Array[Dictionary]:
	var empty: Array[Dictionary] = []
	return empty


func hitches() -> Array[Dictionary]:
	var empty: Array[Dictionary] = []
	return empty


func explain_around(_at: float) -> Dictionary:
	return {}


func record_hitch(_frame_ms: float) -> int:
	return -1


func window_span() -> Vector2:
	return Vector2.ZERO


func sample_count() -> int:
	return 0


func series(_id: String) -> PackedFloat32Array:
	return PackedFloat32Array()


func times() -> PackedFloat64Array:
	return PackedFloat64Array()


func latest(_id: String) -> float:
	return 0.0


func frame_summary() -> Dictionary:
	return {}


func snapshot(_from_t: float = -1.0, _to_t: float = -1.0) -> Dictionary:
	return {}


func export_named(_title: String, _hitch_index := -1) -> String:
	return ""


func open_export_folder() -> void:
	pass


func export_dir() -> String:
	return ""
