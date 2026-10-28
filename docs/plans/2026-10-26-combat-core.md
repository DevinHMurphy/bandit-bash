# Plan: Combat Core
**Date:** October 26, 2026
**Status:** **Approved** October 26, 2026, after review (questions 9–12 answered, seven fixes
applied). In progress: CC1–CC5 implemented October 27, 2026 (with P01 fixes F9–F12; 428 headless combat tests pass); CC6 waits on P01
EB6. Orchestrator ID
**P02** ([game-orchestrator.md](game-orchestrator.md)).

The rules of a fight: turns and phases, the action economy, the exchange (Attack Speed, bonus
turns, attacks per turn, hit, crit, the damage stages, Block, Stance), Shove, staves, Pouch items,
weapon swaps, runes and Wait, plus the forecast and the AI's exchange summary. Everything here is
pure rules code on top of the event bus plan ([P01](2026-10-23-event-bus-and-effects.md)); maps,
enemies, the darkness and the UI plug in through the interfaces this plan defines.

## Problem

`bandit-bash/` has no combat. P01 EB1 (facts and buses) is built
(`scripts/bus/combat_fact.gd`, `combat_bus.gd`); the effect engine (EB2–EB4) is gated on this plan
because the combat core is its first and heaviest consumer. Gaps found while drafting:

- `CombatFact` can't say whose phase a `PHASE_START` / `PHASE_END` is (`combat_fact.gd:TOD-001`).
- `CombatFact.Kind` has no fact for a Stance change below Exposed, the Phase Start Block and Stance
  refresh, Block lost outside damage, a Pouch item use, a weapon swap, a rune cast or a Wait, so a
  client mirror can't follow them (P01: "every state change emits a fact").
- The vision's mitigation formula (game-vision.md, Damage) leaves out the terrain DEF/RES bonus
  that unit-roster.md's terrain table gives a unit standing on a tile.
- `Godot_FE`'s exchange (`Godot_FE/scripts/combat/controllers/combat_exchange.gd`) mixes pure math
  with an `await` sequencer, reads the defender's specials from the attacker's inventory (`:463`),
  rolls on the global RNG, and grants bonus turns only above a strict threshold (`:470`).

## Open Questions

