---
name: project-new-modifier-checklist
description: Complete file-by-file checklist for adding a new tile modifier (e.g. 3x after 2x)
metadata:
  type: project
---

Adding a new modifier (e.g. `MOD_3X`) touches **every** layer of the stack. Miss one and the modifier silently breaks in live play or diverges from the sim.

**Checklist — touch all of these:**

1. **`scripts/game_data.gd`** — add `const MOD_3X: String = "3x"` alongside MOD_NONE / MOD_2X.

2. **`scripts/tile.gd`** — add gradient color constants (`C_MOD3X_GRADIENT_LEFT/RIGHT`), branch in `_draw()` (new `elif modifier == GameData.MOD_3X`), and in `_refresh_visual()` extend the modifier guard so labels go white for the new mod too.

3. **`scripts/board_cell.gd`** — same gradient constants as tile.gd. In `_draw()` branch on `active_mod == GameData.MOD_3X` for the background. In `_sync_label_color()` extend the guard.

4. **`scripts/upgrade_item.gd`** — add `_draw_mod3x_body(rect)` helper (gradient + bevel + draw_string). Branch in `_draw()` on `upgrade_id == GameData.MOD_3X`.

5. **`scripts/main.gd`** — three scoring paths must each handle the new modifier:
   - `_score_word()` valid-word path
   - sub-word valid path
   - invalid-word fallback path
   Also update `_get_modifiers_str()` for logging.

6. **`scripts/sim/game_core.gd`** — add `const MOD_3X: String = "3x"`. Same three scoring paths in `_score_word_sim()`, sub-word valid path, and invalid-word fallback. Update upgrade auto-pick in `end_turn()`.

7. **`scripts/sim/tests/test_game_core.gd`** — update any TSM test that checks for a specific modifier to also accept the new one (or add a new test case TSMn+1).

**Why:** Discovered during 3x implementation — missing a scoring path silently under-scores tiles, missing a visual branch leaves tiles rendering as plain yellow. The game_core.gd drift is the most dangerous because the sim gives no visual feedback.

**How to apply:** Before writing any code, open all 7 files and plan the branches. Run `test_game_core.gd` after each file group. [[feedback-sim-verification]]
