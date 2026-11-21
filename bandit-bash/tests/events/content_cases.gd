# ==============================================================================
# Bandit Bash
# Copyright (c) 2026 Derc Development
# Licensed under the MIT License. See LICENSE.
#
# File:     content_cases.gd
# Author:
# Created:  November 20, 2026
# Modified: November 21, 2026
# ==============================================================================

extends RefCounted
## The 13 events of res://data/events/ as content: the pool loads every one soundly, each id is
## its file name, and every id an event names exists in the catalog. Every option of each is
## played through the event commands (the chooser stage first, as the screen does) against a
## fresh solo Mercenary run in an Unknown node, checking its outcome (gold, HP, stats, items,
## units, curses, heirlooms, runes, army size) and its facts. Each requirement's greyed-out case,
## Bandit Toll's team vote over two seats, and the shrine's revive with and without a fallen unit.
## The values checked are events.md's. Touches no save files.

const SUITE: String = "events"

const Fixture = preload("res://tests/events/event_fixture.gd")

## The events' ids, as the pool sorts them.
const EVENT_IDS: PackedStringArray = [
	"bandit_toll",
	"black_altar",
	"broken_shrine_of_valor",
	"cavern_of_echoing_steel",
	"clockwork_hermit",
	"cursed_hoard",
	"dark_goblet",
	"festival_of_embers",
	"frozen_armory",
	"ghastly_library",
	"mercenary_camp",
	"mirror_of_doubt",
	"whispering_oak",
]

## The events with no Godot_FE scene, so no art.
const WITHOUT_ART: PackedStringArray = [
	"bandit_toll", "black_altar", "cursed_hoard", "mercenary_camp",
]

## Every content id the events name outright (curses are all drawn from tiers).
const NAMED_IDS: PackedStringArray = [
	"cleansed_goblet", "emberglass_vial", "goblet_infusion", "oak_wood_charm", "resonant_ore",
]

const TEAM_EVENT: String = "bandit_toll"
const SHRINE: String = "broken_shrine_of_valor"
const MINOR: String = "minor"
const MAJOR: String = "major"
const SEVERE: String = "severe"
const RARE: String = "rare"

# Gold that meets none of the gold requirements (30, 40 and 50).
const POOR_GOLD: int = 10
# The HP a hurt unit is left on before a heal.
const HURT_HP: int = 1
# The share of max HP the cold deals and the heals restore, and the revive's.
const COLD_PERCENT: int = 20
const HEAL_PERCENT: int = 20
const REVIVE_PERCENT: int = 10
# What a Basic weapon scraps for at the default 20% rate once modified: items.md's Modified items
# examples (Basic prices 10, 25 and 40). Infuse's needs its effect's item_points (BUG-021).
const INFUSED_BASIC_SCRAP: int = 2
const UPGRADED_BASIC_SCRAP: int = 5
const RESONANT_BASIC_SCRAP: int = 8

var _report: Callable
var _fx: Fixture = null
var _pool: EventPool = null


func _init(check: Callable) -> void:
	_report = check


func run() -> void:
	_fx = Fixture.new()
	_check("content: the catalog and rules load", _fx.is_ready())
	if not _fx.is_ready():
		return
	_pool = EventPool.load_default()
	_test_pool()
	_test_named_ids()
	_test_dark_goblet()
	_test_cavern()
	_test_clockwork_hermit()
	_test_festival()
	_test_frozen_armory()
	_test_ghastly_library()
	_test_whispering_oak()
	_test_mirror()
	_test_shrine()
	_test_toll_solo()
	_test_toll_team()
	_test_cursed_hoard()
	_test_mercenary_camp()
	_test_black_altar()


func _test_pool() -> void:
	_check("content: the pool loads all 13 events with no problems", (
			_pool.problems.is_empty() and _ids(_pool.events) == EVENT_IDS
	), "%s %s" % [_ids(_pool.events), _pool.problems])
	var misnamed: PackedStringArray = []
	for entry: String in ResourceLoader.list_directory(EventPool.PATH):
		var definition: EventDefinition = load(EventPool.PATH + entry) as EventDefinition
		if definition == null or definition.id != entry.get_basename():
			misnamed.append(entry)
	_check("content: each event's id is its file name", misnamed.is_empty(), str(misnamed))
	var wrong: PackedStringArray = []
	for event: EventDefinition in _pool.events:
		if (event.art == null) != WITHOUT_ART.has(event.id):
			wrong.append("%s art" % [event.id])
		if event.is_team_choice != (event.id == TEAM_EVENT):
			wrong.append("%s team choice" % [event.id])
		var needs_fallen: bool = event.eligibility == EventDefinition.Eligibility.FALLEN_UNIT
		if needs_fallen != (event.id == SHRINE):
			wrong.append("%s eligibility" % [event.id])
		if event.title.is_empty() or event.text.is_empty():
			wrong.append("%s words" % [event.id])
		for option: EventOption in event.options:
			if option.title.is_empty() or option.text.is_empty():
				wrong.append("%s option words" % [event.id])
	_check("content: art on the nine Godot_FE events only, only the toll a team choice, only "
			+ "the shrine needing a fallen unit, and every event and option worded", (
			wrong.is_empty()
	), str(wrong))


