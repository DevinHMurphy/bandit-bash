# ==============================================================================
# Bandit Bash
# Copyright (c) 2026 Derc Development
# Licensed under the MIT License. See LICENSE.
#
# File:     battle_controller.gd
# Author:
# Created:  November 4, 2026
# Modified: November 14, 2026
# ==============================================================================

class_name BattleController
extends HintSource
## Turns the player's input on the battle screen into commands: the tile cursor, selecting a
## unit, its move and attack tiles and path, the action menu, the target picker, confirm, End
## Turn, the opening swap window and Start (combat UI plan, question 6's flow, ported from
## Godot_FE's player FSM).
##
## [b]Commands only:[/b] it never changes combat state. What it offers comes from
## [TurnInputModel], whose every action already passed its command's own validation; confirming
## submits that command to the encounter for the seat and resolves it. A rejection
## ([signal CombatSession.command_rejected]) shows its reason in the [BattleMessage]. Panels go
## through one [PanelHost]: each stage that opens a panel pushes one, and cancel pops exactly one.
## Input waits while playback runs ([method BattleView.is_settled]), except fast-forward and the
## skip.[br]
## [b]Targeting[/b] (question 21): a chosen action's targets are one [TargetList]; its rows, Q / E,
## the mouse and accept all move or pick its current target, so each sends the same command.
## Targets are outlined ([TargetMark]); an attack, a staff or a shove confirms on a
## [ForecastPanel], which cycles the target's weapons ([method cycle_weapon]) while the board
## flashes the HP and Stance it predicts ([method BattleView.show_forecast_preview]).[br]
## [b]Move then act[/b] (question 34 (3)): picking another tile walks the token there first
## ([method BattleView.stage_walk]), locally; the action menu opens on arrival.[br]
## [b]Move preview:[/b] hovering a move tile runs a [MovePreview] on a worker thread
## ([method run_preview_frame]), drawn by [MovePreviewMarks] and the [IntentDisplay]; the picked
## tile's, with its danger zone, stays through the action until Cancel (question 35 (1)).[br]
## [b]Unit detail[/b] (UI11): unit_detail or the unit panel's Details opens any unit's
## [UnitDetailPanel] from IDLE or MOVE ([method request_unit_detail]); Back closes it.[br]
## [b]Enemy information[/b] (question 10): the [IntentDisplay] shows the intents once the board
## settles; [method toggle_danger_zone] draws [DangerZone], support tiles purple (question 23).[br]
## [b]Hints and pads[/b] (questions 24, 25, 31): [constant LIVE_ACTIONS] lists each hint context's
## actions, which [method get_live_actions] gives the [ControlHintBar] less what can do nothing
## now; every action has a pad binding, held directions repeating through [member pad_repeat].[br]
## [BattleScreen] binds it to the seat's map ([method bind]); its widgets are its exports' nodes.
##
## @tutorial(Combat UI plan): docs/plans/2026-11-04-combat-ui.md

# ============================================================
# INPUT MAP SETUP (Project Settings -> Input Map; ui_* are Godot's built-in actions). Each action
# lists its key, then its joypad binding in Xbox names (PlayStation in brackets); joypad buttons
# act on press exactly as the key does, except where noted:
#   "ui_up" / "ui_down" /   -> arrow keys;    (IDLE, MOVE, SWAP, SWAP_PICKED: move the cursor one
#   "ui_left" / "ui_right"     d-pad, left       tile. In a panel the focused row takes them first
#                              stick (built-in   and moves focus instead. A held d-pad direction or
#                              defaults, as      stick push repeats through pad_repeat, the keys
#                              Godot_FE's)       through the system's key echo)
#   (mouse motion)                            (IDLE, MOVE, TARGET, SWAP, SWAP_PICKED: the cursor
#                                                follows the mouse over the board. In TARGET, over
#                                                a listed target it makes that target current)
#   "ui_accept"             -> Enter, Space;  (on the board: confirm the cursor's tile; in MOVE on
#                              A [Cross]         another move tile that starts the walk there
#                                                (WALK). In a panel the focused row takes it first
#                                                and is pressed; in TARGET that row is the current
#                                                target's)
#   (Left Mouse Button)                       (confirm the tile under the mouse; on a panel row the
#                                                row takes the click. In TARGET a click on any
#                                                listed target picks it, as its row would)
#   "target_next"           -> E; RB [R1]     (TARGET, CONFIRM: the next target, wrapping, keeping
#                                                the weapon where it can; in CONFIRM the forecast
#                                                or question follows. IDLE: the cursor and camera
#                                                go to the next of the seat's units that can act.
#                                                Deliberate reuse by stage, as Godot_FE's bumpers.
#                                                Harmless elsewhere and with one target)
#   "target_prev"           -> Q; LB [L1]     (as target_next, backwards)
#   "ui_cancel"             -> Escape;        (step back one stage. Read in _input, before the
#                              B [Circle],       pause menu's _unhandled_input, and only consumed
#                              Menu [Options]    when there is a stage to step back from: in IDLE
#                                                and SWAP, and while input is ignored (below, WALK
#                                                included), it is left to open the pause menu --
#                                                deliberate reuse of one key by stage. From ACTION
#                                                it snaps the walked token back. B is Godot_FE's
#                                                back and Menu its pause; both act as Escape does)
#   (Right Mouse Button)                      (step back one stage, as ui_cancel; nothing in IDLE,
#                                                SWAP and WALK)
#   "end_turn"              -> T; Y           (IDLE, MOVE: End Turn, asking first while units can
#                              [Triangle]        act. SWAP, SWAP_PICKED: Start -- deliberate reuse,
#                                                the keyboard's and pad's way to Start. Harmless
#                                                elsewhere)
#   "fast_forward"          -> F (hold);      (any stage, even during playback: while held, the
#                              RT [R2] (hold)    board plays its waits and animations, WALK's walk
#                                                included, BattleView.fast_forward_speed times
#                                                faster, in order; released, normal speed. The
#                                                trigger counts as held past halfway)
#   "skip_playback"         -> X; LT [L2]     (any stage, while playback runs: the board skips it
#                                                behind a fade to black, BattleView.skip_playback.
#                                                Harmless with nothing playing or during a skip,
#                                                so a trigger's stream of motion events is too)
#   "toggle_danger_zone"    -> R; View        (any stage, even during playback, while a session is
#                              [Create]          bound and still fought: shows or hides the danger
#                                                zone. It changes no state, so it isn't held back)
#   "cycle_weapon"          -> C; X [Square]  (CONFIRM with the forecast panel open: the forecast
#                                                and the command move to the target's next weapon,
#                                                wrapping. Harmless elsewhere, and with one weapon;
#                                                Q / E are targets, not weapons, unlike Godot_FE)
#   "toggle_save_debug"     -> F3; RS [R3]    (read by the save debug panel, in debug builds; not
#                                                read here)
#   "unit_detail"           -> Ctrl; LS [L3]  (IDLE, MOVE: opens the detail of the unit under the
#                                                cursor, else of the selected one (DETAIL); with
#                                                neither, harmless. DETAIL: closes it, as Back
#                                                does. Godot_FE's "details" key; its Square went
#                                                to cycle_weapon. The unit panel's Details button
#                                                is the mouse's way in, Right Mouse Button its way
#                                                out, as everywhere)
#   ui_up / ui_down in DETAIL                 (scroll the detail's body while it overflows; the
#                                                Close button keeps focus. Harmless otherwise)
# ASSUMPTION: Godot_FE bound none of end_turn, toggle_danger_zone, cycle_weapon, fast_forward,
# skip_playback, toggle_save_debug or unit_detail to a pad; their pad buttons above have no basis
# (unit_detail's L3 is the one pad button left free). Every pad input is bound to one action only,
# as this file reads them in one chain and the first match wins.
# While a command's playback runs, the token walks to its picked tile (WALK), the map's combat is
# over, or the seat has no turn, every input but fast_forward, skip_playback and
# toggle_danger_zone is ignored: that guard is deliberate, not a missing check (Godot_FE took no
# input until a walk arrived either). skip_playback does nothing in WALK, as no fact plays.
# pad_repeat still sees the d-pad and stick then, so a direction released during playback stops
# repeating.
# Control hints: LIVE_ACTIONS (below the state block) lists, per stage, the actions above that act
# there, with the panels' focus moves, the pause menu's Esc and the save debug panel's F3; the
# hint bar shows them with their keys or glyphs. A binding whose meaning or stage changes here
# changes that table in the same edit.
# ============================================================

