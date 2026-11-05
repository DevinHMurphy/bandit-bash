# ==============================================================================
# Bandit Bash
# Copyright (c) 2026 Derc Development
# Licensed under the MIT License. See LICENSE.
#
# File:     forecast_view_model.gd
# Author:
# Created:  November 4, 2026
# Modified: November 5, 2026
# ==============================================================================

class_name ForecastViewModel
extends RefCounted
## What the forecast panel shows for one command, as plain rows read from [CombatForecast]: an
## attack's two sides, a staff's user and target, or a shove's shover and target (combat UI plan,
## question 7; Godot_FE FR-UI-4 plus Block and Stance).
##
## [method build] runs the command's own preview ([method CombatForecast.exchange],
## [method CombatForecast.staff] or [method CombatForecast.shove]) on the session's engine, so the
## rows are what the command resolves to with every hit landing (FR-MATH-12). Each [Row] has one
## cell per column: the actor's on the left, the target's on the right. An exchange also keeps each
## side's first landed hit's stages ([member breakdowns], explain's [CombatForecast.HitBreakdown]),
## which the panel shows on its toggle. Reading only: previews run on sandboxes. [ForecastPanel]
## draws it; tests compare it with the forecast without rendering (question 13).
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
}

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

# What separates [method CombatForecast.HitBreakdown.to_text]'s stages, one per line here.
const HIT_BREAKDOWN_SEPARATOR: String = "; "

## Which preview this is.
var kind: Kind = Kind.EXCHANGE

## The heading, such as "Attack Brute".
var title: String = ""

## The command previewed: the one Confirm sends.
var command: UnitTurnCommand = null

## The preview itself, for readers that need more than the rows.
var forecast: CombatForecast.Forecast = null

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


## The row labelled [param label]; null when there is none.
func row(label: String) -> Row:
	for found: Row in rows:
		if found.label == label:
			return found
	return null


## Whether the target can be attacked with another weapon ([member weapon_count] above 1).
func can_cycle() -> bool:
	return weapon_count > 1


# An exchange's rows: both sides' weapon, triangle, effectiveness, Hit, damage, crit, strikes, and
# HP, Block and Stance before and after.
func _fill_exchange(session: CombatSession, found: CombatForecast.ExchangeForecast) -> void:
	forecast = found
	var state: CombatState = session.state
	var sides: Array[CombatForecast.SideForecast] = [found.attacker, found.defender]
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
	for side: CombatForecast.SideForecast in sides:
		var attacks: bool = side.turns > 0
		var effective: String = NONE_TEXT
		if side.breakdown != null:
			effective = "Yes" if side.breakdown.stages.is_effective else "No"
		cells.append(PackedStringArray([
			"%d%%" % [side.hit] if attacks and side.hit >= 0 else NONE_TEXT,
			"%d" % [side.damage] if side.damage >= 0 else NONE_TEXT,
			"%d%%" % [side.crit_chance] if attacks and side.crit_chance >= 0 else NONE_TEXT,
			"%d × %d" % [side.attacks_per_turn, side.turns] if attacks else NONE_TEXT,
			effective,
		]))
		if side.breakdown != null:
			var stages: Breakdown = Breakdown.new()
			stages.unit_id = side.unit_id
			stages.label = BattleText.name_of(session, side.unit_id)
			stages.lines = side.breakdown.to_text().split(HIT_BREAKDOWN_SEPARATOR)
			breakdowns.append(stages)
	var labels: PackedStringArray = ["Hit", "Damage", "Crit", "Strikes", "Effective"]
	for i: int in labels.size():
		_add_row(labels[i], cells[0][i], cells[1][i])
	_add_outcome_rows(found.attacker.outcome, found.defender.outcome)
	if not found.can_counter and found.is_legal:
		notes.append("%s can't counter." % [target_label])
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


# HP, Block and Stance rows, before and after, for the left and right units.
func _add_outcome_rows(
		left: CombatForecast.UnitOutcome, right: CombatForecast.UnitOutcome
) -> void:
	_add_row("HP", _hp_change(left), _hp_change(right))
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


static func _weapon_text(weapon: CombatState.WeaponStats) -> String:
	if weapon == null:
		return NONE_TEXT
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


## One side's hit stages for the breakdown toggle.
class Breakdown:
	extends RefCounted

	## The unit whose hit it is.
	var unit_id: String = ""
	## Its heading: the unit's name ([method BattleText.name_of]).
	var label: String = ""
	## One line per stage, as [method CombatForecast.HitBreakdown.to_text] lists them.
	var lines: PackedStringArray = []
