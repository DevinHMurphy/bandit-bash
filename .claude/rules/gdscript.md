---
paths:
  - "**/*.gd"
  - "**/*.tscn"
  - "**/*.tres"
  - "bandit-bash/project.godot"
---

# GDScript Standards — Bandit Bash, Godot 4.7.1

Code standards for every GDScript file, scene and resource in this project. The workflow rules (ask
first, effort estimates, verification, definition of done, summary format) are in `CLAUDE.md` and
apply alongside this file. Long worked examples are in `docs/standards/gdscript-reference.md`; this
file says when to read them.

**Scope:** these rules govern code written in `bandit-bash/`, and "`project.godot`" means
`bandit-bash/project.godot`. This file also loads when you read `.gd` files in `Godot_FE/` or
`steam_multiplayer_kit/`. Those folders are read-only references that predate these rules: never
edit them, and never copy their code or style (see `CLAUDE.md`, Repository layout).

**New code follows this guide exactly** — not "in the style of the surrounding file". Where existing
code contradicts it, new code still follows the guide; §3.7 covers bringing old comments along.

---

## 1. Engine version

- This project targets **Godot 4.7.1**. Confirm against `config/features` in `project.godot`.
- Don't rely on memory for version-specific API details. If a signature, annotation or default
  matters to a change, check the 4.7 class reference; if you couldn't verify it, say so in the
  summary.
- Godot 4.7 changes that affect code written here:
  - An override of a method with a typed return inherits that return type and needs an explicit
    `return` on every path.
  - Assigning one element of a `Packed*Array` property no longer calls that property's setter.
  - Keyboard and mouse events report `InputEvent.DEVICE_ID_KEYBOARD` / `InputEvent.DEVICE_ID_MOUSE`
    as their device, not `0`. Never test `event.device == 0`; check the event type or these constants.
  - Under Jolt, the sign of `WorldBoundaryShape3D.plane.d` is read the opposite way from 4.6.
- **3D physics engine:** Jolt is the default only for projects *created* in 4.6 or later. Read
  `physics/3d/physics_engine` in `project.godot` before writing code that depends on engine behavior.

---

## 2. File layout

### 2.1 Order

```
1.  Copyright header (# comments)
2.  @tool, @icon, @abstract, @static_unload (only those needed)
3.  class_name
4.  extends
5.  Class documentation (##)
6.  Input map overview block (§3.8), if the script reads input actions
7.  Signals
8.  Enums (state machine overview block directly above the state enum, §3.8)
9.  Constants, including preloads
10. Static variables
11. @export variables
12. Public variables
13. Private variables (_prefixed)
14. @onready variables
15. Built-in virtual callbacks, in this order: _init, _enter_tree, _ready, _exit_tree,
    _input, _unhandled_input, _process, _physics_process, _notification, then any others
16. Public methods
17. Private methods (_prefixed), including signal handlers (_on_*)
18. Static methods (_static_init first)
19. Inner classes
```

Static methods last is a deliberate project choice; the official style guide puts them before the
virtual callbacks.

### 2.2 File header

Every `.gd` file starts with this header. Add it when you create a file.

```gdscript
# ==============================================================================
# Bandit Bash
# Copyright (c) [Year] Derc Development
# Licensed under the MIT License. See LICENSE.
#
# File:     [file_name].gd
# Author:
# Created:  [Month Day, Year]
# Modified: [Month Day, Year]
# ==============================================================================
```

- Project, holder and license line are fixed exactly as shown. **`Author:` stays blank** — never
  fill it in.
- `[Year]` is the year the file was created. It doesn't change on later edits.
- Dates are always `Month Day, Year`, taken from `date "+%B %-d, %Y"`, never from memory.
- `Created:` for a new file is today. When adding a header to an existing file, take the date git
  first saw it: `git log --diff-filter=A --follow --format=%ad --date=format:"%B %-d, %Y" -- <file> | tail -1`.
  If git has no answer, write `[unknown]`. Never guess.
- `Modified:` is updated to today on every edit to that file, in the same change. Only files you
  actually change.
