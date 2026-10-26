# ==============================================================================
# Bandit Bash
# Copyright (c) 2026 Derc Development
# Licensed under the MIT License. See LICENSE.
#
# File:     deal_splash.gd
# Author:
# Created:  October 26, 2026
# Modified: October 26, 2026
# ==============================================================================

@tool
class_name DealSplash
extends EffectOperation
## Deals splash damage: "deal 2 splash damage to adjacent units, friend or foe" (Cleave).
##
## Queued. Splash is flat damage, not an attack: no hit roll, no Mitigation, no crit, no Stance
## loss; Block absorbs it and it fires Damage taken, never Hit taken (effect-triggers.md).
##
## @tutorial(Effect triggers): docs/design/effect-triggers.md

## Who takes the splash. [b]Null:[/b] the effect's owner.
@export var target: TargetSelector = null

## Damage dealt to each unit. [b]Null:[/b] a content error (deals nothing).
@export var amount: ValueSource = null


func describe() -> String:
	var who: String = "this unit" if target == null else target.describe()
	var how_much: String = "?" if amount == null else amount.describe()
	if amount is Constant:
		return "deal %s splash damage to %s" % [how_much, who]
	return "deal splash damage equal to %s to %s" % [how_much, who]
