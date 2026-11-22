# ==============================================================================
# Bandit Bash
# Copyright (c) 2026 Derc Development
# Licensed under the MIT License. See LICENSE.
#
# File:     option_device_cases.gd
# Author:
# Created:  November 19, 2026
# Modified: November 22, 2026
# ==============================================================================

extends RefCounted
## Every option kind of the event panel chosen by keyboard (arrows and Enter), mouse (clicks) and
## pad (d-pad and A), each on a new run in memory with its event open: an option with nothing to
## pick (Walk Away); a chosen unit (+2 MGT), through the saved chooser stage; a chosen weapon
## (+2 weight, Infused); a new item placed in the convoy, with its minor curse; a rune taking a
## full slot's place; a fallen unit revived; a solo team choice taken as an ordinary choice; a
## surprise combat left pending, its Leave become Fight. Each ends on the outcome with the change
## made in the run.

# The suite that runs this file; tests/case_files.gd finds it by this line.
const SUITE: String = "ui/events"

const Fixture = preload("res://tests/ui/events/event_screen_fixture.gd")

const DEVICES: PackedStringArray = ["key", "mouse", "pad"]

var _check: Callable
var _fx: Fixture = null


## [param check]: called as check(case_name: String, passed: bool, detail: String).
## [param root]: the root viewport, where the panels are added and input is pushed.
func _init(check: Callable, root: Window) -> void:
	_check = check
	_fx = Fixture.new(root)


func run() -> void:
	_ok("devices: the fixture's catalog and rules load", _fx.base.is_ready())
	if not _fx.base.is_ready():
		return
	for device: String in DEVICES:
		_test_plain(device)
		_test_unit(device)
		_test_weapon(device)
		_test_placement(device)
		_test_rune(device)
		_test_fallen(device)
		_test_team_solo(device)
		_test_combat(device)


func _test_plain(device: String) -> void:
	var made: CampaignSession = _fx.session_with(Fixture.runes())
	var panel: EventPanel = _fx.open_panel(made)
	var pressed: bool = _press_card(panel, device, Fixture.WALK_AWAY)
	_ok("%s: Walk Away, with nothing to pick, resolves at once to the outcome" % [device], (
			pressed and _is_done(panel, Fixture.WALK_AWAY)
			and panel.get_summary().get_heading() == "You chose Walk Away"
	), _state(panel))
	_fx.close_panel(panel)


func _test_unit(device: String) -> void:
	var made: CampaignSession = _fx.session_with(Fixture.trials())
	var seat_run: SeatRun = made.run.seat_run(0)
	var soldier: UnitInstance = _fx.base.soldier(seat_run)
	var panel: EventPanel = _fx.open_panel(made)
	var pressed: bool = _press_card(panel, device, Fixture.STEADY_HAND)
	var saved_chooser: bool = (
			panel.get_step() == EventPanel.Step.CHOOSER
			and made.run.events.seat_event(0).choosing == Fixture.STEADY_HAND
	)
	var target: Button = panel.get_chooser().get_choice_buttons()[seat_run.army.find(soldier)]
	var chose: bool = _fx.press(device, target, "down")
	_ok("%s: Steady Hand opens the saved unit chooser; the soldier chosen gains +2 MGT" % [
		device,
	], (
			pressed and saved_chooser and chose and _is_done(panel, Fixture.STEADY_HAND)
			and soldier.stat_deltas.size() == 1
			and soldier.stat_deltas[0].amount == float(Fixture.MGT_GAIN)
			and soldier.stat_deltas[0].source_id == Fixture.TRIALS
	), _state(panel))
	_fx.close_panel(panel)


