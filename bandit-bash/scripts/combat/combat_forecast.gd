# ==============================================================================
# Bandit Bash
# Copyright (c) 2026 Derc Development
# Licensed under the MIT License. See LICENSE.
#
# File:     combat_forecast.gd
# Author:
# Created:  October 28, 2026
# Modified: October 29, 2026
# ==============================================================================

class_name CombatForecast
extends RefCounted
## The player's forecast of an attack, a staff or a shove, and the AI's exchange summary, both by
## running the command's own resolver in a [Sandbox] (combat core plan, Forecast and AI summary).
##
## Each preview copies the engine, walks the [UnitTurnCommand]'s path
## ([method UnitTurnCommand.walk_path]) and resolves its action with [ExchangeResolver],
## [StaffResolver] or [ShoveResolver], as the command does when it resolves, so with the same rolls
## the preview's facts are the executed facts. Nothing leaves the sandbox. The player's preview
## rolls with [ForecastRolls] (hits land, chances fail, every probability kept); each chance it
## failed is listed as a [ChanceLine]: the same preview with that chance passing. A context
## observer on the sandbox ([method EffectEngine.add_context_observer]) reads each attack as it
## resolves: its rolls, its damage and, from the hit's own context, a [HitBreakdown] of its stages.
## The AI's summary runs the exchange once per [ForcedRolls] branch
## ([method outcome]) or [SampledRolls] sample ([method sampled_outcome]) into P01's
## [ExchangeOutcome]; the rating that weighs it is the AI plan's.[br]
## A preview checks what [method UnitTurnCommand.validate] checks about the unit, its path and its
## action, but not the phase, which needs a session. The sender copies
## [member Forecast.based_on_seq] into [member Command.based_on_seq].[br]
## Pure and static. Main thread: every preview creates sandboxes.
##
## @tutorial(Combat core plan): docs/plans/2026-10-26-combat-core.md


## The preview of [param command]'s attack ([constant UnitTurnCommand.Action.ATTACK]) on
## [param engine]'s map: the path, Sidearm's free swap when the command names the stowed weapon,
## then the exchange. [param rolls]: null for the player's preview ([ForecastRolls], with
## [ChanceLine]s); a [ForcedRolls] or [SampledRolls] resolves it with those rolls and lists no
## chances.
static func exchange(
		engine: EffectEngine, command: UnitTurnCommand, rolls: RollSource = null
) -> ExchangeForecast:
	var forecast: ExchangeForecast = _preview(
			engine, command, rolls, UnitTurnCommand.Action.ATTACK, true
	)
	return forecast


## The preview of [param command]'s Block or heal staff ([constant UnitTurnCommand.Action.STAFF]):
## the path, then the staff on its target, or on the user for a range-0 staff with no target named
## (question 14). [param rolls] as in [method exchange].
static func staff(
		engine: EffectEngine, command: UnitTurnCommand, rolls: RollSource = null
) -> StaffForecast:
	var forecast: StaffForecast = _preview(
			engine, command, rolls, UnitTurnCommand.Action.STAFF, true
	)
	return forecast


## The preview of [param command]'s shove ([constant UnitTurnCommand.Action.SHOVE]): the path, then
## the shove, its slide, bumps and spikes. [param rolls] as in [method exchange].
static func shove(
		engine: EffectEngine, command: UnitTurnCommand, rolls: RollSource = null
) -> ShoveForecast:
	var forecast: ShoveForecast = _preview(
			engine, command, rolls, UnitTurnCommand.Action.SHOVE, true
	)
	return forecast


## One branch of [param command]'s exchange through [param rolls]: what P01's [ExchangeOutcome]
## records of it. Null when the attack isn't legal. Breakdowns are skipped, so it costs only the
## sandbox and the exchange.
static func branch(
		engine: EffectEngine, command: UnitTurnCommand, rolls: RollSource
) -> ExchangeOutcome.Branch:
	var forecast: ExchangeForecast = _preview(
			engine, command, rolls, UnitTurnCommand.Action.ATTACK, false
	)
	return forecast.to_branch() if forecast.is_legal else null


## The AI's summary of [param command]'s exchange by exact enumeration: one [method branch] per
## [ForcedRolls] sequence, up to [param max_branches] runs ([method ExchangeOutcome.enumerate]).
## An illegal attack gives an outcome with no branches and a total probability of 0.
static func outcome(
		engine: EffectEngine, command: UnitTurnCommand, max_branches: int
) -> ExchangeOutcome:
	var resolve: Callable = func(rolls: ForcedRolls) -> ExchangeOutcome.Branch:
		return branch(engine, command, rolls)
	return ExchangeOutcome.enumerate(resolve, max_branches)


