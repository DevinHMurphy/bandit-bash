# ==============================================================================
# Bandit Bash
# Copyright (c) 2026 Derc Development
# Licensed under the MIT License. See LICENSE.
#
# File:     effect_terms.gd
# Author:
# Created:  October 29, 2026
# Modified: November 15, 2026
# ==============================================================================

@tool
class_name EffectTerms
extends RefCounted
## The effect model's shared vocabulary: the trigger, scope, lane and side enums, their
## effect-text names, and the text and inspector-hint helpers every block uses.
##
## [EffectDefinition] declares its trigger, scope and charge lane with these enums and builds its
## text from these names; blocks, the engine and content use them too. Pure and static; never
## instantiated.[br]
## [b]A leaf:[/b] this script names only value classes ([CombatValue], [CampaignValue],
## [DamageStage], [Modifier], [ValueBreakdown], [CombatFact]), never [EffectDefinition], a block,
## or anything that reaches them. When scripts [EffectDefinition] depends on read its members,
## Godot 4.7 crashes at exit and leaks scripts (likely godotengine/godot#117975, fixed for 4.8),
## so new shared enums and text helpers go here, not on [EffectDefinition].
##
## @tutorial(Effect triggers): docs/design/effect-triggers.md
## @tutorial(Event bus plan): docs/plans/2026-10-23-event-bus-and-effects.md

## When the effect is checked. Saved in .tres files as an int: [b]append only[/b], with explicit
## values. Combat triggers match [enum CombatFact.Kind] (Moved after acting: a flagged
## [constant CombatFact.Kind.UNIT_MOVED]); campaign triggers [enum CampaignFact.Kind].
enum Trigger {
	## Always on: no trigger. Its modifiers apply whenever the owner is involved.
	ALWAYS = 0,
	## A side's phase began, after its Block and Stance refresh.
	PHASE_START = 1,
	## A unit's turn began (in its side's Phase Start window).
	UNIT_TURN_START = 2,
	## An exchange began, before the first attack.
	BEFORE_COMBAT = 3,
	## An exchange resolved, for each surviving participant.
	AFTER_COMBAT = 4,
	## A unit's turn ended (in its side's Phase End window).
	UNIT_TURN_END = 5,
	## A side's phase ended.
	PHASE_END = 6,
	## A unit attacked, hit or miss.
	ATTACK_MADE = 7,
	## A unit's attack hit.
	HIT_DEALT = 8,
	## A unit was hit.
	HIT_TAKEN = 9,
	## A unit's attack missed.
	MISSED = 10,
	## A unit dodged an attack.
	DODGED = 11,
	## A unit's damage reached Block or HP.
	DAMAGE_DEALT = 12,
	## Damage reached a unit's Block or HP.
	DAMAGE_TAKEN = 13,
	## A unit landed a critical hit.
	CRIT_DEALT = 14,
	## A unit took a critical hit.
	CRIT_TAKEN = 15,
	## A unit's Stance reached 0.
	EXPOSED = 16,
	## A unit defeated an enemy.
	DEFEATED_AN_ENEMY = 17,
	## A unit was defeated.
	DEFEATED = 18,
	## A unit restored an ally's HP.
	HEALED_AN_ALLY = 19,
	## A unit regained HP.
	HEALED = 20,
	## A unit used a staff on an ally.
	USED_STAFF_ON_ALLY = 21,
	## A unit took darkness damage.
	DARKNESS_DAMAGE_TAKEN = 22,
	## A unit used a map object.
	OBJECT_USED = 23,
	## A unit shoved another.
	SHOVED_A_UNIT = 24,
	## A unit was shoved.
	SHOVED = 25,
	## A unit gained Block.
	BLOCK_GAINED = 26,
	## A unit made its own move after acting ([constant CombatFact.Flag.SECOND_MOVE] on its
	## [constant CombatFact.Kind.UNIT_MOVED]).
	MOVED_AFTER_ACTING = 27,
	## Campaign: this heirloom or item was acquired.
	GAINED = 100,
	## Campaign: a combat ended for the owner, won or lost.
	COMBAT_ENDED = 101,
	## Campaign: a unit leveled up.
	LEVELED_UP = 102,
}

