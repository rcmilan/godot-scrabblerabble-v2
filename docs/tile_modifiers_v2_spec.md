# Tile Modifiers v2 — Word Multipliers & Wildcards

Design spec for issue #12. Extends the per-letter modifier system
(`MOD_2X` / `MOD_3X`) with two new tile modifier types.

## 0. Scope decisions

Issue #12 proposed three modifiers. Two ship; one is dropped.

| Modifier | Status | Why |
| --- | --- | --- |
| Word multiplier (`MOD_WORD_2X` / `MOD_WORD_3X`) | **In** | Multiplies the whole scored run. Fits the existing modifier plumbing almost exactly. |
| Wildcard / blank (`MOD_WILD`) | **In** | Placeable as any letter, scores 0, still satisfies the dictionary. |
| Frozen | **Cut** | Incoherent with this game's lock model — see below. |

**Why frozen is cut.** The issue asks for a tile that "cannot be
returned/moved for one turn... then thaw", with the acceptance criterion
"frozen tiles reject all four return routes for their duration, then become
movable." In this game *every* pending tile locks at PLAY
(`board_cell.gd::lock_pending`) and a locked tile never moves again. So a
frozen tile is immovable during its turn, then immovable forever — the thaw
can never be observed and the modifier has no effect a player could detect.
Making it coherent needs a design that doesn't exist yet (a thawing tile that
survives the turn *unlocked*, which fights `pending_cells`, scoring, and
refill). Out of scope; reopen with a real design.

## 1. Constants

Mirrored **byte-identically** in `scripts/game_data.gd` and
`scripts/sim/game_core.gd` (sim-parity rule, CLAUDE.md):

```gdscript
const MOD_WORD_2X: String = "w2x"
const MOD_WORD_3X: String = "w3x"
const MOD_WILD:    String = "wild"
```

