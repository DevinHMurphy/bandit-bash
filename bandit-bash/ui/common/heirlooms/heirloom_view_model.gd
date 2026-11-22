# ==============================================================================
# Bandit Bash
# Copyright (c) 2026 Derc Development
# Licensed under the MIT License. See LICENSE.
#
# File:     heirloom_view_model.gd
# Author:
# Created:  November 19, 2026
# Modified: November 21, 2026
# ==============================================================================

class_name HeirloomViewModel
extends RefCounted
## One held heirloom or curse copy as the [HeirloomBar] shows it: what it is, and its state read
## from its effects' own counters and charges, never recounted here.
##
## [method for_battle] reads the battle's live instances, so a campaign-lane count copied in at
## Begin, and a resumed battle's saved state, show as they stand. [method for_run] reads the run's
## saved copies ([SeatRun.OwnedHeirloom]) for campaign screens, where only campaign-lane state
## shows: combat-lane counters and charges start over in every battle. A copy follows one counter,
## its first effect's [CounterCondition], and one charge limit, its first effect with charges.
## [method apply_count] follows a COUNTER_CHANGED fact as it plays.
##
## @tutorial(UI lift, Heirloom bar): docs/design/ui-lift.md

## Content id of its [HeirloomDefinition] or [CurseDefinition].
var heirloom_id: String = ""

## Which copy of [member heirloom_id] the seat holds, from 0 in gain order.
var copy: int = 0

## Its name, as players read it.
var display_name: String = ""

## Its tier id, such as [code]uncommon[/code]; a curse's, such as [code]minor[/code].
var tier: String = ""

## Whether it is a curse.
var is_curse: bool = false

## Its symbol; null when its definition has none, so the bar shows its generic mark.
var icon: Texture2D = null

## Each of its effects' text, the same text as everywhere else ([method EffectDefinition.describe]).
var effect_lines: PackedStringArray = []

## [member effect_lines] with their keywords marked, for the tooltip's [EffectText]
## ([method EffectCarrierDefinition.describe_marked]).
var marked_lines: PackedStringArray = []

## Instance ids of its effects in the battle in progress; empty on campaign screens.
var instance_ids: PackedStringArray = []

## Instance id of the effect whose counter it follows in battle; empty with none, or off battle.
var counter_instance_id: String = ""

## Whether a count toward a period shows: an "every Nth" counter whose lane shows here.
var has_counter: bool = false

## The count toward [member period], as its effect holds it.
var counter: int = 0

## N of "every Nth"; 0 when no count shows.
var period: int = 0

## The lane its counter counts in.
var lane: EffectTerms.Lane = EffectTerms.Lane.COMBAT

## Whether its counter passes only on the first event of its lane's period ("First ... this
## combat"), shown here: it shows no count, and is spent once it has fired.
var is_first_only: bool = false

## Whether a charge limit shows.
var has_charges: bool = false

## Charges left until [member charge_lane]'s period refills them; -1 with no limit shown.
var charges_left: int = -1

## Its effect's charges when full.
var charges: int = 0

## The lane its charges refill in.
var charge_lane: EffectTerms.Lane = EffectTerms.Lane.COMBAT

## Whether the next qualifying event fires it: its count at [member period] - 1 and not spent.
var is_ready: bool = false

## Whether it can't fire until its period starts over: no charges left, or a first-only counter
## that already fired. Other heirlooms are never spent by firing.
var is_spent: bool = false

## What the next qualifying event does, for the ready line, such as
## [code]the next time one of your units attacks, ×2 damage for that attack[/code]; empty with
## no count.
var next_text: String = ""


## Follows a COUNTER_CHANGED fact of its counter's effect as it plays: [param amount] is the
## fact's count. The ready and spent looks follow.
func apply_count(amount: int) -> void:
	counter = amount
	_update_state()


