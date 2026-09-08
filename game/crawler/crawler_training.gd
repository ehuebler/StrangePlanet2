extends RefCounted

## Duals-tab practice field. One of every catalog mob stands idle on a blank
## pad outside the run. A fire click writes the real hit, tagged by shape and
## element, instead of starting a chase.

const SPACING := 50.0
const FLORA_CLEAR := 220.0
const CLEAR_ID := "crawler_training"
const FALLBACK_ORIGIN := Vector3(2400.0, 2.0, 0.0)
const COLUMNS := 4


static func kinds() -> PackedStringArray:
	return CrawlerMobs.FIELD_ORDER


static func max_level() -> int:
	CrawlerMobs.ensure_loaded()
	var top := 1
	for kind: String in kinds():
		top = maxi(top, CrawlerMobs.max_level_for(kind))
	return maxi(top, 1)


static func clamp_level(level: int) -> int:
	return clampi(level, 1, max_level())


static func grid_offset(index: int, count: int, spacing := SPACING) -> Vector2:
	var n := maxi(count, 1)
	var cols := maxi(COLUMNS, 1)
	if n < cols:
		cols = n
	var rows := ceili(float(n) / float(cols))
	var col := posmod(index, cols)
	var row := int(index / cols)
	var x := (float(col) - (float(cols) - 1.0) * 0.5) * spacing
	var z := (float(row) - (float(rows) - 1.0) * 0.5) * spacing
	return Vector2(x, z)


static func grid_point(centre: Transform3D, index: int, count: int,
		spacing := SPACING) -> Vector3:
	var offset := grid_offset(index, count, spacing)
	var up := centre.basis.y
	if up.length_squared() < 0.0001:
		up = Vector3.UP
	up = up.normalized()
	var right := centre.basis.x
	if right.length_squared() < 0.0001:
		right = up.cross(Vector3.FORWARD)
	right = right - up * right.dot(up)
	if right.length_squared() < 0.0001:
		right = up.cross(Vector3.RIGHT)
	right = right.normalized()
	var forward := up.cross(right).normalized()
	return centre.origin + right * offset.x + forward * offset.y


static func hit_tags(hit: DamageHit) -> PackedStringArray:
	var tags := PackedStringArray()
	if hit == null:
		return tags
	if hit.explosive or hit.kind == DamageHit.Kind.AREA:
		tags.append("AOE")
	elif hit.kind == DamageHit.Kind.BEAM:
		tags.append("Beam")
	elif hit.projectile:
		tags.append("Projectile")
	else:
		tags.append("Impact")
	for entry: Dictionary in hit.status_entries():
		var status := StringName(str(entry.get("id", "")))
		var label := _status_tag(status)
		if not label.is_empty() and not tags.has(label):
			tags.append(label)
	return tags


static func hit_who(target: Node, hit: DamageHit) -> String:
	var name := ""
	if target != null and target.has_method(&"combat_display_name"):
		name = str(target.call(&"combat_display_name")).strip_edges()
	if name.is_empty() and target != null:
		name = String(target.name)
	var ability := ""
	if hit != null:
		ability = hit.ability_display_name().strip_edges()
		if ability.is_empty():
			ability = str(hit.ability_id).strip_edges()
	var tags := hit_tags(hit)
	var parts: PackedStringArray = PackedStringArray()
	if not name.is_empty():
		parts.append(name)
	if not ability.is_empty():
		parts.append(ability)
	for tag: String in tags:
		parts.append(tag)
	return " · ".join(parts) if not parts.is_empty() else "Hit"


static func _status_tag(status: StringName) -> String:
	match status:
		CombatStatuses.POISON:
			return "Toxic"
		CombatStatuses.FREEZE:
			return "Freeze"
		CombatStatuses.SLOW:
			return "Slow"
		CombatStatuses.CHARM:
			return "Charm"
		CombatStatuses.SHOCK:
			return "Shock"
		_:
			return ""
