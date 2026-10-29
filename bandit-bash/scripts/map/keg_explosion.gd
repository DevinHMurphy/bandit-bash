# ==============================================================================
# Bandit Bash
# Copyright (c) 2026 Derc Development
# Licensed under the MIT License. See LICENSE.
#
# File:     keg_explosion.gd
# Author:
# Created:  October 29, 2026
# Modified: October 29, 2026
# ==============================================================================

@tool
class_name KegExplosion
extends CustomOperation
## A powder keg's reaction to any hit or splash it takes: it breaks and explodes
## ([method MapObjects.detonate]).
##
## Owned by the keg ([constant EffectOwner.Kind.MAP_OBJECT]), so the reaction counts toward neither
## reaction cap and a chain of kegs is never cut short (event bus plan, question 27). Built by
## [MapObjects] for every keg it places; no content authors it.
##
## @tutorial(Map objects): docs/design/map-objects.md


## Breaks the keg that owns [param ctx]'s effect, credited to the fact's other party: the attacker
## of a hit, the source of a splash.
func apply(ctx: EffectContext) -> void:
	var state: CombatState = ctx.engine.state as CombatState
	if state == null:
		ctx.engine.diagnostics.append("KegExplosion: the engine's state is not a combat state")
		return
	var by_id: String = "" if ctx.fact == null else ctx.fact.target_id
	MapObjects.detonate(ctx.engine, state, ctx.instance.owner.owner_id, by_id)
