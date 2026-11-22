# ==============================================================================
# Bandit Bash
# Copyright (c) 2026 Derc Development
# Licensed under the MIT License. See LICENSE.
#
# File:     effect_terms.gd
# Author:
# Created:  October 29, 2026
# Modified: November 21, 2026
# ==============================================================================

@tool
class_name EffectTerms
extends RefCounted
## The effect model's shared vocabulary: the trigger, scope, lane and side enums, their
## effect-text names, and the text and inspector-hint helpers every block uses.
##
## [EffectDefinition], blocks, the engine and content use them. Pure and static; never instanced.
## [b]A leaf:[/b] this script names only value classes ([CombatValue], [CampaignValue],
## [DamageStage], [Modifier], [ValueBreakdown], [CombatFact]), never [EffectDefinition], a block,
## or anything that reaches them. When scripts [EffectDefinition] depends on read its members,
## Godot 4.7 crashes at exit and leaks scripts (likely godotengine/godot#117975, fixed for 4.8),
## so new shared enums and text helpers go here, not on [EffectDefinition].[br]
## [b]Markup:[/b] the text constants and helpers return keyword-tagged text
## ([code][kw=block]Block[/kw][/code], [method mark]) for [EffectText]; [method plain_text] gives
## the words alone, as [method EffectDefinition.describe] and [method describe_modifier] do.
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

## What happens in each unit trigger, as a clause with its subject ([constant SUBJECT_TEXT]) in
## place of [code]%s[/code]: "%s attacks". Effect text opens "Whenever <clause>", or "Every 7th
## time <clause> each combat" with a counter ([method trigger_head]). A unit trigger not listed
## reads "On <trigger>".
const TRIGGER_CLAUSE_TEXT: Dictionary[int, String] = {
	Trigger.UNIT_TURN_START: "%s starts its turn",
	Trigger.BEFORE_COMBAT: "%s enters an exchange",
	Trigger.AFTER_COMBAT: "%s finishes an exchange",
	Trigger.UNIT_TURN_END: "%s ends its turn",
	Trigger.ATTACK_MADE: "%s attacks",
	Trigger.HIT_DEALT: "%s lands a hit",
	Trigger.HIT_TAKEN: "%s is hit",
	Trigger.MISSED: "%s misses",
	Trigger.DODGED: "%s dodges",
	Trigger.DAMAGE_DEALT: "%s deals [kw=damage]damage[/kw]",
	Trigger.DAMAGE_TAKEN: "%s takes [kw=damage]damage[/kw]",
	Trigger.CRIT_DEALT: "%s lands a crit",
	Trigger.CRIT_TAKEN: "%s takes a crit",
	Trigger.EXPOSED: "%s becomes [kw=exposed]Exposed[/kw]",
	Trigger.DEFEATED_AN_ENEMY: "%s defeats an enemy",
	Trigger.DEFEATED: "%s is defeated",
	Trigger.HEALED_AN_ALLY: "%s [kw=heal]heals[/kw] an ally",
	Trigger.HEALED: "%s is [kw=heal]healed[/kw]",
	Trigger.USED_STAFF_ON_ALLY: "%s uses a staff on an ally",
	Trigger.DARKNESS_DAMAGE_TAKEN: "%s takes [kw=darkness]darkness[/kw] [kw=damage]damage[/kw]",
	Trigger.OBJECT_USED: "%s uses an object",
	Trigger.SHOVED_A_UNIT: "%s shoves a unit",
	Trigger.SHOVED: "%s is shoved",
	Trigger.BLOCK_GAINED: "%s gains [kw=block]Block[/kw]",
	Trigger.MOVED_AFTER_ACTING: "%s moves after acting",
	Trigger.LEVELED_UP: "%s levels up",
}

## The subject of a unit trigger's clause for each scope, in plain words: "Whenever one of your
## units is defeated", not the scope's inspector name ([constant SCOPE_TEXT]).
const SUBJECT_TEXT: Dictionary[int, String] = {
	Scope.THIS_UNIT: "this unit",
	Scope.YOUR_UNIT: "one of your units",
	Scope.ANY_ALLY_UNIT: "an ally",
	Scope.ANY_UNIT: "any unit",
}

