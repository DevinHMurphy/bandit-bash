# ==============================================================================
# Bandit Bash
# Copyright (c) 2026 Derc Development
# Licensed under the MIT License. See LICENSE.
#
# File:     object_attack_cases.gd
# Author:
# Created:  November 19, 2026
# Modified: November 19, 2026
# ==============================================================================

extends "res://tests/ui/battle/input/rune_cases.gd"
## Attacking breakable map objects for the ui/input suite (BUG-019): debris and powder kegs in the
## Attack list, enemies first then objects in spot order, exactly what the validator accepts, and
## a broken one gone; by keys, mouse and pad, each of wooden debris, stone debris and a keg
## targeted (outlined, the cursor, the HUD's unit view on it), its forecast (no counter, crit or
## Stance; DEF and RES; a keg's chain of blasts drawn and its splash on friendly units flashed)
## matching the exchange once confirmed; and breaking each: the event log's line, the board's
## feedback, the token gone. The harness and device drivers are rune_cases.gd's.
##
## Its fixture replaces rune_cases.gd's keg chain: next to seat 0's units, a keg (with a second in
## its blast) beside a melee unit, then wooden and stone debris, each in another unit's reach and
## out of every blast; every player unit at full HP (test setup only; the UI never does this).

const WOODEN: MapLayout.ObjectKind = MapLayout.ObjectKind.WOODEN_DEBRIS
const STONE: MapLayout.ObjectKind = MapLayout.ObjectKind.STONE_DEBRIS
const KEG: MapLayout.ObjectKind = MapLayout.ObjectKind.POWDER_KEG

# The order the device cases attack in: the keg last, as its blasts reach the debris attackers.
const ATTACK_ORDER: Array[MapLayout.ObjectKind] = [WOODEN, STONE, KEG]

# The fixture's object spot indices: far above any map's own and rune_cases.gd's kegs (900).
const OBJECT_INDEX: int = 950

# HP the break case leaves each debris at, so one hit breaks it.
const LOW_HP: int = 1

const ATTACK_KIND: TurnInputModel.ActionKind = TurnInputModel.ActionKind.ATTACK
const NONE_SIDE: CombatFact.CombatSide = CombatFact.CombatSide.NONE

# The last fixture's objects by kind (the keg is the one attacked), its chain keg, and who attacks
# each object, by object id.
var _placed: Dictionary[MapLayout.ObjectKind, String] = {}
var _chain_keg: String = ""
var _attacker_of: Dictionary[String, String] = {}

# Whether the next fixture leaves its debris at LOW_HP.
var _is_low_hp: bool = false


## Runs every case.
func run() -> void:
	_map = load(M1_DEFINITION) as CombatMapDefinition
	if _map == null:
		_check.call("objects: the M1 map definition loads", false, M1_DEFINITION)
		return
	_test_attack_list()
	_test_broken_gone()
	for device: Device in [Device.KEYS, Device.MOUSE, Device.PAD]:
		_test_attack_by(device)
	_test_break_feedback()


