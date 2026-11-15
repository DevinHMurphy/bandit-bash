# ==============================================================================
# Bandit Bash
# Copyright (c) 2026 Derc Development
# Licensed under the MIT License. See LICENSE.
#
# File:     hint_source.gd
# Author:
# Created:  November 14, 2026
# Modified: November 14, 2026
# ==============================================================================

class_name HintSource
extends Node
## What a [ControlHintBar] shows: the screen's hint context and the input actions live in it.
##
## The battle screen's is its [BattleController]; the other screens use [ScreenHints]. A subclass
## overrides [method get_hint_context] and [method get_live_actions], and emits
## [signal live_actions_changed] when its actions change within one context. The bar polls the
## context once a frame, so it must stay cheap. This base shows nothing.

## What [method get_live_actions] returns may have changed without a change of hint context.
signal live_actions_changed()


## The context the screen is in, which picks the bar's labels ([member ControlHintBar.labels]);
## empty for none, which hides the bar.
func get_hint_context() -> StringName:
	return &""


## The input actions live in [method get_hint_context], in the order the bar shows them.
func get_live_actions() -> Array[StringName]:
	return []
