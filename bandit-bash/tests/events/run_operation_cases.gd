# ==============================================================================
# Bandit Bash
# Copyright (c) 2026 Derc Development
# Licensed under the MIT License. See LICENSE.
#
# File:     run_operation_cases.gd
# Author:
# Created:  November 20, 2026
# Modified: November 20, 2026
# ==============================================================================

extends RefCounted
## The event blocks built on RunOperations, each resolved against a real CampaignRunState with its
## facts: the recruit (an elite prefix at the army's average level, the same draw from the same
## stream, a named type, prefix, level and gear, bad data refused; into a full army refused
## without a unit to dismiss, replacing a named one, never the commander, and refused with room);
## the upgrade (a chosen unit, a commander and a repeat refused, every unit); max army size (+1
## with the convoy following, the Company Charter with its curse, the cap of 8 by greying, by
## refusal and by a partial growth, the requirement reading the seat's own size); the revive into
## a full army; the seat's Cursed Blood halving an event heal; the army-size change through a quit
## and Continue, the heirlooms section at version 2, a version 1 section migrating, and malformed
## changes refused. Saves go through memory and JSON only.

# The suite that runs this file; tests/case_files.gd finds it by this line.
const SUITE: String = "events"

const Fixture = preload("res://tests/events/event_fixture.gd")

const MERCENARY_SIZE: int = 4
const CEILING: int = 8
const NAMED_LEVEL: int = 3
const NAMED_TYPE: String = "archer"
const BUCKLER: String = "buckler"
const BAND: String = "band_of_fortune"
const CURSED_BLOOD: String = "cursed_blood"
const MUSTER_ROLL: String = "muster_roll"
const MAJOR: String = "major"
const HEAL_PERCENT: int = 20
const HALF: float = 50.0
const FULL: float = 100.0

var _report: Callable
var _fx: Fixture = null


func _init(check: Callable) -> void:
	_report = check


func run() -> void:
	_fx = Fixture.new()
	_check("run operations: the catalog and rules load", _fx.is_ready())
	if not _fx.is_ready():
		return
	_test_army_size()
	_test_army_size_cap()
	_test_recruit()
	_test_recruit_named()
	_test_recruit_full_army()
	_test_upgrade()
	_test_revive_full_army()
	_test_cursed_blood()
	_test_save_and_load()
	_test_old_save()


func _test_army_size() -> void:
	var made: CampaignSession = _fx.session()
	var seat_run: SeatRun = made.run.seat_run(0)
	_check("army size: the Mercenary starts at 4, full, its convoy holding 4", (
			RunOperations.max_army_size(seat_run, _fx.catalog) == MERCENARY_SIZE
			and seat_run.army.size() == MERCENARY_SIZE
			and ItemPlacement.convoy_capacity(seat_run, _fx.catalog) == MERCENARY_SIZE
	))
	var grown: EventResult = _resolve(made, [_grow(1)])
	_check("army size: +1 makes 5, the convoy follows, one ARMY_SIZE_CHANGED +1 by the event", (
			not grown.is_rejected()
			and RunOperations.max_army_size(seat_run, _fx.catalog) == MERCENARY_SIZE + 1
			and ItemPlacement.convoy_capacity(seat_run, _fx.catalog) == MERCENARY_SIZE + 1
			and _fx.kinds(grown.facts) == [CampaignFact.Kind.ARMY_SIZE_CHANGED]
			and grown.facts[0].amount == 1 and grown.facts[0].seat == 0
			and grown.facts[0].definition_id == Fixture.EVENT_ID
	), grown.rejected_reason)
	_check("army size: kept as one value change on the seat, named after the event", (
			seat_run.value_changes.size() == 1
			and seat_run.value_changes[0].key == CampaignValue.Key.MAX_ARMY_SIZE
			and is_equal_approx(seat_run.value_changes[0].amount, 1.0)
			and seat_run.value_changes[0].source_id == Fixture.EVENT_ID
			and seat_run.value_changes[0].label == Fixture.EVENT_TITLE
	))
	_check("army size: the requirements' read is the seat's own size", (
			EventRequirements.max_army_size(seat_run, _fx.catalog) == MERCENARY_SIZE + 1
	))
	seat_run.add_heirloom(MUSTER_ROLL)
	_check("army size: an heirloom adds to an event's change", (
			RunOperations.max_army_size(seat_run, _fx.catalog) == MERCENARY_SIZE + 2
	), str(RunOperations.max_army_size(seat_run, _fx.catalog)))

	var charter: EventResult = _resolve_with(_fx.session(), _charter())
	_check("army size: the Company Charter gives +1, then its major curse", (
			not charter.is_rejected()
			and _fx.kinds(charter.facts) == [
				CampaignFact.Kind.ARMY_SIZE_CHANGED, CampaignFact.Kind.GAINED,
			]
			and charter.facts[1].definition_id == _fx.curses_of(MAJOR)[0]
	), "%s %s" % [charter.rejected_reason, _fx.kinds(charter.facts)])


