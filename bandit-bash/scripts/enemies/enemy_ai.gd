# ==============================================================================
# Bandit Bash
# Copyright (c) 2026 Derc Development
# Licensed under the MIT License. See LICENSE.
#
# File:     enemy_ai.gd
# Author:
# Created:  October 30, 2026
# Modified: November 13, 2026
# ==============================================================================

class_name EnemyAI
extends RefCounted
## The enemy side's AI: rates every option an enemy has with the forecast the player sees, and
## plays the enemies one at a time, highest-rated first (enemies and AI plan, The AI).
##
## [method decide] lists every (end tile, action, target) its behavior allows, each attack and
## staff previewed fresh from its tile with [ForecastRolls], and rates them in [EnemyPlan]'s order:
## a kill (target or splash) first for every behavior, then the class's target rule. Each
## behavior's rules are in [method decide]. A flooded end tile is dropped when a dry one serves the
## same goal; after the darkness every enemy plays Aggressive on the nearest foe.
## [method next_command] re-decides every enemy yet to act and gives the best plan, so each sees
## what the ones before it did. Rules code: pure, static, deterministic, no RNG or logging
## ([member EffectEngine.diagnostics]); on a sandbox no other thread touches it may run on a
## worker ([method Intents.PreviewJob.run]).
##
## @tutorial(Enemies and AI plan): docs/plans/2026-10-30-enemies-and-ai.md
## @tutorial(Enemy roster): docs/design/enemy-roster.md
##
## @todo: TOD-001 - Block staves and a second move after acting; no class uses either before
## EN8's Bloodhound, and an enemy holding a Block staff regroups.
## @todo: TOD-002 - A boss holding a fixed tile keeps its behavior after the darkness (EN7's mark).
## @todo: TOD-003 - The Warcaller's War Horn, its signature move (EN7); until then it only rallies.
## @todo: TOD-004 - Cutthroat looting: with no attack worth taking, it opens a chest or searches a
## searchable to deny it (EN9; map_objects.gd:TOD-002).

## (c)'s weight on the damage share: Godot_FE's damage bonus ([code]aiAction.gd[/code],
## [code]generate_attack_action_rating[/code]).
const VALUE_WEIGHT: float = 100.0

## (c)'s extra weight when the enemy takes no damage back: Godot_FE's no-damage-received bonus, in
## the same function, so a free hit rates its share × 150.
const NO_DAMAGE_BONUS: float = 50.0

## (d)'s avoid divisor: Godot_FE's [code]calculate_terrain_rating[/code]
## ([code]aiAction.gd[/code]).
const AVOID_DIVISOR: float = 50.0

## The range a weapon reaches to count as ranged: a bow, a tome, the Javelin. A Shieldbearer
## guards an ally holding one, and a Raider goes for foes that carry nothing else or staves.[br]
## [b]Units:[/b] tiles, the weapon's longest range.
const RANGED_REACH: int = 2

## How near an ally counts for the Warcaller's rule, "stays within 2 tiles of the most allies"
## (enemy-roster.md, the Warcaller), by grid distance.[br]
## [b]Units:[/b] tiles.
const RALLY_TILES: int = 2

# Added to a foe's HP under the Cutthroat's rule unless it is Exposed: larger than any HP, so every
# Exposed foe ranks first, then the lowest HP.
const _UNEXPOSED_RANK: float = 1000000.0


## Registers the AI on [param session]'s [constant CombatHooks.Hook.ENEMY_COMMANDS], reading each
## enemy's class from [param catalog]. Once per session, before its battle opens.
static func register(session: CombatSession, catalog: EffectCatalog.Index) -> void:
	session.hooks.add(CombatHooks.Hook.ENEMY_COMMANDS, EnemyAI.next_command.bind(catalog))


## The [constant CombatHooks.Hook.ENEMY_COMMANDS] registration: the best plan of every enemy yet
## to act ([method next_plan]) as its command, seat -1; null once every enemy has acted. A plan
## that fails [method UnitTurnCommand.validate] becomes a Wait, with a diagnostic, so a fault
## never repeats until the phase's command limit.
static func next_command(session: CombatSession, catalog: EffectCatalog.Index) -> Command:
	var plan: EnemyPlan = next_plan(session.engine, catalog, flooded_tiles(session.state))
	if plan == null:
		return null
	var command: UnitTurnCommand = plan.to_command()
	var reason: String = command.validate(session)
	if reason.is_empty():
		return command
	session.engine.diagnostics.append("EnemyAI: %s's %s plan rejected - %s; it waits" % [
		session.describe(plan.actor_id), command.get_label(), reason,
	])
	return UnitTurnCommand.new(-1, plan.actor_id, UnitTurnCommand.Action.WAIT)


## The highest-rated plan ([method EnemyPlan.is_better_than]) among every enemy on
## [param engine]'s map that hasn't acted, each decided on the board as it is now
## ([method decide]); null when none is left. Runs on a sandbox engine unchanged.
static func next_plan(
		engine: EffectEngine,
		catalog: EffectCatalog.Index,
		flooded: Dictionary[Vector2i, bool] = {}
) -> EnemyPlan:
	var state: CombatState = engine.state
	var best: EnemyPlan = null
	for unit_id: String in state.units_of(CombatFact.CombatSide.ENEMY):
		if state.unit(unit_id).has_acted:
			continue
		var plan: EnemyPlan = decide(engine, catalog, unit_id, flooded)
		if best == null or plan.is_better_than(best):
			best = plan
	return best


