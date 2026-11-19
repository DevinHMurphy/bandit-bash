# ==============================================================================
# Bandit Bash
# Copyright (c) 2026 Derc Development
# Licensed under the MIT License. See LICENSE.
#
# File:     outcome_cases.gd
# Author:
# Created:  November 19, 2026
# Modified: November 19, 2026
# ==============================================================================

extends RefCounted
## Outcome block cases for tests/events/run_all.gd, each applied through EventResolver to a real
## CampaignRunState with its facts: gold gained and paid (and an unaffordable payment refused);
## percent heals (halves up, Cursed Blood's half, capped) and damage (never below 1 HP); stat,
## max HP (both directions, never below 1) and Hit changes; pending level-up gains; named and
## random item grants (rare weapon, rare tome, trinket, the same draw from the same stream) and a
## full convoy refused; item modification (effects and deltas, "Infused"); heirlooms (a curse
## refused); runes (a free slot, a full set needing a discard, still offered); the prefix re-roll
## (never the same, never a commander); the revive's fallen-unit rule; the surprise combat's
## descriptor; named curses repeating as copies. Touches no save files.

const Fixture = preload("res://tests/events/event_fixture.gd")

const STARTING_GOLD: int = 100
const LOW_HP: int = 1
const HEAL_PERCENT: int = 20
const CURSED_BLOOD_PERCENT: int = 50
const REVIVE_PERCENT: int = 10

var _report: Callable
var _fx: Fixture = null


func _init(check: Callable) -> void:
	_report = check


func run() -> void:
	_fx = Fixture.new()
	_check("outcomes: the catalog and rules load", _fx.is_ready())
	if not _fx.is_ready():
		return
	_test_gold()
	_test_heal_and_damage()
	_test_stats()
	_test_max_hp()
	_test_pending_gain()
	_test_item_grant()
	_test_random_items()
	_test_item_modification()
	_test_heirloom_and_curse()
	_test_runes()
	_test_prefix_reroll()
	_test_revive()
	_test_surprise_combat()


func _test_gold() -> void:
	var made: CampaignSession = _fx.session()
	var seat_run: SeatRun = made.run.seat_run(0)
	_check("gold: the Mercenary starts with 100", seat_run.gold == STARTING_GOLD)
	var gain: EventResult = _resolve(made, [_gold(40)])
	_check("gold: +40 is added, with GOLD_CHANGED +40 sourced to the event", (
			not gain.is_rejected() and seat_run.gold == STARTING_GOLD + 40
			and _fx.kinds(gain.facts) == [CampaignFact.Kind.GOLD_CHANGED]
			and gain.facts[0].amount == 40 and gain.facts[0].definition_id == Fixture.EVENT_ID
			and gain.facts[0].seat == 0
	), gain.rejected_reason)
	var paid: EventResult = _resolve(made, [_gold(-30)])
	_check("gold: paying 30 takes it, GOLD_CHANGED -30", (
			seat_run.gold == STARTING_GOLD + 10 and paid.facts[0].amount == -30
	))
	var log_size: int = made.run.fact_log.size()
	var too_much: EventResult = _resolve(made, [_gold(-500)])
	_check("gold: a payment the seat can't afford is refused, changing nothing", (
			too_much.is_rejected() and too_much.rejected_reason.contains("gold")
			and seat_run.gold == STARTING_GOLD + 10 and made.run.fact_log.size() == log_size
	), too_much.rejected_reason)


