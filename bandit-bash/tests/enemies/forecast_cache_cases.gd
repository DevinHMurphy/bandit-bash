# ==============================================================================
# Bandit Bash
# Copyright (c) 2026 Derc Development
# Licensed under the MIT License. See LICENSE.
#
# File:     forecast_cache_cases.gd
# Author:
# Created:  November 20, 2026
# Modified: November 20, 2026
# ==============================================================================

extends RefCounted
## The attack forecast cache's cases (move-preview.md, layer 2; [EnemyAI.Forecasts]): a decision
## on an unchanged board reuses every forecast and gives the same plan; a change to a unit, its HP,
## an effect's counter, the darkness under a tile or an effect reading the whole board makes the
## forecasts it can touch afresh, while a change far from every key keeps them; a preview's own
## forecasts join the store as it ends, the oldest dropped past its limit; a negative margin
## reuses nothing; checking mode reports a reuse made stale behind the cache's back and nothing on
## an honest one; and intents reuse forecasts across the steps of the phase and across previews.
## Every plan is also compared with a decision made with no cache. Real catalog classes (the Brute
## and the Crossbowman) against hand-built player units. Reports each case through its callable.
##
## @tutorial(The move preview): docs/design/move-preview.md

# The suite that runs this file; tests/case_files.gd finds it by this line.
const SUITE: String = "enemies/preview"

# A preloaded script used as a type (gdscript.md, Naming): the world has no class name.
const AiWorld = preload("res://tests/enemies/ai_world.gd")

# The margin the views are given: the Brute's Cleave reaches 1, and 2 also covers a unit beside
# a target's neighbour.
const MARGIN: int = 2

# A store limit no case here reaches but the limit case's.
const STORE_LIMIT: int = 100

const BRUTE: String = "brute"
const CROSSBOWMAN: String = "crossbowman"

const PLAIN_12X8: Array[String] = [
	"plain plain plain plain plain plain plain plain plain plain plain plain",
	"plain plain plain plain plain plain plain plain plain plain plain plain",
	"plain plain plain plain plain plain plain plain plain plain plain plain",
	"plain plain plain plain plain plain plain plain plain plain plain plain",
	"plain plain plain plain plain plain plain plain plain plain plain plain",
	"plain plain plain plain plain plain plain plain plain plain plain plain",
	"plain plain plain plain plain plain plain plain plain plain plain plain",
	"plain plain plain plain plain plain plain plain plain plain plain plain",
]

# Where the far player unit stands, out of every key's margin, and the tile it is moved to, within
# the margin of the Brute's target p1.
const FAR_TILE: Vector2i = Vector2i(11, 7)
const NEAR_TILE: Vector2i = Vector2i(5, 1)
# Where p2 steps for the preview case: more than the margin from p1 and the Brute's ends beside it.
const P2_STEP: Vector2i = Vector2i(5, 6)

var _check: Callable = Callable()
var _catalog: EffectCatalog.Index = null


## [param check]: called as check(case_name: String, passed: bool, detail: String).
func _init(check: Callable) -> void:
	_check = check
	_catalog = EffectCatalog.index()


func run() -> void:
	_test_same_board_reuses()
	_test_new_store_makes_afresh()
	_test_overlay_stays_out_of_store()
	_test_overlay_added_when_preview_ends()
	_test_limit_drops_oldest_preview_first()
	_test_hp_change_misses()
	_test_unit_moved_near_misses()
	_test_counter_change_misses()
	_test_darkness_change_misses()
	_test_far_change_keeps()
	_test_whole_board_effect_misses_far()
	_test_negative_margin_reuses_nothing()
	_test_checking_reports_stale()
	_test_checking_honest_reuse()
	_test_intents_reuse_across_steps_and_previews()


# The Brute decides twice on one unchanged board through two views of one store: the second makes
# nothing and reuses what the first made, with the same plan as a decision with no cache.
func _test_same_board_reuses() -> void:
	var world: AiWorld = _world()
	var store: EnemyAI.ForecastStore = EnemyAI.ForecastStore.new()
	var first: EnemyAI.Forecasts = EnemyAI.Forecasts.new(store, MARGIN, false, true)
	var before: EnemyPlan = _decide(world, "e1", first)
	var second: EnemyAI.Forecasts = EnemyAI.Forecasts.new(store, MARGIN)
	var after: EnemyPlan = _decide(world, "e1", second)
	_check.call("cache: a second decision on an unchanged board reuses every forecast", (
			first.made > 0
			and first.reused == 0
			and second.made == 0
			and second.reused == first.made
			and store.size() == first.made
	), "first made %d reused %d; second made %d reused %d; kept %d" % [
		first.made, first.reused, second.made, second.reused, store.size(),
	])
	_check.call("cache: the reused plan equals the first and a decision with no cache", (
			_plan_text(after) == _plan_text(before)
			and _plan_text(after) == _plan_text(_decide(world, "e1", null))
	), "%s / %s" % [_plan_text(before), _plan_text(after)])


