# Effect Triggers

The catalog of everything an effect can react to, and the words effect text uses to say so. It is
the vocabulary for the [effects system](effects-system.md). Keep it small: add a trigger only when
a real effect needs it.

**Status:** built. The triggers are `EffectTerms.Trigger` and their text is generated from it;
how the engine dispatches them is in [event-bus.md](event-bus.md).

## Reading effect text

Every triggered effect reads the same way:

```
<trigger head> [this combat | this campaign]: <operation>
```

- With scope This unit, the head is the trigger's name: "**Before Combat**: gain 2 Block."
- With a wider scope, the scope is the trigger's subject: "**When Your Unit is defeated**: give
  your units 4 Block." "**Before Your Unit's combat**, while it is the initiator: …" ("Defeated by
  Your Unit" would read as Your Unit doing the defeating.)
- A phase is a side's, not a unit's: Your Unit's reads "**Phase Start**", Any Ally Unit's
  "**Allied Phase Start**", Any Unit's "**Any Phase Start**".
- With a counter, a unit trigger keeps the counted form `Every Nth <trigger> by <scope>`:
  "Every 7th **Attack made** by **Your Unit** **this campaign**: that attack gains lifesteal."
- Permissions read as what the unit can do, with the target as subject: "a random one of your
  units can't gain Block until the end of the next phase", "Always: can pick locks".
- A rune reads as its cast, with no head, naming who it is cast on in place of "the target"
  (an ally, an enemy, an ally that hasn't acted): "Heal an ally for 10", "Remove 2 Stance from an
  enemy". Timed modifiers that last alike share one duration: "Give an ally +20 Hit and +2 Attack
  on its next attack until Phase End". Only runes read this way; a Pouch item keeps "the target".

The generated text lives in `EffectTerms` (`trigger_head`, `describe_permission`); a rune's in
`RuneDefinition.describe()`.

## Scopes

A scope says whose events count. It names the unit the event happens to: the attacker for Attack
made, the unit hit for Hit taken, and so on.

| Scope | Counts events on | Use for |
|-------|------------------|---------|
| This unit | Only the unit holding the effect | Items, unit traits, statuses. The default, so effect text can leave it out |
| Your Unit | Any unit the effect's owner controls | Heirlooms and effects that reward one player's army |
| Any Ally Unit | Any friendly unit, including co-op partners' units | Team-play effects in co-op |
| Any Unit | Any unit, friendly or enemy | Effects that react to the whole battlefield |

- In solo, Your Unit and Any Ally Unit count the same units, unless allied units the player doesn't
  control are added later.
- Heirlooms belong to an army, not a unit, so they use Your Unit or wider. They never use This unit.

## Counter lanes

An effect with a counter states its lane in its text. One effect can have one counter in each lane,
and they count separately.

| Lane | Text | Resets | Saved in |
|------|------|--------|----------|
| Combat | "this combat" | At the start of every battle | The `COMBAT` block |
| Campaign | "this campaign" | At the start of a run only | The owner's per-player `CAMPAIGN` section |

The counter is shown on the effect's card, for example "Bulwark 7/10 this combat".

## Triggers

**Turn phases.** These are defined in [game-vision.md](game-vision.md#combat). In co-op, phases are
**per map**: all units on a map, reinforcements included, share its phases, and a map's player
phase ends when every player with units on it has ended their turn (event bus plan, question 11).

| Trigger | Fires when |
|---------|------------|
| Phase Start | A side's phase begins, after that side's Block and Stance refresh |
| Unit Turn Start | For each unit of a side, at its side's Phase Start, after Phase Start effects and before the side gets control |
| Before Combat | A combat exchange begins, before the first attack |
| After Combat | A combat exchange resolves, for each participant that survives |
| Unit Turn End | For each unit of a side, at its side's Phase End, after the Phase End trigger; every unit gets it, acting or not |
| Phase End | A side's phase ends |

No phase trigger has an inline window: each fires at a step boundary, after the step it ends.

**Combat events.** Each event has a pair: one side does it, the other side has it done to them.
A trigger with an **inline window** fires before its amount is committed, so an effect on it can
change *that* action ("that hit takes half damage", "that attack gains lifesteal"). On any other
trigger an effect can only start a new action ("gain 2 Block"), which resolves after the current
step. The content test fails an inline operation on a trigger without a window.

| Trigger | Fires when | Inline window | Notes |
|---------|------------|---------------|-------|
| Attack made | A unit makes an attack, hit or miss | Yes: that attack's Hit, damage stages and flags (lifesteal) | Each attack counts, so AtkX 2 is two attacks |
| Hit dealt / Hit taken | The attack's hit roll succeeds | Yes: every damage stage of that hit, through Stance loss | Counts even if the damage is fully countered (0) or absorbed by Block |
| Missed / Dodged | The attack's hit roll fails | No | Missed is the attacker; Dodged is the defender |
| Damage dealt / Damage taken | Real damage gets through, to Block or HP | No | The same test that costs the defender Stance |
| Crit dealt / Crit taken | A hit is a critical hit | Yes: that hit, from the Critical stage on | Only possible against an Exposed unit |
| Exposed | A unit's Stance reaches 0 | No | Fires once each time it happens |
| Defeated an enemy / Defeated | A unit defeats an enemy / a unit is defeated | No | |
| Healed an ally / Healed | A unit restores an ally's HP / a unit regains HP | Yes: that heal's amount | Includes overhealing; see effects-system.md |
| Used a staff on an ally | A unit uses any staff (heal or Block) on an ally | No | |
| Darkness damage taken | A unit takes damage from [the darkness](the-darkness.md) in the darkness phase at the end of the turn | Yes: that damage | Not an attack: it never fires Hit taken or Damage taken |
| Object used | A unit uses a [map object](map-objects.md) (lights or douses, pulls, searches, passes through) | No | |
| Shoved a unit / Shoved | A unit shoves another / a unit is shoved | No | Shove is described in game-vision.md |
| Block gained | A unit gains Block from any source: an effect, a staff, a Guard Tonic, a Phase Start trait | Yes: that gain's amount (rounded half up, never below 0) | The Phase Start refresh to 0 is not a gain, and a loss (a negative gain, such as Haunted's) never fires it. A unit that can't gain Block (Haunted's ban) gains nothing and fires nothing |
| Moved after acting | A unit makes its own move after acting, which a trait allows (Skirmisher) | No | Only its own walk: being shoved, Recalled or swapped doesn't count. Fires once the move is made, so Skirmisher+'s "gains 2 Block if it moves" lasts until its side's next Block refresh |