# --- Turn input stage (meaningful once bind() has a session) -------------------------------
# INACTIVE:    nothing to do: unbound, the combat is over, the seat has no turn (another phase,
#              or it ended its turn), or a sent command's playback is running. Input is ignored
#              and the board shows no selection.
# SWAP:        the opening swap window, before the seat's Start. Cursor free. Accept on one of
#              the seat's units that has a swap partner picks it (SWAP_PICKED). end_turn or the
#              window's Start sends StartCommand. Cancel is left to the pause menu. No intents
#              exist yet; the danger zone shows unless toggled off, and goes off at Start.
# SWAP_PICKED: a unit picked to swap; its partners' tiles show on the move overlay. Accept on a
#              partner sends the swap (UnitTurnCommand OPENING_SWAP) with no confirm; accept
#              elsewhere is inert. Cancel -> SWAP.
# IDLE:        the seat's player phase, nothing selected. Cursor free. Accept on a unit that can
#              act selects it (MOVE); on an enemy toggles its range on the enemy range overlays,
#              red for what it could attack and purple for what it could support (Godot_FE
#              toggle_selected_unit); elsewhere inert -- Godot_FE's game menu on an empty tile is
#              not ported, End Turn has its own key and button. Q / E move the cursor and camera
#              to the next or previous of the seat's units that can act (cycle_unit), selecting
#              nothing. In every stage the cursor on an enemy shows its target rule and narrows
#              the intent lines to its own.
# MOVE:        a unit selected: its move, attack (red) and support (purple) tiles drawn, and the
#              path to the cursor while
#              the cursor is on a move tile, with that tile's move preview (requested on each
#              hover, started on a worker thread by run_preview_frame and drawn when it finishes,
#              cleared off a move tile and on leaving for any stage but WALK to CONFIRM, which
#              drops one still running); the intent display shows the preview's intents,
#              previewed, and the live ones until one is drawn and once it clears. The danger
#              zone stays the board's here.
#              Accept on another move tile walks the token there (WALK); on its own tile it opens
#              the action menu at once (ACTION); elsewhere inert. Either way the picked tile's
#              preview is kept (below). Cancel -> IDLE.
# WALK:        the token walks the path to the picked tile at the playback walk speed
#              (BattleView.stage_walk), locally: the session is untouched. No overlay; the path
#              and cursor stay. Every input is ignored, as in playback, but is_settled() holds, so
#              the hint context is WALK, not PLAYBACK. On arrival (staged_walk_finished) the action
#              menu opens: ACTION, with MOVE, not WALK, as the stage Cancel returns to.
# ACTION:      the action menu on top of PanelHost; the token stands on the picked tile and the
#              cursor on it, and board clicks and hovers are inert. An action with targets opens
#              the target picker (TARGET); Wait and Swap send their command at once, as Godot_FE's
#              Wait does. Cancel -> MOVE, the token snapped back to its tile at once (Godot_FE
#              walked it back; question 34 (3) snaps).
# TARGET:      the action's TargetList, built once when it was chosen, and the target picker
#              listing it. Every target is outlined (TargetMark) and its tile drawn, purple for
#              Staff and Item, red for the rest; the current target's outline is stronger, its
#              row focused and the cursor (target colour) on it. Q / E, a focused row and the
#              mouse over a target move the current target; the cursor follows the mouse
#              elsewhere. A row, accept, or a click on a target's tile opens the confirm for that
#              target (CONFIRM). Cancel -> ACTION.
# CONFIRM:     Attack, Staff, Shove: the forecast panel (with forecast_panel_scene set), whose
#              Confirm sends the command of the weapon shown; cycle_weapon and Next weapon move to
#              the target's next weapon. While it is open the board flashes the HP and Stance its
#              forecast predicts on every unit it changes, following each target and weapon
#              change, cleared when it closes. Item, Rune, or no forecast scene: the confirm dialog,
#              whose Confirm sends the command. Q / E move to the next target and the panel
#              follows; the outlines stay. Cancel or Back -> TARGET, on the target shown, back to
#              its first weapon.
# END_CONFIRM: End Turn's question while units can still act: Confirm sends EndTurnCommand.
#              Cancel or Back -> the stage it was asked from (IDLE or MOVE).
# DETAIL:      a unit's detail panel (UnitDetailPanel) over IDLE or MOVE, for the unit under the
#              cursor, else the selected one, either side. The board is inert: no cursor, no
#              clicks; MOVE's overlays and path stay drawn, its hover preview is dropped and asked
#              again on return. Up and down scroll the panel; accept presses its Close. Cancel,
#              Close or unit_detail -> the stage it was opened from, with its selection and cursor
#              as they were. Opened through _history like any panel, so it is never left open by
#              a command (none can be sent from it).
# There is no separate forecast stage: the forecast is CONFIRM's panel, as Godot_FE's forecast
# took the confirm. The walk before the action menu is the board's alone: the move and the action
# are still one command, so the session changes only on Confirm, and its playback finds the token
# already on its tile and doesn't walk it again (BattleView._on_unit_moved). Another seat's screen
# never staged it, so a co-op partner sees the walk in that playback. From WALK to CONFIRM the
# intents, the danger zone and the darkness number are the picked tile's move preview's
# (question 35 (1)), still running on its worker when the pick comes before it finished, so no
# intent line points at the tile the unit left; the board's show until it is drawn. Cancel's snap
# back to MOVE clears it, and the session's return. The forecast walks the command's path itself.
# Cycling changes no state: each weapon has its own command (TargetOption.commands),
# where Godot_FE equipped the weapon on the unit at each step and left it equipped on Back. Q / E
# are inert in SWAP, SWAP_PICKED, MOVE, WALK, ACTION, END_CONFIRM and DETAIL: cycling units there
# would drop the selection or the panel under way (Godot_FE's details screen cycled units on its
# bumpers; not ported).
# Global: cancel pops exactly one stage (_history), and one panel with it; WALK is never on
# _history. Sending a command flushes every panel, stage and mark but leaves a staged token where
# it stands, hides the intents, and waits in INACTIVE; when its playback settles the stage, the
# danger zone and the intents are rebuilt from the session, a staged walk still standing (the
# command rejected) snapping back: a rejection's reason shows and the flow returns to IDLE, a unit
# with a second move pending reopens MOVE on its new tile, and otherwise IDLE, SWAP or INACTIVE as
# the session stands.
# Hint contexts (LIVE_ACTIONS, get_hint_context()) are these stages' names and three more:
# FORECAST is CONFIRM on the forecast panel; PLAYBACK is any stage while a command's playback runs
# (only fast_forward, skip_playback, toggle_danger_zone and the pause menu's Esc act), the final
# playback after the battle is decided included, until it settles and the end banner shows;
# PAUSED is the pause menu open over any stage, where this node is paused and the menu takes the
# arrows, accept and Esc. In multiplayer the menu doesn't pause, so PAUSED never comes. With
# nothing bound, or the combat over and its playback settled, there is no context.
## The steps of turn input; see the block above.
enum Stage {
	## Nothing to do; input is ignored.
	INACTIVE = 0,
	## The opening swap window, nothing picked.
	SWAP = 1,
	## The opening swap window, one unit picked.
	SWAP_PICKED = 2,
	## The player phase, nothing selected.
	IDLE = 3,
	## A unit selected, picking its tile.
	MOVE = 4,
	## The action menu.
	ACTION = 5,
	## The target picker.
	TARGET = 6,
	## The confirm dialog before a targeted action is sent.
	CONFIRM = 7,
	## End Turn's question while units can still act.
	END_CONFIRM = 8,
	## The token walking to the picked tile before the action menu opens.
	WALK = 9,
	## A unit's detail panel, opened from IDLE or MOVE.
	DETAIL = 10,
}

const PLAYER: CombatFact.CombatSide = CombatFact.CombatSide.PLAYER
const ENEMY: CombatFact.CombatSide = CombatFact.CombatSide.ENEMY