# Every acting unit's Attack lists exactly what the validator accepts on every unit and object on
# the map, enemies first in state order, then objects in spot order; each fixture object is
# listed for its attacker.
func _test_attack_list() -> void:
	var h: TurnInputCases.Harness = _object_harness("list")
	if h == null:
		return
	var session: CombatSession = h.session
	var state: CombatState = session.state
	var problems: PackedStringArray = []
	for unit_id: String in TurnInputModel.acting_units(session, 0):
		var attack: TurnInputModel.ActionOption = _attack_option(session, unit_id)
		var listed: PackedStringArray = _listed_attacks(attack)
		var accepted: PackedStringArray = _accepted_attacks(session, unit_id)
		if listed != accepted:
			problems.append("%s: listed %s, accepted %s" % [unit_id, listed, accepted])
		if attack == null:
			continue
		var seen_object: bool = false
		var last_index: int = -1
		for target: TurnInputModel.TargetOption in attack.targets:
			var is_object: bool = state.side_of(target.target_id) == NONE_SIDE
			if not is_object and seen_object:
				problems.append("%s: enemy %s after an object" % [unit_id, target.target_id])
			if is_object:
				seen_object = true
				var index: int = state.map.object(target.target_id).index
				if index < last_index:
					problems.append("%s: %s out of spot order" % [unit_id, target.target_id])
				last_index = index
				if target.tile != state.map.object(target.target_id).tile:
					problems.append("%s: %s's tile" % [unit_id, target.target_id])
	for kind: MapLayout.ObjectKind in ATTACK_ORDER:
		var object_id: String = _placed.get(kind, "")
		var attacker: String = _attacker_of.get(object_id, "")
		var attack: TurnInputModel.ActionOption = _attack_option(session, attacker)
		if attack == null or _index_of(attack, object_id) < 0:
			problems.append("%s isn't in its attacker's Attack" % [object_id])
	_check.call("list: Attack lists debris and kegs as the validator accepts, enemies first", (
			problems.is_empty() and _placed.size() == ATTACK_ORDER.size()
	), "; ".join(problems))
	h.close()


# Wooden debris broken off the map (the darkness's erosion, a rule that breaks it without an
# action) leaves its attacker's Attack, and no unit lists it.
func _test_broken_gone() -> void:
	var h: TurnInputCases.Harness = _object_harness("broken")
	if h == null:
		return
	var session: CombatSession = h.session
	var object_id: String = _placed[WOODEN]
	var attacker: String = _attacker_of[object_id]
	var before: TurnInputModel.ActionOption = _attack_option(session, attacker)
	var was_listed: bool = before != null and _index_of(before, object_id) >= 0
	var broke: bool = MapObjects.erode(session.engine, session.state, object_id)
	var still: PackedStringArray = []
	for unit_id: String in TurnInputModel.acting_units(session, 0):
		var attack: TurnInputModel.ActionOption = _attack_option(session, unit_id)
		if attack != null and _index_of(attack, object_id) >= 0:
			still.append(unit_id)
	_check.call("broken: a broken debris leaves every Attack list", (
			was_listed and broke and still.is_empty()
	), "listed before %s, broke %s, still listed by %s" % [was_listed, broke, still])
	h.close()


# By device, each object attacked from its attacker's own tile: targeted with its outline, the
# cursor and the HUD's unit view on it; its forecast showing an object's rows (and a keg's blasts
# in TARGET and CONFIRM, its splash on friendly units); then confirmed, every unit ending as the
# forecast said and its damage the exchange's.
func _test_attack_by(device: Device) -> void:
	var tag: String = "attack (%s)" % [DEVICE_NAMES[device]]
	var h: TurnInputCases.Harness = _object_harness(tag)
	if h == null:
		return
	for kind: MapLayout.ObjectKind in ATTACK_ORDER:
		var object_id: String = _placed[kind]
		var name: String = (MapLayout.ObjectKind.find_key(kind) as String).to_lower()
		var attacker: String = _attacker_of[object_id]
		var problems: PackedStringArray = _attack_object(h, device, attacker, object_id)
		_check.call("%s: %s targeted, forecast and resolved as forecast" % [tag, name], (
				problems.is_empty()
		), "; ".join(problems))
	_check.call(tag + ": no attack was rejected", _rejections(h).is_empty(), str(_rejections(h)))
	h.close()


