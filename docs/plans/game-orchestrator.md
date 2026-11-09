# Game Orchestrator

Where the project is, what's next and what's out of scope. Start here.

**Last updated:** November 9, 2026.

| Need | File |
|---|---|
| What a step needs before it starts; the graphs | [orchestrator/dependencies.md](orchestrator/dependencies.md) |
| Design items to settle when a plan is drafted | [orchestrator/design-items.md](orchestrator/design-items.md) |
| Bugs | [bug-tracker.md](bug-tracker.md) |
| A plan's answered questions | `decisions/Pxx-*.md`, by question number |
| History before November 9, 2026 | [orchestrator/change-log-archive.md](orchestrator/change-log-archive.md); after that, `git log` |

## How to use this file

**On every merge or plan change,** update Where we are, the Milestones status, the registry row and Next actions here, and the gates and both graphs in `orchestrator/dependencies.md`. Commit messages are the change log.

**Before a plan is approved:**

1. Every plan it depends on is at least **Approved**, or the exact contract it uses is named in it.
2. Its design basis has nothing it needs under "Still open" in [game-vision.md](../design/game-vision.md#open-and-unfinished).
3. Every unowned dependency it touches has an owner.
4. It stays inside [MVP scope](#scope-guardrails), or the user has explicitly pulled the item in.

**Before a step starts,** check its row in Gates.

**Plan one step ahead:** draft a plan while the step before it is being built, not all at once and never after the code that needs it.

**Writing plans:** plans hold the current design and only open questions. Answered questions move to `decisions/`. Keep table cells short; a long question becomes a heading with bullets.

**Branches:** build tracks branch from `dev` as `feature/<step>` and merge back into `dev`. Plan and orchestrator commits go to `dev`. `main` holds released state.

## Where we are

- **Milestones:** M0 and M1 are complete. **Current: M2 Combat complete.**
- **What runs today:** a solo run opens the M1 battle: the Mercenary army against the Brigand pack on the greybox map. All of M2's battle systems and functional UI work on keyboard, mouse and controller: targeting, forecast, intents, the darkness, every objective's HUD, unit detail, and Save & Quit with resume.
- **What M2 still needs:** content, enemy AI, docs and bug fixes. No new systems.
- **Tests:** 3,748 cases, all passing, and a clean headless launch (`sh bandit-bash/tools/run_tests.sh`).
- **Not started:** P08–P12, which M3–M5 need.

## Milestones

The MVP is **one full run, start screen to boss, solo and co-op, on Normal** (game-vision.md).

| Milestone | Goal | Plans | Status |
|---|---|---|---|
| **M0 Foundations** | The engine every system plugs into | P00, P01 | **Complete** October 30, 2026 |
| **M1 First playable fight** | One greybox combat, start to finish | P02–P07 (subsets) | **Complete** November 5, 2026; its tuning pass is deferred |
| **M2 Combat complete** | Every MVP combat feature and piece of content, with a functional UI | P02–P07 | **In progress.** Left: P03 CT4–CT13, P05 EN6–EN12, M2's maps, BF1, and the docs (EB8, CC9, MP9, DK6, CT11, EN12) |
| **M3 Solo run** | Start screen → campaign → boss, saved and resumable; 60–80 minutes | P08, P09 | Not started; P08 is a stub |
| **M4 Co-op run** | The same run for 2–4 players, tested live on two machines | P10, P11 | Not started |
| **M5 MVP** | Statistics, the Waystation war table, the MVP checklist | P12, polish | Not started |
| Post-MVP | Meta progression and beyond | P20–P24 | Not planned |

**M2's exit:** every objective and map object, the 10 enemy classes, 4 mini-bosses, the Powder Baron map, and all MVP units, weapons, staves, items, heirlooms and runes as data.

## Plan registry

Statuses: **Not started** · **Stub** · **Draft** · **Approved** · **In progress** · **Implemented** · **Superseded**.

| ID | Plan | Status | Left | Depends on |
|---|---|---|---|---|
| P00 | [Save system](2026-10-13-save-system.md) | **Implemented** | Multiplayer paths untested live | — |
| P01 | [Event bus and effects](2026-10-23-event-bus-and-effects.md) | **In progress** | EB8 docs | P00 |
| P02 | [Combat core](2026-10-26-combat-core.md) | **In progress** | CC9 docs | P01 |
| P03 | [Content catalog](2026-10-29-content-catalog.md) | **In progress** | CT4–CT13 | P01 |
| P04 | [Combat map](2026-10-27-combat-map.md) | **In progress** | MP9 docs; M2's maps | P01, P02 |
| P05 | [Enemies and AI](2026-10-30-enemies-and-ai.md) | **In progress** | EN6–EN12 | P02, P04 |
| P06 | [The darkness](2026-11-03-the-darkness.md) | **In progress** | DK6 docs | P02, P04 |
| P07 | [Combat UI](2026-11-04-combat-ui.md) | **In progress** | Nothing for M2 | P02, P04, P05, P06 |
| P08 | [Campaign and run flow](2026-10-24-campaign-run-flow.md) | **Stub** | To draft next | P01, P03 |
| P09 | Narrative events and curses (events.md) | **Not started** | To draft | P01, P03, P08 |
| P10 | Net transport (multiplayer-combat-options.md; read `steam_multiplayer_kit/` first) | **Not started** | — | P00, P01 |
| P11 | Co-op combat (game-vision.md Multiplayer maps) | **Not started** | — | P01, P02, P04, P08, P10 |
| P12 | Statistics and the Waystation war table (meta-progression.md) | **Not started** | — | P01, P08 |
| P13 | [RNG streams](2026-10-26-rng-streams.md) | **Implemented** | — | P00 |
| P14 | [Project organization](2026-11-09-project-organization.md) | **In progress** | O4 (O5 deferred) | — |
| P20–P24 | Meta progression, tutorials, dev console, status effects, shared co-op battles | Post-MVP | — | — |

## Next actions

**Planning focus (user, November 9, 2026):** build prompts are on hold while planning comes first.

1. **P14:** O1, O2 and O3 done (O3 merged in eb380c8). Next, O4 (tests), a single build agent.
2. **Plans:** draft P08 campaign and run flow, then P09 events and curses. M3 can't start without them. Write the move-preview re-architecture design doc.
3. **Then M2's content, two prompts at a time:**
   - **Wave A (ready):** CT6 target shapes with EN6 enemy roster; then CT13 unit roster with CT5 equipment and consumables.
   - **Wave B:** CT4 weapons and staves, CT9 heirlooms and curses, EN10 reinforcement groups, EN9 map-object AI.
   - **Wave C:** CT7 runes, CT8 unit prefixes and pools, CT10 modified prices (its formula goes to the user first).
   - **Wave D:** EN7 elites and bosses (marks leaders on the HUD), EN8 mini-bosses, EN11 the Powder Baron and its map, CT12 weapon prefixes (waits on the vision's weapon-prefix rules).
   - **Docs:** EB8, CC9, MP9, DK6, CT11 and EN12 as one batched step at the end of M2.
4. **Bugs** ([tracker](bug-tracker.md)), fix step **BF1** once the user's engine bugs are in:
   - BUG-002 (S2): the forecast's crit ignores Stance.
   - BUG-004 (S2): an enemy with an attack intent moves and doesn't attack; details still asked of the user.
   - BUG-005 (S4): unit detail shows the type id.
   - BUG-006 (S3): NetLog raises an engine error once the peer is cleared.
   - BF1 also removes UI11's confirmed `# ASSUMPTION` markers (P07 question 36).
5. **M2's exit:** playtest a full M2 map set, folding in the deferred M1 tuning pass.
6. **Later:** one public `Pathing.path_to` (P07 question 15 d); vision updates for the ideation thread.

**Open questions for the user:** none.

## Scope guardrails

**In the MVP** (game-vision.md): one act, one faction (Mercenary), one commander (the Drengr), Normal only, the 14 MVP unit types, 10 enemy classes, 4 mini-bosses, the Powder Baron, the full item, weapon, heirloom, rune and event pools, the darkness, solo and co-op on parallel maps, statistics recording and the Waystation war table.

**Out of the MVP** (stop and ask before any plan touches these): meta progression (unlocks, the difficulty ladder, almanac, Hall of Heroes, run history, achievements, the other Waystation stations), endless runs and later acts, more bosses, the Mage Tower and Kingdom factions and the other commanders, status effects and status staves, the Ballista and War Drum, darkness extras beyond the Brazier, support weapons beyond staves, one- and two-handed weapons, unique equipment, more enemy factions, units with convoy access, shared and hybrid co-op battles, the dev console, rune prefixes (P03 reserves `data/prefixes/runes/`), directional target shapes (line, cone).

**Focus rules**

- A plan that grows past its row's scope splits into a new row here, not a bigger plan.
- A gameplay value with no basis in the design docs or `Godot_FE/` is a design question, not an implementation choice (CLAUDE.md §1).
- **Every new UI and feature works on keyboard and mouse and on a controller from the start** (user, November 7, 2026): pad bindings, focus navigation and glyph hints in the same step.
- **Every UI element is its own `.tscn`** with documented `@export`s, so it can be edited by hand; every prompt says so.
