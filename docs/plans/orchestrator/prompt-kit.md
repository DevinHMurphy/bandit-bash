# Orchestrator Prompt Kit

How the orchestrator session writes build prompts, merges their reports and reports status. It is
the orchestrator's working reference, kept so the routine survives a context reset. The lanes and
their rules are in [dependencies.md](dependencies.md#concurrency-lanes); the queue below says what
each lane takes next.

## Every status update

End every update with the **lanes table**: one row per lane (A, B, C, D, E, G, F), with what is
building, what is free and the step that fits it, and what waits and on what (user, November 20,
2026). Then offer or give the prompts that fill the free lanes, at most four builds at once.

## Prompt skeleton

Each prompt goes in a code block, with "Written for: a fresh build agent session in this repo."
outside it, under the heading `## <ID> prompt - Expected Effort (low/medium/high)`.

```
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

- `CampaignFact.Kind` (`scripts/bus/campaign_fact.gd`): ends at 26 (RN7) on November 20, 2026.
  `docs/design/event-bus.md` lists every kind with what records it.
- `SceneRouter.Screen`: ends at `CAMP = 15` (RN7).
- `capture` group numbers in `tools/captures/`: 100 to 700 used; EV3 took 450, RN7 460.

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
7. Mark a prompt issued only when the user says it was sent.

## Queue by lane (November 20, 2026)

| Lane | Next | Then | Gated on |
|------|------|------|----------|
| A Battle UI | RB1, after the M2 exit playtest | EN16 (move preview sweep) | the user's playtest |
| B Campaign and run | RN8 Armory | RN9 Guildhall, RN10 Unknown, RN11 full run, RN12 docs | one at a time |
| C Events | EV1F | EV4 (the 13 events), EV6 docs | EV1F before EV4 |
| D Engine, AI, content | EN13 measure | EN14, EN15; CT12 after the weapon modification design | EN13 first |
| E Network | NT3 campaign wire | NT4–NT8 | NT3 when Lanes B and C aren't editing campaign or event commands |
| G Audio and tooling | — | AU2 after the audio direction (M5) | — |
| F Docs and plans | P11 and P12 plans when wanted | ideation write-ups | — |
