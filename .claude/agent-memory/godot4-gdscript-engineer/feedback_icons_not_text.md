---
name: feedback-icons-not-text
description: User expects graphical tile icons (gradient body drawn via _draw) for upgrade items, not plain text labels
metadata:
  type: feedback
---

Use the mod2x gradient tile icon (drawn via `_draw` in `UpgradeItem`) for any upgrade representation in the UI — not a plain text label like "2x Tile".

**Why:** The user explicitly corrected a text-only implementation and asked for "the very same icon we used to display on the shop screen." Visual consistency with the tile aesthetic matters to them.

**How to apply:** Any new upgrade type added in the future should have a corresponding `_draw_*_body` helper in `upgrade_item.gd` rather than a Label node. Mirror the mod2x gradient approach (navy→sky-blue gradient + Win95 bevel + white label text rendered via `draw_string`).