- `File:` matches the file name exactly.

### 2.3 Class declaration

```gdscript
class_name LiveFish
extends Node3D
## Brief one-line description ending in a period.
##
## Extended description of purpose and responsibilities.[br]
## Reference other classes as [Hook] and members as [member current_state].
##
## @tutorial(Perception Model): docs/design/perception.md
## @experimental: Replication scheme may change before 1.0.
##
## @todo: TOD-001 - Replace RPC broadcast with MultiplayerSynchronizer.
```

`class_name` comes before `extends`. The class doc follows `extends` directly, with no blank line.

---

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
  another class's member, qualify it: `[member Hook.cast_range]`.
- Underscore-prefixed members are left out of the generated docs unless they have a `##` comment.
- Doc links are **not** updated when their target is renamed; they break. §6.3 requires grepping
  for them on every rename.

### 3.2 `@export` variables

`@export` docs appear as **Inspector tooltips**, so designers read them. Write them for someone
tuning the value with no access to the code.

```gdscript
## Brief description of what this controls.
##
## Extended notes: what the units are, what the extremes do, what it interacts with.[br]
## [b]Units:[/b] meters per second.[br]
## [b]Default tuned for:[/b] a reference-size fish at 1.0 swim speed.
@export var swim_speed: float = 1.0
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
@export_group("Perception")

## Sight range. Instant and reliable, but requires line of sight.
##
## Gated by [member obstruction_mask] — a lure behind terrain is not seen this way.[br]
## [b]Units:[/b] meters.
@export_range(0.0, 50.0, 0.1) var detection_radius: float = 6.0

## Probability of noticing a target by smell at point-blank range.
##
## Scales linearly to 0.0 at the edge of [member smell_radius].[br]
## [b]0.0:[/b] smell disabled. [b]1.0:[/b] always detected within range.
@export_range(0.0, 1.0, 0.01) var smell_detection_chance: float = 0.35

## Physics layers that block line of sight.
##
## [b]0 (empty):[/b] no obstruction check — everything in range counts as visible.
@export_flags_3d_physics var obstruction_mask: int = 0

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
## Radius of the detection sphere.[br]
## [b]Units:[/b] meters.
@export_range(0.05, 10.0, 0.01) var radius: float = 1.0:
	set(value):
		radius = value
		if not is_node_ready():
			return
		_rebuild_collider()


func _ready() -> void:
	_rebuild_collider()
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
## Emitted when this fish is successfully hooked.
## [param fish]: The fish that was hooked.
## [param hook]: The hook that caught it.
signal fish_hooked(fish: LiveFish, hook: Hook)

## Behavioral states. Replicated to clients for animation only.
enum State {
	## Pre-spawn setup; transitions to [constant ROAM] on first full tick.
	INIT = 0,
	## Wandering between waypoints.
	ROAM = 1,
}

## Physics frames per full decision tick. Higher spreads load further but increases reaction latency.
const TICK_GROUPS: int = 4
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
# FIXME(TOD-005): Hook can register twice on a fast recast.
```

```gdscript
## @todo: TOD-004 - Replace linear tree search with an id-keyed registry.
## @todo: TOD-005 FIXME - Hook can register twice on a fast recast.
```

- IDs are per file. Outside the file, refer to them as `live_fish.gd:TOD-004`.
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
| Class doc | 25 lines, excluding the `@todo` index |

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

---

## 4. Typing

**Every declaration carries an explicit type.** Godot's inference is literal: it silently locks in
`int` where you meant `float`, and it infers `Node` where you meant your class.

```gdscript
# ❌ Inferred int. A later `speed = 1.5` truncates to 1 with only a warning.
var speed := 1

# ❌ Inferred int. `timer += delta` truncates back to 0 every frame.
var timer := 0

# ❌ Integer division. The annotation doesn't help: this is 0.0, not 0.5.
var half: float = 1 / 2

# ❌ Inferred Node, not LiveFish.
var fish := FISH_SCENE.instantiate()

# ❌ Parse error: min() returns Variant, so there is no type to infer.
var step := min(speed * delta, dist)

# ✅
var speed: float = 1.0
var timer: float = 0.0
var half: float = 1.0 / 2.0
var fish: LiveFish = FISH_SCENE.instantiate()
var step: float = minf(speed * delta, dist)
```

