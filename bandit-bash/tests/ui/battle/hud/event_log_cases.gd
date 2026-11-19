# ==============================================================================
# Bandit Bash
# Copyright (c) 2026 Derc Development
# Licensed under the MIT License. See LICENSE.
#
# File:     event_log_cases.gd
# Author:
# Created:  November 18, 2026
# Modified: November 18, 2026
# ==============================================================================

extends RefCounted
## The event log's cases for the ui/display suite (ui-lift.md, Event log; P15 UL4): every
## [enum CombatFact.Kind] in exactly one of the writer's groups, headers or silent kinds (fails on
## a new kind with none); the writer's lines from built facts (a strike with crit and Block, a
## counter, a miss, a move from its tracked tile, a darkness phase's header and its one rising
## spread line, an activation unit first); the M1 battle played with attacks into its darkness
## phase: lines only as their facts play, names and never ids, a header per Phase Start and per
## darkness phase (on the darkness row), each line in a group, the turn bar's darkness chip while
## that phase plays; the filters; the cap, following, "↓ N new" and the collapsed header's count;
## the resume note; the panel hidden under a panel; EVENT_LOG by key and by the right stick, a
## slanted push scrolling and never focusing; the lines' and headers' contrast. No autoload is
## named or needed.

const BattleViewCases = preload("res://tests/ui/battle/board/battle_view_cases.gd")
const TurnInputCases = preload("res://tests/ui/battle/input/turn_input_cases.gd")
const ThemeCases = preload("res://tests/ui/theme/theme_cases.gd")

const M1_DEFINITION: String = "res://maps/standard/m1_greybox.tres"
const VIEW_SCENE: PackedScene = preload("res://ui/battle/board/battle_view.tscn")
const PANEL_HOST_SCENE: PackedScene = preload("res://ui/battle/menus/panel_host.tscn")
const TURN_BAR_SCENE: PackedScene = preload("res://ui/battle/hud/turn_bar.tscn")
const SWAP_WINDOW_SCENE: PackedScene = preload("res://ui/battle/menus/swap_window.tscn")
const MESSAGE_SCENE: PackedScene = preload("res://ui/battle/hud/battle_message.tscn")
const ACTION_MENU_SCENE: PackedScene = preload("res://ui/battle/menus/action_menu.tscn")
const TARGET_PICKER_SCENE: PackedScene = preload("res://ui/battle/input/target_picker.tscn")
const CONFIRM_SCENE: PackedScene = preload("res://ui/battle/menus/confirm_dialog.tscn")
const HUD_SCENE: PackedScene = preload("res://ui/battle/hud/battle_hud.tscn")
const LOG_SCENE: PackedScene = preload("res://ui/battle/hud/event_log/event_log.tscn")
const BATTLE_THEME: Theme = preload("res://ui/theme/battle_theme.tres")

# turn_input_cases.gd's seed: no case compares golden numbers.
const SEED: int = 0x0C0FFEE

# Phases the battle case plays at most: past the darkness's arrival (end of turn 4) on M1.
const MAX_PHASES: int = 7

# The screen size the layout cases lay out at: the project's base size.
const BASE_SCREEN_SIZE: Vector2i = Vector2i(1280, 720)

# How far up from the screen's foot the turn bar reaches as laid out (its 32-unit End Turn in a
# 12-padded panel, 8 above the edge), which the log must stay clear of.
const TURN_BAR_TOP: float = 72.0

# An instance id in text: the allocator's "<kind>:<number>", which a player never reads.
const ID_PATTERN: String = "\\b(unit|enemy|item|rune|effect|object|point|seat):\\d+"

const PLAYER: CombatFact.CombatSide = CombatFact.CombatSide.PLAYER
const ENEMY: CombatFact.CombatSide = CombatFact.CombatSide.ENEMY
const ATTACK: TurnInputModel.ActionKind = TurnInputModel.ActionKind.ATTACK

var _check: Callable
var _root: Node = null
var _catalog: EffectCatalog.Index = null
var _map: CombatMapDefinition = null


