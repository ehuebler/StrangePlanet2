class_name CombatStatuses
extends RefCounted

## Small, temporary combat effects shared by players and future enemies.
##
## Durations are authoritative on the host, but the same snapshot can be ticked
## locally for responsive HUD countdowns. Unknown ids are ignored so malformed
## packets cannot invent gameplay rules.

const FLIGHTLESS := &"flightless"
const POISON := &"poison"
const CHARM := &"charm"
const FREEZE := &"freeze"
const SHOCK := &"shock"
const MAX_DURATION := 3600.0
const CHARM_PULSE := 0.45
const SHOCK_LOCK := 0.22
const SHOCK_MOVE := 0.78
const SHOCK_CYCLE := SHOCK_LOCK + SHOCK_MOVE

const DEFINITIONS := {
	FLIGHTLESS: {
		"title": "Flightless",
		"description": "Flight is disabled.",
	},
	POISON: {
		"title": "Poison",
		"description": "Taking damage over time.",
	},
	CHARM: {
		"title": "Charmed",
		"description": "Fighting other enemies.",
	},
	FREEZE: {
		"title": "Frozen",
		"description": "Unable to move or attack.",
	},
	SHOCK: {
		"title": "Shocked",
		"description": "Locked, then twitching free, then locked again.",
	},
}

signal changed(id: StringName, remaining: float)

var _remaining: Dictionary = {}
## Optional intensity, such as poison damage per second.
var _strength: Dictionary = {}
## Seconds since each status was applied. Shock lock and charm hearts key off it.
var _age: Dictionary = {}
var _pulse_left: Dictionary = {}
var _shock_rising := false
var _was_shock_locked := false
## Reused by [method tick] so the physics hot path does not allocate an array.
var _expired: Array[StringName] = []


static func is_known(id: StringName) -> bool:
	return DEFINITIONS.has(id)


func has(id: StringName) -> bool:
	return float(_remaining.get(id, 0.0)) > 0.0


func remaining(id: StringName) -> float:
	return maxf(float(_remaining.get(id, 0.0)), 0.0)


func strength(id: StringName) -> float:
	return maxf(float(_strength.get(id, 0.0)), 0.0)


func shock_locked() -> bool:
	if not has(SHOCK):
		return false
	return fmod(float(_age.get(SHOCK, 0.0)), SHOCK_CYCLE) < SHOCK_LOCK


func movement_locked() -> bool:
	return has(FREEZE) or shock_locked()


func consume_pulse(id: StringName, interval: float) -> bool:
	if not has(id) or interval <= 0.0:
		return false
	if float(_pulse_left.get(id, 0.0)) > 0.0:
		return false
	_pulse_left[id] = interval
	return true


func consume_shock_pulse() -> bool:
	if not _shock_rising:
		return false
	_shock_rising = false
	return true


## Adds or refreshes an effect. The longer authored duration wins. Strength, when
## supplied, keeps the higher of the two intensities.
func apply_status(id: StringName, duration: float, intensity := 0.0) -> bool:
	if not is_known(id) or not is_finite(duration) or duration <= 0.0:
		return false
	var next := minf(duration, MAX_DURATION)
	var before := remaining(id)
	var next_strength := maxf(strength(id), intensity) \
		if is_finite(intensity) else strength(id)
	if before >= next and is_equal_approx(next_strength, strength(id)):
		return false
	var fresh := before <= 0.0
	_remaining[id] = maxf(before, next)
	if next_strength > 0.0:
		_strength[id] = next_strength
	if fresh:
		_age[id] = 0.0
		_pulse_left[id] = 0.0
		if id == SHOCK:
			_was_shock_locked = false
			_shock_rising = true
	changed.emit(id, remaining(id))
	return true


## Compatibility-friendly short form for combatants authoring an effect.
func apply(id: StringName, duration: float, intensity := 0.0) -> bool:
	return apply_status(id, duration, intensity)


