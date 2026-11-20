# ==============================================================================
# Bandit Bash
# Copyright (c) 2026 Derc Development
# Licensed under the MIT License. See LICENSE.
#
# File:     360_battle_darkness_layers.gd
# Author:
# Created:  November 19, 2026
# Modified: November 19, 2026
# ==============================================================================

extends "res://tools/captures/capture_group.gd"
## The board with its darkness drawn in three bands, Dusk, Gloom and Abyss, from the map's left
## edge, for judging each layer's opacity by eye; the board's own darkness is drawn again after.
## Drawing only: the session's darkness is untouched.[br]
## Needs: the battle started (300_battle_start).


func run() -> bool:
	var view: BattleView = battle_view()
	var session: CombatSession = view.get_session()
	var overlay: DarknessOverlay = view.get_darkness()
	var kept: Dictionary[Vector2i, int] = {}
	for tile: Vector2i in overlay.drawn_tiles():
		kept[tile] = overlay.layer_at(tile)
	var rect: Rect2i = session.layout.get_rect()
	var band: int = maxi(floori(rect.size.x / 4.0), 1)
	var bands: Dictionary[Vector2i, int] = {}
	for y: int in range(rect.position.y, rect.end.y):
		for x: int in range(rect.position.x, mini(rect.position.x + band * 3, rect.end.x)):
			var across: int = floori(float(x - rect.position.x) / band)
			var layer: int = WhileLayerCondition.Layer.DUSK + across
			bands[Vector2i(x, y)] = mini(layer, WhileLayerCondition.Layer.ABYSS)
	overlay.show_layers(bands)
	await frames(SETTLE_FRAMES)
	await capture("battle_darkness_layers")
	overlay.show_layers(kept)
	return true
