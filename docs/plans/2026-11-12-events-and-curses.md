# Plan: Narrative Events and Curses
**Date:** November 12, 2026
**Status:** Draft, awaiting the answers below. Orchestrator ID **P09**

## Problem

An Unknown node that rolls an event has nothing to show. P08 RN10 hands it to a placeholder that returns to the map. events.md designs 13 events and 10 curses, but the game has no event data, no way to apply an outcome on the campaign layer, and no event screen.

Event outcomes act outside battle. P01 says they reuse the effect operation blocks (`CampaignGrant`, `ChangeBaseStat`), but those run only inside a battle's `EffectEngine` (`effect_operation.gd`: "acts through the engine's paths"). Most outcomes also have no operation at all: heal or damage by percent, a revive, a free upgrade, a prefix re-roll, a surprise combat.

## Open Questions

### 1. How event outcomes are applied

- **A, a small outcome block set on the campaign layer (recommended):** `EventOutcome` resources in data, applied by a pure resolver to P08's `RunState`. Where an existing block fits, the outcome holds one and the resolver reads its fields: `CampaignGrant` for gold, a heirloom, a recruit or a rune; `ChangeBaseStat` for a stat change. Granted weapon effects ("Hit dealt: heal 2") go on the `ItemInstance` as it already allows. The engine and its rules stay untouched.
- **B, run outcomes through a battle-less `EffectEngine`:** keeps P01's wording exactly. But the engine is built around a combat state and facts, and six outcome kinds would still need new operations.
- A changes P01's contract wording, not its intent: outcomes are still data blocks, never scripts.

### 2–6. Shorter questions

| # | Question | Recommendation |
|---|----------|----------------|
| 2 | Can event damage kill a unit (Frozen Armory's 20% cold)? | **No:** event damage leaves at least 1 HP. Permadeath stays a combat outcome |
| 3 | A cursed option whose tier has no curse left that the player doesn't hold | **Greyed out with the reason,** as the vision greys out an empty reward pool |
| 4 | How random event items roll | **(a)** A rare weapon or tome uses P08's Weapon pick rule (from a type the army can use 75% of the time). **(b)** A random trinket rolls the Standard item odds without touching the Rare offset. **(c)** A random rune is even across the pool |
| 5 | Small rule readings | **Accept all of (a)–(f)** below |
| 6 | Every event seen this run | **The seen events become available again,** as maps do (P08 question 10) |

**Question 5's readings:**

- (a) Losing max HP (Drink Deep, Drink the Sap) lowers current HP only where it's above the new max.
- (b) Gaining max HP (Be Merry) raises current HP by the same amount, as a level-up does.
- (c) Cursed Blood halves event healing too ("healing received").
- (d) Healing by percent of max HP rounds halves up, as a Feast's does.
- (e) A revived unit returns with whatever items it still holds. If the army is full, reviving works like recruiting past the max.
- (f) A surprise combat pays a Standard combat's full rewards: gold, grades, the item pick and XP.

## Scope

**In:** event content as data; the outcome blocks and their resolver; option requirements; the event draw, eligibility and the never-repeat rule; naming each cursed option's curse when the event is generated; the event screen with unit and weapon choosers; surprise combats through P08's bridge; per-seat state; team-choice rules tested headless.

**Out:** the curses' data and their combat effects (P03 CT9); the Unknown roll itself (P08); co-op event screens and voting transport (P11, as in P08 question 11); new events or curses beyond events.md (the vision's "Still open").

## Design Basis

events.md (all of it). game-vision.md: Run structure (Events, Empty offer pools), Army (revive shrine), Run-wide resources. heirlooms.md (Rare tier, curses outside the pool). items.md (Modified items, Emberglass Vial). unit-roster.md (Recruiting, Prefixes). P13's `EVENT_DRAW`, `TEAM_CHOICE` and `EVENT_OUTCOME` streams.

"More team events, curses and events" is under "Still open", so this plan builds only the first-pass pool. Every value is first pass.

## Legacy Behavior

| Godot_FE file | Behavior | Keep / Change / Drop | Reason |
|---|---|---|---|
| `scripts/resources/events/events.gd` | An event resource with up to 4 options | **Change** | 2–3 options (events.md) |
| `event_option/EventOption.gd` | A 25-value effect enum; 13 outcomes scripted in a `match` | **Change** | Data blocks, no scripted outcomes |
| `campaign_map/events/event_selection.gd` | Requirement checks inside the per-unit loop (a bug: rejects on the first unit) | **Drop** | One check over the whole army |
| `event_selection.gd` | Draws from the global RNG | **Change** | P13's seeded streams |
| `resources/definitions/events/*.tres` | 8 events reworked | **Keep the themes** | events.md rewrote their options |

