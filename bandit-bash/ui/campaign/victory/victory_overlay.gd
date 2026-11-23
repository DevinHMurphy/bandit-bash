# ==============================================================================
# Bandit Bash
# Copyright (c) 2026 Derc Development
# Licensed under the MIT License. See LICENSE.
#
# File:     victory_overlay.gd
# Author:
# Created:  November 19, 2026
# Modified: November 23, 2026
# ==============================================================================

class_name VictoryOverlay
extends CanvasLayer
## A won combat's victory sequence over a darkened scene: Grade, Recap, then Rewards, each moved on
## with the primary button (ui-lift.md, Victory sequence). Read from the run as saved
## ([CombatResultsModel], [VictoryRewards]), rebuilt after every command, so a quit and Continue
## shows the same. The [BattleScreen] shows it over the board after a win; on a resumed run the
## Results screen shows it over a plain backdrop, opening on Rewards once a reward is taken.[br]
## Shows one seat's results; a co-op seat whose map was lost sees only that and Leave. A picker
## sends its reward's commands; Leave sends each open reward's skip, then [LeaveNodeCommand],
## asking first while rewards are open, each once the one before
## settled ([CampaignLink]); after the Boss it reads End run and ends the run as won
## ([method CampaignService.end_won_run]). A refusal shows its reason; once any seat's Leave
## resolves, the run goes on. XP fills run on playback time ([member playback_speed]). The run's
## facts play ([CampaignPlayback]) on opening, each level-up with its card, the rest at Rewards.
##
## @tutorial(UL5 plan): docs/plans/2026-11-19-ul5-victory-sequence.md

# ============================================================
# INPUT MAP SETUP (built-in ui_* actions read through the GUI; named actions in project.godot):
#   "ui_up" / "ui_down"    -> Up / Down arrows; d-pad, left stick   (RECAP_* and REWARDS: along
#                             the rows, the scroll following focus, then down to the button)
#   "ui_left" / "ui_right" -> deliberately inert outside the picker and dialog: focus stays
#   "ui_accept"            -> Enter, Space; pad A [Cross]           (press the focused button or
#                             row: Continue in GRADE and RECAP_*, Leave in REWARDS)
#   "ui_cancel"            -> Esc; pad B [Circle], Menu [Options]   (not read here: the picker and
#                             dialog take it first in _input; otherwise the host's pause menu)
#   "skip_playback"        -> X; LT [L2]   (read in _unhandled_input in RECAP_FILLING only: ends
#                             every fill at once, as Continue does; inert in every other stage)
#   "fast_forward"         -> F; RT [R2]   (polled each frame in RECAP_FILLING while held: fills
#                             run fast_forward_speed times faster; inert elsewhere)
#   Mouse: clicks on the button and rows; the wheel scrolls the recap; the backdrop takes the rest.
# Hint contexts: GRADE, FILL, RECAP, REWARDS (BOSS after the Boss), the picker's own (PICK,
# PLACE), CONFIRM.
# ============================================================

# --- Victory stage (meaningful only after open()) -------------------------------------------
# GRADE:           the grades and the gold collected. Continue -> RECAP_FILLING.
# RECAP_FILLING:   the rows' bars fill one after another on playback time. Continue or
#                  skip_playback ends every fill -> RECAP_LEVEL_UPS (with level-ups) or RECAP_DONE;
#                  the last fill ending does the same.
# RECAP_LEVEL_UPS: one LevelUpCard over the rows. Continue -> the next card; after the last ->
#                  RECAP_DONE.
# RECAP_DONE:      the rows, still. Continue -> REWARDS.
# REWARDS:         a row per open reward and Leave (End run after the Boss). A row -> PICKING;
#                  Leave -> CONFIRM_LEAVE while rewards are open, else the commands, and LEAVING
#                  once the Leave resolves.
# PICKING:         the reward's picker over the stage; the button is out of reach. Resolved or
#                  cancelled -> REWARDS, rebuilt from the saved run.
# CONFIRM_LEAVE:   the LeaveConfirmDialog. Leave -> the commands and LEAVING; Stay -> REWARDS.
# LEAVING:         input does nothing; the screen changes.
# A co-op seat whose map was lost (CombatResultsModel.is_lost) opens on REWARDS with no stage
# shown: the "Map lost" ribbon, the loss line and Leave (End run when another map beat the Boss).
# A resumed sequence opens on REWARDS once a reward is taken, else on GRADE. There is no stage
# for gold: it is collected before the sequence opens. A rejected command stays in REWARDS. Any
# stage: the run leaving these results (any seat's Leave) -> LEAVING.
## Where the sequence is.
enum Stage {
	## The grades and the gold collected.
	GRADE = 0,
	## The recap's XP bars filling.
	RECAP_FILLING = 1,
	## A level-up card over the recap.
	RECAP_LEVEL_UPS = 2,
	## The recap, still.
	RECAP_DONE = 3,
	## The reward list.
	REWARDS = 4,
	## A reward's picker open.
	PICKING = 5,
	## Asking before leaving rewards behind.
	CONFIRM_LEAVE = 6,
	## Leaving for the map or the run's end.
	LEAVING = 7,
}

