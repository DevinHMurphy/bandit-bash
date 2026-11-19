# Bandit Bash docs

**Start with [the orchestrator](plans/game-orchestrator.md):** where the project is and what's next.

| Folder | What's in it | When to read it |
|---|---|---|
| [design/](design/) | What the game is. [game-vision.md](design/game-vision.md) is the master document; the rest cover one system each | Read the section for the feature at hand, not the whole file |
| [plans/](plans/) | One plan per system (`YYYY-MM-DD-<slug>.md`), the [orchestrator](plans/game-orchestrator.md) and the [bug tracker](plans/bug-tracker.md) | The plan's Approach and its step's row |
| [plans/decisions/](plans/decisions/) | Each plan's answered questions, by number | Look up the number you need: `grep -n "^\| 34 \|" P07-combat-ui.md` |
| [plans/orchestrator/](plans/orchestrator/) | Gates and graphs, open design items, the old change log | When checking a gate or drafting a plan |
| [standards/](standards/) | The plan template and worked examples | When writing a plan |
| [briefs/](briefs/) | One-off design briefs | When a plan points at one |

**How-to references** (living docs that describe the code as it is):

| Doc | Covers |
|-----|--------|
| [design/event-bus.md](design/event-bus.md) | Facts, buses, the effect engine, triggers and the rules-code contract |
| [design/map-authoring.md](design/map-authoring.md) | Making a combat map: layers, markers, ids, the generator, the map check, darkness sources, pools |
| [design/content-authoring.md](design/content-authoring.md) | Adding a unit, item, heirloom, curse, rune, prefix, shape or enemy, and the content test |

Coding rules are in `CLAUDE.md` and `.claude/rules/` at the repo root.

**Plan IDs:** P00 save system · P01 event bus and effects · P02 combat core · P03 content · P04 combat map · P05 enemies and AI · P06 the darkness · P07 combat UI · P08 campaign · P09 events · P10 net · P11 co-op · P12 statistics · P13 RNG · P14 project organization.