## The AI's summary of [param command]'s exchange by sampling, for a candidate with too many
## branches: [param samples] runs, each with [SampledRolls] seeded by [param session_seq] and the
## candidate (unit, the path's last tile, target, weapon, sample number), each weighing
## 1 / [param samples]. An estimate, so [member ExchangeOutcome.complete] is false; its total
## probability is 1. An illegal attack, or fewer than one sample, gives an empty outcome.
static func sampled_outcome(
		engine: EffectEngine, command: UnitTurnCommand, session_seq: int, samples: int
) -> ExchangeOutcome:
	var branches: Array[ExchangeOutcome.Branch] = []
	var candidate: Array = _candidate(engine, command)
	for sample: int in maxi(samples, 0):
		var parts: Array = candidate.duplicate()
		# Samples of one candidate are told apart by their number, appended to the candidate's
		# parts; the seed's other parts are P01's (unit, tile, target, weapon).
		parts.append(sample)
		var rolls: SampledRolls = SampledRolls.new(session_seq, parts)
		var sampled: ExchangeOutcome.Branch = branch(engine, command, rolls)
		if sampled == null:
			branches.clear()
			break
		sampled.probability = 1.0 / samples
		for record: RollRecord in rolls.records:
			sampled.outcomes.append(record.outcome)
		branches.append(sampled)
	var summary: ExchangeOutcome = ExchangeOutcome.from_branches(branches)
	summary.complete = false
	return summary


# Runs the preview of action on a sandbox of engine with rolls (ForecastRolls when null, and then
# the chance lines too). explain: whether each hit gets a HitBreakdown.
static func _preview(
		engine: EffectEngine,
		command: UnitTurnCommand,
		rolls: RollSource,
		action: UnitTurnCommand.Action,
		explain: bool
) -> Forecast:
	var forecast: Forecast = _new_forecast(action)
	if command.action != action:
		forecast.reason = "the command's action isn't %s" % [
			(UnitTurnCommand.Action.find_key(action) as String).to_lower(),
		]
		return forecast
	var source: RollSource = rolls if rolls != null else ForecastRolls.new()
	_simulate(Sandbox.new(engine, source), command, forecast, explain)
	if rolls == null and forecast.is_legal:
		_list_chances(engine, command, forecast)
	return forecast


# Walks the command's path and resolves its action on sandbox, filling forecast.
static func _simulate(
		sandbox: Sandbox, command: UnitTurnCommand, forecast: Forecast, explain: bool
) -> void:
	var engine: EffectEngine = sandbox.engine
	var state: CombatState = engine.state
	forecast.actor_id = command.actor_id
	forecast.target_id = command.target_id
	var before: Dictionary[String, UnitOutcome] = {}
	for unit_id: String in state.unit_ids():
		before[unit_id] = UnitOutcome.before(state, unit_id)
	var recorder: Recorder = Recorder.new(engine, command.actor_id, command.target_id, explain)
	engine.add_context_observer(recorder.observe)

	engine.begin_step()
	var reason: String = _walk(engine, state, command)
	if reason.is_empty():
		match command.action:
			UnitTurnCommand.Action.ATTACK:
				reason = _attack(engine, state, command)
			UnitTurnCommand.Action.STAFF:
				reason = _use_staff(engine, state, command, forecast as StaffForecast)
			UnitTurnCommand.Action.SHOVE:
				var result: ShoveResolver.Result = ShoveResolver.resolve(
						engine, state, command.actor_id, command.target_id
				)
				reason = result.reason
				(forecast as ShoveForecast).path = result.path
	engine.drain()

	forecast.reason = reason
	forecast.is_legal = reason.is_empty()
	forecast.facts = sandbox.facts()
	forecast.rolls = sandbox.roll_records()
	forecast.diagnostics = engine.diagnostics
	if not forecast.facts.is_empty():
		forecast.based_on_seq = forecast.facts[0].seq - 1
	for record: RollRecord in forecast.rolls:
		forecast.has_random_pick = forecast.has_random_pick or record.is_placeholder
	for unit_id: String in before:
		var outcome_of: UnitOutcome = before[unit_id]
		outcome_of.finish(state)
		var is_named: bool = unit_id == forecast.actor_id or unit_id == forecast.target_id
		if outcome_of.is_changed() or is_named:
			forecast.units.append(outcome_of)
	if forecast is ExchangeForecast:
		(forecast as ExchangeForecast).fill(recorder)
	elif forecast is StaffForecast:
		(forecast as StaffForecast).fill()


