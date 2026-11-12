# P09 decisions: Narrative events and curses

The answered questions of [the plan](../2026-11-12-events-and-curses.md), moved here on November 12, 2026. Numbers are stable.

## Questions

| # | Question | Recommendation | Answer |
|---|----------|----------------|--------|
| 1 | How event outcomes are applied | A small `EventOutcome` block set on the campaign layer, applied by a pure resolver to `RunState`, reading `CampaignGrant` and `ChangeBaseStat` data where they fit | **Answered November 12, 2026 (user):** as recommended. Changes P01's Events contract wording, not its intent. |
| 2 | Can event damage kill a unit? | No: event damage leaves at least 1 HP | **Answered November 12, 2026 (user):** as recommended. |
| 3 | A cursed option whose tier has no curse left that the player doesn't hold | Greyed out with the reason | **Answered November 12, 2026 (user):** not as recommended. Curses may repeat. An option that names a specific curse gives it even if the player already holds it. An option with a tier draws from the whole tier, held curses included. The case never arises, so nothing is greyed out. Copies stack (heirlooms.md). |
| 4 | How random event items roll | Rare weapon or tome: P08's Weapon pick rule. Trinket: Standard odds without the Rare offset. Rune: even | **Answered November 12, 2026 (user):** as recommended. |
| 5 | Small rule readings (a)–(f) | Accept all | **Answered November 12, 2026 (user):** as recommended. (a) Max HP loss lowers current HP only above the new max. (b) A max HP gain raises current HP. (c) Cursed Blood halves event healing. (d) Percent heals round halves up. (e) A revived unit keeps its remaining items; into a full army it works like recruiting past the max. (f) A surprise combat pays a Standard combat's full rewards. |
| 6 | Every event seen this run | The seen events become available again, as maps do | **Answered November 12, 2026 (user):** as recommended. |