# --- Live actions by hint context: the hint bar's one source ---------------------------------
# Each row is what acts in that context, read from the state and input blocks above: the arrows
# where they move the cursor or a panel's focus (a menu's and the picker's rows go up and down
# only; the forecast's and the dialogs' buttons sit side by side), Q / E in IDLE, TARGET and
# CONFIRM, accept wherever it picks, presses or confirms, cycle_weapon on the forecast only.
# ui_cancel is the pause menu's in SWAP, IDLE, PLAYBACK and INACTIVE (this node leaves Esc to it
# there), and toggle_save_debug is the save debug panel's. Order is the bar's display order.
# get_live_actions() leaves out what a row lists but can do nothing now (question 31 (a)): Q / E
# with one target and C with one weapon in TARGET, CONFIRM and FORECAST, the danger zone in
# the final playback, unit_detail in IDLE and MOVE with no unit to show, and DETAIL's up and down
# while its body fits. tests/ui/hint_bar_cases.gd presses every action in every context it
# reaches, by key and by pad, and fails when one acts outside its row or a listed one does
# nothing; change a row with the blocks above.
# ASSUMPTION: fast_forward is listed in every unpaused context, since holding it before a command
# speeds that command's playback; skip_playback only in PLAYBACK, as it is harmless otherwise.
## The actions live in each hint context ([method get_hint_context]), as [StringName]s in the
## order the [ControlHintBar] shows them; see [method get_live_actions].
const LIVE_ACTIONS: Dictionary[StringName, Array] = {
	&"SWAP": [
		&"ui_up", &"ui_down", &"ui_left", &"ui_right", &"ui_accept", &"end_turn",
		&"toggle_danger_zone", &"fast_forward", &"ui_cancel", &"toggle_save_debug",
	],
	&"SWAP_PICKED": [
		&"ui_up", &"ui_down", &"ui_left", &"ui_right", &"ui_accept", &"ui_cancel", &"end_turn",
		&"toggle_danger_zone", &"fast_forward", &"toggle_save_debug",
	],
	&"IDLE": [
		&"ui_up", &"ui_down", &"ui_left", &"ui_right", &"ui_accept", &"target_prev",
		&"target_next", &"unit_detail", &"end_turn", &"toggle_danger_zone", &"fast_forward",
		&"ui_cancel", &"toggle_save_debug",
	],
	&"MOVE": [
		&"ui_up", &"ui_down", &"ui_left", &"ui_right", &"ui_accept", &"ui_cancel", &"unit_detail",
		&"end_turn", &"toggle_danger_zone", &"fast_forward", &"toggle_save_debug",
	],
	&"DETAIL": [
		&"ui_up", &"ui_down", &"ui_accept", &"ui_cancel", &"unit_detail", &"toggle_danger_zone",
		&"fast_forward", &"toggle_save_debug",
	],
	&"ACTION": [
		&"ui_up", &"ui_down", &"ui_accept", &"ui_cancel", &"toggle_danger_zone", &"fast_forward",
		&"toggle_save_debug",
	],
	&"TARGET": [
		&"ui_up", &"ui_down", &"target_prev", &"target_next", &"ui_accept", &"ui_cancel",
		&"toggle_danger_zone", &"fast_forward", &"toggle_save_debug",
	],
	&"FORECAST": [
		&"ui_up", &"ui_down", &"ui_left", &"ui_right", &"ui_accept", &"target_prev",
		&"target_next", &"cycle_weapon", &"ui_cancel", &"toggle_danger_zone", &"fast_forward",
		&"toggle_save_debug",
	],
	&"CONFIRM": [
		&"ui_left", &"ui_right", &"ui_accept", &"target_prev", &"target_next", &"ui_cancel",
		&"toggle_danger_zone", &"fast_forward", &"toggle_save_debug",
	],
	&"END_CONFIRM": [
		&"ui_left", &"ui_right", &"ui_accept", &"ui_cancel", &"toggle_danger_zone",
		&"fast_forward", &"toggle_save_debug",
	],
	&"WALK": [&"toggle_danger_zone", &"fast_forward", &"ui_cancel", &"toggle_save_debug"],
	&"PLAYBACK": [
		&"fast_forward", &"skip_playback", &"toggle_danger_zone", &"ui_cancel",
		&"toggle_save_debug",
	],
	&"INACTIVE": [&"toggle_danger_zone", &"fast_forward", &"ui_cancel", &"toggle_save_debug"],
	&"PAUSED": [&"ui_up", &"ui_down", &"ui_accept", &"ui_cancel"],
}

@export_group("Panels")

## The action menu scene ([ActionMenu]).[br]
## [b]Unset:[/b] picking a tile opens nothing and an error is reported.
@export var action_menu_scene: PackedScene = null

## The target picker scene ([TargetPicker]).[br]
## [b]Unset:[/b] actions with targets open nothing and an error is reported.
@export var target_picker_scene: PackedScene = null

## The confirm dialog scene ([ConfirmDialog]), for targeted actions and End Turn.[br]
## [b]Unset:[/b] no confirm opens and an error is reported.
@export var confirm_dialog_scene: PackedScene = null

## The forecast panel scene ([ForecastPanel]), the confirm of an attack, a staff or a shove.[br]
## [b]Unset:[/b] those confirm on the confirm dialog, with no forecast.
@export var forecast_panel_scene: PackedScene = null

## The unit detail panel scene ([UnitDetailPanel]), opened by unit_detail or the unit panel's
## Details button.[br]
## [b]Unset:[/b] unit_detail opens nothing and an error is reported.
@export var unit_detail_scene: PackedScene = null

@export_group("Widgets")

## The board: its cursor, overlays and path, and the playback input waits on.[br]
## [b]Unset:[/b] [method bind] reports an error and turn input stays off.
@export var view: BattleView = null

## The panel stack the menu, picker and dialogs open on.[br]
## [b]Unset:[/b] [method bind] reports an error and turn input stays off.
@export var panel_host: PanelHost = null

## The status line and End Turn button.[br]
## [b]Unset:[/b] no status shows; the end_turn action still works.
@export var turn_bar: TurnBar = null

## The opening swap window's panel and Start button.[br]
## [b]Unset:[/b] no hint shows; the end_turn action still sends Start.
@export var swap_window: SwapWindow = null

## Where rejection reasons show.[br]
## [b]Unset:[/b] rejections are only logged by the session.
@export var message: BattleMessage = null

## The move preview on the board, a child of [member view].[br]
## [b]Unset:[/b] no move preview's damage shows; with [member intent_display] also unset, no
## preview is requested or run.
@export var move_preview_marks: MovePreviewMarks = null

## The enemies' intents on the board, a child of [member view].[br]
## [b]Unset:[/b] no intents, lines or target rules show.
@export var intent_display: IntentDisplay = null

## Repeats a held d-pad direction or stick push as cursor steps.[br]
## [b]Unset:[/b] each joypad direction event is read as a press, so a held d-pad steps once and a
## stick push steps once per motion event past the deadzone.
@export var pad_repeat: PadRepeat = null

@export_group("Danger zone")

# ASSUMPTION: question 12's "the window shows the danger zone" read as on by default in the window,
# R still toggling it, and back off at Start (question 10's default for the player phase).
## Whether the danger zone shows when the opening swap window opens (plan, question 12). It goes
## off at Start whatever its state, as toggle_danger_zone's default is off.[br]
## [b]Off:[/b] the swap window follows toggle_danger_zone too, starting hidden.
@export var shows_danger_in_swap_window: bool = true

@export_group("")

var _encounter: CombatEncounter = null
var _session: CombatSession = null
var _seat: int = -1

var _stage: Stage = Stage.INACTIVE

# The stage to return to from each stage entered by a step forward; cancel pops one.
var _history: Array[Stage] = []

var _cursor: Vector2i = CombatFact.NO_TILE

# The selection, filled as the flow steps forward and cleared as it steps back.
var _unit_id: String = ""
var _move_tiles: Array[Vector2i] = []
var _attack_tiles: Array[Vector2i] = []
var _support_tiles: Array[Vector2i] = []
var _is_move_tile: Dictionary[Vector2i, bool] = {}
var _end_tile: Vector2i = CombatFact.NO_TILE
var _path: Array[Vector2i] = []
var _action: TurnInputModel.ActionOption = null

# In TARGET and CONFIRM, the action's targets; its current target and weapon are what CONFIRM
# shows and sends. Null elsewhere.
var _targets: TargetList = null

# The panel open in CONFIRM: the forecast panel, or the confirm dialog; null outside CONFIRM.
var _forecast_panel: ForecastPanel = null
var _confirm_dialog: ConfirmDialog = null

# The target picker open in TARGET and under CONFIRM; null elsewhere.
var _picker: TargetPicker = null

# The unit detail panel open in DETAIL; null elsewhere.
var _detail_panel: UnitDetailPanel = null

# Whether unit_detail had a unit to show when the hints were last told, so a cursor move that
# changes it tells them again.
var _has_detail_unit: bool = false

# In WALK, the action menu's rows for the picked tile, opened on arrival; empty elsewhere.
var _walk_options: Array[TurnInputModel.ActionOption] = []

# The newest hover's move preview, waiting for run_preview_frame, and the one on a worker thread.
var _previews: MovePreview.Queue = MovePreview.Queue.new()

# What accept on a tile picks in SWAP_PICKED: the partners.
var _targets_by_tile: Dictionary[Vector2i, TurnInputModel.TargetOption] = {}

# The enemies whose range is toggled on, in the order they were toggled.
var _shown_enemies: PackedStringArray = []

# A command was sent and its playback hasn't settled.
var _is_waiting: bool = false

# The unit the command being waited on acted for; empty for none.
var _sent_unit_id: String = ""

# The rejection of the command last sent; empty when it resolved.
var _rejection: String = ""

# Whether the danger zone is toggled on, and the zone drawn (the board at the last settle) with
# its support tiles.
var _is_danger_shown: bool = false
var _danger: DangerZone = null
var _danger_support: Array[Vector2i] = []