func _test_heal_and_damage() -> void:
	var made: CampaignSession = _fx.session()
	var seat_run: SeatRun = made.run.seat_run(0)
	var hurt: UnitInstance = seat_run.army[1]
	var full: UnitInstance = seat_run.army[2]
	var hurt_max: int = EventOutcome.max_hp(hurt, _fx.catalog)
	hurt.hp = LOW_HP
	var heal: EventResult = _resolve(made, [_hp(EventOutcome.Target.EVERY, HEAL_PERCENT)])
	var healed: int = EventOutcome.percent_of(hurt_max, HEAL_PERCENT)
	_check("heal: 20% of max HP, halves up, for a hurt unit; a full one stays full, no fact", (
			not heal.is_rejected() and hurt.hp == LOW_HP + healed
			and full.hp == UnitInstance.FULL_HP
			and _fx.kinds(heal.facts) == [CampaignFact.Kind.HP_CHANGED]
			and heal.facts[0].actor_id == hurt.instance_id and heal.facts[0].amount == healed
	), "%d of %d, %s" % [hurt.hp, hurt_max, _fx.kinds(heal.facts)])

	hurt.hp = LOW_HP
	var ctx: EventContext = _fx.context(made, _fx.event_of([
		_hp(EventOutcome.Target.EVERY, HEAL_PERCENT),
	]))
	ctx.healing_percent = CURSED_BLOOD_PERCENT
	EventResolver.resolve(ctx)
	var halved: int = EventOutcome.percent_of(hurt_max, HEAL_PERCENT * CURSED_BLOOD_PERCENT / 100.0)
	_check("heal: Cursed Blood's 50% healing received halves it, rounded at the end", (
			hurt.hp == LOW_HP + halved and halved < healed
	), "%d, expected %d" % [hurt.hp, LOW_HP + halved])

	hurt.hp = hurt_max - 1
	_resolve(made, [_hp(EventOutcome.Target.EVERY, 100)])
	_check("heal: a heal stops at max HP, stored as full", hurt.hp == UnitInstance.FULL_HP)

	var low: UnitInstance = seat_run.army[3]
	low.hp = 2
	var full_max: int = EventOutcome.max_hp(full, _fx.catalog)
	var damage: EventResult = _resolve(made, [_hp(EventOutcome.Target.EVERY, -HEAL_PERCENT)])
	_check("damage: 20% of max HP, halves up, from a full unit", (
			full.hp == full_max - EventOutcome.percent_of(full_max, HEAL_PERCENT)
	), "%d of %d" % [full.hp, full_max])
	_check("damage: event damage never kills; a low unit is left at 1 HP", (
			low.hp == 1 and seat_run.army.has(low)
	), str(low.hp))
	_check("damage: one HP_CHANGED per living unit, each negative", (
			damage.facts.size() == seat_run.army.size()
			and damage.facts.all(func(fact: CampaignFact) -> bool: return fact.amount < 0)
	), str(_fx.kinds(damage.facts)))


