# ==============================================================================
# Bandit Bash
# Copyright (c) 2026 Derc Development
# Licensed under the MIT License. See LICENSE.
#
# File:     heirloom_icon.gd
# Author:
# Created:  November 19, 2026
# Modified: November 19, 2026
# ==============================================================================

class_name HeirloomIcon
extends Button
## One held heirloom or curse copy on the [HeirloomBar]: its symbol on a circle, the number of
## its state in a chip at the corner (its count toward its period, or its uses left), and its
## look: at rest at [member rest_alpha], at full on hover, focus or a [method pulse] when it fires;
## ready (the next qualifying event fires it) at full with a ring and an [code]accent[/code] chip;
## spent (no uses left, a first-only effect used) at [member spent_alpha] with a muted symbol.
##
## Draws a [HeirloomViewModel] and holds no state of its own. It reports being pointed at
## ([signal pointed], [signal unpointed]) for the bar's tooltip; a press does nothing. Keys and
## pads reach it only while [method set_navigable] is on. The circle and focus ring are the theme's
## RuneSlot styles; the ring and chip are drawn in the style guide's tokens.
##
## @tutorial(UI lift, Heirloom bar): docs/design/ui-lift.md

## The mouse entered it, or focus moved onto it.
signal pointed()

## The mouse left it, or focus left it.
signal unpointed()

# Padding around the chip's number, and how far the ring sits inside the circle's edge.
const _CHIP_PADDING: Vector2 = Vector2(3.0, 0.0)
const _RING_INSET: float = 3.0
const _RING_WIDTH: float = 1.0

## How opaque it is at rest: the style guide's 50% for icons that stay out of the way.[br]
## [b]1.0:[/b] always at full. [b]0.0:[/b] invisible until pointed at.
@export_range(0.0, 1.0, 0.05) var rest_alpha: float = 0.5

## How opaque it is while spent and not pointed at: the style guide's disabled look.[br]
## [b]Equal to [member rest_alpha]:[/b] only the muted symbol tells spent apart.
@export_range(0.0, 1.0, 0.05) var spent_alpha: float = UiTokens.DISABLED_ALPHA

# ASSUMPTION: the pulse's length; ui-style.md sets 150-250 ms for fades, none for a pulse.
## How long a [method pulse] takes to fade from full back to its resting look.[br]
## [b]Units:[/b] seconds. [b]0.0:[/b] no pulse.
@export_range(0.0, 3.0, 0.05) var pulse_time: float = 0.6

## The generic mark shown for an heirloom or curse whose definition has no icon.[br]
## [b]Unset:[/b] such an icon shows an empty circle.
@export var fallback_icon: Texture2D = null

var _view: HeirloomViewModel = null
var _is_hovered: bool = false
var _is_pulsing: bool = false

# How lit the pulse still is, 1.0 at its start to 0.0 at its end; tweened by pulse().
var _pulse_strength: float = 0.0:
	set(value):
		_pulse_strength = value
		_apply_look()
var _pulse_tween: Tween = null

@onready var _symbol: TextureRect = %Symbol
@onready var _overlay: Control = %Overlay


func _ready() -> void:
	mouse_entered.connect(_on_mouse_entered)
	mouse_exited.connect(_on_mouse_exited)
	focus_entered.connect(_on_focus_entered)
	focus_exited.connect(_on_focus_exited)
	_overlay.draw.connect(_on_overlay_draw)
	set_navigable(false)
	_apply_look()


## Draws [param view]: its symbol (its icon, else [member fallback_icon]) tinted
## [code]accent[/code], a curse's [code]danger[/code], a spent one's [code]text_muted[/code]; its
## chip's number ([method HeirloomViewModel.badge_text]); and its ready or spent look.
func show_view(view: HeirloomViewModel) -> void:
	_view = view
	if not is_node_ready():
		return
	_apply_look()


## The copy shown; null before [method show_view].
func get_view() -> HeirloomViewModel:
	return _view


## Lets keys and pads focus it, or stops them, dropping a focus held. The mouse hovers it either
## way.
func set_navigable(is_navigable: bool) -> void:
	focus_mode = Control.FOCUS_ALL if is_navigable else Control.FOCUS_NONE
	if not is_navigable and has_focus():
		release_focus()


