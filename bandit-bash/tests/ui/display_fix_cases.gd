# ==============================================================================
# Bandit Bash
# Copyright (c) 2026 Derc Development
# Licensed under the MIT License. See LICENSE.
#
# File:     display_fix_cases.gd
# Author:
# Created:  November 7, 2026
# Modified: November 7, 2026
# ==============================================================================

extends RefCounted
## UI9's display fixes for tests/ui/display/run_all.gd (combat UI plan, UI9 row; questions 28 (e),
## 28 (f) and 30): pop-ups on the unit info layer, above every info panel and kept on their unit
## as the camera pans; a hit's number past Block, overkill included, with a small Block number
## beside it, for a plain hit and a crit alike, and only the Block number for a hit Block took
## whole; the HP bar's "14/22" by default and "14" with its option off; spent units gray only in
## their side's phase; and the range-tracked tint white by default. No autoload is named or needed.
##
## [b]Hits[/b] are played as the facts [code]ExchangeResolver.attack[/code] and
## [code]DamagePipeline.apply[/code] record them, with the fixture's numbers worked through the
## pipeline's own sums (Block takes first, then HP up to what it has).

const BattleViewCases = preload("res://tests/ui/battle_view_cases.gd")

const M1_DEFINITION: String = "res://maps/standard/m1_greybox.tres"
const VIEW_SCENE: PackedScene = preload("res://scenes/ui/battle/battle_view.tscn")
const HP_BAR_SCENE: PackedScene = preload("res://scenes/ui/battle/hp_bar.tscn")
const TOKEN_SCENE: PackedScene = preload("res://scenes/ui/battle/unit_token.tscn")

# Any fixed seed; the other UI cases use the same one.
const SEED: int = 0x0C0FFEE

# One frame at 30 fps, as BattleViewCases steps boards.
const FRAME: float = 1.0 / 30.0

# Frames stepped after a pan: past CameraRig.pan_time, short of DamageNumber.lifetime.
const PAN_FRAMES: int = 10

# How far a pop-up may sit from where the camera draws its board point: rounding only.
const PLACE_TOLERANCE: float = 0.5

# The fixture hit into Block: the hit's damage, the defender's Block and HP before it.
const HIT_DAMAGE: int = 12
const HIT_BLOCK: int = 4
const HIT_HP: int = 5

const PLAYER: CombatFact.CombatSide = CombatFact.CombatSide.PLAYER
const ENEMY: CombatFact.CombatSide = CombatFact.CombatSide.ENEMY
const DAMAGE: DamageNumber.Style = DamageNumber.Style.DAMAGE
const CRITICAL: DamageNumber.Style = DamageNumber.Style.CRITICAL
const BLOCK: DamageNumber.Style = DamageNumber.Style.BLOCK

var _check: Callable
var _root: Node = null
var _catalog: EffectCatalog.Index = null
var _map: CombatMapDefinition = null


## [param check]: called as check(case_name: String, passed: bool, detail: String).
## [param root]: where boards are added, so their nodes are in the tree.
func _init(check: Callable, root: Node) -> void:
	_check = check
	_root = root
	_catalog = EffectCatalog.index()


## Runs every case.
func run() -> void:
	_map = load(M1_DEFINITION) as CombatMapDefinition
	if _map == null:
		_check.call("display: the M1 map definition loads", false, M1_DEFINITION)
		return
	_test_hp_text()
	_test_tracked_tint()
	_test_popups_on_info_layer()
	_test_hit_into_block()
	_test_phase_gray()


# The HP bar's number: "14/22" by default, "14" with is_maximum_shown off, and back.
func _test_hp_text() -> void:
	var bar: HpBar = HP_BAR_SCENE.instantiate()
	_root.add_child(bar)
	bar.show_hp(14, 22)
	var shown: String = bar.get_text()
	bar.is_maximum_shown = false
	var current_only: String = bar.get_text()
	bar.is_maximum_shown = true
	var again: String = bar.get_text()
	bar.free()
	_check.call("hp: the bar shows 14/22 by default and 14 with is_maximum_shown off", (
			shown == "14/22" and current_only == "14" and again == "14/22"
	), "'%s', '%s', '%s'" % [shown, current_only, again])