## The backdrop's opacity over the scene (ui-style.md: [code]bg[/code] at 85%).
const BACKDROP_ALPHA: float = 0.85

## Length of a stage change's fade, and of the overlay's own fade-in (ui-style.md, Motion).[br]
## [b]Units:[/b] seconds, not scaled by playback speed.
const STAGE_FADE_TIME: float = 0.25

# ASSUMPTION: the failed seat's wordings (P11 question 134); no design doc words them.
## The ribbon of a co-op seat whose map was lost ([member CombatResultsModel.is_lost]).
const LOST_TITLE: String = "Map lost"

## The line under it: what the loss costs.
const LOST_TEXT: String = "Your map was lost: no gold, XP, item pick or Standout this combat."

# The Grade stage's gold (Godot_FE's reward panel). Gold has no fact of its own, so it sounds
# here; level-ups sound through their facts (_play_level_up).
const _GOLD_CUE: StringName = &"gold_rewarded"

## How fast the XP fills play: 1.0 is the bar's own timing, 2.0 twice as fast. The battle screen
## sets it to its board's [member BattleView.playback_speed].[br]
## [b]Units:[/b] times real time.
@export_range(0.1, 8.0, 0.1) var playback_speed: float = 1.0

## How many times faster the fills play while fast_forward is held, on top of
## [member playback_speed]. The battle screen sets it to its board's
## [member BattleView.fast_forward_speed].[br]
## [b]Units:[/b] multiplier. [b]1.0:[/b] fast-forward does nothing.
@export_range(1.0, 16.0, 0.5) var fast_forward_speed: float = 4.0

var _stage: Stage = Stage.GRADE
var _seat: int = 0
var _model: CombatResultsModel = null
var _rewards: Array[VictoryReward] = []
var _level_up_index: int = 0
var _picker: RewardPicker = null
var _shown_stage: Control = null
var _link: CampaignLink = null
# Leave's commands still to send, each once the one before resolved.
var _leave_commands: Array[CampaignCommand] = []

@onready var _root: Control = %Root
@onready var _backdrop: ColorRect = %Backdrop
@onready var _ribbon_label: Label = %RibbonText
@onready var _grade_stage: VictoryGradeStage = %VictoryGradeStage
@onready var _recap_stage: VictoryRecapStage = %VictoryRecapStage
@onready var _rewards_stage: VictoryRewardsStage = %VictoryRewardsStage
@onready var _status_label: Label = %Status
@onready var _primary_button: Button = %PrimaryButton
@onready var _picker_holder: Control = %PickerHolder
@onready var _confirm: LeaveConfirmDialog = %LeaveConfirmDialog
@onready var _hints: ScreenHints = %ScreenHints


func _ready() -> void:
	_backdrop.color = UiTokens.with_alpha(UiTokens.BG, BACKDROP_ALPHA)
	_root.visible = false
	for stage: Control in [_grade_stage, _recap_stage, _rewards_stage]:
		stage.visible = false
	_primary_button.pressed.connect(_on_primary_button_pressed)
	_rewards_stage.reward_chosen.connect(_on_rewards_stage_reward_chosen)
	_confirm.confirmed.connect(_on_confirm_confirmed)
	_confirm.cancelled.connect(_on_confirm_cancelled)
	var self_path: NodePath = _primary_button.get_path_to(_primary_button)
	_primary_button.focus_neighbor_left = self_path
	_primary_button.focus_neighbor_right = self_path
	_primary_button.focus_neighbor_bottom = self_path


