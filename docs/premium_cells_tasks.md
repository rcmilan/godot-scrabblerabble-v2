# Premium Board Cells (DL/TL/DW/TW) — Implementation Tasks

Slices `docs/premium_cells_spec.md` into small, ordered, vertical
deliverables. Implement **in order**. Each task compiles on its own, keeps
the game playable, and every sim test stays green at every boundary. Do not
start a task until the previous one is done.

**Conventions (from `CLAUDE.md`):** snake_case; structured logging with
subsystem prefixes (`[Board]`, `[Turn]`, `[GameCore]`); no comments that
restate code; edit existing files only — no new files. Targets Godot 4.6.
**Sim parity is mandatory:** every gameplay change lands in
`scripts/sim/game_core.gd` in the same task as (or before) its live twin —
Tasks 1–2 are sim-only and come first so the math is proven headless before
any UI work.

Files touched: `scripts/sim/game_core.gd`,
`scripts/sim/tests/test_game_core.gd`, `scripts/game_data.gd`,
`scripts/board_cell.gd`, `scripts/board.gd`, `scripts/main.gd`,
`CLAUDE.md`, `scripts/sim/README.md`.

---

## Task 1 — Sim: premium layer + deterministic reroll

**Goal:** `GameCore` owns a `board_premiums[x][y]` layer, seeded from its
own rng, rerolled on init and on board wipe. No scoring change yet.

### 1a. `scripts/sim/game_core.gd` — constants

Under `MOD_3X` (~line 22) add `PREM_NONE=""`, `PREM_DL="dl"`,
`PREM_TL="tl"`, `PREM_DW="dw"`, `PREM_TW="tw"`, and
`const PREMIUM_COUNTS := {PREM_DL: 3, PREM_TL: 2, PREM_DW: 2, PREM_TW: 1}`
(8 of 64 cells; tuning knob, mirror any change into `game_data.gd` later).

### 1b. `scripts/sim/game_core.gd` — state + reroll

- New `var board_premiums: Array = []` next to `board_modifiers` (~line 68).
- `_init_board()` (~101-113): size/zero `board_premiums` alongside the other
  arrays, then call `_reroll_premiums()` last.
- `clear_board()` (~343-347): zero premiums, then `_reroll_premiums()` last
  (`clear_board()` runs on round win via `_advance_round` — matches the live
  reroll-on-win semantics).
- New `_reroll_premiums()`: reset all to `PREM_NONE`, build the 64
  `Vector2i` positions, shuffle with a hand-rolled Fisher–Yates driven by
  `self.rng` (**not** `Array.shuffle()` — that uses the global RNG and
  breaks seed determinism), assign `PREMIUM_COUNTS` from the front.
  Spec §2 has the exact function.

### 1c. `scripts/sim/tests/test_game_core.gd` — determinism test

- **TC18** — two `GameCore.new(same_seed, ...)` produce identical
  `board_premiums`; non-`PREM_NONE` cell count == 8.

### Verify
- `godot --headless --path . --script res://scripts/sim/tests/run_tests.gd`
  → all existing tests + TC18 green. (Existing score tests still pass —
  premiums exist but don't score yet.)

### State after Task 1
Sim boards carry a seed-deterministic premium layout; scoring and the live
game are unchanged.

---

## Task 2 — Sim: premium scoring + hand-computed tests

**Goal:** `_score_word_sim` applies the full multiplier chain:
tile mod → DL/TL → sum → `WORD_BONUS_MULTIPLIER` → DW/TW.

### 2a. `scripts/sim/game_core.gd::_score_word_sim` (~306-319)

Declare `var word_mult := 1` at the top. Inside the per-letter loop, after
the existing `MOD_2X`/`MOD_3X` branch, read
`board_premiums[cell_pos.x][cell_pos.y]`: `PREM_DL` → `letter_pts *= 2`,
`PREM_TL` → `*= 3`, `PREM_DW` → `word_mult *= 2`, `PREM_TW` →
`word_mult *= 3`. After `word_points *= WORD_BONUS_MULTIPLIER`, apply
`word_points *= word_mult`. Spec §3 has the exact snippet.

### 2b. `scripts/sim/tests/test_game_core.gd` — isolate + new cases

- Helper `_zero_premiums(core)` (loop the array, set `PREM_NONE`); call it
  right after `GameCore.new(...)` in **TC4, TC11, TC12, TC13** so their
  hand-computed sums stay valid against the now-random layout.
- **TC15** — TL letter math: `CAT` at (0,0)–(2,0), `PREM_TL` on C →
  AT=4, CAT=22, total **26**.
- **TC16** — TW word math: `PREM_TW` on the A (shared by both words) →
  AT=12, CAT=30, total **42**.
- **TC17** — stacking `MOD_2X` × `PREM_DL` on C → AT=4, CAT=28, total **32**.
- **TC19** — persistence + reroll: `place_pending_tile` onto a premium cell
  → `board_premiums` unchanged; `clear_board()` → letters/modifiers zeroed,
  layout equals a same-seed twin's after identical calls (never assert the
  new layout *differs* from the old — they can rarely coincide).

### Verify
- `run_tests.gd` → all green, including TC15–TC19. If Godot can't run in
  this environment, hand-trace against `data/words.txt` and say so plainly.

### State after Task 2
The sim fully models premium cells with proven math. Live game untouched.

---

## Task 3 — Live: premium state + Win95 rendering (visible, inert)

