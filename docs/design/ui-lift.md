# UI Lift

The scope for making the game's UI ready for more playtesters: how it looks, how a combat reads,
and how a won combat hands out its rewards. M2's goal was a "functional UI" (P07 left art, audio
and animation beyond tweens out of scope); this lifts it before M2 is marked complete.

**Status:** scoped November 18, 2026 (user; every question answered as recommended, see
[Decisions](#decisions)). The steps are plan **P15 UI lift**, an M2 exit item on the
[orchestrator](../plans/game-orchestrator.md); DK7 belongs to P06. The darkness damage rule change
is written into game-vision.md and the-darkness.md (November 19, 2026).

## Where it stands

Found November 18, 2026, in `bandit-bash/`:

- **No shared look.** `project.godot` sets no theme, font or base resolution (Godot's default
  1152×648, `canvas_items` stretch). The one theme, `ui/theme/battle_theme.tres`, covers the
  battle; 53 scenes set their own overrides.
- **Art.** 7 unit sprites (M1's) in `assets/sprites/units/`, the control glyphs, and the rune icons
  (UI14). The board's map objects, intents and signature moves are text glyphs (RF-008).
  `Godot_FE/resources/sprites/` has reusable art: units, sheets, tilemaps, UI frames, item and
  campaign-map icons, damage icons.
- **The fact log** (`ui/battle/hud/fact_log.gd`) is debug-grade by design (P07 question 11): one line
  per batch from `CombatSession.describe_batch`, ids and all, written before the batch plays, so
  it runs ahead of the board.
- **Unit detail.** `UnitDetailPanel` (UI11) exists, minus Godot_FE's XP and growths. Mouse users
  can't reach it: the left unit panel follows the hovered unit, so moving the mouse to its Details
  button changes or hides the panel ([BUG-015](../plans/bug-tracker.md)).
- **Results** (`ui/campaign/combat_results_screen.gd`, P08 RN4–RN5) is its own screen showing
  grades, gold, XP, level-ups and the item pick all at once, built from the saved run so a quit
  and Continue shows the same.
- **Heirlooms** are built as data and effects (CT9: 35 pool heirlooms, the starting and commander
  ones, 10 curses) and work in battle, but show only as effect text in the unit detail panel. No
  screen lists the army's heirlooms, and `HeirloomDefinition` has no icon. Most ways to gain one
  arrive later: the run-start offer (P08 RN6), Treasure and the key combat's heirloom (RN7), the
  Armory (RN8), events (P09).
- **The darkness** changes in one step at the end of every turn (after the enemy Phase End, before
  the player Phase Start; the-darkness.md, The darkness step). Its damage lands at each side's own
  Phase End. Playback shows the spread with no pause or banner of its own.

## Steps

| Step | What | Plans touched | Needs |
|------|------|---------------|-------|
| **UL0 Style guide** ✅ ([ui-style.md](ui-style.md), November 18, 2026) | `docs/design/ui-style.md`: palette, two fonts, icon style, panel and button styles, spacing, focus look on a pad, base resolution and scaling | — | The questions below |
| **UL1 Shared theme** ✅ (merged November 18, 2026; UL1F merged with UL4) | One project theme with colour and size tokens and the fonts; the 53 scenes' overrides moved onto it; base resolution and scaling set | P07, P08 screens | UL0 |
| **UL2 Board art** | Terrain from Godot_FE's tilemaps; a sprite for every unit and enemy class (reused, or one consistent placeholder); map objects, intents and signature moves as icons (most of RF-008); a lit keg's fuse count (RF-021) | P07, P04 | UL1 |
| **UL3 HUD and unit detail** | A layout pass on the unit panel, forecast, turn bar, hint bar and menus, checked at the target sizes; the forecast shows every hit of a multi-hit attack, not only the first (EN18: later hits on a stripped Braced unit deal more; P05 question 45); the [unit detail pop-up](#unit-detail-pop-up); BUG-015. From UL1 and UL4: `danger` as text fails contrast (2.79:1 on `panel`: HudWarning, the turn counter past par, the enemy name, the enemy phase banner); the rune Discard button is about 18 units tall (floor 32); the Saved indicator overlaps the rune bar's third slot; tooltips lack the 320-unit width and name, body and footer | P07 | UL1 |
| **UL4 Event log** ✅ (merged November 18, 2026, with UL1F) | The [event log](#event-log) replaces the fact log. From UL1: `darkness` and `danger` fail contrast as text (2.06:1 and 2.79:1 on `panel`), so log lines need a lighter text form or an icon beside the colour | P07 | UL1 |
| **UL5 Victory sequence** ✅ (merged November 19, 2026) | The [staged victory overlay](#victory-sequence) replaces the Results screen | P08, P07 | UL1 |
| **UL6 Combat feedback** | Hit, crit, Block and Stance-break feedback, floating numbers, phase banners, playback pacing; tweens and existing art only | P07 | UL2 |
| **UL7 Campaign and menu pass** | The campaign map, level-up, item pick and placement, start, save and options screens on the new theme. From UL1: titles and headings are still body text and Continue is not yet a primary button (the styles exist); map nodes are 26×26 (floor 32); sliders show focus only by a brighter grabber | P08 | UL1 |
| **UL8 Heirloom bar** | The [heirloom bar](#heirloom-bar) on every campaign screen and in battle | P07, P08, P03 (an icon on heirlooms and curses) | UL1 |
| **DK7 Darkness phase** (P06, not UI) | The [darkness phase](#darkness-phase) | P06, P07 | — |

**Out of scope** (M5 polish or later): new art made from scratch, unit animations, audio, an
exchange cut-in, tutorials (P21). P08's shop and event screens (RN6+) are built on the new theme,
so they need no second pass.

**Order** (two prompts at a time; content steps take the other slot where
a pair is not listed):

1. UL0 with the user: done November 18, 2026 ([ui-style.md](ui-style.md)).
2. UL1: merged November 18, 2026. Its follow-up UL1F puts DK7's turn bar and darkness overlay on the tokens (the phase banner's colours were moved at the merge) and clears the theme test's exempt list.
3. UL4 with UL1F: merged November 18, 2026.
4. UL3 beside UL5: issued November 19, 2026; UL5 merged November 19, 2026.
5. UL8 beside UL2.
6. UL6 beside UL7.

BF1, P09 EV1 and P08 RN6 take the next free slots between waves (M3 steps that touch no UI-lift screen); CT11 joins the docs batch.

## Heirloom bar

The army's heirlooms, always in view, in the manner of a roguelike relic or item bar (the user's
references, November 18, 2026: relics under the top bar, items in a row).

- **Where:** an HBox directly below the top header: the campaign screens' run header and the
  battle HUD's top strip. One shared `heirloom_bar.tscn`; each heirloom is its own
  `heirloom_icon.tscn`.
- **Look:** each icon sits at low opacity at rest and comes to full on hover, focus or when it
  fires. Curses follow the heirlooms after a divider, tinted apart. A repeated heirloom shows once
  per copy.
- **Tooltip** on hover or focus: name, tier, effect text (the same generated text as everywhere
  else), and its counter where it has one ("every 7th").
- **Live in battle:** a counter shows as a small number on the icon (`COUNTER_CHANGED`), and the icon
  pulses when it fires (`EFFECT_ACTIVATED`), with the matching event log line (UL4).
- **Input:** a key and pad button move focus onto the bar, as the rune bar does (UI14); left and
  right move between icons; Back leaves.
- **Data:** an `icon` export on `HeirloomDefinition` and `CurseDefinition` (P03 content), with
  placeholder art per the art decision; a missing icon falls back to one generic mark.
- **Co-op:** each seat sees its own heirlooms. Showing teammates' bars waits for P11.

## Event log

Replaces the debug fact log with a log a player reads.

- **A scrollable panel**, collapsible, newest line at the bottom. It follows new lines unless the
  player has scrolled up. A header line for each turn and phase ("Turn 3 · Player phase").
- **Written from facts as they play,** so a line appears when the board shows it, not before.
  Names, not ids. Tiles as (x, y).
- **What it tracks:**

  | Group | Lines (from `CombatFact.Kind`) |
  |-------|--------------------------------|
  | Combat | Attacks and counters with hit, miss, crit and damage ("Drengr attacks Brute: 7 damage, crit"); splash, bump, spike and darkness damage with their source; heals and staves; shoves; Exposed; defeats |
  | Movement | `UNIT_MOVED` ("Archer moved (3, 4) → (5, 4)"); spawns; reinforcements incoming and arrived |
  | Events | Map objects used and changed (chest opened, door opened, lever pulled, keg exploded, a Cutthroat looting an item); items used; weapon swaps; runes cast and discarded; waits |
  | Effects | `EFFECT_ACTIVATED` (a trait, heirloom, curse or signature move by name, and what it did); modifiers gained and expired; Block gained and lost; Stance changes; the darkness advancing |

  The MVP has no status effects (game-vision.md); modifiers, Block, Stance and Exposed stand in
  for them.
- **Filters** by group, and keyboard, mouse and pad scrolling from the start.
- **Not saved.** A resumed battle starts the log with one "Battle resumed" line.
- The raw debug log stays reachable from the debug panel.

## Unit detail pop-up

- **The bug (BUG-015):** the left unit panel follows hover, so its Details button can't be clicked.
- **Opening it:** right-click a unit, or the unit-detail key or pad button (UI11's binding), opens
  the pop-up for that unit; the unit panel stops following hover while the mouse is over it, so
  its button works too.
- **The pop-up:** Godot_FE's `ui/battle_prep_new/unit_detailed_info/` layout as the basis, graybox:
  a centred modal over a dimmed board.
  - **Stats:** base stats and combat values, each modifier shown as +x or −x with its source.
  - **Gear:** weapon with profile, the stowed weapon, Equipment, Pouch.
  - **Traits and heirlooms** as effect text.
  - **Player units:** level, XP and growths (UI11 left these out).
  - **Enemies:** intent and target rule, prefix, signature move and its cooldown.
  - Previous and next unit without closing it.

## Victory sequence

When a combat is won, the board stays and a black overlay fades in over it. Three stages, each
moved on with Continue:

1. **Grade:** the combat's grades and what they earned.
2. **Recap:** each unit's performance (kills, damage dealt and taken, heals, the Standout) and its
   XP bar filling, then each level-up in turn.
3. **Rewards:** a list of reward rows, one per reward (an item pick, the key combat's heirloom,
   later runes); choosing a row opens its picker, and a taken row leaves the list. A Leave button
   goes to the campaign map, asking first while rewards are left.

The layout reference is the user's screenshot (November 18, 2026) of a roguelike combat-rewards
screen: a centred reward list over the darkened scene, one row per reward with its icon, a skip
button. Bandit Bash builds its own look on the UL0 style.

- **Resume:** results come from the saved run, as today. A quit at any stage and Continue reopens
  the sequence over a dark backdrop (the battle is gone), with taken rewards gone from the list.
- **A loss** keeps its own screen, restyled in UL7.

## Darkness phase

Not UI, and partly a rule change. Two parts:

- **(a) A phase you can see.** When the darkness step does anything (a wave released, the creep,
  breakables breaking), it gets a "Darkness" banner and an entry on the turn bar, and the spread
  plays tile by tile at a set pace, skippable like other playback. No rule changes.
- **(b) Its damage moves into that phase** (decided: [decision 5](#decisions)). All darkness happens at once:
  damage first, from the layer each unit stands on (the layers the move preview showed), then the
  creep. Both sides take it at the same moment, once per turn. What changes from today:
  - player units in the dark take damage after the enemy phase instead of at the end of their
    own, so an enemy shove can move them in or out first;
  - the-darkness.md's "a unit that ends its side's phase on a dark tile takes damage" becomes "a
    unit standing on a dark tile when the darkness phase begins";
  - "Phase End, while on Abyss" effects still read the tile at Phase End; the Darkness damage
    taken trigger is unchanged.

  A rule change: the-darkness.md and game-vision.md change through the ideation thread. Logged as
  [RF-014](rebalance-and-features.md).

## Open questions

None. The questions as asked, kept for reference:

1. **Art source:** reuse Godot_FE's art wherever it fits and use one consistent placeholder style
   for the rest (recommended), or stop for new art (which would push the lift past M2)?
2. **Target sizes:** 1920×1080 desktop and the 1280×800 Steam Deck (recommended)?
3. **Combat feedback (UL6) and the campaign and menu pass (UL7) in M2?** Recommended yes:
   playtesters judge the whole run.
4. **Gold in the rewards list:** gold is already granted when the combat ends (RN3's save order),
   so show it as a collected row in the Grade stage (recommended), or make it a row the player
   clicks (cosmetic only)?
5. **The darkness's damage (b):** move it into the darkness phase, damage before the creep
   (recommended: one moment to watch, and the move preview stays true), or keep it at each side's
   Phase End and build only (a)?
6. **Opening the unit detail pop-up:** right-click a unit plus the existing key and pad button
   (recommended)?

## Decisions

Decided by the user, November 18, 2026: every question as recommended.

1. **Art:** Godot_FE's art wherever it fits; one consistent placeholder style for the rest. No new
   art blocks the lift.
2. **Target sizes:** 1920×1080 desktop and 1280×800 Steam Deck.
3. **UL6 and UL7 are in M2.**
4. **Gold** shows as already collected in the Grade stage, not as a reward row.
5. **The darkness's damage moves into the darkness phase,** damage first (from the layers units
   stand on), then the creep; both sides at once. The-darkness.md and game-vision.md change through
   the ideation thread.
6. **The unit detail pop-up** opens by right-clicking a unit, plus the existing key and pad button.
7. **A heirloom bar** (UL8) below the top header on campaign screens and in battle: low-opacity
   icons with a tooltip on hover (user, with the questions).