## The words before a phase trigger's name for each scope: a phase is a side's, not a unit's, so
## Your Unit's is just "At Phase Start" and the wider scopes name whose phase counts ("At each
## allied Phase Start", "At every Phase Start").
const PHASE_SCOPE_TEXT: Dictionary[int, String] = {
	Scope.THIS_UNIT: "",
	Scope.YOUR_UNIT: "",
	Scope.ANY_ALLY_UNIT: "each allied ",
	Scope.ANY_UNIT: "every ",
}

## Effect-text names of the scopes, for the inspector and content errors; effect text names a
## scope by [constant SUBJECT_TEXT].
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
	CombatValue.Permission.SKIP_MITIGATION_ON_CRIT: "crits skip [kw=mitigation]Mitigation[/kw]",
	CombatValue.Permission.CAN_PICK_LOCKS: "can pick locks",
	CombatValue.Permission.CAN_GAIN_BLOCK: "can gain [kw=block]Block[/kw]",
	CombatValue.Permission.CAN_LOOT: "can loot",
	CombatValue.Permission.HEX_STORM: "its Curse is a Hex Storm",
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
	CombatValue.Permission.SKIP_MITIGATION_ON_CRIT: (
			"crits don't skip [kw=mitigation]Mitigation[/kw]"
	),
	CombatValue.Permission.CAN_PICK_LOCKS: "can't pick locks",
	CombatValue.Permission.CAN_GAIN_BLOCK: "can't gain [kw=block]Block[/kw]",
	CombatValue.Permission.CAN_LOOT: "can't loot",
	CombatValue.Permission.HEX_STORM: "its Curse isn't a Hex Storm",
	CampaignValue.Permission.INTENTS_HIDDEN: "enemy intents show",
	CampaignValue.Permission.STAT_CAN_GROW: "%s can't grow",
}

# ASSUMPTION: "this run" for the campaign lane, as the menus say "Continue Run" (P01 question 67).
## Effect-text names of the lanes, as the period now running: "3 / 7 this combat".
const LANE_TEXT: Dictionary[int, String] = {
	Lane.COMBAT: "this combat",
	Lane.CAMPAIGN: "this run",
}

## A counter's lane after its count in effect text: "The first time this unit is hit each combat"
## (it starts over every combat), "Every 10th time … this run" (it never does).
const COUNT_LANE_TEXT: Dictionary[int, String] = {
	Lane.COMBAT: "each combat",
	Lane.CAMPAIGN: "this run",
}

## A charge limit's lane in effect text: "(once per combat)".
const CHARGE_LANE_TEXT: Dictionary[int, String] = {
	Lane.COMBAT: "per combat",
	Lane.CAMPAIGN: "per run",
}

## The count word of a first-only counter, for [method trigger_head].
const FIRST_COUNT: String = "first"

# ASSUMPTION: these names, proposed in P01 question 66, until the user's wording pass confirms them.
## Player-facing names of the value keys in effect text, after a signed amount: "+1 max Stance",
## "+8 Gold per won combat". A key not listed reads [method key_name] (base stats keep their
## abbreviations). A key in [constant PERCENT_KEYS] shows its amount as a percent.
const KEY_TEXT: Dictionary[int, String] = {
	CombatValue.Key.NET_WEIGHT: "Weight",
	CombatValue.Key.ATK_X: "[kw=atk_x]AtkX[/kw]",
	CombatValue.Key.CRIT_CHANCE: "[kw=crit]Crit[/kw]",
	CombatValue.Key.CRIT_X: "[kw=crit_x]CritX[/kw]",
	CombatValue.Key.STANCE_MAX: "max [kw=stance]Stance[/kw]",
	CombatValue.Key.SHOVE_DISTANCE: "Shove distance",
	CombatValue.Key.RANGE_MIN: "min [kw=range]Range[/kw]",
	CombatValue.Key.RANGE_MAX: "max [kw=range]Range[/kw]",
	CombatValue.Key.DAMAGE_TYPE: "[kw=damage]damage[/kw] type",
	CombatValue.Key.EFFECTIVE_MODIFIER: "effectiveness",
	CombatValue.Key.STAFF_AMOUNT: "staff amount",
	CampaignValue.Key.COMBAT_GOLD: "[kw=gold]Gold[/kw] per won combat",
	CampaignValue.Key.GRADE_BONUS_PERCENT: "grade bonus",
	CampaignValue.Key.SHARED_XP_PERCENT: "shared [kw=xp]XP[/kw]",
	CampaignValue.Key.UNIT_XP_PERCENT: "[kw=xp]XP[/kw]",
	CampaignValue.Key.SCRAP_PERCENT: "of the price when scrapping",
	CampaignValue.Key.ARMORY_STOCK: "[kw=armory]Armory[/kw] items",
	CampaignValue.Key.GUILDHALL_RECRUITS: "[kw=guildhall]Guildhall[/kw] recruits",
	CampaignValue.Key.PRICE_PERCENT: "shop prices",
	CampaignValue.Key.FREE_REROLLS: "free rerolls",
	CampaignValue.Key.MAX_ARMY_SIZE: "max army size",
	CampaignValue.Key.EXTRA_ENEMIES: "enemies per combat",
	CampaignValue.Key.HEALING_RECEIVED_PERCENT: "[kw=heal]healing[/kw] received",
	CampaignValue.Key.LEVEL_UP_GUARANTEED_GAINS: "stat points per level-up",
	CampaignValue.Key.LEVEL_UP_MIN_STATS: "stats raised per level-up",
	CampaignValue.Key.DARKNESS_ARRIVAL_OFFSET: (
			"turns before the [kw=darkness]darkness[/kw] arrives"
	),
	CampaignValue.Key.POUCH_ITEM_WEIGHT: "weight per [kw=pouch]Pouch[/kw] item",
	CampaignValue.Key.LEVEL_UP_RANDOM_GAINS: "random stat points per level-up",
}

