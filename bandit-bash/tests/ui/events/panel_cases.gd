# ==============================================================================
# Bandit Bash
# Copyright (c) 2026 Derc Development
# Licensed under the MIT License. See LICENSE.
#
# File:     panel_cases.gd
# Author:
# Created:  November 19, 2026
# Modified: November 19, 2026
# ==============================================================================

extends RefCounted
## The event panel's parts over runs in memory: the story and its placeholder art; a greyed
## option's reason on its card, out of the focus order; a cursed option naming its curse with
## tier and effect, and its rolled weapon, before it is chosen; each chooser's entries and why
## one is greyed (the commander for a prefix re-roll, a weapon a prefix doesn't fit, a modified
## weapon shown Infused, the fallen, the rune slots); Back by Esc, B and a click out of the saved
## chooser (closing it), out of a placement and out of the rune discard; a rejected choice's
## reason on the status line; the outcome's summary; and an event the pool lacks, shown closed
## with Leave.

# The suite that runs this file; tests/case_files.gd finds it by this line.
const SUITE: String = "ui/events"

const Fixture = preload("res://tests/ui/events/event_screen_fixture.gd")

var _check: Callable
var _root: Window = null
var _fx: Fixture = null


## [param check]: called as check(case_name: String, passed: bool, detail: String).
## [param root]: the root viewport, where the panels are added and input is pushed.
func _init(check: Callable, root: Window) -> void:
	_check = check
	_root = root
	_fx = Fixture.new(root)


func run() -> void:
	if not _fx.base.is_ready():
		_ok("the fixture's catalog and rules load", false)
		return
	_test_story()
	_test_greyed()
	_test_named_curse()
	_test_unit_chooser()
	_test_weapon_chooser()
	_test_fallen_and_rune_choosers()
	_test_back()
	_test_rejected()
	_test_summary()
	_test_closed()


func _test_story() -> void:
	var made: CampaignSession = _fx.session_with(Fixture.runes())
	var panel: EventPanel = _fx.open_panel(made)
	var story: EventStory = panel.get_story()
	_ok("story: the event's name and text, with the placeholder in its art slot", (
			story.get_title_text() == "The Humming Stone"
			and story.get_text().contains(Fixture.RUNES) and story.is_placeholder_shown()
			and panel.get_cards().size() == 3
	), story.get_title_text())
	_fx.close_panel(panel)


func _test_greyed() -> void:
	var made: CampaignSession = _fx.session_with(Fixture.runes())
	var panel: EventPanel = _fx.open_panel(made)
	var cards: Array[EventOptionCard] = panel.get_cards()
	var tithe: EventOptionCard = cards[Fixture.TITHE]
	panel.focus_first()
	_fx.press_key(KEY_RIGHT)
	var skipped: bool = _root.gui_get_focus_owner() == cards[Fixture.WALK_AWAY]
	_ok("greyed: Pay the Tithe says why on its card, can't be pressed or focused", (
			tithe.disabled and tithe.focus_mode == Control.FOCUS_NONE
			and tithe.text.contains("Can't choose: needs %d gold." % [Fixture.TITHE_GOLD])
			and tithe.problem == "needs %d gold" % [Fixture.TITHE_GOLD]
			and skipped
	), tithe.text)
	_fx.close_panel(panel)


func _test_named_curse() -> void:
	var made: CampaignSession = _fx.session_with(Fixture.trials())
	var panel: EventPanel = _fx.open_panel(made)
	var rolls: EventRolls = made.run.events.seat_event(0).rolls_of(Fixture.PRIZE)
	var curse: CurseDefinition = _fx.base.catalog.curse(rolls.curse_id)
	var weapon: ItemDefinition = _fx.base.catalog.item(rolls.pick(0))
	var text: String = panel.get_cards()[Fixture.PRIZE].text
	_ok("curse: Take the Prize names its weapon and its curse, tier and effect before choosing", (
			curse != null and weapon != null
			and text.contains("Gain %s (Rare" % [weapon.display_name])
			and text.contains("Curse: %s (Minor curse). %s" % [
				curse.display_name, curse.describe()[0],
			])
	), text)
	_fx.close_panel(panel)