## Whose events count, relative to the effect's owner (effect-triggers.md, Scopes). Saved as an
## int: [b]append only[/b].
enum Scope {
	## Only the unit holding the effect. The default; effect text leaves it out.
	THIS_UNIT = 0,
	## Any unit the owner's player controls. Heirlooms use this or wider.
	YOUR_UNIT = 1,
	## Any friendly unit, co-op partners' units included.
	ANY_ALLY_UNIT = 2,
	## Any unit, friend or foe.
	ANY_UNIT = 3,
}

## How long a counter or charge lasts. Saved as an int: [b]append only[/b].
enum Lane {
	## Resets at the start of every battle ("this combat").
	COMBAT = 0,
	## Resets at the start of a run only ("this campaign").
	CAMPAIGN = 1,
}

## Which side of the owner a unit is on, for selectors and position conditions. Saved as an int:
## [b]append only[/b].
enum UnitSide {
	## Friendly units.
	ALLY = 0,
	## Hostile units.
	ENEMY = 1,
	## Friend or foe.
	ANY = 2,
}

## Effect-text names of the triggers (effect-triggers.md wording).
const TRIGGER_TEXT: Dictionary[int, String] = {
	Trigger.ALWAYS: "Always",
	Trigger.PHASE_START: "Phase Start",
	Trigger.UNIT_TURN_START: "Unit Turn Start",
	Trigger.BEFORE_COMBAT: "Before Combat",
	Trigger.AFTER_COMBAT: "After Combat",
	Trigger.UNIT_TURN_END: "Unit Turn End",
	Trigger.PHASE_END: "Phase End",
	Trigger.ATTACK_MADE: "Attack made",
	Trigger.HIT_DEALT: "Hit dealt",
	Trigger.HIT_TAKEN: "Hit taken",
	Trigger.MISSED: "Missed",
	Trigger.DODGED: "Dodged",
	Trigger.DAMAGE_DEALT: "Damage dealt",
	Trigger.DAMAGE_TAKEN: "Damage taken",
	Trigger.CRIT_DEALT: "Crit dealt",
	Trigger.CRIT_TAKEN: "Crit taken",
	Trigger.EXPOSED: "Exposed",
	Trigger.DEFEATED_AN_ENEMY: "Defeated an enemy",
	Trigger.DEFEATED: "Defeated",
	Trigger.HEALED_AN_ALLY: "Healed an ally",
	Trigger.HEALED: "Healed",
	Trigger.USED_STAFF_ON_ALLY: "Used a staff on an ally",
	Trigger.DARKNESS_DAMAGE_TAKEN: "Darkness damage taken",
	Trigger.OBJECT_USED: "Object used",
	Trigger.SHOVED_A_UNIT: "Shoved a unit",
	Trigger.SHOVED: "Shoved",
	Trigger.BLOCK_GAINED: "Block gained",
	Trigger.MOVED_AFTER_ACTING: "Moved after acting",
	Trigger.GAINED: "Gained",
	Trigger.COMBAT_ENDED: "Combat ended",
	Trigger.LEVELED_UP: "Leveled up",
}

