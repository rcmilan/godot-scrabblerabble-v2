# Daily Seed / Challenge Run — Design Spec

Implements issue #14.

## Summary

A **Daily Challenge** mode: every player on a given UTC date gets the identical
tile draws, premium layout, and upgrade offers, plays a single scored run, and
gets a shareable result string. Seed is derived from the date — no server, no
backend.

The enabling change is bigger than the mode itself: **all live gameplay
randomness moves from the global RNG to one seeded
`RandomNumberGenerator` owned by `RunState`** (`RunState.rng`). The daily mode
then just fixes that seed from the date; every other mode seeds it randomly and
plays exactly as today. This is also the shared dependency issue #21 (async
duel) builds on.

Determinism claim, stated precisely: **same seed + same player actions → same
draws, offers, and premiums.** Two players' runs diverge once their choices
differ (placements change refill counts, discards consume draws) — that is
inherent and fine; the daily guarantees identical *starting conditions and
identical response to identical play*, the same guarantee the sim makes.

## Background — why it fits this way

- The sim already proves the whole game is seed-deterministic
  (`simulator.gd::run_batch`, TC2 draw determinism, TC18 premium determinism,
  TSM11 offer determinism). The live game is the only unseeded half.
- Wildcard resolution (`_resolve_wildcards`), modifier promotion
  (`_ensure_modifier_count_in_rack` — always lowest-value tile), and scoring
  are already RNG-free, so they need no change.
- **`rack._ready()` refills before `main._ready()` runs** (child `_ready`
  first — CLAUDE.md quirk). Seeding therefore cannot live in
  `RunState.reset()` (called from `main._ready`, *after* the first 7 draws):
  it must happen before the main scene instantiates. `RunState` is an
  autoload, alive on the start screen — seed there.
- No scoring or constant changes anywhere, so `game_core.gd` is untouched and
  sim parity risk is ~zero.

## 1. Seeded run RNG — `scripts/run_state.gd`

```gdscript
var rng := RandomNumberGenerator.new()
var daily_date: String = ""   # "YYYY-MM-DD" (UTC) while mode == DAILY

static func daily_seed_for(date_utc: String) -> int:
    return hash("scrabblerabble-daily-%s" % date_utc)

func prepare_run() -> void:
    if mode == Mode.DAILY:
        daily_date = Time.get_date_string_from_system(true)  # true = UTC
        rng.seed = daily_seed_for(daily_date)
        print("[RunState] daily run — %s, seed %d" % [daily_date, rng.seed])
    else:
        daily_date = ""
        rng.randomize()
```

`daily_seed_for` is `static` on purpose: GDScript's `String.hash()` is a fixed
algorithm (stable across sessions and platforms), and a static func can be
unit-tested headless via `preload("res://scripts/run_state.gd")` without the
autoload existing.

**Call sites for `prepare_run()`** — every path that leads into
`main.tscn`, always *before* the scene change:

- `start_screen.gd::_on_mode_selected` — after `RunState.mode = mode`.
- `game_over_dialog.gd::_on_restart` — before `reload_current_scene()`
  (non-daily only; daily has no restart, see §4).

`reset()` does **not** touch `rng` — by the time it runs, the rack has
already drawn.

Optional verification hook: honor a `--seed=N` user arg in `prepare_run()`
(via `OS.get_cmdline_user_args()`, the same parsing the sim uses) that forces
`rng.seed = N` in any mode. Pairs with `--autoplay` for the determinism check
in §7.

## 2. RNG call-site migration — the mirror-image of the sim rule

The sim's rule is "never global `randi()`, always `core.rng`". The live game
now adopts the same rule: **gameplay randomness goes through `RunState.rng`;
global RNG is for cosmetics only.**

| Site | Today | Change |
|------|-------|--------|
| `rack.gd::_draw_random_letter` (`bag[randi() % ...]`) | global | `RunState.rng.randi() % bag.size()` |
| `rack.gd::_draw_random_letter_excluding` | global | same |
| `main.gd::_roll_modifier` (`randi() % total`) | global | `RunState.rng.randi() % total` |
| `main.gd::_generate_upgrade_offers` (letter pick) | global | `RunState.rng.randi() % pool.size()` |
| `board.gd::reroll_premiums` (`positions.shuffle()`) | global | hand-rolled Fisher–Yates on `RunState.rng` — copy the loop from `game_core.gd::_reroll_premiums`, which exists for exactly this reason (`Array.shuffle()` is global-RNG-bound) |
| `main.gd::_ready` `randomize()` | seeds global RNG | **delete** — the global RNG no longer feeds gameplay |
| `start_screen.gd::_set_random_subtitle` (`pick_random`) | global | **keep** — cosmetic, pre-run, must not consume run draws |
| `main.gd` Autoplay inner class (`rng.randomize()`) | own RNG | keep its own RNG, but seed it from `RunState.rng.randi()` when a forced `--seed` is active, so autoplay decisions replay too (verification aid; default behavior unchanged) |

