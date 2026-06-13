# Upgrade Wizard — Design

Redesign of the upgrade modal system, settled in design review
(2026-06-13). Replaces the two-step upgrade flow (single take-it-or-
leave-it modifier → letter picker) with a single InstallShield-style
wizard dialog offering three composite upgrades.

## Current state (what this replaces)

- Every `UPGRADE_EVERY_N_ROUNDS` (3) rounds — rounds 4, 7, 10… — after
  the round transition, `main.gd::_show_upgrade_dialog` (line ~296)
  offers exactly ONE modifier (67% `2x` / 33% `3x`) with a Skip button.
- Picking it opens `letter_picker_dialog.tscn`: choose 1 of 5
  uniform-random letters; Back returns to the first dialog (hidden,
  not freed, while the picker is up).
- `RunState.set_letter_modifier(letter, mod)` stores the pick;
  `rack.refill()` applies it. The dict **overwrites**, so a later 2x
  can silently downgrade an existing 3x.
- The sim mirrors this in `game_core.gd:206-217` (5 uniform letters →
  highest points → 67/33 roll), tested by TSM10.

### Known defects fixed by this redesign

1. **Focus cursor misalignment:** `upgrade_item.gd:47-48` draws the
   yellow focus rect around the whole control (`Rect2(Vector2.ZERO,
   size)`) while the body is drawn inset at y=4 with +8px control
   height — the border floats off the tile. (`letter_item.gd:87-88`
   has the same latent bug when stretched by its container.) The new
   card draws the focus/selection border tight around the tile-preview
   rect (`body_rect.grow(2)`).
2. **Interaction leak during modals:** three unguarded input paths let
   the player interact with the game while the upgrade is up:
   `main.gd:94 on_tile_returned_to_rack` (no guard),
   `tile.gd:79 _get_drag_data` (drags can start),
   `board_cell.gd:38 _on_gui_input` (clicking a cell calls
   `grab_focus()` and **steals keyboard focus from the dialog**).

## The new flow

One dialog, one decision, one click path:

> Round won → transition → (if upgrade due) → **Upgrade Wizard** with
> three composite offer cards → select → Next → applied → back to play.

The letter picker is deleted entirely.

## Offer generation

`UPGRADE_OFFER_COUNT` offers per wizard (currently **3**; the layout
supports **1–4**), each a complete `{letter, modifier}` bundle
("All E tiles score 2×"):

- **Letters:** N **distinct** letters, sampled **weighted by
  `LETTER_DISTRIBUTION`** (common letters appear more often),
  **excluding letters already in `RunState.letter_modifiers`** — this
  kills the 3x→2x downgrade trap at the source, no warning UI needed.
  Guard: if fewer than N unowned letters remain (unreachable in normal
  play), allow repeats of owned letters and log it.
