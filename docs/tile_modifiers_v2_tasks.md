# Tile Modifiers v2 — Implementation Tasks

Slices `docs/tile_modifiers_v2_spec.md` into ordered, vertical deliverables.
Implement **in order**. Each task compiles alone, keeps the game playable, and
leaves `run_tests.gd` green at every boundary. Do not start a task until the
previous one is done.

**Conventions (CLAUDE.md):** snake_case; structured logging with subsystem
prefixes (`[Turn]`, `[Wild]`, `[UpgradeWizard]`, `[GameCore]`); no comments
that restate code; **no new files** — every path below already exists. Targets
Godot 4.6.

**Sim parity is mandatory.** Tasks 1–3 are sim-only and come first, so the
math is proven headless before any UI work. Every constant added to
`game_core.gd` must land byte-identically in `game_data.gd`.

**Run the tests.** Godot lives at
`C:\Users\suporte\Documents\Godot_v4.6.1-stable_mono_win64\Godot_v4.6.1-stable_mono_win64\Godot_v4.6.1-stable_mono_win64_console.exe`:

```
<godot> --headless --path . --script res://scripts/sim/tests/run_tests.gd
```

Files touched: `scripts/sim/game_core.gd`,
`scripts/sim/tests/test_game_core.gd`, `scripts/game_data.gd`,
`scripts/main.gd`, `scripts/tile.gd`, `scripts/board_cell.gd`,
`scripts/rack.gd`, `scripts/upgrade_dialog.gd`, `scripts/upgrade_item.gd`,
`CLAUDE.md`, `scripts/sim/README.md`.

---

## Task 1 — Sim: word-multiplier scoring

**Goal:** `MOD_WORD_2X` / `MOD_WORD_3X` multiply the whole run. Nothing grants
them yet; tests inject them directly into `board_modifiers`.

### 1a. `scripts/sim/game_core.gd` — constants

Under `MOD_3X` (line 22) add `MOD_WORD_2X = "w2x"` and `MOD_WORD_3X = "w3x"`.

### 1b. `scripts/sim/game_core.gd::_score_word_sim` (line 343)

`word_mult` already exists for DW/TW. Extend the tile-modifier `if/elif` chain
inside the per-letter loop with two branches: `MOD_WORD_2X` → `word_mult *= 2`,
`MOD_WORD_3X` → `word_mult *= 3`. **Do not touch `letter_pts` for these** — a
word-mult tile contributes its plain letter value. Spec §2 has the snippet.

Order is load-bearing and already correct: the existing
`word_points *= WORD_BONUS_MULTIPLIER` then `word_points *= word_mult`
sequence yields spec steps 6→7→8 with no reordering.

### 1c. `scripts/sim/tests/test_game_core.gd` — new cases

Call `_zero_premiums(core)` right after `GameCore.new(...)` in each (the random
premium layer would corrupt hand-computed sums).

- **TC20** — `CAT` at (0,0)–(2,0), `MOD_WORD_2X` on the `C`.
  Base `CAT` = 3+1+1 = 5. Run scores `AT` and `CAT`:
  `AT` = (1+1)·2 = **4** (no word-mult tile in `AT`).
  `CAT` = 5·2·2 = **20**. Total **24**.
- **TC21** — stacking: `MOD_WORD_2X` on `C` **and** on `T`.
  `AT` = (1+1)·2·2 = **8** (the `T` mult applies; `AT` contains it).
  `CAT` = 5·2·2·2 = **40**. Total **48**.

### Verify
`run_tests.gd` → all existing tests plus TC20–TC21 green.

### State after Task 1
The sim scores word multipliers. No acquisition path, no live change.

---

## Task 2 — Sim: wildcard scoring + resolution

**Goal:** `MOD_WILD` scores 0 for its slot, and `_resolve_wildcards()` picks
each blank's letter to maximize the board score.

### 2a. `scripts/sim/game_core.gd` — constant

`MOD_WILD = "wild"` next to the Task 1a constants.

### 2b. `scripts/sim/game_core.gd::_score_word_sim`

First branch of the tile-modifier chain: `if mod == MOD_WILD: letter_pts = 0`.
It must come **before** the `MOD_2X` / `MOD_3X` branches — a blank is worth
nothing regardless of what cell it sits on (spec §2 step 2).

