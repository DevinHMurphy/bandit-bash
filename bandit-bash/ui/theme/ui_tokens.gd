# ==============================================================================
# Bandit Bash
# Copyright (c) 2026 Derc Development
# Licensed under the MIT License. See LICENSE.
#
# File:     ui_tokens.gd
# Author:
# Created:  November 18, 2026
# Modified: November 18, 2026
# ==============================================================================

class_name UiTokens
extends RefCounted
## The UI style guide's colour tokens, as code reads them:
## [code]UiTokens.color(UiTokens.DANGER)[/code]. Static; never instanced.[br]
## The values live once, in [code]game_theme.tres[/code] (the project theme) as the colours of
## its [constant THEME_TYPE] type, so the theme's Inspector is where a token is retuned. The names
## here are that type's colour names; a typo in a constant fails the parse check, and an unknown
## name logs an error and reads magenta. [code]tests/ui/theme/[/code] checks the two stay in step
## and that each value is the style guide's.
##
## @tutorial(UI style guide): docs/design/ui-style.md

## The theme type holding one colour per token.
const THEME_TYPE: StringName = &"Palette"

## Read when the project theme isn't set (a script run before the GUI loads it).
const THEME_PATH: String = "res://ui/theme/game_theme.tres"

## Screen background, and the victory overlay's base.
const BG: StringName = &"bg"
## Panels, menus, tooltips; a row at rest.
const PANEL: StringName = &"panel"
## Hovered and focused rows and buttons.
const PANEL_RAISED: StringName = &"panel_raised"
## Panel and row borders.
const BORDER: StringName = &"border"
## Body text, names, numbers.
const TEXT: StringName = &"text"
## Secondary text, disabled labels.
const TEXT_MUTED: StringName = &"text_muted"
## Focus, highlights, gold amounts, headers on dark.
const ACCENT: StringName = &"accent"
## The ribbon header's fill (its text is [constant BG]).
const PARCHMENT: StringName = &"parchment"
## Damage, enemy intents and the enemy side, lethal warnings, the danger zone.
const DANGER: StringName = &"danger"
## Healing, positive changes.
const HEAL: StringName = &"heal"
## Block, the player side's colour.
const BLOCK: StringName = &"block"
## The darkness's layers, its phase banner and its log lines.
const DARKNESS: StringName = &"darkness"

## Every token, in the style guide's order.
const ALL: Array[StringName] = [
	BG, PANEL, PANEL_RAISED, BORDER, TEXT, TEXT_MUTED, ACCENT, PARCHMENT, DANGER, HEAL, BLOCK,
	DARKNESS,
]

## How opaque a disabled control is (the style guide's Disabled line).
const DISABLED_ALPHA: float = 0.45

# What an unknown token reads as, so the mistake shows on screen.
const _UNKNOWN: Color = Color(1.0, 0.0, 1.0, 1.0)

static var _theme: Theme = null


## The colour of [param token], one of the constants above, at full opacity.
static func color(token: StringName) -> Color:
	var theme: Theme = _palette_theme()
	if theme == null or not theme.has_color(token, THEME_TYPE):
		push_error("UiTokens: no colour token - %s" % [token])
		return _UNKNOWN
	return theme.get_color(token, THEME_TYPE)


## The colour of [param token] at [param alpha] (0.0 transparent, 1.0 opaque).
static func with_alpha(token: StringName, alpha: float) -> Color:
	return Color(color(token), alpha)


## The theme the tokens are read from: the project theme, else [constant THEME_PATH].
static func _palette_theme() -> Theme:
	if _theme != null:
		return _theme
	var project: Theme = ThemeDB.get_project_theme()
	if project != null and project.has_color(TEXT, THEME_TYPE):
		_theme = project
		return _theme
	_theme = load(THEME_PATH) as Theme
	if _theme == null:
		push_error("UiTokens: the theme did not load - %s" % [THEME_PATH])
	return _theme
