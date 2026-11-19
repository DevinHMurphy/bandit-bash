# ==============================================================================
# Bandit Bash
# Copyright (c) 2026 Derc Development
# Licensed under the MIT License. See LICENSE.
#
# File:     theme_cases.gd
# Author:
# Created:  November 18, 2026
# Modified: November 19, 2026
# ==============================================================================

extends RefCounted
## The shared theme against the UI style guide (docs/design/ui-style.md), for the ui/theme suite:
## every colour token in [code]game_theme.tres[/code]'s Palette with the guide's value and none
## besides, read alike through [UiTokens]; text and muted text at 4.5:1 or more on panel and
## raised panel, and text on the danger and darkness chip fills (the ratios are in the case
## names); every colour in the project and battle themes
## a token at some alpha, white or clear (tints and outlines drawn white), or one of the listed
## placeholders; no font size under 14 base units; the fonts and weights of the type scale, with
## their licence files; the row looks (rest, hover, focus, primary, disabled). No autoload is
## named or needed.

const GAME_THEME: String = "res://ui/theme/game_theme.tres"
const BATTLE_THEME: String = "res://ui/theme/battle_theme.tres"
const SANS_FILE: String = "res://assets/fonts/source_sans_3/source_sans_3.ttf"
const SERIF_FILE: String = "res://assets/fonts/alegreya/alegreya.ttf"

## The style guide's tokens.
const GUIDE: Dictionary[StringName, String] = {
	&"bg": "14171c", &"panel": "2a3038", &"panel_raised": "3a434d", &"border": "4a5560",
	&"text": "e8e2d4", &"text_muted": "a6afb9", &"accent": "d9b45a", &"parchment": "d8c9a3",
	&"danger": "c8463c", &"danger_fill": "9e352e", &"heal": "5fae6b", &"block": "6fa3d8",
	&"darkness": "6b4fa0",
}

## The chip fills text sits on: warnings and the enemy side, the darkness banner and log rows.
const CHIP_FILLS: Array[StringName] = [&"danger_fill", &"darkness"]

## WCAG AA for body text.
const MIN_CONTRAST: float = 4.5

## The guide's floor for text, in base units.
const MIN_FONT_SIZE: int = 14

# Colours in the themes that are no token, each with why (rebalance-and-features.md RF-008 lists
# the placeholders): "<theme file>:<type>/<item>".
const NOT_TOKENS: PackedStringArray = [
	"battle_theme.tres:HpBar/fill", # Godot_FE's HP bar fill; no token has its role
	"battle_theme.tres:StancePips/change_color", # forecast flash tint, placeholder
	"battle_theme.tres:StancePips/overflow_color", # Stance above its maximum, placeholder
	"battle_theme.tres:StancePips/preview_color", # Stance lost in the forecast, placeholder
	"battle_theme.tres:PreviewDamageLabel/font_color", # darkness damage preview, placeholder
	"battle_theme.tres:IntentSignatureGlyph/font_color", # intent glyph, placeholder
	"battle_theme.tres:IntentUseObjectGlyph/font_color", # intent glyph, placeholder
	"battle_theme.tres:ObjectBrazierGlyph/font_color", # map object glyph, placeholder
	"battle_theme.tres:ObjectDoorGlyph/font_color", # map object glyph, placeholder
	"battle_theme.tres:ObjectPassageGlyph/font_color", # map object glyph, placeholder
]

var _check: Callable
var _game: Theme = null
var _battle: Theme = null


## [param check]: called as check(case_name: String, passed: bool, detail: String).
func _init(check: Callable) -> void:
	_check = check
	_game = load(GAME_THEME)
	_battle = load(BATTLE_THEME)


## Runs every case.
func run() -> void:
	if _game == null or _battle == null:
		_check.call("theme: both theme files load", false, "%s, %s" % [_game, _battle])
		return
	_test_tokens()
	_test_contrast()
	_test_theme_colours()
	_test_font_sizes()
	_test_fonts()
	_test_rows()