A tile carries exactly **one** modifier string. A wildcard is therefore never
also a word multiplier — the existing binary rule in
`_ensure_modifier_count_in_rack` ("a tile with ANY modifier is ineligible —
never stack") already enforces this and needs no change.

## 2. Scoring order

The full chain, extending the premium-cell order already documented in
CLAUDE.md. **Identical in `main.gd::_score_word` and
`game_core.gd::_score_word_sim`.**

Per letter:
1. base `LETTER_POINTS`
2. **if the tile is `MOD_WILD` → `letter_pts = 0`** (before any multiplier;
   a blank is worth nothing no matter what it sits on)
3. tile letter modifier: `MOD_2X` ×2 / `MOD_3X` ×3
4. cell letter premium: `PREM_DL` ×2 / `PREM_TL` ×3

Then, once per word:
5. sum the letters
6. × `WORD_BONUS_MULTIPLIER` (2)
7. × cell word premiums: `PREM_DW` ×2 / `PREM_TW` ×3
8. **× tile word modifiers: `MOD_WORD_2X` ×2 / `MOD_WORD_3X` ×3**

**Stacked word multipliers multiply** (issue's recommendation, matches
Scrabble): two `MOD_WORD_2X` tiles in one run → ×4. Word-mult tiles and
DW/TW premium cells multiply together into the same `word_mult` accumulator.

Implementation is a two-line addition to the existing per-letter loop —
`word_mult` already exists for DW/TW:

```gdscript
if mod == GameData.MOD_WILD:
    letter_pts = 0
elif mod == GameData.MOD_2X:
    letter_pts *= 2
elif mod == GameData.MOD_3X:
    letter_pts *= 3
elif mod == GameData.MOD_WORD_2X:
    word_mult *= 2
elif mod == GameData.MOD_WORD_3X:
    word_mult *= 3
```

**Score == highlight is preserved for free.** Both still flow from
`_collect_scoring_words()`; a wildcard's *chosen* letter is a real letter on
the board, so `_board_runs()` sees it and the word forms normally. A wild
changes points, not word membership. **No highlight code changes.**

## 3. Wildcards

### 3a. Acquisition — the upgrade wizard, stored in `modifier_build`

The wizard may offer a **wildcard card** (`{"letter": "?", "modifier":
MOD_WILD}`). Picking it calls `RunState.add_to_build(MOD_WILD)` rather than
`set_letter_modifier` — a wildcard isn't bound to a letter.

This reuses machinery that already exists and is currently dead in the live
game: `modifier_build` is a `{mod: count}` dict, and
`rack.gd::_ensure_modifier_count_in_rack(mod, n)` already means exactly
"guarantee n tiles carrying mod in the rack after every refill". `add_to_build`
gains its first live caller. Nothing new is invented, and the sim already
threads `modifier_build` through `GameCore.new(seed, build)`.

At most **one** wildcard offer per wizard (guard in the offer generator) — a
wizard showing three "?" cards would be a dead end.

### 3b. Rack representation

A promoted wildcard keeps whatever letter it drew; the letter is simply
ignored. `tile.gd::_refresh_visual` displays `?` and `0` instead of the
letter and its points. `rack.gd::find_tile_with_letter` **skips wild tiles**,
so keyboard-placing `E` never silently consumes the blank.

### 3c. Letter resolution — auto-pick, recomputed live

A wildcard's letter is chosen automatically: **the letter A–Z that maximizes
the whole-board score, ties broken alphabetically.** Deterministic, no RNG.

Resolution runs in `_resolve_wildcards()`, which iterates every **pending**
(unlocked) wild cell in board-scan order (x, then y) and, for each, tries all
26 letters against the current board, keeping the best. Multiple wildcards are
resolved greedily one at a time in that fixed order.

> `ponytail:` greedy per-wild, not a joint 26ⁿ search. Two blanks in one turn
> can theoretically miss a better pair. Board is 8×8 and a turn places ≤ 8
> tiles — swap in an exhaustive search only if a sim run shows it matters.

**Call sites, and why they agree:**

- **Live:** at the top of `main.gd::_update_hud()`, which already runs after
  every board/rack mutation. So the "?" resolves the instant it can form a
  word, the rainbow highlight previews it truthfully, and the displayed score
  is the real one. A **locked** wild is never re-resolved (`current_tile ==
  null`), so its letter is frozen at lock.
- **Sim:** at the top of `game_core.gd::end_turn()`, before
  `_calculate_turn_score`.

These converge on the same answer: live re-resolves after every placement, and
the *last* of those sees exactly the final board that the sim's single
end-of-turn pass sees. Same board, same fixed iteration order, same greedy
loop → same letters.

## 4. Word multipliers

### 4a. Acquisition — the upgrade wizard, via `letter_modifiers`

Offered exactly like `MOD_2X` / `MOD_3X`: pick a letter, and every tile of
that letter carries the modifier for the rest of the run ("every E is a
×2-word tile"). `letter_modifiers[letter] = MOD_WORD_2X` — zero new plumbing;
`_apply_rack_modifiers` already applies it.

### 4b. Offer roll

`_generate_upgrade_offers` currently rolls `MOD_3X if randi() % 3 == 0 else
MOD_2X`. Replace with a weighted table, mirrored live and sim:

```gdscript
const MODIFIER_WEIGHTS := {
    MOD_2X: 40, MOD_3X: 20, MOD_WORD_2X: 20, MOD_WORD_3X: 10, MOD_WILD: 10,
}
```

> `ponytail:` first-guess weights. Retune with the simulator alongside
> `INITIAL_TARGET_SCORE` if word-mults dominate every run.

### 4c. Auto-pick heuristic (`_offer_value`, autoplay + sim)

The current formula is `LETTER_DISTRIBUTION × LETTER_POINTS × mult`, which
can't compare a word-mult to a letter-mult (a ×2 on a 1-point `E` adds 1
point; a ×2 on the *word* adds ~12). Switch every branch to **marginal points
gained**, `(mult - 1)`:

```gdscript
const TYPICAL_WORD_POINTS: int = 12   # ponytail: rough mean scored-word value
const WILD_OFFER_VALUE:    int = 60   # ponytail: flat; a blank has no letter to weight

func _offer_value(offer: Dictionary) -> int:
    var mod: String = offer["modifier"]
    if mod == MOD_WILD:
        return WILD_OFFER_VALUE
    var letter: String = offer["letter"]
    var dist: int = LETTER_DISTRIBUTION[letter]
    if mod == MOD_WORD_2X or mod == MOD_WORD_3X:
        var wm := 3 if mod == MOD_WORD_3X else 2
        return dist * TYPICAL_WORD_POINTS * (wm - 1)
    var lm := 3 if mod == MOD_3X else 2
    return dist * LETTER_POINTS[letter] * (lm - 1)
```

This **changes existing letter-mod ranking** (`3x` now scores 2× a `2x`
instead of 1.5×) — intended, and part of what the benchmark measures.

## 5. Visuals

`tile.gd::_draw` and `board_cell.gd::_draw` already switch on the modifier to
paint a gradient body. Two new gradient pairs, distinct from the existing
navy→sky (`2x`) and green (`3x`), plus a flat treatment for the blank:

```gdscript
const C_WORD2X_GRADIENT_LEFT  := Color(0.4,  0.0,  0.4,  1.0)   # purple
const C_WORD2X_GRADIENT_RIGHT := Color(0.72, 0.33, 0.72, 1.0)
const C_WORD3X_GRADIENT_LEFT  := Color(0.55, 0.27, 0.0,  1.0)   # amber
const C_WORD3X_GRADIENT_RIGHT := Color(1.0,  0.65, 0.0,  1.0)
const C_WILD_BODY             := Color(0.75, 0.75, 0.75, 1.0)   # flat silver
```

Word-mult tiles use `C_LABEL_MOD` (white) like the existing modified tiles. A
wildcard draws a flat silver body with the normal navy label showing `?`.

`UpgradeItem` instantiates a real `Tile`, so the wizard renders all new
modifiers for free. Only two spots need a wild-safe branch: the `"N in bag"`
line (`upgrade_item.gd::_draw`, meaningless for `?`) and the caption
(`upgrade_dialog.gd::_update_caption`, currently a hardcoded
`"double"`/`"triple"` ternary).

## 6. Sim parity

Everything above lands in **both** `main.gd` and `scripts/sim/game_core.gd`:
constants, `_score_word` / `_score_word_sim`, `_resolve_wildcards`,
`_generate_upgrade_offers`, `_offer_value`. Strategies stay
modifier-blind — they place a wildcard as an ordinary tile and `GameCore`
resolves it at `end_turn`, so the measured gain is a floor, not a ceiling.

`GameCore.end_turn`'s existing upgrade auto-pick must learn the wildcard
branch: a `MOD_WILD` offer increments `modifier_build[MOD_WILD]` instead of
writing `letter_modifiers`.

## 7. Tests (`scripts/sim/tests/test_game_core.gd`)

All expectations hand-computed against `data/words.txt`; `_zero_premiums(core)`
isolates the random premium layer.

| Test | Asserts |
| --- | --- |
| **TC20** | `MOD_WORD_2X` doubles the whole run; `MOD_WORD_3X` triples it. |
| **TC21** | Two word-mult tiles in one run **multiply** (×2 · ×2 = ×4). |
| **TC22** | A `MOD_WILD` tile scores **0** for its slot but the word still validates and scores. |
| **TC23** | A word-mult tile and a `PREM_DW` cell multiply together. |
| **TC24** | `_resolve_wildcards` picks the score-maximizing letter, alphabetical on ties, and is deterministic. |
| **TC25** | A locked wildcard is never re-resolved. |
| **TSM12** | `modifier_build[MOD_WILD] = n` guarantees n wild tiles in the rack after every refill. |
| **TSM13** | A `MOD_WILD` upgrade offer increments `modifier_build`, not `letter_modifiers`. |

**Existing tests that must be updated, not relaxed:** `TSM10` asserts
`letter_modifiers` values are `MOD_2X` or `MOD_3X` — widen to the new set.
`TSM11` (offer determinism) still holds. Any test pinning `_offer_value`
ranking needs recomputing against the `(mult - 1)` formula.

## 8. Expected fallout

- **Scores inflate again.** Word multipliers stack on the existing ×2 word
  bonus and DW/TW premiums, so `INITIAL_TARGET_SCORE` and `DIFFICULTY_TARGETS`
  need a fresh sweep — same method as the premium-cell retune (scale the
  *initial target*, never `ENDLESS_GROWTH`; see CLAUDE.md).
- **Per-seed sim results shift** vs. historical CSVs: the weighted modifier
  roll consumes rng draws differently. Determinism holds; cross-run
  comparison against old data does not.

## 9. Acceptance criteria (issue #12)

- [x] ~~Frozen tiles reject all four return routes~~ — **cut, see §0.**
- [ ] Each new modifier scores correctly including stacking order, verified by
      sim tests (TC20–TC23).
- [ ] Wildcard completes dictionary words and scores 0 for its slot (TC22).
- [ ] Every scoring tile glows; no scored-but-unlit or lit-but-unscored cells
      — structural, no highlight code touched (§2).
- [ ] `game_core.gd` parity confirmed by a green `run_tests.gd`.
