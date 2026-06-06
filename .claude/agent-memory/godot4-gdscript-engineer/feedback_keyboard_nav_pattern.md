---
name: feedback-keyboard-nav-pattern
description: Keyboard-navigable UI controls must use FOCUS_ALL + _gui_input, same pattern as board_cell.gd and END TURN button
metadata:
  type: feedback
---

All keyboard-navigable UI elements must use `focus_mode = FOCUS_ALL` and handle input in `_gui_input`, not via `_unhandled_input` on a parent node with a custom string-based focus mode (e.g., `_focus_mode = "board"`).

**Why:** The user rejected a custom `_focus_mode` string approach and asked for "the same type of behavior as the END TURN button." The `board_cell.gd` pattern (FOCUS_ALL + `_gui_input` + emit signals upward) is the established contract in this project.

**How to apply:**
- New focusable controls: set `focus_mode = FOCUS_ALL` in `_ready`, handle `ui_accept` / `ui_cancel` / `ui_up` / `ui_down` / `ui_left` / `ui_right` in `_gui_input`, call `get_viewport().set_input_as_handled()` after each handled event.
- Sibling navigation: filter parent's children by class (`is UpgradeItem`), find self, offset index.
- Parent-to-board handoff: emit a `board_focus_requested` signal (or equivalent) so `main.gd` can call `board.focus_cell(cursor)`.