## [param check]: called as check(case_name: String, passed: bool, detail: String).
## [param root]: the root viewport, where the harness is added.
func _init(check: Callable, root: Node) -> void:
	_check = check
	_root = root
	_catalog = EffectCatalog.index()


## Runs every case.
func run() -> void:
	_test_kinds()
	_map = load(M1_DEFINITION) as CombatMapDefinition
	if _map == null:
		_check.call("event log: the M1 map definition loads", false, M1_DEFINITION)
		return
	_test_writer()
	_test_battle()
	_test_layout()
	_test_controller()
	_test_contrast()


# Every kind in exactly one list, so a kind added later fails here until it is given a line or a
# reason to stay silent.
func _test_kinds() -> void:
	var problems: PackedStringArray = []
	for kind: int in CombatFact.Kind.values():
		var homes: int = 0
		homes += 1 if EventLogWriter.GROUP_OF_KIND.has(kind) else 0
		homes += 1 if EventLogWriter.HEADER_KINDS.has(kind) else 0
		homes += 1 if EventLogWriter.SILENT_KINDS.has(kind) else 0
		if homes != 1:
			problems.append("%s in %d lists" % [CombatFact.Kind.find_key(kind), homes])
	_check.call("kinds: every CombatFact.Kind maps to a group, a header or the silent list", (
			problems.is_empty()
	), "; ".join(problems))
	var silent: PackedStringArray = []
	for kind: CombatFact.Kind in EventLogWriter.SILENT_KINDS:
		var kind_name: String = CombatFact.Kind.find_key(kind)
		silent.append(kind_name)
	_check.call("kinds: %d silent (%s)" % [silent.size(), ", ".join(silent)], silent.size() > 0)


