# ==============================================================================
# Bandit Bash
# Copyright (c) 2026 Derc Development
# Licensed under the MIT License. See LICENSE.
#
# File:     value_breakdown.gd
# Author:
# Created:  October 26, 2026
# Modified: October 26, 2026
# ==============================================================================

class_name ValueBreakdown
extends RefCounted
## The answer to a value or permission query: an exact total plus one line per source.
##
## [method compute] applies a key's [Modifier]s in a fixed order: replace base, add, multiply,
## floor and cap, fixed, then the key class's rule clamps. Modifiers are sorted into one canonical
## order first, so the order they were added in never changes the total, even in float math.
## [method compute_permission] answers a permission: any denial beats any grant.[br]
## [member total] stays exact; [method get_int] rounds once by the key's [enum Rounding].[br]
## [b]Thread-safe and silent:[/b] queries run inside sandboxes on worker threads, so problems are
## returned in [member warnings] for the main thread to log, never pushed.
##
## @tutorial(Event bus plan): docs/plans/2026-10-23-event-bus-and-effects.md

## How [method get_int] turns an exact total into a whole number. Each key declares one.
enum Rounding {
	## Halves round up (2.5 is 3, -2.5 is -2). The default, matching damage stage 5 and gold.
	HALF_UP = 0,
	## Rounds down.
	FLOOR = 1,
	## Never rounded by the query; the caller reads [member total] and rounds by its own rule.
	EXACT = 2,
}

## Added before rounding, so float error at an exact half (100 × 0.145 is 14.4999…) can't flip
## the result. Far below any real fraction of a game value.
const ROUNDING_TOLERANCE: float = 1e-9

## The value or permission key this answers.
var key: int = 0

## The exact result. For a permission, 1.0 when allowed and 0.0 when denied.
var total: float = 0.0

## The key's rounding rule, used by [method get_int].
var rounding: Rounding = Rounding.HALF_UP

## Whether this answers a permission rather than a value.
var is_permission: bool = false

## One line per base, modifier and rule clamp, in the order they were applied. Lines that lost a
## collision or were overridden stay, with [member Line.applied] false and a note.
var lines: Array[Line] = []

## Problems found while computing (override collisions, modifiers that can't apply to this key),
## for the main thread to log.
var warnings: PackedStringArray = []


## Use [method compute] or [method compute_permission]; this computes on construction.
func _init(
		value_key: int = 0,
		permission: bool = false,
		base: float = 0.0,
		base_label: String = "",
		modifiers: Array[Modifier] = []
) -> void:
	key = value_key
	is_permission = permission
	if permission:
		_compute_permission(modifiers)
	else:
		_compute_value(base, base_label, modifiers)


## [member total] rounded once by [member rounding]. An [constant EXACT] key rounds half up here;
## its callers are expected to read [member total] instead.
func get_int() -> int:
	return round_to_int(total, rounding)


## For a permission: whether it is allowed.
func is_allowed() -> bool:
	return total != 0.0


## The breakdown as one line of text, applied lines only, such as
## [code]8 base -5 Iron Skin ×0.5 Bulwark = 1.5[/code].
func to_text() -> String:
	var parts: PackedStringArray = []
	for line: Line in lines:
		if line.applied:
			parts.append(line.text)
	if is_permission:
		parts.append("= allowed" if is_allowed() else "= denied")
	else:
		parts.append("= %s" % [_format(total)])
	return " ".join(parts)


func _compute_value(base: float, base_label: String, modifiers: Array[Modifier]) -> void:
	rounding = _rounding_of(key)
	if _is_permission_key(key):
		warnings.append("ValueBreakdown: key %d is a permission" % [key])

	var by_mode: Dictionary[int, Array] = _sorted_by_mode(modifiers)
	var value: float = base
	var shown_label: String = "base" if base_label.is_empty() else base_label
	var base_line: Line = _add_line("%s %s" % [_format(base), shown_label], null)

	var replaced: Array[Modifier] = _typed(by_mode[Modifier.Mode.REPLACE_BASE])
	var replace: Modifier = _pick_override(replaced, "replace-base")
	if replace != null:
		value = replace.value
		base_line.applied = false
		base_line.note = "replaced by %s" % [_name(replace)]
		_add_line(
				"%s %s (instead of %s)" % [_format(replace.value), _name(replace), _format(base)],
				replace
		)
		_add_loser_lines(replaced, replace)

	for modifier: Modifier in _typed(by_mode[Modifier.Mode.ADD]):
		value += modifier.value
		_add_line("%s %s" % [_signed(modifier.value), _name(modifier)], modifier)
	for modifier: Modifier in _typed(by_mode[Modifier.Mode.MULTIPLY]):
		value *= modifier.value
		_add_line("×%s %s" % [_format(modifier.value), _name(modifier)], modifier)

	# ASSUMPTION: the floor applies before the cap, so a cap below a floor wins. No content sets
	# both on one key.
	value = _apply_bound(_typed(by_mode[Modifier.Mode.FLOOR]), value, true)
	value = _apply_bound(_typed(by_mode[Modifier.Mode.CAP]), value, false)

	var fixed_candidates: Array[Modifier] = _typed(by_mode[Modifier.Mode.FIXED])
	var fixed: Modifier = _pick_override(fixed_candidates, "fixed")
	if fixed != null:
		var ignored: PackedStringArray = []
		for line: Line in lines:
			if line.applied:
				line.applied = false
				line.note = "ignored: fixed by %s" % [_name(fixed)]
				ignored.append(line.text)
		value = fixed.value
		var ignoring: String = "" if ignored.is_empty() else " (ignoring %s)" % [", ".join(ignored)]
		_add_line("%s fixed by %s%s" % [_format(value), _name(fixed), ignoring], fixed)
		_add_loser_lines(fixed_candidates, fixed)

	var rule_min: float = _rule_min(key)
	var rule_max: float = _rule_max(key)
	if value < rule_min:
		value = rule_min
		_add_line("at least %s (rule)" % [_format(rule_min)], null)
	if value > rule_max:
		value = rule_max
		_add_line("at most %s (rule)" % [_format(rule_max)], null)
	total = value


