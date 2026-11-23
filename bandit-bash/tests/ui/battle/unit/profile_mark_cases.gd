# ==============================================================================
# Bandit Bash
# Copyright (c) 2026 Derc Development
# Licensed under the MIT License. See LICENSE.
#
# File:     profile_mark_cases.gd
# Author:
# Created:  November 23, 2026
# Modified: November 23, 2026
# ==============================================================================

extends RefCounted
## The weapon-profile marks' cases for the ui/board suite (RF-039, ui-lift.md UL11): each profile's
## shape on each side, filled for the player and hollow for the enemy, and nothing on neither
## side; every M1 token's mark showing its held weapon's profile and its side; a Sidearm swap and
## a paid swap back changing a token's mark only as each WEAPON_SWAPPED plays, from the fact's
## weapon while the state is already past it; and the unit detail's Weapon and Stowed rows leading
## with the same mark, the other gear rows with none. No autoload is named or needed.

# The suite that runs this file; tests/case_files.gd finds it by this line.
const SUITE: String = "ui/board"

const BattleViewCases = preload("res://tests/ui/battle/board/battle_view_cases.gd")

const M1_DEFINITION: String = "res://maps/standard/m1_greybox.tres"
const VIEW_SCENE: PackedScene = preload("res://ui/battle/board/battle_view.tscn")
const MARK_SCENE: PackedScene = preload("res://ui/battle/unit/profile_mark.tscn")
const DETAIL_SCENE: PackedScene = preload("res://ui/battle/unit/unit_detail_panel.tscn")

# The other UI cases' seed: nothing here compares golden numbers.
const SEED: int = 0x0C0FFEE

const STOWED_ID: String = "test:stowed_weapon"

const PLAYER: CombatFact.CombatSide = CombatFact.CombatSide.PLAYER
const ENEMY: CombatFact.CombatSide = CombatFact.CombatSide.ENEMY
const NEITHER: CombatFact.CombatSide = CombatFact.CombatSide.NONE

# Each profile and the shape the style guide gives it.
const SHAPES: Dictionary[WeaponTriangle.Profile, ProfileMark.Shape] = {
	WeaponTriangle.Profile.POWER: ProfileMark.Shape.SQUARE,
	WeaponTriangle.Profile.BALANCE: ProfileMark.Shape.CIRCLE,
	WeaponTriangle.Profile.NIMBLE: ProfileMark.Shape.TRIANGLE,
	WeaponTriangle.Profile.NONE: ProfileMark.Shape.BAR,
}

var _check: Callable
var _root: Node = null
var _catalog: EffectCatalog.Index = null
var _map: CombatMapDefinition = null


## [param check]: called as check(case_name: String, passed: bool, detail: String).
## [param root]: where boards and panels are added, so their nodes are in the tree.
func _init(check: Callable, root: Node) -> void:
	_check = check
	_root = root
	_catalog = EffectCatalog.index()


## Runs every case.
func run() -> void:
	_test_shapes_and_sides()
	_map = load(M1_DEFINITION) as CombatMapDefinition
	if _map == null:
		_check.call("profile marks: the M1 map definition loads", false, M1_DEFINITION)
		return
	_test_board()
	_test_swaps()
	_test_detail_rows()


# Each profile on the player side is its shape, filled; on the enemy side the same shape, hollow;
# on neither side nothing at all.
func _test_shapes_and_sides() -> void:
	var mark: ProfileMark = MARK_SCENE.instantiate()
	_root.add_child(mark)
	var wrong: PackedStringArray = []
	for profile: WeaponTriangle.Profile in SHAPES:
		var profile_name: String = WeaponTriangle.Profile.find_key(profile) as String
		for side: CombatFact.CombatSide in [PLAYER, ENEMY]:
			mark.show_mark(side, profile)
			var is_player: bool = side == PLAYER
			if (
					not mark.is_shown() or mark.is_filled() != is_player
					or mark.get_shape() != SHAPES[profile]
					or ProfileMark.shape_of(profile) != SHAPES[profile]
			):
				wrong.append("%s on side %d: shown %s, filled %s, shape %d" % [
					profile_name, side, mark.is_shown(), mark.is_filled(), mark.get_shape(),
				])
	_check.call("marks: Power square, Balance circle, Nimble triangle, None bar; filled for the "
			+ "player, hollow for the enemy", wrong.is_empty(), "; ".join(wrong))
	var shown_on_neither: PackedStringArray = []
	for profile: WeaponTriangle.Profile in SHAPES:
		mark.show_mark(NEITHER, profile)
		if mark.is_shown():
			shown_on_neither.append(WeaponTriangle.Profile.find_key(profile) as String)
	_check.call("marks: a unit on neither side shows no mark, whatever its profile", (
			shown_on_neither.is_empty()
	), ", ".join(shown_on_neither))
	mark.show_mark(PLAYER, WeaponTriangle.Profile.POWER)
	mark.show_side(ENEMY)
	var kept_shape: bool = mark.get_shape() == ProfileMark.Shape.SQUARE and not mark.is_filled()
	mark.show_profile(WeaponTriangle.Profile.NIMBLE)
	var kept_side: bool = mark.side == ENEMY and mark.get_shape() == ProfileMark.Shape.TRIANGLE
	_check.call("marks: a new side keeps the shape, a new profile keeps the side", (
			kept_shape and kept_side
	))
	mark.free()