func _test_named_ids() -> void:
	var catalog: EffectCatalog.Index = EffectCatalog.index()
	var named: PackedStringArray = []
	var missing: PackedStringArray = []
	for event: EventDefinition in _pool.events:
		for option: EventOption in event.options:
			missing.append_array(_missing(event.id, option, catalog, named))
	named.sort()
	_check("content: every id an event names exists in the catalog", (
			missing.is_empty()
	), str(missing))
	_check("content: the named ids are the four items and Infuse's effect", (
			named == NAMED_IDS
	), str(named))
	_check("content: the random pools the events draw from aren't empty", (
			_rare_weapons(catalog, false) > 0 and _rare_weapons(catalog, true) > 0
			and not catalog.all_of(EffectCatalog.Kind.TRINKET).is_empty()
			and not catalog.all_of(EffectCatalog.Kind.RUNE).is_empty()
			and _heirlooms_of(catalog, RARE) >= 2
			and not RecruitOffer.pool(catalog).is_empty()
	))


func _test_dark_goblet() -> void:
	var id: String = "dark_goblet"
	_check_stats(id, 0, EventOutcome.Target.CHOSEN, {
		CombatValue.Key.MGT: 2,
		CombatValue.Key.HP: -4,
	})
	var deltas: Dictionary[int, float] = {CombatValue.Key.NET_WEIGHT: 2.0}
	_check_weapon(id, 1, deltas, PackedStringArray(["goblet_infusion"]), INFUSED_BASIC_SCRAP)
	_check_item(id, 2, "cleansed_goblet")


func _test_cavern() -> void:
	var id: String = "cavern_of_echoing_steel"
	var deltas: Dictionary[int, float] = {
		CombatValue.Key.ATK_X: 1.0,
		CombatValue.Key.NET_WEIGHT: 4.0,
	}
	_check_weapon(id, 0, deltas, PackedStringArray(), RESONANT_BASIC_SCRAP)
	_check_stats(id, 1, EventOutcome.Target.CHOSEN, {CombatValue.Key.SPD: 2})
	_check_item(id, 2, "resonant_ore")


func _test_clockwork_hermit() -> void:
	var id: String = "clockwork_hermit"
	var deltas: Dictionary[int, float] = {
		DamageStage.Key.ATTACK: 1.0,
		CombatValue.Key.CRIT_CHANCE: 5.0,
		CombatValue.Key.NET_WEIGHT: 1.0,
	}
	_check_weapon(id, 0, deltas, PackedStringArray(), UPGRADED_BASIC_SCRAP)

	var augment: Play = _open(id)
	if augment != null:
		var seat_run: SeatRun = augment.seat_run()
		var unit: UnitInstance = _upgradable(augment)
		var gold: int = seat_run.gold
		var choice: EventChoice = EventChoice.new("" if unit == null else unit.instance_id)
		var is_played: bool = unit != null and _choose(augment, 1, choice)
		_check("clockwork_hermit: Augment Unit pays 40 gold and upgrades the chosen unit", (
				is_played and unit.is_upgraded and seat_run.gold == gold - 40
				and _facts_have(augment.batch, [
					CampaignFact.Kind.GOLD_CHANGED, CampaignFact.Kind.UNIT_UPGRADED,
				])
		), _why(augment))
	_check_greyed(id, 1, _poor, "needs 40 gold")
	_check_stats(id, 2, EventOutcome.Target.CHOSEN, {CombatValue.Key.HIT: 10})


func _test_festival() -> void:
	var id: String = "festival_of_embers"
	_check_stats(id, 0, EventOutcome.Target.EVERY, {CombatValue.Key.HP: 2})
	_check_item(id, 1, "emberglass_vial")
	_check_gold(id, 2, 40, "")


func _test_frozen_armory() -> void:
	var id: String = "frozen_armory"
	var play: Play = _open(id)
	if play != null:
		var seat_run: SeatRun = play.seat_run()
		var expected: PackedInt32Array = []
		for unit: UnitInstance in seat_run.army:
			var unit_max: int = _max_hp(unit)
			expected.append(maxi(unit_max - EventOutcome.percent_of(unit_max, COLD_PERCENT), 1))
		var picked: String = play.rolls(0).pick(0)
		var is_played: bool = _choose(play, 0)
		var weapon: ItemDefinition = _fx.catalog.item(picked)
		_check("frozen_armory: Break the Ice gives its rolled rare weapon, and the cold takes "
				+ "20% of every unit's max HP", (
				is_played and weapon is WeaponDefinition
				and weapon.rarity == ItemDefinition.Rarity.RARE
				and _gained_ids(play).has(picked) and _hp_of(seat_run.army) == expected
				and _count(play.batch, CampaignFact.Kind.HP_CHANGED) == seat_run.army.size()
		), "%s %s %s" % [_why(play), _hp_of(seat_run.army), expected])
	_check_stats(id, 1, EventOutcome.Target.CHOSEN, {CombatValue.Key.RES: 2})
	_check_heal(id, 2)