### 2c. `scripts/sim/game_core.gd::_resolve_wildcards` — new function

Iterate every board cell in scan order (`for x in BOARD_SIZE: for y in
BOARD_SIZE`) whose `board_modifiers[x][y] == MOD_WILD`. For each, try all 26
letters: write the letter into `board[x][y]`, call
`_calculate_turn_score([])`, keep the letter with the highest score. Ties →
the alphabetically first (i.e. only replace the best on a strict `>`). Leave
the winning letter written to the board.

Deterministic; no RNG. Carry the `ponytail:` comment from spec §3c naming the
greedy-per-wild ceiling.

### 2d. `scripts/sim/game_core.gd::end_turn` (line 265)

Call `_resolve_wildcards()` on the first line, before `_calculate_turn_score`.

### 2e. `scripts/sim/tests/test_game_core.gd` — new cases

- **TC22** — wildcard scores 0 but completes the word. `C` and `T` at (0,0)
  and (2,0); a `MOD_WILD` tile at (1,0) resolved to `A`. `AT` = (0+1)·2 = **2**.
  `CAT` = (3+0+1)·2 = **8**. Total **10** (vs. 24 with a real `A`).
- **TC24** — `_resolve_wildcards` maximizes: place `C` and `T` around a wild at
  (1,0) and assert it resolves to `A` (`CAT` scores; `CBT` etc. do not), that
  the result is stable across two identical cores, and that a wild with no
  neighbours resolves to `A` (all letters score 0 → alphabetical tie-break).

### Verify
`run_tests.gd` → TC20–TC22, TC24 green; every pre-existing test still green.

### State after Task 2
The sim fully models both new modifiers. Still no way to obtain one.

---

## Task 3 — Sim: acquisition via the upgrade wizard

**Goal:** the wizard rolls the new modifiers; a wildcard pick feeds
`modifier_build` and the rack guarantees it every refill.

### 3a. `scripts/sim/game_core.gd::_generate_upgrade_offers` (line 399)

Replace `var mod: String = MOD_3X if rng.randi() % 3 == 0 else MOD_2X` with a
weighted roll over `MODIFIER_WEIGHTS` (spec §4b), using `rng` only.

A `MOD_WILD` roll emits `{"letter": "?", "modifier": MOD_WILD}` and **must not
consume a letter** from the pool. Guard: **at most one** wild offer per wizard;
re-roll into a letter modifier if a wild was already emitted.

### 3b. `scripts/sim/game_core.gd::_offer_value` (line 425)

Rewrite to marginal-points-gained per spec §4c: add `TYPICAL_WORD_POINTS = 12`
and `WILD_OFFER_VALUE = 60` constants, branch on `MOD_WILD` → flat, word-mults
→ `dist × TYPICAL_WORD_POINTS × (mult - 1)`, letter-mods → `dist × points ×
(mult - 1)`. This intentionally re-ranks existing letter mods.

### 3c. `scripts/sim/game_core.gd::end_turn` — auto-pick branch

The existing auto-pick writes `letter_modifiers[best["letter"]] =
best["modifier"]`. A `MOD_WILD` winner must instead do
`modifier_build[MOD_WILD] = modifier_build.get(MOD_WILD, 0) + 1`.
Log `[GameCore] upgrade auto-pick — wildcard (build %d)`.

`_ensure_modifier_count_in_rack` already honours any modifier key, so the rack
guarantee needs **no change**.

### 3d. `scripts/sim/tests/test_game_core.gd`

- **TSM12** — `GameCore.new(seed, {MOD_WILD: 2})` → exactly 2 wild tiles in the
  rack, and still 2 after `refill_rack()` on a later turn.
- **TSM13** — a `MOD_WILD` offer routed through the auto-pick increments
  `modifier_build[MOD_WILD]` and leaves `letter_modifiers` untouched.
- **TSM10 (existing)** — widen the assertion: `letter_modifiers` values may now
  be any of `MOD_2X`, `MOD_3X`, `MOD_WORD_2X`, `MOD_WORD_3X` (never `MOD_WILD`,
  which lives in `modifier_build`). Update, do **not** relax.

### Verify
`run_tests.gd` → fully green. Then a smoke batch:
`<godot> --headless --path . --script res://scripts/sim/sim_runner.gd -- --runs 5 --strategies word_search --seed 42`
— completes, and `[GameCore] upgrade auto-pick` lines show the new modifiers.

