# ==============================================================================
# Bandit Bash
# Copyright (c) 2026 Derc Development
# Licensed under the MIT License. See LICENSE.
#
# File:     keyword_tooltip.gd
# Author:
# Created:  November 21, 2026
# Modified: November 22, 2026
# ==============================================================================

class_name KeywordTooltip
extends PanelContainer
## One keyword's explanation, as Slay the Spire's keyword boxes: its name in its colour (the
## [code]EffectText[/code] theme colour of its [member KeywordEntry.colour_group]), then its one
## plain sentence. A style guide tooltip panel at most [member max_width] wide; the sentence wraps.
##
## [EffectText] makes, stacks and places these; it never takes the mouse, so it can sit over what
## it describes. Holds no rules.
##
## @tutorial(Keywords): docs/design/keywords.md

## The widest the tooltip grows, border and padding included; a longer sentence wraps.[br]
## [b]Units:[/b] base units (the style guide's 320 for tooltips).
@export_range(80.0, 640.0, 4.0) var max_width: float = 320.0

## The id of the keyword shown, by [method show_entry]; empty before it.
var keyword_id: String = ""

@onready var _name: RichTextLabel = %KeywordName
@onready var _explanation: Label = %Explanation


## Shows [param entry]'s name in its colour and its explanation, the panel as wide as its wider
## line up to [member max_width]. Call it once the tooltip is in the tree, so its theme is known.
func show_entry(entry: KeywordEntry) -> void:
	if entry == null:
		return
	keyword_id = entry.id
	var colour: Color = get_name_colour(entry)
	_name.text = "[color=#%s]%s[/color]" % [
		colour.to_html(false), entry.display_name.replace("[", "[lb]"),
	]
	var padding: float = get_theme_stylebox(&"panel").get_minimum_size().x
	var inner: float = maxf(max_width - padding, 1.0)
	var name_font: Font = _name.get_theme_font(&"normal_font")
	var name_size: int = _name.get_theme_font_size(&"normal_font_size")
	var body_font: Font = _explanation.get_theme_font(&"font")
	var body_size: int = _explanation.get_theme_font_size(&"font_size")
	var name_width: float = name_font.get_string_size(
			entry.display_name, HORIZONTAL_ALIGNMENT_LEFT, -1, name_size
	).x
	var body_width: float = body_font.get_string_size(
			entry.explanation, HORIZONTAL_ALIGNMENT_LEFT, -1, body_size
	).x
	var widest: float = maxf(name_width, body_width)
	var width: float = minf(ceilf(widest), inner)
	var wraps: bool = widest > inner
	_explanation.autowrap_mode = (
			TextServer.AUTOWRAP_WORD_SMART if wraps else TextServer.AUTOWRAP_OFF
	)
	_explanation.custom_minimum_size.x = width if wraps else 0.0
	# A wrapping label shapes its lines at its own width when its text is set: width first, so the
	# panel's least size is right now rather than a layout later.
	_explanation.size = Vector2(width, _explanation.size.y)
	_explanation.text = entry.explanation
	reset_size()


## The colour [param entry]'s name is drawn in: its group's [code]EffectText[/code] theme colour,
## as text marks it.
func get_name_colour(entry: KeywordEntry) -> Color:
	return _name.get_theme_color(KeywordEntry.colour_item(entry.colour_group))


## Its lines as shown, for tests: the name, then the explanation.
func get_texts() -> PackedStringArray:
	return PackedStringArray([_name.get_parsed_text(), _explanation.text])