## Effect-text heads of the unit triggers under a scope other than This unit, the scope's name in
## place of [code]%s[/code]: the scope is the trigger's subject, so "When Your Unit is defeated",
## not "Defeated by Your Unit" (which reads as Your Unit defeating). A trigger not listed reads
## "<trigger> by <scope>"; the phase triggers read by [method trigger_head].
const SCOPED_TRIGGER_TEXT: Dictionary[int, String] = {
	Trigger.UNIT_TURN_START: "When %s's turn starts",
	Trigger.BEFORE_COMBAT: "Before %s's combat",
	Trigger.AFTER_COMBAT: "After %s's combat",
	Trigger.UNIT_TURN_END: "When %s's turn ends",
	Trigger.ATTACK_MADE: "When %s attacks",
	Trigger.HIT_DEALT: "When %s deals a hit",
	Trigger.HIT_TAKEN: "When %s is hit",
	Trigger.MISSED: "When %s misses",
	Trigger.DODGED: "When %s dodges",
	Trigger.DAMAGE_DEALT: "When %s deals damage",
	Trigger.DAMAGE_TAKEN: "When %s takes damage",
	Trigger.CRIT_DEALT: "When %s lands a crit",
	Trigger.CRIT_TAKEN: "When %s takes a crit",
	Trigger.EXPOSED: "When %s is Exposed",
	Trigger.DEFEATED_AN_ENEMY: "When %s defeats an enemy",
	Trigger.DEFEATED: "When %s is defeated",
	Trigger.HEALED_AN_ALLY: "When %s heals an ally",
	Trigger.HEALED: "When %s is healed",
	Trigger.USED_STAFF_ON_ALLY: "When %s uses a staff on an ally",
	Trigger.DARKNESS_DAMAGE_TAKEN: "When %s takes darkness damage",
	Trigger.OBJECT_USED: "When %s uses an object",
	Trigger.SHOVED_A_UNIT: "When %s shoves a unit",
	Trigger.SHOVED: "When %s is shoved",
	Trigger.BLOCK_GAINED: "When %s gains Block",
	Trigger.MOVED_AFTER_ACTING: "When %s moves after acting",
	Trigger.LEVELED_UP: "When %s levels up",
}

## The words before a phase trigger's name for each scope: a phase is a side's, not a unit's, so
## Your Unit's is just "Phase Start" and the wider scopes name whose phase counts.
const PHASE_SCOPE_TEXT: Dictionary[int, String] = {
	Scope.THIS_UNIT: "",
	Scope.YOUR_UNIT: "",
	Scope.ANY_ALLY_UNIT: "Allied ",
	Scope.ANY_UNIT: "Any ",
}

## Effect-text names of the scopes.
const SCOPE_TEXT: Dictionary[int, String] = {
	Scope.THIS_UNIT: "This unit",
	Scope.YOUR_UNIT: "Your Unit",
	Scope.ANY_ALLY_UNIT: "Any Ally Unit",
	Scope.ANY_UNIT: "Any Unit",
}

## Effect text of each permission allowed, with no subject ("can gain Block"); [code]%s[/code] is
## a per-stat key's stat, or "stats" for every stat. A permission not listed reads
## "allow <name>". Keep its keys equal to [constant PERMISSION_DENIED_TEXT]'s.
const PERMISSION_ALLOWED_TEXT: Dictionary[int, String] = {
	CombatValue.Permission.CAN_COUNTER: "can counter",
	CombatValue.Permission.CAN_BE_SHOVED: "can be shoved",
	CombatValue.Permission.MAY_MOVE_AFTER_ACTING: "may move after acting",
	CombatValue.Permission.FREE_WEAPON_SWAP: "may swap weapons for free once per turn",
	CombatValue.Permission.SKIP_MITIGATION_ON_CRIT: "crits skip Mitigation",
	CombatValue.Permission.CAN_PICK_LOCKS: "can pick locks",
	CombatValue.Permission.CAN_GAIN_BLOCK: "can gain Block",
	CombatValue.Permission.CAN_LOOT: "can loot",
	CampaignValue.Permission.INTENTS_HIDDEN: "enemy intents are hidden",
	CampaignValue.Permission.STAT_CAN_GROW: "%s can grow",
}

## Effect text of each permission denied, as [constant PERMISSION_ALLOWED_TEXT]
## ("can't gain Block"). A permission not listed reads "deny <name>".
const PERMISSION_DENIED_TEXT: Dictionary[int, String] = {
	CombatValue.Permission.CAN_COUNTER: "can't counter",
	CombatValue.Permission.CAN_BE_SHOVED: "can't be shoved",
	CombatValue.Permission.MAY_MOVE_AFTER_ACTING: "can't move after acting",
	CombatValue.Permission.FREE_WEAPON_SWAP: "can't swap weapons for free",
	CombatValue.Permission.SKIP_MITIGATION_ON_CRIT: "crits don't skip Mitigation",
	CombatValue.Permission.CAN_PICK_LOCKS: "can't pick locks",
	CombatValue.Permission.CAN_GAIN_BLOCK: "can't gain Block",
	CombatValue.Permission.CAN_LOOT: "can't loot",
	CampaignValue.Permission.INTENTS_HIDDEN: "enemy intents show",
	CampaignValue.Permission.STAT_CAN_GROW: "%s can't grow",
}

