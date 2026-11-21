# ==============================================================================
# Bandit Bash
# Copyright (c) 2026 Derc Development
# Licensed under the MIT License. See LICENSE.
#
# File:     enemy_ai.gd
# Author:
# Created:  October 30, 2026
# Modified: November 21, 2026
# ==============================================================================

class_name EnemyAI
extends RefCounted
## The enemy side's AI: rates every option an enemy has with the forecast the player sees, and
## plays the enemies one at a time, highest-rated first (enemies and AI plan, The AI).
##
## [method decide] lists every (end tile, action, target) its behavior allows, each attack and
## staff previewed fresh from its tile with [ForecastRolls], and rates them in [EnemyPlan]'s order:
## a kill (target, splash or a keg's blast) first, then the class's target rule; each behavior's
## rules and object uses are in [method decide]. A flooded end tile is dropped when a dry one
## serves the same goal; after the darkness every enemy but a post holder plays Aggressive on the
## nearest foe.
## [method next_command] re-decides every enemy yet to act and gives the best plan, so each sees
## what the ones before it did. Rules code: pure, static, deterministic, no RNG or logging
## ([member EffectEngine.diagnostics]); on a sandbox no other thread touches it may run on a
## worker ([method Intents.PreviewJob.run]).
##
## @tutorial(Enemies and AI plan): docs/plans/2026-10-30-enemies-and-ai.md
## @tutorial(Enemy roster): docs/design/enemy-roster.md
## @tutorial(Map objects): docs/design/map-objects.md
##
## @todo: TOD-001 - Block staves; no enemy class holds one, and an enemy holding one regroups.
## @todo: TOD-005 - Levers off a Seize or Defend map: opening a route toward a foe, and sealing one
## on other objectives, once a map needs it.

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

## How far from its target a Hex Storm reaches, for the Hex Matron's rule (enemy-roster.md, Hex
## Storm: "every unit within 2 tiles of its target"), by grid distance. The Hex Matron's data
## draws the same area with its 2-tile shape.[br]
## [b]Units:[/b] tiles.
const HEX_STORM_TILES: int = 2

# Added to a foe's HP under the Cutthroat's rule unless it is Exposed: larger than any HP, so every
# Exposed foe ranks first, then the lowest HP.
const _UNEXPOSED_RANK: float = 1000000.0

# The path cost to the objective tile of a player side that can't reach it: larger than any path,
# so a lever that cuts the last route always raises it.
const _SEALED: int = 1 << 30


## Registers the AI on [param session]'s [constant CombatHooks.Hook.ENEMY_COMMANDS], reading each
## enemy's class from [param catalog], and the Powder Baron's throw ([method KegBarrage.register]).
## Once per session, before its battle opens.
static func register(session: CombatSession, catalog: EffectCatalog.Index) -> void:
	session.hooks.add(CombatHooks.Hook.ENEMY_COMMANDS, EnemyAI.next_command.bind(catalog))
	KegBarrage.register(session)


## The [constant CombatHooks.Hook.ENEMY_COMMANDS] registration: the best plan of every enemy yet
## to act ([method next_plan]) as its command, seat -1; null once every enemy has acted. A plan
## that fails [method UnitTurnCommand.validate] becomes a Wait, with a diagnostic, so a fault
## never repeats until the phase's command limit.
static func next_command(session: CombatSession, catalog: EffectCatalog.Index) -> Command:
	var plan: EnemyPlan = next_plan(
			session.engine, catalog, flooded_tiles(session.state), objective_tiles(session)
	)
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
## ([method decide]); null when none is left. An enemy with a second move pending after acting
## (the Bloodhound's kill) takes it first ([method decide_second_move]), right after its action.
## Runs on a sandbox engine unchanged.
static func next_plan(
		engine: EffectEngine,
		catalog: EffectCatalog.Index,
		flooded: Dictionary[Vector2i, bool] = {},
		objective: Array[Vector2i] = []
) -> EnemyPlan:
	var state: CombatState = engine.state
	var best: EnemyPlan = null
	for unit_id: String in state.units_of(CombatFact.CombatSide.ENEMY):
		if state.unit(unit_id).is_second_move_pending:
			return decide_second_move(engine, catalog, unit_id, flooded, objective)
	for unit_id: String in state.units_of(CombatFact.CombatSide.ENEMY):
		if state.unit(unit_id).has_acted:
			continue
		var plan: EnemyPlan = decide(engine, catalog, unit_id, flooded, objective)
		if best == null or plan.is_better_than(best):
			best = plan
	return best


## [param unit_id]'s best plan on [param engine]'s map, changing nothing, its class from
## [param catalog]; a Wait with no option or class. Aggressive, Skirmisher: the best attack in
## reach, else advance (a Hound toward its pack's nearest foe). Hold: a kill, else from its tile,
## else as Aggressive. Guard: any attack in reach, else stay (a Shieldbearer beside its ally).
## Support: heal, else regroup (a Warcaller near most allies). Post holders keep theirs after the
## darkness; attackers blow kegs to kill, looters loot, idle advancers seal or douse. Reads
## [method flooded_tiles] and [method objective_tiles]; [param forecasts] reuses attack forecasts
## ([Forecasts]), [param footprint] records what it read ([Footprint]); null for none.
static func decide(
		engine: EffectEngine,
		catalog: EffectCatalog.Index,
		unit_id: String,
		flooded: Dictionary[Vector2i, bool] = {},
		objective: Array[Vector2i] = [],
		forecasts: Forecasts = null,
		footprint: Footprint = null
) -> EnemyPlan:
	var state: CombatState = engine.state
	var definition: EnemyClassDefinition = null
	if catalog != null and state.has_unit(unit_id):
		definition = catalog.enemy_class(state.unit_type_of(unit_id))
	if definition == null:
		return _wait_plan(state, unit_id, EnemyClassDefinition.Behavior.AGGRESSIVE, "")
	var board: Board = Board.new(engine, unit_id, flooded)
	board.objective = objective
	board.catalog = catalog
	board.forecasts = forecasts
	if footprint != null:
		footprint.begin(board)
		board.footprint = footprint
	board.behavior = definition.behavior
	board.rule = definition.target_rule_id
	if Reinforcements.has_darkness_arrived(state) and not definition.holds_post:
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
				# The Warcaller rallies; its War Horn needs no plan, since the trait fires on its
				# own at its side's Phase Start.
				options = _prefer_dry(board, _rallies(board))
			elif options.is_empty():
				options = _prefer_dry(board, _regroups(board))
	# A Guard never advances: with nobody in reach it stays where it stands.
	var advances: bool = (
			board.behavior == EnemyClassDefinition.Behavior.AGGRESSIVE
			or board.behavior == EnemyClassDefinition.Behavior.HOLD
			or board.behavior == EnemyClassDefinition.Behavior.SKIRMISHER
	)
	# Looting is the class's, not the behavior's; once the darkness arrives every enemy only fights.
	var can_loot: bool = (
			MapObjects.is_looter(engine, state, unit_id)
			and not Reinforcements.has_darkness_arrived(state)
	)
	if can_loot:
		options.append_array(_prefer_dry(board, _loots(board)))
	if options.is_empty() and advances:
		options = _prefer_dry(board, _object_uses(board))
		options.append_array(_prefer_dry(board, _advances(board)))
	if options.is_empty():
		return _wait_plan(state, unit_id, board.behavior, board.rule)
	_rate_target_rule(board, options)
	return _best(options)


