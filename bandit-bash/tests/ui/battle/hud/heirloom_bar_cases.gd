# ==============================================================================
# Bandit Bash
# Copyright (c) 2026 Derc Development
# Licensed under the MIT License. See LICENSE.
#
# File:     heirloom_bar_cases.gd
# Author:
# Created:  November 19, 2026
# Modified: November 22, 2026
# ==============================================================================

extends RefCounted
## The heirloom bar's cases for tests/ui/display/run_all.gd (ui-lift.md, Heirloom bar): an M1
## battle begun for a run holding the Commander Heirloom, War Ledger (its campaign count saved at
## 7), two copies of Breaker's Maul, Burglar's Roll and the Shaken Footing curse, drawn by the HUD
## through the campaign bridge. The copies show once each in gain order, the curse after the
## divider; the copied-in count shows; a COUNTER_CHANGED moves an icon only as it plays; the ready
## look at period - 1 and its reset after firing, with the pulse and the event log line; charges
## spent and a first-only curse used take the spent look; the tooltip's text and its keywords'
## tooltips; the fallback mark and
## every heirloom and curse having art; another seat sees none; campaign screens' view from the
## saved copies; focus by key and by pad, in battle (HEIRLOOM_BAR) and on a campaign screen.

# The suite that runs this file; tests/case_files.gd finds it by this line.
const SUITE: String = "ui/display"

const BattleViewCases = preload("res://tests/ui/battle/board/battle_view_cases.gd")
const TurnInputCases = preload("res://tests/ui/battle/input/turn_input_cases.gd")
const PackCatalog = preload("res://tests/enemies/pack_catalog.gd")

const M1_DEFINITION: String = "res://maps/standard/m1_greybox.tres"
const VIEW_SCENE: PackedScene = preload("res://ui/battle/board/battle_view.tscn")
const HUD_SCENE: PackedScene = preload("res://ui/battle/hud/battle_hud.tscn")
const BAR_SCENE: PackedScene = preload("res://ui/common/heirlooms/heirloom_bar.tscn")
const ICON_SCENE: PackedScene = preload("res://ui/common/heirlooms/heirloom_icon.tscn")
const PANEL_HOST_SCENE: PackedScene = preload("res://ui/battle/menus/panel_host.tscn")
const TURN_BAR_SCENE: PackedScene = preload("res://ui/battle/hud/turn_bar.tscn")
const SWAP_WINDOW_SCENE: PackedScene = preload("res://ui/battle/menus/swap_window.tscn")
const MESSAGE_SCENE: PackedScene = preload("res://ui/battle/hud/battle_message.tscn")
const ACTION_MENU_SCENE: PackedScene = preload("res://ui/battle/menus/action_menu.tscn")
const TARGET_PICKER_SCENE: PackedScene = preload("res://ui/battle/input/target_picker.tscn")
const CONFIRM_SCENE: PackedScene = preload("res://ui/battle/menus/confirm_dialog.tscn")

# Any fixed seed; the other UI cases use the same one.
const SEED: int = 0x0C0FFEE

# The staged heirlooms after the faction's own, in gain order (the curse among them).
const STAGED: PackedStringArray = [
	"war_ledger", "breakers_maul", "breakers_maul", "shaken_footing", "burglars_roll",
]

# War Ledger's effect, its saved campaign count, and its period ("every 10th").
const LEDGER_EFFECT: String = "double_damage"
const LEDGER_COUNT: int = 7
const LEDGER_PERIOD: int = 10

# Breaker's Maul's period ("every 5th Hit dealt this combat").
const MAUL_PERIOD: int = 5

const COMBAT: EffectTerms.Lane = EffectTerms.Lane.COMBAT

var _check: Callable
var _root: Node = null
var _catalog: EffectCatalog.Index = null
var _map: CombatMapDefinition = null