func _test_unit_chooser() -> void:
	var made: CampaignSession = _fx.session_with(Fixture.mirror())
	var seat_run: SeatRun = made.run.seat_run(0)
	var panel: EventPanel = _fx.open_panel(made)
	panel.get_cards()[0].pressed.emit()
	var chooser: EventChooser = panel.get_chooser()
	var buttons: Array[Button] = chooser.get_choice_buttons()
	var commander_at: int = -1
	for index: int in seat_run.army.size():
		if seat_run.army[index].instance_id == seat_run.commander_id:
			commander_at = index
	var commander: Button = buttons[commander_at] if commander_at >= 0 else null
	var commander_name: String = EventScreenModel.title_of(
			seat_run.unit(seat_run.commander_id), _fx.base.catalog
	)
	var others_open: bool = true
	for index: int in seat_run.army.size():
		others_open = others_open and (index == commander_at or not buttons[index].disabled)
	_ok("unit chooser: every living unit with its HP, the commander greyed with why; Back last", (
			chooser.get_question() == "Face Yourself: which unit?"
			and buttons.size() == seat_run.army.size() + 1 and buttons[-1].text == "Back"
			and commander != null and commander.disabled
			and commander.focus_mode == Control.FOCUS_NONE
			and commander.text.contains("(%s is a commander, which never has a prefix)" % [
				commander_name,
			])
			and buttons[0].text.contains("HP ") and others_open
	), "" if commander == null else commander.text)
	_fx.close_panel(panel)


func _test_weapon_chooser() -> void:
	var made: CampaignSession = _fx.session_with(Fixture.forge())
	var seat_run: SeatRun = made.run.seat_run(0)
	var archer: UnitInstance = _fx.base.unit_of_type(seat_run, "archer")
	var bow: ItemInstance = seat_run.items[archer.weapon_id]
	bow.stat_deltas.append(ItemInstance.StatDelta.new(
			CombatValue.Key.NET_WEIGHT, Fixture.WEIGHT_GAIN, "test", "Test"
	))
	var panel: EventPanel = _fx.open_panel(made)
	panel.get_cards()[0].pressed.emit()
	var buttons: Array[Button] = panel.get_chooser().get_choice_buttons()
	var bow_button: Button = Fixture.button_starting(buttons, "Infused ")
	var lance: Button = Fixture.button_starting(buttons, "Simple Lance")
	_ok("weapon chooser: held weapons by holder; a modified bow Infused; a lance greyed: no fit", (
			bow_button != null and not bow_button.disabled
			and bow_button.text.contains(", on Archer")
			and lance != null and lance.disabled
			and lance.text.contains("doesn't fit a lance")
	), " | ".join(_texts(buttons)))
	_fx.close_panel(panel)


func _test_fallen_and_rune_choosers() -> void:
	var made: CampaignSession = _fx.session_with(Fixture.shrine(), 1, true)
	var fallen: UnitInstance = made.run.seat_run(0).fallen[0]
	var panel: EventPanel = _fx.open_panel(made)
	panel.get_cards()[Fixture.PRAYER].pressed.emit()
	var buttons: Array[Button] = panel.get_chooser().get_choice_buttons()
	_ok("fallen chooser: the fallen unit by name and max HP, then Back", (
			buttons.size() == 2 and buttons[0].text.begins_with(
					EventScreenModel.title_of(fallen, _fx.base.catalog)
			)
			and buttons[0].text.contains("fallen (max HP ") and not buttons[0].disabled
	), " | ".join(_texts(buttons)))
	_fx.close_panel(panel)

	var with_runes: CampaignSession = _fx.session_with(Fixture.runes(), 1, false, true)
	var rune_panel: EventPanel = _fx.open_panel(with_runes)
	rune_panel.get_cards()[Fixture.RUNE_STONE].pressed.emit()
	var slots: Array[Button] = rune_panel.get_chooser().get_choice_buttons()
	var first: RuneDefinition = _fx.base.catalog.rune(
			with_runes.run.seat_run(0).rune_slots[0].definition_id
	)
	_ok("rune chooser: each full slot's rune to discard, then Back", (
			rune_panel.get_step() == EventPanel.Step.RUNE
			and slots.size() == SeatRun.RUNE_SLOT_COUNT + 1
			and slots[0].text == "Discard %s" % [first.display_name]
			and rune_panel.get_chooser().get_question().contains("Every rune slot is full")
	), " | ".join(_texts(slots)))
	_fx.close_panel(rune_panel)