# Debris at LOW_HP and the keg, each attacked: it breaks, the event log says so ("breaks",
# "explodes" for both kegs), the board plays its hit (a keg's splash on every unit in its blasts)
# and its token leaves the board.
func _test_break_feedback() -> void:
	_is_low_hp = true
	var h: TurnInputCases.Harness = _object_harness("break")
	_is_low_hp = false
	if h == null:
		return
	var session: CombatSession = h.session
	var state: CombatState = session.state
	var fired: Array[Array] = []
	var on_played: Callable = func(unit_id: String, kind: StrikeFeedback.Kind) -> void:
		fired.append([unit_id, kind])
	h.view.feedback_played.connect(on_played)
	for kind: MapLayout.ObjectKind in ATTACK_ORDER:
		var object_id: String = _placed[kind]
		var name: String = BattleText.name_of(session, object_id)
		var tile: Vector2i = state.tile_of(object_id)
		var splashed: PackedStringArray = []
		if kind == KEG:
			splashed = _units_in_blasts(state, _kegs_of(object_id))
		var attack: TurnInputModel.ActionOption = _attack_option(
				session, _attacker_of[object_id]
		)
		var at: int = -1 if attack == null else _index_of(attack, object_id)
		if at < 0:
			_check.call("break: %s is a target" % [name], false)
			continue
		fired.clear()
		_send(h, attack.targets[at].command)
		var batch: CombatSession.FactBatch = h.last_batch()
		var lines: PackedStringArray = _log_lines(session, batch)
		var verb: String = "explodes" if kind == KEG else "breaks"
		var expected: PackedStringArray = ["%s at %s %s" % [name, _tile_text(tile), verb]]
		if kind == KEG:
			var chain_name: String = BattleText.name_of(session, _chain_keg)
			var chain_tile: Vector2i = state.map.object(_chain_keg).tile
			expected.append("%s at %s explodes" % [chain_name, _tile_text(chain_tile)])
		var missing: PackedStringArray = []
		for line: String in expected:
			if not lines.has(line):
				missing.append(line)
		var unplayed: PackedStringArray = []
		if not fired.has([object_id, StrikeFeedback.Kind.HIT]):
			unplayed.append("%s's hit" % [object_id])
		for unit_id: String in splashed:
			if not fired.has([unit_id, StrikeFeedback.Kind.SPLASH]):
				unplayed.append("%s's splash" % [unit_id])
		_check.call("break: %s breaks, logged, its hit played, its token gone" % [name], (
				batch != null and not batch.is_rejected()
				and state.map.object(object_id).is_destroyed
				and missing.is_empty() and unplayed.is_empty()
				and h.view.token_of(object_id) == null
				and (kind != KEG or not splashed.is_empty())
		), "log %s, missing %s, not played %s, fired %s" % [lines, missing, unplayed, fired])
	h.view.feedback_played.disconnect(on_played)
	h.close()


# --- Driving the screen --------------------------------------------------------------------


