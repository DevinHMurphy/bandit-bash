# ==============================================================================
# Bandit Bash
# Copyright (c) 2026 Derc Development
# Licensed under the MIT License. See LICENSE.
#
# File:     420_keywords.gd
# Author:
# Created:  November 22, 2026
# Modified: November 22, 2026
# ==============================================================================

extends "res://tools/captures/capture_group.gd"
## The keyword shots ([EffectText], [KeywordTooltip]), over the map on a panel of their own: a row
## of a sampler item card (a keyword of each colour group, in written text made here) and the
## Lantern Oil and Bounty Ledger heirloom cards, at rest; the sampler's Block hovered (its hover
## signal, as the mouse gives it); and Lantern Oil focused as a pad focuses it, every keyword's
## tooltip stacked beside it. The panel is removed, so the group ends on the map as it found it.
## [br]
## Needs: the map (415_effect_text leaves it there). Runs before 450.

const ITEM_CARD_SCENE: PackedScene = preload("res://ui/campaign/item_offer_card.tscn")
const HEIRLOOM_CARD_SCENE: PackedScene = preload("res://ui/campaign/heirloom_offer_card.tscn")

# The sampler's text: one keyword of each colour group, in danger, block, heal, accent, darkness
# order, the words a plain sentence.
const SAMPLER_TEXT: String = (
		"Deal 2 [kw=damage]damage[/kw], gain 3 [kw=block]Block[/kw], [kw=heal]heal[/kw] 4"
		+ " [kw=hp]HP[/kw] and earn 5 [kw=gold]Gold[/kw] while in the [kw=darkness]darkness[/kw]."
)

# The heirlooms shown beside the sampler, Lantern Oil first (the one focused).
const HEIRLOOMS: PackedStringArray = ["lantern_oil", "bounty_ledger"]

# The gap between the cards, on the style guide's 16-unit gap between groups. Units: base units.
const CARD_GAP: int = 16


func run() -> bool:
	if router_screen() != SCREEN_MAP:
		fail("the keyword shots need the map (screen %d)" % [router_screen()])
		return true
	var layer: CanvasLayer = CanvasLayer.new()
	tree.root.add_child(layer)
	var backdrop: PanelContainer = PanelContainer.new()
	backdrop.theme_type_variation = &"FloatingPanel"
	backdrop.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	layer.add_child(backdrop)
	var center: CenterContainer = CenterContainer.new()
	backdrop.add_child(center)
	var row: HBoxContainer = HBoxContainer.new()
	row.add_theme_constant_override(&"separation", CARD_GAP)
	center.add_child(row)
	var sampler: ItemOfferCard = ITEM_CARD_SCENE.instantiate()
	row.add_child(sampler)
	sampler.show_item(_sampler(), "keyword_sampler")
	var cards: Array[HeirloomOfferCard] = []
	var catalog: EffectCatalog.Index = EffectCatalog.index()
	for heirloom_id: String in HEIRLOOMS:
		var definition: HeirloomDefinition = catalog.heirloom(heirloom_id)
		if definition == null:
			fail("the keyword shots need %s in the catalog" % [heirloom_id])
			continue
		var card: HeirloomOfferCard = HEIRLOOM_CARD_SCENE.instantiate()
		row.add_child(card)
		card.show_heirloom(definition, heirloom_id, "")
		cards.append(card)
	await frames(SETTLE_FRAMES)
	await capture("keywords_colours")

	var text: EffectText = sampler.get_node("%Effects")
	text.meta_hover_started.emit("block")
	await frames(SETTLE_FRAMES)
	await capture("keywords_hovered")
	text.meta_hover_ended.emit("block")

	if not cards.is_empty():
		cards[0].grab_focus()
		await frames(SETTLE_FRAMES)
		await capture("keywords_pad_focus")
		cards[0].release_focus()
	layer.queue_free()
	await frames(SETTLE_FRAMES)
	return true


# The sampler item: one effect whose written text is SAMPLER_TEXT.
func _sampler() -> ItemDefinition:
	var effect: EffectDefinition = EffectDefinition.new()
	effect.id = "keyword_sampler"
	effect.written_text = SAMPLER_TEXT
	var item: ConsumableDefinition = ConsumableDefinition.new()
	item.id = "keyword_sampler"
	item.display_name = "Keyword Sampler"
	item.effects = [effect]
	return item