# Whether the stage was last rebuilt in the swap window, so leaving it turns the danger zone off.
var _was_swapping: bool = false


func _ready() -> void:
	_show_widgets(false)
	if turn_bar != null:
		turn_bar.end_turn_pressed.connect(_on_turn_bar_end_turn_pressed)
	if swap_window != null:
		swap_window.start_pressed.connect(_on_swap_window_start_pressed)
	if pad_repeat != null:
		pad_repeat.stepped.connect(_on_pad_repeat_stepped)


func _exit_tree() -> void:
	unbind()
	# Every WorkerThreadPool task must be waited for; unbind dropped its result already.
	_previews.wait()


func _input(event: InputEvent) -> void:
	if not _is_cancel(event) or not is_accepting_input():
		return
	if step_back():
		get_viewport().set_input_as_handled()


func _unhandled_input(event: InputEvent) -> void:
	if _session == null:
		return
	if event.is_action(&"fast_forward") and not event.is_echo():
		view.set_fast_forward(event.is_pressed())
		return
	if event.is_action_pressed(&"skip_playback"):
		view.skip_playback()
		return
	if event.is_action_pressed(&"toggle_danger_zone"):
		toggle_danger_zone()
		return
	if is_instance_valid(pad_repeat) and pad_repeat.take(event):
		return
	if not is_accepting_input():
		return
	var mouse: InputEventMouse = event as InputEventMouse
	if mouse != null:
		_read_mouse(mouse)
	elif event.is_action_pressed(&"ui_accept"):
		confirm_tile(_cursor)
	elif event.is_action_pressed(&"end_turn"):
		request_end_turn()
	elif event.is_action_pressed(&"unit_detail"):
		if _stage == Stage.DETAIL:
			step_back()
		else:
			request_unit_detail()
	elif event.is_action_pressed(&"cycle_weapon"):
		cycle_weapon()
	elif event.is_action_pressed(&"target_next"):
		_cycle(true)
	elif event.is_action_pressed(&"target_prev"):
		_cycle(false)
	elif event.is_action_pressed(&"ui_up", true):
		_step_cursor(Vector2i.UP)
	elif event.is_action_pressed(&"ui_down", true):
		_step_cursor(Vector2i.DOWN)
	elif event.is_action_pressed(&"ui_left", true):
		_step_cursor(Vector2i.LEFT)
	elif event.is_action_pressed(&"ui_right", true):
		_step_cursor(Vector2i.RIGHT)


func _process(_delta: float) -> void:
	run_preview_frame()


## Takes turn input for [param seat] on [param session], a map of [param encounter], and shows the
## widgets. Binding again replaces the map.
func bind(encounter: CombatEncounter, session: CombatSession, seat: int) -> void:
	unbind()
	if view == null or panel_host == null:
		push_error("BattleController: the view and the panel host must be set")
		return
	_encounter = encounter
	_session = session
	_seat = seat
	_session.command_rejected.connect(_on_session_command_rejected)
	_session.intents_changed.connect(_on_session_intents_changed)
	view.settled.connect(_on_view_settled)
	view.staged_walk_finished.connect(_on_view_staged_walk_finished)
	_show_widgets(true)
	_was_swapping = TurnInputModel.is_swapping(session, seat)
	_is_danger_shown = _was_swapping and shows_danger_in_swap_window
	_danger = null
	var units: PackedStringArray = TurnInputModel.acting_units(session, seat)
	if units.is_empty():
		for unit_id: String in session.state.units_of(PLAYER):
			if session.state.seat_of(unit_id) == seat:
				units.append(unit_id)
	move_cursor(session.state.tile_of(units[0]) if not units.is_empty() else Vector2i.ZERO)
	_rebuild()


## Stops taking input and hides the widgets. Does nothing when nothing is bound.
func unbind() -> void:
	if _session == null:
		return
	if _session.command_rejected.is_connected(_on_session_command_rejected):
		_session.command_rejected.disconnect(_on_session_command_rejected)
	if _session.intents_changed.is_connected(_on_session_intents_changed):
		_session.intents_changed.disconnect(_on_session_intents_changed)
	if view != null and view.settled.is_connected(_on_view_settled):
		view.settled.disconnect(_on_view_settled)
	if (
			is_instance_valid(view)
			and view.staged_walk_finished.is_connected(_on_view_staged_walk_finished)
	):
		view.staged_walk_finished.disconnect(_on_view_staged_walk_finished)
	if is_instance_valid(view):
		view.set_fast_forward(false)
		view.unstage_walk()
	if panel_host != null:
		panel_host.flush()
	if is_instance_valid(pad_repeat):
		pad_repeat.release_all()
	_session = null
	_encounter = null
	_danger = null
	_set_stage(Stage.INACTIVE)
	_draw_target_marks()
	_draw_danger_zone()
	_show_intents()
	_show_widgets(false)


## The stage turn input is at.
func get_stage() -> Stage:
	return _stage


## The unit selected; empty when none is.
func get_selected_unit() -> String:
	return _unit_id


## The tile the cursor is on.
func get_cursor_tile() -> Vector2i:
	return _cursor


## The walk the selected unit would be sent with: to the hovered tile in MOVE, to the picked tile
## after (the walk WALK shows); empty for none or its own tile.
func get_walk() -> Array[Vector2i]:
	return _path.duplicate()


## The enemies whose range is toggled on.
func get_shown_enemies() -> PackedStringArray:
	return _shown_enemies.duplicate()


## The hint context the screen is in, a key of [constant LIVE_ACTIONS]: PAUSED while the tree is
## paused, PLAYBACK while a command plays (the battle's final playback included), FORECAST in
## CONFIRM on the forecast panel, else the stage's name; empty while nothing is bound, or once the
## combat is over and its playback has settled. Cheap enough to poll.
func get_hint_context() -> StringName:
	if _session == null:
		return &""
	var is_playing: bool = _is_waiting or not view.is_settled()
	if _session.is_finished and not is_playing:
		return &""
	if is_inside_tree() and get_tree().paused:
		return &"PAUSED"
	if is_playing:
		return &"PLAYBACK"
	if _stage == Stage.CONFIRM and is_instance_valid(_forecast_panel):
		return &"FORECAST"
	return StringName(Stage.find_key(_stage) as String)


## The actions live now: [constant LIVE_ACTIONS]' row for [method get_hint_context], less what
## can do nothing now (question 31 (a)): target_prev and target_next with one target and
## cycle_weapon with one weapon while targeting, toggle_danger_zone once the combat is over, and
## toggle_save_debug outside debug builds, where the save debug panel removes itself. Empty while
## there is no context.
func get_live_actions() -> Array[StringName]:
	var actions: Array[StringName] = []
	var context: StringName = get_hint_context()
	if context.is_empty():
		return actions
	for action: StringName in LIVE_ACTIONS.get(context, []):
		if _can_act_now(context, action):
			actions.append(action)
	return actions


## Whether input is taken now: a session is bound and still fought, no command's playback is
## running, no token walks to its picked tile (WALK), and the seat has something to do
## ([enum Stage] isn't INACTIVE).
func is_accepting_input() -> bool:
	return (
			_session != null
			and not _session.is_finished
			and not _is_waiting
			and view.is_settled()
			and _stage != Stage.INACTIVE
			and _stage != Stage.WALK
	)


## Moves the cursor to [param tile] when it is on the map, redrawing the path in MOVE and asking
## for the tile's move preview there. Returns whether it moved.
func move_cursor(tile: Vector2i) -> bool:
	if _session == null or not _is_on_map(tile):
		return false
	_cursor = tile
	view.get_cursor().show_at(tile, view.tile_to_position(tile))
	if _stage == Stage.MOVE:
		_path = TurnInputModel.path_to(_session, _unit_id, tile)
		_draw_path()
		_request_preview(tile)
	if is_instance_valid(intent_display):
		intent_display.set_hovered(_hovered_enemy())
	var has_detail_unit: bool = not detail_unit().is_empty()
	if has_detail_unit != _has_detail_unit:
		_has_detail_unit = has_detail_unit
		live_actions_changed.emit()
	return true


## The unit unit_detail would show now: the one under the cursor, else the selected one; empty
## for none, or outside IDLE and MOVE.
func detail_unit() -> String:
	if _session == null or (_stage != Stage.IDLE and _stage != Stage.MOVE):
		return ""
	var occupant: String = _session.state.occupant_at(_cursor)
	# A standing breakable occupies its tile too, but it is on neither side and has no detail.
	if not occupant.is_empty() and _session.state.side_of(occupant) != CombatFact.CombatSide.NONE:
		return occupant
	return _unit_id