# attacker_id attacks object_id by device from its own tile: selected, Attack picked, the object
# made current and picked (TARGET checked there), the forecast checked (CONFIRM), then confirmed
# and the outcome checked against it. Returns every problem; empty when all held.
func _attack_object(
		h: TurnInputCases.Harness, device: Device, attacker_id: String, object_id: String
) -> PackedStringArray:
	var problems: PackedStringArray = []
	var c: BattleController = h.controller
	var session: CombatSession = h.session
	var state: CombatState = session.state
	if not _open_attack(h, device, attacker_id):
		problems.append("Attack didn't open its targets (stage %d)" % [c.get_stage()])
		return problems
	var list: TargetList = c.get_target_list()
	var index: int = -1 if list == null else list.index_of(object_id)
	if index < 0:
		problems.append("%s isn't a target" % [object_id])
		c.step_back()
		c.step_back()
		return problems
	var is_keg: bool = state.map.object(object_id).kind == KEG
	var no_kegs: Array[String] = []
	var blast: Array[Vector2i] = _blast_tiles(state, _kegs_of(object_id) if is_keg else no_kegs)
	if device != Device.MOUSE:
		for _i: int in list.size():
			if list.current_index() == index:
				break
			_press(device, &"target_next")
		_expect_targeted(h, object_id, problems)
		_expect_drawn(h, blast, "TARGET", problems)
	var picked: String = _pick_target(h, device, object_id)
	if not picked.is_empty():
		problems.append(picked)
		return problems
	var panel: ForecastPanel = h.host.top() as ForecastPanel
	if c.get_stage() != CONFIRM or panel == null or panel.get_model() == null:
		problems.append("the forecast didn't open (stage %d)" % [c.get_stage()])
		return problems
	_expect_targeted(h, object_id, problems)
	_expect_drawn(h, blast, "CONFIRM", problems)
	var model: ForecastViewModel = panel.get_model()
	_expect_object_rows(session, model, object_id, problems)
	if is_keg:
		_expect_splash(state, model, _kegs_of(object_id), blast, problems)
	var predicted: Dictionary[String, String] = {}
	for outcome: CombatForecast.UnitOutcome in model.forecast.units:
		predicted[outcome.unit_id] = _outcome_text(outcome.is_defeated, outcome.hp_after)
	var predicted_hits: PackedInt32Array = []
	var found: CombatForecast.ExchangeForecast = model.forecast as CombatForecast.ExchangeForecast
	for attack: CombatForecast.AttackForecast in found.attacks:
		if attack.defender_id == object_id:
			predicted_hits.append(attack.damage)
	if device == Device.MOUSE:
		_click_control(h, panel.get_confirm_button())
	else:
		_press(device, &"ui_accept")
	BattleViewCases.settle(h.view)
	var batch: CombatSession.FactBatch = h.last_batch()
	if batch == null or batch.is_rejected():
		var reason: String = "no batch" if batch == null else batch.rejected_reason
		problems.append("not resolved: %s" % [reason])
		return problems
	var actual: Dictionary[String, String] = {}
	for unit_id: String in predicted:
		var gone: bool = not state.has_unit(unit_id)
		actual[unit_id] = _outcome_text(gone, 0 if gone else state.get_hp(unit_id))
	if predicted != actual:
		problems.append("predicted %s, after %s" % [predicted, actual])
	var hits: PackedInt32Array = []
	for fact: CombatFact in batch.facts:
		if fact.kind == CombatFact.Kind.HIT_TAKEN and fact.actor_id == object_id:
			hits.append(fact.amount)
	if hits != predicted_hits or hits.is_empty():
		problems.append("hits forecast %s, resolved %s" % [predicted_hits, hits])
	if c.get_stage() != IDLE:
		problems.append("the flow didn't return to IDLE (stage %d)" % [c.get_stage()])
	return problems


# Selects unit_id on its own tile and picks Attack in its menu by device: a click on the tile
# twice and on the row, or accept twice and up / down to the row (the keys when the tile is
# covered, for the mouse). Returns whether TARGET opened on Attack.
func _open_attack(h: TurnInputCases.Harness, device: Device, unit_id: String) -> bool:
	var c: BattleController = h.controller
	var tile: Vector2i = h.session.state.tile_of(unit_id)
	if device == Device.MOUSE and _is_clear(h, tile):
		_click(h, tile)
		_click(h, tile)
	else:
		c.move_cursor(tile)
		var keys: Device = Device.KEYS if device == Device.MOUSE else device
		_press(keys, &"ui_accept")
		_press(keys, &"ui_accept")
	var menu: ActionMenu = h.host.top() as ActionMenu
	if c.get_stage() != ACTION or menu == null:
		return false
	var options: Array[TurnInputModel.ActionOption] = menu.get_options()
	for i: int in options.size():
		if options[i].kind == ATTACK_KIND:
			_pick_row(h, device, menu.get_rows(), i)
			break
	return c.get_stage() == TARGET


# --- Checks ----------------------------------------------------------------------------------


