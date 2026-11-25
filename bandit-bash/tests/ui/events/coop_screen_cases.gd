# ==============================================================================
# Bandit Bash
# Copyright (c) 2026 Derc Development
# Licensed under the MIT License. See LICENSE.
#
# File:     coop_screen_cases.gd
# Author:
# Created:  November 22, 2026
# Modified: November 24, 2026
# ==============================================================================

extends RefCounted
## The event screen for its own seat: a 2-seat host run through the real SaveService,
## CampaignService and router at 1280×720, once for the local seat 0 and once for seat 1. An event
## each seat chooses alone: the teammate still choosing, then their choice by name; the seat's own
## choice waiting on them, Leave closed until they choose; its curse's keywords on the card (key
## focus shows their tooltips) and in the outcome. A team vote: each teammate's vote by name, a
## refused vote naming them, the draw, each seat taking it for its own army while the other waits
## read only, the Team panel by keys and pad (a teammate's batch keeps it open; Team's own hints
## while it has focus), and the Fight only after the last seat. Out of the tree the panel's focus
## asks nothing (BUG-026).
## Writes save files, so it runs only with a test user folder; it deletes user://saves/ before
## and after. It never names an autoload: they are reached as nodes.

# The suite that runs this file; tests/case_files.gd finds it by this line.
const SUITE: String = "ui/events"
# Runs only with a test user folder, as it writes save files; the suite skips it otherwise.
const NEEDS_TEST_USER_FOLDER: bool = true

const Fixture = preload("res://tests/ui/events/event_screen_fixture.gd")

const SCREEN_PATH: String = "res://ui/campaign/events/event_screen.tscn"

# SceneRouter.Screen values, read through the node as the suites do.
const SCREEN_GAMEPLAY: int = 3
const SCREEN_MAP: int = 9

# The screen's hint context while Team holds focus (event_screen.gd's TEAM_FOCUS_CONTEXT).
const TEAM_HINTS: StringName = &"ON_TEAM"

# The save file the cases write, in the test user folder only.
const SAVE_NUMBER: int = 2
# Two made-up Steam ids: the host's, then the teammate's.
const STEAM_IDS: Array[int] = [0x1111, 0x2222]

# The omens, an event each seat chooses alone: 0 "Heed It" (nothing), 1 "Scorn It" (gold and a
# minor curse, whose effect text always marks a keyword).
const OMENS: String = "test_omens"
const HEED: int = 0
const SCORN: int = 1
const OMEN_GOLD: int = 40

var _check: Callable
var _root: Window = null
var _fx: Fixture = null
var _saves: Node = null
var _service: Node = null
var _router: Node = null
var _catalog: EffectCatalog.Index = null
var _rules: CombatRewardRules = null

# Every batch the session settled since the last _batches.clear(): [seat, is_rejected].
var _batches: Array[Array] = []


## [param check]: called as check(case_name: String, passed: bool, detail: String).
## [param root]: the root viewport, where the screens are added and input is pushed.
func _init(check: Callable, root: Window) -> void:
	_check = check
	_root = root
	_fx = Fixture.new(root)


func run() -> void:
	_saves = _root.get_node(^"SaveService")
	_service = _root.get_node(^"CampaignService")
	_router = _root.get_node(^"SceneRouter")
	_catalog = EffectCatalog.index()
	_rules = CombatRewardRules.load_default()
	SaveFile.delete_folder("user://saves/")
	_saves.call(&"open_save_file", SAVE_NUMBER)
	var ids: PackedInt64Array = []
	for steam_id: int in STEAM_IDS:
		ids.append(steam_id)
	var err: Error = _saves.call(&"start_new_multiplayer_run", ids)
	var session: CampaignSession = _session()
	_ok("setup: a new 2-seat host run starts", (
			err == OK and session != null and session.seats == PackedInt32Array([0, 1])
	), error_string(err))
	if session != null:
		session.campaign_batch_resolved.connect(_on_session_campaign_batch_resolved)
		for seat: int in session.seats:
			session.run.seat_run(seat).pending_offers.erase(StartingOffer.OFFER_KEY)
		for local: int in session.seats:
			_test_alone(local)
			_test_team(local)
		_test_focus_out_of_tree()
	_saves.call(&"close_save_file")
	SaveFile.delete_folder("user://saves/")