func _test_ghastly_library() -> void:
	var id: String = "ghastly_library"
	_check_stats(id, 0, EventOutcome.Target.COMMANDER, {
		CombatValue.Key.MGT: 2,
		CombatValue.Key.DEF: -1,
		CombatValue.Key.RES: -1,
	})
	_check_greyed(id, 0, _commander_fallen, "needs the commander")

	var play: Play = _open(id)
	if play != null:
		var picked: String = play.rolls(1).pick(0)
		var is_played: bool = _choose(play, 1)
		var tome: WeaponDefinition = _fx.catalog.weapon(picked)
		_check("ghastly_library: Take a Tome gives its rolled rare anima, holy or dark tome", (
				is_played and tome != null and tome.rarity == ItemDefinition.Rarity.RARE
				and ItemGrantOutcome.TOME_TYPES.has(tome.weapon_type)
				and _gained_ids(play).has(picked)
		), _why(play))

	var rune_play: Play = _open(id)
	if rune_play != null:
		var rune_id: String = rune_play.rolls(2).pick(0)
		var is_played: bool = _choose(rune_play, 2)
		var slots: PackedStringArray = []
		for slot: SeatRun.RuneSlot in rune_play.seat_run().rune_slots:
			slots.append(slot.definition_id)
		_check("ghastly_library: Ethereal Infusion puts its rolled rune in a rune slot", (
				is_played and _fx.catalog.rune(rune_id) != null and slots.has(rune_id)
				and _facts_have(rune_play.batch, [CampaignFact.Kind.GAINED])
		), _why(rune_play))


func _test_whispering_oak() -> void:
	var id: String = "whispering_oak"
	var play: Play = _open(id)
	if play != null:
		var unit: UnitInstance = _fx.soldier(play.seat_run())
		var unit_max: int = _max_hp(unit)
		var is_played: bool = _choose(play, 0, EventChoice.new(unit.instance_id))
		var gain: UnitInstance.PendingGain = (
				null if unit.pending_gains.is_empty() else unit.pending_gains[-1]
		)
		_check("whispering_oak: Drink the Sap: the chosen unit loses 2 max HP, and its next two "
				+ "level-ups each gain +1 MGT", (
				is_played and _max_hp(unit) == unit_max - 2 and gain != null
				and gain.stat == CombatValue.Stat.MGT and gain.amount == 1 and gain.remaining == 2
				and gain.source_id == id
				and _facts_have(play.batch, [CampaignFact.Kind.UNIT_CHANGED])
		), _why(play))
	_check_item(id, 1, "oak_wood_charm")
	_check_heal(id, 2)


func _test_mirror() -> void:
	var id: String = "mirror_of_doubt"
	var play: Play = _open(id)
	if play != null:
		var seat_run: SeatRun = play.seat_run()
		var commander: EventChoice = EventChoice.new(seat_run.commander_id)
		var refused: CampaignBatch = _fx.choose(play.made, play.events, 0, 0, commander)
		_check("mirror_of_doubt: Face Yourself can't re-roll the commander's prefix", (
				refused.is_rejected() and refused.rejected_reason.contains("commander")
		), refused.rejected_reason)
		var unit: UnitInstance = _fx.soldier(seat_run)
		var before: String = unit.prefix_id
		var is_played: bool = _choose(play, 0, EventChoice.new(unit.instance_id))
		_check("mirror_of_doubt: Face Yourself re-rolls the chosen unit's prefix, never same", (
				is_played and unit.prefix_id != before
				and _facts_have(play.batch, [CampaignFact.Kind.UNIT_CHANGED])
		), _why(play))

	var shatter: Play = _open(id)
	if shatter != null:
		var picked: String = shatter.rolls(1).pick(0)
		var is_played: bool = _choose(shatter, 1)
		_check("mirror_of_doubt: Shatter the Mirror gives its rolled trinket and a minor curse", (
				is_played and _fx.catalog.item(picked) is TrinketDefinition
				and _gained_ids(shatter).has(picked) and _has_curse(shatter, 1, MINOR)
		), _why(shatter))
	_check_nothing(id, 2)


func _test_shrine() -> void:
	var shrine: EventDefinition = _pool.event(SHRINE)
	var without: CampaignSession = _fx.unknown_session()
	var refused: CampaignBatch = _fx.open(without, EventPool.new([shrine]))
	var ctx: EventContext = EventContext.of(without.run, 0, shrine, 0, _fx.catalog)
	_check("broken_shrine_of_valor: without a fallen unit it can't be drawn, and the prayer "
			+ "would be greyed out", (
			not shrine.is_eligible(without.run.seat_run(0)) and refused.is_rejected()
			and EventResolver.unmet_reason(ctx) == "needs a fallen unit"
	), "%s / %s" % [refused.rejected_reason, EventResolver.unmet_reason(ctx)])

	var play: Play = _open(SHRINE, 1, _soldier_fallen)
	if play != null:
		var seat_run: SeatRun = play.seat_run()
		var fallen: UnitInstance = seat_run.fallen[0]
		var unit_max: int = _max_hp(fallen)
		var is_played: bool = _choose(play, 0, EventChoice.new(fallen.instance_id))
		var hp: int = maxi(EventOutcome.percent_of(unit_max, REVIVE_PERCENT), 1)
		var revived: CampaignFact = _first(play.batch, CampaignFact.Kind.UNIT_REVIVED)
		_check("broken_shrine_of_valor: Offer a Prayer returns the fallen unit at 10% of max HP", (
				is_played and seat_run.army.has(fallen) and seat_run.fallen.is_empty()
				and fallen.hp == hp and revived != null and revived.amount == hp
				and revived.actor_id == fallen.instance_id
		), _why(play))

	var relic: Play = _open(SHRINE, 1, _soldier_fallen)
	if relic != null:
		var picked: String = relic.rolls(1).pick(0)
		var is_played: bool = _choose(relic, 1)
		_check("broken_shrine_of_valor: Claim the Relic gives its rolled rare heirloom", (
				is_played and _is_rare_heirloom(picked)
				and relic.seat_run().heirloom_ids().has(picked)
		), _why(relic))


