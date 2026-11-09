# GDScript Reference — Bandit Bash

Worked examples for the rules in `.claude/rules/gdscript.md` and `CLAUDE.md`. Each section says
which rule it supports. Read the relevant section when that rule tells you to.

---

## 1. Plan document template

Used by `CLAUDE.md` §2. Save as `docs/plans/YYYY-MM-DD-<slug>.md`. Replace every bracketed
placeholder; take the date from `date "+%B %-d, %Y"`.

```markdown
# Plan: [Title]
**Date:** [Month Day, Year]
**Status:** Draft — awaiting approval

## Problem
What's wrong now, with file:line evidence. No proposed solution here.

## Open Questions
Only questions still open. Once answered, a question moves to `docs/plans/decisions/Pxx-<slug>.md` and its outcome goes in the Approach. Keep cells short; a long question becomes a heading with bullets.
| # | Question | Options | Recommendation | Answer |
|---|----------|---------|----------------|--------|

## Scope
In scope / explicitly out of scope.

## Design Basis
Sections of `docs/design/game-vision.md` and `docs/design/living-labyrinth/master-ideation.md`
this follows, and any gap or open item from the vision it depends on. Or the line "Not covered by
the vision." for non-gameplay work.

## Legacy Behavior (ports from Godot_FE only)
| Godot_FE file | Behavior | Keep / Change / Drop | Reason |
|---------------|----------|----------------------|--------|

Tuning values carried over, each with its source file.

## Approach
Chosen design and the alternatives rejected, with reasons.

## Save Impact
What this change persists, per `docs/design/save-system.md`: each block (profile, campaign,
combat, settings), section key and version, whether it is per player, and the migration for any
changed shape. Or the line "Not saved." with why nothing needs to survive a restart.

## Work Breakdown
Ordered, independently committable steps. Each: files touched, description, risk (🟢/🟡/🔴),
verification. Cheapest, highest-confidence steps first, so each can be measured alone.

## Breaking Changes
Table format from gdscript.md §6.4, or the line "No breaking changes."

## Verification
How we know it worked. Include benchmark numbers for performance work (gdscript.md §11).

## Rollback
How to undo it if it regresses.
```

---

## 2. Comment rewrite: before and after

Supports `gdscript.md` §3.

Before:

```gdscript
## Flashes the predicted HP loss. Added in UI10 (question 34 (1)); this used to dim the bar
## instead, like the pips did before UI7F. November 7: changed the flash to white because the
## user wanted damage and heal to match. Calls show_preview, which sets the preview value and
## then starts the tween that pulses the part of the bar between the HP and the predicted HP.
```

After:

```gdscript
## Pulses the part of the bar the forecast predicts will change, lost or restored.
##
## The number keeps the current HP; the forecast panel has the before and after.
```

The dates, the step names, the earlier look and the restated call are gone. What the reader can't see from the code, that the number deliberately stays put, is kept.

---

## 3. State machine and input map blocks

Supports `gdscript.md` §3.8. The real examples are the state block above `Stage` and the input map block below the class doc in `battle_controller.gd`.