# The object is the current target: its tile has the current outline, white for no side, the
# cursor is on it, and the HUD's unit view and tile view for the cursor's tile show it and its HP.
func _expect_targeted(
		h: TurnInputCases.Harness, object_id: String, problems: PackedStringArray
) -> void:
	var state: CombatState = h.session.state
	var tile: Vector2i = state.tile_of(object_id)
	var marked: bool = false
	for mark: TargetMark in h.view.get_target_marks():
		if mark.tile == tile and mark.is_current and mark.side == NONE_SIDE:
			marked = true
	if not marked:
		problems.append("%s has no current outline" % [object_id])
	var cursor: Vector2i = h.controller.get_cursor_tile()
	var shown: HudViewModel.UnitView = HudViewModel.unit_view(h.session, state.occupant_at(cursor))
	var info: HudViewModel.TileView = HudViewModel.tile_view(h.session, cursor)
	if (
			cursor != tile or shown == null or shown.unit_id != object_id
			or shown.hp != state.get_hp(object_id)
			or info.occupant_name != BattleText.name_of(h.session, object_id)
	):
		problems.append("cursor %s, HUD unit %s, tile info '%s'" % [
			cursor, "none" if shown == null else shown.unit_id, info.occupant_name,
		])


# Every tile of blast is on the attack overlay in stage_name.
func _expect_drawn(
		h: TurnInputCases.Harness,
		blast: Array[Vector2i],
		stage_name: String,
		problems: PackedStringArray
) -> void:
	var drawn: Array[Vector2i] = h.view.get_attack_overlay().shown_tiles()
	var missing: PackedStringArray = []
	for tile: Vector2i in blast:
		if not drawn.has(tile):
			missing.append(str(tile))
	if not missing.is_empty():
		problems.append("%s: the blast's %s not drawn" % [stage_name, ", ".join(missing)])


# An object's exchange rows: Hit 100, no counter (Hit, Crit and Strikes empty for it), no crit,
# no Stance (its cell empty, never Exposed), its DEF and RES in the notes, and its HP before and
# after.
func _expect_object_rows(
		session: CombatSession,
		model: ForecastViewModel,
		object_id: String,
		problems: PackedStringArray
) -> void:
	var none: String = ForecastViewModel.NONE_TEXT
	var sheet: StatSheet = session.stats(object_id)
	var note: String = ForecastViewModel.OBJECT_NOTE % [
		BattleText.name_of(session, object_id),
		sheet.get_int(CombatValue.Key.DEF),
		sheet.get_int(CombatValue.Key.RES),
	]
	var found: CombatForecast.ExchangeForecast = model.forecast as CombatForecast.ExchangeForecast
	var outcome: CombatForecast.UnitOutcome = found.unit(object_id)
	var cells: Dictionary[String, String] = {}
	for label: String in ["Hit", "Crit", "Strikes", "Stance", "HP"]:
		var shown: ForecastViewModel.Row = model.row(label)
		cells[label] = "none" if shown == null else "%s | %s" % [shown.actor, shown.target]
	var held: bool = (
			model.kind == ForecastViewModel.Kind.EXCHANGE
			and found.is_legal and not found.can_counter
			and model.row("Hit").actor == "100%" and model.row("Hit").target == none
			and model.row("Crit").actor == none and model.row("Strikes").target == none
			and model.row("Stance").target == none
			and model.row("HP").target.begins_with("%d → " % [session.state.get_hp(object_id)])
			and outcome != null and outcome.hp_after < outcome.hp_before
			and model.notes.has(note)
	)
	if not held:
		problems.append("rows %s, notes %s (expected '%s')" % [cells, model.notes, note])


# A keg's forecast: its tiles hold every blast tile, and every unit in the blasts flashes its HP
# dropping, the attacker and its friends among them.
func _expect_splash(
		state: CombatState,
		model: ForecastViewModel,
		kegs: Array[String],
		blast: Array[Vector2i],
		problems: PackedStringArray
) -> void:
	for tile: Vector2i in blast:
		if not model.tiles.has(tile):
			problems.append("the forecast's tiles miss %s" % [tile])
	var friends: int = 0
	for unit_id: String in _units_in_blasts(state, kegs):
		var flash: ForecastViewModel.Flash = model.flash_of(unit_id)
		if flash == null or flash.hp_after >= flash.hp_before:
			problems.append("%s in the blast doesn't flash its HP" % [unit_id])
		elif state.side_of(unit_id) == PLAYER:
			friends += 1
	if friends == 0:
		problems.append("no friendly unit flashed the keg's splash")


