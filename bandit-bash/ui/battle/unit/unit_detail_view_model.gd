# ==============================================================================
# Bandit Bash
# Copyright (c) 2026 Derc Development
# Licensed under the MIT License. See LICENSE.
#
# File:     unit_detail_view_model.gd
# Author:
# Created:  November 7, 2026
# Modified: November 19, 2026
# ==============================================================================

class_name UnitDetailViewModel
extends RefCounted
## Everything the session holds about one unit on the board, player or enemy, as plain data for the
## [UnitDetailPanel] (ui-lift.md, Unit detail pop-up; game-vision.md, Units, Weapons and
## equipment; Godot_FE's [code]unit_detailed_info[/code] screen).
##
## [method build] reads state, [method CombatSession.stats], the effect engine's instances, the
## intents and, for a player unit, its run record, and never changes them. It holds no rule: every
## number and source line is the session's ([method StatSheet.explain]), every name
## [BattleText]'s, every effect line [method EffectDefinition.describe]'s. Effects are grouped by
## what carries them: the unit's traits, each slot's item, and the army's heirlooms.
##
## @tutorial(UI lift): docs/design/ui-lift.md

## The combat values the panel lists after Attack Speed, in order: each its short name and
## [enum CombatValue.Key]. Hit, Crit and the range are the weapon's, so they go on its line too.
## Attack Speed isn't a row: its key holds only modifiers, on a base the exchange's rule
## computes ([member attack_speed]).
const COMBAT_ROWS: Array[Array] = [
	["Avoid", CombatValue.Key.AVOID],
	["AtkX", CombatValue.Key.ATK_X],
	["Parry", CombatValue.Key.PARRY],
	["Weight", CombatValue.Key.NET_WEIGHT],
	["Shove", CombatValue.Key.SHOVE_DISTANCE],
]

## The weapon-borne values listed with the combat rows, so their sources show: each its short name
## and [enum CombatValue.Key].
const WEAPON_ROWS: Array[Array] = [
	["Hit", CombatValue.Key.HIT],
	["Crit", CombatValue.Key.CRIT_CHANCE],
]

# ASSUMPTION: the verbs' wording; no doc words the intents as text.
## Each [enum EnemyIntent.Kind]'s verb in the intent line, by value.
const INTENT_TEXT: Array[String] = [
	"Attack", "Heal", "Guard", "Advance", "Use an object", "Signature move",
]

# The key the army's effects go under in _effects_by_owner: no instance id is empty.
const _ARMY_KEY: String = ""