## [param unit_id]'s second move after acting on [param engine]'s map, with the movement it has
## left: an advance as its behavior's no-attack advance ([method decide]; a Hound's toward the foe
## nearest its pack), so it ends set for its next turn; a Wait, which ends the move, when no tile
## is better than its own. [member EnemyPlan.is_second_move] is set. Changes nothing.
static func decide_second_move(
		engine: EffectEngine,
		catalog: EffectCatalog.Index,
		unit_id: String,
		flooded: Dictionary[Vector2i, bool] = {},
		objective: Array[Vector2i] = []
) -> EnemyPlan:
	var state: CombatState = engine.state
	var definition: EnemyClassDefinition = null
	if catalog != null and state.has_unit(unit_id):
		definition = catalog.enemy_class(state.unit_type_of(unit_id))
	var plan: EnemyPlan = null
	if definition != null:
		var board: Board = Board.new(engine, unit_id, flooded)
		board.objective = objective
		board.catalog = catalog
		board.behavior = definition.behavior
		board.rule = definition.target_rule_id
		if Reinforcements.has_darkness_arrived(state) and not definition.holds_post:
			board.behavior = EnemyClassDefinition.Behavior.AGGRESSIVE
			board.rule = ContentIds.TARGET_NEAREST_FOE
		var options: Array[EnemyPlan] = _prefer_dry(board, _advances(board))
		if not options.is_empty():
			_rate_target_rule(board, options)
			plan = _best(options)
	if plan == null or plan.path.is_empty():
		var behavior: EnemyClassDefinition.Behavior = EnemyClassDefinition.Behavior.AGGRESSIVE
		var rule: String = ""
		if definition != null:
			behavior = definition.behavior
			rule = definition.target_rule_id
		plan = _wait_plan(state, unit_id, behavior, rule)
	plan.is_second_move = true
	return plan


## The tiles the darkness has flooded on [param state]'s map, any layer, for [method decide]: its
## [member MapState.darkness]. The dry rule weighs flooded against dry only, never one layer
## against another (the-darkness.md, Enemy AI).
static func flooded_tiles(state: CombatState) -> Dictionary[Vector2i, bool]:
	var flooded: Dictionary[Vector2i, bool] = {}
	for tile: Vector2i in state.map.darkness.layers:
		flooded[tile] = true
	return flooded


## The tiles [param session]'s player side must reach to win or hold its map, for
## [method decide]'s levers: Seize's seize tiles, Defend's defend tiles; empty on any other
## objective and outside an encounter.
static func objective_tiles(session: CombatSession) -> Array[Vector2i]:
	var tiles: Array[Vector2i] = []
	if session.setup == null or session.setup.map == null or session.layout == null:
		return tiles
	match session.setup.map.objective:
		CombatMapDefinition.Objective.SEIZE:
			tiles = session.layout.tiles_of(MapLayout.MarkerKind.SEIZE)
		CombatMapDefinition.Objective.DEFEND:
			tiles = session.layout.tiles_of(MapLayout.MarkerKind.DEFEND)
	return tiles


## Rating step (d) for [param tile] on [param grid]: avoid ÷ [constant AVOID_DIVISOR] + DEF + RES
## of its terrain. Higher is better.
static func terrain_rating(grid: CombatGrid, tile: Vector2i) -> float:
	var bonus: CombatGrid.TileBonus = grid.tile_bonus(tile)
	# Avoid ÷ 50 is an exact quotient (question 21); Godot_FE's int avoid
	# floors it (avoid 20 rates 0 there).
	return bonus.avoid / AVOID_DIVISOR + bonus.defense + bonus.resistance


# Every attack the enemy can make this turn: each weapon that attacks (the one in hand, and the
# stowed one through a free Sidearm swap, which the forecast checks), from each end tile, on each
# foe in range there, kept when its preview is legal; and on each unbroken powder keg in range,
# kept only when the blast (or the hit) defeats a player unit.
static func _attacks(board: Board) -> Array[EnemyPlan]:
	var options: Array[EnemyPlan] = []
	var state: CombatState = board.state
	var holder: CombatUnitState = state.unit(board.unit_id)
	var weapon_ids: Array[String] = [holder.equipped_weapon_id, holder.stowed_weapon_id]
	var targets: PackedStringArray = state.units_of(CombatFact.CombatSide.PLAYER)
	var kegs: PackedStringArray = _kegs(state)
	targets.append_array(kegs)
	for order: int in weapon_ids.size():
		var held: CombatState.WeaponStats = state.weapon(weapon_ids[order])
		if held == null or not _attacks_with(held):
			continue
		var span: Vector2i = ExchangeResolver.weapon_range(board.engine, board.unit_id, held.id)
		if board.footprint != null:
			board.footprint.reads_around_walk(span.y)
		for tile: Vector2i in board.reach:
			var path: Array[Vector2i] = board.path_to(tile)
			for target: String in targets:
				var distance: int = state.grid.distance(tile, state.tile_of(target))
				if distance < span.x or distance > span.y:
					continue
				var command: UnitTurnCommand = UnitTurnCommand.new(
						-1, board.unit_id, UnitTurnCommand.Action.ATTACK, target, path
				)
				if order == 1:
					command.weapon_id = held.id
				var forecast: CombatForecast.ExchangeForecast = _exchange(board, command)
				if not forecast.is_legal:
					continue
				var plan: EnemyPlan = _attack_plan(board, tile, forecast, command.weapon_id, order)
				# A keg is blown only to kill (ruthless AI): never for damage alone.
				if plan.is_kill or not kegs.has(target):
					options.append(plan)
	return options


# command's attack forecast on board's engine, without hit breakdowns (no rating step reads them):
# from board's forecasts when it has them, else made afresh.
static func _exchange(board: Board, command: UnitTurnCommand) -> CombatForecast.ExchangeForecast:
	if board.forecasts != null:
		return board.forecasts.exchange(board.engine, command)
	return CombatForecast.exchange(board.engine, command, ForecastRolls.new(), false)


