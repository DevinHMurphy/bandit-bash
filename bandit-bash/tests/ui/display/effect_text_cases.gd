# ==============================================================================
# Bandit Bash
# Copyright (c) 2026 Derc Development
# Licensed under the MIT License. See LICENSE.
#
# File:     effect_text_cases.gd
# Author:
# Created:  November 22, 2026
# Modified: November 22, 2026
# ==============================================================================

extends RefCounted
## [EffectText] and [KeywordTooltip] (docs/design/keywords.md), for the ui/display suite, on an
## [ItemOfferCard] whose item's written text opens with a keyword: each keyword drawn in its colour
## group's theme colour and the rest plain; hovering a keyword (the label's hover signals:
## headless, it lays out no lines for a pushed mouse to hit) showing its tooltip, its name in that
## colour and its explanation, and leaving it, or the mouse leaving the text, hiding it; a real
## click on a keyword still pressing the card; key or pad focus showing one tooltip per distinct
## keyword and focus loss
## hiding them, mouse focus none; the column inside the visible rect at 1280×720, 1920×1080 and
## 1280×800 with the card at either edge; and every swapped surface's effect line an EffectText
## showing the catalog's marked text, its words those of the plain text.

# The suite that runs this file; tests/case_files.gd finds it by this line.
const SUITE: String = "ui/display"

const CARD_SCENE: PackedScene = preload("res://ui/campaign/item_offer_card.tscn")
const STOCK_SCENE: PackedScene = preload("res://ui/campaign/stock_card.tscn")
const HEIRLOOM_SCENE: PackedScene = preload("res://ui/campaign/heirloom_offer_card.tscn")
const TOOLTIP_SCENE: PackedScene = preload("res://ui/common/game_tooltip.tscn")
const EFFECT_ROW_SCENE: PackedScene = preload("res://ui/battle/unit/detail/detail_effect_row.tscn")
const GEAR_ROW_SCENE: PackedScene = preload("res://ui/battle/unit/detail/detail_gear_row.tscn")

# Scenes whose effect line is an EffectText, and that line's unique name.
const SWAPPED: Dictionary[String, String] = {
	"res://ui/campaign/item_offer_card.tscn": "Effects",
	"res://ui/campaign/stock_card.tscn": "Effects",
	"res://ui/campaign/heirloom_offer_card.tscn": "Effects",
	"res://ui/campaign/purchase_panel.tscn": "Details",
	"res://ui/campaign/guildhall_panel.tscn": "Details",
	"res://ui/common/game_tooltip.tscn": "TooltipBody",
	"res://ui/battle/unit/detail/detail_effect_row.tscn": "EffectText",
	"res://ui/battle/unit/detail/detail_gear_row.tscn": "Detail",
}

# The written text of the test item: a keyword opens it, so its first glyphs are a keyword's, and
# Block shows twice (one tooltip).
const WRITTEN: String = (
		"[kw=block]Block[/kw] 3 [kw=damage]damage[/kw], then gain 2 [kw=block]Block[/kw] and"
		+ " [kw=heal]heal[/kw] 1 [kw=hp]HP[/kw]."
)
const WRITTEN_IDS: PackedStringArray = ["block", "damage", "heal", "hp"]

# A keyword of each colour group, for the colour case.
const GROUP_SAMPLES: PackedStringArray = ["damage", "block", "heal", "gold", "darkness"]

# The window sizes the style guide shows the UI at.
const SCREEN_SIZES: Array[Vector2i] = [
	Vector2i(1280, 720), Vector2i(1920, 1080), Vector2i(1280, 800),
]

# Where the mouse goes over the text's first glyph, from its top-left corner, in base units.
const FIRST_GLYPH: Vector2 = Vector2(6.0, 8.0)

var _check: Callable
var _root: Window = null
var _catalog: EffectCatalog.Index = null
var _glossary: KeywordGlossary = null
var _pressed: int = 0


## [param check]: called as check(case_name: String, passed: bool, detail: String).
## [param root]: the root viewport, where the cards are added.
func _init(check: Callable, root: Window) -> void:
	_check = check
	_root = root
	_catalog = EffectCatalog.index()
	_glossary = KeywordGlossary.shared()