## Effect-text names of the lanes.
const LANE_TEXT: Dictionary[int, String] = {
	Lane.COMBAT: "this combat",
	Lane.CAMPAIGN: "this campaign",
}

## Effect-text names of the damage stage keys, as players read a change to them ("+2 Attack for
## that hit", "×0.5 damage taken"); [method key_name] keeps the stage names for the inspector.
const STAGE_TEXT: Dictionary[int, String] = {
	DamageStage.Key.ATTACK: "Attack",
	DamageStage.Key.MITIGATION: "Mitigation",
	DamageStage.Key.CRITICAL: "crit damage",
	DamageStage.Key.MULTIPLIERS: "damage",
	DamageStage.Key.INCOMING_MULTIPLIERS: "damage taken",
}


## Display name of a value or permission key, such as "Combat Gold", "Attack stage" or "SPD" (base
## stats keep their abbreviations).
static func key_name(key: int) -> String:
	if CombatValue.STAT_KEYS.values().has(key) and key != CombatValue.Key.MOVEMENT:
		return CombatValue.Key.find_key(key) as String
	var found: Variant = CombatValue.Key.find_key(key)
	if found == null:
		found = CombatValue.Permission.find_key(key)
	if found == null:
		found = CampaignValue.Key.find_key(key)
	if found == null:
		found = CampaignValue.Permission.find_key(key)
	if found != null:
		return (found as String).capitalize()
	var stage: Variant = DamageStage.Key.find_key(key)
	if stage != null:
		return "%s stage" % [(stage as String).capitalize()]
	return "Key %d" % [key]


## An inspector enum hint listing every value key ([CombatValue], [DamageStage],
## [CampaignValue]), for a block's key property.
static func value_key_hint() -> String:
	var entries: PackedStringArray = []
	for keys: Dictionary in [CombatValue.Key, DamageStage.Key, CampaignValue.Key]:
		for name: String in keys:
			var key: int = keys[name]
			entries.append("%s:%d" % [key_name(key), key])
	return ",".join(entries)


## An inspector enum hint listing every permission key.
static func permission_key_hint() -> String:
	var entries: PackedStringArray = []
	for keys: Dictionary in [CombatValue.Permission, CampaignValue.Permission]:
		for name: String in keys:
			var key: int = keys[name]
			entries.append("%s:%d" % [key_name(key), key])
	return ",".join(entries)


## An inspector enum hint listing [constant Modifier.NO_STAT] and every [enum CombatValue.Stat],
## for a block's stat property.
static func stat_hint() -> String:
	var entries: PackedStringArray = ["None:%d" % [Modifier.NO_STAT]]
	for name: String in CombatValue.Stat:
		entries.append("%s:%d" % [name, CombatValue.Stat[name]])
	return ",".join(entries)


## The head of a triggered effect's text for [param trigger] under [param scope]: the trigger's
## name for This unit ("Hit dealt"), the scope as its subject otherwise
## ([constant SCOPED_TRIGGER_TEXT]), and a phase trigger named by whose phase it is
## ([constant PHASE_SCOPE_TEXT]). [param is_counted]: a counter goes before it, so a unit trigger
## keeps the counted "<trigger> by <scope>" ("Every 5th Hit dealt by Your Unit").
static func trigger_head(trigger: int, scope: int, is_counted: bool = false) -> String:
	var name: String = TRIGGER_TEXT.get(trigger, "Trigger %d" % [trigger])
	if trigger == Trigger.PHASE_START or trigger == Trigger.PHASE_END:
		return "%s%s" % [PHASE_SCOPE_TEXT.get(scope, ""), name]
	if scope == Scope.THIS_UNIT:
		return name
	var subject: String = SCOPE_TEXT[scope]
	if is_counted or not SCOPED_TRIGGER_TEXT.has(trigger):
		return "%s by %s" % [name, subject]
	return SCOPED_TRIGGER_TEXT[trigger] % [subject]


