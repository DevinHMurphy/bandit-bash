# P18 Co-op ready checks: decisions

Answered questions from [the plan](../2026-11-24-coop-ready-checks.md). Each row's outcome is in
the plan's Approach.

### The plan's questions (November 24, 2026)

| # | Question | Options | Recommendation | Answer |
|---|----------|---------|----------------|--------|
| 1 | The starting heirloom with seats finishing at different times | (a) a seat that has picked waits on the screen ("Waiting for Player 2"), and the team goes to the map together; (b) it goes to the map alone (P11 Q61) | **(a)**: the user's ready-check rule; replaces BF14's (a) | **Answered** (user, November 24, 2026): (a) |
| 2 | What a ready check waits for | (a) **both** every seat's Ready press (its choices done) and every machine's load acknowledgement (batch applied, next screen loaded) before input opens; (b) presses only | **(a)**: "complete and loaded correctly in all places" | **Answered** (user, November 24, 2026): (a) |
| 3 | Ready is a toggle a player can take back until everyone is ready | (a) yes; (b) final once pressed | **(a)**: a player who misclicks can go back to shopping | **Answered** (user, November 24, 2026): (a) |
| 4 | Shops and the Camp: when may the team leave? | (a) when every seat has pressed Ready (Done shopping, Done at camp, re-gear and gifts included); (b) as today, any seat's Leave | **(a)** | **Answered** (user, November 24, 2026): (a) |
| 5 | A Ready press with rewards still unclaimed (results, treasure) | (a) a confirm ("Skip your unclaimed rewards?"), then skip and ready; (b) Ready disabled until every reward is taken or skipped by hand | **(a)**, and it fixes BUG-057 | **Answered** (user, November 24, 2026): (a) |
| 6 | The battle's start | (a) the host begins the first Phase Start only once every client's battle has opened (a load gate, reversing P10's rejection); (b) as today, mirrors catch up by seq | **(a)**: the user's "combat" in "every step" | **Answered** (user, November 24, 2026): (a), and use the loading screen placeholders for it: a loading screen with a progress bar showing each player's current loading amount |
| 7 | A seat that never readies (away, not disconnected) | (a) no timer: the team waits; a disconnect falls to today's drop pause and the host's Remove; (b) a host "Continue without" after N seconds | **(a)** for the MVP; revisit at the co-op playtest | **Answered** (user, November 24, 2026): (a) |
| 8 | Whether ready state is saved | (a) not saved: after a resume every seat readies again; (b) saved per seat | **(a)**: it is seconds of state, and a resume reloads every screen anyway | **Answered** (user, November 24, 2026): (a) |
| 9 | Where ready state lives | (a) a host-side gate outside the rules (sessions layer), announced to clients by relay messages; the transition itself stays today's commands, submitted by the host when the gate opens; (b) a `SeatReadyCommand` in the campaign rules, saved and recorded as facts | **(a)**: rules stay pure and unchanged; nothing to save or replay | **Answered** (user, November 24, 2026): (a) |
| 10 | The vision's "no player sits idle for long" pillar (game-vision.md, design pillars) | (a) accept the waits, with a clear "Waiting for <name>" on every one; (b) let a ready seat do something meanwhile (open the heirloom bar, unit detail, the convoy) | **(a) and (b)**: read-only panels stay usable while waiting | **Answered** (user, November 24, 2026): (a) and (b) |

### RC5: the waiting UI (November 24, 2026)

| # | Question | Options | Recommendation | Answer |
|---|----------|---------|----------------|--------|
| 30 | The co-op Ready toggle's look (solo keeps its plain Continue or Leave) | (a) a toggle button reading "Ready", then "Not ready" with the pressed look once Ready, so a second press takes it back; (b) the label names the state ("Not ready", then "Ready ✓"); (c) a "Ready" CheckButton, as the lobby's | **(a)** | **Answered** (user, November 24, 2026): (a) |
| 31 | What a seat that has loaded but isn't Ready shows | (a) "Choosing" on a screen with a choice, "Done" on the loading screen (Loading until loaded, Ready once pressed); (b) always "Choosing", "Done" only for Ready and loaded | **(a)**: all four words used | **Answered** (user, November 24, 2026): (a) |
| 32 | The toggle's glyph hint | (a) while it has key or pad focus it shows the glyph of the key that presses it (ui_accept), from the hint bar's glyph table and device family; no new input action; (b) a dedicated Ready action, shown on each hint bar | **(a)** | **Answered** (user, November 24, 2026): (a) |
| 33 | A co-op Ready press before the gate is wired | (a) every press into Ready calls the screen's existing Continue or Leave handler; a refusal or a "Stay" takes Ready back; (b) only the first press | **(a)**: behaviour stays as today | **Answered** (user, November 24, 2026): (a) |
| 34 | Where TeamReadyStatus shows before the gate feeds it | (a) only on the starting heirloom (a resolved pick is Ready, an open one Choosing); placed but hidden elsewhere; (b) on every screen from today's status data | **(a)**: no other screen knows who has pressed Ready | **Answered** (user, November 24, 2026): (a) |
| 35 | The loading screen before RC3 reports progress | (a) this machine's bar alone, full on arrival (Done), Ready once pressed; teammates appear once the gate's state comes; (b) every seat's bar, full | **(a)** | **Answered** (user, November 24, 2026): (a) |
| 36 | The results overlay's primary button | (a) a Ready toggle only for Rewards' Leave or End run and a lost map's Leave; Grade's and Recap's Continue stay plain buttons; (b) a toggle at every stage | **(a)**: the earlier stages are this seat's own | **Answered** (user, November 24, 2026): (a) |
| 37 | The types of the gate state the UI takes (`_gate_state`'s payload) | (a) ready and loaded seats as `PackedInt32Array`, progress as `Dictionary[int, float]` (0.0 to 1.0), names as `Dictionary[int, String]` keyed by the seats still in the run; (b) RC2's own types, converted by RC4 | **(a)**: RC2 matches them, so RC4 feeds `set_state` unchanged | **Answered** (user, November 24, 2026): (a) |
