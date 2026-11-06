# Bug Tracker

**Created:** November 6, 2026. **Last updated:** November 6, 2026.

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
  [Fixed bugs](#fixed-bugs). The user may mark a fixed bug **Verified** after a playtest, or reopen
  it.

**Severity**

| Level | Meaning |
|-------|---------|
| S1 | Crash, a soft-lock, a corrupted or lost save, or a rule broken so a fight can't be played fairly |
| S2 | A wrong rule, number or preview the player acts on (the forecast, ranges, intents) |
| S3 | Wrong or missing feedback; a workaround exists |
| S4 | Cosmetic, docs or text |

**Status:** New · Needs decision · Assigned (step) · Fixed (commit) · Verified · Won't fix ·
Not a bug.

## Open bugs

| ID | Title | Area | Sev | Status | Found | Fix step |
|----|-------|------|-----|--------|-------|----------|
| [BUG-001](#bug-001-no-block-at-the-start-of-combat) | No unit has Block at the start of combat | P01 / P02 / P03 | S2 | Needs decision | November 6, 2026, user playtest | — |
| [BUG-002](#bug-002-the-forecasts-crit-chance-ignores-current-stance) | The forecast's crit chance ignores current Stance | P02 / P07 | S2 | New | November 6, 2026, user playtest | — |
| [BUG-003](#bug-003-save-systemmd-says-a-battle-retry-repeats-ids) | save-system.md says a battle retry repeats ids | P00 / P02 | S4 | Assigned (CC9, if P02 question 22 is accepted) | November 5, 2026, CC10 report | CC9 |

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
- **Needs decision:** is the report (a) Vanguard not firing on turn 1, a bug, or (b) a wish for
  base Block, a vision change (`Godot_FE` had weapon "block data", which the vision replaced)?

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

## Fixed bugs

| ID | Title | Area | Sev | Fixed in | Verified |
|----|-------|------|-----|----------|----------|