# Why the unit can't walk the command's path now; empty when it can, after walking it.
static func _walk(engine: EffectEngine, state: CombatState, command: UnitTurnCommand) -> String:
	var actor: String = command.actor_id
	if not state.has_unit(actor):
		return "%s isn't on the map" % [actor]
	var unit: CombatUnitState = state.unit(actor)
	if unit.has_acted:
		return "%s has acted" % [actor]
	var check: CombatGrid.PathCheck = UnitTurnCommand.walk_path(engine, state, actor, command.path)
	return "" if check.is_legal else "path: %s" % [check.reason]


# The attack from the path's end: Sidearm's free swap first when the command names the stowed
# weapon, then the exchange, as UnitTurnCommand resolves it.
static func _attack(engine: EffectEngine, state: CombatState, command: UnitTurnCommand) -> String:
	var actor: String = command.actor_id
	if command.target_id.is_empty() or command.target_id == actor:
		return "an attack needs a target at range 1 or more"
	var unit: CombatUnitState = state.unit(actor)
	if not command.weapon_id.is_empty() and command.weapon_id != unit.equipped_weapon_id:
		if command.weapon_id != unit.stowed_weapon_id:
			return "%s doesn't hold %s" % [actor, command.weapon_id]
		var swap_reason: String = WeaponSwap.resolve(engine, state, actor, true)
		if not swap_reason.is_empty():
			return swap_reason
	return ExchangeResolver.resolve(engine, state, actor, command.target_id).reason


# The staff from the path's end, on the target named or, for a range-0 staff, on the user.
static func _use_staff(
		engine: EffectEngine, state: CombatState, command: UnitTurnCommand, forecast: StaffForecast
) -> String:
	var actor: String = command.actor_id
	var target: String = command.target_id
	if target.is_empty():
		if engine.stats(actor).get_int(CombatValue.Key.RANGE_MAX) != 0:
			return "the staff needs a target"
		target = actor
	forecast.target_id = target
	var held: CombatState.WeaponStats = state.equipped_weapon(actor)
	if held != null:
		forecast.kind = held.staff
	forecast.amount = StaffResolver.staff_amount(engine, actor)
	return StaffResolver.resolve(engine, state, actor, target).reason


# One ChanceLine per percent roll the preview failed that isn't a crit roll: the same preview with
# every roll before it as it was and that one passing. Lines that change nothing are kept.
static func _list_chances(
		engine: EffectEngine, command: UnitTurnCommand, forecast: Forecast
) -> void:
	var crit_rolls: PackedInt32Array = []
	if forecast is ExchangeForecast:
		for attack: AttackForecast in (forecast as ExchangeForecast).attacks:
			crit_rolls.append(attack.crit_roll)
	for i: int in forecast.rolls.size():
		var record: RollRecord = forecast.rolls[i]
		if record.kind != RollRecord.Kind.PERCENT or record.succeeded():
			continue
		if record.probability <= 0.0 or crit_rolls.has(i):
			continue
		var outcomes: PackedInt32Array = []
		for j: int in i:
			outcomes.append(forecast.rolls[j].outcome)
		outcomes.append(1)
		var what_if: Forecast = _new_forecast(command.action)
		_simulate(Sandbox.new(engine, WhatIfRolls.new(outcomes)), command, what_if, true)
		forecast.chances.append(ChanceLine.new(record.value, i, forecast, what_if))


# The candidate parts SampledRolls seeds from: unit, the path's last tile, target and weapon.
static func _candidate(engine: EffectEngine, command: UnitTurnCommand) -> Array:
	var state: CombatState = engine.state
	var tile: Vector2i = state.tile_of(command.actor_id)
	if not command.path.is_empty():
		tile = command.path[command.path.size() - 1]
	var weapon_id: String = command.weapon_id
	if weapon_id.is_empty():
		weapon_id = state.equipped_weapon_id(command.actor_id)
	return [command.actor_id, tile, command.target_id, weapon_id]


static func _new_forecast(action: UnitTurnCommand.Action) -> Forecast:
	match action:
		UnitTurnCommand.Action.ATTACK:
			return ExchangeForecast.new()
		UnitTurnCommand.Action.STAFF:
			return StaffForecast.new()
		UnitTurnCommand.Action.SHOVE:
			return ShoveForecast.new()
	return Forecast.new()