# Built facts on the M1 battle's ids: one strike line at its outcome, a counter, a miss, a move
# from the tile it was tracked on, a darkness phase's header and its one spread line, rising.
func _test_writer() -> void:
	var h: TurnInputCases.Harness = _harness(false)
	if h == null:
		return
	var session: CombatSession = h.session
	var player: String = session.state.units_of(PLAYER)[0]
	var enemy: String = session.state.units_of(ENEMY)[0]
	var p_name: String = BattleText.name_of(session, player)
	var e_name: String = BattleText.name_of(session, enemy)
	var writer: EventLogWriter = EventLogWriter.new(session)
	var texts: PackedStringArray = []
	var strike: Array[CombatFact] = [
		_fact(CombatFact.Kind.BEFORE_COMBAT, player, enemy),
		_fact(CombatFact.Kind.BEFORE_COMBAT, enemy, player),
		_fact(CombatFact.Kind.ATTACK_MADE, player, enemy),
		_fact(CombatFact.Kind.HIT_DEALT, player, enemy),
		_fact(CombatFact.Kind.HIT_TAKEN, enemy, player, 7),
		_fact(CombatFact.Kind.CRIT_TAKEN, enemy, player, 7),
		_fact(CombatFact.Kind.DAMAGE_TAKEN, enemy, player, 7, 5, 2),
		_fact(CombatFact.Kind.ATTACK_MADE, enemy, player),
		_fact(CombatFact.Kind.MISSED, enemy, player),
		_fact(CombatFact.Kind.AFTER_COMBAT, player, enemy),
	]
	var written_at: Array[int] = []
	for fact: CombatFact in strike:
		var entries: Array[EventLogWriter.Entry] = writer.write(fact)
		for entry: EventLogWriter.Entry in entries:
			texts.append(entry.text())
			written_at.append(fact.kind)
	_check.call("writer: a strike is one line at its outcome; a counter and a miss name it", (
			texts == PackedStringArray([
				"%s attacks %s: 5 damage, crit (2 blocked)" % [p_name, e_name],
				"%s counters %s: miss" % [e_name, p_name],
			])
			and written_at == [CombatFact.Kind.DAMAGE_TAKEN, CombatFact.Kind.MISSED]
	), str(texts))

	var from: Vector2i = session.state.tile_of(player)
	var to: Vector2i = from + Vector2i.RIGHT
	var moved: CombatFact = _fact(CombatFact.Kind.UNIT_MOVED, player, "", 1)
	moved.tile = to
	var pushed: CombatFact = _fact(CombatFact.Kind.UNIT_MOVED, player)
	pushed.tile = from
	var move_texts: PackedStringArray = []
	for fact: CombatFact in [moved, pushed]:
		for entry: EventLogWriter.Entry in writer.write(fact):
			move_texts.append(entry.text())
	_check.call("writer: a move from its tracked tile, a forced move as 'is moved'", (
			move_texts == PackedStringArray([
				"%s moves (%d, %d) → (%d, %d)" % [p_name, from.x, from.y, to.x, to.y],
				"%s is moved (%d, %d) → (%d, %d)" % [p_name, to.x, to.y, from.x, from.y],
			])
	), str(move_texts))

	var end: CombatFact = _fact(CombatFact.Kind.PHASE_END)
	end.side = ENEMY
	var ids: Array[int] = []
	var dark_texts: PackedStringArray = []
	var tones: Array[int] = []
	var facts: Array[CombatFact] = [end]
	for i: int in 3:
		var deepened: CombatFact = _fact(CombatFact.Kind.DARKNESS_ADVANCED, "", "", 1)
		deepened.tile = Vector2i(i, 0)
		facts.append(deepened)
	for fact: CombatFact in facts:
		for entry: EventLogWriter.Entry in writer.write(fact):
			ids.append(entry.id)
			dark_texts.append(entry.text())
			tones.append(entry.tone)
	var turn: int = session.state.turn
	_check.call("writer: the darkness phase's header, then one spread line counting its tiles", (
			dark_texts.size() == 4
			and dark_texts[0] == "Turn %d · Darkness phase" % [turn]
			and tones[0] == EventLogWriter.Tone.DARKNESS_HEADER
			and ids[1] == ids[2] and ids[2] == ids[3]
			and dark_texts[3] == "The darkness spreads: 3 tiles deepen"
	), str(dark_texts))

	var waited: Array[EventLogWriter.Entry] = writer.write(
			_fact(CombatFact.Kind.UNIT_WAITED, player)
	)
	var resumed: EventLogWriter.Entry = writer.resumed_entry()
	_check.call("writer: a wait in Events; the resume note muted with no group", (
			waited.size() == 1
			and waited[0].text() == "%s waits" % [p_name]
			and waited[0].group == EventLogWriter.Group.EVENTS
			and resumed.text() == EventLogWriter.RESUMED_TEXT
			and resumed.tone == EventLogWriter.Tone.NOTE
			and resumed.group == EventLogWriter.Group.NONE
	), "%s; %s" % [waited.size(), resumed.text()])
	h.close()


