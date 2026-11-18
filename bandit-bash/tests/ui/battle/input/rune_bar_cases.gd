# ==============================================================================
# Bandit Bash
# Copyright (c) 2026 Derc Development
# Licensed under the MIT License. See LICENSE.
#
# File:     rune_bar_cases.gd
# Author:
# Created:  November 18, 2026
# Modified: November 18, 2026
# ==============================================================================

extends "res://tests/ui/battle/input/rune_cases.gd"
## The rune bar's cases for the ui/input suite (combat UI plan, UI14 row): the bar showing every
## held rune with its icon and the pointed rune's text, dimming one with no target; after every
## unit has acted, one rune of each target kind (Mend, Recall, Spark) cast from the bar by keys,
## mouse and pad, every unit's acted state as it was; a cast and a cancel from MOVE returning to
## MOVE with the unit and cursor kept; the bar refusing, with its reason in the message, during
## playback, in the enemy phase, with no runes, with no target and while a unit acts; and a
## discard by keys, mouse and pad, asked first, cancelled back to the bar, then sent as
## [DiscardRuneCommand]. The harness and the device drivers are rune_cases.gd's.


## Runs every case.
func run() -> void:
	_map = load(M1_DEFINITION) as CombatMapDefinition
	if _map == null:
		_check.call("rune bar: the M1 map definition loads", false, M1_DEFINITION)
		return
	_test_display()
	for device: Device in [Device.KEYS, Device.MOUSE, Device.PAD]:
		_test_after_every_unit_acted(device)
	_test_from_move()
	_test_bar_refusals()
	for device: Device in [Device.KEYS, Device.MOUSE, Device.PAD]:
		_test_discard(device)


# The bar shows every held rune in slot order, each with its icon, Spark dimmed with no keg on the
# map; focused by open_runes, its text says the rune and, for Spark, why it can't be cast.
func _test_display() -> void:
	var h: TurnInputCases.Harness = _harness()
	if h == null:
		return
	var bar: RuneBar = h.controller.rune_bar
	var held: PackedStringArray = h.session.state.rune_slots.get(0, PackedStringArray())
	var shown: PackedStringArray = []
	var problems: PackedStringArray = []
	for i: int in bar.get_runes().size():
		var rune: TurnInputModel.HeldRune = bar.get_runes()[i]
		var slot: RuneSlotButton = bar.get_slots()[i]
		shown.append(rune.rune_id)
		if slot.get_icon() == null or slot.get_icon() != bar.icons.get(rune.definition_id, null):
			problems.append("%s has no icon of its own" % [rune.definition_id])
		var is_spark: bool = rune.definition_id == "spark"
		if slot.is_dimmed() != is_spark or (rune.option == null) != is_spark:
			problems.append("%s dimmed %s" % [rune.definition_id, slot.is_dimmed()])
	_check.call("display: every held rune, in slot order, with its icon; only Spark dimmed", (
			shown == held and problems.is_empty() and held.size() == RUNES.size()
	), "shown %s, held %s; %s" % [shown, held, "; ".join(problems)])

	_press(Device.KEYS, &"open_runes")
	var first: TurnInputModel.HeldRune = bar.get_runes()[0]
	var first_text: String = bar.get_text()
	var spark_text: String = ""
	for _i: int in bar.get_runes().size():
		_press(Device.KEYS, &"ui_right")
		if bar.get_focused_rune() == _rune_id_of(h.session, "spark"):
			spark_text = bar.get_text()
			break
	_check.call("display: the focused rune's text, and why Spark can't be cast now", (
			first_text == "%s: %s" % [first.label, first.text]
			and spark_text.ends_with("(%s)" % [TurnInputModel.NO_TARGET_REASON])
	), "first '%s', spark '%s'" % [first_text, spark_text])
	h.close()


