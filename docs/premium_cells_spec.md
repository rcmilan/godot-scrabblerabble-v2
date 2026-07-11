# Premium Board Cells (DL/TL/DW/TW) — Design Spec

Implements issue #13.

## Summary

Scrabble-style premium squares baked into board **positions** — double/triple
**letter** (DL/TL) and double/triple **word** (DW/TW) cells. Unlike tile
modifiers (which travel with a tile), premiums are positional: the bonus
applies to whatever tile sits on that cell. Layout is **randomized per round**
and **rerolled on round win**; all four tiers ship in v1.

Scoring order, deterministic and identical in live and sim:

> **tile modifier (2×/3×) → cell letter premium (DL/TL) → sum letters →
> `WORD_BONUS_MULTIPLIER` (2×) → cell word premiums (DW/TW)**

Minimal diff: five existing scripts plus two docs change, no new files.

## Background — why it fits this way

- `main.gd::_score_word()` already iterates each word letter-by-letter with
  the `BoardCell` node in hand (via `_collect_scoring_words()`'s `cells`
  array), so a per-cell premium needs no plumbing — read `cell.premium` right
  where `cell.get_modifier()` is read today.
- The **score==highlight invariant holds structurally**: premiums change
  points, not word membership. Both scoring and the rainbow glow still flow
  from `_collect_scoring_words()`; no highlight code changes.
- `_board_runs()` only emits letter-bearing cells, so premiums on empty cells
  are inert by construction — no guard needed.
- Seed-determinism only matters in the sim: `GameCore` threads a seeded
  `rng`; the live game may use the global RNG.

## 1. Constants

`scripts/game_data.gd` (next to `MOD_*`):

```gdscript
const PREM_NONE: String = ""
const PREM_DL: String = "dl"
const PREM_TL: String = "tl"
const PREM_DW: String = "dw"
const PREM_TW: String = "tw"
const PREMIUM_COUNTS := {PREM_DL: 3, PREM_TL: 2, PREM_DW: 2, PREM_TW: 1}
```

8 of 64 cells (~12.5%) — a first guess; tune via the simulator, mirroring
both files. Mirror all six constants in `scripts/sim/game_core.gd` under
`MOD_3X`.

## 2. State + layout generation

**`scripts/board_cell.gd`** — new field `var premium: String = ""` (after
`locked_modifier`) plus `set_premium(p)` that assigns and `queue_redraw()`s.
`clear_pending()` / `lock_pending()` / `clear_all()` do **not** touch it, so
persistence through tile lock and the board wipe is free; the reroll is an
explicit call.

**`scripts/board.gd`** — new `reroll_premiums()`: zero every cell's premium,
collect the 64 positions, `Array.shuffle()` (global RNG is fine live), assign
`GameData.PREMIUM_COUNTS` from the front — no overlaps by construction. Log
`[Board] premiums rerolled — 8 cells`.

**`scripts/main.gd`** — two call sites: `_ready()` (scene reload on restart
covers the fresh-run case) and the round-won handler immediately after
`board.clear_all()`.

**`scripts/sim/game_core.gd`** — parallel `board_premiums[x][y]` next to
`board_modifiers`; sized/zeroed in `_init_board()` and `clear_board()`, both
ending with a call to new `_reroll_premiums()` (`clear_board()` is invoked by
`_advance_round`, matching the live round-win reroll). `_reroll_premiums()`
uses a hand-rolled Fisher–Yates driven by `self.rng` — `Array.shuffle()` uses
the global RNG and would break seed determinism.

## 3. Scoring — mirror pair, change both

`scripts/main.gd::_score_word()`, inside the per-letter loop after the
existing tile-modifier branch:

```gdscript
if cell.premium == GameData.PREM_DL:
    letter_pts *= 2
elif cell.premium == GameData.PREM_TL:
    letter_pts *= 3
elif cell.premium == GameData.PREM_DW:
    word_mult *= 2
elif cell.premium == GameData.PREM_TW:
    word_mult *= 3
```

with `var word_mult := 1` declared at the top and `word_points *= word_mult`
applied after the existing `word_points *= WORD_BONUS_MULTIPLIER`.

`scripts/sim/game_core.gd::_score_word_sim()` gets the identical change,
reading `board_premiums[cell_pos.x][cell_pos.y]` and the `PREM_*` constants.

Because the whole-board model scores every valid substring, a DW/TW under a
shared letter multiplies **every word containing that cell** (e.g. TW on the
A of `CAT` triples both `AT` and `CAT`) — consistent with how nested words
already double-count letters by design.

Optional: extend `main.gd::_get_modifiers_str()` to append `dl@i` / `tw@i`
so `[Turn]` logs show premium contributions.

## 4. Rendering — `scripts/board_cell.gd::_draw`

