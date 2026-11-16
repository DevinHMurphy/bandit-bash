# ==============================================================================
# Bandit Bash
# Copyright (c) 2026 Derc Development
# Licensed under the MIT License. See LICENSE.
#
# File:     forecast_view_model.gd
# Author:
# Created:  November 4, 2026
# Modified: November 16, 2026
# ==============================================================================

class_name ForecastViewModel
extends RefCounted
## What the forecast panel shows for one command, as plain rows read from [CombatForecast]: an
## attack's two sides, a staff's or a shove's two units, or a rune cast's changed units, now and
## after (combat UI plan, question 7; Godot_FE FR-UI-4 plus Block and Stance).
##
## [method build] and [method build_rune] run the command's own preview on the session's engine,
## so the rows are what it resolves to with every hit landing (FR-MATH-12). An exchange keeps each
## side's first landed hit's stages ([member breakdowns]) for the panel's toggle, and reads a
## defeat as a chance ([constant DEFEAT_ON_HIT]), its counter from [member counter] (the actor's
## strikes before it missing, [CounterRolls]). [member flashes] gives the board each unit's
## predicted HP and Stance (question 34 (1)). Reading only: previews run on sandboxes.
##
## @tutorial(Combat UI plan): docs/plans/2026-11-04-combat-ui.md

## Which preview the rows come from.
enum Kind {
	## An attack ([constant UnitTurnCommand.Action.ATTACK]).
	EXCHANGE = 0,
	## A Block or heal staff ([constant UnitTurnCommand.Action.STAFF]).
	STAFF = 1,
	## A shove ([constant UnitTurnCommand.Action.SHOVE]).
	SHOVE = 2,
	## A rune cast ([CastRuneCommand], [method CombatForecast.rune]).
	RUNE = 3,
}

# ASSUMPTION: a rune preview's column headings; no design doc words them.
## A rune preview's left column heading: each changed unit as it is now.
const RUNE_NOW_HEADING: String = "Now"

## A rune preview's right column heading: each changed unit after the cast.
const RUNE_AFTER_HEADING: String = "After"

## The cell shown where a side has no value, such as the Hit of a defender that can't counter.
const NONE_TEXT: String = "—"

## Each [enum WhileMatchupCondition.Matchup]'s name in the Triangle row, by value.
const MATCHUP_TEXT: Array[String] = ["Advantage", "Standoff", "Disadvantage"]

## Each [enum CombatState.WeaponStats.Staff]'s name in the Staff row, by value.
const STAFF_TEXT: Array[String] = ["", "Block", "Heal", "Attack"]

## Each [enum ShoveResolver.Stop]'s reason in the notes, by value.
const STOP_TEXT: Array[String] = [
	"stops after its full Shove distance",
	"stops at the map's edge",
	"stops against something it can't enter",
	"bumps into %s: both take %d damage",
	"hits a spiked wall: takes %d damage",
]

## An exchange's HP cell for a unit defeated by one hit: [code]%d[/code] the chance, in percent.
const DEFEAT_ON_HIT: String = " (defeated on hit, %d%%)"

## As [constant DEFEAT_ON_HIT] for a defeat that takes several hits: the hits, then the chance.
const DEFEAT_ON_HITS: String = " (defeated on %d hits, %d%%)"

## The note naming [member counter]: the actor, the target, then the actor's HP cell.
const COUNTER_NOTE: String = "If %s misses, %s counters: %s HP %s."

# What separates [method CombatForecast.HitBreakdown.to_text]'s stages, one per line here.
const HIT_BREAKDOWN_SEPARATOR: String = "; "

## Which preview this is.
var kind: Kind = Kind.EXCHANGE

## The heading, such as "Attack Brute".
var title: String = ""

## The command previewed: the one Confirm sends. Null for a rune's, in [member rune_command].
var command: UnitTurnCommand = null

## A rune preview's command, the one Confirm sends; null for every other kind.
var rune_command: CastRuneCommand = null

## A rune preview's tiles on the map, in the order the cast reaches them
## ([member CombatForecast.RuneForecast.tiles]): Spark's whole chain of blasts. Empty for every
## other kind, and for an illegal cast.
var tiles: Array[Vector2i] = []

## The preview itself, for readers that need more than the rows.
var forecast: CombatForecast.Forecast = null

