# Keywords

How effect text marks its game terms, colours them by meaning and explains them in a tooltip, in
the manner of Slay the Spire's card text: a keyword ("Block") is coloured, and a box beside the
card names it in that colour, then says what it does in one plain sentence.

**Status:** built (TX3, November 22, 2026). The colour mapping, the text tints and every
explanation are drafts for the user to confirm (P01 questions 72 onward); the **Your wording**
column below is for the user's pass.

## Markup

- **Tags in the text.** The generator (`EffectTerms`, every block's `describe`) and
  `EffectDefinition.written_text` mark each keyword as `[kw=<id>]Word[/kw]`. The id is stable
  (`EffectTerms.KEYWORD_IDS`); the shown word may change ("heals", a translation) and stays
  marked.
- **Marked and plain text.** `EffectDefinition.describe_marked()` and
  `EffectCarrierDefinition.describe_marked()` give the tagged text for an `EffectText`;
  `describe()` gives the same words with the tags removed (`EffectTerms.plain_text`), for logs,
  plain labels and tests. `EffectTerms.describe_modifier()` is plain too (the battle log reads
  it); the generator uses `describe_modifier_marked()`.
- **The content test** (`tests/content/keyword_cases.gd`) fails a catalog line whose tags are
  unbalanced or name an unknown id, a keyword left unmarked, and a plain line that isn't its
  marked line's words. "damage", "heal" (and heals, healed, healing) and "darkness" count in
  any case; every other keyword in its own spelling, so the plain words attack, hit, crit and
  range stay unmarked.

## The glossary

`data/keywords/keyword_glossary.tres` (`KeywordGlossary`) holds one `KeywordEntry` per id: its
id, the name its tooltip shows, its colour group and its explanation. The content test fails a
missing, incomplete or extra entry.

## Colours

A keyword takes the colour the UI already uses for its idea, through its entry's **colour
group**, never a colour per scene (user, November 21, 2026). Each group is a colour of the
`EffectText` theme type, and each is a token readable as text on panels (ui-style.md, Colour
tokens): `danger` and `darkness` fail as text on `panel` (2.79:1 and 2.06:1), and `block` and
`heal` fail on `panel_raised` (3.78:1 and 3.71:1), so those groups use lighter tints of the
same hues. `tests/ui/theme/` measures every group on both.

| Group | Colour | On `panel` | On `panel_raised` |
|-------|--------|-----------|-------------------|
| Danger | `danger_text` `#f4978e` | 6.12:1 | 4.62:1 |
| Block | `block_text` `#89b4df` | 6.12:1 | 4.62:1 |
| Heal | `heal_text` `#7fbe89` | 6.10:1 | 4.61:1 |
| Accent | `accent` `#d9b45a` | 6.73:1 | 5.08:1 |
| Darkness | `darkness_text` `#bba5ea` | 6.14:1 | 4.63:1 |

Where the UI already gives a keyword its own colour, that colour wins over the starting mapping:
**Stance** is accent (the Stance pips are accent), **Movement** is block (the move overlay) and
**Range** is danger (the attack and enemy range overlays). Colour is never the only signal: the
word itself names the term, and its tooltip explains it.

## Tooltips

- **`EffectText`** (`ui/common/text/effect_text.tscn`), a RichTextLabel, draws each tag in its
  group's colour and the rest plain. Hovering a keyword shows its `KeywordTooltip`; leaving it
  hides it.
- **`KeywordTooltip`** (`ui/common/text/keyword_tooltip.tscn`): the name in the keyword's
  colour (Alegreya), the explanation below; a style guide tooltip, at most 320 units wide.
  Several stack in a column beside the card, kept inside the screen: right of the card, else
  left of it.
- **Keyboard and controller.** Key or pad focus on the card holding the text (its nearest
  focusable ancestor) shows one tooltip per distinct keyword of every `EffectText` on that card,
  in one column on the card's first text; focus leaving hides them. While it shows, hovering a
  keyword in any text on the card adds no second column. Mouse focus shows none. No input action
  is added.
- **Unit detail** (BF10): up and down step focus from Close through the rows that show text (each
  gear row with text under its name, an enemy's signature move, each trait, heirloom and curse
  row), the body following, so each focused row is a card showing its keywords; past the last row
  and above Close they scroll the body, and accept on a row closes the detail as Close does. The
  focused row draws the theme's focus look. The mouse never focuses a row.
- **The rune menu** (BF10), like the shop panels (BF9): while one of its rows holds key or pad
  focus, the focused rune's keywords show as one column beside the menu.
- **The heirloom bar's tooltip** shows its keywords' tooltips whenever it opens, by hover or
  focus: the mouse can't reach it (pointing away hides it).
- **Surfaces:** the item offer card, the heirloom offer card, the Armory and Guildhall stock
  cards (an heirloom's or rune's details and an item's effect lines), the purchase and Guildhall
  panels' details, unit detail's trait rows, gear rows and an enemy's signature move, the battle's
  rune menu, and the heirloom bar's tooltip. The event screen adopts `EffectText` in CO12; the
  battle log and the rune bar's text stay plain.

## Glossary entries

| Keyword | Id | Colour | Draft explanation | Your wording |
|---------|----|--------|-------------------|--------------|
| Block | `block` | Block | Absorbs damage before HP. Clears when its side's phase starts. | |
| Stance | `stance` | Accent | Each hit that deals damage removes 1; at 0 the unit is Exposed. Refills at Phase Start. | |
| Exposed | `exposed` | Danger | Has no Stance left, so it can be crit and shoved. | |
| Mitigation | `mitigation` | Block | Subtracted from each hit's damage: DEF against Physical, RES against Magic. | |
| Phase Start | `phase_start` | Accent | A side's turn begins: its Block clears and its Stance refills, then effects apply. | |
| Phase End | `phase_end` | Accent | A side's turn ends. Effects that last until Phase End stop. | |
| Attack | `attack` | Danger | A hit's damage before Mitigation: weapon damage plus MGT and bonuses. | |
| Attack Speed | `attack_speed` | Accent | SPD minus any weight over CON. Being 4 or more faster gives extra turns in an exchange. | |
| AtkX | `atk_x` | Danger | How many attacks the unit makes each turn of an exchange. | |
| Parry | `parry` | Block | Removes attacks from each enemy turn of an exchange, but never the last one. | |
| Hit | `hit` | Accent | The chance an attack lands, lowered by the target's Avoid. | |
| Avoid | `avoid` | Accent | Lowers the Hit of attacks against this unit. Comes from terrain and effects. | |
| Crit | `crit` | Danger | The chance a hit is critical. Only Exposed units can be crit. | |
| CritX | `crit_x` | Danger | How much a critical hit multiplies its damage. | |
| Movement | `movement` | Block | How many tiles a unit can move each turn. Rough terrain costs more. | |
| Range | `range` | Danger | How many tiles away a weapon can attack or counter. | |
| HP | `hp` | Heal | Health. A unit at 0 HP is defeated. HP carries over between combats. | |
| MGT | `mgt` | Accent | Might: adds to weapon damage and to staff healing and Block. | |
| SPD | `spd` | Accent | Speed: the base of Attack Speed. | |
| DEF | `def` | Block | Reduces Physical damage taken. | |
| RES | `res` | Block | Reduces Magic damage taken. | |
| CON | `con` | Accent | How much weight a unit carries before it loses Attack Speed. | |
| Gold | `gold` | Accent | Earned in combats and events; spent at the Armory and Guildhall. | |
| XP | `xp` | Heal | Earned mostly at the end of each combat. Enough XP levels a unit up. | |
| Pouch | `pouch` | Accent | Holds one consumable, trinket or spare weapon. Using it takes the unit's action. | |
| Armory | `armory` | Accent | A shop for weapons, equipment, Pouch items and heirlooms. | |
| Guildhall | `guildhall` | Accent | A shop for recruits, runes and prefix re-rolls. | |
| Magic | `magic` | Accent | A damage type, reduced by RES. | |
| Physical | `physical` | Accent | A damage type, reduced by DEF. | |
| damage | `damage` | Danger | Lowers Block first, then HP. | |
| heal | `heal` | Heal | Restores HP, up to its maximum. | |
| Darkness | `darkness` | Darkness | Spreads across the map as turns pass. Units in it lose HP each turn; Block doesn't stop it. | |

The drafts come from game-vision.md (Combat, Stats, Run-wide resources, the darkness) and
the-darkness.md. Two points the sources leave open: the darkness's damage values are still to be
tuned in playtesting (game-vision.md), so its sentence names no number; and "Hit" is both the
accuracy value (the keyword) and a successful roll ("a hit", plain), so the tooltip explains the
value.