# The omens for seat local: seat 1 sees the teammate choose first; seat 0 chooses first and waits.
func _test_alone(local: int) -> void:
	var other: int = 1 - local
	var pool: EventPool = _stage(_omens())
	if pool == null:
		return
	_service.call(&"set_local_seat", local)
	var screen: Control = _open_screen(pool)
	var panel: EventPanel = screen.call(&"get_panel")
	var team: EventTeamStatus = panel.get_team_status()
	var header: RunHeader = screen.call(&"get_header")
	var own: SeatRun = _session().run.seat_run(local)
	var tag: String = "alone, seat %d" % [local]
	_ok("%s: the screen shows its own part and gold; the teammate still choosing; Team" % [tag], (
			panel.get_view().seat == local and panel.get_step() == EventPanel.Step.OPTIONS
			and header.get_gold_text() == "Gold %d" % [own.gold]
			and team.visible and team.get_lines() == PackedStringArray([
				"%s is still choosing." % [_name(other)],
			])
			and panel.get_team_button().visible and not panel.get_vote_status().visible
	), "%s; %s" % [team.get_lines(), header.get_gold_text()])

	panel.focus_first()
	_fx.press_key(KEY_RIGHT)
	var scorn: EventOptionCard = panel.get_cards()[SCORN]
	var effect: EffectText = scorn.get_effect_text()
	var tips: int = effect.get_shown_tooltips().size()
	_ok("%s (keys): the curse's keywords mark its card; key focus shows each one's tooltip" % [
		tag,
	], (
			scorn.has_focus() and effect.marked_text.contains("[kw=")
			and tips > 0 and tips == effect.get_keyword_ids().size()
	), "%s; %d tooltips" % [effect.marked_text, tips])

	if local == 1:
		_submit(EventNode.choose(_session(), other, HEED, null, pool, _catalog))
		_ok("%s: the teammate's choice rebuilds their line by name; the cards stay" % [tag], (
				team.get_lines() == PackedStringArray(["%s chose Heed It." % [_name(other)]])
				and panel.get_step() == EventPanel.Step.OPTIONS
				and panel.get_cards().size() == 2
		), str(team.get_lines()))

	var gold: PackedInt32Array = [own.gold, _session().run.seat_run(other).gold]
	_batches.clear()
	panel.focus_first()
	var pressed: bool = _fx.press("key", panel.get_cards()[SCORN], "right")
	var summary: EventOutcomeSummary = panel.get_summary()
	var leave: Button = panel.get_leave_button()
	var applied: bool = (
			pressed and _only_batch(local, false) and panel.get_step() == EventPanel.Step.OUTCOME
			and own.gold == gold[0] + OMEN_GOLD
			and _session().run.seat_run(other).gold == gold[1]
	)
	var outcome_ids: PackedStringArray = summary.get_effect_text().get_keyword_ids()
	_ok("%s (keys): its choice applies to its own army; the outcome marks the curse's keywords" % [
		tag,
	], applied and not outcome_ids.is_empty(), summary.get_effect_text().marked_text)

	if local == 0:
		var waits: String = "Waiting for %s to choose." % [_name(other)]
		_ok("%s: it waits on the teammate by name, read only, Leave closed" % [tag], (
				leave.visible and leave.disabled and leave.focus_mode == Control.FOCUS_NONE
				and summary.get_lines().contains(waits)
				and team.get_lines() == PackedStringArray([
					"%s is still choosing." % [_name(other)],
				])
				and panel.get_cards().is_empty()
		), summary.get_lines())
		_ok("%s: with Leave closed, focus falls to Team" % [tag], (
				panel.focus_first() and panel.get_team_button().has_focus()
		))
		_submit(EventNode.choose(_session(), other, HEED, null, pool, _catalog))
	_ok("%s: once the teammate has chosen, Leave (Ready) opens and nothing waits" % [tag], (
			not leave.disabled and leave.text == "Ready"
			and (leave as ReadyToggle).solo_text == "Leave"
			and not summary.get_lines().contains("Waiting for")
			and team.get_lines() == PackedStringArray(["%s chose Heed It." % [_name(other)]])
	), summary.get_lines())

	_batches.clear()
	leave.grab_focus()
	_fx.press_pad(JOY_BUTTON_A)
	_ok("%s (pad): Leave sends its own Leave; the run returns to the map" % [tag], (
			_only_batch(local, false) and _session().run.is_on_map()
			and _screen() == SCREEN_MAP
	), "%s; screen %d" % [_batches, _screen()])
	_remove(screen)


