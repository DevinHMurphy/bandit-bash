# Plan: The victory sequence (P15 UL5)
**Date:** November 19, 2026
**Status:** Approved November 19, 2026 (user: "Proceed"); building on `feature/UL5`

## Problem

A won combat shows its results all at once on a separate screen, and the board is gone before
they appear:

- **Separate screen, all at once.** `ui/battle/battle_screen.gd:163` (`_end_battle`) saves the
  battle's end, then changes scene to `COMBAT_RESULTS`. `ui/campaign/combat_results_screen.tscn`
  lays grades, level-ups, the item pick and XP in one scroll (`:47-79`), with no stages, no
  animation, and nothing over the board (ui-lift.md, Victory sequence).
- **A pad can't scroll it.** Its `ScrollContainer` (`combat_results_screen.tscn:47`) holds
  unfocusable XP and level-up rows, so focus-follow never moves it. With a larger army (Muster Roll)
  the rows run off screen (design-items.md, P07 row).
- **No per-unit performance numbers survive the battle.** `BattleTally`
  (`scripts/campaign/battle_tally.gd:27`) counts XP actions (hits, defeats, heals, Block given,
  non-combat). Heals are counts, not HP. Nothing counts damage dealt, damage taken or HP healed.
  The tally lives only in the combat block (`battle_tally_section.gd:25`, dropped at battle end).
  The saved combat report holds only `grades`, `xp` and `level_ups`
  (`campaign_run_state.gd:492`).
- **The XP bar has no starting point to fill from.** The model keeps each unit's XP and level
  after the combat (`combat_results_model.gd:94`), not before.
- **The reward list isn't generic.** The item pick is hard-wired into the screen
  (`combat_results_screen.gd:51`, `:178-202`), so the key combat's heirloom and runes (RN7) have
  nowhere to join.

## Open Questions

None. The eight estimate questions and the plan's two (fallen units in the recap; the `economy`
version) were answered "as recommended" on November 19, 2026 (user), and are recorded as
[P15 questions 1 and 2](decisions/P15-ui-lift.md).

## Scope

**In scope**
- The staged victory overlay (Grade, Recap, Rewards) over the board after a won solo combat.
- The same overlay over a dark backdrop when a saved run resumes at a combat's results.
- Per-unit performance numbers counted in battle, saved mid-battle, and written into the combat
  report.
- A generic reward row and picker, with the item pick as its first reward.
- Keyboard, mouse and pad from the start, including scrolling a long recap with a pad.
- The `tests/ui/campaign` Results walk, a new `tests/ui/victory` suite, and captures at 1280×720,
  1920×1080 and 1280×800.

**Out of scope**
- The loss screen (UL7).
- The key combat's heirloom and the runes as rewards (RN7). Only the row interface is built for
  them.
- Co-op. The overlay serves solo runs, as Results does.
- Any change to what is granted or when, and to the save order.
- The ui-lift.md, design-items.md and orchestrator updates. They are left for the orchestrator
  session at merge, and listed in the summary.

## Design Basis

- **ui-lift.md, Victory sequence;** the UL5 row of Steps; Decisions 1 (Godot_FE's art, else one
  placeholder style), 2 (target sizes) and 4 (gold shows as collected in the Grade stage, not as a
  reward row).
- **ui-style.md:**
  - the overlay is `bg` at 85%;
  - the ribbon header goes on each stage;
  - `PrimaryButton` for Continue and Leave;
  - the row looks for the reward rows;
  - 32-unit icons in reward rows;
  - stage changes are 250 ms tweens and panels 150 ms;
  - skippable motion follows playback speed and skip;
  - the text floor is 14.
- **game-vision.md:**
  - Run structure: grades, +25% each for under par and no losses; the reward table, with a
    Standard combat paying gold and a pick of 1 of 3 items or skip;
  - Units, Experience: shared XP, a personal bonus capped at 15, and the Standout's +5 on top of
    the cap, named "on the results screen";
  - level-ups happen after combat, all together on the results screen.
- **master-ideation.md:** nothing on the results or victory screens (searched for "results" and
  "victory"). The vision governs.
- **save-system.md:** the economy row (`pending_offers.combat`); versioning (bump on a shape change
  and write `migrate`); the combat block's sections.

## Legacy Behavior (ports from Godot_FE only)

