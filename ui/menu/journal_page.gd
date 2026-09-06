class_name JournalPage
extends HBoxContainer

## The Quests tab and the Achievements tab, which are the same page twice.
##
## A quest and an achievement are the same shape — a filter, a list you pick from,
## and a panel describing whatever is picked — and they read from the same table,
## so this is one class handed a kind rather than two files that would drift apart
## the first time the list gained a column. [JournalDB] decides which entries and
## which categories belong to each kind; nothing here knows what a quest is.
##
## The page holds no progress of its own: [Journal] owns what is finished, and this
## redraws when it says so.

const PALETTE: UIPalette = preload("res://ui/themes/ui_palette.tres")

## Share of the width the list takes; the rest is the description.
const LIST_SHARE := 0.38
const LIST_MIN := 260.0

var _journal: Journal
var _kind := JournalDB.QUEST
var _category := "All"
var _search := ""
var _selected := ""

var _list: VBoxContainer
var _detail: VBoxContainer


## Called before the page enters the tree.
func configure(journal: Journal, kind: StringName) -> void:
	_journal = journal
	_kind = kind


func _ready() -> void:
	add_theme_constant_override(&"separation", 18)
	size_flags_vertical = Control.SIZE_EXPAND_FILL
	_build()
	if _journal != null:
		_journal.completed.connect(_on_completed)
		if not _journal.claimed.is_connected(_on_claimed):
			_journal.claimed.connect(_on_claimed)
	var first := _visible_ids()
	_select(first[0] if not first.is_empty() else "")


func _build() -> void:
	var left := VBoxContainer.new()
	left.add_theme_constant_override(&"separation", 12)
	left.custom_minimum_size = Vector2(LIST_MIN, 0)
	left.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	left.size_flags_stretch_ratio = LIST_SHARE
	add_child(left)
	left.add_child(_filter_row())

	var scroll := ScrollContainer.new()
	scroll.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	scroll.size_flags_vertical = Control.SIZE_EXPAND_FILL
	left.add_child(scroll)

	_list = VBoxContainer.new()
	_list.add_theme_constant_override(&"separation", 10)
	_list.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	scroll.add_child(_list)

	var panel := PanelContainer.new()
	panel.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	panel.size_flags_vertical = Control.SIZE_EXPAND_FILL
	panel.size_flags_stretch_ratio = 1.0 - LIST_SHARE
	add_child(panel)
	AuroraSurface.add_to(panel, AuroraSurface.Style.ROW)

	var padding := MarginContainer.new()
	for side in [&"margin_left", &"margin_right", &"margin_top", &"margin_bottom"]:
		padding.add_theme_constant_override(side, 20)
	panel.add_child(padding)

	_detail = VBoxContainer.new()
	_detail.add_theme_constant_override(&"separation", 10)
	padding.add_child(_detail)

	_fill_list()


## The category picker and a search box. Both narrow the same list, so typing and
## picking compose rather than one resetting the other.
func _filter_row() -> Control:
	var row := HBoxContainer.new()
	row.add_theme_constant_override(&"separation", 10)

	var categories := JournalDB.categories_of_kind(_kind)
	var picker := OptionButton.new()
	for category in categories:
		picker.add_item(category)
	picker.selected = maxi(Array(categories).find(_category), 0)
	picker.custom_minimum_size.x = 130
	AuroraSurface.add_to(picker, AuroraSurface.Style.BUTTON)
	picker.item_selected.connect(func(index: int) -> void:
		_category = categories[index] if index < categories.size() else "All"
		_fill_list()
	)
	row.add_child(picker)

	var search := LineEdit.new()
	search.placeholder_text = "Search %s" % ("quests" if _kind == JournalDB.QUEST else "achievements")
	search.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	AuroraSurface.add_to(search, AuroraSurface.Style.INPUT)
	search.text_changed.connect(func(text: String) -> void:
		_search = text.strip_edges().to_lower()
		_fill_list()
	)
	row.add_child(search)
	return row


