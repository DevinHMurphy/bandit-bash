# ==============================================================================
# Bandit Bash
# Copyright (c) 2026 Derc Development
# Licensed under the MIT License. See LICENSE.
#
# File:     vote_view_cases.gd
# Author:
# Created:  November 19, 2026
# Modified: November 19, 2026
# ==============================================================================

extends RefCounted
## The team vote on the event panel, headless, with two seats in one run in memory, each seat's
## panel sending its own commands: the vote view before any vote (how it works, 0 of 2, a
## teammate short of gold greying Pay for both with the seat named); seat 0's vote by key, shown
## on its card and the status line, then changed by mouse; seat 1's vote by pad completing the
## set and drawing; the drawn result on both panels, only the drawn card pressable; seat 0
## taking it, which applies to both seats; both ending on the outcome with the tally.

# The suite that runs this file; tests/case_files.gd finds it by this line.
const SUITE: String = "ui/events"

const Fixture = preload("res://tests/ui/events/event_screen_fixture.gd")

const SEATS: int = 2

var _check: Callable
var _fx: Fixture = null


## [param check]: called as check(case_name: String, passed: bool, detail: String).
## [param root]: the root viewport, where the panels are added and input is pushed.
func _init(check: Callable, root: Window) -> void:
	_check = check
	_fx = Fixture.new(root)


func run() -> void:
	if not _fx.base.is_ready():
		_ok("the fixture's catalog and rules load", false)
		return
	_test_vote()
	_test_greyed_for_team()


func _test_vote() -> void:
	var made: CampaignSession = _fx.session_with(Fixture.toll(), SEATS)
	var first: EventPanel = _fx.open_panel(made, 0)
	var status: EventVoteStatus = first.get_vote_status()
	_ok("vote view: a team vote of two shows how it works and no votes yet", (
			first.get_step() == EventPanel.Step.VOTE and status.visible
			and status.get_heading() == "Team choice: everyone votes"
			and status.get_detail().begins_with("0 of 2 votes cast. You haven't voted.")
			and first.get_cards()[Fixture.FIGHT].text.contains("Votes: 0")
	), status.get_detail())

	var pressed: bool = _press(first, "key", Fixture.FIGHT)
	var vote: int = made.run.events.votes.get(0, EventRunState.NO_OPTION)
	_ok("vote view: seat 0 votes Fight by key; its card and the status line show it", (
			pressed and vote == Fixture.FIGHT
			and first.get_step() == EventPanel.Step.VOTE
			and first.get_cards()[Fixture.FIGHT].text.contains("Votes: 1 (your vote)")
			and status.get_detail().begins_with("1 of 2 votes cast. Your vote: Fight.")
	), status.get_detail())

	pressed = _press(first, "mouse", Fixture.INTIMIDATE)
	vote = made.run.events.votes.get(0, EventRunState.NO_OPTION)
	_ok("vote view: seat 0 changes its vote to Intimidate by mouse", (
			pressed and vote == Fixture.INTIMIDATE
			and first.get_cards()[Fixture.FIGHT].text.contains("Votes: 0")
			and first.get_cards()[Fixture.INTIMIDATE].text.contains("Votes: 1 (your vote)")
	), first.get_cards()[Fixture.INTIMIDATE].text)
	_fx.close_panel(first)

	var second: EventPanel = _fx.open_panel(made, 1)
	pressed = _press(second, "pad", Fixture.INTIMIDATE)
	var drawn: int = made.run.events.drawn_option()
	_ok("vote view: seat 1's vote by pad completes the set and the team draws Intimidate", (
			pressed and drawn == Fixture.INTIMIDATE
			and second.get_step() == EventPanel.Step.DRAWN
			and second.get_vote_status().get_heading() == "The team drew Intimidate"
	), second.get_vote_status().get_heading())
	_fx.close_panel(second)

	first = _fx.open_panel(made, 0)
	var cards: Array[EventOptionCard] = first.get_cards()
	_ok("drawn: seat 0 sees the draw; only the drawn card can be pressed", (
			first.get_step() == EventPanel.Step.DRAWN
			and first.get_vote_status().get_detail().begins_with("2 of 2 votes were for it.")
			and not cards[Fixture.INTIMIDATE].disabled and cards[Fixture.FIGHT].disabled
			and cards[Fixture.FIGHT].text.contains("Can't choose: the team drew another option.")
	), first.get_vote_status().get_detail())

	var gold: PackedInt32Array = [made.run.seat_run(0).gold, made.run.seat_run(1).gold]
	pressed = _press(first, "key", Fixture.INTIMIDATE)
	_ok("drawn: seat 0 takes it with its own picks; it applies to both seats", (
			pressed and first.get_step() == EventPanel.Step.OUTCOME
			and made.run.seat_run(0).gold == gold[0] + Fixture.LOOT_GOLD
			and made.run.seat_run(1).gold == gold[1] + Fixture.LOOT_GOLD
			and first.get_summary().get_lines().contains("The team drew it with 2 of 2 votes.")
	), _fx.last_batch.rejected_reason if _fx.last_batch != null else "")
	_fx.close_panel(first)

	second = _fx.open_panel(made, 1)
	_ok("drawn: seat 1's panel opens on the same outcome, its curse named", (
			second.get_step() == EventPanel.Step.OUTCOME
			and second.get_summary().get_heading() == "You chose Intimidate"
			and second.get_summary().get_lines().contains("(Minor curse)")
	), second.get_summary().get_lines())
	_fx.close_panel(second)


func _test_greyed_for_team() -> void:
	var made: CampaignSession = _fx.session_with(Fixture.toll(), SEATS)
	made.run.seat_run(1).gold = 0
	var panel: EventPanel = _fx.open_panel(made, 0)
	var pay: EventOptionCard = panel.get_cards()[Fixture.PAY]
	_ok("vote view: Pay is greyed for both when seat 1 lacks the gold, the seat named", (
			pay.disabled
			and pay.text.contains("Can't choose: seat 1 needs %d gold." % [Fixture.TOLL_GOLD])
	), pay.text)
	_fx.close_panel(panel)


# Presses option index's card on panel with device, from the first focusable card.
func _press(panel: EventPanel, device: String, index: int) -> bool:
	var cards: Array[EventOptionCard] = panel.get_cards()
	if index >= cards.size() or cards[index].disabled:
		return false
	panel.focus_first()
	return _fx.press(device, cards[index], "right")


func _ok(case_name: String, passed: bool, detail: String = "") -> void:
	_check.call("events %s" % [case_name], passed, detail)