## unit_detail, or the unit panel's Details button: opens [param unit_id]'s [UnitDetailPanel]
## (DETAIL) over IDLE or MOVE; with none given, [method detail_unit]'s. Returns false, opening
## nothing, outside IDLE and MOVE, while input isn't taken, or for a unit not on the map.
func request_unit_detail(unit_id: String = "") -> bool:
	if not is_accepting_input() or (_stage != Stage.IDLE and _stage != Stage.MOVE):
		return false
	var shown: String = unit_id if not unit_id.is_empty() else detail_unit()
	var detail: UnitDetailViewModel = UnitDetailViewModel.build(_session, shown)
	if detail == null:
		return false
	var panel: BattlePanel = _open_panel(Stage.DETAIL, unit_detail_scene, detail)
	if panel == null:
		return false
	_detail_panel = panel as UnitDetailPanel
	panel.cancelled.connect(_on_panel_cancelled)
	if _detail_panel != null:
		_detail_panel.scroll_range_changed.connect(_on_detail_panel_scroll_range_changed)
	_redraw()
	return true


## The unit detail panel open in DETAIL; null elsewhere.
func get_detail_panel() -> UnitDetailPanel:
	return _detail_panel if _stage == Stage.DETAIL else null


## toggle_danger_zone: shows or hides every tile an enemy could attack next turn
## ([method DangerZone.compute], on the board as it last settled). Returns whether it now shows;
## false, doing nothing, while nothing is bound or the combat is over.
func toggle_danger_zone() -> bool:
	if _session == null or _session.is_finished:
		return false
	_is_danger_shown = not _is_danger_shown
	_draw_danger_zone()
	return _is_danger_shown


## Whether the danger zone is toggled on.
func is_danger_zone_shown() -> bool:
	return _is_danger_shown


## Weapon cycling in the forecast (cycle_weapon, Next weapon): shows the target's next weapon's
## forecast, wrapping, and makes its command the one Confirm sends. Returns false, doing nothing,
## outside CONFIRM's forecast panel or with one weapon.
func cycle_weapon() -> bool:
	if _stage != Stage.CONFIRM or _forecast_panel == null or _targets == null:
		return false
	if not _targets.next_weapon():
		return false
	_forecast_panel.show_forecast(_forecast_model())
	_draw_forecast_preview()
	return true


## The command Confirm would send now: in CONFIRM, the current target's with the weapon shown;
## null elsewhere.
func get_confirm_command() -> Command:
	if _stage != Stage.CONFIRM or _targets == null:
		return null
	return _targets.command()


## The chosen action's targets, in TARGET and CONFIRM; null elsewhere.
func get_target_list() -> TargetList:
	return _targets


## target_next / target_prev while targeting: makes the next ([param forward]) or previous target
## current, wrapping, with the cursor, outlines and focused row on it; in CONFIRM the panel shows
## it. Returns false, doing nothing, outside TARGET and CONFIRM or with one target.
func cycle_target(forward: bool) -> bool:
	if not is_accepting_input() or _targets == null:
		return false
	if _stage != Stage.TARGET and _stage != Stage.CONFIRM:
		return false
	var moved: bool = _targets.next_target() if forward else _targets.previous_target()
	if moved:
		_show_current_target()
	return moved


## target_next / target_prev in IDLE: moves the cursor and the camera to the next
## ([param forward]) or previous of the seat's units that can act, from the unit under the cursor
## ([method TurnInputModel.cycle_unit]). Returns that unit; empty, doing nothing, outside IDLE or
## when none can act.
func cycle_unit(forward: bool) -> String:
	if not is_accepting_input() or _stage != Stage.IDLE:
		return ""
	var unit_id: String = TurnInputModel.cycle_unit(
			_session, _seat, _session.state.occupant_at(_cursor), forward
	)
	if unit_id.is_empty():
		return ""
	var tile: Vector2i = _session.state.tile_of(unit_id)
	move_cursor(tile)
	view.focus_tile(tile)
	return unit_id


## Draws the move preview that finished on its worker thread, if one did: its damage, and its
## intents as previewed (from WALK to CONFIRM, its danger zone too); then starts the newest
## hover's when none runs ([method MovePreview.Queue.run_pending]). Runs in MOVE and from WALK to
## CONFIRM, where the picked tile's preview is kept. [method Node._process] calls it once a frame;
## tests call it to stand for a frame, and [method MovePreview.Queue.wait] for the worker. Returns
## whether a preview was drawn.
func run_preview_frame() -> bool:
	if _session == null or not _has_preview_widgets() or not _keeps_preview(_stage):
		return false
	var preview: MovePreview = _previews.run_pending(_session)
	if preview == null:
		return false
	if move_preview_marks != null:
		move_preview_marks.show_preview(preview, view.tile_to_position(preview.tile))
	_show_intents()
	if _stage != Stage.MOVE:
		_draw_danger_zone()
	return true


## The move preview queue, for tests and benchmarks that count the previews run.
func get_preview_queue() -> MovePreview.Queue:
	return _previews


## Accept on [param tile]: what it does depends on the stage (see the state block). Ignored while
## input isn't taken.
func confirm_tile(tile: Vector2i) -> void:
	if not is_accepting_input() or not _is_on_map(tile):
		return
	var occupant: String = _session.state.occupant_at(tile)
	match _stage:
		Stage.SWAP:
			if not occupant.is_empty() and _session.state.seat_of(occupant) == _seat:
				_pick_swap_unit(occupant)
		Stage.SWAP_PICKED:
			if _targets_by_tile.has(tile):
				_send(_targets_by_tile[tile].command)
		Stage.IDLE:
			if occupant.is_empty():
				return
			if (
					_session.state.seat_of(occupant) == _seat
					and TurnInputModel.can_act(_session, occupant)
			):
				_select(occupant)
			elif _session.state.side_of(occupant) == ENEMY:
				_toggle_enemy_range(occupant)
		Stage.MOVE:
			if _is_move_tile.has(tile):
				_pick_tile(tile)
		Stage.TARGET:
			var index: int = _targets.index_at(tile)
			if index >= 0:
				_pick_target(index)


## Cancel: steps back exactly one stage, closing the panel that stage opened; out of ACTION, or of
## WALK (which input never steps back from, but a caller may), the token snaps back to its tile.
## Returns false, doing nothing, where there is nothing to step back from (INACTIVE, SWAP, IDLE).
func step_back() -> bool:
	if _history.is_empty():
		return false
	match _stage:
		Stage.ACTION, Stage.TARGET, Stage.CONFIRM, Stage.END_CONFIRM, Stage.DETAIL:
			panel_host.back()
	var leaving: Stage = _stage
	var previous: Stage = _history.pop_back()
	_set_stage(previous)
	match leaving:
		Stage.SWAP_PICKED, Stage.MOVE:
			_clear_selection()
		Stage.ACTION, Stage.WALK:
			view.unstage_walk()
			_walk_options.clear()
			_action = null
			_end_tile = CombatFact.NO_TILE
			move_cursor(_cursor)
			# The snap back clears the picked tile's preview, so the session's intents and zone
			# return (question 35 (1)).
			# ASSUMPTION: the cursor stays on the picked tile and its hover preview isn't asked
			# again until the cursor moves, so the session's intents stay shown after Cancel.
			_clear_preview()
		Stage.TARGET:
			_targets = null
			_picker = null
			move_cursor(_end_tile)
		Stage.CONFIRM:
			_targets.reset_weapon()
			_forecast_panel = null
			_confirm_dialog = null
			_show_current_target()
		Stage.DETAIL:
			_detail_panel = null
			# Asks MOVE's hover preview again, which DETAIL dropped.
			move_cursor(_cursor)
	_redraw()
	return true


## End Turn, from the key or the button: in the swap window it is Start; in IDLE or MOVE it sends
## [EndTurnCommand], asking first while any of the seat's units can still act. Ignored elsewhere.
func request_end_turn() -> void:
	if not is_accepting_input():
		return
	if _stage == Stage.SWAP or _stage == Stage.SWAP_PICKED:
		# ASSUMPTION: end_turn presses Start in the swap window, the keyboard's only way to it.
		request_start()
		return
	if _stage != Stage.IDLE and _stage != Stage.MOVE:
		return
	var command: EndTurnCommand = TurnInputModel.end_turn_command(_session, _seat)
	if command == null:
		return
	var left: int = TurnInputModel.acting_units(_session, _seat).size()
	if left == 0:
		_send(command)
		return
	var dialog: BattlePanel = _open_panel(Stage.END_CONFIRM, confirm_dialog_scene, (
			"%d %s can still act. End the turn?" % [left, "unit" if left == 1 else "units"]
	))
	if dialog != null:
		dialog.confirmed.connect(_on_end_turn_dialog_confirmed)
		dialog.cancelled.connect(_on_panel_cancelled)


## Start in the opening swap window ([StartCommand]). Ignored outside it.
func request_start() -> void:
	if not is_accepting_input():
		return
	if _stage != Stage.SWAP and _stage != Stage.SWAP_PICKED:
		return
	var command: StartCommand = TurnInputModel.start_command(_session, _seat)
	if command != null:
		_send(command)