## Ids of this kind that pass the category and the search, in table order.
func _visible_ids() -> PackedStringArray:
	var out := PackedStringArray()
	for id in JournalDB.ids_of_kind(_kind):
		if _category != "All" and JournalDB.category_of(id) != _category:
			continue
		if not _search.is_empty():
			var haystack := "%s %s" % [JournalDB.title_of(id), JournalDB.summary_of(id)]
			if not haystack.to_lower().contains(_search):
				continue
		out.append(id)
	return out


func _fill_list() -> void:
	for child in _list.get_children():
		child.queue_free()
	var ids := _visible_ids()
	if ids.is_empty():
		_list.add_child(MenuWidgets.caption("Nothing here matches."))
		return
	for id in ids:
		var done := _journal != null and _journal.is_done(id)
		var waiting := _journal != null and _journal.can_claim(id)
		var mark := ""
		if waiting:
			mark = "[claim]  "
		elif done:
			mark = "[done]  "
		var button := MenuWidgets.button(
			"%s%s" % [mark, JournalDB.title_of(id)],
			AuroraSurface.Style.PRIMARY if id == _selected else AuroraSurface.Style.BUTTON)
		button.alignment = HORIZONTAL_ALIGNMENT_LEFT
		button.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		button.add_theme_font_size_override(&"font_size", 14)
		var chosen := id
		button.pressed.connect(func() -> void: _select(chosen))
		_list.add_child(button)


func _select(id: String) -> void:
	_selected = id
	_fill_list()
	for child in _detail.get_children():
		child.queue_free()
	if id.is_empty():
		_detail.add_child(MenuWidgets.caption("Pick something on the left."))
		return

	_detail.add_child(MenuWidgets.heading(JournalDB.title_of(id).to_upper(), 24))
	var done := _journal != null and _journal.is_done(id)
	var waiting := _journal != null and _journal.can_claim(id)
	_detail.add_child(_status_line(JournalDB.category_of(id), done, waiting,
		_journal != null and _journal.is_claimed(id)))
	_detail.add_child(AuroraSurface.rule())
	_detail.add_child(_paragraph(JournalDB.summary_of(id), 16, PALETTE.text_primary))
	var detail := JournalDB.detail_of(id)
	if not detail.is_empty():
		_detail.add_child(_paragraph(detail, 14, PALETTE.text_secondary))

	var landmark := JournalDB.landmark_of(id)
	if not landmark.is_empty():
		_detail.add_child(_paragraph(
			"Get within %d m of the %s waypoint." % [
				roundi(JournalDB.within_of(id)), JournalDB.title_of(id)],
			13, PALETTE.text_muted))
	var needed := JournalDB.kills_of(id)
	if needed > 0:
		var have := _journal.kills() if _journal != null else 0
		_detail.add_child(_paragraph(
			"Kills %d / %d." % [mini(have, needed), needed],
			13, PALETTE.text_muted))
	var reward := JournalDB.reward_of(id)
	if not reward.is_empty():
		_detail.add_child(_paragraph("Reward: %s" % reward, 13, PALETTE.text_muted))
	if waiting:
		var claim := MenuWidgets.button("Claim gems", AuroraSurface.Style.PRIMARY)
		claim.name = "JournalClaim_%s" % id
		claim.pressed.connect(_claim_selected)
		_detail.add_child(claim)


func _status_line(category: String, done: bool, waiting := false, taken := false) -> Control:
	var label := Label.new()
	var state := "IN PROGRESS"
	if waiting:
		state = "UNCLAIMED"
	elif taken:
		state = "CLAIMED"
	elif done:
		state = "COMPLETE"
	label.text = "%s    %s" % [category, state]
	label.add_theme_font_size_override(&"font_size", 13)
	label.add_theme_color_override(&"font_color",
		PALETTE.secondary if done else PALETTE.text_muted)
	return label


func _paragraph(text: String, font_size: int, colour: Color) -> Label:
	var label := Label.new()
	label.text = text
	label.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	label.add_theme_font_size_override(&"font_size", font_size)
	label.add_theme_color_override(&"font_color", colour)
	return label


func _claim_selected() -> void:
	if _journal != null and _journal.claim(_selected):
		_select(_selected)


func _on_completed(id: String) -> void:
	_fill_list()
	if id == _selected:
		_select(id)


func _on_claimed(id: String) -> void:
	_fill_list()
	if id == _selected:
		_select(id)