func _test_army_size_cap() -> void:
	var made: CampaignSession = _fx.session()
	var seat_run: SeatRun = made.run.seat_run(0)
	_resolve(made, [_grow(3)])
	var partial: EventResult = _resolve(made, [_grow(3)])
	_check("cap: +3 from 7 adds only 1, to 8, ARMY_SIZE_CHANGED +1", (
			not partial.is_rejected()
			and RunOperations.max_army_size(seat_run, _fx.catalog) == CEILING
			and partial.facts.size() == 1 and partial.facts[0].amount == 1
			and is_equal_approx(seat_run.value_changes[-1].amount, 1.0)
	), "%s %d" % [partial.rejected_reason, RunOperations.max_army_size(seat_run, _fx.catalog)])
	var log_size: int = made.run.fact_log.size()
	var refused: EventResult = _resolve(made, [_grow(1), _gold(10)])
	_check("cap: at 8 the growth is refused, so the whole option changes nothing", (
			refused.is_rejected() and refused.rejected_reason.contains("largest")
			and made.run.fact_log.size() == log_size and seat_run.value_changes.size() == 2
	), refused.rejected_reason)
	var charter: EventDefinition = _charter()
	var ctx: EventContext = _fx.context(made, charter)
	_check("cap: at 8 the Charter is greyed out by its requirement", (
			EventResolver.unmet_reason(ctx).contains("largest")
	), EventResolver.unmet_reason(ctx))
	seat_run.add_heirloom(MUSTER_ROLL)
	_check("cap: an heirloom on top never takes it past 8", (
			RunOperations.max_army_size(seat_run, _fx.catalog) == CEILING
	))

	var at_ceiling: CampaignSession = _fx.session()
	at_ceiling.run.seat_run(0).faction_id = Fixture.FULL_FACTION
	var ceiling_result: EventResult = _resolve(at_ceiling, [_grow(1)])
	_check("cap: a faction at 8 can't grow at all", (
			ceiling_result.is_rejected() and at_ceiling.run.seat_run(0).value_changes.is_empty()
	), ceiling_result.rejected_reason)


