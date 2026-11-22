# ==============================================================================
# Bandit Bash
# Copyright (c) 2026 Derc Development
# Licensed under the MIT License. See LICENSE.
#
# File:     triangle_change.gd
# Author:
# Created:  November 19, 2026
# Modified: November 21, 2026
# ==============================================================================

@tool
class_name TriangleChange
extends ValueSource
## The weapon triangle's own change to this unit's attack: "its triangle damage change", "its
## triangle Hit change" (Tactician's Manual, which adds each once more, so the triangle doubles).
##
## Signed, as [WeaponTriangle] gives it: positive on Advantage, negative on Disadvantage, 0 on a
## Standoff, outside an attack, and for a unit that isn't the one attacking, since only the
## attacker's Attack and Hit read the triangle. The damage part is
## [method WeaponTriangle.damage_change] of the attack's weapon, so the doubling keeps the
## triangle's own rounding.
##
## @tutorial(Heirlooms, Starting heirlooms): docs/design/heirlooms.md

## Which change of the triangle is read.
enum Part {
	## The damage change: a quarter of the weapon's damage, halves up, at least 1.
	DAMAGE = 0,
	## The Hit change: [constant WeaponTriangle.HIT_CHANGE].
	HIT = 1,
}

## Which change is read.
@export var part: Part = Part.DAMAGE


func describe() -> String:
	var changed: String = "Hit" if part == Part.HIT else "damage"
	return "its triangle %s change" % [EffectTerms.mark(changed)]


## The change for the queried unit ([member EffectContext.subject_id]) in [param ctx]'s attack;
## 0 unless that unit is the attacker.
func evaluate(ctx: EffectContext) -> float:
	if ctx.subject_id.is_empty() or ctx.subject_id != ctx.attacker_id:
		return 0.0
	var matchup: WhileMatchupCondition.Matchup = ctx.matchup
	if part == Part.HIT:
		return float(WeaponTriangle.hit_change(matchup))
	var state: CombatState = null if ctx.engine == null else ctx.engine.state as CombatState
	if state == null:
		return 0.0
	var weapon: CombatState.WeaponStats = state.weapon(ctx.weapon_id)
	var weapon_damage: float = 0.0 if weapon == null else float(weapon.damage)
	return float(WeaponTriangle.damage_change(matchup, weapon_damage))