func _test_toll_solo() -> void:
	_check_gold(TEAM_EVENT, 0, -30, "")
	_check_greyed(TEAM_EVENT, 0, _poor, "needs 30 gold")
	var fight: Play = _open(TEAM_EVENT)
	if fight != null:
		var is_played: bool = _choose(fight, 1)
		var run: CampaignRunState = fight.made.run
		var request: CampaignSession.BattleRequest = run.battle_request(
				CombatMapPools.load_default(), _fx.catalog
		)
		_check("bandit_toll: Fight starts a surprise combat at the event's node", (
				is_played and run.events.is_combat_pending and request != null
				and request.node == run.node and request.floor_number == run.floor_number
		), _why(fight))
	_check_gold(TEAM_EVENT, 2, 40, MINOR)


func _test_toll_team() -> void:
	var poor: Play = _open(TEAM_EVENT, 2)
	if poor != null:
		poor.made.run.seat_run(1).gold = POOR_GOLD
		var view: EventView = EventNode.view(poor.made, 0, poor.events, _fx.catalog)
		var voted: CampaignBatch = _fx.vote(poor.made, poor.events, 0, 0)
		_check("bandit_toll: in a team, Pay the Toll is greyed out when a teammate can't pay", (
				view.is_team_vote and view.options[0].unmet_reason == "seat 1 needs 30 gold"
				and voted.is_rejected()
		), "%s / %s" % [view.options[0].unmet_reason, voted.rejected_reason])

	for option: int in [0, 1, 2]:
		var team: Play = _open(TEAM_EVENT, 2)
		if team == null:
			continue
		var gold: PackedInt32Array = [
			team.made.run.seat_run(0).gold,
			team.made.run.seat_run(1).gold,
		]
		_fx.vote(team.made, team.events, 0, option)
		_fx.vote(team.made, team.events, 1, option)
		var drawn: int = team.made.run.events.drawn_option()
		team.batch = _fx.choose(team.made, team.events, 0, option)
		if not team.batch.is_rejected():
			team.batch = _fx.choose(team.made, team.events, 1, option)
		var every: bool = drawn == option and not team.batch.is_rejected()
		for seat: int in [0, 1]:
			var seat_run: SeatRun = team.made.run.seat_run(seat)
			var curse: String = team.made.run.events.seat_event(seat).rolls_of(option).curse_id
			match option:
				0:
					every = every and seat_run.gold == gold[seat] - 30
				1:
					every = every and team.made.run.events.is_combat_pending
				2:
					every = every and seat_run.gold == gold[seat] + 40
					every = every and _fx.curses_of(MINOR).has(curse)
					every = every and seat_run.heirloom_ids().has(curse)
		_check("bandit_toll: a team vote for \"%s\" draws it and each seat applies it" % [
			_title(TEAM_EVENT, option),
		], every, _why(team))

	var split: Play = _open(TEAM_EVENT, 2)
	if split != null:
		_fx.vote(split.made, split.events, 0, 0)
		_fx.vote(split.made, split.events, 1, 2)
		var drawn: int = split.made.run.events.drawn_option()
		_check("bandit_toll: a split vote draws one of the voted options", (
				drawn in [0, 2]
		), str(drawn))


func _test_cursed_hoard() -> void:
	var id: String = "cursed_hoard"
	_check_gold(id, 0, 80, MAJOR)
	_check_gold(id, 1, 20, "")
	_check_nothing(id, 2)