## Runs every case.
func run() -> void:
	if _glossary == null:
		_ok("glossary: loads", false)
		return
	_test_colours()
	_test_hover_and_click()
	_test_focus()
	_test_on_screen()
	_test_swapped_scenes()
	_test_surfaces()


# Each keyword in its group's EffectText colour, the rest plain.
func _test_colours() -> void:
	var card: ItemOfferCard = _card(_item(_sample_text()))
	var text: EffectText = card.get_node("%Effects")
	var wrong: PackedStringArray = []
	for id: String in GROUP_SAMPLES:
		var entry: KeywordEntry = _glossary.entry(id)
		var colour: Color = text.get_theme_color(KeywordEntry.colour_item(entry.colour_group))
		var span: String = "[url=%s][color=#%s]" % [id, colour.to_html(false)]
		if not text.text.contains(span):
			wrong.append(id)
	_ok("colour: each group's keyword drawn in its EffectText colour", (
			wrong.is_empty() and text.get_plain_text() == EffectTerms.plain_text(_sample_text())
	), "%s in %s" % [", ".join(wrong), text.text])
	_ok("colour: plain words carry no colour", (
			text.text.begins_with("[url=damage]") and text.text.contains("[/url] and ")
	), text.text)
	_free(card)


# A real mouse move onto the first keyword shows its tooltip; off the text hides it; a click on
# the keyword presses the card.
func _test_hover_and_click() -> void:
	var card: ItemOfferCard = _card(_item(WRITTEN))
	card.pressed.connect(_on_card_pressed)
	var text: EffectText = card.get_node("%Effects")
	_lay_out(card)
	var over: Vector2 = text.get_global_rect().position + FIRST_GLYPH
	# Headless, a RichTextLabel lays its lines out only when drawn, so it can't find the keyword
	# under a pushed mouse move: its hover signals stand in, as the label emits them.
	text.meta_hover_started.emit("block")
	var shown: Array[KeywordTooltip] = text.get_shown_tooltips()
	var entry: KeywordEntry = _glossary.entry("block")
	var texts: PackedStringArray = PackedStringArray() if shown.is_empty() else shown[0].get_texts()
	_ok("hover: the mouse on Block shows its tooltip, its name and explanation", (
			shown.size() == 1 and shown[0].keyword_id == "block"
			and texts == PackedStringArray([entry.display_name, entry.explanation])
	), str(texts))
	_ok("hover: the tooltip's name is in Block's colour", (
			not shown.is_empty() and shown[0].get_name_colour(entry).is_equal_approx(
				text.get_theme_color(KeywordEntry.colour_item(entry.colour_group))
			)
	))
	text.meta_hover_ended.emit("block")
	_ok("hover: leaving the keyword hides its tooltip", text.get_shown_tooltips().is_empty())
	_move_mouse(over)
	text.meta_hover_started.emit("hp")
	_move_mouse(Vector2(_root.get_visible_rect().end) - Vector2(2.0, 2.0))
	_ok("hover: the mouse leaving the text hides its tooltip too", (
			text.get_shown_tooltips().is_empty()
	))
	_pressed = 0
	_move_mouse(over)
	_click(over)
	_ok("hover: a click on the text's first keyword still presses the card", _pressed == 1, (
			"%d" % [_pressed]
	))
	_move_mouse(Vector2.ZERO)
	_free(card)


# Key or pad focus: one tooltip per distinct keyword, in reading order; focus loss hides them;
# mouse focus (hidden) shows none.
func _test_focus() -> void:
	var card: ItemOfferCard = _card(_item(WRITTEN))
	var text: EffectText = card.get_node("%Effects")
	card.grab_focus()
	var ids: PackedStringArray = []
	for tooltip: KeywordTooltip in text.get_shown_tooltips():
		ids.append(tooltip.keyword_id)
	_ok("focus: key or pad focus shows one tooltip per distinct keyword", (
			ids == WRITTEN_IDS
	), str(ids))
	card.release_focus()
	_ok("focus: losing focus hides them", text.get_shown_tooltips().is_empty())
	card.grab_focus(true)
	_ok("focus: mouse focus (hidden) shows none", text.get_shown_tooltips().is_empty())
	card.release_focus()
	_free(card)


