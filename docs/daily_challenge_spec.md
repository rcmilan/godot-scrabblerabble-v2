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

## Baseline — which tree this spec targets

**This spec is written against the tile-modifiers-v2 codebase** (premium
cells #24 + word multipliers/wildcards #25 — the code CLAUDE.md documents).
At the time of writing, `main` is at `e5cedcc` and does **not** contain those
two commits; they live on `claude/repo-issues-roi-analysis-e5fb51`. Every
file/line reference below (e.g. `main.gd::_roll_modifier`,
`board.gd::reroll_premiums`) refers to the v2 tree and does not exist on
current `main`.

**Implementation must happen on top of the v2 tree.** If #24/#25 have not
been merged to `main` by then, rebase this feature branch onto the branch that
carries them first. Implementing against pre-v2 `main` would migrate a
*different* (smaller) set of RNG call sites — the v1 `_generate_upgrade_offers`
rolls `randi()` twice inline and there is no premium shuffle — and the daily
would silently miss the premium/wildcard streams when the trees merge. The
§"RNG call-site migration" table is the v2 inventory; re-run the audit grep
(§Verification) after any rebase.

## Background — why it fits this way

- The sim already proves the whole game is seed-deterministic
  (`simulator.gd::run_batch`, TC2 draw determinism, TC18 premium determinism,
  TSM11 offer determinism). The live game is the only unseeded half.
- Wildcard resolution (`_resolve_wildcards` — tries all 26, strict `>`, ties
  alphabetical), modifier promotion (`_ensure_modifier_count_in_rack` — always
  lowest-value tile), and scoring are already RNG-free, so they need no
  change. The autoplay upgrade pick (`_offer_value` argmax, first-wins tie) is
  likewise deterministic.
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
var daily_date: String = ""     # "YYYY-MM-DD" (UTC) while mode == DAILY
var _run_prepared: bool = false

static func daily_seed_for(date_utc: String) -> int:
    return hash("scrabblerabble-daily-%s" % date_utc)

func prepare_run() -> void:
    _run_prepared = true
    var forced := _forced_seed_arg()   # --seed=N, any mode (verification)
    if mode == Mode.DAILY:
        daily_date = Time.get_date_string_from_system(true)  # true = UTC
        rng.seed = daily_seed_for(daily_date) if forced == 0 else forced
        start_daily_attempt()
    else:
        daily_date = ""
        if forced != 0:
            rng.seed = forced
        else:
            rng.randomize()
    print("[RunState] run seed %d — %s%s" % [rng.seed, mode_name(),
        " (forced)" if forced != 0 else ""])
```

The seed log line is load-bearing: it is the anchor of the determinism diff
(§Verification) and the value a bug report needs to reproduce a run.

`daily_seed_for` is `static` on purpose: GDScript's `String.hash()` is a fixed
algorithm (stable across sessions and platforms), and a static func is
callable headless via `load("res://scripts/run_state.gd")` **without the
autoload existing** — which is how the test harness reaches it (§5).
`run_state.gd` is not scene-coupled (no `$` paths, no `_ready` dependencies),
so loading it from sim tests is safe under CLAUDE.md's "don't import
scene-coupled scripts" rule.

**Call sites for `prepare_run()`** — every path that leads into
`main.tscn`, always *before* the scene change:

- `start_screen.gd::_on_mode_selected` — after `RunState.mode = mode`.
- `game_over_dialog.gd::_on_restart` — before `reload_current_scene()`
  (non-daily only; daily has no restart, see §4).

**Fallback guard.** Launching `scenes/main.tscn` directly from the editor
(F6) skips the start screen, so `prepare_run()` never ran and the first rack
was drawn from an unseeded RNG. `reset()` (which every entry into `main.tscn`
does call) detects and self-heals:

```gdscript
# in reset(), before anything else:
if not _run_prepared:
    print("[RunState] prepare_run fallback — direct scene launch?")
    prepare_run()
_run_prepared = false
```

The fallback run is *not* draw-for-draw deterministic (the pre-reset rack
draws already consumed an unseeded stream) — acceptable for a dev-only flow,
and the log line makes it diagnosable. Player-facing entry points all go
through the start screen or restart, which seed correctly.

`reset()` does **not** touch `rng` beyond this guard.

`_forced_seed_arg()` parses `--seed=N` from `OS.get_cmdline_user_args()`
(NOT `get_cmdline_args()` — same trap as the sim runner, per CLAUDE.md),
returning 0 when absent.

## 2. RNG call-site migration — the mirror-image of the sim rule

The sim's rule is "never global `randi()`, always `core.rng`". The live game
now adopts the same rule: **gameplay randomness goes through `RunState.rng`;
global RNG is for cosmetics only.**

Complete v2 inventory (from `grep -rn "randi\|randf\|shuffle\|pick_random"
scripts/ --include="*.gd"` excluding `scripts/sim/`):

| Site | Today | Change |
|------|-------|--------|
| `rack.gd::_draw_random_letter` (`bag[randi() % ...]`) | global | `RunState.rng.randi() % bag.size()` |
| `rack.gd::_draw_random_letter_excluding` | global | same |
| `main.gd::_roll_modifier` (`randi() % total`) | global | `RunState.rng.randi() % total` |
| `main.gd::_generate_upgrade_offers` (letter pick) | global | `RunState.rng.randi() % pool.size()` |
| `board.gd::reroll_premiums` (`positions.shuffle()`) | global | hand-rolled Fisher–Yates on `RunState.rng` — copy the loop from `game_core.gd::_reroll_premiums`, which exists for exactly this reason (`Array.shuffle()` is global-RNG-bound) |
| `main.gd::_ready` `randomize()` | seeds global RNG | **delete** — the global RNG no longer feeds gameplay |
| `start_screen.gd::_set_random_subtitle` (`pick_random`) | global | **keep** — cosmetic, runs pre-`prepare_run()`, must not consume run draws |
| `main.gd::_AutoplayAdapter._init` (`rng.randomize()`) | own RNG | seed from `RunState.rng.randi()` instead — one extra run-stream draw, consumed identically on every autoplay run, and it makes strategy tie-breaks (`word_search`/`hybrid` use `core.rng`) replayable. Autoplay never runs alongside a human, so human runs are unaffected |

Draw *order* across nodes is fixed by tree order (`rack._ready` refill →
`main._ready` `reroll_premiums`), so it is deterministic per build without
further work. GPU-side randomness (`GPUParticles2D` glitter) and tweens never
touch Godot's RNG streams — no leak there. Anyone adding a new gameplay RNG
consumer must use `RunState.rng` — this rule goes into CLAUDE.md (§7).

## 3. Mode plumbing — `scripts/run_state.gd`

- `enum Mode { EASY, MEDIUM, HARD, ENDLESS, DAILY }` (appended last).
- `is_difficulty_mode()` becomes `return DIFFICULTY_TARGETS.has(mode)` — the
  current `mode != Mode.ENDLESS` would misclassify DAILY. Every existing
  `else`-branch (Endless target curve in `reset()`/`_advance_round`, the
  endless loss path in `register_turn_score`, the HUD's round string) then
  serves DAILY automatically, with **no new branches in progression logic**.
- `mode_name()` gains `"Daily"`.
- **Daily plays the Endless ruleset** (escalating `ENDLESS_GROWTH` curve,
  run ends on a missed target). Rationale: Endless is the branch the sim
  models, and it avoids the live-only `DIFFICULTY_TARGETS` tables — the run's
  result is naturally `total_score` + round reached, which is what the share
  card reports. (Resolves the issue's "which mode?" open question.)
- On the endless-style loss path in `register_turn_score`, when
  `mode == Mode.DAILY`, call `finish_daily_attempt(total_score,
  current_round)` **before** emitting `game_over` — the handler tears things
  down and must find the record already final.

## 4. UI

**Start screen (`scenes/start_screen.tscn` / `start_screen.gd`).** A
`DailyButton` in `MenuButtons` between Endless and Quit, labeled
`Daily — <YYYY-MM-DD>`. If today's attempt exists (§5), the button is
disabled and shows the result instead (`Daily — 287 pts`), Win95-style
(disabled buttons already render correctly via the theme). Otherwise it
launches `Mode.DAILY` through the existing `_on_mode_selected` path (which
also disables it during the launch glitch, alongside the other five buttons).
`_maybe_autoplay` keeps launching ENDLESS — autoplay must never consume the
day's attempt.

**Share dialog (`scenes/daily_share_dialog.tscn` +
`scripts/daily_share_dialog.gd` — new files, justified: no existing dialog
fits).** Shown by `main.gd::_on_game_over` *instead of* the standard game-over
dialog when `mode == Mode.DAILY`. Reuse that handler's exact scaffolding: a
`CanvasLayer` at layer `50` (below the CRT at `100`), a full-rect
`ModalBlocker` Control with `MOUSE_FILTER_STOP`, and centering via
`custom_minimum_size` (`size` is still `(0,0)` pre-layout — CLAUDE.md quirk).
Chrome mirrors `scenes/game_over_dialog.tscn` (`WindowFrame` → `InnerVBox` →
`TitleBar` with `-`/`O`/`X` → `BodyArea`). Body: date, score, round reached,
the share text in a read-only field, and a button row:

- **Copy Result** (`PlayButton` variation — the primary action) →
  `DisplayServer.clipboard_set(share_text)`, logged as
  `[Daily] result copied`.
- **OK** → back to title (`RunState.reset()` + change scene to
  `start_screen.tscn`), same as the `X` button (Win95: X = the dialog's
  cancel path).
- **No Restart** — one attempt per day. (Practice replays: deferred, see
  open questions.)
- Autoplay interaction: `_on_game_over`'s autoplay branch
  (`autoplay_run_completed` + `_autoplay_quit_game_over`) must also cover the
  daily dialog — give it the same `_on_quit()` method name so the existing
  quit call works unchanged.

Share string — reveals outcome, not the board:

```
ScrabbleRabble 95 — Daily 2026-07-14
Score 287 · Round 5
🟩🟩🟩🟩🟥
```

One green square per round cleared (`RunState.history.size()`), one red for
the failed round. Built by `static func build_share_text(date: String,
score: int, rounds_cleared: int) -> String` in **`run_state.gd`**, not the
dialog script — the dialog script is scene-coupled (`$` paths) and therefore
off-limits to headless tests, while `run_state.gd` loads cleanly (§5). The
dialog just calls it.

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

Split into a **pure, path-injectable static layer** (testable headless) and
thin instance wrappers on `RunState` (no new autoload):

```gdscript
static func read_daily_attempt(path: String, date: String) -> Dictionary:
    # {} when absent; {"state": .., "score": .., "round": ..} when present.
    # A failed ConfigFile.load() (missing/corrupt file) reads as {} — the
    # player gets a fresh attempt rather than a crash or a lockout.

static func write_daily_attempt(path: String, date: String,
        state: String, score: int, round: int) -> void

const DAILY_SAVE_PATH := "user://daily.cfg"
func has_daily_attempt(date: String) -> bool   # wraps read, DAILY_SAVE_PATH
func start_daily_attempt() -> void             # state = "started", score 0
func finish_daily_attempt(score: int, round: int) -> void  # state = "done"
```

- `start_daily_attempt()` runs from `prepare_run()` — the attempt is
  **consumed at launch**, so quitting mid-run doesn't grant a retry. An
  abandoned run reads back as score 0 / DNF.
- `finish_daily_attempt()` overwrites with the final result from the loss
  path (§3). It writes to the section named by `daily_date` — *not* "today" —
  so a run that crosses UTC midnight finalizes the attempt it started, and
  the new date's attempt stays available. Log both transitions:
  `[Daily] attempt started — 2026-07-14` / `[Daily] attempt done — 287 pts,
  round 5`.
- Start screen reads `has_daily_attempt(today)` to gate the button.

Reset boundary is **UTC midnight** (matches the seed derivation; resolves the
issue's open question — a wall-clock-local reset would let travelers replay a
seed).

## 6. Determinism observability — the log surface

Today the log stream barely witnesses the RNG: refills log nothing, discard
logs only the outgoing letter, and `[Board] premiums rerolled — 8 cells`
prints a count without positions. A determinism diff over that surface would
pass even with missed call sites. **The migration ships with logs that make
every consumed draw observable** (this is the same philosophy as CLAUDE.md's
wildcard lesson: green tests didn't catch the bugs, reading logs did):

| Event | Log line (new/extended) |
|-------|------------------------|
| Run seeded | `[RunState] run seed %d — %s` (§1) |
| Rack refill | `[Rack] refill — EAITNSR` (letters in slot order, `?` for wild), end of `rack.gd::refill()` |
| Discard replacement | extend the existing `[Discard]` line to `[Discard] rack discard — Q → E, 2 left` |
| Premium reroll | extend to `[Board] premiums rerolled — dl@(3,1) dl@(0,6) … tw@(7,7)` |
| Upgrade offers | `[UpgradeWizard] offers — A×2x, E×w2x, ?` (before the dialog shows) |

`[Rack]` is a new prefix for a new subsystem (allowed by CLAUDE.md's logging
convention). Wildcard resolution already logs `[Wild] resolved`; turn scoring
already logs `[Turn]`. Together these lines are the **canonical diff surface**:

```
grep -E '^\[(RunState|Rack|Discard|Board|UpgradeWizard|Wild|Turn)\]' game.log
```

Two runs with the same seed and same actions must produce identical output
from that grep. Any divergence = a missed or reordered RNG call site.

## 7. Docs

- **CLAUDE.md** — "Game state": `RunState` now owns the run RNG; add the
  rule *"gameplay randomness goes through `RunState.rng` — never global
  `randi()`/`shuffle()`/`pick_random()` in gameplay code (mirror of the
  sim's seeding rule); cosmetic pre-run randomness (start-screen subtitle)
  is the only exemption"* and a short Daily-mode note (seed = UTC date, one
  attempt, Endless ruleset, `user://daily.cfg`). Update the `enum Mode`
  mention and the log-prefix list (`[Rack]`, `[Daily]`).
- **`scripts/sim/README.md`** — one line noting the live game is now seeded
  the same way (relevant to future live↔sim replay work for #21).

## Sim parity

**No scoring, progression, draw-logic, or constant changes** — `game_core.gd`
is untouched and all existing TC/TSM expectations stand. Run
`run_tests.gd` anyway to confirm nothing drifted.

Live↔sim *exact replay* of a daily seed is explicitly **not** a v1 claim:
live and sim consume RNG in different orders (rack refill vs `_init_board`,
human turns vs strategies), so the same seed produces different streams. The
v1 guarantee is **live↔live** determinism (§6, §Verification). Aligning draw
order for true cross-replay is follow-up work under issue #21, where it
actually matters.

## Tests — `scripts/sim/tests/test_daily.gd`

**Registration is manual:** `run_tests.gd` loads a hardcoded file list — add
`_run_test_file("res://scripts/sim/tests/test_daily.gd")` alongside the four
existing entries, or the file silently never runs. Methods are then
auto-discovered by the `test_` prefix; follow the existing convention
(`push_error` with the case ID + `return false` on failure).

The test file loads `run_state.gd` as a plain script — **never via the
autoload**, which doesn't exist under `--script` (CLAUDE.md headless
pitfall): `var RS := load("res://scripts/run_state.gd")`, then call the
statics. Do not load `daily_share_dialog.gd` (scene-coupled).

| Test | What it pins | Expected |
|------|--------------|----------|
| TD1 — seed pin | `daily_seed_for` stability across Godot versions/platforms | `RS.daily_seed_for("2026-01-01")` equals a constant recorded at implementation time; two different dates → different seeds; same date twice → same seed |
| TD2 — share text golden | exact share-string format | `build_share_text("2026-07-14", 287, 4)` == the 3-line string with 4 🟩 + 1 🟥 |
| TD3 — share text edges | degenerate runs | `rounds_cleared == 0` → single 🟥; text contains score and date verbatim |
| TD4 — persistence round-trip | read/write symmetry, path-injected | write `started` → read back `{state: "started", score: 0}`; write `done`/287/5 → read back matches; a date never written → `{}` |
| TD5 — corrupt/missing store | no crash, fail-open | reading from a nonexistent path → `{}`; reading a file with garbage bytes → `{}` |

TD4/TD5 use a **relative scratch path** (`./sim_results/test_daily.cfg` —
`sim_results/` is gitignored and `DirAccess.make_dir_absolute()`-created,
exactly like the results writer), never `user://`, which is unreliable
headless. Clean up the file at test end.

What deliberately has **no unit test**: the RNG migration itself. Its guard
is the live determinism check below — a unit test can't see whether *live*
`rack.gd` still calls global `randi()`.

## Sequencing

0. **Confirm the baseline**: the working tree must contain #24/#25 (check
   for `board.gd::reroll_premiums`). Rebase first if not (§Baseline).