# From Start, attacks where offered and waits elsewhere, End Turn, into the darkness phase.
func _test_battle() -> void:
	var rig: Rig = _rig()
	if rig == null:
		return
	var h: TurnInputCases.Harness = rig.h
	var log: EventLog = rig.hud.get_event_log()
	var lines_before: int = log.get_texts().size()
	h.controller.request_start()
	BattleViewCases.settle(h.view)
	var ahead: PackedStringArray = []
	var attacks: int = 0
	for _phase: int in MAX_PHASES:
		if h.session.is_finished:
			break
		for unit_id: String in TurnInputModel.acting_units(h.session, 0):
			var command: Command = _attack_or_wait(h.session, unit_id)
			attacks += 1 if command is UnitTurnCommand and _is_attack(command) else 0
			var before: int = log.get_texts().size()
			h.battle.submit(command, h.session.session_id)
			h.battle.resolve_queued()
			if log.get_texts().size() != before:
				ahead.append("%s wrote before playing" % [unit_id])
			BattleViewCases.settle(h.view)
			if h.session.is_finished:
				break
		if h.session.is_finished:
			break
		h.battle.submit(EndTurnCommand.new(0), h.session.session_id)
		h.battle.resolve_queued()
		BattleViewCases.settle(h.view)
	var texts: PackedStringArray = log.get_texts()
	_check.call("battle: nothing is written until its facts play", (
			texts.size() > lines_before and ahead.is_empty()
	), "; ".join(ahead))

	var id_hits: PackedStringArray = []
	var pattern: RegEx = RegEx.create_from_string(ID_PATTERN)
	for text: String in texts:
		if pattern.search(text) != null:
			id_hits.append(text)
	_check.call("battle: every line names things, never by id (%d lines)" % [texts.size()], (
			id_hits.is_empty()
	), "; ".join(id_hits.slice(0, 3)))

	var headers: PackedStringArray = []
	var darkness_headers: PackedStringArray = []
	var groups: Dictionary[int, int] = {}
	var ungrouped: PackedStringArray = []
	for node: Control in log.get_entry_nodes():
		var header: EventLogHeader = node as EventLogHeader
		if header != null:
			if header.is_darkness():
				darkness_headers.append(header.get_text())
			elif header.get_text().begins_with("Turn "):
				headers.append(header.get_text())
			continue
		var line: EventLogLine = node as EventLogLine
		groups[line.get_group()] = groups.get(line.get_group(), 0) + 1
		if line.get_group() == EventLogWriter.Group.NONE:
			ungrouped.append(line.get_text())
	_check.call("battle: a header per Phase Start played, in order", (
			not rig.phase_headers.is_empty() and headers == rig.phase_headers
	), "%s vs %s" % [headers, rig.phase_headers])
	var expected_dark: PackedStringArray = []
	for turn: int in rig.darkness_turns:
		expected_dark.append("Turn %d · Darkness phase" % [turn])
	_check.call("battle: a darkness-row header per darkness phase played, with its turn", (
			not rig.darkness_turns.is_empty() and darkness_headers == expected_dark
	), "%s vs %s" % [darkness_headers, expected_dark])
	_check.call("battle: every line has a group; Combat, Movement, Events and Effects all wrote", (
			ungrouped.is_empty()
			and groups.has(EventLogWriter.Group.COMBAT)
			and groups.has(EventLogWriter.Group.MOVEMENT)
			and groups.has(EventLogWriter.Group.EVENTS)
			and groups.has(EventLogWriter.Group.EFFECTS)
			and attacks > 0
	), "groups %s, attacks %d; %s" % [groups, attacks, ungrouped])
	_check.call("turn bar: the darkness chip shows while a darkness phase plays, then goes", (
			not rig.darkness_turns.is_empty()
			and rig.chip_missing == 0
			and not h.bar.is_darkness_shown()
	), "missing %d, shown after %s" % [rig.chip_missing, h.bar.is_darkness_shown()])

	var filters: EventLogFilterRow = log.get_filter_row()
	filters.set_group_shown(EventLogWriter.Group.COMBAT, false)
	var shown: PackedStringArray = log.get_shown_texts()
	var hidden_combat: bool = true
	var headers_kept: bool = false
	for node: Control in log.get_entry_nodes():
		var line: EventLogLine = node as EventLogLine
		if line != null and line.get_group() == EventLogWriter.Group.COMBAT and line.visible:
			hidden_combat = false
		if node is EventLogHeader and node.visible:
			headers_kept = true
	filters.set_group_shown(EventLogWriter.Group.COMBAT, true)
	var all_back: bool = log.get_shown_texts().size() == texts.size()
	rig.hud.bind(h.session, h.controller, h.view)
	_check.call("filters: off hides its group's lines, never headers; a new bind resets them", (
			hidden_combat
			and headers_kept
			and shown.size() < texts.size()
			and all_back
			and filters.get_shown_mask() == _all_groups_mask()
			and log.get_texts().is_empty()
	), "hidden %s, headers %s, %d of %d shown" % [
		hidden_combat, headers_kept, shown.size(), texts.size(),
	])
	log.add_resumed_line()
	var first: Control = log.get_entry_nodes()[0] if not log.get_texts().is_empty() else null
	_check.call("resume: the note 'Battle resumed' starts the log, as a line with no icon", (
			log.get_texts() == PackedStringArray([EventLogWriter.RESUMED_TEXT])
			and first is EventLogLine
			and (first as EventLogLine).get_group() == EventLogWriter.Group.NONE
	), str(log.get_texts()))
	rig.close()