## Lights it at full, fading back over [member pulse_time]: it fired.
func pulse() -> void:
	if pulse_time <= 0.0 or not is_inside_tree():
		return
	if _pulse_tween != null and _pulse_tween.is_valid():
		_pulse_tween.kill()
	_is_pulsing = true
	_pulse_strength = 1.0
	_pulse_tween = create_tween()
	_pulse_tween.tween_property(self, ^"_pulse_strength", 0.0, pulse_time)
	_pulse_tween.finished.connect(_on_pulse_tween_finished)


## Whether a pulse is fading now.
func is_pulsing() -> bool:
	return _is_pulsing


## The texture its symbol shows: its icon, else [member fallback_icon].
func get_symbol() -> Texture2D:
	return _symbol.texture


## The number its chip shows; empty while it shows none.
func get_badge_text() -> String:
	return "" if _view == null else _view.badge_text()


## Whether it shows the ready look.
func is_ready_look() -> bool:
	return _view != null and _view.is_ready


## Whether it shows the spent look.
func is_spent_look() -> bool:
	return _view != null and _view.is_spent


## How opaque it is now: [member rest_alpha], [member spent_alpha], or 1.0 while lit (hovered,
## focused, ready or pulsing).
func get_shown_alpha() -> float:
	return modulate.a


func _apply_look() -> void:
	if not is_node_ready():
		return
	var texture: Texture2D = null
	if _view != null:
		texture = _view.icon if _view.icon != null else fallback_icon
	_symbol.texture = texture
	var token: StringName = UiTokens.ACCENT
	if _view != null and _view.is_spent:
		token = UiTokens.TEXT_MUTED
	elif _view != null and _view.is_curse:
		token = UiTokens.DANGER
	_symbol.self_modulate = UiTokens.color(token)
	var base: float = rest_alpha
	if _view != null and _view.is_spent:
		base = spent_alpha
	var is_lit: bool = _is_hovered or has_focus() or (_view != null and _view.is_ready)
	var alpha: float = 1.0 if is_lit else lerpf(base, 1.0, _pulse_strength)
	modulate = Color(1.0, 1.0, 1.0, alpha)
	_overlay.queue_redraw()


func _on_overlay_draw() -> void:
	if _view == null:
		return
	var center: Vector2 = _overlay.size / 2.0
	if _view.is_ready:
		var radius: float = minf(center.x, center.y) - _RING_INSET
		_overlay.draw_arc(
				center, radius, 0.0, TAU, 48, UiTokens.color(UiTokens.ACCENT), _RING_WIDTH, true
		)
	var text: String = _view.badge_text()
	if text.is_empty():
		return
	var font: Font = get_theme_font(&"font", &"SmallLabel")
	var font_size: int = get_theme_font_size(&"font_size", &"SmallLabel")
	var text_size: Vector2 = font.get_string_size(text, HORIZONTAL_ALIGNMENT_LEFT, -1, font_size)
	var chip_size: Vector2 = Vector2(
			maxf(text_size.x + _CHIP_PADDING.x * 2.0, text_size.y), text_size.y
	)
	var chip: Rect2 = Rect2(_overlay.size - chip_size * 0.75, chip_size)
	var fill: StringName = UiTokens.ACCENT if _view.is_ready else UiTokens.PANEL
	var ink: StringName = UiTokens.BG if _view.is_ready else UiTokens.TEXT
	if _view.is_spent:
		ink = UiTokens.TEXT_MUTED
	_overlay.draw_rect(chip, UiTokens.color(fill))
	_overlay.draw_rect(chip, UiTokens.color(UiTokens.BORDER), false, 1.0)
	var baseline: Vector2 = Vector2(
			chip.position.x + (chip.size.x - text_size.x) / 2.0,
			chip.position.y + font.get_ascent(font_size)
	)
	_overlay.draw_string(
			font, baseline, text, HORIZONTAL_ALIGNMENT_LEFT, -1, font_size, UiTokens.color(ink)
	)


func _on_mouse_entered() -> void:
	_is_hovered = true
	_apply_look()
	pointed.emit()


func _on_mouse_exited() -> void:
	_is_hovered = false
	_apply_look()
	unpointed.emit()


func _on_focus_entered() -> void:
	_apply_look()
	pointed.emit()


func _on_focus_exited() -> void:
	_apply_look()
	unpointed.emit()


func _on_pulse_tween_finished() -> void:
	_is_pulsing = false
	_apply_look()