1. `run_state.gd`: `rng`, `prepare_run()` (+ fallback guard, `--seed`),
   `daily_seed_for()`, Mode.DAILY, `is_difficulty_mode()` fix, `mode_name()`.
2. RNG migration (§2 table) + observability logs (§6) — the game is now
   seedable but plays identically.
3. `test_daily.gd` TD1 (+ registration in `run_tests.gd`); run the
   determinism check (§Verification) **before building UI on top** — this is
   the point where a missed call site is cheapest to find.
4. Daily persistence (§5) + loss-path finalize hook (§3) + TD2–TD5.
5. UI: start-screen button, share dialog, share-text builder.
6. CLAUDE.md + sim README.

## Verification

- **Audit grep** (repeat after any rebase/merge):
  `grep -rn "randi\|randf\|shuffle\|pick_random\|randomize" scripts/ --include="*.gd" | grep -v "scripts/sim/" | grep -v "RunState.rng"`
  — the only survivors must be the start-screen subtitle and the RNG member
  declarations themselves.
- `godot --headless --path . --script res://scripts/sim/tests/run_tests.gd`
  — all existing tests still green, TD1–TD5 pass.
- **Live determinism check** (the core guarantee):
  ```
  godot --headless --path . -- --autoplay=word_search --seed=42 > a.log 2>&1
  godot --headless --path . -- --autoplay=word_search --seed=42 > b.log 2>&1
  diff <(grep -E '^\[(RunState|Rack|Discard|Board|UpgradeWizard|Wild|Turn)\]' a.log) \
       <(grep -E '^\[(RunState|Rack|Discard|Board|UpgradeWizard|Wild|Turn)\]' b.log)
  ```
  Empty diff = migration complete. Any divergence names the subsystem via its
  prefix. (Headless runs of the full game may emit `GPUParticles`/audio
  warnings — harmless; the grep filters them out.) `discard_word_search` as a
  second strategy also exercises the discard-replacement draw path.