# --- Fixtures --------------------------------------------------------------------------------


# rune_cases.gd's harness with this file's fixture; null, failing once as label, when the map has
# no room for it.
func _object_harness(label: String) -> TurnInputCases.Harness:
	var h: TurnInputCases.Harness = _harness(true)
	if h == null:
		return null
	if _placed.size() != ATTACK_ORDER.size() or _chain_keg.is_empty():
		_check.call("%s: the fixture's objects are placed" % [label], false, str(_placed))
		h.close()
		return null
	return h


# This file's fixture, in rune_cases.gd's keg chain's place: every player unit healed to full; a
# keg orthogonally next to a melee unit, preferring one whose blasts reach another player unit,
# and a second keg in its blast; wooden then stone debris, each in another unit's reach and out
# of both blasts. Returns the kegs' ids; fills _placed, _chain_keg and _attacker_of.
func _place_keg_chain(h: TurnInputCases.Harness) -> Array[String]:
	_placed.clear()
	_attacker_of.clear()
	_chain_keg = ""
	var session: CombatSession = h.session
	var state: CombatState = session.state
	for unit_id: String in state.units_of(PLAYER):
		state.set_hp(unit_id, session.stats(unit_id).get_int(CombatValue.Key.HP))
	var no_kegs: Array[String] = []
	var keg_pick: Array = _keg_spot(session)
	if keg_pick.is_empty():
		return no_kegs
	var keg_attacker: String = keg_pick[0]
	var keg_tile: Vector2i = keg_pick[1]
	var chain_tile: Vector2i = keg_pick[2]
	var kegs: Array[Vector2i] = [keg_tile, chain_tile]
	var spots: Array[Array] = [[KEG, keg_tile, keg_attacker], [KEG, chain_tile, ""]]
	var used: Dictionary[String, bool] = {keg_attacker: true}
	var taken: Dictionary[Vector2i, bool] = {keg_tile: true, chain_tile: true}
	var debris: Array[MapLayout.ObjectKind] = [WOODEN, STONE]
	for kind: MapLayout.ObjectKind in debris:
		var pick: Array = _debris_spot(session, used, taken, kegs)
		if pick.is_empty():
			return no_kegs
		var attacker: String = pick[0]
		var spot: Vector2i = pick[1]
		used[attacker] = true
		taken[spot] = true
		spots.append([kind, spot, attacker])
	var layout: MapLayout = MapLayout.new()
	for i: int in spots.size():
		var spot_tile: Vector2i = spots[i][1]
		var spot_kind: MapLayout.ObjectKind = spots[i][0]
		var marker: MapLayout.Marker = layout.add_marker(
				MapLayout.MarkerKind.OBJECT_SPOT, spot_tile, spot_kind
		)
		marker.index = OBJECT_INDEX + i
		marker.container_index = -1
	MapObjects.place_objects(session.engine, state, layout, session.ids)
	var kegs_placed: Array[String] = []
	for i: int in spots.size():
		var object_id: String = InstanceIdAllocator.object_id(OBJECT_INDEX + i)
		var kind: MapLayout.ObjectKind = spots[i][0]
		var attacker: String = spots[i][2]
		if kind == KEG:
			kegs_placed.append(object_id)
		if attacker.is_empty():
			_chain_keg = object_id
			continue
		_placed[kind] = object_id
		_attacker_of[object_id] = attacker
		if _is_low_hp and kind != KEG:
			state.set_hp(object_id, LOW_HP)
	return kegs_placed


