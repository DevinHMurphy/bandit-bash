# ==============================================================================
# Bandit Bash
# Copyright (c) 2026 Derc Development
# Licensed under the MIT License. See LICENSE.
#
# File:     game_tooltip.gd
# Author:
# Created:  November 19, 2026
# Modified: November 19, 2026
# ==============================================================================

class_name GameTooltip
extends PanelContainer
## The style guide's tooltip (ui-style.md, Panels, rows and buttons): a panel at most
## [member max_width] wide with the name in Alegreya, then body text, then a muted footer (tier,
## counter). Text wider than the panel wraps; an empty name or footer hides its line.
##
## Shared by every tooltip so they read alike; its owner places it and shows or hides it. It never
## takes the mouse, so it can sit over what it describes.
##
## @tutorial(UI style guide): docs/design/ui-style.md

## The widest the tooltip grows, border and padding included; longer text wraps.[br]
## [b]Units:[/b] base units (the style guide's 320).
@export_range(80.0, 640.0, 4.0) var max_width: float = 320.0

@onready var _name: Label = %TooltipName
@onready var _body: Label = %TooltipBody
@onready var _footer: Label = %TooltipFooter


## Shows [param tip_name], [param body] and [param footer]; an empty one hides its line. The panel
## takes the width of its widest line, up to [member max_width].
func show_tip(tip_name: String, body: String, footer: String = "") -> void:
	_name.text = tip_name
	_name.visible = not tip_name.is_empty()
	_body.text = body
	_body.visible = not body.is_empty()
	_footer.text = footer
	_footer.visible = not footer.is_empty()
	var padding: float = get_theme_stylebox(&"panel").get_minimum_size().x
	var inner: float = maxf(max_width - padding, 1.0)
	var widest: float = 0.0
	for label: Label in [_name, _body, _footer]:
		if label.visible:
			widest = maxf(widest, _text_width(label))
	var width: float = minf(ceilf(widest), inner)
	# Text that fits stays on one line, so its size is known at once; only longer text wraps, at the
	# cap, and the panel refits once the wrapped lines are measured.
	var wraps: bool = widest > inner
	for label: Label in [_name, _body, _footer]:
		label.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART if wraps else TextServer.AUTOWRAP_OFF
		label.custom_minimum_size.x = width if wraps else 0.0
	reset_size()
	if wraps:
		reset_size.call_deferred()


## Its lines as shown, for tests: name, body, footer (a hidden one as empty).
func get_texts() -> PackedStringArray:
	var texts: PackedStringArray = []
	for label: Label in [_name, _body, _footer]:
		texts.append(label.text if label.visible else "")
	return texts


# label's text on one line, in its own font and size.
func _text_width(label: Label) -> float:
	var font: Font = label.get_theme_font(&"font")
	var size: int = label.get_theme_font_size(&"font_size")
	var widest: float = 0.0
	for line: String in label.text.split("\n"):
		widest = maxf(widest, font.get_string_size(line, HORIZONTAL_ALIGNMENT_LEFT, -1, size).x)
	return widest