| Godot_FE file | Behavior | Keep / Change / Drop | Reason |
|---------------|----------|----------------------|--------|
| `ui/combat/unit_experience_bar/unit_experience_bar.gd` | A bar fills from the old XP to the new, linearly, over √(gain)/6 s after a 0.2 s delay, then holds 0.3 s; the number counts up with it | Keep the timings, scaled by playback speed | The only basis for fill pacing |
| same | A tick sound per XP point | Drop | Audio is out of scope (ui-lift.md) |
| `ui/combat/reward_panel/reward_panel.gd` | Each reward is a button; taking one frees it and focuses the next; with none left the panel closes | Keep the row-leaves-the-list behavior. Change the close: Leave goes on, asking first while rewards are left | The vision's Rewards stage |
| same | Gold and Bonus Exp are clickable rewards, with A–D grades | Change | Gold is already collected (decision 4); the grades are the vision's two |
| `ui/combat/combat_ui.gd:425-439` | One unit's XP bar at a time, in its own pop-up | Change: every unit's bar in one recap list, filling in roster order | The vision's Recap stage |

**Tuning values carried over** (all from `Godot_FE/ui/combat/unit_experience_bar/unit_experience_bar.gd`):
fill time √(XP gained) / 6 s (`:63`), delay 0.2 s (`:44`), hold 0.3 s (`:66`).

## Approach

### The sequence

The overlay is one scene, `ui/campaign/victory/victory_overlay.tscn` (`VictoryOverlay`, a
`CanvasLayer` above the HUD). It holds:

- a full-screen `bg` backdrop at 85%, which fades in over 250 ms;
- a centred column;
- one stage at a time, each changing over a 250 ms tween;
- a footer with the status line and the primary button;
- its own `ScreenHints`, `ControlHintBar` and `InputDeviceAdapter`.

Every look comes from the project theme. New looks become theme types, so the theme scan stays
green.

**Its states** (the state block goes above the enum):

| State | What shows | Continue / Leave |
|-------|------------|------------------|
| GRADE | The ribbon ("Victory", or "Boss defeated"); a row per grade, earned or not (in words, not colour alone), each with the gold it added; base gold; the flat extra gold when above 0; "N gold collected" and the gold now held | Continue → RECAP |
| RECAP_FILLING | A `UnitRecapRow` per unit: the standing units in roster order (with XP), then the fallen (question 1). Bars fill one after another | Continue or skip ends every fill at once |
| RECAP_LEVEL_UPS | A `LevelUpCard` over the recap per level-up, in the order reached: name, the level reached, each gain | Continue → next card |
| RECAP_DONE | The full recap | Continue → REWARDS |
| REWARDS | A `RewardRow` per reward not yet taken, then Leave ("End run" after the Boss) | A row → PICKING; Leave → CONFIRM_LEAVE while rewards are left, else on |
| PICKING | The row's `RewardPicker` as a modal | Resolved → REWARDS, the row gone; cancelled → REWARDS |
| CONFIRM_LEAVE | `LeaveConfirmDialog`: "Leave without taking: Item pick?" | Yes → skip each open reward, then leave; No → REWARDS |
| LEAVING | Input stops | — |

**Leave sends the same commands as today:**
- **With rewards left (Yes):** each open reward's own skip, which for the item pick is
  `ItemPickCommand(seat, SKIP)`, then `LeaveNodeCommand`.
- **After the Boss:** `CampaignService.end_won_run()`, then `RESULTS`.

What is granted, and when, is unchanged. Each command goes through
`CampaignService.submit_command`, which saves. A rejection shows its reason and changes nothing,
as today.

**Pacing** (the overlay's `playback_speed` and `fast_forward_speed` exports):
- Bar fill, delay and hold are divided by the speed, times `fast_forward_speed` while
  `fast_forward` is held.
- `skip_playback` ends the animation running.
- Stage and panel tweens are not scaled (ui-style.md fixes them at 250 and 150 ms).
- On the battle screen the overlay copies `BattleView.playback_speed` and `fast_forward_speed`.
- On the resume host it keeps its own, which default to BattleView's (1.0 and its
  fast-forward speed).

**Input** (no new action):
- **Moving:** `ui_up` and `ui_down` move focus. The recap rows take focus, so their
  `ScrollContainer` (`follow_focus`) scrolls with a pad, and the mouse wheel works as normal.
- **Buttons:** `ui_accept` presses the focused Continue, row or button. `ui_cancel` backs out of a
  picker or the dialog, else opens the host's pause menu, as today.
- **Playback:** `fast_forward` (F / RT) and `skip_playback` (X / LT), as in battle.
- **Hint contexts:** GRADE, RECAP, REWARDS, PICK, PLACE, CONFIRM, BOSS.

### Hosting

- **After a win.** In `battle_screen.gd:_end_battle`, once `CampaignService.end_battle()` has
  saved a won solo combat and `RunScreen.of(run)` is `COMBAT_RESULTS`, the screen:
  - hides the HUD;
  - adds the overlay over the unbound board, which keeps its last frame;
  - stays on `GAMEPLAY`.

  That's about 15 lines in `battle_screen.gd`; UL3 is told what changed. Every other case routes as
  today.
