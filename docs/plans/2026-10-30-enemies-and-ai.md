# Plan: Enemies and AI
**Date:** October 30, 2026
**Status:** **Approved** October 30, 2026 (questions 1–17 answered). **In progress:** EN1 built and
merged October 30, 2026 (60ae740; question 18). EN2–EN4 may start; EN5 waits on P03 CT3.
Orchestrator ID **P05** ([game-orchestrator.md](game-orchestrator.md)).

The enemy side of combat: enemy classes as data, how a battle's enemies are drawn and built, the
AI that plays them, and the intents and danger zone that make it readable. It is staged like P03:
the M1 subset first (three classes, three behaviors, one pack, intents), then the rest of the MVP
roster, elites, mini-bosses, map-object AI, reinforcement groups and the boss.

## Problem

Every enemy in a battle stands still, and nothing describes one:

- With nothing registered on `ENEMY_COMMANDS`, every enemy Waits
  (`scripts/combat/phase_runner.gd:199-205`; `combat_hooks.gd:38-42` names P05 as its owner).
  `INTENTS` (`combat_hooks.gd:46-47`) has no registration either, so there are no intents and no
  danger zone.
- Setup step 4, `ENEMY_SLOTS` (`scripts/sessions/combat_encounter.gd:54`; P01 question 40), has no
  registration: no battle draws enemies. Tests place them by hand.
- No enemy class exists as data. An enemy class built on `UnitTypeDefinition` (P03 question 14)
  would count as a unit type in `EffectCatalog` and fail its folder rule in `data/enemies/`
  (orchestrator design item from P01 EB5).
- Stopgaps that name P05:
  - Bosses: the boss or mini-boss is whatever enemy stands on a leader slot
    (`scripts/map/objectives.gd:146`, TOD-004).
  - The Cutthroat is found by its type name (`scripts/map/map_objects.gd:96`, TOD-002).
  - Reinforcement waves have no groups: `Reinforcements.GroupSource` draws nothing
    (`scripts/map/reinforcements.gd:323`, TOD-002; `scripts/sessions/campaign_session.gd:99`,
    TOD-002), so no point ever sends a wave in the real game.
- The AI's cost decisions were left to this plan by P01 EB9: the branch budget for
  `ExchangeOutcome`, and whether sandboxes copy on write
  ([P01, EB9 results](2026-10-23-event-bus-and-effects.md)).

## Open Questions