Rules:

- **Write `: Type` on every `var`, `const`, parameter and return**, including `-> void`. Type loop
  variables over untyped collections: `for fish: LiveFish in nearby:`.
- **Avoid `:=`.** Use it only when the static type can't be written by name at that point. When you
  do, add a short comment saying why.
- **A value that can legitimately hold more than one type is declared `: Variant`**, with a comment
  listing the allowed types. `:=` can't express this: it locks the variable to the type of the first
  value, or fails to compile when that value has no static type.
- **Float literals always carry a decimal point:** `1.0`, `0.0`, `15.0` — never `1`, `0`, `15`, even
  as an `@export` default.
- **Division:** at least one operand must be a float when you want a fractional result. An
  annotation on the result doesn't change integer division.
- **Use the typed math functions.** `min`, `max`, `clamp`, `lerp`, `abs`, `sign`, `round`, `floor`
  and `ceil` take and return `Variant`.
  - Floats: `minf`, `maxf`, `clampf`, `lerpf`, `absf`, `signf`, `roundf`, `floorf`, `ceilf`, `snappedf`.
  - Ints: `mini`, `maxi`, `clampi`, `absi`, `signi`, `roundi`, `floori`, `ceili`, `snappedi`.
  - The Variant versions are only for vectors and other non-scalar types.
- **Type collections:** `Array[Node3D]`, `Dictionary[int, LiveFish]`, and `Packed*Array` for bulk
  numerics. Typed collections can't nest (`Array[Array[int]]` is invalid); use an inner class or a
  Packed array as the element.
- **Downcasts:** prefer a typed declaration (`var fish: LiveFish = node`), which errors loudly on a
  mismatch. `node as LiveFish` silently returns `null` on a mismatch; if you use `as`, null-check the
  result on the next line. Cast once into a typed local rather than repeating `as`.
- **Overrides of typed-return methods** need an explicit `return` on every path (4.7).
- **Spacing:** `var name: Type` — one space after the colon, none before.

**Expected project warning settings** (Project Settings → Debug → GDScript): `untyped_declaration`,
`unsafe_property_access`, `unsafe_method_access`, `unsafe_call_argument`, `integer_division` and
`narrowing_conversion` set to **Error**. If `project.godot` doesn't have them, tell the user once;
don't change `project.godot` without asking.

Before finishing, re-read new code for numeric declarations and division and confirm each is
correct. This is the most common source of errors in this project.

---

## 5. Godot 3 syntax is banned

Never write Godot 3 syntax. The common traps:

| Godot 3 (never) | Godot 4 |
|-----------------|---------|
| `onready var`, `export var`, `tool` | `@onready var`, `@export var`, `@tool` |
| `yield(obj, "signal")` | `await obj.signal` |
| `connect("sig", self, "_method")` | `sig.connect(_method)` |
| `emit_signal("sig", a)` | `sig.emit(a)` |
| `var x setget set_x, get_x` | `var x: int:` with `set(value):` / `get:` blocks |
| `scene.instance()` | `scene.instantiate()` |
| `Spatial`, `KinematicBody`, `KinematicBody2D` | `Node3D`, `CharacterBody3D`, `CharacterBody2D` |
| `move_and_slide(velocity, Vector3.UP)` | set `velocity` and `up_direction`, then `move_and_slide()` |
| `PoolVector3Array`, `PoolStringArray` | `PackedVector3Array`, `PackedStringArray` |
| `rand_range()`, `deg2rad()`, `stepify()` | `randf_range()`, `deg_to_rad()`, `snappedf()` |
| `OS.get_ticks_msec()` | `Time.get_ticks_msec()` |
| `funcref(obj, "m")` | `obj.m` (a `Callable`) |
| `master`, `puppet`, `remote` keywords | `@rpc(...)` annotation |