## [param check]: called as check(case_name: String, passed: bool, detail: String).
## [param root]: the root viewport, where the rigs are added and input is pushed.
func _init(check: Callable, root: Node) -> void:
	_check = check
	_root = root
	_catalog = EffectCatalog.index()


## Runs every case.
func run() -> void:
	_map = load(M1_DEFINITION) as CombatMapDefinition
	if _map == null:
		_check.call("heirlooms: the M1 map definition loads", false, M1_DEFINITION)
		return
	_test_battle_bar()
	_test_art()
	_test_run_view()
	_test_battle_focus()
	_test_screen_focus()


# The staged battle's bar, through the HUD: order, the copied-in count, facts as they play, the
# ready, fired, spent and used looks, the tooltip, and another seat's empty bar.
func _test_battle_bar() -> void:
	var rig: Rig = _rig()
	if rig == null:
		return
	var bar: HeirloomBar = rig.hud.get_heirloom_bar()
	var icons: Array[HeirloomIcon] = bar.get_icons()
	var shown: PackedStringArray = []
	for icon: HeirloomIcon in icons:
		var view: HeirloomViewModel = icon.get_view()
		shown.append("%s:%d%s" % [view.heirloom_id, view.copy, " curse" if view.is_curse else ""])
	# The run's ids, a copy counted per repeat, the curses moved after the heirlooms.
	var expected: PackedStringArray = []
	var curses: PackedStringArray = []
	var copies: Dictionary[String, int] = {}
	for heirloom_id: String in rig.heirloom_ids:
		var copy_index: int = copies.get(heirloom_id, 0)
		copies[heirloom_id] = copy_index + 1
		if _catalog.heirloom(heirloom_id) is CurseDefinition:
			curses.append("%s:%d curse" % [heirloom_id, copy_index])
		else:
			expected.append("%s:%d" % [heirloom_id, copy_index])
	expected.append_array(curses)
	_check.call("bar: each copy once, heirlooms in gain order, then the divider and the curse", (
			bar.visible and shown == expected and bar.is_divider_shown()
	), "%s vs %s, divider %s" % [shown, expected, bar.is_divider_shown()])

	var ledger: HeirloomIcon = _icon(bar, "war_ledger", 0)
	var footer: String = ledger.get_view().footer_text()
	_check.call("bar: War Ledger shows its saved campaign count, copied into the battle (7 / 10)", (
			ledger.get_badge_text() == str(LEDGER_COUNT)
			and footer.contains("%d / %d this run" % [LEDGER_COUNT, LEDGER_PERIOD])
			and not ledger.is_ready_look()
			and is_equal_approx(ledger.get_shown_alpha(), ledger.rest_alpha)
	), "badge %s, footer %s, alpha %.2f" % [
		ledger.get_badge_text(), footer, ledger.get_shown_alpha(),
	])

	# A counter changed in state shows only when its fact plays.
	var maul: HeirloomIcon = _icon(bar, "breakers_maul", 0)
	var maul_two: HeirloomIcon = _icon(bar, "breakers_maul", 1)
	var instance: EffectInstance = rig.h.session.engine.get_instance(
			maul.get_view().counter_instance_id
	)
	instance.set_counter(COMBAT, MAUL_PERIOD - 2)
	rig.h.session.engine.counter_changed(instance, COMBAT)
	var before_play: String = maul.get_badge_text()
	rig.h.session.bus.play(rig.h.session.engine.fact_log[-1])
	_check.call("bar: COUNTER_CHANGED moves the icon's count as it plays, not before", (
			before_play == "0"
			and maul.get_badge_text() == str(MAUL_PERIOD - 2)
			and maul_two.get_badge_text() == "0"
	), "before %s, after %s, other copy %s" % [
		before_play, maul.get_badge_text(), maul_two.get_badge_text(),
	])

	instance.set_counter(COMBAT, MAUL_PERIOD - 1)
	rig.h.session.engine.counter_changed(instance, COMBAT)
	rig.h.session.bus.play(rig.h.session.engine.fact_log[-1])
	footer = maul.get_view().footer_text()
	_check.call("ready: at period - 1 the icon is lit, ready, saying what fires next", (
			maul.is_ready_look()
			and is_equal_approx(maul.get_shown_alpha(), 1.0)
			and footer.contains("%d / %d this combat" % [MAUL_PERIOD - 1, MAUL_PERIOD])
			and footer.contains("Ready: the next time one of your units lands a hit, the target")
			and not maul_two.is_ready_look()
	), "ready %s, alpha %.2f, footer %s" % [
		maul.is_ready_look(), maul.get_shown_alpha(), footer,
	])

	# It fires: the count starts over, the icon pulses, the event log says so.
	instance.set_counter(COMBAT, 0)
	rig.h.session.engine.counter_changed(instance, COMBAT)
	rig.h.session.bus.play(rig.h.session.engine.fact_log[-1])
	var fired: CombatFact = CombatFact.new(CombatFact.Kind.EFFECT_ACTIVATED)
	fired.actor_id = instance.owner.subject_id()
	fired.source_effect_id = instance.instance_id
	rig.h.session.bus.play(fired)
	var log_texts: PackedStringArray = rig.hud.get_event_log().get_texts()
	var has_line: bool = false
	for text: String in log_texts:
		has_line = has_line or text.contains("The army's Breaker's Maul activates")
	_check.call("fired: the count resets, the ready look goes, it pulses, with its log line", (
			maul.get_badge_text() == "0"
			and not maul.is_ready_look()
			and maul.is_pulsing()
			and not maul_two.is_pulsing()
			and has_line
	), "badge %s, ready %s, pulsing %s, log %s" % [
		maul.get_badge_text(), maul.is_ready_look(), maul.is_pulsing(), log_texts,
	])

	# Charges: Burglar's Roll's use, spent in state, shows at the next settle.
	var roll: HeirloomIcon = _icon(bar, "burglars_roll", 0)
	var had: String = roll.get_badge_text()
	var was_spent: bool = roll.is_spent_look()
	var roll_instance: EffectInstance = rig.h.session.engine.get_instance(
			roll.get_view().instance_ids[0]
	)
	roll_instance.spend_charge()
	rig.hud.refresh()
	footer = roll.get_view().footer_text()
	_check.call("uses: a charge limit shows the uses left; spent, the icon takes the spent look", (
			had == "1"
			and not was_spent
			and roll.get_badge_text() == "0"
			and roll.is_spent_look()
			and is_equal_approx(roll.get_shown_alpha(), roll.spent_alpha)
			and roll.get_symbol() != null
			and footer.contains("No uses left this combat")
	), "had %s, now %s, spent %s, alpha %.2f, footer %s" % [
		had, roll.get_badge_text(), roll.is_spent_look(), roll.get_shown_alpha(), footer,
	])

	# A first-only curse (First Phase Start this combat) is used once it fires.
	var curse: HeirloomIcon = _icon(bar, "shaken_footing", 0)
	var curse_instance: EffectInstance = rig.h.session.engine.get_instance(
			curse.get_view().counter_instance_id
	)
	var was_used: bool = curse.is_spent_look()
	curse_instance.set_counter(COMBAT, 1)
	rig.h.session.engine.counter_changed(curse_instance, COMBAT)
	rig.h.session.bus.play(rig.h.session.engine.fact_log[-1])
	_check.call("first-only: no count shows; once fired it is spent this combat", (
			curse.get_badge_text().is_empty()
			and not was_used
			and curse.is_spent_look()
			and curse.get_view().footer_text().contains("Used this combat")
	), "badge '%s', before %s, after %s" % [
		curse.get_badge_text(), was_used, curse.is_spent_look(),
	])

	# The tooltip, pointed at by the mouse.
	ledger.mouse_entered.emit()
	var texts: PackedStringArray = bar.get_tip().get_texts()
	var definition: HeirloomDefinition = _catalog.heirloom("war_ledger")
	var tip_ok: bool = (
			bar.get_tip().visible
			and texts[0] == "War Ledger"
			and texts[1] == "\n".join(definition.describe())
			and texts[2] == "Uncommon heirloom\n%d / %d this run" % [
				LEDGER_COUNT, LEDGER_PERIOD,
			]
			and is_equal_approx(ledger.get_shown_alpha(), 1.0)
	)
	# Its keywords' tooltips beside it, one per distinct keyword, gone with it.
	var body: EffectText = bar.get_tip().get_body()
	var keyword_ids: PackedStringArray = []
	for tooltip: KeywordTooltip in body.get_shown_tooltips():
		keyword_ids.append(tooltip.keyword_id)
	var keywords_ok: bool = (
			not body.get_keyword_ids().is_empty() and keyword_ids == body.get_keyword_ids()
	)
	ledger.mouse_exited.emit()
	_check.call("tooltip: name, the effect text used everywhere, tier and count; full on hover", (
			tip_ok and not bar.get_tip().visible
	), str(texts))
	_check.call("tooltip: one keyword tooltip per distinct keyword, hidden with the tooltip", (
			keywords_ok and body.get_shown_tooltips().is_empty()
	), "%s of %s" % [keyword_ids, body.get_keyword_ids()])

	_check.call("co-op: another seat's bar holds none of this seat's heirlooms", (
			HeirloomViewModel.for_battle(rig.h.run, rig.h.session, 1, _catalog).is_empty()
	))
	rig.close()