func _compute_permission(modifiers: Array[Modifier]) -> void:
	rounding = Rounding.EXACT
	if not _is_permission_key(key):
		warnings.append("ValueBreakdown: key %d is not a permission" % [key])

	var by_mode: Dictionary[int, Array] = _sorted_by_mode(modifiers)
	var grants: Array[Modifier] = _typed(by_mode[Modifier.Mode.GRANT])
	var denies: Array[Modifier] = _typed(by_mode[Modifier.Mode.DENY])
	var default_allowed: bool = _permission_default(key)
	var allowed: bool = default_allowed
	if not grants.is_empty():
		allowed = true
	if not denies.is_empty():
		allowed = false

	var untouched: bool = grants.is_empty() and denies.is_empty()
	_add_line("allowed by default" if default_allowed else "denied by default", null, untouched)
	for modifier: Modifier in grants:
		var note: String = "" if denies.is_empty() else "denial beats grant"
		_add_line("granted by %s" % [_name(modifier)], modifier, denies.is_empty(), note)
	for modifier: Modifier in denies:
		_add_line("denied by %s" % [_name(modifier)], modifier)
	total = 1.0 if allowed else 0.0


# Splits modifiers for this key by mode, each list in canonical order. Skips, with a warning,
# modifiers for another key and modes this query can't apply.
func _sorted_by_mode(modifiers: Array[Modifier]) -> Dictionary[int, Array]:
	var sorted: Array[Modifier] = modifiers.duplicate()
	sorted.sort_custom(func(a: Modifier, b: Modifier) -> bool: return a.sorts_before(b))

	var by_mode: Dictionary[int, Array] = {}
	for mode: int in Modifier.Mode.values():
		var list: Array[Modifier] = []
		by_mode[mode] = list
	var enum_key: bool = CombatValue.ENUM_KEYS.has(key)
	for modifier: Modifier in sorted:
		var problem: String = ""
		if modifier.key != key:
			problem = "is for key %d" % [modifier.key]
		elif modifier.is_permission() != is_permission:
			problem = "has the wrong kind of mode for this key"
		elif (
				enum_key
				and modifier.mode != Modifier.Mode.REPLACE_BASE
				and modifier.mode != Modifier.Mode.FIXED
		):
			problem = "can't add to, scale or bound an enum-valued key"
		if problem.is_empty():
			by_mode[modifier.mode].append(modifier)
		else:
			warnings.append(
					"ValueBreakdown: skipped %s on key %d: it %s" % [_name(modifier), key, problem]
			)
	return by_mode


# Picks the winner among REPLACE_BASE or FIXED candidates, which are in canonical order. Warns
# when a loser's value differs; copies with the winner's value just don't stack.
func _pick_override(candidates: Array[Modifier], kind_name: String) -> Modifier:
	if candidates.is_empty():
		return null
	# ASSUMPTION: on equal specificity the lowest source id (string order) wins; question 9 says
	# only "ties by instance id".
	var winner: Modifier = candidates[0]
	for i: int in range(1, candidates.size()):
		var loser: Modifier = candidates[i]
		if loser.value != winner.value:
			var detail: String = "%s (%s) wins over %s (%s)" % [
				_name(winner),
				winner.source_id,
				_name(loser),
				loser.source_id,
			]
			warnings.append(
					"ValueBreakdown: key %d has competing %s modifiers; %s"
					% [key, kind_name, detail]
			)
	return winner


# Adds an unapplied line for every override candidate except the winner.
func _add_loser_lines(candidates: Array[Modifier], winner: Modifier) -> void:
	for modifier: Modifier in candidates:
		if modifier == winner:
			continue
		var note: String = (
				"a copy doesn't stack" if modifier.value == winner.value
				else "lost to %s" % [_name(winner)]
		)
		_add_line("%s %s" % [_format(modifier.value), _name(modifier)], modifier, false, note)