**Style constraints** (from `themes/win95.tres`, `board_cell.gd`, and the
project's chrome-vs-effects split): the board is Win95 *chrome* — flat
system-palette colors, hard pixels (`anti_aliasing = false` everywhere in the
theme), procedural bevels in `_draw`. Neon/CRT effects are reserved for
overlays and the score label. Premium marking is therefore **flat chrome, no
gradients, no glow** — gradients are already the visual signature of *tile*
modifiers (navy→sky 2×, green 3× in `C_MOD*_GRADIENT_*`), and premiums must
read as a different mechanic.

Colors — Win95 16-color system palette only, avoiding the modifier
blues/greens, the tile cream `#FFFFC0`, and the cursor cyan `#00FFFF`.
Dark system color + white label, exactly the title-bar idiom
(white-on-navy `SB_TitleBar`) and the modifier-label whitening
(`C_LABEL_MOD`) already in use:

```gdscript
const C_PREM_COLORS := {          # letter = cool, word = warm
    "dl": Color("#008080"),      # teal
    "tl": Color("#800080"),      # purple
    "dw": Color("#808000"),      # olive
    "tw": Color("#800000"),      # maroon
}
const C_PREM_LABEL := Color(1, 1, 1, 1)   # white, as on the title bar
```

1. **Empty premium cell** — in the empty-cell branch, fill with
   `C_PREM_COLORS[premium]` instead of `C_BG_EMPTY` `#C0C0C0`; the sunken
   bevel (`C_OUTER_*`/`C_INNER_*`) draws over it unchanged, so the cell still
   reads as part of the board grid. Then `draw_string` the centered label
   `premium.to_upper()` ("DL"/"TL"/"DW"/"TW") in `C_PREM_LABEL`, size 12,
   via `get_theme_default_font()` (w95fa through the project theme — the
   only font, per CLAUDE.md). The cursor caret sits at the bottom edge; no
   conflict.
2. **Occupied premium cell** — after the raised bevel, a small filled corner
   triangle badge top-right (cells are 56×56):
   `draw_colored_polygon([Vector2(w-13, 3), Vector2(w-3, 3), Vector2(w-3, 13)], C_PREM_COLORS[premium])`
   — `draw_colored_polygon` is not antialiased, matching the hard-pixel
   look. Coexists with the tile-modifier gradient (badge overlays it), the
   cyan focus ring (insets 0/2), and the rainbow highlight frame (2px at
   inset 3).

No Label-node or `_sync_label_color` changes, no theme edits (`win95.tres`
stays untouched — a per-cell premium fill can't be a theme variation, same
reason the modifier gradients live in `_draw`), and no shader work.

## 5. Tests — `scripts/sim/tests/test_game_core.gd`

`GameCore.new()` now rolls premiums, so hand-computed score tests need a
clean board: add helper `_zero_premiums(core)` and call it after
`GameCore.new(...)` in **TC4, TC11, TC12, TC13**.

New tests (auto-discovered; expectations hand-computed against
`data/words.txt`, keeping the existing `is_valid_word` guard style):

| Test | Setup | Expected |
|------|-------|----------|
| TC15 — TL letter math | `CAT` at (0,0)–(2,0), `PREM_TL` on C | AT=(1+1)·2=4, CAT=(3·3+1+1)·2=22 → **26** |
| TC16 — TW word math | `PREM_TW` on the A (in both words) | AT=(1+1)·2·3=12, CAT=(3+1+1)·2·3=30 → **42** |
| TC17 — stacking MOD_2X × DL | both on C | C=3·2·2=12; AT=4, CAT=(12+1+1)·2=28 → **32** |
| TC18 — reroll determinism | two `GameCore.new(same_seed)` | identical `board_premiums`; non-NONE count == 8 |
| TC19 — persistence + reroll | place tile on premium cell, then `clear_board()` | premiums unchanged by placement; after clear, layout equals a same-seed twin's (never assert it *differs* from the old — layouts can rarely coincide) |

## 6. Docs

- **CLAUDE.md** — update the modifier-order bullet in "Scoring & word
  highlight" to the full chain; add a short note under "Tile modifiers"
  naming the mirror pair (`board.gd::reroll_premiums` ↔
  `game_core.gd::_reroll_premiums`) and tests TC15–TC19.
- **`scripts/sim/README.md`** — mirror the scoring-order sentence.

## Sequencing

1. Constants (`game_data.gd` + `game_core.gd`)
2. Sim: `board_premiums`, `_reroll_premiums`, `_score_word_sim`, init/clear hooks
3. Tests: helper + zeroing of TC4/TC11/TC12/TC13 + TC15–TC19 (validates math before UI)
4. Live: cell field/setter, `board.reroll_premiums`, `main.gd` call sites, `_score_word`
5. Rendering in `board_cell.gd::_draw`
6. CLAUDE.md + sim README

## Verification

- `godot --headless --path . --script res://scripts/sim/tests/run_tests.gd` —
  all existing TC/TSM tests plus TC15–TC19 pass. If Godot isn't runnable in
  the agent environment, hand-trace TC15–TC19 and state plainly that tests
  were not executed.
- Launch the game: premium cells labeled when empty, corner badge when
  occupied; place a word across a DL/TW and confirm the `[Turn]` log matches
  hand math; win a round and confirm the layout rerolls.

## Risks / notes

- Extra `rng` draws in `_init_board`/`clear_board` shift per-seed sim
  outcomes vs. historical CSVs. Determinism tests still pass (both sides of a
  same-seed comparison shift identically) — but don't compare new sim results
  against pre-change runs.
- Strategies stay premium-blind in v1 — they under-optimize but work. Add
  premium awareness when tuning `PREMIUM_COUNTS` via the sim.
- Premiums inflate scores further, making the already-open
  `INITIAL_TARGET_SCORE` retuning follow-up more pressing. Out of scope here.

## Acceptance criteria (from issue #13)

- [ ] Premium cells visibly marked when empty and when occupied.
- [ ] Scoring order with tile modifiers + word bonus is deterministic and documented.
- [ ] Layout generation is seed-deterministic in the sim.
- [ ] Score==highlight invariant holds.
- [ ] Sim parity tests pass / hand-verified.