func _test_recruit() -> void:
	var made: CampaignSession = _fx.session()
	var seat_run: SeatRun = made.run.seat_run(0)
	_resolve(made, [_grow(1)])
	var level: int = RecruitOffer.level_for(seat_run)
	var hire: RecruitOutcome = _recruit(RecruitOutcome.PrefixRoll.ELITE)
	var result: EventResult = _resolve(made, [hire])
	var joined: UnitInstance = seat_run.army[-1]
	var prefix: UnitPrefixDefinition = _fx.catalog.unit_prefix(joined.prefix_id)
	_check("recruit: with room it joins last, UNIT_RECRUITED by the event, replacing nobody", (
			not result.is_rejected() and seat_run.army.size() == MERCENARY_SIZE + 1
			and _fx.kinds(result.facts) == [CampaignFact.Kind.UNIT_RECRUITED]
			and result.facts[0].actor_id == joined.instance_id
			and result.facts[0].target_id.is_empty()
			and result.facts[0].definition_id == Fixture.EVENT_ID
	), result.rejected_reason)
	_check("recruit: a guaranteed +1 or +2 prefix, at the army's average level", (
			prefix != null and prefix.tier > 0 and joined.level == level
			and RecruitOffer.pool(_fx.catalog).has(joined.unit_type_id)
	), "%s level %d" % [joined.prefix_id, joined.level])
	_check("recruit: it brings its type's starting weapon, and the roster stays whole", (
			not joined.weapon_id.is_empty() and seat_run.items.has(joined.weapon_id)
			and _fx.is_whole(seat_run)
	))

	_resolve(made, [_grow(1)])
	var volunteer: EventResult = _resolve(made, [_recruit(RecruitOutcome.PrefixRoll.NONE)])
	_check("recruit: a volunteer has no prefix", (
			not volunteer.is_rejected()
			and seat_run.army[-1].prefix_id == UnitPrefixDefinition.NO_PREFIX
	), volunteer.rejected_reason)

	var first: String = _drawn_recruit()
	var second: String = _drawn_recruit()
	_check("recruit: the same stream draws the same recruit", (
			first == second and not first.is_empty()
	), "%s / %s" % [first, second])


func _test_recruit_named() -> void:
	var made: CampaignSession = _fx.session()
	var seat_run: SeatRun = made.run.seat_run(0)
	_resolve(made, [_grow(1)])
	var first_prefix: UnitPrefixDefinition = (
			_fx.catalog.all_of(EffectCatalog.Kind.UNIT_PREFIX)[0] as UnitPrefixDefinition
	)
	var prefix_id: String = first_prefix.id
	var named: RecruitOutcome = _recruit(RecruitOutcome.PrefixRoll.ELITE)
	named.unit_type_id = NAMED_TYPE
	named.prefix_id = prefix_id
	named.level = NAMED_LEVEL
	named.gear_ids = PackedStringArray([BUCKLER, BAND])
	var result: EventResult = _resolve(made, [named])
	var joined: UnitInstance = seat_run.army[-1]
	var equipment: ItemInstance = seat_run.items.get(joined.equipment_id, null)
	var pouch: ItemInstance = seat_run.items.get(
			ItemPlacement.item_in(joined, Loadout.Slot.POUCH), null
	)
	_check("recruit: a named type, prefix and level, with its gear in its slots", (
			not result.is_rejected() and joined.unit_type_id == NAMED_TYPE
			and joined.prefix_id == prefix_id and joined.level == NAMED_LEVEL
			and equipment != null and equipment.definition_id == BUCKLER
			and pouch != null and pouch.definition_id == BAND
			and not joined.weapon_id.is_empty() and _fx.is_whole(seat_run)
	), result.rejected_reason)

	var bad: Array[RecruitOutcome] = []
	for field: String in ["commander", "unknown type", "weapon gear", "two for a slot"]:
		var block: RecruitOutcome = _recruit(RecruitOutcome.PrefixRoll.NONE)
		match field:
			"commander":
				block.unit_type_id = seat_run.army[0].unit_type_id
			"unknown type":
				block.unit_type_id = "no_such_unit"
			"weapon gear":
				block.gear_ids = PackedStringArray([
					seat_run.items[seat_run.army[1].weapon_id].definition_id,
				])
			"two for a slot":
				block.gear_ids = PackedStringArray([BUCKLER, BUCKLER])
		bad.append(block)
	var size: int = seat_run.army.size()
	var reasons: PackedStringArray = []
	for block: RecruitOutcome in bad:
		var refused: EventResult = _resolve(made, [block])
		reasons.append(refused.rejected_reason)
	_check("recruit: a commander's type, an unknown type, a weapon or two items for one slot "
			+ "are refused", (
			reasons.size() == bad.size() and not reasons.has("")
			and seat_run.army.size() == size
	), str(reasons))