- **Pause menu.** Save & Quit there calls `SaveService.save_checkpoint()` with no battle in
  progress: the same campaign checkpoint Results saves today (`pause_menu.gd:165`).
- **On a resume.** The loading gate routes to `COMBAT_RESULTS` as today.
  `combat_results_screen.tscn` keeps its path and its `Screen` value, but becomes the resume host:
  - a `bg` backdrop;
  - the overlay;
  - the pause menu.
- **Where a resume opens.** On REWARDS when any reward is already taken, else on GRADE with the
  bars filling again. This is read from the saved run, so nothing new is saved.
- **Rejected:** routing every win to `COMBAT_RESULTS` with a picture of the board. It isn't "the
  board stays", and the battle's nodes are freed by the scene change.

### Reward rows

A reward is shown by one interface, so later rewards add a class and a picker, with no change to
the overlay:

- **`VictoryReward`** (RefCounted), the base:
  - members `title`, `detail` and `icon` (a `Texture2D`; null shows the placeholder mark);
  - `is_taken(seat_run)`, read from the saved run;
  - `skip_command(seat)`, the command Leave sends for an open reward;
  - `picker_scene`.
- **`RewardPicker`** (Control), the base for every picker:
  - `open(reward, seat)`;
  - signals `resolved(note: String)` and `cancelled()`;
  - each picker submits its own commands.
- **`VictoryRewards.build(model)`** lists the rewards from the saved run. Today that's one
  `ItemPickReward`, while the pick is pending and not resolved.
- **`ItemRewardPicker`** (`item_reward_picker.tscn`) wraps the existing `ItemPickPanel` (offer
  cards and Skip) and `PlacementPanel` in a modal. A take with its placement, or Skip, resolves
  the pick, and the row leaves. The outcome note ("Took X." or "Skipped.") shows on the status
  line.

### The recap's numbers

A new pure observer, **`BattleStats`** (`scripts/campaign/battle_stats.gd`), sits beside
`BattleTally`. `CampaignSession._on_session_fact_recorded` feeds it.

**What it counts, per player unit:**

| Number | Counted from |
|--------|--------------|
| Kills | `DEFEATED_AN_ENEMY` on an enemy |
| Damage dealt | `DAMAGE_DEALT`'s amount on an enemy, Block and HP |
| Damage taken | `DAMAGE_TAKEN`'s amount, every source, plus `DARKNESS_DAMAGE_TAKEN`'s, which is HP only |
| HP healed | `HEALED_AN_ALLY`'s amount, overhealing included, as the tally counts heals |

- **Darkness damage isn't counted twice:** the darkness records its own fact
  (`darkness.gd:299`), never a `DAMAGE_TAKEN`.
- **Separate from the tally on purpose:** `BattleTally` stays "XP-earning actions", and its saved
  shape (`battle_tally_section.gd`) is untouched.
- **Where it goes:**
  - it's reset at Begin and saved mid-battle;
  - `BattleResult` copies it as `stats`;
  - `CampaignRunState._reward_seat` writes the seat's units into the combat report under `stats`;
  - `CombatReport` reads it, with a missing key meaning no numbers ("—").
- **The Standout** comes from the report's `xp` award, as today.

**The XP bar's start** is worked out on the fly: XP before = XP now + (level-ups reached ×
`xp_per_level`) − XP gained. There's no level cap and the rest carries over, so it's exact
(`level_up.gd:115-118`). `CombatResultsModel.XpLine` gains `xp_before`, `level_before` and
`stats`.

### What happens to the old screen's parts

- **Reused:** `ItemPickPanel`, `ItemOfferCard`, `PlacementPanel` and `RunHeader`.
- **Kept and extended:** `CombatResultsModel`.
- **Removed:** `GradesPanel`, `XpPanel`, `XpRow` and `LevelUpPanel`, with their `.uid` files. They
  are used only by `combat_results_screen.tscn`, and the stage scenes replace them.

## Save Impact

| Block | Key | Version | Per player | Change |
|-------|-----|---------|------------|--------|
| COMBAT | `battle_stats` (new) | 1 | No | `{"units": {"unit:57": {"kills": 1, "damage_dealt": 14, "damage_taken": 6, "healed": 0}}}`. Registered after `battle_grants`, as `BattleTallySection`'s partner (like `grants`), so one attach, detach and `load_into` covers all three. Empty outside a battle; a combat file without it resumes with zeros. |
| CAMPAIGN | `economy` | 1 → 2 (P15 question 2) | Yes | `pending_offers.combat` gains `stats`: per unit id, the four numbers above. `migrate` from 1 changes nothing: a version 1 report has no `stats`, and the recap shows "—". `RunSaveSections` gains a per-section version; the other five stay at 1. |