# Every heirloom and curse has its placeholder art; an icon without one shows the generic mark.
func _test_art() -> void:
	var missing: PackedStringArray = []
	var count: int = 0
	for id: String in EffectCatalog.ids():
		var definition: HeirloomDefinition = EffectCatalog.definition(id) as HeirloomDefinition
		if definition == null:
			continue
		count += 1
		if definition.icon == null:
			missing.append(id)
	_check.call("art: every heirloom and curse (%d) has an icon" % [count], (
			missing.is_empty() and count > 0
	), ", ".join(missing))

	var icon: HeirloomIcon = ICON_SCENE.instantiate()
	_root.add_child(icon)
	var view: HeirloomViewModel = HeirloomViewModel.new()
	view.display_name = "Nameless"
	icon.show_view(view)
	var fallback: Texture2D = icon.get_symbol()
	view.icon = _catalog.heirloom("war_ledger").icon
	icon.show_view(view)
	_check.call("art: a missing icon falls back to the one generic mark", (
			fallback != null and fallback == icon.fallback_icon and icon.get_symbol() == view.icon
	), "%s" % [fallback])
	icon.free()


# Campaign screens' view from the saved copies: only campaign-lane state shows.
func _test_run_view() -> void:
	var seat_run: SeatRun = SeatRun.new(0)
	var ledger: SeatRun.OwnedHeirloom = seat_run.add_heirloom("war_ledger")
	ledger.counters[LEDGER_EFFECT] = LEDGER_COUNT
	seat_run.add_heirloom("breakers_maul")
	seat_run.add_heirloom("burglars_roll")
	seat_run.add_heirloom("haunted")
	var views: Array[HeirloomViewModel] = HeirloomViewModel.for_run(seat_run, _catalog)
	var badges: PackedStringArray = []
	for view: HeirloomViewModel in views:
		badges.append("%s=%s" % [view.heirloom_id, view.badge_text()])
	_check.call("campaign: the saved campaign count shows; combat-lane counts and uses don't", (
			views.size() == 4
			and views[0].badge_text() == str(LEDGER_COUNT)
			and views[0].has_counter
			and views[1].badge_text().is_empty()
			and views[2].badge_text().is_empty()
			and views[3].is_curse
	), ", ".join(badges))

	var bar: HeirloomBar = BAR_SCENE.instantiate()
	_root.add_child(bar)
	bar.show_views(views)
	_check.call("campaign: the bar draws them, heirlooms then the curse", (
			bar.get_icons().size() == 4
			and bar.get_icons()[3].get_view().is_curse
			and bar.is_divider_shown()
			and bar.get_icons()[0].get_badge_text() == str(LEDGER_COUNT)
	))
	bar.show_views([])
	_check.call("campaign: with nothing held the bar hides", not bar.visible)
	bar.free()


