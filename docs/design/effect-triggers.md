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

**Turn phases.** These are defined in [game-vision.md](game-vision.md#combat). In co-op, all
players share one player phase, so Phase Start and Phase End fire once for every player's units
together.

| Trigger | Fires when |
|---------|------------|
| Phase Start | A side's phase begins, after that side's Block and Stance refresh |
| Unit Turn Start | A unit begins its action |
| Before Combat | A combat exchange begins, before the first attack |
| After Combat | A combat exchange resolves, for each participant that survives |
| Unit Turn End | A unit finishes its action |
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

Always-on effects have no trigger. They apply whenever their owner is involved, e.g. "Take 5 less
damage".

## Conditions

Kept to three kinds for now:

| Condition | Text | Example |
|-----------|------|---------|
| Counter | "Every Nth" or "First" plus a lane | "Every 10th Hit taken this combat"; "First Hit dealt this combat" fires once per lane |
| Chance | "N% chance" | "25% chance: apply Bleed" |
| While | "While <state>" or "While <comparison>" | "While Exposed", "While below half HP", "While this unit's AS is higher than its opponent's" |

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

**Operations beyond stage modifiers** used by MVP traits: gain Block, gain Hit or crit chance,
remove extra Stance, and "may use its remaining movement" (move again after acting).