Always-on effects have no trigger. They apply whenever their owner is involved, e.g. "Take 5 less
damage".

## Campaign

Campaign triggers belong to heirlooms and items on the campaign layer, per player. All three are
reaction-only: none has an inline window.

| Trigger | Fires when |
|---------|------------|
| Gained | This heirloom or item is acquired |
| Combat ended | A combat ends, for each player, won or lost |
| Leveled up | A unit's level-up is committed ("When Your Unit levels up") |

Node entered, Item scrapped and Shop opened are left out until content needs them.

**As built:** the three triggers exist and have their text, but nothing dispatches campaign facts
to effects yet, and no content uses them ([event-bus.md](event-bus.md#triggers)).

**Steady numbers are values, not triggers.** Economy, XP and army-size effects modify a
**campaign value** that the game reads when it needs the number:

| Campaign value | Starts at | Content |
|----------------|-----------|---------|
| Combat gold | 0 | Bounty Ledger (+8) |
| Grade bonus | 25 points | Gilded Purse (+25 points) |
| Shared XP, a unit's own XP | 100% | Veteran's Medal (+20%), Family Ring (+25%, holder only) |
| Scrap value | 20 points of the buy price | Scrapper's Tongs (+20 points) |
| Armory stock, Guildhall recruits, shop prices, free rerolls | 0, 0, 100%, 0 | Merchant's Ledger, Guild Charter, Membership Seal, Tinker's Token |
| Max army size (never past 8) | 0 | Muster Roll, Abundance, the Company Charter event |
| Extra enemies | 0 | Hunted |
| Healing received (both layers) | 100% | Cursed Blood, Cleansed Goblet |
| Level-up gains: guaranteed, random, fewest stats raised; whether a stat may grow | 0, 0, 0; allowed | Training Weights, Resonant Ore, Royal Crest |
| Enemy intents hidden (a permission) | Shown | Clouded Sight |
| Darkness arrival offset, Pouch item weight (read at battle start) | 0 | Short Wick, Heavy Pack |

Modifiers **add** to the starting value, so copies stack: two Gilded Purses make each grade bonus
+75%. Effect text says "instead of" only for a real override, a value that replaces the base
("Scrapping pays 10% instead of 20%"); the engine keeps that mode for future trade-off heirlooms.

## Conditions

Kept to three kinds for now:

| Condition | Text | Example |
|-----------|------|---------|
| Counter | "Every Nth" or "First" plus a lane | "Every 10th Hit taken this combat"; "First Hit dealt this combat" fires once per lane |
| Chance | "N% chance" | "25% chance: apply Bleed" |
| While | "While <state>" or "While <comparison>" | "While Exposed", "While below half HP", "While on Gloom or deeper" (darkness layer), "While this unit's AS is higher than its opponent's" |

**Comparisons.** A While condition can compare one of this unit's values with its **opponent's**.
The opponent is the other unit in the current combat exchange, so comparisons only apply from
Before Combat to After Combat.

- **Values that can be compared:** any stat (HP, Might, Speed, Defense, Resistance, Movement,
  Constitution) and any combat value (Attack Speed, current HP, HP %, Block, Stance, Parry).
- **Comparisons are strict:** "higher than" and "lower than" fail on a tie, so an evenly matched
  opponent never triggers them.
- **Checked live:** the condition is re-checked at each attack, so it switches off the moment the
  comparison stops being true (e.g. the opponent's HP % drops below this unit's).
- **The forecast shows the result:** whether each comparison holds is displayed, so the player
  never has to work it out.

**Position and movement.** While conditions and amounts can also use the map:

| Term | Means | Example |
|------|-------|---------|
| Adjacent | Units on the four orthogonally neighboring tiles | "Gain 1 Block per adjacent ally", "adjacent allies gain 1 Block" |
| At maximum range | The opponent is at the far end of this unit's weapon range | "Hit dealt while at maximum range: +2 damage" |
| Moved N+ tiles this turn | This unit moved at least N tiles during its current Unit Turn | "While this unit moved 4+ tiles this turn: +2 damage" |
| Hasn't moved this turn | This unit has moved 0 tiles this turn | "While it hasn't moved this turn: +10 Hit" |
| Within N tiles | Units N or fewer tiles away on the grid (tiles up plus tiles across), ignoring walls and terrain; adjacent is within 1 | "Allies within 2 tiles gain +2 damage", "units within 2 tiles take 3 damage" |
| No ally closer to an enemy | No ally of this unit has a smaller tile distance (tiles up plus tiles across, ignoring terrain) to its nearest enemy than this unit has to its own; a tie still counts | "Phase Start, while no ally is closer to an enemy than this unit: gain 3 Block" |

**Shove distance.** How many tiles this unit's shoves push (1 by default). Effects change it like any
other value: "Always: Shove distance +1". A longer shove still moves tile by tile and stops early
at anything in the way, bumping a unit it runs into (see Shove in
[game-vision.md](game-vision.md#combat)).

**Exchange role.** "While it is the defender" / "while it is the initiator" test this unit's role in
the current combat exchange, e.g. "Before Combat, while it is the defender: gain 3 Block".

**Friend or foe.** Effect text that says "every unit … friend or foe" uses the Any Unit scope: it
applies to every unit in the area, whichever side it is on. Enemy traits use this on purpose so
players can turn them around.

**Splash damage** is flat damage dealt to every unit in an area. It is not an attack: no hit roll,
no Mitigation, no crit, and it never costs Stance or fires Hit taken. Block absorbs it, and it
fires Damage taken.

**Operations beyond stage modifiers** used by MVP traits: gain Block, gain Stance, gain Hit or crit
chance, remove extra Stance, a temporary damage bonus "until Phase End", and "may use its remaining
movement" (move again after acting). Heirlooms add **lifesteal**: "that attack heals the attacker
for the damage it deals to HP" (Block absorbed doesn't count).