- Live daily flow: pick Daily → note the `[RunState] run seed` line, first
  `[Rack] refill`, and `[Board] premiums rerolled` positions → quit →
  relaunch → button is disabled with the result shown. Delete
  `user://daily.cfg`, replay the same date → identical seed line, rack, and
  premium positions.
- Copy Result puts the exact share string on the OS clipboard.
- If Godot isn't runnable in the agent environment: hand-trace the §2 table
  against the audit grep's output, hand-compute TD1–TD3 expectations, and
  **state plainly that the runtime checks were not executed** (CLAUDE.md
  harness rule) — the determinism diff then becomes the user's
  pre-merge gate.

## Risks / notes

- **A missed call site is silent.** Nothing crashes if some path still uses
  the global RNG — the daily just quietly stops being fair. Three layered
  guards: the audit grep (static), the log surface (§6, observable), and the
  autoplay diff (behavioral). Re-run all three whenever a new random feature
  lands; the CLAUDE.md rule (§7) is the long-term defense.
- **Baseline skew is the top integration risk**: `main` currently lacks
  #24/#25, and a merge that resolves the two `_generate_upgrade_offers`
  versions wrong would reintroduce a global `randi()`. The audit grep is the
  cheap post-merge check.
- **New draws added later shift the daily stream** (same trap as the sim's
  "don't compare against historical CSVs" note). Harmless — each date is
  self-consistent — but two builds of the game can disagree on a given
  date's draws, so duels (#21) must eventually carry a version tag in the
  challenge code.
- `hash()` stability matters: if a Godot upgrade ever changed `String.hash()`,
  every date's seed would change. Acceptable (each date stays internally
  consistent); TD1 pins the current value so a change is at least noticed at
  upgrade time rather than discovered by players.
- **Direct-scene launches are not deterministic** (editor F6 — §1 fallback
  guard). Fine for dev; the fallback log line marks such runs as
  non-canonical.
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