func _read_mouse(mouse: InputEventMouse) -> void:
	var local: InputEventMouse = view.make_input_local(mouse) as InputEventMouse
	var tile: Vector2i = view.tile_at(local.position)
	var button: InputEventMouseButton = mouse as InputEventMouseButton
	if button != null:
		if not button.pressed:
			return
		# A HUD button clicked earlier keeps keyboard focus, and would take ui_accept from the
		# board; a panel's rows keep theirs.
		if panel_host.depth() == 0:
			get_viewport().gui_release_focus()
		if button.button_index == MOUSE_BUTTON_LEFT and _follows_mouse():
			move_cursor(tile)
			confirm_tile(tile)
		return
	if _follows_mouse() and tile != _cursor:
		move_cursor(tile)
		if _stage == Stage.TARGET and _targets.select(_targets.index_at(tile)):
			_show_current_target()


# Whether action, listed in context's row, can do anything now (see get_live_actions()).
func _can_act_now(context: StringName, action: StringName) -> bool:
	match action:
		&"toggle_save_debug":
			return OS.is_debug_build()
		&"toggle_danger_zone":
			return not _session.is_finished
		&"cycle_weapon":
			return _targets != null and _targets.weapon_count() > 1
		&"target_prev", &"target_next":
			if context == &"IDLE":
				return true
			return _targets != null and _targets.targets().size() > 1
		&"unit_detail":
			if context == &"DETAIL":
				return true
			return unit_detail_scene != null and not detail_unit().is_empty()
		&"ui_up", &"ui_down":
			if context == &"DETAIL":
				return is_instance_valid(_detail_panel) and _detail_panel.can_scroll()
	return true


func _follows_mouse() -> bool:
	return _stage in [Stage.SWAP, Stage.SWAP_PICKED, Stage.IDLE, Stage.MOVE, Stage.TARGET]


# target_next / target_prev: units in IDLE, targets in TARGET and CONFIRM (see the input block).
func _cycle(forward: bool) -> void:
	if _stage == Stage.IDLE:
		cycle_unit(forward)
	else:
		cycle_target(forward)


func _step_cursor(direction: Vector2i) -> void:
	if _stage in [Stage.SWAP, Stage.SWAP_PICKED, Stage.IDLE, Stage.MOVE]:
		move_cursor(_cursor + direction)


func _is_cancel(event: InputEvent) -> bool:
	var button: InputEventMouseButton = event as InputEventMouseButton
	if button != null:
		return button.pressed and button.button_index == MOUSE_BUTTON_RIGHT
	return event.is_action_pressed(&"ui_cancel")


func _select(unit_id: String) -> void:
	_unit_id = unit_id
	_move_tiles = TurnInputModel.move_tiles(_session, unit_id)
	_attack_tiles = TurnInputModel.attack_tiles(_session, unit_id)
	_support_tiles = TurnInputModel.support_tiles(_session, unit_id)
	_is_move_tile.clear()
	for tile: Vector2i in _move_tiles:
		_is_move_tile[tile] = true
	_advance(Stage.MOVE)
	move_cursor(_session.state.tile_of(unit_id))
	_redraw()


# Accept on a move tile: another tile walks the token there first (WALK), its own opens the menu.
func _pick_tile(tile: Vector2i) -> void:
	_end_tile = tile
	_path = TurnInputModel.path_to(_session, _unit_id, tile)
	var options: Array[TurnInputModel.ActionOption] = TurnInputModel.actions_at(
			_session, _unit_id, _path
	)
	if options.is_empty():
		return
	# Kept from here to CONFIRM; a request already shown or running for the tile is reused.
	if _has_preview_widgets():
		_previews.request(_unit_id, tile)
	if not view.stage_walk(_unit_id, _path):
		_open_action_menu(options)
	else:
		_walk_options = options
		_advance(Stage.WALK)
		_redraw()
	_show_intents()
	_draw_danger_zone()


# Opens the action menu on options, stepping forward into ACTION.
func _open_action_menu(options: Array[TurnInputModel.ActionOption]) -> void:
	var menu: BattlePanel = _open_panel(Stage.ACTION, action_menu_scene, options)
	if menu == null:
		return
	menu.confirmed.connect(_on_action_menu_confirmed)
	menu.cancelled.connect(_on_panel_cancelled)
	_redraw()


func _pick_swap_unit(unit_id: String) -> void:
	var partners: Array[TurnInputModel.TargetOption] = TurnInputModel.swap_partners(
			_session, unit_id
	)
	if partners.is_empty():
		return
	_unit_id = unit_id
	_targets_by_tile.clear()
	for partner: TurnInputModel.TargetOption in partners:
		_targets_by_tile[partner.tile] = partner
	_advance(Stage.SWAP_PICKED)
	_redraw()


# The step between the target and the command: the forecast panel for an attack, a staff or a
# shove, the confirm dialog for the rest (see the state block).
func _open_confirm() -> void:
	_forecast_panel = null
	_confirm_dialog = null
	var turn: UnitTurnCommand = _targets.current().command as UnitTurnCommand
	# ASSUMPTION: the forecast takes the confirm dialog's place (Confirm on it sends), as Godot_FE's
	# forecast took ui_confirm; a second question after the forecast would ask twice.
	if forecast_panel_scene != null and turn != null and turn.needs_fresh_forecast():
		var panel: ForecastPanel = (
				_open_panel(Stage.CONFIRM, forecast_panel_scene, _forecast_model()) as ForecastPanel
		)
		if panel == null:
			return
		_forecast_panel = panel
		panel.confirmed.connect(_on_confirm_dialog_confirmed)
		panel.cancelled.connect(_on_panel_cancelled)
		panel.weapon_cycle_requested.connect(_on_forecast_panel_weapon_cycle_requested)
		_redraw()
		return
	var dialog: BattlePanel = _open_panel(Stage.CONFIRM, confirm_dialog_scene, _confirm_question())
	if dialog == null:
		return
	_confirm_dialog = dialog as ConfirmDialog
	dialog.confirmed.connect(_on_confirm_dialog_confirmed)
	dialog.cancelled.connect(_on_panel_cancelled)
	_redraw()


# The confirm dialog's question for the current target.
func _confirm_question() -> String:
	return "%s %s?" % [_action.label, _targets.current().label]


# The forecast of the current target with the weapon shown.
func _forecast_model() -> ForecastViewModel:
	var command: UnitTurnCommand = _targets.command() as UnitTurnCommand
	return ForecastViewModel.build(
			_session, command, _targets.weapon_index(), _targets.weapon_count()
	)


# Puts the cursor, the outlines and the picker's focus on the target list's current target, and
# in CONFIRM shows it on the open panel.
func _show_current_target() -> void:
	if _targets == null or _targets.is_empty():
		return
	move_cursor(_targets.current().tile)
	_draw_target_marks()
	live_actions_changed.emit()
	if is_instance_valid(_picker) and _stage == Stage.TARGET:
		_picker.focus_row(_targets.current_index())
	if _stage != Stage.CONFIRM:
		return
	if is_instance_valid(_forecast_panel):
		_forecast_panel.show_forecast(_forecast_model())
		_draw_forecast_preview()
	elif is_instance_valid(_confirm_dialog):
		_confirm_dialog.open_with(_confirm_question())


# Opens the confirm for target index of the list.
func _pick_target(index: int) -> void:
	if _stage != Stage.TARGET or _targets == null:
		return
	_targets.select(index)
	_show_current_target()
	_open_confirm()


# Outlines every target of the list, the current one strongly, by its side; none outside TARGET
# and CONFIRM.
func _draw_target_marks() -> void:
	if not is_instance_valid(view):
		return
	var marks: Array[TargetMark.Spec] = []
	if _targets != null and (_stage == Stage.TARGET or _stage == Stage.CONFIRM):
		var options: Array[TurnInputModel.TargetOption] = _targets.targets()
		for i: int in options.size():
			var spec: TargetMark.Spec = TargetMark.Spec.new()
			spec.tile = options[i].tile
			spec.side = _session.state.side_of(options[i].target_id)
			spec.is_current = i == _targets.current_index()
			marks.append(spec)
	view.show_target_marks(marks)


# Asks for tile's move preview while it is one of the selected unit's move tiles, else clears it.
func _request_preview(tile: Vector2i) -> void:
	if not _has_preview_widgets():
		return
	if _is_move_tile.has(tile):
		_previews.request(_unit_id, tile)
		return
	_clear_preview()


# Drops the preview, its damage, its intents and its danger zone; the display and the zone fall
# back to the session's.
func _clear_preview() -> void:
	var had_preview: bool = _previews.shown() != null
	_previews.clear()
	# The widgets can be freed first when the screen is torn down; unbind() still calls this.
	if is_instance_valid(move_preview_marks):
		move_preview_marks.clear()
	if had_preview:
		_show_intents()
		_draw_danger_zone()