func _test_mercenary_camp() -> void:
	var id: String = "mercenary_camp"
	var full: Play = _open(id)
	if full != null:
		var refused: CampaignBatch = _fx.choose(full.made, full.events, 0, 0)
		_check("mercenary_camp: a recruit into the full army needs a unit named to leave", (
				refused.is_rejected() and refused.rejected_reason.contains("the army is full")
		), refused.rejected_reason)

	var hire: Play = _open(id)
	if hire != null:
		var seat_run: SeatRun = hire.seat_run()
		var leaving: UnitInstance = _fx.soldier(seat_run)
		var level: int = RecruitOffer.level_for(seat_run)
		var gold: int = seat_run.gold
		var choice: EventChoice = EventChoice.new()
		choice.replaced_id = leaving.instance_id
		var is_played: bool = _choose(hire, 0, choice)
		var joined: UnitInstance = _recruited(hire)
		var prefix: UnitPrefixDefinition = (
				null if joined == null else _fx.catalog.unit_prefix(joined.prefix_id)
		)
		_check("mercenary_camp: Hire the Best pays 50 gold for a recruit with a +1 or +2 prefix "
				+ "at the army's average level, in place of the unit named", (
				is_played and joined != null and prefix != null and prefix.tier >= 1
				and joined.level == level and seat_run.gold == gold - 50
				and not seat_run.army.has(leaving)
				and _facts_have(hire.batch, [
					CampaignFact.Kind.GOLD_CHANGED,
					CampaignFact.Kind.UNIT_DISMISSED,
					CampaignFact.Kind.UNIT_RECRUITED,
				])
		), _why(hire))
	_check_greyed(id, 0, _poor, "needs 50 gold")

	var volunteer: Play = _open(id)
	if volunteer != null:
		var choice: EventChoice = EventChoice.new()
		choice.replaced_id = _fx.soldier(volunteer.seat_run()).instance_id
		var is_played: bool = _choose(volunteer, 1, choice)
		var joined: UnitInstance = _recruited(volunteer)
		_check("mercenary_camp: Take a Volunteer recruits an unprefixed unit, and a minor curse", (
				is_played and joined != null and joined.prefix_id.is_empty()
				and _has_curse(volunteer, 1, MINOR)
		), _why(volunteer))

	var charter: Play = _open(id)
	if charter != null:
		var seat_run: SeatRun = charter.seat_run()
		var size: int = RunOperations.max_army_size(seat_run, _fx.catalog)
		var is_played: bool = _choose(charter, 2)
		_check("mercenary_camp: Sign a Company Charter adds 1 max army size, and a major curse", (
				is_played and RunOperations.max_army_size(seat_run, _fx.catalog) == size + 1
				and _has_curse(charter, 2, MAJOR)
				and _facts_have(charter.batch, [CampaignFact.Kind.ARMY_SIZE_CHANGED])
		), _why(charter))
	_check_greyed(id, 2, _at_ceiling, "the army is already at its largest (8)")


func _test_black_altar() -> void:
	var id: String = "black_altar"
	var pact: Play = _open(id)
	if pact != null:
		var first: String = pact.rolls(0).pick(0)
		var second: String = pact.rolls(0).pick(1)
		var is_played: bool = _choose(pact, 0)
		var held: PackedStringArray = pact.seat_run().heirloom_ids()
		_check("black_altar: Accept the Pact gives two different rare heirlooms, a severe curse", (
				is_played and first != second and _is_rare_heirloom(first)
				and _is_rare_heirloom(second) and held.has(first) and held.has(second)
				and _has_curse(pact, 0, SEVERE)
		), _why(pact))

	var token: Play = _open(id)
	if token != null:
		var picked: String = token.rolls(1).pick(0)
		var is_played: bool = _choose(token, 1)
		_check("black_altar: Take a Token gives one rare heirloom and a major curse", (
				is_played and _is_rare_heirloom(picked)
				and token.seat_run().heirloom_ids().has(picked) and _has_curse(token, 1, MAJOR)
		), _why(token))
	_check_nothing(id, 2)


# Opens event_id alone in a new Mercenary run of seat_count seats inside an Unknown node, after
# prepare (given the run) when valid. Null, with a failed check, when it doesn't open.
func _open(event_id: String, seat_count: int = 1, prepare: Callable = Callable()) -> Play:
	var definition: EventDefinition = _pool.event(event_id)
	if definition == null:
		_check("%s: it is in the pool" % [event_id], false)
		return null
	var play: Play = Play.new()
	play.made = _fx.unknown_session(seat_count)
	play.events = EventPool.new([definition])
	if prepare.is_valid():
		prepare.call(play.made.run)
	var opened: CampaignBatch = _fx.open(play.made, play.events)
	if opened.is_rejected() or play.made.run.events.event_id != event_id:
		_check("%s: it opens" % [event_id], false, opened.rejected_reason)
		return null
	return play


# Seat 0 chooses option with choice, through the chooser stage when the option has one; whether
# it applied.
func _choose(play: Play, option: int, choice: EventChoice = null) -> bool:
	var definition: EventDefinition = play.events.event(play.made.run.events.event_id)
	if definition.options[option].chooser() != EventOutcome.Chooser.NONE:
		var staged: CampaignBatch = _fx.chooser(play.made, play.events, 0, option)
		if staged.is_rejected():
			play.batch = staged
			return false
	play.batch = _fx.choose(play.made, play.events, 0, option, choice)
	return not play.batch.is_rejected()


# Plays option on its target's units and checks each value in changes moved by its amount.
func _check_stats(
		event_id: String, option: int, target: EventOutcome.Target, changes: Dictionary[int, int]
) -> void:
	var play: Play = _open(event_id)
	if play == null:
		return
	var seat_run: SeatRun = play.seat_run()
	var units: Array[UnitInstance] = []
	match target:
		EventOutcome.Target.CHOSEN:
			units.append(_fx.soldier(seat_run))
		EventOutcome.Target.COMMANDER:
			units.append(seat_run.unit(seat_run.commander_id))
		EventOutcome.Target.EVERY:
			units.append_array(seat_run.army)
	var expected: PackedInt32Array = []
	for unit: UnitInstance in units:
		for key: int in changes:
			expected.append(_value(unit, key) + changes[key])
	var choice: EventChoice = (
			EventChoice.new(units[0].instance_id) if target == EventOutcome.Target.CHOSEN else null
	)
	var is_played: bool = _choose(play, option, choice)
	var found: PackedInt32Array = []
	for unit: UnitInstance in units:
		for key: int in changes:
			found.append(_value(unit, key))
	_check("%s: %s changes %s by %s" % [
		event_id, _title(event_id, option), _who(target), _changes_text(changes),
	], (
			is_played and found == expected
			and _count(play.batch, CampaignFact.Kind.UNIT_CHANGED) == units.size() * changes.size()
	), "%s found %s, wanted %s" % [_why(play), found, expected])