## The number on its icon: the count toward its period, else the uses left; empty for neither.
func badge_text() -> String:
	if has_counter:
		return str(counter)
	if has_charges:
		return str(charges_left)
	return ""


# ASSUMPTION: the tooltip footer's wording ("Uncommon heirloom", "7 / 10 this run",
# "Ready: the next time ...", "1 / 1 use left this combat"); ui-lift.md gives only "7 / 10".
## Its tooltip's footer: its tier, then its count toward its period (with the ready line), or that
## a first-only effect is used, then its uses left; one line each.
func footer_text() -> String:
	var lines: PackedStringArray = [tier_text()]
	if has_counter:
		lines.append("%d / %d %s" % [counter, period, EffectTerms.LANE_TEXT[lane]])
		if is_ready and not next_text.is_empty():
			lines.append("Ready: %s." % [next_text])
	if is_first_only and is_spent:
		lines.append("Used %s" % [EffectTerms.LANE_TEXT[lane]])
	if has_charges:
		if charges_left <= 0:
			lines.append("No uses left %s" % [EffectTerms.LANE_TEXT[charge_lane]])
		else:
			lines.append("%d / %d %s left %s" % [
				charges_left, charges, "use" if charges == 1 else "uses",
				EffectTerms.LANE_TEXT[charge_lane],
			])
	return "\n".join(lines)


## Its tier as its tooltip names it: [code]Uncommon heirloom[/code], [code]Minor curse[/code].
func tier_text() -> String:
	var kind: String = "curse" if is_curse else "heirloom"
	if tier.is_empty():
		return kind.capitalize()
	return "%s %s" % [tier.capitalize(), kind]


# Follows effect's counter, condition, at count, when it shows a count or is first-only: an
# "every 1st" counter needs none.
func _follow_counter(effect: EffectDefinition, condition: CounterCondition, count: int) -> void:
	lane = condition.lane
	counter = count
	if condition.mode == CounterCondition.Mode.FIRST:
		is_first_only = true
		return
	if condition.count <= 1:
		return
	has_counter = true
	period = condition.count
	var moment: String = "the next time %s" % [
		EffectTerms.trigger_clause(effect.trigger, effect.scope),
	]
	if effect.trigger == EffectTerms.Trigger.PHASE_START or (
			effect.trigger == EffectTerms.Trigger.PHASE_END
	):
		moment = "at the next %s" % [EffectTerms.TRIGGER_TEXT[effect.trigger]]
	# The ready line is a plain footer, not effect text: its words alone.
	next_text = EffectTerms.plain_text("%s, %s" % [moment, effect.describe_actions()])


# Follows effect's charge limit with left charges, in its lane.
func _follow_charges(effect: EffectDefinition, left: int) -> void:
	has_charges = true
	charges = effect.charges
	charges_left = left
	charge_lane = effect.charge_lane


# Reads the copy's live instances, carrier_ids on session's engine, in its effects' order: its
# first counter and its first charge limit.
func _read_instances(session: CombatSession, carrier_ids: PackedStringArray) -> void:
	var is_counter_found: bool = false
	var is_charge_found: bool = false
	for instance_id: String in carrier_ids:
		var instance: EffectInstance = session.engine.get_instance(instance_id)
		if instance == null or instance.definition == null:
			continue
		instance_ids.append(instance_id)
		var condition: CounterCondition = _counter_of(instance.definition)
		if condition != null and not is_counter_found:
			# ASSUMPTION: a copy with more than one counter (two effects, or two on one effect)
			# follows the first, as its effect text reads first; no content has two.
			is_counter_found = true
			counter_instance_id = instance_id
			_follow_counter(instance.definition, condition, instance.get_counter(condition.lane))
		if instance.definition.charges > 0 and not is_charge_found:
			is_charge_found = true
			_follow_charges(instance.definition, instance.charges_left)
	_update_state()


