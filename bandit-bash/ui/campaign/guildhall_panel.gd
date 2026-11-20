# ==============================================================================
# Bandit Bash
# Copyright (c) 2026 Derc Development
# Licensed under the MIT License. See LICENSE.
#
# File:     guildhall_panel.gd
# Author:
# Created:  November 20, 2026
# Modified: November 20, 2026
# ==============================================================================

class_name GuildhallPanel
extends Control
## One Guildhall purchase, asked over the screen ([enum Step]): a recruit's price, or with a full
## army the unit it replaces and then the hand-over ([HandOverRow] per item, with Best fit); a
## rune's price, or with every slot full the rune it discards; or which unit's prefix to re-roll,
## each priced. Every choice shows its gold; one [Guildhall] refuses is greyed out and says why.
##
## It emits [signal recruit_chosen], [signal rune_chosen] or [signal reroll_chosen] once settled;
## the screen sends the command, which checks it again, and a rejection shows here
## ([method show_problem]). The re-roll step stays open for another ([method refresh]). Choices
## are one column a pad moves up and down; the dimmed backdrop takes every click outside it.
# ============================================================
# INPUT MAP SETUP:
#   "ui_cancel" -> Esc; pad B [Circle], Menu [Options]   (read in _input while shown: steps back
#                  one step, or closes from the first; taken first, so the pause menu doesn't
#                  open over the panel)
#   "ui_up" / "ui_down" / "ui_left" / "ui_right" / "ui_accept"  (not read here: the GUI moves
#                  focus within the column and along a hand-over row, and presses the focused
#                  choice, by key, d-pad, stick or A [Cross])
#   Mouse: a click on a choice presses it; Back steps back as ui_cancel does.
# ============================================================

## The player settled a recruit: replacing [param replaced_id] (empty: none) with its items
## placed by [param hand_over] (item id to [enum Guildhall.HandOver]).
signal recruit_chosen(replaced_id: String, hand_over: Dictionary)

## The player settled a rune, discarding the one in [param discard_slot]
## ([constant Guildhall.NO_SLOT]: none).
signal rune_chosen(discard_slot: int)

## The player chose to re-roll the prefix of the unit [param unit_id].
signal reroll_chosen(unit_id: String)

## The player backed out of the first step: nothing is bought.
signal cancelled()

# --- Purchase step (meaningful only while the panel is shown, after open_*()) -----------------
# RECRUIT:   a recruit's price into an army with room. Back closes (cancelled).
# REPLACE:   a full army's units to replace (the commander greyed out). Back closes.
# HAND_OVER: the leaving unit's items and the recruit's, each placed, Best fit and the price.
#            Back returns to REPLACE.
# RUNE:      a rune's price, or with every slot full the rune each choice discards. Back closes.
# REROLL:    the living units, each with its re-roll price; stays open after one. Back closes.
# RECRUIT, HAND_OVER and RUNE end by emitting their signal; the panel stays shown until the
# screen closes it, so a rejection can be shown on it. ui_cancel acts as Back in every step.
## Which question the panel asks.
enum Step {
	## A recruit's price, the army having room.
	RECRUIT = 0,
	## Which unit a recruit replaces.
	REPLACE = 1,
	## Where each handed-over item goes.
	HAND_OVER = 2,
	## A rune's price, and the slot it empties when every slot is full.
	RUNE = 3,
	## Which unit's prefix to re-roll.
	REROLL = 4,
}

const _ROW_SCENE: PackedScene = preload("res://ui/campaign/hand_over_row.tscn")

var _run: CampaignRunState = null
var _seat: int = 0
var _index: int = -1
var _catalog: EffectCatalog.Index = null
var _ids: InstanceIdAllocator = null
var _joining: RecruitOffer = null
var _replaced_id: String = ""
var _hand_over: Dictionary[String, int] = {}
var _step: Step = Step.RECRUIT

@onready var _title_label: Label = %Title
@onready var _details_label: Label = %Details
@onready var _question_label: Label = %Question
@onready var _rows: VBoxContainer = %Rows
@onready var _choices: VBoxContainer = %Choices
@onready var _problem_label: Label = %Problem


func _ready() -> void:
	visible = false


func _input(event: InputEvent) -> void:
	if not visible or not event.is_action_pressed(&"ui_cancel"):
		return
	get_viewport().set_input_as_handled()
	step_back()


