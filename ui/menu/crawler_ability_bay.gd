class_name CrawlerAbilityBay
extends VBoxContainer

## Open space under the three ability rows. Dropping an ability here fills
## the first empty loadout slot.

var host: Node


func _can_drop_data(_at: Vector2, data: Variant) -> bool:
	if host == null or not host.has_method(&"first_empty_equip") \
			or int(host.call(&"first_empty_equip")) < 0:
		return false
	if typeof(data) != TYPE_DICTIONARY:
		return false
	var payload := data as Dictionary
	if bool(payload.get("crawler_move", false)):
		return ItemDB.is_ability(str(payload.get("token", "")))
	var from := payload.get("red_item_slot") as RedItemSlot
	return from != null and ItemDB.is_ability(from.item_id())


func _drop_data(_at: Vector2, data: Variant) -> void:
	if host != null and host.has_method(&"seat_incoming_ability") \
			and typeof(data) == TYPE_DICTIONARY:
		host.call(&"seat_incoming_ability", data as Dictionary)