func _test_new_store_makes_afresh() -> void:
	var world: AiWorld = _world()
	_filled(world)
	var fresh: EnemyAI.Forecasts = EnemyAI.Forecasts.new(EnemyAI.ForecastStore.new(), MARGIN)
	_decide(world, "e1", fresh)
	_check.call("cache: a new store reuses nothing", fresh.made > 0 and fresh.reused == 0, (
			"made %d reused %d" % [fresh.made, fresh.reused]
	))


# A view that doesn't fill the store (a preview's) keeps what it makes in its own overlay: it
# reuses them itself, and the store and a later view never see them.
func _test_overlay_stays_out_of_store() -> void:
	var world: AiWorld = _world()
	var store: EnemyAI.ForecastStore = EnemyAI.ForecastStore.new()
	var preview: EnemyAI.Forecasts = EnemyAI.Forecasts.new(store, MARGIN)
	_decide(world, "e1", preview)
	var made: int = preview.made
	_decide(world, "e1", preview)
	var later: EnemyAI.Forecasts = EnemyAI.Forecasts.new(store, MARGIN)
	_decide(world, "e1", later)
	_check.call("cache: a preview's forecasts stay in its overlay, out of the store", (
			made > 0
			and preview.made == made
			and preview.reused == made
			and store.size() == 0
			and later.reused == 0
	), "made %d, again %d reused %d; kept %d; later reused %d" % [
		made, preview.made, preview.reused, store.size(), later.reused,
	])


# A preview's forecasts reach the store as it ends, for the next preview to reuse.
func _test_overlay_added_when_preview_ends() -> void:
	var world: AiWorld = _world()
	var store: EnemyAI.ForecastStore = EnemyAI.ForecastStore.new(STORE_LIMIT)
	_decide(world, "e1", EnemyAI.Forecasts.new(store, MARGIN, false, true))
	var computed: int = store.size()
	var preview: EnemyAI.Forecasts = EnemyAI.Forecasts.new(store, MARGIN)
	_decide(world, "e2", preview)
	preview.add_overlay_to_store()
	var next: EnemyAI.Forecasts = EnemyAI.Forecasts.new(store, MARGIN)
	_decide(world, "e2", next)
	_check.call("cache: a preview's forecasts join the store as it ends, for the next to reuse", (
			computed > 0
			and preview.made > 0
			and store.size() == computed + preview.made
			and next.made == 0
			and next.reused == preview.made
	), "computed %d, preview made %d, kept %d, next made %d reused %d" % [
		computed, preview.made, store.size(), next.made, next.reused,
	])


# Past the limit the oldest previews' forecasts are dropped first; the computation's stay.
func _test_limit_drops_oldest_preview_first() -> void:
	var world: AiWorld = _world()
	var store: EnemyAI.ForecastStore = EnemyAI.ForecastStore.new(1)
	_decide(world, "e1", EnemyAI.Forecasts.new(store, MARGIN, false, true))
	var computed: int = store.size()
	var preview: EnemyAI.Forecasts = EnemyAI.Forecasts.new(store, MARGIN)
	_decide(world, "e2", preview)
	preview.add_overlay_to_store()
	var brute: EnemyAI.Forecasts = EnemyAI.Forecasts.new(store, MARGIN)
	_decide(world, "e1", brute)
	var crossbowman: EnemyAI.Forecasts = EnemyAI.Forecasts.new(store, MARGIN)
	_decide(world, "e2", crossbowman)
	_check.call("cache: past the limit a preview keeps its newest, the computation keeps all", (
			preview.made > 1
			and store.size() == computed + 1
			and brute.made == 0
			and crossbowman.reused == 1
	), "computed %d, preview made %d, kept %d; Brute made %d; Crossbowman reused %d" % [
		computed, preview.made, store.size(), brute.made, crossbowman.reused,
	])


# The Brute's target loses HP: its forecasts are made afresh, and the plan is a fresh decision's.
func _test_hp_change_misses() -> void:
	var world: AiWorld = _world()
	var store: EnemyAI.ForecastStore = _filled(world)
	world.wound("p1", 3)
	_check_misses(world, store, "the target's HP changes")