## Its instance id.
var unit_id: String = ""
## Its name ([method BattleText.name_of]).
var name: String = ""
## Its unit type's display name ("Battle Medic"; [method BattleText.type_name]).
var type_name: String = ""
## Its unit type's content id, for its sprite; never shown as text.
var type_id: String = ""
## Its side.
var side: CombatFact.CombatSide = CombatFact.CombatSide.NONE
## Whether it is its army's commander.
var is_commander: bool = false
## HP now.
var hp: int = 0
## Maximum HP ([method CombatSession.stats]).
var max_hp: int = 0
## Stance now.
var stance: int = 0
## Stance after a refresh ([constant CombatValue.Key.STANCE_MAX]).
var stance_max: int = 0
## Block now.
var block: int = 0
## The base stats' short names, in [constant HudViewModel.STAT_ROWS] order.
var stat_names: PackedStringArray = []
## The base stats' values, in the same order.
var stat_values: PackedInt32Array = []
## Maximum HP, then the base stats, each with its sources and, for a player unit, its growth.
var stat_rows: Array[ValueRow] = []
## Attack Speed with no exchange under way ([method ExchangeResolver.attack_speed]): SPD less the
## weight CON doesn't carry, effects included.
var attack_speed: int = 0
## The combat values' short names, in [constant COMBAT_ROWS] order.
var combat_names: PackedStringArray = []
## The combat values, in the same order.
var combat_values: PackedInt32Array = []
## Attack Speed, the [constant COMBAT_ROWS] values, then the [constant WEAPON_ROWS] ones, each
## with its sources.
var combat_rows: Array[ValueRow] = []
## Crit chance against an Exposed foe, effects included.
var crit_chance: int = 0
## The crit multiplier, effects included.
var crit_x: float = 0.0
## The Weapon slot; null when it holds nothing.
var weapon: WeaponLine = null
## The stowed weapon in the Pouch; null for none.
var stowed: WeaponLine = null
## The Equipment slot's name; empty for none.
var equipment_name: String = ""
## The Equipment's effect lines.
var equipment_effects: Array[EffectLine] = []
## The Pouch item's name (a consumable or trinket); empty for none or a stowed weapon, which is
## [member stowed].
var pouch_name: String = ""
## The Pouch item's effect lines.
var pouch_effects: Array[EffectLine] = []
## The unit type's traits.
var traits: Array[EffectLine] = []
## Its army's heirlooms and curses; empty for enemies, which have none.
var heirlooms: Array[EffectLine] = []
## Its movement type, readable ("Mounted").
var movement_name: String = ""
## Its tags (Armored, Mounted, Flier, Terror), as content writes them.
var tags: PackedStringArray = []
## Whether it has taken its turn's action, with no second move left.
var has_acted: bool = false
## A player unit's level from its run record; 0 when there is none (an enemy, or no run).
var level: int = 0
## A player unit's XP toward its next level; -1 when there is no run record.
var xp: int = -1
## XP per level ([member CombatRewardRules.xp_per_level]); 0 when [member xp] isn't shown.
var xp_per_level: int = 0
## An enemy's next action as the intents show it, such as "Attack Archer"; empty with no intent,
## for a player unit, or while the intents are hidden.
var intent_text: String = ""
## An enemy's target rule as its intent states it; empty as [member intent_text].
var target_rule_text: String = ""
## An enemy's signature move's name; empty for one without.
var signature_name: String = ""
## The signature move's effect text.
var signature_text: String = ""
## The signature move's counter now, toward [member signature_period].
var signature_count: int = 0
## Events the signature move's counter counts to before it fires; 0 when it has no counter.
var signature_period: int = 0
## Whether the intents show the signature move firing at the coming enemy Phase Start.
var is_signature_next: bool = false
## Its place among its side's units on the map, from 0, for the pop-up's previous and next.
var place: int = 0
## How many units its side has on the map.
var side_count: int = 1


## [param unit_id]'s detail on [param session]; null when it isn't on the map.
## [param run_unit]: its run record, for a player unit's level, XP and growths; null shows none.
## [param shows_intent]: false while the seat's intents are hidden, so the pop-up hides them too.
static func build(
		session: CombatSession,
		unit_id: String,
		run_unit: UnitInstance = null,
		shows_intent: bool = true,
) -> UnitDetailViewModel:
	var state: CombatState = session.state
	if unit_id.is_empty() or not state.has_unit(unit_id):
		return null
	var unit: CombatUnitState = state.unit(unit_id)
	var sheet: StatSheet = session.stats(unit_id)
	var view: UnitDetailViewModel = UnitDetailViewModel.new()
	view.unit_id = unit_id
	view.name = BattleText.name_of(session, unit_id)
	view.type_name = BattleText.type_name(unit.unit_type)
	view.type_id = unit.unit_type
	view.side = unit.side
	view.is_commander = session.commander_ids.values().has(unit_id)
	view.hp = unit.hp
	view.max_hp = sheet.get_int(CombatValue.Key.HP)
	view.stance = unit.stance
	view.stance_max = sheet.get_int(CombatValue.Key.STANCE_MAX)
	view.block = unit.block
	var catalog: EffectCatalog.Index = EffectCatalog.index()
	view.stat_rows.append(_value_row(sheet, "HP", CombatValue.Key.HP))
	for row: Array in HudViewModel.STAT_ROWS:
		view.stat_names.append(row[0] as String)
		view.stat_values.append(sheet.get_int(row[1] as int))
		view.stat_rows.append(_value_row(sheet, row[0] as String, row[1] as int))
	if run_unit != null:
		_add_progress(view, run_unit, catalog)
	# A read: the exchange's rule, with no action in flight, changes nothing.
	view.attack_speed = ExchangeResolver.attack_speed(session.engine, unit_id, null).get_int()
	var speed: ValueRow = ValueRow.new()
	speed.label = "Atk Spd"
	speed.value = view.attack_speed
	view.combat_rows.append(speed)
	for row: Array in COMBAT_ROWS:
		view.combat_names.append(row[0] as String)
		view.combat_values.append(sheet.get_int(row[1] as int))
		view.combat_rows.append(_value_row(sheet, row[0] as String, row[1] as int))
	for row: Array in WEAPON_ROWS:
		view.combat_rows.append(_value_row(sheet, row[0] as String, row[1] as int))
	view.crit_chance = sheet.get_int(CombatValue.Key.CRIT_CHANCE)
	view.crit_x = sheet.get_value(CombatValue.Key.CRIT_X)
	view.movement_name = (
			CombatGrid.MovementType.find_key(unit.movement_type) as String
	).capitalize()
	view.tags = unit.tags.duplicate()
	view.has_acted = unit.has_acted and not unit.is_second_move_pending
	_add_gear(view, session, unit, sheet)
	_add_place(view, state, unit)
	if unit.side == CombatFact.CombatSide.ENEMY:
		_add_enemy(view, session, unit, catalog, shows_intent)
	return view