## For an exchange whose all-hits line defeats a defender that could counter: the same exchange
## with the actor's strikes before the counter missing, which the target's Damage cell, its
## breakdown and [constant COUNTER_NOTE] read. Null otherwise.
var counter: CombatForecast.ExchangeForecast = null

## The left column's heading: the acting unit.
var actor_label: String = ""

## The right column's heading: the target.
var target_label: String = ""

## Every row, in display order.
var rows: Array[Row] = []

## Lines under the rows: the chance-gated effects left out of the totals, other units the action
## changes, where a shove stops, why the preview isn't legal.
var notes: PackedStringArray = []

## For an exchange, each side's first landed hit's stages: the actor's, then the target's. Empty
## for a staff or a shove, and for a side that lands no hit.
var breakdowns: Array[Breakdown] = []

## The weapon cycle: this command's place among the target's weapons ([member weapon_count]).
var weapon_index: int = 0

## How many weapons can make this attack ([member TurnInputModel.TargetOption.commands]); 1 for a
## staff or a shove.
var weapon_count: int = 1

## Each unit whose HP or Stance the forecast changes, which the board flashes while the panel is
## open (question 34 (1)): the forecast's outcomes, the actor's from [member counter] when there
## is one. Empty for an illegal forecast.
var flashes: Array[Flash] = []


## Builds the rows; see [method build], which is how callers make one. Unset arguments build an
## empty model.
func _init(
		session: CombatSession = null,
		previewed: UnitTurnCommand = null,
		index: int = 0,
		count: int = 1
) -> void:
	if session == null or previewed == null:
		return
	command = previewed
	weapon_index = index
	weapon_count = maxi(count, 1)
	actor_label = BattleText.name_of(session, command.actor_id)
	target_label = BattleText.name_of(session, command.get_target_id())
	match command.action:
		UnitTurnCommand.Action.ATTACK:
			kind = Kind.EXCHANGE
			_fill_exchange(session, CombatForecast.exchange(session.engine, command))
		UnitTurnCommand.Action.STAFF:
			kind = Kind.STAFF
			_fill_staff(session, CombatForecast.staff(session.engine, command))
		UnitTurnCommand.Action.SHOVE:
			kind = Kind.SHOVE
			_fill_shove(session, CombatForecast.shove(session.engine, command))
		_:
			notes.append("No forecast for this action.")
			return
	var action_name: String = "Attack"
	if kind != Kind.EXCHANGE:
		action_name = (Kind.find_key(kind) as String).capitalize()
	title = "%s %s" % [action_name, target_label]
	if not forecast.is_legal:
		notes.append("Not legal: %s" % [forecast.reason])
		return
	_fill_flashes()


## The row labelled [param label]; null when there is none.
func row(label: String) -> Row:
	for found: Row in rows:
		if found.label == label:
			return found
	return null


## Whether the target can be attacked with another weapon ([member weapon_count] above 1).
func can_cycle() -> bool:
	return weapon_count > 1


## [param unit_id]'s entry in [member flashes]; null when the forecast leaves it as it is.
func flash_of(unit_id: String) -> Flash:
	for found: Flash in flashes:
		if found.unit_id == unit_id:
			return found
	return null


# One Flash per unit the forecast changes, read from its outcomes: every hit landing, no crit, Block
# applied, HP after clipped at 0 and Stance after one lower per hit that got damage through (the
# forecast's rolls). An exchange's actor reads the counter line when there is one, as its Damage
# cell and COUNTER_NOTE do (question 18 (b)).
func _fill_flashes() -> void:
	for outcome: CombatForecast.UnitOutcome in forecast.units:
		var shown: CombatForecast.UnitOutcome = outcome
		# The counter line's actor outcome even when the all-hits line defeats the target first,
		# so a predicted kill still shows what the counter would take (question 35 (5)).
		if (
				counter != null
				and outcome.unit_id == forecast.actor_id
				and counter.attacker.outcome != null
		):
			shown = counter.attacker.outcome
		# Every unit the forecast changes flashes (splash, a shove's bump), not only the two named
		# ones (question 35 (5)).
		var hp_changed: bool = shown.hp_after != shown.hp_before
		var stance_dropped: bool = shown.stance_after < shown.stance_before
		if not hp_changed and not stance_dropped:
			continue
		var added: Flash = Flash.new()
		added.unit_id = shown.unit_id
		added.hp_before = shown.hp_before
		added.hp_after = maxi(shown.hp_after, 0)
		added.stance_before = shown.stance_before
		added.stance_after = mini(shown.stance_after, shown.stance_before)
		flashes.append(added)