## Opens the panel for stock entry [param index] of [param run]'s Guildhall, bought by seat
## [param seat]; [param ids] names its units, [param catalog] is their content.
func open_entry(
		run: CampaignRunState,
		seat: int,
		index: int,
		catalog: EffectCatalog.Index,
		ids: InstanceIdAllocator
) -> void:
	_bind(run, seat, catalog, ids)
	_index = index
	var entry: GuildhallStock.Entry = GuildhallStock.pending(run).entries[index]
	visible = true
	if not entry.is_recruit():
		_title_label.text = "Buy %s" % [GuildhallModel.rune_name(entry.definition_id, catalog)]
		_details_label.text = GuildhallModel.rune_details(entry.definition_id, catalog)
		_show_rune()
		return
	_joining = Guildhall.recruit_for(run, seat, index, catalog)
	_title_label.text = "Recruit %s" % [RecruitOfferCard.title_of(_joining.unit, catalog)]
	_details_label.text = "Joins at level %d, with %s." % [
		_joining.unit.level, _brought(_joining),
	]
	if Guildhall.is_army_full(run, seat, catalog):
		_show_replace()
	else:
		_show_recruit()


## Opens the panel at the re-roll step for seat [param seat] of [param run].
func open_reroll(
		run: CampaignRunState, seat: int, catalog: EffectCatalog.Index, ids: InstanceIdAllocator
) -> void:
	_bind(run, seat, catalog, ids)
	_title_label.text = "Re-roll a prefix"
	_details_label.text = (
			"A new prefix, never the same one. Each paid re-roll here costs half the first more."
	)
	visible = true
	_show_reroll()


## Shows the step again from the run as it is now, such as after a re-roll.
func refresh() -> void:
	if not visible:
		return
	match _step:
		Step.REROLL:
			_show_reroll()
		Step.HAND_OVER:
			_show_hand_over()


## Hides the panel.
func close() -> void:
	visible = false


## Shows [param problem] under the choices, such as the reason a command was rejected.
func show_problem(problem: String) -> void:
	_problem_label.text = problem


## The step shown.
func get_step() -> Step:
	return _step


## The choices of the step shown, in order, Back last.
func get_choice_buttons() -> Array[Button]:
	var buttons: Array[Button] = []
	for child: Node in _choices.get_children():
		if child is Button and not child.is_queued_for_deletion():
			buttons.append(child as Button)
	return buttons


## The hand-over rows shown at [constant Step.HAND_OVER], in item order.
func get_rows() -> Array[HandOverRow]:
	var rows: Array[HandOverRow] = []
	for child: Node in _rows.get_children():
		if child is HandOverRow and not child.is_queued_for_deletion():
			rows.append(child as HandOverRow)
	return rows


## The hand-over chosen so far: item id to [enum Guildhall.HandOver].
func get_hand_over() -> Dictionary[String, int]:
	return _hand_over.duplicate()


## Goes back one step, or closes the panel from the first ([signal cancelled]).
func step_back() -> void:
	if _step == Step.HAND_OVER:
		_show_replace()
		return
	close()
	cancelled.emit()


## Chooses the unit [param unit_id] for the recruit to replace, as pressing its choice does: the
## hand-over opens at Best fit.
func choose_replaced(unit_id: String) -> void:
	_replaced_id = unit_id
	_hand_over = Guildhall.best_fit(_run, _seat, _index, unit_id, _catalog)
	_show_hand_over()


## Places the item [param item_id] at [param place] ([enum Guildhall.HandOver]), as pressing its
## row's button does.
func choose_place(item_id: String, place: int) -> void:
	_hand_over[item_id] = place
	_show_hand_over()


func _bind(
		run: CampaignRunState, seat: int, catalog: EffectCatalog.Index, ids: InstanceIdAllocator
) -> void:
	_run = run
	_seat = seat
	_catalog = catalog
	_ids = ids
	_index = -1
	_joining = null
	_replaced_id = ""
	_hand_over = {}


func _show_recruit() -> void:
	_step = Step.RECRUIT
	_clear()
	_question_label.text = "It joins your army."
	var none: Dictionary[String, int] = {}
	var problem: String = Guildhall.recruit_problem(_run, _seat, _index, "", none, _catalog)
	_add_choice(
			_with_problem("Recruit for %s" % [_price_text()], problem),
			problem.is_empty(), _on_recruit_confirmed
	)
	_finish_column()


