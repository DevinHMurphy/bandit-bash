# ==============================================================================
# Bandit Bash
# Copyright (c) 2026 Derc Development
# Licensed under the MIT License. See LICENSE.
#
# File:     m1_battle_cases.gd
# Author:
# Created:  November 4, 2026
# Modified: November 4, 2026
# ==============================================================================

extends RefCounted
## The headless M1 battle for tests/enemies/run_all.gd (enemies and AI plan, EN4 row): the
## Mercenary army ([method StartingArmy.build]) against the M1 pack on the greybox map, begun
## through [method CampaignSession.begin_battle] on the real catalog with seeded rolls, the AI
## playing the enemies, runs to [constant CombatFact.Kind.COMBAT_ENDED]; the same seed gives the
## same fact log twice. Reports each case through the check callable it is given.
##
## [b]The player driver[/b] is deliberately simple, so the battle tests the AI and the turn loop,
## not tactics. In the opening swap window it sends Start, swapping nothing. Each player phase,
## each player unit still on the map, in roster order: when the weapon in hand attacks, it takes
## the attack it can reach on the enemy with the least HP (then the least path cost, the end tile
## in row-major order, the enemy's id); with none, it walks to the reachable tile nearest the
## nearest enemy by tile distance (then path cost, row-major order) and waits. A unit whose weapon
## doesn't attack (the Battle Medic's Shelter) waits where it stands. Then the seat ends its turn.
## [br]
## [b]Past par:[/b] a second pair of battles holds back (the seat ends its turn without acting)
## through [constant HOLD_UNTIL], so the darkness arrives at the end of turn 4 (par 5) and
## releases again; the same seed must still give the same fact log twice.

const M1_DEFINITION: String = "res://maps/standard/m1_greybox.tres"

# The last turn the past-par driver holds back, found by trying: with the seed below, holding
# through turn 3 runs the battle to turn 7, past both the arrival (end of turn 4) and the second
# wave (end of turn 6); holding through 4 or more loses the commander in turn 5, through 2 wins
# in turn 6.
const HOLD_UNTIL: int = 3

# The M1 map's turn par, as m1_greybox.tres sets it.
const M1_TURN_PAR: int = 5

# Any fixed seed: the checks compare two runs, never golden numbers.
const SEED: int = 0xE4F_0001

# Floor 1 is step 1, whose enemies are level 1 (game-vision.md, Run structure).
const FLOOR: int = 1
const NODE: int = 1

# Turns the battle may take before the check gives up: well past what four units need to rout
# three, so only a stalled battle reaches it.
const MAX_TURNS: int = 30

const PLAYER: CombatFact.CombatSide = CombatFact.CombatSide.PLAYER
const ENEMY: CombatFact.CombatSide = CombatFact.CombatSide.ENEMY

var _check: Callable
var _catalog: EffectCatalog.Index = null


## [param check]: called as check(case_name: String, passed: bool, detail: String).
func _init(check: Callable) -> void:
	_check = check
	_catalog = EffectCatalog.index()


## Runs every case.
func run() -> void:
	var map: CombatMapDefinition = load(M1_DEFINITION) as CombatMapDefinition
	if map == null:
		_check.call("m1 battle: the M1 map definition loads", false, M1_DEFINITION)
		return
	var first: Battle = _play(map)
	var second: Battle = _play(map)
	_check.call("m1 battle: begins with the Mercenary army against the M1 pack", (
			first.problems.is_empty() and first.players == 4 and first.enemies == 3
	), "%s; %d player units, %d enemies" % [first.problems, first.players, first.enemies])
	_check.call("m1 battle: runs to COMBAT_ENDED", (
			first.has_ended and first.rejected.is_empty()
	), "%s after turn %d; rejected %s" % [first.outcome, first.turns, first.rejected])
	_check.call("m1 battle: the enemies acted", first.enemy_actions > 0, str(first.enemy_actions))
	_check.call("m1 battle: the same seed gives the same fact log twice", (
			first.facts.size() > 0 and first.facts == second.facts
	), "%d / %d facts" % [first.facts.size(), second.facts.size()])
	print("      m1 battle: %s after turn %d, %d facts, %d enemy actions" % [
		first.outcome, first.turns, first.facts.size(), first.enemy_actions,
	])

	var held: Battle = _play(map, HOLD_UNTIL)
	var held_again: Battle = _play(map, HOLD_UNTIL)
	_check.call("m1 battle past par: the turn par is 5", map.turn_par == M1_TURN_PAR,
			str(map.turn_par))
	_check.call("m1 battle past par: runs past turn par with no command rejected", (
			held.problems.is_empty() and held.turns > M1_TURN_PAR and held.rejected.is_empty()
	), "%s after turn %d; rejected %s" % [held.outcome, held.turns, held.rejected])
	_check.call("m1 battle past par: the darkness arrives at the end of turn 4", (
			held.release_turns.size() > 0 and held.release_turns[0] == M1_TURN_PAR - 1
	), str(held.release_turns))
	_check.call("m1 battle past par: the next wave 2 turns later", (
			held.release_turns.size() > 1 and held.release_turns[1] == M1_TURN_PAR + 1
	), str(held.release_turns))
	_check.call("m1 battle past par: the same seed gives the same fact log twice", (
			held.facts.size() > 0 and held.facts == held_again.facts
	), "%d / %d facts" % [held.facts.size(), held_again.facts.size()])
	print("      m1 battle past par: %s after turn %d, %d facts, releases at %s" % [
		held.outcome, held.turns, held.facts.size(), held.release_turns,
	])