func _test_stats() -> void:
	var made: CampaignSession = _fx.session()
	var seat_run: SeatRun = made.run.seat_run(0)
	var chosen: UnitInstance = seat_run.army[1]
	var before: int = chosen.stats(_fx.catalog).get_int(CombatValue.Key.MGT)
	var result: EventResult = _resolve(
			made, [_stat(EventOutcome.Target.CHOSEN, CombatValue.Stat.MGT, 2)],
			EventChoice.new(chosen.instance_id)
	)
	var delta: ItemInstance.StatDelta = chosen.stat_deltas[-1]
	_check("stat: a chosen unit gains +2 MGT as a delta sourced and labelled to the event", (
			not result.is_rejected()
			and chosen.stats(_fx.catalog).get_int(CombatValue.Key.MGT) == before + 2
			and delta.source_id == Fixture.EVENT_ID and delta.label == Fixture.EVENT_TITLE
			and _fx.kinds(result.facts) == [CampaignFact.Kind.UNIT_CHANGED]
			and result.facts[0].actor_id == chosen.instance_id and result.facts[0].amount == 2
	), result.rejected_reason)
	var unchosen: EventResult = _resolve(
			made, [_stat(EventOutcome.Target.CHOSEN, CombatValue.Stat.MGT, 2)]
	)
	_check("stat: with no unit chosen it is refused", (
			unchosen.is_rejected() and unchosen.rejected_reason.contains("choose a unit")
	), unchosen.rejected_reason)

	var commander: UnitInstance = seat_run.unit(seat_run.commander_id)
	var mgt: int = commander.stats(_fx.catalog).get_int(CombatValue.Key.MGT)
	var def: int = commander.stats(_fx.catalog).get_int(CombatValue.Key.DEF)
	var library: EventResult = _resolve(made, [
		_stat(EventOutcome.Target.COMMANDER, CombatValue.Stat.MGT, 2),
		_stat(EventOutcome.Target.COMMANDER, CombatValue.Stat.DEF, -1),
	])
	_check("stat: the commander gains +2 MGT and loses 1 DEF, one fact each", (
			commander.stats(_fx.catalog).get_int(CombatValue.Key.MGT) == mgt + 2
			and commander.stats(_fx.catalog).get_int(CombatValue.Key.DEF) == def - 1
			and library.facts.size() == 2
	))
	var hit_before: int = chosen.stats(_fx.catalog).get_int(CombatValue.Key.HIT)
	_resolve(made, [_stat(EventOutcome.Target.CHOSEN, CombatValue.HIT_STAT, 10)],
			EventChoice.new(chosen.instance_id))
	_check("stat: +10 Hit is a permanent Hit delta", (
			chosen.stats(_fx.catalog).get_int(CombatValue.Key.HIT) == hit_before + 10
			and chosen.stat_deltas[-1].key == CombatValue.Key.HIT
	))
	var everyone: EventResult = _resolve(made, [
		_stat(EventOutcome.Target.EVERY, CombatValue.Stat.SPD, 1),
	])
	_check("stat: every unit is the living army, one UNIT_CHANGED each", (
			everyone.facts.size() == seat_run.army.size()
	), str(everyone.facts.size()))


func _test_max_hp() -> void:
	var made: CampaignSession = _fx.session()
	var seat_run: SeatRun = made.run.seat_run(0)
	var full: UnitInstance = seat_run.army[1]
	var hurt: UnitInstance = seat_run.army[2]
	var full_max: int = EventOutcome.max_hp(full, _fx.catalog)
	var loss: EventResult = _resolve(
			made, [_stat(EventOutcome.Target.CHOSEN, CombatValue.Stat.HP, -4)],
			EventChoice.new(full.instance_id)
	)
	_check("max HP: a full unit losing 4 max HP stays full at the new max", (
			EventOutcome.max_hp(full, _fx.catalog) == full_max - 4
			and full.hp == UnitInstance.FULL_HP
			and _fx.kinds(loss.facts) == [
				CampaignFact.Kind.UNIT_CHANGED, CampaignFact.Kind.HP_CHANGED,
			]
			and loss.facts[1].amount == -4
	), str(_fx.kinds(loss.facts)))
	hurt.hp = LOW_HP
	var hurt_loss: EventResult = _resolve(
			made, [_stat(EventOutcome.Target.CHOSEN, CombatValue.Stat.HP, -4)],
			EventChoice.new(hurt.instance_id)
	)
	_check("max HP: a loss lowers current HP only above the new max", (
			hurt.hp == LOW_HP and _fx.kinds(hurt_loss.facts) == [CampaignFact.Kind.UNIT_CHANGED]
	), str(hurt.hp))
	var gain: EventResult = _resolve(made, [
		_stat(EventOutcome.Target.EVERY, CombatValue.Stat.HP, 2),
	])
	_check("max HP: +2 max HP for every unit raises current HP by 2", (
			hurt.hp == LOW_HP + 2
			and gain.facts.size() == seat_run.army.size() * 2
	), "%d, %d facts" % [hurt.hp, gain.facts.size()])
	_resolve(made, [_stat(EventOutcome.Target.CHOSEN, CombatValue.Stat.HP, -999)],
			EventChoice.new(full.instance_id))
	_check("max HP: a loss never takes max HP below 1", (
			EventOutcome.max_hp(full, _fx.catalog) == StatOutcome.MIN_MAX_HP
	), str(EventOutcome.max_hp(full, _fx.catalog)))