# The column inside the visible rect at each size, the card at the right and at the left edge.
func _test_on_screen() -> void:
	var old_size: Vector2i = _root.size
	for screen_size: Vector2i in SCREEN_SIZES:
		_root.size = screen_size
		var visible: Rect2 = _root.get_visible_rect()
		for at_right: bool in [true, false]:
			var card: ItemOfferCard = _card(_item(WRITTEN))
			var text: EffectText = card.get_node("%Effects")
			_lay_out(card)
			var x: float = visible.end.x - card.size.x if at_right else visible.position.x
			card.position = Vector2(x, visible.end.y - card.size.y)
			card.grab_focus()
			_settle(text)
			var outside: PackedStringArray = []
			for tooltip: KeywordTooltip in text.get_shown_tooltips():
				var rect: Rect2 = tooltip.get_global_rect()
				if not visible.grow(0.5).encloses(rect):
					outside.append("%s %s" % [tooltip.keyword_id, rect])
			var column: Rect2 = text.get_tooltip_column().get_global_rect()
			var beside: bool = (
					column.end.x <= card.get_global_rect().position.x + 0.5 if at_right
					else column.position.x >= card.get_global_rect().end.x - 0.5
			)
			_ok("on screen: at %dx%d, the card at the %s edge, the column beside it and inside" % [
				screen_size.x, screen_size.y, "right" if at_right else "left",
			], (
					text.get_shown_tooltips().size() == WRITTEN_IDS.size()
					and outside.is_empty() and beside
			), "%s in %s; column %s" % [", ".join(outside), visible, column])
			card.release_focus()
			_free(card)
	_root.size = old_size


# Every scene that shows effect text holds an EffectText for it.
func _test_swapped_scenes() -> void:
	var wrong: PackedStringArray = []
	for path: String in SWAPPED:
		var scene: PackedScene = load(path)
		var node: Node = scene.instantiate()
		var line: Node = node.get_node_or_null("%" + SWAPPED[path])
		if not line is EffectText:
			wrong.append("%s %s" % [path.get_file(), SWAPPED[path]])
		node.free()
	_ok("surfaces: each scene's effect line is an EffectText", wrong.is_empty(), ", ".join(wrong))


# Real content through each card and row: the catalog's marked text, the words its plain text.
func _test_surfaces() -> void:
	var item: ItemDefinition = _catalog.item("brawn_prawn")
	var heirloom: HeirloomDefinition = _catalog.heirloom("war_ledger")
	if item == null or heirloom == null:
		_ok("surfaces: the catalog holds the Brawn Prawn and War Ledger", false)
		return
	var item_text: String = "\n".join(item.describe_marked())
	var heirloom_text: String = "\n".join(heirloom.describe_marked())
	var results: PackedStringArray = []

	var offer: ItemOfferCard = _card(item)
	results.append(_shows(offer.get_node("%Effects"), item_text, "item offer card"))
	_free(offer)

	var stock: StockCard = STOCK_SCENE.instantiate()
	_root.add_child(stock)
	stock.show_entry(0, heirloom.display_name, heirloom_text, "40 gold", null, "")
	results.append(_shows(stock.get_node("%Details"), heirloom_text, "stock card details"))
	stock.show_entry(1, item.display_name, "Common", "40 gold", null, "")
	stock.show_users(item, null, _catalog)
	results.append(_shows(stock.get_node("%Effects"), item_text, "stock card effects"))
	_free(stock)

	var card: HeirloomOfferCard = HEIRLOOM_SCENE.instantiate()
	_root.add_child(card)
	card.show_heirloom(heirloom, heirloom.id, "")
	results.append(_shows(card.get_node("%Effects"), heirloom_text, "heirloom offer card"))
	_ok("surfaces: the heirloom card's words are its name and plain lines", (
			card.get_card_text() == "\n".join(
				PackedStringArray([heirloom.display_name]) + heirloom.describe()
			)
	), card.get_card_text())
	_free(card)

	var tip: GameTooltip = TOOLTIP_SCENE.instantiate()
	_root.add_child(tip)
	tip.show_tip(heirloom.display_name, heirloom_text)
	results.append(_shows(tip.get_body(), heirloom_text, "tooltip body"))
	_free(tip)

	var line: UnitDetailViewModel.EffectLine = UnitDetailViewModel.EffectLine.new()
	line.label = heirloom.display_name
	line.text = heirloom.effects[0].describe()
	line.marked_text = heirloom.effects[0].describe_marked()
	var row: DetailEffectRow = EFFECT_ROW_SCENE.instantiate()
	_root.add_child(row)
	row.show_effect(line, true)
	results.append(_shows(row.get_node("%EffectText"), line.marked_text, "detail trait row"))
	_free(row)

	var gear: DetailGearRow = GEAR_ROW_SCENE.instantiate()
	_root.add_child(gear)
	gear.show_gear("Pouch", item.display_name, item_text)
	results.append(_shows(gear.get_node("%Detail"), item_text, "detail gear row"))
	_free(gear)

	var wrong: PackedStringArray = []
	for result: String in results:
		if not result.is_empty():
			wrong.append(result)
	_ok("surfaces: each card and row shows the marked text, its words the plain text's", (
			wrong.is_empty()
	), "; ".join(wrong))