| # | Question | Options | Recommendation | Answer |
|---|----------|---------|----------------|--------|
| 1 | M1's enemy classes | Any 2–3 of the 10 | **Brute, Crossbowman, Hedge Healer:** three behaviors (Aggressive, Hold, Support), one friend-or-foe trait (Cleave), the enemy staff path. The Cutthroat waits for map-object AI | **Answered October 30, 2026 (user):** as recommended. |
| 2 | How the AI decides | Rate options / scripted rules | **Rate every (end tile, action, target) option with the same forecast the player sees; kills first, then the behavior's target rule; ties broken deterministically; each enemy sees what the ones before it did; no deeper lookahead** | **Answered October 30, 2026 (user):** as recommended. The AI must be obvious and manipulable by the player. Later: an enemy attack forecast like Fire Emblem's (scope, after M1). |
| 3 | When intents update | Phase Start only / after every player action | **After every player action, and live while the player moves a unit** (a preview for the hovered tile), with lines from each enemy to its target as in Fire Emblem; "it should be very clear what the AI is doing when the player does any action" | **Answered October 30, 2026 (user):** after every player action and while moving. |
| 4 | Who owns the danger zone | P05 / P07 | **P05 computes it as data; P07 draws it** | **Answered October 30, 2026 (user):** as recommended. |
| 5 | Plan shape | One staged plan / several | **One staged plan, like P03** (the Work Breakdown below) | **Answered October 30, 2026 (user):** as recommended. |
| 6 | Which numbers the AI decides with | The player's forecast (`ForecastRolls`: hits land, chances listed) / exact `ExchangeOutcome` branches | **The player's forecast calculation, run fresh for every option.** Each (end tile, target, weapon) option gets its own preview from that tile, so the terrain under the enemy and under its target, Block, Stance and every effect count; "the player's forecast" means the same code the forecast panel runs (hits land, chances listed), not one shared result. The AI then reasons in the numbers a player sees when they forecast that matchup. About 2 ms per option (EB9), against 7–32 ms for an exact outcome of 2–4 attacks. `ExchangeOutcome` stays available for later uses (an elite's tie-break, the boss) | **Answered October 30, 2026 (user):** as recommended, once clarified (the user asked how one forecast could serve every tile: it doesn't; each option is forecast on its own). |
| 7 | What "can kill" means, and how options rank | Godot_FE's weighted sum (kill chance × 5000 + damage share × 100–150) / an ordered list | **An ordered list, compared in turn:** (a) **a kill:** the forecast shows the target defeated if the attacker's hits land (crit lines don't count); among kills, the higher chance that those hits land; (b) the behavior's target rule (below); (c) Godot_FE's value: expected damage ÷ the target's max HP, capped at 1, × 100, + 50 more when the enemy takes no damage (`aiAction.gd`); (d) the end tile's terrain: avoid ÷ 50 + DEF + RES (`aiAction.gd`); (e) a fixed order: path cost, then the end tile in row-major order, then the target's id. Each step is something the player can see | **Answered October 30, 2026 (user):** as recommended. |
| 8 | Which enemy acts first | Fixed slot order / highest-rated first | **Highest-rated first, re-deciding the rest after each action** (Godot_FE's `ai_turn`), so a kill anywhere on the board happens before lesser moves. Ties by the fixed order in 7(e) | **Answered October 30, 2026 (user):** as recommended. |
| 9 | Whether intents chain | Each enemy against the current board / chained through the AI's own expectation | **Revised after the user's answer: chained.** The intents show the enemy phase as the AI expects it, in order: the first enemy's plan, its forecast result applied (hits land, as in 7a), then the next enemy's plan on that board, and so on. A kill that exposes a vulnerable unit shows the follow-up that punishes it. Each intent carries its place in the order. In the real phase each enemy still re-decides after the last one resolved (question 8), so a miss changes what follows | **Answered October 30, 2026 (user):** intents must show punishment of an exposed unit ("why wouldn't they?"). Confirmed: chained through the forecast's expectation, in order. |
| 10 | Live preview budget | A latency target to measure against | **50 ms per hovered tile on the dev machine** (a first target with no basis in the docs; measured in EN4's benchmark). With chained intents (question 9), the preview re-decides from the first enemy in the order whose plan the moved unit can change; the ones before it keep their plans. If it misses the target, the preview runs off the main input path and the newest hover wins | **Answered October 30, 2026 (user):** as recommended. |
| 11 | The three M1 behaviors | — | **Aggressive** (Brute): the best attack it can reach this turn; otherwise advance toward the nearest foe by path cost (Godot_FE's move rating), ending on the reachable tile closest to it. **Hold** (Crossbowman): attack from where it stands if a foe is in range (Steady Aim); otherwise the best attack it can reach this turn; otherwise advance as Aggressive. **Support** (Hedge Healer): heal the ally missing the most HP within reach; end on the reachable tile the fewest player units can attack next phase; with nobody hurt, stay with its pack (end on the tile nearest its allies that the fewest player units can attack) | **Answered October 30, 2026 (user):** as recommended. |
| 12 | M1's enemies | — | **3 enemies at level 1** (step 1 of Run structure), one Brute, one Crossbowman and one Hedge Healer, as a provisional M1 pack; the leader slot stays empty (standard combats have no leader) | **Answered October 30, 2026 (user):** as recommended. |
| 13 | Enemy weapons | Enemy-only weapons with a tag / generic weapons | **Generic weapons for humanoid enemies:** M1's Brute carries the Simple Axe, the Crossbowman the Simple Bow (not enemy-roster.md's Heavy Crossbow), the Hedge Healer the Minor Heal staff. **Enemy weapons and staves never run out:** an enemy's uses are unlimited (the loadout ignores per-map and total uses for the enemy side). **Limited uses belong to unique traits and signature moves** (EN7). The Raider's Javelin and the Hound's Fangs (a beast's natural weapon) are decided with EN6 | **Answered October 30, 2026 (user):** generic weapons; infinite durability for every enemy weapon; unique traits and skills have limited uses. |
| 14 | Enemy stats at a level | — | **Base + floor(growth % × (L − 1))** per stat (Run structure), built by the loadout; the level comes from the floor's step (1 / 3 / 5), +1 in key combats, +2 for leaders and mini-bosses | **Answered October 30, 2026 (user):** as recommended. |
| 15 | The darkness | — | **After it arrives** (`MapState`'s flag, set by P06), every enemy behaves as Aggressive, except a boss holding a fixed tile. Every behavior prefers a dry end tile when one serves the same action on the same target (the-darkness.md, Enemy AI) | **Answered October 30, 2026 (user):** as recommended. |
| 16 | A stable index for enemy slots (orchestrator design item from P04 MP5) | Add one / none | **None:** setup fills slots in `MapLayout` order and the allocator mints ids; a saved battle restores its units from the snapshot (CC8), never by re-deriving them from slots | **Answered October 30, 2026 (user):** as recommended. |
| 17 | Where the AI runs | Main thread / worker threads | **The main thread for M1** (`CombatForecast` creates sandboxes on the main thread). Move it to `WorkerThreadPool` (about 2.4× in EB9) only if question 10's target is missed | **Answered October 30, 2026 (user):** as recommended. |
| 18 | Found building EN1 (October 30, 2026): (a) the loadout turns `StaffDefinition.uses` (read by nothing before) into a per-map use effect for player staves and skips it for enemy staves, since valid data had no other way to limit a staff; (b) `ContentIds.TARGET_RULES`, not on the pre-approved list; (c) assumptions: a level's gain uses the unit's full growth, prefix growth included; "uses" are use effects only, so a charged weapon effect on a trigger keeps its limit on an enemy; (d) `ConsumableDefinition.uses` is also read by nothing; (e) the loadout's runtime effects (a staff's uses, an enemy weapon's charge-free copy) in a snapshot | Accept / change each | **(a) and (b) keep.** **(c) accept**; EN7 revisits prefix growth for elites. **(d) a P03 follow-up after CT3:** the loadout reads consumable `uses` as it reads a staff's, and a content rule rejects an item with both `uses` and its own charged use effect (CT3's Potion carries both). **(e) P02 CC8:** runtime effects restore as themselves, never re-resolved from the catalog, so an enemy's staff stays unlimited after a resume | **Answered October 30, 2026 (user):** as recommended. EN1 merged into `dev` (60ae740). |

## Scope

**In scope, for M1 (EN1–EN5):**

- `EnemyClassDefinition` (extends `UnitTypeDefinition`, P03 question 14) with its behavior and
  target rule, its own catalog kind, and the `data/enemies/` layout; packs as data.
- Enemy stats by level (question 14), built by P03's loadout like every other unit.
- Setup step 4: drawing the battle's enemies into its enemy slots from `ENCOUNTER_SETUP`.
- The AI: options, rating (questions 6–7), turn order (question 8), the Aggressive, Hold and Support
  behaviors (question 11), the darkness switch (question 15), registered on `ENEMY_COMMANDS`.
- Intents (an icon kind, the target rule text, the target, the tile it acts from, the area it will
  hit) and the danger zone, recomputed after every player command and previewed for a hovered tile
  (questions 3, 9, 10); P07 draws both.
- M1's three classes and the M1 pack as data, on generic weapons with unlimited uses
  (question 13); a headless M1 battle played to its end against the AI.

**In scope, after M1 (EN6–EN12):** the other seven classes and the Guard and Skirmisher behaviors;
every pack; elites (prefixes on Normal, signature moves telegraphed as intents); marking bosses and
mini-bosses (`objectives.gd:TOD-004`); the four mini-bosses in key combats; map-object AI (kegs,
levers, Braziers, Cutthroat looting, `map_objects.gd:TOD-002`); reinforcement groups
(`reinforcements.gd:TOD-002`, `campaign_session.gd:TOD-002`); the Powder Baron and Keg Barrage;
setup step 6 additions (Hunted, with P09's events); an enemy attack forecast shown on intents, as
in Fire Emblem (question 2; with P07).

**Out of scope:** drawing intents, lines and the danger zone (P07); the darkness itself (P06);
enemy factions beyond the Brigands, the difficulty ladder and enemy prefixes on every enemy
(post-MVP, game-vision.md); the Ballista (post-MVP).

## Design Basis

- **game-vision.md:** [Enemies](../design/game-vision.md#enemies) (every attack has a profile;
  levels and average growths; factions), [Enemy intentions](../design/game-vision.md#enemy-intentions)
  (danger zone and intent icons; intents describe behavior, not committed tiles; aggressive after
  the darkness; Ruthless AI), [Enemy unit types](../design/game-vision.md#enemy-unit-types) (Model
  1: separate classes on the same rules; a behavior per class; special traits, signature moves,
  gimmicks; Cutthroats the only looters), [Bosses](../design/game-vision.md#bosses),
  [Run structure](../design/game-vision.md#run-structure) (enemy count and level by step;
  deterministic growth; only elites and the boss roll prefixes on Normal).
- **Design docs:** [enemy-roster.md](../design/enemy-roster.md) (classes, traits, behaviors and
  target rules, side-agnostic effects, Ruthless AI, enemy-only weapons, packs, elites, mini-bosses,
  the boss); [the-darkness.md](../design/the-darkness.md) (Arrival: every enemy turns aggressive;
  Enemy AI: never end on a flooded tile when a dry one serves); [map-objects.md](../design/map-objects.md)
  (Enemy AI: objects by the same ruthless rule; only Cutthroats loot; intents show the object used).
- **master-ideation.md:** lists "Enemy Units" in its contents but has no section for it; its
  leveling notes (rewards for closing reinforcement routes, no farming reinforcements) are P08's.
- **Decisions in this conversation that extend the vision** (to queue for the ideation thread once
  approved): intents update after every player action and preview while moving, with lines to each
  target (question 3); the AI decides with the player's forecast calculation (question 6); intents
  chain through the AI's expectation, in order (question 9); humanoid enemies carry generic
  weapons (the Crossbowman a Simple Bow, not the Heavy Crossbow) and enemy weapons and staves
  never run out, while unique traits and signature moves have limited uses (question 13).
- **Open in the vision, not a basis for values:** the Brigands' name and theme; every stat in
  enemy-roster.md ("first pass", untested); the boss's 2-phase cadence, 5-tile reach and fuse.
  They are entered as written and tuned in playtesting.

## Legacy Behavior (ports from Godot_FE only)

`Godot_FE` runs on Godot 4.7 too; nothing is copied.

| Godot_FE file | Behavior | Keep / Change / Drop | Reason |
|---------------|----------|----------------------|--------|
| `combat/CController.gd` `get_ai_unit_best_move` | For every reachable tile, rate every attack on a player unit in range; keep the best | Keep | The option search of question 2 |
| `combat/CController.gd` `get_ai_unit_best_move`, step 3 | With no attack, walk toward the nearest tile it could attack from (A* distance), rated by unit value ÷ turns to get there | Change | Path cost from P04's `Pathing`; the unit-value term (level × tier) is dropped (tiers don't exist) |
| `scripts/combat/ai/aiAction.gd` `generate_attack_action_rating` | 1 + hit × 5000 if lethal + damage share × (100 + 50 if no damage taken) | Change | Kill first as an ordered step instead of a weight (question 7); the damage-share term (100, +50) is kept as step (c) |
| `scripts/combat/ai/aiAction.gd` `calculate_terrain_rating` | avoid ÷ 50 + defense + resistance | Keep | Step (d) of question 7 |
| `combat/CController.gd` `ai_turn` | Decide every enemy, act highest-rated first, re-decide the enemies the last action affected | Keep | Question 8 |
| `combat/CController.gd` `select_best_action_position` | Spread enemies over equally good tiles; break ties at random (`pick_random()`) | Change | Ties break in a fixed order (question 7e): rules code never uses the global RNG (gdscript.md §8.5) |
| `scripts/combat/combat_map_constants.gd` `UNIT_AI_TYPE` | `DEFAULT`, `ATTACK_IN_RANGE`, `DEFEND_POINT` | Change | The roster's behaviors (Aggressive, Guard, Hold, Support, Skirmisher) replace them |
| `scripts/resources/enemy_group/enemy_group.gd` | A fixed list of units per group | Change | Packs as data, drawn per run (game-vision.md: enemy groups randomized per run) |

Tuning values carried over: the damage-share weights 100 and +50 and the terrain rating
(`scripts/combat/ai/aiAction.gd`). Class stats come from enemy-roster.md, which lists its own
`Godot_FE` sources.

## Approach

### Shape

```
data/enemies/<class>.tres, packs/ → EffectCatalog (ENEMY_CLASS, PACK)
Setup step 4 (ENCOUNTER_SETUP)   → a pack per encounter, levels by step, units built by Loadout
EnemyAI (pure, static)           → decide(session, unit_id) -> EnemyPlan, from forecast-rated options
  ENEMY_COMMANDS                 → the highest-rated plan as a UnitTurnCommand, one at a time
Intents (pure, static)           → per enemy: kind, rule text, target, action tile, area; danger zone
  INTENTS + every player command → recompute; preview(session, unit_id, tile) for a hovered tile
P07                              → draws icons, lines and the danger zone
```

### Enemy data

`EnemyClassDefinition` extends `UnitTypeDefinition`: stats, growths, movement type, tags, Stance,
weapon and trait as for any unit type, plus `behavior` (Aggressive, Guard, Hold, Support,
Skirmisher), the target rule's id and display text, and, from EN7, a signature move. It has its own
`EffectCatalog.Kind.ENEMY_CLASS` (appended), so it never counts as a player unit type, and lives in
`data/enemies/`. A `PackDefinition` (`data/enemies/packs/`, kind `PACK`) lists class ids with
counts. Elites are not classes: an elite is a class plus a prefix and a signature move, chosen by
setup (EN7). Humanoid enemies carry the player's generic weapons, and the loadout gives every
enemy weapon and staff unlimited uses (question 13); limits on enemies live on their unique traits
and signature moves.

### Setup

Step 4 draws one pack per encounter from `ENCOUNTER_SETUP`, fills the map's enemy slots in
`MapLayout` order (question 16), sets each unit's level from the floor's step (question 14), and
builds each unit through the loadout. Step 4 never draws from a stream used before it (P01
question 40), so a battle restarted from Begin draws the same enemies.

### The AI

`EnemyAI` is rules code: pure, static, deterministic, no RNG, no logging from worker threads.

1. **Options.** For each tile the enemy can end on (`Pathing.reach`), each action its behavior
   allows (attack with each usable weapon, staff, Wait), each legal target.
2. **Numbers.** Each attack and staff option is previewed with `CombatForecast` (question 6). The
   AI reads the forecast's lethal-if-hits-land result, hit chance and expected damage.
3. **Rating.** The ordered comparison of question 7. The behavior supplies step (b) and limits the
   options (Hold attacks from its tile first; Support heals and keeps distance).
4. **No attack.** Advance toward the nearest foe by path cost (question 11), preferring dry tiles
   (question 15).
5. **Order.** `ENEMY_COMMANDS` asks for one command at a time. The AI decides every enemy that
   hasn't acted, gives the highest-rated plan as a `UnitTurnCommand` with seat −1, and re-decides
   after it resolves (question 8). An enemy with no legal plan Waits.
6. **Darkness.** After it arrives, every behavior but a fixed-tile boss's becomes Aggressive.

### Intents and the danger zone

`Intents.compute(session)` plays the enemy phase as the AI expects it, in a sandbox (question 9):
it decides the highest-rated enemy, applies that plan's forecast result (hits land), decides the
next enemy on that board, and so on. It returns one `EnemyIntent` per enemy: its place in the
order, its kind (attack, heal, guard, advance; signature from EN7), its target rule's text, its
target and the tile it would act from (for P07's lines), and the area it would hit (Cleave's
splash, Trample's, a keg's). The danger zone lists, per enemy and combined, every tile it could
attack next phase (reach plus weapon range).

It recomputes after every player Phase Start (`INTENTS`) and after every player command
(`AFTER_STEP` on the player side). `Intents.preview(session, unit_id, tile)` runs the same
computation with that unit moved to that tile, re-deciding from the first enemy in the order whose
options the moved unit's old or new tile touches (question 10). The intents show the phase the
enemies would play if every forecast hit landed; the real phase re-decides after each resolved
action (question 8), so a miss changes what follows.

### Rejected alternatives

- **Exact `ExchangeOutcome` for every option:** 7–32 ms each (EB9); unaffordable for live
  previews, and its numbers aren't the ones the player sees.
- **A weighted sum (Godot_FE's 5000 kill bonus):** works, but a player can't read which term won;
  the ordered list explains every choice in the player's own terms.
- **Unchained intents** (each enemy as if it acted first): cheaper to preview, but they hide the
  follow-up that punishes a unit a kill exposes (question 9).
- **Committed actions (Into the Breach):** rejected by the vision.

## Save Impact

Not saved. The AI is a pure function of the battle state, and intents and the danger zone are
derived from it. Enemy units are battle state saved with the rest of it by P02 CC8 and P04 MP8.
Setup step 4 is re-derived from `ENCOUNTER_SETUP` on a restart from Begin. Later steps add state
that must persist: signature-move cooldowns live on effect counters (CC8's `effects` section), and
EN8's no-repeat mini-boss draw needs the run's list of mini-bosses already met (a campaign
section, block and key decided in EN8 per save-system.md).

## Work Breakdown

| Step | Files | What | Risk | Needs | Verification |
|------|-------|------|------|-------|--------------|
| EN1 Enemy data | `scripts/content/enemy_class_definition.gd`, `pack_definition.gd`; changes in `effect_catalog.gd`, `content_ids.gd`, the content test, `loadout.gd` | The definition and pack classes, two catalog kinds, the `enemies/` folder rules, stats by level (question 14), unlimited uses for enemy weapons and staves (question 13) | 🟡 catalog kinds | Approval | Content test (fixtures); a fixture class's stats at levels 1, 3 and 5 match base + floor(growth × (L − 1)); an enemy's Minor Heal still heals after its per-map uses |
| EN2 Setup step 4 | `scripts/enemies/enemy_setup.gd`; registration in `campaign_session.gd` | Draw a pack, fill the enemy slots, levels by step, build units through the loadout | 🟡 | EN1 | The same seed draws the same enemies twice; a restart from Begin draws them again |
| EN3 AI core | `scripts/enemies/enemy_ai.gd`, `enemy_plan.gd`; registration on `ENEMY_COMMANDS`; `tests/enemies/`, `tests/bench/` | Options, forecast rating, order, Aggressive, Hold and Support, the darkness switch; a benchmark of a full decision | 🟡 | EN1, P02, P04 | Per-behavior cases (kill first, target rule, value, terrain, ties); the same board gives the same plan; an enemy never ends on a flooded tile when a dry one serves; benchmark numbers |
| EN4 Intents and danger zone | `scripts/enemies/intents.gd`, `enemy_intent.gd`, `danger_zone.gd`; registration on `INTENTS` and `AFTER_STEP` | Intents after every player command; the hovered-tile preview; the danger zone | 🟡 | EN3 | The first enemy to act carries out its shown intent when nothing changed; a preview equals the intents after the unit really moves there; the preview meets question 10's target (benchmark) |
| EN5 M1 enemies | `data/enemies/` (Brute, Crossbowman, Hedge Healer), `data/enemies/packs/m1_pack.tres` | M1's three classes on the Simple Axe, Simple Bow and Minor Heal, and the M1 pack (questions 1, 12, 13) | 🟢 | EN1, P03 CT3 | Content test; each class's stats match enemy-roster.md; a headless M1 battle against the AI runs to `COMBAT_ENDED` with seeded rolls |
| EN6 The roster | `data/enemies/`, `packs/`, `enemy_ai.gd` | The other seven classes, Guard and Skirmisher, the Hound's pack movement, the roster's five packs | 🟢 | EN5 | Per-behavior cases; content test |
| EN7 Elites and bosses | `enemy_class_definition.gd`, `enemy_setup.gd`, `intents.gd`, `combat_unit_state.gd`, `objectives.gd` | Leaders, prefixes on Normal elites, signature moves on cooldowns shown as intents, marking bosses and mini-bosses (`objectives.gd:TOD-004`) | 🟡 touches P02 and P04 | EN6, P03 CT8 | The Warcaller's War Horn shows its intent the phase before; Defeat the Leader reads the mark |
| EN8 Mini-bosses | `data/enemies/`, `enemy_setup.gd` | The four mini-bosses in key combats, drawn without repeats per run (save impact stated then) | 🟡 save | EN7 | No repeat in a seeded run; each signature move's case |
| EN9 Map-object AI | `enemy_ai.gd`, `map_objects.gd` | Kegs, levers, Braziers; Cutthroat looting and drops (`map_objects.gd:TOD-002`); intents show the object | 🟡 touches P04 | EN6 | Ruthless keg use; a Cutthroat denies a chest and drops it when defeated |
| EN10 Reinforcement groups | `enemy_setup.gd`, `reinforcements.gd`, `campaign_session.gd` | Fill `GroupSource` (`reinforcements.gd:TOD-002`, `campaign_session.gd:TOD-002`) | 🟡 touches P04 | EN2 | A seeded Survive map sends the same waves twice |
| EN11 The Powder Baron | `data/enemies/`, the boss map with P04 | The boss, Keg Barrage and its intent | 🟡 | EN7, EN9 | The barrage picks the tile catching the most player units; intent one phase ahead |
| EN12 Docs | `docs/design/enemy-authoring.md` (or P03's `content-authoring.md`) | How to add an enemy class, a pack and an elite | 🟢 | EN6 | Review |

M1 needs EN1–EN5. EN6 onward follows M1's first tuning pass (orchestrator focus rules), except
EN10, which waits on a map that sends waves.

## Breaking Changes

| Change | Kind | Current | Proposed | Status | Places to check | Risk |
|--------|------|---------|----------|--------|-----------------|------|
| `EffectCatalog.Kind.ENEMY_CLASS` and `PACK` appended | Enum | — | Two kinds | Suggested (EN1) | `effect_catalog.gd`, the content test | 🟡 |
| Enemies act instead of Waiting | Behavior (P02) | Every enemy Waits | The AI's commands through `ENEMY_COMMANDS` | Suggested (EN3) | `phase_runner.gd`; every combat and sessions test that runs an enemy phase with enemies on the map | 🟡 |
| Setup step 4 registered | Behavior (P01, P04) | No enemies drawn | A pack in the enemy slots | Suggested (EN2) | `combat_encounter.gd`, `campaign_session.gd`, sessions tests | 🟡 |
| `CombatUnitState` gains a boss or mini-boss mark | Interface (P02) | The leader slot stands in | A mark set by setup | Suggested (EN7) | `combat_unit_state.gd`, `objectives.gd` | 🟡 |
| The Cutthroat read from enemy data | Behavior (P04) | Type name | Enemy data | Suggested (EN9) | `map_objects.gd` | 🟢 |

## Verification

- Headless suites: a new `tests/enemies/run_all.gd` (found by `tools/run_tests.sh`), plus the
  content suite for data.
- Determinism: the same board gives the same plan and the same intents, twice, and on a sandbox.
- Readability: the first enemy to act carries out the intent it showed when nothing changed in
  between; a hovered-tile preview equals the intents after that move really happens.
- M1: a headless battle on the M1 greybox map, the Mercenary army against the M1 pack, with seeded
  rolls and scripted player commands, reaches `COMBAT_ENDED`.
- Performance: a benchmark under `tests/bench/` measures a full enemy phase decision and a
  hovered-tile preview on the M1 board (gdscript.md §11), against question 10's target. Release
  build numbers are unmeasured.

## Rollback

Every step registers into hooks and setup steps, or adds data. Reverting a step's merge removes
its registrations: enemies Wait again (P02's fallback), no enemies are drawn, and no intents are
computed. No save data depends on any step before EN8.