- **Modifier per offer rolled independently:** 67% `2x` / 33% `3x`
  (today's odds). No forced 3x per screen — variance is the content.
- **Skip stays a plain button** (no compensation) — with three real
  offers, skipping is legitimately rare. Skip economy is a separate
  question, out of scope.
- Generation lives in `main.gd` (the dialog stays a dumb view fed via
  `populate()`); live game uses global `randi()` as today. The sim
  mirrors generation with its seeded `rng` (see Sim parity).

## The wizard dialog

> **This section was rewritten 2026-06-13** after the first
> implementation shipped broken (elements floating over the board with
> no background; arrow keys appeared dead; banner title flew off
> screen). The structure below is the corrected target. See
> `docs/upgrade_wizard_fixes.md` for the slice-by-slice migration from
> the shipped code to this spec.

Full InstallShield framing, built from the existing `WindowFrame` /
`TitleBar` chrome. The whole dialog is **container-driven** so the gray
background covers every element by construction — nothing is positioned
by hand-set anchors, so nothing can float outside the painted frame.

### Node tree (the contract)

```
ModalRoot (Control)                         ← full-rect, mouse_filter = STOP
│                                             THE reference frame + input blocker.
│                                             Holds class_name UpgradeDialog + script.
└─ CenterContainer                          ← full-rect; centers the window, any size
   └─ Window (PanelContainer, "WindowFrame")← paints opaque gray; custom_minimum_size
      │                                        = (420, 360) → FIXED size (see below)
      └─ RootVBox (VBoxContainer)
         ├─ TitleBar (Panel, "TitleBar")     ← full width, slim; title + X only
         └─ BodyArea (HBoxContainer)
            ├─ Banner (Control)              ← custom_minimum_size.x = 96,
            │                                  size_flags_vertical = FILL
            └─ BodyMargin (MarginContainer)  ← ~10px all sides (content breathing room)
               └─ ContentVBox (VBoxContainer)← size_flags_horizontal = EXPAND_FILL,
                  │                            separation ≈ 8
                  ├─ HeaderLabel  "Choose an upgrade to install:"
                  ├─ Grid (GridContainer)     ← columns = 2; reserved at 2-row footprint
                  ├─ Caption (Label)          ← autowrap, height reserved for 2 lines
                  └─ ButtonRow (HBoxContainer)← right-aligned: < Back  Next >  Cancel
```

```
┌──────────────────────────────────────────────┐
│ ■ Upgrade Wizard                         [X] │  ← title bar: X only, X = Skip
├────────┬─────────────────────────────────────┤
│        │  Choose an upgrade to install:      │
│ banner │   ┌────────┐   ┌────────┐            │  ← 2-column grid,
│ navy→  │   │ card 0 │   │ card 1 │            │     up to 2 rows
│ deep-  │   └────────┘   └────────┘            │     (1–4 cards,
│ navy   │   ┌────────┐   ┌────────┐            │     row-major,
│ grad,  │   │ card 2 │   │ card 3 │            │     top-left fill)
│ rotated│   └────────┘   └────────┘            │
│ title  │  Every E tile scores double points… │  ← caption follows focus
│        │              < Back   Next >  Cancel │  ← right-aligned
└────────┴─────────────────────────────────────┘
```

### Why a PanelContainer (the background fix)

The first build used a bare `Panel` with a hand-set `size` plus
manual centering math in `main.gd`. A `Panel` is **not** a container,
so it does not grow to wrap its children; content overflowed the
painted gray rect and the header/buttons rendered over the board. A
**`PanelContainer`** paints the `WindowFrame` stylebox **and** is a
container, so the gray is sized from the content — the background
covers all elements by construction. `CenterContainer` then centers it
with no math. The `WindowFrame` stylebox is already opaque gray
(`SB_WindowFrame`, alpha 1) — the problem was never transparency, only
sizing.

### Fixed size

- **`Window.custom_minimum_size = (420, 360)`** — a fixed canvas sized
  to fit the **4-card (2×2) worst case** plus the (widest) button row.
  Because content always fits inside, the dialog renders at exactly
  420×360 for **every** variation (1, 2, 3, or 4 offers) and never
  auto-resizes. The container's grow-to-fit behavior remains only as an
  invisible safety net that normal play never triggers.
- **Centering** is handled by `CenterContainer`, not by
  `custom_minimum_size` math. Delete the old `main.gd` positioning.

### Grid (2 columns, fixed footprint)

- **`Grid.columns = 2` always.** Cards fill row-major from the
  top-left: 1 → one card; 2 → one row; 3 → two then one (partial row
  left-aligned); 4 → full 2×2.
- **Reserve the grid at its 2-row footprint** (set the grid's
  `custom_minimum_size` to the full 2×2 size: `2*88 + 12 = 188` wide,
  `2*96 + 12 = 204` tall) so the caption and buttons never shift when
  there are fewer than 4 cards. Card-to-card gap ≈ 12px
  (`h_separation` / `v_separation`).

### Banner

- **96px wide, full body height** (`custom_minimum_size.x = 96`,
  `size_flags_vertical = FILL`). It auto-spans whatever height the body
  is, so the gradient always fills it edge-to-edge — no overflow.
- **Vertical gradient navy → deep-navy** (`Color(0,0,0.5019)` →
  `Color(0,0,0.20)`, **not** pure black) so it reads as the classic
  InstallShield blue panel, not a dead void.
- **"ScrabbleRabble 95" drawn in code** in the banner's draw callback
  (`draw_set_transform` rotate -90°, centered) — **not** a rotated
  `Label` node (the node flew off-screen via broken anchors). Kept as a
  banner so its content can become dynamic later.

### Title bar & buttons

- **Title bar:** text "Upgrade Wizard"; only the `X` decoration button
  (Min/Max removed — period-correct for wizards). `X` = Skip.
- **Buttons** (right-aligned `ButtonRow`): `< Back` permanently
  `disabled = true`, `focus_mode = NONE` (can never trap focus).
  `Next >` commits the selected card. `Cancel` = Skip, same handler as
  `X`. Enter on a focused card also confirms (same outcome as Next).

### Offer cards

Each card (evolved `upgrade_item.gd`, keeps `class_name UpgradeItem`):

```
┌─────────────┐
│   ┌─────┐   │  ← 56×56 tile preview: modifier gradient body
│   │  E  │   │    (blue 2x / green 3x), white letter (24px) and
│   │    1│   │    point value (9px) — exactly what the tile will
│   └─────┘   │    look like in the rack (absorb letter_item.gd's
│     2x      │    face drawing)
│  12 in bag  │  ← LETTER_DISTRIBUTION count, small gray text
└─────────────┘
```

- **Radio-select semantics:** click or arrow-focus *selects* (yellow
  border = selection); it does NOT commit. First card pre-selected on
  open so `Next >` always has a target. **Double-click commits**
  directly (wizard-era shortcut).
- **Selection follows focus:** on `focus_entered` a card emits
  `selected`, so the yellow border and caption update the moment focus
  moves. This is the fix for "arrow keys look dead" — the first build
  tied the border to `is_selected`, which only changed on click, so
  keyboard navigation produced no visible change.
- **Modifier label uses ASCII `2x` / `3x`**, never the `×` glyph —
  `fonts/w95fa.otf` has no U+00D7 and renders it as a missing-glyph
  box. `2x`/`3x` also matches the modifier tile bodies.
- **Focus/selection border drawn tight around the tile-preview rect**
  (`tile_rect.grow(2)`), not the control rect — the cursor alignment
  fix.
- Signals: `pick_requested` is replaced by `selected(index)` +
  `confirmed(index)` (double-click / Enter).

### Caption copy

- Card focused/selected: `Every {LETTER} tile scores {double|triple}
  points for the rest of the run.`
- Cancel/Skip focused: `Install no upgrade this round.`

### Keyboard navigation (2×2 grid)

- **2D arrow nav**, computed from `columns = 2`: Right/Left = index
  ±1, Down/Up = index ±2 (one row), clamped at edges (no wrap).
  Missing cells in a partial grid (1 or 3 cards) are skipped so focus
  never lands on emptiness.
- **Enter** confirms the selected card (identical to pressing Next).
- **Card ↔ button bridge:** Down from the bottom card row focuses
  **Next**; Up from Next returns to the grid. Cancel is reachable by
  Tab from Next, by mouse, or via the title-bar `X`. `< Back` stays
  disabled and `focus_mode = NONE`, so it never traps focus.

## Modal input blocking

The blocker is the scene's own root: **`ModalRoot`** — a full-rect
`Control` with `mouse_filter = STOP`. Every mouse event aimed at
board/rack/HUD dies there; it doubles as the dialog's reference frame.
No tint (Win95 didn't dim). Keyboard is gated by
`main.gd::_unhandled_input` (`is_upgrading`) plus focus containment in
the dialog. `main.gd` no longer creates a separate blocker node — it
just instantiates the scene and adds it to the layer-50 `CanvasLayer`.

Decision: blocker ONLY — no per-entry-point guards added in v1.
Known residual edge (accepted): a drag started *before* the modal
appears can still drop on the rack after; if it shows up in practice,
one guard in `on_tile_returned_to_rack` closes it.

## Autoplay & sim parity

**Pick heuristic (both autoplay and sim):** choose the offer
maximizing

```
LETTER_DISTRIBUTION[letter] × LETTER_POINTS[letter] × multiplier
```

(multiplier = 2 or 3) — expected score contribution per bag cycle.
Ties broken by offer order. Deterministic.

- **Live (`main.gd`):** `_autoplay_pick_upgrade_dialog` becomes
  "select best card, trigger Next". `_autoplay_pick_letter` is deleted
  with the picker.
- **Sim (`game_core.gd`):** lines 206–217 are replaced by a mirror of
  the new generator (distinct, distribution-weighted, unowned, seeded
  `rng`) + the heuristic above. Constants stay mirrored.
- **Tests:** TSM10 updated (offers distinct + unowned; modifier still
  2x/3x; auto-pick still populates `letter_modifiers` at rounds 4,
  7…). Add TSM11: offers never include an already-modified letter and
  the pick is deterministic under a fixed seed.
- Autoplay log lines to keep stable: `[Turn]`/`[RunState]` unchanged;
  new `[UpgradeWizard]` prefix for wizard state transitions
  (shown/selected/confirmed/skipped).

## Deletions

`scenes/letter_picker_dialog.tscn`, `scripts/letter_picker_dialog.gd`,
`scripts/letter_item.gd` (+ their `.uid` files), and in `main.gd`:
`_show_letter_picker`, `_generate_letter_options`,
`_autoplay_pick_letter`. Git history preserves them.

## Explicitly out of scope (possible follow-ups)

- Upgrade paths on owned letters ("upgrade E×2 → E×3")
- Skip compensation ("+1 turn next round")
- Build visibility strip (HUD or in-dialog "your build" chips;
  game-over build recap)
- Upgrade telegraphing in the HUD ("Upgrade in 2 rounds")
- Window-open animation for modals
- New modifier types beyond 2x/3x