# The far unit walks to within the margin of the Brute's target.
func _test_unit_moved_near_misses() -> void:
	var world: AiWorld = _world()
	var store: EnemyAI.ForecastStore = _filled(world)
	world.state().move_unit("p_far", NEAR_TILE)
	_check_misses(world, store, "a unit moves within the margin")


# A counter of the Brute's own effects changes (Cleave's, as a combat-lane count).
func _test_counter_change_misses() -> void:
	var world: AiWorld = _world()
	var store: EnemyAI.ForecastStore = _filled(world)
	var changed: String = ""
	for instance: EffectInstance in world.engine().get_instances():
		if instance.owner.holder_id == "e1":
			instance.set_counter(EffectTerms.Lane.COMBAT, 1)
			changed = instance.instance_id
			break
	_check.call("cache: the Brute holds an effect to count on", not changed.is_empty(), "")
	_check_misses(world, store, "an effect's counter changes")


# A far tile floods: the darkness is read by every forecast's units, so all of them are redone.
func _test_darkness_change_misses() -> void:
	var world: AiWorld = _world()
	var store: EnemyAI.ForecastStore = _filled(world)
	world.state().map.darkness.layers[Vector2i(11, 0)] = WhileLayerCondition.Layer.DUSK
	_check_misses(world, store, "the darkness under a tile changes")


# The far unit is wounded and walks along the map's far edge: no key holds it.
func _test_far_change_keeps() -> void:
	var world: AiWorld = _world()
	var store: EnemyAI.ForecastStore = _filled(world)
	world.wound("p_far", 2)
	world.state().move_unit("p_far", FAR_TILE + Vector2i(-1, 0))
	var view: EnemyAI.Forecasts = EnemyAI.Forecasts.new(store, MARGIN)
	var plan: EnemyPlan = _decide(world, "e1", view)
	_check.call("cache: a change outside every key's margin keeps every forecast", (
			view.made == 0
			and view.reused > 0
			and _plan_text(plan) == _plan_text(_decide(world, "e1", null))
	), "made %d reused %d" % [view.made, view.reused])


# An army effect selecting every unit of the side on a defeat (Grave Candle's shape) reads the
# whole board, so a far change makes every forecast afresh.
func _test_whole_board_effect_misses_far() -> void:
	var world: AiWorld = _world()
	var block: GainResource = GainResource.new()
	block.pool = GainResource.Pool.BLOCK
	block.target = AllOfScope.new()
	var four: Constant = Constant.new()
	four.value = 4.0
	block.amount = four
	var mourning: EffectDefinition = EffectDefinition.new()
	mourning.trigger = EffectTerms.Trigger.DEFEATED
	mourning.scope = EffectTerms.Scope.YOUR_UNIT
	mourning.operations.assign([block])
	world.engine().register(EffectInstance.new(
			"effect:mourning", mourning, EffectOwner.for_army("seat:0", 0),
			Modifier.SourceKind.HEIRLOOM, "Mourning"
	))
	var store: EnemyAI.ForecastStore = _filled(world)
	world.wound("p_far", 2)
	_check_misses(world, store, "an effect reads the whole board and a far unit changes")


func _test_negative_margin_reuses_nothing() -> void:
	var world: AiWorld = _world()
	var store: EnemyAI.ForecastStore = EnemyAI.ForecastStore.new()
	_decide(world, "e1", EnemyAI.Forecasts.new(store, -1, false, true))
	var again: EnemyAI.Forecasts = EnemyAI.Forecasts.new(store, -1, false, true)
	_decide(world, "e1", again)
	_check.call("cache: a margin below 0 (an effect reads the whole map) reuses nothing", (
			again.made > 0 and again.reused == 0 and store.size() == 0
	), "made %d reused %d kept %d" % [again.made, again.reused, store.size()])


# The Brute's target gains 10 DEF with no fact, so no signature sees it: the forecasts are reused
# stale, and checking mode makes each afresh and reports the difference.
func _test_checking_reports_stale() -> void:
	var world: AiWorld = _world()
	var store: EnemyAI.ForecastStore = _filled(world)
	world.engine().add_delta("p1", Modifier.new(
			CombatValue.Key.DEF, Modifier.Mode.ADD, 10.0, Modifier.SourceKind.UNIT_TRAIT,
			"test:hidden", "hidden"
	))
	var view: EnemyAI.Forecasts = EnemyAI.Forecasts.new(store, MARGIN, true)
	_decide(world, "e1", view)
	_check.call("checking: a forecast reused stale behind the cache's back is reported", (
			view.reused > 0 and view.checked == view.reused and not view.mismatches.is_empty()
	), "reused %d checked %d; %s" % [view.reused, view.checked, "; ".join(view.mismatches)])