# Every powder keg still on state's map, as the units that hold its HP, in spot order.
static func _kegs(state: CombatState) -> PackedStringArray:
	var kegs: PackedStringArray = []
	for keg: MapState.ObjectState in state.map.objects_of(MapLayout.ObjectKind.POWDER_KEG):
		if not keg.is_destroyed and state.has_unit(keg.id):
			kegs.append(keg.id)
	return kegs


# Every container a looter can stand on this turn that still holds something: a chest or a
# searchable (P04: every MAP_LOOT giver is a container), unopened. Among them the fixed order picks
# (_object_plan).
static func _loots(board: Board) -> Array[EnemyPlan]:
	var options: Array[EnemyPlan] = []
	var map: MapState = board.state.map
	for object_id: String in map.objects:
		var container: MapState.ObjectState = map.objects[object_id]
		if container.container_index < 0 or container.is_used or container.is_destroyed:
			continue
		if not map.contents.has(container.container_index) or not board.reach.has(container.tile):
			continue
		options.append(_object_plan(board, EnemyPlan.Kind.LOOT, container.tile, object_id))
	return options


# With nothing to attack: every lever it can stand on whose pull seals the objective's route
# (_seals), and every lit Brazier whose light covers a player unit, from each end tile beside it
# (it never lights one).
static func _object_uses(board: Board) -> Array[EnemyPlan]:
	var options: Array[EnemyPlan] = []
	var state: CombatState = board.state
	# TODO(TOD-005): levers only seal a Seize or Defend map's route; none open one toward a foe.
	if not board.objective.is_empty():
		for lever: MapState.ObjectState in state.map.objects_of(MapLayout.ObjectKind.LEVER):
			if lever.is_destroyed or lever.group_id < 0 or not board.reach.has(lever.tile):
				continue
			# Sealing reads every player unit's route to the objective, anywhere on the map.
			if board.footprint != null:
				board.footprint.is_whole = true
			if _seals(board, lever):
				options.append(_object_plan(board, EnemyPlan.Kind.USE_OBJECT, lever.tile, lever.id))
	for brazier: MapState.ObjectState in state.map.objects_of(MapLayout.ObjectKind.BRAZIER):
		if brazier.is_destroyed or not brazier.is_lit:
			continue
		# A foe walking into or out of its light changes the douse wherever the enemy reaches it.
		if board.footprint != null and _is_beside_any(brazier.tile, board.reach):
			board.footprint.reads_occupants(brazier.tile, DarknessState.BRAZIER_RADIUS)
		if not _lights_a_foe(state, brazier.tile):
			continue
		for tile: Vector2i in board.reach:
			if state.grid.distance(tile, brazier.tile) == 1:
				options.append(_object_plan(board, EnemyPlan.Kind.USE_OBJECT, tile, brazier.id))
	return options


# Whether pulling lever, walked to and pulled on a sandbox as the command would, raises the least
# path cost any player unit has to an objective tile (a cut route counts as _SEALED).
static func _seals(board: Board, lever: MapState.ObjectState) -> bool:
	if board.objective_cost < 0:
		board.objective_cost = _objective_cost(board.state, board.objective)
	var sandbox: Sandbox = Sandbox.new(board.engine, ForecastRolls.new())
	var engine: EffectEngine = sandbox.engine
	var state: CombatState = engine.state
	engine.begin_step()
	UnitTurnCommand.walk_path(engine, state, board.unit_id, board.path_to(lever.tile))
	var reason: String = MapObjects.use(engine, state, board.unit_id, lever.id)
	engine.drain()
	return reason.is_empty() and _objective_cost(state, board.objective) > board.objective_cost


# The least path cost from any player unit on state's map to any of objective, walking as that
# unit walks; _SEALED when none can reach one.
static func _objective_cost(state: CombatState, objective: Array[Vector2i]) -> int:
	var least: int = _SEALED
	for foe: String in state.units_of(CombatFact.CombatSide.PLAYER):
		var walker: CombatUnitState = state.unit(foe)
		var walked: Dictionary[Vector2i, int] = Pathing.flood(
				state, walker.tile, -1, walker.movement_type, walker.side
		)
		for tile: Vector2i in objective:
			if walked.has(tile):
				least = mini(least, walked[tile])
	return least


# Whether a player unit stands within a lit Brazier's light around tile (DarknessState).
static func _lights_a_foe(state: CombatState, tile: Vector2i) -> bool:
	for foe: String in state.units_of(CombatFact.CombatSide.PLAYER):
		if state.grid.distance(tile, state.tile_of(foe)) <= DarknessState.BRAZIER_RADIUS:
			return true
	return false


# A plan of kind (LOOT or USE_OBJECT) using object_id from tile. Terrain counts for nothing, so
# among object uses the fixed order (e) picks: the least path cost, then the tile order.
static func _object_plan(
		board: Board, kind: EnemyPlan.Kind, tile: Vector2i, object_id: String
) -> EnemyPlan:
	var plan: EnemyPlan = _new_plan(board, kind, tile)
	plan.target_id = object_id
	plan.terrain = 0.0
	return plan


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
	if board.footprint != null:
		board.footprint.reads_around_walk(span.y)
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
		# Short of a tile beside its ally, it ends where the least movement is left to one,
		# attacking from there if it can.
		var left: Dictionary[Vector2i, int] = _cost_to(
				state, _stand_tiles(board, ally_tile, Vector2i(1, 1)),
				board.movement_type, board.side
		)
		var least: int = -1
		for tile: Vector2i in board.reach:
			if left.has(tile) and (least < 0 or left[tile] < least):
				least = left[tile]
		if least < 0:
			# Cut off from its ally: a unit stepping aside can open a route of any length.
			if board.footprint != null:
				board.footprint.is_whole = true
			return options
		if board.footprint != null:
			# A route as cheap as the posts' can only pass within least of an end tile.
			var bounds: Dictionary[Vector2i, int] = {}
			for tile: Vector2i in board.reach:
				bounds[tile] = least
			board.footprint.reads_routes(ally_tile, 1, bounds)
		for tile: Vector2i in board.reach:
			if left.get(tile, -1) == least:
				posts[tile] = least
	for plan: EnemyPlan in _attacks(board):
		if plan.is_kill or posts.has(plan.tile):
			options.append(plan)
	for tile: Vector2i in posts:
		# Among its posts the best terrain wins, then the least path cost (the fixed order).
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
		# Its weapons' ranges are its stats, which an effect around it can change.
		if not is_support and board.footprint != null:
			board.footprint.reads_unit(state.tile_of(ally), 0)
		if not is_support and not _carries_ranged(board.engine, ally):
			continue
		# Nearest by tile distance, then id.
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