# A tracked unit's sprite keeps its colours: the tint defaults to white, the icon shows it.
func _test_tracked_tint() -> void:
	var token: UnitToken = TOKEN_SCENE.instantiate()
	var tint: Color = token.range_tracked_tint
	token.free()
	_check.call("tint: range_tracked_tint defaults to white", tint == Color.WHITE, str(tint))


# A damage pop-up is a child of the unit info layer, drawn above its infos, on its unit's screen
# point; when the camera pans it stays on that point.
func _test_popups_on_info_layer() -> void:
	var board: BattleViewCases.Board = _board("pop-ups on the info layer: the M1 battle begins")
	if board == null:
		return
	var view: BattleView = board.view
	var layer: UnitInfoLayer = view.get_info_layer()
	var defender: String = board.session.state.units_of(ENEMY)[0]
	var token: UnitToken = view.token_of(defender)
	var info: UnitInfo = layer.info_of(defender)
	var hit: CombatFact = _taken(defender, 3, 3, 0)
	board.session.playback.enqueue([hit])
	view.advance(0.0)
	var number: DamageNumber = _last_popup(view)
	var problems: PackedStringArray = []
	if number == null:
		problems.append("no pop-up")
	else:
		if number.get_parent() != layer:
			problems.append("parent %s" % [number.get_parent()])
		if number.z_index <= info.z_index:
			problems.append("z %d over info z %d" % [number.z_index, info.z_index])
		problems.append_array(_place_problems(view, number, token.global_position, "placed"))
		view.focus_tile(view.tile_at(view.map_rect().end - Vector2.ONE))
		for _i: int in PAN_FRAMES:
			view.advance(FRAME)
		if is_instance_valid(number) and not number.is_queued_for_deletion():
			problems.append_array(_place_problems(view, number, token.global_position, "panned"))
		else:
			problems.append("freed before the pan ended")
	_check.call("pop-ups: on the info layer, above the infos, and on their unit through a pan", (
			problems.is_empty()
	), "; ".join(problems))
	BattleViewCases.settle(view)
	board.close()