## [param unit_id]'s best plan on [param engine]'s map, its class read from [param catalog]: the
## options its behavior allows, rated in [EnemyPlan]'s order; a Wait with no option or no class.
## Aggressive and Skirmisher: the best attack in reach, else advance on the nearest foe (a Hound,
## on the foe nearest its pack). Hold: a kill, else from its own tile, else as Aggressive. Guard:
## any attack in reach, else stay; a Shieldbearer first takes its place beside its back-line ally.
## Support: heal the most wounded ally, else regroup; a Warcaller attacks only from where most
## allies stay near. Changes nothing. [param flooded]: the darkness's ([method flooded_tiles]).
static func decide(
		engine: EffectEngine,
		catalog: EffectCatalog.Index,
		unit_id: String,
		flooded: Dictionary[Vector2i, bool] = {}
) -> EnemyPlan:
	var state: CombatState = engine.state
	var definition: EnemyClassDefinition = null
	if catalog != null and state.has_unit(unit_id):
		definition = catalog.enemy_class(state.unit_type_of(unit_id))
	if definition == null:
		return _wait_plan(state, unit_id, EnemyClassDefinition.Behavior.AGGRESSIVE, "")
	var board: Board = Board.new(engine, unit_id, flooded)
	board.catalog = catalog
	board.behavior = definition.behavior
	board.rule = definition.target_rule_id
	if Reinforcements.has_darkness_arrived(state) and not _holds_fixed_tile(state, unit_id):
		board.behavior = EnemyClassDefinition.Behavior.AGGRESSIVE
		# The target rule turns to the nearest foe with the behavior, as the-darkness.md
		# (Arrival) words it: "moves toward and attacks the nearest reachable target".
		board.rule = ContentIds.TARGET_NEAREST_FOE

	var options: Array[EnemyPlan] = []
	match board.behavior:
		EnemyClassDefinition.Behavior.AGGRESSIVE, EnemyClassDefinition.Behavior.SKIRMISHER:
			# A Skirmisher moves as Aggressive with its own rule, and never moves after attacking.
			options = _prefer_dry(board, _attacks(board))
		EnemyClassDefinition.Behavior.HOLD:
			options = _from_own_tile(board, _prefer_dry(board, _attacks(board)))
		EnemyClassDefinition.Behavior.GUARD:
			options = _prefer_dry(board, _guards(board))
		EnemyClassDefinition.Behavior.SUPPORT:
			options = _prefer_dry(board, _heals(board))
			if options.is_empty() and board.rule == ContentIds.TARGET_MOST_ALLIES_NEAR:
				# TODO(TOD-003): the War Horn, with EN7's signature moves.
				options = _prefer_dry(board, _rallies(board))
			elif options.is_empty():
				options = _prefer_dry(board, _regroups(board))
	# A Guard never advances: with nobody in reach it stays where it stands.
	var advances: bool = (
			board.behavior == EnemyClassDefinition.Behavior.AGGRESSIVE
			or board.behavior == EnemyClassDefinition.Behavior.HOLD
			or board.behavior == EnemyClassDefinition.Behavior.SKIRMISHER
	)
	# TODO(TOD-004): a Cutthroat with no attack loots a chest or a searchable before it advances
	# (EN9).
	if options.is_empty() and advances:
		options = _prefer_dry(board, _advances(board))
	if options.is_empty():
		return _wait_plan(state, unit_id, board.behavior, board.rule)
	_rate_target_rule(board, options)
	return _best(options)


## The tiles the darkness has flooded on [param state]'s map, any layer, for [method decide]: its
## [member MapState.darkness]. The dry rule weighs flooded against dry only, never one layer
## against another (the-darkness.md, Enemy AI).
static func flooded_tiles(state: CombatState) -> Dictionary[Vector2i, bool]:
	var flooded: Dictionary[Vector2i, bool] = {}
	for tile: Vector2i in state.map.darkness.layers:
		flooded[tile] = true
	return flooded


## Rating step (d) for [param tile] on [param grid]: avoid ÷ [constant AVOID_DIVISOR] + DEF + RES
## of its terrain. Higher is better.
static func terrain_rating(grid: CombatGrid, tile: Vector2i) -> float:
	var bonus: CombatGrid.TileBonus = grid.tile_bonus(tile)
	# Avoid ÷ 50 is an exact quotient (question 21); Godot_FE's int avoid
	# floors it (avoid 20 rates 0 there).
	return bonus.avoid / AVOID_DIVISOR + bonus.defense + bonus.resistance