func _exit_tree() -> void:
	if _link != null:
		_link.close()


func _unhandled_input(event: InputEvent) -> void:
	if _stage == Stage.RECAP_FILLING and event.is_action_pressed(&"skip_playback"):
		get_viewport().set_input_as_handled()
		skip()


func _process(delta: float) -> void:
	advance(delta)


## Opens the sequence for seat [param seat] of the run in progress, fading in. [param is_resumed]:
## a continued run, which opens on Rewards once a reward is taken.
func open(seat: int, is_resumed: bool) -> void:
	_seat = seat
	if _link != null:
		_link.close()
	_link = CampaignLink.new(CampaignService.session, seat, CampaignService.submit_command)
	_link.batch_resolved.connect(_on_link_batch_resolved)
	_link.refused.connect(_on_link_refused)
	_root.visible = true
	_root.modulate.a = 0.0
	create_tween().tween_property(_root, "modulate:a", 1.0, STAGE_FADE_TIME)
	_refresh()
	if _model == null:
		_ribbon_label.text = "Victory"
		_status_label.text = "This combat's report couldn't be read; see the log."
		_primary_button.disabled = true
		return
	if _model.is_lost:
		_status_label.text = LOST_TEXT
		_enter(Stage.REWARDS)
		return
	CampaignPlayback.play_before(CampaignService.session, CampaignFact.Kind.LEVELED_UP, _seat)
	var starts_on_rewards: bool = is_resumed and VictoryRewards.has_taken(_rewards)
	_enter(Stage.REWARDS if starts_on_rewards else Stage.GRADE)


## Plays [param delta] seconds of real time on the recap's fills, at [member playback_speed]
## times [member fast_forward_speed] while fast_forward is held. Called each frame; tests call it.
func advance(delta: float) -> void:
	if _stage != Stage.RECAP_FILLING:
		return
	var speed: float = playback_speed
	if Input.is_action_pressed(&"fast_forward"):
		speed *= fast_forward_speed
	if not _recap_stage.step(delta * speed):
		_after_fill()


## Ends every XP fill at once, as skip_playback does; nothing outside RECAP_FILLING.
func skip() -> void:
	if _stage != Stage.RECAP_FILLING:
		return
	_recap_stage.finish_fill()
	_after_fill()


## The stage shown.
func get_stage() -> Stage:
	return _stage


## The model shown, for tests.
func get_model() -> CombatResultsModel:
	return _model


## The Grade stage, for tests.
func get_grade_stage() -> VictoryGradeStage:
	return _grade_stage


## The Recap stage, for tests.
func get_recap_stage() -> VictoryRecapStage:
	return _recap_stage


## The Rewards stage, for tests.
func get_rewards_stage() -> VictoryRewardsStage:
	return _rewards_stage


## The primary button (Continue, Leave or End run), for tests.
func get_primary_button() -> Button:
	return _primary_button


## The open picker; null while none is open.
func get_picker() -> RewardPicker:
	return _picker if is_instance_valid(_picker) else null


## The leave dialog, for tests.
func get_confirm_dialog() -> LeaveConfirmDialog:
	return _confirm


## The status line's text, for tests.
func get_status_text() -> String:
	return _status_label.text


## The ribbon's text, for tests.
func get_title() -> String:
	return _ribbon_label.text


## The hint bar's context, for tests.
func get_hint_context() -> StringName:
	return _hints.context


# Reads the run again: the model and its rewards.
func _refresh() -> void:
	_model = CombatResultsModel.build(CampaignService.session, _seat)
	_rewards = VictoryRewards.build(_model)


