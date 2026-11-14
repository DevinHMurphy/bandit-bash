# ==============================================================================
# Bandit Bash
# Copyright (c) 2026 Derc Development
# Licensed under the MIT License. See LICENSE.
#
# File:     pack_catalog.gd
# Author:
# Created:  November 13, 2026
# Modified: November 13, 2026
# ==============================================================================

extends RefCounted
## A copy of a catalog whose only pack is the one named, for cases that need to know a battle's
## enemies: setup step 4 draws its pack from every pack in the catalog it is given
## ([method EnemySetup.draw]), so on the real catalog a seeded battle can field any of them.
##
## Test-only. The copy shares the catalog's definitions, which are read-only, so nothing loads
## again; every other file keeps its path, in the same order.


## [param catalog] with every [PackDefinition] but [param pack_id] left out.
static func with_only(catalog: EffectCatalog.Index, pack_id: String) -> EffectCatalog.Index:
	var copy: EffectCatalog.Index = EffectCatalog.Index.new()
	copy.root = catalog.root
	for path: String in catalog.paths:
		var definition: Resource = catalog.at_path(path)
		if definition == null:
			continue
		var pack: PackDefinition = definition as PackDefinition
		if pack != null and pack.id != pack_id:
			continue
		copy.add(path, definition)
	copy.finish()
	return copy