func _has_preview_widgets() -> bool:
	return move_preview_marks != null or intent_display != null


# Whether stage shows a move preview: MOVE the hovered tile's, and WALK to CONFIRM the picked
# tile's, kept from the pick until Cancel snaps the token back (question 35 (1)).
func _keeps_preview(stage: Stage) -> bool:
	return stage in [Stage.MOVE, Stage.WALK, Stage.ACTION, Stage.TARGET, Stage.CONFIRM]


# The move preview the board shows now: the queue's in MOVE; from WALK to CONFIRM only the picked
# tile's; null elsewhere, or while it is still on its worker thread.
func _shown_preview() -> MovePreview:
	if not _keeps_preview(_stage):
		return null
	var preview: MovePreview = _previews.shown()
	if preview == null or _stage == Stage.MOVE:
		return preview
	return preview if preview.unit_id == _unit_id and preview.tile == _end_tile else null


# Draws the intents that apply now on the intent display: the shown move preview's
# (_shown_preview()), else the session's, while they are current (no newer fact), the board is
# settled and no command is waited on; otherwise none, so no icon stands where a token is still
# walking.
func _show_intents() -> void:
	if not is_instance_valid(intent_display):
		return
	var shown: Intents = null
	var is_preview: bool = false
	var changed: PackedStringArray = []
	if _session != null and not _session.is_finished and not _is_waiting and view.is_settled():
		var seq: int = _session.last_seq()
		var preview: MovePreview = _shown_preview()
		if preview != null and preview.intents != null and preview.based_on_seq == seq:
			shown = preview.intents
			is_preview = true
			changed = preview.changed_enemies
		elif _session.intents != null and _session.intents.based_on_seq == seq:
			shown = _session.intents
	if shown == null:
		intent_display.clear()
		return
	var model: IntentViewModel = IntentViewModel.build(_session, shown, is_preview, changed)
	intent_display.show_intents(model, view.tile_to_position)
	intent_display.set_hovered(_hovered_enemy())


# The enemy under the cursor; empty for none.
func _hovered_enemy() -> String:
	if _session == null or _cursor == CombatFact.NO_TILE:
		return ""
	var occupant: String = _session.state.occupant_at(_cursor)
	if occupant.is_empty() or _session.state.side_of(occupant) != ENEMY:
		return ""
	return occupant


# Draws the danger zone (red) and its support tiles (purple) while it is toggled on: from WALK to
# CONFIRM the picked tile's move preview's zone once it is drawn, else the board's as it stands,
# computed when none is kept; clears both otherwise. The preview's support tiles are the board's
# reach less what its zone threatens: support reach isn't re-planned for the move.
func _draw_danger_zone() -> void:
	# The board can be freed first when the screen is torn down; unbind() still calls this.
	if not is_instance_valid(view) or view.get_danger_overlay() == null:
		return
	var overlay: TileOverlay = view.get_danger_overlay()
	var support: TileOverlay = view.get_danger_support_overlay()
	if not _is_danger_shown or _session == null or _session.is_finished:
		overlay.clear()
		support.clear()
		return
	var zone: DangerZone = _picked_danger()
	var support_tiles: Array[Vector2i] = []
	# A kept preview with no zone of its own falls back to the board's, as before it was drawn.
	if zone != null:
		support_tiles = TurnInputModel.danger_support_tiles(_session, zone)
	else:
		if _danger == null:
			_danger = DangerZone.compute(_session.engine)
			_danger_support = TurnInputModel.danger_support_tiles(_session, _danger)
		zone = _danger
		support_tiles = _danger_support
	var tiles: Array[Vector2i] = []
	tiles.assign(zone.combined.keys())
	tiles.sort_custom(MapLayout.is_before)
	overlay.show_tiles(tiles)
	support.show_tiles(support_tiles)


# The danger zone of the picked tile's move preview, from WALK to CONFIRM while it is current; null
# in MOVE (whose zone stays the board's) and elsewhere.
func _picked_danger() -> DangerZone:
	if _stage == Stage.MOVE:
		return null
	var preview: MovePreview = _shown_preview()
	if (
			preview == null
			or preview.intents == null
			or preview.based_on_seq != _session.last_seq()
	):
		return null
	# Null when the preview kept the session's own intents (the unit's own tile) and they hold none.
	return preview.intents.danger


# Recomputes the danger zone from the board that just settled and redraws it, turning it off when
# the swap window has closed since the last rebuild.
func _refresh_danger_zone() -> void:
	_danger = null
	if _session != null:
		var is_swapping: bool = TurnInputModel.is_swapping(_session, _seat)
		if _was_swapping and not is_swapping:
			_is_danger_shown = false
		_was_swapping = is_swapping
	_draw_danger_zone()


func _toggle_enemy_range(enemy_id: String) -> void:
	var at: int = _shown_enemies.find(enemy_id)
	if at >= 0:
		_shown_enemies.remove_at(at)
	else:
		_shown_enemies.append(enemy_id)
	_draw_enemy_ranges()


# Opens scene on the panel host for stage, stepping forward into it; null when it didn't open.
func _open_panel(stage: Stage, scene: PackedScene, payload: Variant) -> BattlePanel:
	var panel: BattlePanel = panel_host.open(scene, payload)
	if panel != null:
		_advance(stage)
	return panel


func _advance(stage: Stage) -> void:
	_history.append(_stage)
	_set_stage(stage)


func _set_stage(stage: Stage) -> void:
	_stage = stage
	if not _keeps_preview(stage):
		_clear_preview()
	if view != null and view.get_cursor() != null:
		view.get_cursor().is_targeting = stage == Stage.TARGET or stage == Stage.CONFIRM
	_refresh_widgets()
	live_actions_changed.emit()


func _clear_selection() -> void:
	_unit_id = ""
	_move_tiles.clear()
	_attack_tiles.clear()
	_support_tiles.clear()
	_is_move_tile.clear()
	_end_tile = CombatFact.NO_TILE
	_path.clear()
	_action = null
	_targets = null
	_forecast_panel = null
	_confirm_dialog = null
	_picker = null
	_detail_panel = null
	_walk_options.clear()
	_targets_by_tile.clear()


# Sends command for the seat and resolves it; input waits, with the board's marks cleared, until
# its playback settles. A staged token stays where it walked: the command's move plays from there.
func _send(command: Command) -> void:
	panel_host.flush()
	_history.clear()
	_sent_unit_id = _unit_id
	_clear_selection()
	_rejection = ""
	_is_waiting = true
	_set_stage(Stage.INACTIVE)
	_redraw()
	_show_intents()
	_encounter.submit(command, _session.session_id)
	_encounter.resolve_queued()
	if view.is_settled():
		_after_playback()


# Rebuilds the stage from the session once a command's playback has settled (see the state block).
func _after_playback() -> void:
	_is_waiting = false
	var acted_id: String = _sent_unit_id
	_sent_unit_id = ""
	_rebuild()
	# ASSUMPTION: after a rejection the flow starts over at IDLE, not at the stage it was sent from.
	if not _rejection.is_empty():
		return
	if (
			_stage == Stage.IDLE
			and not acted_id.is_empty()
			and TurnInputModel.is_second_move(_session, acted_id)
			and TurnInputModel.can_act(_session, acted_id)
	):
		_select(acted_id)


# The stage the session allows with nothing selected, with every panel and selection dropped and a
# staged walk its command didn't play (a rejection) snapped back.
func _rebuild() -> void:
	view.unstage_walk()
	panel_host.flush()
	_history.clear()
	_clear_selection()
	var stage: Stage = _base_stage()
	var kept: PackedStringArray = []
	for enemy_id: String in _shown_enemies:
		if _session != null and _session.state.has_unit(enemy_id):
			kept.append(enemy_id)
	_shown_enemies = kept
	_set_stage(stage)
	if _session != null:
		move_cursor(_cursor)
	_redraw()
	_refresh_danger_zone()
	_show_intents()


# The stage the session allows with nothing selected: SWAP in the seat's swap window, IDLE in its
# player phase, else INACTIVE.
func _base_stage() -> Stage:
	if _session == null or _session.is_finished:
		return Stage.INACTIVE
	if TurnInputModel.is_swapping(_session, _seat):
		return Stage.SWAP
	if CommandValidator.player_phase_reason(_session, _seat).is_empty():
		return Stage.IDLE
	return Stage.INACTIVE