func _test_recruit_full_army() -> void:
	var made: CampaignSession = _fx.session()
	var seat_run: SeatRun = made.run.seat_run(0)
	var log_size: int = made.run.fact_log.size()
	var hire: RecruitOutcome = _recruit(RecruitOutcome.PrefixRoll.NONE)
	var refused: EventResult = _resolve(made, [hire])
	_check("recruit: into a full army with no unit named to dismiss it is refused", (
			refused.is_rejected() and refused.rejected_reason.contains("full")
			and made.run.fact_log.size() == log_size and seat_run.army.size() == MERCENARY_SIZE
	), refused.rejected_reason)
	_check("recruit: a full army doesn't grey the option out (the player may replace a unit)", (
			EventResolver.unmet_reason(_fx.context(made, _fx.event_of([hire]))).is_empty()
	))

	var commander: EventChoice = EventChoice.new()
	commander.replaced_id = seat_run.commander_id
	var kept: EventResult = _resolve(made, [hire], commander)
	_check("recruit: the commander is never dismissed for a recruit", (
			kept.is_rejected() and kept.rejected_reason.contains("commander")
	), kept.rejected_reason)

	var leaving: UnitInstance = _fx.soldier(seat_run)
	var weapon_id: String = leaving.weapon_id
	var choice: EventChoice = EventChoice.new()
	choice.replaced_id = leaving.instance_id
	var replaced: EventResult = _resolve(made, [hire], choice)
	var joined: UnitInstance = seat_run.army[-1]
	var kinds: Array[CampaignFact.Kind] = _fx.kinds(replaced.facts)
	_check("recruit: into a full army it replaces the named unit, its items to the convoy", (
			not replaced.is_rejected() and seat_run.army.size() == MERCENARY_SIZE
			and not seat_run.army.has(leaving) and not seat_run.fallen.has(leaving)
			and seat_run.convoy.has(weapon_id) and _fx.is_whole(seat_run)
	), replaced.rejected_reason)
	_check("recruit: UNIT_DISMISSED for the recruit, then UNIT_RECRUITED in its place", (
			kinds.size() >= 2
			and kinds[-2] == CampaignFact.Kind.UNIT_DISMISSED
			and kinds[-1] == CampaignFact.Kind.UNIT_RECRUITED
			and replaced.facts[-2].actor_id == leaving.instance_id
			and replaced.facts[-2].target_id == joined.instance_id
			and replaced.facts[-1].target_id == leaving.instance_id
			and replaced.facts[-1].definition_id == Fixture.EVENT_ID
	), str(kinds))

	_resolve(made, [_grow(1)])
	var with_room: EventChoice = EventChoice.new()
	with_room.replaced_id = _fx.soldier(seat_run).instance_id
	var roomy: EventResult = _resolve(made, [hire], with_room)
	_check("recruit: with room, naming a unit to dismiss is refused", (
			roomy.is_rejected() and roomy.rejected_reason.contains("room")
	), roomy.rejected_reason)