func _test_weapon(device: String) -> void:
	var made: CampaignSession = _fx.session_with(Fixture.trials())
	var seat_run: SeatRun = made.run.seat_run(0)
	var panel: EventPanel = _fx.open_panel(made)
	var pressed: bool = _press_card(panel, device, Fixture.TEMPER)
	var buttons: Array[Button] = panel.get_chooser().get_choice_buttons()
	var weapon_ids: PackedStringArray = _weapon_ids(made, panel)
	var chose: bool = buttons.size() > 2 and _fx.press(device, buttons[1], "down")
	var weapon: ItemInstance = (
			seat_run.items.get(weapon_ids[1], null) if weapon_ids.size() > 1 else null
	)
	_ok("%s: Temper the Blade opens the weapon chooser; the second weapon is Infused" % [
		device,
	], (
			pressed and chose and _is_done(panel, Fixture.TEMPER) and weapon != null
			and weapon.is_modified() and EventScreenModel.held_item_name(
					weapon, _fx.base.catalog
			).begins_with("Infused ")
	), _state(panel))
	_fx.close_panel(panel)


func _test_placement(device: String) -> void:
	var made: CampaignSession = _fx.session_with(Fixture.trials())
	var seat_run: SeatRun = made.run.seat_run(0)
	var convoy_before: int = seat_run.convoy.size()
	var curses_before: int = seat_run.heirloom_ids().size()
	var panel: EventPanel = _fx.open_panel(made)
	var card_text: String = _card_text(panel, Fixture.PRIZE)
	var pressed: bool = _press_card(panel, device, Fixture.PRIZE)
	var placing: bool = panel.get_step() == EventPanel.Step.PLACEMENT
	var convoy: Button = Fixture.button_starting(
			panel.get_placement_panel().get_choice_buttons(), "Send it to the convoy"
	)
	var chose: bool = convoy != null and _fx.press(device, convoy, "down")
	_ok("%s: Take the Prize names its weapon and curse, asks where it goes; the convoy takes it" % [
		device,
	], (
			card_text.contains("Gain ") and card_text.contains("(Minor curse)")
			and pressed and placing and chose and _is_done(panel, Fixture.PRIZE)
			and seat_run.convoy.size() == convoy_before + 1
			and seat_run.heirloom_ids().size() == curses_before + 1
			and not panel.get_placement_panel().visible
	), _state(panel))
	_fx.close_panel(panel)


func _test_rune(device: String) -> void:
	var made: CampaignSession = _fx.session_with(Fixture.runes(), 1, false, true)
	var seat_run: SeatRun = made.run.seat_run(0)
	var old_slot: String = seat_run.rune_slots[1].instance_id
	var panel: EventPanel = _fx.open_panel(made)
	var says_full: bool = _card_text(panel, Fixture.RUNE_STONE).contains("Every rune slot is full")
	var pressed: bool = _press_card(panel, device, Fixture.RUNE_STONE)
	var discarding: bool = panel.get_step() == EventPanel.Step.RUNE
	var buttons: Array[Button] = panel.get_chooser().get_choice_buttons()
	var chose: bool = buttons.size() == SeatRun.RUNE_SLOT_COUNT + 1 and _fx.press(
			device, buttons[1], "down"
	)
	var picked: String = made.run.events.seat_event(0).rolls_of(Fixture.RUNE_STONE).pick(0)
	_ok("%s: Rune Stone with every slot full asks which to discard; slot 2 takes the new rune" % [
		device,
	], (
			says_full and pressed and discarding and chose
			and _is_done(panel, Fixture.RUNE_STONE)
			and seat_run.rune_slots[1].instance_id != old_slot
			and seat_run.rune_slots[1].definition_id == picked
	), _state(panel))
	_fx.close_panel(panel)


