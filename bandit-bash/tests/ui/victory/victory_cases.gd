# ==============================================================================
# Bandit Bash
# Copyright (c) 2026 Derc Development
# Licensed under the MIT License. See LICENSE.
#
# File:     victory_cases.gd
# Author:
# Created:  November 19, 2026
# Modified: November 22, 2026
# ==============================================================================

extends RefCounted
## The victory sequence's parts, for the ui/victory suite: the model's XP before the combat over
## 0, 1 and 2 level-ups, its fallen lines and its stats (and a report saved before stats reading
## "—"); the reward list before and after the pick is settled, and with no pick; the XP bar's
## fill (delay, √gain ÷ 6 length, hold, wrapping at a level, skipping to the end); the recap's
## rows (standing then fallen, the Standout and Fallen tags), its fills one after another, each
## level-up in order; and a long recap scrolled by a pad's focus (begin_scroll, then
## press_down, then finish_scroll, a few frames apart). Never names the overlay or the item
## picker, whose scripts name autoloads.

# The suite that runs this file; tests/case_files.gd finds it by this line.
const SUITE: String = "ui/victory"

const RULES_PATH: String = "res://data/campaign/campaign_map_rules.tres"
const RUN_SEED: int = 0x5EED
const MERCENARY: String = "mercenary"

const XP_BAR_SCENE: PackedScene = preload("res://ui/campaign/victory/xp_bar.tscn")
const RECAP_SCENE: PackedScene = preload("res://ui/campaign/victory/victory_recap_stage.tscn")

# The units of the long recap: more than fit the scroll, as an army grown by Muster Roll.
const LONG_ARMY: int = 8

# The long recap's size in base units: a few rows tall.
const SCROLL_SIZE: Vector2 = Vector2(720.0, 260.0)

# The first unit's XP line: 150 from shared, personal and the Standout's bonus.
const XP_TEXT: String = "+150 XP: shared 40 · personal 105 · Standout 5"

# A step long enough to end any fill in one call.
const LONG_STEP: float = 60.0

var _check: Callable
var _root: Window = null
var _rules: CombatRewardRules = null
var _catalog: EffectCatalog.Index = null

# The long recap scrolled by focus, and the button below it.
var _scroll_stage: VictoryRecapStage = null
var _below: Button = null


## [param check]: called as check(case_name: String, passed: bool, detail: String).
## [param root]: the root viewport, where scenes are added.
func _init(check: Callable, root: Window) -> void:
	_check = check
	_root = root


## Runs every case but the scroll, which takes frames.
func run() -> void:
	_rules = CombatRewardRules.load_default()
	_catalog = EffectCatalog.index()
	_ok("victory: the reward rules and catalog load", (
			_rules != null and _catalog != null
	), "")
	if _rules == null or _catalog == null:
		return
	_test_model()
	_test_old_report()
	_test_rewards()
	_test_xp_bar()
	_test_recap_stage()


func _test_model() -> void:
	var session: CampaignSession = _session()
	var seat_run: SeatRun = session.run.seat_run(0)
	var per: int = _rules.xp_per_level
	# Before the combat: lv 1 at 20, at 10 and at 90; their gains reach 1, 0 and 2 levels.
	var leveled: UnitInstance = _unit_at(seat_run.army[0], 2, 70)
	var steady: UnitInstance = _unit_at(seat_run.army[1], 1, 40)
	var twice: UnitInstance = _unit_at(seat_run.army[2], 3, 10)
	var fallen: UnitInstance = seat_run.army[3]
	seat_run.army.erase(fallen)
	seat_run.fallen.append(fallen)
	_store_report(seat_run, [
		_award(leveled.instance_id, 150, true), _award(steady.instance_id, 30, false),
		_award(twice.instance_id, 120, false),
	], [
		_level_up(leveled.instance_id, 2), _level_up(twice.instance_id, 2),
		_level_up(twice.instance_id, 3),
	], [leveled, steady, twice, fallen])
	var model: CombatResultsModel = CombatResultsModel.build(session, 0, _catalog, _rules)
	var lines: Array[CombatResultsModel.XpLine] = []
	if model != null:
		lines = model.xp_lines
	_ok("model: XP before the combat over 1, 0 and 2 level-ups", (
			lines.size() == 3
			and lines[0].level_before == 1 and lines[0].xp_before == 20
			and lines[1].level_before == 1 and lines[1].xp_before == 10
			and lines[2].level_before == 1 and lines[2].xp_before == 90
			and per == 100
	), "" if lines.size() != 3 else "%d/%d %d/%d %d/%d" % [
		lines[0].level_before, lines[0].xp_before, lines[1].level_before, lines[1].xp_before,
		lines[2].level_before, lines[2].xp_before,
	])
	_ok("model: the fallen unit has its own line, with stats and no award", (
			model != null
			and model.fallen_lines.size() == 1
			and model.fallen_lines[0].unit_id == fallen.instance_id
			and model.fallen_lines[0].is_fallen
			and model.fallen_lines[0].award == null
			and model.fallen_lines[0].stats[BattleStats.Stat.DAMAGE_TAKEN] == 9
	))
	_ok("model: the report's stats and the gold held", (
			model != null
			and model.has_stats
			and lines[0].stats[BattleStats.Stat.KILLS] == 2
			and model.gold_held == seat_run.gold
			and model.level_up_lines.size() == 3
			and model.level_up_lines[1].unit_id == twice.instance_id
	))
	var row_text: String = "" if lines.is_empty() else UnitRecapRow.stats_text(lines[0].stats)
	_ok("row: the stats read as words and numbers; the XP as its parts", (
			row_text == "Kills 2 · Damage dealt 14 · Damage taken 9 · Healed 3"
			and UnitRecapRow.xp_text(lines[0].award) == XP_TEXT
	), row_text)