func _test_upgrade() -> void:
	var made: CampaignSession = _fx.session()
	var seat_run: SeatRun = made.run.seat_run(0)
	var chosen: UnitInstance = _fx.soldier(seat_run)
	var augment: UpgradeOutcome = UpgradeOutcome.new()
	_check("upgrade: a chosen unit asks the player for a unit", (
			augment.chooser() == EventOutcome.Chooser.UNIT
	))
	var result: EventResult = _resolve(made, [augment], EventChoice.new(chosen.instance_id))
	_check("upgrade: the chosen unit is upgraded, UNIT_UPGRADED by the event", (
			not result.is_rejected() and chosen.is_upgraded
			and _fx.kinds(result.facts) == [CampaignFact.Kind.UNIT_UPGRADED]
			and result.facts[0].actor_id == chosen.instance_id
			and result.facts[0].definition_id == Fixture.EVENT_ID
	), result.rejected_reason)
	var again: EventResult = _resolve(made, [augment], EventChoice.new(chosen.instance_id))
	var commander: EventResult = _resolve(
			made, [augment], EventChoice.new(seat_run.commander_id)
	)
	_check("upgrade: a unit upgraded already, and the commander, are refused", (
			again.rejected_reason.contains("already")
			and commander.rejected_reason.contains("commander")
	), "%s / %s" % [again.rejected_reason, commander.rejected_reason])

	var every: UpgradeOutcome = UpgradeOutcome.new()
	every.target = EventOutcome.Target.EVERY
	var all: EventResult = _resolve(made, [every])
	var upgraded: int = 0
	for unit: UnitInstance in seat_run.army:
		upgraded += 1 if unit.is_upgraded else 0
	_check("upgrade: every unit upgrades each one that can be, skipping the commander", (
			not all.is_rejected() and upgraded == seat_run.army.size() - 1
			and all.facts.size() == seat_run.army.size() - 2
	), "%s %d" % [all.rejected_reason, upgraded])
	var none: EventResult = _resolve(made, [every])
	_check("upgrade: every unit, with none left to upgrade, is refused", (
			none.is_rejected() and none.rejected_reason.contains("no unit")
	), none.rejected_reason)


func _test_revive_full_army() -> void:
	var made: CampaignSession = _fx.session()
	var seat_run: SeatRun = made.run.seat_run(0)
	var lost: UnitInstance = seat_run.army[2]
	_fx.fell(seat_run, lost)
	var filler: RecruitOffer = RecruitOffer.make(
			_fx.catalog, NAMED_TYPE, "", 1, made.ids
	)
	RunOperations.recruit(made.run, 0, filler, "test")
	var revive: ReviveOutcome = ReviveOutcome.new()
	var commander: EventChoice = EventChoice.new(lost.instance_id)
	commander.replaced_id = seat_run.commander_id
	var kept: EventResult = _resolve(made, [revive], commander)
	_check("revive: into a full army the commander is never dismissed", (
			kept.is_rejected() and kept.rejected_reason.contains("commander")
			and seat_run.fallen.has(lost)
	), kept.rejected_reason)

	var leaving: UnitInstance = seat_run.army[1]
	var weapon_id: String = leaving.weapon_id
	var choice: EventChoice = EventChoice.new(lost.instance_id)
	choice.replaced_id = leaving.instance_id
	var result: EventResult = _resolve(made, [revive], choice)
	_check("revive: into a full army the named unit leaves, its items to the convoy", (
			not result.is_rejected() and seat_run.army.size() == MERCENARY_SIZE
			and seat_run.army[-1] == lost and not seat_run.fallen.has(lost)
			and not seat_run.army.has(leaving) and not seat_run.fallen.has(leaving)
			and seat_run.convoy.has(weapon_id) and _fx.is_whole(seat_run)
	), result.rejected_reason)
	var kinds: Array[CampaignFact.Kind] = _fx.kinds(result.facts)
	_check("revive: UNIT_DISMISSED for the revived unit, then UNIT_REVIVED", (
			kinds.size() >= 2
			and kinds[-2] == CampaignFact.Kind.UNIT_DISMISSED
			and kinds[-1] == CampaignFact.Kind.UNIT_REVIVED
			and result.facts[-2].target_id == lost.instance_id
			and result.facts[-1].actor_id == lost.instance_id
	), str(kinds))