## What any preview found. [member is_legal] false: [member reason] says why, and the rest
## describes only what resolved before the check failed (a path walked, nothing else).
class Forecast:
	extends RefCounted

	## Whether the unit can take the action from the path's end now (the phase isn't checked).
	var is_legal: bool = false
	## Why it can't; empty when it can.
	var reason: String = ""
	## The unit acting.
	var actor_id: String = ""
	## The unit the action is aimed at: for a range-0 staff, the user.
	var target_id: String = ""
	## The session [member CombatFact.seq] the preview started from, for
	## [member Command.based_on_seq]; [constant Command.NO_SEQ] when it resolved nothing.
	var based_on_seq: int = Command.NO_SEQ
	## The actor, the target, and every other unit the action changes, in state order.
	var units: Array[UnitOutcome] = []
	## The facts the preview resolved, the walk's included, with the seq they would have.
	var facts: Array[CombatFact] = []
	## Every roll it made, with its displayed value and true probability.
	var rolls: Array[RollRecord] = []
	## Chance-gated effects left out of the totals ("25%: +X"), for the player's preview only.
	var chances: Array[ChanceLine] = []
	## Whether a random pick was made: the preview keeps the first candidate, so the display says
	## "a random ally" instead of naming it (event bus plan, question 35).
	var has_random_pick: bool = false
	## The sandbox's diagnostics, for the main thread to log.
	var diagnostics: PackedStringArray = []

	## The predicted state of [param unit_id] (in [member units]); null when the action leaves it
	## untouched and it is neither the actor nor the target.
	func unit(unit_id: String) -> UnitOutcome:
		for outcome_of: UnitOutcome in units:
			if outcome_of.unit_id == unit_id:
				return outcome_of
		return null


## An attack's preview: per side its numbers and predicted state, and each attack in order.
class ExchangeForecast:
	extends Forecast

	## The attacker's side.
	var attacker: SideForecast = SideForecast.new()
	## The defender's side.
	var defender: SideForecast = SideForecast.new()
	## Whether the defender can counter.
	var can_counter: bool = false
	## The units taking each turn, bonus turns included, whether or not all were reached.
	var turn_order: PackedStringArray = []
	## Every attack made, in order.
	var attacks: Array[AttackForecast] = []

	## Fills the sides and attacks from [param recorder] once the exchange has resolved.
	func fill(recorder: Recorder) -> void:
		attacks = recorder.attacks
		turn_order = recorder.turn_order
		can_counter = recorder.can_counter
		for side: SideForecast in [attacker, defender]:
			var own: SideForecast = recorder.sides.get(
					actor_id if side == attacker else target_id, null
			)
			if own != null:
				side.copy_from(own)
			side.unit_id = actor_id if side == attacker else target_id
			side.outcome = unit(side.unit_id)
			for attack: AttackForecast in attacks:
				if attack.attacker_id != side.unit_id:
					continue
				if side.hit_roll < 0:
					side.hit_roll = attack.hit_roll
					side.hit = attack.hit
					side.hit_probability = attack.hit_probability
				if attack.crit_roll >= 0 and side.crit_roll < 0:
					side.crit_roll = attack.crit_roll
					side.crit_chance = attack.crit_chance
				if attack.is_hit and side.damage < 0:
					side.damage = attack.damage
					side.breakdown = attack.breakdown

	## What P01's [ExchangeOutcome] records of this exchange, as one branch: damage each unit took
	## from the other (hits and splash it was credited with), defeats, and whether the defender
	## ends Exposed. The probability is set by the caller.
	func to_branch() -> ExchangeOutcome.Branch:
		var result: ExchangeOutcome.Branch = ExchangeOutcome.Branch.new()
		for fact: CombatFact in facts:
			if fact.kind != CombatFact.Kind.DAMAGE_TAKEN:
				continue
			if fact.actor_id == target_id and fact.target_id == actor_id:
				result.dealt_hp += fact.hp_amount
				result.dealt_block += fact.block_amount
			elif fact.actor_id == actor_id and fact.target_id == target_id:
				result.taken_hp += fact.hp_amount
				result.taken_block += fact.block_amount
		var attacker_state: UnitOutcome = unit(actor_id)
		var defender_state: UnitOutcome = unit(target_id)
		result.attacker_defeated = attacker_state != null and attacker_state.is_defeated
		result.defender_defeated = defender_state != null and defender_state.is_defeated
		result.defender_exposed = (
				defender_state != null
				and not defender_state.is_defeated
				and defender_state.stance_after == 0
		)
		result.diagnostics = diagnostics
		return result