# Every token on the M1 board: its mark shows its side and its held weapon's profile.
func _test_board() -> void:
	var board: BattleViewCases.Board = _board("board: the M1 battle begins")
	if board == null:
		return
	var state: CombatState = board.session.state
	var wrong: PackedStringArray = []
	var sides: Dictionary[int, int] = {}
	for unit_id: String in board.view.token_ids():
		var token: UnitToken = board.view.token_of(unit_id)
		var mark: ProfileMark = token.info.get_profile_mark()
		var side: CombatFact.CombatSide = state.side_of(unit_id)
		var held: WeaponTriangle.Profile = state.weapon_profile_of(
				state.equipped_weapon_id(unit_id)
		)
		if mark.side != side or mark.profile != held or token.profile != held:
			wrong.append("%s: side %d shows %d, profile %d shows %d" % [
				unit_id, side, mark.side, held, mark.profile,
			])
		sides[side] = sides.get(side, 0) + 1
	_check.call("board: every token's mark shows its side and its held weapon's profile", (
			wrong.is_empty() and sides.get(PLAYER, 0) > 0 and sides.get(ENEMY, 0) > 0
	), "; ".join(wrong))
	board.close()


# A player unit with a stowed weapon of another profile and Sidearm swaps for free, then pays to
# swap back, both resolved before either fact plays: the mark keeps the first weapon's profile
# until the first fact plays, shows the stowed weapon's though the state already holds the first
# again, and only the second fact brings the first back.
func _test_swaps() -> void:
	var board: BattleViewCases.Board = _board("swaps: the M1 battle begins")
	if board == null:
		return
	var session: CombatSession = board.session
	var state: CombatState = session.state
	var unit_id: String = state.units_of(PLAYER)[0]
	var first: WeaponTriangle.Profile = state.weapon_profile_of(state.equipped_weapon_id(unit_id))
	var other: WeaponTriangle.Profile = WeaponTriangle.Profile.NIMBLE
	if first == WeaponTriangle.Profile.NIMBLE:
		other = WeaponTriangle.Profile.POWER
	_give_sidearm(session, unit_id, other)
	var mark: ProfileMark = board.view.token_of(unit_id).info.get_profile_mark()
	var logged: int = session.engine.fact_log.size()
	var free_reason: String = WeaponSwap.resolve(session.engine, state, unit_id, true)
	var swap_facts: Array[CombatFact] = session.engine.fact_log.slice(logged)
	logged = session.engine.fact_log.size()
	var paid_reason: String = WeaponSwap.resolve(session.engine, state, unit_id, false)
	var back_facts: Array[CombatFact] = session.engine.fact_log.slice(logged)
	var swapped: bool = (
			free_reason.is_empty() and paid_reason.is_empty()
			and _has_swap(swap_facts) and _has_swap(back_facts)
	)
	_check.call("swaps: a Sidearm swap and a paid swap back resolve, each a WEAPON_SWAPPED", (
			swapped
	), "free '%s', paid '%s'" % [free_reason, paid_reason])
	if not swapped:
		board.close()
		return
	var before: WeaponTriangle.Profile = mark.profile
	session.playback.enqueue(swap_facts)
	BattleViewCases.settle(board.view)
	var after_free: WeaponTriangle.Profile = mark.profile
	var held_now: WeaponTriangle.Profile = state.weapon_profile_of(
			state.equipped_weapon_id(unit_id)
	)
	_check.call("swaps: the mark changes only as the Sidearm swap's fact plays, to its weapon's", (
			before == first and after_free == other and held_now == first
	), "before %d, after %d (expected %d then %d); the state holds %d" % [
		before, after_free, first, other, held_now,
	])
	session.playback.enqueue(back_facts)
	BattleViewCases.settle(board.view)
	_check.call("swaps: the paid swap back's fact brings the first profile back", (
			mark.profile == first and mark.side == PLAYER and mark.is_filled()
	), "shows %d, expected %d" % [mark.profile, first])
	board.close()