# The toll for seat local: the vote, a refusal naming the teammate, the draw, each seat's own
# apply, the Team panel, and the Fight once the last seat has applied.
func _test_team(local: int) -> void:
	var other: int = 1 - local
	var pool: EventPool = _stage(Fixture.toll())
	if pool == null:
		return
	_session().run.seat_run(other).gold = 0
	_service.call(&"set_local_seat", local)
	var screen: Control = _open_screen(pool)
	var panel: EventPanel = screen.call(&"get_panel")
	var votes: EventVoteStatus = panel.get_vote_status()
	var team: EventTeamStatus = panel.get_team_status()
	var hints: ScreenHints = screen.get_node(^"ScreenHints")
	var tag: String = "team, seat %d" % [local]
	var mate: String = _name(other)
	var pay: EventOptionCard = panel.get_cards()[Fixture.PAY]
	_ok("%s: the vote names the teammate yet to vote; Pay greyed for their gold, by name" % [
		tag,
	], (
			panel.get_step() == EventPanel.Step.VOTE and votes.visible and not team.visible
			and votes.get_seat_lines() == PackedStringArray(["%s hasn't voted." % [mate]])
			and pay.disabled and pay.get_card_text().contains(
					"Can't choose: %s needs %d gold." % [mate, Fixture.TOLL_GOLD]
			)
	), "%s; %s" % [votes.get_seat_lines(), pay.get_card_text()])

	_batches.clear()
	panel.command_ready.emit(EventNode.vote(_session(), local, Fixture.PAY, pool, _catalog))
	_ok("%s: a vote for Pay is refused, the teammate named" % [tag], (
			_only_batch(local, true)
			and panel.get_status_text() == "Can't do that: %s: needs %d gold." % [
				mate, Fixture.TOLL_GOLD,
			]
	), panel.get_status_text())

	_batches.clear()
	_lay_out(screen)
	_fx.click(panel.get_cards()[Fixture.FIGHT])
	_ok("%s (mouse): its vote for Fight shows; the teammate still hasn't voted" % [tag], (
			_only_batch(local, false) and panel.get_step() == EventPanel.Step.VOTE
			and votes.get_detail().begins_with("1 of 2 votes cast. Your vote: Fight.")
			and votes.get_seat_lines() == PackedStringArray(["%s hasn't voted." % [mate]])
	), "%s; %s" % [votes.get_detail(), _batches])

	_submit(EventNode.vote(_session(), other, Fixture.FIGHT, pool, _catalog))
	_ok("%s: the teammate's vote draws Fight; their vote and that they haven't taken it show" % [
		tag,
	], (
			panel.get_step() == EventPanel.Step.DRAWN
			and votes.get_heading() == "The team drew Fight"
			and votes.get_seat_lines() == PackedStringArray(["%s voted for Fight." % [mate]])
			and team.visible
			and team.get_lines() == PackedStringArray(["%s hasn't taken Fight yet." % [mate]])
	), "%s; %s" % [votes.get_heading(), team.get_lines()])

	var team_button: Button = panel.get_team_button()
	var team_panel: TeamPanel = screen.call(&"get_team_panel")
	panel.focus_first()
	_fx.press_key(KEY_DOWN)
	var reached: bool = team_button.has_focus()
	_fx.press_key(KEY_ENTER)
	var rows: Array[TeammateRow] = team_panel.get_rows()
	var note: String = rows[0].get_note_text() if not rows.is_empty() else ""
	_ok("%s (keys): down from the drawn card reaches Team; Enter lists the teammate's part" % [
		tag,
	], (
			reached and team_panel.visible and rows.size() == 1 and rows[0].shown_seat == other
			and note.contains("%s hasn't taken Fight yet." % [mate])
			and hints.context == TeamPanel.HINT_TEAM
	), "%s; %s" % [note, hints.context])
	_fx.press_key(KEY_ESCAPE)
	var on_team: StringName = hints.context
	_fx.press_key(KEY_UP)
	_ok("%s (keys): Esc closes Team, giving back focus and Team's hints; up, the step's" % [tag], (
			not team_panel.visible and on_team == TEAM_HINTS and hints.context == &"OPTIONS"
			and not team_button.has_focus() and not _root.get_tree().paused
	), "%s, then %s" % [on_team, hints.context])

	_batches.clear()
	panel.focus_first()
	_fx.press_pad(JOY_BUTTON_A)
	var summary: EventOutcomeSummary = panel.get_summary()
	var leave: Button = panel.get_leave_button()
	var events: EventRunState = _session().run.events
	_ok("%s (pad): it takes Fight for its own army and waits on the teammate, no combat yet" % [
		tag,
	], (
			_only_batch(local, false) and panel.get_step() == EventPanel.Step.OUTCOME
			and leave.disabled and leave.text == "Ready" and not events.is_combat_pending
			and hints.context == &"WAITING"
			and summary.get_lines().contains("Waiting for %s to choose." % [mate])
			and team.get_lines() == PackedStringArray(["%s hasn't taken Fight yet." % [mate]])
	), summary.get_lines())

	panel.focus_first()
	_fx.press_pad(JOY_BUTTON_A)
	var opened: bool = team_panel.visible
	_submit(EventNode.choose(_session(), other, Fixture.FIGHT, null, pool, _catalog))
	rows = team_panel.get_rows()
	note = rows[0].get_note_text() if not rows.is_empty() else ""
	_ok("%s (pad): the teammate's apply rebuilds the open Team panel; Ready to fight waits" % [
		tag,
	], (
			opened and team_panel.visible and hints.context == TeamPanel.HINT_TEAM
			and note.contains("%s took Fight." % [mate])
			and events.is_combat_pending and leave.text == "Ready to fight" and not leave.disabled
			and (leave as ReadyToggle).solo_text == "Fight"
			and summary.get_lines().contains("A surprise combat begins")
	), "%s; %s; %s" % [note, hints.context, leave.text])
	_fx.press_pad(JOY_BUTTON_B)
	var closed_on: StringName = hints.context
	_fx.press_pad(JOY_BUTTON_DPAD_UP)
	_ok("%s (pad): B closes Team onto Team's hints, no pause menu; up to Fight, its hints" % [tag], (
			not team_panel.visible and closed_on == TEAM_HINTS and leave.has_focus()
			and hints.context == &"FIGHT" and not _root.get_tree().paused
	), "%s, then %s" % [closed_on, hints.context])

	_batches.clear()
	leave.grab_focus()
	_fx.press_key(KEY_ENTER)
	_ok("%s (keys): Fight goes to the battle, sending nothing" % [tag], (
			_batches.is_empty() and _screen() == SCREEN_GAMEPLAY
	), str(_screen()))
	_remove(screen)