func _enter(stage: Stage) -> void:
	_stage = stage
	match stage:
		Stage.GRADE:
			_ribbon_label.text = "Boss defeated" if _model.is_boss else "Victory"
			_grade_stage.show_grades(_model)
			_show_stage(_grade_stage)
			_set_primary("Continue")
			Sound.play(_GOLD_CUE)
		Stage.RECAP_FILLING, Stage.RECAP_LEVEL_UPS, Stage.RECAP_DONE:
			_ribbon_label.text = "Battle report"
			_show_stage(_recap_stage)
			_set_primary("Continue")
			_recap_stage.link_focus(_primary_button)
			if stage == Stage.RECAP_DONE:
				_recap_stage.hide_level_up()
		Stage.REWARDS when _model.is_lost:
			# A lost map's results: the loss and Leave, no stage shown.
			CampaignPlayback.play_pending(CampaignService.session)
			_ribbon_label.text = LOST_TITLE
			for stage_shown: Control in [_grade_stage, _recap_stage, _rewards_stage]:
				stage_shown.visible = false
			_shown_stage = null
			_set_primary("End run" if _model.is_boss else "Leave")
		Stage.REWARDS:
			CampaignPlayback.play_pending(CampaignService.session)
			_ribbon_label.text = "Rewards"
			_rewards_stage.show_rewards(VictoryRewards.open_of(_rewards))
			_show_stage(_rewards_stage)
			_set_primary("End run" if _model.is_boss else "Leave")
			_rewards_stage.link_focus(_primary_button)
	_primary_button.focus_mode = (
			Control.FOCUS_NONE if stage >= Stage.PICKING else Control.FOCUS_ALL
	)
	_update_hints()
	_focus_default.call_deferred()


func _set_primary(text: String) -> void:
	_primary_button.text = text
	_primary_button.disabled = false


# Shows stage, fading it in when it wasn't already shown.
func _show_stage(stage: Control) -> void:
	if _shown_stage == stage:
		return
	for other: Control in [_grade_stage, _recap_stage, _rewards_stage]:
		other.visible = other == stage
	_shown_stage = stage
	stage.modulate.a = 0.0
	create_tween().tween_property(stage, "modulate:a", 1.0, STAGE_FADE_TIME)


func _update_hints() -> void:
	match _stage:
		Stage.GRADE:
			_hints.context = &"GRADE"
		Stage.RECAP_FILLING:
			_hints.context = &"FILL"
		Stage.RECAP_LEVEL_UPS, Stage.RECAP_DONE:
			_hints.context = &"RECAP"
		Stage.REWARDS:
			_hints.context = &"BOSS" if _model.is_boss else &"REWARDS"
		Stage.PICKING:
			_hints.context = _picker.get_hint_context() if get_picker() != null else &"PICK"
		Stage.CONFIRM_LEAVE:
			_hints.context = &"CONFIRM"
		Stage.LEAVING:
			_hints.context = &""


# Focus where the player acts next: the first reward row in REWARDS, else the button. The picker
# and the dialog focus their own.
func _focus_default() -> void:
	if not is_inside_tree():
		return
	match _stage:
		Stage.REWARDS:
			if not _rewards_stage.focus_first() and not _primary_button.disabled:
				_primary_button.grab_focus()
		Stage.GRADE, Stage.RECAP_FILLING, Stage.RECAP_LEVEL_UPS, Stage.RECAP_DONE:
			_primary_button.grab_focus()


func _begin_recap() -> void:
	_recap_stage.show_recap(_model)
	_recap_stage.begin_fill()
	_enter(Stage.RECAP_FILLING)
	if not _recap_stage.is_filling():
		_after_fill()


# The fills ended: the first level-up, else the still recap.
func _after_fill() -> void:
	_level_up_index = 0
	if _recap_stage.show_level_up(_level_up_index):
		_play_level_up(_level_up_index)
		_enter(Stage.RECAP_LEVEL_UPS)
	else:
		_enter(Stage.RECAP_DONE)


func _next_level_up() -> void:
	_level_up_index += 1
	if not _recap_stage.show_level_up(_level_up_index):
		_enter(Stage.RECAP_DONE)
		return
	_play_level_up(_level_up_index)


# Plays card index's LEVELED_UP fact, and any still to play before it; nothing when the run's log
# no longer holds it (a resumed run).
func _play_level_up(index: int) -> void:
	var session: CampaignSession = CampaignService.session
	if _model == null or index < 0 or index >= _model.level_up_lines.size():
		return
	var unit_id: String = _model.level_up_lines[index].unit_id
	CampaignPlayback.play_through(session, CampaignPlayback.next_pending(
			session, CampaignFact.Kind.LEVELED_UP, _seat, unit_id
	))