# Every unit acts first; then Mend (one unit), Recall (a pair) and Spark (a keg) are cast from the
# bar by device, each returning to IDLE with every unit's acted state as it was.
func _test_after_every_unit_acted(device: Device) -> void:
	var tag: String = "after every unit acted (%s)" % [DEVICE_NAMES[device]]
	var h: TurnInputCases.Harness = _harness(true)
	if h == null:
		return
	var session: CombatSession = h.session
	for unit_id: String in TurnInputModel.acting_units(session, 0):
		_send(h, UnitTurnCommand.new(0, unit_id, UnitTurnCommand.Action.WAIT))
	var all_acted: bool = TurnInputModel.acting_units(session, 0).is_empty()
	var before: Dictionary[String, String] = _acted_states(session)
	var failed: PackedStringArray = []
	for definition_id: String in ["mend", "recall", "spark"]:
		var rune_id: String = _rune_id_of(session, definition_id)
		var aim: Array = _aim(h, definition_id, "", _kegs)
		if aim.is_empty():
			failed.append("%s: nothing to aim at" % [definition_id])
			continue
		var target_id: String = aim[0]
		var second_id: String = aim[1]
		var problem: String = _cast(h, device, rune_id, target_id, second_id)
		if problem.is_empty():
			problem = _cast_landed(h, rune_id)
		var changed: PackedStringArray = _acted_changes(before, session)
		if problem.is_empty() and not changed.is_empty():
			problem = "acted states changed: %s" % [", ".join(changed)]
		if not problem.is_empty():
			failed.append("%s: %s" % [definition_id, problem])
	_check.call(tag + ": one rune of each kind is cast, no unit's acted state changes", (
			all_acted and failed.is_empty() and h.controller.get_stage() == IDLE
	), "all acted %s; %s" % [all_acted, "; ".join(failed)])
	h.close()


# From MOVE (a unit selected, the cursor on one of its move tiles): open_runes and cancel return
# to MOVE as it was; Aegis cast on another unit from a click on its slot returns to MOVE with the
# same unit selected, the cursor where it was, and no unit's acted state changed.
func _test_from_move() -> void:
	var h: TurnInputCases.Harness = _harness()
	if h == null:
		return
	var c: BattleController = h.controller
	var session: CombatSession = h.session
	var caster: String = _caster(h)
	c.move_cursor(session.state.tile_of(caster))
	_press(Device.KEYS, &"ui_accept")
	for tile: Vector2i in TurnInputModel.move_tiles(session, caster):
		if tile != session.state.tile_of(caster):
			c.move_cursor(tile)
			break
	var cursor: Vector2i = c.get_cursor_tile()
	var walk: Array[Vector2i] = c.get_walk()
	_press(Device.KEYS, &"open_runes")
	var opened: bool = c.get_stage() == RUNE_SLOTS and c.get_selected_unit() == caster
	_press(Device.KEYS, &"ui_cancel")
	_check.call("from MOVE: open_runes then cancel return to MOVE, unit, cursor and walk kept", (
			opened and c.get_stage() == MOVE and c.get_selected_unit() == caster
			and c.get_cursor_tile() == cursor and c.get_walk() == walk and not walk.is_empty()
	), "opened %s, stage %d, unit %s, cursor %s (was %s), walk %s (was %s)" % [
		opened, c.get_stage(), c.get_selected_unit(), c.get_cursor_tile(), cursor,
		c.get_walk(), walk,
	])

	var other: String = ""
	for unit_id: String in session.state.units_of(PLAYER):
		if unit_id != caster:
			other = unit_id
			break
	var before: Dictionary[String, String] = _acted_states(session)
	var problem: String = _cast(h, Device.MOUSE, _rune_id_of(session, "aegis"), other, "")
	_check.call("from MOVE: a cast from the bar returns to MOVE, unit and cursor kept", (
			problem.is_empty() and c.get_stage() == MOVE and c.get_selected_unit() == caster
			and c.get_cursor_tile() == cursor and _acted_changes(before, session).is_empty()
	), "%s; stage %d, unit %s, cursor %s (was %s)" % [
		problem, c.get_stage(), c.get_selected_unit(), c.get_cursor_tile(), cursor,
	])
	h.close()