**Goal:** the real board shows premium cells — colored + labeled when
empty, corner badge when occupied — persisting through tile lock and
rerolling on round win. They don't score yet.

### 3a. `scripts/game_data.gd` — constants

Mirror the six `PREM_*` constants + `PREMIUM_COUNTS` from Task 1a next to
`MOD_*`. Values must stay identical to `game_core.gd` (sim-parity rule).

### 3b. `scripts/board_cell.gd` — field + setter

`var premium: String = ""` after `locked_modifier`;
`set_premium(p)` assigns and `queue_redraw()`s. Do **not** touch premium in
`clear_pending()` / `lock_pending()` / `clear_all()` — persistence through
lock and wipe is by omission; reroll is explicit.

### 3c. `scripts/board.gd` — layout generation

New `reroll_premiums()`: zero every cell's premium, shuffle the 64
positions (`Array.shuffle()`; global RNG is fine live), assign
`GameData.PREMIUM_COUNTS` from the front. Log
`print("[Board] premiums rerolled — %d cells" % i)`.

### 3d. `scripts/main.gd` — call sites

`board.reroll_premiums()` in `_ready()` (scene reload covers restart) and in
the round-won handler immediately after `board.clear_all()`.

### 3e. `scripts/board_cell.gd::_draw` — Win95 chrome rendering

Spec §4 has the full constraints. Flat 16-color system palette, no
gradients/glow (those are the *tile-modifier* signature):

```gdscript
const C_PREM_COLORS := {"dl": Color("#008080"), "tl": Color("#800080"),
                        "dw": Color("#808000"), "tw": Color("#800000")}
const C_PREM_LABEL := Color(1, 1, 1, 1)
```

- **Empty premium cell:** fill with `C_PREM_COLORS[premium]` instead of
  `C_BG_EMPTY`; sunken bevel unchanged on top; centered
  `premium.to_upper()` label, size 12, `get_theme_default_font()` (w95fa),
  `C_PREM_LABEL` white.
- **Occupied premium cell:** after the raised bevel, corner triangle badge
  top-right: `draw_colored_polygon([Vector2(w-13, 3), Vector2(w-3, 3),
  Vector2(w-3, 13)], C_PREM_COLORS[premium])`. Coexists with modifier
  gradient, cyan focus ring (insets 0/2), rainbow frame (2px at inset 3).

No theme edits, no Label-node / `_sync_label_color` changes.

### Verify
- Run the game: 8 colored, labeled premium cells appear; place a tile on
  one → badge shows, letter renders normally; lock it (PLAY) → badge stays;
  win a round → board wipes and the layout rerolls (`[Board]` log).
  Cursor ring and rainbow highlight still render on premium cells.
- `run_tests.gd` → still green (sim untouched by this task).

### State after Task 3
Premium cells are fully visible and persistent in the live game but worth
nothing — scoring still matches the sim's pre-premium behavior only because
live `_score_word` ignores `premium` (fixed next task).

---

## Task 4 — Live: premium scoring + docs

**Goal:** live scoring matches the sim exactly; docs record the invariants.

### 4a. `scripts/main.gd::_score_word` (~374-387)

Identical change to Task 2a, reading `cell.premium` against the
`GameData.PREM_*` constants: `word_mult` accumulator, DL/TL on
`letter_pts`, `word_points *= word_mult` after the word bonus.
Score==highlight holds untouched — premiums change points, not word
membership; both flow from `_collect_scoring_words()`.

### 4b. `scripts/main.gd::_get_modifiers_str` (~389-398) — optional

Append `dl@i` / `tw@i` etc. so `[Turn]` logs show premium contributions.
Skip if the diff budget is tight.

### 4c. Docs

- **CLAUDE.md** — update the modifier-order bullet in "Scoring & word
  highlight" to: tile mod (2×/3×) → cell letter premium (DL/TL) → word
  bonus → cell word premiums (DW/TW), same order live and sim. Add a short
  note under "Tile modifiers" naming the mirror pair
  (`board.gd::reroll_premiums` ↔ `game_core.gd::_reroll_premiums`) and
  tests TC15–TC19.
- **`scripts/sim/README.md`** — mirror the scoring-order sentence.

### Verify
- Run the game: place a word across a DL and a TW; the `[Turn]` word log
  must match hand math (letter mod → DL/TL → ×2 word bonus → DW/TW).
  Confirm a glowing word's score changes when it crosses a premium — and
  that nothing glows that doesn't score.
- `run_tests.gd` → all green (TC1–TC19).

### State after Task 4
Full feature: visible, persistent, per-round-random premium cells that
score identically in the live game and the simulator.

---

## Done criteria (all tasks)

- Premium cells visibly marked when empty (color + DL/TL/DW/TW label) and
  when occupied (corner badge). (Issue #13 AC 1)
- Scoring order with tile modifiers + word bonus is deterministic and
  documented in CLAUDE.md. (AC 2)
- Layout is seed-deterministic in the sim (TC18) and rerolls on round win
  in both sim (`clear_board`) and live (`board.clear_all()` handler). (AC 3)
- Score==highlight invariant holds — no highlight code changed. (AC 4)
- `run_tests.gd` green including TC15–TC19; `game_core.gd` and the live
  game share identical constants and scoring math. (AC 5)
- Follow-up (out of scope): tune `PREMIUM_COUNTS` / `INITIAL_TARGET_SCORE`
  via the simulator; teach strategies to see premiums.
