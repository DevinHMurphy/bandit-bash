# GDScript standards: documentation

Detail for [the core rules](../../../.claude/rules/gdscript.md). Section numbers match the citations in code and plans.

## 3. Documentation

### 3.1 Placement rules

- A member's `##` doc **immediately precedes the member, or its annotations if it has any** — no
  blank line and no `#` line in between, or Godot won't attach it.
- The class doc goes after `class_name`/`extends`, before any member doc.
- Regular `#` blocks (orientation blocks, §3.8) go **above** a member's `##` lines, never between
  the `##` lines and the declaration.
- Godot joins consecutive doc lines with a space. Use `[br]` for a line break; a bare `##` line
  separates the brief from the description.
- Godot recognizes three tags: `@tutorial`, `@deprecated` and `@experimental` (no space before the
  colon). `@todo` is a project convention: Godot shows it as plain text in the class description,
  which is accepted because it serves as the file's marker index (§3.5).
- Cross-references: `[ClassName]`, `[member name]`, `[method name]`, `[signal name]`,
  `[constant NAME]`, `[enum Name]`, `[param name]`, `[code]...[/code]`, `[b]...[/b]`, `[br]`. For
  another class's member, qualify it: `[member UnitToken.move_speed]`.
- Underscore-prefixed members are left out of the generated docs unless they have a `##` comment.
- Doc links are **not** updated when their target is renamed; they break. §6.3 requires grepping
  for them on every rename.

### 3.2 `@export` variables

`@export` docs appear as **Inspector tooltips**, so designers read them. Write them for someone
tuning the value with no access to the code.

```gdscript
## How fast the forecast's flash pulses.
##
## [b]Units:[/b] pulses per second.[br]
## [b]0:[/b] a steady highlight with no pulse. Keep equal to [member StancePips.preview_flash_rate].
@export_range(0.0, 10.0, 0.1) var preview_flash_rate: float = 1.5
```

- The doc goes **above the annotation**, not between annotation and `var`.
- Value types always have an explicit type and an explicit default. Object-typed exports (`Node`,
  `Resource` and subclasses) default to `null`; null-check them before use and say in the doc what
  happens when unset.
- State **units** for anything physical (meters, seconds, radians, Hz, kg).
- State what **0 and 1 mean** for any normalized or `_influence`-style value — the values designers
  try first and misread most.
- Cross-reference with `[member other_var]` when two exports must be tuned together.
- Never leave an export undocumented. If you can't describe it, you don't understand it yet — ask.

**Ranges, groups and flags:**

```gdscript
@export_group("Forecast flash")

## Peak colour of the flash; its alpha is the peak opacity.
@export var preview_flash_color: Color = Color(1.0, 1.0, 1.0, 0.8)

## How many pips show before the row collapses to one bar.
##
## [b]0:[/b] always a bar.
@export_range(0, 20, 1) var bar_mode_count: int = 8

@export_group("")  # Closes the group.
```

- Prefer `@export_range` over a bare `float` whenever bounds are known.
- Use `@export_group` / `@export_subgroup` once a script has more than about 8 exports. Close them
  with `@export_group("")` / `@export_subgroup("")`.
- For any flags or mask export, document what **0** means — usually "feature off", which the
  Inspector doesn't show.

### 3.3 Export setters

Three facts drive the pattern below:

- A scene stores only values that differ from the default, so at load the setter **often doesn't run
  at all**.
- When it does run at load, it runs before `_ready()` and before children exist.
- Assigning one element of a `Packed*Array` export doesn't call the setter (4.7).

So the setter guards on readiness, and `_ready()` applies the value once:

```gdscript
## Thickness of the outline.[br]
## [b]Units:[/b] pixels. [b]0:[/b] no outline.
@export_range(0, 4, 1) var outline_width: int = 1:
	set(value):
		outline_width = value
		if not is_node_ready():
			return
		queue_redraw()


func _ready() -> void:
	queue_redraw()
```

To change one element of a packed array export, copy, modify and reassign the whole array:

```gdscript
var points_copy: PackedVector3Array = waypoints
points_copy[index] = new_point
waypoints = points_copy  # Runs the setter.
```

In a `@tool` script, setters also run in the editor; guard editor-only work with
`Engine.is_editor_hint()`.

### 3.4 Other members

```gdscript
## Emitted when a unit is defeated.
## [param unit_id]: The instance id of the unit.
## [param killer_id]: The unit that struck the blow, or -1 for darkness damage.
signal unit_defeated(unit_id: int, killer_id: int)

## The turn input's stages.
enum Stage {
	## Nothing selected; the cursor roams.
	IDLE = 0,
	## A unit is selected and its move tiles show.
	MOVE = 1,
}

## Most strikes one exchange can hold. Higher lengthens the forecast panel.
const MAX_STRIKES: int = 4
```

Function docs: a brief line, then constraints, then `[param name]` lines and a `Returns` line when
the return value isn't obvious from the name.

### 3.5 Code markers

| Marker | Meaning | Gets a TOD ID and class-doc line |
|--------|---------|----------------------------------|
| `TODO` | Planned work | Yes |
| `FIXME` | Known bug | Yes |
| `HACK` | Deliberate workaround; must name what it works around | Yes |
| `NOTE` | Non-obvious constraint | No |
| `ASSUMPTION` | Unconfirmed guess (see `CLAUDE.md` §1) | No; removed once the user confirms |