# One battle from Begin to its end, or to MAX_TURNS. Through turn [param hold_until], the seat
# ends its turn without acting.
func _play(map: CombatMapDefinition, hold_until: int = 0) -> Battle:
	var played: Battle = Battle.new()
	var run: CampaignSession = CampaignSession.new(
			CampaignData.Mode.SOLO, SEED, PackedInt32Array([0])
	)
	var mercenary: StartingArmy = StartingArmy.build(_catalog, "mercenary", run.ids)
	played.problems.append_array(mercenary.problems)
	var army: CampaignSession.Army = CampaignSession.Army.new()
	army.unit_instances = mercenary.units
	army.item_instances = mercenary.items
	army.heirloom_ids = mercenary.heirloom_ids
	var request: CampaignSession.BattleRequest = CampaignSession.BattleRequest.new()
	request.floor_number = FLOOR
	request.node = NODE
	request.pool = [map]
	request.catalog = _catalog
	request.armies[0] = army
	var battle: CombatEncounter = run.begin_battle(request)
	if battle == null:
		played.problems.append("begin_battle gave no battle")
		run.close()
		return played
	var session: CombatSession = battle.get_session(0)
	played.players = session.state.units_of(PLAYER).size()
	played.enemies = session.state.units_of(ENEMY).size()

	# The opening swap setting is on by default: the seat starts at once, swapping nothing.
	if session.state.map.opening_swap_open:
		_send(session, StartCommand.new(0), played)
	# Bounded by player phases played, not by the turn number, so a battle stuck short of a phase
	# still stops.
	for _phase: int in MAX_TURNS:
		if session.is_finished:
			break
		var acting: PackedStringArray = (
				session.state.units_of(PLAYER) if session.state.turn > hold_until
				else PackedStringArray()
		)
		for unit_id: String in acting:
			if session.is_finished:
				break
			if not session.state.has_unit(unit_id) or session.state.unit(unit_id).has_acted:
				continue
			_send(session, _turn_for(session, unit_id), played)
		if not session.is_finished:
			_send(session, EndTurnCommand.new(0), played)

	played.turns = session.state.turn
	played.has_ended = session.is_finished
	played.outcome = "running" if not session.is_finished else (
			"won" if session.is_won else "lost"
	)
	var turn: int = 0
	for fact: CombatFact in session.engine.fact_log:
		played.facts.append(JSON.stringify(fact.to_wire()))
		if fact.kind == CombatFact.Kind.PHASE_START:
			turn = fact.amount
		var is_release: bool = (
				fact.kind == CombatFact.Kind.DARKNESS_ADVANCED
				and (fact.flags & CombatFact.Flag.DARKNESS_RELEASED) != 0
		)
		if is_release:
			played.release_turns.append(turn)
		var acts: bool = (
				fact.kind == CombatFact.Kind.ATTACK_MADE
				or fact.kind == CombatFact.Kind.USED_STAFF_ON_ALLY
				or fact.kind == CombatFact.Kind.UNIT_MOVED
		)
		if acts and session.state.side_of(fact.actor_id) == ENEMY:
			played.enemy_actions += 1
	run.close()
	return played


func _send(session: CombatSession, command: Command, played: Battle) -> void:
	session.submit(command)
	var batch: CombatSession.FactBatch = session.resolve_next()
	if batch != null and batch.is_rejected():
		played.rejected.append("%s %s: %s" % [batch.label, batch.actor_id, batch.rejected_reason])