func _test_pending_gain() -> void:
	var made: CampaignSession = _fx.session()
	var chosen: UnitInstance = made.run.seat_run(0).army[1]
	var block: PendingGainOutcome = PendingGainOutcome.new()
	block.stat = CombatValue.Stat.MGT
	block.amount = 1
	block.level_ups = 2
	var result: EventResult = _resolve(made, [block], EventChoice.new(chosen.instance_id))
	var gain: UnitInstance.PendingGain = (
			null if chosen.pending_gains.is_empty() else chosen.pending_gains[0]
	)
	_check("pending gain: next two level-ups +1 MGT each, sourced to the event", (
			gain != null and gain.stat == CombatValue.Stat.MGT and gain.amount == 1
			and gain.remaining == 2 and gain.source_id == Fixture.EVENT_ID
			and _fx.kinds(result.facts) == [CampaignFact.Kind.UNIT_CHANGED]
	))


func _test_item_grant() -> void:
	var made: CampaignSession = _fx.session()
	var seat_run: SeatRun = made.run.seat_run(0)
	var grant: ItemGrantOutcome = ItemGrantOutcome.new()
	grant.item_id = "cleansed_goblet"
	var result: EventResult = _resolve(made, [grant])
	var gained_id: String = "" if result.facts.is_empty() else result.facts[0].actor_id
	_check("item: a named item goes to the convoy by default, GAINED with its new id", (
			not result.is_rejected() and seat_run.convoy.has(gained_id)
			and seat_run.items[gained_id].definition_id == "cleansed_goblet"
			and _fx.kinds(result.facts) == [CampaignFact.Kind.GAINED]
			and _fx.is_whole(seat_run)
	), result.rejected_reason)
	while seat_run.convoy.size() < ItemPlacement.convoy_capacity(seat_run, _fx.catalog):
		_fx.add_to_convoy(made, "cleansed_goblet")
	var items_before: int = seat_run.items.size()
	var full: EventResult = _resolve(made, [grant])
	_check("item: into a full convoy with nothing scrapped it is refused, changing nothing", (
			full.is_rejected() and full.rejected_reason.contains("convoy is full")
			and seat_run.items.size() == items_before
	), full.rejected_reason)
	var choice: EventChoice = EventChoice.new()
	choice.placements[0] = ItemPlacement.new(
			ItemPlacement.Destination.CONVOY, "", false, seat_run.convoy[0]
	)
	var scrapped: EventResult = _resolve(made, [grant], choice)
	_check("item: scrapping a convoy item makes room, as ItemPlacement does", (
			not scrapped.is_rejected()
			and _fx.kinds(scrapped.facts).has(CampaignFact.Kind.ITEM_SCRAPPED)
			and _fx.is_whole(seat_run)
	), scrapped.rejected_reason)