# An exchange's rows: both sides' weapon, triangle, effectiveness, Hit, damage, crit, strikes, and
# HP, Block and Stance before and after. The target's damage, effectiveness and breakdown come from
# the counter line when the all-hits line defeats it first.
func _fill_exchange(session: CombatSession, found: CombatForecast.ExchangeForecast) -> void:
	forecast = found
	var state: CombatState = session.state
	if found.is_legal and found.defender.turns > 0 and found.defender.damage < 0:
		counter = _counter_line(session, found)
	var sides: Array[CombatForecast.SideForecast] = [found.attacker, found.defender]
	var landed: Array[CombatForecast.SideForecast] = [
		found.attacker, found.defender if counter == null else counter.defender,
	]
	var actor_weapon: CombatState.WeaponStats = state.weapon(found.attacker.weapon_id)
	var target_weapon: CombatState.WeaponStats = state.weapon(found.defender.weapon_id)
	_add_row("Weapon", _weapon_text(actor_weapon), _weapon_text(target_weapon))
	if actor_weapon != null and target_weapon != null:
		var result: WhileMatchupCondition.Matchup = WeaponTriangle.matchup(
				actor_weapon.profile, target_weapon.profile
		)
		_add_row(
				"Triangle",
				MATCHUP_TEXT[result],
				MATCHUP_TEXT[WeaponTriangle.mirror(result)]
		)
	else:
		_add_row("Triangle", NONE_TEXT, NONE_TEXT)
	var cells: Array[PackedStringArray] = []
	for i: int in sides.size():
		var side: CombatForecast.SideForecast = sides[i]
		var hit_side: CombatForecast.SideForecast = landed[i]
		var attacks: bool = side.turns > 0
		var effective: String = NONE_TEXT
		if hit_side.breakdown != null:
			effective = "Yes" if hit_side.breakdown.stages.is_effective else "No"
		cells.append(PackedStringArray([
			"%d%%" % [side.hit] if attacks and side.hit >= 0 else NONE_TEXT,
			"%d" % [hit_side.damage] if hit_side.damage >= 0 else NONE_TEXT,
			"%d%%" % [side.crit_chance] if attacks and side.crit_chance >= 0 else NONE_TEXT,
			"%d × %d" % [side.attacks_per_turn, side.turns] if attacks else NONE_TEXT,
			effective,
		]))
		if hit_side.breakdown != null:
			var stages: Breakdown = Breakdown.new()
			stages.unit_id = hit_side.unit_id
			stages.label = BattleText.name_of(session, hit_side.unit_id)
			stages.lines = hit_side.breakdown.to_text().split(HIT_BREAKDOWN_SEPARATOR)
			breakdowns.append(stages)
	var labels: PackedStringArray = ["Hit", "Damage", "Crit", "Strikes", "Effective"]
	for i: int in labels.size():
		_add_row(labels[i], cells[0][i], cells[1][i])
	_add_outcome_rows(found.attacker.outcome, found.defender.outcome, found)
	if not found.can_counter and found.is_legal:
		notes.append("%s can't counter." % [target_label])
	if counter != null and counter.attacker.outcome != null:
		notes.append(COUNTER_NOTE % [
			actor_label, target_label, actor_label,
			exchange_hp(counter, counter.attacker.outcome),
		])
	for chance: CombatForecast.ChanceLine in found.chances:
		notes.append("Chance %s" % [chance.to_text()])
	_note_others(session, found)


# A staff's rows: the staff and its amount, then both units' HP, Block and Stance.
func _fill_staff(session: CombatSession, found: CombatForecast.StaffForecast) -> void:
	forecast = found
	# A range-0 staff names no target: the forecast fills in the user.
	if not found.target_id.is_empty():
		target_label = BattleText.name_of(session, found.target_id)
	var held: CombatState.WeaponStats = session.state.equipped_weapon(found.actor_id)
	var staff_text: String = NONE_TEXT
	if held != null:
		staff_text = "%s: %s %s" % [
			_weapon_text(held), STAFF_TEXT[found.kind], EffectTerms.format_number(found.amount),
		]
	var given: PackedStringArray = []
	for recipient: CombatForecast.Recipient in found.recipients:
		if recipient.block_gained > 0:
			given.append("Block +%d" % [recipient.block_gained])
		if recipient.healed > 0:
			given.append("HP +%d" % [recipient.restored])
	_add_row("Staff", staff_text, ", ".join(given) if not given.is_empty() else NONE_TEXT)
	var user: CombatForecast.UnitOutcome = found.unit(found.actor_id)
	var target: CombatForecast.UnitOutcome = found.unit(found.target_id)
	_add_outcome_rows(user, target)
	for recipient: CombatForecast.Recipient in found.recipients:
		if recipient.overheal() > 0:
			notes.append("%s: %d healing lost to its maximum HP." % [
				BattleText.name_of(session, recipient.unit_id), recipient.overheal(),
			])
	_note_others(session, found)


