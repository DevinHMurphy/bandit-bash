# ==============================================================================
# Bandit Bash
# Copyright (c) 2026 Derc Development
# Licensed under the MIT License. See LICENSE.
#
# File:     effect_text.gd
# Author:
# Created:  November 21, 2026
# Modified: November 22, 2026
# ==============================================================================

class_name EffectText
extends RichTextLabel
## Effect text with its keywords coloured by meaning and explained: [member marked_text] is the
## text as [EffectTerms] writes it, each keyword tagged [code][kw=<id>]Word[/kw][/code]. A known
## tag draws in its [KeywordEntry]'s colour group (the [code]EffectText[/code] theme type's
## [code]keyword_*[/code] colours); everything else, an unknown tag's word included, is plain.[br]
## [b]Tooltips[/b] ([KeywordTooltip], stacked in a column beside the card, kept on screen):
## hovering a keyword shows its own; keyboard or pad focus on the card holding this text (its
## nearest focusable ancestor) shows one per distinct keyword of every [EffectText] on that card,
## until focus leaves. Mouse focus shows none, so a click never opens the whole column. An owner
## whose text no card holds (the heirloom bar's tooltip) calls [method show_all_keywords] itself.
## Reads no input action.
##
## @tutorial(Keywords): docs/design/keywords.md

## The text with its keyword tags, such as [code]gain 2 [kw=block]Block[/kw].[/code]; lines
## break at "\n". [b]Empty:[/b] shows nothing.
@export_multiline var marked_text: String = "":
	set(value):
		marked_text = value
		if not is_node_ready():
			return
		hide_tooltips()
		_render()

## Whether hovering a keyword, or focus on the card, shows tooltips.
## [b]Off:[/b] the keywords are coloured only.
@export var shows_tooltips: bool = true

## The tooltip made for each keyword shown: a [KeywordTooltip] scene.[br]
## [b]Unset:[/b] no tooltip shows and an error is reported.
@export var tooltip_scene: PackedScene = null

# ASSUMPTION: the gap; ui-style.md sets 4 units between rows and places tooltips by no distance.
## The space between the card and the tooltip column, and between stacked tooltips.[br]
## [b]Units:[/b] base units. [b]0.0:[/b] the column touches the card.
@export_range(0.0, 32.0, 1.0) var tooltip_gap: float = 4.0

# The ancestor whose keyboard or pad focus shows every keyword; null when none can take focus.
var _holder: Control = null

# Whether focus, not the mouse, opened the tooltips shown.
var _is_showing_all: bool = false

@onready var _stack: VBoxContainer = %Tooltips


func _ready() -> void:
	if tooltip_scene == null:
		push_error("EffectText: no tooltip scene set")
	_stack.add_theme_constant_override(&"separation", roundi(tooltip_gap))
	_stack.visible = false
	meta_hover_started.connect(_on_meta_hover_started)
	meta_hover_ended.connect(_on_meta_hover_ended)
	mouse_exited.connect(_on_mouse_exited)
	# A RichTextLabel refits its height to a new width only when drawn; as a Label does, refit on
	# resize, so a card sized from its content's least height (ItemOfferCard) sees the wrapped one.
	resized.connect(update_minimum_size)
	_bind_holder()
	_render()


func _exit_tree() -> void:
	_unbind_holder()


func _notification(what: int) -> void:
	if what == NOTIFICATION_THEME_CHANGED and is_node_ready():
		_render()
	elif what == NOTIFICATION_ENTER_TREE and is_node_ready():
		_bind_holder()


## [member marked_text]'s words alone, as shown: what a plain label would say.
func get_plain_text() -> String:
	return EffectTerms.plain_text(marked_text)


## The ids of the keywords shown, each once, in reading order; a tag the glossary lacks is left out.
func get_keyword_ids() -> PackedStringArray:
	var ids: PackedStringArray = []
	var glossary: KeywordGlossary = KeywordGlossary.shared()
	if glossary == null:
		return ids
	for piece: PackedStringArray in EffectTerms.split_marked(marked_text):
		if not piece[0].is_empty() and not ids.has(piece[0]) and glossary.entry(piece[0]) != null:
			ids.append(piece[0])
	return ids


## Shows one tooltip per distinct id in [param ids] the glossary knows, in order, stacked beside
## the card; hides those shown before.
func show_tooltips(ids: PackedStringArray) -> void:
	hide_tooltips()
	var glossary: KeywordGlossary = KeywordGlossary.shared()
	if not shows_tooltips or tooltip_scene == null or glossary == null:
		return
	var shown: PackedStringArray = []
	for id: String in ids:
		var entry: KeywordEntry = glossary.entry(id)
		if entry == null or shown.has(id):
			continue
		shown.append(id)
		var tooltip: KeywordTooltip = tooltip_scene.instantiate()
		_stack.add_child(tooltip)
		tooltip.show_entry(entry)
		# A tooltip whose text settles after a layout refits the column, kept on screen.
		tooltip.minimum_size_changed.connect(place_tooltips, CONNECT_DEFERRED)
	_stack.visible = not shown.is_empty()
	place_tooltips()
	# Tooltips refit a frame later when their text wraps; place the column again then.
	place_tooltips.call_deferred()