- **Unchanged:** `battle_tally`, `battle_grants`, `run_flow` and the save order. Rewards are
  rolled once, before the save at battle end; Leave clears `pending_offers` as today.
- **Not saved:** the overlay's stage. The resume rule above reads it from the saved run.
- **save-system.md:** the economy row, the combat-block table and the version list are updated in
  step V1.

## Work Breakdown

1. **V1 — Performance numbers** 🔴
   - **Files:** `scripts/campaign/battle_stats.gd` (new); `battle_tally_section.gd` (the
     `stats` partner); `campaign_session.gd` (feed, reset, `BattleResult.stats`, copied in
     `collect_battle`); `campaign_service.gd` (register the section); `campaign_run_state.gd`
     (report `stats`, `CombatReport.stats`); `run_save_sections.gd` (per-section version, economy
     2, `migrate`); `docs/design/save-system.md`.
   - **Tests:** in `tests/campaign` (`battle_bridge_cases.gd`, `reward_cases.gd`) and `tests/save`.
     They cover counting each fact kind, a resume keeping the counts, the report round trip, and a
     version 1 economy loading with no stats.
2. **V2 — Models** 🟢
   - **Files:** `combat_results_model.gd` (`xp_before`, `level_before`, `stats`, fallen units);
     `ui/campaign/victory/victory_reward.gd`, `item_pick_reward.gd` and `victory_rewards.gd`
     (new).
   - **Tests:** the XP-before arithmetic over 0, 1 and 2 level-ups; the reward list before and
     after the take.
3. **V3 — The elements** 🟡
   - **Files:** in `ui/campaign/victory/`, each `.tscn` with its `.gd`: `xp_bar`,
     `unit_recap_row`, `level_up_card`, `victory_grade_stage`, `victory_recap_stage`,
     `reward_row`, `victory_rewards_stage`, `reward_picker.gd` (base), `item_reward_picker`,
     `leave_confirm_dialog`, `victory_overlay`. Theme types added to `ui/theme/game_theme.tres`
     where a look is new.
   - **Tests:** a new suite, `tests/ui/victory/`, with `SUITE_DESCRIPTION` and grouped timing. It
     covers stage order, fill timing scaled by speed, skip ending every fill, level-up cards in
     order, a taken row leaving, Leave asking only with rewards left, the Boss's End run, pad
     focus scrolling a long recap (8 units), and each device.
4. **V4 — Hosts and old parts** 🟡
   - **Files:** `battle_screen.gd` (the win hook); `combat_results_screen.gd` and `.tscn` (the
     resume host, `get_overlay()`); the four old panels removed; the Results walk in
     `tests/ui/campaign/run_all.gd` rewritten (every stage, each device, a quit and Continue at
     each stage); `tools/capture_screens.gd` (each stage and a resumed sequence).
   - **Verification:** the full runner, and captures at 1280×720, 1920×1080 and 1280×800, saved
     outside the repo.

Each step is committed on `feature/UL5` on its own.

## Breaking Changes

| Kind | Old | New | Migration |
|------|-----|-----|-----------|
| Public methods | `combat_results_screen.gd` `get_model()`, `get_pick_panel()`, `get_placement_panel()`, `get_continue_button()`, `get_status_text()` | `get_overlay()`; the same getters on `VictoryOverlay` | Tests and `capture_screens.gd` updated in V4 |
| Classes removed | `GradesPanel`, `XpPanel`, `XpRow`, `LevelUpPanel` | The stage scenes | Used only by the Results scene |
| Save format | `economy` version 1; the combat block without `battle_stats` | `economy` version 2 with `pending_offers.combat.stats`; `battle_stats` version 1 | `migrate` from 1 is a no-op; a missing `battle_stats` resumes with zeros |
| Public members added | — | `BattleResult.stats`, `CampaignSession.stats`, `CombatReport.stats`, `XpLine.xp_before`, `XpLine.level_before`, `XpLine.stats`, the new classes | — |

## Verification

- `sh bandit-bash/tools/run_tests.sh`, all suites green, with the report path in the summary.
- `--check-only` on every changed `.gd`. Scripts that use autoloads are covered by their suites.
- The `tests/ui/theme` scene scan is green, so no look is set outside the theme.
- Captures with `tools/capture_screens.gd` of GRADE, RECAP (filling and done, plus a level-up
  card), REWARDS, the item picker, the leave dialog, and a resumed sequence over the backdrop, each
  at 1280×720, 1920×1080 and 1280×800. They're saved outside the repo and the path is listed.
- No performance claims.

## Rollback

Each step is its own commit on `feature/UL5`; revert from V4 back.

- **Reverting V4** alone restores the Results screen. V1–V3 are additive.
- **Reverting V1** after saves were written at economy version 2: those saves are refused by the
  older build ("a newer version is refused"). They are test saves only until merge.