# Whether unit_id carries a weapon that attacks and reaches RANGED_REACH tiles, in hand or stowed,
# each range read by ExchangeResolver.weapon_range().
static func _carries_ranged(engine: EffectEngine, unit_id: String) -> bool:
	var state: CombatState = engine.state
	for held: CombatState.WeaponStats in _carried(state, unit_id):
		if (
				_attacks_with(held)
				and ExchangeResolver.weapon_range(engine, unit_id, held.id).y >= RANGED_REACH
		):
			return true
	return false


# The Raider's back-line foe: a unit carrying a weapon, every one ranged (RANGED_REACH, read by
# ExchangeResolver.weapon_range()) or a staff.
static func _is_back_line_foe(engine: EffectEngine, unit_id: String) -> bool:
	var state: CombatState = engine.state
	var carried: Array[CombatState.WeaponStats] = _carried(state, unit_id)
	if carried.is_empty():
		return false
	for held: CombatState.WeaponStats in carried:
		if (
				not held.is_staff()
				and ExchangeResolver.weapon_range(engine, unit_id, held.id).y < RANGED_REACH
		):
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
# every unit beside it (enemy-roster.md, Curse), or within HEX_STORM_TILES while the cursing unit
# holds the Hex Storm; its own side caught too never counts against.
static func _cursed_foes(board: Board, target_id: String) -> int:
	var state: CombatState = board.state
	var reach: int = 1
	# ASSUMPTION: during a Hex Storm the Hex Matron's rule counts the foes the storm's wider area
	# catches, as "whose curse catches the most player units" reads for that attack.
	if board.engine.stats(board.unit_id).is_allowed(CombatValue.Permission.HEX_STORM):
		reach = HEX_STORM_TILES
	var center: Vector2i = state.tile_of(target_id)
	var caught: int = 0
	for foe: String in state.units_of(CombatFact.CombatSide.PLAYER):
		if state.grid.distance(center, state.tile_of(foe)) <= reach:
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
		# The foe nearest a Hound's pack has the least tile distance to any other enemy, then the
		# least path cost; a Hound alone takes its own nearest foe.
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
		# No foe reachable: one walking within range of the whole flood, or freeing a tile beside
		# it, can become one.
		if board.footprint != null:
			board.footprint.reads_far(walked, maxi(span.y, 1))
		return options
	var left: Dictionary[Vector2i, int] = _cost_to(
			state, nearest_goals, board.movement_type, board.side
	)
	if board.footprint != null:
		_note_advance(board, span, nearest_key, state.tile_of(nearest_id), pack_tiles, left)
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


# Records in board's footprint what an advance on the foe at target_tile read, chosen by key
# (pack distance, path cost) and closing to span: a foe that could become nearer, by cost
# (within key.y + span.y of the enemy, every step costing at least 1) or for a Hound by distance
# (within key.x of its pack), and every route between an end tile and the foe's stand tiles that
# could get cheaper or dearer (left: the cost from each end tile). A move anywhere else changes
# neither the foe nor any cost; the target rule records the foe itself.
static func _note_advance(
		board: Board,
		span: Vector2i,
		key: Vector2i,
		target_tile: Vector2i,
		pack_tiles: Array[Vector2i],
		left: Dictionary[Vector2i, int]
) -> void:
	var footprint: Footprint = board.footprint
	footprint.reads_occupants(board.origin, key.y + span.y)
	for ally_tile: Vector2i in pack_tiles:
		footprint.reads_occupants(ally_tile, key.x)
	var bounds: Dictionary[Vector2i, int] = {}
	for tile: Vector2i in board.reach:
		# NOTE: never missing (every end tile walks back to the enemy, which reaches the foe);
		# an end tile with no route could gain one of any length.
		if not left.has(tile):
			footprint.is_whole = true
			return
		bounds[tile] = left[tile]
	footprint.reads_routes(target_tile, span.y, bounds)


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
# tile, target or not; the others rate each option's subject (_rule_subject).
static func _rate_target_rule(board: Board, options: Array[EnemyPlan]) -> void:
	if board.rule == ContentIds.TARGET_MOST_ALLIES_NEAR:
		for plan: EnemyPlan in options:
			plan.target_rule_key = -_allies_near(board, plan.tile)
		return
	var subjects: Dictionary[EnemyPlan, String] = {}
	var nearest: Dictionary[String, int] = {}
	for plan: EnemyPlan in options:
		var subject: String = _rule_subject(board, plan)
		if subject.is_empty():
			continue
		subjects[plan] = subject
		if not nearest.has(subject) or plan.path_cost < nearest[subject]:
			nearest[subject] = plan.path_cost
	if board.footprint != null:
		# Each rule reads its subject's state; the Hexer's also counts the foes around it.
		var around: int = 0
		if board.rule == ContentIds.TARGET_MOST_CURSED:
			around = HEX_STORM_TILES
		for subject: String in nearest:
			board.footprint.reads_unit(board.state.tile_of(subject), around)
	for plan: EnemyPlan in subjects:
		var subject: String = subjects[plan]
		var hp: int = board.state.get_hp(subject)
		match board.rule:
			# Holding its ground, the Duelist and the Shieldbearer take the foe they reach with
			# the least movement, as the nearest foe.
			ContentIds.TARGET_NEAREST_FOE, ContentIds.TARGET_HOLDS_GROUND, \
					ContentIds.TARGET_BACK_LINE_ALLY:
				plan.target_rule_key = nearest[subject]
			ContentIds.TARGET_EXPOSED_THEN_LOWEST_HP:
				var is_exposed: bool = board.state.get_stance(subject) == 0
				plan.target_rule_key = hp + (0.0 if is_exposed else _UNEXPOSED_RANK)
			ContentIds.TARGET_PACK_LOWEST_HP:
				plan.target_rule_key = hp
			ContentIds.TARGET_MOST_CURSED:
				plan.target_rule_key = -_cursed_foes(board, subject)
			ContentIds.TARGET_BACK_LINE_FOES:
				var is_back_line: bool = _is_back_line_foe(board.engine, subject)
				plan.target_rule_key = 0.0 if is_back_line else 1.0
			ContentIds.TARGET_LOWEST_DEFENSE:
				# The target's DEF stat as its unit panel shows it, without its terrain.
				plan.target_rule_key = board.engine.stats(subject).get_int(CombatValue.Key.DEF)
			ContentIds.TARGET_MOST_WOUNDED_ALLY:
				var max_hp: int = board.engine.stats(subject).get_int(CombatValue.Key.HP)
				plan.target_rule_key = -(max_hp - board.state.get_hp(subject))