# Empty when text shows marked (a tag in it, the words its plain text); else what is wrong.
func _shows(node: Node, marked: String, where: String) -> String:
	var text: EffectText = node as EffectText
	if text == null:
		return "%s: no EffectText" % [where]
	if (
			not marked.contains(EffectTerms.KEYWORD_OPEN) or text.marked_text != marked
			or text.get_plain_text() != EffectTerms.plain_text(marked)
			or text.get_keyword_ids().is_empty()
	):
		return "%s: shows \"%s\"" % [where, text.marked_text]
	return ""


# One line of every colour group's sample keyword, plain words between.
func _sample_text() -> String:
	var parts: PackedStringArray = []
	for id: String in GROUP_SAMPLES:
		var entry: KeywordEntry = _glossary.entry(id)
		parts.append("[kw=%s]%s[/kw]" % [id, entry.display_name])
	return " and ".join(parts)


# A consumable carrying one effect with written text: the cards show it as its effect line.
func _item(written: String) -> ItemDefinition:
	var effect: EffectDefinition = EffectDefinition.new()
	effect.id = "keyword_test"
	effect.written_text = written
	var item: ConsumableDefinition = ConsumableDefinition.new()
	item.id = "keyword_test_item"
	item.display_name = "Keyword Test"
	item.effects = [effect]
	return item


func _card(item: ItemDefinition) -> ItemOfferCard:
	var card: ItemOfferCard = CARD_SCENE.instantiate()
	_root.add_child(card)
	card.show_item(item, item.id)
	_lay_out(card)
	return card


# Sizes and sorts card and its children now, as a frame's layout would.
func _lay_out(control: Control) -> void:
	for _pass: int in 3:
		if control.has_method(&"fit_content"):
			control.call(&"fit_content")
		control.reset_size()
		for node: Node in control.find_children("*", "Container", true, false):
			node.notification(Container.NOTIFICATION_SORT_CHILDREN)


# Sorts text's tooltip column and places it again, as the frame after showing it does.
func _settle(text: EffectText) -> void:
	var column: Control = text.get_tooltip_column()
	for _pass: int in 2:
		for tooltip: KeywordTooltip in text.get_shown_tooltips():
			tooltip.notification(Container.NOTIFICATION_SORT_CHILDREN)
			tooltip.get_node("Lines").notification(Container.NOTIFICATION_SORT_CHILDREN)
			tooltip.reset_size()
		column.notification(Container.NOTIFICATION_SORT_CHILDREN)
		text.place_tooltips()


func _move_mouse(point: Vector2) -> void:
	var motion: InputEventMouseMotion = InputEventMouseMotion.new()
	motion.position = point
	motion.global_position = point
	_root.push_input(motion, true)


func _click(point: Vector2) -> void:
	for is_down: bool in [true, false]:
		var click: InputEventMouseButton = InputEventMouseButton.new()
		click.position = point
		click.global_position = point
		click.button_index = MOUSE_BUTTON_LEFT
		click.pressed = is_down
		_root.push_input(click, true)


func _free(node: Node) -> void:
	if is_instance_valid(node):
		node.get_parent().remove_child(node)
		node.free()


func _on_card_pressed() -> void:
	_pressed += 1


func _ok(case_name: String, passed: bool, detail: String = "") -> void:
	_check.call(case_name, passed, detail)