# Applies the highest floor (is_floor) or the lowest cap; adds a line for every candidate.
func _apply_bound(bounds: Array[Modifier], value: float, is_floor: bool) -> float:
	if bounds.is_empty():
		return value
	var binding: Modifier = bounds[0]
	for modifier: Modifier in bounds:
		if (modifier.value > binding.value) if is_floor else (modifier.value < binding.value):
			binding = modifier
	var word: String = "at least" if is_floor else "at most"
	for modifier: Modifier in bounds:
		var text: String = "%s %s %s" % [word, _format(modifier.value), _name(modifier)]
		if modifier != binding:
			var other: String = "a higher floor" if is_floor else "a lower cap"
			_add_line(text, modifier, false, "%s applies" % [other])
			continue
		var binds: bool = value < binding.value if is_floor else value > binding.value
		_add_line(text, modifier, binds, "" if binds else "not reached")
		if binds:
			value = binding.value
	return value


func _add_line(text: String, modifier: Modifier, applied: bool = true, note: String = "") -> Line:
	var line: Line = Line.new()
	line.text = text
	line.modifier = modifier
	line.applied = applied
	line.note = note
	lines.append(line)
	return line


## Computes [param value_key] from [param base] and [param modifiers].
##
## Modifiers for other keys, permission modifiers, and modes an enum-valued key doesn't take are
## skipped with a warning. [param base_label] names the base in the text ("base" when empty).
static func compute(
		value_key: int, base: float, base_label: String, modifiers: Array[Modifier]
) -> ValueBreakdown:
	return ValueBreakdown.new(value_key, false, base, base_label, modifiers)


## Answers [param permission_key] from [param modifiers]: denied if any denies, else allowed if
## any grants, else the key class's default.
static func compute_permission(permission_key: int, modifiers: Array[Modifier]) -> ValueBreakdown:
	return ValueBreakdown.new(permission_key, true, 0.0, "", modifiers)


## Rounds [param value] to a whole number by [param rule], with [constant ROUNDING_TOLERANCE].
## [constant EXACT] rounds half up, for callers that must have an int anyway.
static func round_to_int(value: float, rule: Rounding) -> int:
	if rule == Rounding.FLOOR:
		return floori(value + ROUNDING_TOLERANCE)
	return floori(value + 0.5 + ROUNDING_TOLERANCE)


static func _typed(list: Array) -> Array[Modifier]:
	var typed: Array[Modifier] = []
	typed.assign(list)
	return typed


static func _rounding_of(value_key: int) -> Rounding:
	if DamageStage.ROUNDING.has(value_key):
		return DamageStage.ROUNDING[value_key] as Rounding
	if CombatValue.ROUNDING.has(value_key):
		return CombatValue.ROUNDING[value_key] as Rounding
	if CampaignValue.ROUNDING.has(value_key):
		return CampaignValue.ROUNDING[value_key] as Rounding
	return Rounding.HALF_UP


static func _rule_min(value_key: int) -> float:
	if DamageStage.RULE_MIN.has(value_key):
		return DamageStage.RULE_MIN[value_key]
	if CombatValue.RULE_MIN.has(value_key):
		return CombatValue.RULE_MIN[value_key]
	if CampaignValue.RULE_MIN.has(value_key):
		return CampaignValue.RULE_MIN[value_key]
	return -INF


static func _rule_max(value_key: int) -> float:
	if DamageStage.RULE_MAX.has(value_key):
		return DamageStage.RULE_MAX[value_key]
	if CombatValue.RULE_MAX.has(value_key):
		return CombatValue.RULE_MAX[value_key]
	if CampaignValue.RULE_MAX.has(value_key):
		return CampaignValue.RULE_MAX[value_key]
	return INF


static func _is_permission_key(value_key: int) -> bool:
	return (
			CombatValue.Permission.values().has(value_key)
			or CampaignValue.Permission.values().has(value_key)
	)


static func _permission_default(permission_key: int) -> bool:
	if CombatValue.PERMISSION_DEFAULTS.has(permission_key):
		return CombatValue.PERMISSION_DEFAULTS[permission_key]
	return CampaignValue.PERMISSION_DEFAULTS.get(permission_key, false)


static func _name(modifier: Modifier) -> String:
	return modifier.source_id if modifier.label.is_empty() else modifier.label


static func _signed(value: float) -> String:
	return "%s%s" % ["-" if value < 0.0 else "+", _format(absf(value))]


# Whole numbers print without a decimal point; others with up to 6 decimals.
static func _format(value: float) -> String:
	if absf(value - roundf(value)) < ROUNDING_TOLERANCE:
		return "%d" % [roundi(value)]
	return String.num(value, 6)


## One applied, overridden or losing contribution to a [ValueBreakdown].
class Line:
	extends RefCounted

	## The contribution as text, such as "+8 Bounty Ledger".
	var text: String = ""
	## The modifier behind the line; [code]null[/code] for the base and for rule clamps.
	var modifier: Modifier = null
	## Whether the line counts toward the total.
	var applied: bool = true
	## Why the line doesn't count, when [member applied] is false.
	var note: String = ""