# A shove's rows: both units' tile, HP and Block before and after; where it stops in the notes.
func _fill_shove(session: CombatSession, found: CombatForecast.ShoveForecast) -> void:
	forecast = found
	var shover: CombatForecast.UnitOutcome = found.unit(found.actor_id)
	var target: CombatForecast.UnitOutcome = found.unit(found.target_id)
	_add_row("Tile", _tile_change(shover), _tile_change(target))
	_add_outcome_rows(shover, target)
	if found.path != null:
		var stop: String = STOP_TEXT[found.path.stop]
		match found.path.stop:
			ShoveResolver.Stop.BUMP:
				stop = stop % [
					BattleText.name_of(session, found.path.bumped_id), ShoveResolver.BUMP_DAMAGE,
				]
			ShoveResolver.Stop.SPIKE:
				stop = stop % [ShoveResolver.SPIKE_DAMAGE]
		var slide: String = ", sliding on oil" if found.path.slid else ""
		notes.append("%s moves %d tiles and %s%s." % [
			target_label, found.path.tiles_moved, stop, slide,
		])
	_note_others(session, found)


# HP, Block and Stance rows, before and after, for the left and right units; an exchange's HP
# cells give a defeat's chance ([method exchange_hp]).
func _add_outcome_rows(
		left: CombatForecast.UnitOutcome,
		right: CombatForecast.UnitOutcome,
		exchange: CombatForecast.ExchangeForecast = null
) -> void:
	if exchange == null:
		_add_row("HP", _hp_change(left), _hp_change(right))
	else:
		_add_row("HP", exchange_hp(exchange, left), exchange_hp(exchange, right))
	_add_row("Block", _change(left, &"block"), _change(right, &"block"))
	_add_row("Stance", _change(left, &"stance"), _change(right, &"stance"))


# A note for each unit besides the two columns that the action changes (splash, a bump).
func _note_others(session: CombatSession, found: CombatForecast.Forecast) -> void:
	for outcome: CombatForecast.UnitOutcome in found.units:
		if outcome.unit_id == found.actor_id or outcome.unit_id == found.target_id:
			continue
		var text: String = outcome.describe_change()
		if not text.is_empty():
			var shown_name: String = BattleText.name_of(session, outcome.unit_id)
			notes.append(text.replace(outcome.unit_id, shown_name))


# The exchange with the actor's strikes before the target's first turn missing, so the target
# counters; null when the target has no turn, or lands no hit even so.
func _counter_line(
		session: CombatSession, found: CombatForecast.ExchangeForecast
) -> CombatForecast.ExchangeForecast:
	var first_turn: int = found.turn_order.find(found.target_id)
	if first_turn < 0:
		return null
	var misses: int = 0
	for i: int in first_turn:
		if found.turn_order[i] == found.actor_id:
			misses += found.attacker.attacks_per_turn
	var line: CombatForecast.ExchangeForecast = CombatForecast.exchange(
			session.engine, command, CounterRolls.new(misses)
	)
	if not line.is_legal or line.defender.damage < 0:
		return null
	return line