## Advances countdowns and returns whether an effect expired.
func tick(delta: float) -> bool:
	if delta <= 0.0 or _remaining.is_empty():
		return false
	_expired.clear()
	for id_variant: Variant in _remaining:
		var id := StringName(id_variant)
		var left := maxf(float(_remaining[id]) - delta, 0.0)
		_age[id] = float(_age.get(id, 0.0)) + delta
		_pulse_left[id] = maxf(float(_pulse_left.get(id, 0.0)) - delta, 0.0)
		if left <= 0.0:
			_expired.append(id)
		else:
			_remaining[id] = left
			changed.emit(id, left)
	var locked := shock_locked()
	_shock_rising = locked and not _was_shock_locked
	_was_shock_locked = locked
	for id in _expired:
		_remaining.erase(id)
		_strength.erase(id)
		_age.erase(id)
		_pulse_left.erase(id)
		if id == SHOCK:
			_was_shock_locked = false
			_shock_rising = false
		changed.emit(id, 0.0)
	return not _expired.is_empty()


## Clears one effect, or all effects when no id is supplied.
func clear(id := &"") -> bool:
	var status_id := StringName(id)
	if not status_id.is_empty():
		if not _remaining.erase(status_id):
			return false
		_strength.erase(status_id)
		_age.erase(status_id)
		_pulse_left.erase(status_id)
		if status_id == SHOCK:
			_was_shock_locked = false
			_shock_rising = false
		changed.emit(status_id, 0.0)
		return true
	if _remaining.is_empty():
		return false
	_expired.clear()
	for id_variant: Variant in _remaining:
		_expired.append(StringName(id_variant))
	_remaining.clear()
	_strength.clear()
	_age.clear()
	_pulse_left.clear()
	_was_shock_locked = false
	_shock_rising = false
	for expired_id in _expired:
		changed.emit(expired_id, 0.0)
	return true


## Stable HUD/stat rows. Callers may redraw these only when [signal changed] fires.
func rows() -> Array[Dictionary]:
	var out: Array[Dictionary] = []
	for id: StringName in DEFINITIONS:
		var left := remaining(id)
		if left <= 0.0:
			continue
		var definition: Dictionary = DEFINITIONS[id]
		out.append({
			"id": id,
			"title": String(definition.get("title", String(id))),
			"description": String(definition.get("description", "")),
			"remaining": left,
			"text": "%.1f s" % left,
		})
	return out


## Compact wire snapshot. Dictionary keys are strings for RPC compatibility.
func to_wire() -> Dictionary:
	var wire := {}
	var intensities := {}
	for id_variant: Variant in _remaining:
		var id := StringName(id_variant)
		var left := remaining(id)
		if left > 0.0:
			wire[String(id)] = left
			var intensity := strength(id)
			if intensity > 0.0:
				intensities[String(id)] = intensity
	if not intensities.is_empty():
		wire["_strength"] = intensities
	var ages := {}
	for id_variant: Variant in _age:
		var id := StringName(id_variant)
		if remaining(id) > 0.0:
			ages[String(id)] = float(_age[id_variant])
	if not ages.is_empty():
		wire["_age"] = ages
	return wire


func snapshot() -> Dictionary:
	return to_wire()


func apply_wire(wire: Dictionary) -> void:
	var next := {}
	for id_variant: Variant in wire:
		var id := StringName(id_variant)
		if not is_known(id):
			continue
		var left := float(wire[id_variant])
		if not is_finite(left) or left <= 0.0:
			continue
		next[id] = minf(left, MAX_DURATION)

	_expired.clear()
	for id_variant: Variant in _remaining:
		var old_id := StringName(id_variant)
		if not next.has(old_id):
			_expired.append(old_id)
	for old_id in _expired:
		changed.emit(old_id, 0.0)
	_remaining = next
	_strength.clear()
	_age.clear()
	_pulse_left.clear()
	var intensities: Variant = wire.get("_strength", {})
	if intensities is Dictionary:
		for id_variant: Variant in _remaining:
			var id := StringName(id_variant)
			var listed := float((intensities as Dictionary).get(String(id), 0.0))
			if is_finite(listed) and listed > 0.0:
				_strength[id] = listed
	var ages: Variant = wire.get("_age", {})
	if ages is Dictionary:
		for id_variant: Variant in _remaining:
			var id := StringName(id_variant)
			var listed := float((ages as Dictionary).get(String(id), 0.0))
			if is_finite(listed) and listed >= 0.0:
				_age[id] = listed
	_was_shock_locked = shock_locked()
	_shock_rising = false
	for id_variant: Variant in _remaining:
		var id := StringName(id_variant)
		changed.emit(id, float(_remaining[id]))


func apply_snapshot(wire: Dictionary) -> void:
	apply_wire(wire)