func _show_replace() -> void:
	_step = Step.REPLACE
	_clear()
	var seat_run: SeatRun = _run.seat_run(_seat)
	_question_label.text = "Your army is full (%d of %d). Which unit leaves?" % [
		seat_run.army.size(), RunOperations.max_army_size(seat_run, _catalog),
	]
	for unit: UnitInstance in seat_run.army:
		var is_commander: bool = unit.instance_id == seat_run.commander_id
		var text: String = "Replace %s" % [_unit_name(unit.instance_id)]
		if is_commander:
			text += " - can't: the commander never leaves the army"
		_add_choice(text, not is_commander, choose_replaced.bind(unit.instance_id))
	_finish_column()


func _show_hand_over() -> void:
	_step = Step.HAND_OVER
	var focused: Control = get_viewport().gui_get_focus_owner() if is_inside_tree() else null
	var focused_path: String = "" if focused == null else str(_rows.get_path_to(focused))
	_clear()
	var seat_run: SeatRun = _run.seat_run(_seat)
	var owner_name: String = _unit_name(_replaced_id)
	_question_label.text = "%s leaves. Where does each item go?" % [owner_name]
	var items: PackedStringArray = Guildhall.hand_over_items(_run, _seat, _replaced_id, _joining)
	var capacity: int = ItemPlacement.convoy_capacity(seat_run, _catalog)
	var to_convoy: int = 0
	for item_id: String in items:
		if _place_of(item_id) == Guildhall.HandOver.CONVOY:
			to_convoy += 1
	for item_id: String in items:
		var row: HandOverRow = _ROW_SCENE.instantiate()
		_rows.add_child(row)
		var refusals: Dictionary[int, String] = {}
		var place: int = _place_of(item_id)
		if not _joining.items.has(item_id) and not _recruit_can_use(item_id):
			refusals[Guildhall.HandOver.RECRUIT] = "the recruit can't use it"
		if place != Guildhall.HandOver.CONVOY and seat_run.convoy.size() + to_convoy >= capacity:
			refusals[Guildhall.HandOver.CONVOY] = "the convoy is full (%d of %d)" % [
				seat_run.convoy.size() + to_convoy, capacity,
			]
		row.show_item(
				item_id,
				GuildhallModel.hand_over_item_name(
						item_id, seat_run, _joining, owner_name, _catalog
				),
				place,
				refusals
		)
		row.place_chosen.connect(choose_place)
	_add_choice("Best fit", true, choose_replaced.bind(_replaced_id))
	var problem: String = Guildhall.recruit_problem(
			_run, _seat, _index, _replaced_id, _hand_over, _catalog
	)
	_add_choice(
			_with_problem("Recruit for %s" % [_price_text()], problem),
			problem.is_empty(), _on_recruit_confirmed
	)
	_finish_column(false)
	var restored: Control = (
			null if focused_path.is_empty() else _rows.get_node_or_null(focused_path) as Control
	)
	if restored != null and restored.focus_mode != Control.FOCUS_NONE:
		restored.grab_focus()
	else:
		_first_focus()


func _show_rune() -> void:
	_step = Step.RUNE
	_clear()
	var seat_run: SeatRun = _run.seat_run(_seat)
	var price: String = GuildhallModel.entry_price_text(_run, _seat, _index, _catalog)
	if Guildhall.empty_rune_slot(seat_run) >= 0:
		_question_label.text = "It goes in an empty rune slot."
		_add_rune_choice("Buy for %s" % [price], Guildhall.NO_SLOT)
	else:
		_question_label.text = "Every rune slot is full. Which rune do you discard?"
		for slot: int in seat_run.rune_slots.size():
			var held: SeatRun.RuneSlot = seat_run.rune_slots[slot]
			_add_rune_choice("Discard %s, buy for %s" % [
				GuildhallModel.rune_name(held.definition_id, _catalog), price,
			], slot)
	_finish_column()


func _show_reroll() -> void:
	_step = Step.REROLL
	_clear()
	var seat_run: SeatRun = _run.seat_run(_seat)
	var free: int = Guildhall.free_rerolls_left(_run, _seat, _catalog)
	_question_label.text = (
			"Whose prefix?" if free == 0 else "Whose prefix? %d free re-roll(s) left." % [free]
	)
	for unit: UnitInstance in seat_run.army:
		var problem: String = Guildhall.reroll_problem(_run, _seat, unit.instance_id, _catalog)
		var paid: int = Guildhall.reroll_price(_run, _seat, unit.instance_id, _catalog)
		var text: String = RecruitOfferCard.title_of(unit, _catalog)
		if unit.instance_id != seat_run.commander_id:
			text += ": %s" % ["free" if paid == 0 else "%d gold" % [paid]]
		_add_choice(_with_problem(text, problem), problem.is_empty(), _on_reroll_pressed.bind(
				unit.instance_id
		))
	_finish_column()