# Sends the next of Leave's commands, once the one before resolved; the last is the Leave, whose
# batch moves the run on (_on_link_batch_resolved).
func _send_next_leave_command(_resolved: CampaignBatch = null) -> void:
	if _stage == Stage.LEAVING or _leave_commands.is_empty():
		return
	var command: CampaignCommand = _leave_commands.pop_front()
	_link.send(command, _send_next_leave_command)


# Asks first while rewards are open, else leaves.
func _request_leave() -> void:
	var open: Array[VictoryReward] = VictoryRewards.open_of(_rewards)
	if open.is_empty():
		_leave()
		return
	var titles: PackedStringArray = []
	for reward: VictoryReward in open:
		titles.append(reward.title)
	_enter(Stage.CONFIRM_LEAVE)
	_confirm.open(titles)


# Gives up each open reward, then leaves the node; after the Boss, ends the run as won.
func _leave() -> void:
	if _model.is_boss:
		var err: Error = CampaignService.end_won_run()
		if CampaignService.session != null:
			_status_label.text = "Couldn't end the run (%s)." % [error_string(err)]
			_enter(Stage.REWARDS)
			return
		_enter(Stage.LEAVING)
		SceneRouter.goto_screen(SceneRouter.Screen.RESULTS)
		return
	_leave_commands.clear()
	for reward: VictoryReward in VictoryRewards.open_of(_rewards):
		var skip_command: CampaignCommand = reward.skip_command(_seat)
		if skip_command != null:
			_leave_commands.append(skip_command)
	_leave_commands.append(LeaveNodeCommand.new(_seat))
	_send_next_leave_command()


# A batch the sequence follows ([method CampaignLink.moves_with]; a picker's own sends are its
# picker's): once the run has left these results, the sequence leaves too; at Rewards its facts
# play. A level-up still to show waits for its card.
func _on_link_batch_resolved(batch: CampaignBatch, is_answer: bool) -> void:
	if _stage == Stage.LEAVING or not _link.moves_with(batch, is_answer):
		return
	if RunScreen.of(CampaignService.session) != SceneRouter.Screen.COMBAT_RESULTS:
		_leave_commands.clear()
		_close_picker()
		CampaignPlayback.play_pending(CampaignService.session)
		_enter(Stage.LEAVING)
		RunScreen.go()
		return
	if _stage >= Stage.REWARDS:
		CampaignPlayback.play_pending(CampaignService.session)


# A refusal of one of Leave's commands stops the rest and shows the rewards again; a picker's
# refusal shows on the picker.
func _on_link_refused(reason: String) -> void:
	if _stage == Stage.PICKING or _stage == Stage.LEAVING:
		return
	_leave_commands.clear()
	_status_label.text = "Can't do that: %s." % [reason]
	_refresh()
	_enter(Stage.REWARDS)


func _close_picker() -> void:
	if get_picker() != null:
		_picker.queue_free()
	_picker = null


func _on_primary_button_pressed() -> void:
	match _stage:
		Stage.GRADE:
			_begin_recap()
		Stage.RECAP_FILLING:
			skip()
		Stage.RECAP_LEVEL_UPS:
			_next_level_up()
		Stage.RECAP_DONE:
			_enter(Stage.REWARDS)
		Stage.REWARDS:
			_request_leave()


func _on_rewards_stage_reward_chosen(reward: VictoryReward) -> void:
	if _stage != Stage.REWARDS:
		return
	var scene: PackedScene = load(reward.picker_path) as PackedScene
	var picker: RewardPicker = scene.instantiate() as RewardPicker if scene != null else null
	if picker == null:
		push_error("VictoryOverlay: no picker for reward %s - %s" % [
			reward.title, reward.picker_path,
		])
		return
	_close_picker()
	_picker = picker
	_picker_holder.add_child(picker)
	picker.resolved.connect(_on_picker_resolved)
	picker.cancelled.connect(_on_picker_cancelled)
	picker.hint_context_changed.connect(_update_hints)
	_status_label.text = ""
	_enter(Stage.PICKING)
	picker.open(reward, _seat)


func _on_picker_resolved(note: String) -> void:
	_close_picker()
	_refresh()
	_status_label.text = note
	_enter(Stage.REWARDS)


func _on_picker_cancelled() -> void:
	_close_picker()
	_enter(Stage.REWARDS)


func _on_confirm_confirmed() -> void:
	_leave()


func _on_confirm_cancelled() -> void:
	_enter(Stage.REWARDS)