# The unit detail of a player unit with a stowed weapon and of an enemy: the Weapon and Stowed
# rows show each weapon's mark in the unit's style; Equipment and Pouch show none.
func _test_detail_rows() -> void:
	var board: BattleViewCases.Board = _board("detail rows: the M1 battle begins")
	if board == null:
		return
	var session: CombatSession = board.session
	var state: CombatState = session.state
	var player_id: String = state.units_of(PLAYER)[0]
	var held: WeaponTriangle.Profile = state.weapon_profile_of(state.equipped_weapon_id(player_id))
	var stowed: WeaponTriangle.Profile = WeaponTriangle.Profile.POWER
	if held == WeaponTriangle.Profile.POWER:
		stowed = WeaponTriangle.Profile.BALANCE
	_give_sidearm(session, player_id, stowed)
	var enemy_id: String = state.units_of(ENEMY)[0]
	var cases: Array[Array] = [
		[player_id, PLAYER, held, stowed],
		[enemy_id, ENEMY, state.weapon_profile_of(state.equipped_weapon_id(enemy_id)), -1],
	]
	for entry: Array in cases:
		var unit_id: String = entry[0]
		var side: CombatFact.CombatSide = entry[1]
		var weapon_profile: WeaponTriangle.Profile = entry[2]
		var stowed_profile: int = entry[3]
		var panel: UnitDetailPanel = DETAIL_SCENE.instantiate()
		_root.add_child(panel)
		panel.show_detail(UnitDetailViewModel.build(session, unit_id))
		var problems: PackedStringArray = []
		var weapon_mark: ProfileMark = _row_mark(panel, ^"%WeaponRow")
		if not _shows(weapon_mark, side, weapon_profile):
			problems.append("Weapon row: %s" % [_describe(weapon_mark)])
		var stowed_mark: ProfileMark = _row_mark(panel, ^"%StowedRow")
		if stowed_profile >= 0 and not _shows(
				stowed_mark, side, stowed_profile as WeaponTriangle.Profile
		):
			problems.append("Stowed row: %s" % [_describe(stowed_mark)])
		for path: NodePath in [^"%EquipmentRow", ^"%PouchRow"]:
			var none: ProfileMark = _row_mark(panel, path)
			if none == null or none.visible:
				problems.append("%s: %s" % [path, _describe(none)])
		_check.call("detail rows (%s): each weapon row leads with its mark, other rows none" % [
			"player" if side == PLAYER else "enemy",
		], problems.is_empty(), "; ".join(problems))
		panel.free()
	board.close()


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


# The Sidearm fixture of forecast_cases.gd, with the stowed weapon's profile given: a stowed
# sword of that profile and free weapon swaps for unit_id.
func _give_sidearm(
		session: CombatSession, unit_id: String, profile: WeaponTriangle.Profile
) -> void:
	var sword: CombatState.WeaponStats = CombatState.WeaponStats.new()
	sword.id = STOWED_ID
	sword.label = "Stowed Sword"
	sword.weapon_type = "sword"
	sword.damage = 5
	sword.atk_x = 1
	sword.profile = profile
	sword.range_min = 1
	sword.range_max = 1
	sword.hit = 80
	sword.crit_x = 3.0
	sword.weight = 8
	session.state.add_weapon(sword)
	session.state.unit(unit_id).stowed_weapon_id = STOWED_ID
	session.state.load_bases(session.engine, unit_id)
	var grant: SetPermission = SetPermission.new()
	grant.permission = CombatValue.Permission.FREE_WEAPON_SWAP
	grant.allow = true
	var definition: EffectDefinition = EffectDefinition.new()
	definition.id = "test_sidearm"
	definition.operations.append(grant)
	var state: CombatState = session.state
	var owner: EffectOwner = EffectOwner.for_unit(
			unit_id, state.seat_of(unit_id), state.side_of(unit_id)
	)
	session.engine.register(EffectInstance.new(
			"test:sidearm", definition, owner, Modifier.SourceKind.UNIT_TRAIT, "test:sidearm"
	))


static func _has_swap(facts: Array[CombatFact]) -> bool:
	for fact: CombatFact in facts:
		if fact.kind == CombatFact.Kind.WEAPON_SWAPPED:
			return true
	return false


static func _row_mark(panel: UnitDetailPanel, path: NodePath) -> ProfileMark:
	var row: DetailGearRow = panel.get_node_or_null(path) as DetailGearRow
	return null if row == null else row.get_profile_mark()


static func _shows(
		mark: ProfileMark, side: CombatFact.CombatSide, profile: WeaponTriangle.Profile
) -> bool:
	return (
			mark != null and mark.visible and mark.side == side and mark.profile == profile
			and mark.is_filled() == (side == PLAYER)
	)


static func _describe(mark: ProfileMark) -> String:
	if mark == null:
		return "no mark"
	return "visible %s, side %d, profile %d" % [mark.visible, mark.side, mark.profile]