# Every attack the enemy can make this turn: each weapon that attacks (the one in hand, and the
# stowed one through a free Sidearm swap, which the forecast checks), from each end tile, on each
# foe in range there, kept when its preview is legal.
static func _attacks(board: Board) -> Array[EnemyPlan]:
	var options: Array[EnemyPlan] = []
	var state: CombatState = board.state
	var holder: CombatUnitState = state.unit(board.unit_id)
	var weapon_ids: Array[String] = [holder.equipped_weapon_id, holder.stowed_weapon_id]
	var foes: PackedStringArray = state.units_of(CombatFact.CombatSide.PLAYER)
	for order: int in weapon_ids.size():
		var held: CombatState.WeaponStats = state.weapon(weapon_ids[order])
		if held == null or not _attacks_with(held):
			continue
		var span: Vector2i = Vector2i(held.range_min, held.range_max)
		if order == 0:
			span = _range_of(board.engine, board.unit_id)
		for tile: Vector2i in board.reach:
			var path: Array[Vector2i] = board.path_to(tile)
			for foe: String in foes:
				var distance: int = state.grid.distance(tile, state.tile_of(foe))
				if distance < span.x or distance > span.y:
					continue
				var command: UnitTurnCommand = UnitTurnCommand.new(
						-1, board.unit_id, UnitTurnCommand.Action.ATTACK, foe, path
				)
				if order == 1:
					command.weapon_id = held.id
				# Without hit breakdowns: no rating step reads them.
				var forecast: CombatForecast.ExchangeForecast = CombatForecast.exchange(
						board.engine, command, ForecastRolls.new(), false
				)
				if forecast.is_legal:
					options.append(_attack_plan(board, tile, forecast, command.weapon_id, order))
	return options


# One attack's plan, rated from its forecast: (a) and (c).
static func _attack_plan(
		board: Board,
		tile: Vector2i,
		forecast: CombatForecast.ExchangeForecast,
		weapon_id: String,
		weapon_order: int
) -> EnemyPlan:
	var plan: EnemyPlan = _new_plan(board, EnemyPlan.Kind.ATTACK, tile)
	plan.target_id = forecast.target_id
	plan.weapon_id = weapon_id
	plan.weapon_order = weapon_order
	plan.forecast = forecast
	plan.is_kill = _defeats_a_foe(board, forecast)
	var chance: float = 1.0
	var dealt: float = 0.0
	var taken: float = 0.0
	for attack: CombatForecast.AttackForecast in forecast.attacks:
		# Expected damage is each hit's HP damage (Block absorbs the rest) times its hit
		# chance; Godot_FE's counted every hit, unweighted, before Block existed.
		var expected: float = attack.hp_damage * attack.hit_probability
		if attack.attacker_id == board.unit_id:
			chance *= attack.hit_probability
			dealt += expected
		elif attack.attacker_id == plan.target_id:
			taken += expected
	plan.kill_chance = chance if plan.is_kill else 0.0
	var max_hp: int = board.engine.stats(plan.target_id).get_int(CombatValue.Key.HP)
	var share: float = clampf(dealt / max_hp, 0.0, 1.0) if max_hp > 0 else 0.0
	plan.value = share * (VALUE_WEIGHT + (NO_DAMAGE_BONUS if taken == 0.0 else 0.0))
	return plan


# Whether forecast defeats a player unit: the target, or another by splash (Cleave beside the
# enemy), question 21. Its own side's losses never count, for or against: it swings with its allies
# beside it (enemy-roster.md, the Brute).
static func _defeats_a_foe(board: Board, forecast: CombatForecast.ExchangeForecast) -> bool:
	# ASSUMPTION: every kill counts the same: a splash kill ranks as a direct one, and two kills in
	# one option as one; among kills, the higher chance that the enemy's hits land still wins.
	for outcome: CombatForecast.UnitOutcome in forecast.units:
		var side: CombatFact.CombatSide = board.state.side_of(outcome.unit_id)
		if outcome.is_defeated and side == CombatFact.CombatSide.PLAYER:
			return true
	return false


# Every heal the enemy can give this turn with the heal staff in hand: from each end tile, on each
# damaged ally in range there (itself, for a range-0 staff), kept when its preview is legal. Each
# rates the player units that could attack its end tile next phase.
static func _heals(board: Board) -> Array[EnemyPlan]:
	var options: Array[EnemyPlan] = []
	var state: CombatState = board.state
	var held: CombatState.WeaponStats = state.equipped_weapon(board.unit_id)
	# TODO(TOD-001): a Block staff (Shelter) on an ally; no enemy class holds one yet.
	if held == null or held.staff != CombatState.WeaponStats.Staff.HEAL:
		return options
	var span: Vector2i = _range_of(board.engine, board.unit_id)
	var allies: PackedStringArray = state.units_of(CombatFact.CombatSide.ENEMY)
	for tile: Vector2i in board.reach:
		var path: Array[Vector2i] = board.path_to(tile)
		for ally: String in allies:
			var is_self: bool = ally == board.unit_id
			var distance: int = 0 if is_self else state.grid.distance(tile, state.tile_of(ally))
			if distance < span.x or distance > span.y:
				continue
			if state.get_hp(ally) >= board.engine.stats(ally).get_int(CombatValue.Key.HP):
				continue
			var command: UnitTurnCommand = UnitTurnCommand.new(
					-1, board.unit_id, UnitTurnCommand.Action.STAFF, "" if is_self else ally, path
			)
			var forecast: CombatForecast.StaffForecast = CombatForecast.staff(
					board.engine, command, ForecastRolls.new()
			)
			if not forecast.is_legal:
				continue
			var plan: EnemyPlan = _new_plan(board, EnemyPlan.Kind.STAFF, tile)
			plan.target_id = ally
			plan.forecast = forecast
			plan.safety = _safety_of(board, tile)
			options.append(plan)
	return options