# BUG-026: an outcome shown, then the panel out of the tree in the same frame, as a scene change
# takes it: its focus asks nothing of a control outside the tree, so the engine logs no error.
func _test_focus_out_of_tree() -> void:
	var pool: EventPool = _stage(_omens())
	if pool == null:
		return
	_service.call(&"set_local_seat", CampaignData.HOST_SEAT)
	var screen: Control = _open_screen(pool)
	var panel: EventPanel = screen.call(&"get_panel")
	panel.get_cards()[HEED].pressed.emit()
	var at_outcome: bool = panel.get_step() == EventPanel.Step.OUTCOME
	_root.remove_child(screen)
	var catcher: FocusErrorCatcher = FocusErrorCatcher.new()
	OS.add_logger(catcher)
	var took: bool = panel.focus_first()
	OS.remove_logger(catcher)
	_ok("BUG-026: out of the tree, the outcome's focus takes nothing and logs no error", (
			at_outcome and not took and catcher.get_errors().is_empty()
	), "; ".join(catcher.get_errors()))
	screen.free()


# --- Helpers -----------------------------------------------------------------------------------


func _session() -> CampaignSession:
	return _service.get(&"session") as CampaignSession


func _name(seat: int) -> String:
	return CampaignLink.seat_name(seat)


# The screen the router last went to, a SceneRouter.Screen value.
func _screen() -> int:
	return _router.get(&"current_screen")


