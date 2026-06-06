---
name: project-panel-vs-container-positioning
description: Free anchor positioning (layout_mode=0) only works when the parent is a Panel, not a Container — critical for overlay/column UI elements
metadata:
  type: project
---

In `scenes/main.tscn`, `WinFrame` is a `Panel` (does NOT control children layout). `GameArea` is a `VBoxContainer` (DOES control layout and overrides child anchors). A child of `GameArea` with `layout_mode = 0` will still be laid out by the container — it ends up at the bottom of the VBox, not where its anchors say.

**Why:** Discovered when `UpgradeColumn` was placed inside `GameArea` and appeared at the bottom of the screen instead of on the left. Moving it to be a direct child of `WinFrame` (Panel) fixed it immediately.

**How to apply:** Any overlay, column, or absolutely-positioned element in `main.tscn` must be a direct child of `WinFrame`, not of `GameArea` or any other Container. Use `layout_mode = 0` + explicit anchor offsets. For the upgrade column: `anchor_bottom = 1.0`, `offset_left = 4`, `offset_top = 52` (below titlebar + HUD), `offset_right = 114`, `offset_bottom = -4`.