## The base stats as "MGT 7" pairs, for one line.
func stat_pairs() -> PackedStringArray:
	var pairs: PackedStringArray = []
	for i: int in stat_names.size():
		pairs.append("%s %d" % [stat_names[i], stat_values[i]])
	return pairs


## Attack Speed, then the combat values, as "Avoid 10" pairs, for one line.
func combat_pairs() -> PackedStringArray:
	var pairs: PackedStringArray = ["Atk Spd %d" % [attack_speed]]
	for i: int in combat_names.size():
		pairs.append("%s %d" % [combat_names[i], combat_values[i]])
	return pairs


# Level, XP and each stat row's growth from the unit's run record.
static func _add_progress(
		view: UnitDetailViewModel, run_unit: UnitInstance, catalog: EffectCatalog.Index
) -> void:
	view.level = run_unit.level
	view.xp = run_unit.xp
	var rules: CombatRewardRules = CombatRewardRules.load_default()
	view.xp_per_level = rules.xp_per_level if rules != null else 0
	var unit_type: UnitTypeDefinition = run_unit.definition(catalog)
	for row: ValueRow in view.stat_rows:
		for stat: int in CombatValue.STAT_KEYS:
			if CombatValue.STAT_KEYS[stat] != row.key:
				continue
			var growth: int = run_unit.growth(catalog, stat)
			# A stat the type never grows (the MVP's MOV and CON) shows none unless one is given.
			if growth > 0 or (unit_type != null and unit_type.growths.has(stat)):
				row.growth = growth


# The Weapon, Pouch and Equipment slots and every effect line, grouped by carrier.
static func _add_gear(
		view: UnitDetailViewModel, session: CombatSession, unit: CombatUnitState, sheet: StatSheet
) -> void:
	var state: CombatState = session.state
	var effects: Dictionary[String, Array] = _effects_by_owner(session, unit)
	var held: CombatState.WeaponStats = state.equipped_weapon(unit.id)
	if held != null:
		view.weapon = _weapon_line(session, held, effects)
		view.weapon.hit = sheet.get_int(CombatValue.Key.HIT)
		view.weapon.range_min = sheet.get_int(CombatValue.Key.RANGE_MIN)
		view.weapon.range_max = sheet.get_int(CombatValue.Key.RANGE_MAX)
	if not unit.stowed_weapon_id.is_empty() and unit.stowed_weapon_id != unit.equipped_weapon_id:
		var stowed_stats: CombatState.WeaponStats = state.weapon(unit.stowed_weapon_id)
		if stowed_stats != null:
			view.stowed = _weapon_line(session, stowed_stats, effects)
			# The range it will have in hand: a quivered bow reaches what the Short Quiver gives.
			var reach: Vector2i = ExchangeResolver.weapon_range(
					session.engine, unit.id, unit.stowed_weapon_id
			)
			view.stowed.range_min = reach.x
			view.stowed.range_max = reach.y
	if not unit.equipment_id.is_empty():
		view.equipment_name = BattleText.name_of(session, unit.equipment_id)
		view.equipment_effects = _lines_of(effects, unit.equipment_id)
	if not unit.pouch_item_id.is_empty() and unit.pouch_item_id != unit.stowed_weapon_id:
		view.pouch_name = BattleText.name_of(session, unit.pouch_item_id)
		view.pouch_effects = _lines_of(effects, unit.pouch_item_id)
	view.traits = _lines_of(effects, unit.id)
	view.heirlooms = _lines_of(effects, _ARMY_KEY)