# Plays option on the first soldier's weapon, a Basic one, and checks its deltas from the event,
# its granted effects, and that it now scraps for basic_scrap at the default rate.
func _check_weapon(
		event_id: String,
		option: int,
		deltas: Dictionary[int, float],
		effects: PackedStringArray,
		basic_scrap: int
) -> void:
	var play: Play = _open(event_id)
	if play == null:
		return
	var seat_run: SeatRun = play.seat_run()
	var weapon: ItemInstance = seat_run.items.get(_fx.soldier(seat_run).weapon_id, null)
	if weapon == null:
		_check("%s: a soldier holds a weapon" % [event_id], false)
		return
	var is_played: bool = _choose(play, option, EventChoice.new("", weapon.instance_id))
	var found: Dictionary[int, float] = {}
	for delta: ItemInstance.StatDelta in weapon.stat_deltas:
		if delta.source_id == event_id:
			found[delta.key] = found.get(delta.key, 0.0) + delta.amount
	_check("%s: %s modifies the chosen weapon by %s%s" % [
		event_id, _title(event_id, option), _changes_text(deltas),
		"" if effects.is_empty() else " and %s" % [", ".join(effects)],
	], (
			is_played and found == deltas and weapon.granted_effect_ids == effects
			and weapon.is_modified()
			and _facts_have(play.batch, [CampaignFact.Kind.ITEM_MODIFIED])
	), "%s found %s %s" % [_why(play), found, weapon.granted_effect_ids])
	var definition: ItemDefinition = _fx.catalog.item(weapon.definition_id)
	var scrap: int = ItemPlacement.held_scrap_value(weapon, _fx.catalog)
	_check("%s: %s makes a Basic weapon scrap for %d at the default rate" % [
		event_id, _title(event_id, option), basic_scrap,
	], (
			definition != null and definition.rarity == ItemDefinition.Rarity.BASIC
			and scrap == basic_scrap
	), "%s scraps for %d" % [weapon.definition_id, scrap])


# Plays option and checks it gives item_id into the convoy.
func _check_item(event_id: String, option: int, item_id: String) -> void:
	var play: Play = _open(event_id)
	if play == null:
		return
	var is_played: bool = _choose(play, option)
	var in_convoy: bool = false
	for held_id: String in play.seat_run().convoy:
		in_convoy = in_convoy or play.seat_run().items[held_id].definition_id == item_id
	_check("%s: %s gives the %s, into the convoy" % [
		event_id, _title(event_id, option), item_id,
	], is_played and in_convoy and _gained_ids(play).has(item_id), _why(play))


# Plays option and checks gold moved by amount, with a curse of tier when tier isn't empty.
func _check_gold(event_id: String, option: int, amount: int, tier: String) -> void:
	var play: Play = _open(event_id)
	if play == null:
		return
	var gold: int = play.seat_run().gold
	var is_played: bool = _choose(play, option)
	var changed: CampaignFact = _first(play.batch, CampaignFact.Kind.GOLD_CHANGED)
	var cursed: bool = _has_curse(play, option, tier) if not tier.is_empty() else (
			_count(play.batch, CampaignFact.Kind.GAINED) == 0
	)
	_check("%s: %s changes gold by %d%s" % [
		event_id, _title(event_id, option), amount,
		"" if tier.is_empty() else " with a %s curse" % [tier],
	], (
			is_played and play.seat_run().gold == gold + amount
			and changed != null and changed.amount == amount and cursed
	), _why(play))


# Hurts every unit to HURT_HP, plays option, and checks each heals 20% of its max HP.
func _check_heal(event_id: String, option: int) -> void:
	var play: Play = _open(event_id)
	if play == null:
		return
	var army: Array[UnitInstance] = play.seat_run().army
	var expected: PackedInt32Array = []
	for unit: UnitInstance in army:
		unit.hp = HURT_HP
		var unit_max: int = _max_hp(unit)
		expected.append(mini(HURT_HP + EventOutcome.percent_of(unit_max, HEAL_PERCENT), unit_max))
	var is_played: bool = _choose(play, option)
	_check("%s: %s heals every unit 20%% of its max HP" % [event_id, _title(event_id, option)], (
			is_played and _hp_of(army) == expected
			and _count(play.batch, CampaignFact.Kind.HP_CHANGED) == army.size()
	), "%s %s %s" % [_why(play), _hp_of(army), expected])


# Plays option and checks only EVENT_CHOSEN is recorded: nothing changes.
func _check_nothing(event_id: String, option: int) -> void:
	var play: Play = _open(event_id)
	if play == null:
		return
	var gold: int = play.seat_run().gold
	var is_played: bool = _choose(play, option)
	_check("%s: %s changes nothing" % [event_id, _title(event_id, option)], (
			is_played and play.batch.facts.size() == 1
			and play.batch.facts[0].kind == CampaignFact.Kind.EVENT_CHOSEN
			and play.seat_run().gold == gold
	), _why(play))


