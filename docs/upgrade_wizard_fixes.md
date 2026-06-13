# Upgrade Wizard — Fixes

The upgrade wizard shipped (commits `a3c9ba8`…`164845e`) but the live
result is broken in four distinct ways. This doc diagnoses each and
gives exact fixes. Read `docs/upgrade_wizard_design.md` for intent.

All work is in three files:
- `scripts/upgrade_item.gd` (the offer card)
- `scripts/upgrade_dialog.gd` (the dialog controller)
- `scenes/upgrade_dialog.tscn` (layout)

Do the fixes in order; each is independent and committable.
Verification command (must still pass / exit 0):

```
godot --headless --path . --script res://scripts/sim/tests/run_tests.gd
timeout 180 godot --headless --path . -- --autoplay=word_search; echo "exit: $?"
```

None of these fixes touch offer generation or the sim, so TSM10/TSM11
and the autoplay loop must be unaffected — if they break, you changed
too much.

---

## Symptoms (from the live screenshot)

1. **Cards laid out 2×2, not in a single row** — O and P on the top
   row, I orphaned below.
2. **Arrow keys appear to do nothing** — the player cannot navigate
   between cards; only mouse-clicking a card changes the selection.
3. **The left banner is a giant black void**, and the rotated
   "ScrabbleRabble 95" title escapes the dialog entirely — it renders
   over the board at the top-left of the screen.
4. **The "×2 / ×3" labels render as garbage** (the `×` glyph is
   missing from the w95fa font).

---

## Fix 1 — Cards in a single row (the 2×2 bug)

**Root cause:** `upgrade_dialog.gd::populate` line ~35 overrides the
scene's `columns = 3` with leftover logic from the old single-offer
dialog:

```gdscript
_grid.columns = max(1, int(ceil(sqrt(float(count)))))   # ceil(sqrt(3)) = 2
```

`ceil(sqrt(3))` is **2**, so three cards wrap to a 2×2 grid.

**Fix:** put every offer in one row. Replace that line with:

```gdscript
_grid.columns = count
```

(The scene's `Grid` node already declares `columns = 3`; this just
stops the override from shrinking it.)

---

## Fix 2 — Arrow-key navigation (the critical one)

**Root cause — a regression, not a missing feature.** In the deleted
`letter_item.gd`, the yellow border was drawn on `has_focus()`, so
moving keyboard focus *was* the visible selection. The new
`upgrade_item.gd` decoupled them: the border is now drawn on
`is_selected` (line ~81), and `is_selected` is only updated by a mouse
click or a confirm — **never by focus changes**.

So when the player presses Right:
- `upgrade_item._gui_input` fires `nav_right`,
- `upgrade_dialog._on_item_nav_right` calls `grab_focus()` on the
  neighbor,
- focus moves correctly… **but nothing redraws as selected and the
  caption never updates**, because `is_selected` didn't change.

From the player's seat: "arrow keys are dead." The design doc actually
specified the fix ("focus_entered → emit selected") but it wasn't
wired.

**Fix — make selection follow focus.** In `upgrade_item.gd::_ready`,
change the focus signal hookup from a bare redraw to emitting
`selected`:

```gdscript
# was: focus_entered.connect(queue_redraw)
focus_entered.connect(emit_selected)
focus_exited.connect(queue_redraw)
```

`emit_selected()` already exists and emits `selected(item_index)`,
which `upgrade_dialog._on_item_selected` handles — it updates
`is_selected` on every card, redraws them, and refreshes the caption.
Now arrow navigation is fully visible: focus moves → that card becomes
the selected card → caption updates.

**Also fix the focus trap.** `populate` wires
`nav_up`/`nav_down` to `_next_btn.grab_focus()`. Once focus lands on
the Next button there is no keyboard path back to the cards, and the
disabled Back button plus an unset `focus_neighbor` chain leave the
player stranded. For a single row of three cards this up/down jump adds
nothing. Remove it — delete these two lines in `populate`:

```gdscript
item.nav_up.connect(func(): _next_btn.grab_focus())
item.nav_down.connect(func(): _next_btn.grab_focus())
```

Keyboard model after this fix: **Left/Right** moves between cards
(selection follows), **Enter** confirms the selected card
(`ui_accept` on a card already emits `confirmed`, which is identical to
pressing Next). Next/Cancel remain reachable by mouse or Tab.

> If, after Fix 2, arrows still don't move focus at all (i.e. the
> items aren't receiving key events in `_gui_input`), the fallback is
> to handle navigation in the dialog instead: give `UpgradeDialog` a
> `_gui_input`/`_unhandled_input` that reads `ui_left`/`ui_right` and
> calls `_item_nodes[new_index].grab_focus()` directly. But the
> item-level `_gui_input` matches the old working letter picker, so
> the selection-follows-focus fix above is expected to be sufficient.

---

## Fix 3 — The banner (black void + escaped title)

Two separate defects in the same node.

### 3a. The rotated title escapes the dialog

