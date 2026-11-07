# Bug Tracker

**Created:** November 6, 2026. **Last updated:** November 7, 2026.

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

## Closed bugs

| ID | Title | Area | Sev | Closed as | Verified |
|----|-------|------|-----|----------|----------|
| [BUG-001](#bug-001-no-block-at-the-start-of-combat) | No unit has Block at the start of combat | P01 / P02 / P03 | S2 | Can't reproduce (November 7, 2026; no base Block, Vanguard fires on turn 1) | — |