## One side of an exchange: what the forecast panel shows for it.
class SideForecast:
	extends RefCounted

	## The unit.
	var unit_id: String = ""
	## The weapon it fights with, after a Sidearm swap: the forecast shows its exact profile
	## (game-vision.md, the triangle). Empty when it holds none.
	var weapon_id: String = ""
	## Its Hit against the other unit, as its first attack rolled it; for a unit that makes no
	## attack, as read when the exchange's first attack started. -1 when unknown.
	var hit: int = -1
	## The true 2RN probability of [member hit] ([method RollSource.hit_2rn_probability]).
	var hit_probability: float = 0.0
	## Its crit chance against the other unit once that unit is Exposed: rolled, or read like
	## [member hit]. -1 when unknown.
	var crit_chance: int = -1
	## Attacks it makes per turn: [code]max(1, AtkX - the other unit's Parry)[/code].
	var attacks_per_turn: int = 0
	## Its turns in the turn order, bonus turns included; 0 when it can't counter.
	var turns: int = 0
	## The damage of its first hit that landed, after stage 5; -1 when none landed.
	var damage: int = -1
	## That hit's stages; null when none landed.
	var breakdown: HitBreakdown = null
	## Its predicted HP, Block and Stance after the exchange.
	var outcome: UnitOutcome = null
	## Index in [member Forecast.rolls] of its first hit roll; -1 when it made no attack.
	var hit_roll: int = -1
	## Index in [member Forecast.rolls] of its first crit roll; -1 when it made none.
	var crit_roll: int = -1

	## Takes the numbers read when the exchange's first attack started from [param read].
	func copy_from(read: SideForecast) -> void:
		weapon_id = read.weapon_id
		hit = read.hit
		hit_probability = read.hit_probability
		crit_chance = read.crit_chance
		attacks_per_turn = read.attacks_per_turn
		turns = read.turns


## One attack of an exchange, as it resolved in the preview.
class AttackForecast:
	extends RefCounted

	## Its position in the exchange, from 0.
	var index: int = 0
	## The unit attacking.
	var attacker_id: String = ""
	## The unit attacked.
	var defender_id: String = ""
	## Its Hit, as rolled (0 to 100).
	var hit: int = 0
	## The true 2RN probability of [member hit].
	var hit_probability: float = 0.0
	## Index in [member Forecast.rolls] of its hit roll.
	var hit_roll: int = -1
	## Whether it hit.
	var is_hit: bool = false
	## Its crit chance, rolled because the defender was Exposed; -1 when not rolled.
	var crit_chance: int = -1
	## Index in [member Forecast.rolls] of its crit roll; -1 when not rolled.
	var crit_roll: int = -1
	## Whether it was a crit.
	var is_crit: bool = false
	## Its damage after stage 5; 0 for a miss or a fully countered hit.
	var damage: int = 0
	## The part of [member damage] that reached HP.
	var hp_damage: int = 0
	## The part of [member damage] that Block absorbed.
	var block_damage: int = 0
	## Whether it defeated the defender.
	var defeated: bool = false
	## Its stages; null for a miss, and in [method CombatForecast.branch].
	var breakdown: HitBreakdown = null


