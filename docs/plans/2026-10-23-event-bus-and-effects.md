# Plan: Event Bus and Effects Architecture
**Date:** October 23, 2026
**Status:** Approved October 26, 2026 — in progress: EB1–EB4 implemented October 26, 2026 (490
headless effect tests pass); EB5 waits on the P03 sketch, EB6 on P04 and P08 question 1, EB9 on P02
CC3; amended October 26, 2026 with the combat core's and RNG plan's needs
([Amendments from P02 and P13](#amendments-from-p02-and-p13)) and with the EB4 build's findings
([Follow-ups from the EB4 build](#follow-ups-from-the-eb4-build))

The foundation that every gameplay IMPL plan plugs into: how combat and the campaign announce what
happened, how heirlooms, items, traits, curses, runes and enemy traits react to it, and how numbers
(damage, Hit, prices, XP) are computed with every source visible. Downstream plans (combat core,
units, items, heirlooms, enemies, darkness, map objects, campaign flow, events, multiplayer combat)
build against the contracts in [Contracts for downstream IMPL plans](#contracts-for-downstream-impl-plans).

## Problem

`bandit-bash/` has no combat, campaign or effect code yet. The only cross-system signals are the
service autoloads' own lifecycle signals (`SaveService`, `SceneRouter`, `SteamNetwork`). Every
system the design calls for depends on "when X happens, Y reacts" and "this number has these
sources", and without a shared spine each system will call the others directly.

That is how `Godot_FE/` ended up monolithic:

- **The UI drives the controller's internals.** `Godot_FE/ui/combat/combat_ui.gd` makes 22 direct
  `controller.fsm_*` / `controller._on_*` calls (e.g. `:199-201`), including private handlers.
- **Signals used as control flow.** `CController.gd` awaits `combat.reinforcement_check_completed`
  (`:1013`) and `combat.entity_processing_completed` (`:1944`); `Combat.gd:113-116` declares
  `pause_fsm` / `resume_fsm`. `Godot_FE/docs/systems/09_combat_event_bus.md` §3 measured 14 such
  handshakes, which can resume each other's awaits ("handshake crossing").
- **References passed by signal.** `Combat.gd:261` emits `register_combat(self)`; listeners then
  reach into it (`campaign.gd` reads `combat.unit_data`, `battle_prep.gd` reads
  `combat.entity_manager`).
- **Effects checked inline.** `SpecialEffect.SPECIAL_EFFECT` (about 30 values,
  `scripts/resources/Items/special_effect.gd`) is checked where it matters: 26 checks in
  `scripts/combat/controllers/combat_exchange.gd` (e.g. `VAMPYRIC` at `:78`) and one in
  `CController.gd:652`. `THORNS` and `INCOMING_DAMAGE_AUGMENT` are declared and never read; the
  activation fields (`activation_type`, `activation_chance`) have no callers, so every effect is
  always on (`effects-system.md`, Why this shape).
- **Three parallel trigger vocabularies:** `SpecialEffect`, the deprecated
  `WeaponDefinition.WEAPON_SPECIALS` (duplicating `VAMPYRIC`, with the comment
  "make this modular and configurable"), and `EffectConstants.DECAY_TRIGGER`.
- **Rules mixed with presentation.** `combat_exchange.gd:208` `do_damage()` changes HP, plays
  audio, shows damage numbers, awaits the animation, then checks for death.
- **God objects.** `CController.gd` is 2,157 lines and 121 functions; `Combat.gd` 1,690 and 87.

The redesign makes this harder, not easier: parallel co-op maps run at the same time on the host,
units can move between maps, runes can be cast on a teammate's map, the forecast must explain every
number, and the AI must evaluate kills with every effect included.

## Open Questions

Questions already settled by the design docs are listed first as answered. Everything else is open.

| # | Question | Options | Recommendation | Answer |
|---|----------|---------|----------------|--------|
| A1 | Who resolves combat and effects in co-op? | Host / lockstep | Host | **Answered** by effects-system.md: the host resolves; clients replay. |
| A2 | Relic (heirloom) ownership in co-op | Per player / shared | Per player | **Answered** by game-vision.md Co-op ownership: per player; *unique* heirlooms one owner per campaign. |
| A3 | What is a rune? | Socket / run-wide consumable | — | **Answered** by game-vision.md Run-wide resources: 3-slot run-wide single-use abilities, no owner, consumed on use. |
| A4 | One effect model for every carrier? | One / per carrier | One | **Answered** by effects-system.md: one model for items, traits, statuses, heirlooms, runes. |
| A5 | How modifiers combine | Priority order / order-free | Order-free | **Answered** by game-vision.md damage stages: flat values add, percent values multiply, per stage; source order never matters. |
| 1 | Naming. "Events" already means narrative events (events.md, Unknown nodes). | `Events` / `CombatBus` + `CombatFact` / other | **`CombatBus` / `CampaignBus`** for the buses, **`CombatFact` / `CampaignFact`** for payloads. Narrative events keep "event". | **Answered October 23, 2026:** A. `CombatBus` / `CampaignBus`, `CombatFact` / `CampaignFact`; "event" stays with narrative events; "trigger" stays the effect-text word for the fact kind an effect reacts to. |
| 2 | How effects subscribe | Godot `Signal.connect` / an engine dispatcher | **Engine dispatcher.** Authors still pick a trigger in the inspector, but dispatch is deterministic, queued and can run in forecast mode. Bus signals are for presentation and observers. See [Approach](#rejected-alternatives). | **Answered October 23, 2026:** engine dispatcher. The buses don't depend on the engine (both share only `CombatFact` / `CampaignFact`); the engine stays in this plan as EB2–EB4. |
| 3 | How many combat buses | One global / one per map | **One per map (session).** Parallel maps run concurrently on the host. This replaces the `Events.combat` autoload slot from our earlier discussion. | **Answered October 23, 2026:** one `CombatSession` per map, all owned by a `CombatEncounter` that mediates everything crossing maps. Sessions never reference each other. See [Sessions](#sessions). |
| 4 | Replication unit | State sync / fact batches | **Fact batches.** The host broadcasts the facts each command produced. Clients keep a read-only mirror (including effect counters) updated only by facts, so they can run the forecast locally. Solo uses the same playback path. | **Answered October 23, 2026:** A. Fact batches; client mirrors updated only by facts; local forecasts; a snapshot for join and resume; a test that rebuilding a mirror from the fact log matches the host's state. Follow-ups agreed the same day: the enemy phase is one resolve-then-play command; rejoin support; per-session command serialization with first-arrival-wins; atomic unit turns; seat ownership; per-map phase end; stale-forecast rejection. See [Commands, concurrency and rejoin](#commands-concurrency-and-rejoin). |
| 5 | Which triggers can change "that hit / that attack"? | See [Inline and queued operations](#inline-and-queued-operations) | **Inline window** on Attack made, Hit dealt / taken, Crit dealt / taken, Healed / Healed an ally, Darkness damage taken. All others react only after the fact. | **Answered October 23, 2026:** inline windows on Attack made, Hit dealt / taken (through stage 8, so Stance loss is "that hit's"), Crit dealt / taken, Healed / Healed an ally, Darkness damage taken, and the new **Block gained**. Leveled up is reaction-only; level-up shaping is done by queries in a fixed resolver order. See [Inline and queued operations](#inline-and-queued-operations). |
| 6 | Order of reactions to one fact | — | **The fact's actor's effects, then its target's, then everyone else by seat (enemies last), then instance id.** Mostly invisible (Block and heals commute), but it must be fixed for determinism. | **Answered October 24, 2026:** after fact order: (1) role: the fact's actor, then its target, then others; (2) seat ascending, enemy side last; (3) carrier kind: unit trait → weapon → equipment → Pouch item → heirloom → **curse last**; (4) instance id. Deciding case: Iron Rations vs Haunted at Phase Start; curses always act on the finished result. |
| 7 | Safety cap on chained reactions per command | Value | **16.** Exceeding it stops the chain with `push_error`; it means a content bug, not a gameplay rule. No MVP content chains past 3. | **Answered October 24, 2026:** depth cap **16** generations per chain; total cap **256 reactions per resolution step** (one unit's turn, one phase boundary, the darkness step or reinforcement arrival), not per command, since the enemy phase is one command. Map-object cascades (keg chains, breakables) are exempt. On overflow: stop the chain, keep what resolved, `push_error`; tests fail; release logs via `NetLog`. |
| 8 | Chance conditions in the forecast | Include / exclude / show separately | **Excluded from the totals and listed as "25%: +X"** in the breakdown. The AI treats them as not happening. | **Answered October 24, 2026:** A for the **player forecast**. **Changed for the AI:** the AI reasons in probabilities and can gamble on a chance of a kill, as `Godot_FE`'s rating did (expected damage plus a max-damage lethal check). The engine supports it with a sandboxed simulation and injectable roll sources; see [Forecast and AI simulation](#forecast-and-ai-simulation). The rating formula belongs to the AI plan. |
| 9 | Conflicting overrides and permissions (Short Quiver range, Spirit Coating damage type, "may move again", Unshovable) | — | **Denial beats grant** for permissions. **At most one override per value per unit**; a content test flags combinations; at runtime the unit's own item beats its trait beats a heirloom, ties by instance id, with a warning. | **Answered October 24, 2026:** as recommended. Permissions: denial beats grant. Overrides: at most one per value per unit (content test); at runtime the unit's own item beats its trait beats a heirloom, ties by instance id, with a warning. Floors take the highest floor and caps the lowest cap. |
| 10 | Campaign-level hooks missing from effect-triggers.md | Add / defer | **Add a "Campaign" section to effect-triggers.md:** triggers Gained (this heirloom or item), Combat won, Leveled up, Node entered, Item scrapped. Economy, XP and army-size heirlooms become **campaign value modifiers**, not triggers. Needed by Training Weights, Resonant Ore, Royal Crest, Family Ring, War Chest, Family Relic, Abundance, Bounty Ledger, Merchant's Ledger, Membership Seal. | **Answered October 24, 2026:** add a Campaign section to effect-triggers.md (EB8) with triggers **Gained**, **Combat ended**, **Leveled up** (all reaction-only) and the campaign value keys in [Campaign hooks](#campaign-hooks). Gilded Purse and Scrapper's Tongs become **additions** (+25 and +20 points), so copies stack. **"Instead of" stays supported as an override** for future trade-off heirlooms. |
| 11 | Turn phases in co-op (docs disagree) | — | **Phases are per map.** Units on one map, including reinforcements, share that map's phase. Update effect-triggers.md ("all players share one player phase") and the multiplayer-combat-options.md facts table. The save-system.md checkpoint row "once every player has ended their turn" goes to the multiplayer-combat plan. | **Answered October 24, 2026:** phases are per map; all units on a map, reinforcements included, share its phases; a map's player phase ends when every player with units on it has ended their turn. EB8 updates effect-triggers.md and the multiplayer-combat-options.md facts table, and adds a pointer in save-system.md (each map checkpoints at the end of its own player phase; the format change belongs to the multiplayer-combat plan). |
| 12 | Do scopes reach across parallel maps? | Same map only / non-positional effects reach other maps | **Same map only for the MVP.** Any Ally Unit reaches a partner's units only when they share a map (reinforcement). No MVP effect needs cross-map reach (Brothers in Arms is positional). Revisit when one does. | **Answered October 23, 2026 (changed from the recommendation):** non-positional Any Ally Unit and Any Unit effects reach partner maps through the `CombatEncounter`, built in this plan. Positional conditions never match across maps. |
| 13 | Effects added to one item by an event (Dark Goblet *Infuse*, Cavern *Forge Resonance*) | — | **`ItemInstance` = definition id + granted effect ids + stat deltas.** Granted effects are standalone definitions in the catalog. | **Answered October 24, 2026:** as recommended; see [Definitions and instances](#definitions-and-instances). A modified item's **price and scrap value change** (the items plan sets the formula from its deltas). Naming a modified item is undecided ("Infused" / "Modified" are candidates; items and UI plans). |
| 14 | Content ids and catalog (also: "UI configurable" from our discussion) | — | **Every carrier and standalone effect has a stable string `id`.** One `EffectCatalog` loads definitions from `res://data/`. Authoring is in the Godot inspector; ids keep other tools (spreadsheet import, mods) possible later. | **Answered October 24, 2026:** content ids are `snake_case`, equal to the file name, unique within their kind (not Godot UIDs). One static `EffectCatalog` class (not an autoload) with typed lookups, loaded once at startup on the main thread via `ResourceLoader.list_directory()` (export-safe). Layout under `res://data/` per kind. Inspector authoring. Content tests: id = file name, no duplicates, every reference resolves, definitions unchanged by the suite. **Instance ids (same day):** kind + counter (`item:412`), minted only by one host-owned `InstanceIdAllocator` with a preset per kind; never parsed, never reused; readable through describe helpers and the logging in [Logging and debugging](#logging-and-debugging). |
| 15 | Who owns the sessions | New autoload here / the run-flow plan | **No autoload in this plan.** The campaign/run-flow IMPL plan owns `CampaignSession` (likely from its own autoload). This plan exposes a `combat_session_opened(session)` signal for observers (audio, UI, achievements). | **Answered October 24, 2026:** A. No autoload in this plan; the campaign and run-flow plan owns `CampaignSession` (stub: [2026-10-24-campaign-run-flow.md](2026-10-24-campaign-run-flow.md)). Discovery: `CampaignSession.combat_encounter_opened(encounter)` / `combat_encounter_closed(encounter)` and `CombatEncounter.session_opened(session)`. `CampaignSession` and `CombatEncounter` depend on no scene or autoload except `NetLog`. |
| 16 | Where the rules live | — | **Add a short "Event bus and effects" subsection to `.claude/rules/gdscript.md` §8, and a living `docs/design/event-bus.md`** written at the end of implementation, like save-system.md. `.claude/` needs your OK. | **Answered October 24, 2026:** both. `.claude/rules/gdscript.md` §8.5 "Event bus and effects" added the same day (it links this plan until `docs/design/event-bus.md` exists); the design doc is written in EB8. |
| 17 | Rounding of values that end as whole numbers (heals halved by Cursed Blood, +20% healing, Movement, Hit) | Per key, halves up / per key, round down / each caller rounds | **Per key, halves up.** Each key declares its rounding, applied once at the end; the default matches damage stage 5 and gold. | **Answered October 26, 2026:** as recommended. Damage stages stay exact (P02's stage 5 rounds); darkness keeps its floor, minimum 1 (P06). See [Amendments from P02 and P13](#amendments-from-p02-and-p13). |
| 18 | Which attack spends a "next attack" modifier (Momentum, Clarity, Bloodied Banner) | Any attack, hit or miss / only attacks on its own turn / only a hit | **Any attack, hit or miss**, counters included: the literal reading, and the one the Momentum fixture assumes. | **Answered October 26, 2026:** as recommended. |
| 19 | Unshovable vs "denial beats grant" (found building EB2) | Invert to `CAN_BE_SHOVED` / keep `UNSHOVABLE` with a grant-wins exception | **Invert:** allowed by default, the Unshovable trait denies it, so no grant can cancel it. Same shape as `CAN_COUNTER`. | **Answered October 26, 2026:** as recommended. Fix F1 in [Follow-ups from the EB2–CC1 build](#follow-ups-from-the-eb2cc1-build). |
| 20 | Where `ITEM_USED`, `WEAPON_SWAPPED` and `RUNE_USED` name the item or rune, and a rune's caster (found building CC1) | New `item_id` field, seat in `amount` / two new fields / reuse `source_effect_id` | **One appended field `item_id`; `RUNE_USED` carries the casting seat in `amount`**, as `PHASE_START` carries the turn. Mirrors need both to spend a charge and empty a rune slot. | **Answered October 26, 2026:** as recommended. Fix F2. |
| 21 | When base stats get value keys (found building EB3: Training Weights needs SPD; `STAT_CAN_GROW` must name a stat) | Seed now in EB4 / wait for P03 | **Seed in EB4:** HP, MGT, SPD, DEF, RES, CON (MOV is `MOVEMENT`), the vision's fixed list, plus one shared `Stat` enum. P03 still owns growths and meaning. | **Answered October 26, 2026:** as recommended. Addition F3. |
| 22 | MVP content the EB3 blocks can't express (found building EB3) | Add blocks in EB4 / escape hatch until reused | **Add three in EB4:** a `CommandTarget` selector (the targeted runes), extra Stance loss as a `ModifyThat` target (Breaker, Breaker+), a `WhileMatchupCondition` for the triangle (Professional). "While Equipment is a shield" waits for real content (it is a pattern example in unit-roster.md). | **Answered October 26, 2026:** as recommended. Addition F4. |
| 23 | Order in which an effect's conditions run (found building EB4) | Authored order, stop at the first failure, charges last / counters always advance | **Authored order, stop at the first failure, charges checked last.** A counter placed before a While counts every event; one placed after counts only events that qualify. A Chance after a failing While draws no roll. | **Answered October 26, 2026:** as recommended. |
| 24 | A Block gain that ends at 0 (Brittle Guard on a gain of 1) | Record `BLOCK_GAINED` with amount 0 / record nothing | **Record it with amount 0.** The window already opened and may have advanced counters, and mirrors only replay facts. The minimum belongs to the effect (Brittle Guard: "minimum 0", events.md); the engine's floor of 0 is a backstop. P03's personal XP ignores 0-amount gains. | **Answered October 26, 2026:** as recommended. |
| 25 | Where `COUNTER_CHANGED` names its lane, and how mirrors see a permanent stat change (stat boosters are used in combat) | Lane in `flags` until EB7 / new field now | **Append `STAT_CHANGED` and one int field `key` now**, its meaning set per kind as `amount`'s is. Fix F5. | **Answered October 26, 2026:** as recommended. |
| 26 | "No ally closer to an enemy" with no enemy on the map (Vanguard) | Passes / fails | Fails (no risk to trade the Block against). | **Answered October 26, 2026:** **passes**, as built; a valid strategy, and the case is rare. |
| 27 | How map-object cascades are exempt from the reaction caps (question 7) | By owner kind / by fact source | **By owner kind** (`EffectOwner.Kind.MAP_OBJECT`): those reactions count toward neither cap and add no depth, so a unit reacting at the end of a long keg chain starts from its own depth. | **Answered October 26, 2026:** as recommended. |
| 28 | When Momentum's +15 Hit lands (found building EB4: the reaction queue drains only at Before Combat and After Combat) | At the After Combat drain / at once / drain after every attack | **At the After Combat drain**, with no engine or P02 change: `MISSED` stays queued, so the bonus reaches the holder's first attack in a later exchange, never a follow-up in the same one. Two misses in one exchange stack (+30). | **Answered October 26, 2026:** as recommended (the user's proposal). Cleave's queued splash lands at the same drain (P02). |
| 29 | Where combat heals read `HEALING_RECEIVED_PERCENT` | One engine heal path / each healer | **One engine heal path** beside the Block-gain path: the Healed window, then the healed unit's `HEALING_RECEIVED_PERCENT`, rounding halves up at the end of the window, never below 0. Every heal (staves, potions, lifesteal, terrain) goes through it. | **Answered October 26, 2026:** as recommended. |
| 30 | What "this unit" means for wide-scope effects, and how phase facts (no actor) match | Per fact / per unit in scope | **Once per fact.** Counters, charges and Chance are checked once per fire. "This unit" is the owner's unit, or for army and rune effects the fact's unit; an army effect whose condition names "this unit" on a fact with no unit is a content error (diagnostics). Filtering per unit is a selector's job (`AllOfScope`, `Area`). Phase Start and Phase End match the owner's side. Brothers in Arms needs a selector filter that doesn't exist yet (heirlooms plan). | **Answered October 26, 2026:** as recommended. |
| 31 | Who reports content errors and cap overflows (question 7 says `push_error`) | Engine logs / engine collects, session reports | **The engine collects them in `diagnostics`, never logging;** EB6's session reports them with `push_error` (`NetLog` in release). Tests assert the list is empty. | **Answered October 26, 2026:** as recommended. |
| 32 | The base of a percent key no one sets (it read 0, cancelling every heal) | Per-key default table / caller passes it | **A per-key `CampaignValue.DEFAULT_BASES` table**, next to `RULE_MAX`. Fix F7. | **Answered October 26, 2026:** as recommended. |
| 33 | What happens to a defeated unit's effects, a stowed weapon's effects, and reactions already queued by a unit later defeated | Engine reads the state / P02 unregisters | **The engine reads the state:** such effects go dormant (fix F8). Reactions queued before a defeat still resolve, with the context they were queued with (a Brute killed by the counter still splashes, from its old tile). | **Answered October 26, 2026:** as recommended. |
| 34 | What `ExchangeOutcome`'s "expected damage before defeat" measures (`exchange_outcome.gd` assumption) | Damage dealt given the attacker is defeated / over all branches | **Given the attacker is defeated:** "how much it does before it dies", the reading of `Godot_FE`'s TODO this settles. The AI plan (P05) may add others. | Open |
| 35 | What a player forecast shows for a random pick, such as `RandomOf` (`forecast_rolls.gd` assumption) | First candidate / mark it random | **The sandbox keeps the first candidate, and its `RollRecord` marks the pick as random,** so P07 shows "a random ally" instead of naming one, as question 8 does for Chance. | Open |
| 36 | How `SampledRolls` turns a candidate's ids into numbers for `RngKey.mix()` (`sampled_rolls.gd` assumption) | As the class doc describes / other | **As built and documented in the class doc.** Only the host's AI samples; the rule must stay fixed within a build so a resumed battle decides the same. | Open |
| 37 | Assumptions left from EB1–EB2: a rune is the least specific source (`modifier.gd`); a floor applies before a cap, so a cap below a floor wins (`value_breakdown.gd`); on equal specificity the lowest source id wins (`value_breakdown.gd`); map tiles are never negative (`combat_fact.gd` `NO_TILE`) | Confirm / change each | **Confirm all four.** No MVP content hits the first three; P04 takes "no negative tile coordinates" as a map rule. | Open |

## Scope

**In scope**

- `CombatBus` and `CampaignBus`: typed signals grouped by domain, a tracer, and the
  `CombatFact` / `CampaignFact` payloads.
- The effect engine: registration, trigger dispatch with scope filters, conditions, inline and
  queued operations, a reaction queue, counter lanes, charges, timed modifiers, permissions, value
  queries with a source breakdown, and a forecast mode that changes nothing.
- The effect data model as inspector-authored Resources: `EffectDefinition`, building blocks
  (conditions, operations, target selectors, value sources), carrier definitions, and effect text
  generated from data.
- `EffectInstance` (runtime state) and stable ids.
- `EffectCatalog` and content tests.
- `CombatSession` and `CampaignSession` skeletons: per-map state holder, RNG-stream injection
  point, engine, bus, fact log, command entry, playback queue. Also the campaign→combat bridge
  (register carriers at battle start, write campaign-lane counters back at the end).
- Wire (network) and save serialization helpers for facts and effect instances.
- A headless test suite and golden fact logs for one fixture per content pattern.
- Docs: `docs/design/event-bus.md` and the design-doc edits answered in questions 10 and 11.

**Out of scope** (each belongs to a downstream IMPL plan)

- The combat rules themselves: movement, the exchange, the damage-stage calculation, Block and
  Stance refresh, Shove, objectives. This plan provides the hooks, keys and stages they use.
- Content: the `.tres` files for real heirlooms, items, traits, curses, runes and enemies (only
  test fixtures here).
- AI, intents, the forecast UI, the combat HUD, animations and audio.
- Network transport: the `Net` autoload, RPCs, command validation rules. Its IMPL plan must read
  `steam_multiplayer_kit/` first.
- The save-format change to one battle state per map (game-vision.md Still open).
- Status effects (post-MVP). The engine supports their owner and lane model; no status blocks ship.
- Migrating existing autoload signals (`SaveService.run_ended` etc.).

## Design Basis

**game-vision.md:** Combat (action economy, turn phases, exchange, damage stages, Block, Stance,
triangle, Shove); Combat maps (parallel maps, reinforce, runes on a teammate's map, spectate, game
speed, fast-forward, co-op ownership); Run-wide resources (runes, convoy, heirlooms); Units
(experience, Standout, upgrades, inventory); Enemies (intents, ruthless AI, Model 1 enemy classes);
Run structure (economy, grades, shops).

**Effect design docs:** effects-system.md and effect-triggers.md (all), heirlooms.md, items.md,
weapons.md (named effects), unit-roster.md (traits, upgrades, Sidearm), enemy-roster.md (traits,
signature moves, ruthless AI), the-darkness.md (darkness step, co-op, effects), map-objects.md
(rules, Object used, explosions), events.md (curses, event outcomes), multiplayer-combat-options.md,
save-system.md.

**master-ideation.md:** Starting and Commander Heirlooms, relic examples, and runes
("units and heirlooms can generate runes" — supported by the campaign operations, not built). Its
"cap at 8–12 relics" is superseded by heirlooms.md (no cap).

**Depends on open vision items:** "Multiplayer: the save change to one battle state per player"
(Still open) — this plan keys effect state by session so that change can land without reshaping
it.

### Re-review against the design docs

What changed from our conversation once the design docs were read:

| Earlier idea | Now | Why |
|--------------|-----|-----|
| "Relics" | **Heirlooms** (curses are negative heirlooms) | Design vocabulary |
| A modifier pipeline with explicit priority order | **Order-free stages:** flat values add, percent values multiply | game-vision.md damage stages; effects-system.md |
| One `Events` autoload with `Events.combat` | **One session (state, RNG, engine, bus) per map, under a `CombatEncounter` that mediates cross-map effects and rules** | Parallel co-op maps run at the same time; heirlooms can count partner units' actions |
| Trigger subclasses (`OnDamageTakenTrigger`) | **A trigger enum** | Catalog triggers have no parameters; parameters live in conditions, selectors and value sources |
| Reactions only | **Inline and queued operations** | "Take half damage from *that* hit", "*that* attack deals double damage" |
| — | **Target selectors** as a block family | "that ally", "the shover", "adjacent allies", "a random unit in this army" |
| Combat-only modifiers | **Campaign value modifiers too** | Economy heirlooms, curses (Short Wick, Hunted, Clouded Sight) |
| Runes as possible sockets | **Run-wide consumables with no trigger** | game-vision.md Run-wide resources |
| Status effects in v1 | **Supported by the model, not shipped** | No statuses in the MVP |
| Forecast on the host | **Forecast on every peer**, from a mirrored state | The client's UI shows it; host round-trips on hover would lag |
| — | **Keep most of `Godot_FE`'s own unbuilt bus design (D1–D8)** | See Legacy Behavior |

**Conflicts found between design docs** (questions 10–12):

1. effect-triggers.md (Turn phases) and the multiplayer-combat-options.md facts table say all
   co-op players share one player phase. game-vision.md says each parallel map runs on its own
   turns.
2. save-system.md checkpoints a battle "once every player has ended their turn". On parallel maps
   that moment doesn't exist.
3. effect-triggers.md has no campaign-level triggers, but items.md (Training Weights, Resonant Ore,
   Royal Crest), heirlooms.md (economy, starting heirlooms) and events.md (curses) need them.
4. effect-triggers.md lists Darkness damage taken as a trigger, and heirlooms.md's Lantern Oil
   modifies that damage ("take 50% less"). That only works if the trigger fires before the damage
   is applied, which this plan makes explicit (question 5).

## Legacy Behavior

| Godot_FE file | Behavior | Keep / Change / Drop | Reason |
|---------------|----------|----------------------|--------|
| `scripts/resources/Items/special_effect.gd` | ~30-value effect enum with weight type, activation type, threshold, chance | Change | Becomes building blocks (conditions, operations, value sources). Activation fields were never called. |
| `scripts/combat/controllers/combat_exchange.gd` (26 checks) | Effects checked inline in combat code | Drop | Replaced by value queries and trigger dispatch |
| `special_effect.gd` `THORNS`, `INCOMING_DAMAGE_AUGMENT` | Declared, never read | Drop | Not ported; content can re-add them as blocks |
| `scripts/resources/Items/WeaponDefinition.gd` `WEAPON_SPECIALS` | Deprecated duplicate vocabulary | Drop | One vocabulary: effect-triggers.md |
| `scripts/Constants/EffectConstants.gd`, `combat_unit_status_effect_manager.gd` | Status effects with their own `DECAY_TRIGGER` list | Change | Statuses use the same triggers and lanes (post-MVP) |
| `scripts/resources/effects/UnitStatusEffectDefinition.gd` vs `combat_unit_status_effect.gd` | Definition and instance split | Keep | Generalised to every carrier |
| `scripts/Unit/inventory.gd:30`, `ui/battle_prep_new/shop/shop.gd:121,130` | An item instance is a `.duplicate()` of its whole `ItemDefinition` | Change | `ItemInstance` holds only id, definition id, deltas, granted effects and state. Old doc 05 §6 recommends the same split |
| `scripts/resources/Items/weapon_stats.gd:29` `apply_weapon_stats` | Events bake stat changes into the item's fields | Change | Deltas kept as sourced modifiers, so they can be explained, priced and rebalanced |
| `campaign_map/events/event_selection.gd:291-300` | Event items from a loot table (`loot_table_item_entry.gd:8` returns the shared `.tres`) or the `iron_sword` fallback (`:295`) are modified **without duplicating** | Drop (bug, not ported) | Modifying a shared definition changed every later copy of that item. Read-only definitions plus the hash test make this impossible |
| `scripts/Unit/unit.gd:84,119` | Units copy their type's `base_stats`, then are modified directly | Change | Unit instances keep sourced deltas and pending gains over a read-only type (units plan) |
| `combat_exchange.gd:208` `do_damage()` | HP, audio, numbers and await in one function | Change | Rules emit facts; presentation plays them |
| `Combat.gd:113-122`, `CController.gd:1013`, `:1944` | Signal handshakes and awaits | Drop | Rules never await; presentation-only request objects |
| `Combat.gd:261` `register_combat(self)` | Node references passed by signal | Drop | Facts carry ids |
| `ui/combat/combat_ui.gd:199-201` (22 calls) | UI drives controller internals | Change | UI sends commands to the session |
| `docs/COMBAT_SIGNAL_BUS_PLAN.md` D1–D8 (never built) | Scene-local bus with domain channels | Keep D1, D2, D3, D5, D8; change D7 | D1 per-session bus, D2 domain channels, D3 queries are calls not messages, D5 completion on request objects, D8 nothing per-frame. D7 ("emission order is not a contract") stays true for presentation signals but **not** for effect dispatch, which must be deterministic. |
| `scripts/combat/ai/aiAction.gd` `generate_attack_action_rating`, `combat/Combat.gd` `calc_expected_combat_exchange` (`:1196`) | AI rates attacks by expected damage, a max-damage lethal check and a no-retaliation bonus | Keep the intent; change the math | Kill chance becomes a probability from branch simulation, so the AI can gamble. Fixes the documented bug where `attacker_hit_chance` was never assigned, zeroing the kill bonus (`docs/systems/08_grid_pathing_ai.md` §6), and the "dies before max damage" TODO. Weights move to the AI plan |
| `docs/systems/14_multiplayer_integration.md`, `16_rebuild_playbook.md` | Host-authoritative command → resolve → event → replay; loopback for solo; "rules return events, never wait on a screen" | Keep | Matches effects-system.md |

Tuning values carried over: none. This plan sets no gameplay values; the only numbers are the
safety caps from question 7 (depth 16, 256 reactions per step), which affect only content bugs.

## Approach

### The shape

```
Content     EffectDefinition + blocks inside carrier Resources (.tres, inspector)    read-only, keyed by id
   ↓
Model       Session state (units, items, map) + EffectInstance (counters, charges)   plain data, ids
   ↓
Rules       resolver → EffectEngine (dispatch, queries) → ordered facts             pure; host only
   ↓ fact batch
Session     CombatSession (one per map) · CampaignSession (one per run)             owns state, RNG, engine, bus, log
   ↓ commands in / facts out ───── net adapter (multiplayer plan) ─────
Presentation  CombatBus / CampaignBus signals during playback                     every peer: UI, VFX, audio, camera
```

Dependencies point down; information travels up as facts. **Rules never wait on a screen.**

### Which mechanism for which need

| Need | Mechanism | Runs on |
|------|-----------|---------|
| An effect reacts ("Phase Start: gain 3 Block") | Engine **trigger dispatch** | Host |
| A number is computed (damage stage, Hit, MOV, price, XP %) | Engine **value query** with a source breakdown | Host, plus the forecast on every peer |
| A rules system tallies (XP, Standout, grades, objectives) | Engine **observer**: read-only, called at dispatch time | Host |
| Something is shown (HP bar, damage number, sound, camera) | **Bus signal** during playback | Every peer |
| A player acts | **Command** to the session, validated | Host |
| The UI needs an answer (a choice popup) | **Request object** with `completed`, presentation only | Local |
| A system needs a value now | **Direct call** (old D3) | Anywhere |
| Per-frame or per-tile data | Not on any of these (old D8) | — |

### Facts and buses

- A **fact** is one thing that happened, with past-tense meaning: `CombatFact` (or
  `CampaignFact`), a `RefCounted` with a `kind` and fixed typed fields. Fields: `seq`,
  `session_id`, `actor_id`, `target_id`, `amount`, `hp_amount`, `block_amount`, `damage_type`,
  `source` (attack, splash, bump, darkness, effect), `source_effect_id`, `tile`, `flags`.
- **Facts are a superset of triggers.** Every trigger in effect-triggers.md is a fact kind. State
  facts (unit moved, spawned, counter changed, timed modifier gained or expired, darkness advanced,
  object state changed) also exist so the client mirror and the presentation can follow along.
- **One payload type per bus** lets one condition, selector or value source work on every trigger
  (e.g. `PercentOfFact(50)` on Damage dealt and on Healed alike).
- `to_wire()` / `from_wire()` turn a fact into an array of primitives (save-system.md: never send
  a Resource).
- **Settled at EB1 (October 26, 2026):**
  - **Paired triggers are two facts.** A hit emits `HIT_DEALT`, then `HIT_TAKEN`. `actor_id` is
    always the unit the kind is about (the unit a scope tests); `target_id` is the other party. So
    `HIT_TAKEN`'s actor is the unit hit, and the log line draws received kinds as `<-`. Before
    Combat is one fact per participant; After Combat is one per surviving participant.
  - **`CombatFact.DamageType`** (`NONE`, `PHYSICAL`, `MAGIC`, `SPLIT`, `PURE`) lives on the fact,
    next to `CombatFact.Source`; weapons and the combat core use it.
  - **`source_effect_id` is an effect *instance* id**, so EB4 gives every `EffectInstance` an
    allocator id (a preset such as `next_effect_id()`), and `describe()` expands it (e.g.
    "bulwark on item:412").
  - **`hp_amount` / `block_amount`** are the parts of `amount` that reached HP and Block. For
    healing, `amount − hp_amount` is the overheal (`PercentOfFact(overheal)`).
  - **`CampaignFact`** fields: `seq`, `seat` (`NO_SEAT` = −1), `actor_id`, `target_id`,
    `definition_id`, `amount`, `source_effect_id`, `flags`. Kinds: `GAINED`, `COMBAT_ENDED`,
    `LEVELED_UP`, `EFFECT_ACTIVATED`, `COUNTER_CHANGED`. `CampaignBus` has the `run`, `army` and
    `effect` channels; P08 appends its kinds with the `map` and `economy` channels.
  - Every enum on a fact is append-only with explicit values. `NO_TILE` is `(-1, -1)`. `from_wire`
    accepts whole-number floats, so facts survive JSON (repro dumps).
  - **Gap for P02:** phase facts don't say which side's phase it is (`combat_fact.gd:TOD-001`).
- **`CombatBus`** groups signals in `RefCounted` domain channels, following old D2: `flow`
  (phases, turns, combat end), `unit` (moved, HP, Block, Stance, defeated), `action` (exchange,
  hits, shoves, objects), `world` (tiles, darkness, objects), `effect` (activated, counter changed,
  modifier gained or expired). Every typed signal carries the `CombatFact`, and `fact_played(fact)`
  fires for every fact, for the tracer and spectating.
- **`CampaignBus`** works the same way: `run`, `map`, `army`, `economy`, `effect`.
- Bus signals fire **during playback**, on every peer, in fact order. Nothing on a bus may change
  rules state.

### The effect engine

One `EffectEngine` per session.

- **Registration.** Carriers register their effects into the engine as `EffectInstance`s with an
  owner: a unit, an item (resolved to its holder), an army (a seat), or a rune. Instances are
  indexed by trigger kind (dispatch) and by value key (queries), so the cost scales with the effects
  that care, not with all effects.
- **Scope** is evaluated relative to the owner, as effect-triggers.md defines it: This unit, Your
  Unit (the owner's seat), Any Ally Unit, Any Unit. Instances whose scope can see other maps live in
  the `CombatEncounter`, not a session (question 12; see [Sessions](#sessions)).
- **Conditions** come in the three families from effect-triggers.md: Counter (Every Nth / First,
  with a lane), Chance (one `roll_percent` through the roll source), and While. While covers state
  (Exposed), comparisons (strict, re-checked at every attack), position (adjacent, max range,
  moved N+, within N, no ally closer), exchange role and darkness layer.
- **Counter lanes:** combat (reset each battle, saved in `COMBAT`) and campaign (reset per run,
  saved with the owner). One instance can have a counter in each lane. **Charges** (Burglar's Roll,
  heal-staff uses, potion uses) use the same two lanes. Combat-lane counters and charges start
  fresh in every `CombatSession` at battle start, so per-map uses (staves, potions, Guard Tonics)
  refill each combat, and they move with their instance when a unit changes maps; campaign-lane
  values (Elixir, lockpicks, run totals) are copied in and written back (P02 need N7).

#### Inline and queued operations

Effect text uses triggers in two ways, and the engine keeps them apart:

- **Inline:** the operation changes the action in flight ("take half damage from *that* hit",
  "*that* attack gains lifesteal", Lantern Oil's "take 50% less"). It runs immediately at the
  trigger point and adds stage modifiers or flags to that action's context. Stage math is
  order-free, so the order of inline operations doesn't matter.
- **Queued:** the operation is a new action ("gain 2 Block", "heal 3", Cleave's splash, "loses 1
  extra Stance"). It is added to the session's **reaction queue** and resolved after the current
  step, and it can trigger further reactions. Two safety caps catch content bugs (question 7): a
  chain stops at **16 generations** deep, and a resolution step (one unit's turn, one phase
  boundary, the darkness step, reinforcement arrival) stops at **256 reactions**. Map-object
  cascades are exempt: each object breaks once, so keg chains are bounded by the map. On overflow,
  the chain stops, what already resolved stays, and the engine records a diagnostic that the
  session reports with `push_error` (`NetLog` in release; question 31). Reactions to one fact
  resolve by role (the fact's actor, then its target, then others), then seat (enemy side last),
  then carrier kind (unit trait → weapon → equipment → Pouch item → heirloom → curse), then
  instance id. **Curses resolve last**, so a curse always acts on the finished result and can't be
  dodged by acquisition order (question 6). This removes reentrancy: thorns-style loops can't recurse mid-hit.

A trigger only has an inline window if it fires before its amount is committed (question 5):

| Trigger | Fires at | Inline window | Content that needs it |
|---------|----------|---------------|-----------------------|
| Attack made | Start of the attack, before the hit roll | Yes: Hit, damage stages, flags (lifesteal) of that attack | Iron Heart, War Ledger |
| Hit dealt / Hit taken | Hit roll succeeded, before the damage stages | Yes: every stage of that hit, through stage 8 (Stance loss) | Volley, Fletcher's Kit, Executioner's Brand, Breaker, Breaker's Maul |
| Crit dealt / Crit taken | Crit confirmed, before stage 3 | Yes | — |
| Healed / Healed an ally | Before the heal is applied | Yes: the healing amount | Cleansed Goblet, Cursed Blood |
| Darkness damage taken | Before darkness damage is applied | Yes | Lantern Oil |
| **Block gained** (new) | Before a Block gain from any source is applied | Yes: the amount gained | Brittle Guard; also the "gave Block" fact for personal XP |
| Damage dealt / Damage taken | After stages 6–7 | No | Lifesteal's heal reads its HP amount |
| Missed / Dodged, Exposed, Defeated an enemy / Defeated | After the event | No | Momentum, Warlord's Spoils, Grave Candle |
| Before Combat / After Combat, phase and unit-turn triggers | Step boundaries | No | Professional, Hunter's Horn, Vanguard, Phalanx |
| Shoved a unit / Shoved, Object used, Used a staff on an ally | After the action | No | Shoving Pole, Sapper's Fuse, Triage |
| Leveled up (campaign) | After stats are committed | No | Results-screen presentation; future reactions |

- **The reaction queue drains at every step boundary.** Before Combat is its own step, so
  Professional's Block and Hunter's Horn's Hit are in place before the first attack.
- **Level-ups are shaped by queries, not inline operations**, because their modifiers are
  order-dependent (a minimum must count every other gain). The level-up resolver asks in a fixed
  order: (1) roll growths for stats the permission `STAT_CAN_GROW` allows (Training Weights denies
  Speed); (2) add `LEVEL_UP_GUARANTEED_GAINS` (Training Weights +1 MGT, Resonant Ore's random
  non-Speed stat, Feast ingredients); (3) fill up to `LEVEL_UP_MIN_STATS` (Royal Crest: 3) from
  stats still allowed to grow. Random picks come from the campaign stream. The results screen can
  preview every rule. Level-ups only happen after combat (game-vision.md, Experience).
- **Steady numbers are value queries, not triggers:** XP percentages (Family Ring, Veteran's
  Medal), combat gold (Bounty Ledger, Gilded Purse), shop stock and prices (Merchant's Ledger,
  Guild Charter, Membership Seal). A post-MVP Garrison status ("a refresh keeps leftover Block")
  is a permission read by the Block refresh.
- **Deliberately absent windows:** "would be defeated" (the vision forbids preventing a death),
  "would become Exposed" (no content; it would undercut Stance), splash or bump damage taken (no
  content yet; added as a `source` condition on a damage trigger when needed).
- **Note for the units plan:** whether Breaker's extra Stance loss applies when the hit is fully
  countered (0 damage, normally no Stance loss) is unstated in unit-roster.md.

- **Value queries** compute a key (e.g. `CombatValue.MOVEMENT`, `DamageStage.MITIGATION`,
  `CampaignValue.ARMORY_PRICE_PERCENT`) for a subject. They gather the matching always-on effects
  and active timed modifiers, check their conditions live, sum flat values, multiply percent
  values, and apply any override. They return a **`ValueBreakdown`**, a total plus one line per
  source, so the forecast can print "8 dmg − 5 Iron Skin × 0.5 Bulwark (10th hit) = 2". The keys
  live in `CombatValue` / `CampaignValue` enums; each downstream plan adds its keys (EB2 seeds the
  combat core's, which are already approved).
- **Values are exact; rounding is per key** (P02 need N1, question 17). A query computes in floats
  and `get_value()` returns the exact total. Each key declares one rounding rule, applied once at
  the end by `get_int()`: `HALF_UP` (the default), `FLOOR` or `EXACT` (never rounded by the query;
  the `DamageStage` keys are `EXACT` because P02's stage 5 rounds the whole damage once). The same
  rule covers amounts shaped in an inline window: a heal or Block gain stays exact through its
  window and rounds halves up when applied; darkness damage floors with a minimum of 1 (P06).
  Rounding adds a tolerance of 1e-9 so float error at an exact half (5 × 1.1) never flips the result.
- **Read API and stat sheets.** Callers (combat rules, the AI, the forecast, the UI) never assemble
  a value themselves; they ask the session: `session.stats(unit_id).get_value(key, ctx)` for the
  number and `.explain(key, ctx)` for the `ValueBreakdown`. Behind that API each value has two
  parts:
  - **Static, cached:** unit type base, prefix, permanent deltas, item stats and deltas, and
    unconditional always-on modifiers, kept in a per-unit **stat sheet** in RAM.
  - **Contextual, live:** anything with a condition (While position or comparison, counters),
    inline "that hit" modifiers and timed modifiers, evaluated on every query, as effect-triggers.md
    requires ("checked live").
  - **Invalidation is fact-driven.** A fact that touches a sheet's inputs (item equipped, delta
    added, carrier gained or lost, timed modifier gained or expired, unit moved between sessions)
    marks that sheet dirty; it rebuilds on its next read.
  - **Verify mode** (tests and debug builds, off in release): every cached read is also computed
    fresh and must match, or it raises an error.
  - Sandboxes copy sheets instead of re-deriving them, which keeps AI branches cheap.
  - Nothing reads or writes disk during play: definitions load once, state lives in RAM, and saves
    happen only at save-system.md's checkpoints.
- **Timed modifiers** come from operations with an expiry: this exchange (ends at After Combat),
  until Phase End, until the end of the next phase, next attack, this combat. Examples: Momentum, War Horn, Tactical Map, Haste, Clarity.
  They are session state. Each one has an **end** and optional **uses** (P02 need N6):

  | End | Expires at | Content |
  |-----|-----------|---------|
  | `THIS_EXCHANGE` | After Combat of the exchange it was added in | — |
  | `UNTIL_PHASE_END` | Phase End of the phase it was added in (P02's Phase End step 5) | Iron Wall, Tactical Map, Haste, Clarity |
  | `END_OF_NEXT_PHASE` | Phase End of the phase after the one it was added in | War Horn ("your units keep the bonus through your next phase") |
  | `THIS_COMBAT` | Battle end (combat lane, dropped) | Momentum, Bloodied Banner |

  - The session counts phases (both sides); a modifier records the phase it was added in. One added
    between phases (at placement, before the first Phase Start) belongs to the next phase to start.
  - **Uses:** "next attack" is one use, spent when the holder's next attack that started after the
    modifier was added finishes, counters included, hit or miss (question 18). "Next attack this
    phase" (Clarity) is one use with `UNTIL_PHASE_END`; "next attack this combat" (Momentum,
    Bloodied Banner) is one use with `THIS_COMBAT`. Whichever comes first ends it.
  - **Boundary API:** rules code calls `EffectEngine.reach_boundary(boundary, subject_id)` with
    `ATTACK_RESOLVED` (the attacker's id), `EXCHANGE_END`, `PHASE_END` or `COMBAT_END`, at the points
    P02 names. The engine expires what is due and emits one `MODIFIER_EXPIRED` per modifier, which
    also invalidates the stat sheet.
- **Permissions** are boolean queries (may use remaining movement, open without a lockpick,
  Sidearm free swap, can be shoved, Speed can't grow). **Denial beats grant**, so a curse or a
  boss's Unshovable (a denial of `CAN_BE_SHOVED`, question 19) can't be quietly cancelled
  (question 9).
- **Modifier modes and their effect-text wording.** A value query applies them in this fixed
  order:

  | # | Mode | Effect text | Example |
  |---|------|-------------|---------|
  | 1 | Replace base | "X instead of Y" | Short Quiver: "bows reach 1–2 instead of 2–3"; a future "Scrapping pays 10% instead of 20%" |
  | 2 | Add / multiply | "+X", "+X%", "×X" (stage rules: flat adds, percent multiplies) | Bounty Ledger "+8 gold"; Gilded Purse "+25% grade bonus" |
  | 3 | Floor / cap | "at least X" / "at most X" | Royal Crest: "at least 3 stats" |
  | 4 | Fixed | "always X" | A future "Scrapping always pays 50%" |
  | 5 | Rule clamps | — (game rules, not effects) | Army size never past 8; HP never below 0 |

  - **Replace base** keeps every bonus: "10% instead of 20%" plus a +20-point heirloom gives 30%.
  - **Fixed** is the hard version: the final value regardless of every other modifier, including
    floors and caps; only the game's own rule clamps still apply. The breakdown names what it
    overrode ("50%: fixed by X, ignoring +20% Scrapper's Tongs"), so the trade-off is visible.
  - **Floors and caps:** the highest floor and the lowest cap apply.
  - **Conflicts** (question 9): at most one replace-base and one fixed modifier per value per
    unit or player, enforced by a content test. A runtime collision resolves to the most specific
    source (the unit's own item, then its trait, then a heirloom; ties by instance id) and logs a
    warning. Copies of a replace-base or fixed modifier don't stack.
- **Observers** are read-only listeners on dispatch (XP tally, Standout, "lost no units",
  objectives). They run at resolve time on the host, so their state is consistent with the state
  that gets saved.
- **Forecast mode** runs the real resolver in a sandbox; see
  [Forecast and AI simulation](#forecast-and-ai-simulation).

#### Forecast and AI simulation

A forecast is a **simulation, not a separate calculation**. The same resolver that executes a
command runs on a **sandbox**: a scratch copy of the state the action can read, its effect
instances included. Inside the sandbox everything runs normally: counters advance, reactions
queue and resolve, timed modifiers apply, so Flow's 3rd attack and a Stance break enabling crits on
later attacks appear within one exchange, and Momentum's +15 Hit after a miss appears from the next
exchange (question 28). Nothing leaves the
sandbox: the real state, the real RNG stream and the real counters are untouched, and no fact
reaches the bus. Because it is the same code, **the forecast equals what executes** by construction.

**Every random decision goes through a roll source** that reports the decision's probability: hit
rolls (2RN, so the reported probability is the true two-roll probability, not the displayed Hit),
crit rolls, Chance conditions and random target selectors.

| Roll source | Used by | Behavior |
|-------------|---------|----------|
| `LiveRolls` | Real resolution on the host | Wraps the `RngStream` it is given at construction (the seat's `COMBAT_ROLLS` stream, P13) and draws only from it (P13 need R-N1) |
| `ForecastRolls` | The player forecast (question 8, A) | Hits land, chance effects fail; every probability is reported for display, and chance-gated effects are listed as "25%: +X" lines |
| `ForcedRolls` | AI branch enumeration | Returns a given outcome sequence and its combined probability |
| `SampledRolls` | AI sampling when branches are too many | A deterministic generator seeded with P13's `RngKey.mix()` over the session `seq` and the candidate (unit, tile, target, weapon), so a resumed enemy phase makes identical decisions; never a stream (P13 need R-N2) |

**The `RollSource` interface** (P02 need N8), shared by all four. Rolls are `Godot_FE`'s
(`CustomUtilityLibrary.random_rolls_bool`): d100 means an integer from 0 to 99.

| Method | Rule | Reported probability |
|--------|------|----------------------|
| `roll_hit_2rn(hit_percent: int) -> bool` | Two d100; hit if their integer average is below `hit_percent` | The true two-roll probability (pairs summing to at most `2 × hit_percent − 1`, over 10,000) |
| `roll_percent(chance: int) -> bool` | One d100; success if below `chance` (crits, Chance conditions) | `chance` / 100 |
| `pick_index(count: int) -> int` | Uniform pick (`RandomOf` selectors) | 1 / `count` per choice |

Each call appends a `RollRecord` (kind, displayed value, probability, outcome) to the source, which
is what the forecast displays and the branch enumeration multiplies.

**What the AI gets:** an `ExchangeOutcome` summary built by running branches (every hit or miss,
crit, chance proc, ending early when either unit is defeated): probability of a kill, probability
of the attacker dying, expected damage dealt and taken (to HP and Block), maximum damage, expected
damage before defeat, and probability of breaking Stance. This is `Godot_FE`'s expected-damage plus
max-damage approach made exact, and it settles its TODO ("a unit will most likely die before doing
maximum damage") because each branch stops at a defeat. The AI can now gamble: a 40% kill is worth
40% of a kill. The rating formula and its weights belong to the AI plan, with `Godot_FE`'s values as
the basis (kill bonus 5000, damage 100, no-retaliation bonus 50).

**Cost:** the AI evaluates tiles × targets × weapons × branches per enemy. The redesign keeps the
weapon factor small: enemy classes carry one weapon (game-vision.md Model 1) and player units at
most two (Weapon slot plus a stowed weapon), where `Godot_FE` cycled a 4-slot inventory. The sandbox
must be cheap to create (only the state an exchange can read, copied on write) and EB9 measures it.
Exact enumeration up to a branch budget, then sampling, is the AI plan's choice once the numbers
exist.

**Sandbox state hook** (P02 need N9). The engine can't know the combat core's state, so EB4 defines
an abstract `SandboxState` (`RefCounted`) with `copy_for_sandbox() -> SandboxState` and the map
reads and writes the engine needs (the full list is fix F6). A session holds its rules state as a `SandboxState`; the sandbox calls `copy_for_sandbox()` and
copies the engine's instances, counters, timed modifiers and stat sheets itself. P02's
`CombatState` extends it (copy on write where it matters; no nodes or Resources). EB4's tests use a
small fake state.

**Threading.** Sandboxes share no mutable state, so candidate evaluations are independent and can
run in parallel on Godot's `WorkerThreadPool` (a group task over candidates, waiting for all to
report back). This plan makes that safe; the AI plan decides whether to use it, from EB9's numbers.

- **Real resolution stays on the main thread.** Only sandboxed simulation may run on workers.
- **Thread-safety rules for every block, the engine and the sandbox:** no node, scene-tree,
  autoload or bus access; no global RNG; no writes to shared containers; definitions and the
  catalog are loaded on the main thread beforehand and only read on workers. effects-system.md's
  "effects never touch nodes, UI, audio or disk" already implies most of this.
- **Deterministic merge.** Results are combined in candidate order, never completion order.
  `SampledRolls` is seeded per candidate (unit, tile, target, weapon, session `seq`), never per
  thread, so thread count and timing can't change a decision, and a resumed enemy phase repeats
  it.
- **Hiding the rest.** If the AI still takes noticeable time, the enemy phase can be sent as one
  sub-batch per enemy: playback of enemy 1 starts while enemy 2 is planned. The phase stays one
  command; only delivery is split.

Clients run player forecasts on their mirror; the AI runs only on the host.

**Stub — targeting forecast for ranged and multi-tile attacks (investigate later).** `Godot_FE`
had forecast problems when a long-range weapon could reach a target from several tiles. The
forecast depends on where the attack is made from: terrain avoid, "at maximum range" (Volley,
Fletcher's Kit), "moved N+ tiles" (Charge), and whether the defender can counter at that distance.
The contract here is that every forecast takes **origin tile, path and weapon** as inputs, and the
atomic unit-turn command fixes all three before confirm. The combat UI and targeting plan
investigates the old defect (`Godot_FE/docs/systems/08_grid_pathing_ai.md` FR-GRID-6, targeting
and weapon cycling) and designs tile selection for ranged attacks.

### Effect data model (inspector-authored)

An effect is **trigger → conditions → operations**, with optional counters and charges
(effects-system.md). Everything below is a `Resource`, so the Godot inspector lists every block
type in its dropdowns. That is the "UI configurable" goal.

| Block | Shape | MVP set (covers every MVP trait, heirloom, item, curse, rune and enemy trait in the design docs) |
|-------|-------|------------------------------------------------------------------------------------------|
| `EffectDefinition` | `id`, `trigger` (enum, `ALWAYS` for always-on), `scope`, `conditions[]`, `operations[]`, counter and charge settings, `tags` (`unique`, `curse`) | — |
| `EffectCondition` | Base class with `test(ctx)` and `describe()` | `CounterCondition`, `ChanceCondition`, `WhileStateCondition`, `WhileCompareCondition`, `WhilePositionCondition`, `WhileRoleCondition`, `WhileLayerCondition` |
| `EffectOperation` | Base class with `apply(ctx)`, `describe()`, and whether it is inline | `ModifyValue` (always-on modifiers), `ModifyThat` (inline), `AddTimedModifier`, `GainResource` (HP, Block, Stance), `DealSplash`, `ChangeBaseStat` (permanent, e.g. stat boosters, Training Weights), `SetPermission`, `CampaignGrant` (gold, heirloom, recruit, rune), `CustomOperation` (the script escape hatch) |
| `TargetSelector` | Who an operation affects | `Owner`, `FactActor`, `FactTarget`, `Area` (center, radius, side filter, include self), `AllOfScope`, `RandomOf` (`pick_index` through the roll source) |
| `ValueSource` | How much | `Constant`, `PercentOfFact` (amount, HP amount, overheal), `StatOf`, `CountOf` (selector), `CounterValue` |
| Carrier definitions | `id`, display data, `effects: Array[EffectDefinition]` | Base `EffectCarrierDefinition`; heirlooms (curses are heirlooms tagged `curse`), items, unit types, enemy classes and runes extend it in their own plans |

#### Definitions and instances

Definitions are authored once and never change at runtime. Everything that belongs to one item or
one unit lives on its instance, as the differences from its definition:

| Instance | Holds |
|----------|-------|
| `ItemInstance` | `instance_id`, `definition_id`, `granted_effect_ids` (standalone catalog effects, e.g. *Infuse*'s "Hit dealt: heal 2"), `stat_deltas` each with its source (e.g. AtkX +1 from Cavern of Echoing Steel), charges, and its effects' counter state. All of it moves with the item between units, the convoy and maps. |
| Unit (contract for the units plan) | `instance_id`, unit type id, prefix id, level, upgrade state, item instance ids, permanent stat deltas each with its source (Dark Goblet, stat boosters), and **pending level-up gains** with a remaining count (*Drink the Sap*: "+1 MGT, 2 remaining"; Feast ingredients: count 1), read by the level-up queries. |

- **Instance ids** are `<kind>:<counter>` strings (`item:412`, `unit:57`, `enemy:88`), minted only
  by the host's `InstanceIdAllocator` (owned by `CampaignSession`) through a preset per kind
  (`next_item_id()`, `next_unit_id()`, `next_enemy_id()`, …) that share one counter. Ids are never
  parsed (the definition lives in `definition_id`) and never reused. Every session on the host
  mints from the same allocator on the main thread, so parallel maps can't collide. The counter is
  saved in the campaign state and at every `COMBAT` checkpoint, so a resumed enemy phase mints
  identical ids; `end_battle()` writes it back, and a restart from Begin uses the value captured
  at Begin.
- **Deltas are modifiers, not edited fields.** They go through the same value queries and modes
  as every other modifier, so breakdowns can say "AtkX 2 (+1 Cavern of Echoing Steel)".
- **Price and scrap value follow the deltas** (question 13): the items plan defines how much each
  kind of delta is worth; this plan guarantees the deltas and their sources are available.
- **Display name** of a modified item is undecided ("Infused", "Modified"); the instance exposes
  whether and how it was modified.
- **Definitions are read-only by rule and by test:** a content test hashes every catalog
  definition before and after the headless suite and fails if any changed.
- **Saves and the network carry instance data only:** plain JSON ids, deltas and counters, never a
  Resource.

- **The escape hatch rule:** when the same need appears in two pieces of content, it becomes a
  block; until then a `CustomOperation` script is fine.
- **Effect text is generated** from `describe()` in the effect-triggers.md grammar
  ("[Every Nth] <trigger> by <scope> [this combat | this campaign]: <operation>"), so text and
  behavior can't drift.
- **Definition vs. instance.** Definitions are shared and read-only, because Godot shares a loaded
  `.tres`. All mutable state (owner, counters, charges, granted effects) lives in `EffectInstance`
  or the owning `ItemInstance`, keyed by stable ids.
- **Content tests** fail the build on: a duplicate id; a block whose `describe()` is empty; a
  heirloom scoped This unit; an inline operation on a trigger with no inline window. They **warn**
  on a heirloom scoped Any Ally Unit or wider without the `unique` tag (effects-system.md).

Coverage check against real content (each becomes a fixture with a golden fact log in EB4):

| Content | Built from |
|---------|-----------|
| Vanguard (Drengr) | `PHASE_START` + `WhilePosition(no ally closer)` + `GainResource(BLOCK, Constant 3)` |
| Iron Heart (Commander Heirloom) | `ATTACK_MADE`, Your Unit + `Counter(7, combat)` + inline `ModifyThat(lifesteal)` |
| Momentum (Fighter) | `MISSED` + `AddTimedModifier(HIT +15, next attack)` |
| Phalanx (Lancer) | `UNIT_TURN_START` + `GainResource(BLOCK, CountOf(adjacent allies))` |
| Cleave (Brute) | `HIT_DEALT` + queued `DealSplash(Area(self, 1, any, exclude self), 2)` |
| War Horn (Warcaller) | `PHASE_START` + `Counter(2, combat)` + `AddTimedModifier(Area(self, 2, any), ATTACK +2, end of next phase)` |
| Overflowing Cup | `HEALED`, Your Unit + `GainResource(BLOCK, PercentOfFact(overheal, 100))` |
| Lantern Oil | `DARKNESS_DAMAGE_TAKEN`, Your Unit + inline `ModifyThat(MULTIPLIERS ×0.5)` |
| Bounty Ledger | `ALWAYS` + `ModifyValue(CampaignValue.COMBAT_GOLD, +8)` |
| Training Weights | `ALWAYS` + `ModifyValue(SPD −2)` + `SetPermission(STAT_CAN_GROW SPD, deny)` + `ModifyValue(LEVEL_UP_GUARANTEED_GAINS, MGT +1)` |
| Brittle Guard (curse) | `BLOCK_GAINED`, Your Unit + inline `ModifyThat(amount −1, minimum 0)` |
| Haunted (curse) | `PHASE_START` + `GainResource(RandomOf(army), BLOCK −2)` |
| Mend (rune) | no trigger; `GainResource(CommandTarget, HP, Constant 10)` (F4) |
| Breaker (Brawler) | `HIT_DEALT` + `Counter(first, combat)` + inline `ModifyThat(extra Stance loss +1)` (F4) |
| Professional (Sellsword) | `BEFORE_COMBAT` + `WhileMatchup(Advantage)` + `GainResource(BLOCK, Constant 3)` (F4) |

### Sessions

```
CampaignSession
└── CombatEncounter          one per combat node; owns cross-map effects and an encounter bus
    ├── CombatSession seat 0   map copy · RNG stream · EffectEngine · CombatBus
    ├── CombatSession seat 1
    └── CombatSession seat 2
```

- **`CombatEncounter`** owns the sessions of one combat node and is the only path between them.
  Sessions never hold a reference to each other. In solo it holds one session and its cross-map
  paths are no-ops. It owns:
  - **Encounter rules that span maps:** the combat ends when every map has finished; the team wins
    if anyone wins; reinforcement transfers; runes cast on a teammate's map; the co-op doc's light
    links (e.g. a team objective counter).
  - **Cross-map effect instances:** any instance whose scope can see units on other maps
    (non-positional Any Ally Unit or Any Unit). It holds their counters and charges.
  - **Forwarding:** for each trigger kind a cross-map instance needs, the encounter subscribes on
    every session's engine. After a session dispatches that kind locally, it forwards the fact to
    the encounter in the same step. This uses the engine's existing trigger index, so sessions
    without such instances pay nothing.
  - **Delivery:** an operation from a cross-map instance goes to the session where its target is
    ("that unit" → the fact's session; "Your Units" → the owner's session), into that session's
    reaction queue. Inline operations ("that hit deals +2") apply synchronously during forwarding,
    since every session runs in one process on the host.
  - **Rules:** positional conditions (adjacent, within N, max range, no ally closer) never match
    across maps. Cross-map order is the host's command arrival order, stamped with an encounter
    sequence number. Encounter facts (counter changed, team objective progress) go to every client
    on the encounter's own `CombatBus`, so client forecasts can peek encounter counters.
  - Cross-map heirlooms reach other players' units, so effects-system.md's **unique** tag rule
    applies to them.
- **`CombatSession`** holds one map's state, its seeded RNG stream (P13, injected), an
  `EffectEngine`, a `CombatBus`, the fact log and a playback queue. It accepts
  commands through one validated entry point and returns the fact batch each command produced. In
  co-op (Option B) the host runs one session per player's map. Sessions have their own `session_id`
  and a list of `seats`, so Option D's shared battles need no reshaping.
- **`CampaignSession`** holds run state and has its own engine and `CampaignBus`. It is the bridge
  into combat:
  - **Randomness is injected, never looked up** (P13 need R-N3). `CampaignSession` holds P13's
    `RngStreams` and hands out streams: the `CombatEncounter` receives the `ENCOUNTER_SETUP`
    stream and draws the whole setup once at battle start (reinforcement waves included); each
    `CombatSession` receives the setup results, its seat's `COMBAT_ROLLS` stream (wrapped in
    `LiveRolls`) and its seat's `MAP_LOOT` lookup. Neither ever sees the registry.
  - At battle start it builds the `CombatEncounter` and each seat's `CombatSession`, and registers
    that seat's carriers (unit traits, item instances, heirlooms, curses) in the session, or in the
    encounter for cross-map scopes, copying campaign-lane counters in.
  - Before `end_battle()` it writes campaign-lane values back; combat-lane state is dropped
    (effects-system.md Save impact).
  - Observers find sessions by signal, without an autoload: `CampaignSession` emits
    `combat_encounter_opened(encounter)` and `combat_encounter_closed(encounter)`, and the
    encounter emits `session_opened(session)` for each map. Who owns `CampaignSession` belongs to
    the campaign and run-flow plan (question 15).
- **Moving units between maps** (reinforcement) is done by the encounter: it moves their
  instances, with their state, from one session's engine to the other at the receiving map's next
  Phase Start. A rune cast on a teammate's map is a command the encounter routes to that session,
  with the caster's seat.
- **Playback.** The host plays its own fact batches; clients play the batches they receive. Both go
  through one `FactPlayback` queue, which applies game speed (a host lobby setting) and
  fast-forward with its pauses on a boss combat or a player unit's death. Spectating means attaching
  playback to another session's stream.

### Campaign hooks

The campaign engine uses the same model as combat, scoped per player (seat). Question 10 adds
these to effect-triggers.md:

| Campaign trigger | Fires when | MVP content |
|------------------|------------|-------------|
| Gained (this carrier) | The heirloom or item is acquired | War Chest, Family Relic, Abundance, Ancestral Weapon, Veteran Company, Mercenary Contract |
| Combat ended | A combat ends, for each player, won or lost | Refillable Potion |
| Leveled up | A level-up is committed | None yet (presentation) |

All are reaction-only. Node entered, Item scrapped and Shop opened wait until content needs them.

| Campaign value key | MVP content |
|--------------------|-------------|
| `COMBAT_GOLD` | Bounty Ledger (+8) |
| `GRADE_BONUS_PERCENT` | Gilded Purse (+25 points: 25% → 50%) |
| `SHARED_XP_PERCENT`, `UNIT_XP_PERCENT` | Veteran's Medal (+20%), Family Ring (+25%, holder only) |
| `SCRAP_PERCENT` | Scrapper's Tongs (+20 points: 20% → 40%) |
| `ARMORY_STOCK`, `GUILDHALL_RECRUITS`, `PRICE_PERCENT`, `FREE_REROLLS` | Merchant's Ledger, Guild Charter, Membership Seal, Tinker's Token |
| `MAX_ARMY_SIZE` (cap 8) | Muster Roll, Abundance, the Company Charter event |
| `EXTRA_ENEMIES` | Hunted |
| `HEALING_RECEIVED_PERCENT` (both layers: Feasts heal on the campaign layer) | Cursed Blood, Cleansed Goblet |
| `INTENTS_HIDDEN` (permission, read by the client UI) | Clouded Sight |
| `LEVEL_UP_GUARANTEED_GAINS`, `LEVEL_UP_MIN_STATS`, `STAT_CAN_GROW` | Training Weights, Resonant Ore, Royal Crest, Feast ingredients |

Combat-layer keys read at battle start: `DARKNESS_ARRIVAL_OFFSET` (Short Wick),
`POUCH_ITEM_WEIGHT` (Heavy Pack).

Gilded Purse and Scrapper's Tongs are written "instead of" in heirlooms.md but are built as
additions, so copies stack as effects-system.md promises; EB8 updates their text to "+25% grade
bonus" and "+20% scrap value". Generated effect text uses "instead of" only for real overrides.

### Commands, concurrency and rejoin

**Resolve, then play.** Every command resolves completely on the host before any of it is shown;
peers then play its fact batch. The **enemy phase is one command**: the last player end-turn on a
map resolves player Phase End, enemy Phase Start, every enemy turn in order (each AI decision sees
the resolved result of the one before), enemy Phase End, the darkness step, reinforcement arrival,
the next player Phase Start and the new intents, as one batch. No player can act during the enemy
phase (runes are player-phase only), so nothing can interrupt it. Fast-forward, its pauses and game
speed change playback only.

**Serialization.** Each session is the single serialization point for its map:

- Commands from every seat enter the session's queue on the host, stamped on arrival, and resolve
  one at a time. A command resolves **atomically**: the action, every reaction, and the drained
  reaction queue, before the next command starts.
- All real resolution runs on the main thread. Arrival order is therefore well defined across
  sessions too, which the encounter's cross-map counters rely on. (Sandboxed AI simulation may use
  worker threads; see [Forecast and AI simulation](#forecast-and-ai-simulation).)
- Commands are **validated against the state at resolve time**, not at send time. First arrival
  wins, matching the shared-shop rule in game-vision.md. An invalid command is rejected with a
  reason, sent as `command_rejected` to that seat only; it costs nothing (no movement, no action
  spent).
- Clients never apply anything optimistically. A confirmed command shows as pending until its facts
  arrive.

**Command contracts** (for the combat core and multiplayer plans):

| Contract | Rule |
|----------|------|
| Atomic unit turn | A unit's turn is **one command: path + action**. The client previews the move and the action menu on its mirror; nothing is sent until confirm, so cancel and undo are free. A partner can't take a target between someone's move and their action. |
| Ownership | The host checks the sender's seat against the unit's owner. Runes are the exception: any seat may cast one on a map during that map's player phase. |
| Phase end per map | A map's player phase ends when every seat with units on it has ended its turn. A seat that has ended can't act. The last end-turn is the enemy-phase command. |
| Stale forecast | Each command carries the `seq` its forecast was based on. Attack, staff and shove commands are rejected if any fact since that `seq` touched the actor, the target, or a unit or tile the forecast's effects read. The client shows the refreshed forecast and asks for confirmation again. Moves only need to be legal. This keeps "the forecast equals what executes". |
| Selection markers | Presentation-only markers ("seat 1 is targeting chest X") reduce collisions before they happen. Not rules; owned by the multiplayer and UI plans. |

**Rejoin and resume.** The bus is never saved or resent; presentation always starts from state.

- A full quit or crash resumes from the last checkpoint (save-system.md `BATTLE`); a lost combat
  file restarts from Begin (`BATTLE_RETRY`). Unchanged by this plan.
- For a client that drops while the host keeps running:
  - Every fact carries its session's `seq`; encounter facts carry the encounter's `seq`.
  - `CombatSession.snapshot()` / `load_snapshot()` and the same on `CombatEncounter` reuse the save
    capture helpers (EB7), so saving and rejoining can't drift apart.
  - The host keeps each session's facts in memory since its last checkpoint. A rejoining client gets
    the latest snapshot plus the facts after it, or a fresh snapshot if it is too far behind.
  - Mirrors are idempotent: a fact with a `seq` already applied is ignored.
  - **Presentation rule for every downstream plan:** each view can rebuild itself from mirror
    state at any moment, not only by accumulating facts.
- A dropped player's map can pause while other maps continue; the encounter waits for it before
  the combat ends. **The drop policy** (how long to wait, skipping the turn, timeout or kick) is a
  gameplay decision for the multiplayer plan, recorded under Still open in game-vision.md.

### Logging and debugging

Logging builds on the existing `NetLog` autoload (`scripts/autoload/net_log.gd`): leveled,
categorized, and tagged with the peer id, which matters most when two machines' logs are compared.

- **New categories** (appended to `NetLog.Category`; existing values unchanged): `COMBAT`
  (commands, facts, phases), `EFFECTS` (activations, counters, cache), `CAMPAIGN`, `AI`. `NetLog`'s
  class doc is widened from "networking code" to the whole game.
- **Readable ids everywhere.** `describe(id)` on the session turns an instance id into
  `item:412 (Iron Axe, Infused, held by unit:57 Hakkapel)`. Every fact, command and effect log
  line, and every `push_error` / `push_warning` from this system, uses it. Ids stay opaque in data;
  only text is decorated.
- **What each level shows:**

  | Level | Lines |
  |-------|-------|
  | ERROR | Reaction cap hit, cache verify mismatch, invalid content at load, unresolvable id |
  | WARN | Override collision, `command_rejected` (with reason), client mirror hash mismatch, unexpected rejoin catch-up gap |
  | INFO | Commands (seat, arrival stamp, `based_on_seq`, result), phase changes, battle start / end, unit transfers between maps, rejoin and snapshot |
  | DEBUG | Every fact as it resolves, every effect activation (counter before / after, inline or queued, what it changed), stat-sheet rebuilds, AI's top candidates per enemy with their ratings |

- **Line shapes,** each prefixed by NetLog's `[LEVEL][Category][peer N]`:
  - Fact: `s0#143 HIT_TAKEN unit:57 (Hakkapel) <- enemy:61 (Brute) amount 6 (hp 4, block 2) source attack`
  - Effect: `s0#143 EFFECT bulwark on item:412 (Iron Greatshield) owner unit:57: HIT_TAKEN counter 9 -> 10, FIRED inline MULTIPLIERS x0.5`
  - Command: `s0 CMD seat 1 unit:57 move+attack enemy:61 based_on s0#140 -> REJECTED stale forecast (s0#142 touched enemy:61)`
- **Hot paths are gated** with `NetLog.would_log()` before any string is built (gdscript.md §9.1).
- **Worker threads never log.** `NetLog` reads the multiplayer peer and is an autoload, which the
  threading rules forbid on workers. The AI collects its diagnostics into its results; the main
  thread logs them after the merge.
- **Desync detection** (debug builds): host and clients hash the session state after each batch;
  the host's hash travels with the batch, and a client logs WARN with the `seq` on a mismatch.
- **Repro dumps.** `debug_dump()` on a session writes its latest snapshot, the commands since it
  and the resulting facts as JSON to `user://logs/`. Snapshots and dumps carry the run seed, the
  build version and the live stream states (P13 need R-N4), so a dump names the run it came from. Resolution is deterministic, so a headless
  test can load the dump, replay the commands and reproduce the bug exactly.
- `project.godot`'s `file_logging/enable_file_logging` (already recommended by `NetLog`'s doc)
  keeps every run's lines in `user://logs/godot.log` on each machine.

### Contracts for downstream IMPL plans

Each plan below builds on this one. The table is the interlink map.

| IMPL plan (design doc) | Emits facts | Owns queries / keys | Registers carriers | Observers / save |
|------------------------|-------------|--------------------|--------------------|------------------|
| Combat core (game-vision Combat) | Phases, unit turn, Before/After Combat, Attack made, Hit, Miss, Damage, Crit, Exposed, Defeated, Shove, Healed, Used a staff | `DamageStage` (Attack, Mitigation, Critical, Multipliers), AS, AtkX, Parry, Hit, Avoid, Crit chance, CritX, Stance, Block gain, Shove distance, range, damage type, weight | — | Combat state section per session. Must follow the command contracts: atomic unit turn (path + action), enemy phase as one command, phase end per map, stale-forecast checks |
| Units and traits (unit-roster) | — | Stats, growth permissions | `UnitTypeDefinition` (trait, "+" trait) | Unit instance in `roster` |
| Weapons and items (weapons, items) | Item used, charges spent, item modified | Item stat modifiers, healing received; **price and scrap value from deltas** | `ItemDefinition`; `ItemInstance` with granted effects and sourced deltas | Instance state in `roster` / convoy; decides the modified-item display name |
| Heirlooms and curses (heirlooms, events) | Gained | Campaign values (economy, XP %, max army size, darkness offset, extra enemies, intent visibility) | `HeirloomDefinition` (army owner) | Per-player heirloom section |
| Runes (items) | Rune used | — | `RuneDefinition` (no trigger) | Per-player rune slots |
| Enemies and AI (enemy-roster) | Intent declared | The AI reads `ExchangeOutcome` from sandboxed simulation with `ForcedRolls` / `SampledRolls`; owns the rating formula (basis: `Godot_FE` kill 5000, damage 100, no retaliation 50) and the branch budget | `EnemyClassDefinition` (trait, signature move) | — |
| Darkness (the-darkness) | Darkness advanced, Darkness damage taken | Darkness damage, arrival offset | — | Darkness state per session |
| Map objects (map-objects) | Object used, keg exploded (splash) | Object Defense | — | Object state per session |
| Campaign and run flow (game-vision Run structure) | Run, node, combat start/end, rewards, gold, shop, level-up | Shop stock, prices, scrap %, grade %, shared and personal XP % | Bridge in `CampaignSession` | XP, Standout and grade observers |
| Events (events.md) | Option chosen | — | Event outcomes reuse operation blocks (`CampaignGrant`, granting effects to an item, adding a curse) | — |
| Multiplayer combat (multiplayer-combat-options) | Map finished, call for aid, reinforcement sent / arrived, seat dropped / rejoined | — | Uses `CombatEncounter` transfers and rune routing | Net adapter sends session and encounter fact batches and `command_rejected`; rejoin via snapshot + catch-up log; drop policy; selection markers; one combat state per map |
| Every UI / presentation plan | — | — | — | Views rebuild from mirror state at any moment; no optimistic changes; pending state on confirm |
| Combat UI and forecast | Commands only | Runs player forecasts (`ForecastRolls`) from origin tile, path and weapon; reads `ValueBreakdown` and generated text | — | Request objects for popups. Owns the stub: investigate `Godot_FE`'s ranged multi-tile forecast defect (FR-GRID-6) |

### Amendments from P02 and P13

Added October 26, 2026, before EB2, from the combat core plan's
[needs from P01](2026-10-26-combat-core.md#what-p02-needs-from-p01-eb2eb4) and the RNG plan's
[needs from other plans](2026-10-26-rng-streams.md#what-p13-needs-from-other-plans). Each row
names the step that builds it; rules already written into a section above are linked there.

| # | Need | Step | Where |
|---|------|------|-------|
| N1 | Exact values; rounding once, per key | EB2 | [Value queries](#the-effect-engine) (question 17) |
| N2 | `DamageStage` and the combat core's `CombatValue` keys | EB2 | Seeded keys, below |
| N5 | The combat core's permission keys | EB2 | Seeded keys, below |
| N3 | `EffectContext` fields for "that attack / that hit" | EB4 | Attack context, below |
| N4 | Inline flags: lifesteal, skip Mitigation, damage type override | EB4 | Attack context, below |
| N6 | Timed-modifier ends, uses and the boundary call | EB4 | [Timed modifiers](#the-effect-engine) (question 18) |
| N7 | Per-map reset of combat-lane charges | EB4 | [Counter lanes](#the-effect-engine) |
| N8 | `roll_hit_2rn` and `roll_percent` on every roll source | EB4 | [`RollSource` interface](#forecast-and-ai-simulation) |
| N9 | Sandbox copies the combat state through `copy_for_sandbox()` | EB4 | [Sandbox state hook](#forecast-and-ai-simulation) |
| N10 | `BLOCK_GAINED` inline window for every Block gain | EB4 | Block gains, below |
| R-N1 | `LiveRolls` wraps a given `RngStream` | EB4 | [Roll sources](#forecast-and-ai-simulation) |
| R-N2 | `SampledRolls` seeds with `RngKey.mix()` | EB4 | [Roll sources](#forecast-and-ai-simulation) |
| R-N3 | Streams injected into the encounter and sessions | EB6 | [Sessions](#sessions) |
| R-N4 | Run seed, build version and stream states in snapshots and dumps | EB7 | [Logging and debugging](#logging-and-debugging) |

**Seeded keys (EB2).** EB2 creates the enums with the combat core's keys already in them, so EB2's
tests run on real keys and P02 appends nothing later. Every key rounds `HALF_UP` unless noted.

- `CombatValue`: `ATTACK_SPEED`, `NET_WEIGHT`, `ATK_X`, `PARRY`, `HIT`, `AVOID`, `CRIT_CHANCE`,
  `CRIT_X`, `STANCE_MAX`, `SHOVE_DISTANCE`, `RANGE_MIN`, `RANGE_MAX`, `DAMAGE_TYPE` (an enum value:
  replace-base and fixed modes only), `EFFECTIVE_MODIFIER`, `STAFF_AMOUNT`, `MOVEMENT`. The combat
  core also reads `POUCH_ITEM_WEIGHT` from the campaign list, at battle start.
- `DamageStage`: `ATTACK`, `MITIGATION`, `CRITICAL`, `MULTIPLIERS`, all `EXACT`.
- Permission keys: `CAN_COUNTER` (denied while holding a staff), `CAN_BE_SHOVED` (allowed by
  default; Unshovable denies it, question 19), `MAY_MOVE_AFTER_ACTING`, `FREE_WEAPON_SWAP`,
  `SKIP_MITIGATION_ON_CRIT`.
- Base stats (HP, MGT, SPD, DEF, RES, CON; MOV is `MOVEMENT`) are appended in EB4 (question 21,
  F3). P03 owns their growths and meaning.

**Attack context (EB4).** `EffectContext` carries, for every trigger in an attack's or a hit's
inline window: attacker id, defender id, weapon instance id, origin tile, distance, exchange role
(attacker or defender), attack index within the exchange, whether the defender was Exposed before
this hit, and whether this hit is a crit. Inline operations set:

- **Flags** `LIFESTEAL` and `SKIP_MITIGATION`. Flags only turn on, never off, so the order of inline
  operations still can't matter.
- **A damage type override.** Two overrides on one hit resolve like a replace-base collision (the
  most specific source wins, with a warning).

**Block gains (EB4).** Every Block gain goes through one engine call that opens the `BLOCK_GAINED`
inline window. That covers `GainResource(BLOCK)`, Block staves, Guard Tonics and Phase Start effects
(Vanguard, Phalanx). The amount stays exact through the window and rounds halves up, never below 0
(Brittle Guard). The Phase Start refresh to 0 is not a gain. A negative amount (Haunted's −2) is a
loss: `BLOCK_LOST` (P02 CC1), with no window.

**Build order.** EB2 and EB3 need nothing else. EB4 also needs the RNG plan's R1–R3 (`RngKey`,
`RngStream`, `RngStreams`), which are pure and can be built alongside EB2–EB3.

#### Follow-ups from the EB2–CC1 build

Gaps the build of EB2, EB3 and P02 CC1 found (questions 19–22, answered October 26, 2026).

| # | Change | Step | Detail |
|---|--------|------|--------|
| F1 | Rename `CombatValue.Permission.UNSHOVABLE` to `CAN_BE_SHOVED`, default **allowed** | Fix-up before EB4 | Value 3001 unchanged; nothing uses it yet. The Unshovable trait is a denial. Remove the `# ASSUMPTION` |
| F2 | Append `item_id: String` to `CombatFact` (wire array 15 → 16 slots) | Fix-up before EB4 (amends P02 CC1) | The instance id of the item, weapon or rune the fact is about; empty otherwise. `ITEM_USED`: actor the user, target the recipient. `WEAPON_SWAPPED`: the weapon now in the Weapon slot. `RUNE_USED`: actor empty, target and tile what it was cast on, `amount` the casting seat. Runes get instance ids (`rune:N`) from the allocator's new `next_rune_id()` preset (EB6), so two copies of one rune are told apart. Remove both `# ASSUMPTION`s |
| F3 | Append base stat keys `HP`, `MGT`, `SPD`, `DEF`, `RES`, `CON` to `CombatValue.Key`, and one shared `Stat` enum (the same seven stats, `MOV` included) | EB4 | `STAT_CAN_GROW` and `LEVEL_UP_GUARANTEED_GAINS` modifiers name a `Stat` (resolves `campaign_value.gd` TOD-001). Training Weights' fixture uses `SPD` |
| F4 | Three blocks: `CommandTarget` selector; extra Stance loss as a `ModifyThat` target; `WhileMatchupCondition` (triangle Advantage, Standoff, Disadvantage) | EB4 | `EffectContext` gains the command target, the hit's extra Stance loss (added at stage 8, P02 question 10) and the attacker's triangle result. Fixtures: Mend (replacing "on the command's target" in the coverage table), Breaker, Professional |

#### Follow-ups from the EB4 build

Gaps the build of EB4 found (questions 23–33, answered October 26, 2026). All four were built in EB4.

| # | Change | Detail |
|---|--------|--------|
| F5 | Append `CombatFact.Kind.STAT_CHANGED` and an int field `key` (wire array 16 → 17 slots) | `STAT_CHANGED`: actor the unit, `amount` the delta, `key` the `Stat`; `ChangeBaseStat` records it. `COUNTER_CHANGED`: `key` is the lane. Empty (0) for other kinds |
| F6 | `SandboxState` is the engine's whole view of the map: 17 abstract methods, the contract P02's `CombatState` implements | `copy_for_sandbox()`; reads `unit_ids()` (defeated excluded, roster then spawn order), `has_unit`, `side_of`, `seat_of`, `tile_of`, `walking_distance` (with terrain, −1 for no path), `get_hp`, `get_block`, `get_stance`, `tiles_moved`, `darkness_layer`, `equipped_weapon_id`; writes `set_hp`, `set_block`, `set_stance` (called only by the engine's resource paths, which clamp and emit the facts); `deal_splash` (P02's one splash rule, recording through `EffectEngine.record`). "Within N" uses walking distance and "no ally closer" tile distance, per effect-triggers.md |
| F7 | `CampaignValue.DEFAULT_BASES` | `HEALING_RECEIVED_PERCENT` 100, `GRADE_BONUS_PERCENT` 25 (vision: grade bonuses +25% each), `SCRAP_PERCENT` 20 (vision: 20% of buy price), `SHARED_XP_PERCENT` 100, `UNIT_XP_PERCENT` 100, `PRICE_PERCENT` 100. Keys not listed start at 0 |
| F8 | Dormant carriers | An instance owned by a unit, or by an item it carries, is dormant while `has_unit()` is false; a weapon's instances are dormant unless it is `equipped_weapon_id()`. Dormant: no query contributions, no reactions, counters and charges kept. Army, rune and map-object owners are never dormant (Grave Candle fires). Works inside the sandbox, so a forecast that swaps weapons needs nothing extra |

The sandbox copies the whole session for every branch, with no copy on write yet; its cost is
**unmeasured** until EB9, and copy on write is a follow-up only if EB9 misses the budget.

### Rejected alternatives

- **Effects connect to bus signals with `Signal.connect`.** This is the simplest version of
  "a relic listens for a signal". It fails four requirements: the forecast and AI must run effects
  without side effects; "that hit" operations must act before the amount is committed; reactions
  must queue rather than recurse; and listener order would follow connection order, which is
  implicit and depends on load order. Authors still pick a trigger exactly as before; only the
  plumbing differs.
- **A string-keyed bus** (`publish("unit_died", data)`). It loses typing (gdscript.md §4) and makes
  renames silent.
- **One global combat bus (autoload).** It can't serve two concurrent parallel maps.
- **Priority-ordered modifiers.** Unneeded: the design makes stage math order-free.
- **`MultiplayerSynchronizer` state sync.** No ordering guarantees for playback, and the state is
  graph-shaped (old doc 14 reached the same conclusion).
- **A relic subclass per trigger.** The combinations multiply; composition covers them as data.

## Save Impact

Per save-system.md and effects-system.md:

| Data | Block | Section key (proposed) | Per player | Version |
|------|-------|------------------------|------------|---------|
| Campaign-lane counters and charges of items and unit traits | `CAMPAIGN` | inside `roster` (the owner's data; the archive copies this section) | Yes | Set by the units plan |
| Owned heirlooms and curses, with their campaign-lane counters | `CAMPAIGN` | `heirlooms` | Yes | 1 |
| Rune slots | `CAMPAIGN` | `runes` | Yes | 1 |
| Instance id counter | `CAMPAIGN` (and copied into every `COMBAT` checkpoint) | `instance_ids` | No | 1 |
| Effect state during a battle (combat-lane counters, charges, timed modifiers, in-battle campaign-lane values) | `COMBAT` | `effects` (one entry per `session_id`, plus an `encounter` entry for cross-map instances) | Per session | 1 |

- This plan adds **capture/restore helpers** on `EffectInstance` and the engine (plain JSON:
  definition ids as strings, counters as integers converted in `restore()`). It registers no
  section itself: each owning plan registers its section, using these helpers.
- The `COMBAT` `effects` section assumes one battle state per map, the open save change. Until the
  multiplayer-combat plan lands it, solo is session 0.
- Facts, the fact log and the bus are **not saved**. A resumed battle rebuilds from state; the
  presentation starts fresh.

## Work Breakdown

Each step is independently committable and verified headlessly before the next. Paths are under
`bandit-bash/`.

**Dependencies.** The buses (EB1) stand alone: they need only the fact classes, so presentation and
observer work in downstream plans can start once EB1 lands. The effect engine (EB2–EB4) depends on
the fact classes, never on the buses. Sessions (EB6) join the two.

```
EB1 facts + buses ──┬──────────────────────────────► downstream presentation / observers
                    └─► EB2 values ─► EB3 blocks ─► EB4 engine ─► EB5 catalog
                                                         └──────► EB6 sessions ─► EB7 wire/save
```

| Step | Files | Description | Risk | Verification |
|------|-------|-------------|------|--------------|
| EB1 Facts and buses | `scripts/bus/combat_fact.gd`, `campaign_fact.gd`, `combat_bus.gd`, `campaign_bus.gd`, `bus_channel.gd`, `bus_tracer.gd`; `scripts/autoload/net_log.gd` (append `COMBAT`, `EFFECTS`, `CAMPAIGN`, `AI` categories; widen class doc) | Fact classes with kinds, wire round-trip and a log-line formatter; buses with domain channels; tracer that records fact order | 🟢 | `tests/effects/run_all.gd`: wire round-trip; tracer order; fact log lines match the documented shape |
| EB2 Values and modifiers | `scripts/effects/modifier.gd`, `value_breakdown.gd`, `combat_value.gd`, `campaign_value.gd`, `damage_stage.gd`, `stat_sheet.gd` (static part only; invalidation arrives in EB4) | The five modifier modes in fixed order (replace base, add / multiply, floor / cap, fixed, then rule clamps) and permission math, all with sources; exact values with each key's rounding rule (`get_value` / `get_int`); the combat core's seeded keys and permissions ([Amendments](#amendments-from-p02-and-p13)) | 🟢 | Shuffled-source property test (order of sources never changes the total); one test per mode boundary (replace base keeps bonuses; fixed ignores them, floors and caps included; rule clamps still apply after fixed); denial beats grant; override precedence and its warning; highest floor and lowest cap; breakdown text names what a fixed value overrode; `get_value` stays exact (a halved 3 is 1.5) while `get_int` rounds by the key's rule (`HALF_UP` 1.5 → 2, `FLOOR` → 1, `EXACT` untouched); float error at a half doesn't flip the rounding (5 × 1.1 → 6) |
| EB3 Definitions and blocks | `scripts/effects/effect_definition.gd`, `effect_carrier_definition.gd`, `blocks/conditions/*`, `blocks/operations/*`, `blocks/selectors/*`, `blocks/values/*` | The inspector model and `describe()` text generation | 🟡 many new `class_name`s | `--import`, then `--check-only` on every file; `describe()` snapshot per block |
| EB4 Instances and engine | `scripts/effects/effect_instance.gd`, `effect_owner.gd`, `effect_context.gd`, `effect_engine.gd`, `reaction_queue.gd`, `timed_modifier.gd`, `rolls/roll_source.gd` (+ `live_rolls`, `forecast_rolls`, `forced_rolls`, `sampled_rolls`), `sandbox.gd`, `sandbox_state.gd`, `roll_record.gd`, `exchange_outcome.gd` | Registration and indexes, scope, dispatch, inline windows per trigger, inline vs queued, reaction queue (draining at every step boundary) and cap, counters and charges per lane (combat lane fresh per session), timed modifiers with ends, uses and `reach_boundary()`, observers, roll sources (`roll_hit_2rn`, `roll_percent`, `pick_index`; `LiveRolls` over a given `RngStream`; `SampledRolls` from `RngKey.mix()`), the attack context's fields and flags, the single Block-gain path, the sandbox with its `SandboxState` hook and branch summary, the `stats(unit_id)` read API with cached sheets, fact-driven invalidation and verify mode; base stat keys and the `Stat` enum (F3); the `CommandTarget` selector, extra Stance loss and `WhileMatchupCondition` (F4). **Needs P13 R1–R3 and fix-ups F1–F2** | 🟡 | `roll_hit_2rn`'s reported probability equals the exact two-roll count at Hit 0, 1, 50, 99 and 100, and 10⁵ `LiveRolls` draws match it; `LiveRolls` advances only its own stream; `SampledRolls` gives the same draws for the same `seq` and candidate; each timed-modifier end expires at its boundary (Iron Wall at its own Phase End, War Horn at the next one); a "next attack" use is spent by a counter and by a miss, and an attack already under way when it was added doesn't spend it; staff, Guard Tonic and Phase Start Block gains all open `BLOCK_GAINED`; a per-map charge spent in one combat is full in the next; flags set in any order give the same hit; golden fact logs for the 15 coverage fixtures; determinism (shuffled registration order gives the same log); sandbox purity (real state, RNG and counters unchanged after any number of forecasts); a forecast with `ForcedRolls` matching a real resolution with the same outcomes gives the same facts; `ExchangeOutcome` kill probability matches hand-computed 2RN odds on a fixture; Momentum's +15 Hit appears in a branch after a miss; the same candidate set evaluated on `WorkerThreadPool` and single-threaded gives identical results; for each invalidating fact kind (equip, delta, gain, loss, timed modifier gained / expired, transfer between sessions) the cached value equals a fresh computation; the whole suite runs with verify mode on; the deepest known chain (Brute → Cleave → Defeated → Grave Candle) resolves; a deliberate loop fixture stops at depth 16; a "worst legitimate step" fixture (maximum bonus turns, AtkX 2, Cleave splash, both armies' heirlooms) stays under 256; a keg chain is never cut |
| EB5 Catalog and content tests | `scripts/effects/effect_catalog.gd`, `tests/effects/content_test.gd`, `tests/effects/fixtures/*.tres` | Static catalog with typed lookups, loaded via `ResourceLoader.list_directory()` from `res://data/{heirlooms,curses,items/weapons,items/equipment,items/trinkets,items/consumables,runes,units,enemies,effects}`; content rules | 🟡 new registry | The content test passes on fixtures and fails on deliberately bad fixtures (id ≠ file name, duplicate id, dangling reference); every catalog definition hashes the same before and after the whole suite |
| EB6 Sessions, encounter and bridge | `scripts/sessions/combat_session.gd`, `combat_encounter.gd`, `campaign_session.gd`, `command.gd`, `fact_playback.gd`, `presentation_request.gd`, `instance_id_allocator.gd` | The allocator with per-kind presets and `describe(id)`; INFO / DEBUG logging per [Logging and debugging](#logging-and-debugging); | Session skeletons with a minimal fake state for tests; the command queue (arrival stamps, atomic resolution, resolve-time validation, `command_rejected`, ownership check, `based_on_seq` stale-forecast check); fact batches with `seq`; the in-memory catch-up log; playback with speed and pause hooks; the encounter (cross-map instances, forwarding, delivery, routing, transfers); campaign→combat bridge with lane write-back; stream injection (the encounter draws the setup once; each session gets its `COMBAT_ROLLS` stream and `MAP_LOOT` lookup) | 🔴 sets the contracts every plan uses | Headless scenarios: two seats' sessions roll independently, and neither holds the registry; `ENCOUNTER_SETUP` is drawn only inside the encounter's setup call (P13 R6); start a battle, run fixture commands, end, with campaign lanes written back and combat lanes dropped; a unit moved between sessions keeps its counters; a cross-map fixture ("Every 10th Hit dealt by Any Ally Unit") counts hits on two sessions and delivers its operation to the right one; a positional condition never matches across sessions; two seats racing for one chest: the first resolves, the second is rejected at no cost; a stale attack is rejected, a stale move that is still legal is accepted; a command for another seat's unit is rejected |
| EB7 Serialization, rejoin and repro | Changes in EB1, EB4 and EB6 files | `to_wire` / `from_wire`; capture/restore helpers; `snapshot()` / `load_snapshot()` on sessions and the encounter built from them; idempotent mirror apply by `seq`; debug state hash per batch; `debug_dump()` repro files carrying the run seed, build version and stream states | 🟡 | A dump records its run seed and stream states; round-trip tests, including the float-to-int conversion rule; a mirror rebuilt from snapshot + catch-up facts equals the host's state; a resent batch doesn't double-apply; ids minted after a resume match the original run; a dump replayed headlessly reproduces the same facts; a deliberately diverged mirror logs a hash mismatch |
| EB8 Docs | `docs/design/event-bus.md` (new); `effect-triggers.md` (Campaign section, Block gained, inline-window column, per-map phases); `heirlooms.md` (Gilded Purse and Scrapper's Tongs wording); `multiplayer-combat-options.md` (questions 10–11); `.claude/rules/gdscript.md` §8.5 (point its link at `docs/design/event-bus.md`) | The living reference and the design-doc updates. The §8.5 rule subsection itself was added during planning (question 16) | 🟢 | Review |
| EB9 Benchmark | `tests/bench/forecast_bench.tscn` + script | Seeded AI-like workload on a 6-vs-5 fixture map: sandbox creation cost, value queries with and without cached stat sheets, one player forecast, and a full `ExchangeOutcome` at exact enumeration for exchanges of 2, 4 and 8 attacks, each single-threaded and on `WorkerThreadPool` | 🟢 | Median and p95 printed; these numbers set the AI plan's branch budget. Until it runs, every performance statement is **unmeasured** |

## Breaking Changes

No breaking changes. Everything is additive; no existing public member, signal, autoload, save key
or `project.godot` entry changes. `NetLog.Category` gains four values appended after the existing
ones, so existing values and call sites are unchanged. The new public classes are listed per step
above for approval.

## Verification

- Every changed `.gd`: `godot --headless --path bandit-bash --check-only --script res://<path>.gd`,
  after `--import` whenever a `class_name` is added.
- Headless suite: `godot --headless --path bandit-bash --script res://tests/effects/run_all.gd`
  (no autoloads, no Steam, the same pattern as `tests/save/run_all.gd`). It covers modifier math
  order-independence, golden fact logs for each coverage fixture, determinism under shuffled
  registration, forecast purity, the reaction cap, lane reset and write-back, wire and save
  round-trips, and content rules. It also covers the multiplayer mechanics headlessly, with several
  seats in one process: mirrors rebuilt from facts match the host, concurrent commands, stale
  forecasts, ownership, and rejoin from snapshot plus catch-up.
- Benchmark EB9 for forecast cost (the ruthless AI and intents call it heavily). Report the median
  and p95 numbers. Without them, performance is unmeasured.
- Multiplayer replay is untested live until the multiplayer-combat plan's two-machine run.

## Rollback

All code is new and lives under `scripts/bus/`, `scripts/effects/`, `scripts/sessions/` and
`tests/effects/`, with no autoload and no `project.godot` change. Revert the step's commit. The
design-doc edits in EB8 revert independently.