Draw *order* across nodes is fixed by tree order (`rack._ready` refill →
`main._ready` `reroll_premiums`), so it is deterministic per build without
further work. Anyone adding a new gameplay RNG consumer must use
`RunState.rng` — this rule goes into CLAUDE.md (§6).

## 3. Mode plumbing — `scripts/run_state.gd`

- `enum Mode { EASY, MEDIUM, HARD, ENDLESS, DAILY }` (appended last).
- `is_difficulty_mode()` becomes `return DIFFICULTY_TARGETS.has(mode)` — the
  current `mode != Mode.ENDLESS` would misclassify DAILY. Every existing
  `else`-branch (Endless target curve, endless loss path) then serves DAILY
  automatically.
- `mode_name()` gains `"Daily"`.
- **Daily plays the Endless ruleset** (escalating `ENDLESS_GROWTH` curve,
  run ends on a missed target). Rationale: Endless is the branch the sim
  models, and it avoids the live-only `DIFFICULTY_TARGETS` tables — the run's
  result is naturally `total_score` + round reached, which is what the share
  card reports. (Resolves the issue's "which mode?" open question.)
- On the endless-style loss path in `register_turn_score`, when
  `mode == Mode.DAILY`, finalize the attempt record (§5) before emitting
  `game_over`.

## 4. UI

**Start screen (`scenes/start_screen.tscn` / `start_screen.gd`).** A
`DailyButton` in `MenuButtons` between Endless and Quit, labeled
`Daily — <YYYY-MM-DD>`. If today's attempt exists (§5), the button is
disabled and shows the result instead (`Daily — 287 pts`), Win95-style
(disabled buttons already render correctly via the theme). Otherwise it
launches `Mode.DAILY` through the existing `_on_mode_selected` path.

**Share dialog (`scenes/daily_share_dialog.tscn` +
`scripts/daily_share_dialog.gd` — new files, justified: no existing dialog
fits).** Shown by `main.gd::_on_game_over` *instead of* the standard game-over
dialog when `mode == Mode.DAILY`, on the same CanvasLayer (`50`, below the
CRT). Mirrors `scenes/game_over_dialog.tscn` chrome exactly (`WindowFrame` →
`InnerVBox` → `TitleBar` with `-`/`O`/`X` → `BodyArea`). Body: date, score,
round reached, the share text in a read-only field, and a button row:

- **Copy Result** (`PlayButton` variation — the primary action) →
  `DisplayServer.clipboard_set(share_text)`.
- **OK** → back to title (`RunState.reset()` + change scene to
  `start_screen.tscn`), same as the `X` button.
- **No Restart** — one attempt per day. (Practice replays: deferred, see
  open questions.)

Share string — reveals outcome, not the board:

```
ScrabbleRabble 95 — Daily 2026-07-14
Score 287 · Round 5
🟩🟩🟩🟩🟥
```

One green square per round cleared (`RunState.history.size()`), one red for
the failed round. Built by a pure `static func build_share_text(date, score,
rounds_cleared) -> String` so it's unit-testable headless.

## 5. One attempt per day — persistence

`ConfigFile` at `user://daily.cfg`, one section per date:

```ini
[2026-07-14]
state = "done"        ; "started" | "done"
score = 287
round = 5
```

(The CLAUDE.md `user://` warning is specific to headless sim runs; the live
game's `user://` is fine — the issue says the same.)

Owned by `RunState` (no new autoload): `has_daily_attempt(date) -> bool`,
`start_daily_attempt()`, `finish_daily_attempt(score, round)`.

- `start_daily_attempt()` writes `state = "started"` from `prepare_run()` —
  the attempt is **consumed at launch**, so quitting mid-run doesn't grant a
  retry. An abandoned run reads back as score 0 / DNF.
- `finish_daily_attempt()` overwrites with the final result from the loss
  path (§3).
- Start screen reads `has_daily_attempt(today)` to gate the button.

Reset boundary is **UTC midnight** (matches the seed derivation; resolves the
issue's open question — a wall-clock-local reset would let travelers replay a
seed).

## 6. Docs

- **CLAUDE.md** — "Game state": `RunState` now owns the run RNG; add the
  rule *"gameplay randomness goes through `RunState.rng` — never global
  `randi()`/`shuffle()` in gameplay code (mirror of the sim's seeding rule)"*
  and a short Daily-mode note (seed = UTC date, one attempt, Endless
  ruleset). Update the `enum Mode` mention.
- **`scripts/sim/README.md`** — one line noting the live game is now seeded
  the same way (relevant to future live↔sim replay work for #21).

## Sim parity

**No scoring, progression, draw-logic, or constant changes** — `game_core.gd`
is untouched and all existing TC/TSM expectations stand. Run
`run_tests.gd` anyway to confirm nothing drifted.

Live↔sim *exact replay* of a daily seed is explicitly **not** a v1 claim:
live and sim consume RNG in different orders (rack refill vs `_init_board`,
human turns vs strategies), so the same seed produces different streams. The
v1 guarantee is **live↔live** determinism (§7). Aligning draw order for true
cross-replay is follow-up work under issue #21, where it actually matters.

## Sequencing

1. `run_state.gd`: `rng`, `prepare_run()`, `daily_seed_for()`, Mode.DAILY,
   `is_difficulty_mode()` fix, `mode_name()`.
2. RNG migration (§2 table) — the game is now seedable but plays identically.
3. Verify determinism via §7's autoplay diff **before** building UI on top.
4. Daily persistence (§5) + loss-path finalize hook.
5. UI: start-screen button, share dialog, share-text builder.
6. CLAUDE.md + sim README.

## Verification

- `godot --headless --path . --script res://scripts/sim/tests/run_tests.gd`
  — all existing tests still green (nothing in `scripts/sim/` changes).
- **Determinism check:** run
  `godot --path . -- --autoplay --seed=42` twice; grep both logs and diff
  the draw-dependent lines (rack letters on refill, `[Board] premiums
  rerolled`, upgrade offers, `[Turn]` scores). Identical output = the
  migration is complete; any divergence means a call site was missed.
- Live daily flow: pick Daily → note first rack + premium layout → quit →
  relaunch → button is disabled with the result shown. Delete
  `user://daily.cfg`, replay the same date → identical first rack/premiums.
- Copy Result puts the exact share string on the OS clipboard.
- If Godot isn't runnable in the agent environment: hand-trace the §2 table
  against every `randi`/`shuffle`/`pick_random` grep hit, and state plainly
  that the runtime checks were not executed.

## Risks / notes

- **A missed call site is silent.** Nothing crashes if some path still uses
  the global RNG — the daily just quietly stops being fair. The §7 autoplay
  diff is the guard; re-run it whenever a new random feature lands. The
  CLAUDE.md rule (§6) is the long-term defense.
- **New draws added later shift the daily stream** (same trap as the sim's
  "don't compare against historical CSVs" note). Harmless — each date is
  self-consistent — but two builds of the game can disagree on a given
  date's draws, so duels (#21) must eventually carry a version tag in the
  challenge code.
- `hash()` stability matters: if a Godot upgrade ever changed `String.hash()`,
  every date's seed would change. Acceptable (each date stays internally
  consistent); the unit test on `daily_seed_for` pins the current value so a
  change is at least noticed.
- One-attempt enforcement is local-trust (deleting `user://daily.cfg` resets
  it) — explicitly fine per the issue; anti-cheat is out of scope.

## Acceptance criteria (from issue #14)

- [ ] Same date → identical run for all players (verified by replaying a seed).
- [ ] One attempt/day enforced locally.
- [ ] Shareable summary generated; does not reveal the board solution.
- [ ] Start screen entry point added in Win95 style.

## Open questions (carried / resolved)

- **Which ruleset?** Resolved: Endless curve (§3).
- **Reset boundary?** Resolved: UTC midnight (§5).
- **Practice replays after the scored attempt?** Deferred — v1 is one
  attempt, period. If added later, a practice run must re-seed
  (`rng.randomize()`) so it can't be used to scout the daily board… which it
  still could, by replaying the date's seed. Needs real design; not v1.