# [attacker, keg tile, chain keg tile]: a free tile orthogonally next to a seat-0 unit that
# attacks at range 1, and a free tile next to it, the pair whose blasts reach the most other
# player units; empty when there is none.
func _keg_spot(session: CombatSession) -> Array:
	var state: CombatState = session.state
	var best: Array = []
	var best_friends: int = -1
	for unit_id: String in _attackers(session):
		var reach: Vector2i = _reach_of(session, unit_id)
		if reach.x > 1 or reach.y < 1:
			continue
		var tile: Vector2i = state.tile_of(unit_id)
		for keg: Vector2i in MapObjects.KEG_BLAST.tiles(tile):
			if state.grid.distance(tile, keg) != 1 or not _is_free(state, keg):
				continue
			for chain: Vector2i in MapObjects.KEG_BLAST.tiles(keg):
				if chain == keg or chain == tile or not _is_free(state, chain):
					continue
				var friends: int = 0
				for other: String in state.units_of(PLAYER):
					var at: Vector2i = state.tile_of(other)
					var is_hit: bool = (
							MapObjects.KEG_BLAST.covers(keg, at)
							or MapObjects.KEG_BLAST.covers(chain, at)
					)
					if other != unit_id and is_hit:
						friends += 1
				if friends > best_friends:
					best_friends = friends
					best = [unit_id, keg, chain]
	return best


# [attacker, tile]: the first free tile in reach of a seat-0 attacker not in used, not taken and
# out of every keg's blast; empty when there is none.
func _debris_spot(
		session: CombatSession,
		used: Dictionary[String, bool],
		taken: Dictionary[Vector2i, bool],
		kegs: Array[Vector2i]
) -> Array:
	var state: CombatState = session.state
	for unit_id: String in _attackers(session):
		if used.has(unit_id):
			continue
		var reach: Vector2i = _reach_of(session, unit_id)
		var tile: Vector2i = state.tile_of(unit_id)
		for dy: int in range(-reach.y, reach.y + 1):
			for dx: int in range(-reach.y, reach.y + 1):
				var spot: Vector2i = tile + Vector2i(dx, dy)
				var distance: int = state.grid.distance(tile, spot)
				if distance < reach.x or distance > reach.y or taken.has(spot):
					continue
				if not _is_free(state, spot):
					continue
				var is_blasted: bool = false
				for keg: Vector2i in kegs:
					is_blasted = is_blasted or MapObjects.KEG_BLAST.covers(keg, spot)
				if not is_blasted:
					return [unit_id, spot]
	return []


# Seat 0's units holding a weapon that attacks, in state order.
func _attackers(session: CombatSession) -> PackedStringArray:
	var found: PackedStringArray = []
	var state: CombatState = session.state
	for unit_id: String in state.units_of(PLAYER):
		var held: CombatState.WeaponStats = state.equipped_weapon(unit_id)
		if state.seat_of(unit_id) != 0 or held == null:
			continue
		if held.is_staff() and held.staff != CombatState.WeaponStats.Staff.ATTACK:
			continue
		found.append(unit_id)
	return found


# The kegs a blast from keg_id reaches in this fixture: it, then its chain keg.
func _kegs_of(keg_id: String) -> Array[String]:
	var kegs: Array[String] = [keg_id, _chain_keg]
	return kegs


# unit_id's range with the weapon in hand, as (shortest, longest).
static func _reach_of(session: CombatSession, unit_id: String) -> Vector2i:
	var sheet: StatSheet = session.stats(unit_id)
	return Vector2i(
			sheet.get_int(CombatValue.Key.RANGE_MIN), sheet.get_int(CombatValue.Key.RANGE_MAX)
	)


# --- Reading --------------------------------------------------------------------------------


# unit_id's Attack on its own tile; null when it has none.
static func _attack_option(
		session: CombatSession, unit_id: String
) -> TurnInputModel.ActionOption:
	if unit_id.is_empty():
		return null
	for option: TurnInputModel.ActionOption in TurnInputModel.actions_at(session, unit_id, []):
		if option.kind == ATTACK_KIND:
			return option
	return null


# target_id's place among option's targets; -1 for none.
static func _index_of(option: TurnInputModel.ActionOption, target_id: String) -> int:
	for i: int in option.targets.size():
		if option.targets[i].target_id == target_id:
			return i
	return -1


