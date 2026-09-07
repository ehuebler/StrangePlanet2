class_name Journal
extends RefCounted

## What one player has done, against the goals in [JournalDB].
##
## Held by [OnlinePlayer] and driven from its physics step, because the only
## condition there is measures a distance from the player to a place. Checked on an
## interval rather than every frame: the entries are a handful, but each one is a
## group walk and a square root against a target that cannot be reached in the
## seven metres a flight covers between checks.
##
## Completion is **local and persistent**. Nothing about a quest is replicated: a
## co-op session shares a world, not a diary, and the host has no business being
## told which achievements a guest has. It saves to `settings.cfg` under
## `progress/done` and `progress/claimed` for the same reason the look does —
## it is a fact about this player on this machine. Claimable gems wait on the
## menu. Instant XP, auto gems, and unlocks pay the moment the goal finishes.

## Seconds between condition checks.
const INTERVAL := 0.5

## Bumped when claim persistence changed. Revision 0 saves paid gems on
## complete; seeding those ids as claimed avoids a second payout.
const CLAIM_REVISION := 1

signal completed(id: String)
signal claimed(id: String)

static var _testing := false
static var _test_done: Dictionary = {}
static var _test_claimed: Dictionary = {}
static var _test_kills := 0

var _done: Dictionary = {}
var _claimed: Dictionary = {}
var _kills := 0
var _elapsed := 0.0
var _session_unlocked: PackedStringArray = PackedStringArray()
var _unlocking_levels := false


static func begin_test() -> void:
	_testing = true
	_test_done = {}
	_test_claimed = {}
	_test_kills = 0


static func end_test() -> void:
	_testing = false
	_test_done = {}
	_test_claimed = {}
	_test_kills = 0


func _init() -> void:
	load_progress()


func is_done(id: String) -> bool:
	return bool(_done.get(id, false))


func is_claimed(id: String) -> bool:
	return bool(_claimed.get(id, false))


## Finished, pays gems, and those gems have not been taken from the menu yet.
func can_claim(id: String) -> bool:
	return is_done(id) and not is_claimed(id) and JournalDB.gems_of(id) > 0


func done_count(kind: StringName) -> int:
	var count := 0
	for id in JournalDB.ids_of_kind(kind):
		if is_done(id):
			count += 1
	return count


## Marks an entry done and saves. Claimable gem rewards stay unclaimed until
## [method claim] from the menu. Instant XP, auto gems, and unlocks pay now.
## Returns false if it was already done, so a caller can tell a fresh
## completion from a repeat and only announce the former.
func complete(id: String) -> bool:
	if not JournalDB.has_entry(id) or is_done(id):
		return false
	_done[id] = true
	if not _session_unlocked.has(id):
		_session_unlocked.append(id)
	_grant_instant_rewards(id)
	save_progress()
	completed.emit(id)
	if not _unlocking_levels:
		note_global_level(CrawlerMeta.global_level())
	return true


func session_completed() -> PackedStringArray:
	return _session_unlocked.duplicate()


func _grant_instant_rewards(id: String) -> void:
	var gems := JournalDB.auto_gems_of(id)
	if gems > 0:
		CrawlerMeta.add_gems(gems)
	var xp := JournalDB.xp_of(id)
	if xp > 0:
		CrawlerMeta.add_xp(xp)
	for unlock: String in JournalDB.unlocks_of(id):
		if unlock == "sandbox":
			CrawlerMeta.unlock_sandbox()


## Pays a finished achievement's gems once. Returns false if it is not waiting.
func claim(id: String) -> bool:
	if not can_claim(id):
		return false
	_claimed[id] = true
	var gems := JournalDB.gems_of(id)
	if gems > 0:
		CrawlerMeta.add_gems(gems)
	save_progress()
	claimed.emit(id)
	return true


## Clears one entry or, with no id, all of them. The admin tab's undo.
## A full reset also clears the lifetime kill count so combat achievements
## can fire again. Claimed rewards are cleared too; gems already paid stay.
func reset(id := "") -> void:
	if id.is_empty():
		_done.clear()
		_claimed.clear()
		_kills = 0
		_session_unlocked.clear()
		CrawlerMeta.lock_sandbox()
	else:
		_done.erase(id)
		_claimed.erase(id)
		var kept := PackedStringArray()
		for held: String in _session_unlocked:
			if held != id:
				kept.append(held)
		_session_unlocked = kept
		if id == "first_city":
			CrawlerMeta.lock_sandbox()
	save_progress()


## Homescreen reset: combat and achievement rows only. Quests stay.
func reset_achievements() -> void:
	for id: String in JournalDB.ids_of_kind(JournalDB.ACHIEVEMENT):
		_done.erase(id)
		_claimed.erase(id)
	_kills = 0
	_session_unlocked.clear()
	CrawlerMeta.lock_sandbox()
	save_progress()