No tuning values come from `Godot_FE/`; events.md sets them all.

## Approach

**Shape.** Rules in `scripts/events/`, data in `data/events/`, the screen in `ui/campaign/events/`.

| Piece | Job |
|---|---|
| `EventDefinition` | Id, text, art, team-choice flag, eligibility, 2–3 options |
| `EventOption` | Text, requirements, its outcome blocks, an optional curse tier |
| `EventOutcome` blocks | Gold, heal or damage by percent, stat or max HP change, pending level-up gain, item grant or modification, heirloom, rune, recruit, upgrade, prefix re-roll, revive, max army size, surprise combat, curse |
| `EventResolver` | Applies one option's blocks to one seat's `RunState`, emitting `CampaignFact`s |
| `EventRequirements` | One pure check over the whole army: gold, a unit type, the commander, an item, a fallen unit, army size below 8 |

**The draw.** On entering, `EVENT_DRAW` picks one eligible event this run hasn't seen. The shrine is eligible only with a fallen unit. Each option's random parts are then rolled per seat from `EVENT_OUTCOME`: named curses, random items, the heirloom. They are saved before anything shows, so a quit and resume shows the same event. Every curse is named and shown with its effect and tier before choosing.

**Choosing.** Picking an option that says "a chosen unit" or "a chosen weapon" opens a chooser. Fallen units can't be chosen, except by the shrine. Items gained are placed as P08 question 6 decided: straight onto a unit or into the convoy. Modified items show as "Infused <name>" with their changes (items.md).

**Surprise combats** go through P08's battle bridge on the Standard pool, at the node's floor and step, and return to the map afterwards.

**Co-op hooks kept now.** An individual event lets each seat choose for itself. A team choice collects one vote per seat, then `TEAM_CHOICE` draws weighted by votes and the option applies to every seat. An option is available only if every seat meets its requirement. Combat options are always team choices.

**UI.** One event screen, its own `.tscn`, with documented `@export`s and a placeholder art slot. It works on keyboard, mouse and controller with glyph hints. Greyed options show their reason.

**Rejected:** an event as a scripted scene per event (`Godot_FE`'s defect); rolling curses when an option is chosen (the curse must be named first).

## Save Impact

| Section key | Block | Per player | Holds |
|---|---|---|---|
| `events` | `CAMPAIGN` | No | Seen event ids; the current event; each seat's rolled outcomes, choice and chooser stage; team votes |

The section is new, version 1, with no schema change. Outcomes land in P08's sections: curses in `heirlooms`, deltas and pending gains in `roster`, gold in `economy`.

## Work Breakdown

| Step | Work | Risk | After | Needs from M2 | Done when |
|---|---|---|---|---|---|
| EV1 Outcomes | `EventDefinition`, options, the outcome blocks, `EventResolver`, `EventRequirements` | 🟡 | Questions answered; P08 RN2 | — | Every block kind tested against a `RunState` |
| EV2 Draw and state | Eligibility, the draw, rolled outcomes, the `events` section, surprise combats | 🔴 save format | EV1; P08 RN5 | — | Quit and resume shows the same event and curses |
| EV3 Screen | The event screen and choosers on all three input devices | 🟡 | EV2 | — | Every option kind can be chosen with each device |
| EV4 Content | The 13 events as data | 🟢 | EV3 | CT4, CT5, CT8, CT9, CT13 | Each event plays; content test passes |
| EV5 Team choice | Votes, the weighted draw, every-seat requirements, headless | 🟢 | EV2 | — | Vote odds match over many seeds |
| EV6 Docs | save-system.md's section; events.md's rule readings | 🟢 | EV4 | — | Docs match the code |

P08 RN10 wires the Unknown roll to EV2 once both exist.

## Breaking Changes

| Change | Kind | Current | Proposed | Status | Places to check | Risk |
|---|---|---|---|---|---|---|
| Event outcomes | P01 contract wording | Reuse the effect operation blocks | Their own blocks on the campaign layer, reading `CampaignGrant` and `ChangeBaseStat` data where they fit | Proposed (question 1) | P01's Events contract, `decisions/P08-campaign-run-flow.md` | 🟢 |

## Verification

Each step's Done when column, in `tests/events/`, and the full runner. EV4 plays every event's every option in a headless run and checks its outcome. M3's playtest covers events in real runs.

## Rollback

Each step is its own merge; revert it. EV2 adds a save section: a run saved after it won't resume an event on an earlier build, which is acceptable before release.