# Support with nobody to heal: every end tile, rated by the player units that could attack it next
# phase, then its tile distance to every ally.
static func _regroups(board: Board) -> Array[EnemyPlan]:
	var options: Array[EnemyPlan] = []
	var state: CombatState = board.state
	var allies: Array[Vector2i] = _ally_tiles(board)
	for tile: Vector2i in board.reach:
		var plan: EnemyPlan = _new_plan(board, EnemyPlan.Kind.REGROUP, tile)
		plan.safety = _safety_of(board, tile)
		# "Nearest its allies" is the summed tile distance to every ally, ranked after
		# the fewest player units that could attack the tile.
		for ally_tile: Vector2i in allies:
			plan.pack += state.grid.distance(tile, ally_tile)
		options.append(plan)
	return options


# The Warcaller with nobody to heal: every kill in reach, the attacks from an end tile with the
# most allies within RALLY_TILES, and every regroup; the target rule then rates each end tile by
# those allies, before Support's safety and summed distance.
static func _rallies(board: Board) -> Array[EnemyPlan]:
	var most: int = 0
	for tile: Vector2i in board.reach:
		most = maxi(most, _allies_near(board, tile))
	var options: Array[EnemyPlan] = []
	for plan: EnemyPlan in _attacks(board):
		if plan.is_kill or _allies_near(board, plan.tile) == most:
			options.append(plan)
	options.append_array(_regroups(board))
	return options


# Guard: every attack it can reach this turn, moving if it must; with none it stays (it never
# advances). A Shieldbearer with a back-line ally left takes its place beside it first (_beside).
static func _guards(board: Board) -> Array[EnemyPlan]:
	if board.rule == ContentIds.TARGET_BACK_LINE_ALLY:
		var ally: String = _back_line_ally(board)
		if not ally.is_empty():
			var beside: Array[EnemyPlan] = _beside(board, ally)
			if not beside.is_empty():
				return beside
	return _attacks(board)


# The Shieldbearer beside ally: its end tiles next to ally, or with none in reach the tiles
# leaving the least movement to one; a wait on each, the attacks from them, and every kill in
# reach (kills first). Empty when it can't walk toward ally at all, so it plays Guard.
static func _beside(board: Board, ally: String) -> Array[EnemyPlan]:
	var options: Array[EnemyPlan] = []
	var state: CombatState = board.state
	var ally_tile: Vector2i = state.tile_of(ally)
	var posts: Dictionary[Vector2i, int] = {}
	for tile: Vector2i in board.reach:
		if state.grid.distance(tile, ally_tile) == 1:
			posts[tile] = 0
	if posts.is_empty():
		# ASSUMPTION: short of a tile beside its ally, it ends where the least movement is left
		# to one, attacking from there if it can.
		var left: Dictionary[Vector2i, int] = _cost_to(
				state, _stand_tiles(board, ally_tile, Vector2i(1, 1)),
				board.movement_type, board.side
		)
		var least: int = -1
		for tile: Vector2i in board.reach:
			if left.has(tile) and (least < 0 or left[tile] < least):
				least = left[tile]
		if least < 0:
			return options
		for tile: Vector2i in board.reach:
			if left.get(tile, -1) == least:
				posts[tile] = least
	for plan: EnemyPlan in _attacks(board):
		if plan.is_kill or posts.has(plan.tile):
			options.append(plan)
	for tile: Vector2i in posts:
		# ASSUMPTION: among its posts it takes the best terrain, then the least path cost (the
		# fixed order); nothing else ranks them.
		var plan: EnemyPlan = _new_plan(board, EnemyPlan.Kind.REGROUP, tile)
		plan.progress = posts[tile]
		options.append(plan)
	return options


# The Shieldbearer's back-line ally: the nearest other enemy whose class plays Support or that
# carries a ranged weapon (RANGED_REACH); empty when none is left.
static func _back_line_ally(board: Board) -> String:
	var state: CombatState = board.state
	var found: String = ""
	var found_distance: int = -1
	for ally: String in state.units_of(CombatFact.CombatSide.ENEMY):
		if ally == board.unit_id:
			continue
		var definition: EnemyClassDefinition = null
		if board.catalog != null:
			definition = board.catalog.enemy_class(state.unit_type_of(ally))
		var is_support: bool = (
				definition != null
				and definition.behavior == EnemyClassDefinition.Behavior.SUPPORT
		)
		if not is_support and not _carries_ranged(state, ally):
			continue
		# ASSUMPTION: nearest by tile distance, then id; the rule names no measure.
		var distance: int = state.grid.distance(board.origin, state.tile_of(ally))
		var is_nearer: bool = (
				found_distance < 0
				or distance < found_distance
				or (distance == found_distance and ally < found)
		)
		if is_nearer:
			found = ally
			found_distance = distance
	return found