func _test_random_items() -> void:
	var made: CampaignSession = _fx.session()
	var seat_run: SeatRun = made.run.seat_run(0)
	var weapon: ItemGrantOutcome = _random(ItemGrantOutcome.RandomItem.RARE_WEAPON)
	var tome: ItemGrantOutcome = _random(ItemGrantOutcome.RandomItem.RARE_TOME)
	var trinket: ItemGrantOutcome = _random(ItemGrantOutcome.RandomItem.TRINKET)
	var option: EventOption = _fx.event_of([weapon, tome, trinket]).options[0]
	var stream: RngStream = _fx.stream(made)
	var state: String = stream.capture()
	var rolls: EventRolls = EventResolver.roll(option, seat_run, stream, _fx.catalog, _fx.rules)
	stream.restore(state)
	var again: EventRolls = EventResolver.roll(option, seat_run, stream, _fx.catalog, _fx.rules)
	var drawn_weapon: WeaponDefinition = _fx.catalog.weapon(rolls.pick(0))
	var drawn_tome: WeaponDefinition = _fx.catalog.weapon(rolls.pick(1))
	_check("random item: a rare weapon is a Rare weapon", (
			drawn_weapon != null and drawn_weapon.rarity == ItemDefinition.Rarity.RARE
	), rolls.pick(0))
	_check("random item: a rare tome is a Rare anima, holy or dark weapon", (
			drawn_tome != null and drawn_tome.rarity == ItemDefinition.Rarity.RARE
			and ItemGrantOutcome.TOME_TYPES.has(drawn_tome.weapon_type)
	), rolls.pick(1))
	_check("random item: a trinket is a trinket", (
			_fx.catalog.trinket(rolls.pick(2)) != null
	), rolls.pick(2))
	_check("random item: the same stream state draws the same items", (
			rolls.picks == again.picks
	), "%s / %s" % [rolls.picks, again.picks])
	var ctx: EventContext = _fx.context(made, _fx.event_of([weapon]))
	ctx.rolls.picks[0] = rolls.pick(0)
	var result: EventResult = EventResolver.resolve(ctx)
	_check("random item: the rolled weapon is the one given", (
			not result.is_rejected()
			and seat_run.items[result.facts[0].actor_id].definition_id == rolls.pick(0)
	), result.rejected_reason)
	var empty: EventContext = _fx.context(made, _fx.event_of([weapon]))
	empty.rolls.picks[0] = ""
	_check("random item: an empty pool greys the option out, with the reason", (
			EventResolver.unmet_reason(empty) == "no item is left to give"
			and EventResolver.resolve(empty).is_rejected()
	), EventResolver.unmet_reason(empty))


func _test_item_modification() -> void:
	var made: CampaignSession = _fx.session()
	var seat_run: SeatRun = made.run.seat_run(0)
	var archer: UnitInstance = _fx.unit_of_type(seat_run, "archer")
	var bow: ItemInstance = seat_run.items[archer.weapon_id]
	var block: ItemModificationOutcome = ItemModificationOutcome.new()
	block.effect_ids = [Fixture.TEST_EFFECT]
	block.stat_deltas = {CombatValue.Key.NET_WEIGHT: 2.0}
	var result: EventResult = _resolve(made, [block], EventChoice.new("", bow.instance_id))
	_check("modify: a chosen weapon gains the effect and +2 weight, sourced; it is Infused", (
			not result.is_rejected() and bow.granted_effect_ids.has(Fixture.TEST_EFFECT)
			and bow.stat_deltas.size() == 1 and bow.stat_deltas[0].amount == 2.0
			and bow.stat_deltas[0].source_id == Fixture.EVENT_ID and bow.is_modified()
			and _fx.kinds(result.facts) == [CampaignFact.Kind.ITEM_MODIFIED]
			and result.facts[0].actor_id == bow.instance_id
	), result.rejected_reason)
	var potion_id: String = archer.pouch_id
	var not_weapon: EventResult = _resolve(made, [block], EventChoice.new("", potion_id))
	_check("modify: an item that isn't a weapon is refused", not_weapon.is_rejected())
	_fx.fell(seat_run, archer)
	var fallen: EventResult = _resolve(made, [block], EventChoice.new("", bow.instance_id))
	_check("modify: a fallen unit's weapon is refused", (
			fallen.is_rejected() and bow.stat_deltas.size() == 1
	), fallen.rejected_reason)
	var in_convoy: ItemInstance = _fx.add_to_convoy(made, "simple_sword")
	_check("modify: a weapon in the convoy can be chosen", not _resolve(
			made, [block], EventChoice.new("", in_convoy.instance_id)
	).is_rejected())


