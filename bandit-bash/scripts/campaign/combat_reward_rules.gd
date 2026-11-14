# ==============================================================================
# Bandit Bash
# Copyright (c) 2026 Derc Development
# Licensed under the MIT License. See LICENSE.
#
# File:     combat_reward_rules.gd
# Author:
# Created:  November 14, 2026
# Modified: November 14, 2026
# ==============================================================================

class_name CombatRewardRules
extends Resource
## What a won combat pays: gold, shared and personal XP, the Standout, levels, a fallen
## commander's return and the item pick's slot and rarity odds. Read by [CombatGrades],
## [XpAward], [LevelUp], [ItemPick] and [method CampaignRunState.apply_battle].
##
## The run's copy lives in [constant DEFAULT_PATH]; values are game-vision.md's first pass (Run
## structure, Gold, Units: Experience) and the campaign plan's item pick tables, all to tune in
## playtesting. Read-only at runtime. The defaults here are 0 so a missing value shows in tests.
##
## @tutorial(Campaign and run flow): docs/plans/2026-10-24-campaign-run-flow.md

## Where the run's rules are.
const DEFAULT_PATH: String = "res://data/campaign/combat_rewards.tres"

@export_group("Gold")

## Gold a won Standard combat pays before grades and bonuses.[br]
## [b]Units:[/b] gold. [b]0:[/b] pays nothing but bonuses.
@export_range(0, 1000, 1, "or_greater") var standard_gold: int = 0

## Gold a won Key combat pays before grades and bonuses.[br]
## [b]Units:[/b] gold. [b]0:[/b] pays nothing but bonuses.
@export_range(0, 1000, 1, "or_greater") var key_gold: int = 0

## Gold a won Boss combat pays before grades and bonuses; the run ends after it.[br]
## [b]Units:[/b] gold. [b]0:[/b] pays nothing but bonuses.
@export_range(0, 1000, 1, "or_greater") var boss_gold: int = 0

@export_group("Shared XP")

## XP every surviving unit gets from a won Standard combat.[br]
## [b]Units:[/b] XP. [b]0:[/b] only personal XP and the Standout.
@export_range(0, 500, 1, "or_greater") var standard_shared_xp: int = 0

## XP every surviving unit gets from a won Key combat.[br]
## [b]Units:[/b] XP. [b]0:[/b] only personal XP and the Standout.
@export_range(0, 500, 1, "or_greater") var key_shared_xp: int = 0

## XP every surviving unit gets from a won Boss combat.[br]
## [b]Units:[/b] XP. [b]0:[/b] only personal XP and the Standout.
@export_range(0, 500, 1, "or_greater") var boss_shared_xp: int = 0

@export_group("Personal XP")

## Personal XP per hit on an enemy, a fully absorbed one included.[br]
## [b]Units:[/b] XP per action. [b]0:[/b] hits earn none, but still count for the Standout.
@export_range(0, 50, 1, "or_greater") var hit_xp: int = 0

## Personal XP per enemy defeated; a killing blow also earns [member hit_xp].[br]
## [b]Units:[/b] XP per action. [b]0:[/b] defeats earn none, but still count for the Standout.
@export_range(0, 50, 1, "or_greater") var defeat_xp: int = 0

## Personal XP per heal given to another player unit.[br]
## [b]Units:[/b] XP per action. [b]0:[/b] heals earn none, but still count for the Standout.
@export_range(0, 50, 1, "or_greater") var heal_xp: int = 0

## Personal XP per Block given to another player unit.[br]
## [b]Units:[/b] XP per action. [b]0:[/b] Block earns none, but still counts for the Standout.
@export_range(0, 50, 1, "or_greater") var block_xp: int = 0

## Personal XP per non-combat action: a point closed, a container searched, a chest opened.[br]
## [b]Units:[/b] XP per action. [b]0:[/b] they earn none, but still count for the Standout.
@export_range(0, 50, 1, "or_greater") var non_combat_xp: int = 0

## Most personal XP one unit earns in one combat; the Standout's XP comes on top.[br]
## [b]Units:[/b] XP. [b]0:[/b] no personal XP at all.
@export_range(0, 200, 1, "or_greater") var personal_xp_cap: int = 0

## XP the Standout gets on top of the cap.[br]
## [b]Units:[/b] XP. [b]0:[/b] the Standout is named but earns nothing.
@export_range(0, 100, 1, "or_greater") var standout_xp: int = 0

@export_group("Levels")

## XP a unit needs for each level-up, at every level; what is left over carries.[br]
## [b]Units:[/b] XP. At least 1.
@export_range(1, 1000, 1, "or_greater") var xp_per_level: int = 1