func _test_checking_honest_reuse() -> void:
	var world: AiWorld = _world()
	var store: EnemyAI.ForecastStore = _filled(world)
	var view: EnemyAI.Forecasts = EnemyAI.Forecasts.new(store, MARGIN, true)
	_decide(world, "e1", view)
	_check.call("checking: an honest reuse is checked and finds nothing", (
			view.reused > 0 and view.checked == view.reused and view.mismatches.is_empty()
	), "reused %d checked %d; %s" % [view.reused, view.checked, "; ".join(view.mismatches)])


# Intents.compute reuses forecasts from one step of the phase to the next (the Crossbowman's,
# after the Brute acts far from them), and a preview built on them reuses theirs, with checking
# mode finding nothing changed: p2 steps aside, so the enemies decide again, and the Brute's
# forecasts on p1 are out of its reach.
func _test_intents_reuse_across_steps_and_previews() -> void:
	var world: AiWorld = _world()
	EnemyAI.register(world.session, _catalog)
	Intents.register(world.session, _catalog)
	world.session.open_battle()
	var latest: Intents = world.session.intents
	_check.call("cache: intents reuse forecasts from one step of the phase to the next", (
			latest != null and latest.forecasts_reused > 0
	), "made %d reused %d" % [
		-1 if latest == null else latest.forecasts_made,
		-1 if latest == null else latest.forecasts_reused,
	])
	var was_checking: bool = Intents.is_checking
	Intents.is_checking = true
	var preview: Intents = Intents.preview(world.session, "p2", P2_STEP)
	Intents.is_checking = was_checking
	var flags: PackedStringArray = []
	if preview != null:
		for line: String in preview.diagnostics:
			if line.begins_with(Intents.CHECK_PREFIX):
				flags.append(line)
	_check.call("cache: a preview reuses the latest intents' forecasts, checked unchanged", (
			preview != null and preview.forecasts_reused > 0 and flags.is_empty()
	), "made %d reused %d; %s" % [
		-1 if preview == null else preview.forecasts_made,
		-1 if preview == null else preview.forecasts_reused,
		"; ".join(flags),
	])


# A store holding the Brute's forecasts on world's board as it is, as Intents.compute fills one.
func _filled(world: AiWorld) -> EnemyAI.ForecastStore:
	var store: EnemyAI.ForecastStore = EnemyAI.ForecastStore.new()
	_decide(world, "e1", EnemyAI.Forecasts.new(store, MARGIN, false, true))
	return store


# After a change near the Brute's options: a decision through store makes forecasts afresh and
# gives the plan a decision with no cache gives.
func _check_misses(world: AiWorld, store: EnemyAI.ForecastStore, change: String) -> void:
	var view: EnemyAI.Forecasts = EnemyAI.Forecasts.new(store, MARGIN)
	var plan: EnemyPlan = _decide(world, "e1", view)
	var fresh: EnemyPlan = _decide(world, "e1", null)
	_check.call("cache: %s, so its forecasts are made afresh" % [change], (
			view.made > 0 and _plan_text(plan) == _plan_text(fresh)
	), "made %d reused %d; %s / %s" % [
		view.made, view.reused, _plan_text(plan), _plan_text(fresh),
	])


func _decide(world: AiWorld, unit_id: String, forecasts: EnemyAI.Forecasts) -> EnemyPlan:
	return EnemyAI.decide(world.engine(), _catalog, unit_id, {}, [], forecasts)


# A Brute with p1 two tiles away, a Crossbowman with p2 in its reach, and p_far out of everyone's.
func _world() -> AiWorld:
	var world: AiWorld = AiWorld.new(_catalog, PLAIN_12X8)
	world.add_enemy("e1", BRUTE, Vector2i(1, 1))
	world.add_enemy("e2", CROSSBOWMAN, Vector2i(1, 5))
	world.add_player("p1", Vector2i(3, 1))
	world.add_player("p2", Vector2i(4, 5))
	world.add_player("p_far", FAR_TILE)
	return world


# plan as one line: its kind, target, weapon, path, rating and its forecast's text.
static func _plan_text(plan: EnemyPlan) -> String:
	var parts: PackedStringArray = [
		EnemyPlan.Kind.find_key(plan.kind), plan.target_id, plan.weapon_id, str(plan.path),
		str(plan.is_kill), str(plan.kill_chance), str(plan.value), str(plan.target_rule_key),
	]
	var exchange: CombatForecast.ExchangeForecast = plan.forecast as CombatForecast.ExchangeForecast
	if exchange != null:
		parts.append(EnemyAI.Forecasts.text_of(exchange))
	return " ".join(parts)