# The Palette holds the guide's tokens and nothing else; UiTokens reads the same values.
func _test_tokens() -> void:
	var wrong: PackedStringArray = []
	for token: StringName in GUIDE:
		var expected: Color = Color(GUIDE[token])
		if not _game.has_color(token, UiTokens.THEME_TYPE):
			wrong.append("%s missing" % [token])
		elif not _game.get_color(token, UiTokens.THEME_TYPE).is_equal_approx(expected):
			wrong.append("%s is %s" % [token, _game.get_color(token, UiTokens.THEME_TYPE)])
		elif not UiTokens.color(token).is_equal_approx(expected):
			wrong.append("UiTokens reads %s as %s" % [token, UiTokens.color(token)])
	var extra: PackedStringArray = []
	for name: StringName in _game.get_color_list(UiTokens.THEME_TYPE):
		if not GUIDE.has(name):
			extra.append(name)
	var constants: Array[StringName] = UiTokens.ALL.duplicate()
	constants.sort()
	var guide: Array[StringName] = GUIDE.keys()
	guide.sort()
	_check.call("tokens: the Palette holds the guide's %d tokens, read alike by UiTokens" % [
		GUIDE.size(),
	], (
			wrong.is_empty() and extra.is_empty() and constants == guide
	), "; ".join(wrong + extra))
	var project: Theme = ThemeDB.get_project_theme()
	_check.call("tokens: the project theme is game_theme.tres", (
			project != null and project.resource_path == GAME_THEME
	), project.resource_path if project != null else "none")


# Text and muted text on panel and raised panel, by WCAG relative luminance.
func _test_contrast() -> void:
	for text: StringName in [UiTokens.TEXT, UiTokens.TEXT_MUTED]:
		for back: StringName in [UiTokens.PANEL, UiTokens.PANEL_RAISED]:
			var ratio: float = contrast(UiTokens.color(text), UiTokens.color(back))
			_check.call("contrast: %s on %s is %.2f:1 (at least %.1f)" % [
				text, back, ratio, MIN_CONTRAST,
			], ratio >= MIN_CONTRAST)
	for fill: StringName in CHIP_FILLS:
		var on_fill: float = contrast(UiTokens.color(UiTokens.TEXT), UiTokens.color(fill))
		_check.call("contrast: text on the %s chip is %.2f:1 (at least %.1f)" % [
			fill, on_fill, MIN_CONTRAST,
		], on_fill >= MIN_CONTRAST)


# Every colour either theme draws is a token (any alpha), white or clear, or listed.
func _test_theme_colours() -> void:
	var stray: PackedStringArray = []
	for pair: Array in [["game_theme.tres", _game], ["battle_theme.tres", _battle]]:
		var file: String = pair[0]
		var theme: Theme = pair[1]
		for type: StringName in theme.get_type_list():
			if type == UiTokens.THEME_TYPE:
				continue
			for name: StringName in theme.get_color_list(type):
				_note_colour(stray, file, type, name, theme.get_color(name, type))
			for name: StringName in theme.get_stylebox_list(type):
				var box: StyleBoxFlat = theme.get_stylebox(name, type) as StyleBoxFlat
				if box == null:
					continue
				for colour: Color in _drawn_colours(box):
					_note_colour(stray, file, type, name, colour)
	_check.call("theme colours: every colour is a token, white, clear or a listed placeholder", (
			stray.is_empty()
	), "; ".join(stray))


# Every font size in either theme, and the default, at the floor or above.
func _test_font_sizes() -> void:
	var low: PackedStringArray = []
	var count: int = 0
	for theme: Theme in [_game, _battle]:
		if theme.has_default_font_size() and theme.default_font_size < MIN_FONT_SIZE:
			low.append("default %d" % [theme.default_font_size])
		for type: StringName in theme.get_type_list():
			for name: StringName in theme.get_font_size_list(type):
				count += 1
				var size: int = theme.get_font_size(name, type)
				if size < MIN_FONT_SIZE:
					low.append("%s/%s %d" % [type, name, size])
	_check.call("font sizes: all %d are %d base units or more" % [count, MIN_FONT_SIZE], (
			low.is_empty() and count > 0
	), "; ".join(low))
	var scale: Dictionary[StringName, int] = {
		&"TitleLabel": 24, &"HeaderLabel": 18, &"BodyLabel": 16, &"SmallLabel": 14,
		&"BigNumberLabel": 28,
	}
	var wrong: PackedStringArray = []
	for type: StringName in scale:
		if _game.get_font_size(&"font_size", type) != scale[type]:
			wrong.append("%s %d" % [type, _game.get_font_size(&"font_size", type)])
	_check.call("font sizes: the type scale is 24, 18, 16, 14 and 28", (
			wrong.is_empty() and _game.default_font_size == 16
	), "; ".join(wrong))


