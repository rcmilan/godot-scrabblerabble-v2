---
name: project-upgrade-column-architecture
description: Shop was removed; replaced with UpgradeColumn — a left-side panel visible from round 4+ whenever upgrades are pending
metadata:
  type: project
---

The shop screen (`scenes/desktop.tscn`, `scripts/desktop.gd`) was completely removed. Upgrades are now shown in an `UpgradeColumn` panel on the left side of the board, visible from round 4 onward (every `UPGRADE_EVERY_N_ROUNDS` = 3 rounds: round 4, 7, 10…).

**Key architecture decisions:**
- `UpgradeColumn` (Panel, not Container) is a direct child of `WinFrame` in `main.tscn`, positioned with `layout_mode = 0` free anchors on the left.
- Unpicked upgrades accumulate — if player skips a round's upgrade, next eligible round shows multiple items.
- Column hides itself when all upgrades are picked (`visible = false`); shows again when new ones are added.
- `UpgradeItem` (extends Control, `FOCUS_ALL`) draws the mod2x icon via `_draw` and handles its own keyboard input.
- `unique_name_in_owner = true` on both nodes allows `%UpgradeColumn` scene-agnostic lookup in `main.gd`.
- Sim: `game_core.gd` auto-picks upgrades inline in `end_turn()` — no `shop_strategy` param. Test coverage: `test_upgrade_auto_pick_at_intervals` (was TSM10).

**Why:** User wanted the upgrade choice to remain part of the game flow without interrupting it with a separate screen. The column keeps upgrades visible but non-blocking.

**How to apply:** If adding new upgrade types, add a new `_draw_*_body` method in `upgrade_item.gd` and branch on `upgrade_id` in `_draw`. Mirror any new upgrade IDs in `game_core.gd`'s auto-pick logic.