func kills() -> int:
	return _kills


## One crawler kill toward combat achievements. Returns any ids that just
## completed so a HUD sting can name them.
func note_kill(amount := 1) -> PackedStringArray:
	if amount <= 0:
		return PackedStringArray()
	_kills += amount
	var unlocked := PackedStringArray()
	for id: String in JournalDB.ids_of_kind(JournalDB.ACHIEVEMENT):
		var needed := JournalDB.kills_of(id)
		if needed <= 0 or _kills < needed:
			continue
		if complete(id):
			unlocked.append(id)
	if unlocked.is_empty():
		save_progress()
	return unlocked


## First city ring. Returns any ids that just completed.
func note_city() -> PackedStringArray:
	var unlocked := PackedStringArray()
	for id: String in JournalDB.ids_of_kind(JournalDB.ACHIEVEMENT):
		if not JournalDB.wants_city(id):
			continue
		if complete(id):
			unlocked.append(id)
	return unlocked


## Global-level milestones after XP is paid. Returns any ids that just completed.
func note_global_level(level: int) -> PackedStringArray:
	if _unlocking_levels:
		return PackedStringArray()
	_unlocking_levels = true
	var unlocked := PackedStringArray()
	for id: String in JournalDB.ids_of_kind(JournalDB.ACHIEVEMENT):
		var needed := JournalDB.global_level_of(id)
		if needed <= 0 or level < needed:
			continue
		if complete(id):
			unlocked.append(id)
	_unlocking_levels = false
	return unlocked


## Walks the unfinished entries and completes any whose condition now holds.
## `where` is the player's global position; `tree` is how landmarks are found.
func track(where: Vector3, tree: SceneTree, delta: float) -> void:
	_elapsed += delta
	if _elapsed < INTERVAL or tree == null:
		return
	_elapsed = 0.0
	var places := _landmarks(tree)
	for id: String in JournalDB.ENTRIES:
		if is_done(id):
			continue
		var wanted := JournalDB.landmark_of(id)
		if wanted.is_empty() or not places.has(wanted):
			continue
		var at: Vector3 = places[wanted]
		if where.distance_to(at) <= JournalDB.within_of(id):
			complete(id)


## Landmark node name → where it is. By node name rather than title, because the
## title is player-facing text and free to be reworded without breaking a goal.
func _landmarks(tree: SceneTree) -> Dictionary:
	var out: Dictionary = {}
	for node in tree.get_nodes_in_group(Landmark.GROUP):
		var landmark := node as Landmark
		if landmark != null:
			out[landmark.name] = landmark.global_position
	return out


func load_progress() -> void:
	_done.clear()
	_claimed.clear()
	_kills = 0
	if _testing:
		_done = _test_done.duplicate()
		_claimed = _test_claimed.duplicate()
		_kills = _test_kills
		return
	if SettingsManager == null:
		return
	var raw: Variant = SettingsManager.get_setting(&"progress", &"done", [])
	if raw is Array:
		for entry: Variant in raw:
			var id := str(entry)
			if JournalDB.has_entry(id):
				_done[id] = true
	var claimed_raw: Variant = SettingsManager.get_setting(&"progress", &"claimed", [])
	if claimed_raw is Array:
		for entry: Variant in claimed_raw:
			var id := str(entry)
			if JournalDB.has_entry(id):
				_claimed[id] = true
	_kills = maxi(int(SettingsManager.get_setting(&"progress", &"kills", 0)), 0)
	var revision := int(SettingsManager.get_setting(&"progress", &"claim_revision", 0))
	if revision < CLAIM_REVISION:
		_seed_legacy_claims()
		save_progress()


## Older builds added gems the moment an achievement finished. Those payouts
## already landed, so finished gem goals are marked claimed and cannot be taken
## a second time from the menu.
func _seed_legacy_claims() -> void:
	for id: String in _done:
		if JournalDB.gems_of(id) > 0:
			_claimed[id] = true


func save_progress() -> void:
	if _testing:
		_test_done = _done.duplicate()
		_test_claimed = _claimed.duplicate()
		_test_kills = _kills
		return
	if SettingsManager == null:
		return
	LagTracker.note_throttled("io", "journal_save", "journal save", 1.0)
	SettingsManager.set_setting(&"progress", &"done", _done.keys(), false)
	SettingsManager.set_setting(&"progress", &"claimed", _claimed.keys(), false)
	SettingsManager.set_setting(&"progress", &"kills", _kills, false)
	SettingsManager.set_setting(&"progress", &"claim_revision", CLAIM_REVISION, false)
	SettingsManager.save_settings()
