# ==============================================================================
# Bandit Bash
# Copyright (c) 2026 Derc Development
# Licensed under the MIT License. See LICENSE.
#
# File:     600_contact_sheets.gd
# Author:
# Created:  November 19, 2026
# Modified: November 19, 2026
# ==============================================================================

extends "res://tools/captures/capture_group.gd"
## Contact sheets for reviewing the art picks: every sprite in the unit sprite table at twice its
## size with its key, then every item's icon with its name, a page at a time. Each is drawn over
## whatever screen is open and removed after, so it needs no earlier group.

const UNIT_SPRITES: String = "res://assets/sprites/units/unit_sprites.tres"

# The sheets' layout, in base units: columns, art size, label width, margin, and how many items
# fit a page at 1280×720. Drawn over every screen.
const SHEET_UNIT_COLUMNS: int = 5
const SHEET_UNIT_ICON: int = 64
const SHEET_ITEM_COLUMNS: int = 6
const SHEET_ITEM_ICON: int = 32
const SHEET_ITEMS_PER_PAGE: int = 84
const SHEET_LABEL_WIDTH: int = 140
const SHEET_MARGIN: int = 12
const SHEET_LAYER: int = 100


func run() -> bool:
	var table: UnitSpriteTable = load(UNIT_SPRITES)
	var units: Array[Array] = []
	var keys: Array[String] = []
	keys.assign(table.sprites.keys())
	keys.sort()
	for key: String in keys:
		units.append([key, table.sprites[key]])
	await _sheet("sheet_unit_sprites", units, SHEET_UNIT_COLUMNS, SHEET_UNIT_ICON)
	var items: Array[Array] = []
	for kind: EffectCatalog.Kind in [
		EffectCatalog.Kind.WEAPON, EffectCatalog.Kind.EQUIPMENT, EffectCatalog.Kind.TRINKET,
		EffectCatalog.Kind.CONSUMABLE,
	]:
		for resource: Resource in EffectCatalog.all_of(kind):
			var item: ItemDefinition = resource as ItemDefinition
			if item != null:
				items.append([item.display_name, item.icon])
	var page: int = 0
	while page * SHEET_ITEMS_PER_PAGE < items.size():
		var start: int = page * SHEET_ITEMS_PER_PAGE
		var shown: Array[Array] = []
		shown.assign(items.slice(start, start + SHEET_ITEMS_PER_PAGE))
		await _sheet(
				"sheet_item_icons_%d" % [page + 1], shown, SHEET_ITEM_COLUMNS, SHEET_ITEM_ICON
		)
		page += 1
	return true


# One contact sheet of entries ([label, texture]) in a grid over the screen, captured and removed.
func _sheet(shot_name: String, entries: Array[Array], columns: int, icon_size: int) -> void:
	var layer: CanvasLayer = CanvasLayer.new()
	layer.layer = SHEET_LAYER
	var backdrop: Panel = Panel.new()
	backdrop.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	layer.add_child(backdrop)
	var grid: GridContainer = GridContainer.new()
	grid.columns = columns
	layer.add_child(grid)
	grid.set_anchors_and_offsets_preset(
			Control.PRESET_FULL_RECT, Control.PRESET_MODE_MINSIZE, SHEET_MARGIN
	)
	for entry: Array in entries:
		var cell: HBoxContainer = HBoxContainer.new()
		cell.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		var art: TextureRect = TextureRect.new()
		art.texture = entry[1]
		art.texture_filter = CanvasItem.TEXTURE_FILTER_NEAREST
		art.custom_minimum_size = Vector2(icon_size, icon_size)
		art.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
		art.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_CENTERED
		cell.add_child(art)
		var label: Label = Label.new()
		label.text = entry[0]
		label.clip_text = true
		label.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		label.custom_minimum_size = Vector2(SHEET_LABEL_WIDTH, 0.0)
		cell.add_child(label)
		grid.add_child(cell)
	tree.root.add_child(layer)
	await frames(SETTLE_FRAMES)
	await capture(shot_name)
	layer.queue_free()
	await frames(1)
