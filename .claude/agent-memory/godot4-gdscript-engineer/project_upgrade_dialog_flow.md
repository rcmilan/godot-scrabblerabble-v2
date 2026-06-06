---
name: project-upgrade-dialog-flow
description: Upgrade popup flow — single randomised offer per eligible round, two-step dialog (modifier → letter)
metadata:
  type: project
---

The upgrade system triggers in `main.gd` every `UPGRADE_EVERY_N_ROUNDS` rounds after round 1. It is a **two-step dialog** flow, not the UpgradeColumn accumulation pattern.

**Flow:**
1. `_show_upgrade_dialog()` rolls the offer: `var offered_id := GameData.MOD_3X if randi() % 3 == 0 else GameData.MOD_2X` (1/3 → 3x, 2/3 → 2x). Builds a one-item `upgrades: Array[Dictionary]` and passes it to `UpgradeDialog`.
2. Player picks → `upgrade_picked` signal fires with the chosen `upgrade_id`.
3. `_show_letter_picker()` opens a second dialog showing 5 random letter options.
4. Player picks a letter → `letter_picked` signal fires.
5. `RunState.set_letter_modifier(letter, upgrade_id)` stores the binding.
6. On each `refill_rack()`, tiles whose letter is in `letter_modifiers` get that modifier applied.

**Autoplay path:** `_autoplay_pick_upgrade_dialog(dialog, upgrade_id: String)` receives `offered_id` as a parameter (NOT captured by closure — it's a local variable in `_show_upgrade_dialog`). This was a scope bug caught during implementation.

**Sim mirror (`game_core.gd` `end_turn()`):**
```gdscript
var offered_mod := MOD_3X if rng.randi() % 3 == 0 else MOD_2X
letter_modifiers[best] = offered_mod
```
Uses `rng.randi()` (seeded) not bare `randi()` for determinism. Live game uses `randi()` because `randomize()` is called at startup.

**Why:** The probability (2/3 vs 1/3) and the two-dialog chain are non-obvious from the code alone. The autoplay parameter bug was a real defect that needed fixing.

**How to apply:** When adding a new upgrade type, the roll stays in `_show_upgrade_dialog()`. Add the new `MOD_*` constant to the weighted random expression there and mirror the same weight in `game_core.gd`. [[project-new-modifier-checklist]]