# The unit the target rule measures for plan: its target; for a powder keg it blows, the first
# player unit the blast defeats, in state order; empty for an object use and a plan with no target.
static func _rule_subject(board: Board, plan: EnemyPlan) -> String:
	if plan.target_id.is_empty():
		return ""
	if plan.kind == EnemyPlan.Kind.LOOT or plan.kind == EnemyPlan.Kind.USE_OBJECT:
		return ""
	if board.state.side_of(plan.target_id) != CombatFact.CombatSide.NONE:
		return plan.target_id
	if plan.forecast != null:
		for outcome: CombatForecast.UnitOutcome in plan.forecast.units:
			var side: CombatFact.CombatSide = board.state.side_of(outcome.unit_id)
			if outcome.is_defeated and side == CombatFact.CombatSide.PLAYER:
				return outcome.unit_id
	return ""


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
		if board.footprint != null:
			board.footprint.reads_threats = true
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
			if board.footprint != null:
				board.footprint.reads_threat(
						foe,
						foe_unit.tile,
						board.engine.stats(foe).get_int(CombatValue.Key.MOVEMENT),
						span
				)
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



# What the same goal means for the dry rule: the same kind of action, on the same target, with the
# same kill.
static func _goal_of(plan: EnemyPlan) -> String:
	return "%d %s %s" % [plan.kind, plan.target_id, plan.is_kill]


# Whether any of tiles is beside tile (grid distance 1).
static func _is_beside_any(tile: Vector2i, tiles: Dictionary[Vector2i, int]) -> bool:
	for other: Vector2i in tiles:
		if absi(other.x - tile.x) + absi(other.y - tile.y) == 1:
			return true
	return false


# Whether held attacks: any weapon but a Block or heal staff.
static func _attacks_with(held: CombatState.WeaponStats) -> bool:
	return not held.is_staff() or held.staff == CombatState.WeaponStats.Staff.ATTACK


# unit_id's range now, as (shortest, longest), with the weapon in hand.
static func _range_of(engine: EffectEngine, unit_id: String) -> Vector2i:
	return ExchangeResolver.weapon_range(
			engine, unit_id, engine.state.equipped_weapon_id(unit_id)
	)


# The range an advance closes to: the weapon in hand's when it attacks, else the stowed one's.
static func _advance_range(board: Board) -> Vector2i:
	var holder: CombatUnitState = board.state.unit(board.unit_id)
	var held: CombatState.WeaponStats = board.state.weapon(holder.equipped_weapon_id)
	if held != null and _attacks_with(held):
		return _range_of(board.engine, board.unit_id)
	var stowed: CombatState.WeaponStats = board.state.weapon(holder.stowed_weapon_id)
	if stowed != null and _attacks_with(stowed):
		return ExchangeResolver.weapon_range(board.engine, board.unit_id, stowed.id)
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
	## The tiles the player side must reach ([method EnemyAI.objective_tiles]); empty for none.
	var objective: Array[Vector2i] = []
	## The least path cost any player unit has to [member objective] on this board; -1 until the
	## first lever asks.
	var objective_cost: int = -1
	## The attack forecasts its decision may reuse ([method EnemyAI.decide]); null for none.
	var forecasts: Forecasts = null
	## What its decision reads, recorded as it reads it ([method EnemyAI.decide]); null for none.
	var footprint: Footprint = null

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

	## Every tile it can walk through this turn with the cost to get there, its paths' flood;
	## shared, not copied.
	func walked_tiles() -> Dictionary[Vector2i, int]:
		return _walked


