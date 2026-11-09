# ==============================================================================
# Bandit Bash
# Copyright (c) 2026 Derc Development
# Licensed under the MIT License. See LICENSE.
#
# File:     unit_detail_view_model.gd
# Author:
# Created:  November 7, 2026
# Modified: November 7, 2026
# ==============================================================================

class_name UnitDetailViewModel
extends RefCounted
## Everything the session holds about one unit on the board, player or enemy, as plain data for the
## [UnitDetailPanel] (combat UI plan, UI11; game-vision.md, Units, Weapons and equipment; Godot_FE's
## combat unit detail screen, minus XP and growths, which are P08's).
##
## [method build] reads state, [method CombatSession.stats] and the effect engine's instances only,
## never changes them, and holds no rule: every number is the session's, every name
## [method BattleText.name_of]'s, every effect line [method EffectDefinition.describe]'s. Effects
## are grouped by what carries them: the unit's traits, each slot's item, and the army's
## heirlooms (army-wide passives, so every unit of the seat lists the same). What the vision lists
## and the session doesn't hold yet (XP, level, prefix, growths) isn't shown.
##
## @tutorial(Combat UI plan): docs/plans/2026-11-04-combat-ui.md

## The combat values the panel lists after Attack Speed, in order: each its short name and
## [enum CombatValue.Key]. Hit, Crit and the range are the weapon's, so they go on its line.
## Attack Speed isn't a row: its key holds only modifiers, on a base the exchange's rule
## computes ([member attack_speed]).
const COMBAT_ROWS: Array[Array] = [
	["Avoid", CombatValue.Key.AVOID],
	["AtkX", CombatValue.Key.ATK_X],
	["Parry", CombatValue.Key.PARRY],
	["Weight", CombatValue.Key.NET_WEIGHT],
	["Shove", CombatValue.Key.SHOVE_DISTANCE],
]

# The key the army's effects go under in _effects_by_owner: no instance id is empty.
const _ARMY_KEY: String = ""

## Its instance id.
var unit_id: String = ""
## Its name ([method BattleText.name_of]).
var name: String = ""
## Its unit type, readable ("Battle Medic" for [code]battle_medic[/code]).
var type_name: String = ""
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
## Attack Speed with no exchange under way ([method ExchangeResolver.attack_speed]): SPD less the
## weight CON doesn't carry, effects included.
var attack_speed: int = 0
## The combat values' short names, in [constant COMBAT_ROWS] order.
var combat_names: PackedStringArray = []
## The combat values, in the same order.
var combat_values: PackedInt32Array = []
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


## [param unit_id]'s detail on [param session]; null when it isn't on the map.
static func build(session: CombatSession, unit_id: String) -> UnitDetailViewModel:
	var state: CombatState = session.state
	if unit_id.is_empty() or not state.has_unit(unit_id):
		return null
	var unit: CombatUnitState = state.unit(unit_id)
	var sheet: StatSheet = session.stats(unit_id)
	var view: UnitDetailViewModel = UnitDetailViewModel.new()
	view.unit_id = unit_id
	view.name = BattleText.name_of(session, unit_id)
	view.type_name = unit.unit_type.capitalize()
	view.side = unit.side
	view.is_commander = session.commander_ids.values().has(unit_id)
	view.hp = unit.hp
	view.max_hp = sheet.get_int(CombatValue.Key.HP)
	view.stance = unit.stance
	view.stance_max = sheet.get_int(CombatValue.Key.STANCE_MAX)
	view.block = unit.block
	for row: Array in HudViewModel.STAT_ROWS:
		view.stat_names.append(row[0] as String)
		view.stat_values.append(sheet.get_int(row[1] as int))
	for row: Array in COMBAT_ROWS:
		view.combat_names.append(row[0] as String)
		view.combat_values.append(sheet.get_int(row[1] as int))
	# A read: the exchange's rule, with no action in flight, changes nothing.
	view.attack_speed = ExchangeResolver.attack_speed(session.engine, unit_id, null).get_int()
	view.crit_chance = sheet.get_int(CombatValue.Key.CRIT_CHANCE)
	view.crit_x = sheet.get_value(CombatValue.Key.CRIT_X)
	view.movement_name = (
			CombatGrid.MovementType.find_key(unit.movement_type) as String
	).capitalize()
	view.tags = unit.tags.duplicate()
	view.has_acted = unit.has_acted and not unit.is_second_move_pending
	var effects: Dictionary[String, Array] = _effects_by_owner(session, unit)
	var held: CombatState.WeaponStats = state.equipped_weapon(unit_id)
	if held != null:
		view.weapon = _weapon_line(session, held, effects)
		view.weapon.hit = sheet.get_int(CombatValue.Key.HIT)
		view.weapon.range_min = sheet.get_int(CombatValue.Key.RANGE_MIN)
		view.weapon.range_max = sheet.get_int(CombatValue.Key.RANGE_MAX)
	if not unit.stowed_weapon_id.is_empty() and unit.stowed_weapon_id != unit.equipped_weapon_id:
		var stowed_stats: CombatState.WeaponStats = state.weapon(unit.stowed_weapon_id)
		if stowed_stats != null:
			view.stowed = _weapon_line(session, stowed_stats, effects)
	if not unit.equipment_id.is_empty():
		view.equipment_name = BattleText.name_of(session, unit.equipment_id)
		view.equipment_effects = _lines_of(effects, unit.equipment_id)
	if not unit.pouch_item_id.is_empty() and unit.pouch_item_id != unit.stowed_weapon_id:
		view.pouch_name = BattleText.name_of(session, unit.pouch_item_id)
		view.pouch_effects = _lines_of(effects, unit.pouch_item_id)
	view.traits = _lines_of(effects, unit_id)
	view.heirlooms = _lines_of(effects, _ARMY_KEY)
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
	## Its shortest range, in tiles: on the Weapon slot the unit's, effects included.
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