# The fixture hit into Block (12 damage, 4 Block, 5 HP): Block takes 4, HP the 5 it has. The
# number is the 8 past Block (overkill included, though only 5 HP were left) and a blue 4 beside
# it; a crit shows "Critical 8" and the same 4; a hit Block takes whole shows only its Block.
func _test_hit_into_block() -> void:
	var board: BattleViewCases.Board = _board("hit into Block: the M1 battle begins")
	if board == null:
		return
	var view: BattleView = board.view
	var attacker: String = board.session.state.units_of(PLAYER)[0]
	var defender: String = board.session.state.units_of(ENEMY)[0]
	var shown: Array[String] = []
	var on_shown: Callable = func(unit_id: String, style: DamageNumber.Style) -> void:
		var number: DamageNumber = _last_popup(view)
		shown.append("%s %s '%s'" % [
			"defender" if unit_id == defender else unit_id,
			DamageNumber.Style.find_key(style),
			number.get_text() if number != null else "?",
		])
	view.number_shown.connect(on_shown)
	var absorbed: int = mini(HIT_BLOCK, HIT_DAMAGE)
	var to_hp: int = mini(HIT_HP, HIT_DAMAGE - absorbed)
	var past_block: int = HIT_DAMAGE - absorbed

	_play(board, _strike(attacker, defender, HIT_DAMAGE, to_hp, absorbed, false))
	var plain: Array[String] = shown.duplicate()
	shown.clear()
	var block_number: DamageNumber = _last_popup(view)
	var block_color: bool = (
			block_number != null
			and block_number.style == BLOCK
			and block_number.get_text() == str(absorbed)
	)
	_play(board, _strike(attacker, defender, HIT_DAMAGE, to_hp, absorbed, true))
	var crit: Array[String] = shown.duplicate()
	shown.clear()
	_play(board, _strike(attacker, defender, 3, 0, 3, false))
	var whole: Array[String] = shown.duplicate()
	view.number_shown.disconnect(on_shown)

	var expected_plain: Array[String] = [
		"defender DAMAGE '%d'" % [past_block], "defender BLOCK '%d'" % [absorbed],
	]
	_check.call("hit into Block: the number past Block, overkill included, and a Block number", (
			plain == expected_plain and past_block > HIT_HP and block_color
	), "%s, expected %s" % [plain, expected_plain])
	var expected_crit: Array[String] = [
		"defender CRITICAL 'Critical %d'" % [past_block], "defender BLOCK '%d'" % [absorbed],
	]
	_check.call("hit into Block: a crit follows the same rule, as Critical", (
			crit == expected_crit
	), "%s, expected %s" % [crit, expected_crit])
	_check.call("hit into Block: a hit Block takes whole shows only its Block number", (
			whole == ["defender BLOCK '3'"]
	), str(whole))
	var number: DamageNumber = DamageNumber.new()
	var colour_ok: bool = number.color_of(BLOCK).b > number.color_of(BLOCK).r
	number.free()
	_check.call("hit into Block: the Block number is blue", colour_ok)
	board.close()


# Gray only for the side whose phase it is: a player unit that waited is gray in the player phase
# and in colour once the enemy phase starts, where a spent enemy is gray; back in the player phase
# the enemy shows in colour again. Then a real End Turn: the board's phase agrees with the state.
func _test_phase_gray() -> void:
	var board: BattleViewCases.Board = _board("phase gray: the M1 battle begins")
	if board == null:
		return
	var view: BattleView = board.view
	var session: CombatSession = board.session
	var unit_id: String = TurnInputModel.acting_units(session, 0)[0]
	board.battle.submit(
			UnitTurnCommand.new(0, unit_id, UnitTurnCommand.Action.WAIT), session.session_id
	)
	board.battle.resolve_queued()
	BattleViewCases.settle(view)
	var player: UnitToken = view.token_of(unit_id)
	var enemy: UnitToken = view.token_of(session.state.units_of(ENEMY)[0])
	enemy.show_turn(true, false)
	var gray: float = player.spent_gray
	var seen: PackedStringArray = []
	seen.append("player phase: player %.1f enemy %.1f" % [player.get_gray(), enemy.get_gray()])
	_play(board, [_phase(ENEMY)])
	seen.append("enemy phase: player %.1f enemy %.1f" % [player.get_gray(), enemy.get_gray()])
	_play(board, [_phase(PLAYER)])
	seen.append("player phase: player %.1f enemy %.1f" % [player.get_gray(), enemy.get_gray()])
	var expected: PackedStringArray = [
		"player phase: player %.1f enemy 0.0" % [gray],
		"enemy phase: player 0.0 enemy %.1f" % [gray],
		"player phase: player %.1f enemy 0.0" % [gray],
	]
	_check.call("phase gray: spent units gray only in their side's phase", (
			seen == expected and player.has_acted and enemy.has_acted
	), "%s, expected %s" % [seen, expected])
	enemy.show_turn(false, false)
	board.battle.submit(EndTurnCommand.new(0), session.session_id)
	board.battle.resolve_queued()
	BattleViewCases.settle(view)
	_check.call("phase gray: after a real End Turn the board's phase agrees with the state", (
			view.mismatches().is_empty()
	), "; ".join(view.mismatches()))
	board.close()


# --- Fixtures --------------------------------------------------------------------------------