## What one decision ([method EnemyAI.decide]) read of the board, so a move preview can tell
## which tiles a moved unit must touch to change it (move-preview.md, layer 3). A tile can change
## it when a reading below covers it, by terrain-free distance: every step costs at least 1, so a
## route never costs less. Units' own reads widen by the effect margin, which an effect reading
## positions can reach; occupancy and routes read only who stands where. Player units' threat
## counts compare their stats instead ([method threat_changed]). Built on one thread, then only
## read: [Intents] shares it across threads with its decision.
## @tutorial(The move preview): docs/design/move-preview.md
class Footprint:
	extends RefCounted

	## Whether any move can change it: a lever's seal, or a route of any length opening.
	var is_whole: bool = false
	## Whether it counts the player units that could attack its end tiles ([method threat_changed]).
	var reads_threats: bool = false

	# The deciding enemy's tile, its walk (shared with its board), its end tiles, and how far from a
	# walked tile it reads units: at least 1, since a unit beside the walk can block it.
	var _origin: Vector2i = CombatFact.NO_TILE
	var _walked: Dictionary[Vector2i, int] = {}
	var _reach: Dictionary[Vector2i, int] = {}
	var _walk_reads: int = 1
	# The farthest walked tile from _origin, so a far tile skips the walk.
	var _extent: int = 0
	# (x, y, radius): units it reads within radius, widened by the margin; occupants it counts
	# within radius, not widened.
	var _units: Array[Vector3i] = []
	var _occupants: Array[Vector3i] = []
	# Routes from each end tile to the stand tiles within _route_span of _route_goal, each at most
	# its bound: a tile on one, or freeing a cheaper one, changes it.
	var _route_goal: Vector2i = CombatFact.NO_TILE
	var _route_span: int = 0
	var _route_bounds: Dictionary[Vector2i, int] = {}
	# A whole-map flood, any tile within _far_reach of which can change it.
	var _far: Dictionary[Vector2i, int] = {}
	var _far_reach: int = 0
	# The player units counted as threats: id, tile, MOVEMENT and range then.
	var _threat_ids: PackedStringArray = []
	var _threat_tiles: Array[Vector2i] = []
	var _threat_moves: PackedInt32Array = []
	var _threat_spans: Array[Vector2i] = []

	## Starts on [param board]: its enemy's tile, walk and end tiles.
	func begin(board: Board) -> void:
		_origin = board.origin
		_walked = board.walked_tiles()
		_reach = board.reach
		for tile: Vector2i in _walked:
			_extent = maxi(_extent, absi(tile.x - _origin.x) + absi(tile.y - _origin.y))

	## Reads units within [param tiles] of every walked tile: its targets, or a staff's allies.
	func reads_around_walk(tiles: int) -> void:
		_walk_reads = maxi(_walk_reads, tiles)

	## Reads the state of the unit on [param tile], and counts the units within [param around].
	func reads_unit(tile: Vector2i, around: int) -> void:
		_units.append(Vector3i(tile.x, tile.y, around))

	## Counts who stands within [param tiles] of [param tile].
	func reads_occupants(tile: Vector2i, tiles: int) -> void:
		_occupants.append(Vector3i(tile.x, tile.y, tiles))

	## Reads routes from each end tile in [param bounds] to the stand tiles within [param span] of
	## [param goal], none costing more than its bound. A second set makes it whole.
	func reads_routes(goal: Vector2i, span: int, bounds: Dictionary[Vector2i, int]) -> void:
		if not _route_bounds.is_empty():
			is_whole = true
			return
		_route_goal = goal
		_route_span = span
		_route_bounds = bounds

	## Reads [param flood], a whole-map walk, and the units within [param tiles] of it.
	func reads_far(flood: Dictionary[Vector2i, int], tiles: int) -> void:
		_far = flood
		_far_reach = tiles

	## Counts player unit [param unit_id] on [param tile] as a threat, with its [param movement]
	## and range [param span] (shortest, longest) as it read them.
	func reads_threat(unit_id: String, tile: Vector2i, movement: int, span: Vector2i) -> void:
		_threat_ids.append(unit_id)
		_threat_tiles.append(tile)
		_threat_moves.append(movement)
		_threat_spans.append(span)

	## Whether a unit entering, leaving or changing on [param tile] can change the decision, with
	## [param margin] the effect margin. Threat counts aside ([method threat_changed]).
	func can_change(tile: Vector2i, margin: int) -> bool:
		if is_whole:
			return true
		var walk_reads: int = _walk_reads + margin
		if _distance(_origin, tile) <= _extent + walk_reads:
			for walked: Vector2i in _walked:
				if _distance(walked, tile) <= walk_reads:
					return true
		for read: Vector3i in _units:
			if _distance(Vector2i(read.x, read.y), tile) <= read.z + margin:
				return true
		for read: Vector3i in _occupants:
			if _distance(Vector2i(read.x, read.y), tile) <= read.z:
				return true
		if not _route_bounds.is_empty():
			var past: int = maxi(0, _distance(tile, _route_goal) - _route_span)
			for end: Vector2i in _route_bounds:
				if _distance(end, tile) + past <= _route_bounds[end]:
					return true
		for far: Vector2i in _far:
			if _distance(far, tile) <= _far_reach:
				return true
		return false

	## Whether the threat counts of its end tiles can differ on [param engine], the board it was
	## made for with [param moved_id] moved off or onto [param tiles] (Godot_FE's absolute range):
	## a player unit's MOVEMENT or range changed, or an end tile lies within the moved unit's
	## movement plus range of where it stood or stands, or within another's range of a tile it can
	## now end on or no longer can. Without [param engine], whether it counts threats at all.
	func threat_changed(engine: EffectEngine, tiles: Array[Vector2i], moved_id: String) -> bool:
		if not reads_threats:
			return false
		if engine == null:
			return true
		var state: CombatState = engine.state
		var others: int = -1
		var was: int = -1
		var was_on: Vector2i = CombatFact.NO_TILE
		for index: int in _threat_ids.size():
			var unit_id: String = _threat_ids[index]
			var span: Vector2i = _threat_spans[index]
			if unit_id == moved_id:
				was = _threat_moves[index] + span.y
				was_on = _threat_tiles[index]
				continue
			others = maxi(others, span.y)
			if not state.has_unit(unit_id):
				return true
			var held: CombatState.WeaponStats = state.equipped_weapon(unit_id)
			if held == null or not EnemyAI._attacks_with(held):
				return true
			if engine.stats(unit_id).get_int(CombatValue.Key.MOVEMENT) != _threat_moves[index]:
				return true
			if EnemyAI._range_of(engine, unit_id) != span:
				return true
		for unit_id: String in state.units_of(CombatFact.CombatSide.PLAYER):
			var held: CombatState.WeaponStats = state.equipped_weapon(unit_id)
			var attacks: bool = held != null and EnemyAI._attacks_with(held)
			if attacks and unit_id != moved_id and not _threat_ids.has(unit_id):
				return true
		var now: int = -1
		var now_on: Vector2i = CombatFact.NO_TILE
		if state.has_unit(moved_id):
			now_on = state.tile_of(moved_id)
			var held: CombatState.WeaponStats = state.equipped_weapon(moved_id)
			if held != null and EnemyAI._attacks_with(held):
				now = (
						engine.stats(moved_id).get_int(CombatValue.Key.MOVEMENT)
						+ EnemyAI._range_of(engine, moved_id).y
				)
		for tile: Vector2i in tiles:
			var reach: int = others
			if tile == was_on:
				reach = maxi(reach, was)
			if tile == now_on:
				reach = maxi(reach, now)
			if reach < 0:
				continue
			for end: Vector2i in _reach:
				if _distance(end, tile) <= reach:
					return true
		return false

	static func _distance(a: Vector2i, b: Vector2i) -> int:
		return absi(a.x - b.x) + absi(a.y - b.y)