## [constant KEY_TEXT]'s name for an amount of exactly 1 or -1, where it differs: "+1 free
## reroll".
const KEY_TEXT_ONE: Dictionary[int, String] = {
	CampaignValue.Key.ARMORY_STOCK: "[kw=armory]Armory[/kw] item",
	CampaignValue.Key.GUILDHALL_RECRUITS: "[kw=guildhall]Guildhall[/kw] recruit",
	CampaignValue.Key.FREE_REROLLS: "free reroll",
	CampaignValue.Key.LEVEL_UP_GUARANTEED_GAINS: "stat point per level-up",
	CampaignValue.Key.EXTRA_ENEMIES: "enemy per combat",
	CampaignValue.Key.DARKNESS_ARRIVAL_OFFSET: "turn before the [kw=darkness]darkness[/kw] arrives",
	CampaignValue.Key.LEVEL_UP_RANDOM_GAINS: "random stat point per level-up",
}

## Keys whose amount is in percent or percentage points, shown with a percent sign: "+25% XP".
const PERCENT_KEYS: Array[int] = [
	CampaignValue.Key.GRADE_BONUS_PERCENT,
	CampaignValue.Key.SHARED_XP_PERCENT,
	CampaignValue.Key.UNIT_XP_PERCENT,
	CampaignValue.Key.SCRAP_PERCENT,
	CampaignValue.Key.PRICE_PERCENT,
	CampaignValue.Key.HEALING_RECEIVED_PERCENT,
]

## The game terms effect text names, spelled and capitalized the same everywhere and marked
## with a keyword tag ([constant KEYWORD_IDS]). The content test fails text that writes one in
## lower case ("block"), except the terms that are also plain words ("that attack", "lands a
## hit", "at range 2", "the darkness"), and fails a keyword left unmarked.
const KEYWORDS: PackedStringArray = [
	"Block", "Stance", "Exposed", "Mitigation", "Phase Start", "Phase End", "Attack",
	"Attack Speed", "AtkX", "Parry", "Hit", "Avoid", "Crit", "CritX", "Movement", "Range", "HP",
	"MGT", "SPD", "DEF", "RES", "CON", "Gold", "XP", "Pouch", "Armory", "Guildhall", "Magic",
	"Physical", "damage", "heal", "Darkness",
]

## Each keyword's stable id, by its [constant KEYWORDS] spelling: what a tag names, so the shown
## word may change (a translation, "heals") while the glossary entry stays. Ids are snake_case
## and never change; data/keywords/ holds one glossary entry per id.
const KEYWORD_IDS: Dictionary[String, String] = {
	"Block": "block", "Stance": "stance", "Exposed": "exposed", "Mitigation": "mitigation",
	"Phase Start": "phase_start", "Phase End": "phase_end", "Attack": "attack",
	"Attack Speed": "attack_speed", "AtkX": "atk_x", "Parry": "parry", "Hit": "hit",
	"Avoid": "avoid", "Crit": "crit", "CritX": "crit_x", "Movement": "movement",
	"Range": "range", "HP": "hp", "MGT": "mgt", "SPD": "spd", "DEF": "def", "RES": "res",
	"CON": "con", "Gold": "gold", "XP": "xp", "Pouch": "pouch", "Armory": "armory",
	"Guildhall": "guildhall", "Magic": "magic", "Physical": "physical", "damage": "damage",
	"heal": "heal", "Darkness": "darkness",
}