# Source Sans 3 (regular, bold; tabular digits) and Alegreya Bold, each beside its licence.
func _test_fonts() -> void:
	var wght: int = TextServerManager.get_primary_interface().name_to_tag("wght")
	var tnum: int = TextServerManager.get_primary_interface().name_to_tag("tnum")
	var body: FontVariation = _game.default_font as FontVariation
	var title: FontVariation = _game.get_font(&"font", &"TitleLabel") as FontVariation
	var big: FontVariation = _game.get_font(&"font", &"BigNumberLabel") as FontVariation
	var ok: bool = body != null and title != null and big != null
	if ok:
		# By file: a variable font names itself after its default instance (ExtraLight).
		ok = (
				body.base_font.resource_path == SANS_FILE
				and body.variation_opentype.get(wght) == 400
				and body.opentype_features.get(tnum) == 1
				and big.base_font.resource_path == SANS_FILE
				and big.variation_opentype.get(wght) == 700
				and title.base_font.resource_path == SERIF_FILE
				and title.variation_opentype.get(wght) == 700
		)
	_check.call("fonts: body Source Sans 3 400 (tabular), big numbers 700, titles Alegreya 700", ok)
	var missing: PackedStringArray = []
	for folder: String in ["res://assets/fonts/alegreya/", "res://assets/fonts/source_sans_3/"]:
		if not FileAccess.file_exists(folder + "OFL.txt"):
			missing.append(folder)
	_check.call("fonts: each font folder holds its OFL licence", missing.is_empty(), (
			", ".join(missing)
	))


# Rest: panel with a border; hover: raised; focus: raised with the 2-unit accent outline;
# primary: an accent border; disabled: 45% with muted text.
func _test_rows() -> void:
	var rest: StyleBoxFlat = _game.get_stylebox(&"normal", &"Button")
	var hover: StyleBoxFlat = _game.get_stylebox(&"hover", &"Button")
	var focus: StyleBoxFlat = _game.get_stylebox(&"focus", &"Button")
	var disabled: StyleBoxFlat = _game.get_stylebox(&"disabled", &"Button")
	var primary: StyleBoxFlat = _game.get_stylebox(&"normal", &"PrimaryButton")
	var accent: Color = UiTokens.color(UiTokens.ACCENT)
	var muted: Color = _game.get_color(&"font_disabled_color", &"Button")
	_check.call("rows: rest, hover, focus, primary and disabled as the guide sets them", (
			rest.bg_color == UiTokens.color(UiTokens.PANEL)
			and rest.border_color == UiTokens.color(UiTokens.BORDER)
			and rest.border_width_top == 1
			and hover.bg_color == UiTokens.color(UiTokens.PANEL_RAISED)
			and hover.border_color != accent
			and focus.bg_color == UiTokens.color(UiTokens.PANEL_RAISED)
			and focus.border_color == accent
			and focus.border_width_left == 2
			and primary.border_color == accent
			and is_equal_approx(disabled.bg_color.a, UiTokens.DISABLED_ALPHA)
			and Color(muted, 1.0).is_equal_approx(UiTokens.color(UiTokens.TEXT_MUTED))
			and is_equal_approx(muted.a, UiTokens.DISABLED_ALPHA)
	))


func _note_colour(
		stray: PackedStringArray, file: String, type: StringName, name: StringName, colour: Color
) -> void:
	if colour.a == 0.0 or Color(colour, 1.0).is_equal_approx(Color.WHITE):
		return
	for token: StringName in GUIDE:
		if Color(colour, 1.0).is_equal_approx(Color(GUIDE[token])):
			return
	var key: String = "%s:%s/%s" % [file, type, name]
	if not NOT_TOKENS.has(key):
		stray.append("%s %s" % [key, colour])


# The colours a flat style box draws: its fill, its border and its shadow, where each shows.
func _drawn_colours(box: StyleBoxFlat) -> Array[Color]:
	var colours: Array[Color] = []
	if box.draw_center:
		colours.append(box.bg_color)
	var widths: int = (
			box.border_width_left + box.border_width_top + box.border_width_right
			+ box.border_width_bottom
	)
	if widths > 0:
		colours.append(box.border_color)
	if box.shadow_size > 0:
		colours.append(box.shadow_color)
	return colours


## The WCAG contrast ratio of [param a] against [param b], from 1.0 to 21.0 (alpha ignored).
static func contrast(a: Color, b: Color) -> float:
	var la: float = _luminance(a)
	var lb: float = _luminance(b)
	return (maxf(la, lb) + 0.05) / (minf(la, lb) + 0.05)


static func _luminance(colour: Color) -> float:
	var channels: Array[float] = []
	for value: float in [colour.r, colour.g, colour.b]:
		channels.append(value / 12.92 if value <= 0.04045 else pow((value + 0.055) / 1.055, 2.4))
	return 0.2126 * channels[0] + 0.7152 * channels[1] + 0.0722 * channels[2]
