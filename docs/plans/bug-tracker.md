# Bug Tracker

**Created:** November 6, 2026. **Last updated:** November 16, 2026.

Every known defect in `bandit-bash/`, from playtests, build reports and reviews. It works under the
[orchestrator](game-orchestrator.md): the orchestrator session triages new rows, batches them into
fix steps, issues the prompts and closes rows on merge. Missing features and design changes go in
the plans and the orchestrator's Design items, not here.

## How it works

- **Adding a bug:** anyone (the user, the orchestrator, a build agent's report) adds a row to
  [Open bugs](#open-bugs) with status **New** and a details section below it. IDs are `BUG-NNN`,
  the next free number, never reused or renumbered.
- **Triage** (orchestrator): set the severity and the area (plan), check the expected behaviour
  against `game-vision.md` and the plan, and either assign the bug to a fix step or ask the user.
  A bug whose expected behaviour the vision doesn't settle is **Needs decision** until the user
  answers (CLAUDE.md §1: never silently fix, never silently port).
- **Fixing:** a fix step names its bugs (for example *BF1: BUG-002, BUG-004*). Every fixed bug gets
  a regression test that fails before the fix. A build agent that finds a bug outside its step
  reports it ("found, not fixed"); the orchestrator adds the row.
- **Closing:** on merge the orchestrator sets **Fixed** with the merge commit and moves the row to
  [Closed bugs](#closed-bugs). The user may mark a fixed bug **Verified** after a playtest, or reopen
  it.

**Severity**

| Level | Meaning |
|-------|---------|
| S1 | Crash, a soft-lock, a corrupted or lost save, or a rule broken so a fight can't be played fairly |
| S2 | A wrong rule, number or preview the player acts on (the forecast, ranges, intents) |
| S3 | Wrong or missing feedback; a workaround exists |
| S4 | Cosmetic, docs or text |

**Status:** New · Needs decision · Assigned (step) · Fixed (commit) · Verified · Won't fix · Can't reproduce ·
Not a bug.

## Open bugs

| ID | Title | Area | Sev | Status | Found | Fix step |
|----|-------|------|-----|--------|-------|----------|
| [BUG-002](#bug-002-the-forecasts-crit-chance-ignores-current-stance) | The forecast's crit chance ignores current Stance | P02 / P07 | S2 | New | November 6, 2026, user playtest | — |
| [BUG-003](#bug-003-save-systemmd-says-a-battle-retry-repeats-ids) | save-system.md says a battle retry repeats ids | P00 / P02 | S4 | Assigned (CC9; P02 question 22 accepted November 7, 2026) | November 5, 2026, CC10 report | CC9 |
| [BUG-004](#bug-004-an-enemy-with-an-attack-intent-moves-and-doesnt-attack) | An enemy with an attack intent moves and doesn't attack; the next enemy hits its target | P05 / P07 | S2 | New | November 6, 2026, user playtest | — |
| [BUG-005](#bug-005-unit-detail-shows-the-type-id-not-its-name) | Unit detail shows the type id, not its name | P07 | S4 | Assigned (BF1) | November 7, 2026, UI11 report | BF1 |
| [BUG-006](#bug-006-netlog-raises-an-engine-error-once-the-peer-is-cleared) | NetLog raises an engine error once the peer is cleared | P00 / P10 | S3 | Assigned (BF1) | November 9, 2026, O3 report | BF1 |
| [BUG-008](#bug-008-a-mirror-keeps-a-used-up-consumable) | A mirror keeps a used-up consumable, so its hash differs from the host's | P02 / P11 | S2 | Assigned (BF1) | November 13, 2026, CT5 report | BF1 |
| [BUG-012](#bug-012-loading-the-map-pools-in-a-test-leaks-resources) | Loading `CombatMapPools.load_default()` inside the board suite's route case leaves 74 objects and 58 resources in use at exit | P04 (map pools) / tests | S4 | New | November 16, 2026, MP10a report | — (worked around in the test) |

### BUG-001 No Block at the start of combat

- **Reported:** no unit gets any natural Block at the start of combat.
- **What the vision says:** Block's base value is **0 for every unit**; all Block comes from
  phase-tied effect text (traits, weapons, equipment, heirlooms), refreshed at the side's Phase
  Start (game-vision.md, Block). In M1 the only Phase Start source is the Drengr's **Vanguard**
  ("Phase Start, while no ally is closer to an enemy: +3 Block"); the Battle Medic's Shelter staff
  gives Block as an action. So zero Block on turn 1 is the vision's rule unless Vanguard should
  have fired.
- **To check:** whether the first player Phase Start (after the opening swap window and Start)
  applies Phase Start effects at all. UI7's windowed run showed the Drengr's 3 Block only at the
  turn 2 player phase.
- **Decided** (user, November 7, 2026): no base Block. Vanguard fires at the first player Phase
  Start when its condition holds, as at every other. The current playtest doesn't reproduce the
  report, so it is closed as **Can't reproduce**; reopen it if a turn 1 Vanguard is seen missing.

### BUG-002 The forecast's crit chance ignores current Stance

- **Reported:** critical chance in the preview isn't populated dynamically from current Stance.
- **Expected** (game-vision.md, the damage stages and Stance and Exposure): a hit can crit only if
  the defender's Stance was 0 before that hit; a hit that gets real damage through lowers Stance
  by 1. So the forecast's crit line follows each strike: shown for a defender already Exposed,
  shown from the strike that breaks the last Stance onward in a multi-strike exchange, and absent
  while Stance remains.
- **To check:** `CombatForecast` (`defender_exposed`, the side's `crit_chance`, -1 when not
  rolled) and how `forecast_view_model.gd` shows it.

### BUG-003 save-system.md says a battle retry repeats ids

- **Found:** CC10's report. A `BATTLE_RETRY` restart repeats the rolls but not the instance ids,
  because the campaign file keeps the counter after Begin minted the army and setup. Nothing
  reads ids for meaning.
- **Recommended fix** (P02 question 22): correct the doc in CC9.

### BUG-004 An enemy with an attack intent moves and doesn't attack

- **Reported:** the intents showed two enemy attacks. In the enemy phase the first enemy moved but
  didn't attack, and the second enemy attacked the first enemy's intended target.
- **Run:** solo, seed `52FC-D7F9-0BD5-D`, `m1_greybox`, resumed battle (floor 1, node 1); most
  likely the turn 2 enemy phase (`s0#56`–`s0#95`, the only enemy phase with a long run of steps).
- **Log gap:** the log has no line per enemy action, so it shows neither the plans nor a rejection.
  `EnemyAI.next_command` turns a plan that fails `UnitTurnCommand.validate` into a Wait and
  records the diagnostic "*X*'s *kind* plan rejected - *reason*; it waits"; that line isn't in the
  log, so either the plan wasn't rejected or the diagnostic isn't reaching the log.
- **Expected** (game-vision.md, Enemy intentions; `intents.gd` class doc): intents aren't
  committed tiles, and the real phase decides again after each action, so a *miss* can change
  what *later* enemies do. The first enemy to act has had nothing change since the intents were
  computed, so it should carry out the attack its intent showed (a move and attack, hit or miss).
  A move with no attack from the first actor is a bug unless something on its board differed.
- **To check:**
  - whether the first enemy's real plan was rejected and became a Wait (the move then belongs to
    a path the validator refused partway, or the walk and the attack disagree on the end tile or
    range); `EnemyAI.next_command`, `UnitTurnCommand.validate`, `Intents._carry_out`
  - whether the real phase picks the same first actor as `Intents._play` (the NOTE there: same
    enemies, order and tie rule as `EnemyAI.next_plan`); a different first actor with stale
    intents on screen would look like this report
  - whether the board `Intents.compute` reads matches the real enemy phase start (player Phase
    End, darkness, enemy Phase Start effects crossed the same way)
  - why the diagnostic, if raised, isn't in the playtest log
- **Asked the user:** each enemy's class, the second enemy's own intent target, and where the
  first enemy ended (in range of its target or not).

### BUG-005 Unit detail shows the type id, not its name

- **Found:** UI11's report. The unit detail panel shows the type as the id capitalised
  (`unit_detail_view_model.gd`: `unit.unit_type.capitalize()`), on the reading that content has
  no display names.
- **Expected:** every definition carries `display_name` (P01's `EffectCarrierDefinition`), and
  the M1 data fills it ("Battle Medic", "Brute"). The detail looks the type up in the content
  catalog and shows that; the capitalised id is only a fallback for a missing definition.
- **Also check:** the weapon type line (`held.weapon_type.capitalize()`) and any other id shown
  as text in the battle UI.

### BUG-006 NetLog raises an engine error once the peer is cleared

- **Found:** O3's windowed run logs "No multiplayer peer is assigned" from `net_log.gd` on most
  logged events once the menus start. O3 didn't touch that file.
- **Likely cause** (read, not run): `SteamNetwork.leave_lobby()` sets
  `multiplayer.multiplayer_peer = null`, and `NetLog._log` calls `multiplayer.get_unique_id()` on
  every line. Its comment says that returns 1 with no peer, which holds only for the default
  offline peer. `SceneRouter` calls `leave_lobby()` on entering the start, save select and main
  menu screens, so every solo session reaches this.
- **Expected:** logging is silent with no peer and shows peer 1, as in solo play.
- **To check:** whether `leave_lobby()` should restore an offline peer rather than null, or NetLog
  should guard the call. `steam_network.gd` guards on `multiplayer_peer != null` elsewhere.

### BUG-008 A mirror keeps a used-up consumable

- **Found:** CT5's report (read, not run in multiplayer). On a client mirror, a consumable whose
  last use is spent stays in the Pouch, so the mirror's state hash differs from the host's.
- **Cause:** `CombatState._is_used_up` (`combat_state.gd:747`) returns false at the first effect
  with no charges; the host's check skips such effects instead. It hits every consumable whose uses
  the loadout counts: the Elixir, stat boosters, ingredients and the Key.
- **Expected:** host and mirror drop the item at the same use, and the hashes match.
- **Fix:** `return false` becomes `continue`, with a regression test comparing the mirror's hash
  after an Elixir's last use (CT5's Hit-booster test compares only Hit).

### BUG-009 A second copy of a heirloom never reaches the battle

- **Found:** RN2's report (read, not run). `CampaignSession._add_heirlooms` dedups carriers by
  `"seat:content id"`, so a seat holding a curse twice brings only one copy into battle.
- **Expected:** curses may repeat and copies stack (P09 question 3); `SeatRun.heirlooms` already
  saves copies. Each copy becomes its own carrier; how copies stack is CT9's.
- **Fix in RN3,** which rebuilds the battle bridge, with a regression test bringing a curse held
  twice into a battle.
- **Fixed** in RN3 (9e34098, merged November 13, 2026). Each copy becomes its own carrier
  (`seat:id:copy index`), and each copy's campaign-lane counters write back to its own saved
  entry. Regression: "curse twice: two carriers in battle…" and "…each copy's lane is written back
  to its own entry".

### BUG-010 Save Select shows a stale floor

- **Found:** RN2's report. `CampaignData.floors_climbed`, shown on Save Select, doesn't follow
  `CampaignRunState.floor_number`.
- **Expected:** Save Select shows the run's current floor.
- **Fix in RN3,** with a test that choosing a node updates what Save Select reads.
- **Fixed** in RN3 (9e34098, merged November 13, 2026): every save `CampaignService` makes sets
  `floors_climbed` to the run's floor. Regression: "choosing a node moves Save Select's floor to
  the run's (BUG-010)".

### BUG-011 A test run deletes another run's override

- **Found:** merging RN4 in the main checkout. A run cut off at 16:02 left `bandit-bash/override.cfg`
  behind (the next run refused to start, as designed). Once removed, a new run started, and the cut-off
  run, still alive in the background, finished and ran its `end_run()`, which deleted the new run's
  override. The later user-folder suites then had no test folder: ui/display and ui/input skipped 3
  screen cases ("needs a test user folder") and still reported PASS. Rerun alone, both were clean.
- **Cause** (read): `tools/run_tests.sh` `end_run()` does `rm -f "$OVERRIDE"` without checking the
  file names this run's folder (`custom_user_dir_name="$TEST_DIR_NAME"`).
- **Harm seen:** only Godot log files reached the real user folder; saves were untouched. The guards in
  the UI and sessions suites did their job, so this is lost coverage, not lost data.
- **Expected:** a run removes `override.cfg` only when it still names this run's folder; a suite that
  skips because the folder went missing makes the run fail, not pass.
- **Workaround:** one runner per checkout at a time; after an interrupted run, wait for its Godot
  processes to exit before starting another.
- **Priority:** low (user, November 14, 2026): fix when a runner step or a free slot comes up.
- **Fixed** in O6 (`feature/O6`, not yet merged, November 16, 2026). The runner writes no
  `override.cfg` at all: each suite's Godot gets its own user folder through its own `APPDATA`
  (`XDG_DATA_HOME` on Linux, `HOME` on macOS; both unchecked), in the run's log folder, so no run
  can delete or block another's. The ui and sessions guards read the folder Godot resolved
  (`OS.get_user_data_dir()`) instead of the project setting, and the runner fails any suite that
  prints "needs a test user folder". Regression: a copy of the runner with the per-suite folder
  switched off makes `sessions` FAIL on its skipped cases instead of PASS; two full runs at once,
  in one checkout and in two worktrees, both pass.

### BUG-007 Test runs in two worktrees share one user folder

- **Found:** CT6's report. On a clean `dev`, `sessions` failed `_test_service_rng_campaign_streams`
  once while RN1's worktree was also running tests; it passed on a rerun.
- **Cause** (read, not run): `tools/run_tests.sh` writes an `override.cfg` with
  `config/custom_user_dir_name="bandit_bash_tests"`, a fixed name, so every worktree's run uses
  the same `user://` folder. O4 serialised the suites that use it within one run, but two runs at
  once still collide.
- **Expected:** each run gets its own test user folder, removed when the run ends, so parallel
  build agents never interfere.
- **Workaround until fixed:** a `sessions` or `save` failure during another worktree's run is
  rerun once before it counts.
- **Seen again:** RN1's report: `ui/board` failed 3 save cases ("Already exists") while CT6's worktree ran; it passed alone and on a rerun. So any suite that writes to `user://` is affected.
- **Fixed** in BF2 (76774d4, merged November 12, 2026). Each run names its folder
  `bandit_bash_tests_<pid>_<random>` and prints it. It deletes only that folder, at the end and on
  interrupt, after copying its `logs/` into the run's log folder. The ui and sessions guards accept
  the `bandit_bash_tests` prefix. Regression: with the old runner, concurrent runs collided in 2 of 3
  rounds; with the fix, none did. The old folders `%APPDATA%\bandit_bash_tests` and
  `bandit_bash_tests_r5` are left for the user to delete.

## Closed bugs

| ID | Title | Area | Sev | Closed as | Verified |
|----|-------|------|-----|----------|----------|
| [BUG-001](#bug-001-no-block-at-the-start-of-combat) | No unit has Block at the start of combat | P01 / P02 / P03 | S2 | Can't reproduce (November 7, 2026; no base Block, Vanguard fires on turn 1) | — |
| [BUG-007](#bug-007-test-runs-in-two-worktrees-share-one-user-folder) | Test runs in two worktrees share one user folder | P14 (runner) | S3 | Fixed (BF2, 76774d4, November 12, 2026) | — |
| [BUG-009](#bug-009-a-second-copy-of-a-heirloom-never-reaches-the-battle) | A second copy of a heirloom or curse never reaches the battle | P08 / P09 | S2 | Fixed (RN3, 9e34098, November 13, 2026) | — |
| [BUG-011](#bug-011-a-test-run-deletes-another-runs-override) | A test run's cleanup deletes another run's `override.cfg` in the same checkout | P14 (runner) | S3 | Fixed (O6, 57e51eb, November 16, 2026: no `override.cfg` at all; a missing-folder skip fails the suite) | Two runs at once in one checkout, both ALL PASS |
| [BUG-010](#bug-010-save-select-shows-a-stale-floor) | Save Select's floor doesn't follow the run's floor | P08 | S4 | Fixed (RN3, 9e34098, November 13, 2026) | — |
| [BUG-013](#bug-013-a-map-can-need-a-door-no-one-can-open) | A map can put a required route behind a door the army can't open | P04 (maps, map check) | S2 | Fixed (MP12, 419ec4a, November 18, 2026: doors, levers and every map object are drawn on the board; two levers added inside rooms; the map check proves every map reachable) | The user's playtest, pending |

### BUG-012 Loading the map pools in a test leaks resources

- **Found:** MP10a's report. Calling `CombatMapPools.load_default()` inside the ui/board suite's
  route case leaves 74 objects and 58 resources in use at exit. The battle screen's own call to the
  same function doesn't.
- **Cause:** not investigated. MP10a worked around it in the test.
- **Expected:** loading the pools from a test frees everything at exit, as the battle screen does.
- **Harm seen:** an exit warning only; no wrong result.

### BUG-013 A map can need a door no one can open

- **Found:** the user's playtest (November 18, 2026): maps have doors with no lever and no key to
  open them, so the map can't be finished.
- **Read so far:** every door on the M2 maps has a lever in its group except the Hall's (a key
  door to its chest room, which is optional loot): `old_mill`, `watch_post` (the leader behind a
  lever door) and `gatehouse` (two levers). So the likely cause is a lever that can only be
  reached through its own door, or a lever the player can't find. `MapCheck` checks no
  reachability at all, so nothing caught it. Which map the user saw is not yet known.
- **Expected** (the user's rule): every required tile (objectives, the leader slot, the deployment
  zone's way out, every enemy slot an objective needs) is reachable without a key. Only optional
  content, such as shortcuts and loot, sits behind a key-only door. Every lever door's lever is
  reachable from the player's side without passing that door.
- **Fix in P04 MP12:** the map check enforces the rule, every map passes it, and the rule is
  written into map-objects.md.
- **Cause (MP12, November 18, 2026):** no door truly lacked a lever. The battle board drew only terrain: a door looked like an open gap units couldn't enter, and its lever, and every chest, searchable, passage and brazier, was invisible. Two maps also had traps: on `watch_post` and `old_mill` the only lever stood outside its door, so an enemy could shut units in (on a Rout map with every survivor inside, the battle could never end).
- **Fixed in MP12** (merged November 18, 2026): each map object is drawn (`map_object_mark.tscn`, placeholder symbols, dimmed once spent, a tag linking levers to doors and passage ends) and named with its state in the tile panel; a second lever inside each trap room, (4,1) on `watch_post` and (2,3) on `old_mill`; `MapCheck.Rule.REACHABILITY` fails any map whose required tiles or levers can't be reached without a key, or whose lever-door room has no lever inside; map-objects.md's "Reachable maps" states the rule. **Verify:** the user's next playtest.