func _test_cursed_blood() -> void:
	var made: CampaignSession = _fx.session()
	var seat_run: SeatRun = made.run.seat_run(0)
	var hurt: UnitInstance = _fx.soldier(seat_run)
	var unit_max: int = EventOutcome.max_hp(hurt, _fx.catalog)
	var ctx: EventContext = _fx.context(made, _fx.event_of([]))
	var before: float = ctx.healing_received_percent(hurt)
	seat_run.add_heirloom(CURSED_BLOOD)
	var cursed: float = ctx.healing_received_percent(hurt)
	_check("cursed blood: the context reads 100% healing received, 50% once the seat holds it", (
			is_equal_approx(before, FULL) and is_equal_approx(cursed, HALF)
	), "%s, %s" % [before, cursed])
	hurt.hp = 1
	var heal: HpPercentOutcome = HpPercentOutcome.new()
	heal.target = EventOutcome.Target.EVERY
	heal.percent = HEAL_PERCENT
	var result: EventResult = _resolve(made, [heal])
	var expected: int = EventOutcome.percent_of(unit_max, HEAL_PERCENT * HALF / FULL)
	_check("cursed blood: an event heal through the resolver restores half", (
			not result.is_rejected() and hurt.hp == 1 + expected
	), "%d, expected %d" % [hurt.hp, 1 + expected])


func _test_save_and_load() -> void:
	var made: CampaignSession = _fx.session()
	_resolve(made, [_grow(1)])
	var players: Array[CampaignData.PlayerRun] = _captured_players(made)
	var heirlooms: Dictionary = players[0].sections.get("heirlooms", {})
	var data: Dictionary = heirlooms.get("data", {})
	var changes: Array = data.get("value_changes", [])
	_check("save: the heirlooms section is at version 2 and holds the change", (
			_version_of(players[0], "heirlooms") == RunSaveSections.HEIRLOOMS_VERSION
			and RunSaveSections.HEIRLOOMS_VERSION == 2 and changes.size() == 1
	), str(heirlooms))
	var resumed: CampaignSession = _fx.resume(made)
	var seat_run: SeatRun = resumed.run.seat_run(0) if resumed != null else null
	_check("save: the army-size change survives a quit and Continue, through JSON", (
			seat_run != null
			and RunOperations.max_army_size(seat_run, _fx.catalog) == MERCENARY_SIZE + 1
			and ItemPlacement.convoy_capacity(seat_run, _fx.catalog) == MERCENARY_SIZE + 1
			and seat_run.value_changes.size() == 1
			and seat_run.value_changes[0].source_id == Fixture.EVENT_ID
			and seat_run.value_changes[0].label == Fixture.EVENT_TITLE
	), error_string(_fx.resume_error))

	var parsed: SeatRun = SeatRun.new(0)
	var good: Dictionary = made.run.seat_run(0).capture_heirlooms()
	var bad_key: Dictionary = good.duplicate(true)
	_first_change(bad_key)["key"] = "combat.HIT"
	var bad_amount: Dictionary = good.duplicate(true)
	_first_change(bad_amount)["amount"] = "one"
	var not_a_list: Dictionary = good.duplicate(true)
	not_a_list["value_changes"] = {}
	_check("save: a change keyed off the campaign values, a non-number or a non-list is refused", (
			parsed.restore_heirlooms(bad_key) == ERR_INVALID_DATA
			and parsed.restore_heirlooms(bad_amount) == ERR_INVALID_DATA
			and parsed.restore_heirlooms(not_a_list) == ERR_INVALID_DATA
			and parsed.value_changes.is_empty()
	))