# A rune cast's rows: for each unit it changes, the HP, Block, Stance and tile that change, now
# and after; its text and any refusal in the notes. A unit it names that changes none of those
# (Clarity's and Haste's timed modifiers, which the preview doesn't track) is read in the text.
func _fill_rune(session: CombatSession, cast: CastRuneCommand, text: String) -> void:
	kind = Kind.RUNE
	rune_command = cast
	var found: CombatForecast.RuneForecast = CombatForecast.rune(session.engine, cast)
	forecast = found
	var aimed: String = BattleText.name_of(session, cast.target_id)
	if found.target_kind == ContentIds.RUNE_PAIR:
		aimed = "%s ↔ %s" % [aimed, BattleText.name_of(session, cast.second_target_id)]
	elif found.target_kind == ContentIds.RUNE_OBJECT:
		aimed = BattleText.name_of(session, found.object_id)
	title = "%s %s" % [BattleText.name_of(session, cast.rune_id), aimed]
	actor_label = RUNE_NOW_HEADING
	target_label = RUNE_AFTER_HEADING
	if not text.is_empty():
		notes.append(text + ".")
	if not found.is_legal:
		notes.append("Not legal: %s" % [found.reason])
		return
	for tile: Vector2i in found.tiles:
		if session.state.grid.step(tile, Vector2i.ZERO) != CombatFact.NO_TILE:
			tiles.append(tile)
	for outcome: CombatForecast.UnitOutcome in found.units:
		var shown_name: String = BattleText.name_of(session, outcome.unit_id)
		if outcome.hp_after != outcome.hp_before or outcome.is_defeated:
			_add_row("%s HP" % [shown_name], "%d" % [outcome.hp_before], (
					"%d (defeated)" % [maxi(outcome.hp_after, 0)] if outcome.is_defeated
					else "%d" % [outcome.hp_after]
			))
		if outcome.is_defeated:
			continue
		if outcome.block_after != outcome.block_before:
			_add_row("%s Block" % [shown_name], "%d" % [outcome.block_before], (
					"%d" % [outcome.block_after]
			))
		if outcome.stance_after != outcome.stance_before:
			_add_row("%s Stance" % [shown_name], "%d" % [outcome.stance_before], (
					"%d (Exposed)" % [outcome.stance_after] if outcome.stance_after == 0
					else "%d" % [outcome.stance_after]
			))
		if outcome.tile_after != outcome.tile_before:
			_add_row("%s tile" % [shown_name], str(outcome.tile_before), str(outcome.tile_after))
	_fill_flashes()


func _add_row(label: String, left: String, right: String) -> void:
	var added: Row = Row.new()
	added.label = label
	added.actor = left
	added.target = right
	rows.append(added)


## The rows for [param previewed] on [param session], which must be an attack, a staff use or a
## shove (an empty, illegal model otherwise). [param index] and [param count]: its place in the
## target's weapon cycle ([member TurnInputModel.TargetOption.commands]).
static func build(
		session: CombatSession,
		previewed: UnitTurnCommand,
		index: int = 0,
		count: int = 1
) -> ForecastViewModel:
	return ForecastViewModel.new(session, previewed, index, count)


## The rows for [param cast], a rune cast, on [param session] ([method CombatForecast.rune]):
## each unit it changes now and after, its [member tiles], and [param text] (the rune's own
## text, [member TurnInputModel.RuneOption.text]) as the first note. Confirm sends
## [member rune_command]; there is one weapon and no breakdown.
static func build_rune(
		session: CombatSession, cast: CastRuneCommand, text: String = ""
) -> ForecastViewModel:
	var model: ForecastViewModel = ForecastViewModel.new()
	model._fill_rune(session, cast, text)
	return model


## The HP cell of [param outcome] in [param exchange]: before and after, and for a defeat by the
## other side's hits, how many it takes and their chance ([constant DEFEAT_ON_HIT],
## [method defeat_chance]); a defeat by anything else reads "(defeated)".
static func exchange_hp(
		exchange: CombatForecast.ExchangeForecast, outcome: CombatForecast.UnitOutcome
) -> String:
	if outcome == null or not outcome.is_defeated:
		return _hp_change(outcome)
	var hits: int = 0
	for attack: CombatForecast.AttackForecast in exchange.attacks:
		if attack.defender_id != outcome.unit_id or not attack.is_hit:
			continue
		hits += 1
		if not attack.defeated:
			continue
		var killer: CombatForecast.SideForecast = (
				exchange.attacker if attack.attacker_id == exchange.actor_id else exchange.defender
		)
		var strikes: int = maxi(killer.attacks_per_turn * killer.turns, hits)
		var percent: int = roundi(defeat_chance(killer.hit, hits, strikes) * 100.0)
		var text: String = "%d → %d" % [outcome.hp_before, outcome.hp_after]
		if hits == 1:
			return text + DEFEAT_ON_HIT % [percent]
		return text + DEFEAT_ON_HITS % [hits, percent]
	return _hp_change(outcome)


