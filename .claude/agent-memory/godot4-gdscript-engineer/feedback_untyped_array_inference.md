---
name: feedback-untyped-array-inference
description: GDScript cannot infer type from plain Array elements via :=; must use explicit var x: String = arr[i]
metadata:
  type: feedback
---

Never use `:=` to infer a type from an element of a plain `Array` in GDScript 4.x. It causes a parse error at runtime.

```gdscript
# WRONG — parse error: "Cannot infer the type of 'mod' variable"
var mod := board_modifiers[cell_pos.x][cell_pos.y]

# CORRECT
var mod: String = board_modifiers[cell_pos.x][cell_pos.y]
```

**Why:** `board_modifiers` in `game_core.gd` is declared `var board_modifiers: Array = []` (untyped, because GDScript 4.x doesn't support nested typed arrays like `Array[Array[String]]`). The `:=` walrus operator requires a statically-known type on the right side — it can't resolve one from a plain Array element. This caused 3 parse errors in `game_core.gd` during the 3x modifier implementation, all in the scoring loops.

**How to apply:** Any time you read from `board`, `board_modifiers`, `rack`, or any other `Array` (not `Array[T]`) that stores dictionaries or primitives, always write `var x: ExpectedType = arr[i]` explicitly. Also applies to `rack[i]` when reading `.letter` or `.modifier` fields — cast or annotate explicitly.