func _add_rune_choice(text: String, slot: int) -> void:
	var problem: String = Guildhall.rune_problem(_run, _seat, _index, slot, _catalog)
	_add_choice(_with_problem(text, problem), problem.is_empty(), _on_rune_chosen.bind(slot))


func _clear() -> void:
	_problem_label.text = ""
	for container: Node in [_rows, _choices]:
		for child: Node in container.get_children():
			container.remove_child(child)
			child.queue_free()


func _add_choice(text: String, is_enabled: bool, chosen: Callable) -> void:
	var button: Button = Button.new()
	button.text = text
	button.disabled = not is_enabled
	button.focus_mode = Control.FOCUS_ALL if is_enabled else Control.FOCUS_NONE
	button.alignment = HORIZONTAL_ALIGNMENT_LEFT
	button.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	button.pressed.connect(chosen)
	_choices.add_child(button)


# Adds Back and links the enabled choices as one column that stops at its ends (left and right
# stay put while no rows show); focuses the first when focus_first.
func _finish_column(focus_first: bool = true) -> void:
	_add_choice("Back", true, step_back)
	var column: Array[Button] = []
	for button: Button in get_choice_buttons():
		if not button.disabled:
			column.append(button)
	var has_rows: bool = _rows.get_child_count() > 0
	for i: int in column.size():
		var button: Button = column[i]
		var self_path: NodePath = button.get_path_to(button)
		if i > 0 or not has_rows:
			button.focus_neighbor_top = button.get_path_to(column[maxi(i - 1, 0)])
		button.focus_neighbor_bottom = button.get_path_to(column[mini(i + 1, column.size() - 1)])
		button.focus_neighbor_left = self_path
		button.focus_neighbor_right = self_path
	if focus_first:
		column[0].grab_focus()


# The first enabled place of the first row, else the first enabled choice.
func _first_focus() -> void:
	for row: HandOverRow in get_rows():
		var button: Button = row.button_for(row.place)
		if button != null and button.focus_mode != Control.FOCUS_NONE:
			button.grab_focus()
			return
	for button: Button in get_choice_buttons():
		if not button.disabled:
			button.grab_focus()
			return


func _place_of(item_id: String) -> int:
	return _hand_over.get(
			item_id,
			Guildhall.HandOver.RECRUIT if _joining.items.has(item_id) else Guildhall.HandOver.CONVOY
	)


# Whether the recruit can use the leaving unit's item item_id: a weapon of a type it wields.
func _recruit_can_use(item_id: String) -> bool:
	var item: ItemInstance = _run.seat_run(_seat).items.get(item_id, null)
	var definition: ItemDefinition = null if item == null else _catalog.item(item.definition_id)
	var weapon: WeaponDefinition = definition as WeaponDefinition
	return weapon == null or ItemPlacement.weapon_types_of(_joining.unit, _catalog).has(
			weapon.weapon_type
	)


func _price_text() -> String:
	return GuildhallModel.entry_price_text(_run, _seat, _index, _catalog)


func _brought(offer: RecruitOffer) -> String:
	var weapon: ItemInstance = offer.items.get(offer.unit.weapon_id, null)
	if weapon == null:
		return "no weapon"
	return CombatResultsModel.item_name(_catalog.item(weapon.definition_id), weapon.definition_id)


func _unit_name(unit_id: String) -> String:
	return CombatResultsModel.unit_name(_ids, _run.seat_run(_seat), unit_id, _catalog)


static func _with_problem(text: String, problem: String) -> String:
	return text if problem.is_empty() else "%s - can't: %s" % [text, problem]


func _on_recruit_confirmed() -> void:
	recruit_chosen.emit(_replaced_id, _hand_over.duplicate())


func _on_rune_chosen(slot: int) -> void:
	rune_chosen.emit(slot)


func _on_reroll_pressed(unit_id: String) -> void:
	reroll_chosen.emit(unit_id)