## A hit's damage stages, each source on its own line, as [DamagePipeline] computes them.
##
## Read with the hit's own context, so the "that hit" modifiers and flags of its inline windows
## show in the stages they change.
class HitBreakdown:
	extends RefCounted

	## Every stage's exact value and the damage ([method DamagePipeline.compute]).
	var stages: DamagePipeline.HitDamage = null
	## Stage 1's Attack value: weapon damage and every flat attack modifier.
	var attack: ValueBreakdown = null
	## Stage 1's Might, times the scaling modifier.
	var might: float = 0.0
	## Stage 1's triangle bonus or penalty.
	var triangle: float = 0.0
	## Stage 1's extra weapon damage from effectiveness; 0 when not effective.
	var effectiveness: float = 0.0
	## Stage 2; null when skipped (Pure damage, a skip-Mitigation crit).
	var mitigation: ValueBreakdown = null
	## Stage 3's multiplier; null without a crit.
	var critical: ValueBreakdown = null

	## One line per stage, such as
	## [code]attack 5 base = 5, +3 Might; mitigation 2 base = 2; multipliers ...; damage 6[/code].
	func to_text() -> String:
		var parts: PackedStringArray = []
		var first: String = "attack %s" % [attack.to_text()]
		if might != 0.0:
			first += ", %s Might" % [_signed(might)]
		if triangle != 0.0:
			first += ", %s triangle" % [_signed(triangle)]
		if effectiveness != 0.0:
			first += ", %s effective" % [_signed(effectiveness)]
		parts.append(first)
		if mitigation != null:
			parts.append("mitigation %s" % [mitigation.to_text()])
		if critical != null:
			parts.append("critical %s" % [critical.to_text()])
		parts.append(
				"multipliers %s × %s" % [stages.outgoing.to_text(), stages.incoming.to_text()]
		)
		parts.append("damage %d" % [stages.damage])
		return "; ".join(parts)

	## The stages of the hit in [param ctx] (attacker, defender, weapon, triangle result, Exposed
	## and crit set), on [param engine] before the hit is applied.
	static func explain(
			engine: EffectEngine, state: CombatState, ctx: EffectContext
	) -> HitBreakdown:
		var found: HitBreakdown = HitBreakdown.new()
		found.stages = DamagePipeline.compute(engine, state, ctx)
		var sheet: StatSheet = engine.stats(ctx.attacker_id)
		var weapon: CombatState.WeaponStats = state.weapon(ctx.weapon_id)
		var weapon_damage: float = 0.0 if weapon == null else float(weapon.damage)
		# NOTE: the same parts as DamagePipeline.compute; [member stages] holds its own totals.
		found.attack = sheet.explain(DamageStage.Key.ATTACK, ctx)
		found.might = DamagePipeline.SCALING_MODIFIER * sheet.get_value(CombatValue.Key.MGT, ctx)
		found.triangle = WeaponTriangle.damage_change(ctx.matchup, weapon_damage)
		if found.stages.is_effective:
			var times: float = sheet.get_value(CombatValue.Key.EFFECTIVE_MODIFIER, ctx)
			found.effectiveness = (times - 1.0) * weapon_damage
		var skips: bool = (
				found.stages.damage_type == CombatFact.DamageType.PURE
				or ctx.has_flag(ModifyThat.Flag.SKIP_MITIGATION)
				or (
						ctx.is_crit
						and sheet.is_allowed(CombatValue.Permission.SKIP_MITIGATION_ON_CRIT, ctx)
				)
		)
		if not skips:
			found.mitigation = DamagePipeline.mitigation(
					engine, state, ctx.defender_id, found.stages.damage_type, ctx
			)
		if ctx.is_crit:
			found.critical = DamagePipeline.value_with_base(
					engine,
					ctx.attacker_id,
					DamageStage.Key.CRITICAL,
					sheet.get_value(CombatValue.Key.CRIT_X, ctx),
					"CritX",
					ctx
			)
		return found

	static func _signed(value: float) -> String:
		var shown: String = String.num(absf(value), 6)
		return ("-" if value < 0.0 else "+") + shown


## A Block or heal staff's preview.
class StaffForecast:
	extends Forecast

	## What the staff does ([enum CombatState.WeaponStats.Staff]).
	var kind: CombatState.WeaponStats.Staff = CombatState.WeaponStats.Staff.NONE
	## Its amount before any "that heal" or "that Block gain" change and healing received:
	## [constant CombatValue.Key.STAFF_AMOUNT] plus Might, exact.
	var amount: float = 0.0
	## Each unit the staff gave to, in the order it gave.
	var recipients: Array[Recipient] = []

	## Fills [member recipients] from the facts: the staff's own Block gains and heals, which name
	## no effect.
	func fill() -> void:
		for fact: CombatFact in facts:
			var is_gain: bool = fact.kind == CombatFact.Kind.BLOCK_GAINED
			if not is_gain and fact.kind != CombatFact.Kind.HEALED:
				continue
			if not fact.source_effect_id.is_empty():
				continue
			var recipient: Recipient = null
			for known: Recipient in recipients:
				if known.unit_id == fact.actor_id:
					recipient = known
			if recipient == null:
				recipient = Recipient.new()
				recipient.unit_id = fact.actor_id
				recipients.append(recipient)
			if is_gain:
				recipient.block_gained += fact.amount
			else:
				recipient.healed += fact.amount
				recipient.restored += fact.hp_amount


## What a staff gave one unit.
class Recipient:
	extends RefCounted

	## The unit.
	var unit_id: String = ""
	## Block it gained.
	var block_gained: int = 0
	## The heal's amount after healing received, before the cap at maximum HP.
	var healed: int = 0
	## HP it got back.
	var restored: int = 0

	## Healing lost to the cap at maximum HP.
	func overheal() -> int:
		return healed - restored


## A shove's preview.
class ShoveForecast:
	extends Forecast

	## Where the target goes and why it stops; null when the shove isn't legal.
	var path: ShoveResolver.Path = null