If you're unsure whether an API is Godot 3 or 4, check the 4.7 class reference before writing it.

---

## 6. Naming, renames and breaking changes

### 6.1 Naming

| Element | Convention | Example |
|---------|------------|---------|
| Files (`.gd`, `.tscn`, `.tres`) | snake_case | `live_fish.gd` |
| Classes | PascalCase | `LiveFish` |
| Nodes in a scene | PascalCase | `DetectionArea` |
| Functions / variables | snake_case | `get_swim_speed()` |
| Constants | SCREAMING_SNAKE_CASE | `TICK_GROUPS` |
| Preloaded script used as a type | PascalCase | `const FishAI = preload("res://ai/fish_ai.gd")` |
| Preloaded scene or resource | SCREAMING_SNAKE_CASE | `const FISH_SCENE: PackedScene = preload("res://fish/live_fish.tscn")` |
| Enums | PascalCase, singular | `SwimZone` |
| Enum values | SCREAMING_SNAKE_CASE | `BENTHIC` |
| Private members | `_snake_case` | `_body_radius` |
| Signals | past-tense snake_case | `fish_hooked` |
| Signal handlers | `_on_<emitter>_<signal>` | `_on_detection_area_body_entered` |
| Booleans | `is_` / `has_` / `can_` / `should_` | `is_active` |

snake_case file names also avoid case-sensitivity failures when exporting from Windows or macOS.

### 6.2 Never rename without explicit approval

`class_name`, signals, public functions, public variables, `@export` variables, enum names or values,
constants, file and folder paths, **and any method connected from a scene** — including private
`_on_*` handlers.

### 6.3 Where names are stored (check all of them before suggesting a rename)

- **Scene signal connections** store method names in `.tscn` (`[connection ... method="_on_x"]`).
- **Exported property values** are stored by name in `.tscn`/`.tres`. Renaming an `@export`
  silently drops every saved value, with no error.
- **AnimationPlayer tracks** reference properties and methods by string.
- **String-based calls:** `call()`, `call_deferred()`, `set()`, `get()`, `has_method()`, `connect()`
  with string names, and `Callable(obj, "name")`.
- **RPC methods** must have the same name on every peer.
- **`project.godot`**: autoload names and paths, input action names, global groups.
- **Groups** referenced as strings.
- **Doc links:** `[member old_name]`, `[method old_name]`, `[ClassName]`.
- **Paths** (`res://...`) in scenes, resources and `preload()` calls.

Search only the new project:
`grep -rn --include='*.gd' --include='*.tscn' --include='*.tres' --include='project.godot' "old_name" bandit-bash/`.
Binary `.scn`/`.res` files can't be searched; if the project has any, say so in the summary.

### 6.4 Breaking Changes table

Suggest a rename; don't apply it. Every summary and every plan ends with this table, or the line
`No breaking changes.`

| Change | Kind | Current | Proposed | Status | Places to check | Risk |
|--------|------|---------|----------|--------|-----------------|------|
| Typo + convention | Constant | `tile_nieghbor_index` | `TILE_NEIGHBOR_INDEX` | Suggested | `.gd`, `.tscn`, `.tres` | 🟡 |

`Status` is `Suggested` or `Applied`. Risk uses the legend in `CLAUDE.md` §2.

---

## 7. Scenes, resources and UID files

- **Prefer the editor.** Wiring that the editor does safely (adding nodes, connecting signals,
  assigning resources) is better done there. When a task needs it, describe the change and ask the
  user to make it, or do it in code.
- **A structural scene/resource change** is any of: adding, removing, renaming or reparenting a
  node; attaching or swapping a script; adding or removing a signal connection; adding or removing
  an `ext_resource`/`sub_resource`. Changing a property value is not structural, but can still
  change gameplay feel (`CLAUDE.md` §1).
- **When hand-editing `.tscn`/`.tres`:**
  - Never change or invent a `uid="uid://..."` value.
  - Keep `ext_resource`/`sub_resource` `id`s unique within the file, and update every reference to
    an id you change.
  - Never duplicate a node block by copy and paste; its identifiers come along with it.
  - Never edit binary `.scn`/`.res` files.