# Its place among its side's units on the map, in the order the state lists them.
static func _add_place(
		view: UnitDetailViewModel, state: CombatState, unit: CombatUnitState
) -> void:
	var units: PackedStringArray = state.units_of(unit.side)
	view.side_count = maxi(units.size(), 1)
	view.place = maxi(units.find(unit.id), 0)


# An enemy's intent and target rule (unless the intents are hidden) and its signature move.
static func _add_enemy(
		view: UnitDetailViewModel,
		session: CombatSession,
		unit: CombatUnitState,
		catalog: EffectCatalog.Index,
		shows_intent: bool,
) -> void:
	var intent: EnemyIntent = null
	if shows_intent and session.intents != null:
		intent = session.intents.intent_of(unit.id)
	if intent != null:
		view.intent_text = INTENT_TEXT[intent.kind] if intent.kind < INTENT_TEXT.size() else ""
		if not intent.target_id.is_empty():
			view.intent_text += " " + BattleText.name_of(session, intent.target_id)
		view.target_rule_text = intent.target_rule_text
		view.is_signature_next = not intent.signature_name.is_empty()
	var enemy_class: EnemyClassDefinition = catalog.enemy_class(unit.unit_type)
	if enemy_class == null or enemy_class.signature_move == null:
		return
	var move: EffectDefinition = enemy_class.signature_move
	view.signature_text = move.describe()
	view.signature_name = enemy_class.signature_name
	for instance: EffectInstance in session.engine.get_instances():
		if instance.definition != move or instance.owner == null:
			continue
		if instance.owner.holder_id != unit.id:
			continue
		if view.signature_name.is_empty():
			view.signature_name = instance.label
		for condition: EffectCondition in move.conditions:
			var counter: CounterCondition = condition as CounterCondition
			if counter != null and counter.mode == CounterCondition.Mode.EVERY_NTH:
				view.signature_period = counter.count
				view.signature_count = instance.get_counter(counter.lane)
		break


# The row for key: its value and, when anything changes it, every applied line of its breakdown
# ("7 base", "+2 Iron Heart"), as the session explains it.
static func _value_row(sheet: StatSheet, label: String, key: int) -> ValueRow:
	var row: ValueRow = ValueRow.new()
	row.label = label
	row.key = key
	var answer: ValueBreakdown = sheet.explain(key)
	row.value = answer.get_int()
	var has_modifier: bool = false
	for line: ValueBreakdown.Line in answer.lines:
		if line.applied and line.modifier != null:
			has_modifier = true
	if not has_modifier:
		return row
	for line: ValueBreakdown.Line in answer.lines:
		if line.applied:
			row.sources.append(line.text)
	return row


# Each effect the unit carries, as an EffectLine, by the id of what carries it: the unit's own
# (traits) under its id, each item's under the item's id, its army's heirlooms under _ARMY_KEY.
static func _effects_by_owner(
		session: CombatSession, unit: CombatUnitState
) -> Dictionary[String, Array]:
	var found: Dictionary[String, Array] = {}
	for instance: EffectInstance in session.engine.get_instances():
		var owner: EffectOwner = instance.owner
		if owner == null or instance.definition == null:
			continue
		var key: String = ""
		match owner.kind:
			EffectOwner.Kind.UNIT, EffectOwner.Kind.ITEM:
				if owner.holder_id != unit.id:
					continue
				key = owner.owner_id
			EffectOwner.Kind.ARMY:
				if unit.side != CombatFact.CombatSide.PLAYER or owner.seat != unit.seat:
					continue
				key = _ARMY_KEY
			_:
				continue
		if not found.has(key):
			found[key] = []
		found[key].append(EffectLine.from_instance(instance))
	return found


# The lines _effects_by_owner found under key, typed; empty for none.
static func _lines_of(effects: Dictionary[String, Array], key: String) -> Array[EffectLine]:
	var lines: Array[EffectLine] = []
	if effects.has(key):
		lines.assign(effects[key])
	return lines


