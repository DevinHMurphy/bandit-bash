# Rebalance and Feature Updates

The one place for playtest feedback and for the tuning and feature changes it leads to. Entries
start here as ideas; the user accepts them; the orchestrator turns accepted ones into build steps.
Every entry targeted at M2 is built before M2 is marked complete.

**Status:** ideation, opened November 18, 2026 (user). Nothing here changes the game until it is
**Accepted** and built. Accepted rules that change the vision go through the ideation thread;
values that only tune live here and in the data.

## How it works

1. **Log.** Write playtest notes in the [Inbox](#inbox) in any form: what you did, what happened,
   how it felt. A date and the map or unit is enough.
2. **Triage** (orchestrator). Each note becomes one or more entries in
   [Entries](#entries), or goes elsewhere:
   - a defect (something doesn't work as designed) → [bug-tracker.md](../plans/bug-tracker.md);
   - a rule the vision states differently → the ideation thread (design items);
   - everything else (a value, a feel, a missing feature) → an entry here.
3. **Decide** (user). Each entry gets a status: **Open** (logged, not decided), **Accepted**
   (do it, with a target), **Rejected** (with why), **Parked** (after the MVP).
4. **Build** (orchestrator). Accepted entries are batched into build steps: tuning into a
   **rebalance pass** (RB1, RB2...), features into the plan that owns the system. The entry
   records its step, then **Done** with the commit.

**Targets:** **M2** (built before M2 is complete), **M3** (before the solo run is complete),
**Later**.

**Tuning values:** an accepted value changes the data, the design doc that lists it (for example
unit-roster.md) and the tests that check it, in one change, as the November 17 rebalance did.

## Inbox

Raw playtest notes, newest first. The orchestrator empties this into Entries.

- *(empty)*

## Entries

IDs are permanent. **Type:** Balance (a value), Feature (new or changed behaviour), Feel (UI,
pacing, readability).

| ID | Logged | Area | Type | What | Proposal | Status | Target | Step |
|----|--------|------|------|------|----------|--------|--------|------|
| RF-001 | November 17, 2026 (user) | Units | Balance | The starting army felt fragile | Drengr HP 24 → 40 and a Simple Sword instead of the Simple Axe; Archer HP 13 → 21; Hakkapel HP 22 → 36 | **Done** (84d0a4e) | M2 | — |
| RF-002 | November 16, 2026 (MP10a report) | Maps | Balance | Turn par on all ten M2 maps is a first guess (`# ASSUMPTION` in each map's `.tres`) | Set each par from playtest turn counts | Open | M2 | — |
| RF-003 | November 17, 2026 (EN7 report) | Maps | Balance | `bandit_camp` at step 1 was won on turn 1 by killing the Hexer leader | Watch in play; move the leader slot back, or add cover in front of it | Open | M2 | — |
| RF-004 | November 15, 2026 (enemy-packs.md decision 4) | Enemies | Balance | Reinforcement waves send a whole basic or hard pack at the step's size (`# ASSUMPTION` in `WaveGroups.draw_group`) | Settle wave sizes in play; the user's guess is that Defend maps field more but weaker units | Open | M2 | — |
| RF-005 | November 15, 2026 (enemy-packs.md decision 5) | Enemies | Balance | The first 2 standard combats of each step draw the basic pool | Tune the 2 in play | Open | M2 | — |
| RF-006 | November 16, 2026 (P03 question 8) | Economy | Balance | Modified-item point values: AtkX 3, Range 2, weight −0.25 (`# ASSUMPTION` in `prices.gd`) | Tune once events modify items in play | Open | M3 | — |
| RF-007 | November 16, 2026 (UI13 report) | Runes | Feature | A rune can only be cast from a unit's own menu, so once every unit has acted none can be cast; the vision puts runes outside the action economy | A battle-level Runes entry (key, pad button, HUD button) usable at any time in the player phase (proposed P07 UI14) | Open | M2 | — |
| RF-008 | November 15–17, 2026 (UI12, UI13, EN7 reports) | UI | Feel | Placeholder glyphs and colours: "¤" object intent, "Ø" Block ban, "§" signature, gold Recall pick, the rune preview's "Now / After" | Replace in the art pass, or confirm | Open | Later | — |
| RF-009 | November 5, 2026 (M1) | All | Balance | M1's tuning pass was deferred to M2's playtest | Fold into the first rebalance pass | Open | M2 | — |

## Rebalance passes

Built batches of accepted entries.

| Step | Entries | Status |
|------|---------|--------|
| *(none yet)* | | |