# A report saved before stats: no fallen lines, every unit's stats unread ("—").
func _test_old_report() -> void:
	var session: CampaignSession = _session()
	var seat_run: SeatRun = session.run.seat_run(0)
	var unit: UnitInstance = _unit_at(seat_run.army[0], 1, 30)
	_store_report(seat_run, [_award(unit.instance_id, 30, false)], [], [])
	(seat_run.pending_offers[CampaignRunState.COMBAT_REPORT_KEY] as Dictionary).erase("stats")
	var model: CombatResultsModel = CombatResultsModel.build(session, 0, _catalog, _rules)
	_ok("model: a report saved before stats reads, its stats shown as —", (
			model != null
			and not model.has_stats
			and model.fallen_lines.is_empty()
			and model.xp_lines.size() == 1
			and UnitRecapRow.stats_text(model.xp_lines[0].stats) == UnitRecapRow.NO_STATS
	))


func _test_rewards() -> void:
	var session: CampaignSession = _session()
	var seat_run: SeatRun = session.run.seat_run(0)
	_store_report(seat_run, [], [], [])
	var pick: ItemPick = ItemPick.new()
	pick.slot = ItemPick.Slot.WEAPON
	for weapon_id: String in _weapon_ids(2):
		pick.offers.append(ItemPick.Offer.new(weapon_id, session.ids.next_item_id(weapon_id)))
	pick.store(seat_run)
	var rewards: Array[VictoryReward] = VictoryRewards.build(
			CombatResultsModel.build(session, 0, _catalog, _rules)
	)
	var skip: CampaignCommand = null if rewards.is_empty() else rewards[0].skip_command(0)
	_ok("rewards: an open item pick is one row, open, its skip an ItemPickCommand", (
			rewards.size() == 1
			and rewards[0] is ItemPickReward
			and rewards[0].title == "Item pick"
			and rewards[0].detail == "Choose a weapon, or skip"
			and not rewards[0].is_taken()
			and VictoryRewards.open_of(rewards).size() == 1
			and not VictoryRewards.has_taken(rewards)
			and skip is ItemPickCommand
			and not rewards[0].picker_path.is_empty()
			and ResourceLoader.exists(rewards[0].picker_path)
	))
	pick.is_resolved = true
	pick.store(seat_run)
	var settled: Array[VictoryReward] = VictoryRewards.build(
			CombatResultsModel.build(session, 0, _catalog, _rules)
	)
	_ok("rewards: once settled, the row is taken and leaves the open list", (
			settled.size() == 1
			and settled[0].is_taken()
			and VictoryRewards.open_of(settled).is_empty()
			and VictoryRewards.has_taken(settled)
	))
	seat_run.pending_offers.erase(ItemPick.OFFER_KEY)
	_ok("rewards: with no pick (the Boss), none", (
			VictoryRewards.build(CombatResultsModel.build(session, 0, _catalog, _rules)).is_empty()
			and VictoryRewards.build(null).is_empty()
	))