# Whether unit_id carries a weapon that attacks and reaches RANGED_REACH tiles, in hand or stowed.
static func _carries_ranged(state: CombatState, unit_id: String) -> bool:
	for held: CombatState.WeaponStats in _carried(state, unit_id):
		if _attacks_with(held) and held.range_max >= RANGED_REACH:
			return true
	return false


# The Raider's back-line foe: a unit carrying a weapon, every one ranged (RANGED_REACH) or a
# staff.
static func _is_back_line_foe(state: CombatState, unit_id: String) -> bool:
	var carried: Array[CombatState.WeaponStats] = _carried(state, unit_id)
	if carried.is_empty():
		return false
	for held: CombatState.WeaponStats in carried:
		if not held.is_staff() and held.range_max < RANGED_REACH:
			return false
	return true


# The weapons unit_id carries: the one in hand, then the stowed one, each when it has one.
static func _carried(state: CombatState, unit_id: String) -> Array[CombatState.WeaponStats]:
	var carried: Array[CombatState.WeaponStats] = []
	var unit: CombatUnitState = state.unit(unit_id)
	for weapon_id: String in [unit.equipped_weapon_id, unit.stowed_weapon_id]:
		var held: CombatState.WeaponStats = state.weapon(weapon_id)
		if held != null:
			carried.append(held)
	return carried


# The Hexer's rule: the player units its Curse would catch hitting target_id, the target and
# every unit beside it (enemy-roster.md, Curse); its own side caught too never counts against.
static func _cursed_foes(state: CombatState, target_id: String) -> int:
	var center: Vector2i = state.tile_of(target_id)
	var caught: int = 0
	for foe: String in state.units_of(CombatFact.CombatSide.PLAYER):
		if state.grid.distance(center, state.tile_of(foe)) <= 1:
			caught += 1
	return caught


# Other enemies within RALLY_TILES of tile, by grid distance, where they stand now.
static func _allies_near(board: Board, tile: Vector2i) -> int:
	var near: int = 0
	for ally_tile: Vector2i in _ally_tiles(board):
		if board.state.grid.distance(tile, ally_tile) <= RALLY_TILES:
			near += 1
	return near


# The tiles of every other enemy on the map.
static func _ally_tiles(board: Board) -> Array[Vector2i]:
	var tiles: Array[Vector2i] = []
	for ally: String in board.state.units_of(CombatFact.CombatSide.ENEMY):
		if ally != board.unit_id:
			tiles.append(board.state.tile_of(ally))
	return tiles


# The least grid distance from unit_id to any of tiles; 0 with no tiles, so nothing is preferred.
static func _nearest_distance(state: CombatState, unit_id: String, tiles: Array[Vector2i]) -> int:
	var least: int = -1
	for tile: Vector2i in tiles:
		var distance: int = state.grid.distance(state.tile_of(unit_id), tile)
		if least < 0 or distance < least:
			least = distance
	return maxi(least, 0)


# With no attack: the nearest foe by path cost to a tile the enemy could attack it from
# (Godot_FE's move search), then every end tile still able to walk there, rated by the cost left.
# A Hound goes for the foe nearest its pack instead, and rates each tile by the allies beside it.
static func _advances(board: Board) -> Array[EnemyPlan]:
	var options: Array[EnemyPlan] = []
	var state: CombatState = board.state
	var span: Vector2i = _advance_range(board)
	var walked: Dictionary[Vector2i, int] = Pathing.flood(
			state, board.origin, -1, board.movement_type, board.side
	)
	var with_pack: bool = board.rule == ContentIds.TARGET_PACK_LOWEST_HP
	var pack_tiles: Array[Vector2i] = []
	if with_pack:
		pack_tiles = _ally_tiles(board)
	var nearest_id: String = ""
	var nearest_key: Vector2i = Vector2i(-1, -1)
	var nearest_goals: Array[Vector2i] = []
	for foe: String in state.units_of(CombatFact.CombatSide.PLAYER):
		var goals: Array[Vector2i] = _stand_tiles(board, state.tile_of(foe), span)
		var cost: int = -1
		for goal: Vector2i in goals:
			if walked.has(goal) and (cost < 0 or walked[goal] < cost):
				cost = walked[goal]
		if cost < 0:
			continue
		# ASSUMPTION: the foe nearest a Hound's pack is the one with the least tile distance to
		# any other enemy, then its own path cost (first pass); alone, its own nearest foe.
		var key: Vector2i = Vector2i(_nearest_distance(state, foe, pack_tiles), cost)
		var is_nearer: bool = (
				nearest_id.is_empty()
				or key.x < nearest_key.x
				or (key.x == nearest_key.x and key.y < nearest_key.y)
				or (key == nearest_key and foe < nearest_id)
		)
		if is_nearer:
			nearest_id = foe
			nearest_key = key
			nearest_goals = goals
	if nearest_id.is_empty():
		return options
	var left: Dictionary[Vector2i, int] = _cost_to(
			state, nearest_goals, board.movement_type, board.side
	)
	for tile: Vector2i in board.reach:
		if not left.has(tile):
			continue
		var plan: EnemyPlan = _new_plan(board, EnemyPlan.Kind.ADVANCE, tile)
		plan.target_id = nearest_id
		plan.progress = left[tile]
		if with_pack:
			# ASSUMPTION: among tiles equally far along, the most allies beside it (first pass).
			for ally_tile: Vector2i in pack_tiles:
				if state.grid.distance(tile, ally_tile) == 1:
					plan.allies_beside += 1
		options.append(plan)
	return options