## One unit before and after a preview.
class UnitOutcome:
	extends RefCounted

	## The unit.
	var unit_id: String = ""
	## HP before the command.
	var hp_before: int = 0
	## HP after; 0 when defeated.
	var hp_after: int = 0
	## Block before.
	var block_before: int = 0
	## Block after.
	var block_after: int = 0
	## Stance before.
	var stance_before: int = 0
	## Stance after; 0 is Exposed.
	var stance_after: int = 0
	## Tile before.
	var tile_before: Vector2i = CombatFact.NO_TILE
	## Tile after; [constant CombatFact.NO_TILE] when defeated.
	var tile_after: Vector2i = CombatFact.NO_TILE
	## Whether it was defeated.
	var is_defeated: bool = false

	## [param of_id]'s state in [param state] now, as the "before" half.
	static func before(state: CombatState, of_id: String) -> UnitOutcome:
		var found: UnitOutcome = UnitOutcome.new()
		found.unit_id = of_id
		found.hp_before = state.get_hp(of_id)
		found.block_before = state.get_block(of_id)
		found.stance_before = state.get_stance(of_id)
		found.tile_before = state.tile_of(of_id)
		return found

	## Fills the "after" half from [param state].
	func finish(state: CombatState) -> void:
		is_defeated = not state.has_unit(unit_id)
		hp_after = state.get_hp(unit_id)
		block_after = state.get_block(unit_id)
		stance_after = state.get_stance(unit_id)
		tile_after = state.tile_of(unit_id)

	## Whether anything changed.
	func is_changed() -> bool:
		return (
				is_defeated
				or hp_after != hp_before
				or block_after != block_before
				or stance_after != stance_before
				or tile_after != tile_before
		)

	## The changes as text, such as [code]e1 HP -4, Stance -1[/code]; empty when none.
	func describe_change(compared: UnitOutcome = null) -> String:
		var hp: int = hp_after - (hp_before if compared == null else compared.hp_after)
		var block: int = block_after - (block_before if compared == null else compared.block_after)
		var stance: int = (
				stance_after - (stance_before if compared == null else compared.stance_after)
		)
		var parts: PackedStringArray = []
		if hp != 0:
			parts.append("HP %+d" % [hp])
		if block != 0:
			parts.append("Block %+d" % [block])
		if stance != 0:
			parts.append("Stance %+d" % [stance])
		var was_defeated: bool = false if compared == null else compared.is_defeated
		if is_defeated and not was_defeated:
			parts.append("defeated")
		if parts.is_empty():
			return ""
		return "%s %s" % [unit_id, ", ".join(parts)]


## A chance-gated effect the preview left out of its totals: what would differ if that chance
## passed, every other roll as the preview made it ("25%: e1 HP -4").
class ChanceLine:
	extends RefCounted

	## The chance, in percent.
	var chance: int = 0
	## Index of its roll in [member Forecast.rolls].
	var roll_index: int = -1
	## The effect whose chance it was: the first activation the passing chance adds; empty when
	## passing it activates nothing new.
	var effect_id: String = ""
	## The same preview with the chance passing.
	var what_if: Forecast = null
	## Each unit's difference from the preview, such as "e1 HP -4"; empty when none.
	var changes: PackedStringArray = []

	func _init(percent: int, index: int, base: Forecast, passing: Forecast) -> void:
		chance = percent
		roll_index = index
		what_if = passing
		var seen: Dictionary[String, int] = {}
		for fact: CombatFact in base.facts:
			if fact.kind == CombatFact.Kind.EFFECT_ACTIVATED:
				seen[fact.source_effect_id] = seen.get(fact.source_effect_id, 0) + 1
		for fact: CombatFact in passing.facts:
			if fact.kind != CombatFact.Kind.EFFECT_ACTIVATED:
				continue
			var left: int = seen.get(fact.source_effect_id, 0)
			if left > 0:
				seen[fact.source_effect_id] = left - 1
				continue
			effect_id = fact.source_effect_id
			break
		for after: UnitOutcome in passing.units:
			var compared: UnitOutcome = base.unit(after.unit_id)
			var text: String = after.describe_change(compared)
			if not text.is_empty():
				changes.append(text)

	## The line as text, such as [code]25%: e1 HP -4 (effect:lucky)[/code].
	func to_text() -> String:
		var shown: String = "no change" if changes.is_empty() else ", ".join(changes)
		var named: String = "" if effect_id.is_empty() else " (%s)" % [effect_id]
		return "%d%%: %s%s" % [chance, shown, named]


## The rolls of a [ChanceLine]'s preview: the given outcomes first, then as [ForecastRolls]
## decides (hits land, chances fail, the first candidate).
class WhatIfRolls:
	extends ForecastRolls

	var _outcomes: PackedInt32Array = []

	func _init(outcomes: PackedInt32Array) -> void:
		_outcomes = outcomes

	func _draw_hit_2rn(hit_percent: int, odds: float) -> bool:
		if records.size() < _outcomes.size():
			return _outcomes[records.size()] != 0
		return super(hit_percent, odds)

	func _draw_percent(chance: int, odds: float) -> bool:
		if records.size() < _outcomes.size():
			return _outcomes[records.size()] != 0
		return super(chance, odds)

	func _draw_index(count: int) -> int:
		if records.size() < _outcomes.size():
			return _outcomes[records.size()]
		return super(count)


