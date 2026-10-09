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
| # | Question | Options | Recommendation | Answer |
|---|----------|---------|----------------|--------|

## Scope
In scope / explicitly out of scope.

## Legacy Behavior (ports from Godot_FE only)
| Godot_FE file | Behavior | Keep / Change / Drop | Reason |
|---------------|----------|----------------------|--------|

Tuning values carried over, each with its source file.

## Approach
Chosen design and the alternatives rejected, with reasons.

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

Supports `gdscript.md` §3.6 and §3.7.

**Before** (12 lines, mostly history):

```gdscript
## 2026-08-12: scales this fish's own DetectionArea collider to match caught_size, and caches
## the resulting radius as _body_radius for terrain-clearance checks (see that field's own doc).
## The collider as authored in LiveFish.tscn (a SphereShape3D, radius 0.3) is tuned for a
## reference_fish_size fish -- same baseline reference_fish_size already uses to scale
## wander_radius -- so a species/individual bigger or smaller than that reference now actually
## occupies a correspondingly bigger or smaller sphere instead of every fish sharing one
## size-blind constant regardless of how big it visibly is (see _apply_fish_definition_visuals's
## sprite scaling, which already varies per-instance the same way this now does).
##
## Duplicates the shape resource before resizing it: Godot shares one SphereShape3D sub-resource
## across every instance of a scene by default, so resizing it in place would resize every other
## fish's collider too, not just this one's.
```

**After** (6 lines — every durable fact survives, the history is gone):

```gdscript
## Scales the DetectionArea collider to [member caught_size] and caches the result as
## [member _body_radius].
##
## The authored radius is calibrated to [member reference_fish_size].[br]
## [b]Must duplicate the shape:[/b] Godot shares sub-resources across scene instances, so
## resizing in place resizes every other fish's collider too.
```

What changed: the date, the prior-state narration ("now actually occupies") and the cross-function
aside are gone. The calibration baseline and the duplicate-before-resize constraint are kept, as
links where possible. `[member _body_radius]` resolves only because `_body_radius` has its own `##`
doc; an undocumented private member doesn't appear in the generated docs.

---

## 3. State machine overview block

Supports `gdscript.md` §3.8. Placed directly above the enum it describes, and above that enum's
`##` doc if it has one.

```gdscript
# --- Action sub-state (only meaningful while current_mode == ACTION) ---------
# READY:      reticle and range indicator are live, cursor is free, camera at normal zoom.
# CHARGING:   player is holding action_confirm. Cursor is captured (locked in place, which is
#             also what freezes aim_point -- see _process below), camera zooms in, charge_power
#             fills over charge_time_to_full seconds.
# EXECUTING:  release fired -- the projectile is mid-flight toward the computed impact point.
# SETTLED:    the projectile landed and is ALREADY live, waiting for a trigger -- there is no
#             separate "arm it" step; it is active from the moment it lands.
# PROMPT:     a trigger fired and the reaction window is open. action_alt attempts the reaction;
#             action_confirm deliberately does NOT start recovery here (unlike SETTLED's idle
#             case) -- nothing is captured yet, so Target.start_recovery() would no-op while this
#             action_state still flipped to RECOVERING, desyncing the two.
# RECOVERING: EITHER holding action_confirm to retract an empty projectile, OR (once a reaction
#             lands) the resolution minigame -- see _on_target_captured, which jumps straight here
#             the instant attempt_reaction() succeeds, with no separate input required.
#             Target.start_recovery() / Target.is_minigame_active() tell the two cases apart;
#             action_state doesn't need to.
# action_cancel aborts from EXECUTING/SETTLED/PROMPT/RECOVERING. toggle_mode is ignored outside
# READY -- you can't leave action mode with a projectile deployed; cancel first.
```

What makes it worth its length:

- **The precondition in the header** — when the enum is meaningful at all.
- **A shared binding with different meanings.** `action_confirm` does three unrelated things across
  three states; no single handler shows that.
- **Deliberate non-behavior.** The `PROMPT` entry records that a binding is intentionally inert and
  what breaks if someone "fixes" it. This is the highest-value line in the block.
- **Which object owns the real distinction.** `RECOVERING` covers two situations the enum doesn't
  separate, and names what does.
- **Absent steps.** "There is no separate arm-it step" stops the next reader from adding one.

---

## 4. Input map overview block

Supports `gdscript.md` §3.8. Placed directly below the class doc of any script that reads named
actions.

```gdscript
# ============================================================
# INPUT MAP SETUP (Project Settings -> Input Map):
#   "toggle_mode"    -> Q key                (switch Move Mode <-> Action Mode)
#   "strafe_left"    -> A key                (move mode only: step left)
#   "strafe_right"   -> D key                (move mode only: step right)
#   "move_forward"   -> Left Mouse Button    (hold to advance)
#   "move_backward"  -> Right Mouse Button   (hold to reverse)
#   "move_dash"      -> Space key            (move mode only: HOLD to charge a longer dash,
#                                              release to fire -- collides with nearby actors and
#                                              pushes off obstacles; a bare tap dashes at the
#                                              uncharged baseline)
#   "action_confirm" -> Left Mouse Button    (action mode: HOLD to charge power, release to fire;
#                                              also held to retract once deployed)
#   "action_cancel"  -> Right Mouse Button   (action mode: cancel aiming/charging, or abort a
#                                              deployed projectile)
#   "action_alt"     -> Space key            (action mode: reaction input during a prompt window
#                                              -- harmless with no prompt open, since the
#                                              projectile is already live from the moment it lands)
#   (move_forward + move_backward held together = brace / hard stop)
# ============================================================
```

What it demonstrates:

- **Every action the script reads**, including trivial ones.
- **Reused bindings, marked by mode.** Left Mouse is `move_forward` in move mode and
  `action_confirm` in action mode; that collision is a design decision and is visible here.
- **Combinations** that exist in no single action name (the brace).
- **Harmless inputs.** "Harmless with no prompt open" tells the next reader a guard clause is
  intentional, not a missing check.