## Shows every keyword of every [EffectText] on this text's card, each once, as keyboard or pad
## focus on the card does; only this text's own when no ancestor can take focus.
func show_all_keywords() -> void:
	var ids: PackedStringArray = []
	for text: EffectText in _texts_on_card():
		for id: String in text.get_keyword_ids():
			if not ids.has(id):
				ids.append(id)
	show_tooltips(ids)
	_is_showing_all = not ids.is_empty()


## Hides and frees the tooltips shown, if any.
func hide_tooltips() -> void:
	_is_showing_all = false
	if not is_node_ready():
		return
	for child: Node in _stack.get_children():
		_stack.remove_child(child)
		child.queue_free()
	_stack.visible = false


## The tooltips shown, top to bottom; empty when none is.
func get_shown_tooltips() -> Array[KeywordTooltip]:
	var shown: Array[KeywordTooltip] = []
	if not is_node_ready():
		return shown
	for child: Node in _stack.get_children():
		var tooltip: KeywordTooltip = child as KeywordTooltip
		if tooltip != null:
			shown.append(tooltip)
	return shown


## The column of tooltips, for tests of where it sits; hidden while none shows.
func get_tooltip_column() -> Control:
	return _stack


## What the tooltips sit beside: the focusable card holding this text, else the panel holding it,
## else this text.
func get_card() -> Control:
	if is_instance_valid(_holder):
		return _holder
	var node: Node = get_parent()
	while node != null:
		if node is PanelContainer:
			return node as Control
		node = node.get_parent()
	return self


## Places the tooltip column beside [method get_card]: right of it, else left of it, kept inside
## the visible rect. An owner that moves the card calls it again.
func place_tooltips() -> void:
	if not is_node_ready() or not is_inside_tree() or not _stack.visible:
		return
	_stack.reset_size()
	var column: Vector2 = _stack.get_combined_minimum_size()
	var card: Rect2 = get_card().get_global_rect()
	var screen: Rect2 = get_viewport().get_visible_rect()
	var x: float = card.end.x + tooltip_gap
	if x + column.x > screen.end.x:
		x = card.position.x - tooltip_gap - column.x
	x = clampf(x, screen.position.x, maxf(screen.end.x - column.x, screen.position.x))
	var y: float = clampf(
			card.position.y, screen.position.y, maxf(screen.end.y - column.y, screen.position.y)
	)
	_stack.global_position = Vector2(x, y)


# Turns the tags into coloured, hoverable spans ([url] with the keyword's id) and escapes the rest.
func _render() -> void:
	var glossary: KeywordGlossary = KeywordGlossary.shared()
	var parts: PackedStringArray = []
	for piece: PackedStringArray in EffectTerms.split_marked(marked_text):
		var words: String = piece[1].replace("[", "[lb]")
		var entry: KeywordEntry = null
		if not piece[0].is_empty() and glossary != null:
			entry = glossary.entry(piece[0])
		if entry == null:
			parts.append(words)
			continue
		var colour: Color = get_theme_color(KeywordEntry.colour_item(entry.colour_group))
		parts.append("[url=%s][color=#%s]%s[/color][/url]" % [
			entry.id, colour.to_html(false), words,
		])
	text = "".join(parts)


# Every EffectText on the card, this one included, in tree order.
func _texts_on_card() -> Array[EffectText]:
	var found: Array[EffectText] = []
	if not is_instance_valid(_holder):
		found.append(self)
		return found
	_collect_texts(_holder, found)
	if not found.has(self):
		found.append(self)
	return found


func _collect_texts(node: Node, found: Array[EffectText]) -> void:
	for child: Node in node.get_children():
		var text: EffectText = child as EffectText
		if text != null and text.shows_tooltips and text.is_visible_in_tree():
			found.append(text)
		_collect_texts(child, found)


# The first visible EffectText on the card speaks for all of them, so one column shows.
func _is_card_leader() -> bool:
	var texts: Array[EffectText] = _texts_on_card()
	return not texts.is_empty() and texts[0] == self


func _bind_holder() -> void:
	_unbind_holder()
	var node: Node = get_parent()
	while node != null:
		var control: Control = node as Control
		if control != null and control.focus_mode != Control.FOCUS_NONE:
			_holder = control
			break
		node = node.get_parent()
	if _holder == null:
		return
	_holder.focus_entered.connect(_on_holder_focus_entered)
	_holder.focus_exited.connect(_on_holder_focus_exited)


func _unbind_holder() -> void:
	if not is_instance_valid(_holder):
		_holder = null
		return
	if _holder.focus_entered.is_connected(_on_holder_focus_entered):
		_holder.focus_entered.disconnect(_on_holder_focus_entered)
	if _holder.focus_exited.is_connected(_on_holder_focus_exited):
		_holder.focus_exited.disconnect(_on_holder_focus_exited)
	_holder = null


func _on_holder_focus_entered() -> void:
	# A mouse click focuses with the focus hidden: only keys and pads open the column.
	if not is_instance_valid(_holder) or not _holder.has_focus(true):
		return
	if shows_tooltips and is_visible_in_tree() and _is_card_leader():
		show_all_keywords()


func _on_holder_focus_exited() -> void:
	hide_tooltips()


func _on_meta_hover_started(meta: Variant) -> void:
	if _is_showing_all:
		return
	show_tooltips(PackedStringArray([str(meta)]))


func _on_meta_hover_ended(_meta: Variant) -> void:
	if not _is_showing_all:
		hide_tooltips()


func _on_mouse_exited() -> void:
	if not _is_showing_all:
		hide_tooltips()