## The HP a fallen commander comes back with after its combat, out of its max HP in that battle,
## halves rounding up, never below 1.[br]
## [b]Units:[/b] percent. [b]0:[/b] it comes back at 1 HP.
@export_range(0, 100, 1) var fallen_commander_hp_percent: int = 0

@export_group("Item pick")

## Items one pick offers, all different.[br]
## [b]Units:[/b] items. [b]0:[/b] no pick is offered.
@export_range(0, 10, 1) var offer_count: int = 0

## Weight of a Weapon pick among the three slot kinds.[br]
## [b]Units:[/b] relative weight. [b]0:[/b] never a Weapon pick.
@export_range(0, 100, 1) var weapon_pick_weight: int = 0

## Weight of an Equipment pick among the three slot kinds.[br]
## [b]Units:[/b] relative weight. [b]0:[/b] never an Equipment pick.
@export_range(0, 100, 1) var equipment_pick_weight: int = 0

## Weight of a Pouch pick (trinkets and consumables) among the three slot kinds.[br]
## [b]Units:[/b] relative weight. [b]0:[/b] never a Pouch pick.
@export_range(0, 100, 1) var pouch_pick_weight: int = 0

## The chance each weapon offered is of a type the army can use; otherwise any type.[br]
## [b]Units:[/b] percent. [b]0:[/b] any type always. [b]100:[/b] usable types whenever any exist.
@export_range(0, 100, 1) var usable_weapon_chance: int = 0

## A Standard combat's Common, Uncommon and Rare chances for each offer, before the rare offset.[br]
## [b]Units:[/b] percent, each. [b]0:[/b] that rarity is never rolled (offset aside).
@export_range(0, 100, 1) var standard_common: int = 0
## See [member standard_common].
@export_range(0, 100, 1) var standard_uncommon: int = 0
## See [member standard_common].
@export_range(0, 100, 1) var standard_rare: int = 0

## A Key combat's Common, Uncommon and Rare chances for each offer, before the rare offset.[br]
## [b]Units:[/b] percent, each. [b]0:[/b] that rarity is never rolled (offset aside).
@export_range(0, 100, 1) var key_common: int = 0
## See [member key_common].
@export_range(0, 100, 1) var key_uncommon: int = 0
## See [member key_common].
@export_range(0, 100, 1) var key_rare: int = 0

## How much the seat's rare offset rises for each Common offer shown, up to
## [constant SeatRun.RARE_OFFSET_CAP].[br]
## [b]Units:[/b] percentage points. [b]0:[/b] the offset only ever resets.
@export_range(0, 10, 1) var rare_offset_step: int = 0


## Gold a won combat of [param combat_type] pays before grades and bonuses.
func gold_for(combat_type: CombatMapDefinition.CombatType) -> int:
	match combat_type:
		CombatMapDefinition.CombatType.KEY:
			return key_gold
		CombatMapDefinition.CombatType.BOSS:
			return boss_gold
	return standard_gold


## Shared XP a won combat of [param combat_type] pays every surviving unit.
func shared_xp_for(combat_type: CombatMapDefinition.CombatType) -> int:
	match combat_type:
		CombatMapDefinition.CombatType.KEY:
			return key_shared_xp
		CombatMapDefinition.CombatType.BOSS:
			return boss_shared_xp
	return standard_shared_xp


## Personal XP for one [param action].
func personal_xp_for(action: BattleTally.Action) -> int:
	match action:
		BattleTally.Action.HIT:
			return hit_xp
		BattleTally.Action.DEFEAT:
			return defeat_xp
		BattleTally.Action.HEAL:
			return heal_xp
		BattleTally.Action.BLOCK:
			return block_xp
		BattleTally.Action.NON_COMBAT:
			return non_combat_xp
	return 0


## The weights of [enum ItemPick.Slot]'s kinds, in its order.
func slot_weights() -> PackedInt32Array:
	return PackedInt32Array([weapon_pick_weight, equipment_pick_weight, pouch_pick_weight])


## A combat of [param combat_type]'s Common, Uncommon and Rare chances, in that order, before the
## rare offset. A Boss combat offers no pick; it reads as Standard.
func rarity_table(combat_type: CombatMapDefinition.CombatType) -> PackedInt32Array:
	if combat_type == CombatMapDefinition.CombatType.KEY:
		return PackedInt32Array([key_common, key_uncommon, key_rare])
	return PackedInt32Array([standard_common, standard_uncommon, standard_rare])


## The rules at [constant DEFAULT_PATH]; null, with an error, when they don't load.
static func load_default() -> CombatRewardRules:
	var loaded: CombatRewardRules = load(DEFAULT_PATH) as CombatRewardRules
	if loaded == null:
		push_error("CombatRewardRules: no reward rules at %s" % [DEFAULT_PATH])
	return loaded
