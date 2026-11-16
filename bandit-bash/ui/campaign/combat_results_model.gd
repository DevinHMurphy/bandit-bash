# ==============================================================================
# Bandit Bash
# Copyright (c) 2026 Derc Development
# Licensed under the MIT License. See LICENSE.
#
# File:     combat_results_model.gd
# Author:
# Created:  November 14, 2026
# Modified: November 15, 2026
# ==============================================================================

class_name CombatResultsModel
extends RefCounted
## What Results shows for one seat after a won combat, read from the run as saved: its combat
## report ([method CampaignRunState.read_combat_report]) and item pick, with units and items named.
##
## Built afresh after every command the screen sends, so a quit and Continue shows the same
## report and offers. Units are named as the run minted them
## ([method InstanceIdAllocator.label_of]), else by type. Reading only; the text helpers are
## static so other screens can share them.
##
## @tutorial(Campaign and run flow): docs/plans/2026-10-24-campaign-run-flow.md

## The grades and the gold they paid.
var grades: CombatGrades = null

## Each standing unit's XP, in roster order.
var xp_lines: Array[XpLine] = []

## The Standout's name; empty when nobody was.
var standout_name: String = ""

## Every level-up, in the order reached.
var level_up_lines: Array[LevelUpLine] = []

## The seat's item pick; null after a Boss, which offers none.
var pick: ItemPick = null

## The definition of each of [member pick]'s offers, in order; null for one not in the catalog.
var offers: Array[ItemDefinition] = []

## Whether this is the Boss's Results, after which the run ends.
var is_boss: bool = false

## XP needed per level ([member CombatRewardRules.xp_per_level]).[br]
## [b]Units:[/b] XP.
var xp_per_level: int = 0


## Whether every choice is made, so the run can go on: no pick, or one taken or skipped.
func can_continue() -> bool:
	return pick == null or pick.is_resolved


## What became of the pick: empty while it is open, else what was taken, or that it was skipped.
func pick_outcome() -> String:
	if pick == null or not pick.is_resolved:
		return ""
	if pick.taken == ItemPick.NOT_TAKEN:
		return "Skipped."
	return "Took %s." % [item_name(offers[pick.taken], pick.offers[pick.taken].definition_id)]


## Results for seat [param seat] of [param session]'s run; null when the seat has no combat
## report. [param catalog] null: the loaded one. [param rules] null: the shipped ones.
static func build(
		session: CampaignSession,
		seat: int,
		catalog: EffectCatalog.Index = null,
		rules: CombatRewardRules = null
) -> CombatResultsModel:
	var contents: EffectCatalog.Index = catalog if catalog != null else EffectCatalog.index()
	var reward_rules: CombatRewardRules = (
			rules if rules != null else CombatRewardRules.load_default()
	)
	var run: CampaignRunState = session.run
	var seat_run: SeatRun = run.seat_run(seat)
	if seat_run == null or reward_rules == null:
		return null
	var report: CampaignRunState.CombatReport = CampaignRunState.read_combat_report(
			seat_run, reward_rules
	)
	if report == null:
		return null
	var model: CombatResultsModel = CombatResultsModel.new()
	model.grades = report.grades
	model.is_boss = run.is_boss_beaten()
	model.xp_per_level = reward_rules.xp_per_level
	for award: XpAward in report.xp:
		var line: XpLine = XpLine.new()
		line.name = unit_name(session.ids, seat_run, award.unit_id, contents)
		line.award = award
		var unit: UnitInstance = seat_run.unit(award.unit_id)
		line.level = unit.level if unit != null else 0
		line.xp = unit.xp if unit != null else 0
		model.xp_lines.append(line)
		if award.is_standout:
			model.standout_name = line.name
	for reached: LevelUp in report.level_ups:
		var leveled: LevelUpLine = LevelUpLine.new()
		leveled.name = unit_name(session.ids, seat_run, reached.unit_id, contents)
		leveled.level = reached.level
		leveled.gains = gains_text(reached.gains)
		model.level_up_lines.append(leveled)
	model.pick = ItemPick.pending(seat_run)
	if model.pick != null:
		for offer: ItemPick.Offer in model.pick.offers:
			model.offers.append(contents.item(offer.definition_id))
	return model


## The name [param unit_id] of [param seat_run] shows by: its minted label in [param ids], else
## its unit type's name, else the id itself.
static func unit_name(
		ids: InstanceIdAllocator,
		seat_run: SeatRun,
		unit_id: String,
		catalog: EffectCatalog.Index
) -> String:
	var label: String = ids.label_of(unit_id) if ids != null else ""
	if not label.is_empty():
		return label
	var unit: UnitInstance = seat_run.unit(unit_id)
	var unit_type: UnitTypeDefinition = unit.definition(catalog) if unit != null else null
	if unit_type != null and not unit_type.display_name.is_empty():
		return unit_type.display_name
	return unit_id


## [param definition]'s name; [param fallback] (its content id) when it is null or unnamed.
static func item_name(definition: ItemDefinition, fallback: String = "") -> String:
	if definition == null or definition.display_name.is_empty():
		return fallback
	return definition.display_name


## [param definition]'s rarity and kind, and a weapon's type and numbers, on two lines:
## [code]Rare weapon · sword[/code] then [code]Dmg 5 · Hit 80 · Crit 5 · Rng 1-2[/code].
static func item_details(definition: ItemDefinition) -> String:
	if definition == null:
		return "Not in the catalog"
	var rarity: String = (ItemDefinition.Rarity.find_key(definition.rarity) as String).capitalize()
	var line: String = "%s %s" % [rarity, definition.kind]
	if not definition is WeaponDefinition:
		return line
	var weapon: WeaponDefinition = definition
	# NOTE: the weapon's own range, not ExchangeResolver.weapon_range's: an offer has no holder and
	# Results has no combat engine, so a Short Quiver's bows show their reach in battle.
	var reach: String = (
			str(weapon.range_min) if weapon.range_min == weapon.range_max
			else "%d-%d" % [weapon.range_min, weapon.range_max]
	)
	return "%s · %s\nDmg %d · Hit %d · Crit %d · Rng %s" % [
		line, weapon.weapon_type, weapon.damage, weapon.hit, weapon.crit, reach,
	]


## [param gains] as text, in stat order: [code]HP +1, MGT +2[/code]; [code]no gains[/code] when
## empty.
static func gains_text(gains: Dictionary[int, int]) -> String:
	var parts: PackedStringArray = []
	var stats: Array[int] = []
	stats.assign(gains.keys())
	stats.sort()
	for stat: int in stats:
		var stat_name: Variant = CombatValue.Stat.find_key(stat)
		parts.append("%s +%d" % [stat_name if stat_name != null else str(stat), gains[stat]])
	return "no gains" if parts.is_empty() else ", ".join(parts)


## One unit's XP line.
class XpLine:
	extends RefCounted

	## The unit's name.
	var name: String = ""
	## What it earned.
	var award: XpAward = null
	## Its level now, after any level-ups.
	var level: int = 0
	## Its XP toward the next level now.
	var xp: int = 0


## One level-up's line.
class LevelUpLine:
	extends RefCounted

	## The unit's name.
	var name: String = ""
	## The level it reached.
	var level: int = 0
	## The stat points gained, as [method CombatResultsModel.gains_text] writes them.
	var gains: String = ""