### State after Task 3
The simulator plays the full feature end to end. Live game untouched.

---

## Task 4 — Live: constants, scoring, wildcard resolution

**Goal:** live scoring matches the sim exactly. Mirror of Tasks 1–3's logic.

### 4a. `scripts/game_data.gd` — constants

Mirror `MOD_WORD_2X`, `MOD_WORD_3X`, `MOD_WILD` next to `MOD_3X` (line 6).
Byte-identical values to `game_core.gd`.

### 4b. `scripts/main.gd::_score_word` (line 375)

The same branch chain as Task 1b + 2b, reading `cell.get_modifier()` against
the `GameData.MOD_*` constants. `word_mult` already exists.

### 4c. `scripts/main.gd::_resolve_wildcards` — new function

Mirror of Task 2c against live nodes: scan `board.cells[x][y]` in the same
(x, y) order, skip cells whose `current_tile == null` (**locked wilds are
frozen — never re-resolve**), try 26 letters via `cell.current_tile.set_letter`,
score with `_calculate_turn_score()`, keep the best (strict `>` for the
alphabetical tie-break).

Call it on the **first line of `_update_hud()`**, before `_refresh_highlights()`.
`_update_hud` already runs after every board/rack mutation, so the blank
resolves live and the rainbow preview stays truthful. Log the resolution once
per change: `print("[Wild] resolved %s -> %s" % [cell.grid_pos, letter])`.

### 4d. `scripts/main.gd::_get_modifiers_str` (line 400)

Append `w2x@i` / `w3x@i` / `wild@i` tags so `[Turn]` logs show the new
contributions.

### Verify
`<godot> --headless --path . -- --autoplay=word_search` runs to a clean exit 0.
Hand-check one `[Turn] word ... = N (modifiers: ...)` line against spec §2.

### State after Task 4
Live and sim score identically. Nothing grants the new modifiers live yet.

---

## Task 5 — Live: wizard offers the new modifiers

**Goal:** the player can actually acquire word-mults and wildcards.

### 5a. `scripts/main.gd::_generate_upgrade_offers` (line 479)

Mirror Task 3a: weighted roll, at most one wild offer, wild offers don't
consume a letter. Uses `randi()` (live may use the global RNG).

### 5b. `scripts/main.gd::_offer_value` (line 516)

Mirror Task 3b exactly.

### 5c. `scripts/main.gd::_show_upgrade_dialog` — pick handler (line 462)

The `upgrade_picked` handler currently always calls
`RunState.set_letter_modifier(...)`. Branch: a `MOD_WILD` offer calls
`RunState.add_to_build(GameData.MOD_WILD)` instead. `add_to_build` already
exists in `run_state.gd` (line 104) and has had **no live caller until now** —
this is it. `rack.refill()` on the next line already re-applies the build.

### 5d. `scripts/rack.gd::find_tile_with_letter` (line 99)

Skip tiles whose `modifier == GameData.MOD_WILD`, so keyboard-placing `E`
never silently consumes the blank.

### Verify
`--autoplay=word_search` to round 4+ (the first upgrade). `[UpgradeWizard]`
logs show the new modifier types; a wildcard pick emits
`[RunState] build += wild`, and the next refill's rack contains a wild tile.

### State after Task 5
The feature is playable. It is not yet *visible* — new modifiers still render
as plain tiles.

---

## Task 6 — Live: visuals

**Goal:** the new modifiers are legible on the rack, the board, and in the
wizard.

### 6a. `scripts/tile.gd` — gradients + blank face

Add the three colour constants from spec §5 next to `C_MOD3X_*` (line 24).
In `_draw` (line 67), extend the modifier chain: `MOD_WORD_2X` → purple
gradient, `MOD_WORD_3X` → amber gradient, `MOD_WILD` → flat `C_WILD_BODY`.
In `_refresh_visual` (line 57): a `MOD_WILD` tile shows `letter_label.text =
"?"` and `point_label.text = "0"` with the normal navy/grey label colours;
word-mult tiles use `C_LABEL_MOD` (white) like the existing modified tiles.

### 6b. `scripts/board_cell.gd` — same gradients

