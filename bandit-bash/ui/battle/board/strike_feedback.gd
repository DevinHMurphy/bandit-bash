# ==============================================================================
# Bandit Bash
# Copyright (c) 2026 Derc Development
# Licensed under the MIT License. See LICENSE.
#
# File:     strike_feedback.gd
# Author:
# Created:  November 19, 2026
# Modified: November 19, 2026
# ==============================================================================

class_name StrikeFeedback
extends Node
## The look of each strike result on the board, one [StrikeLook] per [enum Kind]: hit, miss,
## crit, no damage, Block absorbed, Stance lost, Stance broken and splash (game-vision.md, Combat).
##
## [BattleView] calls [method play] as each fact plays, never before, and steps the tweens it
## returns with its other cosmetic animations, so fast-forward speeds them and a skip finishes
## them; playback never waits on them. A crit's flash and shake are the board's own
## ([member BattleView.crit_flash_time], [member BattleView.crit_shake_strength]); its look here
## adds the pop. Holds no rules and changes no state.
##
## @tutorial(UI lift, UL6): docs/design/ui-lift.md

## A strike result. Append only: [signal BattleView.feedback_played] carries these values.
enum Kind {
	## A hit whose damage got past Block.
	HIT = 0,
	## A strike that missed; played on the unit that dodged it.
	MISS = 1,
	## A critical hit (only on an Exposed unit).
	CRIT = 2,
	## A hit fully countered: 0 damage.
	NO_DAMAGE = 3,
	## Block absorbed some or all of a hit's or a splash's damage.
	BLOCK_ABSORBED = 4,
	## The unit lost Stance.
	STANCE_LOST = 5,
	## The unit's Stance broke: it is Exposed.
	STANCE_BROKEN = 6,
	## Damage with no hit roll: splash, a bump, a spike or an effect.
	SPLASH = 7,
}

# ASSUMPTION: the scene's pop, 1.15 over 0.15 s, has no basis; the flash is the crit's 0.1 s.
## A hit past Block: a short white flash and a small pop.
@export var hit_look: StrikeLook = null

## A miss: the "Miss" pop-up carries it; nothing by default.
@export var miss_look: StrikeLook = null

# ASSUMPTION: the scene's crit pop, 1.25 over 0.15 s, has no basis.
## A crit: the pop, larger than a hit's; the board adds its flash and shake.
@export var crit_look: StrikeLook = null

## A hit for 0: the "No damage" pop-up carries it; nothing by default.
@export var no_damage_look: StrikeLook = null

# ASSUMPTION: the scene's 0.1 s flash and the badge's 1.3 pulse over 0.15 s have no basis.
## Block absorbing damage: a flash in the Block colour and a pulse of the Block badge.
@export var block_absorbed_look: StrikeLook = null

## Stance lost: the pips' own flash and the Stance number carry it; nothing by default.
@export var stance_lost_look: StrikeLook = null

## Stance broken: the "Exposed" pop-up and the pips carry it; nothing by default.
@export var stance_broken_look: StrikeLook = null

# ASSUMPTION: the scene's 0.1 s splash flash has no basis; it matches a hit's.
## Damage with no roll: a short flash in the danger colour, with no pop or shake.
@export var splash_look: StrikeLook = null


## Plays [param kind]'s look on [param token] (and [param camera] for a shake; null for none), and
## returns its tweens, paused for the caller to step ([method Tween.custom_step]). Empty when the
## kind has no look, or its look does nothing.
func play(kind: Kind, token: UnitToken, camera: CameraRig) -> Array[Tween]:
	var tweens: Array[Tween] = []
	var look: StrikeLook = look_of(kind)
	if look == null or not is_instance_valid(token):
		return tweens
	_add(tweens, token.flash(look.flash_tint(), look.flash_time))
	_add(tweens, _pop(token, look.pop_scale, look.pop_time))
	if is_instance_valid(camera):
		_add(tweens, camera.shake(look.shake_strength, look.shake_time))
	var badge: BlockBadge = token.get_block_badge()
	if badge != null:
		_add(tweens, _pop(badge, look.badge_pulse_scale, look.pop_time))
	return tweens


## The look [param kind] plays; null for none.
func look_of(kind: Kind) -> StrikeLook:
	match kind:
		Kind.HIT:
			return hit_look
		Kind.MISS:
			return miss_look
		Kind.CRIT:
			return crit_look
		Kind.NO_DAMAGE:
			return no_damage_look
		Kind.BLOCK_ABSORBED:
			return block_absorbed_look
		Kind.STANCE_LOST:
			return stance_lost_look
		Kind.STANCE_BROKEN:
			return stance_broken_look
		Kind.SPLASH:
			return splash_look
	return null


func _add(tweens: Array[Tween], tween: Tween) -> void:
	if tween != null:
		tweens.append(tween)


# Grows target (a Node2D or a Control, about its centre) to peak and back over seconds, ending at
# its rest scale of 1; null when peak is 1 or seconds is 0.
func _pop(target: CanvasItem, peak: float, seconds: float) -> Tween:
	if peak <= 1.0 or seconds <= 0.0:
		return null
	var control: Control = target as Control
	if control != null:
		control.pivot_offset = control.size * 0.5
	var tween: Tween = target.create_tween()
	tween.pause()
	tween.tween_property(target, ^"scale", Vector2(peak, peak), seconds * 0.5)
	tween.tween_property(target, ^"scale", Vector2.ONE, seconds * 0.5)
	return tween