# Hold: every kill in reach, wherever it ends, since kills come first for every behavior
# (question 21); of the rest, only those from its own tile while it has any (Steady Aim). With
# none from its own tile, all of them. The dry rule runs before this (question 21), so a Hold enemy
# on a flooded tile moves to a dry one that serves the same attack rather than stand.
static func _from_own_tile(board: Board, options: Array[EnemyPlan]) -> Array[EnemyPlan]:
	var kept: Array[EnemyPlan] = []
	var standing: Array[EnemyPlan] = []
	for plan: EnemyPlan in options:
		if plan.is_kill:
			kept.append(plan)
		elif plan.tile == board.origin:
			standing.append(plan)
	if standing.is_empty():
		return options
	kept.append_array(standing)
	return kept


# Drops each flooded option whose action, target and kill a dry option also serves
# (the-darkness.md, Enemy AI). A kill from a flooded tile is not served by a dry tile that only
# wounds.
static func _prefer_dry(board: Board, options: Array[EnemyPlan]) -> Array[EnemyPlan]:
	if board.flooded.is_empty():
		return options
	var served: Dictionary[String, bool] = {}
	for plan: EnemyPlan in options:
		if not plan.is_flooded:
			served[_goal_of(plan)] = true
	var kept: Array[EnemyPlan] = []
	for plan: EnemyPlan in options:
		if not plan.is_flooded or not served.has(_goal_of(plan)):
			kept.append(plan)
	return kept


# Step (b) on every option of one enemy: lower is better. The Warcaller's rule rates every end
# tile, target or not; the others rate each option's target.
static func _rate_target_rule(board: Board, options: Array[EnemyPlan]) -> void:
	if board.rule == ContentIds.TARGET_MOST_ALLIES_NEAR:
		for plan: EnemyPlan in options:
			plan.target_rule_key = -_allies_near(board, plan.tile)
		return
	var nearest: Dictionary[String, int] = {}
	for plan: EnemyPlan in options:
		if plan.target_id.is_empty():
			continue
		if not nearest.has(plan.target_id) or plan.path_cost < nearest[plan.target_id]:
			nearest[plan.target_id] = plan.path_cost
	for plan: EnemyPlan in options:
		if plan.target_id.is_empty():
			continue
		var hp: int = board.state.get_hp(plan.target_id)
		match board.rule:
			# Holding its ground, the Duelist and the Shieldbearer take the foe they reach with
			# the least movement, as the nearest foe.
			ContentIds.TARGET_NEAREST_FOE, ContentIds.TARGET_HOLDS_GROUND, \
					ContentIds.TARGET_BACK_LINE_ALLY:
				plan.target_rule_key = nearest[plan.target_id]
			ContentIds.TARGET_EXPOSED_THEN_LOWEST_HP:
				var is_exposed: bool = board.state.get_stance(plan.target_id) == 0
				plan.target_rule_key = hp + (0.0 if is_exposed else _UNEXPOSED_RANK)
			ContentIds.TARGET_PACK_LOWEST_HP:
				plan.target_rule_key = hp
			ContentIds.TARGET_MOST_CURSED:
				plan.target_rule_key = -_cursed_foes(board.state, plan.target_id)
			ContentIds.TARGET_BACK_LINE_FOES:
				var is_back_line: bool = _is_back_line_foe(board.state, plan.target_id)
				plan.target_rule_key = 0.0 if is_back_line else 1.0
			ContentIds.TARGET_LOWEST_DEFENSE:
				# The target's DEF stat as its unit panel shows it, without its terrain.
				plan.target_rule_key = board.engine.stats(plan.target_id).get_int(
						CombatValue.Key.DEF
				)
			ContentIds.TARGET_MOST_WOUNDED_ALLY:
				var max_hp: int = board.engine.stats(plan.target_id).get_int(CombatValue.Key.HP)
				plan.target_rule_key = -(max_hp - board.state.get_hp(plan.target_id))


# The best of options, with the step that made it beat its rival: the best option on another
# target or of another kind (why this target), else the next best (why this tile).
static func _best(options: Array[EnemyPlan]) -> EnemyPlan:
	var best: EnemyPlan = options[0]
	for i: int in range(1, options.size()):
		if options[i].is_better_than(best):
			best = options[i]
	var rival: EnemyPlan = null
	var next_best: EnemyPlan = null
	for plan: EnemyPlan in options:
		if plan == best:
			continue
		if next_best == null or plan.is_better_than(next_best):
			next_best = plan
		var is_other_choice: bool = plan.target_id != best.target_id or plan.kind != best.kind
		if is_other_choice and (rival == null or plan.is_better_than(rival)):
			rival = plan
	best.decided_by = best.deciding_step(rival if rival != null else next_best)
	return best


