class_name ItemContainer
extends RefCounted

## A fixed run of slots holding item ids, with "" for an empty slot.
##
## The player's backpack, the equipment they are wearing and a wardrobe's shelves
## are all one of these, which is what lets a single move function serve dragging,
## shift-clicking and equipping. A slot can carry a filter naming the body slot it
## accepts, so an equipment slot refuses a pair of shoes on the head without the
## UI needing to know the rule.

signal changed

var _items: PackedStringArray = PackedStringArray()
var _filters: PackedStringArray = PackedStringArray()


func _init(slot_count: int, contents: Array = []) -> void:
	_items.resize(slot_count)
	_filters.resize(slot_count)
	for index in mini(contents.size(), slot_count):
		_items[index] = String(contents[index])


func size() -> int:
	return _items.size()


## Grows or shrinks the slot run. Items past the new length are returned so a
## caller can stash them; filters on kept slots stay put.
func resize(slot_count: int) -> PackedStringArray:
	var wanted := maxi(slot_count, 0)
	var overflow := PackedStringArray()
	if wanted == _items.size():
		return overflow
	if wanted < _items.size():
		for index in range(wanted, _items.size()):
			if not _items[index].is_empty():
				overflow.append(_items[index])
	_items.resize(wanted)
	_filters.resize(wanted)
	changed.emit()
	return overflow


func get_item(index: int) -> String:
	if index < 0 or index >= _items.size():
		return ""
	return _items[index]


func set_item(index: int, id: String) -> void:
	if index < 0 or index >= _items.size() or _items[index] == id \
			or not accepts(index, id):
		return
	_items[index] = id
	changed.emit()


func items() -> PackedStringArray:
	return _items.duplicate()


## Restricts `index` to items worn in `body_slot`. An empty filter accepts
## anything.
func set_filter(index: int, body_slot: String) -> void:
	if index >= 0 and index < _filters.size():
		_filters[index] = body_slot


func filter_of(index: int) -> String:
	if index < 0 or index >= _filters.size():
		return ""
	return _filters[index]


func accepts(index: int, id: String) -> bool:
	if id.is_empty():
		return true
	var filter := filter_of(index)
	return filter.is_empty() or ItemDB.accepts(filter, id)


## The slot `id` should go to when nothing more specific was asked for: a free
## slot that accepts it, or -1 when the container is full.
func first_accepting(id: String) -> int:
	for index in _items.size():
		if _items[index].is_empty() and accepts(index, id):
			return index
	return -1


func find(id: String) -> int:
	for index in _items.size():
		if _items[index] == id:
			return index
	return -1


func is_full() -> bool:
	return first_accepting("") < 0


func clear() -> void:
	var had_items := false
	for index in _items.size():
		had_items = had_items or not _items[index].is_empty()
		_items[index] = ""
	if had_items:
		changed.emit()


## Moves an item onto a specific slot, swapping with whatever is already there.
## Refuses a move either slot's filter rejects, so a swap cannot smuggle an item
## into a slot it does not belong in.
static func transfer(from: ItemContainer, from_index: int, to: ItemContainer, to_index: int) -> bool:
	var moving := from.get_item(from_index)
	if moving.is_empty():
		return false
	if from == to and from_index == to_index:
		return false
	var displaced := to.get_item(to_index)
	if not to.accepts(to_index, moving) or not from.accepts(from_index, displaced):
		return false
	to.set_item(to_index, moving)
	from.set_item(from_index, displaced)
	return true


## Sends an item to the first slot of `to` that will take it, which is what
## shift-clicking does.
static func quick_move(from: ItemContainer, from_index: int, to: ItemContainer) -> bool:
	var moving := from.get_item(from_index)
	if moving.is_empty():
		return false
	var target := to.first_accepting(moving)
	if target < 0:
		return false
	return transfer(from, from_index, to, target)