- **`.uid` sidecar files:** every script has a `<name>.gd.uid` beside it.
  - Move or rename the script and its `.uid` together (`git mv` both).
  - Delete them together.
  - Never create a `.uid` file by hand; the editor generates one for a new script.
  - Commit `.uid` files.
- After moving or renaming a script or scene, grep for its old `res://` path (§6.3).

---

## 8. Code quality baseline

### 8.1 Formatting

- Tabs for indentation; LF line endings; UTF-8 without BOM; one newline at end of file.
- Lines under 100 characters. Wrap with parentheses; continuation lines get two indent levels.
- Two blank lines around every function and inner class; one blank line between logical sections
  inside a function.
- One statement per line. The only one-line conditional allowed is the ternary
  (`a if cond else b`).
- Trailing comma on the last item of a multiline array, dictionary or enum; none on a single line.
- `and` / `or` / `not`, never `&&` / `||` / `!`.
- Double quotes, unless single quotes avoid escaping.
- Spaces around operators and `->`, after commas; no trailing whitespace.
- Comments start with `# ` (one space); commented-out code has no space and isn't committed.

### 8.2 Control flow and errors

- Guard clauses and early returns over nested `if`.
- Return the expression, not `if cond: return true` / `return false`.
- Report problems with `push_error("ClassName: detail - %s" % [value])` / `push_warning(...)`,
  never `print()`.
- **Always wrap format arguments in an array:** `"%s" % [value]`. If `value` is itself an Array,
  a bare `% value` spreads it into separate arguments and fails.
- `assert()` is removed from release builds. Never put side effects inside one.
- Check `Error` returns and nulls from `ResourceLoader.load()`, `FileAccess.open()` and similar.
  On failure, report `FileAccess.get_open_error()` or the returned `Error`.
- `@warning_ignore("...")` only with a comment explaining why the warning is wrong here.

### 8.3 Object lifetime

- For anything that can be freed while referenced (nodes, objects passed in from elsewhere), use
  `is_instance_valid(obj)`. `!= null` is only for values that can be null but not freed.
- After any `await`, the node may have been freed or removed from the tree. Check
  `is_instance_valid(self)` / `is_inside_tree()` before touching state.
- Static registries (`static var active: Array[LiveFish]`) outlive scene changes. Add in
  `_enter_tree()` or `_ready()` and always remove in `_exit_tree()`.

### 8.4 Signals and inheritance

- Connect with `signal.connect(callable)` in `_ready()`, never in `_process()`. Use
  `CONNECT_ONE_SHOT` for one-time listeners.
- Don't connect lambdas you'll need to disconnect; keep a named method or a stored `Callable`.
- Godot 4 doesn't call a parent script's `_ready`, `_process` and other virtuals automatically.
  When overriding a method that the parent script also implements, call `super()` unless you mean to
  replace the parent's behavior; if you do mean to, say so in a comment.

### 8.5 Event bus and effects

Applies to every script in combat, the campaign layer, effects, content definitions and their
presentation. The design is in `docs/plans/2026-10-23-event-bus-and-effects.md` until
`docs/design/event-bus.md` replaces it; read the relevant section before changing these systems.

- **Rules code is pure.** It never touches nodes, the scene tree, autoloads (except `NetLog`, on
  the main thread only), a bus, the global RNG or disk.
- **Rules never `await`.** Commands resolve completely, then presentation plays the resulting facts.
  Presentation never drives rules.
- **Effects react through the engine's trigger dispatch**, never through `Signal.connect` on a bus.
  Bus signals are for presentation and observers only.
- **Every state change emits a fact.** Facts are past tense and carry ids, never objects or
  Resources.
- **Content definitions are read-only at runtime.** Per-item and per-unit changes live on instances
  (deltas, granted effects), never on the shared `.tres`.
- **Read values through `session.stats(unit_id)`**, never by assembling definition, deltas and
  effects in the caller.