# The driver's turn for unit_id (see the class doc).
func _turn_for(session: CombatSession, unit_id: String) -> UnitTurnCommand:
	var state: CombatState = session.state
	var wait: UnitTurnCommand = UnitTurnCommand.new(0, unit_id)
	var held: CombatState.WeaponStats = state.equipped_weapon(unit_id)
	if held == null or (held.is_staff() and held.staff != CombatState.WeaponStats.Staff.ATTACK):
		return wait
	var sheet: StatSheet = session.stats(unit_id)
	var shortest: int = sheet.get_int(CombatValue.Key.RANGE_MIN)
	var longest: int = sheet.get_int(CombatValue.Key.RANGE_MAX)
	var reach: Dictionary[Vector2i, int] = Pathing.reach(session.engine, state, unit_id)
	var ends: Array[Vector2i] = []
	ends.assign(reach.keys())
	ends.sort_custom(EnemyPlan.tile_precedes)
	var foes: PackedStringArray = state.units_of(ENEMY)

	var best: UnitTurnCommand = null
	var best_key: Array = []
	for tile: Vector2i in ends:
		for foe: String in foes:
			var distance: int = state.grid.distance(tile, state.tile_of(foe))
			if distance < shortest or distance > longest:
				continue
			var key: Array = [state.get_hp(foe), reach[tile], foe]
			if best != null and not _is_lower(key, best_key):
				continue
			var attack: UnitTurnCommand = UnitTurnCommand.new(
					0, unit_id, UnitTurnCommand.Action.ATTACK, foe, _path_to(session, unit_id, tile)
			)
			if attack.validate(session).is_empty():
				best = attack
				best_key = key
	if best != null:
		return best

	var nearest: int = -1
	var goal: Vector2i = state.tile_of(unit_id)
	for tile: Vector2i in ends:
		for foe: String in foes:
			var distance: int = state.grid.distance(tile, state.tile_of(foe))
			var is_nearer: bool = (
					nearest < 0
					or distance < nearest
					or (distance == nearest and reach[tile] < reach[goal])
			)
			if is_nearer:
				nearest = distance
				goal = tile
	if goal == state.tile_of(unit_id):
		return wait
	return UnitTurnCommand.new(
			0, unit_id, UnitTurnCommand.Action.WAIT, "", _path_to(session, unit_id, goal)
	)


# Whether key a sorts before key b, entry by entry ([HP, path cost, id]); tiles are already walked
# in row-major order, so the first tile found keeps a tie.
static func _is_lower(a: Array, b: Array) -> bool:
	for i: int in a.size():
		if a[i] != b[i]:
			return a[i] < b[i]
	return false


# A cheapest walk from unit_id's tile to tile, one of its reach: each step back to the first
# neighbor, in CombatGrid.DIRECTIONS order, whose cost leads to it.
static func _path_to(session: CombatSession, unit_id: String, tile: Vector2i) -> Array[Vector2i]:
	var state: CombatState = session.state
	var mover: CombatUnitState = state.unit(unit_id)
	var path: Array[Vector2i] = []
	if tile == mover.tile:
		return path
	var walked: Dictionary[Vector2i, int] = Pathing.flood(
			state,
			mover.tile,
			Pathing.budget_of(session.engine, state, unit_id),
			mover.movement_type,
			mover.side
	)
	path.append(tile)
	var at: Vector2i = tile
	while at != mover.tile:
		var entry: int = state.grid.move_cost(at, mover.movement_type)
		var came_from: Vector2i = CombatFact.NO_TILE
		for direction: Vector2i in CombatGrid.DIRECTIONS:
			var before: Vector2i = state.grid.step(at, direction)
			if walked.has(before) and walked[before] + entry == walked[at]:
				came_from = before
				break
		if came_from == CombatFact.NO_TILE:
			path.clear()
			return path
		path.push_front(came_from)
		at = came_from
	return path


## What one battle did, for comparing two runs.
class Battle:
	extends RefCounted

	## Setup problems: the army's, or no battle.
	var problems: PackedStringArray = []
	## Player units on the map when it opened.
	var players: int = 0
	## Enemies on the map when it opened.
	var enemies: int = 0
	## Commands the session rejected, one line each.
	var rejected: PackedStringArray = []
	## The turn it stopped on.
	var turns: int = 0
	## Whether COMBAT_ENDED was recorded.
	var has_ended: bool = false
	## "won", "lost" or "running".
	var outcome: String = ""
	## Every fact, as its wire form in JSON.
	var facts: PackedStringArray = []
	## Enemy moves, attacks and staff uses.
	var enemy_actions: int = 0
	## The turn of each darkness wave released, in order: the turn whose darkness step released it.
	var release_turns: PackedInt32Array = []