# HEIRLOOM_BAR by key and by pad: in, across the icons (wrapping), out by Back and by the action.
func _test_battle_focus() -> void:
	var rig: Rig = _rig()
	if rig == null:
		return
	var h: TurnInputCases.Harness = rig.h
	var bar: HeirloomBar = rig.hud.get_heirloom_bar()
	h.controller.request_start()
	BattleViewCases.settle(h.view)
	var viewport: Viewport = _root.get_viewport()
	var icons: Array[HeirloomIcon] = bar.get_icons()
	var start: BattleController.Stage = h.controller.get_stage()
	_send_action(&"heirloom_bar_focus", true)
	_send_action(&"heirloom_bar_focus", false)
	var entered: bool = (
			h.controller.get_stage() == BattleController.Stage.HEIRLOOM_BAR
			and viewport.gui_get_focus_owner() == icons[0]
			and bar.get_tip().visible
	)
	_send_action(&"ui_right", true)
	_send_action(&"ui_right", false)
	var right: bool = viewport.gui_get_focus_owner() == icons[1]
	_send_action(&"ui_left", true)
	_send_action(&"ui_left", false)
	_send_action(&"ui_left", true)
	_send_action(&"ui_left", false)
	var wrapped: bool = viewport.gui_get_focus_owner() == icons[-1]
	_send_action(&"ui_cancel", true)
	_send_action(&"ui_cancel", false)
	var left_by_back: bool = (
			h.controller.get_stage() == BattleController.Stage.IDLE
			and viewport.gui_get_focus_owner() == null
			and not bar.is_navigable()
	)
	_check.call("battle (keys): H focuses the bar; Right and Left move, wrapping; Back leaves", (
			start == BattleController.Stage.IDLE and entered and right and wrapped and left_by_back
	), "start %d, entered %s, right %s, wrapped %s, back %s" % [
		start, entered, right, wrapped, left_by_back,
	])

	_push_axis(JOY_AXIS_RIGHT_X, -1.0)
	_push_axis(JOY_AXIS_RIGHT_X, 0.0)
	var by_stick: bool = h.controller.get_stage() == BattleController.Stage.HEIRLOOM_BAR
	_push_button(JOY_BUTTON_DPAD_RIGHT)
	var pad_moved: bool = viewport.gui_get_focus_owner() == icons[0]
	_push_button(JOY_BUTTON_B)
	var by_b: bool = h.controller.get_stage() == BattleController.Stage.IDLE
	_push_axis(JOY_AXIS_RIGHT_X, -1.0)
	_push_axis(JOY_AXIS_RIGHT_X, 0.0)
	var again: bool = h.controller.get_stage() == BattleController.Stage.HEIRLOOM_BAR
	_push_axis(JOY_AXIS_RIGHT_X, -1.0)
	_push_axis(JOY_AXIS_RIGHT_X, 0.0)
	var closed: bool = h.controller.get_stage() == BattleController.Stage.IDLE
	_check.call("battle (pad): RS left focuses its last icon; B leaves; RS left again closes", (
			by_stick and pad_moved and by_b and again and closed
	), "stick %s, d-pad %s, B %s, again %s, closed %s" % [
		by_stick, pad_moved, by_b, again, closed,
	])
	rig.close()