## Reads each attack of a preview's exchange as it resolves, from the sandbox's facts and the
## contexts they are recorded with: a context observer on the sandbox engine
## ([method EffectEngine.add_context_observer]), so it reads the state between the resolver's steps
## and changes nothing.
class Recorder:
	extends RefCounted

	## Every attack, in order.
	var attacks: Array[AttackForecast] = []
	## The turn order, read when the first attack started.
	var turn_order: PackedStringArray = []
	## Whether the defender can counter, read then.
	var can_counter: bool = false
	## Each side's numbers, read then, by unit id.
	var sides: Dictionary[String, SideForecast] = {}

	var _engine: EffectEngine = null
	var _initiator_id: String = ""
	var _defender_id: String = ""
	var _explain: bool = true
	var _current: AttackForecast = null

	func _init(
			engine: EffectEngine, initiator_id: String, defender_id: String, explain: bool
	) -> void:
		_engine = engine
		_initiator_id = initiator_id
		_defender_id = defender_id
		_explain = explain

	## Called with every fact the sandbox records and the context it was recorded with.
	func observe(fact: CombatFact, ctx: EffectContext) -> void:
		var state: CombatState = _engine.state
		match fact.kind:
			CombatFact.Kind.ATTACK_MADE:
				if attacks.is_empty():
					_read_sides(state)
				_current = AttackForecast.new()
				_current.index = attacks.size()
				_current.attacker_id = fact.actor_id
				_current.defender_id = fact.target_id
				# The hit roll is the next roll: the Attack made window rolled before this fact.
				_current.hit_roll = _engine.rolls.records.size()
				attacks.append(_current)
			CombatFact.Kind.MISSED:
				_take_hit_roll()
			CombatFact.Kind.HIT_DEALT:
				_take_hit_roll()
				_current.is_hit = true
				_current.is_crit = ctx.is_crit
				_current.damage = fact.amount
				if ctx.defender_was_exposed:
					# NOTE: the crit roll is the last roll before Hit dealt is recorded, unless
					# the crit landed and a Chance in a Crit window rolled after it.
					# ForecastRolls never crits, so the player's preview always reads it right.
					_current.crit_roll = _engine.rolls.records.size() - 1
					_current.crit_chance = _engine.rolls.records[_current.crit_roll].value
				# The hit's own context, with every inline change from its windows, before stage 6
				# applies it: the same reads DamagePipeline.compute made.
				if _explain:
					_current.breakdown = HitBreakdown.explain(_engine, state, ctx)
			CombatFact.Kind.DAMAGE_DEALT:
				if _current != null and fact.actor_id == _current.attacker_id:
					_current.hp_damage = fact.hp_amount
					_current.block_damage = fact.block_amount
			CombatFact.Kind.DEFEATED:
				if _current != null and fact.actor_id == _current.defender_id:
					_current.defeated = true

	func _take_hit_roll() -> void:
		var record: RollRecord = _engine.rolls.records[_current.hit_roll]
		_current.hit = record.value
		_current.hit_probability = record.probability

	# The turn order and both sides' numbers as the resolver reads them: after Before Combat, as
	# the first attack starts.
	func _read_sides(state: CombatState) -> void:
		turn_order = ExchangeResolver.turn_order(_engine, state, _initiator_id, _defender_id)
		can_counter = ExchangeResolver.can_counter(_engine, state, _defender_id, _initiator_id)
		for unit_id: String in [_initiator_id, _defender_id]:
			var other: String = _defender_id if unit_id == _initiator_id else _initiator_id
			var ctx: EffectContext = ExchangeResolver.context(
					_engine, state, unit_id, other, _initiator_id, 0
			)
			var side: SideForecast = SideForecast.new()
			side.unit_id = unit_id
			side.weapon_id = state.equipped_weapon_id(unit_id)
			side.hit = ExchangeResolver.hit_chance(_engine, state, ctx)
			side.hit_probability = RollSource.hit_2rn_probability(side.hit)
			side.crit_chance = clampi(
					ExchangeResolver.CRIT_BASE
					+ _engine.stats(unit_id).get_int(CombatValue.Key.CRIT_CHANCE, ctx),
					0,
					100
			)
			side.attacks_per_turn = ExchangeResolver.attacks_per_turn(
					_engine, state, unit_id, other, _initiator_id
			)
			side.turns = turn_order.count(unit_id)
			sides[unit_id] = side