# Draws the overlays, path and cursor colour for the stage and the selection.
func _redraw() -> void:
	if view == null or _session == null:
		return
	var move: TileOverlay = view.get_move_overlay()
	var attack: TileOverlay = view.get_attack_overlay()
	var support: TileOverlay = view.get_support_overlay()
	move.clear()
	attack.clear()
	support.clear()
	match _stage:
		Stage.SWAP_PICKED:
			var partners: Array[Vector2i] = []
			partners.assign(_targets_by_tile.keys())
			move.show_tiles(partners)
		Stage.MOVE:
			move.show_tiles(_move_tiles)
			attack.show_tiles(_attack_tiles)
			support.show_tiles(_support_tiles)
		Stage.TARGET, Stage.CONFIRM:
			var tiles: Array[Vector2i] = []
			for option: TurnInputModel.TargetOption in _targets.targets():
				tiles.append(option.tile)
			if TurnInputModel.is_support_action(_action.kind):
				support.show_tiles(tiles)
			else:
				attack.show_tiles(tiles)
		Stage.END_CONFIRM, Stage.DETAIL:
			if not _unit_id.is_empty():
				move.show_tiles(_move_tiles)
				attack.show_tiles(_attack_tiles)
				support.show_tiles(_support_tiles)
	if _stage in [Stage.MOVE, Stage.END_CONFIRM, Stage.DETAIL] and not _unit_id.is_empty():
		_path = TurnInputModel.path_to(_session, _unit_id, _cursor)
	_draw_path()
	_draw_target_marks()
	_draw_enemy_ranges()
	_draw_forecast_preview()
	# Again here, as a stage's panel is kept only after _set_stage() runs (see get_hint_context()).
	live_actions_changed.emit()


func _draw_path() -> void:
	var points: PackedVector2Array = []
	for tile: Vector2i in _path:
		points.append(view.tile_to_position(tile))
	view.get_path_preview().show_path(_path, points)


# The toggled enemies' ranges, red where one could attack and purple where one could only
# support, and the range-tracked icon on their tokens.
func _draw_enemy_ranges() -> void:
	var covered: Dictionary[Vector2i, bool] = {}
	var supported: Dictionary[Vector2i, bool] = {}
	for enemy_id: String in _shown_enemies:
		for tile: Vector2i in TurnInputModel.enemy_range_tiles(_session, enemy_id):
			covered[tile] = true
		for tile: Vector2i in TurnInputModel.enemy_support_tiles(_session, enemy_id):
			supported[tile] = true
	for tile: Vector2i in covered:
		supported.erase(tile)
	var tiles: Array[Vector2i] = []
	tiles.assign(covered.keys())
	tiles.sort_custom(MapLayout.is_before)
	view.get_enemy_range_overlay().show_tiles(tiles)
	var support_tiles: Array[Vector2i] = []
	support_tiles.assign(supported.keys())
	support_tiles.sort_custom(MapLayout.is_before)
	view.get_enemy_support_overlay().show_tiles(support_tiles)
	view.show_range_tracked(_shown_enemies)


# The HP and Stance the forecast panel's action would change, flashed on the board while it is
# open in CONFIRM; nothing otherwise (questions 29 (3) and 34 (1)).
func _draw_forecast_preview() -> void:
	if not is_instance_valid(view):
		return
	var model: ForecastViewModel = null
	if _stage == Stage.CONFIRM and is_instance_valid(_forecast_panel):
		model = _forecast_panel.get_model()
	view.show_forecast_preview(model)


func _show_widgets(is_shown: bool) -> void:
	if turn_bar != null:
		turn_bar.visible = is_shown
	if swap_window != null:
		swap_window.visible = false
	if panel_host != null:
		panel_host.visible = is_shown
	if view != null and view.get_cursor() != null and not is_shown:
		view.get_cursor().visible = false


# The status line, End Turn's state, and the swap window with its hint.
func _refresh_widgets() -> void:
	if _session == null:
		return
	var state: CombatState = _session.state
	var is_swapping: bool = TurnInputModel.is_swapping(_session, _seat)
	if swap_window != null:
		swap_window.visible = is_swapping and not _session.is_finished
		if _stage == Stage.SWAP_PICKED:
			swap_window.show_hint("Pick the unit to trade tiles with.")
		else:
			swap_window.show_hint("Pick two of your units to trade tiles, then Start.")
	if turn_bar == null:
		return
	turn_bar.set_can_end_turn(
			(_stage == Stage.IDLE or _stage == Stage.MOVE)
			and not _is_waiting
			and TurnInputModel.end_turn_command(_session, _seat) != null
	)
	var status: String = "Turn %d · %s phase" % [
		state.turn,
		(CombatFact.CombatSide.find_key(state.phase_side) as String).to_lower(),
	]
	if is_swapping:
		status = "Opening swap"
	elif _session.is_finished:
		status = "Won" if _session.is_won else "Lost"
	turn_bar.show_status(status)


func _is_on_map(tile: Vector2i) -> bool:
	return _session.state.grid.step(tile, Vector2i.ZERO) != CombatFact.NO_TILE


func _on_action_menu_confirmed(result: Variant) -> void:
	var option: TurnInputModel.ActionOption = result
	if not option.has_targets():
		# ASSUMPTION: an action with no target (Wait, Swap) is sent when picked, as Godot_FE's
		# Wait is; the confirm stage is for targeted actions, where UI3's forecast goes.
		_send(option.command)
		return
	_action = option
	_targets = TargetList.build(option)
	var request: TargetPicker.Request = TargetPicker.Request.new()
	request.title = option.label
	request.targets = _targets.targets()
	var picker: BattlePanel = _open_panel(Stage.TARGET, target_picker_scene, request)
	if picker == null:
		_action = null
		_targets = null
		return
	_picker = picker as TargetPicker
	picker.confirmed.connect(_on_target_picker_confirmed)
	picker.highlighted.connect(_on_target_picker_highlighted)
	picker.cancelled.connect(_on_panel_cancelled)
	_redraw()
	_show_current_target()


func _on_target_picker_confirmed(result: Variant) -> void:
	var option: TurnInputModel.TargetOption = result
	if _targets != null:
		_pick_target(_targets.targets().find(option))


func _on_target_picker_highlighted(result: Variant) -> void:
	var option: TurnInputModel.TargetOption = result
	if _stage != Stage.TARGET or _targets == null:
		return
	if _targets.select(_targets.targets().find(option)):
		_show_current_target()
	else:
		move_cursor(option.tile)


func _on_confirm_dialog_confirmed(_result: Variant) -> void:
	var command: Command = get_confirm_command()
	if command != null:
		_send(command)


func _on_forecast_panel_weapon_cycle_requested() -> void:
	cycle_weapon()


func _on_end_turn_dialog_confirmed(_result: Variant) -> void:
	if _stage != Stage.END_CONFIRM:
		return
	var command: EndTurnCommand = TurnInputModel.end_turn_command(_session, _seat)
	if command != null:
		_send(command)


func _on_panel_cancelled() -> void:
	step_back()


# The detail's body grew or shrank past the panel: whether up and down scroll it may have changed.
func _on_detail_panel_scroll_range_changed() -> void:
	live_actions_changed.emit()


func _on_session_command_rejected(seat: int, _arrival: int, reason: String) -> void:
	if seat != _seat:
		return
	_rejection = reason
	if message != null:
		message.show_message("Can't do that: %s" % [reason])


# Playback this controller didn't start (a command from elsewhere) can change what the seat may do:
# with no flow under way the stage follows the session; a flow under way is left to its command,
# which the session checks when it is sent.
func _on_view_settled() -> void:
	if _is_waiting:
		_after_playback()
		return
	if _stage in [Stage.INACTIVE, Stage.SWAP, Stage.IDLE] and _base_stage() != _stage:
		_rebuild()
		return
	_refresh_widgets()
	_refresh_danger_zone()
	_show_intents()


# WALK's walk arrived: the action menu opens with MOVE, not WALK, as the stage Cancel returns to.
# A menu that fails to open leaves MOVE, the token snapped back.
func _on_view_staged_walk_finished(unit_id: String) -> void:
	if _stage != Stage.WALK or unit_id != _unit_id:
		return
	var options: Array[TurnInputModel.ActionOption] = _walk_options.duplicate()
	_walk_options.clear()
	var previous: Stage = _history.pop_back()
	_set_stage(previous)
	_open_action_menu(options)
	if _stage != Stage.ACTION:
		view.unstage_walk()
		_end_tile = CombatFact.NO_TILE
		_redraw()


# New intents reach the display only once the board has settled (see _show_intents()).
func _on_session_intents_changed(_intents: Intents) -> void:
	_show_intents()


func _on_turn_bar_end_turn_pressed() -> void:
	request_end_turn()


func _on_swap_window_start_pressed() -> void:
	request_start()


# A held d-pad direction or stick push stepped, or repeated: moves the cursor as an arrow key
# would, while input is taken.
func _on_pad_repeat_stepped(direction: Vector2i) -> void:
	if is_accepting_input():
		_step_cursor(direction)