# A log on its own at the base size: the cap, following, scrolling up and "↓ N new", the collapsed
# header's count, and hidden under a panel; in the HUD, clear of the map's area.
func _test_layout() -> void:
	var window: Window = _root.get_window()
	var old_size: Vector2i = window.size
	window.size = BASE_SCREEN_SIZE
	var layer: CanvasLayer = CanvasLayer.new()
	_root.add_child(layer)
	var holder: Control = Control.new()
	holder.theme = BATTLE_THEME
	holder.set_anchors_preset(Control.PRESET_FULL_RECT)
	layer.add_child(holder)
	var log: EventLog = LOG_SCENE.instantiate()
	holder.add_child(log)
	for i: int in 250:
		log.add_entry(_note(i))
	var texts: PackedStringArray = log.get_texts()
	_check.call("cap: the newest max_lines kept, oldest dropped", (
			texts.size() == log.max_lines and texts[0] == "Line 50" and texts[-1] == "Line 249"
	), "%d kept, first '%s'" % [texts.size(), texts[0] if not texts.is_empty() else ""])
	_lay_out(log)
	var rect: Rect2 = log.get_global_rect()
	_check.call("layout: the right column's foot, 8 units above the turn bar, 300 wide", (
			is_equal_approx(rect.size.x, 300.0)
			and is_equal_approx(rect.end.y, BASE_SCREEN_SIZE.y - TURN_BAR_TOP - 8.0)
			and is_equal_approx(rect.end.x, BASE_SCREEN_SIZE.x - 8.0)
	), str(rect))
	var can: bool = log.can_scroll()
	log.scroll_to_end()
	_lay_out(log)
	var was_following: bool = log.is_following()
	log.scroll_lines(-5)
	var up_follows: bool = log.is_following()
	log.add_entry(_note(1000))
	_lay_out(log)
	var jump: Button = log.get_node(^"%JumpButton")
	var jump_text: String = jump.text if jump.visible else "(hidden)"
	log.scroll_to_end()
	_lay_out(log)
	_check.call("follow: following at the bottom, stopped when scrolled up, '↓ N new' returns", (
			can
			and was_following
			and not up_follows
			and jump_text == log.jump_format % [1]
			and log.is_following()
			and not jump.visible
	), "can %s, following %s, up %s, jump '%s'" % [can, was_following, up_follows, jump_text])
	log.set_open(false)
	log.add_entry(_note(1001))
	log.add_entry(_note(1002))
	var collapsed_text: String = log.get_toggle().text
	var frame: Control = log.get_node(^"%Frame")
	_lay_out(log)
	var collapsed_height: float = frame.size.y
	log.set_open(true)
	_check.call("collapse: a 40-unit header counting lines added unseen", (
			collapsed_text == log.separator.join(PackedStringArray([
				log.title_text, log.new_format % [2], log.show_text,
			]))
			and is_equal_approx(collapsed_height, 40.0)
	), "'%s', %.1f tall" % [collapsed_text, collapsed_height])
	log.set_covered(true)
	var covered: bool = not log.is_shown() and not log.can_scroll() and not frame.visible
	log.set_covered(false)
	_check.call("covered: hidden under a panel, then back", (
			covered and log.is_shown() and frame.visible
	))
	layer.free()

	var rig: Rig = _rig()
	if rig != null:
		var camera: Camera2D = _root.get_viewport().get_camera_2d()
		if camera != null:
			camera.force_update_scroll()
		var map: Rect2 = rig.h.view.get_global_transform_with_canvas() * rig.h.view.map_rect()
		var log_rect: Rect2 = rig.hud.get_event_log().get_global_rect()
		_check.call("layout: at 1280×720 the event log covers none of the M1 map", (
				map.has_area() and log_rect.has_area() and not log_rect.intersects(map)
		), "log %s, map %s" % [log_rect, map])
		rig.close()
	window.size = old_size