The inline marker and the class-doc line carry the **same ID**, so each can be found from the other:

```gdscript
# TODO(TOD-004): Replace linear tree search with an id-keyed registry.
# FIXME(TOD-005): A token can register twice on a fast rejoin.
```

```gdscript
## @todo: TOD-004 - Replace linear tree search with an id-keyed registry.
## @todo: TOD-005 FIXME - A token can register twice on a fast rejoin.
```

- IDs are per file. Outside the file, refer to them as `unit_token.gd:TOD-004`.
- A new ID is the highest ID in the file + 1. Never renumber existing IDs.
- When work is done, delete both the inline marker and its class-doc line.
- Report every marker you add or encounter in the summary.

**Urgency (optional),** in brackets after the ID:

- `[HIGH]` — the feature can't be called done without it; a player would notice it missing.
- `[MEDIUM]` — a real gap, but not blocking.
- `[LOW]` — polish; fine to leave indefinitely.

Most markers need no tag.

```gdscript
## @todo: TOD-006 [HIGH] - Add deflection logic, an on-screen pop-up, audio, and VFX for a miss.
```

### 3.6 How much to write

This project values cross-references and rationale. It does **not** want changelogs in source.
**Keep the constraint, drop the chronology.**

**Cut** — git already stores it, and a stale copy reads as authoritative:

- Dated change entries (`2026-08-09: raised 0.3 -> 0.7`). `git log -p` has the change and the date.
- Narration of prior states ("used to be a bare `pass`", "before this existed", "this slice adds").
- Which refactor, slice or roadmap phase a change belonged to. That's the commit message's job.
- Plan and question numbers ("question 34 (1)"). State the rule itself. One `@tutorial` link to the plan or design doc is fine, and markers may name the step that owns them.
- Restating what the next line does.
- The same rationale at several call sites. State it once at the most-read location and link to it.

The file header's `Created:`/`Modified:` lines are the one sanctioned exception.

**Keep:**

- Why the obvious alternative was rejected, stated timelessly rather than as history
- What breaks if someone changes this
- Invariants the code assumes but can't enforce
- Cross-file coupling: what else must change in step, and where
- Units, ranges and edge-case meanings on `@export`s (§3.2)

Write in the **present tense**, describing the code as it is now. If a sentence only makes sense to
someone who saw the previous version, delete it.

**Budget** — over it means you are writing design docs in a source file:

| Scope | Limit |
|-------|-------|
| Member doc | 4 lines |
| Function doc | 8 lines, excluding `[param]` / `Returns` lines |
| Class doc | 12 lines, excluding the `@todo` index |

Longer rationale goes in `docs/design/<topic>.md`, linked with `@tutorial(Title): <path>`.
Orientation blocks (§3.8) are exempt from the budget.

**Prefer a link over a description:** `[member X]` / `[method Y]` is shorter, navigable in the
editor, and a broken link is greppable after a rename, which a prose description isn't.

Before rewriting a long comment for the first time in a session, read the before/after example in
`docs/standards/gdscript-reference.md`.

### 3.7 Applying this to existing files

Older files carry long dated changelogs. **You have standing permission to rewrite comments in
members you are changing — you don't need to ask.**

| What you're doing | What to do with the comments |
|-------------------|------------------------------|
| Rewriting a function or block | Rewrite its docs from scratch to the budget. Don't patch the old text. |
| Small edit inside a member | Bring that member's doc to budget. |
| Reading only, no code change | Leave it alone. |

Salvage before you delete: carry the durable facts (cross-file coupling, rejected alternatives,
invariants, units) into the new doc; drop dates, prior-state narration and roadmap references. If a
piece of rationale is too large for the budget, move it to `docs/design/` rather than dropping it.

Don't reformat comments in code you aren't otherwise changing. Keep comment rewrites in the same
change as the code they accompany.

### 3.8 Orientation blocks

Two `#` block comments are **required where they apply** and **exempt from the budget**:

- a **state machine overview**, in any script that defines a state enum or state variable, placed
  directly above that enum or variable (above its `##` doc, if any);
- an **input map overview**, in any script that reads named input actions, placed directly below
  the class doc.

They use `#`, not `##`, so they don't become the member's doc. They earn the exemption because each
records something not in the file: transition rules spread across handlers, and bindings stored in
`project.godot`. They follow every other §3 rule: present tense, no dates, no prior-state narration.
**A stale block is actively harmful** — it will be trusted. Update it in the same edit that changes a
state, a transition or a binding.

Before writing or restructuring either block, read the worked examples in
`docs/standards/gdscript-reference.md`.

**State machine block must contain:**

- the precondition: when the enum is meaningful at all
- one aligned line per state: what is live, what is frozen, what each input does
- which states give a shared binding a different meaning
- deliberate non-behavior: a binding that is intentionally inert, and what breaks if someone "fixes" it
- which object owns a distinction the enum doesn't capture
- steps that deliberately don't exist ("there is no separate arm step")
- the global transitions that apply across states

**Input map block must contain:**

- **every** action the script reads, even trivial ones — a partial list is read as complete
- action name, binding, and what it does, including mode restrictions
- reused bindings (one key, two actions by mode), marked as deliberate
- combinations, which exist in no single action name
- inputs that are deliberately harmless in some state, so a guard clause isn't mistaken for a
  missing check

Before adding or changing a binding, compare the block with the `[input]` section of
`project.godot`. If they disagree, stop and ask which is correct.