# Every command option lists, as "target|weapon", in list order; empty for null.
static func _listed_attacks(option: TurnInputModel.ActionOption) -> PackedStringArray:
	var keys: PackedStringArray = []
	if option == null:
		return keys
	for target: TurnInputModel.TargetOption in option.targets:
		for command: Command in target.commands:
			keys.append(_attack_key(command as UnitTurnCommand))
	return keys


# Every attack of unit_id from its own tile the validator accepts, on every other unit and object,
# with each weapon it holds, in _listed_attacks's order: enemies in state order, then objects in
# spot order, the weapon in hand first.
static func _accepted_attacks(session: CombatSession, unit_id: String) -> PackedStringArray:
	var state: CombatState = session.state
	var unit: CombatUnitState = state.unit(unit_id)
	var weapons: PackedStringArray = [""]
	if not unit.stowed_weapon_id.is_empty() and unit.stowed_weapon_id != unit.equipped_weapon_id:
		weapons.append(unit.stowed_weapon_id)
	var defenders: PackedStringArray = []
	var objects: Array[MapState.ObjectState] = []
	for other: String in state.unit_ids():
		if other == unit_id:
			continue
		if state.side_of(other) == NONE_SIDE:
			objects.append(state.map.object(other))
		else:
			defenders.append(other)
	objects.sort_custom(func(a: MapState.ObjectState, b: MapState.ObjectState) -> bool:
		return a.index < b.index
	)
	var ordered: PackedStringArray = []
	for enemy_id: String in state.units_of(ENEMY):
		if defenders.has(enemy_id):
			ordered.append(enemy_id)
	for other: String in defenders:
		if not ordered.has(other):
			ordered.append(other)
	for placed: MapState.ObjectState in objects:
		ordered.append(placed.id)
	var keys: PackedStringArray = []
	for defender_id: String in ordered:
		for weapon_id: String in weapons:
			var command: UnitTurnCommand = UnitTurnCommand.new(
					0, unit_id, UnitTurnCommand.Action.ATTACK, defender_id
			)
			command.weapon_id = weapon_id
			if command.validate(session).is_empty():
				keys.append(_attack_key(command))
	return keys


static func _attack_key(command: UnitTurnCommand) -> String:
	return "none" if command == null else "%s|%s" % [command.target_id, command.weapon_id]


# The on-map tiles the blasts of kegs cover, each once, in row-major order.
static func _blast_tiles(state: CombatState, kegs: Array[String]) -> Array[Vector2i]:
	var covered: Dictionary[Vector2i, bool] = {}
	for keg_id: String in kegs:
		var keg: MapState.ObjectState = state.map.object(keg_id)
		if keg == null:
			continue
		for tile: Vector2i in MapObjects.KEG_BLAST.tiles(keg.tile):
			if state.grid.step(tile, Vector2i.ZERO) != CombatFact.NO_TILE:
				covered[tile] = true
	var tiles: Array[Vector2i] = []
	tiles.assign(covered.keys())
	tiles.sort_custom(MapLayout.is_before)
	return tiles


# The units of either side standing in the blasts of kegs now, in state order.
static func _units_in_blasts(state: CombatState, kegs: Array[String]) -> PackedStringArray:
	var found: PackedStringArray = []
	var blast: Array[Vector2i] = _blast_tiles(state, kegs)
	for unit_id: String in state.unit_ids():
		if state.side_of(unit_id) != NONE_SIDE and blast.has(state.tile_of(unit_id)):
			found.append(unit_id)
	return found


# The event log's lines for batch's facts, in order.
static func _log_lines(
		session: CombatSession, batch: CombatSession.FactBatch
) -> PackedStringArray:
	var lines: PackedStringArray = []
	if batch == null:
		return lines
	var writer: EventLogWriter = EventLogWriter.new(session)
	for fact: CombatFact in batch.facts:
		for entry: EventLogWriter.Entry in writer.write(fact):
			lines.append(entry.text())
	return lines


static func _tile_text(tile: Vector2i) -> String:
	return "(%d, %d)" % [tile.x, tile.y]
