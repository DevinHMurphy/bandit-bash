# Map Objects

The things placed on a map that units interact with: `Godot_FE/`'s map entities, carried over and
made neutral, plus new objects. Any unit, player or enemy, can use them to change the battlefield,
and the [ruthless AI](enemy-roster.md#ruthless-ai) uses them as hard as the player can.
[game-vision.md](game-vision.md#combat-maps) wins where the two differ.

**Status:** second pass, October 22, 2026, rebuilt from `Godot_FE/scripts/combat/entities/` and the
entity data of its levels. Every number is to be tuned in playtesting.

**Objects are not terrain.** Terrain is the ground itself: its movement cost, avoid, DEF/RES and
healing (forts, thrones, forests; see [unit-roster.md](unit-roster.md#movement-and-tags)). An
object sits on a tile and is used, broken or triggered. Terrain ideas that came up here are listed
under [Terrain candidates](#terrain-candidates).

## The short version

- **Neutral:** every object works for whoever uses it. None belongs to a side.
- **Using one is the unit's action** for the turn (after moving), unless it is triggered by damage.
- **Breakable objects** have HP, Defense and Resistance like `Godot_FE`'s entities: units attack
  them, they never counter, and splash damages them.
- **Telegraphed:** hovering shows an object's area and effect; if an enemy can use one this turn,
  the effect shows in the danger zone and the enemy's intent.
- **Placed from candidates:** maps author candidate spots; the run's seed picks which objects
  appear, like darkness sources.

## Carried over from Godot_FE

| Object | `Godot_FE` | Here |
|--------|-----------|------|
| **Chest** | Key opens it; loot rolled at load | A lockpick opens it; loot rolled from the run's seed. A Cutthroat can open one too and carries its loot until defeated, then drops it, so chests become a race |
| **Door** | Key or lever opens it; can span several tiles | Same. Locked doors block the darkness. Doors on a lever group can also be closed again (below) |
| **Lever** | Opens every door in its group | **Toggles** its group open or closed, for anyone who pulls it: both sides can seal or open a route |
| **Searchable** | "Search": house, food shelf, book shelf, weapon rack, each with a loot table | Keeps all four. A **house** gives 15–25 gold or one consumable, plus the personal-XP bonus (the vision's "looting houses"); a **food shelf** gives an [ingredient](items.md#consumables); a **book shelf** gives a rune; a **weapon rack** gives a weapon. One search each; a Cutthroat can search one first to deny it, and drops what it took when defeated |
| **Debris** | Wooden (25 HP, 0 DEF/RES) or stone (35 HP, 5 DEF/RES); destroyed by attacking it | Same values. Destroying it restores the terrain beneath and opens a lane for both sides. The darkness erodes it |
| **Breakable wall** | Cracked wall; being replaced by debris | Folded into debris |
| **Passage** | "Movement" entity, declared but never built: moves a unit to a target tile | Built: a linked pair (stairs, a tunnel, a ladder). A unit on one end can use it to arrive at the other end, if it is free. Both sides can take the shortcut |

## New objects

| Object | How it's used | Effect |
|--------|---------------|--------|
| **Powder Keg** | Breakable (10 HP, 0 DEF/RES): any hit, any splash, or the darkness eroding it | Explodes: 5 splash damage to every unit within 1 tile, friend or foe, and destroys adjacent breakables. A keg caught in another keg's blast explodes too, so kegs can chain |
| **Ballista** *(after the MVP)* | A unit next to it uses it | A siege attack: 8 damage, Power, physical, range 2–5, 70 Hit, ignoring the user's Might and weapon; 3 shots per map. It rolls to hit, takes part in the triangle and damage stages, and can crit an Exposed target |
| **War Drum** *(after the MVP)* | A unit next to it uses it | Every unit within 2 tiles, friend or foe, gains +2 damage until the end of the next phase; then silent for 2 turns |
| **Brazier** | A unit next to it lights or douses it | While lit, tiles within 2 tiles never deepen past Dusk. It is [the darkness](the-darkness.md)'s torch (decided October 23, 2026) |

The Ballista and War Drum are held until after the MVP (decided October 23, 2026) to keep the
number of map rules down: the War Drum duplicates the Warcaller's War Horn, and the Ballista is a
second attack system. Their rules below stay for later.

## Rules

- **Using** an object (Chest, Lever, Searchable, Passage, Ballista, War Drum, Brazier) takes the
  unit's action for the turn, after moving. Chests need a lockpick in the Pouch; Cutthroats, the only
  enemies that loot, don't.
- **Breaking** an object (Debris, Powder Keg) is an attack on it: the attacker hits its Defense or
  Resistance, the object never counters, and splash damages it.
- **Explosions are splash damage:** no hit roll, Mitigation or crit, no Stance loss; Block absorbs
  them.
- **The darkness:** Debris and Powder Kegs are breakables, so darkness contact counts down and
  breaks them (a keg becomes a timed bomb). Locked doors don't erode. A lit Brazier holds its area
  at Dusk.
- **Trigger:** using an object fires **Object used**, so traits and heirlooms can reward it later.
- **Co-op:** each player's parallel map has its own copy of every object.

## Enemy AI

- Enemies use objects by the same ruthless rule: any kill first, friendly fire ignored. An enemy
  will blow a keg next to its own pack to kill one player unit.
- Enemies race the player for value: they pull levers to seal routes and douse Braziers (and,
  after the MVP, man the Ballista). Only **Cutthroats** loot: they open chests and search
  searchables to deny loot, and drop what they took when defeated. Enemies have no drops of their
  own.
- An enemy's intent shows the object it plans to use and what that will hit.

## Terrain candidates

Decided since: the **spiked wall** is terrain (see [unit-roster.md](unit-roster.md#movement-and-tags)
and Shove in [game-vision.md](game-vision.md#combat)): a wall no unit can enter that deals 4 damage
to a unit shoved into it. Shoving one unit into another also bumps both for 2 (see Shove).

These came up as objects but are terrain, so they belong with the terrain table, not here:

- **Watchtower:** +20 avoid and +1 bow range; costs 2 movement to enter (fliers 1).
- **Healing spring:** heals at Phase Start like a Fort; possibly limited uses.
- **Rope bridge:** bridge terrain that can be cut, becoming impassable to non-fliers. It changes
  terrain when triggered, like `Godot_FE`'s interactable tiles (`changes_terrain`), so it may need a
  lever or breakable on it.

## Values (first pass, to tune in playtesting)

| Value | First pass |
|-------|------------|
| Wooden / stone debris | 25 HP, 0 DEF/RES / 35 HP, 5 DEF/RES (`Godot_FE`) |
| Powder Keg | 10 HP; 5 splash damage within 1 tile |
| Ballista | 8 damage, Power, physical, range 2–5, 70 Hit, crit 0, CritX 3, 3 shots per map |
| War Drum | +2 damage within 2 tiles until the end of the next phase; 2-turn cooldown |
| Brazier | Holds tiles within 2 tiles at Dusk at most |
| Objects per map | 1–3 notable objects, plus any number of debris |

## Open questions

- **Action economy** is decided ([game-vision.md](game-vision.md#combat)): move, then one action;
  using an object is that action.
- **Shove** is designed as a first pass in [game-vision.md](game-vision.md#combat): push an adjacent
  unit by its Shove distance (1 tile by default), with fairness rules (it costs the action, only onto
  legal tiles, only Exposed foes, once per phase), bumps into units (2) and spiked walls (4).
- **Keg chains** (decided October 23, 2026): no chain limit; maps author at most 3 kegs (the Powder
  Baron's arena excepted), so a chain is a set piece, not a map wipe.
- **Enemy looting** (decided October 23, 2026): Cutthroats only.