static func _weapon_line(
		session: CombatSession,
		held: CombatState.WeaponStats,
		effects: Dictionary[String, Array],
) -> WeaponLine:
	var line: WeaponLine = WeaponLine.new()
	line.weapon_id = held.id
	line.name = BattleText.name_of(session, held.id)
	line.weapon_type = held.weapon_type.capitalize()
	line.profile = (WeaponTriangle.Profile.find_key(held.profile) as String).capitalize()
	line.is_staff = held.is_staff()
	line.staff_kind = (CombatState.WeaponStats.Staff.find_key(held.staff) as String).capitalize()
	line.staff_amount = held.staff_amount
	line.damage = held.damage
	line.damage_type = (CombatFact.DamageType.find_key(held.damage_type) as String).capitalize()
	line.atk_x = held.atk_x
	line.hit = held.hit
	line.crit = held.crit
	line.crit_x = held.crit_x
	line.weight = held.weight
	line.range_min = held.range_min
	line.range_max = held.range_max
	line.effective_against = held.effective_against.duplicate()
	line.effects = _lines_of(effects, held.id)
	return line


## One value as the pop-up lists it: its short name, its value, the lines of its breakdown and,
## for a player unit's stat, its growth.
class ValueRow:
	extends RefCounted

	## Its short name ("MGT", "Avoid").
	var label: String = ""
	## Its [enum CombatValue.Key]; -1 for Attack Speed, which has no key of its own.
	var key: int = -1
	## Its value now.
	var value: int = 0
	## Every applied line of its breakdown, base first ("7 base", "+2 Iron Heart"); empty when
	## nothing changes it.
	var sources: PackedStringArray = []
	## Its growth, in percent; -1 when not shown (an enemy, a value that never grows, no run).
	var growth: int = -1


## One weapon's profile (game-vision.md, Weapons and equipment: the forecast and the weapon card
## show the exact profile).
class WeaponLine:
	extends RefCounted

	## Its instance id.
	var weapon_id: String = ""
	## Its name.
	var name: String = ""
	## Its weapon type, readable ("Sword").
	var weapon_type: String = ""
	## Its triangle profile, readable ("Nimble"; "None" outside the triangle).
	var profile: String = ""
	## Whether it is a staff, which never counters; [member staff_kind] says which.
	var is_staff: bool = false
	## The staff's kind, readable ("Block", "Heal"); "None" for a weapon.
	var staff_kind: String = ""
	## A staff's Block or heal before Might.
	var staff_amount: int = 0
	## Damage before Might.
	var damage: int = 0
	## Its damage type, readable ("Physical", "Magic").
	var damage_type: String = ""
	## Attacks per turn before the defender's Parry.
	var atk_x: int = 1
	## Hit: on the Weapon slot the unit's, effects included; on a stowed weapon its own.
	var hit: int = 0
	## The weapon's own crit chance.
	var crit: int = 0
	## The weapon's crit multiplier.
	var crit_x: float = 0.0
	## Its weight.
	var weight: int = 0
	## Its shortest range, in tiles: on the Weapon slot the unit's, effects included; on a stowed
	## weapon the unit's once it is swapped in ([method ExchangeResolver.weapon_range]).
	var range_min: int = 1
	## Its longest range, in tiles, as [member range_min].
	var range_max: int = 1
	## The unit tags, weapon types or profiles it is effective against.
	var effective_against: PackedStringArray = []
	## Its effect lines.
	var effects: Array[EffectLine] = []

	## The range as "1" or "2-3".
	func range_text() -> String:
		if range_min == range_max:
			return "%d" % [range_max]
		return "%d-%d" % [range_min, range_max]


## One effect's text, under the name of what carries it.
class EffectLine:
	extends RefCounted

	## The carrier's display name ([member EffectInstance.label]), such as "Iron Heart".
	var label: String = ""
	## The effect text ([method EffectDefinition.describe]).
	var text: String = ""
	## Charges left this period; -1 when unlimited.
	var charges_left: int = -1

	## The line for [param instance].
	static func from_instance(instance: EffectInstance) -> EffectLine:
		var line: EffectLine = EffectLine.new()
		line.label = instance.label
		line.text = instance.definition.describe()
		line.charges_left = instance.charges_left
		return line