func _test_old_save() -> void:
	var made: CampaignSession = _fx.session()
	var seat_run: SeatRun = made.run.seat_run(0)
	seat_run.add_heirloom(MUSTER_ROLL)
	var saving: Fixture.Sections = Fixture.Sections.new()
	saving.attach(made)
	var block: Dictionary = saving.registry.capture(SaveSection.Block.CAMPAIGN, {})
	var players: Array[CampaignData.PlayerRun] = _captured_players(made)
	var old: Dictionary = players[0].sections["heirlooms"]
	var old_data: Dictionary = old["data"]
	old["version"] = 1
	old_data.erase("value_changes")
	var parsed: Variant = JSON.parse_string(JSON.stringify(players[0].to_dict()))
	var read: Array[CampaignData.PlayerRun] = [CampaignData.PlayerRun.from_dict(parsed)]
	var loading: Fixture.Sections = Fixture.Sections.new()
	var err: Error = loading.registry.restore(SaveSection.Block.CAMPAIGN, block)
	if err == OK:
		err = loading.registry.restore_players(read)
	var resumed: CampaignSession = CampaignSession.new(made.mode, Fixture.RUN_SEED, made.seats)
	if err == OK:
		err = loading.attach(resumed)
	var loaded: SeatRun = resumed.run.seat_run(0) if err == OK else null
	_check("old save: a version 1 heirlooms section migrates, with no value changes", (
			loaded != null and loaded.value_changes.is_empty()
			and loaded.heirloom_ids() == seat_run.heirloom_ids()
			and RunOperations.max_army_size(loaded, _fx.catalog) == MERCENARY_SIZE + 1
	), error_string(err))
	var saved_again: Array[CampaignData.PlayerRun] = _captured_players(resumed)
	_check("old save: saved again, it is written at version 2", (
			_version_of(saved_again[0], "heirlooms") == RunSaveSections.HEIRLOOMS_VERSION
	))


# The saved version of player's section key; 0 when it has none.
func _version_of(player: CampaignData.PlayerRun, key: String) -> int:
	var section: Variant = player.sections.get(key)
	if not section is Dictionary:
		return 0
	return ItemInstance.read_int((section as Dictionary).get("version"), 0)


# The first value change in captured heirloom data, to spoil.
func _first_change(data: Dictionary) -> Dictionary:
	var changes: Array = data["value_changes"]
	return changes[0]


# The seats of made, captured through the campaign block's player sections.
func _captured_players(made: CampaignSession) -> Array[CampaignData.PlayerRun]:
	var saving: Fixture.Sections = Fixture.Sections.new()
	saving.attach(made)
	var players: Array[CampaignData.PlayerRun] = []
	for seat: int in made.seats:
		var player: CampaignData.PlayerRun = CampaignData.PlayerRun.new()
		player.seat = seat
		players.append(player)
	saving.registry.capture_players(players)
	return players


# The type and prefix a random elite recruit draws in a fresh run with room for it.
func _drawn_recruit() -> String:
	var made: CampaignSession = _fx.session()
	_resolve(made, [_grow(1)])
	_resolve(made, [_recruit(RecruitOutcome.PrefixRoll.ELITE)])
	var joined: UnitInstance = made.run.seat_run(0).army[-1]
	return "%s/%s" % [joined.unit_type_id, joined.prefix_id]


# The Company Charter as events.md writes it: needs room below 8, +1 and a named major curse.
func _charter() -> EventDefinition:
	var needs: EventRequirements = EventRequirements.new()
	needs.needs_army_room = true
	return _fx.event_of([_grow(1)], needs, _fx.curses_of(MAJOR)[0])


func _resolve(
		made: CampaignSession, outcomes: Array[EventOutcome], choice: EventChoice = null
) -> EventResult:
	return _resolve_with(made, _fx.event_of(outcomes), choice)


func _resolve_with(
		made: CampaignSession, event: EventDefinition, choice: EventChoice = null
) -> EventResult:
	return EventResolver.resolve(_fx.context(made, event, choice))


func _grow(amount: int) -> ArmySizeOutcome:
	var block: ArmySizeOutcome = ArmySizeOutcome.new()
	block.amount = amount
	return block


func _recruit(roll: RecruitOutcome.PrefixRoll) -> RecruitOutcome:
	var block: RecruitOutcome = RecruitOutcome.new()
	block.prefix_roll = roll
	return block


func _gold(amount: int) -> GoldOutcome:
	var block: GoldOutcome = GoldOutcome.new()
	block.amount = amount
	return block


func _check(case_name: String, passed: bool, detail: String = "") -> void:
	_report.call(case_name, passed, detail)