# The bar refuses, saying why in the message and changing nothing: during playback (End Turn's
# enemy phase playing), in the enemy phase, while a unit's menu is open, for a rune with no
# target, and with every slot empty, when open_runes leaves the hints.
func _test_bar_refusals() -> void:
	var h: TurnInputCases.Harness = _harness()
	if h == null:
		return
	var c: BattleController = h.controller
	var session: CombatSession = h.session
	var bar: RuneBar = c.rune_bar
	var first: RuneSlotButton = bar.get_slots()[0]
	var said: PackedStringArray = []
	var stages: Array[BattleController.Stage] = []

	# End Turn sent straight to the encounter, as a co-op partner's would arrive: the controller
	# stays in IDLE while the board plays it.
	h.battle.submit(EndTurnCommand.new(0), session.session_id)
	h.battle.resolve_queued()
	_press(Device.KEYS, &"open_runes")
	said.append(h.message.get_text())
	stages.append(c.get_stage())
	BattleViewCases.settle(h.view)
	var sent: int = h.batches.size()

	session.state.phase_side = ENEMY
	_press(Device.PAD, &"open_runes")
	said.append(h.message.get_text())
	stages.append(c.get_stage())
	_click_control(h, first.get_slot_button())
	said.append(h.message.get_text())
	stages.append(c.get_stage())
	session.state.phase_side = PLAYER

	var caster: String = _caster(h)
	_open_rune_menu(h, Device.KEYS, caster)
	_press(Device.KEYS, &"ui_cancel")
	_click_control(h, first.get_slot_button())
	said.append(h.message.get_text())
	stages.append(c.get_stage())
	while c.step_back():
		pass

	var spark: int = -1
	for i: int in bar.get_runes().size():
		if bar.get_runes()[i].definition_id == "spark":
			spark = i
	if spark >= 0:
		_click_control(h, bar.get_slots()[spark].get_slot_button())
	said.append(h.message.get_text())
	stages.append(c.get_stage())

	var expected: PackedStringArray = [
		"Runes: %s" % [BattleController.RUNES_PLAYING],
		"Runes: %s" % [BattleController.RUNES_ENEMY_PHASE],
		"Runes: %s" % [BattleController.RUNES_ENEMY_PHASE],
		"Runes: %s" % [BattleController.RUNES_UNIT_BUSY],
		"Spark: %s." % [TurnInputModel.NO_TARGET_REASON],
	]
	var expected_stages: Array[BattleController.Stage] = [IDLE, IDLE, IDLE, ACTION, IDLE]
	_check.call("refusals: playback, the enemy phase, a unit's action, no target: each says why", (
			said == expected and stages == expected_stages and h.batches.size() == sent
	), "said %s, stages %s, sent %d" % [said, stages, h.batches.size() - sent])

	# Every slot emptied (test setup only), then bound again so the bar reads it.
	session.state.rune_slots[0] = PackedStringArray()
	c.bind(h.battle, session, 0)
	_press(Device.KEYS, &"open_runes")
	var empty: bool = true
	for slot: RuneSlotButton in bar.get_slots():
		empty = empty and slot.is_empty()
	_check.call("refusals: no runes: empty slots, open_runes says why and isn't hinted", (
			h.message.get_text() == "Runes: %s" % [BattleController.RUNES_NONE]
			and c.get_stage() == IDLE and empty
			and bar.get_slots().size() == SeatRun.RUNE_SLOT_COUNT
			and not c.get_live_actions().has(&"open_runes")
	), "message '%s', stage %d, empty %s, slots %d, live %s" % [
		h.message.get_text(), c.get_stage(), empty, bar.get_slots().size(), c.get_live_actions(),
	])
	h.close()