- **Randomness goes through a roll source.** Real resolution uses the session's combat stream; never
  `randf()`, `randi()` or `pick_random()` in rules code.
- **Gameplay randomness comes only from an `RngStream` handed to the code** (P13,
  `docs/plans/2026-10-26-rng-streams.md`); cosmetic randomness uses its own unsaved generator in
  presentation code and never a stream.
- **Instance ids come only from `InstanceIdAllocator`** and are never parsed; use the session's
  `describe(id)` for log and error text.
- **Code that may run in a sandbox on a worker thread** follows the first rule strictly and does not
  log; it returns diagnostics for the main thread to log.

### 8.6 Comments, dead code and constants

- Comments explain **why**, not **what**, in the present tense (§3.6).
- Delete dead code instead of commenting it out — but only inside members you're already changing.
  Report dead code elsewhere; don't delete it uninvited.
- No magic numbers: name them as `const`, with a comment on how the value was chosen. Don't invent
  the value (`CLAUDE.md` §1).

---

## 9. Performance

Ordered by how often each dominates a profile. Assume **many instances of the same script run
concurrently**, so per-instance costs multiply.

### 9.1 Per-frame cost × instance count

Anything in `_process` / `_physics_process` runs instances × frames per second.

- **Prefer manager loops over per-node callbacks.** 200 nodes each with `_physics_process` is 200
  script calls per frame; one manager iterating an array is one. Turn off unused callbacks with
  `set_process(false)` / `set_physics_process(false)`.
- **Stagger expensive work across frames.** Assign each instance a bucket at spawn and do heavy work
  every Nth frame. Assign buckets from an explicit counter; instance IDs aren't evenly distributed
  modulo N.
- **Never build strings you might not use.** `_log.debug("x=%s" % [value])` formats before the call
  whatever the log level. Gate on a level check first. Don't name a variable `log`: it shadows the
  built-in `log()` function.
- **Guard property writes that trigger work.** Many engine setters have no equality check and queue
  a redraw or server update on every assignment: `if sprite.flip_h != v: sprite.flip_h = v`.

### 9.2 Physics

- **Don't query outward for a small, known set.** An `intersect_shape` sphere per instance per tick
  to find a handful of objects is backwards. Keep a registry (§8.3) and compare with
  `distance_squared_to()`. Query cost grows with the number of candidates inside the volume.
- `intersect_shape()` returns a fresh `Array[Dictionary]`; `intersect_ray()` returns a fresh
  `Dictionary`. Reusing the query parameters doesn't avoid the result allocation.
- `intersect_shape(query, max_results)` silently truncates at `max_results` (default 32). If
  unrelated bodies share the mask, real targets get dropped. Keep collision layers narrow.
- Reuse `PhysicsShapeQueryParameters3D` / `PhysicsRayQueryParameters3D`: build once, then change
  `transform` or `from`/`to` per call.
- On an `Area3D`, `monitoring = false` stops it detecting others; `monitorable = false` stops other
  areas detecting it. Turn off whichever direction nothing uses.
- **Jolt specifics** (when §1 confirms Jolt): collision margins shrink shapes and can produce odd
  normals in shape queries, which matters for small colliders; ray results report `face_index = -1`
  unless enabled in project settings. Prefer resizing shapes over scaling nodes.

### 9.3 Allocation

- No `Object.new()`, Array or Dictionary construction in hot paths. Hoist to `_ready()` or pool.
  Value types (`Vector3`, `Transform3D`) are fine.
- Call `duplicate()` before mutating a shape or material shared across scene instances — Godot shares
  sub-resources by default, so an in-place change affects every instance. For editor-assigned
  resources, `resource_local_to_scene = true` does this without code. `duplicate()` is shallow by
  default; nested sub-resources stay shared.
- Each evaluation of a lambda creates a new `Callable`. Don't create them inside loops.
- `Packed*Array` types avoid per-element Variant boxing. Use them for bulk numeric data, especially
  over the network.
- `await` allocates coroutine state. Fine for setup, not for per-frame logic.

### 9.4 Lookups and dispatch