# A campaign screen's bar (handles_focus_input): H and RS left take focus from the screen's button
# and give it back on Back, B or the action again, telling the screen to switch its hints.
func _test_screen_focus() -> void:
	var holder: Control = Control.new()
	_root.add_child(holder)
	var button: Button = Button.new()
	holder.add_child(button)
	var bar: HeirloomBar = BAR_SCENE.instantiate()
	bar.handles_focus_input = true
	holder.add_child(bar)
	var seat_run: SeatRun = SeatRun.new(0)
	seat_run.add_heirloom("war_ledger")
	seat_run.add_heirloom("iron_heart")
	bar.show_views(HeirloomViewModel.for_run(seat_run, _catalog))
	var signals: PackedStringArray = []
	bar.navigation_started.connect(func() -> void: signals.append("started"))
	bar.navigation_ended.connect(func() -> void: signals.append("ended"))
	var viewport: Viewport = _root.get_viewport()
	button.grab_focus()
	_press_key(KEY_H)
	var by_key: bool = viewport.gui_get_focus_owner() == bar.get_icons()[0]
	_press_key(KEY_RIGHT)
	var moved: bool = viewport.gui_get_focus_owner() == bar.get_icons()[1]
	_press_key(KEY_ESCAPE)
	var back: bool = viewport.gui_get_focus_owner() == button and not bar.is_navigable()
	_check.call("screen (keys): H focuses the bar, Right moves, Esc gives focus back", (
			by_key and moved and back
	), "key %s, moved %s, back %s" % [by_key, moved, back])

	_push_axis(JOY_AXIS_RIGHT_X, -1.0)
	var by_stick: bool = viewport.gui_get_focus_owner() == bar.get_icons()[1]
	_push_axis(JOY_AXIS_RIGHT_X, -0.9)
	var held: bool = bar.is_navigable()
	_push_axis(JOY_AXIS_RIGHT_X, 0.0)
	_push_button(JOY_BUTTON_B)
	var by_b: bool = viewport.gui_get_focus_owner() == button
	_push_axis(JOY_AXIS_RIGHT_X, -1.0)
	_push_axis(JOY_AXIS_RIGHT_X, 0.0)
	_push_axis(JOY_AXIS_RIGHT_X, -1.0)
	_push_axis(JOY_AXIS_RIGHT_X, 0.0)
	var toggled: bool = viewport.gui_get_focus_owner() == button
	_check.call("screen (pad): RS left focuses its last icon once a push; B, RS left go back", (
			by_stick and held and by_b and toggled
			and signals == PackedStringArray([
				"started", "ended", "started", "ended", "started", "ended",
			])
	), "stick %s, held %s, B %s, toggled %s, signals %s" % [
		by_stick, held, by_b, toggled, signals,
	])
	holder.free()