# A discard by device: the bar's X (down from the rune, or a click) asks first; cancel returns
# there; confirmed, DiscardRuneCommand removes the rune with a Rune discarded fact and no cast,
# and no unit's acted state changes.
func _test_discard(device: Device) -> void:
	var tag: String = "discard (%s)" % [DEVICE_NAMES[device]]
	var h: TurnInputCases.Harness = _harness()
	if h == null:
		return
	var c: BattleController = h.controller
	var session: CombatSession = h.session
	var bar: RuneBar = c.rune_bar
	var rune_id: String = bar.get_runes()[0].rune_id
	var before: Dictionary[String, String] = _acted_states(session)
	var sent: int = h.batches.size()
	_open_discard(h, device)
	var asked: bool = c.get_stage() == DISCARD_CONFIRM and h.host.top() is ConfirmDialog
	_cancel(h, device)
	var back: BattleController.Stage = c.get_stage()
	var expected_back: BattleController.Stage = IDLE if device == Device.MOUSE else RUNE_SLOTS
	var refocused: bool = device == Device.MOUSE or bar.get_focused_rune() == rune_id
	_check.call(tag + ": X asks first, and cancel steps back to where it was asked from", (
			asked and back == expected_back and refocused and h.batches.size() == sent
	), "asked %s, back to %d, focus %s" % [asked, back, bar.get_focused_rune()])
	if device != Device.MOUSE:
		_press(device, &"ui_cancel")

	_open_discard(h, device)
	var dialog: ConfirmDialog = h.host.top() as ConfirmDialog
	if dialog != null and device == Device.MOUSE:
		_click_control(h, dialog.get_confirm_button())
	elif dialog != null:
		dialog.get_confirm_button().grab_focus()
		_press(device, &"ui_accept")
	BattleViewCases.settle(h.view)
	var batch: CombatSession.FactBatch = h.last_batch()
	var discarded: bool = false
	var cast: bool = false
	if batch != null and not batch.is_rejected():
		for fact: CombatFact in batch.facts:
			discarded = discarded or (
					fact.kind == CombatFact.Kind.RUNE_DISCARDED and fact.item_id == rune_id
					and fact.amount == 0
			)
			cast = cast or fact.kind == CombatFact.Kind.RUNE_USED
	var left: PackedStringArray = session.state.rune_slots.get(0, PackedStringArray())
	_check.call(tag + ": confirmed, the rune is discarded uncast, and the flow is back in IDLE", (
			discarded and not cast and not left.has(rune_id) and left.size() == RUNES.size() - 1
			and c.get_stage() == IDLE and _acted_changes(before, session).is_empty()
			and bar.get_runes().size() == left.size()
	), "discarded %s, cast %s, left %d, stage %d" % [discarded, cast, left.size(), c.get_stage()])
	h.close()


# Opens the discard question for the bar's first rune by device: a click on its X, or open_runes,
# down to its X and accept.
func _open_discard(h: TurnInputCases.Harness, device: Device) -> void:
	var bar: RuneBar = h.controller.rune_bar
	var slot: RuneSlotButton = bar.get_slots()[0]
	if device == Device.MOUSE:
		_click_control(h, slot.get_discard_button())
		return
	if h.controller.get_stage() != RUNE_SLOTS:
		_press(device, &"open_runes")
	slot.get_slot_button().grab_focus()
	_press(device, &"ui_down")
	_press(device, &"ui_accept")


# Every unit's acted and second-move state, by unit.
static func _acted_states(session: CombatSession) -> Dictionary[String, String]:
	var states: Dictionary[String, String] = {}
	for unit_id: String in session.state.unit_ids():
		var unit: CombatUnitState = session.state.unit(unit_id)
		states[unit_id] = "%s/%s" % [unit.has_acted, unit.is_second_move_pending]
	return states


# The units still on the map whose acted or second-move state differs from before; a unit a rune
# defeated (Spark's blast) has no state left to compare.
static func _acted_changes(
		before: Dictionary[String, String], session: CombatSession
) -> PackedStringArray:
	var changed: PackedStringArray = []
	var now: Dictionary[String, String] = _acted_states(session)
	for unit_id: String in now:
		if before.get(unit_id, now[unit_id]) != now[unit_id]:
			changed.append("%s %s -> %s" % [unit_id, before[unit_id], now[unit_id]])
	return changed
