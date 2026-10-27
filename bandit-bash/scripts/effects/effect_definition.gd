# ==============================================================================
# Bandit Bash
# Copyright (c) 2026 Derc Development
# Licensed under the MIT License. See LICENSE.
#
# File:     effect_definition.gd
# Author:
# Created:  October 26, 2026
# Modified: October 27, 2026
# ==============================================================================

@tool
class_name EffectDefinition
extends Resource
## One effect: a trigger, a scope, conditions and operations, authored in the inspector.
##
## Items, traits, heirlooms, curses and runes all carry their effects as these
## ([EffectCarrierDefinition]). [b]Read-only at runtime:[/b] Godot shares a loaded .tres, so
## counters, charges and owners live on the effect's runtime instance, never here.[br]
## [method describe] generates the effect text in the effect-triggers.md grammar,
## "[Every Nth] <trigger> by <scope> [this combat | this campaign]: <operation>", so text and
## behavior can't drift. The static helpers name keys and modifiers for every block's text.
##
## @tutorial(Effect triggers): docs/design/effect-triggers.md
## @tutorial(Event bus plan): docs/plans/2026-10-23-event-bus-and-effects.md

## When the effect is checked. Saved in .tres files as an int: [b]append only[/b], with explicit
## values. Combat triggers match [enum CombatFact.Kind]; campaign triggers [enum CampaignFact.Kind].
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

## How "within N" measures, for selectors and position conditions (effect-triggers.md, Position
## and movement; event bus plan, question 38). Saved as an int: [b]append only[/b].
enum Distance {
	## "Within N tiles": tiles up plus tiles across on the grid, ignoring walls and terrain.
	GRID = 0,
	## "Within N movable tiles": the steps the source could take with its own movement type
	## ([method SandboxState.walking_distance]).
	MOVABLE = 1,
}

## Bits of [member tags].
enum Tag {
	## Once any player owns it, it is never offered to anyone else (co-op).
	UNIQUE = 1,
	## A negative heirloom. Curses resolve last among reactions.
	CURSE = 2,
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
	Trigger.GAINED: "Gained",
	Trigger.COMBAT_ENDED: "Combat ended",
	Trigger.LEVELED_UP: "Leveled up",
}

## Effect-text names of the scopes.
const SCOPE_TEXT: Dictionary[int, String] = {
	Scope.THIS_UNIT: "This unit",
	Scope.YOUR_UNIT: "Your Unit",
	Scope.ANY_ALLY_UNIT: "Any Ally Unit",
	Scope.ANY_UNIT: "Any Unit",
}

## Effect-text names of the lanes.
const LANE_TEXT: Dictionary[int, String] = {
	Lane.COMBAT: "this combat",
	Lane.CAMPAIGN: "this campaign",
}

## Content id: snake_case, equal to the file name, unique among effects. Never shown to players.
@export var id: String = ""

## When the effect is checked. [b]Always:[/b] an always-on effect; its operations are modifiers.
@export var trigger: Trigger = Trigger.ALWAYS

## Whose events count, relative to the owner. Heirlooms never use This unit.
@export var scope: Scope = Scope.THIS_UNIT

## Tests that must all pass for the operations to run. A [CounterCondition] supplies the
## "Every Nth" and lane words of the text. Empty: always passes.
@export var conditions: Array[EffectCondition] = []

## What the effect does, in order. Empty is a content error.
@export var operations: Array[EffectOperation] = []

@export_group("Charges")

## Uses before the effect stops working, spent once per activation (potions, staff uses).
##
## [b]0:[/b] no limit. Refilled at the start of [member charge_lane]'s period.
@export_range(0, 99) var charges: int = 0

## When [member charges] refill: every battle (per map) or once per run.
@export var charge_lane: Lane = Lane.COMBAT

@export_group("")

## Content tags. [b]Unique:[/b] never offered to a second player in co-op. [b]Curse:[/b] a negative
## heirloom that resolves last. [b]0:[/b] no tags.
@export_flags("Unique:1", "Curse:2") var tags: int = 0


## The effect text, generated from the data, such as
## [code]Every 7th Attack made by Your Unit this combat: that attack gains lifesteal[/code].
func describe() -> String:
	var counter: CounterCondition = null
	var clauses: PackedStringArray = []
	for condition: EffectCondition in conditions:
		if condition == null:
			continue
		if condition is CounterCondition and counter == null:
			counter = condition
		else:
			clauses.append(condition.describe())

	var head: String = ""
	if trigger != Trigger.ALWAYS:
		head = TRIGGER_TEXT.get(trigger, "Trigger %d" % [trigger])
		if scope != Scope.THIS_UNIT:
			head += " by %s" % [SCOPE_TEXT[scope]]
	if counter != null:
		head = ("%s %s" % [counter.describe_count(), head]).strip_edges()
		head += " %s" % [LANE_TEXT[counter.lane]]
	if head.is_empty() and clauses.is_empty():
		head = TRIGGER_TEXT[Trigger.ALWAYS]

	var opening: PackedStringArray = []
	if not head.is_empty():
		opening.append(head)
	opening.append_array(clauses)
	var actions: PackedStringArray = []
	for operation: EffectOperation in operations:
		if operation != null:
			actions.append(operation.describe_for_trigger(trigger))

	var text: String = "%s: %s" % [", ".join(opening), ", ".join(actions)]
	if charges > 0:
		var uses: String = "use" if charges == 1 else "uses"
		text += " (%d %s %s)" % [charges, uses, LANE_TEXT[charge_lane]]
	return text.left(1).to_upper() + text.substr(1)


## Whether [member tags] includes [param tag].
func has_tag(tag: Tag) -> bool:
	return tags & tag != 0


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


## Effect text for one modifier, such as "+8 Combat Gold", "×0.5 Multipliers stage",
## "Range Max 2 instead of its base", "deny Can Counter" or, for a per-stat key with
## [param stat], "deny Stat Can Grow (SPD)".
static func describe_modifier(
		key: int, mode: Modifier.Mode, value: float, stat: int = Modifier.NO_STAT
) -> String:
	var name: String = key_name(key)
	var stat_name: Variant = CombatValue.Stat.find_key(stat)
	if stat_name != null:
		name = "%s (%s)" % [name, stat_name]
	var shown: String = format_number(value)
	if CombatValue.ENUM_KEYS.has(key):
		var type_name: Variant = CombatFact.DamageType.find_key(roundi(value))
		shown = shown if type_name == null else (type_name as String).capitalize()
	match mode:
		Modifier.Mode.REPLACE_BASE:
			return "%s %s instead of its base" % [name, shown]
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
		Modifier.Mode.GRANT:
			return "allow %s" % [name]
		Modifier.Mode.DENY:
			return "deny %s" % [name]
	return "%s %s" % [name, shown]


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