func _test_back() -> void:
	for device: String in ["key", "pad", "mouse"]:
		var made: CampaignSession = _fx.session_with(Fixture.trials())
		var panel: EventPanel = _fx.open_panel(made)
		panel.get_cards()[Fixture.STEADY_HAND].pressed.emit()
		var opened: bool = made.run.events.seat_event(0).choosing == Fixture.STEADY_HAND
		_fx.back(device, panel.get_chooser().get_choice_buttons()[-1])
		_ok("back %s: out of the saved unit chooser, which closes, to the cards" % [device], (
				opened and panel.get_step() == EventPanel.Step.OPTIONS
				and made.run.events.seat_event(0).choosing == EventRunState.NO_OPTION
				and not _root.get_tree().paused
		), str(EventPanel.Step.find_key(panel.get_step())))
		_fx.close_panel(panel)

	var prize_run: CampaignSession = _fx.session_with(Fixture.trials())
	var prize: EventPanel = _fx.open_panel(prize_run)
	prize.get_cards()[Fixture.PRIZE].pressed.emit()
	var placing: bool = prize.get_step() == EventPanel.Step.PLACEMENT
	_fx.press_key(KEY_ESCAPE)
	_ok("back: Esc out of the placement returns to the cards, nothing taken", (
			placing and prize.get_step() == EventPanel.Step.OPTIONS
			and not prize.get_placement_panel().visible
			and prize_run.run.events.seat_event(0).chosen == EventRunState.NO_OPTION
	), str(EventPanel.Step.find_key(prize.get_step())))
	_fx.close_panel(prize)

	var rune_run: CampaignSession = _fx.session_with(Fixture.runes(), 1, false, true)
	var runes: EventPanel = _fx.open_panel(rune_run)
	runes.get_cards()[Fixture.RUNE_STONE].pressed.emit()
	_fx.press_pad(JOY_BUTTON_B)
	_ok("back: B out of the rune discard returns to the cards", (
			runes.get_step() == EventPanel.Step.OPTIONS
	), str(EventPanel.Step.find_key(runes.get_step())))
	_fx.close_panel(runes)


func _test_rejected() -> void:
	var made: CampaignSession = _fx.session_with(Fixture.trials())
	var seat_run: SeatRun = made.run.seat_run(0)
	var soldier: UnitInstance = _fx.base.soldier(seat_run)
	var panel: EventPanel = _fx.open_panel(made)
	panel.get_cards()[Fixture.STEADY_HAND].pressed.emit()
	var button: Button = panel.get_chooser().get_choice_buttons()[seat_run.army.find(soldier)]
	_fx.base.fell(seat_run, soldier)
	button.pressed.emit()
	_ok("rejected: a choice the run refuses says why and stays in the chooser", (
			panel.get_step() == EventPanel.Step.CHOOSER
			and panel.get_status_text().begins_with("Can't do that: ")
			and panel.get_status_text().contains("isn't a living unit")
			and made.run.events.seat_event(0).chosen == EventRunState.NO_OPTION
	), panel.get_status_text())
	_fx.close_panel(panel)


func _test_summary() -> void:
	var made: CampaignSession = _fx.session_with(Fixture.trials())
	var rolls: EventRolls = made.run.events.seat_event(0).rolls_of(Fixture.PRIZE)
	var panel: EventPanel = _fx.open_panel(made)
	panel.get_cards()[Fixture.PRIZE].pressed.emit()
	Fixture.button_starting(
			panel.get_placement_panel().get_choice_buttons(), "Send it to the convoy"
	).pressed.emit()
	var lines: String = panel.get_summary().get_lines()
	var weapon: ItemDefinition = _fx.base.catalog.item(rolls.pick(0))
	var curse: CurseDefinition = _fx.base.catalog.curse(rolls.curse_id)
	var leave: Button = panel.get_leave_button()
	_ok("summary: what the option gave by name, its curse with tier; Leave focused", (
			panel.get_summary().get_heading() == "You chose Take the Prize"
			and lines.contains("Gained %s (Rare" % [weapon.display_name])
			and lines.contains("Cursed: %s (Minor curse)." % [curse.display_name])
			and leave.visible and leave.text == "Leave" and not leave.disabled
			and panel.focus_first() and _root.gui_get_focus_owner() == leave
	), lines)
	_fx.close_panel(panel)


func _test_closed() -> void:
	var made: CampaignSession = _fx.session_with(Fixture.trials())
	_fx.pool = EventPool.new([])
	var panel: EventPanel = _fx.open_panel(made)
	_ok("closed: an event the pool lacks says so, with Leave and no cards", (
			panel.get_step() == EventPanel.Step.CLOSED
			and panel.get_story().get_title_text() == "This event can't be shown"
			and panel.get_story().get_text().contains(Fixture.TRIALS)
			and panel.get_cards().is_empty() and panel.get_leave_button().visible
			and not panel.get_leave_button().disabled
	), panel.get_story().get_text())
	_fx.close_panel(panel)


func _texts(buttons: Array[Button]) -> PackedStringArray:
	var texts: PackedStringArray = []
	for button: Button in buttons:
		texts.append(button.text)
	return texts


func _ok(case_name: String, passed: bool, detail: String = "") -> void:
	_check.call("events panel %s" % [case_name], passed, detail)
