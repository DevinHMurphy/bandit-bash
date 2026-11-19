# ==============================================================================
# Bandit Bash
# Copyright (c) 2026 Derc Development
# Licensed under the MIT License. See LICENSE.
#
# File:     event_log_line.gd
# Author:
# Created:  November 18, 2026
# Modified: November 18, 2026
# ==============================================================================

class_name EventLogLine
extends HBoxContainer
## One line of the [EventLog]: its group's icon, then its text in [code]text[/code], tiles and
## sources in [code]text_muted[/code] (ui-style.md: 10.30:1 and 5.99:1 on [code]panel[/code]).
## The words carry the meaning; the icon only tells the groups apart at a glance.[br]
## [b]Icons[/b] are placeholders in the style guide's form, a flat [code]accent[/code] symbol on a
## [code]panel[/code] circle with a [code]border[/code] ring, drawn here: Combat crossed strokes,
## Movement an arrow, Events a square, Effects a four-point star (RF-008). A note shows none.
##
## @tutorial(UI lift): docs/design/ui-lift.md

# ASSUMPTION: placeholder art; no design doc sets a stroke width.
## How thick the icon's strokes are (Combat's and Movement's).[br]
## [b]Units:[/b] pixels at the base size. [b]1.0:[/b] a hairline.
@export_range(0.5, 4.0, 0.5) var icon_stroke: float = 1.5:
	set(value):
		icon_stroke = value
		if is_node_ready():
			_icon.queue_redraw()

var _group: EventLogWriter.Group = EventLogWriter.Group.NONE
var _plain: String = ""

@onready var _icon: Control = %Icon
@onready var _text: RichTextLabel = %Text


func _ready() -> void:
	_icon.draw.connect(_on_icon_draw)


## Shows [param entry]: its pieces, muted where the entry says, and its group's icon. A note is
## muted throughout, with no icon.
func show_entry(entry: EventLogWriter.Entry) -> void:
	_group = entry.group
	_plain = entry.text()
	var is_note: bool = entry.tone == EventLogWriter.Tone.NOTE
	_text.text = markup(entry, is_note)
	_icon.visible = _group != EventLogWriter.Group.NONE
	_icon.queue_redraw()


## The filter group of the line shown.
func get_group() -> EventLogWriter.Group:
	return _group


## The line's text, unstyled.
func get_text() -> String:
	return _plain


## [param entry]'s BBCode: each muted piece (every piece when [param is_all_muted]) in
## [code]text_muted[/code], the rest in the label's own colour; "[" escaped.
static func markup(entry: EventLogWriter.Entry, is_all_muted: bool = false) -> String:
	var muted_hex: String = UiTokens.color(UiTokens.TEXT_MUTED).to_html(false)
	var parts: PackedStringArray = []
	for i: int in entry.pieces.size():
		var piece: String = entry.pieces[i].replace("[", "[lb]")
		if is_all_muted or entry.muted[i]:
			parts.append("[color=#%s]%s[/color]" % [muted_hex, piece])
		else:
			parts.append(piece)
	return "".join(parts)


func _on_icon_draw() -> void:
	if _group == EventLogWriter.Group.NONE:
		return
	var size: Vector2 = _icon.size
	var radius: float = minf(size.x, size.y) * 0.5
	var centre: Vector2 = size * 0.5
	var symbol: Color = UiTokens.color(UiTokens.ACCENT)
	_icon.draw_circle(centre, radius, UiTokens.color(UiTokens.PANEL))
	_icon.draw_arc(centre, radius - 0.5, 0.0, TAU, 24, UiTokens.color(UiTokens.BORDER), 1.0, true)
	# The symbol sits inside half the radius, clear of the ring.
	var reach: float = radius * 0.5
	match _group:
		EventLogWriter.Group.COMBAT:
			var a: Vector2 = Vector2(reach, reach)
			var b: Vector2 = Vector2(reach, -reach)
			_icon.draw_line(centre - a, centre + a, symbol, icon_stroke, true)
			_icon.draw_line(centre - b, centre + b, symbol, icon_stroke, true)
		EventLogWriter.Group.MOVEMENT:
			var tip: Vector2 = centre + Vector2(reach, 0.0)
			_icon.draw_line(centre - Vector2(reach, 0.0), tip, symbol, icon_stroke, true)
			var head: float = reach * 0.6
			_icon.draw_line(tip, tip + Vector2(-head, -head), symbol, icon_stroke, true)
			_icon.draw_line(tip, tip + Vector2(-head, head), symbol, icon_stroke, true)
		EventLogWriter.Group.EVENTS:
			var side: float = reach * 1.4
			_icon.draw_rect(Rect2(centre - Vector2(side, side) * 0.5, Vector2(side, side)), symbol)
		EventLogWriter.Group.EFFECTS:
			var waist: float = reach * 0.35
			var points: PackedVector2Array = [
				centre + Vector2(0.0, -reach), centre + Vector2(waist, -waist),
				centre + Vector2(reach, 0.0), centre + Vector2(waist, waist),
				centre + Vector2(0.0, reach), centre + Vector2(-waist, waist),
				centre + Vector2(-reach, 0.0), centre + Vector2(-waist, -waist),
			]
			_icon.draw_colored_polygon(points, symbol)
