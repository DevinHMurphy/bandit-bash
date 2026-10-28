# Effect Triggers

The catalog of everything an effect can react to, and the words effect text uses to say so. It is
the vocabulary for the [effects system](effects-system.md). Keep it small: add a trigger only when
a real effect needs it.

**Status:** designed October 15, 2026; not built yet.

## Reading effect text

Every triggered effect reads the same way:

```
[Every Nth] <trigger> by <scope> [this combat | this campaign]: <operation>
```

- "Every 10th **Hit taken** by **This unit** **this combat**: take half damage from that hit."
- "Every 7th **Attack made** by **Your Unit** **this campaign**: that attack gains lifesteal."
- "**Before Combat**: gain 2 Block." (scope This unit and no counter, so both are left out)

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
| Unit Turn End | For each unit of a side, at its side's Phase End, after the Phase End trigger and before darkness damage; every unit gets it, acting or not |
| Phase End | A side's phase ends |

**Combat events.** Each event has a pair: one side does it, the other side has it done to them.

| Trigger | Fires when | Notes |
|---------|------------|-------|
| Attack made | A unit makes an attack, hit or miss | Each attack counts, so AtkX 2 is two attacks |
| Hit dealt / Hit taken | The attack's hit roll succeeds | Counts even if the damage is fully countered (0) or absorbed by Block |
| Missed / Dodged | The attack's hit roll fails | Missed is the attacker; Dodged is the defender |
| Damage dealt / Damage taken | Real damage gets through, to Block or HP | The same test that costs the defender Stance |
| Crit dealt / Crit taken | A hit is a critical hit | Only possible against an Exposed unit |
| Exposed | A unit's Stance reaches 0 | Fires once each time it happens |
| Defeated an enemy / Defeated | A unit defeats an enemy / a unit is defeated | |
| Healed an ally / Healed | A unit restores an ally's HP / a unit regains HP | Includes overhealing; see effects-system.md |
| Used a staff on an ally | A unit uses any staff (heal or Block) on an ally | |
| Darkness damage taken | A unit takes damage from [the darkness](the-darkness.md) at its side's Phase End | Not an attack: it never fires Hit taken or Damage taken |
| Object used | A unit uses a [map object](map-objects.md) (lights or douses, pulls, searches, passes through) | |
| Shoved a unit / Shoved | A unit shoves another / a unit is shoved | Shove is described in game-vision.md |

Always-on effects have no trigger. They apply whenever their owner is involved, e.g. "Take 5 less
damage".

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
