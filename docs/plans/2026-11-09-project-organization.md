# Plan: Project organization

**Status:** **Approved** November 9, 2026 (user). O1 and O2 are the orchestrator's; O3 and O4 go to build agents. Orchestrator ID **P14**

## Problem

The project costs too much context and is hard for a person to find their way around.

- A build agent must read about 50 KB of standing rules before it edits code, then whole plans.
- The orchestrator was 100 KB, over half of it change log. A third of the plans' bytes were answered questions.
- A UI element's scene and script sit in two separate flat folders of about 60 files each.
- Four test suites keep all their cases in one `run_all.gd`, up to 3,383 lines. A full run takes about 10 minutes.

## Open Questions

None open. The six scoping questions were answered as recommended on November 9, 2026; their answers are the Approach below.

## Scope

**In:** the docs layout, the standing rules, the UI's folders, the test layout and the test runner.

**Out:** gameplay, saves, the game logic's folders (`scripts/`), and `data/`, `assets/` and `maps/`. Splitting large source files (O5) is deferred.

## Design Basis

None: no gameplay changes. `.claude/rules/gdscript.md` and `CLAUDE.md` change in O2, at the user's request.

## Approach

- **Docs:** the orchestrator is a dashboard; its history and reference tables live in `orchestrator/`. Answered questions move verbatim to `decisions/`, keeping their numbers, so the code's citations still resolve.
- **No change log:** commit messages record each merge. The old log is archived.
- **One screenful per table cell:** a question too long for a short row becomes a heading with bullets.
- **Standards:** a short core everyone reads, and topic files read only when the task needs them.
- **Comments, from now on:** code states the rule itself and doesn't cite plan or question numbers. Existing comments change only when their file is next touched.
- **UI:** a scene and its script sit side by side in `ui/`, grouped by feature. Only the UI moves, because scripts barely depend on paths and the 150 or so logic scripts gain little from moving.

### Target layout (O3)

| New folder | Contents, from `scripts/ui/`, `scripts/screens/`, `scenes/` |
|---|---|
| `ui/theme/` | `battle_theme` |
| `ui/common/` | `nav_button`, `pause_menu`, `save_indicator` |
| `ui/debug/` | `save_debug_panel` |
| `ui/screens/` | `boot`, `start_screen`, `main_menu`, `lobby_screen`, `loading_gate`, `new_run_screen`, `save_select_screen`, `options_screen`, `setting_toggle`, `results_screen` |
| `ui/battle/` | `gameplay`, `battle_screen`, `battle_controller`, `battle_panel`, `battle_text` |
| `ui/battle/board/` | `battle_view`, `board_view_model`, `camera_rig`, `tile_cursor`, `tile_info`, `tile_overlay`, `path_preview`, `move_preview`, `move_preview_marks`, `darkness_overlay`, and the overlays `attack`, `danger`, `danger_support`, `enemy_range`, `enemy_support`, `move`, `support` |
| `ui/battle/hud/` | `battle_hud`, `hud_view_model`, `turn_bar`, `turn_counter`, `darkness_counter`, `phase_banner`, `battle_message`, `control_hint_bar`, `control_glyph_table`, `fact_log`, `skip_fade` |
| `ui/battle/objectives/` | `objective_panel`, `objective_detail`, `rout_objective`, `leader_objective`, `seize_objective`, `survive_objective`, `defend_objective`, `reinforcement_status`, `leader_mark`, and the overlays `seize`, `defend`, `reinforcement` |
| `ui/battle/forecast/` | `forecast_panel`, `forecast_row`, `forecast_breakdown`, `forecast_view_model` |
| `ui/battle/intents/` | `intent_display`, `intent_icon`, `intent_line`, `intent_rule_tooltip`, `intent_view_model` |
| `ui/battle/menus/` | `action_menu`, `menu_row`, `confirm_dialog`, `panel_host`, `swap_window` |
| `ui/battle/unit/` | `unit_token`, `unit_info`, `unit_info_layer`, `unit_panel`, `unit_detail_panel`, `unit_detail_view_model`, `unit_sprite_table`, `unit_sprite.gdshader`, `hp_bar`, `stance_pips`, `block_badge`, `damage_number` |
| `ui/battle/input/` | `turn_input_model`, `input_device_adapter`, `pad_repeat`, `target_list`, `target_mark`, `target_picker` |

`scenes/`, `scripts/ui/`, `scripts/screens/` and `scripts/debug/` no longer exist afterwards.

## Save Impact

Not saved. O3 confirms no save holds a `res://` path to a moved file before moving anything.

## Work Breakdown

| Step | Work | Risk | After | Done when |
|---|---|---|---|---|
| O1 Docs | Split the orchestrator; move answered questions; add `docs/README.md` | 🟢 | — | Nothing lost; links resolve |
| O2 Standards | Split `gdscript.md`; drop the other project's examples; update `CLAUDE.md` | 🟢 | O1 | Core about 8 KB; every rule still has a home |
| O3 UI layout | Move per the table; rewrite paths in scenes, resources, tests, `scene_router.gd` and `project.godot` | 🟡 about 165 files | O2, no open branches | Same test counts; launch and a windowed boot clean; no old paths left |
| O4 Tests | Split the four huge `run_all.gd` files into runner and case files; mirror `ui/`'s folders in `tests/ui/`; add parallel suites to the runner | 🟢 | O3 | Same test counts; a full run clearly under 10 minutes |
| O5 Large files | Split `battle_controller.gd` and `battle_view.gd` | 🟡 | Deferred | When a step next needs them |

**O3's rules:** one commit, no behaviour change. Move with `git mv` and take each `.uid` along. Don't touch `Modified:` headers, so git keeps seeing renames and history follows.

**O4's caution:** the sessions suite writes a temporary `override.cfg` into the project, so it can't share a project folder with another suite.

## Breaking Changes

| Change | Kind | Current | Proposed | Status | Places to check | Risk |
|---|---|---|---|---|---|---|
| UI scene and script paths | Paths | `scenes/**`, `scripts/ui/**`, `scripts/screens/**` | `ui/**` | Proposed (O3) | Scenes, resources, tests, `scene_router.gd`, `project.godot` | 🟡 |
| Orchestrator sections | Doc locations | One file | `orchestrator/` | Applied (O1) | Links | 🟢 |

## Verification

O1 and O2: rows and sections counted before and after, and links checked. O3 and O4: `sh bandit-bash/tools/run_tests.sh` gives the same count per suite, a clean launch, and a windowed boot into a battle.

## Rollback

Each step is one commit; revert it.