## How a keyword tag opens: [code][kw=<id>]Word[/kw][/code], the word as shown.
const KEYWORD_OPEN: String = "[kw="

## How a keyword tag closes.
const KEYWORD_CLOSE: String = "[/kw]"

## Effect-text names of the damage stage keys, as players read a change to them ("+2 Attack for
## that hit", "×0.5 damage taken"); [method key_name] keeps the stage names for the inspector.
const STAGE_TEXT: Dictionary[int, String] = {
	DamageStage.Key.ATTACK: "[kw=attack]Attack[/kw]",
	DamageStage.Key.MITIGATION: "[kw=mitigation]Mitigation[/kw]",
	DamageStage.Key.CRITICAL: "crit [kw=damage]damage[/kw]",
	DamageStage.Key.MULTIPLIERS: "[kw=damage]damage[/kw]",
	DamageStage.Key.INCOMING_MULTIPLIERS: "[kw=damage]damage[/kw] taken",
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


## The opening phrase of a triggered effect's text for [param trigger] under [param scope], with
## no comma: "Whenever one of your units is defeated", "At Phase Start", "Upon pickup"; empty for
## Always. [param count]: empty for every time, [constant FIRST_COUNT], or an ordinal ("7th"),
## counted in [param lane]: "The first time this unit is hit each combat", "Every 7th time one of
## your units attacks each combat", "At the first Phase Start each combat".
static func trigger_head(
		trigger: int, scope: int, count: String = "", lane: int = Lane.COMBAT
) -> String:
	var period: String = COUNT_LANE_TEXT.get(lane, "")
	match trigger:
		Trigger.ALWAYS:
			return ""
		Trigger.GAINED:
			return "Upon pickup"
		Trigger.COMBAT_ENDED:
			if count.is_empty():
				return "At the end of each combat"
			if count == FIRST_COUNT:
				return "At the end of the first combat"
			return "At the end of every %s combat" % [count]
		Trigger.PHASE_START, Trigger.PHASE_END:
			var phase: String = mark(TRIGGER_TEXT[trigger])
			if count.is_empty():
				return "At %s%s" % [PHASE_SCOPE_TEXT.get(scope, ""), phase]
			var allied: String = "allied " if scope == Scope.ANY_ALLY_UNIT else ""
			if count == FIRST_COUNT:
				return "At the first %s%s %s" % [allied, phase, period]
			return "At every %s %s%s %s" % [count, allied, phase, period]
	var clause: String = trigger_clause(trigger, scope)
	if count == FIRST_COUNT:
		return "The first time %s %s" % [clause, period]
	if not count.is_empty():
		return "Every %s time %s %s" % [count, clause, period]
	if scope == Scope.THIS_UNIT:
		match trigger:
			Trigger.BEFORE_COMBAT:
				return "Before each exchange"
			Trigger.AFTER_COMBAT:
				return "After each exchange"
			Trigger.UNIT_TURN_START:
				return "At the start of this unit's turn"
			Trigger.UNIT_TURN_END:
				return "At the end of this unit's turn"
			Trigger.DEFEATED:
				return "When %s" % [clause]
	return "Whenever %s" % [clause]


## What happens in a unit trigger, with [param scope]'s subject: "one of your units attacks"
## ([constant TRIGGER_CLAUSE_TEXT], [constant SUBJECT_TEXT]); the heirloom bar's ready line names
## the next event by it.
static func trigger_clause(trigger: int, scope: int) -> String:
	var subject: String = SUBJECT_TEXT.get(scope, "this unit")
	if not TRIGGER_CLAUSE_TEXT.has(trigger):
		return "%s: %s" % [subject, TRIGGER_TEXT.get(trigger, "Trigger %d" % [trigger])]
	return TRIGGER_CLAUSE_TEXT[trigger] % [subject]


## The player-facing name of [param key] in effect text for an amount of [param value], marked
## ([constant KEY_TEXT], [constant KEY_TEXT_ONE], a damage stage's [constant STAGE_TEXT]), else
## [method key_name], marked when it is a keyword ("SPD").
static func text_name(key: int, value: float = 0.0) -> String:
	if is_equal_approx(absf(value), 1.0) and KEY_TEXT_ONE.has(key):
		return KEY_TEXT_ONE[key]
	if KEY_TEXT.has(key):
		return KEY_TEXT[key]
	if STAGE_TEXT.has(key):
		return STAGE_TEXT[key]
	return mark_if_keyword(key_name(key))


## [param parts] as one English list: "a", "a and b", "a, b and c".
static func join_list(parts: PackedStringArray) -> String:
	if parts.size() <= 1:
		return "".join(parts)
	return "%s and %s" % [", ".join(parts.slice(0, parts.size() - 1)), parts[parts.size() - 1]]


## [param text] as a sentence: its first letter capitalized (inside a keyword tag that opens it)
## and a closing period added unless it ends in one; empty stays empty.
static func sentence(text: String) -> String:
	var trimmed: String = text.strip_edges()
	if trimmed.is_empty():
		return ""
	if not (trimmed.ends_with(".") or trimmed.ends_with("!") or trimmed.ends_with("?")):
		trimmed += "."
	var first: int = 0
	if trimmed.begins_with(KEYWORD_OPEN):
		first = trimmed.find("]") + 1
	return trimmed.left(first) + trimmed.substr(first, 1).to_upper() + trimmed.substr(first + 1)


## A charge limit as effect text: "(once per combat)", "(twice per run)", "(3 times per combat)".
static func describe_charges(charges: int, lane: int) -> String:
	var times: String = "%d times" % [charges]
	if charges == 1:
		times = "once"
	elif charges == 2:
		times = "twice"
	return "(%s %s)" % [times, CHARGE_LANE_TEXT.get(lane, "")]


## Effect text for [param key] allowed ([param is_allowed]) or denied, with no subject and
## marked, such as "can't gain Block" ([constant PERMISSION_DENIED_TEXT]); a per-stat key names
## [param stat], such as "SPD can't grow".
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
			name = "%s (%s)" % [name, mark_if_keyword(str(stat_name))]
		return "%s %s" % ["allow" if is_allowed else "deny", name]
	var phrase: String = phrases[key]
	if phrase.contains("%s"):
		var named: Variant = CombatValue.Stat.find_key(stat)
		phrase = phrase % [mark_if_keyword(str(named)) if named != null else "stats"]
	return phrase


## [method describe_modifier_marked] as plain words, for text no [EffectText] shows (the battle
## log's lines).
static func describe_modifier(
		key: int, mode: Modifier.Mode, value: float, stat: int = Modifier.NO_STAT
) -> String:
	return plain_text(describe_modifier_marked(key, mode, value, stat))


## Effect text for one modifier, marked, such as "+8 Gold per won combat", "+25% XP", "×0.5
## damage" (a damage stage), "max Range becomes 2", "attacks deal Magic damage" or a
## permission's, such as "can't counter" or, for a per-stat key with [param stat], "SPD can't
## grow" ([method describe_permission]); key names by [method text_name].
static func describe_modifier_marked(
		key: int, mode: Modifier.Mode, value: float, stat: int = Modifier.NO_STAT
) -> String:
	if mode == Modifier.Mode.GRANT or mode == Modifier.Mode.DENY:
		return describe_permission(key, mode == Modifier.Mode.GRANT, stat)
	var name: String = text_name(key, value)
	var stat_name: Variant = CombatValue.Stat.find_key(stat)
	if stat_name != null and key == CampaignValue.Key.LEVEL_UP_GUARANTEED_GAINS:
		name = "%s per level-up" % [mark_if_keyword(str(stat_name))]
	elif stat_name != null:
		name = "%s (%s)" % [name, mark_if_keyword(str(stat_name))]
	var shown: String = format_number(value)
	var percent: String = "%" if PERCENT_KEYS.has(key) else ""
	if CombatValue.ENUM_KEYS.has(key):
		var type_name: Variant = CombatFact.DamageType.find_key(roundi(value))
		if type_name != null:
			shown = mark_if_keyword((type_name as String).capitalize())
		if key == CombatValue.Key.DAMAGE_TYPE and type_name != null:
			return "attacks deal %s %s" % [shown, mark("damage")]
	if mode == Modifier.Mode.FLOOR and key == CampaignValue.Key.LEVEL_UP_MIN_STATS:
		return "at least %s %s" % [shown, name]
	match mode:
		Modifier.Mode.REPLACE_BASE:
			return "%s becomes %s%s" % [name, shown, percent]
		Modifier.Mode.ADD:
			return "%s%s%s %s" % [
				"-" if value < 0.0 else "+", format_number(absf(value)), percent, name,
			]
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
## weapon's, marked: "Range becomes 1-2", or "Range becomes 2" when both are the same.
static func describe_range_base(range_min: float, range_max: float) -> String:
	var shown: String = format_number(range_max)
	if absf(range_min - range_max) >= ValueBreakdown.ROUNDING_TOLERANCE:
		shown = "%s-%s" % [format_number(range_min), shown]
	return "%s becomes %s" % [mark("Range"), shown]


## [param word], a [constant KEYWORDS] spelling, as a keyword tag showing [param shown] (the word
## itself when empty): [code]mark("heal", "Heals")[/code] is [code][kw=heal]Heals[/kw][/code].
## An unknown word logs an error and stays unmarked.
static func mark(word: String, shown: String = "") -> String:
	var text: String = word if shown.is_empty() else shown
	if not KEYWORD_IDS.has(word):
		push_error("EffectTerms: not a keyword - %s" % [word])
		return text
	return "%s%s]%s%s" % [KEYWORD_OPEN, KEYWORD_IDS[word], text, KEYWORD_CLOSE]


## [param word] marked when it is a [constant KEYWORDS] spelling ("SPD"), else as it is ("MOV").
static func mark_if_keyword(word: String) -> String:
	return mark(word) if KEYWORD_IDS.has(word) else word


## [param text] with its keyword tags removed and their words kept: "gain 2 Block". Text no
## [EffectText] shows (logs, plain labels, tests of the words) reads this.
static func plain_text(text: String) -> String:
	if not text.contains(KEYWORD_OPEN):
		return text
	var words: PackedStringArray = []
	for piece: PackedStringArray in split_marked(text):
		words.append(piece[1])
	return "".join(words)


## [param text] split into pieces in order, each [code][id, words][/code]: a keyword's id and its
## shown word, or an empty id for plain text. A tag with no id, no "]" or no close ends the
## split: the rest is one plain piece, tags and all, which [method markup_problems] reports.
static func split_marked(text: String) -> Array[PackedStringArray]:
	var pieces: Array[PackedStringArray] = []
	var at: int = 0
	while at < text.length():
		var open: int = text.find(KEYWORD_OPEN, at)
		if open < 0:
			pieces.append(PackedStringArray(["", text.substr(at)]))
			break
		if open > at:
			pieces.append(PackedStringArray(["", text.substr(at, open - at)]))
		var id_start: int = open + KEYWORD_OPEN.length()
		var id_end: int = text.find("]", id_start)
		var close: int = -1 if id_end < 0 else text.find(KEYWORD_CLOSE, id_end)
		if id_end <= id_start or close < 0:
			pieces.append(PackedStringArray(["", text.substr(open)]))
			break
		pieces.append(PackedStringArray([
			text.substr(id_start, id_end - id_start), text.substr(id_end + 1, close - id_end - 1),
		]))
		at = close + KEYWORD_CLOSE.length()
	return pieces


## What is wrong with [param text]'s keyword tags, one line each; empty when every tag names a
## known id ([constant KEYWORD_IDS]), shows a word, and closes, with none nested or left over.
static func markup_problems(text: String) -> PackedStringArray:
	var problems: PackedStringArray = []
	var ids: Array[String] = KEYWORD_IDS.values()
	for piece: PackedStringArray in split_marked(text):
		var id: String = piece[0]
		var words: String = piece[1]
		if id.is_empty():
			if words.contains(KEYWORD_OPEN) or words.contains(KEYWORD_CLOSE):
				problems.append("an unbalanced tag in \"%s\"" % [words])
			continue
		if not ids.has(id):
			problems.append("unknown keyword id \"%s\"" % [id])
		if words.strip_edges().is_empty() or words.contains("["):
			problems.append("keyword \"%s\" shows \"%s\"" % [id, words])
	return problems


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
