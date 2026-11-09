# GDScript standards: engine, file layout and code quality

Detail for [the core rules](../../../.claude/rules/gdscript.md). Section numbers match the citations in code and plans. §8.5 is in the core.

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
class_name UnitToken
extends Node3D
## Brief one-line description ending in a period.
##
## Extended description of purpose and responsibilities.[br]
## Reference other classes as [BattleView] and members as [member current_state].
##
## @tutorial(Combat UI plan): docs/plans/2026-11-04-combat-ui.md
## @experimental: Replication scheme may change before 1.0.
##
## @todo: TOD-001 - Replace RPC broadcast with MultiplayerSynchronizer.
```

`class_name` comes before `extends`. The class doc follows `extends` directly, with no blank line.

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
- Static registries (`static var active: Array[UnitToken]`) outlive scene changes. Add in
  `_enter_tree()` or `_ready()` and always remove in `_exit_tree()`.

### 8.4 Signals and inheritance

- Connect with `signal.connect(callable)` in `_ready()`, never in `_process()`. Use
  `CONNECT_ONE_SHOT` for one-time listeners.
- Don't connect lambdas you'll need to disconnect; keep a named method or a stored `Callable`.
- Godot 4 doesn't call a parent script's `_ready`, `_process` and other virtuals automatically.
  When overriding a method that the parent script also implements, call `super()` unless you mean to
  replace the parent's behavior; if you do mean to, say so in a comment.

### 8.6 Comments, dead code and constants

- Comments explain **why**, not **what**, in the present tense (§3.6).
- Delete dead code instead of commenting it out — but only inside members you're already changing.
  Report dead code elsewhere; don't delete it uninvited.
- No magic numbers: name them as `const`, with a comment on how the value was chosen. Don't invent
  the value (`CLAUDE.md` §1).