# --- Rig and input ---------------------------------------------------------------------------


# The M1 battle for a run holding the faction's heirlooms and STAGED, War Ledger's campaign count
# saved at LEDGER_COUNT; the HUD drawing it with the controller; null, reported, when it can't.
func _rig() -> Rig:
	var h: TurnInputCases.Harness = TurnInputCases.Harness.new()
	h.run = CampaignSession.new(CampaignData.Mode.SOLO, SEED, PackedInt32Array([0]))
	var state: CampaignRunState = CampaignRunState.new()
	var seat_run: SeatRun = SeatRun.new(0)
	state.seats[0] = seat_run
	h.run.run = state
	var mercenary: StartingArmy = StartingArmy.build(_catalog, "mercenary", h.run.ids)
	for heirloom_id: String in mercenary.heirloom_ids:
		seat_run.add_heirloom(heirloom_id)
	for heirloom_id: String in STAGED:
		var owned: SeatRun.OwnedHeirloom = seat_run.add_heirloom(heirloom_id)
		if heirloom_id == "war_ledger":
			owned.counters[LEDGER_EFFECT] = LEDGER_COUNT
	var army: CampaignSession.Army = CampaignSession.Army.new()
	army.unit_instances = mercenary.units
	army.item_instances = mercenary.items
	army.heirloom_ids = seat_run.heirloom_ids()
	var request: CampaignSession.BattleRequest = CampaignSession.BattleRequest.new()
	request.floor_number = BattleViewCases.FLOOR
	request.node = BattleViewCases.NODE
	request.pool = [_map]
	request.catalog = PackCatalog.with_only(_catalog, "m1_pack")
	request.armies[0] = army
	h.battle = h.run.begin_battle(request)
	if h.battle == null:
		_check.call("heirlooms: the staged M1 battle begins", false, "begin_battle gave no battle")
		h.run.close()
		return null
	h.session = h.battle.get_session(0)
	h.view = VIEW_SCENE.instantiate()
	_root.add_child(h.view)
	h.hud = CanvasLayer.new()
	_root.add_child(h.hud)
	var rig: Rig = Rig.new()
	rig.h = h
	rig.heirloom_ids = seat_run.heirloom_ids()
	rig.hud = HUD_SCENE.instantiate()
	h.hud.add_child(rig.hud)
	h.bar = TURN_BAR_SCENE.instantiate()
	h.swap = SWAP_WINDOW_SCENE.instantiate()
	h.host = PANEL_HOST_SCENE.instantiate()
	h.message = MESSAGE_SCENE.instantiate()
	for widget: Control in [h.bar, h.swap, h.host, h.message]:
		h.hud.add_child(widget)
	h.controller = BattleController.new()
	h.controller.action_menu_scene = ACTION_MENU_SCENE
	h.controller.target_picker_scene = TARGET_PICKER_SCENE
	h.controller.confirm_dialog_scene = CONFIRM_SCENE
	h.controller.view = h.view
	h.controller.panel_host = h.host
	h.controller.turn_bar = h.bar
	h.controller.swap_window = h.swap
	h.controller.message = h.message
	h.controller.heirloom_bar = rig.hud.get_heirloom_bar()
	_root.add_child(h.controller)
	h.view.map_area = rig.hud.get_map_area()
	h.view.bind(h.session)
	h.controller.bind(h.battle, h.session, 0)
	rig.hud.bind(h.session, h.controller, h.view)
	rig.hud.bind_heirlooms(h.run, 0)
	return rig


