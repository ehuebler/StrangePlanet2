class_name DamageNumberEvent
extends RefCounted

## Presentation-only description of one combat number.

enum Kind {
	DAMAGE,
	GOLD,
	XP,
	GEM,
	POISON,
	CHARM,
	SHOCK,
	FREEZE,
}

var amount := 0.0
var world_position := Vector3.ZERO
var incoming := false
var blocked := false
var critical := false
var structure := false
var killed := false
var source_peer := 0
var source_name := ""
var ability_name := ""
var target_peer := 0
var merge_key := ""
var kind := Kind.DAMAGE
var screen_offset := Vector2.ZERO


func caption(total := -1.0) -> String:
	var value := roundi(total if total >= 0.0 else amount)
	match kind:
		Kind.GOLD:
			return "$%d" % value
		Kind.XP:
			return "+%d" % value
		Kind.GEM:
			return "+%d G" % value
		Kind.CHARM:
			return "♥"
		Kind.SHOCK:
			return "⚡"
		_:
			return str(value)


func to_wire() -> Dictionary:
	return {
		"amount": amount,
		"world_position": world_position,
		"incoming": incoming,
		"blocked": blocked,
		"critical": critical,
		"structure": structure,
		"killed": killed,
		"source_peer": source_peer,
		"source_name": source_name,
		"ability_name": ability_name,
		"target_peer": target_peer,
		"merge_key": merge_key,
		"kind": int(kind),
		"screen_offset": screen_offset,
	}


static func from_wire(wire: Dictionary) -> DamageNumberEvent:
	var event := DamageNumberEvent.new()
	event.amount = maxf(float(wire.get("amount", 0.0)), 0.0)
	var at: Variant = wire.get("world_position", Vector3.ZERO)
	event.world_position = at if at is Vector3 and (at as Vector3).is_finite() \
		else Vector3.ZERO
	event.incoming = bool(wire.get("incoming", false))
	event.blocked = bool(wire.get("blocked", false))
	event.critical = bool(wire.get("critical", false))
	event.structure = bool(wire.get("structure", false))
	event.killed = bool(wire.get("killed", false))
	event.source_peer = maxi(int(wire.get("source_peer", 0)), 0)
	event.source_name = String(wire.get("source_name", ""))
	event.ability_name = String(wire.get("ability_name", ""))
	event.target_peer = maxi(int(wire.get("target_peer", 0)), 0)
	event.merge_key = String(wire.get("merge_key", ""))
	event.kind = clampi(int(wire.get("kind", Kind.DAMAGE)), Kind.DAMAGE, Kind.FREEZE) as Kind
	var shift: Variant = wire.get("screen_offset", Vector2.ZERO)
	event.screen_offset = shift if shift is Vector2 else Vector2.ZERO
	return event
