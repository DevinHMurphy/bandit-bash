# ==============================================================================
# Bandit Bash
# Copyright (c) 2026 Derc Development
# Licensed under the MIT License. See LICENSE.
#
# File:     pack_catalog.gd
# Author:
# Created:  November 13, 2026
# Modified: November 15, 2026
# ==============================================================================

extends RefCounted
## Packs for cases that need to know a battle's enemies: a copy of a catalog whose only pack is the
## one named, drawn by every standard combat that hasn't reached the hard pool, and fixture packs.
## Setup step 4 draws from a pool of the catalog's packs ([method EnemySetup.draw]), so on the real
## catalog a seeded battle can field any of them, and the M1 Pack is never drawn.
##
## Test-only. The copy shares the catalog's definitions, which are read-only, so nothing loads
## again; every other file keeps its path, in the same order.


## [param catalog] with every [PackDefinition] but [param pack_id] left out, and that one replaced
## by a copy in the basic pool, so a standard combat with fewer than
## [constant EnemySetup.BASIC_COMBATS_PER_STEP] before it in its step draws it (the M1 Pack is in
## no pool of its own).
static func with_only(catalog: EffectCatalog.Index, pack_id: String) -> EffectCatalog.Index:
	var copy: EffectCatalog.Index = EffectCatalog.Index.new()
	copy.root = catalog.root
	for path: String in catalog.paths:
		var definition: Resource = catalog.at_path(path)
		if definition == null:
			continue
		var pack: PackDefinition = definition as PackDefinition
		if pack != null:
			if pack.id != pack_id:
				continue
			var drawn: PackDefinition = pack.duplicate() as PackDefinition
			drawn.pool = PackDefinition.Pool.BASIC
			definition = drawn
		copy.add(path, definition)
	copy.finish()
	return copy


## A fixture pack [param id] in [param pool] fielding [param counts] (class id to count, in
## placement order) at every step, whatever the step's size.
static func fixture(
		id: String, counts: Dictionary, pool: PackDefinition.Pool = PackDefinition.Pool.BASIC
) -> PackDefinition:
	var pack: PackDefinition = PackDefinition.new()
	pack.id = id
	pack.display_name = id
	pack.pool = pool
	pack.step_1_counts.assign(counts)
	pack.step_2_counts.assign(counts)
	pack.step_3_counts.assign(counts)
	return pack
