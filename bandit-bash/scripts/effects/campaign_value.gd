# ==============================================================================
# Bandit Bash
# Copyright (c) 2026 Derc Development
# Licensed under the MIT License. See LICENSE.
#
# File:     campaign_value.gd
# Author:
# Created:  October 26, 2026
# Modified: October 26, 2026
# ==============================================================================

class_name CampaignValue
extends RefCounted
## Value and permission keys of the campaign layer, per player (seat).
##
## The keys from the event bus plan's Campaign hooks, including the combat-layer keys read once at
## battle start ([constant DARKNESS_ARRIVAL_OFFSET], [constant POUCH_ITEM_WEIGHT]). Steady numbers
## such as gold and prices are queries on these keys, not triggers. Never instantiated.
##
## @tutorial(Event bus plan): docs/plans/2026-10-23-event-bus-and-effects.md
##
## @todo: TOD-001 - Let a modifier name the stat for STAT_CAN_GROW and LEVEL_UP_GUARANTEED_GAINS.

## A campaign value. Values live in this class's block (2000 to 2999), unique across every value
## key class. [b]Append only[/b], with explicit values.
enum Key {
	## Gold from a won combat (Bounty Ledger).
	COMBAT_GOLD = 2000,
	## Grade bonus, in percentage points (Gilded Purse).
	GRADE_BONUS_PERCENT = 2001,
	## Shared XP, in percent (Veteran's Medal).
	SHARED_XP_PERCENT = 2002,
	## A unit's own XP, in percent (Family Ring).
	UNIT_XP_PERCENT = 2003,
	## Scrap value, in percentage points of the price (Scrapper's Tongs).
	SCRAP_PERCENT = 2004,
	## Items the Armory stocks (Merchant's Ledger).
	ARMORY_STOCK = 2005,
	## Recruits the Guildhall offers (Guild Charter).
	GUILDHALL_RECRUITS = 2006,
	## Shop prices, in percent (Membership Seal).
	PRICE_PERCENT = 2007,
	## Free shop rerolls (Tinker's Token).
	FREE_REROLLS = 2008,
	## Most units the army may hold. Never above 8 (a game rule).
	MAX_ARMY_SIZE = 2009,
	## Extra enemies in each combat (Hunted).
	EXTRA_ENEMIES = 2010,
	## Healing received, in percent, on both layers (Cursed Blood, Cleansed Goblet).
	HEALING_RECEIVED_PERCENT = 2011,
	# TODO(TOD-001): Modifiers can't name the stat yet; base stat keys arrive with the units plan.
	## Stats a level-up raises regardless of growths (Training Weights). Per stat.
	LEVEL_UP_GUARANTEED_GAINS = 2012,
	## Fewest stats a level-up raises (Royal Crest).
	LEVEL_UP_MIN_STATS = 2013,
	## Turns the darkness arrives later, read at battle start (Short Wick).
	DARKNESS_ARRIVAL_OFFSET = 2014,
	## Weight of each Pouch item, read at battle start (Heavy Pack). 0 unless modified.
	POUCH_ITEM_WEIGHT = 2015,
}

## A campaign permission: any denial beats any grant. Values live in this class's permission
## block (4000 to 4999). [b]Append only[/b], with explicit values.
enum Permission {
	## Enemy intents are hidden from this player's UI (Clouded Sight). Off by default.
	INTENTS_HIDDEN = 4000,
	## A stat may grow on level-up; Training Weights denies Speed. Allowed by default. Per stat.
	STAT_CAN_GROW = 4001,
}

## Rounding of each key; keys not listed round [constant ValueBreakdown.HALF_UP].
const ROUNDING: Dictionary[int, int] = {}

## Game-rule lower bounds, applied after every modifier. None.
const RULE_MIN: Dictionary[int, float] = {}

## Game-rule upper bounds, applied after every modifier, even a fixed one.
const RULE_MAX: Dictionary[int, float] = {
	Key.MAX_ARMY_SIZE: 8.0,
}

## The answer of each permission that no modifier grants or denies.
const PERMISSION_DEFAULTS: Dictionary[int, bool] = {
	Permission.INTENTS_HIDDEN: false,
	Permission.STAT_CAN_GROW: true,
}