# After prepare (given the run), option is greyed out with reason and choosing it is refused.
func _check_greyed(event_id: String, option: int, prepare: Callable, reason: String) -> void:
	var play: Play = _open(event_id, 1, prepare)
	if play == null:
		return
	var view: EventView = EventNode.view(play.made, 0, play.events, _fx.catalog)
	var refused: CampaignBatch = _fx.choose(play.made, play.events, 0, option)
	_check("%s: %s is greyed out: \"%s\"" % [event_id, _title(event_id, option), reason], (
			view.options[option].unmet_reason == reason and refused.is_rejected()
	), "%s / %s" % [view.options[option].unmet_reason, refused.rejected_reason])


func _poor(run: CampaignRunState) -> void:
	run.seat_run(0).gold = POOR_GOLD


func _commander_fallen(run: CampaignRunState) -> void:
	var seat_run: SeatRun = run.seat_run(0)
	_fx.fell(seat_run, seat_run.unit(seat_run.commander_id))


func _soldier_fallen(run: CampaignRunState) -> void:
	var seat_run: SeatRun = run.seat_run(0)
	_fx.fell(seat_run, _fx.soldier(seat_run))


func _at_ceiling(run: CampaignRunState) -> void:
	run.seat_run(0).faction_id = Fixture.FULL_FACTION


# Whether option's rolled curse is of tier, now held, and recorded as GAINED.
func _has_curse(play: Play, option: int, tier: String) -> bool:
	var curse_id: String = play.rolls(option).curse_id
	return (
			_fx.curses_of(tier).has(curse_id) and play.seat_run().heirloom_ids().has(curse_id)
			and _gained_ids(play).has(curse_id)
	)


# The definition ids of play's GAINED facts.
func _gained_ids(play: Play) -> PackedStringArray:
	var found: PackedStringArray = []
	for fact: CampaignFact in play.batch.facts:
		if fact.kind == CampaignFact.Kind.GAINED:
			found.append(fact.definition_id)
	return found


# The unit play's UNIT_RECRUITED fact names, in the army; null when none.
func _recruited(play: Play) -> UnitInstance:
	var fact: CampaignFact = _first(play.batch, CampaignFact.Kind.UNIT_RECRUITED)
	return null if fact == null else play.seat_run().unit(fact.actor_id)


# The first soldier Train can upgrade; null when none can.
func _upgradable(play: Play) -> UnitInstance:
	var seat_run: SeatRun = play.seat_run()
	for unit: UnitInstance in seat_run.army:
		if unit.instance_id != seat_run.commander_id and RunOperations.upgrade_problem(
				play.made.run, 0, unit.instance_id, _fx.catalog
		).is_empty():
			return unit
	return null


# Whether batch starts with EVENT_CHOSEN and holds every kind in wanted.
func _facts_have(batch: CampaignBatch, wanted: Array[CampaignFact.Kind]) -> bool:
	if batch == null or batch.facts.is_empty():
		return false
	if batch.facts[0].kind != CampaignFact.Kind.EVENT_CHOSEN:
		return false
	var kinds: Array[CampaignFact.Kind] = _fx.kinds(batch.facts)
	for kind: CampaignFact.Kind in wanted:
		if not kinds.has(kind):
			return false
	return true


func _count(batch: CampaignBatch, kind: CampaignFact.Kind) -> int:
	return 0 if batch == null else _fx.kinds(batch.facts).count(kind)


func _first(batch: CampaignBatch, kind: CampaignFact.Kind) -> CampaignFact:
	if batch == null:
		return null
	for fact: CampaignFact in batch.facts:
		if fact.kind == kind:
			return fact
	return null


# What went wrong with play, for a failed check: its refusal, or its facts' kinds.
func _why(play: Play) -> String:
	if play.batch == null:
		return "not played"
	if play.batch.is_rejected():
		return play.batch.rejected_reason
	return str(_fx.kinds(play.batch.facts))


func _value(unit: UnitInstance, key: int) -> int:
	return unit.stats(_fx.catalog).get_int(key)


func _max_hp(unit: UnitInstance) -> int:
	return EventOutcome.max_hp(unit, _fx.catalog)


func _hp_of(units: Array[UnitInstance]) -> PackedInt32Array:
	var found: PackedInt32Array = []
	for unit: UnitInstance in units:
		found.append(EventOutcome.current_hp(unit, _max_hp(unit)))
	return found


func _title(event_id: String, option: int) -> String:
	return _pool.event(event_id).options[option].title


# changes (int or float amounts by value key) as "+2 MGT, -4 HP", for case names.
func _changes_text(changes: Dictionary) -> String:
	var parts: PackedStringArray = []
	for key: int in changes:
		var named: Variant = CombatValue.Key.find_key(key)
		if named == null:
			named = DamageStage.Key.find_key(key)
		var amount: float = changes[key]
		parts.append("%+d %s" % [roundi(amount), "?" if named == null else named as String])
	return ", ".join(parts)


func _who(target: EventOutcome.Target) -> String:
	match target:
		EventOutcome.Target.EVERY:
			return "every unit"
		EventOutcome.Target.COMMANDER:
			return "the commander"
	return "the chosen unit"


func _is_rare_heirloom(heirloom_id: String) -> bool:
	var heirloom: HeirloomDefinition = _fx.catalog.heirloom(heirloom_id)
	return heirloom != null and not heirloom is CurseDefinition and heirloom.tier == RARE