**Root cause:** `BannerLabel` (scene lines ~66-80) combines
`anchors_preset = 15` (full-rect) with `offset_left = 48`,
`offset_right = -48`, `offset_top = -48`, `offset_bottom = 48` on a
96px-wide banner. That resolves to a **0-px-wide** rect starting
*above* the banner (`y = -48`), then `rotation = -1.5708` spins it
about the top-left pivot — flinging the text out of the dialog to the
top-left of the screen (exactly what the screenshot shows).

**Fix (recommended): delete the `BannerLabel` node and draw the text
in code**, where the transform is controllable. In
`upgrade_dialog.gd::_on_banner_draw`, after the gradient loop, add:

```gdscript
var font := get_theme_default_font()
if font:
    var text := "ScrabbleRabble 95"
    var font_size := 16
    var text_w := font.get_string_size(text, HORIZONTAL_ALIGNMENT_LEFT, -1, font_size).x
    # Rotate -90° about the banner centre, then draw the string centred
    # on the new axis so it reads bottom-to-top.
    var centre := banner_rect.size * 0.5
    _banner.draw_set_transform(centre, -PI / 2.0, Vector2.ONE)
    _banner.draw_string(font, Vector2(-text_w * 0.5, 0), text,
            HORIZONTAL_ALIGNMENT_LEFT, -1, font_size, Color(1, 1, 1, 1))
    _banner.draw_set_transform(Vector2.ZERO, 0.0, Vector2.ONE)  # reset
```

(Remove the `BannerLabel` node and its properties from
`upgrade_dialog.tscn` lines ~66-80.)

> Acceptable simpler fallback if the rotated draw is fiddly: drop the
> banner text entirely and ship a clean gradient-only banner. A blank
> banner reads as intentional; escaped text does not.

### 3b. The gradient is almost entirely black

**Root cause:** `_on_banner_draw` lerps navy → `Color.BLACK` across
~238 rows, so all but the top sliver is black — a dead void rather
than a banner.

**Fix:** lerp navy → a darker navy, not pure black, so it still reads
as the classic InstallShield blue panel:

```gdscript
var navy := Color(0, 0, 0.5019, 1.0)
var deep := Color(0, 0, 0.20, 1.0)   # was Color.BLACK
...
var color := navy.lerp(deep, t)
```

### 3c. Safety: clip the banner to the dialog

Set `clip_contents = true` on the root `UpgradeDialog` Panel in the
scene so nothing a banner draws can ever bleed past the window frame
again.

---

## Fix 4 — "×2 / ×3" renders as garbage

**Root cause:** the multiplication sign `×` (U+00D7) is not present in
`fonts/w95fa.otf`, so it draws as a missing-glyph box/dot (visible
under each tile in the screenshot).

**Fix:** use ASCII in `upgrade_item.gd::_draw` (line ~86):

```gdscript
# was: var mod_text := "×2" if modifier == GameData.MOD_2X else "×3"
var mod_text := "2x" if modifier == GameData.MOD_2X else "3x"
```

`2x` / `3x` also matches the text historically drawn on modifier tile
bodies, so it reads consistently. Leave the caption wording
("double"/"triple") alone — those are plain ASCII words and render
fine.

---

## Fix 5 — Scene hygiene (do while you're in the file)

`scenes/upgrade_dialog.tscn` line 7 carries a leftover
`size = Vector2(240, 160)` from the old 240×160 dialog, contradicting
`custom_minimum_size = Vector2(430, 260)`. It doesn't break layout
(the container minimums win) but it's misleading. Set it to
`Vector2(430, 260)` or delete the `size` line.

---

## Verification checklist (with a window)

Reach round 4 (or temporarily set `UPGRADE_EVERY_N_ROUNDS = 1` in
`run_state.gd` for testing — **revert before committing**) and confirm:

1. Three cards sit in **one horizontal row**.
2. **Left/Right arrows move the yellow selection** between cards and
   the caption updates with each move. Enter confirms the highlighted
   card. Double-click and single-click+Enter also confirm.
3. The banner is a **blue gradient panel** with the product name
   reading bottom-to-top **inside** it — nothing draws over the board.
4. Each card shows **"2x" / "3x"** cleanly (no missing-glyph box).
5. Board and rack stay inert behind the modal; Cancel and the title-bar
   X both skip.

Then the headless checks:

6. `run_tests.gd` — all TC/TS/TSM pass (TSM10, TSM11 included).
7. `--autoplay=word_search` exits 0 and the upgrade-round log still
   shows `[UpgradeWizard] autoplay pick — …` → `[RunState] letter
   modifier set — …` (autoplay emits `upgrade_picked` directly, so the
   UI fixes must not disturb it).

## Suggested commits

- `fix: upgrade cards in a single row`
- `fix: upgrade wizard arrow-key navigation (selection follows focus)`
- `fix: upgrade banner gradient + in-code rotated title`
- `fix: use ASCII 2x/3x on upgrade cards (w95fa lacks ×)`

(Or one combined `fix: upgrade wizard UX — layout, navigation, banner,
glyphs` — match the cadence of recent commits.)