func _test_xp_bar() -> void:
	var bar: XpBar = XP_BAR_SCENE.instantiate()
	_root.add_child(bar)
	bar.prepare(1, 90, 120, 100)
	var at_start: bool = bar.get_shown_level() == 1 and bar.get_shown_xp() == 90
	var fill: float = bar.fill_duration()
	var waiting: bool = bar.step(bar.fill_delay * 0.5) and bar.get_shown_xp() == 90
	bar.step(bar.fill_delay * 0.5 + fill * 0.5)
	var halfway: int = bar.get_shown_level() * 100 + bar.get_shown_xp()
	var still_holding: bool = bar.step(fill * 0.5 + bar.hold_time * 0.5)
	var done: bool = not bar.step(bar.hold_time)
	_ok("xp bar: waits, fills √gain ÷ 6 seconds, wraps at each level, then holds", (
			at_start
			and is_equal_approx(fill, sqrt(120.0) / 6.0)
			and waiting
			and halfway == 250
			and still_holding
			and done
			and bar.get_shown_level() == 3
			and bar.get_shown_xp() == 10
	), "half %d, end lv %d xp %d" % [halfway, bar.get_shown_level(), bar.get_shown_xp()])
	bar.prepare(2, 0, 64, 100)
	bar.finish()
	_ok("xp bar: finish jumps to the end", (
			not bar.is_running() and bar.get_shown_level() == 2 and bar.get_shown_xp() == 64
	))
	bar.free()


func _test_recap_stage() -> void:
	var stage: VictoryRecapStage = RECAP_SCENE.instantiate()
	_root.add_child(stage)
	var model: CombatResultsModel = _long_model(3)
	stage.show_recap(model)
	var rows: Array[UnitRecapRow] = stage.get_rows()
	_ok("recap: a row per standing unit, then the fallen; Standout and Fallen in words", (
			rows.size() == LONG_ARMY
			and rows[0].get_tag_text() == "Standout"
			and rows[1].get_tag_text().is_empty()
			and rows[LONG_ARMY - 1].get_tag_text() == "Fallen"
			and not rows[LONG_ARMY - 1].get_xp_bar().visible
	), "%d rows" % [rows.size()])
	stage.begin_fill()
	var steps: int = 0
	var order_ok: bool = true
	while stage.is_filling() and steps < LONG_ARMY * 2:
		var running: int = -1
		for i: int in rows.size():
			if rows[i].get_xp_bar().is_running():
				running = i
				break
		order_ok = order_ok and running == steps
		stage.step(LONG_STEP)
		steps += 1
	_ok("recap: the bars fill one after another, the fallen row has none", (
			order_ok and steps == LONG_ARMY - 1 and not stage.is_filling()
	), "%d steps" % [steps])
	var shown: PackedStringArray = []
	var index: int = 0
	while stage.show_level_up(index):
		shown.append(stage.get_level_up_card().get_text())
		index += 1
	_ok("recap: each level-up in the order reached, then none", (
			shown.size() == 3
			and shown[0].begins_with("Unit 1 | Level 2")
			and shown[2].begins_with("Unit 3 | Level 2")
			and not stage.get_level_up_card().visible
	), " / ".join(shown))
	stage.begin_fill()
	stage.finish_fill()
	_ok("recap: finishing ends every fill at once", (
			not stage.is_filling() and rows[0].get_xp_bar().get_shown_xp() == 50
	))
	stage.free()


## Opens the long recap in a small box with a button below it and focuses its first row; the
## scroll starts at the top.
func begin_scroll() -> void:
	var box: Control = Control.new()
	box.size = SCROLL_SIZE
	_root.add_child(box)
	_scroll_stage = RECAP_SCENE.instantiate()
	box.add_child(_scroll_stage)
	_scroll_stage.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	_scroll_stage.show_recap(_long_model(0))
	_below = Button.new()
	_below.text = "Continue"
	_below.position = Vector2(0.0, SCROLL_SIZE.y + 8.0)
	box.add_child(_below)
	_scroll_stage.link_focus(_below)
	_scroll_stage.get_rows()[0].grab_focus()


## Presses the d-pad down once per row but the first, as a pad moves along the recap.
func press_down() -> void:
	for _row: int in LONG_ARMY - 1:
		for is_down: bool in [true, false]:
			var event: InputEventJoypadButton = InputEventJoypadButton.new()
			event.device = 0
			event.button_index = JOY_BUTTON_DPAD_DOWN
			event.pressed = is_down
			_root.push_input(event, true)


## The last row has focus and is in view, the scroll moved; one more down reaches the button.
func finish_scroll() -> void:
	var rows: Array[UnitRecapRow] = _scroll_stage.get_rows()
	var scroll: ScrollContainer = _scroll_stage.get_scroll()
	var last: UnitRecapRow = rows[rows.size() - 1]
	var in_view: bool = scroll.get_global_rect().grow(1.0).encloses(last.get_global_rect())
	var focused: bool = last.has_focus()
	var moved: int = scroll.scroll_vertical
	for is_down: bool in [true, false]:
		var event: InputEventJoypadButton = InputEventJoypadButton.new()
		event.device = 0
		event.button_index = JOY_BUTTON_DPAD_DOWN
		event.pressed = is_down
		_root.push_input(event, true)
	_ok("recap (pad): the d-pad reaches the last of %d rows, scrolled into view" % [
		LONG_ARMY,
	], focused and in_view and moved > 0, "scroll %d, in view %s" % [moved, in_view])
	_ok("recap (pad): down from the last row reaches the button below", _below.has_focus())
	_scroll_stage.get_parent().free()


