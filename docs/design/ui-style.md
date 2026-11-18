# UI Style Guide

How Bandit Bash's UI looks: colours, fonts, sizes, panels, focus and icons. Every screen follows
it through one shared theme (P15 UL1); a scene sets no colour, font or size of its own outside the
theme's tokens.

**Status:** decided November 18, 2026 (user; P15 UL0, [ui-lift.md](ui-lift.md)). Placeholder art
stays until the art pass; this guide sets the frame it fits in.

## Mood

**Torchlight on slate.** Dark blue-grey panels over a darkened scene; warm parchment and gold for
headers and highlights; red only for danger and damage. The darkness has its own violet, so it
never reads as a dim tile. Ornament is rare: the parchment ribbon is kept for big moments (the
victory stages, screen titles).

## Colour tokens

Every colour comes from a token. Names are the theme's.

| Token | Hex | Use |
|-------|-----|-----|
| `bg` | `#14171c` | Screen background, the victory overlay's base (at 85% over the board) |
| `panel` | `#2a3038` | Panels, menus, tooltips |
| `panel_raised` | `#3a434d` | Rows, buttons, hovered rows |
| `border` | `#4a5560` | Panel and row borders |
| `text` | `#e8e2d4` | Body text, names, numbers |
| `text_muted` | `#9aa3ad` | Secondary text, disabled labels, the event log's tiles and times |
| `accent` | `#d9b45a` | Focus, highlights, gold amounts, headers on dark |
| `parchment` | `#d8c9a3` | The ribbon header's fill (its text is `bg`) |
| `danger` | `#c8463c` | Damage, enemy intents, lethal warnings, the danger zone |
| `heal` | `#5fae6b` | Healing, positive changes |
| `block` | `#6fa3d8` | Block, the player side's colour |
| `darkness` | `#6b4fa0` | The darkness's layers, its phase banner and its log lines |

- **Disabled:** a control at 45% opacity, its text `text_muted`. Refused options say why (as UI13
  and UI14 do).
- **Contrast:** `text` and `text_muted` on `panel` and `panel_raised` meet WCAG AA (4.5:1). Colour
  is never the only signal: an icon, word or shape goes with it.

## Fonts

Two fonts, both under the SIL Open Font License, shipped in `bandit-bash/assets/fonts/` with their
licence files:

- **Alegreya** (serif): headers, unit and item names, the ribbon, phase banners.
- **Source Sans 3** (sans): body text, numbers, the HUD, the event log. Its digits are tabular, so
  HP, damage and gold line up in columns.

## Base resolution and sizes

- **Base viewport 1280×720**, `canvas_items` stretch, aspect `expand`. It scales ×1.5 to
  1920×1080 and ×1 on the Steam Deck's 1280×800 (the extra height is spare room).
- **Sizes are in base units** (1 unit = 1 px on the Deck, 1.5 px at 1080p):

  | Role | Font | Base units | At 1080p |
  |------|------|-----------|----------|
  | Screen title, ribbon | Alegreya Bold | 24 | 36 |
  | Header, unit name | Alegreya Bold | 18 | 27 |
  | Body | Source Sans 3 | 16 | 24 |
  | Small labels, the log, tooltips' footers | Source Sans 3 | 14 | 21 |
  | Big numbers (damage, grades) | Source Sans 3 Bold | 28 | 42 |

- **Floor:** no text below 14 base units, so nothing on the Deck is under 14 px.
- **Spacing:** a 4-unit grid; panels pad 12, rows pad 8 vertically and 12 horizontally, gaps
  between rows 4, between groups 16.
- **Targets:** anything clickable is at least 32 units tall.

## Panels, rows and buttons

- **Panel:** `panel` fill, 1-unit `border`, corner radius 4, a soft shadow (`bg` at 50%, 4 units
  down) where it floats over the board.
- **Row** (menus, reward lists, the event log's filters): full width, `panel_raised` fill, an icon on
  the left (24 units), label, and a value or hint on the right.
- **Button:** a row with centred text. The primary button of a screen (Continue, Start) uses an
  `accent` border.
- **Ribbon header:** `parchment` fill with `bg` text in Alegreya; only on screen titles and the
  victory stages.
- **Tooltip:** a panel, at most 320 units wide; name in Alegreya, then body text, then muted
  footer (tier, counter).

## Focus and hover

- **Keyboard and pad focus:** a 2-unit `accent` outline and the row lightened to `panel_raised`.
- **Mouse hover:** the lighter row alone, no outline, so pad focus can always be found.
- Every focusable element shows focus; nothing relies on hover alone (a tooltip opens on focus as
  well as hover).

## Icons

- **Godot_FE's painted icons** (`Godot_FE/resources/sprites/`) wherever one fits.
- **Otherwise one placeholder style:** a flat `accent` symbol on a dark circle (`panel` fill, 1-unit
  `border`), like UI14's rune slots. Every placeholder is listed in rebalance-and-features.md
  RF-008 until the art pass.
- Icons sit on a 24-unit grid (16 in dense rows, 32 in the heirloom bar and reward rows).
- At-rest icons that should stay out of the way (the heirloom bar) sit at 50% opacity and come to
  full on hover, focus or when they fire.

## Motion

Tweens only (no new animation in the MVP). Panels fade and slide in over 150 ms; stage changes
(the victory sequence, phase banners) over 250 ms; everything skippable follows the battle's
playback speed and skip.