## Effect text for [param key] allowed ([param is_allowed]) or denied, with no subject, such as
## "can't gain Block" ([constant PERMISSION_DENIED_TEXT]); a per-stat key names [param stat],
## such as "SPD can't grow".
static func describe_permission(
		key: int, is_allowed: bool, stat: int = Modifier.NO_STAT
) -> String:
	var phrases: Dictionary[int, String] = (
			PERMISSION_ALLOWED_TEXT if is_allowed else PERMISSION_DENIED_TEXT
	)
	if not phrases.has(key):
		var name: String = key_name(key)
		var stat_name: Variant = CombatValue.Stat.find_key(stat)
		if stat_name != null:
			name = "%s (%s)" % [name, stat_name]
		return "%s %s" % ["allow" if is_allowed else "deny", name]
	var phrase: String = phrases[key]
	if phrase.contains("%s"):
		var named: Variant = CombatValue.Stat.find_key(stat)
		phrase = phrase % [named if named != null else "stats"]
	return phrase


## Effect text for one modifier, such as "+8 Combat Gold", "×0.5 damage" (a damage stage, named
## by [constant STAGE_TEXT]), "Range Max becomes 2" or a permission's, such as
## "can't counter" or, for a per-stat key with [param stat], "SPD can't grow"
## ([method describe_permission]).
static func describe_modifier(
		key: int, mode: Modifier.Mode, value: float, stat: int = Modifier.NO_STAT
) -> String:
	if mode == Modifier.Mode.GRANT or mode == Modifier.Mode.DENY:
		return describe_permission(key, mode == Modifier.Mode.GRANT, stat)
	var name: String = STAGE_TEXT.get(key, key_name(key))
	var stat_name: Variant = CombatValue.Stat.find_key(stat)
	if stat_name != null:
		name = "%s (%s)" % [name, stat_name]
	var shown: String = format_number(value)
	if CombatValue.ENUM_KEYS.has(key):
		var type_name: Variant = CombatFact.DamageType.find_key(roundi(value))
		shown = shown if type_name == null else (type_name as String).capitalize()
	match mode:
		Modifier.Mode.REPLACE_BASE:
			return "%s becomes %s" % [name, shown]
		Modifier.Mode.ADD:
			return "%s%s %s" % ["-" if value < 0.0 else "+", format_number(absf(value)), name]
		Modifier.Mode.MULTIPLY:
			return "×%s %s" % [shown, name]
		Modifier.Mode.FLOOR:
			return "%s at least %s" % [name, shown]
		Modifier.Mode.CAP:
			return "%s at most %s" % [name, shown]
		Modifier.Mode.FIXED:
			return "%s always %s" % [name, shown]
	return "%s %s" % [name, shown]


## Effect text for a unit's range set to [param range_min]-[param range_max] in place of its
## weapon's: "Range becomes 1-2", or "Range becomes 2" when both are the same.
static func describe_range_base(range_min: float, range_max: float) -> String:
	var shown: String = format_number(range_max)
	if absf(range_min - range_max) >= ValueBreakdown.ROUNDING_TOLERANCE:
		shown = "%s-%s" % [format_number(range_min), shown]
	return "Range becomes %s" % [shown]


## [param value] for effect text: whole numbers without a decimal point ("3"), others with up to
## 6 decimals ("0.5").
static func format_number(value: float) -> String:
	if absf(value - roundf(value)) < ValueBreakdown.ROUNDING_TOLERANCE:
		return "%d" % [roundi(value)]
	return String.num(value, 6)


## English ordinal of [param number]: 1st, 2nd, 3rd, 4th, 11th, 21st.
static func ordinal(number: int) -> String:
	var suffix: String = "th"
	var last_two: int = absi(number) % 100
	if last_two < 11 or last_two > 13:
		match absi(number) % 10:
			1:
				suffix = "st"
			2:
				suffix = "nd"
			3:
				suffix = "rd"
	return "%d%s" % [number, suffix]