func _test_fallen(device: String) -> void:
	var made: CampaignSession = _fx.session_with(Fixture.shrine(), 1, true)
	var seat_run: SeatRun = made.run.seat_run(0)
	var fallen: UnitInstance = seat_run.fallen[0]
	var panel: EventPanel = _fx.open_panel(made)
	var pressed: bool = _press_card(panel, device, Fixture.PRAYER)
	var buttons: Array[Button] = panel.get_chooser().get_choice_buttons()
	var lists_fallen: bool = (
			panel.get_step() == EventPanel.Step.CHOOSER and buttons.size() == 2
			and buttons[0].text.contains("fallen")
	)
	var chose: bool = _fx.press(device, buttons[0], "down")
	_ok("%s: Offer a Prayer lists the fallen; the one chosen rejoins the army" % [device], (
			pressed and lists_fallen and chose and _is_done(panel, Fixture.PRAYER)
			and seat_run.fallen.is_empty() and seat_run.army.has(fallen)
	), _state(panel))
	_fx.close_panel(panel)


func _test_team_solo(device: String) -> void:
	var made: CampaignSession = _fx.session_with(Fixture.toll())
	var seat_run: SeatRun = made.run.seat_run(0)
	var gold_before: int = seat_run.gold
	var panel: EventPanel = _fx.open_panel(made)
	var hides_votes: bool = not panel.get_vote_status().visible
	var pressed: bool = _press_card(panel, device, Fixture.INTIMIDATE)
	_ok("%s: a solo team choice shows no vote and Intimidate resolves as an ordinary choice" % [
		device,
	], (
			hides_votes and panel.get_step() != EventPanel.Step.VOTE and pressed
			and _is_done(panel, Fixture.INTIMIDATE)
			and seat_run.gold == gold_before + Fixture.LOOT_GOLD
			and panel.get_leave_button().text == "Leave"
	), _state(panel))
	_fx.close_panel(panel)


func _test_combat(device: String) -> void:
	var made: CampaignSession = _fx.session_with(Fixture.toll())
	var panel: EventPanel = _fx.open_panel(made)
	var pressed: bool = _press_card(panel, device, Fixture.FIGHT)
	var leave: Button = panel.get_leave_button()
	_ok("%s: Fight leaves a surprise combat pending; the outcome's button is Fight" % [device], (
			pressed and _is_done(panel, Fixture.FIGHT)
			and made.run.events.is_combat_pending_at(made.run.floor_number, made.run.node)
			and leave.visible and leave.text == "Fight" and not leave.disabled
			and panel.get_summary().get_lines().contains("surprise combat")
	), _state(panel))
	_fx.close_panel(panel)


# --- Helpers -----------------------------------------------------------------------------------


# Presses option index's card with device, from the first focusable card for key and pad.
func _press_card(panel: EventPanel, device: String, index: int) -> bool:
	var cards: Array[EventOptionCard] = panel.get_cards()
	if index >= cards.size() or cards[index].disabled:
		return false
	panel.focus_first()
	return _fx.press(device, cards[index], "right")


func _card_text(panel: EventPanel, index: int) -> String:
	var cards: Array[EventOptionCard] = panel.get_cards()
	return cards[index].get_card_text() if index < cards.size() else ""


# The weapon ids the Temper chooser lists for seat 0 of made, in its order.
func _weapon_ids(made: CampaignSession, panel: EventPanel) -> PackedStringArray:
	var ids: PackedStringArray = []
	var view: EventView = panel.get_view()
	if not view.is_open():
		return ids
	for entry: EventScreenModel.Entry in EventScreenModel.chooser_entries(
			made.run, 0, view.event, Fixture.TEMPER, _fx.base.catalog
	):
		ids.append(entry.id)
	return ids


# Whether panel shows the outcome of option index, chosen and saved.
func _is_done(panel: EventPanel, index: int) -> bool:
	return (
			panel.get_step() == EventPanel.Step.OUTCOME
			and panel.get_view().chosen == index
	)


func _state(panel: EventPanel) -> String:
	return "step %s; status '%s'; %s" % [
		str(EventPanel.Step.find_key(panel.get_step())), panel.get_status_text(),
		"" if _fx.last_batch == null else _fx.last_batch.rejected_reason,
	]


func _ok(case_name: String, passed: bool, detail: String = "") -> void:
	_check.call("events %s" % [case_name], passed, detail)