- `has_method("name")` and `call("name")` are string lookups. Cache the `has_method` result (it only
  changes if the script changes), or hold a `Callable`.
- Typed code compiles to faster typed instructions; untyped variables force dynamic dispatch (§4).
- No `get_node()` per frame: cache in `@onready` with an explicit type. Use `^"Path"` NodePath and
  `&"name"` StringName literals to avoid runtime conversion.
- `Array.has()` is O(n); `Dictionary.has()` is O(1). With frequent lookups in more than about 20
  elements, use a Dictionary. A recursive tree search is fine at small N — say so in a comment, and
  add a registry when N grows.

### 9.5 Scene tree and rendering

- Writing a node's transform marks every descendant dirty and notifies those that listen, including
  physics bodies and areas. Don't write a transform whose only consumer is a distance check; compute
  the point arithmetically.
- Node count is itself a cost. Prefer a baked composite over a multi-node assembly.
- `MultiMeshInstance3D` for large numbers of identical visuals.
- `queue_free()` + re-instantiate in a loop is churn. Pool anything spawned more than a few times per
  second.
- Visibility and processing are independent. `visible = false` stops drawing but scripts still run;
  `set_process(false)` affects one node only. To freeze a whole subtree, set
  `process_mode = Node.PROCESS_MODE_DISABLED` on its root (children inherit it). To fully idle a
  subtree, hide it **and** disable it.

### 9.6 Misc

- Vector types are valid Dictionary keys; never `dict[str(vec)]`. For grid coordinates use
  `Vector2i`/`Vector3i`: float keys need exact equality.
- Iterate with `for item in array` or `for i in count`; both evaluate the size once. In a `while`
  loop, cache `array.size()` if the array doesn't change.
- Build strings with `PackedStringArray` and `", ".join(parts)`, not `+=` in a loop.

---

## 10. Multiplayer

- **Read `steam_multiplayer_kit/` first.** Before any networked change, read the relevant parts of
  the kit and follow its API for Steam and peer setup (`CLAUDE.md`, Multiplayer). The rules below
  still govern the code you write.
- **Gate all decision logic behind `is_multiplayer_authority()`.** Clients render; they don't decide.
- **Set authority identically on every peer** (`set_multiplayer_authority()`) before the node
  replicates; a mismatch drops or rejects updates.
- **Validate every `@rpc("any_peer")` handler on the receiver:** check
  `multiplayer.get_remote_sender_id()` is allowed to make that call, and range-check every
  argument. Never trust client input.
- **Throttle network updates independently of simulation.** Simulate at full rate on the authority;
  broadcast at 10–20 Hz; interpolate on the receiver so the low rate doesn't look choppy.
- **Randomize each instance's broadcast phase**, or every instance spawned in one batch sends on the
  same frame forever.
- **Batch.** Each RPC carries its own target, method and encoding overhead, multiplied by instance
  count. Send many instances' state through one replicator using Packed arrays.
- **Dirty-check before sending.** An idle object shouldn't broadcast an unchanged value forever.
- **`unreliable`** for continuously updated values; **`reliable`** for discrete one-off events. Getting
  this backwards either floods the channel or loses state permanently. Put high-rate traffic on its
  own `transfer_channel`.
- **Consider `MultiplayerSynchronizer`** (with its replication and delta intervals) before writing a
  hand-rolled replicator, and say why if you don't use it.

---

## 11. Measuring

Never claim a speedup you didn't measure.

- Claude Code can't drive the editor profiler. Measure with a **headless benchmark scene** under
  `bandit-bash/tests/bench/`. It spawns a fixed, seeded workload, records `Time.get_ticks_usec()`
  around the code under test (or reads `Performance.get_monitor()`), prints the median and 95th
  percentile, and quits:
  `godot --headless --path bandit-bash res://tests/bench/<name>.tscn --quit-after <frames>`
- If no benchmark exists for the system, ask before creating one (`CLAUDE.md` §1).
- Measure before and after, one change at a time, on the same machine, and report both numbers.
- If you can't measure, label the improvement **unmeasured** in the summary.