# A plan of kind ending on tile, with what every kind rates: path, path cost, flood, terrain.
static func _new_plan(board: Board, kind: EnemyPlan.Kind, tile: Vector2i) -> EnemyPlan:
	var plan: EnemyPlan = EnemyPlan.new()
	plan.actor_id = board.unit_id
	plan.kind = kind
	plan.behavior = board.behavior
	plan.target_rule_id = board.rule
	plan.tile = tile
	plan.path = board.path_to(tile)
	plan.path_cost = board.reach.get(tile, 0)
	plan.is_flooded = board.flooded.has(tile)
	plan.terrain = terrain_rating(board.state.grid, tile)
	return plan


static func _wait_plan(
		state: CombatState,
		unit_id: String,
		behavior: EnemyClassDefinition.Behavior,
		rule: String
) -> EnemyPlan:
	var plan: EnemyPlan = EnemyPlan.new()
	plan.actor_id = unit_id
	plan.kind = EnemyPlan.Kind.WAIT
	plan.behavior = behavior
	plan.target_rule_id = rule
	plan.tile = state.tile_of(unit_id)
	if plan.tile != CombatFact.NO_TILE:
		plan.terrain = terrain_rating(state.grid, plan.tile)
	return plan


# How many player units could attack tile next phase: with their full movement, from any tile they
# could end on, with the weapon in hand. Counted once per board, on the board as it is.
static func _safety_of(board: Board, tile: Vector2i) -> int:
	if not board.has_threats:
		board.has_threats = true
		var state: CombatState = board.state
		for foe: String in state.units_of(CombatFact.CombatSide.PLAYER):
			var held: CombatState.WeaponStats = state.equipped_weapon(foe)
			if held == null or not _attacks_with(held):
				continue
			var foe_unit: CombatUnitState = state.unit(foe)
			# NOTE: next phase's full movement, not what is left of this turn's; the deciding
			# enemy's own tile still blocks them, as it does until it moves.
			var walked: Dictionary[Vector2i, int] = Pathing.flood(
					state,
					foe_unit.tile,
					board.engine.stats(foe).get_int(CombatValue.Key.MOVEMENT),
					foe_unit.movement_type,
					foe_unit.side
			)
			var span: Vector2i = _range_of(board.engine, foe)
			var covered: Dictionary[Vector2i, bool] = {}
			for end: Vector2i in walked:
				var occupant: String = state.occupant_at(end)
				if not occupant.is_empty() and occupant != foe:
					continue
				for target: Vector2i in _tiles_within(end, span):
					covered[target] = true
			for target: Vector2i in covered:
				board.threats[target] = board.threats.get(target, 0) + 1
	return board.threats.get(tile, 0)


# Whether unit_id is a boss that holds a fixed tile, which keeps its behavior after the darkness
# arrives (the-darkness.md, Arrival).
static func _holds_fixed_tile(_state: CombatState, _unit_id: String) -> bool:
	# TODO(TOD-002): EN7's boss mark answers; no boss exists before it.
	return false


# What the same goal means for the dry rule: the same kind of action, on the same target, with the
# same kill.
static func _goal_of(plan: EnemyPlan) -> String:
	return "%d %s %s" % [plan.kind, plan.target_id, plan.is_kill]


# Whether held attacks: any weapon but a Block or heal staff.
static func _attacks_with(held: CombatState.WeaponStats) -> bool:
	return not held.is_staff() or held.staff == CombatState.WeaponStats.Staff.ATTACK


# unit_id's range now, as (shortest, longest), from its values for the weapon in hand.
static func _range_of(engine: EffectEngine, unit_id: String) -> Vector2i:
	var sheet: StatSheet = engine.stats(unit_id)
	return Vector2i(
			sheet.get_int(CombatValue.Key.RANGE_MIN), sheet.get_int(CombatValue.Key.RANGE_MAX)
	)


# The range an advance closes to: the weapon in hand's when it attacks, else the stowed one's.
static func _advance_range(board: Board) -> Vector2i:
	var holder: CombatUnitState = board.state.unit(board.unit_id)
	var held: CombatState.WeaponStats = board.state.weapon(holder.equipped_weapon_id)
	if held != null and _attacks_with(held):
		return _range_of(board.engine, board.unit_id)
	var stowed: CombatState.WeaponStats = board.state.weapon(holder.stowed_weapon_id)
	if stowed != null and _attacks_with(stowed):
		return Vector2i(stowed.range_min, stowed.range_max)
	# An enemy with nothing to attack with (a healer once the darkness arrives) closes
	# to an adjacent tile.
	return Vector2i(1, 1)


# The tiles within reach (shortest, longest) of center that the enemy could end its move on:
# terrain and objects let it stand there, and no other unit does.
static func _stand_tiles(board: Board, center: Vector2i, reach: Vector2i) -> Array[Vector2i]:
	var found: Array[Vector2i] = []
	for tile: Vector2i in _tiles_within(center, reach):
		if not board.state.can_stand(tile, board.movement_type):
			continue
		var occupant: String = board.state.occupant_at(tile)
		if occupant.is_empty() or occupant == board.unit_id:
			found.append(tile)
	return found