# The M1 battle on a board, past Start.
func _board(case_name: String) -> BattleViewCases.Board:
	var run: CampaignSession = CampaignSession.new(
			CampaignData.Mode.SOLO, SEED, PackedInt32Array([0])
	)
	var battle: CombatEncounter = BattleViewCases.begin_m1(_catalog, _map, run)
	if battle == null:
		_check.call(case_name, false, "begin_battle gave no battle")
		run.close()
		return null
	var board: BattleViewCases.Board = BattleViewCases.Board.new()
	board.run = run
	board.battle = battle
	board.session = battle.get_session(0)
	board.view = VIEW_SCENE.instantiate()
	_root.add_child(board.view)
	board.view.bind(board.session)
	if board.session.state.map.opening_swap_open:
		board.battle.submit(StartCommand.new(0), board.session.session_id)
		board.battle.resolve_queued()
		BattleViewCases.settle(board.view)
	return board


func _play(board: BattleViewCases.Board, facts: Array[CombatFact]) -> void:
	board.session.playback.enqueue(facts)
	BattleViewCases.settle(board.view)


# One strike's facts as ExchangeResolver.attack and DamagePipeline.apply record them: damage is
# the hit's, to_hp and absorbed what reached HP and Block.
static func _strike(
		a: String, d: String, damage: int, to_hp: int, absorbed: int, is_crit: bool
) -> Array[CombatFact]:
	var facts: Array[CombatFact] = [CombatFact.new(CombatFact.Kind.ATTACK_MADE, a, d)]
	var hit_kinds: Array[CombatFact.Kind] = [CombatFact.Kind.HIT_DEALT, CombatFact.Kind.HIT_TAKEN]
	if is_crit:
		hit_kinds.append_array([CombatFact.Kind.CRIT_DEALT, CombatFact.Kind.CRIT_TAKEN])
	for kind: CombatFact.Kind in hit_kinds:
		var is_dealt: bool = kind in [CombatFact.Kind.HIT_DEALT, CombatFact.Kind.CRIT_DEALT]
		var fact: CombatFact = CombatFact.new(kind, a if is_dealt else d, d if is_dealt else a)
		fact.amount = damage
		facts.append(fact)
	var dealt: CombatFact = CombatFact.new(CombatFact.Kind.DAMAGE_DEALT, a, d)
	dealt.amount = absorbed + to_hp
	dealt.hp_amount = to_hp
	dealt.block_amount = absorbed
	facts.append(dealt)
	var taken: CombatFact = _taken(d, absorbed + to_hp, to_hp, absorbed)
	taken.target_id = a
	facts.append(taken)
	return facts


static func _taken(unit_id: String, amount: int, to_hp: int, absorbed: int) -> CombatFact:
	var fact: CombatFact = CombatFact.new(CombatFact.Kind.DAMAGE_TAKEN, unit_id)
	fact.amount = amount
	fact.hp_amount = to_hp
	fact.block_amount = absorbed
	return fact


static func _phase(side: CombatFact.CombatSide) -> CombatFact:
	var fact: CombatFact = CombatFact.new(CombatFact.Kind.PHASE_START)
	fact.side = side
	return fact


# The pop-up added last to the unit info layer; null with none.
static func _last_popup(view: BattleView) -> DamageNumber:
	var popups: Array[Node2D] = view.get_info_layer().get_popups()
	return null if popups.is_empty() else popups[popups.size() - 1] as DamageNumber


# Why number isn't where the camera draws board_point now; empty when it is.
static func _place_problems(
		view: BattleView, number: DamageNumber, board_point: Vector2, when: String
) -> PackedStringArray:
	var problems: PackedStringArray = []
	var expected: Vector2 = view.get_camera_rig().board_to_screen() * board_point
	if number.position.distance_to(expected) > PLACE_TOLERANCE:
		problems.append("%s at %s, expected %s" % [when, number.position, expected])
	return problems
