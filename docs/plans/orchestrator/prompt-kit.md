# Orchestrator Prompt Kit

How the orchestrator session writes build prompts, merges their reports and reports status. It is
the orchestrator's working reference, kept so the routine survives a context reset. The lanes and
their rules are in [dependencies.md](dependencies.md#concurrency-lanes); the queue below says what
each lane takes next.

## Every status update

End every update with the **lanes table**: one row per lane (A, B, C, D, E, G, F) and three
columns (user, November 20, 2026):

- **Now:** what is building, or "free" / "waiting" (and on what).
- **Queue:** the steps after it, in order, each with its gate in brackets (`EN16 [EN14]`),
  taken from the queue below.
- **Ready to send:** the step that can go out now, or "—".

Then offer or give the prompts that fill the free lanes, at most four builds at once.

Before the table, an **Open questions** block carries forward every question still waiting on
the user, old and new, each with its source and a recommendation, so one "yes to all" clears
them (user, November 22, 2026). Find them by searching `decisions/` for rows not yet Answered
(`Open`, `Proposed`, `Draft; confirm`, `built as (a)`), rebalance-and-features.md for Open items,
and the chat for anything asked there (a prompt's send, the user's own tasks).

## Prompt skeleton

Each prompt goes in a code block, with "Written for: a fresh build agent session in this repo."
outside it, under the heading `## <ID> prompt - Expected Effort (low/medium/high)`. Its first line
is `<ID>: <scope>` (for example `EN14: Preview diff and cache`), so the session tab is named
after the step (user, November 20, 2026). Paste-ready notes to a running agent start the same
way (`EV4 note: ...`).

```
<ID>: <scope in a few words>

You are building <plan> <ID>, <what>, for Bandit Bash (Godot 4.7.1).

SETUP
git worktree add ../Bandit_Bash-<ID> -b feature/<ID> dev
Work only in that worktree. Read CLAUDE.md and .claude/rules/gdscript.md first and follow them.

LANE (up to four builds run at once; docs/plans/orchestrator/dependencies.md#concurrency-lanes)
- You are Lane <X> (<name>). You own: <folders>.
- Shared, append only: <project.godot, save-system.md rows, enums others append to>.
- Don't touch: <each running build's folders, named by step>.
- Don't edit the orchestrator records, the bug tracker, rebalance-and-features.md or ui-lift.md.
  Put proposed entries in your report.
- Your decision rows are <plan> questions <N> onward, in docs/plans/decisions/<file>.
- New case files declare const SUITE: String = "<suite as run_tests.sh prints it>" and are never
  added to a run_all.gd; iterate with run_tests.sh --quick, but the final run is a full one.
- (UI steps) Screenshots: add your shots as a new
  bandit-bash/tools/captures/<number>_<name>.gd that extends
  "res://tools/captures/capture_group.gd" and overrides run() -> bool (use capture(), goto(),
  frames(), note()). Pick an unused number that runs it after the group whose state it needs,
  and name that group in its class doc. Don't edit capture_screens.gd or another lane's group.

READ FIRST
- The plan's row and its decisions; the vision and design sections; the code it builds on;
  Godot_FE/ files (read-only, behaviour not code).

BUILD
1. ...

RULES
- (UI steps) Every element is its own .tscn with documented @exports. Keyboard, mouse and
  controller from the start, with glyph hints. No theme overrides; the tests/ui/theme scene scan
  must pass.
- Save, network or snapshot: say what is allowed; anything else, STOP and report.
- Ask before inferring (CLAUDE.md §1). Batch questions, each with a recommendation.

TESTS AND CHECKS
- Cases for: ...
- Captures (UI): at 1280x720, 1920x1080 and 1280x800, with 0 layout issues.
- Before reporting, merge dev into your branch and fix any conflicts. Then do one full run:
  JOBS=8 SUITE_TIMEOUT=450 sh bandit-bash/tools/run_tests.sh   (no --open). Give the report path.

REPORT
- Summary per CLAUDE.md §5: files changed, the port summary, assumptions, markers, verification
  lines, the report path, the captures folder, save impact, Breaking Changes (appended enums as
  network-contract rows), and proposed record entries.
- Commit on feature/<ID>. Don't merge or push.
```

**Effort labels:** low (one fix or a small data step), medium (one system, a few files), high (a
screen or system with many parts).

## Shared enums that several lanes append to

When two branches append, the second to merge renumbers its own. Check the last value on `dev`
before writing a prompt and name it in the LANE block.

- `CampaignFact.Kind` (`scripts/bus/campaign_fact.gd`): ends at 32 (RN10) on November 20, 2026;
  `CampaignFact.flags` defines `FLAG_BOUGHT = 1` (RN8).
  `docs/design/event-bus.md` lists every kind with what records it.
- `SceneRouter.Screen`: ends at `GUILDHALL = 17` (RN9).
- `FactCueMap.Shape`: ends at `GUILDHALL_NODE = 9` (RN9).
- `capture` group numbers in `tools/captures/`: 100 to 700 used; EV3 took 450, RN7 460, RN8 470, RN9 480, EV1G 455, UL9 405, UL10 475, CO10 485 (needs 480), TX3 420, BF8 487 (needs 485), BF9 488 (needs 487); CO12 458 (needs 455), BF10 335; EV7 told 459.

## Reviewing a report

- Check the report against the prompt: scope, lanes, save and network changes, markers.
- Recommendations that need the user go in one batch, each with the recommended answer, so one
  "yes" accepts them; give a paste-ready reply for the agent.
- A clean report is merged straight away. Proposed record entries are filed by the orchestrator.

## Merging

1. The main checkout must be clean apart from the user's `bandit-bash/ui/screens/boot.tscn`,
   `.vscode/`, `.claude/settings.json` and `assests/`. Editor resaves of `.tres` files (same lines,
   new order or `uid`s) are checked with `diff <(git show HEAD:f | sort) <(sort f)` and committed
   on their own; real user edits are asked about, never swept into a merge commit.
2. `git merge --no-ff --no-commit feature/<ID>`; resolve conflicts (keep both sides' additions;
   for marker comments keep the confirmed removals).
3. Full run, foreground, 600000 ms timeout:
   `export TMPDIR="C:/Users/demur/AppData/Local/Temp/claude/edbd0acd0014a836/1b27d07f-610b-46d4-a620-8a49246414b0/scratchpad" && SUITE_TIMEOUT=450 sh bandit-bash/tools/run_tests.sh --open > "$TMPDIR/x_run.txt" 2>&1; grep -E "FAIL|HUNG|Report:|ALL PASS" "$TMPDIR/x_run.txt"`
   and the case total: `grep -o -- "--- [0-9]* passed" "$TMPDIR/x_run.txt" | awk '{s+=$2} END{print s}'`.
4. Update the records: the dashboard's test count and plan rows, dependencies.md (gate rows, the
   graph's `class ... done / active / ready / waiting` lines), design-items.md, the bug tracker,
   rebalance-and-features.md, ui-lift.md or the plan's scope doc.
5. `git add docs/` (plus any files resolved by hand), commit with a message ending
   "Co-Authored-By: Claude Opus 5.5 <noreply@anthropic.com>".
6. `git worktree remove ../Bandit_Bash-<ID>` and `git branch -d feature/<ID>`.
7. Mark a prompt issued only when the user says it was sent. Log it in the records but don't
   commit it: the edit stays unstaged and goes in with the next merge commit (user, November 22,
   2026), so a session that fails before merging leaves no commit to undo.

## Queue by lane (November 21, 2026)

| Lane | Next | Then | Gated on |
|------|------|------|----------|
| A Battle UI | EN17 preview cancel (P05 question 54 (a); issued November 22, 2026) | UL11 weapon-profile marks (RF-039, user November 23, 2026); CO13 the co-op battle screen after NT5, which removes the battle screen's co-op placeholder (P11 question 1 (a)); it builds on `has_sent()`, `senders_of()`, `is_aid_called()`, `is_frozen()`); the HUD rune bar as an EffectText, with the detail rows' 4-unit focus inset; RB1 after the full-run playtest | RB1: the user's full-run playtest (user, November 20 and 22, 2026) |
| B Campaign and run | P11 CO11 the co-op campaign map (issued November 23, 2026; a co-op host can't leave the map until it sends route votes) | CO8 the co-op battle end and rewards (with CO5's visitor reward gaps); CO14 (a forfeit clears swaps and route votes); BUG-034 before CO16 | — |
| C Events | — (free: EV7 merged November 23, 2026) | the event option's expected-heirloom field when events offer a unique heirloom; unit-roster.md's temporary convoy overflow, if wanted | Nothing ready |
| D Engine, AI, content | EN18 plan: the intents refresh on the worker (P05 question 53 (a), plan doc first; BUG-035's release part; CO2 merged November 22, 2026) | CO3 units on a partner's map, with BUG-038; CO4 the darkness on mirrors; CT12 after the weapon modification design | — |
| E Network | NT5 client mirrors (issued November 23, 2026; attaches to `NetRelay`'s `*_received` signals and `command_settled`; switches `battle_controller.gd` to `submit_combat()`; removes the battle screen's co-op placeholder, P11 question 1) | NT6 (builds `NetRelay.seats` from SteamNetwork's admitted members), NT7, NT8; CO15 after NT4 | — |
| G Audio and tooling | TX2 trait wording, part 2, with RF-038 (Foods), after the user's wording pass (in the Wording Pass artifact, https://claude.ai/artifact/V1CKy2XcDTHEtkDdtxYHS5, collection `wording`, read back with ArtifactData; it covers effect-text.md and keywords.md; TX3 merged November 22, 2026) | AU2 after the audio direction (M5); the capture builder tidy-up | TX2 after the user's wording pass (it applies it, and confirms P01 65–68) |
| F Docs and plans | CO20 docs, with BUG-033 (P11 answered November 22, 2026) | P12 plan when wanted; P17 parked (user, November 22, 2026: very low priority) | — |