# Reads owned, a saved copy of definition: its first counter and first charge limit, each only
# when it lasts the run.
func _read_owned(definition: HeirloomDefinition, owned: SeatRun.OwnedHeirloom) -> void:
	var is_counter_found: bool = false
	var is_charge_found: bool = false
	for effect: EffectDefinition in definition.effects:
		if effect == null:
			continue
		var condition: CounterCondition = _counter_of(effect)
		if condition != null and not is_counter_found:
			is_counter_found = true
			if condition.lane == EffectTerms.Lane.CAMPAIGN:
				var count: int = owned.counters.get(effect.id, 0)
				_follow_counter(effect, condition, count)
		if effect.charges > 0 and not is_charge_found:
			is_charge_found = true
			if effect.charge_lane == EffectTerms.Lane.CAMPAIGN:
				var left: int = owned.charges.get(effect.id, effect.charges)
				_follow_charges(effect, left)
	_update_state()


func _update_state() -> void:
	is_spent = (has_charges and charges_left <= 0) or (is_first_only and counter > 0)
	is_ready = has_counter and not is_spent and counter == period - 1


## Seat [param seat]'s heirloom and curse copies in the battle in progress on [param session],
## the seat's map, in gain order, each read from its live instances
## ([method CampaignSession.heirloom_copies]). [param catalog]: where definitions are found;
## null for the content catalog. Empty with no campaign or session.
static func for_battle(
		campaign: CampaignSession,
		session: CombatSession,
		seat: int,
		catalog: EffectCatalog.Index = null
) -> Array[HeirloomViewModel]:
	var views: Array[HeirloomViewModel] = []
	if campaign == null or session == null:
		return views
	var definitions: EffectCatalog.Index = catalog if catalog != null else EffectCatalog.index()
	for held: CampaignSession.HeirloomLane in campaign.heirloom_copies(seat):
		var definition: HeirloomDefinition = definitions.heirloom(held.heirloom_id)
		if definition == null:
			continue
		var view: HeirloomViewModel = _from_definition(definition, held.copy)
		view._read_instances(session, held.carrier_ids)
		views.append(view)
	return views


## [param seat_run]'s heirloom and curse copies in gain order, for campaign screens: each one's
## campaign-lane counter and charges as the run saved them ([SeatRun.OwnedHeirloom]); combat-lane
## ones don't show. [param catalog]: where definitions are found; null for the content catalog.
static func for_run(
		seat_run: SeatRun, catalog: EffectCatalog.Index = null
) -> Array[HeirloomViewModel]:
	var views: Array[HeirloomViewModel] = []
	if seat_run == null:
		return views
	var definitions: EffectCatalog.Index = catalog if catalog != null else EffectCatalog.index()
	var copies: Dictionary[String, int] = {}
	for owned: SeatRun.OwnedHeirloom in seat_run.heirlooms:
		var copy_index: int = copies.get(owned.heirloom_id, 0)
		copies[owned.heirloom_id] = copy_index + 1
		var definition: HeirloomDefinition = definitions.heirloom(owned.heirloom_id)
		if definition == null:
			continue
		var view: HeirloomViewModel = _from_definition(definition, copy_index)
		view._read_owned(definition, owned)
		views.append(view)
	return views


# A copy of definition, its state not read yet.
static func _from_definition(definition: HeirloomDefinition, copy_index: int) -> HeirloomViewModel:
	var view: HeirloomViewModel = HeirloomViewModel.new()
	view.heirloom_id = definition.id
	view.copy = copy_index
	view.display_name = definition.display_name
	view.tier = definition.tier
	view.is_curse = definition is CurseDefinition
	view.icon = definition.icon
	view.effect_lines = definition.describe()
	view.marked_lines = definition.describe_marked()
	return view



# The first CounterCondition among effect's conditions, as its text reads it; null for none.
static func _counter_of(effect: EffectDefinition) -> CounterCondition:
	for condition: EffectCondition in effect.conditions:
		if condition is CounterCondition:
			return condition as CounterCondition
	return null
