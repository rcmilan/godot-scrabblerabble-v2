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

Three offers per wizard, each a complete `{letter, modifier}` bundle
("All E tiles score 2×"):

- **Letters:** three **distinct** letters, sampled **weighted by
  `LETTER_DISTRIBUTION`** (common letters appear more often),
  **excluding letters already in `RunState.letter_modifiers`** — this
  kills the 3x→2x downgrade trap at the source, no warning UI needed.
  Guard: if fewer than 3 unowned letters remain (unreachable in normal
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

Full InstallShield framing, built from the existing
`WindowFrame`/`TitleBar` chrome:

```
┌──────────────────────────────────────────────┐
│ ■ Upgrade Wizard                         [X] │  ← title bar: X only
├────────┬─────────────────────────────────────┤     (no Min/Max);
│        │  Choose an upgrade to install:      │     X = Skip
│ banner │                                     │
│ navy→  │   [card E×2] [card S×2] [card Q×3]  │
│ black  │                                     │
│ grad,  │  Every E tile scores double points  │  ← caption, follows
│ white  │  for the rest of the run.           │     focus, 2 lines
│ rotated│                                     │     reserved
│ title  │        < Back   Next >   Cancel     │  ← right-aligned
└────────┴─────────────────────────────────────┘
```

- **Size ~430×260**, centered via `custom_minimum_size` (never `size`
  in `_ready`).
- **Banner:** ~96px wide, full body height, vertical navy→black
  gradient (adapt `upgrade_item.gd::_draw_horizontal_gradient`), with
  "ScrabbleRabble 95" in white w95fa rotated -90°, reading
  bottom-to-top. No image assets.
- **Title bar:** text "Upgrade Wizard"; only the `X` decoration button
  (Min/Max removed — period-correct for wizards). `X` = Skip.
- **Buttons:** `< Back` permanently `disabled = true`,
  `focus_mode = NONE` (authentic first-page InstallShield, can never
  trap focus). `Next >` is the **default button** — Enter anywhere in
  the dialog activates it — and commits the selected card. `Cancel` =
  Skip, same handler as `X`.

### Offer cards

Each card (evolved `upgrade_item.gd`, keeps `class_name UpgradeItem`):

```
┌─────────────┐
│   ┌─────┐   │  ← 56×56 tile preview: modifier gradient body
│   │  E  │   │    (blue 2x / green 3x), white letter (24px) and
│   │    1│   │    point value (9px) — exactly what the tile will
│   └─────┘   │    look like in the rack (absorb letter_item.gd's
│     ×2      │    face drawing)
│  12 in bag  │  ← LETTER_DISTRIBUTION count, small gray text
└─────────────┘
```

- **Radio-select semantics:** click or arrow-focus *selects* (yellow
  border = selection); it does NOT commit. First card pre-selected on
  open so `Next >` always has a target. **Double-click commits**
  directly (wizard-era shortcut).
- **Focus border drawn tight around the tile-preview rect**
  (`body_rect.grow(2)`), not the control rect — this is the cursor
  alignment fix.
- Signals: `pick_requested` is replaced by `selected(index)` +
  `confirmed(index)` (double-click).

### Caption copy

- Card focused/selected: `Every {LETTER} tile scores {double|triple}
  points for the rest of the run.`
- Cancel/Skip focused: `Install no upgrade this round.`

## Modal input blocking

A **full-screen invisible blocker** — `Control`, full-rect,
`mouse_filter = STOP`, no tint (Win95 didn't dim) — added to the
upgrade CanvasLayer (layer 50) **under** the dialog. Every mouse event
aimed at board/rack/HUD dies there. Keyboard is already gated by
`main.gd::_unhandled_input` (`is_upgrading`) plus focus containment
inside the dialog.

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
