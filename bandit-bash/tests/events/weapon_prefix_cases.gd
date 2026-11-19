# ==============================================================================
# Bandit Bash
# Copyright (c) 2026 Derc Development
# Licensed under the MIT License. See LICENSE.
#
# File:     weapon_prefix_cases.gd
# Author:
# Created:  November 19, 2026
# Modified: November 19, 2026
# ==============================================================================

extends RefCounted
## Weapon modification cases for tests/events/run_all.gd, with test-only prefixes (+2 weight,
## +2 damage): a sword in the convoy made Heavy (prefix_id set, ITEM_MODIFIED); the archer's bow
## made Heavy and loaded by Loadout with both deltas sourced to the prefix; refusals for a prefix
## of another weapon type, a staff of another kind, a weapon that already has a prefix, an
## unknown prefix, a fallen unit's weapon, and no weapon chosen, each changing nothing.
## Touches no save files.

# The suite that runs this file; tests/case_files.gd finds it by this line.
const SUITE: String = "events"

const Fixture = preload("res://tests/events/event_fixture.gd")

var _report: Callable
var _fx: Fixture = null


func _init(check: Callable) -> void:
	_report = check


func run() -> void:
	_fx = Fixture.new()
	_check("weapon prefix: the catalog and rules load", _fx.is_ready())
	if not _fx.is_ready():
		return
	_test_applied()
	_test_loadout()
	_test_refusals()


func _test_applied() -> void:
	var made: CampaignSession = _fx.session()
	var sword: ItemInstance = _fx.add_to_convoy(made, "simple_sword")
	var result: EventResult = _apply(made, Fixture.HEAVY_SWORD, sword.instance_id)
	_check("weapon prefix: a Standard Sword is made Heavy through its prefix_id", (
			not result.is_rejected() and sword.prefix_id == Fixture.HEAVY_SWORD
			and _fx.kinds(result.facts) == [CampaignFact.Kind.ITEM_MODIFIED]
			and result.facts[0].actor_id == sword.instance_id
			and result.facts[0].definition_id == Fixture.EVENT_ID
	), result.rejected_reason)
	var again: EventResult = _apply(made, Fixture.HEAVY_SWORD, sword.instance_id)
	_check("weapon prefix: a weapon that already has a prefix is refused", (
			again.is_rejected() and again.rejected_reason.contains("already has a prefix")
	), again.rejected_reason)
	var copy: ItemInstance = ItemInstance.restore(sword.capture())
	_check("weapon prefix: the prefix is kept through the roster's item data", (
			copy != null and copy.prefix_id == Fixture.HEAVY_SWORD
	))


func _test_loadout() -> void:
	var made: CampaignSession = _fx.session()
	var seat_run: SeatRun = made.run.seat_run(0)
	var archer: UnitInstance = _fx.unit_of_type(seat_run, "archer")
	var result: EventResult = _apply(made, Fixture.HEAVY_BOW, archer.weapon_id)
	_check("weapon prefix: the archer's bow takes a bow prefix", not result.is_rejected(), (
			result.rejected_reason
	))
	var loaded: Loadout.LoadedUnit = Loadout.load_unit(
			_fx.catalog, archer, seat_run.items, CombatFact.CombatSide.PLAYER, 0, made.ids
	)
	var changes: Dictionary[int, float] = {}
	for instance: EffectInstance in loaded.effects:
		if instance.definition.id != "prefix" or instance.label != "Heavy":
			continue
		for operation: EffectOperation in instance.definition.operations:
			var change: ModifyValue = operation as ModifyValue
			if change != null:
				changes[change.key] = change.value
	var weight: float = changes.get(CombatValue.Key.NET_WEIGHT, 0.0)
	var damage: float = changes.get(DamageStage.Key.ATTACK, 0.0)
	_check("weapon prefix: Loadout applies +2 weight and +2 damage, sourced to the prefix", (
			loaded.is_loaded() and loaded.problems.is_empty()
			and is_equal_approx(weight, float(Fixture.PREFIX_WEIGHT))
			and is_equal_approx(damage, float(Fixture.PREFIX_DAMAGE))
	), "%s %s" % [changes, loaded.problems])


func _test_refusals() -> void:
	var made: CampaignSession = _fx.session()
	var seat_run: SeatRun = made.run.seat_run(0)
	var archer: UnitInstance = _fx.unit_of_type(seat_run, "archer")
	var bow: ItemInstance = seat_run.items[archer.weapon_id]
	var log_size: int = made.run.fact_log.size()
	var wrong_type: EventResult = _apply(made, Fixture.HEAVY_SWORD, bow.instance_id)
	_check("weapon prefix: a sword prefix doesn't fit a bow", (
			wrong_type.is_rejected() and wrong_type.rejected_reason.contains("doesn't fit")
			and bow.prefix_id.is_empty()
	), wrong_type.rejected_reason)
	var medic: UnitInstance = _fx.unit_of_type(seat_run, "battle_medic")
	var staff: StaffDefinition = _fx.catalog.staff(seat_run.items[medic.weapon_id].definition_id)
	var wrong_kind: EventResult = _apply(made, Fixture.HEAL_STAFF, medic.weapon_id)
	_check("weapon prefix: a Heal-staff prefix doesn't fit a staff of another kind", (
			staff != null and staff.staff_kind != ContentIds.STAFF_HEAL
			and wrong_kind.is_rejected() and wrong_kind.rejected_reason.contains("staff")
	), "%s: %s" % [
		"no staff" if staff == null else staff.staff_kind, wrong_kind.rejected_reason,
	])
	var unknown: EventResult = _apply(made, "no_such_prefix", bow.instance_id)
	_check("weapon prefix: an unknown prefix is refused", (
			unknown.is_rejected() and unknown.rejected_reason.contains("catalog")
	))
	var unchosen: EventResult = _apply(made, Fixture.HEAVY_BOW, "")
	_check("weapon prefix: with no weapon chosen it is refused", (
			unchosen.is_rejected() and unchosen.rejected_reason.contains("choose a weapon")
	))
	_fx.fell(seat_run, archer)
	var fallen: EventResult = _apply(made, Fixture.HEAVY_BOW, bow.instance_id)
	_check("weapon prefix: a fallen unit's weapon is refused", (
			fallen.is_rejected() and bow.prefix_id.is_empty()
	), fallen.rejected_reason)
	_check("weapon prefix: no refusal recorded a fact", made.run.fact_log.size() == log_size)


func _apply(made: CampaignSession, prefix_id: String, weapon_id: String) -> EventResult:
	var block: WeaponPrefixOutcome = WeaponPrefixOutcome.new()
	block.prefix_id = prefix_id
	return EventResolver.resolve(_fx.context(
			made, _fx.event_of([block]), EventChoice.new("", weapon_id)
	))


func _check(case_name: String, passed: bool, detail: String = "") -> void:
	_report.call(case_name, passed, detail)