## Attack forecasts one computation of the intents made, for its later steps and every preview
## built on those intents to reuse (move-preview.md, layer 2), each under the key [Forecasts]
## builds. The computation fills it; a preview keeps its own in an overlay and adds them when it
## ends, the oldest previews' dropped first past [member limit], since a hover's neighbours share
## most forecasts (a forecast holds about 37 KB in debug). Every board that reads it starts from
## the same session state: [Intents] drops it with those intents. Safe on any thread: a lock
## guards every read and write.
class ForecastStore:
	extends RefCounted

	## The most forecasts previews' additions keep; the computation's are always kept.
	## [b]0:[/b] previews add nothing.
	var limit: int = 0

	var _lock: Mutex = Mutex.new()
	var _entries: Dictionary[String, CombatForecast.ExchangeForecast] = {}
	# The keys previews added, oldest first from _first_added; the earlier ones are dropped.
	var _added: PackedStringArray = []
	var _first_added: int = 0
	# Each signature text a kept key names, by a short number, so keys stay small.
	var _numbers: Dictionary[String, int] = {}
	# Whether each effect definition reads past any positional reach (_reads_whole_board).
	var _whole: Dictionary[EffectDefinition, bool] = {}

	func _init(most: int = 0) -> void:
		limit = most

	## The forecasts kept.
	func size() -> int:
		_lock.lock()
		var count: int = _entries.size()
		_lock.unlock()
		return count

	## Keeps each of [param overlay]'s forecasts by its key, as a preview ends, dropping the
	## oldest kept by previews while more than [member limit] are.
	func keep_all(overlay: Dictionary[String, CombatForecast.ExchangeForecast]) -> void:
		if limit <= 0:
			return
		_lock.lock()
		for key: String in overlay:
			if _entries.has(key):
				continue
			_entries[key] = overlay[key]
			_added.append(key)
		while _added.size() - _first_added > limit:
			_entries.erase(_added[_first_added])
			_first_added += 1
		# Compacts the dropped keys away once they are most of the list.
		if _first_added > limit:
			_added = _added.slice(_first_added)
			_first_added = 0
		_lock.unlock()

	## The forecast kept under [param key]; null when none is.
	func find(key: String) -> CombatForecast.ExchangeForecast:
		_lock.lock()
		var found: CombatForecast.ExchangeForecast = _entries.get(key, null)
		_lock.unlock()
		return found

	## Keeps [param forecast] under [param key]. Kept forecasts are shared by every plan that
	## reuses them, so nothing may change one; their facts keep the seq of the board that made
	## them, which no plan or intent reads.
	func keep(key: String, forecast: CombatForecast.ExchangeForecast) -> void:
		_lock.lock()
		_entries[key] = forecast
		_lock.unlock()

	## The short number standing for [param signature], the same for equal texts, from 0 up.
	## Unknown: a new number when [param may_add], else -1.
	func number_of(signature: String, may_add: bool) -> int:
		_lock.lock()
		var number: int = _numbers.get(signature, -1)
		if number < 0 and may_add:
			number = _numbers.size()
			_numbers[signature] = number
		_lock.unlock()
		return number

	## Whether [param definition] can change an exchange anywhere on the map, whoever it belongs
	## to: it fires outside the phase triggers and selects a whole scope, runs a custom script (a
	## keg's blast, counted in the margin, aside) or tests "no ally closer".
	func reads_whole_board(definition: EffectDefinition) -> bool:
		_lock.lock()
		var known: bool = _whole.has(definition)
		var whole: bool = _whole.get(definition, false)
		_lock.unlock()
		if known:
			return whole
		var phase_only: bool = (
				definition.trigger == EffectTerms.Trigger.PHASE_START
				or definition.trigger == EffectTerms.Trigger.PHASE_END
		)
		whole = not phase_only and _reads_whole(definition)
		_lock.lock()
		_whole[definition] = whole
		_lock.unlock()
		return whole

	# Whether block, or any resource it stores, reads past a positional reach.
	static func _reads_whole(block: Object) -> bool:
		if block is AllOfScope and not (block as AllOfScope).is_owner():
			return true
		if block is CustomOperation and not block is KegExplosion:
			return true
		if block is WhilePositionCondition:
			var position: WhilePositionCondition = block
			if position.kind == WhilePositionCondition.Kind.NO_ALLY_CLOSER_TO_ENEMY:
				return true
		for property: Dictionary in block.get_property_list():
			var usage: int = property["usage"]
			var kind: int = property["type"]
			if usage & PROPERTY_USAGE_STORAGE == 0 or (kind != TYPE_OBJECT and kind != TYPE_ARRAY):
				continue
			var property_name: StringName = property["name"]
			var value: Variant = block.get(property_name)
			var children: Array = value if value is Array else [value]
			for child: Variant in children:
				if child is Resource and not child is Script and _reads_whole(child as Resource):
					return true
		return false