func _test_heirloom_and_curse() -> void:
	var made: CampaignSession = _fx.session()
	var seat_run: SeatRun = made.run.seat_run(0)
	var heirloom: HeirloomOutcome = HeirloomOutcome.new()
	heirloom.heirloom_id = "iron_heart"
	var result: EventResult = _resolve(made, [heirloom])
	_check("heirloom: a named heirloom is owned, GAINED", (
			seat_run.heirloom_ids().has("iron_heart")
			and _fx.kinds(result.facts) == [CampaignFact.Kind.GAINED]
			and result.facts[0].definition_id == "iron_heart"
	), result.rejected_reason)
	heirloom.heirloom_id = "haunted"
	_check("heirloom: a curse given as an heirloom is refused", _resolve(
			made, [heirloom]
	).is_rejected())
	var curse: CurseOutcome = CurseOutcome.new("haunted")
	_resolve(made, [curse])
	var repeat: EventResult = _resolve(made, [curse])
	_check("curse: a named curse is given even when held, adding a copy", (
			not repeat.is_rejected() and seat_run.heirloom_ids().count("haunted") == 2
			and _fx.kinds(repeat.facts) == [CampaignFact.Kind.GAINED]
	), repeat.rejected_reason)


func _test_runes() -> void:
	var made: CampaignSession = _fx.session()
	var seat_run: SeatRun = made.run.seat_run(0)
	var named: RuneOutcome = RuneOutcome.new()
	named.rune_id = "mend"
	var result: EventResult = _resolve(made, [named])
	_check("rune: a named rune goes into the first empty slot, GAINED with its instance", (
			not result.is_rejected() and seat_run.rune_slots[0].definition_id == "mend"
			and result.facts[0].actor_id == seat_run.rune_slots[0].instance_id
	), result.rejected_reason)
	var random: RuneOutcome = RuneOutcome.new()
	random.is_random = true
	var rolls: EventRolls = EventResolver.roll(
			_fx.event_of([random]).options[0], seat_run, _fx.stream(made), _fx.catalog, _fx.rules
	)
	_check("rune: a random rune is drawn from the catalog's runes", (
			_fx.catalog.rune(rolls.pick(0)) != null
	), rolls.pick(0))
	_resolve(made, [named])
	_resolve(made, [named])
	var full: EventContext = _fx.context(made, _fx.event_of([named]))
	_check("rune: with every slot full the option is still offered", (
			EventResolver.unmet_reason(full).is_empty()
	), EventResolver.unmet_reason(full))
	var refused: EventResult = EventResolver.resolve(full)
	_check("rune: with every slot full and no discard named, it is refused", (
			refused.is_rejected() and refused.rejected_reason.contains("discarded")
	), refused.rejected_reason)
	var old: SeatRun.RuneSlot = seat_run.rune_slots[1]
	var choice: EventChoice = EventChoice.new()
	choice.rune_discard_slot = 1
	var swapped: EventResult = _resolve(made, [named], choice)
	_check("rune: discarding slot 1 frees it: RUNE_DISCARDED, then GAINED", (
			not swapped.is_rejected()
			and _fx.kinds(swapped.facts) == [
				CampaignFact.Kind.RUNE_DISCARDED, CampaignFact.Kind.GAINED,
			]
			and swapped.facts[0].actor_id == old.instance_id and swapped.facts[0].amount == 1
			and seat_run.rune_slots[1].instance_id == swapped.facts[1].actor_id
			and SeatRun.new(0).restore_runes(seat_run.capture_runes()) == OK
	), swapped.rejected_reason)


func _test_prefix_reroll() -> void:
	var made: CampaignSession = _fx.session()
	var seat_run: SeatRun = made.run.seat_run(0)
	var chosen: UnitInstance = seat_run.army[1]
	var before: String = chosen.prefix_id
	var result: EventResult = _resolve(
			made, [PrefixRerollOutcome.new()], EventChoice.new(chosen.instance_id)
	)
	_check("re-roll: the chosen unit's prefix changes, never the same", (
			not result.is_rejected() and chosen.prefix_id != before
			and _fx.kinds(result.facts).has(CampaignFact.Kind.UNIT_CHANGED)
	), "%s -> %s %s" % [before, chosen.prefix_id, result.rejected_reason])
	var commander: EventResult = _resolve(
			made, [PrefixRerollOutcome.new()], EventChoice.new(seat_run.commander_id)
	)
	_check("re-roll: a commander is refused", (
			commander.is_rejected() and commander.rejected_reason.contains("commander")
	), commander.rejected_reason)