# Puts the run inside the next node made an Unknown one (a floor 1 node to start), rolled as an
# event, and opens event there from a pool of it alone through the service, which saves. Returns
# the pool; null, with a FAIL line, when it doesn't open.
func _stage(event: EventDefinition) -> EventPool:
	var run: CampaignRunState = _session().run
	var next: PackedInt32Array = (
			run.graph.nodes_on_floor(1) if run.visited.is_empty()
			else run.graph.children_of(run.node)
	)
	if next.is_empty():
		_ok("setup: a next node for %s" % [event.id], false)
		return null
	run.graph.set_node_type(next[0], CampaignGraph.NodeType.UNKNOWN)
	run.visited.append(next[0])
	run.floor_number = run.visited.size()
	run.node = next[0]
	run.flow.stage = RunFlow.Stage.NODE
	run.flow.unknown = UnknownResolution.EVENT
	var pool: EventPool = EventPool.new([event])
	var batch: CampaignBatch = _service.call(
			&"submit_command", EventNode.open(_session(), pool, _catalog, _rules)
	)
	var is_open: bool = batch != null and not batch.is_rejected()
	_ok("setup: %s opens at node %d" % [event.id, next[0]], is_open, (
			"no batch" if batch == null else batch.rejected_reason
	))
	return pool if is_open else null


# The event screen as the router opens it, laid out at the base viewport, then shown on pool's
# event (the game's pool lacks it).
func _open_screen(pool: EventPool) -> Control:
	var screen: Control = (load(SCREEN_PATH) as PackedScene).instantiate()
	_root.add_child(screen)
	screen.set_anchors_preset(Control.PRESET_TOP_LEFT)
	screen.size = Fixture.SCREEN_SIZE
	screen.call(&"reopen", pool, _catalog)
	_lay_out(screen)
	return screen


func _remove(screen: Control) -> void:
	if screen.is_inside_tree():
		_root.remove_child(screen)
	screen.free()


# Sorts the screen's containers twice, parents first, as a frame's deferred sort would.
func _lay_out(screen: Control) -> void:
	for _pass: int in 2:
		for node: Node in screen.find_children("*", "Container", true, false):
			node.notification(Container.NOTIFICATION_SORT_CHILDREN)


# Sends command as the teammate or the host would, outside any screen.
func _submit(command: CampaignCommand) -> void:
	var batch: CampaignBatch = _service.call(&"submit_command", command)
	if batch == null or batch.is_rejected():
		_ok("co-op: %s resolves" % [command.get_label()], false, (
				batch.rejected_reason if batch != null else "no batch"
		))


# Whether exactly one batch settled since the last clear, of seat, rejected or not.
func _only_batch(seat: int, is_rejected: bool) -> bool:
	return _batches.size() == 1 and _batches[0] == [seat, is_rejected]


func _on_session_campaign_batch_resolved(batch: CampaignBatch) -> void:
	_batches.append([batch.seat, batch.is_rejected()])


func _ok(case_name: String, passed: bool, detail: String = "") -> void:
	_check.call("events co-op %s" % [case_name], passed, detail)


# The omens (see OMENS).
static func _omens() -> EventDefinition:
	var heed: EventOption = EventOption.new()
	heed.title = "Heed It"
	heed.text = "Nothing happens."
	var gold: GoldOutcome = GoldOutcome.new()
	gold.amount = OMEN_GOLD
	var scorn_outcomes: Array[EventOutcome] = [gold]
	var scorn: EventOption = EventOption.new()
	scorn.title = "Scorn It"
	scorn.text = "Gain 40 gold and a minor curse."
	scorn.outcomes = scorn_outcomes
	scorn.curse_tier = Fixture.MINOR
	var options: Array[EventOption] = [heed, scorn]
	var event: EventDefinition = EventDefinition.new()
	event.id = OMENS
	event.title = "A Crow's Warning"
	event.text = "A test-only event: each seat chooses alone."
	event.options = options
	return event


# Keeps every grab_focus error the engine logs while it is added with OS.add_logger. The engine may
# call a logger from any thread, so the list is locked.
class FocusErrorCatcher:
	extends Logger

	var _errors: PackedStringArray = []
	var _lock: Mutex = Mutex.new()

	func _log_error(
			function: String,
			file: String,
			line: int,
			code: String,
			rationale: String,
			_is_editor_notified: bool,
			_error_type: int,
			_backtraces: Array[ScriptBacktrace]
	) -> void:
		if function != "grab_focus":
			return
		_lock.lock()
		_errors.append("%s (%s:%d)" % [rationale if not rationale.is_empty() else code, file, line])
		_lock.unlock()

	## Every grab_focus error logged while it was added.
	func get_errors() -> PackedStringArray:
		_lock.lock()
		var copy: PackedStringArray = _errors.duplicate()
		_lock.unlock()
		return copy