Mirror the constants and extend the `_draw` background chain (line 112) and
`_sync_label_color` (line 177) for the two word-mult modifiers. A placed
wildcard shows its **resolved letter**, not `?` — `label.text` is already set
from `tile.letter` by `place_tile`, so this needs no change, but confirm a
locked wild still renders its letter.

### 6c. `scripts/upgrade_item.gd::_draw` — bag count

`GameData.LETTER_DISTRIBUTION.get(letter, 0)` returns 0 for `"?"`. Skip the
`"N in bag"` line entirely when `modifier == GameData.MOD_WILD`.

### 6d. `scripts/upgrade_dialog.gd::_update_caption` (line 120)

The hardcoded `"double" if modifier == MOD_2X else "triple"` ternary needs one
line per new type:
- `MOD_WORD_2X` / `MOD_WORD_3X` → `"Every %s tile doubles/triples the whole word."`
- `MOD_WILD` → `"A blank tile. Plays as any letter, scores nothing."`

### Verify
Launch the game. Rack and board render all five modifier types distinctly; the
wizard cards match the rack tiles (they share `tile.gd`); a wildcard card shows
`?` with no bag count.

### State after Task 6
Feature complete and legible. Balance is untuned.

---

## Task 7 — Docs

### 7a. `CLAUDE.md`

- **"Scoring & word highlight"** — extend the scoring-order bullet to the full
  eight-step chain from spec §2 (wild-zero → tile letter mod → cell letter
  premium → sum → word bonus → cell word premium → tile word mod).
- **"Tile modifiers"** — document the five modifier types, the binary
  never-stack rule, that word-mults and DW/TW premiums multiply into one
  accumulator, and that wildcards live in `modifier_build` while letter-bound
  modifiers live in `letter_modifiers`.
- Name the new mirror pair (`main.gd::_resolve_wildcards` ↔
  `game_core.gd::_resolve_wildcards`) and tests TC20–TC25 / TSM12–TSM13.

### 7b. `scripts/sim/README.md`

Mirror the scoring-order sentence in the **Modifiers** section. Note under
**Upgrade Wizard Parity** that the offer roll is now weighted
(`MODIFIER_WEIGHTS`) and that `_offer_value` uses marginal points `(mult - 1)`.

---

## Task 8 — Rebalance

**Goal:** restore the pre-feature survival curve. Method is fixed by CLAUDE.md
("Retuning is measured, never guessed") — do not guess a number.

1. **Baseline.** On `main`, run all 8 strategies × 200 runs, seed 42. Record
   mean rounds per strategy.
2. **Measure inflation.** Same batch on this branch. The ratio of mean scores
   is the inflation factor.
3. **Sweep.** Scale **`INITIAL_TARGET_SCORE`** only — never `ENDLESS_GROWTH`
   (it compounds and warps early vs. late rounds). Try candidates, 200 runs ×
   the 4 competent strategies, and pick the value whose mean-rounds vector is
   closest to the `main` baseline.
4. **Mirror** the winner into **both** `run_state.gd` and `game_core.gd`.
5. **Scale `DIFFICULTY_TARGETS`** by the measured inflation factor — the
   difficulty modes are live-only and not simulated (see
   `scripts/sim/README.md`), so the factor transfers from the Endless curve.
6. **Recompute the pinned tests:** `TC1` (constants), `TC6` (target curve),
   `TC7` (post-advance target) hand-pin these values and **will** fail.

### Verify
`run_tests.gd` fully green; the final 200-run batch lands every strategy within
~0.5 rounds of its `main` baseline.

---

## Done criteria (issue #12)

- Word multipliers score correctly and stack multiplicatively (TC20, TC21).
- Wildcards complete dictionary words and score 0 for their slot (TC22, TC24).
- Word-mults multiply with DW/TW premium cells (TC23).
- Score == highlight: no highlight code touched; a wild's chosen letter is a
  real board letter, so it glows iff it scores.
- `run_tests.gd` green; `game_core.gd` and the live game share identical
  constants and scoring math.
- Frozen tiles: **cut from v1** (spec §0) — the issue's AC is incoherent with
  this game's lock model.
- Follow-ups (out of scope): teach strategies to see modifiers (they are
  modifier-blind, so measured gains are a floor); tune `MODIFIER_WEIGHTS`,
  `TYPICAL_WORD_POINTS`, `WILD_OFFER_VALUE`.