# EVENT_LOG by key: focus on the header, out by cancel; hidden under End Turn's question; the
# right stick: a slanted push scrolls and never focuses, a sideways one focuses once per push.
func _test_controller() -> void:
	var rig: Rig = _rig()
	if rig == null:
		return
	var h: TurnInputCases.Harness = rig.h
	var log: EventLog = rig.hud.get_event_log()
	h.controller.request_start()
	BattleViewCases.settle(h.view)
	var stage: BattleController.Stage = h.controller.get_stage()
	var opened: bool = h.controller.request_event_log()
	var focus: Control = _root.get_viewport().gui_get_focus_owner()
	var in_log: bool = (
			h.controller.get_stage() == BattleController.Stage.EVENT_LOG
			and focus == log.get_toggle()
			and log.is_navigable()
	)
	var closed: bool = h.controller.step_back()
	_check.call("EVENT_LOG: event_log_focus focuses the header; cancel returns, focus let go", (
			stage == BattleController.Stage.IDLE
			and opened
			and in_log
			and closed
			and h.controller.get_stage() == BattleController.Stage.IDLE
			and not log.is_navigable()
			and _root.get_viewport().gui_get_focus_owner() == null
	), "stage %d, opened %s, in log %s, focus %s" % [stage, opened, in_log, focus])

	h.controller.request_end_turn()
	var covered: bool = log.is_covered()
	h.controller.step_back()
	_check.call("covered: End Turn's question hides the log; closing it shows it again", (
			covered and not log.is_covered()
	), "covered %s" % [covered])

	_push_axis(JOY_AXIS_RIGHT_Y, 0.8)
	_push_axis(JOY_AXIS_RIGHT_X, 0.6)
	var slanted: BattleController.Stage = h.controller.get_stage()
	_push_axis(JOY_AXIS_RIGHT_X, 0.0)
	_push_axis(JOY_AXIS_RIGHT_Y, 0.0)
	_push_axis(JOY_AXIS_RIGHT_X, 0.9)
	_push_axis(JOY_AXIS_RIGHT_X, 1.0)
	var sideways: BattleController.Stage = h.controller.get_stage()
	_push_axis(JOY_AXIS_RIGHT_X, 0.0)
	_push_axis(JOY_AXIS_RIGHT_X, -1.0)
	var again: BattleController.Stage = h.controller.get_stage()
	_push_axis(JOY_AXIS_RIGHT_X, 0.0)
	_check.call("stick: a slanted push never focuses; sideways focuses, the next push closes", (
			slanted == BattleController.Stage.IDLE
			and sideways == BattleController.Stage.EVENT_LOG
			and again == BattleController.Stage.IDLE
	), "slanted %d, sideways %d, again %d" % [slanted, sideways, again])
	rig.close()