func _test_revive() -> void:
	var made: CampaignSession = _fx.session()
	var seat_run: SeatRun = made.run.seat_run(0)
	var revive: ReviveOutcome = ReviveOutcome.new()
	var living: EventResult = _resolve(
			made, [revive], EventChoice.new(seat_run.army[1].instance_id)
	)
	_check("revive: a living unit can't be chosen", (
			living.is_rejected() and living.rejected_reason.contains("fallen")
	), living.rejected_reason)
	var lost: UnitInstance = seat_run.army[2]
	var weapon_id: String = lost.weapon_id
	_fx.fell(seat_run, lost)
	var unit_max: int = EventOutcome.max_hp(lost, _fx.catalog)
	var result: EventResult = _resolve(made, [revive], EventChoice.new(lost.instance_id))
	var expected: int = maxi(EventOutcome.percent_of(unit_max, REVIVE_PERCENT), 1)
	_check("revive: the fallen unit rejoins at 10% of max HP, its items kept", (
			not result.is_rejected() and seat_run.army[-1] == lost
			and not seat_run.fallen.has(lost) and lost.hp == expected
			and lost.weapon_id == weapon_id and _fx.is_whole(seat_run)
			and _fx.kinds(result.facts) == [CampaignFact.Kind.UNIT_REVIVED]
			and result.facts[0].amount == expected
	), "%s, hp %d of %d" % [result.rejected_reason, lost.hp, unit_max])
	var other: UnitInstance = seat_run.army[1]
	_fx.fell(seat_run, other)
	seat_run.army.append(UnitInstance.new(made.ids.next_unit_id("archer"), "archer"))
	var full: EventResult = _resolve(made, [revive], EventChoice.new(other.instance_id))
	_check("revive: into a full army it is refused for now", (
			full.is_rejected() and full.rejected_reason.contains("full")
			and seat_run.fallen.has(other)
	), full.rejected_reason)


func _test_surprise_combat() -> void:
	var made: CampaignSession = _fx.session()
	made.run.enter_node(made.run.next_nodes()[0])
	var log_size: int = made.run.fact_log.size()
	var result: EventResult = _resolve(made, [SurpriseCombatOutcome.new()])
	var combat: EventResult.SurpriseCombat = result.surprise_combat
	_check("combat: a Standard combat at the event node's floor and node, no fact", (
			combat != null
			and combat.combat_type == CombatMapDefinition.CombatType.STANDARD
			and combat.floor_number == made.run.floor_number and combat.node == made.run.node
			and made.run.fact_log.size() == log_size
	))


func _resolve(
		made: CampaignSession, outcomes: Array[EventOutcome], choice: EventChoice = null
) -> EventResult:
	return EventResolver.resolve(_fx.context(made, _fx.event_of(outcomes), choice))


func _gold(amount: int) -> GoldOutcome:
	var block: GoldOutcome = GoldOutcome.new()
	block.amount = amount
	return block


func _hp(target: EventOutcome.Target, percent: int) -> HpPercentOutcome:
	var block: HpPercentOutcome = HpPercentOutcome.new()
	block.target = target
	block.percent = percent
	return block


func _stat(target: EventOutcome.Target, stat: int, amount: int) -> StatOutcome:
	var block: StatOutcome = StatOutcome.new()
	block.target = target
	block.stat = stat
	block.amount = amount
	return block


func _random(kind: ItemGrantOutcome.RandomItem) -> ItemGrantOutcome:
	var block: ItemGrantOutcome = ItemGrantOutcome.new()
	block.random = kind
	return block


func _check(case_name: String, passed: bool, detail: String = "") -> void:
	_report.call(case_name, passed, detail)