func _ids(events: Array[EventDefinition]) -> PackedStringArray:
	var ids: PackedStringArray = []
	for event: EventDefinition in events:
		ids.append(event.id)
	return ids


# The references option of event_id makes that catalog lacks, one line each; each id it names
# outright is added to named.
func _missing(
		event_id: String,
		option: EventOption,
		catalog: EffectCatalog.Index,
		named: PackedStringArray
) -> PackedStringArray:
	var wanted: Dictionary[String, bool] = {}
	if not option.curse_id.is_empty():
		wanted[option.curse_id] = catalog.curse(option.curse_id) != null
	if not option.curse_tier.is_empty():
		wanted["curse tier " + option.curse_tier] = _curses_of(catalog, option.curse_tier) > 0
	var needs: EventRequirements = option.requirements
	if needs != null and not needs.unit_type_id.is_empty():
		wanted[needs.unit_type_id] = catalog.unit_type(needs.unit_type_id) != null
	if needs != null and not needs.item_id.is_empty():
		wanted[needs.item_id] = catalog.item(needs.item_id) != null
	for outcome: EventOutcome in option.outcomes:
		_wanted_by(outcome, catalog, wanted)
	var missing: PackedStringArray = []
	for id: String in wanted:
		if not id.contains(" "):
			named.append(id)
		if not wanted[id]:
			missing.append("%s \"%s\": %s" % [event_id, option.title, id])
	return missing


# Adds each id outcome names to wanted, with whether catalog has it.
func _wanted_by(
		outcome: EventOutcome, catalog: EffectCatalog.Index, wanted: Dictionary[String, bool]
) -> void:
	var grant: ItemGrantOutcome = outcome as ItemGrantOutcome
	if grant != null and grant.random == ItemGrantOutcome.RandomItem.NONE:
		wanted[grant.item_id] = catalog.item(grant.item_id) != null
	var modification: ItemModificationOutcome = outcome as ItemModificationOutcome
	if modification != null:
		for effect_id: String in modification.effect_ids:
			wanted[effect_id] = catalog.effect(effect_id) != null
	var prefix: WeaponPrefixOutcome = outcome as WeaponPrefixOutcome
	if prefix != null:
		wanted[prefix.prefix_id] = catalog.weapon_prefix(prefix.prefix_id) != null
	var recruit: RecruitOutcome = outcome as RecruitOutcome
	if recruit != null:
		if not recruit.unit_type_id.is_empty():
			wanted[recruit.unit_type_id] = catalog.unit_type(recruit.unit_type_id) != null
		if not recruit.prefix_id.is_empty():
			wanted[recruit.prefix_id] = catalog.unit_prefix(recruit.prefix_id) != null
		for item_id: String in recruit.gear_ids:
			wanted[item_id] = catalog.item(item_id) != null
	var heirloom: HeirloomOutcome = outcome as HeirloomOutcome
	if heirloom != null and not heirloom.heirloom_id.is_empty():
		wanted[heirloom.heirloom_id] = catalog.heirloom(heirloom.heirloom_id) != null
	elif heirloom != null:
		wanted["heirloom tier " + heirloom.tier] = _heirlooms_of(catalog, heirloom.tier) > 0
	var rune: RuneOutcome = outcome as RuneOutcome
	if rune != null and not rune.is_random:
		wanted[rune.rune_id] = catalog.rune(rune.rune_id) != null
	var curse: CurseOutcome = outcome as CurseOutcome
	if curse != null:
		wanted[curse.curse_id] = catalog.curse(curse.curse_id) != null


func _curses_of(catalog: EffectCatalog.Index, tier: String) -> int:
	var found: int = 0
	for definition: Resource in catalog.all_of(EffectCatalog.Kind.CURSE):
		var curse: CurseDefinition = definition as CurseDefinition
		if curse != null and curse.tier == tier:
			found += 1
	return found


# The heirlooms of tier in catalog, curses left out.
func _heirlooms_of(catalog: EffectCatalog.Index, tier: String) -> int:
	var found: int = 0
	for definition: Resource in catalog.all_of(EffectCatalog.Kind.HEIRLOOM):
		var heirloom: HeirloomDefinition = definition as HeirloomDefinition
		if heirloom != null and not heirloom is CurseDefinition and heirloom.tier == tier:
			found += 1
	return found


# The Rare weapons in catalog, or the Rare anima, holy and dark ones when tomes_only.
func _rare_weapons(catalog: EffectCatalog.Index, tomes_only: bool) -> int:
	var found: int = 0
	for definition: Resource in catalog.all_of(EffectCatalog.Kind.WEAPON):
		var weapon: WeaponDefinition = definition as WeaponDefinition
		if weapon == null or weapon.rarity != ItemDefinition.Rarity.RARE:
			continue
		if not tomes_only or ItemGrantOutcome.TOME_TYPES.has(weapon.weapon_type):
			found += 1
	return found


func _check(case_name: String, passed: bool, detail: String = "") -> void:
	_report.call(case_name, passed, detail)


# One event opened for play: its session, its one-event pool, and the last choice's batch.
class Play:
	extends RefCounted

	var made: CampaignSession = null
	var events: EventPool = null
	var batch: CampaignBatch = null

	func seat_run() -> SeatRun:
		return made.run.seat_run(0)

	func rolls(option: int) -> EventRolls:
		return made.run.events.seat_event(0).rolls_of(option)