# Lines in text with muted pieces in text_muted, both 4.5:1 or more on the log's panel; a header
# in accent on panel; the darkness header text on its darkness fill.
func _test_contrast() -> void:
	var layer: CanvasLayer = CanvasLayer.new()
	_root.add_child(layer)
	var holder: Control = Control.new()
	holder.theme = BATTLE_THEME
	layer.add_child(holder)
	var log: EventLog = LOG_SCENE.instantiate()
	holder.add_child(log)
	var line: EventLogLine = log.line_scene.instantiate()
	var header: EventLogHeader = log.header_scene.instantiate()
	var dark: EventLogHeader = log.header_scene.instantiate()
	for node: Control in [line, header, dark]:
		holder.add_child(node)
	var entry: EventLogWriter.Entry = _note(0)
	entry.add(" (3, 4)", true)
	line.show_entry(entry)
	var header_entry: EventLogWriter.Entry = _note(1)
	header_entry.tone = EventLogWriter.Tone.HEADER
	header.show_entry(header_entry)
	var dark_entry: EventLogWriter.Entry = _note(2)
	dark_entry.tone = EventLogWriter.Tone.DARKNESS_HEADER
	dark.show_entry(dark_entry)
	var frame_box: StyleBoxFlat = (
			log.get_node(^"%Frame") as Control
	).get_theme_stylebox(&"panel") as StyleBoxFlat
	var panel: Color = frame_box.bg_color if frame_box != null else Color.BLACK
	var text: Color = (line.get_node(^"%Text") as RichTextLabel).get_theme_color(&"default_color")
	var muted: Color = UiTokens.color(UiTokens.TEXT_MUTED)
	var header_colour: Color = (header.get_node(^"%Text") as Label).get_theme_color(&"font_color")
	var dark_box: StyleBoxFlat = dark.get_theme_stylebox(&"panel") as StyleBoxFlat
	var dark_fill: Color = dark_box.bg_color if dark_box != null else Color.BLACK
	var dark_text: Color = (dark.get_node(^"%Text") as Label).get_theme_color(&"font_color")
	var ratios: PackedFloat32Array = [
		ThemeCases.contrast(text, panel), ThemeCases.contrast(muted, panel),
		ThemeCases.contrast(header_colour, panel), ThemeCases.contrast(dark_text, dark_fill),
	]
	var markup: String = (line.get_node(^"%Text") as RichTextLabel).text
	var ok: bool = true
	for ratio: float in ratios:
		ok = ok and ratio >= ThemeCases.MIN_CONTRAST
	_check.call("contrast: line %.2f, muted %.2f, header %.2f, darkness header %.2f (4.5+)" % [
		ratios[0], ratios[1], ratios[2], ratios[3],
	], (
			ok
			and panel == UiTokens.color(UiTokens.PANEL)
			and text == UiTokens.color(UiTokens.TEXT)
			and dark_fill == UiTokens.color(UiTokens.DARKNESS)
			and markup.contains(muted.to_html(false))
			and dark.is_darkness()
	), markup)
	layer.free()


# --- Fixtures --------------------------------------------------------------------------------


# The turn-input harness on the M1 battle, with the controller's widgets; started when asked.
func _harness(is_started: bool) -> TurnInputCases.Harness:
	var h: TurnInputCases.Harness = TurnInputCases.Harness.new()
	h.run = CampaignSession.new(CampaignData.Mode.SOLO, SEED, PackedInt32Array([0]))
	h.battle = BattleViewCases.begin_m1(_catalog, _map, h.run)
	if h.battle == null:
		_check.call("event log: the M1 battle begins", false, "begin_battle gave no battle")
		h.run.close()
		return null
	h.session = h.battle.get_session(0)
	h.view = VIEW_SCENE.instantiate()
	_root.add_child(h.view)
	h.hud = CanvasLayer.new()
	_root.add_child(h.hud)
	h.bar = TURN_BAR_SCENE.instantiate()
	h.swap = SWAP_WINDOW_SCENE.instantiate()
	h.host = PANEL_HOST_SCENE.instantiate()
	h.message = MESSAGE_SCENE.instantiate()
	for widget: Control in [h.bar, h.swap, h.host, h.message]:
		h.hud.add_child(widget)
	h.controller = BattleController.new()
	h.controller.action_menu_scene = ACTION_MENU_SCENE
	h.controller.target_picker_scene = TARGET_PICKER_SCENE
	h.controller.confirm_dialog_scene = CONFIRM_SCENE
	h.controller.view = h.view
	h.controller.panel_host = h.host
	h.controller.turn_bar = h.bar
	h.controller.swap_window = h.swap
	h.controller.message = h.message
	if is_started:
		_root.add_child(h.controller)
	return h


# The harness with the HUD on its layer and the controller taking the HUD's event log, bound as
# the gameplay screen binds them.
func _rig() -> Rig:
	var h: TurnInputCases.Harness = _harness(false)
	if h == null:
		return null
	var rig: Rig = Rig.new()
	rig.h = h
	rig.hud = HUD_SCENE.instantiate()
	h.hud.add_child(rig.hud)
	h.hud.move_child(rig.hud, 0)
	h.controller.event_log = rig.hud.get_event_log()
	_root.add_child(h.controller)
	h.view.map_area = rig.hud.get_map_area()
	h.view.bind(h.session)
	h.controller.bind(h.battle, h.session, 0)
	rig.hud.bind(h.session, h.controller, h.view)
	h.session.batch_resolved.connect(h.record)
	h.session.bus.flow.phase_started.connect(rig.count_phase)
	h.view.darkness_phase_started.connect(rig.count_darkness)
	return rig