# The bar's icon for copy copy_index of heirloom_id; null for none.
func _icon(bar: HeirloomBar, heirloom_id: String, copy_index: int) -> HeirloomIcon:
	for icon: HeirloomIcon in bar.get_icons():
		var view: HeirloomViewModel = icon.get_view()
		if view.heirloom_id == heirloom_id and view.copy == copy_index:
			return icon
	return null


func _send_action(action: StringName, is_down: bool) -> void:
	var event: InputEventAction = InputEventAction.new()
	event.action = action
	event.pressed = is_down
	_root.get_viewport().push_input(event, true)


func _press_key(key: Key) -> void:
	for is_down: bool in [true, false]:
		var event: InputEventKey = InputEventKey.new()
		event.keycode = key
		event.physical_keycode = key
		event.pressed = is_down
		_root.get_viewport().push_input(event, true)


func _push_button(button: JoyButton) -> void:
	for is_down: bool in [true, false]:
		var event: InputEventJoypadButton = InputEventJoypadButton.new()
		event.button_index = button
		event.pressed = is_down
		_root.get_viewport().push_input(event, true)


func _push_axis(axis: JoyAxis, value: float) -> void:
	var event: InputEventJoypadMotion = InputEventJoypadMotion.new()
	event.axis = axis
	event.axis_value = value
	_root.get_viewport().push_input(event, true)


## The harness with the HUD and the staged heirlooms.
class Rig:
	extends RefCounted

	## The board, widgets and controller (turn_input_cases.gd).
	var h: TurnInputCases.Harness = null
	## The HUD, whose heirloom bar is under test.
	var hud: BattleHud = null
	## The run's heirloom and curse ids in gain order, a copy once each.
	var heirloom_ids: PackedStringArray = []

	## Frees the nodes and closes the run.
	func close() -> void:
		h.close()