# Every tile whose tile distance from center is within reach (shortest, longest), on the map
# or not.
static func _tiles_within(center: Vector2i, reach: Vector2i) -> Array[Vector2i]:
	var found: Array[Vector2i] = []
	for dy: int in range(-reach.y, reach.y + 1):
		var across: int = reach.y - absi(dy)
		for dx: int in range(-across, across + 1):
			if absi(dx) + absi(dy) >= reach.x:
				found.append(center + Vector2i(dx, dy))
	return found


# The movement cost left from each tile to the nearest of goals, for a mover of movement_type on
# side: Pathing.flood run backwards, each step paying the cost of the tile it enters.
static func _cost_to(
		state: CombatState,
		goals: Array[Vector2i],
		movement_type: CombatGrid.MovementType,
		side: CombatFact.CombatSide
) -> Dictionary[Vector2i, int]:
	var settled: Dictionary[Vector2i, int] = {}
	var best: Dictionary[Vector2i, int] = {}
	var frontier: Array[Vector2i] = []
	for goal: Vector2i in goals:
		best[goal] = 0
		frontier.append(goal)
	while not frontier.is_empty():
		var pick: int = 0
		for i: int in range(1, frontier.size()):
			if best[frontier[i]] < best[frontier[pick]]:
				pick = i
		var tile: Vector2i = frontier.pop_at(pick)
		settled[tile] = best[tile]
		var entry: int = state.grid.move_cost(tile, movement_type)
		for direction: Vector2i in CombatGrid.DIRECTIONS:
			var from: Vector2i = state.grid.step(tile, direction)
			if from == CombatFact.NO_TILE or settled.has(from):
				continue
			if not Pathing.can_enter(state, from, movement_type, side):
				continue
			var total: int = best[tile] + entry
			if best.has(from) and best[from] <= total:
				continue
			best[from] = total
			if not frontier.has(from):
				frontier.append(from)
	return settled


## One enemy's view of the board for one decision: where it can end and how it gets there, the
## behavior and target rule it plays, and the player units' reach next phase, counted once.
## Built and read by [EnemyAI] only.
class Board:
	extends RefCounted

	## The engine the decision reads; a sandbox's works unchanged.
	var engine: EffectEngine = null
	## The catalog every enemy's class is read from: the Shieldbearer reads its allies' behaviors.
	var catalog: EffectCatalog.Index = null
	## Its state.
	var state: CombatState = null
	## The enemy deciding.
	var unit_id: String = ""
	## Its tile.
	var origin: Vector2i = CombatFact.NO_TILE
	## Its movement type.
	var movement_type: CombatGrid.MovementType = CombatGrid.MovementType.DEFAULT
	## Its side, whose units it walks through.
	var side: CombatFact.CombatSide = CombatFact.CombatSide.ENEMY
	## The tiles the darkness has flooded.
	var flooded: Dictionary[Vector2i, bool] = {}
	## The behavior it plays, after the darkness switch.
	var behavior: EnemyClassDefinition.Behavior = EnemyClassDefinition.Behavior.AGGRESSIVE
	## The target rule it plays.
	var rule: String = ""
	## Every tile it can end its move on, with the cost to get there ([method Pathing.reach]).
	var reach: Dictionary[Vector2i, int] = {}
	## How many player units could attack each tile next phase; filled on first use, while
	## [member has_threats] is false.
	var threats: Dictionary[Vector2i, int] = {}
	## Whether [member threats] is filled.
	var has_threats: bool = false

	# The flood reach is cut from, every tile it can walk through: the paths.
	var _walked: Dictionary[Vector2i, int] = {}

	func _init(
			on_engine: EffectEngine, of_unit: String, flooded_tiles: Dictionary[Vector2i, bool]
	) -> void:
		engine = on_engine
		state = engine.state
		unit_id = of_unit
		flooded = flooded_tiles
		var mover: CombatUnitState = state.unit(of_unit)
		origin = mover.tile
		movement_type = mover.movement_type
		side = mover.side
		reach = Pathing.reach(engine, state, of_unit)
		_walked = Pathing.flood(
				state, origin, Pathing.budget_of(engine, state, of_unit), movement_type, side
		)

	## A cheapest walk from [member origin] to [param tile], one of [member reach]: each step back
	## to the first neighbor, in [constant CombatGrid.DIRECTIONS] order, whose cost leads to it.
	## Empty when [param tile] is [member origin].
	func path_to(tile: Vector2i) -> Array[Vector2i]:
		var path: Array[Vector2i] = []
		if tile == origin:
			return path
		path.append(tile)
		var at: Vector2i = tile
		while at != origin:
			var entry: int = state.grid.move_cost(at, movement_type)
			var came_from: Vector2i = CombatFact.NO_TILE
			for direction: Vector2i in CombatGrid.DIRECTIONS:
				var before: Vector2i = state.grid.step(at, direction)
				if _walked.has(before) and _walked[before] + entry == _walked[at]:
					came_from = before
					break
			# NOTE: never missing for a tile of reach; a broken walk fails the command's path check.
			if came_from == CombatFact.NO_TILE:
				break
			path.push_front(came_from)
			at = came_from
		return path