# The first attack unit_id can make this turn, else its wait.
func _attack_or_wait(session: CombatSession, unit_id: String) -> Command:
	for tile: Vector2i in TurnInputModel.move_tiles(session, unit_id):
		var path: Array[Vector2i] = TurnInputModel.path_to(session, unit_id, tile)
		for option: TurnInputModel.ActionOption in TurnInputModel.actions_at(
				session, unit_id, path
		):
			if option.kind == ATTACK and not option.targets.is_empty():
				return option.targets[0].command
	return UnitTurnCommand.new(0, unit_id, UnitTurnCommand.Action.WAIT)


func _is_attack(command: Command) -> bool:
	var turn: UnitTurnCommand = command as UnitTurnCommand
	return turn != null and turn.action == UnitTurnCommand.Action.ATTACK


# Pushes a right-stick axis motion into the viewport, as a pad would.
func _push_axis(axis: JoyAxis, value: float) -> void:
	var motion: InputEventJoypadMotion = InputEventJoypadMotion.new()
	motion.axis = axis
	motion.axis_value = value
	_root.get_viewport().push_input(motion, true)


# Sorts the log's containers twice, parents first, as a frame's deferred sort would.
func _lay_out(log: EventLog) -> void:
	for _pass: int in 2:
		log.notification(Container.NOTIFICATION_SORT_CHILDREN)
		for node: Node in log.find_children("*", "Container", true, false):
			node.notification(Container.NOTIFICATION_SORT_CHILDREN)


static func _fact(
		kind: CombatFact.Kind,
		actor: String = "",
		target: String = "",
		amount: int = 0,
		hp: int = 0,
		block: int = 0
) -> CombatFact:
	var fact: CombatFact = CombatFact.new(kind, actor, target)
	fact.amount = amount
	fact.hp_amount = hp
	fact.block_amount = block
	if kind == CombatFact.Kind.DAMAGE_TAKEN:
		fact.source = CombatFact.Source.ATTACK
	return fact


# A plain grouped line "Line <n>", with an id clear of any writer's.
static func _note(n: int) -> EventLogWriter.Entry:
	var entry: EventLogWriter.Entry = EventLogWriter.Entry.new()
	entry.id = 1000000 + n
	entry.group = EventLogWriter.Group.EVENTS
	entry.add("Line %d" % [n])
	return entry


static func _all_groups_mask() -> int:
	var mask: int = 0
	for group: EventLogWriter.Group in EventLogWriter.GROUPS:
		mask |= 1 << group
	return mask


## The harness with the HUD, and the phases played since bind.
class Rig:
	extends RefCounted

	## The board, widgets and controller (turn_input_cases.gd).
	var h: TurnInputCases.Harness = null
	## The HUD.
	var hud: BattleHud = null
	## The header each Phase Start played should write, in order.
	var phase_headers: PackedStringArray = []
	## The turn of each darkness phase announced ([signal BattleView.darkness_phase_started]).
	var darkness_turns: Array[int] = []
	## Darkness phases whose turn bar showed no chip as they began.
	var chip_missing: int = 0

	## Keeps the header [param fact], a Phase Start played, should write.
	func count_phase(fact: CombatFact) -> void:
		var side: String = EventLogWriter.PHASE_NAMES.get(fact.side, "?")
		phase_headers.append(EventLogWriter.PHASE_HEADER_FORMAT % [fact.amount, side])

	## Keeps turn [param turn]'s darkness phase; the turn bar's chip must show.
	func count_darkness(turn: int) -> void:
		darkness_turns.append(turn)
		if not h.bar.is_darkness_shown():
			chip_missing += 1

	## Frees the nodes and closes the run.
	func close() -> void:
		if h.session.bus.flow.phase_started.is_connected(count_phase):
			h.session.bus.flow.phase_started.disconnect(count_phase)
		if h.view.darkness_phase_started.is_connected(count_darkness):
			h.view.darkness_phase_started.disconnect(count_darkness)
		h.close()
