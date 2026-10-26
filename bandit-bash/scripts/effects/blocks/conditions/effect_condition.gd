# ==============================================================================
# Bandit Bash
# Copyright (c) 2026 Derc Development
# Licensed under the MIT License. See LICENSE.
#
# File:     effect_condition.gd
# Author:
# Created:  October 26, 2026
# Modified: October 26, 2026
# ==============================================================================

@tool
@abstract
class_name EffectCondition
extends Resource
## Base for a test an effect must pass before its operations run: Counter, Chance or While
## (effect-triggers.md, Conditions).
##
## Subclasses are inspector blocks in [member EffectDefinition.conditions]; read-only at runtime.
## Counter state lives on the effect's runtime instance, never here.
##
## @tutorial(Effect triggers): docs/design/effect-triggers.md


## This condition as effect text, such as "while Exposed" or "25% chance". Never empty.
@abstract func describe() -> String
