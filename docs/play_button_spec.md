# PLAY Button + Explicit Commit — Design Spec

## Summary

Two linked changes, decided together in interview:

1. **Visual:** replace the cramped top-right `END TURN` button with a clear,
   prominent **`PLAY`** button — bigger, inset from the window edge, and given
   the authentic Win95 *default-button* outline so it reads as the primary
   action. It grays out (disabled) until the player has placed at least one
   tile.

2. **Gameplay:** stop auto-ending the turn the instant the player fills their
   placement quota. Placing tiles no longer plays/scores the move. The player
   may place up to `tiles_per_turn` tiles, freely **move / swap / return** them
   (the drag feature already shipped), and the turn resolves **only** when they
   press `PLAY` (or the existing `confirm_turn` key). The per-turn placement
   limit is preserved as a hard cap on placement.

Three files change: `scenes/main.tscn`, `themes/win95.tres`, `scripts/main.gd`.
No `scripts/sim/` change (see §7).

## Background — why these belong together

`_place_tile_on_cell` (`main.gd`) currently ends the turn automatically:

```gdscript
if pending_cells.size() >= RunState.tiles_per_turn:
    _on_end_turn_pressed()
```

So the player's *last placement* silently computes and commits — there is no
moment to reconsider, and the `END TURN` button is only ever pressed for
short moves. Making `PLAY` the sole commit gives the player that moment; the
move/swap/return tools (already implemented) are what they use during it. The
two changes only make sense as one feature: a prominent commit button is
pointless if the turn auto-commits, and removing auto-commit is confusing
without an obvious button to press.

The placement quota (`tiles_per_turn`) survives unchanged — it just stops
doubling as the commit trigger and becomes a pure cap.

## 1. Rename — `scenes/main.tscn`

`EndTurnButton.text`: `"END TURN"` → `"PLAY"`. The node name and the
`%EndTurnButton` unique reference stay (renaming the node would touch
`main.gd` for no gameplay benefit; the label is what the player sees).

## 2. Size + edge spacing — `scenes/main.tscn`

The button stays in the top HUD row (`Score | Placed | PLAY`).

- `EndTurnButton.custom_minimum_size = Vector2(120, 32)` — the tallest/widest
  control in the row, an easy mouse target.
- Inset the row off the window border: wrap the existing `HUD` `HBoxContainer`
  in a `MarginContainer` (~10px left/right margins) so `PLAY` no longer butts
  against the frame. The labels and button keep their order and unique names.
- Add `theme_override_constants/separation` (~12px) on the `HUD` HBox so `PLAY`
  doesn't crowd the `Placed` label.

## 3. Emphasis — `PlayButton` theme variation in `themes/win95.tres`

A new theme-type-variation, applied via
`theme_type_variation = &"PlayButton"` on the button (same mechanism as the
existing `ScoreNeon` / `TitleBar` variations).

- `PlayButton/base_type = &"Button"`.
- `PlayButton/font_sizes/font_size = 16` (default buttons are 14).
- **Default-button outline:** a new `SB_PlayNormal` StyleBoxFlat — gray body
  (`Color(0.7529, 0.7529, 0.7529, 1)`), 1px near-black border
  (`Color(0.039, 0.039, 0.039, 1)`) on all four sides — mirrors the framed
  look of the existing `SB_RaisedOuter` so the button reads as "the default
  action." Used for `normal` and `hover`.
- Reuse existing styles for the other states: `pressed = SB_RaisedPressed`,
  `disabled = SB_Disabled`, `focus = SB_Focus`. (Disabled already grays the
  font via `Button/colors/font_disabled_color`.)

Color is deliberately avoided — Win95 never colored push buttons; the outline
+ larger font is the period-correct way to mark a primary action.

## 4. Disabled state — `main.gd::_update_hud`

`PLAY` should *show* when it's actionable:

```gdscript
end_turn_button.disabled = pending_cells.is_empty() \
    or RunState.is_transitioning or RunState.is_upgrading or _discard_busy
```

Place at the end of `_update_hud`, which already runs after every board/rack
mutation. Net effect: empty board → grayed PLAY; place a tile → PLAY lights
up. This matches the handler's existing "no-op when nothing pending" rule and
prevents commits mid-animation/overlay.

## 5. Remove auto-end — `main.gd::_place_tile_on_cell`

Delete the trailing two lines:

```gdscript
if pending_cells.size() >= RunState.tiles_per_turn:
    _on_end_turn_pressed()
```

Placement now only places. The debug autoplay loop is unaffected — it calls
`_on_end_turn_pressed()` explicitly (`main.gd:634, 656`), so it still commits.

## 6. Hard cap on placement — `main.gd` + `board_cell.gd`

With auto-end gone, the quota becomes a cap: a *new* rack→board placement is
refused once `pending_cells.size() >= tiles_per_turn`.

- New gate helper on `main`:
  ```gdscript
  func can_place_pending_tile() -> bool:
      return pending_cells.size() < RunState.tiles_per_turn
  ```
- `BoardCell._can_drop_data` rack-tile branch consults it so the drop visibly
  snaps back (same UX as dropping on an occupied/locked cell). Board-tile
  moves/swaps are **not** gated by the cap — they don't change the count.
- Defensive guard in `on_tile_dropped_on_cell` for the rack branch (a drop
  shouldn't slip through if `_can_drop_data` and state ever disagree).

Keyboard placement (`_try_place_letter_on_cursor`) routes through
`_place_tile_on_cell` as well, so it must honor the same cap — gate it on
`can_place_pending_tile()` too.

## 7. Commit semantics (unchanged) + sim parity

- `PLAY` (and the `confirm_turn` key) remain the commit; both no-op at zero
  pending tiles. Pressing `PLAY` with no valid word still commits, locks,
  scores 0, and spends the turn — the risk of a bad commit is intentional.
- **No `scripts/sim/` change.** `game_core.gd` already separates
  `place_pending_tile` from an explicit `end_turn(...)` — it never auto-ended
  on the cap, so the sim already models "place, then explicitly end." This
  change only removes a UI convenience; sim parity is untouched. Drag/drop,
  focus, and theme are scene-coupled and have no headless test.

## Files touched

- `scenes/main.tscn` — rename text; `custom_minimum_size`; wrap HUD in a
  `MarginContainer`; HBox separation; `theme_type_variation = &"PlayButton"`.
- `themes/win95.tres` — `SB_PlayNormal` StyleBoxFlat + `PlayButton/*` variation.
- `scripts/main.gd` — disabled wiring in `_update_hud`; remove auto-end;
  `can_place_pending_tile`; cap-gate the rack-drop and keyboard-place paths.

## Out of scope

- Blocking `PLAY` on a zero-score board (rejected in interview — commit
  stays a real cost).
- Moving `PLAY` out of the HUD row (kept in place per interview).
- Colored / animated button states beyond the existing pop + glitter.
- Any `game_core.gd` / strategy change.