# A model of LONG_ARMY lines: units 1 to LONG_ARMY - 1 standing (the first the Standout, each
# gaining 50 from 0), the last fallen; level-ups for the first level_ups units.
func _long_model(level_ups: int) -> CombatResultsModel:
	var model: CombatResultsModel = CombatResultsModel.new()
	model.xp_per_level = 100
	model.has_stats = true
	for i: int in LONG_ARMY:
		var line: CombatResultsModel.XpLine = CombatResultsModel.XpLine.new()
		line.unit_id = "unit:%d" % [i + 1]
		line.name = "Unit %d" % [i + 1]
		line.stats = PackedInt32Array([i, i * 3, i * 2, 0])
		line.level = 1
		line.level_before = 1
		if i == LONG_ARMY - 1:
			line.is_fallen = true
			model.fallen_lines.append(line)
			continue
		line.award = _award(line.unit_id, 50, i == 0)
		line.xp = 50
		line.xp_before = 0
		model.xp_lines.append(line)
	for i: int in level_ups:
		var leveled: CombatResultsModel.LevelUpLine = CombatResultsModel.LevelUpLine.new()
		leveled.unit_id = "unit:%d" % [i + 1]
		leveled.name = "Unit %d" % [i + 1]
		leveled.level = 2
		leveled.gains = "HP +1"
		model.level_up_lines.append(leveled)
	return model


func _session() -> CampaignSession:
	var session: CampaignSession = CampaignSession.new(
			CampaignData.Mode.SOLO, RUN_SEED, PackedInt32Array([0])
	)
	var factions: Dictionary[int, String] = {0: MERCENARY}
	var start: RunStart = RunStart.build(
			load(RULES_PATH) as CampaignMapRules,
			session.rng.stream(RngKey.new(RngKey.RngPurpose.MAP_GENERATION)),
			_catalog,
			factions,
			session.ids
	)
	session.run = start.run
	return session


func _unit_at(unit: UnitInstance, level: int, xp: int) -> UnitInstance:
	unit.level = level
	unit.xp = xp
	return unit


func _award(unit_id: String, total: int, is_standout: bool) -> XpAward:
	var award: XpAward = XpAward.new()
	award.unit_id = unit_id
	award.total = total
	award.shared = 40
	award.is_standout = is_standout
	award.standout = 5 if is_standout else 0
	award.personal = total - award.shared - award.standout
	return award


func _level_up(unit_id: String, level: int) -> LevelUp:
	var reached: LevelUp = LevelUp.new()
	reached.unit_id = unit_id
	reached.level = level
	reached.gains = {CombatValue.Stat.HP: 1}
	return reached


# A combat report in seat_run's pending offers: grades paying 30 gold, the awards and level-ups,
# and stats for each of fought (2 kills, 14 dealt, 9 taken, 3 healed).
func _store_report(
		seat_run: SeatRun, awards: Array, level_ups: Array, fought: Array
) -> void:
	var grades: CombatGrades = CombatGrades.new()
	grades.base_gold = 30
	grades.gold = 30
	var xp_data: Array = []
	for award: XpAward in awards:
		xp_data.append(award.capture())
	var level_data: Array = []
	for reached: LevelUp in level_ups:
		level_data.append(reached.capture())
	var stats_data: Dictionary = {}
	for unit: UnitInstance in fought:
		stats_data[unit.instance_id] = {
			"kills": 2, "damage_dealt": 14, "damage_taken": 9, "healed": 3,
		}
	seat_run.pending_offers[CampaignRunState.COMBAT_REPORT_KEY] = {
		"grades": grades.capture(), "xp": xp_data, "level_ups": level_data, "stats": stats_data,
	}


# The first count weapon ids of the catalog, sorted.
func _weapon_ids(count: int) -> PackedStringArray:
	var found: PackedStringArray = []
	var ids: PackedStringArray = _catalog.ids()
	ids.sort()
	for id: String in ids:
		if found.size() >= count:
			break
		if _catalog.definition(id) is WeaponDefinition:
			found.append(id)
	return found


func _ok(case_name: String, passed: bool, detail: String = "") -> void:
	_check.call(case_name, passed, detail)