## One play of the enemy phase's view of a [ForecastStore] ([method EnemyAI.decide]): an attack
## forecast is reused when its key matches. The key holds the option (attacker, weapon, path,
## target), the effect margin, each unit on the path or within the margin of the attacker's tile,
## its end tile and the target's tile with its signature, and what the whole board shares (the
## turn, the darkness, map objects, army effects). A signature is a unit's whole state, its
## effects' counters and charges, its timed modifiers and its stat changes. The filling view adds
## what it makes to the store; any other keeps it in its own overlay, dropped with the view. Use
## one per board timeline, on one thread.
## @tutorial(The move preview): docs/design/move-preview.md
class Forecasts:
	extends RefCounted

	## Forecasts reused (from the store or the overlay), and made afresh, through this view.
	var reused: int = 0
	var made: int = 0
	## Reused forecasts made afresh again by checking mode and compared.
	var checked: int = 0
	## For each reused forecast that differs from a fresh one, in checking mode: what was kept and
	## what a fresh one gives.
	var mismatches: PackedStringArray = []

	var _store: ForecastStore = null
	var _margin: int = 0
	var _is_checking: bool = false
	var _fills_store: bool = false
	# What this view made, when it doesn't fill the store; and the numbers of signatures the store
	# doesn't know, below 0 so they never match a kept key.
	var _overlay: Dictionary[String, CombatForecast.ExchangeForecast] = {}
	var _local_numbers: Dictionary[String, int] = {}
	# The board the signatures below were read from: its engine and fact count. Rules code records
	# a fact for every change, so a board with the same count is unchanged.
	var _engine: EffectEngine = null
	var _facts: int = -1
	# Each unit's signature number and tile, in state order; the whole board's signature number;
	# whether an effect reads the whole board, so every key holds every unit.
	var _units: Dictionary[String, int] = {}
	var _tiles: Dictionary[String, Vector2i] = {}
	var _shared: int = -1
	var _is_whole: bool = false

	## [param margin]: the board's effect margin ([method Intents.preview]); below 0, an effect
	## reads the whole map and nothing is reused. [param is_checking]: make each reused forecast
	## afresh too and list a difference in [member mismatches]. [param fills_store]: add what it
	## makes to [param store], for one computation of the intents only; otherwise to the overlay.
	func _init(
			store: ForecastStore,
			margin: int,
			is_checking: bool = false,
			fills_store: bool = false
	) -> void:
		_store = store
		_margin = margin
		_is_checking = is_checking
		_fills_store = fills_store

	## [param command]'s attack forecast on [param engine]'s board, as
	## [method CombatForecast.exchange] makes it with [ForecastRolls] and no breakdowns: kept from
	## the overlay or the store when its key matches, else made and kept.
	func exchange(
			engine: EffectEngine, command: UnitTurnCommand
	) -> CombatForecast.ExchangeForecast:
		if _store == null or _margin < 0:
			made += 1
			return CombatForecast.exchange(engine, command, ForecastRolls.new(), false)
		_read(engine)
		var key: String = _key_of(command)
		var kept: CombatForecast.ExchangeForecast = _overlay.get(key, null)
		if kept == null:
			kept = _store.find(key)
		if kept == null:
			kept = CombatForecast.exchange(engine, command, ForecastRolls.new(), false)
			if _fills_store:
				_store.keep(key, kept)
			else:
				_overlay[key] = kept
			made += 1
			return kept
		reused += 1
		if _is_checking:
			checked += 1
			var fresh: CombatForecast.ExchangeForecast = CombatForecast.exchange(
					engine, command, ForecastRolls.new(), false
			)
			var was: String = Forecasts.text_of(kept)
			var now: String = Forecasts.text_of(fresh)
			if was != now:
				mismatches.append("%s on %s from %s kept [%s], a fresh one gives [%s]" % [
					command.actor_id, command.target_id, command.path, was, now,
				])
		return kept

	## Adds the overlay to the store, as a preview ends ([method ForecastStore.keep_all]).
	func add_overlay_to_store() -> void:
		if _store != null and not _overlay.is_empty():
			_store.keep_all(_overlay)

	# Reads every signature from engine's board unless it is the board last read.
	func _read(engine: EffectEngine) -> void:
		if engine == _engine and engine.fact_log.size() == _facts:
			return
		_engine = engine
		_facts = engine.fact_log.size()
		var state: CombatState = engine.state
		var parts: Dictionary[String, PackedStringArray] = {}
		_tiles.clear()
		for unit_id: String in state.unit_ids():
			parts[unit_id] = PackedStringArray([str(state.unit(unit_id).capture())])
			_tiles[unit_id] = state.tile_of(unit_id)
		var shared: PackedStringArray = [
			str(state.turn), str(state.phase_side), str(state.is_phase_ended),
			str(state.map.has_darkness_arrived), str(state.map.darkness.layers),
		]
		_is_whole = false
		for instance: EffectInstance in engine.get_instances():
			# An effect firing only at a phase boundary never fires in an exchange, and only its
			# own instance reads its counters and charges (CounterCondition, CounterValue).
			var trigger: int = instance.definition.trigger
			var is_phase_only: bool = (
					trigger == EffectTerms.Trigger.PHASE_START
					or trigger == EffectTerms.Trigger.PHASE_END
			)
			if is_phase_only:
				continue
			var holder: String = instance.owner.holder_id
			var text: String = "%s %d %d %d" % [
				instance.instance_id, instance.charges_left,
				instance.get_counter(EffectTerms.Lane.COMBAT),
				instance.get_counter(EffectTerms.Lane.CAMPAIGN),
			]
			if parts.has(holder):
				parts[holder].append(text)
			else:
				shared.append(text)
			if _is_whole or engine.is_dormant(instance):
				continue
			# A unit's effect reaching other units by scope (an aura) reads its holder anywhere.
			var is_aura: bool = (
					parts.has(holder) and instance.definition.scope != EffectTerms.Scope.THIS_UNIT
			)
			_is_whole = is_aura or _store.reads_whole_board(instance.definition)
		for unit_id: String in parts:
			for timed: TimedModifier in engine.get_timed_modifiers(unit_id):
				parts[unit_id].append(str(timed.capture()))
		for fact: CombatFact in engine.fact_log:
			if fact.kind == CombatFact.Kind.STAT_CHANGED and parts.has(fact.actor_id):
				parts[fact.actor_id].append("stat %d %d %s" % [
					fact.key, fact.amount, fact.source_effect_id,
				])
		var object_ids: Array[String] = []
		object_ids.assign(state.map.objects.keys())
		object_ids.sort()
		for object_id: String in object_ids:
			var spot: MapState.ObjectState = state.map.objects[object_id]
			shared.append("%s %s %s %s %s %s %s %d" % [
				spot.id, spot.tile, spot.is_open, spot.is_lit, spot.is_used, spot.is_destroyed,
				spot.is_thrown, spot.fuse,
			])
		_shared = _number_of(" ".join(shared))
		_units.clear()
		for unit_id: String in parts:
			_units[unit_id] = _number_of(" ".join(parts[unit_id]))

	# The store's number for signature, added when the store keeps anything of this view's.
	# Otherwise one of this view's own, below 0, which never matches a kept key.
	func _number_of(signature: String) -> int:
		var number: int = _store.number_of(signature, _fills_store or _store.limit > 0)
		if number >= 0:
			return number
		if not _local_numbers.has(signature):
			_local_numbers[signature] = -1 - _local_numbers.size()
		return _local_numbers[signature]

	# The key of command's forecast on the board last read: every unit within the margin of the
	# attacker's tile (its movement), its end tile and the target's tile (the exchange), and every
	# unit on its path. NOTE: the walk reads only the path's own tiles and records a move that
	# fires nothing before the unit acts (EffectEngine's trigger of a move, Pathing.check_path).
	func _key_of(command: UnitTurnCommand) -> String:
		var actor: String = command.actor_id
		var target: String = command.target_id
		var origin: Vector2i = _tiles.get(actor, CombatFact.NO_TILE)
		var path: Array[Vector2i] = command.path
		var anchors: Array[Vector2i] = [
			origin,
			origin if path.is_empty() else path[path.size() - 1],
			_tiles.get(target, CombatFact.NO_TILE),
		]
		var parts: PackedStringArray = [
			actor, command.weapon_id, str(path), target, str(_margin), str(_shared),
		]
		for unit_id: String in _units:
			var is_read: bool = (
					_is_whole
					or unit_id == actor
					or unit_id == target
					or path.has(_tiles[unit_id])
					or _is_near(_tiles[unit_id], anchors)
			)
			if is_read:
				parts.append("%s=%d" % [unit_id, _units[unit_id]])
		return "|".join(parts)

	# Whether tile lies within the margin of any of anchors, by grid distance.
	func _is_near(tile: Vector2i, anchors: Array[Vector2i]) -> bool:
		for anchor: Vector2i in anchors:
			if absi(tile.x - anchor.x) + absi(tile.y - anchor.y) <= _margin:
				return true
		return false

	## [param forecast] as one line holding everything a plan or an intent reads of it: legality,
	## every unit's outcome, every attack and every fact but its seq.
	static func text_of(forecast: CombatForecast.ExchangeForecast) -> String:
		var parts: PackedStringArray = [
			str(forecast.is_legal), forecast.reason, forecast.actor_id, forecast.target_id,
		]
		for outcome: CombatForecast.UnitOutcome in forecast.units:
			parts.append("%s %d>%d b%d>%d s%d>%d %s>%s %s" % [
				outcome.unit_id, outcome.hp_before, outcome.hp_after, outcome.block_before,
				outcome.block_after, outcome.stance_before, outcome.stance_after,
				outcome.tile_before, outcome.tile_after, outcome.is_defeated,
			])
		for attack: CombatForecast.AttackForecast in forecast.attacks:
			parts.append("%s>%s %d %s %s %d %d %d %d %s" % [
				attack.attacker_id, attack.defender_id, attack.hit, attack.hit_probability,
				attack.is_hit, attack.crit_chance, attack.damage, attack.hp_damage,
				attack.block_damage, attack.defeated,
			])
		for fact: CombatFact in forecast.facts:
			parts.append("%d %s %s %s %s %d %d" % [
				fact.kind, fact.actor_id, fact.target_id, fact.source_effect_id, fact.tile,
				fact.amount, fact.key,
			])
		return " ".join(parts)