## The chance that at least [param hits] of [param strikes] strikes land at [param hit] percent
## each, from 0.0 to 1.0. Reads the displayed Hit, as the Hit row shows it, and assumes every
## strike is made.
static func defeat_chance(hit: int, hits: int, strikes: int) -> float:
	# ASSUMPTION: the displayed Hit, not its true 2RN probability, so "60%" matches the Hit row's
	# 60% (question 18 (b)'s example); strikes are independent and all made.
	var p: float = clampf(hit / 100.0, 0.0, 1.0)
	var chance: float = 0.0
	for landed: int in range(maxi(hits, 0), strikes + 1):
		chance += (
				_choose(strikes, landed)
				* pow(p, float(landed))
				* pow(1.0 - p, float(strikes - landed))
		)
	return clampf(chance, 0.0, 1.0)


# Ways to choose k of n.
static func _choose(n: int, k: int) -> float:
	var ways: float = 1.0
	for i: int in k:
		ways = ways * float(n - i) / float(i + 1)
	return ways


# A weapon's label and its triangle profile; a weapon outside the triangle (a staff) shows none.
static func _weapon_text(weapon: CombatState.WeaponStats) -> String:
	if weapon == null:
		return NONE_TEXT
	if weapon.profile == WeaponTriangle.Profile.NONE:
		return weapon.label
	var profile: String = (WeaponTriangle.Profile.find_key(weapon.profile) as String).capitalize()
	return "%s (%s)" % [weapon.label, profile]


static func _hp_change(outcome: CombatForecast.UnitOutcome) -> String:
	if outcome == null:
		return NONE_TEXT
	var text: String = "%d → %d" % [outcome.hp_before, outcome.hp_after]
	return text + " (defeated)" if outcome.is_defeated else text


# Block or Stance before and after; Stance 0 after is Exposed.
static func _change(outcome: CombatForecast.UnitOutcome, which: StringName) -> String:
	if outcome == null or outcome.is_defeated:
		return NONE_TEXT
	if which == &"block":
		return "%d → %d" % [outcome.block_before, outcome.block_after]
	var text: String = "%d → %d" % [outcome.stance_before, outcome.stance_after]
	return text + " (Exposed)" if outcome.stance_after == 0 else text


static func _tile_change(outcome: CombatForecast.UnitOutcome) -> String:
	if outcome == null:
		return NONE_TEXT
	if outcome.tile_after == outcome.tile_before:
		return "stays"
	return "%s → %s" % [outcome.tile_before, outcome.tile_after]


## One row of the forecast: a label and one cell per column.
class Row:
	extends RefCounted

	## What the row shows, such as "Hit".
	var label: String = ""
	## The acting unit's cell.
	var actor: String = ""
	## The target's cell.
	var target: String = ""


## One unit's predicted HP and Stance, which its [HpBar] and [StancePips] flash between.
class Flash:
	extends RefCounted

	## The unit.
	var unit_id: String = ""
	## Its HP now.
	var hp_before: int = 0
	## Its HP after the action, never below 0; above [member hp_before] for a heal.
	var hp_after: int = 0
	## Its Stance now.
	var stance_before: int = 0
	## Its Stance after the action, never above [member stance_before].
	var stance_after: int = 0

	## Whether the action changes its HP.
	func changes_hp() -> bool:
		return hp_after != hp_before

	## Whether the action breaks any of its Stance.
	func breaks_stance() -> bool:
		return stance_after < stance_before


## One side's hit stages for the breakdown toggle.
class Breakdown:
	extends RefCounted

	## The unit whose hit it is.
	var unit_id: String = ""
	## Its heading: the unit's name ([method BattleText.name_of]).
	var label: String = ""
	## One line per stage, as [method CombatForecast.HitBreakdown.to_text] lists them.
	var lines: PackedStringArray = []


## The counter line's rolls ([member ForecastViewModel.counter]): the first hit rolls miss, as
## many as it is made with, then as [ForecastRolls] decides (hits land, chances fail, the first
## candidate). Draws nothing, so it shifts no stream.
class CounterRolls:
	extends ForecastRolls

	var _misses: int = 0
	var _hit_rolls: int = 0

	## [param misses]: how many hit rolls miss before every later one lands.
	func _init(misses: int) -> void:
		_misses = misses

	func _draw_hit_2rn(_hit_percent: int, _odds: float) -> bool:
		_hit_rolls += 1
		return _hit_rolls > _misses