| # | Question | Options | Recommendation | Answer |
|---|----------|---------|----------------|--------|
| 1 | How combat meets the grid (P04 owns maps) | Narrow interface + test stub / P02 builds a basic grid | Interface + stub | **Answered October 26, 2026:** a narrow `CombatGrid` interface defined here, a stub for tests; P04 implements it. |
| 2 | Which actions P02 owns | All non-map actions / exchange and staves only | All non-map | **Answered:** Attack, staves, Shove (bumps, spikes, oil), Pouch items, weapon swap and Sidearm, runes and Wait. Map objects, chests, doors and searchables stay with P04. Content stays with P03. |
| 3 | Slots other plans fill in the turn loop | Ordered extension points / hard-coded calls | Extension points | **Answered:** P02 owns the loop and its order, with named hooks that P04, P05 and P06 register into. |
| 4 | Bonus-turn thresholds | Vision 4/10/18 cap 3 / `Godot_FE` 5/11/19 / vision uncapped | Vision, cap 3 | **Answered (changed from the recommendation):** 4, 10, 18, then each step 2 wider than the last (28, 40, 54…), **no cap**. `Godot_FE`'s strict check is not ported. The vision is updated. |
| 5 | Rounding in the damage stages | Exact then round once / round each stage / floor | Exact, round once | **Answered:** stages 1–4 keep exact values; stage 5 rounds once, halves up, never below 0. The triangle bonus keeps its own rule; darkness keeps floor, minimum 1. |
| 6 | Crit roll | One roll / 2RN | One roll | **Answered:** a single d100, as in `Godot_FE`. Hit stays 2RN. |
| 7 | Who counters; staff targets | `Godot_FE` rule / staves target freely | `Godot_FE` rule | **Answered:** a defender counters only if its weapon's range covers the distance; a unit holding a staff never counters. Heal staves target only damaged allies; Block staves any ally. |
| 8 | Shove legality | Only if it does something / always | Only if it does something | **Answered:** offered only if the target would move at least one tile, or bump a unit, or hit a spiked wall. |
| 9 | When Unit Turn Start fires | Before moving / after moving / at Phase Start | Before moving | **Answered October 26, 2026 (changed from the recommendation):** in the Phase Start window, for each unit of the side, after the refresh and Phase Start effects and before the side gets control, as `Godot_FE`'s beginning phase did (`CController.gd` `beginning_phase_processing`: terrain effects, then each unit's turn-begin specials, then control). Vision and effect-triggers.md updated. |
| 10 | Extra Stance loss on a fully countered hit (Breaker, Breaker's Maul) | Only if damage got through / always | Only if damage got through | **Answered:** extra Stance loss adds to stage 8's loss, which happens only when damage reached Block or HP. |
| 11 | When Unit Turn End fires, now that Unit Turn Start is at Phase Start | After the unit's action (unchanged) / each unit in the Phase End window | Phase End window | **Answered October 26, 2026:** for each unit of the side in the Phase End window, mirroring Unit Turn Start, so a unit's "turn" is its side's phase and every unit gets both triggers. Effects like Radiance count units at their final positions. Vision and effect-triggers.md updated. |
| 12 | At Phase End, do queued effects resolve before darkness damage? | Effects first / darkness first | Effects first | **Answered October 26, 2026 (approval check):** the reaction queue drains after Unit Turn End and before the darkness hook, so Phase End heals and Unit Turn End Block land first and a heal can save a unit from that phase's darkness; it drains again after. |
| 13 | How `CombatState` answers `SandboxState.walking_distance()` ("within N" was walking distance in effect-triggers.md, but `CombatGrid` offered only grid `distance` and listed it for "within N") | Add `walking_distance` to `CombatGrid` / compute it in `CombatState` / grid distance only | **Add `walking_distance` to `CombatGrid`**, P04 implements it. | **Answered October 27, 2026 (user):** add it, and keep two terms the effect picks (P01 question 38): "within N tiles" is grid `distance`, ignoring walls; "within N movable tiles" is `walking_distance(a, b, movement_type)`, the steps the source could take with its own movement type. `CombatState.walking_distance(from_id, to_id)` passes the source's movement type. The stub returns grid distance on its open rectangle. **Reversed October 27, 2026 (user, P04 question 12):** the movable term is cut; `walking_distance` is removed and every "within N tiles" uses `distance`. |
| 14 | How a staff with no range is used (Everwall: "every ally within 3 tiles of the user", range "—" in weapons.md; found building CC5) | No target, centered on the user / target self | **No target:** the command names only the staff, and its area centers on the user. CC6's command and validator. | **Answered October 28, 2026 (user):** a staff or weapon with no range doesn't exist. A staff that works around its user has **range 0**: the user is its only target, so the player picks no target (the command fills in the user), and its area centers on the user. Everwall is range 0. Content without a range fails the content test (P03, EB5); attacks (weapons and attack staves) start at range 1. |
| 15 | Whether defenders can change the damage they take (found reviewing CC2–CC5: stage 4 read only the attacker's multipliers) | Two-sided stages / attacker only | **Two-sided:** every damage stage reads the attacker's bonuses and the defender's changes to damage taken; stage 4 adds `INCOMING_MULTIPLIERS`; `MITIGATION` may go negative; P01's `WhileAttackCondition` makes them conditional ("×2 against Beasts", "×2 from magic"). | **Answered October 27, 2026 (user):** as recommended; architecture must allow these for future content. P01 question 39, fix F12. |
| 16 | Where combat rule bases live (found reviewing CC2–CC5: both Multipliers 1, effectiveness 3 and Shove distance 1 are set by `CombatState.load_bases()` at placement, so a unit not placed through `place_unit` reads 0) | A per-key default-base table the stat sheet falls back to / keep them in `load_bases` | **A default-base table** for rule constants, as P01 fix F7 did for campaign percents, so no read depends on placement. Weapon numbers stay in `load_bases`. | **Answered October 27, 2026:** as recommended: one constants table the stat sheet falls back to. Built in the warnings fix-up (`feature/gdscript-warnings`). |

No open questions remain. Derived facts other plans must respect are under
[Notes for other plans](#notes-for-other-plans).

## Scope

**In scope**

- Combat state for one map: units' combat state, sides and seats, the turn counter and phase.
- The `CombatGrid` interface and a stub grid for tests.
- The turn and phase loop, its ordered hooks, Block and Stance refresh, terrain healing, end turn
  per seat, and the enemy phase as one command.
- Commands and validation: the atomic unit turn (path + action), end turn, cast rune; ownership,
  per-map phase end and stale-forecast rejection (P01 command contracts).
- The exchange: range and counters, Attack Speed and bonus turns, attacks per turn and Parry, 2RN
  hit, the triangle, effectiveness, crits, the eight damage stages, Block, Stance and Exposed,
  lifesteal, defeat.
- Splash damage resolution (the rules every splash source uses: Cleave, Trample, kegs, bumps).
- Shove: validation, step-by-step movement, bumps, spiked walls and oil sliding.
- Staves (Block, heal and attack), Pouch item use, weapon swap and Sidearm, runes, Wait.
- The player forecast and the AI's `ExchangeOutcome`, both by sandbox simulation (P01).
- The combat value keys, permissions and fact kinds these rules need.
- The `combat_state` save section for one session.

**Out of scope** (owner in brackets)

- Movement costs, pathing, deployment, terrain data, objectives, reinforcement points, map objects,
  map authoring [P04]. P02 validates a path only through `CombatGrid`.
- Enemy decisions, intents and the danger zone [P05]; the darkness [P06]; the forecast panel, HUD
  and animations [P07].
- XP, the Standout, grade bonuses, level-ups, permadeath bookkeeping and the battle bridge [P08].
- Content: unit types, traits, weapons, staves, items, runes, heirlooms [P03].
- Multiplayer transport, rejoin delivery and the per-map battle save format [P10, P11]. P02 keeps
  seats and per-map phases correct so P11 needs no rule changes.
- Status effects (post-MVP).

## Design Basis

- game-vision.md: **Combat** (action economy, turn phases, exchange, bonus turns, attacks per turn,
  Parry, hit, damage stages, damage, Block, Stance and Exposure, the triangle, Shove), **Weapons and
  equipment** (staves, Pouch items, stowed weapons), **Run-wide resources** (runes), **Army** (HP
  carries over).
- unit-roster.md: Stance values, traits (effect text), Sidearm, the terrain table (avoid, DEF/RES,
  healing).
- weapons.md (staves), items.md (potions, Guard Tonics, Elixir, stat boosters, ingredients, runes),
  effect-triggers.md (triggers, splash, Shove distance, position terms), effects-system.md.
- living-labyrinth/master-ideation.md: Combat Exchange, Block, Stance, Exposure and Critical Hits,
  the Weapon Profile Triangle. The vision supersedes it everywhere they differ.
- Nothing this plan needs is under "Still open" in game-vision.md.

## Legacy Behavior

Read: `Godot_FE/docs/systems/06_combat_core.md`, `07_combat_math_and_exchange.md`,
`Godot_FE/scripts/combat/controllers/combat_exchange.gd` (`calc_unit_turn_count`, `perform_hit`),
`Godot_FE/combat/CController.gd` (`get_potential_shove_targets`, `perform_shove`),
`Godot_FE/combat/Combat.gd` (`Shove`).

| Godot_FE file | Behavior | Keep / Change / Drop | Reason |
|---------------|----------|----------------------|--------|
| `combat_exchange.gd` FR-MATH-1 | Hit is the average of two d100 compared `<` chance (2RN) | Keep | game-vision.md "2RN, carried over"; now through a roll source |
| FR-MATH-2 | Crit is one d100 | Keep | Question 6 |
| FR-MATH-2 | Crit any time, `crit − crit_avoid` | Change | Vision: only against an Exposed target; base 25; no crit avoid |
| FR-MATH-3 | Damage = attack + triangle ±2 + effectiveness − DEF/RES | Change | Vision's eight damage stages; triangle ±¼ weapon damage (min 1) |
| FR-MATH-4, `:470` | Bonus turns when the AS gap is **strictly greater** than 4, 6, 8 (5, 11, 19), uncapped | Change | Question 4: gap of 4 or more, 10 or more, 18 or more, then each step 2 wider, uncapped. The strict test reads as an off-by-one bug |
| FR-MATH-4 | Each turn repeats `attacks_per_combat_turn` | Change | Vision: `max(1, AtkX − Parry)` |
| FR-MATH-5 | Attacker, defender, then the faster unit's extra turns; ends on the first death | Keep | Vision Exchange |
| FR-MATH-6 | A defender counters only if its weapon's range covers the distance | Keep | Question 7 |
| FR-MATH-7 | Triangle by weapon type, ±20 Hit, ±2 damage | Change | Vision: by profile, ±15 Hit, ±¼ weapon damage |
| FR-MATH-7 | Effectiveness ×3 weapon damage | Keep | Vision ("effectiveness ×3" kept) |
| FR-MATH-8 | Healing never rolls to hit | Keep | Applies to every heal and Block staff |
| FR-MATH-8 | Staves lose durability per use; healer gets 20 XP | Change | Per-map uses (weapons.md); XP is P08's personal bonus |
| FR-MATH-9 | Durability per strike; Devil Reversal; heal on exchange end | Drop | No per-strike durability; no such content |
| FR-MATH-10 | XP inside the exchange | Drop (moved) | Vision's shared + personal XP, an observer in P08 |
| `:463` | Defender's specials read from the attacker's inventory | Drop | Bug; every value comes from `session.stats()` |
| FR-MATH-13 | Global RNG; `await` inside resolution | Change | Roll sources and pure resolution (P01) |
| 06 FR-CMB-4 | Minor and major action budgets; Trade | Change | Vision: move, then one action; no trading |
| `Combat.gd:720` | Shove is free (no action budget), always one tile | Change | Vision: costs the action, Shove distance, Exposed foes only, once per phase |
| `CController.gd:549` | Shove offered only with a free landing tile | Change | Question 8: also offered when it bumps a unit or hits a spiked wall |

**Tuning values carried over:** `ExtraTurnConstant` 4 and its +2 spacing (`combat_exchange.gd:467–473`);
effectiveness ×3 (`07` FR-MATH-7); default CritX 3.0 (`WeaponDefinition.gd`
`DEFAULT_CRITICAL_MULTIPLIER`). Every other value comes from the design docs.

## Approach

### Shape

```
CombatSession (P01 EB6)
├── CombatState            units' combat state, sides, seats, turn, phase      plain data
├── CombatGrid             interface (P04 implements; StubCombatGrid in tests)
├── PhaseRunner            the turn loop and its ordered hooks
├── CommandValidator       ownership, legality, per-map phase end, stale forecast
└── resolvers (pure)       Exchange, Damage, Shove, Staff, ItemUse, Rune, Splash
         ↓ facts, queries and reactions through EffectEngine (P01 EB4)
```

All rules code follows gdscript.md §8.5: pure, never awaits, reads values through
`session.stats(unit_id)`, rolls through a roll source, emits a fact for every state change.

### Combat state

- **`CombatUnitState`** (one per unit on the map): instance id, side (`PLAYER` or `ENEMY`), seat
  (enemies: none), tile, current HP, Block, current Stance, whether it has acted this phase, tiles
  moved and movement cost spent this turn (for "moved N+ tiles" and "remaining movement"), whether
  a second move is pending (a `MAY_MOVE_AFTER_ACTING` permission fired), whether it was shoved this
  phase, whether its Sidearm swap is spent this turn, its equipped and stowed weapon instance ids, its movement type, unit type and tags (plain strings until P03), its Pouch item, and the growth changes it gained this battle (P01 fix F11) for the battle-end bridge.
  Maximum HP, Stance maximum and every combat value are queries, never stored.
- **Placement:** a unit placed on the map at any time (battle start, a spawn, reinforcement
  arrival, a transfer between maps) starts with Block 0 and its full Stance, so units attacked
  before their side's first Phase Start still have Stance. Timed modifiers that apply "on the first
  turn" (Shaken Footing) are added at that moment.
- **`CombatState`**: units by id, occupancy by tile, the turn counter, the current phase's side, the
  seats that have ended their turn this phase, and the session's rune slots per seat (copied in at
  battle start by P08's bridge).
- **Per-map uses** (staves, potions, Guard Tonics) are combat-lane charges on the item's effect
  instance (P01: "charges use the same two lanes"). Total uses (Elixir, lockpicks, stat boosters,
  ingredients) are campaign-lane charges or consume the item.
- `CombatState.copy_for_sandbox()` gives P01's sandbox a cheap copy (copy on write where it
  matters); it holds no nodes or Resources.
- `CombatState` extends P01's `SandboxState` and implements all 21 of its methods (P01 fixes F6, F11 and F12),
  `equipped_weapon_id()` included. Writes to HP, Block and Stance from effects arrive through the
  engine's resource paths, which emit the facts. A defeated unit's effects and a stowed weapon's
  effects are dormant (P01 fix F8), so P02 never unregisters them.

### CombatGrid

An abstract `RefCounted` defined here, implemented by P04, with `StubCombatGrid` (a rectangle of
configurable tiles) for P02's tests.

| Method | Returns | Used for |
|--------|---------|----------|
| `distance(a, b)` | Tiles up plus across (Manhattan), ignoring walls and terrain | Range, "within N tiles" (the only effect distance, P04 question 12), "no ally closer" |
| `neighbors(tile)` | The four orthogonal tiles | Adjacency, Shove |
| `step(tile, direction)` | The next tile in a direction, or `CombatFact.NO_TILE` off the map | Shove |
| `can_stand(tile, movement_type)` | Whether that movement type may stand there | Shove landing |
| `blocker_at(tile)` | None, unit, plain blocker (wall, door, object), or spiked wall | Shove stops, bumps, spikes |
| `is_slick(tile)` | Whether the tile is spilled oil | Oil slides |
| `tile_bonus(tile)` | Avoid, DEF, RES and Phase Start healing (flat or percent) | Hit, mitigation, terrain healing |
| `validate_path(unit_id, path)` | Legal or a rejection reason, tiles moved, and the movement cost spent | The unit-turn command and "remaining movement". **Moves to `CombatState`** in P04 MP2 (it needs units and objects); the grid keeps a terrain-only path cost (P04 question 12) |

Occupancy lives in `CombatState`; the grid answers terrain and objects. Darkness layers (P06) and
map objects (P04) answer through `blocker_at` and hooks, not new grid methods.

### Turn and phase loop

A **turn** is one player phase then one enemy phase; the counter rises at the player Phase Start.
Each phase runs in this fixed order:

1. **Phase Start** for the side, in this order, as `Godot_FE`'s beginning phase
   (`CController.gd` `beginning_phase_processing`):
   1. Every unit of that side has its Block cleared to 0 and its Stance set to its maximum (one
      `BLOCK_STANCE_REFRESHED` fact per unit).
   2. Terrain healing for units on healing tiles (skipped on flooded tiles: P06 answers through a
      hook).
   3. `PHASE_START` (one fact, the side's).
   4. `UNIT_TURN_START` for each unit of the side, in a fixed order (roster order for players,
      spawn order for enemies), at its current tile (question 9).
   5. The reaction queue drains; then the side gets control.
2. **Units act.** Player side: seats send unit-turn commands until every seat with units on the map
   has ended its turn. Enemy side: the AI hook returns the enemy's commands one at a time, each
   seeing the resolved result of the one before.
3. **Phase End** for the side, mirroring Phase Start:
   1. `PHASE_END` (one fact, the side's).
   2. `UNIT_TURN_END` for each unit of the side still on the map, in the same fixed order as step
      1.4, at its final tile (question 11). Every unit gets it, whether it acted or not.
   3. The reaction queue drains, so Phase End and Unit Turn End effects (Sunshard Band's heal,
      Radiance's Block) land **before** darkness damage (question 12).
   4. The `PHASE_END_EFFECTS` hook (darkness damage for that side, P06).
   5. The reaction queue drains again; then timed modifiers that end "until Phase End" expire.

A unit's action (an attack, a staff, a shove, an item, a swap, a map-object action or Wait) ends
its turn for the phase; it fires no Unit Turn End of its own.

The enemy phase is **one command** (P01): the last player end-turn resolves player Phase End, the
whole enemy phase, the hooks after it, and the next player Phase Start with its new intents.

**Ordered hooks** (other plans register; P02's tests register no-ops):

| Hook | When | Registered by |
|------|------|---------------|
| `TERRAIN_HEALING_ALLOWED` | During Phase Start healing, per unit | P06 (flooded tiles don't heal) |
| `PHASE_END_EFFECTS` | Phase End, after triggers | P06 (darkness damage for that side) |
| `ENEMY_COMMANDS` | Enemy phase, step 2 | P05 (the AI) |
| `AFTER_ENEMY_PHASE` | After enemy Phase End, in registration order | P06 (darkness step), then P04 (reinforcement arrival) |
| `INTENTS` | After the next player Phase Start | P05 |
| `AFTER_STEP` | After every command step (each enemy's turn is a step inside the enemy-phase command) | P04 (objective and defeat checks; ends the combat) |
| `OBJECT_OPERATIONS` | When a rune or effect acts on a map object (Spark detonates a powder keg) | P04 (map objects own their break and explode rules) |

Hooks are pure functions on the session; their order is fixed by registration order recorded in
the session, and a test asserts the full order.

### Commands

| Command | Contents | Validated |
|---------|----------|-----------|
| `UnitTurnCommand` | unit id, path, action (kind, target, weapon choice, item), `based_on_seq` | Seat owns the unit; the unit hasn't acted; it's that side's phase and the seat hasn't ended; path legal (`validate_path`); action legal from the path's end tile; stale forecast for attack, staff and shove |
| `EndTurnCommand` | seat | That seat has units on the map and hasn't ended; the last seat's end-turn runs the enemy phase |
| `CastRuneCommand` | seat, rune slot, target | Any seat with that rune, during this map's player phase; valid target anywhere on the map |

- **Atomic unit turn:** the move and the action are one command. "No moving after acting" holds
  unless a permission allows the remaining movement (Freewing's Skirmisher, Bloodhound's Collar);
  that second move is its own command, allowed only while the unit's second move is pending, and
  its budget is `MOVEMENT` minus the movement cost already spent this turn.
- **Actions:** Attack (any weapon, including attack staves), Use a staff (Block or heal), Shove, Use
  a Pouch item (self or an adjacent ally), Swap weapon (with the stowed weapon; costs the action, or
  free with Sidearm once per unit turn before acting), Wait. Map-object actions are P04's, through
  the same command.
- **A unit that never acts** emits no facts; it simply ends the phase unmoved.
- **Rejections** cost nothing and return a reason (P01 `command_rejected`).

### The exchange

Given attacker, defender, the attacker's weapon and origin tile:

1. **Legal:** the weapon's range covers the distance; it isn't a staff the rules forbid here.
2. **Before Combat** facts for both units (attacker first); the reaction queue drains, so effects
   such as Professional's Block land before the first attack.
3. **Can the defender counter?** Only if its weapon's range covers the distance, it isn't holding a
   staff, and no permission denies it.
4. **Turns:** attacker, then defender (if it can counter), then the faster unit's bonus turns.
   **Attack Speed** = `SPD − max(0, NET_WEIGHT − CON)`, where `NET_WEIGHT` = Weapon slot weight +
   Equipment weight + Pouch weight + effect weight. Pouch items, a stowed weapon included, weigh 0
   unless `POUCH_ITEM_WEIGHT` says otherwise (Heavy Pack: 2 each). The
   Attack Speed gap gives bonus turns at 4 or more, 10 or more, 18 or more, then each threshold 2
   wider than the last gap (28, 40, 54…), **uncapped** (question 4). A unit that can't counter gets
   no turns.
5. **Each turn** makes `max(1, AtkX − defender's Parry)` attacks. Each attack:
   - `ATTACK_MADE` (inline window: Hit, stages and flags of that attack, e.g. Iron Heart's lifesteal).
   - **Hit roll:** `Hit% = clamp(weapon Hit + triangle ±15 + effects − defender's avoid, 0, 100)`,
     avoid = terrain + effects; 2RN through the roll source. A miss emits `MISSED` and `DODGED`.
   - **On a hit:** `HIT_DEALT` and `HIT_TAKEN` (inline window through stage 8).
   - **Crit:** only if the defender's Stance was 0 before this hit; one d100 against
     `25 + crit modifiers`; `CRIT_DEALT` and `CRIT_TAKEN`.
   - **Damage stages** (exact values in 1–4, question 5):

     | # | Stage | Rule |
     |---|-------|------|
     | 1 | Attack | Weapon damage + Might (scaling modifier 1) + flat attack modifiers, ± the triangle (`round(weapon damage ÷ 4)`, halves up, at least 1, for Advantage and Disadvantage), and effectiveness: if the weapon is effective against the defender, weapon damage counts `EffectiveModifier` times (3 + bonuses) |
     | 2 | Mitigation | Subtract the defender's stat for the damage type (Physical DEF, Magic RES, Split ½ × (DEF + RES), Pure skips this stage) + the terrain's DEF or RES bonus (Split: half of each) + flat mitigation modifiers, which may make it negative ("takes 2 more damage"; question 15). A crit with "skips Mitigation" (Kukri) skips it too |
     | 3 | Critical | × the weapon's CritX (+ modifiers) on a crit |
     | 4 | Multipliers | The attacker's `MULTIPLIERS` × the defender's `INCOMING_MULTIPLIERS` (question 15); a "that hit" modifier joins the key it targets. Each side's sources appear in the breakdown |
     | 5 | Floor | Round once, halves up; never below 0. A 0 is fully countered |
     | 6 | Block | The defender's Block absorbs what it can |
     | 7 | HP | HP takes the rest |
     | 8 | After hit | If damage reached Block or HP: `DAMAGE_DEALT` / `DAMAGE_TAKEN`, Stance −1 plus any extra Stance loss from that hit's inline effects (Breaker, Breaker's Maul; question 10), never below 0 (`STANCE_CHANGED`); `EXPOSED` when it reaches 0; after-hit effects. A fully countered hit (0) costs no Stance, extra loss included |

   - **Lifesteal** (an inline flag): heals the attacker for the damage that reached HP, after
     stage 7 (`HEALED`), through the engine's one heal path, which applies
     `HEALING_RECEIVED_PERCENT` (P01 question 29). Staves, potions and terrain heal through it too.
   - **Defeat:** HP 0 emits `DEFEATED` and `DEFEATED_AN_ENEMY`, removes the unit from occupancy and
     ends the exchange at once.
6. **After Combat** facts for each surviving participant; timed modifiers "this exchange" expire;
   the reaction queue drains. Reactions to facts from inside the exchange resolve here, after the
   last attack: Cleave's splash and Momentum's bonus (P01 question 28) never act between attacks.
   A reaction queued by a unit defeated later in the exchange still resolves (P01 question 33).

The triangle: Balance beats Nimble, Power beats Balance, Nimble beats Power; same profile is a
Standoff; profile None never takes part (both sides Standoff).

### Splash damage

One resolver for every splash source (Cleave, Trample, powder kegs, bumps, spiked walls): flat
damage, no hit roll, no Mitigation, no crit, no Stance loss; Block absorbs it; it fires
`DAMAGE_TAKEN` (with `source` SPLASH, BUMP or SPIKE), never `HIT_TAKEN`; it can defeat. A queued
splash (Cleave) resolves at the next drain, centered on the tile its source stood on when it was
queued, even if that unit has since been defeated. The engine calls it through
`SandboxState.deal_splash()`.

### Shove

- **Legal:** the target is orthogonally adjacent; an ally (always willing) or an Exposed foe; not
  yet shoved this phase; not denied by Unshovable; and the shove does something (question 8).
- **Movement:** the target moves tile by tile in the direction away from the shover, up to the
  shover's Shove distance. Each step checks the next tile:
  - off the map, a plain blocker, or a tile its movement type can't stand on: stop, no damage;
  - another unit: stop; **bump**, 2 splash damage to both (source BUMP);
  - a spiked wall: stop; 4 splash damage to the target (source SPIKE).
- **Oil:** a unit that lands on a slick tile keeps sliding in the same direction, past its Shove
  distance, until it lands on a non-slick tile or is stopped (with bump or spike damage if a unit
  or a spiked wall stops it). The whole slide is the one shove it can receive this phase.
- Facts: `SHOVED_A_UNIT`, `SHOVED`, `UNIT_MOVED` (final tile), then any damage. Darkness never
  damages on the spot (the shoved unit gets its own phase to step out).

### Staves, Pouch items, weapon swaps, runes

- **Block staff:** an ally in range gains its amount (e.g. 3 + Might) through `BLOCK_GAINED` (inline
  window: Brittle Guard); spends a per-map use if it has a limit; `USED_STAFF_ON_ALLY`.
- **Heal staff:** a damaged ally in range heals its amount, capped at maximum HP (overheal recorded);
  `HEALED_AN_ALLY` and `HEALED` (inline window: Cleansed Goblet, Cursed Blood); spends a use;
  `USED_STAFF_ON_ALLY`. Area staves (Sanctuary, Everwall) apply per target.
- **Range 0 (self):** a Block or heal staff with range 0 (Everwall) targets only its user: the
  command needs no target picked, the validator uses the user's tile, and `USED_STAFF_ON_ALLY` names
  the user as its target (question 14). Every staff and weapon has a range; none has "no range".
- **Attack staff:** an ordinary Attack whose weapon is the staff; spends a use per Attack action;
  its holder never counters.
- **Pouch item** (self or an adjacent ally): potions heal and Guard Tonics give Block, each spending
  a per-map use; the Elixir heals to full and is consumed; stat boosters add a permanent stat delta;
  eaten ingredients heal and add a permanent growth delta. Permanent deltas are written to the
  roster by P08's bridge at battle end. `ITEM_USED`.
- **Weapon swap:** exchanges the Weapon slot and the stowed weapon; only the Weapon slot counts
  toward Attack Speed, and only its effects apply (a stowed weapon's are dormant, P01 fix F8);
  `WEAPON_SWAPPED`. As an action it ends the unit's turn; with Sidearm it is
  free once per unit turn, before acting, and the attack command can name either weapon (the
  forecast cycles both).
- **Runes:** `CastRuneCommand`; the rune's operation resolves on its target; the rune leaves its
  seat's slot; `RUNE_USED`. Outside the action economy; player phase only. Most of the seven runes
  are ordinary effect operations (Mend, Aegis, Shatter, Clarity, Haste). Two need more:
  - **Spark** (a powder keg explodes) acts on a map object through the `OBJECT_OPERATIONS` hook;
    P04 owns the explosion.
  - **Recall** (two of your units swap positions) is a P02 operation: legal only if each unit can
    stand on the other's tile (`can_stand`); it emits `UNIT_MOVED` for both and counts as neither
    unit's move nor a shove.
  - Any Stance loss outside a hit (Shatter, the Hexer's Curse) emits `STANCE_CHANGED` and `EXPOSED`
    at 0, like a hit.
- **Wait:** ends the unit's turn; `UNIT_WAITED`.

### Forecast and AI summary

- **Player forecast:** the exchange resolver run in a P01 sandbox with `ForecastRolls`, from the
  command's origin tile, path and weapon. It returns per side: Hit (displayed and true 2RN),
  crit chance when Exposed, attacks per turn, turn order, damage per hit with its
  `ValueBreakdown`, predicted HP, Block and Stance after, and chance-gated effects listed as
  "25%: +X". The same code executes, so the forecast equals the result. Staff and shove previews
  use the same pattern.
- **AI summary:** `ExchangeOutcome` from P01's branch enumeration (`ForcedRolls`) or sampling
  (`SampledRolls`): kill and death probabilities, expected damage dealt and taken, maximum damage,
  probability of breaking Stance. **P01 owns the `ExchangeOutcome` type and the branch summary**
  (EB4 `exchange_outcome.gd`); P02 runs its exchange resolver inside those branches and reports the
  combat results the summary records. P05 owns the rating formula.

### Value keys, permissions and facts

**`CombatValue` keys** this plan registers: `ATTACK_SPEED`, `NET_WEIGHT`, `ATK_X`, `PARRY`, `HIT`,
`AVOID`, `CRIT_CHANCE`, `CRIT_X`, `STANCE_MAX`, `SHOVE_DISTANCE`, `RANGE_MIN`, `RANGE_MAX`,
`DAMAGE_TYPE` (override), `EFFECTIVE_MODIFIER`, `STAFF_AMOUNT`, `MOVEMENT` (the move budget; the
Haste rune and Quick Soles change it; P03 supplies the base stat and P04 spends it), plus the four
`DamageStage` keys (`ATTACK`, `MITIGATION`, `CRITICAL`, `MULTIPLIERS`). It reads
`POUCH_ITEM_WEIGHT` (P01's campaign list, read at battle start).

**Permissions:** `CAN_COUNTER` (denied while holding a staff), `CAN_BE_SHOVED` (Unshovable denies
it; P01 question 19),
`MAY_MOVE_AFTER_ACTING` (Skirmisher, Bloodhound's Collar), `FREE_WEAPON_SWAP` (Sidearm),
`SKIP_MITIGATION_ON_CRIT` (Kukri).

**`CombatFact` changes** (append only, per its rules):

| Change | Why |
|--------|-----|
| New field `side` (`NONE`, `PLAYER`, `ENEMY`), appended to the wire array | `PHASE_START` / `PHASE_END` say whose phase it is (`combat_fact.gd:TOD-001`) |
| Kinds `BLOCK_STANCE_REFRESHED`, `STANCE_CHANGED`, `ITEM_USED`, `WEAPON_SWAPPED`, `RUNE_USED`, `UNIT_WAITED`, `BLOCK_LOST` | Every state change emits a fact; `BLOCK_LOST` covers Block taken away outside damage (Haunted: "loses 2 Block") |
| `Source.SPIKE` | Spiked-wall damage is separable from a bump |
| `PHASE_START` carries the turn number in `amount` | The mirror and presentation know the turn |
| New field `item_id`, appended after `side` (P01 question 20, fix F2) | `ITEM_USED`, `WEAPON_SWAPPED` and `RUNE_USED` name the item, weapon or rune; `RUNE_USED` carries the casting seat in `amount`. Mirrors spend charges and empty rune slots from them |

### What P02 needs from P01 (EB2–EB4)

The reason P02 is drafted before EB2. Each item is checked against the P01 plan; anything P01
doesn't already promise is amended into P01 before EB2 starts. **All ten were amended into P01 on
October 26, 2026** ([Amendments from P02 and P13](2026-10-23-event-bus-and-effects.md#amendments-from-p02-and-p13));
the "P01 today" column records the state before that.

| # | Need | P01 today |
|---|------|-----------|
| N1 | Value queries return **exact (float) values**; only P02's stage 5 rounds | Not stated; add to EB2 |
| N2 | `DamageStage` keys and the `CombatValue` keys above | EB2 creates `damage_stage.gd`; keys added by P02 (contracts table) |
| N3 | `EffectContext` fields for "that attack / that hit": attacker, defender, weapon instance, origin tile, distance, exchange role, attack index, whether the defender was Exposed before the hit, whether it is a crit | Add to EB4's `effect_context.gd` |
| N4 | Inline flags on an attack or hit context: lifesteal, skip Mitigation, damage type override | Lifesteal named; add the others |
| N5 | The permissions above | Permission mechanism exists; keys added by P02 |
| N6 | Timed-modifier expiry points: this exchange, next attack, until Phase End, end of next phase, this combat; P02 calls the engine at each boundary | Listed; confirm the boundary call API in EB4 |
| N7 | Charges with a per-map reset at combat start (combat lane) and run-total (campaign lane) | Lanes exist; confirm per-map reset at battle start |
| N8 | Roll sources expose `roll_hit_2rn(hit_percent)` reporting the true 2RN probability, and `roll_percent(chance)` for one-roll crits and Chance conditions | Roll sources exist; add the two methods |
| N9 | The sandbox copies P02's `CombatState` through `copy_for_sandbox()` | Add the hook to EB4's sandbox |
| N10 | `BLOCK_GAINED` inline window for every Block gain, including staves and Phase Start | Listed (question 5) |

### Notes for other plans

- **P04:** implements `CombatGrid` (`validate_path` returns tiles and movement cost); registers
  `AFTER_STEP` for objectives and ends the combat; registers `OBJECT_OPERATIONS` (the Spark rune
  detonates a keg); a commander's defeat in solo ends the combat as a loss at once, and in co-op
  loses that player's map (the commander returns at critical health after the combat, P08).
  Map-object actions use the unit-turn command. Units placed by deployment or reinforcement start
  with Block 0 and full Stance.
- **P03:** Breaker and Breaker's Maul add their extra Stance loss to stage 8 (question 10), so their
  text needs no change; P01's note on this for the units plan is answered.
- **P05:** registers `ENEMY_COMMANDS` and `INTENTS`; enemies issue the same commands as players.
- **P06:** registers `TERRAIN_HEALING_ALLOWED`, `PHASE_END_EFFECTS` and the darkness step.
- **P07:** reads the forecast API and plays facts; a unit-turn command is built on the client and
  sent only on confirm.
- **P08:** XP, the Standout and grades are observers on these facts. "Beat par" means the combat
  ended before turn par began (the first darkness wave is released at the end of the turn before
  par), i.e. the turn counter at the end is below par. Permanent deltas from stat boosters and
  eaten ingredients go to the roster at battle end.
- **P11:** seats, per-map phase end and runes on a teammate's map are already in P02's rules.

## Save Impact

- **New `COMBAT` section `combat_state`**, version 1, one per session (a `SaveSection` in solo; the
  per-map format is P11's change): every unit's `CombatUnitState`, the turn, the phase side, the
  seats that have ended this phase, shoved-this-phase ids, each unit's movement spent, pending
  second move and growth changes (Save & Quit works mid-phase), and rune slots per seat. Plain JSON, ids as
  strings, enums as string ids (save-system.md data rules).
- `CombatData`'s core `turn` and `phase` are kept equal to the solo session's values, so the save
  summary still shows them; P11 decides their future for parallel maps.
- Effect state (counters, charges, timed modifiers) is saved by P01 EB7; the RNG stream state by
  P13 (the combat `rng` section; [RNG streams plan](2026-10-26-rng-streams.md)).
- Checkpoints are unchanged (save-system.md: Begin, end of each player phase, battle end).

## Work Breakdown

| Step | Files | Description | Risk | Gate | Verification |
|------|-------|-------------|------|------|--------------|
| CC1 Fact amendments | `scripts/bus/combat_fact.gd`, `combat_bus.gd`, `tests/effects/run_all.gd` | `side` field (wire array appended), the seven new kinds, `Source.SPIKE`, turn in `PHASE_START.amount`; channel routing for the new kinds; wire round-trip tests | 🟡 wire format change (nothing saved or shipped uses it yet) | EB1 ✅ | Headless suite; check-only on changed files |
| CC2 State, grid, keys | `scripts/combat/combat_unit_state.gd`, `combat_state.gd`, `combat_grid.gd`, `tests/combat/stub_combat_grid.gd`, value-key and permission registrations | State model, sandbox copy, the grid interface and stub, P02's value keys and permissions | 🟢 | EB2 | Unit tests for occupancy, copies and the stub |
| CC3 Exchange | `scripts/combat/exchange_resolver.gd`, `damage_pipeline.gd`, `weapon_triangle.gd`, `bonus_turns.gd` | The full exchange, stages, crits, Block, Stance, lifesteal, defeat | 🟡 core balance | EB4 | Golden fact logs per fixture; property tests; 2RN distribution test |
| CC4 Splash and Shove | `scripts/combat/splash_resolver.gd`, `shove_resolver.gd` | Splash rules; Shove legality, steps, bumps, spikes, oil | 🟢 | CC3 | Golden logs for each stop case and an oil slide |
| CC5 Support actions | `scripts/combat/staff_resolver.gd`, `item_use_resolver.gd`, `weapon_swap.gd`, `rune_resolver.gd` | Staves, Pouch items, swaps and Sidearm, runes, Wait | 🟢 | CC3 | Golden logs; per-map uses reset between two battles |
| CC6 Turn loop and commands | `scripts/combat/phase_runner.gd`, `combat_hooks.gd`, `unit_turn_command.gd`, `end_turn_command.gd`, `cast_rune_command.gd`, `command_validator.gd` | Phases, refresh, terrain healing, hooks, commands, validation, the enemy phase as one command | 🟡 | EB6 | A scripted two-side fight runs to a defeat headless; hook order test; rejection tests (ownership, stale forecast, ended seat) |
| CC7 Forecast and AI summary | `scripts/combat/combat_forecast.gd` | Player forecast by sandbox, and the combat results P01's `ExchangeOutcome` records (P01 owns that type) | 🟡 | CC6, EB4 sandbox | Forecast equals execution over 1,000 seeded exchanges; summary probabilities sum to 1 |
| CC8 Save section | `scripts/combat/combat_state_section.gd` | `combat_state` capture and restore; `CombatData` core sync | 🟡 save format (new section) | EB7 | Save, quit, resume mid-phase reproduces the same fact log |
| CC9 Docs | `docs/design/game-vision.md`, `docs/plans/game-orchestrator.md`, P01 plan | Vision (already updated for question 4), orchestrator status, P01 amendments N1–N10 | 🟢 | Before EB2 | Review |

New classes are registered with a cache refresh (`--import`) after each step that adds a
`class_name`, per CLAUDE.md §3.

## Breaking Changes

| Change | Kind | Current | Proposed | Status | Places to check | Risk |
|--------|------|---------|----------|--------|-----------------|------|
| `CombatFact` gains `side` | Wire format | 14-slot wire array (`WIRE_PATTERN` `iiissiiiiisiii`) | 15 slots, `side` appended | Suggested | `combat_fact.gd` `to_wire` / `from_wire` / `WIRE_PATTERN`, `tests/effects/run_all.gd` | 🟡 |
| `CombatFact.Kind` and `Source` append values | Enum | 35 kinds, 6 sources | +7 kinds, +1 source | Suggested | `combat_fact.gd`, `combat_bus.gd` routing, `bus_tracer.gd` | 🟢 |

## Verification

- **Golden fact logs:** fixed state + seed ⇒ the exact fact list, committed per fixture: a plain
  exchange, a triangle Advantage, effectiveness, a bonus turn at a gap of exactly 4 and of 10, a
  crit on an Exposed target, Parry cutting attacks, full mitigation (0 damage, no Stance loss),
  Block absorbing, a defeat mid-exchange, a bow that can't counter at 1, a staff holder that can't
  counter, lifesteal, each Shove stop case, an oil slide, each staff kind, each Pouch item kind, a
  Sidearm swap, a rune. Added by the October 26 review: an enemy attacked on turn 1 before its
  first Phase Start (full Stance from placement); the Phase Start order (refresh, terrain healing,
  `PHASE_START`, then `UNIT_TURN_START` per unit in roster order) with Phalanx counting allies at
  the start-of-phase tile, and `UNIT_TURN_END` per unit after `PHASE_END` with Radiance counting allies at their final tiles (an idle unit included); Breaker on a fully countered hit (no Stance lost); Skirmisher's second
  move limited to `MOVEMENT` minus the cost spent; Recall's swap and a Recall rejected by
  `can_stand`; Spark through a registered `OBJECT_OPERATIONS` stub; Haunted emitting `BLOCK_LOST`;
  Heavy Pack's Pouch weight lowering Attack Speed. Added by the approval check: a Sunshard Band
  heal at Phase End resolving before that phase's darkness damage (a unit that would die to the
  darkness alone survives).
- **Property tests:** damage ≥ 0; HP never below 0; the exchange stops at the first defeat; bonus
  turns never fall as the gap grows; triangle Advantage and Disadvantage are mirror images.
- **2RN distribution:** 10⁵ seeded rolls at several Hit values match the analytic two-roll curve
  (`07` §10).
- **Forecast = execution:** for 1,000 seeded exchanges, the forecast with the real rolls forced
  matches the executed fact log.
- **Determinism:** the same commands and seed produce the same log twice, and after a save and
  resume.
- **Checks:** `godot --headless --path bandit-bash --check-only --script <file>` on every changed
  script; the headless suites under `tests/effects/` and `tests/combat/`.

## Rollback

Each step is its own commit. CC1 reverts by restoring the 14-slot wire array (nothing persists
facts yet). CC2–CC7 add new files only and revert by deleting them. CC8 adds a new save section;
an older build ignores an unknown section (save-system.md), so reverting it is safe.
